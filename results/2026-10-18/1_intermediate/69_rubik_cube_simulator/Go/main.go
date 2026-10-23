package main

import (
    "bufio"
    "fmt"
    "io"
    "os"
    "sort"
    "strconv"
    "strings"
)

const faces = "URFDLB"
const colors = "WRGYOB"

type move struct {
    letter byte
    amount int
}
type permutation [54]int
type state [54]byte
type vector [3]int
type place struct {
    cubie, normal vector
}
type turn struct {
    axis, count int
    layers []int
}
type piece struct {
    id, orientation int
}
type group struct {
    names []string
    stickers [][]int
}
type saved struct {
    cube state
    history []move
}

var turns = map[byte]turn{
    'R': {0, 1, []int{1}}, 'L': {0, 3, []int{-1}}, 'M': {0, 3, []int{0}},
    'r': {0, 1, []int{0, 1}}, 'l': {0, 3, []int{-1, 0}}, 'x': {0, 1, []int{-1, 0, 1}},
    'U': {1, 1, []int{1}}, 'D': {1, 3, []int{-1}}, 'E': {1, 3, []int{0}},
    'u': {1, 1, []int{0, 1}}, 'd': {1, 3, []int{-1, 0}}, 'y': {1, 1, []int{-1, 0, 1}},
    'F': {2, 1, []int{1}}, 'B': {2, 3, []int{-1}}, 'S': {2, 1, []int{0}},
    'f': {2, 1, []int{0, 1}}, 'b': {2, 3, []int{-1, 0}}, 'z': {2, 1, []int{-1, 0, 1}},
}
var tables map[move]permutation
var byEffect map[permutation]move
var rotations [][]move
var rotationEffects []permutation
var solved state
var corners, edges, centers group

