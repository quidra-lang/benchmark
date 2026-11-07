package main

import (
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
)

var settingNames = []string{
	"CAPACITY", "INITIAL", "CHARGE", "DISCHARGE", "CEFF", "DEFF", "RESERVE", "COST",
	"EXPORT", "FEEDIN", "FIXED", "DEMAND", "PVSCALE",
}

var settingRanges = map[string][2]int{
	"CAPACITY": {1, 100000}, "INITIAL": {0, 100}, "CHARGE": {1, 20000},
	"DISCHARGE": {1, 20000}, "CEFF": {1, 100}, "DEFF": {1, 100},
	"RESERVE": {0, 100}, "COST": {0, 100000}, "EXPORT": {0, 100000},
	"FEEDIN": {0, 10000}, "FIXED": {0, 100000}, "DEMAND": {0, 100000},
	"PVSCALE": {0, 300},
}

var strategyRanges = map[string][2]int{
	"TOU": {1, 100}, "PEAKSHAVE": {0, 100000}, "BACKUP": {0, 100},
}

var dayNames = []string{"MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"}
var flowNames = []string{
	"PV>LOAD", "PV>BATTERY", "PV>GRID", "PV>CURTAIL",
	"BATTERY>LOAD", "BATTERY>GRID", "GRID>LOAD", "GRID>BATTERY",
}

type Strategy struct {
	Name      string
	Parameter int
	HasParam  bool
}

func (s Strategy) String() string {
	if s.HasParam {
		return fmt.Sprintf("%s %d", s.Name, s.Parameter)
	}
	return s.Name
}

func value(text string) int {
	n, _ := strconv.Atoi(text)
	return n
}

func money(amount int) string {
	sign := ""
	if amount < 0 {
		amount = -amount
		sign = "-"
	}
	return fmt.Sprintf("%s%d.%02d", sign, amount/100, amount%100)
}

func percentage(numerator, denominator int) string {
	if denominator == 0 {
		return "0.00"
	}
	hundredths := 10000 * numerator / denominator
	return fmt.Sprintf("%d.%02d", hundredths/100, hundredths%100)
}

func ceiling(a, b int) int { return (a + b - 1) / b }
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
func min3(a, b, c int) int { return min(min(a, b), c) }

func row(values []any, widths []int) string {
	var text strings.Builder
	for i, v := range values {
		fmt.Fprintf(&text, "%*v", widths[i], v)
	}
	return text.String()
}

func bar(width int) string {
	return "|" + strings.Repeat("#", width) + strings.Repeat(".", 20-width) + "|"
}

func clone(source map[string]int) map[string]int {
	result := make(map[string]int, len(source))
	for name, number := range source {
		result[name] = number
	}
	return result
}

func tariffExtremes(prices map[string]int, names []string) (string, string) {
	cheapest, peak := names[0], names[0]
	for _, name := range names {
		if prices[name] < prices[cheapest] {
			cheapest = name
		}
		if prices[name] > prices[peak] {
			peak = name
		}
	}
	return cheapest, peak
}

func readStrategies(words []string) ([]Strategy, error) {
	strategies := make([]Strategy, 0)
	for i := 0; i < len(words); {
		name := words[i]
		i++
		if name == "SELF" || name == "EXPORTPEAK" {
			strategies = append(strategies, Strategy{Name: name})
			continue
		}
		limits, ok := strategyRanges[name]
		if !ok {
			return nil, fmt.Errorf("unknown strategy %s", name)
		}
		if i >= len(words) {
			return nil, fmt.Errorf("missing parameter for %s", name)
		}
		parameter := value(words[i])
		i++
		if parameter < limits[0] || parameter > limits[1] {
			return nil, fmt.Errorf("invalid parameter for %s", name)
		}
		strategies = append(strategies, Strategy{Name: name, Parameter: parameter, HasParam: true})
	}
	return strategies, nil
}

func oneStrategy(words []string) (Strategy, error) {
	strategies, err := readStrategies(words)
	if err != nil {
		return Strategy{}, err
	}
	if len(strategies) != 1 {
		return Strategy{}, fmt.Errorf("wrong number of arguments")
	}
	return strategies[0], nil
}

func requireCount(words []string, expected int) error {
	if len(words) != expected {
		return fmt.Errorf("wrong number of arguments")
	}
	return nil
}

func checkedRange(low, high, step int, limits [2]int) ([]int, error) {
	if low < limits[0] || high > limits[1] || high < low || step < 1 ||
		(high-low)/step+1 > 20 {
		return nil, fmt.Errorf("invalid range")
	}
	values := make([]int, 0, 20)
	for number := low; number <= high; number += step {
		values = append(values, number)
	}
	return values, nil
}

func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}

type InputData struct {
	InitialSettings map[string]int
	InitialPrices   map[string]int
	PriceOrder      []string
	DayCount        int
	Loads           []int
	BasePV          []int
	DayNames        []string
	WeekendDays     []bool
	Periods         []string
	Commands        []string
}

