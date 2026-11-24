import Testing
import AgentRendererCore

@Test func specializedChartsRejectInconsistentData() throws {
    func validate(_ type: String, _ rows: [[String: JSONValue]]) throws {
        try AdvancedChartData.validate(type: type, props: ["data": .array(rows.map(JSONValue.object))])
    }
    try AdvancedChartData.validate(type: "GaugeChart", props: ["value": .number(42)])
    #expect(throws: RendererError.self) { try AdvancedChartData.validate(type: "GaugeChart", props: ["value": .number(101)]) }
    #expect(throws: RendererError.self) { try AdvancedChartData.validate(type: "GaugeChart", props: ["value": .number(0), "min": .number(1), "max": .number(1)]) }
    let valid: [String: JSONValue] = ["x": .string("Mon"), "open": .number(10), "high": .number(15), "low": .number(8), "close": .number(12)]
    try validate("CandlestickChart", [valid])
    var invalid = valid; invalid["close"] = .number(20)
    #expect(throws: RendererError.self) { try validate("CandlestickChart", [invalid]) }
    #expect(throws: RendererError.self) { try validate("CandlestickChart", [valid, valid]) }
    try validate("NumericScatterChart", [["x": .number(1.25), "y": .number(-2)]])
    #expect(throws: RendererError.self) { try validate("NumericScatterChart", [["x": .string("category"), "y": .number(2)]]) }
    let heat: [String: JSONValue] = ["x": .string("Mon"), "y": .string("AM"), "value": .number(5)]
    try validate("Heatmap", [heat])
    #expect(throws: RendererError.self) { try validate("Heatmap", [heat, heat]) }
    #expect(throws: RendererError.self) { try validate("FunnelChart", [["label": .string("A"), "value": .number(-1)]]) }
    let radar = ["A", "B", "C"].map { ["label": JSONValue.string($0), "value": .number(25), "series": .string("first")] }
    try validate("RadarChart", radar)
    #expect(throws: RendererError.self) { try validate("RadarChart", Array(radar.prefix(2))) }
    #expect(throws: RendererError.self) { try validate("RadarChart", radar + [["label": .string("A"), "value": .number(30), "series": .string("second")]]) }
    for type in AdvancedChartData.types where type != "GaugeChart" { try validate(type, []) }
}
