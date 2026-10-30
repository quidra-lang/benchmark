package main

import "sort"

type Instruction struct {
	Op   string
	A, B int64
	Position
	Callee *Declaration
}
type BasicBlock struct {
	First, Last int
	Successors  []int
}
type Unit struct {
	Name                string
	Function            *Declaration
	Code                []Instruction
	Start, Slots, Stack int
	Blocks              []BasicBlock
}
type LoopLabels struct{ Break, Continue int }
type Generator struct {
	Unit   *Unit
	Labels []int
	Loops  []LoopLabels
}

func jump(op string) bool        { return op == "JUMP" || op == "JUMPF" || op == "JUMPT" }
func conditional(op string) bool { return op == "JUMPF" || op == "JUMPT" }
func transfer(op string) bool    { return op == "JUMP" || op == "RET" || op == "RETV" || op == "HALT" }
func (g *Generator) emit(op string, a, b int64, pos Position, callee *Declaration) {
	g.Unit.Code = append(g.Unit.Code, Instruction{op, a, b, pos, callee})
}
func (g *Generator) label() int {
	id := len(g.Labels)
	g.Labels = append(g.Labels, -1)
	return id
}
func (g *Generator) place(label int) { g.Labels[label] = len(g.Unit.Code) }
func (g *Generator) patch() {
	for i := range g.Unit.Code {
		if jump(g.Unit.Code[i].Op) {
			g.Unit.Code[i].A = int64(g.Labels[int(g.Unit.Code[i].A)])
		}
	}
}
func (g *Generator) to(op string, label int, pos Position) { g.emit(op, int64(label), 0, pos, nil) }
func (g *Generator) expression(e *Expr) {
	pos := e.position()
	switch e.Kind {
	case "integer", "boolean":
		g.emit("PUSH", e.Value, 0, pos, nil)
	case "read":
		g.emit("READ", 0, 0, pos, nil)
	case "variable":
		symbol := e.Referent
		op := "LOADL"
		address := symbol.Slot
		if symbol.Kind == "global" {
			op = "LOADG"
			address = symbol.Address
		}
		g.emit(op, int64(address), 0, pos, nil)
	case "array":
		g.expression(e.Children[0])
		g.emit("LOADA", int64(e.Referent.Address), int64(e.Referent.Size), pos, nil)
	case "call":
		for _, argument := range e.Children {
			g.expression(argument)
		}
		g.emit("CALL", 0, int64(len(e.Children)), pos, e.Referent.Declaration)
	case "unary":
		g.expression(e.Children[0])
		op := "NEG"
		if e.Token.Spelling == "!" {
			op = "NOT"
		}
		g.emit(op, 0, 0, pos, nil)
	case "binary":
		op := e.Token.Spelling
		if op == "&&" || op == "||" {
			first, last := g.label(), g.label()
			g.expression(e.Children[0])
			branch, value := "JUMPF", int64(0)
			if op == "||" {
				branch = "JUMPT"
				value = 1
			}
			g.to(branch, first, pos)
			g.expression(e.Children[1])
			g.to("JUMP", last, pos)
			g.place(first)
			g.emit("PUSH", value, 0, pos, nil)
			g.place(last)
		} else {
			g.expression(e.Children[0])
			g.expression(e.Children[1])
			instruction := map[string]string{"+": "ADD", "-": "SUB", "*": "MUL", "/": "DIV", "%": "MOD", "<": "LT", "<=": "LE", ">": "GT", ">=": "GE", "==": "EQ", "!=": "NE"}[op]
			g.emit(instruction, 0, 0, pos, nil)
		}
	}
}
func (g *Generator) statement(s *Statement) {
	if s == nil {
		return
	}
	pos := s.Token.Position
	switch s.Kind {
	case "declaration":
		d := s.Declaration
		if d.Initializer == nil {
			g.emit("PUSH", 0, 0, d.Name.Position, nil)
		} else {
			g.expression(d.Initializer)
		}
		g.emit("STOREL", int64(d.Symbol.Slot), 0, d.Name.Position, nil)
	case "assignment":
		symbol := s.Referent
		if s.Index != nil {
			g.expression(s.Index)
			g.expression(s.Expr)
			g.emit("STOREA", int64(symbol.Address), int64(symbol.Size), pos, nil)
		} else {
			g.expression(s.Expr)
			op, address := "STOREL", symbol.Slot
			if symbol.Kind == "global" {
				op = "STOREG"
				address = symbol.Address
			}
			g.emit(op, int64(address), 0, pos, nil)
		}
	case "call":
		g.expression(s.Expr)
		if s.Expr.Type != "void" {
			g.emit("POP", 0, 0, pos, nil)
		}
	case "print":
		for _, e := range s.Expressions {
			g.expression(e)
		}
		g.emit("PRINT", int64(len(s.Expressions)), 0, pos, nil)
	case "return":
		if s.Expr == nil {
			g.emit("RET", 0, 0, pos, nil)
		} else {
			g.expression(s.Expr)
			g.emit("RETV", 0, 0, pos, nil)
		}
	case "block":
		for _, child := range s.Statements {
			g.statement(child)
		}
	case "if":
		other := g.label()
		g.expression(s.Condition)
		g.to("JUMPF", other, pos)
		g.statement(s.Then)
		if s.Else != nil {
			last := g.label()
			g.to("JUMP", last, pos)
			g.place(other)
			g.statement(s.Else)
			g.place(last)
		} else {
			g.place(other)
		}
	case "while":
		first, last := g.label(), g.label()
		g.place(first)
		g.expression(s.Condition)
		g.to("JUMPF", last, pos)
		g.Loops = append(g.Loops, LoopLabels{last, first})
		g.statement(s.Body)
		g.Loops = g.Loops[:len(g.Loops)-1]
		g.to("JUMP", first, pos)
		g.place(last)
	case "for":
		first, update, last := g.label(), g.label(), g.label()
		g.statement(s.Init)
		g.place(first)
		if s.Condition != nil {
			g.expression(s.Condition)
			g.to("JUMPF", last, pos)
		}
		g.Loops = append(g.Loops, LoopLabels{last, update})
		g.statement(s.Body)
		g.Loops = g.Loops[:len(g.Loops)-1]
		g.place(update)
		g.statement(s.Update)
		g.to("JUMP", first, pos)
		g.place(last)
	case "break", "continue":
		loop := g.Loops[len(g.Loops)-1]
		label := loop.Break
		if s.Kind == "continue" {
			label = loop.Continue
		}
		g.to("JUMP", label, pos)
	}
}
func walkStatements(s *Statement, visit func(*Statement)) {
	if s == nil {
		return
	}
	visit(s)
	for _, child := range s.Statements {
		walkStatements(child, visit)
	}
	for _, child := range []*Statement{s.Then, s.Else, s.Body, s.Init, s.Update} {
		walkStatements(child, visit)
	}
}
func generate(program *Program, reachable map[*Symbol]bool) ([]*Unit, int) {
	cells := 0
	for _, d := range program.Globals {
		d.Symbol.Address = cells
		size := 1
		if d.Array {
			size = int(d.Size.Integer)
		}
		cells += size
	}
	init := &Unit{Name: "<init>"}
	units := []*Unit{init}
	g := &Generator{Unit: init}
	for _, d := range program.Globals {
		if d.Initializer != nil {
			g.expression(d.Initializer)
			g.emit("STOREG", int64(d.Symbol.Address), 0, d.Name.Position, nil)
		}
	}
	main := program.Names["main"].Declaration
	g.emit("CALL", 0, 0, main.Name.Position, main)
	g.emit("HALT", 0, 0, main.Name.Position, nil)
	g.patch()
	for _, function := range program.Functions {
		if !reachable[function.Symbol] {
			continue
		}
		slots := []*Symbol{}
		for _, parameter := range function.Parameters {
			slots = append(slots, parameter.Symbol)
		}
		locals := []*Declaration{}
		walkStatements(function.Body, func(s *Statement) {
			if s.Kind == "declaration" {
				locals = append(locals, s.Declaration)
			}
		})
		sort.Slice(locals, func(i, j int) bool { return earlier(locals[i].Name.Position, locals[j].Name.Position) })
		for _, local := range locals {
			slots = append(slots, local.Symbol)
		}
		for i, symbol := range slots {
			symbol.Slot = i
		}
		function.Slots = slots
		unit := &Unit{Name: function.Name.Spelling, Function: function, Slots: len(slots)}
		g = &Generator{Unit: unit}
		g.emit("ENTER", int64(unit.Slots), 0, function.Name.Position, nil)
		g.statement(function.Body)
		if function.Type == "void" {
			g.emit("RET", 0, 0, function.Body.Close.Position, nil)
		}
		g.patch()
		units = append(units, unit)
	}
	return units, cells
}
