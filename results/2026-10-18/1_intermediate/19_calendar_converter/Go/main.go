package main

import (
	"bufio"
	"cmp"
	"errors"
	"fmt"
	"os"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

type Calendar int

const (
	Gregorian Calendar = iota
	Julian
	ISO
	Islamic
	Hebrew
	Persian
	Coptic
	Ethiopic
	French
	Mayan
	JD
	Fixed
)

const maxFixed = 3652059

var calendarNames = strings.Fields("GREGORIAN JULIAN ISO ISLAMIC HEBREW PERSIAN COPTIC ETHIOPIC FRENCH MAYAN JD FIXED")
var weekdays = strings.Fields("Sunday Monday Tuesday Wednesday Thursday Friday Saturday")
var tzolkin = strings.Fields("Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau")
var haab = strings.Fields("Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb")
var decades = strings.Fields("Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi")
var festivals = strings.Fields("Vertu Genie Travail Opinion Recompenses Revolution")
var monthNames = map[Calendar][]string{
	Gregorian: strings.Fields("January February March April May June July August September October November December"),
	Julian:    strings.Fields("January February March April May June July August September October November December"),
	Islamic:   strings.Fields("Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah"),
	Hebrew:    strings.Fields("Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul"),
	Persian:   strings.Fields("Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand"),
	Coptic:    strings.Fields("Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie"),
	Ethiopic:  strings.Fields("Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume"),
	French:    strings.Fields("Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides"),
}
var hebrewLeapNames = strings.Fields("Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul")
var islamicLeapYears = []int64{2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29}

var (
	yearPattern     = regexp.MustCompile(`^[0-9]{1,5}$`)
	twoDigitPattern = regexp.MustCompile(`^[0-9]{1,2}$`)
	amountPattern   = regexp.MustCompile(`^-?[0-9]{1,7}$`)
	ymdPattern      = regexp.MustCompile(`^([0-9]{1,5})-([0-9]{1,2})-([0-9]{1,2})$`)
	isoPattern      = regexp.MustCompile(`^([0-9]{1,5})-W([0-9]{1,2})-([0-9])$`)
	mayanPattern    = regexp.MustCompile(`^([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,2})$`)
	integerPattern  = regexp.MustCompile(`^-?[0-9]{1,8}$`)
)

type dateError string

func (e dateError) Error() string { return string(e) }

var errCommand = errors.New("invalid command")

type holiday struct {
	name     string
	calendar Calendar
	month    string
	day      int
}

type entry struct {
	fixed    int64
	order    int
	name     string
	calendar Calendar
}

type newYear struct {
	year, fixed int64
}

func number(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func floorDiv(a, b int64) int64 {
	quotient := a / b
	if a%b < 0 {
		quotient--
	}
	return quotient
}

func mod(a, n int64) int64 {
	remainder := a % n
	if remainder < 0 {
		remainder += n
	}
	return remainder
}

func inRange(fixed int64) bool { return 1 <= fixed && fixed <= maxFixed }

func isYMD(calendar Calendar) bool {
	return calendar != ISO && calendar != Mayan && calendar != JD && calendar != Fixed
}

func hasYears(calendar Calendar) bool { return isYMD(calendar) || calendar == ISO }

func calendarOf(name string) Calendar { return Calendar(slices.Index(calendarNames, name)) }

func leap(calendar Calendar, year int64) bool {
	switch calendar {
	case Gregorian:
		return mod(year, 4) == 0 && (mod(year, 100) != 0 || mod(year, 400) == 0)
	case Julian:
		return mod(year, 4) == 0
	case Islamic:
		return slices.Contains(islamicLeapYears, mod(year, 30))
	case Hebrew:
		return mod(7*year+1, 19) < 7
	case Persian:
		b := mod(year-474, 2820) + 474
		return mod((b+38)*682, 2816) < 682
	case Coptic, Ethiopic:
		return mod(year, 4) == 3
	case French:
		century := mod(year, 400)
		return mod(year, 4) == 0 && century != 100 && century != 200 && century != 300 && mod(year, 4000) != 0
	}
	return (start(ISO, year+1)-start(ISO, year))/7 == 53
}

func monthsBefore(year int64) int64 { return floorDiv(235*year-234, 19) }

func molad(year int64) (day, parts, fixed int64, rules []string) {
	quantity := 5604 + 765433*monthsBefore(year)
	day, parts = floorDiv(quantity, 25920), mod(quantity, 25920)
	weekday := mod(day-1373427, 7)
	postponed := day
	switch {
	case parts >= 19440:
		postponed++
		rules = append(rules, "ZAKEN")
	case !leap(Hebrew, year) && weekday == 2 && parts >= 9924:
		postponed += 2
		rules = append(rules, "GATARAD")
	case leap(Hebrew, year-1) && weekday == 1 && parts >= 16789:
		postponed++
		rules = append(rules, "BETUTAKPAT")
	}
	if postponedWeekday := mod(postponed-1373427, 7); postponedWeekday == 0 || postponedWeekday == 3 || postponedWeekday == 5 {
		postponed++
		rules = append(rules, "ADU")
	}
	return day, parts, postponed - 1373427, rules
}

func start(calendar Calendar, year int64) int64 {
	previous := year - 1
	switch calendar {
	case Gregorian:
		return 365*previous + floorDiv(previous, 4) - floorDiv(previous, 100) + floorDiv(previous, 400) + 1
	case Julian:
		return 365*previous + floorDiv(previous, 4) - 1
	case Islamic:
		return 227015 + 354*previous + floorDiv(3+11*year, 30)
	case Hebrew:
		_, _, fixed, _ := molad(year)
		return fixed
	case Persian:
		a := year - 474
		b := mod(a, 2820) + 474
		return 226896 + 1029983*floorDiv(a, 2820) + 365*(b-1) + floorDiv(682*b-110, 2816)
	case Coptic:
		return 103605 + 365*previous + floorDiv(year, 4)
	case Ethiopic:
		return 2796 + 365*previous + floorDiv(year, 4)
	case French:
		return 654415 + 365*previous + floorDiv(previous, 4) - floorDiv(previous, 100) + floorDiv(previous, 400) - floorDiv(previous, 4000)
	}
	januaryFour := start(Gregorian, year) + 3
	return januaryFour - mod(januaryFour-1, 7)
}

func yearType(year int64) string {
	switch start(Hebrew, year+1) - start(Hebrew, year) {
	case 353, 383:
		return "DEFICIENT"
	case 354, 384:
		return "REGULAR"
	}
	return "COMPLETE"
}

func names(calendar Calendar, year int64) []string {
	if calendar == Hebrew && leap(calendar, year) {
		return hebrewLeapNames
	}
	return monthNames[calendar]
}

func lengths(calendar Calendar, year int64) []int {
	extra := 0
	if leap(calendar, year) {
		extra = 1
	}
	switch calendar {
	case Gregorian, Julian:
		return []int{31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	case Islamic:
		return []int{30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 + extra}
	case Persian:
		return []int{31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29 + extra}
	case Coptic, Ethiopic, French:
		return []int{30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 5 + extra}
	}
	kind := yearType(year)
	heshvan, kislev := 29, 30
	if kind == "COMPLETE" {
		heshvan = 30
	}
	if kind == "DEFICIENT" {
		kislev = 29
	}
	if extra == 1 {
		return []int{30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29}
	}
	return []int{30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29}
}

func fixedDate(calendar Calendar, year int64, month, day int) int64 {
	if calendar == ISO {
		return start(calendar, year) + int64(7*(month-1)+day-1)
	}
	fixed := start(calendar, year) + int64(day-1)
	for _, days := range lengths(calendar, year)[:month-1] {
		fixed += int64(days)
	}
	return fixed
}

func yearOf(calendar Calendar, fixed int64) int64 {
	if fixed < start(calendar, 1) {
		return 0
	}
	low, high := int64(1), int64(100000)
	for low+1 < high {
		middle := (low + high) / 2
		if start(calendar, middle) <= fixed {
			low = middle
		} else {
			high = middle
		}
	}
	return low
}

func partsOf(calendar Calendar, fixed int64) (year int64, month, day int, ok bool) {
	year = yearOf(calendar, fixed)
	if year == 0 {
		return 0, 0, 0, false
	}
	offset := fixed - start(calendar, year)
	if calendar == ISO {
		return year, int(offset/7) + 1, int(offset%7) + 1, true
	}
	for index, days := range lengths(calendar, year) {
		if offset < int64(days) {
			return year, index + 1, int(offset) + 1, true
		}
		offset -= int64(days)
	}
	panic("calendar year length")
}

func formatDate(calendar Calendar, fixed int64) string {
	if !inRange(fixed) {
		return "OUT OF RANGE"
	}
	if hasYears(calendar) {
		year, month, day, ok := partsOf(calendar, fixed)
		if !ok {
			return "OUT OF RANGE"
		}
		if calendar == ISO {
			return fmt.Sprintf("%04d-W%02d-%d", year, month, day)
		}
		return fmt.Sprintf("%04d-%02d-%02d", year, month, day)
	}
	switch calendar {
	case JD:
		return strconv.FormatInt(fixed+1721425, 10)
	case Fixed:
		return strconv.FormatInt(fixed, 10)
	}
	count := fixed + 1137142
	haabDay := (count + 348) % 365
	return fmt.Sprintf("%d.%d.%d.%d.%d %d %s %d %s", count/144000, count/7200%20, count/360%20, count/20%18, count%20,
		(count+3)%13+1, tzolkin[(count+19)%20], haabDay%20, haab[haabDay/20])
}

func parseDate(calendar Calendar, text string) (int64, error) {
	var fixed int64
	switch {
	case isYMD(calendar):
		match := ymdPattern.FindStringSubmatch(text)
		if match == nil {
			return 0, dateError("FORMAT")
		}
		year, month, day := int64(number(match[1])), number(match[2]), number(match[3])
		if year == 0 {
			return 0, dateError("YEAR")
		}
		days := lengths(calendar, year)
		if month < 1 || month > len(days) {
			return 0, dateError("MONTH")
		}
		if day < 1 || day > days[month-1] {
			return 0, dateError("DAY")
		}
		fixed = fixedDate(calendar, year, month, day)
	case calendar == ISO:
		match := isoPattern.FindStringSubmatch(text)
		if match == nil {
			return 0, dateError("FORMAT")
		}
		year, week, day := int64(number(match[1])), number(match[2]), number(match[3])
		if year == 0 {
			return 0, dateError("YEAR")
		}
		weeks := int((start(calendar, year+1) - start(calendar, year)) / 7)
		if week < 1 || week > weeks {
			return 0, dateError("WEEK")
		}
		if day < 1 || day > 7 {
			return 0, dateError("DAY")
		}
		fixed = fixedDate(calendar, year, week, day)
	case calendar == Mayan:
		match := mayanPattern.FindStringSubmatch(text)
		if match == nil {
			return 0, dateError("FORMAT")
		}
		b, k, t, u, n := int64(number(match[1])), int64(number(match[2])), int64(number(match[3])), int64(number(match[4])), int64(number(match[5]))
		if k > 19 || t > 19 || u > 17 || n > 19 {
			return 0, dateError("FIELD")
		}
		fixed = (((b*20+k)*20+t)*18+u)*20 + n - 1137142
	default:
		if !integerPattern.MatchString(text) {
			return 0, dateError("FORMAT")
		}
		fixed = int64(number(text))
		if calendar == JD {
			fixed -= 1721425
		}
	}
	if !inRange(fixed) {
		return 0, dateError("RANGE")
	}
	return fixed, nil
}

func monthIndex(calendar Calendar, year int64) int64 {
	if calendar == Hebrew {
		return monthsBefore(year)
	}
	count := int64(12)
	if calendar == Coptic || calendar == Ethiopic || calendar == French {
		count = 13
	}
	return count * (year - 1)
}

func shift(calendar Calendar, fixed, years, months int64) (int64, bool) {
	year, month, day, _ := partsOf(calendar, fixed)
	targetYear := year + years
	if calendar == ISO {
		if targetYear < 1 || targetYear > 99999 {
			return 0, false
		}
		weeks := int((start(calendar, targetYear+1) - start(calendar, targetYear)) / 7)
		return fixedDate(calendar, targetYear, min(month, weeks), day), true
	}
	if calendar == Hebrew {
		oldName := names(calendar, year)[month-1]
		newNames := names(calendar, targetYear)
		if !slices.Contains(newNames, oldName) {
			if oldName == "Adar" {
				oldName = "AdarII"
			} else {
				oldName = "Adar"
			}
		}
		month = slices.Index(newNames, oldName) + 1
	}
	absolute := monthIndex(calendar, targetYear) + int64(month-1) + months
	var finalYear int64
	if calendar == Hebrew {
		finalYear = floorDiv(19*absolute+234, 235)
		for monthIndex(calendar, finalYear) > absolute {
			finalYear--
		}
		for monthIndex(calendar, finalYear+1) <= absolute {
			finalYear++
		}
	} else {
		finalYear = floorDiv(absolute, int64(len(names(calendar, targetYear)))) + 1
	}
	if finalYear < 1 || finalYear > 99999 {
		return 0, false
	}
	finalMonth := int(absolute-monthIndex(calendar, finalYear)) + 1
	finalDay := min(day, lengths(calendar, finalYear)[finalMonth-1])
	return fixedDate(calendar, finalYear, finalMonth, finalDay), true
}

func monthBounds(calendar Calendar, year int64, month int) (int64, int64, error) {
	days := lengths(calendar, year)
	if month < 1 || month > len(days) {
		return 0, 0, dateError("MONTH")
	}
	first := fixedDate(calendar, year, month, 1)
	return first, first + int64(days[month-1]) - 1, nil
}

func newYears(calendar Calendar, first, last int64) []newYear {
	year := max(1, yearOf(calendar, first))
	for start(calendar, year) < first {
		year++
	}
	var result []newYear
	for ; start(calendar, year) <= last; year++ {
		result = append(result, newYear{year, start(calendar, year)})
	}
	return result
}

func easter(year int64, calendar Calendar) (epact int64, letters string, moon, sunday int64) {
	golden := year % 19
	if calendar == Gregorian {
		century := year/100 + 1
		epact = mod(14+11*golden-3*century/4+(5+8*century)/25, 30)
		if epact == 0 || (epact == 1 && golden > 10) {
			epact++
		}
	} else {
		epact = (14 + 11*golden) % 30
	}
	moon = fixedDate(calendar, year, 4, 19) - epact
	sunday = moon + 7 - mod(moon, 7)
	const alphabet = "ABCDEFG"
	index := mod(-start(calendar, year), 7)
	letters = alphabet[index : index+1]
	if leap(calendar, year) {
		previous := mod(index-1, 7)
		letters += alphabet[previous : previous+1]
	}
	return epact, letters, moon, sunday
}

var holidays = []holiday{
	{"Christmas", Gregorian, "December", 25},
	{"OrthodoxChristmas", Julian, "December", 25},
	{"RoshHashanah", Hebrew, "Tishri", 1},
	{"YomKippur", Hebrew, "Tishri", 10},
	{"Sukkot", Hebrew, "Tishri", 15},
	{"Hanukkah", Hebrew, "Kislev", 25},
	{"Purim", Hebrew, "Adar", 14},
	{"Passover", Hebrew, "Nisan", 15},
	{"Shavuot", Hebrew, "Sivan", 6},
	{"IslamicNewYear", Islamic, "Muharram", 1},
	{"Ashura", Islamic, "Muharram", 10},
	{"Mawlid", Islamic, "RabiI", 12},
	{"RamadanStart", Islamic, "Ramadan", 1},
	{"EidAlFitr", Islamic, "Shawwal", 1},
	{"EidAlAdha", Islamic, "DhuAlHijjah", 10},
	{"Nowruz", Persian, "Farvardin", 1},
	{"SizdahBedar", Persian, "Farvardin", 13},
	{"Yalda", Persian, "Azar", 30},
	{"Nayrouz", Coptic, "Thout", 1},
	{"CopticChristmas", Coptic, "Koiak", 29},
	{"Enkutatash", Ethiopic, "Meskerem", 1},
	{"Meskel", Ethiopic, "Meskerem", 17},
	{"Timkat", Ethiopic, "Ter", 11},
	{"RepublicDay", French, "Vendemiaire", 1},
	{"RevolutionDay", French, "Sansculottides", 6},
}

func holidayLines(year int64) []string {
	first := start(Gregorian, year)
	last := start(Gregorian, year+1) - 1
	_, _, _, gregorianEaster := easter(year, Gregorian)
	_, _, _, orthodoxEaster := easter(year, Julian)
	movable := []struct {
		name   string
		offset int64
	}{
		{"AshWednesday", -46}, {"GoodFriday", -2}, {"Easter", 0}, {"Ascension", 39}, {"Pentecost", 49},
	}
	var entries []entry
	for order, feast := range movable {
		entries = append(entries, entry{gregorianEaster + feast.offset, order, feast.name, Gregorian})
	}
	entries = append(entries, entry{orthodoxEaster, 5, "OrthodoxEaster", Julian})
	for index, h := range holidays {
		for candidate := max(1, yearOf(h.calendar, first)); start(h.calendar, candidate) <= last; candidate++ {
			actualName := h.month
			if h.calendar == Hebrew && actualName == "Adar" && leap(h.calendar, candidate) {
				actualName = "AdarII"
			}
			month := slices.Index(names(h.calendar, candidate), actualName) + 1
			if h.day > lengths(h.calendar, candidate)[month-1] {
				continue
			}
			fixed := fixedDate(h.calendar, candidate, month, h.day)
			if first <= fixed && fixed <= last {
				entries = append(entries, entry{fixed, index + 6, h.name, h.calendar})
			}
		}
	}
	slices.SortFunc(entries, func(a, b entry) int {
		return cmp.Or(cmp.Compare(a.fixed, b.fixed), cmp.Compare(a.order, b.order))
	})
	lines := make([]string, 0, len(entries))
	for _, e := range entries {
		lines = append(lines, fmt.Sprintf("%s %s %s %s %s", formatDate(Gregorian, e.fixed), weekdays[e.fixed%7],
			e.name, calendarNames[e.calendar], formatDate(e.calendar, e.fixed)))
	}
	return lines
}

var arity = map[string]int{
	"CONVERT": 4, "ALL": 2, "VALID": 2, "WEEKDAY": 2, "INFO": 2,
	"LEAP": 2, "MONTHS": 2, "MONTHCAL": 3, "NTH": 5, "NEWYEAR": 2,
	"DIFF": 4, "COUNT": 4, "ADD": 4, "SPAN": 3, "EASTER": 2,
	"COMPUTUS": 2, "PASSOVER": 1, "HOLIDAYS": 1, "MOLAD": 1, "ROUND": 6,
}

func validYear(text string) bool { return yearPattern.MatchString(text) && number(text) >= 1 }

func validArguments(command string, args []string) bool {
	switch command {
	case "EASTER", "COMPUTUS":
		return validYear(args[0]) && (args[1] == "GREGORIAN" || args[1] == "JULIAN")
	case "PASSOVER", "HOLIDAYS", "MOLAD":
		return validYear(args[0])
	}
	if !slices.Contains(calendarNames, args[0]) {
		return false
	}
	calendar := calendarOf(args[0])
	switch command {
	case "INFO", "MONTHS", "MONTHCAL", "NTH", "SPAN":
		if !isYMD(calendar) {
			return false
		}
	case "LEAP", "NEWYEAR":
		if !hasYears(calendar) {
			return false
		}
	}
	switch command {
	case "CONVERT":
		return args[2] == "TO" && slices.Contains(calendarNames, args[3])
	case "DIFF":
		return slices.Contains(calendarNames, args[2])
	case "LEAP", "MONTHS", "NEWYEAR":
		return validYear(args[1])
	case "MONTHCAL":
		return validYear(args[1]) && twoDigitPattern.MatchString(args[2])
	case "NTH":
		return validYear(args[1]) && twoDigitPattern.MatchString(args[2]) &&
			slices.Contains([]string{"1", "2", "3", "4", "5", "LAST"}, args[3]) && slices.Contains(weekdays, args[4])
	case "COUNT":
		return slices.Contains(weekdays, args[3])
	case "ADD":
		if !amountPattern.MatchString(args[2]) || !slices.Contains([]string{"DAYS", "WEEKS", "MONTHS", "YEARS"}, args[3]) {
			return false
		}
		switch args[3] {
		case "MONTHS":
			return isYMD(calendar)
		case "YEARS":
			return hasYears(calendar)
		}
	case "ROUND":
		if !twoDigitPattern.MatchString(args[2]) || !twoDigitPattern.MatchString(args[4]) {
			return false
		}
		limit := 19
		if args[5] == "Uayeb" {
			limit = 4
		}
		value := number(args[2])
		return 1 <= value && value <= 13 && slices.Contains(tzolkin, args[3]) && slices.Contains(haab, args[5]) && number(args[4]) <= limit
	}
	return true
}

func calendarLines(calendar Calendar, year int64, month int) ([]string, error) {
	first, last, err := monthBounds(calendar, year, month)
	if err != nil {
		return nil, err
	}
	if !inRange(first) || !inRange(last) {
		return []string{"OUT OF RANGE"}, nil
	}
	lines := []string{
		fmt.Sprintf("%s %d (%s to %s)", names(calendar, year)[month-1], year, formatDate(Gregorian, first), formatDate(Gregorian, last)),
		"Mo Tu We Th Fr Sa Su",
	}
	for cursor := first - (first-1)%7; cursor <= last; cursor += 7 {
		fields := make([]string, 0, 7)
		for fixed := cursor; fixed < cursor+7; fixed++ {
			if first <= fixed && fixed <= last {
				fields = append(fields, fmt.Sprintf("%2d", fixed-first+1))
			} else {
				fields = append(fields, "  ")
			}
		}
		lines = append(lines, strings.TrimRight(strings.Join(fields, " "), " "))
	}
	return lines, nil
}

func spanText(calendar Calendar, first, last int64) string {
	negative := first > last
	if negative {
		first, last = last, first
	}
	startYear, _, _, _ := partsOf(calendar, first)
	endYear, _, _, _ := partsOf(calendar, last)
	low, high := int64(0), endYear-startYear+2
	for low+1 < high {
		middle := (low + high) / 2
		if shifted, ok := shift(calendar, first, middle, 0); ok && shifted <= last {
			low = middle
		} else {
			high = middle
		}
	}
	years := low
	low, high = 0, 32
	for low+1 < high {
		middle := (low + high) / 2
		if shifted, ok := shift(calendar, first, years, middle); ok && shifted <= last {
			low = middle
		} else {
			high = middle
		}
	}
	months := low
	shifted, _ := shift(calendar, first, years, months)
	sign := ""
	if negative {
		sign = "-"
	}
	return fmt.Sprintf("%s%dy %dm %dd", sign, years, months, last-shifted)
}

func roundDate(calendar Calendar, fixed, tzNumber int64, tzName string, day int64, month string) string {
	targetTz := int64(slices.Index(tzolkin, tzName))
	targetHaab := int64(slices.Index(haab, month))*20 + day
	candidate := fixed
	for {
		count := candidate + 1137142
		if (count+3)%13+1 == tzNumber && (count+19)%20 == targetTz {
			break
		}
		candidate++
	}
	for ; candidate <= fixed+18979; candidate += 260 {
		if (candidate+1137142+348)%365 == targetHaab {
			return formatDate(calendar, candidate)
		}
	}
	return "NONE"
}

func execute(command string, args []string) ([]string, error) {
	if !validArguments(command, args) {
		return nil, errCommand
	}
	switch command {
	case "EASTER", "COMPUTUS":
		year := int64(number(args[0]))
		if year > 9999 {
			return []string{"OUT OF RANGE"}, nil
		}
		kind := calendarOf(args[1])
		epact, letters, moon, sunday := easter(year, kind)
		if command == "EASTER" {
			return []string{formatDate(Gregorian, sunday)}, nil
		}
		return []string{fmt.Sprintf("golden=%d epact=%d letters=%s moon=%s easter=%s",
			year%19+1, epact, letters, formatDate(kind, moon), formatDate(kind, sunday))}, nil
	case "MOLAD":
		day, parts, fixed, rules := molad(int64(number(args[0])))
		if !inRange(fixed) {
			return []string{"OUT OF RANGE"}, nil
		}
		applied := "NONE"
		if len(rules) > 0 {
			applied = strings.Join(rules, "+")
		}
		return []string{fmt.Sprintf("%s %dh %dp %s %s %s", weekdays[mod(day-1373427, 7)], parts/1080, parts%1080,
			applied, weekdays[fixed%7], formatDate(Gregorian, fixed))}, nil
	case "PASSOVER", "HOLIDAYS":
		year := int64(number(args[0]))
		if year > 9999 {
			return []string{"OUT OF RANGE"}, nil
		}
		if command == "HOLIDAYS" {
			return holidayLines(year), nil
		}
		hebrewYear := year + 3760
		month := slices.Index(names(Hebrew, hebrewYear), "Nisan") + 1
		fixed := fixedDate(Hebrew, hebrewYear, month, 15)
		return []string{formatDate(Gregorian, fixed) + " " + weekdays[fixed%7]}, nil
	}
	calendar := calendarOf(args[0])
	switch command {
	case "LEAP":
		year := int64(number(args[1]))
		answer := "NO"
		if leap(calendar, year) {
			answer = "YES"
		}
		line := fmt.Sprintf("%s %d", answer, start(calendar, year+1)-start(calendar, year))
		if calendar == Hebrew {
			line += " " + yearType(year)
		}
		return []string{line}, nil
	case "MONTHS":
		year := int64(number(args[1]))
		monthList := names(calendar, year)
		var items []string
		for index, days := range lengths(calendar, year) {
			items = append(items, fmt.Sprintf("%s=%d", monthList[index], days))
		}
		return []string{strings.Join(items, " ")}, nil
	case "NEWYEAR":
		year := int64(number(args[1]))
		if year > 9999 {
			return []string{"OUT OF RANGE"}, nil
		}
		var items []string
		for _, found := range newYears(calendar, start(Gregorian, year), start(Gregorian, year+1)-1) {
			items = append(items, fmt.Sprintf("%d:%s", found.year, formatDate(Gregorian, found.fixed)))
		}
		if len(items) == 0 {
			return []string{"NONE"}, nil
		}
		return []string{strings.Join(items, " ")}, nil
	case "MONTHCAL":
		return calendarLines(calendar, int64(number(args[1])), number(args[2]))
	case "NTH":
		first, last, err := monthBounds(calendar, int64(number(args[1])), number(args[2]))
		if err != nil {
			return nil, err
		}
		weekday := int64(slices.Index(weekdays, args[4]))
		var fixed int64
		if args[3] == "LAST" {
			fixed = last - mod(last-weekday, 7)
		} else {
			fixed = first + mod(weekday-first, 7) + 7*int64(number(args[3])-1)
		}
		if fixed > last {
			return []string{"NONE"}, nil
		}
		return []string{formatDate(calendar, fixed)}, nil
	case "VALID":
		fixed, err := parseDate(calendar, args[1])
		if err != nil {
			return []string{"NO " + err.Error()}, nil
		}
		return []string{"YES " + formatDate(calendar, fixed)}, nil
	}
	first, err := parseDate(calendar, args[1])
	if err != nil {
		return nil, err
	}
	switch command {
	case "DIFF":
		last, err := parseDate(calendarOf(args[2]), args[3])
		if err != nil {
			return nil, err
		}
		return []string{strconv.FormatInt(last-first, 10)}, nil
	case "COUNT", "SPAN":
		last, err := parseDate(calendar, args[2])
		if err != nil {
			return nil, err
		}
		if command == "SPAN" {
			return []string{spanText(calendar, first, last)}, nil
		}
		low, high := min(first, last), max(first, last)
		occurrence := low + mod(int64(slices.Index(weekdays, args[3]))-low, 7)
		total := int64(0)
		if occurrence <= high {
			total = (high-occurrence)/7 + 1
		}
		return []string{strconv.FormatInt(total, 10)}, nil
	case "CONVERT":
		return []string{formatDate(calendarOf(args[3]), first)}, nil
	case "WEEKDAY":
		return []string{weekdays[first%7]}, nil
	case "ALL":
		lines := make([]string, 0, len(calendarNames))
		for index, name := range calendarNames {
			target := Calendar(index)
			text := formatDate(target, first)
			if isYMD(target) && text != "OUT OF RANGE" {
				year, month, _, _ := partsOf(target, first)
				text += " " + names(target, year)[month-1]
			}
			lines = append(lines, name+" "+text)
		}
		return lines, nil
	case "INFO":
		year, month, day, _ := partsOf(calendar, first)
		weekday := weekdays[first%7]
		if calendar == French {
			if month <= 12 {
				weekday = decades[(day-1)%10]
			} else {
				weekday = festivals[day-1]
			}
		}
		ordinal := first - start(calendar, year) + 1
		length := start(calendar, year+1) - start(calendar, year)
		return []string{fmt.Sprintf("%s %d %s %d day=%d/%d", weekday, day, names(calendar, year)[month-1], year, ordinal, length)}, nil
	case "ROUND":
		return []string{roundDate(calendar, first, int64(number(args[2])), args[3], int64(number(args[4])), args[5])}, nil
	}
	amount := int64(number(args[2]))
	var result int64
	ok := true
	switch args[3] {
	case "DAYS":
		result = first + amount
	case "WEEKS":
		result = first + 7*amount
	case "YEARS":
		result, ok = shift(calendar, first, amount, 0)
	default:
		result, ok = shift(calendar, first, 0, amount)
	}
	if !ok {
		return []string{"OUT OF RANGE"}, nil
	}
	return []string{formatDate(calendar, result)}, nil
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	scanner.Scan()
	count := number(scanner.Text())
	for i := 0; i < count && scanner.Scan(); i++ {
		words := strings.Split(scanner.Text(), " ")
		command, args := words[0], words[1:]
		if expected, known := arity[command]; !known || len(args) != expected {
			fmt.Fprintln(out, "INVALID COMMAND")
			continue
		}
		lines, err := execute(command, args)
		var reason dateError
		switch {
		case errors.As(err, &reason) && reason == "RANGE":
			lines = []string{"OUT OF RANGE"}
		case errors.As(err, &reason):
			lines = []string{"INVALID DATE"}
		case err != nil:
			lines = []string{"INVALID COMMAND"}
		}
		for _, line := range lines {
			fmt.Fprintln(out, line)
		}
	}
}