func readPeriodHours(tokens []string) []string {
	hours := make([]string, 0, 24)
	for i := 0; i < len(tokens); i += 2 {
		end := 24
		if i+2 < len(tokens) {
			end = value(tokens[i+2])
		}
		for hour := value(tokens[i]); hour < end; hour++ {
			hours = append(hours, tokens[i+1])
		}
	}
	return hours
}

func readInput(lines []string) *InputData {
	index := 0
	read := func() []string {
		fields := strings.Fields(lines[index])
		index++
		return fields
	}
	battery := read()[1:]
	grid := read()[1:]
	fields := append(append(append([]string{}, battery...), grid...), "100")
	settings := make(map[string]int, len(settingNames))
	for i, name := range settingNames {
		settings[name] = value(fields[i])
	}
	count := value(read()[1])
	prices := make(map[string]int, count)
	names := make([]string, 0, count)
	for i := 0; i < count; i++ {
		pair := read()
		names = append(names, pair[0])
		prices[pair[0]] = value(pair[1])
	}
	weekday, weekend := readPeriodHours(read()[1:]), readPeriodHours(read()[1:])
	profileCount := value(read()[1])
	profiles := make(map[string][]int, profileCount)
	for i := 0; i < profileCount; i++ {
		spec := read()
		vals := make([]int, 0, 24)
		for _, token := range spec[2:] {
			vals = append(vals, value(token))
		}
		profiles[spec[0]+"/"+spec[1]] = vals
	}
	days := value(read()[1])
	result := &InputData{
		InitialSettings: settings, InitialPrices: prices, PriceOrder: names,
		DayCount: days, Loads: make([]int, 0, 24*days), BasePV: make([]int, 0, 24*days),
	}
	for day := 0; day < days; day++ {
		args := read()
		for _, load := range profiles["LOAD/"+args[0]] {
			result.Loads = append(result.Loads, load*value(args[1])/100)
		}
		for _, pv := range profiles["PV/"+args[2]] {
			result.BasePV = append(result.BasePV, pv*value(args[3])/100)
		}
	}
	holidayArgs := read()
	holidays := make(map[int]bool)
	for _, name := range holidayArgs[2:] {
		holidays[value(name)] = true
	}
	overrides := value(read()[1])
	for i := 0; i < overrides; i++ {
		args := read()
		offset := (value(args[0])-1)*24 + value(args[1])
		result.Loads[offset] = value(args[2])
		result.BasePV[offset] = value(args[3])
	}
	for day := 1; day <= days; day++ {
		holiday := holidays[day]
		isWeekend := holiday || (day-1)%7 >= 5
		name := dayNames[(day-1)%7]
		if holiday {
			name = "HOL"
		}
		result.DayNames = append(result.DayNames, name)
		result.WeekendDays = append(result.WeekendDays, isWeekend)
		if isWeekend {
			result.Periods = append(result.Periods, weekend...)
		} else {
			result.Periods = append(result.Periods, weekday...)
		}
	}
	result.Commands = lines[index:]
	return result
}

type HourRecord struct {
	Index, Day, Hour                                          int
	Period                                                    string
	Load, PV, SOC                                             int
	Flows                                                     [8]int
	Charge, Discharge, Imported, Exported, Curtailed          int
	Drawn, Shortfall, Loss, ImportCost, ExportIncome, NetCost int
}

func newHourRecord(index int, period string, load, pv, soc int, flows [8]int,
	drawn, shortfall, loss, price, feedin int) HourRecord {
	record := HourRecord{
		Index: index, Day: index/24 + 1, Hour: index % 24, Period: period,
		Load: load, PV: pv, SOC: soc, Flows: flows, Drawn: drawn,
		Shortfall: shortfall, Loss: loss,
	}
	record.Charge = flows[1] + flows[7]
	record.Discharge = flows[4] + flows[5]
	record.Imported = flows[6] + flows[7]
	record.Exported = flows[2] + flows[5]
	record.Curtailed = flows[3]
	record.ImportCost = record.Imported * price / 100000
	record.ExportIncome = record.Exported * feedin / 100000
	record.NetCost = record.ImportCost - record.ExportIncome
	return record
}

type Totals struct {
	Count                                                      int
	Load, PV, Charge, Discharge, Imported, Exported, Curtailed int
	Drawn, Loss, Shortfall, ImportCost, ExportIncome, NetCost  int
	Flows                                                      [8]int
}

func totalRecords(records []HourRecord) Totals {
	total := Totals{Count: len(records)}
	for _, record := range records {
		total.Load += record.Load
		total.PV += record.PV
		total.Charge += record.Charge
		total.Discharge += record.Discharge
		total.Imported += record.Imported
		total.Exported += record.Exported
		total.Curtailed += record.Curtailed
		total.Drawn += record.Drawn
		total.Loss += record.Loss
		total.Shortfall += record.Shortfall
		total.ImportCost += record.ImportCost
		total.ExportIncome += record.ExportIncome
		for i, amount := range record.Flows {
			total.Flows[i] += amount
		}
	}
	total.NetCost = total.ImportCost - total.ExportIncome
	return total
}

