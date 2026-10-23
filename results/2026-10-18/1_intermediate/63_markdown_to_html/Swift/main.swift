import Foundation
let tocMarker = "\u{1}toc\u{2}"

func ascii(_ s: String) -> [UInt8] {
    Array(s.utf8)
}

func string(_ b: [UInt8]) -> String {
    String(decoding: b, as: UTF8.self)
}

func part(_ b: [UInt8], _ start: Int, _ end: Int? = nil) -> String {
    String(decoding: b[start..<(end ?? b.count)], as: UTF8.self)
}

func white(_ c: UInt8) -> Bool {
    c == 32 || c == 10
}

func alnum(_ c: UInt8) -> Bool {
    (48...57).contains(c) || (65...90).contains(c) || (97...122).contains(c)
}

func label(_ c: UInt8) -> Bool {
    alnum(c) || c == 45 || c == 95
}

func punctuation(_ c: UInt8) -> Bool {
    (33...47).contains(c) || (58...64).contains(c) || (91...96).contains(c) || (123...126).contains(c)
}

func trim(_ s: String) -> String {
    s.trimmingCharacters(in: CharacterSet(charactersIn: " "))
}

func leftTrim(_ s: String) -> String {
    String(s.drop(while: {
        $0 == " "
    }))
}

func rightTrim(_ s: String) -> String {
    String(s.reversed().drop(while: { $0 == " " }).reversed())
}

func lower(_ s: String) -> String {
    s.lowercased()
}

func escape(_ s: String) -> String {
    var html = ""
    for c in s.utf8 {
        switch c {
            case 38: html += "&amp;"
            case 60: html += "&lt;"
            case 62: html += "&gt;"
            case 34: html += "&quot;"
            default: html += string([c])
        }
    }
    return html
}

func first(_ b: [UInt8], _ c: UInt8, _ start: Int) -> Int? {
    guard start < b.count else {
        return nil
    }
    return (start..<b.count).first {
        b[$0] == c
    }
}

func starts(_ b: [UInt8], _ at: Int, _ s: String) -> Bool {
    let prefix = ascii(s)
    return at + prefix.count <= b.count && b[at..<(at + prefix.count)].elementsEqual(prefix)
}

func stripTags(_ s: String) -> String {
    let b = ascii(s)
    var html = "", at = 0
    while at < b.count {
        if b[at] == 60, let end = first(b,62,at) {
            at = end + 1
            continue
        }
        html += string([b[at]])
        at += 1
    }
    return html
}

func normalize(_ s: String) -> String {
    s.lowercased().split(whereSeparator: {
        $0 == " " || $0 == "\n"
    }).joined(separator: " ")
}

func skip(_ b: [UInt8], _ position: Int) -> Int {
    var at = position
    while at < b.count && white(b[at]) {
        at += 1
    }
    return at
}

func escapedRead(_ b: [UInt8], _ position: Int, _ stops: [UInt8]) -> (String, Int) {
    var at = position, result: [UInt8] = []
    while at < b.count && !stops.contains(b[at]) {
        if b[at] == 92 && at + 1 < b.count && punctuation(b[at+1]) {
            at += 1
        }
        result.append(b[at])
        at += 1
    }
    return (string(result),at)
}

func runEnd(_ b: [UInt8], _ position: Int) -> Int {
    var at = position
    let c = b[at]
    while at < b.count && b[at] == c {
        at += 1
    }
    return at
}

func tickCloser(_ b: [UInt8], _ position: Int, _ length: Int) -> Int? {
    var at = position
    while let next = first(b,96,at) {
        let end = runEnd(b,next)
        if end-next == length {
            return next
        }
        at = end
    }
    return nil
}

func closingBracket(_ b: [UInt8], _ position: Int) -> Int? {
    var at = position, depth = 0
    while at < b.count {
        if b[at] == 92 {
            at += 2
            continue
        }
        if b[at] == 96 {
            let end = runEnd(b,at)
            at = tickCloser(b,end,end-at).map {
                $0 + end - at
            } ?? end
            continue
        }
        if b[at] == 91 {
            depth += 1
        }
        if b[at] == 93 {
            depth -= 1
            if depth == 0 {
                return at
            }
        }
        at += 1
    }
    return nil
}

