package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

const scale int64 = 1 << 37

var terms = map[string][3]string{
	"parent":          {"father", "mother", "parent"},
	"child":           {"son", "daughter", "child"},
	"sibling":         {"brother", "sister", "sibling"},
	"pibling":         {"uncle", "aunt", "pibling"},
	"nibling":         {"nephew", "niece", "nibling"},
	"spouse":          {"husband", "wife", "spouse"},
	"late":            {"late husband", "late wife", "late spouse"},
	"survivor":        {"widower", "widow", "surviving spouse"},
	"ex":              {"ex-husband", "ex-wife", "ex-spouse"},
	"stepparent":      {"stepfather", "stepmother", "stepparent"},
	"stepchild":       {"stepson", "stepdaughter", "stepchild"},
	"stepsibling":     {"stepbrother", "stepsister", "stepsibling"},
	"stepgrandparent": {"stepgrandfather", "stepgrandmother", "stepgrandparent"},
	"stepgrandchild":  {"stepgrandson", "stepgranddaughter", "stepgrandchild"},
	"parent-in-law":   {"father-in-law", "mother-in-law", "parent-in-law"},
	"child-in-law":    {"son-in-law", "daughter-in-law", "child-in-law"},
	"sibling-in-law":  {"brother-in-law", "sister-in-law", "sibling-in-law"},
}

func sexIndex(sex string) int {
	if sex == "M" {
		return 0
	}
	if sex == "F" {
		return 1
	}
	return 2
}

func gendered(kind, sex string) string {
	return terms[kind][sexIndex(sex)]
}

func generationPrefix(g int) string {
	if g == 1 {
		return ""
	}
	return strings.Repeat("great-", g-2) + "grand"
}

