package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var stageNames = [4]string{"RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY"}
var policyParameters = map[string]int{
	"FIXED": 1, "PASS": 0, "BASESTOCK": 1, "MINMAX": 2,
	"MOVAVG": 2, "SMOOTH": 2, "STERMAN": 4,
}

func parse(text string) int64 {
	value, _ := strconv.ParseInt(text, 10, 64)
	return value
}

func money(value int64) string {
	return fmt.Sprintf("%d.%02d", value/100, value%100)
}

func decimal(numerator, denominator int64, places int) string {
	whole, remainder := numerator/denominator, numerator%denominator
	var result strings.Builder
	fmt.Fprintf(&result, "%d.", whole)
	for i := 0; i < places; i++ {
		remainder *= 10
		result.WriteByte('0' + byte(remainder/denominator))
		remainder %= denominator
	}
	return result.String()
}

func variation(values []int64) int64 {
	var sum, squares int64
	for _, value := range values {
		sum += value
		squares += value * value
	}
	return int64(len(values))*squares - sum*sum
}

func sum(values []int64) int64 {
	var result int64
	for _, value := range values {
		result += value
	}
	return result
}

func floorDiv(numerator, denominator int64) int64 {
	result := numerator / denominator
	if numerator%denominator < 0 {
		result--
	}
	return result
}

func pipelineText(values []int64) string {
	parts := make([]string, len(values))
	for i, value := range values {
		parts[i] = fmt.Sprint(value)
	}
	return strings.Join(parts, ",")
}

type Policy struct {
	name string
	args []int64
	text string
}

func parsePolicy(tokens []string) (Policy, error) {
	name := tokens[0]
	count, known := policyParameters[name]
	if !known {
		return Policy{}, fmt.Errorf("unknown policy %s", name)
	}
	if len(tokens)-1 != count {
		return Policy{}, fmt.Errorf("%s needs %d parameters", name, count)
	}
	args := make([]int64, count)
	for i, token := range tokens[1:] {
		if name == "STERMAN" && i < 3 {
			token = strings.ReplaceAll(token, ".", "")
		}
		args[i] = parse(token)
	}
	valid := false
	switch name {
	case "FIXED":
		valid = args[0] <= 1000
	case "PASS":
		valid = true
	case "BASESTOCK":
		valid = args[0] <= 10000
	case "MINMAX":
		valid = args[0] < args[1] && args[1] <= 10000
	case "MOVAVG":
		valid = 1 <= args[0] && args[0] <= 52 && args[1] <= 10000
	case "SMOOTH":
		valid = 1 <= args[0] && args[0] <= 10 && args[1] <= 10000
	case "STERMAN":
		valid = args[0] <= 100 && args[1] <= 100 && args[2] <= 100 && args[3] <= 10000
	}
	if !valid {
		return Policy{}, fmt.Errorf("invalid parameter for %s", name)
	}
	return Policy{name, args, strings.Join(tokens, " ")}, nil
}

type Setting struct {
	inventory int64
	quantity  int64
	shipping  int
	orders    int
	holding   int64
	backlog   int64
	policy    Policy
}

type Record struct {
	received    int64
	incoming    int64
	shipped     int64
	before      int64
	ontime      int64
	inventory   int64
	backlog     int64
	order       int64
	holding     int64
	backlogCost int64
	cost        int64
}

type PlantRecord struct {
	incoming int64
	produced int64
	backlog  int64
}

type Stage struct {
	inventory   int64
	backlog     int64
	shipping    []int64
	orders      []int64
	policy      Policy
	expected    int64
	holding     int64
	backlogRate int64
	lot         int64
	capacity    *int64
	records     []Record
}

func newStage(initial Setting) Stage {
	shipping := make([]int64, initial.shipping)
	orders := make([]int64, initial.orders)
	for i := range shipping {
		shipping[i] = initial.quantity
	}
	for i := range orders {
		orders[i] = initial.quantity
	}
	return Stage{
		inventory: initial.inventory, shipping: shipping, orders: orders,
		policy: initial.policy, expected: 100 * initial.quantity,
		holding: initial.holding, backlogRate: initial.backlog, lot: 1,
	}
}

func (stage *Stage) clone() Stage {
	copied := *stage
	copied.shipping = append([]int64(nil), stage.shipping...)
	copied.orders = append([]int64(nil), stage.orders...)
	copied.records = append([]Record(nil), stage.records...)
	return copied
}

func (stage *Stage) costs() int64 {
	var cost int64
	for _, record := range stage.records {
		cost += record.cost
	}
	return cost
}

type Simulation struct {
	initials      [4]Setting
	week          int
	demands       []int64
	stages        [4]Stage
	plantBacklog  int64
	plantCapacity *int64
	plantRecords  []PlantRecord
	visibility    string
}

