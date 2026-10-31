using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
sealed class SourceFile {
    public List<LogicalLine> Lines {
        get;
    }
    public int PhysicalLines {
        get;
    }
    public string? GuardName {
        get;
    }
    public SourceFile(string source) {
        Lines = Lexer.Lex(source);
        PhysicalLines = source.Count(c => c == '\n');
        GuardName = IncludeManager.Guard(Lines);
    }
    public int Entered {
        get;
        set;
    } public int Skipped {
        get;
        set;
    } public int Output {
        get;
        set;
    } public int SkippedLines {
        get;
        set;
    } public bool Once {
        get;
        set;
    }
}
sealed class IncludeManager {
    public Dictionary<string, SourceFile> Files {
        get;
    } = new();
    public List<string> Order {
        get;
    } = new();
    public static string? Search(string name, bool quoted) {
        if (quoted && File.Exists("input/" + name)) return name;
        string path = "include/" + name;
        return File.Exists("input/" + path) ? path : null;
    }
    public static string? Guard(List<LogicalLine> original) {
        List<LogicalLine> lines = original.Where(line => line.Tokens.Count > 0).ToList();
        if (lines.Count == 0) return null;
        List<Token> first = lines[0].Tokens, last = lines[^1].Tokens;
        if (first.Count != 3 || first[0].Text != "#" || first[1].Text != "ifndef" || first[2].Kind != "identifier" || last.Count != 2 || last[0].Text != "#" || last[1].Text != "endif") return null;
        int depth = 0;
        for (int i = 0; i < lines.Count; i++) {
            List<Token> tokens = lines[i].Tokens;
            string directive = tokens.Count >= 2 && tokens[0].Text == "#" && tokens[1].Kind == "identifier" ? tokens[1].Text : "";
            if (depth == 1 && directive is "elif" or "elifdef" or "elifndef" or "else") return null;
            if (directive is "if" or "ifdef" or "ifndef") depth++;
            else if (directive == "endif") depth--;
            if (depth == 0 && i + 1 != lines.Count) return null;
        } return depth == 0 ? first[2].Text : null;
    }
    public SourceFile Enter(string path) {
        if (!Files.TryGetValue(path, out SourceFile? file)) {
            file = new(File.ReadAllText("input/" + path));
            Files[path] = file;
            Order.Add(path);
        } file.Entered++;
        return file;
    }
}
