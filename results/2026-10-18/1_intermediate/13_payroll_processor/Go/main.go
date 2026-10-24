package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var settingOrder = []string{
	"STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED",
	"UIRATE", "MATCH", "MATCHMAX", "GARNCAP",
	"SSBASE", "ADDBASE", "UIBASE", "RETIRECAP", "ALLOWANCE", "NIGHT",
}

var rateSettings = map[string]bool{
	"STATE": true, "SUPP": true, "SSRATE": true, "MEDRATE": true,
	"ADDMED": true, "UIRATE": true, "MATCH": true, "MATCHMAX": true,
	"GARNCAP": true,
}

var initialSettings = map[string]int{
	"STATE": 500, "SUPP": 2200, "SSRATE": 620, "MEDRATE": 145,
	"ADDMED": 90, "UIRATE": 270, "MATCH": 5000, "MATCHMAX": 600,
	"GARNCAP": 2500, "SSBASE": 16860000, "ADDBASE": 20000000,
	"UIBASE": 700000, "RETIRECAP": 2300000, "ALLOWANCE": 15000, "NIGHT": 100,
}

var fields = []string{
	"R", "O", "D", "N", "P", "accrued", "salary", "leave", "deduction",
	"sales", "commission", "earnings", "bonus", "gross", "retirement", "health",
	"federal", "supplemental", "state", "social", "medicare", "garnishment", "net",
	"employer_social", "employer_medicare", "unemployment", "match", "employer",
	"W", "Y", "F", "J",
}

var weekdays = []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}