indirect enum Block {
    case heading(Int, String), paragraph(String), rule, code(String, [String])
    case quote([Block]), alert(String, [Block]), list(Int?, [[Block]])
    case table([String], [String], [[String]]), toc
}

struct Reference {
    let url: String
    let title: String?
}

struct Marker {
    let kind: UInt8
    let number: Int?
    let content: String
}

struct Fence {
    let char: UInt8
    let length: Int
    let language: String
}

func fence(_ text: String) -> Fence? {
    let b = ascii(text)
    guard let c = b.first, c == 96 || c == 126 else {
        return nil
    }
    let n = runEnd(b,0), info = trim(part(b,runEnd(b,0)))
    guard n >= 3 && (c != 96 || !info.contains("`")) else {
        return nil
    }
    return Fence(char: c,length: n,language: info.components(separatedBy: " ")[0])
}

func atx(_ line: String) -> Block? {
    let b = ascii(line), n = line.prefix(while: {
        $0 == "#"
    }).count
    guard n >= 1 && n <= 6 && (n == b.count || b[n] == 32) else {
        return nil
    }
    var text = trim(part(b,n))
    let unmarked = String(text.reversed().drop(while: {
        $0 == "#"
    }).reversed())
    if unmarked.isEmpty || unmarked.hasSuffix(" ") {
        text = trim(unmarked)
    }
    return .heading(n,text)
}

func rule(_ text: String) -> Bool {
    let b = ascii(text).filter {
        $0 != 32
    }
    return b.count >= 3 && [UInt8(45),42,95].contains(b[0]) && b.allSatisfy {
        $0 == b[0]
    }
}

func marker(_ text: String) -> Marker? {
    let b = ascii(text)
    guard let c = b.first, !rule(text) else {
        return nil
    }
    let kind: UInt8, number: Int?
    var at: Int
    if [UInt8(45),42,43].contains(c) {
        kind = c
        number = nil
        at = 1
    } else {
        let n = b.prefix(while: {
            (48...57).contains($0)
        }).count
        guard n >= 1 && n <= 9 && n < b.count && [UInt8(46),41].contains(b[n]) else {
            return nil
        }
        kind = b[n]
        number = Int(part(b,0,n))!
        at = n+1
    }
    guard at < b.count && b[at] == 32 else {
        return nil
    }
    while at < b.count && b[at] == 32 {
        at += 1
    }
    return Marker(kind: kind,number: number,content: part(b,at))
}

func interrupt(_ text: String) -> Bool {
    !text.hasPrefix(" ") && (fence(text) != nil || atx(text) != nil || rule(text) || text.hasPrefix(">") || marker(text) != nil)
}

func cells(_ line: String) -> [String] {
    var b = ascii(trim(line))
    if b.first == 124 {
        b.removeFirst()
    }
    var result: [[UInt8]] = [[]], at = 0, separator = false
    while at < b.count {
        let c = b[at]
        at += 1
        separator = false
        if c == 92 && at < b.count {
            if b[at] != 124 {
                result[result.count-1].append(92)
            }
            result[result.count-1].append(b[at])
            at += 1
        } else if c == 124 {
            result.append([])
            separator = true
        } else {
            result[result.count-1].append(c)
        }
    }
    if separator {
        result.removeLast()
    }
    return result.map {
        trim(string($0))
    }
}

func alignment(_ text: String) -> String? {
    var core = text
    if core.hasPrefix(":") {
        core.removeFirst()
    }
    if core.hasSuffix(":") {
        core.removeLast()
    }
    guard !core.isEmpty && core.allSatisfy({
        $0 == "-"
    }) else {
        return nil
    }
    if text.hasPrefix(":") {
        return text.hasSuffix(":") ? "center" : "left"
    }
    return text.hasSuffix(":") ? "right" : ""
}

