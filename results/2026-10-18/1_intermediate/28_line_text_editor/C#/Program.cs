using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

sealed class CommandError(string reason) : Exception(reason);
enum ElementKind { Number, Offset, Current, Last, Mark, Forward, Backward, Separator, All }
enum CommandKind
{
    Empty, Append, Insert, Change, Print, Numbered, Listed, Number, Count, Yank,
    Marks, History, Files, Delete, Put, Join, JoinSpaced, Window, Indent, Unindent,
    Undo, Redo, Case, Read, Write, WriteAppend, Edit, WritePrint, Mark, Move, Copy,
    Sort, Substitute, Global, InverseGlobal
}

readonly record struct Element(ElementKind Kind, int Value = 0, char Symbol = '\0', string Text = "");
sealed record Address(Element[] Left, Element[]? Right = null, char Separator = '\0')
{
    public int Count => Right is not null ? 2 : Left.Length == 0 ? 0 : 1;
}
sealed record Delimited(string Text, char?[] Replacement, string Raw);
sealed class Command(CommandKind kind)
{
    public CommandKind Kind { get; } = kind;
    public int Count;
    public char Suffix, CaseMode;
    public string Name = "", Pattern = "", Options = "";
    public char?[]? Replacement;
    public bool All;
    public Element[] Destination = [];
    public Command? Subcommand;
}

static class Parser
{
    public static bool Digit(char c) => c is >= '0' and <= '9';
    static bool Digits(string text) => text.Length > 0 && text.All(Digit);
    static int Number(string text) => int.Parse(text, CultureInfo.InvariantCulture);
    static bool PrintSuffix(char c) => c is 'p' or 'n' or 'l';
    static bool SortForm(string text) => text == "sort" || text.StartsWith("sort ", StringComparison.Ordinal);

    public static Delimited ReadDelimited(string text, ref int position, char delimiter)
    {
        int start = position;
        var value = new StringBuilder();
        var replacement = new List<char?>();
        while (position < text.Length)
        {
            char c = text[position++];
            if (c == delimiter)
                return new(value.ToString(), replacement.ToArray(), text[start..(position - 1)]);
            bool escaped = c == '\\';
            if (escaped)
            {
                if (position == text.Length) break;
                c = text[position++];
            }
            value.Append(c);
            replacement.Add(c == '&' && !escaped ? null : c);
        }
        throw new CommandError("missing delimiter");
    }

    public static List<Element> Scan(string text, ref int position)
    {
        var elements = new List<Element>();
        while (position < text.Length)
        {
            char c = text[position];
            if (Digit(c))
            {
                int start = position++;
                while (position < text.Length && Digit(text[position])) position++;
                elements.Add(new(ElementKind.Number, Number(text[start..position])));
            }
            else if (c is '+' or '-')
            {
                int start = ++position;
                while (position < text.Length && Digit(text[position])) position++;
                int value = position == start ? 1 : Number(text[start..position]);
                elements.Add(new(ElementKind.Offset, c == '+' ? value : -value));
            }
            else if (c == '\'')
            {
                position++;
                elements.Add(new(ElementKind.Mark, Symbol: position < text.Length ? text[position++] : '\0'));
            }
            else if (c is '/' or '?')
            {
                position++;
                string pattern = ReadDelimited(text, ref position, c).Text;
                elements.Add(new(c == '/' ? ElementKind.Forward : ElementKind.Backward, Text: pattern));
            }
            else
            {
                ElementKind? kind = c switch
                {
                    '.' => ElementKind.Current, '$' => ElementKind.Last,
                    ',' or ';' => ElementKind.Separator, '%' => ElementKind.All, _ => null
                };
                if (kind is null) break;
                elements.Add(new(kind.Value, Symbol: c));
                position++;
            }
        }
        return elements;
    }

    static bool Expression(IReadOnlyList<Element> elements)
    {
        for (int i = 0; i < elements.Count; i++)
        {
            ElementKind kind = elements[i].Kind;
            if (kind == ElementKind.Offset) continue;
            if (i != 0 || kind is ElementKind.Separator or ElementKind.All) return false;
        }
        return true;
    }

