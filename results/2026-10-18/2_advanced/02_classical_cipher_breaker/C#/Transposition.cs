#nullable enable
using System;
using System.Linq;
using System.Text;
using System.Collections.Generic;

static class Transposition
{
    public static int Rail(int position, int rails)
    {
        int cycle = 2 * rails - 2;
        int offset = position % cycle;
        return Math.Min(offset, cycle - offset);
    }

    public static string RailFence(string letters, int rails, bool encrypt)
    {
        int n = letters.Length;
        int[] order = Enumerable.Range(0, n)
            .OrderBy(i => Rail(i, rails))
            .ThenBy(i => i)
            .ToArray();
        char[] output = new char[n];
        if (encrypt)
        {
            for (int i = 0; i < n; i++)
                output[i] = letters[order[i]];
        }
        else
        {
            for (int i = 0; i < n; i++)
                output[order[i]] = letters[i];
        }
        return new string(output);
    }

    public static int[] Order(string key)
    {
        return Enumerable.Range(0, key.Length)
            .OrderBy(i => key[i])
            .ThenBy(i => i)
            .ToArray();
    }

    public static string RankString(string key)
    {
        int[] order = Order(key);
        char[] digits = new char[key.Length];
        for (int i = 0; i < key.Length; i++)
            digits[order[i]] = (char)('1' + i);
        return new string(digits);
    }

    public static string Columnar(string letters, string key, bool encrypt)
    {
        int width = key.Length;
        int length = letters.Length;
        int[] order = Order(key);
        char[] result = new char[length];
        int position = 0;
        if (encrypt)
        {
            foreach (int col in order)
                for (int p = col; p < length; p += width)
                    result[position++] = letters[p];
        }
        else
        {
            foreach (int col in order)
                for (int p = col; p < length; p += width)
                    result[p] = letters[position++];
        }
        return new string(result);
    }
}
