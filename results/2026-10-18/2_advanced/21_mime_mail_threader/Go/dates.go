package main

import (
	"fmt"
	"strconv"
	"strings"
)

var weekdays = []string{"mon", "tue", "wed", "thu", "fri", "sat", "sun"}
var months = []string{"jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"}
var namedZones = map[string]int{"ut": 0, "gmt": 0, "z": 0, "est": -300, "edt": -240, "cst": -360, "cdt": -300, "mst": -420, "mdt": -360, "pst": -480, "pdt": -420}

func leap(year int) bool { return year%4 == 0 && year%100 != 0 || year%400 == 0 }
func monthDays(year, month int) int {
	days := []int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	if month == 2 && leap(year) {
		return 29
	}
	return days[month-1]
}
func yearDays(year int) int {
	if leap(year) {
		return 366
	}
	return 365
}
func stringIndex(values []string, value string) int {
	for i, text := range values {
		if text == value {
			return i
		}
	}
	return -1
}
func digits(text string, lengths ...int) bool {
	valid := false
	for _, length := range lengths {
		if len(text) == length {
			valid = true
		}
	}
	if !valid {
		return false
	}
	for i := 0; i < len(text); i++ {
		if text[i] < '0' || text[i] > '9' {
			return false
		}
	}
	return true
}
func decimal(text string) int { value, _ := strconv.Atoi(text); return value }
func parseDate(value string) (int64, string) {
	text, ok := removeComments(value)
	if !ok {
		return 0, "bad Date syntax"
	}
	tokens := splitWords(strings.ReplaceAll(text, ",", " , "))
	weekday := -1
	if len(tokens) >= 3 && tokens[1] == "," {
		weekday = stringIndex(weekdays, strings.ToLower(tokens[0]))
		if weekday >= 0 {
			tokens = tokens[2:]
		}
	}
	if len(tokens) != 5 {
		return 0, "bad Date syntax"
	}
	pieces := strings.Split(tokens[3], ":")
	month := stringIndex(months, strings.ToLower(tokens[1])) + 1
	zone := tokens[4]
	numericZone := len(zone) == 5 && (zone[0] == '+' || zone[0] == '-') && digits(zone[1:], 4)
	offset, named := namedZones[strings.ToLower(zone)]
	if !digits(tokens[0], 1, 2) || month == 0 || !digits(tokens[2], 2, 4) || len(pieces) < 2 || len(pieces) > 3 || !(numericZone || named) {
		return 0, "bad Date syntax"
	}
	for _, piece := range pieces {
		if !digits(piece, 2) {
			return 0, "bad Date syntax"
		}
	}
	day, year := decimal(tokens[0]), decimal(tokens[2])
	if len(tokens[2]) == 2 {
		if year < 50 {
			year += 2000
		} else {
			year += 1900
		}
	}
	hour, minute, second := decimal(pieces[0]), decimal(pieces[1]), 0
	if len(pieces) == 3 {
		second = decimal(pieces[2])
	}
	if numericZone {
		hh, mm := decimal(zone[1:3]), decimal(zone[3:5])
		if hh > 23 || mm > 59 {
			return 0, "Date out of range"
		}
		offset = hh*60 + mm
		if zone[0] == '-' {
			offset = -offset
		}
	}
	if year < 1970 || year > 2099 || day < 1 || day > monthDays(year, month) || hour > 23 || minute > 59 || second > 59 {
		return 0, "Date out of range"
	}
	days := 0
	for current := 1970; current < year; current++ {
		days += yearDays(current)
	}
	for current := 1; current < month; current++ {
		days += monthDays(year, current)
	}
	days += day - 1
	seconds := int64(days)*86400 + int64(hour*3600+minute*60+second-offset*60)
	if seconds < 0 {
		return 0, "Date out of range"
	}
	if weekday >= 0 && (days+3)%7 != weekday {
		return 0, "Date weekday mismatch"
	}
	return seconds, ""
}
func formatUTC(seconds int64) string {
	days, rest := seconds/86400, seconds%86400
	year := 1970
	for days >= int64(yearDays(year)) {
		days -= int64(yearDays(year))
		year++
	}
	month := 1
	for days >= int64(monthDays(year, month)) {
		days -= int64(monthDays(year, month))
		month++
	}
	return fmt.Sprintf("%04d-%02d-%02d %02d:%02d:%02d", year, month, days+1, rest/3600, (rest%3600)/60, rest%60)
}
