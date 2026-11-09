using System.Text.RegularExpressions;

var input = new List<string>();
while (Console.ReadLine() is { } inputLine)
{
    input.Add(inputLine);
}

var workspace = new Workspace();
var position = 1;
var commandCount = int.Parse(input[0]);
for (var command = 0; command < commandCount; command++)
{
    var words = input[position].Split(' ');
    position++;
    var data = new List<string>();
    if (Workspace.DataCommands.Contains(words[0]))
    {
        var count = int.Parse(words[2]);
        data = input.GetRange(position, count);
        position += count;
    }
    workspace.Execute(words, data);
}
Console.Out.Write(string.Join("\n", workspace.Output) + "\n");

class CommandException(string message) : Exception(message);

static class Ranges
{
    public static string R(int start, int count) => count switch
    {
        >= 2 => $"{start + 1},{start + count}",
        1 => $"{start + 1}",
        _ => $"{start}",
    };

    public static string U(int start, int count) => count switch
    {
        >= 2 => $"{start + 1},{count}",
        1 => $"{start + 1}",
        _ => $"{start},0",
    };

    public static string M(int start, int count) => $"{start + 1},{count}";
}

record ChangeBlock(int P, int Q, int X, int Y)
{
    public char Letter => X >= 1 && Y >= 1 ? 'c' : Y == 0 ? 'd' : 'a';
}

readonly record struct Step(int OldIndex, int NewIndex, ChangeBlock? Block);

static class LineMatching
{
    public static List<(int I, int J)> MatchedPairs(
        IReadOnlyList<string> first, IReadOnlyList<string> second)
    {
        int rows = first.Count, columns = second.Count;
        var table = new int[rows + 1, columns + 1];
        for (var i = 1; i <= rows; i++)
        {
            for (var j = 1; j <= columns; j++)
            {
                table[i, j] = first[i - 1] == second[j - 1]
                    ? table[i - 1, j - 1] + 1
                    : Math.Max(table[i - 1, j], table[i, j - 1]);
            }
        }
        var pairs = new List<(int I, int J)> { (rows + 1, columns + 1) };
        int row = rows, column = columns;
        while (row >= 1 && column >= 1)
        {
            if (first[row - 1] == second[column - 1])
            {
                pairs.Add((row, column));
                row--;
                column--;
            }
            else if (table[row - 1, column] >= table[row, column - 1])
            {
                row--;
            }
            else
            {
                column--;
            }
        }
        pairs.Add((0, 0));
        pairs.Reverse();
        return pairs;
    }

    public static List<ChangeBlock> ChangeBlocks(
        IReadOnlyList<string> first, IReadOnlyList<string> second)
    {
        var pairs = MatchedPairs(first, second);
        var blocks = new List<ChangeBlock>();
        for (var index = 0; index + 1 < pairs.Count; index++)
        {
            var (i, j) = pairs[index];
            var (nextI, nextJ) = pairs[index + 1];
            if (nextI - i > 1 || nextJ - j > 1)
            {
                blocks.Add(new ChangeBlock(i, j, nextI - i - 1, nextJ - j - 1));
            }
        }
        return blocks;
    }

    public static List<Step> Walk(List<ChangeBlock> blocks, int oldStart, int newStart, int oldEnd)
    {
        var steps = new List<Step>();
        var (oldIndex, newIndex) = (oldStart, newStart);
        foreach (var block in blocks)
        {
            while (oldIndex < block.P)
            {
                steps.Add(new Step(oldIndex, newIndex, null));
                oldIndex++;
                newIndex++;
            }
            steps.Add(new Step(oldIndex, newIndex, block));
            (oldIndex, newIndex) = (block.P + block.X, block.Q + block.Y);
        }
        while (oldIndex < oldEnd)
        {
            steps.Add(new Step(oldIndex, newIndex, null));
            oldIndex++;
            newIndex++;
        }
        return steps;
    }
}

class Hunk
{
    public Hunk(List<ChangeBlock> blocks, int context, int oldTotal)
    {
        var (first, last) = (blocks[0], blocks[^1]);
        var before = Math.Min(context, first.P);
        var after = Math.Min(context, oldTotal - last.P - last.X);
        Blocks = blocks;
        OldStart = first.P - before;
        OldCount = last.P + last.X + after - OldStart;
        NewStart = first.Q - before;
        NewCount = last.Q + last.Y + after - NewStart;
    }

    public List<ChangeBlock> Blocks { get; }
    public int OldStart { get; }
    public int OldCount { get; }
    public int NewStart { get; }
    public int NewCount { get; }

    public List<Step> Steps() => LineMatching.Walk(Blocks, OldStart, NewStart, OldStart + OldCount);
}

class LineDiff(List<string> oldLines, List<string> newLines, IReadOnlyCollection<string> options)
{
    public List<ChangeBlock> Blocks { get; } = LineMatching.ChangeBlocks(
        oldLines.Select(line => ComparisonKey(line, options)).ToList(),
        newLines.Select(line => ComparisonKey(line, options)).ToList());

