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

var methods = []string{"GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"}
var reasons = []string{"fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency"}
var statusClasses = []string{"1xx", "2xx", "3xx", "4xx", "5xx"}
var filterKeys = []string{"METHOD", "STATUS", "IP", "PATH"}
var monthDays = []int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
var forms = map[string][]string{
	"SUMMARY": {}, "MALFORMED": {}, "STATUS": {}, "METHODS": {},
	"TOP": {"kind", "limit"}, "HOURLY": {}, "TIMELINE": {"minutes"},
	"BANDWIDTH": {}, "VISITORS": {}, "LATENCY": {"path"},
	"HISTOGRAM": {"width"}, "APDEX": {"threshold"}, "ERRORS": {},
	"SLOWEST": {"limit"}, "SESSIONS": {"ip", "minutes"},
	"BURST": {"length", "times"}, "PEAK": {"length"}, "GAPS": {"length"},
	"IP": {"ip"}, "RANGE": {"date", "time", "date", "time"},
	"FILTER": {"key", "value"}, "UNFILTER": {"subject"},
	"RESET": {}, "STATE": {},
}
var argumentRanges = map[string][2]int{
	"limit": {1, 100}, "minutes": {1, 1440}, "width": {1, 100000},
	"threshold": {1, 100000}, "length": {1, 86400}, "times": {1, 1000},
}
var argumentErrors = map[string]string{
	"limit": "invalid number", "minutes": "invalid number", "width": "invalid number",
	"threshold": "invalid number", "length": "invalid number", "times": "invalid number",
	"kind": "invalid kind", "path": "invalid path", "ip": "invalid ip",
	"date": "invalid timestamp", "time": "invalid timestamp",
	"key": "invalid key", "subject": "invalid key", "value": "invalid value",
}
var requireRecords = map[string]bool{
	"STATUS": true, "METHODS": true, "TOP": true, "HOURLY": true,
	"TIMELINE": true, "BANDWIDTH": true, "VISITORS": true,
	"HISTOGRAM": true, "APDEX": true, "ERRORS": true, "SLOWEST": true,
	"BURST": true, "PEAK": true, "GAPS": true,
}
var digitsPattern = regexp.MustCompile(`^[0-9]+$`)
var datePattern = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}$`)
var timePattern = regexp.MustCompile(`^[0-9]{2}:[0-9]{2}:[0-9]{2}$`)
var statusPattern = regexp.MustCompile(`^[0-9]{3}$`)
var hexPattern = regexp.MustCompile(`^[0-9a-f]+$`)
var hexDigitPattern = regexp.MustCompile(`[0-9]`)

func includes(a []string, s string) bool {
	for _, x := range a {
		if x == s {
			return true
		}
	}
	return false
}
func parse(s string) int { v, _ := strconv.Atoi(s); return v }
func canonical(s string, maxDigits int) bool {
	return len(s) > 0 && len(s) <= maxDigits && digitsPattern.MatchString(s) &&
		(len(s) == 1 || s[0] != '0')
}
func leapYear(y int) bool { return y%4 == 0 && (y%100 != 0 || y%400 == 0) }
func daysInYear(y int) int {
	if leapYear(y) {
		return 366
	}
	return 365
}
func daysInMonth(y, m int) int {
	if m == 2 && leapYear(y) {
		return 29
	}
	return monthDays[m-1]
}
func validDate(s string) bool {
	if !datePattern.MatchString(s) {
		return false
	}
	y, m, d := parse(s[:4]), parse(s[5:7]), parse(s[8:10])
	return y >= 2000 && y <= 2059 && m >= 1 && m <= 12 &&
		d >= 1 && d <= daysInMonth(y, m)
}
func validTime(s string) bool {
	if !timePattern.MatchString(s) {
		return false
	}
	return parse(s[:2]) < 24 && parse(s[3:5]) < 60 && parse(s[6:8]) < 60
}
func validIP(s string) bool {
	parts := strings.Split(s, ".")
	if len(parts) != 4 {
		return false
	}
	for _, p := range parts {
		if !canonical(p, 3) || parse(p) > 255 {
			return false
		}
	}
	return true
}
func validStatus(s string) bool {
	return statusPattern.MatchString(s) && parse(s) >= 100 && parse(s) <= 599
}
func validFilterValue(kind, value string) bool {
	switch kind {
	case "METHOD":
		return includes(methods, value)
	case "STATUS":
		return includes(statusClasses, value) || validStatus(value)
	case "IP":
		return validIP(value)
	default:
		return strings.HasPrefix(value, "/")
	}
}
func validArgument(kind, value string, args []string) bool {
	if pair, ok := argumentRanges[kind]; ok {
		return canonical(value, 6) && parse(value) >= pair[0] && parse(value) <= pair[1]
	}
	switch kind {
	case "kind":
		return value == "PATHS" || value == "IPS"
	case "path":
		return strings.HasPrefix(value, "/")
	case "ip":
		return validIP(value)
	case "date":
		return validDate(value)
	case "time":
		return validTime(value)
	case "key":
		return includes(filterKeys, value)
	case "subject":
		return value == "RANGE" || includes(filterKeys, value)
	default:
		return validFilterValue(args[0], value)
	}
}
func malformedReason(fields []string) string {
	if len(fields) != 8 {
		return "fields"
	}
	if !validDate(fields[0]) {
		return "date"
	}
	if !validTime(fields[1]) {
		return "time"
	}
	if !validIP(fields[2]) {
		return "ip"
	}
	if !includes(methods, fields[3]) {
		return "method"
	}
	if !strings.HasPrefix(fields[4], "/") {
		return "path"
	}
	if !validStatus(fields[5]) {
		return "status"
	}
	if !canonical(fields[6], 8) {
		return "bytes"
	}
	if !canonical(fields[7], 6) {
		return "latency"
	}
	return ""
}
func dayNumber(y, m, d int) int {
	days := d - 1
	for yy := 2000; yy < y; yy++ {
		days += daysInYear(yy)
	}
	for mm := 1; mm < m; mm++ {
		days += daysInMonth(y, mm)
	}
	return days
}
func secondsOf(date, clock string) int {
	y, m, d := parse(date[:4]), parse(date[5:7]), parse(date[8:10])
	return dayNumber(y, m, d)*86400 + parse(clock[:2])*3600 +
		parse(clock[3:5])*60 + parse(clock[6:8])
}
func intervalLabel(seconds int) string {
	days, rest, year := seconds/86400, seconds%86400, 2000
	for days >= daysInYear(year) {
		days -= daysInYear(year)
		year++
	}
	month := 1
	for days >= daysInMonth(year, month) {
		days -= daysInMonth(year, month)
		month++
	}
	return fmt.Sprintf("%d-%02d-%02d %02d:%02d", year, month, days+1, rest/3600, rest%3600/60)
}
func normalizePath(raw string) string {
	raw = strings.SplitN(raw, "?", 2)[0]
	parts := make([]string, 0)
	for _, item := range strings.Split(raw, "/") {
		if item == ".." {
			if len(parts) > 0 {
				parts = parts[:len(parts)-1]
			}
			continue
		}
		if item == "" || item == "." {
			continue
		}
		if digitsPattern.MatchString(item) {
			item = "{id}"
		} else if len(item) >= 8 && hexPattern.MatchString(item) && hexDigitPattern.MatchString(item) {
			item = "{hex}"
		}
		parts = append(parts, item)
	}
	return "/" + strings.Join(parts, "/")
}
func compareIP(a, b string) int {
	left, right := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < 4; i++ {
		diff := parse(left[i]) - parse(right[i])
		if diff != 0 {
			return diff
		}
	}
	return 0
}
func statusMatches(filter string, status int) bool {
	if includes(statusClasses, filter) {
		return status/100 == int(filter[0]-'0')
	}
	return status == parse(filter)
}
func decimal(numerator, denominator, places int) string {
	scale := 1
	for range places {
		scale *= 10
	}
	value := numerator * scale / denominator
	return fmt.Sprintf("%d.%0*d", value/scale, places, value%scale)
}
func percent(numerator, denominator int) string { return decimal(numerator*100, denominator, 2) + "%" }
func bar(count, maximum int) string             { return strings.Repeat("#", (count*30+maximum-1)/maximum) }
func bytesText(size int) string {
	for _, pair := range []struct {
		unit   int
		suffix string
	}{
		{1073741824, "GB"}, {1048576, "MB"}, {1024, "KB"},
	} {
		if size >= pair.unit {
			return decimal(size, pair.unit, 1) + pair.suffix
		}
	}
	return strconv.Itoa(size) + "B"
}
func sortedCounts(counts map[string]int, ip bool) []string {
	keys := make([]string, 0, len(counts))
	for k := range counts {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if counts[keys[i]] != counts[keys[j]] {
			return counts[keys[i]] > counts[keys[j]]
		}
		if ip {
			return compareIP(keys[i], keys[j]) < 0
		}
		return keys[i] < keys[j]
	})
	return keys
}
func bucketCounts(numbers []int) (int, []int, bool) {
	first, last := numbers[0], numbers[0]
	for _, n := range numbers {
		if n < first {
			first = n
		}
		if n > last {
			last = n
		}
	}
	if last-first+1 > 60 {
		return 0, nil, false
	}
	counts := make([]int, last-first+1)
	for _, n := range numbers {
		counts[n-first]++
	}
	return first, counts, true
}
func percentile(sorted []int, rank int) int { return sorted[(rank*len(sorted)+99)/100-1] }
func sumRecords(rows []Record, key string) int {
	total := 0
	for _, r := range rows {
		if key == "size" {
			total += r.Size
		} else {
			total += r.Latency
		}
	}
	return total
}
func grouped(rows []Record, key func(Record) string) map[string][]Record {
	groups := make(map[string][]Record)
	for _, r := range rows {
		k := key(r)
		groups[k] = append(groups[k], r)
	}
	return groups
}
func tallied(values []string) map[string]int {
	counts := make(map[string]int)
	for _, value := range values {
		counts[value]++
	}
	return counts
}
func countStatusClasses(rows []Record) [5]int {
	var counts [5]int
	for _, r := range rows {
		counts[r.Status/100-1]++
	}
	return counts
}
func uniqueCount(rows []Record, key func(Record) string) int { return len(grouped(rows, key)) }
func latestPeak(rows []Record, length int) Window {
	result := Window{}
	first := 0
	for last := range rows {
		for rows[last].Seconds-rows[first].Seconds >= length {
			first++
		}
		if last-first+1 > result.Size {
			result = Window{Size: last - first + 1, Start: rows[first], End: rows[last]}
		}
	}
	return result
}
func apdexScore(rows []Record, threshold int) Apdex {
	satisfied, tolerating := 0, 0
	for _, r := range rows {
		if r.Status < 500 && r.Latency <= threshold {
			satisfied++
		} else if r.Status < 500 && r.Latency > threshold && r.Latency <= 4*threshold {
			tolerating++
		}
	}
	points, total := 2*satisfied+tolerating, 2*len(rows)
	rating := "unacceptable"
	switch {
	case points*100 >= 94*total:
		rating = "excellent"
	case points*100 >= 85*total:
		rating = "good"
	case points*100 >= 70*total:
		rating = "fair"
	case points*100 >= 50*total:
		rating = "poor"
	}
	return Apdex{Count: len(rows), Satisfied: satisfied, Tolerating: tolerating,
		Frustrated: len(rows) - satisfied - tolerating, Points: points, Total: total,
		Notation: decimal(points, total, 3), Rating: rating}
}

type Record struct {
	Line, Hour, Seconds, Status, Size, Latency int
	Date, Timestamp, IP, Method, Path          string
}
type Malformed struct {
	Line   int
	Reason string
}
type Window struct {
	Size       int
	Start, End Record
}
type Apdex struct {
	Count, Satisfied, Tolerating, Frustrated, Points, Total int
	Notation, Rating                                        string
}
type TimeRange struct {
	Start, End               string
	StartSeconds, EndSeconds int
}
type Analyzer struct {
	Records    []Record
	Malformed  []Malformed
	LineCount  int
	Conditions map[string]string
	Range      *TimeRange
	Output     []string
}

func newAnalyzer(lines []string) *Analyzer {
	a := &Analyzer{LineCount: len(lines), Conditions: make(map[string]string)}
	for i, line := range lines {
		fields := strings.Fields(line)
		reason := malformedReason(fields)
		if reason != "" {
			a.Malformed = append(a.Malformed, Malformed{Line: i + 1, Reason: reason})
			continue
		}
		date, clock := fields[0], fields[1]
		a.Records = append(a.Records, Record{
			Line: i + 1, Hour: parse(clock[:2]), Seconds: secondsOf(date, clock),
			Status: parse(fields[5]), Size: parse(fields[6]), Latency: parse(fields[7]),
			Date: date, Timestamp: date + " " + clock, IP: fields[2], Method: fields[3],
			Path: normalizePath(fields[4]),
		})
	}
	sort.Slice(a.Records, func(i, j int) bool {
		x, y := a.Records[i], a.Records[j]
		if x.Seconds != y.Seconds {
			return x.Seconds < y.Seconds
		}
		return x.Line < y.Line
	})
	return a
}
func (a *Analyzer) emit(parts ...any) {
	words := make([]string, len(parts))
	for i, v := range parts {
		words[i] = fmt.Sprint(v)
	}
	a.Output = append(a.Output, strings.Join(words, " "))
}
func (a *Analyzer) selected() []Record {
	out := make([]Record, 0, len(a.Records))
	for _, r := range a.Records {
		if a.Range != nil && (r.Seconds < a.Range.StartSeconds || r.Seconds > a.Range.EndSeconds) {
			continue
		}
		if f := a.Conditions["METHOD"]; f != "" && f != r.Method {
			continue
		}
		if f := a.Conditions["STATUS"]; f != "" && !statusMatches(f, r.Status) {
			continue
		}
		if f := a.Conditions["IP"]; f != "" && f != r.IP {
			continue
		}
		if f := a.Conditions["PATH"]; f != "" && f != r.Path {
			continue
		}
		out = append(out, r)
	}
	return out
}
func (a *Analyzer) barLine(label string, count, maximum int) {
	if count > 0 {
		a.emit(label, count, bar(count, maximum))
	} else {
		a.emit(label, count)
	}
}
func (a *Analyzer) execute(line string) {
	tokens := strings.Fields(line)
	name := tokens[0]
	args := tokens[1:]
	form, ok := forms[name]
	if !ok {
		a.emit("ERROR", "unknown query")
		return
	}
	optional := (name == "LATENCY" || name == "SESSIONS") && len(args) == len(form)-1
	if len(args) != len(form) && !optional {
		a.emit("ERROR", "wrong arguments")
		return
	}
	for i, v := range args {
		if !validArgument(form[i], v, args) {
			a.emit("ERROR", argumentErrors[form[i]])
			return
		}
	}
	rows := a.selected()
	if requireRecords[name] && len(rows) == 0 {
		a.emit(name, "no records")
		return
	}
	if msg := a.run(name, args, rows); msg != "" {
		a.emit("ERROR", msg)
	}
}
func stringValues(rows []Record, f func(Record) string) []string {
	values := make([]string, len(rows))
	for i, r := range rows {
		values[i] = f(r)
	}
	return values
}
func sortedMapKeys[T any](group map[string]T) []string {
	keys := make([]string, 0, len(group))
	for k := range group {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func (a *Analyzer) run(name string, args []string, rows []Record) string {
	switch name {
	case "SUMMARY":
		a.emit("SUMMARY", "lines", a.LineCount, "valid", len(a.Records), "malformed", len(a.Malformed))
		a.emit("requests", len(rows), "bytes", sumRecords(rows, "size"),
			"ips", uniqueCount(rows, func(r Record) string { return r.IP }),
			"paths", uniqueCount(rows, func(r Record) string { return r.Path }))
		if len(rows) == 0 {
			a.emit("span", "none")
		} else {
			first, last := rows[0], rows[len(rows)-1]
			a.emit("span", first.Timestamp, last.Timestamp, last.Seconds-first.Seconds)
		}
	case "MALFORMED":
		a.emit("MALFORMED", len(a.Malformed))
		for _, reason := range reasons {
			lines := make([]any, 0)
			for _, row := range a.Malformed {
				if row.Reason == reason {
					lines = append(lines, row.Line)
				}
			}
			if len(lines) > 0 {
				a.emit(append([]any{reason, len(lines)}, lines...)...)
			}
		}
	case "STATUS":
		a.emit("STATUS", len(rows))
		classes := countStatusClasses(rows)
		for i, kind := range statusClasses {
			a.emit(kind, classes[i], percent(classes[i], len(rows)))
		}
		statuses := make(map[int]int)
		for _, r := range rows {
			statuses[r.Status]++
		}
		codes := make([]int, 0, len(statuses))
		for code := range statuses {
			codes = append(codes, code)
		}
		sort.Ints(codes)
		for _, code := range codes {
			a.emit(code, statuses[code], percent(statuses[code], len(rows)))
		}
	case "METHODS":
		counts := tallied(stringValues(rows, func(r Record) string { return r.Method }))
		a.emit("METHODS", len(rows))
		for _, method := range sortedCounts(counts, false) {
			a.emit(method, counts[method], percent(counts[method], len(rows)))
		}
	case "TOP":
		kind, limit := args[0], parse(args[1])
		ip := kind == "IPS"
		counts := tallied(stringValues(rows, func(r Record) string {
			if ip {
				return r.IP
			}
			return r.Path
		}))
		keys := sortedCounts(counts, ip)
		shown := min(limit, len(keys))
		a.emit("TOP", kind, shown, "of", len(keys))
		rank := 0
		for i, k := range keys[:shown] {
			if i == 0 || counts[k] != counts[keys[i-1]] {
				rank = i + 1
			}
			a.emit(rank, k, counts[k], percent(counts[k], len(rows)))
		}
	case "HOURLY":
		var counts [24]int
		for _, r := range rows {
			counts[r.Hour]++
		}
		top, peak := 0, 0
		for i, n := range counts {
			if n > top {
				top = n
				peak = i
			}
		}
		a.emit("HOURLY", len(rows), "peak", fmt.Sprintf("%02d", peak), top)
		for i, n := range counts {
			a.barLine(fmt.Sprintf("%02d", i), n, top)
		}
	case "TIMELINE":
		minutes := parse(args[0])
		width := minutes * 60
		values := make([]int, len(rows))
		for i, r := range rows {
			values[i] = r.Seconds / width
		}
		first, counts, ok := bucketCounts(values)
		if !ok {
			return "too many buckets"
		}
		top := 0
		for _, n := range counts {
			top = max(top, n)
		}
		a.emit("TIMELINE", minutes, len(counts))
		for i, n := range counts {
			a.barLine(intervalLabel((first+i)*width), n, top)
		}
	case "BANDWIDTH":
		days := grouped(rows, func(r Record) string { return r.Date })
		volume := sumRecords(rows, "size")
		a.emit("BANDWIDTH", len(days), volume, bytesText(volume))
		for _, date := range sortedMapKeys(days) {
			data := days[date]
			count := sumRecords(data, "size")
			a.emit(date, len(data), count, bytesText(count))
		}
	case "VISITORS":
		first := make(map[string]string)
		for _, r := range rows {
			if date, ok := first[r.IP]; !ok || r.Date < date {
				first[r.IP] = r.Date
			}
		}
		days := grouped(rows, func(r Record) string { return r.Date })
		a.emit("VISITORS", len(days), len(first))
		for _, date := range sortedMapKeys(days) {
			ips := make(map[string]bool)
			for _, r := range days[date] {
				ips[r.IP] = true
			}
			newcomers := 0
			for ip := range ips {
				if first[ip] == date {
					newcomers++
				}
			}
			a.emit(date, "unique", len(ips), "new", newcomers, "returning", len(ips)-newcomers)
		}
	case "LATENCY":
		label := "all"
		filtered := rows
		if len(args) > 0 {
			label = normalizePath(args[0])
			filtered = make([]Record, 0)
			for _, r := range rows {
				if r.Path == label {
					filtered = append(filtered, r)
				}
			}
		}
		if len(filtered) == 0 {
			a.emit("LATENCY", "no records")
			break
		}
		values := make([]int, len(filtered))
		for i, r := range filtered {
			values[i] = r.Latency
		}
		sort.Ints(values)
		n := len(values)
		trim := n / 10
		trimmed := values[trim : n-trim]
		total, trimmedTotal := 0, 0
		for _, v := range values {
			total += v
		}
		for _, v := range trimmed {
			trimmedTotal += v
		}
		a.emit("LATENCY", label, "count", n, "min", values[0],
			"p50", percentile(values, 50), "p90", percentile(values, 90),
			"p99", percentile(values, 99), "max", values[n-1],
			"mean", decimal(total, n, 2), "trimmed", decimal(trimmedTotal, len(trimmed), 2))
	case "HISTOGRAM":
		width := parse(args[0])
		values := make([]int, len(rows))
		for i, r := range rows {
			values[i] = r.Latency / width
		}
		first, counts, ok := bucketCounts(values)
		if !ok {
			return "too many buckets"
		}
		top := 0
		for _, n := range counts {
			top = max(top, n)
		}
		a.emit("HISTOGRAM", width, len(counts))
		for i, n := range counts {
			lo := (first + i) * width
			a.barLine(fmt.Sprintf("%d-%d", lo, lo+width-1), n, top)
		}
	case "APDEX":
		threshold := parse(args[0])
		overall := apdexScore(rows, threshold)
		a.emit("APDEX", threshold, overall.Notation, overall.Rating,
			"satisfied", overall.Satisfied, "tolerating", overall.Tolerating,
			"frustrated", overall.Frustrated)
		groupedPaths := grouped(rows, func(r Record) string { return r.Path })
		type scoreRow struct {
			Path  string
			Score Apdex
		}
		scores := make([]scoreRow, 0, len(groupedPaths))
		for path, items := range groupedPaths {
			scores = append(scores, scoreRow{path, apdexScore(items, threshold)})
		}
		sort.Slice(scores, func(i, j int) bool {
			x, y := scores[i], scores[j]
			left, right := x.Score.Points*y.Score.Total, y.Score.Points*x.Score.Total
			if left != right {
				return left < right
			}
			if x.Score.Count != y.Score.Count {
				return x.Score.Count > y.Score.Count
			}
			return x.Path < y.Path
		})
		for _, row := range scores {
			a.emit(row.Path, row.Score.Notation, row.Score.Rating, row.Score.Count)
		}
	case "ERRORS":
		failed := 0
		for _, r := range rows {
			if r.Status >= 400 {
				failed++
			}
		}
		a.emit("ERRORS", failed, "of", len(rows), percent(failed, len(rows)))
		groups := grouped(rows, func(r Record) string { return r.Path })
		type errorRow struct {
			Path                  string
			Count, Client, Server int
		}
		errors := make([]errorRow, 0)
		for path, items := range groups {
			item := errorRow{Path: path, Count: len(items)}
			for _, r := range items {
				if r.Status/100 == 4 {
					item.Client++
				}
				if r.Status/100 == 5 {
					item.Server++
				}
			}
			if item.Client+item.Server > 0 {
				errors = append(errors, item)
			}
		}
		sort.Slice(errors, func(i, j int) bool {
			x, y := errors[i], errors[j]
			xf, yf := x.Client+x.Server, y.Client+y.Server
			if xf*y.Count != yf*x.Count {
				return xf*y.Count > yf*x.Count
			}
			if xf != yf {
				return xf > yf
			}
			return x.Path < y.Path
		})
		for _, row := range errors {
			a.emit(row.Path, row.Count, row.Client, row.Server,
				percent(row.Client+row.Server, row.Count))
		}
	case "SLOWEST":
		groups := grouped(rows, func(r Record) string { return r.Method + "\x01" + r.Path })
		type slowRow struct {
			Method, Path          string
			Count, Total, Maximum int
		}
		slow := make([]slowRow, 0, len(groups))
		for key, items := range groups {
			pair := strings.Split(key, "\x01")
			current := slowRow{Method: pair[0], Path: pair[1], Count: len(items),
				Total: sumRecords(items, "latency")}
			for _, r := range items {
				current.Maximum = max(current.Maximum, r.Latency)
			}
			slow = append(slow, current)
		}
		sort.Slice(slow, func(i, j int) bool {
			x, y := slow[i], slow[j]
			if x.Total*y.Count != y.Total*x.Count {
				return x.Total*y.Count > y.Total*x.Count
			}
			if x.Maximum != y.Maximum {
				return x.Maximum > y.Maximum
			}
			if x.Path != y.Path {
				return x.Path < y.Path
			}
			return x.Method < y.Method
		})
		shown := min(parse(args[0]), len(slow))
		a.emit("SLOWEST", shown, "of", len(slow))
		for i, r := range slow[:shown] {
			a.emit(i+1, r.Method, r.Path, "count", r.Count,
				"avg", decimal(r.Total, r.Count, 2), "max", r.Maximum)
		}
	case "SESSIONS":
		ip := args[0]
		minutes := 30
		if len(args) > 1 {
			minutes = parse(args[1])
		}
		found := make([]Record, 0)
		for _, r := range rows {
			if r.IP == ip {
				found = append(found, r)
			}
		}
		if len(found) == 0 {
			a.emit("SESSIONS", "no records")
			break
		}
		sessions := [][]Record{{found[0]}}
		for i := 1; i < len(found); i++ {
			prev := found[i-1]
			current := found[i]
			if current.Seconds-prev.Seconds <= minutes*60 {
				last := len(sessions) - 1
				sessions[last] = append(sessions[last], current)
			} else {
				sessions = append(sessions, []Record{current})
			}
		}
		duration := 0
		for _, session := range sessions {
			duration += session[len(session)-1].Seconds - session[0].Seconds
		}
		a.emit("SESSIONS", ip, "timeout", minutes, "count", len(sessions),
			"requests", len(found), "avg_duration", decimal(duration, len(sessions), 1),
			"avg_requests", decimal(len(found), len(sessions), 1))
		for i, session := range sessions {
			start, end := session[0], session[len(session)-1]
			a.emit(i+1, start.Timestamp, end.Timestamp, end.Seconds-start.Seconds,
				len(session), uniqueCount(session, func(r Record) string { return r.Path }))
		}
	case "BURST":
		length, times := parse(args[0]), parse(args[1])
		failures := make([]Record, 0)
		for _, r := range rows {
			if r.Status >= 400 {
				failures = append(failures, r)
			}
		}
		ips := grouped(failures, func(r Record) string { return r.IP })
		type burstRow struct {
			IP     string
			Window Window
		}
		bursts := make([]burstRow, 0, len(ips))
		for ip, items := range ips {
			window := latestPeak(items, length)
			if window.Size >= times {
				bursts = append(bursts, burstRow{ip, window})
			}
		}
		sort.Slice(bursts, func(i, j int) bool {
			x, y := bursts[i], bursts[j]
			if x.Window.Size != y.Window.Size {
				return x.Window.Size > y.Window.Size
			}
			return compareIP(x.IP, y.IP) < 0
		})
		a.emit("BURST", length, times, len(bursts))
		for _, row := range bursts {
			a.emit(row.IP, row.Window.Size, row.Window.Start.Timestamp, row.Window.End.Timestamp)
		}
	case "PEAK":
		length := parse(args[0])
		window := latestPeak(rows, length)
		a.emit("PEAK", length, window.Size, window.Start.Timestamp, window.End.Timestamp)
	case "GAPS":
		length := parse(args[0])
		count := 0
		for i := 1; i < len(rows); i++ {
			if rows[i].Seconds-rows[i-1].Seconds >= length {
				count++
			}
		}
		a.emit("GAPS", length, count)
		for i := 1; i < len(rows); i++ {
			if rows[i].Seconds-rows[i-1].Seconds >= length {
				a.emit(rows[i-1].Timestamp, rows[i].Timestamp, rows[i].Seconds-rows[i-1].Seconds)
			}
		}
	case "IP":
		ip := args[0]
		found := make([]Record, 0)
		for _, r := range rows {
			if r.IP == ip {
				found = append(found, r)
			}
		}
		if len(found) == 0 {
			a.emit("IP", "no records")
			break
		}
		paths := tallied(stringValues(found, func(r Record) string { return r.Path }))
		errors := 0
		for _, r := range found {
			if r.Status >= 400 {
				errors++
			}
		}
		a.emit("IP", ip, "requests", len(found), "bytes", sumRecords(found, "size"),
			"errors", errors, "paths", len(paths))
		a.emit("first", found[0].Timestamp, "last", found[len(found)-1].Timestamp)
		methods := tallied(stringValues(found, func(r Record) string { return r.Method }))
		info := []any{"methods"}
		for _, method := range sortedCounts(methods, false) {
			info = append(info, method, methods[method])
		}
		a.emit(info...)
		classes := countStatusClasses(found)
		info = []any{"classes"}
		for i, c := range statusClasses {
			info = append(info, c, classes[i])
		}
		a.emit(info...)
		keys := sortedCounts(paths, false)
		for _, path := range keys[:min(3, len(keys))] {
			a.emit("path", path, paths[path])
		}
	case "RANGE":
		start, end := args[0]+" "+args[1], args[2]+" "+args[3]
		startSeconds, endSeconds := secondsOf(args[0], args[1]), secondsOf(args[2], args[3])
		if startSeconds > endSeconds {
			return "invalid range"
		}
		a.Range = &TimeRange{Start: start, End: end, StartSeconds: startSeconds, EndSeconds: endSeconds}
		a.emit("RANGE", start, end, "active", len(a.selected()))
	case "FILTER":
		key, value := args[0], args[1]
		if key == "PATH" {
			value = normalizePath(value)
		}
		a.Conditions[key] = value
		a.emit("FILTER", key, value, "active", len(a.selected()))
	case "UNFILTER":
		key := args[0]
		if key == "RANGE" {
			if a.Range == nil {
				return "not filtered"
			}
			a.Range = nil
		} else {
			if a.Conditions[key] == "" {
				return "not filtered"
			}
			delete(a.Conditions, key)
		}
		a.emit("UNFILTER", key, "active", len(a.selected()))
	case "RESET":
		a.Range = nil
		a.Conditions = make(map[string]string)
		a.emit("RESET", "active", len(a.selected()))
	case "STATE":
		timeRange := "-"
		if a.Range != nil {
			timeRange = a.Range.Start + " " + a.Range.End
		}
		info := []any{"STATE", "active", len(rows), "range", timeRange}
		for _, key := range filterKeys {
			value := a.Conditions[key]
			if value == "" {
				value = "-"
			}
			info = append(info, strings.ToLower(key), value)
		}
		a.emit(info...)
	}
	return ""
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 1024*1024)
	lines := make([]string, 0)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	separator := -1
	end := -1
	for i, line := range lines {
		if separator < 0 && line == "---" {
			separator = i
			continue
		}
		if separator >= 0 && line == "END" {
			end = i
			break
		}
	}
	analyzer := newAnalyzer(lines[:separator])
	for _, line := range lines[separator+1 : end] {
		analyzer.execute(line)
	}
	if len(analyzer.Output) > 0 {
		fmt.Println(strings.Join(analyzer.Output, "\n"))
	}
}
