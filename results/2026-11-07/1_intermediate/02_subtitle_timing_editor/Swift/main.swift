import Foundation

struct Cue {
    var index: Int
    var start: Int
    var end: Int
    var text: [String]
    var duration: Int { end-start }
    var chars: Int { text.reduce(0) { $0+$1.count } }
    var dialogue: Bool { text.contains { $0.hasPrefix("- ") } }
}
struct Undo {
    let command: String
    let cues: [Cue]
}
struct Item {
    let text: String
    let kind: Int
    let digit: Int
}
struct Problem: Error {
    let message: String
}

final class Editor {
    var cues: [Cue] = []
    var history: [Undo] = []
    let schemas = [
        "LIST":"", "VALIDATE":"", "SEARCH":"X", "AT":"T", "GAPS":"g", "STATS":"",
        "PRINT":"", "TOVTT":"", "TOASS":"", "FRAMES":"F", "SHIFT":"I", "SHIFTFROM":"PI",
        "SCALE":"rr", "SYNC":"PTPT", "SNAP":"F", "FIXOVERLAP":"g", "EXTEND":"e", "TIME":"PTT",
        "SORT":"", "RENUMBER":"", "MERGE":"g", "SPLIT":"w", "INSERT":"PTTX", "DELETE":"P",
        "TEXT":"PX", "BALANCE":"", "STRIP":"", "CLEANHI":"", "REPLACE":"X", "UNDO":""
    ]
    let modifying: Set<String> = ["SHIFT","SHIFTFROM","SCALE","SYNC","SNAP","FIXOVERLAP","EXTEND",
        "TIME","SORT","RENUMBER","MERGE","SPLIT","INSERT","DELETE","TEXT","BALANCE","STRIP","CLEANHI","REPLACE"]

