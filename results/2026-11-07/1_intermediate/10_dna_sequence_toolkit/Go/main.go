package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

const bases = "ACGT"

var iupac = map[byte]string{
	'A': "A", 'C': "C", 'G': "G", 'T': "T", 'R': "AG",
	'Y': "CT", 'W': "AT", 'S': "CG", 'K': "GT", 'M': "AC",
	'B': "CGT", 'D': "AGT", 'H': "ACT", 'V': "ACG", 'N': "ACGT",
}
var complements = map[byte]byte{
	'A': 'T', 'C': 'G', 'G': 'C', 'T': 'A', 'R': 'Y',
	'Y': 'R', 'W': 'W', 'S': 'S', 'K': 'M', 'M': 'K',
	'B': 'V', 'D': 'H', 'H': 'D', 'V': 'B', 'N': 'N',
}
var groups = map[byte]string{
	'A': "GCT GCC GCA GCG", 'C': "TGT TGC", 'D': "GAT GAC",
	'E': "GAA GAG", 'F': "TTT TTC", 'G': "GGT GGC GGA GGG",
	'H': "CAT CAC", 'I': "ATT ATC ATA", 'K': "AAA AAG",
	'L': "TTA TTG CTT CTC CTA CTG", 'M': "ATG", 'N': "AAT AAC",
	'P': "CCT CCC CCA CCG", 'Q': "CAA CAG",
	'R': "CGT CGC CGA CGG AGA AGG", 'S': "TCT TCC TCA TCG AGT AGC",
	'T': "ACT ACC ACA ACG", 'V': "GTT GTC GTA GTG", 'W': "TGG",
	'Y': "TAT TAC", '*': "TAA TAG TGA",
}
var aminoMass = map[byte]int{
	'A': 71079, 'C': 103139, 'D': 115089, 'E': 129116,
	'F': 147177, 'G': 57052, 'H': 137141, 'I': 113160,
	'K': 128174, 'L': 113160, 'M': 131193, 'N': 114104,
	'P': 97117, 'Q': 128131, 'R': 156188, 'S': 87078,
	'T': 101105, 'V': 99133, 'W': 186213, 'Y': 163176,
}
var baseMass = map[byte]int{
	'A': 331222, 'C': 307197, 'G': 347221, 'T': 322208,
}
type enzyme struct {
	motif  string
	offset int
}
var enzymes = map[string]enzyme{
	"EcoRI": {"GAATTC", 1}, "BamHI": {"GGATCC", 1},
	"HindIII": {"AAGCTT", 1}, "PstI": {"CTGCAG", 5},
	"SmaI": {"CCCGGG", 3}, "KpnI": {"GGTACC", 5},
	"XbaI": {"TCTAGA", 1}, "NotI": {"GCGGCCGC", 2},
	"EcoRV": {"GATATC", 3}, "HaeIII": {"GGCC", 2},
	"AluI": {"AGCT", 2}, "TaqI": {"TCGA", 1},
	"Sau3AI": {"GATC", 0}, "HincII": {"GTYRAC", 3},
	"AvaI": {"CYCGRG", 1},
}

var arity = map[string][2]int{
	"SEQ": {2, 2}, "SLICE": {4, 4}, "JOIN": {3, 9},
	"MUTATE": {3, 3}, "DEL": {1, 1}, "LIST": {0, 0},
	"REVCOMP": {1, 1}, "COMPLEMENT": {1, 1}, "REVERSE": {1, 1},
	"TRANSCRIBE": {1, 1}, "TRANSLATE": {2, 2}, "CODONS": {2, 2},
	"PROTEIN": {2, 2}, "ORFS": {2, 2}, "GC": {1, 1},
	"GCWINDOW": {3, 3}, "SKEW": {1, 1}, "KMERS": {3, 3},
	"FIND": {2, 2}, "RESTRICT": {2, 7}, "PALINDROMES": {3, 3},
	"REPEATS": {4, 4}, "HAMMING": {2, 2}, "ALIGN": {6, 6},
	"CONSENSUS": {2, 10}, "TM": {1, 1}, "MASS": {1, 1},
	"PRIMER": {1, 1}, "FOLD": {2, 2}, "ASSEMBLE": {4, 10},
	"PACK": {1, 1}, "UNPACK": {3, 3},
}
var integerPattern = regexp.MustCompile("^-?[0-9]{1,6}$")
var namePattern = regexp.MustCompile("^[a-z][a-z0-9]{0,9}$")
var hexPattern = regexp.MustCompile("^[0-9A-F]+$")

func geneticCode() map[string]byte {
	code := make(map[string]byte)
	for amino, codons := range groups {
		for _, triplet := range strings.Fields(codons) {
			code[triplet] = amino
		}
	}
	return code
}

func complement(sequence string) string {
	result := []byte(sequence)
	for i, base := range result {
		result[i] = complements[base]
	}
	return string(result)
}

