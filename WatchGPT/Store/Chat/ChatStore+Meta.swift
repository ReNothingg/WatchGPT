import Foundation
import WatchKit

extension ChatStore {
    static let usageMaxAge: TimeInterval = 300
    static let modelsMaxAge: TimeInterval = 6 * 3600

    func refreshMeta(force: Bool = false) async {
        guard auth.isSignedIn else { return }
        let now = Date.now
        if !force, let last = lastMetaRefresh, now.timeIntervalSince(last) < 60 { return }
        lastMetaRefresh = now
        let usageStale = force || usage.map { now.timeIntervalSince($0.updatedAt) >= Self.usageMaxAge } ?? true
        let modelsStale = modelsAreStale(maxAge: Self.modelsMaxAge)
        let claudeStale = auth.hasClaudeKey && claudeModelsAreStale(maxAge: Self.modelsMaxAge)
        await withTaskGroup(of: Void.self) { group in
            if usageStale { group.addTask { await self.refreshUsage() } }
            if modelsStale { group.addTask { await self.refreshModels() } }
            if claudeStale { group.addTask { await self.refreshClaudeModels() } }
            group.addTask { await self.refreshClientVersion() }
        }
    }

    func refreshModels(ifOlderThan maxAge: TimeInterval) async {
        guard auth.isSignedIn, modelsAreStale(maxAge: maxAge) else { return }
        await refreshModels()
    }

    func refreshClaudeModels(ifOlderThan maxAge: TimeInterval) async {
        guard auth.hasClaudeKey, claudeModelsAreStale(maxAge: maxAge) else { return }
        await refreshClaudeModels()
    }

    func refreshClaudeModels() async {
        guard let key = auth.claudeKey?.key else { return }
        do {
            let fetched = try await AnthropicClient(apiKey: key).fetchModels()
            guard auth.claudeKey?.key == key, !fetched.isEmpty else { return }
            defaults.set(Date.now, forKey: Keys.claudeModelsFetchedAt)
            if fetched != claudeModels { claudeModels = fetched }
            if let data = try? JSONEncoder().encode(fetched) { defaults.set(data, forKey: Keys.claudeModels) }
            if !fetched.contains(where: { $0.slug == claudeModelSlug }) {
                claudeModelSlug = fetched.first { $0.slug == ModelOption.claudeFallback[0].slug }?.slug ?? fetched[0].slug
            }
        } catch {
            if GPTHistory.isCancellation(error) { return }
            DiagnosticsLog.shared.record(.models, error)
        }
    }

    func claudeKeyChanged() {
        defaults.removeObject(forKey: Keys.claudeModelsFetchedAt)
        if auth.hasClaudeKey {
            Task { await refreshClaudeModels() }
        } else {
            provider = .chatgpt
            claudeModels = ModelOption.claudeFallback
            defaults.removeObject(forKey: Keys.claudeModels)
        }
    }

    func claudeModelsAreStale(maxAge: TimeInterval) -> Bool {
        guard let fetchedAt = defaults.object(forKey: Keys.claudeModelsFetchedAt) as? Date else { return true }
        return Date.now.timeIntervalSince(fetchedAt) >= maxAge
    }

    func modelsAreStale(maxAge: TimeInterval) -> Bool {
        guard let fetchedAt = defaults.object(forKey: Keys.modelsFetchedAt) as? Date else { return true }
        return Date.now.timeIntervalSince(fetchedAt) >= maxAge
    }

    func refreshUsage() async {
        do {
            let tokens = try await auth.validTokens()
            let snapshot = try await ChatGPTClient(tokens: tokens).fetchUsage()
            usageError = nil
            applyUsage(snapshot)
        } catch ChatGPTClient.APIError.unauthorized {
            if (try? await auth.refresh()) != nil, let tokens = auth.tokens,
               let snapshot = try? await ChatGPTClient(tokens: tokens).fetchUsage() {
                applyUsage(snapshot)
            }
        } catch {
            usageError = Self.describe(error)
            DiagnosticsLog.shared.record(.usage, error)
        }
    }

    func refreshClientVersion() async {
        guard auth.isSignedIn else { return }
        if case .updated = await ClientVersion.refresh() { await refreshModels() }
    }

