package main

import (
    "bufio"
    "fmt"
    "io"
    "os"
    "sort"
    "strconv"
    "strings"
)

type station struct {
    id, name string
    zone, transfer int
    closed bool
    walks map[string]int
}

type line struct {
    id string
    first, last, headway, total, delay int
    stops []*station
    cumulative []int
    suspended bool
}

type leg struct {
    kind string
    service *line
    terminal, from, to *station
    depart, arrive, stops int
}

type label struct {
    arrival int
    journey []leg
}

type direction struct {
    stops []*station
    offsets []int
}

type departure struct {
    time int
    service *line
    direction int
    terminal, start *station
}

type tariff struct {
    discount, window int
    prices []int
}

type network struct {
    stations map[string]*station
    lines map[string]*line
    closed map[string]bool
    walks int
    tariff *tariff
    out *bufio.Writer
}

func number(s string) int {
    n, _ := strconv.Atoi(s)
    return n
}

func timeValue(s string) int {
    return number(s[:2]) * 60 + number(s[3:])
}

func timeText(n int) string {
    return fmt.Sprintf("%02d:%02d", n / 60, n % 60)
}

func pair(a, b string) string {
    if a > b {
        a, b = b, a
    }
    return a + "\x00" + b
}

func names[T any](items map[string]T) []string {
    result := []string{}
    for name := range items {
        result = append(result, name)
    }
    sort.Strings(result)
    return result
}

func (l *line) direction(which int) direction {
    if which == 0 {
        return direction{l.stops, l.cumulative}
    }
    stops, offsets := make([]*station, len(l.stops)), make([]int, len(l.stops))
    for i := range stops {
        j := len(stops) - 1 - i
        stops[i], offsets[i] = l.stops[j], l.total - l.cumulative[j]
    }
    return direction{stops, offsets}
}

func (l *line) trains() int {
    return (l.last - l.first) / l.headway + 1
}

func (l *line) firstTrain(offset, ready int) int {
    base := l.first + l.delay + offset
    q := 0
    if ready > base {
        q = (ready - base + l.headway - 1) / l.headway
    }
    if q >= l.trains() {
        return -1
    }
    return q
}

func (l *line) time(q, offset int) int {
    return l.first + l.delay + q * l.headway + offset
}

func indexOf(stops []*station, s *station) int {
    for i, candidate := range stops {
        if candidate == s {
            return i
        }
    }
    return -1
}

func extend(journey []leg, part leg) []leg {
    return append(append([]leg{}, journey...), part)
}

func copyLabels(labels map[*station]*label) map[*station]*label {
    result := map[*station]*label{}
    for s, value := range labels {
        result[s] = value
    }
    return result
}

func update(labels map[*station]*label, s *station, arrival int, journey []leg) bool {
    if labels[s] == nil || labels[s].arrival > arrival {
        labels[s] = &label{arrival, journey}
        return true
    }
    return false
}

