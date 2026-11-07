package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var letterPoints = [...]int{1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10}

func readLines(name string) []string {
	data, err := os.ReadFile("input/" + name)
	if err != nil {
		panic(err)
	}
	lines := strings.Split(string(data), "\n")
	return lines[:len(lines)-1]
}

func parseInt(text string) int {
	value, err := strconv.Atoi(text)
	if err != nil {
		panic(err)
	}
	return value
}
func ignored(line string) bool { return line == "" || strings.HasPrefix(line, "#") }
func joined(values []string, separator string) string {
	if len(values) == 0 {
		return "-"
	}
	return strings.Join(values, separator)
}

func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
		panic(err)
	}
}

func writeParagraphs(name string, paragraphs [][]string) {
	var lines []string
	for _, paragraph := range paragraphs {
		if len(lines) > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, paragraph...)
	}
	writeLines(name, lines)
}

type Settings struct {
	Budget, Minimum int
	Symmetry        string
	Relax, Weak     int
}

func readSettings(lines []string) Settings {
	values := make(map[string]string)
	for _, line := range lines {
		if !ignored(line) {
			key, value, _ := strings.Cut(line, " ")
			values[key] = value
		}
	}
	return Settings{parseInt(values["node_budget"]), parseInt(values["min_score"]), values["symmetry"], parseInt(values["relax_step"]), parseInt(values["weak_score"])}
}

type Issue struct {
	Line   int
	Reason string
}
type Duplicate struct {
	Line  int
	Word  string
	First int
}
type WordList struct {
	LineCount  int
	Index      *WordIndex
	Invalid    []Issue
	Duplicates []Duplicate
}

func newWordList(lines []string) *WordList {
	list := &WordList{LineCount: len(lines)}
	scores := make(map[string]int)
	firstLines := make(map[string]int)
	for number, line := range lines {
		if reason := wordLineError(line); reason != "" {
			list.Invalid = append(list.Invalid, Issue{number + 1, reason})
			continue
		}
		word, score, _ := strings.Cut(line, " ")
		if first, exists := firstLines[word]; exists {
			list.Duplicates = append(list.Duplicates, Duplicate{number + 1, word, first})
		} else {
			scores[word] = parseInt(score)
			firstLines[word] = number + 1
		}
	}
	list.Index = newWordIndex(scores)
	return list
}

func (list *WordList) Report() []string {
	index := list.Index
	lines := []string{fmt.Sprintf("WORDLIST lines=%d valid=%d invalid=%d duplicates=%d", list.LineCount, len(index.Words), len(list.Invalid), len(list.Duplicates))}
	for _, issue := range list.Invalid {
		lines = append(lines, fmt.Sprintf("invalid %d %s", issue.Line, issue.Reason))
	}
	for _, duplicate := range list.Duplicates {
		lines = append(lines, fmt.Sprintf("duplicate %d %s first=%d", duplicate.Line, duplicate.Word, duplicate.First))
	}
	for length := 3; length <= 15; length++ {
		words := index.ByLength[length]
		if len(words) == 0 {
			continue
		}
		total := 0
		for _, id := range words {
			total += index.Words[id].Score
		}
		best := index.Words[words[0]]
		lines = append(lines, fmt.Sprintf("length %d words=%d average=%s best=%s:%d", length, len(words), decimal(total, len(words), 2), best.Text, best.Score))
	}
	var bands, top []string
	for band := range 5 {
		low, high, count := band*20+1, (band+1)*20, 0
		for _, word := range index.Words {
			if word.Score >= low && word.Score <= high {
				count++
			}
		}
		bands = append(bands, fmt.Sprintf("%d-%d=%d", low, high, count))
	}
	for _, word := range index.Words[:min(5, len(index.Words))] {
		top = append(top, fmt.Sprintf("%s:%d", word.Text, word.Score))
	}
	type LetterCount struct {
		Letter byte
		Count  int
	}
	rare := make([]LetterCount, 26)
	for letter := range 26 {
		count := 0
		for _, word := range index.Words {
			if strings.ContainsRune(word.Text, rune('A'+letter)) {
				count++
			}
		}
		rare[letter] = LetterCount{byte('A' + letter), count}
	}
	sort.Slice(rare, func(i, j int) bool {
		if rare[i].Count == rare[j].Count {
			return rare[i].Letter < rare[j].Letter
		}
		return rare[i].Count < rare[j].Count
	})
	var rareText []string
	for _, entry := range rare[:5] {
		rareText = append(rareText, fmt.Sprintf("%c:%d", entry.Letter, entry.Count))
	}
	return append(lines, "bands "+strings.Join(bands, " "), "top "+strings.Join(top, " "), "rare_letters "+strings.Join(rareText, " "))
}

