import Combine

/// StateObject supplies a lazy factory tied to view identity. The model itself
/// can use Observation; this holder only owns its lifetime. State(initialValue:)
/// would eagerly build and discard another model whenever the parent rebuilds.
///
/// Deliberately not generic: a generic class makes the Swift 6.2 optimizer crash
/// while specializing its implicit `deinit`. It only ever holds one model type.
@MainActor final class StableViewModel: ObservableObject {
    let value: SessionChatModel

    init(_ makeValue: () -> SessionChatModel) {
        value = makeValue()
    }
}
