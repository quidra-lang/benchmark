package main

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"math/bits"
	"os"
	"strconv"
	"strings"
)

var methods = []string{"STORE", "LZW", "LZ77", "LZH", "ARITH"}
var statuses = []string{"ok", "repaired", "checksum", "error", "unsupported", "truncated", "bad_header"}

type Parameters struct{ B, K, M int }
type NamedFile struct {
	Name string
	Data []byte
}
type LZStats struct{ Tokens, Literals, Matches, Matched, Longest, Farthest int }
type LZHStats struct {
	Mode                                                                             string
	FixedBits, TableBits, CodeBits, Halvings, LitUsed, LitMax, OffsetUsed, OffsetMax int
	Slots                                                                            []int
}
type Encoding struct {
	Name     string
	Data     []byte
	Payloads [][]byte
	Best     int
	LZW      LZWStats
	LZ       LZStats
	LZH      LZHStats
	Arith    ArithStats
}

func (e Encoding) payload() []byte { return e.Payloads[e.Best] }

type Entry struct {
	Number, Offset                                     int
	Status                                             string
	Valid                                              bool
	Name                                               string
	Method, Original, Compressed, Checksum, Start, End int
	Data                                               []byte
	Error                                              *DecodeError
	Repair                                             [3]int
	Computed                                           int
}
type ParsedArchive struct {
	Size, B, K, Declared int
	Entries              []*Entry
	Error                string
	Stopped              bool
	Trailing             int
}

