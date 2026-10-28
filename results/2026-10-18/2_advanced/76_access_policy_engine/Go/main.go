package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Value struct {
	kind    string
	integer int
	text    string
	boolean bool
	bag     []string
}

func intValue(n int) Value       { return Value{kind: "integer", integer: n} }
func stringValue(s string) Value { return Value{kind: "string", text: s} }
func boolValue(b bool) Value     { return Value{kind: "boolean", boolean: b} }
func bagValue(a []string) Value  { return Value{kind: "bag", bag: a} }
func errorValue(s string) Value  { return Value{kind: "error", text: s} }
func (v Value) notation() string {
	switch v.kind {
	case "integer":
		return strconv.Itoa(v.integer)
	case "boolean":
		return strconv.FormatBool(v.boolean)
	case "bag":
		a := make([]string,
			len(v.bag))
		for i, s := range v.bag {
			a[i] = "\"" + s + "\""
		}
		return "[" + strings.Join(a, ",") + "]"
	default:
		return "\"" + v.text + "\""
	}
}
func parseValue(s string) Value {
	if s == "true" || s == "false" {
		return boolValue(s == "true")
	}
	if s[0] == '[' {
		if len(s) == 2 {
			return bagValue(nil)
		}
		return bagValue(strings.Split(s[1:len(s)-1],
			","))
	}
	if s[0] == '-' || s[0] >= '0' && s[0] <= '9' {
		return intValue(number(s))
	}
	return stringValue(s)
}
func number(s string) int { v, _ := strconv.Atoi(s); return v }
func readLines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(b) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(b),
		"\n"), "\n")
}
func evaluateExpr(e *Expr, attributes map[string]Value, it string) Value {
	switch e.op {
	case "literal":
		return e.value
	case "it":
		return stringValue(it)
	case "attribute":
		v,
			ok := attributes[e.name]
		if !ok {
			return errorValue("missing " + e.name)
		}
		return v
	case "present":
		_,
			ok := attributes[e.args[0].name]
		return boolValue(ok)
	case "any_of", "all_of":
		x := evaluateExpr(e.args[0],
			attributes, it)
		if x.kind == "error" {
			return x
		}
		if x.kind != "bag" {
			return errorValue("type " + e.op)
		}
		firstError := ""
		found := false
		any := e.op == "any_of"
		for _, item := range x.bag {
			v := evaluateExpr(e.args[1], attributes, item)
			if v.kind != "error" && v.kind != "boolean" {
				v = errorValue("type " + e.op)
			}
			if v.kind == "boolean" && v.boolean == any {
				found = true
			}
			if v.kind == "error" && firstError == "" {
				firstError = v.text
			}
		}
		if found {
			return boolValue(any)
		}
		if firstError != "" {
			return errorValue(firstError)
		}
		return boolValue(!any)
	}
	values := make([]Value,
		len(e.args))
	for i, arg := range e.args {
		values[i] = evaluateExpr(arg, attributes, it)
	}
	if e.op == "and" || e.op == "or" {
		for i, v := range values {
			if v.kind != "boolean" && v.kind != "error" {
				values[i] = errorValue("type " + e.op)
			}
		}
		winning := e.op == "or"
		for _, v := range values {
			if v.kind == "boolean" && v.boolean == winning {
				return boolValue(winning)
			}
		}
		for _, v := range values {
			if v.kind == "error" {
				return v
			}
		}
		return boolValue(!winning)
	}
	for _, v := range values {
		if v.kind == "error" {
			return v
		}
	}
	a := values[0]
	if len(values) == 1 {
		switch e.op {
		case "not":
			if a.kind == "boolean" {
				return boolValue(!a.boolean)
			}
		case "-":
			if a.kind == "integer" {
				return intValue(-a.integer)
			}
		case "size":
			if a.kind == "bag" {
				return intValue(len(a.bag))
			}
		}
		return errorValue("type " + e.op)
	}
	b := values[1]
	switch e.op {
	case "+",
		"-", "*":
		if a.kind == "integer" && b.kind == "integer" {
			switch e.op {
			case "+":
				return intValue(a.integer + b.integer)
			case "-":
				return intValue(a.integer - b.integer)
			default:
				return intValue(a.integer * b.integer)
			}
		}
	case "starts_with":
		if a.kind == "string" && b.kind == "string" {
			return boolValue(strings.HasPrefix(a.text,
				b.text))
		}
	case "in":
		if a.kind == "string" && b.kind == "bag" {
			for _, s := range b.bag {
				if s == a.text {
					return boolValue(true)
				}
			}
			return boolValue(false)
		}
	default:
		return compareValues(e.op,
			a, b)
	}
	return errorValue("type " + e.op)
}
func compareValues(op string, a, b Value) Value {
	if op == "==" || op == "!=" {
		if a.kind != b.kind || a.kind == "bag" {
			return errorValue("type " + op)
		}
		equal := false
		switch a.kind {
		case "integer":
			equal = a.integer == b.integer
		case "string":
			equal = a.text == b.text
		case "boolean":
			equal = a.boolean == b.boolean
		}
		if op == "!=" {
			equal = !equal
		}
		return boolValue(equal)
	}
	if op == "^=" {
		if a.kind == "string" && b.kind == "string" {
			return boolValue(strings.HasPrefix(a.text,
				b.text))
		}
		return errorValue("type " + op)
	}
	if a.kind != "integer" || b.kind != "integer" {
		return errorValue("type " + op)
	}
	switch op {
	case "<":
		return boolValue(a.integer < b.integer)
	case "<=":
		return boolValue(a.integer <= b.integer)
	case ">":
		return boolValue(a.integer > b.integer)
	default:
		return boolValue(a.integer >= b.integer)
	}
}
func mergeTargets(values []TargetResult, conjunction bool) TargetResult {
	winning := "MATCH"
	fallback := "NO_MATCH"
	if conjunction {
		winning,
			fallback = fallback, winning
	}
	reason := ""
	found := false
	for _, v := range values {
		if v.state == winning {
			found = true
		}
		if v.state == "INDETERMINATE" && reason == "" {
			reason = v.reason
		}
	}
	if found {
		return TargetResult{state: winning}
	}
	if reason != "" {
		return TargetResult{"INDETERMINATE",
			reason}
	}
	return TargetResult{state: fallback}
}
func evaluateTarget(e *Element, attributes map[string]Value) TargetResult {
	var lines []TargetResult
	for _, line := range e.targets {
		var alternatives []TargetResult
		for _, alt := range line {
			var clauses []TargetResult
			for _, c := range alt {
				v, present := attributes[c.attribute]
				var items []Value
				if present {
					if v.kind == "bag" {
						for _, s := range v.bag {
							items = append(items, stringValue(s))
						}
					} else {
						items = []Value{v}
					}
				}
				matched := false
				reason := ""
				for _, item := range items {
					test := compareValues(c.operator, item, c.literal)
					if test.kind == "boolean" && test.boolean {
						matched = true
					}
					if test.kind == "error" && reason == "" {
						reason = test.text
					}
				}
				result := TargetResult{state: "NO_MATCH"}
				if matched {
					result.state = "MATCH"
				} else if reason != "" {
					result = TargetResult{"INDETERMINATE",
						reason}
				} else if !present && c.mandatory {
					result = TargetResult{"INDETERMINATE", "missing " + c.attribute}
				}
				clauses = append(clauses,
					result)
			}
			alternatives = append(alternatives, mergeTargets(clauses, true))
		}
		lines = append(lines, mergeTargets(alternatives,
			false))
	}
	return mergeTargets(lines, true)
}

