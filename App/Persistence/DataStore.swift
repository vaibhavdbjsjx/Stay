import Foundation
import UIKit

/// Reads and writes the Stay database and media files.
/// Data lives in Application Support (excluded from nothing: it is backed up
/// with the user's device backup, never uploaded by Stay itself).
struct DataStore: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stay", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
    }

    var databaseURL: URL { directory.appendingPathComponent("stay.json") }
    var mediaDirectory: URL { directory.appendingPathComponent("Media", isDirectory: true) }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func load() -> StayDatabase {
        guard let data = try? Data(contentsOf: databaseURL),
              let database = try? Self.decoder.decode(StayDatabase.self, from: data) else {
            return StayDatabase()
        }
        return database
    }

    func save(_ database: StayDatabase) {
        guard let data = try? Self.encoder.encode(database) else { return }
        try? data.write(to: databaseURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Media

    @discardableResult
    func saveImage(_ image: UIImage, maxSide: CGFloat = 1400, quality: CGFloat = 0.82) -> String? {
        let resized = image.resized(maxSide: maxSide)
        guard let data = resized.jpegData(compressionQuality: quality) else { return nil }
        return saveJPEG(data)
    }

    @discardableResult
    func saveJPEG(_ data: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: mediaDirectory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func mediaURL(_ filename: String) -> URL {
        mediaDirectory.appendingPathComponent(filename)
    }

    func image(named filename: String) -> UIImage? {
        UIImage(contentsOfFile: mediaURL(filename).path)
    }

    func deleteMedia(_ filename: String) {
        try? FileManager.default.removeItem(at: mediaURL(filename))
    }

    func deleteEverything() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