    private static string ComparisonKey(string line, IReadOnlyCollection<string> options)
    {
        if (options.Contains("ICASE"))
        {
            line = line.ToLowerInvariant();
        }
        if (options.Contains("IWHITE"))
        {
            line = line.Replace(" ", "");
        }
        if (options.Contains("ISPACE"))
        {
            line = Regex.Replace(line, " {2,}", " ");
        }
        return line;
    }

    private static string Clip(string text, int width) => text.Length > width ? text[..width] : text;

    private static string SideRow(string left, string symbol, string right, int width) =>
        (Clip(left, width).PadRight(width) + " " + symbol + " " + Clip(right, width)).TrimEnd(' ');

    private List<string> Deleted(ChangeBlock block) => oldLines.GetRange(block.P, block.X);

    private List<string> Inserted(ChangeBlock block) => newLines.GetRange(block.Q, block.Y);

    private List<Hunk> Hunks(int context)
    {
        var groups = new List<List<ChangeBlock>>();
        foreach (var block in Blocks)
        {
            if (groups.Count > 0)
            {
                var previous = groups[^1][^1];
                if (block.P - (previous.P + previous.X) <= 2 * context)
                {
                    groups[^1].Add(block);
                    continue;
                }
            }
            groups.Add([block]);
        }
        return groups.Select(group => new Hunk(group, context, oldLines.Count)).ToList();
    }

    public List<string> Normal()
    {
        var lines = new List<string>();
        foreach (var block in Blocks)
        {
            var letter = block.Letter;
            lines.Add(Ranges.R(block.P, block.X) + letter + Ranges.R(block.Q, block.Y));
            lines.AddRange(Deleted(block).Select(line => "< " + line));
            if (letter == 'c')
            {
                lines.Add("---");
            }
            lines.AddRange(Inserted(block).Select(line => "> " + line));
        }
        return lines;
    }

    public List<string> Ed()
    {
        var lines = new List<string>();
        foreach (var block in Enumerable.Reverse(Blocks))
        {
            var letter = block.Letter;
            lines.Add(Ranges.R(block.P, block.X) + letter);
            if (letter != 'd')
            {
                lines.AddRange(Inserted(block));
                lines.Add(".");
            }
        }
        return lines;
    }

    public List<string> Rcs()
    {
        var lines = new List<string>();
        foreach (var block in Blocks)
        {
            if (block.X >= 1)
            {
                lines.Add($"d{block.P + 1} {block.X}");
            }
            if (block.Y >= 1)
            {
                lines.Add($"a{block.P + block.X} {block.Y}");
                lines.AddRange(Inserted(block));
            }
        }
        return lines;
    }

    public List<string> IfDef(string macro)
    {
        var lines = new List<string>();
        foreach (var (oldIndex, _, block) in LineMatching.Walk(Blocks, 0, 0, oldLines.Count))
        {
            if (block is null)
            {
                lines.Add(oldLines[oldIndex]);
            }
            else if (block.X >= 1 && block.Y >= 1)
            {
                lines.Add($"#ifndef {macro}");
                lines.AddRange(Deleted(block));
                lines.Add($"#else /* {macro} */");
                lines.AddRange(Inserted(block));
                lines.Add($"#endif /* {macro} */");
            }
            else if (block.Y == 0)
            {
                lines.Add($"#ifndef {macro}");
                lines.AddRange(Deleted(block));
                lines.Add($"#endif /* ! {macro} */");
            }
            else
            {
                lines.Add($"#ifdef {macro}");
                lines.AddRange(Inserted(block));
                lines.Add($"#endif /* {macro} */");
            }
        }
        return lines;
    }

    public List<string> Unified(int context, string oldName, string newName)
    {
        var lines = new List<string> { $"--- {oldName}", $"+++ {newName}" };
        foreach (var hunk in Hunks(context))
        {
            var oldRange = Ranges.U(hunk.OldStart, hunk.OldCount);
            var newRange = Ranges.U(hunk.NewStart, hunk.NewCount);
            lines.Add($"@@ -{oldRange} +{newRange} @@");
            foreach (var (oldIndex, _, block) in hunk.Steps())
            {
                if (block is null)
                {
                    lines.Add(" " + oldLines[oldIndex]);
                }
                else
                {
                    lines.AddRange(Deleted(block).Select(line => "-" + line));
                    lines.AddRange(Inserted(block).Select(line => "+" + line));
                }
            }
        }
        return lines;
    }

    public List<string> Context(int context, string oldName, string newName)
    {
        var lines = new List<string> { $"*** {oldName}", $"--- {newName}" };
        foreach (var hunk in Hunks(context))
        {
            lines.Add(new string('*', 15));
            lines.Add($"*** {Ranges.R(hunk.OldStart, hunk.OldCount)} ****");
            if (hunk.Blocks.Any(block => block.X >= 1))
            {
                foreach (var (oldIndex, _, block) in hunk.Steps())
                {
                    if (block is null)
                    {
                        lines.Add("  " + oldLines[oldIndex]);
                    }
                    else
                    {
                        var marker = block.Y >= 1 ? "! " : "- ";
                        lines.AddRange(Deleted(block).Select(line => marker + line));
                    }
                }
            }
            lines.Add($"--- {Ranges.R(hunk.NewStart, hunk.NewCount)} ----");
            if (hunk.Blocks.Any(block => block.Y >= 1))
            {
                foreach (var (_, newIndex, block) in hunk.Steps())
                {
                    if (block is null)
                    {
                        lines.Add("  " + newLines[newIndex]);
                    }
                    else
                    {
                        var marker = block.X >= 1 ? "! " : "+ ";
                        lines.AddRange(Inserted(block).Select(line => marker + line));
                    }
                }
            }
        }
        return lines;
    }

