package main

import (
	"regexp"
	"strconv"
	"strings"
)

var bodyKinds = map[string]bool{"paragraph": true, "item": true, "enum": true, "quote": true, "term": true}
var settingNames = map[string]bool{"width": true, "indent": true, "align": true}
var preambleNames = map[string]bool{"page": true, "header": true, "footer": true}
var blockNames = map[string]bool{"title": true, "author": true, "h1": true, "h2": true, "item": true,
	"enum": true, "quote": true, "term": true, "table": true, "verbatim": true, "toc": true, "lot": true,
	"index": true, "bibliography": true}
var emptyArgumentNames = map[string]bool{"newpage": true, "verbatim": true, "toc": true, "lot": true, "index": true, "bibliography": true}
var dictionaryWord = regexp.MustCompile(`^[a-z]+(-[a-z]+)*$`)

type SourceLine struct {
	Number int
	Text   string
}
type Warning struct {
	Number  int
	Message string
}
type InlineToken struct {
	Kind, Text, Argument string
	Number               int
}
type Block struct {
	Kind, Argument, Align, Term, Columns, Caption, Text, Label, Number string
	Line, Width, Indent, ID, ParagraphNumber, EnumNumber               int
	PageBreak                                                          bool
	BodyLines, InnerLines                                              []SourceLine
	Tokens                                                             []InlineToken
	Rows                                                               [][]string
	TableLines                                                         []string
}
type BibEntry struct {
	Line                                       int
	Key, Author, Year, Title, BaseLabel, Label string
	Cited                                      bool
}
type Document struct {
	Blocks            []*Block
	Warnings          []Warning
	Height, PageWidth int
	Header, Footer    [3]string
	Hyphenation       []string
	Bibliography      []*BibEntry
}

func validArgument(name, argument string) bool {
	switch name {
	case "width", "indent", "page":
		if !regexp.MustCompile(`^[0-9]{1,9}$`).MatchString(argument) {
			return false
		}
		v, _ := strconv.Atoi(argument)
		limits := map[string][2]int{"width": {20, 80}, "indent": {0, 8}, "page": {10, 100}}[name]
		return v >= limits[0] && v <= limits[1]
	case "align":
		return argument == "left" || argument == "right" || argument == "center" || argument == "justify"
	case "header", "footer":
		return strings.Count(argument, "|") == 2
	case "hyphenation":
		if argument == "" {
			return false
		}
		for _, w := range strings.Split(argument, " ") {
			if !dictionaryWord.MatchString(w) {
				return false
			}
		}
		return true
	case "bib":
		key, fields, found := strings.Cut(argument, " ")
		if !found || !regexp.MustCompile(`^[a-z0-9]+$`).MatchString(key) {
			return false
		}
		parts := strings.Split(fields, "|")
		return len(parts) == 3 && parts[0] != "" && parts[2] != "" && regexp.MustCompile(`^[0-9]{4}$`).MatchString(parts[1])
	case "term":
		term, description, found := strings.Cut(argument, "|")
		return found && term != "" && description != ""
	case "table":
		columns, _, _ := strings.Cut(argument, " ")
		return regexp.MustCompile(`^[lrc]+$`).MatchString(columns)
	default:
		if emptyArgumentNames[name] {
			return argument == ""
		}
		return argument != ""
	}
}
func parseDocument(lines []string) *Document {
	d := &Document{Height: 40, PageWidth: 60}
	width, indent, align := 60, 0, "left"
	accepted := map[string]bool{}
	var open, inner *Block
	pending := false
	create := func(kind string, line int, argument string) *Block {
		if len(d.Blocks) == 0 {
			d.PageWidth = width
		}
		b := &Block{Kind: kind, Line: line, Argument: argument, Width: width, Indent: indent, Align: align, PageBreak: pending}
		pending = false
		d.Blocks = append(d.Blocks, b)
		return b
	}
	for index, line := range lines {
		number := index + 1
		if inner != nil {
			if line == ".end" {
				inner = nil
			} else {
				inner.InnerLines = append(inner.InnerLines, SourceLine{number, line})
			}
			continue
		}
		if line == "" {
			open = nil
			continue
		}
		if !strings.HasPrefix(line, ".") {
			if open == nil {
				open = create("paragraph", number, "")
			}
			open.BodyLines = append(open.BodyLines, SourceLine{number, line})
			continue
		}
		open = nil
		name, argument, _ := strings.Cut(line[1:], " ")
		warning := ""
		if !settingNames[name] && !preambleNames[name] && !blockNames[name] && name != "newpage" && name != "hyphenation" && name != "bib" {
			warning = "unknown directive ." + name
		} else if !validArgument(name, argument) {
			warning = "bad argument for ." + name
		} else if preambleNames[name] && len(d.Blocks) > 0 {
			warning = "." + name + " ignored after the preamble"
		} else if preambleNames[name] && accepted[name] {
			warning = "duplicate ." + name
		}
		if warning != "" {
			d.Warnings = append(d.Warnings, Warning{number, warning})
			continue
		}
		if settingNames[name] {
			if name == "align" {
				align = argument
			} else if name == "width" {
				width, _ = strconv.Atoi(argument)
			} else {
				indent, _ = strconv.Atoi(argument)
			}
		} else if preambleNames[name] {
			accepted[name] = true
			if name == "page" {
				d.Height, _ = strconv.Atoi(argument)
			} else {
				parts := strings.Split(argument, "|")
				var f [3]string
				copy(f[:], parts)
				if name == "header" {
					d.Header = f
				} else {
					d.Footer = f
				}
			}
		} else if name == "newpage" {
			pending = true
		} else if name == "hyphenation" {
			d.Hyphenation = append(d.Hyphenation, strings.Split(argument, " ")...)
		} else if name == "bib" {
			key, fields, _ := strings.Cut(argument, " ")
			parts := strings.Split(fields, "|")
			d.Bibliography = append(d.Bibliography, &BibEntry{Line: number, Key: key, Author: parts[0], Year: parts[1], Title: parts[2]})
		} else {
			b := create(name, number, argument)
			if name == "item" || name == "enum" || name == "quote" {
				b.BodyLines = append(b.BodyLines, SourceLine{number, argument})
				open = b
			} else if name == "term" {
				term, description, _ := strings.Cut(argument, "|")
				b.Term = term
				b.BodyLines = append(b.BodyLines, SourceLine{number, description})
				open = b
			} else if name == "table" {
				b.Columns, b.Caption, _ = strings.Cut(argument, " ")
				inner = b
			} else if name == "verbatim" {
				inner = b
			}
		}
	}
	if inner != nil {
		d.Warnings = append(d.Warnings, Warning{inner.Line, "unterminated " + inner.Kind})
	}
	return d
}
