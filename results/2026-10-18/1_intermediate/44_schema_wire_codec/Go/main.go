package main

import (
	"bufio"
	"cmp"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
)

type kind int

const (
	uint32Kind kind = iota
	uint64Kind
	sint32Kind
	sint64Kind
	boolKind
	fixed32Kind
	sfixed32Kind
	fixed64Kind
	stringKind
	bytesKind
	enumKind
	messageKind
)

type enumMember struct {
	name   string
	number int64
}
type definition struct {
	name    string
	kind    kind
	fields  []*field
	members []enumMember
}
type field struct {
	number                     int64
	name, typeName, group      string
	typ                        *definition
	required, repeated, packed bool
}
type schema map[string]*definition

func (t *definition) wire() int {
	switch t.kind {
	case fixed64Kind:
		return 1
	case stringKind, bytesKind, messageKind:
		return 2
	case fixed32Kind, sfixed32Kind:
		return 5
	default:
		return 0
	}
}
func (t *definition) byName(name string) *field {
	for _, field := range t.fields {
		if field.name == name { return field }
	}
	return nil
}
func (t *definition) byNumber(number int64) *field {
	for _, field := range t.fields {
		if field.number == number { return field }
	}
	return nil
}
func (t *definition) enumName(number int64) (string, bool) {
	for _, member := range t.members {
		if member.number == number { return member.name, true }
	}
	return "", false
}
func (t *definition) enumNumber(name string) (int64, bool) {
	for _, member := range t.members {
		if member.name == name { return member.number, true }
	}
	return 0, false
}

const maxUnsigned int64 = 9_007_199_254_740_991

func (t *definition) contains(number int64) bool {
	switch t.kind {
	case uint32Kind, fixed32Kind:
		return number >= 0 && number <= 4_294_967_295
	case uint64Kind, fixed64Kind:
		return number >= 0 && number <= maxUnsigned
	case sint32Kind, sfixed32Kind:
		return number >= -2_147_483_648 && number <= 2_147_483_647
	case sint64Kind:
		return number >= -4_503_599_627_370_496 && number <= 4_503_599_627_370_495
	default:
		return true
	}
}
func readSchema(input *bufio.Scanner) schema {
	types := make(schema)
	names := []string{"uint32", "uint64", "sint32", "sint64", "bool", "fixed32", "sfixed32", "fixed64", "string", "bytes"}
	for i, name := range names { types[name] = &definition{name: name, kind: kind(i)} }
	var current *definition
	for input.Scan() {
		if input.Text() == "END SCHEMA" { break }
		words := strings.Split(input.Text(), " ")
		switch words[0] {
		case "ENUM", "MESSAGE":
			current = &definition{name: words[1], kind: enumKind}
			if words[0] == "MESSAGE" { current.kind = messageKind }
			types[current.name] = current
		case "VALUE":
			number, _ := strconv.ParseInt(words[2], 10, 64)
			current.members = append(current.members, enumMember{words[1], number})
		case "FIELD":
			number, _ := strconv.ParseInt(words[1], 10, 64)
			field := &field{number: number, typeName: words[2], name: words[3]}
			if len(words) > 4 {
				field.required, field.repeated = words[4] == "REQUIRED", words[4] == "REPEATED"
				field.packed = field.repeated && len(words) == 6
				if words[4] == "ONEOF" { field.group = words[5] }
			}
			current.fields = append(current.fields, field)
		}
	}
	for _, typ := range types {
		slices.SortFunc(typ.fields, func(a, b *field) int { return cmp.Compare(a.number, b.number) })
		slices.SortFunc(typ.members, func(a, b enumMember) int { return cmp.Compare(a.number, b.number) })
		for _, field := range typ.fields { field.typ = types[field.typeName] }
	}
	return types
}

type value interface { isValue() }
type numberValue int64
type booleanValue bool
type binaryValue []byte
func (numberValue) isValue() {}
func (booleanValue) isValue() {}
func (binaryValue) isValue() {}
func (*message) isValue() {}

