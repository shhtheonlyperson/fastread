import Foundation

struct LocalEpubFile: Identifiable, Hashable {
    let url: URL
    private let documentsURL: URL

    init(url: URL, documentsURL: URL) {
        self.url = url
        self.documentsURL = documentsURL
    }

    var id: String { url.path }

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }

    var locationName: String {
        if url.deletingLastPathComponent() == documentsURL {
            return "ON MY IPHONE / JUSTREAD"
        }
        return "ON MY IPHONE / JUSTREAD / \(url.deletingLastPathComponent().lastPathComponent.uppercased())"
    }

    static func discoverInAppDocuments() -> [LocalEpubFile] {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }

        let searchRoots = [
            documentsURL,
            documentsURL.appendingPathComponent("Inbox", isDirectory: true)
        ]
        var files: [LocalEpubFile] = []

        for root in searchRoots {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in urls where url.pathExtension.caseInsensitiveCompare("epub") == .orderedSame {
                files.append(LocalEpubFile(url: url, documentsURL: documentsURL))
            }
        }

        return files.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