func ordinal(k int) string {
	words := []string{"first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"}
	if k <= 10 {
		return words[k-1]
	}
	suffix := "th"
	if k%100 < 11 || k%100 > 13 {
		switch k % 10 {
		case 1:
			suffix = "st"
		case 2:
			suffix = "nd"
		case 3:
			suffix = "rd"
		}
	}
	return strconv.Itoa(k) + suffix
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

func number(text string) int {
	n, _ := strconv.Atoi(text)
	return n
}

func kinshipTerm(da, db int, sex string) string {
	switch {
	case da == 0 && db == 0:
		return "self"
	case da == 0:
		return generationPrefix(db) + gendered("parent", sex)
	case db == 0:
		return generationPrefix(da) + gendered("child", sex)
	case da == 1 && db == 1:
		return gendered("sibling", sex)
	case da == 1:
		return generationPrefix(db-1) + gendered("pibling", sex)
	case db == 1:
		return generationPrefix(da-1) + gendered("nibling", sex)
	}
	removal := ""
	switch r := abs(da - db); r {
	case 0:
	case 1:
		removal = " once removed"
	case 2:
		removal = " twice removed"
	default:
		removal = fmt.Sprintf(" %d times removed", r)
	}
	return ordinal(min(da, db)-1) + " cousin" + removal
}

func fraction(value int64) string {
	a, b := value, scale
	for b != 0 {
		a, b = b, a%b
	}
	return fmt.Sprintf("%d/%d", value/a, scale/a)
}

func has(ids []string, x string) bool {
	for _, y := range ids {
		if y == x {
			return true
		}
	}
	return false
}

func without(ids []string, x string) []string {
	result := make([]string, 0, len(ids))
	for _, y := range ids {
		if y != x {
			result = append(result, y)
		}
	}
	return result
}

type Person struct {
	Sex     string
	Birth   int
	Name    string
	Death   int
	Parents []string
}

func (p *Person) life() string {
	end := ""
	if p.Death != 0 {
		end = strconv.Itoa(p.Death)
	}
	return fmt.Sprintf("%d-%s", p.Birth, end)
}

type Marriage struct {
	First, Second string
	Start, End    int
	Status, Died  string
}

func (m *Marriage) contains(x string) bool {
	return m.First == x || m.Second == x
}

func (m *Marriage) other(x string) string {
	if m.First == x {
		return m.Second
	}
	return m.First
}

type Apex struct {
	Person         string
	DA, DB, Shares int
}

func (a *Apex) bloodTerm(sex string) string {
	prefix := ""
	if a.Shares == 1 {
		prefix = "half-"
	} else if a.Shares >= 4 {
		prefix = "double "
	}
	return prefix + kinshipTerm(a.DA, a.DB, sex)
}

type Family struct {
	Persons      map[string]*Person
	Marriages    []*Marriage
	Distances    map[string]map[string]int
	Coefficients map[[2]string]int64
}

func newFamily() *Family {
	return &Family{Persons: make(map[string]*Person), Distances: make(map[string]map[string]int), Coefficients: make(map[[2]string]int64)}
}

func (f *Family) copy() *Family {
	result := newFamily()
	for id, p := range f.Persons {
		copied := *p
		copied.Parents = append([]string(nil), p.Parents...)
		result.Persons[id] = &copied
	}
	for _, m := range f.Marriages {
		copied := *m
		result.Marriages = append(result.Marriages, &copied)
	}
	return result
}

func (f *Family) ids() []string {
	ids := make([]string, 0, len(f.Persons))
	for id := range f.Persons {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}

func (f *Family) ageLess(a, b string) bool {
	return f.Persons[a].Birth < f.Persons[b].Birth || (f.Persons[a].Birth == f.Persons[b].Birth && a < b)
}

func (f *Family) ageOrder(ids []string) []string {
	ordered := append([]string(nil), ids...)
	sort.Slice(ordered, func(i, j int) bool {
		return f.ageLess(ordered[i], ordered[j])
	})
	return ordered
}

func (f *Family) personList(ids []string) string {
	if len(ids) == 0 {
		return "-"
	}
	return strings.Join(f.ageOrder(ids), " ")
}

func (f *Family) children(x string) []string {
	var ids []string
	for id, p := range f.Persons {
		if has(p.Parents, x) {
			ids = append(ids, id)
		}
	}
	return ids
}

func (f *Family) commonParents(a, b string) int {
	count := 0
	for _, p := range f.Persons[a].Parents {
		if has(f.Persons[b].Parents, p) {
			count++
		}
	}
	return count
}

func (f *Family) areSiblings(a, b string) bool {
	return a != b && f.commonParents(a, b) > 0
}

func (f *Family) siblings(x string) []string {
	var result []string
	for y := range f.Persons {
		if f.areSiblings(x, y) {
			result = append(result, y)
		}
	}
	return result
}

func (f *Family) records(x string) []*Marriage {
	var result []*Marriage
	for _, m := range f.Marriages {
		if m.contains(x) {
			result = append(result, m)
		}
	}
	return result
}

func (f *Family) current(x string) *Marriage {
	for _, m := range f.Marriages {
		if m.Status == "current" && m.contains(x) {
			return m
		}
	}
	return nil
}

func (f *Family) spouse(x string) string {
	if m := f.current(x); m != nil {
		return m.other(x)
	}
	return ""
}

func (f *Family) last(a, b string) *Marriage {
	for i := len(f.Marriages) - 1; i >= 0; i-- {
		m := f.Marriages[i]
		if m.contains(a) && m.contains(b) {
			return m
		}
	}
	return nil
}

func (f *Family) partners(x string) map[string]bool {
	latest := make(map[string]*Marriage)
	for _, m := range f.records(x) {
		latest[m.other(x)] = m
	}
	result := make(map[string]bool)
	for y, m := range latest {
		if m.Status != "divorced" {
			result[y] = true
		}
	}
	return result
}

func (f *Family) stepRelated(a, b string) bool {
	for _, p := range f.Persons[a].Parents {
		partners := f.partners(p)
		for _, q := range f.Persons[b].Parents {
			if partners[q] {
				return true
			}
		}
	}
	return false
}

func (f *Family) distances(start string, upward bool) map[string]int {
	key := fmt.Sprintf("%t:%s", upward, start)
	if cached, ok := f.Distances[key]; ok {
		return cached
	}
	distances := map[string]int{start: 0}
	queue := []string{start}
	for i := 0; i < len(queue); i++ {
		x := queue[i]
		var neighbors []string
		if upward {
			neighbors = f.Persons[x].Parents
		} else {
			neighbors = f.children(x)
		}
		for _, y := range neighbors {
			if _, seen := distances[y]; !seen {
				distances[y] = distances[x] + 1
				queue = append(queue, y)
			}
		}
	}
	f.Distances[key] = distances
	return distances
}

func (f *Family) ancestor(a, b string) bool {
	_, ok := f.distances(b, true)[a]
	return a != b && ok
}

func (f *Family) grandparents(x string) []string {
	var ids []string
	for y, g := range f.distances(x, true) {
		if g == 2 {
			ids = append(ids, y)
		}
	}
	return ids
}

func (f *Family) apex(a, b string) *Apex {
	upA, upB := f.distances(a, true), f.distances(b, true)
	if g, ok := upB[a]; ok {
		return &Apex{Person: a, DB: g}
	}
	if g, ok := upA[b]; ok {
		return &Apex{Person: b, DA: g}
	}
	var best *Apex
	for c, da := range upA {
		db, ok := upB[c]
		if !ok {
			continue
		}
		if best == nil || da+db < best.DA+best.DB ||
			(da+db == best.DA+best.DB && (da < best.DA || (da == best.DA && c < best.Person))) {
			best = &Apex{Person: c, DA: da, DB: db}
		}
	}
	if best != nil {
		for c, da := range upA {
			if db, ok := upB[c]; ok && da == best.DA && db == best.DB {
				best.Shares++
			}
		}
	}
	return best
}

func (f *Family) relationship(a, b, sex string) []string {
	if a == b {
		return []string{"self"}
	}
	var result []string
	if apex := f.apex(a, b); apex != nil {
		result = append(result, apex.bloodTerm(sex))
	}
	m := f.last(a, b)
	if m == nil {
		for _, p := range f.Persons {
			if has(p.Parents, a) && has(p.Parents, b) {
				result = append(result, "co-parent")
				break
			}
		}
	} else {
		kind := "ex"
		if m.Status == "current" {
			kind = "spouse"
		} else if m.Status == "widowed" {
			kind = "survivor"
			if m.Died == a {
				kind = "late"
			}
		}
		result = append(result, gendered(kind, sex))
	}
	pa, pb := f.Persons[a].Parents, f.Persons[b].Parents
	qa, qb := f.partners(a), f.partners(b)
	if !has(pb, a) {
		for _, p := range pb {
			if qa[p] {
				result = append(result, gendered("stepparent", sex))
				break
			}
		}
	}
	if !has(pa, b) {
		for _, p := range pa {
			if qb[p] {
				result = append(result, gendered("stepchild", sex))
				break
			}
		}
	}
	if f.commonParents(a, b) == 0 && f.stepRelated(a, b) {
		result = append(result, gendered("stepsibling", sex))
	}
	if !f.ancestor(a, b) {
		for _, g := range f.grandparents(b) {
			if qa[g] {
				result = append(result, gendered("stepgrandparent", sex))
				break
			}
		}
	}
	if !f.ancestor(b, a) {
		for _, g := range f.grandparents(a) {
			if qb[g] {
				result = append(result, gendered("stepgrandchild", sex))
				break
			}
		}
	}
	for q := range qb {
		if has(f.Persons[q].Parents, a) {
			result = append(result, gendered("parent-in-law", sex))
			break
		}
	}
	for q := range qa {
		if has(f.Persons[q].Parents, b) {
			result = append(result, gendered("child-in-law", sex))
			break
		}
	}
	siblingInLaw := false
	for q := range qb {
		if f.areSiblings(a, q) {
			siblingInLaw = true
		}
	}
	for q := range qa {
		if f.areSiblings(q, b) {
			siblingInLaw = true
		}
	}
	if siblingInLaw {
		result = append(result, gendered("sibling-in-law", sex))
	}
	return result
}

func (f *Family) relationshipText(a, b string) string {
	result := f.relationship(a, b, f.Persons[a].Sex)
	if len(result) == 0 {
		return "no relation"
	}
	return strings.Join(result, ", ")
}

func (f *Family) coefficient(a, b string) int64 {
	key := [2]string{a, b}
	if a > b {
		key = [2]string{b, a}
	}
	if value, ok := f.Coefficients[key]; ok {
		return value
	}
	var value int64
	if a == b {
		value = (scale + f.inbreeding(a)) / 2
	} else {
		x, y := a, b
		if f.Persons[b].Birth > f.Persons[a].Birth {
			x, y = b, a
		}
		for _, p := range f.Persons[x].Parents {
			value += f.coefficient(p, y)
		}
		value /= 2
	}
	f.Coefficients[key] = value
	return value
}

func (f *Family) inbreeding(x string) int64 {
	parents := f.Persons[x].Parents
	if len(parents) != 2 {
		return 0
	}
	return f.coefficient(parents[0], parents[1])
}

func (f *Family) lineageLength(x string, memo map[string]int) int {
	if length, ok := memo[x]; ok {
		return length
	}
	length := 1
	for _, p := range f.Persons[x].Parents {
		length = max(length, 1+f.lineageLength(p, memo))
	}
	memo[x] = length
	return length
}

func (f *Family) modify(command string, args []string) (string, error) {
	x := args[0]
	if command == "PERSON" {
		if f.Persons[x] != nil {
			return "", fmt.Errorf("DUPLICATE PERSON %s", x)
		}
		f.Persons[x] = &Person{Sex: args[1], Birth: number(args[2]), Name: args[3]}
		return fmt.Sprintf("ADDED %s %s %s %s", x, args[3], args[1], args[2]), nil
	}
	if f.Persons[x] == nil {
		return "", fmt.Errorf("UNKNOWN PERSON %s", x)
	}
	if command == "PARENT" || command == "UNPARENT" || command == "SPOUSE" || command == "DIVORCE" {
		if f.Persons[args[1]] == nil {
			return "", fmt.Errorf("UNKNOWN PERSON %s", args[1])
		}
	}
	p := f.Persons[x]
	switch command {
	case "DEATH":
		year := number(args[1])
		if p.Death != 0 {
			return "", fmt.Errorf("ALREADY DECEASED %s", x)
		}
		bad := year < p.Birth
		for _, m := range f.records(x) {
			if year < m.Start || (m.End != 0 && year < m.End) {
				bad = true
			}
		}
		if bad {
			return "", fmt.Errorf("BAD YEAR %s", x)
		}
		children := f.children(x)
		sort.Strings(children)
		for _, c := range children {
			if f.Persons[c].Birth > year+1 {
				return "", fmt.Errorf("AFTER DEATH %s %s", c, x)
			}
		}
		p.Death = year
		m := f.current(x)
		if m == nil {
			return fmt.Sprintf("DIED %s %d", x, year), nil
		}
		m.End, m.Status, m.Died = year, "widowed", x
		return fmt.Sprintf("DIED %s %d spouse=%s", x, year, m.other(x)), nil
	case "REMOVE":
		for _, person := range f.Persons {
			person.Parents = without(person.Parents, x)
		}
		var records []*Marriage
		for _, m := range f.Marriages {
			if !m.contains(x) {
				records = append(records, m)
			}
		}
		f.Marriages = records
		delete(f.Persons, x)
		return "REMOVED " + x, nil
	case "PARENT":
		y := args[1]
		parent := f.Persons[y]
		if x == y {
			return "", fmt.Errorf("SAME PERSON %s", x)
		}
		if has(p.Parents, y) {
			return "", fmt.Errorf("ALREADY PARENT %s %s", x, y)
		}
		if len(p.Parents) == 2 {
			return "", fmt.Errorf("TOO MANY PARENTS %s", x)
		}
		if f.ancestor(x, y) {
			return "", fmt.Errorf("CYCLE %s %s", x, y)
		}
		if parent.Birth+12 > p.Birth {
			return "", fmt.Errorf("AGE GAP %s %s", x, y)
		}
		if parent.Death != 0 && parent.Death+1 < p.Birth {
			return "", fmt.Errorf("AFTER DEATH %s %s", x, y)
		}
		p.Parents = append(p.Parents, y)
		return fmt.Sprintf("LINKED %s %s %s", x, y, gendered("parent", parent.Sex)), nil
	case "UNPARENT":
		y := args[1]
		if !has(p.Parents, y) {
			return "", fmt.Errorf("NOT PARENT %s %s", x, y)
		}
		p.Parents = without(p.Parents, y)
		return fmt.Sprintf("UNLINKED %s %s", x, y), nil
	case "SPOUSE":
		y, year := args[1], number(args[2])
		if x == y {
			return "", fmt.Errorf("SAME PERSON %s", x)
		}
		for _, a := range []string{x, y} {
			if f.Persons[a].Death != 0 {
				return "", fmt.Errorf("DECEASED %s", a)
			}
		}
		for _, a := range []string{x, y} {
			if f.spouse(a) != "" {
				return "", fmt.Errorf("ALREADY MARRIED %s", a)
			}
		}
		if f.ancestor(x, y) || f.ancestor(y, x) || f.areSiblings(x, y) {
			return "", fmt.Errorf("CLOSE KIN %s %s", x, y)
		}
		for _, a := range []string{x, y} {
			if year < f.Persons[a].Birth+16 {
				return "", fmt.Errorf("TOO YOUNG %s", a)
			}
		}
		for _, a := range []string{x, y} {
			for _, m := range f.records(a) {
				if m.End != 0 && m.End >= year {
					return "", fmt.Errorf("BAD YEAR %s", a)
				}
			}
		}
		f.Marriages = append(f.Marriages, &Marriage{First: x, Second: y, Start: year, Status: "current"})
		return fmt.Sprintf("MARRIED %s %s %d", x, y, year), nil
	case "DIVORCE":
		y, year := args[1], number(args[2])
		if f.spouse(x) != y {
			return "", fmt.Errorf("NOT MARRIED %s %s", x, y)
		}
		m := f.current(x)
		if year <= m.Start {
			return "", fmt.Errorf("BAD YEAR %s", x)
		}
		m.End, m.Status = year, "divorced"
		return fmt.Sprintf("DIVORCED %s %s %d", x, y, year), nil
	}
	panic("unknown modifying command")
}

type LineageEntry struct {
	ID       string
	Distance int
}

func (f *Family) lineage(x string, upward bool) []LineageEntry {
	var result []LineageEntry
	for y, g := range f.distances(x, upward) {
		if y != x {
			result = append(result, LineageEntry{y, g})
		}
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i].Distance < result[j].Distance || (result[i].Distance == result[j].Distance && result[i].ID < result[j].ID)
	})
	return result
}

