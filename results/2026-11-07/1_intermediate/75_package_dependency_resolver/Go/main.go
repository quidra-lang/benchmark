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

type version struct {
	core [3]int
	pre  []string
	text string
}
type comparator struct {
	op    string
	value *version
}
type alternative struct {
	comparisons []comparator
	prerelease  map[[3]int]bool
}
type constraint struct {
	alternatives []alternative
	normal       string
}
type requirementPair struct{ name, text string }
type release struct {
	name                    string
	version                 *version
	dependencies, conflicts []requirementPair
	yanked                  bool
}
type requirement struct {
	requirementPair
	chain []string
}
type advisory struct{ name, text string }
type snapshot struct {
	requests  []requirementPair
	installed map[string]*release
}
type manager struct {
	registry   map[string][]*release
	parsed     map[string]*constraint
	requests   []requirementPair
	installed  map[string]*release
	held       map[string]bool
	advisories map[string]advisory
	history    []snapshot
	out        *bufio.Writer
}

func keys[T any](items map[string]T) []string {
	result := []string{}
	for name := range items {
		result = append(result, name)
	}
	sort.Strings(result)
	return result
}
func numeric(text string) bool {
	if len(text) == 0 {
		return false
	}
	for i := range text {
		if text[i] < '0' || text[i] > '9' {
			return false
		}
	}
	return true
}
func numberWord(text string) bool {
	return len(text) >= 1 && len(text) <= 4 && numeric(text) && (len(text) == 1 || text[0] != '0')
}
func integer(text string) int { value, _ := strconv.Atoi(text); return value }
func makeVersion(core [3]int, pre []string) *version {
	text := fmt.Sprintf("%d.%d.%d", core[0], core[1], core[2])
	if len(pre) > 0 {
		text += "-" + strings.Join(pre, ".")
	}
	return &version{core, pre, text}
}
func parseVersion(text string) *version {
	coreText, suffix, hasSuffix := strings.Cut(text, "-")
	parts := strings.Split(coreText, ".")
	if len(parts) != 3 {
		return nil
	}
	core := [3]int{}
	for i, part := range parts {
		if !numberWord(part) {
			return nil
		}
		core[i] = integer(part)
	}
	pre := []string{}
	if hasSuffix {
		pre = strings.Split(suffix, ".")
		for _, part := range pre {
			if len(part) == 0 {
				return nil
			}
			for i := range part {
				if !(part[i] >= 'a' && part[i] <= 'z' || part[i] >= '0' && part[i] <= '9') {
					return nil
				}
			}
			if numeric(part) && !numberWord(part) {
				return nil
			}
		}
	}
	return makeVersion(core, pre)
}
func compare(a, b *version) int {
	for i := 0; i < 3; i++ {
		if a.core[i] < b.core[i] {
			return -1
		}
		if a.core[i] > b.core[i] {
			return 1
		}
	}
	if len(a.pre) == 0 && len(b.pre) > 0 {
		return 1
	}
	if len(b.pre) == 0 && len(a.pre) > 0 {
		return -1
	}
	for i := 0; i < len(a.pre) && i < len(b.pre); i++ {
		x, y := a.pre[i], b.pre[i]
		if x == y {
			continue
		}
		nx, ny := numeric(x), numeric(y)
		if nx && ny {
			if integer(x) < integer(y) {
				return -1
			}
			return 1
		}
		if nx != ny {
			if nx {
				return -1
			}
			return 1
		}
		if x < y {
			return -1
		}
		return 1
	}
	if len(a.pre) < len(b.pre) {
		return -1
	}
	if len(a.pre) > len(b.pre) {
		return 1
	}
	return 0
}
func parseConstraint(text string) *constraint {
	result, forms := &constraint{}, []string{}
	for _, branch := range strings.Split(text, " || ") {
		item := alternative{prerelease: map[[3]int]bool{}}
		for _, term := range strings.Split(branch, " ") {
			if term == "" {
				return nil
			}
			op, pattern := "", term
			for _, candidate := range []string{">=", "<=", ">", "<", "=", "^", "~"} {
				if strings.HasPrefix(term, candidate) {
					op, pattern = candidate, term[len(candidate):]
					break
				}
			}
			core, pre, count := [3]int{}, []string{}, 0
			if strings.Contains(pattern, "-") {
				value := parseVersion(pattern)
				if value == nil || len(value.pre) == 0 {
					return nil
				}
				core, pre, count = value.core, value.pre, 3
				item.prerelease[core] = true
			} else {
				parts, wildcard := strings.Split(pattern, "."), false
				if len(parts) < 1 || len(parts) > 3 {
					return nil
				}
				for i, part := range parts {
					if part == "x" || part == "*" {
						wildcard = true
					} else {
						if wildcard || !numberWord(part) {
							return nil
						}
						core[i], count = integer(part), count+1
					}
				}
			}
			lower := makeVersion(core, pre)
			upper := func(at int) *version {
				next := core
				next[at]++
				for i := at + 1; i < 3; i++ {
					next[i] = 0
				}
				return makeVersion(next, nil)
			}
			add := func(operator string, value *version) {
				item.comparisons = append(item.comparisons, comparator{operator, value})
			}
			if count == 0 {
				if op == ">" || op == "<" {
					add("<", makeVersion([3]int{}, []string{"0"}))
				}
			} else {
				switch op {
				case "", "=":
					if count == 3 {
						add("=", lower)
					} else {
						add(">=", lower)
						add("<", upper(count-1))
					}
				case ">":
					if count == 3 {
						add(">", lower)
					} else {
						add(">=", upper(count-1))
					}
				case "<=":
					if count == 3 {
						add("<=", lower)
					} else {
						add("<", upper(count-1))
					}
				case ">=", "<":
					add(op, lower)
				case "~":
					at := 1
					if count == 1 {
						at = 0
					}
					add(">=", lower)
					add("<", upper(at))
				case "^":
					at := 2
					if core[0] != 0 || count == 1 {
						at = 0
					} else if core[1] != 0 || count == 2 {
						at = 1
					}
					add(">=", lower)
					add("<", upper(at))
				}
			}
		}
		words := []string{}
		for _, comparison := range item.comparisons {
			words = append(words, comparison.op+comparison.value.text)
		}
		if len(words) == 0 {
			words = append(words, "*")
		}
		forms = append(forms, strings.Join(words, " "))
		result.alternatives = append(result.alternatives, item)
	}
	result.normal = strings.Join(forms, " || ")
	return result
}
func (c *constraint) matches(v *version) bool {
	for _, branch := range c.alternatives {
		if len(v.pre) > 0 && !branch.prerelease[v.core] {
			continue
		}
		valid := true
		for _, comparison := range branch.comparisons {
			order := compare(v, comparison.value)
			switch comparison.op {
			case "=":
				valid = order == 0
			case ">":
				valid = order > 0
			case ">=":
				valid = order >= 0
			case "<":
				valid = order < 0
			case "<=":
				valid = order <= 0
			}
			if !valid {
				break
			}
		}
		if valid {
			return true
		}
	}
	return false
}
func (m *manager) constraint(text string) (*constraint, error) {
	if value := m.parsed[text]; value != nil {
		return value, nil
	}
	value := parseConstraint(text)
	if value == nil {
		return nil, fmt.Errorf("invalid constraint '%s'", text)
	}
	m.parsed[text] = value
	return value, nil
}
func checkedVersion(text string) (*version, error) {
	value := parseVersion(text)
	if value == nil {
		return nil, fmt.Errorf("invalid version '%s'", text)
	}
	return value, nil
}
func (m *manager) matches(v *version, text string) bool { return m.parsed[text].matches(v) }
func (m *manager) find(name, text string) *release {
	for _, value := range m.registry[name] {
		if value.version.text == text {
			return value
		}
	}
	return nil
}
func clone(items map[string]*release) map[string]*release {
	result := map[string]*release{}
	for name, value := range items {
		result[name] = value
	}
	return result
}
func (m *manager) applicable(value *release) []string {
	result := []string{}
	for _, id := range keys(m.advisories) {
		advisory := m.advisories[id]
		if advisory.name == value.name && m.matches(value.version, advisory.text) {
			result = append(result, id)
		}
	}
	return result
}
func (m *manager) usable(value *release, audit bool) bool {
	return (!value.yanked || m.installed[value.name] == value) && (!audit || len(m.applicable(value)) == 0)
}
func (m *manager) display(value *release) string {
	flags := []string{}
	if value.yanked {
		flags = append(flags, "yanked")
	}
	if m.installed[value.name] == value {
		flags = append(flags, "installed")
	}
	text := value.name + "@" + value.version.text
	if len(flags) > 0 {
		text += " (" + strings.Join(flags, ", ") + ")"
	}
	return text
}
func label(value *release) string { return value.name + "@" + value.version.text }