func newSimulation(initials [4]Setting, demands []int64) *Simulation {
	sim := &Simulation{
		initials: initials,
		demands: append([]int64(nil), demands...),
		visibility: "OFF",
	}
	for i := range sim.stages {
		sim.stages[i] = newStage(initials[i])
	}
	return sim
}

func (sim *Simulation) clone() *Simulation {
	copied := *sim
	copied.demands = append([]int64(nil), sim.demands...)
	for i := range sim.stages {
		copied.stages[i] = sim.stages[i].clone()
	}
	copied.plantRecords = append([]PlantRecord(nil), sim.plantRecords...)
	return &copied
}

func (sim *Simulation) signal(index int, week int, current *[4]int64) int64 {
	if sim.visibility == "ON" {
		return sim.demands[week-1]
	}
	if current != nil && week == sim.week+1 {
		return current[index]
	}
	return sim.stages[index].records[week-1].incoming
}

func (sim *Simulation) setPolicy(index int, policy Policy) {
	stage := &sim.stages[index]
	stage.policy = policy
	if policy.name == "STERMAN" {
		previous := sim.initials[index].quantity
		if sim.week > 0 {
			previous = sim.signal(index, sim.week, nil)
		}
		stage.expected = 100 * previous
	}
}

func (sim *Simulation) positions() ([4]int64, [4]int64) {
	var supply, position [4]int64
	for i, stage := range sim.stages {
		upstream := sim.plantBacklog
		if i < 3 {
			upstream = sim.stages[i+1].backlog
		}
		line := sum(stage.orders) + upstream + sum(stage.shipping)
		supply[i] = line
		position[i] = stage.inventory + line - stage.backlog
	}
	return supply, position
}

func (sim *Simulation) policyOrder(index int, incoming [4]int64, line, position int64) int64 {
	stage := &sim.stages[index]
	name, args := stage.policy.name, stage.policy.args
	week := sim.week + 1
	demand := sim.signal(index, week, &incoming)
	switch name {
	case "FIXED":
		return args[0]
	case "PASS":
		return incoming[index]
	case "BASESTOCK":
		if args[0] > position {
			return args[0] - position
		}
		return 0
	case "MINMAX":
		if position <= args[0] {
			return args[1] - position
		}
		return 0
	case "MOVAVG":
		count := int(args[0])
		if count > week {
			count = week
		}
		var total int64
		for u := week - count + 1; u <= week; u++ {
			total += sim.signal(index, u, &incoming)
		}
		forecast := total / int64(count)
		delay := sim.initials[index].shipping + sim.initials[index].orders
		value := args[1] + forecast*int64(delay) - position
		if value > 0 {
			return value
		}
		return 0
	case "SMOOTH":
		value := demand + floorDiv(args[1]-position, args[0])
		if value > 0 {
			return value
		}
		return 0
	case "STERMAN":
		theta, alpha, beta, target := args[0], args[1], args[2], args[3]
		stage.expected = floorDiv(
			100*theta*demand+(100-theta)*stage.expected, 100)
		net := stage.inventory - stage.backlog
		value := floorDiv(100*stage.expected+
			alpha*(100*(target-net)-beta*line), 10000)
		if value > 0 {
			return value
		}
		return 0
	}
	return 0
}

func (sim *Simulation) step() [4]Record {
	var received [4]int64
	for i := range sim.stages {
		stage := &sim.stages[i]
		received[i] = stage.shipping[0]
		stage.shipping = stage.shipping[1:]
		stage.inventory += received[i]
	}
	incoming := [4]int64{
		sim.demands[sim.week], sim.stages[0].orders[0],
		sim.stages[1].orders[0], sim.stages[2].orders[0],
	}
	plantIncoming := sim.stages[3].orders[0]
	for i := range sim.stages {
		stage := &sim.stages[i]
		stage.orders = stage.orders[1:]
	}

	var records [4]Record
	for i := range sim.stages {
		stage := &sim.stages[i]
		before := stage.backlog
		requested := before + incoming[i]
		shipped := stage.inventory
		if requested < shipped {
			shipped = requested
		}
		if stage.capacity != nil && *stage.capacity < shipped {
			shipped = *stage.capacity
		}
		stage.inventory -= shipped
		stage.backlog = requested - shipped
		if i > 0 {
			sim.stages[i-1].shipping = append(sim.stages[i-1].shipping, shipped)
		}
		ontime := shipped - before
		if ontime < 0 {
			ontime = 0
		}
		if ontime > incoming[i] {
			ontime = incoming[i]
		}
		records[i] = Record{
			received: received[i], incoming: incoming[i], shipped: shipped,
			before: before, ontime: ontime, inventory: stage.inventory,
			backlog: stage.backlog,
		}
	}
	requested := sim.plantBacklog + plantIncoming
	produced := requested
	if sim.plantCapacity != nil && *sim.plantCapacity < produced {
		produced = *sim.plantCapacity
	}
	sim.plantBacklog = requested - produced
	sim.stages[3].shipping = append(sim.stages[3].shipping, produced)

	supply, positions := sim.positions()
	var orders [4]int64
	for i := range sim.stages {
		orders[i] = sim.policyOrder(i, incoming, supply[i], positions[i])
	}
	for i := range sim.stages {
		stage := &sim.stages[i]
		quantity := (orders[i] + stage.lot - 1) / stage.lot * stage.lot
		stage.orders = append(stage.orders, quantity)
		record := &records[i]
		record.order = quantity
		record.holding = stage.holding * stage.inventory
		record.backlogCost = stage.backlogRate * stage.backlog
		record.cost = record.holding + record.backlogCost
		stage.records = append(stage.records, *record)
	}
	sim.plantRecords = append(sim.plantRecords,
		PlantRecord{plantIncoming, produced, sim.plantBacklog})
	sim.week++
	return records
}

