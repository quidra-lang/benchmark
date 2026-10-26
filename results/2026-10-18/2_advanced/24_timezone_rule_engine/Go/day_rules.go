package main

const secondsPerDay int64 = 86400
const negInfinity int64 = -(1 << 60)
const posInfinity int64 = 1 << 60

var monthNames = []string{"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
var weekdayNames = []string{"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
var commonMonthDays = []int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

func floorDiv(a, b int64) int64 {
	q, r := a/b, a%b
	if r < 0 {
		q--
	}
	return q
}
func modulo(a, b int64) int64 { return a - b*floorDiv(a, b) }
func leap(year int) bool      { return year%4 == 0 && year%100 != 0 || year%400 == 0 }
func daysInMonth(year, month int) int {
	if month == 2 && leap(year) {
		return 29
	}
	return commonMonthDays[month-1]
}
func daysBeforeYear(year int) int64 {
	previous := int64(year - 1)
	return previous*365 + floorDiv(previous, 4) - floorDiv(previous, 100) + floorDiv(previous, 400)
}
func dayNumber(year, month, day int) int64 {
	days := daysBeforeYear(year) - daysBeforeYear(1970) + int64(day-1)
	for earlier := 1; earlier < month; earlier++ {
		days += int64(daysInMonth(year, earlier))
	}
	return days
}
func weekday(number int64) int { return int(modulo(number+4, 7)) }
func dateOfDay(number int64) (int, int, int) {
	year := 1970 + int(floorDiv(number, 366))
	for dayNumber(year, 1, 1) > number {
		year--
	}
	for dayNumber(year+1, 1, 1) <= number {
		year++
	}
	month := 1
	day := int(number - dayNumber(year, 1, 1) + 1)
	for day > daysInMonth(year, month) {
		day -= daysInMonth(year, month)
		month++
	}
	return year, month, day
}
func timeValue(year, month, day, hour, minute, second int) int64 {
	return dayNumber(year, month, day)*secondsPerDay + int64(hour*3600+minute*60+second)
}
func splitTime(value int64) (int, int, int, int, int, int) {
	year, month, day := dateOfDay(floorDiv(value, secondsPerDay))
	rest := modulo(value, secondsPerDay)
	return year, month, day, int(rest / 3600), int(rest / 60 % 60), int(rest % 60)
}

type DaySpec struct {
	Kind         string
	Weekday, Day int
}

func (d DaySpec) Value(year, month int) int64 {
	if d.Kind == "last" {
		last := dayNumber(year, month, daysInMonth(year, month))
		return last - modulo(int64(weekday(last)-d.Weekday), 7)
	}
	base := dayNumber(year, month, d.Day)
	if d.Kind == "after" {
		return base + modulo(int64(d.Weekday-weekday(base)), 7)
	}
	if d.Kind == "before" {
		return base - modulo(int64(weekday(base)-d.Weekday), 7)
	}
	return base
}
