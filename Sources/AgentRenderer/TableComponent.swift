import AgentRendererCore
import SwiftUI

struct TableComponent: View {
    private struct Column: Identifiable {
        let key: String
        let label: String
        let format: JSONValue?
        let numeric: Bool

        var id: String { key }
        var alignment: Alignment { numeric ? .trailing : .leading }
    }

    private let title: String
    private let filterable: Bool
    private let columns: [Column]
    private let sourceRows: [[String: JSONValue]]
    @Environment(\.renderSurfaceDepth) private var depth
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var minimumColumnWidth: CGFloat = 112
    @State private var query = ""
    @State private var sortKey: String?
    @State private var ascending = true

    init(context: ComponentRenderContext) {
        let props = context.node.props
        title = props["title"]?.text ?? "数据表"
        filterable = props["filterable"] == .bool(true)
        let rows = (props["rows"]?.array ?? []).compactMap(\.object)
        sourceRows = rows
        columns = (props["columns"]?.array ?? []).compactMap { definition in
            guard let column = definition.object, let key = column["key"]?.string,
                  let label = column["label"]?.string else { return nil }
            let values = rows.compactMap { $0[key] }.filter { $0 != .null }
            let numeric = column["format"] != nil || (!values.isEmpty && values.allSatisfy { $0.number != nil })
            return Column(key: key, label: label, format: column["format"], numeric: numeric)
        }
    }

    private var displayedRows: [[String: JSONValue]] {
        let matches = query.isEmpty ? sourceRows : sourceRows.filter { row in
            columns.contains { row[$0.key]?.text.localizedCaseInsensitiveContains(query) == true }
        }
        guard let sortKey else { return matches }
        return matches.sorted { lhs, rhs in
            let a = lhs[sortKey] ?? .null, b = rhs[sortKey] ?? .null
            if let x = a.number, let y = b.number { return ascending ? x < y : x > y }
            return a.text.localizedStandardCompare(b.text) == (ascending ? .orderedAscending : .orderedDescending)
        }
    }

    var body: some View {
        let rows = displayedRows
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                ShareLink(item: ChartCSV.encode(rows)) {
                    Image("lucide-share", bundle: .module).resizable().scaledToFit()
                        .frame(width: 16, height: 16).foregroundStyle(RenderTheme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(RenderPlainButtonStyle()).accessibilityLabel("导出表格 CSV").disabled(rows.isEmpty)
            }
            if filterable { filterField }
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(columns) { column in sortButton(column) }
                    }
                    .background(RenderTheme.secondary, in: RoundedRectangle(cornerRadius: RenderTheme.fieldRadius))
                    ForEach(rows.indices, id: \.self) { index in
                        if index != rows.startIndex { Divider().overlay(RenderTheme.border) }
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            ForEach(columns) { column in
                                let value = rows[index][column.key]
                                Text(value.map { ValueFormat.text($0, format: column.format) } ?? "—")
                                    .font(.subheadline).monospacedDigit().textSelection(.enabled)
                                    .multilineTextAlignment(column.numeric ? .trailing : .leading)
                                    .frame(minWidth: 0, maxWidth: .infinity, alignment: column.alignment)
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                            }
                        }
                    }
                }
                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                    max(width, minimumColumnWidth * CGFloat(columns.count))
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            if rows.isEmpty {
                Text(query.isEmpty ? "暂无数据" : "没有匹配结果")
                    .font(.subheadline).foregroundStyle(RenderTheme.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }
        .foregroundStyle(RenderTheme.foreground)
        .padding(depth == 0 ? 12 : 0)
        .background {
            if depth == 0 { RoundedRectangle(cornerRadius: RenderTheme.surfaceRadius).fill(RenderTheme.surface) }
        }
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: sortKey)
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: ascending)
    }

    private var filterField: some View {
        HStack(spacing: 8) {
            Image("lucide-search", bundle: .module).resizable().scaledToFit()
                .frame(width: 15, height: 15).foregroundStyle(RenderTheme.muted).accessibilityHidden(true)
            TextField("筛选表格…", text: $query)
                .textFieldStyle(.plain).font(.subheadline).padding(.vertical, 8)
                .accessibilityLabel("筛选表格").accessibilityIdentifier("render-table-filter")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image("lucide-circle-x", bundle: .module).resizable().scaledToFit()
                        .frame(width: 16, height: 16).foregroundStyle(RenderTheme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(RenderPlainButtonStyle()).accessibilityLabel("清除筛选")
            }
        }
        .padding(.leading, 12).padding(.trailing, query.isEmpty ? 12 : 0).frame(minHeight: 44)
        .background(RenderTheme.secondary, in: RoundedRectangle(cornerRadius: RenderTheme.fieldRadius))
    }

    private func sortButton(_ column: Column) -> some View {
        let selected = sortKey == column.key
        return Button {
            if selected { ascending.toggle() } else { sortKey = column.key; ascending = true }
        } label: {
            HStack(spacing: 4) {
                Text(column.label)
                if selected {
                    Image("lucide-arrow-up", bundle: .module).resizable().scaledToFit()
                        .frame(width: 12, height: 12).rotationEffect(.degrees(ascending ? 0 : 180))
                        .accessibilityHidden(true)
                }
            }
            .font(.caption.weight(.semibold)).foregroundStyle(selected ? accent : RenderTheme.muted)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: column.alignment)
            .padding(.horizontal, 12).padding(.vertical, 4).frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RenderPlainButtonStyle())
        .accessibilityLabel(column.label).accessibilityValue(selected ? (ascending ? "升序" : "降序") : "")
        .accessibilityHint("按此列排序")
    }
}