type SimulationResult struct {
	Strategy                         Strategy
	Settings, Prices                 map[string]int
	StartSOC, Reserve                int
	Hours                            []HourRecord
	Days                             [][]HourRecord
	Daily                            []Totals
	ByPeriod                         map[string]Totals
	Total                            Totals
	Peak, DemandCharge, Bill, EndSOC int
	Sufficiency                      string
}

func newSimulationResult(strategy Strategy, settings, prices map[string]int,
	names []string, startSOC, reserve int, records []HourRecord) *SimulationResult {
	result := &SimulationResult{
		Strategy: strategy, Settings: clone(settings), Prices: clone(prices),
		StartSOC: startSOC, Reserve: reserve, Hours: records, ByPeriod: make(map[string]Totals),
	}
	for start := 0; start < len(records); start += 24 {
		day := records[start : start+24]
		result.Days = append(result.Days, day)
		result.Daily = append(result.Daily, totalRecords(day))
	}
	for _, name := range names {
		belonging := make([]HourRecord, 0)
		for _, record := range records {
			if record.Period == name {
				belonging = append(belonging, record)
			}
		}
		result.ByPeriod[name] = totalRecords(belonging)
	}
	result.Total = totalRecords(records)
	for _, record := range records {
		result.Peak = max(result.Peak, record.Imported)
	}
	result.DemandCharge = result.Peak * settings["DEMAND"] / 1000
	result.Bill = result.Total.NetCost + settings["FIXED"] + result.DemandCharge
	result.EndSOC = records[len(records)-1].SOC
	result.Sufficiency = percentage(max(0, result.Total.Load-result.Total.Imported), result.Total.Load)
	return result
}

type Simulator struct {
	Data                                                    *InputData
	Strategy                                                Strategy
	Settings, Prices                                        map[string]int
	Name                                                    string
	Parameter, Capacity, CEff, DEff, Reserve, StartSOC, SOC int
	Cheapest, Peak                                          string
	Arbitrage                                               bool
	Outage                                                  *[2]int
}

func newSimulator(data *InputData, strategy Strategy, settings, prices map[string]int, outage *[2]int) *Simulator {
	capacity := settings["CAPACITY"]
	reservePct := settings["RESERVE"]
	if strategy.Name == "BACKUP" {
		reservePct = max(reservePct, strategy.Parameter)
	}
	cheapest, peak := tariffExtremes(prices, data.PriceOrder)
	initial := capacity * settings["INITIAL"] / 100
	return &Simulator{
		Data: data, Strategy: strategy, Settings: clone(settings), Prices: clone(prices),
		Name: strategy.Name, Parameter: strategy.Parameter,
		Capacity: capacity, CEff: settings["CEFF"], DEff: settings["DEFF"],
		Reserve: capacity * reservePct / 100, StartSOC: initial, SOC: initial,
		Cheapest: cheapest, Peak: peak,
		Arbitrage: strategy.Name == "EXPORTPEAK" && settings["FEEDIN"] > prices[cheapest], Outage: outage,
	}
}

func (s *Simulator) dischargeTarget(deficit int, period string) int {
	switch {
	case s.Name == "TOU":
		if period == s.Peak {
			return deficit
		}
		return 0
	case s.Name == "PEAKSHAVE":
		return max(0, deficit-s.Parameter)
	case s.Arbitrage && period == s.Cheapest && period != s.Peak:
		return 0
	default:
		return deficit
	}
}

func (s *Simulator) gridCharge(period string, pvCharge, gridLoad int) int {
	headroom := s.Settings["CHARGE"] - pvCharge
	target := -1
	switch {
	case s.Name == "TOU" && period == s.Cheapest && period != s.Peak:
		target = s.Capacity * s.Parameter / 100
	case s.Name == "PEAKSHAVE" && period == s.Cheapest:
		target = s.Capacity
		headroom = min(headroom, max(0, s.Parameter-gridLoad))
	case s.Name == "BACKUP" && period == s.Cheapest:
		target = s.Reserve
	case s.Arbitrage && period == s.Cheapest && period != s.Peak:
		target = s.Capacity
	}
	if target < 0 {
		return 0
	}
	amount := min(headroom, ceiling(100*max(0, target-s.SOC), s.CEff))
	s.SOC += amount * s.CEff / 100
	return amount
}

