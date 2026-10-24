package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
)

const punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
const whitespace = " \n"
const tocMarker = "\x00toc\x00"

var htmlEscaper = strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", "\"", "&quot;")
var listPattern = regexp.MustCompile(`^(?:([-*+])|([0-9]{1,9})([.)])) +`)
var footnotePattern = regexp.MustCompile(`^\[\^([A-Za-z0-9_-]+)\]:(.*)$`)
var delimiterPattern = regexp.MustCompile(`^:?-+:?$`)
var labelPattern = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)
var emailPattern = regexp.MustCompile(`^[A-Za-z0-9.+_-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$`)

func escape(text string) string {
	return htmlEscaper.Replace(text)
}

func trim(text string) string {
	return strings.Trim(text, " ")
}

func alphanumeric(c byte) bool {
	return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9'
}

func normalize(text string) string {
	return strings.Join(strings.Fields(strings.ToLower(text)), " ")
}

func skipSpace(text string, at int) int {
	for at < len(text) && strings.ContainsRune(whitespace, rune(text[at])) {
		at++
	}
	return at
}

func escapedRead(text string, at int, stops string) (string, int) {
	var out strings.Builder
	for at < len(text) && !strings.ContainsRune(stops, rune(text[at])) {
		if text[at] == '\\' && at+1 < len(text) && strings.ContainsRune(punctuation, rune(text[at+1])) {
			at++
		}
		out.WriteByte(text[at])
		at++
	}
	return out.String(), at
}

func stripTags(text string) string {
	var out strings.Builder
	for len(text) > 0 {
		start := strings.IndexByte(text, '<')
		if start < 0 {
			out.WriteString(text)
			break
		}
		end := strings.IndexByte(text[start:], '>')
		if end < 0 {
			out.WriteString(text)
			break
		}
		out.WriteString(text[:start])
		text = text[start+end+1:]
	}
	return out.String()
}

func runEnd(text string, at int) int {
	end := at+1
	for end < len(text) && text[end] == text[at] {
		end++
	}
	return end
}

func backtickCloser(text string, at, length int) int {
	for at < len(text) {
		next := strings.IndexByte(text[at:], '`')
		if next < 0 {
			return -1
		}
		at += next
		end := runEnd(text, at)
		if end-at == length {
			return at
		}
		at = end
	}
	return -1
}

func closingBracket(text string, at int) int {
	depth := 0
	for at < len(text) {
		switch text[at] {
		case '\\':
			at += 2
			continue
		case '`':
			end := runEnd(text, at)
			close := backtickCloser(text, end, end-at)
			if close < 0 {
				at = end
			} else {
				at = close+end-at
			}
			continue
		case '[':
			depth++
		case ']':
			depth--
			if depth == 0 {
				return at
			}
		}
		at++
	}
	return -1
}

type reference struct {
	url string
	title *string
}

type block struct {
	kind, text string
	number int
	ordered bool
	lines []string
	children []*block
	items [][]*block
	alignments []string
	rows [][]string
}

type marker struct {
	kind string
	number int
	ordered bool
	content string
}

func openingFence(line string) (string, string, bool) {
	if len(line) == 0 || line[0] != '`' && line[0] != '~' {
		return "", "", false
	}
	end := runEnd(line, 0)
	if end < 3 {
		return "", "", false
	}
	info := trim(line[end:])
	if line[0] == '`' && strings.ContainsRune(info, '`') {
		return "", "", false
	}
	return line[:end], info, true
}

func atxHeading(line string) *block {
	n := 0
	for n < len(line) && line[n] == '#' {
		n++
	}
	if n < 1 || n > 6 || n < len(line) && line[n] != ' ' {
		return nil
	}
	text := trim(line[n:])
	stripped := strings.TrimRight(text, "#")
	if stripped == "" || strings.HasSuffix(stripped, " ") {
		text = trim(stripped)
	}
	return &block{kind: "heading", text: text, number: n}
}

func isRule(line string) bool {
	text := strings.ReplaceAll(line, " ", "")
	return len(text) >= 3 && strings.ContainsRune("-*_", rune(text[0])) && strings.Trim(text, text[:1]) == ""
}

func listMarker(line string) *marker {
	if isRule(line) {
		return nil
	}
	match := listPattern.FindStringSubmatch(line)
	if match == nil {
		return nil
	}
	m := &marker{kind: match[1], number: 1, content: line[len(match[0]): ]}
	if match[2] != "" {
		m.kind = match[3]
		m.ordered = true
		m.number, _ = strconv.Atoi(match[2])
	}
	return m
}

