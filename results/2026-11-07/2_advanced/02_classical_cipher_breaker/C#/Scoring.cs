#nullable enable
using System;
using System.IO;
using System.Linq;
using System.Text;

static class Scoring
{
    public static bool IsLetter(char c) => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z';

    public static int Value(char c) => c is >= 'a' and <= 'z' ? c - 'a' : c - 'A';

    public static char Letter(int value) => (char)('A' + value);

    public static string Letters(string text)
    {
        var result = new StringBuilder(text.Length);
        foreach (char c in text)
            if (IsLetter(c))
                result.Append(Letter(Value(c)));
        return result.ToString();
    }

    public static string[] Groups(string letters)
    {
        var lines = new System.Collections.Generic.List<string>();
        var groups = new System.Collections.Generic.List<string>();
        for (int i = 0; i < letters.Length; i += 5)
        {
            groups.Add(letters.Substring(i, Math.Min(5, letters.Length - i)));
            if (groups.Count == 10)
            {
                lines.Add(string.Join(" ", groups));
                groups.Clear();
            }
        }
        if (groups.Count > 0)
            lines.Add(string.Join(" ", groups));
        return lines.ToArray();
    }

    public static int Mono(string letters, int[] weights)
    {
        int sum = 0;
        foreach (char c in letters)
            sum += weights[c - 'A'];
        return sum;
    }

    public static int Bi(string letters, int[,] weights)
    {
        int sum = 0;
        for (int i = 1; i < letters.Length; i++)
            sum += weights[letters[i - 1] - 'A', letters[i] - 'A'];
        return sum;
    }

    public static (int[] Mono, int[,] Bi) Read(string path)
    {
        string[] lines = File.ReadAllLines(path, Encoding.ASCII);
        int[] mono = lines[1].Split(' ').Select(int.Parse).ToArray();
        int[,] bi = new int[26, 26];
        for (int row = 0; row < 26; row++)
        {
            int[] values = lines[row + 3].Split(' ').Select(int.Parse).ToArray();
            for (int col = 0; col < 26; col++)
                bi[row, col] = values[col];
        }
        return (mono, bi);
    }
}
