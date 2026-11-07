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

var adjacentKeys = [26]string{
	"qswz", "ghnv", "dfvx", "cefrsx", "drsw", "cdgrtv", "bfhtvy", "bgjnuy",
	"jkou", "hikmnu", "ijlmo", "kop", "jkn", "bhjm", "iklp", "lo", "aw",
	"deft", "adewxz", "fgry", "hijy", "bcfg", "aeqs", "cdsz", "ghtu", "asx",
}

var soundexDigits = func() [26]byte {
	var digits [26]byte
	groups := []string{"bfpv", "cgjkqsxz", "dt", "l", "mn", "r", "aeiouy"}
	for i, group := range groups {
		digit := byte('1' + i)
		if i == 6 {
			digit = '0'
		}
		for j := 0; j < len(group); j++ {
			digits[group[j]-'a'] = digit
		}
	}
	return digits
}()

var wordPattern = regexp.MustCompile(`^[A-Za-z]{1,30}$`)
var numberPattern = regexp.MustCompile(`^[0-9]{1,7}$`)
var textWords = regexp.MustCompile(`[A-Za-z]+`)
var counterNames = []string{"checked", "unknown", "case", "capital", "repeats", "corrected"}
var findingNames = []string{"unknown", "case", "capital", "repeats"}
var commands = map[string]int{
	"CHECK": -1, "CORRECT": -1, "FIX": -1, "PROFILE": -1, "LEARN": -1,
	"SUGGEST": 1, "DIST": 2, "SOUNDEX": 1, "SOUNDS": 1, "SPLIT": 1,
	"PREFIX": 2, "COMPLETE": 2, "LIST": 2, "WORD": 1, "ADD": 2,
	"REMOVE": 1, "IGNORE": 1, "UNIGNORE": 1, "RULE": 2, "UNRULE": 1,
	"RULES": 0, "KEYBOARD": 1, "SET": 2, "UNDO": 0, "REPORT": 0,
	"HISTORY": 0, "STATS": 0,
}

type commandError string

func (e commandError) Error() string { return string(e) }

func wordArgument(text string) (string, error) {
	if !wordPattern.MatchString(text) {
		return "", commandError("BAD WORD " + text)
	}
	return strings.ToLower(text), nil
}

func numberArgument(text string, minimum, maximum int) (int, error) {
	if !numberPattern.MatchString(text) {
		return 0, commandError("BAD NUMBER " + text)
	}
	value, _ := strconv.Atoi(text)
	if value < minimum || value > maximum {
		return 0, commandError("BAD NUMBER " + text)
	}
	return value, nil
}

func decimalText(numerator, denominator int, digits int) string {
	scale := 10
	if digits == 2 {
		scale = 100
	}
	rounded := (2*numerator*scale + denominator) / (2 * denominator)
	return fmt.Sprintf("%d.%0*d", rounded/scale, digits, rounded%scale)
}

func capitalize(word string) string { return strings.ToUpper(word[:1]) + word[1:] }
func applyCase(original, word string) string {
	if len(original) >= 2 && original == strings.ToUpper(original) {
		return strings.ToUpper(word)
	}
	if original[0] >= 'A' && original[0] <= 'Z' {
		return capitalize(word)
	}
	return word
}

type token struct {
	number, start, end                 int
	original, word, gap                string
	sentenceStart, repeated, mixedCase bool
}

func tokenizeText(text string) []token {
	matches := textWords.FindAllStringIndex(text, -1)
	tokens := make([]token, 0, len(matches))
	position := 0
	for _, match := range matches {
		start, end := match[0], match[1]
		original := text[start:end]
		word := strings.ToLower(original)
		gap := text[position:start]
		sentenceStart := len(tokens) == 0 || strings.ContainsAny(gap, ".!?")
		repeated := len(tokens) > 0 && tokens[len(tokens)-1].word == word && strings.Trim(gap, " ") == ""
		mixed := original != strings.ToUpper(original) && strings.IndexAny(original[1:], "ABCDEFGHIJKLMNOPQRSTUVWXYZ") >= 0
		tokens = append(tokens, token{len(tokens) + 1, start, end, original, word, gap, sentenceStart, repeated, mixed})
		position = end
	}
	return tokens
}

func substitutionCost(first, second byte, keyboard bool) int {
	if first == second {
		return 0
	}
	if !keyboard {
		return 1
	}
	if strings.IndexByte(adjacentKeys[first-'a'], second) >= 0 {
		return 1
	}
	return 2
}

