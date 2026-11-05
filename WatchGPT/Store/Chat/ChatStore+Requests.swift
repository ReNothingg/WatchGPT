import Foundation

extension ChatStore {
    func requestOptions() -> ChatGPTClient.Options {
        let model = gptModel
        let refine = messages.last { $0.role == .user }?.refine
        var verbosity = refine?.verbosity ?? (conciseAnswers ? "low" : "medium")
        if siriRequest { verbosity = "low" }
        return ChatGPTClient.Options(
            model: model.slug,
            effort: requestEffort(model, selected: gptEffort),
            webSearch: webSearch,
            verbosity: model.supportsVerbosity ? verbosity : nil,
            fast: fastMode && model.supportsFast == true,
            instructions: instructions(assistant: "ChatGPT"),
            context: requestContext(),
            conversationID: conversationID
        )
    }

    func claudeOptions() -> AnthropicClient.Options {
        let model = claudeModel
        return AnthropicClient.Options(
            model: model.slug,
            effort: requestEffort(model, selected: claudeEffort),
            thinking: model.thinking == true,
            webSearch: webSearch,
            fast: fastMode && model.supportsFast == true,
            instructions: instructions(assistant: "Claude"),
            context: requestContext()
        )
    }

    func requestEffort(_ model: ModelOption, selected: String) -> String? {
        guard !model.efforts.isEmpty else { return nil }
        if siriRequest {
            return model.efforts.min { ModelOption.effortRank($0) < ModelOption.effortRank($1) }
        }
        return model.efforts.contains(selected) ? selected : model.defaultEffort
    }

    func requestContext() -> String {
        var context = "Current date and time: \(Date.now.formatted(date: .complete, time: .shortened))."
        if siriRequest {
            context += " Siri will read this answer aloud: reply in one to three short spoken sentences, without lists, formulas or markdown."
        }
        return context
    }

    func instructions(assistant: String) -> String {
        let style = conciseAnswers
            ? "Be brief: lead with the answer, then at most 2–4 short sentences or a compact list. Expand only if the user explicitly asks for detail."
            : "Be clear and well structured, but keep in mind the screen is small; avoid filler."
        let tables = "Use a table only when it genuinely helps, with at most 3 narrow columns and short cells."
        return """
        You are \(assistant) running on the user's Apple Watch. The user speaks to you through dictation, \
        so their message may contain speech-recognition mistakes — infer what they meant. \
        Always reply in the language of the user's message. \(style) \
        Write plain text that is easy to read on a tiny screen and to read aloud: no headings; \
        simple **bold** and short bullet lists are fine. \(tables) \
        Use code blocks only when essential, fenced with ``` and a language tag. \
        Math: write formulas in LaTeX. Short inline math goes in \\( … \\); every important formula goes \
        on its own line in \\[ … \\]. The screen is about 180 points wide, so keep each displayed formula short: \
        split long derivations into several \\[ … \\] lines, avoid wide matrices, never put formulas in code blocks. \
        Simple chemistry like H₂O can stay as plain text. \
        Locale: \(Locale.current.identifier).
        """
    }
}
