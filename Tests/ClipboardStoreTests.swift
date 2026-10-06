import AppKit
import Foundation

private struct LegacyItem: Codable {
    let id: UUID
    let copiedAt: Date
    let preview: String
    let representations: [ClipboardRepresentation]
}

@main
struct ClipboardStoreTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CopyclipTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("History.plist")
        let oldItems = (1...3).map { number in
            LegacyItem(id: UUID(), copiedAt: Date(), preview: "Clip \(number)", representations: [
                ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue,
                                        data: Data("Clip \(number)".utf8)),
                ClipboardRepresentation(type: "app.copyclip.item-break", data: Data())
            ])
        }
        try PropertyListEncoder().encode(oldItems).write(to: url)

        let store = ClipboardStore(fileURL: url)
        precondition(store.items.count == 3, "Old history should load")
        precondition(store.items[0].sourceBundleIdentifier == nil, "Old history should decode without an app ID")
        precondition(FileManager.default.fileExists(atPath: directory.appendingPathComponent("HistoryIndex.plist").path),
                     "Old history should migrate to the index")

        let firstID = store.items[0].id
        store.setPinned(id: firstID, to: true)
        store.setPinned(id: store.items[1].id, to: true)
        store.rename(id: firstID, to: "Favorite")
        store.enforceLimit(1)
        store.flush()
        let retained = ClipboardStore(fileURL: url)
        precondition(retained.items.count == 2, "Pinned clips should survive the retention limit")
        precondition(retained.items[0].displayTitle == "Favorite" && retained.items[0].isPinned,
                     "Pin and rename should persist")

        store.editText(id: firstID, to: "Edited\nclip")
        store.flush()
        precondition(ClipboardStore(fileURL: url).items[0].editableText == "Edited\nclip", "Edits should persist")

        store.delete(id: firstID)
        store.flush()
        precondition(ClipboardStore(fileURL: url).items.count == 1, "Single deletion should persist")

        store.deleteAll()
        store.flush()
        precondition(ClipboardStore(fileURL: url).items.isEmpty, "Delete all should persist")
        print("Clipboard store tests passed")
    }
}