type Evaluation struct {
	element                               *Element
	target                                TargetResult
	condition, decision, reason, decisive string
	children                              []ChildState
	obligations, advice                   []string
}

func (e *Evaluation) notation() string {
	if indeterminate(e.decision) {
		return e.decision + " (" + e.reason + ")"
	}
	return e.decision
}
func effectError(effect string) string {
	if effect == "DENY" {
		return id
	}
	return ip
}
func ruleResult(e *Element, attributes map[string]Value) *Evaluation {
	r := &Evaluation{element: e, target: evaluateTarget(e,
		attributes), decision: na}
	if r.target.state == "NO_MATCH" {
		return r
	}
	if r.target.state == "INDETERMINATE" {
		r.decision = effectError(e.effect)
		r.reason = r.target.reason
		return r
	}
	c := boolValue(true)
	if e.condition != nil {
		c = evaluateExpr(e.condition,
			attributes, "")
	}
	if c.kind != "boolean" && c.kind != "error" {
		c = errorValue("type condition")
	}
	r.condition = "FALSE"
	if c.kind == "error" {
		r.condition = "INDETERMINATE"
		r.decision = effectError(e.effect)
		r.reason = c.text
	} else if c.boolean {
		r.condition = "TRUE"
		r.decision = e.effect
		r.decisive = e.id
	}
	return r
}
func attachments(r *Evaluation, attributes map[string]Value) {
	if !definite(r.decision) {
		return
	}
	for _, kind := range []string{"obligation", "advice"} {
		for _, a := range r.element.attachments {
			if a.kind != kind || a.effect != r.decision {
				continue
			}
			text := a.id
			reason := ""
			for _, arg := range a.args {
				v := evaluateExpr(arg.expression, attributes, "")
				if v.kind == "error" && reason == "" {
					reason = v.text
				}
				text += " " + arg.name + "=" + v.notation()
			}
			if reason != "" {
				if kind == "obligation" {
					r.decision = effectError(r.decision)
					r.reason = "obligation " + a.id + ": " + reason
					r.decisive = ""
					r.obligations = nil
					r.advice = nil
					return
				}
				continue
			}
			if kind == "obligation" {
				r.obligations = append(r.obligations,
					text)
			} else {
				r.advice = append(r.advice, text)
			}
		}
	}
}
func evaluate(e *Element, attributes map[string]Value, coverage map[*Element]string) *Evaluation {
	var r *Evaluation
	if e.kind == "rule" {
		r = ruleResult(e,
			attributes)
		attachments(r, attributes)
		if coverage != nil {
			symbol := "I"
			switch r.decision {
			case "PERMIT":
				symbol = "P"
			case "DENY":
				symbol = "D"
			case na:
				symbol = "-"
			}
			coverage[e] = symbol
		}
		return r
	}
	r = &Evaluation{element: e,
		target: evaluateTarget(e, attributes), decision: na}
	if r.target.state == "NO_MATCH" {
		return r
	}
	r.decision,
		r.reason, r.children = combine(e.algorithm, e.children, func(child *Element) *Evaluation {
		return evaluate(child,
			attributes, coverage)
	}, func(child *Element) TargetResult { return evaluateTarget(child, attributes) })
	if r.target.state == "INDETERMINATE" {
		if definite(r.decision) {
			r.decision = effectError(r.decision)
		}
		if indeterminate(r.decision) {
			r.reason = r.target.reason
		}
	}
	if definite(r.decision) {
		r.decisive = e.id
		first := true
		for _, state := range r.children {
			child := state.result
			if child != nil && child.decision == r.decision {
				if first {
					r.decisive = child.decisive
					first = false
				}
				r.obligations = append(r.obligations,
					child.obligations...)
				r.advice = append(r.advice, child.advice...)
			}
		}
		attachments(r, attributes)
	}
	return r
}
func treeLines(r *Evaluation, depth int) []string {
	indent := strings.Repeat(" ", 2+2*depth)
	e := r.element
	text := indent + e.kind + " " + e.id + " "
	if e.kind == "rule" {
		text += e.effect + " target " + r.target.state
		if r.target.state == "MATCH" {
			text += " condition " + r.condition
		}
	} else {
		text += e.algorithm + " target " + r.target.state
	}
	out := []string{text + " -> " + r.notation()}
	if e.kind != "rule" && r.target.state != "NO_MATCH" {
		for i, child := range e.children {
			state := r.children[i]
			if state.result != nil {
				out = append(out, treeLines(state.result,
					depth+1)...)
			} else {
				line := indent + "  " + child.kind + " " + child.id
				if state.checked {
					line += " " + child.algorithm + " target " + state.target.state
					if state.target.state == "INDETERMINATE" {
						line += " (" + state.target.reason + ")"
					}
				} else {
					line += " skipped"
				}
				out = append(out,
					line)
			}
		}
	}
	return out
}

