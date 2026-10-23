import Foundation
import Combine

/// Editors bind to each row, never to an index in the parent's mutable array.
/// A field can finish an edit after deletion or reset without accessing another
/// row or writing the removed row back into the configuration.
@MainActor
final class RuntimeEnvironmentRow: Identifiable, ObservableObject {
    let id = UUID()
    @Published var key: String
    @Published var value: String
    @Published var removesInherited: Bool

    init(key: String = "", value: String = "", removesInherited: Bool = false) {
        self.key = key
        self.value = value
        self.removesInherited = removesInherited
    }
}

@MainActor
final class RuntimeEffortRow: Identifiable, ObservableObject {
    let id = UUID()
    @Published var effortID: String
    @Published var displayName: String

    init(effortID: String = "", displayName: String = "") {
        self.effortID = effortID
        self.displayName = displayName
    }
}

@MainActor
final class RuntimeCustomModelRow: Identifiable, ObservableObject {
    let id = UUID()
    @Published var modelID: String
    @Published var displayName: String
    @Published var efforts: [RuntimeEffortRow]

    init(modelID: String = "", displayName: String = "", efforts: [RuntimeEffortRow] = []) {
        self.modelID = modelID
        self.displayName = displayName
        self.efforts = efforts
    }

    func removeEffort(_ id: UUID) {
        efforts.removeAll { $0.id == id }
    }
}