type Clue struct {
	Text string
	Uses int
}
type UnknownClue struct {
	Line int
	Word string
}
type ClueBook struct {
	Entries, Added int
	Invalid        []Issue
	Unknown        []UnknownClue
	Clues          [][]Clue
}

func newClueBook(lines []string, index *WordIndex) *ClueBook {
	book := &ClueBook{Clues: make([][]Clue, len(index.Words))}
	for number, line := range lines {
		if ignored(line) {
			continue
		}
		book.Entries++
		if reason := clueLineError(line); reason != "" {
			book.Invalid = append(book.Invalid, Issue{number + 1, reason})
			continue
		}
		word, text, _ := strings.Cut(line, "|")
		if id, exists := index.Lookup[word]; exists {
			book.Clues[id] = append(book.Clues[id], Clue{Text: text})
			book.Added++
		} else {
			book.Unknown = append(book.Unknown, UnknownClue{number + 1, word})
		}
	}
	return book
}

func (book *ClueBook) Choose(id int) string {
	clues := book.Clues[id]
	if len(clues) == 0 {
		return ""
	}
	chosen := 0
	for number, clue := range clues {
		if clue.Uses < clues[chosen].Uses {
			chosen = number
		}
	}
	book.Clues[id][chosen].Uses++
	return clues[chosen].Text
}

func (book *ClueBook) Report(index *WordIndex) []string {
	words, used, repeated := 0, 0, 0
	for _, clues := range book.Clues {
		if len(clues) > 0 {
			words++
		}
		for _, clue := range clues {
			if clue.Uses > 0 {
				used++
			}
			if clue.Uses >= 2 {
				repeated++
			}
		}
	}
	lines := []string{fmt.Sprintf("CLUES entries=%d valid=%d invalid=%d unknown=%d words=%d", book.Entries, book.Added, len(book.Invalid), len(book.Unknown), words)}
	for _, issue := range book.Invalid {
		lines = append(lines, fmt.Sprintf("clue_invalid %d %s", issue.Line, issue.Reason))
	}
	for _, issue := range book.Unknown {
		lines = append(lines, fmt.Sprintf("clue_unknown %d %s", issue.Line, issue.Word))
	}
	lines = append(lines, fmt.Sprintf("CLUE_USE used=%d unused=%d repeated=%d", used, book.Added-used, repeated))
	names := make([]string, 0, len(index.Lookup))
	for word := range index.Lookup {
		names = append(names, word)
	}
	sort.Strings(names)
	for _, word := range names {
		for number, clue := range book.Clues[index.Lookup[word]] {
			if clue.Uses >= 2 {
				lines = append(lines, fmt.Sprintf("repeated %s clue=%d uses=%d", word, number+1, clue.Uses))
			}
		}
	}
	return lines
}

type Block struct {
	Name          string
	Options, Rows []string
}

func splitBlocks(lines []string) []Block {
	var blocks []Block
	var current *Block
	for _, line := range lines {
		if current == nil {
			if strings.HasPrefix(line, "TEMPLATE ") {
				current = &Block{Name: strings.TrimPrefix(line, "TEMPLATE ")}
			}
		} else if line == "END" {
			blocks = append(blocks, *current)
			current = nil
		} else if strings.Contains(line, " ") {
			current.Options = append(current.Options, line)
		} else {
			current.Rows = append(current.Rows, line)
		}
	}
	return blocks
}

func validName(name string) bool {
	if len(name) < 1 || len(name) > 20 {
		return false
	}
	for i := range name {
		letter := name[i]
		if !(letter >= 'a' && letter <= 'z') && !(letter >= '0' && letter <= '9') && letter != '_' {
			return false
		}
	}
	return true
}

func validRow(row string, width int) bool {
	if len(row) < 3 || len(row) > 15 || len(row) != width {
		return false
	}
	for i := range row {
		if row[i] != '.' && row[i] != '#' && (row[i] < 'A' || row[i] > 'Z') {
			return false
		}
	}
	return true
}

type Prepared struct {
	Settings   Settings
	Layout     *Layout
	Initial    GridState
	ThemeSlots []bool
}

