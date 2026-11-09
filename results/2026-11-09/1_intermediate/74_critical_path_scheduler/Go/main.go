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

type task struct {
	name, resource                  string
	base, units, notBefore, crashed int
	crash                           bool
	crashLimit, cost                int
	estimate                        []int
}

type dependency struct {
	from, to, kind string
	lag            int
}

type timing struct{ es, ef, ls, lf, tf, free int }
type schedule struct {
	times map[string]timing
	total int
}
type baseline struct {
	times map[string][2]int
	total int
}
type project struct {
	tasks           map[string]*task
	deps            map[string]dependency
	capacities      map[string]int
	holidays        map[int]bool
	start, deadline *int
	baseline        *baseline
	out             *bufio.Writer
}

func number(s string) int { n, _ := strconv.Atoi(s); return n }
func keys[T any](items map[string]T) []string {
	result := []string{}
	for name := range items {
		result = append(result, name)
	}
	sort.Strings(result)
	return result
}
func leap(year int) bool { return year%4 == 0 && year%100 != 0 || year%400 == 0 }
func monthDays(year, month int) int {
	days := []int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	if month == 2 && leap(year) {
		return 29
	}
	return days[month-1]
}
func dateValue(text string) (int, bool) {
	year, month, day := number(text[:4]), number(text[5:7]), number(text[8:])
	if month < 1 || month > 12 || day < 1 || day > monthDays(year, month) {
		return 0, false
	}
	total := day - 1
	for y := 2000; y < year; y++ {
		total += 365
		if leap(y) {
			total++
		}
	}
	for m := 1; m < month; m++ {
		total += monthDays(year, m)
	}
	return total, true
}
func dateText(ordinal int) string {
	original, year, month := ordinal, 2000, 1
	for {
		count := 365
		if leap(year) {
			count++
		}
		if ordinal < count {
			break
		}
		ordinal -= count
		year++
	}
	for ordinal >= monthDays(year, month) {
		ordinal -= monthDays(year, month)
		month++
	}
	weekdays := []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
	return fmt.Sprintf("%04d-%02d-%02d %s", year, month, ordinal+1, weekdays[(original+5)%7])
}
func decimal(numerator, denominator int) string {
	hundredths := numerator * 100 / denominator
	return fmt.Sprintf("%d.%02d", hundredths/100, hundredths%100)
}
func (p *project) get(name string) (*task, error) {
	t := p.tasks[name]
	if t == nil {
		return nil, fmt.Errorf("unknown task %s", name)
	}
	return t, nil
}
func (p *project) predecessors(name string) []dependency {
	result := []dependency{}
	for _, dep := range p.deps {
		if dep.to == name {
			result = append(result, dep)
		}
	}
	sort.Slice(result, func(i, j int) bool { return result[i].from < result[j].from })
	return result
}
func (p *project) successors(name string) []dependency {
	result := []dependency{}
	for _, dep := range p.deps {
		if dep.from == name {
			result = append(result, dep)
		}
	}
	sort.Slice(result, func(i, j int) bool { return result[i].to < result[j].to })
	return result
}
func (p *project) topology() ([]string, string) {
	names, removed, order := keys(p.tasks), map[string]bool{}, []string{}
	for {
		selected := ""
		for _, name := range names {
			if removed[name] {
				continue
			}
			ready := true
			for _, dep := range p.predecessors(name) {
				if !removed[dep.from] {
					ready = false
					break
				}
			}
			if ready {
				selected = name
				break
			}
		}
		if selected == "" {
			break
		}
		removed[selected] = true
		order = append(order, selected)
	}
	if len(order) == len(names) {
		return order, ""
	}
	current := ""
	for _, name := range names {
		if !removed[name] {
			current = name
			break
		}
	}
	visited, chain := map[string]int{}, []string{}
	for {
		if at, exists := visited[current]; exists {
			cycle := []string{chain[at]}
			for i := len(chain) - 1; i > at; i-- {
				cycle = append(cycle, chain[i])
			}
			first := 0
			for i, name := range cycle {
				if name < cycle[first] {
					first = i
				}
			}
			cycle = append(append([]string{}, cycle[first:]...), cycle[:first]...)
			cycle = append(cycle, cycle[0])
			return order, strings.Join(cycle, " -> ")
		}
		visited[current] = len(chain)
		chain = append(chain, current)
		for _, dep := range p.predecessors(current) {
			if !removed[dep.from] {
				current = dep.from
				break
			}
		}
	}
}
func (p *project) duration(name string, override map[string]int) int {
	if value, exists := override[name]; exists {
		return value
	}
	t := p.tasks[name]
	return t.base - t.crashed
}
func (p *project) compute(order []string, override map[string]int) schedule {
	result := schedule{times: map[string]timing{}}
	for _, name := range order {
		start, duration := p.tasks[name].notBefore, p.duration(name, override)
		for _, dep := range p.predecessors(name) {
			previous := result.times[dep.from]
			value := previous.ef + dep.lag
			if dep.kind == "SS" {
				value = previous.es + dep.lag
			}
			if dep.kind == "FF" {
				value -= duration
			}
			start = max(start, value)
		}
		result.times[name] = timing{es: start, ef: start + duration}
		result.total = max(result.total, start+duration)
	}
	for i := len(order) - 1; i >= 0; i-- {
		name := order[i]
		value, duration := result.times[name], p.duration(name, override)
		finish := result.total
		for _, dep := range p.successors(name) {
			next := result.times[dep.to]
			candidate := next.ls - dep.lag
			if dep.kind == "SS" {
				candidate += duration
			}
			if dep.kind == "FF" {
				candidate = next.lf - dep.lag
			}
			finish = min(finish, candidate)
		}
		value.lf, value.ls = finish, finish-duration
		value.tf, value.free = value.ls-value.es, result.total-value.ef
		result.times[name] = value
	}
	for _, name := range order {
		value := result.times[name]
		for _, dep := range p.successors(name) {
			value.free = min(value.free, margin(dep, result))
		}
		result.times[name] = value
	}
	return result
}
func margin(dep dependency, s schedule) int {
	a, b := s.times[dep.from], s.times[dep.to]
	if dep.kind == "SS" {
		return b.es - a.es - dep.lag
	}
	if dep.kind == "FF" {
		return b.ef - a.ef - dep.lag
	}
	return b.es - a.ef - dep.lag
}
func (p *project) critical(s schedule) []string {
	result := []string{}
	for _, name := range keys(p.tasks) {
		if s.times[name].tf == 0 {
			result = append(result, name)
		}
	}
	return result
}
func (p *project) criticalPaths(s schedule) [][]string {
	following, incoming := map[string][]string{}, map[string]bool{}
	for _, name := range keys(p.tasks) {
		for _, dep := range p.successors(name) {
			if s.times[name].tf == 0 && s.times[dep.to].tf == 0 && margin(dep, s) == 0 {
				following[name] = append(following[name], dep.to)
				incoming[dep.to] = true
			}
		}
	}
	result := [][]string{}
	var visit func(string, []string)
	visit = func(name string, prefix []string) {
		path := append(append([]string{}, prefix...), name)
		if len(following[name]) == 0 {
			result = append(result, path)
			return
		}
		for _, next := range following[name] {
			visit(next, path)
		}
	}
	for _, name := range p.critical(s) {
		if !incoming[name] {
			visit(name, nil)
		}
	}
	return result
}
func (p *project) resources() []string {
	all := map[string]bool{}
	for _, t := range p.tasks {
		all[t.resource] = true
	}
	return keys(all)
}
func (p *project) usage(s schedule, resource string) []int {
	result := make([]int, s.total)
	for name, t := range p.tasks {
		if t.resource == resource {
			value := s.times[name]
			for day := value.es; day < value.ef; day++ {
				result[day] += t.units
			}
		}
	}
	return result
}
func peak(values []int) int {
	result := 0
	for _, value := range values {
		result = max(result, value)
	}
	return result
}
func (p *project) workingDay(day int) bool { return (day+5)%7 < 5 && !p.holidays[day] }
func (p *project) calendar(s schedule) {
	days := []int{}
	for day := *p.start; len(days) < s.total; day++ {
		if p.workingDay(day) {
			days = append(days, day)
		}
	}
	names := keys(p.tasks)
	sort.Slice(names, func(i, j int) bool {
		a, b := s.times[names[i]].es, s.times[names[j]].es
		if a != b {
			return a < b
		}
		return names[i] < names[j]
	})
	for _, name := range names {
		value := s.times[name]
		fmt.Fprintf(p.out, "%s %s - %s\n", name, dateText(days[value.es]), dateText(days[value.ef-1]))
	}
	first, last := days[0], days[len(days)-1]
	fmt.Fprintf(p.out, "project %s - %s, %d working days, %d calendar days\n", dateText(first), dateText(last), s.total, last-first+1)
	if p.deadline != nil {
		a, b, count := last, *p.deadline, 0
		if a > b {
			a, b = b, a
		}
		for day := a + 1; day <= b; day++ {
			if p.workingDay(day) {
				count++
			}
		}
		if last <= *p.deadline {
			fmt.Fprintf(p.out, "deadline %s met, %d working days to spare\n", dateText(*p.deadline), count)
		} else {
			fmt.Fprintf(p.out, "deadline %s missed by %d working days\n", dateText(*p.deadline), count)
		}
	}
	holidays := []int{}
	for day := range p.holidays {
		if day >= first && day <= last && (day+5)%7 < 5 {
			holidays = append(holidays, day)
		}
	}
	sort.Ints(holidays)
	text := []string{}
	for _, day := range holidays {
		text = append(text, dateText(day))
	}
	if len(text) == 0 {
		text = append(text, "none")
	}
	fmt.Fprintln(p.out, "holidays in span: "+strings.Join(text, ", "))
}
func (p *project) level(order []string, s schedule, limit int) error {
	capacity := func(resource string) int {
		if value, exists := p.capacities[resource]; exists {
			return value
		}
		return limit
	}
	for _, name := range keys(p.tasks) {
		t := p.tasks[name]
		if t.units > capacity(t.resource) {
			return fmt.Errorf("capacity %d too small for %s", capacity(t.resource), name)
		}
	}
	decided, loads, sequence := map[string]timing{}, map[string][]int{}, []string{}
	total := 0
	for len(sequence) < len(order) {
		selected := ""
		for _, name := range keys(p.tasks) {
			if _, exists := decided[name]; exists {
				continue
			}
			ready := true
			for _, dep := range p.predecessors(name) {
				if _, exists := decided[dep.from]; !exists {
					ready = false
					break
				}
			}
			if ready && (selected == "" || s.times[name].ls < s.times[selected].ls) {
				selected = name
			}
		}
		t := p.tasks[selected]
		start, duration := t.notBefore, p.duration(selected, nil)
		for _, dep := range p.predecessors(selected) {
			a := decided[dep.from]
			value := a.ef + dep.lag
			if dep.kind == "SS" {
				value = a.es + dep.lag
			}
			if dep.kind == "FF" {
				value -= duration
			}
			start = max(start, value)
		}
		load := loads[t.resource]
		for {
			valid := true
			for day := start; day < start+duration && day < len(load); day++ {
				if load[day]+t.units > capacity(t.resource) {
					valid = false
					break
				}
			}
			if valid {
				break
			}
			start++
		}
		for len(load) < start+duration {
			load = append(load, 0)
		}
		for day := start; day < start+duration; day++ {
			load[day] += t.units
		}
		loads[t.resource] = load
		decided[selected] = timing{es: start, ef: start + duration}
		sequence = append(sequence, selected)
		total = max(total, start+duration)
	}
	fmt.Fprintf(p.out, "level capacity %d: duration %d -> %d\n", limit, s.total, total)
	for _, name := range sequence {
		value := decided[name]
		fmt.Fprintf(p.out, "%s start %d finish %d shift %d\n", name, value.es, value.ef, value.es-s.times[name].es)
	}
	for _, resource := range p.resources() {
		fmt.Fprintf(p.out, "resource %s capacity %d peak %d -> %d\n", resource, capacity(resource), peak(p.usage(s, resource)), peak(loads[resource]))
	}
	return nil
}

