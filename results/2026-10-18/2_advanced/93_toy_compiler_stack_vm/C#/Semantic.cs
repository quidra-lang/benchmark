using System;
using System.Collections.Generic;
using System.Linq;
sealed class Symbol(Name name, ToyType type, Variable? variable, Function? function, bool parameter = false) {
    public Name Name {
        get;
    } = name;
    public ToyType Type {
        get;
    } = type;
    public Variable? Variable {
        get;
    } = variable;
    public Function? Function {
        get;
    } = function;
    public bool Parameter {
        get;
    } = parameter;
    public List<Position> References {
        get;
    } = new();
    public int Reads {
        get;
        set;
    }
}
sealed class Semantic {
    public List<Symbol> Symbols {
        get;
    } = new();
    public Dictionary<string, int> Globals {
        get;
    } = new();
    readonly List<Dictionary<string, int>> scopes = new();
    public Dictionary<int, HashSet<int>> Calls {
        get;
    } = new();
    Function? current;
    static CompileError Failure(Position position, string reason) => new("semantic", position, reason);
    int Add(Variable variable, bool parameter = false) {
        int id = Symbols.Count;
        variable.Id = id;
        Symbols.Add(new(variable.Name, variable.Type, variable, null, parameter));
        return id;
    }
    int Add(Function function) {
        int id = Symbols.Count;
        function.Id = id;
        Symbols.Add(new(function.Name, function.Type, null, function));
        return id;
    }
    static List<Position> Forbidden(Expr expression) => expression.Kind switch {
        ExprKind.VariableRef or ExprKind.Read => new() {
            expression.Position
        }, ExprKind.Element e => new[] {
            expression.Position
        }.Concat(Forbidden(e.Index)).ToList(), ExprKind.Call e => new[] {
            expression.Position
        }.Concat(e.Arguments.SelectMany(Forbidden)).ToList(), ExprKind.Unary e => Forbidden(e.Value), ExprKind.Binary e => Forbidden(e.Left).Concat(Forbidden(e.Right)).ToList(), _ => new()
    };
    public void Analyze(ToyProgram program) {
        foreach (Top declaration in program.Declarations) {
            switch (declaration) {
                case Top.VariableDecl d: {
                    Variable variable = d.Variable;
                    Name name = variable.Name;
                    if (variable.Size.HasValue) {
                        if (variable.Type != ToyType.Int) throw Failure(name.Position, $"array '{name.Text}' must have element type int");
                        if (variable.Size == 0) throw Failure(variable.SizePosition!.Value, $"array '{name.Text}' must have a positive size");
                    } else if (variable.Type == ToyType.Void) throw Failure(name.Position, $"variable '{name.Text}' cannot have type void");
                    if (Globals.ContainsKey(name.Text)) throw Failure(name.Position, $"redeclaration of '{name.Text}'");
                    if (variable.Initializer is {
                    } initializer) {
                        List<Position> forbidden = Forbidden(initializer);
                        if (forbidden.Count > 0) throw Failure(forbidden.Min(), "global initializer must be constant");
                        if (Expression(initializer) != variable.Type) throw Failure(name.Position, $"type mismatch in initialization of '{name.Text}'");
                    } Globals[name.Text] = Add(variable);
                    break;
                }
                case Top.FunctionDecl d: {
                    Function function = d.Function;
                    if (Globals.ContainsKey(function.Name.Text)) throw Failure(function.Name.Position, $"redeclaration of '{function.Name.Text}'");
                    HashSet<string> names = new();
                    foreach (Variable parameter in function.Parameters) {
                        if (parameter.Type == ToyType.Void) throw Failure(parameter.Name.Position, $"parameter '{parameter.Name.Text}' cannot have type void");
                        if (!names.Add(parameter.Name.Text)) throw Failure(parameter.Name.Position, $"redeclaration of '{parameter.Name.Text}'");
                    } Globals[function.Name.Text] = Add(function);
                    break;
                }
            }
        }
        Function main = Globals.TryGetValue("main", out int mainId) && Symbols[mainId].Function is {
        } mainFunction ? mainFunction : throw Failure(program.End, "no main function");
        if (main.Type != ToyType.Void || main.Parameters.Count != 0) throw Failure(main.Name.Position, "main must be declared as 'void main()'");
        foreach (Function function in program.Declarations.OfType<Top.FunctionDecl>().Select(d => d.Function)) {
            current = function;
            scopes.Clear();
            scopes.Add(new());
            Calls[function.Id] = new();
            foreach (Variable parameter in function.Parameters) scopes[0][parameter.Name.Text] = Add(parameter, true);
            foreach (Stmt statement in ((StmtKind.Block)function.Body.Kind).Statements) Statement(statement, 0);
            if (function.Type != ToyType.Void && CanComplete(function.Body)) throw Failure(function.Name.Position, $"missing return in function '{function.Name.Text}'");
        } current = null;
        scopes.Clear();
    }
    int Lookup(Name name, bool read, bool call = false) {
        int? id = scopes.AsEnumerable().Reverse().Where(scope => scope.ContainsKey(name.Text)).Select(scope => (int?)scope[name.Text]).FirstOrDefault();
        if (!id.HasValue && Globals.TryGetValue(name.Text, out int global)) id = global;
        if (!id.HasValue) throw Failure(name.Position, $"undeclared {(call ? "function" : "identifier")} '{name.Text}'");
        Symbols[id.Value].References.Add(name.Position);
        if (read) Symbols[id.Value].Reads++;
        return id.Value;
    }
    int Variable(Name name, bool array, bool read) {
        int id = Lookup(name, read);
        Symbol symbol = Symbols[id];
        if (symbol.Function != null) throw Failure(name.Position, $"'{name.Text}' is a function, not a variable");
        if (!array && symbol.Variable!.Size.HasValue) throw Failure(name.Position, $"array '{name.Text}' used without index");
        if (array && !symbol.Variable!.Size.HasValue) throw Failure(name.Position, $"'{name.Text}' is not an array");
        return id;
    }
    public ToyType Expression(Expr expression, bool callStatement = false) {
        ToyType type;
        switch (expression.Kind) {
            case ExprKind.Integer: case ExprKind.Read: type = ToyType.Int;
            break;
            case ExprKind.BooleanValue: type = ToyType.Bool;
            break;
            case ExprKind.VariableRef e: {
                int id = Variable(e.Name, false, true);
                expression.Reference = id;
                type = Symbols[id].Type;
                break;
            }
            case ExprKind.Element e: {
                int id = Variable(e.Name, true, true);
                expression.Reference = id;
                if (Expression(e.Index) != ToyType.Int) throw Failure(e.Name.Position, $"index of '{e.Name.Text}' must be int");
                type = ToyType.Int;
                break;
            }
            case ExprKind.Call e: {
                int id = Lookup(e.Name, true, true);
                expression.Reference = id;
                Function function = Symbols[id].Function ?? throw Failure(e.Name.Position, $"'{e.Name.Text}' is not a function");
                if (e.Arguments.Count != function.Parameters.Count) throw Failure(e.Name.Position, $"wrong number of arguments to '{e.Name.Text}' (expected {function.Parameters.Count}, found {e.Arguments.Count})");
                for (int k = 0; k < e.Arguments.Count; k++) if (Expression(e.Arguments[k]) != function.Parameters[k].Type) throw Failure(e.Name.Position, $"argument {k + 1} of '{e.Name.Text}' must be {function.Parameters[k].Type.Text()}");
                if (!callStatement && function.Type == ToyType.Void) throw Failure(e.Name.Position, $"void function '{e.Name.Text}' used as a value");
                if (current != null) Calls[current.Id].Add(id);
                type = function.Type;
                break;
            }
            case ExprKind.Unary e: {
                type = Expression(e.Value);
                ToyType required = e.Op == "-" ? ToyType.Int : ToyType.Bool;
                if (type != required) throw Failure(expression.Position, $"operator '{e.Op}' requires {required.Text()} operand");
                break;
            }
            case ExprKind.Binary e: {
                ToyType a = Expression(e.Left), b = Expression(e.Right);
                if (e.Op is "+" or "-" or "*" or "/" or "%" or "<" or "<=" or ">" or ">=") {
                    if (a != ToyType.Int || b != ToyType.Int) throw Failure(expression.Position, $"operator '{e.Op}' requires int operands");
                    type = e.Op is "+" or "-" or "*" or "/" or "%" ? ToyType.Int : ToyType.Bool;
                } else if (e.Op is "==" or "!=") {
                    if (a != b) throw Failure(expression.Position, $"operator '{e.Op}' requires operands of the same type");
                    type = ToyType.Bool;
                } else {
                    if (a != ToyType.Bool || b != ToyType.Bool) throw Failure(expression.Position, $"operator '{e.Op}' requires bool operands");
                    type = ToyType.Bool;
                } break;
            }
            default: throw new InvalidOperationException();
        }
        expression.Type = type;
        return type;
    }
    void Statement(Stmt statement, int loops) {
        switch (statement.Kind) {
            case StmtKind.Declaration s: {
                Variable variable = s.Variable;
                Name name = variable.Name;
                if (variable.Type == ToyType.Void) throw Failure(name.Position, $"variable '{name.Text}' cannot have type void");
                if (scopes[^1].ContainsKey(name.Text)) throw Failure(name.Position, $"redeclaration of '{name.Text}'");
                if (variable.Initializer is {
                } initializer && Expression(initializer) != variable.Type) throw Failure(name.Position, $"type mismatch in initialization of '{name.Text}'");
                scopes[^1][name.Text] = Add(variable);
                break;
            }
            case StmtKind.Assignment s: {
                int id = Variable(s.Name, s.Index != null, false);
                statement.Reference = id;
                if (s.Index != null && Expression(s.Index) != ToyType.Int) throw Failure(s.Name.Position, $"index of '{s.Name.Text}' must be int");
                if (Expression(s.Value) != Symbols[id].Type) throw Failure(s.Name.Position, $"type mismatch in assignment to '{s.Name.Text}'");
                break;
            }
            case StmtKind.Call s: Expression(s.Value, true);
            break;
            case StmtKind.Conditional s: if (Expression(s.Condition) != ToyType.Bool) throw Failure(statement.Position, "condition of 'if' must be bool");
            Statement(s.Yes, loops);
            if (s.No != null) Statement(s.No, loops);
            break;
            case StmtKind.WhileLoop s: if (Expression(s.Condition) != ToyType.Bool) throw Failure(statement.Position, "condition of 'while' must be bool");
            Statement(s.Body, loops + 1);
            break;
            case StmtKind.ForLoop s: scopes.Add(new());
            if (s.Initial != null) Statement(s.Initial, loops);
            if (s.Condition != null && Expression(s.Condition) != ToyType.Bool) throw Failure(statement.Position, "condition of 'for' must be bool");
            if (s.Update != null) Statement(s.Update, loops);
            Statement(s.Body, loops + 1);
            scopes.RemoveAt(scopes.Count - 1);
            break;
            case StmtKind.BreakLoop: if (loops == 0) throw Failure(statement.Position, "'break' outside loop");
            break;
            case StmtKind.ContinueLoop: if (loops == 0) throw Failure(statement.Position, "'continue' outside loop");
            break;
            case StmtKind.ReturnValue s: {
                Function function = current!;
                if (function.Type == ToyType.Void && s.Value != null) throw Failure(statement.Position, $"function '{function.Name.Text}' must not return a value");
                if (function.Type != ToyType.Void) {
                    Expr value = s.Value ?? throw Failure(statement.Position, $"function '{function.Name.Text}' must return a value");
                    if (Expression(value) != function.Type) throw Failure(statement.Position, $"return value of '{function.Name.Text}' must be {function.Type.Text()}");
                } break;
            }
            case StmtKind.Print s: for (int k = 0; k < s.Values.Count; k++) if (Expression(s.Values[k]) != ToyType.Int) throw Failure(statement.Position, $"argument {k + 1} of 'print' must be int");
            break;
            case StmtKind.Block s: scopes.Add(new());
            foreach (Stmt value in s.Statements) Statement(value, loops);
            scopes.RemoveAt(scopes.Count - 1);
            break;
        }
    }
    public static bool CanComplete(Stmt statement) => statement.Kind switch {
        StmtKind.ReturnValue or StmtKind.BreakLoop or StmtKind.ContinueLoop => false, StmtKind.Block s => s.Statements.All(CanComplete), StmtKind.Conditional s => s.No == null || CanComplete(s.Yes) || CanComplete(s.No), _ => true
    };
}
