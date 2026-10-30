package main

import "fmt"

func instructionLine(s *Instruction) CodeLine { return CodeLine{Instruction: s} }
func rewrite(f *Function, replacements map[int][]CodeLine, insertions map[int][]CodeLine) {
	out := []CodeLine{}
	number := 0
	for i, line := range f.Code {
		out = append(out, insertions[i]...)
		if line.Instruction != nil {
			number++
			if replacement, found := replacements[number]; found {
				out = append(out, replacement...)
				continue
			}
		}
		out = append(out, line)
	}
	out = append(out, insertions[len(f.Code)]...)
	f.Code = out
}
func folded(s *Instruction) (*Instruction, bool) {
	if s.Kind != "bin" && s.Kind != "if" {
		return s, false
	}
	a, b := s.A, s.B
	if a.IsConstant && b.IsConstant {
		if (s.Operator == "/" || s.Operator == "%") && b.Constant == 0 {
			return s, false
		}
		value := calculate(s.Operator, a.Constant, b.Constant)
		if s.Kind == "if" {
			if value != 0 {
				return &Instruction{Kind: "goto", Name: s.Name}, true
			}
			return nil, true
		}
		if value >= -2147483648 && value <= 2147483647 {
			return &Instruction{Kind: "copy", Destination: s.Destination, A: constant(value)}, true
		}
		return s, false
	}
	if s.Kind != "bin" || a.IsConstant == b.IsConstant {
		return s, false
	}
	replacement := Operand{}
	changed := true
	switch {
	case s.Operator == "+" && (a.IsConstant && a.Constant == 0 || b.IsConstant && b.Constant == 0):
		if a.IsConstant {
			replacement = b
		} else {
			replacement = a
		}
	case s.Operator == "-" && b.IsConstant && b.Constant == 0:
		replacement = a
	case s.Operator == "*" && (a.IsConstant && a.Constant == 1 || b.IsConstant && b.Constant == 1):
		if a.IsConstant {
			replacement = b
		} else {
			replacement = a
		}
	case s.Operator == "/" && b.IsConstant && b.Constant == 1:
		replacement = a
	case s.Operator == "*" && (a.IsConstant && a.Constant == 0 || b.IsConstant && b.Constant == 0):
		replacement = constant(0)
	default:
		changed = false
	}
	if !changed {
		return s, false
	}
	return &Instruction{Kind: "copy", Destination: s.Destination, A: replacement}, true
}
func cseReplacements(f *Function, g *CFG, sources, candidates Set[int]) (string, map[int][]CodeLine) {
	f.TemporarySerial++
	temporary := fmt.Sprintf("_t%d", f.TemporarySerial)
	replacements := map[int][]CodeLine{}
	for n := range sources {
		old := g.Instructions[n]
		copy := *old
		copy.Destination = temporary
		replacements[n] = []CodeLine{instructionLine(&copy), instructionLine(&Instruction{Kind: "copy", Destination: old.Destination, A: Operand{Variable: temporary}})}
	}
	for n := range candidates {
		replacements[n] = []CodeLine{instructionLine(&Instruction{Kind: "copy", Destination: g.Instructions[n].Destination, A: Operand{Variable: temporary}})}
	}
	return temporary, replacements
}
func hoist(f *Function, g *CFG, loop *Loop, moves []int) string {
	header := g.Blocks[loop.Header]
	outside := []int{}
	for _, pred := range header.Predecessors {
		if !loop.Blocks[pred] {
			outside = append(outside, pred)
		}
	}
	replacements := map[int][]CodeLine{}
	instructions := []CodeLine{}
	for _, n := range moves {
		replacements[n] = nil
		instructions = append(instructions, instructionLine(g.Instructions[n]))
	}
	position := 0
	destination := ""
	insertion := instructions
	if loop.Header != 1 && len(outside) == 1 && len(g.Blocks[outside[0]].Successors) == 1 && g.Blocks[outside[0]].Successors[0] == loop.Header {
		preheader := g.Blocks[outside[0]]
		last := g.Instructions[preheader.Last]
		position = g.Positions[preheader.Last]
		if last.Kind != "goto" && last.Kind != "if" {
			position++
		}
		destination = fmt.Sprintf("B%d", preheader.Number)
	} else {
		f.PreheaderSerial++
		label := fmt.Sprintf("_p%d", f.PreheaderSerial)
		position = header.Start
		insertion = append([]CodeLine{{Label: label}}, instructions...)
		destination = "new " + label
		labels := Set[string]{}
		for _, name := range header.Labels {
			labels[name] = true
		}
		for _, pred := range outside {
			n := g.Blocks[pred].Last
			old := g.Instructions[n]
			if (old.Kind == "goto" || old.Kind == "if") && labels[old.Name] {
				copy := *old
				copy.Name = label
				replacements[n] = []CodeLine{instructionLine(&copy)}
			}
		}
	}
	rewrite(f, replacements, map[int][]CodeLine{position: insertion})
	return destination
}
func removeUnreachable(f *Function, g *CFG) []string {
	records := []string{}
	deleted := Set[int]{}
	for _, b := range g.Blocks[1:] {
		if !b.Reachable {
			records = append(records, fmt.Sprintf("remove block B%d", b.Number))
			for i := b.Start; i < b.End; i++ {
				deleted[i] = true
			}
		}
	}
	remaining := []CodeLine{}
	for i, line := range f.Code {
		if !deleted[i] {
			remaining = append(remaining, line)
		}
	}
	jumps := Set[int]{}
	for i, line := range remaining {
		s := line.Instruction
		if s == nil || s.Kind != "goto" && s.Kind != "if" {
			continue
		}
		for j := i + 1; j < len(remaining) && remaining[j].Instruction == nil; j++ {
			if remaining[j].Label == s.Name {
				jumps[s.Number] = true
				break
			}
		}
	}
	for _, n := range sortedInts(jumps) {
		records = append(records, fmt.Sprintf("remove jump #%d", n))
	}
	withoutJumps := []CodeLine{}
	targets := Set[string]{}
	for _, line := range remaining {
		s := line.Instruction
		if s != nil && jumps[s.Number] {
			continue
		}
		withoutJumps = append(withoutJumps, line)
		if s != nil && (s.Kind == "goto" || s.Kind == "if") {
			targets[s.Name] = true
		}
	}
	f.Code = nil
	for _, line := range withoutJumps {
		if line.Instruction == nil && !targets[line.Label] {
			records = append(records, "remove label "+line.Label)
		} else {
			f.Code = append(f.Code, line)
		}
	}
	return records
}
