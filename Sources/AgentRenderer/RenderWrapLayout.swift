import SwiftUI

/// Intrinsic-width chips wrap naturally instead of stretching into grid columns.
struct RenderWrapLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + layout.points[index].x, y: bounds.minY + layout.points[index].y), anchor: .topLeading, proposal: ProposedViewSize(layout.sizes[index]))
        }
    }
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint], sizes: [CGSize]) {
        let available = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? CGFloat.greatestFiniteMagnitude
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, width: CGFloat = 0
        var points: [CGPoint] = [], sizes: [CGSize] = []
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(ideal.width, available), height: nil))
            if x > 0 && x + size.width > available { y += lineHeight + spacing; x = 0; lineHeight = 0 }
            points.append(CGPoint(x: x, y: y)); sizes.append(size)
            width = max(width, x + size.width); x += size.width + spacing; lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: width, height: y + lineHeight), points, sizes)
    }
}
