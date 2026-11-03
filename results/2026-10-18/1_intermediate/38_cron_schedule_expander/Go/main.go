package main

import (
	"bufio"
	"errors"
	"fmt"
	"math/bits"
	"os"
	"slices"
	"strconv"
	"strings"
)

var fieldNames = [...]string{"minute", "hour", "day-of-month", "month", "day-of-week"}
var minimum = [...]int{0, 0, 1, 1, 0}
var maximum = [...]int{59, 23, 31, 12, 7}
var monthNames = [...]string{"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
var weekNames = [...]string{"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}

func digits(text string, least, most int) bool {
	if len(text) < least || len(text) > most {
		return false
	}
	for _, c := range text {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
func integer(text string) int { value, _ := strconv.Atoi(text); return value }
func leap(year int) bool { return year%4 == 0 && (year%100 != 0 || year%400 == 0) }
func monthLength(year, month int) int {
	if month == 2 && leap(year) {
		return 29
	}
	return [...]int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}[month-1]
}

type Date struct{ year, month, day int }

func (d Date) number() int {
	result := d.day - 1
	for year := 2000; year < d.year; year++ {
		if leap(year) { result += 366 } else { result += 365 }
	}
	for month := 1; month < d.month; month++ {
		result += monthLength(d.year, month)
	}
	return result
}
func dateFromNumber(number int) Date {
	year, month := 2000, 1
	for {
		days := 365
		if leap(year) { days++ }
		if number < days { break }
		number -= days
		year++
	}
	for number >= monthLength(year, month) {
		number -= monthLength(year, month)
		month++
	}
	return Date{year, month, number + 1}
}
func (d Date) weekday() int { return (d.number() + 6) % 7 }
func (d Date) String() string {
	return fmt.Sprintf("%04d-%02d-%02d %s", d.year, d.month, d.day, weekNames[d.weekday()][:3])
}
func pattern(text, form string) bool {
	if len(text) != len(form) { return false }
	for i := range len(form) {
		if form[i] == '#' {
			if text[i] < '0' || text[i] > '9' { return false }
		} else if text[i] != form[i] { return false }
	}
	return true
}
func readDate(text, reason string) (Date, error) {
	if !pattern(text, "####-##-##") { return Date{}, errors.New(reason) }
	date := Date{integer(text[:4]), integer(text[5:7]), integer(text[8:])}
	if date.year < 2001 || date.year > 2098 || date.month < 1 || date.month > 12 || date.day < 1 || date.day > monthLength(date.year, date.month) {
		return Date{}, errors.New(reason)
	}
	return date, nil
}
func readDatetime(words []string, at int) (int, error) {
	date, err := readDate(words[at], "invalid datetime")
	if err != nil { return 0, err }
	time := words[at+1]
	if !pattern(time, "##:##") { return 0, errors.New("invalid datetime") }
	hour, minute := integer(time[:2]), integer(time[3:])
	if hour > 23 || minute > 59 { return 0, errors.New("invalid datetime") }
	return date.number()*1440 + hour*60 + minute, nil
}
func readMonth(text string) (Date, error) {
	if !pattern(text, "####-##") { return Date{}, errors.New("invalid month") }
	date := Date{integer(text[:4]), integer(text[5:]), 1}
	if date.year < 2001 || date.year > 2098 || date.month < 1 || date.month > 12 {
		return Date{}, errors.New("invalid month")
	}
	return date, nil
}
func datetimeText(time int) string {
	date := dateFromNumber(time / 1440)
	return fmt.Sprintf("%04d-%02d-%02d %02d:%02d %s", date.year, date.month, date.day, time%1440/60, time%60, weekNames[date.weekday()][:3])
}
func span(minutes int) string { return fmt.Sprintf("%dd%02dh%02dm", minutes/1440, minutes%1440/60, minutes%60) }
func positive(text string, width, maximum int, reason string) (int, error) {
	if !digits(text, 1, width) || text[0] == '0' || integer(text) > maximum { return 0, errors.New(reason) }
	return integer(text), nil
}
func readWindow(words []string, at int) (int, int, error) {
	low, err := readDatetime(words, at)
	if err != nil { return 0, 0, err }
	high, err := readDatetime(words, at+2)
	if err != nil { return 0, 0, err }
	if low > high { return 0, 0, errors.New("invalid window") }
	if high-low > 44640 { return 0, 0, errors.New("window too long") }
	return low, high, nil
}

type SpecialKind int

const (
	LastDay SpecialKind = iota
	LastWorkday
	BeforeLast
	NearestWorkday
	NthWeekday
	LastWeekday
)

type Special struct {
	kind SpecialKind
	value, occurrence int
}

func (s Special) String() string {
	switch s.kind {
	case LastDay: return "L"
	case LastWorkday: return "LW"
	case BeforeLast: return fmt.Sprintf("L-%d", s.value)
	case NearestWorkday: return fmt.Sprintf("%dW", s.value)
	case NthWeekday: return fmt.Sprintf("%d#%d", s.value, s.occurrence)
	default: return fmt.Sprintf("%dL", s.value)
	}
}

type Field struct {
	values []int
	specials []Special
	restricted bool
}

func readValue(text string, index int) (int, error) {
	names := []string{}
	if index == 3 { names = []string{"JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"} }
	if index == 4 { names = []string{"SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"} }
	if at := slices.Index(names, text); at >= 0 {
		if index == 3 { at++ }
		return at, nil
	}
	if !digits(text, 1, 2) { return 0, errors.New("invalid value") }
	value := integer(text)
	if value < minimum[index] || value > maximum[index] { return 0, errors.New("out of range") }
	return value, nil
}
func specialNumber(text string, upper, width int) (int, error) {
	if !digits(text, 1, width) { return 0, errors.New("invalid value") }
	value := integer(text)
	if value < 1 || value > upper { return 0, errors.New("out of range") }
	return value, nil
}
func (f *Field) addItem(item string, index int, values *[60]bool) error {
	if item == "" { return errors.New("empty item") }
	var special Special
	isSpecial := false
	if index == 2 && (strings.HasPrefix(item, "L") || strings.HasSuffix(item, "W")) {
		isSpecial = true
		switch {
		case item == "L": special.kind = LastDay
		case item == "LW": special.kind = LastWorkday
		case strings.HasPrefix(item, "L-"):
			n, err := specialNumber(item[2:], 30, 2)
			if err != nil { return err }
			special = Special{kind: BeforeLast, value: n}
		case strings.HasSuffix(item, "W"):
			n, err := specialNumber(item[:len(item)-1], 31, 2)
			if err != nil { return err }
			special = Special{kind: NearestWorkday, value: n}
		default: return errors.New("invalid value")
		}
	} else if index == 4 && strings.Contains(item, "#") {
		v, n, _ := strings.Cut(item, "#")
		weekday, err := readValue(v, index)
		if err != nil { return err }
		occurrence, err := specialNumber(n, 5, 1)
		if err != nil { return err }
		special, isSpecial = Special{NthWeekday, weekday % 7, occurrence}, true
	} else if index == 4 && len(item) >= 2 && strings.HasSuffix(item, "L") {
		weekday, err := readValue(item[:len(item)-1], index)
		if err != nil { return err }
		special, isSpecial = Special{kind: LastWeekday, value: weekday % 7}, true
	}
	if isSpecial {
		if !slices.Contains(f.specials, special) { f.specials = append(f.specials, special) }
		return nil
	}
	base, stepPart, hasStep := strings.Cut(item, "/")
	var first, last int
	if base == "*" { first, last = minimum[index], maximum[index] } else {
		a, b, hasRange := strings.Cut(base, "-")
		var err error
		first, err = readValue(a, index)
		if err != nil { return err }
		if hasRange {
			last, err = readValue(b, index)
			if err != nil { return err }
			if first > last { return errors.New("invalid range") }
		} else if hasStep { last = maximum[index] } else { last = first }
	}
	step := 1
	if hasStep {
		if !digits(stepPart, 1, 2) || integer(stepPart) == 0 { return errors.New("invalid step") }
		step = integer(stepPart)
	}
	for value := first; value <= last; value += step {
		normalized := value
		if index == 4 { normalized %= 7 }
		values[normalized] = true
	}
	return nil
}
func readField(text string, index int) (Field, error) {
	field := Field{restricted: text[0] != '*'}
	var values [60]bool
	for _, item := range strings.Split(text, ",") {
		if err := field.addItem(item, index, &values); err != nil { return Field{}, fmt.Errorf("%s %s", fieldNames[index], err) }
	}
	for value, present := range values {
		if present { field.values = append(field.values, value) }
	}
	return field, nil
}
func (f Field) contains(value int) bool { _, found := slices.BinarySearch(f.values, value); return found }
func wordList(parts []string, either bool) string {
	if len(parts) < 2 { return strings.Join(parts, "") }
	conjunction := " and "
	if either { conjunction = " or " }
	return strings.Join(parts[:len(parts)-1], ", ") + conjunction + parts[len(parts)-1]
}
func valueName(index, value int) string {
	if index == 3 { return monthNames[value-1] }
	if index == 4 { return weekNames[value] }
	return strconv.Itoa(value)
}
func (f Field) valueList(index int, either bool) string {
	var parts []string
	for first := 0; first < len(f.values); {
		last := first
		for last+1 < len(f.values) && f.values[last+1] == f.values[last]+1 { last++ }
		if last-first >= 2 { parts = append(parts, valueName(index, f.values[first])+" through "+valueName(index, f.values[last])) } else {
			for _, value := range f.values[first:last+1] { parts = append(parts, valueName(index, value)) }
		}
		first = last + 1
	}
	return wordList(parts, either)
}
func (f Field) stepped(upper int) int {
	if len(f.values) < 2 || f.values[0] != 0 || f.values[1] < 2 { return 0 }
	step := f.values[1]
	if len(f.values) != upper/step+1 { return 0 }
	for i, value := range f.values { if value != i*step { return 0 } }
	return step
}
func (f Field) dayPhrase(weekday, either bool) string {
	var parts []string
	if len(f.values) != 0 {
		if weekday { parts = append(parts, f.valueList(4, either)) } else {
			prefix := "days "
			if len(f.values) == 1 { prefix = "day " }
			parts = append(parts, prefix+f.valueList(2, false))
		}
	}
	for _, special := range f.specials {
		var text string
		switch special.kind {
		case LastDay: text = "the last day"
		case LastWorkday: text = "the last weekday"
		case BeforeLast:
			noun := "days"
			if special.value == 1 { noun = "day" }
			text = fmt.Sprintf("%d %s before the last day", special.value, noun)
		case NearestWorkday: text = fmt.Sprintf("the weekday nearest day %d", special.value)
		case NthWeekday: text = fmt.Sprintf("the %s %s", [...]string{"1st", "2nd", "3rd", "4th", "5th"}[special.occurrence-1], weekNames[special.value])
		case LastWeekday: text = "the last " + weekNames[special.value]
		}
		parts = append(parts, text)
	}
	text := wordList(parts, either)
	if !weekday || len(f.specials) != 0 { text += " of the month" }
	return text
}

type Cron struct {
	fields [5]Field
	daily []int
	text, expanded string
}

func parseCron(words []string) (*Cron, error) {
	cron := &Cron{text: strings.Join(words, " ")}
	if len(words) == 1 && strings.HasPrefix(words[0], "@") {
		var expansion string
		switch words[0] {
		case "@yearly", "@annually": expansion = "0 0 1 1 *"
		case "@monthly": expansion = "0 0 1 * *"
		case "@weekly": expansion = "0 0 * * 0"
		case "@daily", "@midnight": expansion = "0 0 * * *"
		case "@hourly": expansion = "0 * * * *"
		default: return nil, errors.New("unknown macro")
		}
		words = strings.Split(expansion, " ")
	}
	if len(words) != 5 { return nil, errors.New("field count") }
	cron.expanded = strings.Join(words, " ")
	for i, word := range words {
		field, err := readField(word, i)
		if err != nil { return nil, err }
		cron.fields[i] = field
	}
	for _, hour := range cron.fields[1].values {
		for _, minute := range cron.fields[0].values { cron.daily = append(cron.daily, hour*60+minute) }
	}
	return cron, nil
}
func (c *Cron) orRule() bool { return c.fields[2].restricted && c.fields[4].restricted }
func (c *Cron) matchDay(date Date) (bool, bool, bool) {
	last, weekday := monthLength(date.year, date.month), date.weekday()
	nearest := func(day int) int {
		w := (date.number() - date.day + day + 6) % 7
		if w == 6 { if day == 1 { return 3 }; return day - 1 }
		if w == 0 { if day == last { return day - 2 }; return day + 1 }
		return day
	}
	dom, dow := c.fields[2].contains(date.day), c.fields[4].contains(weekday)
	for _, special := range c.fields[2].specials {
		target := 0
		switch special.kind {
		case LastDay: target = last
		case LastWorkday: target = nearest(last)
		case BeforeLast: target = last - special.value
		case NearestWorkday: if special.value <= last { target = nearest(special.value) }
		}
		dom = dom || target == date.day
	}
	for _, special := range c.fields[4].specials {
		matches := date.day+7 > last
		if special.kind == NthWeekday { matches = (date.day-1)/7+1 == special.occurrence }
		dow = dow || weekday == special.value && matches
	}
	if c.orRule() { return dom, dow, dom || dow }
	return dom, dow, dom && dow
}
func (c *Cron) scheduled(date Date) bool {
	_, _, condition := c.matchDay(date)
	return c.fields[3].contains(date.month) && condition
}
func (c *Cron) fires(low, high int, holidays map[int]bool, reverse bool, limit int) []int {
	first, last, step := low/1440, high/1440, 1
	day := first
	if reverse { day, step = last, -1 }
	var result []int
	for ; day >= first && day <= last; day += step {
		if holidays[day] || !c.scheduled(dateFromNumber(day)) { continue }
		i := 0
		if reverse { i = len(c.daily) - 1 }
		for ; i >= 0 && i < len(c.daily); i += step {
			time := day*1440 + c.daily[i]
			if time < low || time > high { continue }
			result = append(result, time)
			if limit > 0 && len(result) == limit { return result }
		}
	}
	return result
}
func (c *Cron) description() string {
	minute, hour, dom, month, dow := c.fields[0], c.fields[1], c.fields[2], c.fields[3], c.fields[4]
	var text string
	if len(c.daily) <= 4 {
		var times []string
		for _, t := range c.daily { times = append(times, fmt.Sprintf("%02d:%02d", t/60, t%60)) }
		text = "At " + wordList(times, false)
	} else {
		ms, hs := minute.stepped(59), hour.stepped(23)
		switch {
		case len(minute.values) == 60: text = "Every minute"
		case ms > 0: text = fmt.Sprintf("Every %d minutes", ms)
		case len(minute.values) == 1: text = fmt.Sprintf("At minute %d", minute.values[0])
		default: text = "At minutes " + minute.valueList(0, false)
		}
		first, last := hour.values[0], hour.values[len(hour.values)-1]
		switch {
		case len(hour.values) == 24: if strings.HasPrefix(text, "At minute") { text += " of every hour" }
		case hs > 0: text += fmt.Sprintf(", every %d hours", hs)
		case last-first+1 == len(hour.values): text += fmt.Sprintf(", between %02d:00 and %02d:59", first, last)
		default: text += ", during hours " + hour.valueList(1, false)
		}
	}
	dFull, wFull := len(dom.values) == 31, len(dow.values) == 7
	if c.orRule() {
		if !dFull && !wFull { text += ", on " + dom.dayPhrase(false, false) + " or on " + dow.dayPhrase(true, false) }
	} else if !dFull && !wFull { text += ", on " + dom.dayPhrase(false, false) + " if it is " + dow.dayPhrase(true, true) } else if !dFull {
		text += ", on " + dom.dayPhrase(false, false)
	} else if !wFull { text += ", on " + dow.dayPhrase(true, false) }
	if len(month.values) != 12 { text += ", in " + month.valueList(3, false) }
	return text
}

type Policy int

const (
	Allow Policy = iota
	Forbid
	Replace
)

func (p Policy) String() string { return [...]string{"ALLOW", "FORBID", "REPLACE"}[p] }

type Job struct {
	id string
	cron *Cron
	enabled bool
	duration int
	policy Policy
}
type Scheduler struct {
	jobs map[string]*Job
	holidays map[int]bool
}

func (s *Scheduler) job(id string) (*Job, error) {
	job := s.jobs[id]
	if job == nil { return nil, errors.New("unknown job") }
	return job, nil
}
func (s *Scheduler) newID(id string) error {
	if len(id) < 1 || len(id) > 16 || id[0] < 'a' || id[0] > 'z' { return errors.New("invalid id") }
	for _, c := range id {
		if !(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') && c != '_' { return errors.New("invalid id") }
	}
	if s.jobs[id] != nil { return errors.New("duplicate job") }
	return nil
}
func (s *Scheduler) ordered(enabledOnly bool) []*Job {
	var result []*Job
	for _, job := range s.jobs { if !enabledOnly || job.enabled { result = append(result, job) } }
	slices.SortFunc(result, func(a, b *Job) int { return strings.Compare(a.id, b.id) })
	return result
}
func (s *Scheduler) timeline(low, high int, conflicts bool) []string {
	jobs := s.ordered(true)
	masks := make([]uint64, high-low+1)
	for i, job := range jobs {
		for _, time := range job.cron.fires(low, high, s.holidays, false, 0) { masks[time-low] |= uint64(1) << i }
	}
	total, peak := 0, 0
	for _, mask := range masks {
		count := bits.OnesCount64(mask)
		if !conflicts { total += count } else if count >= 2 { total++; peak = max(peak, count) }
	}
	rows := []string{fmt.Sprintf("TIMELINE %d", total)}
	if conflicts { rows[0] = fmt.Sprintf("CONFLICTS %d peak %d", total, peak) }
	for offset, mask := range masks {
		if len(rows) == 101 { break }
		if conflicts {
			if bits.OnesCount64(mask) < 2 { continue }
			var ids []string
			for i, job := range jobs { if mask&(uint64(1)<<i) != 0 { ids = append(ids, job.id) } }
			rows = append(rows, fmt.Sprintf("%s %d %s", datetimeText(low+offset), len(ids), strings.Join(ids, " ")))
		} else {
			for i, job := range jobs {
				if len(rows) == 101 { break }
				if mask&(uint64(1)<<i) != 0 { rows = append(rows, datetimeText(low+offset)+" "+job.id) }
			}
		}
	}
	if total > 100 { rows = append(rows, fmt.Sprintf("... %d more", total-100)) }
	return rows
}
func (s *Scheduler) simulate(low, high int) []string {
	jobs := s.ordered(true)
	events := make([]int, high-low+1441)
	var rows []string
	for _, job := range jobs {
		started, skipped, replaced, busy, lastEnd := 0, 0, 0, 0, -1
		for _, time := range job.cron.fires(low, high, s.holidays, false, 0) {
			if lastEnd > time && job.policy == Forbid { skipped++; continue }
			if lastEnd > time && job.policy == Replace {
				events[lastEnd-low]++; events[time-low]--
				busy -= lastEnd - time; replaced++
			}
			lastEnd = time + job.duration
			events[time-low]++; events[lastEnd-low]--
			started++; busy += job.duration
		}
		rows = append(rows, fmt.Sprintf("%s %s started %d skipped %d replaced %d busy %d", job.id, job.policy, started, skipped, replaced, busy))
	}
	running, peak, at := 0, 0, 0
	for i, change := range events {
		running += change
		if running > peak { peak, at = running, low+i }
	}
	header := fmt.Sprintf("SIMULATE %d peak %d", len(jobs), peak)
	if peak > 0 { header += " at " + datetimeText(at) }
	return append([]string{header}, rows...)
}

var arity = map[string]int{
	"JOB": -3, "VALIDATE": -2, "REMOVE": 2, "RENAME": 3, "ENABLE": 2, "DISABLE": 2,
	"RUNTIME": 4, "LIST": 1, "EXPAND": 3, "DESCRIBE": 2, "MATCH": 4, "NEXT": 5,
	"PREV": 5, "COUNT": 6, "GAP": 4, "OVERLAP": 7, "TIMELINE": 5, "CONFLICTS": 5,
	"WEEK": 2, "CALENDAR": 3, "SIMULATE": 5, "EXCLUDE": 2, "INCLUDE": 2, "HOLIDAYS": 1,
}

func (s *Scheduler) execute(words []string) ([]string, error) {
	command := words[0]
	expected, known := arity[command]
	if !known { return nil, errors.New("unknown command") }
	if expected < 0 && len(words) < -expected || expected >= 0 && len(words) != expected {
		return nil, errors.New("wrong arguments")
	}
	var job *Job
	var err error
	switch command {
	case "REMOVE", "RENAME", "ENABLE", "DISABLE", "RUNTIME", "EXPAND", "DESCRIBE", "MATCH", "NEXT", "PREV", "COUNT", "GAP", "OVERLAP", "CALENDAR":
		job, err = s.job(words[1])
		if err != nil { return nil, err }
	}
	switch command {
	case "JOB":
		if err := s.newID(words[1]); err != nil { return nil, err }
		cron, err := parseCron(words[2:])
		if err != nil { return nil, err }
		s.jobs[words[1]] = &Job{id: words[1], cron: cron, enabled: true, duration: 1, policy: Allow}
		return []string{"JOB " + words[1] + " added"}, nil
	case "VALIDATE":
		cron, err := parseCron(words[1:])
		if err != nil { return nil, err }
		rule := "AND"
		if cron.orRule() { rule = "OR" }
		return []string{fmt.Sprintf("VALID %s %s %d", cron.expanded, rule, len(cron.daily))}, nil
	case "REMOVE":
		delete(s.jobs, job.id)
		return []string{"REMOVE " + job.id}, nil
	case "RENAME":
		if err := s.newID(words[2]); err != nil { return nil, err }
		delete(s.jobs, job.id)
		job.id = words[2]
		s.jobs[job.id] = job
		return []string{"RENAME " + words[1] + " " + words[2]}, nil
	case "ENABLE", "DISABLE":
		enabled := command == "ENABLE"
		if job.enabled == enabled {
			if enabled { return nil, errors.New("already enabled") }
			return nil, errors.New("already disabled")
		}
		job.enabled = enabled
		return []string{command + " " + job.id}, nil
	case "RUNTIME":
		duration, err := positive(words[2], 4, 1440, "invalid duration")
		if err != nil { return nil, err }
		var policy Policy
		switch words[3] {
		case "ALLOW": policy = Allow
		case "FORBID": policy = Forbid
		case "REPLACE": policy = Replace
		default: return nil, errors.New("invalid policy")
		}
		job.duration, job.policy = duration, policy
		return []string{fmt.Sprintf("RUNTIME %s %d %s", job.id, duration, policy)}, nil
	case "LIST":
		rows := []string{fmt.Sprintf("LIST %d", len(s.jobs))}
		for _, job := range s.ordered(false) {
			status := "off"
			if job.enabled { status = "on" }
			rows = append(rows, fmt.Sprintf("%s %s %d %s %s", job.id, status, job.duration, job.policy, job.cron.text))
		}
		return rows, nil
	case "EXPAND":
		index := slices.Index(fieldNames[:], words[2])
		if index < 0 { return nil, errors.New("invalid field") }
		field := job.cron.fields[index]
		parts := []string{fmt.Sprintf("EXPAND %s %s %d", job.id, words[2], len(field.values))}
		for _, value := range field.values { parts = append(parts, strconv.Itoa(value)) }
		for _, special := range field.specials { parts = append(parts, special.String()) }
		return []string{strings.Join(parts, " ")}, nil
	case "DESCRIBE":
		return []string{"DESCRIBE " + job.id + " " + job.cron.description()}, nil
	case "MATCH":
		time, err := readDatetime(words, 2)
		if err != nil { return nil, err }
		date := dateFromNumber(time / 1440)
		dom, dow, condition := job.cron.matchDay(date)
		var reasons []string
		if !job.cron.fields[0].contains(time % 60) { reasons = append(reasons, "minute") }
		if !job.cron.fields[1].contains(time % 1440 / 60) { reasons = append(reasons, "hour") }
		if !condition && !dom { reasons = append(reasons, "day-of-month") }
		if !job.cron.fields[3].contains(date.month) { reasons = append(reasons, "month") }
		if !condition && !dow { reasons = append(reasons, "day-of-week") }
		if s.holidays[time/1440] { reasons = append(reasons, "excluded") }
		result := "yes"
		if len(reasons) != 0 { result = "no " + strings.Join(reasons, " ") }
		return []string{fmt.Sprintf("MATCH %s %s %s", job.id, datetimeText(time), result)}, nil
	case "NEXT", "PREV":
		base, err := readDatetime(words, 2)
		if err != nil { return nil, err }
		limit, err := positive(words[4], 2, 50, "invalid count")
		if err != nil { return nil, err }
		reverse := command == "PREV"
		low, high, sign := base+1, base+527040, "+"
		if reverse { low, high, sign = base-527040, base-1, "-" }
		times := job.cron.fires(low, high, s.holidays, reverse, limit)
		rows := []string{fmt.Sprintf("%s %s %d", command, job.id, len(times))}
		for _, time := range times {
			distance := time - base
			if reverse { distance = -distance }
			rows = append(rows, datetimeText(time)+" "+sign+span(distance))
		}
		if len(times) < limit { rows = append(rows, "NONE") }
		return rows, nil
	case "COUNT":
		low, high, err := readWindow(words, 2)
		if err != nil { return nil, err }
		times := job.cron.fires(low, high, s.holidays, false, 0)
		days, previous := 0, -1
		for _, time := range times {
			if time/1440 != previous { days++; previous = time / 1440 }
		}
		return []string{fmt.Sprintf("COUNT %s runs %d days %d", job.id, len(times), days)}, nil
	case "GAP":
		base, err := readDatetime(words, 2)
		if err != nil { return nil, err }
		times := job.cron.fires(base, base+44640, s.holidays, false, 0)
		if len(times) < 2 { return []string{fmt.Sprintf("GAP %s runs %d none", job.id, len(times))}, nil }
		histogram := make(map[int]int)
		shortest, longest, first := 44641, 0, 0
		for i := 0; i+1 < len(times); i++ {
			gap := times[i+1] - times[i]
			histogram[gap]++
			shortest = min(shortest, gap)
			if gap > longest { longest, first = gap, i }
		}
		rows := []string{fmt.Sprintf("GAP %s runs %d shortest %s longest %s from %s to %s", job.id, len(times), span(shortest), span(longest), datetimeText(times[first]), datetimeText(times[first+1]))}
		var gaps []int
		for gap := range histogram { gaps = append(gaps, gap) }
		slices.Sort(gaps)
		for _, gap := range gaps { rows = append(rows, fmt.Sprintf("%s %d", span(gap), histogram[gap])) }
		return rows, nil
	case "OVERLAP":
		second, err := s.job(words[2])
		if err != nil { return nil, err }
		low, high, err := readWindow(words, 3)
		if err != nil { return nil, err }
		a, b := job.cron.fires(low, high, s.holidays, false, 0), second.cron.fires(low, high, s.holidays, false, 0)
		count, first, last := 0, 0, 0
		for i, j := 0, 0; i < len(a) && j < len(b); {
			if a[i] < b[j] { i++ } else if a[i] > b[j] { j++ } else {
				if count == 0 { first = a[i] }
				last = a[i]; count++; i++; j++
			}
		}
		row := fmt.Sprintf("OVERLAP %s %s %d", job.id, second.id, count)
		if count > 0 { row += " first " + datetimeText(first) + " last " + datetimeText(last) }
		return []string{row}, nil
	case "TIMELINE", "CONFLICTS", "SIMULATE":
		low, high, err := readWindow(words, 1)
		if err != nil { return nil, err }
		if command == "SIMULATE" { return s.simulate(low, high), nil }
		return s.timeline(low, high, command == "CONFLICTS"), nil
	case "WEEK":
		date, err := readDate(words[1], "invalid date")
		if err != nil { return nil, err }
		var counts [7][24]int
		first := date.number()
		total := 0
		for _, job := range s.ordered(true) {
			for _, time := range job.cron.fires(first*1440, (first+7)*1440-1, s.holidays, false, 0) {
				counts[time/1440-first][time%1440/60]++
				total++
			}
		}
		rows := []string{fmt.Sprintf("WEEK %s %d", words[1], total)}
		for d, hours := range counts {
			var heat [24]byte
			dayTotal := 0
			for hour, count := range hours {
				dayTotal += count
				if count == 0 { heat[hour] = '.' } else if count >= 10 { heat[hour] = '+' } else { heat[hour] = byte('0' + count) }
			}
			rows = append(rows, fmt.Sprintf("%s %s %d", dateFromNumber(first+d), string(heat[:]), dayTotal))
		}
		return rows, nil
	case "CALENDAR":
		first, err := readMonth(words[2])
		if err != nil { return nil, err }
		var cells []string
		for range first.weekday() { cells = append(cells, "...") }
		days := 0
		for d := 1; d <= monthLength(first.year, first.month); d++ {
			date := Date{first.year, first.month, d}
			mark := '-'
			if job.cron.scheduled(date) {
				if s.holidays[date.number()] { mark = 'x' } else { mark = '*'; days++ }
			}
			cells = append(cells, fmt.Sprintf("%02d%c", d, mark))
		}
		for len(cells)%7 != 0 { cells = append(cells, "...") }
		rows := []string{fmt.Sprintf("CALENDAR %s %s days %d runs %d", job.id, words[2], days, days*len(job.cron.daily)), "Sun Mon Tue Wed Thu Fri Sat"}
		for i := 0; i < len(cells); i += 7 { rows = append(rows, strings.Join(cells[i:i+7], " ")) }
		return rows, nil
	case "EXCLUDE", "INCLUDE":
		date, err := readDate(words[1], "invalid date")
		if err != nil { return nil, err }
		day := date.number()
		if command == "EXCLUDE" {
			if s.holidays[day] { return nil, errors.New("already excluded") }
			s.holidays[day] = true
		} else {
			if !s.holidays[day] { return nil, errors.New("not excluded") }
			delete(s.holidays, day)
		}
		return []string{fmt.Sprintf("%s %s holidays %d", command, date, len(s.holidays))}, nil
	case "HOLIDAYS":
		var dates []int
		for day := range s.holidays { dates = append(dates, day) }
		slices.Sort(dates)
		rows := []string{fmt.Sprintf("HOLIDAYS %d", len(dates))}
		for _, day := range dates { rows = append(rows, dateFromNumber(day).String()) }
		return rows, nil
	}
	panic("unreachable command")
}

func main() {
	input := bufio.NewScanner(os.Stdin)
	if !input.Scan() { return }
	count := integer(input.Text())
	scheduler := Scheduler{jobs: make(map[string]*Job), holidays: make(map[int]bool)}
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	for range count {
		input.Scan()
		rows, err := scheduler.execute(strings.Fields(input.Text()))
		if err != nil { fmt.Fprintln(output, "ERROR", err) } else {
			for _, row := range rows { fmt.Fprintln(output, row) }
		}
	}
}
