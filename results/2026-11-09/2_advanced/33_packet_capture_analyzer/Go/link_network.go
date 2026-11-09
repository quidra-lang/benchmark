package main

import (
	"fmt"
	"strings"
)

type Malformed string

func fail(reason string) { panic(Malformed(reason)) }

type Layer struct {
	Fields             Fields
	Next               string
	Payload, Remaining []byte
}

func newLayer() *Layer { return &Layer{Fields: Fields{}} }
func readInt(data []byte, index, size int) int64 {
	value := int64(0)
	for _, b := range data[index : index+size] {
		value = value*256 + int64(b)
	}
	return value
}
func checksumStatus(data []byte) string {
	total := int64(0)
	for i := 0; i < len(data); i += 2 {
		value := int64(data[i]) * 256
		if i+1 < len(data) {
			value += int64(data[i+1])
		}
		total += value
	}
	for total > 65535 {
		total = total%65536 + total/65536
	}
	if total == 65535 {
		return "good"
	}
	return "bad"
}
func macNotation(value int64) string {
	fields := make([]string, 6)
	for i := 5; i >= 0; i-- {
		fields[i] = fmt.Sprintf("%02x", value%256)
		value /= 256
	}
	return strings.Join(fields, ":")
}
func ipv4Notation(value int64) string {
	fields := make([]string, 4)
	for i := 3; i >= 0; i-- {
		fields[i] = fmt.Sprint(value % 256)
		value /= 256
	}
	return strings.Join(fields, ".")
}
func dissectEthernet(data []byte) *Layer {
	if len(data) < 14 {
		fail("eth: truncated")
	}
	l := newLayer()
	t := readInt(data, 12, 2)
	l.Fields.N("eth.dst", readInt(data, 0, 6))
	l.Fields.N("eth.src", readInt(data, 6, 6))
	l.Fields.N("eth.type", t)
	if t == 2054 {
		l.Next = "arp"
	} else if t == 2048 {
		l.Next = "ip"
	}
	if l.Next != "" {
		l.Payload = data[14:]
	} else {
		l.Remaining = data[14:]
	}
	return l
}
func dissectARP(data []byte) *Layer {
	if len(data) < 28 {
		fail("arp: truncated")
	}
	if readInt(data, 0, 2) != 1 || readInt(data, 2, 2) != 2048 || data[4] != 6 || data[5] != 4 {
		fail("arp: unsupported format")
	}
	l := newLayer()
	l.Fields.N("arp.opcode", readInt(data, 6, 2))
	l.Fields.N("arp.src.hw", readInt(data, 8, 6))
	l.Fields.N("arp.src.ip", readInt(data, 14, 4))
	l.Fields.N("arp.dst.hw", readInt(data, 18, 6))
	l.Fields.N("arp.dst.ip", readInt(data, 24, 4))
	return l
}
func dissectIPv4(data []byte) *Layer {
	if len(data) < 20 {
		fail("ip: truncated header")
	}
	version := data[0] / 16
	if version != 4 {
		fail(fmt.Sprintf("ip: bad version %d", version))
	}
	h := int(data[0]%16) * 4
	if h < 20 {
		fail(fmt.Sprintf("ip: bad header length %d", h))
	}
	if len(data) < h {
		fail("ip: truncated header")
	}
	t := int(readInt(data, 2, 2))
	if t < h {
		fail(fmt.Sprintf("ip: bad total length %d", t))
	}
	if t > len(data) {
		fail(fmt.Sprintf("ip: truncated (total length %d, available %d)", t, len(data)))
	}
	flags := readInt(data, 6, 2)
	mf, offset := flags/8192%2, flags%8192*8
	l := newLayer()
	f := l.Fields
	f.N("ip.hdr_len", int64(h))
	f.N("ip.tos", int64(data[1]))
	f.N("ip.len", int64(t))
	f.N("ip.id", readInt(data, 4, 2))
	f.N("ip.flags.df", flags/16384%2)
	f.N("ip.flags.mf", mf)
	f.N("ip.frag_offset", offset)
	f.N("ip.ttl", int64(data[8]))
	f.N("ip.proto", int64(data[9]))
	f.N("ip.checksum", readInt(data, 10, 2))
	f.S("ip.checksum.status", checksumStatus(data[:h]))
	f.N("ip.src", readInt(data, 12, 4))
	f.N("ip.dst", readInt(data, 16, 4))
	payload := data[h:t]
	if mf == 1 || offset != 0 {
		f.N("ip.fragment", 1)
		l.Remaining = payload
	} else {
		switch data[9] {
		case 1:
			l.Next = "icmp"
		case 17:
			l.Next = "udp"
		case 6:
			l.Next = "tcp"
		}
		if l.Next == "" {
			l.Remaining = payload
		} else {
			l.Payload = payload
		}
	}
	return l
}
