package main

import (
	"bufio"
	"fmt"
	"math/big"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type Composition map[string]int64

var symbols = strings.Fields("H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe")
var weights = []int64{1008, 4003, 6941, 9012, 10811, 12011, 14007, 15999, 18998, 20180, 22990, 24305, 26982, 28086, 30974, 32065, 35453, 39948, 39098, 40078, 44956, 47867, 50942, 51996, 54938, 55845, 58933, 58693, 63546, 65380, 69723, 72630, 74922, 78971, 79904, 83798, 85468, 87620, 88906, 91224, 92906, 95950, 98000, 101070, 102906, 106420, 107868, 112414, 114818, 118710, 121760, 127600, 126904, 131293}
var W = func() Composition {
	m := Composition{}
	for i, s := range symbols {
		m[s] = weights[i]
	}
	return m
}()
var valence = Composition{"H": 1, "F": 1, "Cl": 1, "Br": 1, "I": 1, "O": 2, "S": 2, "Se": 2, "B": 3, "N": 3, "P": 3, "As": 3, "C": 4, "Si": 4, "Ge": 4}
var metals = Composition{"Li": 1, "Na": 1, "K": 1, "Rb": 1, "Be": 2, "Mg": 2, "Ca": 2, "Sr": 2, "Al": 3}

func problem(s string) error {
	return fmt.Errorf("error: %s", s)
}
func abs(n int64) int64 {
	if n < 0 {
		return -n
	}
	return n
}
func gcd(a, b int64) int64 {
	a = abs(a)
	b = abs(b)
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func dec(n int64, d int) string {
	p := int64(1)
	for i := 0; i < d; i++ {
		p *= 10
	}
	return fmt.Sprintf("%d.%0*d", n/p, d, n%p)
}
func ent(n int64) string {
	sign := ""
	if n < 0 {
		sign = "-"
	}
	return sign + dec(abs(n), 2)
}
func signed(n int64) string {
	if n > 0 {
		return "+" + strconv.FormatInt(n, 10)
	}
	return strconv.FormatInt(n, 10)
}
func signedRat(r *big.Rat) string {
	if r.Sign() > 0 {
		return "+" + r.RatString()
	}
	return r.RatString()
}
func order(c Composition) []string {
	es := []string{}
	for e := range c {
		es = append(es, e)
	}
	sort.Strings(es)
	if _, ok := c["C"]; !ok {
		return es
	}
	out := []string{"C"}
	if _, ok := c["H"]; ok {
		out = append(out, "H")
	}
	for _, e := range es {
		if e != "C" && e != "H" {
			out = append(out, e)
		}
	}
	return out
}
func add(a, b Composition, k int64) Composition {
	c := Composition{}
	for e, n := range a {
		c[e] = n
	}
	for e, n := range b {
		c[e] += n * k
	}
	return c
}
func scale(c Composition, k int64) Composition {
	b := Composition{}
	for e, n := range c {
		b[e] = n * k
	}
	return b
}
func mass(c Composition) int64 {
	m := int64(0)
	for e, n := range c {
		m += n * W[e]
	}
	return m
}
func hill(c Composition, q int64) string {
	var s strings.Builder
	for _, e := range order(c) {
		s.WriteString(e)
		if c[e] != 1 {
			s.WriteString(strconv.FormatInt(c[e], 10))
		}
	}
	if q != 0 {
		s.WriteByte('^')
		if abs(q) != 1 {
			s.WriteString(strconv.FormatInt(abs(q), 10))
		}
		if q > 0 {
			s.WriteByte('+')
		} else {
			s.WriteByte('-')
		}
	}
	return s.String()
}

type Formula struct {
	c Composition
	q int64
}
type Species struct {
	f, state    string
	coefficient int64
	formula     Formula
}

func (s Species) name() string {
	return s.f + s.state
}
func (s Species) mass() int64 {
	return mass(s.formula.c)
}

type Equation struct {
	list []Species
	r    int
}

func (e Equation) signs() []int64 {
	s := make([]int64, len(e.list))
	for i := range s {
		if i < e.r {
			s[i] = 1
		} else {
			s[i] = -1
		}
	}
	return s
}

type Parser struct {
	text string
	p    int
	seen []string
	err  bool
}

func (p *Parser) peek() byte {
	if p.p < len(p.text) {
		return p.text[p.p]
	}
	return 0
}
func (p *Parser) number() int64 {
	start := p.p
	for p.peek() >= '0' && p.peek() <= '9' {
		p.p++
	}
	if start == p.p {
		return 1
	}
	if p.text[start] == '0' {
		p.err = true
	}
	n, _ := strconv.ParseInt(p.text[start:p.p], 10, 64)
	return n
}
func (p *Parser) sequence() Composition {
	c := Composition{}
	items := 0
	for {
		ch := p.peek()
		var item Composition
		if ch >= 'A' && ch <= 'Z' {
			start := p.p
			p.p++
			if p.peek() >= 'a' && p.peek() <= 'z' {
				p.p++
			}
			e := p.text[start:p.p]
			p.seen = append(p.seen, e)
			item = Composition{e: 1}
		} else if ch == '(' || ch == '[' {
			p.p++
			item = p.sequence()
			close := byte(')')
			if ch == '[' {
				close = ']'
			}
			if p.peek() != close {
				p.err = true
			} else {
				p.p++
			}
		} else {
			break
		}
		c = add(c, item, p.number())
		items++
	}
	if items == 0 {
		p.err = true
	}
	return c
}
func formula(text, word string) (Formula, error) {
	p := Parser{text: text}
	c := p.sequence()
	for p.peek() == '.' {
		p.p++
		k := p.number()
		c = add(c, p.sequence(), k)
	}
	q := int64(0)
	if p.peek() == '^' {
		p.p++
		k := p.number()
		ch := p.peek()
		if ch != '+' && ch != '-' {
			p.err = true
		} else {
			p.p++
			q = k
			if ch == '-' {
				q = -q
			}
		}
	}
	if p.err || p.p != len(text) {
		return Formula{}, problem("invalid formula " + word)
	}
	for _, e := range p.seen {
		if _, ok := W[e]; !ok {
			return Formula{}, problem("unknown element " + e)
		}
	}
	return Formula{c, q}, nil
}
func species(word string, check bool) (Species, error) {
	f, state, k := word, "", int64(1)
	for _, s := range []string{"(s)", "(l)", "(g)", "(aq)"} {
		if strings.HasSuffix(word, s) {
			state = s
			f = strings.TrimSuffix(word, s)
			break
		}
	}
	if check && len(f) > 0 && f[0] >= '0' && f[0] <= '9' {
		i := 0
		for i < len(f) && f[i] >= '0' && f[i] <= '9' {
			i++
		}
		if f[0] == '0' {
			return Species{}, problem("invalid formula " + word)
		}
		k, _ = strconv.ParseInt(f[:i], 10, 64)
		f = f[i:]
	}
	x, err := formula(f, word)
	return Species{f, state, k, x}, err
}
func equation(a []string, check bool) (Equation, error) {
	valid := len(a)%2 == 1
	arrow := -1
	for i, s := range a {
		op := s == "+" || s == "->"
		if i%2 == 1 {
			if !op {
				valid = false
			}
			if s == "->" {
				if arrow >= 0 {
					valid = false
				}
				arrow = i
			}
		} else if op {
			valid = false
		}
	}
	if !valid || arrow < 0 {
		return Equation{}, problem("malformed equation")
	}
	e := Equation{r: (arrow + 1) / 2}
	for i := 0; i < len(a); i += 2 {
		s, err := species(a[i], check)
		if err != nil {
			return Equation{}, err
		}
		e.list = append(e.list, s)
	}
	return e, nil
}

var quantityPattern = regexp.MustCompile(`^(0|[1-9][0-9]{0,3})(\.[0-9]{1,3})?$`)
var enthalpyPattern = regexp.MustCompile(`^-?(0|[1-9][0-9]{0,4})(\.[0-9]{1,2})?$`)

func quantity(s string) (int64, error) {
	if !quantityPattern.MatchString(s) {
		return 0, problem("invalid quantity " + s)
	}
	parts := strings.Split(s, ".")
	n, _ := strconv.ParseInt(parts[0], 10, 64)
	q := n * 1000
	if len(parts) > 1 {
		n, _ = strconv.ParseInt((parts[1] + "000")[:3], 10, 64)
		q += n
	}
	if q == 0 {
		return 0, problem("invalid quantity " + s)
	}
	return q, nil
}
func enthalpy(s string) (int64, error) {
	if !enthalpyPattern.MatchString(s) {
		return 0, problem("invalid enthalpy " + s)
	}
	parts := strings.Split(strings.TrimPrefix(s, "-"), ".")
	n, _ := strconv.ParseInt(parts[0], 10, 64)
	h := n * 100
	if len(parts) > 1 {
		n, _ = strconv.ParseInt((parts[1] + "00")[:2], 10, 64)
		h += n
	}
	if strings.HasPrefix(s, "-") {
		h = -h
	}
	return h, nil
}
func matrix(list []Species, sign []int64) ([]string, [][]int64) {
	all := Composition{}
	for _, s := range list {
		all = add(all, s.formula.c, 1)
	}
	labels := append(order(all), "charge")
	rows := [][]int64{}
	for _, e := range labels {
		row := make([]int64, len(list))
		for i, s := range list {
			x := s.formula.c[e]
			if e == "charge" {
				x = s.formula.q
			}
			row[i] = sign[i] * x
		}
		rows = append(rows, row)
	}
	return labels, rows
}
func nullspace(rows [][]int64, n int) (int, [][]int64) {
	a := make([][]*big.Rat, len(rows))
	for i, row := range rows {
		a[i] = make([]*big.Rat, n)
		for j, x := range row {
			a[i][j] = new(big.Rat).SetInt64(x)
		}
	}
	piv, free := []int{}, []int{}
	for j := 0; j < n; j++ {
		r := len(piv)
		i := r
		for i < len(a) && a[i][j].Sign() == 0 {
			i++
		}
		if i == len(a) {
			free = append(free, j)
			continue
		}
		a[r], a[i] = a[i], a[r]
		t := a[r][j]
		for z := 0; z < n; z++ {
			a[r][z] = new(big.Rat).Quo(a[r][z], t)
		}
		for k := range a {
			if k != r && a[k][j].Sign() != 0 {
				f := a[k][j]
				for z := 0; z < n; z++ {
					a[k][z] = new(big.Rat).Sub(a[k][z], new(big.Rat).Mul(f, a[r][z]))
				}
			}
		}
		piv = append(piv, j)
	}
	basis := [][]int64{}
	for _, f := range free {
		v := make([]*big.Rat, n)
		for i := range v {
			v[i] = new(big.Rat)
		}
		v[f].SetInt64(1)
		for i, j := range piv {
			v[j].Neg(a[i][f])
		}
		l := int64(1)
		for _, x := range v {
			d := x.Denom().Int64()
			l = l / gcd(l, d) * d
		}
		b := make([]int64, n)
		g := int64(0)
		for i, x := range v {
			b[i] = x.Num().Int64() * (l / x.Denom().Int64())
			g = gcd(g, b[i])
		}
		for i := range b {
			b[i] /= g
		}
		basis = append(basis, b)
	}
	return len(piv), basis
}
func coefficients(list []Species, sign []int64, required int) ([]int64, error) {
	_, rows := matrix(list, sign)
	_, basis := nullspace(rows, len(list))
	if len(basis) >= 2 {
		return nil, fmt.Errorf("AMBIGUOUS (nullity %d)", len(basis))
	}
	if len(basis) == 0 {
		return nil, fmt.Errorf("IMPOSSIBLE")
	}
	v := basis[0]
	if v[0] < 0 {
		for i := range v {
			v[i] = -v[i]
		}
	}
	for _, x := range v[:required] {
		if x <= 0 {
			return nil, fmt.Errorf("IMPOSSIBLE")
		}
	}
	return v, nil
}
func term(s string, k int64) string {
	if k == 1 {
		return s
	}
	return strconv.FormatInt(k, 10) + s
}
func notation(eq Equation, v []int64) string {
	left, right := []string{}, []string{}
	for i, s := range eq.list {
		if i < eq.r {
			left = append(left, term(s.name(), v[i]))
		} else {
			right = append(right, term(s.name(), v[i]))
		}
	}
	return strings.Join(left, " + ") + " -> " + strings.Join(right, " + ")
}
func gas(s Species, n, d int64) string {
	if s.state == "(g)" {
		return " " + dec(n*22414/d, 3) + " L"
	}
	return ""
}
func ratios(a Composition) []string {
	es := order(a)
	f := es[0]
	for _, e := range es {
		if a[e]*W[f] < a[f]*W[e] {
			f = e
		}
	}
	out := []string{}
	for _, e := range es {
		out = append(out, e+" "+dec(1000*a[e]*W[f]/(W[e]*a[f]), 3))
	}
	for k := int64(1); k <= 12; k++ {
		c := Composition{}
		ok := true
		for _, e := range es {
			n, d := k*a[e]*W[f], W[e]*a[f]
			i := (2*n + d) / (2 * d)
			c[e] = i
			if 20*abs(n-i*d) > d {
				ok = false
			}
		}
		if ok {
			return append(out, fmt.Sprintf("%s (k = %d)", hill(c, 0), k))
		}
	}
	return append(out, "no simple ratio")
}
func group(f string, k int64) string {
	c := strings.Split(f, "^")[0]
	if k == 1 {
		return c
	}
	depth, last := 0, -1
	if c[0] == '[' {
		for i, ch := range c {
			if ch == '[' {
				depth++
			}
			if ch == ']' {
				depth--
				if depth == 0 {
					last = i
					break
				}
			}
		}
	}
	if !regexp.MustCompile(`^[A-Z][a-z]?$`).MatchString(c) && last != len(c)-1 {
		c = "(" + c + ")"
	}
	return c + strconv.FormatInt(k, 10)
}
func find(list []Species, name string, start, end int) int {
	for i := start; i < end; i++ {
		if list[i].name() == name {
			return i
		}
	}
	return -1
}

var counts = map[string]int{"ELEMENT": 1, "PARSE": 1, "MASS": 1, "PERCENT": 1, "EMPIRICAL": 1, "DBE": 1, "OXSTATE": 1, "MOLES": 2, "GRAMS": 2, "MOLECULAR": 2, "SALT": 2, "HEAT": 2, "COMBUST": 3, "HEATS": 0, "DERIVE": -2, "BALANCE": -1, "MATRIX": -1, "CHECK": -1, "DELTAH": -1, "REDOX": -3, "HALF": -3, "STOICH": -4, "LIMITING": -4, "YIELD": -4}

type Chemistry struct {
	heats Composition
}

func (e *Chemistry) execute(line string) ([]string, error) {
	words := strings.Fields(line)
	cmd, a := words[0], words[1:]
	n := len(a)
	expected, ok := counts[cmd]
	if !ok {
		return nil, problem("unknown command " + cmd)
	}
	if (expected >= 0 && n != expected) || (expected == -1 && n < 1) || (expected == -2 && (n < 2 || n%2 != 0)) || (expected == -3 && n < 2) {
		return nil, problem("wrong argument count for " + cmd)
	}
	if cmd == "ELEMENT" {
		w, ok := W[a[0]]
		if !ok {
			return nil, problem("unknown element " + a[0])
		}
		z := 0
		for i, s := range symbols {
			if s == a[0] {
				z = i + 1
				break
			}
		}
		return []string{fmt.Sprintf("%s (Z = %d) %s u", a[0], z, dec(w, 3))}, nil
	}
	if cmd == "HEATS" {
		keys := []string{}
		for s := range e.heats {
			keys = append(keys, s)
		}
		sort.Strings(keys)
		out := []string{}
		for _, s := range keys {
			out = append(out, s+" "+ent(e.heats[s])+" kJ/mol")
		}
		if len(out) == 0 {
			out = append(out, "no enthalpies")
		}
		return out, nil
	}
	if cmd == "HEAT" {
		if _, err := species(a[0], false); err != nil {
			return nil, err
		}
		h, err := enthalpy(a[1])
		if err != nil {
			return nil, err
		}
		text := "dHf(" + a[0] + ") = " + ent(h) + " kJ/mol"
		if old, ok := e.heats[a[0]]; ok {
			text += " (was " + ent(old) + ")"
		}
		e.heats[a[0]] = h
		return []string{text}, nil
	}
	if cmd == "DERIVE" {
		b := Composition{}
		total := int64(0)
		for i := 0; i < n; i += 2 {
			s := a[i]
			if _, ok := W[s]; !ok {
				return nil, problem("unknown element " + s)
			}
			if _, ok := b[s]; ok {
				return nil, problem("duplicate element " + s)
			}
			q, err := quantity(a[i+1])
			if err != nil {
				return nil, err
			}
			if q > 100000 {
				return nil, problem("invalid percentage " + a[i+1])
			}
			b[s] = q
			total += q
		}
		if abs(total-100000) > 1000 {
			return nil, problem("percentages sum to " + dec(total, 3))
		}
		return ratios(b), nil
	}
	if cmd == "COMBUST" {
		qs := []int64{}
		for _, s := range a {
			q, err := quantity(s)
			if err != nil {
				return nil, err
			}
			qs = append(qs, q)
		}
		sample, c, h := qs[0], qs[1]*12011/44009, qs[2]*2016/18015
		o := sample - c - h
		if c == 0 || h == 0 || 100*o < -sample {
			return nil, problem("inconsistent masses")
		}
		b := Composition{"C": c, "H": h}
		if 100*o > sample {
			b["O"] = o
		}
		out := []string{}
		for _, s := range order(b) {
			out = append(out, "mass "+s+" "+dec(b[s], 3)+" g")
		}
		return append(out, ratios(b)...), nil
	}
	if strings.Contains(" PARSE MASS PERCENT EMPIRICAL DBE OXSTATE MOLES GRAMS MOLECULAR SALT ", " "+cmd+" ") {
		f, err := formula(a[0], a[0])
		if err != nil {
			return nil, err
		}
		c, q, m := f.c, f.q, mass(f.c)
		es := order(c)
		out := []string{}
		switch cmd {
		case "PARSE":
			for _, s := range es {
				out = append(out, fmt.Sprintf("%s %d", s, c[s]))
			}
			return []string{hill(c, q) + " (" + strings.Join(out, ", ") + "; charge " + signed(q) + ")"}, nil
		case "MASS":
			return []string{"M(" + a[0] + ") = " + dec(m, 3) + " g/mol"}, nil
		case "PERCENT":
			for _, s := range es {
				out = append(out, s+" "+dec(10000*c[s]*W[s]/m, 2)+"%")
			}
			return out, nil
		case "EMPIRICAL":
			g := int64(0)
			for _, x := range c {
				g = gcd(g, x)
			}
			b := Composition{}
			for s, x := range c {
				b[s] = x / g
			}
			return []string{fmt.Sprintf("%s (n = %d)", hill(b, 0), g)}, nil
		case "DBE":
			if q != 0 {
				return nil, problem("charged formula " + a[0])
			}
			t := int64(2)
			for _, s := range es {
				v, ok := valence[s]
				if !ok {
					return nil, problem("no valence for " + s)
				}
				t += c[s] * (v - 2)
			}
			sign := ""
			if t < 0 {
				sign = "-"
			}
			return []string{fmt.Sprintf("DBE = %s%d.%d", sign, abs(t)/2, 5*(abs(t)%2))}, nil
		case "OXSTATE":
			st := map[string]*big.Rat{}
			last := ""
			assign := func(s string, x int64) {
				st[s] = new(big.Rat).SetInt64(x)
				last = s
			}
			if len(es) == 1 {
				st[es[0]] = new(big.Rat).SetFrac64(q, c[es[0]])
			} else {
				if c["F"] > 0 {
					assign("F", -1)
				}
				for _, s := range es {
					if x, ok := metals[s]; ok {
						assign(s, x)
					}
				}
				if c["H"] > 0 {
					only := true
					for _, s := range es {
						if s != "H" && metals[s] == 0 {
							only = false
						}
					}
					x := int64(1)
					if only {
						x = -1
					}
					assign("H", x)
				}
				if c["O"] > 0 {
					assign("O", -2)
				} else if c["F"] == 0 {
					for _, s := range []string{"Cl", "Br", "I"} {
						if c[s] > 0 {
							assign(s, -1)
							break
						}
					}
				}
				u := []string{}
				total := int64(0)
				for _, s := range es {
					if x, ok := st[s]; ok {
						total += c[s] * x.Num().Int64()
					} else {
						u = append(u, s)
					}
				}
				if len(u) > 1 {
					return []string{"indeterminate: " + strings.Join(u, " ")}, nil
				}
				if len(u) == 1 {
					st[u[0]] = new(big.Rat).SetFrac64(q-total, c[u[0]])
				} else if total != q {
					st[last] = new(big.Rat).SetFrac64(q-total+c[last]*st[last].Num().Int64(), c[last])
				}
			}
			for _, s := range es {
				out = append(out, s+" "+signedRat(st[s]))
			}
			return []string{strings.Join(out, ", ")}, nil
		case "SALT":
			b, err := formula(a[1], a[1])
			if err != nil {
				return nil, err
			}
			if q <= 0 {
				return nil, problem("not a cation " + a[0])
			}
			if b.q >= 0 {
				return nil, problem("not an anion " + a[1])
			}
			for _, s := range a {
				if strings.Contains(s, ".") {
					return nil, problem("hydrate ion " + s)
				}
			}
			g := gcd(q, b.q)
			x, y := -b.q/g, q/g
			z := add(scale(c, x), b.c, y)
			return []string{group(a[0], x) + group(a[1], y) + " (" + hill(z, 0) + ", " + dec(mass(z), 3) + " g/mol)"}, nil
		}
		if cmd == "MOLECULAR" && q != 0 {
			return nil, problem("charged formula " + a[0])
		}
		x, err := quantity(a[1])
		if err != nil {
			return nil, err
		}
		if cmd == "MOLES" {
			return []string{dec(x, 3) + " g " + a[0] + " = " + dec(x*1000000/m, 6) + " mol"}, nil
		}
		if cmd == "GRAMS" {
			return []string{dec(x, 3) + " mol " + a[0] + " = " + dec(x*m/1000, 3) + " g"}, nil
		}
		k := (2*x + m) / (2 * m)
		if k == 0 || 10*abs(x-k*m) > m {
			return []string{"no integer multiple (ratio " + dec(1000*x/m, 3) + ")"}, nil
		}
		return []string{fmt.Sprintf("%s (n = %d, %s g/mol)", hill(scale(c, k), 0), k, dec(k*m, 3))}, nil
	}
	if cmd == "REDOX" || cmd == "HALF" {
		if a[0] != "acidic" && a[0] != "basic" {
			return nil, problem("invalid medium " + a[0])
		}
		eq, err := equation(a[1:], false)
		if err != nil {
			return nil, err
		}
		for _, s := range eq.list {
			if s.f == "H^+" || s.f == "OH^-" || s.f == "H2O" {
				return nil, problem("reserved species " + s.name())
			}
		}
		ion := "H^+"
		if a[0] == "basic" {
			ion = "OH^-"
		}
		x, _ := species(ion, false)
		water, _ := species("H2O", false)
		list := append(append([]Species(nil), eq.list...), x, water)
		if cmd == "HALF" {
			list = append(list, Species{"e^-", "", 1, Formula{Composition{}, -1}})
		}
		sign := eq.signs()
		for len(sign) < len(list) {
			sign = append(sign, 1)
		}
		v, err := coefficients(list, sign, len(eq.list))
		if err != nil {
			return nil, err
		}
		left, right := []string{}, []string{}
		for i, s := range eq.list {
			if i < eq.r {
				left = append(left, term(s.name(), v[i]))
			} else {
				right = append(right, term(s.name(), v[i]))
			}
		}
		for i := len(eq.list); i < len(list); i++ {
			if v[i] > 0 {
				left = append(left, term(list[i].name(), v[i]))
			} else if v[i] < 0 {
				right = append(right, term(list[i].name(), -v[i]))
			}
		}
		out := []string{strings.Join(left, " + ") + " -> " + strings.Join(right, " + ")}
		if cmd == "HALF" {
			kind := "no electron transfer"
			if v[len(v)-1] > 0 {
				kind = "reduction"
			} else if v[len(v)-1] < 0 {
				kind = "oxidation"
			}
			out = append(out, kind)
		}
		return out, nil
	}
	eqWords, rest := a, []string{}
	if cmd == "STOICH" || cmd == "LIMITING" || cmd == "YIELD" {
		index, count := -1, 0
		for i, s := range a {
			if s == ":" {
				index = i
				count++
			}
		}
		if count != 1 {
			return nil, problem("invalid separator")
		}
		eqWords, rest = a[:index], a[index+1:]
		if (cmd == "STOICH" && len(rest) != 2) || (cmd == "YIELD" && len(rest) != 4) {
			return nil, problem("wrong argument count for " + cmd)
		}
	}
	eq, err := equation(eqWords, cmd == "CHECK")
	if err != nil {
		return nil, err
	}
	list, r, sign := eq.list, eq.r, eq.signs()
	if cmd == "MATRIX" {
		labels, rows := matrix(list, sign)
		rank, basis := nullspace(rows, len(list))
		names := []string{}
		for _, s := range list {
			names = append(names, s.name())
		}
		out := []string{"columns: " + strings.Join(names, " ")}
		for i, row := range rows {
			parts := []string{}
			for _, x := range row {
				parts = append(parts, strconv.FormatInt(x, 10))
			}
			out = append(out, labels[i]+": "+strings.Join(parts, " "))
		}
		out = append(out, fmt.Sprintf("rank %d, nullity %d", rank, len(basis)))
		for _, row := range basis {
			parts := []string{}
			for _, x := range row {
				parts = append(parts, strconv.FormatInt(x, 10))
			}
			out = append(out, "null: "+strings.Join(parts, " "))
		}
		return out, nil
	}
	if cmd == "CHECK" {
		labels, rows := matrix(list, sign)
		diff := []string{}
		for i, row := range rows {
			l, rr := int64(0), int64(0)
			for j, x := range row {
				if j < r {
					l += x * list[j].coefficient
				} else {
					rr -= x * list[j].coefficient
				}
			}
			if l != rr {
				ls, rs := strconv.FormatInt(l, 10), strconv.FormatInt(rr, 10)
				if labels[i] == "charge" {
					ls, rs = signed(l), signed(rr)
				}
				diff = append(diff, labels[i]+": "+ls+" != "+rs)
			}
		}
		if len(diff) > 0 {
			return append([]string{"not balanced"}, diff...), nil
		}
		g := int64(0)
		for _, s := range list {
			g = gcd(g, s.coefficient)
		}
		if g == 1 {
			return []string{"balanced"}, nil
		}
		return []string{fmt.Sprintf("balanced, not in lowest terms (gcd %d)", g)}, nil
	}
	target, product := -1, -1
	qs := []int64{}
	if cmd == "DELTAH" {
		for _, s := range list {
			if _, ok := e.heats[s.name()]; !ok {
				return nil, problem("no enthalpy for " + s.name())
			}
		}
	}
	if cmd == "STOICH" {
		target = find(list, rest[0], 0, len(list))
		if target < 0 {
			return nil, problem("species " + rest[0] + " not in equation")
		}
		q, err := quantity(rest[1])
		if err != nil {
			return nil, err
		}
		qs = append(qs, q)
	}
	if cmd == "LIMITING" {
		if len(rest) != r {
			return nil, problem(fmt.Sprintf("expected %d masses, got %d", r, len(rest)))
		}
		for _, s := range rest {
			q, err := quantity(s)
			if err != nil {
				return nil, err
			}
			qs = append(qs, q)
		}
	}
	if cmd == "YIELD" {
		target = find(list, rest[0], 0, r)
		if target < 0 {
			return nil, problem(rest[0] + " is not a reactant")
		}
		product = find(list, rest[2], r, len(list))
		if product < 0 {
			return nil, problem(rest[2] + " is not a product")
		}
		for _, s := range []string{rest[1], rest[3]} {
			q, err := quantity(s)
			if err != nil {
				return nil, err
			}
			qs = append(qs, q)
		}
	}
	v, err := coefficients(list, sign, len(list))
	if err != nil {
		return nil, err
	}
	out := []string{notation(eq, v)}
	if cmd == "BALANCE" {
		return out, nil
	}
	if cmd == "DELTAH" {
		h := int64(0)
		for i, s := range list {
			h -= sign[i] * v[i] * e.heats[s.name()]
		}
		kind := "thermoneutral"
		if h < 0 {
			kind = "exothermic"
		} else if h > 0 {
			kind = "endothermic"
		}
		return append(out, "dH = "+ent(h)+" kJ ("+kind+")"), nil
	}
	if cmd == "STOICH" {
		d := v[target] * list[target].mass()
		for i, s := range list {
			x := qs[0] * v[i]
			out = append(out, s.name()+" "+dec(x*1000000/d, 6)+" mol "+dec(x*s.mass()/d, 3)+" g"+gas(s, x, d))
		}
		return out, nil
	}
	if cmd == "YIELD" {
		t := qs[0] * v[product] * list[product].mass() / (v[target] * list[target].mass())
		out = append(out, "theoretical "+dec(t, 3)+" g", "actual "+dec(qs[1], 3)+" g")
		yield := "yield undefined"
		if t != 0 {
			yield = "yield " + dec(qs[1]*10000/t, 2) + "%"
		}
		return append(out, yield), nil
	}
	l := 0
	for i := 1; i < r; i++ {
		if qs[i]*v[l]*list[l].mass() < qs[l]*v[i]*list[i].mass() {
			l = i
		}
	}
	d := v[l] * list[l].mass()
	out = append(out, "limiting "+list[l].name(), "extent "+dec(qs[l]*1000000/d, 6)+" mol")
	for i := r; i < len(list); i++ {
		out = append(out, "product "+list[i].name()+" "+dec(qs[l]*v[i]*list[i].mass()/d, 3)+" g"+gas(list[i], qs[l]*v[i], d))
	}
	for i := 0; i < r; i++ {
		if i != l {
			out = append(out, "remaining "+list[i].name()+" "+dec((qs[i]*d-qs[l]*v[i]*list[i].mass())/d, 3)+" g")
		}
	}
	return out, nil
}
func main() {
	in := bufio.NewScanner(os.Stdin)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	in.Scan()
	n, _ := strconv.Atoi(in.Text())
	e := Chemistry{Composition{}}
	for i := 0; i < n && in.Scan(); i++ {
		lines, err := e.execute(in.Text())
		if err != nil {
			fmt.Fprintln(out, err)
		} else {
			for _, s := range lines {
				fmt.Fprintln(out, s)
			}
		}
		out.Flush()
	}
}
