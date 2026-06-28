import Foundation

public struct PetPersona: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let systemInstructions: String
    public let maxResponseSentences: Int

    public init(
        id: String,
        displayName: String,
        systemInstructions: String,
        maxResponseSentences: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.systemInstructions = systemInstructions
        self.maxResponseSentences = maxResponseSentences
    }
}

public extension PetPersona {
    static let warmCompanion = PetPersona(
        id: "warm-companion",
        displayName: "Warm Companion",
        systemInstructions: """
        You are a small desktop pet that chats with the user in Japanese.
        Be warm, compact, and gently supportive.
        Reply in 1-2 sentences whenever possible, and never more than 3 sentences.
        The host app handles explicit reminder creation and Codex handoff requests before this model is called.
        Do not claim you can directly open apps, operate macOS, browse, code, or bypass Codex approvals.
        If the user asks for an unavailable action, honestly say it is not available here and keep the tone kind.
        """,
        maxResponseSentences: 3
    )
}

public enum ConversationSpeaker: String, Equatable, Sendable {
    case user
    case pet
}

public struct ConversationMessage: Equatable, Sendable {
    public let speaker: ConversationSpeaker
    public let text: String

    public init(speaker: ConversationSpeaker, text: String) {
        self.speaker = speaker
        self.text = text
    }
}

public struct ConversationSession: Equatable, Sendable {
    public let persona: PetPersona
    public let maxExchangeCount: Int
    public private(set) var messages: [ConversationMessage]

    public init(
        persona: PetPersona = .warmCompanion,
        maxExchangeCount: Int = 5,
        messages: [ConversationMessage] = []
    ) {
        self.persona = persona
        self.maxExchangeCount = max(1, maxExchangeCount)
        self.messages = []
        messages.forEach { append($0) }
    }

    public var recentMessages: [ConversationMessage] {
        messages
    }

    public mutating func recordUserMessage(_ text: String) {
        append(ConversationMessage(speaker: .user, text: text))
    }

    public mutating func recordPetMessage(_ text: String) {
        append(ConversationMessage(speaker: .pet, text: text))
    }

    private mutating func append(_ message: ConversationMessage) {
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        messages.append(ConversationMessage(speaker: message.speaker, text: trimmed))
        let maximumMessageCount = maxExchangeCount * 2
        if messages.count > maximumMessageCount {
            messages.removeFirst(messages.count - maximumMessageCount)
        }
    }
}

public enum UnsupportedConversationRequest: Equatable, Sendable {
    case reminder
    case codexHandoff
    case osOperation

    public var reply: String {
        switch self {
        case .reminder:
            return "予定やリマインダー作成はまだできないよ。今はここで少し話そう。"
        case .codexHandoff:
            return "Codexへの引き継ぎはまだできないよ。今はここで少し話そう。"
        case .osOperation:
            return "Macの操作はまだできないよ。今はここで少し話そう。"
        }
    }
}

public enum ConversationPolicy {
    public static func unsupportedRequest(in rawInput: String) -> UnsupportedConversationRequest? {
        let input = rawInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !input.isEmpty else {
            return nil
        }

        if CodexHandoffPlanner.plan(for: input, recentMessages: []) != nil {
            return .codexHandoff
        }

        if ReminderParser.isActionRequest(input) {
            return .reminder
        }

        if containsAny(input, [
            "システム終了",
            "macを再起動",
            "mac再起動",
            "pcを再起動",
            "pc再起動",
            "osを再起動",
            "システムを再起動",
            "システム再起動",
            "シャットダウン",
            "ログアウト"
        ]) {
            return .osOperation
        }

        return nil
    }

    private static func containsAny(_ input: String, _ patterns: [String]) -> Bool {
        patterns.contains { input.contains($0) }
    }
}

public struct ReminderRequest: Equatable, Sendable {
    public let title: String
    public let dueDate: Date

    public init(title: String, dueDate: Date) {
        self.title = title
        self.dueDate = dueDate
    }
}