func revcomp(sequence string) string {
	result := []byte(complement(sequence))
	for i, j := 0, len(result)-1; i < j; i, j = i+1, j-1 {
		result[i], result[j] = result[j], result[i]
	}
	return string(result)
}

func gc(sequence string) int {
	return strings.Count(sequence, "G") + strings.Count(sequence, "C")
}

func fixed(value, places int) string {
	scale := 1
	for i := 0; i < places; i++ {
		scale *= 10
	}
	return fmt.Sprintf("%d.%0*d", value/scale, places, value%scale)
}

func pct(part, whole int) string {
	return fixed(10000*part/whole, 2)
}

func transition(a, b byte) bool {
	return a != b && (a == 'A' && b == 'G' || a == 'G' && b == 'A' ||
		a == 'C' && b == 'T' || a == 'T' && b == 'C')
}

func frequencyOrder(counts map[string]int) []string {
	keys := make([]string, 0, len(counts))
	for key := range counts {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		if counts[keys[i]] != counts[keys[j]] {
			return counts[keys[i]] > counts[keys[j]]
		}
		return keys[i] < keys[j]
	})
	return keys
}

func codons(sequence string, frame int) []string {
	strand := sequence
	if frame < 0 {
		strand = revcomp(sequence)
		frame = -frame
	}
	var result []string
	for i := frame - 1; i+2 < len(strand); i += 3 {
		result = append(result, strand[i:i+3])
	}
	return result
}

func occurrences(sequence, motif string) []int {
	var positions []int
	for i := 0; i+len(motif) <= len(sequence); i++ {
		matched := true
		for j := 0; j < len(motif); j++ {
			if !strings.ContainsRune(iupac[motif[j]], rune(sequence[i+j])) {
				matched = false
				break
			}
		}
		if matched {
			positions = append(positions, i+1)
		}
	}
	return positions
}

func repeatCount(sequence string, position, width int) int {
	unit := sequence[position : position+width]
	count := 0
	for position+(count+1)*width <= len(sequence) &&
		sequence[position+count*width:position+(count+1)*width] == unit {
		count++
	}
	return count
}

func primitive(unit string) bool {
	for width := 1; width < len(unit); width++ {
		if len(unit)%width != 0 {
			continue
		}
		repeated := true
		for i := width; i < len(unit); i++ {
			if unit[i] != unit[i%width] {
				repeated = false
				break
			}
		}
		if repeated {
			return false
		}
	}
	return true
}

func longestPalindrome(sequence string) int {
	best := 0
	for center := 1; center < len(sequence); center++ {
		left, right := center-1, center
		for left >= 0 && right < len(sequence) &&
			complements[sequence[left]] == sequence[right] {
			if right-left+1 > best {
				best = right-left+1
			}
			left--
			right++
		}
	}
	return best
}

func temperature(sequence string) int {
	n, amount := len(sequence), gc(sequence)
	if n < 14 {
		return 10 * (2*(n-amount) + 4*amount)
	}
	return (649*n + 410*amount - 6724)/n
}

func strandMass(sequence string) int {
	mass := 0
	for i := 0; i < len(sequence); i++ {
		mass += baseMass[sequence[i]]
	}
	return mass - (len(sequence)-1)*18015
}

func kinds(command string, count int) []string {
	switch command {
	case "SEQ":
		return []string{"new", "sequence"}
	case "SLICE":
		return []string{"name", "position", "position", "new"}
	case "MUTATE":
		return []string{"name", "position", "base"}
	case "TRANSLATE", "CODONS", "PROTEIN":
		return []string{"name", "frame"}
	case "ORFS":
		return []string{"name", "orf"}
	case "GCWINDOW":
		return []string{"name", "window", "window"}
	case "KMERS":
		return []string{"name", "kmer", "limit"}
	case "FIND":
		return []string{"name", "motif"}
	case "PALINDROMES":
		return []string{"name", "palindrome", "palindrome"}
	case "REPEATS":
		return []string{"name", "repeat", "repeat", "repeatCount"}
	case "ALIGN":
		return []string{"name", "name", "mode", "match", "mismatch", "gap"}
	case "FOLD":
		return []string{"name", "loop"}
	case "UNPACK":
		return []string{"new", "length", "hex"}
	}
	result := make([]string, count)
	for i := range result {
		result[i] = "name"
	}
	if command == "JOIN" || command == "ASSEMBLE" {
		result[0] = "new"
	}
	if command == "ASSEMBLE" {
		result[1] = "overlap"
	}
	if command == "RESTRICT" {
		for i := 1; i < count; i++ {
			result[i] = "enzyme"
		}
	}
	return result
}

