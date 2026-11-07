using System;
using System.Collections.Generic;
using System.Linq;
abstract record Expr(Position Position);
sealed record IntExpr(Position Position, long Value) : Expr(Position);
sealed record BoolExpr(Position Position, bool Value) : Expr(Position);
sealed record StringExpr(Position Position, string Value) : Expr(Position);
sealed record NameExpr(Position Position, string Name) : Expr(Position);
sealed record Lambda(Position Position, Parameter Parameter, Expr Body) : Expr(Position);
sealed record Apply(Position Position, Expr Function, Expr Argument) : Expr(Position);
sealed record Binary(Position Position, string Op, Position OperatorPosition, Expr Left, Expr Right) : Expr(Position);
sealed record Negate(Position Position, Expr Operand) : Expr(Position);
sealed record Conditional(Position Position, Expr Condition, Expr Yes, Expr No) : Expr(Position);
sealed record PairExpr(Position Position, Expr First, Expr Second) : Expr(Position);
sealed record ListExpr(Position Position, List<Expr> Elements) : Expr(Position);
sealed record Match(Position Position, Expr Value, List<(Pattern Pattern, Expr Body)> Arms) : Expr(Position);
sealed record LetIn(Position Position, Group Group, Expr Body) : Expr(Position);
sealed record Parameter(string? Name, Position Position);
sealed record Binding(string Name, Position Position, Expr Expression);
sealed record Group(Position? Recursive, List<Binding> Bindings);
abstract record Pattern(Position Position);
sealed record WildPattern(Position Position) : Pattern(Position);
sealed record NamePattern(Position Position, string Name) : Pattern(Position);
sealed record IntPattern(Position Position, long Value) : Pattern(Position);
sealed record BoolPattern(Position Position, bool Value) : Pattern(Position);
sealed record StringPattern(Position Position, string Value) : Pattern(Position);
sealed record ConsPattern(Position Position, Pattern Head, Pattern Tail) : Pattern(Position);
sealed record ListPattern(Position Position, List<Pattern> Elements) : Pattern(Position);
sealed record PairPattern(Position Position, Pattern First, Pattern Second) : Pattern(Position);
abstract record TypeExpression {
    public sealed record Primitive(string Name) : TypeExpression;
    public sealed record Variable(string Name) : TypeExpression;
    public sealed record ListType(TypeExpression Element) : TypeExpression;
    public sealed record PairType(TypeExpression First, TypeExpression Second) : TypeExpression;
    public sealed record Function(TypeExpression Argument, TypeExpression Result) : TypeExpression;
}
abstract record Item {
    public sealed record Signature(string Name, Position Position, TypeExpression Type) : Item;
    public sealed record Declaration(Group Group) : Item;
    public sealed record Expression(Expr Expr) : Item;
}
sealed class SyntaxError(Token token) : Exception {
    public Token Token {
        get;
    } = token;
}
sealed class Parser(List<Token> tokens) {
    int index;
    public Token Peek => tokens[index];
    string Word => Peek.Value;
    SyntaxError Failure() => new(Peek);
    Token Take() {
        Token token = Peek;
        if (token.Kind != "eof") index++;
        return token;
    }
    Token Expect(string word) {
        if (Word != word || Peek.Kind == "invalid") throw Failure();
        return Take();
    }
    Token Name() {
        if (Peek.Kind != "identifier" || Word == "_") throw Failure();
        return Take();
    }
    Parameter Parameter() {
        if (Peek.Kind != "identifier") throw Failure();
        Token token = Take();
        return new(token.Value == "_" ? null : token.Value, token.Position);
    }
    bool AtomicStart => Peek.Kind is "integer" or "string" || Peek.Kind == "identifier" && Word != "_" || Peek.Kind != "invalid" && Word is "true" or "false" or "(" or "[";
    Group Group() {
        Expect("let");
        Position? recursive = Word == "rec" ? Take().Position : null;
        List<Binding> bindings = new();
        while (true) {
            Token token = Name();
            List<Parameter> parameters = new();
            while (Peek.Kind == "identifier") parameters.Add(Parameter());
            Expect("=");
            Expr body = Expression();
            foreach (Parameter parameter in parameters.AsEnumerable().Reverse()) body = new Lambda(parameter.Position, parameter, body);
            bindings.Add(new(token.Value, token.Position, body));
            if (Word != "and") break;
            Take();
        } return new(recursive, bindings);
    }
    public Item ReadItem() {
        Item result;
        if (Word == "val") {
            Take();
            Token token = Name();
            Expect(":");
            result = new Item.Signature(token.Value, token.Position, Type());
        }
        else if (Word == "let") {
            Position position = Peek.Position;
            Group group = Group();
            if (Word == "in") {
                Take();
                result = new Item.Expression(new LetIn(position, group, Expression()));
            } else result = new Item.Declaration(group);
        }
        else result = new Item.Expression(Expression());
        Expect(";;");
        return result;
    }
    Expr Expression() {
        Position position = Peek.Position;
        switch (Word) {
            case "let": {
                Group group = Group();
                Expect("in");
                return new LetIn(position, group, Expression());
            }
            case "fun": {
                Take();
                List<Parameter> parameters = new() {
                    Parameter()
                };
                while (Peek.Kind == "identifier") parameters.Add(Parameter());
                Expect("->");
                Expr body = Expression();
                for (int i = parameters.Count - 1; i >= 0; i--) body = new Lambda(i == 0 ? position : parameters[i].Position, parameters[i], body);
                return body;
            }
            case "if": {
                Take();
                Expr condition = Expression();
                Expect("then");
                Expr yes = Expression();
                Expect("else");
                Expr no = Expression();
                return new Conditional(position, condition, yes, no);
            }
            case "match": {
                Take();
                Expr value = Expression();
                Expect("with");
                if (Word == "|") Take();
                List<(Pattern, Expr)> arms = new();
                while (true) {
                    Pattern pattern = Pattern();
                    Expect("->");
                    arms.Add((pattern, Expression()));
                    if (Word != "|") break;
                    Take();
                } return new Match(position, value, arms);
            }
            default: return BinaryExpression(1);
        }
    }
    Expr BinaryExpression(int minimum) {
        Expr left = Unary();
        while (true) {
            int p = Precedence(Word);
            if (p == 0 || p < minimum) break;
            Token op = Take();
            Expr right = BinaryExpression(RightAssociative(op.Value) ? p : p + 1);
            left = new Binary(left.Position, op.Value, op.Position, left, right);
        } return left;
    }
    Expr Unary() {
        if (Word == "-") {
            Token token = Take();
            return new Negate(token.Position, Unary());
        } Expr function = Atomic();
        while (AtomicStart) {
            Expr argument = Atomic();
            function = new Apply(function.Position, function, argument);
        } return function;
    }
    Expr Atomic() {
        Token token = Peek;
        Position position = token.Position;
        switch (token.Kind) {
            case "integer": Take();
            return new IntExpr(position, long.Parse(token.Value));
            case "string": Take();
            return new StringExpr(position, token.Value);
            case "identifier": if (Word != "_") {
                Take();
                return new NameExpr(position, token.Value);
            } break;
        }
        if (token.Kind == "invalid") throw Failure();
        switch (Word) {
            case "true": case "false": Take();
            return new BoolExpr(position, token.Value == "true");
            case "(": {
                Take();
                Expr first = Expression();
                if (Word == ",") {
                    Take();
                    Expr second = Expression();
                    Expect(")");
                    return new PairExpr(position, first, second);
                } Expect(")");
                return first;
            }
            case "[": {
                Take();
                List<Expr> elements = new();
                if (Word != "]") {
                    elements.Add(Expression());
                    while (Word == ";") {
                        Take();
                        elements.Add(Expression());
                    }
                } Expect("]");
                return new ListExpr(position, elements);
            }
            default: throw Failure();
        }
    }
    Pattern Pattern() {
        Pattern head = AtomicPattern();
        if (Word != "::") return head;
        Take();
        return new ConsPattern(head.Position, head, Pattern());
    }
    Pattern AtomicPattern() {
        Token token = Peek;
        Position position = token.Position;
        switch (token.Kind) {
            case "integer": Take();
            return new IntPattern(position, long.Parse(token.Value));
            case "string": Take();
            return new StringPattern(position, token.Value);
            case "identifier": Take();
            return token.Value == "_" ? new WildPattern(position) : new NamePattern(position, token.Value);
        }
        if (token.Kind == "invalid") throw Failure();
        switch (Word) {
            case "true": case "false": Take();
            return new BoolPattern(position, token.Value == "true");
            case "-": Take();
            if (Peek.Kind != "integer") throw Failure();
            return new IntPattern(position, -long.Parse(Take().Value));
            case "(": {
                Take();
                Pattern first = Pattern();
                if (Word == ",") {
                    Take();
                    Pattern second = Pattern();
                    Expect(")");
                    return new PairPattern(position, first, second);
                } Expect(")");
                return first;
            }
            case "[": {
                Take();
                List<Pattern> elements = new();
                if (Word != "]") {
                    elements.Add(Pattern());
                    while (Word == ";") {
                        Take();
                        elements.Add(Pattern());
                    }
                } Expect("]");
                return new ListPattern(position, elements);
            }
            default: throw Failure();
        }
    }
    TypeExpression Type() {
        TypeExpression first = ProductType();
        if (Word != "->") return first;
        Take();
        return new TypeExpression.Function(first, Type());
    }
    TypeExpression ProductType() {
        TypeExpression first = ListType();
        if (Word != "*") return first;
        Take();
        return new TypeExpression.PairType(first, ListType());
    }
    TypeExpression ListType() {
        TypeExpression type = TypeAtom();
        while (Peek.Kind == "identifier" && Word == "list") {
            Take();
            type = new TypeExpression.ListType(type);
        } return type;
    }
    TypeExpression TypeAtom() {
        if (Peek.Kind == "type_variable") return new TypeExpression.Variable(Take().Value);
        if (Peek.Kind == "identifier" && Word is "int" or "bool" or "string") return new TypeExpression.Primitive(Take().Value);
        if (Peek.Kind == "symbol" && Word == "(") {
            Take();
            TypeExpression type = Type();
            Expect(")");
            return type;
        } throw Failure();
    }
    public void Recover() {
        while (Peek.Kind != "eof" && Word != ";;") Take();
        if (Word == ";;") Take();
    }
    public static int Precedence(string op) => op switch {
        "||" => 1, "&&" => 2, "=" or "<>" or "<" or ">" or "<=" or ">=" => 3, "::" or "^" => 4, "+" or "-" => 5, "*" or "/" or "mod" => 6, _ => 0
    };
    public static bool RightAssociative(string op) => op is "||" or "&&" or "::" or "^";
}