public enum ReminderParseResult: Equatable, Sendable {
    case notReminder
    case needsClarification(String)
    case clockAlarmUnsupported(String)
    case ready(ReminderRequest)
}

public enum ReminderParser {
    public static func isUndoRequest(_ rawInput: String) -> Bool {
        let input = normalized(rawInput)
        guard !input.isEmpty else {
            return false
        }

        if [
            "取り消して",
            "取り消し",
            "リマインダーを取り消して",
            "直前のリマインダーを取り消して",
            "最後のリマインダーを取り消して",
            "さっきのリマインダーを取り消して",
            "undo"
        ].contains(input) {
            return true
        }

        return matches(
            input,
            pattern: #"^(直前|最後|さっき)の?リマインダーを?取り消して$"#
        )
    }

    public static func isActionRequest(_ rawInput: String) -> Bool {
        let input = normalized(rawInput)
        guard !input.isEmpty else {
            return false
        }
        if containsAny(input, ["教えて", "方法", "違い", "とは", "?", "？"]) {
            return false
        }

        return containsAny(input, [
            "リマインドして",
            "リマインダーを作",
            "リマインダー作",
            "通知して",
            "通知を設定",
            "通知を作",
            "通知を出",
            "通知を送",
            "予定を作",
            "覚えておいて",
            "知らせて",
            "アラームをかけ",
            "アラームを設定",
            "alarm"
        ])
    }

