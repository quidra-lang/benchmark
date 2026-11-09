package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var issueTypes = []string{"BUG", "TASK", "STORY"}
var priorities = []string{"LOW", "MEDIUM", "HIGH", "CRITICAL"}
var workflows = map[string][]string{
	"BUG":   {"OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED", "CLOSED", "REOPENED"},
	"TASK":  {"OPEN", "IN_PROGRESS", "DONE"},
	"STORY": {"BACKLOG", "READY", "IN_PROGRESS", "REVIEW", "DONE"},
}
var transitions = map[string][]string{
	"BUG": {
		"OPEN TRIAGED", "TRIAGED IN_PROGRESS", "IN_PROGRESS REVIEW", "REVIEW IN_PROGRESS",
		"REVIEW RESOLVED", "RESOLVED CLOSED", "RESOLVED REOPENED", "CLOSED REOPENED", "REOPENED IN_PROGRESS",
	},
	"TASK":  {"OPEN IN_PROGRESS", "IN_PROGRESS OPEN", "IN_PROGRESS DONE"},
	"STORY": {"BACKLOG READY", "READY BACKLOG", "READY IN_PROGRESS", "IN_PROGRESS REVIEW", "REVIEW IN_PROGRESS", "REVIEW DONE"},
}
var estimates = map[int]bool{0: true, 1: true, 2: true, 3: true, 5: true, 8: true, 13: true, 21: true}
var equalityOperators = []string{"=", "!="}
var orderOperators = []string{"=", "!=", "<", "<=", ">", ">="}
var fieldOperators = map[string][]string{
	"id":       orderOperators,
	"type":     equalityOperators,
	"status":   equalityOperators,
	"priority": orderOperators,
	"assignee": equalityOperators,
	"reviewer": equalityOperators,
	"estimate": orderOperators,
	"sprint":   equalityOperators,
	"comments": orderOperators,
	"blocked":  equalityOperators,
	"done":     equalityOperators,
	"title":    {"~"},
}

