package main

import (
    "bufio"
    "fmt"
    "os"
    "slices"
    "sort"
    "strconv"
    "strings"
)

const (
    tennis = iota
    tableTennis
    badminton
    volleyball
    bowling
    dartsSport
)
type segment struct { a, b, kind, loser int }
type rallyState struct {
    points, games, sets, substitutions, timeouts [2]int
    stats [2][10]int
    lineup [2][6]int
    segments [7]segment
    segmentCount, server, winner int
}
type bowlingState struct {
    rolls [21]int
    count int
}
type dartsState struct {
    remaining, legs, sets [2]int
    stats [2][8]int
    segments [9][2]int
    turn [3]int
    segmentCount, server, turnStart, turnCount, turnScore, legNumber, winner int
}
type match struct {
    id string
    names [2]string
    sport, first, sets, games, final, start, legs int
    noAd bool
    initialLineup [2][6]int
    state any
    history []any
}
type bowlingInfo struct {
    start, count, score [10]int
    closed, final [10]bool
    marks [21]byte
    standing, frame int
    fresh, finished bool
}
type dart struct {
    name string
    value int
    double bool
}
var dartKinds []dart
var matches = map[string]*match{}

func fail(message string) { panic(message) }
func number(s string) int {
    n, _ := strconv.Atoi(s)
    return n
}
func pairText(p [2]int, first int) string { return fmt.Sprintf("%d-%d", p[first], p[1-first]) }
func initializeDarts() {
    for _, multiplier := range []int{1, 3, 2} {
        prefix := "S"
        if multiplier == 2 { prefix = "D" }
        if multiplier == 3 { prefix = "T" }
        for n := 20; n >= 1; n-- {
            dartKinds = append(dartKinds, dart{fmt.Sprintf("%s%d", prefix, n), multiplier*n, multiplier == 2})
        }
    }
    dartKinds = append(dartKinds, dart{"25", 25, false}, dart{"BULL", 50, true}, dart{"MISS", 0, false})
}
func doubleDart(value int) int {
    if value == 50 { return 61 }
    if value >= 2 && value <= 40 && value%2 == 0 { return 60-value/2 }
    return -1
}
func checkout(score, maximum int) []int {
    if last := doubleDart(score); last >= 0 { return []int{last} }
    if maximum >= 2 {
        for i := 0; i < 62; i++ {
            if last := doubleDart(score-dartKinds[i].value); last >= 0 { return []int{i, last} }
        }
    }
    if maximum >= 3 && score <= 170 {
        for i := 0; i < 62; i++ {
            for j := 0; j < 62; j++ {
                if last := doubleDart(score-dartKinds[i].value-dartKinds[j].value); last >= 0 { return []int{i, j, last} }
            }
        }
    }
    return nil
}
func dartNames(ids []int) string {
    result := make([]string, len(ids))
    for i, id := range ids { result[i] = dartKinds[id].name }
    return strings.Join(result, " ")
}
func describeBowling(state bowlingState) bowlingInfo {
    info := bowlingInfo{standing: 10, fresh: true}
    for i := 0; i < state.count; i++ {
        frame, pins := info.frame, state.rolls[i]
        if info.count[frame] == 0 { info.start[frame] = i }
        mark := byte('0'+pins)
        switch {
        case info.fresh && pins == 10: mark = 'X'
        case pins == info.standing: mark = '/'
        case pins == 0: mark = '-'
        }
        info.marks[i] = mark
        info.count[frame]++
        info.standing -= pins
        info.fresh = false
        ended := false
        if frame < 9 { ended = pins == 10 && info.count[frame] == 1 || info.count[frame] == 2 } else if info.count[frame] == 2 {
            ended = state.rolls[info.start[frame]]+pins < 10
        } else if info.count[frame] == 3 { ended = true }
        if ended {
            info.closed[frame] = true
            if frame == 9 { info.finished = true } else { info.frame++ }
            info.standing, info.fresh = 10, true
        } else if frame == 9 && info.standing == 0 { info.standing, info.fresh = 10, true }
    }
    for frame := 0; frame < 10; frame++ {
        if info.count[frame] == 0 { continue }
        start := info.start[frame]
        if frame == 9 {
            info.final[frame] = info.closed[frame]
            for j := 0; j < info.count[frame]; j++ { info.score[frame] += state.rolls[start+j] }
        } else if state.rolls[start] == 10 {
            info.final[frame] = state.count >= start+3
            if info.final[frame] { info.score[frame] = 10+state.rolls[start+1]+state.rolls[start+2] }
        } else if info.count[frame] >= 2 {
            total := state.rolls[start]+state.rolls[start+1]
            info.final[frame] = total < 10 || state.count >= start+3
            if info.final[frame] {
                info.score[frame] = total
                if total == 10 { info.score[frame] += state.rolls[start+2] }
            }
        }
    }
    return info
}
func bowlingTotal(info bowlingInfo) int {
    total := 0
    for _, score := range info.score { total += score }
    return total
}
func finalSet(m *match, s rallyState) bool { return s.sets[0] == m.sets/2 && s.sets[1] == m.sets/2 }
func tennisKind(m *match, s rallyState) int {
    if finalSet(m, s) && m.final == 3 { return 2 }
    if s.games[0] == 6 && s.games[1] == 6 && !(finalSet(m, s) && m.final == 2) { return 1 }
    return 0
}
func rallyServer(m *match, s rallyState) int {
    if m.sport == tennis && tennisKind(m, s) != 0 { return s.server ^ ((s.points[0]+s.points[1]+1)/2%2) }
    if m.sport == tableTennis {
        first, played := m.first ^ (s.segmentCount%2), s.points[0]+s.points[1]
        if played < 20 { return first ^ (played/2%2) }
        return first ^ (played%2)
    }
    return s.server
}
func normalGame(m *match, own, other int) bool { return own >= 4 && (m.noAd || own-other >= 2) }
func addRally(m *match, s *rallyState, side int) {
    other, server := 1-side, rallyServer(m, *s)
    s.stats[side][0]++
    s.stats[server][1]++
    if side == server { s.stats[side][2]++ }
    s.stats[side][3]++
    s.stats[other][3] = 0
    s.stats[side][4] = max(s.stats[side][4], s.stats[side][3])
    kind := 0
    if m.sport == tennis {
        kind = tennisKind(m, *s)
        receiver := 1-s.server
        if kind == 0 && normalGame(m, s.points[receiver]+1, s.points[s.server]) {
            s.stats[receiver][8]++
            if side == receiver { s.stats[receiver][9]++ }
        }
    }
    s.points[side]++
    if m.sport == tennis {
        target := 7
        if kind == 2 || kind == 1 && finalSet(m, *s) && m.final == 1 { target = 10 }
        ended := normalGame(m, s.points[side], s.points[other])
        if kind != 0 { ended = s.points[side] >= target && s.points[side]-s.points[other] >= 2 }
        if !ended { return }
        if kind == 0 {
            s.stats[s.server][5]++
            if side == s.server { s.stats[side][6]++ } else { s.stats[side][7]++ }
        }
        var finished segment
        if kind == 2 { finished = segment{s.points[0], s.points[1], 2, 0} } else {
            s.games[side]++
            loser := 0
            if kind != 0 { loser = s.points[other] }
            finished = segment{s.games[0], s.games[1], kind, loser}
        }
        s.server ^= 1
        s.points = [2]int{}
        if kind != 0 || s.games[side] >= 6 && s.games[side]-s.games[other] >= 2 {
            s.segments[s.segmentCount] = finished
            s.segmentCount++
            s.sets[side]++
            s.games = [2]int{}
            if s.sets[side] == m.sets/2+1 { s.winner = side }
        }
        return
    }
    if m.sport == volleyball && side != s.server {
        s.server = side
        first := s.lineup[side][0]
        copy(s.lineup[side][:5], s.lineup[side][1:])
        s.lineup[side][5] = first
    }
    if m.sport == badminton { s.server = side }
    target := 25
    if m.sport == tableTennis { target = 11 }
    if m.sport == badminton { target = 21 }
    if m.sport == volleyball && s.segmentCount == 4 { target = 15 }
    ended := s.points[side] >= target && s.points[side]-s.points[other] >= 2
    if m.sport == badminton && s.points[side] == 30 { ended = true }
    if !ended { return }
    s.segments[s.segmentCount] = segment{s.points[0], s.points[1], 0, 0}
    s.segmentCount++
    s.sets[side]++
    needed := 3
    if m.sport == tableTennis { needed = m.games/2+1 }
    if m.sport == badminton { needed = 2 }
    if s.sets[side] == needed { s.winner = side } else {
        s.points = [2]int{}
        if m.sport == volleyball {
            s.lineup = m.initialLineup
            s.substitutions, s.timeouts = [2]int{}, [2]int{}
            s.server = m.first ^ (s.segmentCount%2)
        }
    }
}
func endDartsTurn(s *dartsState) {
    s.server ^= 1
    s.turnStart = s.remaining[s.server]
    s.turnCount, s.turnScore = 0, 0
}
func completedDartsTurn(s *dartsState, side int) {
    s.stats[side][3] = max(s.stats[side][3], s.turnScore)
    if s.turnScore >= 100 { s.stats[side][4]++ }
    if s.turnScore == 180 { s.stats[side][5]++ }
}
func addDart(m *match, s *dartsState, id int) {
    side := s.server
    remaining, dart := s.remaining[side], dartKinds[id]
    s.stats[side][0]++
    if remaining == 50 || remaining <= 40 && remaining%2 == 0 { s.stats[side][6]++ }
    s.turn[s.turnCount] = id
    s.turnCount++
    s.turnScore += dart.value
    s.stats[side][1] += dart.value
    after := remaining-dart.value
    if after < 0 || after == 1 || after == 0 && !dart.double {
        s.stats[side][1] -= s.turnScore
        s.stats[side][2]++
        s.remaining[side] = s.turnStart
        endDartsTurn(s)
        return
    }
    s.remaining[side] = after
    if after == 0 {
        s.stats[side][7]++
        completedDartsTurn(s, side)
        s.legs[side]++
        if s.legs[side] == m.legs {
            s.segments[s.segmentCount] = s.legs
            s.segmentCount++
            s.sets[side]++
            if s.sets[side] == m.sets {
                s.winner = side
                return
            }
            s.legs = [2]int{}
        }
        s.legNumber++
        s.remaining = [2]int{m.start, m.start}
        s.server = m.first ^ ((s.legNumber-1)%2)
        s.turnStart = m.start
        s.turnCount, s.turnScore = 0, 0
    } else if s.turnCount == 3 {
        completedDartsTurn(s, side)
        endDartsTurn(s)
    }
}
func finished(m *match) bool {
    switch s := m.state.(type) {
    case bowlingState: return describeBowling(s).finished
    case dartsState: return s.winner >= 0
    default: return s.(rallyState).winner >= 0
    }
}
func winningSide(m *match) int {
    if s, ok := m.state.(dartsState); ok { return s.winner }
    return m.state.(rallyState).winner
}
func segmentText(s segment, first int) string {
    result := pairText([2]int{s.a, s.b}, first)
    if s.kind == 1 { result += fmt.Sprintf("(%d)", s.loser) }
    if s.kind == 2 { result = "["+result+"]" }
    return result
}
func situation(m *match, s rallyState, side int) string {
    next := s
    addRally(m, &next, side)
    if next.winner >= 0 { return "match point" }
    if next.segmentCount != s.segmentCount {
        if m.sport == tableTennis || m.sport == badminton { return "game point" }
        return "set point"
    }
    if m.sport == tennis && tennisKind(m, s) == 0 && next.server != s.server {
        if rallyServer(m, s) == side { return "game point" }
        return "break point"
    }
    return ""
}
func score(m *match) string {
    if s, ok := m.state.(bowlingState); ok {
        info := describeBowling(s)
        result := m.id+": "+m.names[0]
        cumulative := 0
        for frame := 0; frame < 10; frame++ {
            if info.count[frame] == 0 { continue }
            start := info.start[frame]
            display := string(info.marks[start:start+info.count[frame]])
            cumulative += info.score[frame]
            if info.final[frame] { display += fmt.Sprintf("(%d)", cumulative) }
            result += " "+display
        }
        return result
    }
    over, server := finished(m), 0
    if s, ok := m.state.(dartsState); ok { server = s.server } else { server = rallyServer(m, m.state.(rallyState)) }
    names := m.names
    if !over { names[server] += "*" }
    result := m.id+": "+names[0]+" vs "+names[1]
    if s, ok := m.state.(dartsState); ok {
        result += " sets "+pairText(s.sets, 0)+" legs "+pairText(s.legs, 0)+" score "+pairText(s.remaining, 0)
        if !over {
            if s.turnCount > 0 { result += " turn "+dartNames(s.turn[:s.turnCount]) }
            if finish := checkout(s.remaining[s.server], 3-s.turnCount); len(finish) > 0 { result += " checkout "+dartNames(finish) }
        }
        return result
    }
    s := m.state.(rallyState)
    for i := 0; i < s.segmentCount; i++ { result += " "+segmentText(s.segments[i], 0) }
    if !over {
        if m.sport == tennis {
            kind := tennisKind(m, s)
            if kind == 2 { result += " ["+pairText(s.points, 0)+"]" } else {
                result += " "+pairText(s.games, 0)+" "
                if kind != 0 { result += pairText(s.points, 0) } else if !m.noAd && s.points[0] >= 3 && s.points[1] >= 3 {
                    if s.points[0] == s.points[1] { result += "40-40" } else if s.points[0] > s.points[1] { result += "AD-40" } else { result += "40-AD" }
                } else {
                    labels := []string{"0", "15", "30", "40"}
                    result += labels[s.points[0]]+"-"+labels[s.points[1]]
                }
            }
        } else {
            result += " "+pairText(s.points, 0)
            if m.sport == volleyball { result += fmt.Sprintf(" server %d", s.lineup[s.server][0]) }
        }
        for side := 0; side < 2; side++ {
            if label := situation(m, s, side); label != "" { result += " ("+label+" "+m.names[side]+")" }
        }
    }
    return result
}
func statistics(m *match) []string {
    if s, ok := m.state.(bowlingState); ok {
        info := describeBowling(s)
        strikes, spares, open := 0, 0, 0
        for i := 0; i < s.count; i++ {
            if info.marks[i] == 'X' { strikes++ }
            if info.marks[i] == '/' { spares++ }
        }
        for i := 0; i < 10; i++ {
            start := info.start[i]
            if info.count[i] >= 2 && s.rolls[start] != 10 && s.rolls[start]+s.rolls[start+1] < 10 { open++ }
        }
        for !info.finished {
            s.rolls[s.count] = info.standing
            s.count++
            info = describeBowling(s)
        }
        return []string{fmt.Sprintf("%s %s: strikes %d spares %d open %d max %d", m.id, m.names[0], strikes, spares, open, bowlingTotal(info))}
    }
    var result []string
    for side := 0; side < 2; side++ {
        line := m.id+" "+m.names[side]+": "
        if state, ok := m.state.(dartsState); ok {
            s := state.stats[side]
            average := 0
            if s[0] > 0 { average = s[1]*300/s[0] }
            line += fmt.Sprintf("darts %d average %d.%02d busts %d high %d tons %d 180s %d doubles %d/%d", s[0], average/100, average%100, s[2], s[3], s[4], s[5], s[7], s[6])
        } else {
            r := m.state.(rallyState)
            s := r.stats[side]
            line += fmt.Sprintf("points %d serve %d/%d run %d", s[0], s[2], s[1], s[4])
            if m.sport == tennis { line += fmt.Sprintf(" holds %d/%d breaks %d break points %d/%d", s[6], s[5], s[7], s[9], s[8]) }
            if m.sport == volleyball {
                var lineup []string
                for _, value := range r.lineup[side] { lineup = append(lineup, strconv.Itoa(value)) }
                line += fmt.Sprintf(" subs %d timeouts %d lineup %s", r.substitutions[side], r.timeouts[side], strings.Join(lineup, ","))
            }
        }
        result = append(result, line)
    }
    return result
}
func result(m *match) string {
    if !finished(m) { fail("match not finished") }
    if s, ok := m.state.(bowlingState); ok { return fmt.Sprintf("%s: %s %d", m.id, m.names[0], bowlingTotal(describeBowling(s))) }
    first := winningSide(m)
    line := m.id+": "+m.names[first]+" def. "+m.names[1-first]
    if s, ok := m.state.(dartsState); ok {
        for i := 0; i < s.segmentCount; i++ { line += " "+pairText(s.segments[i], first) }
    } else {
        s := m.state.(rallyState)
        for i := 0; i < s.segmentCount; i++ { line += " "+segmentText(s.segments[i], first) }
    }
    return line
}
func createMatch(a []string) {
    if _, exists := matches[a[1]]; exists { fail("duplicate match") }
    m := &match{id: a[1], sport: slices.Index([]string{"TENNIS", "TABLETENNIS", "BADMINTON", "VOLLEYBALL", "BOWLING", "DARTS"}, a[2]), sets: 3, games: 5, start: 501, legs: 1}
    m.names[0] = a[3]
    if m.sport != bowling { m.names[1] = a[4] }
    if m.sport == dartsSport { m.sets = 1 }
    optionStart := 5
    if m.sport == bowling { optionStart = 4 }
    if m.sport == volleyball { optionStart = 7 }
    allowed := map[string][]string{}
    switch m.sport {
    case tennis:
        allowed = map[string][]string{"SETS":{"3", "5"}, "DEUCE":{"AD", "NOAD"}, "FINAL":{"TB7", "TB10", "ADV", "SUPER"}, "FIRST":{"A", "B"}}
    case tableTennis: allowed = map[string][]string{"GAMES":{"5", "7"}, "FIRST":{"A", "B"}}
    case badminton, volleyball: allowed = map[string][]string{"FIRST":{"A", "B"}}
    case dartsSport:
        allowed = map[string][]string{"START":{"301", "501", "701"}, "SETS":{"1", "2", "3", "4", "5"}, "LEGS":{"1", "2", "3", "4", "5"}, "FIRST":{"A", "B"}}
    }
    seen := map[string]bool{}
    for _, item := range a[optionStart:] {
        pair := strings.Split(item, "=")
        if len(pair) != 2 { fail("invalid option") }
        values, exists := allowed[pair[0]]
        if !exists || seen[pair[0]] || slices.Index(values, pair[1]) < 0 { fail("invalid option") }
        seen[pair[0]] = true
        switch pair[0] {
        case "FIRST": m.first = slices.Index(values, pair[1])
        case "SETS": m.sets = number(pair[1])
        case "GAMES": m.games = number(pair[1])
        case "START": m.start = number(pair[1])
        case "LEGS": m.legs = number(pair[1])
        case "DEUCE": m.noAd = pair[1] == "NOAD"
        case "FINAL": m.final = slices.Index(values, pair[1])
        }
    }
    switch m.sport {
    case bowling: m.state = bowlingState{}
    case dartsSport: m.state = dartsState{remaining: [2]int{m.start, m.start}, server: m.first, turnStart: m.start, legNumber: 1, winner: -1}
    default:
        s := rallyState{server: m.first, winner: -1}
        if m.sport == volleyball {
            for side := 0; side < 2; side++ {
                for i, value := range strings.Split(a[5+side], ",") { m.initialLineup[side][i] = number(value) }
            }
            s.lineup = m.initialLineup
        }
        m.state = s
    }
    matches[m.id] = m
}
func execute(a []string) []string {
    command := a[0]
    if command == "MATCH" {
        createMatch(a)
        return nil
    }
    if command == "CHECKOUT" {
        finish := checkout(number(a[1]), 3)
        display := "none"
        if len(finish) > 0 { display = dartNames(finish) }
        return []string{"checkout "+a[1]+": "+display}
    }
    if command == "STANDINGS" {
        totals := map[string][2]int{}
        for _, m := range matches {
            if m.sport == bowling || !finished(m) { continue }
            first := winningSide(m)
            for side := 0; side < 2; side++ {
                value := totals[m.names[side]]
                if side == first { value[0]++ } else { value[1]++ }
                totals[m.names[side]] = value
            }
        }
        var names []string
        for name := range totals { names = append(names, name) }
        sort.Slice(names, func(i, j int) bool {
            x, y := totals[names[i]], totals[names[j]]
            if x[0] != y[0] { return x[0] > y[0] }
            if x[1] != y[1] { return x[1] < y[1] }
            return names[i] < names[j]
        })
        var displays []string
        for _, name := range names { displays = append(displays, name+" "+pairText(totals[name], 0)) }
        display := "none"
        if len(displays) > 0 { display = strings.Join(displays, ", ") }
        return []string{"standings: "+display}
    }
    m, exists := matches[a[1]]
    if !exists { fail("unknown match") }
    switch command {
    case "SCORE": return []string{score(m)}
    case "STATS": return statistics(m)
    case "RESULT": return []string{result(m)}
    case "UNDO":
        if len(m.history) == 0 { fail("nothing to undo") }
        m.state = m.history[len(m.history)-1]
        m.history = m.history[:len(m.history)-1]
        return nil
    }
    allowed := command == "POINT" && m.sport <= volleyball || command == "ROLL" && m.sport == bowling || command == "THROW" && m.sport == dartsSport || (command == "SUB" || command == "TIMEOUT") && m.sport == volleyball
    if !allowed { fail("wrong event") }
    count := 1
    if command == "POINT" { count = len(a[2]) }
    if command == "ROLL" || command == "THROW" { count = len(a)-2 }
    for i := 0; i < count; i++ {
        if finished(m) { fail("match over") }
        value, position, side := 0, -1, 0
        switch command {
        case "POINT":
            if a[2][i] == 'B' { value = 1 }
        case "ROLL":
            value = number(a[i+2])
            if value > describeBowling(m.state.(bowlingState)).standing { fail("too many pins") }
        case "THROW":
            value = slices.IndexFunc(dartKinds, func(d dart) bool { return d.name == a[i+2] })
            if value < 0 { fail("invalid dart") }
        case "SUB", "TIMEOUT":
            if a[2] == "B" { side = 1 }
            s := m.state.(rallyState)
            if command == "TIMEOUT" {
                if s.timeouts[side] >= 2 { fail("no timeouts left") }
            } else {
                leaving := number(a[3])
                value = number(a[4])
                position = slices.Index(s.lineup[side][:], leaving)
                if position < 0 { fail("player not on court") }
                if slices.Contains(s.lineup[side][:], value) { fail("player already on court") }
                if s.substitutions[side] >= 6 { fail("no substitutions left") }
            }
        }
        m.history = append(m.history, m.state)
        switch command {
        case "POINT":
            s := m.state.(rallyState)
            addRally(m, &s, value)
            m.state = s
        case "ROLL":
            s := m.state.(bowlingState)
            s.rolls[s.count] = value
            s.count++
            m.state = s
        case "THROW":
            s := m.state.(dartsState)
            addDart(m, &s, value)
            m.state = s
        case "SUB", "TIMEOUT":
            s := m.state.(rallyState)
            if command == "SUB" {
                s.lineup[side][position] = value
                s.substitutions[side]++
            } else { s.timeouts[side]++ }
            m.state = s
        }
    }
    return nil
}
func commandResult(a []string) (result []string) {
    defer func() {
        if message := recover(); message != nil { result = []string{"ERROR "+message.(string)} }
    }()
    return execute(a)
}
func main() {
    initializeDarts()
    scanner := bufio.NewScanner(os.Stdin)
    scanner.Scan()
    count := number(scanner.Text())
    output := bufio.NewWriter(os.Stdout)
    defer output.Flush()
    for i := 0; i < count && scanner.Scan(); i++ {
        for _, line := range commandResult(strings.Split(scanner.Text(), " ")) { fmt.Fprintln(output, line) }
    }
}
