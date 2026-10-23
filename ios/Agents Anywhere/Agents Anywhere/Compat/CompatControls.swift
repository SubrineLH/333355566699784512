import SwiftUI
import UIKit

// Modifiers that only exist from iOS 15 on, plus the two iOS 16 text-weight
// helpers. Each replacement keeps the call site's intent: either it applies the
// closest iOS 14 equivalent, or it does nothing because the effect was purely
// cosmetic on newer systems.

extension View {
    /// `.listRowSeparator(_:)` is iOS 15.
    func compatListRowSeparator(_ visibility: CompatListRowSeparator = .automatic) -> some View {
        self
    }

    /// `.symbolRenderingMode(_:)` is iOS 15; single-colour symbols are the
    /// default everywhere.
    func compatSymbolRenderingMode() -> some View {
        self
    }
}

enum CompatListRowSeparator {
    case automatic, hidden, visible
}

/// UIKit equivalent of `.textInputAutocapitalization(_:)`, applied through the
/// appearance proxy so a plain `TextField` picks it up.
struct CompatAutocapitalization: ViewModifier {
    let mode: UITextAutocapitalizationType

    func body(content: Content) -> some View {
        content.onAppear {
            UITextField.appearance().autocapitalizationType = mode
        }
    }
}

extension View {
    /// `.textInputAutocapitalization(_:)` is iOS 15.
    func compatTextInputAutocapitalization(_ mode: CompatTextInputAutocapitalization) -> some View {
        modifier(CompatAutocapitalization(mode: mode.uiType))
    }

    /// `.autocorrectionDisabled()` is iOS 15.
    func compatAutocorrectionDisabled(_ disabled: Bool = true) -> some View {
        modifier(CompatAutocorrection(disabled: disabled))
    }
}

enum CompatTextInputAutocapitalization {
    case never, words, sentences, characters

    var uiType: UITextAutocapitalizationType {
        switch self {
        case .never: return .none
        case .words: return .words
        case .sentences: return .sentences
        case .characters: return .allCharacters
        }
    }
}

struct CompatAutocorrection: ViewModifier {
    let disabled: Bool

    func body(content: Content) -> some View {
        content.onAppear {
            UITextField.appearance().autocorrectionType = disabled ? .no : .default
        }
    }
}

/// Stand-in for `.buttonStyle(.borderedProminent)`, which is iOS 15.
struct CompatProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Stand-in for `.buttonStyle(.bordered)`, which is iOS 15.
struct CompatBorderedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(CompatPalette.secondarySystemBackground.opacity(configuration.isPressed ? 0.6 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