func (sim *Simulation) costs() [4]int64 {
	var result [4]int64
	for i := range sim.stages {
		result[i] = sim.stages[i].costs()
	}
	return result
}

type Game struct {
	initials [4]Setting
	base     []int64
	sim      *Simulation
	saved    map[string]*Simulation
	output   []string
}

func newGame(lines [4][]string) *Game {
	game := &Game{saved: make(map[string]*Simulation)}
	for i, tokens := range lines {
		policy, _ := parsePolicy(tokens[7:])
		game.initials[i] = Setting{
			inventory: parse(tokens[1]), quantity: parse(tokens[2]),
			shipping: int(parse(tokens[3])), orders: int(parse(tokens[4])),
			holding: parse(tokens[5]), backlog: parse(tokens[6]), policy: policy,
		}
	}
	game.initialize(nil)
	return game
}

func (game *Game) emit(parts ...any) {
	words := make([]string, len(parts))
	for i, part := range parts {
		words[i] = fmt.Sprint(part)
	}
	game.output = append(game.output, strings.Join(words, " "))
}

func stageIndex(name string) (int, error) {
	for i, stage := range stageNames {
		if name == stage {
			return i, nil
		}
	}
	return 0, fmt.Errorf("unknown stage %s", name)
}

func target(name string) ([]int, error) {
	if name == "ALL" {
		return []int{0, 1, 2, 3}, nil
	}
	index, err := stageIndex(name)
	if err != nil {
		return nil, err
	}
	return []int{index}, nil
}

func (game *Game) requireWeeks() error {
	if game.sim.week == 0 {
		return errors.New("no weeks simulated")
	}
	return nil
}

func rangeCheck(args []string, limit int) (int, int, error) {
	if len(args) == 0 {
		return 1, limit, nil
	}
	first, last := int(parse(args[0])), int(parse(args[1]))
	if first < 1 || first > last || last > limit {
		return 0, 0, fmt.Errorf("bad range %s %s", args[0], args[1])
	}
	return first, last, nil
}

func modeCheck(mode string) error {
	switch mode {
	case "ORDERS", "INV", "BACK", "NET":
		return nil
	}
	return fmt.Errorf("unknown mode %s", mode)
}

func (game *Game) values(index int, mode string) []int64 {
	values := []int64{}
	for _, record := range game.sim.stages[index].records {
		switch mode {
		case "ORDERS":
			values = append(values, record.order)
		case "INV":
			values = append(values, record.inventory)
		case "BACK":
			values = append(values, record.backlog)
		case "NET":
			values = append(values, record.inventory-record.backlog)
		}
	}
	return values
}

func (game *Game) initialize(demands []int64) {
	if demands != nil {
		game.base = append([]int64(nil), demands...)
	}
	game.sim = newSimulation(game.initials, game.base)
}

func (game *Game) trial(policies [4]Policy) *Simulation {
	current := game.sim
	trial := newSimulation(game.initials, current.demands)
	trial.visibility = current.visibility
	trial.plantCapacity = current.plantCapacity
	for i := range trial.stages {
		stage := &trial.stages[i]
		previous := &current.stages[i]
		stage.lot = previous.lot
		stage.capacity = previous.capacity
		stage.holding = previous.holding
		stage.backlogRate = previous.backlogRate
		trial.setPolicy(i, policies[i])
	}
	for trial.week < len(trial.demands) {
		trial.step()
	}
	return trial
}

func (game *Game) demand(values []int64) {
	game.initialize(values)
	minimum, maximum := values[0], values[0]
	for _, value := range values {
		if value < minimum {
			minimum = value
		}
		if value > maximum {
			maximum = value
		}
	}
	game.emit("DEMAND", "weeks", len(values), "total", sum(values),
		"min", minimum, "max", maximum)
}

