package main

import (
	"bufio"
	"errors"
	"fmt"
	"math/bits"
	"os"
	"slices"
	"sort"
	"strconv"
	"strings"
)

type Word uint32
type Command string

const (
	Gen Command = "GEN"
	Pcheck Command = "PCHECK"
	Hamming Command = "HAMMING"
	Simplex Command = "SIMPLEX"
	Repetition Command = "REPETITION"
	Parity Command = "PARITY"
	Rm Command = "RM"
	Cyclic Command = "CYCLIC"
	Dual Command = "DUAL"
	Extend Command = "EXTEND"
	Puncture Command = "PUNCTURE"
	Shorten Command = "SHORTEN"
	Augment Command = "AUGMENT"
	Expurgate Command = "EXPURGATE"
	Permute Command = "PERMUTE"
	Directsum Command = "DIRECTSUM"
	Uuv Command = "UUV"
	Product Command = "PRODUCT"
	List Command = "LIST"
	Delete Command = "DELETE"
	Show Command = "SHOW"
	Info Command = "INFO"
	Systematic Command = "SYSTEMATIC"
	Weights Command = "WEIGHTS"
	Covering Command = "COVERING"
	Burst Command = "BURST"
	Trellis Command = "TRELLIS"
	Stdarray Command = "STDARRAY"
	Equal Command = "EQUAL"
	Encode Command = "ENCODE"
	Syndrome Command = "SYNDROME"
	Decode Command = "DECODE"
	Bounded Command = "BOUNDED"
	Coset Command = "COSET"
	Erasure Command = "ERASURE"
	Interleave Command = "INTERLEAVE"
	Crc Command = "CRC"
	Crccheck Command = "CRCCHECK"
	Factor Command = "FACTOR"
	Macwilliams Command = "MACWILLIAMS"
	Bounds Command = "BOUNDS"
)

type Format struct {
	types string
	minimum, maximum int
}

var formats = map[Command]Format{
	Gen: {"NV", 2, 25}, Pcheck: {"NV", 2, 25},
	Hamming: {"NI", 2, 2}, Simplex: {"NI", 2, 2},
	Repetition: {"NI", 2, 2}, Parity: {"NI", 2, 2},
	Rm: {"NII", 3, 3}, Cyclic: {"NIV", 3, 3},
	Dual: {"NA", 2, 2}, Extend: {"NA", 2, 2},
	Puncture: {"NAI", 3, 3}, Shorten: {"NAI", 3, 3},
	Augment: {"NA", 2, 2}, Expurgate: {"NA", 2, 2},
	Permute: {"NAI", 3, 26}, Directsum: {"NAB", 3, 3},
	Uuv: {"NAB", 3, 3}, Product: {"NAB", 3, 3},
	List: {"", 0, 0}, Delete: {"A", 1, 1},
	Show: {"A", 1, 1}, Info: {"A", 1, 1},
	Systematic: {"A", 1, 1}, Weights: {"A", 1, 1},
	Covering: {"A", 1, 1}, Burst: {"A", 1, 1},
	Trellis: {"A", 1, 1}, Stdarray: {"A", 1, 1},
	Equal: {"AB", 2, 2}, Encode: {"AV", 2, 2},
	Syndrome: {"AV", 2, 2}, Decode: {"AV", 2, 2},
	Bounded: {"AIV", 3, 3}, Coset: {"AV", 2, 2},
	Erasure: {"AX", 2, 2}, Interleave: {"AIIV", 4, 11},
	Crc: {"VV", 2, 2}, Crccheck: {"VV", 2, 2},
	Factor: {"I", 1, 1}, Macwilliams: {"II", 2, 26}, Bounds: {"II", 2, 2},
}

func (command Command) defining() bool {
	switch command {
	case Gen, Pcheck, Hamming, Simplex, Repetition, Parity, Rm, Cyclic,
		Dual, Extend, Puncture, Shorten, Augment, Expurgate, Permute, Directsum, Uuv, Product:
		return true
	}
	return false
}