    public static func parse(
        _ rawInput: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReminderParseResult {
        let input = normalized(rawInput)
        guard !input.isEmpty else {
            return .notReminder
        }

        guard isActionRequest(input) else {
            return .notReminder
        }

        if containsAny(input, ["アラーム", "alarm"]) {
            return .clockAlarmUnsupported("Clockのアラームはまだ作れないよ。リマインダーなら日付と時刻つきで作れるよ。")
        }

        guard containsAny(input, [
            "リマインド",
            "リマインダーを作",
            "リマインダー作",
            "通知して",
            "通知を設定",
            "通知を作",
            "通知を出",
            "通知を送",
            "覚えておいて",
            "知らせて",
            "予定を作"
        ]) else {
            return .notReminder
        }

        guard let date = dateComponent(in: input, now: now, calendar: calendar) else {
            return .needsClarification("いつのリマインダーにする？日付と時刻を入れてね。")
        }

        if hasAmbiguousBareHour(in: input) {
            return .needsClarification("午前か午後も教えてね。")
        }

        guard let time = timeComponent(in: input) else {
            return .needsClarification("何時にリマインドする？日付と時刻を入れてね。")
        }

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0

        guard let dueDate = calendar.date(from: components) else {
            return .needsClarification("日時をうまく読み取れなかったよ。もう一度だけ具体的に教えて。")
        }

        guard dueDate > now else {
            return .needsClarification("その日時は過去みたい。未来の日時を指定してね。")
        }

        return .ready(ReminderRequest(title: title(in: input), dueDate: dueDate))
    }

    public static func isCancellationReply(_ rawInput: String) -> Bool {
        let input = normalized(rawInput)
        return ["やめて", "キャンセル", "なし", "いいえ", "no", "cancel"].contains(input)
    }

    public static func isClarificationReply(_ rawInput: String) -> Bool {
        let input = normalized(rawInput)
        guard !input.isEmpty else {
            return false
        }

        if amPMMarker(in: input) != nil {
            return true
        }

        return dateComponent(in: input, now: Date(), calendar: .current) != nil
            || timeComponent(in: input) != nil
            || hasAmbiguousBareHour(in: input)
    }

    public static func mergeClarification(pendingInput: String, reply rawReply: String) -> String? {
        let pending = normalized(pendingInput)
        let reply = normalized(rawReply)
        guard !pending.isEmpty, !reply.isEmpty, isClarificationReply(reply) else {
            return nil
        }

        if let marker = amPMMarker(in: reply),
           hasAmbiguousBareHour(in: pending),
           let refined = pending.replacingFirstMatch(
               pattern: #"(^|[^0-9午前午後])(\d{1,2}\s*時)"#,
               with: "$1\(marker)$2"
           ) {
            return refined
        }

        return "\(pending) \(reply)"
    }

    private struct TimeComponent {
        let hour: Int
        let minute: Int
    }

    private static func normalized(_ rawInput: String) -> String {
        rawInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func dateComponent(in input: String, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)

        if containsAny(input, ["明後日", "あさって"]) {
            return calendar.date(byAdding: .day, value: 2, to: today)
        }
        if containsAny(input, ["明日", "あした", "あす"]) {
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
        if containsAny(input, ["今日", "本日"]) {
            return today
        }

        if let fullDate = components(
            in: input,
            pattern: #"(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日?"#,
            captureCount: 3
        ) ?? components(
            in: input,
            pattern: #"(\d{4})[/-](\d{1,2})[/-](\d{1,2})"#,
            captureCount: 3
        ),
           let year = Int(fullDate[0]),
           let month = Int(fullDate[1]),
           let day = Int(fullDate[2]) {
            return validDate(year: year, month: month, day: day, calendar: calendar)
        }

        if let monthDay = components(
            in: input,
            pattern: #"(\d{1,2})\s*月\s*(\d{1,2})\s*日"#,
            captureCount: 2
        ),
           let month = Int(monthDay[0]),
           let day = Int(monthDay[1]) {
            var year = calendar.component(.year, from: now)
            var date = validDate(year: year, month: month, day: day, calendar: calendar)
            if let candidate = date, candidate < today {
                year += 1
                date = validDate(year: year, month: month, day: day, calendar: calendar)
            }
            return date
        }

        return nil
    }

    private static func timeComponent(in input: String) -> TimeComponent? {
        if let time = components(
            in: input,
            pattern: #"(^|[^0-9])(\d{1,2})[:：]([0-5][0-9])"#,
            captureCount: 3
        ),
           var hour = Int(time[1]),
           let minute = Int(time[2]),
           (0...23).contains(hour) {
            if let marker = amPMMarker(in: input) {
                if marker == "午後", hour < 12 {
                    hour += 12
                } else if marker == "午前", hour == 12 {
                    hour = 0
                }
            }
            return TimeComponent(hour: hour, minute: minute)
        }

        if let time = components(
            in: input,
            pattern: #"(午前|午後|朝|夕方|夜)?\s*(\d{1,2})\s*時(?:\s*([0-5]?\d)\s*分)?"#,
            captureCount: 3
        ),
           var hour = Int(time[1]) {
            let marker = amPMMarker(in: time[0].isEmpty ? input : time[0])
            if marker == "午後", hour < 12 {
                hour += 12
            } else if marker == "午前", hour == 12 {
                hour = 0
            }
            guard (0...23).contains(hour) else {
                return nil
            }
            return TimeComponent(hour: hour, minute: Int(time[2]) ?? 0)
        }

        return nil
    }

    private static func hasAmbiguousBareHour(in input: String) -> Bool {
        guard amPMMarker(in: input) == nil else {
            return false
        }

        if let colonTime = components(
            in: input,
            pattern: #"(^|[^0-9])(\d{1,2})[:：]([0-5][0-9])"#,
            captureCount: 3
        ),
           let hour = Int(colonTime[1]) {
            return (1...12).contains(hour)
        }

        guard let time = components(
            in: input,
            pattern: #"(午前|午後|朝|夕方|夜)?\s*(\d{1,2})\s*時(?:\s*([0-5]?\d)\s*分)?"#,
            captureCount: 3
        ),
              let hour = Int(time[1]) else {
            return false
        }

        return (1...12).contains(hour)
    }

    private static func amPMMarker(in input: String) -> String? {
        if input.contains("午後") || input.contains("夕方") || input.contains("夜") {
            return "午後"
        }
        if input.contains("午前") || input.contains("朝") {
            return "午前"
        }
        return nil
    }

    private static func title(in input: String) -> String {
        var title = input
        [
            #"リマインドして"#,
            #"リマインダー"#,
            #"通知して"#,
            #"通知を(設定|作|出|送)(して|する|って)?"#,
            #"覚えておいて"#,
            #"明後日|あさって|明日|あした|あす|今日|本日"#,
            #"\d{4}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*日?"#,
            #"\d{4}[/-]\d{1,2}[/-]\d{1,2}"#,
            #"\d{1,2}\s*月\s*\d{1,2}\s*日"#,
            #"(午前|午後|朝|夕方|夜)?\s*\d{1,2}[:：][0-5][0-9]"#,
            #"(午前|午後|朝|夕方|夜)?\s*\d{1,2}\s*時(?:\s*[0-5]?\d\s*分)?"#,
            #"までに|ください|お願い"#
        ].forEach { pattern in
            title = title.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }

        let compact = title
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let cleaned = compact
            .replacingOccurrences(of: #"^(に|で|を)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*(に|で|を)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "リマインダー" : cleaned
    }

    private static func validDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }

        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year,
              resolved.month == month,
              resolved.day == day else {
            return nil
        }

        return calendar.startOfDay(for: date)
    }

    private static func components(in input: String, pattern: String, captureCount: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: range) else {
            return nil
        }

        var values: [String] = []
        for index in 1...captureCount {
            let captureRange = match.range(at: index)
            if captureRange.location == NSNotFound {
                values.append("")
                continue
            }
            guard let range = Range(captureRange, in: input) else {
                return nil
            }
            values.append(String(input[range]))
        }
        return values
    }