func (m *manager) resolve(requests []requirementPair, preferred map[string]bool, audit bool) (map[string]*release, []string) {
	selected, origins := map[string]*release{}, map[string]requirement{}
	failure, depth := []string(nil), -1
	record := func(r requirement, reason string, extra []string) {
		if len(selected) <= depth {
			return
		}
		depth, failure = len(selected), []string{"UNSATISFIABLE"}
		for _, line := range r.chain {
			failure = append(failure, "  "+line)
		}
		failure = append(failure, "  "+reason)
		for _, line := range extra {
			failure = append(failure, "    "+line)
		}
	}
	var search func([]requirement) bool
	search = func(todo []requirement) bool {
		if len(todo) == 0 {
			return true
		}
		r, rest := todo[0], todo[1:]
		if chosen := selected[r.name]; chosen != nil {
			if m.matches(chosen.version, r.text) {
				return search(rest)
			}
			record(r, label(chosen)+" was selected by:", origins[r.name].chain)
			return false
		}
		candidates := []*release{}
		if m.held[r.name] {
			value := m.installed[r.name]
			if m.matches(value.version, r.text) && m.usable(value, audit) {
				candidates = append(candidates, value)
			} else {
				record(r, label(value)+" is held", nil)
				return false
			}
		} else {
			for _, value := range m.registry[r.name] {
				if m.matches(value.version, r.text) && m.usable(value, audit) {
					candidates = append(candidates, value)
				}
			}
			if preferred[r.name] {
				for i, value := range candidates {
					if m.installed[r.name] == value {
						candidates = append([]*release{value}, append(candidates[:i:i], candidates[i+1:]...)...)
						break
					}
				}
			}
			if len(candidates) == 0 {
				record(r, fmt.Sprintf("no version of %s matches %s", r.name, r.text), nil)
				return false
			}
		}
		for _, candidate := range candidates {
			conflicting := ""
			for _, name := range keys(selected) {
				chosen := selected[name]
				conflict := false
				for _, pair := range candidate.conflicts {
					if pair.name == name && m.matches(chosen.version, pair.text) {
						conflict = true
						break
					}
				}
				if !conflict {
					for _, pair := range chosen.conflicts {
						if pair.name == r.name && m.matches(candidate.version, pair.text) {
							conflict = true
							break
						}
					}
				}
				if conflict {
					conflicting = name
					break
				}
			}
			if conflicting != "" {
				record(r, fmt.Sprintf("%s conflicts with %s, which was selected by:", label(candidate), label(selected[conflicting])), origins[conflicting].chain)
				continue
			}
			selected[r.name], origins[r.name] = candidate, r
			following := []requirement{}
			for _, pair := range candidate.dependencies {
				chain := append(append([]string{}, r.chain...), fmt.Sprintf("%s requires %s %s", label(candidate), pair.name, pair.text))
				following = append(following, requirement{pair, chain})
			}
			following = append(following, rest...)
			if search(following) {
				return true
			}
			delete(selected, r.name)
			delete(origins, r.name)
		}
		return false
	}
	initial := []requirement{}
	for _, pair := range requests {
		initial = append(initial, requirement{pair, []string{fmt.Sprintf("requested %s %s", pair.name, pair.text)}})
	}
	if search(initial) {
		return selected, nil
	}
	return nil, failure
}
func (m *manager) reportFailure(lines []string) {
	for _, line := range lines {
		fmt.Fprintln(m.out, line)
	}
}
func (m *manager) plan(next map[string]*release) {
	arranged, installed, upgraded, downgraded, removed := map[string]bool{}, 0, 0, 0, 0
	for len(arranged) < len(next) {
		for _, name := range keys(next) {
			if arranged[name] {
				continue
			}
			ready := true
			for _, dep := range next[name].dependencies {
				if !arranged[dep.name] {
					ready = false
					break
				}
			}
			if !ready {
				continue
			}
			value, old := next[name], m.installed[name]
			if old == nil {
				fmt.Fprintln(m.out, "install "+label(value))
				installed++
			} else if old != value {
				action := "upgrade"
				if compare(value.version, old.version) < 0 {
					action = "downgrade"
					downgraded++
				} else {
					upgraded++
				}
				fmt.Fprintf(m.out, "%s %s %s -> %s\n", action, name, old.version.text, value.version.text)
			}
			arranged[name] = true
			break
		}
	}
	dropping := map[string]bool{}
	for name := range m.installed {
		if next[name] == nil {
			dropping[name] = true
		}
	}
	for len(dropping) > 0 {
		for _, name := range keys(dropping) {
			ready := true
			for other := range dropping {
				for _, dep := range m.installed[other].dependencies {
					if dep.name == name {
						ready = false
						break
					}
				}
				if !ready {
					break
				}
			}
			if ready {
				fmt.Fprintln(m.out, "remove "+label(m.installed[name]))
				delete(dropping, name)
				removed++
				break
			}
		}
	}
	if installed+upgraded+downgraded+removed == 0 {
		fmt.Fprintln(m.out, "no changes")
	} else {
		fmt.Fprintf(m.out, "%d installed, %d upgraded, %d downgraded, %d removed\n", installed, upgraded, downgraded, removed)
	}
}
func (m *manager) update(requests []requirementPair, installed map[string]*release, save bool) {
	if save {
		m.history = append(m.history, snapshot{append([]requirementPair{}, m.requests...), clone(m.installed)})
	}
	m.requests, m.installed = append([]requirementPair{}, requests...), clone(installed)
	for name := range m.held {
		if installed[name] == nil {
			delete(m.held, name)
		}
	}
}
func (m *manager) parent(name string) string {
	for _, candidate := range keys(m.installed) {
		for _, dep := range m.installed[candidate].dependencies {
			if dep.name == name {
				return candidate
			}
		}
	}
	return ""
}
func (m *manager) requested(name string) (string, bool) {
	for _, pair := range m.requests {
		if pair.name == name {
			return pair.text, true
		}
	}
	return "", false
}
func (m *manager) tree(root string, seen map[string]bool, text *string, prefix, indent string) {
	value := m.installed[root]
	body := prefix + label(value)
	if text != nil {
		body += " [" + *text + "]"
	}
	if seen[root] {
		fmt.Fprintln(m.out, body+" (*)")
		return
	}
	fmt.Fprintln(m.out, body)
	seen[root] = true
	for i, pair := range value.dependencies {
		mark, following := "|-- ", "|   "
		if i+1 == len(value.dependencies) {
			mark, following = "`-- ", "    "
		}
		m.tree(pair.name, seen, &pair.text, indent+mark, indent+following)
	}
}

