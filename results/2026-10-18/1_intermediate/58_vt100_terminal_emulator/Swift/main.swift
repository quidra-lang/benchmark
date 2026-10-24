import Foundation

struct Attributes: Equatable {
    var flags = 0
    var fg = "default"
    var bg = "default"
}
struct Cell {
    var character: Character = " "
    var attributes = Attributes()
}
struct Saved {
    let row: Int, col: Int
    let attributes: Attributes
    let origin: Bool, g0: Bool, g1: Bool, gl: Bool
}
enum ParserState { case ground, escape, escapeIntermediate, csiEntry, csiParam, csiIntermediate, csiIgnore, osc }

final class Terminal {
    let width: Int, height: Int
    let irm = 0, lnm = 1, ckm = 2, scnm = 3, origin = 4, wrap = 5, visible = 6, keypad = 7, bracketed = 8
    var screens: [[[Cell]]] = []
    var screen = 0, row = 1, col = 1, top = 1, bottom = 1, shape = 1
    var pending = false, g0 = false, g1 = false, gl = false
    var modes = Array(repeating: false, count: 9)
    var tabs = Set<Int>()
    var saved: [Saved?] = [nil, nil]
    var scrollback: [String] = []
    var title: String?
    var last: Character?
    var attributes = Attributes()
    var parser = ParserState.ground
    var marker = "", parameters = "", intermediate = "", osc = ""
    var bytes = 0, printed = 0, sequences = 0, bells = 0, replies = 0, dumps = 0
    var ignored = [0, 0, 0, 0]

