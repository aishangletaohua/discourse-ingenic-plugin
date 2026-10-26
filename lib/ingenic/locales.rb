# frozen_string_literal: true

module Ingenic
  # The languages this forum publishes content in.
  #
  # Discourse already knows which languages a site serves; the plugin reads
  # those settings rather than keeping a list of its own. Content is filed under
  # these codes exactly, so a page written for `zh_CN` is not accidentally
  # invisible because someone typed `zh-CN`.
  module Locales
    module_function

    # The site's own default. This is also the language new content starts in
    # when nobody has picked one, which is why the plugin no longer keeps a
    # second "documentation default" setting.
    def default
      normalize(SiteSetting.default_locale) || "en"
    end

    # The default plus every language content localisation is enabled for.
    # Order is stable and the default is always first.
    def supported
      codes = [default]

      if SiteSetting.content_localization_enabled
        # A list setting is read as the stored string, pipe-separated. Joining it
        # whole would turn "zh_CN|en" into one language of its own, which no
        # reader or editor could ever pick.
        codes.concat(SiteSetting.content_localization_supported_locales.to_s.split("|"))
      end

      codes.filter_map { |value| normalize(value) }.uniq
    end

    # Accepts what a person or a URL is likely to write and returns the code the
    # site actually uses: `zh-CN` becomes `zh_CN`, `EN` becomes `en`.
    def normalize(value)
      raw = value.to_s.strip.tr("-", "_")
      return if raw.empty?

      known = LocaleSiteSetting.values.map { |option| option[:value].to_s }
      known.find { |code| code.casecmp?(raw) } || raw
    end

    def served?(value)
      supported.include?(normalize(value))
    end

    # What an editor asked to work in, read from a request parameter. A language
    # the site no longer serves is answered with the default rather than an
    # empty screen: the choice is stored in the browser, so a supported language
    # turned off in site settings must not strand the editor in it.
    def resolve(value)
      candidate = normalize(value)
      served?(candidate) ? candidate : default
    end

    # What a public reader is looking at.
    #
    # The request may name the language outright. The documentation reader
    # fetches one address per page and changes the language without leaving it,
    # so the address has to be able to say which language it is asking for —
    # otherwise the answer depends on a cookie the URL does not mention, and a
    # cache between the two serves the first reader's language to the second.
    #
    # A locale the site does not publish is answered with the default rather
    # than an empty catalogue; a supported one is used as-is with no
    # cross-language fallback inside the content.
    def reading(requested = nil)
      candidate = normalize(requested).presence || normalize(I18n.locale)
      supported.include?(candidate) ? candidate : default
    end

    # The codes with the name each language uses for itself, for the management
    # screen's picker.
    def options
      names = LocaleSiteSetting.values.index_by { |option| option[:value].to_s }

      supported.map do |code|
        { value: code, name: names.dig(code, :native_name).presence || code }
      end
    end
  end
end