func number(text string, min, max int, nonzero bool) (int, error) {
	if !integerPattern.MatchString(text) {
		return 0, fmt.Errorf("invalid number %s", text)
	}
	value, err := strconv.Atoi(text)
	if err != nil || value < min || value > max || nonzero && value == 0 {
		return 0, fmt.Errorf("invalid number %s", text)
	}
	return value, nil
}

type Toolkit struct {
	sequences map[string]string
	output []string
	code map[string]byte
}

func newToolkit() *Toolkit {
	return &Toolkit{sequences: make(map[string]string), code: geneticCode()}
}

func (tool *Toolkit) emit(parts ...any) {
	text := make([]string, len(parts))
	for i, part := range parts {
		text[i] = fmt.Sprint(part)
	}
	tool.output = append(tool.output, strings.Join(text, " "))
}

func (tool *Toolkit) emitList(label string, values []string) {
	if len(values) == 0 {
		tool.emit(label, "none")
		return
	}
	tool.emit(label, strings.Join(values, " "))
}

func numbersText(values []int) []string {
	text := make([]string, len(values))
	for i, value := range values {
		text[i] = strconv.Itoa(value)
	}
	return text
}

func (tool *Toolkit) validate(command string, args []string) error {
	limits, ok := arity[command]
	if !ok {
		return fmt.Errorf("unknown command %s", command)
	}
	if len(args) < limits[0] || len(args) > limits[1] {
		return fmt.Errorf("wrong argument count")
	}
	seen := make(map[string]bool)
	for position, kind := range kinds(command, len(args)) {
		text := args[position]
		switch kind {
		case "position", "frame", "orf", "window", "kmer", "limit", "palindrome",
			"repeat", "repeatCount", "match", "mismatch", "gap", "loop", "overlap", "length":
			min, max := 1, 500
			switch kind {
			case "position":
				max = len(tool.sequences[args[0]])
			case "frame":
				min, max = -3, 3
			case "orf":
				max = 200
			case "kmer":
				max = 12
			case "limit", "overlap":
				max = 100
			case "palindrome":
				min, max = 2, 20
			case "repeat":
				max = 6
			case "repeatCount":
				min, max = 2, 50
			case "match":
				max = 20
			case "mismatch":
				min, max = -20, 0
			case "gap":
				min, max = -20, -1
			case "loop":
				min, max = 0, 10
			}
			if _, err := number(text, min, max, kind == "frame"); err != nil {
				return err
			}
		case "name":
			if _, ok := tool.sequences[text]; !ok {
				return fmt.Errorf("unknown sequence %s", text)
			}
		case "new":
			if !namePattern.MatchString(text) {
				return fmt.Errorf("invalid name %s", text)
			}
		case "sequence":
			for i := 0; i < len(text); i++ {
				if !strings.ContainsRune(bases, rune(text[i])) {
					return fmt.Errorf("invalid base %c at %d", text[i], i+1)
				}
			}
		case "base":
			if len(text) != 1 || !strings.Contains(bases, text) {
				return fmt.Errorf("invalid base %s", text)
			}
		case "motif":
			valid := len(text) >= 1 && len(text) <= 30
			for i := 0; i < len(text); i++ {
				if _, ok := iupac[text[i]]; !ok {
					valid = false
				}
			}
			if !valid {
				return fmt.Errorf("invalid motif %s", text)
			}
		case "enzyme":
			if _, ok := enzymes[text]; !ok {
				return fmt.Errorf("unknown enzyme %s", text)
			}
			if seen[text] {
				return fmt.Errorf("duplicate enzyme %s", text)
			}
			seen[text] = true
		case "mode":
			if text != "GLOBAL" && text != "LOCAL" {
				return fmt.Errorf("invalid mode %s", text)
			}
		case "hex":
			length, _ := strconv.Atoi(args[1])
			if len(text) != 2*((length+3)/4) || !hexPattern.MatchString(text) {
				return fmt.Errorf("invalid hex")
			}
		}
	}
	return nil
}

func (tool *Toolkit) store(name, sequence string) (string, error) {
	if len(sequence) > 500 {
		return "", fmt.Errorf("too long")
	}
	action := "stored"
	if _, ok := tool.sequences[name]; ok {
		action = "replaced"
	}
	tool.sequences[name] = sequence
	return fmt.Sprintf("%s %s %d nt", action, name, len(sequence)), nil
}

