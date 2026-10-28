package main

import (
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	if len(data) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}
func wordsIn(text string) []string {
	words := []string{}
	for _, word := range strings.Split(text, " ") {
		if word != "" {
			words = append(words, word)
		}
	}
	return words
}
func splitLabel(text string) (string, string) {
	if strings.HasSuffix(text, "}") {
		if i := strings.LastIndex(text, " {#"); i >= 0 {
			return text[:i], text[i+3 : len(text)-1]
		}
	}
	return text, ""
}

type TextLine struct {
	Text               string
	Footnotes, Indexes []int
	Anchor             int
	ChapterStart       bool
}

func textLine(text string) *TextLine { return &TextLine{Text: text, Anchor: -1} }

type Position struct{ Word, Offset int }
type BreakPosition struct {
	Start, End            Position
	Midword, AppendHyphen bool
}
type PieceRange struct{ Word, First, Last int }
type MeasuredLine struct {
	Start, End                    int
	Pieces                        []string
	Ranges                        []PieceRange
	Gaps, Length, Capacity, Slack int
	Last, Midword                 bool
}
type TextMetrics struct {
	Words                        []string
	FirstCapacity, LaterCapacity int
	Offsets                      []int
	Breaks                       []BreakPosition
	End                          int
}

func newTextMetrics(words []string, first, later int, dictionary *Hyphenation) *TextMetrics {
	m := &TextMetrics{Words: words, FirstCapacity: first, LaterCapacity: later, Breaks: []BreakPosition{{}}}
	offset := 0
	for i, word := range words {
		m.Offsets = append(m.Offsets, offset)
		offset += len(word) + 1
		for _, p := range dictionary.SplitPoints(word) {
			point := Position{i, p.Position}
			m.Breaks = append(m.Breaks, BreakPosition{point, point, true, p.AppendHyphen})
		}
		m.Breaks = append(m.Breaks, BreakPosition{Position{i + 1, 0}, Position{i, len(word)}, false, false})
	}
	m.End = len(m.Breaks) - 1
	return m
}
func (m *TextMetrics) Capacity(start int) int {
	if start == 0 {
		return m.FirstCapacity
	}
	return m.LaterCapacity
}
func (m *TextMetrics) Length(start, end int) int {
	a, b := m.Breaks[start].Start, m.Breaks[end].End
	length := m.Offsets[b.Word] + b.Offset - m.Offsets[a.Word] - a.Offset
	if m.Breaks[end].AppendHyphen {
		length++
	}
	return length
}
func (m *TextMetrics) Slack(start, end int) int { return m.Capacity(start) - m.Length(start, end) }
func (m *TextMetrics) Measure(start, end int) *MeasuredLine {
	a, b := m.Breaks[start].Start, m.Breaks[end].End
	line := &MeasuredLine{Start: start, End: end, Length: m.Length(start, end), Capacity: m.Capacity(start), Last: end == m.End, Midword: m.Breaks[end].Midword}
	line.Slack = line.Capacity - line.Length
	for word := a.Word; word <= b.Word; word++ {
		first, last := 0, len(m.Words[word])
		if word == a.Word {
			first = a.Offset
		}
		if word == b.Word {
			last = b.Offset
		}
		line.Pieces = append(line.Pieces, m.Words[word][first:last])
		line.Ranges = append(line.Ranges, PieceRange{word, first, last})
	}
	if m.Breaks[end].AppendHyphen {
		line.Pieces[len(line.Pieces)-1] += "-"
	}
	line.Gaps = len(line.Pieces) - 1
	return line
}

type TextResult struct {
	Lines  []*TextLine
	Broken []*MeasuredLine
	Cost   int
}
type WordMark struct {
	Kind             string
	Number, Position int
}
type IndexEntry struct {
	Name       string
	Marks      []int
	References map[string]bool
	Children   map[string]*IndexEntry
}

func newIndexEntry(name string) *IndexEntry {
	return &IndexEntry{Name: name, References: map[string]bool{}, Children: map[string]*IndexEntry{}}
}

