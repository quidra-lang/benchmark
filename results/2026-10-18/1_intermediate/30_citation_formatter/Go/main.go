package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var fieldOrder = []string{
	"author", "editor", "title", "journal", "booktitle", "edition", "volume", "number", "pages",
	"publisher", "institution", "school", "address", "howpublished", "month", "year", "doi", "note",
}
var typeNames = []string{"article", "book", "inproceedings", "incollection", "techreport", "phdthesis", "misc"}
var required = [][]string{
	{"author", "title", "journal", "year"}, {"author", "title", "publisher", "year"},
	{"author", "title", "booktitle", "year"}, {"author", "title", "booktitle", "publisher", "year"},
	{"author", "title", "institution", "year"}, {"author", "title", "school", "year"}, {"author", "title", "year"},
}
var months = []string{"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
var monthMacros = []string{"jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"}
var monthShort = []string{"Jan.", "Feb.", "Mar.", "Apr.", "May", "June", "July", "Aug.", "Sep.", "Oct.", "Nov.", "Dec."}
var smallWords = strings.Fields("a an and as at but by for from in into nor of on or over per so the to up via with yet")

func indexOf(values []string, value string) int {
	for i, item := range values {
		if item == value { return i }
	}
	return -1
}
func lower(c byte) bool { return c >= 'a' && c <= 'z' }
func upper(c byte) bool { return c >= 'A' && c <= 'Z' }
func letter(c byte) bool { return lower(c) || upper(c) }
func digit(c byte) bool { return c >= '0' && c <= '9' }
func lowercase(c byte) byte {
	if upper(c) { return c + 'a' - 'A' }
	return c
}
func uppercase(c byte) byte {
	if lower(c) { return c + 'A' - 'a' }
	return c
}
func plain(text string) string { return strings.NewReplacer("{", "", "}", "").Replace(text) }
func letters(text string) string {
	var result strings.Builder
	for i := range len(text) { if letter(text[i]) { result.WriteByte(lowercase(text[i])) } }
	return result.String()
}
func allDigits(text string) bool {
	if text == "" { return false }
	for i := range len(text) { if !digit(text[i]) { return false } }
	return true
}
func splitDepth(text, separator string) []string {
	var result []string
	start, i, depth := 0, 0, 0
	for i < len(text) {
		if depth == 0 && strings.HasPrefix(text[i:], separator) {
			result = append(result, text[start:i]); i += len(separator); start = i
		} else {
			if text[i] == '{' { depth++ }
			if text[i] == '}' { depth-- }
			i++
		}
	}
	return append(result, text[start:])
}
func evaluate(expression string, macros map[string]string) (string, error) {
	depth := 0
	for i := range len(expression) {
		if expression[i] == '{' { depth++ }
		if expression[i] == '}' { depth-- }
		if depth < 0 { return "", fmt.Errorf("unbalanced braces") }
	}
	if depth != 0 { return "", fmt.Errorf("unbalanced braces") }
	var result strings.Builder
	for _, term := range strings.Split(expression, " # ") {
		if term[0] == '{' || term[0] == '"' { result.WriteString(term[1:len(term)-1])
		} else if digit(term[0]) { result.WriteString(term)
		} else if value, ok := macros[term]; ok { result.WriteString(value)
		} else { return "", fmt.Errorf("unknown macro '%s'", term) }
	}
	return result.String(), nil
}
func accent(text string, at int) (byte, int) {
	if at+1 >= len(text) || text[at] != '\\' { return 0, 0 }
	command := text[at+1]
	if command == '&' { return '&', 2 }
	symbol := strings.ContainsRune("'\"`^~=.", rune(command))
	if symbol && at+2 < len(text) && letter(text[at+2]) { return text[at+2], 3 }
	if (symbol || strings.ContainsRune("cuvH", rune(command))) && at+4 < len(text) && text[at+2] == '{' && letter(text[at+3]) && text[at+4] == '}' { return text[at+3], 5 }
	return 0, 0
}
func normalize(value string) string {
	var result strings.Builder
	for i := 0; i < len(value); {
		if value[i] == '{' {
			c, width := accent(value, i+1)
			if width > 0 && i+width+1 < len(value) && value[i+width+1] == '}' { result.WriteByte(c); i += width+2; continue }
		}
		if c, width := accent(value, i); width > 0 { result.WriteByte(c); i += width
		} else { result.WriteByte(value[i]); i++ }
	}
	return strings.Join(strings.Fields(strings.ReplaceAll(result.String(), "~", " ")), " ")
}

type Name struct { First, Von, Last, Jr string }
type NameList struct { Names []Name; EtAl bool }

func parseName(text string) Name {
	parts := splitDepth(text, ",")
	for i := range parts { parts[i] = strings.Trim(parts[i], " ") }
	words := splitDepth(parts[0], " ")
	firstLower, lastLower := -1, -1
	for i := 0; i+1 < len(words); i++ {
		if lower(words[i][0]) {
			if firstLower < 0 { firstLower = i }
			lastLower = i
		}
	}
	var name Name
	if len(parts) == 1 {
		if firstLower < 0 { name.First = strings.Join(words[:len(words)-1], " "); name.Last = words[len(words)-1]
		} else { name.First = strings.Join(words[:firstLower], " "); name.Von = strings.Join(words[firstLower:lastLower+1], " "); name.Last = strings.Join(words[lastLower+1:], " ") }
	} else {
		if lastLower < 0 { name.Last = strings.Join(words, " ")
		} else { name.Von = strings.Join(words[:lastLower+1], " "); name.Last = strings.Join(words[lastLower+1:], " ") }
		name.First = parts[len(parts)-1]
		if len(parts) == 3 { name.Jr = parts[1] }
	}
	return name
}
func parseNames(text string) *NameList {
	result := &NameList{}
	for _, name := range splitDepth(text, " and ") {
		if name == "others" { result.EtAl = true } else { result.Names = append(result.Names, parseName(name)) }
	}
	return result
}
func (a *NameList) Equal(b *NameList) bool {
	if len(a.Names) != len(b.Names) || a.EtAl != b.EtAl { return false }
	for i := range a.Names { if a.Names[i] != b.Names[i] { return false } }
	return true
}
func (a *NameList) Single() bool { return len(a.Names) == 1 && !a.EtAl }
func (name Name) Surname() string {
	if name.Von == "" { return plain(name.Last) }
	return plain(name.Von + " " + name.Last)
}
func (name Name) Initials() string {
	var words []string
	for _, word := range strings.Fields(plain(name.First)) {
		var initials []string
		for _, piece := range strings.Split(word, "-") {
			for i := range len(piece) { if letter(piece[i]) { initials = append(initials, string(uppercase(piece[i]))+"."); break } }
		}
		words = append(words, strings.Join(initials, "-"))
	}
	return strings.Join(words, " ")
}
func (name Name) Text(inverted, abbreviated bool) string {
	given, result := plain(name.First), name.Surname()
	if abbreviated { given = name.Initials() }
	if name.First != "" {
		if inverted { result += ", " + given } else { result = given + " " + result }
	}
	if name.Jr != "" { result += ", " + plain(name.Jr) }
	return result
}

type Style int
const (
	APA Style = iota
	IEEE
	Chicago
	MLA
)
func titleCase(title string, style Style) string {
	if style == IEEE { return title }
	if style == APA {
		result, depth := []byte(title), 0
		for i, c := range result {
			switch {
			case c == '{': depth++
			case c == '}': depth--
			case depth == 0 && letter(c):
				if i == 0 || i >= 2 && title[i-2:i] == ": " { result[i] = uppercase(c) } else { result[i] = lowercase(c) }
			}
		}
		return string(result)
	}
	words := splitDepth(title, " ")
	for i, word := range words {
		if word[0] == '{' { continue }
		makeLower := i > 0 && i+1 < len(words) && !strings.HasSuffix(words[i-1], ":") && indexOf(smallWords, letters(word)) >= 0
		result, depth, firstLetter := []byte(word), 0, true
		for j, c := range result {
			switch {
			case c == '{': depth++
			case c == '}': depth--
			case letter(c):
				if depth == 0 && makeLower { result[j] = lowercase(c) } else if depth == 0 && firstLetter { result[j] = uppercase(c) }
				firstLetter = false
			}
		}
		words[i] = string(result)
	}
	return strings.Join(words, " ")
}
func listed(names []string, conjunction string, listB bool) string {
	if len(names) == 1 { return names[0] }
	if listB && len(names) == 2 { return names[0]+" "+conjunction+" "+names[1] }
	return strings.Join(names[:len(names)-1], ", ")+", "+conjunction+" "+names[len(names)-1]
}
func renderNames(list *NameList, style Style, editor bool) string {
	names := make([]string, len(list.Names))
	for i, name := range list.Names { names[i] = name.Text(!editor && (style == APA || style != IEEE && i == 0), style == APA || style == IEEE) }
	if editor {
		if list.EtAl { return names[0]+" et al." }
		conjunction := "and"
		if style == APA { conjunction = "&" }
		return listed(names, conjunction, true)
	}
	switch style {
	case APA:
		if list.EtAl { return strings.Join(names, ", ")+", et al." }
		if len(names) >= 21 { return strings.Join(names[:19], ", ")+", . . . "+names[len(names)-1] }
		return listed(names, "&", false)
	case IEEE:
		if list.EtAl || len(names) >= 7 { return names[0]+" et al." }
		return listed(names, "and", true)
	case Chicago:
		if list.EtAl || len(names) >= 11 { return strings.Join(names[:min(len(names), 7)], ", ")+", et al." }
		return listed(names, "and", false)
	default:
		if list.EtAl || len(names) >= 3 { return names[0]+", et al." }
		return listed(names, "and", false)
	}
}

type Entry struct {
	Key string
	Kind int
	Fields map[string]string
	Authors, Editors *NameList
	Suffix string
	SortLast, Year, SortTitle, PlainTitle, LowerTitle, BaseKey string
}
func (entry *Entry) Primary() *NameList {
	if entry.Authors != nil { return entry.Authors }
	return entry.Editors
}
func newEntry(key string, kind int, fields map[string]string) *Entry {
	entry := &Entry{Key: key, Kind: kind, Fields: fields}
	if value, ok := fields["author"]; ok { entry.Authors = parseNames(value) }
	if value, ok := fields["editor"]; ok { entry.Editors = parseNames(value) }
	lead := entry.Primary().Names[0]
	entry.SortLast = strings.ToLower(plain(lead.Last))
	entry.Year = plain(fields["year"])
	entry.PlainTitle = plain(fields["title"])
	entry.LowerTitle = strings.ToLower(entry.PlainTitle)
	entry.SortTitle = entry.LowerTitle
	for _, prefix := range []string{"a ", "an ", "the "} {
		if strings.HasPrefix(entry.SortTitle, prefix) { entry.SortTitle = strings.TrimPrefix(entry.SortTitle, prefix); break }
	}
	var base strings.Builder
	base.WriteString(letters(plain(lead.Last)))
	for _, c := range fields["year"] { if c >= '0' && c <= '9' { base.WriteRune(c) } }
	for _, word := range strings.Split(entry.PlainTitle, " ") {
		word = letters(word)
		if word != "" && indexOf(smallWords, word) < 0 { base.WriteString(word); break }
	}
	entry.BaseKey = base.String()
	return entry
}
func bibliographyLess(a, b *Entry) bool {
	if a.SortLast != b.SortLast { return a.SortLast < b.SortLast }
	if a.Year != b.Year { return a.Year < b.Year }
	if a.SortTitle != b.SortTitle { return a.SortTitle < b.SortTitle }
	return a.Key < b.Key
}
func (entry *Entry) YearLabel(style Style) string {
	if style == APA || style == Chicago { return entry.Year + entry.Suffix }
	return entry.Year
}
func (entry *Entry) ShortName(style Style, parenthetical bool) string {
	list, limit := entry.Primary(), 3
	if style == Chicago { limit = 4 }
	if list.EtAl || len(list.Names) >= limit { return list.Names[0].Surname()+" et al." }
	names := make([]string, len(list.Names))
	for i, name := range list.Names { names[i] = name.Surname() }
	conjunction := "and"
	if style == APA && parenthetical { conjunction = "&" }
	return listed(names, conjunction, true)
}
func (entry *Entry) UnknownFields() []string {
	var names []string
	for name := range entry.Fields { if indexOf(fieldOrder, name) < 0 { names = append(names, name) } }
	sort.Strings(names)
	return names
}

var templates = [4][6]string{
	{
		"{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
		"{author}. ({year}). {title}< ({edition})>. {publisher}.",
		"{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
		"{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
		"{author}. ({year}). {title} [Doctoral dissertation, {school}].",
		"{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>",
	}, {
		"{author}, \"{title},\" {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.",
		"{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
		"{author}, \"{title},\" in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.",
		"{author}, \"{title},\" {institution}<, {address}>, Tech. Rep.< {number}>, {year}.",
		"{author}, \"{title},\" Ph.D. dissertation, {school}<, {address}>, {year}.",
		"{author}, \"{title},\"< {howpublished},> <{mon} >{year}.< {note}.>",
	}, {
		"{author}. {year}. \"{title}.\" {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>",
		"{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
		"{author}. {year}. \"{title}.\" In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>",
		"{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
		"{author}. {year}. \"{title}.\" PhD diss., {school}.",
		"{author}. {year}. {title}.< {howpublished}.>< {note}.>",
	}, {
		"{author}. \"{title}.\" {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>",
		"{author}. {title}.< {edition},> {publisher}, {year}.",
		"{author}. \"{title}.\" {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.",
		"{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
		"{author}. {title}. {year}. {school}, PhD dissertation.",
		"{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>",
	},
}
func optionalEnd(pattern string, start int) int {
	depth := 1
	for i := start+1; ; i++ {
		if pattern[i] == '<' { depth++ }
		if pattern[i] == '>' { depth-- }
		if depth == 0 { return i }
	}
}
func optionalPresent(pattern string, start, end int, values map[string]string) bool {
	for i := start; i < end; i++ {
		if pattern[i] == '<' { i = optionalEnd(pattern, i)
		} else if pattern[i] == '{' {
			close := i+strings.IndexByte(pattern[i:], '}')
			if values[pattern[i+1:close]] == "" { return false }
			i = close
		}
	}
	return true
}
func renderTemplate(pattern string, start, end int, values map[string]string, result *strings.Builder) {
	for i := start; i < end; i++ {
		switch pattern[i] {
		case '<':
			close := optionalEnd(pattern, i)
			if optionalPresent(pattern, i+1, close, values) { renderTemplate(pattern, i+1, close, values, result) }
			i = close
		case '{':
			close := i+strings.IndexByte(pattern[i:], '}')
			result.WriteString(values[pattern[i+1:close]]); i = close
		default:
			if pattern[i] != '.' || result.Len() == 0 || !strings.ContainsRune(".?!", rune(result.String()[result.Len()-1])) { result.WriteByte(pattern[i]) }
		}
	}
}
func (entry *Entry) Reference(style Style, number int, repeated bool) string {
	values := make(map[string]string)
	for _, name := range fieldOrder { values[name] = plain(entry.Fields[name]) }
	list := entry.Primary()
	if repeated { values["author"] = "---" } else { values["author"] = renderNames(list, style, false) }
	if entry.Authors == nil {
		annotations := [4][2]string{{" (Ed.)", " (Eds.)"}, {", Ed.", ", Eds."}, {", ed.", ", eds."}, {", editor", ", editors"}}
		index := 1
		if list.Single() { index = 0 }
		values["author"] += annotations[style][index]
	}
	if entry.Editors != nil {
		values["editor"] = renderNames(entry.Editors, style, true)
		values["eds"] = "Eds."
		if entry.Editors.Single() { values["eds"] = "Ed." }
	}
	values["title"] = plain(titleCase(entry.Fields["title"], style))
	values["year"] = entry.YearLabel(style)
	if pages, ok := entry.Fields["pages"]; ok {
		values["pages"] = strings.ReplaceAll(plain(pages), "--", "-")
		prefix := "p. "
		if strings.Contains(values["pages"], "-") { prefix = "pp. " }
		values["pp"] = prefix+values["pages"]
	}
	if edition, ok := entry.Fields["edition"]; ok {
		value := plain(edition)
		if allDigits(value) {
			n, _ := strconv.Atoi(value)
			suffix := "th"
			if n%100 < 11 || n%100 > 13 {
				switch n%10 { case 1: suffix = "st"; case 2: suffix = "nd"; case 3: suffix = "rd" }
			}
			value = fmt.Sprintf("%d%s", n, suffix)
		}
		values["edition"] = value+" ed."
	}
	if month, ok := entry.Fields["month"]; ok {
		value := plain(month)
		if i := indexOf(months, value); i >= 0 { value = monthShort[i] }
		values["mon"] = value
	}
	kind := entry.Kind
	if kind == 3 { kind = 2 } else if kind > 3 { kind-- }
	pattern := templates[style][kind]
	var result strings.Builder
	if style == IEEE { fmt.Fprintf(&result, "[%d] ", number) }
	renderTemplate(pattern, 0, len(pattern), values, &result)
	return result.String()
}

type Database struct {
	Entries []*Entry
	Lookup map[string]*Entry
	Record []*Entry
	Output []string
}
type LoadError struct { Line int; Reason string }
func readDatabase(lines []string) *Database {
	database := &Database{Lookup: make(map[string]*Entry)}
	macros := make(map[string]string)
	for i, name := range monthMacros { macros[name] = months[i] }
	macroCount, errors := 0, 0
	for i := 0; i < len(lines); {
		line := lines[i]
		if line == "" || line[0] == '%' { i++; continue }
		if strings.HasPrefix(line, "@string{") {
			name, expression, _ := strings.Cut(line[8:len(line)-1], " = ")
			value, err := evaluate(expression, macros)
			if _, exists := macros[name]; err == nil && exists { err = fmt.Errorf("duplicate macro") }
			if err != nil { database.Output = append(database.Output, fmt.Sprintf("ERROR line %d: %s: %s", i+1, name, err)); errors++
			} else { macros[name] = value; macroCount++ }
			i++; continue
		}
		kindName, key, _ := strings.Cut(line[1:len(line)-1], "{")
		kind := indexOf(typeNames, kindName)
		var loadError *LoadError
		if kind < 0 { loadError = &LoadError{i+1, fmt.Sprintf("unknown type '%s'", kindName)}
		} else if _, exists := database.Lookup[key]; exists { loadError = &LoadError{i+1, "duplicate key"} }
		fields := make(map[string]string)
		i++
		for lines[i] != "}" {
			if loadError == nil {
				name, expression, _ := strings.Cut(lines[i][2:], " = ")
				value, err := evaluate(strings.TrimSuffix(expression, ","), macros)
				if _, exists := fields[name]; err == nil && exists { err = fmt.Errorf("duplicate field '%s'", name) }
				if err != nil { loadError = &LoadError{i+1, err.Error()} } else { fields[name] = normalize(value) }
			}
			i++
		}
		if loadError == nil {
			for _, name := range required[kind] {
				_, present := fields[name]
				_, editor := fields["editor"]
				if !present && !(kind == 1 && name == "author" && editor) { loadError = &LoadError{i+1, fmt.Sprintf("missing field '%s'", name)}; break }
			}
		}
		if loadError != nil { database.Output = append(database.Output, fmt.Sprintf("ERROR line %d: %s: %s", loadError.Line, key, loadError.Reason)); errors++
		} else { entry := newEntry(key, kind, fields); database.Entries = append(database.Entries, entry); database.Lookup[key] = entry }
		i++
	}
	database.Output = append(database.Output, fmt.Sprintf("LOADED entries=%d macros=%d errors=%d", len(database.Entries), macroCount, errors))
	assigned := make(map[*Entry]bool)
	for i, entry := range database.Entries {
		if assigned[entry] { continue }
		var group []*Entry
		for _, other := range database.Entries[i:] {
			if entry.Primary().Equal(other.Primary()) && entry.Fields["year"] == other.Fields["year"] { group = append(group, other); assigned[other] = true }
		}
		if len(group) >= 2 {
			sort.Slice(group, func(i, j int) bool {
				if group[i].SortTitle != group[j].SortTitle { return group[i].SortTitle < group[j].SortTitle }
				return group[i].Key < group[j].Key
			})
			for j, other := range group { other.Suffix = string(rune('a'+j)) }
		}
	}
	return database
}
func (database *Database) IEEEOrder() ([]*Entry, map[*Entry]int) {
	cited := make(map[*Entry]bool)
	order := append([]*Entry(nil), database.Record...)
	for _, entry := range order { cited[entry] = true }
	var rest []*Entry
	for _, entry := range database.Entries { if !cited[entry] { rest = append(rest, entry) } }
	sort.Slice(rest, func(i, j int) bool { return rest[i].Key < rest[j].Key })
	order = append(order, rest...)
	numbers := make(map[*Entry]int)
	for i, entry := range order { numbers[entry] = i+1 }
	return order, numbers
}

type CitationKind int
const (
	Parenthetical CitationKind = iota
	Narrative
	Author
	Year
)
type Citation struct { Start, End int; Kind CitationKind; Entries []*Entry }
func citationText(citation Citation, style Style, numbers map[*Entry]int) string {
	parenthetical := citation.Kind == Parenthetical
	var parts []string
	if citation.Kind == Author || citation.Kind == Year || style == MLA || style == IEEE && !parenthetical {
		for _, entry := range citation.Entries {
			value := entry.ShortName(style, false)
			if citation.Kind == Year { value = entry.YearLabel(style)
			} else if style == IEEE && citation.Kind == Narrative { value = fmt.Sprintf("%s [%d]", value, numbers[entry]) }
			parts = append(parts, value)
		}
		separator := "; "
		if citation.Kind == Year { separator = ", " }
		text := strings.Join(parts, separator)
		if style == MLA && parenthetical { text = "("+text+")" }
		return text
	}
	if style == IEEE {
		var sorted []int
		for _, entry := range citation.Entries { sorted = append(sorted, numbers[entry]) }
		sort.Ints(sorted)
		for i := 0; i < len(sorted); {
			end := i+1
			for end < len(sorted) && sorted[end] == sorted[end-1]+1 { end++ }
			if end-i >= 3 { parts = append(parts, fmt.Sprintf("[%d]-[%d]", sorted[i], sorted[end-1]))
			} else { for _, number := range sorted[i:end] { parts = append(parts, fmt.Sprintf("[%d]", number)) } }
			i = end
		}
		return strings.Join(parts, ", ")
	}
	entries := append([]*Entry(nil), citation.Entries...)
	if parenthetical { sort.Slice(entries, func(i, j int) bool { return bibliographyLess(entries[i], entries[j]) }) }
	for i := 0; i < len(entries); {
		name := entries[i].ShortName(style, parenthetical)
		end := i+1
		for end < len(entries) && entries[end].ShortName(style, parenthetical) == name { end++ }
		var years []string
		for _, entry := range entries[i:end] { years = append(years, entry.YearLabel(style)) }
		if parenthetical {
			separator := " "
			if style == APA { separator = ", " }
			parts = append(parts, name+separator+strings.Join(years, ", "))
		} else { parts = append(parts, name+" ("+strings.Join(years, ", ")+")") }
		i = end
	}
	text := strings.Join(parts, "; ")
	if parenthetical { text = "("+text+")" }
	return text
}
func (database *Database) Cite(style Style, text string) (string, error) {
	var citations []Citation
	for position := 0; position < len(text); {
		offset := strings.IndexByte(text[position:], '\\')
		if offset < 0 { break }
		start := position+offset
		brace := start+strings.IndexByte(text[start:], '{')
		end := brace+strings.IndexByte(text[brace:], '}')
		citation := Citation{Start: start, End: end+1}
		switch text[start+1:brace] { case "citet": citation.Kind = Narrative; case "citeauthor": citation.Kind = Author; case "citeyear": citation.Kind = Year }
		seen := make(map[*Entry]bool)
		for _, key := range strings.Split(text[brace+1:end], ",") {
			entry, exists := database.Lookup[key]
			if !exists { return "", fmt.Errorf("unknown key '%s'", key) }
			if !seen[entry] { citation.Entries = append(citation.Entries, entry); seen[entry] = true }
		}
		citations = append(citations, citation); position = end+1
	}
	recorded := make(map[*Entry]bool)
	for _, entry := range database.Record { recorded[entry] = true }
	for _, citation := range citations { for _, entry := range citation.Entries { if !recorded[entry] { database.Record = append(database.Record, entry); recorded[entry] = true } } }
	_, numbers := database.IEEEOrder()
	var result strings.Builder
	position := 0
	for _, citation := range citations {
		result.WriteString(text[position:citation.Start]); result.WriteString(citationText(citation, style, numbers)); position = citation.End
	}
	result.WriteString(text[position:])
	return result.String(), nil
}
func (database *Database) Keygen() []string {
	counts, used := make(map[string]int), make(map[string]int)
	for _, entry := range database.Entries { counts[entry.BaseKey]++ }
	var result []string
	for _, entry := range database.Entries {
		key := entry.BaseKey
		if counts[key] >= 2 { key += string(rune('a'+used[entry.BaseKey])); used[entry.BaseKey]++ }
		result = append(result, entry.Key+" -> "+key)
	}
	return result
}
func (database *Database) Check() []string {
	var result []string
	for i, entry := range database.Entries {
		var warnings []string
		if pages, exists := entry.Fields["pages"]; exists {
			pages = plain(pages)
			if strings.Contains(pages, "-") && !strings.Contains(pages, "--") { warnings = append(warnings, "pages use a single hyphen") }
			parts := strings.FieldsFunc(pages, func(c rune) bool { return c == '-' })
			if len(parts) == 2 && allDigits(parts[0]) && allDigits(parts[1]) {
				a, _ := strconv.Atoi(parts[0]); b, _ := strconv.Atoi(parts[1])
				if a > b { warnings = append(warnings, "pages are reversed") }
			}
		}
		if len(entry.Year) != 4 || !allDigits(entry.Year) { warnings = append(warnings, "year is not 4 digits") }
		lowerCount, upperCount := 0, 0
		for j := range len(entry.PlainTitle) { if lower(entry.PlainTitle[j]) { lowerCount++ }; if upper(entry.PlainTitle[j]) { upperCount++ } }
		if lowerCount == 0 && upperCount >= 2 { warnings = append(warnings, "title is all caps") }
		if _, exists := entry.Fields["doi"]; entry.Kind == 0 && !exists { warnings = append(warnings, "article has no doi") }
		for _, earlier := range database.Entries[:i] { if entry.LowerTitle == earlier.LowerTitle { warnings = append(warnings, "same title as "+earlier.Key); break } }
		for _, name := range entry.UnknownFields() { warnings = append(warnings, fmt.Sprintf("unknown field '%s'", name)) }
		for _, warning := range warnings { result = append(result, "WARN "+entry.Key+": "+warning) }
	}
	return append(result, fmt.Sprintf("CHECK warnings=%d", len(result)))
}
func (database *Database) Export(key string) ([]string, error) {
	entry, exists := database.Lookup[key]
	if !exists { return nil, fmt.Errorf("unknown key '%s'", key) }
	var names []string
	for _, name := range fieldOrder { if _, exists := entry.Fields[name]; exists { names = append(names, name) } }
	names = append(names, entry.UnknownFields()...)
	result := []string{"@"+typeNames[entry.Kind]+"{"+key+","}
	for i, name := range names {
		line := "  "+name+" = {"+entry.Fields[name]+"}"
		if i+1 < len(names) { line += "," }
		result = append(result, line)
	}
	return append(result, "}"), nil
}
func sortedKeys[V any](values map[string]V) []string {
	keys := make([]string, 0, len(values))
	for key := range values { keys = append(keys, key) }
	sort.Strings(keys)
	return keys
}
type Pair struct { A, B string }
func (database *Database) Stats() []string {
	types, years := make(map[string]int), make(map[string]int)
	authors := make(map[string]bool)
	pairs := make(map[Pair]int)
	for _, entry := range database.Entries {
		types[typeNames[entry.Kind]]++; years[entry.Year]++
		if entry.Authors != nil {
			distinct := make(map[string]bool)
			for _, name := range entry.Authors.Names { text := name.Text(false, false); distinct[text] = true; authors[text] = true }
			names := sortedKeys(distinct)
			for a := range names { for b := a+1; b < len(names); b++ { pairs[Pair{names[a], names[b]}]++ } }
		}
	}
	result := []string{fmt.Sprintf("ENTRIES %d", len(database.Entries))}
	for _, kind := range sortedKeys(types) { result = append(result, fmt.Sprintf("TYPE %s %d", kind, types[kind])) }
	for _, year := range sortedKeys(years) { result = append(result, fmt.Sprintf("YEAR %s %d", year, years[year])) }
	result = append(result, fmt.Sprintf("AUTHORS %d", len(authors)))
	var best Pair
	bestCount := 0
	for pair, count := range pairs {
		if count > bestCount || count == bestCount && (pair.A < best.A || pair.A == best.A && pair.B < best.B) { best, bestCount = pair, count }
	}
	if bestCount == 0 { return append(result, "PAIR none") }
	return append(result, fmt.Sprintf("PAIR %s & %s %d", best.A, best.B, bestCount))
}
func (database *Database) Command(line string) ([]string, error) {
	command, _, _ := strings.Cut(line, " ")
	words := strings.Split(line, " ")
	if command == "CITE" || command == "SEARCH" { words = strings.SplitN(line, " ", 3) }
	commandNames := []string{"FORMAT", "BIBLIOGRAPHY", "CITE", "KEYGEN", "CHECK", "SEARCH", "EXPORT", "STATS"}
	kind := indexOf(commandNames, command)
	if kind < 0 { return nil, fmt.Errorf("unknown command '%s'", command) }
	arities := []int{-1, 1, 2, 0, 0, 2, 1, 0}
	if kind == 0 && len(words) < 3 || kind != 0 && len(words) != arities[kind]+1 { return nil, fmt.Errorf("wrong number of arguments") }
	style := APA
	if kind <= 2 {
		index := indexOf([]string{"APA", "IEEE", "CHICAGO", "MLA"}, words[1])
		if index < 0 { return nil, fmt.Errorf("unknown style '%s'", words[1]) }
		style = Style(index)
	}
	switch command {
	case "FORMAT":
		_, numbers := database.IEEEOrder()
		var result []string
		for _, key := range words[2:] {
			if entry, exists := database.Lookup[key]; exists { result = append(result, entry.Reference(style, numbers[entry], false))
			} else { result = append(result, fmt.Sprintf("ERROR unknown key '%s'", key)) }
		}
		return result, nil
	case "BIBLIOGRAPHY":
		order, numbers := database.IEEEOrder()
		if style != IEEE { sort.Slice(order, func(i, j int) bool { return bibliographyLess(order[i], order[j]) }) }
		heading := "References"
		if style == MLA { heading = "Works Cited" }
		result := []string{heading}
		for i, entry := range order {
			repeated := i > 0 && (style == Chicago || style == MLA) && entry.Primary().Equal(order[i-1].Primary())
			result = append(result, entry.Reference(style, numbers[entry], repeated))
		}
		return result, nil
	case "CITE":
		text, err := database.Cite(style, words[2]); return []string{text}, err
	case "KEYGEN": return database.Keygen(), nil
	case "CHECK": return database.Check(), nil
	case "EXPORT": return database.Export(words[1])
	case "STATS": return database.Stats(), nil
	case "SEARCH":
		var matches []string
		needle := strings.ToLower(words[2])
		for _, entry := range database.Entries { if value, exists := entry.Fields[words[1]]; exists && strings.Contains(strings.ToLower(plain(value)), needle) { matches = append(matches, entry.Key) } }
		if len(matches) == 0 { return []string{"MATCHES 0"}, nil }
		return []string{fmt.Sprintf("MATCHES %d: %s", len(matches), strings.Join(matches, " "))}, nil
	}
	panic("unreachable command")
}
func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var lines []string
	for scanner.Scan() { if scanner.Text() == "%%" { break }; lines = append(lines, scanner.Text()) }
	database := readDatabase(lines)
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	for _, line := range database.Output { fmt.Fprintln(output, line) }
	scanner.Scan()
	count, _ := strconv.Atoi(scanner.Text())
	for range count {
		scanner.Scan()
		result, err := database.Command(scanner.Text())
		if err != nil { fmt.Fprintln(output, "ERROR "+err.Error())
		} else { for _, line := range result { fmt.Fprintln(output, line) } }
	}
}
