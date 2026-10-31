package main

import (
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type FieldSpec struct{ Name, Type string }

var fieldSpecs = []FieldSpec{
	{"frame.number", "integer"},
	{"frame.time", "integer"},
	{"frame.len", "integer"},
	{"frame.protocols", "string"},
	{"frame.malformed", "string"},
	{"frame.bad_checksum", "presence"},
	{"eth.dst", "mac"},
	{"eth.src", "mac"},
	{"eth.type", "hex4"},
	{"arp.opcode", "integer"},
	{"arp.src.hw", "mac"},
	{"arp.src.ip", "ipv4"},
	{"arp.dst.hw", "mac"},
	{"arp.dst.ip", "ipv4"},
	{"ip.hdr_len", "integer"},
	{"ip.tos", "hex2"},
	{"ip.len", "integer"},
	{"ip.id", "hex4"},
	{"ip.flags.df", "integer"},
	{"ip.flags.mf", "integer"},
	{"ip.frag_offset", "integer"},
	{"ip.ttl", "integer"},
	{"ip.proto", "integer"},
	{"ip.checksum", "hex4"},
	{"ip.checksum.status", "string"},
	{"ip.src", "ipv4"},
	{"ip.dst", "ipv4"},
	{"ip.fragment", "presence"},
	{"icmp.type", "integer"},
	{"icmp.code", "integer"},
	{"icmp.checksum", "hex4"},
	{"icmp.checksum.status", "string"},
	{"icmp.id", "integer"},
	{"icmp.seq", "integer"},
	{"udp.srcport", "integer"},
	{"udp.dstport", "integer"},
	{"udp.length", "integer"},
	{"udp.checksum", "hex4"},
	{"udp.checksum.status", "string"},
	{"tcp.srcport", "integer"},
	{"tcp.dstport", "integer"},
	{"tcp.stream", "integer"},
	{"tcp.seq", "integer"},
	{"tcp.seq_raw", "integer"},
	{"tcp.ack", "integer"},
	{"tcp.ack_raw", "integer"},
	{"tcp.hdr_len", "integer"},
	{"tcp.flags", "hex2"},
	{"tcp.flags.fin", "integer"},
	{"tcp.flags.syn", "integer"},
	{"tcp.flags.rst", "integer"},
	{"tcp.flags.psh", "integer"},
	{"tcp.flags.ack", "integer"},
	{"tcp.flags.urg", "integer"},
	{"tcp.window", "integer"},
	{"tcp.window.calc", "integer"},
	{"tcp.checksum", "hex4"},
	{"tcp.checksum.status", "string"},
	{"tcp.urgent", "integer"},
	{"tcp.option", "string"},
	{"tcp.options.mss", "integer"},
	{"tcp.options.wscale", "integer"},
	{"tcp.options.malformed", "presence"},
	{"tcp.len", "integer"},
	{"tcp.analysis.retransmission", "presence"},
	{"tcp.analysis.out_of_order", "presence"},
	{"tcp.analysis.lost_segment", "presence"},
	{"tcp.analysis.duplicate_ack", "presence"},
	{"dns.id", "hex4"},
	{"dns.flags", "hex4"},
	{"dns.flags.response", "integer"},
	{"dns.flags.opcode", "integer"},
	{"dns.flags.rcode", "integer"},
	{"dns.count.queries", "integer"},
	{"dns.count.answers", "integer"},
	{"dns.count.auth_rr", "integer"},
	{"dns.count.add_rr", "integer"},
	{"dns.qry.name", "string"},
	{"dns.qry.type", "integer"},
	{"dns.answer", "string"},
	{"dns.authority", "string"},
	{"dns.additional", "string"},
	{"dns.a", "ipv4"},
	{"data.len", "integer"},
}
var aliases = map[string][3]string{"eth.addr": {"mac", "eth.dst", "eth.src"}, "ip.addr": {"ipv4",
	"ip.src", "ip.dst"}, "udp.port": {"integer", "udp.srcport", "udp.dstport"}, "tcp.port": {"integer",
	"tcp.srcport", "tcp.dstport"}}
var protocolNames = []string{"eth", "arp", "ip", "icmp", "udp", "tcp", "dns", "data"}
var protocolLabels = map[string]string{"eth": "ETH", "arp": "ARP", "ip": "IPv4", "icmp": "ICMP", "udp": "UDP", "tcp": "TCP", "dns": "DNS"}
var checksumLayers = [][2]string{{"ip", "IPv4"}, {"icmp", "ICMP"}, {"udp", "UDP"}, {"tcp", "TCP"}}
var flagNames = []string{"FIN", "SYN", "RST", "PSH", "ACK", "URG", "ECE", "CWR"}

func contains(values []string, value string) bool {
	for _, v := range values {
		if v == value {
			return true
		}
	}
	return false
}
func fieldType(name string) string {
	for _, spec := range fieldSpecs {
		if spec.Name == name {
			return spec.Type
		}
	}
	if alias, ok := aliases[name]; ok {
		return alias[0]
	}
	if contains(protocolNames, name) {
		return "presence"
	}
	return ""
}
func fieldValues(p *Packet, name string) []FieldValue {
	if alias, ok := aliases[name]; ok {
		values := append([]FieldValue(nil), p.Fields[alias[1]]...)
		return append(values, p.Fields[alias[2]]...)
	}
	return p.Fields[name]
}
func seconds(t int64) string { return fmt.Sprintf("%d.%06d", t/1000000, t%1000000) }
func optionalNumber(value int64) string {
	if value < 0 {
		return "-"
	}
	return fmt.Sprint(value)
}
func optionalPacket(number int) string {
	if number == 0 {
		return "-"
	}
	return fmt.Sprint(number)
}
func notation(kind string, v FieldValue) string {
	switch kind {
	case "hex2":
		return fmt.Sprintf("0x%02x", v.Number)
	case "hex4":
		return fmt.Sprintf("0x%04x", v.Number)
	case "ipv4":
		return ipv4Notation(v.Number)
	case "mac":
		return macNotation(v.Number)
	case "string":
		return v.Text
	default:
		return fmt.Sprint(v.Number)
	}
}
func shown(p *Packet, name string) string { return notation(fieldType(name), p.Fields[name][0]) }
func endpointText(e Endpoint) string {
	text := ipv4Notation(e.Address)
	if e.Port >= 0 {
		text += fmt.Sprintf(":%d", e.Port)
	}
	return text
}
func dissectOne(p *Packet, name string, payload []byte) (layer *Layer, reason string) {
	defer func() {
		if caught := recover(); caught != nil {
			if malformed, ok := caught.(Malformed); ok {
				layer = nil
				reason = string(malformed)
			} else {
				panic(caught)
			}
		}
	}()
	switch name {
	case "eth":
		layer = dissectEthernet(payload)
	case "arp":
		layer = dissectARP(payload)
	case "ip":
		layer = dissectIPv4(payload)
	case "icmp":
		layer = dissectICMP(payload)
	case "udp":
		layer = dissectUDP(payload, p.Fields.Num("ip.src"), p.Fields.Num("ip.dst"))
	case "tcp":
		layer = dissectTCP(payload, p.Fields.Num("ip.src"), p.Fields.Num("ip.dst"))
	default:
		layer = dissectDNS(payload)
	}
	return
}
func dissect(p *Packet, base int64) {
	reason := p.Error
	if reason == "" {
		name, payload := "eth", p.Data
		for {
			p.Layers = append(p.Layers, name)
			l, error := dissectOne(p, name, payload)
			if error != "" {
				reason = error
				break
			}
			for field, values := range l.Fields {
				p.Fields[field] = values
			}
			if l.Next == "" {
				p.Remaining = l.Remaining
				break
			}
			name, payload = l.Next, l.Payload
		}
	}
	if reason == "" && len(p.Remaining) > 0 {
		p.Layers = append(p.Layers, "data")
		p.Fields.N("data.len", int64(len(p.Remaining)))
	}
	p.Fields.N("frame.number", int64(p.Number))
	p.Fields.N("frame.time", p.Time-base)
	p.Fields.N("frame.len", int64(p.Length))
	if len(p.Layers) > 0 {
		p.Fields.S("frame.protocols", strings.Join(p.Layers, ":"))
	}
	if reason != "" {
		p.Fields.S("frame.malformed", reason)
	}
	for _, layer := range checksumLayers {
		if p.Fields.Text(layer[0]+".checksum.status") == "bad" {
			p.Fields.N("frame.bad_checksum", 1)
			break
		}
	}
}
func flagNotation(flags int64) string {
	names := []string{}
	for bit, name := range flagNames {
		if flags>>uint(bit)&1 == 1 {
			names = append(names, name)
		}
	}
	if len(names) == 0 {
		return "<None>"
	}
	return strings.Join(names, ", ")
}
func optionSummary(options []FieldValue) string {
	text := ""
	for _, option := range options {
		words := strings.Fields(option.Text)
		switch words[0] {
		case "MSS":
			text += " MSS=" + words[1]
		case "WS":
			shift, _ := strconv.Atoi(words[1])
			text += fmt.Sprintf(" WS=%d", int64(1)<<uint(shift))
		case "SACK_PERM":
			text += " SACK_PERM"
		case "TS":
			text += " TSval=" + words[1] + " TSecr=" + words[2]
		}
	}
	return text
}
func basicInfo(p *Packet, protocol string, duplicate map[int][2]int) string {
	f := p.Fields
	if f.Exists("frame.malformed") {
		return f.Text("frame.malformed")
	}
	switch protocol {
	case "ETH":
		return "EtherType " + shown(p, "eth.type")
	case "ARP":
		switch f.Num("arp.opcode") {
		case 1:
			return "Who has " + shown(p, "arp.dst.ip") + "? Tell " + shown(p, "arp.src.ip")
		case 2:
			return shown(p, "arp.src.ip") + " is at " + shown(p, "arp.src.hw")
		default:
			return fmt.Sprintf("Opcode %d", f.Num("arp.opcode"))
		}
	case "IPv4":
		if !f.Exists("ip.fragment") {
			return fmt.Sprintf("Protocol %d", f.Num("ip.proto"))
		}
		text := fmt.Sprintf("Fragment id=%s off=%d", shown(p, "ip.id"), f.Num("ip.frag_offset"))
		if f.Num("ip.flags.mf") == 1 {
			text += " MF"
		}
		return text
	case "ICMP":
		t := f.Num("icmp.type")
		echo := fmt.Sprintf("id=%d seq=%d", f.Num("icmp.id"), f.Num("icmp.seq"))
		if t == 8 {
			return "Echo request " + echo
		}
		if t == 0 {
			return "Echo reply " + echo
		}
		return fmt.Sprintf("Type %d code %d", t, f.Num("icmp.code"))
	case "UDP":
		return fmt.Sprintf("%d -> %d Len=%d", f.Num("udp.srcport"), f.Num("udp.dstport"), f.Num("udp.length")-8)
	case "TCP":
		mark := ""
		if f.Exists("tcp.analysis.duplicate_ack") {
			record := duplicate[p.Number]
			mark = fmt.Sprintf("[TCP Dup ACK %d#%d] ", record[0], record[1])
		} else {
			labels := []string{"[TCP Retransmission] ", "[TCP Out-Of-Order] ", "[TCP Previous segment not captured] "}
			for i, name := range marks[:3] {
				if f.Exists("tcp.analysis." + name) {
					mark = labels[i]
					break
				}
			}
		}
		text := mark + fmt.Sprintf("%d -> %d [%s] Seq=%d", f.Num("tcp.srcport"), f.Num("tcp.dstport"), flagNotation(f.Num("tcp.flags")), f.Num("tcp.seq"))
		if f.Num("tcp.flags.ack") == 1 {
			text += fmt.Sprintf(" Ack=%d", f.Num("tcp.ack"))
		}
		return text + fmt.Sprintf(" Win=%d Len=%d", f.Num("tcp.window.calc"), f.Num("tcp.len")) + optionSummary(f["tcp.option"])
	default:
		kind := "Query"
		if f.Num("dns.flags.response") == 1 {
			kind = "Response"
		}
		parts := []string{kind, shown(p, "dns.id")}
		if rcode := f.Num("dns.flags.rcode"); rcode != 0 {
			parts = append(parts, rcodeName(rcode))
		}
		for i, name := range f["dns.qry.name"] {
			parts = append(parts, typeName(f["dns.qry.type"][i].Number), name.Text)
		}
		for _, record := range f["dns.answer"] {
			fields := strings.SplitN(record.Text, " ", 5)
			parts = append(parts, fields[1], fields[4])
		}
		return strings.Join(parts, " ")
	}
}
func summaryLine(p *Packet, duplicate map[int][2]int) string {
	source, destination := "-", "-"
	if p.Fields.Exists("ip.src") {
		source, destination = shown(p, "ip.src"), shown(p, "ip.dst")
	} else if p.Fields.Exists("eth.src") {
		source, destination = shown(p, "eth.src"), shown(p, "eth.dst")
	}
	protocol := "DUMP"
	for _, name := range p.Layers {
		if name != "data" {
			protocol = protocolLabels[name]
		}
	}
	info := basicInfo(p, protocol, duplicate)
	if p.Fields.Exists("tcp.options.malformed") {
		info += " [bad TCP options]"
	}
	for _, layer := range checksumLayers {
		if p.Fields.Text(layer[0]+".checksum.status") == "bad" {
			info += " [bad " + layer[1] + " checksum]"
		}
	}
	return fmt.Sprintf("%d %s %s -> %s %s %d %s", p.Number, seconds(p.Fields.Num("frame.time")), source, destination, protocol, p.Length, info)
}

type FilterError string

func filterFail(message string) { panic(FilterError(message)) }

type Token struct {
	Kind, Text string
	Column     int
}

func wordCharacter(b byte) bool {
	return b >= 'A' && b <= 'Z' || b >= 'a' && b <= 'z' || b >= '0' && b <= '9' || b == '.' || b == '_' || b == ':'
}
func tokenize(expression string) []Token {
	tokens := []Token{}
	for index := 0; index < len(expression); {
		c := expression[index]
		column := index + 1
		if c == ' ' {
			index++
			continue
		}
		if index+1 < len(expression) && contains([]string{"==", "!=", "<=", ">=", "&&", "||"}, expression[index:index+2]) {
			t := expression[index : index+2]
			tokens = append(tokens, Token{t, t, column})
			index += 2
			continue
		}
		if strings.ContainsRune("()!<>", rune(c)) {
			t := string(c)
			tokens = append(tokens, Token{t, t, column})
			index++
			continue
		}
		if c == '"' {
			relative := strings.IndexByte(expression[index+1:], '"')
			if relative < 0 {
				filterFail(fmt.Sprintf("unterminated string at column %d", column))
			}
			end := index + relative + 2
			tokens = append(tokens, Token{"string", expression[index:end], column})
			index = end
			continue
		}
		if wordCharacter(c) {
			end := index
			for end < len(expression) && wordCharacter(expression[end]) {
				end++
			}
			word := expression[index:end]
			kind := map[string]string{"and": "&&", "or": "||", "not": "!"}[word]
			if kind == "" {
				kind = "word"
			}
			tokens = append(tokens, Token{kind, word, column})
			index = end
			continue
		}
		filterFail(fmt.Sprintf("invalid character '%c' at column %d", c, column))
	}
	return tokens
}
func parseLiteral(kind string, t Token) (FieldValue, bool) {
	if kind == "string" {
		if t.Kind == "string" {
			return FieldValue{Text: t.Text[1 : len(t.Text)-1]}, true
		}
		return FieldValue{}, false
	}
	if t.Kind != "word" {
		return FieldValue{}, false
	}
	text := t.Text
	if kind == "integer" || kind == "hex2" || kind == "hex4" {
		if regexp.MustCompile(`^[0-9]{1,15}$`).MatchString(text) {
			value, _ := strconv.ParseInt(text, 10, 64)
			return FieldValue{Number: value}, true
		}
		if regexp.MustCompile(`^0x[0-9a-fA-F]{1,12}$`).MatchString(text) {
			value, _ := strconv.ParseInt(text[2:], 16, 64)
			return FieldValue{Number: value}, true
		}
		return FieldValue{}, false
	}
	separator, count, base, pattern := ".", 4, 10, `^[0-9]{1,3}$`
	if kind == "mac" {
		separator, count, base, pattern = ":", 6, 16, `^[0-9a-fA-F]{2}$`
	}
	parts := strings.Split(text, separator)
	if len(parts) != count {
		return FieldValue{}, false
	}
	number := int64(0)
	for _, part := range parts {
		if !regexp.MustCompile(pattern).MatchString(part) {
			return FieldValue{}, false
		}
		v, _ := strconv.ParseInt(part, base, 64)
		if v > 255 {
			return FieldValue{}, false
		}
		number = number*256 + v
	}
	return FieldValue{Number: number}, true
}
func unexpected(t Token) { filterFail(fmt.Sprintf("unexpected '%s' at column %d", t.Text, t.Column)) }

type FilterNode struct {
	Kind, Field, Operator string
	Value                 FieldValue
	Left, Right           *FilterNode
}
type FilterParser struct {
	Tokens   []Token
	Position int
}

func (p *FilterParser) Next() string {
	if p.Position >= len(p.Tokens) {
		return ""
	}
	return p.Tokens[p.Position].Kind
}
func (p *FilterParser) Take() Token {
	if p.Position >= len(p.Tokens) {
		filterFail("unexpected end of filter")
	}
	t := p.Tokens[p.Position]
	p.Position++
	return t
}
func (p *FilterParser) Expression() *FilterNode {
	node := p.Product()
	for p.Next() == "||" {
		p.Take()
		node = &FilterNode{Kind: "or", Left: node, Right: p.Product()}
	}
	return node
}
func (p *FilterParser) Product() *FilterNode {
	node := p.Negation()
	for p.Next() == "&&" {
		p.Take()
		node = &FilterNode{Kind: "and", Left: node, Right: p.Negation()}
	}
	return node
}
func (p *FilterParser) Negation() *FilterNode {
	if p.Next() == "!" {
		p.Take()
		return &FilterNode{Kind: "not", Left: p.Negation()}
	}
	token := p.Take()
	if token.Kind == "(" {
		node := p.Expression()
		closing := p.Take()
		if closing.Kind != ")" {
			unexpected(closing)
		}
		return node
	}
	if token.Kind != "word" {
		unexpected(token)
	}
	name := token.Text
	kind := fieldType(name)
	if kind == "" {
		filterFail("unknown field " + name)
	}
	if !contains([]string{"==", "!=", "<", ">", "<=", ">="}, p.Next()) {
		return &FilterNode{Kind: "exists", Field: name}
	}
	operator := p.Take().Kind
	if kind == "presence" || kind == "string" && operator != "==" && operator != "!=" {
		filterFail("operator " + operator + " not allowed for " + name)
	}
	literal := p.Take()
	if literal.Kind != "word" && literal.Kind != "string" {
		unexpected(literal)
	}
	value, ok := parseLiteral(kind, literal)
	if !ok {
		filterFail("invalid value " + literal.Text + " for " + name)
	}
	return &FilterNode{Kind: "compare", Field: name, Operator: operator, Value: value}
}
func evaluate(node *FilterNode, p *Packet) bool {
	switch node.Kind {
	case "or":
		return evaluate(node.Left, p) || evaluate(node.Right, p)
	case "and":
		return evaluate(node.Left, p) && evaluate(node.Right, p)
	case "not":
		return !evaluate(node.Left, p)
	case "exists":
		if contains(protocolNames, node.Field) {
			return contains(p.Layers, node.Field)
		}
		return len(fieldValues(p, node.Field)) > 0
	}
	values := fieldValues(p, node.Field)
	if len(values) == 0 {
		return false
	}
	if node.Operator == "!=" {
		for _, v := range values {
			if v == node.Value {
				return false
			}
		}
		return true
	}
	for _, v := range values {
		if node.Operator == "==" && v == node.Value || node.Operator == "<" && v.Number < node.Value.Number || node.Operator == ">" && v.Number > node.Value.Number || node.Operator == "<=" && v.Number <= node.Value.Number || node.Operator == ">=" && v.Number >= node.Value.Number {
			return true
		}
	}
	return false
}
func filterBlock(expression string, packets []*Packet, summaries []string) (lines []string) {
	lines = []string{"", "filter " + expression}
	defer func() {
		if caught := recover(); caught != nil {
			if error, ok := caught.(FilterError); ok {
				lines = append(lines, "error: "+string(error))
			} else {
				panic(caught)
			}
		}
	}()
	parser := FilterParser{Tokens: tokenize(expression)}
	node := parser.Expression()
	if parser.Position < len(parser.Tokens) {
		unexpected(parser.Tokens[parser.Position])
	}
	count := 0
	for _, p := range packets {
		if evaluate(node, p) {
			lines = append(lines, summaries[p.Number-1])
			count++
		}
	}
	return append(lines, fmt.Sprintf("matched %d of %d", count, len(packets)))
}
func detailLines(packets []*Packet, number int) []string {
	if number < 1 || number > len(packets) {
		return []string{fmt.Sprintf("packet %d not found", number)}
	}
	p := packets[number-1]
	lines := []string{fmt.Sprintf("packet %d", number)}
	layers := append([]string{"frame"}, p.Layers...)
	for _, layer := range layers {
		lines = append(lines, layer)
		for _, spec := range fieldSpecs {
			if !strings.HasPrefix(spec.Name, layer+".") {
				continue
			}
			for _, value := range p.Fields[spec.Name] {
				text := "  " + spec.Name
				if spec.Type != "presence" {
					text += " = " + notation(spec.Type, value)
				}
				lines = append(lines, text)
			}
		}
		if layer == "data" {
			for _, text := range hexDumpLines(p.Remaining) {
				lines = append(lines, "  "+text)
			}
		}
	}
	return lines
}
func protocolStats(packets []*Packet) []string {
	bytes := 0
	for _, p := range packets {
		bytes += p.Length
	}
	lines := []string{fmt.Sprintf("packets %d", len(packets)), fmt.Sprintf("bytes %d", bytes), "duration " + seconds(packets[len(packets)-1].Time-packets[0].Time),
		"hierarchy"}
	for _, h := range []struct {
		Name   string
		Indent int
	}{{"eth", 0}, {"arp", 2}, {"ip", 2}, {"icmp", 4}, {"udp", 4}, {"dns", 6}, {"tcp", 4}} {
		count, bytes := 0, 0
		for _, p := range packets {
			if contains(p.Layers, h.Name) {
				count++
				bytes += p.Length
			}
		}
		lines = append(lines, fmt.Sprintf("%s%s %d %d", strings.Repeat(" ", h.Indent), h.Name, count, bytes))
	}
	lines = append(lines, "checksums")
	for _, layer := range checksumLayers {
		counts := map[string]int{}
		for _, p := range packets {
			counts[p.Fields.Text(layer[0]+".checksum.status")]++
		}
		text := fmt.Sprintf("%s good %d bad %d", layer[0], counts["good"], counts["bad"])
		if layer[0] == "udp" {
			text += fmt.Sprintf(" none %d", counts["none"])
		}
		lines = append(lines, text)
	}
	lines = append(lines, "malformed")
	counts := map[string]int{}
	for _, p := range packets {
		if p.Error != "" {
			counts["dump"]++
		} else if p.Fields.Exists("frame.malformed") {
			counts[p.Layers[len(p.Layers)-1]]++
		}
	}
	for _, name := range []string{"dump", "eth", "arp", "ip", "icmp", "udp", "tcp", "dns"} {
		lines = append(lines, fmt.Sprintf("%s %d", name, counts[name]))
	}
	lines = append(lines, "tcp analysis")
	for _, mark := range marks {
		count := 0
		for _, p := range packets {
			if p.Fields.Exists("tcp.analysis." + mark) {
				count++
			}
		}
		lines = append(lines, fmt.Sprintf("%s %d", mark, count))
	}
	queries, responses, pending := []*Packet{}, []*Packet{}, []*Packet{}
	times := []int64{}
	for _, p := range packets {
		if !p.Fields.Exists("dns.id") {
			continue
		}
		if p.Fields.Num("dns.flags.response") == 0 {
			queries = append(queries, p)
			pending = append(pending, p)
			continue
		}
		responses = append(responses, p)
		for i, q := range pending {
			qf, pf := q.Fields, p.Fields
			if qf.Num("dns.id") == pf.Num("dns.id") && qf.Num("ip.src") == pf.Num("ip.dst") && qf.Num("udp.srcport") == pf.Num("udp.dstport") && qf.Num("ip.dst") == pf.Num("ip.src") && qf.Num("udp.dstport") == pf.Num("udp.srcport") {
				pending = append(pending[:i], pending[i+1:]...)
				times = append(times, p.Time-q.Time)
				break
			}
		}
	}
	lines = append(lines, "dns", fmt.Sprintf("queries %d", len(queries)), fmt.Sprintf("responses %d",
		len(responses)), fmt.Sprintf("transactions %d", len(times)), fmt.Sprintf("unanswered %d",
		len(pending)))
	if len(times) > 0 {
		lo, hi := times[0], times[0]
		for _, t := range times {
			lo, hi = min(lo, t), max(hi, t)
		}
		lines = append(lines, "response_time min "+seconds(lo)+" max "+seconds(hi))
	} else {
		lines = append(lines, "response_time -")
	}
	rcodes := map[int64]int{}
	for _, p := range responses {
		rcodes[p.Fields.Num("dns.flags.rcode")]++
	}
	for code := int64(0); code < 16; code++ {
		if rcodes[code] > 0 {
			lines = append(lines, fmt.Sprintf("rcode %s %d", rcodeName(code), rcodes[code]))
		}
	}
	lines = append(lines, "names")
	names := map[string]int{}
	for _, q := range queries {
		for _, v := range q.Fields["dns.qry.name"] {
			names[v.Text]++
		}
	}
	ordered := []string{}
	for name := range names {
		ordered = append(ordered, name)
	}
	sort.Slice(ordered, func(i, j int) bool {
		a, b := ordered[i], ordered[j]
		if names[a] != names[b] {
			return names[a] > names[b]
		}
		return a < b
	})
	for _, name := range ordered {
		lines = append(lines, fmt.Sprintf("%s %d", name, names[name]))
	}
	return lines
}
func conversationLines(packets []*Packet) []string {
	lines := []string{"type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration"}
	kinds := []string{"ipv4", "tcp", "udp"}
	base := packets[0].Time
	for _, c := range buildConversations(packets) {
		lines = append(lines, fmt.Sprintf("%s,%s,%s,%d,%d,%d,%d,%d,%d,%s,%s", kinds[c.Kind], endpointText(c.A),
			endpointText(c.B), c.Packets(), c.Bytes(), c.PacketsAB, c.BytesAB, c.PacketsBA, c.BytesBA,
			seconds(c.FirstTime-base), seconds(c.LastTime-c.FirstTime)))
	}
	return lines
}
func endpointLines(packets []*Packet) []string {
	lines := []string{"address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes"}
	for _, e := range buildEndpoints(packets) {
		lines = append(lines, fmt.Sprintf("%s,%d,%d,%d,%d,%d,%d", ipv4Notation(e.Address), e.Packets(), e.Bytes(), e.TxPackets, e.TxBytes, e.RxPackets, e.RxBytes))
	}
	return lines
}
func sideLine(s *Side) string {
	text := fmt.Sprintf("%s packets %d payload %d", s.Name, s.Packets, s.Payload)
	for _, mark := range marks {
		text += fmt.Sprintf(" %s %d", mark, s.Marks[mark])
	}
	return text
}
func streamLines(s *Stream, packets []*Packet) []string {
	history := []string{}
	for _, entry := range s.History {
		history = append(history, fmt.Sprintf("%s %d", entry.State, entry.Packet))
	}
	rtt := "-"
	if s.Syn > 0 && s.HandshakeAck > 0 {
		rtt = seconds(packets[s.HandshakeAck-1].Time - packets[s.Syn-1].Time)
	}
	client, server := s.ClientSide, s.ServerSide
	lines := []string{fmt.Sprintf("stream %d %s -> %s", s.Number, endpointText(s.Client), endpointText(s.Server)),
		fmt.Sprintf("packets %d bytes %d start %s duration %s", s.Packets, s.Bytes, seconds(s.Start-packets[0].Time),
			seconds(s.End-s.Start)), "states " + strings.Join(history, ", "), fmt.Sprintf("handshake syn %s syn_ack %s ack %s rtt %s",
			optionalPacket(s.Syn), optionalPacket(s.SynAck), optionalPacket(s.HandshakeAck), rtt), fmt.Sprintf("options client mss %s wscale %s server mss %s wscale %s",
			optionalNumber(client.MSS), optionalNumber(client.WScale), optionalNumber(server.MSS), optionalNumber(server.WScale)),
		sideLine(client), sideLine(server)}
	for _, e := range s.Events {
		lines = append(lines, fmt.Sprintf("event %d %s %s seq %d len %d", e.Packet, e.Side, e.Mark, e.Start, e.Size))
	}
	return lines
}
func joinedBlocks(blocks [][]string) []string {
	lines := []string{}
	for i, block := range blocks {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, block...)
	}
	return lines
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
func main() {
	packets := readCapture()
	base := packets[0].Time
	for _, p := range packets {
		dissect(p, base)
	}
	tracker := newTracker()
	for _, p := range packets {
		if p.Fields.Exists("tcp.srcport") {
			tracker.Track(p)
		}
	}
	summaries := []string{}
	for _, p := range packets {
		summaries = append(summaries, summaryLine(p, tracker.DuplicateAcks))
	}
	summary := append([]string(nil), summaries...)
	details := [][]string{}
	for _, request := range readLines("input/filters.txt") {
		if strings.HasPrefix(request, "FILTER ") {
			summary = append(summary, filterBlock(request[7:], packets, summaries)...)
		} else if strings.HasPrefix(request, "DETAIL ") {
			number, _ := strconv.Atoi(request[7:])
			details = append(details, detailLines(packets, number))
		}
	}
	streams := [][]string{}
	for _, s := range tracker.Streams {
		streams = append(streams, streamLines(s, packets))
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("summary.txt", summary)
	writeLines("details.txt", joinedBlocks(details))
	writeLines("conversations.csv", conversationLines(packets))
	writeLines("endpoints.csv", endpointLines(packets))
	writeLines("protocol_stats.txt", protocolStats(packets))
	writeLines("tcp_streams.txt", joinedBlocks(streams))
}
