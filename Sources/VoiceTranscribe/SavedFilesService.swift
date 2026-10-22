import Foundation

/// A transcript, Markdown export, or recording metadata file found on disk — the files a
/// recording or export session "touches" beyond the audio itself.
struct SavedFileEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case transcript
        case markdownExport
        case metadata

        var label: String {
            switch self {
            case .transcript: return "Transcript"
            case .markdownExport: return "Markdown Export"
            case .metadata: return "Metadata"
            }
        }

        var systemImage: String {
            switch self {
            case .transcript: return "doc.text"
            case .markdownExport: return "doc.richtext"
            case .metadata: return "doc.badge.gearshape"
            }
        }

        init?(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "txt": self = .transcript
            case "md": self = .markdownExport
            case "json": self = .metadata
            default: return nil
            }
        }
    }

    let url: URL
    let kind: Kind
    let modifiedDate: Date

    var id: URL { url }
}

enum SavedFilesService {
    /// Scans `folder` for every saved transcript (`.txt`), Markdown export (`.md`), and
    /// recording metadata (`.json`) file, newest first. This is a filesystem scan rather than
    /// an in-memory list, so it surfaces files from past launches too, not just this session's.
    static func scan(folder: URL) -> [SavedFileEntry] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let entries: [SavedFileEntry] = urls.compactMap { url in
            guard let kind = SavedFileEntry.Kind(fileExtension: url.pathExtension) else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            return SavedFileEntry(url: url, kind: kind, modifiedDate: modified)
        }

        return entries.sorted { $0.modifiedDate > $1.modifiedDate }
    }
}