// Collect definitions recursively before any inline conversion takes place.
final class Parser {
    var references: [String:Reference] = [:]
    var footnotes: [String:String] = [:]

    func definition(_ text: String) -> Bool {
        let b = ascii(text)
        if text.hasPrefix("[^"), let end = first(b,93,2), starts(b,end,"]:") {
            let name = part(b,2,end), body = trim(part(b,end+2))
            if !name.isEmpty && name.utf8.allSatisfy(label) && !body.isEmpty {
                if footnotes[lower(name)] == nil {
                    footnotes[lower(name)] = body
                }
                return true
            }
        }
        guard text.hasPrefix("["), let close = first(b,93,0), starts(b,close+1,":") else {
            return false
        }
        let name = part(b,1,close)
        guard !name.contains("[") && !trim(name).isEmpty && !name.hasPrefix("^") else {
            return false
        }
        let (url,end) = escapedRead(b,skip(b,close+2),[32])
        guard !url.isEmpty else {
            return false
        }
        let at = skip(b,end)
        var title: String? = nil
        if at < b.count {
            guard at > end && [UInt8(34),39].contains(b[at]) else {
                return false
            }
            let (value,stop) = escapedRead(b,at+1,[b[at]])
            guard stop == b.count-1 else {
                return false
            }
            title = value
        }
        if references[normalize(name)] == nil {
            references[normalize(name)] = Reference(url: url,title: title)
        }
        return true
    }

    func parse(_ lines: [String]) -> [Block] {
        var blocks: [Block] = [], at = 0
        while at < lines.count {
            let line = lines[at]
            if line.isEmpty {
                at += 1
                continue
            }
            if line.hasPrefix("    ") {
                let start = at
                while at < lines.count && (lines[at].isEmpty || lines[at].hasPrefix("    ")) {
                    at += 1
                }
                while lines[at-1].isEmpty {
                    at -= 1
                }
                blocks.append(.code("",lines[start..<at].map {
                    $0.isEmpty ? "" : String($0.dropFirst(4))
                }))
                continue
            }
            if !line.hasPrefix(" ") {
                if let fence = fence(line) {
                    at += 1
                    var code: [String] = []
                    while at < lines.count {
                        let row = lines[at]
                        at += 1
                        if row.utf8.count >= fence.length && row.utf8.allSatisfy({
                            $0 == fence.char
                        }) {
                            break
                        }
                        code.append(row)
                    }
                    blocks.append(.code(fence.language,code))
                    continue
                }
                if let heading = atx(line) {
                    blocks.append(heading)
                    at += 1
                    continue
                }
                if rule(line) {
                    blocks.append(.rule)
                    at += 1
                    continue
                }
                if line.hasPrefix(">") {
                    var content: [String] = []
                    while at < lines.count && lines[at].hasPrefix(">") {
                        var row = String(lines[at].dropFirst())
                        if row.hasPrefix(" ") {
                            row.removeFirst()
                        }
                        content.append(row)
                        at += 1
                    }
                    let kind = content[0].hasPrefix("[!") && content[0].hasSuffix("]") ? String(content[0].dropFirst(2).dropLast()) : ""
                    if ["NOTE","TIP","IMPORTANT","WARNING","CAUTION"].contains(kind) {
                        blocks.append(.alert(kind,parse(Array(content.dropFirst()))))
                    } else {
                        blocks.append(.quote(parse(content)))
                    }
                    continue
                }
                if let first = marker(line) {
                    var item = first, items: [[Block]] = []
                    while true {
                        var content = [item.content]
                        at += 1
                        while at < lines.count && lines[at].hasPrefix("  ") {
                            content.append(String(lines[at].dropFirst(2)))
                            at += 1
                        }
                        items.append(parse(content))
                        var next = at
                        while next < lines.count && lines[next].isEmpty {
                            next += 1
                        }
                        guard next < lines.count, let following = marker(lines[next]), following.kind == first.kind, (following.number != nil) == (first.number != nil) else {
                            break
                        }
                        item = following
                        at = next
                    }
                    blocks.append(.list(first.number,items))
                    continue
                }
                if definition(line) {
                    at += 1
                    continue
                }
                if at+1 < lines.count && line.contains("|") && lines[at+1].contains("|") {
                    let header = cells(line), delimiters = cells(lines[at+1]), align = delimiters.map(alignment)
                    if header.count == delimiters.count && align.allSatisfy({
                        $0 != nil
                    }) {
                        at += 2
                        var rows: [[String]] = []
                        while at < lines.count && lines[at].contains("|") {
                            var row = Array(cells(lines[at]).prefix(header.count))
                            at += 1
                            while row.count < header.count {
                                row.append("")
                            }
                            rows.append(row)
                        }
                        blocks.append(.table(align.map {
                            $0!
                        },header,rows))
                        continue
                    }
                }
            }
            var text = [leftTrim(line)], level = 0
            at += 1
            while at < lines.count && !lines[at].isEmpty {
                let row = lines[at], b = ascii(lines[at])
                if b.count >= 3 && [UInt8(61),45].contains(b[0]) && b.allSatisfy({
                    $0 == b[0]
                }) {
                    level = b[0] == 61 ? 1 : 2
                    at += 1
                    break
                }
                if interrupt(row) {
                    break
                }
                text.append(leftTrim(row))
                at += 1
            }
            let combined = text.joined(separator: "\n")
            blocks.append(level > 0 ? .heading(level,combined) : (combined == "[TOC]" ? .toc : .paragraph(combined)))
        }
        return blocks
    }
}