func (s *Simulator) runHour(index int) HourRecord {
	settings := s.Settings
	load := s.Data.Loads[index]
	pv := s.Data.BasePV[index] * settings["PVSCALE"] / 100
	period := s.Data.Periods[index]
	direct := min(load, pv)
	surplus := pv - direct
	deficit := load - direct
	pvCharge := min3(surplus, settings["CHARGE"], ceiling(100*(s.Capacity-s.SOC), s.CEff))
	s.SOC += pvCharge * s.CEff / 100
	surplus -= pvCharge
	isOutage := s.Outage != nil && s.Outage[0] <= index && index <= s.Outage[1]
	target := s.dischargeTarget(deficit, period)
	lowerBound := s.Reserve
	if isOutage {
		target = deficit
		lowerBound = 0
	}
	loadDrawn := min3(ceiling(100*target, s.DEff), settings["DISCHARGE"], max(0, s.SOC-lowerBound))
	loadDischarge := loadDrawn * s.DEff / 100
	s.SOC -= loadDrawn
	deficit -= loadDischarge
	gridLoad, shortfall, pvExport, curtailed, gridCharge, exportDrawn, batteryExport := 0, 0, 0, 0, 0, 0, 0
	if isOutage {
		shortfall, curtailed = deficit, surplus
	} else {
		gridLoad = deficit
		pvExport = min(surplus, settings["EXPORT"])
		curtailed = surplus - pvExport
		gridCharge = s.gridCharge(period, pvCharge, gridLoad)
		if s.Arbitrage && period == s.Peak && pvCharge == 0 {
			exportDrawn = min3(ceiling(100*(settings["EXPORT"]-pvExport), s.DEff),
				settings["DISCHARGE"]-loadDrawn, max(0, s.SOC-s.Reserve))
			batteryExport = exportDrawn * s.DEff / 100
			s.SOC -= exportDrawn
		}
	}
	loss := pvCharge - pvCharge*s.CEff/100 + gridCharge - gridCharge*s.CEff/100 +
		loadDrawn - loadDischarge + exportDrawn - batteryExport
	flows := [8]int{direct, pvCharge, pvExport, curtailed, loadDischarge, batteryExport, gridLoad, gridCharge}
	return newHourRecord(index, period, load, pv, s.SOC, flows, loadDrawn+exportDrawn,
		shortfall, loss, s.Prices[period], settings["FEEDIN"])
}

func (s *Simulator) run() *SimulationResult {
	records := make([]HourRecord, 0, len(s.Data.Loads))
	for i := range s.Data.Loads {
		records = append(records, s.runHour(i))
	}
	return newSimulationResult(s.Strategy, s.Settings, s.Prices, s.Data.PriceOrder, s.StartSOC, s.Reserve, records)
}

type Desk struct {
	data             *InputData
	settings, prices map[string]int
	current          *SimulationResult
}

func newDesk(data *InputData) *Desk {
	return &Desk{data: data, settings: clone(data.InitialSettings), prices: clone(data.InitialPrices)}
}

func (d *Desk) simulate(strategy Strategy, settings, prices map[string]int, outage *[2]int) *SimulationResult {
	return newSimulator(d.data, strategy, settings, prices, outage).run()
}

func (d *Desk) baseline(settings, prices map[string]int) *SimulationResult {
	withoutBattery := clone(settings)
	withoutBattery["CAPACITY"] = 0
	return d.simulate(Strategy{Name: "SELF"}, withoutBattery, prices, nil)
}

func (d *Desk) requireResult() (*SimulationResult, error) {
	if d.current == nil {
		return nil, fmt.Errorf("no run")
	}
	return d.current, nil
}

func (d *Desk) checkedDay(token string) (int, error) {
	day := value(token)
	if day < 1 || day > d.data.DayCount {
		return 0, fmt.Errorf("invalid day")
	}
	return day, nil
}

func (d *Desk) resultNoArgs(args []string) (*SimulationResult, error) {
	if err := requireCount(args, 0); err != nil {
		return nil, err
	}
	return d.requireResult()
}

func (d *Desk) resultForDay(args []string) (int, *SimulationResult, error) {
	if err := requireCount(args, 1); err != nil {
		return 0, nil, err
	}
	day, err := d.checkedDay(args[0])
	if err != nil {
		return 0, nil, err
	}
	result, err := d.requireResult()
	return day, result, err
}

func (d *Desk) execute(tokens []string) []string {
	output, err := d.handle(tokens[0], tokens[1:])
	if err != nil {
		return []string{"ERROR " + err.Error()}
	}
	return output
}