func (m *manager) command(line string) error {
	w := strings.Split(line, " ")
	cmd := w[0]
	switch cmd {
	case "PKG":
		clauses := strings.Split(line, "; ")
		head := strings.Split(clauses[0], " ")
		value, err := checkedVersion(head[2])
		if err != nil {
			return err
		}
		if m.find(head[1], head[2]) != nil {
			return fmt.Errorf("%s@%s is already registered", head[1], head[2])
		}
		candidate := &release{name: head[1], version: value}
		for _, clause := range clauses[1:] {
			parts := strings.SplitN(clause, " ", 3)
			if _, err := m.constraint(parts[2]); err != nil {
				return err
			}
			pair := requirementPair{parts[1], parts[2]}
			if parts[0] == "DEP" {
				candidate.dependencies = append(candidate.dependencies, pair)
			} else {
				candidate.conflicts = append(candidate.conflicts, pair)
			}
		}
		m.registry[candidate.name] = append(m.registry[candidate.name], candidate)
		sort.Slice(m.registry[candidate.name], func(i, j int) bool {
			return compare(m.registry[candidate.name][i].version, m.registry[candidate.name][j].version) > 0
		})
		fmt.Fprintln(m.out, "registered "+label(candidate))
	case "YANK", "INFO":
		value := m.find(w[1], w[2])
		if value == nil {
			return fmt.Errorf("%s@%s is not registered", w[1], w[2])
		}
		if cmd == "YANK" {
			if value.yanked {
				return fmt.Errorf("%s is already yanked", label(value))
			}
			value.yanked = true
			fmt.Fprintln(m.out, "yanked "+label(value))
		} else {
			fmt.Fprintln(m.out, m.display(value))
			for _, pair := range value.dependencies {
				fmt.Fprintf(m.out, "  requires %s %s\n", pair.name, pair.text)
			}
			for _, pair := range value.conflicts {
				fmt.Fprintf(m.out, "  conflicts with %s %s\n", pair.name, pair.text)
			}
			for _, id := range m.applicable(value) {
				fmt.Fprintln(m.out, "  advisory "+id)
			}
		}
	case "COMPARE":
		a, err := checkedVersion(w[1])
		if err != nil {
			return err
		}
		b, err := checkedVersion(w[2])
		if err != nil {
			return err
		}
		relation := "="
		if compare(a, b) < 0 {
			relation = "<"
		} else if compare(a, b) > 0 {
			relation = ">"
		}
		fmt.Fprintf(m.out, "%s %s %s\n", w[1], relation, w[2])
	case "MATCH":
		parts := strings.SplitN(line, " ", 3)
		value, err := checkedVersion(parts[1])
		if err != nil {
			return err
		}
		condition, err := m.constraint(parts[2])
		if err != nil {
			return err
		}
		if condition.matches(value) {
			fmt.Fprintln(m.out, "yes")
		} else {
			fmt.Fprintln(m.out, "no")
		}
	case "RANGE":
		condition, err := m.constraint(line[6:])
		if err != nil {
			return err
		}
		fmt.Fprintln(m.out, condition.normal)
	case "VERSIONS", "INSTALL", "SIMULATE":
		parts := strings.SplitN(line, " ", 3)
		text := "*"
		if len(parts) == 3 {
			text = parts[2]
		}
		condition, err := m.constraint(text)
		if err != nil {
			return err
		}
		if len(m.registry[w[1]]) == 0 {
			return fmt.Errorf("unknown package %s", w[1])
		}
		if cmd == "VERSIONS" {
			count := 0
			for _, value := range m.registry[w[1]] {
				if len(parts) == 2 || condition.matches(value.version) {
					fmt.Fprintln(m.out, m.display(value))
					count++
				}
			}
			if count == 0 {
				fmt.Fprintln(m.out, "no matching versions")
			}
		} else {
			requests, found := append([]requirementPair{}, m.requests...), false
			for i := range requests {
				if requests[i].name == w[1] {
					requests[i].text, found = text, true
					break
				}
			}
			if !found {
				requests = append(requests, requirementPair{w[1], text})
			}
			preferred := map[string]bool{}
			for name := range m.installed {
				preferred[name] = true
			}
			next, failure := m.resolve(requests, preferred, false)
			if failure != nil {
				m.reportFailure(failure)
			} else {
				m.plan(next)
				if cmd == "INSTALL" {
					m.update(requests, next, true)
				}
			}
		}
	case "DEPENDENTS":
		var selected *version
		if len(w) == 3 {
			var err error
			selected, err = checkedVersion(w[2])
			if err != nil {
				return err
			}
		}
		count := 0
		for _, name := range keys(m.registry) {
			for _, value := range m.registry[name] {
				for _, pair := range value.dependencies {
					if pair.name == w[1] && (selected == nil || m.matches(selected, pair.text)) {
						fmt.Fprintf(m.out, "%s requires %s %s\n", label(value), w[1], pair.text)
						count++
					}
				}
			}
		}
		if count == 0 {
			fmt.Fprintln(m.out, "no dependents")
		}
	case "REMOVE":
		_, requested := m.requested(w[1])
		if !requested {
			if m.installed[w[1]] != nil {
				return fmt.Errorf("%s is required by %s", w[1], m.parent(w[1]))
			}
			return fmt.Errorf("%s is not installed", w[1])
		}
		requests, keep, queue := []requirementPair{}, map[string]*release{}, []string{}
		for _, pair := range m.requests {
			if pair.name != w[1] {
				requests = append(requests, pair)
				queue = append(queue, pair.name)
			}
		}
		for at := 0; at < len(queue); at++ {
			name := queue[at]
			if keep[name] != nil {
				continue
			}
			keep[name] = m.installed[name]
			for _, dep := range m.installed[name].dependencies {
				queue = append(queue, dep.name)
			}
		}
		if keep[w[1]] != nil {
			fmt.Fprintf(m.out, "%s is still required by %s\n", label(m.installed[w[1]]), m.parent(w[1]))
			m.update(requests, m.installed, true)
		} else {
			m.plan(keep)
			m.update(requests, keep, true)
		}
	case "UPGRADE":
		if len(w) == 2 && m.installed[w[1]] == nil {
			return fmt.Errorf("%s is not installed", w[1])
		}
		preferred := map[string]bool{}
		if len(w) == 2 {
			for name := range m.installed {
				if name != w[1] {
					preferred[name] = true
				}
			}
		}
		next, failure := m.resolve(m.requests, preferred, false)
		if failure != nil {
			m.reportFailure(failure)
		} else {
			m.plan(next)
			m.update(m.requests, next, true)
		}
	case "ROLLBACK":
		if len(m.history) == 0 {
			return fmt.Errorf("nothing to roll back")
		}
		saved := m.history[len(m.history)-1]
		m.history = m.history[:len(m.history)-1]
		m.plan(saved.installed)
		m.update(saved.requests, saved.installed, false)
	case "HOLD":
		if m.installed[w[1]] == nil {
			return fmt.Errorf("%s is not installed", w[1])
		}
		if m.held[w[1]] {
			return fmt.Errorf("%s is already held", w[1])
		}
		m.held[w[1]] = true
		fmt.Fprintln(m.out, "held "+label(m.installed[w[1]]))
	case "UNHOLD":
		if !m.held[w[1]] {
			return fmt.Errorf("%s is not held", w[1])
		}
		delete(m.held, w[1])
		fmt.Fprintln(m.out, "released "+w[1])
	case "WHY":
		value := m.installed[w[1]]
		if value == nil {
			return fmt.Errorf("%s is not installed", w[1])
		}
		if _, requested := m.requested(w[1]); requested {
			fmt.Fprintln(m.out, label(value)+" is explicitly installed")
			return nil
		}
		previous, seen, queue := map[string]string{}, map[string]bool{}, []string{}
		roots := map[string]bool{}
		for _, pair := range m.requests {
			roots[pair.name] = true
		}
		for _, name := range keys(roots) {
			queue = append(queue, name)
			seen[name] = true
		}
		for at := 0; at < len(queue); at++ {
			name, deps := queue[at], map[string]bool{}
			for _, pair := range m.installed[name].dependencies {
				deps[pair.name] = true
			}
			for _, dep := range keys(deps) {
				if !seen[dep] {
					seen[dep], previous[dep] = true, name
					queue = append(queue, dep)
				}
			}
		}
		path := []string{}
		for name := w[1]; name != ""; name = previous[name] {
			path = append(path, label(m.installed[name]))
		}
		for a, b := 0, len(path)-1; a < b; a, b = a+1, b-1 {
			path[a], path[b] = path[b], path[a]
		}
		fmt.Fprintln(m.out, strings.Join(path, " -> "))
	case "TREE":
		if len(w) == 2 && m.installed[w[1]] == nil {
			return fmt.Errorf("%s is not installed", w[1])
		}
		roots := []string{}
		if len(w) == 2 {
			roots = append(roots, w[1])
		} else {
			for _, pair := range m.requests {
				roots = append(roots, pair.name)
			}
			sort.Strings(roots)
		}
		if len(roots) == 0 {
			fmt.Fprintln(m.out, "(empty)")
		}
		seen := map[string]bool{}
		for _, name := range roots {
			var text *string
			if value, requested := m.requested(name); requested {
				text = &value
			}
			m.tree(name, seen, text, "", "")
		}
	case "OUTDATED":
		count := 0
		for _, name := range keys(m.installed) {
			current, conditions := m.installed[name], []string{}
			if text, requested := m.requested(name); requested {
				conditions = append(conditions, text)
			}
			for _, value := range m.installed {
				for _, pair := range value.dependencies {
					if pair.name == name {
						conditions = append(conditions, pair.text)
					}
				}
			}
			var wanted, latest *release
			for _, value := range m.registry[name] {
				if !value.yanked && len(value.version.pre) == 0 && latest == nil {
					latest = value
				}
				if wanted != nil || value.yanked && value != current {
					continue
				}
				valid := true
				for _, text := range conditions {
					if !m.matches(value.version, text) {
						valid = false
						break
					}
				}
				if valid {
					wanted = value
				}
			}
			if wanted != current || latest != nil && compare(latest.version, current.version) > 0 {
				latestText := "-"
				if latest != nil {
					latestText = latest.version.text
				}
				fmt.Fprintf(m.out, "%s %s %s %s\n", name, current.version.text, wanted.version.text, latestText)
				count++
			}
		}
		if count == 0 {
			fmt.Fprintln(m.out, "all packages are up to date")
		}
	case "LOCK":
		if len(m.installed) == 0 {
			fmt.Fprintln(m.out, "(empty)")
		}
		for _, name := range keys(m.installed) {
			fmt.Fprintln(m.out, label(m.installed[name]))
		}
	case "STATUS":
		if len(m.requests) == 0 {
			fmt.Fprintln(m.out, "no requests")
		}
		for _, pair := range m.requests {
			fmt.Fprintf(m.out, "%s %s -> %s\n", pair.name, pair.text, m.installed[pair.name].version.text)
		}
		fmt.Fprintf(m.out, "%d installed, %d held, %d snapshots\n", len(m.installed), len(m.held), len(m.history))
	case "ADVISORY":
		parts := strings.SplitN(line, " ", 4)
		if _, exists := m.advisories[w[1]]; exists {
			return fmt.Errorf("advisory %s already exists", w[1])
		}
		if _, err := m.constraint(parts[3]); err != nil {
			return err
		}
		m.advisories[w[1]] = advisory{w[2], parts[3]}
		fmt.Fprintf(m.out, "advisory %s recorded\n", w[1])
	case "AUDIT":
		if len(w) == 2 {
			preferred := map[string]bool{}
			for name := range m.installed {
				preferred[name] = true
			}
			next, failure := m.resolve(m.requests, preferred, true)
			if failure != nil {
				m.reportFailure(failure)
			} else {
				m.plan(next)
				m.update(m.requests, next, true)
			}
		} else {
			count := 0
			for _, name := range keys(m.installed) {
				current := m.installed[name]
				ids := m.applicable(current)
				if len(ids) == 0 {
					continue
				}
				var fix *release
				values := m.registry[name]
				for i := len(values) - 1; i >= 0; i-- {
					value := values[i]
					if compare(value.version, current.version) > 0 && len(value.version.pre) == 0 && !value.yanked && len(m.applicable(value)) == 0 {
						fix = value
						break
					}
				}
				suffix := "no fix"
				if fix != nil {
					suffix = "fix: " + fix.version.text
				}
				fmt.Fprintf(m.out, "%s: %s (%s)\n", label(current), strings.Join(ids, ", "), suffix)
				count++
			}
			if count == 0 {
				fmt.Fprintln(m.out, "no known vulnerabilities")
			}
		}
	}
	return nil
}

func main() {
	input, _ := io.ReadAll(os.Stdin)
	lines := strings.Split(string(input), "\n")
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	m := &manager{registry: map[string][]*release{}, parsed: map[string]*constraint{}, installed: map[string]*release{}, held: map[string]bool{}, advisories: map[string]advisory{}, out: out}
	for _, text := range lines[1 : integer(lines[0])+1] {
		if err := m.command(text); err != nil {
			fmt.Fprintln(out, "error: "+err.Error())
		}
	}
}
