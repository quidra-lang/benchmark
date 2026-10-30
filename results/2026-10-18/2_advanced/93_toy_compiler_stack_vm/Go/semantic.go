package main

import "fmt"

type Symbol struct {
	Name, Type, Kind    string
	Declaration         *Declaration
	Array               bool
	Size, Address, Slot int
	References          []Position
	Reads               int
	Calls               map[*Symbol]bool
}
type Semantics struct {
	Program  *Program
	Scopes   []map[string]*Symbol
	Function *Declaration
	Loops    int
}

func semanticError(pos Position, message string) { panic(&CompileError{"semantic", message, pos}) }
func (s *Semantics) symbol(d *Declaration, kind string) *Symbol {
	symbol := &Symbol{Name: d.Name.Spelling, Type: d.Type, Kind: kind, Declaration: d, Array: d.Array, Size: int(d.Size.Integer), Calls: map[*Symbol]bool{}}
	d.Symbol = symbol
	s.Program.Symbols = append(s.Program.Symbols, symbol)
	return symbol
}
func (s *Semantics) lookup(t Token, read bool) *Symbol {
	var symbol *Symbol
	for i := len(s.Scopes) - 1; i >= 0; i-- {
		if value, found := s.Scopes[i][t.Spelling]; found {
			symbol = value
			break
		}
	}
	if symbol == nil {
		symbol = s.Program.Names[t.Spelling]
	}
	if symbol != nil {
		symbol.References = append(symbol.References, t.Position)
		if read {
			symbol.Reads++
		}
	}
	return symbol
}
func (s *Semantics) variable(t Token, array, read bool) *Symbol {
	symbol := s.lookup(t, read)
	name := t.Spelling
	if symbol == nil {
		semanticError(t.Position, "undeclared identifier '"+name+"'")
	}
	if symbol.Kind == "function" {
		semanticError(t.Position, "'"+name+"' is a function, not a variable")
	}
	if array && !symbol.Array {
		semanticError(t.Position, "'"+name+"' is not an array")
	}
	if !array && symbol.Array {
		semanticError(t.Position, "array '"+name+"' used without index")
	}
	return symbol
}
func (s *Semantics) expression(e *Expr, statement bool) string {
	typ := ""
	name := e.Token.Spelling
	pos := e.position()
	switch e.Kind {
	case "integer", "read":
		typ = "int"
	case "boolean":
		typ = "bool"
	case "variable":
		e.Referent = s.variable(e.Token, false, true)
		typ = e.Referent.Type
	case "array":
		e.Referent = s.variable(e.Token, true, true)
		if s.expression(e.Children[0], false) != "int" {
			semanticError(pos, "index of '"+name+"' must be int")
		}
		typ = "int"
	case "call":
		symbol := s.lookup(e.Token, true)
		if symbol == nil {
			semanticError(pos, "undeclared function '"+name+"'")
		}
		if symbol.Kind != "function" {
			semanticError(pos, "'"+name+"' is not a function")
		}
		e.Referent = symbol
		if s.Function != nil {
			s.Function.Symbol.Calls[symbol] = true
		}
		parameters := symbol.Declaration.Parameters
		if len(e.Children) != len(parameters) {
			semanticError(pos, fmt.Sprintf("wrong number of arguments to '%s' (expected %d, found %d)", name, len(parameters), len(e.Children)))
		}
		for j, argument := range e.Children {
			if s.expression(argument, false) != parameters[j].Type {
				semanticError(pos, fmt.Sprintf("argument %d of '%s' must be %s", j+1, name, parameters[j].Type))
			}
		}
		if !statement && symbol.Type == "void" {
			semanticError(pos, "void function '"+name+"' used as a value")
		}
		typ = symbol.Type
	case "unary":
		operand := s.expression(e.Children[0], false)
		required := "int"
		if e.Token.Spelling == "!" {
			required = "bool"
		}
		if operand != required {
			semanticError(pos, "operator '"+e.Token.Spelling+"' requires "+required+" operand")
		}
		typ = operand
	case "binary":
		left := s.expression(e.Children[0], false)
		right := s.expression(e.Children[1], false)
		op := e.Token.Spelling
		switch {
		case wordIn("+ - * / % < <= > >=", op):
			if left != "int" || right != "int" {
				semanticError(pos, "operator '"+op+"' requires int operands")
			}
			typ = "int"
			if wordIn("< <= > >=", op) {
				typ = "bool"
			}
		case op == "==" || op == "!=":
			if left != right {
				semanticError(pos, "operator '"+op+"' requires operands of the same type")
			}
			typ = "bool"
		default:
			if left != "bool" || right != "bool" {
				semanticError(pos, "operator '"+op+"' requires bool operands")
			}
			typ = "bool"
		}
	}
	e.Type = typ
	return typ
}
func canComplete(s *Statement) bool {
	switch s.Kind {
	case "return", "break", "continue":
		return false
	case "block":
		for _, child := range s.Statements {
			if !canComplete(child) {
				return false
			}
		}
		return true
	case "if":
		return s.Else == nil || canComplete(s.Then) || canComplete(s.Else)
	}
	return true
}
func (s *Semantics) declaration(d *Declaration) {
	name := d.Name.Spelling
	pos := d.Name.Position
	current := s.Scopes[len(s.Scopes)-1]
	if d.Type == "void" {
		semanticError(pos, "variable '"+name+"' cannot have type void")
	}
	if _, found := current[name]; found {
		semanticError(pos, "redeclaration of '"+name+"'")
	}
	if d.Initializer != nil && s.expression(d.Initializer, false) != d.Type {
		semanticError(pos, "type mismatch in initialization of '"+name+"'")
	}
	current[name] = s.symbol(d, "local")
}
func (s *Semantics) statement(n *Statement) {
	pos := n.Token.Position
	switch n.Kind {
	case "declaration":
		s.declaration(n.Declaration)
	case "assignment":
		name := n.Token.Spelling
		n.Referent = s.variable(n.Token, n.Index != nil, false)
		if n.Index != nil && s.expression(n.Index, false) != "int" {
			semanticError(pos, "index of '"+name+"' must be int")
		}
		if s.expression(n.Expr, false) != n.Referent.Type {
			semanticError(pos, "type mismatch in assignment to '"+name+"'")
		}
	case "call":
		s.expression(n.Expr, true)
	case "if", "while":
		if s.expression(n.Condition, false) != "bool" {
			semanticError(pos, "condition of '"+n.Kind+"' must be bool")
		}
		if n.Kind == "if" {
			s.statement(n.Then)
			if n.Else != nil {
				s.statement(n.Else)
			}
		} else {
			s.Loops++
			s.statement(n.Body)
			s.Loops--
		}
	case "for":
		s.Scopes = append(s.Scopes, map[string]*Symbol{})
		if n.Init != nil {
			s.statement(n.Init)
		}
		if n.Condition != nil && s.expression(n.Condition, false) != "bool" {
			semanticError(pos, "condition of 'for' must be bool")
		}
		if n.Update != nil {
			s.statement(n.Update)
		}
		s.Loops++
		s.statement(n.Body)
		s.Loops--
		s.Scopes = s.Scopes[:len(s.Scopes)-1]
	case "break", "continue":
		if s.Loops == 0 {
			semanticError(pos, "'"+n.Kind+"' outside loop")
		}
	case "return":
		function := s.Function
		if function.Type == "void" {
			if n.Expr != nil {
				semanticError(pos, "function '"+function.Name.Spelling+"' must not return a value")
			}
		} else {
			if n.Expr == nil {
				semanticError(pos, "function '"+function.Name.Spelling+"' must return a value")
			}
			if s.expression(n.Expr, false) != function.Type {
				semanticError(pos, "return value of '"+function.Name.Spelling+"' must be "+function.Type)
			}
		}
	case "print":
		for j, e := range n.Expressions {
			if s.expression(e, false) != "int" {
				semanticError(pos, fmt.Sprintf("argument %d of 'print' must be int", j+1))
			}
		}
	case "block":
		s.Scopes = append(s.Scopes, map[string]*Symbol{})
		for _, child := range n.Statements {
			s.statement(child)
		}
		s.Scopes = s.Scopes[:len(s.Scopes)-1]
	}
}
func analyze(program *Program) (err *CompileError) {
	defer func() {
		if value := recover(); value != nil {
			if failure, ok := value.(*CompileError); ok {
				err = failure
			} else {
				panic(value)
			}
		}
	}()
	program.Names = map[string]*Symbol{}
	s := &Semantics{Program: program}
	for _, d := range program.Declarations {
		name := d.Name.Spelling
		pos := d.Name.Position
		if !d.Function {
			if d.Array {
				if d.Type != "int" {
					semanticError(pos, "array '"+name+"' must have element type int")
				}
				if d.Size.Integer == 0 {
					semanticError(d.Size.Position, "array '"+name+"' must have a positive size")
				}
			} else if d.Type == "void" {
				semanticError(pos, "variable '"+name+"' cannot have type void")
			}
		}
		if program.Names[name] != nil {
			semanticError(pos, "redeclaration of '"+name+"'")
		}
		if d.Function {
			seen := map[string]bool{}
			for _, parameter := range d.Parameters {
				pname := parameter.Name.Spelling
				if parameter.Type == "void" {
					semanticError(parameter.Name.Position, "parameter '"+pname+"' cannot have type void")
				}
				if seen[pname] {
					semanticError(parameter.Name.Position, "redeclaration of '"+pname+"'")
				}
				seen[pname] = true
			}
			program.Names[name] = s.symbol(d, "function")
		} else {
			if d.Initializer != nil {
				var first *Expr
				var visit func(*Expr)
				visit = func(e *Expr) {
					if wordIn("variable array call read", e.Kind) && (first == nil || earlier(e.position(), first.position())) {
						first = e
					}
					for _, child := range e.Children {
						visit(child)
					}
				}
				visit(d.Initializer)
				if first != nil {
					semanticError(first.position(), "global initializer must be constant")
				}
				if s.expression(d.Initializer, false) != d.Type {
					semanticError(pos, "type mismatch in initialization of '"+name+"'")
				}
			}
			program.Names[name] = s.symbol(d, "global")
		}
	}
	main := program.Names["main"]
	if main == nil || main.Kind != "function" {
		semanticError(program.End.Position, "no main function")
	}
	if main.Type != "void" || len(main.Declaration.Parameters) != 0 {
		semanticError(main.Declaration.Name.Position, "main must be declared as 'void main()'")
	}
	for _, function := range program.Functions {
		s.Function = function
		s.Scopes = []map[string]*Symbol{{}}
		for _, parameter := range function.Parameters {
			s.Scopes[0][parameter.Name.Spelling] = s.symbol(parameter, "parameter")
		}
		for _, statement := range function.Body.Statements {
			s.statement(statement)
		}
		if function.Type != "void" && canComplete(function.Body) {
			semanticError(function.Name.Position, "missing return in function '"+function.Name.Spelling+"'")
		}
	}
	return nil
}
