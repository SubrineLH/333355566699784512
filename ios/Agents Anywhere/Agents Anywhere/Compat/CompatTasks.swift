import SwiftUI

// This file is superseded by CompatSwiftUI.swift. The `task` / `onChange`
// overlay extensions here relied on `@available(obsoleted:)` shadowing, which is
// fragile: the app target still builds against the newest SDK, so the same-named
// SDK symbols stay visible and the overloads compete. All call sites use the
// explicitly named `compatTask` / `compatOnChange` APIs from CompatSwiftUI.swift.
//
// `DismissActionCompat` is gone as well: its `presentationMode` chain had been
// mangled, and every call site uses `presentationMode.wrappedValue.dismiss()` or
// `CompatKeyboard.dismiss()` directly.

enum CompatLayerAliases {}