struct Piece {
    var html: String = ""
    var delimiter: UInt8 = 0
    var length: Int = 0
    var open: Bool = false
    var close: Bool = false
}

func emphasis(_ pieces: [Piece], _ start: Int = 0, _ end: Int? = nil) -> String {
    let end = end ?? pieces.count
    var html = "", at = start
    while at < end {
        let piece = pieces[at]
        if piece.delimiter == 0 {
            html += piece.html
            at += 1
            continue
        }
        var closer: Int? = nil
        if piece.open {
            closer = (at+1..<end).first {
                pieces[$0].delimiter == piece.delimiter && pieces[$0].length == piece.length && pieces[$0].close
            }
        }
        if let close = closer {
            let tags: (String,String)
            if piece.delimiter == 126 {
                tags = ("<del>","</del>")
            } else if piece.length == 1 {
                tags = ("<em>","</em>")
            } else if piece.length == 2 {
                tags = ("<strong>","</strong>")
            } else {
                tags = ("<em><strong>","</strong></em>")
            }
            html += tags.0 + emphasis(pieces,at+1,close) + tags.1
            at = close+1
        } else {
            html += string(Array(repeating: piece.delimiter,count: piece.length))
            at += 1
        }
    }
    return html
}

func email(_ text: String) -> Bool {
    let parts = text.components(separatedBy: "@")
    guard parts.count == 2 && !parts[0].isEmpty && parts[0].utf8.allSatisfy({
        alnum($0) || [UInt8(46),43,45,95].contains($0)
    }) else {
        return false
    }
    let domain = parts[1].components(separatedBy: ".")
    return domain.count >= 2 && domain.allSatisfy {
        !$0.isEmpty && $0.utf8.allSatisfy {
            alnum($0) || $0 == 45
        }
    }
}

struct HeadingEntry {
    let level: Int
    let id: String
    let text: String
}

final class Renderer {
    let references: [String:Reference], footnotes: [String:String]
    var usedIds: Set<String> = [], headings: [HeadingEntry] = []
    var noteNumbers: [String:Int] = [:], noteNames: [String] = [], noteCounts: [Int] = []
    init(_ parser: Parser) {
        references = parser.references
        footnotes = parser.footnotes
    }

