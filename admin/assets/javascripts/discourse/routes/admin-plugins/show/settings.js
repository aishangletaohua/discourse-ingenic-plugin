import DiscourseRoute from "discourse/routes/discourse";

/**
 * The way back to the settings that drive every screen above.
 *
 * They are Discourse site settings rather than a form of their own: the
 * plugin's switches, storage paths, e-mail address and developer form are all
 * declared in `config/settings.yml`, and a second editor would be a second
 * place for them to disagree. This page is the signpost, so an administrator
 * working in the plugin does not have to remember where they live.
 */
export default class AdminPluginsShowSettings extends DiscourseRoute {}