func interrupts(line string) bool {
	if line == "" || line[0] == ' ' {
		return false
	}
	_, _, fence := openingFence(line)
	return fence || atxHeading(line) != nil || isRule(line) || line[0] == '>' || listMarker(line) != nil
}

func splitCells(line string) []string {
	text := trim(line)
	if strings.HasPrefix(text, "|") {
		text = text[1:]
	}
	cells := []string{}
	var cell strings.Builder
	finalSeparator := false
	for at := 0; at < len(text); at++ {
		c := text[at]
		finalSeparator = false
		if c == '\\' && at+1 < len(text) {
			at++
			if text[at] != '|' {
				cell.WriteByte('\\')
			}
			cell.WriteByte(text[at])
		} else if c == '|' {
			cells = append(cells, trim(cell.String()))
			cell.Reset()
			finalSeparator = true
		} else {
			cell.WriteByte(c)
		}
	}
	if !finalSeparator {
		cells = append(cells, trim(cell.String()))
	}
	return cells
}

type parser struct {
	references map[string]reference
	footnotes map[string]string
}

func (p *parser) definition(line string) bool {
	if match := footnotePattern.FindStringSubmatch(line); match != nil && trim(match[2]) != "" {
		name := strings.ToLower(match[1])
		if _, exists := p.footnotes[name]; !exists {
			p.footnotes[name] = trim(match[2])
		}
		return true
	}
	if !strings.HasPrefix(line, "[") {
		return false
	}
	close := strings.IndexByte(line, ']')
	if close < 0 || close+1 >= len(line) || line[close+1] != ':' {
		return false
	}
	label := line[1:close]
	if strings.Contains(label, "[") || trim(label) == "" || strings.HasPrefix(label, "^") {
		return false
	}
	url, end := escapedRead(line, skipSpace(line, close+2), " ")
	if url == "" {
		return false
	}
	at := skipSpace(line, end)
	var title *string
	if at < len(line) {
		if at == end || !strings.ContainsRune("\"'", rune(line[at])) {
			return false
		}
		value, stop := escapedRead(line, at+1, line[at:at+1])
		if stop != len(line)-1 {
			return false
		}
		title = &value
	}
	key := normalize(label)
	if _, exists := p.references[key]; !exists {
		p.references[key] = reference{url, title}
	}
	return true
}

