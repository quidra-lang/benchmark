package main

import (
	"fmt"
	"strings"
)

var dnsTypeNames = map[int64]string{1: "A", 2: "NS", 5: "CNAME", 6: "SOA", 12: "PTR", 15: "MX", 16: "TXT", 28: "AAAA"}

func typeName(t int64) string {
	if name, ok := dnsTypeNames[t]; ok {
		return name
	}
	return fmt.Sprintf("TYPE%d", t)
}
func rcodeName(code int64) string {
	names := []string{"NoError", "FormErr", "ServFail", "NXDomain", "NotImp", "Refused"}
	if code < int64(len(names)) {
		return names[code]
	}
	return fmt.Sprintf("RCODE%d", code)
}
func className(c int64) string {
	if c == 1 {
		return "IN"
	}
	return fmt.Sprintf("CLASS%d", c)
}
func labelText(bytes []byte) string {
	text := ""
	for _, b := range bytes {
		if b >= 33 && b <= 126 && b != 46 && b != 92 {
			text += string(b)
		} else {
			text += fmt.Sprintf("\\%03d", b)
		}
	}
	return text
}
func ipv6Notation(bytes []byte) string {
	groups := []int64{}
	texts := []string{}
	for i := 0; i < 16; i += 2 {
		group := readInt(bytes, i, 2)
		groups = append(groups, group)
		texts = append(texts, fmt.Sprintf("%x", group))
	}
	bestStart, bestLength := -1, 1
	for i := 0; i < len(groups); {
		if groups[i] != 0 {
			i++
			continue
		}
		end := i
		for end < len(groups) && groups[end] == 0 {
			end++
		}
		if end-i > bestLength {
			bestStart, bestLength = i, end-i
		}
		i = end
	}
	if bestStart < 0 {
		return strings.Join(texts, ":")
	}
	return strings.Join(texts[:bestStart], ":") + "::" + strings.Join(texts[bestStart+bestLength:], ":")
}

type DNSReader struct{ Message []byte }

func (r DNSReader) Chunk(position, size int) []byte {
	if position+size > len(r.Message) {
		fail("dns: truncated")
	}
	return r.Message[position : position+size]
}
func (r DNSReader) Integer(position, size int) int64 {
	return readInt(r.Chunk(position, size), 0, size)
}
func (r DNSReader) Name(position int) (string, int) {
	labels := []string{}
	pointers, after := 0, -1
	for {
		length := int(r.Integer(position, 1))
		if length == 0 {
			if after < 0 {
				after = position + 1
			}
			break
		}
		if length >= 192 {
			low := int(r.Integer(position+1, 1))
			if after < 0 {
				after = position + 2
			}
			pointers++
			if pointers > 16 {
				fail("dns: compression loop")
			}
			target := (length-192)*256 + low
			if target >= len(r.Message) {
				fail("dns: pointer out of range")
			}
			position = target
		} else if length >= 64 {
			fail("dns: bad label type")
		} else {
			labels = append(labels, labelText(r.Chunk(position+1, length)))
			position += length + 1
		}
	}
	notation := strings.Join(labels, ".")
	if len(labels) == 0 {
		notation = "<root>"
	}
	return notation, after
}
func (r DNSReader) Rdata(t int64, start, length int) (string, int) {
	switch t {
	case 1:
		return ipv4Notation(r.Integer(start, 4)), start + 4
	case 28:
		return ipv6Notation(r.Chunk(start, 16)), start + 16
	case 2, 5, 12:
		return r.Name(start)
	case 15:
		preference := r.Integer(start, 2)
		exchange, end := r.Name(start + 2)
		return fmt.Sprintf("%d %s", preference, exchange), end
	case 6:
		primary, pos := r.Name(start)
		mailbox, pos := r.Name(pos)
		parts := []string{primary, mailbox}
		for i := 0; i < 5; i++ {
			parts = append(parts, fmt.Sprint(r.Integer(pos, 4)))
			pos += 4
		}
		return strings.Join(parts, " "), pos
	default:
		return fmt.Sprintf("%d bytes", length), start + length
	}
}
func (r DNSReader) Record(position int, section string, l *Layer) int {
	name, pos := r.Name(position)
	fixed := r.Chunk(pos, 10)
	t, c, ttl, length := readInt(fixed, 0, 2), readInt(fixed, 2, 2), readInt(fixed, 4, 4), int(readInt(fixed, 8, 2))
	start := pos + 10
	r.Chunk(start, length)
	data, end := r.Rdata(t, start, length)
	if end != start+length {
		fail("dns: bad rdata length")
	}
	l.Fields.AddS(section, fmt.Sprintf("%s %s %s %d %s", name, typeName(t), className(c), ttl, data))
	if section == "dns.answer" && t == 1 {
		l.Fields.AddN("dns.a", readInt(r.Message, start, 4))
	}
	return start + length
}
func dissectDNS(message []byte) *Layer {
	r := DNSReader{message}
	header := r.Chunk(0, 12)
	flags := readInt(header, 2, 2)
	counts := []int{}
	for i := 4; i < 12; i += 2 {
		counts = append(counts, int(readInt(header, i, 2)))
	}
	l := newLayer()
	f := l.Fields
	f.N("dns.id", readInt(header, 0, 2))
	f.N("dns.flags", flags)
	f.N("dns.flags.response", flags/32768%2)
	f.N("dns.flags.opcode", flags/2048%16)
	f.N("dns.flags.rcode", flags%16)
	for i, name := range []string{"dns.count.queries", "dns.count.answers", "dns.count.auth_rr", "dns.count.add_rr"} {
		f.N(name, int64(counts[i]))
	}
	pos := 12
	for i := 0; i < counts[0]; i++ {
		name, end := r.Name(pos)
		tail := r.Chunk(end, 4)
		f.AddS("dns.qry.name", name)
		f.AddN("dns.qry.type", readInt(tail, 0, 2))
		pos = end + 4
	}
	for i, section := range []string{"dns.answer", "dns.authority", "dns.additional"} {
		for j := 0; j < counts[i+1]; j++ {
			pos = r.Record(pos, section, l)
		}
	}
	return l
}