func (game *Game) generate(args []string) error {
	weeks := int(parse(args[0]))
	base, spread, seed := parse(args[1]), parse(args[2]), parse(args[3])
	type Change struct {
		kind   string
		week   int
		amount int64
	}
	changes := []Change{}
	for i := 4; i < len(args); i += 3 {
		change := Change{args[i], int(parse(args[i+1])), parse(args[i+2])}
		if change.week < 1 || change.week > weeks {
			return fmt.Errorf("week %d outside horizon", change.week)
		}
		changes = append(changes, change)
	}
	levels := make([]int64, weeks)
	for week := 1; week <= weeks; week++ {
		level := base
		for _, change := range changes {
			switch change.kind {
			case "STEP":
				if week >= change.week {
					level += change.amount
				}
			case "PULSE":
				if week == change.week {
					level += change.amount
				}
			case "RAMP":
				if week >= change.week {
					level += change.amount * int64(week-change.week+1)
				}
			}
		}
		if level < 0 {
			return fmt.Errorf("negative level at week %d", week)
		}
		levels[week-1] = level
	}
	values := make([]int64, weeks)
	for i, level := range levels {
		seed = 48271 * seed % 2147483647
		values[i] = level + seed%spread
	}
	game.demand(values)
	return nil
}

func (game *Game) showStatus() {
	sim := game.sim
	game.emit("STATUS", "week", sim.week, "of", len(sim.demands))
	supply, position := sim.positions()
	for i, stage := range sim.stages {
		text := fmt.Sprintf(
			"%s inv %d back %d transit %s pending %s supply %d position %d policy %s",
			stageNames[i], stage.inventory, stage.backlog,
			pipelineText(stage.shipping), pipelineText(stage.orders),
			supply[i], position[i], stage.policy.text)
		if stage.policy.name == "STERMAN" {
			text += " expect " + money(stage.expected)
		}
		game.emit(text)
	}
	game.emit("PLANT", "back", sim.plantBacklog)
}

func (game *Game) showWeek(week int) {
	sim := game.sim
	game.emit("WEEK", week, "demand", sim.demands[week-1])
	for i, stage := range sim.stages {
		record := stage.records[week-1]
		game.emit(stageNames[i], "recv", record.received, "in", record.incoming,
			"ship", record.shipped, "inv", record.inventory, "back", record.backlog,
			"order", record.order, "cost", money(record.cost))
	}
	plant := sim.plantRecords[week-1]
	game.emit("PLANT", "in", plant.incoming, "made", plant.produced, "back", plant.backlog)
}

func right(text string, width int) string {
	return fmt.Sprintf("%*s", width, text)
}

func (game *Game) showTable(index, first, last int) {
	game.emit("TABLE", stageNames[index], fmt.Sprintf("%d-%d", first, last))
	labels := []string{"week", "in", "ship", "recv", "inv", "back", "order", "cost"}
	widths := []int{4, 6, 6, 6, 6, 6, 6, 9}
	fields := make([]string, len(labels))
	for i, label := range labels {
		fields[i] = right(label, widths[i])
	}
	game.emit(strings.Join(fields, " "))
	for week := first; week <= last; week++ {
		record := game.sim.stages[index].records[week-1]
		values := []string{
			fmt.Sprint(week), fmt.Sprint(record.incoming), fmt.Sprint(record.shipped),
			fmt.Sprint(record.received), fmt.Sprint(record.inventory),
			fmt.Sprint(record.backlog), fmt.Sprint(record.order), money(record.cost),
		}
		for i, value := range values {
			fields[i] = right(value, widths[i])
		}
		game.emit(strings.Join(fields, " "))
	}
}

func (game *Game) showCosts() {
	game.emit("COSTS", "week", game.sim.week)
	var totalHolding, totalBacklog int64
	for i, stage := range game.sim.stages {
		var holding, backlog int64
		for _, record := range stage.records {
			holding += record.holding
			backlog += record.backlogCost
		}
		totalHolding += holding
		totalBacklog += backlog
		game.emit(stageNames[i], "holding", money(holding), "backlog", money(backlog),
			"total", money(holding+backlog))
	}
	game.emit("TOTAL", "holding", money(totalHolding),
		"backlog", money(totalBacklog), "total", money(totalHolding+totalBacklog))
}

func fillText(records []Record) (int64, int64, string) {
	var ordered, ontime int64
	for _, record := range records {
		ordered += record.incoming
		ontime += record.ontime
	}
	fill := "n/a"
	if ordered != 0 {
		fill = decimal(ontime*100, ordered, 2) + "%"
	}
	return ordered, ontime, fill
}

func (game *Game) bullwhip() {
	sim := game.sim
	n := sim.week
	demands := sim.demands[:n]
	demandVar := variation(demands)
	game.emit("BULLWHIP", "weeks", fmt.Sprintf("1-%d", n), "demand",
		"mean", decimal(sum(demands), int64(n), 4),
		"var", decimal(demandVar, int64(n*n), 4))
	previous := demandVar
	for i, stage := range sim.stages {
		values := make([]int64, len(stage.records))
		for j, record := range stage.records {
			values[j] = record.order
		}
		current := variation(values)
		ratio := "n/a"
		step := "n/a"
		if demandVar != 0 {
			ratio = decimal(current, demandVar, 4)
		}
		if previous != 0 {
			step = decimal(current, previous, 4)
		}
		game.emit(stageNames[i], "mean", decimal(sum(values), int64(n), 4),
			"var", decimal(current, int64(n*n), 4), "ratio", ratio, "step", step)
		previous = current
	}
}