func (p *parser) parse(lines []string) []*block {
	var blocks []*block
	for at := 0; at < len(lines); {
		line := lines[at]
		if line == "" {
			at++
			continue
		}
		if strings.HasPrefix(line, "    ") {
			end := at
			for end < len(lines) && (lines[end] == "" || strings.HasPrefix(lines[end], "    ")) {
				end++
			}
			for lines[end-1] == "" {
				end--
			}
			b := &block{kind: "code"}
			for at < end {
				row := lines[at]
				if row != "" {
					row = row[4:]
				}
				b.lines = append(b.lines, row)
				at++
			}
			blocks = append(blocks, b)
			continue
		}
		if line[0] != ' ' {
			if fence, info, ok := openingFence(line); ok {
				language := strings.SplitN(info, " ", 2)[0]
				b := &block{kind: "code", text: language}
				at++
				for at < len(lines) {
					row := lines[at]
					at++
					if len(row) >= len(fence) && strings.Trim(row, fence[:1]) == "" {
						break
					}
					b.lines = append(b.lines, row)
				}
				blocks = append(blocks, b)
				continue
			}
			if heading := atxHeading(line); heading != nil {
				blocks = append(blocks, heading)
				at++
				continue
			}
			if isRule(line) {
				blocks = append(blocks, &block{kind: "rule"})
				at++
				continue
			}
			if line[0] == '>' {
				var content []string
				for at < len(lines) && strings.HasPrefix(lines[at], ">") {
					row := lines[at][1:]
					if strings.HasPrefix(row, " ") {
						row = row[1:]
					}
					content = append(content, row)
					at++
				}
				b := &block{kind: "quote"}
				for _, kind := range []string{"NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"} {
					if content[0] == "[!"+kind+"]" {
						b.kind = "alert"
						b.text = kind
						content = content[1:]
						break
					}
				}
				b.children = p.parse(content)
				blocks = append(blocks, b)
				continue
			}
			if m := listMarker(line); m != nil {
				b := &block{kind: "list", number: m.number, ordered: m.ordered}
				kind := m.kind
				for {
					content := []string{m.content}
					at++
					for at < len(lines) && strings.HasPrefix(lines[at], "  ") {
						content = append(content, lines[at][2:])
						at++
					}
					b.items = append(b.items, p.parse(content))
					next := at
					for next < len(lines) && lines[next] == "" {
						next++
					}
					if next >= len(lines) {
						break
					}
					m = listMarker(lines[next])
					if m == nil || m.kind != kind || m.ordered != b.ordered {
						break
					}
					at = next
				}
				blocks = append(blocks, b)
				continue
			}
			if p.definition(line) {
				at++
				continue
			}
			if at+1 < len(lines) && strings.Contains(line, "|") && strings.Contains(lines[at+1], "|") {
				header, delimiters := splitCells(line), splitCells(lines[at+1])
				valid := len(header) == len(delimiters)
				for _, cell := range delimiters {
					if !delimiterPattern.MatchString(cell) {
						valid = false
					}
				}
				if valid {
					b := &block{kind: "table", lines: header}
					for _, cell := range delimiters {
						left, right := strings.HasPrefix(cell, ":"), strings.HasSuffix(cell, ":")
						alignment := ""
						if left && right {
							alignment = "center"
						} else if left {
							alignment = "left"
						} else if right {
							alignment = "right"
						}
						b.alignments = append(b.alignments, alignment)
					}
					at += 2
					for at < len(lines) && lines[at] != "" && strings.Contains(lines[at], "|") {
						cells := splitCells(lines[at])
						row := make([]string, len(delimiters))
						copy(row, cells)
						b.rows = append(b.rows, row)
						at++
					}
					blocks = append(blocks, b)
					continue
				}
			}
		}
		text := []string{strings.TrimLeft(line, " ")}
		at++
		level := 0
		for at < len(lines) && lines[at] != "" {
			row := lines[at]
			if len(row) >= 3 && (row[0] == '=' || row[0] == '-') && strings.Trim(row, row[:1]) == "" {
				level = 2
				if row[0] == '=' {
					level = 1
				}
				at++
				break
			}
			if interrupts(row) {
				break
			}
			text = append(text, strings.TrimLeft(row, " "))
			at++
		}
		b := &block{kind: "paragraph", text: strings.Join(text, "\n"), number: level}
		if level != 0 {
			b.kind = "heading"
		} else if b.text == "[TOC]" {
			b.kind = "toc"
		}
		blocks = append(blocks, b)
	}
	return blocks
}

type piece struct {
	html string
	delimiter byte
	length int
	open, close bool
}

func emphasis(pieces []piece) string {
	var out strings.Builder
	for at := 0; at < len(pieces); at++ {
		p := pieces[at]
		if p.delimiter == 0 {
			out.WriteString(p.html)
			continue
		}
		end := len(pieces)
		if p.open {
			for next := at+1; next < len(pieces); next++ {
				q := pieces[next]
				if q.delimiter == p.delimiter && q.length == p.length && q.close {
					end = next
					break
				}
			}
		}
		if end == len(pieces) {
			out.WriteString(strings.Repeat(string(p.delimiter), p.length))
			continue
		}
		opening, closing := "<del>", "</del>"
		if p.delimiter != '~' {
			switch p.length {
			case 1:
				opening, closing = "<em>", "</em>"
			case 2:
				opening, closing = "<strong>", "</strong>"
			case 3:
				opening, closing = "<em><strong>", "</strong></em>"
			}
		}
		out.WriteString(opening)
		out.WriteString(emphasis(pieces[at+1:end]))
		out.WriteString(closing)
		at = end
	}
	return out.String()
}

type headingEntry struct {
	level int
	id, label string
	children []*headingEntry
}

type renderer struct {
	references map[string]reference
	footnotes map[string]string
	usedIDs map[string]bool
	headings []*headingEntry
	footnoteNumbers map[string]int
	footnoteNames []string
	footnoteCounts []int
}