type Resource struct {
	kind       string
	attributes map[string]Value
}
type Request struct {
	id, user, roles, action, resource string
	environment                       map[string]Value
	explain                           bool
}
type Activation struct{ role, reason string }
type Answer struct {
	request     Request
	error       string
	day         int
	kind, grant string
	activations []Activation
	roles       []string
	result      *Evaluation
	coverage    map[*Element]string
}
type Engine struct {
	rbac            *RBAC
	root            *Element
	elements, rules []*Element
	subjects        map[string]map[string]Value
	resources       map[string]Resource
	domains         []Domain
	reference       map[string]Value
	requests        []Request
	answers         []*Answer
}

func parseAttributes(parts []string) map[string]Value {
	out := map[string]Value{}
	for _, part := range parts {
		a := strings.SplitN(part,
			"=", 2)
		out[a[0]] = parseValue(a[1])
	}
	return out
}
func (e *Engine) readInputs() {
	e.subjects = map[string]map[string]Value{}
	e.resources = map[string]Resource{}
	for _, line := range readLines("input/attributes.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "SUBJECT":
			e.subjects[a[1]] = parseAttributes(a[2:])
		case "RESOURCE":
			e.resources[a[1]] = Resource{a[2],
				parseAttributes(a[3:])}
		case "DOMAIN":
			d := Domain{attribute: a[1]}
			for _, s := range a[2:] {
				d.values = append(d.values,
					parseValue(s))
			}
			e.domains = append(e.domains, d)
		case "REFERENCE":
			e.reference = parseAttributes(a[1:])
		}
	}
	for _, line := range readLines("input/requests.txt") {
		a := strings.Fields(line)
		explain := a[len(a)-1] == "EXPLAIN"
		if explain {
			a = a[:len(a)-1]
		}
		e.requests = append(e.requests,
			Request{a[0], a[1], a[2], a[3], a[4], parseAttributes(a[5:]), explain})
	}
}
func (e *Engine) answer(request Request, record bool) *Answer {
	a := &Answer{request: request, coverage: map[*Element]string{}}
	if record {
		for _, rule := range e.rules {
			a.coverage[rule] = "."
		}
	}
	subject, ok := e.subjects[request.user]
	if !ok {
		a.error = "unknown user " + request.user
		return a
	}
	resource,
		ok := e.resources[request.resource]
	if !ok {
		a.error = "unknown resource " + request.resource
		return a
	}
	day := request.environment["day"]
	if day.kind != "integer" || day.integer < 1 || day.integer > 365 {
		a.error = "bad day"
		return a
	}
	a.day = day.integer
	a.kind = resource.kind
	authorized := e.rbac.authorized(request.user,
		a.day)
	var candidates []string
	switch request.roles {
	case "-":
	case "*":
		candidates = sortedSet(authorized)
	default:
		candidates = strings.Split(request.roles,
			",")
	}
	seen := map[string]bool{}
	var active []string
	for _, candidate := range candidates {
		reason := ""
		if !e.rbac.roles[candidate] {
			reason = "unknown"
		} else if seen[candidate] {
			reason = "duplicate"
		} else if !authorized[candidate] {
			reason = "unauthorized"
		} else {
			set := e.rbac.closure(append(append([]string(nil),
				active...), candidate))
			for _, constraint := range e.rbac.dsd {
				if len(intersection(constraint.roles,
					set)) >= constraint.cardinality {
					reason = "dsd " + constraint.name
					break
				}
			}
		}
		seen[candidate] = true
		a.activations = append(a.activations,
			Activation{candidate, reason})
		if reason == "" {
			active = append(active, candidate)
		}
	}
	a.roles = sortedSet(e.rbac.closure(active))
	for _, role := range a.roles {
		if e.rbac.permissions[role][request.action+" "+resource.kind] {
			a.grant = role
			break
		}
	}
	attributes := map[string]Value{}
	for name, v := range subject {
		attributes["subject."+name] = v
	}
	attributes["subject.id"] = stringValue(request.user)
	attributes["subject.role"] = bagValue(a.roles)
	attributes["subject.rbac"] = boolValue(a.grant != "")
	for name, v := range resource.attributes {
		attributes["resource."+name] = v
	}
	attributes["resource.id"] = stringValue(request.resource)
	attributes["resource.type"] = stringValue(resource.kind)
	attributes["action.id"] = stringValue(request.action)
	for name, v := range request.environment {
		attributes["environment."+name] = v
	}
	var coverage map[*Element]string
	if record {
		coverage = a.coverage
	}
	a.result = evaluate(e.root,
		attributes, coverage)
	return a
}
func (a *Answer) decisionText() string {
	text := a.result.notation()
	if definite(a.result.decision) {
		text += " by " + a.result.decisive
	}
	return text
}
func (e *Engine) decisionLines() []string {
	var out []string
	for _, a := range e.answers {
		if a.error != "" {
			out = append(out,
				a.request.id+" ERROR "+a.error)
			continue
		}
		out = append(out, a.request.id+" "+a.decisionText())
		for _, v := range a.activations {
			if v.reason != "" {
				out = append(out, "  refused "+v.role+" "+v.reason)
			}
		}
		for _, item := range a.result.obligations {
			out = append(out, "  obligation "+item)
		}
		for _, item := range a.result.advice {
			out = append(out,
				"  advice "+item)
		}
	}
	return out
}
func (e *Engine) traceLines() []string {
	var out []string
	for _, a := range e.answers {
		r := a.request
		if !r.explain {
			continue
		}
		if len(out) > 0 {
			out = append(out,
				"")
		}
		out = append(out, "request "+r.id)
		if a.error != "" {
			out = append(out, "  error "+a.error)
			continue
		}
		out = append(out,
			fmt.Sprintf("  user %s resource %s type %s action %s day %d", r.user, r.resource, a.kind, r.action,
				a.day))
		for _, v := range a.activations {
			text := "ok"
			if v.reason != "" {
				text = "refused " + v.reason
			}
			out = append(out,
				"  activate "+v.role+" "+text)
		}
		roles := strings.Join(a.roles, ",")
		if roles == "" {
			roles = "-"
		}
		out = append(out,
			"  roles "+roles)
		if a.grant != "" {
			out = append(out, "  rbac yes "+a.grant)
		} else {
			out = append(out, "  rbac no")
		}
		out = append(out,
			treeLines(a.result, 0)...)
		out = append(out, "  decision "+a.decisionText())
	}
	return out
}
func stringKeys[V any](a map[string]V) []string {
	keys := make([]string, 0, len(a))
	for key := range a {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
func (e *Engine) permissionLines() []string {
	assigned := map[string]map[string]Days{}
	for _, a := range e.rbac.assignments {
		if assigned[a.user] == nil {
			assigned[a.user] = map[string]Days{}
		}
		days := assigned[a.user][a.role]
		for d := a.first; d <= a.last; d++ {
			days[d] = true
		}
		assigned[a.user][a.role] = days
	}
	var out []string
	for _, user := range stringKeys(assigned) {
		if len(out) > 0 {
			out = append(out, "")
		}
		out = append(out, "user "+user)
		authorization := map[string]Days{}
		for _, role := range stringKeys(assigned[user]) {
			days := assigned[user][role]
			out = append(out, "  assigned "+role+" "+dayNotation(days))
			for child := range e.rbac.closure([]string{role}) {
				authorization[child] = unionDays(authorization[child],
					days)
			}
		}
		permissions := map[string]Days{}
		via := map[string][]string{}
		for _, role := range stringKeys(authorization) {
			days := authorization[role]
			out = append(out,
				"  authorized "+role+" "+dayNotation(days))
			for permission := range e.rbac.permissions[role] {
				permissions[permission] = unionDays(permissions[permission],
					days)
				via[permission] = append(via[permission], role)
			}
		}
		for _, permission := range stringKeys(permissions) {
			effective := "-"
			if _,
				ok := e.subjects[user]; ok {
				pair := strings.Fields(permission)
				n, k := 0, 0
				for _, id := range stringKeys(e.resources) {
					resource := e.resources[id]
					if resource.kind != pair[1] {
						continue
					}
					n++
					answer := e.answer(Request{user: user,
						roles: "*", action: pair[0], resource: id, environment: e.reference}, false)
					if answer.result.decision == "PERMIT" {
						k++
					}
				}
				effective = fmt.Sprintf("%d/%d",
					k, n)
			}
			out = append(out, "  permission "+permission+" "+dayNotation(permissions[permission])+" via "+strings.Join(via[permission],
				",")+" effective "+effective)
		}
	}
	return out
}

type Conflict struct {
	policy, a, b, winner *Element
	count                int
}

func (e *Engine) analysisLines() []string {
	out := []string{fmt.Sprintf("rbac %d", len(e.rbac.diagnostics))}
	for _, d := range e.rbac.diagnostics {
		out = append(out, fmt.Sprintf("  line %d %s %s", d.line, d.keyword, d.message))
	}
	permits := append([]Permission(nil),
		e.rbac.permits...)
	sort.Slice(permits, func(i, j int) bool {
		a, b := permits[i], permits[j]
		if a.role != b.role {
			return a.role < b.role
		}
		if a.action != b.action {
			return a.action < b.action
		}
		return a.kind < b.kind
	})
	out = append(out,
		fmt.Sprintf("grants %d", len(permits)))
	for _, p := range permits {
		count := 0
		for _, a := range e.answers {
			if a.error == "" && a.grant == p.role && a.request.action == p.action && a.kind == p.kind {
				count++
			}
		}
		out = append(out,
			fmt.Sprintf("  %s %s %s %d", p.role, p.action, p.kind, count))
	}
	var conflicts []*Conflict
	for _, policy := range e.elements {
		if policy.kind != "policy" {
			continue
		}
		for i, a := range policy.children {
			for _, b := range policy.children[i+1:] {
				if a.effect != b.effect {
					conflicts = append(conflicts,
						&Conflict{policy: policy, a: a, b: b, winner: conflictWinner(policy, a, b)})
				}
			}
		}
	}
	points := 1
	for _, d := range e.domains {
		points *= len(d.values)
	}
	counts := map[*Element]int{}
	examples := map[*Element]string{}
	unblocked := map[*Element]bool{}
	blockers := map[*Element]map[*Element]bool{}
	enumeratePoints(e.domains,
		func(point map[string]Value) {
			targets := map[*Element]TargetResult{}
			for _, element := range e.elements {
				targets[element] = evaluateTarget(element,
					point)
			}
			standalone := map[*Element]string{}
			applies := map[*Element]bool{}
			for _, rule := range e.rules {
				standalone[rule] = ruleResult(rule,
					point).decision
				applies[rule] = definite(standalone[rule])
				for parent := rule.parent; parent != nil; parent = parent.parent {
					if targets[parent].state != "MATCH" {
						applies[rule] = false
					}
				}
			}
			for _, rule := range e.rules {
				if !applies[rule] {
					continue
				}
				counts[rule]++
				if counts[rule] == 1 {
					var parts []string
					for _, domain := range e.domains {
						if len(domain.values) > 1 {
							parts = append(parts, domain.attribute+"="+point[domain.attribute].notation())
						}
					}
					examples[rule] = strings.Join(parts,
						" ")
				}
				if rule.parent.algorithm == "first-applicable" {
					b := blocker(rule, standalone)
					if b == nil {
						unblocked[rule] = true
					} else {
						if blockers[rule] == nil {
							blockers[rule] = map[*Element]bool{}
						}
						blockers[rule][b] = true
					}
				}
			}
			for _, c := range conflicts {
				if applies[c.a] && applies[c.b] {
					c.count++
				}
			}
		})
	out = append(out, fmt.Sprintf("applicability %d",
		points))
	var dead, shadowed, uncovered []*Element
	for _, rule := range e.rules {
		example := examples[rule]
		if counts[rule] == 0 {
			example = "-"
			dead = append(dead,
				rule)
		}
		out = append(out, fmt.Sprintf("  %s %d %s", rule.id, counts[rule], example))
		if counts[rule] > 0 && rule.parent.algorithm == "first-applicable" && !unblocked[rule] {
			shadowed = append(shadowed,
				rule)
		}
	}
	out = append(out, fmt.Sprintf("dead %d", len(dead)))
	for _, rule := range dead {
		out = append(out,
			"  "+rule.id)
	}
	out = append(out, fmt.Sprintf("shadowed %d", len(shadowed)))
	for _, rule := range shadowed {
		var ids []string
		for _, earlier := range rule.parent.children {
			if blockers[rule][earlier] {
				ids = append(ids, earlier.id)
			}
		}
		out = append(out,
			"  "+rule.id+" by "+strings.Join(ids, ","))
	}
	conflictCount := 0
	for _, c := range conflicts {
		if c.count > 0 {
			conflictCount++
		}
	}
	out = append(out,
		fmt.Sprintf("conflicts %d", conflictCount))
	for _, c := range conflicts {
		if c.count > 0 {
			out = append(out,
				fmt.Sprintf("  %s %s %s %d %s", c.policy.id, c.a.id, c.b.id, c.count, c.winner.id))
		}
	}
	out = append(out,
		fmt.Sprintf("coverage %d", len(e.answers)))
	for _, rule := range e.rules {
		symbols := ""
		count := 0
		for _, a := range e.answers {
			symbol := a.coverage[rule]
			symbols += symbol
			if symbol == "P" || symbol == "D" {
				count++
			}
		}
		out = append(out,
			fmt.Sprintf("  %s %s %d", rule.id, symbols, count))
		if count == 0 {
			uncovered = append(uncovered, rule)
		}
	}
	out = append(out,
		fmt.Sprintf("uncovered %d", len(uncovered)))
	for _, rule := range uncovered {
		out = append(out, "  "+rule.id)
	}
	decisionCounts := map[string]int{}
	decisive := map[string]int{}
	obligationCounts := map[string]int{}
	adviceCounts := map[string]int{}
	refused := 0
	for _, a := range e.answers {
		if a.error != "" {
			decisionCounts["ERROR"]++
			continue
		}
		r := a.result
		decision := r.decision
		if indeterminate(decision) {
			decision = "INDETERMINATE"
		}
		decisionCounts[decision]++
		for _, activation := range a.activations {
			if activation.reason != "" {
				refused++
			}
		}
		if definite(r.decision) {
			decisive[r.decisive]++
		}
		for _, item := range r.obligations {
			obligationCounts[strings.Fields(item)[0]]++
		}
		for _, item := range r.advice {
			adviceCounts[strings.Fields(item)[0]]++
		}
	}
	out = append(out,
		"summary")
	for _, name := range []string{"PERMIT", "DENY", na, "INDETERMINATE", "ERROR"} {
		out = append(out,
			fmt.Sprintf("  decision %s %d", name, decisionCounts[name]))
	}
	out = append(out, fmt.Sprintf("  refused %d",
		refused))
	for _, element := range e.elements {
		if decisive[element.id] > 0 {
			out = append(out, fmt.Sprintf("  decisive %s %d",
				element.id, decisive[element.id]))
		}
	}
	for _, name := range stringKeys(obligationCounts) {
		out = append(out,
			fmt.Sprintf("  obligation %s %d", name, obligationCounts[name]))
	}
	for _, name := range stringKeys(adviceCounts) {
		out = append(out,
			fmt.Sprintf("  advice %s %d", name, adviceCounts[name]))
	}
	return out
}
func main() {
	root, elements, rules := readPolicies()
	engine := &Engine{rbac: readRBAC(), root: root, elements: elements,
		rules: rules}
	engine.readInputs()
	for _, request := range engine.requests {
		engine.answers = append(engine.answers,
			engine.answer(request, true))
	}
	reports := map[string][]string{"decisions.txt": engine.decisionLines(),
		"traces.txt": engine.traceLines(), "permissions.txt": engine.permissionLines(), "analysis.txt": engine.analysisLines()}
	if err := os.MkdirAll("output",
		0755); err != nil {
		panic(err)
	}
	for name, lines := range reports {
		text := ""
		if len(lines) > 0 {
			text = strings.Join(lines,
				"\n") + "\n"
		}
		if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
			panic(err)
		}
	}
}