    func destination(_ b: [UInt8], _ at: Int, _ content: String) -> (Reference,Int)? {
        if starts(b,at,"[") {
            if let end = first(b,93,at+1) {
                let name = part(b,at+1,end)
                if !name.contains("[") {
                    // A syntactically complete reference suffix blocks shortcut fallback.
                    guard let reference = references[normalize(name.isEmpty ? content : name)] else {
                        return nil
                    }
                    return (reference,end+1)
                }
            }
        } else if starts(b,at,"(") {
            let (url,end) = escapedRead(b,skip(b,at+1),[32,10,41])
            var next = skip(b,end), title: String? = nil, valid = true
            if next > end && next < b.count && [UInt8(34),39].contains(b[next]) {
                let (value,stop) = escapedRead(b,next+1,[b[next]])
                if stop == b.count {
                    valid = false
                } else {
                    title = value
                    next = skip(b,stop+1)
                }
            }
            if valid && starts(b,next,")") {
                return (Reference(url: url,title: title),next+1)
            }
        }
        return references[normalize(content)].map {
            ($0,at)
        }
    }

    func inline(_ text: String, links: Bool = true, notes: Bool = true) -> String {
        let b = ascii(text)
        var pieces: [Piece] = [], at = 0
        while at < b.count {
            let c = b[at]
            if c == 92 {
                if at+1 < b.count && punctuation(b[at+1]) {
                    pieces.append(Piece(html: escape(part(b,at+1,at+2))))
                    at += 2
                } else if at+1 < b.count && b[at+1] == 10 {
                    pieces.append(Piece(html: "<br />\n"))
                    at += 2
                } else {
                    pieces.append(Piece(html: "\\"))
                    at += 1
                }
                continue
            }
            if c == 96 {
                let end = runEnd(b,at)
                if let close = tickCloser(b,end,end-at) {
                    var code = part(b,end,close).replacingOccurrences(of: "\n",with: " ")
                    if code.hasPrefix(" ") && code.hasSuffix(" ") && code.contains(where: {
                        $0 != " "
                    }) {
                        code = String(code.dropFirst().dropLast())
                    }
                    pieces.append(Piece(html: "<code>\(escape(code))</code>"))
                    at = close+end-at
                } else {
                    pieces.append(Piece(html: part(b,at,end)))
                    at = end
                }
                continue
            }
            if links && c == 60, let close = first(b,62,at+1) {
                let target = part(b,at+1,close), clean = !b[at+1..<close].contains {
                    white($0) || $0 == 60
                }
                var href: String? = nil
                if clean && ((target.hasPrefix("http://") && target.utf8.count > 7) || (target.hasPrefix("https://") && target.utf8.count > 8)) {
                    href = target
                } else if email(target) {
                    href = "mailto:" + target
                }
                if let href {
                    pieces.append(Piece(html: "<a href=\"\(escape(href))\">\(escape(target))</a>"))
                    at = close+1
                    continue
                }
            }
            if links && (starts(b,at,"http://") || starts(b,at,"https://")) && (at == 0 || [UInt8(32),10,42,95,126,40].contains(b[at-1])) {
                var end = at
                while end < b.count && ![UInt8(32),10,60].contains(b[end]) {
                    end += 1
                }
                while end > at && ascii(".,:;!?*_~)").contains(b[end-1]) {
                    end -= 1
                }
                let url = part(b,at,end)
                if url != "http://" && url != "https://" {
                    pieces.append(Piece(html: "<a href=\"\(escape(url))\">\(escape(url))</a>"))
                    at = end
                    continue
                }
            }
            if c == 91 || (c == 33 && starts(b,at+1,"[")) {
                if links && notes && starts(b,at,"[^"), let close = first(b,93,at+2) {
                    let name = lower(part(b,at+2,close))
                    if footnotes[name] != nil {
                        pieces.append(Piece(html: noteReference(name)))
                        at = close+1
                        continue
                    }
                }
                let image = c == 33, opening = at + (c == 33 ? 1 : 0)
                if image || links, let close = closingBracket(b,opening) {
                    let content = part(b,opening+1,close)
                    if let (reference,end) = destination(b,close+1,content) {
                        let body = inline(content,links: false,notes: false), url = escape(reference.url)
                        let title = reference.title.map {
                            " title=\"\(escape($0))\""
                        } ?? ""
                        let html = image ? "<img src=\"\(url)\" alt=\"\(stripTags(body))\"\(title) />" : "<a href=\"\(url)\"\(title)>\(body)</a>"
                        pieces.append(Piece(html: html))
                        at = end
                        continue
                    }
                }
            }
            if [UInt8(42),95,126].contains(c) {
                let end = runEnd(b,at), n = end-at, before: UInt8 = at == 0 ? 32 : b[at-1], after: UInt8 = end == b.count ? 32 : b[end]
                var open = !white(after), close = !white(before)
                if c == 95 && alnum(before) && alnum(after) {
                    open = false
                    close = false
                }
                if (c != 126 && n <= 3) || (c == 126 && n == 2) {
                    pieces.append(Piece(delimiter: c,length: n,open: open,close: close))
                } else {
                    pieces.append(Piece(html: part(b,at,end)))
                }
                at = end
                continue
            }
            pieces.append(Piece(html: escape(string([c]))))
            at += 1
        }
        return emphasis(pieces)
    }

