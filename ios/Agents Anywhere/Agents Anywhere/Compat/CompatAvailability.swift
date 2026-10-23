import SwiftUI

// iOS 14 backport support layer.
//
// The upstream client targets iOS 26.5 and freely uses APIs introduced in
// iOS 15, 16, 17 and 26. Every declaration in this directory exists so the
// iOS 14 build can keep the original call sites unchanged. Keep this layer
// dependency free and free of business logic: it only re-implements the
// missing surface with iOS 14 primitives.
//
// Naming rule: a shim keeps the upstream name when SwiftUI's own declaration
// is unavailable on iOS 14, so call sites need no edit. When the shape cannot
// be reproduced (different generic signature, two-way binding, etc.) the shim
// takes a `compat` prefix and call sites are edited instead.

/// Marks code that only exists to backport a newer SwiftUI API.
enum CompatLayer {}