func (d *Desk) handle(command string, args []string) ([]string, error) {
	switch command {
	case "RUN":
		strategy, err := oneStrategy(args)
		if err != nil {
			return nil, err
		}
		result := d.simulate(strategy, d.settings, d.prices, nil)
		d.current = result
		return []string{fmt.Sprintf("RUN %s bill %s import %d export %d soc %d",
			strategy, money(result.Bill), result.Total.Imported, result.Total.Exported, result.EndSOC)}, nil

	case "SET":
		if err := requireCount(args, 2); err != nil {
			return nil, err
		}
		name := args[0]
		limits, ok := settingRanges[name]
		if !ok {
			return nil, fmt.Errorf("unknown parameter %s", name)
		}
		v := value(args[1])
		if v < limits[0] || v > limits[1] {
			return nil, fmt.Errorf("invalid value for %s", name)
		}
		previous := d.settings[name]
		d.settings[name] = v
		return []string{fmt.Sprintf("SET %s %d -> %d", name, previous, v)}, nil

	case "PRICE":
		if err := requireCount(args, 2); err != nil {
			return nil, err
		}
		name := args[0]
		previous, ok := d.prices[name]
		if !ok {
			return nil, fmt.Errorf("unknown period %s", name)
		}
		v := value(args[1])
		if v < 0 || v > 10000 {
			return nil, fmt.Errorf("invalid value for %s", name)
		}
		d.prices[name] = v
		cheapest, peak := tariffExtremes(d.prices, d.data.PriceOrder)
		return []string{fmt.Sprintf("PRICE %s %d -> %d cheapest %s peak %s",
			name, previous, v, cheapest, peak)}, nil

	case "RESET":
		if err := requireCount(args, 0); err != nil {
			return nil, err
		}
		d.settings = clone(d.data.InitialSettings)
		d.prices = clone(d.data.InitialPrices)
		return []string{"RESET"}, nil

	case "CONFIG":
		if err := requireCount(args, 0); err != nil {
			return nil, err
		}
		pieces := []string{}
		for _, name := range settingNames[:8] {
			pieces = append(pieces, strings.ToLower(name), strconv.Itoa(d.settings[name]))
		}
		battery := "BATTERY " + strings.Join(pieces, " ")
		pieces = nil
		for _, name := range settingNames[8:12] {
			pieces = append(pieces, strings.ToLower(name), strconv.Itoa(d.settings[name]))
		}
		grid := "GRID " + strings.Join(pieces, " ")
		pieces = nil
		for _, name := range d.data.PriceOrder {
			pieces = append(pieces, name, strconv.Itoa(d.prices[name]))
		}
		cheapest, peak := tariffExtremes(d.prices, d.data.PriceOrder)
		tariff := fmt.Sprintf("TARIFF %s cheapest %s peak %s", strings.Join(pieces, " "), cheapest, peak)
		return []string{battery, grid, fmt.Sprintf("SOLAR pvscale %d", d.settings["PVSCALE"]), tariff}, nil

	case "NOBATTERY":
		if err := requireCount(args, 0); err != nil {
			return nil, err
		}
		result := d.baseline(d.settings, d.prices)
		return []string{fmt.Sprintf("NOBATTERY bill %s import %d export %d curtailed %d peak %d",
			money(result.Bill), result.Total.Imported, result.Total.Exported, result.Total.Curtailed, result.Peak)}, nil

	case "COMPARE":
		strategies, err := readStrategies(args)
		if err != nil {
			return nil, err
		}
		if len(strategies) == 0 {
			return nil, fmt.Errorf("wrong number of arguments")
		}
		reference := d.baseline(d.settings, d.prices)
		results := make([]*SimulationResult, 0, len(strategies))
		for _, strategy := range strategies {
			results = append(results, d.simulate(strategy, d.settings, d.prices, nil))
		}
		sort.SliceStable(results, func(i, j int) bool { return results[i].Bill < results[j].Bill })
		output := []string{fmt.Sprintf("COMPARE baseline %s", money(reference.Bill))}
		for i, result := range results {
			output = append(output, fmt.Sprintf("%d. %s bill %s saving %s sufficiency %s%%",
				i+1, result.Strategy, money(result.Bill), money(reference.Bill-result.Bill), result.Sufficiency))
		}
		return output, nil

	case "SIZE":
		if err := requireCount(args, 3); err != nil {
			return nil, err
		}
		capacities, err := checkedRange(value(args[0]), value(args[1]), value(args[2]), settingRanges["CAPACITY"])
		if err != nil {
			return nil, err
		}
		reference := d.baseline(d.settings, d.prices)
		output := []string{}
		bestCapacity, bestCost, bestSaving := 0, 0, 0
		for _, capacity := range capacities {
			settings := clone(d.settings)
			settings["CAPACITY"] = capacity
			result := d.simulate(Strategy{Name: "SELF"}, settings, d.prices, nil)
			saving := reference.Bill - result.Bill
			cost := capacity * settings["COST"] / 1000
			payback := "never"
			if saving > 0 {
				tenths := 10 * cost / saving
				payback = fmt.Sprintf("%d.%d", tenths/10, tenths%10)
				if bestCapacity == 0 || cost*bestSaving < bestCost*saving {
					bestCapacity, bestCost, bestSaving = capacity, cost, saving
				}
			}
			output = append(output, fmt.Sprintf("SIZE %d bill %s saving %s cost %s payback %s",
				capacity, money(result.Bill), money(saving), money(cost), payback))
		}
		if bestCapacity == 0 {
			output = append(output, "BEST none")
		} else {
			output = append(output, fmt.Sprintf("BEST %d", bestCapacity))
		}
		return output, nil

	case "SWEEP":
		if len(args) < 5 {
			return nil, fmt.Errorf("wrong number of arguments")
		}
		item := args[0]
		limits, ok := settingRanges[item]
		if !ok {
			return nil, fmt.Errorf("unknown parameter %s", item)
		}
		vals, err := checkedRange(value(args[1]), value(args[2]), value(args[3]), limits)
		if err != nil {
			return nil, err
		}
		strategy, err := oneStrategy(args[4:])
		if err != nil {
			return nil, err
		}
		output := []string{}
		bestValue, bestBill := 0, 0
		for i, v := range vals {
			settings := clone(d.settings)
			settings[item] = v
			result := d.simulate(strategy, settings, d.prices, nil)
			reference := d.baseline(settings, d.prices)
			if i == 0 || result.Bill < bestBill {
				bestValue, bestBill = v, result.Bill
			}
			output = append(output, fmt.Sprintf("SWEEP %s %d bill %s saving %s sufficiency %s%%",
				item, v, money(result.Bill), money(reference.Bill-result.Bill), result.Sufficiency))
		}
		output = append(output, fmt.Sprintf("BEST %d", bestValue))
		return output, nil

	case "OUTAGE":
		if err := requireCount(args, 3); err != nil {
			return nil, err
		}
		day, err := d.checkedDay(args[0])
		if err != nil {
			return nil, err
		}
		start, end := value(args[1]), value(args[2])
		if start < 0 || start > end || end > 23 {
			return nil, fmt.Errorf("invalid hours")
		}
		previous, err := d.requireResult()
		if err != nil {
			return nil, err
		}
		first, last := (day-1)*24+start, (day-1)*24+end
		outage := [2]int{first, last}
		result := d.simulate(previous.Strategy, previous.Settings, previous.Prices, &outage)
		before := result.StartSOC
		if first > 0 {
			before = result.Hours[first-1].SOC
		}
		output := []string{fmt.Sprintf("OUTAGE day %d hours %d-%d strategy %s soc %d",
			day, start, end, result.Strategy, before), "hour   load     pv  disch    soc  short   curt"}
		records := result.Hours[first : last+1]
		for _, r := range records {
			output = append(output, row([]any{r.Hour, r.Load, r.PV, r.Discharge, r.SOC, r.Shortfall, r.Curtailed},
				[]int{4, 7, 7, 7, 7, 7, 7}))
		}
		total := totalRecords(records)
		served := "100.00"
		if total.Load != 0 {
			served = percentage(total.Load-total.Shortfall, total.Load)
		}
		output = append(output, fmt.Sprintf("TOTAL load %d unserved %d served %s%% bill %s",
			total.Load, total.Shortfall, served, money(result.Bill)))
		return output, nil

	case "DIFF":
		if len(args) < 2 {
			return nil, fmt.Errorf("wrong number of arguments")
		}
		day, err := d.checkedDay(args[0])
		if err != nil {
			return nil, err
		}
		strategy, err := oneStrategy(args[1:])
		if err != nil {
			return nil, err
		}
		previous, err := d.requireResult()
		if err != nil {
			return nil, err
		}
		comparison := d.simulate(strategy, previous.Settings, previous.Prices, nil)
		output := []string{fmt.Sprintf("DIFF day %d %s %s vs %s", day, d.data.DayNames[day-1], previous.Strategy, strategy),
			"hour   imp1   imp2   exp1   exp2   soc1   soc2"}
		for i, first := range previous.Days[day-1] {
			second := comparison.Days[day-1][i]
			output = append(output, row([]any{first.Hour, first.Imported, second.Imported, first.Exported,
				second.Exported, first.SOC, second.SOC}, []int{4, 7, 7, 7, 7, 7, 7}))
		}
		cost1, cost2 := previous.Daily[day-1].NetCost, comparison.Daily[day-1].NetCost
		output = append(output, fmt.Sprintf("TOTAL cost1 %s cost2 %s difference %s",
			money(cost1), money(cost2), money(cost2-cost1)))
		return output, nil

	case "HOURLY":
		day, result, err := d.resultForDay(args)
		if err != nil {
			return nil, err
		}
		output := []string{fmt.Sprintf("HOURLY day %d %s strategy %s",
			day, d.data.DayNames[day-1], result.Strategy),
			"hour   load     pv charge  disch    soc import export   curt"}
		widths := []int{4, 7, 7, 7, 7, 7, 7, 7, 7}
		for _, r := range result.Days[day-1] {
			output = append(output, row([]any{r.Hour, r.Load, r.PV, r.Charge, r.Discharge, r.SOC, r.Imported,
				r.Exported, r.Curtailed}, widths))
		}
		total := result.Daily[day-1]
		output = append(output, row([]any{"sum", total.Load, total.PV, total.Charge, total.Discharge,
			"", total.Imported, total.Exported, total.Curtailed}, widths))
		return output, nil

	case "DAILY":
		result, err := d.resultNoArgs(args)
		if err != nil {
			return nil, err
		}
		output := []string{fmt.Sprintf("DAILY strategy %s", result.Strategy),
			"day name    load      pv  import  export    curt     soc      cost"}
		widths := []int{3, 5, 8, 8, 8, 8, 8, 8, 10}
		for i, total := range result.Daily {
			day := result.Days[i]
			output = append(output, row([]any{i + 1, d.data.DayNames[i], total.Load, total.PV, total.Imported,
				total.Exported, total.Curtailed, day[len(day)-1].SOC, money(total.NetCost)}, widths))
		}
		total := result.Total
		output = append(output, fmt.Sprintf("TOTAL load %d pv %d import %d export %d curtailed %d cost %s",
			total.Load, total.PV, total.Imported, total.Exported, total.Curtailed, money(total.NetCost)))
		return output, nil

	case "BILL":
		result, err := d.resultNoArgs(args)
		if err != nil {
			return nil, err
		}
		output := []string{fmt.Sprintf("BILL strategy %s days %d", result.Strategy, d.data.DayCount)}
		for _, period := range d.data.PriceOrder {
			total := result.ByPeriod[period]
			output = append(output, fmt.Sprintf("IMPORT %s %d Wh %s", period, total.Imported, money(total.ImportCost)))
		}
		output = append(output,
			fmt.Sprintf("EXPORT %d Wh %s", result.Total.Exported, money(-result.Total.ExportIncome)),
			fmt.Sprintf("FIXED %s", money(result.Settings["FIXED"])),
			fmt.Sprintf("DEMAND %d Wh %s", result.Peak, money(result.DemandCharge)),
			fmt.Sprintf("TOTAL %s", money(result.Bill)))
		return output, nil

	case "SAVINGS":
		result, err := d.resultNoArgs(args)
		if err != nil {
			return nil, err
		}
		reference := d.baseline(result.Settings, result.Prices)
		output := []string{fmt.Sprintf("SAVINGS strategy %s", result.Strategy)}
		for _, period := range d.data.PriceOrder {
			before, after := reference.ByPeriod[period].ImportCost, result.ByPeriod[period].ImportCost
			output = append(output, fmt.Sprintf("%s %s -> %s saving %s",
				period, money(before), money(after), money(before-after)))
		}
		pairs := [][3]int{{0, -reference.Total.ExportIncome, -result.Total.ExportIncome},
			{1, reference.DemandCharge, result.DemandCharge}, {2, reference.Bill, result.Bill}}
		for _, pair := range pairs {
			name := []string{"EXPORT", "DEMAND", "TOTAL"}[pair[0]]
			output = append(output, fmt.Sprintf("%s %s -> %s saving %s",
				name, money(pair[1]), money(pair[2]), money(pair[1]-pair[2])))
		}
		return output, nil

	case "BYPERIOD":
		result, err := d.resultNoArgs(args)
		if err != nil {
			return nil, err
		}
		output := []string{fmt.Sprintf("BYPERIOD strategy %s", result.Strategy)}
		for _, period := range d.data.PriceOrder {
			t := result.ByPeriod[period]
			output = append(output, fmt.Sprintf("%s hours %d load %d pv %d charge %d discharge %d import %d export %d",
				period, t.Count, t.Load, t.PV, t.Charge, t.Discharge, t.Imported, t.Exported))
		}
		return output, nil

	case "DAYTYPE":
		result, err := d.resultNoArgs(args)
		if err != nil {
			return nil, err
		}
		output := []string{fmt.Sprintf("DAYTYPE strategy %s", result.Strategy)}
		for _, category := range []struct {
			Name    string
			Weekend bool
		}{{"WEEKDAY", false}, {"WEEKEND", true}} {
			records := []HourRecord{}
			count := 0
			for i, isWeekend := range d.data.WeekendDays {
				if isWeekend == category.Weekend {
					count++
					records = append(records, result.Days[i]...)
				}
			}
			total := totalRecords(records)
			output = append(output, fmt.Sprintf("%s days %d load %d pv %d import %d export %d cost %s",
				category.Name, count, total.Load/count, total.PV/count, total.Imported/count,
				total.Exported/count, money(total.NetCost/count)))
		}
		return output, nil

	case "PEAKS":
		if err := requireCount(args, 1); err != nil {
			return nil, err
		}
		count := value(args[0])
		if count < 1 {
			return nil, fmt.Errorf("invalid count")
		}
		result, err := d.requireResult()
		if err != nil {
			return nil, err
		}
		records := []HourRecord{}
		for _, record := range result.Hours {
			if record.Imported > 0 {
				records = append(records, record)
			}
		}
		sort.Slice(records, func(i, j int) bool {
			if records[i].Imported != records[j].Imported {
				return records[i].Imported > records[j].Imported
			}
			return records[i].Index < records[j].Index
		})
		output := []string{fmt.Sprintf("PEAKS strategy %s", result.Strategy)}
		for i := 0; i < count && i < len(records); i++ {
			r := records[i]
			output = append(output, fmt.Sprintf("%d. day %d hour %d %s import %d load %d soc %d",
				i+1, r.Day, r.Hour, r.Period, r.Imported, r.Load, r.SOC))
		}
		if len(records) == 0 {
			output = append(output, "none")
		}
		return output, nil

	case "PROFILE":
		result, err := d.resultNoArgs(args)
		if err != nil {
			return nil, err
		}
		output := []string{fmt.Sprintf("PROFILE strategy %s days %d", result.Strategy, d.data.DayCount),
			"hour   load     pv import export    soc"}
		for hour := 0; hour < 24; hour++ {
			loads, pvs, imports, exports, socs := 0, 0, 0, 0, 0
			for i := hour; i < len(result.Hours); i += 24 {
				r := result.Hours[i]
				loads += r.Load
				pvs += r.PV
				imports += r.Imported
				exports += r.Exported
				socs += r.SOC
			}
			n := d.data.DayCount
			output = append(output, row([]any{hour, loads / n, pvs / n, imports / n, exports / n, socs / n},
				[]int{4, 7, 7, 7, 7, 7}))
		}
		return output, nil

	case "FLOWS":
		result, err := d.resultNoArgs(args)
		if err != nil {
			return nil, err
		}
		output := []string{fmt.Sprintf("FLOWS strategy %s", result.Strategy)}
		for i, name := range flowNames {
			output = append(output, fmt.Sprintf("%s %d", name, result.Total.Flows[i]))
		}
		output = append(output, fmt.Sprintf("LOSSES %d", result.Total.Loss),
			fmt.Sprintf("STORED %d", result.EndSOC-result.StartSOC))
		return output, nil

	case "SELFSUFF":
		result, err := d.resultNoArgs(args)
		if err != nil {
			return nil, err
		}
		flows := result.Total.Flows
		return []string{fmt.Sprintf("SELFSUFF sufficiency %s%% consumption %s%%",
			result.Sufficiency, percentage(flows[0]+flows[1], result.Total.PV))}, nil

	case "CYCLES":
		result, err := d.resultNoArgs(args)
		if err != nil {
			return nil, err
		}
		drawn := result.Total.Drawn
		capacity := result.Settings["CAPACITY"]
		common := gcd(drawn, capacity)
		thousandths := 1000 * drawn / capacity
		return []string{fmt.Sprintf("CYCLES %d/%d %d.%03d drawn %d losses %d",
			drawn/common, capacity/common, thousandths/1000, thousandths%1000, drawn, result.Total.Loss)}, nil

	case "USAGE":
		result, err := d.resultNoArgs(args)
		if err != nil {
			return nil, err
		}
		charging, discharging, idle, full, low, longest, length := 0, 0, 0, 0, 0, 0, 0
		first := -1
		for _, r := range result.Hours {
			if r.Charge > 0 {
				charging++
			}
			if r.Drawn > 0 {
				discharging++
			}
			if r.Charge == 0 && r.Drawn == 0 {
				idle++
			}
			if r.SOC == result.Settings["CAPACITY"] {
				full++
			}
			if r.SOC <= result.Reserve {
				low++
				length++
				if length > longest {
					longest = length
					first = r.Index - length + 1
				}
			} else {
				length = 0
			}
		}
		message := fmt.Sprintf("USAGE charging %d discharging %d idle %d full %d low %d longest %d",
			charging, discharging, idle, full, low, longest)
		if first >= 0 {
			r := result.Hours[first]
			message += fmt.Sprintf(" from day %d hour %d", r.Day, r.Hour)
		}
		return []string{message}, nil

	case "HISTOGRAM":
		result, err := d.resultNoArgs(args)
		if err != nil {
			return nil, err
		}
		var counts [10]int
		for _, r := range result.Hours {
			band := min(9, 10*r.SOC/result.Settings["CAPACITY"])
			counts[band]++
		}
		output := []string{fmt.Sprintf("HISTOGRAM strategy %s", result.Strategy)}
		for i, count := range counts {
			output = append(output, fmt.Sprintf("%3d%% %s %d", i*10, bar(20*count/len(result.Hours)), count))
		}
		return output, nil

	case "CHART":
		day, result, err := d.resultForDay(args)
		if err != nil {
			return nil, err
		}
		capacity := result.Settings["CAPACITY"]
		output := []string{fmt.Sprintf("CHART day %d %s strategy %s", day, d.data.DayNames[day-1], result.Strategy)}
		for _, r := range result.Days[day-1] {
			output = append(output, fmt.Sprintf("%2d %s %s%%", r.Hour,
				bar(20*r.SOC/capacity), percentage(r.SOC, capacity)))
		}
		return output, nil

	default:
		return nil, fmt.Errorf("unknown command %s", command)
	}
}

func main() {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		panic(err)
	}
	input := strings.TrimRight(string(data), "\r\n")
	if input == "" {
		return
	}
	lines := strings.Split(strings.ReplaceAll(input, "\r\n", "\n"), "\n")
	parsed := readInput(lines)
	desk := newDesk(parsed)
	output := []string{}
	for _, line := range parsed.Commands {
		tokens := strings.Fields(line)
		if len(tokens) == 0 {
			continue
		}
		if tokens[0] == "END" {
			break
		}
		output = append(output, desk.execute(tokens)...)
	}
	if len(output) != 0 {
		fmt.Println(strings.Join(output, "\n"))
	}
}
