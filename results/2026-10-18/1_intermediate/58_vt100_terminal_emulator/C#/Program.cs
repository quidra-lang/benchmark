using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

record struct Attributes(int Flags = 0, string Fg = "default", string Bg = "default");
record struct Cell(char Character, Attributes Attributes);
record Saved(int Row, int Col, Attributes Attributes, bool Origin, bool G0, bool G1, bool GL);
enum ParseState { Ground, Escape, EscapeIntermediate, CsiEntry, CsiParam, CsiIntermediate, CsiIgnore, Osc }

sealed class Terminal
{
    const int IRM = 0, LNM = 1, CKM = 2, SCNM = 3, ORIGIN = 4,
              WRAP = 5, VISIBLE = 6, KEYPAD = 7, BRACKETED = 8;
    static readonly Attributes Default = new(0, "default", "default");
    static readonly string[] FlagNames = { "bold", "dim", "italic", "underline", "blink", "reverse", "hidden", "strike" };
    static readonly string[] ModeNames = { "IRM", "LNM", "DECCKM", "DECSCNM", "DECOM", "DECAWM", "DECTCEM", "DECKPAM", "BRACKETED" };
    readonly int width, height;
    Cell[][][] screens = Array.Empty<Cell[][]>();
    int screen, row, col, top, bottom, shape, last = -1;
    bool pending, g0, g1, gl;
    readonly bool[] modes = new bool[9];
    readonly SortedSet<int> tabs = new();
    readonly Saved?[] saved = new Saved?[2];
    readonly List<string> scrollback = new();
    string? title;
    Attributes attributes = Default;
    ParseState state;
    readonly StringBuilder intermediate = new(), parameters = new(), osc = new();
    string marker = "";
    int bytes, printed, sequences, bells, replies, dumps;
    readonly int[] ignored = new int[4];
    Cell[] BlankRow() => Enumerable.Repeat(new Cell(' ', Default), width).ToArray();
    Cell[][] BlankScreen() => Enumerable.Range(0, height).Select(_ => BlankRow()).ToArray();
    Cell[][] Screen => screens[screen];

