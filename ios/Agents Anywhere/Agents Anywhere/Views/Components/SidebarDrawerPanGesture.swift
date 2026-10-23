#if canImport(UIKit)
import SwiftUI
import UIKit

// Establishes horizontal intent before recognition so drawer pans cancel row
// taps without stealing vertical scrolling.
//
// `UIGestureRecognizerRepresentable` and the `.gesture(_:)` overload that takes
// one are iOS 18. iOS 14 hosts the same recognizer in a transparent
// `UIViewRepresentable` instead: the recognizer attaches to the host's
// superview, so touches still reach the drawer content underneath.
struct SidebarDrawerPanGesture: UIViewRepresentable {
    let progress: CGFloat
    let edgeActivationWidth: CGFloat
    let onBegan: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = PassthroughView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        let recognizer = UIPanGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.handle(_:)))
        recognizer.cancelsTouchesInView = true
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        context.coordinator.recognizer = recognizer
        context.coordinator.parent = self
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attachIfNeeded(from: view)
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class PassthroughView: UIView {
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SidebarDrawerPanGesture?
        var recognizer: UIPanGestureRecognizer?
        private weak var host: UIView?

        func attachIfNeeded(from view: UIView) {
            guard let recognizer, host !== view.superview else { return }
            detach()
            guard let target = view.superview else { return }
            target.addGestureRecognizer(recognizer)
            host = target
        }

        func detach() {
            if let recognizer, let host {
                host.removeGestureRecognizer(recognizer)
            }
            host = nil
        }

        @objc func handle(_ recognizer: UIPanGestureRecognizer) {
            guard let parent, let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            let velocity = recognizer.velocity(in: view)
            switch recognizer.state {
            case .began:
                parent.onBegan()
            case .changed:
                parent.onChanged(translation.x)
            case .ended:
                parent.onEnded(translation.x, velocity.x, false)
            case .cancelled:
                parent.onEnded(translation.x, velocity.x, true)
            case .possible, .failed:
                break
            @unknown default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard
                let parent,
                let pan = gestureRecognizer as? UIPanGestureRecognizer,
                let view = pan.view
            else {
                return false
            }

            let velocity = pan.velocity(in: view)
            guard abs(velocity.x) > abs(velocity.y) else { return false }

            if parent.progress <= 0.001 {
                let translation = pan.translation(in: view)
                let initialX = pan.location(in: view).x - translation.x
                return initialX <= max(parent.edgeActivationWidth, 0) && velocity.x > 0
            }

            if parent.progress >= 0.999 {
                return velocity.x < 0
            }

            return true
        }
    }
}
#endif
