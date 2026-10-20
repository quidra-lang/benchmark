package main

import (
    "bufio"
    "fmt"
    "os"
    "regexp"
    "sort"
    "strconv"
    "strings"
)

type Position [2][26]int

type State struct {
    Position Position
    Side, Cube, Owner int
    Pending, Over bool
    Score [2]int
}

type Move struct {
    From, To int
}

type Play struct {
    Position Position
    Moves, Key []Move
    Hits uint32
    Die int
    Notation string
}

type Entry struct {
    Record string
    Before, After State
}

type Engine struct {
    State State
    History, Redo []Entry
}

type Evaluation struct {
    E, P, S, H, R, A, G int
}

type Random struct {
    Value int64
}

type Result struct {
    Winner int
    Kind string
    Points, Turns, Start int
}
var out = bufio.NewWriter(os.Stdout)
var playElement = regexp.MustCompile(`^(bar|[1-9]|1[0-9]|2[0-4])(?:/(?:[1-9]|1[0-9]|2[0-4])\*?)*(?:/off|/(?:[1-9]|1[0-9]|2[0-4])\*?)(?:\([234]\))?$`)

func emit(s string) {
    fmt.Fprintln(out, s)
}

func color(side int) string {
    return []string{"W", "B"}[side]
}

func owner(s State) string {
    if s.Owner < 0 {
        return "center"
    }
    return color(s.Owner)
}

func number(text string) int {
    value, _ := strconv.Atoi(text)
    return value
}

func initial() State {
    s := State{Cube: 1, Owner: -1}
    for side := 0; side < 2; side++ {
        s.Position[side][24] = 2
        s.Position[side][13] = 5
        s.Position[side][8] = 3
        s.Position[side][6] = 5
    }
    return s
}

func (r *Random) next() int64 {
    r.Value = r.Value * 48271 % 2147483647
    return r.Value
}

func (r *Random) die() int {
    return int(r.next() % 6) + 1
}

func pips(pos Position, side int) int {
    total := 0
    for p := 1; p <= 25; p++ {
        total += p * pos[side][p]
    }
    return total
}

func keith(pos Position, side int) int {
    c := pos[side]
    total := pips(pos, side) + 2 * max(c[1] - 1, 0) + max(c[2] - 1, 0) + max(c[3] - 3, 0)
    for p := 4; p <= 6; p++ {
        if c[p] == 0 {
            total++
        }
    }
    return total
}

func contact(pos Position) bool {
    white, black := 0, 25
    if pos[0][25] > 0 {
        white = 25
    }
    if pos[1][25] > 0 {
        black = 0
    }
    for p := 1; p <= 24; p++ {
        if pos[0][p] > 0 {
            white = max(white, p)
        }
        if pos[1][p] > 0 {
            black = min(black, 25 - p)
        }
    }
    return white > black
}

func evaluate(pos Position, side int) Evaluation {
    other := 1 - side
    value := Evaluation{P: pips(pos, other) - pips(pos, side), G: pos[other][25] - pos[side][25]}
    run := 0
    for p := 1; p <= 24; p++ {
        if pos[side][p] >= 2 {
            run++
            value.R = max(value.R, run)
            if p <= 6 {
                value.H++
            }
            if p >= 19 {
                value.A++
            }
        } else {
            run = 0
        }
        if pos[side][p] == 1 {
            distances := [25]bool{}
            for q := 0; q < p; q++ {
                if pos[other][25 - q] > 0 {
                    distances[p - q] = true
                }
            }
            for a := 1; a <= 6; a++ {
                for b := 1; b <= 6; b++ {
                    if distances[a] || distances[b] || distances[a + b] || a == b && (distances[3 * a] || distances[4 * a]) {
                        value.S++
                    }
                }
            }
        }
    }
    value.E = 2 * value.P - value.S + 4 * value.H + 3 * value.R + 3 * value.A + 6 * value.G
    return value
}

func cubeDecision(s State, prohibited bool) string {
    if s.Owner == 1 - s.Side || s.Cube == 64 || prohibited {
        return "unavailable"
    }
    if contact(s.Position) {
        e := evaluate(s.Position, s.Side).E
        if e < 60 {
            return "no double"
        }
        if e <= 100 {
            return "double take"
        }
        return "double drop"
    }
    v := 8 * keith(s.Position, s.Side) - 7 * keith(s.Position, 1 - s.Side)
    limit := 21
    if s.Owner < 0 {
        limit = 28
    }
    if v > limit {
        return "no double"
    }
    if v >= 14 {
        return "double take"
    }
    return "double drop"
}