func (n *network) earliest(origin *station, start int) map[*station]*label {
    labels, settled := map[*station]*label{origin:{arrival:start}}, map[*station]bool{}
    services := names(n.lines)
    for {
        var selected *station
        for s, value := range labels {
            if !settled[s] && (selected == nil || value.arrival < labels[selected].arrival || value.arrival == labels[selected].arrival && s.id < selected.id) {
                selected = s
            }
        }
        if selected == nil {
            return labels
        }
        settled[selected] = true
        current := labels[selected]
        ready := current.arrival
        if selected != origin {
            ready += selected.transfer
        }
        for _, id := range services {
            service := n.lines[id]
            if service.suspended {
                continue
            }
            for which := 0; which < 2; which++ {
                d := service.direction(which)
                i := indexOf(d.stops, selected)
                if i < 0 || i == len(d.stops) - 1 {
                    continue
                }
                q := service.firstTrain(d.offsets[i], ready)
                if q < 0 {
                    continue
                }
                depart := service.time(q, d.offsets[i])
                for j := i + 1; j < len(d.stops); j++ {
                    target := d.stops[j]
                    if n.closed[pair(d.stops[j - 1].id, target.id)] {
                        break
                    }
                    if target.closed {
                        continue
                    }
                    arrival := service.time(q, d.offsets[j])
                    if labels[target] == nil || labels[target].arrival > arrival {
                        update(labels, target, arrival, extend(current.journey, leg{kind:"ride", service:service, terminal:d.stops[len(d.stops) - 1], from:selected, to:target, depart:depart, arrive:arrival, stops:j - i}))
                    }
                }
            }
        }
        for _, id := range names(selected.walks) {
            target := n.stations[id]
            arrival := current.arrival + selected.walks[id]
            if !target.closed && arrival <= 1440 && (labels[target] == nil || labels[target].arrival > arrival) {
                update(labels, target, arrival, extend(current.journey, leg{kind:"walk", from:selected, to:target, depart:current.arrival, arrive:arrival}))
            }
        }
    }
}

func stationOrder(set map[*station]bool) []*station {
    result := []*station{}
    for s := range set {
        result = append(result, s)
    }
    sort.Slice(result, func(i, j int) bool {
        return result[i].id < result[j].id
    })
    return result
}

func (n *network) walkStep(labels map[*station]*label, sources, marked map[*station]bool) {
    recorded := map[*station]*label{}
    for s := range sources {
        recorded[s] = labels[s]
    }
    for _, source := range stationOrder(sources) {
        current := recorded[source]
        for _, id := range names(source.walks) {
            target := n.stations[id]
            arrival := current.arrival + source.walks[id]
            if !target.closed && arrival <= 1440 && (labels[target] == nil || labels[target].arrival > arrival) {
                update(labels, target, arrival, extend(current.journey, leg{kind:"walk", from:source, to:target, depart:current.arrival, arrive:arrival}))
                marked[target] = true
            }
        }
    }
}

func (n *network) rounds(origin *station, start int, stop *station) []map[*station]*label {
    current := map[*station]*label{origin:{arrival:start}}
    marked := map[*station]bool{origin:true}
    n.walkStep(current, map[*station]bool{origin:true}, marked)
    result := []map[*station]*label{current}
    services := names(n.lines)
    for len(marked) > 0 {
        if stop != nil && current[stop] != nil {
            break
        }
        next, updated, walking := copyLabels(current), map[*station]bool{}, map[*station]bool{}
        for _, id := range services {
            service := n.lines[id]
            if service.suspended {
                continue
            }
            for which := 0; which < 2; which++ {
                d := service.direction(which)
                q, boarding, depart := -1, 0, 0
                var prefix []leg
                for j, target := range d.stops {
                    if j > 0 && n.closed[pair(d.stops[j - 1].id, target.id)] {
                        q = -1
                    }
                    if target.closed {
                        continue
                    }
                    if q >= 0 {
                        arrival := service.time(q, d.offsets[j])
                        if next[target] == nil || next[target].arrival > arrival {
                            update(next, target, arrival, extend(prefix, leg{kind:"ride", service:service, terminal:d.stops[len(d.stops) - 1], from:d.stops[boarding], to:target, depart:depart, arrive:arrival, stops:j - boarding}))
                            walking[target], updated[target] = true, true
                        }
                    }
                    if j + 1 < len(d.stops) && marked[target] {
                        previous := current[target]
                        ready := previous.arrival
                        if target != origin {
                            ready += target.transfer
                        }
                        candidate := service.firstTrain(d.offsets[j], ready)
                        if candidate >= 0 && (q < 0 || candidate < q) {
                            q, boarding, depart, prefix = candidate, j, service.time(candidate, d.offsets[j]), previous.journey
                        }
                    }
                }
            }
        }
        n.walkStep(next, walking, updated)
        result = append(result, next)
        current, marked = next, updated
    }
    return result
}