func identity() permutation {
    var p permutation
    for i := range p {
        p[i] = i
    }
    return p
}
func compose(a, b permutation) permutation {
    var p permutation
    for i := range p {
        p[i] = a[b[i]]
    }
    return p
}
func inversePermutation(p permutation) permutation {
    var result permutation
    for i, source := range p {
        result[source] = i
    }
    return result
}
func applyPermutation(cube state, p permutation) state {
    var result state
    for i := range result {
        result[i] = cube[p[i]]
    }
    return result
}
func apply(cube state, seq []move) state {
    for _, m := range seq {
        cube = applyPermutation(cube, tables[m])
    }
    return cube
}
func effect(seq []move) permutation {
    p := identity()
    for _, m := range seq {
        p = compose(p, tables[m])
    }
    return p
}
func inverse(seq []move) []move {
    result := make([]move, len(seq))
    for i, m := range seq {
        result[len(seq) - 1 - i] = move{m.letter, 4 - m.amount}
    }
    return result
}
func copyMoves(seq []move) []move {
    return append([]move{}, seq...)
}
func quarter(v vector, axis int) vector {
    a, b := (axis + 1) % 3, (axis + 2) % 3
    v[a], v[b] = v[b], -v[a]
    return v
}
func literalMoves(text string) []move {
    result := []move{}
    for _, word := range strings.Fields(text) {
        amount := 1
        if len(word) > 1 {
            if word[1] == '2' {
                amount = 2
            } else {
                amount = 3
            }
        }
        result = append(result, move{word[0], amount})
    }
    return result
}
func makeGroup(names, layout string) group {
    g := group{names:strings.Fields(names)}
    for _, row := range strings.Split(layout, ";") {
        positions := []int{}
        for _, word := range strings.Fields(row) {
            positions = append(positions, strings.IndexByte(faces, word[0]) * 9 + int(word[1] - '1'))
        }
        g.stickers = append(g.stickers, positions)
    }
    return g
}
func initialize() {
    frames := [6][3]vector{
        {{0, 1, 0}, {1, 0, 0}, {0, 0, 1}},
        {{1, 0, 0}, {0, 0, -1}, {0, -1, 0}},
        {{0, 0, 1}, {1, 0, 0}, {0, -1, 0}},
        {{0, -1, 0}, {1, 0, 0}, {0, 0, -1}},
        {{-1, 0, 0}, {0, 0, 1}, {0, -1, 0}},
        {{0, 0, -1}, {-1, 0, 0}, {0, -1, 0}},
    }
    places := []place{}
    numbers := map[place]int{}
    for _, frame := range frames {
        for row := -1; row <= 1; row++ {
            for column := -1; column <= 1; column++ {
                cubie := frame[0]
                for axis := 0; axis < 3; axis++ {
                    cubie[axis] += column * frame[1][axis] + row * frame[2][axis]
                }
                p := place{cubie, frame[0]}
                numbers[p] = len(places)
                places = append(places, p)
            }
        }
    }
    tables, byEffect = map[move]permutation{}, map[permutation]move{}
    for letter, t := range turns {
        p := identity()
        for source, original := range places {
            selected := false
            for _, layer := range t.layers {
                if original.cubie[t.axis] == layer {
                    selected = true
                }
            }
            if selected {
                destination := original
                for i := 0; i < t.count; i++ {
                    destination.cubie = quarter(destination.cubie, t.axis)
                    destination.normal = quarter(destination.normal, t.axis)
                }
                p[numbers[destination]] = source
            }
        }
        current := identity()
        for amount := 1; amount <= 3; amount++ {
            current = compose(current, p)
            m := move{letter, amount}
            tables[m], byEffect[current] = current, m
        }
    }
    for _, first := range []string{"", "x", "x2", "x'", "z", "z'"} {
        for _, second := range []string{"", "y", "y2", "y'"} {
            seq := literalMoves(first + " " + second)
            rotations = append(rotations, seq)
            rotationEffects = append(rotationEffects, effect(seq))
        }
    }
    for i := range solved {
        solved[i] = colors[i / 9]
    }
    corners = makeGroup("URF UFL ULB UBR DFR DLF DBL DRB", "U9 R1 F3;U7 F1 L3;U1 L1 B3;U3 B1 R3;D3 F9 R7;D1 L9 F7;D7 B9 L7;D9 R9 B7")
    edges = makeGroup("UR UF UL UB DR DF DL DB FR FL BL BR", "U6 R2;U8 F2;U4 L2;U2 B2;D6 R8;D2 F8;D4 L8;D8 B8;F6 R4;F4 L6;B6 L4;B4 R6")
    centers = makeGroup("U R F D L B", "U5;R5;F5;D5;L5;B5")
}
func moveText(m move) string {
    suffix := ""
    if m.amount == 2 {
        suffix = "2"
    } else if m.amount == 3 {
        suffix = "'"
    }
    return string(m.letter) + suffix
}
func movesText(seq []move) string {
    words := make([]string, len(seq))
    for i, m := range seq {
        words[i] = moveText(m)
    }
    return strings.Join(words, " ")
}
func sequenceText(seq []move) string {
    if len(seq) == 0 {
        return "0"
    }
    return strconv.Itoa(len(seq)) + " " + movesText(seq)
}
func normalize(cube state) (state, int, bool) {
    for i, p := range rotationEffects {
        candidate := applyPermutation(cube, p)
        good := true
        for face := 0; face < 6; face++ {
            if candidate[9 * face + 4] != colors[face] {
                good = false
                break
            }
        }
        if good {
            return candidate, i, true
        }
    }
    return cube, 0, false
}
func identify(cube state, g group) []piece {
    result := make([]piece, len(g.names))
    for position, stickers := range g.stickers {
        result[position] = piece{-1, 0}
        found := false
        for id, name := range g.names {
            for orientation := 0; orientation < len(stickers); orientation++ {
                same := true
                for i := range stickers {
                    color := colors[strings.IndexByte(faces, name[i])]
                    if cube[stickers[(orientation + i) % len(stickers)]] != color {
                        same = false
                        break
                    }
                }
                if same {
                    result[position] = piece{id, orientation}
                    found = true
                    break
                }
            }
            if found {
                break
            }
        }
    }
    return result
}
func cycles(cube state, g group) string {
    identified := identify(cube, g)
    where, orientation := make([]int, len(g.names)), make([]int, len(g.names))
    for position, p := range identified {
        where[p.id], orientation[p.id] = position, p.orientation
    }
    seen := make([]bool, len(g.names))
    written := []string{}
    for first := range g.names {
        if seen[first] {
            continue
        }
        names, sum, at := []string{}, 0, first
        for !seen[at] {
            seen[at] = true
            names = append(names, g.names[at])
            sum += orientation[at]
            at = where[at]
        }
        mark := ""
        if width := len(g.stickers[0]); width > 1 {
            mark = []string{"", "+", "-"}[sum % width]
        }
        if len(names) > 1 || mark != "" {
            written = append(written, "(" + strings.Join(names, " ") + ")" + mark)
        }
    }
    if len(written) == 0 {
        return "none"
    }
    return strings.Join(written, " ")
}
func parity(pieces []piece) int {
    result := 0
    for i, a := range pieces {
        for _, b := range pieces[i + 1:] {
            if a.id > b.id {
                result ^= 1
            }
        }
    }
    return result
}
func check(word string) string {
    if len(word) != 54 {
        return fmt.Sprintf("length %d", len(word))
    }
    counts := [6]int{}
    for i := range word {
        at := strings.IndexByte(colors, word[i])
        if at < 0 {
            return fmt.Sprintf("char %d", i + 1)
        }
        counts[at]++
    }
    for i, count := range counts {
        if count != 9 {
            return fmt.Sprintf("count %c %d", colors[i], count)
        }
    }
    var cube state
    copy(cube[:], word)
    normalized, _, ok := normalize(cube)
    if !ok {
        return "centers"
    }
    c, e := identify(cube, corners), identify(cube, edges)
    for i, p := range c {
        if p.id < 0 {
            return "corner " + corners.names[i]
        }
    }
    for i, p := range e {
        if p.id < 0 {
            return "edge " + edges.names[i]
        }
    }
    for _, pair := range []struct{
        g group
        pieces []piece
    }{{corners, c}, {edges, e}} {
        for id, name := range pair.g.names {
            found := false
            for _, p := range pair.pieces {
                if p.id == id {
                    found = true
                    break
                }
            }
            if !found {
                return "missing " + name
            }
        }
    }
    c, e = identify(normalized, corners), identify(normalized, edges)
    twist, flip := 0, 0
    for _, p := range c {
        twist += p.orientation
    }
    for _, p := range e {
        flip += p.orientation
    }
    if twist % 3 != 0 {
        return "twist"
    }
    if flip % 2 != 0 {
        return "flip"
    }
    if parity(c) != parity(e) {
        return "parity"
    }
    return ""
}
func misplaced(cube state) int {
    count := 0
    for i, color := range cube {
        if color != cube[i / 9 * 9 + 4] {
            count++
        }
    }
    return count
}
func sameMoves(a, b []move) bool {
    if len(a) != len(b) {
        return false
    }
    for i := range a {
        if a[i] != b[i] {
            return false
        }
    }
    return true
}
func simplify(seq []move) []move {
    for {
        result := []move{}
        for start := 0; start < len(seq); {
            end := start + 1
            for end < len(seq) && turns[seq[end].letter].axis == turns[seq[start].letter].axis {
                end++
            }
            order := []byte{}
            amounts := map[byte]int{}
            for _, m := range seq[start:end] {
                if _, exists := amounts[m.letter]; !exists {
                    order = append(order, m.letter)
                }
                amounts[m.letter] += m.amount
            }
            for _, letter := range order {
                if amount := amounts[letter] % 4; amount != 0 {
                    result = append(result, move{letter, amount})
                }
            }
            start = end
        }
        if sameMoves(seq, result) {
            return result
        }
        seq = result
    }
}
func gcd(a, b int64) int64 {
    for b != 0 {
        a, b = b, a % b
    }
    return a
}
func order(p permutation) int64 {
    seen := [54]bool{}
    result := int64(1)
    for first := range p {
        if seen[first] {
            continue
        }
        length, at := int64(0), first
        for !seen[at] {
            seen[at] = true
            length++
            at = p[at]
        }
        result = result / gcd(result, length) * length
    }
    return result
}
func conjugate(rotation permutation, m move) move {
    return byEffect[compose(compose(rotation, tables[m]), inversePermutation(rotation))]
}
func unrotate(seq []move) []move {
    replacements := map[byte][]move{
        'M': literalMoves("R L' x'"), 'E': literalMoves("U D' y'"), 'S': literalMoves("F' B z"),
        'r': literalMoves("L x"), 'l': literalMoves("R x'"), 'u': literalMoves("D y"),
        'd': literalMoves("U y'"), 'f': literalMoves("B z"), 'b': literalMoves("F z'"),
    }
    result, rotation := []move{}, identity()
    for _, m := range seq {
        expanded, exists := replacements[m.letter]
        if exists {
            expanded = copyMoves(expanded)
            for i := range expanded {
                expanded[i].amount = expanded[i].amount * m.amount % 4
            }
        } else {
            expanded = []move{m}
        }
        for _, part := range expanded {
            if strings.ContainsRune("xyz", rune(part.letter)) {
                rotation = compose(rotation, tables[part])
            } else {
                result = append(result, conjugate(rotation, part))
            }
        }
    }
    for i, p := range rotationEffects {
        if p == rotation {
            return append(result, rotations[i]...)
        }
    }
    return result
}
func search(cube state, depth int, previous byte) ([]move, bool) {
    if depth == 0 {
        return []move{}, misplaced(cube) == 0
    }
    for i := range faces {
        face := faces[i]
        if face == previous || previous == 'D' && face == 'U' || previous == 'L' && face == 'R' || previous == 'B' && face == 'F' {
            continue
        }
        for amount := 1; amount <= 3; amount++ {
            m := move{face, amount}
            if rest, found := search(applyPermutation(cube, tables[m]), depth - 1, face); found {
                return append([]move{m}, rest...), true
            }
        }
    }
    return nil, false
}