    public List<string> SideBySide(int width)
    {
        var lines = new List<string>();
        foreach (var (oldIndex, newIndex, block) in LineMatching.Walk(Blocks, 0, 0, oldLines.Count))
        {
            if (block is null)
            {
                lines.Add(SideRow(oldLines[oldIndex], " ", newLines[newIndex], width));
                continue;
            }
            for (var row = 0; row < Math.Max(block.X, block.Y); row++)
            {
                var (left, symbol, right) = (row < block.X, row < block.Y) switch
                {
                    (true, true) => (oldLines[block.P + row], "|", newLines[block.Q + row]),
                    (true, false) => (oldLines[block.P + row], "<", ""),
                    _ => ("", ">", newLines[block.Q + row]),
                };
                lines.Add(SideRow(left, symbol, right, width));
            }
        }
        return lines;
    }
}

class TokenTotals
{
    public int Deleted { get; set; }
    public int Inserted { get; set; }
    public int Common { get; set; }
}

static class TokenDiff
{
    public static string[] Split(string line, bool byWord) =>
        byWord
            ? line.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            : line.Select(character => character.ToString()).ToArray();

    public static string Deletion(IEnumerable<string> tokens, string separator) =>
        "[-" + string.Join(separator, tokens) + "-]";

    public static string Insertion(IEnumerable<string> tokens, string separator) =>
        "{+" + string.Join(separator, tokens) + "+}";

    public static string Compare(
        string[] oldTokens, string[] newTokens, string separator, TokenTotals totals)
    {
        var parts = new List<string>();
        var blocks = LineMatching.ChangeBlocks(oldTokens, newTokens);
        foreach (var (oldIndex, _, block) in LineMatching.Walk(blocks, 0, 0, oldTokens.Length))
        {
            if (block is null)
            {
                parts.Add(oldTokens[oldIndex]);
                totals.Common++;
                continue;
            }
            if (block.X >= 1)
            {
                parts.Add(Deletion(oldTokens[block.P..(block.P + block.X)], separator));
            }
            if (block.Y >= 1)
            {
                parts.Add(Insertion(newTokens[block.Q..(block.Q + block.Y)], separator));
            }
            totals.Deleted += block.X;
            totals.Inserted += block.Y;
        }
        return string.Join(separator, parts);
    }
}

record HunkMatch(int Fuzz, int Delta, int Position, List<string> Lines)
{
    public string Report(int number)
    {
        var text = $"Hunk #{number} succeeded at {Position + 1}";
        if (Fuzz >= 1)
        {
            text += $" with fuzz {Fuzz}";
        }
        if (Delta is 1 or -1)
        {
            text += $" (offset {Delta} line)";
        }
        else if (Delta != 0)
        {
            text += $" (offset {Delta} lines)";
        }
        return text;
    }
}

record PatchHunk(int LineNumber, int OldStart, int OldCount, int NewStart, int NewCount)
{
    private static readonly int[] Offsets = [0, 1, -1, 2, -2, 3, -3];

    public List<(char Kind, string Text)> Body { get; } = [];

    private int LeadingContext => Body.TakeWhile(line => line.Kind == ' ').Count();

    private int TrailingContext => Enumerable.Reverse(Body).TakeWhile(line => line.Kind == ' ').Count();

    private List<string> Texts(char changeKind) =>
        Body.Where(line => line.Kind == ' ' || line.Kind == changeKind).Select(line => line.Text).ToList();

    public (List<string> Old, List<string> New) Sequences(bool reverse) =>
        reverse ? (Texts('+'), Texts('-')) : (Texts('-'), Texts('+'));

    public int Start(bool reverse) => reverse ? NewStart : OldStart;

    public HunkMatch? Search(List<string> lines, int adjustment, bool reverse, int maxFuzz)
    {
        var (oldLines, newLines) = Sequences(reverse);
        var start = Start(reverse);
        var expected = oldLines.Count > 0 ? start - 1 + adjustment : start + adjustment;
        var (leading, trailing) = (LeadingContext, TrailingContext);
        for (var fuzz = 0; fuzz <= maxFuzz; fuzz++)
        {
            var head = Math.Min(fuzz, leading);
            var tail = Math.Min(fuzz, trailing);
            var oldPart = oldLines[head..(oldLines.Count - tail)];
            var newPart = newLines[head..(newLines.Count - tail)];
            foreach (var delta in Offsets)
            {
                var position = expected + head + delta;
                var end = position + oldPart.Count;
                if (position < 0 || end > lines.Count || !lines[position..end].SequenceEqual(oldPart))
                {
                    continue;
                }
                List<string> result = [.. lines[..position], .. newPart, .. lines[end..]];
                return new HunkMatch(fuzz, delta, position, result);
            }
        }
        return null;
    }
}

