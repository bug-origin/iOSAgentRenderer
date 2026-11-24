import SwiftUI

extension View {
    func chartSelectionFocus(_ selected: Bool, clear: @escaping () -> Void) -> some View {
        modifier(ChartSelectionFocus(selected: selected, clear: clear))
    }
}

private struct ChartSelectionFocus: ViewModifier {
    let selected: Bool
    let clear: () -> Void
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .background {
                if selected { ChartTouchBoundary(clear: clear).allowsHitTesting(false) }
            }
            #else
            .onHover { if !$0 && selected { clear() } }
            #endif
            .onChange(of: phase) { _, phase in if phase != .active && selected { clear() } }
            .onDisappear { if selected { clear() } }
    }
}

#if os(iOS)
import UIKit

/// Observe the next touch outside the selected plot, including touches on the chat chrome.
private struct ChartTouchBoundary: UIViewRepresentable {
    let clear: () -> Void
    func makeUIView(context: Context) -> Boundary { Boundary() }
    func updateUIView(_ view: Boundary, context: Context) { view.clear = clear }

    final class Boundary: UIView, UIGestureRecognizerDelegate {
        var clear: (() -> Void)?
        private lazy var observer: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer()
            tap.delegate = self
            tap.cancelsTouchesInView = false
            return tap
        }()

        override func willMove(toWindow next: UIWindow?) {
            window?.removeGestureRecognizer(observer)
            super.willMove(toWindow: next)
            next?.addGestureRecognizer(observer)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if !bounds.contains(touch.location(in: self)) { clear?() }
            // Observing touch-down suffices. Let the original target handle its gesture.
            return false
        }
    }
}
#endif
