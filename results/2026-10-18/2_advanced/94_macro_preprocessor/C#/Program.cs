using System;
using System.IO;
using System.Globalization;
using System.Collections.Generic;
using System.Linq;
sealed record Header(string Name, string Rendering, bool Quoted, int End);
sealed class ConditionalBlock(string kind, Position start, bool parent) {
    public string Kind {
        get;
    } = kind;
    public Position Start {
        get;
    } = start;
    public bool Parent {
        get;
    } = parent;
    public bool Chosen {
        get;
        set;
    } public bool Active {
        get;
        set;
    } public bool ElseSeen {
        get;
        set;
    } public int? SkipStart {
        get;
        set;
    }
}
sealed class Inclusion(string path, int depth) {
    public string Path {
        get;
    } = path;
    public int Depth {
        get;
    } = depth;
    public string File {
        get;
        set;
    } = path;
    public int Offset {
        get;
        set;
    } public List<ConditionalBlock> Blocks {
        get;
    } = new();
    public List<Token> Segment {
        get;
    } = new();
    public bool Active => Blocks.LastOrDefault()?.Active ?? true;
    public Position Position(int physical) => new(File, physical + Offset);
}
sealed class Preprocessor {
    readonly Expander expander = new();
    readonly IncludeManager includes = new();
    readonly List<string> history = new();
    readonly HashSet<string> ever = new(), poison = new();
    readonly Dictionary<string, Stack<Macro?>> saves = new();
    readonly List<string> output = new(), tree = new() {
        "main.c"
    }, records = new(), results = new(), regions = new();
    Position previous = new("main.c", 0);
    static Header? ReadHeader(List<Token> tokens, int index = 0) {
        if (index >= tokens.Count) return null;
        Token token = tokens[index];
        if (token.Kind is "string" or "header") return new(token.Text[1..^1], token.Text, token.Kind == "string", index + 1);
        if (token.Text == "<") {
            int end = tokens.FindIndex(index + 1, t => t.Text == ">");
            if (end < 0) throw new PPError("missing terminating > character");
            string name = Lexer.Render(tokens.GetRange(index + 1, end - index - 1));
            return new(name, "<" + name + ">", false, end + 1);
        } return null;
    }
    void Diagnostic(Position position, string kind, string message) => expander.Diagnostic(position, kind, message);
    void Event(Position position, string text) => history.Add($"{position}: {text}");
    void PoisonCheck(List<Token> tokens, Inclusion state) {
        foreach (Token token in tokens) if (token.Kind == "identifier" && poison.Contains(token.Text)) Diagnostic(state.Position(token.Line), "error", $"attempt to use poisoned \"{token.Text}\"");
    }
    void Unused(Macro definition) {
        if (definition.Main && definition.Expanded == 0 && definition.Tested == 0) Diagnostic(definition.Position, "warning", $"macro \"{definition.Name}\" is not used");
    }
    void Define(List<Token> tokens, Position position, bool main) {
        Macro definition = Definitions.Parse(tokens, position, main);
        string name = definition.Name;
        if (expander.Table.TryGetValue(name, out Macro? old)) {
            if (old.Identical(definition)) {
                Event(position, "identical " + definition.Signature);
                return;
            } Unused(old);
            Diagnostic(position, "warning", $"\"{name}\" redefined (previous definition at {old.Position})");
            Event(position, "redefine " + definition.Signature);
        } else Event(position, "define " + definition.Signature);
        expander.Table[name] = definition;
        ever.Add(name);
    }
    void Undef(List<Token> tokens, Position position) {
        string name = Definitions.Name(tokens, "undef");
        if (tokens.Count > 1) Diagnostic(position, "warning", "extra tokens at end of #undef directive");
        if (expander.Table.Remove(name, out Macro? old)) {
            Unused(old);
            Event(position, "undef " + name);
        } else Event(position, $"undef {name} (not defined)");
    }
    void Marker(string file, int line, string flag = "") {
        output.Add($"# {line} \"{file}\"{flag}");
        previous = new(file, line - 1);
    }
    void OutputLine(string text, int physical, Inclusion state) {
        Position position = state.Position(physical);
        if (previous.File == position.File && previous.Line < position.Line && position.Line <= previous.Line + 8) output.AddRange(Enumerable.Repeat("", position.Line - previous.Line - 1));
        else Marker(position.File, position.Line);
        output.Add(text);
        previous = position;
        includes.Files[state.Path].Output++;
    }
    void Flush(Inclusion state) {
        PoisonCheck(state.Segment, state);
        List<Token> tokens = expander.Expand(state.Segment, state.File, state.Offset);
        state.Segment.Clear();
        int i = 0;
        while (i < tokens.Count) {
            int end = i + 1;
            while (end < tokens.Count && tokens[end].Line == tokens[i].Line) end++;
            OutputLine(Lexer.Render(tokens.GetRange(i, end - i), true), tokens[i].Line, state);
            i = end;
        }
    }
    bool Defined(string name) {
        if (expander.Table.TryGetValue(name, out Macro? definition)) {
            definition.Tested++;
            return true;
        } return Definitions.Builtin(name) || name == "__has_include";
    }
    List<Token> ReplaceOperators(List<Token> tokens) {
        List<Token> result = new();
        int i = 0;
        while (i < tokens.Count) {
            Token token = tokens[i];
            if (token.Kind == "identifier" && token.Text == "defined") {
                i++;
                bool parenthesis = i < tokens.Count && tokens[i].Text == "(";
                if (parenthesis) i++;
                if (i >= tokens.Count || tokens[i].Kind != "identifier") throw new PPError("operator \"defined\" requires an identifier");
                string name = tokens[i++].Text;
                if (parenthesis) {
                    if (i >= tokens.Count || tokens[i].Text != ")") throw new PPError("missing ')' after \"defined\"");
                    i++;
                } result.Add(new("number", Defined(name) ? "1" : "0", token.Line, token.Space));
            } else if (token.Kind == "identifier" && token.Text == "__has_include") {
                i++;
                if (i >= tokens.Count || tokens[i].Text != "(") throw new PPError("missing '(' after \"__has_include\"");
                i++;
                Header? header = ReadHeader(tokens, i);
                if (header == null || header.Name.Length == 0) throw new PPError("operator \"__has_include\" requires a header-name");
                i = header.End;
                if (i >= tokens.Count || tokens[i].Text != ")") throw new PPError("missing ')' after \"__has_include\" operand");
                i++;
                result.Add(new("number", IncludeManager.Search(header.Name, header.Quoted) == null ? "0" : "1", token.Line, token.Space));
            } else {
                result.Add(token);
                i++;
            }
        }
        return result;
    }
    (bool Taken, string Result) Test(string directive, List<Token> tokens, Position position, Inclusion state) {
        PoisonCheck(tokens, state);
        if (directive is not ("if" or "elif")) {
            if (tokens.Count == 0) {
                Diagnostic(position, "error", $"no macro name given in #{directive} directive");
                return (false, "not taken (error)");
            } if (tokens[0].Kind != "identifier") {
                Diagnostic(position, "error", "macro names must be identifiers");
                return (false, "not taken (error)");
            } if (tokens.Count > 1) Diagnostic(position, "warning", $"extra tokens at end of #{directive} directive");
            bool value = Defined(tokens[0].Text), taken = directive is "ifndef" or "elifndef" ? !value : value;
            return (taken, taken ? "taken" : "not taken");
        }
        List<Token> replaced;
        try {
            replaced = ReplaceOperators(tokens);
        } catch (PPError error) {
            Diagnostic(position, "error", error.Reason);
            return (false, "not taken (error)");
        }
        List<Token> expanded = expander.Expand(replaced, state.File, state.Offset);
        var (number, diagnostics) = ExpressionParser.Test(expanded, directive);
        foreach (var (kind, message) in diagnostics) Diagnostic(position, kind, message);
        string result = number.HasValue ? (number.Value != 0 ? "taken" : "not taken") + $" (value {number.Value})" : "not taken (error)";
        return (number.HasValue && number.Value != 0, result + " [" + Lexer.Render(expanded, true) + "]");
    }
    void Close(ConditionalBlock block, int end, Inclusion state) {
        if (block.SkipStart is int start && end >= start) {
            regions.Add($"{state.File}:{start + state.Offset}-{end + state.Offset} lines={end - start + 1}");
            includes.Files[state.Path].SkippedLines += end - start + 1;
        } block.SkipStart = null;
    }
    void Conditional(string directive, List<Token> operands, LogicalLine line, Inclusion state) {
        Position position = state.Position(line.Tokens[0].Line);
        bool opening = directive is "if" or "ifdef" or "ifndef";
        int level = opening ? state.Blocks.Count : state.Blocks.Count - 1;
        string result;
        if (opening) {
            ConditionalBlock block = new(directive, position, state.Active);
            if (block.Parent) {
                var (taken, text) = Test(directive, operands, position, state);
                block.Chosen = block.Active = taken;
                if (!taken) block.SkipStart = line.End + 1;
                result = text;
            } else result = "skipped";
            state.Blocks.Add(block);
        }
        else {
            ConditionalBlock? block = state.Blocks.LastOrDefault();
            if (block == null) {
                Diagnostic(position, "error", $"#{directive} without #if");
                return;
            } Close(block, line.Start - 1, state);
            if (directive == "endif") {
                state.Blocks.RemoveAt(state.Blocks.Count - 1);
                if (block.Parent && operands.Count > 0) Diagnostic(position, "warning", "extra tokens at end of #endif directive");
                result = $"closes #{block.Kind} at line {block.Start.Line}";
            }
            else {
                if (block.ElseSeen) Diagnostic(position, "error", $"#{directive} after #else");
                if (directive == "else") {
                    if (block.Parent && operands.Count > 0) Diagnostic(position, "warning", "extra tokens at end of #else directive");
                    block.ElseSeen = true;
                    if (block.Parent) {
                        block.Active = !block.Chosen;
                        block.Chosen = true;
                        result = block.Active ? "taken" : "not taken";
                    } else result = "skipped";
                }
                else if (!block.Parent) {
                    block.Active = false;
                    result = "skipped";
                } else if (block.Chosen) {
                    block.Active = false;
                    result = "not evaluated";
                } else {
                    var (taken, text) = Test(directive, operands, position, state);
                    block.Active = taken;
                    if (taken) block.Chosen = true;
                    result = text;
                }
                if (block.Parent && !block.Active) block.SkipStart = line.End + 1;
            }
        }
        string rendering = "#" + directive + (operands.Count == 0 ? "" : " " + Lexer.Render(operands));
        records.Add(position + ": " + new string(' ', 2 * level) + rendering + " => " + result);
        results.Add(result);
    }
    void Include(List<Token> operands, LogicalLine line, Inclusion state) {
        Position position = state.Position(line.Tokens[0].Line);
        List<Token> tokens = operands;
        Header? header = ReadHeader(tokens);
        if (header == null && tokens.Count > 0) {
            tokens = expander.Expand(tokens, state.File, state.Offset);
            header = ReadHeader(tokens);
        } if (header == null) throw new PPError("#include expects \"FILENAME\" or <FILENAME>");
        if (header.End < tokens.Count) Diagnostic(position, "warning", "extra tokens at end of #include directive");
        if (header.Name.Length == 0) throw new PPError("empty filename in #include");
        string prefix = new string(' ', 2 * (state.Depth + 1)) + line.Tokens[0].Line + ": ";
        string? path = IncludeManager.Search(header.Name, header.Quoted);
        if (path == null) {
            tree.Add(prefix + header.Rendering + " [not found]");
            throw new PPError("cannot find include file " + header.Rendering);
        }
        if (includes.Files.TryGetValue(path, out SourceFile? file)) {
            if (file.Once) {
                tree.Add(prefix + path + " [skipped: pragma once]");
                file.Skipped++;
                return;
            } if (file.GuardName != null && expander.Table.ContainsKey(file.GuardName)) {
                tree.Add(prefix + path + $" [skipped: guard {file.GuardName}]");
                file.Skipped++;
                return;
            }
        }
        if (state.Depth + 1 > 8) {
            tree.Add(prefix + path + " [too deep]");
            throw new PPError("#include nested too deeply");
        } tree.Add(prefix + path);
        Marker(path, 1, " 1");
        Process(path, state.Depth + 1);
        Marker(state.File, line.End + 1 + state.Offset, " 2");
    }
    void Pragma(List<Token> operands, LogicalLine line, Position position, Inclusion state) {
        Token? first = operands.FirstOrDefault();
        if (first?.Kind == "identifier" && first.Text == "once") {
            if (operands.Count > 1) Diagnostic(position, "warning", "extra tokens at end of #pragma once directive");
            if (state.Depth == 0) Diagnostic(position, "warning", "#pragma once in main file");
            includes.Files[state.Path].Once = true;
        }
        else if (operands.Count >= 2 && operands[0].Text == "GCC" && operands[1].Text == "poison") {
            if (operands.Skip(2).Any(token => token.Kind != "identifier")) throw new PPError("invalid #pragma GCC poison directive");
            foreach (Token token in operands.Skip(2)) {
                if (expander.Table.ContainsKey(token.Text)) Diagnostic(position, "warning", $"poisoning existing macro \"{token.Text}\"");
                poison.Add(token.Text);
            }
        }
        else if (first?.Kind == "identifier" && first.Text is "push_macro" or "pop_macro") {
            string command = first.Text;
            if (operands.Count != 4 || operands[1].Text != "(" || operands[2].Kind != "string" || operands[3].Text != ")") throw new PPError($"invalid #pragma {command} directive");
            string name = operands[2].Text[1..^1];
            if (!saves.TryGetValue(name, out Stack<Macro?>? stack)) {
                stack = new();
                saves[name] = stack;
            }
            if (command == "push_macro") {
                stack.Push(expander.Table.GetValueOrDefault(name));
                Event(position, "push " + name);
            } else if (stack.Count == 0) Diagnostic(position, "warning", $"no matching push_macro for \"{name}\"");
            else {
                Macro? old = stack.Pop();
                if (old == null) expander.Table.Remove(name);
                else expander.Table[name] = old;
                Event(position, "pop " + name + (old == null ? " (undefined)" : ""));
            }
        } else OutputLine("#pragma" + (operands.Count == 0 ? "" : " " + Lexer.Render(operands)), line.Tokens[0].Line, state);
    }
    void Directive(string name, List<Token> operands, LogicalLine line, Inclusion state) {
        Position position = state.Position(line.Tokens[0].Line);
        if (line.Tokens.Count == 1) return;
        if (!(name == "pragma" && operands.Count >= 2 && operands[0].Text == "GCC" && operands[1].Text == "poison")) PoisonCheck(operands, state);
        try {
            switch (name) {
                case "define": Define(operands, position, state.Depth == 0);
                break;
                case "undef": Undef(operands, position);
                break;
                case "include": Include(operands, line, state);
                break;
                case "line": {
                    bool Decimal(Token token) => token.Kind == "number" && token.Text.Length > 0 && token.Text.All(c => c is >= '0' and <= '9');
                    List<Token> tokens = operands.FirstOrDefault() is {
                    } first && Decimal(first) ? operands : expander.Expand(operands, state.File, state.Offset);
                    if (tokens.Count is < 1 or > 2 || !Decimal(tokens[0]) || tokens.Count == 2 && tokens[1].Kind != "string") throw new PPError("invalid #line directive");
                    long number = long.Parse(tokens[0].Text, CultureInfo.InvariantCulture);
                    if (number is < 1 or > int.MaxValue) throw new PPError("line number out of range");
                    state.Offset = (int)number - line.End - 1;
                    if (tokens.Count == 2) state.File = tokens[1].Text[1..^1];
                    break;
                }
                case "error": case "warning": Diagnostic(position, name, "#" + name + (operands.Count == 0 ? "" : " " + Lexer.Render(operands)));
                break;
                case "pragma": Pragma(operands, line, position, state);
                break;
                default: throw new PPError("invalid preprocessing directive #" + line.Tokens[1].Text);
            }
        } catch (PPError error) {
            Diagnostic(position, "error", error.Reason);
        }
    }
    void Process(string path, int depth) {
        SourceFile file = includes.Enter(path);
        Inclusion state = new(path, depth);
        foreach (LogicalLine line in file.Lines) {
            List<Token> tokens = line.Tokens;
            if (tokens.FirstOrDefault()?.Text == "#") {
                string name = tokens.Count >= 2 && tokens[1].Kind == "identifier" ? tokens[1].Text : "";
                List<Token> operands = tokens.Skip(2).ToList();
                if (name is "if" or "ifdef" or "ifndef" or "elif" or "elifdef" or "elifndef" or "else" or "endif") {
                    Flush(state);
                    Conditional(name, operands, line, state);
                } else if (state.Active) {
                    Flush(state);
                    Directive(name, operands, line, state);
                }
            } else if (state.Active) state.Segment.AddRange(tokens);
        } Flush(state);
        foreach (ConditionalBlock block in state.Blocks) Close(block, file.PhysicalLines, state);
        foreach (ConditionalBlock block in state.Blocks) Diagnostic(block.Start, "error", "unterminated #" + block.Kind);
    }
    public void Run() {
        string[] definitions = File.ReadAllLines("input/defines.txt");
        for (int i = 0; i < definitions.Length; i++) {
            string line = definitions[i];
            if (line.Length == 0) continue;
            int equals = line.IndexOf('=');
            string text = equals < 0 ? line + " 1" : line[..equals] + " " + line[(equals + 1)..];
            Position position = new("defines.txt", i + 1);
            List<Token> tokens = Lexer.Lex(text + "\n").SelectMany(logical => logical.Tokens).ToList();
            try {
                Define(tokens, position, false);
            } catch (PPError error) {
                Diagnostic(position, "error", error.Reason);
            }
        } Marker("main.c", 1);
        Process("main.c", 0);
        foreach (string name in expander.Table.Keys.Order(StringComparer.Ordinal)) Unused(expander.Table[name]);
        Finish();
    }
    void Finish() {
        List<string> includeLines = tree.Concat(new[] {
            "", "== files =="
        }).ToList();
        foreach (string path in includes.Files.Keys.Order(StringComparer.Ordinal)) {
            SourceFile file = includes.Files[path];
            includeLines.Add($"{path} entered={file.Entered} skipped={file.Skipped} lines={file.PhysicalLines} output_lines={file.Output} skipped_lines={file.SkippedLines} guard={file.GuardName ?? "-"} once={(file.Once ? "yes" : "no")}");
        } includeLines.Add("");
        string dependency = "main.o:";
        bool hasPath = false;
        foreach (string path in includes.Order) {
            if (dependency.Length + 1 + path.Length > 76 && hasPath) {
                includeLines.Add(dependency + " " + (char)92);
                dependency = " ";
                hasPath = false;
            } dependency += " " + path;
            hasPath = true;
        } includeLines.Add(dependency);
        Dictionary<string, Macro> table = expander.Table;
        Dictionary<string, List<string>> references = table.ToDictionary(pair => pair.Key, pair => pair.Value.Replacement.Where(token => token.Kind == "identifier" && table.ContainsKey(token.Text) && !(pair.Value.Parameters?.Contains(token.Text) ?? false)).Select(token => token.Text).Distinct().Order(StringComparer.Ordinal).ToList());
        bool Recursive(string name) {
            HashSet<string> seen = new();
            Stack<string> pending = new(references[name]);
            while (pending.TryPop(out string? current)) {
                if (current == name) return true;
                if (seen.Add(current)) foreach (string next in references[current]) pending.Push(next);
            } return false;
        }
        List<string> macros = new[] {
            "== history =="
        }.Concat(history).Concat(new[] {
            "", "== table =="
        }).ToList();
        foreach (string name in table.Keys.Order(StringComparer.Ordinal)) {
            Macro definition = table[name];
            macros.AddRange(new[] {
                definition.Definition, $"  at {definition.Position} expanded={definition.Expanded} tested={definition.Tested} recursive={(Recursive(name) ? "yes" : "no")}", "  refs:" + string.Concat(references[name].Select(reference => " " + reference))
            });
        } int functionLike = table.Values.Count(definition => definition.Parameters != null);
        macros.AddRange(new[] {
            "", $"macros={table.Count} object_like={table.Count - functionLike} function_like={functionLike}", "undefined:" + string.Concat(ever.Except(table.Keys).Order(StringComparer.Ordinal).Select(name => " " + name)), $"builtins: __COUNTER__={expander.Uses["__COUNTER__"]} __FILE__={expander.Uses["__FILE__"]} __LINE__={expander.Uses["__LINE__"]}"
        });
        int Count(string prefix) => results.Count(result => result.StartsWith(prefix, StringComparison.Ordinal));
        List<string> conditionals = records.Concat(new[] {
            "", "== skipped regions =="
        }).Concat(regions).Concat(new[] {
            "", $"directives={records.Count} taken={Count("taken")} not_taken={Count("not taken")} skipped={Count("skipped")} not_evaluated={Count("not evaluated")} endif={Count("closes")} regions={regions.Count}"
        }).ToList();
        int errors = expander.Diagnostics.Count(diagnostic => diagnostic.Kind == "error");
        List<string> diagnostics = expander.Diagnostics.Select(diagnostic => $"{diagnostic.Position}: {diagnostic.Kind}: {diagnostic.Message}").Append($"errors={errors} warnings={expander.Diagnostics.Count - errors}").ToList();
        Write("preprocessed.txt", output);
        Write("includes.txt", includeLines);
        Write("macros.txt", macros);
        Write("conditionals.txt", conditionals);
        Write("diagnostics.txt", diagnostics);
    }
    static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, lines.Count == 0 ? "" : string.Join("\n", lines) + "\n");
    }
}
static class Program {
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;
        new Preprocessor().Run();
    }
}