func (p ParsedArchive) intact() []*Entry {
	entries := []*Entry{}
	for _, e := range p.Entries {
		if e.Status == "ok" || e.Status == "repaired" {
			entries = append(entries, e)
		}
	}
	return entries
}
func mustRead(path string) []byte {
	v, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return v
}
func parseInt(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func readInputs() (Parameters, []NamedFile, []byte) {
	lines := strings.Split(strings.TrimSuffix(string(mustRead("input/manifest.txt")), "\n"), "\n")
	p := Parameters{parseInt(strings.Split(lines[0], " ")[1]), parseInt(strings.Split(lines[1], " ")[1]), parseInt(strings.Split(lines[2], " ")[1])}
	files := []NamedFile{}
	for _, line := range lines[3:] {
		name := strings.Split(line, " ")[1]
		files = append(files, NamedFile{name, mustRead("input/files/" + name)})
	}
	archive, err := hex.DecodeString(strings.ReplaceAll(string(mustRead("input/archive.hex")), "\n", ""))
	if err != nil {
		panic(err)
	}
	return p, files, archive
}
func ratio(compressed, original int) string {
	if original == 0 {
		return "-"
	}
	return strconv.FormatInt(1000*int64(compressed)/int64(original), 10)
}
func methodName(number int) string {
	if number < 5 {
		return methods[number]
	}
	return fmt.Sprintf("#%d", number)
}
func adler(data []byte) int {
	a, b := int64(1), int64(0)
	for _, x := range data {
		a = (a + int64(x)) % 65521
		b = (b + a) % 65521
	}
	return int(b*65536 + a)
}
func modulo(a int64) int64 { return (a%65521 + 65521) % 65521 }
func modPower(a, exponent int64) int64 {
	v := int64(1)
	for exponent > 0 {
		if exponent&1 != 0 {
			v = v * a % 65521
		}
		a = a * a % 65521
		exponent >>= 1
	}
	return v
}
func repairOneByte(data []byte, stored, computed int) ([]byte, [3]int, bool) {
	deltaA := modulo(int64(stored%65536 - computed%65536))
	deltaB := modulo(int64(stored/65536 - computed/65536))
	delta := deltaA
	if 1 <= deltaA && deltaA <= 255 {
	} else if 65266 <= deltaA && deltaA <= 65520 {
		delta -= 65521
	} else {
		return nil, [3]int{}, false
	}
	inverse := modPower(modulo(delta), 65519)
	t := deltaB * inverse % 65521
	if t < 1 || t > int64(len(data)) {
		return nil, [3]int{}, false
	}
	position := len(data) - int(t)
	before := int(data[position])
	after := before + int(delta)
	if after < 0 || after > 255 {
		return nil, [3]int{}, false
	}
	result := append([]byte{}, data...)
	result[position] = byte(after)
	if adler(result) != stored {
		return nil, [3]int{}, false
	}
	return result, [3]int{position, before, after}, true
}
func encodeLZ77(tokens []Token, b, k int) []byte {
	w := BitWriter{}
	for _, t := range tokens {
		if t.Length == 0 {
			w.write(0, 1)
			w.write(t.Literal, 8)
		} else {
			w.write(1, 1)
			w.write(t.Distance-1, b)
			w.write(t.Length-3, k)
		}
	}
	return w.finish()
}
func decodeLZ77(payload []byte, n, b, k int) ([]byte, *DecodeError) {
	r := BitReader{Payload: payload}
	out := []byte{}
	for len(out) < n {
		flag, e := r.read(1, len(out))
		if e != nil {
			return nil, e
		}
		if flag == 0 {
			x, e := r.read(8, len(out))
			if e != nil {
				return nil, e
			}
			out = append(out, byte(x))
		} else {
			u, e := r.read(b, len(out))
			if e != nil {
				return nil, e
			}
			v, e := r.read(k, len(out))
			if e != nil {
				return nil, e
			}
			out, e = copyMatch(out, u+1, v+3, n)
			if e != nil {
				return nil, e
			}
		}
	}
	return out, nil
}
func fixedLengths(count int) []int {
	width := bits.Len(uint(count - 1))
	shorter := (1 << width) - count
	lengths := make([]int, count)
	for s := range lengths {
		lengths[s] = width
		if s < shorter {
			lengths[s]--
		}
	}
	return lengths
}
func writeCodeTable(w *BitWriter, lengths []int) {
	for s := 0; s < len(lengths); {
		if lengths[s] > 0 {
			w.write(lengths[s], 4)
			s++
		} else {
			run := 1
			for run < 256 && s+run < len(lengths) && lengths[s+run] == 0 {
				run++
			}
			w.write(0, 4)
			w.write(run-1, 8)
			s += run
		}
	}
}
func readCodeTable(r *BitReader, count, position int) ([]int, *DecodeError) {
	lengths := []int{}
	for len(lengths) < count {
		length, e := r.read(4, position)
		if e != nil {
			return nil, e
		}
		if length > 0 {
			lengths = append(lengths, length)
		} else {
			run, e := r.read(8, position)
			if e != nil {
				return nil, e
			}
			run++
			if len(lengths)+run > count {
				return nil, &DecodeError{"bad_table", position}
			}
			lengths = append(lengths, make([]int, run)...)
		}
	}
	used, sum, single := 0, 0, 0
	for _, v := range lengths {
		if v > 0 {
			used++
			single = v
			sum += 1 << (15 - v)
		}
	}
	if used == 1 && single != 1 || used >= 2 && sum != 1<<15 {
		return nil, &DecodeError{"bad_table", position}
	}
	return lengths, nil
}

type HuffmanReader struct {
	Symbols map[[2]int]int
	Maximum int
}

func newHuffmanReader(lengths []int) HuffmanReader {
	h := HuffmanReader{Symbols: map[[2]int]int{}}
	codes := canonicalCodes(lengths)
	for s, l := range lengths {
		if l > 0 {
			h.Symbols[[2]int{l, codes[s]}] = s
			h.Maximum = max(h.Maximum, l)
		}
	}
	return h
}
func (h HuffmanReader) read(r *BitReader, position int) (int, *DecodeError) {
	if len(h.Symbols) == 0 {
		return 0, &DecodeError{"bad_code", position}
	}
	code := 0
	for width := 1; width <= h.Maximum; width++ {
		b, e := r.read(1, position)
		if e != nil {
			return 0, e
		}
		code = 2*code + b
		if symbol, ok := h.Symbols[[2]int{width, code}]; ok {
			return symbol, nil
		}
	}
	return 0, &DecodeError{"bad_code", position}
}
func writeLZHTokens(w *BitWriter, tokens []Token, lit, dist []int) {
	lc, dc := canonicalCodes(lit), canonicalCodes(dist)
	for _, t := range tokens {
		if t.Length == 0 {
			w.write(lc[t.Literal], lit[t.Literal])
		} else {
			symbol := t.Length + 253
			w.write(lc[symbol], lit[symbol])
			u := t.Distance - 1
			slot := bits.Len(uint(u))
			w.write(dc[slot], dist[slot])
			if slot >= 2 {
				w.write(u-(1<<(slot-1)), slot-1)
			}
		}
	}
}
func lengthStats(lengths []int) (int, int) {
	used, longest := 0, 0
	for _, l := range lengths {
		if l > 0 {
			used++
		}
		longest = max(longest, l)
	}
	return used, longest
}
func encodeLZH(tokens []Token, p Parameters) ([]byte, LZHStats) {
	litFreq, distFreq := make([]int, 256+(1<<p.K)), make([]int, p.B+1)
	for _, t := range tokens {
		if t.Length == 0 {
			litFreq[t.Literal]++
		} else {
			litFreq[t.Length+253]++
			distFreq[bits.Len(uint(t.Distance-1))]++
		}
	}
	lit, lh := limitedLengths(litFreq, p.M)
	dist, dh := limitedLengths(distFreq, p.M)
	fixed, dynamic := BitWriter{}, BitWriter{}
	fixed.write(0, 1)
	writeLZHTokens(&fixed, tokens, fixedLengths(len(lit)), fixedLengths(len(dist)))
	dynamic.write(1, 1)
	writeCodeTable(&dynamic, lit)
	writeCodeTable(&dynamic, dist)
	tableBits := dynamic.Count - 1
	writeLZHTokens(&dynamic, tokens, lit, dist)
	codeBits := dynamic.Count - 1 - tableBits
	lu, lm := lengthStats(lit)
	du, dm := lengthStats(dist)
	stats := LZHStats{Mode: "dynamic", FixedBits: fixed.Count - 1, TableBits: tableBits, CodeBits: codeBits,
		Halvings: lh + dh, LitUsed: lu, LitMax: lm, OffsetUsed: du, OffsetMax: dm, Slots: distFreq}
	if fixed.Count-1 <= tableBits+codeBits {
		stats.Mode = "fixed"
		return fixed.finish(), stats
	}
	return dynamic.finish(), stats
}
func decodeLZH(payload []byte, n, b, k int) ([]byte, *DecodeError) {
	r := BitReader{Payload: payload}
	flag, e := r.read(1, 0)
	if e != nil {
		return nil, e
	}
	var lit, dist []int
	if flag == 1 {
		lit, e = readCodeTable(&r, 256+(1<<k), 0)
		if e != nil {
			return nil, e
		}
		dist, e = readCodeTable(&r, b+1, 0)
		if e != nil {
			return nil, e
		}
	} else {
		lit = fixedLengths(256 + (1 << k))
		dist = fixedLengths(b + 1)
	}
	lr, dr := newHuffmanReader(lit), newHuffmanReader(dist)
	out := []byte{}
	for len(out) < n {
		symbol, e := lr.read(&r, len(out))
		if e != nil {
			return nil, e
		}
		if symbol < 256 {
			out = append(out, byte(symbol))
		} else {
			slot, e := dr.read(&r, len(out))
			if e != nil {
				return nil, e
			}
			u := slot
			if slot >= 2 {
				extra, e := r.read(slot-1, len(out))
				if e != nil {
					return nil, e
				}
				u = (1 << (slot - 1)) + extra
			}
			out, e = copyMatch(out, u+1, symbol-253, n)
			if e != nil {
				return nil, e
			}
		}
	}
	return out, nil
}
func decodePayload(method int, payload []byte, n, b, k int) ([]byte, *DecodeError) {
	switch method {
	case 0:
		if len(payload) < n {
			return nil, &DecodeError{"end_of_data", len(payload)}
		}
		return append([]byte{}, payload[:n]...), nil
	case 1:
		return decodeLZW(payload, n)
	case 2:
		return decodeLZ77(payload, n, b, k)
	case 3:
		return decodeLZH(payload, n, b, k)
	case 4:
		return decodeArith(payload, n)
	}
	panic("unsupported method")
}
func encodeFile(name string, data []byte, p Parameters) Encoding {
	tokens := tokenize(data, p.B, p.K)
	zw, zws := encodeLZW(data)
	zh, zhs := encodeLZH(tokens, p)
	arith, as := encodeArith(data)
	payloads := [][]byte{data, zw, encodeLZ77(tokens, p.B, p.K), zh, arith}
	best := 0
	for k := 1; k < 5; k++ {
		if len(payloads[k]) < len(payloads[best]) {
			best = k
		}
	}
	zs := LZStats{Tokens: len(tokens)}
	for _, t := range tokens {
		if t.Length == 0 {
			zs.Literals++
		} else {
			zs.Matches++
			zs.Matched += t.Length
			zs.Longest = max(zs.Longest, t.Length)
			zs.Farthest = max(zs.Farthest, t.Distance)
		}
	}
	return Encoding{name, data, payloads, best, zws, zs, zhs, as}
}
func appendBig(data []byte, value, width int) []byte {
	for shift := 8 * (width - 1); shift >= 0; shift -= 8 {
		data = append(data, byte(value>>shift))
	}
	return data
}
func buildArchive(encodings []Encoding, p Parameters) []byte {
	archive := append([]byte("TXAR"), byte(p.B), byte(p.K))
	archive = appendBig(archive, len(encodings), 2)
	for _, e := range encodings {
		header := append([]byte{byte(len(e.Name))}, []byte(e.Name)...)
		header = append(header, byte(e.Best))
		header = appendBig(header, len(e.Data), 4)
		header = appendBig(header, len(e.payload()), 4)
		header = appendBig(header, adler(e.Data), 4)
		check := 0
		for _, v := range header {
			check += int(v)
		}
		header = append(header, byte(check%256))
		archive = append(archive, header...)
		archive = append(archive, e.payload()...)
	}
	return archive
}
func readEntryHeader(x []byte, number, pos int) *Entry {
	m := int(x[pos])
	name := x[pos+1 : pos+1+m]
	cursor := pos + 1 + m
	start := pos + 15 + m
	original := int(binary.BigEndian.Uint32(x[cursor+1 : cursor+5]))
	compressed := int(binary.BigEndian.Uint32(x[cursor+5 : cursor+9]))
	sum := int(binary.BigEndian.Uint32(x[cursor+9 : cursor+13]))
	valid := 1 <= m && m <= 32
	for _, b := range name {
		if !(b >= 'a' && b <= 'z' || b >= '0' && b <= '9' || b == '.' || b == '_' || b == '-') {
			valid = false
		}
	}
	check := 0
	for _, b := range x[pos : start-1] {
		check += int(b)
	}
	valid = valid && check%256 == int(x[start-1])
	return &Entry{Number: number, Offset: pos, Valid: valid, Name: string(name), Method: int(x[cursor]),
		Original: original, Compressed: compressed, Checksum: sum, Start: start, End: start + compressed}
}
func examinePayload(e *Entry, x []byte, b, k int) {
	data, err := decodePayload(e.Method, x[e.Start:e.End], e.Original, b, k)
	if err != nil {
		e.Status = "error"
		e.Error = err
		return
	}
	e.Data = data
	e.Computed = adler(data)
	if e.Computed == e.Checksum {
		e.Status = "ok"
		return
	}
	repaired, detail, ok := repairOneByte(data, e.Checksum, e.Computed)
	if ok {
		e.Status = "repaired"
		e.Data = repaired
		e.Repair = detail
	} else {
		e.Status = "checksum"
	}
}
func parseArchive(x []byte) ParsedArchive {
	p := ParsedArchive{Size: len(x)}
	if len(x) < 8 || !bytes.Equal(x[:4], []byte("TXAR")) {
		p.Error = "bad_magic"
		return p
	}
	p.B, p.K = int(x[4]), int(x[5])
	if p.B < 6 || p.B > 12 || p.K < 2 || p.K > 5 {
		p.Error = "bad_params"
		return p
	}
	p.Declared = int(binary.BigEndian.Uint16(x[6:8]))
	pos := 8
	for number := 1; number <= p.Declared; number++ {
		if pos >= len(x) || pos+15+int(x[pos]) > len(x) {
			p.Entries = append(p.Entries, &Entry{Number: number, Offset: pos, Status: "truncated"})
			p.Stopped = true
			break
		}
		e := readEntryHeader(x, number, pos)
		p.Entries = append(p.Entries, e)
		if !e.Valid {
			e.Status = "bad_header"
			pos = e.End
			if pos > len(x) {
				p.Stopped = true
				break
			}
			continue
		}
		if e.End > len(x) {
			e.Status = "truncated"
			p.Stopped = true
			break
		}
		if e.Method >= 5 {
			e.Status = "unsupported"
		} else {
			examinePayload(e, x, p.B, p.K)
		}
		pos = e.End
	}
	if !p.Stopped {
		p.Trailing = len(x) - pos
	}
	return p
}
func verifyArchive(archive []byte, encodings []Encoding) (int, int) {
	p := parseArchive(archive)
	verified := 0
	for i, e := range p.Entries {
		if i < len(encodings) && e.Status == "ok" && bytes.Equal(e.Data, encodings[i].Data) {
			verified++
		}
	}
	return len(p.Entries), verified
}
func sizesReport(encodings []Encoding, p Parameters, archive []byte, examined, verified int) []string {
	lines := []string{fmt.Sprintf("params offset_bits %d length_bits %d window %d lookahead %d max_code_length %d", p.B, p.K, 1<<p.B, (1<<p.K)+2, p.M)}
	totals, chosen := [5]int{}, [5]int{}
	originalTotal, bestTotal := 0, 0
	for _, e := range encodings {
		original := len(e.Data)
		originalTotal += original
		chosen[e.Best]++
		bestTotal += len(e.payload())
		fields := []string{fmt.Sprintf("file %s original %d", e.Name, original)}
		for k, name := range methods {
			n := len(e.Payloads[k])
			totals[k] += n
			fields = append(fields, fmt.Sprintf("%s %d %s", name, n, ratio(n, original)))
		}
		fields = append(fields, "best "+methods[e.Best])
		lines = append(lines, strings.Join(fields, " "))
	}
	line := fmt.Sprintf("total original %d", originalTotal)
	for k, name := range methods {
		line += fmt.Sprintf(" %s %d %s", name, totals[k], ratio(totals[k], originalTotal))
	}
	line += fmt.Sprintf(" best %d %s", bestTotal, ratio(bestTotal, originalTotal))
	lines = append(lines, line)
	line = "chosen"
	for k, name := range methods {
		line += fmt.Sprintf(" %s %d", name, chosen[k])
	}
	return append(lines, line, fmt.Sprintf("archive bytes %d entries %d ratio %s", len(archive), len(encodings),
		ratio(len(archive), originalTotal)), fmt.Sprintf("verify entries %d ok %d", examined, verified))
}
func ints(values []int) string {
	a := make([]string, len(values))
	for i, v := range values {
		a[i] = strconv.Itoa(v)
	}
	return strings.Join(a, " ")
}
func analysisReport(encodings []Encoding) []string {
	lines := []string{}
	for _, e := range encodings {
		zw, z, zh, ar := e.LZW, e.LZ, e.LZH, e.Arith
		lines = append(lines, fmt.Sprintf("lzw %s codes %d clears %d widths %s longest %d", e.Name, zw.Codes,
			zw.Clears, ints(zw.Widths[:]), zw.Longest), fmt.Sprintf("lz77 %s tokens %d literals %d matches %d matched %d longest %d farthest %d",
			e.Name, z.Tokens, z.Literals, z.Matches, z.Matched, z.Longest, z.Farthest), fmt.Sprintf("lzh %s mode %s fixed_bits %d table_bits %d code_bits %d halvings %d litlen_used %d litlen_max %d offset_used %d offset_max %d",
			e.Name, zh.Mode, zh.FixedBits, zh.TableBits, zh.CodeBits, zh.Halvings, zh.LitUsed, zh.LitMax,
			zh.OffsetUsed, zh.OffsetMax), "slots "+e.Name+" "+ints(zh.Slots), fmt.Sprintf("arith %s bits %d contexts %d rescales %d",
			e.Name, ar.Bits, ar.Contexts, ar.Rescales))
	}
	return lines
}
func listingReport(p ParsedArchive) []string {
	if p.Error != "" {
		return []string{fmt.Sprintf("archive bytes %d error %s", p.Size, p.Error)}
	}
	lines := []string{fmt.Sprintf("archive bytes %d offset_bits %d length_bits %d entries %d", p.Size, p.B, p.K, p.Declared)}
	totals := [5][3]int{}
	listed := 0
	for _, e := range p.Entries {
		prefix := fmt.Sprintf("entry %d offset %d", e.Number, e.Offset)
		if !e.Valid {
			suffix := "truncated header"
			if e.Status == "bad_header" {
				suffix = "bad_header"
			}
			lines = append(lines, prefix+" "+suffix)
			continue
		}
		listed++
		lines = append(lines, fmt.Sprintf("%s method %s original %d compressed %d ratio %s adler %08x name %s",
			prefix, methodName(e.Method), e.Original, e.Compressed, ratio(e.Compressed, e.Original),
			e.Checksum, e.Name))
		if e.Method < 5 {
			totals[e.Method][0]++
			totals[e.Method][1] += e.Original
			totals[e.Method][2] += e.Compressed
		}
	}
	for k, name := range methods {
		t := totals[k]
		lines = append(lines, fmt.Sprintf("method %s entries %d original %d compressed %d ratio %s", name, t[0], t[1], t[2], ratio(t[2], t[1])))
	}
	state := "complete"
	if p.Stopped {
		state = "truncated"
	}
	return append(lines, fmt.Sprintf("end listed %d of %d stop %s trailing %d", listed, p.Declared, state, p.Trailing))
}
func entryTestLine(e *Entry, size int) string {
	prefix := fmt.Sprintf("entry %d offset %d", e.Number, e.Offset)
	if !e.Valid {
		suffix := "truncated header"
		if e.Status == "bad_header" {
			suffix = "bad_header"
		}
		return prefix + " status " + suffix
	}
	line := fmt.Sprintf("%s name %s method %s status %s", prefix, e.Name, methodName(e.Method), e.Status)
	switch e.Status {
	case "repaired":
		line += fmt.Sprintf(" byte %d from %d to %d", e.Repair[0], e.Repair[1], e.Repair[2])
	case "checksum":
		line += fmt.Sprintf(" stored %08x computed %08x", e.Checksum, e.Computed)
	case "error":
		line += fmt.Sprintf(" %s at %d", e.Error.Kind, e.Error.Position)
	case "truncated":
		line += fmt.Sprintf(" payload have %d need %d", size-e.Start, e.Compressed)
	}
	return line
}
func testReport(p ParsedArchive, salvaged []Encoding, archive []byte, verified int) []string {
	lines := []string{}
	if p.Error != "" {
		lines = append(lines, "archive error "+p.Error)
	} else {
		counts := map[string]int{}
		for _, e := range p.Entries {
			lines = append(lines, entryTestLine(e, p.Size))
			counts[e.Status]++
		}
		line := fmt.Sprintf("summary entries %d checked %d", p.Declared, len(p.Entries))
		for _, status := range statuses {
			line += fmt.Sprintf(" %s %d", status, counts[status])
		}
		line += fmt.Sprintf(" missing %d trailing %d", p.Declared-len(p.Entries), p.Trailing)
		lines = append(lines, line)
	}
	intact := p.intact()
	total := 0
	for i, e := range salvaged {
		old := intact[i]
		lines = append(lines, fmt.Sprintf("salvage %s method %s compressed %d was %s %d", e.Name, methods[e.Best],
			len(e.payload()), methodName(old.Method), old.Compressed))
		total += len(e.Data)
	}
	return append(lines, fmt.Sprintf("salvaged entries %d bytes %d original %d verified %d", len(salvaged), len(archive), total, verified))
}
func textLines(data []byte) []string {
	if len(data) == 0 {
		return []string{}
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func extractionReport(entries []*Entry) []string {
	lines := []string{}
	for _, e := range entries {
		contents := textLines(e.Data)
		words, longest := 0, 0
		for _, line := range contents {
			longest = max(longest, len(line))
			for _, w := range strings.Split(line, " ") {
				if w != "" {
					words++
				}
			}
		}
		lines = append(lines, fmt.Sprintf("file %s bytes %d lines %d words %d longest %d", e.Name, len(e.Data), len(contents), words, longest))
		lines = append(lines, contents...)
	}
	return lines
}

type Edit struct {
	Sign    byte
	Number  int
	Content string
}

func editList(old, new []string) []Edit {
	a, b := len(old), len(new)
	below, current := make([]int, b+1), make([]int, b+1)
	decisions := make([][]byte, a)
	for i := a - 1; i >= 0; i-- {
		deletions := make([]byte, (b+7)/8)
		right := 0
		for j := b - 1; j >= 0; j-- {
			length := 0
			if old[i] == new[j] {
				length = below[j+1] + 1
			} else if below[j] >= right {
				length = below[j]
				deletions[j/8] |= 1 << uint(j%8)
			} else {
				length = right
			}
			current[j] = length
			right = length
		}
		decisions[i] = deletions
		below, current = current, below
	}
	edits := []Edit{}
	i, j := 0, 0
	for i < a || j < b {
		if i < a && j < b && old[i] == new[j] {
			i++
			j++
		} else if j == b || (i < a && decisions[i][j/8]&(1<<uint(j%8)) != 0) {
			edits = append(edits, Edit{'-', i + 1, old[i]})
			i++
		} else {
			edits = append(edits, Edit{'+', j + 1, new[j]})
			j++
		}
	}
	return edits
}
func comparisonReport(entries []*Entry, files []NamedFile) []string {
	manifest := map[string][]byte{}
	for _, f := range files {
		manifest[f.Name] = f.Data
	}
	seen := map[string]bool{}
	lines := []string{}
	for _, e := range entries {
		seen[e.Name] = true
		data, ok := manifest[e.Name]
		if !ok {
			lines = append(lines, "archive_only "+e.Name)
			continue
		}
		old, new := textLines(e.Data), textLines(data)
		first := 0
		for first < min(len(old), len(new)) && old[first] == new[first] {
			first++
		}
		if first == len(old) && first == len(new) {
			lines = append(lines, fmt.Sprintf("same %s lines %d", e.Name, len(old)))
			continue
		}
		edits := editList(old, new)
		removed := 0
		for _, edit := range edits {
			if edit.Sign == '-' {
				removed++
			}
		}
		lines = append(lines, fmt.Sprintf("differs %s first_line %d archive_lines %d manifest_lines %d removed %d added %d",
			e.Name, first+1, len(old), len(new), removed, len(edits)-removed))
		for _, edit := range edits {
			lines = append(lines, fmt.Sprintf("%c%d:%s", edit.Sign, edit.Number, edit.Content))
		}
	}
	for _, f := range files {
		if !seen[f.Name] {
			lines = append(lines, "new "+f.Name)
		}
	}
	return lines
}
func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name, []byte(text), 0644); e != nil {
		panic(e)
	}
}
func writeHex(name string, data []byte) {
	lines := []string{}
	for i := 0; i < len(data); i += 32 {
		lines = append(lines, hex.EncodeToString(data[i:min(i+32, len(data))]))
	}
	writeLines(name, lines)
}
func main() {
	p, files, supplied := readInputs()
	encodings := []Encoding{}
	for _, f := range files {
		encodings = append(encodings, encodeFile(f.Name, f.Data, p))
	}
	created := buildArchive(encodings, p)
	examined, verified := verifyArchive(created, encodings)
	parsed := parseArchive(supplied)
	sp := p
	if parsed.Error == "" {
		sp = Parameters{parsed.B, parsed.K, p.M}
	}
	salvaged := []Encoding{}
	for _, e := range parsed.intact() {
		salvaged = append(salvaged, encodeFile(e.Name, e.Data, sp))
	}
	salvage := buildArchive(salvaged, sp)
	_, salvageVerified := verifyArchive(salvage, salvaged)
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("sizes.txt", sizesReport(encodings, p, created, examined, verified))
	writeLines("analysis.txt", analysisReport(encodings))
	writeHex("archive.hex", created)
	writeLines("listing.txt", listingReport(parsed))
	writeLines("test_report.txt", testReport(parsed, salvaged, salvage, salvageVerified))
	writeLines("extracted.txt", extractionReport(parsed.intact()))
	writeLines("compare.txt", comparisonReport(parsed.intact(), files))
	writeHex("salvaged.hex", salvage)
}