func swapAt(first, second string, i, j int) bool {
	return i >= 2 && j >= 2 && first[i-1] == second[j-2] && first[i-2] == second[j-1]
}

func minimum(values ...int) int {
	smallest := values[0]
	for _, value := range values[1:] {
		if value < smallest {
			smallest = value
		}
	}
	return smallest
}

func distanceTable(first, second string, keyboard bool) [][]int {
	rows, columns := len(first), len(second)
	gap := 1
	if keyboard {
		gap = 2
	}
	table := make([][]int, rows+1)
	for i := range table {
		table[i] = make([]int, columns+1)
		table[i][0] = i * gap
	}
	for j := 0; j <= columns; j++ {
		table[0][j] = j * gap
	}
	for i := 1; i <= rows; i++ {
		for j := 1; j <= columns; j++ {
			best := minimum(table[i-1][j]+gap, table[i][j-1]+gap,
				table[i-1][j-1]+substitutionCost(first[i-1], second[j-1], keyboard))
			if swapAt(first, second, i, j) {
				best = minimum(best, table[i-2][j-2]+1)
			}
			table[i][j] = best
		}
	}
	return table
}

func editDistance(first, second string, keyboard bool) int {
	return distanceTable(first, second, keyboard)[len(first)][len(second)]
}

func prefixDistance(first, second string, keyboard bool) int {
	return minimum(distanceTable(first, second, keyboard)[len(first)]...)
}

func editOperations(first, second string, keyboard bool) (int, []string) {
	table := distanceTable(first, second, keyboard)
	gap := 1
	if keyboard {
		gap = 2
	}
	operations := []string{}
	i, j := len(first), len(second)
	for i > 0 || j > 0 {
		if i >= 1 && j >= 1 && table[i][j] == table[i-1][j-1]+
			substitutionCost(first[i-1], second[j-1], keyboard) {
			if first[i-1] != second[j-1] {
				operations = append(operations, fmt.Sprintf("sub:%c>%c", first[i-1], second[j-1]))
			}
			i--
			j--
		} else if swapAt(first, second, i, j) && table[i][j] == table[i-2][j-2]+1 {
			operations = append(operations, "swap:"+first[i-2:i])
			i -= 2
			j -= 2
		} else if i >= 1 && table[i][j] == table[i-1][j]+gap {
			operations = append(operations, "del:"+first[i-1:i])
			i--
		} else {
			operations = append(operations, "ins:"+second[j-1:j])
			j--
		}
	}
	for a, b := 0, len(operations)-1; a < b; a, b = a+1, b-1 {
		operations[a], operations[b] = operations[b], operations[a]
	}
	return table[len(first)][len(second)], operations
}

func soundex(word string) string {
	result := strings.ToUpper(word[:1])
	previous := soundexDigits[word[0]-'a']
	if word[0] == 'h' || word[0] == 'w' {
		previous = '0'
	}
	for i := 1; i < len(word); i++ {
		ch := word[i]
		if ch == 'h' || ch == 'w' {
			continue
		}
		digit := soundexDigits[ch-'a']
		if digit != '0' && digit != previous {
			result += string(digit)
		}
		previous = digit
	}
	return (result + "000")[:4]
}

type segmentation struct {
	ways  int64
	words []string
}

func segment(word string, dictionary map[string]int) segmentation {
	length := len(word)
	ways := make([]int64, length+1)
	best := make([][]string, length+1)
	ways[length] = 1
	best[length] = []string{}
	for start := length - 1; start >= 0; start-- {
		for end := start + 1; end <= length; end++ {
			piece := word[start:end]
			if dictionary[piece] == 0 || ways[end] == 0 {
				continue
			}
			ways[start] += ways[end]
			candidate := append([]string{piece}, best[end]...)
			if best[start] == nil || len(candidate) < len(best[start]) ||
				(len(candidate) == len(best[start]) && lessWordSequence(candidate, best[start])) {
				best[start] = candidate
			}
		}
	}
	return segmentation{ways[0], best[0]}
}

func lessWordSequence(a, b []string) bool {
	for i := 0; i < len(a) && i < len(b); i++ {
		if a[i] != b[i] {
			return a[i] < b[i]
		}
	}
	return len(a) < len(b)
}

