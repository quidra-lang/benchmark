using System;
using System.Collections.Generic;
using System.Linq;
sealed record Instruction(string Op, List<long> Operands, Position Position, int? Callee = null) {
    public Instruction Snapshot() => this with {
        Operands = new(Operands)
    };
}
sealed record CodeUnit(string Name, Function? Function, List<Variable> Slots, List<Instruction> Code);
sealed class Label {
    public int? Position {
        get;
        set;
    } public List<int> Patches {
        get;
    } = new();
}
sealed class Codegen(Semantic semantic) {
    List<Instruction> code = new();
    void Emit(string op, List<long> args, Position position, int? callee = null) => code.Add(new(op, args, position, callee));
    void Jump(string op, Label label, Position position) {
        int i = code.Count;
        Emit(op, new() {
            label.Position ?? 0
        }, position);
        if (!label.Position.HasValue) label.Patches.Add(i);
    }
    void Mark(Label label) {
        label.Position = code.Count;
        foreach (int i in label.Patches) code[i].Operands[0] = code.Count;
    }
    void Expression(Expr expression) {
        switch (expression.Kind) {
            case ExprKind.Integer e: Emit("PUSH", new() {
                e.Value
            }, expression.Position);
            break;
            case ExprKind.BooleanValue e: Emit("PUSH", new() {
                e.Value ? 1 : 0
            }, expression.Position);
            break;
            case ExprKind.Read: Emit("READ", new(), expression.Position);
            break;
            case ExprKind.VariableRef: {
                Variable variable = semantic.Symbols[expression.Reference!.Value].Variable!;
                Emit(variable.Address >= 0 ? "LOADG" : "LOADL", new() {
                    variable.Address >= 0 ? variable.Address : variable.Slot
                }, expression.Position);
                break;
            }
            case ExprKind.Element e: {
                Expression(e.Index);
                Variable variable = semantic.Symbols[expression.Reference!.Value].Variable!;
                Emit("LOADA", new() {
                    variable.Address, variable.Size!.Value
                }, expression.Position);
                break;
            }
            case ExprKind.Call e: foreach (Expr argument in e.Arguments) Expression(argument);
            Emit("CALL", new() {
                0, e.Arguments.Count
            }, expression.Position, expression.Reference);
            break;
            case ExprKind.Unary e: Expression(e.Value);
            Emit(e.Op == "-" ? "NEG" : "NOT", new(), expression.Position);
            break;
            case ExprKind.Binary e: {
                Expression(e.Left);
                if (e.Op is "&&" or "||") {
                    Label alternate = new(), end = new();
                    Jump(e.Op == "&&" ? "JUMPF" : "JUMPT", alternate, expression.Position);
                    Expression(e.Right);
                    Jump("JUMP", end, expression.Position);
                    Mark(alternate);
                    Emit("PUSH", new() {
                        e.Op == "&&" ? 0 : 1
                    }, expression.Position);
                    Mark(end);
                }
                else {
                    Expression(e.Right);
                    string op = e.Op switch {
                        "+" => "ADD", "-" => "SUB", "*" => "MUL", "/" => "DIV", "%" => "MOD", "<" => "LT", "<=" => "LE", ">" => "GT", ">=" => "GE", "==" => "EQ", _ => "NE"
                    };
                    Emit(op, new(), expression.Position);
                } break;
            }
        }
    }
    void Statement(Stmt statement, Label? breakLabel = null, Label? continueLabel = null) {
        switch (statement.Kind) {
            case StmtKind.Block s: foreach (Stmt value in s.Statements) Statement(value, breakLabel, continueLabel);
            break;
            case StmtKind.Declaration s: if (s.Variable.Initializer is {
            } initial) Expression(initial);
            else Emit("PUSH", new() {
                0
            }, s.Variable.Name.Position);
            Emit("STOREL", new() {
                s.Variable.Slot
            }, s.Variable.Name.Position);
            break;
            case StmtKind.Assignment s: {
                Variable variable = semantic.Symbols[statement.Reference!.Value].Variable!;
                if (s.Index != null) Expression(s.Index);
                Expression(s.Value);
                if (s.Index != null) Emit("STOREA", new() {
                    variable.Address, variable.Size!.Value
                }, statement.Position);
                else Emit(variable.Address >= 0 ? "STOREG" : "STOREL", new() {
                    variable.Address >= 0 ? variable.Address : variable.Slot
                }, statement.Position);
                break;
            }
            case StmtKind.Call s: Expression(s.Value);
            if (s.Value.Type != ToyType.Void) Emit("POP", new(), statement.Position);
            break;
            case StmtKind.Print s: foreach (Expr value in s.Values) Expression(value);
            Emit("PRINT", new() {
                s.Values.Count
            }, statement.Position);
            break;
            case StmtKind.Conditional s: {
                Label alternate = new();
                Expression(s.Condition);
                Jump("JUMPF", alternate, statement.Position);
                Statement(s.Yes, breakLabel, continueLabel);
                if (s.No != null) {
                    Label end = new();
                    Jump("JUMP", end, statement.Position);
                    Mark(alternate);
                    Statement(s.No, breakLabel, continueLabel);
                    Mark(end);
                } else Mark(alternate);
                break;
            }
            case StmtKind.WhileLoop s: {
                Label start = new(), end = new();
                Mark(start);
                Expression(s.Condition);
                Jump("JUMPF", end, statement.Position);
                Statement(s.Body, end, start);
                Jump("JUMP", start, statement.Position);
                Mark(end);
                break;
            }
            case StmtKind.ForLoop s: {
                if (s.Initial != null) Statement(s.Initial, breakLabel, continueLabel);
                Label start = new(), next = new(), end = new();
                Mark(start);
                if (s.Condition != null) {
                    Expression(s.Condition);
                    Jump("JUMPF", end, statement.Position);
                } Statement(s.Body, end, next);
                Mark(next);
                if (s.Update != null) Statement(s.Update, breakLabel, continueLabel);
                Jump("JUMP", start, statement.Position);
                Mark(end);
                break;
            }
            case StmtKind.BreakLoop: Jump("JUMP", breakLabel!, statement.Position);
            break;
            case StmtKind.ContinueLoop: Jump("JUMP", continueLabel!, statement.Position);
            break;
            case StmtKind.ReturnValue s: if (s.Value != null) {
                Expression(s.Value);
                Emit("RETV", new(), statement.Position);
            } else Emit("RET", new(), statement.Position);
            break;
        }
    }
    static List<Variable> Declarations(Stmt statement) => statement.Kind switch {
        StmtKind.Declaration s => new() {
            s.Variable
        }, StmtKind.Block s => s.Statements.SelectMany(Declarations).ToList(), StmtKind.Conditional s => Declarations(s.Yes).Concat(s.No == null ? Enumerable.Empty<Variable>() : Declarations(s.No)).ToList(), StmtKind.WhileLoop s => Declarations(s.Body), StmtKind.ForLoop s => (s.Initial == null ? Enumerable.Empty<Variable>() : Declarations(s.Initial)).Concat(Declarations(s.Body)).Concat(s.Update == null ? Enumerable.Empty<Variable>() : Declarations(s.Update)).ToList(), _ => new()
    };
    public (List<CodeUnit> Units, int Area) Generate(ToyProgram program, HashSet<int> reachable) {
        int area = 0;
        List<CodeUnit> units = new();
        foreach (Variable variable in program.Declarations.OfType<Top.VariableDecl>().Select(d => d.Variable)) {
            variable.Address = area;
            area += variable.Size ?? 1;
        }
        foreach (Variable variable in program.Declarations.OfType<Top.VariableDecl>().Select(d => d.Variable)) if (variable.Initializer is {
        } initial) {
            Expression(initial);
            Emit("STOREG", new() {
                variable.Address
            }, variable.Name.Position);
        }
        int mainId = semantic.Globals["main"];
        Function main = semantic.Symbols[mainId].Function!;
        Emit("CALL", new() {
            0, 0
        }, main.Name.Position, mainId);
        Emit("HALT", new(), main.Name.Position);
        units.Add(new("<init>", null, new(), new(code)));
        foreach (Function function in program.Declarations.OfType<Top.FunctionDecl>().Select(d => d.Function).Where(f => reachable.Contains(f.Id))) {
            List<Variable> slots = function.Parameters.Concat(Declarations(function.Body).OrderBy(variable => variable.Name.Position)).ToList();
            for (int i = 0; i < slots.Count; i++) slots[i].Slot = i;
            code = new();
            Emit("ENTER", new() {
                slots.Count
            }, function.Name.Position);
            Statement(function.Body);
            if (function.Type == ToyType.Void) Emit("RET", new(), ((StmtKind.Block)function.Body.Kind).Close);
            units.Add(new(function.Name.Text, function, slots, new(code)));
        } return (units, area);
    }
}