func (r *renderer) destination(text string, at int, label string) (reference, int, bool) {
	if at < len(text) && text[at] == '[' {
		relative := strings.IndexByte(text[at+1:], ']')
		if relative >= 0 {
			close := at+1+relative
			key := text[at+1:close]
			if !strings.Contains(key, "[") {
				if key == "" {
					key = label
				}
				ref, found := r.references[normalize(key)]
				return ref, close+1, found
			}
		}
	} else if at < len(text) && text[at] == '(' {
		url, end := escapedRead(text, skipSpace(text, at+1), " \n)")
		next := skipSpace(text, end)
		var title *string
		valid := true
		if next > end && next < len(text) && strings.ContainsRune("\"'", rune(text[next])) {
			value, stop := escapedRead(text, next+1, text[next:next+1])
			if stop == len(text) {
				valid = false
			} else {
				title = &value
				next = skipSpace(text, stop+1)
			}
		}
		if valid && next < len(text) && text[next] == ')' {
			return reference{url, title}, next+1, true
		}
	}
	ref, found := r.references[normalize(label)]
	return ref, at, found
}

func referenceID(number, count int) string {
	id := "fnref-"+strconv.Itoa(number)
	if count > 1 {
		id += "-"+strconv.Itoa(count)
	}
	return id
}

func (r *renderer) footnoteReference(name string) string {
	number, exists := r.footnoteNumbers[name]
	if !exists {
		number = len(r.footnoteNames)+1
		r.footnoteNumbers[name] = number
		r.footnoteNames = append(r.footnoteNames, name)
		r.footnoteCounts = append(r.footnoteCounts, 0)
	}
	r.footnoteCounts[number-1]++
	id := referenceID(number, r.footnoteCounts[number-1])
	value := strconv.Itoa(number)
	return `<sup id="`+id+`"><a href="#fn-`+value+`">`+value+`</a></sup>`
}

func (r *renderer) inline(text string, links, notes bool) string {
	var pieces []piece
	for at := 0; at < len(text); {
		ch := text[at]
		if ch == '\\' {
			if at+1 < len(text) && strings.ContainsRune(punctuation, rune(text[at+1])) {
				pieces = append(pieces, piece{html: escape(text[at+1: at+2])})
				at += 2
			} else if at+1 < len(text) && text[at+1] == '\n' {
				pieces = append(pieces, piece{html: "<br />\n"})
				at += 2
			} else {
				pieces = append(pieces, piece{html: "\\"})
				at++
			}
			continue
		}
		if ch == '`' {
			end := runEnd(text, at)
			close := backtickCloser(text, end, end-at)
			if close < 0 {
				pieces = append(pieces, piece{html: text[at: end]})
				at = end
			} else {
				code := strings.ReplaceAll(text[end:close], "\n", " ")
				if strings.HasPrefix(code, " ") && strings.HasSuffix(code, " ") && strings.Trim(code, " ") != "" {
					code = code[1:len(code)-1]
				}
				pieces = append(pieces, piece{html: "<code>"+escape(code)+"</code>"})
				at = close+end-at
			}
			continue
		}
		if links && ch == '<' {
			if offset := strings.IndexByte(text[at+1:], '>'); offset >= 0 {
				close := at+1+offset
				target := text[at+1:close]
				href := ""
				if !strings.ContainsAny(target, " \n<") && (strings.HasPrefix(target, "http://") && len(target)>7 || strings.HasPrefix(target, "https://") && len(target)>8) {
					href = target
				} else if emailPattern.MatchString(target) {
					href = "mailto:"+target
				}
				if href != "" {
					pieces = append(pieces, piece{html: `<a href="`+escape(href)+`">`+escape(target)+`</a>`})
					at = close+1
					continue
				}
			}
		}
		if links && (strings.HasPrefix(text[at:], "http://") || strings.HasPrefix(text[at:], "https://")) && (at == 0 || strings.ContainsRune(" \n*_~(", rune(text[at-1]))) {
			end := at
			for end < len(text) && !strings.ContainsRune(" \n<", rune(text[end])) {
				end++
			}
			for end > at && strings.ContainsRune(".,:;!?*_~)", rune(text[end-1])) {
				end--
			}
			url := text[at:end]
			if url != "http://" && url != "https://" {
				value := escape(url)
				pieces = append(pieces, piece{html: `<a href="`+value+`">`+value+`</a>`})
				at = end
				continue
			}
		}
		if ch == '[' || ch == '!' && at+1 < len(text) && text[at+1] == '[' {
			if links && notes && strings.HasPrefix(text[at:], "[^") {
				if offset := strings.IndexByte(text[at+2:], ']'); offset >= 0 {
					close := at+2+offset
					name := strings.ToLower(text[at+2:close])
					if _, found := r.footnotes[name]; found {
						pieces = append(pieces, piece{html: r.footnoteReference(name)})
						at = close+1
						continue
					}
				}
			}
			image := ch == '!'
			opening := at
			if image {
				opening++
			}
			close := closingBracket(text, opening)
			if (image || links) && close >= 0 {
				label := text[opening+1:close]
				if ref, end, ok := r.destination(text, close+1, label); ok {
					content := r.inline(label, false, false)
					title := ""
					if ref.title != nil {
						title = ` title="`+escape(*ref.title)+`"`
					}
					var html string
					if image {
						html = `<img src="`+escape(ref.url)+`" alt="`+stripTags(content)+`"`+title+` />`
					} else {
						html = `<a href="`+escape(ref.url)+`"`+title+`>`+content+`</a>`
					}
					pieces = append(pieces, piece{html: html})
					at = end
					continue
				}
			}
			pieces = append(pieces, piece{html: string(ch)})
			at++
			continue
		}
		if strings.ContainsRune("*_~", rune(ch)) {
			end := runEnd(text, at)
			length := end-at
			before, after := byte(' '), byte(' ')
			if at > 0 {
				before = text[at-1]
			}
			if end < len(text) {
				after = text[end]
			}
			open, close := !strings.ContainsRune(whitespace, rune(after)), !strings.ContainsRune(whitespace, rune(before))
			if ch == '_' && alphanumeric(before) && alphanumeric(after) {
				open, close = false, false
			}
			if ch != '~' && length <= 3 || ch == '~' && length == 2 {
				pieces = append(pieces, piece{delimiter: ch, length: length, open: open, close: close})
			} else {
				pieces = append(pieces, piece{html: text[at: end]})
			}
			at = end
			continue
		}
		pieces = append(pieces, piece{html: escape(text[at: at+1])})
		at++
	}
	return emphasis(pieces)
}