    private static func containsAny(_ input: String, _ patterns: [String]) -> Bool {
        patterns.contains { input.contains($0) }
    }

    private static func matches(_ input: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.firstMatch(in: input, range: range) != nil
    }
}

private extension String {
    func replacingFirstMatch(pattern: String, with replacement: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range) else {
            return nil
        }
        return regex.stringByReplacingMatches(
            in: self,
            range: match.range,
            withTemplate: replacement
        )
    }
}

public enum CodexHandoffCategory: String, Equatable, Sendable {
    case coding
    case research
    case computerUse
}

public struct CodexHandoffRequest: Equatable, Sendable {
    public let category: CodexHandoffCategory
    public let summary: String
    public let taskText: String

    public init(category: CodexHandoffCategory, summary: String, taskText: String) {
        self.category = category
        self.summary = summary
        self.taskText = taskText
    }
}

public enum CodexHandoffPlanner {
    public static func plan(
        for rawInput: String,
        recentMessages: [ConversationMessage]
    ) -> CodexHandoffRequest? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = input.lowercased()
        guard !input.isEmpty, shouldHandoff(normalized) else {
            return nil
        }

        let category = category(for: normalized)
        let summary = summary(for: category, input: input)
        let taskText = taskText(for: input, summary: summary, recentMessages: recentMessages)
        return CodexHandoffRequest(category: category, summary: summary, taskText: taskText)
    }

    public static func isConfirmation(_ rawInput: String) -> Bool {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["はい", "お願い", "ok", "okay", "yes", "実行して", "送って"].contains(input)
    }

    public static func isCancellation(_ rawInput: String) -> Bool {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["いいえ", "やめて", "キャンセル", "no", "cancel"].contains(input)
    }

    private static func shouldHandoff(_ input: String) -> Bool {
        guard !isUnsafeOSLifecycleRequest(input) else {
            return false
        }

        if containsAny(input, ["codex", "computer use"]) {
            return true
        }

        let codingContext = containsAny(input, [
            "codex",
            "リポジトリ",
            "repo",
            "pr ",
            "prを",
            "prの",
            "pull request",
            "コード",
            "テスト",
            "ビルド",
            "エラー",
            "実装して",
            "修正して"
        ])
        let researchContext = containsAny(input, ["調査して", "調べて", "まとめて", "要約して"])
            && containsAny(input, ["技術", "api", "sdk", "ライブラリ", "repo", "リポジトリ", "コード", "エラー"])
        let computerUseContext = containsAny(input, [
            "クリック",
            "ブラウザ",
            "画面",
            "gui",
            "クリックして",
            "入力して",
            "操作して",
            "設定して",
            "ブラウザで",
            "開いて",
            "起動して",
            "立ち上げて",
            "open ",
            "launch ",
            "アプリ操作",
            "アプリを操作",
            "アプリで操作"
        ])

        return codingContext || researchContext || computerUseContext
    }

    private static func category(for input: String) -> CodexHandoffCategory {
        if containsAny(input, [
            "computer use",
            "クリック",
            "ブラウザ",
            "画面",
            "gui",
            "クリックして",
            "入力して",
            "操作して",
            "設定して",
            "ブラウザで",
            "開いて",
            "起動して",
            "立ち上げて",
            "open ",
            "launch ",
            "アプリ操作",
            "アプリを操作",
            "アプリで操作"
        ]) {
            return .computerUse
        }
        if containsAny(input, [
            "調査して",
            "調べて",
            "まとめて",
            "要約して"
        ]) {
            return .research
        }
        return .coding
    }

    private static func summary(for category: CodexHandoffCategory, input: String) -> String {
        switch category {
        case .coding:
            return "コード作業としてCodexに引き継ぐ: \(input)"
        case .research:
            return "調査・要約としてCodexに引き継ぐ: \(input)"
        case .computerUse:
            return "Computer Useを含む可能性がある作業としてCodexに引き継ぐ: \(input)"
        }
    }

    private static func taskText(
        for input: String,
        summary: String,
        recentMessages: [ConversationMessage]
    ) -> String {
        let contextNote = recentMessages.isEmpty
            ? "なし"
            : "直近会話はプライバシーのため本文転送せず、依頼本文と要約だけを渡しています。"

        return """
        ペット会話からCodexへ委譲されたタスクです。

        依頼:
        \(input)

        引き継ぎ要約:
        \(summary)

        直近の最小コンテキスト:
        \(contextNote)

        境界:
        - 必要な承認、Computer Use、外部アクセスの判断はCodex側の通常フローに従ってください。
        - ペット側は実行権限を持たず、このタスク文だけを渡しています。
        - 依頼に含まれないOS操作や破壊的操作は行わないでください。
        """
    }

    private static func containsAny(_ input: String, _ patterns: [String]) -> Bool {
        patterns.contains { input.contains($0) }
    }

    private static func isUnsafeOSLifecycleRequest(_ input: String) -> Bool {
        containsAny(input, [
            "システム終了",
            "macを再起動",
            "mac再起動",
            "pcを再起動",
            "pc再起動",
            "osを再起動",
            "システムを再起動",
            "システム再起動",
            "シャットダウン",
            "ログアウト"
        ])
    }
}