type unknown struct {
	number, integer int64
	wire            int
	bytes           []byte
}
type message struct {
	typ     *definition
	fields  map[*field][]value
	unknown []unknown
}
func newMessage(typ *definition) *message { return &message{typ: typ, fields: make(map[*field][]value)} }
func (m *message) choose(field *field) {
	if field.group == "" { return }
	for _, other := range m.typ.fields {
		if other != field && other.group == field.group { delete(m.fields, other) }
	}
}
func (m *message) apply(field *field, incoming []value) {
	if len(incoming) == 0 { return }
	m.choose(field)
	old := m.fields[field]
	if field.repeated {
		m.fields[field] = append(old, incoming...)
	} else if field.typ.kind == messageKind && len(old) != 0 {
		old[0].(*message).merge(incoming[0].(*message))
	} else {
		m.fields[field] = incoming
	}
}
func (m *message) merge(incoming *message) {
	for _, field := range m.typ.fields { m.apply(field, incoming.fields[field]) }
	m.unknown = append(m.unknown, incoming.unknown...)
}
func (m *message) required(prefix string) {
	for _, field := range m.typ.fields {
		values, path := m.fields[field], prefix + field.name
		if field.required && len(values) == 0 { fail("missing required field " + path) }
		if field.typ.kind == messageKind {
			for i, value := range values {
				next := path
				if field.repeated { next += fmt.Sprintf("[%d]", i) }
				value.(*message).required(next + ".")
			}
		}
	}
}

type codecError string
func (e codecError) Error() string { return string(e) }
func fail(reason string) { panic(codecError(reason)) }
func byteError(reason string, offset int) { fail(fmt.Sprintf("%s at byte %d", reason, offset)) }
func columnError(reason string, column int) { fail(fmt.Sprintf("%s at column %d", reason, column)) }

