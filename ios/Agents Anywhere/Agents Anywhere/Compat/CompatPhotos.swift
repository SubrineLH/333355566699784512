import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// `PhotosPicker`, `PhotosPickerItem` and the `.photosPicker` modifier are iOS 16.
// The underlying `PHPickerViewController` is iOS 14, so the shim drives it
// directly and keeps the same call-site vocabulary.

/// Stand-in for `PhotosPickerItem`: wraps the provider and hands back raw bytes.
struct CompatPhotosPickerItem: Identifiable, Equatable {
    let id = UUID()
    let provider: NSItemProvider

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    func loadTransferable(type: Data.Type) async throws -> Data? {
        if let data = await loadData(identifier: UTType.image.identifier) { return data }
        let image = await loadImage()
        return image?.jpegData(compressionQuality: 0.9)
    }

    private func loadData(identifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func loadImage() async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }
}

/// Kept for source compatibility with `matching: .images`; the picker always
/// filters to images because that is the only thing the call sites request.
enum CompatPhotoFilter {
    case images
}

private struct CompatPhotoPickerController: UIViewControllerRepresentable {
    let maxSelectionCount: Int
    let onFinish: ([CompatPhotosPickerItem]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = max(1, maxSelectionCount)
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinish: ([CompatPhotosPickerItem]) -> Void

        init(onFinish: @escaping ([CompatPhotosPickerItem]) -> Void) {
            self.onFinish = onFinish
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onFinish(results.map { CompatPhotosPickerItem(provider: $0.itemProvider) })
        }
    }
}

/// Bordered button form, so a labelled picker reads like the system control.
struct CompatPhotosPicker<Label: View>: View {
    @Binding private var selection: [CompatPhotosPickerItem]
    private let maxSelectionCount: Int
    private let label: () -> Label
    @State private var isPresented = false

    init(selection: Binding<[CompatPhotosPickerItem]>,
         maxSelectionCount: Int = 1,
         matching: CompatPhotoFilter = .images,
         @ViewBuilder label: @escaping () -> Label) {
        _selection = selection
        self.maxSelectionCount = maxSelectionCount
        self.label = label
    }

    var body: some View {
        // A trailing closure cannot be a bare closure reference, so the label
        // is passed through the labelled initialiser instead.
        Button(action: { isPresented = true }, label: label)
            .sheet(isPresented: $isPresented) {
                CompatPhotoPickerController(maxSelectionCount: maxSelectionCount) { items in
                    selection = items
                    isPresented = false
                }
            }
    }
}

private struct CompatPhotosPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selection: [CompatPhotosPickerItem]
    let maxSelectionCount: Int

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            CompatPhotoPickerController(maxSelectionCount: maxSelectionCount) { items in
                selection = items
                isPresented = false
            }
        }
    }
}

extension View {
    func photosPicker(isPresented: Binding<Bool>,
                      selection: Binding<[CompatPhotosPickerItem]>,
                      maxSelectionCount: Int = 1,
                      matching: CompatPhotoFilter = .images) -> some View {
        modifier(CompatPhotosPickerModifier(isPresented: isPresented,
                                            selection: selection,
                                            maxSelectionCount: maxSelectionCount))
    }
}