func prepare(block Block, defaults Settings, names map[string]bool, index *WordIndex) (*Prepared, string) {
	if !validName(block.Name) {
		return nil, "bad name"
	}
	if names[block.Name] {
		return nil, "duplicate name"
	}
	settings := defaults
	seen := make(map[string]bool)
	var themes []string
	themeNames := make(map[string]bool)
	for number, line := range block.Options {
		key, value, _ := strings.Cut(line, " ")
		valid := false
		if key == "theme" {
			if validWord(value) && !themeNames[value] {
				themes = append(themes, value)
				themeNames[value] = true
				valid = true
			}
		} else if !seen[key] {
			switch key {
			case "node_budget":
				if validInteger(value, 1, 100000) {
					settings.Budget = parseInt(value)
					valid = true
				}
			case "min_score":
				if validInteger(value, 1, 100) {
					settings.Minimum = parseInt(value)
					valid = true
				}
			case "symmetry":
				if value == "rot180" || value == "mirror" || value == "none" {
					settings.Symmetry = value
					valid = true
				}
			}
		}
		if !valid {
			return nil, fmt.Sprintf("bad option %d", number+1)
		}
		seen[key] = true
	}
	if len(block.Rows) < 3 || len(block.Rows) > 15 {
		return nil, "bad height"
	}
	width := len(block.Rows[0])
	for number, row := range block.Rows {
		if !validRow(row, width) {
			return nil, fmt.Sprintf("bad row %d", number+1)
		}
	}
	grid := newGrid(block.Rows)
	if settings.Symmetry != "none" {
		if cell := grid.AsymmetricCell(settings.Symmetry); cell >= 0 {
			return nil, "asymmetric at " + grid.Location(cell)
		}
	}
	if components := grid.ComponentCount(); components != 1 {
		return nil, fmt.Sprintf("disconnected components=%d", components)
	}
	if reason := shortRunError(grid); reason != "" {
		return nil, reason
	}
	layout := newLayout(grid)
	if cell := layout.OrphanCell(); cell >= 0 {
		return nil, "orphan cell " + grid.Location(cell)
	}
	initial := newGridState(grid.Cells, len(layout.Slots), len(index.Words))
	themeSlots := make([]bool, len(layout.Slots))
	for number, theme := range themes {
		id, exists := index.Lookup[theme]
		if !exists {
			return nil, fmt.Sprintf("unknown theme %d", number+1)
		}
		chosen := -1
		for _, slot := range layout.Slots {
			if initial.Words[slot.Index] < 0 && slot.Length() == len(theme) && matches(index.Words[id].Letters, initial.Pattern(slot)) {
				chosen = slot.Index
				break
			}
		}
		if chosen < 0 {
			return nil, fmt.Sprintf("theme %d does not fit", number+1)
		}
		initial.Assign(layout.Slots[chosen], id, index)
		themeSlots[chosen] = true
	}
	return &Prepared{settings, layout, initial, themeSlots}, ""
}

type Completed struct {
	Prepared *Prepared
	Attempts []*Attempt
	State    GridState
	Chosen   []string
}

func newCompleted(prepared *Prepared, index *WordIndex, clues *ClueBook) *Completed {
	result := &Completed{Prepared: prepared, Chosen: make([]string, len(prepared.Layout.Slots))}
	minimum := prepared.Settings.Minimum
	for {
		attempt := newAttempt(prepared.Layout, index, prepared.Initial, minimum, prepared.Settings.Budget)
		attempt.Run()
		result.Attempts = append(result.Attempts, attempt)
		if attempt.Outcome == "filled" || prepared.Settings.Relax < 1 || minimum <= 1 {
			break
		}
		minimum = max(minimum-prepared.Settings.Relax, 1)
	}
	result.State = result.FinalAttempt().FinalState().Copy()
	for _, across := range []bool{true, false} {
		for _, slot := range prepared.Layout.Slots {
			if slot.Across == across && result.State.Words[slot.Index] >= 0 {
				result.Chosen[slot.Index] = clues.Choose(result.State.Words[slot.Index])
			}
		}
	}
	return result
}

func (c *Completed) FinalAttempt() *Attempt { return c.Attempts[len(c.Attempts)-1] }
func (c *Completed) Filled() bool           { return c.FinalAttempt().Outcome == "filled" }
func (c *Completed) TotalScore(index *WordIndex) int {
	total := 0
	for _, id := range c.State.Words {
		if id >= 0 {
			total += index.Words[id].Score
		}
	}
	return total
}
func (c *Completed) Entry(slot Slot, index *WordIndex) string {
	word := index.Words[c.State.Words[slot.Index]]
	return fmt.Sprintf("%s:%s:%d", slot.Label, word.Text, word.Score)
}