func counts(journey []leg) (int, int) {
    rides, walks := 0, 0
    for _, part := range journey {
        if part.kind == "ride" {
            rides++
        } else if part.kind == "walk" {
            walks++
        }
    }
    return rides, walks
}

func (n *network) printJourney(heading string, start int, result *label) {
    rides, walks := counts(result.journey)
    fmt.Fprintf(n.out, "%s %s -> %s total %d rides %d walks %d\n", heading, timeText(start), timeText(result.arrival), result.arrival - start, rides, walks)
    previous := start
    for _, part := range result.journey {
        if part.kind == "ride" {
            fmt.Fprintf(n.out, "RIDE %s toward %s %s %s -> %s %s wait %d stops %d\n", part.service.id, part.terminal.id, part.from.id, timeText(part.depart), part.to.id, timeText(part.arrive), part.depart - previous, part.stops)
        } else if part.kind == "walk" {
            fmt.Fprintf(n.out, "WALK %s %s -> %s %s\n", part.from.id, timeText(part.depart), part.to.id, timeText(part.arrive))
        } else {
            fmt.Fprintf(n.out, "STAY %s %s -> %s\n", part.from.id, timeText(part.depart), timeText(part.arrive))
        }
        previous = part.arrive
    }
}

func (n *network) getStation(id string) (*station, error) {
    s := n.stations[id]
    if s == nil {
        return nil, fmt.Errorf("unknown station %s", id)
    }
    return s, nil
}

func (n *network) getLine(id string) (*line, error) {
    l := n.lines[id]
    if l == nil {
        return nil, fmt.Errorf("unknown line %s", id)
    }
    return l, nil
}

func (n *network) common(origin, destination string) (*station, *station, error) {
    a, err := n.getStation(origin)
    if err != nil {
        return nil, nil, err
    }
    b, err := n.getStation(destination)
    if err != nil {
        return nil, nil, err
    }
    if a == b {
        return nil, nil, fmt.Errorf("origin and destination are the same")
    }
    if a.closed {
        return nil, nil, fmt.Errorf("station %s is closed", origin)
    }
    if b.closed {
        return nil, nil, fmt.Errorf("station %s is closed", destination)
    }
    return a, b, nil
}

func (n *network) segmentLines(a, b *station) []string {
    result := []string{}
    for _, id := range names(n.lines) {
        service := n.lines[id]
        for i := 1; i < len(service.stops); i++ {
            if service.stops[i - 1] == a && service.stops[i] == b || service.stops[i - 1] == b && service.stops[i] == a {
                result = append(result, id)
                break
            }
        }
    }
    return result
}

func half(price int) int {
    return (price + 19) / 20 * 10
}

func (n *network) fare(origin, destination string, start int, class string, result *label) {
    type ticket struct {
        part leg
        zones, price, discount int
    }
    tickets, total, previous := []ticket{}, 0, -1
    for _, part := range result.journey {
        if part.kind != "ride" {
            continue
        }
        a, b := indexOf(part.service.stops, part.from), indexOf(part.service.stops, part.to)
        if a > b {
            a, b = b, a
        }
        zones := map[int]bool{}
        for _, s := range part.service.stops[a:b + 1] {
            zones[s.zone] = true
        }
        count := len(zones)
        at := count - 1
        if at >= len(n.tariff.prices) {
            at = len(n.tariff.prices) - 1
        }
        price, cap := n.tariff.prices[at], n.tariff.discount
        if class == "CHILD" {
            price, cap = half(price), half(cap)
        }
        discount := 0
        if previous >= 0 && part.depart - previous <= n.tariff.window {
            discount = cap
            if price < discount {
                discount = price
            }
        }
        total += price - discount
        tickets = append(tickets, ticket{part, count, price, discount})
        previous = part.arrive
    }
    fmt.Fprintf(n.out, "FARE %s %s %s %s rides %d total %d\n", origin, destination, timeText(start), class, len(tickets), total)
    for _, ticket := range tickets {
        part := ticket.part
        fmt.Fprintf(n.out, "TICKET %s %s %s zones %d price %d discount %d pay %d\n", part.service.id, part.from.id, part.to.id, ticket.zones, ticket.price, ticket.discount, ticket.price - ticket.discount)
    }
}

