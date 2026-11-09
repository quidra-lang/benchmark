using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
abstract record PPExpression {
    public sealed record Value(long Number) : PPExpression;
    public sealed record Name(string Text) : PPExpression;
    public sealed record Unary(string Op, PPExpression Operand) : PPExpression;
    public sealed record Binary(string Op, PPExpression Left, PPExpression Right) : PPExpression;
    public sealed record Conditional(PPExpression Condition, PPExpression Yes, PPExpression No) : PPExpression;
}
sealed class ExpressionParser(List<Token> tokens) {
    public int Index {
        get;
        private set;
    }
    string Text => Index < tokens.Count ? tokens[Index].Text : "";
    static int Priority(string op) => op switch {
        "||" => 1, "&&" => 2, "|" => 3, "^" => 4, "&" => 5, "==" or "!=" => 6, "<" or ">" or "<=" or ">=" => 7, "<<" or ">>" => 8, "+" or "-" => 9, "*" or "/" or "%" => 10, _ => 0
    };
    PPExpression Expression() {
        PPExpression left = Binary(1);
        if (Text != "?") return left;
        Index++;
        PPExpression yes = Expression();
        if (Text != ":") throw new PPError("'?' without following ':'");
        Index++;
        return new PPExpression.Conditional(left, yes, Expression());
    }
    PPExpression Binary(int minimum) {
        PPExpression left = Unary();
        while (Priority(Text) >= minimum) {
            string op = Text;
            Index++;
            left = new PPExpression.Binary(op, left, Binary(Priority(op) + 1));
        } return left;
    }
    PPExpression Unary() {
        if (Text is "+" or "-" or "!" or "~") {
            string op = Text;
            Index++;
            return new PPExpression.Unary(op, Unary());
        } if (Index == tokens.Count) throw new PPError("expected value at end of expression");
        Token token = tokens[Index++];
        if (token.Kind is "number" or "character") return new PPExpression.Value(Constant(token));
        if (token.Kind == "identifier") return new PPExpression.Name(token.Text);
        if (token.Text == "(") {
            PPExpression value = Expression();
            if (Text != ")") throw new PPError("missing ')' in expression");
            Index++;
            return value;
        } throw new PPError($"expected value before \"{token.Text}\"");
    }
    static long Constant(Token token) {
        string original = token.Text;
        if (token.Kind == "character") {
            string body = original[1..^1];
            if (body.Length == 1 && body[0] != 39 && body[0] != 92) return body[0];
            Dictionary<char, long> escapes = new() {
                ['n'] = 10, ['t'] = 9, [(char)92] = 92, [(char)39] = 39, ['"'] = 34, ['0'] = 0
            };
            if (body.Length == 2 && body[0] == 92 && escapes.TryGetValue(body[1], out long value)) return value;
            throw new PPError("invalid character constant " + original);
        }
        string number = original;
        foreach (string suffix in new[] {
            "ll", "LL", "l", "L"
        }) if (number.Length > suffix.Length && number.EndsWith(suffix, StringComparison.Ordinal)) {
            number = number[..^suffix.Length];
            break;
        } int radix;
        string digits;
        if (number.StartsWith("0x", StringComparison.Ordinal) || number.StartsWith("0X", StringComparison.Ordinal)) {
            radix = 16;
            digits = number[2..];
        } else if (number.StartsWith('0')) {
            radix = 8;
            digits = number;
        } else {
            radix = 10;
            digits = number;
        }
        bool valid = digits.Length > 0 && digits.All(c => radix == 16 ? c is >= '0' and <= '9' or >= 'a' and <= 'f' or >= 'A' and <= 'F' : radix == 8 ? c is >= '0' and <= '7' : c is >= '0' and <= '9');
        if (valid) {
            long value = 0;
            foreach (char c in digits) value = value * radix + (c <= '9' ? c - '0' : char.ToLowerInvariant(c) - 'a' + 10);
            return value;
        } throw new PPError($"invalid integer constant \"{original}\"");
    }
    static long Evaluate(PPExpression expression, List<(string Kind, string Message)> diagnostics) {
        switch (expression) {
            case PPExpression.Value value: return value.Number;
            case PPExpression.Name name: diagnostics.Add(("warning", $"identifier \"{name.Text}\" evaluates to 0"));
            return 0;
            case PPExpression.Unary unary: {
                long value = Evaluate(unary.Operand, diagnostics);
                return unary.Op switch {
                    "+" => value, "-" => -value, "!" => value == 0 ? 1 : 0, _ => -value - 1
                };
            }
            case PPExpression.Conditional conditional: {
                long value = Evaluate(conditional.Condition, diagnostics);
                return Evaluate(value != 0 ? conditional.Yes : conditional.No, diagnostics);
            }
            case PPExpression.Binary binary: {
                long a = Evaluate(binary.Left, diagnostics);
                if (binary.Op == "&&" && a == 0) return 0;
                if (binary.Op == "||" && a != 0) return 1;
                long b = Evaluate(binary.Right, diagnostics);
                if (binary.Op is "/" or "%" && b == 0) throw new PPError("division by zero in #if");
                return binary.Op switch {
                    "+" => a + b, "-" => a - b, "*" => a * b, "/" => a / b, "%" => a % b, "<<" => a << (int)b, ">>" => a >> (int)b, "&" => a & b, "|" => a | b, "^" => a ^ b, "&&" or "||" => b == 0 ? 0 : 1, "<" => a < b ? 1 : 0, ">" => a > b ? 1 : 0, "<=" => a <= b ? 1 : 0, ">=" => a >= b ? 1 : 0, "==" => a == b ? 1 : 0, _ => a != b ? 1 : 0
                };
            }
            default: throw new InvalidOperationException();
        }
    }
    public static (long? Value, List<(string Kind, string Message)> Diagnostics) Test(List<Token> tokens, string directive) {
        ExpressionParser parser = new(tokens);
        List<(string, string)> diagnostics = new();
        try {
            if (tokens.Count == 0) throw new PPError($"#{directive} with no expression");
            PPExpression expression = parser.Expression();
            if (parser.Index != tokens.Count) throw new PPError($"missing binary operator before \"{tokens[parser.Index].Text}\"");
            long value = Evaluate(expression, diagnostics);
            return (value, diagnostics);
        } catch (PPError error) {
            diagnostics.Add(("error", error.Reason));
            return (null, diagnostics);
        }
    }
}
