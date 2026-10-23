package main

import (
	"bufio"
	"cmp"
	"errors"
	"fmt"
	"maps"
	"os"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

const (
	vowels            = "aeiou"
	kwicWidth         = 30
	maxCount          = 100
	maxDocumentNumber = 999
	maxLineNumber     = 999
)

var (
	tokenPattern      = regexp.MustCompile(`[A-Za-z]+`)
	wordPattern       = regexp.MustCompile(`^[A-Za-z]{1,30}$`)
	numberPattern     = regexp.MustCompile(`^[0-9]{1,7}$`)
	prefixTermPattern = regexp.MustCompile(`^[A-Za-z]{1,30}\*$`)
	lexemePattern     = regexp.MustCompile(`[()]|[^ ()]+`)
	stepNames         = []string{"1a", "1b", "1c", "2", "3", "4", "5a", "5b"}
	step4Suffixes     = []string{
		"al", "ance", "ence", "er", "ic", "able", "ible", "ant", "ement", "ment",
		"ent", "ion", "ou", "ism", "ate", "iti", "ous", "ive", "ize",
	}
	errSyntax = errors.New("SYNTAX")
)

func letterPattern(word string) string {
	kinds := make([]byte, len(word))
	for index := range len(word) {
		letter := word[index]
		vowel := strings.IndexByte(vowels, letter) >= 0 ||
			(letter == 'y' && index > 0 && kinds[index-1] == 'C')
		if vowel {
			kinds[index] = 'V'
		} else {
			kinds[index] = 'C'
		}
	}
	return string(kinds)
}

func measure(word string) int {
	return strings.Count(letterPattern(word), "VC")
}

func hasVowel(word string) bool {
	return strings.Contains(letterPattern(word), "V")
}

func endsDouble(word string) bool {
	return strings.HasSuffix(letterPattern(word), "CC") && word[len(word)-1] == word[len(word)-2]
}

func endsCvc(word string) bool {
	return strings.HasSuffix(letterPattern(word), "CVC") &&
		strings.IndexByte("wxy", word[len(word)-1]) < 0
}

func always(string) bool {
	return true
}

func measureAboveZero(remainder string) bool {
	return measure(remainder) > 0
}

func measureAboveOne(remainder string) bool {
	return measure(remainder) > 1
}

func ionCondition(remainder string) bool {
	return measure(remainder) > 1 &&
		(strings.HasSuffix(remainder, "s") || strings.HasSuffix(remainder, "t"))
}

func finalECondition(remainder string) bool {
	value := measure(remainder)
	return value > 1 || (value == 1 && !endsCvc(remainder))
}

type rule struct {
	suffix      string
	replacement string
	condition   func(string) bool
}

func rulesWith(condition func(string) bool, replacements [][2]string) []rule {
	rules := make([]rule, 0, len(replacements))
	for _, pair := range replacements {
		rules = append(rules, rule{pair[0], pair[1], condition})
	}
	return rules
}

func step4Rules() []rule {
	rules := make([]rule, 0, len(step4Suffixes))
	for _, suffix := range step4Suffixes {
		condition := measureAboveOne
		if suffix == "ion" {
			condition = ionCondition
		}
		rules = append(rules, rule{suffix, "", condition})
	}
	return rules
}

var ruleTables = map[string][]rule{
	"1a": rulesWith(always, [][2]string{{"sses", "ss"}, {"ies", "i"}, {"ss", "ss"}, {"s", ""}}),
	"1b": {{"eed", "ee", measureAboveZero}, {"ed", "", hasVowel}, {"ing", "", hasVowel}},
	"1c": {{"y", "i", hasVowel}},
	"2": rulesWith(measureAboveZero, [][2]string{
		{"ational", "ate"}, {"tional", "tion"}, {"enci", "ence"}, {"anci", "ance"},
		{"izer", "ize"}, {"abli", "able"}, {"alli", "al"}, {"entli", "ent"},
		{"eli", "e"}, {"ousli", "ous"}, {"ization", "ize"}, {"ation", "ate"},
		{"ator", "ate"}, {"alism", "al"}, {"iveness", "ive"}, {"fulness", "ful"},
		{"ousness", "ous"}, {"aliti", "al"}, {"iviti", "ive"}, {"biliti", "ble"},
	}),
	"3": rulesWith(measureAboveZero, [][2]string{
		{"icate", "ic"}, {"ative", ""}, {"alize", "al"}, {"iciti", "ic"},
		{"ical", "ic"}, {"ful", ""}, {"ness", ""},
	}),
	"4":  step4Rules(),
	"5a": {{"e", "", finalECondition}},
}

// applyRules applies the rule with the longest matching suffix and returns the
// resulting word and the applied suffix ("" when no rule changed the word).
func applyRules(word string, rules []rule) (string, string) {
	var selected *rule
	for index := range rules {
		candidate := &rules[index]
		longer := selected == nil || len(candidate.suffix) > len(selected.suffix)
		if strings.HasSuffix(word, candidate.suffix) && longer {
			selected = candidate
		}
	}
	if selected == nil {
		return word, ""
	}
	remainder := strings.TrimSuffix(word, selected.suffix)
	if !selected.condition(remainder) {
		return word, ""
	}
	return remainder + selected.replacement, selected.suffix
}

func tidyStep1b(word string) string {
	if strings.HasSuffix(word, "at") || strings.HasSuffix(word, "bl") ||
		strings.HasSuffix(word, "iz") {
		return word + "e"
	}
	if endsDouble(word) && strings.IndexByte("lsz", word[len(word)-1]) < 0 {
		return word[:len(word)-1]
	}
	if measure(word) == 1 && endsCvc(word) {
		return word + "e"
	}
	return word
}

func applyStep(name, word string) string {
	if name == "5b" {
		if measure(word) > 1 && endsDouble(word) && strings.HasSuffix(word, "l") {
			return word[:len(word)-1]
		}
		return word
	}
	result, suffix := applyRules(word, ruleTables[name])
	if name == "1b" && (suffix == "ed" || suffix == "ing") {
		return tidyStep1b(result)
	}
	return result
}

type stepChange struct {
	step string
	word string
}

func stemmingSteps(word string) (string, []stepChange) {
	var changes []stepChange
	if len(word) > 2 {
		for _, name := range stepNames {
			result := applyStep(name, word)
			if result != word {
				changes = append(changes, stepChange{name, result})
			}
			word = result
		}
	}
	return word, changes
}

func porterStem(word string) string {
	stem, _ := stemmingSteps(word)
	return stem
}

func yesNo(flag bool) string {
	if flag {
		return "YES"
	}
	return "NO"
}

func wordArgument(text string) (string, error) {
	if !wordPattern.MatchString(text) {
		return "", errors.New("BAD WORD " + text)
	}
	return strings.ToLower(text), nil
}

func numberArgument(text string, minimum, maximum int) (int, error) {
	if !numberPattern.MatchString(text) {
		return 0, errors.New("BAD NUMBER " + text)
	}
	value, _ := strconv.Atoi(text)
	if value < minimum || value > maximum {
		return 0, errors.New("BAD NUMBER " + text)
	}
	return value, nil
}

func splitArguments(name, rest string) []string {
	switch name {
	case "SEARCH":
		return []string{rest}
	case "APPEND":
		return strings.SplitN(rest, " ", 2)
	default:
		return strings.Split(rest, " ")
	}
}

type stemCount struct {
	stem  string
	count int
}

func rankedCounts(counts map[string]int) []stemCount {
	ranked := make([]stemCount, 0, len(counts))
	for stem, count := range counts {
		ranked = append(ranked, stemCount{stem, count})
	}
	slices.SortFunc(ranked, func(left, right stemCount) int {
		return cmp.Or(cmp.Compare(right.count, left.count), strings.Compare(left.stem, right.stem))
	})
	return ranked
}

func closestDistance(positions, others []int, sameStem bool) (int, bool) {
	var gaps []int
	if sameStem {
		for index := 1; index < len(positions); index++ {
			gaps = append(gaps, positions[index]-positions[index-1])
		}
	} else {
		// The closest pair of different stems is adjacent in the merged order.
		type marker struct {
			position int
			source   int
		}
		var merged []marker
		for _, position := range positions {
			merged = append(merged, marker{position, 0})
		}
		for _, other := range others {
			merged = append(merged, marker{other, 1})
		}
		slices.SortFunc(merged, func(left, right marker) int {
			return cmp.Compare(left.position, right.position)
		})
		for index := 1; index < len(merged); index++ {
			if merged[index-1].source != merged[index].source {
				gaps = append(gaps, merged[index].position-merged[index-1].position)
			}
		}
	}
	if len(gaps) == 0 {
		return 0, false
	}
	return slices.Min(gaps), true
}

func gcd(first, second int) int {
	for second != 0 {
		first, second = second, first%second
	}
	return first
}

func jaccard(common, union int) (int, int) {
	if union == 0 {
		return 0, 1
	}
	divisor := gcd(common, union)
	return common / divisor, union / divisor
}

type token struct {
	text     string
	form     string
	stem     string
	line     int
	position int
	start    int
}

func (t token) end() int {
	return t.start + len(t.text)
}

type document struct {
	number int
	lines  []string
	tokens []token
}

func (d *document) addLine(text string) []token {
	d.lines = append(d.lines, text)
	var added []token
	for _, bounds := range tokenPattern.FindAllStringIndex(text, -1) {
		word := text[bounds[0]:bounds[1]]
		form := strings.ToLower(word)
		tok := token{word, form, porterStem(form), len(d.lines), len(d.tokens) + 1, bounds[0]}
		d.tokens = append(d.tokens, tok)
		added = append(added, tok)
	}
	return added
}

func (d *document) lineTokens(lineNumber int) []token {
	var found []token
	for _, tok := range d.tokens {
		if tok.line == lineNumber {
			found = append(found, tok)
		}
	}
	return found
}

func (d *document) reference(tok token) string {
	return fmt.Sprintf("%d:%d:%d", d.number, tok.line, tok.position)
}

type occurrence struct {
	doc *document
	tok token
}

func (o occurrence) reference() string {
	return o.doc.reference(o.tok)
}

func documentCount(occurrences []occurrence) int {
	numbers := make(map[int]bool)
	for _, found := range occurrences {
		numbers[found.doc.number] = true
	}
	return len(numbers)
}

type lexemeKind int

const (
	kindEnd lexemeKind = iota
	kindAnd
	kindOr
	kindNot
	kindOpen
	kindClose
	kindTerm
	kindPrefix
)

var symbols = map[string]lexemeKind{
	"AND": kindAnd, "OR": kindOr, "NOT": kindNot, "(": kindOpen, ")": kindClose,
}

type queryItem struct {
	kind     lexemeKind
	spelling string
}

func classify(lexeme string) (queryItem, error) {
	if kind, found := symbols[lexeme]; found {
		return queryItem{kind, lexeme}, nil
	}
	if wordPattern.MatchString(lexeme) {
		return queryItem{kindTerm, strings.ToLower(lexeme)}, nil
	}
	if prefixTermPattern.MatchString(lexeme) {
		return queryItem{kindPrefix, strings.ToLower(strings.TrimSuffix(lexeme, "*"))}, nil
	}
	return queryItem{}, errors.New("BAD TERM " + lexeme)
}

type queryResult struct {
	canonical string
	documents map[int]bool
}

type queryParser struct {
	items    []queryItem
	position int
	stemSets map[int]map[string]bool
}

func (p *queryParser) peek() lexemeKind {
	if p.position < len(p.items) {
		return p.items[p.position].kind
	}
	return kindEnd
}

func (p *queryParser) take() (queryItem, error) {
	if p.position >= len(p.items) {
		return queryItem{}, errSyntax
	}
	item := p.items[p.position]
	p.position++
	return item, nil
}

func (p *queryParser) parse() (queryResult, error) {
	result, err := p.expression()
	if err != nil {
		return queryResult{}, err
	}
	if p.position < len(p.items) {
		return queryResult{}, errSyntax
	}
	return result, nil
}

func (p *queryParser) expression() (queryResult, error) {
	result, err := p.conjunction()
	if err != nil {
		return queryResult{}, err
	}
	for p.peek() == kindOr {
		p.position++
		right, err := p.conjunction()
		if err != nil {
			return queryResult{}, err
		}
		documents := maps.Clone(result.documents)
		maps.Copy(documents, right.documents)
		result = queryResult{"(" + result.canonical + " OR " + right.canonical + ")", documents}
	}
	return result, nil
}

func continuesConjunction(kind lexemeKind) bool {
	switch kind {
	case kindAnd, kindNot, kindOpen, kindTerm, kindPrefix:
		return true
	}
	return false
}

func (p *queryParser) conjunction() (queryResult, error) {
	result, err := p.negation()
	if err != nil {
		return queryResult{}, err
	}
	for continuesConjunction(p.peek()) {
		if p.peek() == kindAnd {
			p.position++
		}
		right, err := p.negation()
		if err != nil {
			return queryResult{}, err
		}
		documents := make(map[int]bool)
		for number := range result.documents {
			if right.documents[number] {
				documents[number] = true
			}
		}
		result = queryResult{"(" + result.canonical + " AND " + right.canonical + ")", documents}
	}
	return result, nil
}

func (p *queryParser) negation() (queryResult, error) {
	if p.peek() != kindNot {
		return p.element()
	}
	p.position++
	inner, err := p.negation()
	if err != nil {
		return queryResult{}, err
	}
	documents := make(map[int]bool)
	for number := range p.stemSets {
		if !inner.documents[number] {
			documents[number] = true
		}
	}
	return queryResult{"(NOT " + inner.canonical + ")", documents}, nil
}

func (p *queryParser) element() (queryResult, error) {
	item, err := p.take()
	if err != nil {
		return queryResult{}, err
	}
	switch item.kind {
	case kindOpen:
		result, err := p.expression()
		if err != nil {
			return queryResult{}, err
		}
		closing, err := p.take()
		if err != nil || closing.kind != kindClose {
			return queryResult{}, errSyntax
		}
		return result, nil
	case kindTerm:
		stem := porterStem(item.spelling)
		documents := p.documentsWhere(func(stems map[string]bool) bool {
			return stems[stem]
		})
		return queryResult{stem, documents}, nil
	case kindPrefix:
		documents := p.documentsWhere(func(stems map[string]bool) bool {
			for stem := range stems {
				if strings.HasPrefix(stem, item.spelling) {
					return true
				}
			}
			return false
		})
		return queryResult{item.spelling + "*", documents}, nil
	}
	return queryResult{}, errSyntax
}

func (p *queryParser) documentsWhere(condition func(map[string]bool) bool) map[int]bool {
	documents := make(map[int]bool)
	for number, stems := range p.stemSets {
		if condition(stems) {
			documents[number] = true
		}
	}
	return documents
}

type command struct {
	minimum int
	maximum int
	handler func(*searchEngine, []string) error
}

var commands = map[string]command{
	"STEM":     {1, 10, (*searchEngine).stemWords},
	"STEPS":    {1, 1, (*searchEngine).showSteps},
	"MEASURE":  {1, 1, (*searchEngine).showMeasure},
	"INDEX":    {0, 1, (*searchEngine).showIndex},
	"SEARCH":   {1, 1, (*searchEngine).search},
	"PHRASE":   {2, 10, (*searchEngine).phrase},
	"NEAR":     {3, 3, (*searchEngine).near},
	"TOP":      {1, 2, (*searchEngine).top},
	"KWIC":     {1, 1, (*searchEngine).kwic},
	"TF":       {2, 2, (*searchEngine).termFrequency},
	"DF":       {1, 1, (*searchEngine).documentFrequency},
	"VARIANTS": {1, 1, (*searchEngine).variants},
	"SIMILAR":  {2, 2, (*searchEngine).similar},
	"RANK":     {2, 11, (*searchEngine).rank},
	"INFO":     {1, 1, (*searchEngine).info},
	"LINE":     {2, 2, (*searchEngine).showLine},
	"STATS":    {0, 0, (*searchEngine).stats},
	"STOP":     {1, 1, (*searchEngine).stop},
	"UNSTOP":   {1, 1, (*searchEngine).unstop},
	"APPEND":   {2, 2, (*searchEngine).appendLine},
	"DELETE":   {1, 1, (*searchEngine).delete},
}

type searchEngine struct {
	stopwords map[string]bool
	documents map[int]*document
	output    *bufio.Writer
}

func (e *searchEngine) emit(head string, items ...string) {
	e.output.WriteString(head)
	for _, item := range items {
		e.output.WriteString(" " + item)
	}
	e.output.WriteString("\n")
}

func (e *searchEngine) addDocument(number int) *document {
	doc := &document{number: number}
	e.documents[number] = doc
	return doc
}

func (e *searchEngine) orderedDocuments() []*document {
	numbers := slices.Sorted(maps.Keys(e.documents))
	ordered := make([]*document, len(numbers))
	for index, number := range numbers {
		ordered[index] = e.documents[number]
	}
	return ordered
}

func (e *searchEngine) isIndexed(tok token) bool {
	return !e.stopwords[tok.form]
}

func (e *searchEngine) indexedTokens(doc *document) []token {
	var indexed []token
	for _, tok := range doc.tokens {
		if e.isIndexed(tok) {
			indexed = append(indexed, tok)
		}
	}
	return indexed
}

func (e *searchEngine) termFrequencies(doc *document) map[string]int {
	counts := make(map[string]int)
	for _, tok := range e.indexedTokens(doc) {
		counts[tok.stem]++
	}
	return counts
}

func (e *searchEngine) stemSet(doc *document) map[string]bool {
	stems := make(map[string]bool)
	for stem := range e.termFrequencies(doc) {
		stems[stem] = true
	}
	return stems
}

func (e *searchEngine) totalFrequencies() map[string]int {
	totals := make(map[string]int)
	for _, doc := range e.documents {
		for stem, count := range e.termFrequencies(doc) {
			totals[stem] += count
		}
	}
	return totals
}

func (e *searchEngine) occurrenceMap() map[string][]occurrence {
	occurrences := make(map[string][]occurrence)
	for _, doc := range e.orderedDocuments() {
		for _, tok := range e.indexedTokens(doc) {
			occurrences[tok.stem] = append(occurrences[tok.stem], occurrence{doc, tok})
		}
	}
	return occurrences
}

func (e *searchEngine) stemPositions(doc *document, stem string) []int {
	var positions []int
	for _, tok := range e.indexedTokens(doc) {
		if tok.stem == stem {
			positions = append(positions, tok.position)
		}
	}
	return positions
}

func (e *searchEngine) formCount(form string) int {
	count := 0
	for _, doc := range e.documents {
		for _, tok := range doc.tokens {
			if tok.form == form {
				count++
			}
		}
	}
	return count
}

func (e *searchEngine) tokenMatches(tok token, target string) bool {
	return target == "?" || (e.isIndexed(tok) && tok.stem == target)
}

func (e *searchEngine) describeToken(tok token) string {
	if e.isIndexed(tok) {
		return tok.form + "/" + tok.stem
	}
	return tok.form + "/-"
}

func (e *searchEngine) termArgument(text string) (string, error) {
	word, err := wordArgument(text)
	if err != nil {
		return "", err
	}
	if e.stopwords[word] {
		return "", errors.New("STOPWORD " + word)
	}
	return porterStem(word), nil
}

func (e *searchEngine) documentArgument(text string) (*document, error) {
	number, err := numberArgument(text, 1, maxDocumentNumber)
	if err != nil {
		return nil, err
	}
	doc, found := e.documents[number]
	if !found {
		return nil, fmt.Errorf("NO DOC %d", number)
	}
	return doc, nil
}

func (e *searchEngine) stemWords(arguments []string) error {
	items := make([]string, 0, len(arguments))
	for _, argument := range arguments {
		word, err := wordArgument(argument)
		if err != nil {
			return err
		}
		items = append(items, word+":"+porterStem(word))
	}
	e.emit("STEM", items...)
	return nil
}

func (e *searchEngine) showSteps(arguments []string) error {
	word, err := wordArgument(arguments[0])
	if err != nil {
		return err
	}
	_, changes := stemmingSteps(word)
	if len(changes) == 0 {
		e.emit("STEPS " + word + " NONE")
		return nil
	}
	items := make([]string, len(changes))
	for index, change := range changes {
		items[index] = change.step + ":" + change.word
	}
	e.emit("STEPS "+word, items...)
	return nil
}

func (e *searchEngine) showMeasure(arguments []string) error {
	word, err := wordArgument(arguments[0])
	if err != nil {
		return err
	}
	e.emit(fmt.Sprintf("MEASURE %s %s m=%d vowel=%s double=%s cvc=%s", word,
		letterPattern(word), measure(word), yesNo(hasVowel(word)), yesNo(endsDouble(word)),
		yesNo(endsCvc(word))))
	return nil
}

func (e *searchEngine) showIndex(arguments []string) error {
	prefix := ""
	if len(arguments) == 1 {
		word, err := wordArgument(arguments[0])
		if err != nil {
			return err
		}
		prefix = word
	}
	occurrences := e.occurrenceMap()
	var stems []string
	for stem := range occurrences {
		if strings.HasPrefix(stem, prefix) {
			stems = append(stems, stem)
		}
	}
	slices.Sort(stems)
	e.emit(fmt.Sprintf("INDEX stems=%d", len(stems)))
	for _, stem := range stems {
		found := occurrences[stem]
		references := make([]string, len(found))
		for index, item := range found {
			references[index] = item.reference()
		}
		e.emit(fmt.Sprintf("%s df=%d", stem, documentCount(found)), references...)
	}
	return nil
}

func (e *searchEngine) search(arguments []string) error {
	var items []queryItem
	for _, lexeme := range lexemePattern.FindAllString(arguments[0], -1) {
		item, err := classify(lexeme)
		if err != nil {
			return err
		}
		items = append(items, item)
	}
	stemSets := make(map[int]map[string]bool)
	for number, doc := range e.documents {
		stemSets[number] = e.stemSet(doc)
	}
	parser := queryParser{items: items, stemSets: stemSets}
	result, err := parser.parse()
	if err != nil {
		return err
	}
	for _, item := range items {
		if item.kind == kindTerm && e.stopwords[item.spelling] {
			return errors.New("STOPWORD " + item.spelling)
		}
	}
	var numbers []string
	for _, number := range slices.Sorted(maps.Keys(result.documents)) {
		numbers = append(numbers, strconv.Itoa(number))
	}
	e.emit(fmt.Sprintf("SEARCH %s count=%d", result.canonical, len(numbers)), numbers...)
	return nil
}

func (e *searchEngine) phrase(arguments []string) error {
	words := make([]string, 0, len(arguments))
	for _, argument := range arguments {
		word, err := wordArgument(argument)
		if err != nil {
			return err
		}
		words = append(words, word)
	}
	if !slices.ContainsFunc(words, func(word string) bool { return !e.stopwords[word] }) {
		return errors.New("STOPWORDS ONLY")
	}
	targets := make([]string, len(words))
	for index, word := range words {
		if e.stopwords[word] {
			targets[index] = "?"
		} else {
			targets[index] = porterStem(word)
		}
	}
	var matches []string
	for _, doc := range e.orderedDocuments() {
		for start := 0; start+len(targets) <= len(doc.tokens); start++ {
			matched := true
			for offset, target := range targets {
				if !e.tokenMatches(doc.tokens[start+offset], target) {
					matched = false
					break
				}
			}
			if matched {
				matches = append(matches, doc.reference(doc.tokens[start]))
			}
		}
	}
	header := fmt.Sprintf("PHRASE \"%s\" matches=%d", strings.Join(targets, " "), len(matches))
	e.emit(header, matches...)
	return nil
}

func (e *searchEngine) near(arguments []string) error {
	first, err := e.termArgument(arguments[0])
	if err != nil {
		return err
	}
	second, err := e.termArgument(arguments[1])
	if err != nil {
		return err
	}
	limit, err := numberArgument(arguments[2], 1, maxCount)
	if err != nil {
		return err
	}
	var found []string
	for _, doc := range e.orderedDocuments() {
		distance, exists := closestDistance(
			e.stemPositions(doc, first), e.stemPositions(doc, second), first == second)
		if exists && distance <= limit {
			found = append(found, fmt.Sprintf("%d:%d", doc.number, distance))
		}
	}
	e.emit(fmt.Sprintf("NEAR %s %s %d count=%d", first, second, limit, len(found)), found...)
	return nil
}

func (e *searchEngine) top(arguments []string) error {
	limit, err := numberArgument(arguments[0], 1, maxCount)
	if err != nil {
		return err
	}
	var counts map[string]int
	header := fmt.Sprintf("TOP %d", limit)
	if len(arguments) == 2 {
		doc, err := e.documentArgument(arguments[1])
		if err != nil {
			return err
		}
		counts = e.termFrequencies(doc)
		header += fmt.Sprintf(" doc=%d", doc.number)
	} else {
		counts = e.totalFrequencies()
	}
	ranked := rankedCounts(counts)
	items := make([]string, 0, limit)
	for _, entry := range ranked[:min(limit, len(ranked))] {
		items = append(items, fmt.Sprintf("%s:%d", entry.stem, entry.count))
	}
	e.emit(header, items...)
	return nil
}

func (e *searchEngine) kwic(arguments []string) error {
	stem, err := e.termArgument(arguments[0])
	if err != nil {
		return err
	}
	found := e.occurrenceMap()[stem]
	e.emit(fmt.Sprintf("KWIC %s count=%d", stem, len(found)))
	for _, item := range found {
		text := item.doc.lines[item.tok.line-1]
		before := text[max(0, item.tok.start-kwicWidth):item.tok.start]
		after := text[item.tok.end():min(len(text), item.tok.end()+kwicWidth)]
		context := fmt.Sprintf("|%*s[%s]%-*s|", kwicWidth, before, item.tok.text, kwicWidth, after)
		e.emit(context, item.reference())
	}
	return nil
}

func (e *searchEngine) termFrequency(arguments []string) error {
	doc, err := e.documentArgument(arguments[0])
	if err != nil {
		return err
	}
	stem, err := e.termArgument(arguments[1])
	if err != nil {
		return err
	}
	e.emit(fmt.Sprintf("TF %d %s %d", doc.number, stem, e.termFrequencies(doc)[stem]))
	return nil
}

func (e *searchEngine) documentFrequency(arguments []string) error {
	stem, err := e.termArgument(arguments[0])
	if err != nil {
		return err
	}
	e.emit(fmt.Sprintf("DF %s %d", stem, documentCount(e.occurrenceMap()[stem])))
	return nil
}

func (e *searchEngine) variants(arguments []string) error {
	stem, err := e.termArgument(arguments[0])
	if err != nil {
		return err
	}
	forms := make(map[string]int)
	for _, item := range e.occurrenceMap()[stem] {
		forms[item.tok.form]++
	}
	var items []string
	for _, form := range slices.Sorted(maps.Keys(forms)) {
		items = append(items, fmt.Sprintf("%s:%d", form, forms[form]))
	}
	e.emit(fmt.Sprintf("VARIANTS %s count=%d", stem, len(forms)), items...)
	return nil
}

func (e *searchEngine) similar(arguments []string) error {
	doc, err := e.documentArgument(arguments[0])
	if err != nil {
		return err
	}
	limit, err := numberArgument(arguments[1], 1, maxCount)
	if err != nil {
		return err
	}
	type similarity struct {
		number      int
		numerator   int
		denominator int
	}
	stems := e.stemSet(doc)
	var scores []similarity
	for _, other := range e.documents {
		if other == doc {
			continue
		}
		otherStems := e.stemSet(other)
		common := 0
		for stem := range stems {
			if otherStems[stem] {
				common++
			}
		}
		numerator, denominator := jaccard(common, len(stems)+len(otherStems)-common)
		scores = append(scores, similarity{other.number, numerator, denominator})
	}
	slices.SortFunc(scores, func(left, right similarity) int {
		return cmp.Or(
			cmp.Compare(right.numerator*left.denominator, left.numerator*right.denominator),
			cmp.Compare(left.number, right.number),
		)
	})
	var items []string
	for _, score := range scores[:min(limit, len(scores))] {
		items = append(items,
			fmt.Sprintf("%d:%d/%d", score.number, score.numerator, score.denominator))
	}
	e.emit(fmt.Sprintf("SIMILAR %d", doc.number), items...)
	return nil
}

func (e *searchEngine) rank(arguments []string) error {
	limit, err := numberArgument(arguments[0], 1, maxCount)
	if err != nil {
		return err
	}
	query := make(map[string]bool)
	for _, argument := range arguments[1:] {
		stem, err := e.termArgument(argument)
		if err != nil {
			return err
		}
		query[stem] = true
	}
	type ranking struct {
		number  int
		matched int
		total   int
	}
	var ranked []ranking
	for _, doc := range e.documents {
		counts := e.termFrequencies(doc)
		matched, total := 0, 0
		for stem := range query {
			if counts[stem] > 0 {
				matched++
			}
			total += counts[stem]
		}
		if matched > 0 {
			ranked = append(ranked, ranking{doc.number, matched, total})
		}
	}
	slices.SortFunc(ranked, func(left, right ranking) int {
		return cmp.Or(
			cmp.Compare(right.matched, left.matched),
			cmp.Compare(right.total, left.total),
			cmp.Compare(left.number, right.number),
		)
	})
	var items []string
	for _, entry := range ranked[:min(limit, len(ranked))] {
		items = append(items, fmt.Sprintf("%d:%d:%d", entry.number, entry.matched, entry.total))
	}
	e.emit(fmt.Sprintf("RANK count=%d", len(ranked)), items...)
	return nil
}

func (e *searchEngine) info(arguments []string) error {
	doc, err := e.documentArgument(arguments[0])
	if err != nil {
		return err
	}
	counts := e.termFrequencies(doc)
	top := "-"
	if ranked := rankedCounts(counts); len(ranked) > 0 {
		top = fmt.Sprintf("%s:%d", ranked[0].stem, ranked[0].count)
	}
	indexed := 0
	for _, count := range counts {
		indexed += count
	}
	e.emit(fmt.Sprintf("INFO %d lines=%d tokens=%d indexed=%d stems=%d top=%s", doc.number,
		len(doc.lines), len(doc.tokens), indexed, len(counts), top))
	return nil
}

func (e *searchEngine) showLine(arguments []string) error {
	doc, err := e.documentArgument(arguments[0])
	if err != nil {
		return err
	}
	lineNumber, err := numberArgument(arguments[1], 1, maxLineNumber)
	if err != nil {
		return err
	}
	if lineNumber > len(doc.lines) {
		return fmt.Errorf("NO LINE %d:%d", doc.number, lineNumber)
	}
	tokens := doc.lineTokens(lineNumber)
	items := make([]string, len(tokens))
	for index, tok := range tokens {
		items[index] = e.describeToken(tok)
	}
	e.emit(fmt.Sprintf("LINE %d:%d tokens=%d", doc.number, lineNumber, len(tokens)), items...)
	return nil
}

func (e *searchEngine) stats(_ []string) error {
	lines, tokens, indexed := 0, 0, 0
	for _, doc := range e.documents {
		lines += len(doc.lines)
		tokens += len(doc.tokens)
		indexed += len(e.indexedTokens(doc))
	}
	e.emit(fmt.Sprintf("STATS docs=%d lines=%d tokens=%d indexed=%d stems=%d stopwords=%d",
		len(e.documents), lines, tokens, indexed, len(e.totalFrequencies()), len(e.stopwords)))
	return nil
}

func (e *searchEngine) stop(arguments []string) error {
	word, err := wordArgument(arguments[0])
	if err != nil {
		return err
	}
	if e.stopwords[word] {
		return errors.New("ALREADY STOPWORD " + word)
	}
	e.stopwords[word] = true
	e.emit(fmt.Sprintf("STOP %s unindexed=%d", word, e.formCount(word)))
	return nil
}

func (e *searchEngine) unstop(arguments []string) error {
	word, err := wordArgument(arguments[0])
	if err != nil {
		return err
	}
	if !e.stopwords[word] {
		return errors.New("NOT STOPWORD " + word)
	}
	delete(e.stopwords, word)
	e.emit(fmt.Sprintf("UNSTOP %s indexed=%d", word, e.formCount(word)))
	return nil
}

func (e *searchEngine) appendLine(arguments []string) error {
	number, err := numberArgument(arguments[0], 1, maxDocumentNumber)
	if err != nil {
		return err
	}
	doc, exists := e.documents[number]
	if !exists {
		doc = e.addDocument(number)
	}
	added := doc.addLine(arguments[1])
	indexed := 0
	for _, tok := range added {
		if e.isIndexed(tok) {
			indexed++
		}
	}
	e.emit(fmt.Sprintf("APPEND %d line=%d tokens=%d indexed=%d new=%s", number, len(doc.lines),
		len(added), indexed, yesNo(!exists)))
	return nil
}

func (e *searchEngine) delete(arguments []string) error {
	doc, err := e.documentArgument(arguments[0])
	if err != nil {
		return err
	}
	delete(e.documents, doc.number)
	e.emit(fmt.Sprintf("DELETE %d lines=%d tokens=%d", doc.number, len(doc.lines), len(doc.tokens)))
	return nil
}

func (e *searchEngine) execute(line string) {
	name, rest, hasArguments := strings.Cut(line, " ")
	if err := e.run(name, rest, hasArguments); err != nil {
		e.emit("ERROR " + err.Error())
	}
}

func (e *searchEngine) run(name, rest string, hasArguments bool) error {
	cmd, found := commands[name]
	if !found {
		return errors.New("UNKNOWN COMMAND " + name)
	}
	var arguments []string
	if hasArguments {
		arguments = splitArguments(name, rest)
	}
	if len(arguments) < cmd.minimum || len(arguments) > cmd.maximum {
		return errors.New("BAD ARGUMENTS " + name)
	}
	return cmd.handler(e, arguments)
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var lines []string
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	stopwords := make(map[string]bool)
	for _, word := range strings.Fields(lines[0])[1:] {
		stopwords[word] = true
	}
	engine := &searchEngine{
		stopwords: stopwords,
		documents: make(map[int]*document),
		output:    output,
	}
	index := 1
	for strings.HasPrefix(lines[index], "DOC ") {
		number, _ := strconv.Atoi(lines[index][4:])
		doc := engine.addDocument(number)
		index++
		for lines[index] != "ENDDOC" {
			doc.addLine(lines[index])
			index++
		}
		index++
	}
	for _, line := range lines[index:] {
		if line == "END" {
			break
		}
		engine.execute(line)
	}
}