func (n *network) command(w []string) error {
    cmd := w[0]
    switch cmd {
    case "STATION":
        if n.stations[w[1]] != nil {
            return fmt.Errorf("station %s already exists", w[1])
        }
        n.stations[w[1]] = &station{id:w[1], name:w[3], zone:number(w[2]), walks:map[string]int{}}
        fmt.Fprintf(n.out, "STATION %s zone %s %s\n", w[1], w[2], w[3])
    case "LINE":
        if n.lines[w[1]] != nil {
            return fmt.Errorf("line %s already exists", w[1])
        }
        stops := []*station{}
        for i := 5; i < len(w); i += 2 {
            s, err := n.getStation(w[i])
            if err != nil {
                return err
            }
            stops = append(stops, s)
        }
        seen := map[*station]bool{}
        for _, s := range stops {
            if seen[s] {
                return fmt.Errorf("station %s appears twice on line %s", s.id, w[1])
            }
            seen[s] = true
        }
        first, last := timeValue(w[2]), timeValue(w[3])
        if first > last {
            return fmt.Errorf("line %s first departure is after last departure", w[1])
        }
        cumulative := []int{0}
        for i := 6; i < len(w); i += 2 {
            cumulative = append(cumulative, cumulative[len(cumulative) - 1] + number(w[i]))
        }
        total := cumulative[len(cumulative) - 1]
        if last + total > 1440 {
            return fmt.Errorf("line %s runs past 24:00", w[1])
        }
        service := &line{id:w[1], first:first, last:last, headway:number(w[4]), total:total, stops:stops, cumulative:cumulative}
        n.lines[w[1]] = service
        fmt.Fprintf(n.out, "LINE %s stops %d time %d trips %d\n", w[1], len(stops), total, service.trains())
    case "TRANSFER":
        s, err := n.getStation(w[1])
        if err != nil {
            return err
        }
        s.transfer = number(w[2])
        fmt.Fprintf(n.out, "TRANSFER %s %d\n", s.id, s.transfer)
    case "WALK":
        a, err := n.getStation(w[1])
        if err != nil {
            return err
        }
        b, err := n.getStation(w[2])
        if err != nil {
            return err
        }
        if a == b {
            return fmt.Errorf("walk from %s to itself", w[1])
        }
        previous, exists := a.walks[b.id]
        minutes := number(w[3])
        a.walks[b.id], b.walks[a.id] = minutes, minutes
        fmt.Fprintf(n.out, "WALK %s %s %d", a.id, b.id, minutes)
        if exists {
            fmt.Fprintf(n.out, " was %d", previous)
        } else {
            n.walks++
        }
        fmt.Fprintln(n.out)
    case "TARIFF":
        prices := []int{}
        for _, word := range w[3:] {
            price := number(word)
            if len(prices) > 0 && price < prices[len(prices) - 1] {
                return fmt.Errorf("tariff prices must not decrease")
            }
            prices = append(prices, price)
        }
        n.tariff = &tariff{number(w[1]), number(w[2]), prices}
        fmt.Fprintf(n.out, "TARIFF zones %d discount %s window %s\n", len(prices), w[1], w[2])
    case "CLOSE", "OPEN":
        a, err := n.getStation(w[1])
        if err != nil {
            return err
        }
        if len(w) == 2 {
            if cmd == "CLOSE" && a.closed {
                return fmt.Errorf("station %s is already closed", a.id)
            }
            if cmd == "OPEN" && !a.closed {
                return fmt.Errorf("station %s is not closed", a.id)
            }
            a.closed = cmd == "CLOSE"
            fmt.Fprintf(n.out, "%s %s\n", cmd, a.id)
        } else {
            b, err := n.getStation(w[2])
            if err != nil {
                return err
            }
            key := pair(a.id, b.id)
            if cmd == "CLOSE" {
                lines := n.segmentLines(a, b)
                if len(lines) == 0 {
                    return fmt.Errorf("no segment %s-%s", a.id, b.id)
                }
                if n.closed[key] {
                    return fmt.Errorf("segment %s-%s is already closed", a.id, b.id)
                }
                n.closed[key] = true
                fmt.Fprintf(n.out, "CLOSE %s-%s lines %s\n", a.id, b.id, strings.Join(lines, " "))
            } else {
                if !n.closed[key] {
                    return fmt.Errorf("segment %s-%s is not closed", a.id, b.id)
                }
                delete(n.closed, key)
                fmt.Fprintf(n.out, "OPEN %s-%s\n", a.id, b.id)
            }
        }
    case "DELAY", "SUSPEND", "RESUME":
        service, err := n.getLine(w[1])
        if err != nil {
            return err
        }
        if cmd == "DELAY" {
            minutes := number(w[2])
            if service.last + minutes + service.total > 1440 {
                return fmt.Errorf("line %s runs past 24:00", service.id)
            }
            service.delay = minutes
            fmt.Fprintf(n.out, "DELAY %s %d\n", service.id, minutes)
        } else {
            if cmd == "SUSPEND" && service.suspended {
                return fmt.Errorf("line %s is already suspended", service.id)
            }
            if cmd == "RESUME" && !service.suspended {
                return fmt.Errorf("line %s is not suspended", service.id)
            }
            service.suspended = cmd == "SUSPEND"
            fmt.Fprintf(n.out, "%s %s\n", cmd, service.id)
        }
    case "ROUTE", "FEWEST", "PARETO", "FARE", "LASTTRAIN", "ARRIVEBY", "PROFILE":
        origin, destination, err := n.common(w[1], w[2])
        if err != nil {
            return err
        }
        if cmd == "FARE" {
            if w[4] != "ADULT" && w[4] != "CHILD" {
                return fmt.Errorf("unknown fare class %s", w[4])
            }
            if n.tariff == nil {
                return fmt.Errorf("no tariff")
            }
        }
        start := 0
        if len(w) > 3 {
            start = timeValue(w[3])
        }
        if cmd == "PROFILE" {
            end := timeValue(w[4])
            if start > end {
                return fmt.Errorf("empty interval %s %s", w[3], w[4])
            }
            arrivals := make([]int, end - start + 1)
            for t := start; t <= end; t++ {
                result := n.earliest(origin, t)[destination]
                arrivals[t - start] = -1
                if result != nil {
                    arrivals[t - start] = result.arrival
                }
            }
            selected := []int{}
            for i, arrival := range arrivals {
                if arrival >= 0 && (i == len(arrivals) - 1 || arrivals[i + 1] < 0 || arrival < arrivals[i + 1]) {
                    selected = append(selected, i)
                }
            }
            fmt.Fprintf(n.out, "PROFILE %s %s %s %s count %d\n", origin.id, destination.id, w[3], w[4], len(selected))
            for _, i := range selected {
                fmt.Fprintf(n.out, "%s -> %s total %d\n", timeText(start + i), timeText(arrivals[i]), arrivals[i] - start - i)
            }
        } else if cmd == "LASTTRAIN" || cmd == "ARRIVEBY" {
            latest := 1439
            heading := "LASTTRAIN " + origin.id + " " + destination.id
            if cmd == "ARRIVEBY" {
                latest = start - 1
                heading = "ARRIVEBY " + origin.id + " " + destination.id + " by " + w[3]
            }
            for t := latest; t >= 0; t-- {
                result := n.earliest(origin, t)[destination]
                if result != nil && (cmd == "LASTTRAIN" || result.arrival <= start) {
                    n.printJourney(heading, t, result)
                    return nil
                }
            }
            fmt.Fprintln(n.out, heading + " none")
        } else if cmd == "FEWEST" || cmd == "PARETO" {
            var stop *station
            if cmd == "FEWEST" {
                stop = destination
            }
            rounds := n.rounds(origin, start, stop)
            if cmd == "FEWEST" {
                for k, labels := range rounds {
                    if result := labels[destination]; result != nil {
                        n.printJourney(fmt.Sprintf("FEWEST %s %s trips %d", origin.id, destination.id, k), start, result)
                        return nil
                    }
                }
                fmt.Fprintf(n.out, "FEWEST %s %s %s unreachable\n", origin.id, destination.id, w[3])
            } else {
                options, previous := []int{}, -1
                for k, labels := range rounds {
                    if result := labels[destination]; result != nil {
                        if previous < 0 || result.arrival < previous {
                            options = append(options, k)
                        }
                        previous = result.arrival
                    }
                }
                fmt.Fprintf(n.out, "PARETO %s %s %s options %d\n", origin.id, destination.id, w[3], len(options))
                for _, k := range options {
                    n.printJourney(fmt.Sprintf("OPTION trips %d", k), start, rounds[k][destination])
                }
            }
        } else {
            result := n.earliest(origin, start)[destination]
            if result == nil {
                suffix := ""
                if cmd == "FARE" {
                    suffix = " " + w[4]
                }
                fmt.Fprintf(n.out, "%s %s %s %s%s unreachable\n", cmd, origin.id, destination.id, w[3], suffix)
            } else if cmd == "FARE" {
                n.fare(origin.id, destination.id, start, w[4], result)
            } else {
                n.printJourney("ROUTE " + origin.id + " " + destination.id, start, result)
            }
        }
    case "VIA":
        origin, err := n.getStation(w[1])
        if err != nil {
            return err
        }
        via, err := n.getStation(w[2])
        if err != nil {
            return err
        }
        destination, err := n.getStation(w[3])
        if err != nil {
            return err
        }
        if origin == destination {
            return fmt.Errorf("origin and destination are the same")
        }
        if via == origin || via == destination {
            return fmt.Errorf("via station %s must differ from origin and destination", via.id)
        }
        for _, s := range []*station{origin, via, destination} {
            if s.closed {
                return fmt.Errorf("station %s is closed", s.id)
            }
        }
        start := timeValue(w[4])
        first := n.earliest(origin, start)[via]
        if first != nil {
            ready := first.arrival + via.transfer
            second := n.earliest(via, ready)[destination]
            if second != nil {
                journey := extend(first.journey, leg{kind:"stay", from:via, to:via, depart:first.arrival, arrive:ready})
                journey = append(journey, second.journey...)
                n.printJourney("VIA " + origin.id + " " + via.id + " " + destination.id, start, &label{second.arrival, journey})
                return nil
            }
        }
        fmt.Fprintf(n.out, "VIA %s %s %s %s unreachable\n", origin.id, via.id, destination.id, w[4])
    case "REACH":
        origin, err := n.getStation(w[1])
        if err != nil {
            return err
        }
        if origin.closed {
            return fmt.Errorf("station %s is closed", origin.id)
        }
        start, duration := timeValue(w[2]), number(w[3])
        labels := n.earliest(origin, start)
        selected := []*station{}
        for s, result := range labels {
            if result.arrival <= start + duration {
                selected = append(selected, s)
            }
        }
        sort.Slice(selected, func(i, j int) bool {
            a, b := selected[i], selected[j]; if labels[a].arrival != labels[b].arrival {
                return labels[a].arrival < labels[b].arrival
            }; return a.id < b.id
        })
        fmt.Fprintf(n.out, "REACH %s %s %d count %d\n", origin.id, w[2], duration, len(selected))
        for _, s := range selected {
            result := labels[s]
            rides, _ := counts(result.journey)
            fmt.Fprintf(n.out, "%s %s %s %d rides %d\n", s.id, s.name, timeText(result.arrival), result.arrival - start, rides)
        }
    case "TIMETABLE":
        s, err := n.getStation(w[1])
        if err != nil {
            return err
        }
        service, err := n.getLine(w[2])
        if err != nil {
            return err
        }
        if indexOf(service.stops, s) < 0 {
            return fmt.Errorf("station %s is not on line %s", s.id, service.id)
        }
        first, last := service.stops[0], service.stops[len(service.stops) - 1]
        if w[3] != first.id && w[3] != last.id {
            return fmt.Errorf("%s is not a terminal of line %s", w[3], service.id)
        }
        if s.id == w[3] {
            return fmt.Errorf("no departures from %s toward %s", s.id, w[3])
        }
        if service.suspended {
            return fmt.Errorf("line %s is suspended", service.id)
        }
        if s.closed {
            return fmt.Errorf("station %s is closed", s.id)
        }
        which := 0
        if w[3] == first.id {
            which = 1
        }
        d := service.direction(which)
        at := indexOf(d.stops, s)
        q := service.firstTrain(d.offsets[at], timeValue(w[4]))
        times := []string{}
        if q >= 0 {
            for ; q < service.trains() && len(times) < number(w[5]); q++ {
                times = append(times, timeText(service.time(q, d.offsets[at])))
            }
        }
        fmt.Fprintf(n.out, "TIMETABLE %s %s toward %s %s next %d", s.id, service.id, w[3], w[4], len(times))
        for _, text := range times {
            fmt.Fprint(n.out, " " + text)
        }
        fmt.Fprintln(n.out)
    case "DEPARTURES", "ARRIVALS":
        s, err := n.getStation(w[1])
        if err != nil {
            return err
        }
        if s.closed {
            return fmt.Errorf("station %s is closed", s.id)
        }
        choices := []departure{}
        for _, id := range names(n.lines) {
            service := n.lines[id]
            if service.suspended {
                continue
            }
            for which := 0; which < 2; which++ {
                d := service.direction(which)
                at := indexOf(d.stops, s)
                if at < 0 || cmd == "DEPARTURES" && at == len(d.stops) - 1 || cmd == "ARRIVALS" && at == 0 {
                    continue
                }
                q := service.firstTrain(d.offsets[at], timeValue(w[2]))
                if q >= 0 {
                    for ; q < service.trains(); q++ {
                        choices = append(choices, departure{service.time(q, d.offsets[at]), service, which, d.stops[len(d.stops) - 1], d.stops[0]})
                    }
                }
            }
        }
        sort.Slice(choices, func(i, j int) bool {
            a, b := choices[i], choices[j]; if a.time != b.time {
                return a.time < b.time
            }; if a.service.id != b.service.id {
                return a.service.id < b.service.id
            }; return a.direction < b.direction
        })
        if len(choices) > number(w[3]) {
            choices = choices[:number(w[3])]
        }
        fmt.Fprintf(n.out, "%s %s %s count %d\n", cmd, s.id, w[2], len(choices))
        for _, choice := range choices {
            relation, target := "toward", choice.terminal
            if cmd == "ARRIVALS" {
                relation, target = "from", choice.start
            }
            fmt.Fprintf(n.out, "%s %s %s %s\n", timeText(choice.time), choice.service.id, relation, target.id)
        }
    case "TRIP", "SHOWLINE":
        service, err := n.getLine(w[1])
        if err != nil {
            return err
        }
        if cmd == "SHOWLINE" {
            state := "running"
            if service.suspended {
                state = "suspended"
            }
            fmt.Fprintf(n.out, "SHOWLINE %s %s first %s last %s headway %d delay %d trips %d\n", service.id, state, timeText(service.first), timeText(service.last), service.headway, service.delay, service.trains())
            for i, s := range service.stops {
                suffix := ""
                if s.closed {
                    suffix += " closed"
                }
                if i > 0 && n.closed[pair(service.stops[i - 1].id, s.id)] {
                    suffix += " blocked"
                }
                fmt.Fprintf(n.out, "%d %s zone %d%s\n", service.cumulative[i], s.id, s.zone, suffix)
            }
        } else {
            first, last := service.stops[0], service.stops[len(service.stops) - 1]
            if w[2] != first.id && w[2] != last.id {
                return fmt.Errorf("%s is not a terminal of line %s", w[2], service.id)
            }
            if service.suspended {
                return fmt.Errorf("line %s is suspended", service.id)
            }
            which := 0
            if w[2] == first.id {
                which = 1
            }
            d := service.direction(which)
            q := service.firstTrain(0, timeValue(w[3]))
            if q < 0 {
                fmt.Fprintf(n.out, "TRIP %s toward %s %s none\n", service.id, w[2], w[3])
                return nil
            }
            fmt.Fprintf(n.out, "TRIP %s toward %s %s trip %d departs %s\n", service.id, w[2], w[3], q + 1, timeText(service.time(q, 0)))
            for i, s := range d.stops {
                suffix := ""
                if s.closed {
                    suffix += " closed"
                }
                if i > 0 && n.closed[pair(d.stops[i - 1].id, s.id)] {
                    suffix += " blocked"
                }
                fmt.Fprintf(n.out, "%s %s%s\n", timeText(service.time(q, d.offsets[i])), s.id, suffix)
            }
        }
    case "INFO":
        s, err := n.getStation(w[1])
        if err != nil {
            return err
        }
        state := "open"
        if s.closed {
            state = "closed"
        }
        fmt.Fprintf(n.out, "INFO %s %s zone %d transfer %d %s\n", s.id, s.name, s.zone, s.transfer, state)
        lines := []string{}
        for _, id := range names(n.lines) {
            if indexOf(n.lines[id].stops, s) >= 0 {
                lines = append(lines, id)
            }
        }
        if len(lines) == 0 {
            lines = append(lines, "none")
        }
        fmt.Fprintln(n.out, "LINES " + strings.Join(lines, " "))
        walks := names(s.walks)
        fmt.Fprint(n.out, "WALKS")
        if len(walks) == 0 {
            fmt.Fprint(n.out, " none")
        }
        for _, id := range walks {
            fmt.Fprintf(n.out, " %s %d", id, s.walks[id])
        }
        fmt.Fprintln(n.out)
    case "STATUS":
        fmt.Fprintf(n.out, "STATUS stations %d lines %d walks %d\n", len(n.stations), len(n.lines), n.walks)
        for _, id := range names(n.stations) {
            if n.stations[id].closed {
                fmt.Fprintln(n.out, "CLOSED " + id)
            }
        }
        for _, key := range names(n.closed) {
            fields := strings.Split(key, "\x00")
            fmt.Fprintf(n.out, "CLOSED %s-%s\n", fields[0], fields[1])
        }
        for _, id := range names(n.lines) {
            if n.lines[id].suspended {
                fmt.Fprintln(n.out, "SUSPENDED " + id)
            }
        }
        for _, id := range names(n.lines) {
            if n.lines[id].delay != 0 {
                fmt.Fprintf(n.out, "DELAYED %s %d\n", id, n.lines[id].delay)
            }
        }
    }
    return nil
}

func main() {
    input, _ := io.ReadAll(os.Stdin)
    lines := strings.Split(string(input), "\n")
    count := number(lines[0])
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    n := network{stations:map[string]*station{}, lines:map[string]*line{}, closed:map[string]bool{}, out:out}
    for _, line := range lines[1:count + 1] {
        if err := n.command(strings.Split(line, " ")); err != nil {
            fmt.Fprintln(out, "ERROR " + err.Error())
        }
    }
}