func letter(c byte) bool { return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' }
func digit(c byte) bool { return c >= '0' && c <= '9' }

func validWord(text string, kind byte) bool {
	if len(text) == 0 {
		return false
	}
	switch kind {
	case 'N', 'A', 'B':
		if len(text) > 8 || !letter(text[0]) {
			return false
		}
		for i := range len(text) {
			if !letter(text[i]) && !digit(text[i]) {
				return false
			}
		}
	case 'I':
		if len(text) > 4 || len(text) > 1 && text[0] == '0' {
			return false
		}
		for i := range len(text) {
			if !digit(text[i]) {
				return false
			}
		}
	default:
		if len(text) > 30 {
			return false
		}
		for i := range len(text) {
			if text[i] != '0' && text[i] != '1' && !(kind == 'X' && text[i] == '?') {
				return false
			}
		}
	}
	return true
}

func number(text string) int { value, _ := strconv.Atoi(text); return value }
func parseWord(text string) Word { value, _ := strconv.ParseUint(text, 2, 32); return Word(value) }
func mask(n int) Word { return (Word(1) << n) - 1 }
func bit(n, column int) Word { return Word(1) << (n - column - 1) }
func weight(word Word) int { return bits.OnesCount32(uint32(word)) }
func length(word Word) int { return bits.Len32(uint32(word)) }
func wordText(word Word, n int) string { return fmt.Sprintf("%0*b", n, word) }
func yes(value bool) string { if value { return "yes" }; return "no" }
func asBit(value bool) Word { if value { return 1 }; return 0 }

func divide(value, divisor Word) (Word, Word) {
	var quotient Word
	for value != 0 && length(value) >= length(divisor) {
		shift := length(value) - length(divisor)
		quotient ^= Word(1) << shift
		value ^= divisor << shift
	}
	return quotient, value
}

func basis(rows []Word, n int) []Word {
	var pivots [32]Word
	var result []Word
	for _, original := range rows {
		row := original
		for column := n - 1; column >= 0; column-- {
			if row&(Word(1)<<column) == 0 {
				continue
			}
			if pivots[column] != 0 {
				row ^= pivots[column]
			} else {
				pivots[column] = row
				result = append(result, original)
				break
			}
		}
	}
	return result
}

func rref(source []Word, n int) ([]Word, []int) {
	rows := slices.Clone(source)
	var pivots []int
	for column := range n {
		rank := len(pivots)
		found := rank
		for found < len(rows) && rows[found]&bit(n, column) == 0 {
			found++
		}
		if found == len(rows) {
			continue
		}
		rows[rank], rows[found] = rows[found], rows[rank]
		for i := range rows {
			if i != rank && rows[i]&bit(n, column) != 0 {
				rows[i] ^= rows[rank]
			}
		}
		pivots = append(pivots, column)
	}
	return rows[:len(pivots)], pivots
}

func nullSpace(source []Word, n int) []Word {
	rows, pivots := rref(source, n)
	var result []Word
	for column := range n {
		if slices.Contains(pivots, column) {
			continue
		}
		row := bit(n, column)
		for i, pivot := range pivots {
			if rows[i]&bit(n, column) != 0 {
				row |= bit(n, pivot)
			}
		}
		result = append(result, row)
	}
	return result
}

func span(rows []Word) []Word {
	words := []Word{0}
	for _, row := range rows {
		for i := range len(words) {
			words = append(words, words[i]^row)
		}
	}
	return words
}

func reedMuller(r, m int) []Word {
	if r == 0 {
		return []Word{mask(1 << m)}
	}
	half := 1 << (m - 1)
	var rows []Word
	for _, row := range reedMuller(min(r, m-1), m-1) {
		rows = append(rows, (row<<half)|row)
	}
	return append(rows, reedMuller(r-1, m-1)...)
}

func checkDimension(n, k int) error {
	if k < 1 || k > 12 || n-k < 1 || n-k > 12 {
		return fmt.Errorf("bad dimension %d %d", n, k)
	}
	return nil
}

type Code struct {
	n int
	g, h []Word
	polynomial *Word
}

type Decoded struct { word, message, error Word }

func newCode(n int, g, h []Word, polynomial *Word) (*Code, error) {
	if err := checkDimension(n, len(g)); err != nil {
		return nil, err
	}
	if h == nil {
		h = nullSpace(g, n)
	}
	return &Code{n, g, h, polynomial}, nil
}

func (code *Code) k() int { return len(code.g) }
func (code *Code) encoder() string { if code.polynomial != nil { return "polynomial" }; return "matrix" }

func (code *Code) encode(message Word) Word {
	if code.polynomial != nil {
		shifted := message << len(code.h)
		_, remainder := divide(shifted, *code.polynomial)
		return shifted | remainder
	}
	var result Word
	for i, row := range code.g {
		if message&bit(code.k(), i) != 0 {
			result ^= row
		}
	}
	return result
}

func (code *Code) syndrome(word Word) Word {
	var result Word
	for _, row := range code.h {
		result = (result << 1) | Word(weight(row&word)&1)
	}
	return result
}

func (code *Code) message(word Word) Word {
	for message := Word(0); message < Word(1)<<code.k(); message++ {
		if code.encode(message) == word {
			return message
		}
	}
	panic("word outside code")
}

func (code *Code) leaders() []Word {
	result := make([]Word, 1<<len(code.h))
	for i := range result {
		result[i] = ^Word(0)
	}
	result[0] = 0
	found := 1
	for w := 1; w <= code.n; w++ {
		for word := mask(w); word < Word(1)<<code.n; {
			s := code.syndrome(word)
			if result[s] == ^Word(0) {
				result[s] = word
				found++
				if found == len(result) {
					return result
				}
			}
			lowest := word & -word
			next := word + lowest
			word = next | (((next ^ word) >> 2) / lowest)
		}
	}
	return result
}

func (code *Code) decode(word Word, leaders []Word) Decoded {
	error := leaders[code.syndrome(word)]
	return Decoded{word ^ error, code.message(word ^ error), error}
}

func (code *Code) decodedText(decoded Decoded) string {
	return fmt.Sprintf("codeword %s message %s error %s weight %d", wordText(decoded.word, code.n),
		wordText(decoded.message, code.k()), wordText(decoded.error, code.n), weight(decoded.error))
}

func (code *Code) burstCorrection() int {
	seen := make([]bool, 1<<len(code.h))
	seen[0] = true
	for size := 1; size <= code.n; size++ {
		variants := Word(1)
		if size > 1 {
			variants <<= size - 2
		}
		for offset := 0; offset <= code.n-size; offset++ {
			for middle := Word(0); middle < variants; middle++ {
				word := Word(1)
				if size > 1 {
					word = (Word(1) << (size - 1)) | (middle << 1) | 1
				}
				s := code.syndrome(word << offset)
				if seen[s] {
					return size - 1
				}
				seen[s] = true
			}
		}
	}
	panic("no colliding burst")
}

func construct(command Command, args []string, a, b *Code) (*Code, error) {
	var n int
	var g, h []Word
	var polynomial *Word
	switch command {
	case Gen, Pcheck:
		n = len(args[1])
		var rows []Word
		for _, text := range args[1:] {
			if len(text) != n {
				return nil, errors.New("bad length")
			}
			rows = append(rows, parseWord(text))
		}
		rows = basis(rows, n)
		if command == Gen {
			g = rows
		} else {
			h, g = rows, nullSpace(rows, n)
		}
	case Hamming, Simplex:
		r := number(args[1])
		if r < 2 || r > 4 {
			return nil, errors.New("bad parameter")
		}
		n = (1 << r) - 1
		rows := make([]Word, r)
		for i := range r {
			for j := 1; j <= n; j++ {
				rows[i] = (rows[i] << 1) | Word((j>>(r-i-1))&1)
			}
		}
		if command == Simplex {
			g = rows
		} else {
			h, g = rows, nullSpace(rows, n)
		}
	case Repetition, Parity:
		n = number(args[1])
		if n < 2 || n > 24 {
			return nil, errors.New("bad parameter")
		}
		if command == Repetition {
			g = []Word{mask(n)}
		} else {
			for i := range n - 1 {
				g = append(g, bit(n, i)|1)
			}
		}
	case Rm:
		r, m := number(args[1]), number(args[2])
		if m < 1 || m > 4 || r > m {
			return nil, errors.New("bad parameter")
		}
		n, g = 1<<m, reedMuller(r, m)
	case Cyclic:
		n = number(args[1])
		d := len(args[2]) - 1
		if n < 2 || n > 24 || args[2][0] != '1' || d < 1 || d >= n {
			return nil, errors.New("bad parameter")
		}
		p := parseWord(args[2])
		if _, remainder := divide((Word(1)<<n)|1, p); remainder != 0 {
			return nil, errors.New("not a divisor")
		}
		k := n - d
		for i := range k {
			g = append(g, p<<(k-i-1))
		}
		h = make([]Word, d)
		for j := range n {
			_, remainder := divide(bit(n, j), p)
			for i := range d {
				h[i] = (h[i] << 1) | ((remainder >> (d - i - 1)) & 1)
			}
		}
		polynomial = &p
	case Dual:
		n, g, h = a.n, a.h, a.g
	case Extend:
		n = a.n + 1
		for _, row := range a.g {
			g = append(g, (row<<1)|Word(weight(row)&1))
		}
	case Puncture, Shorten, Expurgate:
		position := 0
		n = a.n
		if command != Expurgate {
			position = number(args[2])
			if position < 1 || position > a.n {
				return nil, errors.New("bad position")
			}
			n--
		}
		selected := func(row Word) bool {
			if command == Expurgate {
				return weight(row)&1 != 0
			}
			return row&bit(a.n, position-1) != 0
		}
		removed := -1
		if command != Puncture {
			for i, row := range a.g {
				if selected(row) {
					removed = i
					break
				}
			}
		}
		for i, row := range a.g {
			if i == removed {
				continue
			}
			if removed >= 0 && selected(row) {
				row ^= a.g[removed]
			}
			if command != Expurgate {
				low := a.n - position
				row = ((row >> (low + 1)) << low) | (row & mask(low))
			}
			g = append(g, row)
		}
		if command == Puncture {
			g = basis(g, n)
		}
	case Augment:
		n = a.n
		g = basis(append(slices.Clone(a.g), mask(n)), n)
	case Permute:
		n = a.n
		if len(args)-2 != n {
			return nil, errors.New("bad permutation")
		}
		used := make([]bool, n+1)
		for _, text := range args[2:] {
			position := number(text)
			if position < 1 || position > n || used[position] {
				return nil, errors.New("bad permutation")
			}
			used[position] = true
		}
		for _, original := range a.g {
			var row Word
			for _, text := range args[2:] {
				row = (row << 1) | asBit(original&bit(n, number(text)-1) != 0)
			}
			g = append(g, row)
		}
	case Directsum, Uuv, Product:
		if command == Uuv && a.n != b.n {
			return nil, errors.New("bad length")
		}
		n, k := a.n+b.n, a.k()+b.k()
		if command == Product {
			n, k = a.n*b.n, a.k()*b.k()
		}
		if err := checkDimension(n, k); err != nil {
			return nil, err
		}
		if command == Product {
			for _, x := range a.g {
				for _, y := range b.g {
					var row Word
					for i := range a.n {
						row <<= b.n
						if x&bit(a.n, i) != 0 {
							row |= y
						}
					}
					g = append(g, row)
				}
			}
		} else {
			for _, row := range a.g {
				value := row << b.n
				if command == Uuv {
					value |= row
				}
				g = append(g, value)
			}
			g = append(g, b.g...)
		}
		return newCode(n, g, nil, nil)
	}
	return newCode(n, g, h, polynomial)
}

func distribution(words []Word, offset Word, n int) []int64 {
	counts := make([]int64, n+1)
	for _, word := range words {
		counts[weight(word^offset)]++
	}
	return counts
}

func weightList(counts []int64) string {
	var items []string
	for i, count := range counts {
		if count != 0 {
			items = append(items, fmt.Sprintf("%d:%d", i, count))
		}
	}
	return strings.Join(items, " ")
}

func gcd(a, b int64) int64 {
	if a < 0 {
		a = -a
	}
	for b != 0 {
		a, b = b, a%b
	}
	return a
}

var combinations = func() [25][25]int64 {
	var table [25][25]int64
	for n := 0; n <= 24; n++ {
		table[n][0], table[n][n] = 1, 1
		for k := 1; k < n; k++ {
			table[n][k] = table[n-1][k-1] + table[n-1][k]
		}
	}
	return table
}()

func choose(n, k int) int64 {
	if k < 0 || k > n {
		return 0
	}
	return combinations[n][k]
}

func volume(n, radius int) int64 {
	var sum int64
	for i := 0; i <= radius; i++ {
		sum += choose(n, i)
	}
	return sum
}

func krawtchouk(n, j, x int) int64 {
	var sum int64
	for y := 0; y <= j; y++ {
		term := choose(x, y) * choose(n-x, j-y)
		if y%2 == 0 {
			sum += term
		} else {
			sum -= term
		}
	}
	return sum
}

func matrixText(out *strings.Builder, label string, rows []Word, n int) {
	for _, row := range rows {
		fmt.Fprintf(out, "%s %s\n", label, wordText(row, n))
	}
}

func systematic(name string, code *Code) string {
	rows := slices.Clone(code.g)
	permutation := make([]int, code.n)
	for i := range permutation {
		permutation[i] = i + 1
	}
	for r := range code.k() {
		column, found := r, r
		for {
			found = r
			for found < len(rows) && rows[found]&bit(code.n, column) == 0 {
				found++
			}
			if found < len(rows) {
				break
			}
			column++
		}
		if column != r {
			left, right := bit(code.n, r), bit(code.n, column)
			for i, row := range rows {
				if (row&left != 0) != (row&right != 0) {
					rows[i] ^= left | right
				}
			}
			permutation[r], permutation[column] = permutation[column], permutation[r]
		}
		rows[r], rows[found] = rows[found], rows[r]
		for i := range rows {
			if i != r && rows[i]&bit(code.n, r) != 0 {
				rows[i] ^= rows[r]
			}
		}
	}
	var out strings.Builder
	fmt.Fprintf(&out, "systematic %s perm", name)
	for _, column := range permutation {
		fmt.Fprintf(&out, " %d", column)
	}
	out.WriteByte('\n')
	matrixText(&out, "G", rows, code.n)
	for j := range len(code.h) {
		var row Word
		for _, value := range rows {
			row = (row << 1) | asBit(value&bit(code.n, code.k()+j) != 0)
		}
		row = (row << len(code.h)) | bit(len(code.h), j)
		fmt.Fprintf(&out, "H %s\n", wordText(row, code.n))
	}
	return out.String()
}

func independent(command Command, args []string) (string, error) {
	if command == Crc || command == Crccheck {
		d := len(args[0]) - 1
		if args[0][0] != '1' || d < 1 || d > 16 {
			return "", errors.New("bad parameter")
		}
		if command == Crc && len(args[1])+d > 30 {
			return "", errors.New("bad length")
		}
		value := parseWord(args[1])
		if command == Crc {
			value <<= d
		}
		_, remainder := divide(value, parseWord(args[0]))
		suffix := wordText(remainder, d)
		if command == Crc {
			return fmt.Sprintf("crc remainder %s frame %s%s\n", suffix, args[1], suffix), nil
		}
		status := "ok"
		if remainder != 0 {
			status = "error"
		}
		return fmt.Sprintf("crccheck %s remainder %s\n", status, suffix), nil
	}
	n := number(args[0])
	if command == Bounds {
		d := number(args[1])
		if d < 1 || d > n || n > 24 {
			return "", errors.New("bad parameter")
		}
		v := volume(n, (d-1)/2)
		hamming, griesmer, sum := 0, 0, 0
		for k := 0; k <= n; k++ {
			if (int64(1)<<k)*v <= int64(1)<<n {
				hamming = k
			}
		}
		for k := 1; k <= n; k++ {
			denominator := 1 << (k - 1)
			sum += (d + denominator - 1) / denominator
			if sum <= n {
				griesmer = k
			}
		}
		return fmt.Sprintf("bounds n %d d %d singleton %d hamming %d griesmer %d\n", n, d, n-d+1, hamming, griesmer), nil
	}
	if n < 1 || n > 24 {
		return "", errors.New("bad parameter")
	}
	var out strings.Builder
	if command == Factor {
		remaining := (Word(1) << n) | 1
		divisors := 1
		fmt.Fprintf(&out, "factor %d", n)
		for factor := Word(3); 2*(length(factor)-1) <= length(remaining)-1; factor += 2 {
			exponent := 0
			for {
				quotient, remainder := divide(remaining, factor)
				if remainder != 0 {
					break
				}
				remaining = quotient
				exponent++
			}
			if exponent != 0 {
				fmt.Fprintf(&out, " %s^%d", wordText(factor, length(factor)), exponent)
				divisors *= exponent + 1
			}
		}
		if remaining != 1 {
			fmt.Fprintf(&out, " %s^1", wordText(remaining, length(remaining)))
			divisors *= 2
		}
		fmt.Fprintf(&out, " divisors %d\n", divisors)
		return out.String(), nil
	}
	if len(args) != n+2 {
		return "", errors.New("bad length")
	}
	if number(args[1]) != 1 {
		return "", errors.New("bad parameter")
	}
	var size int64
	for _, text := range args[1:] {
		size += int64(number(text))
	}
	feasible := size&(size-1) == 0
	fmt.Fprintf(&out, "macwilliams n %d size %d\ndual", n, size)
	for j := 0; j <= n; j++ {
		var numerator int64
		for x := 0; x <= n; x++ {
			numerator += int64(number(args[x+1])) * krawtchouk(n, j, x)
		}
		if numerator < 0 || numerator%size != 0 {
			feasible = false
		}
		divisor := gcd(numerator, size)
		fmt.Fprintf(&out, " %d", numerator/divisor)
		if denominator := size / divisor; denominator != 1 {
			fmt.Fprintf(&out, "/%d", denominator)
		}
	}
	fmt.Fprintf(&out, "\nfeasible %s\n", yes(feasible))
	return out.String(), nil
}

type Laboratory struct { codes map[string]*Code }

func (lab *Laboratory) process(line string) (string, error) {
	words := strings.Split(line, " ")
	command := Command(words[0])
	format, exists := formats[command]
	if !exists {
		return "", fmt.Errorf("unknown command %s", words[0])
	}
	args := words[1:]
	if len(args) < format.minimum || len(args) > format.maximum {
		return "", errors.New("bad arguments")
	}
	for i, text := range args {
		if !validWord(text, format.types[min(i, len(format.types)-1)]) {
			return "", errors.New("bad arguments")
		}
	}
	var a, b *Code
	for i := range len(format.types) {
		kind := format.types[i]
		if kind != 'A' && kind != 'B' {
			continue
		}
		code, exists := lab.codes[args[i]]
		if !exists {
			return "", fmt.Errorf("no code %s", args[i])
		}
		if kind == 'A' {
			a = code
		} else {
			b = code
		}
	}
	if command.defining() {
		code, err := construct(command, args, a, b)
		if err != nil {
			return "", err
		}
		status := "defined"
		if _, exists := lab.codes[args[0]]; exists {
			status = "redefined"
		}
		lab.codes[args[0]] = code
		return fmt.Sprintf("%s %s n %d k %d\n", status, args[0], code.n, code.k()), nil
	}
	switch command {
	case Crc, Crccheck, Factor, Macwilliams, Bounds:
		return independent(command, args)
	}
	var out strings.Builder
	if command == List {
		names := make([]string, 0, len(lab.codes))
		for name := range lab.codes {
			names = append(names, name)
		}
		sort.Strings(names)
		fmt.Fprintf(&out, "codes %d\n", len(names))
		for _, name := range names {
			code := lab.codes[name]
			fmt.Fprintf(&out, "%s n %d k %d encoder %s\n", name, code.n, code.k(), code.encoder())
		}
		return out.String(), nil
	}
	name := args[0]
	if command == Delete {
		delete(lab.codes, name)
		return fmt.Sprintf("deleted %s\n", name), nil
	}
	n, k := a.n, a.k()
	switch command {
	case Show:
		fmt.Fprintf(&out, "code %s n %d k %d encoder %s\n", name, n, k, a.encoder())
		if a.polynomial != nil {
			quotient, _ := divide((Word(1)<<n)|1, *a.polynomial)
			fmt.Fprintf(&out, "poly g %s h %s\n", wordText(*a.polynomial, n-k+1), wordText(quotient, k+1))
		}
		matrixText(&out, "G", a.g, n)
		matrixText(&out, "H", a.h, n)
	case Info:
		words := span(a.g)
		distance, generator := n, ^Word(0)
		for _, word := range words[1:] {
			distance, generator = min(distance, weight(word)), min(generator, word)
		}
		t, divisor := (distance-1)/2, gcd(int64(k), int64(n))
		cyclic := true
		for _, row := range a.g {
			if a.syndrome(((row<<1)&mask(n))|(row>>(n-1))) != 0 {
				cyclic = false
			}
		}
		text := "no"
		if cyclic {
			text = wordText(generator, length(generator))
		}
		fmt.Fprintf(&out, "info %s n %d k %d rate %d/%d d %d t %d perfect %s mds %s cyclic %s\n",
			name, n, k, int64(k)/divisor, int64(n)/divisor, distance, t,
			yes(volume(n, t) == int64(1)<<(n-k)), yes(distance == n-k+1), text)
	case Systematic:
		return systematic(name, a), nil
	case Weights:
		primary, dual := distribution(span(a.g), 0, n), distribution(span(a.h), 0, n)
		orthogonal := true
		for _, x := range a.g {
			for _, y := range a.g {
				if weight(x&y)&1 != 0 {
					orthogonal = false
				}
			}
		}
		fmt.Fprintf(&out, "weights %s %s\ndual %s %s\n", name, weightList(primary), name, weightList(dual))
		fmt.Fprintf(&out, "duality %s self-orthogonal %s self-dual %s formally-self-dual %s\n",
			name, yes(orthogonal), yes(orthogonal && n == 2*k), yes(slices.Equal(primary, dual)))
	case Covering:
		counts := distribution(a.leaders(), 0, n)
		radius := n
		for counts[radius] == 0 {
			radius--
		}
		fmt.Fprintf(&out, "covering %s radius %d leaders", name, radius)
		for i := 0; i <= radius; i++ {
			fmt.Fprintf(&out, " %d:%d", i, counts[i])
		}
		out.WriteByte('\n')
	case Burst:
		detect := n
		for _, word := range span(a.g)[1:] {
			detect = min(detect, length(word)-bits.TrailingZeros32(uint32(word))-1)
		}
		fmt.Fprintf(&out, "burst %s detect %d correct %d\n", name, detect, a.burstCorrection())
	case Trellis:
		fmt.Fprintf(&out, "trellis %s profile", name)
		maximum := 0
		for cut := 0; cut <= n; cut++ {
			right := n - cut
			prefix, suffix := make([]Word, k), make([]Word, k)
			for i, row := range a.g {
				prefix[i], suffix[i] = row>>right, row&mask(right)
			}
			states := len(basis(prefix, cut)) + len(basis(suffix, right)) - k
			maximum = max(maximum, states)
			fmt.Fprintf(&out, " %d", states)
		}
		fmt.Fprintf(&out, " max %d\n", maximum)
	case Stdarray:
		if n-k > 6 || k > 4 {
			return "", errors.New("too large")
		}
		leaders := a.leaders()
		syndromes := make([]int, len(leaders))
		for i := range syndromes {
			syndromes[i] = i
		}
		sort.Slice(syndromes, func(i, j int) bool {
			x, y := leaders[syndromes[i]], leaders[syndromes[j]]
			if weight(x) != weight(y) {
				return weight(x) < weight(y)
			}
			return x < y
		})
		words := span(a.g)
		slices.Sort(words)
		fmt.Fprintf(&out, "stdarray %s rows %d columns %d\n", name, len(leaders), len(words))
		for _, s := range syndromes {
			fmt.Fprintf(&out, "%s:", wordText(Word(s), n-k))
			for _, word := range words {
				fmt.Fprintf(&out, " %s", wordText(leaders[s]^word, n))
			}
			out.WriteByte('\n')
		}
	case Equal:
		if n != b.n {
			fmt.Fprintf(&out, "equal %s %s no lengths %d %d\n", name, args[1], n, b.n)
		} else {
			rows := append(slices.Clone(a.g), b.g...)
			common := k + b.k() - len(basis(rows, n))
			fmt.Fprintf(&out, "equal %s %s %s intersection %d\n", name, args[1], yes(k == common && b.k() == common), common)
		}
	case Encode:
		if len(args[1]) != k {
			return "", errors.New("bad length")
		}
		fmt.Fprintf(&out, "encode %s message %s codeword %s\n", name, args[1], wordText(a.encode(parseWord(args[1])), n))
	case Syndrome, Decode, Bounded, Coset:
		position := 1
		if command == Bounded {
			position = 2
		}
		if len(args[position]) != n {
			return "", errors.New("bad length")
		}
		word := parseWord(args[position])
		s := a.syndrome(word)
		if command == Syndrome {
			fmt.Fprintf(&out, "syndrome %s %s codeword %s\n", name, wordText(s, n-k), yes(s == 0))
		} else {
			decoded := a.decode(word, a.leaders())
			if command == Coset {
				counts := distribution(span(a.g), word, n)
				fmt.Fprintf(&out, "coset %s syndrome %s leader %s weights %s\n", name, wordText(s, n-k), wordText(decoded.error, n), weightList(counts))
			} else if command == Bounded && weight(decoded.error) > number(args[1]) {
				fmt.Fprintf(&out, "bounded %s fail weight %d\n", name, weight(decoded.error))
			} else {
				prefix := "decode"
				if command == Bounded {
					prefix = "bounded"
				}
				fmt.Fprintf(&out, "%s %s %s\n", prefix, name, a.decodedText(decoded))
			}
		}
	case Erasure:
		if len(args[1]) != n {
			return "", errors.New("bad length")
		}
		var known, value, candidate Word
		erased, candidates := 0, 0
		for i, character := range args[1] {
			if character == '?' {
				erased++
			} else {
				known |= bit(n, i)
				if character == '1' {
					value |= bit(n, i)
				}
			}
		}
		for _, word := range span(a.g) {
			if word&known == value {
				candidate = word
				candidates++
			}
		}
		fmt.Fprintf(&out, "erasure %s erased %d candidates %d", name, erased, candidates)
		if candidates == 1 {
			fmt.Fprintf(&out, " codeword %s message %s", wordText(candidate, n), wordText(a.message(candidate), k))
		}
		out.WriteByte('\n')
	case Interleave:
		depth, start, size := len(args)-3, number(args[1]), number(args[2])
		for _, text := range args[3:] {
			if len(text) != k {
				return "", errors.New("bad length")
			}
		}
		if start < 1 || size < 1 || start+size-1 > depth*n {
			return "", errors.New("bad burst")
		}
		sentRows, receivedRows := make([]Word, depth), make([]Word, depth)
		for i := range depth {
			sentRows[i] = a.encode(parseWord(args[i+3]))
		}
		sent, received := make([]byte, depth*n), make([]byte, depth*n)
		for column := range n {
			for i := range depth {
				position := column*depth + i
				value := sentRows[i]&bit(n, column) != 0
				sent[position] = '0' + byte(asBit(value))
				if position >= start-1 && position < start-1+size {
					value = !value
				}
				received[position] = '0' + byte(asBit(value))
				receivedRows[i] = (receivedRows[i] << 1) | asBit(value)
			}
		}
		fmt.Fprintf(&out, "interleave %s depth %d burst %d %d\nsent %s\nrecv %s\n", name, depth, start, size, sent, received)
		leaders, correct := a.leaders(), 0
		for i := range depth {
			decoded := a.decode(receivedRows[i], leaders)
			status := "wrong"
			if decoded.message == parseWord(args[i+3]) {
				status = "ok"
				correct++
			}
			fmt.Fprintf(&out, "row %d errors %d corrected %d message %s %s\n", i+1,
				weight(receivedRows[i]^sentRows[i]), weight(decoded.error), wordText(decoded.message, k), status)
		}
		fmt.Fprintf(&out, "result ok %d wrong %d\n", correct, depth-correct)
	}
	return out.String(), nil
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {
		return
	}
	count := number(scanner.Text())
	lab := Laboratory{codes: make(map[string]*Code)}
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	for i := 0; i < count && scanner.Scan(); i++ {
		text, err := lab.process(scanner.Text())
		if err != nil {
			fmt.Fprintln(output, "error:", err)
		} else {
			fmt.Fprint(output, text)
		}
	}
}