    func bad() -> Problem { Problem(message: "bad arguments") }
    func sub(_ s: String, _ start: Int, _ end: Int? = nil) -> String {
        String(s.dropFirst(start).prefix((end ?? s.count)-start))
    }
    func number(_ s: String) throws -> Int {
        guard (1...9).contains(s.count) && s.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
            throw bad()
        }
        return Int(s)!
    }
    func time(_ s: String) throws -> Int {
        let c = Array(s)
        guard c.count == 12 && c[2] == ":" && c[5] == ":" && c[8] == "," else {
            throw bad()
        }
        for i in [0,1,3,4,6,7,9,10,11] {
            guard c[i] >= "0" && c[i] <= "9" else { throw bad() }
        }
        let hours = Int(sub(s,0,2))!
        let minutes = Int(sub(s,3,5))!
        let seconds = Int(sub(s,6,8))!
        guard minutes <= 59 && seconds <= 59 else { throw bad() }
        return hours*3600000+minutes*60000+seconds*1000+Int(sub(s,9))!
    }
    func fps(_ s: String) throws -> (Int,Int) {
        let pieces = s.components(separatedBy: "/")
        guard pieces.count <= 2 else { throw bad() }
        let a = try number(pieces[0])
        let b: Int
        if pieces.count == 2 {
            b = try number(pieces[1])
        } else {
            b = 1
        }
        guard (1...100000).contains(a) && (1...100000).contains(b) else { throw bad() }
        return (a,b)
    }
    func text(_ s: String) throws -> [String] {
        let lines = s.components(separatedBy: "|")
        guard lines.allSatisfy({ !$0.isEmpty }) else { throw bad() }
        return lines
    }
    func srt(_ t: Int) -> String {
        String(format: "%02ld:%02ld:%02ld,%03ld",locale: Locale(identifier: "en_US_POSIX"),t/3600000,t/60000%60,t/1000%60,t%1000)
    }
    func ass(_ t: Int) -> String {
        let c = (t+5)/10
        return String(format: "%ld:%02ld:%02ld.%02ld",locale: Locale(identifier: "en_US_POSIX"),c/360000,c/6000%60,c/100%60,c%100)
    }
    func decimal(_ v: Int) -> String {
        String(format: "%ld.%02ld",locale: Locale(identifier: "en_US_POSIX"),v/100,v%100)
    }
    func round(_ numerator: Int, _ denominator: Int) -> Int {
        let a = denominator < 0 ? -numerator : numerator
        let b = abs(denominator)
        let n = 2*a+b
        let d = 2*b
        return n/d-(n%d < 0 ? 1 : 0)
    }
    func words(_ lines: [String]) -> [String] {
        lines.joined(separator: " ").split(separator: " ").map(String.init)
    }
    func normalize(_ s: String) -> String { words([s]).joined(separator: " ") }
    func wrap(_ lines: [String], _ width: Int) -> [String] {
        var result: [String] = []
        for word in words(lines) {
            if result.isEmpty || result.last!.count+1+word.count > width {
                result.append(word)
            } else {
                result[result.count-1] += " "+word
            }
        }
        return result
    }
    func markup(_ line: String) -> [Item] {
        line.matches(of: #/</?[ibu]>|</font>|<font(?=[ >])[^>]*>|\{\\an[1-9]\}|./#).map {
            let text = String($0.output)
            let kind = text.hasPrefix("{\\an") ? 3 :
                (text.hasPrefix("<font") || text == "</font>" ? 2 : (text.count > 1 ? 1 : 0))
            return Item(text: text,kind: kind,digit: kind == 3 ? Int(String(text.dropFirst(4).first!))! : 0)
        }
    }
    func listing(_ p: Int, _ c: Cue) -> String {
        "\(p) \(c.index) \(srt(c.start)) \(srt(c.end)) "+c.text.joined(separator: "|")
    }
    func load(_ blocks: [[String]]) -> [String] {
        var output: [String] = []
        var badCount = 0
        for (i,block) in blocks.enumerated() {
            var reason = ""
            var start = 0
            var end = 0
            if !(1...6).contains(block[0].count) || !block[0].allSatisfy({ $0 >= "0" && $0 <= "9" }) {
                reason = "index"
            } else {
                do {
                    guard block.count >= 2 && block[1].count == 29 && sub(block[1],12,17) == " --> " else {
                        throw bad()
                    }
                    start = try time(sub(block[1],0,12))
                    end = try time(sub(block[1],17))
                } catch {
                    reason = "time"
                }
                if reason.isEmpty && block.count < 3 { reason = "no text" }
            }
            if !reason.isEmpty {
                output.append("BAD CUE \(i+1): "+reason)
                badCount += 1
            } else {
                cues.append(Cue(index: Int(block[0])!,start: start,end: end,text: Array(block.dropFirst(2))))
            }
        }
        output.append("LOAD cues=\(cues.count) bad=\(badCount)")
        return output
    }
    func execute(_ line: String) throws -> [String] {
        let command = String(line.split(separator: " ",maxSplits: 1)[0])
        guard var schema = schemas[command] else { throw Problem(message: "unknown command") }
        if command == "DELETE" && line.split(separator: " ").count == 3 { schema = "PP" }
        let tokens = schema.hasSuffix("X") ?
            line.split(separator: " ",maxSplits: schema.count,omittingEmptySubsequences: false).map(String.init) :
            line.components(separatedBy: " ")
        guard tokens.count == schema.count+1 else { throw bad() }
        let args = Array(tokens.dropFirst())
        let types = Array(schema)
        var values = Array(repeating: 0,count: args.count)
        for i in args.indices {
            let type = types[i]
            let arg = args[i]
            if type == "T" { values[i] = try time(arg) }
            else if type == "F" { _ = try fps(arg) }
            else if type == "X" {
                if command == "INSERT" || command == "TEXT" { _ = try text(arg) }
                if command == "REPLACE" {
                    let pieces = arg.components(separatedBy: "|")
                    guard pieces.count == 2 && pieces.allSatisfy({ !$0.isEmpty }) else { throw bad() }
                }
            } else {
                let negative = type == "I" && arg.hasPrefix("-")
                values[i] = try number(negative ? sub(arg,1) : arg)*(negative ? -1 : 1)
                let v = values[i]
                if (type == "P" && v < 1) || (type == "r" && !(1...100000).contains(v)) ||
                    (type == "g" && v > 60000) || (type == "e" && !(1...60000).contains(v)) ||
                    (type == "w" && !(10...80).contains(v)) { throw bad() }
            }
        }
        if command == "DELETE" && values.count == 2 && values[1] < values[0] { throw bad() }
        for i in args.indices {
            if types[i] == "P" && values[i] > cues.count+(command == "INSERT" ? 1 : 0) {
                throw Problem(message: "no cue \(values[i])")
            }
        }
        if command == "SYNC" && cues[values[0]-1].start == cues[values[2]-1].start {
            throw Problem(message: "sync points coincide")
        }
        if command == "UNDO" {
            guard let undo = history.popLast() else { throw Problem(message: "nothing to undo") }
            cues = undo.cues
            return ["UNDO command="+undo.command]
        }
        if modifying.contains(command) { history.append(Undo(command: command,cues: cues)) }
        var output: [String] = []
        let n = cues.count
        let v = values.first ?? 0
        switch command {
        case "LIST", "AT", "SEARCH", "GAPS":
            var count = 0
            for (i,c) in cues.enumerated() {
                if command == "LIST" || (command == "AT" && c.start <= v && v < c.end) {
                    output.append(listing(i+1,c))
                    count += 1
                }
                if command == "SEARCH", let found = c.text.first(where: { $0.contains(args[0]) }) {
                    output.append("\(i+1) \(srt(c.start)) "+found)
                    count += 1
                }
                if command == "GAPS" && i+1 < n && cues[i+1].start-c.end < v {
                    output.append("\(i+1) \(i+2) \(cues[i+1].start-c.end)")
                    count += 1
                }
            }
            if command != "LIST" {
                let label = command == "AT" ? "active" : (command == "SEARCH" ? "found" : "count")
                output.append(command+" "+label+"=\(count)")
            }
        case "VALIDATE":
            for (i,c) in cues.enumerated() {
                let d = c.duration
                let p = "cue \(i+1): "
                if c.index != i+1 { output.append(p+"index \(c.index) (expected \(i+1))") }
                if d <= 0 { output.append(p+"end not after start") }
                if i > 0 && c.start < cues[i-1].end { output.append(p+"overlaps previous by \(cues[i-1].end-c.start) ms") }
                if d > 0 && d < 700 { output.append(p+"too short (\(d) ms)") }
                if d > 7000 { output.append(p+"too long (\(d) ms)") }
                for (j,t) in c.text.enumerated() {
                    if t.count > 42 { output.append(p+"line \(j+1) too long (\(t.count) chars)") }
                }
                if c.text.count >= 3 { output.append(p+"too many lines (\(c.text.count))") }
                if d > 0 && c.chars*1000 > 21*d {
                    output.append(p+"too fast (\(decimal(c.chars*100000/d)) cps)")
                }
            }
            output.append("VALIDATE problems=\(output.count)")
        case "STATS":
            output.append("STATS cues=\(n)")
            if n > 0 {
                let durations = cues.map { max(0,$0.duration) }
                let total = durations.reduce(0,+)
                let chars = cues.filter { $0.duration > 0 }.reduce(0) { $0+$1.chars }
                let longest = durations.max()!
                output.append("duration total=\(srt(total)) mean=\(srt(total/n))")
                output.append("speed "+(total == 0 ? "-" : decimal(chars*100000/total)))
                output.append("longest cue=\(durations.firstIndex(of: longest)!+1) duration=\(srt(longest))")
                if n == 1 { output.append("gap none") }
                else {
                    let gaps = (0..<(n-1)).map { cues[$0+1].start-cues[$0].end }
                    let gap = gaps.max()!
                    output.append("gap cue=\(gaps.firstIndex(of: gap)!+1) ms=\(gap)")
                }
            }
        case "PRINT", "TOVTT", "TOASS":
            if command == "TOVTT" { output += ["WEBVTT",""] }
            if command == "TOASS" { output += ["[Events]","Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"] }
            for c in cues {
                var code = 0
                var lines: [String] = []
                for t in c.text {
                    var converted = ""
                    for item in markup(t) {
                        if code == 0 && item.kind == 3 { code = item.digit }
                        if command == "PRINT" { converted += item.text }
                        else if command == "TOASS" {
                            if item.kind == 1 {
                                let closing = item.text.hasPrefix("</")
                                let tag = Array(item.text)[closing ? 2 : 1]
                                converted += "{\\\(tag)\(closing ? 0 : 1)}"
                            } else if item.kind != 2 { converted += item.text }
                        } else if item.kind == 1 { converted += item.text }
                        else if item.kind == 0 {
                            switch item.text {
                            case "&": converted += "&amp;"
                            case "<": converted += "&lt;"
                            case ">": converted += "&gt;"
                            default: converted += item.text
                            }
                        }
                    }
                    if command == "TOVTT" { converted = converted.trimmingCharacters(in: CharacterSet(charactersIn: " ")) }
                    if command != "TOVTT" || !converted.isEmpty { lines.append(converted) }
                }
                if command == "TOASS" {
                    output.append("Dialogue: 0,\(ass(c.start)),\(ass(c.end)),Default,,0,0,0,,"+lines.joined(separator: "\\N"))
                } else if !lines.isEmpty {
                    var settings = ""
                    if command == "TOVTT" && code != 0 {
                        if code >= 7 { settings += " line:0" }
                        else if code >= 4 { settings += " line:50%" }
                        if code%3 == 1 { settings += " align:start" }
                        if code%3 == 0 { settings += " align:end" }
                    }
                    output.append(String(c.index))
                    let times = "\(srt(c.start)) --> \(srt(c.end))"
                    output.append((command == "TOVTT" ? times.replacingOccurrences(of: ",",with: ".") : times)+settings)
                    output += lines
                    output.append("")
                }
            }
        case "FRAMES":
            let (a,b) = try fps(args[0])
            for (i,c) in cues.enumerated() { output.append("\(i+1) \(c.start*a/(1000*b)) \(c.end*a/(1000*b))") }
        case "SHIFT", "SHIFTFROM", "SCALE", "SYNC", "SNAP":
            let first = command == "SHIFTFROM" ? v-1 : 0
            let delta = command == "SHIFTFROM" ? values[1] : v
            let s1 = command == "SYNC" ? cues[v-1].start : 0
            let s2 = command == "SYNC" ? cues[values[2]-1].start : 0
            let rate: (Int,Int)
            if command == "SNAP" {
                rate = try fps(args[0])
            } else {
                rate = (1,1)
            }
            let (a,b) = rate
            var clamped = 0
            var changed = 0
            for i in first..<n {
                var c = cues[i]
                var times = [c.start,c.end]
                var clamp = false
                for j in times.indices {
                    let old = times[j]
                    let next: Int
                    switch command {
                    case "SCALE": next = round(old*v,values[1])
                    case "SYNC": next = round(values[1]*(s2-s1)+(old-s1)*(values[3]-values[1]),s2-s1)
                    case "SNAP": next = round(round(old*a,1000*b)*1000*b,a)
                    default: next = old+delta
                    }
                    if next < 0 { clamp = true }
                    times[j] = max(0,next)
                    if times[j] != old { changed += 1 }
                }
                if clamp { clamped += 1 }
                c.start = times[0]
                c.end = times[1]
                cues[i] = c
            }
            output.append(command == "SNAP" ? "SNAP changed=\(changed)" :
                command+" cues=\(n-first)"+(command == "SCALE" ? "" : " clamped=\(clamped)"))
        case "FIXOVERLAP", "EXTEND":
            var changed = 0
            var failed = 0
            for i in cues.indices {
                var c = cues[i]
                if command == "FIXOVERLAP" && i+1 < n && c.end > cues[i+1].start-v {
                    let candidate = cues[i+1].start-v
                    if candidate > c.start {
                        c.end = candidate
                        changed += 1
                    } else {
                        output.append("cue \(i+1): cannot fix")
                        failed += 1
                    }
                }
                if command == "EXTEND" && c.duration < v {
                    let candidate = i+1 < n ? min(c.start+v,cues[i+1].start) : c.start+v
                    if candidate > c.end {
                        c.end = candidate
                        changed += 1
                    }
                }
                cues[i] = c
            }
            output.append(command == "FIXOVERLAP" ? "FIXOVERLAP fixed=\(changed) failed=\(failed)" :
                "EXTEND extended=\(changed) short=\(cues.filter { $0.duration < v }.count)")
        case "TIME":
            cues[v-1].start = values[1]
            cues[v-1].end = values[2]
            output.append("TIME cue=\(v)")
        case "SORT":
            let ordered = cues.enumerated().sorted {
                if $0.element.start != $1.element.start { return $0.element.start < $1.element.start }
                if $0.element.end != $1.element.end { return $0.element.end < $1.element.end }
                return $0.offset < $1.offset
            }
            let moved = ordered.enumerated().filter { $0.offset != $0.element.offset }.count
            cues = ordered.map { $0.element }
            output.append("SORT moved=\(moved)")
        case "RENUMBER":
            var changed = 0
            for i in cues.indices {
                if cues[i].index != i+1 { changed += 1 }
                cues[i].index = i+1
            }
            output.append("RENUMBER changed=\(changed)")
        case "MERGE":
            var result: [Cue] = []
            var merged = 0
            for b in cues {
                if var a = result.last, b.start-a.end < v && !a.dialogue && !b.dialogue {
                    let wrapped = wrap(a.text+b.text,42)
                    if wrapped.count <= 2 {
                        a.end = max(a.end,b.end)
                        a.text = wrapped
                        result[result.count-1] = a
                        merged += 1
                        continue
                    }
                }
                result.append(b)
            }
            cues = result
            output.append("MERGE merged=\(merged) cues=\(cues.count)")
        case "SPLIT":
            var result: [Cue] = []
            var split = 0
            for var c in cues {
                if c.duration <= 0 || c.dialogue {
                    result.append(c)
                    continue
                }
                let wrapped = wrap(c.text,v)
                if wrapped.count <= 2 {
                    c.text = wrapped
                    result.append(c)
                    continue
                }
                split += 1
                var parts: [[String]] = []
                for i in stride(from: 0,to: wrapped.count,by: 2) {
                    parts.append(Array(wrapped[i..<min(i+2,wrapped.count)]))
                }
                let counts = parts.map { $0.reduce(0) { $0+$1.count } }
                let total = counts.reduce(0,+)
                var durations = counts.map { c.duration*$0/total }
                let order = parts.indices.sorted {
                    let a = c.duration*counts[$0]%total
                    let b = c.duration*counts[$1]%total
                    return a == b ? $0 < $1 : a > b
                }
                let remainder = c.duration-durations.reduce(0,+)
                for i in 0..<remainder { durations[order[i]] += 1 }
                var start = c.start
                for i in parts.indices {
                    result.append(Cue(index: c.index,start: start,end: start+durations[i],text: parts[i]))
                    start += durations[i]
                }
            }
            cues = result
            output.append("SPLIT split=\(split) cues=\(cues.count)")
        case "INSERT":
            cues.insert(Cue(index: v,start: values[1],end: values[2],text: try text(args[3])),at: v-1)
            output.append("INSERT cue=\(v) cues=\(cues.count)")
        case "DELETE":
            let last = values.count == 2 ? values[1] : v
            cues.removeSubrange((v-1)..<last)
            output.append("DELETE removed=\(last-v+1) cues=\(cues.count)")
        case "TEXT":
            let lines = try text(args[1])
            cues[v-1].text = lines
            output.append("TEXT cue=\(v) lines=\(lines.count)")
        case "BALANCE":
            var changed = 0
            var skipped = 0
            var dialogue = 0
            for i in cues.indices {
                var c = cues[i]
                if c.dialogue {
                    dialogue += 1
                    continue
                }
                let tokens = words(c.text)
                let joined = tokens.joined(separator: " ")
                var best: [String]? = joined.count <= 42 ? [joined] : nil
                var difference = Int.max
                var firstLength = Int.max
                if joined.count > 42 && tokens.count > 1 {
                    for j in 1..<tokens.count {
                        let a = tokens.prefix(j).joined(separator: " ")
                        let b = tokens.dropFirst(j).joined(separator: " ")
                        let d = abs(a.count-b.count)
                        if a.count <= 42 && b.count <= 42 && (d < difference || (d == difference && a.count < firstLength)) {
                            best = [a,b]
                            difference = d
                            firstLength = a.count
                        }
                    }
                }
                if let best {
                    if best != c.text {
                        changed += 1
                        c.text = best
                        cues[i] = c
                    }
                } else { skipped += 1 }
            }
            output.append("BALANCE changed=\(changed) skipped=\(skipped) dialogue=\(dialogue)")
        case "STRIP", "CLEANHI":
            var result: [Cue] = []
            var tags = 0
            var segments = 0
            var labels = 0
            var removed = 0
            for var c in cues {
                var lines: [String] = []
                for t in c.text {
                    var cleaned = ""
                    if command == "STRIP" {
                        for item in markup(t) {
                            if item.kind == 0 { cleaned += item.text }
                            else { tags += 1 }
                        }
                        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " "))
                    } else {
                        let chars = Array(t)
                        var p = 0
                        while p < chars.count {
                            let closer: Character? = chars[p] == "[" ? "]" : (chars[p] == "(" ? ")" : nil)
                            if let closer, let end = chars[(p+1)...].firstIndex(of: closer) {
                                segments += 1
                                p = end+1
                            } else {
                                cleaned.append(chars[p])
                                p += 1
                            }
                        }
                        cleaned = normalize(cleaned)
                        let prefix = cleaned.hasPrefix("- ") ? "- " : ""
                        let body = sub(cleaned,prefix.count)
                        let bodyChars = Array(body)
                        if let colon = bodyChars.firstIndex(of: ":"), colon > 0 {
                            let name = Array(bodyChars[..<colon])
                            if name[0] >= "A" && name[0] <= "Z" && name.allSatisfy({
                                ($0 >= "A" && $0 <= "Z") || ($0 >= "0" && $0 <= "9") || $0 == " "
                            }) {
                                labels += 1
                                cleaned = normalize(prefix+String(bodyChars[(colon+1)...]))
                            }
                        }
                    }
                    if cleaned.isEmpty || (command == "CLEANHI" && cleaned == "-") { removed += 1 }
                    else { lines.append(cleaned) }
                }
                if !lines.isEmpty {
                    c.text = lines
                    result.append(c)
                }
            }
            let removedCues = n-result.count
            cues = result
            output.append(command == "STRIP" ? "STRIP tags=\(tags) removed_lines=\(removed) removed_cues=\(removedCues)" :
                "CLEANHI segments=\(segments) labels=\(labels) removed_lines=\(removed) removed_cues=\(removedCues)")
        case "REPLACE":
            let parts = args[0].components(separatedBy: "|")
            let old = parts[0]
            let replacement = parts[1]
            var count = 0
            var changed = 0
            for i in cues.indices {
                var c = cues[i]
                let before = count
                c.text = c.text.map { t in
                    let pieces = t.components(separatedBy: old)
                    count += pieces.count-1
                    return pieces.joined(separator: replacement)
                }
                if count > before { changed += 1 }
                cues[i] = c
            }
            output.append("REPLACE count=\(count) cues=\(changed)")
        default:
            preconditionFailure("Unreachable command")
        }
        return output
    }
}

var blocks: [[String]] = []
var block: [String] = []
while let line = readLine(), line != "###" {
    if line.isEmpty {
        if !block.isEmpty { blocks.append(block) }
        block = []
    } else { block.append(line) }
}
if !block.isEmpty { blocks.append(block) }
let editor = Editor()
for line in editor.load(blocks) { print(line) }
let count = Int(readLine()!)!
for _ in 0..<count {
    do {
        for line in try editor.execute(readLine()!) { print(line) }
    } catch let problem as Problem {
        print("ERROR "+problem.message)
    } catch {
        preconditionFailure("Unexpected error")
    }
}