type Page struct {
	Content                          []*TextLine
	Footnotes                        []int
	Height, Serial, BodyNumber       int
	EndsByForce, Blank, ChapterStart bool
	Display, Header, Footer          string
	Body                             []string
}
type WarningText struct {
	Name    string
	Text    *TextResult
	Justify bool
}
type GeneratedLines struct {
	Block *Block
	Lines []*TextLine
}
type LayoutResult struct {
	Method            string
	Bodies, Footnotes map[int]*TextResult
	WarningTexts      []WarningText
	Generated         []GeneratedLines
	Pages             []*Page
	FrontMatter       int
	BlockPages        map[int]*Page
	MarkPages         map[int]int
	LabelValues       map[string]string
}
type Typesetter struct {
	Document                             *Document
	Params                               map[string]int
	Dictionary                           *Hyphenation
	Labels                               map[string]*Block
	Bibliography                         map[string]*BibEntry
	BibOrder, CitedEntries               []*BibEntry
	BodyBlocks, Headings, NumberedTables []*Block
	Footnotes, IndexMarks                []string
	IndexEntries                         map[string]*IndexEntry
}

func newTypesetter(d *Document, p map[string]int, dictionary []string) *Typesetter {
	t := &Typesetter{Document: d, Params: p, Dictionary: newHyphenation(dictionary, d.Hyphenation, p["left_min"],
		p["right_min"]), Labels: map[string]*Block{}, Bibliography: map[string]*BibEntry{}, IndexEntries: map[string]*IndexEntry{}}
	t.RegisterDocument()
	t.CheckDocument()
	t.AssignBibliographyLabels()
	t.PrepareIndex()
	sort.SliceStable(d.Warnings, func(i, j int) bool { return d.Warnings[i].Number < d.Warnings[j].Number })
	return t
}
func (t *Typesetter) Warn(line int, message string) {
	t.Document.Warnings = append(t.Document.Warnings, Warning{line, message})
}
func (t *Typesetter) RegisterDocument() {
	chapter, section, tableNumber := 0, 0, 0
	var previous *Block
	for index, b := range t.Document.Blocks {
		b.ID = index
		kind := b.Kind
		switch kind {
		case "h1", "h2":
			b.Text, b.Label = splitLabel(b.Argument)
			if kind == "h1" {
				chapter++
				section = 0
				b.Number = fmt.Sprint(chapter)
				if index > 0 {
					b.PageBreak = true
				}
			} else {
				section++
				b.Number = fmt.Sprintf("%d.%d", chapter, section)
			}
			t.Headings = append(t.Headings, b)
		case "enum":
			b.EnumNumber = 1
			if previous != nil && previous.Kind == "enum" {
				b.EnumNumber = previous.EnumNumber + 1
			}
			b.Number = fmt.Sprint(b.EnumNumber)
		case "table":
			b.Caption, b.Label = splitLabel(b.Caption)
			if b.Caption != "" {
				tableNumber++
				b.Number = fmt.Sprint(tableNumber)
				t.NumberedTables = append(t.NumberedTables, b)
			}
		}
		if b.Label != "" {
			if t.Labels[b.Label] != nil {
				t.Warn(b.Line, "duplicate label "+b.Label)
				b.Label = ""
			} else {
				t.Labels[b.Label] = b
			}
		}
		if kind == "paragraph" && previous != nil && (previous.Kind == "h1" || previous.Kind == "h2") {
			b.Indent = 0
		}
		if bodyKinds[kind] {
			t.BodyBlocks = append(t.BodyBlocks, b)
			b.ParagraphNumber = len(t.BodyBlocks)
		}
		previous = b
	}
	for _, entry := range t.Document.Bibliography {
		if t.Bibliography[entry.Key] != nil {
			t.Warn(entry.Line, "duplicate bibliography key "+entry.Key)
		} else {
			t.Bibliography[entry.Key] = entry
			t.BibOrder = append(t.BibOrder, entry)
		}
	}
}
func (t *Typesetter) CheckTable(b *Block) {
	count := len(b.Columns)
	for _, line := range b.InnerLines {
		raw := strings.Split(line.Text, "|")
		cells := []string{}
		for _, s := range raw {
			cells = append(cells, strings.Trim(s, " "))
		}
		if len(cells) != count {
			t.Warn(line.Number, fmt.Sprintf("table row has %d cells, expected %d", len(cells), count))
			for len(cells) < count {
				cells = append(cells, "")
			}
			cells = cells[:count]
		}
		b.Rows = append(b.Rows, cells)
	}
	b.TableLines = formatTable(b.Rows, b.Columns, b.Caption, b.Number)
	longest := 0
	for _, line := range b.TableLines {
		longest = max(longest, len(line))
	}
	if excess := longest - b.Width; excess > 0 {
		t.Warn(b.Line, fmt.Sprintf("table too wide by %d", excess))
	}
}
func (t *Typesetter) AcceptCommand(name, argument string, line int) InlineToken {
	token := InlineToken{Kind: name, Argument: argument}
	switch name {
	case "ref", "page":
		if t.Labels[argument] == nil {
			t.Warn(line, "undefined label "+argument)
		}
	case "cite":
		for _, key := range strings.Split(argument, ",") {
			if entry := t.Bibliography[key]; entry != nil {
				entry.Cited = true
			} else {
				t.Warn(line, "undefined citation "+key)
			}
		}
	case "fn":
		t.Footnotes = append(t.Footnotes, argument)
		token.Number = len(t.Footnotes)
	case "idx":
		t.IndexMarks = append(t.IndexMarks, argument)
		token.Number = len(t.IndexMarks)
	}
	return token
}
func (t *Typesetter) ParseBodyLine(text string, line int) []InlineToken {
	tokens := []InlineToken{}
	position := 0
	for position < len(text) {
		relative := strings.IndexByte(text[position:], '{')
		if relative < 0 {
			tokens = append(tokens, InlineToken{Kind: "text", Text: text[position:]})
			break
		}
		opening := position + relative
		if opening > position {
			tokens = append(tokens, InlineToken{Kind: "text", Text: text[position:opening]})
		}
		relative = strings.IndexByte(text[opening+1:], '}')
		if relative < 0 {
			t.Warn(line, "unclosed brace")
			tokens = append(tokens, InlineToken{Kind: "text", Text: text[opening:]})
			break
		}
		closing := opening + 1 + relative
		content := text[opening+1 : closing]
		name, argument, separator := strings.Cut(content, ":")
		if separator && argument != "" && (name == "ref" || name == "page" || name == "fn" || name == "idx" || name == "cite") {
			tokens = append(tokens, t.AcceptCommand(name, argument, line))
		} else {
			t.Warn(line, "bad command {"+content+"}")
		}
		position = closing + 1
	}
	return tokens
}
func (t *Typesetter) CheckDocument() {
	for _, b := range t.Document.Blocks {
		if b.Kind == "table" {
			t.CheckTable(b)
		} else if b.Kind == "verbatim" {
			for _, line := range b.InnerLines {
				if excess := len(line.Text) - b.Width; excess > 0 {
					t.Warn(line.Number, fmt.Sprintf("verbatim line too long by %d", excess))
				}
			}
		} else if bodyKinds[b.Kind] {
			for i, line := range b.BodyLines {
				if i > 0 {
					b.Tokens = append(b.Tokens, InlineToken{Kind: "text", Text: " "})
				}
				b.Tokens = append(b.Tokens, t.ParseBodyLine(line.Text, line.Number)...)
			}
		}
	}
	for _, entry := range t.BibOrder {
		if !entry.Cited {
			t.Warn(entry.Line, "unused bibliography entry "+entry.Key)
		}
	}
}
func (t *Typesetter) AssignBibliographyLabels() {
	for _, entry := range t.BibOrder {
		if !entry.Cited {
			continue
		}
		names := strings.Split(entry.Author, " and ")
		base := ""
		if len(names) == 1 {
			base = names[0][:min(3, len(names[0]))]
		} else {
			count := len(names)
			if count >= 5 {
				count = 3
			}
			for _, name := range names[:count] {
				base += name[:1]
			}
			if len(names) >= 5 {
				base += "+"
			}
		}
		entry.BaseLabel = base + entry.Year[2:]
		t.CitedEntries = append(t.CitedEntries, entry)
	}
	sort.Slice(t.CitedEntries, func(i, j int) bool {
		a, b := t.CitedEntries[i], t.CitedEntries[j]
		if a.BaseLabel != b.BaseLabel {
			return a.BaseLabel < b.BaseLabel
		}
		if a.Author != b.Author {
			return a.Author < b.Author
		}
		if a.Title != b.Title {
			return a.Title < b.Title
		}
		return a.Key < b.Key
	})
	for start := 0; start < len(t.CitedEntries); {
		end := start + 1
		for end < len(t.CitedEntries) && t.CitedEntries[end].BaseLabel == t.CitedEntries[start].BaseLabel {
			end++
		}
		for i := start; i < end; i++ {
			entry := t.CitedEntries[i]
			entry.Label = entry.BaseLabel
			if end-start > 1 {
				entry.Label += string(rune('a' + i - start))
			}
		}
		start = end
	}
}
func (t *Typesetter) PrepareIndex() {
	for i, phrase := range t.IndexMarks {
		entryPart, reference, hasReference := strings.Cut(phrase, "|")
		parentName, childName, hasChild := strings.Cut(entryPart, "!")
		parent := t.IndexEntries[parentName]
		if parent == nil {
			parent = newIndexEntry(parentName)
			t.IndexEntries[parentName] = parent
		}
		entry := parent
		if hasChild {
			entry = parent.Children[childName]
			if entry == nil {
				entry = newIndexEntry(childName)
				parent.Children[childName] = entry
			}
		}
		if hasReference {
			entry.References[reference] = true
		} else {
			entry.Marks = append(entry.Marks, i+1)
		}
	}
}
func (t *Typesetter) CitationText(argument string) string {
	labels := map[string]bool{}
	undefined := false
	for _, key := range strings.Split(argument, ",") {
		if entry := t.Bibliography[key]; entry != nil {
			labels[entry.Label] = true
		} else {
			undefined = true
		}
	}
	parts := []string{}
	for label := range labels {
		parts = append(parts, label)
	}
	sort.Strings(parts)
	if undefined {
		parts = append(parts, "?")
	}
	return "[" + strings.Join(parts, ", ") + "]"
}
func (t *Typesetter) ExpandBody(b *Block, pageValues map[string]string) ([]string, map[int][]WordMark) {
	type OffsetMark struct {
		Offset, Number int
		Kind           string
	}
	parts := []string{}
	marks := []OffsetMark{}
	offset := 0
	for _, token := range b.Tokens {
		text := token.Text
		switch token.Kind {
		case "idx":
			marks = append(marks, OffsetMark{offset - 1, token.Number, "idx"})
			continue
		case "fn":
			marks = append(marks, OffsetMark{offset, token.Number, "fn"})
			text = fmt.Sprintf("[%d]", token.Number)
		case "ref":
			text = "??"
			if target := t.Labels[token.Argument]; target != nil {
				text = target.Number
			}
		case "page":
			text = "??"
			if value, ok := pageValues[token.Argument]; ok {
				text = value
			}
		case "cite":
			text = t.CitationText(token.Argument)
		}
		parts = append(parts, text)
		offset += len(text)
	}
	expanded := strings.Join(parts, "")
	matches := regexp.MustCompile(`[^ ]+`).FindAllStringIndex(expanded, -1)
	words, starts := []string{}, []int{}
	for _, match := range matches {
		starts = append(starts, match[0])
		words = append(words, expanded[match[0]:match[1]])
	}
	wordMarks := map[int][]WordMark{}
	for _, mark := range marks {
		word := sort.Search(len(starts), func(i int) bool { return starts[i] > mark.Offset }) - 1
		wordMarks[word] = append(wordMarks[word], WordMark{mark.Kind, mark.Number, mark.Offset - starts[word]})
	}
	return words, wordMarks
}
func placeMarks(line *TextLine, measured *MeasuredLine, marks map[int][]WordMark) {
	for _, r := range measured.Ranges {
		for _, mark := range marks[r.Word] {
			if r.First <= mark.Position && mark.Position < r.Last {
				if mark.Kind == "fn" {
					line.Footnotes = append(line.Footnotes, mark.Number)
				} else {
					line.Indexes = append(line.Indexes, mark.Number)
				}
			}
		}
	}
}
func (t *Typesetter) LayOutText(words []string, capacities [2]int, alignment string, prefixes [2]string, method string, marks map[int][]WordMark) *TextResult {
	metrics := newTextMetrics(words, capacities[0], capacities[1], t.Dictionary)
	breaking, cost := breakText(metrics, method, t.Params)
	result := &TextResult{Cost: cost}
	start := 0
	for i, end := range breaking {
		measured := metrics.Measure(start, end)
		text := displayLine(measured.Pieces, measured.Slack, alignment, measured.Last)
		prefix := prefixes[1]
		if i == 0 {
			prefix = prefixes[0]
		}
		line := textLine(prefix + text)
		placeMarks(line, measured, marks)
		result.Lines = append(result.Lines, line)
		result.Broken = append(result.Broken, measured)
		start = end
	}
	return result
}
func bodyFormat(b *Block) ([2]int, [2]string) {
	width := b.Width
	switch b.Kind {
	case "paragraph":
		return [2]int{width - b.Indent, width}, [2]string{strings.Repeat(" ", b.Indent), ""}
	case "item":
		return [2]int{width - 2, width - 2}, [2]string{"- ", "  "}
	case "enum":
		return [2]int{width - 4, width - 4}, [2]string{fmt.Sprintf("%2d. ", b.EnumNumber), "    "}
	case "quote":
		return [2]int{width - 8, width - 8}, [2]string{"    ", "    "}
	default:
		first := strings.Repeat(" ", 12)
		if len(b.Term) <= 10 {
			first = b.Term + strings.Repeat(" ", 12-len(b.Term))
		}
		return [2]int{width - 12, width - 12}, [2]string{first, strings.Repeat(" ", 12)}
	}
}
func (t *Typesetter) LayOutBody(b *Block, pages map[string]string, method string) *TextResult {
	words, marks := t.ExpandBody(b, pages)
	capacities, prefixes := bodyFormat(b)
	result := t.LayOutText(words, capacities, b.Align, prefixes, method, marks)
	if b.Kind == "term" && len(b.Term) >= 11 {
		result.Lines = append([]*TextLine{textLine(b.Term)}, result.Lines...)
	}
	return result
}
func (t *Typesetter) LayOutFootnotes(method string) map[int]*TextResult {
	result := map[int]*TextResult{}
	for i, text := range t.Footnotes {
		prefix := fmt.Sprintf("[%d] ", i+1)
		capacity := t.Document.PageWidth - len(prefix)
		result[i+1] = t.LayOutText(wordsIn(text), [2]int{capacity, capacity}, "left", [2]string{prefix, strings.Repeat(" ", len(prefix))}, method, nil)
	}
	return result
}
func (t *Typesetter) LayOutReference(entry *BibEntry, width int, method string) *TextResult {
	margin := 0
	for _, e := range t.CitedEntries {
		margin = max(margin, len(e.Label))
	}
	margin += 3
	text := entry.Author + ". " + entry.Year + ". " + entry.Title
	capacity := width - margin
	prefix := "[" + entry.Label + "]"
	prefix += strings.Repeat(" ", margin-len(prefix))
	return t.LayOutText(wordsIn(text), [2]int{capacity, capacity}, "left", [2]string{prefix, strings.Repeat(" ", margin)}, method, nil)
}
func pageList(numbers []int) string {
	set := map[int]bool{}
	for _, v := range numbers {
		set[v] = true
	}
	numbers = []int{}
	for v := range set {
		numbers = append(numbers, v)
	}
	sort.Ints(numbers)
	parts := []string{}
	for i := 0; i < len(numbers); {
		last := i
		for last+1 < len(numbers) && numbers[last+1] == numbers[last]+1 {
			last++
		}
		if last-i >= 2 {
			parts = append(parts, fmt.Sprintf("%d-%d", numbers[i], numbers[last]))
		} else {
			for _, v := range numbers[i : last+1] {
				parts = append(parts, fmt.Sprint(v))
			}
		}
		i = last + 1
	}
	return strings.Join(parts, ", ")
}
func indexEntryLine(entry *IndexEntry, pages map[int]int, child bool) string {
	text := entry.Name
	if child {
		text = "  " + text
	}
	numbers := []int{}
	for _, number := range entry.Marks {
		if page, ok := pages[number]; ok {
			numbers = append(numbers, page)
		}
	}
	if len(numbers) > 0 {
		text += ", " + pageList(numbers)
	}
	if len(entry.References) > 0 {
		refs := []string{}
		for r := range entry.References {
			refs = append(refs, r)
		}
		sort.Strings(refs)
		text += ", see " + strings.Join(refs, ", ")
	}
	return text
}
func indexNames(entries map[string]*IndexEntry) []string {
	names := []string{}
	for name := range entries {
		names = append(names, name)
	}
	sort.Slice(names, func(i, j int) bool {
		a, b := names[i], names[j]
		la, lb := strings.ToLower(a), strings.ToLower(b)
		if la != lb {
			return la < lb
		}
		return a < b
	})
	return names
}
func (t *Typesetter) IndexLines(pages map[int]int) []string {
	lines := []string{}
	previous := ""
	for _, name := range indexNames(t.IndexEntries) {
		entry := t.IndexEntries[name]
		group := "Symbols"
		if isLetter(name[0]) {
			group = strings.ToUpper(name[:1])
		}
		if group != previous {
			lines = append(lines, group)
			previous = group
		}
		lines = append(lines, indexEntryLine(entry, pages, false))
		for _, child := range indexNames(entry.Children) {
			lines = append(lines, indexEntryLine(entry.Children[child], pages, true))
		}
	}
	return lines
}
func (t *Typesetter) ContentsLines(b *Block, pages map[int]*Page) []string {
	entries := t.NumberedTables
	if b.Kind == "toc" {
		entries = t.Headings
	}
	lines := []string{}
	for _, entry := range entries {
		left := "Table " + entry.Number + ". " + entry.Caption
		if b.Kind == "toc" {
			left = entry.Number + " " + entry.Text
			if entry.Kind == "h2" {
				left = "  " + left
			}
		}
		number := "??"
		if page := pages[entry.ID]; page != nil {
			number = page.Display
		}
		dots := b.Width - len(left) - len(number) - 2
		lines = append(lines, left+" "+strings.Repeat(".", dots)+" "+number)
	}
	return lines
}
func addLayoutBlock(layout *[]*LayoutBlock, source *Block, kind string, lines []*TextLine, list, first bool) {
	if first {
		lines[0].Anchor = source.ID
		lines[0].ChapterStart = source.Kind == "h1"
	}
	*layout = append(*layout, &LayoutBlock{Kind: kind, Lines: lines, List: list, PageBreak: first && source.PageBreak})
}
func textLines(texts []string) []*TextLine {
	lines := []*TextLine{}
	for _, text := range texts {
		lines = append(lines, textLine(text))
	}
	return lines
}
func (t *Typesetter) BuildLayoutBlocks(pageValues map[string]string, method string, result *LayoutResult) []*LayoutBlock {
	layout := []*LayoutBlock{}
	for _, b := range t.Document.Blocks {
		kind := b.Kind
		if bodyKinds[kind] {
			body := t.LayOutBody(b, pageValues, method)
			result.Bodies[b.ID] = body
			result.WarningTexts = append(result.WarningTexts, WarningText{fmt.Sprintf("paragraph %d", b.ParagraphNumber), body, b.Align == "justify"})
			addLayoutBlock(&layout, b, "flow", body.Lines, kind == "item" || kind == "enum" || kind == "term", true)
		} else {
			switch kind {
			case "title", "author":
				text := b.Argument
				if kind == "title" {
					text = strings.ToUpper(text)
				}
				text = strings.Repeat(" ", (b.Width-len(text))/2) + text
				addLayoutBlock(&layout, b, "heading", textLines([]string{text}), false, true)
			case "h1", "h2":
				text := b.Text
				rule := "-"
				if kind == "h1" {
					text = strings.ToUpper(text)
					rule = "="
				}
				text = b.Number + " " + text
				addLayoutBlock(&layout, b, "heading", textLines([]string{text, strings.Repeat(rule, len(text))}), false, true)
			case "table":
				addLayoutBlock(&layout, b, "solid", textLines(b.TableLines), false, true)
			case "verbatim":
				texts := []string{}
				for _, line := range b.InnerLines {
					texts = append(texts, line.Text)
				}
				addLayoutBlock(&layout, b, "flow", textLines(texts), false, true)
			case "toc", "lot", "index":
				title := map[string]string{"toc": "CONTENTS", "lot": "TABLES", "index": "INDEX"}[kind]
				addLayoutBlock(&layout, b, "heading", textLines([]string{title, strings.Repeat("=", len(title))}), false, true)
				var entries []string
				if kind == "index" {
					entries = t.IndexLines(nil)
				} else {
					entries = t.ContentsLines(b, nil)
				}
				lines := textLines(entries)
				addLayoutBlock(&layout, b, "flow", lines, false, false)
				result.Generated = append(result.Generated, GeneratedLines{b, lines})
			case "bibliography":
				addLayoutBlock(&layout, b, "heading", textLines([]string{"REFERENCES", "=========="}), false, true)
				for _, entry := range t.CitedEntries {
					reference := t.LayOutReference(entry, b.Width, method)
					result.WarningTexts = append(result.WarningTexts, WarningText{"reference " + entry.Label, reference, false})
					addLayoutBlock(&layout, b, "flow", reference.Lines, true, false)
				}
			}
		}
	}
	return layout
}
func roman(number int) string {
	units := []string{"", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"}
	return strings.Repeat("x", number/10) + units[number%10]
}
func (t *Typesetter) NumberPages(pages []*Page, result *LayoutResult) {
	numbered := []*Page{}
	for _, page := range pages {
		chapterStart := len(page.Content) > 0 && page.Content[0].ChapterStart
		serial := len(numbered) + 1
		if chapterStart && serial%2 == 0 {
			numbered = append(numbered, &Page{Serial: serial, Blank: true, EndsByForce: true})
			serial++
		}
		page.Serial = serial
		page.ChapterStart = chapterStart
		numbered = append(numbered, page)
	}
	blockPages := map[int]*Page{}
	for _, page := range numbered {
		for _, line := range page.Content {
			if line.Anchor >= 0 {
				blockPages[line.Anchor] = page
			}
		}
	}
	frontMatter := 0
	if len(t.Headings) > 0 {
		frontMatter = blockPages[t.Headings[0].ID].Serial - 1
	}
	markPages := map[int]int{}
	for _, page := range numbered {
		page.BodyNumber = page.Serial - frontMatter
		page.Display = fmt.Sprint(page.BodyNumber)
		if page.Serial <= frontMatter {
			page.Display = roman(page.Serial)
		}
		for _, line := range page.Content {
			for _, mark := range line.Indexes {
				markPages[mark] = page.BodyNumber
			}
		}
	}
	result.Pages = numbered
	result.FrontMatter = frontMatter
	result.BlockPages = blockPages
	result.MarkPages = markPages
	result.LabelValues = map[string]string{}
	for label, b := range t.Labels {
		result.LabelValues[label] = blockPages[b.ID].Display
	}
}
func (t *Typesetter) LayoutOnce(pageValues map[string]string, method string) *LayoutResult {
	footnotes := t.LayOutFootnotes(method)
	result := &LayoutResult{Method: method, Bodies: map[int]*TextResult{}, Footnotes: footnotes}
	layout := t.BuildLayoutBlocks(pageValues, method, result)
	heights := map[int]int{}
	for number, note := range footnotes {
		heights[number] = len(note.Lines)
	}
	pages := choosePages(layout, heights, t.Document.Height, t.Params["orphan_lines"], t.Params["widow_lines"])
	t.NumberPages(pages, result)
	for number := 1; number <= len(t.Footnotes); number++ {
		result.WarningTexts = append(result.WarningTexts, WarningText{fmt.Sprintf("footnote %d", number), footnotes[number], false})
	}
	return result
}
func (t *Typesetter) CompleteGeneratedLines(result *LayoutResult) {
	for _, generated := range result.Generated {
		b := generated.Block
		var texts []string
		if b.Kind == "index" {
			texts = t.IndexLines(result.MarkPages)
		} else {
			texts = t.ContentsLines(b, result.BlockPages)
		}
		for i, text := range texts {
			generated.Lines[i].Text = text
		}
	}
}
func (t *Typesetter) AssemblePages(result *LayoutResult) {
	chapter, section := "", ""
	height := t.Document.Height
	total := len(result.Pages) - result.FrontMatter
	for _, page := range result.Pages {
		if page.Blank {
			page.Body = make([]string, height)
			continue
		}
		for _, line := range page.Content {
			if line.Anchor < 0 {
				continue
			}
			b := t.Document.Blocks[line.Anchor]
			if b.Kind == "h1" {
				chapter = b.Number + " " + b.Text
				section = ""
			} else if b.Kind == "h2" {
				section = b.Number + " " + b.Text
			}
		}
		values := [4]string{page.Display, fmt.Sprint(total), chapter, section}
		if !page.ChapterStart {
			page.Header = runningHead(t.Document.Header, values, t.Document.PageWidth, page.Serial)
		}
		page.Footer = runningHead(t.Document.Footer, values, t.Document.PageWidth, page.Serial)
		content := []string{}
		for _, line := range page.Content {
			content = append(content, line.Text)
		}
		notes := []string{}
		for _, number := range page.Footnotes {
			for _, line := range result.Footnotes[number].Lines {
				notes = append(notes, line.Text)
			}
		}
		if len(notes) > 0 {
			padding := height - len(content) - len(notes) - 1
			content = append(content, make([]string, padding)...)
			content = append(content, "----------")
			content = append(content, notes...)
		} else {
			content = append(content, make([]string, height-len(content))...)
		}
		page.Body = content
	}
}
func sameValues(a, b map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for key, value := range a {
		if other, ok := b[key]; !ok || other != value {
			return false
		}
	}
	return true
}
func (t *Typesetter) Layout(method string) *LayoutResult {
	values := map[string]string{}
	for label := range t.Labels {
		values[label] = "??"
	}
	for {
		result := t.LayoutOnce(values, method)
		if sameValues(result.LabelValues, values) {
			t.CompleteGeneratedLines(result)
			t.AssemblePages(result)
			return result
		}
		values = result.LabelValues
	}
}
func (t *Typesetter) LayoutWarnings(result *LayoutResult) []string {
	warnings := []string{}
	for _, entry := range result.WarningTexts {
		for i, line := range entry.Text.Broken {
			if line.Slack < 0 {
				warnings = append(warnings, fmt.Sprintf("%s line %d: overfull by %d", entry.Name, i+1, -line.Slack))
			} else if entry.Justify && !line.Last && line.Slack >= t.Params["underfull_slack"] {
				warnings = append(warnings, fmt.Sprintf("%s line %d: underfull, slack %d", entry.Name, i+1, line.Slack))
			}
		}
	}
	for _, page := range result.Pages {
		if page.Blank || page.EndsByForce {
			continue
		}
		empty := t.Document.Height - page.Height
		if empty >= t.Params["underfull_page"] {
			warnings = append(warnings, fmt.Sprintf("page %d: underfull, %d empty lines", page.Serial, empty))
		}
	}
	hyphenated := 0
	for _, b := range t.BodyBlocks {
		for _, line := range result.Bodies[b.ID].Broken {
			if line.Midword {
				hyphenated++
			}
		}
	}
	warnings = append(warnings, fmt.Sprintf("%d pages, %d hyphenated lines", len(result.Pages), hyphenated))
	for i, message := range warnings {
		warnings[i] = result.Method + ": " + message
	}
	return warnings
}
func (t *Typesetter) Statistics(optimal, greedy *LayoutResult) string {
	lines := []string{"paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy"}
	totals := [4]int{}
	for _, b := range t.BodyBlocks {
		kp, g := optimal.Bodies[b.ID], greedy.Bodies[b.ID]
		values := [4]int{len(kp.Broken), kp.Cost, len(g.Broken), g.Cost}
		for i, v := range values {
			totals[i] += v
		}
		lines = append(lines, fmt.Sprintf("%d,%d,%d,%d,%d", b.ParagraphNumber, values[0], values[1], values[2], values[3]))
	}
	lines = append(lines, fmt.Sprintf("total,%d,%d,%d,%d", totals[0], totals[1], totals[2], totals[3]))
	return strings.Join(lines, "\n") + "\n"
}
func writeOutput(name, text string) {
	if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
		panic(err)
	}
}
func main() {
	params := map[string]int{}
	for _, line := range readLines("input/params.txt") {
		name, value, _ := strings.Cut(line, " ")
		params[name], _ = strconv.Atoi(value)
	}
	typesetter := newTypesetter(parseDocument(readLines("input/document.txt")), params, readLines("input/hyphenation.txt"))
	optimal, greedy := typesetter.Layout("kp"), typesetter.Layout("greedy")
	warnings := []string{}
	for _, w := range typesetter.Document.Warnings {
		warnings = append(warnings, fmt.Sprintf("line %d: %s", w.Number, w.Message))
	}
	warnings = append(warnings, typesetter.LayoutWarnings(optimal)...)
	warnings = append(warnings, typesetter.LayoutWarnings(greedy)...)
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeOutput("pages.txt", pagesText(optimal.Pages))
	writeOutput("greedy_pages.txt", pagesText(greedy.Pages))
	writeOutput("stats.csv", typesetter.Statistics(optimal, greedy))
	writeOutput("log.txt", strings.Join(warnings, "\n")+"\n")
}