type candidate struct {
	word                string
	distance, frequency int
}
type snapshot struct {
	name       string
	dictionary map[string]int
	ignored    map[string]bool
	rules      map[string]string
}
type spellChecker struct {
	dictionary                          map[string]int
	ignored                             map[string]bool
	rules                               map[string]string
	keyboard                            bool
	baseLimit, suggestionCount          int
	undoHistory                         []snapshot
	unknownLog, correctionLog, counters map[string]int
	output                              []string
}

func newSpellChecker(dictionary map[string]int) *spellChecker {
	checker := &spellChecker{dictionary: dictionary, ignored: map[string]bool{}, rules: map[string]string{},
		baseLimit: 2, suggestionCount: 5, unknownLog: map[string]int{},
		correctionLog: map[string]int{}, counters: map[string]int{}}
	for _, name := range counterNames {
		checker.counters[name] = 0
	}
	return checker
}
func (s *spellChecker) emit(parts ...string) { s.output = append(s.output, strings.Join(parts, " ")) }
func (s *spellChecker) limit() int {
	if s.keyboard {
		return 2 * s.baseLimit
	}
	return s.baseLimit
}
func (s *spellChecker) isKnown(word string) bool { return s.dictionary[word] > 0 || s.ignored[word] }
func (s *spellChecker) frequencyOrder() []string {
	words := make([]string, 0, len(s.dictionary))
	for word := range s.dictionary {
		words = append(words, word)
	}
	sort.Slice(words, func(i, j int) bool {
		if s.dictionary[words[i]] != s.dictionary[words[j]] {
			return s.dictionary[words[i]] > s.dictionary[words[j]]
		}
		return words[i] < words[j]
	})
	return words
}
func (s *spellChecker) requireEntry(word string) (int, error) {
	if f := s.dictionary[word]; f > 0 {
		return f, nil
	}
	return 0, commandError("NOT FOUND " + word)
}
func (s *spellChecker) candidates(word string) []candidate {
	found := []candidate{}
	maxDistance, gap := s.limit(), 1
	if s.keyboard {
		gap = 2
	}
	for other, freq := range s.dictionary {
		if other == word || (len(other)-len(word))*gap > maxDistance || (len(word)-len(other))*gap > maxDistance {
			continue
		}
		distance := editDistance(word, other, s.keyboard)
		if distance <= maxDistance {
			found = append(found, candidate{other, distance, freq})
		}
	}
	sort.Slice(found, func(i, j int) bool {
		if found[i].distance != found[j].distance {
			return found[i].distance < found[j].distance
		}
		if found[i].frequency != found[j].frequency {
			return found[i].frequency > found[j].frequency
		}
		return found[i].word < found[j].word
	})
	return found
}
func (s *spellChecker) correction(word string) string {
	if s.isKnown(word) {
		return ""
	}
	if target, ok := s.rules[word]; ok {
		return target
	}
	found := s.candidates(word)
	if len(found) > 0 {
		return found[0].word
	}
	return ""
}
func cloneMap[V any](source map[string]V) map[string]V {
	out := make(map[string]V, len(source))
	for k, v := range source {
		out[k] = v
	}
	return out
}
func (s *spellChecker) recordUndo(name string) {
	s.undoHistory = append(s.undoHistory, snapshot{name, cloneMap(s.dictionary), cloneMap(s.ignored), cloneMap(s.rules)})
}
func (s *spellChecker) logCorrection(word, target string) {
	s.correctionLog[word+">"+target]++
	s.counters["corrected"]++
}
func (s *spellChecker) unknownFinding(t token) string {
	prefix := fmt.Sprintf("UNKNOWN %d %s", t.number, t.original)
	if target, ok := s.rules[t.word]; ok {
		return prefix + " RULE " + target
	}
	found := s.candidates(t.word)
	if len(found) == 0 {
		return prefix + " NONE"
	}
	words := []string{prefix, "SUGGEST"}
	for i := 0; i < len(found) && i < s.suggestionCount; i++ {
		words = append(words, found[i].word)
	}
	return strings.Join(words, " ")
}
func (s *spellChecker) checkText(text string) {
	tokens := tokenizeText(text)
	counts := map[string]int{}
	findings := []string{}
	for _, t := range tokens {
		if !s.isKnown(t.word) {
			findings = append(findings, s.unknownFinding(t))
			s.unknownLog[t.word]++
			counts["unknown"]++
		}
		if t.mixedCase {
			findings = append(findings, fmt.Sprintf("CASE %d %s", t.number, t.original))
			counts["case"]++
		}
		if t.sentenceStart && t.original[0] >= 'a' && t.original[0] <= 'z' {
			findings = append(findings, fmt.Sprintf("CAPITAL %d %s", t.number, t.original))
			counts["capital"]++
		}
		if t.repeated {
			findings = append(findings, fmt.Sprintf("REPEAT %d %s", t.number, t.original))
			counts["repeats"]++
		}
	}
	s.counters["checked"] += len(tokens)
	header := fmt.Sprintf("CHECK words=%d", len(tokens))
	for _, kind := range findingNames {
		header += fmt.Sprintf(" %s=%d", kind, counts[kind])
		s.counters[kind] += counts[kind]
	}
	s.emit(header)
	s.output = append(s.output, findings...)
}
func (s *spellChecker) correctText(text string) {
	var b strings.Builder
	position, changed := 0, 0
	for _, t := range tokenizeText(text) {
		b.WriteString(t.gap)
		target := s.correction(t.word)
		if target == "" {
			b.WriteString(t.original)
		} else {
			b.WriteString(applyCase(t.original, target))
			s.logCorrection(t.word, target)
			changed++
		}
		position = t.end
	}
	b.WriteString(text[position:])
	s.emit(fmt.Sprintf("CORRECT changed=%d: %s", changed, b.String()))
}
func (s *spellChecker) fixText(text string) {
	var b strings.Builder
	position, removed, replaced, recased := 0, 0, 0, 0
	for _, t := range tokenizeText(text) {
		position = t.end
		if t.repeated {
			removed++
			continue
		}
		target := s.correction(t.word)
		revised := t.word
		if target != "" {
			revised = target
		}
		revised = applyCase(t.original, revised)
		if t.sentenceStart && revised[0] >= 'a' && revised[0] <= 'z' {
			revised = capitalize(revised)
		}
		if target != "" {
			s.logCorrection(t.word, target)
			replaced++
		} else if revised != t.original {
			recased++
		}
		b.WriteString(t.gap)
		b.WriteString(revised)
	}
	b.WriteString(text[position:])
	s.emit(fmt.Sprintf("FIX removed=%d replaced=%d recased=%d: %s", removed, replaced, recased, b.String()))
}
func (s *spellChecker) profile(text string) {
	tokens := tokenizeText(text)
	distinct := map[string]bool{}
	unknown, sentences, characters := 0, 0, 0
	longest := "-"
	for _, t := range tokens {
		distinct[t.word] = true
		if !s.isKnown(t.word) {
			unknown++
		}
		if t.sentenceStart {
			sentences++
		}
		characters += len(t.original)
		if longest == "-" || len(t.original) > len(longest) {
			longest = t.word
		}
	}
	rate, average := "0.0", "0.00"
	if len(tokens) > 0 {
		rate = decimalText(100*unknown, len(tokens), 1)
		average = decimalText(characters, len(tokens), 2)
	}
	s.emit(fmt.Sprintf("PROFILE words=%d distinct=%d unknown=%d rate=%s avglen=%s longest=%s sentences=%d",
		len(tokens), len(distinct), unknown, rate, average, longest, sentences))
}
func (s *spellChecker) learn(text string) {
	s.recordUndo("LEARN")
	updated, added, skipped := 0, 0, 0
	for _, t := range tokenizeText(text) {
		if len(t.word) > 30 {
			skipped++
		} else if s.dictionary[t.word] > 0 {
			s.dictionary[t.word]++
			updated++
		} else {
			s.dictionary[t.word] = 1
			delete(s.ignored, t.word)
			added++
		}
	}
	s.emit(fmt.Sprintf("LEARN updated=%d added=%d skipped=%d", updated, added, skipped))
}
func (s *spellChecker) suggest(args []string) error {
	word, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	if s.isKnown(word) {
		s.emit("SUGGEST", word, "KNOWN")
		return nil
	}
	if target, ok := s.rules[word]; ok {
		s.emit("SUGGEST", word, "RULE", target)
		return nil
	}
	found := s.candidates(word)
	parts := []string{"SUGGEST", word, fmt.Sprintf("found=%d", len(found))}
	for i := 0; i < len(found) && i < s.suggestionCount; i++ {
		parts = append(parts, fmt.Sprintf("%s:%d", found[i].word, found[i].distance))
	}
	s.emit(parts...)
	return nil
}
func (s *spellChecker) dist(args []string) error {
	first, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	second, err := wordArgument(args[1])
	if err != nil {
		return err
	}
	d, operations := editOperations(first, second, s.keyboard)
	s.emit(append([]string{"DIST", first, second, strconv.Itoa(d)}, operations...)...)
	return nil
}
func (s *spellChecker) sounds(args []string) error {
	word, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	code := soundex(word)
	found := []string{}
	for _, other := range s.frequencyOrder() {
		if other != word && soundex(other) == code {
			found = append(found, other)
		}
	}
	parts := []string{"SOUNDS", word, code, fmt.Sprintf("count=%d", len(found))}
	for i := 0; i < len(found) && i < 10; i++ {
		parts = append(parts, found[i])
	}
	s.emit(parts...)
	return nil
}
func (s *spellChecker) split(args []string) error {
	word, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	result := segment(word, s.dictionary)
	parts := []string{"SPLIT", word, fmt.Sprintf("ways=%d", result.ways), "->"}
	if result.ways == 0 {
		parts = append(parts, "NONE")
	} else {
		parts = append(parts, result.words...)
	}
	s.emit(parts...)
	return nil
}
func (s *spellChecker) prefix(args []string) error {
	word, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	count, err := numberArgument(args[1], 1, 20)
	if err != nil {
		return err
	}
	found := []string{}
	for _, other := range s.frequencyOrder() {
		if strings.HasPrefix(other, word) {
			found = append(found, other)
		}
	}
	parts := []string{"PREFIX", word, fmt.Sprintf("count=%d", len(found))}
	for i := 0; i < len(found) && i < count; i++ {
		parts = append(parts, fmt.Sprintf("%s:%d", found[i], s.dictionary[found[i]]))
	}
	s.emit(parts...)
	return nil
}
func (s *spellChecker) complete(args []string) error {
	word, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	count, err := numberArgument(args[1], 1, 20)
	if err != nil {
		return err
	}
	threshold := s.limit() / 2
	found := []candidate{}
	for other, freq := range s.dictionary {
		distance := prefixDistance(word, other, s.keyboard)
		if distance <= threshold {
			found = append(found, candidate{other, distance, freq})
		}
	}
	sort.Slice(found, func(i, j int) bool {
		if found[i].distance != found[j].distance {
			return found[i].distance < found[j].distance
		}
		if found[i].frequency != found[j].frequency {
			return found[i].frequency > found[j].frequency
		}
		return found[i].word < found[j].word
	})
	parts := []string{"COMPLETE", word, fmt.Sprintf("count=%d", len(found))}
	for i := 0; i < len(found) && i < count; i++ {
		parts = append(parts, fmt.Sprintf("%s:%d", found[i].word, found[i].distance))
	}
	s.emit(parts...)
	return nil
}
func (s *spellChecker) listWords(args []string) error {
	word, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	count, err := numberArgument(args[1], 1, 20)
	if err != nil {
		return err
	}
	found := []string{}
	for other := range s.dictionary {
		if other >= word {
			found = append(found, other)
		}
	}
	sort.Strings(found)
	parts := []string{"LIST", word, fmt.Sprintf("count=%d", len(found))}
	for i := 0; i < len(found) && i < count; i++ {
		parts = append(parts, fmt.Sprintf("%s:%d", found[i], s.dictionary[found[i]]))
	}
	s.emit(parts...)
	return nil
}
func (s *spellChecker) wordInfo(args []string) error {
	word, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	freq, err := s.requireEntry(word)
	if err != nil {
		return err
	}
	rank := 0
	for i, other := range s.frequencyOrder() {
		if other == word {
			rank = i + 1
			break
		}
	}
	s.emit(fmt.Sprintf("WORD %s freq=%d rank=%d soundex=%s neighbors=%d", word, freq, rank, soundex(word), len(s.candidates(word))))
	return nil
}