type parser struct {
    line string
    pos int
    macros map[string][]move
}
func (p *parser) peek() byte {
    if p.pos < len(p.line) {
        return p.line[p.pos]
    }
    return 0
}
func (p *parser) skip() {
    for p.peek() == ' ' {
        p.pos++
    }
}
func (p *parser) syntax() error {
    position := p.pos + 1
    if position > len(p.line) + 1 {
        position = len(p.line) + 1
    }
    return fmt.Errorf("syntax at %d", position)
}
func (p *parser) power(seq []move) []move {
    count := 1
    if p.peek() >= '1' && p.peek() <= '9' {
        count = int(p.peek() - '0')
        p.pos++
        if p.peek() >= '0' && p.peek() <= '9' {
            count = count * 10 + int(p.peek() - '0')
            p.pos++
        }
    }
    invert := p.peek() == '\''
    if invert {
        p.pos++
    }
    result := []move{}
    for i := 0; i < count; i++ {
        result = append(result, seq...)
    }
    if invert {
        return inverse(result)
    }
    return result
}
func (p *parser) sequence() ([]move, error) {
    result := []move{}
    for {
        p.skip()
        c := p.peek()
        var part []move
        if _, exists := turns[c]; exists {
            p.pos++
            amount := 1
            if p.peek() == '2' {
                amount = 2
                p.pos++
            } else if p.peek() == '\'' {
                amount = 3
                p.pos++
            }
            part = []move{{c, amount}}
        } else if c == '(' {
            p.pos++
            nested, err := p.sequence()
            if err != nil {
                return nil, err
            }
            p.skip()
            if p.peek() != ')' {
                return nil, p.syntax()
            }
            p.pos++
            part = p.power(nested)
        } else if c == '[' {
            p.pos++
            a, err := p.sequence()
            if err != nil {
                return nil, err
            }
            p.skip()
            separator := p.peek()
            if separator != ',' && separator != ':' {
                return nil, p.syntax()
            }
            p.pos++
            b, err := p.sequence()
            if err != nil {
                return nil, err
            }
            p.skip()
            if p.peek() != ']' {
                return nil, p.syntax()
            }
            p.pos++
            nested := append(copyMoves(a), b...)
            nested = append(nested, inverse(a)...)
            if separator == ',' {
                nested = append(nested, inverse(b)...)
            }
            part = p.power(nested)
        } else if c == '{' {
            p.pos++
            start := p.pos
            for p.peek() >= 'a' && p.peek() <= 'z' {
                p.pos++
            }
            name := p.line[start:p.pos]
            if name == "" || p.peek() != '}' {
                return nil, p.syntax()
            }
            nested, exists := p.macros[name]
            if !exists {
                return nil, fmt.Errorf("undefined %s", name)
            }
            p.pos++
            part = p.power(nested)
        } else {
            return result, nil
        }
        result = append(result, part...)
    }
}
func (p *parser) whole() ([]move, error) {
    result, err := p.sequence()
    if err != nil {
        return nil, err
    }
    p.skip()
    if p.peek() != 0 {
        return nil, p.syntax()
    }
    if len(result) > 500 {
        return nil, fmt.Errorf("too long")
    }
    return result, nil
}
func nameWord(word string) bool {
    if len(word) == 0 || len(word) > 8 {
        return false
    }
    for i := range word {
        if word[i] < 'a' || word[i] > 'z' {
            return false
        }
    }
    return true
}
func numberWord(word string) bool {
    if len(word) == 0 || len(word) > 10 || len(word) > 1 && word[0] == '0' {
        return false
    }
    for i := range word {
        if word[i] < '0' || word[i] > '9' {
            return false
        }
    }
    return true
}
func numeric(word string) int64 {
    n, _ := strconv.ParseInt(word, 10, 64)
    return n
}
func contains(words []string, word string) bool {
    for _, s := range words {
        if s == word {
            return true
        }
    }
    return false
}