func has(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

func number(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func yesNo(value bool) string {
	if value {
		return "yes"
	}
	return "no"
}

func estimateText(value int) string {
	if value < 0 {
		return "-"
	}
	return strconv.Itoa(value)
}

func sortedNumbers(values map[int]bool) []int {
	result := make([]int, 0, len(values))
	for id := range values {
		result = append(result, id)
	}
	sort.Ints(result)
	return result
}

func numberList(values map[int]bool) string {
	if len(values) == 0 {
		return "-"
	}
	parts := make([]string, 0, len(values))
	for _, id := range sortedNumbers(values) {
		parts = append(parts, strconv.Itoa(id))
	}
	return strings.Join(parts, ",")
}

type Issue struct {
	ID                        int
	Kind, Priority, Title     string
	State, Assignee, Reviewer string
	Estimate                  int
	Sprint                    string
	Comments                  int
	Blocks, Blockers          map[int]bool
	Duplicate                 int
	Duplicates                map[int]bool
	History                   []string
}

func (i *Issue) done() bool {
	return i.State == "RESOLVED" || i.State == "CLOSED" || i.State == "DONE"
}

func (i *Issue) points() int {
	if i.Estimate < 0 {
		return 0
	}
	return i.Estimate
}

func (i *Issue) level() int {
	for level, priority := range priorities {
		if i.Priority == priority {
			return level
		}
	}
	return -1
}

type Sprint struct {
	Name, Phase          string
	Start, End, Velocity int
	Records              map[int]int
}

type Tracker struct {
	Day         int
	Users       map[string]bool
	Issues      map[int]*Issue
	Sprints     map[string]*Sprint
	SprintOrder []string
}

func newTracker() *Tracker {
	return &Tracker{
		Day:     1,
		Users:   make(map[string]bool),
		Issues:  make(map[int]*Issue),
		Sprints: make(map[string]*Sprint),
	}
}

func (t *Tracker) requireIssue(text string) (*Issue, error) {
	issue := t.Issues[number(text)]
	if issue == nil {
		return nil, fmt.Errorf("unknown issue")
	}
	return issue, nil
}

func (t *Tracker) requireUser(user string) error {
	if user != "-" && !t.Users[user] {
		return fmt.Errorf("unknown user")
	}
	return nil
}

func (t *Tracker) requireSprint(name string) (*Sprint, error) {
	sprint := t.Sprints[name]
	if sprint == nil {
		return nil, fmt.Errorf("unknown sprint")
	}
	return sprint, nil
}

func (t *Tracker) orderedIssues() []*Issue {
	issues := make([]*Issue, 0, len(t.Issues))
	for _, issue := range t.Issues {
		issues = append(issues, issue)
	}
	sort.Slice(issues, func(i, j int) bool {
		return issues[i].ID < issues[j].ID
	})
	return issues
}

func (t *Tracker) unfinishedBlockers(issue *Issue) []int {
	var blockers []int
	for _, id := range sortedNumbers(issue.Blockers) {
		if !t.Issues[id].done() {
			blockers = append(blockers, id)
		}
	}
	return blockers
}

func (t *Tracker) blocked(issue *Issue) bool {
	return !issue.done() && len(t.unfinishedBlockers(issue)) > 0
}

func (t *Tracker) wipCount(user string) int {
	count := 0
	for _, issue := range t.Issues {
		if issue.Assignee == user && issue.State == "IN_PROGRESS" {
			count++
		}
	}
	return count
}

func (t *Tracker) activeSprint() *Sprint {
	for _, name := range t.SprintOrder {
		if t.Sprints[name].Phase == "ACTIVE" {
			return t.Sprints[name]
		}
	}
	return nil
}

func (t *Tracker) members(sprint *Sprint) []*Issue {
	var result []*Issue
	for _, issue := range t.orderedIssues() {
		if issue.Sprint == sprint.Name {
			result = append(result, issue)
		}
	}
	return result
}

func (t *Tracker) remaining(sprint *Sprint) int {
	points := 0
	for _, issue := range t.members(sprint) {
		if !issue.done() {
			points += issue.points()
		}
	}
	return points
}

func (t *Tracker) summary(sprint *Sprint) string {
	members := t.members(sprint)
	points := 0
	for _, issue := range members {
		points += issue.points()
	}
	return fmt.Sprintf("issues %d points %d", len(members), points)
}

func (t *Tracker) record(issue *Issue, content string) {
	issue.History = append(issue.History, fmt.Sprintf("day %d %s", t.Day, content))
}

func (t *Tracker) blockedStates(ids map[int]bool) map[int]bool {
	result := make(map[int]bool)
	for id := range ids {
		result[id] = t.blocked(t.Issues[id])
	}
	return result
}

func (t *Tracker) notifications(before map[int]bool) []string {
	var lines []string
	for _, id := range sortedNumbers(before) {
		after := t.blocked(t.Issues[id])
		if after != before[id] {
			word := "UNBLOCKED"
			if after {
				word = "BLOCKED"
			}
			lines = append(lines, fmt.Sprintf("%s %d", word, id))
		}
	}
	return lines
}

func (t *Tracker) changeState(issue *Issue, target string) []string {
	before := t.blockedStates(issue.Blocks)
	previous := issue.State
	t.record(issue, "MOVE "+previous+" "+target)
	issue.State = target
	return append([]string{fmt.Sprintf("MOVE %d %s %s", issue.ID, previous, target)}, t.notifications(before)...)
}

func (t *Tracker) reaches(start, goal int) bool {
	pending := []int{start}
	visited := make(map[int]bool)
	for len(pending) > 0 {
		id := pending[len(pending)-1]
		pending = pending[:len(pending)-1]
		if id == goal {
			return true
		}
		if visited[id] {
			continue
		}
		visited[id] = true
		for next := range t.Issues[id].Blocks {
			pending = append(pending, next)
		}
	}
	return false
}

type QueryNode interface {
	matches(*Tracker, *Issue) bool
}

type Condition struct {
	Field, Operator, Text string
	Number                int
	None                  bool
}

type NotNode struct {
	Child QueryNode
}

func (n *NotNode) matches(t *Tracker, issue *Issue) bool {
	return !n.Child.matches(t, issue)
}

type BinaryNode struct {
	Operator    string
	Left, Right QueryNode
}

func (n *BinaryNode) matches(t *Tracker, issue *Issue) bool {
	if n.Operator == "AND" {
		return n.Left.matches(t, issue) && n.Right.matches(t, issue)
	}
	return n.Left.matches(t, issue) || n.Right.matches(t, issue)
}

func (c *Condition) matches(t *Tracker, issue *Issue) bool {
	var actualText string
	actualNumber := 0
	numeric, none := false, false
	switch c.Field {
	case "id":
		actualNumber, numeric = issue.ID, true
	case "type":
		actualText = issue.Kind
	case "status":
		actualText = issue.State
	case "priority":
		actualNumber, numeric = issue.level(), true
	case "assignee":
		actualText, none = issue.Assignee, issue.Assignee == "-"
	case "reviewer":
		actualText, none = issue.Reviewer, issue.Reviewer == "-"
	case "estimate":
		actualNumber, numeric, none = issue.Estimate, true, issue.Estimate < 0
	case "sprint":
		actualText, none = issue.Sprint, issue.Sprint == "-"
	case "comments":
		actualNumber, numeric = issue.Comments, true
	case "blocked":
		actualText = yesNo(t.blocked(issue))
	case "done":
		actualText = yesNo(issue.done())
	case "title":
		return strings.Contains(strings.ToLower(issue.Title), c.Text)
	}
	equal := none && c.None
	if !none && !c.None {
		if numeric {
			equal = actualNumber == c.Number
		} else {
			equal = actualText == c.Text
		}
	}
	switch c.Operator {
	case "=":
		return equal
	case "!=":
		return !equal
	}
	if none {
		return false
	}
	switch c.Operator {
	case "<":
		return actualNumber < c.Number
	case "<=":
		return actualNumber <= c.Number
	case ">":
		return actualNumber > c.Number
	default:
		return actualNumber >= c.Number
	}
}

func digits(text string) bool {
	if len(text) < 1 || len(text) > 6 {
		return false
	}
	for i := range len(text) {
		if text[i] < '0' || text[i] > '9' {
			return false
		}
	}
	return true
}

func (t *Tracker) condition(token string) (*Condition, error) {
	position := 0
	for position < len(token) && token[position] >= 'a' && token[position] <= 'z' {
		position++
	}
	field, rest := token[:position], token[position:]
	operator := ""
	for _, candidate := range []string{">=", "<=", "!=", "=", "<", ">", "~"} {
		if strings.HasPrefix(rest, candidate) {
			operator = candidate
			break
		}
	}
	value := rest[len(operator):]
	if field == "" || operator == "" || value == "" {
		return nil, fmt.Errorf("syntax near %s", token)
	}
	operators, known := fieldOperators[field]
	if !known {
		return nil, fmt.Errorf("unknown field %s", field)
	}
	if !has(operators, operator) {
		return nil, fmt.Errorf("bad operator %s", token)
	}
	c := &Condition{Field: field, Operator: operator, Text: value}
	valid := false
	switch field {
	case "id", "comments", "estimate":
		if digits(value) {
			c.Number = number(value)
			valid = true
		} else if field == "estimate" && value == "-" && has(equalityOperators, operator) {
			c.None, valid = true, true
		}
	case "priority":
		for level, priority := range priorities {
			if value == priority {
				c.Number, valid = level, true
			}
		}
	case "type":
		valid = has(issueTypes, value)
	case "status":
		for _, states := range workflows {
			valid = valid || has(states, value)
		}
	case "assignee", "reviewer":
		c.None = value == "-"
		valid = c.None || t.Users[value]
	case "sprint":
		c.None = value == "-"
		valid = c.None || t.Sprints[value] != nil
	case "blocked", "done":
		valid = value == "yes" || value == "no"
	case "title":
		c.Text, valid = strings.ToLower(value), true
	}
	if !valid {
		return nil, fmt.Errorf("bad value %s", token)
	}
	return c, nil
}

func tokenize(query string) []string {
	var tokens []string
	start := 0
	for position := 0; position < len(query); position++ {
		c := query[position]
		if c == ' ' || c == '(' || c == ')' {
			if start < position {
				tokens = append(tokens, query[start:position])
			}
			if c != ' ' {
				tokens = append(tokens, string(c))
			}
			start = position + 1
		}
	}
	if start < len(query) {
		tokens = append(tokens, query[start:])
	}
	return tokens
}

type QueryParser struct {
	Tokens     []string
	Conditions []QueryNode
	Position   int
}

func (p *QueryParser) accept(token string) bool {
	if p.Position < len(p.Tokens) && p.Tokens[p.Position] == token {
		p.Position++
		return true
	}
	return false
}

func (p *QueryParser) factor() QueryNode {
	if p.accept("NOT") {
		return &NotNode{p.factor()}
	}
	if p.accept("(") {
		node := p.expression()
		p.accept(")")
		return node
	}
	node := p.Conditions[p.Position]
	p.Position++
	return node
}

func (p *QueryParser) term() QueryNode {
	node := p.factor()
	for p.accept("AND") {
		node = &BinaryNode{"AND", node, p.factor()}
	}
	return node
}

func (p *QueryParser) expression() QueryNode {
	node := p.term()
	for p.accept("OR") {
		node = &BinaryNode{"OR", node, p.term()}
	}
	return node
}

func (t *Tracker) parseQuery(query string) (QueryNode, error) {
	tokens := tokenize(query)
	conditions := make([]QueryNode, len(tokens))
	operand, depth := true, 0
	for position, token := range tokens {
		if operand {
			switch token {
			case "NOT":
			case "(":
				depth++
			case "AND", "OR", ")":
				return nil, fmt.Errorf("syntax near %s", token)
			default:
				condition, err := t.condition(token)
				if err != nil {
					return nil, err
				}
				conditions[position] = condition
				operand = false
			}
		} else {
			switch token {
			case "AND", "OR":
				operand = true
			case ")":
				if depth == 0 {
					return nil, fmt.Errorf("syntax near %s", token)
				}
				depth--
			default:
				return nil, fmt.Errorf("syntax near %s", token)
			}
		}
	}
	if operand || depth != 0 {
		return nil, fmt.Errorf("syntax at end")
	}
	parser := &QueryParser{Tokens: tokens, Conditions: conditions}
	return parser.expression(), nil
}

func (t *Tracker) processSprint(args []string) ([]string, error) {
	command, name := args[0], args[1]
	if command == "NEW" {
		if t.Sprints[name] != nil {
			return nil, fmt.Errorf("sprint exists")
		}
		t.Sprints[name] = &Sprint{Name: name, Phase: "PLANNED", Records: make(map[int]int)}
		t.SprintOrder = append(t.SprintOrder, name)
		return []string{"SPRINT NEW " + name}, nil
	}
	sprint, err := t.requireSprint(name)
	if err != nil {
		return nil, err
	}
	if command == "ADD" || command == "REMOVE" {
		issue, err := t.requireIssue(args[2])
		if err != nil {
			return nil, err
		}
		if sprint.Phase == "ENDED" {
			return nil, fmt.Errorf("sprint ended")
		}
		if command == "ADD" {
			if issue.done() {
				return nil, fmt.Errorf("issue done")
			}
			if issue.Sprint != "-" && t.Sprints[issue.Sprint].Phase != "ENDED" {
				return nil, fmt.Errorf("in sprint %s", issue.Sprint)
			}
			if issue.State == "BACKLOG" {
				return nil, fmt.Errorf("not ready")
			}
			issue.Sprint = name
		} else {
			if issue.Sprint != name {
				return nil, fmt.Errorf("not in sprint")
			}
			if issue.done() {
				return nil, fmt.Errorf("issue done")
			}
			issue.Sprint = "-"
		}
		t.record(issue, "SPRINT "+command+" "+name)
		return []string{fmt.Sprintf("SPRINT %s %s %d %s", command, name, issue.ID, t.summary(sprint))}, nil
	}
	if command == "START" {
		if sprint.Phase != "PLANNED" {
			return nil, fmt.Errorf("sprint not planned")
		}
		if active := t.activeSprint(); active != nil {
			return nil, fmt.Errorf("sprint active %s", active.Name)
		}
		if len(t.members(sprint)) == 0 {
			return nil, fmt.Errorf("sprint empty")
		}
		sprint.Phase, sprint.Start = "ACTIVE", t.Day
		sprint.Records[t.Day] = t.remaining(sprint)
		return []string{fmt.Sprintf("SPRINT START %s day %d %s remaining %d", name, t.Day, t.summary(sprint), t.remaining(sprint))}, nil
	}
	if sprint.Phase != "ACTIVE" {
		return nil, fmt.Errorf("sprint not active")
	}
	sprint.Records[t.Day] = t.remaining(sprint)
	var finished, returned []*Issue
	for _, issue := range t.members(sprint) {
		if issue.done() {
			finished = append(finished, issue)
		} else {
			returned = append(returned, issue)
		}
	}
	for _, issue := range finished {
		sprint.Velocity += issue.points()
	}
	sprint.Phase, sprint.End = "ENDED", t.Day
	lines := []string{fmt.Sprintf("SPRINT END %s day %d velocity %d done %d returned %d", name, t.Day, sprint.Velocity, len(finished), len(returned))}
	for _, issue := range returned {
		issue.Sprint = "-"
		t.record(issue, "SPRINT RETURN "+name)
		lines = append(lines, fmt.Sprintf("RETURNED %d", issue.ID))
	}
	return lines, nil
}

func (t *Tracker) process(line string) ([]string, error) {
	words := strings.Split(line, " ")
	command, args := words[0], words[1:]
	switch command {
	case "DAY":
		day := number(args[0])
		if day < t.Day {
			return nil, fmt.Errorf("day backwards")
		}
		t.Day = day
		return []string{fmt.Sprintf("DAY %d", day)}, nil
	case "USER":
		user := args[0]
		if t.Users[user] {
			return nil, fmt.Errorf("user exists")
		}
		t.Users[user] = true
		return []string{"USER " + user}, nil
	case "CREATE":
		id, kind, priority := number(args[0]), args[1], args[2]
		if t.Issues[id] != nil {
			return nil, fmt.Errorf("issue exists")
		}
		if !has(issueTypes, kind) {
			return nil, fmt.Errorf("bad type")
		}
		if !has(priorities, priority) {
			return nil, fmt.Errorf("bad priority")
		}
		issue := &Issue{
			ID: id, Kind: kind, Priority: priority, Title: strings.Join(args[3:], " "),
			State: workflows[kind][0], Assignee: "-", Reviewer: "-", Estimate: -1, Sprint: "-",
			Blocks: make(map[int]bool), Blockers: make(map[int]bool), Duplicates: make(map[int]bool),
		}
		t.Issues[id] = issue
		t.record(issue, "CREATE "+kind+" "+priority)
		return []string{fmt.Sprintf("CREATE %d %s %s %s", id, kind, priority, issue.State)}, nil
	case "SPRINT":
		return t.processSprint(args)
	case "QUERY":
		tree, err := t.parseQuery(strings.Join(args, " "))
		if err != nil {
			return nil, err
		}
		var found []*Issue
		for _, issue := range t.Issues {
			if tree.matches(t, issue) {
				found = append(found, issue)
			}
		}
		sort.Slice(found, func(i, j int) bool {
			return found[i].level() > found[j].level() || (found[i].level() == found[j].level() && found[i].ID < found[j].ID)
		})
		lines := []string{fmt.Sprintf("QUERY %d", len(found))}
		for _, issue := range found {
			lines = append(lines, fmt.Sprintf("%d %s %s %s %s %s %s", issue.ID, issue.Kind, issue.Priority, issue.State, issue.Assignee, estimateText(issue.Estimate), issue.Title))
		}
		return lines, nil
	case "BOARD":
		lines := []string{"BOARD"}
		for _, kind := range issueTypes {
			parts := []string{kind}
			for _, state := range workflows[kind] {
				count := 0
				for _, issue := range t.Issues {
					if issue.Kind == kind && issue.State == state {
						count++
					}
				}
				parts = append(parts, state, strconv.Itoa(count))
			}
			lines = append(lines, strings.Join(parts, " "))
		}
		finished := 0
		for _, issue := range t.Issues {
			if issue.done() {
				finished++
			}
		}
		lines = append(lines, fmt.Sprintf("TOTAL %d open %d done %d", len(t.Issues), len(t.Issues)-finished, finished))
		return lines, nil
	case "WORKLOAD":
		var users []string
		for user := range t.Users {
			users = append(users, user)
		}
		sort.Strings(users)
		lines := []string{fmt.Sprintf("WORKLOAD %d", len(users))}
		for _, user := range users {
			assigned, progress, review, reviewing, points := 0, 0, 0, 0, 0
			for _, issue := range t.Issues {
				if issue.Assignee == user && !issue.done() {
					assigned++
					points += issue.points()
					if issue.State == "IN_PROGRESS" {
						progress++
					}
					if issue.State == "REVIEW" {
						review++
					}
				}
				if issue.Reviewer == user && issue.State == "REVIEW" {
					reviewing++
				}
			}
			lines = append(lines, fmt.Sprintf("%s assigned %d in_progress %d review %d reviewing %d points %d", user, assigned, progress, review, reviewing, points))
		}
		return lines, nil
	case "SPRINTS":
		lines := []string{fmt.Sprintf("SPRINTS %d", len(t.Sprints))}
		for _, name := range t.SprintOrder {
			s := t.Sprints[name]
			switch s.Phase {
			case "PLANNED":
				lines = append(lines, fmt.Sprintf("%s PLANNED %s", name, t.summary(s)))
			case "ACTIVE":
				lines = append(lines, fmt.Sprintf("%s ACTIVE start %d %s remaining %d", name, s.Start, t.summary(s), t.remaining(s)))
			case "ENDED":
				lines = append(lines, fmt.Sprintf("%s ENDED start %d end %d velocity %d", name, s.Start, s.End, s.Velocity))
			}
		}
		return lines, nil
	case "BURNDOWN":
		sprint, err := t.requireSprint(args[0])
		if err != nil {
			return nil, err
		}
		if sprint.Phase == "PLANNED" {
			return nil, fmt.Errorf("sprint not started")
		}
		last := sprint.End
		if sprint.Phase == "ACTIVE" {
			last = t.Day
		}
		lines := []string{fmt.Sprintf("BURNDOWN %s %s days %d", sprint.Name, sprint.Phase, last-sprint.Start+1)}
		value := 0
		for day := sprint.Start; day <= last; day++ {
			if recorded, ok := sprint.Records[day]; ok {
				value = recorded
			}
			lines = append(lines, fmt.Sprintf("day %d %d", day, value))
		}
		return lines, nil
	case "LINK", "UNLINK":
		relation := args[1]
		if relation != "BLOCKS" && (command == "UNLINK" || relation != "DUPLICATES") {
			return nil, fmt.Errorf("bad link")
		}
		a, err := t.requireIssue(args[0])
		if err != nil {
			return nil, err
		}
		b, err := t.requireIssue(args[2])
		if err != nil {
			return nil, err
		}
		if command == "UNLINK" {
			if !a.Blocks[b.ID] {
				return nil, fmt.Errorf("no link")
			}
			before := map[int]bool{b.ID: t.blocked(b)}
			delete(a.Blocks, b.ID)
			delete(b.Blockers, a.ID)
			t.record(a, fmt.Sprintf("UNLINK BLOCKS %d", b.ID))
			t.record(b, fmt.Sprintf("UNLINK BLOCKED_BY %d", a.ID))
			return append([]string{fmt.Sprintf("UNLINK %d BLOCKS %d", a.ID, b.ID)}, t.notifications(before)...), nil
		}
		if a == b {
			return nil, fmt.Errorf("self link")
		}
		if relation == "BLOCKS" {
			if a.Blocks[b.ID] {
				return nil, fmt.Errorf("link exists")
			}
			if t.reaches(b.ID, a.ID) {
				return nil, fmt.Errorf("cycle")
			}
			if b.done() {
				return nil, fmt.Errorf("issue done")
			}
			before := map[int]bool{b.ID: t.blocked(b)}
			a.Blocks[b.ID], b.Blockers[a.ID] = true, true
			t.record(a, fmt.Sprintf("LINK BLOCKS %d", b.ID))
			t.record(b, fmt.Sprintf("LINK BLOCKED_BY %d", a.ID))
			return append([]string{fmt.Sprintf("LINK %d BLOCKS %d", a.ID, b.ID)}, t.notifications(before)...), nil
		}
		if a.Kind != b.Kind {
			return nil, fmt.Errorf("type mismatch")
		}
		if a.done() {
			return nil, fmt.Errorf("issue done")
		}
		if b.Duplicate != 0 {
			return nil, fmt.Errorf("target is duplicate")
		}
		a.Duplicate, b.Duplicates[a.ID] = b.ID, true
		t.record(a, fmt.Sprintf("LINK DUPLICATES %d", b.ID))
		t.record(b, fmt.Sprintf("LINK DUPLICATED_BY %d", a.ID))
		target := "DONE"
		if a.Kind == "BUG" {
			target = "CLOSED"
		}
		lines := append([]string{fmt.Sprintf("LINK %d DUPLICATES %d", a.ID, b.ID)}, t.changeState(a, target)...)
		if a.Sprint != "-" && t.Sprints[a.Sprint].Phase != "ENDED" {
			t.record(a, "SPRINT REMOVE "+a.Sprint)
			a.Sprint = "-"
		}
		return lines, nil
	}
	issue, err := t.requireIssue(args[0])
	if err != nil {
		return nil, err
	}
	switch command {
	case "SHOW":
		duplicate := "-"
		if issue.Duplicate != 0 {
			duplicate = strconv.Itoa(issue.Duplicate)
		}
		return []string{
			fmt.Sprintf("ISSUE %d %s %s %s blocked %s", issue.ID, issue.Kind, issue.Priority, issue.State, yesNo(t.blocked(issue))),
			"TITLE " + issue.Title,
			fmt.Sprintf("PEOPLE assignee %s reviewer %s", issue.Assignee, issue.Reviewer),
			fmt.Sprintf("PLAN estimate %s sprint %s comments %d", estimateText(issue.Estimate), issue.Sprint, issue.Comments),
			fmt.Sprintf("LINKS blocks %s blocked_by %s duplicate_of %s duplicated_by %s", numberList(issue.Blocks), numberList(issue.Blockers), duplicate, numberList(issue.Duplicates)),
		}, nil
	case "HISTORY":
		return append([]string{fmt.Sprintf("HISTORY %d %d", issue.ID, len(issue.History))}, issue.History...), nil
	case "COMMENT":
		if err := t.requireUser(args[1]); err != nil {
			return nil, err
		}
		issue.Comments++
		t.record(issue, "COMMENT "+args[1]+" "+strings.Join(args[2:], " "))
		return []string{fmt.Sprintf("COMMENT %d %d", issue.ID, issue.Comments)}, nil
	case "PRIORITY":
		target := args[1]
		if !has(priorities, target) {
			return nil, fmt.Errorf("bad priority")
		}
		if issue.done() {
			return nil, fmt.Errorf("issue done")
		}
		if target == issue.Priority {
			return nil, fmt.Errorf("no change")
		}
		previous := issue.Priority
		issue.Priority = target
		t.record(issue, "PRIORITY "+previous+" "+target)
		return []string{fmt.Sprintf("PRIORITY %d %s %s", issue.ID, previous, target)}, nil
	case "ASSIGN", "REVIEWER":
		target := args[1]
		if err := t.requireUser(target); err != nil {
			return nil, err
		}
		if issue.done() {
			return nil, fmt.Errorf("issue done")
		}
		current := issue.Reviewer
		if command == "ASSIGN" {
			current = issue.Assignee
		}
		if target == current {
			return nil, fmt.Errorf("no change")
		}
		if command == "ASSIGN" {
			if target == "-" && (issue.State == "IN_PROGRESS" || issue.State == "REVIEW") {
				return nil, fmt.Errorf("assignee required")
			}
			if issue.State == "IN_PROGRESS" && t.wipCount(target) >= 3 {
				return nil, fmt.Errorf("wip limit %s", target)
			}
			if issue.State == "REVIEW" && target == issue.Reviewer {
				return nil, fmt.Errorf("reviewer is assignee")
			}
			issue.Assignee = target
		} else {
			if target == "-" && issue.State == "REVIEW" {
				return nil, fmt.Errorf("reviewer required")
			}
			if issue.State == "REVIEW" && target == issue.Assignee {
				return nil, fmt.Errorf("reviewer is assignee")
			}
			issue.Reviewer = target
		}
		t.record(issue, command+" "+target)
		return []string{fmt.Sprintf("%s %d %s", command, issue.ID, target)}, nil
	case "ESTIMATE":
		value := number(args[1])
		if !estimates[value] {
			return nil, fmt.Errorf("bad estimate")
		}
		if issue.done() {
			return nil, fmt.Errorf("issue done")
		}
		if issue.Estimate == value {
			return nil, fmt.Errorf("no change")
		}
		previous := estimateText(issue.Estimate)
		issue.Estimate = value
		t.record(issue, fmt.Sprintf("ESTIMATE %s %d", previous, value))
		return []string{fmt.Sprintf("ESTIMATE %d %s %d", issue.ID, previous, value)}, nil
	case "MOVE":
		target := args[1]
		if issue.Duplicate != 0 {
			return nil, fmt.Errorf("duplicate of %d", issue.Duplicate)
		}
		if !has(workflows[issue.Kind], target) {
			return nil, fmt.Errorf("bad state")
		}
		if !has(transitions[issue.Kind], issue.State+" "+target) {
			return nil, fmt.Errorf("cannot move %s to %s", issue.State, target)
		}
		if target == "IN_PROGRESS" {
			active := t.activeSprint()
			if issue.Kind == "STORY" && (active == nil || issue.Sprint != active.Name) {
				return nil, fmt.Errorf("not in active sprint")
			}
			if issue.Assignee == "-" {
				return nil, fmt.Errorf("no assignee")
			}
			if t.wipCount(issue.Assignee) >= 3 {
				return nil, fmt.Errorf("wip limit %s", issue.Assignee)
			}
		}
		if target == "REVIEW" {
			if issue.Reviewer == "-" {
				return nil, fmt.Errorf("no reviewer")
			}
			if issue.Reviewer == issue.Assignee {
				return nil, fmt.Errorf("reviewer is assignee")
			}
		}
		if target == "DONE" || target == "RESOLVED" {
			if blockers := t.unfinishedBlockers(issue); len(blockers) > 0 {
				return nil, fmt.Errorf("blocked by %d", blockers[0])
			}
		}
		if target == "READY" && issue.Estimate < 0 {
			return nil, fmt.Errorf("no estimate")
		}
		return t.changeState(issue, target), nil
	}
	panic("unknown command")
}

func (t *Tracker) execute(line string) []string {
	lines, err := t.process(line)
	if err != nil {
		lines = []string{"ERROR " + err.Error()}
	}
	if active := t.activeSprint(); active != nil {
		active.Records[t.Day] = t.remaining(active)
	}
	return lines
}

func main() {
	in := bufio.NewScanner(os.Stdin)
	in.Scan()
	count := number(in.Text())
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	tracker := newTracker()
	for range count {
		in.Scan()
		for _, line := range tracker.execute(in.Text()) {
			fmt.Fprintln(out, line)
		}
	}
}