func (tool *Toolkit) translation(command, name string, frame int) error {
	triplets := codons(tool.sequences[name], frame)
	var builder strings.Builder
	for _, codon := range triplets {
		builder.WriteByte(tool.code[codon])
	}
	protein := builder.String()
	switch command {
	case "TRANSLATE":
		if protein == "" {
			protein = "none"
		}
		tool.emit(protein)
	case "CODONS":
		counts := make(map[string]int)
		for _, codon := range triplets {
			counts[codon]++
		}
		if len(counts) == 0 {
			tool.emit("none")
		}
		for _, codon := range frequencyOrder(counts) {
			tool.emit(codon, string(tool.code[codon]), counts[codon])
		}
	case "PROTEIN":
		if i := strings.IndexByte(protein, '*'); i >= 0 {
			protein = protein[:i]
		}
		if protein == "" {
			return fmt.Errorf("empty protein")
		}
		counts, mass, charge := make(map[string]int), 18015, 0
		for i := 0; i < len(protein); i++ {
			amino := protein[i]
			counts[string(amino)]++
			mass += aminoMass[amino]
			if amino == 'K' || amino == 'R' {
				charge++
			} else if amino == 'D' || amino == 'E' {
				charge--
			}
		}
		tool.emit(protein)
		chargeText := strconv.Itoa(charge)
		if charge > 0 {
			chargeText = "+" + chargeText
		}
		tool.emit("length", len(protein), "mass", fixed(mass, 3), "charge", chargeText)
		fields := make([]string, 0, len(counts))
		for _, amino := range frequencyOrder(counts) {
			fields = append(fields, fmt.Sprintf("%s=%d", amino, counts[amino]))
		}
		tool.emit(strings.Join(fields, " "))
	}
	return nil
}

type ORF struct {
	left, right, frame int
	protein string
}

func (tool *Toolkit) orfs(sequence string, minimum int) {
	var found []ORF
	for _, frame := range []int{1, 2, 3, -1, -2, -3} {
		triplets := codons(sequence, frame)
		start := -1
		for position, codon := range triplets {
			if start < 0 {
				if codon == "ATG" {
					start = position
				}
			} else if tool.code[codon] == '*' {
				if position-start >= minimum {
					offset := frame
					if offset < 0 {
						offset = -offset
					}
					left := offset - 1 + 3*start
					right := offset - 1 + 3*(position+1)
					if frame < 0 {
						left, right = len(sequence)-right, len(sequence)-left
					}
					var protein strings.Builder
					for _, codon := range triplets[start:position] {
						protein.WriteByte(tool.code[codon])
					}
					found = append(found, ORF{left+1, right, frame, protein.String()})
				}
				start = -1
			}
		}
	}
	sort.Slice(found, func(i, j int) bool {
		a, b := found[i], found[j]
		if a.left != b.left {
			return a.left < b.left
		}
		if a.right != b.right {
			return a.right < b.right
		}
		return a.frame < b.frame
	})
	if len(found) == 0 {
		tool.emit("none")
	}
	for _, entry := range found {
		tool.emit(fmt.Sprintf("%+d", entry.frame), entry.left, entry.right,
			len(entry.protein), entry.protein)
	}
}

func (tool *Toolkit) restriction(sequence string, selected []string) {
	cuts := make(map[int]bool)
	for _, name := range selected {
		enzyme := enzymes[name]
		positions := make([]int, 0)
		for _, position := range occurrences(sequence, enzyme.motif) {
			cut := position + enzyme.offset - 1
			if cut >= 1 && cut < len(sequence) {
				positions = append(positions, cut)
				cuts[cut] = true
			}
		}
		tool.emitList(name, numbersText(positions))
	}
	endpoints := []int{0}
	for cut := range cuts {
		endpoints = append(endpoints, cut)
	}
	sort.Ints(endpoints)
	endpoints = append(endpoints, len(sequence))
	fragments, sizes := make([]string, 0), make([]int, 0)
	for i := 1; i < len(endpoints); i++ {
		left, right := endpoints[i-1]+1, endpoints[i]
		fragments = append(fragments, fmt.Sprintf("%d-%d", left, right))
		sizes = append(sizes, right-left+1)
	}
	sort.Sort(sort.Reverse(sort.IntSlice(sizes)))
	tool.emitList("fragments", fragments)
	tool.emitList("sizes", numbersText(sizes))
}

type Repeat struct {
	position, width, count int
	unit string
}

func (tool *Toolkit) repeats(sequence string, minimum, maximum, count int) error {
	if minimum > maximum {
		return fmt.Errorf("invalid range")
	}
	var results []Repeat
	for width := minimum; width <= maximum; width++ {
		position := 0
		for position+width <= len(sequence) {
			unit := sequence[position : position+width]
			repeated := repeatCount(sequence, position, width)
			if primitive(unit) && repeated >= count {
				results = append(results, Repeat{position, width, repeated, unit})
				position += repeated * width
			} else {
				position++
			}
		}
	}
	sort.Slice(results, func(i, j int) bool {
		a, b := results[i], results[j]
		if a.position != b.position {
			return a.position < b.position
		}
		return a.width < b.width
	})
	if len(results) == 0 {
		tool.emit("none")
	}
	for _, row := range results {
		tool.emit(fmt.Sprintf("%d-%d", row.position+1,
			row.position+row.width*row.count), fmt.Sprintf("%sx%d", row.unit, row.count))
	}
	return nil
}