type simulator struct {
    cube state
    history, redo []move
    macros map[string][]move
    saves map[string]saved
    out *bufio.Writer
}
func (s *simulator) record(seq []move) {
    s.cube = apply(s.cube, seq)
    s.history = append(s.history, seq...)
    s.redo = nil
}
func (s *simulator) command(line string) error {
    command, arguments, hasArguments := strings.Cut(line, " ")
    noArguments := contains([]string{"RESET", "SHOW", "STATE", "ISSOLVED", "HISTORY", "SOLUTION", "ANALYZE", "STAGE", "MACROS"}, command)
    wordCounts := map[string]int{"CHECK":1, "LOAD":1, "UNDO":1, "REDO":1, "SEARCH":1, "WHERE":1, "SAVE":1, "RESTORE":1, "SCRAMBLE":2}
    count, wordCommand := wordCounts[command]
    sequenceCommand := contains([]string{"APPLY", "INVERT", "SIMPLIFY", "METRICS", "ORDER", "CYCLES", "UNROTATE", "UNTIL"}, command)
    headCommand := contains([]string{"DEFINE", "MIRROR", "ROTATE"}, command)
    if !noArguments && !wordCommand && !sequenceCommand && !headCommand {
        return fmt.Errorf("unknown command %s", command)
    }
    words, head := strings.Fields(arguments), ""
    seqStart := len(command) + 1
    badArguments := noArguments && hasArguments || wordCommand && len(words) != count || headCommand && !hasArguments
    if !badArguments && wordCommand {
        if contains([]string{"UNDO", "REDO", "SEARCH", "SCRAMBLE"}, command) {
            for _, word := range words {
                if !numberWord(word) {
                    badArguments = true
                }
            }
        }
        if (command == "SAVE" || command == "RESTORE") && !nameWord(words[0]) {
            badArguments = true
        }
    }
    if !badArguments && headCommand {
        head, _, _ = strings.Cut(arguments, " ")
        seqStart = len(command) + len(head) + 2
        switch command {
        case "DEFINE":
            badArguments = !nameWord(head)
        case "MIRROR":
            badArguments = !contains([]string{"LR", "UD", "FB"}, head)
        case "ROTATE":
            badArguments = !contains([]string{"x", "x2", "x'", "y", "y2", "y'", "z", "z2", "z'"}, head)
        }
    }
    if badArguments {
        return fmt.Errorf("bad arguments")
    }
    var seq []move
    if sequenceCommand || headCommand {
        p := parser{line:line, pos:seqStart, macros:s.macros}
        var err error
        seq, err = p.whole()
        if err != nil {
            return err
        }
    }
    if (command == "UNDO" || command == "REDO") && numeric(words[0]) < 1 || command == "SEARCH" && numeric(words[0]) > 4 || command == "SCRAMBLE" && (numeric(words[0]) < 1 || numeric(words[0]) > 50 || numeric(words[1]) < 1 || numeric(words[1]) > 2147483646) {
        return fmt.Errorf("bad value")
    }
    if command == "WHERE" && !contains(corners.names, words[0]) && !contains(edges.names, words[0]) {
        return fmt.Errorf("unknown piece %s", words[0])
    }
    switch command {
    case "RESET":
        s.cube, s.history, s.redo = solved, nil, nil
        fmt.Fprintln(s.out, "reset")
    case "SHOW":
        for row := 0; row < 9; row++ {
            indices, prefix := []int{}, ""
            if row < 3 || row >= 6 {
                face, r := 0, row
                if row >= 6 {
                    face, r = 3, row - 6
                }
                prefix = "      "
                for column := 0; column < 3; column++ {
                    indices = append(indices, face * 9 + r * 3 + column)
                }
            } else {
                for _, face := range []int{4, 2, 1, 5} {
                    for column := 0; column < 3; column++ {
                        indices = append(indices, face * 9 + (row - 3) * 3 + column)
                    }
                }
            }
            cells := []string{}
            for _, index := range indices {
                cells = append(cells, string(s.cube[index]))
            }
            fmt.Fprintln(s.out, prefix + strings.Join(cells, " "))
        }
    case "STATE":
        fmt.Fprintln(s.out, "state " + string(s.cube[:]))
    case "ISSOLVED":
        if n := misplaced(s.cube); n == 0 {
            fmt.Fprintln(s.out, "solved")
        } else {
            fmt.Fprintf(s.out, "unsolved %d\n", n)
        }
    case "HISTORY":
        fmt.Fprintln(s.out, "history " + sequenceText(s.history))
    case "SOLUTION":
        fmt.Fprintln(s.out, "solution " + sequenceText(simplify(inverse(s.history))))
    case "ANALYZE", "STAGE", "WHERE":
        cube, rotation, _ := normalize(s.cube)
        if command == "ANALYZE" {
            text := movesText(rotations[rotation])
            if text == "" {
                text = "none"
            }
            fmt.Fprintln(s.out, "rotation " + text)
            fmt.Fprintln(s.out, "corners " + cycles(cube, corners))
            fmt.Fprintln(s.out, "edges " + cycles(cube, edges))
        } else if command == "WHERE" {
            g, orientation := edges, "flip"
            if contains(corners.names, words[0]) {
                g, orientation = corners, "twist"
            }
            for position, p := range identify(cube, g) {
                if g.names[p.id] == words[0] {
                    fmt.Fprintf(s.out, "%s at %s %s %d\n", words[0], g.names[position], orientation, p.orientation)
                    break
                }
            }
        } else {
            c, e := identify(cube, corners), identify(cube, edges)
            cross, slots, top := 0, 0, 0
            for i := 4; i < 8; i++ {
                if e[i].id == i && e[i].orientation == 0 {
                    cross++
                }
                if c[i].id == i && c[i].orientation == 0 && e[i + 4].id == i + 4 && e[i + 4].orientation == 0 {
                    slots++
                }
            }
            for _, color := range cube[:9] {
                if color == 'W' {
                    top++
                }
            }
            stage := "none"
            if misplaced(cube) == 0 {
                stage = "solved"
            } else if cross == 4 && slots == 4 && top == 9 {
                stage = "oll"
            } else if cross == 4 && slots == 4 {
                stage = "f2l"
            } else if cross == 4 {
                stage = "cross"
            }
            fmt.Fprintf(s.out, "stage %s cross %d slots %d top %d\n", stage, cross, slots, top)
        }
    case "MACROS":
        names := []string{}
        for name := range s.macros {
            names = append(names, name)
        }
        sort.Strings(names)
        fmt.Fprintf(s.out, "macros %d\n", len(names))
        for _, name := range names {
            fmt.Fprintf(s.out, "macro %s %s\n", name, sequenceText(s.macros[name]))
        }
    case "CHECK", "LOAD":
        invalid := check(words[0])
        if command == "CHECK" {
            if invalid == "" {
                fmt.Fprintln(s.out, "valid")
            } else {
                fmt.Fprintln(s.out, "invalid " + invalid)
            }
        } else {
            if invalid != "" {
                return fmt.Errorf("invalid %s", invalid)
            }
            copy(s.cube[:], words[0])
            s.history, s.redo = nil, nil
            fmt.Fprintln(s.out, "loaded")
        }
    case "UNDO", "REDO":
        source := &s.history
        message := "undo"
        if command == "REDO" {
            source, message = &s.redo, "redo"
        }
        if len(*source) == 0 {
            return fmt.Errorf("nothing to %s", message)
        }
        count := numeric(words[0])
        if count > int64(len(*source)) {
            count = int64(len(*source))
        }
        for i := int64(0); i < count; i++ {
            m := (*source)[len(*source) - 1]
            *source = (*source)[:len(*source) - 1]
            if command == "UNDO" {
                s.cube = applyPermutation(s.cube, tables[move{m.letter, 4 - m.amount}])
                s.redo = append(s.redo, m)
            } else {
                s.cube = applyPermutation(s.cube, tables[m])
                s.history = append(s.history, m)
            }
        }
        if command == "UNDO" {
            fmt.Fprintf(s.out, "undone %d\n", count)
        } else {
            fmt.Fprintf(s.out, "redone %d\n", count)
        }
    case "SEARCH":
        for depth := 0; depth <= int(numeric(words[0])); depth++ {
            if found, ok := search(s.cube, depth, 0); ok {
                fmt.Fprintln(s.out, "found " + sequenceText(found))
                return nil
            }
        }
        fmt.Fprintln(s.out, "not found")
    case "SAVE":
        s.saves[words[0]] = saved{s.cube, copyMoves(s.history)}
        fmt.Fprintln(s.out, "saved " + words[0])
    case "RESTORE":
        save, exists := s.saves[words[0]]
        if !exists {
            return fmt.Errorf("no save %s", words[0])
        }
        s.cube, s.history, s.redo = save.cube, copyMoves(save.history), nil
        fmt.Fprintln(s.out, "restored " + words[0])
    case "SCRAMBLE":
        scramble, seed := []move{}, numeric(words[1])
        for i := 0; i < int(numeric(words[0])); i++ {
            usable := []byte{}
            for j := range faces {
                face := faces[j]
                if i > 0 && face == scramble[i - 1].letter {
                    continue
                }
                if i > 1 && turns[scramble[i - 1].letter].axis == turns[scramble[i - 2].letter].axis && turns[face].axis == turns[scramble[i - 1].letter].axis {
                    continue
                }
                usable = append(usable, face)
            }
            seed = 48271 * seed % 2147483647
            face := usable[seed % int64(len(usable))]
            seed = 48271 * seed % 2147483647
            scramble = append(scramble, move{face, []int{1, 3, 2}[seed % 3]})
        }
        s.record(scramble)
        fmt.Fprintln(s.out, "scramble " + movesText(scramble))
    case "APPLY":
        s.record(seq)
        fmt.Fprintf(s.out, "applied %d\n", len(seq))
    case "INVERT":
        fmt.Fprintln(s.out, "inverse " + sequenceText(inverse(seq)))
    case "SIMPLIFY":
        fmt.Fprintln(s.out, "simplified " + sequenceText(simplify(seq)))
    case "METRICS":
        htm, qtm, stm := 0, 0, 0
        for _, m := range seq {
            if strings.ContainsRune("xyz", rune(m.letter)) {
                continue
            }
            h, q := 1, 1
            if strings.ContainsRune("MES", rune(m.letter)) {
                h = 2
            }
            if m.amount == 2 {
                q = 2
            }
            htm, qtm, stm = htm + h, qtm + h * q, stm + 1
        }
        fmt.Fprintf(s.out, "metrics htm %d qtm %d stm %d etm %d\n", htm, qtm, stm, len(seq))
    case "ORDER":
        fmt.Fprintf(s.out, "order %d\n", order(effect(seq)))
    case "CYCLES":
        cube := apply(solved, seq)
        fmt.Fprintln(s.out, "corners " + cycles(cube, corners))
        fmt.Fprintln(s.out, "edges " + cycles(cube, edges))
        fmt.Fprintln(s.out, "centers " + cycles(cube, centers))
    case "UNROTATE":
        fmt.Fprintln(s.out, "unrotated " + sequenceText(unrotate(seq)))
    case "UNTIL":
        p, cube := effect(seq), s.cube
        for k, limit := int64(1), order(p); k <= limit; k++ {
            cube = applyPermutation(cube, p)
            if misplaced(cube) == 0 {
                fmt.Fprintf(s.out, "until %d\n", k)
                return nil
            }
        }
        fmt.Fprintln(s.out, "until never")
    case "DEFINE":
        s.macros[head] = copyMoves(seq)
        fmt.Fprintf(s.out, "defined %s %d\n", head, len(seq))
    case "MIRROR":
        axis := map[string]int{"LR":0, "UD":1, "FB":2}[head]
        opposites := map[byte]byte{'R':'L', 'L':'R', 'U':'D', 'D':'U', 'F':'B', 'B':'F', 'r':'l', 'l':'r', 'u':'d', 'd':'u', 'f':'b', 'b':'f'}
        mirrored := copyMoves(seq)
        for i, m := range mirrored {
            if turns[m.letter].axis != axis {
                mirrored[i].amount = 4 - m.amount
            } else if opposite, exists := opposites[m.letter]; exists {
                mirrored[i] = move{opposite, 4 - m.amount}
            }
        }
        fmt.Fprintln(s.out, "mirror " + sequenceText(mirrored))
    case "ROTATE":
        rotation, rotated := effect(literalMoves(head)), copyMoves(seq)
        for i, m := range seq {
            rotated[i] = conjugate(rotation, m)
        }
        fmt.Fprintln(s.out, "rotated " + sequenceText(rotated))
    }
    return nil
}
func main() {
    initialize()
    data, _ := io.ReadAll(os.Stdin)
    lines := strings.Split(string(data), "\n")
    count, _ := strconv.Atoi(lines[0])
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    s := simulator{cube:solved, macros:map[string][]move{}, saves:map[string]saved{}, out:out}
    for _, line := range lines[1:count + 1] {
        if err := s.command(line); err != nil {
            fmt.Fprintln(out, "error: " + err.Error())
        }
    }
}
