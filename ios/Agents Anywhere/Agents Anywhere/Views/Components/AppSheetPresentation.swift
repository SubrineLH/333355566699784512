import SwiftUI

enum AppSheetSize: Equatable {
    case compact
    case expanded
}

extension View {
    /// Short pickers keep their chosen height across native navigation pushes.
    /// Long forms opt into the large system detent without replacing the sheet.
    ///
    /// iOS 14 has no detents, so every sheet is a full-height card; `size` stays
    /// part of the API for the call sites that still pass it.
    func appSheetPresentation(_ size: AppSheetSize) -> some View {
        modifier(AppSheetPresentation(size: size))
    }
}

private struct AppSheetPresentation: ViewModifier {
    let size: AppSheetSize

    func body(content: Content) -> some View {
        content.presentationDragIndicator(.visible)
    }
}
