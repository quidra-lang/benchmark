package main

import (
	"fmt"
	"os"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
)

var nameForm = regexp.MustCompile(`^[A-Za-z0-9_-]{1,32}$`)

func abs(a int) int {
	if a < 0 {
		return -a
	}
	return a
}
func analyze(m *Molecule, elements map[string]Element) *ParseError {
	detectRings(m)
	for _, b := range m.Bonds {
		b.Type = symbolType(b.Symbol)
		if b.Type == 0 {
			b.Type = 1
			if b.Ring && m.Atoms[b.A].Aromatic && m.Atoms[b.B].Aromatic {
				b.Type = 4
			}
		}
	}
	if failure := kekulize(m, elements); failure != nil {
		return failure
	}
	for i, a := range m.Atoms {
		if a.Bracket {
			valences := elements[a.Symbol].Valences
			if m.Multiplicity(i)+a.Hydrogens > valences[len(valences)-1]+abs(a.Charge) {
				return &ParseError{"bad valence", a.Column}
			}
		} else {
			hydrogens, ok := organicHydrogens(m, i, elements)
			if !ok {
				return &ParseError{"bad valence", a.Column}
			}
			a.Hydrogens = hydrogens
		}
	}
	return nil
}
func properties(m *Molecule, elements map[string]Element) {
	counts := map[string]int{}
	hydrogens := 0
	heavyDegree := make([]int, len(m.Atoms))
	triple := make([]bool, len(m.Atoms))
	for i, a := range m.Atoms {
		counts[a.Symbol]++
		hydrogens += a.Hydrogens
		m.Charge += a.Charge
		if a.Mass != 0 {
			m.Weight += a.Mass * 1000
		} else {
			m.Weight += elements[a.Symbol].Weight
		}
		if a.Symbol != "H" {
			m.Heavy++
		}
		attached := a.Hydrogens
		for _, e := range m.Adjacent[i] {
			b := m.Bonds[e]
			other := m.Atoms[b.Other(i)]
			if other.Symbol == "H" {
				attached++
			} else {
				heavyDegree[i]++
			}
			if b.Multiplicity == 3 {
				triple[i] = true
			}
		}
		if a.Symbol == "N" || a.Symbol == "O" {
			m.Acceptors++
			if attached > 0 {
				m.Donors++
			}
		}
	}
	counts["H"] += hydrogens
	m.Weight += hydrogens * elements["H"].Weight
	symbols := []string{}
	for symbol, count := range counts {
		if count > 0 {
			symbols = append(symbols, symbol)
		}
	}
	sort.Strings(symbols)
	if counts["C"] > 0 {
		hill := []string{"C"}
		if counts["H"] > 0 {
			hill = append(hill, "H")
		}
		for _, symbol := range symbols {
			if symbol != "C" && symbol != "H" {
				hill = append(hill, symbol)
			}
		}
		symbols = hill
	}
	for _, symbol := range symbols {
		m.Formula += symbol
		if counts[symbol] > 1 {
			m.Formula += strconv.Itoa(counts[symbol])
		}
	}
	for _, b := range m.Bonds {
		if b.Multiplicity == 1 && !b.Ring && heavyDegree[b.A] >= 2 && heavyDegree[b.B] >= 2 && !triple[b.A] && !triple[b.B] {
			m.Rotatable++
		}
	}
	violations := 0
	if m.Weight > 500000 {
		violations++
	}
	if m.Donors > 5 {
		violations++
	}
	if m.Acceptors > 10 {
		violations++
	}
	m.Lipinski = "pass"
	if violations >= 2 {
		m.Lipinski = "fail"
	}
}
func scaffold(m *Molecule, elements map[string]Element) string {
	if len(m.Rings) == 0 {
		return ""
	}
	remaining := make([]bool, len(m.Atoms))
	for i := range remaining {
		remaining[i] = true
	}
	for {
		remove := -1
		for a := range m.Atoms {
			if !remaining[a] || m.RingAtoms[a] {
				continue
			}
			degree := 0
			for _, e := range m.Adjacent[a] {
				if remaining[m.Bonds[e].Other(a)] {
					degree++
				}
			}
			if degree == 1 {
				remove = a
				break
			}
		}
		if remove < 0 {
			break
		}
		remaining[remove] = false
	}
	keep := slices.Clone(remaining)
	for _, b := range m.Bonds {
		if b.Multiplicity == 2 {
			if remaining[b.A] {
				keep[b.B] = true
			}
			if remaining[b.B] {
				keep[b.A] = true
			}
		}
	}
	s := &Molecule{}
	renumber := make([]int, len(m.Atoms))
	for i := range renumber {
		renumber[i] = -1
	}
	for i, a := range m.Atoms {
		if !keep[i] {
			continue
		}
		copy := *a
		for _, e := range m.Adjacent[i] {
			b := m.Bonds[e]
			if !keep[b.Other(i)] {
				copy.Hydrogens += b.Multiplicity
			}
		}
		renumber[i] = len(s.Atoms)
		s.Atoms = append(s.Atoms, &copy)
	}
	for _, b := range m.Bonds {
		if keep[b.A] && keep[b.B] {
			copy := *b
			copy.A, copy.B = renumber[b.A], renumber[b.B]
			s.Bonds = append(s.Bonds, &copy)
		}
	}
	s.Build()
	canonicalRanks(s, elements)
	return canonicalSMILES(s, elements)
}