func (tool *Toolkit) alignment(a, b, mode string, match, mismatch, gap int) {
	m, n := len(a), len(b)
	local := mode == "LOCAL"
	matrix := make([][]int, m+1)
	for i := range matrix {
		matrix[i] = make([]int, n+1)
	}
	if !local {
		for i := 0; i <= m; i++ {
			matrix[i][0] = i * gap
		}
		for j := 0; j <= n; j++ {
			matrix[0][j] = j * gap
		}
	}
	best, endI, endJ := 0, 0, 0
	for i := 1; i <= m; i++ {
		for j := 1; j <= n; j++ {
			score := mismatch
			if a[i-1] == b[j-1] {
				score = match
			}
			diagonal := matrix[i-1][j-1]+score
			value := diagonal
			if matrix[i-1][j]+gap > value {
				value = matrix[i-1][j]+gap
			}
			if matrix[i][j-1]+gap > value {
				value = matrix[i][j-1]+gap
			}
			if local && value < 0 {
				value = 0
			}
			matrix[i][j] = value
			if local && value > best {
				best, endI, endJ = value, i, j
			}
		}
	}
	if !local {
		best, endI, endJ = matrix[m][n], m, n
	}
	if local && best == 0 {
		tool.emit("score", 0)
		return
	}
	i, j := endI, endJ
	var rowA, rowB []byte
	for local && matrix[i][j] != 0 || !local && (i != 0 || j != 0) {
		score := mismatch
		if i > 0 && j > 0 && a[i-1] == b[j-1] {
			score = match
		}
		if i > 0 && j > 0 && matrix[i][j] == matrix[i-1][j-1]+score {
			i--
			j--
			rowA = append(rowA, a[i])
			rowB = append(rowB, b[j])
		} else if i > 0 && matrix[i][j] == matrix[i-1][j]+gap {
			i--
			rowA = append(rowA, a[i])
			rowB = append(rowB, '-')
		} else {
			j--
			rowA = append(rowA, '-')
			rowB = append(rowB, b[j])
		}
	}
	reverseBytes := func(row []byte) {
		for left, right := 0, len(row)-1; left < right; left, right = left+1, right-1 {
			row[left], row[right] = row[right], row[left]
		}
	}
	reverseBytes(rowA)
	reverseBytes(rowB)
	middle := make([]byte, len(rowA))
	identity, gaps := 0, 0
	for position := range rowA {
		if rowA[position] == '-' || rowB[position] == '-' {
			middle[position] = '-'
			gaps++
		} else if rowA[position] == rowB[position] {
			middle[position] = '|'
			identity++
		} else {
			middle[position] = '*'
		}
	}
	tool.emit("score", best, "a", fmt.Sprintf("%d-%d", i+1, endI),
		"b", fmt.Sprintf("%d-%d", j+1, endJ),
		"identity", fmt.Sprintf("%d/%d", identity, len(middle)), "gaps", gaps)
	tool.emit(string(rowA))
	tool.emit(string(middle))
	tool.emit(string(rowB))
}

func (tool *Toolkit) consensus(names []string) error {
	n := len(tool.sequences[names[0]])
	for _, name := range names {
		if len(tool.sequences[name]) != n {
			return fmt.Errorf("length mismatch")
		}
	}
	profiles := [4][]int{}
	symbols := make(map[string]byte)
	for letter, chars := range iupac {
		symbols[chars] = letter
	}
	var consensus, ambiguous strings.Builder
	for position := 0; position < n; position++ {
		counts := [4]int{}
		for _, name := range names {
			counts[strings.IndexByte(bases, tool.sequences[name][position])]++
		}
		largest := counts[0]
		for _, count := range counts {
			if count > largest {
				largest = count
			}
		}
		tied := ""
		for i := 0; i < 4; i++ {
			profiles[i] = append(profiles[i], counts[i])
			if counts[i] == largest {
				tied += string(bases[i])
			}
		}
		consensus.WriteByte(tied[0])
		ambiguous.WriteByte(symbols[tied])
	}
	for i := 0; i < 4; i++ {
		tool.emit(string(bases[i]), strings.Join(numbersText(profiles[i]), " "))
	}
	tool.emit("consensus", consensus.String())
	tool.emit("iupac", ambiguous.String())
	return nil
}