public enum ConversationResponseNormalizer {
    public static func normalize(_ rawResponse: String, maxSentences: Int) -> String {
        let compact = compactWhitespace(rawResponse)
        guard maxSentences > 0 else {
            return compact
        }

        var sentenceCount = 0
        var result = ""
        for character in compact {
            result.append(character)
            if isSentenceTerminator(character) {
                sentenceCount += 1
                if sentenceCount >= maxSentences {
                    break
                }
            }
        }

        let normalized = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? compact : normalized
    }

    private static func compactWhitespace(_ text: String) -> String {
        var result = ""
        var previousWasSpace = false
        var newlineCount = 0

        for scalar in text.unicodeScalars {
            if CharacterSet.newlines.contains(scalar) {
                if result.last == " " {
                    result.removeLast()
                }
                newlineCount += 1
                previousWasSpace = false
                if newlineCount <= 2 {
                    result.append("\n")
                }
                continue
            }

            newlineCount = 0
            if CharacterSet.whitespaces.contains(scalar) {
                if !previousWasSpace {
                    result.append(" ")
                }
                previousWasSpace = true
            } else {
                result.append(String(scalar))
                previousWasSpace = false
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSentenceTerminator(_ character: Character) -> Bool {
        ["。", "！", "？", ".", "!", "?"].contains(character)
    }
}
