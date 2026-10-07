import Foundation

/// Where Initials looks for releases: one definition for the Settings and Updates window, `initials updates`
/// and `initials update check|install`.
enum InitialsUpdates {
    static let bundleID = "cyou.tianli.initials"
    /// The release record on the product website.
    static let feed = URL(string: "https://initials.tianli.cyou/updates.json")!
    /// The channel an isolated run reads instead of the website.
    static let testChannel = "test"

    static var isolated: Bool { ProcessInfo.processInfo.environment["INITIALS_SUPPORT_DIR"] != nil }

    /// What `initials update` checks and installs from. Outside an isolated run it is always the website, whatever
    /// else the environment says. An isolated run (`INITIALS_SUPPORT_DIR`) never goes online: the shared layer then
    /// reads `$APP_LIFECYCLE_CLOUD_DIR/TianliApps/Updates/<bundle id>/test/release.json`, or reports that no test
    /// feed is configured.
    static var source: AppUpdateSource { isolated ? .privateCloud(channel: testChannel) : .manifest(feed) }
}
