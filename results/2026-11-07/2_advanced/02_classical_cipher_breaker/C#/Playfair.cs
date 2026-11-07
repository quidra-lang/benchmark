#nullable enable
using System;
using System.Linq;
using System.Text;
using System.Collections.Generic;

static class Playfair
{
    public static string Square(string key)
    {
        var visited = new HashSet<char>();
        var builder = new StringBuilder(25);
        foreach (char c in key.ToUpperInvariant().Replace('J', 'I') + "ABCDEFGHIKLMNOPQRSTUVWXYZ")
            if (visited.Add(c))
                builder.Append(c);
        return builder.ToString();
    }

    public static bool Valid(string text)
    {
        string normalized = text.Replace('J', 'I');
        if (normalized.Length % 2 != 0)
            return false;
        for (int i = 0; i < normalized.Length; i += 2)
            if (normalized[i] == normalized[i + 1])
                return false;
        return true;
    }

    public static string Prepare(string text)
    {
        text = text.Replace('J', 'I');
        var prepared = new StringBuilder(text.Length + 4);
        int index = 0;
        while (index < text.Length)
        {
            char first = text[index];
            char second;
            if (index + 1 < text.Length && text[index + 1] != first)
            {
                second = text[index + 1];
                index += 2;
            }
            else
            {
                second = first == 'X' ? 'Q' : 'X';
                index++;
            }
            prepared.Append(first).Append(second);
        }
        return prepared.ToString();
    }

    public static string Apply(string letters, string key, bool encrypt)
    {
        string square = Square(key);
        string text = encrypt ? Prepare(letters) : letters.Replace('J', 'I');
        var result = new StringBuilder(text.Length);
        int distance = encrypt ? 1 : 4;
        for (int i = 0; i < text.Length; i += 2)
        {
            int ai = square.IndexOf(text[i]);
            int bi = square.IndexOf(text[i + 1]);
            int ar = ai / 5, ac = ai % 5;
            int br = bi / 5, bc = bi % 5;
            if (ar == br)
            {
                ac = (ac + distance) % 5;
                bc = (bc + distance) % 5;
            }
            else if (ac == bc)
            {
                ar = (ar + distance) % 5;
                br = (br + distance) % 5;
            }
            else
            {
                (ac, bc) = (bc, ac);
            }
            result.Append(square[5 * ar + ac]);
            result.Append(square[5 * br + bc]);
        }
        return result.ToString();
    }
}
