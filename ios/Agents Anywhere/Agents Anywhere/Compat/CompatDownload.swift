import Foundation

/// iOS 14 replacement for `URLSession.download(for:delegate:)`, which is iOS 15.
///
/// The redirect policy still runs, so a cross-origin redirect cannot carry the
/// bearer token that the caller attached to the original request.
func compatDownload(
    _ request: URLRequest,
    policy: DownloadRedirectPolicy
) async throws -> (URL, URLResponse) {
    let coordinator = CompatDownloadCoordinator(policy: policy)
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            coordinator.start(request: request, continuation: continuation)
        }
    } onCancel: {
        coordinator.cancel()
    }
}

private final class CompatDownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let policy: DownloadRedirectPolicy
    private let lock = NSLock()
    private var session: URLSession?
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var downloadedFile: URL?

    init(policy: DownloadRedirectPolicy) {
        self.policy = policy
    }

    func start(
        request: URLRequest,
        continuation: CheckedContinuation<(URL, URLResponse), Error>
    ) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        lock.lock()
        self.session = session
        lock.unlock()

        session.downloadTask(with: request).resume()
    }

    func cancel() {
        lock.lock()
        let session = self.session
        self.session = nil
        lock.unlock()
        session?.invalidateAndCancel()
    }

    // MARK: - Redirects

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url?.hasSameOrigin(as: policy.origin) == true ? request : nil)
    }

    // MARK: - Downloads

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The system deletes `location` when this method returns, so the file is
        // claimed synchronously before the caller ever sees it.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("aa-download-\(UUID().uuidString)")
        var claimed: URL?
        if (try? FileManager.default.moveItem(at: location, to: destination)) != nil {
            claimed = destination
        }
        lock.lock()
        downloadedFile = claimed
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let file = downloadedFile
        let activeSession = self.session
        self.session = nil
        lock.unlock()

        activeSession?.finishTasksAndInvalidate()

        guard let continuation else {
            if let file { try? FileManager.default.removeItem(at: file) }
            return
        }
        if let error {
            if let file { try? FileManager.default.removeItem(at: file) }
            continuation.resume(throwing: error)
            return
        }
        guard let file, let response = task.response else {
            if let file { try? FileManager.default.removeItem(at: file) }
            continuation.resume(throwing: URLError(.badServerResponse))
            return
        }
        continuation.resume(returning: (file, response))
    }
}