func (f *Family) query(command string, args []string) ([]string, error) {
	switch command {
	case "TERM":
		return []string{fmt.Sprintf("TERM %s %s %s %s", args[0], args[1], args[2], kinshipTerm(number(args[0]), number(args[1]), args[2]))}, nil
	case "STATS":
		living, links, couples, founders, longest := 0, 0, 0, 0, 0
		memo := make(map[string]int)
		for x, p := range f.Persons {
			if p.Death == 0 {
				living++
			}
			links += len(p.Parents)
			if len(p.Parents) == 0 {
				founders++
			}
			longest = max(longest, f.lineageLength(x, memo))
		}
		for _, m := range f.Marriages {
			if m.Status == "current" {
				couples++
			}
		}
		return []string{fmt.Sprintf("STATS persons=%d living=%d links=%d couples=%d founders=%d generations=%d", len(f.Persons), living, links, couples, founders, longest)}, nil
	case "AUDIT":
		var lines []string
		for _, m := range f.Marriages {
			if apex := f.apex(m.First, m.Second); apex != nil {
				lines = append(lines, fmt.Sprintf("  marriage %s %s %s", m.First, m.Second, apex.bloodTerm(f.Persons[m.First].Sex)))
			}
		}
		for _, x := range f.ids() {
			if value := f.inbreeding(x); value != 0 {
				lines = append(lines, fmt.Sprintf("  inbred %s %s", x, fraction(value)))
			}
		}
		return append([]string{fmt.Sprintf("AUDIT %d", len(lines))}, lines...), nil
	case "CENSUS":
		year := number(args[0])
		var residents []string
		for x, p := range f.Persons {
			if p.Birth <= year && (p.Death == 0 || p.Death > year) {
				residents = append(residents, x)
			}
		}
		lines := []string{fmt.Sprintf("CENSUS %d %d", year, len(residents))}
		for _, x := range f.ageOrder(residents) {
			var last *Marriage
			for _, m := range f.records(x) {
				if m.Start <= year {
					last = m
				}
			}
			status := "single"
			if last != nil {
				if last.End == 0 || last.End > year {
					status = "married " + last.other(x)
				} else {
					status = last.Status
				}
			}
			lines = append(lines, fmt.Sprintf("  %s %d %s", x, year-f.Persons[x].Birth, status))
		}
		return lines, nil
	}
	x := args[0]
	if f.Persons[x] == nil {
		return nil, fmt.Errorf("UNKNOWN PERSON %s", x)
	}
	if command == "RELATION" || command == "PATH" || command == "COMMON" || command == "KINSHIP" {
		if f.Persons[args[1]] == nil {
			return nil, fmt.Errorf("UNKNOWN PERSON %s", args[1])
		}
	}
	p := f.Persons[x]
	switch command {
	case "INFO":
		lines := []string{fmt.Sprintf("INFO %s %s %s %s", x, p.Name, p.Sex, p.life()), "  parents: " + f.personList(p.Parents)}
		for _, m := range f.records(x) {
			end := ""
			if m.End != 0 {
				end = strconv.Itoa(m.End)
			}
			lines = append(lines, fmt.Sprintf("  marriage: %s %d-%s %s", m.other(x), m.Start, end, m.Status))
		}
		lines = append(lines, "  children: "+f.personList(f.children(x)), "  siblings: "+f.personList(f.siblings(x)), "  inbreeding: "+fraction(f.inbreeding(x)))
		return lines, nil
	case "RELATION":
		return []string{fmt.Sprintf("RELATION %s %s: %s", x, args[1], f.relationshipText(x, args[1]))}, nil
	case "KINSHIP":
		return []string{fmt.Sprintf("KINSHIP %s %s %s", x, args[1], fraction(f.coefficient(x, args[1])))}, nil
	case "RELATIVES", "WHO":
		var lines []string
		query := strings.Join(args[1:], " ")
		for _, y := range f.ids() {
			if y == x {
				continue
			}
			actual := f.relationship(y, x, f.Persons[y].Sex)
			if command == "RELATIVES" {
				if len(actual) > 0 {
					lines = append(lines, fmt.Sprintf("  %s: %s", y, strings.Join(actual, ", ")))
				}
			} else {
				neutral := f.relationship(y, x, "X")
				for i, t := range actual {
					if t == query || neutral[i] == query {
						lines = append(lines, fmt.Sprintf("  %s: %s", y, t))
						break
					}
				}
			}
		}
		header := fmt.Sprintf("RELATIVES %s %d", x, len(lines))
		if command == "WHO" {
			header = fmt.Sprintf("WHO %s %s %d", x, query, len(lines))
		}
		return append([]string{header}, lines...), nil
	case "PATH":
		y := args[1]
		apex := f.apex(x, y)
		if apex == nil {
			return []string{fmt.Sprintf("PATH %s %s none", x, y)}, nil
		}
		depths := f.distances(apex.Person, false)
		upward := func(start string) []string {
			path := []string{start}
			for current := start; current != apex.Person; {
				var choices []string
				for _, parent := range f.Persons[current].Parents {
					if d, ok := depths[parent]; ok && d == depths[current]-1 {
						choices = append(choices, parent)
					}
				}
				sort.Strings(choices)
				current = choices[0]
				path = append(path, current)
			}
			return path
		}
		route, descent := upward(x), upward(y)
		for i := len(descent) - 2; i >= 0; i-- {
			route = append(route, descent[i])
		}
		return []string{fmt.Sprintf("PATH %s %s %d: %s", x, y, apex.DA+apex.DB, strings.Join(route, " "))}, nil
	case "COMMON":
		y := args[1]
		a, b := f.distances(x, true), f.distances(y, true)
		shared := make(map[string]bool)
		for c := range a {
			if _, ok := b[c]; ok {
				shared[c] = true
			}
		}
		var nearest []string
		for c := range shared {
			ok := true
			for _, child := range f.children(c) {
				if shared[child] {
					ok = false
					break
				}
			}
			if ok {
				nearest = append(nearest, c)
			}
		}
		sort.Slice(nearest, func(i, j int) bool {
			c, d := nearest[i], nearest[j]
			return a[c]+b[c] < a[d]+b[d] || (a[c]+b[c] == a[d]+b[d] && c < d)
		})
		lines := []string{fmt.Sprintf("COMMON %s %s %d", x, y, len(nearest))}
		for _, c := range nearest {
			lines = append(lines, fmt.Sprintf("  %s %d %d", c, a[c], b[c]))
		}
		return lines, nil
	case "ANCESTORS", "DESCENDANTS":
		upward := command == "ANCESTORS"
		entries := f.lineage(x, upward)
		lines := []string{fmt.Sprintf("%s %s %d", command, x, len(entries))}
		for _, e := range entries {
			da, db := e.Distance, 0
			if upward {
				da, db = 0, e.Distance
			}
			lines = append(lines, fmt.Sprintf("  %d %s %s", e.Distance, e.ID, kinshipTerm(da, db, f.Persons[e.ID].Sex)))
		}
		return lines, nil
	case "COUSINS":
		type Match struct {
			ID   string
			Apex *Apex
		}
		var matches []Match
		for y := range f.Persons {
			if x == y {
				continue
			}
			apex := f.apex(y, x)
			if apex != nil && apex.DA >= 2 && apex.DB >= 2 && min(apex.DA, apex.DB)-1 == number(args[1]) {
				matches = append(matches, Match{y, apex})
			}
		}
		sort.Slice(matches, func(i, j int) bool {
			a, b := matches[i], matches[j]
			da, db := abs(a.Apex.DA-a.Apex.DB), abs(b.Apex.DA-b.Apex.DB)
			return da < db || (da == db && a.ID < b.ID)
		})
		lines := []string{fmt.Sprintf("COUSINS %s %s %d", x, args[1], len(matches))}
		for _, m := range matches {
			lines = append(lines, fmt.Sprintf("  %s %s", m.ID, m.Apex.bloodTerm(f.Persons[m.ID].Sex)))
		}
		return lines, nil
	case "SIBLINGS":
		var lines []string
		earlier := 0
		for _, y := range f.ageOrder(f.ids()) {
			if y == x {
				continue
			}
			common := f.commonParents(x, y)
			kind := ""
			if common == 2 {
				kind = "full"
			} else if common == 1 {
				kind = "half"
			} else if f.stepRelated(x, y) {
				kind = "step"
			}
			if kind == "" {
				continue
			}
			if common > 0 && f.ageLess(y, x) {
				earlier++
			}
			lines = append(lines, fmt.Sprintf("  %s %s %d", y, kind, f.Persons[y].Birth))
		}
		return append([]string{fmt.Sprintf("SIBLINGS %s %d order=%d", x, len(lines), earlier+1)}, lines...), nil
	case "GENERATIONS":
		groups := make(map[int][]string)
		for _, e := range f.lineage(x, false) {
			groups[e.Distance] = append(groups[e.Distance], e.ID)
		}
		var generations []int
		for g := range groups {
			generations = append(generations, g)
		}
		sort.Ints(generations)
		lines := []string{fmt.Sprintf("GENERATIONS %s %d", x, len(groups))}
		for _, g := range generations {
			members := groups[g]
			lo, hi, living := 2025, 1800, 0
			for _, y := range members {
				p := f.Persons[y]
				lo, hi = min(lo, p.Birth), max(hi, p.Birth)
				if p.Death == 0 {
					living++
				}
			}
			lines = append(lines, fmt.Sprintf("  %d %d %d %d-%d", g, len(members), living, lo, hi))
		}
		return lines, nil
	case "TREE":
		lines := []string{fmt.Sprintf("TREE %s %d", x, len(f.lineage(x, false)))}
		visited := make(map[string]bool)
		var visit func(string, int)
		visit = func(y string, depth int) {
			indent := strings.Repeat(" ", 2*(depth+1))
			if visited[y] {
				lines = append(lines, indent+y+" (see above)")
				return
			}
			visited[y] = true
			p := f.Persons[y]
			line := fmt.Sprintf("%s%s %s %s", indent, y, p.Name, p.life())
			if spouse := f.spouse(y); spouse != "" {
				line += " = " + spouse
			}
			lines = append(lines, line)
			for _, child := range f.ageOrder(f.children(y)) {
				visit(child, depth+1)
			}
		}
		visit(x, 0)
		return lines, nil
	case "PEDIGREE":
		var entries []string
		entered := make(map[string]bool)
		depth := number(args[1])
		var enter func(string, int, int)
		enter = func(y string, k, g int) {
			p := f.Persons[y]
			entries = append(entries, fmt.Sprintf("%s%d %s %s %s", strings.Repeat(" ", 2*(g+1)), k, y, p.Name, p.life()))
			entered[y] = true
			if g >= depth {
				return
			}
			parents := append([]string(nil), p.Parents...)
			sort.Slice(parents, func(i, j int) bool {
				a, b := parents[i], parents[j]
				sa, sb := sexIndex(f.Persons[a].Sex), sexIndex(f.Persons[b].Sex)
				return sa < sb || (sa == sb && a < b)
			})
			for i, parent := range parents {
				enter(parent, 2*k+i, g+1)
			}
		}
		enter(x, 1, 0)
		return append([]string{fmt.Sprintf("PEDIGREE %s %d entries=%d distinct=%d", x, depth, len(entries), len(entered))}, entries...), nil
	case "TIMELINE":
		type Event struct {
			Year, Rank  int
			Other, Text string
		}
		events := []Event{{p.Birth, 0, "", "born"}}
		for _, m := range f.records(x) {
			y := m.other(x)
			events = append(events, Event{m.Start, 1, y, "married " + y})
			if m.Status == "divorced" {
				events = append(events, Event{m.End, 3, y, "divorced " + y})
			} else if m.Status == "widowed" && m.Died == y {
				events = append(events, Event{m.End, 4, y, "widowed " + y})
			}
		}
		children := f.children(x)
		for _, y := range children {
			events = append(events, Event{f.Persons[y].Birth, 2, y, "child " + y})
		}
		for _, relatives := range []struct {
			Label string
			IDs   []string
		}{{"parent", p.Parents}, {"child", children}} {
			for _, y := range relatives.IDs {
				death := f.Persons[y].Death
				if death != 0 && death >= p.Birth && (p.Death == 0 || death <= p.Death) {
					events = append(events, Event{death, 5, y, "lost " + relatives.Label + " " + y})
				}
			}
		}
		if p.Death != 0 {
			events = append(events, Event{p.Death, 6, "", "died"})
		}
		sort.Slice(events, func(i, j int) bool {
			a, b := events[i], events[j]
			if a.Year != b.Year {
				return a.Year < b.Year
			}
			if a.Rank != b.Rank {
				return a.Rank < b.Rank
			}
			return a.Other < b.Other
		})
		lines := []string{fmt.Sprintf("TIMELINE %s %d", x, len(events))}
		for _, e := range events {
			lines = append(lines, fmt.Sprintf("  %d %s", e.Year, e.Text))
		}
		return lines, nil
	case "FIND":
		steps := map[string][2]string{
			"parent":   {"parent", ""},
			"father":   {"parent", "M"},
			"mother":   {"parent", "F"},
			"child":    {"child", ""},
			"son":      {"child", "M"},
			"daughter": {"child", "F"},
			"sibling":  {"sibling", ""},
			"brother":  {"sibling", "M"},
			"sister":   {"sibling", "F"},
			"spouse":   {"spouse", ""},
			"husband":  {"spouse", "M"},
			"wife":     {"spouse", "F"},
		}
		current := map[string]bool{x: true}
		for _, step := range strings.Split(args[1], ".") {
			kind, sex := steps[step][0], steps[step][1]
			next := make(map[string]bool)
			for y := range current {
				var targets []string
				switch kind {
				case "parent":
					targets = f.Persons[y].Parents
				case "child":
					targets = f.children(y)
				case "sibling":
					targets = f.siblings(y)
				case "spouse":
					if s := f.spouse(y); s != "" {
						targets = []string{s}
					}
				}
				for _, z := range targets {
					if sex == "" || f.Persons[z].Sex == sex {
						next[z] = true
					}
				}
			}
			current = next
		}
		delete(current, x)
		var ids []string
		for y := range current {
			ids = append(ids, y)
		}
		sort.Strings(ids)
		lines := []string{fmt.Sprintf("FIND %s %s %d", x, args[1], len(ids))}
		for _, y := range ids {
			lines = append(lines, fmt.Sprintf("  %s: %s", y, f.relationshipText(y, x)))
		}
		return lines, nil
	}
	panic("unknown query")
}

