package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
)

type entry struct {
	key   int
	value string
}

func (e entry) String() string { return fmt.Sprintf("%d=%s", e.key, e.value) }

type node struct {
	entries  []entry
	children []int
}

func (n *node) notation() string {
	keys := make([]string, len(n.entries))
	for i, e := range n.entries {
		keys[i] = strconv.Itoa(e.key)
	}
	return "[" + strings.Join(keys, " ") + "]"
}

func (n *node) position(key int) int {
	for i, e := range n.entries {
		if key <= e.key {
			return i
		}
	}
	return len(n.entries)
}

func copyPages(pages map[int]*node) map[int]*node {
	result := make(map[int]*node, len(pages))
	for id, n := range pages {
		result[id] = &node{slices.Clone(n.entries), slices.Clone(n.children)}
	}
	return result
}

type trace struct {
	enabled bool
	lines   []string
}

func (tr *trace) emit(format string, args ...any) {
	if tr.enabled {
		tr.lines = append(tr.lines, fmt.Sprintf(format, args...))
	}
}

type tree struct {
	degree, root            int
	pages                   map[int]*node
	splits, merges, borrows int
}

func newTree(degree int) *tree {
	return &tree{degree: degree, pages: map[int]*node{0: {}}}
}

func (t *tree) clone() *tree {
	result := *t
	result.pages = copyPages(t.pages)
	return &result
}

func (t *tree) allocate(n *node) int {
	id := 0
	for t.pages[id] != nil {
		id++
	}
	t.pages[id] = n
	return id
}

func (t *tree) entries() []entry {
	var result []entry
	var visit func(int)
	visit = func(page int) {
		n := t.pages[page]
		for j := 0; j <= len(n.entries); j++ {
			if len(n.children) != 0 {
				visit(n.children[j])
			}
			if j < len(n.entries) {
				result = append(result, n.entries[j])
			}
		}
	}
	visit(t.root)
	return result
}

type searchResult struct {
	page, position int
	found          bool
	path           []string
}

func (t *tree) search(key int) searchResult {
	result := searchResult{page: t.root}
	for {
		n := t.pages[result.page]
		result.path = append(result.path, n.notation())
		result.position = n.position(key)
		if result.position < len(n.entries) && n.entries[result.position].key == key {
			result.found = true
			return result
		}
		if len(n.children) == 0 {
			return result
		}
		result.page = n.children[result.position]
	}
}

func (t *tree) violation() string {
	referenceDepth := -1
	var visit func(int, string, int, *int, *int) string
	visit = func(page int, location string, depth int, low, high *int) string {
		n := t.pages[page]
		count, minimum, maximum := len(n.entries), t.degree-1, 2*t.degree-1
		if page == t.root {
			minimum = 0
			if len(n.children) != 0 {
				minimum = 1
			}
		}
		details := fmt.Sprintf("at=%s node=%s", location, n.notation())
		if count < minimum || count > maximum {
			return fmt.Sprintf("COUNT %s keys=%d allowed=%d..%d", details, count, minimum, maximum)
		}
		for j := 0; j+1 < count; j++ {
			if n.entries[j].key >= n.entries[j+1].key {
				return fmt.Sprintf("ORDER %s %d>=%d", details, n.entries[j].key, n.entries[j+1].key)
			}
		}
		for _, e := range n.entries {
			if low != nil && e.key <= *low || high != nil && e.key >= *high {
				lower, upper := "-inf", "+inf"
				if low != nil {
					lower = strconv.Itoa(*low)
				}
				if high != nil {
					upper = strconv.Itoa(*high)
				}
				return fmt.Sprintf("RANGE %s key=%d low=%s high=%s", details, e.key, lower, upper)
			}
		}
		if len(n.children) == 0 {
			if referenceDepth < 0 {
				referenceDepth = depth
			} else if referenceDepth != depth {
				return fmt.Sprintf("DEPTH %s depth=%d expected=%d", details, depth, referenceDepth)
			}
		}
		for j, child := range n.children {
			lower, upper := low, high
			if j > 0 {
				lower = &n.entries[j-1].key
			}
			if j < count {
				upper = &n.entries[j].key
			}
			if problem := visit(child, location+"."+strconv.Itoa(j), depth+1, lower, upper); problem != "" {
				return problem
			}
		}
		return ""
	}
	return visit(t.root, "root", 0, nil, nil)
}