type RingSystem struct {
	Rings []int
	Kind  string
	Atoms int
}

func ringRelation(m *Molecule, first, second []int) string {
	common := []int{}
	for _, a := range first {
		if slices.Contains(second, a) {
			common = append(common, a)
		}
	}
	if len(common) == 1 {
		return "spiro"
	}
	if len(common) == 2 && m.Bond(common[0], common[1]) != nil {
		return "fused"
	}
	if len(common) >= 2 {
		return "bridged"
	}
	return ""
}
func ringSystems(m *Molecule) []RingSystem {
	adjacent := make([][]int, len(m.Rings))
	for i, a := range m.Rings {
		for j := i + 1; j < len(m.Rings); j++ {
			if ringRelation(m, a, m.Rings[j]) != "" {
				adjacent[i] = append(adjacent[i], j)
				adjacent[j] = append(adjacent[j], i)
			}
		}
	}
	seen := make([]bool, len(m.Rings))
	out := []RingSystem{}
	for first := range m.Rings {
		if seen[first] {
			continue
		}
		queue := []int{first}
		seen[first] = true
		for h := 0; h < len(queue); h++ {
			for _, r := range adjacent[queue[h]] {
				if !seen[r] {
					seen[r] = true
					queue = append(queue, r)
				}
			}
		}
		slices.Sort(queue)
		atoms := map[int]bool{}
		kind := "isolated"
		if len(queue) > 1 {
			kind = "spiro"
		}
		for i, r := range queue {
			for _, a := range m.Rings[r] {
				atoms[a] = true
			}
			for _, s := range queue[i+1:] {
				relation := ringRelation(m, m.Rings[r], m.Rings[s])
				if relation == "bridged" {
					kind = "bridged"
				} else if relation == "fused" && kind != "bridged" {
					kind = "fused"
				}
			}
		}
		out = append(out, RingSystem{queue, kind, len(atoms)})
	}
	return out
}
func ringAromatic(m *Molecule, ring []int) bool {
	for _, a := range ring {
		if !m.Atoms[a].Aromatic {
			return false
		}
	}
	return true
}
func ints(a []int, separator string, offset int) string {
	out := make([]string, len(a))
	for i, n := range a {
		out[i] = strconv.Itoa(n + offset)
	}
	return strings.Join(out, separator)
}
func memberNames(molecules []*Molecule, indices []int) string {
	names := make([]string, len(indices))
	for i, j := range indices {
		names[i] = molecules[j].Name
	}
	return strings.Join(names, ",")
}
func canonicalParagraphs(molecules []*Molecule) [][]string {
	canonGroups, formulaGroups, scaffoldGroups := map[string][]int{}, map[string][]int{}, map[string][]int{}
	canonOrder, formulaOrder := []string{}, []string{}
	acyclic := 0
	canonical := []string{}
	for i, m := range molecules {
		if _, ok := canonGroups[m.Canonical]; !ok {
			canonOrder = append(canonOrder, m.Canonical)
		}
		canonGroups[m.Canonical] = append(canonGroups[m.Canonical], i)
		if _, ok := formulaGroups[m.Formula]; !ok {
			formulaOrder = append(formulaOrder, m.Formula)
		}
		formulaGroups[m.Formula] = append(formulaGroups[m.Formula], i)
		if m.Scaffold == "" {
			acyclic++
		} else {
			scaffoldGroups[m.Scaffold] = append(scaffoldGroups[m.Scaffold], i)
		}
	}
	canonical = append(canonical, fmt.Sprintf("CANONICAL molecules=%d unique=%d", len(molecules), len(canonGroups)))
	for _, m := range molecules {
		charge := strconv.Itoa(m.Charge)
		if m.Charge > 0 {
			charge = "+" + charge
		}
		canonical = append(canonical, fmt.Sprintf("%s %s classes=%d charge=%s", m.Name, m.Canonical, m.Classes, charge))
	}
	duplicates := []string{}
	duplicateCount, duplicateMolecules := 0, 0
	for _, key := range canonOrder {
		indices := canonGroups[key]
		if len(indices) < 2 {
			continue
		}
		duplicateCount++
		duplicateMolecules += len(indices)
		duplicates = append(duplicates, fmt.Sprintf("group %d %s members=%s", duplicateCount, key, memberNames(molecules, indices)))
	}
	duplicates = append([]string{fmt.Sprintf("DUPLICATES groups=%d molecules=%d", duplicateCount, duplicateMolecules)}, duplicates...)
	isomers := []string{}
	isomerCount := 0
	for _, formula := range formulaOrder {
		indices := formulaGroups[formula]
		forms := []string{}
		for _, i := range indices {
			forms = append(forms, molecules[i].Canonical)
		}
		distinct := distinctStrings(forms)
		if distinct < 2 {
			continue
		}
		isomerCount++
		isomers = append(isomers, fmt.Sprintf("isomer %d %s forms=%d members=%s", isomerCount, formula, distinct, memberNames(molecules, indices)))
	}
	isomers = append([]string{fmt.Sprintf("ISOMERS groups=%d", isomerCount)}, isomers...)
	scaffolds := []string{fmt.Sprintf("SCAFFOLDS distinct=%d acyclic=%d", len(scaffoldGroups), acyclic)}
	keys := []string{}
	for key := range scaffoldGroups {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		a, b := keys[i], keys[j]
		if len(scaffoldGroups[a]) != len(scaffoldGroups[b]) {
			return len(scaffoldGroups[a]) > len(scaffoldGroups[b])
		}
		return a < b
	})
	for i, key := range keys {
		indices := scaffoldGroups[key]
		scaffolds = append(scaffolds, fmt.Sprintf("scaffold %d %s count=%d members=%s", i+1, key, len(indices), memberNames(molecules, indices)))
	}
	return [][]string{canonical, duplicates, isomers, scaffolds}
}
func ringParagraphs(molecules []*Molecule) [][]string {
	out := [][]string{}
	cyclic, total, aromatic := 0, 0, 0
	sizes := map[int]int{}
	kinds := map[string]int{}
	for _, m := range molecules {
		if len(m.Rings) == 0 {
			continue
		}
		cyclic++
		total += len(m.Rings)
		systems := ringSystems(m)
		aromaticCount, ringAtoms, ringBonds := 0, 0, 0
		for _, v := range m.RingAtoms {
			if v {
				ringAtoms++
			}
		}
		for _, b := range m.Bonds {
			if b.Ring {
				ringBonds++
			}
		}
		for _, r := range m.Rings {
			sizes[len(r)]++
			if ringAromatic(m, r) {
				aromaticCount++
			}
		}
		aromatic += aromaticCount
		paragraph := []string{fmt.Sprintf("MOLECULE %s atoms=%d bonds=%d rings=%d aromatic=%d systems=%d ring_atoms=%d ring_bonds=%d", m.Name, len(m.Atoms), len(m.Bonds), len(m.Rings), aromaticCount, len(systems), ringAtoms, ringBonds)}
		for i, r := range m.Rings {
			flag := "no"
			if ringAromatic(m, r) {
				flag = "yes"
			}
			hetero := 0
			for _, a := range r {
				if m.Atoms[a].Symbol != "C" {
					hetero++
				}
			}
			paragraph = append(paragraph, fmt.Sprintf("ring %d size=%d aromatic=%s hetero=%d atoms=%s", i+1, len(r), flag, hetero, ints(r, "-", 1)))
		}
		for i, s := range systems {
			kinds[s.Kind]++
			paragraph = append(paragraph, fmt.Sprintf("system %d kind=%s rings=%s atoms=%d", i+1, s.Kind, ints(s.Rings, ",", 1), s.Atoms))
		}
		double := []string{}
		for _, b := range m.Bonds {
			if b.Type == 4 && b.Multiplicity == 2 {
				double = append(double, fmt.Sprintf("%d=%d", b.A+1, b.B+1))
			}
		}
		bonds := "-"
		if len(double) > 0 {
			bonds = strings.Join(double, " ")
		}
		paragraph = append(paragraph, "kekule "+bonds)
		out = append(out, paragraph)
	}
	sizeValues := []int{}
	for size := range sizes {
		sizeValues = append(sizeValues, size)
	}
	slices.Sort(sizeValues)
	line := "sizes"
	for _, size := range sizeValues {
		line += fmt.Sprintf(" %d=%d", size, sizes[size])
	}
	if len(sizeValues) == 0 {
		line += " -"
	}
	out = append(out, []string{fmt.Sprintf("SUMMARY molecules=%d cyclic=%d rings=%d aromatic=%d", len(molecules), cyclic, total, aromatic), line, fmt.Sprintf("systems isolated=%d fused=%d spiro=%d bridged=%d", kinds["isolated"], kinds["fused"], kinds["spiro"], kinds["bridged"])})
	return out
}