func zigzag(number int64) int64 {
	if number >= 0 { return number * 2 }
	return -number * 2 - 1
}
func unzigzag(number int64) int64 {
	if number % 2 == 0 { return number / 2 }
	return -1 - number / 2
}
func putVarint(bytes []byte, number int64) []byte {
	for number >= 128 { bytes = append(bytes, byte(number % 128 + 128)); number /= 128 }
	return append(bytes, byte(number))
}
func encodeElement(bytes []byte, typ *definition, item value) []byte {
	var number int64
	switch item := item.(type) {
	case *message:
		payload := encode(item)
		return append(putVarint(bytes, int64(len(payload))), payload...)
	case binaryValue:
		return append(putVarint(bytes, int64(len(item))), item...)
	case booleanValue:
		if item { number = 1 }
	case numberValue:
		number = int64(item)
	}
	if typ.kind == sint32Kind || typ.kind == sint64Kind { number = zigzag(number) }
	if typ.kind == sfixed32Kind && number < 0 { number += 4_294_967_296 }
	if typ.wire() == 0 { return putVarint(bytes, number) }
	count := 4
	if typ.wire() == 1 { count = 8 }
	for range count { bytes = append(bytes, byte(number % 256)); number /= 256 }
	return bytes
}
func encodeField(field *field, values []value) []byte {
	var bytes []byte
	if len(values) == 0 { return bytes }
	if field.packed {
		var payload []byte
		for _, value := range values { payload = encodeElement(payload, field.typ, value) }
		bytes = putVarint(bytes, field.number * 8 + 2)
		bytes = append(putVarint(bytes, int64(len(payload))), payload...)
	} else {
		for _, value := range values {
			bytes = putVarint(bytes, field.number * 8 + int64(field.typ.wire()))
			bytes = encodeElement(bytes, field.typ, value)
		}
	}
	return bytes
}
func encode(m *message) []byte {
	var bytes []byte
	for _, field := range m.typ.fields { bytes = append(bytes, encodeField(field, m.fields[field])...) }
	for _, unknown := range m.unknown {
		bytes = putVarint(bytes, unknown.number * 8 + int64(unknown.wire))
		if unknown.wire == 0 {
			bytes = putVarint(bytes, unknown.integer)
		} else {
			if unknown.wire == 2 { bytes = putVarint(bytes, int64(len(unknown.bytes))) }
			bytes = append(bytes, unknown.bytes...)
		}
	}
	return bytes
}
func hexNotation(bytes []byte) string {
	if len(bytes) == 0 { return "-" }
	return hex.EncodeToString(bytes)
}
func byteNotation(bytes []byte) string { return "<" + hex.EncodeToString(bytes) + ">" }
func quote(bytes []byte, json bool) string {
	var result strings.Builder
	result.WriteByte('"')
	for _, byte := range bytes {
		switch byte {
		case '"': result.WriteString(`\"`)
		case '\\': result.WriteString(`\\`)
		case '\n': result.WriteString(`\n`)
		case '\t': result.WriteString(`\t`)
		default:
			if byte >= 32 && byte <= 126 { result.WriteByte(byte) } else {
				if json { result.WriteString(`\u00`) } else { result.WriteString(`\x`) }
				fmt.Fprintf(&result, "%02x", byte)
			}
		}
	}
	result.WriteByte('"')
	return result.String()
}
func notation(typ *definition, item value, json bool) string {
	switch item := item.(type) {
	case numberValue:
		text := strconv.FormatInt(int64(item), 10)
		if typ.kind == enumKind {
			text, _ = typ.enumName(int64(item))
			if json { return `"` + text + `"` }
		} else if json && (typ.kind == uint64Kind || typ.kind == sint64Kind || typ.kind == fixed64Kind) { return `"` + text + `"` }
		return text
	case booleanValue:
		return strconv.FormatBool(bool(item))
	case binaryValue:
		if typ.kind == stringKind { return quote(item, json) }
		if json { return `"` + base64.StdEncoding.EncodeToString(item) + `"` }
		return byteNotation(item)
	case *message:
		return messageNotation(item, json)
	default:
		return "(none)"
	}
}
func sequenceNotation(typ *definition, values []value, json bool) string {
	items := make([]string, len(values))
	for i, value := range values { items[i] = notation(typ, value, json) }
	separator := ", "
	if json { separator = "," }
	return "[" + strings.Join(items, separator) + "]"
}
func messageNotation(m *message, json bool) string {
	var items []string
	separator := ", "
	if json { separator = "," }
	for _, field := range m.typ.fields {
		values := m.fields[field]
		if len(values) == 0 { continue }
		key := field.name + ": "
		if json {
			var name strings.Builder
			uppercase := false
			for _, c := range []byte(field.name) {
				if c == '_' { uppercase = true; continue }
				if uppercase && c >= 'a' && c <= 'z' { c -= 'a' - 'A' }
				name.WriteByte(c); uppercase = false
			}
			key = `"` + name.String() + `":`
		}
		if field.repeated { items = append(items, key + sequenceNotation(field.typ, values, json)) } else {
			items = append(items, key + notation(field.typ, values[0], json))
		}
	}
	return "{" + strings.Join(items, separator) + "}"
}
func wireName(wire int) string {
	switch wire { case 0: return "varint"; case 1: return "i64"; case 2: return "len"; default: return "i32" }
}
func rawNotation(raw unknown) string {
	if raw.wire == 0 { return strconv.FormatInt(raw.integer, 10) }
	return byteNotation(raw.bytes)
}
func textContents(m *message, depth int, lines *[]string) {
	indent := strings.Repeat("  ", depth)
	for _, field := range m.typ.fields {
		for _, value := range m.fields[field] {
			if child, ok := value.(*message); ok {
				*lines = append(*lines, indent + field.name + " {")
				textContents(child, depth + 1, lines)
				*lines = append(*lines, indent + "}")
			} else { *lines = append(*lines, indent + field.name + ": " + notation(field.typ, value, false)) }
		}
	}
	for _, unknown := range m.unknown { *lines = append(*lines, fmt.Sprintf("%s%d: %s %s", indent, unknown.number, wireName(unknown.wire), rawNotation(unknown))) }
}
func textMessage(m *message) []string {
	lines := []string{m.typ.name + " {"}
	textContents(m, 1, &lines)
	return append(lines, "}")
}