    public static Address Form(List<Element> elements)
    {
        if (elements.Count == 1 && elements[0].Kind == ElementKind.All)
            return new([new(ElementKind.Number, 1)], [new(ElementKind.Last)], ',');
        int[] separators = Enumerable.Range(0, elements.Count)
            .Where(i => elements[i].Kind == ElementKind.Separator).ToArray();
        if (separators.Length > 1) throw new CommandError("bad address");
        if (separators.Length == 0)
        {
            if (!Expression(elements)) throw new CommandError("bad address");
            return new(elements.ToArray());
        }
        int split = separators[0];
        Element[] left = elements.Take(split).ToArray(), right = elements.Skip(split + 1).ToArray();
        if (!Expression(left) || !Expression(right)) throw new CommandError("bad address");
        return new(left, right, elements[split].Symbol);
    }

    static int OptionalCount(string argument)
    {
        if (argument.Length == 0) return 0;
        if (!Digits(argument) || Number(argument) == 0) throw new CommandError("invalid suffix");
        return Number(argument);
    }

    static char Suffix(string argument)
    {
        if (argument.Length == 0) return '\0';
        if (argument.Length != 1 || !PrintSuffix(argument[0])) throw new CommandError("invalid suffix");
        return argument[0];
    }

    static string FileName(string argument)
    {
        if (argument.Length is < 2 or > 9 || argument[0] != ' ' ||
            !argument[1..].All(c => c is >= 'a' and <= 'z' || Digit(c)))
            throw new CommandError("invalid file name");
        return argument[1..];
    }

    static Command Substitution(string argument)
    {
        var command = new Command(CommandKind.Substitute) { Count = 1 };
        string flags = argument;
        if (!argument.All(c => c is 'g' or 'p' or 'n' or 'l' || Digit(c)))
        {
            char delimiter = argument[0];
            if (delimiter is ' ' or '\\') throw new CommandError("missing delimiter");
            int position = 1;
            command.Pattern = ReadDelimited(argument, ref position, delimiter).Text;
            Delimited replacement = ReadDelimited(argument, ref position, delimiter);
            if (replacement.Raw != "%") command.Replacement = replacement.Replacement;
            flags = argument[position..];
        }
        bool hasCount = false;
        for (int position = 0; position < flags.Length;)
        {
            char c = flags[position++];
            if (c == 'g' && !command.All) command.All = true;
            else if (PrintSuffix(c) && command.Suffix == '\0') command.Suffix = c;
            else if (Digit(c) && !hasCount)
            {
                int start = position - 1;
                while (position < flags.Length && Digit(flags[position])) position++;
                command.Count = Number(flags[start..position]);
                if (command.Count == 0) throw new CommandError("invalid suffix");
                hasCount = true;
            }
            else throw new CommandError("invalid suffix");
        }
        return command;
    }

