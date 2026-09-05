import XCTest
@testable import Oto

final class CoordinatedReadTests: XCTestCase {
    @MainActor func testAlreadyCancelledReadDoesNotRunAccessor() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("music".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let read = Task {
            try await CoordinatedRead.perform(at: url) { _ in
                XCTFail("A cancelled read must not open the file")
                return Data()
            }
        }
        read.cancel()
        do { _ = try await read.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }

    func testCancellationReleasesWaitForFilePresenter() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("music".utf8).write(to: url)
        let presenter = DelayedPresenter(url: url)
        NSFileCoordinator.addFilePresenter(presenter)
        defer {
            presenter.release.signal()
            NSFileCoordinator.removeFilePresenter(presenter)
            try? FileManager.default.removeItem(at: url)
        }
        let read = Task.detached {
            try await CoordinatedRead.perform(at: url) { try Data(contentsOf: $0) }
        }
        let result = await XCTWaiter.fulfillment(of: [presenter.requested], timeout: 2)
        guard result == .completed else {
            read.cancel()
            _ = await read.result
            throw XCTSkip("This simulator did not request local file-presenter coordination")
        }
        let started = Date()
        read.cancel()
        do { _ = try await read.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1,
                          "Cancellation should stop waiting, without needing the presenter to relinquish")
    }
}

private final class DelayedPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    let requested = XCTestExpectation(description: "Reader waits for file presenter")
    let release = DispatchSemaphore(value: 0)

    init(url: URL) {
        presentedItemURL = url
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        super.init()
    }

    func relinquishPresentedItem(toReader reader: @escaping ((() -> Void)?) -> Void) {
        requested.fulfill()
        _ = release.wait(timeout: .now() + 5)
        reader(nil)
    }
}
