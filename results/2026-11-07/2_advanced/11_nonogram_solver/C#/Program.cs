global using System;
global using System.Collections.Generic;
global using System.IO;
global using System.Linq;
using System.Globalization;
using System.Text;
using static LineSolver;

sealed record Given(int Row, int Column, char Value);
static class Text
{
    public static bool ValidName(string name) => name.Length is >= 1 and <= 20 && name.All(c => c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_');
    public static string Cell(int row, int column) => $"{row + 1},{column + 1}";
    public static string Numbers(IEnumerable<int> values) { int[] numbers = values.ToArray(); return numbers.Length == 0 ? "-" : string.Join(',',numbers); }
    public static List<List<string>> ReadBlocks(string path)
    {
        List<List<string>> blocks = []; List<string>? current = null;
        foreach (string line in File.ReadLines(path))
        {
            if (current is null) { if (line.Length > 0 && line[0] != '#') current = [line]; }
            else if (line == "END") { blocks.Add(current); current = null; } else current.Add(line);
        }
        return blocks;
    }
    public static List<string> Paragraphs(List<List<string>> paragraphs)
    {
        List<string> result = []; foreach (var paragraph in paragraphs) { if (result.Count > 0) result.Add(""); result.AddRange(paragraph); } return result;
    }
    public static void Write(string name, List<string> lines) => File.WriteAllText(Path.Combine("output",name),string.Concat(lines.Select(line => line + "\n")),new UTF8Encoding(false));
    public static List<(int Row, int Column)> Differences(char[][] first, char[][] second)
    {
        List<(int, int)> cells = []; for (int r = 0; r < first.Length; r++) for (int c = 0; c < first[0].Length; c++) if (first[r][c] != second[r][c]) cells.Add((r,c)); return cells;
    }
}
sealed class Puzzle
{
    public string Name;
    public int Width, Height;
    public List<string> RowLines, ColumnLines = [];
    public List<int[]> Rows = [], Columns = [];
    public List<Given> Givens = [];
    public char[][]? Answer;
    public Puzzle(List<string> block)
    {
        Name = block[0][7..]; string[] size = block[1].Split(' '); Width = int.Parse(size[1]); Height = int.Parse(size[2]); int split = block.IndexOf("COLUMNS"); RowLines = block.GetRange(3,split - 3); int position = split + 1;
        while (position < block.Count && Clues.IsLine(block[position])) ColumnLines.Add(block[position++]);
        while (position < block.Count && block[position].StartsWith("GIVEN ",StringComparison.Ordinal)) { string[] p = block[position++].Split(' '); Givens.Add(new(int.Parse(p[1]) - 1,int.Parse(p[2]) - 1,p[3][0])); }
        if (position < block.Count) Answer = block.Skip(position + 1).Select(s => s.ToCharArray()).ToArray();
    }
    public string Validate(HashSet<string> names)
    {
        if (!Text.ValidName(Name)) return "bad name"; if (names.Contains(Name)) return "duplicate name";
        if (Width is < 1 or > 30 || Height is < 1 or > 30) return "bad size";
        if (RowLines.Count != Height) return $"row count {RowLines.Count} expected {Height}"; if (ColumnLines.Count != Width) return $"column count {ColumnLines.Count} expected {Width}";
        foreach (bool row in new[] { true,false })
        {
            List<string> lines = row ? RowLines : ColumnLines; List<int[]> clues = row ? Rows : Columns; string kind = row ? "row" : "column";
            for (int i = 0; i < lines.Count; i++) { int[]? clue = Clues.Parse(lines[i]); if (clue is null) return $"bad clue {kind} {i + 1}"; if (Clues.Span(clue) > (row ? Width : Height)) return $"{kind} {i + 1} too long"; clues.Add(clue); }
        }
        int a = Rows.Sum(c => c.Sum()), b = Columns.Sum(c => c.Sum()); if (a != b) return $"total mismatch rows={a} columns={b}";
        HashSet<(int, int)> taken = [];
        for (int i = 0; i < Givens.Count; i++) { Given g = Givens[i]; if (g.Row < 0 || g.Row >= Height || g.Column < 0 || g.Column >= Width || g.Value is not ('#' or '.')) return $"bad given {i + 1}"; if (!taken.Add((g.Row,g.Column))) return $"duplicate given {i + 1}"; }
        if (Answer is not null && (Answer.Length != Height || Answer.Any(row => row.Length != Width || row.Any(c => c is not ('#' or '.' or '?'))))) return "bad answer"; return "";
    }
}
sealed class Analysis
{
    public char[][] SimpleGrid, LogicGrid;
    public Propagation Simple, Logic;
    public string SimpleResult, LogicResult, Status, Difficulty = "-";
    public Search? SearchResult;
    public List<char[][]> Solutions = [];
    public int LineSolves, Guesses, MaxDepth;
    static string Result(char[][] grid, Propagation propagation) => propagation.Conflict is not null ? "contradiction at=" + propagation.Conflict.Label : Propagation.Determined(grid) == grid.Length * grid[0].Length ? "solved" : "stuck";
    public Analysis(List<int[]> rows, List<int[]> columns, List<Given> givens)
    {
        int h = rows.Count, w = columns.Count; char[][] initial = Enumerable.Range(0,h).Select(_ => Enumerable.Repeat(Unknown,w).ToArray()).ToArray(); foreach (Given g in givens) initial[g.Row][g.Column] = g.Value;
        SimpleGrid = Propagation.Copy(initial); LogicGrid = Propagation.Copy(initial); Simple = Propagation.Run(SimpleGrid,rows,columns,false,Enumerable.Repeat(true,h).ToArray(),Enumerable.Repeat(true,w).ToArray()); Logic = Propagation.Run(LogicGrid,rows,columns,true,Enumerable.Repeat(true,h).ToArray(),Enumerable.Repeat(true,w).ToArray());
        SimpleResult = Result(SimpleGrid,Simple); LogicResult = Result(LogicGrid,Logic); LineSolves = Logic.Steps.Count;
        if (Logic.Conflict is not null) Status = "contradiction";
        else if (LogicResult == "solved") { Status = "unique"; Solutions.Add(LogicGrid); Difficulty = SimpleResult == "solved" ? "easy" : "medium"; }
        else { SearchResult = Search.Run(LogicGrid,rows,columns); Solutions = SearchResult.Solutions; Status = Solutions.Count == 0 ? "none" : Solutions.Count == 1 ? "unique" : "multiple"; if (Status == "unique") Difficulty = "hard"; LineSolves += SearchResult.LineSolves; Guesses = SearchResult.Guesses.Count; MaxDepth = SearchResult.MaxDepth; }
    }
}
static class Measures
{
    public static string ClueStatistics(List<int[]> rows, List<int[]> columns)
    {
        int maximum = rows.Concat(columns).SelectMany(c => c).DefaultIfEmpty(0).Max(); int fixedLines = rows.Count(c => c.Length == 0 || Clues.Span(c) == columns.Count) + columns.Count(c => c.Length == 0 || Clues.Span(c) == rows.Count);
        return $"row_blocks={rows.Sum(c => c.Length)} column_blocks={columns.Sum(c => c.Length)} filled={rows.Sum(c => c.Sum())} max_block={maximum} fixed_lines={fixedLines}";
    }
    public static string StepStatistics(Propagation propagation)
    {
        int productive = 0, idle = 0, best = 0; string at = "-"; foreach (LineStep step in propagation.Steps.Where(s => !s.Contradiction)) { if (step.Gain > 0) productive++; else idle++; if (step.Gain > best) { best = step.Gain; at = step.Label; } } return $"productive={productive} idle={idle} best={best} at={at}";
    }
    public static string UnknownSummary(char[][] grid, bool row)
    {
        List<string> result = []; for (int i = 0; i < (row ? grid.Length : grid[0].Length); i++) { int count = Propagation.Cells(grid,row,i).Count(c => c == Unknown); if (count > 0) result.Add($"{i + 1}:{count}"); } return string.Join(' ',result);
    }
    public static string Features(char[][] grid)
    {
        int h = grid.Length, w = grid[0].Length, filled = 0, components = 0, largest = 0, minRow = h, minColumn = w, maxRow = -1, maxColumn = -1; bool[][] seen = Enumerable.Range(0,h).Select(_ => new bool[w]).ToArray();
        for (int r = 0; r < h; r++) for (int c = 0; c < w; c++) if (grid[r][c] == Filled)
        {
            filled++; minRow = Math.Min(minRow,r); maxRow = Math.Max(maxRow,r); minColumn = Math.Min(minColumn,c); maxColumn = Math.Max(maxColumn,c); if (seen[r][c]) continue;
            components++; int size = 0; Stack<(int Row, int Column)> pending = new(); pending.Push((r,c)); seen[r][c] = true;
            while (pending.Count > 0)
            {
                var cell = pending.Pop(); size++;
                foreach (var delta in new[] { (-1,0),(1,0),(0,-1),(0,1) }) { int row = cell.Row + delta.Item1, column = cell.Column + delta.Item2; if (row >= 0 && row < h && column >= 0 && column < w && grid[row][column] == Filled && !seen[row][column]) { seen[row][column] = true; pending.Push((row,column)); } }
            }
            largest = Math.Max(largest,size);
        }
        List<string> symmetries = [];
        foreach (var symmetry in new[] { (Name: "lr",Rows: false,Columns: true),(Name: "ud",Rows: true,Columns: false),(Name: "rot180",Rows: true,Columns: true) })
        {
            bool same = true; for (int r = 0; r < h; r++) for (int c = 0; c < w; c++) if (grid[r][c] != grid[symmetry.Rows ? h - 1 - r : r][symmetry.Columns ? w - 1 - c : c]) same = false; if (same) symmetries.Add(symmetry.Name);
        }
        string box = filled == 0 ? "-" : $"{minRow + 1},{minColumn + 1},{maxRow + 1},{maxColumn + 1}"; return $"filled={filled} components={components} largest={largest} bbox={box} symmetry={(symmetries.Count == 0 ? "none" : string.Join(',',symmetries))}";
    }
    public static string Evaluate(Puzzle puzzle, Analysis analysis)
    {
        if (puzzle.Givens.Count == 0 || analysis.Status == "multiple") return ""; List<int> accepted = [];
        for (int i = 0; i < puzzle.Givens.Count; i++) { List<Given> others = puzzle.Givens.Where((_,k) => k != i).ToList(); string status = new Analysis(puzzle.Rows,puzzle.Columns,others).Status; if (status == "unique" || analysis.Status != "unique" && status == "multiple") accepted.Add(i + 1); }
        return $"givens {(analysis.Status == "unique" ? "redundant" : "blame")}={Text.Numbers(accepted)}";
    }
}
sealed class Grade
{
    public string Result = "-";
    public List<string> Lines = [];
    public Grade(Puzzle puzzle, Analysis analysis)
    {
        if (puzzle.Answer is null) return; char[][] answer = puzzle.Answer; int known = Propagation.Determined(answer); bool partial = known < puzzle.Width * puzzle.Height; List<int> rows = [], columns = [], givens = []; List<string> mismatches = [];
        foreach (bool row in new[] { true,false }) for (int i = 0; i < (row ? puzzle.Height : puzzle.Width); i++)
        {
            char[] cells = Propagation.Cells(answer,row,i); int[] clue = row ? puzzle.Rows[i] : puzzle.Columns[i]; if (HasPlacement(cells,clue)) continue;
            (row ? rows : columns).Add(i + 1); mismatches.Add($"mismatch {Propagation.Label(row,i)} expected={Clues.Text(clue,',')} " + (partial ? "cells=" + Render.StateString(cells) : "got=" + Clues.Text(Clues.Run(cells),',')));
        }
        HashSet<(int, int)> taken = []; for (int i = 0; i < puzzle.Givens.Count; i++) { Given g = puzzle.Givens[i]; taken.Add((g.Row,g.Column)); if (answer[g.Row][g.Column] != Unknown && answer[g.Row][g.Column] != g.Value) givens.Add(i + 1); }
        bool mismatch = rows.Count > 0 || columns.Count > 0 || givens.Count > 0; Result = partial ? "partial" : mismatch ? "wrong" : "correct";
        string text = $"answer result={Result} known={known} rows={Text.Numbers(rows)} columns={Text.Numbers(columns)} givens={Text.Numbers(givens)}";
        if (partial)
        {
            bool extendable = false;
            if (!mismatch) { List<Given> combined = [..puzzle.Givens]; for (int r = 0; r < puzzle.Height; r++) for (int c = 0; c < puzzle.Width; c++) if (answer[r][c] != Unknown && !taken.Contains((r,c))) combined.Add(new(r,c,answer[r][c])); string status = new Analysis(puzzle.Rows,puzzle.Columns,combined).Status; extendable = status is "unique" or "multiple"; }
            text += " extendable=" + (extendable ? "yes" : "no");
        }
        if (analysis.Status == "unique") { int differs = 0; for (int r = 0; r < puzzle.Height; r++) for (int c = 0; c < puzzle.Width; c++) if (answer[r][c] != Unknown && answer[r][c] != analysis.Solutions[0][r][c]) differs++; text += " differs=" + differs; }
        Lines.Add(text); Lines.AddRange(mismatches);
    }
}
sealed class Report
{
    public Puzzle Puzzle;
    public Analysis Analysis;
    public Grade Grade;
    public int Score => Analysis.LineSolves + 25 * Analysis.Guesses;
    public Report(Puzzle puzzle) { Puzzle = puzzle; Analysis = new(puzzle.Rows,puzzle.Columns,puzzle.Givens); Grade = new(puzzle,Analysis); }
    public List<string> Paragraph()
    {
        Puzzle p = Puzzle; Analysis a = Analysis;
        List<string> result = ["PUZZLE " + p.Name,$"size={p.Width}x{p.Height} givens={p.Givens.Count} status={a.Status} difficulty={a.Difficulty}","clues " + Measures.ClueStatistics(p.Rows,p.Columns),$"simple known={Propagation.Determined(a.SimpleGrid)} line_solves={a.Simple.Steps.Count} result={a.SimpleResult}",$"logic known={Propagation.Determined(a.LogicGrid)} line_solves={a.Logic.Steps.Count} result={a.LogicResult}","steps " + Measures.StepStatistics(a.Logic)];
        if (p.Width * p.Height <= 49) result.Add("trace " + a.Logic.Record);
        if (a.LogicResult == "stuck") result.Add($"stuck rows={Measures.UnknownSummary(a.LogicGrid,true)} columns={Measures.UnknownSummary(a.LogicGrid,false)}");
        if (a.Status == "contradiction") { LineStep step = a.Logic.Conflict!; result.Add($"conflict line={step.Label} clue={Clues.Text(step.Row ? p.Rows[step.Index] : p.Columns[step.Index],',')} cells={Render.StateString(Propagation.Cells(a.LogicGrid,step.Row,step.Index))}"); }
        if (a.SearchResult is not null)
        {
            Search s = a.SearchResult; result.Add($"search guesses={s.Guesses.Count} max_depth={s.MaxDepth} backtracks={s.Backtracks} solutions={s.Solutions.Count} line_solves={s.LineSolves}");
            foreach (Guess g in s.Guesses) result.Add($"guess {g.Number} depth={g.Depth} cell={Text.Cell(g.Row,g.Column)} value={Render.StateChar(g.Value)} solves={g.Solves} known={g.Known} result={g.Result}");
        }
        if (a.Status == "multiple") { var cells = Text.Differences(a.Solutions[0],a.Solutions[1]); result.Add($"differ count={cells.Count} cells={string.Join(' ',cells.Select(c => Text.Cell(c.Row,c.Column)))}"); }
        List<(string Name, char[][] Grid)> display = [];
        if (a.Status == "contradiction") display.Add(("partial",a.LogicGrid)); else { if (a.SimpleResult == "stuck") display.Add(("simple",a.SimpleGrid)); if (a.LogicResult == "stuck") display.Add(("logic",a.LogicGrid)); if (a.Status == "multiple") { display.Add(("first",a.Solutions[0])); display.Add(("second",a.Solutions[1])); } } result.AddRange(Render.GridDisplay(display));
        if (a.Status == "unique") { result.Add("sheet"); result.AddRange(Render.AnswerSheet(p.Rows,p.Columns,a.Solutions[0])); result.Add("picture " + Measures.Features(a.Solutions[0])); }
        string evaluation = Measures.Evaluate(p,a); if (evaluation.Length > 0) result.Add(evaluation); result.AddRange(Grade.Lines); return result;
    }
    public string Stats() => $"{Puzzle.Name},{Analysis.Status},{Analysis.Difficulty},{Puzzle.Width},{Puzzle.Height},{Puzzle.Givens.Count},{Propagation.Determined(Analysis.SimpleGrid)},{Propagation.Determined(Analysis.LogicGrid)},{Analysis.LineSolves},{Analysis.Guesses},{Analysis.MaxDepth},{Analysis.Solutions.Count},{Grade.Result}";
}
sealed class Generation
{
    public char[][] Grid;
    public List<int[]> Rows, Columns;
    public List<Given> Givens = [];
    public List<string> Log = [];
    public Analysis Initial, Final;
    Analysis Analyze(List<Given> givens) => new(Rows,Columns,givens);
    string Add((int Row, int Column) cell) { char value = Grid[cell.Row][cell.Column]; Givens.Add(new(cell.Row,cell.Column,value)); return $"cell={Text.Cell(cell.Row,cell.Column)} value={Render.StateChar(value)}"; }
    public Generation(char[][] grid)
    {
        Grid = grid; Rows = grid.Select(Clues.Run).ToList(); Columns = Enumerable.Range(0,grid[0].Length).Select(c => Clues.Run(Propagation.Cells(grid,false,c))).ToList(); Initial = Analyze(Givens); Analysis current = Initial;
        while (current.Status == "multiple") { string text = Add(Text.Differences(current.Solutions[0],current.Solutions[1])[0]); current = Analyze(Givens); Log.Add($"# hint {Givens.Count} {text} status={current.Status}"); }
        foreach (Given given in Givens.ToArray()) { List<Given> others = Givens.Where(g => g != given).ToList(); if (Analyze(others).Status == "unique") { Givens = others; Log.Add("# drop cell=" + Text.Cell(given.Row,given.Column)); } }
        Final = Analyze(Givens); int count = 0;
        while (Final.Difficulty == "hard") { string text = Add(Search.GuessCell(Final.LogicGrid)); Final = Analyze(Givens); Log.Add($"# logic hint {++count} {text} difficulty={Final.Difficulty}"); }
    }
    public List<string> Paragraph(string name, List<Report> reports)
    {
        string duplicate = reports.FirstOrDefault(r => Clues.Equal(r.Puzzle.Rows,Rows) && Clues.Equal(r.Puzzle.Columns,Columns))?.Puzzle.Name ?? "-";
        List<string> result = [$"# picture {name} size={Columns.Count}x{Rows.Count} {Measures.Features(Grid)}",$"# clues {Measures.ClueStatistics(Rows,Columns)} duplicate_of={duplicate}",$"# plain status={Initial.Status} difficulty={Initial.Difficulty} line_solves={Initial.LineSolves} guesses={Initial.Guesses}"]; result.AddRange(Log); result.Add($"# final status={Final.Status} difficulty={Final.Difficulty} hints={Givens.Count} line_solves={Final.LineSolves} guesses={Final.Guesses}"); result.AddRange(["PUZZLE " + name,$"SIZE {Columns.Count} {Rows.Count}","ROWS"]);
        result.AddRange(Rows.Select(c => Clues.Text(c))); result.Add("COLUMNS"); result.AddRange(Columns.Select(c => Clues.Text(c))); foreach (Given given in Givens.OrderBy(g => g.Row).ThenBy(g => g.Column)) result.Add($"GIVEN {given.Row + 1} {given.Column + 1} {Render.StateChar(given.Value)}"); result.Add("END"); return result;
    }
}
static class Program
{
    static List<Report> ProcessPuzzles(List<Puzzle> puzzles)
    {
        HashSet<string> names = []; List<Report> reports = []; List<List<string>> paragraphs = []; List<string> stats = ["puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer"];
        foreach (Puzzle puzzle in puzzles)
        {
            string error = puzzle.Validate(names); names.Add(puzzle.Name);
            if (error.Length > 0) { paragraphs.Add(["PUZZLE " + puzzle.Name,"error " + error]); stats.Add(puzzle.Name + ",invalid" + string.Concat(Enumerable.Repeat(",-",11))); }
            else { Report report = new(puzzle); reports.Add(report); paragraphs.Add(report.Paragraph()); stats.Add(report.Stats()); }
        }
        int Difficulty(string difficulty) => difficulty == "easy" ? 0 : difficulty == "medium" ? 1 : 2;
        List<Report> ranked = reports.Where(r => r.Analysis.Status == "unique").OrderBy(r => Difficulty(r.Analysis.Difficulty)).ThenBy(r => r.Score).ThenBy(r => r.Puzzle.Name,StringComparer.Ordinal).ToList(); List<string> ranking = ["RANKING"];
        for (int i = 0; i < ranked.Count; i++) { Report r = ranked[i]; ranking.Add($"rank {i + 1} {r.Puzzle.Name} {r.Analysis.Difficulty} score={r.Score} size={r.Puzzle.Width}x{r.Puzzle.Height}"); } paragraphs.Add(ranking);
        int CountStatus(string status) => reports.Count(r => r.Analysis.Status == status); int CountDifficulty(string difficulty) => reports.Count(r => r.Analysis.Difficulty == difficulty);
        paragraphs.Add([$"SUMMARY puzzles={puzzles.Count} invalid={puzzles.Count - reports.Count} contradiction={CountStatus("contradiction")} none={CountStatus("none")} unique={CountStatus("unique")} multiple={CountStatus("multiple")} easy={CountDifficulty("easy")} medium={CountDifficulty("medium")} hard={CountDifficulty("hard")} line_solves={reports.Sum(r => r.Analysis.LineSolves)} guesses={reports.Sum(r => r.Analysis.Guesses)}"]); Text.Write("solutions.txt",Text.Paragraphs(paragraphs)); Text.Write("stats.csv",stats); return reports;
    }
    static void ProcessPictures(List<List<string>> pictures, List<Report> reports)
    {
        HashSet<string> names = []; List<List<string>> paragraphs = []; int valid = 0, unique = 0, logic = 0, hinted = 0, hints = 0;
        foreach (var block in pictures)
        {
            string name = block[0][8..], error = ""; char[][] grid = block.Skip(1).Select(row => row.ToCharArray()).ToArray();
            if (!Text.ValidName(name)) error = "bad name"; else if (names.Contains(name)) error = "duplicate name"; else if (grid.Length is < 1 or > 30) error = "bad height";
            else for (int i = 0; i < grid.Length; i++) if (grid[i].Length is < 1 or > 30 || grid[i].Length != grid[0].Length || grid[i].Any(c => c is not ('#' or '.'))) { error = $"bad row {i + 1}"; break; }
            names.Add(name); if (error.Length > 0) { paragraphs.Add([$"# picture {name} error {error}"]); continue; }
            Generation generation = new(grid); valid++; if (generation.Initial.Status == "unique") unique++; if (generation.Initial.Difficulty is "easy" or "medium") logic++; if (generation.Givens.Count > 0) hinted++; hints += generation.Givens.Count; paragraphs.Add(generation.Paragraph(name,reports));
        }
        paragraphs.Add([$"# SUMMARY pictures={pictures.Count} invalid={pictures.Count - valid} unique={unique} line_logic={logic} hinted={hinted} hints={hints}"]); Text.Write("generated.txt",Text.Paragraphs(paragraphs));
    }
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture; Directory.CreateDirectory("output"); List<Report> reports = ProcessPuzzles(Text.ReadBlocks("input/puzzles.txt").Select(block => new Puzzle(block)).ToList()); ProcessPictures(Text.ReadBlocks("input/pictures.txt"),reports);
    }
}
