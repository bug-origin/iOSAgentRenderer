import Testing
import AgentRendererCore

@Test func mapReferencesAndExternalMediaValidate() throws {
    let a: JSONValue = .object(["id": .string("a"), "title": .string("A"), "latitude": .number(0), "longitude": .number(0), "rating": .number(4.8), "website": .string("https://example.com")])
    let b: JSONValue = .object(["id": .string("b"), "title": .string("B"), "latitude": .number(1), "longitude": .number(1)])
    let route: JSONValue = .object(["id": .string("walk"), "stopIds": .array([.string("a"), .string("b")]), "mode": .string("walking")])
    let props: [String: JSONValue] = ["locations": .array([a,b]), "routes": .array([route])]
    try MapData.validate(props)
    #expect(MapData.coordinates(route, locations: [a.object!,b.object!]).count == 2)
    var invalid = props
    invalid["locations"] = .array([a])
    #expect(throws: RendererError.self) { try MapData.validate(invalid) }
    var unsafe = a.object!; unsafe["website"] = .string("javascript:alert(1)")
    #expect(throws: RendererError.self) { try MapData.validate(["locations": .array([.object(unsafe)])]) }
    unsafe = a.object!; unsafe["reviewCount"] = .number(1e100)
    #expect(throws: RendererError.self) { try MapData.validate(["locations": .array([.object(unsafe)])]) }
}

@Test func valueFormattingRejectsInvalidCurrencyAndPrecision() throws {
    try ValueFormat.validate(.object(["style": .string("currency"), "currency": .string("USD"), "compact": .bool(true)]))
    #expect(throws: RendererError.self) { try ValueFormat.validate(.object(["style": .string("currency"), "currency": .string("usd")])) }
    #expect(throws: RendererError.self) { try ValueFormat.validate(.object(["minimumFractionDigits": .number(3), "maximumFractionDigits": .number(2)])) }
    #expect(ValueFormat.text(.number(1200), format: .object(["compact": .bool(true)])).hasSuffix("K"))
    #expect(ValueFormat.text(.string("unchanged"), format: .object([:])) == "unchanged")
}

@Test func scatterBubbleRequiresPositiveSize() throws {
    let row: [String: JSONValue] = ["x": .number(64), "y": .number(88), "size": .number(1200), "label": .string("A"), "series": .string("A")]
    try AdvancedChartData.validate(type: "NumericScatterChart", props: ["data": .array([.object(row)])])
    var invalid = row; invalid["size"] = .number(0)
    #expect(throws: RendererError.self) { try AdvancedChartData.validate(type: "NumericScatterChart", props: ["data": .array([.object(invalid)])]) }
}

@Test func csvPreservesNumbersQuotesAndGuardsTextFormulas() {
    let csv = ChartCSV.encode([["label": .string("=SUM(A1)"), "value": .number(-3)], ["label": .string("A,\"B\""), "value": .number(2)]])
    #expect(csv.contains("\"'=SUM(A1)\""))
    #expect(csv.contains("\"A,\"\"B\"\"\""))
    #expect(csv.contains(",-3.0"))
}