func submoves(pos Position, side, die int) []Move {
    sources := []int{}
    if pos[side][25] > 0 {
        sources = append(sources, 25)
    } else {
        for p := 24; p >= 1; p-- {
            if pos[side][p] > 0 {
                sources = append(sources, p)
            }
        }
    }
    home := pos[side][25] == 0
    for p := 7; p <= 24; p++ {
        if pos[side][p] > 0 {
            home = false
        }
    }
    moves := []Move{}
    for _, from := range sources {
        to := from - die
        if to >= 1 {
            if pos[1 - side][25 - to] < 2 {
                moves = append(moves, Move{from, to})
            }
        } else if home {
            allowed := true
            if to < 0 {
                for p := from + 1; p <= 6; p++ {
                    if pos[side][p] > 0 {
                        allowed = false
                    }
                }
            }
            if allowed {
                moves = append(moves, Move{from, 0})
            }
        }
    }
    return moves
}

func applySubmove(pos Position, side int, move Move) (Position, bool) {
    pos[side][move.From]--
    pos[side][move.To]++
    hit := move.To > 0 && pos[1 - side][25 - move.To] == 1
    if hit {
        pos[1 - side][25 - move.To] = 0
        pos[1 - side][25]++
    }
    return pos, hit
}

func moveLess(a, b Move) bool {
    if a.From != b.From {
        return a.From > b.From
    }
    return a.To > b.To
}

func canonical(moves []Move, hits uint32) ([]Move, string) {
    key := append([]Move{}, moves...)
    sort.Slice(key, func(i, j int) bool {
        return moveLess(key[i], key[j])
    })
    for {
        first, second := -1, -1
        for i, a := range key {
            if a.To == 0 || hits & (1 << a.To) != 0 {
                continue
            }
            for j, b := range key {
                if b.From == a.To {
                    first = i
                    second = j
                    break
                }
            }
            if first >= 0 {
                break
            }
        }
        if first < 0 {
            break
        }
        combined := Move{key[first].From, key[second].To}
        next := []Move{}
        for i, pair := range key {
            if i != first && i != second {
                next = append(next, pair)
            }
        }
        key = append(next, combined)
        sort.Slice(key, func(i, j int) bool {
            return moveLess(key[i], key[j])
        })
    }
    parts := []string{}
    marked := map[int]bool{}
    for i := 0; i < len(key); {
        pair := key[i]
        j := i + 1
        for j < len(key) && key[j] == pair {
            j++
        }
        from, to := strconv.Itoa(pair.From), strconv.Itoa(pair.To)
        if pair.From == 25 {
            from = "bar"
        }
        if pair.To == 0 {
            to = "off"
        }
        part := from + "/" + to
        if hits & (1 << pair.To) != 0 && !marked[pair.To] {
            part += "*"
            marked[pair.To] = true
        }
        if j - i >= 2 {
            part += fmt.Sprintf("(%d)", j - i)
        }
        parts = append(parts, part)
        i = j
    }
    if len(parts) == 0 {
        return key, "none"
    }
    return key, strings.Join(parts, " ")
}

func keyLess(a, b []Move) bool {
    for i := 0; i < len(a) && i < len(b); i++ {
        if a[i] != b[i] {
            return moveLess(a[i], b[i])
        }
    }
    return len(a) > len(b)
}

