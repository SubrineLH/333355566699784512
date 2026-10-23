import Foundation

enum V2BusinessError: LocalizedError {
    case emptyMessage
    case emptySessionSelection
    case tooManySessions
    case emptySessionTitle
    case emptyAvatar
    case passwordTooShort
    case passwordMismatch
    case emptyDeviceName
    case invalidPairingCode
    case pairingNotClaimed
    case signedInServerUnavailable
    case invalidRuntimeConfigSchema
    case invalidRuntimeConfigField(title: String)
    case tooManyAttachments(maximum: Int)
    case emptyAttachment(name: String)
    case emptyAttachmentSelection
    case attachmentTooLarge(name: String)
    case invalidPageSize
    case workspaceFilesUnavailable(message: String)
    case workspaceEntryNotPreviewable
    case invalidWorkspacePreviewURL

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return L("Enter a message before sending.")
        case .emptySessionSelection:
            return L("Select at least one session.")
        case .tooManySessions:
            return L("Select no more than 200 sessions at once.")
        case .emptySessionTitle:
            return L("Enter a session title.")
        case .emptyAvatar:
            return L("Choose an avatar image before uploading.")
        case .passwordTooShort:
            return L("Password must be at least 8 characters.")
        case .passwordMismatch:
            return L("Passwords do not match.")
        case .emptyDeviceName:
            return L("Enter a device name before continuing.")
        case .invalidPairingCode:
            return L("Enter the 6-digit pairing code shown on the device.")
        case .pairingNotClaimed:
            return L("The server did not accept this pairing request.")
        case .signedInServerUnavailable:
            return L("The signed-in server is unavailable.")
        case .invalidRuntimeConfigSchema:
            return L("The runtime configuration schema is unavailable or invalid.")
        case let .invalidRuntimeConfigField(title):
            return L("Enter a valid value for \(title).")
        case let .tooManyAttachments(maximum):
            return L("Attach no more than \(maximum) files.")
        case let .emptyAttachment(name):
            return L("The attachment '\(name)' is empty.")
        case .emptyAttachmentSelection:
            return L("Choose at least one file to upload.")
        case let .attachmentTooLarge(name):
            return L("The attachment '\(name)' exceeds the 25 MiB file limit.")
        case .invalidPageSize:
            return L("The requested page size is outside the supported range.")
        case let .workspaceFilesUnavailable(message):
            return message
        case .workspaceEntryNotPreviewable:
            return L("This workspace item cannot be previewed.")
        case .invalidWorkspacePreviewURL:
            return L("The file preview URL is invalid.")
        }
    }
}

struct V2LocalAttachment: Hashable {
    let fileId: V2AttachmentID
    let name: String
    let mediaType: String
    let data: Data
    let sha256: String?
}
