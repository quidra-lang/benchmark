package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Profile struct {
	Width, Indent, MaxBlank, CommentColumn                             int
	Allman, Spaces, KeywordSpace, IndentCases, AddBraces, RemoveParens bool
}
type Source struct {
	Header, Name, Profile string
	Lines                 []string
}
type FormatResult struct {
	Lines                 []string
	Err                   *FileError
	Document, FunctionDoc *Doc
	FunctionName          string
	Comments              int
}

func attachComments(tokens []*Token, items []Lexeme) int {
	next := make([]*Token, len(items))
	var following *Token
	for i := len(items) - 1; i >= 0; i-- {
		next[i] = following
		if items[i].Token != nil {
			following = items[i].Token
		}
	}
	var previous *Token
	count := 0
	for i, item := range items {
		if item.Token != nil {
			previous = item.Token
			continue
		}
		count++
		c := item.Comment
		n := next[i]
		if previous != nil && previous.Line == c.Line && (n == nil || n.Line > c.Line) {
			previous.Trailing = append(previous.Trailing, c)
			previous.OriginalTrailing = true
		} else {
			c.Own = c.Kind == "line" || i+1 == len(items) || items[i+1].line() > c.Line
			if n == nil {
				n = tokens[len(tokens)-1]
			}
			n.Leading = append(n.Leading, c)
		}
	}
	return count
}
func checkComments(root *Node, tokens []*Token) *FileError {
	allowed := map[int]bool{len(tokens) - 1: true}
	trailing := map[int]bool{}
	var walk func(*Node)
	walk = func(n *Node) {
		if n == nil {
			return
		}
		switch n.Kind {
		case "program":
			for _, item := range n.Elements {
				allowed[item.First] = true
			}
		case "block":
			allowed[n.Close.Index] = true
			for _, s := range n.Elements {
				allowed[s.First] = true
			}
		case "switchbody":
			allowed[n.Close.Index] = true
			for _, clause := range n.Elements {
				allowed[clause.Token.Index] = true
				for _, s := range clause.Elements {
					allowed[s.First] = true
				}
			}
		case "if", "while", "for":
			if n.Body.Kind != "block" {
				allowed[n.Body.First] = true
			}
			if n.Kind == "if" && n.Else != nil && n.Else.Kind != "block" && n.Else.Kind != "if" {
				allowed[n.Else.First] = true
			}
		case "list":
			for _, element := range n.Elements {
				allowed[element.First] = true
			}
			if n.Trailing != nil {
				trailing[n.Trailing.Index] = true
			}
		}
		for _, child := range nodeChildren(n) {
			walk(child)
		}
	}
	walk(root)
	for _, token := range tokens {
		for _, comment := range token.Leading {
			if trailing[token.Index] || comment.Own && !allowed[token.Index] {
				return &FileError{comment.Position, "comment not allowed here"}
			}
		}
	}
	return nil
}

type Builder struct {
	Profile       Profile
	Tokens        []*Token
	FirstFunction *Doc
	FunctionName  string
}