type Snapshot struct {
	Line   string
	Family *Family
}

func main() {
	in := bufio.NewScanner(os.Stdin)
	in.Scan()
	count := number(in.Text())
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	family := newFamily()
	var history []Snapshot
	modifying := map[string]bool{"PERSON": true, "DEATH": true, "REMOVE": true, "PARENT": true, "UNPARENT": true, "SPOUSE": true, "DIVORCE": true}
	for range count {
		in.Scan()
		line := in.Text()
		words := strings.Split(line, " ")
		command, args := words[0], words[1:]
		if command == "UNDO" {
			if len(history) == 0 {
				fmt.Fprintln(out, "ERROR NOTHING TO UNDO")
				continue
			}
			saved := history[len(history)-1]
			history = history[:len(history)-1]
			family = saved.Family
			fmt.Fprintln(out, "UNDONE "+saved.Line)
			continue
		}
		if modifying[command] {
			saved := family.copy()
			result, err := family.modify(command, args)
			if err != nil {
				fmt.Fprintln(out, "ERROR "+err.Error())
				continue
			}
			history = append(history, Snapshot{line, saved})
			clear(family.Distances)
			clear(family.Coefficients)
			fmt.Fprintln(out, result)
		} else {
			lines, err := family.query(command, args)
			if err != nil {
				fmt.Fprintln(out, "ERROR "+err.Error())
				continue
			}
			for _, result := range lines {
				fmt.Fprintln(out, result)
			}
		}
	}
}
