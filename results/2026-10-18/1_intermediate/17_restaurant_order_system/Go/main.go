package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var stationNames = []string{"GRILL", "FRY", "COLD", "BAR"}
var courseNames = []string{"DRINK", "STARTER", "MAIN", "DESSERT"}

func integer(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func cents(text string) int {
	return integer(strings.ReplaceAll(text, ".", ""))
}

func money(value int) string {
	return fmt.Sprintf("%d.%02d", value/100, value%100)
}

func clock(time int) string {
	minutes := 660 + time
	return fmt.Sprintf("%02d:%02d", minutes/60, minutes%60)
}

func rounded(value, rate int) int {
	return (value*rate + 50) / 100
}

type Table struct {
	Number int
	Seats  int
	Check  *Check
}

type Server struct {
	Name    string
	Parties int
	Sales   int
	Tips    int
}

type MenuItem struct {
	Name    string
	Station string
	Prep    int
	Price   int
	Course  string
	Stock   *int
}

type Check struct {
	Party    string
	Size     int
	Table    *Table
	Server   *Server
	Seated   int
	Lines    []*OrderLine
	Paid     int
	Discount int
	Closed   bool
}

func (check *Check) active() []*OrderLine {
	active := make([]*OrderLine, 0, len(check.Lines))
	for _, line := range check.Lines {
		if line.State != "VOID" {
			active = append(active, line)
		}
	}
	return active
}

type OrderLine struct {
	Number   int
	Check    *Check
	Seat     int
	Item     string
	Quantity int
	Station  string
	Prep     int
	Price    int
	Course   string
	State    string
	Reason   string
	Fire     int
	Ready    int
	Started  bool
}

func (line *OrderLine) amount() int {
	if line.Reason != "" {
		return 0
	}
	return line.Price * line.Quantity
}

type Station struct {
	Name     string
	Capacity int
	Up       bool
	Queue    []*OrderLine
	Cooking  []*OrderLine
	Tickets  []int
	Remakes  int
}

type WaitingParty struct {
	Party  string
	Size   int
	Joined int
}

type Amounts struct {
	Subtotal int
	Discount int
	Service  int
	Tax      int
	Total    int
	Due      int
}

type Restaurant struct {
	Now        int
	Tables     map[int]*Table
	Servers    []*Server
	Waiting    []WaitingParty
	Menu       map[string]*MenuItem
	Lines      []*OrderLine
	Stations   map[string]*Station
	HappyRate  int
	HappyEnd   int
	Covers     int
	Parties    int
	Turns      int
	Stay       int
	Sales      map[string]int
	Totals     map[string]int
	Payments   map[string]int
	Tips       int
	Comps      int
	CompAmount int
	Voids      int
	Served     map[string]int
	Output     []string
}

func newRestaurant() *Restaurant {
	r := &Restaurant{
		Tables:   make(map[int]*Table),
		Menu:     make(map[string]*MenuItem),
		Stations: make(map[string]*Station),
		Sales:    make(map[string]int),
		Totals:   make(map[string]int),
		Payments: make(map[string]int),
		Served:   make(map[string]int),
	}
	for _, name := range stationNames {
		capacity := 1
		if name == "BAR" {
			capacity = 2
		}
		r.Stations[name] = &Station{Name: name, Capacity: capacity, Up: true}
	}
	for _, name := range courseNames {
		r.Sales[name] = 0
	}
	return r
}

func (r *Restaurant) emit(parts ...any) {
	fields := make([]string, len(parts))
	for i, part := range parts {
		fields[i] = fmt.Sprint(part)
	}
	r.Output = append(r.Output, strings.Join(fields, " "))
}

func (r *Restaurant) table(text string) (*Table, error) {
	table := r.Tables[integer(text)]
	if table == nil {
		return nil, fmt.Errorf("unknown table %s", text)
	}
	return table, nil
}

func (r *Restaurant) check(text string) (*Check, error) {
	table, err := r.table(text)
	if err != nil {
		return nil, err
	}
	if table.Check == nil {
		return nil, fmt.Errorf("table %s is free", text)
	}
	return table.Check, nil
}

func (r *Restaurant) line(text string) (*OrderLine, error) {
	number := integer(text)
	if number < 1 || number > len(r.Lines) {
		return nil, fmt.Errorf("unknown line %s", text)
	}
	return r.Lines[number-1], nil
}

func (r *Restaurant) station(name string) (*Station, error) {
	station := r.Stations[name]
	if station == nil {
		return nil, fmt.Errorf("unknown station %s", name)
	}
	return station, nil
}

func requireCourse(name string) error {
	for _, course := range courseNames {
		if course == name {
			return nil
		}
	}
	return fmt.Errorf("unknown course %s", name)
}

func (r *Restaurant) item(name string) (*MenuItem, error) {
	item := r.Menu[name]
	if item == nil {
		return nil, fmt.Errorf("unknown item %s", name)
	}
	return item, nil
}

func unlocked(check *Check) error {
	if check.Paid > 0 {
		return fmt.Errorf("check for table %d is locked", check.Table.Number)
	}
	return nil
}

func modifiable(line *OrderLine) error {
	if line.State == "VOID" {
		return fmt.Errorf("#%d is void", line.Number)
	}
	if line.Check.Closed {
		return fmt.Errorf("#%d is on a closed check", line.Number)
	}
	return unlocked(line.Check)
}

func unserved(check *Check) error {
	count := 0
	for _, line := range check.active() {
		if line.State != "SERVED" {
			count++
		}
	}
	if count != 0 {
		return fmt.Errorf("table %d has %d unserved items", check.Table.Number, count)
	}
	return nil
}

func (r *Restaurant) load(server *Server) int {
	count := 0
	for _, table := range r.Tables {
		if table.Check != nil && table.Check.Server == server {
			count++
		}
	}
	return count
}

func (r *Restaurant) selectTable(size int) *Table {
	var best *Table
	for _, table := range r.Tables {
		if table.Check != nil || table.Seats < size {
			continue
		}
		if best == nil || table.Seats < best.Seats ||
			table.Seats == best.Seats && table.Number < best.Number {
			best = table
		}
	}
	return best
}

func (r *Restaurant) seat(party string, size int, table *Table) *Check {
	server := r.Servers[0]
	for _, candidate := range r.Servers {
		if r.load(candidate) < r.load(server) {
			server = candidate
		}
	}
	check := &Check{
		Party: party, Size: size, Table: table, Server: server, Seated: r.Now,
	}
	table.Check = check
	server.Parties++
	r.Covers += size
	r.Parties++
	return check
}

func (r *Restaurant) processWaiting() {
	remaining := make([]WaitingParty, 0, len(r.Waiting))
	for _, entry := range r.Waiting {
		table := r.selectTable(entry.Size)
		if table == nil {
			remaining = append(remaining, entry)
			continue
		}
		check := r.seat(entry.Party, entry.Size, table)
		r.emit("SEATED", entry.Party, entry.Size, "table", table.Number,
			"server", check.Server.Name, "waited", r.Now-entry.Joined)
	}
	r.Waiting = remaining
}

func calculate(check *Check) Amounts {
	result := Amounts{}
	for _, line := range check.active() {
		result.Subtotal += line.amount()
	}
	result.Discount = rounded(result.Subtotal, check.Discount)
	after := result.Subtotal - result.Discount
	if check.Size >= 6 {
		result.Service = rounded(after, 18)
	}
	result.Tax = rounded(after, 8)
	result.Total = after + result.Service + result.Tax
	result.Due = result.Total - check.Paid
	return result
}

func (r *Restaurant) close(check *Check) {
	amounts := calculate(check)
	r.Turns++
	r.Stay += r.Now - check.Seated
	for _, line := range check.active() {
		r.Sales[line.Course] += line.amount()
	}
	r.Totals["subtotal"] += amounts.Subtotal
	r.Totals["discount"] += amounts.Discount
	r.Totals["service"] += amounts.Service
	r.Totals["tax"] += amounts.Tax
	r.Totals["total"] += amounts.Total
	check.Server.Sales += amounts.Total
	check.Closed = true
	check.Table.Check = nil
	r.emit("FREE", "table", check.Table.Number, check.Party, "stayed", r.Now-check.Seated)
	r.processWaiting()
}

func start(station *Station, time int) {
	for station.Up && len(station.Queue) != 0 &&
		len(station.Cooking) < station.Capacity {
		line := station.Queue[0]
		station.Queue = station.Queue[1:]
		line.State = "COOKING"
		line.Ready = time + line.Prep
		line.Started = true
		station.Cooking = append(station.Cooking, line)
	}
}

func (r *Restaurant) tick(minutes int) {
	end := r.Now + minutes
	r.emit("TICK", clock(end))
	for {
		var earliest int
		found := false
		for _, name := range stationNames {
			for _, line := range r.Stations[name].Cooking {
				if !found || line.Ready < earliest {
					earliest, found = line.Ready, true
				}
			}
		}
		if !found || earliest > end {
			break
		}
		for _, name := range stationNames {
			station := r.Stations[name]
			var finished, remaining []*OrderLine
			for _, line := range station.Cooking {
				if line.Ready == earliest {
					finished = append(finished, line)
				} else {
					remaining = append(remaining, line)
				}
			}
			station.Cooking = remaining
			sort.Slice(finished, func(i, j int) bool {
				return finished[i].Number < finished[j].Number
			})
			for _, line := range finished {
				line.State = "READY"
				station.Tickets = append(station.Tickets, earliest-line.Fire)
				r.emit("READY", clock(earliest), name, "#"+strconv.Itoa(line.Number),
					line.Item, "x"+strconv.Itoa(line.Quantity), "table",
					line.Check.Table.Number, "seat", line.Seat)
			}
		}
		for _, name := range stationNames {
			start(r.Stations[name], earliest)
		}
	}
	r.Now = end
}

func seatSubtotals(check *Check) map[int]int {
	result := make(map[int]int)
	for _, line := range check.active() {
		result[line.Seat] += line.amount()
	}
	return result
}

func sortedSeats(values map[int]int) []int {
	seats := make([]int, 0, len(values))
	for seat := range values {
		seats = append(seats, seat)
	}
	sort.Ints(seats)
	return seats
}

func allocate(values map[int]int, rate int) map[int]int {
	result := make(map[int]int, len(values))
	total, assigned := 0, 0
	for seat, value := range values {
		result[seat] = value * rate / 100
		total += value
		assigned += result[seat]
	}
	extra := rounded(total, rate) - assigned
	order := sortedSeats(values)
	sort.Slice(order, func(i, j int) bool {
		a, b := order[i], order[j]
		left, right := values[a]*rate%100, values[b]*rate%100
		if left != right {
			return left > right
		}
		return a < b
	})
	for _, seat := range order[:extra] {
		result[seat]++
	}
	return result
}

func (r *Restaurant) bill(check *Check) {
	r.emit("BILL", "table", check.Table.Number, check.Party, "guests", check.Size)
	values := seatSubtotals(check)
	for _, seat := range sortedSeats(values) {
		r.emit("SEAT", seat, money(values[seat]))
		for _, line := range check.active() {
			if line.Seat != seat {
				continue
			}
			parts := []any{
				"#" + strconv.Itoa(line.Number), line.Item,
				"x" + strconv.Itoa(line.Quantity), money(line.amount()),
			}
			if line.Reason != "" {
				parts = append(parts, "COMP", line.Reason)
			}
			r.emit(parts...)
		}
	}
	amounts := calculate(check)
	r.emit("SUBTOTAL", money(amounts.Subtotal))
	if check.Discount != 0 {
		r.emit("DISCOUNT", strconv.Itoa(check.Discount)+"%", money(amounts.Discount))
	}
	if check.Size >= 6 {
		r.emit("SERVICE", money(amounts.Service))
	}
	r.emit("TAX", money(amounts.Tax))
	r.emit("TOTAL", money(amounts.Total))
	if check.Paid > 0 {
		r.emit("PAID", money(check.Paid))
		r.emit("DUE", money(amounts.Due))
	}
}

func (r *Restaurant) report() {
	r.emit("REPORT", clock(r.Now))
	r.emit("COVERS", r.Covers, "parties", r.Parties)
	stay := "-"
	if r.Turns != 0 {
		stay = strconv.Itoa(r.Stay / r.Turns)
	}
	r.emit("TURNS", r.Turns, "avg_stay", stay)
	sales := []any{"SALES"}
	for _, course := range courseNames {
		sales = append(sales, course, money(r.Sales[course]))
	}
	r.emit(sales...)
	totals := []any{"TOTALS"}
	for _, name := range []string{"subtotal", "discount", "service", "tax", "total"} {
		totals = append(totals, name, money(r.Totals[name]))
	}
	r.emit(totals...)
	r.emit("PAYMENTS", "cash", money(r.Payments["CASH"]),
		"card", money(r.Payments["CARD"]), "tips", money(r.Tips))
	r.emit("COMPS", r.Comps, money(r.CompAmount), "VOIDS", r.Voids)
	names := make([]string, 0, len(r.Served))
	for name, count := range r.Served {
		if count > 0 {
			names = append(names, name)
		}
	}
	sort.Slice(names, func(i, j int) bool {
		if r.Served[names[i]] != r.Served[names[j]] {
			return r.Served[names[i]] > r.Served[names[j]]
		}
		return names[i] < names[j]
	})
	for i := 0; i < len(names) && i < 3; i++ {
		r.emit("TOP", i+1, names[i], r.Served[names[i]])
	}
	for _, name := range stationNames {
		station := r.Stations[name]
		if len(station.Tickets) == 0 {
			r.emit(name, "tickets", 0, "avg", "-", "max", "-", "remakes", station.Remakes)
			continue
		}
		sum, maximum := 0, 0
		for _, ticket := range station.Tickets {
			sum += ticket
			if ticket > maximum {
				maximum = ticket
			}
		}
		r.emit(name, "tickets", len(station.Tickets), "avg", sum/len(station.Tickets),
			"max", maximum, "remakes", station.Remakes)
	}
	for _, server := range r.Servers {
		r.emit("SERVER", server.Name, "tables", r.load(server),
			"parties", server.Parties, "sales", money(server.Sales),
			"tips", money(server.Tips))
	}
}

func (r *Restaurant) command(cmd string, a []string) error {
	switch cmd {
	case "TABLE":
		number := integer(a[0])
		if r.Tables[number] != nil {
			return fmt.Errorf("table %s already exists", a[0])
		}
		r.Tables[number] = &Table{Number: number, Seats: integer(a[1])}
		r.emit("TABLE", number, "seats", integer(a[1]))
		r.processWaiting()

	case "STAFF":
		for _, server := range r.Servers {
			if server.Name == a[0] {
				return fmt.Errorf("%s is already on duty", a[0])
			}
		}
		r.Servers = append(r.Servers, &Server{Name: a[0]})
		r.emit("STAFF", a[0])

	case "SEAT":
		for _, table := range r.Tables {
			if table.Check != nil && table.Check.Party == a[0] {
				return fmt.Errorf("%s is already seated at table %d", a[0], table.Number)
			}
		}
		for _, party := range r.Waiting {
			if party.Party == a[0] {
				return fmt.Errorf("%s is already waiting", a[0])
			}
		}
		size := integer(a[1])
		accommodates := false
		for _, table := range r.Tables {
			if table.Seats >= size {
				accommodates = true
				break
			}
		}
		if !accommodates {
			return fmt.Errorf("no table for party of %d", size)
		}
		if len(r.Servers) == 0 {
			return fmt.Errorf("no server on duty")
		}
		if table := r.selectTable(size); table != nil {
			check := r.seat(a[0], size, table)
			r.emit("SEAT", a[0], size, "table", table.Number, "server", check.Server.Name)
		} else {
			r.Waiting = append(r.Waiting, WaitingParty{a[0], size, r.Now})
			r.emit("WAIT", a[0], size, "position", len(r.Waiting))
		}

	case "CANCEL":
		for i, party := range r.Waiting {
			if party.Party == a[0] {
				r.Waiting = append(r.Waiting[:i], r.Waiting[i+1:]...)
				r.emit("CANCEL", party.Party, party.Size, "waited", r.Now-party.Joined)
				return nil
			}
		}
		return fmt.Errorf("%s is not waiting", a[0])

	case "MOVE":
		source, err := r.table(a[0])
		if err != nil {
			return err
		}
		destination, err := r.table(a[1])
		if err != nil {
			return err
		}
		if source.Check == nil {
			return fmt.Errorf("table %s is free", a[0])
		}
		if destination.Check != nil {
			return fmt.Errorf("table %s is occupied", a[1])
		}
		check := source.Check
		if destination.Seats < check.Size {
			return fmt.Errorf("table %s is too small for %s", a[1], check.Party)
		}
		source.Check = nil
		destination.Check = check
		check.Table = destination
		r.emit("MOVE", check.Party, "table", source.Number, "->", destination.Number)
		r.processWaiting()

	case "MENU":
		if _, err := r.station(a[1]); err != nil {
			return err
		}
		if err := requireCourse(a[4]); err != nil {
			return err
		}
		old := r.Menu[a[0]]
		item := &MenuItem{
			Name: a[0], Station: a[1], Prep: integer(a[2]),
			Price: cents(a[3]), Course: a[4],
		}
		status := "ADD"
		if old != nil {
			item.Stock = old.Stock
			status = "UPDATE"
		}
		r.Menu[a[0]] = item
		r.emit("MENU", status, item.Name, item.Station,
			item.Prep, money(item.Price), item.Course)

	case "STOCK":
		item, err := r.item(a[0])
		if err != nil {
			return err
		}
		count := integer(a[1])
		item.Stock = &count
		r.emit("STOCK", item.Name, count)

	case "HAPPY":
		r.HappyRate = integer(a[0])
		r.HappyEnd = r.Now + integer(a[1])
		r.emit("HAPPY", strconv.Itoa(r.HappyRate)+"%", "until", clock(r.HappyEnd))

	case "ITEMS":
		items := make([]*MenuItem, 0, len(r.Menu))
		for _, item := range r.Menu {
			items = append(items, item)
		}
		priority := make(map[string]int)
		for i, course := range courseNames {
			priority[course] = i
		}
		sort.Slice(items, func(i, j int) bool {
			if priority[items[i].Course] != priority[items[j].Course] {
				return priority[items[i].Course] < priority[items[j].Course]
			}
			return items[i].Name < items[j].Name
		})
		r.emit("ITEMS", len(items))
		for _, item := range items {
			stock := "-"
			if item.Stock != nil {
				stock = strconv.Itoa(*item.Stock)
			}
			r.emit(item.Course, item.Name, item.Station, item.Prep, money(item.Price), stock)
		}

	case "ORDER":
		check, err := r.check(a[0])
		if err != nil {
			return err
		}
		if err := unlocked(check); err != nil {
			return err
		}
		seat := integer(a[1])
		if seat > check.Size {
			return fmt.Errorf("seat %d out of range for table %s", seat, a[0])
		}
		item, err := r.item(a[2])
		if err != nil {
			return err
		}
		quantity := integer(a[3])
		if item.Stock != nil && *item.Stock < quantity {
			return fmt.Errorf("only %d %s left", *item.Stock, item.Name)
		}
		happy := item.Course == "DRINK" && r.Now < r.HappyEnd
		price := item.Price
		if happy {
			price -= rounded(price, r.HappyRate)
		}
		line := &OrderLine{
			Number: len(r.Lines) + 1, Check: check, Seat: seat,
			Item: item.Name, Quantity: quantity, Station: item.Station,
			Prep: item.Prep, Price: price, Course: item.Course,
			State: "ORDERED",
		}
		r.Lines = append(r.Lines, line)
		check.Lines = append(check.Lines, line)
		parts := []any{
			"ORDER", "#"+strconv.Itoa(line.Number), "table", check.Table.Number,
			"seat", seat, item.Name, "x"+strconv.Itoa(quantity), money(line.amount()),
		}
		if happy {
			parts = append(parts, "HAPPY")
		}
		r.emit(parts...)
		if item.Stock != nil {
			*item.Stock -= quantity
			if *item.Stock == 0 {
				r.emit("SOLDOUT", item.Name)
			}
		}

	case "FIRE":
		check, err := r.check(a[0])
		if err != nil {
			return err
		}
		if err := requireCourse(a[1]); err != nil {
			return err
		}
		firing := make([]*OrderLine, 0)
		for _, line := range check.Lines {
			if line.Course == a[1] && line.State == "ORDERED" {
				firing = append(firing, line)
			}
		}
		if len(firing) == 0 {
			return fmt.Errorf("nothing to fire for %s at table %s", a[1], a[0])
		}
		ordered := []string{"STARTER", "MAIN", "DESSERT"}
		for _, course := range ordered {
			if course == a[1] {
				break
			}
			if a[1] == "DRINK" {
				break
			}
			for _, line := range check.Lines {
				if line.Course == course && line.State == "ORDERED" {
					return fmt.Errorf("fire %s first", course)
				}
			}
		}
		parts := []any{"FIRE", "table", check.Table.Number, a[1]}
		for _, line := range firing {
			line.State = "QUEUED"
			line.Fire = r.Now
			r.Stations[line.Station].Queue = append(r.Stations[line.Station].Queue, line)
			parts = append(parts, "#"+strconv.Itoa(line.Number))
		}
		r.emit(parts...)
		for _, name := range stationNames {
			start(r.Stations[name], r.Now)
		}

	case "TICK":
		r.tick(integer(a[0]))

	case "SERVE":
		check, err := r.check(a[0])
		if err != nil {
			return err
		}
		var ready []*OrderLine
		for _, line := range check.Lines {
			if line.State == "READY" {
				ready = append(ready, line)
			}
		}
		if len(ready) == 0 {
			return fmt.Errorf("nothing ready for table %s", a[0])
		}
		parts := []any{"SERVE", "table", check.Table.Number}
		for _, line := range ready {
			line.State = "SERVED"
			r.Served[line.Item] += line.Quantity
			parts = append(parts, "#"+strconv.Itoa(line.Number))
		}
		r.emit(parts...)

	case "RUSH":
		line, err := r.line(a[0])
		if err != nil {
			return err
		}
		if line.State != "QUEUED" {
			return fmt.Errorf("#%d is not queued", line.Number)
		}
		station := r.Stations[line.Station]
		queue := []*OrderLine{line}
		for _, current := range station.Queue {
			if current != line {
				queue = append(queue, current)
			}
		}
		station.Queue = queue
		r.emit("RUSH", "#"+strconv.Itoa(line.Number), line.Station)

	case "REMAKE":
		line, err := r.line(a[0])
		if err != nil {
			return err
		}
		if line.Check.Closed {
			return fmt.Errorf("#%d is on a closed check", line.Number)
		}
		if line.State != "READY" && line.State != "SERVED" {
			return fmt.Errorf("#%d is not ready or served", line.Number)
		}
		line.State = "QUEUED"
		line.Fire = r.Now
		station := r.Stations[line.Station]
		station.Queue = append([]*OrderLine{line}, station.Queue...)
		station.Remakes++
		r.emit("REMAKE", "#"+strconv.Itoa(line.Number), line.Item, line.Station)
		start(station, r.Now)

	case "VOID":
		line, err := r.line(a[0])
		if err != nil {
			return err
		}
		if line.State == "VOID" {
			return fmt.Errorf("#%d is already void", line.Number)
		}
		if line.Started {
			return fmt.Errorf("#%d has already started", line.Number)
		}
		if line.State == "QUEUED" {
			station := r.Stations[line.Station]
			queue := make([]*OrderLine, 0, len(station.Queue))
			for _, current := range station.Queue {
				if current != line {
					queue = append(queue, current)
				}
			}
			station.Queue = queue
		}
		line.State = "VOID"
		item := r.Menu[line.Item]
		if item.Stock != nil {
			*item.Stock += line.Quantity
		}
		r.Voids++
		r.emit("VOID", "#"+strconv.Itoa(line.Number), line.Item, "x"+strconv.Itoa(line.Quantity))

	case "STATION":
		station, err := r.station(a[0])
		if err != nil {
			return err
		}
		if a[1] == "DOWN" && !station.Up {
			return fmt.Errorf("station %s is already down", a[0])
		}
		if a[1] == "UP" && station.Up {
			return fmt.Errorf("station %s is not down", a[0])
		}
		station.Up = a[1] == "UP"
		if station.Up {
			start(station, r.Now)
		}
		r.emit("STATION", station.Name, a[1])

	case "COMP", "TRANSFER":
		line, err := r.line(a[0])
		if err != nil {
			return err
		}
		if err := modifiable(line); err != nil {
			return err
		}
		if cmd == "COMP" {
			if line.Reason != "" {
				return fmt.Errorf("#%d is already comped", line.Number)
			}
			value := line.amount()
			r.emit("COMP", "#"+strconv.Itoa(line.Number), line.Item, money(value), a[1])
			r.Comps++
			r.CompAmount += value
			line.Reason = a[1]
		} else {
			seat := integer(a[1])
			if seat > line.Check.Size {
				return fmt.Errorf("seat %d out of range for table %d",
					seat, line.Check.Table.Number)
			}
			if seat == line.Seat {
				return fmt.Errorf("#%d is already on seat %d", line.Number, seat)
			}
			r.emit("TRANSFER", "#"+strconv.Itoa(line.Number), "seat", line.Seat, "->", seat)
			line.Seat = seat
		}

	case "DISCOUNT":
		check, err := r.check(a[0])
		if err != nil {
			return err
		}
		if err := unlocked(check); err != nil {
			return err
		}
		check.Discount = integer(a[1])
		r.emit("DISCOUNT", "table", check.Table.Number,
			strconv.Itoa(check.Discount)+"%")

	case "BILL":
		check, err := r.check(a[0])
		if err != nil {
			return err
		}
		r.bill(check)

	case "SPLIT":
		check, err := r.check(a[0])
		if err != nil {
			return err
		}
		amounts := calculate(check)
		if amounts.Due == 0 {
			return fmt.Errorf("nothing to split for table %s", a[0])
		}
		if a[1] == "EVEN" {
			count := integer(a[2])
			if count > check.Size {
				return fmt.Errorf("cannot split table %s %d ways", a[0], count)
			}
			r.emit("SPLIT", "table", check.Table.Number, "EVEN", count,
				"due", money(amounts.Due))
			quotient, remainder := amounts.Due/count, amounts.Due%count
			for i := 1; i <= count; i++ {
				amount := quotient
				if i <= remainder {
					amount++
				}
				r.emit("PAYER", i, money(amount))
			}
		} else {
			if check.Paid > 0 {
				return fmt.Errorf("table %s has payments", a[0])
			}
			values := seatSubtotals(check)
			discounts := allocate(values, check.Discount)
			after := make(map[int]int)
			for seat, value := range values {
				after[seat] = value - discounts[seat]
			}
			serviceRate := 0
			if check.Size >= 6 {
				serviceRate = 18
			}
			services := allocate(after, serviceRate)
			taxes := allocate(after, 8)
			r.emit("SPLIT", "table", check.Table.Number, "BYSEAT",
				"total", money(amounts.Total))
			for _, seat := range sortedSeats(values) {
				r.emit("SEAT", seat, "subtotal", money(values[seat]),
					"discount", money(discounts[seat]),
					"service", money(services[seat]),
					"tax", money(taxes[seat]),
					"total", money(after[seat]+services[seat]+taxes[seat]))
			}
		}

	case "PAY":
		check, err := r.check(a[0])
		if err != nil {
			return err
		}
		if a[1] != "CASH" && a[1] != "CARD" {
			return fmt.Errorf("unknown method %s", a[1])
		}
		if err := unserved(check); err != nil {
			return err
		}
		due := calculate(check).Due
		if due == 0 {
			return fmt.Errorf("nothing to pay for table %s", a[0])
		}
		value := cents(a[2])
		applied := value
		if applied > due {
			applied = due
		}
		check.Paid += applied
		r.Payments[a[1]] += applied
		if value < due {
			r.emit("PAY", "table", check.Table.Number, a[1],
				money(value), "remaining", money(due-value))
		} else {
			label := "change"
			if a[1] == "CARD" {
				label = "tip"
				r.Tips += value - due
				check.Server.Tips += value - due
			}
			r.emit("PAY", "table", check.Table.Number, a[1],
				money(value), label, money(value-due))
			r.close(check)
		}

	case "CLOSE":
		check, err := r.check(a[0])
		if err != nil {
			return err
		}
		if err := unserved(check); err != nil {
			return err
		}
		due := calculate(check).Due
		if due != 0 {
			return fmt.Errorf("table %s still owes %s", a[0], money(due))
		}
		r.close(check)

	case "STATUS":
		check, err := r.check(a[0])
		if err != nil {
			return err
		}
		r.emit("STATUS", "table", check.Table.Number, check.Party, "guests",
			check.Size, "since", clock(check.Seated))
		for _, line := range check.Lines {
			parts := []any{
				"#" + strconv.Itoa(line.Number), "seat", line.Seat,
				line.Item, "x" + strconv.Itoa(line.Quantity),
				line.Course, line.State,
			}
			if line.State == "COOKING" {
				parts = append(parts, "until", clock(line.Ready))
			}
			if line.Reason != "" {
				parts = append(parts, "COMP", line.Reason)
			}
			r.emit(parts...)
		}

	case "KITCHEN":
		r.emit("KITCHEN", clock(r.Now))
		for _, name := range stationNames {
			station := r.Stations[name]
			cooking := append([]*OrderLine(nil), station.Cooking...)
			sort.Slice(cooking, func(i, j int) bool {
				if cooking[i].Ready != cooking[j].Ready {
					return cooking[i].Ready < cooking[j].Ready
				}
				return cooking[i].Number < cooking[j].Number
			})
			cookingText := make([]string, 0, len(cooking))
			for _, line := range cooking {
				cookingText = append(cookingText,
					"#"+strconv.Itoa(line.Number)+"@"+clock(line.Ready))
			}
			queueText := make([]string, 0, len(station.Queue))
			for _, line := range station.Queue {
				queueText = append(queueText, "#"+strconv.Itoa(line.Number))
			}
			status := "down"
			if station.Up {
				status = "up"
			}
			first, second := "-", "-"
			if len(cookingText) != 0 {
				first = strings.Join(cookingText, " ")
			}
			if len(queueText) != 0 {
				second = strings.Join(queueText, " ")
			}
			r.emit(name, status, "cooking", first, "queue", second)
		}

	case "FLOOR":
		tables := make([]*Table, 0, len(r.Tables))
		for _, table := range r.Tables {
			tables = append(tables, table)
		}
		sort.Slice(tables, func(i, j int) bool {
			return tables[i].Number < tables[j].Number
		})
		free := 0
		for _, table := range tables {
			if table.Check == nil {
				free++
			}
		}
		r.emit("FLOOR", clock(r.Now), "free", free,
			"seated", len(tables)-free, "waiting", len(r.Waiting))
		for _, table := range tables {
			check := table.Check
			if check == nil {
				r.emit("table", table.Number, "seats", table.Seats, "free")
				continue
			}
			parts := []any{
				"table", table.Number, "seats", table.Seats,
				check.Party, "guests", check.Size, "server", check.Server.Name,
				"since", clock(check.Seated), "items", len(check.active()),
				"total", money(calculate(check).Total),
			}
			if check.Paid > 0 {
				parts = append(parts, "paid", money(check.Paid))
			}
			r.emit(parts...)
		}
		for i, party := range r.Waiting {
			r.emit("WAITING", i+1, party.Party, party.Size, "since", clock(party.Joined))
		}

	case "REPORT":
		r.report()
	}
	return nil
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	count := integer(scanner.Text())
	restaurant := newRestaurant()
	for i := 0; i < count && scanner.Scan(); i++ {
		fields := strings.Split(scanner.Text(), " ")
		if err := restaurant.command(fields[0], fields[1:]); err != nil {
			restaurant.emit("ERROR", err.Error())
		}
	}
	writer := bufio.NewWriter(os.Stdout)
	defer writer.Flush()
	for _, line := range restaurant.Output {
		fmt.Fprintln(writer, line)
	}
}