func number(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func cents(text string) int {
	parts := strings.Split(text, ".")
	return number(parts[0])*100 + number(parts[1])
}

func money(value int) string {
	return fmt.Sprintf("%d.%02d", value/100, value%100)
}

func rateText(value int) string {
	return money(value) + "%"
}

func duration(value int) string {
	return fmt.Sprintf("%d:%02d", value/60, value%60)
}

func clock(value int) string {
	return fmt.Sprintf("%02d:%02d", value/60, value%60)
}

func weekday(day int) string {
	return weekdays[(day-1)%7]
}

func periodOf(day int) int {
	return (day-1)/14 + 1
}

func emptyTotals() map[string]int {
	values := make(map[string]int, len(fields))
	for _, field := range fields {
		values[field] = 0
	}
	return values
}

func sumStubs(stubs []map[string]int) map[string]int {
	result := emptyTotals()
	for _, stub := range stubs {
		for _, field := range fields {
			result[field] += stub[field]
		}
	}
	return result
}

func sortedKeys[V any](values map[int]V) []int {
	keys := make([]int, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Ints(keys)
	return keys
}

func sortedStrings[V any](values map[string]V) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func progressive(brackets map[int]int, amount int) int {
	limits := sortedKeys(brackets)
	numerator := 0
	for i, lower := range limits {
		if lower >= amount {
			break
		}
		upper := amount
		if i+1 < len(limits) {
			upper = limits[i+1]
		}
		if upper > amount {
			upper = amount
		}
		numerator += brackets[lower] * (upper - lower)
	}
	return numerator / 10000
}

type Shift struct {
	start int
	end   int
}

type Garnishment struct {
	rate    int
	balance int
}

type StubRecord struct {
	totals     map[string]int
	department string
}

type Employee struct {
	id           int
	department   string
	kind         string
	base         int
	active       bool
	retirement   int
	health       int
	allowances   int
	extra        int
	garnishments []Garnishment
	bonus        int
	ptoBalance   int
	shifts       map[int][]Shift
	pto          map[int]int
	leave        map[int]bool
	sales        map[int]int
	stubs        map[int]StubRecord
	ytd          map[string]int
	periods      int
}

func newEmployee(id int, department, kind string, base int) *Employee {
	return &Employee{
		id: id, department: department, kind: kind, base: base, active: true,
		shifts: make(map[int][]Shift), pto: make(map[int]int),
		leave: make(map[int]bool), sales: make(map[int]int),
		stubs: make(map[int]StubRecord), ytd: emptyTotals(),
	}
}

func (e *Employee) garnishmentBalance() int {
	sum := 0
	for _, order := range e.garnishments {
		sum += order.balance
	}
	return sum
}

type Payroll struct {
	settings  map[string]int
	brackets  map[int]int
	tiers     map[int]int
	holidays  map[int]bool
	employees map[int]*Employee
	closed    int
	output    []string
}

func newPayroll() *Payroll {
	settings := make(map[string]int, len(initialSettings))
	for key, value := range initialSettings {
		settings[key] = value
	}
	return &Payroll{
		settings: settings, brackets: make(map[int]int),
		tiers: make(map[int]int), holidays: make(map[int]bool),
		employees: make(map[int]*Employee),
	}
}

func (p *Payroll) emit(indent int, parts ...any) {
	strings_ := make([]string, len(parts))
	for i, part := range parts {
		strings_[i] = fmt.Sprint(part)
	}
	p.output = append(p.output, strings.Repeat(" ", indent)+strings.Join(strings_, " "))
}

func (p *Payroll) employee(text string, active bool, kind string) (*Employee, error) {
	employee := p.employees[number(text)]
	if employee == nil {
		return nil, fmt.Errorf("unknown employee %s", text)
	}
	if active && !employee.active {
		return nil, fmt.Errorf("terminated employee %s", text)
	}
	if kind != "" && employee.kind != kind {
		return nil, fmt.Errorf("not %s %s", strings.ToLower(kind), text)
	}
	return employee, nil
}

func (p *Payroll) dayCheck(text string) (int, error) {
	day := number(text)
	if day < 1 || day > 364 {
		return 0, fmt.Errorf("invalid day %s", text)
	}
	if period := periodOf(day); period <= p.closed {
		return 0, fmt.Errorf("period closed %d", period)
	}
	return day, nil
}

func periodCheck(text string) (int, error) {
	period := number(text)
	if period < 1 || period > 26 {
		return 0, fmt.Errorf("invalid period %s", text)
	}
	return period, nil
}

func rateCheck(text string) (int, error) {
	value := cents(text)
	if value > 10000 {
		return 0, fmt.Errorf("invalid rate %s", text)
	}
	return value, nil
}

func amountCheck(text string) (int, error) {
	value := cents(text)
	if value == 0 {
		return 0, fmt.Errorf("invalid amount")
	}
	return value, nil
}

func timeCheck(text string) (int, error) {
	parts := strings.Split(text, ":")
	hour, minute := number(parts[0]), number(parts[1])
	if hour > 23 || minute > 59 {
		return 0, fmt.Errorf("invalid time %s", text)
	}
	return hour*60 + minute, nil
}

type Hours [5]int

func (p *Payroll) daily(employee *Employee, day int) (int, Hours) {
	var values Hours
	worked := 0
	for _, shift := range employee.shifts[day] {
		worked += shift.end - shift.start
		nightEnd := shift.end
		if nightEnd > 360 {
			nightEnd = 360
		}
		if nightEnd > shift.start {
			values[3] += nightEnd - shift.start
		}
		nightStart := shift.start
		if nightStart < 1320 {
			nightStart = 1320
		}
		if shift.end > nightStart {
			values[3] += shift.end - nightStart
		}
	}
	values[4] = employee.pto[day]
	if day%7 == 0 || p.holidays[day] {
		values[2] = worked
	} else {
		values[0] = min(worked, 480)
		values[1] = min(max(worked-480, 0), 240)
		values[2] = max(worked-720, 0)
	}
	return worked, values
}

func (p *Payroll) weekly(employee *Employee, week int) (Hours, int) {
	var totals Hours
	for day := 7*week - 6; day <= 7*week; day++ {
		_, values := p.daily(employee, day)
		for i := range totals {
			totals[i] += values[i]
		}
	}
	weeklyOvertime := max(0, totals[0]-2400)
	totals[0] -= weeklyOvertime
	totals[1] += weeklyOvertime
	return totals, weeklyOvertime
}

func (p *Payroll) breakdown(employee *Employee, period int) Hours {
	first, _ := p.weekly(employee, 2*period-1)
	second, _ := p.weekly(employee, 2*period)
	for i := range first {
		first[i] += second[i]
	}
	return first
}

func (p *Payroll) calculate(employee *Employee, period int) (map[string]int, []int) {
	stub := emptyTotals()
	settings := p.settings
	ytd := employee.ytd
	switch employee.kind {
	case "HOURLY":
		values := p.breakdown(employee, period)
		for i, field := range []string{"R", "O", "D", "N", "P"} {
			stub[field] = values[i]
		}
		weighted := 2*(stub["R"]+stub["P"]) + 3*stub["O"] + 4*stub["D"]
		stub["earnings"] = (weighted*employee.base + 2*stub["N"]*settings["NIGHT"]) / 120
	case "SALARIED":
		if employee.active {
			stub["salary"] = employee.base / 26
			for day := range employee.leave {
				if periodOf(day) == period && !p.holidays[day] {
					stub["leave"]++
				}
			}
			stub["deduction"] = stub["leave"] * (employee.base / 260)
			stub["earnings"] = stub["salary"] - stub["deduction"]
		}
	case "COMMISSION":
		stub["sales"] = employee.sales[period]
		stub["commission"] = progressive(p.tiers, stub["sales"])
		stub["earnings"] = stub["commission"]
		if employee.active {
			stub["earnings"] += employee.base
		}
	}
	stub["bonus"] = employee.bonus
	gross := stub["earnings"] + stub["bonus"]
	if gross == 0 {
		return nil, nil
	}
	stub["gross"] = gross
	remaining := gross
	deduct := func(field string, amount int) {
		stub[field] = min(amount, remaining)
		remaining -= stub[field]
	}
	retirementRoom := max(0, settings["RETIRECAP"]-ytd["retirement"])
	deduct("retirement", min(gross*employee.retirement/10000, retirementRoom))
	deduct("health", employee.health)
	stub["W"] = remaining
	baseTaxable := max(0, stub["earnings"]-stub["retirement"]-stub["health"])
	allowanceTaxable := max(0, baseTaxable-employee.allowances*settings["ALLOWANCE"])
	deduct("federal", progressive(p.brackets, allowanceTaxable)+employee.extra)
	deduct("supplemental", (stub["W"]-baseTaxable)*settings["SUPP"]/10000)
	deduct("state", stub["W"]*settings["STATE"]/10000)

	medicareWages := gross - stub["health"]
	socialWages := min(medicareWages, max(0, settings["SSBASE"]-ytd["Y"]))
	additional := max(0, min(medicareWages, ytd["F"]+medicareWages-settings["ADDBASE"]))
	stub["F"], stub["Y"] = medicareWages, socialWages
	deduct("social", socialWages*settings["SSRATE"]/10000)
	deduct("medicare", medicareWages*settings["MEDRATE"]/10000+
		additional*settings["ADDMED"]/10000)
	disposable := remaining
	cap := disposable * settings["GARNCAP"] / 10000
	balances := make([]int, len(employee.garnishments))
	garnishment := 0
	for i, order := range employee.garnishments {
		taken := min(disposable*order.rate/10000, order.balance, cap-garnishment)
		garnishment += taken
		balances[i] = order.balance - taken
		stub["garnishment_balance"] += balances[i]
	}
	stub["garnishment"] = garnishment
	stub["net"] = remaining - garnishment
	stub["employer_social"] = socialWages * settings["SSRATE"] / 10000
	stub["employer_medicare"] = medicareWages * settings["MEDRATE"] / 10000
	stub["J"] = min(medicareWages, max(0, settings["UIBASE"]-ytd["J"]))
	stub["unemployment"] = stub["J"] * settings["UIRATE"] / 10000
	eligibleMatch := min(stub["retirement"], gross*settings["MATCHMAX"]/10000)
	stub["match"] = eligibleMatch * settings["MATCH"] / 10000
	stub["employer"] = stub["employer_social"] + stub["employer_medicare"] +
		stub["unemployment"] + stub["match"]
	if employee.kind == "HOURLY" {
		stub["accrued"] = min(960-employee.ptoBalance,
			(stub["R"]+stub["O"]+stub["D"])/20)
	}
	stub["pto_balance"] = employee.ptoBalance + stub["accrued"]
	return stub, balances
}

func hoursParts(values Hours) []any {
	parts := make([]any, 0, 10)
	for i, name := range []string{"reg", "ot", "dbl", "night", "pto"} {
		parts = append(parts, name, duration(values[i]))
	}
	return parts
}

func (p *Payroll) stubBlock(employee *Employee, stub map[string]int, indent int) {
	switch employee.kind {
	case "HOURLY":
		values := Hours{
			stub["R"], stub["O"], stub["D"], stub["N"], stub["P"],
		}
		p.emit(indent, append([]any{"hours"}, hoursParts(values)...)...)
		p.emit(indent, "pto", "accrued", duration(stub["accrued"]),
			"balance", duration(stub["pto_balance"]))
	case "SALARIED":
		p.emit(indent, "salary", money(stub["salary"]), "leave", stub["leave"],
			"deduction", money(stub["deduction"]))
	case "COMMISSION":
		p.emit(indent, "sales", money(stub["sales"]),
			"commission", money(stub["commission"]))
	}
	for _, field := range []string{
		"earnings", "bonus", "gross", "retirement", "health",
		"federal", "supplemental", "state", "social", "medicare",
	} {
		label := field
		if field == "social" {
			label = "social-security"
		}
		p.emit(indent, label, money(stub[field]))
	}
	p.emit(indent, "garnishment", money(stub["garnishment"]),
		"balance", money(stub["garnishment_balance"]))
	p.emit(indent, "net", money(stub["net"]))
	p.emit(indent, "employer", "social-security", money(stub["employer_social"]),
		"medicare", money(stub["employer_medicare"]),
		"unemployment", money(stub["unemployment"]), "match", money(stub["match"]))
}

func (p *Payroll) printStub(employee *Employee, period int, stub map[string]int, department string) {
	p.emit(2, "STUB", employee.id, department, employee.kind, "period", period)
	p.stubBlock(employee, stub, 4)
}

func (p *Payroll) showHours(employee *Employee, period int) {
	p.emit(0, "HOURS", employee.id, "period", period)
	found := false
	for day := 14*period - 13; day <= 14*period; day++ {
		shifts := append([]Shift(nil), employee.shifts[day]...)
		if len(shifts) == 0 && employee.pto[day] == 0 {
			continue
		}
		sort.Slice(shifts, func(i, j int) bool {
			return shifts[i].start < shifts[j].start
		})
		worked, values := p.daily(employee, day)
		parts := []any{"day", day, weekday(day)}
		if p.holidays[day] {
			parts = append(parts, "holiday")
		}
		for _, shift := range shifts {
			parts = append(parts, clock(shift.start)+"-"+clock(shift.end))
		}
		parts = append(parts, "total", duration(worked))
		parts = append(parts, hoursParts(values)...)
		p.emit(2, parts...)
		found = true
	}
	if !found {
		p.emit(2, "(none)")
	}
	for _, week := range []int{2*period - 1, 2 * period} {
		values, overtime := p.weekly(employee, week)
		parts := []any{"week", week}
		parts = append(parts, hoursParts(values)...)
		parts = append(parts, "weekly-ot", duration(overtime))
		p.emit(2, parts...)
	}
	p.emit(2, append([]any{"total"}, hoursParts(p.breakdown(employee, period))...)...)
}

func (p *Payroll) run(period int) {
	p.closed = period
	p.emit(0, "RUN", period, "days", fmt.Sprintf("%d-%d", 14*period-13, 14*period))
	paid, skipped := 0, 0
	var stubs []map[string]int
	for _, id := range sortedKeys(p.employees) {
		employee := p.employees[id]
		stub, balances := p.calculate(employee, period)
		if stub == nil {
			if employee.active {
				skipped++
			}
			continue
		}
		p.printStub(employee, period, stub, employee.department)
		employee.bonus = 0
		employee.ptoBalance = stub["pto_balance"]
		for i, balance := range balances {
			employee.garnishments[i].balance = balance
		}
		for _, field := range fields {
			employee.ytd[field] += stub[field]
		}
		employee.periods++
		employee.stubs[period] = StubRecord{totals: stub, department: employee.department}
		stubs = append(stubs, stub)
		paid++
	}
	totals := sumStubs(stubs)
	p.emit(2, "TOTAL", "paid", paid, "skipped", skipped,
		"gross", money(totals["gross"]),
		"deductions", money(totals["gross"]-totals["net"]),
		"net", money(totals["net"]), "employer", money(totals["employer"]))
}

func (p *Payroll) journal(period int) {
	var stubs []map[string]int
	for _, employee := range p.employees {
		if entry, ok := employee.stubs[period]; ok {
			stubs = append(stubs, entry.totals)
		}
	}
	total := sumStubs(stubs)
	type JournalRow struct {
		side   string
		label  string
		amount int
	}
	rows := []JournalRow{
		{"debit", "wages", total["gross"]},
		{"debit", "employer-tax", total["employer_social"] + total["employer_medicare"] + total["unemployment"]},
		{"debit", "retirement-match", total["match"]},
		{"credit", "retirement", total["retirement"] + total["match"]},
		{"credit", "health", total["health"]},
		{"credit", "federal", total["federal"] + total["supplemental"]},
		{"credit", "state", total["state"]},
		{"credit", "fica", total["social"] + total["medicare"] + total["employer_social"] + total["employer_medicare"]},
		{"credit", "unemployment", total["unemployment"]},
		{"credit", "garnishment", total["garnishment"]},
		{"credit", "net-pay", total["net"]},
	}
	p.emit(0, "JOURNAL", period, "stubs", len(stubs))
	debit, credit := 0, 0
	for _, row := range rows {
		p.emit(2, row.side, row.label, money(row.amount))
		if row.side == "debit" {
			debit += row.amount
		} else {
			credit += row.amount
		}
	}
	p.emit(2, "total", "debit", money(debit), "credit", money(credit))
}

func (p *Payroll) reportLine(department string, stubs []map[string]int) {
	totals := sumStubs(stubs)
	taxes := totals["federal"] + totals["supplemental"] +
		totals["state"] + totals["social"] + totals["medicare"]
	p.emit(2, department, "stubs", len(stubs), "gross", money(totals["gross"]),
		"pretax", money(totals["retirement"]+totals["health"]),
		"taxes", money(taxes), "garnishment", money(totals["garnishment"]),
		"net", money(totals["net"]), "employer", money(totals["employer"]))
}

func (p *Payroll) command(command string, a []string) error {
	switch command {
	case "SET":
		name := a[0]
		if _, ok := p.settings[name]; !ok {
			return fmt.Errorf("unknown setting %s", name)
		}
		var value int
		if rateSettings[name] {
			var err error
			value, err = rateCheck(a[1])
			if err != nil {
				return err
			}
		} else {
			value = cents(a[1])
		}
		formatter := money
		if rateSettings[name] {
			formatter = rateText
		}
		old := p.settings[name]
		p.settings[name] = value
		p.emit(0, "SET", name, formatter(old), "->", formatter(value))
	case "BRACKET", "TIER":
		rate, err := rateCheck(a[1])
		if err != nil {
			return err
		}
		brackets := p.brackets
		if command == "TIER" {
			brackets = p.tiers
		}
		lower := cents(a[0])
		action := "added"
		if _, ok := brackets[lower]; ok {
			action = "replaced"
		}
		brackets[lower] = rate
		p.emit(0, command, money(lower), rateText(rate), action)
	case "EMP":
		id := number(a[0])
		if p.employees[id] != nil {
			return fmt.Errorf("duplicate employee %s", a[0])
		}
		base, err := amountCheck(a[3])
		if err != nil {
			return err
		}
		p.employees[id] = newEmployee(id, a[1], a[2], base)
		p.emit(0, "EMP", id, a[1], a[2], money(base))
	case "RATE", "DEPT", "BENEFIT", "W4", "GARNISH", "TERM", "BONUS":
		employee, err := p.employee(a[0], true, "")
		if err != nil {
			return err
		}
		switch command {
		case "RATE":
			base, err := amountCheck(a[1])
			if err != nil {
				return err
			}
			old := employee.base
			employee.base = base
			p.emit(0, "RATE", employee.id, money(old), "->", money(base))
		case "DEPT":
			if a[1] == employee.department {
				return fmt.Errorf("same department %s", a[1])
			}
			old := employee.department
			employee.department = a[1]
			p.emit(0, "DEPT", employee.id, old, "->", a[1])
		case "BENEFIT":
			rate, err := rateCheck(a[1])
			if err != nil {
				return err
			}
			employee.retirement = rate
			employee.health = cents(a[2])
			p.emit(0, "BENEFIT", employee.id, "retirement", rateText(rate),
				"health", money(employee.health))
		case "W4":
			employee.allowances = number(a[1])
			employee.extra = cents(a[2])
			p.emit(0, "W4", employee.id, "allowances", employee.allowances,
				"extra", money(employee.extra))
		case "GARNISH":
			rate, err := rateCheck(a[1])
			if err != nil {
				return err
			}
			amount, err := amountCheck(a[2])
			if err != nil {
				return err
			}
			employee.garnishments = append(employee.garnishments, Garnishment{rate, amount})
			p.emit(0, "GARNISH", employee.id, "order", len(employee.garnishments),
				rateText(rate), "balance", money(amount))
		case "TERM":
			employee.active = false
			p.emit(0, "TERM", employee.id)
		case "BONUS":
			amount, err := amountCheck(a[1])
			if err != nil {
				return err
			}
			employee.bonus += amount
			p.emit(0, "BONUS", employee.id, money(amount),
				"pending", money(employee.bonus))
		}
	case "HOLIDAY":
		day, err := p.dayCheck(a[0])
		if err != nil {
			return err
		}
		if p.holidays[day] {
			return fmt.Errorf("duplicate holiday %s", a[0])
		}
		p.holidays[day] = true
		p.emit(0, "HOLIDAY", day, weekday(day))
	case "TIME", "UNTIME", "PTO", "LEAVE", "SALES":
		kind := "HOURLY"
		if command == "LEAVE" {
			kind = "SALARIED"
		} else if command == "SALES" {
			kind = "COMMISSION"
		}
		employee, err := p.employee(a[0], true, kind)
		if err != nil {
			return err
		}
		day, err := p.dayCheck(a[1])
		if err != nil {
			return err
		}
		switch command {
		case "TIME":
			start, err := timeCheck(a[2])
			if err != nil {
				return err
			}
			end, err := timeCheck(a[3])
			if err != nil {
				return err
			}
			if start >= end {
				return fmt.Errorf("invalid shift %s-%s", a[2], a[3])
			}
			shifts := append([]Shift(nil), employee.shifts[day]...)
			sort.Slice(shifts, func(i, j int) bool {
				return shifts[i].start < shifts[j].start
			})
			total := 0
			for _, shift := range shifts {
				if start < shift.end && shift.start < end {
					return fmt.Errorf("overlapping shift %s-%s", clock(shift.start), clock(shift.end))
				}
				total += shift.end - shift.start
			}
			if total+end-start > 960 {
				return fmt.Errorf("daily limit %s %s", a[0], a[1])
			}
			employee.shifts[day] = append(employee.shifts[day], Shift{start, end})
			p.emit(0, "TIME", employee.id, "day", day,
				clock(start)+"-"+clock(end), duration(end-start))
		case "UNTIME":
			start, err := timeCheck(a[2])
			if err != nil {
				return err
			}
			shifts := employee.shifts[day]
			position := -1
			for i, shift := range shifts {
				if shift.start == start {
					position = i
					break
				}
			}
			if position < 0 {
				return fmt.Errorf("no shift %s %s %s", a[0], a[1], a[2])
			}
			shift := shifts[position]
			employee.shifts[day] = append(shifts[:position], shifts[position+1:]...)
			p.emit(0, "UNTIME", employee.id, "day", day,
				clock(shift.start)+"-"+clock(shift.end))
		case "PTO":
			parts := strings.Split(a[2], ":")
			hour, minute := number(parts[0]), number(parts[1])
			length := hour*60 + minute
			if minute > 59 || length < 1 || length > 480 {
				return fmt.Errorf("invalid duration %s", a[2])
			}
			if _, ok := employee.pto[day]; ok {
				return fmt.Errorf("duplicate pto %s %s", a[0], a[1])
			}
			if length > employee.ptoBalance {
				return fmt.Errorf("insufficient pto %s %s", a[0], duration(employee.ptoBalance))
			}
			employee.pto[day] = length
			employee.ptoBalance -= length
			p.emit(0, "PTO", employee.id, "day", day, duration(length),
				"balance", duration(employee.ptoBalance))
		case "LEAVE":
			if day%7 == 0 || day%7 == 6 || p.holidays[day] {
				return fmt.Errorf("not workday %s", a[1])
			}
			if employee.leave[day] {
				return fmt.Errorf("duplicate leave %s %s", a[0], a[1])
			}
			employee.leave[day] = true
			p.emit(0, "LEAVE", employee.id, "day", day, weekday(day))
		case "SALES":
			amount, err := amountCheck(a[2])
			if err != nil {
				return err
			}
			period := periodOf(day)
			employee.sales[period] += amount
			p.emit(0, "SALES", employee.id, "day", day, money(amount),
				"period", period, "total", money(employee.sales[period]))
		}
	case "HOURS":
		employee, err := p.employee(a[0], false, "HOURLY")
		if err != nil {
			return err
		}
		period, err := periodCheck(a[1])
		if err != nil {
			return err
		}
		p.showHours(employee, period)
	case "RUN":
		period := number(a[0])
		if period != p.closed+1 || period > 26 {
			return fmt.Errorf("invalid period %s", a[0])
		}
		p.run(period)
	case "PREVIEW":
		employee, err := p.employee(a[0], false, "")
		if err != nil {
			return err
		}
		period := p.closed + 1
		stub, _ := p.calculate(employee, period)
		p.emit(0, "PREVIEW", employee.id, "period", period)
		if stub == nil {
			p.emit(2, "no pay")
		} else {
			p.printStub(employee, period, stub, employee.department)
		}
	case "REPRINT":
		employee, err := p.employee(a[0], false, "")
		if err != nil {
			return err
		}
		period, err := periodCheck(a[1])
		if err != nil {
			return err
		}
		entry, ok := employee.stubs[period]
		if !ok {
			return fmt.Errorf("no stub %s %s", a[0], a[1])
		}
		p.emit(0, "REPRINT", employee.id, period)
		p.printStub(employee, period, entry.totals, entry.department)
	case "YTD":
		employee, err := p.employee(a[0], false, "")
		if err != nil {
			return err
		}
		status := "terminated"
		if employee.active {
			status = "active"
		}
		p.emit(0, "YTD", employee.id, employee.department, employee.kind,
			status, "periods", employee.periods)
		totals := emptyTotals()
		for field, value := range employee.ytd {
			totals[field] = value
		}
		totals["pto_balance"] = employee.ptoBalance
		totals["garnishment_balance"] = employee.garnishmentBalance()
		p.stubBlock(employee, totals, 2)
		p.emit(2, "wages", "federal", money(totals["W"]), "social-security",
			money(totals["Y"]), "medicare", money(totals["F"]),
			"unemployment", money(totals["J"]))
		p.emit(2, "retirement-room",
			money(max(0, p.settings["RETIRECAP"]-totals["retirement"])),
			"pending-bonus", money(employee.bonus))
	case "JOURNAL":
		period := number(a[0])
		if period < 1 || period > p.closed {
			return fmt.Errorf("no run %s", a[0])
		}
		p.journal(period)
	case "REPORT":
		departments := make(map[string][]map[string]int)
		var allStubs []map[string]int
		for _, employee := range p.employees {
			for _, entry := range employee.stubs {
				departments[entry.department] = append(departments[entry.department], entry.totals)
				allStubs = append(allStubs, entry.totals)
			}
		}
		p.emit(0, "REPORT", "period", p.closed)
		for _, department := range sortedStrings(departments) {
			p.reportLine(department, departments[department])
		}
		p.reportLine("total", allStubs)
	case "TOP":
		count := number(a[0])
		var employees []*Employee
		for _, employee := range p.employees {
			if employee.periods > 0 {
				employees = append(employees, employee)
			}
		}
		sort.Slice(employees, func(i, j int) bool {
			if employees[i].ytd["gross"] != employees[j].ytd["gross"] {
				return employees[i].ytd["gross"] > employees[j].ytd["gross"]
			}
			return employees[i].id < employees[j].id
		})
		p.emit(0, "TOP", count)
		for i := 0; i < min(count, len(employees)); i++ {
			employee := employees[i]
			p.emit(2, i+1, employee.id, employee.department,
				"gross", money(employee.ytd["gross"]), "net", money(employee.ytd["net"]))
		}
		if len(employees) == 0 {
			p.emit(2, "(none)")
		}
	case "EMPLOYEES":
		p.emit(0, "EMPLOYEES")
		ids := sortedKeys(p.employees)
		for _, id := range ids {
			employee := p.employees[id]
			status := "terminated"
			if employee.active {
				status = "active"
			}
			p.emit(2, id, employee.department, employee.kind, money(employee.base),
				status, "retirement", rateText(employee.retirement),
				"health", money(employee.health), "allowances", employee.allowances,
				"extra", money(employee.extra), "bonus", money(employee.bonus))
			for i, order := range employee.garnishments {
				p.emit(4, "garnish", i+1, rateText(order.rate),
					"balance", money(order.balance))
			}
		}
		if len(ids) == 0 {
			p.emit(2, "(none)")
		}
	case "CONFIG":
		p.emit(0, "CONFIG")
		for _, name := range settingOrder {
			value := p.settings[name]
			formatter := money
			if rateSettings[name] {
				formatter = rateText
			}
			p.emit(2, name, formatter(value))
		}
		for _, item := range []struct {
			label  string
			values map[int]int
		}{{"bracket", p.brackets}, {"tier", p.tiers}} {
			for _, lower := range sortedKeys(item.values) {
				p.emit(2, item.label, money(lower), rateText(item.values[lower]))
			}
		}
	}
	return nil
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	count := number(scanner.Text())
	payroll := newPayroll()
	for i := 0; i < count && scanner.Scan(); i++ {
		tokens := strings.Fields(scanner.Text())
		if err := payroll.command(tokens[0], tokens[1:]); err != nil {
			payroll.emit(0, "ERROR", err.Error())
		}
	}
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	for _, line := range payroll.output {
		fmt.Fprintln(output, line)
	}
}
