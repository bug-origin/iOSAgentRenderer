import Foundation
import Observation
import AgentRendererCore

@MainActor @Observable
public final class RendererSession {
    public private(set) var engine: RenderEngine
    public private(set) var context: RenderContext
    public private(set) var state: JSONValue
    public private(set) var root: ResolvedNode?
    public private(set) var errorMessage: String?
    public private(set) var validationErrors: [String: String] = [:]
    public private(set) var pendingInstances: Set<String> = []
    public private(set) var focusedInstanceId: String?
    public private(set) var lastAction: ActionEnvelope?
    public private(set) var outcome: ActionOutcome?
    @ObservationIgnored private var presentationValues: [String: [String: JSONValue]] = [:]

    /// Local UI state survives content virtualization without entering the wire protocol.
    public func presentationValue(for instanceId: String, key: String) -> JSONValue? {
        presentationValues[instanceId]?[key]
    }

    public func setPresentationValue(_ value: JSONValue, for instanceId: String, key: String) {
        presentationValues[instanceId, default: [:]][key] = value
    }

    @ObservationIgnored private var draftErrors: [String: String] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let handler: @MainActor (ActionEnvelope) async throws -> ActionOutcome

    /// Start an interactive card from the versioned document returned by an agent.
    public convenience init(
        document: RenderDocument,
        onAction: @escaping @MainActor (ActionEnvelope) async throws -> ActionOutcome
    ) throws {
        try self.init(spec: document.spec, state: document.state, context: document.context,
                      catalog: .bundled(), onAction: onAction)
    }

    public init(spec: RenderSpec, state: JSONValue, context: RenderContext, catalog: RenderCatalog,
                onAction: @escaping @MainActor (ActionEnvelope) async throws -> ActionOutcome) throws {
        self.engine = try RenderEngine(spec: spec, catalog: catalog)
        self.context = context; self.state = state; self.handler = onAction
        self.root = try engine.resolve(state: state)
    }

    /// Host-only refresh. Build the complete new tree before committing; old action completions are discarded.
    public func replace(spec: RenderSpec, state: JSONValue, context: RenderContext) throws {
        if context.threadId == self.context.threadId, context.viewId == self.context.viewId, context.revision < self.context.revision {
            throw RendererError("Stale view revision")
        }
        let engine = try RenderEngine(spec: spec, catalog: self.engine.catalog)
        let root = try engine.resolve(state: state)
        setFocus(nil)
        generation += 1
        self.engine = engine; self.root = root; self.state = state; self.context = context
        presentationValues = [:]
        draftErrors = [:]
        pendingInstances = []; validationErrors = [:]; errorMessage = nil; outcome = nil; lastAction = nil
    }

