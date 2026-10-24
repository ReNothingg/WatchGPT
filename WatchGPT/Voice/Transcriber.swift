import Foundation

/// Where speech is turned into text.
enum VoiceEngine: String, CaseIterable, Codable, Sendable {
    /// ChatGPT dictation first, then OpenAI gpt-4o-transcribe.
    case auto
    /// ChatGPT's own dictation endpoint (part of the subscription; unofficial).
    case chatgpt
    /// OpenAI speech-to-text API (gpt-4o-transcribe) with the key from your login.
    case openai
    /// Built-in watchOS dictation.
    case apple

    var title: String {
        switch self {
        case .auto: return "Авто"
        case .chatgpt: return "ChatGPT"
        case .openai: return "OpenAI API"
        case .apple: return "Apple"
        }
    }
}

enum TranscribeModel: String, CaseIterable, Codable, Sendable {
    case best = "gpt-4o-transcribe"
    case fast = "gpt-4o-mini-transcribe"

    var title: String {
        switch self {
        case .best: return "Точная"
        case .fast: return "Быстрая"
        }
    }
}

enum Transcriber {
    struct Result: Sendable {
        var text: String
        var engine: VoiceEngine
        var label: String
    }

    enum TranscribeError: LocalizedError {
        case empty
        case noQuota
        case badKey
        case http(Int, String)
        case unavailable
        case chatgpt(Int)
        case noEngine(String)

        var errorDescription: String? {
            switch self {
            case .empty: return "Не расслышал. Попробуйте ещё раз."
            case .noQuota: return "На API-аккаунте OpenAI нет средств для распознавания. Пополните баланс на platform.openai.com или выберите Apple-диктовку."
            case .badKey: return "API-ключ OpenAI не подошёл. Получите новый в настройках."
            case let .http(code, message): return message.isEmpty ? "Ошибка распознавания (\(code))." : message
            case .unavailable: return "Распознавание ChatGPT недоступно."
            case let .chatgpt(code): return "Диктовка ChatGPT не сработала (\(code)). Попробуйте ещё раз или выберите Apple-диктовку."
            case let .noEngine(reason): return "Не получилось распознать речь. \(reason)"
            }
        }
    }

    static let languages: [(code: String, name: String)] = [
        ("auto", "Авто"), ("ru", "Русский"), ("en", "English"), ("uk", "Українська"), ("de", "Deutsch"),
        ("es", "Español"), ("fr", "Français"), ("it", "Italiano"), ("pt", "Português"), ("tr", "Türkçe"),
        ("kk", "Қазақша"), ("pl", "Polski"), ("zh", "中文"), ("ja", "日本語"), ("ko", "한국어"), ("ar", "العربية"),
    ]

    /// Context for the speech model: keeps the language and writes spoken math as formulas.
    static let prompt = """
    Transcribe exactly what is said, in the language it is spoken in, with normal punctuation. \
    The speaker may dictate mathematics, physics or chemistry. Write spoken formulas in compact math notation \
    with Unicode symbols, for example: "икс в квадрате плюс два икс минус три равно нулю" → "x² + 2x − 3 = 0", \
    "корень из а плюс бэ" → "√(a + b)", "интеграл от нуля до единицы икс дэ икс" → "∫₀¹ x dx", \
    "синус альфа" → "sin α", "a over b" → "a/b", "H two O" → "H₂O". Keep ordinary speech as plain text.
    """

    private static let chatgptBlockedKey = "voice.chatgptBlockedUntil"