func (tool *Toolkit) primer(sequence string) {
	n, amount, tm := len(sequence), gc(sequence), temperature(sequence)
	clamp := sequence
	if n > 5 {
		clamp = sequence[n-5:]
	}
	clampCount := gc(clamp)
	longestRun, run, repeated := 0, 0, 0
	var previous byte
	for i := 0; i < n; i++ {
		if i > 0 && sequence[i] == previous {
			run++
		} else {
			run = 1
		}
		if run > longestRun {
			longestRun = run
		}
		previous = sequence[i]
	}
	for i := 0; i+1 < n; i++ {
		if sequence[i] != sequence[i+1] {
			count := repeatCount(sequence, i, 2)
			if count > repeated {
				repeated = count
			}
		}
	}
	selfcomp := longestPalindrome(sequence)
	type check struct {
		label, value string
		pass bool
	}
	checks := []check{
		{"length", strconv.Itoa(n), 18 <= n && n <= 25},
		{"gc", pct(amount, n), 40*n <= 100*amount && 100*amount <= 60*n},
		{"tm", fixed(tm, 1), 520 <= tm && tm <= 620},
		{"clamp", strconv.Itoa(clampCount), 1 <= clampCount && clampCount <= 3},
		{"run", strconv.Itoa(longestRun), longestRun <= 4},
		{"repeat", strconv.Itoa(repeated), repeated <= 4},
		{"selfcomp", strconv.Itoa(selfcomp), selfcomp <= 6},
	}
	var failed []string
	for _, item := range checks {
		verdict := "OK"
		if !item.pass {
			verdict = "FAIL"
			failed = append(failed, item.label)
		}
		tool.emit(item.label, item.value, verdict)
	}
	if len(failed) == 0 {
		tool.emit("PASS")
	} else {
		tool.emit("FAIL", strings.Join(failed, " "))
	}
}

func (tool *Toolkit) folding(sequence string, loop int) error {
	n := len(sequence)
	if n > 100 {
		return fmt.Errorf("too long")
	}
	matrix := make([][]int, n)
	for i := range matrix {
		matrix[i] = make([]int, n)
	}
	value := func(i, j int) int {
		if i > j {
			return 0
		}
		return matrix[i][j]
	}
	paired := func(i, j int) bool {
		switch string([]byte{sequence[i], sequence[j]}) {
		case "AT", "TA", "CG", "GC", "GT", "TG":
			return true
		}
		return false
	}
	for width := 2; width <= n; width++ {
		for i := 0; i+width <= n; i++ {
			j := i+width-1
			best := value(i, j-1)
			for k := i; k < j-loop; k++ {
				if paired(k, j) {
					candidate := value(i, k-1)+1+value(k+1, j-1)
					if candidate > best {
						best = candidate
					}
				}
			}
			matrix[i][j] = best
		}
	}
	structure := make([]byte, n)
	for i := range structure {
		structure[i] = '.'
	}
	type interval struct{ i, j int }
	pending := []interval{{0, n - 1}}
	for len(pending) > 0 {
		entry := pending[len(pending)-1]
		pending = pending[:len(pending)-1]
		i, j := entry.i, entry.j
		if i > j || value(i, j) == 0 {
			continue
		}
		if value(i, j) == value(i, j-1) {
			pending = append(pending, interval{i, j - 1})
			continue
		}
		for k := i; k < j-loop; k++ {
			if paired(k, j) && value(i, k-1)+1+value(k+1, j-1) == value(i, j) {
				structure[k] = '('
				structure[j] = ')'
				pending = append(pending, interval{i, k-1}, interval{k+1, j-1})
				break
			}
		}
	}
	tool.emit(string(structure))
	tool.emit("pairs", matrix[0][n-1])
	return nil
}

func (tool *Toolkit) assembly(name string, minimum int, sequences []string) error {
	var unique []string
	seen := make(map[string]bool)
	for _, sequence := range sequences {
		if !seen[sequence] {
			unique = append(unique, sequence)
			seen[sequence] = true
		}
	}
	var fragments []string
	for _, sequence := range unique {
		contained := false
		for _, other := range unique {
			if sequence != other && strings.Contains(other, sequence) {
				contained = true
				break
			}
		}
		if !contained {
			fragments = append(fragments, sequence)
		}
	}
	for len(fragments) >= 2 {
		best, chosenI, chosenJ := 0, -1, -1
		for i, first := range fragments {
			for j, second := range fragments {
				if i == j {
					continue
				}
				overlap := 0
				limit := len(first)
				if len(second) < limit {
					limit = len(second)
				}
				for width := limit-1; width > 0; width-- {
					if first[len(first)-width:] == second[:width] {
						overlap = width
						break
					}
				}
				if chosenI == -1 || overlap > best {
					best, chosenI, chosenJ = overlap, i, j
				}
			}
		}
		if best < minimum {
			break
		}
		merged := fragments[chosenI]+fragments[chosenJ][best:]
		next := make([]string, 0)
		for k, fragment := range fragments {
			if k == chosenI {
				next = append(next, merged)
			} else if k != chosenJ && !strings.Contains(merged, fragment) {
				next = append(next, fragment)
			}
		}
		fragments = next
	}
	longest := fragments[0]
	for _, fragment := range fragments {
		if len(fragment) > len(longest) {
			longest = fragment
		}
	}
	registration, err := tool.store(name, longest)
	if err != nil {
		return err
	}
	tool.emit("contigs", len(fragments))
	for _, fragment := range fragments {
		tool.emit(len(fragment), fragment)
	}
	tool.emit(registration)
	return nil
}