func (game *Game) peaks() {
	sim := game.sim
	game.emit("PEAKS", "weeks", fmt.Sprintf("1-%d", sim.week))
	for i, stage := range sim.stages {
		maxInventory, maxBacklog := int64(0), int64(0)
		inventoryWeek, backlogWeek := 0, 0
		longest, run, first, bestFirst, bestLast := 0, 0, 0, 0, 0
		for week, record := range stage.records {
			t := week + 1
			if record.inventory > maxInventory {
				maxInventory = record.inventory
				inventoryWeek = t
			}
			if record.backlog > maxBacklog {
				maxBacklog = record.backlog
				backlogWeek = t
			}
			if record.backlog > 0 {
				if run == 0 {
					first = t
				}
				run++
				if run > longest {
					longest, bestFirst, bestLast = run, first, t
				}
			} else {
				run = 0
			}
		}
		inventoryText, backlogText, longestText := "-", "-", "0"
		if inventoryWeek != 0 {
			inventoryText = fmt.Sprint(inventoryWeek)
		}
		if backlogWeek != 0 {
			backlogText = fmt.Sprint(backlogWeek)
		}
		if longest != 0 {
			longestText = fmt.Sprintf("%d weeks %d-%d", longest, bestFirst, bestLast)
		}
		game.emit(stageNames[i], "max_inv", maxInventory, "week", inventoryText,
			"max_back", maxBacklog, "week", backlogText,
			"longest_stockout", longestText)
	}
}

func (game *Game) leadtime(index int) {
	sim := game.sim
	stage := &sim.stages[index]
	initial := game.initials[index]
	nominal := initial.shipping + initial.orders
	cumulative := make([]int64, len(stage.records))
	var received int64
	for i, record := range stage.records {
		received += record.received
		cumulative[i] = received - int64(nominal)*initial.quantity
	}
	var ordered int64
	count := 0
	leads := []int64{}
	for t, record := range stage.records {
		ordered += record.order
		if record.order == 0 {
			continue
		}
		count++
		for u := t + 1; u < len(stage.records); u++ {
			if cumulative[u] >= ordered {
				leads = append(leads, int64(u-t))
				break
			}
		}
	}
	minimum, average, maximum := "-", "-", "-"
	if len(leads) > 0 {
		min, max := leads[0], leads[0]
		for _, value := range leads {
			if value < min {
				min = value
			}
			if value > max {
				max = value
			}
		}
		minimum, maximum = fmt.Sprint(min), fmt.Sprint(max)
		average = decimal(sum(leads), int64(len(leads)), 2)
	}
	game.emit("LEADTIME", stageNames[index], "nominal", nominal,
		"orders", count, "completed", len(leads), "open", count-len(leads),
		"min", minimum, "avg", average, "max", maximum)
}

func (game *Game) plot(index int, mode string, first, last int) {
	values := game.values(index, mode)[first-1 : last]
	maximum, minimum := values[0], values[0]
	for _, value := range values {
		if value > maximum {
			maximum = value
		}
		if value < minimum {
			minimum = value
		}
	}
	if mode == "NET" {
		game.emit("PLOT", stageNames[index], mode,
			fmt.Sprintf("%d-%d", first, last), "min", minimum, "max", maximum)
		var scale int64
		for _, value := range values {
			if value < 0 {
				value = -value
			}
			if value > scale {
				scale = value
			}
		}
		for i, value := range values {
			size := 0
			if scale != 0 {
				abs := value
				if abs < 0 {
					abs = -abs
				}
				size = int(abs * 25 / scale)
			}
			left := strings.Repeat(" ", 25)
			rightBar := ""
			if value < 0 {
				left = strings.Repeat(" ", 25-size) + strings.Repeat("-", size)
			} else if value > 0 {
				rightBar = strings.Repeat("+", size)
			}
			game.emit(fmt.Sprintf("%3d %s|%s %d", first+i, left, rightBar, value))
		}
	} else {
		game.emit("PLOT", stageNames[index], mode,
			fmt.Sprintf("%d-%d", first, last), "max", maximum)
		for i, value := range values {
			size := 0
			if maximum != 0 {
				size = int(value * 50 / maximum)
			}
			game.emit(fmt.Sprintf("%3d |%s %d",
				first+i, strings.Repeat("#", size), value))
		}
	}
}

