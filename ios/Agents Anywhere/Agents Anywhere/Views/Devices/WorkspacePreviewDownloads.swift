import Foundation

/// Download handling for the web preview.
///
/// WebKit's native download pipeline (`WKDownload`, `WKNavigationActionPolicy
/// .download`) is iOS 14.5, so on iOS 14 the preview cannot claim a navigation
/// as a download. The preview sheet routes those links to Safari instead and
/// this type keeps the same surface so the call sites stay unchanged.
@MainActor final class WorkspacePreviewDownloads: NSObject {
    var onComplete: (WorkspaceDownloadedFile) -> Void
    var onFailure: (String) -> Void
    var onLoading: (Bool) -> Void

    init(onComplete: @escaping (WorkspaceDownloadedFile) -> Void, onFailure: @escaping (String) -> Void,
         onLoading: @escaping (Bool) -> Void) {
        self.onComplete = onComplete
        self.onFailure = onFailure
        self.onLoading = onLoading
    }

    func cancel() {}
}