func (r *renderer) blocks(blocks []*block) string {
	var out strings.Builder
	for _, b := range blocks {
		out.WriteString(r.render(b))
		out.WriteByte('\n')
	}
	return out.String()
}

func (r *renderer) heading(level int, text string) string {
	id := ""
	start := strings.LastIndex(text, " {#")
	if strings.HasSuffix(text, "}") && start >= 0 && labelPattern.MatchString(text[start+3:len(text)-1]) {
		id = text[start+3:len(text)-1]
		text = strings.TrimRight(text[:start], " ")
	}
	if id == "" {
		var slug strings.Builder
		for _, c := range strings.ToLower(text) {
			if c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '_' {
				slug.WriteRune(c)
			} else if c == ' ' || c == '\n' {
				slug.WriteByte('-')
			}
		}
		base := slug.String()
		if base == "" {
			base = "heading"
		}
		id = base
		for suffix := 1; r.usedIDs[id]; suffix++ {
			id = base+"-"+strconv.Itoa(suffix)
		}
	}
	r.usedIDs[id] = true
	html := r.inline(text, true, true)
	r.headings = append(r.headings, &headingEntry{level: level, id: id, label: stripTags(html)})
	n := strconv.Itoa(level)
	return `<h`+n+` id="`+id+`">`+html+`</h`+n+`>`
}

func (r *renderer) item(blocks []*block) string {
	var out strings.Builder
	out.WriteString("<li>")
	newline := false
	for index, b := range blocks {
		if b.kind == "paragraph" {
			text := b.text
			if index == 0 && len(text)>4 && (strings.HasPrefix(text, "[ ] ") || strings.HasPrefix(text, "[x] ") || strings.HasPrefix(text, "[X] ")) {
				if text[1] == ' ' {
					out.WriteString(`<input type="checkbox" disabled="" /> `)
				} else {
					out.WriteString(`<input type="checkbox" checked="" disabled="" /> `)
				}
				text = text[4:]
			}
			html := r.inline(text, true, true)
			out.WriteString(html)
			if html != "" {
				newline = strings.HasSuffix(html, "\n")
			}
		} else {
			if !newline {
				out.WriteByte('\n')
			}
			out.WriteString(r.render(b))
			out.WriteByte('\n')
			newline = true
		}
	}
	out.WriteString("</li>")
	return out.String()
}

func (r *renderer) tableCells(tag string, b *block, cells []string) string {
	var out strings.Builder
	for index, cell := range cells {
		out.WriteString("<"+tag)
		if b.alignments[index] != "" {
			out.WriteString(` style="text-align:`+b.alignments[index]+`"`)
		}
		out.WriteString(">"+r.inline(cell, true, true)+"</"+tag+">\n")
	}
	return out.String()
}

