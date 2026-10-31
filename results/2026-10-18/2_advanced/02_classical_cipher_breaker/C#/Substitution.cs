#nullable enable
using System;
using System.Text;

static class Substitution
{
    public static int Mod(int x, int m = 26) => (x % m + m) % m;

    public static int Inverse(int a)
    {
        for (int i = 1; i < 26; i++)
            if (a * i % 26 == 1)
                return i;
        throw new ArgumentException("Non-invertible affine key");
    }

    public static string Apply(string text, string cipher, string key, bool encrypt)
    {
        var result = new StringBuilder(text.Length);
        int letterIndex = 0;
        string prefix = key;
        int a = 1;
        int b = 0;
        if (cipher == "caesar")
            b = int.Parse(key);
        else if (cipher == "affine")
        {
            string[] parts = key.Split(',');
            a = int.Parse(parts[0]);
            b = int.Parse(parts[1]);
        }
        int inverse = cipher == "affine" ? Inverse(a) : 1;
        var plaintext = new System.Collections.Generic.List<int>();
        foreach (char c in text)
        {
            if (!Scoring.IsLetter(c))
            {
                result.Append(c);
                continue;
            }
            int x = Scoring.Value(c);
            int shift = 0;
            if (cipher == "vigenere")
                shift = Scoring.Value(prefix[letterIndex % prefix.Length]);
            else if (cipher == "autokey")
                shift = letterIndex < prefix.Length
                    ? Scoring.Value(prefix[letterIndex])
                    : plaintext[letterIndex - prefix.Length];
            int y = cipher switch
            {
                "caesar" => Mod(x + (encrypt ? b : -b)),
                "affine" => encrypt ? Mod(a * x + b) : Mod(inverse * (x - b)),
                "vigenere" or "autokey" => Mod(x + (encrypt ? shift : -shift)),
                _ => throw new ArgumentException("Unknown substitution cipher")
            };
            plaintext.Add(encrypt ? x : y);
            result.Append((char)((c is >= 'a' and <= 'z' ? 'a' : 'A') + y));
            letterIndex++;
        }
        return result.ToString();
    }
}