static class PatchParser
{
    public static readonly Regex NumberPair = new("^([0-9]{1,4})(?:,([0-9]{1,4}))?$");

    private static (int Start, int Count)? ParseRange(string text, char sign)
    {
        if (!text.StartsWith(sign))
        {
            return null;
        }
        var match = NumberPair.Match(text[1..]);
        if (!match.Success)
        {
            return null;
        }
        var start = int.Parse(match.Groups[1].Value);
        var count = match.Groups[2].Success ? int.Parse(match.Groups[2].Value) : 1;
        if (start == 0 && count != 0)
        {
            return null;
        }
        return (start, count);
    }

    private static PatchHunk ParseHunkHeader(string line, int lineNumber)
    {
        var parts = line.Split(' ');
        (int Start, int Count)? oldRange = null, newRange = null;
        if (parts.Length == 4 && parts[0] == "@@" && parts[3] == "@@")
        {
            oldRange = ParseRange(parts[1], '-');
            newRange = ParseRange(parts[2], '+');
        }
        if (oldRange is not { } oldValue || newRange is not { } newValue)
        {
            throw new CommandException($"PATCH ERROR line {lineNumber}: bad hunk header");
        }
        return new PatchHunk(
            lineNumber, oldValue.Start, oldValue.Count, newValue.Start, newValue.Count);
    }

    public static List<PatchHunk> Parse(List<string> patchLines)
    {
        var index = patchLines.FindIndex(line => line.StartsWith("@@", StringComparison.Ordinal));
        if (index < 0)
        {
            throw new CommandException("PATCH ERROR no hunks");
        }
        var hunks = new List<PatchHunk>();
        while (index < patchLines.Count)
        {
            var hunk = ParseHunkHeader(patchLines[index], index + 1);
            index++;
            int oldSeen = 0, newSeen = 0;
            while (oldSeen < hunk.OldCount || newSeen < hunk.NewCount)
            {
                if (index == patchLines.Count)
                {
                    throw new CommandException($"PATCH ERROR line {hunk.LineNumber}: truncated hunk");
                }
                var line = patchLines[index];
                var kind = line[0];
                var inOld = kind is ' ' or '-';
                var inNew = kind is ' ' or '+';
                if (line.Length < 2
                    || !(inOld || inNew)
                    || (inOld && oldSeen == hunk.OldCount)
                    || (inNew && newSeen == hunk.NewCount))
                {
                    throw new CommandException($"PATCH ERROR line {index + 1}: bad hunk line");
                }
                hunk.Body.Add((kind, line[1..]));
                if (inOld)
                {
                    oldSeen++;
                }
                if (inNew)
                {
                    newSeen++;
                }
                index++;
            }
            if (hunk.Body.All(line => line.Kind == ' '))
            {
                throw new CommandException($"PATCH ERROR line {hunk.LineNumber}: no changes");
            }
            hunks.Add(hunk);
        }
        return hunks;
    }
}

static class EditScript
{
    private static (char Instruction, int First, int Last)? ParseCommand(string line)
    {
        var instruction = line[^1];
        var match = PatchParser.NumberPair.Match(line[..^1]);
        if (instruction is not ('a' or 'c' or 'd') || !match.Success)
        {
            return null;
        }
        if (instruction == 'a' && match.Groups[2].Success)
        {
            return null;
        }
        var first = int.Parse(match.Groups[1].Value);
        var last = match.Groups[2].Success ? int.Parse(match.Groups[2].Value) : first;
        return (instruction, first, last);
    }

    public static (List<string> Lines, int Executed) Run(List<string> original, List<string> script)
    {
        var lines = new List<string>(original);
        var executed = 0;
        var index = 0;
        while (index < script.Count)
        {
            var lineNumber = index + 1;
            if (ParseCommand(script[index]) is not { } command)
            {
                throw new CommandException($"EDIT ERROR line {lineNumber}: bad command");
            }
            var (instruction, first, last) = command;
            var valid = instruction == 'a'
                ? first <= lines.Count
                : 1 <= first && first <= last && last <= lines.Count;
            if (!valid)
            {
                throw new CommandException($"EDIT ERROR line {lineNumber}: bad range");
            }
            index++;
            var text = new List<string>();
            if (instruction is 'a' or 'c')
            {
                var end = script.FindIndex(index, line => line == ".");
                if (end < 0)
                {
                    throw new CommandException($"EDIT ERROR line {lineNumber}: missing terminator");
                }
                text = script[index..end];
                index = end + 1;
            }
            if (instruction == 'a')
            {
                lines.InsertRange(first, text);
            }
            else
            {
                lines.RemoveRange(first - 1, last - first + 1);
                lines.InsertRange(first - 1, text);
            }
            executed++;
        }
        return (lines, executed);
    }
}

enum ChunkKind
{
    Stable,
    A,
    B,
    Both,
    Conflict,
}

record Chunk(
    ChunkKind Kind,
    int BaseStart,
    int OursStart,
    int TheirsStart,
    List<string> Base,
    List<string> Ours,
    List<string> Theirs)
{
    public string KindName => Kind.ToString().ToLowerInvariant();

    public string Location =>
        $"base {Ranges.M(BaseStart, Base.Count)} a {Ranges.M(OursStart, Ours.Count)}"
        + $" b {Ranges.M(TheirsStart, Theirs.Count)}";
}