func enumerate(pos Position, side, d1, d2 int) ([]Play, []Play, int) {
    dice := []int{d1, d2}
    if d1 == d2 {
        dice = []int{d1, d1, d1, d1}
    }
    possible := []Play{}
    maximum := 0
    var search func(Position, []int, []Move, uint32, int)
    search = func(current Position, left []int, path []Move, hits uint32, first int) {
        copied := append([]Move{}, path...)
        possible = append(possible, Play{Position: current, Moves: copied, Hits: hits, Die: first})
        maximum = max(maximum, len(path))
        seenDie := map[int]bool{}
        for i, die := range left {
            if seenDie[die] {
                continue
            }
            seenDie[die] = true
            rest := append([]int{}, left[: i]...)
            rest = append(rest, left[i + 1:]...)
            for _, move := range submoves(current, side, die) {
                next, hit := applySubmove(current, side, move)
                mask := hits
                if hit {
                    mask |= 1 << move.To
                }
                used := first
                if len(path) == 0 {
                    used = die
                }
                search(next, rest, append(copied, move), mask, used)
            }
        }
    }
    search(pos, dice, nil, 0, 0)
    larger := false
    if maximum == 1 && d1 != d2 {
        for _, play := range possible {
            if len(play.Moves) == 1 && play.Die == max(d1, d2) {
                larger = true
            }
        }
    }
    legal := []Play{}
    positions := map[Position]bool {}
    for _, play := range possible {
        if len(play.Moves) != maximum || larger && play.Die != max(d1, d2) || positions[play.Position] {
            continue
        }
        play.Key, play.Notation = canonical(play.Moves, play.Hits)
        legal = append(legal, play)
        positions[play.Position] = true
    }
    sort.Slice(legal, func(i, j int) bool {
        return keyLess(legal[i].Key, legal[j].Key)
    })
    return legal, possible, maximum
}

func best(plays []Play, side int) (Play, int) {
    chosen := plays[0]
    score := evaluate(chosen.Position, side).E
    for _, play := range plays[1:] {
        value := evaluate(play.Position, side).E
        if value > score {
            chosen, score = play, value
        }
    }
    return chosen, score
}

func multiplier(kind string) int {
    switch kind {
    case "gammon":
        return 2
    case "backgammon":
        return 3
    }
    return 1
}

func finish(s *State, winner int, kind string) Result {
    s.Pending = false
    s.Over = true
    points := multiplier(kind) * s.Cube
    s.Score[winner] += points
    return Result{Winner: winner, Kind: kind, Points: points}
}

func bearResult(s *State, winner int) Result {
    other := 1 - winner
    kind := "single"
    if s.Position[other][0] == 0 {
        kind = "gammon"
        back := s.Position[other][25] > 0
        for p := 19; p <= 24; p++ {
            back = back || s.Position[other][p] > 0
        }
        if back {
            kind = "backgammon"
        }
    }
    return finish(s, winner, kind)
}

func resultLine(result Result) string {
    return fmt.Sprintf("result %s %s %d", color(result.Winner), result.Kind, result.Points)
}

func (e *Engine) makePlay(play Play, d1, d2 int) {
    before := e.State
    side := e.State.Side
    e.State.Position = play.Position
    var result *Result
    if play.Position[side][0] == 15 {
        value := bearResult(&e.State, side)
        result = &value
    } else {
        e.State.Side = 1 - side
    }
    record := fmt.Sprintf("%s %d-%d %s", color(side), d1, d2, play.Notation)
    e.History = append(e.History, Entry{record, before, e.State})
    e.Redo = nil
    if result != nil {
        emit(resultLine(*result))
    }
}

func parsePlay(words []string) ([]Move, bool) {
    if len(words) == 1 && words[0] == "none" {
        return nil, true
    }
    moves := []Move{}
    for _, word := range words {
        if !playElement.MatchString(word) {
            return nil, false
        }
        count := 1
        if strings.HasSuffix(word, ")") {
            count = number(word[len(word) - 2: len(word) - 1])
            word = word[: len(word) - 3]
        }
        parts := strings.Split(word, "/")
        points := []int{}
        for _, part := range parts {
            point := 0
            if part == "bar" {
                point = 25
            } else if part != "off" {
                point = number(strings.TrimSuffix(part, "*"))
            }
            points = append(points, point)
        }
        for i := 0; i + 1 < len(points); i++ {
            if points[i] <= points[i + 1] {
                return nil, false
            }
            for j := 0; j < count; j++ {
                moves = append(moves, Move{points[i], points[i + 1]})
            }
        }
    }
    return moves, true
}