func (b *Builder) space() *Doc {
	if b.Profile.Spaces {
		return text(" ")
	}
	return text("")
}
func (b *Builder) operatorLine() *Doc {
	if b.Profile.Spaces {
		return marker("line")
	}
	return marker("softline")
}
func (b *Builder) keywordSpace() *Doc {
	if b.Profile.KeywordSpace {
		return text(" ")
	}
	return text("")
}
func (b *Builder) braceSeparator() *Doc {
	if b.Profile.Allman {
		return marker("hardline")
	}
	return text(" ")
}
func (b *Builder) separator(blank int) *Doc {
	docs := []*Doc{marker("hardline")}
	for i := 0; i < min(blank, b.Profile.MaxBlank); i++ {
		docs = append(docs, marker("hardline"))
	}
	return cat(docs...)
}
func preBlank(t *Token) int {
	if len(t.Leading) > 0 {
		return t.Leading[0].Blank
	}
	return t.Blank
}
func (b *Builder) comments(comments []*Comment, lastBlank *int) *Doc {
	docs := []*Doc{}
	for i, c := range comments {
		docs = append(docs, text(c.Text))
		var nextBlank *int
		if i+1 < len(comments) {
			nextBlank = &comments[i+1].Blank
		} else {
			nextBlank = lastBlank
		}
		if nextBlank != nil {
			if c.Own {
				docs = append(docs, b.separator(*nextBlank))
			} else {
				docs = append(docs, text(" "))
			}
		}
	}
	return cat(docs...)
}
func trailingPart(t *Token) *Doc {
	if len(t.Trailing) == 0 {
		return text("")
	}
	parts := []string{}
	for _, c := range t.Trailing {
		parts = append(parts, c.Text)
	}
	return suffix(strings.Join(parts, " "))
}
func (b *Builder) tokenLeading(t *Token, leading []*Comment) *Doc {
	return cat(b.comments(leading, &t.Blank), text(t.Text), trailingPart(t))
}
func (b *Builder) token(t *Token) *Doc {
	if t == nil {
		return text("")
	}
	return b.tokenLeading(t, t.Leading)
}
func splitClosing(t *Token) ([]*Comment, []*Comment) {
	last := -1
	for i, c := range t.Leading {
		if c.Own {
			last = i
		}
	}
	return t.Leading[:last+1], t.Leading[last+1:]
}
func (b *Builder) whole(root *Node) *Doc {
	docs := []*Doc{}
	for i, item := range root.Elements {
		if i > 0 {
			docs = append(docs, b.separator(preBlank(b.Tokens[item.First])))
		}
		d := b.statement(item)
		docs = append(docs, d)
		if item.Kind == "function" && b.FirstFunction == nil {
			b.FirstFunction = d
			b.FunctionName = item.Name.Text
		}
	}
	end := b.Tokens[len(b.Tokens)-1]
	if len(end.Leading) > 0 {
		if len(root.Elements) > 0 {
			docs = append(docs, b.separator(end.Leading[0].Blank))
		}
		docs = append(docs, b.comments(end.Leading, nil))
	}
	return cat(docs...)
}
func (b *Builder) list(n *Node) *Doc {
	if len(n.Elements) == 0 {
		return cat(b.token(n.Open), b.token(n.Close))
	}
	markerDoc := text("")
	for i := n.Open.Index; i < n.Close.Index; i++ {
		if b.Tokens[i].OriginalTrailing {
			markerDoc = marker("break_parent")
			break
		}
	}
	inside := []*Doc{marker("softline")}
	for i, element := range n.Elements {
		if i > 0 {
			inside = append(inside, b.token(n.Commas[i-1]), marker("line"))
		}
		if n.Value == "arguments" {
			inside = append(inside, b.expression(element, 0))
		} else {
			inside = append(inside, b.statement(element))
		}
	}
	if n.Value == "initializer" {
		inside = append(inside, ifBreak(",", ""))
		if n.Trailing != nil {
			inside = append(inside, trailingPart(n.Trailing))
		}
	}
	return group(markerDoc, b.token(n.Open), nest(b.Profile.Indent, inside...), marker("softline"), b.token(n.Close))
}
func (b *Builder) block(n *Node) *Doc {
	h, g := splitClosing(n.Close)
	if len(n.Elements) == 0 && len(h) == 0 {
		return cat(b.token(n.Open), b.tokenLeading(n.Close, g))
	}
	inside := []*Doc{marker("hardline")}
	for i, statement := range n.Elements {
		if i > 0 {
			inside = append(inside, b.separator(preBlank(b.Tokens[statement.First])))
		}
		inside = append(inside, b.statement(statement))
	}
	if len(h) > 0 {
		if len(n.Elements) > 0 {
			inside = append(inside, b.separator(h[0].Blank))
		}
		inside = append(inside, b.comments(h, nil))
	}
	return cat(b.token(n.Open), nest(b.Profile.Indent, inside...), marker("hardline"), b.tokenLeading(n.Close, g))
}
func (b *Builder) body(n *Node) *Doc {
	if n.Kind == "block" {
		return cat(b.braceSeparator(), b.block(n))
	}
	if b.Profile.AddBraces {
		return cat(b.braceSeparator(), text("{"), nest(b.Profile.Indent, marker("hardline"), b.statement(n)), marker("hardline"), text("}"))
	}
	return nest(b.Profile.Indent, marker("hardline"), b.statement(n))
}
func (b *Builder) declaration(n *Node) *Doc {
	docs := []*Doc{b.token(n.Token), text(" "), b.token(n.Name)}
	for _, d := range n.Dimensions {
		docs = append(docs, b.token(d.Open))
		if d.Expr != nil {
			docs = append(docs, b.expression(d.Expr, 0))
		}
		docs = append(docs, b.token(d.Close))
	}
	if n.Op != nil {
		docs = append(docs, b.space(), b.token(n.Op), b.space())
		if n.Init.Kind == "list" {
			docs = append(docs, b.list(n.Init))
		} else {
			docs = append(docs, b.expression(n.Init, 0))
		}
	}
	docs = append(docs, b.token(n.Semi))
	return cat(docs...)
}
func (b *Builder) simple(n *Node) *Doc {
	if n.Kind == "assignment" {
		return cat(b.expression(n.Left, 0), b.space(), b.token(n.Op), b.space(), b.expression(n.Right, 0))
	}
	return b.expression(n.Expr, 0)
}
func (b *Builder) statement(n *Node) *Doc {
	switch n.Kind {
	case "function":
		return cat(b.token(n.Token), text(" "), b.token(n.Name), b.list(n.Init), marker("hardline"), b.block(n.Body))
	case "parameter", "declaration":
		return b.declaration(n)
	case "list":
		return b.list(n)
	case "block":
		return b.block(n)
	case "assignment", "simple":
		return cat(b.simple(n), b.token(n.Semi))
	case "return":
		docs := []*Doc{b.token(n.Token)}
		if n.Expr != nil {
			docs = append(docs, text(" "), b.expression(n.Expr, 0))
		}
		docs = append(docs, b.token(n.Semi))
		return cat(docs...)
	case "break", "continue":
		return cat(b.token(n.Token), b.token(n.Semi))
	case "while":
		return cat(b.token(n.Token), b.keywordSpace(), b.token(n.Open), b.expression(n.Expr, 0), b.token(n.Close), b.body(n.Body))
	case "for":
		parts := []*Doc{}
		if n.Init != nil {
			if n.Init.Kind == "declaration" {
				parts = append(parts, b.declaration(n.Init))
			} else {
				parts = append(parts, b.simple(n.Init))
			}
		}
		parts = append(parts, b.token(n.Semi))
		if n.Cond != nil {
			parts = append(parts, marker("line"), b.expression(n.Cond, 0))
		}
		parts = append(parts, b.token(n.Semi2))
		if n.Update != nil {
			parts = append(parts, marker("line"), b.simple(n.Update))
		}
		return cat(b.token(n.Token), b.keywordSpace(), b.token(n.Open), group(align(parts...)), b.token(n.Close), b.body(n.Body))
	case "if":
		docs := []*Doc{b.token(n.Token), b.keywordSpace(), b.token(n.Open), b.expression(n.Expr, 0), b.token(n.Close), b.body(n.Body)}
		if n.Else != nil {
			separator := marker("hardline")
			if !b.Profile.Allman && (n.Body.Kind == "block" || b.Profile.AddBraces) {
				separator = text(" ")
			}
			docs = append(docs, separator, b.token(n.ElseToken))
			if n.Else.Kind == "if" {
				docs = append(docs, text(" "), b.statement(n.Else))
			} else {
				docs = append(docs, b.body(n.Else))
			}
		}
		return cat(docs...)
	case "switch":
		body := n.Body
		h, g := splitClosing(body.Close)
		head := cat(b.token(n.Token), b.keywordSpace(), b.token(n.Open), b.expression(n.Expr, 0), b.token(n.Close), b.braceSeparator(), b.token(body.Open))
		if len(body.Elements) == 0 && len(h) == 0 {
			return cat(head, b.tokenLeading(body.Close, g))
		}
		inside := []*Doc{marker("hardline")}
		for i, clause := range body.Elements {
			if i > 0 {
				inside = append(inside, b.separator(preBlank(clause.Token)))
			}
			parts := []*Doc{b.token(clause.Token)}
			if clause.Expr != nil {
				parts = append(parts, text(" "), b.expression(clause.Expr, 0))
			}
			parts = append(parts, b.token(clause.Colon))
			if len(clause.Elements) > 0 {
				statements := []*Doc{marker("hardline")}
				for j, statement := range clause.Elements {
					if j > 0 {
						statements = append(statements, b.separator(preBlank(b.Tokens[statement.First])))
					}
					statements = append(statements, b.statement(statement))
				}
				parts = append(parts, nest(b.Profile.Indent, statements...))
			}
			inside = append(inside, cat(parts...))
		}
		if len(h) > 0 {
			if len(body.Elements) > 0 {
				inside = append(inside, b.separator(h[0].Blank))
			}
			inside = append(inside, b.comments(h, nil))
		}
		indent := 0
		if b.Profile.IndentCases {
			indent = b.Profile.Indent
		}
		return cat(head, nest(indent, inside...), marker("hardline"), b.tokenLeading(body.Close, g))
	}
	return b.expression(n, 0)
}
func (b *Builder) opening(n *Node, required int) *Node {
	if !b.Profile.RemoveParens {
		return n
	}
	for n.Kind == "paren" && expressionLevel(n.Expr) >= required && len(n.Open.Leading) == 0 && len(n.Close.Leading) == 0 {
		inner := n.Expr
		first, last := b.Tokens[inner.First], b.Tokens[inner.Last]
		front := append([]*Comment{}, n.Open.Trailing...)
		first.Trailing = append(front, first.Trailing...)
		last.Trailing = append(last.Trailing, n.Close.Trailing...)
		n.Open.Trailing = nil
		n.Close.Trailing = nil
		n = inner
	}
	return n
}
func postfix(n *Node) bool { return n.Kind == "call" || n.Kind == "index" || n.Kind == "member" }
func (b *Builder) postfixDocument(n *Node) *Doc {
	switch n.Kind {
	case "call":
		return b.list(n.Init)
	case "index":
		return cat(b.token(n.Open), b.expression(n.Expr, 0), b.token(n.Close))
	default:
		return cat(b.token(n.Op), b.token(n.Name))
	}
}
func (b *Builder) expression(original *Node, required int) *Doc {
	n := b.opening(original, required)
	switch n.Kind {
	case "atom":
		return b.token(n.Token)
	case "paren":
		return cat(b.token(n.Open), b.expression(n.Expr, 0), b.token(n.Close))
	case "unary":
		return cat(b.token(n.Op), b.expression(n.Expr, 8))
	case "binary":
		level := expressionLevel(n)
		operators := []*Token{}
		operands := []*Node{}
		head := n
		for head.Kind == "binary" && expressionLevel(head) == level {
			operators = append(operators, head.Op)
			operands = append(operands, head.Right)
			head = b.opening(head.Left, level)
		}
		inside := []*Doc{}
		for i := len(operators) - 1; i >= 0; i-- {
			inside = append(inside, b.operatorLine(), b.token(operators[i]), b.space(), b.expression(operands[i], level+1))
		}
		return group(b.expression(head, level), nest(b.Profile.Indent, inside...))
	case "conditional":
		inside := []*Doc{}
		current := n
		for {
			inside = append(inside, b.operatorLine(), b.token(current.Op), b.space(), b.expression(current.Then, 0), b.operatorLine(), b.token(current.Colon), b.space())
			other := b.opening(current.Else, 0)
			if other.Kind == "conditional" {
				inside = append(inside, b.expression(other.Expr, 1))
				current = other
			} else {
				inside = append(inside, b.expression(other, 0))
				break
			}
		}
		return group(b.expression(n.Expr, 1), nest(b.Profile.Indent, inside...))
	case "call", "index", "member":
		reversed := []*Node{}
		head := n
		for postfix(head) {
			reversed = append(reversed, head)
			head = b.opening(head.Left, 8)
		}
		operations := make([]*Node, len(reversed))
		for i, op := range reversed {
			operations[len(reversed)-1-i] = op
		}
		segments := [][]*Node{{}}
		for _, op := range operations {
			if op.Kind == "member" {
				segments = append(segments, []*Node{})
			}
			segments[len(segments)-1] = append(segments[len(segments)-1], op)
		}
		count, first := 0, -1
		for i := 1; i < len(segments); i++ {
			hasCall := false
			for _, op := range segments[i] {
				if op.Kind == "call" {
					hasCall = true
				}
			}
			if hasCall {
				count++
				if first < 0 {
					first = i
				}
			}
		}
		docs := []*Doc{b.expression(head, 8)}
		if count < 2 {
			for _, op := range operations {
				docs = append(docs, b.postfixDocument(op))
			}
			return cat(docs...)
		}
		for i := 0; i < first; i++ {
			for _, op := range segments[i] {
				docs = append(docs, b.postfixDocument(op))
			}
		}
		inside := []*Doc{}
		for i := first; i < len(segments); i++ {
			inside = append(inside, marker("softline"))
			for _, op := range segments[i] {
				inside = append(inside, b.postfixDocument(op))
			}
		}
		docs = append(docs, nest(b.Profile.Indent, inside...))
		return group(docs...)
	}
	return text("")
}
func format(source []string, profile Profile) FormatResult {
	tokens, items, err := lex(source)
	if err != nil {
		return FormatResult{Err: err}
	}
	comments := attachComments(tokens, items)
	parser := &Parser{Tokens: tokens}
	root := parser.program()
	if parser.Err != nil {
		return FormatResult{Err: parser.Err}
	}
	if err = checkComments(root, tokens); err != nil {
		return FormatResult{Err: err}
	}
	builder := &Builder{Profile: profile, Tokens: tokens}
	document := builder.whole(root)
	result := FormatResult{Document: document, FunctionDoc: builder.FirstFunction, FunctionName: builder.FunctionName, Comments: comments}
	if len(root.Elements) == 0 && len(tokens[len(tokens)-1].Leading) == 0 {
		result.Lines = []string{}
	} else {
		result.Lines = printDoc(document, profile.Width, profile.CommentColumn)
	}
	return result
}
func readLines(path string) []string {
	f, err := os.Open(path)
	if err != nil {
		panic(err)
	}
	defer f.Close()
	lines := []string{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	if err = scanner.Err(); err != nil {
		panic(err)
	}
	return lines
}
func readProfiles() map[string]Profile {
	profiles := map[string]Profile{}
	name := ""
	values := map[string]string{}
	save := func() {
		if name == "" {
			return
		}
		number := func(key string) int {
			n, _ := strconv.Atoi(values[key])
			return n
		}
		profiles[name] = Profile{Width: number("width"), Indent: number("indent"), MaxBlank: number("max_blank_lines"), CommentColumn: number("comment_column"), Allman: values["brace_style"] == "allman", Spaces: values["space_around_operators"] == "yes", KeywordSpace: values["space_after_keyword"] == "yes", IndentCases: values["indent_case_labels"] == "yes", AddBraces: values["add_braces"] == "yes", RemoveParens: values["remove_parens"] == "yes"}
	}
	for _, line := range readLines("input/style.txt") {
		if line == "" {
			continue
		}
		if line[0] == '[' {
			save()
			name = line[1 : len(line)-1]
			values = map[string]string{}
		} else {
			a := strings.SplitN(line, "=", 2)
			values[a[0]] = a[1]
		}
	}
	save()
	return profiles
}
func readSources() []Source {
	out := []Source{}
	for _, line := range readLines("input/sources.txt") {
		if strings.HasPrefix(line, "=== ") {
			a := strings.Split(line, " ")
			out = append(out, Source{Header: line, Name: a[1], Profile: a[2]})
		} else {
			out[len(out)-1].Lines = append(out[len(out)-1].Lines, line)
		}
	}
	return out
}
func writeLines(path string, lines []string) {
	value := ""
	if len(lines) > 0 {
		value = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+path, []byte(value), 0644); err != nil {
		panic(err)
	}
}
func main() {
	profiles := readProfiles()
	formatted, idempotency, diagnostics, trees, changes := []string{}, []string{}, []string{}, []string{}, []string{}
	for _, source := range readSources() {
		profile := profiles[source.Profile]
		result := format(source.Lines, profile)
		original := make([]string, len(source.Lines))
		for i, line := range source.Lines {
			original[i] = strings.TrimRight(line, " ")
		}
		formatted = append(formatted, source.Header)
		trees = append(trees, "=== "+source.Name)
		changes = append(changes, "=== "+source.Name)
		if result.Err != nil {
			err := result.Err
			formatted = append(formatted, original...)
			idempotency = append(idempotency, source.Name+": skipped (syntax error)")
			diagnostics = append(diagnostics, fmt.Sprintf("%s:%d:%d: error: %s", source.Name, err.Line, err.Column, err.Message))
			trees = append(trees, "syntax error")
			changes = append(changes, "skipped (syntax error)")
			continue
		}
		formatted = append(formatted, result.Lines...)
		second := format(result.Lines, profile)
		if second.Err != nil {
			err := second.Err
			idempotency = append(idempotency, fmt.Sprintf("%s: unstable (second pass: %d:%d: %s)", source.Name, err.Line, err.Column, err.Message))
		} else {
			difference := -1
			for i := 0; i < min(len(result.Lines), len(second.Lines)); i++ {
				if result.Lines[i] != second.Lines[i] {
					difference = i + 1
					break
				}
			}
			if difference < 0 && len(result.Lines) != len(second.Lines) {
				difference = min(len(result.Lines), len(second.Lines)) + 1
			}
			if difference < 0 {
				idempotency = append(idempotency, source.Name+": stable")
			} else {
				idempotency = append(idempotency, fmt.Sprintf("%s: unstable at line %d", source.Name, difference))
			}
		}
		longest := 0
		for i, line := range result.Lines {
			longest = max(longest, len(line))
			if len(line) > profile.Width {
				diagnostics = append(diagnostics, fmt.Sprintf("%s:%d: warning: line too long (%d > %d)", source.Name, i+1, len(line), profile.Width))
			}
		}
		groups, broken, forced := groupMetrics(result.Document)
		trees = append(trees, fmt.Sprintf("metrics lines=%d longest=%d comments=%d groups=%d broken=%d forced=%d", len(result.Lines), longest, result.Comments, groups, broken, forced))
		if result.FunctionDoc == nil {
			trees = append(trees, "no function")
		} else {
			trees = append(trees, "function "+result.FunctionName)
			trees = append(trees, docTree(result.FunctionDoc, 0)...)
		}
		diff, _, _ := diffLines(original, result.Lines)
		changes = append(changes, diff...)
	}
	if len(diagnostics) == 0 {
		diagnostics = append(diagnostics, "no diagnostics")
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("formatted.txt", formatted)
	writeLines("idempotency.txt", idempotency)
	writeLines("diagnostics.txt", diagnostics)
	writeLines("doc_tree.txt", trees)
	writeLines("changes.txt", changes)
}