static class ThreeWay
{
    public const string Separator = "=======";

    private static ChunkKind KindOf(List<string> baseLines, List<string> ours, List<string> theirs)
    {
        if (ours.SequenceEqual(baseLines))
        {
            return ChunkKind.B;
        }
        if (theirs.SequenceEqual(baseLines))
        {
            return ChunkKind.A;
        }
        return ours.SequenceEqual(theirs) ? ChunkKind.Both : ChunkKind.Conflict;
    }

    private static int[] MatchTable(List<string> first, List<string> second)
    {
        var matches = new int[first.Count + 2];
        var pairs = LineMatching.MatchedPairs(first, second);
        foreach (var (i, j) in pairs[1..^1])
        {
            matches[i] = j;
        }
        return matches;
    }

    public static List<Chunk> Chunks(List<string> baseLines, List<string> ours, List<string> theirs)
    {
        var oursMatch = MatchTable(baseLines, ours);
        var theirsMatch = MatchTable(baseLines, theirs);
        var chunks = new List<Chunk>();
        int x = 0, y = 0, z = 0;
        while (x < baseLines.Count || y < ours.Count || z < theirs.Count)
        {
            if (x < baseLines.Count && oursMatch[x + 1] == y + 1 && theirsMatch[x + 1] == z + 1)
            {
                chunks.Add(new Chunk(
                    ChunkKind.Stable, x, y, z, [baseLines[x]], [ours[y]], [theirs[z]]));
                x++;
                y++;
                z++;
                continue;
            }
            var anchor = x + 1;
            while (anchor <= baseLines.Count && (oursMatch[anchor] == 0 || theirsMatch[anchor] == 0))
            {
                anchor++;
            }
            var (nextX, nextY, nextZ) = anchor <= baseLines.Count
                ? (anchor - 1, oursMatch[anchor] - 1, theirsMatch[anchor] - 1)
                : (baseLines.Count, ours.Count, theirs.Count);
            var (basePart, oursPart, theirsPart) = (baseLines[x..nextX], ours[y..nextY], theirs[z..nextZ]);
            var kind = KindOf(basePart, oursPart, theirsPart);
            chunks.Add(new Chunk(kind, x, y, z, basePart, oursPart, theirsPart));
            (x, y, z) = (nextX, nextY, nextZ);
        }
        return chunks;
    }

    public static string KindCounts(List<Chunk> chunks)
    {
        int CountOf(ChunkKind kind) => chunks.Count(chunk => chunk.Kind == kind);
        return $"a={CountOf(ChunkKind.A)} b={CountOf(ChunkKind.B)} both={CountOf(ChunkKind.Both)}"
            + $" conflicts={CountOf(ChunkKind.Conflict)}";
    }

    private static int CommonPrefixLength(List<string> first, List<string> second)
    {
        var length = 0;
        while (length < first.Count && length < second.Count && first[length] == second[length])
        {
            length++;
        }
        return length;
    }

    private static int CommonSuffixLength(List<string> first, List<string> second, int limit)
    {
        var length = 0;
        while (length < limit && first[^(length + 1)] == second[^(length + 1)])
        {
            length++;
        }
        return length;
    }

    public static List<string> ConflictLines(
        Chunk chunk, string mode, string baseName, string oursName, string theirsName)
    {
        var (ours, theirs) = (chunk.Ours, chunk.Theirs);
        switch (mode)
        {
            case "OURS":
                return ours;
            case "THEIRS":
                return theirs;
            case "DIFF3":
                return
                [
                    $"<<<<<<< {oursName}", .. ours, $"||||||| {baseName}", .. chunk.Base,
                    Separator, .. theirs, $">>>>>>> {theirsName}",
                ];
        }
        var head = CommonPrefixLength(ours, theirs);
        var tail = CommonSuffixLength(ours, theirs, Math.Min(ours.Count, theirs.Count) - head);
        var oursMiddle = ours[head..(ours.Count - tail)];
        var theirsMiddle = theirs[head..(theirs.Count - tail)];
        List<string> middle = mode == "UNION"
            ? [.. oursMiddle, .. theirsMiddle]
            : [$"<<<<<<< {oursName}", .. oursMiddle, Separator, .. theirsMiddle, $">>>>>>> {theirsName}"];
        return [.. ours[..head], .. middle, .. ours[(ours.Count - tail)..]];
    }
}

enum Marker
{
    Start,
    Base,
    Separator,
    End,
}

record ConflictRegion(int Start, int End, List<string> Ours, List<string>? Base, List<string> Theirs)
{
    public List<string> Part(string side) => side switch
    {
        "OURS" => Ours,
        "THEIRS" => Theirs,
        "BASE" => Base ?? [],
        _ => [.. Ours, .. Theirs],
    };
}

static class ConflictScanner
{
    private static Marker? MarkerKind(string line)
    {
        if (line == ThreeWay.Separator)
        {
            return Marker.Separator;
        }
        if (line.Length < 7 || (line.Length > 7 && line[7] != ' '))
        {
            return null;
        }
        return line[..7] switch
        {
            "<<<<<<<" => Marker.Start,
            "|||||||" => Marker.Base,
            ">>>>>>>" => Marker.End,
            _ => null,
        };
    }

