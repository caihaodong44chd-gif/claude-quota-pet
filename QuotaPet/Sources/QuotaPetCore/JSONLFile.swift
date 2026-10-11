import Foundation

/// 只追加的 .jsonl 记录文件（区间记录、命令行读数）共用的写法
enum JSONLFile {
    /// 把整行（每行以换行结尾）追加到文件末尾，文件和目录不存在就建，成功才返回 true。
    /// 上次写到一半（文件不是以换行结尾）时先补一个换行，不然这次的第一行会接在坏行后面一起作废
    static func append(_ lines: Data, to url: URL) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forUpdating: url) else { return false }
        defer { try? handle.close() }
        do {
            var data = lines
            let end = try handle.seekToEnd()
            if end > 0 {
                try handle.seek(toOffset: end - 1)
                if try handle.read(upToCount: 1) != Data([0x0A]) { data.insert(0x0A, at: 0) }
                try handle.seekToEnd()
            }
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }
}