    func refreshModels() async {
        guard let tokens = try? await auth.validTokens() else { return }
        var fetched: [ModelOption] = []
        var didUpgradeClient = false
        while true {
            do {
                fetched = try await ChatGPTClient(tokens: tokens).fetchModels()
                break
            } catch {
                if GPTHistory.isCancellation(error) { return }
                if !didUpgradeClient, await ClientVersion.refreshAfterError(error) {
                    didUpgradeClient = true
                    continue
                }
                DiagnosticsLog.shared.record(.models, error)
                return
            }
        }
        guard !fetched.isEmpty else { return }
        defaults.set(Date.now, forKey: Keys.modelsFetchedAt)
        let adjusted = applyEffortOverrides(fetched)
        if adjusted != models { models = adjusted }
        if let data = try? JSONEncoder().encode(fetched) { defaults.set(data, forKey: Keys.models) }
        if !fetched.contains(where: { $0.slug == selectedModelSlug }) {
            selectedModelSlug = fetched[0].slug
        }
    }

    func applyEffortOverrides(_ list: [ModelOption]) -> [ModelOption] {
        list.map { model in
            guard let supported = effortOverrides[model.slug] else { return model }
            var fixed = model
            let kept = model.efforts.filter { supported.contains($0) }
            fixed.efforts = kept.isEmpty ? supported : kept
            if let current = fixed.defaultEffort, !fixed.efforts.contains(current) {
                fixed.defaultEffort = fixed.efforts.last { ModelOption.effortRank($0) <= ModelOption.effortRank(current) } ?? fixed.efforts.first
            }
            return fixed
        }
    }

    func fixUnsupportedEffort(_ error: Error) -> Bool {
        let message: String
        switch error {
        case let ChatGPTClient.APIError.stream(m): message = m
        case let ChatGPTClient.APIError.http(_, m): message = m
        default: return false
        }
        guard let parsed = Self.parseUnsupportedValue(message), parsed.invalid == gptEffort else { return false }
        let model = gptModel
        let supported = parsed.supported
        effortOverrides[model.slug] = supported
        defaults.set(effortOverrides, forKey: Keys.effortOverrides)
        models = applyEffortOverrides(models)

        let rank = ModelOption.effortRank(parsed.invalid)
        let efforts = gptModel.efforts
        gptEffort = efforts.last { ModelOption.effortRank($0) < rank } ?? gptModel.defaultEffort ?? efforts.first ?? "low"
        return true
    }

    static func parseUnsupportedValue(_ message: String) -> (invalid: String, supported: [String])? {
        guard let marker = message.range(of: "Supported values are", options: .caseInsensitive) else { return nil }
        func quoted(_ s: Substring) -> [String] {
            var out: [String] = []
            var rest = s
            while let open = rest.firstIndex(of: "'") {
                let after = rest.index(after: open)
                guard let close = rest[after...].firstIndex(of: "'") else { break }
                out.append(String(rest[after..<close]))
                rest = rest[rest.index(after: close)...]
            }
            return out
        }
        guard let invalid = quoted(message[..<marker.lowerBound]).last else { return nil }
        let supported = quoted(message[marker.upperBound...])
        return supported.isEmpty ? nil : (invalid, supported)
    }

    func applyUsage(_ snapshot: UsageSnapshot) {
        var merged = usage.map { $0.merged(with: snapshot) } ?? snapshot
        if merged.planType == nil { merged.planType = auth.tokens?.planType }
        guard merged != usage else { return }
        let contentChanged = merged.ignoringTimestamp != usage?.ignoringTimestamp
        usage = merged
        if contentChanged { usageHistory.record(merged) }
        if let data = try? JSONEncoder().encode(merged) { defaults.set(data, forKey: Keys.usage) }
        guard contentChanged else { return }
        LimitReminder.update(for: merged)
        publishWidget()
    }

    func signedOut() {
        deleteAllChats()
        gptHistory.clear()
        path = []
        usage = nil
        usageHistory.clear()
        defaults.removeObject(forKey: Keys.usage)
        defaults.removeObject(forKey: Keys.modelsFetchedAt)
        LimitReminder.update(for: nil)
        publishWidget()
    }
}