type raw struct {
	number            int64
	bytes             []byte
	position, payload int
}
type reader struct {
	data          []byte
	position, end int
}
func (r *reader) varint() int64 {
	start := r.position
	var number int64
	for i := range 8 {
		if r.position >= r.end { byteError("truncated varint", start) }
		byte := r.data[r.position]; r.position++
		number += int64(byte & 127) << (7 * i)
		if byte < 128 {
			if number > maxUnsigned { byteError("varint too large", start) }
			return number
		}
	}
	byteError("varint too long", start)
	return 0
}
func (r *reader) read(wire int) raw {
	start := r.position
	if wire == 0 { return raw{number: r.varint(), position: start, payload: start} }
	length := int64(4)
	if wire == 1 { length = 8 } else if wire == 2 { length = r.varint() }
	if length > int64(r.end - r.position) {
		reason := "truncated i32"
		if wire == 1 { reason = "truncated i64" } else if wire == 2 { reason = "length past end" }
		byteError(reason, start)
	}
	payload := r.position; r.position += int(length)
	return raw{bytes: r.data[payload:r.position], position: start, payload: payload}
}
type decoder struct {
	data    []byte
	explain bool
	lines   []string
}
func convert(typ *definition, raw raw) value {
	if typ.kind == stringKind || typ.kind == bytesKind {
		if typ.kind == stringKind {
			for i, byte := range raw.bytes { if byte >= 128 { byteError("invalid string", raw.payload + i) } }
		}
		return binaryValue(raw.bytes)
	}
	number := raw.number
	if typ.wire() == 1 || typ.wire() == 5 {
		if typ.kind == fixed64Kind && (raw.bytes[7] != 0 || raw.bytes[6] >= 32) { byteError("value out of range", raw.position) }
		number = 0
		for i := len(raw.bytes) - 1; i >= 0; i-- { number = number * 256 + int64(raw.bytes[i]) }
	}
	if typ.kind == sint32Kind || typ.kind == sint64Kind { number = unzigzag(number) }
	if typ.kind == sfixed32Kind && number >= 2_147_483_648 { number -= 4_294_967_296 }
	if !typ.contains(number) { byteError("value out of range", raw.position) }
	if typ.kind == boolKind {
		if number > 1 { byteError("value out of range", raw.position) }
		return booleanValue(number == 1)
	}
	if typ.kind == enumKind {
		if _, ok := typ.enumName(number); !ok { byteError("unknown enum number", raw.position) }
	}
	return numberValue(number)
}
func (d *decoder) message(typ *definition, start, end, depth int) *message {
	m := newMessage(typ)
	r := reader{d.data, start, end}
	for r.position < end {
		offset := r.position; tag := r.varint()
		number, wire := tag / 8, int(tag % 8)
		if number == 0 { byteError("invalid field number", offset) }
		if wire != 0 && wire != 1 && wire != 2 && wire != 5 { byteError("invalid wire type", offset) }
		field := typ.byNumber(number)
		packed := field != nil && field.repeated && field.typ.wire() != 2 && wire == 2
		if field != nil && wire != field.typ.wire() && !packed { byteError("wire type mismatch", offset) }
		raw := r.read(wire)
		name := "?"
		if field != nil { name = field.name }
		header := fmt.Sprintf("%s%d %d %s %s", strings.Repeat("  ", depth), offset, number, name, wireName(wire))
		if wire == 2 { header += fmt.Sprintf(" %d", len(raw.bytes)) }
		if field == nil {
			unknown := unknown{number, raw.number, wire, raw.bytes}
			if d.explain { d.lines = append(d.lines, header + " " + rawNotation(unknown)) } else { m.unknown = append(m.unknown, unknown) }
			continue
		}
		var values []value
		if field.typ.kind == messageKind {
			if d.explain { d.lines = append(d.lines, header) }
			values = append(values, d.message(field.typ, raw.payload, raw.payload + len(raw.bytes), depth + 1))
		} else {
			if packed {
				elements := reader{d.data, raw.payload, raw.payload + len(raw.bytes)}
				for elements.position < elements.end { values = append(values, convert(field.typ, elements.read(field.typ.wire()))) }
			} else { values = append(values, convert(field.typ, raw)) }
			if d.explain {
				if packed { header += " packed" }
				for _, value := range values { header += " " + notation(field.typ, value, false) }
				d.lines = append(d.lines, header)
			}
		}
		if !d.explain { m.apply(field, values) }
	}
	return m
}
func decode(typ *definition, bytes []byte, suffix string) (m *message) {
	defer func() {
		if recovered := recover(); recovered != nil {
			if problem, ok := recovered.(codecError); ok { panic(codecError(string(problem) + suffix)) }
			panic(recovered)
		}
	}()
	d := decoder{data: bytes}
	m = d.message(typ, 0, len(bytes), 0)
	m.required("")
	return m
}

