import Foundation

/// Claude Code 的一次 API 响应
public struct ClaudeRequest: Equatable, Sendable {
    public var id: String
    public var time: Date
    public var family: ModelFamily
    public var tokens: TokenCounts
    /// 思考程度（high / xhigh / max…），日志里没有就是 nil
    public var effort: String?
    /// 输出 token 里有多少是思考（已经包含在 tokens.output 里）
    public var thinkingTokens: Int

    public init(id: String, time: Date, family: ModelFamily, tokens: TokenCounts, effort: String? = nil, thinkingTokens: Int = 0) {
        self.id = id
        self.time = time
        self.family = family
        self.tokens = tokens
        self.effort = effort
        self.thinkingTokens = thinkingTokens
    }

    /// API 等价花费（美元）
    public var usd: Double { ClaudePricing.cost(family, tokens) }

    /// 「模型/思考程度」，比如 "opus/max"
    public var group: String { "\(family.rawValue)/\(effort ?? "-")" }
}

/// 增量读取 ~/.claude/projects/**/*.jsonl 里每个 API 响应的 token 用量。
/// 规则和 usage_lab.py 的 load_requests 一样：一个响应会按内容块拆成多行，
/// 按 message.id 去重，同一响应的各字段取最大值。
/// 每个文件只读新追加的部分，Claude Code 边写我们边算。
public final class ClaudeTranscriptScanner {
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    public let root: URL
    /// 只保留这么久以内的请求（周额度窗口是 7 天，多留一天）
    public let retention: TimeInterval

    private struct Cursor {
        var offset: UInt64 = 0
        var partial = Data()  // 还没写完的最后一行
    }

    private var cursors: [String: Cursor] = [:]
    private var records: [String: ClaudeRequest] = [:]
    public private(set) var trackedFiles = 0

    public init(root: URL = ClaudeTranscriptScanner.defaultRoot, retention: TimeInterval = 8 * 86400) {
        self.root = root
        self.retention = retention
    }

    /// 读取新增内容，返回保留期内的全部请求（按时间排序）
    public func refresh(now: Date = Date()) -> [ClaudeRequest] {
        let cutoff = now.addingTimeInterval(-retention)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var seen = Set<String>()
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) {
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                let path = url.path
                // 很久没动过的文件不用读
                if cursors[path] == nil, let mtime = values.contentModificationDate, mtime < cutoff { continue }
                seen.insert(path)
                var cursor = cursors[path] ?? Cursor()
                let size = UInt64(values.fileSize ?? 0)
                if size < cursor.offset { cursor = Cursor() }  // 文件被截断或重写了，从头读
                if size > cursor.offset { readAppended(url, &cursor) }
                cursors[path] = cursor
            }
        }
        cursors = cursors.filter { seen.contains($0.key) }
        trackedFiles = cursors.count
        records = records.filter { $0.value.time >= cutoff }
        return records.values.sorted { $0.time < $1.time }
    }

    private func readAppended(_ url: URL, _ cursor: inout Cursor) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: cursor.offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return }
        cursor.offset += UInt64(data.count)
        var buffer = cursor.partial
        buffer.append(data)
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            ingest(line: buffer[start..<newline], path: url.path)
            start = buffer.index(after: newline)
        }
        cursor.partial = Data(buffer[start...])
    }

    private static let usageMarker = Data("\"usage\"".utf8)

    /// 解析一行 jsonl；不是带 usage 的 API 响应就忽略
    func ingest(line: Data, path: String) {
        guard line.range(of: Self.usageMarker) != nil,
              let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any], !usage.isEmpty,
              let stamp = obj["timestamp"] as? String, let time = Self.parseDate(stamp),
              let family = ModelFamily.of(model: message["model"] as? String)  // 例如 <synthetic> 占位消息会被跳过
        else { return }

        func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
        let cacheCreation = usage["cache_creation"] as? [String: Any] ?? [:]
        let cw5: Int, cw1h: Int
        if cacheCreation.isEmpty {
            cw5 = int(usage["cache_creation_input_tokens"])
            cw1h = 0
        } else {
            cw5 = int(cacheCreation["ephemeral_5m_input_tokens"])
            cw1h = int(cacheCreation["ephemeral_1h_input_tokens"])
        }
        let tokens = TokenCounts(input: int(usage["input_tokens"]), cacheWrite5m: cw5, cacheWrite1h: cw1h,
                                 cacheRead: int(usage["cache_read_input_tokens"]), output: int(usage["output_tokens"]))
        let thinking = int((usage["output_tokens_details"] as? [String: Any])?["thinking_tokens"])
        let key = (message["id"] as? String) ?? (obj["requestId"] as? String)
            ?? "\(path)#\(obj["uuid"] as? String ?? UUID().uuidString)"

        if var previous = records[key] {
            previous.tokens.formMax(tokens)
            previous.thinkingTokens = max(previous.thinkingTokens, thinking)
            previous.time = max(previous.time, time)
            records[key] = previous
        } else {
            records[key] = ClaudeRequest(id: key, time: time, family: family, tokens: tokens,
                                         effort: obj["effort"] as? String, thinkingTokens: thinking)
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ string: String) -> Date? {
        isoFractional.date(from: string) ?? isoPlain.date(from: string)
    }
}