func (game *Game) histogram(index int, mode string, width int64) {
	values := game.values(index, mode)
	bins := make(map[int64]int)
	var min, max int64
	for i, value := range values {
		bucket := floorDiv(value, width)
		bins[bucket]++
		if i == 0 || bucket < min {
			min = bucket
		}
		if i == 0 || bucket > max {
			max = bucket
		}
	}
	game.emit("HISTOGRAM", stageNames[index], mode, "width", width,
		"weeks", fmt.Sprintf("1-%d", game.sim.week))
	for bucket := min; bucket <= max; bucket++ {
		count := bins[bucket]
		text := fmt.Sprintf("%d..%d %d", bucket*width, bucket*width+width-1, count)
		if count != 0 {
			text += " " + strings.Repeat("*", count)
		}
		game.emit(text)
	}
}

func (game *Game) command(words []string) error {
	command, args := words[0], words[1:]
	sim := game.sim
	switch command {
	case "DEMAND":
		values := make([]int64, len(args))
		for i, token := range args {
			values[i] = parse(token)
		}
		game.demand(values)
	case "GENERATE":
		return game.generate(args)
	case "RUN":
		if sim.week == len(sim.demands) {
			return fmt.Errorf("horizon reached at week %d", len(sim.demands))
		}
		first := sim.week + 1
		count := int(parse(args[0]))
		if count > len(sim.demands)-sim.week {
			count = len(sim.demands) - sim.week
		}
		var cost int64
		for t := 0; t < count; t++ {
			records := sim.step()
			for i, record := range records {
				cost += record.cost
				if record.before == 0 && record.backlog > 0 {
					game.emit("STOCKOUT", stageNames[i], "week", sim.week,
						"backlog", record.backlog)
				} else if record.before > 0 && record.backlog == 0 {
					game.emit("RECOVER", stageNames[i], "week", sim.week)
				}
			}
		}
		game.emit("RUN", fmt.Sprintf("%d-%d", first, sim.week),
			"demand", sum(sim.demands[first-1:sim.week]), "cost", money(cost))
		if sim.week == len(sim.demands) {
			game.emit("HORIZON", sim.week)
		}
	case "RESET":
		game.initialize(nil)
		game.emit("RESET", "week", 0)
	case "SAVE":
		game.saved[args[0]] = sim.clone()
		game.emit("SAVE", args[0], "week", sim.week)
	case "LOAD":
		snapshot := game.saved[args[0]]
		if snapshot == nil {
			return fmt.Errorf("no snapshot %s", args[0])
		}
		game.sim = snapshot.clone()
		game.emit("LOAD", args[0], "week", game.sim.week)
	case "SET":
		indices, err := target(args[0])
		if err != nil {
			return err
		}
		policy, err := parsePolicy(args[1:])
		if err != nil {
			return err
		}
		for _, index := range indices {
			sim.setPolicy(index, policy)
		}
		game.emit("SET", args[0], policy.text)
	case "BATCH":
		index, err := stageIndex(args[0])
		if err != nil {
			return err
		}
		lot := parse(args[1])
		if lot < 1 || lot > 100 {
			return fmt.Errorf("invalid batch size %s", args[1])
		}
		sim.stages[index].lot = lot
		game.emit("BATCH", args[0], lot)
	case "CAPACITY":
		index := -1
		if args[0] != "PLANT" {
			var err error
			index, err = stageIndex(args[0])
			if err != nil {
				return err
			}
		}
		var capacity *int64
		if args[1] != "OFF" {
			value := parse(args[1])
			if value > 10000 {
				return fmt.Errorf("invalid capacity %s", args[1])
			}
			capacity = &value
		}
		if index < 0 {
			sim.plantCapacity = capacity
		} else {
			sim.stages[index].capacity = capacity
		}
		game.emit("CAPACITY", args[0], args[1])
	case "COST":
		index, err := stageIndex(args[0])
		if err != nil {
			return err
		}
		holding, backlog := parse(args[1]), parse(args[2])
		if holding > 1000 || backlog > 1000 {
			return errors.New("invalid cost")
		}
		sim.stages[index].holding = holding
		sim.stages[index].backlogRate = backlog
		game.emit("COST", args[0], "holding", holding, "backlog", backlog)
	case "VISIBILITY":
		if args[0] != "ON" && args[0] != "OFF" {
			return fmt.Errorf("unknown visibility %s", args[0])
		}
		sim.visibility = args[0]
		game.emit("VISIBILITY", args[0])
	case "SHOCK":
		week := int(parse(args[0]))
		value := parse(args[1])
		if week < 1 || week > len(sim.demands) {
			return fmt.Errorf("week %s outside horizon", args[0])
		}
		if week <= sim.week {
			return fmt.Errorf("week %s already simulated", args[0])
		}
		old := sim.demands[week-1]
		sim.demands[week-1] = value
		game.emit("SHOCK", "week", week, old, "->", value)
	case "STATUS":
		game.showStatus()
	case "SETTINGS":
		game.emit("SETTINGS")
		for i, stage := range sim.stages {
			capacity := "OFF"
			if stage.capacity != nil {
				capacity = fmt.Sprint(*stage.capacity)
			}
			initial := game.initials[i]
			game.emit(stageNames[i], "holding", stage.holding,
				"backlog", stage.backlogRate, "batch", stage.lot,
				"capacity", capacity, "delays", initial.shipping, initial.orders)
		}
		capacity := "OFF"
		if sim.plantCapacity != nil {
			capacity = fmt.Sprint(*sim.plantCapacity)
		}
		game.emit("PLANT", "capacity", capacity)
		game.emit("VISIBILITY", sim.visibility)
	case "WEEK":
		if err := game.requireWeeks(); err != nil {
			return err
		}
		week := int(parse(args[0]))
		if week < 1 || week > sim.week {
			return fmt.Errorf("bad week %s", args[0])
		}
		game.showWeek(week)
	case "TABLE":
		index, err := stageIndex(args[0])
		if err != nil {
			return err
		}
		if err := game.requireWeeks(); err != nil {
			return err
		}
		first, last, err := rangeCheck(args[1:], sim.week)
		if err != nil {
			return err
		}
		game.showTable(index, first, last)
	case "CHAIN":
		if err := game.requireWeeks(); err != nil {
			return err
		}
		first, last, err := rangeCheck(args, sim.week)
		if err != nil {
			return err
		}
		game.emit("CHAIN", fmt.Sprintf("%d-%d", first, last))
		header := []string{right("week", 4), right("demand", 6)}
		for _, stage := range stageNames {
			header = append(header, right(stage, 11))
		}
		game.emit(strings.Join(header, " "))
		for week := first; week <= last; week++ {
			fields := []string{right(fmt.Sprint(week), 4),
				right(fmt.Sprint(sim.demands[week-1]), 6)}
			for _, stage := range sim.stages {
				fields = append(fields,
					right(fmt.Sprint(stage.records[week-1].order), 11))
			}
			game.emit(strings.Join(fields, " "))
		}
	case "DEMANDS":
		first, last, err := rangeCheck(args, len(sim.demands))
		if err != nil {
			return err
		}
		values := sim.demands[first-1 : last]
		minimum, maximum := values[0], values[0]
		for _, value := range values {
			if value < minimum {
				minimum = value
			}
			if value > maximum {
				maximum = value
			}
		}
		game.emit("DEMANDS", fmt.Sprintf("%d-%d", first, last),
			"total", sum(values), "min", minimum, "max", maximum)
		parts := make([]string, len(values))
		for i, value := range values {
			parts[i] = fmt.Sprint(value)
		}
		game.emit(strings.Join(parts, " "))
	case "COSTS":
		game.showCosts()
	case "SUMMARY":
		if err := game.requireWeeks(); err != nil {
			return err
		}
		game.emit("SUMMARY", "weeks", fmt.Sprintf("1-%d", sim.week))
		for i, stage := range sim.stages {
			var inv, back, orders int64
			minimum, maximum := stage.records[0].order, stage.records[0].order
			zeroWeeks := 0
			for _, record := range stage.records {
				inv += record.inventory
				back += record.backlog
				orders += record.order
				if record.order < minimum {
					minimum = record.order
				}
				if record.order > maximum {
					maximum = record.order
				}
				if record.order == 0 {
					zeroWeeks++
				}
			}
			game.emit(stageNames[i],
				"avg_inv", decimal(inv, int64(sim.week), 2),
				"avg_back", decimal(back, int64(sim.week), 2),
				"orders", orders, "min", minimum, "max", maximum,
				"zero_weeks", zeroWeeks)
		}
	case "BALANCE":
		game.emit("BALANCE", "week", sim.week)
		var initialGoods, produced, delivered, stock, transit int64
		for i, stage := range sim.stages {
			var received, shipped int64
			for _, record := range stage.records {
				received += record.received
				shipped += record.shipped
			}
			game.emit(stageNames[i], "start", game.initials[i].inventory,
				"received", received, "shipped", shipped,
				"end", stage.inventory, "owed", stage.backlog)
			initial := game.initials[i]
			initialGoods += initial.inventory + initial.quantity*int64(initial.shipping)
			if i == 0 {
				delivered = shipped
			}
			stock += stage.inventory
			transit += sum(stage.shipping)
		}
		for _, record := range sim.plantRecords {
			produced += record.produced
		}
		game.emit("SYSTEM", "initial", initialGoods, "produced", produced,
			"delivered", delivered, "stock", stock, "transit", transit)
	case "FILLRATE":
		if err := game.requireWeeks(); err != nil {
			return err
		}
		game.emit("FILLRATE", "weeks", fmt.Sprintf("1-%d", sim.week))
		for i, stage := range sim.stages {
			ordered, ontime, fill := fillText(stage.records)
			stockouts := 0
			for _, record := range stage.records {
				if record.backlog > 0 {
					stockouts++
				}
			}
			service := decimal(int64(sim.week-stockouts)*100, int64(sim.week), 2) + "%"
			game.emit(stageNames[i], "fill", fill, "ontime", ontime,
				"ordered", ordered, "stockout_weeks", stockouts, "service", service)
		}
	case "BULLWHIP":
		if err := game.requireWeeks(); err != nil {
			return err
		}
		game.bullwhip()
	case "PEAKS":
		if err := game.requireWeeks(); err != nil {
			return err
		}
		game.peaks()
	case "LEADTIME":
		index, err := stageIndex(args[0])
		if err != nil {
			return err
		}
		if err := game.requireWeeks(); err != nil {
			return err
		}
		game.leadtime(index)
	case "PLOT", "HISTOGRAM":
		index, err := stageIndex(args[0])
		if err != nil {
			return err
		}
		if err := modeCheck(args[1]); err != nil {
			return err
		}
		width := int64(0)
		if command == "HISTOGRAM" {
			width = parse(args[2])
			if width < 1 || width > 100 {
				return fmt.Errorf("invalid width %s", args[2])
			}
		}
		if err := game.requireWeeks(); err != nil {
			return err
		}
		if command == "PLOT" {
			first, last, err := rangeCheck(args[2:], sim.week)
			if err != nil {
				return err
			}
			game.plot(index, args[1], first, last)
		} else {
			game.histogram(index, args[1], width)
		}
	case "COMPARE":
		policies := []Policy{}
		start := 0
		for end := 0; end <= len(args); end++ {
			if end == len(args) || args[end] == "/" {
				policy, err := parsePolicy(args[start:end])
				if err != nil {
					return err
				}
				policies = append(policies, policy)
				start = end + 1
			}
		}
		type Row struct {
			cost, index int64
			policy      string
			fill        string
			ratio       string
		}
		rows := []Row{}
		for i, policy := range policies {
			selected := [4]Policy{policy, policy, policy, policy}
			trial := game.trial(selected)
			costs := trial.costs()
			var cost int64
			for _, value := range costs {
				cost += value
			}
			_, _, fill := fillText(trial.stages[0].records)
			demandVar := variation(trial.demands)
			factoryOrders := make([]int64, len(trial.stages[3].records))
			for j, record := range trial.stages[3].records {
				factoryOrders[j] = record.order
			}
			factoryVar := variation(factoryOrders)
			ratio := "n/a"
			if demandVar != 0 {
				ratio = decimal(factoryVar, demandVar, 4)
			}
			rows = append(rows, Row{cost, int64(i), policy.text, fill, ratio})
		}
		sort.Slice(rows, func(i, j int) bool {
			if rows[i].cost != rows[j].cost {
				return rows[i].cost < rows[j].cost
			}
			return rows[i].index < rows[j].index
		})
		game.emit("COMPARE", len(policies), "weeks", len(sim.demands))
		for i, row := range rows {
			game.emit(i+1, row.policy, "total", money(row.cost),
				"fill", row.fill, "bullwhip", row.ratio)
		}
	case "OPTIMIZE":
		indices, err := target(args[0])
		if err != nil {
			return err
		}
		low, high := int(parse(args[1])), int(parse(args[2]))
		if low > high {
			return fmt.Errorf("bad range %s %s", args[1], args[2])
		}
		if high-low > 200 {
			return errors.New("range too large")
		}
		var bestCost, bestTotal int64
		bestTarget := low
		first := true
		for value := low; value <= high; value++ {
			var policies [4]Policy
			for i, stage := range sim.stages {
				policies[i] = stage.policy
			}
			replacement := Policy{"BASESTOCK", []int64{int64(value)},
				fmt.Sprintf("BASESTOCK %d", value)}
			for _, index := range indices {
				policies[index] = replacement
			}
			trial := game.trial(policies)
			costs := trial.costs()
			var objective, totalCost int64
			for _, index := range indices {
				objective += costs[index]
			}
			for _, value := range costs {
				totalCost += value
			}
			if first || objective < bestCost {
				bestCost, bestTotal, bestTarget = objective, totalCost, value
				first = false
			}
		}
		game.emit("OPTIMIZE", args[0], "BASESTOCK", bestTarget,
			"cost", money(bestCost), "total", money(bestTotal))
	default:
		return fmt.Errorf("unknown command %s", command)
	}
	return nil
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var lines [4][]string
	for i := range lines {
		scanner.Scan()
		lines[i] = strings.Fields(scanner.Text())
	}
	game := newGame(lines)
	for scanner.Scan() {
		words := strings.Fields(scanner.Text())
		if len(words) == 0 {
			continue
		}
		if words[0] == "END" {
			break
		}
		if err := game.command(words); err != nil {
			game.emit("ERROR", err.Error())
		}
	}
	writer := bufio.NewWriter(os.Stdout)
	defer writer.Flush()
	for _, line := range game.output {
		fmt.Fprintln(writer, line)
	}
}
