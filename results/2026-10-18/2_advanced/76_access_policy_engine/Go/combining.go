package main

const na = "NOT_APPLICABLE"
const ip = "INDETERMINATE{P}"
const id = "INDETERMINATE{D}"
const idp = "INDETERMINATE{DP}"

type TargetResult struct{ state, reason string }
type ChildState struct {
	checked bool
	target  TargetResult
	result  *Evaluation
}

func definite(d string) bool      { return d == "PERMIT" || d == "DENY" }
func indeterminate(d string) bool { return d == ip || d == id || d == idp }
func combine(algorithm string, children []*Element, evaluate func(*Element) *Evaluation, target func(*Element) TargetResult) (string,
	string, []ChildState) {
	states := make([]ChildState, len(children))
	if algorithm == "only-one-applicable" {
		matched := -1
		for i, child := range children {
			t := target(child)
			states[i] = ChildState{checked: true, target: t}
			if t.state == "INDETERMINATE" {
				return idp,
					t.reason, states
			}
			if t.state == "MATCH" {
				if matched >= 0 {
					return idp, "multiple applicable " + children[matched].id + " " + child.id,
						states
				}
				matched = i
			}
		}
		if matched < 0 {
			return na, "", states
		}
		result := evaluate(children[matched])
		states[matched] = ChildState{result: result}
		return result.decision,
			result.reason, states
	}
	decisions := map[string]bool{}
	firstError := ""
	for i, child := range children {
		result := evaluate(child)
		states[i] = ChildState{result: result}
		d := result.decision
		decisions[d] = true
		if indeterminate(d) && firstError == "" {
			firstError = result.reason
		}
		if algorithm == "first-applicable" && d != na {
			return d,
				result.reason, states
		}
		if (algorithm == "deny-overrides" || algorithm == "permit-unless-deny") && d == "DENY" {
			return "DENY",
				"", states
		}
		if (algorithm == "permit-overrides" || algorithm == "deny-unless-permit") && d == "PERMIT" {
			return "PERMIT",
				"", states
		}
	}
	switch algorithm {
	case "deny-unless-permit":
		return "DENY", "", states
	case "permit-unless-deny":
		return "PERMIT",
			"", states
	case "first-applicable":
		return na, "", states
	}
	d := na
	if algorithm == "deny-overrides" {
		switch {
		case decisions[idp] || decisions[id] && (decisions[ip] || decisions["PERMIT"]):
			d = idp
		case decisions[id]:
			d = id
		case decisions["PERMIT"]:
			d = "PERMIT"
		case decisions[ip]:
			d = ip
		}
	} else {
		switch {
		case decisions[idp] || decisions[ip] && (decisions[id] || decisions["DENY"]):
			d = idp
		case decisions[ip]:
			d = ip
		case decisions["DENY"]:
			d = "DENY"
		case decisions[id]:
			d = id
		}
	}
	if indeterminate(d) {
		return d,
			firstError, states
	}
	return d, "", states
}
