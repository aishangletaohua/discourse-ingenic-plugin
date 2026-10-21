# frozen_string_literal: true

module Ingenic
  # Turns the sparse per-version page rows into the complete document a reader
  # sees at one version.
  #
  # A version only stores the pages that were actually edited for it. Anything
  # untouched is inherited from the versions before it, so publishing a new
  # version does not mean duplicating the whole manual and then keeping every
  # copy in sync.
  #
  # Version order is the `position` column, lowest first, so moving a version
  # changes what inherits from what. Ties fall back to insertion order.
  #
  # There is no language dimension here. The resolver works on one product, and
  # a product is already one language's row in the catalogue; its versions and
  # pages cannot be written in another.
  class DocumentationResolver
    def initialize(product)
      @product = product
    end

    # Every version of the product, oldest first. There is no `published` flag on
    # a version to filter by — what a reader may see is decided page by page, and
    # a version with no pages of its own is not empty, it is the one before it.
    def versions
      @versions ||= product.versions.to_a.sort_by { |version| [version.position, version.id] }
    end

    # Every version that contributes to `version`, oldest first and including
    # the version itself.
    def chain_for(version)
      versions.select { |candidate| candidate.position <= version.position }
    end

    # The version's pages in reading order: depth-first, parents before their
    # children, each carrying the depth the tree renders at.
    #
    # `published_only: false` is for the management page, which has to show
    # drafts that a reader would not see.
    def effective_pages(version, published_only: true)
      build_tree(effective_rows(version, published_only: published_only))
    end

    # Folders never resolve as a page: an address that names one is a broken
    # link, not an empty document.
    def find_page(version, slug)
      effective_pages(version).find do |resolved|
        resolved.slug == slug && !resolved.folder?
      end
    end

    # Previous and next in the flattened reading order, so the theme can render
    # footer navigation without rebuilding the tree. Folders are skipped: a
    # reader stepping forward should land on an article.
    def navigation_for(version, page)
      flat = effective_pages(version).reject(&:folder?)
      index = flat.index { |resolved| resolved.slug == page.slug }

      {
        previous: index && index.positive? ? flat[index - 1] : nil,
        next: index && index < flat.length - 1 ? flat[index + 1] : nil,
      }
    end

    private

    attr_reader :product

    # Newest definition of each slug wins, so walking the chain oldest-first and
    # overwriting gives the inherited value for anything the target version left
    # alone.
    def effective_rows(version, published_only:)
      chain = chain_for(version)
      pages_by_version =
        chain.index_with do |source|
          readable_pages(source, published_only: published_only)
        end
      rows_by_id = pages_by_version.values.flatten.index_by(&:id)
      target_id = version.id

      resolved =
        chain.each_with_object({}) do |source, result|
          pages_by_version[source].each do |page|
            result[page.slug] = ResolvedPage.new(
              page,
              inherited_from: (source.id == target_id ? nil : source),
              parent_slug: parent_slug_for(page, rows_by_id),
            )
          end
        end

      # A folder taken down takes its section with it. Without this, its
      # published children lost their parent from the resolved set and
      # build_tree re-attached them at the top level — taking a folder down
      # published its articles, one level up.
      prune_taken_down_subtrees!(resolved) if published_only

      resolved
    end

    # A parent that exists but is not published is a section that was
    # withdrawn, not a missing row: readers see none of it. The management page
    # asks for drafts as well (published_only: false), so this only runs for a
    # reader.
    def prune_taken_down_subtrees!(rows)
      parent_ids = rows.each_value.filter_map { |resolved| resolved.page.parent_id }.uniq
      return if parent_ids.empty?

      published_parent_ids =
        IngenicDocPage.where(id: parent_ids, published: true).pluck(:id).to_set

      hidden =
        rows.each_value.filter_map do |resolved|
          parent_id = resolved.page.parent_id
          resolved.slug if parent_id && !published_parent_ids.include?(parent_id)
        end.to_set

      return if hidden.empty?

      # The children of a hidden row are hidden too, down the whole chain: it
      # is the section that was withdrawn, not one row of it.
      changed = true
      while changed
        changed = false

        rows.each_value do |resolved|
          next if hidden.include?(resolved.slug)
          next unless resolved.parent_slug && hidden.include?(resolved.parent_slug)

          hidden << resolved.slug
          changed = true
        end
      end

      hidden.each { |slug| rows.delete(slug) }
    end

    # A page can be defined in one version while its parent is only defined in
    # an earlier one, so the parent is resolved by identity first and by a plain
    # lookup second.
    def parent_slug_for(page, rows_by_id)
      return if page.parent_id.nil?

      (rows_by_id[page.parent_id] || page.parent)&.slug
    end

    def readable_pages(version, published_only:)
      scope = version.pages
      scope = scope.where(published: true) if published_only
      scope.to_a.sort_by { |page| [page.position, page.id] }
    end

    # A depth-ordered flat list is enough to render the tree, and it keeps the
    # navigation order and the sidebar order from drifting apart.
    def build_tree(rows)
      children_by_parent = Hash.new { |hash, key| hash[key] = [] }
      rows.each_value { |resolved| children_by_parent[resolved.parent_slug] << resolved }
      children_by_parent.each_value { |list| list.sort_by! { |page| [page.position, page.id] } }

      ordered = []
      seen = {}
      walk(children_by_parent, nil, 0, ordered, seen)

      # A page whose parent is missing from the resolved set is not reachable
      # from the root — the parent may have been deleted. Showing the page at
      # the top level beats dropping it silently. Unpublished parents never
      # reach this point: their whole subtree was pruned in effective_rows.
      rows.each_value do |resolved|
        next if seen[resolved.slug]

        resolved.depth = 0
        ordered << resolved
      end

      ordered
    end

    def walk(children_by_parent, parent_slug, depth, ordered, seen)
      children_by_parent[parent_slug].each do |resolved|
        next if seen[resolved.slug]

        seen[resolved.slug] = true
        resolved.depth = depth
        ordered << resolved
        walk(children_by_parent, resolved.slug, depth + 1, ordered, seen)
      end
    end
  end
end
