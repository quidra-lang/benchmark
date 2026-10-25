struct MemoryQueue {
    let capacity: Int
    var texts: [String] = []
    var log: [String] = []

    mutating func store(_ prefix: String, keyword: String, text: String) -> Bool {
        if texts.contains(text) { log.append("\(prefix) SKIP \(keyword) \(text)"); return false }
        if texts.count == capacity { log.append("\(prefix) DROP \(texts.removeFirst())") }
        texts.append(text)
        log.append("\(prefix) STORE \(keyword) \(text)")
        return true
    }

    mutating func recall(_ prefix: String) -> String {
        let text = texts.removeFirst()
        log.append("\(prefix) RECALL \(text)")
        return text
    }

    mutating func clear(_ prefix: String) {
        if !texts.isEmpty { log.append("\(prefix) CLEAR \(texts.count)"); texts = [] }
    }
}
