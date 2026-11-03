using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Lz77 {
    public record Token(int literal, int distance, int length) {
    }
    public static List<Token> Split(int[] data, int b, int k) {
        List<Token> result = new();
        int i = 0, window = 1 << b, limit = (1 << k) + 2;
        while (i < data.Length) {
            int distance = 0, length = 0;
            for (int d = 1; d <= Math.Min(window, i); d++) {
                int match = 0;
                while (match < Math.Min(limit, data.Length - i) && data[i + match] == data[i + match - d])
                    match++;
                if (match > length) {
                    length = match;
                    distance = d;
                }
            }
            if (length >= 3) {
                result.Add(new Token(-1, distance, length));
                i += length;
            } else {
                result.Add(new Token(data[i], 0, 0));
                i++;
            }
        }
        return result;
    }
    public static void Copy(List<int> output, int distance, int length, long size) {
        if (distance > output.Count)
            throw new BitIo.DecodeError("bad_offset", output.Count);
        if ((long)output.Count + length > size)
            throw new BitIo.DecodeError("overrun", output.Count);
        for (int i = 0; i < length; i++)
            output.Add(output[output.Count - distance]);
    }
}