    private static Marker? MarkerAt(List<string> lines, int index) =>
        index < lines.Count ? MarkerKind(lines[index]) : null;

    private static int NextMarker(List<string> lines, int index)
    {
        index++;
        while (index < lines.Count && MarkerKind(lines[index]) is null)
        {
            index++;
        }
        return index;
    }

    private static ConflictRegion? RegionAt(List<string> lines, int start)
    {
        if (MarkerAt(lines, start) != Marker.Start)
        {
            return null;
        }
        var middle = NextMarker(lines, start);
        int? baseMarker = null;
        if (MarkerAt(lines, middle) == Marker.Base)
        {
            baseMarker = middle;
            middle = NextMarker(lines, middle);
        }
        if (MarkerAt(lines, middle) != Marker.Separator)
        {
            return null;
        }
        var end = NextMarker(lines, middle);
        if (MarkerAt(lines, end) != Marker.End)
        {
            return null;
        }
        var ours = lines[(start + 1)..(baseMarker ?? middle)];
        var baseLines = baseMarker is { } marker ? lines[(marker + 1)..middle] : null;
        return new ConflictRegion(start + 1, end + 1, ours, baseLines, lines[(middle + 1)..end]);
    }

    public static List<ConflictRegion> Regions(List<string> lines)
    {
        var regions = new List<ConflictRegion>();
        var index = 0;
        while (index < lines.Count)
        {
            if (RegionAt(lines, index) is { } region)
            {
                regions.Add(region);
                index = region.End;
            }
            else
            {
                index++;
            }
        }
        return regions;
    }
}

class Workspace
{
    public static readonly string[] DataCommands = ["FILE", "PATCH", "EDIT"];
    private static readonly string[] FormatsWithArgument = ["IFDEF", "UNIFIED", "CONTEXT", "SIDE"];
    private const int GraphWidth = 20;

    private readonly SortedDictionary<string, List<string>> _files = new(StringComparer.Ordinal);
    private readonly Dictionary<string, List<List<string>?>> _history = new();

    public List<string> Output { get; } = [];

    private void Require(params string[] names)
    {
        foreach (var name in names)
        {
            if (!_files.ContainsKey(name))
            {
                throw new CommandException($"ERROR no such file {name}");
            }
        }
    }

    private void Save(string name, List<string> lines)
    {
        if (!_history.TryGetValue(name, out var states))
        {
            states = [];
            _history[name] = states;
        }
        states.Add(_files.GetValueOrDefault(name));
        _files[name] = [.. lines];
    }

    private void LoadFile(string[] arguments, List<string> data)
    {
        var name = arguments[0];
        Save(name, data);
        Output.Add($"FILE {name} lines={data.Count}");
    }

    private void Copy(string[] arguments)
    {
        var (source, target) = (arguments[0], arguments[1]);
        Require(source);
        var lines = _files[source];
        Save(target, lines);
        Output.Add($"COPY {source} {target} lines={lines.Count}");
    }

    private void PrintFile(string[] arguments)
    {
        var name = arguments[0];
        Require(name);
        var lines = _files[name];
        Output.Add($"PRINT {name} lines={lines.Count}");
        for (var index = 0; index < lines.Count; index++)
        {
            Output.Add($"{index + 1,3}| {lines[index]}");
        }
    }

    private void ListFiles()
    {
        Output.Add($"FILES count={_files.Count}");
        foreach (var (name, lines) in _files)
        {
            Output.Add($"{name} lines={lines.Count} undo={_history[name].Count}");
        }
    }

    private void Undo(string[] arguments)
    {
        var name = arguments[0];
        if (!_history.TryGetValue(name, out var states) || states.Count == 0)
        {
            throw new CommandException($"ERROR nothing to undo {name}");
        }
        var state = states[^1];
        states.RemoveAt(states.Count - 1);
        if (state is null)
        {
            _files.Remove(name);
            Output.Add($"UNDO {name} removed");
        }
        else
        {
            _files[name] = state;
            Output.Add($"UNDO {name} lines={state.Count}");
        }
    }

    private void Diff(string[] arguments)
    {
        var (oldName, newName, form) = (arguments[0], arguments[1], arguments[2]);
        Require(oldName, newName);
        var hasParameter = FormatsWithArgument.Contains(form);
        var parameter = hasParameter ? arguments[3] : "";
        var options = arguments[(hasParameter ? 4 : 3)..];
        var diff = new LineDiff(_files[oldName], _files[newName], options);
        if (diff.Blocks.Count == 0)
        {
            Output.Add($"Files {oldName} and {newName} are identical");
            return;
        }
        List<string> lines = form switch
        {
            "BRIEF" => [$"Files {oldName} and {newName} differ"],
            "NORMAL" => diff.Normal(),
            "ED" => diff.Ed(),
            "RCS" => diff.Rcs(),
            "IFDEF" => diff.IfDef(parameter),
            "UNIFIED" => diff.Unified(int.Parse(parameter), oldName, newName),
            "CONTEXT" => diff.Context(int.Parse(parameter), oldName, newName),
            _ => diff.SideBySide(int.Parse(parameter)),
        };
        Output.AddRange(lines);
    }

