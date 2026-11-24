import Foundation

/// The protocol and gestures share bounds and quantization, including fractional steps.
public struct SliderRange: Sendable {
    public let min: Double
    public let max: Double
    public let step: Double
    public var steps: Double { (max - min) / step }

    public init(props: [String: JSONValue]) throws {
        min = props["min"]?.number ?? 0
        max = props["max"]?.number ?? 100
        step = props["step"]?.number ?? 1
        let span = max - min
        let count = span / step
        guard min.isFinite, max.isFinite, step.isFinite, span.isFinite,
              min < max, step > 0, step <= span, min + step > min, max - step < max,
              count.isFinite, count <= 1_000_000,
              abs(count - count.rounded()) < 0.000_000_1 else {
            throw RendererError("Slider requires finite min < max, positive step, and 1...1000000 equal steps")
        }
    }

    public func snapped(_ value: Double) -> Double {
        guard value.isFinite else { return min }
        let index = ((Swift.min(max, Swift.max(min, value)) - min) / step).rounded()
        return Swift.min(max, Swift.max(min, min + index * step))
    }

    public func contains(_ value: Double) -> Bool {
        guard value.isFinite, value >= min, value <= max else { return false }
        let index = (value - min) / step
        return abs(index - index.rounded()) < 0.000_000_1
    }
}
