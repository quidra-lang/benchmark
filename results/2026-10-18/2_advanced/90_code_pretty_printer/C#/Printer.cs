using System;
using System.Collections.Generic;
using System.Linq;
readonly record struct Command(int Indent, bool Flat, Document Document);
sealed record Printed(List<string> Lines, Dictionary<int, string> Modes);
static class Printer {
    public static bool Fits(int width, Command first, List<Command> stack) {
        if (width < 0) return false;
        int remaining = width;
        List<Command> check = new(stack) {
            first
        };
        while (check.Count > 0) {
            Command command = check[^1];
            check.RemoveAt(check.Count - 1);
            int i = command.Indent;
            bool flat = command.Flat;
            switch (command.Document) {
                case Document.Text t: remaining -= t.Value.Length;
                break;
                case Document.IfBreak b: remaining -= flat ? b.Flat.Length : b.Broken.Length;
                break;
                case Document.Line: if (flat) remaining--;
                else return true;
                break;
                case Document.Softline: if (!flat) return true;
                break;
                case Document.Hardline: return true;
                case Document.Concat c: foreach (Document part in c.Children.AsEnumerable().Reverse()) check.Add(new(i, flat, part));
                break;
                case Document.Group g: check.Add(new(i, g.Forced ? false : flat, g.Child));
                break;
                case Document.Nest n: check.Add(new(i, flat, n.Child));
                break;
                case Document.Align a: check.Add(new(i, flat, a.Child));
                break;
            }
            if (remaining < 0) return false;
        }
        return true;
    }
    public static Printed Print(Document document, int width, int column) {
        List<Command> stack = new() {
            new(0, false, document)
        };
        List<string> lines = new(), pending = new();
        Dictionary<int, string> modes = new();
        string current = "";
        int col = 0;
        void FinalizeLine() {
            string value = Lexer.Trim(current);
            if (pending.Count > 0) {
                string comment = string.Join(" ", pending);
                value += column > 0 && value.Length < column - 1 && column - 1 + comment.Length <= width ? new string(' ', column - 1 - value.Length) : " ";
                value += comment;
                pending.Clear();
            } lines.Add(value);
        }
        while (stack.Count > 0) {
            Command command = stack[^1];
            stack.RemoveAt(stack.Count - 1);
            int i = command.Indent;
            bool flat = command.Flat;
            Document doc = command.Document;
            switch (doc) {
                case Document.Text t: current += t.Value;
                col += t.Value.Length;
                break;
                case Document.IfBreak b: {
                    string value = flat ? b.Flat : b.Broken;
                    current += value;
                    col += value.Length;
                    break;
                }
                case Document.Line: case Document.Softline: case Document.Hardline:
                if (doc is Document.Hardline || !flat) {
                    FinalizeLine();
                    current = new string(' ', i);
                    col = i;
                } else if (doc is Document.Line) {
                    current += " ";
                    col++;
                } break;
                case Document.Concat c: foreach (Document part in c.Children.AsEnumerable().Reverse()) stack.Add(new(i, flat, part));
                break;
                case Document.Nest n: stack.Add(new(i + n.Amount, flat, n.Child));
                break;
                case Document.Align a: stack.Add(new(col, flat, a.Child));
                break;
                case Document.Suffix s: pending.Add(s.Value);
                break;
                case Document.Group g: {
                    string mode = flat ? "flat" : g.Forced ? "forced" : Fits(width - col, new(i, true, g.Child), stack) ? "flat" : "break";
                    modes[g.Id] = mode;
                    stack.Add(new(i, mode == "flat", g.Child));
                    break;
                }
            }
        }
        FinalizeLine();
        return new(lines, modes);
    }
}
