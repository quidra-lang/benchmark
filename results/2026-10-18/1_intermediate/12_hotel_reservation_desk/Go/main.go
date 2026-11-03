package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var roomTypes = []string{"SINGLE", "DOUBLE", "SUITE"}
var weekdays = []string{"SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI"}

func leap(year int) bool {
	return year%4 == 0 && (year%100 != 0 || year%400 == 0)
}

func monthLengths(year int) [12]int {
	february := 28
	if leap(year) {
		february++
	}
	return [12]int{31, february, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
}

func dayNumber(text string) (int, error) {
	parts := strings.Split(text, "-")
	year, _ := strconv.Atoi(parts[0])
	month, _ := strconv.Atoi(parts[1])
	day, _ := strconv.Atoi(parts[2])
	if year < 2000 || year > 2099 || month < 1 || month > 12 {
		return 0, fmt.Errorf("invalid date %s", text)
	}
	lengths := monthLengths(year)
	if day < 1 || day > lengths[month-1] {
		return 0, fmt.Errorf("invalid date %s", text)
	}
	number := day - 1
	for previous := 2000; previous < year; previous++ {
		if leap(previous) {
			number += 366
		} else {
			number += 365
		}
	}
	for previous := 0; previous < month-1; previous++ {
		number += lengths[previous]
	}
	return number, nil
}

func dateText(number int) string {
	year := 2000
	for {
		days := 365
		if leap(year) {
			days++
		}
		if number < days {
			break
		}
		number -= days
		year++
	}
	month := 1
	for _, days := range monthLengths(year) {
		if number < days {
			break
		}
		number -= days
		month++
	}
	return fmt.Sprintf("%04d-%02d-%02d", year, month, number+1)
}

func dateWeekday(day int) string {
	return dateText(day) + " " + weekdays[day%7]
}

func cents(text string) int {
	parts := strings.Split(text, ".")
	whole, _ := strconv.Atoi(parts[0])
	fraction, _ := strconv.Atoi(parts[1])
	return 100*whole + fraction
}

func money(value int) string {
	return fmt.Sprintf("%d.%02d", value/100, value%100)
}

func stringLine(parts ...any) string {
	texts := make([]string, len(parts))
	for i, part := range parts {
		texts[i] = fmt.Sprint(part)
	}
	return strings.Join(texts, " ")
}

type Room struct {
	Number int
	Kind   string
	Rate   int
	Clean  bool
}

type Night struct {
	Day  int
	Room int
	Rate int
}

type Bill struct {
	Lodging  int
	Discount int
	Penalty  int
	Extras   int
	Tax      int
	Total    int
}

type Reservation struct {
	ID        string
	Guest     string
	Room      *Room
	Arrival   int
	Departure int
	Nights    []Night
	Status    string
	Extras    []Extra
	Deposit   int
	Paid      int
	Posting   *int
	Fee       int
	Penalty   *Night
	Bill      *Bill
}

type Extra struct {
	Item   string
	Amount int
}

func (r *Reservation) lodging() int {
	total := 0
	for _, night := range r.Nights {
		total += night.Rate
	}
	return total
}

func (r *Reservation) firstRate() int {
	return r.Nights[0].Rate
}

type WaitingEntry struct {
	ID        string
	Guest     string
	Kind      string
	Arrival   int
	Departure int
}

type NightKey struct {
	Day  int
	Room int
}

type Occupied struct {
	Reservation *Reservation
	Rate        int
}

type Season struct {
	Start      int
	End        int
	Percentage int
}

type HotelDesk struct {
	Today            int
	Rooms            map[int]*Room
	Seasons          []Season
	Blocks           map[NightKey]bool
	Reservations     map[string]*Reservation
	ReservationOrder []*Reservation
	Waitlist         []WaitingEntry
	UsedIDs          map[string]bool
	Occupied         map[NightKey]Occupied
	Output           []string
}

func newHotelDesk() *HotelDesk {
	initial, _ := dayNumber("2026-01-01")
	return &HotelDesk{
		Today:        initial,
		Rooms:        make(map[int]*Room),
		Blocks:       make(map[NightKey]bool),
		Reservations: make(map[string]*Reservation),
		UsedIDs:      make(map[string]bool),
		Occupied:     make(map[NightKey]Occupied),
	}
}

func (desk *HotelDesk) emit(parts ...any) {
	desk.Output = append(desk.Output, stringLine(parts...))
}

func (desk *HotelDesk) emitIndented(parts ...any) {
	desk.Output = append(desk.Output, "  "+stringLine(parts...))
}

func (desk *HotelDesk) requireRoom(text string) (*Room, error) {
	number, _ := strconv.Atoi(text)
	room := desk.Rooms[number]
	if room == nil {
		return nil, fmt.Errorf("unknown room %s", text)
	}
	return room, nil
}

func requireType(kind string) error {
	for _, valid := range roomTypes {
		if kind == valid {
			return nil
		}
	}
	return fmt.Errorf("invalid type %s", kind)
}

func (desk *HotelDesk) requireUnused(id string) error {
	if desk.UsedIDs[id] {
		return fmt.Errorf("duplicate reservation %s", id)
	}
	return nil
}

func (desk *HotelDesk) reservation(id, required string) (*Reservation, error) {
	reservation := desk.Reservations[id]
	if reservation == nil {
		return nil, fmt.Errorf("unknown reservation %s", id)
	}
	if required != "" && reservation.Status != required {
		return nil, fmt.Errorf("invalid status %s %s", id, reservation.Status)
	}
	return reservation, nil
}

func (desk *HotelDesk) stay(first, last string) (int, int, error) {
	arrival, err := dayNumber(first)
	if err != nil {
		return 0, 0, err
	}
	departure, err := dayNumber(last)
	if err != nil {
		return 0, 0, err
	}
	switch {
	case arrival < desk.Today:
		return 0, 0, fmt.Errorf("past date %s", first)
	case departure <= arrival:
		return 0, 0, fmt.Errorf("invalid range %s %s", first, last)
	case departure-arrival > 30:
		return 0, 0, fmt.Errorf("too long %d", departure-arrival)
	}
	return arrival, departure, nil
}

func (desk *HotelDesk) period(first, last string, pastRestricted, limited bool) (int, int, error) {
	start, err := dayNumber(first)
	if err != nil {
		return 0, 0, err
	}
	end, err := dayNumber(last)
	if err != nil {
		return 0, 0, err
	}
	switch {
	case pastRestricted && start < desk.Today:
		return 0, 0, fmt.Errorf("past date %s", first)
	case end < start:
		return 0, 0, fmt.Errorf("invalid range %s %s", first, last)
	case limited && end-start+1 > 31:
		return 0, 0, fmt.Errorf("too long %d", end-start+1)
	}
	return start, end, nil
}

func (desk *HotelDesk) nightRate(room *Room, day int) int {
	percentage := 100
	for i := len(desk.Seasons) - 1; i >= 0; i-- {
		season := desk.Seasons[i]
		if season.Start <= day && day <= season.End {
			percentage = season.Percentage
			break
		}
	}
	return room.Rate * percentage / 100
}

func (desk *HotelDesk) price(room *Room, arrival, departure int) []Night {
	nights := make([]Night, 0, departure-arrival)
	for day := arrival; day < departure; day++ {
		nights = append(nights, Night{day, room.Number, desk.nightRate(room, day)})
	}
	return nights
}

func (desk *HotelDesk) firstUnavailable(
	room *Room, arrival, departure int, exceptFor *Reservation,
) *int {
	for day := arrival; day < departure; day++ {
		key := NightKey{day, room.Number}
		if desk.Blocks[key] {
			return &day
		}
		if occupied, ok := desk.Occupied[key]; ok && occupied.Reservation != exceptFor {
			return &day
		}
	}
	return nil
}

func (desk *HotelDesk) sortedRooms() []*Room {
	rooms := make([]*Room, 0, len(desk.Rooms))
	for _, room := range desk.Rooms {
		rooms = append(rooms, room)
	}
	sort.Slice(rooms, func(i, j int) bool { return rooms[i].Number < rooms[j].Number })
	return rooms
}

func (desk *HotelDesk) freeRoom(
	kind string, arrival, departure int, exceptFor *Reservation,
) *Room {
	for _, room := range desk.sortedRooms() {
		if room.Kind == kind && desk.firstUnavailable(room, arrival, departure, exceptFor) == nil {
			return room
		}
	}
	return nil
}

func (desk *HotelDesk) inhouse(room *Room) *Reservation {
	for _, reservation := range desk.ReservationOrder {
		if reservation.Status == "inhouse" && reservation.Room == room {
			return reservation
		}
	}
	return nil
}

func (desk *HotelDesk) occupy(reservation *Reservation, nights []Night) {
	for _, night := range nights {
		desk.Occupied[NightKey{night.Day, night.Room}] = Occupied{reservation, night.Rate}
	}
}

func (desk *HotelDesk) release(reservation *Reservation, first *int) {
	for _, night := range reservation.Nights {
		if first == nil || night.Day >= *first {
			delete(desk.Occupied, NightKey{night.Day, night.Room})
		}
	}
}

func (desk *HotelDesk) createReservation(
	id, guest string, room *Room, arrival, departure int, indent bool,
) {
	nights := desk.price(room, arrival, departure)
	reservation := &Reservation{
		ID: id, Guest: guest, Room: room,
		Arrival: arrival, Departure: departure, Nights: nights, Status: "booked",
	}
	desk.Reservations[id] = reservation
	desk.ReservationOrder = append(desk.ReservationOrder, reservation)
	desk.UsedIDs[id] = true
	desk.occupy(reservation, nights)
	parts := []any{
		"BOOK", id, guest, "room", room.Number, room.Kind,
		dateText(arrival), "->", dateText(departure), "nights", departure - arrival,
		"total", money(reservation.lodging()),
	}
	if indent {
		desk.emitIndented(parts...)
	} else {
		desk.emit(parts...)
	}
}

func (desk *HotelDesk) guestTotal(guest string) int {
	total := 0
	for _, reservation := range desk.ReservationOrder {
		if reservation.Guest == guest {
			total += reservation.Paid
		}
	}
	return total
}

func (desk *HotelDesk) tier(guest string) string {
	points := desk.guestTotal(guest) / 100
	switch {
	case points >= 2000:
		return "GOLD"
	case points >= 500:
		return "SILVER"
	default:
		return "BRONZE"
	}
}

func (desk *HotelDesk) calculateBill(reservation *Reservation) *Bill {
	lodging := reservation.lodging()
	percentage := 0
	switch desk.tier(reservation.Guest) {
	case "GOLD":
		percentage = 10
	case "SILVER":
		percentage = 5
	}
	discount := lodging * percentage / 100
	penalty := 0
	if reservation.Penalty != nil {
		penalty = reservation.Penalty.Rate
	}
	extras := 0
	for _, extra := range reservation.Extras {
		extras += extra.Amount
	}
	subtotal := lodging - discount + penalty + extras
	tax := subtotal / 10
	return &Bill{lodging, discount, penalty, extras, tax, subtotal + tax}
}

func depositParts(reservation *Reservation, amount int) []any {
	if amount >= reservation.Deposit {
		return []any{"deposit", money(reservation.Deposit), "due", money(amount - reservation.Deposit)}
	}
	return []any{"deposit", money(reservation.Deposit), "refund", money(reservation.Deposit - amount)}
}

func (desk *HotelDesk) checkOut(reservation *Reservation, day int, indent bool) {
	if day < reservation.Departure {
		for _, night := range reservation.Nights {
			if night.Day == day {
				penalty := night
				reservation.Penalty = &penalty
				break
			}
		}
		desk.release(reservation, &day)
		past := make([]Night, 0, len(reservation.Nights))
		for _, night := range reservation.Nights {
			if night.Day < day {
				past = append(past, night)
			}
		}
		reservation.Nights = past
		reservation.Departure = day
	}
	bill := desk.calculateBill(reservation)
	reservation.Bill = bill
	reservation.Paid = bill.Total
	reservation.Status = "checkedout"
	reservation.Posting = &day
	reservation.Room.Clean = false
	parts := []any{
		"CHECKOUT", reservation.ID, "nights", len(reservation.Nights),
		"lodging", money(bill.Lodging), "discount", money(bill.Discount),
		"penalty", money(bill.Penalty), "extras", money(bill.Extras),
		"tax", money(bill.Tax), "total", money(bill.Total),
	}
	parts = append(parts, depositParts(reservation, bill.Total)...)
	if indent {
		desk.emitIndented(parts...)
	} else {
		desk.emit(parts...)
	}
}

func (desk *HotelDesk) processWaitlist() {
	remaining := make([]WaitingEntry, 0, len(desk.Waitlist))
	for _, entry := range desk.Waitlist {
		if entry.Arrival < desk.Today {
			desk.emitIndented("WAITLIST", entry.ID, "expired")
			continue
		}
		room := desk.freeRoom(entry.Kind, entry.Arrival, entry.Departure, nil)
		if room == nil {
			remaining = append(remaining, entry)
		} else {
			desk.createReservation(entry.ID, entry.Guest, room, entry.Arrival, entry.Departure, true)
		}
	}
	desk.Waitlist = remaining
}

func (desk *HotelDesk) cmdRoom(a []string) error {
	number, _ := strconv.Atoi(a[0])
	if desk.Rooms[number] != nil {
		return fmt.Errorf("duplicate room %s", a[0])
	}
	if err := requireType(a[1]); err != nil {
		return err
	}
	desk.Rooms[number] = &Room{number, a[1], cents(a[2]), true}
	desk.emit("ROOM", a[0], a[1], a[2])
	return nil
}

func (desk *HotelDesk) cmdRate(a []string) error {
	room, err := desk.requireRoom(a[0])
	if err != nil {
		return err
	}
	previous := room.Rate
	room.Rate = cents(a[1])
	desk.emit("RATE", a[0], money(previous), "->", a[1])
	return nil
}

func (desk *HotelDesk) cmdSeason(a []string) error {
	start, end, err := desk.period(a[0], a[1], false, false)
	if err != nil {
		return err
	}
	percentage, _ := strconv.Atoi(a[2])
	desk.Seasons = append(desk.Seasons, Season{start, end, percentage})
	desk.emit("SEASON", len(desk.Seasons), a[0], "->", a[1], a[2]+"%")
	return nil
}

func (desk *HotelDesk) cmdBlock(a []string) error {
	room, err := desk.requireRoom(a[0])
	if err != nil {
		return err
	}
	start, end, err := desk.period(a[1], a[2], true, true)
	if err != nil {
		return err
	}
	for day := start; day <= end; day++ {
		if _, exists := desk.Occupied[NightKey{day, room.Number}]; exists {
			return fmt.Errorf("room unavailable %s %s", a[0], dateText(day))
		}
	}
	added := 0
	for day := start; day <= end; day++ {
		key := NightKey{day, room.Number}
		if !desk.Blocks[key] {
			desk.Blocks[key] = true
			added++
		}
	}
	desk.emit("BLOCK", a[0], a[1], "->", a[2], "added", added)
	return nil
}

func (desk *HotelDesk) cmdUnblock(a []string) error {
	room, err := desk.requireRoom(a[0])
	if err != nil {
		return err
	}
	start, end, err := desk.period(a[1], a[2], true, true)
	if err != nil {
		return err
	}
	removed := 0
	for day := start; day <= end; day++ {
		key := NightKey{day, room.Number}
		if desk.Blocks[key] {
			delete(desk.Blocks, key)
			removed++
		}
	}
	desk.emit("UNBLOCK", a[0], a[1], "->", a[2], "removed", removed)
	return nil
}

func (desk *HotelDesk) cmdClean(a []string) error {
	room, err := desk.requireRoom(a[0])
	if err != nil {
		return err
	}
	if room.Clean {
		return fmt.Errorf("already clean %s", a[0])
	}
	room.Clean = true
	desk.emit("CLEAN", a[0])
	return nil
}

func (desk *HotelDesk) cmdToday(a []string) error {
	day, err := dayNumber(a[0])
	if err != nil {
		return err
	}
	if day < desk.Today {
		return fmt.Errorf("past date %s", a[0])
	}
	desk.emit("TODAY", dateWeekday(day))
	var departing []*Reservation
	for _, reservation := range desk.ReservationOrder {
		if reservation.Status == "inhouse" && reservation.Departure < day {
			departing = append(departing, reservation)
		}
	}
	sort.Slice(departing, func(i, j int) bool {
		if departing[i].Departure != departing[j].Departure {
			return departing[i].Departure < departing[j].Departure
		}
		return departing[i].ID < departing[j].ID
	})
	for _, reservation := range departing {
		desk.checkOut(reservation, reservation.Departure, true)
	}
	var absent []*Reservation
	for _, reservation := range desk.ReservationOrder {
		if reservation.Status == "booked" && reservation.Arrival < day {
			absent = append(absent, reservation)
		}
	}
	sort.Slice(absent, func(i, j int) bool {
		if absent[i].Arrival != absent[j].Arrival {
			return absent[i].Arrival < absent[j].Arrival
		}
		return absent[i].ID < absent[j].ID
	})
	for _, reservation := range absent {
		desk.release(reservation, nil)
		reservation.Fee = reservation.firstRate()
		reservation.Paid = reservation.Fee
		reservation.Status = "noshow"
		posting := reservation.Arrival
		reservation.Posting = &posting
		parts := []any{"NOSHOW", reservation.ID, reservation.Guest, "fee", money(reservation.Fee)}
		desk.emitIndented(append(parts, depositParts(reservation, reservation.Fee)...)...)
	}
	desk.Today = day
	return nil
}

func (desk *HotelDesk) cmdBook(a []string) error {
	if err := desk.requireUnused(a[0]); err != nil {
		return err
	}
	if err := requireType(a[2]); err != nil {
		return err
	}
	arrival, departure, err := desk.stay(a[3], a[4])
	if err != nil {
		return err
	}
	room := desk.freeRoom(a[2], arrival, departure, nil)
	if room == nil {
		return fmt.Errorf("no availability %s %s %s", a[2], a[3], a[4])
	}
	desk.createReservation(a[0], a[1], room, arrival, departure, false)
	return nil
}

func (desk *HotelDesk) cmdBookroom(a []string) error {
	if err := desk.requireUnused(a[0]); err != nil {
		return err
	}
	room, err := desk.requireRoom(a[2])
	if err != nil {
		return err
	}
	arrival, departure, err := desk.stay(a[3], a[4])
	if err != nil {
		return err
	}
	if unavailable := desk.firstUnavailable(room, arrival, departure, nil); unavailable != nil {
		return fmt.Errorf("room unavailable %s %s", a[2], dateText(*unavailable))
	}
	desk.createReservation(a[0], a[1], room, arrival, departure, false)
	return nil
}

func (desk *HotelDesk) cmdWaitlist(a []string) error {
	if err := desk.requireUnused(a[0]); err != nil {
		return err
	}
	if err := requireType(a[2]); err != nil {
		return err
	}
	arrival, departure, err := desk.stay(a[3], a[4])
	if err != nil {
		return err
	}
	room := desk.freeRoom(a[2], arrival, departure, nil)
	if room != nil {
		desk.createReservation(a[0], a[1], room, arrival, departure, false)
	} else {
		desk.Waitlist = append(desk.Waitlist,
			WaitingEntry{a[0], a[1], a[2], arrival, departure})
		desk.UsedIDs[a[0]] = true
		desk.emit("WAITLIST", a[0], "queued position", len(desk.Waitlist))
	}
	return nil
}

func (desk *HotelDesk) cmdModify(a []string) error {
	reservation, err := desk.reservation(a[0], "booked")
	if err != nil {
		return err
	}
	arrival, departure, err := desk.stay(a[1], a[2])
	if err != nil {
		return err
	}
	room := reservation.Room
	choice := "kept"
	if desk.firstUnavailable(room, arrival, departure, reservation) != nil {
		room = desk.freeRoom(room.Kind, arrival, departure, reservation)
		if room == nil {
			return fmt.Errorf("no availability %s %s %s", reservation.Room.Kind, a[1], a[2])
		}
		choice = "reassigned"
	}
	nights := desk.price(room, arrival, departure)
	desk.release(reservation, nil)
	reservation.Room = room
	reservation.Arrival = arrival
	reservation.Departure = departure
	reservation.Nights = nights
	desk.occupy(reservation, nights)
	desk.emit("MODIFY", a[0], "room", room.Number, choice, a[1], "->", a[2],
		"nights", departure-arrival, "total", money(reservation.lodging()))
	return nil
}

func (desk *HotelDesk) cmdCancel(a []string) error {
	for position, entry := range desk.Waitlist {
		if entry.ID == a[0] {
			desk.Waitlist = append(desk.Waitlist[:position], desk.Waitlist[position+1:]...)
			desk.emit("CANCEL", a[0], "waitlist removed")
			return nil
		}
	}
	reservation, err := desk.reservation(a[0], "booked")
	if err != nil {
		return err
	}
	days := reservation.Arrival - desk.Today
	firstRate := reservation.firstRate()
	fee := firstRate
	if days >= 7 {
		fee = 0
	} else if days >= 1 {
		fee = firstRate / 2
	}
	desk.release(reservation, nil)
	reservation.Fee = fee
	reservation.Paid = fee
	reservation.Status = "cancelled"
	posting := desk.Today
	reservation.Posting = &posting
	parts := []any{"CANCEL", a[0], "days", days, "fee", money(fee)}
	desk.emit(append(parts, depositParts(reservation, fee)...)...)
	return nil
}

func (desk *HotelDesk) cmdCheckin(a []string) error {
	reservation, err := desk.reservation(a[0], "booked")
	if err != nil {
		return err
	}
	if reservation.Arrival != desk.Today {
		return fmt.Errorf("not arrival date %s %s", a[0], dateText(reservation.Arrival))
	}
	if occupant := desk.inhouse(reservation.Room); occupant != nil {
		return fmt.Errorf("room occupied %d %s", reservation.Room.Number, occupant.ID)
	}
	if !reservation.Room.Clean {
		return fmt.Errorf("room dirty %d", reservation.Room.Number)
	}
	reservation.Status = "inhouse"
	desk.emit("CHECKIN", a[0], reservation.Guest, "room", reservation.Room.Number,
		"until", dateText(reservation.Departure))
	return nil
}

func (desk *HotelDesk) cmdMove(a []string) error {
	reservation, err := desk.reservation(a[0], "inhouse")
	if err != nil {
		return err
	}
	room, err := desk.requireRoom(a[1])
	if err != nil {
		return err
	}
	previous := reservation.Room
	if room == previous {
		return fmt.Errorf("same room %s", a[1])
	}
	var remaining []Night
	for _, night := range reservation.Nights {
		if night.Day >= desk.Today {
			remaining = append(remaining, night)
		}
	}
	if len(remaining) == 0 {
		return fmt.Errorf("no remaining nights %s", a[0])
	}
	if unavailable := desk.firstUnavailable(
		room, remaining[0].Day, reservation.Departure, reservation,
	); unavailable != nil {
		return fmt.Errorf("room unavailable %s %s", a[1], dateText(*unavailable))
	}
	if occupant := desk.inhouse(room); occupant != nil {
		return fmt.Errorf("room occupied %s %s", a[1], occupant.ID)
	}
	if !room.Clean {
		return fmt.Errorf("room dirty %s", a[1])
	}
	desk.release(reservation, &desk.Today)
	for i, night := range reservation.Nights {
		if night.Day >= desk.Today {
			reservation.Nights[i].Room = room.Number
		}
	}
	var future []Night
	for _, night := range reservation.Nights {
		if night.Day >= desk.Today {
			future = append(future, night)
		}
	}
	desk.occupy(reservation, future)
	previous.Clean = false
	reservation.Room = room
	desk.emit("MOVE", a[0], previous.Number, "->", a[1], "nights", len(remaining))
	return nil
}

func (desk *HotelDesk) cmdExtend(a []string) error {
	reservation, err := desk.reservation(a[0], "inhouse")
	if err != nil {
		return err
	}
	departure, err := dayNumber(a[1])
	if err != nil {
		return err
	}
	if departure <= reservation.Departure {
		return fmt.Errorf("invalid range %s %s", dateText(reservation.Departure), a[1])
	}
	if departure-reservation.Arrival > 30 {
		return fmt.Errorf("too long %d", departure-reservation.Arrival)
	}
	if unavailable := desk.firstUnavailable(
		reservation.Room, reservation.Departure, departure, reservation,
	); unavailable != nil {
		return fmt.Errorf("room unavailable %d %s", reservation.Room.Number, dateText(*unavailable))
	}
	nights := desk.price(reservation.Room, reservation.Departure, departure)
	reservation.Nights = append(reservation.Nights, nights...)
	desk.occupy(reservation, nights)
	reservation.Departure = departure
	desk.emit("EXTEND", a[0], "until", a[1], "nights", len(reservation.Nights),
		"total", money(reservation.lodging()))
	return nil
}

func (desk *HotelDesk) cmdCharge(a []string) error {
	reservation, err := desk.reservation(a[0], "inhouse")
	if err != nil {
		return err
	}
	amount := cents(a[1])
	if amount == 0 {
		return fmt.Errorf("invalid amount")
	}
	reservation.Extras = append(reservation.Extras, Extra{a[2], amount})
	total := 0
	for _, extra := range reservation.Extras {
		total += extra.Amount
	}
	desk.emit("CHARGE", a[0], a[2], a[1], "extras", money(total))
	return nil
}

func (desk *HotelDesk) cmdPay(a []string) error {
	reservation, err := desk.reservation(a[0], "")
	if err != nil {
		return err
	}
	if reservation.Status != "booked" && reservation.Status != "inhouse" {
		return fmt.Errorf("invalid status %s %s", a[0], reservation.Status)
	}
	amount := cents(a[1])
	if amount == 0 {
		return fmt.Errorf("invalid amount")
	}
	reservation.Deposit += amount
	desk.emit("PAY", a[0], a[1], "deposit", money(reservation.Deposit))
	return nil
}

func (desk *HotelDesk) cmdCheckout(a []string) error {
	reservation, err := desk.reservation(a[0], "inhouse")
	if err != nil {
		return err
	}
	desk.checkOut(reservation, desk.Today, false)
	return nil
}

func (desk *HotelDesk) cmdInvoice(a []string) error {
	reservation, err := desk.reservation(a[0], "")
	if err != nil {
		return err
	}
	desk.emit("INVOICE", a[0], reservation.Guest, "room", reservation.Room.Number,
		reservation.Room.Kind, reservation.Status)
	if reservation.Status == "cancelled" || reservation.Status == "noshow" {
		label := "noshow"
		if reservation.Status == "cancelled" {
			label = "cancellation"
		}
		desk.emitIndented(label, "fee", money(reservation.Fee))
		desk.emitIndented("total", money(reservation.Fee))
		desk.emitIndented(depositParts(reservation, reservation.Fee)...)
		return nil
	}
	for _, night := range reservation.Nights {
		desk.emitIndented(dateWeekday(night.Day), "room", night.Room, money(night.Rate))
	}
	bill := reservation.Bill
	if bill == nil {
		bill = desk.calculateBill(reservation)
	}
	desk.emitIndented("lodging", money(bill.Lodging))
	desk.emitIndented("discount", money(bill.Discount))
	if reservation.Penalty != nil {
		desk.emitIndented("penalty", dateWeekday(reservation.Penalty.Day), money(bill.Penalty))
	}
	for _, extra := range reservation.Extras {
		desk.emitIndented("extra", extra.Item, money(extra.Amount))
	}
	desk.emitIndented("tax", money(bill.Tax))
	desk.emitIndented("total", money(bill.Total))
	desk.emitIndented(depositParts(reservation, bill.Total)...)
	return nil
}

func (desk *HotelDesk) cmdAvail(a []string) error {
	if err := requireType(a[0]); err != nil {
		return err
	}
	start, end, err := desk.period(a[1], a[2], false, true)
	if err != nil {
		return err
	}
	var rooms []int
	for _, room := range desk.sortedRooms() {
		if room.Kind == a[0] {
			rooms = append(rooms, room.Number)
		}
	}
	desk.emit("AVAIL", a[0], a[1], "->", a[2])
	for day := start; day <= end; day++ {
		parts := []any{dateWeekday(day), "free"}
		var free []int
		for _, number := range rooms {
			key := NightKey{day, number}
			if !desk.Blocks[key] {
				if _, occupied := desk.Occupied[key]; !occupied {
					free = append(free, number)
				}
			}
		}
		parts = append(parts, len(free))
		for _, number := range free {
			parts = append(parts, number)
		}
		desk.emitIndented(parts...)
	}
	return nil
}

func (desk *HotelDesk) occupancyParts(numbers []int, day int) []any {
	blocked, occupied := 0, 0
	for _, number := range numbers {
		key := NightKey{day, number}
		if desk.Blocks[key] {
			blocked++
		}
		if _, used := desk.Occupied[key]; used {
			occupied++
		}
	}
	available := len(numbers) - blocked
	rate := "n/a"
	if available > 0 {
		rate = fmt.Sprintf("%d%%", occupied*100/available)
	}
	return []any{"rooms", len(numbers), "blocked", blocked, "occupied", occupied, "rate", rate}
}

func (desk *HotelDesk) cmdOccupancy(a []string) error {
	day, err := dayNumber(a[0])
	if err != nil {
		return err
	}
	all := make([]int, 0, len(desk.Rooms))
	for number := range desk.Rooms {
		all = append(all, number)
	}
	desk.emit(append([]any{"OCCUPANCY", dateWeekday(day)}, desk.occupancyParts(all, day)...)...)
	for _, kind := range roomTypes {
		var numbers []int
		for _, room := range desk.Rooms {
			if room.Kind == kind {
				numbers = append(numbers, room.Number)
			}
		}
		if len(numbers) > 0 {
			desk.emitIndented(append([]any{kind}, desk.occupancyParts(numbers, day)...)...)
		}
	}
	return nil
}

func (desk *HotelDesk) dailyValues(day int) (int, int, int) {
	available := len(desk.Rooms)
	occupiedCount, revenue := 0, 0
	for number := range desk.Rooms {
		key := NightKey{day, number}
		if desk.Blocks[key] {
			available--
		}
		if night, exists := desk.Occupied[key]; exists {
			occupiedCount++
			revenue += night.Rate
		}
	}
	return available, occupiedCount, revenue
}

func metricsParts(available, occupied, revenue int) []any {
	rate, average, revpar := "n/a", "n/a", "n/a"
	if available > 0 {
		rate = fmt.Sprintf("%d%%", occupied*100/available)
		revpar = money(revenue / available)
	}
	if occupied > 0 {
		average = money(revenue / occupied)
	}
	return []any{"sold", fmt.Sprintf("%d/%d", occupied, available), "rate", rate,
		"revenue", money(revenue), "adr", average, "revpar", revpar}
}

func (desk *HotelDesk) cmdStats(a []string) error {
	start, end, err := desk.period(a[0], a[1], false, true)
	if err != nil {
		return err
	}
	desk.emit("STATS", a[0], "->", a[1])
	tAvailable, tOccupied, tRevenue := 0, 0, 0
	for day := start; day <= end; day++ {
		available, occupied, revenue := desk.dailyValues(day)
		tAvailable += available
		tOccupied += occupied
		tRevenue += revenue
		desk.emitIndented(append([]any{dateWeekday(day)}, metricsParts(available, occupied, revenue)...)...)
	}
	desk.emitIndented(append([]any{"total"}, metricsParts(tAvailable, tOccupied, tRevenue)...)...)
	return nil
}

func (desk *HotelDesk) cmdRooms(a []string) error {
	desk.emit("ROOMS", dateWeekday(desk.Today), "rooms", len(desk.Rooms))
	for _, room := range desk.sortedRooms() {
		state := "dirty"
		if room.Clean {
			state = "clean"
		}
		parts := []any{room.Number, room.Kind, "base", money(room.Rate),
			"tonight", money(desk.nightRate(room, desk.Today)), state}
		occupant := desk.inhouse(room)
		switch {
		case occupant != nil:
			parts = append(parts, "occupied", occupant.ID)
		case desk.Blocks[NightKey{desk.Today, room.Number}]:
			parts = append(parts, "blocked")
		default:
			parts = append(parts, "vacant")
		}
		var upcoming *Reservation
		for _, reservation := range desk.ReservationOrder {
			if reservation.Status == "booked" && reservation.Room == room &&
				(upcoming == nil || reservation.Arrival < upcoming.Arrival) {
				upcoming = reservation
			}
		}
		if upcoming != nil {
			parts = append(parts, "next", upcoming.ID, dateText(upcoming.Arrival))
		}
		desk.emitIndented(parts...)
	}
	return nil
}

func (desk *HotelDesk) cmdList(a []string) error {
	var selected []*Reservation
	for _, reservation := range desk.ReservationOrder {
		if reservation.Status == a[0] {
			selected = append(selected, reservation)
		}
	}
	sort.Slice(selected, func(i, j int) bool {
		if selected[i].Arrival != selected[j].Arrival {
			return selected[i].Arrival < selected[j].Arrival
		}
		return selected[i].ID < selected[j].ID
	})
	desk.emit("LIST", a[0], len(selected))
	for _, reservation := range selected {
		desk.emitIndented(reservation.ID, reservation.Guest, "room", reservation.Room.Number,
			dateText(reservation.Arrival), "->", dateText(reservation.Departure))
	}
	return nil
}

func (desk *HotelDesk) cmdQueue(a []string) error {
	desk.emit("QUEUE", len(desk.Waitlist))
	for i, entry := range desk.Waitlist {
		desk.emitIndented(i+1, entry.ID, entry.Guest, entry.Kind,
			dateText(entry.Arrival), "->", dateText(entry.Departure))
	}
	return nil
}

func (desk *HotelDesk) cmdSchedule(a []string) error {
	day, err := dayNumber(a[0])
	if err != nil {
		return err
	}
	var arrivals, departures []*Reservation
	for _, reservation := range desk.ReservationOrder {
		if reservation.Arrival == day && reservation.Status != "cancelled" {
			arrivals = append(arrivals, reservation)
		}
		if reservation.Departure == day &&
			(reservation.Status == "booked" || reservation.Status == "inhouse" ||
				reservation.Status == "checkedout") {
			departures = append(departures, reservation)
		}
	}
	sort.Slice(arrivals, func(i, j int) bool { return arrivals[i].ID < arrivals[j].ID })
	sort.Slice(departures, func(i, j int) bool { return departures[i].ID < departures[j].ID })
	desk.emit("SCHEDULE", dateWeekday(day), "arrivals", len(arrivals), "departures", len(departures))
	for _, reservation := range arrivals {
		desk.emitIndented("arrival", reservation.ID, reservation.Guest, "room",
			reservation.Room.Number, reservation.Status)
	}
	for _, reservation := range departures {
		desk.emitIndented("departure", reservation.ID, reservation.Guest, "room",
			reservation.Room.Number, reservation.Status)
	}
	return nil
}

func (desk *HotelDesk) cmdGuest(a []string) error {
	var selected []*Reservation
	for _, reservation := range desk.ReservationOrder {
		if reservation.Guest == a[0] {
			selected = append(selected, reservation)
		}
	}
	if len(selected) == 0 {
		return fmt.Errorf("unknown guest %s", a[0])
	}
	desk.emit("GUEST", a[0])
	for _, reservation := range selected {
		field, amount := "paid", reservation.Paid
		if reservation.Status == "booked" || reservation.Status == "inhouse" {
			field, amount = "deposit", reservation.Deposit
		}
		desk.emitIndented(reservation.ID, "room", reservation.Room.Number,
			reservation.Room.Kind, dateText(reservation.Arrival), "->",
			dateText(reservation.Departure), reservation.Status, field, money(amount))
	}
	total := desk.guestTotal(a[0])
	desk.emitIndented("total paid", money(total), "points", total/100, "tier", desk.tier(a[0]))
	return nil
}

func (desk *HotelDesk) cmdRevenue(a []string) error {
	start, end, err := desk.period(a[0], a[1], false, false)
	if err != nil {
		return err
	}
	var lodging, discount, penalty, extras, tax int
	var cancellations, noshows int
	var checkouts, cancelled, absent int
	for _, reservation := range desk.ReservationOrder {
		if reservation.Posting == nil || *reservation.Posting < start || *reservation.Posting > end {
			continue
		}
		switch reservation.Status {
		case "checkedout":
			checkouts++
			lodging += reservation.Bill.Lodging
			discount += reservation.Bill.Discount
			penalty += reservation.Bill.Penalty
			extras += reservation.Bill.Extras
			tax += reservation.Bill.Tax
		case "cancelled":
			cancelled++
			cancellations += reservation.Fee
		case "noshow":
			absent++
			noshows += reservation.Fee
		}
	}
	desk.emit("REVENUE", a[0], "->", a[1])
	desk.emitIndented("lodging", money(lodging))
	desk.emitIndented("discount", money(discount))
	desk.emitIndented("penalty", money(penalty))
	desk.emitIndented("extras", money(extras))
	desk.emitIndented("tax", money(tax))
	desk.emitIndented("cancellation", money(cancellations))
	desk.emitIndented("noshow", money(noshows))
	desk.emitIndented("total", money(lodging-discount+penalty+extras+tax+cancellations+noshows))
	desk.emitIndented("checkouts", checkouts, "cancellations", cancelled, "noshows", absent)
	return nil
}

func (desk *HotelDesk) command(tokens []string) error {
	command, a := tokens[0], tokens[1:]
	switch command {
	case "ROOM":
		return desk.cmdRoom(a)
	case "RATE":
		return desk.cmdRate(a)
	case "SEASON":
		return desk.cmdSeason(a)
	case "BLOCK":
		return desk.cmdBlock(a)
	case "UNBLOCK":
		return desk.cmdUnblock(a)
	case "CLEAN":
		return desk.cmdClean(a)
	case "TODAY":
		return desk.cmdToday(a)
	case "BOOK":
		return desk.cmdBook(a)
	case "BOOKROOM":
		return desk.cmdBookroom(a)
	case "WAITLIST":
		return desk.cmdWaitlist(a)
	case "MODIFY":
		return desk.cmdModify(a)
	case "CANCEL":
		return desk.cmdCancel(a)
	case "CHECKIN":
		return desk.cmdCheckin(a)
	case "MOVE":
		return desk.cmdMove(a)
	case "EXTEND":
		return desk.cmdExtend(a)
	case "CHARGE":
		return desk.cmdCharge(a)
	case "PAY":
		return desk.cmdPay(a)
	case "CHECKOUT":
		return desk.cmdCheckout(a)
	case "INVOICE":
		return desk.cmdInvoice(a)
	case "AVAIL":
		return desk.cmdAvail(a)
	case "OCCUPANCY":
		return desk.cmdOccupancy(a)
	case "STATS":
		return desk.cmdStats(a)
	case "ROOMS":
		return desk.cmdRooms(a)
	case "LIST":
		return desk.cmdList(a)
	case "QUEUE":
		return desk.cmdQueue(a)
	case "SCHEDULE":
		return desk.cmdSchedule(a)
	case "GUEST":
		return desk.cmdGuest(a)
	case "REVENUE":
		return desk.cmdRevenue(a)
	}
	return nil
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	count, _ := strconv.Atoi(scanner.Text())
	desk := newHotelDesk()
	for i := 0; i < count && scanner.Scan(); i++ {
		tokens := strings.Fields(scanner.Text())
		if err := desk.command(tokens); err != nil {
			desk.emit("ERROR", err.Error())
		}
		desk.processWaitlist()
	}
	writer := bufio.NewWriter(os.Stdout)
	defer writer.Flush()
	for _, line := range desk.Output {
		fmt.Fprintln(writer, line)
	}
}