    private void TokenDiffCommand(string[] arguments, bool byWord)
    {
        var (oldName, newName) = (arguments[0], arguments[1]);
        Require(oldName, newName);
        var (oldLines, newLines) = (_files[oldName], _files[newName]);
        var diff = new LineDiff(oldLines, newLines, []);
        if (diff.Blocks.Count == 0)
        {
            Output.Add($"Files {oldName} and {newName} are identical");
            return;
        }
        var separator = byWord ? " " : "";
        var totals = new TokenTotals();
        foreach (var block in diff.Blocks)
        {
            for (var row = 0; row < Math.Max(block.X, block.Y); row++)
            {
                var (oldNumber, newNumber) = (block.P + row + 1, block.Q + row + 1);
                if (row < block.X && row < block.Y)
                {
                    var oldTokens = TokenDiff.Split(oldLines[oldNumber - 1], byWord);
                    var newTokens = TokenDiff.Split(newLines[newNumber - 1], byWord);
                    var text = TokenDiff.Compare(oldTokens, newTokens, separator, totals);
                    Output.Add($"a{oldNumber} b{newNumber}: {text}");
                }
                else if (row < block.X)
                {
                    var oldTokens = TokenDiff.Split(oldLines[oldNumber - 1], byWord);
                    totals.Deleted += oldTokens.Length;
                    Output.Add($"a{oldNumber}: {TokenDiff.Deletion(oldTokens, separator)}");
                }
                else
                {
                    var newTokens = TokenDiff.Split(newLines[newNumber - 1], byWord);
                    totals.Inserted += newTokens.Length;
                    Output.Add($"b{newNumber}: {TokenDiff.Insertion(newTokens, separator)}");
                }
            }
        }
        var label = byWord ? "WORDS" : "CHARS";
        Output.Add(
            $"{label} deleted={totals.Deleted} inserted={totals.Inserted} common={totals.Common}");
    }

    private static string StatGraph(int inserted, int deleted)
    {
        var total = inserted + deleted;
        var (plus, minus) = (inserted, deleted);
        if (total > GraphWidth)
        {
            plus = GraphWidth * inserted / total;
            minus = GraphWidth * deleted / total;
            if (inserted >= 1 && plus == 0)
            {
                plus = 1;
            }
            if (deleted >= 1 && minus == 0)
            {
                minus = 1;
            }
        }
        return new string('+', plus) + new string('-', minus);
    }

    private void Stat(string[] arguments)
    {
        var (oldName, newName) = (arguments[0], arguments[1]);
        Require(oldName, newName);
        var (oldLines, newLines) = (_files[oldName], _files[newName]);
        var diff = new LineDiff(oldLines, newLines, arguments[2..]);
        var deleted = diff.Blocks.Sum(block => block.X);
        var inserted = diff.Blocks.Sum(block => block.Y);
        var total = deleted + inserted;
        var unchanged = oldLines.Count - deleted;
        var summary = $"{oldName} -> {newName} | {total}";
        if (total > 0)
        {
            summary += " " + StatGraph(inserted, deleted);
        }
        Output.Add(summary);
        var lineTotal = oldLines.Count + newLines.Count;
        var similarity = lineTotal > 0 ? 200 * unchanged / lineTotal : 100;
        Output.Add($"changes={diff.Blocks.Count} insertions={inserted} deletions={deleted}"
            + $" unchanged={unchanged} similarity={similarity}%");
    }

    private void Patch(string[] arguments, List<string> data)
    {
        var name = arguments[0];
        Require(name);
        var options = arguments[2..];
        var reverse = options.Contains("REVERSE");
        var dryRun = options.Contains("DRYRUN");
        var fuzzIndex = Array.IndexOf(options, "FUZZ");
        var maxFuzz = fuzzIndex >= 0 ? int.Parse(options[fuzzIndex + 1]) : 0;
        var hunks = PatchParser.Parse(data);
        Output.Add((dryRun ? "checking file " : "patching file ") + name);
        var lines = _files[name];
        var first = hunks[0];
        if (first.Search(lines, 0, reverse, maxFuzz) is null
            && first.Search(lines, 0, !reverse, maxFuzz) is not null)
        {
            Output.Add("Reversed (or previously applied) patch detected! Skipping patch.");
            Output.Add($"RESULT applied=0 failed=0 ignored={hunks.Count} lines={lines.Count}");
            return;
        }
        var adjustment = 0;
        int applied = 0, failed = 0;
        for (var index = 0; index < hunks.Count; index++)
        {
            var hunk = hunks[index];
            var match = hunk.Search(lines, adjustment, reverse, maxFuzz);
            if (match is null)
            {
                failed++;
                Output.Add($"Hunk #{index + 1} FAILED at {hunk.Start(reverse)}");
                continue;
            }
            var (oldLines, newLines) = hunk.Sequences(reverse);
            lines = match.Lines;
            adjustment += match.Delta + newLines.Count - oldLines.Count;
            applied++;
            Output.Add(match.Report(index + 1));
        }
        Output.Add($"RESULT applied={applied} failed={failed} ignored=0 lines={lines.Count}");
        if (!dryRun && applied >= 1)
        {
            Save(name, lines);
        }
    }