type Query struct {
	Kind, ID  string
	Arguments []string
	Pattern   *Molecule
	Threshold Fraction
	Count     int
}

func number(s string, low, high int) bool {
	if s == "" || len(s) > 2 || (len(s) > 1 && s[0] == '0') {
		return false
	}
	for i := range s {
		if !digit(s[i]) {
			return false
		}
	}
	n := integer(s)
	return n >= low && n <= high
}
func threshold(s string) (Fraction, bool) {
	a := strings.Split(s, "/")
	if len(a) != 2 || !number(a[0], 0, 99) || !number(a[1], 1, 99) {
		return Fraction{}, false
	}
	n, d := integer(a[0]), integer(a[1])
	if n > d {
		return Fraction{}, false
	}
	return fraction(n, d), true
}
func checkQuery(tokens []string, seen map[string]bool, byName map[string]int, elements map[string]Element) (*Query, string) {
	kind := tokens[0]
	if !slices.Contains([]string{"MATCH", "CONTAINS", "MATRIX", "NEAREST", "WITHIN", "COMPARE", "CLUSTER"}, kind) {
		return nil, "unknown query"
	}
	if len(tokens) == 1 || !nameForm.MatchString(tokens[1]) {
		return nil, "bad id"
	}
	id := tokens[1]
	if seen[id] {
		return nil, "duplicate id"
	}
	seen[id] = true
	args := tokens[2:]
	validLength := len(args) == 2
	switch kind {
	case "MATCH", "CLUSTER":
		validLength = len(args) == 1
	case "MATRIX":
		validLength = len(args) >= 2 && len(args) <= 12
	}
	if !validLength {
		return nil, "bad arguments"
	}
	q := &Query{Kind: kind, ID: id, Arguments: args}
	switch kind {
	case "MATCH":
		pattern, failure := parseSMILES(args[0], elements, true)
		if failure != nil {
			return nil, fmt.Sprintf("bad pattern %s at column %d", failure.Reason, failure.Column)
		}
		q.Pattern = pattern
	case "CLUSTER":
		value, ok := threshold(args[0])
		if !ok {
			return nil, "bad threshold"
		}
		q.Threshold = value
	case "CONTAINS", "MATRIX", "COMPARE":
		for _, name := range args {
			if _, ok := byName[name]; !ok {
				return nil, "unknown molecule " + name
			}
		}
		names := map[string]bool{}
		for _, name := range args {
			if names[name] {
				return nil, "repeated molecule"
			}
			names[name] = true
		}
	case "NEAREST", "WITHIN":
		if _, ok := byName[args[0]]; !ok {
			return nil, "unknown molecule " + args[0]
		}
		if kind == "NEAREST" {
			if !number(args[1], 1, 99) {
				return nil, "bad count"
			}
			q.Count = integer(args[1])
		} else {
			value, ok := threshold(args[1])
			if !ok {
				return nil, "bad threshold"
			}
			q.Threshold = value
		}
	}
	return q, ""
}
func fractionText(f Fraction) string { return fmt.Sprintf("%d/%d", f.N, f.D) }
func substructureParagraphs(queries []*Query, molecules []*Molecule, byName map[string]int) [][]string {
	paragraphs := [][]string{}
	patterns, hits, contains, found := 0, 0, 0, 0
	for _, q := range queries {
		switch q.Kind {
		case "MATCH":
			patterns++
			hitLines := []string{}
			embeddingsTotal, topCount := 0, 0
			top := ""
			for _, m := range molecules {
				result := embeddings(q.Pattern, m)
				if result.Count == 0 {
					continue
				}
				hits++
				embeddingsTotal += result.Count
				hitLines = append(hitLines, fmt.Sprintf("%s count=%d unique=%d map=%s", m.Name, result.Count, result.Unique, ints(result.First, ",", 0)))
				if result.Count > topCount {
					top = m.Name
					topCount = result.Count
				}
			}
			paragraph := []string{fmt.Sprintf("MATCH %s %s atoms=%d bonds=%d hits=%d embeddings=%d", q.ID, q.Arguments[0], len(q.Pattern.Atoms), len(q.Pattern.Bonds), len(hitLines), embeddingsTotal)}
			paragraph = append(paragraph, hitLines...)
			if top != "" {
				paragraph = append(paragraph, fmt.Sprintf("top %s count=%d", top, topCount))
			}
			paragraphs = append(paragraphs, paragraph)
		case "CONTAINS":
			contains++
			x, y := molecules[byName[q.Arguments[0]]], molecules[byName[q.Arguments[1]]]
			result := embeddings(moleculePattern(x), y)
			line := fmt.Sprintf("CONTAINS %s %s %s result=", q.ID, x.Name, y.Name)
			if result.Count > 0 {
				found++
				line += fmt.Sprintf("yes count=%d unique=%d map=%s", result.Count, result.Unique, ints(result.First, ",", 0))
			} else {
				line += "no"
			}
			paragraphs = append(paragraphs, []string{line})
		}
	}
	return append(paragraphs, []string{fmt.Sprintf("SUMMARY patterns=%d hits=%d contains=%d found=%d", patterns, hits, contains, found)})
}

