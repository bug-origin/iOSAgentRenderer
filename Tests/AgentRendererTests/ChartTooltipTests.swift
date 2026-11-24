import Foundation
import Testing
@testable import AgentRenderer

@Test func chartTooltipFollowsDatumAndStaysInsideChart() {
    let size = CGSize(width: 350, height: 220)
    let tooltip = CGSize(width: 120, height: 64)
    let first = ChartTooltipLayout.position(anchor: CGPoint(x: 100, y: 150), tooltip: tooltip, container: size)
    let second = ChartTooltipLayout.position(anchor: CGPoint(x: 200, y: 150), tooltip: tooltip, container: size)
    #expect(second.x - first.x == 100)
    #expect(first.y < 150)
    let top = ChartTooltipLayout.position(anchor: CGPoint(x: 100, y: 5), tooltip: tooltip, container: size)
    #expect(top.y > 5)
    for anchor in [CGPoint(x: 0, y: 0), CGPoint(x: 350, y: 220), CGPoint(x: 175, y: 110)] {
        let position = ChartTooltipLayout.position(anchor: anchor, tooltip: tooltip, container: size)
        #expect(position.x - tooltip.width / 2 >= 0)
        #expect(position.x + tooltip.width / 2 <= size.width)
        #expect(position.y - tooltip.height / 2 >= 0)
        #expect(position.y + tooltip.height / 2 <= size.height)
    }
}