func (r *renderer) render(b *block) string {
	switch b.kind {
	case "heading":
		return r.heading(b.number, b.text)
	case "paragraph":
		return "<p>"+r.inline(b.text, true, true)+"</p>"
	case "rule":
		return "<hr />"
	case "code":
		var out strings.Builder
		out.WriteString("<pre><code")
		if b.text != "" {
			out.WriteString(` class="language-`+escape(b.text)+`"`)
		}
		out.WriteByte('>')
		for _, line := range b.lines {
			out.WriteString(escape(line))
			out.WriteByte('\n')
		}
		out.WriteString("</code></pre>")
		return out.String()
	case "quote":
		return "<blockquote>\n"+r.blocks(b.children)+"</blockquote>"
	case "alert":
		kind := strings.ToLower(b.text)
		title := strings.ToUpper(kind[:1])+kind[1:]
		return `<div class="alert alert-`+kind+`">`+"\n"+`<p class="alert-title">`+title+"</p>\n"+r.blocks(b.children)+"</div>"
	case "list":
		tag := "ul"
		if b.ordered {
			tag = "ol"
		}
		var out strings.Builder
		out.WriteString("<"+tag)
		if b.ordered && b.number != 1 {
			out.WriteString(` start="`+strconv.Itoa(b.number)+`"`)
		}
		out.WriteString(">\n")
		for _, item := range b.items {
			out.WriteString(r.item(item))
			out.WriteByte('\n')
		}
		out.WriteString("</"+tag+">")
		return out.String()
	case "table":
		var out strings.Builder
		out.WriteString("<table>\n<thead>\n<tr>\n"+r.tableCells("th", b, b.lines)+"</tr>\n</thead>\n")
		if len(b.rows)>0 {
			out.WriteString("<tbody>\n")
			for _, row := range b.rows {
				out.WriteString("<tr>\n"+r.tableCells("td", b, row)+"</tr>\n")
			}
			out.WriteString("</tbody>\n")
		}
		out.WriteString("</table>")
		return out.String()
	case "toc":
		return tocMarker
	}
	panic("unknown block")
}

func tocList(entries []*headingEntry) string {
	var out strings.Builder
	out.WriteString("<ul>\n")
	for _, h := range entries {
		out.WriteString(`<li><a href="#`+h.id+`">`+h.label+`</a>`)
		if len(h.children)>0 {
			out.WriteByte('\n')
			out.WriteString(tocList(h.children))
			out.WriteByte('\n')
		}
		out.WriteString("</li>\n")
	}
	out.WriteString("</ul>")
	return out.String()
}

func (r *renderer) toc() string {
	if len(r.headings)==0 {
		return "<nav class=\"toc\">\n</nav>"
	}
	var roots, parents []*headingEntry
	for _, h := range r.headings {
		for len(parents)>0 && parents[len(parents)-1].level >= h.level {
			parents = parents[:len(parents)-1]
		}
		if len(parents)==0 {
			roots = append(roots, h)
		} else {
			parent := parents[len(parents)-1]
			parent.children = append(parent.children, h)
		}
		parents = append(parents, h)
	}
	return "<nav class=\"toc\">\n"+tocList(roots)+"\n</nav>"
}

func (r *renderer) footnoteList() string {
	var out strings.Builder
	out.WriteString("<section class=\"footnotes\">\n<ol>\n")
	for index, name := range r.footnoteNames {
		out.WriteString(`<li id="fn-`+strconv.Itoa(index+1)+`">`+r.inline(r.footnotes[name], true, false))
		for count := 1; count <= r.footnoteCounts[index]; count++ {
			out.WriteString(` <a href="#`+referenceID(index+1, count)+`">&#8617;</a>`)
		}
		out.WriteString("</li>\n")
	}
	out.WriteString("</ol>\n</section>\n")
	return out.String()
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 4096)
	var lines []string
	for scanner.Scan() {
		line := scanner.Text()
		if line == "@@END@@" {
			break
		}
		lines = append(lines, line)
	}
	if err := scanner.Err(); err != nil {
		panic(err)
	}
	p := &parser{references: make(map[string]reference), footnotes: make(map[string]string)}
	blocks := p.parse(lines)
	r := &renderer{references: p.references, footnotes: p.footnotes, usedIDs: make(map[string]bool), footnoteNumbers: make(map[string]int)}
	html := r.blocks(blocks)
	html = strings.ReplaceAll(html, tocMarker, r.toc())
	if len(r.footnoteNames)>0 {
		html += r.footnoteList()
	}
	fmt.Print(html)
}