func (tool *Toolkit) command(cmd string, args []string) error {
	switch cmd {
	case "SEQ":
		result, err := tool.store(args[0], args[1])
		if err != nil {
			return err
		}
		tool.emit(result)
		return nil
	case "UNPACK":
		count, _ := strconv.Atoi(args[1])
		var codes []int
		for i := 0; i < len(args[2]); i += 2 {
			value, _ := strconv.ParseUint(args[2][i:i+2], 16, 8)
			byteValue := int(value)
			codes = append(codes, byteValue/64, byteValue/16%4, byteValue/4%4, byteValue%4)
		}
		for _, code := range codes[count:] {
			if code != 0 {
				return fmt.Errorf("invalid padding")
			}
		}
		var sequence strings.Builder
		for _, code := range codes[:count] {
			sequence.WriteByte(bases[code])
		}
		result, err := tool.store(args[0], sequence.String())
		if err != nil {
			return err
		}
		tool.emit(result)
		return nil
	case "JOIN":
		var sequence strings.Builder
		for _, name := range args[1:] {
			sequence.WriteString(tool.sequences[name])
		}
		result, err := tool.store(args[0], sequence.String())
		if err != nil {
			return err
		}
		tool.emit(result)
		return nil
	case "ASSEMBLE":
		minimum, _ := strconv.Atoi(args[1])
		fragments := make([]string, 0, len(args)-2)
		for _, name := range args[2:] {
			fragments = append(fragments, tool.sequences[name])
		}
		return tool.assembly(args[0], minimum, fragments)
	case "LIST":
		names := make([]string, 0, len(tool.sequences))
		for name := range tool.sequences {
			names = append(names, name)
		}
		sort.Strings(names)
		if len(names) == 0 {
			tool.emit("no sequences")
		}
		for _, name := range names {
			tool.emit(name, len(tool.sequences[name]), "nt")
		}
		return nil
	}

	name := args[0]
	sequence := tool.sequences[name]
	n := len(sequence)
	switch cmd {
	case "SLICE":
		first, _ := strconv.Atoi(args[1])
		last, _ := strconv.Atoi(args[2])
		part := ""
		if first <= last {
			part = sequence[first-1:last]
		} else {
			part = revcomp(sequence[last-1:first])
		}
		result, err := tool.store(args[3], part)
		if err != nil {
			return err
		}
		tool.emit(result)
	case "MUTATE":
		position, _ := strconv.Atoi(args[1])
		before := sequence[position-1]
		after := args[2][0]
		if before == after {
			return fmt.Errorf("no change")
		}
		tool.sequences[name] = sequence[:position-1]+args[2]+sequence[position:]
		kind := "transversion"
		if transition(before, after) {
			kind = "transition"
		}
		tool.emit(name, fmt.Sprintf("%c%d%c", before, position, after), kind)
	case "DEL":
		delete(tool.sequences, name)
		tool.emit("deleted", name)
	case "REVCOMP":
		tool.emit(revcomp(sequence))
	case "COMPLEMENT":
		tool.emit(complement(sequence))
	case "REVERSE":
		text := []byte(sequence)
		for i, j := 0, n-1; i < j; i, j = i+1, j-1 {
			text[i], text[j] = text[j], text[i]
		}
		tool.emit(string(text))
	case "TRANSCRIBE":
		tool.emit(strings.ReplaceAll(sequence, "T", "U"))
	case "TRANSLATE", "CODONS", "PROTEIN":
		frame, _ := strconv.Atoi(args[1])
		return tool.translation(cmd, name, frame)
	case "ORFS":
		minimum, _ := strconv.Atoi(args[1])
		tool.orfs(sequence, minimum)
	case "GC":
		fields := make([]string, 0, 5)
		for i := 0; i < len(bases); i++ {
			base := string(bases[i])
			fields = append(fields, fmt.Sprintf("%s=%d", base, strings.Count(sequence, base)))
		}
		fields = append(fields, "GC="+pct(gc(sequence), n)+"%")
		tool.emit(strings.Join(fields, " "))
	case "GCWINDOW":
		width, _ := strconv.Atoi(args[1])
		step, _ := strconv.Atoi(args[2])
		if width > n {
			return fmt.Errorf("window too large")
		}
		for i := 0; i+width <= n; i += step {
			tool.emit(fmt.Sprintf("%d-%d", i+1, i+width), pct(gc(sequence[i:i+width]), width)+"%")
		}
	case "SKEW":
		values := []int{0}
		for i := 0; i < n; i++ {
			next := values[len(values)-1]
			if sequence[i] == 'G' {
				next++
			} else if sequence[i] == 'C' {
				next--
			}
			values = append(values, next)
		}
		minimum, maximum := values[0], values[0]
		for _, value := range values {
			if value < minimum {
				minimum = value
			}
			if value > maximum {
				maximum = value
			}
		}
		for _, row := range []struct{
			label string
			value int
		}{{"min", minimum}, {"max", maximum}} {
			positions := []int{}
			for position, value := range values {
				if value == row.value {
					positions = append(positions, position)
				}
			}
			tool.emit(row.label, row.value, "at", strings.Join(numbersText(positions), " "))
		}
	case "KMERS":
		width, _ := strconv.Atoi(args[1])
		limit, _ := strconv.Atoi(args[2])
		if width > n {
			return fmt.Errorf("k too large")
		}
		counts := make(map[string]int)
		for i := 0; i+width <= n; i++ {
			counts[sequence[i:i+width]]++
		}
		tool.emit(n-width+1, "windows", len(counts), "distinct")
		order := frequencyOrder(counts)
		for i := 0; i < len(order) && i < limit; i++ {
			tool.emit(order[i], counts[order[i]])
		}
	case "FIND":
		for _, item := range []struct{
			label, motif string
		}{{"forward", args[1]}, {"reverse", revcomp(args[1])}} {
			tool.emitList(item.label, numbersText(occurrences(sequence, item.motif)))
		}
	case "RESTRICT":
		tool.restriction(sequence, args[1:])
	case "PALINDROMES":
		minimum, _ := strconv.Atoi(args[1])
		maximum, _ := strconv.Atoi(args[2])
		if minimum > maximum {
			return fmt.Errorf("invalid range")
		}
		found := false
		for position := 0; position < n; position++ {
			for width := minimum; width <= maximum && position+width <= n; width++ {
				part := sequence[position:position+width]
				if part == revcomp(part) {
					tool.emit(position+1, width, part)
					found = true
				}
			}
		}
		if !found {
			tool.emit("none")
		}
	case "REPEATS":
		first, _ := strconv.Atoi(args[1])
		last, _ := strconv.Atoi(args[2])
		count, _ := strconv.Atoi(args[3])
		return tool.repeats(sequence, first, last, count)
	case "HAMMING":
		other := tool.sequences[args[1]]
		if len(other) != n {
			return fmt.Errorf("length mismatch")
		}
		distance, transitions := 0, 0
		for i := 0; i < n; i++ {
			if sequence[i] != other[i] {
				distance++
				if transition(sequence[i], other[i]) {
					transitions++
				}
			}
		}
		tool.emit("distance", distance, "transitions", transitions,
			"transversions", distance-transitions)
	case "ALIGN":
		match, _ := strconv.Atoi(args[3])
		mismatch, _ := strconv.Atoi(args[4])
		gap, _ := strconv.Atoi(args[5])
		tool.alignment(sequence, tool.sequences[args[1]], args[2], match, mismatch, gap)
	case "CONSENSUS":
		return tool.consensus(args)
	case "TM":
		method := "gc"
		if n < 14 {
			method = "wallace"
		}
		tool.emit("Tm", fixed(temperature(sequence), 1), method)
	case "MASS":
		single := strandMass(sequence)
		tool.emit("ss", fixed(single, 3), "ds", fixed(single+strandMass(revcomp(sequence)), 3))
	case "PRIMER":
		tool.primer(sequence)
	case "FOLD":
		loop, _ := strconv.Atoi(args[1])
		return tool.folding(sequence, loop)
	case "PACK":
		codes := make([]int, 0, n+3)
		for i := 0; i < n; i++ {
			codes = append(codes, strings.IndexByte(bases, sequence[i]))
		}
		for len(codes)%4 != 0 {
			codes = append(codes, 0)
		}
		var encoded strings.Builder
		for i := 0; i < len(codes); i += 4 {
			value := 64*codes[i]+16*codes[i+1]+4*codes[i+2]+codes[i+3]
			fmt.Fprintf(&encoded, "%02X", value)
		}
		tool.emit(n, encoded.String())
	}
	return nil
}

func (tool *Toolkit) execute(line string) {
	fields := strings.Fields(line)
	cmd := fields[0]
	args := fields[1:]
	if err := tool.validate(cmd, args); err != nil {
		tool.emit("ERROR", err.Error())
		return
	}
	if err := tool.command(cmd, args); err != nil {
		tool.emit("ERROR", err.Error())
	}
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	count, _ := strconv.Atoi(scanner.Text())
	tool := newToolkit()
	for i := 0; i < count && scanner.Scan(); i++ {
		tool.execute(scanner.Text())
	}
	writer := bufio.NewWriter(os.Stdout)
	defer writer.Flush()
	for _, line := range tool.output {
		fmt.Fprintln(writer, line)
	}
}