type SimilarityValue struct {
	Value         Fraction
	Common, Union int
}

func similarityParagraphs(queries []*Query, molecules []*Molecule, byName map[string]int) [][]string {
	n := len(molecules)
	matrix := make([][]SimilarityValue, n)
	for i := range matrix {
		matrix[i] = make([]SimilarityValue, n)
	}
	for i, a := range molecules {
		for j := i; j < n; j++ {
			value, common, union := similarity(a, molecules[j])
			record := SimilarityValue{value, common, union}
			matrix[i][j] = record
			matrix[j][i] = record
		}
	}
	fingerprints := []string{fmt.Sprintf("FINGERPRINTS molecules=%d size=1024 depth=5", n)}
	for _, m := range molecules {
		fingerprints = append(fingerprints, fmt.Sprintf("%s bits=%d paths=%d", m.Name, m.BitCount, m.Paths))
	}
	out := [][]string{fingerprints}
	for _, q := range queries {
		args := q.Arguments
		paragraph := []string{}
		switch q.Kind {
		case "MATRIX":
			indices := make([]int, len(args))
			for i, name := range args {
				indices[i] = byName[name]
			}
			paragraph = append(paragraph, fmt.Sprintf("MATRIX %s size=%d", q.ID, len(args)))
			bestI, bestJ := 0, 1
			for i, a := range indices {
				values := []string{}
				for j, b := range indices {
					values = append(values, fractionText(matrix[a][b].Value))
					if i < j && matrix[a][b].Value.Cmp(matrix[indices[bestI]][indices[bestJ]].Value) > 0 {
						bestI, bestJ = i, j
					}
				}
				paragraph = append(paragraph, "row "+args[i]+" "+strings.Join(values, " "))
			}
			paragraph = append(paragraph, fmt.Sprintf("best %s %s %s", args[bestI], args[bestJ], fractionText(matrix[indices[bestI]][indices[bestJ]].Value)))
		case "NEAREST", "WITHIN":
			base := byName[args[0]]
			order := []int{}
			for i := range molecules {
				if i != base {
					order = append(order, i)
				}
			}
			sort.Slice(order, func(i, j int) bool {
				a, b := order[i], order[j]
				comparison := matrix[base][a].Value.Cmp(matrix[base][b].Value)
				if comparison != 0 {
					return comparison > 0
				}
				return a < b
			})
			if q.Kind == "NEAREST" {
				order = order[:min(q.Count, len(order))]
				paragraph = append(paragraph, fmt.Sprintf("NEAREST %s %s count=%d", q.ID, args[0], len(order)))
			} else {
				selected := []int{}
				for _, i := range order {
					if matrix[base][i].Value.Cmp(q.Threshold) >= 0 {
						selected = append(selected, i)
					}
				}
				order = selected
				paragraph = append(paragraph, fmt.Sprintf("WITHIN %s %s threshold=%s count=%d", q.ID, args[0], fractionText(q.Threshold), len(order)))
			}
			for k, i := range order {
				value := matrix[base][i]
				paragraph = append(paragraph, fmt.Sprintf("%d %s %s common=%d", k+1, molecules[i].Name, fractionText(value.Value), value.Common))
			}
		case "COMPARE":
			a, b := byName[args[0]], byName[args[1]]
			record := matrix[a][b]
			identical := "no"
			if molecules[a].Canonical == molecules[b].Canonical {
				identical = "yes"
			}
			paragraph = append(paragraph, fmt.Sprintf("COMPARE %s %s %s bits=%d,%d common=%d union=%d tanimoto=%s identical=%s", q.ID, args[0], args[1], molecules[a].BitCount, molecules[b].BitCount, record.Common, record.Union, fractionText(record.Value), identical))
		case "CLUSTER":
			neighbors := make([][]int, n)
			order := make([]int, n)
			for i := range molecules {
				order[i] = i
				for j := range molecules {
					if i != j && matrix[i][j].Value.Cmp(q.Threshold) >= 0 {
						neighbors[i] = append(neighbors[i], j)
					}
				}
			}
			sort.Slice(order, func(i, j int) bool {
				a, b := order[i], order[j]
				if len(neighbors[a]) != len(neighbors[b]) {
					return len(neighbors[a]) > len(neighbors[b])
				}
				return a < b
			})
			assigned := make([]bool, n)
			clusters := [][]int{}
			singletons := 0
			for _, center := range order {
				if assigned[center] {
					continue
				}
				members := []int{center}
				assigned[center] = true
				for _, neighbor := range neighbors[center] {
					if !assigned[neighbor] {
						members = append(members, neighbor)
						assigned[neighbor] = true
					}
				}
				if len(members) == 1 {
					singletons++
				}
				clusters = append(clusters, members)
			}
			paragraph = append(paragraph, fmt.Sprintf("CLUSTER %s threshold=%s clusters=%d singletons=%d", q.ID, fractionText(q.Threshold), len(clusters), singletons))
			number := 0
			for _, members := range clusters {
				if len(members) == 1 {
					continue
				}
				number++
				paragraph = append(paragraph, fmt.Sprintf("cluster %d centroid=%s size=%d members=%s", number, molecules[members[0]].Name, len(members), memberNames(molecules, members)))
			}
		}
		if len(paragraph) > 0 {
			out = append(out, paragraph)
		}
	}
	return out
}
func writeLines(name string, a []string) {
	text := ""
	if len(a) > 0 {
		text = strings.Join(a, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name, []byte(text), 0644); e != nil {
		panic(e)
	}
}
func writeParagraphs(name string, paragraphs [][]string) {
	out := []string{}
	for _, p := range paragraphs {
		if len(p) == 0 {
			continue
		}
		if len(out) > 0 {
			out = append(out, "")
		}
		out = append(out, p...)
	}
	writeLines(name, out)
}
func main() {
	elements := readElements()
	molecules := []*Molecule{}
	byName := map[string]int{}
	seenNames := map[string]bool{}
	moleculeErrors, queryErrors := []string{}, []string{}
	causes := map[string]int{}
	moleculeLines := 0
	for index, line := range lines("input/molecules.smi") {
		if ignored(line) {
			continue
		}
		moleculeLines++
		tokens := strings.Split(line, " ")
		if len(tokens) != 2 || tokens[0] == "" || !nameForm.MatchString(tokens[1]) {
			moleculeErrors = append(moleculeErrors, fmt.Sprintf("line %d: bad line", index+1))
			causes["bad line"]++
			continue
		}
		name := tokens[1]
		if seenNames[name] {
			moleculeErrors = append(moleculeErrors, fmt.Sprintf("line %d %s: duplicate name", index+1, name))
			causes["duplicate name"]++
			continue
		}
		seenNames[name] = true
		m, failure := parseSMILES(tokens[0], elements, false)
		if failure == nil {
			failure = analyze(m, elements)
		}
		if failure != nil {
			moleculeErrors = append(moleculeErrors, fmt.Sprintf("line %d %s: %s at column %d", index+1, name, failure.Reason, failure.Column))
			causes[failure.Reason]++
			continue
		}
		m.Name = name
		properties(m, elements)
		canonicalRanks(m, elements)
		m.Canonical = canonicalSMILES(m, elements)
		m.Scaffold = scaffold(m, elements)
		fingerprint(m, elements)
		byName[name] = len(molecules)
		molecules = append(molecules, m)
	}
	queries := []*Query{}
	seenIDs := map[string]bool{}
	queryLines := 0
	for index, line := range lines("input/queries.txt") {
		if ignored(line) {
			continue
		}
		queryLines++
		tokens := strings.Split(line, " ")
		q, reason := checkQuery(tokens, seenIDs, byName, elements)
		if reason != "" {
			text := fmt.Sprintf("line %d", index+1)
			if reason == "unknown query" {
				text += ": unknown query"
			} else if reason == "bad id" {
				text += " " + tokens[0] + ": bad id"
			} else {
				text += " " + tokens[0] + " " + tokens[1] + ": " + reason
			}
			queryErrors = append(queryErrors, text)
			cause := reason
			if strings.HasPrefix(cause, "bad pattern ") {
				cause = "bad pattern"
			}
			if strings.HasPrefix(cause, "unknown molecule ") {
				cause = "unknown molecule"
			}
			causes[cause]++
			continue
		}
		queries = append(queries, q)
	}
	propertiesLines := []string{"name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski"}
	for _, m := range molecules {
		propertiesLines = append(propertiesLines, fmt.Sprintf("%s,%s,%d.%03d,%d,%d,%d,%d,%d,%s", m.Name, m.Formula, m.Weight/1000, m.Weight%1000, m.Heavy, len(m.Rings), m.Rotatable, m.Donors, m.Acceptors, m.Lipinski))
	}
	molErrors := append([]string{fmt.Sprintf("MOLECULES lines=%d valid=%d errors=%d", moleculeLines, len(molecules), len(moleculeErrors))}, moleculeErrors...)
	queErrors := append([]string{fmt.Sprintf("QUERIES lines=%d valid=%d errors=%d", queryLines, len(queries), len(queryErrors))}, queryErrors...)
	causeNames := []string{}
	for name := range causes {
		causeNames = append(causeNames, name)
	}
	sort.Slice(causeNames, func(i, j int) bool {
		a, b := causeNames[i], causeNames[j]
		if causes[a] != causes[b] {
			return causes[a] > causes[b]
		}
		return a < b
	})
	causeLines := []string{fmt.Sprintf("CAUSES kinds=%d", len(causes))}
	for _, name := range causeNames {
		causeLines = append(causeLines, fmt.Sprintf("%s=%d", name, causes[name]))
	}
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	writeLines("properties.csv", propertiesLines)
	writeParagraphs("canonical.txt", canonicalParagraphs(molecules))
	writeParagraphs("rings.txt", ringParagraphs(molecules))
	writeParagraphs("substructure.txt", substructureParagraphs(queries, molecules, byName))
	writeParagraphs("similarity.txt", similarityParagraphs(queries, molecules, byName))
	writeParagraphs("errors.txt", [][]string{molErrors, queErrors, causeLines})
}
