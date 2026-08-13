import Foundation

/// A human-readable stamp for the running build, so it's obvious on-device which version is being
/// tested. The marketing version and build number come from the generated Info.plist; the git short
/// hash and build time come from GeneratedBuildInfo.swift, which the "Stamp build" run-script phase
/// rewrites before every compile (see project.pbxproj). A trailing "+" on the hash means the working
/// tree had uncommitted changes when the build was made.
enum BuildStamp {
    private static func info(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespaces).nonEmpty
    }

    static var version: String { info("CFBundleShortVersionString") ?? "1.0" }
    static var build: String { info("CFBundleVersion") ?? "0" }
    static var gitHash: String { GeneratedBuild.hash }
    static var buildDate: String { GeneratedBuild.date }

    /// e.g. "v1.0 (12) · a1b2c3d · 13 Aug 21:40". Compact enough for a corner of the menu.
    static var short: String {
        var s = "v\(version) (\(build))"
        if !gitHash.isEmpty { s += " · \(gitHash)" }
        if !buildDate.isEmpty { s += " · \(buildDate)" }
        return s
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