    public static Command Parse(string text)
    {
        if (SortForm(text))
        {
            string options = text.Length == 4 ? "" : text[5..];
            if (text.Length > 4 && options.Length == 0 || options.Any(c => !"ruin".Contains(c)) ||
                options.Distinct().Count() != options.Length || options.Contains('i') && options.Contains('n'))
                throw new CommandError("invalid suffix");
            return new(CommandKind.Sort) { Options = options };
        }
        char first = text.Length == 0 ? '\0' : text[0];
        string argument = text.Length == 0 ? "" : text[1..];
        CommandKind? plain = first switch
        {
            '\0' => CommandKind.Empty, 'a' => CommandKind.Append, 'i' => CommandKind.Insert,
            'c' => CommandKind.Change, 'p' => CommandKind.Print, 'n' => CommandKind.Numbered,
            'l' => CommandKind.Listed, '=' => CommandKind.Number, '#' => CommandKind.Count,
            'y' => CommandKind.Yank, 'K' => CommandKind.Marks, 'h' => CommandKind.History,
            'f' => CommandKind.Files, _ => null
        };
        if (plain is not null)
        {
            if (argument.Length != 0) throw new CommandError("invalid suffix");
            return new(plain.Value);
        }
        switch (first)
        {
            case 'd': case 'x': case 'j': case 'J':
                return new(first switch
                {
                    'd' => CommandKind.Delete, 'x' => CommandKind.Put, 'j' => CommandKind.Join,
                    _ => CommandKind.JoinSpaced
                }) { Suffix = Suffix(argument) };
            case 'z': case '>': case '<': case 'u':
                return new(first switch
                {
                    'z' => CommandKind.Window, '>' => CommandKind.Indent, '<' => CommandKind.Unindent,
                    _ => CommandKind.Undo
                }) { Count = OptionalCount(argument) };
            case '~':
                if (argument != "" && argument != "u" && argument != "l") throw new CommandError("invalid suffix");
                return new(CommandKind.Case) { CaseMode = argument.Length == 0 ? '\0' : argument[0] };
            case 'r':
                return argument.Length == 0 || Digits(argument)
                    ? new(CommandKind.Redo) { Count = OptionalCount(argument) }
                    : new(CommandKind.Read) { Name = FileName(argument) };
            case 'w':
                return argument.Length == 0 ? new(CommandKind.WritePrint)
                    : new(CommandKind.Write) { Name = FileName(argument) };
            case 'W': case 'e':
                return new(first == 'W' ? CommandKind.WriteAppend : CommandKind.Edit) { Name = FileName(argument) };
            case 'k':
                if (argument.Length != 1 || argument[0] is < 'a' or > 'z') throw new CommandError("invalid mark");
                return new(CommandKind.Mark) { Name = argument };
            case 'm': case 't':
                int position = 0;
                List<Element> destination = Scan(argument, ref position);
                if (destination.Count == 0 || !Expression(destination)) throw new CommandError("invalid destination");
                return new(first == 'm' ? CommandKind.Move : CommandKind.Copy)
                {
                    Destination = destination.ToArray(), Suffix = Suffix(argument[position..])
                };
            case 's': return Substitution(argument);
            case 'g': case 'v':
                if (argument.Length == 0 || argument[0] is ' ' or '\\') throw new CommandError("missing delimiter");
                int offset = 1;
                string pattern = ReadDelimited(argument, ref offset, argument[0]).Text;
                string subcommand = offset == argument.Length ? "p" : argument[offset..];
                if (!"pnldmtjJs><~aicx".Contains(subcommand[0]) || SortForm(subcommand))
                    throw new CommandError("invalid global command");
                return new(first == 'g' ? CommandKind.Global : CommandKind.InverseGlobal)
                {
                    Pattern = pattern, Subcommand = Parse(subcommand)
                };
            default: throw new CommandError("unknown command");
        }
    }

    public static bool HasText(string line)
    {
        try
        {
            int position = 0;
            Scan(line, ref position);
            string command = line[position..];
            if (command is "a" or "i" or "c") return true;
            if (command.Length < 2 || command[0] is not ('g' or 'v') || command[1] is ' ' or '\\') return false;
            position = 2;
            ReadDelimited(command, ref position, command[1]);
            return command[position..] is "a" or "i" or "c";
        }
        catch (CommandError) { return false; }
    }
}

readonly record struct Line(long Id, string Text);
sealed record HistoryRecord(string Command, Line[] Lines, int Current);

sealed class State
{
    public List<Line> Lines = [];
    public int Current, DisplayCount = 5;
    public long NextId = 1;
    public long?[] Marks = new long?[26];
    public string[] Cut = [];
    public string? Pattern;
    public char?[]? Replacement;
    public List<HistoryRecord> Undo = [], Redo = [];
    public Dictionary<string, string[]> Files = new(StringComparer.Ordinal);

    public State Copy() => new()
    {
        Lines = [.. Lines], Current = Current, DisplayCount = DisplayCount, NextId = NextId,
        Marks = (long?[])Marks.Clone(), Cut = Cut, Pattern = Pattern, Replacement = Replacement,
        Undo = [.. Undo], Redo = [.. Redo], Files = new(Files, StringComparer.Ordinal)
    };
}

sealed class Editor(State state)
{
    public List<string> Output { get; } = [];
    static bool NoAddress(CommandKind kind) => kind is CommandKind.Undo or CommandKind.Redo or
        CommandKind.History or CommandKind.Marks or CommandKind.Files or CommandKind.Edit;
    static bool OneAddress(CommandKind kind) => kind is CommandKind.Append or CommandKind.Insert or
        CommandKind.Put or CommandKind.Number or CommandKind.Read or CommandKind.Mark or CommandKind.Window;
    static bool Modifies(Command command) => command.Kind switch
    {
        CommandKind.Append or CommandKind.Insert or CommandKind.Change or CommandKind.Delete or
        CommandKind.Put or CommandKind.Join or CommandKind.JoinSpaced or CommandKind.Move or CommandKind.Copy or
        CommandKind.Substitute or CommandKind.Indent or CommandKind.Unindent or CommandKind.Case or
        CommandKind.Sort or CommandKind.Read or CommandKind.Edit => true,
        CommandKind.Global or CommandKind.InverseGlobal => Modifies(command.Subcommand!),
        _ => false
    };

