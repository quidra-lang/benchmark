#nullable enable
using System.Collections.Generic;
using System.Text;

public sealed record Origin(string Document, int Line)
{
    public override string ToString() => $"{Document}:{Line}";
}

public sealed record Diagnostic(Origin Origin, string Code, string Message);

public sealed class LogicalLine
{
    public int Number { get; }
    public List<string> Segments { get; } = new();
    public (string Code, string Message)? Error { get; private set; }

    public LogicalLine(int number) => Number = number;
    public void Fail(string code, string message) => Error ??= (code, message);
}

public static class Lexer
{
    // Input is printable ASCII, so this marker cannot collide with input text.
    public const char LiteralDollar = '\u0001';

    public static IEnumerable<LogicalLine> Read(IReadOnlyList<string> physicalLines)
    {
        int index = 0;
        while (index < physicalLines.Count)
        {
            var line = new LogicalLine(index + 1);
            string source = physicalLines[index++];
            int position = 0;
            bool quoted = false;
            var current = new StringBuilder();
            while (position < source.Length)
            {
                char c = source[position];
                if (c == '\\' && position == source.Length - 1)
                {
                    source = physicalLines[index++].TrimStart(' ');
                    position = 0;
                }
                else if (quoted && c == '\\')
                {
                    char follower = source[position + 1];
                    char? decoded = follower switch
                    {
                        '\\' => '\\', '"' => '"', 'n' => '\n', 't' => '\t',
                        '$' => LiteralDollar, _ => null
                    };
                    if (decoded.HasValue)
                        current.Append(decoded.Value);
                    else
                        line.Fail("E_ESCAPE", "invalid escape sequence \\" + follower);
                    position += 2;
                }
                else if (c == '"')
                {
                    line.Segments.Add(current.ToString());
                    current.Clear();
                    quoted = !quoted;
                    position++;
                }
                else if (!quoted && (c == ';' || c == '#'))
                    break;
                else
                {
                    current.Append(c);
                    position++;
                }
            }
            if (quoted)
                line.Fail("E_UNTERMINATED", "unterminated string");
            line.Segments.Add(current.ToString());
            yield return line;
        }
    }
}
