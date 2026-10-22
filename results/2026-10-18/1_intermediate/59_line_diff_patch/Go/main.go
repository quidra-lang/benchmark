package main

import (
	"bufio"
	"errors"
	"fmt"
	"maps"
	"os"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

const (
	graphWidth = 20
	separator  = "======="
)

var (
	dataCommands        = []string{"FILE", "PATCH", "EDIT"}
	formatsWithArgument = []string{"IFDEF", "UNIFIED", "CONTEXT", "SIDE"}
	offsets             = []int{0, 1, -1, 2, -2, 3, -3}
	numberPair          = regexp.MustCompile(`^([0-9]{1,4})(?:,([0-9]{1,4}))?$`)
	repeatedSpaces      = regexp.MustCompile(` {2,}`)
	markerPrefixes      = map[string]string{"<<<<<<<": "start", "|||||||": "base", ">>>>>>>": "end"}
)

func number(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func rangeR(start, count int) string {
	switch {
	case count >= 2:
		return fmt.Sprintf("%d,%d", start+1, start+count)
	case count == 1:
		return strconv.Itoa(start + 1)
	}
	return strconv.Itoa(start)
}

func rangeU(start, count int) string {
	switch {
	case count >= 2:
		return fmt.Sprintf("%d,%d", start+1, count)
	case count == 1:
		return strconv.Itoa(start + 1)
	}
	return fmt.Sprintf("%d,0", start)
}

func rangeM(start, count int) string {
	return fmt.Sprintf("%d,%d", start+1, count)
}

func prefixed(prefix string, lines []string) []string {
	result := make([]string, len(lines))
	for i, line := range lines {
		result[i] = prefix + line
	}
	return result
}

type compareOptions struct {
	ignoreCase   bool
	ignoreWhite  bool
	squeezeSpace bool
}

func parseCompareOptions(words []string) compareOptions {
	return compareOptions{
		ignoreCase:   slices.Contains(words, "ICASE"),
		ignoreWhite:  slices.Contains(words, "IWHITE"),
		squeezeSpace: slices.Contains(words, "ISPACE"),
	}
}

func (o compareOptions) key(line string) string {
	if o.ignoreCase {
		line = strings.ToLower(line)
	}
	if o.ignoreWhite {
		line = strings.ReplaceAll(line, " ", "")
	}
	if o.squeezeSpace {
		line = repeatedSpaces.ReplaceAllString(line, " ")
	}
	return line
}

type pair struct {
	i, j int
}

func matchedPairs(first, second []string) []pair {
	rows, columns := len(first), len(second)
	table := make([][]int, rows+1)
	for i := range table {
		table[i] = make([]int, columns+1)
	}
	for i := 1; i <= rows; i++ {
		for j := 1; j <= columns; j++ {
			if first[i-1] == second[j-1] {
				table[i][j] = table[i-1][j-1] + 1
			} else {
				table[i][j] = max(table[i-1][j], table[i][j-1])
			}
		}
	}
	pairs := []pair{{rows + 1, columns + 1}}
	i, j := rows, columns
	for i >= 1 && j >= 1 {
		switch {
		case first[i-1] == second[j-1]:
			pairs = append(pairs, pair{i, j})
			i--
			j--
		case table[i-1][j] >= table[i][j-1]:
			i--
		default:
			j--
		}
	}
	pairs = append(pairs, pair{0, 0})
	slices.Reverse(pairs)
	return pairs
}

type changeBlock struct {
	p, q, x, y int
}

func (b *changeBlock) letter() string {
	switch {
	case b.x >= 1 && b.y >= 1:
		return "c"
	case b.y == 0:
		return "d"
	}
	return "a"
}

func changeBlocks(first, second []string) []changeBlock {
	pairs := matchedPairs(first, second)
	var blocks []changeBlock
	for k := 0; k+1 < len(pairs); k++ {
		current, next := pairs[k], pairs[k+1]
		deleted, inserted := next.i-current.i-1, next.j-current.j-1
		if deleted > 0 || inserted > 0 {
			blocks = append(blocks, changeBlock{current.i, current.j, deleted, inserted})
		}
	}
	return blocks
}

// A step is either a common line (block == nil) or a whole change block.
type step struct {
	oldIndex, newIndex int
	block              *changeBlock
}

func walk(blocks []changeBlock, oldStart, newStart, oldEnd int) []step {
	var steps []step
	oldIndex, newIndex := oldStart, newStart
	for k := range blocks {
		block := &blocks[k]
		for oldIndex < block.p {
			steps = append(steps, step{oldIndex, newIndex, nil})
			oldIndex++
			newIndex++
		}
		steps = append(steps, step{oldIndex, newIndex, block})
		oldIndex, newIndex = block.p+block.x, block.q+block.y
	}
	for oldIndex < oldEnd {
		steps = append(steps, step{oldIndex, newIndex, nil})
		oldIndex++
		newIndex++
	}
	return steps
}

func sideRow(left, symbol, right string, width int) string {
	row := fmt.Sprintf("%-*.*s %s %.*s", width, width, left, symbol, width, right)
	return strings.TrimRight(row, " ")
}

func statGraph(inserted, deleted int) string {
	total := inserted + deleted
	plus, minus := inserted, deleted
	if total > graphWidth {
		plus = graphWidth * inserted / total
		minus = graphWidth * deleted / total
		if inserted >= 1 && plus == 0 {
			plus = 1
		}
		if deleted >= 1 && minus == 0 {
			minus = 1
		}
	}
	return strings.Repeat("+", plus) + strings.Repeat("-", minus)
}

type hunk struct {
	blocks   []changeBlock
	oldStart int
	oldCount int
	newStart int
	newCount int
}

func newHunk(blocks []changeBlock, context, oldTotal int) hunk {
	first, last := blocks[0], blocks[len(blocks)-1]
	before := min(context, first.p)
	after := min(context, oldTotal-last.p-last.x)
	oldStart := first.p - before
	newStart := first.q - before
	return hunk{
		blocks:   blocks,
		oldStart: oldStart,
		oldCount: last.p + last.x + after - oldStart,
		newStart: newStart,
		newCount: last.q + last.y + after - newStart,
	}
}

func (h hunk) steps() []step {
	return walk(h.blocks, h.oldStart, h.newStart, h.oldStart+h.oldCount)
}

type lineDiff struct {
	oldLines []string
	newLines []string
	blocks   []changeBlock
}

func comparisonKeys(lines []string, options compareOptions) []string {
	keys := make([]string, len(lines))
	for i, line := range lines {
		keys[i] = options.key(line)
	}
	return keys
}

func newLineDiff(oldLines, newLines []string, options compareOptions) *lineDiff {
	blocks := changeBlocks(comparisonKeys(oldLines, options), comparisonKeys(newLines, options))
	return &lineDiff{oldLines: oldLines, newLines: newLines, blocks: blocks}
}

func (d *lineDiff) deleted(b *changeBlock) []string {
	return d.oldLines[b.p : b.p+b.x]
}

func (d *lineDiff) inserted(b *changeBlock) []string {
	return d.newLines[b.q : b.q+b.y]
}

func (d *lineDiff) hunks(context int) []hunk {
	var groups [][]changeBlock
	for _, block := range d.blocks {
		if len(groups) > 0 {
			group := groups[len(groups)-1]
			previous := group[len(group)-1]
			if block.p-(previous.p+previous.x) <= 2*context {
				groups[len(groups)-1] = append(group, block)
				continue
			}
		}
		groups = append(groups, []changeBlock{block})
	}
	hunks := make([]hunk, len(groups))
	for i, group := range groups {
		hunks[i] = newHunk(group, context, len(d.oldLines))
	}
	return hunks
}

func (d *lineDiff) normal() []string {
	var lines []string
	for k := range d.blocks {
		block := &d.blocks[k]
		letter := block.letter()
		lines = append(lines, rangeR(block.p, block.x)+letter+rangeR(block.q, block.y))
		lines = append(lines, prefixed("< ", d.deleted(block))...)
		if letter == "c" {
			lines = append(lines, "---")
		}
		lines = append(lines, prefixed("> ", d.inserted(block))...)
	}
	return lines
}

func (d *lineDiff) ed() []string {
	var lines []string
	for k := len(d.blocks) - 1; k >= 0; k-- {
		block := &d.blocks[k]
		letter := block.letter()
		lines = append(lines, rangeR(block.p, block.x)+letter)
		if letter != "d" {
			lines = append(lines, d.inserted(block)...)
			lines = append(lines, ".")
		}
	}
	return lines
}

func (d *lineDiff) rcs() []string {
	var lines []string
	for k := range d.blocks {
		block := &d.blocks[k]
		if block.x >= 1 {
			lines = append(lines, fmt.Sprintf("d%d %d", block.p+1, block.x))
		}
		if block.y >= 1 {
			lines = append(lines, fmt.Sprintf("a%d %d", block.p+block.x, block.y))
			lines = append(lines, d.inserted(block)...)
		}
	}
	return lines
}

func (d *lineDiff) ifdef(macro string) []string {
	var lines []string
	for _, s := range walk(d.blocks, 0, 0, len(d.oldLines)) {
		block := s.block
		switch {
		case block == nil:
			lines = append(lines, d.oldLines[s.oldIndex])
		case block.x >= 1 && block.y >= 1:
			lines = append(lines, "#ifndef "+macro)
			lines = append(lines, d.deleted(block)...)
			lines = append(lines, "#else /* "+macro+" */")
			lines = append(lines, d.inserted(block)...)
			lines = append(lines, "#endif /* "+macro+" */")
		case block.y == 0:
			lines = append(lines, "#ifndef "+macro)
			lines = append(lines, d.deleted(block)...)
			lines = append(lines, "#endif /* ! "+macro+" */")
		default:
			lines = append(lines, "#ifdef "+macro)
			lines = append(lines, d.inserted(block)...)
			lines = append(lines, "#endif /* "+macro+" */")
		}
	}
	return lines
}

func (d *lineDiff) unified(context int, oldName, newName string) []string {
	lines := []string{"--- " + oldName, "+++ " + newName}
	for _, h := range d.hunks(context) {
		oldRange := rangeU(h.oldStart, h.oldCount)
		newRange := rangeU(h.newStart, h.newCount)
		lines = append(lines, fmt.Sprintf("@@ -%s +%s @@", oldRange, newRange))
		for _, s := range h.steps() {
			if s.block == nil {
				lines = append(lines, " "+d.oldLines[s.oldIndex])
			} else {
				lines = append(lines, prefixed("-", d.deleted(s.block))...)
				lines = append(lines, prefixed("+", d.inserted(s.block))...)
			}
		}
	}
	return lines
}

func (d *lineDiff) context(context int, oldName, newName string) []string {
	lines := []string{"*** " + oldName, "--- " + newName}
	for _, h := range d.hunks(context) {
		lines = append(lines, strings.Repeat("*", 15))
		lines = append(lines, fmt.Sprintf("*** %s ****", rangeR(h.oldStart, h.oldCount)))
		if slices.ContainsFunc(h.blocks, func(b changeBlock) bool { return b.x >= 1 }) {
			for _, s := range h.steps() {
				if s.block == nil {
					lines = append(lines, "  "+d.oldLines[s.oldIndex])
					continue
				}
				marker := "- "
				if s.block.y >= 1 {
					marker = "! "
				}
				lines = append(lines, prefixed(marker, d.deleted(s.block))...)
			}
		}
		lines = append(lines, fmt.Sprintf("--- %s ----", rangeR(h.newStart, h.newCount)))
		if slices.ContainsFunc(h.blocks, func(b changeBlock) bool { return b.y >= 1 }) {
			for _, s := range h.steps() {
				if s.block == nil {
					lines = append(lines, "  "+d.newLines[s.newIndex])
					continue
				}
				marker := "+ "
				if s.block.x >= 1 {
					marker = "! "
				}
				lines = append(lines, prefixed(marker, d.inserted(s.block))...)
			}
		}
	}
	return lines
}

func (d *lineDiff) sideBySide(width int) []string {
	var lines []string
	for _, s := range walk(d.blocks, 0, 0, len(d.oldLines)) {
		block := s.block
		if block == nil {
			left, right := d.oldLines[s.oldIndex], d.newLines[s.newIndex]
			lines = append(lines, sideRow(left, " ", right, width))
			continue
		}
		for row := range max(block.x, block.y) {
			switch {
			case row < block.x && row < block.y:
				left, right := d.oldLines[block.p+row], d.newLines[block.q+row]
				lines = append(lines, sideRow(left, "|", right, width))
			case row < block.x:
				lines = append(lines, sideRow(d.oldLines[block.p+row], "<", "", width))
			default:
				lines = append(lines, sideRow("", ">", d.newLines[block.q+row], width))
			}
		}
	}
	return lines
}

type tokenTotals struct {
	deleted  int
	inserted int
	common   int
}

func splitTokens(line string, byWord bool) []string {
	if byWord {
		return strings.Fields(line)
	}
	return strings.Split(line, "")
}

func deletion(tokens []string, separator string) string {
	return "[-" + strings.Join(tokens, separator) + "-]"
}

func insertion(tokens []string, separator string) string {
	return "{+" + strings.Join(tokens, separator) + "+}"
}

func compareTokens(oldTokens, newTokens []string, separator string, totals *tokenTotals) string {
	var parts []string
	for _, s := range walk(changeBlocks(oldTokens, newTokens), 0, 0, len(oldTokens)) {
		block := s.block
		if block == nil {
			parts = append(parts, oldTokens[s.oldIndex])
			totals.common++
			continue
		}
		if block.x >= 1 {
			parts = append(parts, deletion(oldTokens[block.p:block.p+block.x], separator))
		}
		if block.y >= 1 {
			parts = append(parts, insertion(newTokens[block.q:block.q+block.y], separator))
		}
		totals.deleted += block.x
		totals.inserted += block.y
	}
	return strings.Join(parts, separator)
}

type bodyLine struct {
	kind byte
	text string
}

type patchHunk struct {
	lineNumber int
	oldStart   int
	oldCount   int
	newStart   int
	newCount   int
	body       []bodyLine
}

func (h *patchHunk) sequences(reverse bool) (oldLines, newLines []string) {
	oldKind, newKind := byte('-'), byte('+')
	if reverse {
		oldKind, newKind = newKind, oldKind
	}
	for _, line := range h.body {
		if line.kind == ' ' || line.kind == oldKind {
			oldLines = append(oldLines, line.text)
		}
		if line.kind == ' ' || line.kind == newKind {
			newLines = append(newLines, line.text)
		}
	}
	return oldLines, newLines
}

func (h *patchHunk) start(reverse bool) int {
	if reverse {
		return h.newStart
	}
	return h.oldStart
}

func (h *patchHunk) leadingContext() int {
	count := 0
	for count < len(h.body) && h.body[count].kind == ' ' {
		count++
	}
	return count
}

func (h *patchHunk) trailingContext() int {
	count := 0
	for count < len(h.body) && h.body[len(h.body)-1-count].kind == ' ' {
		count++
	}
	return count
}

type hunkMatch struct {
	fuzz     int
	delta    int
	position int
	lines    []string
}

func (m *hunkMatch) report(number int) string {
	text := fmt.Sprintf("Hunk #%d succeeded at %d", number, m.position+1)
	if m.fuzz >= 1 {
		text += fmt.Sprintf(" with fuzz %d", m.fuzz)
	}
	if m.delta == 1 || m.delta == -1 {
		text += fmt.Sprintf(" (offset %d line)", m.delta)
	} else if m.delta != 0 {
		text += fmt.Sprintf(" (offset %d lines)", m.delta)
	}
	return text
}

func parseRange(text, sign string) (start, count int, ok bool) {
	digits, found := strings.CutPrefix(text, sign)
	if !found {
		return 0, 0, false
	}
	match := numberPair.FindStringSubmatch(digits)
	if match == nil {
		return 0, 0, false
	}
	start, count = number(match[1]), 1
	if match[2] != "" {
		count = number(match[2])
	}
	if start == 0 && count != 0 {
		return 0, 0, false
	}
	return start, count, true
}

func parseHunkHeader(line string, lineNumber int) (*patchHunk, error) {
	parts := strings.Split(line, " ")
	if len(parts) == 4 && parts[0] == "@@" && parts[3] == "@@" {
		oldStart, oldCount, oldOK := parseRange(parts[1], "-")
		newStart, newCount, newOK := parseRange(parts[2], "+")
		if oldOK && newOK {
			return &patchHunk{
				lineNumber: lineNumber,
				oldStart:   oldStart,
				oldCount:   oldCount,
				newStart:   newStart,
				newCount:   newCount,
			}, nil
		}
	}
	return nil, fmt.Errorf("PATCH ERROR line %d: bad hunk header", lineNumber)
}

func parsePatch(patchLines []string) ([]*patchHunk, error) {
	index := slices.IndexFunc(patchLines, func(line string) bool {
		return strings.HasPrefix(line, "@@")
	})
	if index < 0 {
		return nil, errors.New("PATCH ERROR no hunks")
	}
	var hunks []*patchHunk
	for index < len(patchLines) {
		h, err := parseHunkHeader(patchLines[index], index+1)
		if err != nil {
			return nil, err
		}
		index++
		oldSeen, newSeen := 0, 0
		for oldSeen < h.oldCount || newSeen < h.newCount {
			if index == len(patchLines) {
				return nil, fmt.Errorf("PATCH ERROR line %d: truncated hunk", h.lineNumber)
			}
			line := patchLines[index]
			kind := line[0]
			inOld := kind == ' ' || kind == '-'
			inNew := kind == ' ' || kind == '+'
			if len(line) < 2 || !(inOld || inNew) ||
				(inOld && oldSeen == h.oldCount) || (inNew && newSeen == h.newCount) {
				return nil, fmt.Errorf("PATCH ERROR line %d: bad hunk line", index+1)
			}
			h.body = append(h.body, bodyLine{kind, line[1:]})
			if inOld {
				oldSeen++
			}
			if inNew {
				newSeen++
			}
			index++
		}
		if !slices.ContainsFunc(h.body, func(line bodyLine) bool { return line.kind != ' ' }) {
			return nil, fmt.Errorf("PATCH ERROR line %d: no changes", h.lineNumber)
		}
		hunks = append(hunks, h)
	}
	return hunks, nil
}

func searchHunk(
	h *patchHunk, lines []string, adjustment int, reverse bool, maxFuzz int,
) *hunkMatch {
	oldLines, newLines := h.sequences(reverse)
	expected := h.start(reverse) + adjustment
	if len(oldLines) > 0 {
		expected--
	}
	leading, trailing := h.leadingContext(), h.trailingContext()
	for fuzz := 0; fuzz <= maxFuzz; fuzz++ {
		head := min(fuzz, leading)
		tail := min(fuzz, trailing)
		oldPart := oldLines[head : len(oldLines)-tail]
		newPart := newLines[head : len(newLines)-tail]
		for _, delta := range offsets {
			position := expected + head + delta
			end := position + len(oldPart)
			if position < 0 || end > len(lines) {
				continue
			}
			if slices.Equal(lines[position:end], oldPart) {
				result := slices.Concat(lines[:position], newPart, lines[end:])
				return &hunkMatch{fuzz, delta, position, result}
			}
		}
	}
	return nil
}

type editCommand struct {
	instruction byte
	first       int
	last        int
}

func parseEditCommand(line string) (editCommand, bool) {
	instruction, address := line[len(line)-1], line[:len(line)-1]
	match := numberPair.FindStringSubmatch(address)
	if !strings.ContainsRune("acd", rune(instruction)) || match == nil {
		return editCommand{}, false
	}
	if instruction == 'a' && match[2] != "" {
		return editCommand{}, false
	}
	first := number(match[1])
	last := first
	if match[2] != "" {
		last = number(match[2])
	}
	return editCommand{instruction, first, last}, true
}

func runEditScript(lines, script []string) ([]string, int, error) {
	lines = slices.Clone(lines)
	executed := 0
	index := 0
	for index < len(script) {
		lineNumber := index + 1
		command, ok := parseEditCommand(script[index])
		if !ok {
			return nil, 0, fmt.Errorf("EDIT ERROR line %d: bad command", lineNumber)
		}
		var valid bool
		if command.instruction == 'a' {
			valid = command.first <= len(lines)
		} else {
			valid = 1 <= command.first && command.first <= command.last &&
				command.last <= len(lines)
		}
		if !valid {
			return nil, 0, fmt.Errorf("EDIT ERROR line %d: bad range", lineNumber)
		}
		index++
		var text []string
		if command.instruction != 'd' {
			end := index
			for end < len(script) && script[end] != "." {
				end++
			}
			if end == len(script) {
				return nil, 0, fmt.Errorf("EDIT ERROR line %d: missing terminator", lineNumber)
			}
			text = script[index:end]
			index = end + 1
		}
		switch command.instruction {
		case 'a':
			lines = slices.Insert(lines, command.first, text...)
		case 'c':
			lines = slices.Replace(lines, command.first-1, command.last, text...)
		default:
			lines = slices.Delete(lines, command.first-1, command.last)
		}
		executed++
	}
	return lines, executed, nil
}

type chunk struct {
	kind        string
	baseStart   int
	oursStart   int
	theirsStart int
	base        []string
	ours        []string
	theirs      []string
}

func (c *chunk) location() string {
	return fmt.Sprintf("base %s a %s b %s", rangeM(c.baseStart, len(c.base)),
		rangeM(c.oursStart, len(c.ours)), rangeM(c.theirsStart, len(c.theirs)))
}

func chunkKind(base, ours, theirs []string) string {
	switch {
	case slices.Equal(ours, base):
		return "b"
	case slices.Equal(theirs, base):
		return "a"
	case slices.Equal(ours, theirs):
		return "both"
	}
	return "conflict"
}

func matchTable(first, second []string) []int {
	matches := make([]int, len(first)+2)
	pairs := matchedPairs(first, second)
	for _, p := range pairs[1 : len(pairs)-1] {
		matches[p.i] = p.j
	}
	return matches
}

func threeWayChunks(base, ours, theirs []string) []chunk {
	oursMatch := matchTable(base, ours)
	theirsMatch := matchTable(base, theirs)
	var chunks []chunk
	x, y, z := 0, 0, 0
	for x < len(base) || y < len(ours) || z < len(theirs) {
		if x < len(base) && oursMatch[x+1] == y+1 && theirsMatch[x+1] == z+1 {
			stable := chunk{"stable", x, y, z, base[x : x+1], ours[y : y+1], theirs[z : z+1]}
			chunks = append(chunks, stable)
			x++
			y++
			z++
			continue
		}
		anchor := x + 1
		for anchor <= len(base) && (oursMatch[anchor] == 0 || theirsMatch[anchor] == 0) {
			anchor++
		}
		nextX, nextY, nextZ := len(base), len(ours), len(theirs)
		if anchor <= len(base) {
			nextX, nextY, nextZ = anchor-1, oursMatch[anchor]-1, theirsMatch[anchor]-1
		}
		basePart, oursPart, theirsPart := base[x:nextX], ours[y:nextY], theirs[z:nextZ]
		kind := chunkKind(basePart, oursPart, theirsPart)
		chunks = append(chunks, chunk{kind, x, y, z, basePart, oursPart, theirsPart})
		x, y, z = nextX, nextY, nextZ
	}
	return chunks
}

func kindCounts(chunks []chunk) string {
	counts := map[string]int{}
	for _, c := range chunks {
		counts[c.kind]++
	}
	return fmt.Sprintf("a=%d b=%d both=%d conflicts=%d",
		counts["a"], counts["b"], counts["both"], counts["conflict"])
}

func commonPrefixLength(first, second []string) int {
	length := 0
	for length < len(first) && length < len(second) && first[length] == second[length] {
		length++
	}
	return length
}

func commonSuffixLength(first, second []string, limit int) int {
	length := 0
	for length < limit && first[len(first)-1-length] == second[len(second)-1-length] {
		length++
	}
	return length
}

func conflictLines(c *chunk, mode, baseName, oursName, theirsName string) []string {
	switch mode {
	case "OURS":
		return c.ours
	case "THEIRS":
		return c.theirs
	case "DIFF3":
		return slices.Concat([]string{"<<<<<<< " + oursName}, c.ours,
			[]string{"||||||| " + baseName}, c.base,
			[]string{separator}, c.theirs, []string{">>>>>>> " + theirsName})
	}
	ours, theirs := c.ours, c.theirs
	head := commonPrefixLength(ours, theirs)
	tail := commonSuffixLength(ours, theirs, min(len(ours), len(theirs))-head)
	oursMiddle := ours[head : len(ours)-tail]
	theirsMiddle := theirs[head : len(theirs)-tail]
	var middle []string
	if mode == "UNION" {
		middle = slices.Concat(oursMiddle, theirsMiddle)
	} else {
		middle = slices.Concat([]string{"<<<<<<< " + oursName}, oursMiddle, []string{separator},
			theirsMiddle, []string{">>>>>>> " + theirsName})
	}
	return slices.Concat(ours[:head], middle, ours[len(ours)-tail:])
}

func markerKind(line string) string {
	if line == separator {
		return "separator"
	}
	if len(line) < 7 || (len(line) > 7 && line[7] != ' ') {
		return ""
	}
	return markerPrefixes[line[:7]]
}

func nextMarker(lines []string, index int) int {
	index++
	for index < len(lines) && markerKind(lines[index]) == "" {
		index++
	}
	return index
}

type conflictRegion struct {
	start   int
	end     int
	ours    []string
	base    []string
	hasBase bool
	theirs  []string
}

func (r *conflictRegion) part(side string) []string {
	switch side {
	case "OURS":
		return r.ours
	case "THEIRS":
		return r.theirs
	case "BASE":
		return r.base
	}
	return slices.Concat(r.ours, r.theirs)
}

func regionAt(lines []string, start int) (conflictRegion, bool) {
	if markerKind(lines[start]) != "start" {
		return conflictRegion{}, false
	}
	middle := nextMarker(lines, start)
	baseMarker := -1
	if middle < len(lines) && markerKind(lines[middle]) == "base" {
		baseMarker = middle
		middle = nextMarker(lines, middle)
	}
	if middle == len(lines) || markerKind(lines[middle]) != "separator" {
		return conflictRegion{}, false
	}
	end := nextMarker(lines, middle)
	if end == len(lines) || markerKind(lines[end]) != "end" {
		return conflictRegion{}, false
	}
	region := conflictRegion{start: start + 1, end: end + 1, theirs: lines[middle+1 : end]}
	if baseMarker < 0 {
		region.ours = lines[start+1 : middle]
	} else {
		region.ours = lines[start+1 : baseMarker]
		region.base = lines[baseMarker+1 : middle]
		region.hasBase = true
	}
	return region, true
}

func conflictRegions(lines []string) []conflictRegion {
	var regions []conflictRegion
	index := 0
	for index < len(lines) {
		region, found := regionAt(lines, index)
		if found {
			regions = append(regions, region)
			index = region.end
		} else {
			index++
		}
	}
	return regions
}

type snapshot struct {
	lines  []string
	exists bool
}

type workspace struct {
	files   map[string][]string
	history map[string][]snapshot
	out     *bufio.Writer
}

func (w *workspace) emit(format string, args ...any) {
	fmt.Fprintf(w.out, format+"\n", args...)
}

func (w *workspace) emitLines(lines []string) {
	for _, line := range lines {
		fmt.Fprintln(w.out, line)
	}
}

func (w *workspace) require(names ...string) error {
	for _, name := range names {
		if _, ok := w.files[name]; !ok {
			return errors.New("ERROR no such file " + name)
		}
	}
	return nil
}

func (w *workspace) save(name string, lines []string) {
	previous, exists := w.files[name]
	w.history[name] = append(w.history[name], snapshot{previous, exists})
	w.files[name] = slices.Clone(lines)
}

func (w *workspace) loadFile(name string, data []string) {
	w.save(name, data)
	w.emit("FILE %s lines=%d", name, len(data))
}

func (w *workspace) copy(source, target string) error {
	if err := w.require(source); err != nil {
		return err
	}
	lines := w.files[source]
	w.save(target, lines)
	w.emit("COPY %s %s lines=%d", source, target, len(lines))
	return nil
}

func (w *workspace) printFile(name string) error {
	if err := w.require(name); err != nil {
		return err
	}
	lines := w.files[name]
	w.emit("PRINT %s lines=%d", name, len(lines))
	for i, line := range lines {
		w.emit("%3d| %s", i+1, line)
	}
	return nil
}

func (w *workspace) listFiles() {
	w.emit("FILES count=%d", len(w.files))
	for _, name := range slices.Sorted(maps.Keys(w.files)) {
		w.emit("%s lines=%d undo=%d", name, len(w.files[name]), len(w.history[name]))
	}
}

func (w *workspace) undo(name string) error {
	states := w.history[name]
	if len(states) == 0 {
		return errors.New("ERROR nothing to undo " + name)
	}
	state := states[len(states)-1]
	w.history[name] = states[:len(states)-1]
	if !state.exists {
		delete(w.files, name)
		w.emit("UNDO %s removed", name)
	} else {
		w.files[name] = state.lines
		w.emit("UNDO %s lines=%d", name, len(state.lines))
	}
	return nil
}

func (w *workspace) diff(args []string) error {
	oldName, newName, format := args[0], args[1], args[2]
	if err := w.require(oldName, newName); err != nil {
		return err
	}
	parameter := ""
	options := args[3:]
	if slices.Contains(formatsWithArgument, format) {
		parameter = args[3]
		options = args[4:]
	}
	diff := newLineDiff(w.files[oldName], w.files[newName], parseCompareOptions(options))
	if len(diff.blocks) == 0 {
		w.emit("Files %s and %s are identical", oldName, newName)
		return nil
	}
	switch format {
	case "BRIEF":
		w.emit("Files %s and %s differ", oldName, newName)
	case "NORMAL":
		w.emitLines(diff.normal())
	case "ED":
		w.emitLines(diff.ed())
	case "RCS":
		w.emitLines(diff.rcs())
	case "IFDEF":
		w.emitLines(diff.ifdef(parameter))
	case "UNIFIED":
		w.emitLines(diff.unified(number(parameter), oldName, newName))
	case "CONTEXT":
		w.emitLines(diff.context(number(parameter), oldName, newName))
	default:
		w.emitLines(diff.sideBySide(number(parameter)))
	}
	return nil
}

func (w *workspace) tokenDiff(oldName, newName string, byWord bool) error {
	if err := w.require(oldName, newName); err != nil {
		return err
	}
	oldLines, newLines := w.files[oldName], w.files[newName]
	diff := newLineDiff(oldLines, newLines, compareOptions{})
	if len(diff.blocks) == 0 {
		w.emit("Files %s and %s are identical", oldName, newName)
		return nil
	}
	separator := ""
	label := "CHARS"
	if byWord {
		separator = " "
		label = "WORDS"
	}
	var totals tokenTotals
	for _, block := range diff.blocks {
		for row := range max(block.x, block.y) {
			oldNumber, newNumber := block.p+row+1, block.q+row+1
			switch {
			case row < block.x && row < block.y:
				oldTokens := splitTokens(oldLines[oldNumber-1], byWord)
				newTokens := splitTokens(newLines[newNumber-1], byWord)
				text := compareTokens(oldTokens, newTokens, separator, &totals)
				w.emit("a%d b%d: %s", oldNumber, newNumber, text)
			case row < block.x:
				oldTokens := splitTokens(oldLines[oldNumber-1], byWord)
				totals.deleted += len(oldTokens)
				w.emit("a%d: %s", oldNumber, deletion(oldTokens, separator))
			default:
				newTokens := splitTokens(newLines[newNumber-1], byWord)
				totals.inserted += len(newTokens)
				w.emit("b%d: %s", newNumber, insertion(newTokens, separator))
			}
		}
	}
	w.emit("%s deleted=%d inserted=%d common=%d",
		label, totals.deleted, totals.inserted, totals.common)
	return nil
}

func (w *workspace) stat(args []string) error {
	oldName, newName := args[0], args[1]
	if err := w.require(oldName, newName); err != nil {
		return err
	}
	oldLines, newLines := w.files[oldName], w.files[newName]
	diff := newLineDiff(oldLines, newLines, parseCompareOptions(args[2:]))
	deleted, inserted := 0, 0
	for _, block := range diff.blocks {
		deleted += block.x
		inserted += block.y
	}
	total := deleted + inserted
	unchanged := len(oldLines) - deleted
	summary := fmt.Sprintf("%s -> %s | %d", oldName, newName, total)
	if total > 0 {
		summary += " " + statGraph(inserted, deleted)
	}
	w.emit("%s", summary)
	similarity := 100
	if lineTotal := len(oldLines) + len(newLines); lineTotal > 0 {
		similarity = 200 * unchanged / lineTotal
	}
	w.emit("changes=%d insertions=%d deletions=%d unchanged=%d similarity=%d%%",
		len(diff.blocks), inserted, deleted, unchanged, similarity)
	return nil
}

func (w *workspace) patch(args, data []string) error {
	name := args[0]
	if err := w.require(name); err != nil {
		return err
	}
	options := args[2:]
	reverse := slices.Contains(options, "REVERSE")
	dryRun := slices.Contains(options, "DRYRUN")
	maxFuzz := 0
	if i := slices.Index(options, "FUZZ"); i >= 0 {
		maxFuzz = number(options[i+1])
	}
	hunks, err := parsePatch(data)
	if err != nil {
		return err
	}
	if dryRun {
		w.emit("checking file %s", name)
	} else {
		w.emit("patching file %s", name)
	}
	lines := w.files[name]
	first := hunks[0]
	if searchHunk(first, lines, 0, reverse, maxFuzz) == nil &&
		searchHunk(first, lines, 0, !reverse, maxFuzz) != nil {
		w.emit("Reversed (or previously applied) patch detected! Skipping patch.")
		w.emit("RESULT applied=0 failed=0 ignored=%d lines=%d", len(hunks), len(lines))
		return nil
	}
	adjustment, applied, failed := 0, 0, 0
	for i, h := range hunks {
		match := searchHunk(h, lines, adjustment, reverse, maxFuzz)
		if match == nil {
			failed++
			w.emit("Hunk #%d FAILED at %d", i+1, h.start(reverse))
			continue
		}
		oldLines, newLines := h.sequences(reverse)
		lines = match.lines
		adjustment += match.delta + len(newLines) - len(oldLines)
		applied++
		w.emit("%s", match.report(i+1))
	}
	w.emit("RESULT applied=%d failed=%d ignored=0 lines=%d", applied, failed, len(lines))
	if !dryRun && applied >= 1 {
		w.save(name, lines)
	}
	return nil
}

func (w *workspace) edit(name string, data []string) error {
	if err := w.require(name); err != nil {
		return err
	}
	lines, executed, err := runEditScript(w.files[name], data)
	if err != nil {
		return err
	}
	w.emit("EDIT %s commands=%d lines=%d", name, executed, len(lines))
	w.save(name, lines)
	return nil
}

func (w *workspace) threeWay(baseName, oursName, theirsName string) ([]chunk, error) {
	if err := w.require(baseName, oursName, theirsName); err != nil {
		return nil, err
	}
	return threeWayChunks(w.files[baseName], w.files[oursName], w.files[theirsName]), nil
}

func (w *workspace) diff3(baseName, oursName, theirsName string) error {
	chunks, err := w.threeWay(baseName, oursName, theirsName)
	if err != nil {
		return err
	}
	changes := 0
	for k := range chunks {
		c := &chunks[k]
		if c.kind == "stable" {
			continue
		}
		changes++
		w.emit("==== %s %s", c.kind, c.location())
		w.emitLines(prefixed("O ", c.base))
		if c.kind != "b" {
			w.emitLines(prefixed("A ", c.ours))
		}
		if c.kind == "b" || c.kind == "conflict" {
			w.emitLines(prefixed("B ", c.theirs))
		}
	}
	w.emit("DIFF3 chunks=%d %s", changes, kindCounts(chunks))
	return nil
}

func (w *workspace) merge(args []string) error {
	baseName, oursName, theirsName, target := args[0], args[1], args[2], args[3]
	mode := "MARKERS"
	if len(args) == 5 {
		mode = args[4]
	}
	chunks, err := w.threeWay(baseName, oursName, theirsName)
	if err != nil {
		return err
	}
	var result []string
	var conflicts []*chunk
	for k := range chunks {
		c := &chunks[k]
		switch c.kind {
		case "b":
			result = append(result, c.theirs...)
		case "conflict":
			result = append(result, conflictLines(c, mode, baseName, oursName, theirsName)...)
			conflicts = append(conflicts, c)
		default:
			result = append(result, c.ours...)
		}
	}
	w.emit("MERGE %s lines=%d %s", target, len(result), kindCounts(chunks))
	for i, c := range conflicts {
		w.emit("CONFLICT %d %s", i+1, c.location())
	}
	w.save(target, result)
	return nil
}

func (w *workspace) conflicts(name string) error {
	if err := w.require(name); err != nil {
		return err
	}
	regions := conflictRegions(w.files[name])
	w.emit("CONFLICTS %s count=%d", name, len(regions))
	for i, region := range regions {
		base := "none"
		if region.hasBase {
			base = strconv.Itoa(len(region.base))
		}
		w.emit("%d: lines %d-%d ours=%d base=%s theirs=%d",
			i+1, region.start, region.end, len(region.ours), base, len(region.theirs))
	}
	return nil
}

func (w *workspace) resolve(name, numberText, side string) error {
	if err := w.require(name); err != nil {
		return err
	}
	index := number(numberText)
	lines := w.files[name]
	regions := conflictRegions(lines)
	if len(regions) < index {
		return fmt.Errorf("ERROR no conflict %d in %s", index, name)
	}
	region := regions[index-1]
	if side == "BASE" && !region.hasBase {
		return fmt.Errorf("ERROR no base section in conflict %d", index)
	}
	content := slices.Concat(lines[:region.start-1], region.part(side), lines[region.end:])
	remaining := len(conflictRegions(content))
	w.emit("RESOLVE %s %d %s lines=%d remaining=%d", name, index, side, len(content), remaining)
	w.save(name, content)
	return nil
}

func (w *workspace) execute(words, data []string) error {
	args := words[1:]
	switch words[0] {
	case "FILE":
		w.loadFile(args[0], data)
	case "COPY":
		return w.copy(args[0], args[1])
	case "PRINT":
		return w.printFile(args[0])
	case "FILES":
		w.listFiles()
	case "DIFF":
		return w.diff(args)
	case "WORDDIFF":
		return w.tokenDiff(args[0], args[1], true)
	case "CHARDIFF":
		return w.tokenDiff(args[0], args[1], false)
	case "STAT":
		return w.stat(args)
	case "PATCH":
		return w.patch(args, data)
	case "EDIT":
		return w.edit(args[0], data)
	case "DIFF3":
		return w.diff3(args[0], args[1], args[2])
	case "MERGE":
		return w.merge(args)
	case "CONFLICTS":
		return w.conflicts(args[0])
	case "RESOLVE":
		return w.resolve(args[0], args[1], args[2])
	case "UNDO":
		return w.undo(args[0])
	}
	return nil
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var lines []string
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	w := &workspace{files: map[string][]string{}, history: map[string][]snapshot{}, out: out}
	position := 1
	for range number(lines[0]) {
		words := strings.Split(lines[position], " ")
		position++
		var data []string
		if slices.Contains(dataCommands, words[0]) {
			count := number(words[2])
			data = lines[position : position+count]
			position += count
		}
		if err := w.execute(words, data); err != nil {
			fmt.Fprintln(out, err)
		}
	}
}