func (t *tree) status() string {
	if t.violation() == "" {
		return "OK"
	}
	return "DAMAGED"
}

func (t *tree) height() int {
	page, depth := t.root, 0
	for len(t.pages[page].children) != 0 {
		page = t.pages[page].children[0]
		depth++
	}
	return depth
}

func number(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

type parser struct {
	tokens   []string
	position int
	index    *tree
}

func (p *parser) peek() string {
	if p.position == len(p.tokens) {
		return ""
	}
	return p.tokens[p.position]
}

func (p *parser) entry() (entry, error) {
	key, value, ok := strings.Cut(p.peek(), "=")
	if !ok {
		return entry{}, fmt.Errorf("SYNTAX %d", p.position+1)
	}
	p.position++
	return entry{number(key), value}, nil
}

func (p *parser) node() (int, error) {
	if p.peek() != "(" {
		return 0, fmt.Errorf("SYNTAX %d", p.position+1)
	}
	p.position++
	n := &node{}
	page := p.index.allocate(n)
	internal := p.peek() == "("
	if internal {
		child, err := p.node()
		if err != nil {
			return 0, err
		}
		n.children = append(n.children, child)
	}
	for p.peek() != ")" {
		e, err := p.entry()
		if err != nil {
			return 0, err
		}
		n.entries = append(n.entries, e)
		if internal {
			child, err := p.node()
			if err != nil {
				return 0, err
			}
			n.children = append(n.children, child)
		}
	}
	p.position++
	return page, nil
}

func loadTree(degree int, tokens []string) (*tree, error) {
	p := parser{tokens: tokens, index: &tree{degree: degree, pages: make(map[int]*node)}}
	root, err := p.node()
	if err != nil {
		return nil, err
	}
	if p.position != len(tokens) {
		return nil, fmt.Errorf("SYNTAX %d", p.position+1)
	}
	p.index.root = root
	return p.index, nil
}

func (t *tree) changes(before map[int]*node) (writes, frees int) {
	for page, after := range t.pages {
		old := before[page]
		if old == nil || !slices.Equal(old.entries, after.entries) || !slices.Equal(old.children, after.children) {
			writes++
		}
	}
	for page := range before {
		if t.pages[page] == nil {
			frees++
		}
	}
	return
}

func (t *tree) split(parent, position int, tr *trace) {
	x := t.pages[parent]
	child := x.children[position]
	y := t.pages[child]
	old, middle := y.notation(), y.entries[t.degree-1]
	z := &node{entries: slices.Clone(y.entries[t.degree:])}
	if len(y.children) != 0 {
		z.children = slices.Clone(y.children[t.degree:])
		y.children = y.children[:t.degree]
	}
	y.entries = y.entries[:t.degree-1]
	newPage := t.allocate(z)
	x.entries = slices.Insert(x.entries, position, middle)
	x.children = slices.Insert(x.children, position+1, newPage)
	t.splits++
	tr.emit("STEP split page=%d keys=%s up=%d new=%d", child, old, middle.key, newPage)
}

func (t *tree) upsert(e entry, tr *trace) (string, bool) {
	found := t.search(e.key)
	if found.found {
		n := t.pages[found.page]
		old := n.entries[found.position].value
		n.entries[found.position].value = e.value
		return old, true
	}
	if len(t.pages[t.root].entries) == 2*t.degree-1 {
		t.root = t.allocate(&node{children: []int{t.root}})
		tr.emit("STEP grow page=%d", t.root)
		t.split(t.root, 0, tr)
	}
	page := t.root
	for len(t.pages[page].children) != 0 {
		n := t.pages[page]
		position := n.position(e.key)
		if len(t.pages[n.children[position]].entries) == 2*t.degree-1 {
			t.split(page, position, tr)
			if e.key > n.entries[position].key {
				position++
			}
		}
		page = n.children[position]
	}
	n := t.pages[page]
	n.entries = slices.Insert(n.entries, n.position(e.key), e)
	tr.emit("STEP place page=%d keys=%s", page, n.notation())
	return "", false
}

func (t *tree) extreme(page int, last bool) entry {
	for {
		n := t.pages[page]
		if len(n.children) == 0 {
			if last {
				return n.entries[len(n.entries)-1]
			}
			return n.entries[0]
		}
		page = n.children[0]
		if last {
			page = n.children[len(n.children)-1]
		}
	}
}

func (t *tree) merge(parent, position int, caseName string, tr *trace) int {
	x := t.pages[parent]
	left, right := x.children[position], x.children[position+1]
	y, z := t.pages[left], t.pages[right]
	y.entries = append(y.entries, x.entries[position])
	y.entries = append(y.entries, z.entries...)
	y.children = append(y.children, z.children...)
	x.entries = slices.Delete(x.entries, position, position+1)
	x.children = slices.Delete(x.children, position+1, position+2)
	delete(t.pages, right)
	t.merges++
	tr.emit("STEP %s page=%d merge=%d+%d keys=%s", caseName, parent, left, right, y.notation())
	if parent == t.root && len(x.entries) == 0 {
		t.root = left
		delete(t.pages, parent)
		tr.emit("STEP shrink page=%d", left)
	}
	return left
}

func (t *tree) removeAt(page, key int, cases *[]string, tr *trace) {
	x := t.pages[page]
	position := x.position(key)
	if position < len(x.entries) && x.entries[position].key == key {
		if len(x.children) == 0 {
			*cases = append(*cases, "1")
			x.entries = slices.Delete(x.entries, position, position+1)
			tr.emit("STEP 1 page=%d keys=%s", page, x.notation())
			return
		}
		left, right := x.children[position], x.children[position+1]
		if len(t.pages[left].entries) >= t.degree {
			*cases = append(*cases, "2a")
			predecessor := t.extreme(left, true)
			tr.emit("STEP 2a page=%d pred=%d", page, predecessor.key)
			t.removeAt(left, predecessor.key, cases, tr)
			x.entries[position] = predecessor
		} else if len(t.pages[right].entries) >= t.degree {
			*cases = append(*cases, "2b")
			successor := t.extreme(right, false)
			tr.emit("STEP 2b page=%d succ=%d", page, successor.key)
			t.removeAt(right, successor.key, cases, tr)
			x.entries[position] = successor
		} else {
			*cases = append(*cases, "2c")
			child := t.merge(page, position, "2c", tr)
			t.removeAt(child, key, cases, tr)
		}
		return
	}
	child := x.children[position]
	c := t.pages[child]
	if len(c.entries) == t.degree-1 {
		left, right := -1, -1
		if position > 0 {
			left = x.children[position-1]
		}
		if position+1 < len(x.children) {
			right = x.children[position+1]
		}
		switch {
		case left >= 0 && len(t.pages[left].entries) >= t.degree:
			*cases = append(*cases, "3a-left")
			sibling := t.pages[left]
			last := len(sibling.entries) - 1
			c.entries = slices.Insert(c.entries, 0, x.entries[position-1])
			x.entries[position-1] = sibling.entries[last]
			sibling.entries = sibling.entries[:last]
			if len(sibling.children) != 0 {
				last := len(sibling.children) - 1
				c.children = slices.Insert(c.children, 0, sibling.children[last])
				sibling.children = sibling.children[:last]
			}
			t.borrows++
			tr.emit("STEP 3a-left page=%d child=%d from=%d keys=%s", page, child, left, c.notation())
		case right >= 0 && len(t.pages[right].entries) >= t.degree:
			*cases = append(*cases, "3a-right")
			sibling := t.pages[right]
			c.entries = append(c.entries, x.entries[position])
			x.entries[position] = sibling.entries[0]
			sibling.entries = slices.Delete(sibling.entries, 0, 1)
			if len(sibling.children) != 0 {
				c.children = append(c.children, sibling.children[0])
				sibling.children = slices.Delete(sibling.children, 0, 1)
			}
			t.borrows++
			tr.emit("STEP 3a-right page=%d child=%d from=%d keys=%s", page, child, right, c.notation())
		case left >= 0:
			*cases = append(*cases, "3b-left")
			child = t.merge(page, position-1, "3b-left", tr)
		default:
			*cases = append(*cases, "3b-right")
			child = t.merge(page, position, "3b-right", tr)
		}
	}
	t.removeAt(child, key, cases, tr)
}

func (t *tree) scan(low, high int) ([]entry, int) {
	var entries []entry
	visits := 0
	var visit func(int)
	visit = func(page int) {
		visits++
		n := t.pages[page]
		for j := 0; j <= len(n.entries); j++ {
			if len(n.children) != 0 && (j == 0 || n.entries[j-1].key < high) && (j == len(n.entries) || n.entries[j].key > low) {
				visit(n.children[j])
			}
			if j < len(n.entries) && low <= n.entries[j].key && n.entries[j].key <= high {
				entries = append(entries, n.entries[j])
			}
		}
	}
	visit(t.root)
	return entries, visits
}

func (t *tree) dump() string {
	var tokens []string
	var visit func(int)
	visit = func(page int) {
		n := t.pages[page]
		tokens = append(tokens, "(")
		for j := 0; j <= len(n.entries); j++ {
			if len(n.children) != 0 {
				visit(n.children[j])
			}
			if j < len(n.entries) {
				tokens = append(tokens, n.entries[j].String())
			}
		}
		tokens = append(tokens, ")")
	}
	visit(t.root)
	return strings.Join(tokens, " ")
}

func (t *tree) compact() {
	source := t.entries()
	var children []int
	var built []*node
	oldRoot := 0
	for {
		groups := (len(source) + 2*t.degree) / (2 * t.degree)
		keys := len(source) - (groups - 1)
		base, extra := keys/groups, keys%groups
		position, childPosition := 0, 0
		var separators []entry
		var level []int
		for j := range groups {
			count := base
			if j < extra {
				count++
			}
			n := &node{entries: slices.Clone(source[position : position+count])}
			position += count
			if len(children) != 0 {
				n.children = slices.Clone(children[childPosition : childPosition+count+1])
				childPosition += count + 1
			}
			level = append(level, len(built))
			built = append(built, n)
			if j+1 < groups {
				separators = append(separators, source[position])
				position++
			}
		}
		if groups == 1 {
			oldRoot = level[0]
			break
		}
		source, children = separators, level
	}
	t.pages = make(map[int]*node)
	var renumber func(int) int
	renumber = func(old int) int {
		page := len(t.pages)
		n := &node{entries: built[old].entries}
		t.pages[page] = n
		for _, child := range built[old].children {
			n.children = append(n.children, renumber(child))
		}
		return page
	}
	t.root = renumber(oldRoot)
	t.splits, t.merges, t.borrows = 0, 0, 0
}

type cursorKind int

const (
	unset cursorKind = iota
	atKey
	begin
	end
)

type cursor struct {
	kind cursorKind
	key  int
}

type workbench struct {
	index, saved *tree
	cursor       cursor
	trace        bool
}

func findEntry(entries []entry, last bool, accepts func(entry) bool) *entry {
	for step := range len(entries) {
		i := step
		if last {
			i = len(entries) - 1 - step
		}
		if accepts(entries[i]) {
			return &entries[i]
		}
	}
	return nil
}

func display(e *entry, fallback string) string {
	if e == nil {
		return fallback
	}
	return e.String()
}

func (w *workbench) process(line string) ([]string, error) {
	words := strings.Split(line, " ")
	command := words[0]
	if command == "TRACE" {
		w.trace = words[1] == "ON"
		return []string{"TRACE " + words[1]}, nil
	}
	first, second := 0, 0
	if len(words) > 1 {
		first = number(words[1])
	}
	ranged := command == "DELRANGE" || command == "RANGE" || command == "COUNT"
	if ranged {
		second = number(words[2])
	}
	if command == "CREATE" || command == "LOAD" {
		if first < 2 || first > 5 {
			return nil, fmt.Errorf("BAD DEGREE %d", first)
		}
		t := newTree(first)
		result := fmt.Sprintf("CREATE t=%d", first)
		if command == "LOAD" {
			loaded, err := loadTree(first, words[2:])
			if err != nil {
				return nil, err
			}
			t = loaded
			result = fmt.Sprintf("LOAD t=%d nodes=%d keys=%d %s", first, len(t.pages), len(t.entries()), t.status())
		}
		w.index, w.cursor = t, cursor{}
		return []string{result}, nil
	}
	t := w.index
	if t == nil {
		return nil, errors.New("NO INDEX")
	}
	switch command {
	case "INSERT", "BULKLOAD", "DELETE", "DELRANGE", "RANGE", "COUNT", "MIN", "MAX", "FLOOR", "CEIL", "RANK", "SELECT", "SEEK", "NEXT", "PREV", "HEIGHT", "COMPACT":
		if t.violation() != "" {
			return nil, errors.New("DAMAGED")
		}
	}
	entries := t.entries()
	if ranged && first > second {
		return nil, fmt.Errorf("BAD RANGE %d %d", first, second)
	}
	if command == "SELECT" && (first < 1 || first > len(entries)) {
		return nil, fmt.Errorf("BAD POSITION %d", first)
	}
	if (command == "NEXT" || command == "PREV") && w.cursor.kind == unset {
		return nil, errors.New("NO CURSOR")
	}
	if command == "RESTORE" && w.saved == nil {
		return nil, errors.New("NO SAVE")
	}
	var output []string
	tr := &trace{enabled: w.trace && (command == "INSERT" || command == "DELETE")}
	switch command {
	case "INSERT":
		before, splits := copyPages(t.pages), t.splits
		old, updated := t.upsert(entry{first, words[2]}, tr)
		writes, _ := t.changes(before)
		output = append(output, tr.lines...)
		if updated {
			output = append(output, fmt.Sprintf("INSERT %d UPDATED old=%s writes=%d", first, old, writes))
		} else {
			output = append(output, fmt.Sprintf("INSERT %d NEW splits=%d height=%d writes=%d", first, t.splits-splits, t.height(), writes))
		}
	case "BULKLOAD":
		before, splits := copyPages(t.pages), t.splits
		added, updated := 0, 0
		for i := 1; i < len(words); i += 2 {
			if _, replaced := t.upsert(entry{number(words[i]), words[i+1]}, tr); replaced {
				updated++
			} else {
				added++
			}
		}
		writes, _ := t.changes(before)
		output = append(output, fmt.Sprintf("BULKLOAD pairs=%d new=%d updated=%d splits=%d height=%d writes=%d", (len(words)-1)/2, added, updated, t.splits-splits, t.height(), writes))
	case "DELETE":
		found := t.search(first)
		if !found.found {
			output = append(output, fmt.Sprintf("DELETE %d NOT FOUND", first))
			break
		}
		value := t.pages[found.page].entries[found.position].value
		before := copyPages(t.pages)
		var cases []string
		t.removeAt(t.root, first, &cases, tr)
		writes, frees := t.changes(before)
		output = append(output, tr.lines...)
		output = append(output, fmt.Sprintf("DELETE %d REMOVED value=%s cases=%s height=%d writes=%d frees=%d", first, value, strings.Join(cases, ","), t.height(), writes, frees))
	case "DELRANGE":
		before := copyPages(t.pages)
		merges, borrows, removed := t.merges, t.borrows, 0
		for _, e := range entries {
			if first <= e.key && e.key <= second {
				var cases []string
				t.removeAt(t.root, e.key, &cases, tr)
				removed++
			}
		}
		writes, frees := t.changes(before)
		output = append(output, fmt.Sprintf("DELRANGE %d %d removed=%d merges=%d borrows=%d height=%d writes=%d frees=%d", first, second, removed, t.merges-merges, t.borrows-borrows, t.height(), writes, frees))
	case "GET":
		found := t.search(first)
		result := "NOT FOUND"
		if found.found {
			result = "FOUND value=" + t.pages[found.page].entries[found.position].value
		}
		output = append(output, fmt.Sprintf("GET %d %s path=%s", first, result, strings.Join(found.path, " -> ")))
	case "RANGE", "COUNT":
		found, visits := t.scan(first, second)
		result := fmt.Sprintf("%s %d %d count=%d visited=%d", command, first, second, len(found), visits)
		if command == "RANGE" {
			for _, e := range found {
				result += " " + e.String()
			}
		}
		output = append(output, result)
	case "MIN", "MAX":
		e := findEntry(entries, command == "MAX", func(entry) bool { return true })
		output = append(output, command+" "+display(e, "EMPTY"))
	case "FLOOR", "CEIL":
		e := findEntry(entries, command == "FLOOR", func(e entry) bool {
			if command == "FLOOR" {
				return e.key <= first
			}
			return e.key >= first
		})
		output = append(output, fmt.Sprintf("%s %d %s", command, first, display(e, "NONE")))
	case "RANK":
		rank := 0
		for _, e := range entries {
			if e.key < first {
				rank++
			}
		}
		output = append(output, fmt.Sprintf("RANK %d %d", first, rank))
	case "SELECT":
		output = append(output, fmt.Sprintf("SELECT %d %s", first, entries[first-1]))
	case "SEEK":
		e := findEntry(entries, false, func(e entry) bool { return e.key >= first })
		w.cursor = cursor{kind: end}
		if e != nil {
			w.cursor = cursor{atKey, e.key}
		}
		output = append(output, fmt.Sprintf("SEEK %d %s", first, display(e, "END")))
	case "NEXT", "PREV":
		var e *entry
		if command == "NEXT" {
			if w.cursor.kind == begin || w.cursor.kind == atKey {
				e = findEntry(entries, false, func(e entry) bool { return w.cursor.kind == begin || e.key > w.cursor.key })
			}
			w.cursor = cursor{kind: end}
			output = append(output, "NEXT "+display(e, "END"))
		} else {
			if w.cursor.kind == end || w.cursor.kind == atKey {
				e = findEntry(entries, true, func(e entry) bool { return w.cursor.kind == end || e.key < w.cursor.key })
			}
			w.cursor = cursor{kind: begin}
			output = append(output, "PREV "+display(e, "BEGIN"))
		}
		if e != nil {
			w.cursor = cursor{atKey, e.key}
		}
	case "PRINT":
		level := []int{t.root}
		for depth := 0; len(level) != 0; depth++ {
			result := fmt.Sprintf("LEVEL %d", depth)
			var next []int
			for _, page := range level {
				n := t.pages[page]
				result += " " + n.notation()
				next = append(next, n.children...)
			}
			output = append(output, result)
			level = next
		}
	case "PAGES":
		pages := make([]int, 0, len(t.pages))
		for page := range t.pages {
			pages = append(pages, page)
		}
		slices.Sort(pages)
		for _, page := range pages {
			n := t.pages[page]
			children := make([]string, len(n.children))
			for j, child := range n.children {
				children[j] = strconv.Itoa(child)
			}
			kids := "-"
			if len(children) != 0 {
				kids = strings.Join(children, ",")
			}
			output = append(output, fmt.Sprintf("PAGE %d %s kids=%s", page, n.notation(), kids))
		}
	case "DUMP":
		output = append(output, fmt.Sprintf("DUMP %d %s", t.degree, t.dump()))
	case "HEIGHT":
		output = append(output, fmt.Sprintf("HEIGHT %d", t.height()))
	case "STATS":
		leaves := 0
		for _, n := range t.pages {
			if len(n.children) == 0 {
				leaves++
			}
		}
		fill := 100 * len(entries) / ((2*t.degree - 1) * len(t.pages))
		output = append(output, fmt.Sprintf("STATS t=%d nodes=%d leaves=%d keys=%d fill=%d%% splits=%d merges=%d borrows=%d", t.degree, len(t.pages), leaves, len(entries), fill, t.splits, t.merges, t.borrows))
	case "VERIFY":
		result := "VERIFY OK"
		if problem := t.violation(); problem != "" {
			result = "VERIFY FAIL " + problem
		}
		output = append(output, result)
	case "REBUILD":
		t = newTree(t.degree)
		for _, e := range entries {
			t.upsert(e, tr)
		}
		output = append(output, fmt.Sprintf("REBUILD entries=%d keys=%d nodes=%d splits=%d height=%d", len(entries), len(t.entries()), len(t.pages), t.splits, t.height()))
	case "COMPACT":
		nodes := len(t.pages)
		t.compact()
		output = append(output, fmt.Sprintf("COMPACT nodes=%d->%d height=%d", nodes, len(t.pages), t.height()))
	case "SAVE":
		w.saved = t.clone()
		output = append(output, fmt.Sprintf("SAVE nodes=%d keys=%d %s", len(t.pages), len(entries), t.status()))
	case "RESTORE":
		t = w.saved.clone()
		output = append(output, fmt.Sprintf("RESTORE nodes=%d keys=%d %s", len(t.pages), len(t.entries()), t.status()))
	}
	w.index = t
	return output, nil
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	count := number(scanner.Text())
	w := &workbench{}
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	for range count {
		scanner.Scan()
		lines, err := w.process(scanner.Text())
		if err != nil {
			fmt.Fprintf(output, "ERROR %s\n", err)
		} else {
			for _, line := range lines {
				fmt.Fprintln(output, line)
			}
		}
	}
}