    @MainActor
    static func transcribe(
        fileURL: URL,
        engine: VoiceEngine,
        model: TranscribeModel,
        language: String,
        auth: AuthService
    ) async throws -> Result {
        let audio = try Data(contentsOf: fileURL)

        switch engine {
        case .chatgpt:
            return try await viaChatGPT(audio, language: language, auth: auth)
        case .openai:
            return try await viaOpenAI(audio, model: model, language: language, auth: auth)
        case .auto, .apple:
            let hasKey = auth.apiKey != nil
            let blockedUntil = UserDefaults.standard.object(forKey: chatgptBlockedKey) as? Date ?? .distantPast
            var chatgptError: Error?
            if !hasKey || blockedUntil < .now {
                do {
                    return try await viaChatGPT(audio, language: language, auth: auth)
                } catch let error as URLError {
                    throw error
                } catch {
                    chatgptError = error
                    if hasKey { UserDefaults.standard.set(Date.now.addingTimeInterval(15 * 60), forKey: chatgptBlockedKey) }
                }
            }
            do {
                return try await viaOpenAI(audio, model: model, language: language, auth: auth)
            } catch let error as URLError {
                throw error
            } catch OAuth.Failure.noAPIOrganization {
                let reason = chatgptError?.localizedDescription ?? "Диктовка ChatGPT не ответила."
                throw TranscribeError.noEngine("\(reason) Запасной вариант через OpenAI API недоступен: у аккаунта нет API-организации.")
            } catch {
                if let chatgptError, !hasKey { throw chatgptError }
                throw error
            }
        }
    }

    static func resetChatGPTAvailability() {
        UserDefaults.standard.removeObject(forKey: chatgptBlockedKey)
    }

    // MARK: ChatGPT dictation (subscription)

    static let desktopOriginator = "Codex Desktop"
    static let desktopVersion = "26.429.30905"

    @MainActor
    private static func viaChatGPT(_ audio: Data, language: String, auth: AuthService) async throws -> Result {
        var tokens = try await auth.validTokens()
        var refreshed = false

        while true {
            var form = MultipartForm()
            form.addFile(name: "file", filename: "dictation.m4a", mimeType: "audio/mp4", data: audio)
            if language != "auto" { form.addField(name: "language", value: language) }

            var request = URLRequest(url: ChatGPTClient.baseURL.appending(path: "transcribe"))
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            if let account = tokens.accountID { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
            request.setValue(desktopOriginator, forHTTPHeaderField: "originator")
            request.setValue("\(desktopOriginator)/\(desktopVersion) (watchOS; arm64)", forHTTPHeaderField: "User-Agent")
            request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.upload(for: request, from: form.finalize())
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, !refreshed {
                tokens = try await auth.refresh()
                refreshed = true
                continue
            }
            guard (200..<300).contains(status) else { throw TranscribeError.chatgpt(status) }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = obj["text"] as? String else {
                throw TranscribeError.unavailable
            }
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw TranscribeError.empty }
            return Result(text: clean, engine: .chatgpt, label: "ChatGPT")
        }
    }

    // MARK: OpenAI speech-to-text

    @MainActor
    private static func viaOpenAI(_ audio: Data, model: TranscribeModel, language: String, auth: AuthService) async throws -> Result {
        var key = try await auth.ensureAPIKey()
        var retriedKey = false

        while true {
            var form = MultipartForm()
            form.addField(name: "model", value: model.rawValue)
            form.addField(name: "response_format", value: "json")
            form.addField(name: "prompt", value: prompt)
            if language != "auto" { form.addField(name: "language", value: language) }
            form.addFile(name: "file", filename: "dictation.m4a", mimeType: "audio/mp4", data: audio)

            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.upload(for: request, from: form.finalize())
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            if (200..<300).contains(status) {
                let text = ((obj?["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw TranscribeError.empty }
                return Result(text: text, engine: .openai, label: "OpenAI · \(model.rawValue)")
            }

            let error = obj?["error"] as? [String: Any]
            let code = (error?["code"] as? String) ?? (error?["type"] as? String) ?? ""
            let message = (error?["message"] as? String) ?? ""

            if status == 401 {
                // An auto-obtained key may have been rotated: fetch a fresh one once.
                if !retriedKey, auth.apiKey?.isManual != true, let fresh = try? await auth.obtainAPIKey() {
                    key = fresh
                    retriedKey = true
                    continue
                }
                throw TranscribeError.badKey
            }
            if code.contains("insufficient_quota") || code.contains("billing") {
                throw TranscribeError.noQuota
            }
            throw TranscribeError.http(status, message)
        }
    }
}

/// Minimal multipart/form-data body builder.
struct MultipartForm {
    private let boundary = "WatchGPT-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func finalize() -> Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }
}
