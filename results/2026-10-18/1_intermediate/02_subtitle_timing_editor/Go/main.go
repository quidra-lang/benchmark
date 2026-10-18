package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type cue struct {
    index int64
    start, end int64
    text []string
}
type record struct {
    command string
    cues []cue
}
type editor struct {
    cues []cue
    history []record
}
type arguments struct {
    name string
    raw []string
    values []int64
    denominator int64
}
type markup struct {
    kind int
    text string
    digit int
}

func clone(cues []cue) []cue {
    result := append([]cue(nil), cues...)
    for i := range result {
        result[i].text = append([]string(nil), result[i].text...)
    }
    return result
}
func fail(message string) { panic(message) }
func unsigned(s string) (int64, bool) {
    if len(s) < 1 || len(s) > 9 { return 0, false }
    for i := range s {
        if s[i] < '0' || s[i] > '9' { return 0, false }
    }
    n, _ := strconv.ParseInt(s, 10, 64)
    return n, true
}
func timeValue(s string) (int64, bool) {
    if len(s) != 12 || s[2] != ':' || s[5] != ':' || s[8] != ',' { return 0, false }
    for i := range s {
        if i != 2 && i != 5 && i != 8 && (s[i] < '0' || s[i] > '9') { return 0, false }
    }
    h, _ := strconv.ParseInt(s[:2], 10, 64)
    m, _ := strconv.ParseInt(s[3:5], 10, 64)
    sec, _ := strconv.ParseInt(s[6:8], 10, 64)
    ms, _ := strconv.ParseInt(s[9:], 10, 64)
    return h*3600000+m*60000+sec*1000+ms, m <= 59 && sec <= 59
}
func timeText(t int64, kind int) string {
    if kind == 2 {
        c := (t+5)/10
        return fmt.Sprintf("%d:%02d:%02d.%02d", c/360000, c/6000%60, c/100%60, c%100)
    }
    mark := ","
    if kind == 1 { mark = "." }
    return fmt.Sprintf("%02d:%02d:%02d%s%03d", t/3600000, t/60000%60, t/1000%60, mark, t%1000)
}
func decimal(v int64) string { return fmt.Sprintf("%d.%02d", v/100, v%100) }
func floorRatio(a, b int64) int64 {
    if b < 0 { a, b = -a, -b }
    q, r := a/b, a%b
    if r < 0 { q-- }
    return q
}
func halfUp(a, b int64) int64 {
    if b < 0 { a, b = -a, -b }
    return floorRatio(2*a+b, 2*b)
}
func countChars(c cue) int64 {
    var count int64
    for _, line := range c.text { count += int64(len(line)) }
    return count
}
func dialogue(c cue) bool {
    for _, line := range c.text {
        if strings.HasPrefix(line, "- ") { return true }
    }
    return false
}
func words(lines []string) []string { return strings.Fields(strings.Join(lines, " ")) }
func wrap(lines []string, width int) []string {
    var result []string
    for _, w := range words(lines) {
        if len(result) == 0 || len(result[len(result)-1])+1+len(w) > width {
            result = append(result, w)
        } else { result[len(result)-1] += " " + w }
    }
    return result
}
func sameText(a, b []string) bool {
    if len(a) != len(b) { return false }
    for i := range a {
        if a[i] != b[i] { return false }
    }
    return true
}
func scanMarkup(line string) []markup {
    tags := []string{"<i>", "</i>", "<b>", "</b>", "<u>", "</u>"}
    var result []markup
    for p := 0; p < len(line); {
        size, kind, digit := 1, 0, 0
        for _, tag := range tags {
            if strings.HasPrefix(line[p:], tag) {
                size, kind = len(tag), 1
                break
            }
        }
        if kind == 0 && strings.HasPrefix(line[p:], "</font>") { size, kind = 7, 2 }
        if kind == 0 && strings.HasPrefix(line[p:], "<font") && p+5 < len(line) && (line[p+5] == ' ' || line[p+5] == '>') {
            if end := strings.IndexByte(line[p+5:], '>'); end >= 0 { size, kind = 6+end, 2 }
        }
        if kind == 0 && p+6 <= len(line) && line[p:p+4] == "{\\an" && line[p+4] >= '1' && line[p+4] <= '9' && line[p+5] == '}' {
            size, kind, digit = 6, 3, int(line[p+4]-'0')
        }
        result = append(result, markup{kind, line[p:p+size], digit})
        p += size
    }
    return result
}
func converted(lines []string, mode int) ([]string, int, int) {
    var result []string
    first, removed := 0, 0
    ass := map[string]string{"<i>": "{\\i1}", "</i>": "{\\i0}", "<b>": "{\\b1}", "</b>": "{\\b0}", "<u>": "{\\u1}", "</u>": "{\\u0}"}
    for _, line := range lines {
        var output strings.Builder
        for _, m := range scanMarkup(line) {
            if m.kind == 3 && first == 0 { first = m.digit }
            if mode == 0 {
                if m.kind == 0 { output.WriteString(m.text) } else { removed++ }
            } else if mode == 1 {
                if m.kind == 1 { output.WriteString(m.text) }
                if m.kind == 0 {
                    switch m.text {
                    case "&": output.WriteString("&amp;")
                    case "<": output.WriteString("&lt;")
                    case ">": output.WriteString("&gt;")
                    default: output.WriteString(m.text)
                    }
                }
            } else {
                if m.kind == 1 { output.WriteString(ass[m.text]) }
                if m.kind == 0 || m.kind == 3 { output.WriteString(m.text) }
            }
        }
        text := output.String()
        if mode != 2 { text = strings.Trim(text, " ") }
        if mode == 2 || text != "" { result = append(result, text) }
    }
    return result, first, removed
}
func cleanHI(line string) (string, int, int) {
    var output strings.Builder
    segments := 0
    for p := 0; p < len(line); {
        end := -1
        if line[p] == '[' { end = strings.IndexByte(line[p+1:], ']') }
        if line[p] == '(' { end = strings.IndexByte(line[p+1:], ')') }
        if end >= 0 {
            segments++
            p += end+2
        } else {
            output.WriteByte(line[p])
            p++
        }
    }
    text := strings.Join(strings.Fields(output.String()), " ")
    prefix, body := "", text
    if strings.HasPrefix(body, "- ") { prefix, body = "- ", body[2:] }
    labels := 0
    if colon := strings.IndexByte(body, ':'); colon > 0 {
        label := body[:colon]
        valid := label[0] >= 'A' && label[0] <= 'Z'
        for i := range label {
            c := label[i]
            if !(c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == ' ') { valid = false }
        }
        if valid {
            labels = 1
            text = strings.Join(strings.Fields(prefix+body[colon+1:]), " ")
        }
    }
    return text, segments, labels
}
func parseArguments(line string, count int) arguments {
    schemas := map[string]string{
        "LIST":"", "VALIDATE":"", "SEARCH":"S", "AT":"T", "GAPS":"U", "STATS":"",
        "PRINT":"", "TOVTT":"", "TOASS":"", "FRAMES":"F", "SHIFT":"I", "SHIFTFROM":"PI",
        "SCALE":"UU", "SYNC":"PTPT", "SNAP":"F", "FIXOVERLAP":"U", "EXTEND":"U", "TIME":"PTT",
        "SORT":"", "RENUMBER":"", "MERGE":"U", "SPLIT":"U", "INSERT":"PTTX", "DELETE":"P",
        "TEXT":"PX", "BALANCE":"", "STRIP":"", "CLEANHI":"", "REPLACE":"R", "UNDO":"",
    }
    name, rest, hasSpace := strings.Cut(line, " ")
    schema, known := schemas[name]
    if !known { fail("unknown command") }
    var raw []string
    if hasSpace {
        if strings.ContainsAny(schema, "SXR") { raw = strings.SplitN(rest, " ", len(schema)) } else { raw = strings.Split(rest, " ") }
    }
    if name == "DELETE" && len(raw) == 2 { schema = "PP" }
    if len(raw) != len(schema) { fail("bad arguments") }
    a := arguments{name: name, raw: raw, values: make([]int64, len(raw)), denominator: 1}
    for i, kind := range schema {
        s := raw[i]
        valid := true
        var value int64
        switch kind {
        case 'P', 'U':
            value, valid = unsigned(s)
            if kind == 'P' && value == 0 { valid = false }
        case 'I':
            negative := strings.HasPrefix(s, "-")
            if negative { s = s[1:] }
            value, valid = unsigned(s)
            if negative { value = -value }
        case 'T': value, valid = timeValue(s)
        case 'F':
            parts := strings.Split(s, "/")
            if len(parts) > 2 { valid = false } else {
                value, valid = unsigned(parts[0])
                if len(parts) == 2 {
                    denominator, ok := unsigned(parts[1])
                    a.denominator = denominator
                    valid = valid && ok
                }
                valid = valid && value >= 1 && value <= 100000 && a.denominator >= 1 && a.denominator <= 100000
            }
        case 'X':
            for _, part := range strings.Split(s, "|") {
                if part == "" { valid = false }
            }
        case 'R':
            old, replacement, found := strings.Cut(s, "|")
            valid = found && old != "" && replacement != "" && !strings.Contains(replacement, "|")
        case 'S': valid = s != ""
        }
        if !valid { fail("bad arguments") }
        a.values[i] = value
    }
    if name == "SCALE" && (a.values[0] < 1 || a.values[0] > 100000 || a.values[1] < 1 || a.values[1] > 100000) { fail("bad arguments") }
    if name == "GAPS" || name == "FIXOVERLAP" || name == "MERGE" || name == "EXTEND" {
        minimum := int64(0)
        if name == "EXTEND" { minimum = 1 }
        if a.values[0] < minimum || a.values[0] > 60000 { fail("bad arguments") }
    }
    if name == "SPLIT" && (a.values[0] < 10 || a.values[0] > 80) { fail("bad arguments") }
    if name == "DELETE" && len(raw) == 2 && a.values[1] < a.values[0] { fail("bad arguments") }
    limit := int64(count)
    if name == "INSERT" { limit++ }
    for i, kind := range schema {
        if kind == 'P' && a.values[i] > limit { fail(fmt.Sprintf("no cue %d", a.values[i])) }
    }
    return a
}
func cueLine(position int, c cue) string {
    return fmt.Sprintf("%d %d %s %s %s", position, c.index, timeText(c.start, 0), timeText(c.end, 0), strings.Join(c.text, "|"))
}
func (e *editor) execute(line string) []string {
    a := parseArguments(line, len(e.cues))
    name, v := a.name, a.values
    n := len(e.cues)
    if name == "UNDO" {
        if len(e.history) == 0 { fail("nothing to undo") }
        previous := e.history[len(e.history)-1]
        e.history = e.history[:len(e.history)-1]
        e.cues = previous.cues
        return []string{"UNDO command="+previous.command}
    }
    if name == "SYNC" && e.cues[v[0]-1].start == e.cues[v[2]-1].start { fail("sync points coincide") }
    modifying := strings.Contains(" SHIFT SHIFTFROM SCALE SYNC SNAP FIXOVERLAP EXTEND TIME SORT RENUMBER MERGE SPLIT INSERT DELETE TEXT BALANCE STRIP CLEANHI REPLACE ", " "+name+" ")
    if modifying { e.history = append(e.history, record{name, clone(e.cues)}) }
    var output []string
    switch name {
    case "LIST", "AT":
        matches := 0
        for i, c := range e.cues {
            if name == "LIST" || c.start <= v[0] && v[0] < c.end {
                output = append(output, cueLine(i+1, c))
                matches++
            }
        }
        if name == "AT" { output = append(output, fmt.Sprintf("AT active=%d", matches)) }
    case "VALIDATE":
        for i, c := range e.cues {
            prefix := fmt.Sprintf("cue %d: ", i+1)
            d := c.end-c.start
            if c.index != int64(i+1) { output = append(output, prefix+fmt.Sprintf("index %d (expected %d)", c.index, i+1)) }
            if d <= 0 { output = append(output, prefix+"end not after start") }
            if i > 0 && c.start < e.cues[i-1].end { output = append(output, prefix+fmt.Sprintf("overlaps previous by %d ms", e.cues[i-1].end-c.start)) }
            if d >= 1 && d < 700 { output = append(output, prefix+fmt.Sprintf("too short (%d ms)", d)) }
            if d > 7000 { output = append(output, prefix+fmt.Sprintf("too long (%d ms)", d)) }
            for j, text := range c.text {
                if len(text) > 42 { output = append(output, prefix+fmt.Sprintf("line %d too long (%d chars)", j+1, len(text))) }
            }
            if len(c.text) >= 3 { output = append(output, prefix+fmt.Sprintf("too many lines (%d)", len(c.text))) }
            chars := countChars(c)
            if d >= 1 && chars*1000 > 21*d { output = append(output, prefix+"too fast ("+decimal(chars*100000/d)+" cps)") }
        }
        output = append(output, fmt.Sprintf("VALIDATE problems=%d", len(output)))
    case "SEARCH":
        for i, c := range e.cues {
            for _, text := range c.text {
                if strings.Contains(text, a.raw[0]) {
                    output = append(output, fmt.Sprintf("%d %s %s", i+1, timeText(c.start, 0), text))
                    break
                }
            }
        }
        output = append(output, fmt.Sprintf("SEARCH found=%d", len(output)))
    case "GAPS":
        for i := 0; i+1 < n; i++ {
            gap := e.cues[i+1].start-e.cues[i].end
            if gap < v[0] { output = append(output, fmt.Sprintf("%d %d %d", i+1, i+2, gap)) }
        }
        output = append(output, fmt.Sprintf("GAPS count=%d", len(output)))
    case "STATS":
        output = append(output, fmt.Sprintf("STATS cues=%d", n))
        if n == 0 { return output }
        var total, chars, longest int64
        longestPosition := 1
        for i, c := range e.cues {
            d := max(int64(0), c.end-c.start)
            total += d
            if d > 0 { chars += countChars(c) }
            if d > longest { longest, longestPosition = d, i+1 }
        }
        output = append(output, "duration total="+timeText(total, 0)+" mean="+timeText(total/int64(n), 0))
        speed := "-"
        if total > 0 { speed = decimal(chars*100000/total) }
        output = append(output, "speed "+speed, fmt.Sprintf("longest cue=%d duration=%s", longestPosition, timeText(longest, 0)))
        if n == 1 { output = append(output, "gap none") } else {
            position, gap := 1, e.cues[1].start-e.cues[0].end
            for i := 1; i+1 < n; i++ {
                candidate := e.cues[i+1].start-e.cues[i].end
                if candidate > gap { position, gap = i+1, candidate }
            }
            output = append(output, fmt.Sprintf("gap cue=%d ms=%d", position, gap))
        }
    case "PRINT", "TOVTT":
        if name == "TOVTT" { output = append(output, "WEBVTT", "") }
        for _, c := range e.cues {
            text, code := c.text, 0
            kind := 0
            if name == "TOVTT" {
                text, code, _ = converted(c.text, 1)
                kind = 1
            }
            if len(text) == 0 { continue }
            setting := ""
            if code >= 7 { setting = " line:0" } else if code >= 4 { setting = " line:50%" }
            if code > 0 && code%3 == 1 { setting += " align:start" }
            if code > 0 && code%3 == 0 { setting += " align:end" }
            output = append(output, strconv.FormatInt(c.index, 10), timeText(c.start, kind)+" --> "+timeText(c.end, kind)+setting)
            output = append(output, text...)
            output = append(output, "")
        }
    case "TOASS":
        output = append(output, "[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text")
        for _, c := range e.cues {
            text, _, _ := converted(c.text, 2)
            output = append(output, "Dialogue: 0,"+timeText(c.start, 2)+","+timeText(c.end, 2)+",Default,,0,0,0,,"+strings.Join(text, "\\N"))
        }
    case "FRAMES":
        for i, c := range e.cues { output = append(output, fmt.Sprintf("%d %d %d", i+1, c.start*v[0]/(1000*a.denominator), c.end*v[0]/(1000*a.denominator))) }
    case "SHIFT", "SHIFTFROM", "SYNC", "SCALE", "SNAP":
        start, shift := 0, int64(0)
        if name == "SHIFT" { shift = v[0] }
        if name == "SHIFTFROM" { start, shift = int(v[0]-1), v[1] }
        var s1, s2 int64
        if name == "SYNC" { s1, s2 = e.cues[v[0]-1].start, e.cues[v[2]-1].start }
        clamped, changed := 0, 0
        for i := start; i < n; i++ {
            cueClamped := false
            times := []*int64{&e.cues[i].start, &e.cues[i].end}
            for _, t := range times {
                old, value := *t, *t
                switch name {
                case "SHIFT", "SHIFTFROM": value += shift
                case "SCALE": value = halfUp(value*v[0], v[1])
                case "SYNC": value = halfUp(v[1]*(s2-s1)+(value-s1)*(v[3]-v[1]), s2-s1)
                case "SNAP":
                    frame := halfUp(value*v[0], 1000*a.denominator)
                    value = halfUp(frame*1000*a.denominator, v[0])
                }
                if value < 0 {
                    value = 0
                    cueClamped = true
                }
                if old != value { changed++ }
                *t = value
            }
            if cueClamped { clamped++ }
        }
        if name == "SNAP" { output = append(output, fmt.Sprintf("SNAP changed=%d", changed)) } else if name == "SCALE" {
            output = append(output, fmt.Sprintf("SCALE cues=%d", n))
        } else { output = append(output, fmt.Sprintf("%s cues=%d clamped=%d", name, n-start, clamped)) }
    case "FIXOVERLAP":
        fixed, failed := 0, 0
        for i := 0; i+1 < n; i++ {
            candidate := e.cues[i+1].start-v[0]
            if e.cues[i].end > candidate {
                if candidate > e.cues[i].start {
                    e.cues[i].end = candidate
                    fixed++
                } else {
                    failed++
                    output = append(output, fmt.Sprintf("cue %d: cannot fix", i+1))
                }
            }
        }
        output = append(output, fmt.Sprintf("FIXOVERLAP fixed=%d failed=%d", fixed, failed))
    case "EXTEND":
        extended, short := 0, 0
        for i := range e.cues {
            if e.cues[i].end-e.cues[i].start < v[0] {
                candidate := e.cues[i].start+v[0]
                if i+1 < n { candidate = min(candidate, e.cues[i+1].start) }
                if candidate > e.cues[i].end {
                    e.cues[i].end = candidate
                    extended++
                }
            }
            if e.cues[i].end-e.cues[i].start < v[0] { short++ }
        }
        output = append(output, fmt.Sprintf("EXTEND extended=%d short=%d", extended, short))
    case "TIME":
        e.cues[v[0]-1].start, e.cues[v[0]-1].end = v[1], v[2]
        output = append(output, fmt.Sprintf("TIME cue=%d", v[0]))
    case "SORT":
        order := make([]int, n)
        for i := range order { order[i] = i }
        sort.SliceStable(order, func(i, j int) bool {
            x, y := e.cues[order[i]], e.cues[order[j]]
            if x.start != y.start { return x.start < y.start }
            return x.end < y.end
        })
        sorted := make([]cue, n)
        moved := 0
        for i, original := range order {
            sorted[i] = e.cues[original]
            if i != original { moved++ }
        }
        e.cues = sorted
        output = append(output, fmt.Sprintf("SORT moved=%d", moved))
    case "RENUMBER":
        changed := 0
        for i := range e.cues {
            if e.cues[i].index != int64(i+1) { changed++ }
            e.cues[i].index = int64(i+1)
        }
        output = append(output, fmt.Sprintf("RENUMBER changed=%d", changed))
    case "MERGE":
        var result []cue
        merged := 0
        for _, c := range e.cues {
            if len(result) > 0 {
                previous := &result[len(result)-1]
                if c.start-previous.end < v[0] && !dialogue(*previous) && !dialogue(c) {
                    lines := append(append([]string(nil), previous.text...), c.text...)
                    wrapped := wrap(lines, 42)
                    if len(wrapped) <= 2 {
                        previous.end = max(previous.end, c.end)
                        previous.text = wrapped
                        merged++
                        continue
                    }
                }
            }
            result = append(result, c)
        }
        e.cues = result
        output = append(output, fmt.Sprintf("MERGE merged=%d cues=%d", merged, len(result)))
    case "SPLIT":
        var result []cue
        split := 0
        for _, c := range e.cues {
            d := c.end-c.start
            if d < 1 || dialogue(c) {
                result = append(result, c)
                continue
            }
            wrapped := wrap(c.text, int(v[0]))
            if len(wrapped) <= 2 {
                c.text = wrapped
                result = append(result, c)
                continue
            }
            split++
            parts := make([]cue, (len(wrapped)+1)/2)
            var total int64
            for i := range parts {
                parts[i] = cue{index: c.index, text: wrapped[2*i:min(2*i+2, len(wrapped))]}
                total += countChars(parts[i])
            }
            lengths, remainders := make([]int64, len(parts)), make([]int64, len(parts))
            order := make([]int, len(parts))
            remaining := d
            for i := range parts {
                product := d*countChars(parts[i])
                lengths[i], remainders[i] = product/total, product%total
                remaining -= lengths[i]
                order[i] = i
            }
            sort.SliceStable(order, func(i, j int) bool { return remainders[order[i]] > remainders[order[j]] })
            for i := int64(0); i < remaining; i++ { lengths[order[i]]++ }
            start := c.start
            for i := range parts {
                parts[i].start, parts[i].end = start, start+lengths[i]
                start += lengths[i]
                result = append(result, parts[i])
            }
        }
        e.cues = result
        output = append(output, fmt.Sprintf("SPLIT split=%d cues=%d", split, len(result)))
    case "INSERT":
        p := int(v[0]-1)
        c := cue{index: v[0], start: v[1], end: v[2], text: strings.Split(a.raw[3], "|")}
        e.cues = append(e.cues, cue{})
        copy(e.cues[p+1:], e.cues[p:n])
        e.cues[p] = c
        output = append(output, fmt.Sprintf("INSERT cue=%d cues=%d", v[0], len(e.cues)))
    case "DELETE":
        p, q := int(v[0]-1), int(v[0])
        if len(v) == 2 { q = int(v[1]) }
        e.cues = append(e.cues[:p], e.cues[q:]...)
        output = append(output, fmt.Sprintf("DELETE removed=%d cues=%d", q-p, len(e.cues)))
    case "TEXT":
        e.cues[v[0]-1].text = strings.Split(a.raw[1], "|")
        output = append(output, fmt.Sprintf("TEXT cue=%d lines=%d", v[0], len(e.cues[v[0]-1].text)))
    case "BALANCE":
        changed, skipped, dialogues := 0, 0, 0
        for i, c := range e.cues {
            if dialogue(c) {
                dialogues++
                continue
            }
            w := words(c.text)
            text := strings.Join(w, " ")
            var candidate []string
            if len(text) <= 42 { candidate = []string{text} } else {
                bestDifference, bestFirst := int(^uint(0)>>1), int(^uint(0)>>1)
                for j := 1; j < len(w); j++ {
                    first, second := strings.Join(w[:j], " "), strings.Join(w[j:], " ")
                    difference := len(first)-len(second)
                    if difference < 0 { difference = -difference }
                    if len(first) <= 42 && len(second) <= 42 && (difference < bestDifference || difference == bestDifference && len(first) < bestFirst) {
                        candidate = []string{first, second}
                        bestDifference, bestFirst = difference, len(first)
                    }
                }
            }
            if candidate == nil { skipped++ } else {
                if !sameText(c.text, candidate) { changed++ }
                e.cues[i].text = candidate
            }
        }
        output = append(output, fmt.Sprintf("BALANCE changed=%d skipped=%d dialogue=%d", changed, skipped, dialogues))
    case "STRIP", "CLEANHI":
        removedItems, labels, removedLines, removedCues := 0, 0, 0, 0
        var result []cue
        for _, c := range e.cues {
            var lines []string
            if name == "STRIP" {
                var tags int
                lines, _, tags = converted(c.text, 0)
                removedItems += tags
                removedLines += len(c.text)-len(lines)
            } else {
                for _, line := range c.text {
                    text, segments, names := cleanHI(line)
                    removedItems += segments
                    labels += names
                    if text == "" || text == "-" { removedLines++ } else { lines = append(lines, text) }
                }
            }
            if len(lines) == 0 {
                removedCues++
            } else {
                c.text = lines
                result = append(result, c)
            }
        }
        e.cues = result
        if name == "STRIP" { output = append(output, fmt.Sprintf("STRIP tags=%d removed_lines=%d removed_cues=%d", removedItems, removedLines, removedCues)) } else {
            output = append(output, fmt.Sprintf("CLEANHI segments=%d labels=%d removed_lines=%d removed_cues=%d", removedItems, labels, removedLines, removedCues))
        }
    case "REPLACE":
        old, replacement, _ := strings.Cut(a.raw[0], "|")
        count, cues := 0, 0
        for i := range e.cues {
            matches := 0
            for j, text := range e.cues[i].text {
                matches += strings.Count(text, old)
                e.cues[i].text[j] = strings.ReplaceAll(text, old, replacement)
            }
            count += matches
            if matches > 0 { cues++ }
        }
        output = append(output, fmt.Sprintf("REPLACE count=%d cues=%d", count, cues))
    }
    return output
}
func commandResult(e *editor, line string) (output []string) {
    defer func() {
        if message := recover(); message != nil { output = []string{"ERROR "+message.(string)} }
    }()
    return e.execute(line)
}
func loadBlock(block []string, position int, e *editor) string {
    index, valid := unsigned(block[0])
    if !valid || len(block[0]) > 6 { return fmt.Sprintf("BAD CUE %d: index", position) }
    var start, end int64
    valid = false
    if len(block) >= 2 && len(block[1]) == 29 && block[1][12:17] == " --> " {
        var ok bool
        start, valid = timeValue(block[1][:12])
        end, ok = timeValue(block[1][17:])
        valid = valid && ok
    }
    if !valid { return fmt.Sprintf("BAD CUE %d: time", position) }
    if len(block) < 3 { return fmt.Sprintf("BAD CUE %d: no text", position) }
    e.cues = append(e.cues, cue{index, start, end, append([]string(nil), block[2:]...)})
    return ""
}
func main() {
    scanner := bufio.NewScanner(os.Stdin)
    output := bufio.NewWriter(os.Stdout)
    defer output.Flush()
    e := editor{}
    var block []string
    blocks, bad := 0, 0
    finish := func() {
        if len(block) == 0 { return }
        blocks++
        if message := loadBlock(block, blocks, &e); message != "" {
            fmt.Fprintln(output, message)
            bad++
        }
        block = nil
    }
    for scanner.Scan() {
        line := scanner.Text()
        if line == "###" {
            finish()
            break
        }
        if line == "" { finish() } else { block = append(block, line) }
    }
    fmt.Fprintf(output, "LOAD cues=%d bad=%d\n", len(e.cues), bad)
    scanner.Scan()
    count, _ := strconv.Atoi(scanner.Text())
    for i := 0; i < count && scanner.Scan(); i++ {
        for _, line := range commandResult(&e, scanner.Text()) { fmt.Fprintln(output, line) }
    }
}
