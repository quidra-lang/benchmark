package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type seat struct {
    row, cabin, block, position, kind int
    letter byte
}
type cabin struct {
    from, to int
    blocks []string
}
type aircraft struct {
    model string
    base, limit int
    cabins [3]cabin
    seats []seat
    blocked []bool
    lookup [2600]int
    exits [100]bool
    capacity [3]int
}
type flight struct {
    name string
    model int
    closed bool
    limit [3]int
    blocked []bool
    occupants, passengers, volunteers []int
}
type booking struct {
    pnr string
    flight int
    checked bool
    people []int
}
type person struct {
    name string
    booking, kind, preference, cabin, seat, lap int
    active, volunteer bool
}
var aircrafts []*aircraft
var flights []*flight
var bookings []*booking
var people []*person
var modelIDs = map[string]int{}
var flightIDs = map[string]int{}
var bookingIDs = map[string]int{}
var tiers = map[string]int{}
var building *aircraft
const classes = "FJY"
var typeNames = []string{"ADULT", "CHILD", "INFANT"}
var tierNames = []string{"PLATINUM", "GOLD", "SILVER", "NONE"}

func fail(message string) { panic(message) }
func number(s string) int {
    value, _ := strconv.Atoi(s)
    return value
}
func index(values []string, s string) int {
    for i, value := range values { if value == s { return i } }
    return -1
}
func cabinID(s string) int { return strings.IndexByte(classes, s[0]) }
func tier(id int) int {
    if value, exists := tiers[people[id].name]; exists { return value }
    return 3
}
func seatKey(s string) int { return number(s[:len(s)-1])*26+int(s[len(s)-1]-'A') }
func seatName(a *aircraft, id int) string {
    if id < 0 { return "UNASSIGNED" }
    return fmt.Sprintf("%d%c", a.seats[id].row, a.seats[id].letter)
}
func flightID(name string, open bool) int {
    id, exists := flightIDs[name]
    if !exists { fail("unknown flight "+name) }
    if open && flights[id].closed { fail("flight "+name+" is closed") }
    return id
}
func activeCount(b int) int {
    count := 0
    for _, id := range bookings[b].people { if people[id].active { count++ } }
    return count
}
func bookingID(pnr string, open bool) int {
    id, exists := bookingIDs[pnr]
    if !exists || activeCount(id) == 0 { fail("unknown PNR "+pnr) }
    if open && flights[bookings[id].flight].closed { fail("flight "+flights[bookings[id].flight].name+" is closed") }
    return id
}
func passengerID(b int, name string) int {
    for _, id := range bookings[b].people {
        if people[id].active && people[id].name == name { return id }
    }
    fail("no passenger "+name+" in "+bookings[b].pnr)
    return -1
}
func resolve(pnr, name string) int { return passengerID(bookingID(pnr, true), name) }
func hasInfant(id int) bool { return people[id].kind == 0 && people[id].lap >= 0 && people[people[id].lap].active }
func bookingInfants(b int) bool {
    for _, id := range bookings[b].people {
        if people[id].active && people[id].kind == 2 { return true }
    }
    return false
}
func bookedCount(f, c int) int {
    count := 0
    for _, id := range flights[f].passengers {
        p := people[id]
        if p.active && p.kind != 2 && p.cabin == c { count++ }
    }
    return count
}
func contains(values []int, value int) bool {
    for _, item := range values { if item == value { return true } }
    return false
}
func exitAllowed(id int, a *aircraft, target int) bool {
    return !a.exits[a.seats[target].row] || people[id].kind == 0 && !hasInfant(id)
}
func infantAllowed(f, id, target int, moving, ids, assigned []int) bool {
    if !hasInfant(id) { return true }
    plane := aircrafts[flights[f].model]
    s := plane.seats[target]
    for _, letter := range plane.cabins[s.cabin].blocks[s.block] {
        peer := plane.lookup[s.row*26+int(letter-'A')]
        owner := flights[f].occupants[peer]
        if owner >= 0 && owner != id && !contains(moving, owner) && hasInfant(owner) { return false }
    }
    for i, other := range ids {
        t := plane.seats[assigned[i]]
        if other != id && hasInfant(other) && t.row == s.row && t.block == s.block { return false }
    }
    return true
}
func fits(f int, ids, assigned, vacated []int) bool {
    plane := aircrafts[flights[f].model]
    moving := append(append([]int(nil), ids...), vacated...)
    for i, id := range ids {
        target := assigned[i]
        owner := flights[f].occupants[target]
        if flights[f].blocked[target] || owner >= 0 && !contains(moving, owner) || !exitAllowed(id, plane, target) || !infantAllowed(f, id, target, moving, ids, assigned) { return false }
    }
    return true
}
func chooseSeat(f, id, c int) int {
    plane := aircrafts[flights[f].model]
    first := -1
    for target, s := range plane.seats {
        if s.cabin != c || flights[f].blocked[target] || flights[f].occupants[target] >= 0 || !exitAllowed(id, plane, target) || !infantAllowed(f, id, target, nil, nil, nil) { continue }
        if first < 0 { first = target }
        if people[id].preference < 0 || people[id].preference == s.kind { return target }
    }
    return first
}
func seatPerson(f, id, target int) {
    if people[id].seat >= 0 { flights[f].occupants[people[id].seat] = -1 }
    people[id].seat = target
    if target >= 0 { flights[f].occupants[target] = id }
}
func reassign(f int) []string {
    var out []string
    plane := aircrafts[flights[f].model]
    for _, id := range flights[f].passengers {
        p := people[id]
        if !p.active || p.kind == 2 || p.seat >= 0 { continue }
        target := chooseSeat(f, id, p.cabin)
        if target < 0 { continue }
        seatPerson(f, id, target)
        out = append(out, "REASSIGNED "+bookings[p.booking].pnr+" "+p.name+" "+seatName(plane, target))
    }
    return out
}
func removePerson(id int) {
    p := people[id]
    if !p.active { return }
    lap := p.lap
    if p.kind == 0 && lap >= 0 { removePerson(lap) }
    if p.kind == 2 && lap >= 0 { people[lap].lap = -1 }
    seatPerson(bookings[p.booking].flight, id, -1)
    p.active, p.volunteer, p.lap = false, false, -1
}
func passengerResult(id int) string {
    if people[id].kind == 2 { return "LAP" }
    f := flights[bookings[people[id].booking].flight]
    return seatName(aircrafts[f.model], people[id].seat)
}
func assignBooking(f, c int, ids []int) string {
    if len(ids) == 1 {
        seatPerson(f, ids[0], chooseSeat(f, ids[0], c))
        return "SINGLE"
    }
    plane := aircrafts[flights[f].model]
    cabin := plane.cabins[c]
    count := len(ids)
    for stage := 0; stage < 3; stage++ {
        firstHeight, lastHeight := 1, 1
        if stage == 2 { firstHeight, lastHeight = 2, count }
        for height := firstHeight; height <= lastHeight; height++ {
            width := count
            if stage == 2 { width = (count+height-1)/height }
            rows := (count+width-1)/width
            for row := cabin.from; row+rows-1 <= cabin.to; row++ {
                blocks := cabin.blocks
                if stage == 1 { blocks = []string{strings.Join(cabin.blocks, "")} }
                for _, block := range blocks {
                    for x := 0; x+width <= len(block); x++ {
                        candidate := make([]int, count)
                        for j := range candidate { candidate[j] = plane.lookup[(row+j/width)*26+int(block[x+j%width]-'A')] }
                        if !fits(f, ids, candidate, nil) { continue }
                        for j, id := range ids { seatPerson(f, id, candidate[j]) }
                        return []string{"BLOCK", "ROW", "STACK"}[stage]
                    }
                }
            }
        }
    }
    for _, id := range ids { seatPerson(f, id, chooseSeat(f, id, c)) }
    return "SPLIT"
}
func execute(v []string) []string {
    command := v[0]
    var out []string
    switch command {
    case "AIRCRAFT":
        building = &aircraft{model: v[1], base: number(v[2]), limit: number(v[3])}
        for i := range building.lookup { building.lookup[i] = -1 }
    case "CABIN":
        c := cabinID(v[1])
        building.cabins[c] = cabin{number(v[2]), number(v[3]), append([]string(nil), v[4:]...)}
        definition := building.cabins[c]
        for row := definition.from; row <= definition.to; row++ {
            for b, block := range definition.blocks {
                for position := range block {
                    kind := 1
                    if b == 0 && position == 0 || b == len(definition.blocks)-1 && position == len(block)-1 { kind = 0 } else if position == 0 || position == len(block)-1 { kind = 2 }
                    letter := block[position]
                    building.lookup[row*26+int(letter-'A')] = len(building.seats)
                    building.seats = append(building.seats, seat{row, c, b, position, kind, letter})
                    building.blocked = append(building.blocked, false)
                }
            }
        }
    case "EXIT":
        for _, value := range v[1:] { building.exits[number(value)] = true }
    case "BLOCKED":
        for _, value := range v[1:] { building.blocked[building.lookup[seatKey(value)]] = true }
    case "END":
        for i, s := range building.seats {
            if !building.blocked[i] { building.capacity[s.cabin]++ }
        }
        line := "AIRCRAFT "+building.model
        for c := 0; c < 3; c++ {
            if building.cabins[c].from > 0 { line += fmt.Sprintf(" %c %d", classes[c], building.capacity[c]) }
        }
        modelIDs[building.model] = len(aircrafts)
        aircrafts = append(aircrafts, building)
        out = append(out, line)
    case "FLIGHT":
        if _, exists := flightIDs[v[1]]; exists { fail("duplicate flight "+v[1]) }
        model, exists := modelIDs[v[2]]
        if !exists { fail("unknown aircraft "+v[2]) }
        plane := aircrafts[model]
        f := &flight{name: v[1], model: model, blocked: append([]bool(nil), plane.blocked...), occupants: make([]int, len(plane.seats))}
        for i := range f.occupants { f.occupants[i] = -1 }
        line := "FLIGHT "+f.name+" "+plane.model
        for c := 0; c < 3; c++ {
            f.limit[c] = plane.capacity[c]*(100+number(v[3]))/100
            if plane.cabins[c].from > 0 { line += fmt.Sprintf(" %c %d/%d", classes[c], plane.capacity[c], f.limit[c]) }
        }
        flightIDs[f.name] = len(flights)
        flights = append(flights, f)
        out = append(out, line)
    case "BOOK":
        if _, exists := bookingIDs[v[1]]; exists { fail("duplicate PNR "+v[1]) }
        f, c := flightID(v[2], true), cabinID(v[3])
        plane := aircrafts[flights[f].model]
        if plane.cabins[c].from == 0 { fail("no cabin "+v[3]+" on "+v[2]) }
        var draft []*person
        seen := map[string]bool{}
        var adults, infants []int
        for _, item := range v[4:] {
            fields := strings.Split(item, ":")
            if seen[fields[0]] { fail("duplicate name "+fields[0]+" in "+v[1]) }
            seen[fields[0]] = true
            p := &person{name: fields[0], booking: len(bookings), kind: index(typeNames, fields[1]), cabin: c, preference: -1, seat: -1, lap: -1, active: true}
            if len(fields) == 3 { p.preference = strings.IndexByte("WMA", fields[2][0]) }
            if p.kind == 0 { adults = append(adults, len(draft)) }
            if p.kind == 2 { infants = append(infants, len(draft)) }
            draft = append(draft, p)
        }
        for _, p := range draft {
            for _, id := range flights[f].passengers {
                if people[id].active && people[id].name == p.name { fail(p.name+" already on "+v[2]) }
            }
        }
        if len(adults) == 0 { fail("no adult in "+v[1]) }
        if len(infants) > len(adults) { fail("too many infants in "+v[1]) }
        if bookedCount(f, c)+len(draft)-len(infants) > flights[f].limit[c] { fail("limit exceeded for "+v[2]+" "+v[3]) }
        base := len(people)
        for i, infant := range infants {
            draft[adults[i]].lap = base+infant
            draft[infant].lap = base+adults[i]
        }
        b := &booking{pnr: v[1], flight: f}
        var needs []int
        for _, p := range draft {
            id := len(people)
            people = append(people, p)
            b.people = append(b.people, id)
            flights[f].passengers = append(flights[f].passengers, id)
            if p.kind != 2 { needs = append(needs, id) }
        }
        bookingIDs[b.pnr] = len(bookings)
        bookings = append(bookings, b)
        method := assignBooking(f, c, needs)
        line := "BOOKED "+b.pnr+" "+v[2]+" "+v[3]+" "+method
        for _, id := range b.people { line += " "+people[id].name+":"+passengerResult(id) }
        out = append(out, line)
    case "STATUS":
        tiers[v[1]] = index(tierNames, v[2])
        out = append(out, "STATUS "+v[1]+" "+v[2])
    case "FIND":
        membership := 3
        if value, exists := tiers[v[1]]; exists { membership = value }
        var found []string
        for _, f := range flights {
            for _, id := range f.passengers {
                p := people[id]
                if !p.active || p.name != v[1] { continue }
                state := "OPEN"
                if f.closed { state = "CLOSED" }
                found = append(found, fmt.Sprintf("%s %s %c %s %s", f.name, bookings[p.booking].pnr, classes[p.cabin], passengerResult(id), state))
            }
        }
        out = append(out, fmt.Sprintf("FIND %s %s %d", v[1], tierNames[membership], len(found)))
        out = append(out, found...)
    case "SEAT":
        id := resolve(v[1], v[2])
        p := people[id]
        f := bookings[p.booking].flight
        plane := aircrafts[flights[f].model]
        if p.kind == 2 { fail("infant "+p.name+" has no seat") }
        target := plane.lookup[seatKey(v[3])]
        if target < 0 || plane.seats[target].cabin != p.cabin { fail(fmt.Sprintf("no seat %s in cabin %c", v[3], classes[p.cabin])) }
        if flights[f].blocked[target] { fail("seat "+v[3]+" is blocked") }
        if flights[f].occupants[target] >= 0 { fail("seat "+v[3]+" is occupied") }
        if !exitAllowed(id, plane, target) { fail(fmt.Sprintf("exit row %d not allowed for %s", plane.seats[target].row, p.name)) }
        if !infantAllowed(f, id, target, nil, nil, nil) { fail("infant limit reached at "+v[3]) }
        old := seatName(plane, p.seat)
        seatPerson(f, id, target)
        out = append(out, "MOVED "+v[1]+" "+v[2]+" "+old+" -> "+v[3])
        out = append(out, reassign(f)...)
    case "SWAP":
        first, second := resolve(v[1], v[2]), resolve(v[3], v[4])
        if first == second { fail("cannot swap "+v[2]+" with itself") }
        for _, id := range []int{first, second} {
            if people[id].kind == 2 { fail("infant "+people[id].name+" has no seat") }
        }
        f := bookings[people[first].booking].flight
        if f != bookings[people[second].booking].flight { fail(v[1]+" and "+v[3]+" are on different flights") }
        if people[first].cabin != people[second].cabin { fail(v[2]+" and "+v[4]+" are in different cabins") }
        for _, id := range []int{first, second} {
            if people[id].seat < 0 { fail(people[id].name+" has no seat") }
        }
        oldFirst, oldSecond := people[first].seat, people[second].seat
        if !fits(f, []int{first, second}, []int{oldSecond, oldFirst}, nil) { fail("swap of "+v[2]+" and "+v[4]+" breaks seating rules") }
        flights[f].occupants[oldFirst], flights[f].occupants[oldSecond] = -1, -1
        people[first].seat, people[second].seat = -1, -1
        seatPerson(f, first, oldSecond)
        seatPerson(f, second, oldFirst)
        plane := aircrafts[flights[f].model]
        out = append(out, "SWAPPED "+v[1]+" "+v[2]+" "+seatName(plane, oldSecond)+" "+v[3]+" "+v[4]+" "+seatName(plane, oldFirst))
        out = append(out, reassign(f)...)
    case "CANCEL":
        b := bookingID(v[1], true)
        target := -1
        if len(v) == 3 { target = passengerID(b, v[2]) }
        var removed []int
        for _, id := range bookings[b].people {
            if people[id].active && (target < 0 || id == target || people[target].kind == 0 && people[target].lap == id) { removed = append(removed, id) }
        }
        remaining, adults := 0, 0
        for _, id := range bookings[b].people {
            if people[id].active && !contains(removed, id) {
                remaining++
                if people[id].kind == 0 { adults++ }
            }
        }
        if target >= 0 && remaining > 0 && adults == 0 { fail(v[1]+" would have no adult") }
        line := "CANCELLED "+v[1]
        for _, id := range removed { line += " "+people[id].name }
        for _, id := range removed { removePerson(id) }
        out = append(out, line)
        out = append(out, reassign(bookings[b].flight)...)
    case "CHECKIN", "VOLUNTEER", "INFO":
        b := bookingID(v[1], command != "INFO")
        book := bookings[b]
        if command == "CHECKIN" {
            if book.checked { fail(v[1]+" already checked in") }
            book.checked = true
            out = append(out, fmt.Sprintf("CHECKIN %s %d", book.pnr, activeCount(b)))
        } else if command == "INFO" {
            state := "NOT-CHECKED"
            if book.checked { state = "CHECKED" }
            out = append(out, fmt.Sprintf("INFO %s %s %d %s", book.pnr, flights[book.flight].name, activeCount(b), state))
            for _, id := range book.people {
                p := people[id]
                if p.active { out = append(out, fmt.Sprintf("%s %s %c %s", p.name, typeNames[p.kind], classes[p.cabin], passengerResult(id))) }
            }
        } else {
            id := passengerID(b, v[2])
            p := people[id]
            if p.kind != 0 || hasInfant(id) { fail(p.name+" cannot volunteer") }
            if p.seat < 0 { fail(p.name+" has no seat") }
            if p.volunteer { fail(p.name+" already volunteered") }
            p.volunteer = true
            flights[book.flight].volunteers = append(flights[book.flight].volunteers, id)
            out = append(out, "VOLUNTEER "+book.pnr+" "+p.name+" "+passengerResult(id))
        }
    default:
        modifying := command == "UPGRADE" || command == "CLOSE" || command == "BLOCK" || command == "UNBLOCK"
        f := flightID(v[1], modifying)
        flight := flights[f]
        plane := aircrafts[flight.model]
        switch command {
        case "BLOCK", "UNBLOCK":
            target := plane.lookup[seatKey(v[2])]
            if target < 0 { fail("no seat "+v[2]+" on "+flight.name) }
            if command == "BLOCK" && flight.blocked[target] { fail("seat "+v[2]+" is blocked") }
            if command == "UNBLOCK" && !flight.blocked[target] { fail("seat "+v[2]+" is not blocked") }
            flight.blocked[target] = command == "BLOCK"
            out = append(out, command+" "+flight.name+" "+v[2])
            id := flight.occupants[target]
            if command == "BLOCK" && id >= 0 {
                seatPerson(f, id, -1)
                seatPerson(f, id, chooseSeat(f, id, people[id].cabin))
                out = append(out, "DISPLACED "+bookings[people[id].booking].pnr+" "+people[id].name+" "+v[2]+" -> "+passengerResult(id))
            }
            out = append(out, reassign(f)...)
        case "UPGRADE":
            var cabins []int
            for c := 0; c < 3; c++ { if plane.cabins[c].from > 0 { cabins = append(cabins, c) } }
            upgraded := 0
            for pair := 0; pair+1 < len(cabins); pair++ {
                higher, lower := cabins[pair], cabins[pair+1]
                booked := bookedCount(f, higher)
                type target struct { tier, id int }
                var targets []target
                for _, id := range flight.passengers {
                    p := people[id]
                    if p.active && p.cabin == lower && p.kind == 0 && !hasInfant(id) && tier(id) < 3 { targets = append(targets, target{tier(id), id}) }
                }
                sort.SliceStable(targets, func(i, j int) bool { return targets[i].tier < targets[j].tier })
                for _, item := range targets {
                    if booked >= flight.limit[higher] { break }
                    id := item.id
                    target := chooseSeat(f, id, higher)
                    if target < 0 { break }
                    old := passengerResult(id)
                    people[id].cabin = higher
                    seatPerson(f, id, target)
                    booked++
                    upgraded++
                    out = append(out, fmt.Sprintf("UPGRADED %s %s %c %s -> %c %s", bookings[people[id].booking].pnr, people[id].name, classes[lower], old, classes[higher], seatName(plane, target)))
                }
            }
            out = append(out, reassign(f)...)
            out = append(out, fmt.Sprintf("UPGRADE %s %d", flight.name, upgraded))
        case "CLOSE":
            for b, book := range bookings {
                if book.flight != f || book.checked || activeCount(b) == 0 { continue }
                out = append(out, fmt.Sprintf("NOSHOW %s %d", book.pnr, activeCount(b)))
                for _, id := range book.people { removePerson(id) }
            }
            out = append(out, reassign(f)...)
            denied, compensation := 0, 0
            voluntary, involuntary := []int{500, 300, 150}, []int{1000, 600, 300}
            for c := 0; c < 3; c++ {
                var targets []int
                for _, id := range flight.volunteers {
                    p := people[id]
                    if p.active && p.volunteer && p.seat >= 0 && p.cabin == c { targets = append(targets, id) }
                }
                for _, id := range targets {
                    target := people[id].seat
                    useful := false
                    for _, other := range flight.passengers {
                        p := people[other]
                        if p.active && p.kind != 2 && p.cabin == c && p.seat < 0 && fits(f, []int{other}, []int{target}, []int{id}) { useful = true }
                    }
                    if !useful { continue }
                    out = append(out, fmt.Sprintf("DENIED VOLUNTARY %s %s %c %d", bookings[people[id].booking].pnr, people[id].name, classes[c], voluntary[c]))
                    denied++
                    compensation += voluntary[c]
                    removePerson(id)
                    out = append(out, reassign(f)...)
                }
            }
            for _, id := range flight.passengers {
                p := people[id]
                if !p.active || p.kind == 2 || p.seat >= 0 { continue }
                value := involuntary[p.cabin]
                if p.kind == 1 { value /= 2 }
                out = append(out, fmt.Sprintf("DENIED INVOLUNTARY %s %s %c %d", bookings[p.booking].pnr, p.name, classes[p.cabin], value))
                denied++
                compensation += value
                removePerson(id)
            }
            flight.closed = true
            out = append(out, fmt.Sprintf("CLOSED %s denied %d compensation %d", flight.name, denied, compensation))
        case "MAP":
            out = append(out, "MAP "+flight.name)
            for c := 0; c < 3; c++ {
                cabin := plane.cabins[c]
                if cabin.from == 0 { continue }
                out = append(out, fmt.Sprintf("CABIN %c", classes[c]), "   "+strings.Join(cabin.blocks, " "))
                for row := cabin.from; row <= cabin.to; row++ {
                    line := fmt.Sprintf("%2d ", row)
                    for b, block := range cabin.blocks {
                        if b > 0 { line += " " }
                        for i := range block {
                            target := plane.lookup[row*26+int(block[i]-'A')]
                            mark := "."
                            if plane.exits[row] { mark = "E" }
                            if flight.occupants[target] >= 0 { mark = "X" }
                            if flight.blocked[target] { mark = "#" }
                            line += mark
                        }
                    }
                    out = append(out, line)
                }
            }
        case "MANIFEST":
            var order []int
            for _, owner := range flight.occupants { if owner >= 0 { order = append(order, owner) } }
            seated, unassigned, infants := len(order), 0, 0
            for _, id := range flight.passengers {
                p := people[id]
                if !p.active { continue }
                if p.kind == 2 { infants++ } else if p.seat < 0 {
                    unassigned++
                    order = append(order, id)
                }
            }
            out = append(out, fmt.Sprintf("MANIFEST %s seated %d unassigned %d infants %d", flight.name, seated, unassigned, infants))
            for _, id := range order {
                p := people[id]
                b := bookings[p.booking]
                position := "---"
                if p.seat >= 0 { position = seatName(plane, p.seat) }
                line := fmt.Sprintf("%s %c %s %s %s", position, classes[p.cabin], b.pnr, p.name, typeNames[p.kind])
                if hasInfant(id) { line += " +"+people[p.lap].name }
                if tier(id) < 3 { line += " "+tierNames[tier(id)] }
                if b.checked { line += " CHECKED" }
                if p.volunteer { line += " VOL" }
                out = append(out, line)
            }
        case "LOADFACTOR":
            out = append(out, "LOADFACTOR "+flight.name)
            allSeated, allSeats := 0, 0
            for c := 0; c < 3; c++ {
                if plane.cabins[c].from == 0 { continue }
                seats, seated := 0, 0
                for i, s := range plane.seats {
                    if s.cabin != c { continue }
                    if !flight.blocked[i] { seats++ }
                    if flight.occupants[i] >= 0 { seated++ }
                }
                factor := seated*1000/seats
                out = append(out, fmt.Sprintf("%c %d/%d %d.%d%% booked %d/%d", classes[c], seated, seats, factor/10, factor%10, bookedCount(f, c), flight.limit[c]))
                allSeated += seated
                allSeats += seats
            }
            factor := allSeated*1000/allSeats
            out = append(out, fmt.Sprintf("ALL %d/%d %d.%d%%", allSeated, allSeats, factor/10, factor%10))
        case "BALANCE":
            weight, moment := 0, 0
            for _, id := range flight.occupants {
                if id < 0 { continue }
                value := 80
                if people[id].kind == 1 { value = 40 }
                if hasInfant(id) { value += 10 }
                weight += value
                moment += value*(plane.seats[people[id].seat].row-plane.base)
            }
            verdict := "OK"
            if moment < -plane.limit { verdict = "NOSE-HEAVY" }
            if moment > plane.limit { verdict = "TAIL-HEAVY" }
            out = append(out, fmt.Sprintf("BALANCE %s weight %d moment %d limit %d %s", flight.name, weight, moment, plane.limit, verdict))
        case "BOARDING":
            type item struct {
                id, group, zone, kind, row int
                letter byte
            }
            var order []item
            for _, id := range flight.occupants {
                if id < 0 { continue }
                p := people[id]
                s := plane.seats[p.seat]
                group := 3
                if bookingInfants(p.booking) { group = 0 } else if p.cabin < 2 { group = 1 } else if tier(id) < 2 { group = 2 }
                zone := 0
                if group == 3 { zone = (s.row-plane.cabins[2].from)/5+1 }
                order = append(order, item{id, group, zone, s.kind, s.row, s.letter})
            }
            sort.Slice(order, func(i, j int) bool {
                x, y := order[i], order[j]
                if x.group != y.group { return x.group < y.group }
                if x.group == 3 {
                    if x.zone != y.zone { return x.zone > y.zone }
                    if x.kind != y.kind { return x.kind < y.kind }
                    if x.row != y.row { return x.row > y.row }
                } else if x.row != y.row { return x.row < y.row }
                return x.letter < y.letter
            })
            out = append(out, fmt.Sprintf("BOARDING %s %d", flight.name, len(order)))
            for i, item := range order {
                p := people[item.id]
                group := ""
                if item.group == 3 { group = fmt.Sprintf("ZONE%d", item.zone) } else { group = []string{"PRE", "CABIN", "TIER"}[item.group] }
                out = append(out, fmt.Sprintf("%d %s %s %s %s", i+1, group, seatName(plane, p.seat), bookings[p.booking].pnr, p.name))
            }
        case "AVAIL":
            c := cabinID(v[2])
            if plane.cabins[c].from == 0 { fail("no cabin "+v[2]+" on "+flight.name) }
            free, exits := 0, 0
            kinds := [3]int{}
            for i, s := range plane.seats {
                if s.cabin != c || flight.blocked[i] || flight.occupants[i] >= 0 { continue }
                free++
                kinds[s.kind]++
                if plane.exits[s.row] { exits++ }
            }
            out = append(out, fmt.Sprintf("AVAIL %s %c free %d W %d M %d A %d EXIT %d", flight.name, classes[c], free, kinds[0], kinds[1], kinds[2], exits))
        }
    }
    return out
}
func commandResult(v []string) (out []string) {
    defer func() {
        if message := recover(); message != nil { out = []string{"ERROR "+message.(string)} }
    }()
    return execute(v)
}
func main() {
    scanner := bufio.NewScanner(os.Stdin)
    scanner.Scan()
    count := number(scanner.Text())
    output := bufio.NewWriter(os.Stdout)
    defer output.Flush()
    for i := 0; i < count && scanner.Scan(); i++ {
        for _, line := range commandResult(strings.Split(scanner.Text(), " ")) { fmt.Fprintln(output, line) }
    }
}