func (s *spellChecker) add(args []string) error {
	word, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	frequency, err := numberArgument(args[1], 1, 1000000)
	if err != nil {
		return err
	}
	if s.dictionary[word] > 0 {
		return commandError("DUPLICATE " + word)
	}
	s.recordUndo("ADD")
	s.dictionary[word] = frequency
	delete(s.ignored, word)
	s.emit("ADD", word, strconv.Itoa(frequency))
	return nil
}
func (s *spellChecker) remove(args []string) error {
	word, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	freq, err := s.requireEntry(word)
	if err != nil {
		return err
	}
	s.recordUndo("REMOVE")
	delete(s.dictionary, word)
	s.emit("REMOVE", word, strconv.Itoa(freq))
	return nil
}
func (s *spellChecker) ignore(args []string) error {
	word, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	if s.dictionary[word] > 0 {
		return commandError("IN DICTIONARY " + word)
	}
	if s.ignored[word] {
		return commandError("ALREADY IGNORED " + word)
	}
	s.recordUndo("IGNORE")
	s.ignored[word] = true
	s.emit("IGNORE", word)
	return nil
}
func (s *spellChecker) unignore(args []string) error {
	word, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	if !s.ignored[word] {
		return commandError("NOT IGNORED " + word)
	}
	s.recordUndo("UNIGNORE")
	delete(s.ignored, word)
	s.emit("UNIGNORE", word)
	return nil
}
func (s *spellChecker) rule(args []string) error {
	source, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	target, err := wordArgument(args[1])
	if err != nil {
		return err
	}
	if s.dictionary[source] > 0 {
		return commandError("IN DICTIONARY " + source)
	}
	if s.dictionary[target] == 0 {
		return commandError("NOT FOUND " + target)
	}
	s.recordUndo("RULE")
	previous, exists := s.rules[source]
	s.rules[source] = target
	if exists {
		s.emit("RULE", source, target, "REPLACED", previous)
	} else {
		s.emit("RULE", source, target)
	}
	return nil
}
func (s *spellChecker) unrule(args []string) error {
	word, err := wordArgument(args[0])
	if err != nil {
		return err
	}
	previous, exists := s.rules[word]
	if !exists {
		return commandError("NO RULE " + word)
	}
	s.recordUndo("UNRULE")
	delete(s.rules, word)
	s.emit("UNRULE", word, previous)
	return nil
}
func (s *spellChecker) showRules() {
	keys := make([]string, 0, len(s.rules))
	for key := range s.rules {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	parts := []string{"RULES", fmt.Sprintf("count=%d", len(keys))}
	for _, key := range keys {
		parts = append(parts, key+">"+s.rules[key])
	}
	s.emit(parts...)
}
func (s *spellChecker) keyboardMode(args []string) error {
	if args[0] != "ON" && args[0] != "OFF" {
		return commandError("BAD MODE " + args[0])
	}
	s.keyboard = args[0] == "ON"
	s.emit("KEYBOARD", args[0])
	return nil
}
func (s *spellChecker) setOption(args []string) error {
	option := args[0]
	maximum := 0
	switch option {
	case "LIMIT":
		maximum = 3
	case "SUGGESTIONS":
		maximum = 10
	default:
		return commandError("BAD OPTION " + option)
	}
	value, err := numberArgument(args[1], 1, maximum)
	if err != nil {
		return err
	}
	if option == "LIMIT" {
		s.baseLimit = value
	} else {
		s.suggestionCount = value
	}
	s.emit("SET", option, strconv.Itoa(value))
	return nil
}
func (s *spellChecker) undo() error {
	count := len(s.undoHistory)
	if count == 0 {
		return commandError("NOTHING TO UNDO")
	}
	record := s.undoHistory[count-1]
	s.undoHistory = s.undoHistory[:count-1]
	s.dictionary = record.dictionary
	s.ignored = record.ignored
	s.rules = record.rules
	s.emit("UNDO", record.name)
	return nil
}
func (s *spellChecker) report() {
	words := make([]string, 0, len(s.unknownLog))
	for word := range s.unknownLog {
		words = append(words, word)
	}
	sort.Slice(words, func(i, j int) bool {
		if s.unknownLog[words[i]] != s.unknownLog[words[j]] {
			return s.unknownLog[words[i]] > s.unknownLog[words[j]]
		}
		return words[i] < words[j]
	})
	parts := []string{"REPORT", fmt.Sprintf("distinct=%d", len(words))}
	for i := 0; i < len(words) && i < 10; i++ {
		parts = append(parts, fmt.Sprintf("%s:%d", words[i], s.unknownLog[words[i]]))
	}
	s.emit(parts...)
}
func (s *spellChecker) history() {
	words := make([]string, 0, len(s.correctionLog))
	for word := range s.correctionLog {
		words = append(words, word)
	}
	sort.Slice(words, func(i, j int) bool {
		if s.correctionLog[words[i]] != s.correctionLog[words[j]] {
			return s.correctionLog[words[i]] > s.correctionLog[words[j]]
		}
		return words[i] < words[j]
	})
	parts := []string{"HISTORY", fmt.Sprintf("distinct=%d", len(words))}
	for i := 0; i < len(words) && i < 10; i++ {
		parts = append(parts, fmt.Sprintf("%s:%d", words[i], s.correctionLog[words[i]]))
	}
	s.emit(parts...)
}
func (s *spellChecker) stats() {
	words := s.frequencyOrder()
	top := words[0]
	total, characters := 0, 0
	for _, word := range words {
		total += s.dictionary[word]
		characters += len(word)
	}
	mode := "OFF"
	if s.keyboard {
		mode = "ON"
	}
	s.emit(fmt.Sprintf("STATS words=%d total=%d avglen=%s top=%s:%d ignored=%d rules=%d keyboard=%s limit=%d suggestions=%d undo=%d",
		len(words), total, decimalText(characters, len(words), 2), top, s.dictionary[top], len(s.ignored), len(s.rules), mode, s.limit(), s.suggestionCount, len(s.undoHistory)))
	parts := []string{"SESSION"}
	for _, name := range counterNames {
		parts = append(parts, fmt.Sprintf("%s=%d", name, s.counters[name]))
	}
	s.emit(parts...)
}
func (s *spellChecker) execute(line string) {
	name, rest, hasSpace := strings.Cut(line, " ")
	arity, ok := commands[name]
	if !ok {
		s.emit("ERROR", "UNKNOWN COMMAND", name)
		return
	}
	if arity == -1 {
		if !hasSpace {
			s.emit("ERROR", "BAD ARGUMENTS", name)
			return
		}
		switch name {
		case "CHECK":
			s.checkText(rest)
		case "CORRECT":
			s.correctText(rest)
		case "FIX":
			s.fixText(rest)
		case "PROFILE":
			s.profile(rest)
		case "LEARN":
			s.learn(rest)
		}
		return
	}
	args := []string{}
	if hasSpace {
		args = strings.Split(rest, " ")
	}
	if len(args) != arity {
		s.emit("ERROR", "BAD ARGUMENTS", name)
		return
	}
	var err error
	switch name {
	case "SUGGEST":
		err = s.suggest(args)
	case "DIST":
		err = s.dist(args)
	case "SOUNDEX":
		var word string
		word, err = wordArgument(args[0])
		if err == nil {
			s.emit("SOUNDEX", word, soundex(word))
		}
	case "SOUNDS":
		err = s.sounds(args)
	case "SPLIT":
		err = s.split(args)
	case "PREFIX":
		err = s.prefix(args)
	case "COMPLETE":
		err = s.complete(args)
	case "LIST":
		err = s.listWords(args)
	case "WORD":
		err = s.wordInfo(args)
	case "ADD":
		err = s.add(args)
	case "REMOVE":
		err = s.remove(args)
	case "IGNORE":
		err = s.ignore(args)
	case "UNIGNORE":
		err = s.unignore(args)
	case "RULE":
		err = s.rule(args)
	case "UNRULE":
		err = s.unrule(args)
	case "RULES":
		s.showRules()
	case "KEYBOARD":
		err = s.keyboardMode(args)
	case "SET":
		err = s.setOption(args)
	case "UNDO":
		err = s.undo()
	case "REPORT":
		s.report()
	case "HISTORY":
		s.history()
	case "STATS":
		s.stats()
	}
	if err != nil {
		s.emit("ERROR", err.Error())
	}
}

func main() {
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 4096), 1<<20)
	in.Scan()
	number, _ := strconv.Atoi(in.Text())
	dictionary := make(map[string]int, number)
	for i := 0; i < number; i++ {
		in.Scan()
		fields := strings.Fields(in.Text())
		frequency, _ := strconv.Atoi(fields[1])
		dictionary[fields[0]] = frequency
	}
	checker := newSpellChecker(dictionary)
	in.Scan()
	count, _ := strconv.Atoi(in.Text())
	for i := 0; i < count; i++ {
		in.Scan()
		checker.execute(in.Text())
	}
	for _, line := range checker.output {
		fmt.Println(line)
	}
}