    string Pattern(string search)
    {
        if (search.Length != 0) state.Pattern = search;
        return state.Pattern ?? throw new CommandError("no previous pattern");
    }

    int Evaluate(Element[] elements)
    {
        int value = state.Current;
        foreach (Element element in elements)
        {
            switch (element.Kind)
            {
                case ElementKind.Offset: value += element.Value; break;
                case ElementKind.Number: value = element.Value; break;
                case ElementKind.Current: value = state.Current; break;
                case ElementKind.Last: value = state.Lines.Count; break;
                case ElementKind.Mark:
                    if (element.Symbol is < 'a' or > 'z') throw new CommandError("invalid mark");
                    long? id = state.Marks[element.Symbol - 'a'];
                    value = id is null ? 0 : state.Lines.FindIndex(line => line.Id == id.Value) + 1;
                    if (value == 0) throw new CommandError("mark not set");
                    break;
                case ElementKind.Forward: case ElementKind.Backward:
                    string pattern = Pattern(element.Text);
                    int size = state.Lines.Count;
                    bool forward = element.Kind == ElementKind.Forward;
                    int index = forward ? state.Current : state.Current - 2;
                    value = 0;
                    for (int checkedLines = 0; checkedLines < size; checkedLines++)
                    {
                        if (index >= size) index = 0;
                        if (index < 0) index = size - 1;
                        if (state.Lines[index].Text.Contains(pattern, StringComparison.Ordinal))
                        {
                            value = index + 1;
                            break;
                        }
                        index += forward ? 1 : -1;
                    }
                    if (value == 0) throw new CommandError("no match");
                    break;
            }
        }
        return value;
    }

    int[] Evaluate(Address address)
    {
        if (address.Count == 0) return [];
        if (address.Count == 1) return [Evaluate(address.Left)];
        int left = address.Left.Length == 0 ? address.Separator == ',' ? 1 : state.Current : Evaluate(address.Left);
        if (address.Separator == ';')
        {
            if (left < 0 || left > state.Lines.Count) throw new CommandError("address out of range");
            state.Current = left;
        }
        int right = address.Right!.Length == 0 ? state.Lines.Count : Evaluate(address.Right);
        return [left, right];
    }

    (int First, int Last) Range(Command command, int[] addresses)
    {
        CommandKind kind = command.Kind;
        int size = state.Lines.Count, a, b;
        if (NoAddress(kind)) return (0, 0);
        if (OneAddress(kind))
        {
            a = addresses.Length != 0 ? addresses[0] : kind switch
            {
                CommandKind.Number or CommandKind.Read => size,
                CommandKind.Window => state.Current + 1, _ => state.Current
            };
            int minimum = kind is CommandKind.Mark or CommandKind.Window ? 1 : 0;
            if (a < minimum || a > size) throw new CommandError("address out of range");
            return (a, a);
        }
        if (addresses.Length != 0)
        {
            a = addresses[0];
            b = addresses[^1];
        }
        else if (kind is CommandKind.WritePrint or CommandKind.Write or CommandKind.WriteAppend or CommandKind.Count)
            return (1, size);
        else if (kind is CommandKind.Global or CommandKind.InverseGlobal or CommandKind.Sort) (a, b) = (1, size);
        else if (kind is CommandKind.Join or CommandKind.JoinSpaced) (a, b) = (state.Current, state.Current + 1);
        else (a, b) = (state.Current, state.Current);
        if (a < 1 || b < 1 || a > size || b > size) throw new CommandError("address out of range");
        if (a > b || a == b && kind is (CommandKind.Join or CommandKind.JoinSpaced))
            throw new CommandError("invalid range");
        return (a, b);
    }

    public void Process(string line, string[] text, State before)
    {
        int position = 0;
        Address address = Parser.Form(Parser.Scan(line, ref position));
        Command command = Parser.Parse(line[position..]);
        if (NoAddress(command.Kind) && address.Count != 0) throw new CommandError("unexpected address");
        if (OneAddress(command.Kind) && address.Count == 2) throw new CommandError("too many addresses");
        var (a, b) = Range(command, Evaluate(address));
        Execute(command, a, b, text);
        if (state.Lines.Count > 200) throw new CommandError("buffer full");
        if (Modifies(command))
        {
            state.Undo.Add(new(line, before.Lines.ToArray(), before.Current));
            state.Redo.Clear();
        }
    }

