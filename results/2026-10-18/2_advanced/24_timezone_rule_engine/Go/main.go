package main

import (
	"errors"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	if len(data) == 0 {
		return []string{}
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func yearStart(year int) int64       { return dayNumber(year, 1, 1) * secondsPerDay }
func clockSeconds(text string) int64 { return int64(integer(text[:2])*3600 + integer(text[3:5])*60) }
func namesOrNone(names []string, separator string) string {
	if len(names) == 0 {
		return "none"
	}
	return strings.Join(names, separator)
}
func indented(lines []string) []string {
	result := append([]string(nil), lines...)
	for i := 1; i < len(result); i++ {
		result[i] = "  " + result[i]
	}
	return result
}

type Interval struct{ Low, High int64 }

func mergeIntervals(intervals []Interval) []Interval {
	sort.Slice(intervals, func(i, j int) bool {
		if intervals[i].Low != intervals[j].Low {
			return intervals[i].Low < intervals[j].Low
		}
		return intervals[i].High < intervals[j].High
	})
	merged := []Interval{}
	for _, span := range intervals {
		if len(merged) > 0 && span.Low <= merged[len(merged)-1].High {
			merged[len(merged)-1].High = max(merged[len(merged)-1].High, span.High)
		} else {
			merged = append(merged, span)
		}
	}
	return merged
}
func intersectIntervals(first, second []Interval) []Interval {
	pieces := []Interval{}
	for _, a := range first {
		for _, b := range second {
			low, high := max(a.Low, b.Low), min(a.High, b.High)
			if low < high {
				pieces = append(pieces, Interval{low, high})
			}
		}
	}
	return mergeIntervals(pieces)
}

type SourceLine struct {
	Number     int
	Fields     []string
	Kind       string
	Block      *Block
	Position   int
	ZoneLine   *ZoneLine
	FieldError bool
	Error      string
}

func newSourceLine(number int, content string) *SourceLine {
	fields := splitFields(content)
	kind := "unknown"
	if isContinuation(content) {
		kind = "continuation"
	} else if fields[0] == "Rule" || fields[0] == "Zone" || fields[0] == "Link" {
		kind = fields[0]
	}
	return &SourceLine{Number: number, Fields: fields, Kind: kind}
}
func (l *SourceLine) AcceptsContinuation() bool {
	return l.Kind == "Zone" && len(l.Fields) >= 6 || l.Kind == "continuation" && len(l.Fields) >= 4
}

type Block struct {
	Name    string
	Number  int
	Lines   []*SourceLine
	Defined bool
}

func (b *Block) Add(line *SourceLine) {
	line.Block = b
	line.Position = len(b.Lines)
	b.Lines = append(b.Lines, line)
}

type ZoneLine struct {
	StdOffset                  int64
	RulesText, RuleSet, Format string
	Save                       int64
	Until                      *Until
	Start, End                 int64
}

func newZoneLine(fields []string) (*ZoneLine, error) {
	offset, err := parseOffset(fields[0])
	if err != nil {
		return nil, err
	}
	line := &ZoneLine{StdOffset: offset, RulesText: fields[1], Format: fields[2], Start: negInfinity, End: posInfinity}
	if line.RulesText[0] >= '0' && line.RulesText[0] <= '9' {
		line.Save, err = parseSave(line.RulesText)
		if err != nil {
			return nil, err
		}
	} else if line.RulesText != "-" {
		line.RuleSet = line.RulesText
	}
	if err = checkFormat(line.Format, line.RuleSet != ""); err != nil {
		return nil, err
	}
	if len(fields) > 3 {
		line.Until, err = parseUntil(fields[3:])
		if err != nil {
			return nil, err
		}
	}
	return line, nil
}
func (l *ZoneLine) RulesNotation() string {
	if l.RuleSet != "" {
		return l.RuleSet
	}
	if l.RulesText == "-" {
		return "-"
	}
	return clockText(l.Save)
}
func (l *ZoneLine) UntilNotation() string {
	until := l.Until
	return until.YearText + " " + until.MonthText + " " + until.DayText + " " + clockText(until.Time) + until.Type
}

type Zone struct {
	Name     string
	Lines    []*ZoneLine
	Aliases  []string
	Applied  map[int]int
	Timeline Timeline
}

func (z *Zone) RuleSets() []string {
	names := []string{}
	for _, line := range z.Lines {
		if line.RuleSet != "" && nameIndex(names, line.RuleSet) < 0 {
			names = append(names, line.RuleSet)
		}
	}
	return names
}
func (z *Zone) LineNumberAt(time int64) int {
	for i, line := range z.Lines {
		if line.Start <= time && time < line.End {
			return i + 1
		}
	}
	return 0
}
func parseRule(line *SourceLine) (*Rule, error) {
	fields := line.Fields
	from, err := parseYear(fields[2])
	if err != nil {
		return nil, err
	}
	to, err := parseTo(fields[3], from)
	if err != nil {
		return nil, err
	}
	if fields[4] != "-" {
		return nil, errors.New("syntax error")
	}
	month, err := parseMonth(fields[5])
	if err != nil {
		return nil, err
	}
	day, err := parseDaySpec(fields[6], month)
	if err != nil {
		return nil, err
	}
	at, kind, err := parseTime(fields[7])
	if err != nil {
		return nil, err
	}
	save, err := parseSave(fields[8])
	if err != nil {
		return nil, err
	}
	letter, err := parseLetter(fields[9])
	if err != nil {
		return nil, err
	}
	return &Rule{line.Number, fields, fields[1], from, to, month, day, at, kind, save, letter}, nil
}
func standardLetter(instances []RuleInstance) string {
	for _, instance := range instances {
		if instance.Rule.Save == 0 {
			return instance.Rule.Letter
		}
	}
	return ""
}

type Database struct {
	Lines          []*SourceLine
	Blocks         []*Block
	RuleOrder      []string
	Rules          map[string][]*Rule
	Sequences      map[string][]RuleInstance
	ZoneOrder      []*Zone
	Zones, Aliases map[string]*Zone
}

func newDatabase(rawLines []string) *Database {
	db := &Database{Rules: map[string][]*Rule{}, Sequences: map[string][]RuleInstance{}, Zones: map[string]*Zone{}, Aliases: map[string]*Zone{}}
	for i, raw := range rawLines {
		if content := lineContent(raw); content != "" {
			db.Lines = append(db.Lines, newSourceLine(i+1, content))
		}
	}
	var previous *SourceLine
	for _, line := range db.Lines {
		if line.Kind == "Zone" {
			block := &Block{Name: line.Fields[1], Number: line.Number}
			block.Add(line)
			db.Blocks = append(db.Blocks, block)
		} else if line.Kind == "continuation" && previous != nil && previous.Block != nil && previous.AcceptsContinuation() {
			previous.Block.Add(line)
		}
		previous = line
	}
	for _, line := range db.Lines {
		if err := db.ParseFields(line); err != nil {
			line.FieldError = true
			line.Error = err.Error()
		}
	}
	zoneNames := map[string]bool{}
	for _, line := range db.Lines {
		if line.ZoneLine != nil {
			line.Error = db.StructuralError(line, zoneNames)
		}
	}
	for _, name := range db.RuleOrder {
		db.Sequences[name] = instanceSequence(db.Rules[name])
	}
	for _, block := range db.Blocks {
		block.Defined = true
		for _, line := range block.Lines {
			if line.Error != "" {
				block.Defined = false
				break
			}
		}
		if block.Defined {
			db.DefineZone(block)
		}
	}
	for _, line := range db.Lines {
		if line.Kind == "Link" && line.Error == "" {
			db.RegisterLink(line)
		}
	}
	return db
}
func (db *Database) ParseFields(line *SourceLine) error {
	limits := map[string][2]int{"Rule": {10, 10}, "Zone": {5, 9}, "continuation": {3, 7}, "Link": {3, 3}}
	if line.Kind == "unknown" || line.Kind == "continuation" && line.Block == nil {
		return errors.New("syntax error")
	}
	bounds := limits[line.Kind]
	if len(line.Fields) < bounds[0] || len(line.Fields) > bounds[1] {
		return errors.New("syntax error")
	}
	var err error
	if line.Kind == "Rule" {
		rule, problem := parseRule(line)
		if problem != nil {
			return problem
		}
		if _, exists := db.Rules[rule.Name]; !exists {
			db.RuleOrder = append(db.RuleOrder, rule.Name)
		}
		db.Rules[rule.Name] = append(db.Rules[rule.Name], rule)
	} else if line.Kind == "Zone" {
		line.ZoneLine, err = newZoneLine(line.Fields[2:])
	} else if line.Kind == "continuation" {
		line.ZoneLine, err = newZoneLine(line.Fields)
	}
	return err
}
func (db *Database) StructuralError(line *SourceLine, names map[string]bool) string {
	current := line.ZoneLine
	if line.Kind == "Zone" {
		name := line.Fields[1]
		if names[name] {
			return "duplicate zone " + name
		}
		names[name] = true
	}
	if current.RuleSet != "" {
		if _, found := db.Rules[current.RuleSet]; !found {
			return "unknown rule " + current.RuleSet
		}
	}
	if current.Until == nil {
		return ""
	}
	if line.Kind == "continuation" {
		previous := line.Block.Lines[line.Position-1]
		if !previous.FieldError && current.Until.Value <= previous.ZoneLine.Until.Value {
			return "until not increasing"
		}
	}
	if line.Position == len(line.Block.Lines)-1 {
		return "missing continuation"
	}
	return ""
}
func (db *Database) DefineZone(block *Block) {
	zone := &Zone{Name: block.Name, Applied: map[int]int{}}
	periods := []Period{}
	start := negInfinity
	add := func(time, save int64, letter string, line *ZoneLine) {
		period := Period{time, line.StdOffset + save, save != 0, abbreviation(line.Format, save, letter)}
		if len(periods) == 0 || !periods[len(periods)-1].SameState(period) {
			periods = append(periods, period)
		}
	}
	for _, source := range block.Lines {
		line := source.ZoneLine
		line.Start = start
		zone.Lines = append(zone.Lines, line)
		if line.RuleSet == "" {
			if line.Until != nil {
				line.End = line.Until.Value - adjustment(line.Until.Type, line.StdOffset, line.Save)
			}
			add(start, line.Save, "", line)
		} else {
			instances := db.Sequences[line.RuleSet]
			run := runInstances(instances, line.StdOffset, start, line.Until)
			line.End = run.End
			save, letter := int64(0), standardLetter(instances)
			if len(run.PreStart) > 0 {
				last := run.PreStart[len(run.PreStart)-1]
				save, letter = last.Save, last.Letter
			}
			add(start, save, letter, line)
			for _, applied := range run.Applied {
				add(applied.Time, applied.Rule.Save, applied.Rule.Letter, line)
				zone.Applied[applied.Rule.Number]++
			}
		}
		start = line.End
	}
	zone.Timeline = Timeline{periods}
	db.Zones[zone.Name] = zone
	db.ZoneOrder = append(db.ZoneOrder, zone)
}
func (db *Database) RegisterLink(line *SourceLine) {
	target, alias := line.Fields[1], line.Fields[2]
	zone := db.Zones[target]
	if zone == nil {
		line.Error = "unknown link target " + target
	} else if db.Zones[alias] != nil || db.Aliases[alias] != nil {
		line.Error = "duplicate link " + alias
	} else {
		db.Aliases[alias] = zone
		zone.Aliases = append(zone.Aliases, alias)
	}
}
func (db *Database) FindZone(name string) *Zone {
	if zone := db.Zones[name]; zone != nil {
		return zone
	}
	return db.Aliases[name]
}
func (db *Database) ErrorLines() []string {
	lines := []string{}
	for _, line := range db.Lines {
		if line.Error != "" {
			lines = append(lines, fmt.Sprintf("line %d: %s", line.Number, line.Error))
		}
	}
	return lines
}

func offsetShift(timeline Timeline, index int) int64 {
	return timeline.Periods[index].Offset - timeline.Periods[index-1].Offset
}
func transitionsBetween(timeline Timeline, low, high int64) []int {
	indices := []int{}
	for i := 1; i < len(timeline.Periods); i++ {
		if low <= timeline.Periods[i].Start && timeline.Periods[i].Start < high {
			indices = append(indices, i)
		}
	}
	return indices
}
func changeAt(timeline Timeline, index int) string {
	return changeText(timeline.Periods[index].Start, timeline.Periods[index-1], timeline.Periods[index])
}
func transitionLine(timeline Timeline, index int) string {
	time := timeline.Periods[index].Start
	shift := offsetShift(timeline, index)
	kind := "no shift"
	if shift > 0 {
		kind = "gap " + durationText(shift)
	} else if shift < 0 {
		kind = "overlap " + durationText(-shift)
	}
	return changeAt(timeline, index) + " (local " + localText(time+timeline.Periods[index-1].Offset) + " -> " + localText(time+timeline.Periods[index].Offset) + ", " + kind + ")"
}
func shiftsText(timeline Timeline, indices []int) string {
	gaps, overlaps, unchanged := 0, 0, 0
	for _, index := range indices {
		shift := offsetShift(timeline, index)
		if shift > 0 {
			gaps++
		} else if shift < 0 {
			overlaps++
		} else {
			unchanged++
		}
	}
	return fmt.Sprintf("gaps %d, overlaps %d, no shift %d", gaps, overlaps, unchanged)
}
func candidateText(timeline Timeline, local int64, index int) string {
	period := timeline.Periods[index]
	return utText(local-period.Offset) + " (" + stateText(period) + ")"
}
func chosenCandidate(candidates []int, option string) int {
	if len(candidates) == 1 || len(candidates) == 2 && option == "EARLIER" {
		return candidates[0]
	}
	if len(candidates) == 2 && option == "LATER" {
		return candidates[1]
	}
	return -1
}
func unresolvedText(timeline Timeline, local int64, candidates []int) string {
	if len(candidates) > 0 {
		texts := []string{}
		for _, index := range candidates {
			texts = append(texts, candidateText(timeline, local, index))
		}
		return "AMBIGUOUS " + strings.Join(texts, " or ")
	}
	index := timeline.SkippingTransition(local)
	time := timeline.Periods[index].Start
	return "NONEXISTENT gap " + localText(time+timeline.Periods[index-1].Offset) + " to " + localText(time+timeline.Periods[index].Offset) + " at " + utText(time)
}
func workingHours(timeline Timeline, start, end int64) []Interval {
	pieces := []Interval{}
	for _, index := range timeline.Nearby(start, end) {
		offset := timeline.Periods[index].Offset
		low, high := max(start-offset, timeline.Periods[index].Start), min(end-offset, timeline.EndOf(index))
		if low < high {
			pieces = append(pieces, Interval{low, high})
		}
	}
	return mergeIntervals(pieces)
}
func parseValue(kind, word string) (int64, bool) {
	year := integer(word[:4])
	if year < 1800 || year > 2099 {
		return 0, false
	}
	if kind == "year" {
		return int64(year), true
	}
	month, day := integer(word[5:7]), integer(word[8:10])
	if month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month) {
		return 0, false
	}
	if kind == "date" {
		return dayNumber(year, month, day), true
	}
	hour, minute, second := integer(word[11:13]), integer(word[14:16]), integer(word[17:19])
	if hour > 23 || minute > 59 || second > 59 {
		return 0, false
	}
	return timeValue(year, month, day, hour, minute, second), true
}

type QueryArgument struct {
	Zone  *Zone
	Value int64
}
type QueryRunner struct {
	Database           *Database
	WorkStart, WorkEnd int64
	Answers            []string
	TransitionBlocks   [][]string
}

func (q *QueryRunner) Run(line string) {
	words := strings.Split(line, " ")
	command := words[0]
	arguments := words[1:]
	option := ""
	if (command == "TOUTC" || command == "CONVERT") && (arguments[len(arguments)-1] == "EARLIER" || arguments[len(arguments)-1] == "LATER") {
		option = arguments[len(arguments)-1]
		arguments = arguments[:len(arguments)-1]
	}
	kinds := map[string][]string{"TOUTC": {"zone", "local"}, "TOLOCAL": {"zone", "ut"}, "CONVERT": {"zone", "zone", "local"}, "OFFSET": {"zone", "ut"}, "TRANSITIONS": {"zone", "year", "year"}, "DURATION": {"zone", "local", "local"}}[command]
	if command == "MEETING" {
		kinds = make([]string, len(arguments))
		kinds[0] = "date"
		for i := 1; i < len(kinds); i++ {
			kinds[i] = "zone"
		}
	}
	values := make([]QueryArgument, len(arguments))
	result := ""
	for i, word := range arguments {
		if kinds[i] == "zone" {
			values[i].Zone = q.Database.FindZone(word)
			if values[i].Zone == nil {
				result = "ERROR unknown zone " + word
				break
			}
		} else {
			value, ok := parseValue(kinds[i], word)
			if !ok {
				result = "ERROR invalid value " + word
				break
			}
			values[i].Value = value
		}
	}
	if result == "" {
		result = q.Answer(line, command, values, arguments, option)
	}
	q.Answers = append(q.Answers, line+" => "+result)
}
func (q *QueryRunner) Answer(line, command string, values []QueryArgument, arguments []string, option string) string {
	if command == "MEETING" {
		zones := []*Zone{}
		for _, value := range values[1:] {
			zones = append(zones, value.Zone)
		}
		return q.Meeting(values[0].Value, zones, arguments[1:])
	}
	zone := values[0].Zone
	timeline := zone.Timeline
	value := values[1].Value
	switch command {
	case "TOUTC":
		candidates := timeline.Candidates(value)
		index := chosenCandidate(candidates, option)
		if index < 0 {
			return unresolvedText(timeline, value, candidates)
		}
		return candidateText(timeline, value, index)
	case "TOLOCAL":
		period := timeline.PeriodAt(value)
		return localText(value+period.Offset) + " (" + stateText(period) + ")"
	case "CONVERT":
		local := values[2].Value
		candidates := timeline.Candidates(local)
		index := chosenCandidate(candidates, option)
		if index < 0 {
			return unresolvedText(timeline, local, candidates)
		}
		time := local - timeline.Periods[index].Offset
		period := values[1].Zone.Timeline.PeriodAt(time)
		targetLocal := time + period.Offset
		shift := floorDiv(targetLocal, secondsPerDay) - floorDiv(local, secondsPerDay)
		shiftText := strconv.FormatInt(shift, 10)
		if shift > 0 {
			shiftText = "+" + shiftText
		}
		return localText(targetLocal) + " (" + stateText(period) + ") at " + utText(time) + ", day shift " + shiftText
	case "OFFSET":
		index := timeline.IndexAt(value)
		text := stateText(timeline.Periods[index])
		if index >= 1 {
			text += " since " + utText(timeline.Periods[index].Start)
		}
		if index+1 < len(timeline.Periods) {
			text += " until " + utText(timeline.Periods[index+1].Start)
		}
		return text
	case "TRANSITIONS":
		last := values[2].Value
		if value > last {
			return "ERROR invalid range"
		}
		selected := transitionsBetween(timeline, yearStart(int(value)), yearStart(int(last)+1))
		block := []string{line}
		for _, index := range selected {
			block = append(block, transitionLine(timeline, index))
		}
		block = append(block, shiftsText(timeline, selected))
		q.TransitionBlocks = append(q.TransitionBlocks, block)
		return fmt.Sprintf("transitions: %d", len(selected))
	case "DURATION":
		offsets := make([]int64, 2)
		for i := 0; i < 2; i++ {
			candidates := timeline.Candidates(values[i+1].Value)
			if len(candidates) == 2 {
				return "AMBIGUOUS " + arguments[i+1]
			}
			if len(candidates) == 0 {
				return "NONEXISTENT " + arguments[i+1]
			}
			offsets[i] = timeline.Periods[candidates[0]].Offset
		}
		second := values[2].Value
		elapsed := (second - offsets[1]) - (value - offsets[0])
		return fmt.Sprintf("%d s (%s), wall clock %s, offset change %s", elapsed, durationText(elapsed), durationText(second-value), offsetText(offsets[1]-offsets[0]))
	}
	return ""
}
func (q *QueryRunner) Meeting(day int64, zones []*Zone, words []string) string {
	start, end := day*secondsPerDay+q.WorkStart, day*secondsPerDay+q.WorkEnd
	common := workingHours(zones[0].Timeline, start, end)
	for _, zone := range zones[1:] {
		common = intersectIntervals(common, workingHours(zone.Timeline, start, end))
	}
	if len(common) == 0 {
		return "NONE"
	}
	parts := []string{}
	for _, span := range common {
		members := []string{}
		for i, zone := range zones {
			period := zone.Timeline.PeriodAt(span.Low)
			members = append(members, words[i]+" "+localText(span.Low+period.Offset)+" "+period.Abbreviation)
		}
		parts = append(parts, utText(span.Low)+" to "+utText(span.High)+" ("+durationText(span.High-span.Low)+") ["+strings.Join(members, ", ")+"]")
	}
	return strings.Join(parts, "; ")
}

func ruleText(rule *Rule) string {
	fields := rule.Fields
	return "rule " + rule.Name + " " + fields[2] + " " + fields[3] + " " + fields[5] + " " + fields[6] + " " + clockText(rule.At) + rule.AtType + " " + clockText(rule.Save) + " " + fields[9]
}
func databaseBlock(db *Database) []string {
	validRules, ruleCount, validLinks, linkCount, zoneLines := 0, 0, 0, 0, 0
	for _, line := range db.Lines {
		if line.Kind == "Rule" {
			ruleCount++
			if line.Error == "" {
				validRules++
			}
		}
		if line.Kind == "Link" {
			linkCount++
			if line.Error == "" {
				validLinks++
			}
		}
	}
	used := map[string]bool{}
	for _, zone := range db.ZoneOrder {
		zoneLines += len(zone.Lines)
		for _, name := range zone.RuleSets() {
			used[name] = true
		}
	}
	unused, invalid := []string{}, []string{}
	for _, name := range db.RuleOrder {
		if !used[name] {
			unused = append(unused, name)
		}
	}
	for _, block := range db.Blocks {
		if !block.Defined {
			invalid = append(invalid, fmt.Sprintf("%s (line %d)", block.Name, block.Number))
		}
	}
	lines := []string{"DATABASE", fmt.Sprintf("rule lines: %d valid, %d invalid", validRules, ruleCount-validRules), fmt.Sprintf("zones: %d defined, %d invalid", len(db.Zones), len(db.Blocks)-len(db.Zones)), fmt.Sprintf("zone lines: %d in defined zones", zoneLines), fmt.Sprintf("links: %d defined, %d invalid", validLinks, linkCount-validLinks), fmt.Sprintf("errors: %d", len(db.ErrorLines())), "unused rules: " + namesOrNone(unused, " "), "invalid zones: " + namesOrNone(invalid, ", ")}
	for _, name := range db.RuleOrder {
		rules := db.Rules[name]
		first, last := rules[0].From, rules[0].To
		hasMax := false
		for _, rule := range rules {
			first = min(first, rule.From)
			last = max(last, rule.To)
			hasMax = hasMax || rule.Fields[3] == "max"
		}
		lastText := strconv.Itoa(last)
		if hasMax {
			lastText = "max"
		}
		count := 0
		for _, zone := range db.ZoneOrder {
			if nameIndex(zone.RuleSets(), name) >= 0 {
				count++
			}
		}
		lines = append(lines, fmt.Sprintf("rule set %s: lines %d, years %d-%s, zones %d", name, len(rules), first, lastText, count))
	}
	return lines
}
func dstLines(timeline Timeline, reference int64) []string {
	indices := []int{}
	for i, period := range timeline.Periods {
		if period.DST {
			indices = append(indices, i)
		}
	}
	lines := []string{"dst years: none"}
	if len(indices) > 0 {
		first, _, _, _, _, _ := splitTime(timeline.Periods[indices[0]].Start)
		last := first
		for _, i := range indices[1:] {
			year, _, _, _, _, _ := splitTime(timeline.Periods[i].Start)
			first = min(first, year)
			last = max(last, year)
		}
		lines[0] = fmt.Sprintf("dst years: %d-%d", first, last)
	}
	year, _, _, _, _, _ := splitTime(reference)
	low, high := yearStart(year), yearStart(year+1)
	pieces := []Interval{}
	for _, i := range indices {
		start, end := max(low, timeline.Periods[i].Start), min(high, timeline.EndOf(i))
		if start < end {
			pieces = append(pieces, Interval{start, end})
		}
	}
	total := int64(0)
	for _, span := range mergeIntervals(pieces) {
		lines = append(lines, "dst period: "+utText(span.Low)+" to "+utText(span.High)+" ("+durationText(span.High-span.Low)+")")
		total += span.High - span.Low
	}
	return append(lines, fmt.Sprintf("dst total %d: %s", year, durationText(total)))
}
func zoneBlock(db *Database, zone *Zone, reference int64) []string {
	timeline := zone.Timeline
	periods := timeline.Periods
	lines := []string{"ZONE " + zone.Name, "aliases: " + namesOrNone(zone.Aliases, " ")}
	for i, line := range zone.Lines {
		text := fmt.Sprintf("line %d: %s %s %s", i+1, offsetText(line.StdOffset), line.RulesNotation(), line.Format)
		if i > 0 {
			text += " from " + utText(line.Start)
		}
		if line.Until != nil {
			text += " until " + line.UntilNotation() + " = " + utText(line.End)
		}
		lines = append(lines, fmt.Sprintf("%s, transitions %d", text, len(transitionsBetween(timeline, line.Start, line.End))))
	}
	for _, name := range zone.RuleSets() {
		for _, rule := range db.Rules[name] {
			lines = append(lines, fmt.Sprintf("%s, applied %d", ruleText(rule), zone.Applied[rule.Number]))
		}
	}
	lowOffset, highOffset := periods[0].Offset, periods[0].Offset
	stateOrder := []string{}
	counts := map[string]int{}
	for _, period := range periods {
		lowOffset = min(lowOffset, period.Offset)
		highOffset = max(highOffset, period.Offset)
		state := stateText(period)
		if counts[state] == 0 {
			stateOrder = append(stateOrder, state)
		}
		counts[state]++
	}
	lines = append(lines, "offset range: "+offsetText(lowOffset)+" to "+offsetText(highOffset))
	for _, state := range stateOrder {
		lines = append(lines, fmt.Sprintf("state %s, periods %d", state, counts[state]))
	}
	index := timeline.IndexAt(reference)
	period := periods[index]
	lines = append(lines, fmt.Sprintf("reference: %s (%s), line %d", localText(reference+period.Offset), stateText(period), zone.LineNumberAt(reference)))
	previous, next := "none", "none"
	if index >= 1 {
		previous = changeAt(timeline, index)
	}
	if index+1 < len(periods) {
		next = changeAt(timeline, index+1)
	}
	every := make([]int, len(periods)-1)
	for i := range every {
		every[i] = i + 1
	}
	lines = append(lines, "previous transition: "+previous, "next transition: "+next, fmt.Sprintf("transitions: %d, %s", len(every), shiftsText(timeline, every)))
	return append(lines, dstLines(timeline, reference)...)
}
func main() {
	database := newDatabase(readLines("input/tzdata.txt"))
	params := readLines("input/params.txt")
	reference, _ := parseValue("ut", strings.Split(params[0], " ")[1])
	workday := strings.Split(params[1], " ")
	runner := &QueryRunner{Database: database, WorkStart: clockSeconds(workday[1]), WorkEnd: clockSeconds(workday[2])}
	for _, line := range readLines("input/queries.txt") {
		runner.Run(line)
	}
	blocks := [][]string{indented(databaseBlock(database))}
	names := []string{}
	for name := range database.Zones {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		blocks = append(blocks, indented(zoneBlock(database, database.Zones[name], reference)))
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("answers.txt", runner.Answers)
	writeLines("errors.txt", database.ErrorLines())
	writeBlocks("transitions.txt", runner.TransitionBlocks)
	writeBlocks("zone_summary.txt", blocks)
}
