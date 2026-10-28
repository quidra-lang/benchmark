package main

import (
	"fmt"
	"strings"
)

func pseudoHeader(source, destination int64, protocol, length int) []byte {
	result := make([]byte, 12)
	for i := 3; i >= 0; i-- {
		result[i] = byte(source % 256)
		result[i+4] = byte(destination % 256)
		source /= 256
		destination /= 256
	}
	result[9] = byte(protocol)
	result[10] = byte(length / 256)
	result[11] = byte(length % 256)
	return result
}
func dissectICMP(data []byte) *Layer {
	if len(data) < 8 {
		fail("icmp: truncated")
	}
	l := newLayer()
	f := l.Fields
	t := data[0]
	f.N("icmp.type", int64(t))
	f.N("icmp.code", int64(data[1]))
	f.N("icmp.checksum", readInt(data, 2, 2))
	f.S("icmp.checksum.status", checksumStatus(data))
	if t == 0 || t == 8 {
		f.N("icmp.id", readInt(data, 4, 2))
		f.N("icmp.seq", readInt(data, 6, 2))
	}
	l.Remaining = data[8:]
	return l
}
func dissectUDP(data []byte, source, destination int64) *Layer {
	if len(data) < 8 {
		fail("udp: truncated")
	}
	length := int(readInt(data, 4, 2))
	if length < 8 || length > len(data) {
		fail(fmt.Sprintf("udp: bad length %d", length))
	}
	src, dst, checksum := readInt(data, 0, 2), readInt(data, 2, 2), readInt(data, 6, 2)
	status := "none"
	if checksum != 0 {
		status = checksumStatus(append(pseudoHeader(source, destination, 17, length), data[:length]...))
	}
	l := newLayer()
	f := l.Fields
	f.N("udp.srcport", src)
	f.N("udp.dstport", dst)
	f.N("udp.length", int64(length))
	f.N("udp.checksum", checksum)
	f.S("udp.checksum.status", status)
	if src == 53 || dst == 53 {
		l.Next = "dns"
		l.Payload = data[8:length]
	} else {
		l.Remaining = data[8:length]
	}
	return l
}
func parseOptions(options []byte, l *Layer) {
	lengths := map[byte][]int{2: {4}, 3: {3}, 4: {2}, 5: {10, 18, 26, 34}, 8: {10}}
	for i := 0; i < len(options); {
		kind := options[i]
		if kind == 0 {
			l.Fields.AddS("tcp.option", "EOL")
			return
		}
		if kind == 1 {
			l.Fields.AddS("tcp.option", "NOP")
			i++
			continue
		}
		length := 0
		if i+1 < len(options) {
			length = int(options[i+1])
		}
		valid := length >= 2 && i+length <= len(options)
		if allowed, exists := lengths[kind]; exists {
			matches := false
			for _, v := range allowed {
				if length == v {
					matches = true
				}
			}
			valid = valid && matches
		}
		if !valid {
			l.Fields.N("tcp.options.malformed", 1)
			return
		}
		body := options[i+2 : i+length]
		text := ""
		switch kind {
		case 2:
			value := readInt(body, 0, 2)
			l.Fields.N("tcp.options.mss", value)
			text = fmt.Sprintf("MSS %d", value)
		case 3:
			l.Fields.N("tcp.options.wscale", int64(body[0]))
			text = fmt.Sprintf("WS %d", body[0])
		case 4:
			text = "SACK_PERM"
		case 5:
			parts := []string{"SACK"}
			for start := 0; start < len(body); start += 8 {
				parts = append(parts, fmt.Sprintf("%d-%d", readInt(body, start, 4), readInt(body, start+4, 4)))
			}
			text = strings.Join(parts, " ")
		case 8:
			text = fmt.Sprintf("TS %d %d", readInt(body, 0, 4), readInt(body, 4, 4))
		default:
			text = fmt.Sprintf("kind %d len %d", kind, length)
		}
		l.Fields.AddS("tcp.option", text)
		i += length
	}
}
func dissectTCP(data []byte, source, destination int64) *Layer {
	if len(data) < 20 {
		fail("tcp: truncated header")
	}
	h := int(data[12]/16) * 4
	if h < 20 {
		fail(fmt.Sprintf("tcp: bad header length %d", h))
	}
	if h > len(data) {
		fail("tcp: truncated header")
	}
	l := newLayer()
	f := l.Fields
	flags := int64(data[13])
	f.N("tcp.srcport", readInt(data, 0, 2))
	f.N("tcp.dstport", readInt(data, 2, 2))
	f.N("tcp.seq_raw", readInt(data, 4, 4))
	f.N("tcp.hdr_len", int64(h))
	f.N("tcp.flags", flags)
	for bit, name := range []string{"fin", "syn", "rst", "psh", "ack", "urg"} {
		f.N("tcp.flags."+name, flags>>uint(bit)&1)
	}
	f.N("tcp.window", readInt(data, 14, 2))
	f.N("tcp.checksum", readInt(data, 16, 2))
	f.S("tcp.checksum.status", checksumStatus(append(pseudoHeader(source, destination, 6, len(data)), data...)))
	f.N("tcp.urgent", readInt(data, 18, 2))
	f.N("tcp.len", int64(len(data)-h))
	if flags&16 != 0 {
		f.N("tcp.ack_raw", readInt(data, 8, 4))
	}
	parseOptions(data[20:h], l)
	l.Remaining = data[h:]
	return l
}
