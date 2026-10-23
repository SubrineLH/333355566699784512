import SwiftUI
import UIKit

// `ShareLink`, `SharePreview` and `Transferable` are iOS 16. Every share in this
// app exports plain text, so the shim hosts a `UIActivityViewController`.

/// Presents the system share sheet for one string.
struct CompatShareLink<Label: View>: View {
    let text: () -> String
    let label: () -> Label
    @State private var isPresented = false

    init(text: @escaping () -> String, @ViewBuilder label: @escaping () -> Label) {
        self.text = text
        self.label = label
    }

    var body: some View {
        // A trailing closure cannot be a bare closure reference, so the label
        // is passed through the labelled initialiser instead.
        Button(action: { isPresented = true }, label: label)
            .sheet(isPresented: $isPresented) {
                CompatActivityView(activityItems: [text()])
            }
    }
}

/// Wraps `UIActivityViewController` so it can live in a `.sheet`.
struct CompatActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
