package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type stop struct {
	x, y, demand, service, open, close int
	window                             bool
}
type run struct{ returned, travel, wait, service, violations, lateness int }
type workbench struct {
	depot    *stop
	start    int
	stops    map[int]stop
	tour     []int
	routes   [][]int
	capacity int
	output   []string
}

func number(s string) int { n, _ := strconv.Atoi(s); return n }
func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
func clock(s string) int    { return number(s[:2])*60 + number(s[3:]) }
func timeText(t int) string { return fmt.Sprintf("%02d:%02d", t/60, t%60) }
func label(id int) string {
	if id == 0 {
		return "D"
	}
	return strconv.Itoa(id)
}
func clone(p []int) []int { return append([]int(nil), p...) }
func reverse(p []int) {
	for i, j := 0, len(p)-1; i < j; i, j = i+1, j-1 {
		p[i], p[j] = p[j], p[i]
	}
}
func place(p []int, index int, values []int) []int {
	result := make([]int, 0, len(p)+len(values))
	result = append(result, p[:index]...)
	result = append(result, values...)
	return append(result, p[index:]...)
}
func notation(p []int) string {
	list := []string{"D"}
	for _, id := range p {
		list = append(list, label(id))
	}
	return strings.Join(append(list, "D"), "-")
}
func (w *workbench) emit(format string, args ...any) {
	w.output = append(w.output, fmt.Sprintf(format, args...))
}
func (w *workbench) ids() []int {
	list := make([]int, 0, len(w.stops))
	for id := range w.stops {
		list = append(list, id)
	}
	sort.Ints(list)
	return list
}
func (w *workbench) distance(a, b int) int {
	x, y := w.stops[a], w.stops[b]
	if a == 0 {
		x = *w.depot
	}
	if b == 0 {
		y = *w.depot
	}
	return abs(x.x-y.x) + abs(x.y-y.y)
}
func (w *workbench) length(p []int) int {
	total, last := 0, 0
	for _, id := range p {
		total += w.distance(last, id)
		last = id
	}
	return total + w.distance(last, 0)
}
func (w *workbench) load(p []int) int {
	total := 0
	for _, id := range p {
		total += w.stops[id].demand
	}
	return total
}
func (w *workbench) total() int {
	total := 0
	for _, p := range w.routes {
		total += w.length(p)
	}
	return total
}
func (w *workbench) normalize() {
	result := [][]int{}
	for _, p := range w.routes {
		if len(p) > 0 {
			if p[0] > p[len(p)-1] {
				reverse(p)
			}
			result = append(result, p)
		}
	}
	minimum := func(p []int) int {
		value := p[0]
		for _, id := range p {
			if id < value {
				value = id
			}
		}
		return value
	}
	sort.Slice(result, func(i, j int) bool { return minimum(result[i]) < minimum(result[j]) })
	w.routes = result
}
func (w *workbench) routeLines() {
	for i, p := range w.routes {
		w.emit("route %d: %s load %d length %d", i+1, notation(p), w.load(p), w.length(p))
	}
}
func (w *workbench) simulate(p []int, display bool) run {
	result := run{travel: w.length(p)}
	t, last := w.start, 0
	for _, id := range p {
		item := w.stops[id]
		arrival := t + w.distance(last, id)
		wait, late := 0, 0
		if item.window {
			if arrival < item.open {
				wait = item.open - arrival
			}
			if arrival > item.close {
				late = arrival - item.close
			}
		}
		begin := arrival + wait
		t = begin + item.service
		last = id
		result.wait += wait
		result.service += item.service
		result.lateness += late
		status := "ok"
		if late > 0 {
			result.violations++
			status = fmt.Sprintf("late %d", late)
		}
		if display {
			w.emit("%d arrive %s wait %d begin %s leave %s %s", id, timeText(arrival), wait, timeText(begin), timeText(t), status)
		}
	}
	result.returned = t + w.distance(last, 0)
	if display {
		w.emit("return %s, travel %d, wait %d, service %d, violations %d, lateness %d", timeText(result.returned), result.travel, result.wait, result.service, result.violations, result.lateness)
	}
	return result
}
func (w *workbench) twoopt(p []int, display bool) int {
	moves := 0
	for {
		changed := false
		for i := 0; i < len(p)-1 && !changed; i++ {
			for j := i + 1; j < len(p); j++ {
				a, b := 0, 0
				if i > 0 {
					a = p[i-1]
				}
				if j+1 < len(p) {
					b = p[j+1]
				}
				gain := w.distance(a, p[i]) + w.distance(p[j], b) - w.distance(a, p[j]) - w.distance(p[i], b)
				if gain > 0 {
					if display {
						w.emit("reverse %d..%d gain %d", p[i], p[j], gain)
					}
					reverse(p[i : j+1])
					moves++
					changed = true
					break
				}
			}
		}
		if !changed {
			return moves
		}
	}
}
func (w *workbench) baseCheck() bool {
	if w.depot == nil {
		w.emit("error: no depot")
		return false
	}
	if len(w.stops) == 0 {
		w.emit("error: no stops")
		return false
	}
	return true
}
func (w *workbench) capacityCheck(q int) bool {
	for _, id := range w.ids() {
		if w.stops[id].demand > q {
			w.emit("error: stop %d demand %d exceeds capacity %d", id, w.stops[id].demand, q)
			return false
		}
	}
	return true
}
func (w *workbench) exact() []int {
	ids := w.ids()
	n := len(ids)
	full := (1 << n) - 1
	memo := map[[2]int]int{}
	var cost func(int, int) int
	cost = func(mask, last int) int {
		if mask == 0 {
			return w.distance(last, 0)
		}
		key := [2]int{mask, last}
		if value, ok := memo[key]; ok {
			return value
		}
		best := int(^uint(0) >> 1)
		for i, id := range ids {
			if mask&(1<<i) != 0 {
				value := w.distance(last, id) + cost(mask^(1<<i), id)
				if value < best {
					best = value
				}
			}
		}
		memo[key] = best
		return best
	}
	result := []int{}
	mask, last := full, 0
	for mask != 0 {
		best := cost(mask, last)
		for i, id := range ids {
			if mask&(1<<i) != 0 && w.distance(last, id)+cost(mask^(1<<i), id) == best {
				result = append(result, id)
				mask ^= 1 << i
				last = id
				break
			}
		}
	}
	return result
}
func (w *workbench) bound() {
	ids := w.ids()
	tree := []int{0}
	remaining := map[int]bool{}
	for _, id := range ids {
		remaining[id] = true
	}
	edges := []string{}
	mst := 0
	for len(remaining) > 0 {
		best, candidate, parent := int(^uint(0)>>1), 0, 0
		for _, id := range ids {
			if remaining[id] {
				for _, p := range tree {
					d := w.distance(p, id)
					if d < best {
						best, candidate, parent = d, id, p
					}
				}
			}
		}
		mst += best
		edges = append(edges, label(parent)+"-"+label(candidate))
		tree = append(tree, candidate)
		delete(remaining, candidate)
	}
	one := 2 * w.distance(0, ids[0])
	if len(ids) > 1 {
		distances := []int{}
		for _, id := range ids {
			distances = append(distances, w.distance(0, id))
		}
		sort.Ints(distances)
		one = distances[0] + distances[1]
		used := map[int]bool{ids[0]: true}
		for len(used) < len(ids) {
			best, candidate := int(^uint(0)>>1), 0
			for _, a := range ids {
				if used[a] {
					for _, b := range ids {
						if !used[b] && w.distance(a, b) < best {
							best, candidate = w.distance(a, b), b
						}
					}
				}
			}
			one += best
			used[candidate] = true
		}
	}
	best := mst
	if one > best {
		best = one
	}
	w.emit("mst: %s (length %d)", strings.Join(edges, " "), mst)
	w.emit("bound: mst %d, one-tree %d, best %d", mst, one, best)
	if w.tour == nil {
		w.emit("gap: no tour")
	} else {
		length, u := w.length(w.tour), 0
		if best > 0 {
			u = (2000*(length-best) + best) / (2 * best)
		}
		w.emit("gap: tour %d, %d.%d%%", length, u/10, u%10)
	}
}
func (w *workbench) improve(command string) {
	initial, k0, moves := w.total(), len(w.routes), 0
	for {
		changed := false
		switch command {
		case "RELOCATE":
		scan:
			for r, a := range w.routes {
				for p, c := range a {
					for t, b := range w.routes {
						if r == t || w.load(b)+w.stops[c].demand > w.capacity {
							continue
						}
						for j := 0; j <= len(b); j++ {
							before, after, u, v := 0, 0, 0, 0
							if p > 0 {
								before = a[p-1]
							}
							if p+1 < len(a) {
								after = a[p+1]
							}
							if j > 0 {
								u = b[j-1]
							}
							if j < len(b) {
								v = b[j]
							}
							gain := w.distance(before, c) + w.distance(c, after) - w.distance(before, after) - w.distance(u, c) - w.distance(c, v) + w.distance(u, v)
							if gain > 0 {
								w.emit("relocate %d from route %d to route %d after %s gain %d", c, r+1, t+1, label(u), gain)
								w.routes[r] = append(clone(a[:p]), a[p+1:]...)
								w.routes[t] = place(b, j, []int{c})
								changed = true
								break scan
							}
						}
					}
				}
			}
		case "EXCHANGE":
		scan:
			for r, a := range w.routes {
				for t := r + 1; t < len(w.routes); t++ {
					b := w.routes[t]
					for p, c := range a {
						for j, e := range b {
							if w.load(a)-w.stops[c].demand+w.stops[e].demand > w.capacity || w.load(b)-w.stops[e].demand+w.stops[c].demand > w.capacity {
								continue
							}
							before := w.length(a) + w.length(b)
							a[p], b[j] = e, c
							gain := before - w.length(a) - w.length(b)
							if gain > 0 {
								w.emit("exchange %d (route %d) with %d (route %d) gain %d", c, r+1, e, t+1, gain)
								changed = true
								break scan
							}
							a[p], b[j] = c, e
						}
					}
				}
			}
		case "CROSS":
		scan:
			for r, a := range w.routes {
				for t := r + 1; t < len(w.routes); t++ {
					b := w.routes[t]
					for i := 0; i <= len(a); i++ {
						for j := 0; j <= len(b); j++ {
							x := append(clone(a[:i]), b[j:]...)
							y := append(clone(b[:j]), a[i:]...)
							if w.load(x) > w.capacity || w.load(y) > w.capacity {
								continue
							}
							gain := w.length(a) + w.length(b) - w.length(x) - w.length(y)
							if gain > 0 {
								u, v := 0, 0
								if i > 0 {
									u = a[i-1]
								}
								if j > 0 {
									v = b[j-1]
								}
								w.emit("cross route %d after %s with route %d after %s gain %d", r+1, label(u), t+1, label(v), gain)
								w.routes[r], w.routes[t] = x, y
								changed = true
								break scan
							}
						}
					}
				}
			}
		}
		if !changed {
			break
		}
		moves++
		w.normalize()
	}
	lower := strings.ToLower(command)
	if command == "EXCHANGE" {
		w.emit("%s: moves %d, length %d -> %d", lower, moves, initial, w.total())
	} else {
		w.emit("%s: moves %d, routes %d -> %d, length %d -> %d", lower, moves, k0, len(w.routes), initial, w.total())
	}
}
func (w *workbench) construct(command string, args []string) {
	q := number(args[0])
	if !w.capacityCheck(q) {
		return
	}
	limit := 0
	if command == "VRP" && len(args) > 1 {
		limit = number(args[1])
		for _, id := range w.ids() {
			if 2*w.distance(0, id) > limit {
				w.emit("error: stop %d too far for limit %d", id, limit)
				return
			}
		}
	}
	routes := [][]int{}
	merges := 0
	if command == "VRP" {
		ids := w.ids()
		for _, id := range ids {
			routes = append(routes, []int{id})
		}
		type saving struct{ i, j, value int }
		pairs := []saving{}
		for i, a := range ids {
			for _, b := range ids[i+1:] {
				value := w.distance(0, a) + w.distance(0, b) - w.distance(a, b)
				if value > 0 {
					pairs = append(pairs, saving{a, b, value})
				}
			}
		}
		sort.Slice(pairs, func(i, j int) bool {
			a, b := pairs[i], pairs[j]
			if a.value != b.value {
				return a.value > b.value
			}
			if a.i != b.i {
				return a.i < b.i
			}
			return a.j < b.j
		})
		for _, pair := range pairs {
			r, t := -1, -1
			for k, p := range routes {
				for _, id := range p {
					if id == pair.i {
						r = k
					}
					if id == pair.j {
						t = k
					}
				}
			}
			if r == t {
				continue
			}
			a, b := routes[r], routes[t]
			if a[0] != pair.i && a[len(a)-1] != pair.i ||
				b[0] != pair.j && b[len(b)-1] != pair.j || w.load(a)+w.load(b) > q {
				continue
			}
			a, b = clone(a), clone(b)
			if a[0] == pair.i {
				reverse(a)
			}
			if b[len(b)-1] == pair.j {
				reverse(b)
			}
			joined := append(a, b...)
			if limit > 0 && w.length(joined) > limit {
				continue
			}
			routes[r] = joined
			routes = append(routes[:t], routes[t+1:]...)
			merges++
		}
	} else if command == "SPLIT" {
		p := w.tour
		cost, previous := make([]int, len(p)+1), make([]int, len(p)+1)
		for j := 1; j <= len(p); j++ {
			cost[j] = int(^uint(0) >> 1)
			for i := 0; i < j; i++ {
				if w.load(p[i:j]) > q {
					continue
				}
				value := cost[i] + w.length(p[i:j])
				if value < cost[j] {
					cost[j], previous[j] = value, i
				}
			}
		}
		for j := len(p); j > 0; {
			i := previous[j]
			routes = append(routes, clone(p[i:j]))
			j = i
		}
	} else {
		ids := w.ids()
		sort.Slice(ids, func(i, j int) bool {
			a, b := w.stops[ids[i]], w.stops[ids[j]]
			ax, ay := a.x-w.depot.x, a.y-w.depot.y
			bx, by := b.x-w.depot.x, b.y-w.depot.y
			az, bz := ax == 0 && ay == 0, bx == 0 && by == 0
			if az != bz {
				return az
			}
			if az {
				return ids[i] < ids[j]
			}
			ah, bh := ay > 0 || ay == 0 && ax > 0, by > 0 || by == 0 && bx > 0
			if ah != bh {
				return ah
			}
			cross := ax*by - ay*bx
			if cross != 0 {
				return cross > 0
			}
			da, db := abs(ax)+abs(ay), abs(bx)+abs(by)
			if da != db {
				return da < db
			}
			return ids[i] < ids[j]
		})
		current := []int{}
		for _, id := range ids {
			if w.load(current)+w.stops[id].demand > q {
				routes = append(routes, current)
				current = []int{}
			}
			current = append(current, id)
		}
		routes = append(routes, current)
	}
	w.routes, w.capacity = routes, q
	w.normalize()
	if command == "VRP" {
		w.emit("vrp: capacity %d, merges %d, routes %d, length %d", q, merges, len(w.routes), w.total())
	} else {
		w.emit("%s: capacity %d, routes %d, length %d", strings.ToLower(command), q, len(w.routes), w.total())
	}
	w.routeLines()
}
func (w *workbench) improveTour(command string) {
	before, moves := w.length(w.tour), 0
	for {
		changed := false
		p := w.tour
		length := w.length(p)
		if command == "SWAP" {
		scan:
			for i := 0; i < len(p)-1; i++ {
				for j := i + 1; j < len(p); j++ {
					a, b := p[i], p[j]
					p[i], p[j] = b, a
					gain := length - w.length(p)
					if gain > 0 {
						w.emit("swap %d and %d gain %d", a, b, gain)
						changed = true
						break scan
					}
					p[i], p[j] = a, b
				}
			}
		} else {
		scan:
			for size := 1; size <= 3; size++ {
				for i := 0; i+size <= len(p); i++ {
					segment := clone(p[i : i+size])
					rest := append(clone(p[:i]), p[i+size:]...)
					for j := 0; j <= len(rest); j++ {
						if j == i {
							continue
						}
						candidate := place(rest, j, segment)
						gain := length - w.length(candidate)
						if gain > 0 {
							names := []string{}
							for _, id := range segment {
								names = append(names, label(id))
							}
							after := 0
							if j > 0 {
								after = rest[j-1]
							}
							w.emit("move %s after %s gain %d", strings.Join(names, "-"), label(after), gain)
							w.tour = candidate
							changed = true
							break scan
						}
					}
				}
			}
		}
		if !changed {
			break
		}
		moves++
	}
	w.emit("%s: moves %d, length %d -> %d", strings.ToLower(command), moves, before, w.length(w.tour))
}
func (w *workbench) report() {
	demand, service, windows := 0, 0, 0
	for _, item := range w.stops {
		demand += item.demand
		service += item.service
		if item.window {
			windows++
		}
	}
	w.emit("report: stops %d, demand %d, service %d, windows %d", len(w.stops), demand, service, windows)
	if w.tour == nil {
		w.emit("tour: none")
	} else {
		r := w.simulate(w.tour, false)
		w.emit("tour: length %d, return %s, violations %d, lateness %d", r.travel, timeText(r.returned), r.violations, r.lateness)
	}
	if w.routes == nil {
		w.emit("plan: none")
		return
	}
	returned, violations, lateness := 0, 0, 0
	for _, p := range w.routes {
		r := w.simulate(p, false)
		if r.returned > returned {
			returned = r.returned
		}
		violations += r.violations
		lateness += r.lateness
	}
	denominator := len(w.routes) * w.capacity
	utilization := (2000*demand + denominator) / (2 * denominator)
	w.emit("plan: capacity %d, routes %d, length %d, utilization %d.%d%%, return %s, violations %d, lateness %d",
		w.capacity, len(w.routes), w.total(), utilization/10, utilization%10, timeText(returned), violations, lateness)
}
func (w *workbench) command(line string) {
	fields := strings.Split(line, " ")
	command, args := fields[0], fields[1:]
	switch command {
	case "DEPOT":
		w.depot = &stop{x: number(args[0]), y: number(args[1])}
		w.emit("depot at (%d,%d)", w.depot.x, w.depot.y)
		return
	case "START":
		w.start = clock(args[0])
		w.emit("start %s", timeText(w.start))
		return
	case "STOP":
		id := number(args[0])
		if _, exists := w.stops[id]; exists {
			w.emit("error: stop %d already exists", id)
			return
		}
		item := stop{x: number(args[1]), y: number(args[2]), demand: number(args[3]), service: number(args[4])}
		if len(args) > 5 {
			item.window, item.open, item.close = true, clock(args[5]), clock(args[6])
			if item.open > item.close {
				w.emit("error: invalid window")
				return
			}
		}
		w.stops[id], w.tour, w.routes = item, nil, nil
		w.emit("stop %d added", id)
		return
	case "REMOVE":
		id := number(args[0])
		if _, exists := w.stops[id]; !exists {
			w.emit("error: unknown stop %d", id)
			return
		}
		delete(w.stops, id)
		remove := func(p []int) []int {
			result := []int{}
			for _, value := range p {
				if value != id {
					result = append(result, value)
				}
			}
			return result
		}
		if len(w.stops) == 0 {
			w.tour, w.routes = nil, nil
		} else {
			if w.tour != nil {
				w.tour = remove(w.tour)
			}
			if w.routes != nil {
				for i, p := range w.routes {
					w.routes[i] = remove(p)
				}
				w.normalize()
			}
		}
		w.emit("stop %d removed", id)
		return
	case "LIST":
		if w.depot == nil {
			w.emit("depot none")
		} else {
			w.emit("depot (%d,%d)", w.depot.x, w.depot.y)
		}
		w.emit("start %s", timeText(w.start))
		w.emit("stops %d", len(w.stops))
		for _, id := range w.ids() {
			item := w.stops[id]
			window := "none"
			if item.window {
				window = timeText(item.open) + "-" + timeText(item.close)
			}
			w.emit("%d at (%d,%d) demand %d service %d window %s", id, item.x, item.y, item.demand, item.service, window)
		}
		return
	case "MATRIX":
		if w.depot == nil {
			w.emit("error: no depot")
			return
		}
		ids, width := append([]int{0}, w.ids()...), 1
		for _, a := range ids {
			if len(label(a)) > width {
				width = len(label(a))
			}
			for _, b := range ids {
				if n := len(strconv.Itoa(w.distance(a, b))); n > width {
					width = n
				}
			}
		}
		header := fmt.Sprintf("%*s", width, "")
		for _, id := range ids {
			header += fmt.Sprintf(" %*s", width, label(id))
		}
		w.emit("%s", header)
		for _, a := range ids {
			row := fmt.Sprintf("%*s", width, label(a))
			for _, b := range ids {
				row += fmt.Sprintf(" %*d", width, w.distance(a, b))
			}
			w.emit("%s", row)
		}
		return
	case "REPORT":
		w.report()
		return
	}
	needsTour := containsCommand(command, "TOUR", "TWOOPT", "OROPT", "SWAP", "SPLIT") || command == "TIMECHECK" && len(args) == 0
	needsPlan := containsCommand(command, "ROUTES", "RELOCATE", "EXCHANGE", "CROSS", "ROUTEOPT", "TIMECHECK")
	if needsTour {
		if w.tour == nil {
			w.emit("error: no tour")
			return
		}
	} else if needsPlan {
		if w.routes == nil {
			w.emit("error: no plan")
			return
		}
	} else if !w.baseCheck() {
		return
	}
	switch command {
	case "ORDER":
		list := []int{}
		for _, arg := range args {
			id := number(arg)
			if _, exists := w.stops[id]; !exists {
				w.emit("error: unknown stop %d", id)
				return
			}
			list = append(list, id)
		}
		seen := map[int]bool{}
		for _, id := range list {
			if seen[id] {
				w.emit("error: duplicate stop %d", id)
				return
			}
			seen[id] = true
		}
		if len(list) != len(w.stops) {
			w.emit("error: order has %d stops, expected %d", len(list), len(w.stops))
			return
		}
		w.tour = list
		w.emit("order: %s length %d", notation(list), w.length(list))
	case "NEAREST", "INSERTION", "EXACT":
		if command == "EXACT" && len(w.stops) > 10 {
			w.emit("error: too many stops for exact (%d)", len(w.stops))
			return
		}
		list := []int{}
		remaining := map[int]bool{}
		for _, id := range w.ids() {
			remaining[id] = true
		}
		if command == "EXACT" {
			list = w.exact()
		} else {
			for len(remaining) > 0 {
				best, candidate, position := int(^uint(0)>>1), 0, 0
				for _, id := range w.ids() {
					if !remaining[id] {
						continue
					}
					if command == "NEAREST" {
						last := 0
						if len(list) > 0 {
							last = list[len(list)-1]
						}
						distance := w.distance(last, id)
						if distance < best {
							best, candidate, position = distance, id, len(list)
						}
					} else {
						for j := 0; j <= len(list); j++ {
							a, b := 0, 0
							if j > 0 {
								a = list[j-1]
							}
							if j < len(list) {
								b = list[j]
							}
							increase := w.distance(a, id) + w.distance(id, b) - w.distance(a, b)
							if increase < best {
								best, candidate, position = increase, id, j
							}
						}
					}
				}
				list = place(list, position, []int{candidate})
				delete(remaining, candidate)
			}
		}
		w.tour = list
		w.emit("%s: %s length %d", strings.ToLower(command), notation(list), w.length(list))
	case "TOUR":
		w.emit("tour: %s length %d", notation(w.tour), w.length(w.tour))
	case "TWOOPT":
		before := w.length(w.tour)
		moves := w.twoopt(w.tour, true)
		w.emit("twoopt: moves %d, length %d -> %d", moves, before, w.length(w.tour))
	case "SWAP", "OROPT":
		w.improveTour(command)
	case "TIMECHECK":
		if len(args) == 0 {
			w.emit("timecheck tour depart %s", timeText(w.start))
			w.simulate(w.tour, true)
		} else {
			r := number(args[0])
			if r > len(w.routes) {
				w.emit("error: no route %d", r)
				return
			}
			w.emit("timecheck route %d depart %s", r, timeText(w.start))
			w.simulate(w.routes[r-1], true)
		}
	case "BOUND":
		w.bound()
	case "VRP", "SPLIT", "SWEEP":
		w.construct(command, args)
	case "ROUTES":
		w.emit("plan: capacity %d, routes %d, length %d", w.capacity, len(w.routes), w.total())
		w.routeLines()
	case "RELOCATE", "EXCHANGE", "CROSS":
		w.improve(command)
	case "ROUTEOPT":
		before := w.total()
		for i, p := range w.routes {
			old := w.length(p)
			moves := w.twoopt(p, false)
			w.emit("route %d: moves %d, length %d -> %d", i+1, moves, old, w.length(p))
		}
		w.normalize()
		w.emit("routeopt: length %d -> %d", before, w.total())
	}
}
func containsCommand(command string, names ...string) bool {
	for _, name := range names {
		if command == name {
			return true
		}
	}
	return false
}
func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	count := number(scanner.Text())
	w := workbench{start: 480, stops: map[int]stop{}}
	for i := 0; i < count && scanner.Scan(); i++ {
		w.command(scanner.Text())
	}
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	for _, line := range w.output {
		fmt.Fprintln(out, line)
	}
}
