import Foundation
import Observation

@MainActor
@Observable
final class AIConsent {
    enum Service: String, CaseIterable, Identifiable {
        case openAI
        case anthropic

        var id: String { rawValue }

        var company: String {
            switch self {
            case .openAI: return "OpenAI"
            case .anthropic: return "Anthropic"
            }
        }

        var product: String {
            switch self {
            case .openAI: return "ChatGPT"
            case .anthropic: return "Claude"
            }
        }

        var policyURL: URL {
            switch self {
            case .openAI: return URL(string: "https://openai.com/policies/privacy-policy")!
            case .anthropic: return URL(string: "https://www.anthropic.com/legal/privacy")!
            }
        }

        var sharedData: [String] {
            switch self {
            case .openAI:
                return [
                    "текст ваших вопросов и предыдущие сообщения открытого чата",
                    "записи голоса, если для распознавания выбран ChatGPT или OpenAI",
                    "токен входа в ваш аккаунт ChatGPT",
                ]
            case .anthropic:
                return [
                    "текст ваших вопросов и предыдущие сообщения открытого чата",
                    "ваш API-ключ Anthropic",
                ]
            }
        }
    }

    static let shared = AIConsent()
    static let privacyPolicyURL = URL(string: "https://github.com/ReNothingg/WatchGPT/blob/main/PRIVACY.md")!
    static let supportURL = URL(string: "https://renothingg.github.io/?contact")!

    private static let version = 1
    private let defaults = UserDefaults.standard
    private var granted: Set<Service>

    private init() {
        granted = Set(Service.allCases.filter {
            UserDefaults.standard.integer(forKey: Self.key($0)) >= Self.version
        })
    }

    func isGranted(_ service: Service) -> Bool {
        granted.contains(service)
    }

    func grant(_ service: Service) {
        granted.insert(service)
        defaults.set(Self.version, forKey: Self.key(service))
    }

    func revoke(_ service: Service) {
        granted.remove(service)
        defaults.removeObject(forKey: Self.key(service))
    }

    private static func key(_ service: Service) -> String {
        "consent.ai.\(service.rawValue)"
    }
}