    public Terminal(int width, int height)
    {
        this.width = width; this.height = height;
        Reset();
    }
    void Reset()
    {
        screens = new[] { BlankScreen(), BlankScreen() };
        screen = 0; row = col = top = shape = 1; bottom = height;
        pending = g0 = g1 = gl = false; attributes = Default;
        Array.Clear(modes); modes[WRAP] = modes[VISIBLE] = true;
        saved[0] = saved[1] = null; scrollback.Clear(); title = null; last = -1;
        tabs.Clear(); for (int c = 9; c <= width; c += 8) tabs.Add(c);
        state = ParseState.Ground; intermediate.Clear(); parameters.Clear(); osc.Clear(); marker = "";
    }
    string RowText(Cell[] cells) => new string(cells.Select(c => c.Character).ToArray()).TrimEnd(' ');
    void Erase(int r, int start, int end)
    {
        for (int c = start; c <= end; ++c) Screen[r-1][c-1] = new Cell(' ', Default);
    }
    void Scroll(bool up, int count)
    {
        for (int k = 0; k < count; ++k)
        {
            if (up)
            {
                if (screen == 0 && top == 1)
                {
                    scrollback.Add(RowText(Screen[top-1]));
                    if (scrollback.Count > 100) scrollback.RemoveAt(0);
                }
                for (int r = top; r < bottom; ++r) Screen[r-1] = Screen[r];
                Screen[bottom-1] = BlankRow();
            }
            else
            {
                for (int r = bottom; r > top; --r) Screen[r-1] = Screen[r-2];
                Screen[top-1] = BlankRow();
            }
        }
    }
    void LineFeed()
    {
        if (row == bottom) Scroll(true, 1);
        else if (row < height) ++row;
    }
    void Tab(bool reverse)
    {
        int c = col + (reverse ? -1 : 1);
        while (c >= 1 && c <= width && !tabs.Contains(c)) c += reverse ? -1 : 1;
        col = Math.Clamp(c, 1, width);
    }
    int Address(int n) => modes[ORIGIN] ? Math.Min(top+n-1, bottom) : Math.Min(n, height);
    void Home() { row = Address(1); col = 1; }
    void Save() => saved[screen] = new(row, col, attributes, modes[ORIGIN], g0, g1, gl);
    void Restore()
    {
        Saved? s = saved[screen];
        row = s?.Row ?? 1; col = s?.Col ?? 1; attributes = s?.Attributes ?? Default;
        modes[ORIGIN] = s?.Origin ?? false;
        g0 = s?.G0 ?? false; g1 = s?.G1 ?? false; gl = s?.GL ?? false;
        pending = false;
    }
    void Write(char c)
    {
        ++printed; last = c;
        if (pending) { pending = false; col = 1; LineFeed(); }
        if (modes[IRM])
            for (int x = width-1; x >= col; --x) Screen[row-1][x] = Screen[row-1][x-1];
        Screen[row-1][col-1] = new Cell(c, attributes);
        if (col < width) ++col; else if (modes[WRAP]) pending = true;
    }
    void Print(char c)
    {
        if (gl ? g1 : g0)
            c = c switch { '`' => '*', 'a' => '#', 'q' => '-', 'x' => '|', '~' => 'o',
                'j' or 'k' or 'l' or 'm' or 'n' or 't' or 'u' or 'v' or 'w' => '+', _ => c };
        Write(c);
    }
    void Control(int b)
    {
        if (b >= 8 && b <= 13) pending = false;
        switch (b)
        {
            case 7: ++bells; break;
            case 8: col = Math.Max(1, col-1); break;
            case 9: Tab(false); break;
            case 10: case 11: case 12: LineFeed(); if (modes[LNM]) col = 1; break;
            case 13: col = 1; break;
            case 14: gl = true; break;
            case 15: gl = false; break;
        }
    }
    static string Palette(int n)
    {
        string[] colors = { "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white" };
        return n < 8 ? colors[n] : n < 16 ? "bright-" + colors[n-8] : n.ToString();
    }
    bool Sgr(int[] p)
    {
        Attributes a = attributes;
        for (int i = 0; i < p.Length; ++i)
        {
            int v = p[i], bit = v >= 1 && v <= 5 ? v-1 : v >= 7 && v <= 9 ? v-2 : -1;
            if (v == 0) a = Default;
            else if (bit >= 0) a = a with { Flags = a.Flags | (1 << bit) };
            else if (v == 22) a = a with { Flags = a.Flags & ~3 };
            else if (v >= 23 && v <= 25) a = a with { Flags = a.Flags & ~(1 << (v-21)) };
            else if (v >= 27 && v <= 29) a = a with { Flags = a.Flags & ~(1 << (v-22)) };
            else if (v >= 30 && v <= 37) a = a with { Fg = Palette(v-30) };
            else if (v >= 90 && v <= 97) a = a with { Fg = Palette(v-82) };
            else if (v >= 40 && v <= 47) a = a with { Bg = Palette(v-40) };
            else if (v >= 100 && v <= 107) a = a with { Bg = Palette(v-92) };
            else if (v == 39) a = a with { Fg = "default" };
            else if (v == 49) a = a with { Bg = "default" };
            else if (v == 38 || v == 48)
            {
                string color;
                if (i+2 < p.Length && p[i+1] == 5 && p[i+2] <= 255) { color = Palette(p[i+2]); i += 2; }
                else if (i+4 < p.Length && p[i+1] == 2 && p[i+2] <= 255 && p[i+3] <= 255 && p[i+4] <= 255)
                { color = $"#{p[i+2]:x2}{p[i+3]:x2}{p[i+4]:x2}"; i += 4; }
                else return false;
                a = v == 38 ? a with { Fg = color } : a with { Bg = color };
            }
            else return false;
        }
        attributes = a; return true;
    }
    static int ModeIndex(int p, bool dec) => dec ? p switch
    { 1 => CKM, 5 => SCNM, 6 => ORIGIN, 7 => WRAP, 25 => VISIBLE, 2004 => BRACKETED, _ => -1 }
        : p switch { 4 => IRM, 20 => LNM, _ => -1 };
    bool SetModes(int[] p, bool dec, bool on)
    {
        if (p.Any(v => ModeIndex(v, dec) < 0 && !(dec && (v == 47 || v == 1047 || v == 1048 || v == 1049)))) return false;
        foreach (int v in p)
        {
            int index = ModeIndex(v, dec);
            if (index >= 0)
            {
                modes[index] = on;
                if (index == ORIGIN) { pending = false; Home(); }
                if (index == WRAP && !on) pending = false;
            }
            else if (v == 1048) { if (on) Save(); else Restore(); }
            else
            {
                pending = false;
                if (on && screen == 0)
                {
                    if (v == 1049) Save(); screen = 1;
                    if (v == 1049) screens[1] = BlankScreen();
                }
                else if (!on && screen == 1)
                {
                    if (v == 1047) screens[1] = BlankScreen(); screen = 0;
                    if (v == 1049) Restore();
                }
            }
        }
        return true;
    }
    void Osc()
    {
        string s = osc.ToString();
        if (s.StartsWith("0;") || s.StartsWith("2;")) { title = s[2..]; ++sequences; }
        else ++ignored[0];
    }
    void Escape(char final)
    {
        string k = intermediate.ToString() + final;
        switch (k)
        {
            case "7": Save(); break;
            case "8": Restore(); break;
            case "D": case "E": pending = false; if (final == 'E') col = 1; LineFeed(); break;
            case "M": pending = false; if (row == top) Scroll(false, 1); else row = Math.Max(1, row-1); break;
            case "H": tabs.Add(col); break;
            case "c": Reset(); break;
            case "=": modes[KEYPAD] = true; break;
            case ">": modes[KEYPAD] = false; break;
            case "\\": break;
            case "(0": g0 = true; break;
            case "(B": g0 = false; break;
            case ")0": g1 = true; break;
            case ")B": g1 = false; break;
            case "#8":
                for (int r = 1; r <= height; ++r)
                    for (int c = 1; c <= width; ++c) Screen[r-1][c-1] = new Cell('E', Default);
                top = 1; bottom = height; modes[ORIGIN] = false; row = col = 1; pending = false; break;
            default: ++ignored[0]; return;
        }
        ++sequences;
    }
    void Reply(string s) { ++replies; Console.WriteLine("REPLY " + s); }
    void Csi(char final)
    {
        string[] fields = parameters.Length == 0 ? Array.Empty<string>() : parameters.ToString().Split(';');
        if (fields.Length >= 17) { ++ignored[3]; return; }
        int[] raw = fields.Select(f => { int v = 0; foreach (char c in f) v = Math.Min(9999, v*10+c-'0'); return v; }).ToArray();
        int[] p = raw.Length == 0 ? new[] { 0 } : raw;
        int first = p[0], second = p.Length > 1 ? p[1] : 0, n = Math.Max(first, 1);
        string k = marker + intermediate.ToString() + final;
        if ((k == "J" && first > 3) || (k == "K" && first > 2) || (k == "g" && first != 0 && first != 3)
            || (k == " q" && first > 6) || (k == "n" && first != 5 && first != 6)
            || (k == "?n" && first != 6) || ((k == "c" || k == ">c") && first != 0) || (k == "t" && first != 18))
        { ++ignored[0]; return; }
        if (k.Length == 1 && "ABCDEFGHIJKLM PSTXZ`adef@".Contains(final) && final != ' ') pending = false;
        bool supported = true;
        switch (k)
        {
            case "A": case "F": row = Math.Max(row-n, row >= top ? top : 1); if (k == "F") col = 1; break;
            case "B": case "e": case "E": row = Math.Min(row+n, row <= bottom ? bottom : height); if (k == "E") col = 1; break;
            case "C": case "a": col = Math.Min(col+n, width); break;
            case "D": col = Math.Max(col-n, 1); break;
            case "G": case "`": col = Math.Min(n, width); break;
            case "H": case "f": row = Address(n); col = Math.Min(Math.Max(second, 1), width); break;
            case "d": row = Address(n); break;
            case "I": case "Z": for (int i = 0; i < n; ++i) Tab(k == "Z"); break;
            case "J":
                if (first == 3) scrollback.Clear();
                else for (int r = 1; r <= height; ++r)
                {
                    if (first == 2 || (first == 0 && r > row) || (first == 1 && r < row)) Erase(r, 1, width);
                    else if (r == row) Erase(r, first == 0 ? col : 1, first == 1 ? col : width);
                }
                break;
            case "K": Erase(row, first == 0 ? col : 1, first == 1 ? col : width); break;
            case "X": Erase(row, col, Math.Min(col+n-1, width)); break;
            case "@": case "P":
                int amount = Math.Min(n, width-col+1);
                if (k == "@")
                {
                    for (int c = width-1; c >= col-1+amount; --c) Screen[row-1][c] = Screen[row-1][c-amount];
                    Erase(row, col, col+amount-1);
                }
                else
                {
                    for (int c = col-1; c < width-amount; ++c) Screen[row-1][c] = Screen[row-1][c+amount];
                    Erase(row, width-amount+1, width);
                }
                break;
            case "L": case "M":
                if (row >= top && row <= bottom)
                {
                    int lines = Math.Min(n, bottom-row+1);
                    if (k == "L")
                    {
                        for (int r = bottom; r >= row+lines; --r) Screen[r-1] = Screen[r-lines-1];
                        for (int r = row; r < row+lines; ++r) Screen[r-1] = BlankRow();
                    }
                    else
                    {
                        for (int r = row; r <= bottom-lines; ++r) Screen[r-1] = Screen[r+lines-1];
                        for (int r = bottom-lines+1; r <= bottom; ++r) Screen[r-1] = BlankRow();
                    }
                    col = 1;
                }
                break;
            case "S": case "T": Scroll(k == "S", Math.Min(n, bottom-top+1)); break;
            case "b": if (last >= 0) for (int i = 0; i < n; ++i) Write((char)last); break;
            case "g": if (first == 0) tabs.Remove(col); else tabs.Clear(); break;
            case "m": supported = Sgr(p); break;
            case "h": case "l": case "?h": case "?l": supported = SetModes(p, k[0] == '?', final == 'h'); break;
            case " q": shape = n; break;
            case "r":
                int newTop = first == 0 ? 1 : first, newBottom = Math.Min(second == 0 ? height : second, height);
                if (newTop >= newBottom) { ++ignored[3]; return; }
                pending = false; top = newTop; bottom = newBottom; Home(); break;
            case "s": Save(); break;
            case "u": Restore(); break;
            case "!p":
                pending = false; modes[IRM] = modes[CKM] = modes[ORIGIN] = modes[KEYPAD] = false;
                modes[WRAP] = modes[VISIBLE] = true; top = 1; bottom = height; attributes = Default;
                g0 = g1 = gl = false; saved[screen] = null; break;
            case "n": Reply(first == 5 ? "^[[0n" : $"^[[{(modes[ORIGIN] ? Math.Max(row-top+1, 1) : row)};{col}R"); break;
            case "?n": Reply($"^[[?{(modes[ORIGIN] ? Math.Max(row-top+1, 1) : row)};{col};1R"); break;
            case "c": Reply("^[[?1;2c"); break;
            case ">c": Reply("^[[>0;95;0c"); break;
            case "t": Reply($"^[[8;{height};{width}t"); break;
            case "$p": case "?$p":
                bool dec = k[0] == '?'; int index = ModeIndex(first, dec);
                int status = index >= 0 ? (modes[index] ? 1 : 2) : dec && (first == 47 || first == 1047 || first == 1049) ? (screen == 1 ? 1 : 2) : 0;
                Reply($"^[[{(dec ? "?" : "")}{first};{status}$y"); break;
            default: supported = false; break;
        }
        if (supported) ++sequences; else ++ignored[0];
    }
    public void Feed(int b)
    {
        ++bytes;
        if (b == 27)
        {
            if (state == ParseState.Osc) Osc(); else if (state != ParseState.Ground) ++ignored[2];
            marker = ""; intermediate.Clear(); parameters.Clear(); osc.Clear(); state = ParseState.Escape; return;
        }
        if (b == 24 || b == 26)
        { if (state != ParseState.Ground) ++ignored[2]; state = ParseState.Ground; return; }
        if (b < 32)
        {
            if (state == ParseState.Osc) { if (b == 7) { Osc(); state = ParseState.Ground; } }
            else Control(b);
            return;
        }
        char c = (char)b;
        if (state == ParseState.CsiEntry)
        {
            state = ParseState.CsiParam;
            if (b >= 60 && b <= 63) { marker = c.ToString(); return; }
        }
        switch (state)
        {
            case ParseState.Ground: Print(c); break;
            case ParseState.Osc: osc.Append(c); break;
            case ParseState.Escape:
                if (b <= 47) { intermediate.Append(c); state = ParseState.EscapeIntermediate; }
                else if (c == '[') state = ParseState.CsiEntry;
                else if (c == ']') state = ParseState.Osc;
                else { Escape(c); state = ParseState.Ground; }
                break;
            case ParseState.EscapeIntermediate:
                if (b <= 47) intermediate.Append(c); else { Escape(c); state = ParseState.Ground; }
                break;
            case ParseState.CsiParam:
                if ((c >= '0' && c <= '9') || c == ';') parameters.Append(c);
                else if (b <= 47) { intermediate.Append(c); state = ParseState.CsiIntermediate; }
                else if (b < 64) state = ParseState.CsiIgnore;
                else { Csi(c); state = ParseState.Ground; }
                break;
            case ParseState.CsiIntermediate:
                if (b <= 47) intermediate.Append(c);
                else if (b < 64) state = ParseState.CsiIgnore;
                else { Csi(c); state = ParseState.Ground; }
                break;
            case ParseState.CsiIgnore:
                if (b >= 64) { ++ignored[1]; state = ParseState.Ground; }
                break;
        }
    }
    public void Dump(string label)
    {
        Console.WriteLine($"{label} {(screen == 0 ? "main" : "alt")} cursor {row},{col} scrollback {scrollback.Count}{(pending ? " pending" : "")}");
        foreach (Cell[] cells in Screen) Console.WriteLine("|" + RowText(cells));
    }
    string Key(string name)
    {
        string[] nav = { "UP", "DOWN", "RIGHT", "LEFT", "HOME", "END" };
        int i = Array.IndexOf(nav, name);
        if (i >= 0) return (modes[CKM] ? "^[O" : "^[[") + "ABCDHF"[i];
        if (name.StartsWith("F"))
        {
            int f = int.Parse(name[1..]); int[] codes = { 15, 17, 18, 19, 20, 21, 23, 24 };
            return f <= 4 ? "^[O" + (char)('P'+f-1) : $"^[[{codes[f-5]}~";
        }
        if (name.StartsWith("KP") && name.Length == 3) return modes[KEYPAD] ? "^[O" + (char)('p'+name[2]-'0') : name[2].ToString();
        return name switch
        {
            "INSERT" => "^[[2~", "DELETE" => "^[[3~", "PAGEUP" => "^[[5~", "PAGEDOWN" => "^[[6~",
            "TAB" => "^I", "BACKSPACE" => "^?", "ESCAPE" => "^[", "KPENTER" when modes[KEYPAD] => "^[OM",
            _ => modes[LNM] ? "^M^J" : "^M"
        };
    }
    public void Directive(string line)
    {
        if (line == "%%DUMP") Dump($"DUMP {++dumps}");
        else if (line.StartsWith("%%KEY ")) { string name = line[6..]; Console.WriteLine($"KEY {name} {Key(name)}"); }
        else
        {
            string s = line[8..].Replace("^", "^^");
            Console.WriteLine("PASTE " + (modes[BRACKETED] ? "^[[200~" + s + "^[[201~" : s));
        }
    }
    static string AttrText(Attributes a)
    {
        List<string> parts = new();
        for (int i = 0; i < 8; ++i) if ((a.Flags & (1 << i)) != 0) parts.Add(FlagNames[i]);
        if (a.Fg != "default") parts.Add("fg=" + a.Fg);
        if (a.Bg != "default") parts.Add("bg=" + a.Bg);
        return string.Join(" ", parts);
    }
    public void Finish()
    {
        if (state != ParseState.Ground) ++ignored[2];
        Dump("FINAL"); Console.WriteLine(title == null ? "TITLE none" : $"TITLE \"{title}\"");
        List<string> changed = new();
        for (int i = 0; i < 9; ++i)
            if (modes[i] != (i == WRAP || i == VISIBLE)) changed.Add(ModeNames[i] + (modes[i] ? "=on" : "=off"));
        if (g0) changed.Add("G0=graphics"); if (g1) changed.Add("G1=graphics"); if (gl) changed.Add("GL=G1");
        if (shape != 1) changed.Add("CURSOR=" + shape);
        Console.WriteLine("MODES " + (changed.Count == 0 ? "default" : string.Join(" ", changed)));
        Console.WriteLine($"REGION {top}-{bottom}");
        Console.WriteLine("TABS " + (tabs.Count == 0 ? "none" : string.Join(",", tabs)));
        Console.WriteLine("SCROLLBACK " + scrollback.Count);
        foreach (string s in scrollback.Skip(Math.Max(0, scrollback.Count-5))) Console.WriteLine("|" + s);
        List<string> runs = new();
        for (int r = 0; r < height; ++r)
            for (int c = 0; c < width;)
            {
                Attributes a = Screen[r][c].Attributes;
                int end = c+1; while (end < width && Screen[r][end].Attributes == a) ++end;
                if (a != Default) runs.Add($"row {r+1} col {c+1}-{end} {AttrText(a)}");
                c = end;
            }
        Console.WriteLine("ATTRS " + runs.Count); foreach (string s in runs) Console.WriteLine(s);
        Console.WriteLine($"BELL {bells}\nREPLIES {replies}\nSTATS bytes={bytes} printed={printed} sequences={sequences}");
        Console.WriteLine($"IGNORED {ignored.Sum()} unsupported={ignored[0]} malformed={ignored[1]} canceled={ignored[2]} invalid={ignored[3]}");
    }
}
static class Program
{
    static void Main()
    {
        int[] size = Console.ReadLine()!.Split(' ').Select(int.Parse).ToArray();
        Terminal terminal = new(size[0], size[1]);
        string? line;
        while ((line = Console.ReadLine()) != null)
        {
            if (line == "%%END") { terminal.Finish(); break; }
            if (line.StartsWith("%%")) { terminal.Directive(line); continue; }
            for (int i = 0; i < line.Length; ++i)
            {
                int b = line[i];
                if (b == '^') { b = line[++i]; if (b != '^') b -= 64; }
                terminal.Feed(b);
            }
        }
    }
}
