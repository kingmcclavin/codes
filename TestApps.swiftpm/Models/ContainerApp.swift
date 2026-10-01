import Foundation

/// A logical application in the container, grouping every imported build that
/// shares a bundle identifier. This is the unit shown on the virtual Home Screen.
///
/// NOTE: The brief suggested a flat `ContainerApp` with a single `ipaPath`.
/// To support the version-management requirement ("allow multiple builds of the
/// same application to exist") we instead model an app as a group of
/// `AppVersion`s and expose the currently-active one through convenience
/// accessors that match the originally-requested shape.
struct ContainerApp: Codable, Hashable, Identifiable {
    let id: UUID
    var bundleIdentifier: String

    /// User-editable label shown under the icon. Defaults to the IPA display name.
    var displayLabel: String

    /// All imported builds, newest import last (sorted on demand for display).
    var versions: [AppVersion]

    /// Which build is the "active testing version" that Launch will use.
    var activeVersionID: UUID

    var installationDate: Date
    var isFavorite: Bool
    var lastLaunched: Date?

    /// Optional folder this app lives in on the virtual Home Screen.
    var folderID: UUID?

    /// Home Screen ordering index within its page/folder.
    var sortIndex: Int

    init(id: UUID = UUID(),
         bundleIdentifier: String,
         displayLabel: String,
         versions: [AppVersion],
         activeVersionID: UUID,
         installationDate: Date = Date(),
         isFavorite: Bool = false,
         lastLaunched: Date? = nil,
         folderID: UUID? = nil,
         sortIndex: Int = 0) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayLabel = displayLabel
        self.versions = versions
        self.activeVersionID = activeVersionID
        self.installationDate = installationDate
        self.isFavorite = isFavorite
        self.lastLaunched = lastLaunched
        self.folderID = folderID
        self.sortIndex = sortIndex
    }
}

extension ContainerApp {
    var activeVersion: AppVersion {
        versions.first(where: { $0.id == activeVersionID }) ?? versions[0]
    }

    /// Builds sorted newest-first for display in the build-history list.
    var versionsNewestFirst: [AppVersion] {
        versions.sorted { $0.isNewer(than: $1) }
    }

    var displayName: String { displayLabel }
    var version: String { activeVersion.version }
    var buildNumber: String { activeVersion.buildNumber }
    var metadata: AppMetadata { activeVersion.metadata }

    /// Does any existing build match the given build number? Used for the
    /// "new version detected" import flow.
    func existingVersion(matching metadata: AppMetadata) -> AppVersion? {
        versions.first {
            $0.version == metadata.version && $0.buildNumber == metadata.buildNumber
        }
    }
}

// MARK: - Folders

struct HomeFolder: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var sortIndex: Int

    init(id: UUID = UUID(), name: String, sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
    }
}