    public func setInput(_ value: JSONValue, at path: String) {
        do {
            try RenderEngine.validateWritePath(path)
            var updated = state
            try updated.set(value, at: path)
            let root = try engine.resolve(state: updated)
            self.state = updated; self.root = root; errorMessage = nil
            validationErrors.removeValue(forKey: path)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Invalid intermediate numeric text stays local, but must block form submission.
    public func setDraftError(_ message: String?, instanceId: String) {
        guard let node = find(instanceId, in: root), node.type == "NumberField", let path = node.bindings["value"] else { return }
        draftErrors[path] = message
        validationErrors[path] = message
    }

    /// Focus belongs to a rendered instance (including repeated fields), never to the wire document.
    /// Lifecycle bindings are local-only so opening a keyboard cannot trigger a business request.
    public func setFocus(_ instanceId: String?) {
        guard focusedInstanceId != instanceId else { return }
        if let instanceId {
            guard let node = find(instanceId, in: root), (Set(["TextField", "TextArea", "Select", "Slider", "Switch", "Radio", "Checkbox"]).union(ExtendedInput.types)).contains(node.type),
                  node.props["disabled"] != .bool(true) else { return }
        }
        let old = focusedInstanceId.flatMap { find($0, in: root) }
        focusedInstanceId = instanceId
        if let old {
            applyLifecycle("blur", node: old)
            updateValidation(for: old)
        }
        if let instanceId, let node = find(instanceId, in: root) { applyLifecycle("focus", node: node) }
    }

    /// New controls update the binding first; optional change hooks observe the new state.
    /// Slider drags suppress hooks until release. No network action can be bound to change.
    @discardableResult
    public func setControlValue(_ value: JSONValue, instanceId: String, emitChange: Bool = true) -> Bool {
        guard pendingInstances.isEmpty, let node = find(instanceId, in: root),
              (Set(["Slider", "Switch", "Radio", "Checkbox"]).union(ExtendedInput.types)).contains(node.type),
              node.props["disabled"] != .bool(true), let path = node.bindings["value"] else { return false }
        if ["CheckboxGroup", "ComboBox", "ToggleGroup"].contains(node.type), let selected = value.array {
            guard selected.allSatisfy({ choice in (node.props["options"]?.array ?? []).contains { $0.object?["value"] == choice && $0.object?["disabled"] != .bool(true) } }) else { return false }
        }
        if node.type == "Radio" {
            guard (node.props["options"]?.array ?? []).contains(where: {
                $0.object?["value"] == value && $0.object?["disabled"] != .bool(true)
            }) else { return false }
        }
        setInput(value, at: path)
        guard stateValue(at: path) == value else { return false }
        if emitChange, let updated = find(instanceId, in: root) { applyLifecycle("change", node: updated) }
        return true
    }

    public func chooseFollowup(instanceId: String, index: Int) async {
        guard pendingInstances.isEmpty, let node = find(instanceId, in: root), node.type == "Followup",
              let prompts = node.props["prompts"]?.array, prompts.indices.contains(index), let path = node.bindings["value"] else { return }
        setFocus(nil)
        setInput(prompts[index], at: path)
        await emit(instanceId: instanceId, event: "press")
    }

    /// A step change is local. Only moving forward validates the departing page.
    @discardableResult
    public func moveStep(instanceId: String, offset: Int) -> Bool {
        guard [-1, 1].contains(offset), pendingInstances.isEmpty,
              let node = find(instanceId, in: root), node.type == "Steps",
              node.props["disabled"] != .bool(true), let index = node.props["value"]?.number,
              let path = node.bindings["value"] else { return false }
        let current = Int(index), next = current + offset
        guard node.children.indices.contains(current), node.children.indices.contains(next) else { return false }
        setFocus(nil)
        if offset > 0, !updateValidation(for: node.children[current]) { return false }
        setInput(.number(Double(next)), at: path)
        return stateValue(at: path) == .number(Double(next))
    }

    private func stateValue(at path: String) -> JSONValue? { try? state.value(at: path) }

    private func applyLifecycle(_ event: String, node: ResolvedNode) {
        guard let binding = engine.spec.elements[node.elementKey]?.on?[event], binding.action == "setState" else { return }
        do {
            let params = try (binding.params ?? [:]).mapValues { try engine.resolveValue($0, state: state, scope: node.scope) }
            guard Set(params.keys) == ["statePath", "value"], let path = params["statePath"]?.string,
                  let value = params["value"] else { throw RendererError("Invalid focus/blur parameters") }
            setInput(value, at: path)
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    private func updateValidation(for node: ResolvedNode) -> Bool {
        var errors: [String: String] = [:]
        func inspect(_ node: ResolvedNode) {
            if let path = node.bindings["value"], (Set(["TextField", "TextArea", "Select", "Slider", "Switch", "Radio", "Checkbox"]).union(ExtendedInput.types)).contains(node.type) {
                validationErrors.removeValue(forKey: path)
                if let error = fieldError(node) { errors[path] = error }
            }
            node.children.forEach(inspect)
            node.slots.values.flatMap { $0 }.forEach(inspect)
        }
        inspect(node)
        validationErrors.merge(errors) { _, new in new }
        return errors.isEmpty
    }

    private func fieldError(_ node: ResolvedNode) -> String? {
        guard node.props["disabled"] != .bool(true), let path = node.bindings["value"],
              let value = try? state.value(at: path) else { return nil }
        if let draft = draftErrors[path] { return draft }
        if ExtendedInput.types.contains(node.type) { return ExtendedInput.error(type: node.type, props: node.props) }
        if node.type == "Checkbox", node.props["required"] == .bool(true), value != .bool(true) {
            return "请勾选" + (node.props["label"]?.text ?? "此选项")
        }
        if node.type == "Radio" {
            if value == .string(""), node.props["required"] != .bool(true) { return nil }
            guard (node.props["options"]?.array ?? []).contains(where: {
                $0.object?["value"] == value && $0.object?["disabled"] != .bool(true)
            }) else { return "请选择" + (node.props["label"]?.text ?? "有效选项") }
        }
        if node.props["required"] == .bool(true), value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写" + (node.props["label"]?.text ?? "此字段")
        }
        if let limit = node.props["maxLength"]?.number, Double(value.text.count) > limit { return "输入长度超出限制" }
        if node.type == "Select", !value.text.isEmpty,
           !(node.props["options"]?.array ?? []).contains(where: { $0.object?["value"] == value }) { return "请选择有效选项" }
        return nil
    }

    public func canEmit(node: ResolvedNode, event: String) -> Bool {
        engine.spec.elements[node.elementKey]?.on?[event] != nil
    }

    public func emit(instanceId: String, event: String) async {
        guard !pendingInstances.contains(instanceId), let node = find(instanceId, in: root),
              node.props["disabled"] != .bool(true),
              let binding = engine.spec.elements[node.elementKey]?.on?[event] else { return }
        do {
            let params = try (binding.params ?? [:]).mapValues { try engine.resolveValue($0, state: state, scope: node.scope) }
            if binding.action == "setState" {
                guard Set(params.keys) == ["statePath", "value"], let pointer = params["statePath"]?.string,
                      let value = params["value"] else { throw RendererError("Invalid setState parameters") }
                try RenderEngine.validateWritePath(pointer)
                var updated = state
                try updated.set(value, at: pointer)
                let root = try engine.resolve(state: updated)
                self.state = updated; self.root = root; errorMessage = nil
                return
            }
            guard let actionId = params["actionId"]?.string, !actionId.isEmpty else { throw RendererError("Host action requires actionId") }
            if binding.action == "submitForm" {
                guard let path = params["formPath"]?.string, try JSONValue.tokens(path).first == "form" else {
                    throw RendererError("submitForm requires a /form path")
                }
                validationErrors = try validateForm(at: path)
                guard validationErrors.isEmpty else { return }
            }
            let invocation = ActionEnvelope(context: context, node: node, event: event, action: binding.action, params: params)
            let expectedGeneration = generation
            lastAction = invocation; outcome = nil; errorMessage = nil
            pendingInstances.insert(instanceId)
            do {
                let result = try await handler(invocation)
                guard generation == expectedGeneration else { return }
                pendingInstances.remove(instanceId)
                outcome = result
            } catch {
                guard generation == expectedGeneration else { return }
                pendingInstances.remove(instanceId)
                // A thrown transport error cannot prove whether the backend accepted the operation.
                outcome = ActionOutcome(status: .unknown, message: "结果待核对：" + error.localizedDescription)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func validateForm(at path: String) throws -> [String: String] {
        let prefix = try JSONValue.tokens(path)
        _ = try state.value(at: path)
        var errors: [String: String] = [:]
        func inspect(_ node: ResolvedNode) throws {
            if let pointer = node.bindings["value"], try JSONValue.tokens(pointer).starts(with: prefix) {
                if let error = fieldError(node) { errors[pointer] = error }
            }
            for child in node.children { try inspect(child) }
            for children in node.slots.values { for child in children { try inspect(child) } }
        }
        if let root { try inspect(root) }
        return errors
    }

    private func find(_ id: String, in node: ResolvedNode?) -> ResolvedNode? {
        guard let node else { return nil }
        if node.id == id { return node }
        for child in node.children { if let found = find(id, in: child) { return found } }
        for children in node.slots.values { for child in children { if let found = find(id, in: child) { return found } } }
        return nil
    }
}