    init(_ width: Int, _ height: Int) { self.width = width; self.height = height; reset() }
    func blankRow() -> [Cell] { Array(repeating: Cell(), count: width) }
    func blankScreen() -> [[Cell]] { Array(repeating: blankRow(), count: height) }
    func reset() {
        screens = [blankScreen(), blankScreen()]
        screen = 0; row = 1; col = 1; top = 1; bottom = height; shape = 1
        pending = false; attributes = Attributes(); modes = Array(repeating: false, count: 9)
        modes[wrap] = true; modes[visible] = true
        g0 = false; g1 = false; gl = false; saved = [nil, nil]
        tabs = Set(stride(from: 9, through: width, by: 8))
        scrollback = []; title = nil; last = nil
        parser = .ground; marker = ""; parameters = ""; intermediate = ""; osc = ""
    }
    func rowText(_ cells: [Cell]) -> String {
        var chars = cells.map(\.character)
        while chars.last == " " { chars.removeLast() }
        return String(chars)
    }
    func erase(_ r: Int, _ first: Int, _ end: Int) {
        if first > end { return }
        for c in first...end { screens[screen][r-1][c-1] = Cell() }
    }
    func scroll(_ up: Bool, _ count: Int) {
        for _ in 0..<count {
            if up {
                if screen == 0 && top == 1 {
                    scrollback.append(rowText(screens[0][top-1]))
                    if scrollback.count > 100 { scrollback.removeFirst() }
                }
                for r in top..<bottom { screens[screen][r-1] = screens[screen][r] }
                screens[screen][bottom-1] = blankRow()
            } else {
                for r in stride(from: bottom, through: top+1, by: -1) { screens[screen][r-1] = screens[screen][r-2] }
                screens[screen][top-1] = blankRow()
            }
        }
    }
    func lineFeed() {
        if row == bottom { scroll(true, 1) }
        else if row < height { row += 1 }
    }
    func tab(_ reverse: Bool) {
        col = reverse ? (tabs.filter { $0 < col }.max() ?? 1) : (tabs.filter { $0 > col }.min() ?? width)
    }
    func address(_ n: Int) -> Int { modes[origin] ? min(top+n-1, bottom) : min(n, height) }
    func home() { row = address(1); col = 1 }
    func save() { saved[screen] = Saved(row: row, col: col, attributes: attributes, origin: modes[origin], g0: g0, g1: g1, gl: gl) }
    func restore() {
        if let s = saved[screen] {
            row = s.row; col = s.col; attributes = s.attributes; modes[origin] = s.origin
            g0 = s.g0; g1 = s.g1; gl = s.gl
        } else {
            row = 1; col = 1; attributes = Attributes(); modes[origin] = false
            g0 = false; g1 = false; gl = false
        }
        pending = false
    }
    func write(_ ch: Character) {
        printed += 1; last = ch
        if pending { pending = false; col = 1; lineFeed() }
        if modes[irm] {
            for c in stride(from: width-1, through: col, by: -1) { screens[screen][row-1][c] = screens[screen][row-1][c-1] }
        }
        screens[screen][row-1][col-1] = Cell(character: ch, attributes: attributes)
        if col < width { col += 1 } else if modes[wrap] { pending = true }
    }
    func printCharacter(_ character: Character) {
        var ch = character
        if gl ? g1 : g0 {
            switch ch {
            case "`": ch = "*"
            case "a": ch = "#"
            case "q": ch = "-"
            case "x": ch = "|"
            case "~": ch = "o"
            case "j", "k", "l", "m", "n", "t", "u", "v", "w": ch = "+"
            default: break
            }
        }
        write(ch)
    }
    func control(_ b: UInt8) {
        if b >= 8 && b <= 13 { pending = false }
        switch b {
        case 7: bells += 1
        case 8: col = max(1, col-1)
        case 9: tab(false)
        case 10...12: lineFeed(); if modes[lnm] { col = 1 }
        case 13: col = 1
        case 14: gl = true
        case 15: gl = false
        default: break
        }
    }
    func palette(_ n: Int) -> String {
        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
        if n < 8 { return names[n] }
        if n < 16 { return "bright-" + names[n-8] }
        return String(n)
    }
    func sgr(_ p: [Int]) -> Bool {
        var a = attributes, i = 0
        while i < p.count {
            let v = p[i]
            switch v {
            case 0: a = Attributes()
            case 1...5: a.flags |= 1 << (v-1)
            case 7...9: a.flags |= 1 << (v-2)
            case 22: a.flags &= ~3
            case 23...25: a.flags &= ~(1 << (v-21))
            case 27...29: a.flags &= ~(1 << (v-22))
            case 30...37: a.fg = palette(v-30)
            case 90...97: a.fg = palette(v-82)
            case 40...47: a.bg = palette(v-40)
            case 100...107: a.bg = palette(v-92)
            case 39: a.fg = "default"
            case 49: a.bg = "default"
            case 38, 48:
                let color: String
                if i+2 < p.count && p[i+1] == 5 && p[i+2] <= 255 {
                    color = palette(p[i+2]); i += 2
                } else if i+4 < p.count && p[i+1] == 2 && p[(i+2)...(i+4)].allSatisfy({ $0 <= 255 }) {
                    color = String(format: "#%02x%02x%02x", p[i+2], p[i+3], p[i+4]); i += 4
                } else { return false }
                if v == 38 { a.fg = color } else { a.bg = color }
            default: return false
            }
            i += 1
        }
        attributes = a
        return true
    }
    func modeIndex(_ p: Int, _ dec: Bool) -> Int? {
        if dec {
            switch p {
            case 1: return ckm
            case 5: return scnm
            case 6: return origin
            case 7: return wrap
            case 25: return visible
            case 2004: return bracketed
            default: return nil
            }
        }
        return p == 4 ? irm : p == 20 ? lnm : nil
    }
    func setModes(_ p: [Int], _ dec: Bool, _ on: Bool) -> Bool {
        if p.contains(where: { modeIndex($0, dec) == nil && !(dec && [47,1047,1048,1049].contains($0)) }) { return false }
        for v in p {
            if let index = modeIndex(v, dec) {
                modes[index] = on
                if index == origin { pending = false; home() }
                if index == wrap && !on { pending = false }
            } else if v == 1048 { if on { save() } else { restore() } }
            else {
                pending = false
                if on && screen == 0 {
                    if v == 1049 { save() }
                    screen = 1
                    if v == 1049 { screens[1] = blankScreen() }
                } else if !on && screen == 1 {
                    if v == 1047 { screens[1] = blankScreen() }
                    screen = 0
                    if v == 1049 { restore() }
                }
            }
        }
        return true
    }
    func executeOsc() {
        if osc.hasPrefix("0;") || osc.hasPrefix("2;") { title = String(osc.dropFirst(2)); sequences += 1 }
        else { ignored[0] += 1 }
    }
    func escape(_ final: Character) {
        let key = intermediate + String(final)
        switch key {
        case "7": save()
        case "8": restore()
        case "D", "E": pending = false; if final == "E" { col = 1 }; lineFeed()
        case "M": pending = false; if row == top { scroll(false, 1) } else { row = max(1, row-1) }
        case "H": tabs.insert(col)
        case "c": reset()
        case "=": modes[keypad] = true
        case ">": modes[keypad] = false
        case "\\": break
        case "(0": g0 = true
        case "(B": g0 = false
        case ")0": g1 = true
        case ")B": g1 = false
        case "#8":
            screens[screen] = Array(repeating: Array(repeating: Cell(character: "E"), count: width), count: height)
            top = 1; bottom = height; modes[origin] = false; row = 1; col = 1; pending = false
        default: ignored[0] += 1; return
        }
        sequences += 1
    }
    func reply(_ s: String) { replies += 1; print("REPLY " + s) }
    func csi(_ final: Character) {
        let fields = parameters.isEmpty ? [] : parameters.split(separator: ";", omittingEmptySubsequences: false)
        if fields.count >= 17 { ignored[3] += 1; return }
        var p = fields.map { field in field.utf8.reduce(0) { min(9999, $0*10+Int($1)-48) } }
        if p.isEmpty { p = [0] }
        let first = p[0], second = p.count > 1 ? p[1] : 0, n = max(first, 1)
        let key = marker + intermediate + String(final)
        if (key == "J" && first > 3) || (key == "K" && first > 2) || (key == "g" && first != 0 && first != 3)
            || (key == " q" && first > 6) || (key == "n" && first != 5 && first != 6) || (key == "?n" && first != 6)
            || (["c", ">c"].contains(key) && first != 0) || (key == "t" && first != 18) { ignored[0] += 1; return }
        if key.count == 1 && "ABCDEFGHIJKLMPSTXZ`adef@".contains(final) { pending = false }
        var supported = true
        switch key {
        case "A", "F": row = max(row-n, row >= top ? top : 1); if key == "F" { col = 1 }
        case "B", "e", "E": row = min(row+n, row <= bottom ? bottom : height); if key == "E" { col = 1 }
        case "C", "a": col = min(col+n, width)
        case "D": col = max(col-n, 1)
        case "G", "`": col = min(n, width)
        case "H", "f": row = address(n); col = min(max(second, 1), width)
        case "d": row = address(n)
        case "I", "Z": for _ in 0..<n { tab(key == "Z") }
        case "J":
            if first == 3 { scrollback = [] }
            else {
                for r in 1...height {
                    if first == 2 || (first == 0 && r > row) || (first == 1 && r < row) { erase(r, 1, width) }
                    else if r == row { erase(r, first == 0 ? col : 1, first == 1 ? col : width) }
                }
            }
        case "K": erase(row, first == 0 ? col : 1, first == 1 ? col : width)
        case "X": erase(row, col, min(col+n-1, width))
        case "@", "P":
            let amount = min(n, width-col+1)
            if key == "@" {
                for c in stride(from: width-1, through: col-1+amount, by: -1) { screens[screen][row-1][c] = screens[screen][row-1][c-amount] }
                erase(row, col, col+amount-1)
            } else {
                for c in (col-1)..<(width-amount) { screens[screen][row-1][c] = screens[screen][row-1][c+amount] }
                erase(row, width-amount+1, width)
            }
        case "L", "M":
            if row >= top && row <= bottom {
                let amount = min(n, bottom-row+1)
                if key == "L" {
                    for r in stride(from: bottom, through: row+amount, by: -1) { screens[screen][r-1] = screens[screen][r-amount-1] }
                    for r in row..<(row+amount) { screens[screen][r-1] = blankRow() }
                } else {
                    if row <= bottom-amount {
                        for r in row...(bottom-amount) { screens[screen][r-1] = screens[screen][r+amount-1] }
                    }
                    for r in (bottom-amount+1)...bottom { screens[screen][r-1] = blankRow() }
                }
                col = 1
            }
        case "S", "T": scroll(key == "S", min(n, bottom-top+1))
        case "b": if let ch = last { for _ in 0..<n { write(ch) } }
        case "g": if first == 0 { tabs.remove(col) } else { tabs = [] }
        case "m": supported = sgr(p)
        case "h", "l", "?h", "?l": supported = setModes(p, key.hasPrefix("?"), final == "h")
        case " q": shape = n
        case "r":
            let t = first == 0 ? 1 : first, b = min(second == 0 ? height : second, height)
            if t >= b { ignored[3] += 1; return }
            pending = false; top = t; bottom = b; home()
        case "s": save()
        case "u": restore()
        case "!p":
            pending = false; modes[irm] = false; modes[ckm] = false; modes[origin] = false; modes[keypad] = false
            modes[wrap] = true; modes[visible] = true; top = 1; bottom = height; attributes = Attributes()
            g0 = false; g1 = false; gl = false; saved[screen] = nil
        case "n": reply(first == 5 ? "^[[0n" : "^[[\(modes[origin] ? max(row-top+1, 1) : row);\(col)R")
        case "?n": reply("^[[?\(modes[origin] ? max(row-top+1, 1) : row);\(col);1R")
        case "c": reply("^[[?1;2c")
        case ">c": reply("^[[>0;95;0c")
        case "t": reply("^[[8;\(height);\(width)t")
        case "$p", "?$p":
            let dec = key.hasPrefix("?")
            let status: Int
            if let index = modeIndex(first, dec) { status = modes[index] ? 1 : 2 }
            else if dec && [47,1047,1049].contains(first) { status = screen == 1 ? 1 : 2 }
            else { status = 0 }
            reply("^[[\(dec ? "?" : "")\(first);\(status)$y")
        default: supported = false
        }
        if supported { sequences += 1 } else { ignored[0] += 1 }
    }
    func feed(_ b: UInt8) {
        bytes += 1
        if b == 27 {
            if parser == .osc { executeOsc() } else if parser != .ground { ignored[2] += 1 }
            marker = ""; parameters = ""; intermediate = ""; osc = ""; parser = .escape; return
        }
        if b == 24 || b == 26 { if parser != .ground { ignored[2] += 1 }; parser = .ground; return }
        if b < 32 {
            if parser == .osc { if b == 7 { executeOsc(); parser = .ground } }
            else { control(b) }
            return
        }
        let c = Character(UnicodeScalar(b))
        if parser == .csiEntry {
            parser = .csiParam
            if b >= 60 && b <= 63 { marker = String(c); return }
        }
        switch parser {
        case .ground: printCharacter(c)
        case .osc: osc.append(c)
        case .escape:
            if b <= 47 { intermediate.append(c); parser = .escapeIntermediate }
            else if c == "[" { parser = .csiEntry }
            else if c == "]" { parser = .osc }
            else { escape(c); parser = .ground }
        case .escapeIntermediate:
            if b <= 47 { intermediate.append(c) } else { escape(c); parser = .ground }
        case .csiParam:
            if (b >= 48 && b <= 57) || c == ";" { parameters.append(c) }
            else if b <= 47 { intermediate.append(c); parser = .csiIntermediate }
            else if b < 64 { parser = .csiIgnore }
            else { csi(c); parser = .ground }
        case .csiIntermediate:
            if b <= 47 { intermediate.append(c) }
            else if b < 64 { parser = .csiIgnore }
            else { csi(c); parser = .ground }
        case .csiIgnore: if b >= 64 { ignored[1] += 1; parser = .ground }
        case .csiEntry: break
        }
    }
    func dump(_ label: String) {
        print("\(label) \(screen == 0 ? "main" : "alt") cursor \(row),\(col) scrollback \(scrollback.count)\(pending ? " pending" : "")")
        for cells in screens[screen] { print("|" + rowText(cells)) }
    }
    func key(_ name: String) -> String {
        let nav = ["UP", "DOWN", "RIGHT", "LEFT", "HOME", "END"]
        if let index = nav.firstIndex(of: name) { return (modes[ckm] ? "^[O" : "^[[") + String(Array("ABCDHF")[index]) }
        if name.hasPrefix("F") {
            let f = Int(name.dropFirst())!
            if f <= 4 { return "^[O" + String(Character(UnicodeScalar(80+f-1)!)) }
            return "^[[\([15,17,18,19,20,21,23,24][f-5])~"
        }
        if name.hasPrefix("KP") && name.count == 3 {
            let digit = name.last!
            return modes[keypad] ? "^[O" + String(Character(UnicodeScalar(112+Int(String(digit))!)!)) : String(digit)
        }
        switch name {
        case "INSERT": return "^[[2~"
        case "DELETE": return "^[[3~"
        case "PAGEUP": return "^[[5~"
        case "PAGEDOWN": return "^[[6~"
        case "TAB": return "^I"
        case "BACKSPACE": return "^?"
        case "ESCAPE": return "^["
        case "KPENTER" where modes[keypad]: return "^[OM"
        default: return modes[lnm] ? "^M^J" : "^M"
        }
    }
    func directive(_ line: String) {
        if line == "%%DUMP" { dumps += 1; dump("DUMP \(dumps)") }
        else if line.hasPrefix("%%KEY ") { let name = String(line.dropFirst(6)); print("KEY \(name) \(key(name))") }
        else {
            let s = String(line.dropFirst(8)).replacingOccurrences(of: "^", with: "^^")
            print("PASTE " + (modes[bracketed] ? "^[[200~" + s + "^[[201~" : s))
        }
    }
    func attributeText(_ a: Attributes) -> String {
        let names = ["bold", "dim", "italic", "underline", "blink", "reverse", "hidden", "strike"]
        var parts = (0..<8).filter { a.flags & (1 << $0) != 0 }.map { names[$0] }
        if a.fg != "default" { parts.append("fg=" + a.fg) }
        if a.bg != "default" { parts.append("bg=" + a.bg) }
        return parts.joined(separator: " ")
    }
    func finish() {
        if parser != .ground { ignored[2] += 1 }
        dump("FINAL")
        print(title.map { "TITLE \"\($0)\"" } ?? "TITLE none")
        let names = ["IRM", "LNM", "DECCKM", "DECSCNM", "DECOM", "DECAWM", "DECTCEM", "DECKPAM", "BRACKETED"]
        var changes: [String] = []
        for i in 0..<9 where modes[i] != (i == wrap || i == visible) { changes.append(names[i] + (modes[i] ? "=on" : "=off")) }
        if g0 { changes.append("G0=graphics") }; if g1 { changes.append("G1=graphics") }; if gl { changes.append("GL=G1") }
        if shape != 1 { changes.append("CURSOR=\(shape)") }
        print("MODES " + (changes.isEmpty ? "default" : changes.joined(separator: " ")))
        print("REGION \(top)-\(bottom)")
        print("TABS " + (tabs.isEmpty ? "none" : tabs.sorted().map(String.init).joined(separator: ",")))
        print("SCROLLBACK \(scrollback.count)")
        for s in scrollback.suffix(5) { print("|" + s) }
        var runs: [String] = []
        for r in 0..<height {
            var c = 0
            while c < width {
                let a = screens[screen][r][c].attributes
                var end = c+1
                while end < width && screens[screen][r][end].attributes == a { end += 1 }
                if a != Attributes() { runs.append("row \(r+1) col \(c+1)-\(end) \(attributeText(a))") }
                c = end
            }
        }
        print("ATTRS \(runs.count)"); for s in runs { print(s) }
        print("BELL \(bells)\nREPLIES \(replies)\nSTATS bytes=\(bytes) printed=\(printed) sequences=\(sequences)")
        print("IGNORED \(ignored.reduce(0, +)) unsupported=\(ignored[0]) malformed=\(ignored[1]) canceled=\(ignored[2]) invalid=\(ignored[3])")
    }
}

let size = readLine()!.split(separator: " ").map { Int($0)! }
let terminal = Terminal(size[0], size[1])
while let line = readLine() {
    if line == "%%END" { terminal.finish(); break }
    if line.hasPrefix("%%") { terminal.directive(line); continue }
    let data = Array(line.utf8)
    var i = 0
    while i < data.count {
        var b = data[i]
        if b == 94 { i += 1; b = data[i]; if b != 94 { b -= 64 } }
        terminal.feed(b); i += 1
    }
}