    func blocks(_ blocks: [Block]) -> String {
        var html = ""
        for block in blocks {
            html += render(block) + "\n"
        }
        return html
    }

    func render(_ block: Block) -> String {
        switch block {
            case let .heading(level,text): return heading(level,text)
            case let .paragraph(text): return "<p>\(inline(text))</p>"
            case .rule: return "<hr />"
            case .toc: return tocMarker
            case let .code(language,lines):
            let attribute = language.isEmpty ? "" : " class=\"language-\(escape(language))\""
            return "<pre><code\(attribute)>" + lines.map {
                escape($0) + "\n"
            }.joined() + "</code></pre>"
            case let .quote(content): return "<blockquote>\n\(blocks(content))</blockquote>"
            case let .alert(kind,content):
            let name = lower(kind), title = String(kind.prefix(1)) + String(name.dropFirst())
            return "<div class=\"alert alert-\(name)\">\n<p class=\"alert-title\">\(title)</p>\n\(blocks(content))</div>"
            case let .list(start,items):
            let tag = start == nil ? "ul" : "ol", attribute = start.flatMap {
                $0 == 1 ? nil : " start=\"\($0)\""
            } ?? ""
            return "<\(tag)\(attribute)>\n" + items.map {
                item($0) + "\n"
            }.joined() + "</\(tag)>"
            case let .table(align,header,rows):
            var html = "<table>\n<thead>\n<tr>\n" + tableCells("th",align,header) + "</tr>\n</thead>\n"
            if !rows.isEmpty {
                html += "<tbody>\n"
                for row in rows {
                    html += "<tr>\n" + tableCells("td",align,row) + "</tr>\n"
                }
                html += "</tbody>\n"
            }
            return html + "</table>"
        }
    }

    func item(_ blocks: [Block]) -> String {
        var html = "<li>"
        for (i,block) in blocks.enumerated() {
            if case let .paragraph(text) = block {
                let task = i == 0 && text.utf8.count > 4 && ["[ ] ","[x] ","[X] "].contains {
                    text.hasPrefix($0)
                }
                if task {
                    html += text.hasPrefix("[ ] ") ? "<input type=\"checkbox\" disabled=\"\" /> " : "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> "
                }
                html += inline(task ? String(text.dropFirst(4)) : text)
            } else {
                if !html.hasSuffix("\n") {
                    html += "\n"
                }
                html += render(block) + "\n"
            }
        }
        return html + "</li>"
    }

    func tableCells(_ tag: String, _ align: [String], _ cells: [String]) -> String {
        var html = ""
        for (i,cell) in cells.enumerated() {
            let style = align[i].isEmpty ? "" : " style=\"text-align:\(align[i])\""
            html += "<\(tag)\(style)>\(inline(cell))</\(tag)>\n"
        }
        return html
    }

