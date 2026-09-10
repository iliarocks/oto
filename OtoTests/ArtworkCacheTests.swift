import Foundation
import XCTest
@testable import Oto

final class ArtworkCacheTests: XCTestCase {
    func testPruningRetainsReferencedArtworkAndUnrelatedFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let active = "v1-" + String(repeating: "a", count: 64) + ".jpg"
        let obsolete = "v1-" + String(repeating: "b", count: 64) + ".jpg"
        let unrelated = "notes.txt"
        for name in [active, obsolete, unrelated] {
            try Data(name.utf8).write(to: directory.appendingPathComponent(name))
        }
        try ArtworkCache.prune(in: directory, keeping: [active])
        let remaining = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertEqual(remaining, [active, unrelated])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(active)), Data(active.utf8))
    }
}
