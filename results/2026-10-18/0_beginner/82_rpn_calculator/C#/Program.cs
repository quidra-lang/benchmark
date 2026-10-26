using System;
using System.Collections.Generic;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] expressions = { "3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3",
    "15 7 1 1 + - / 3 * 2 1 1 + + -", "4 2 5 * + 1 3 2 * - 5 + /",
    "2 3 4 + 5", "46341 46339 * -2 /" };
foreach (string expression in expressions)
{
    var stack = new Stack<int>();
    string? error = null;
    foreach (string token in expression.Split(' '))
    {
        if (token.Length == 1 && "+-*/".Contains(token, StringComparison.Ordinal))
        {
            if (stack.Count < 2)
            {
                error = "stack underflow";
                break;
            }
            int b = stack.Pop(), a = stack.Pop();
            if (token == "/" && b == 0)
            {
                error = "division by zero";
                break;
            }
            int value = token switch
            {
                "+" => a + b,
                "-" => a - b,
                "*" => a * b,
                _ => a / b
            };
            stack.Push(value);
        }
        else
        {
            stack.Push(int.Parse(token, CultureInfo.InvariantCulture));
        }
    }
    if (error is null && stack.Count != 1) error = "leftover operands";
    string result = error is null ? stack.Peek().ToString(CultureInfo.InvariantCulture) : "error: " + error;
    Console.WriteLine($"{expression} => {result}");
}
