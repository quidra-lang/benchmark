package main

import (
	"encoding/hex"
	"fmt"
	"os"
	"regexp"
	"strings"
)

type FieldValue struct {
	Number int64
	Text   string
}
type Fields map[string][]FieldValue

func (f Fields) N(name string, value int64)    { f[name] = []FieldValue{{Number: value}} }
func (f Fields) S(name, value string)          { f[name] = []FieldValue{{Text: value}} }
func (f Fields) AddN(name string, value int64) { f[name] = append(f[name], FieldValue{Number: value}) }
func (f Fields) AddS(name, value string)       { f[name] = append(f[name], FieldValue{Text: value}) }
func (f Fields) Num(name string) int64 {
	if len(f[name]) == 0 {
		return 0
	}
	return f[name][0].Number
}
func (f Fields) Text(name string) string {
	if len(f[name]) == 0 {
		return ""
	}
	return f[name][0].Text
}
func (f Fields) Exists(name string) bool { return len(f[name]) > 0 }

type Packet struct {
	Number, Length  int
	Time            int64
	Data, Remaining []byte
	Error           string
	Layers          []string
	Fields          Fields
}

func readLines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(b) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func readCapture() []*Packet {
	packets := []*Packet{}
	type DumpLine struct {
		Number int
		Text   string
	}
	dumps := [][]DumpLine{}
	pattern := regexp.MustCompile(`^[0-9a-f]{4}  [0-9a-f]{2}( [0-9a-f]{2}){0,15}$`)
	for i, text := range readLines("input/capture.txt") {
		if strings.HasPrefix(text, "PACKET ") {
			p := &Packet{Fields: Fields{}}
			fmt.Sscanf(text, "PACKET %d %d %d", &p.Number, &p.Time, &p.Length)
			packets = append(packets, p)
			dumps = append(dumps, nil)
		} else if text != "" {
			last := len(dumps) - 1
			dumps[last] = append(dumps[last], DumpLine{i + 1, text})
		}
	}
	for i, p := range packets {
		data := []byte{}
		for _, dump := range dumps[i] {
			text := dump.Text
			if !pattern.MatchString(text) {
				p.Error = fmt.Sprintf("dump: bad line %d", dump.Number)
				break
			}
			var offset int
			fmt.Sscanf(text[:4], "%x", &offset)
			if offset != len(data) {
				p.Error = fmt.Sprintf("dump: offset mismatch at line %d", dump.Number)
				break
			}
			b, _ := hex.DecodeString(strings.ReplaceAll(text[6:], " ", ""))
			data = append(data, b...)
		}
		if p.Error == "" {
			if len(data) != p.Length {
				p.Error = fmt.Sprintf("dump: length mismatch (header %d, data %d)", p.Length, len(data))
			} else {
				p.Data = data
			}
		}
	}
	return packets
}
func hexDumpLines(data []byte) []string {
	lines := []string{}
	for offset := 0; offset < len(data); offset += 16 {
		piece := data[offset:min(offset+16, len(data))]
		bytes := []string{}
		text := ""
		for _, b := range piece {
			bytes = append(bytes, fmt.Sprintf("%02x", b))
			if b >= 32 && b <= 126 {
				text += string(b)
			} else {
				text += "."
			}
		}
		lines = append(lines, fmt.Sprintf("%04x  %-47s  |%s|", offset, strings.Join(bytes, " "), text))
	}
	return lines
}