    private void Edit(string[] arguments, List<string> data)
    {
        var name = arguments[0];
        Require(name);
        var (lines, executed) = EditScript.Run(_files[name], data);
        Output.Add($"EDIT {name} commands={executed} lines={lines.Count}");
        Save(name, lines);
    }

    private List<Chunk> ThreeWayChunks(string baseName, string oursName, string theirsName)
    {
        Require(baseName, oursName, theirsName);
        return ThreeWay.Chunks(_files[baseName], _files[oursName], _files[theirsName]);
    }

    private void Diff3(string[] arguments)
    {
        var (baseName, oursName, theirsName) = (arguments[0], arguments[1], arguments[2]);
        var chunks = ThreeWayChunks(baseName, oursName, theirsName);
        var changes = chunks.Where(chunk => chunk.Kind != ChunkKind.Stable).ToList();
        foreach (var chunk in changes)
        {
            Output.Add($"==== {chunk.KindName} {chunk.Location}");
            Output.AddRange(chunk.Base.Select(line => "O " + line));
            if (chunk.Kind != ChunkKind.B)
            {
                Output.AddRange(chunk.Ours.Select(line => "A " + line));
            }
            if (chunk.Kind is ChunkKind.B or ChunkKind.Conflict)
            {
                Output.AddRange(chunk.Theirs.Select(line => "B " + line));
            }
        }
        Output.Add($"DIFF3 chunks={changes.Count} {ThreeWay.KindCounts(chunks)}");
    }

    private void Merge(string[] arguments)
    {
        var (baseName, oursName, theirsName, target) =
            (arguments[0], arguments[1], arguments[2], arguments[3]);
        var mode = arguments.Length == 5 ? arguments[4] : "MARKERS";
        var chunks = ThreeWayChunks(baseName, oursName, theirsName);
        var result = new List<string>();
        var conflicts = new List<Chunk>();
        foreach (var chunk in chunks)
        {
            if (chunk.Kind == ChunkKind.B)
            {
                result.AddRange(chunk.Theirs);
            }
            else if (chunk.Kind == ChunkKind.Conflict)
            {
                result.AddRange(ThreeWay.ConflictLines(chunk, mode, baseName, oursName, theirsName));
                conflicts.Add(chunk);
            }
            else
            {
                result.AddRange(chunk.Ours);
            }
        }
        Output.Add($"MERGE {target} lines={result.Count} {ThreeWay.KindCounts(chunks)}");
        for (var index = 0; index < conflicts.Count; index++)
        {
            Output.Add($"CONFLICT {index + 1} {conflicts[index].Location}");
        }
        Save(target, result);
    }

    private void Conflicts(string[] arguments)
    {
        var name = arguments[0];
        Require(name);
        var regions = ConflictScanner.Regions(_files[name]);
        Output.Add($"CONFLICTS {name} count={regions.Count}");
        for (var index = 0; index < regions.Count; index++)
        {
            var region = regions[index];
            var baseCount = region.Base is null ? "none" : region.Base.Count.ToString();
            Output.Add($"{index + 1}: lines {region.Start}-{region.End} ours={region.Ours.Count}"
                + $" base={baseCount} theirs={region.Theirs.Count}");
        }
    }

    private void Resolve(string[] arguments)
    {
        var (name, side) = (arguments[0], arguments[2]);
        Require(name);
        var number = int.Parse(arguments[1]);
        var lines = _files[name];
        var regions = ConflictScanner.Regions(lines);
        if (regions.Count < number)
        {
            throw new CommandException($"ERROR no conflict {number} in {name}");
        }
        var region = regions[number - 1];
        if (side == "BASE" && region.Base is null)
        {
            throw new CommandException($"ERROR no base section in conflict {number}");
        }
        List<string> content = [.. lines[..(region.Start - 1)], .. region.Part(side), .. lines[region.End..]];
        var remaining = ConflictScanner.Regions(content).Count;
        Output.Add($"RESOLVE {name} {number} {side} lines={content.Count} remaining={remaining}");
        Save(name, content);
    }

    public void Execute(string[] words, List<string> data)
    {
        var arguments = words[1..];
        Action handler = words[0] switch
        {
            "FILE" => () => LoadFile(arguments, data),
            "COPY" => () => Copy(arguments),
            "PRINT" => () => PrintFile(arguments),
            "FILES" => ListFiles,
            "DIFF" => () => Diff(arguments),
            "WORDDIFF" => () => TokenDiffCommand(arguments, true),
            "CHARDIFF" => () => TokenDiffCommand(arguments, false),
            "STAT" => () => Stat(arguments),
            "PATCH" => () => Patch(arguments, data),
            "EDIT" => () => Edit(arguments, data),
            "DIFF3" => () => Diff3(arguments),
            "MERGE" => () => Merge(arguments),
            "CONFLICTS" => () => Conflicts(arguments),
            "RESOLVE" => () => Resolve(arguments),
            "UNDO" => () => Undo(arguments),
            _ => throw new ArgumentException($"unknown command {words[0]}"),
        };
        try
        {
            handler();
        }
        catch (CommandException error)
        {
            Output.Add(error.Message);
        }
    }
}
