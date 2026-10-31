package main

type Clause struct {
	Head, Body *Term
	File       string
	Line       int
}
type Predicate struct {
	Indicator Indicator
	Clauses   []*Clause
}
type Database struct {
	Predicates map[Indicator]*Predicate
	Order      []*Predicate
}

func newDatabase() *Database { return &Database{Predicates: map[Indicator]*Predicate{}} }
func (d *Database) ensure(p Indicator) *Predicate {
	if previous := d.Predicates[p]; previous != nil {
		return previous
	}
	predicate := &Predicate{Indicator: p}
	d.Predicates[p] = predicate
	d.Order = append(d.Order, predicate)
	return predicate
}
func sameKind(a, b *Term) bool {
	a, b = dereference(a), dereference(b)
	if a.Kind == "variable" || b.Kind == "variable" {
		return true
	}
	if a.Kind != b.Kind {
		return false
	}
	switch a.Kind {
	case "integer":
		return a.Integer == b.Integer
	case "atom":
		return a.Name == b.Name
	case "compound":
		return a.Name == b.Name && len(a.Arguments) == len(b.Arguments)
	}
	return false
}
func (p *Predicate) candidates(goal *Term) []*Clause {
	out := []*Clause{}
	for _, clause := range p.Clauses {
		if p.Indicator.Arity == 0 || sameKind(goal.Arguments[0], clause.Head.Arguments[0]) {
			out = append(out, clause)
		}
	}
	return out
}
func copyClause(c *Clause) (*Term, *Term) {
	copier := newCopier()
	head := copier.copy(c.Head)
	var body *Term
	if c.Body != nil {
		body = copier.copy(c.Body)
	}
	return head, body
}
