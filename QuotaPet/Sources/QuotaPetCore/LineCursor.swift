import Foundation

/// 增量读取一个只往后追加的日志文件（*.jsonl）：记住读到哪了，每次只读新追加的部分，一行一行交出去；
/// 最后一行还没写完就先留着，等下次写完再交。Claude Code 和 Codex 的日志扫描器共用。
struct LineCursor {
    private(set) var offset: UInt64 = 0
    private var partial = Data()

    init(offset: UInt64 = 0) {
        self.offset = offset
    }

    /// size：文件现在的大小。文件变小了（被截断或重写）就从头读。
    /// 分块读，每块读完马上释放：扫描是后台队列上的一个任务，不包 autoreleasepool 的话，
    /// 读过的块要等整个任务结束才一起释放，第一次扫几百 MB 日志时内存会跟着涨
    mutating func readAppended(from url: URL, size: UInt64, onLine: (Data) -> Void) {
        if size < offset { self = LineCursor() }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil else { return }
        var more = true
        while more {
            more = autoreleasepool {
                guard let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty else { return false }
                offset += UInt64(chunk.count)
                var buffer = partial
                buffer.append(chunk)
                var start = buffer.startIndex
                while let newline = buffer[start...].firstIndex(of: 0x0A) {
                    onLine(buffer[start..<newline])
                    start = buffer.index(after: newline)
                }
                partial = Data(buffer[start...])
                return true
            }
        }
    }
}