func (c *Completed) ClueParagraph(name string, index *WordIndex) []string {
	lines := []string{"TEMPLATE " + name}
	clued, missing, unfilled := 0, 0, 0
	for _, across := range []bool{true, false} {
		var group []Slot
		for _, slot := range c.Prepared.Layout.Slots {
			if slot.Across == across {
				group = append(group, slot)
			}
		}
		if len(group) > 0 {
			heading := "DOWN"
			if across {
				heading = "ACROSS"
			}
			lines = append(lines, heading)
		}
		for _, slot := range group {
			id := c.State.Words[slot.Index]
			if id < 0 {
				unfilled++
				lines = append(lines, listLine(slot, "(unfilled)", string(c.State.Pattern(slot)), "-", false))
				continue
			}
			clue := c.Chosen[slot.Index]
			if clue == "" {
				missing++
				clue = "(no clue)"
			} else {
				clued++
			}
			lines = append(lines, listLine(slot, clue, index.Words[id].Text, strconv.Itoa(index.Words[id].Score), c.Prepared.ThemeSlots[slot.Index]))
		}
	}
	return append(lines, fmt.Sprintf("clued=%d missing=%d unfilled=%d", clued, missing, unfilled))
}

type CountedSlot struct{ Count, Index int }

func (c *Completed) StatsParagraph(name string, index *WordIndex) []string {
	p, state := c.Prepared, c.State
	layout := p.Layout
	grid, slots := layout.Grid, layout.Slots
	whites := grid.WhiteCells()
	blacks, givens := len(grid.Cells)-len(whites), 0
	for _, cell := range whites {
		if grid.Cells[cell] != '.' {
			givens++
		}
	}
	var holding []string
	for _, symmetry := range []string{"rot180", "mirror"} {
		if grid.AsymmetricCell(symmetry) < 0 {
			holding = append(holding, symmetry)
		}
	}
	symmetry := "none"
	if len(holding) > 0 {
		symmetry = strings.Join(holding, ",")
	}
	counts := make(map[int]int)
	across, lengthSum, longest, unchecked := 0, 0, 0, 0
	for _, slot := range slots {
		counts[slot.Length()]++
		lengthSum += slot.Length()
		longest = max(longest, slot.Length())
		if slot.Across {
			across++
		}
	}
	for _, cell := range whites {
		if layout.OwnerCount(cell) == 1 {
			unchecked++
		}
	}
	var lengths []int
	for length := range counts {
		lengths = append(lengths, length)
	}
	sort.Ints(lengths)
	var lengthText, supply, themes []string
	for _, length := range lengths {
		lengthText = append(lengthText, fmt.Sprintf("%d:%d", length, counts[length]))
		available := 0
		for _, id := range index.ByLength[length] {
			if index.Words[id].Score >= p.Settings.Minimum {
				available++
			}
		}
		supply = append(supply, fmt.Sprintf("%d:%d", length, available))
	}
	lines := []string{"TEMPLATE " + name, fmt.Sprintf("grid size=%dx%d blocks=%d white=%d density=%s givens=%d required=%s symmetry=%s", grid.Width, grid.Height, blacks, len(whites), decimal(100*blacks, len(grid.Cells), 1), givens, p.Settings.Symmetry, symmetry),
		fmt.Sprintf("slots across=%d down=%d total=%d lengths=%s avg_length=%s longest=%d unchecked=%d", across, len(slots)-across, len(slots), strings.Join(lengthText, ","), decimal(lengthSum, len(slots), 2), longest, unchecked)}
	var tight []CountedSlot
	for _, slot := range slots {
		if p.ThemeSlots[slot.Index] {
			themes = append(themes, c.Entry(slot, index))
		} else {
			tight = append(tight, CountedSlot{len(index.Candidates(p.Initial.Pattern(slot), p.Settings.Minimum, p.Initial.Used)), slot.Index})
		}
	}
	if len(themes) > 0 {
		lines = append(lines, "themes "+strings.Join(themes, " "))
	}
	lines = append(lines, "coverage "+strings.Join(supply, " "))
	sort.Slice(tight, func(i, j int) bool {
		if tight[i].Count == tight[j].Count {
			return tight[i].Index < tight[j].Index
		}
		return tight[i].Count < tight[j].Count
	})
	var tightText []string
	for _, item := range tight[:min(3, len(tight))] {
		tightText = append(tightText, fmt.Sprintf("%s:%d", slots[item.Index].Label, item.Count))
	}
	lines = append(lines, "tightest "+joined(tightText, " "))
	for number, attempt := range c.Attempts {
		lines = append(lines, fmt.Sprintf("attempt %d min_score=%d budget=%d outcome=%s nodes=%d backtracks=%d prunes=%d dead_ends=%d max_depth=%d", number+1, attempt.Minimum, attempt.Budget, attempt.Outcome, attempt.Nodes, attempt.Backtracks, attempt.Prunes, attempt.DeadEnds, attempt.MaxDepth))
	}
	last := c.FinalAttempt()
	lines = append(lines, "trace "+joined(last.Trace, " "))
	var hot []CountedSlot
	for i, count := range last.Failures {
		if count > 0 {
			hot = append(hot, CountedSlot{count, i})
		}
	}
	sort.Slice(hot, func(i, j int) bool {
		if hot[i].Count == hot[j].Count {
			return hot[i].Index < hot[j].Index
		}
		return hot[i].Count > hot[j].Count
	})
	var hotText []string
	for _, item := range hot[:min(3, len(hot))] {
		hotText = append(hotText, fmt.Sprintf("%s:%d", slots[item.Index].Label, item.Count))
	}
	lines = append(lines, "hotspots "+joined(hotText, " "))
	if c.Filled() {
		var order []string
		for _, slot := range last.Sequence {
			order = append(order, slots[slot].Label)
		}
		lines = append(lines, "order "+joined(order, " "))
		weakest := 0
		var weak []string
		for i, slot := range slots {
			score := index.Words[state.Words[i]].Score
			if score < index.Words[state.Words[weakest]].Score {
				weakest = i
			}
			if score < p.Settings.Weak {
				weak = append(weak, c.Entry(slot, index))
			}
		}
		total := c.TotalScore(index)
		lines = append(lines, fmt.Sprintf("quality total=%d average=%s weakest=%s weak=%s", total, decimal(total, len(slots), 2), c.Entry(slots[weakest], index), joined(weak, ",")))
		var present [26]bool
		points, distinct := 0, 0
		for _, cell := range whites {
			letter := state.Letters[cell] - 'A'
			present[letter] = true
			points += letterPoints[letter]
		}
		var missing strings.Builder
		for letter, found := range present {
			if found {
				distinct++
			} else {
				missing.WriteByte(byte('A' + letter))
			}
		}
		missingText, pangram := missing.String(), "no"
		if missingText == "" {
			missingText, pangram = "-", "yes"
		}
		worst, worstSum := -1, 0
		for _, cell := range whites {
			a, d := layout.AcrossSlot[cell], layout.DownSlot[cell]
			if a < 0 || d < 0 {
				continue
			}
			sum := index.Words[state.Words[a]].Score + index.Words[state.Words[d]].Score
			if worst < 0 || sum < worstSum {
				worst, worstSum = cell, sum
			}
		}
		crossing := "-"
		if worst >= 0 {
			a, d := layout.AcrossSlot[worst], layout.DownSlot[worst]
			crossing = fmt.Sprintf("%s %s:%s+%s:%s=%d", grid.Location(worst), slots[a].Label, index.Words[state.Words[a]].Text, slots[d].Label, index.Words[state.Words[d]].Text, worstSum)
		}
		lines = append(lines, fmt.Sprintf("letters distinct=%d pangram=%s missing=%s scrabble=%s worst_crossing=%s", distinct, pangram, missingText, decimal(points, len(whites), 2), crossing))
	} else {
		assigned, lettered := 0, 0
		for _, id := range state.Words {
			if id >= 0 {
				assigned++
			}
		}
		for _, cell := range whites {
			if state.Letters[cell] != '.' {
				lettered++
			}
		}
		var blocked []string
		for _, slot := range slots {
			if state.Words[slot.Index] < 0 && len(index.Candidates(state.Pattern(slot), last.Minimum, state.Used)) == 0 {
				blocked = append(blocked, slot.Label)
			}
		}
		lines = append(lines, fmt.Sprintf("partial assigned=%d/%d letters=%d/%d blocked=%s", assigned, len(slots), lettered, len(whites), joined(blocked, ",")))
	}
	return lines
}