func (p *project) command(w []string) error {
	cmd := w[0]
	switch cmd {
	case "TASK":
		if p.tasks[w[1]] != nil {
			return fmt.Errorf("task %s already exists", w[1])
		}
		p.tasks[w[1]] = &task{name: w[1], base: number(w[2]), resource: w[3], units: number(w[4])}
		fmt.Fprintf(p.out, "task %s added\n", w[1])
		return nil
	case "DEP", "UNDEP":
		if _, err := p.get(w[1]); err != nil {
			return err
		}
		if _, err := p.get(w[2]); err != nil {
			return err
		}
		key := w[1] + "\x00" + w[2]
		if cmd == "DEP" {
			if w[1] == w[2] {
				return fmt.Errorf("self dependency %s", w[1])
			}
			if _, exists := p.deps[key]; exists {
				return fmt.Errorf("dependency %s -> %s already exists", w[1], w[2])
			}
			p.deps[key] = dependency{w[1], w[2], w[3], number(w[4])}
			fmt.Fprintf(p.out, "dependency %s -> %s %s%+d added\n", w[1], w[2], w[3], number(w[4]))
		} else {
			if _, exists := p.deps[key]; !exists {
				return fmt.Errorf("no dependency %s -> %s", w[1], w[2])
			}
			delete(p.deps, key)
			fmt.Fprintf(p.out, "dependency %s -> %s removed\n", w[1], w[2])
		}
		return nil
	case "REMOVE", "NOTBEFORE", "CRASHCOST", "UNCRASH", "PERT", "SHOW", "IMPACT":
		t, err := p.get(w[1])
		if err != nil {
			return err
		}
		switch cmd {
		case "REMOVE":
			count := 0
			for key, dep := range p.deps {
				if dep.from == t.name || dep.to == t.name {
					delete(p.deps, key)
					count++
				}
			}
			delete(p.tasks, t.name)
			fmt.Fprintf(p.out, "task %s removed with %d dependencies\n", t.name, count)
		case "NOTBEFORE":
			t.notBefore = number(w[2])
			fmt.Fprintf(p.out, "notbefore %s %s\n", t.name, w[2])
		case "CRASHCOST":
			limit := number(w[2])
			if limit >= t.base {
				return fmt.Errorf("crash limit too large for %s", t.name)
			}
			if limit < t.crashed {
				return fmt.Errorf("crash limit below used days for %s", t.name)
			}
			t.crash, t.crashLimit, t.cost = true, limit, number(w[3])
			fmt.Fprintf(p.out, "crash %s max %d cost %d\n", t.name, limit, t.cost)
		case "UNCRASH":
			fmt.Fprintf(p.out, "uncrash %s restored %d days\n", t.name, t.crashed)
			t.crashed = 0
		case "PERT":
			o, m, pessimistic := number(w[2]), number(w[3]), number(w[4])
			if o > m || m > pessimistic {
				return fmt.Errorf("invalid estimate")
			}
			t.estimate = []int{o, m, pessimistic}
			fmt.Fprintf(p.out, "pert %s expected %s variance %s\n", t.name, decimal(o+4*m+pessimistic, 6), decimal((pessimistic-o)*(pessimistic-o), 36))
		case "IMPACT":
			reached, queue := map[string]bool{t.name: true}, []string{t.name}
			for at := 0; at < len(queue); at++ {
				for _, dep := range p.successors(queue[at]) {
					if !reached[dep.to] {
						reached[dep.to] = true
						queue = append(queue, dep.to)
					}
				}
			}
			delete(reached, t.name)
			names := keys(reached)
			if len(names) == 0 {
				names = append(names, "none")
			}
			fmt.Fprintf(p.out, "impact %s: %s\n", t.name, strings.Join(names, " "))
		case "SHOW":
			fmt.Fprintf(p.out, "task %s duration %d resource %s units %d", t.name, p.duration(t.name, nil), t.resource, t.units)
			if t.notBefore != 0 {
				fmt.Fprintf(p.out, " notbefore %d", t.notBefore)
			}
			fmt.Fprintln(p.out)
			for _, relation := range []string{"preds", "succs"} {
				deps := p.predecessors(t.name)
				if relation == "succs" {
					deps = p.successors(t.name)
				}
				parts := []string{}
				for _, dep := range deps {
					name := dep.from
					if relation == "succs" {
						name = dep.to
					}
					parts = append(parts, fmt.Sprintf("%s %s%+d", name, dep.kind, dep.lag))
				}
				if len(parts) == 0 {
					parts = append(parts, "none")
				}
				fmt.Fprintf(p.out, "%s: %s\n", relation, strings.Join(parts, ", "))
			}
			if t.crash {
				fmt.Fprintf(p.out, "crash: max %d used %d cost %d\n", t.crashLimit, t.crashed, t.cost)
			} else {
				fmt.Fprintln(p.out, "crash: none")
			}
			if t.estimate != nil {
				fmt.Fprintf(p.out, "pert: %d %d %d\n", t.estimate[0], t.estimate[1], t.estimate[2])
			} else {
				fmt.Fprintln(p.out, "pert: none")
			}
			order, cycle := p.topology()
			if cycle != "" {
				fmt.Fprintln(p.out, "schedule: unavailable")
			} else {
				value := p.compute(order, nil).times[t.name]
				fmt.Fprintf(p.out, "schedule: ES %d EF %d LS %d LF %d TF %d FF %d", value.es, value.ef, value.ls, value.lf, value.tf, value.free)
				if value.tf == 0 {
					fmt.Fprint(p.out, " critical")
				}
				fmt.Fprintln(p.out)
			}
		}
		return nil
	case "CAPACITY":
		p.capacities[w[1]] = number(w[2])
		fmt.Fprintf(p.out, "capacity %s %s\n", w[1], w[2])
		return nil
	case "START", "HOLIDAY", "DEADLINE":
		date, valid := dateValue(w[1])
		if !valid {
			return fmt.Errorf("invalid date %s", w[1])
		}
		if cmd == "HOLIDAY" {
			if p.holidays[date] {
				return fmt.Errorf("duplicate holiday %s", w[1])
			}
			p.holidays[date] = true
		} else if cmd == "START" {
			p.start = &date
		} else {
			p.deadline = &date
		}
		fmt.Fprintf(p.out, "%s %s\n", strings.ToLower(cmd), dateText(date))
		return nil
	case "LIST":
		fmt.Fprintf(p.out, "tasks %d, dependencies %d, holidays %d\n", len(p.tasks), len(p.deps), len(p.holidays))
		for _, name := range keys(p.tasks) {
			t, previous := p.tasks[name], []string{}
			for _, dep := range p.predecessors(name) {
				previous = append(previous, dep.from)
			}
			if len(previous) == 0 {
				previous = append(previous, "none")
			}
			fmt.Fprintf(p.out, "%s duration %d resource %s units %d preds %s\n", name, p.duration(name, nil), t.resource, t.units, strings.Join(previous, " "))
		}
		return nil
	}
	if len(p.tasks) == 0 {
		return fmt.Errorf("no tasks")
	}
	order, cycle := p.topology()
	if cycle != "" {
		return fmt.Errorf("cycle %s", cycle)
	}
	if cmd == "CALENDAR" && p.start == nil {
		return fmt.Errorf("no start date")
	}
	if cmd == "WHATIF" {
		if _, err := p.get(w[1]); err != nil {
			return err
		}
	}
	if cmd == "VARIANCE" && p.baseline == nil {
		return fmt.Errorf("no baseline")
	}
	if cmd == "LOAD" {
		found := false
		for _, t := range p.tasks {
			if t.resource == w[1] {
				found = true
			}
		}
		if !found {
			return fmt.Errorf("unknown resource %s", w[1])
		}
	}
	s := p.compute(order, nil)
	switch cmd {
	case "CPM":
		width := 4
		for name := range p.tasks {
			width = max(width, len(name))
		}
		fmt.Fprintf(p.out, "%-*s", width, "TASK")
		for _, column := range []string{"DUR", "ES", "EF", "LS", "LF", "TF", "FF"} {
			fmt.Fprintf(p.out, "%5s", column)
		}
		fmt.Fprintln(p.out)
		for _, name := range keys(p.tasks) {
			v := s.times[name]
			fmt.Fprintf(p.out, "%-*s", width, name)
			for _, value := range []int{p.duration(name, nil), v.es, v.ef, v.ls, v.lf, v.tf, v.free} {
				fmt.Fprintf(p.out, "%5d", value)
			}
			if v.tf == 0 {
				fmt.Fprint(p.out, " *")
			}
			fmt.Fprintln(p.out)
		}
		fmt.Fprintf(p.out, "project duration %d\n", s.total)
	case "CRITICAL", "PERTSUM":
		paths := p.criticalPaths(s)
		if cmd == "CRITICAL" {
			fmt.Fprintf(p.out, "critical paths: %d\n", len(paths))
		}
		for _, path := range paths {
			text := strings.Join(path, " -> ")
			if cmd == "CRITICAL" {
				fmt.Fprintln(p.out, text)
			} else {
				expected, variance := 0, 0
				for _, name := range path {
					values := p.tasks[name].estimate
					if values == nil {
						d := p.duration(name, nil)
						values = []int{d, d, d}
					}
					expected += values[0] + 4*values[1] + values[2]
					variance += (values[2] - values[0]) * (values[2] - values[0])
				}
				fmt.Fprintf(p.out, "%s: expected %s variance %s\n", text, decimal(expected, 6), decimal(variance, 36))
			}
		}
	case "SLACK":
		groups := map[int][]string{}
		floats := []int{}
		for _, name := range keys(p.tasks) {
			value := s.times[name].tf
			if _, exists := groups[value]; !exists {
				floats = append(floats, value)
			}
			groups[value] = append(groups[value], name)
		}
		sort.Ints(floats)
		for _, value := range floats {
			fmt.Fprintf(p.out, "float %d: %s\n", value, strings.Join(groups[value], " "))
		}
	case "DRAG":
		for _, name := range p.critical(s) {
			after := p.compute(order, map[string]int{name: 0})
			fmt.Fprintf(p.out, "%s drag %d\n", name, s.total-after.total)
		}
	case "STATS":
		counts := map[string]int{}
		for _, dep := range p.deps {
			counts[dep.kind]++
		}
		critical := len(p.critical(s))
		fmt.Fprintf(p.out, "tasks %d, critical %d, dependencies %d (FS %d, SS %d, FF %d)\n", len(p.tasks), critical, len(p.deps), counts["FS"], counts["SS"], counts["FF"])
		work := []string{}
		for _, resource := range p.resources() {
			total := 0
			for name, t := range p.tasks {
				if t.resource == resource {
					total += p.duration(name, nil) * t.units
				}
			}
			work = append(work, fmt.Sprintf("%s %d", resource, total))
		}
		fmt.Fprintln(p.out, "work "+strings.Join(work, ", "))
		total := 0
		for _, value := range s.times {
			total += value.tf
		}
		fmt.Fprintf(p.out, "float total %d, average %s\nduration %d, critical share %s%%\n", total, decimal(total, len(p.tasks)), s.total, decimal(100*critical, len(p.tasks)))
	case "CALENDAR":
		p.calendar(s)
	case "GANTT":
		if s.total > 60 {
			return fmt.Errorf("chart too wide (%d days)", s.total)
		}
		width, names := 0, keys(p.tasks)
		for _, name := range names {
			width = max(width, len(name))
		}
		sort.Slice(names, func(i, j int) bool {
			a, b := s.times[names[i]].es, s.times[names[j]].es
			if a != b {
				return a < b
			}
			return names[i] < names[j]
		})
		fmt.Fprint(p.out, strings.Repeat(" ", width)+" |")
		for day := 0; day < s.total; day++ {
			fmt.Fprint(p.out, day%10)
		}
		fmt.Fprintln(p.out, "|")
		for _, name := range names {
			v := s.times[name]
			bar := []byte(strings.Repeat(" ", s.total))
			for day := 0; day < s.total; day++ {
				if v.es <= day && day < v.ef {
					bar[day] = '-'
					if v.tf == 0 {
						bar[day] = '='
					}
				} else if v.ef <= day && day < v.lf {
					bar[day] = '.'
				}
			}
			fmt.Fprintf(p.out, "%-*s |%s|\n", width, name, string(bar))
		}
	case "LEVEL":
		return p.level(order, s, number(w[1]))
	case "LOAD":
		values := p.usage(s, w[1])
		highest, first := peak(values), 0
		fmt.Fprintf(p.out, "load %s:", w[1])
		for _, value := range values {
			fmt.Fprintf(p.out, " %d", value)
		}
		fmt.Fprintln(p.out)
		for values[first] != highest {
			first++
		}
		fmt.Fprintf(p.out, "peak %d on day %d\n", highest, first)
		if capacity, exists := p.capacities[w[1]]; exists {
			count := 0
			for _, value := range values {
				if value > capacity {
					count++
				}
			}
			fmt.Fprintf(p.out, "capacity %d exceeded on %d days\n", capacity, count)
		}
	case "CRASH":
		initial, remaining, steps, spent := s.total, number(w[1]), 0, 0
		reason := ""
		for {
			s = p.compute(order, nil)
			chosen := ""
			for _, name := range p.critical(s) {
				t := p.tasks[name]
				if t.crash && t.crashed < t.crashLimit && p.compute(order, map[string]int{name: p.duration(name, nil) - 1}).total < s.total {
					if chosen == "" || t.cost < p.tasks[chosen].cost {
						chosen = name
					}
				}
			}
			if chosen == "" {
				reason = "no candidate"
				break
			}
			t := p.tasks[chosen]
			if t.cost > remaining {
				reason = "insufficient budget"
				break
			}
			before := p.duration(chosen, nil)
			t.crashed++
			remaining -= t.cost
			spent += t.cost
			steps++
			after := p.compute(order, nil)
			fmt.Fprintf(p.out, "step %d: %s %d -> %d, cost %d, project %d\n", steps, chosen, before, before-1, t.cost, after.total)
		}
		fmt.Fprintf(p.out, "crash done: %d days, cost %d, project %d -> %d, budget left %d, %s\n", steps, spent, initial, s.total, remaining, reason)
	case "WHATIF":
		after := p.compute(order, map[string]int{w[1]: number(w[2])})
		fmt.Fprintf(p.out, "whatif %s %d -> %s: project %d -> %d\n", w[1], p.duration(w[1], nil), w[2], s.total, after.total)
		for _, name := range keys(p.tasks) {
			a, b := s.times[name], after.times[name]
			changes := []string{}
			if a.es != b.es {
				changes = append(changes, fmt.Sprintf("ES %d->%d", a.es, b.es))
			}
			if a.ef != b.ef {
				changes = append(changes, fmt.Sprintf("EF %d->%d", a.ef, b.ef))
			}
			if a.tf != b.tf {
				changes = append(changes, fmt.Sprintf("TF %d->%d", a.tf, b.tf))
			}
			if len(changes) > 0 {
				fmt.Fprintf(p.out, "%s %s\n", name, strings.Join(changes, " "))
			}
		}
		beforeNames, afterNames := strings.Join(p.critical(s), " "), strings.Join(p.critical(after), " ")
		if beforeNames != afterNames {
			fmt.Fprintf(p.out, "critical %s -> %s\n", beforeNames, afterNames)
		}
	case "BASELINE":
		saved := &baseline{times: map[string][2]int{}, total: s.total}
		for name, value := range s.times {
			saved.times[name] = [2]int{value.es, value.ef}
		}
		p.baseline = saved
		fmt.Fprintf(p.out, "baseline saved: %d tasks, duration %d\n", len(p.tasks), s.total)
	case "VARIANCE":
		old := p.baseline
		fmt.Fprintf(p.out, "variance: duration %d -> %d (%+d)\n", old.total, s.total, s.total-old.total)
		names := map[string]bool{}
		for name := range old.times {
			names[name] = true
		}
		for name := range p.tasks {
			names[name] = true
		}
		count := 0
		for _, name := range keys(names) {
			before, existed := old.times[name]
			after, exists := s.times[name]
			if !exists {
				fmt.Fprintln(p.out, name+" removed")
				count++
			} else if !existed {
				fmt.Fprintln(p.out, name+" new")
				count++
			} else if before[0] != after.es || before[1] != after.ef {
				fmt.Fprintf(p.out, "%s start %+d finish %+d\n", name, after.es-before[0], after.ef-before[1])
				count++
			}
		}
		if count == 0 {
			fmt.Fprintln(p.out, "no task changes")
		}
	}
	return nil
}

func main() {
	input, _ := io.ReadAll(os.Stdin)
	lines := strings.Split(string(input), "\n")
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	p := &project{tasks: map[string]*task{}, deps: map[string]dependency{}, capacities: map[string]int{}, holidays: map[int]bool{}, out: out}
	for _, text := range lines[1 : number(lines[0])+1] {
		if err := p.command(strings.Split(text, " ")); err != nil {
			fmt.Fprintln(out, "error: "+err.Error())
		}
	}
}
