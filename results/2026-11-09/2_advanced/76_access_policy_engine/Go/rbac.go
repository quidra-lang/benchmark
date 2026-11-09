package main

import (
	"fmt"
	"sort"
	"strings"
)

type Constraint struct {
	name        string
	cardinality int
	roles       []string
}
type Assignment struct {
	user, role  string
	first, last int
}
type Permission struct{ role, action, kind string }
type Diagnostic struct {
	line             int
	keyword, message string
}
type RBAC struct {
	roles       map[string]bool
	edges       map[string][]string
	permissions map[string]map[string]bool
	permits     []Permission
	ssd,
	dsd []Constraint
	assignments []Assignment
	diagnostics []Diagnostic
}

func sortedSet(a map[string]bool) []string {
	out := make([]string, 0, len(a))
	for s := range a {
		out = append(out, s)
	}
	sort.Strings(out)
	return out
}
func (r *RBAC) closure(roles []string) map[string]bool {
	out := map[string]bool{}
	var visit func(string)
	visit = func(role string) {
		if out[role] {
			return
		}
		out[role] = true
		for _, child := range r.edges[role] {
			visit(child)
		}
	}
	for _, role := range roles {
		visit(role)
	}
	return out
}
func (r *RBAC) path(from, to string) []string {
	failed := map[string]bool{}
	var search func(string) []string
	search = func(current string) []string {
		if current == to {
			return []string{current}
		}
		if failed[current] {
			return nil
		}
		children := append([]string(nil), r.edges[current]...)
		sort.Strings(children)
		for _, child := range children {
			if tail := search(child); tail != nil {
				return append([]string{current}, tail...)
			}
		}
		failed[current] = true
		return nil
	}
	return search(from)
}

func (r *RBAC) assigned(user string, day int) []string {
	set := map[string]bool{}
	for _, a := range r.assignments {
		if a.user == user && a.first <= day && day <= a.last {
			set[a.role] = true
		}
	}
	return sortedSet(set)
}
func (r *RBAC) authorized(user string, day int) map[string]bool {
	return r.closure(r.assigned(user, day))
}
func intersection(roles []string, set map[string]bool) []string {
	var out []string
	for _, role := range roles {
		if set[role] {
			out = append(out,
				role)
		}
	}
	sort.Strings(out)
	return out
}
func readRBAC() *RBAC {
	r := &RBAC{roles: map[string]bool{}, edges: map[string][]string{}, permissions: map[string]map[string]bool{}}
	lines := readLines("input/rbac.txt")
	for _, keyword := range []string{"ROLE", "INHERITS", "PERMIT", "SSD", "DSD", "ASSIGN"} {
		for i, line := range lines {
			a := strings.Fields(line)
			if a[0] != keyword {
				continue
			}
			message := ""
			switch keyword {
			case "ROLE":
				if r.roles[a[1]] {
					message = "duplicate role " + a[1]
				} else {
					r.roles[a[1]] = true
					r.permissions[a[1]] = map[string]bool{}
				}
			case "INHERITS":
				senior, junior := a[1], a[2]
				if !r.roles[senior] {
					message = "unknown role " + senior
				} else if !r.roles[junior] {
					message = "unknown role " + junior
				} else {
					duplicate := false
					for _, v := range r.edges[senior] {
						if v == junior {
							duplicate = true
						}
					}
					if duplicate {
						message = "duplicate inheritance " + senior + " " + junior
					} else if path := r.path(junior,
						senior); path != nil {
						message = "cycle " + strings.Join(append([]string{senior}, path...), " > ")
					} else {
						r.edges[senior] = append(r.edges[senior],
							junior)
					}
				}
			case "PERMIT":
				if !r.roles[a[1]] {
					message = "unknown role " + a[1]
				} else if r.permissions[a[1]][a[2]+" "+a[3]] {
					message = "duplicate permission " + strings.Join(a[1:],
						" ")
				} else {
					r.permissions[a[1]][a[2]+" "+a[3]] = true
					r.permits = append(r.permits, Permission{a[1],
						a[2], a[3]})
				}
			case "SSD", "DSD":
				constraints := r.ssd
				if keyword == "DSD" {
					constraints = r.dsd
				}
				for _, c := range constraints {
					if c.name == a[1] {
						message = "duplicate constraint " + a[1]
						break
					}
				}
				roles := strings.Split(a[3],
					",")
				if message == "" {
					for _, role := range roles {
						if !r.roles[role] {
							message = "unknown role " + role
							break
						}
					}
				}
				cardinality := number(a[2])
				if message == "" && (cardinality < 2 || cardinality > len(roles)) {
					message = fmt.Sprintf("bad cardinality %s %d",
						a[1], cardinality)
				}
				if message == "" {
					c := Constraint{a[1], cardinality, roles}
					if keyword == "SSD" {
						r.ssd = append(r.ssd,
							c)
					} else {
						r.dsd = append(r.dsd, c)
					}
				}
			case "ASSIGN":
				user, role := a[1], a[2]
				first, last := number(a[3]), number(a[4])
				if !r.roles[role] {
					message = "unknown role " + role
				} else if !(1 <= first && first <= last && last <= 365) {
					message = fmt.Sprintf("bad range %d %d",
						first, last)
				} else {
					for _, c := range r.ssd {
						for day := first; day <= last; day++ {
							set := r.closure(append(r.assigned(user,
								day), role))
							common := intersection(c.roles, set)
							if len(common) >= c.cardinality {
								message = fmt.Sprintf("ssd %s day %d roles %s",
									c.name, day, strings.Join(common, ","))
								break
							}
						}
						if message != "" {
							break
						}
					}
				}
				if message == "" {
					r.assignments = append(r.assignments,
						Assignment{user, role, first, last})
				}
			}
			if message != "" {
				r.diagnostics = append(r.diagnostics, Diagnostic{i + 1,
					keyword, message})
			}
		}
	}
	sort.Slice(r.diagnostics, func(i, j int) bool { return r.diagnostics[i].line < r.diagnostics[j].line })
	return r
}