    void Print(int number, char form = 'p')
    {
        string text = state.Lines[number - 1].Text;
        if (form == 'n') Output.Add($"{number,3} {text}");
        else if (form == 'l')
        {
            text = text.Replace("\\", "\\\\", StringComparison.Ordinal) + "$";
            while (text.Length > 40)
            {
                Output.Add(text[..39] + "\\");
                text = text[39..];
            }
            Output.Add(text);
        }
        else Output.Add(text);
    }

    string[] Contents(int a, int b) => state.Lines.GetRange(a - 1, b - a + 1).Select(line => line.Text).ToArray();
    static int Bytes(IEnumerable<string> lines) => lines.Sum(line => line.Length + 1);

    void Insert(int position, IEnumerable<string> text)
    {
        Line[] lines = text.Select(value => new Line(state.NextId++, value)).ToArray();
        state.Lines.InsertRange(position, lines);
        state.Current = position + lines.Length;
    }

    void History(bool undo, int count)
    {
        List<HistoryRecord> source = undo ? state.Undo : state.Redo, target = undo ? state.Redo : state.Undo;
        if (source.Count < count) throw new CommandError(undo ? "nothing to undo" : "nothing to redo");
        for (int i = 0; i < count; i++)
        {
            HistoryRecord record = source[^1];
            source.RemoveAt(source.Count - 1);
            target.Add(new(record.Command, state.Lines.ToArray(), state.Current));
            state.Lines = [.. record.Lines];
            state.Current = record.Current;
        }
    }

    static int LeadingInteger(string text)
    {
        int position = text[0] == '-' ? 1 : 0, start = position;
        while (position < text.Length && Parser.Digit(text[position])) position++;
        return position == start ? 0 : int.Parse(text[..position], CultureInfo.InvariantCulture);
    }

    void Sort(Command command, int a, int b)
    {
        List<Line> lines = state.Lines.GetRange(a - 1, b - a + 1);
        bool reverse = command.Options.Contains('r'), numeric = command.Options.Contains('n');
        string Key(Line line) => command.Options.Contains('i') ? line.Text.ToLowerInvariant() : line.Text;
        IEnumerable<Line> ordered = numeric
            ? reverse ? lines.OrderByDescending(line => LeadingInteger(line.Text)) : lines.OrderBy(line => LeadingInteger(line.Text))
            : reverse ? lines.OrderByDescending(Key, StringComparer.Ordinal) : lines.OrderBy(Key, StringComparer.Ordinal);
        var result = new List<Line>();
        foreach (Line line in ordered)
        {
            if (command.Options.Contains('u') && result.Count != 0 &&
                (numeric ? LeadingInteger(result[^1].Text) == LeadingInteger(line.Text) : Key(result[^1]) == Key(line))) continue;
            result.Add(line);
        }
        state.Lines.RemoveRange(a - 1, b - a + 1);
        state.Lines.InsertRange(a - 1, result);
        state.Current = a + result.Count - 1;
    }

    int Substitute(Command command, int a, int b, bool global)
    {
        string pattern = Pattern(command.Pattern);
        char?[] replacement = command.Replacement ?? state.Replacement ?? throw new CommandError("no previous substitution");
        state.Replacement = replacement;
        var expanded = new StringBuilder();
        foreach (char? part in replacement)
            if (part is null) expanded.Append(pattern); else expanded.Append(part.Value);
        string value = expanded.ToString();
        int substituted = 0;
        for (int number = a; number <= b; number++)
        {
            Line line = state.Lines[number - 1];
            var result = new StringBuilder();
            int position = 0, occurrences = 0, match;
            while ((match = line.Text.IndexOf(pattern, position, StringComparison.Ordinal)) >= 0)
            {
                result.Append(line.Text, position, match - position);
                occurrences++;
                result.Append(occurrences == command.Count || command.All && occurrences >= command.Count ? value : pattern);
                position = match + pattern.Length;
            }
            if (occurrences < command.Count) continue;
            result.Append(line.Text, position, line.Text.Length - position);
            string changed = result.ToString();
            if (changed.Length > 80) throw new CommandError("line too long");
            if (changed.Length == 0 || changed[^1] == ' ') throw new CommandError("bad line");
            state.Lines[number - 1] = line with { Text = changed };
            state.Current = number;
            substituted++;
        }
        if (substituted == 0 && !global) throw new CommandError("no match");
        if (substituted != 0 && command.Suffix != '\0') Print(state.Current, command.Suffix);
        return substituted;
    }