func validatePlay(pos Position, side int, moves []Move, legal, possible []Play, maximum int) (Play, string) {
    final := pos
    destinations := map[int]bool{}
    nonbar, bear := false, false
    for _, move := range moves {
        final[side][move.From]--
        final[side][move.To]++
        destinations[move.To] = true
        nonbar = nonbar || move.From != 25
        bear = bear || move.To == 0
    }
    for to := range destinations {
        if to > 0 && pos[1 - side][25 - to] == 1 {
            final[1 - side][25 - to] = 0
            final[1 - side][25]++
        }
    }
    for p := 1; p <= 25; p++ {
        if final[side][p] < 0 {
            return Play{}, "no checker"
        }
    }
    if final[side][25] > 0 && nonbar {
        return Play{}, "bar"
    }
    for to := range destinations {
        if to > 0 && pos[1 - side][25 - to] >= 2 {
            return Play{}, "blocked"
        }
    }
    if bear {
        if final[side][25] > 0 {
            return Play{}, "bear-off"
        }
        for p := 7; p <= 24; p++ {
            if final[side][p] > 0 {
                return Play{}, "bear-off"
            }
        }
    }
    for _, play := range legal {
        if play.Position == final {
            return play, ""
        }
    }
    matched, short := false, false
    for _, play := range possible {
        if play.Position == final {
            matched = true
            short = short || len(play.Moves) < maximum
        }
    }
    if short {
        return Play{}, "too few dice"
    }
    if matched {
        return Play{}, "larger die required"
    }
    return Play{}, "impossible"
}

func simulation(s State, rng *Random, strategies [2]string, opening bool, target int, score [2]int, crawford, verbose bool) Result {
    firstDice := [2]int{}
    if opening {
        for {
            firstDice = [2]int{rng.die(), rng.die()}
            if firstDice[0] != firstDice[1] {
                break
            }
        }
        s.Side = 0
        if firstDice[1] > firstDice[0] {
            s.Side = 1
        }
    }
    start, turns := s.Side, 0
    for t := 1;; t++ {
        side, other := s.Side, 1 - s.Side
        d1, d2 := 0, 0
        if opening && t == 1 {
            d1, d2 = firstDice[0], firstDice[1]
        } else {
            prohibited := target > 0 && (crawford || score[side] + s.Cube >= target)
            decision := cubeDecision(s, prohibited)
            if decision == "double take" || decision == "double drop" {
                if verbose {
                    emit(fmt.Sprintf("%d %s doubles %d", t, color(side), s.Cube * 2))
                }
                if decision == "double drop" {
                    if verbose {
                        emit(fmt.Sprintf("%d %s drops", t, color(other)))
                    }
                    result := finish(&s, side, "drop")
                    result.Turns = turns
                    result.Start = start
                    return result
                }
                s.Cube *= 2
                s.Owner = other
                if verbose {
                    emit(fmt.Sprintf("%d %s takes", t, color(other)))
                }
            }
            d1, d2 = rng.die(), rng.die()
        }
        plays, _, _ := enumerate(s.Position, side, d1, d2)
        chosen := plays[0]
        switch strategies[side] {
        case "BEST":
            chosen, _ = best(plays, side)
        case "RANDOM":
            chosen = plays[int(rng.next() % int64(len(plays)))]
        }
        s.Position = chosen.Position
        turns++
        if verbose {
            emit(fmt.Sprintf("%d %s %d-%d %s", t, color(side), d1, d2, chosen.Notation))
        }
        if s.Position[side][0] == 15 {
            result := bearResult(&s, side)
            result.Turns = turns
            result.Start = start
            return result
        }
        s.Side = other
    }
}

func (e *Engine) board() {
    s := e.State
    format := func(values []string) string {
        line := ""
        for i, value := range values {
            if i == 6 {
                line += " |"
            }
            line += fmt.Sprintf("%3s", value)
        }
        return line
    }
    for half := 0; half < 2; half++ {
        points := []int{}
        for i := 0; i < 12; i++ {
            if half == 0 {
                points = append(points, 13 + i)
            } else {
                points = append(points, 12 - i)
            }
        }
        labels := []string{}
        for _, p := range points {
            labels = append(labels, strconv.Itoa(p))
        }
        if half == 0 {
            emit(format(labels))
        }
        for row := 1; row <= 5; row++ {
            level := row
            if half == 1 {
                level = 6 - row
            }
            fields := []string{}
            for _, p := range points {
                count, letter := s.Position[0][p], "W"
                if count == 0 {
                    count = s.Position[1][25 - p]
                    letter = "B"
                }
                value := "."
                if count >= level {
                    value = letter
                }
                if level == 5 && count > 5 {
                    value = strconv.Itoa(count)
                }
                fields = append(fields, value)
            }
            emit(format(fields))
        }
        if half == 0 {
            status := color(s.Side) + " to move"
            if s.Over {
                status = "game over"
            } else if s.Pending {
                status = color(s.Side) + " doubles"
            }
            emit(fmt.Sprintf("bar W%d B%d | off W%d B%d | cube %d %s | %s", s.Position[0][25], s.Position[1][25], s.Position[0][0], s.Position[1][0], s.Cube, owner(s), status))
        } else {
            emit(format(labels))
        }
    }
}

