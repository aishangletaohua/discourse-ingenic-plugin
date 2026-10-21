# frozen_string_literal: true

class IngenicBoardSerializer < ActiveModel::Serializer
  attributes :id,
             :slug,
             :name,
             :kind,
             :chip_name,
             :product_slug,
             :series_slug,
             :series_name,
             :description,
             :details,
             :details_html,
             :specs,
             :image_url,
             :application_url,
             :purchase_url,
             :sold_out,
             :locale

  # The slugs are what the filter controls compare against, and they come back
  # as null rather than empty for a board that has not been filed against the
  # tree yet, so the page can tell "no chip" from "chip named nothing".
  def product_slug
    object.product&.slug
  end

  def series_slug
    object.series&.slug
  end

  def series_name
    object.series&.name
  end

  # The dialog's long description is authored as Markdown by the Ingenic team,
  # so it goes through the same sanitizer as a documentation page. Onebox is
  # off because a board description should not fetch third-party pages while
  # the catalogue is being read.
  def details_html
    PrettyText.cook(object.details.to_s, features: { Onebox: false })
  end
end