    int Execute(Command command, int a, int b, string[] text, bool global = false)
    {
        CommandKind kind = command.Kind;
        switch (kind)
        {
            case CommandKind.Empty: Print(b); state.Current = b; break;
            case CommandKind.Print: case CommandKind.Numbered: case CommandKind.Listed:
                char form = kind == CommandKind.Print ? 'p' : kind == CommandKind.Numbered ? 'n' : 'l';
                for (int i = a; i <= b; i++) Print(i, form);
                state.Current = b;
                break;
            case CommandKind.Window:
                if (command.Count != 0) state.DisplayCount = command.Count;
                int end = Math.Min(state.Lines.Count, a + state.DisplayCount - 1);
                for (int i = a; i <= end; i++) Print(i);
                state.Current = end;
                break;
            case CommandKind.Number: Output.Add(a.ToString(CultureInfo.InvariantCulture)); break;
            case CommandKind.Count:
                string[] counted = Contents(a, b);
                Output.Add($"count lines={counted.Length} words={counted.Sum(line => line.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length)} chars={counted.Sum(line => line.Length)}");
                break;
            case CommandKind.WritePrint:
                for (int i = a; i <= b; i++) Print(i);
                Output.Add($"lines={b - a + 1} bytes={Bytes(Contents(a, b))}");
                break;
            case CommandKind.Append: Insert(a, text); break;
            case CommandKind.Insert: Insert(Math.Max(a, 1) - 1, text); break;
            case CommandKind.Change: case CommandKind.Delete:
                state.Cut = Contents(a, b);
                state.Lines.RemoveRange(a - 1, b - a + 1);
                if (kind == CommandKind.Change && text.Length != 0) Insert(a - 1, text);
                else state.Current = Math.Min(a, state.Lines.Count);
                break;
            case CommandKind.Yank: state.Cut = Contents(a, b); break;
            case CommandKind.Put:
                if (state.Cut.Length == 0) throw new CommandError("nothing to put");
                Insert(a, state.Cut);
                break;
            case CommandKind.Move: case CommandKind.Copy:
                int destination = Evaluate(command.Destination);
                if (destination < 0 || destination > state.Lines.Count) throw new CommandError("address out of range");
                if (kind == CommandKind.Copy) Insert(destination, Contents(a, b));
                else
                {
                    if (a <= destination && destination < b) throw new CommandError("invalid destination");
                    List<Line> moved = state.Lines.GetRange(a - 1, b - a + 1);
                    state.Lines.RemoveRange(a - 1, moved.Count);
                    int position = destination < a ? destination : destination - moved.Count;
                    state.Lines.InsertRange(position, moved);
                    state.Current = position + moved.Count;
                }
                break;
            case CommandKind.Join: case CommandKind.JoinSpaced:
                string[] pieces = Contents(a, b);
                if (kind == CommandKind.JoinSpaced)
                    for (int i = 1; i < pieces.Length; i++) pieces[i] = pieces[i].TrimStart(' ');
                string joined = string.Join(kind == CommandKind.Join ? "" : " ", pieces);
                if (joined.Length > 80) throw new CommandError("line too long");
                state.Lines[a - 1] = state.Lines[a - 1] with { Text = joined };
                state.Lines.RemoveRange(a, b - a);
                state.Current = a;
                break;
            case CommandKind.Indent: case CommandKind.Unindent: case CommandKind.Case:
                int width = command.Count == 0 ? 4 : command.Count;
                for (int i = a - 1; i < b; i++)
                {
                    Line line = state.Lines[i];
                    string changed = line.Text;
                    if (kind == CommandKind.Indent)
                    {
                        if (changed.Length + width > 80) throw new CommandError("line too long");
                        changed = new string(' ', width) + changed;
                    }
                    else if (kind == CommandKind.Unindent)
                    {
                        int removed = 0;
                        while (removed < width && removed < changed.Length && changed[removed] == ' ') removed++;
                        changed = changed[removed..];
                    }
                    else if (command.CaseMode == 'u') changed = changed.ToUpperInvariant();
                    else if (command.CaseMode == 'l') changed = changed.ToLowerInvariant();
                    else changed = new string(changed.Select(c => c is >= 'A' and <= 'Z' ? (char)(c + 32) :
                        c is >= 'a' and <= 'z' ? (char)(c - 32) : c).ToArray());
                    state.Lines[i] = line with { Text = changed };
                }
                state.Current = b;
                break;
            case CommandKind.Sort: Sort(command, a, b); break;
            case CommandKind.Substitute: return Substitute(command, a, b, global);
            case CommandKind.Mark: state.Marks[command.Name[0] - 'a'] = state.Lines[a - 1].Id; break;
            case CommandKind.Marks:
                var marks = new List<string>();
                for (int i = 0; i < 26; i++)
                {
                    int number = state.Marks[i] is long id ? state.Lines.FindIndex(line => line.Id == id) + 1 : 0;
                    if (number != 0) marks.Add($"{(char)('a' + i)}={number}");
                }
                Output.Add("marks " + (marks.Count == 0 ? "none" : string.Join(' ', marks)));
                break;
            case CommandKind.Undo: case CommandKind.Redo:
                History(kind == CommandKind.Undo, command.Count == 0 ? 1 : command.Count);
                break;
            case CommandKind.History:
                Output.Add($"history undo={state.Undo.Count} redo={state.Redo.Count}");
                for (int i = 0; i < state.Undo.Count; i++) Output.Add($"undo {i + 1}: {state.Undo[^(i + 1)].Command}");
                for (int i = 0; i < state.Redo.Count; i++) Output.Add($"redo {i + 1}: {state.Redo[^(i + 1)].Command}");
                break;
            case CommandKind.Global: case CommandKind.InverseGlobal:
                string pattern = Pattern(command.Pattern);
                long[] selected = state.Lines.GetRange(a - 1, b - a + 1)
                    .Where(line => line.Text.Contains(pattern, StringComparison.Ordinal) == (kind == CommandKind.Global))
                    .Select(line => line.Id).ToArray();
                if (selected.Length == 0) throw new CommandError("no match");
                int substituted = 0;
                Command subcommand = command.Subcommand!;
                foreach (long id in selected)
                {
                    int index = state.Lines.FindIndex(line => line.Id == id);
                    if (index < 0) continue;
                    state.Current = index + 1;
                    var (first, last) = Range(subcommand, []);
                    substituted += Execute(subcommand, first, last, text, true);
                }
                if (subcommand.Kind == CommandKind.Substitute && substituted == 0) throw new CommandError("no match");
                break;
            case CommandKind.Write: case CommandKind.WriteAppend: case CommandKind.Read: case CommandKind.Edit:
                if (kind is CommandKind.Write or CommandKind.WriteAppend)
                {
                    string[] contents = Contents(a, b);
                    state.Files[command.Name] = kind == CommandKind.WriteAppend && state.Files.TryGetValue(command.Name, out string[]? old)
                        ? [.. old, .. contents] : contents;
                }
                else
                {
                    if (!state.Files.TryGetValue(command.Name, out string[]? contents)) throw new CommandError("no such file");
                    if (kind == CommandKind.Edit) state.Lines.Clear();
                    Insert(kind == CommandKind.Edit ? 0 : a, contents);
                }
                string[] file = state.Files[command.Name];
                Output.Add($"file {command.Name} lines={file.Length} bytes={Bytes(file)}");
                break;
            case CommandKind.Files:
                Output.Add("files " + (state.Files.Count == 0 ? "none" : string.Join(' ',
                    state.Files.OrderBy(pair => pair.Key, StringComparer.Ordinal).Select(pair => $"{pair.Key}={pair.Value.Length}"))));
                break;
        }
        if (command.Suffix != '\0' && state.Current >= 1) Print(state.Current, command.Suffix);
        return 0;
    }
}

static class Program
{
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var state = new State();
        while (Console.ReadLine() is string line && line != "Q")
        {
            var text = new List<string>();
            if (Parser.HasText(line))
                while (Console.ReadLine() is string value && value != ".") text.Add(value);
            try
            {
                State next = state.Copy();
                var editor = new Editor(next);
                editor.Process(line, text.ToArray(), state);
                state = next;
                foreach (string output in editor.Output) Console.WriteLine(output);
            }
            catch (CommandError error) { Console.WriteLine("? " + error.Message); }
        }
    }
}