func (e *Engine) execute(words []string) {
    cmd, a := words[0], words[1:]
    noargs := " NEW SHOW BOARD PIPS RACE EVAL SHOTS CUBE DOUBLE TAKE DROP SCORE HISTORY "
    known := strings.Contains(noargs, " " + cmd + " ") || strings.Contains(" POS MOVES PLAY AUTO HINT RESIGN UNDO REDO GAME MATCH STATS ", " " + cmd + " ")
    if !known {
        emit("ERROR unknown command")
        return
    }
    valid := true
    rangeArg := func(at, low, high int) bool {
        return at < len(a) && number(a[at]) >= low && number(a[at]) <= high
    }
    if strings.Contains(noargs, " " + cmd + " ") {
        valid = len(a) == 0
    }
    switch cmd {
    case "POS":
        valid = len(a) == 4
    case "MOVES", "AUTO":
        valid = len(a) == 2 && rangeArg(0, 1, 6) && rangeArg(1, 1, 6)
    case "PLAY":
        valid = len(a) >= 3 && rangeArg(0, 1, 6) && rangeArg(1, 1, 6)
    case "HINT":
        valid = len(a) == 3 && rangeArg(0, 1, 6) && rangeArg(1, 1, 6) && rangeArg(2, 1, 1000)
    case "RESIGN":
        valid = len(a) == 1 && (a[0] == "single" || a[0] == "gammon" || a[0] == "backgammon")
    case "UNDO", "REDO":
        valid = len(a) == 1 && rangeArg(0, 1, 1000)
    case "GAME":
        valid = len(a) == 3 && rangeArg(0, 1, 2147483646)
        if valid {
            for _, strategy := range a[1:] {
                valid = valid && (strategy == "BEST" || strategy == "FIRST" || strategy == "RANDOM")
            }
        }
    case "MATCH":
        valid = len(a) == 2 && rangeArg(0, 1, 15) && rangeArg(1, 1, 2147483646)
    case "STATS":
        valid = len(a) == 2 && rangeArg(0, 1, 50) && rangeArg(1, 1, 2147483646)
    }
    if cmd == "POS" && valid {
        points := strings.Split(a[0], ",")
        valid = len(points) == 24 && rangeArg(1, 0, 15) && rangeArg(2, 0, 15) && (a[3] == "W" || a[3] == "B")
        s := initial()
        s.Position = Position{}
        s.Score = e.State.Score
        if valid {
            s.Position[0][25] = number(a[1])
            s.Position[1][25] = number(a[2])
            for i, text := range points {
                value := number(text)
                if value > 0 {
                    s.Position[0][i + 1] = value
                } else if value < 0 {
                    s.Position[1][24 - i] = -value
                }
            }
            for side := 0; side < 2; side++ {
                total := 0
                for p := 1; p <= 25; p++ {
                    total += s.Position[side][p]
                }
                s.Position[side][0] = 15 - total
                valid = valid && s.Position[side][0] >= 0 && s.Position[side][0] <= 14
            }
            if a[3] == "B" {
                s.Side = 1
            }
        }
        if valid {
            e.State = s
            e.History = nil
            e.Redo = nil
            emit("OK")
            return
        }
    }
    if !valid {
        if cmd == "POS" {
            emit("ERROR bad position")
        } else {
            emit("ERROR bad arguments")
        }
        return
    }
    after := " RACE MOVES PLAY AUTO HINT EVAL SHOTS CUBE DOUBLE TAKE DROP RESIGN GAME "
    pending := " PLAY AUTO CUBE DOUBLE RESIGN GAME "
    if e.State.Over && strings.Contains(after, " " + cmd + " ") {
        emit("ERROR game over")
        return
    }
    if e.State.Pending && strings.Contains(pending, " " + cmd + " ") {
        emit("ERROR double pending")
        return
    }
    s := &e.State
    switch cmd {
    case "NEW":
        score := s.Score
        e.State = initial()
        e.State.Score = score
        e.History = nil
        e.Redo = nil
        emit("OK")
    case "SHOW":
        points := []string{}
        for p := 1; p <= 24; p++ {
            points = append(points, strconv.Itoa(s.Position[0][p] - s.Position[1][25 - p]))
        }
        emit(fmt.Sprintf("POS %s %d %d %s", strings.Join(points, ","), s.Position[0][25], s.Position[1][25], color(s.Side)))
    case "BOARD":
        e.board()
    case "PIPS":
        emit(fmt.Sprintf("pips W %d B %d", pips(s.Position, 0), pips(s.Position, 1)))
    case "RACE":
        if contact(s.Position) {
            emit("contact")
        } else {
            emit(fmt.Sprintf("race W %d B %d", keith(s.Position, 0), keith(s.Position, 1)))
        }
    case "EVAL":
        v := evaluate(s.Position, s.Side)
        emit(fmt.Sprintf("eval %d pips %d blots %d home %d prime %d anchors %d bar %d", v.E, v.P, v.S, v.H, v.R, v.A, v.G))
    case "MOVES", "PLAY", "AUTO", "HINT":
        d1, d2 := number(a[0]), number(a[1])
        if cmd == "PLAY" {
            moves, ok := parsePlay(a[2:])
            if !ok {
                emit("ILLEGAL syntax")
                return
            }
            legal, possible, maximum := enumerate(s.Position, s.Side, d1, d2)
            play, reason := validatePlay(s.Position, s.Side, moves, legal, possible, maximum)
            if reason != "" {
                emit("ILLEGAL " + reason)
                return
            }
            emit("OK " + play.Notation)
            e.makePlay(play, d1, d2)
            return
        }
        legal, _, _ := enumerate(s.Position, s.Side, d1, d2)
        if cmd == "MOVES" {
            for _, play := range legal {
                emit(play.Notation)
            }
            emit(fmt.Sprintf("total %d", len(legal)))
        } else if cmd == "AUTO" {
            play, value := best(legal, s.Side)
            emit(fmt.Sprintf("OK %s eval %d", play.Notation, value))
            e.makePlay(play, d1, d2)
        } else {
            scores := make([]int, len(legal))
            for i, play := range legal {
                scores[i] = evaluate(play.Position, s.Side).E
            }
            order := make([]int, len(legal))
            for i := range order {
                order[i] = i
            }
            sort.SliceStable(order, func(i, j int) bool {
                return scores[order[i]] > scores[order[j]]
            })
            for _, i := range order[: min(number(a[2]), len(order))] {
                emit(fmt.Sprintf("%d %s", scores[i], legal[i].Notation))
            }
        }
    case "SHOTS":
        blots := []int{}
        for p := 24; p >= 1; p-- {
            if s.Position[s.Side][p] == 1 {
                blots = append(blots, p)
            }
        }
        counts := map[int]int{}
        total := 0
        rolls := []string{}
        for a := 6; a >= 1; a-- {
            for b := a; b >= 1; b-- {
                legal, _, _ := enumerate(s.Position, 1 - s.Side, a, b)
                hit := map[int]bool{}
                for _, play := range legal {
                    for _, p := range blots {
                        if play.Hits & (1 << (25 - p)) != 0 {
                            hit[p] = true
                        }
                    }
                }
                weight := 2
                if a == b {
                    weight = 1
                }
                if len(hit) > 0 {
                    total += weight
                    rolls = append(rolls, fmt.Sprintf("%d-%d", a, b))
                }
                for p := range hit {
                    counts[p] += weight
                }
            }
        }
        line := fmt.Sprintf("shots %d/36", total)
        if len(rolls) > 0 {
            line += " " + strings.Join(rolls, " ")
        }
        emit(line)
        for _, p := range blots {
            emit(fmt.Sprintf("blot %d %d/36", p, counts[p]))
        }
    case "CUBE":
        emit("cube " + cubeDecision(* s, false))
    case "DOUBLE":
        if s.Owner == 1 - s.Side || s.Cube == 64 {
            emit("ERROR cube unavailable")
        } else {
            s.Pending = true
            e.Redo = nil
            emit(fmt.Sprintf("OK double %d", s.Cube * 2))
        }
    case "TAKE":
        if !s.Pending {
            emit("ERROR no double")
        } else {
            s.Pending = false
            s.Cube *= 2
            s.Owner = 1 - s.Side
            e.Redo = nil
            emit(fmt.Sprintf("OK take %d %s", s.Cube, owner(* s)))
        }
    case "DROP":
        if !s.Pending {
            emit("ERROR no double")
        } else {
            result := finish(s, s.Side, "drop")
            e.Redo = nil
            emit("OK drop")
            emit(resultLine(result))
        }
    case "RESIGN":
        result := finish(s, 1 - s.Side, a[0])
        e.Redo = nil
        emit("OK resign")
        emit(resultLine(result))
    case "SCORE":
        emit(fmt.Sprintf("score W %d B %d", s.Score[0], s.Score[1]))
    case "HISTORY":
        emit(fmt.Sprintf("history %d", len(e.History)))
        for i, entry := range e.History {
            emit(fmt.Sprintf("%d %s", i + 1, entry.Record))
        }
    case "UNDO":
        n := number(a[0])
        index := len(e.History) - n
        if index < 0 {
            emit("ERROR cannot undo")
        } else {
            e.State = e.History[index].Before
            undone := append([]Entry{}, e.History[index:]...)
            e.Redo = append(undone, e.Redo...)
            e.History = e.History[: index]
            emit("OK")
        }
    case "REDO":
        n := number(a[0])
        if n > len(e.Redo) {
            emit("ERROR cannot redo")
        } else {
            e.State = e.Redo[n - 1].After
            e.History = append(e.History, e.Redo[: n]...)
            e.Redo = e.Redo[n:]
            emit("OK")
        }
    case "GAME":
        rng := Random{int64(number(a[0]))}
        result := simulation(* s, &rng, [2]string{a[1], a[2]}, false, 0, [2]int{}, false, true)
        emit(resultLine(result))
    case "MATCH":
        target := number(a[0])
        rng := Random{int64(number(a[1]))}
        score := [2]int{}
        used := false
        game := 0
        for score[0] < target && score[1] < target {
            game++
            crawford := !used && max(score[0], score[1]) == target - 1
            used = used || crawford
            result := simulation(initial(), &rng, [2]string{"BEST", "BEST"}, true, target, score, crawford, false)
            score[result.Winner] += result.Points
            label := ""
            if crawford {
                label = " crawford"
            }
            emit(fmt.Sprintf("game %d%s start %s turns %d result %s %s %d score %d-%d", game, label, color(result.Start), result.Turns, color(result.Winner), result.Kind, result.Points, score[0], score[1]))
        }
        winner := 0
        if score[1] >= target {
            winner = 1
        }
        emit(fmt.Sprintf("match %s %d-%d", color(winner), score[0], score[1]))
    case "STATS":
        rng := Random{int64(number(a[1]))}
        counts := map[string][2]int{}
        points := [2]int{}
        turns := 0
        for i := 0; i < number(a[0]); i++ {
            result := simulation(initial(), &rng, [2]string{"BEST", "BEST"}, true, 0, [2]int{}, false, false)
            c := counts[result.Kind]
            c[result.Winner]++
            counts[result.Kind] = c
            points[result.Winner] += result.Points
            turns += result.Turns
        }
        for _, kind := range []string{"single", "gammon", "backgammon", "drop"} {
            c := counts[kind]
            emit(fmt.Sprintf("%s W %d B %d", kind, c[0], c[1]))
        }
        emit(fmt.Sprintf("points W %d B %d", points[0], points[1]))
        emit(fmt.Sprintf("turns %d", turns))
    }
}

func main() {
    defer out.Flush()
    input := bufio.NewReader(os.Stdin)
    line, _ := input.ReadString('\n')
    n := number(strings.TrimSpace(line))
    engine := Engine{State: initial()}
    for i := 0; i < n; i++ {
        line, _ = input.ReadString('\n')
        engine.execute(strings.Fields(line))
        out.Flush()
    }
}
