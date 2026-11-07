using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Hashing {
    public static string Digest(string text) {
        long[] bases = { 1000003, 1500007, 2750159, 4194301 }, initials = { 11, 23, 37, 53 };
        StringBuilder result = new StringBuilder();
        for (int lane = 0; lane < 4; lane++) {
            long value = initials[lane];
            for (int i = 0; i < text.Length; i++)
                value = (value * bases[lane] + text[i]) % 2147483647;
            foreach (int extra in new int[] { text.Length, 0, 0 })
                value = (value * bases[lane] + extra) % 2147483647;
            result.Append(value.ToString("x8", CultureInfo.InvariantCulture));
        }
        return result.ToString();
    }
    public static string Merkle(List<string> hashes) {
        List<string> level = hashes.ToList();
        while (level.Count > 1) {
            if (level.Count % 2 == 1)
                level.Add(level[^1]);
            List<string> next = new();
            for (int i = 0; i < level.Count; i += 2)
                next.Add(Digest(level[i] + level[i + 1]));
            level = next;
        }
        return level[0];
    }
    public static string ShortId(string value) {
        return value.Substring(0, 8);
    }
}