    func heading(_ level: Int, _ source: String) -> String {
        var text = source, id: String? = nil
        if source.hasSuffix("}"), let range = source.range(of: " {#",options: .backwards) {
            let candidate = String(source[range.upperBound..<source.index(before: source.endIndex)])
            if !candidate.isEmpty && candidate.utf8.allSatisfy(label) {
                id = candidate
                text = rightTrim(String(source[..<range.lowerBound]))
            }
        }
        if id == nil {
            var base = string(ascii(lower(source)).compactMap {
                label($0) ? $0 : (white($0) ? UInt8(45) : nil)
            })
            if base.isEmpty {
                base = "heading"
            }
            var candidate = base, suffix = 1
            while usedIds.contains(candidate) {
                candidate = "\(base)-\(suffix)"
                suffix += 1
            }
            id = candidate
        }
        let identifier = id!
        usedIds.insert(identifier)
        let html = inline(text)
        headings.append(HeadingEntry(level: level,id: identifier,text: stripTags(html)))
        return "<h\(level) id=\"\(identifier)\">\(html)</h\(level)>"
    }

    func tocList(_ children: [[Int]], _ entries: [Int]) -> String {
        var html = "<ul>\n"
        for i in entries {
            let heading = headings[i]
            html += "<li><a href=\"#\(heading.id)\">\(heading.text)</a>"
            if !children[i].isEmpty {
                html += "\n" + tocList(children,children[i]) + "\n"
            }
            html += "</li>\n"
        }
        return html + "</ul>"
    }

    func toc() -> String {
        if headings.isEmpty {
            return "<nav class=\"toc\">\n</nav>"
        }
        var roots: [Int] = [], parents: [Int] = [], children = Array(repeating: [Int](),count: headings.count)
        for (i,heading) in headings.enumerated() {
            while let p = parents.last, headings[p].level >= heading.level {
                parents.removeLast()
            }
            if let p = parents.last {
                children[p].append(i)
            } else {
                roots.append(i)
            }
            parents.append(i)
        }
        return "<nav class=\"toc\">\n" + tocList(children,roots) + "\n</nav>"
    }

    func referenceId(_ index: Int, _ count: Int) -> String {
        "fnref-\(index+1)" + (count == 1 ? "" : "-\(count)")
    }

    func noteReference(_ name: String) -> String {
        let index: Int
        if let number = noteNumbers[name] {
            index = number
        } else {
            index = noteNames.count
            noteNumbers[name] = index
            noteNames.append(name)
            noteCounts.append(0)
        }
        noteCounts[index] += 1
        return "<sup id=\"\(referenceId(index,noteCounts[index]))\"><a href=\"#fn-\(index+1)\">\(index+1)</a></sup>"
    }

    func noteList() -> String {
        var html = "<section class=\"footnotes\">\n<ol>\n"
        for i in noteNames.indices {
            let body = inline(footnotes[noteNames[i]]!,notes: false)
            html += "<li id=\"fn-\(i+1)\">\(body)"
            for count in 1...noteCounts[i] {
                html += " <a href=\"#\(referenceId(i,count))\">&#8617;</a>"
            }
            html += "</li>\n"
        }
        return html + "</ol>\n</section>\n"
    }

    func document(_ blocks: [Block]) -> String {
        // Resolve each TOC only after all heading IDs and labels are known.
        let html = self.blocks(blocks)
        var result = html.replacingOccurrences(of: tocMarker,with: toc())
        if !noteNames.isEmpty {
            result += noteList()
        }
        return result
    }
}
var lines: [String] = []
while let line = readLine(), line != "@@END@@" {
    lines.append(line)
}
let parser = Parser()
let blocks = parser.parse(lines)
let renderer = Renderer(parser)
FileHandle.standardOutput.write(Data(renderer.document(blocks).utf8))
