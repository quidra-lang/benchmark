using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

foreach (string text in new[] { "(a + b) * [c - d]", "{x = [1, 2, (3 + 4)]}", "f(a[i] + g(b)}", "(1 + 2)) * 3", "if (a < b) { c = d[0]; }", "((a + b] * c", "[{(x * y) - z}" }) {
    var stack = new Stack<char>(); int error = -1;
    for (int i = 0; i < text.Length; i++) {
        char ch = text[i]; int close = ")]}".IndexOf(ch);
        if ("([{".IndexOf(ch) >= 0) stack.Push(ch);
        else if (close >= 0) { if (stack.Count == 0 || stack.Peek() != "([{"[close]) { error = i; break; } stack.Pop(); }
    }
    if (error < 0 && stack.Count > 0) error = text.Length;
    Console.WriteLine(text + " -> " + (error < 0 ? "balanced" : $"error at index {error}"));
}
