using System;
using System.Collections.Generic;
using System.Linq;
enum ToyType {
    Int, Bool, Void
}
static class ToyTypes {
    public static string Text(this ToyType type) => type.ToString().ToLowerInvariant();
    public static ToyType? Read(string text) => text switch {
        "int" => ToyType.Int, "bool" => ToyType.Bool, "void" => ToyType.Void, _ => null
    };
}
sealed record Name(string Text, Position Position);
sealed class Variable(ToyType type, Name name, Expr? initializer = null, int? size = null, Position? sizePosition = null) {
    public ToyType Type {
        get;
    } = type;
    public Name Name {
        get;
    } = name;
    public Expr? Initializer {
        get;
        set;
    } = initializer;
    public int? Size {
        get;
    } = size;
    public Position? SizePosition {
        get;
    } = sizePosition;
    public int Id {
        get;
        set;
    } = -1;
    public int Address {
        get;
        set;
    } = -1;
    public int Slot {
        get;
        set;
    } = -1;
}
sealed class Function(ToyType type, Name name, List<Variable> parameters, Stmt body) {
    public ToyType Type {
        get;
    } = type;
    public Name Name {
        get;
    } = name;
    public List<Variable> Parameters {
        get;
    } = parameters;
    public Stmt Body {
        get;
    } = body;
    public int Id {
        get;
        set;
    } = -1;
}
abstract record Top {
    public sealed record VariableDecl(Variable Variable) : Top;
    public sealed record FunctionDecl(Function Function) : Top;
}
sealed record ToyProgram(List<Top> Declarations, Position End);
sealed class Expr(Position position, ExprKind kind) {
    public Position Position {
        get;
    } = position;
    public ExprKind Kind {
        get;
        set;
    } = kind;
    public int? Reference {
        get;
        set;
    } public ToyType? Type {
        get;
        set;
    }
}
abstract record ExprKind {
    public sealed record Integer(long Value) : ExprKind;
    public sealed record BooleanValue(bool Value) : ExprKind;
    public sealed record Read : ExprKind;
    public sealed record VariableRef(Name Name) : ExprKind;
    public sealed record Element(Name Name, Expr Index) : ExprKind;
    public sealed record Call(Name Name, List<Expr> Arguments) : ExprKind;
    public sealed record Unary(string Op, Expr Value) : ExprKind;
    public sealed record Binary(string Op, Expr Left, Expr Right) : ExprKind;
}
sealed class Stmt(Position position, StmtKind kind) {
    public Position Position {
        get;
    } = position;
    public StmtKind Kind {
        get;
        set;
    } = kind;
    public int? Reference {
        get;
        set;
    }
}
abstract record StmtKind {
    public sealed record Block(List<Stmt> Statements, Position Close) : StmtKind;
    public sealed record Declaration(Variable Variable) : StmtKind;
    public sealed record Assignment(Name Name, Expr? Index, Expr Value) : StmtKind;
    public sealed record Call(Expr Value) : StmtKind;
    public sealed record Conditional(Expr Condition, Stmt Yes, Stmt? No) : StmtKind;
    public sealed record WhileLoop(Expr Condition, Stmt Body) : StmtKind;
    public sealed record ForLoop(Stmt? Initial, Expr? Condition, Stmt? Update, Stmt Body) : StmtKind;
    public sealed record BreakLoop : StmtKind;
    public sealed record ContinueLoop : StmtKind;
    public sealed record ReturnValue(Expr? Value) : StmtKind;
    public sealed record Print(List<Expr> Values) : StmtKind;
    public sealed record Empty : StmtKind;
}
sealed class Parser(List<Token> tokens) {
    int index;
    Token Peek => tokens[index];
    string Text => Peek.Text;
    CompileError Failure() => new("syntax", Peek.Position, Peek.Kind == "end" ? "unexpected end of program" : $"unexpected '{Text}'");
    Token Take() {
        Token token = Peek;
        if (token.Kind != "end") index++;
        return token;
    }
    Token Expect(string text) {
        if (Text != text) throw Failure();
        return Take();
    }
    Name Name() {
        if (Peek.Kind != "identifier") throw Failure();
        Token token = Take();
        return new(token.Text, token.Position);
    }
    ToyType Type() {
        ToyType type = ToyTypes.Read(Text) ?? throw Failure();
        Take();
        return type;
    }
    public ToyProgram Parse() {
        List<Top> declarations = new();
        while (Peek.Kind != "end") {
            ToyType type = Type();
            Name name = Name();
            if (Text == "(") {
                Take();
                List<Variable> parameters = new();
                if (Text != ")") while (true) {
                    ToyType t = Type();
                    Name n = Name();
                    parameters.Add(new(t, n));
                    if (Text != ",") break;
                    Take();
                } Expect(")");
                declarations.Add(new Top.FunctionDecl(new(type, name, parameters, Block())));
            }
            else {
                Expr? initial = null;
                int? size = null;
                Position? sizePosition = null;
                if (Text == "[") {
                    Take();
                    if (Peek.Kind != "integer") throw Failure();
                    sizePosition = Peek.Position;
                    size = int.Parse(Take().Text);
                    Expect("]");
                } else if (Text == "=") {
                    Take();
                    initial = Expression();
                } Expect(";");
                declarations.Add(new Top.VariableDecl(new(type, name, initial, size, sizePosition)));
            }
        }
        return new(declarations, Peek.Position);
    }
    Stmt Declaration(bool required) {
        Position position = Peek.Position;
        ToyType type = Type();
        Name name = Name();
        Expr? initial = null;
        if (Text == "=") {
            Take();
            initial = Expression();
        } else if (required) Expect("=");
        return new(position, new StmtKind.Declaration(new(type, name, initial)));
    }
    Stmt Block() {
        Position position = Expect("{").Position;
        List<Stmt> statements = new();
        while (Text != "}") {
            if (ToyTypes.Read(Text).HasValue) {
                Stmt statement = Declaration(false);
                Expect(";");
                statements.Add(statement);
            } else statements.Add(Statement());
        } Position close = Take().Position;
        return new(position, new StmtKind.Block(statements, close));
    }
    Stmt Statement() {
        Position position = Peek.Position;
        switch (Text) {
            case "{": return Block();
            case "if": {
                Take();
                Expect("(");
                Expr condition = Expression();
                Expect(")");
                Stmt yes = Statement();
                Stmt? no = null;
                if (Text == "else") {
                    Take();
                    no = Statement();
                } return new(position, new StmtKind.Conditional(condition, yes, no));
            }
            case "while": {
                Take();
                Expect("(");
                Expr condition = Expression();
                Expect(")");
                return new(position, new StmtKind.WhileLoop(condition, Statement()));
            }
            case "for": {
                Take();
                Expect("(");
                Stmt? initial = Text == ";" ? null : ToyTypes.Read(Text).HasValue ? Declaration(true) : Simple();
                Expect(";");
                Expr? condition = Text == ";" ? null : Expression();
                Expect(";");
                Stmt? update = Text == ")" ? null : Simple();
                Expect(")");
                return new(position, new StmtKind.ForLoop(initial, condition, update, Statement()));
            }
            case "break": case "continue": {
                string keyword = Take().Text;
                Expect(";");
                return new(position, keyword == "break" ? new StmtKind.BreakLoop() : new StmtKind.ContinueLoop());
            }
            case "return": {
                Take();
                Expr? value = Text == ";" ? null : Expression();
                Expect(";");
                return new(position, new StmtKind.ReturnValue(value));
            }
            case "print": {
                Take();
                Expect("(");
                List<Expr> values = new() {
                    Expression()
                };
                while (Text == ",") {
                    Take();
                    values.Add(Expression());
                } Expect(")");
                Expect(";");
                return new(position, new StmtKind.Print(values));
            }
            default: {
                Stmt result = Simple();
                Expect(";");
                return result;
            }
        }
    }
    Stmt Simple() {
        Position position = Peek.Position;
        if (Text == "read") {
            Take();
            Expect("(");
            Expect(")");
            return new(position, new StmtKind.Call(new(position, new ExprKind.Read())));
        } Name name = Name();
        if (Text == "(") return new(position, new StmtKind.Call(new(position, new ExprKind.Call(name, Arguments()))));
        Expr? index = null;
        if (Text == "[") {
            Take();
            index = Expression();
            Expect("]");
        } Expect("=");
        return new(position, new StmtKind.Assignment(name, index, Expression()));
    }
    List<Expr> Arguments() {
        Expect("(");
        List<Expr> values = new();
        if (Text != ")") {
            values.Add(Expression());
            while (Text == ",") {
                Take();
                values.Add(Expression());
            }
        } Expect(")");
        return values;
    }
    static int Priority(string op) => op switch {
        "||" => 1, "&&" => 2, "==" or "!=" => 3, "<" or "<=" or ">" or ">=" => 4, "+" or "-" => 5, "*" or "/" or "%" => 6, _ => 0
    };
    Expr Expression(int minimum = 1) {
        Expr left = Unary();
        while (Priority(Text) >= minimum) {
            Token op = Take();
            Expr right = Expression(Priority(op.Text) + 1);
            left = new(op.Position, new ExprKind.Binary(op.Text, left, right));
        } return left;
    }
    Expr Unary() {
        if (Text is "-" or "!") {
            Token op = Take();
            return new(op.Position, new ExprKind.Unary(op.Text, Unary()));
        } return Primary();
    }
    Expr Primary() {
        Token token = Peek;
        if (token.Kind == "integer") {
            Take();
            return new(token.Position, new ExprKind.Integer(long.Parse(token.Text)));
        } if (Text is "true" or "false") {
            Take();
            return new(token.Position, new ExprKind.BooleanValue(token.Text == "true"));
        } if (Text == "read") {
            Take();
            Expect("(");
            Expect(")");
            return new(token.Position, new ExprKind.Read());
        } if (Text == "(") {
            Take();
            Expr value = Expression();
            Expect(")");
            return value;
        } Name name = Name();
        if (Text == "(") return new(token.Position, new ExprKind.Call(name, Arguments()));
        if (Text == "[") {
            Take();
            Expr index = Expression();
            Expect("]");
            return new(token.Position, new ExprKind.Element(name, index));
        } return new(token.Position, new ExprKind.VariableRef(name));
    }
}
