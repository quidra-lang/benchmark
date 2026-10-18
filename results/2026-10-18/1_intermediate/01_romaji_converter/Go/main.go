package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

const (
    moraN = 108
    moraQ = 109
    moraL = 110
)

type mora struct {
    id, row, dan string
    spelling [5]string
    base, voice int
}
type token struct { id, col int }
type word struct {
    original string
    start, end, section, pattern int
    tokens []token
}
type element struct { id, voice, size int }
type settings struct { long, casing, order int }

var systems = []string{"HEPBURN", "TRADITIONAL", "KUNREI", "NIHON", "WAPURO"}
var rows = []string{"a", "ka", "sa", "ta", "na", "ha", "ma", "ya", "ra", "wa", "ga", "za", "da", "ba", "pa"}
var table []mora

func index(items []string, s string) int {
    for i, item := range items {
        if item == s { return i }
    }
    return -1
}
func letter(c byte) bool { return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' }
func vowel(c byte) bool { return c != 0 && strings.ContainsRune("aiueo", rune(c)) }
func wordChar(c byte) bool { return letter(c) || c == '\'' || c == '-' }
func lower(c byte) byte {
    if c >= 'A' && c <= 'Z' { return c + 'a' - 'A' }
    return c
}
func upper(c byte) byte {
    if c >= 'a' && c <= 'z' { return c - 'a' + 'A' }
    return c
}
func moraID(id string) int {
    for i, m := range table {
        if m.id == id { return i }
    }
    return moraN
}
func initialize() {
    base := []string{
        "a i u e o", "ka ki ku ke ko", "sa si su se so", "ta ti tu te to",
        "na ni nu ne no", "ha hi hu he ho", "ma mi mu me mo", "ya yu yo",
        "ra ri ru re ro", "wa wi we wo", "ga gi gu ge go", "za zi zu ze zo",
        "da di du de do", "ba bi bu be bo", "pa pi pu pe po",
    }
    baseRows := []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 5, 5}
    for r, line := range base {
        for _, id := range strings.Fields(line) {
            voice := 0
            if r >= 10 { voice = 1 }
            if r == 14 { voice = 2 }
            table = append(table, mora{id: id, row: rows[r], dan: id[len(id)-1:], base: baseRows[r], voice: voice})
        }
    }
    for _, r := range []int{1, 2, 3, 4, 5, 6, 8, 10, 11, 12, 13, 14} {
        for _, dan := range []string{"ya", "yu", "yo"} {
            voice := 0
            if r >= 10 { voice = 1 }
            if r == 14 { voice = 2 }
            table = append(table, mora{id: rows[r][:1]+dan, row: rows[r], dan: dan, base: baseRows[r], voice: voice})
        }
    }
    special := []string{"si", "ti", "tu", "hu", "zi", "di", "du", "wi", "we", "wo"}
    hepburn := []string{"shi", "chi", "tsu", "fu", "ji", "ji", "zu", "i", "e", "o"}
    kunreiFrom := []string{"di", "du", "wi", "we", "wo", "dya", "dyu", "dyo"}
    kunreiTo := []string{"zi", "zu", "i", "e", "o", "zya", "zyu", "zyo"}
    for i := range table {
        m := &table[i]
        for s := 0; s < 5; s++ {
            p := m.id
            k := index(special, m.id)
            if k >= 0 && (s <= 1 || s == 4 && k < 5) { p = hepburn[k] }
            k = index(kunreiFrom, m.id)
            if s == 2 && k >= 0 { p = kunreiTo[k] }
            if len(m.dan) == 2 && (s <= 1 || s == 4) {
                switch m.id[:2] {
                case "sy": p = "sh" + m.id[2:]
                case "ty": p = "ch" + m.id[2:]
                case "zy": p = "j" + m.id[2:]
                case "dy":
                    if s <= 1 { p = "j" + m.id[2:] }
                }
            }
            m.spelling[s] = p
        }
    }
}
func fail(message string) { panic(message) }
func columnError(col int, message string) { fail(fmt.Sprintf("col %d: %s", col, message)) }
func lex(text string) []word {
    var words []word
    section := 0
    for i := 0; i < len(text); {
        if !wordChar(text[i]) {
            if text[i] == '/' { section++ }
            i++
            continue
        }
        start := i
        for i < len(text) && wordChar(text[i]) { i++ }
        words = append(words, word{original: text[start:i], start: start, end: i, section: section})
    }
    return words
}
func checkCase(w *word) {
    allLower, allUpper := true, true
    title := w.original[0] >= 'A' && w.original[0] <= 'Z'
    letters := 0
    for i := 0; i < len(w.original); i++ {
        c := w.original[i]
        if !letter(c) { continue }
        letters++
        if c != lower(c) { allLower = false }
        if c != upper(c) { allUpper = false }
        if i > 0 && c != lower(c) { title = false }
    }
    switch {
    case allLower: w.pattern = 0
    case title: w.pattern = 1
    case letters >= 2 && allUpper: w.pattern = 2
    default: columnError(w.start+1, "mixed case")
    }
}
func match(s string, pos, system int) (int, int) {
    id, length := -1, 0
    for i, m := range table {
        for t, p := range m.spelling {
            if system >= 0 && t != system { continue }
            if len(p) > length && strings.HasPrefix(s[pos:], p) {
                id, length = i, len(p)
            }
        }
    }
    return id, length
}
func parse(w *word, system int) string {
    w.tokens = nil
    s := strings.ToLower(w.original)
    for p := 0; p < len(s); {
        c, c2 := s[p], byte(0)
        if p+1 < len(s) { c2 = s[p+1] }
        id, advance := -1, 1
        if c == '-' {
            if len(w.tokens) == 0 || w.tokens[len(w.tokens)-1].id >= moraN {
                return fmt.Sprintf("col %d: misplaced long mark", w.start+p+1)
            }
            id = moraL
        } else if c == '\'' {
            return fmt.Sprintf("col %d: misplaced apostrophe", w.start+p+1)
        } else {
            found, length := match(s, p, system)
            switch {
            case found >= 0:
                id, advance = found, length
            case (system == 4 || system < 0) && strings.HasPrefix(s[p:], "xtu"):
                id, advance = moraQ, 3
            case c == 'n':
                id = moraN
                if system < 0 {
                    c3 := byte(0)
                    if p+2 < len(s) { c3 = s[p+2] }
                    if c2 == '\'' || c2 == 'n' && !vowel(c3) && c3 != 'y' && c3 != '\'' { advance = 2 }
                } else if system == 4 && c2 == 'n' || system != 4 && c2 == '\'' { advance = 2 }
            case (system == 1 || system < 0) && c == 'm' && c2 != 0 && strings.ContainsRune("bmp", rune(c2)):
                id = moraN
            default:
                next, _ := match(s, p+1, system)
                if letter(c) && !vowel(c) && c != 'n' && c2 == c && next >= 0 {
                    id = moraQ
                } else if system <= 1 && c == 't' && strings.HasPrefix(s[p+1:], "ch") && next >= 0 {
                    id = moraQ
                } else { return fmt.Sprintf("col %d: unknown syllable", w.start+p+1) }
            }
        }
        w.tokens = append(w.tokens, token{id, w.start+p+1})
        p += advance
    }
    return ""
}
func pairs(w word, longOnly bool) []bool {
    result := make([]bool, len(w.tokens))
    for i := 0; i+1 < len(w.tokens); {
        a, b := w.tokens[i].id, w.tokens[i+1].id
        if a < moraN && b < 5 {
            x, y := table[a].id[len(table[a].id)-1], table[b].id[0]
            if x == y || x == 'o' && y == 'u' || x == 'e' && y == 'i' {
                result[i+1] = !longOnly || x == 'o' && (y == 'o' || y == 'u') || x == 'u' && y == 'u'
                i += 2
                continue
            }
        }
        i++
    }
    if longOnly {
        for i, t := range w.tokens {
            if t.id == moraL { result[i] = true }
        }
    }
    return result
}
func parts(w word, system, mode int) []string {
    longElements := pairs(w, true)
    result := make([]string, len(w.tokens))
    for i, t := range w.tokens {
        nextID, next := -1, ""
        if i+1 < len(w.tokens) {
            nextID = w.tokens[i+1].id
            if nextID < moraN { next = table[nextID].spelling[system] }
        }
        first := byte(0)
        if next != "" { first = next[0] }
        s := ""
        if longElements[i] {
            previous := table[w.tokens[i-1].id].id
            v := previous[len(previous)-1]
            switch mode {
            case 0:
                if t.id == moraL { s = "-" } else { s = table[t.id].spelling[system] }
            case 2:
                if v == 'o' && !vowel(first) { s = "h" }
            case 3: s = "-"
            case 4: s = string(v)
            }
        } else if t.id < moraN {
            s = table[t.id].spelling[system]
        } else if t.id == moraN {
            s = "n"
            if system == 4 {
                if nextID == moraN || vowel(first) || first == 'y' || first == 'n' { s = "nn" }
            } else if system == 1 && first != 0 && strings.ContainsRune("bmp", rune(first)) {
                s = "m"
            } else if vowel(first) || first == 'y' { s = "n'" }
        } else if t.id == moraQ {
            if first != 0 && !vowel(first) && first != 'n' {
                s = string(first)
                if system <= 1 && strings.HasPrefix(next, "ch") { s = "t" }
            } else if system == 4 { s = "xtu" } else { columnError(t.col, "small tsu cannot be written") }
        }
        result[i] = s
    }
    return result
}
func writeWord(w word, system int, canonical bool, config settings) string {
    mode := config.long
    pattern := w.pattern
    if canonical { mode = 0 } else if config.casing != 0 {
        pattern = []int{0, 0, 2, 1}[config.casing]
    }
    result := strings.Join(parts(w, system, mode), "")
    if pattern == 1 && len(result) > 0 { result = string(upper(result[0])) + result[1:] }
    if pattern == 2 { result = strings.ToUpper(result) }
    return result
}
func sequence(w word, loose bool) []int {
    omit := pairs(w, true)
    var result []int
    for i, t := range w.tokens {
        if !loose || !omit[i] { result = append(result, t.id) }
    }
    return result
}
func equal(a, b []int) bool {
    if len(a) != len(b) { return false }
    for i := range a {
        if a[i] != b[i] { return false }
    }
    return true
}
func elements(w word) []element {
    var result []element
    for _, t := range w.tokens {
        switch t.id {
        case moraL: continue
        case moraN: result = append(result, element{moraN, 0, 0})
        case moraQ: result = append(result, element{moraID("tu"), 0, 1})
        default:
            m := table[t.id]
            base := m.id
            if m.voice != 0 {
                r := index([]string{"ga", "za", "da", "ba", "pa"}, m.row)
                base = string("ksthh"[r]) + base[1:]
            }
            if len(m.dan) == 2 {
                result = append(result, element{moraID(base[:1]+"i"), m.voice, 0}, element{moraID(m.dan), 0, 1})
            } else { result = append(result, element{moraID(base), m.voice, 0}) }
        }
    }
    return result
}
func key(w word, order int) [][]int {
    ranks := strings.Fields("a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N")
    if order == 1 { ranks = strings.Fields("i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N") }
    result := make([][]int, 4)
    for _, e := range elements(w) {
        id := "N"
        if e.id != moraN { id = table[e.id].id }
        result[0] = append(result[0], index(ranks, id))
        result[1] = append(result[1], e.voice)
        result[2] = append(result[2], e.size)
    }
    for _, t := range w.tokens {
        n := 0
        if t.id == moraL { n = 1 }
        result[3] = append(result[3], n)
    }
    return result
}
func less(a, b [][]int) bool {
    for k := range a {
        for i := 0; i < len(a[k]) && i < len(b[k]); i++ {
            if a[k][i] != b[k][i] { return a[k][i] < b[k][i] }
        }
        if len(a[k]) != len(b[k]) { return len(a[k]) < len(b[k]) }
    }
    return false
}
func patternTokens(pattern string, system int) []int {
    var result []int
    start := 0
    for i := 0; i <= len(pattern); i++ {
        c := byte(0)
        if i < len(pattern) { c = pattern[i] }
        if c == 0 || c == '?' || c == '*' {
            if i > start {
                w := word{original: pattern[start:i]}
                if parse(&w, system) != "" { fail("invalid pattern") }
                result = append(result, sequence(w, false)...)
            }
            if c == '?' { result = append(result, -1) }
            if c == '*' { result = append(result, -2) }
            start = i+1
        } else if !(c >= 'a' && c <= 'z' || c == '\'' || c == '-') { fail("invalid pattern") }
    }
    return result
}
func glob(pattern []int, w word) bool {
    dp := make([]bool, len(w.tokens)+1)
    dp[0] = true
    for _, p := range pattern {
        next := make([]bool, len(dp))
        if p == -2 {
            next[0] = dp[0]
            for j := 1; j < len(dp); j++ { next[j] = dp[j] || next[j-1] }
        } else {
            for j := 1; j < len(dp); j++ { next[j] = dp[j-1] && (p == -1 || p == w.tokens[j-1].id) }
        }
        dp = next
    }
    return dp[len(w.tokens)]
}
func process(line string, config *settings) string {
    names := []string{"SET", "TABLE", "CONVERT", "NORMALIZE", "REVERSE", "VALID", "DETECT", "DIFF", "SAME", "MORAE", "SYLLABLES", "ROW", "STATS", "SORT", "INDEX", "FIND", "HAIKU", "KAIBUN", "SHIRITORI"}
    fixed := []int{2, 2, 2, 0, 1, 1, 0, 2, 2, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1}
    command, _, _ := strings.Cut(line, " ")
    cmd := index(names, command)
    if cmd < 0 { fail("unknown command " + command) }
    var args []string
    text := ""
    if cmd <= 1 {
        fields := strings.Split(line, " ")
        if len(fields) < 3 { fail("missing argument") }
        if len(fields) > 3 { fail("too many arguments") }
        args = fields[1:]
    } else {
        rest := line
        for i := 0; i <= fixed[cmd]; i++ {
            field, tail, found := strings.Cut(rest, " ")
            if !found { fail("missing argument") }
            if i > 0 { args = append(args, field) }
            rest = tail
        }
        text = rest
    }
    if cmd == 0 {
        option := index([]string{"LONG", "CASE", "ORDER"}, args[0])
        if option < 0 { fail("unknown option " + args[0]) }
        values := [][]string{{"KEEP", "DROP", "PASSPORT", "HYPHEN", "DOUBLE"}, {"KEEP", "LOWER", "UPPER", "TITLE"}, {"GOJUON", "IROHA"}}
        value := index(values[option], args[1])
        if value < 0 { fail("unknown value " + args[1]) }
        switch option {
        case 0: config.long = value
        case 1: config.casing = value
        case 2: config.order = value
        }
        return args[0]+"="+args[1]
    }
    systemCount := 1
    if cmd == 3 || cmd == 6 { systemCount = 0 }
    if cmd == 2 || cmd == 7 || cmd == 8 { systemCount = 2 }
    sys := []int{-1, -1}
    for i := 0; i < systemCount; i++ {
        sys[i] = index(systems, args[i])
        if sys[i] < 0 { fail("unknown system " + args[i]) }
    }
    source := sys[0]
    if cmd == 1 {
        if index(rows, args[1]) < 0 { fail("unknown row " + args[1]) }
        var result []string
        for _, m := range table {
            if m.row == args[1] { result = append(result, m.spelling[source]) }
        }
        return strings.Join(result, " ")
    }
    var pattern []int
    if cmd == 15 { pattern = patternTokens(args[1], source) }
    for i := 0; i < len(text); i++ {
        c := text[i]
        if !wordChar(c) && !(c >= '0' && c <= '9') && !strings.ContainsRune(" .,!?;:()\"", rune(c)) && !((cmd == 8 || cmd == 16) && c == '/') {
            columnError(i+1, "invalid character")
        }
    }
    words := lex(text)
    sections := strings.Count(text, "/")+1
    counts := make([]int, sections)
    for _, w := range words { counts[w.section]++ }
    if cmd == 8 && (sections != 2 || counts[0] == 0 || counts[1] == 0) { fail("expected two texts") }
    if cmd == 16 {
        if sections != 3 && sections != 5 { fail("expected 3 or 5 lines") }
        for _, c := range counts {
            if c == 0 { fail("expected 3 or 5 lines") }
        }
    }
    if len(words) == 0 { fail("no words") }
    for i := range words { checkCase(&words[i]) }
    if cmd == 6 {
        var output []string
        for s := 0; s < 5; s++ {
            parsed := append([]word(nil), words...)
            verdict := "canonical"
            for i := range parsed {
                if parse(&parsed[i], s) != "" {
                    verdict = "error"
                    break
                }
            }
            if verdict != "error" {
                for _, w := range parsed {
                    if writeWord(w, s, true, *config) != w.original { verdict = "readable" }
                }
            }
            output = append(output, systems[s]+"="+verdict)
        }
        return strings.Join(output, " ")
    }
    for i := range words {
        s := source
        if cmd == 8 && words[i].section == 1 { s = sys[1] }
        if message := parse(&words[i], s); message != "" { fail(message) }
    }
    if cmd == 2 || cmd == 3 || cmd == 4 {
        var output strings.Builder
        pos := 0
        for _, w := range words {
            output.WriteString(text[pos:w.start])
            target := source
            if cmd == 2 { target = sys[1] }
            if cmd == 3 { target = 0 }
            if cmd == 4 {
                for i := range w.tokens {
                    if w.tokens[i].id == moraL {
                        previous := table[w.tokens[i-1].id].id
                        w.tokens[i].id = moraID(previous[len(previous)-1:])
                    }
                }
                for i, j := 0, len(w.tokens)-1; i < j; i, j = i+1, j-1 {
                    w.tokens[i], w.tokens[j] = w.tokens[j], w.tokens[i]
                }
            }
            output.WriteString(writeWord(w, target, false, *config))
            pos = w.end
        }
        output.WriteString(text[pos:])
        return output.String()
    }
    if cmd == 5 {
        for _, w := range words {
            canonical := writeWord(w, source, true, *config)
            if canonical != w.original {
                i := 0
                for i < len(canonical) && i < len(w.original) && canonical[i] == w.original[i] { i++ }
                return fmt.Sprintf("INVALID col %d: expected %s", w.start+i+1, canonical)
            }
        }
        return "VALID"
    }
    if cmd == 7 || cmd == 15 {
        var selected []string
        for _, w := range words {
            if cmd == 7 {
                a := writeWord(w, source, false, *config)
                b := writeWord(w, sys[1], false, *config)
                if a != b { selected = append(selected, a+">"+b) }
            } else if glob(pattern, w) { selected = append(selected, w.original) }
        }
        result := fmt.Sprintf("%d of %d", len(selected), len(words))
        if len(selected) > 0 { result += ": " + strings.Join(selected, " ") }
        return result
    }
    if cmd == 8 {
        boundary := counts[0]
        left, right := words[:boundary], words[boundary:]
        exact := true
        for i := 0; i < len(left) && i < len(right); i++ {
            if !equal(sequence(left[i], true), sequence(right[i], true)) { return fmt.Sprintf("DIFFERENT at word %d", i+1) }
            if !equal(sequence(left[i], false), sequence(right[i], false)) { exact = false }
        }
        if len(left) != len(right) { return fmt.Sprintf("DIFFERENT at word %d", min(len(left), len(right))+1) }
        if exact { return "EXACT" }
        return "LOOSE"
    }
    if cmd == 9 || cmd == 10 {
        var output []string
        total := 0
        for _, w := range words {
            var pieces []string
            if cmd == 9 {
                for _, t := range w.tokens {
                    s := "-"
                    switch t.id {
                    case moraN: s = "N"
                    case moraQ: s = "Q"
                    case moraL:
                    default: s = table[t.id].spelling[source]
                    }
                    pieces = append(pieces, s)
                }
            } else {
                canonical := parts(w, source, 0)
                paired := pairs(w, false)
                for i, t := range w.tokens {
                    if i > 0 && (t.id >= moraN || paired[i]) {
                        pieces[len(pieces)-1] += canonical[i]
                    } else {
                        pieces = append(pieces, canonical[i])
                    }
                }
            }
            total += len(pieces)
            output = append(output, strings.Join(pieces, "."))
        }
        return fmt.Sprintf("%d: %s", total, strings.Join(output, " "))
    }
    if cmd == 11 {
        var output []string
        for _, w := range words {
            for _, t := range w.tokens {
                if t.id < moraN {
                    m := table[t.id]
                    output = append(output, m.spelling[source]+": "+m.row+" "+m.dan)
                } else { output = append(output, []string{"N", "Q", "-"}[t.id-moraN]+": special") }
            }
        }
        return strings.Join(output, ", ")
    }
    if cmd == 12 {
        rowCounts := make([]int, 10)
        other := make([]int, 6)
        total := 0
        for _, w := range words {
            for _, t := range w.tokens {
                total++
                if t.id < moraN {
                    m := table[t.id]
                    rowCounts[m.base]++
                    if m.voice != 0 { other[m.voice-1]++ }
                    if len(m.dan) == 2 { other[2]++ }
                } else { other[t.id-moraN+3]++ }
            }
        }
        output := []string{fmt.Sprintf("morae=%d", total)}
        for r, c := range rowCounts {
            if c > 0 { output = append(output, fmt.Sprintf("%s=%d", rows[r], c)) }
        }
        labels := []string{"voiced", "semivoiced", "contracted", "N", "Q", "L"}
        for i, c := range other { output = append(output, fmt.Sprintf("%s=%d", labels[i], c)) }
        return strings.Join(output, " ")
    }
    if cmd == 13 || cmd == 14 {
        sort.SliceStable(words, func(i, j int) bool { return less(key(words[i], config.order), key(words[j], config.order)) })
        var output []string
        previous := ""
        for _, w := range words {
            if cmd == 13 {
                output = append(output, w.original)
                continue
            }
            id := elements(w)[0].id
            heading := "N"
            if id != moraN {
                heading = table[id].row
                if config.order == 1 { heading = table[id].id }
            }
            if heading == previous { output[len(output)-1] += " " + w.original } else { output = append(output, heading+": "+w.original) }
            previous = heading
        }
        separator := " "
        if cmd == 14 { separator = "; " }
        return strings.Join(output, separator)
    }
    if cmd == 16 {
        counts = make([]int, sections)
        for _, w := range words { counts[w.section] += len(w.tokens) }
        expected := []int{5, 7, 5, 7, 7}[:sections]
        verdict, kind := "NG", "haiku"
        if equal(counts, expected) { verdict = "OK" }
        if sections == 5 { kind = "tanka" }
        var numbers []string
        for _, c := range counts { numbers = append(numbers, strconv.Itoa(c)) }
        return verdict+" "+kind+" "+strings.Join(numbers, "-")
    }
    if cmd == 17 {
        var kana []int
        var output []string
        for _, w := range words {
            for _, e := range elements(w) {
                kana = append(kana, e.id)
                s := "N"
                if e.id != moraN { s = table[e.id].id }
                output = append(output, s)
            }
        }
        verdict := "YES"
        for i := 0; i < len(kana)/2; i++ {
            if kana[i] != kana[len(kana)-1-i] {
                verdict = "NO"
            }
        }
        return verdict+" "+strings.Join(output, ".")
    }
    previousTail := -1
    for i, w := range words {
        e := elements(w)
        prefix := fmt.Sprintf("NG %d: %s", i+1, w.original)
        if i > 0 && e[0].id != previousTail { return prefix+" must start with "+table[previousTail].spelling[source] }
        for j := 0; j < i; j++ {
            if equal(sequence(w, false), sequence(words[j], false)) {
                return prefix+" is repeated"
            }
        }
        previousTail = e[len(e)-1].id
        if previousTail == moraN { return prefix+" ends with N" }
    }
    return fmt.Sprintf("OK %d", len(words))
}
func commandResult(line string, config *settings) (result string) {
    defer func() {
        if message := recover(); message != nil { result = "ERROR " + message.(string) }
    }()
    return process(line, config)
}
func main() {
    initialize()
    scanner := bufio.NewScanner(os.Stdin)
    scanner.Scan()
    count, _ := strconv.Atoi(scanner.Text())
    config := settings{}
    output := bufio.NewWriter(os.Stdout)
    defer output.Flush()
    for i := 0; i < count && scanner.Scan(); i++ {
        fmt.Fprintln(output, commandResult(strings.TrimSuffix(scanner.Text(), "\r"), &config))
    }
}
