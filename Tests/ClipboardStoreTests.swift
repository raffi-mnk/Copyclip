import AppKit
import Foundation

private struct LegacyItem: Codable {
    let id: UUID
    let copiedAt: Date
    let preview: String
    let representations: [ClipboardRepresentation]
    var isPinned: Bool? = nil
}

private func textRepresentations(_ text: String) -> [ClipboardRepresentation] {
    [
        ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8)),
        ClipboardRepresentation(type: "app.copyclip.item-break", data: Data())
    ]
}

private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CopyclipTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@main
struct ClipboardStoreTests {
    static func main() throws {
        try testSingleFileHistory()
        try testPerClipFilesFromPreviousVersion()
        try testCapture()
        print("Clipboard store tests passed")
    }

    static func testSingleFileHistory() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("History.plist")
        let oldItems = (1...3).map { number in
            LegacyItem(id: UUID(), copiedAt: Date(), preview: "Clip \(number)",
                       representations: textRepresentations("Clip \(number)"))
        }
        try PropertyListEncoder().encode(oldItems).write(to: url)

        let store = ClipboardStore(fileURL: url)
        precondition(store.items.count == 3, "Old history should load")
        precondition(store.items[0].sourceBundleIdentifier == nil, "Old history should decode without an app ID")
        precondition(FileManager.default.fileExists(atPath: directory.appendingPathComponent("HistoryIndex.plist").path),
                     "Old history should migrate to the index")
        precondition(store.content(for: store.items[0])?.text == "Clip 1", "Migrated clip data should load from disk")

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
        let edited = ClipboardStore(fileURL: url)
        precondition(edited.content(for: edited.items[0])?.text == "Edited\nclip", "Edits should persist")
        precondition(edited.items[0].preview == "Edited clip" && edited.items[0].textExcerpt == "Edited\nclip",
                     "Edits should update the clip details")

        store.delete(id: firstID)
        store.flush()
        precondition(ClipboardStore(fileURL: url).items.count == 1, "Single deletion should persist")

        store.deleteAll()
        store.flush()
        precondition(ClipboardStore(fileURL: url).items.isEmpty, "Delete all should persist")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Clips").path)
        precondition(leftovers.isEmpty, "Deleting clips should remove their data and detail files")
    }

    static func testPerClipFilesFromPreviousVersion() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clips = directory.appendingPathComponent("Clips")
        try FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
        let longText = String(repeating: "word ", count: 2_000)
        let old = LegacyItem(id: UUID(), copiedAt: Date(), preview: longText,
                             representations: textRepresentations(longText), isPinned: true)
        try PropertyListEncoder().encode(old)
            .write(to: clips.appendingPathComponent(old.id.uuidString).appendingPathExtension("plist"))
        try PropertyListEncoder().encode([old.id]).write(to: directory.appendingPathComponent("HistoryIndex.plist"))

        let store = ClipboardStore(fileURL: directory.appendingPathComponent("History.plist"))
        precondition(store.items.count == 1 && store.items[0].isPinned, "Previous clip files should load")
        precondition(store.items[0].preview.count == ClipboardItem.previewLimit, "Previews should be shortened")
        precondition(store.items[0].textExcerpt?.count == ClipboardItem.excerptLimit, "Excerpts should be shortened")
        precondition(store.content(for: store.items[0])?.text == longText, "The full text should stay on disk")
        precondition(FileManager.default.fileExists(atPath: clips.appendingPathComponent(old.id.uuidString + ".meta.plist").path),
                     "Clip details should be saved on their own")
    }

    static func testCapture() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CopyclipTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let store = ClipboardStore(fileURL: directory.appendingPathComponent("History.plist"))

        let image = NSPasteboardItem()
        image.setData(Data([1, 2, 3]), forType: .png)
        image.setData(Data([4, 5, 6]), forType: .tiff)
        image.setData(Data([7]), forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"))
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        precondition(store.capture(from: pasteboard), "Images should be captured")
        let types = store.content(for: store.items[0])?.representations.map(\.type) ?? []
        precondition(types.contains(NSPasteboard.PasteboardType.png.rawValue), "PNG should be kept")
        precondition(!types.contains(NSPasteboard.PasteboardType.tiff.rawValue), "TIFF copies of PNG images should be skipped")
        precondition(!types.contains("com.apple.pasteboard.promised-file-url"), "File promises should be skipped")

        pasteboard.clearContents()
        pasteboard.setString("Hello", forType: .string)
        precondition(store.capture(from: pasteboard), "Text should be captured")
        precondition(!store.capture(from: pasteboard), "Repeated copies should be skipped")
        precondition(store.items[0].textExcerpt == "Hello", "Text clips should have an excerpt")

        let other = NSPasteboard(name: NSPasteboard.Name("CopyclipTests-\(UUID().uuidString)"))
        defer { other.releaseGlobally() }
        precondition(store.restore(store.items[1], to: other), "Clips should restore from disk")
        precondition(other.data(forType: .png) == Data([1, 2, 3]), "Restored data should match")
    }
}
