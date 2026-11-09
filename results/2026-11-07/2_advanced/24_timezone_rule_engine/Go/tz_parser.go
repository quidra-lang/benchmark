package main

import (
	"errors"
	"strconv"
	"strings"
)

type Until struct {
	YearText, MonthText, DayText string
	Time                         int64
	Type                         string
	Value                        int64
}

func lineContent(raw string) string {
	if index := strings.IndexByte(raw, '#'); index >= 0 {
		raw = raw[:index]
	}
	return strings.TrimRight(raw, " ")
}
func isContinuation(content string) bool  { return strings.HasPrefix(content, " ") }
func splitFields(content string) []string { return strings.Fields(content) }
func isNumber(text string, low, high int) bool {
	if len(text) < low || len(text) > high {
		return false
	}
	for i := 0; i < len(text); i++ {
		if text[i] < '0' || text[i] > '9' {
			return false
		}
	}
	return true
}
func integer(text string) int { value, _ := strconv.Atoi(text); return value }
func hmsValue(text string, maxParts int) (int64, bool) {
	parts := strings.Split(text, ":")
	if len(parts) > maxParts || !isNumber(parts[0], 1, 2) {
		return 0, false
	}
	value := int64(integer(parts[0]) * 3600)
	units := []int{60, 1}
	for i, part := range parts[1:] {
		if !isNumber(part, 2, 2) || integer(part) > 59 {
			return 0, false
		}
		value += int64(integer(part) * units[i])
	}
	return value, true
}
func parseYear(text string) (int, error) {
	if !isNumber(text, 4, 4) || integer(text) < 1800 || integer(text) > 2099 {
		return 0, errors.New("bad year")
	}
	return integer(text), nil
}
func parseTo(text string, from int) (int, error) {
	if text == "only" {
		return from, nil
	}
	if text == "max" {
		return 2099, nil
	}
	if !isNumber(text, 4, 4) || integer(text) < from || integer(text) > 2099 {
		return 0, errors.New("bad year")
	}
	return integer(text), nil
}
func nameIndex(names []string, text string) int {
	for i, name := range names {
		if name == text {
			return i
		}
	}
	return -1
}
func parseMonth(text string) (int, error) {
	month := nameIndex(monthNames, text) + 1
	if month == 0 {
		return 0, errors.New("bad month")
	}
	return month, nil
}
func parseWeekday(text string) (int, error) {
	value := nameIndex(weekdayNames, text)
	if value < 0 {
		return 0, errors.New("bad day spec")
	}
	return value, nil
}
func parseDayOfMonth(text string, month int) (int, error) {
	if !isNumber(text, 1, 2) || text[0] == '0' || integer(text) > commonMonthDays[month-1] {
		return 0, errors.New("bad day spec")
	}
	return integer(text), nil
}
func parseDaySpec(text string, month int) (DaySpec, error) {
	if strings.HasPrefix(text, "last") {
		day, err := parseWeekday(text[4:])
		return DaySpec{Kind: "last", Weekday: day}, err
	}
	for i, operator := range []string{">=", "<="} {
		if position := strings.Index(text, operator); position >= 0 {
			day, err := parseWeekday(text[:position])
			if err != nil {
				return DaySpec{}, err
			}
			number, err := parseDayOfMonth(text[position+2:], month)
			return DaySpec{[]string{"after", "before"}[i], day, number}, err
		}
	}
	day, err := parseDayOfMonth(text, month)
	return DaySpec{Kind: "day", Day: day}, err
}
func parseTime(text string) (int64, string, error) {
	kind := "w"
	if len(text) > 0 && strings.ContainsRune("wsu", rune(text[len(text)-1])) {
		kind = text[len(text)-1:]
		text = text[:len(text)-1]
	}
	value, ok := hmsValue(text, 3)
	if !ok || value > 86400 {
		return 0, "", errors.New("bad time")
	}
	return value, kind, nil
}
func parseSave(text string) (int64, error) {
	value, ok := hmsValue(text, 2)
	if !ok || value > 7200 {
		return 0, errors.New("bad save")
	}
	return value, nil
}
func parseLetter(text string) (string, error) {
	if text == "-" {
		return "", nil
	}
	if len(text) == 0 || len(text) > 5 {
		return "", errors.New("bad letter")
	}
	for i := 0; i < len(text); i++ {
		if text[i] < 'A' || text[i] > 'Z' {
			return "", errors.New("bad letter")
		}
	}
	return text, nil
}
func parseOffset(text string) (int64, error) {
	sign := int64(1)
	if strings.HasPrefix(text, "-") {
		sign = -1
		text = text[1:]
	}
	value, ok := hmsValue(text, 3)
	if !ok || value >= 57600 {
		return 0, errors.New("bad offset")
	}
	return sign * value, nil
}
func checkFormat(text string, usesRules bool) error {
	placeholders, slashes := 0, 0
	for i := 0; i < len(text); i++ {
		c := text[i]
		if c == '%' {
			if i+1 >= len(text) || text[i+1] != 's' {
				return errors.New("bad format")
			}
			placeholders++
			i++
			continue
		}
		if c == '/' {
			slashes++
			continue
		}
		if !(c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '+' || c == '-') {
			return errors.New("bad format")
		}
	}
	if placeholders > 1 || slashes > 1 || placeholders > 0 && (slashes > 0 || !usesRules) || slashes == 1 && (strings.HasPrefix(text, "/") || strings.HasSuffix(text, "/")) {
		return errors.New("bad format")
	}
	return nil
}
func parseUntil(fields []string) (*Until, error) {
	year, err := parseYear(fields[0])
	if err != nil {
		return nil, err
	}
	monthText, dayText := "Jan", "1"
	if len(fields) > 1 {
		monthText = fields[1]
	}
	month, err := parseMonth(monthText)
	if err != nil {
		return nil, err
	}
	if len(fields) > 2 {
		dayText = fields[2]
	}
	day, err := parseDaySpec(dayText, month)
	if err != nil {
		return nil, err
	}
	value, kind := int64(0), "w"
	if len(fields) > 3 {
		value, kind, err = parseTime(fields[3])
		if err != nil {
			return nil, err
		}
	}
	return &Until{fields[0], monthText, dayText, value, kind, day.Value(year, month)*secondsPerDay + value}, nil
}