type Template struct {
	Name, Error string
	Completed   *Completed
}

func (template *Template) GridParagraph() []string {
	lines := []string{"TEMPLATE " + template.Name}
	if template.Error != "" {
		return append(lines, "error "+template.Error)
	}
	result, last := template.Completed, template.Completed.FinalAttempt()
	lines = append(lines, fmt.Sprintf("outcome=%s attempts=%d min_score=%d", last.Outcome, len(result.Attempts), last.Minimum))
	lines = append(lines, gridLines(result.Prepared.Layout.Grid, result.State.Letters)...)
	lines = append(lines, "numbers")
	return append(lines, numberLines(result.Prepared.Layout)...)
}

func overallParagraphs(templates []*Template, index *WordIndex) [][]string {
	var valid, filled []*Template
	attempts, nodes, unfillable, budget := 0, 0, 0, 0
	for _, template := range templates {
		if template.Error != "" {
			continue
		}
		valid = append(valid, template)
		result := template.Completed
		if result.Filled() {
			filled = append(filled, template)
		} else if result.FinalAttempt().Outcome == "unfillable" {
			unfillable++
		} else {
			budget++
		}
		attempts += len(result.Attempts)
		for _, attempt := range result.Attempts {
			nodes += attempt.Nodes
		}
	}
	ranked := append([]*Template(nil), filled...)
	sort.Slice(ranked, func(i, j int) bool {
		first, second := ranked[i], ranked[j]
		left := first.Completed.TotalScore(index) * len(second.Completed.Prepared.Layout.Slots)
		right := second.Completed.TotalScore(index) * len(first.Completed.Prepared.Layout.Slots)
		if left == right {
			return first.Name < second.Name
		}
		return left > right
	})
	ranking := []string{"RANKING"}
	for position, template := range ranked {
		total, entries := template.Completed.TotalScore(index), len(template.Completed.Prepared.Layout.Slots)
		ranking = append(ranking, fmt.Sprintf("rank %d %s average=%s total=%d entries=%d", position+1, template.Name, decimal(total, entries, 2), total, entries))
	}
	appearances := make(map[int][]string)
	for _, template := range filled {
		for _, id := range template.Completed.State.Words {
			appearances[id] = append(appearances[id], template.Name)
		}
	}
	var reused []int
	for id, names := range appearances {
		if len(names) >= 2 {
			reused = append(reused, id)
		}
	}
	sort.Slice(reused, func(i, j int) bool {
		first, second := reused[i], reused[j]
		if len(appearances[first]) == len(appearances[second]) {
			return index.Words[first].Text < index.Words[second].Text
		}
		return len(appearances[first]) > len(appearances[second])
	})
	reuse := []string{"REUSE"}
	for _, id := range reused {
		names := appearances[id]
		reuse = append(reuse, fmt.Sprintf("reused %s %d %s", index.Words[id].Text, len(names), strings.Join(names, ",")))
	}
	summary := []string{fmt.Sprintf("SUMMARY templates=%d invalid=%d filled=%d unfillable=%d budget=%d attempts=%d nodes=%d", len(templates), len(templates)-len(valid), len(filled), unfillable, budget, attempts, nodes)}
	return [][]string{ranking, reuse, summary}
}

func main() {
	settings := readSettings(readLines("params.txt"))
	wordList := newWordList(readLines("words.txt"))
	index := wordList.Index
	clues := newClueBook(readLines("clues.txt"), index)
	names := make(map[string]bool)
	var templates []*Template
	for _, block := range splitBlocks(readLines("templates.txt")) {
		prepared, reason := prepare(block, settings, names, index)
		template := &Template{Name: block.Name, Error: reason}
		if reason == "" {
			template.Completed = newCompleted(prepared, index, clues)
		}
		names[block.Name] = true
		templates = append(templates, template)
	}
	var grids, clueLines, stats [][]string
	for _, template := range templates {
		grids = append(grids, template.GridParagraph())
		if template.Error == "" {
			clueLines = append(clueLines, template.Completed.ClueParagraph(template.Name, index))
			stats = append(stats, template.Completed.StatsParagraph(template.Name, index))
		}
	}
	stats = append(stats, overallParagraphs(templates, index)...)
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeParagraphs("grid.txt", grids)
	writeParagraphs("clues.txt", clueLines)
	writeParagraphs("search_stats.txt", stats)
	writeLines("wordlist.txt", append(wordList.Report(), clues.Report(index)...))
}