type tokenKind int
const (
	symbolToken tokenKind = iota
	integerToken
	nameToken
	stringToken
	bytesToken
	endToken
)
type shape int
const (
	noShape shape = iota
	messageShape
	listShape
	integerShape
	booleanShape
	nameShape
	stringShape
	bytesShape
)
type token struct {
	kind   tokenKind
	column int
	symbol byte
	name   string
	number int64
	bytes  []byte
}
func (t token) shape() shape {
	switch t.kind {
	case integerToken: return integerShape
	case stringToken: return stringShape
	case bytesToken: return bytesShape
	case nameToken:
		if t.name == "true" || t.name == "false" { return booleanShape }
		return nameShape
	case symbolToken:
		if t.symbol == '{' { return messageShape }
		if t.symbol == '[' { return listShape }
	}
	return noShape
}
func digit(c byte) bool { return c >= '0' && c <= '9' }
func letter(c byte) bool { return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' }
func hexDigit(c byte) int {
	if digit(c) { return int(c - '0') }
	if c >= 'a' && c <= 'f' { return int(c - 'a') + 10 }
	return -1
}
func tokenize(source string) []token {
	var tokens []token
	for at := 0; at < len(source); {
		c := source[at]
		if c == ' ' { at++; continue }
		start := at; at++
		t := token{kind: symbolToken, symbol: c, column: start + 1}
		switch {
		case strings.ContainsRune("{}[]:,", rune(c)):
		case c == '"':
			t.kind = stringToken
			for at < len(source) && source[at] != '"' {
				b := source[at]; at++
				if b == '\\' {
					if at == len(source) { columnError("syntax error", t.column) }
					escaped := source[at]; at++
					switch escaped {
					case '"', '\\': b = escaped
					case 'n': b = '\n'
					case 't': b = '\t'
					case 'x':
						if at + 1 >= len(source) { columnError("syntax error", t.column) }
						high, low := hexDigit(source[at]), hexDigit(source[at + 1])
						if high < 0 || high > 7 || low < 0 { columnError("syntax error", t.column) }
						b = byte(high * 16 + low); at += 2
					default: columnError("syntax error", t.column)
					}
				}
				t.bytes = append(t.bytes, b)
			}
			if at == len(source) { columnError("syntax error", t.column) }
			at++
		case c == '<':
			t.kind = bytesToken
			relative := strings.IndexByte(source[at:], '>')
			if relative < 0 || relative % 2 != 0 { columnError("syntax error", t.column) }
			end := at + relative
			for at < end {
				high, low := hexDigit(source[at]), hexDigit(source[at + 1])
				if high < 0 || low < 0 { columnError("syntax error", t.column) }
				t.bytes = append(t.bytes, byte(high * 16 + low)); at += 2
			}
			at++
		case c == '-' || digit(c):
			t.kind = integerToken
			if c == '-' && (at == len(source) || !digit(source[at])) { columnError("syntax error", t.column) }
			for at < len(source) && digit(source[at]) { at++ }
			t.number, _ = strconv.ParseInt(source[start:at], 10, 64)
		case letter(c) || c == '_':
			t.kind = nameToken
			for at < len(source) && (letter(source[at]) || digit(source[at]) || source[at] == '_') { at++ }
			t.name = source[start:at]
		default:
			columnError("syntax error", t.column)
		}
		tokens = append(tokens, t)
	}
	return append(tokens, token{kind: endToken, column: len(source) + 1})
}
type literal struct {
	tokens   []token
	position int
}
func newLiteral(source string) *literal { return &literal{tokens: tokenize(source)} }
func (p *literal) next() token { return p.tokens[p.position] }
func (p *literal) symbol(c byte) bool { return p.next().kind == symbolToken && p.next().symbol == c }
func (p *literal) expect(c byte) {
	if !p.symbol(c) { columnError("syntax error", p.next().column) }
	p.position++
}
func (p *literal) end() {
	if p.next().kind != endToken { columnError("syntax error", p.next().column) }
}
func (p *literal) require(wanted shape) {
	if p.next().shape() == noShape { columnError("syntax error", p.next().column) }
	if p.next().shape() != wanted { columnError("type mismatch", p.next().column) }
}
func (p *literal) element(typ *definition) value {
	wanted := integerShape
	switch typ.kind {
	case boolKind: wanted = booleanShape
	case stringKind: wanted = stringShape
	case bytesKind: wanted = bytesShape
	case enumKind: wanted = nameShape
	case messageKind: wanted = messageShape
	}
	p.require(wanted)
	if wanted == messageShape { return p.message(typ) }
	t := p.next(); p.position++
	switch wanted {
	case integerShape:
		if !typ.contains(t.number) { columnError("out of range", t.column) }
		return numberValue(t.number)
	case booleanShape:
		return booleanValue(t.name == "true")
	case nameShape:
		number, ok := typ.enumNumber(t.name)
		if !ok { columnError("unknown enum value", t.column) }
		return numberValue(number)
	default:
		return binaryValue(t.bytes)
	}
}
func (p *literal) fieldValue(field *field) []value {
	if !field.repeated { return []value{p.element(field.typ)} }
	p.require(listShape); p.expect('[')
	var values []value
	if !p.symbol(']') {
		values = append(values, p.element(field.typ))
		for p.symbol(',') { p.position++; values = append(values, p.element(field.typ)) }
	}
	p.expect(']')
	return values
}
func (p *literal) message(typ *definition) *message {
	p.expect('{')
	m := newMessage(typ)
	seen, groups := make(map[*field]bool), make(map[string]bool)
	if !p.symbol('}') {
		for {
			t := p.next()
			if t.kind != nameToken { columnError("syntax error", t.column) }
			field := typ.byName(t.name)
			if field == nil { columnError("unknown field", t.column) }
			if seen[field] { columnError("duplicate field", t.column) }
			if field.group != "" && groups[field.group] { columnError("oneof conflict", t.column) }
			seen[field], groups[field.group] = true, true
			p.position++; p.expect(':')
			m.fields[field] = p.fieldValue(field)
			if !p.symbol(',') { break }
			p.position++
		}
	}
	closing := p.next(); p.expect('}')
	for _, field := range typ.fields {
		if field.required && !seen[field] { columnError("missing required field " + field.name, closing.column) }
	}
	return m
}

type segment struct {
	field   *field
	index   int
	indexed bool
}
func parsePath(typ *definition, source string) []segment {
	var path []segment
	parts := strings.Split(source, ".")
	for i, part := range parts {
		name, index, indexed := part, 0, false
		if open := strings.IndexByte(part, '['); open >= 0 {
			if !strings.HasSuffix(part, "]") { fail("invalid path") }
			digits := part[open + 1:len(part) - 1]
			if len(digits) == 0 || len(digits) > 6 { fail("invalid path") }
			for j := range len(digits) { if !digit(digits[j]) { fail("invalid path") } }
			index, _ = strconv.Atoi(digits); indexed = true; name = part[:open]
		}
		field := typ.byName(name)
		if field == nil || indexed && !field.repeated { fail("invalid path") }
		if i + 1 < len(parts) && (field.typ.kind != messageKind || field.repeated && !indexed) { fail("invalid path") }
		path = append(path, segment{field, index, indexed}); typ = field.typ
	}
	return path
}
func getPath(m *message, path []segment) string {
	for i, segment := range path {
		var values []value
		if m != nil { values = m.fields[segment.field] }
		if i + 1 == len(path) && segment.field.repeated && !segment.indexed { return sequenceNotation(segment.field.typ, values, false) }
		var selected value
		if segment.index < len(values) { selected = values[segment.index] }
		if i + 1 == len(path) { return notation(segment.field.typ, selected, false) }
		if selected == nil { m = nil } else { m = selected.(*message) }
	}
	return "(none)"
}
func editPath(m *message, path []segment, replacement *[]value) {
	for i, segment := range path {
		field, values := segment.field, m.fields[segment.field]
		if i + 1 == len(path) {
			if segment.indexed {
				if segment.index >= len(values) {
					if replacement != nil { fail("index out of range") }
				} else if replacement == nil {
					m.fields[field] = slices.Delete(values, segment.index, segment.index + 1)
				} else { values[segment.index] = (*replacement)[0] }
			} else if replacement == nil { delete(m.fields, field) } else { m.choose(field); m.fields[field] = *replacement }
			return
		}
		if segment.index >= len(values) {
			if replacement == nil { return }
			if segment.indexed { fail("index out of range") }
			m.choose(field); values = []value{newMessage(field.typ)}; m.fields[field] = values
		}
		m = values[segment.index].(*message)
	}
}
func equalValue(a, b value) bool {
	switch a := a.(type) {
	case numberValue: return a == b.(numberValue)
	case booleanValue: return a == b.(booleanValue)
	case binaryValue: return slices.Equal(a, b.(binaryValue))
	default: return false
	}
}
func differences(a, b *message, prefix string, lines *[]string) {
	for _, field := range a.typ.fields {
		x, y := a.fields[field], b.fields[field]
		for i := range max(len(x), len(y)) {
			path := prefix + field.name
			if field.repeated { path += fmt.Sprintf("[%d]", i) }
			if i < len(x) && i < len(y) && field.typ.kind == messageKind {
				differences(x[i].(*message), y[i].(*message), path + ".", lines)
			} else if i >= len(x) || i >= len(y) || !equalValue(x[i], y[i]) {
				var left, right value
				if i < len(x) { left = x[i] }
				if i < len(y) { right = y[i] }
				*lines = append(*lines, path + ": " + notation(field.typ, left, false) + " -> " + notation(field.typ, right, false))
			}
		}
	}
}
func schemaFields(typ *definition, chain []*definition, lines *[]string) {
	chain = append(chain, typ)
	for _, field := range typ.fields {
		mode := ""
		if field.required { mode = "required " } else if field.packed { mode = "repeated packed " } else if field.repeated { mode = "repeated " } else if field.group != "" { mode = "oneof " + field.group + " " }
		line := fmt.Sprintf("%s%d %s: %s%s", strings.Repeat("  ", len(chain)), field.number, field.name, mode, field.typ.name)
		if field.typ.kind == enumKind {
			var members []string
			for _, member := range field.typ.members { members = append(members, fmt.Sprintf("%s=%d", member.name, member.number)) }
			line += " (" + strings.Join(members, ", ") + ")"
		}
		recursive := field.typ.kind == messageKind && slices.Contains(chain, field.typ)
		if recursive { line += " (recursive)" }
		*lines = append(*lines, line)
		if field.typ.kind == messageKind && !recursive { schemaFields(field.typ, chain, lines) }
	}
}
func parseHex(source string) []byte {
	if source == "-" { return nil }
	if len(source) == 0 || len(source) % 2 != 0 { fail("invalid hex") }
	for i := range len(source) { if hexDigit(source[i]) < 0 { fail("invalid hex") } }
	bytes, _ := hex.DecodeString(source)
	return bytes
}
func rest(source string, count int) string { return strings.SplitN(source, " ", count + 1)[count] }
func (s schema) perform(source string) []string {
	words := strings.Split(source, " ")
	command, count := words[0], 0
	switch command {
	case "VARINT", "ZIGZAG", "SCHEMA": count = 2
	case "ENCODE", "SIZE", "DECODE", "LITERAL", "JSON", "CANON", "EXPLAIN": count = 3
	case "GET", "CLEAR", "MERGE", "DIFF": count = 4
	case "PATCH": count = 5
	default: fail("unknown command")
	}
	flexible := command == "ENCODE" || command == "SIZE" || command == "PATCH"
	if len(words) < count || !flexible && len(words) != count { fail("wrong number of arguments") }
	if command == "VARINT" || command == "ZIGZAG" {
		digits := strings.TrimPrefix(words[1], "-")
		if len(digits) == 0 || len(digits) > 18 { fail("invalid number") }
		for i := range len(digits) { if !digit(digits[i]) { fail("invalid number") } }
		number, _ := strconv.ParseInt(words[1], 10, 64)
		if command == "VARINT" {
			if number < 0 || number > maxUnsigned { fail("invalid number") }
			return []string{hexNotation(putVarint(nil, number))}
		}
		if !s["sint64"].contains(number) { fail("invalid number") }
		z := zigzag(number)
		return []string{fmt.Sprintf("%d %s", z, hexNotation(putVarint(nil, z)))}
	}
	typ := s[words[1]]
	if typ == nil || typ.kind != messageKind { fail("unknown message type") }
	if command == "SCHEMA" {
		lines := []string{typ.name}; schemaFields(typ, nil, &lines); return lines
	}
	if command == "ENCODE" || command == "SIZE" {
		parser := newLiteral(rest(source, 2)); m := parser.message(typ); parser.end()
		bytes := encode(m)
		if command == "ENCODE" { return []string{hexNotation(bytes)} }
		line := strconv.Itoa(len(bytes))
		for _, field := range typ.fields {
			if values := m.fields[field]; len(values) != 0 { line += fmt.Sprintf(" %s=%d", field.name, len(encodeField(field, values))) }
		}
		return []string{line}
	}
	first := parseHex(words[2])
	var second []byte
	if command == "MERGE" || command == "DIFF" { second = parseHex(words[3]) }
	var path []segment
	if command == "GET" || command == "PATCH" || command == "CLEAR" { path = parsePath(typ, words[3]) }
	if command == "EXPLAIN" {
		d := decoder{data: first, explain: true}; d.message(typ, 0, len(first), 0)
		if len(first) == 0 { return []string{"(empty)"} }
		return d.lines
	}
	if command == "DIFF" {
		a := decode(typ, first, " in first"); b := decode(typ, second, " in second")
		var lines []string; differences(a, b, "", &lines)
		if len(lines) == 0 { return []string{"SAME"} }
		return lines
	}
	if command == "MERGE" { first = append(first, second...) }
	m := decode(typ, first, "")
	switch command {
	case "DECODE", "MERGE": return textMessage(m)
	case "LITERAL", "JSON": return []string{messageNotation(m, command == "JSON")}
	case "GET": return []string{getPath(m, path)}
	case "PATCH":
		parser := newLiteral(rest(source, 4)); last := path[len(path) - 1]
		var replacement []value
		if last.field.repeated && !last.indexed { replacement = parser.fieldValue(last.field) } else { replacement = []value{parser.element(last.field.typ)} }
		parser.end(); editPath(m, path, &replacement); m.required("")
	case "CLEAR":
		editPath(m, path, nil); m.required("")
	}
	return []string{hexNotation(encode(m))}
}
func (s schema) execute(source string) (lines []string) {
	defer func() {
		if recovered := recover(); recovered != nil {
			if problem, ok := recovered.(codecError); ok { lines = []string{"ERROR " + string(problem)} } else { panic(recovered) }
		}
	}()
	return s.perform(source)
}
func main() {
	input := bufio.NewScanner(os.Stdin)
	types := readSchema(input)
	input.Scan(); count, _ := strconv.Atoi(input.Text())
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	for range count {
		input.Scan()
		for _, line := range types.execute(input.Text()) { fmt.Fprintln(output, line) }
	}
}
