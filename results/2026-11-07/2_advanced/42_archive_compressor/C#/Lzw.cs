using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Lzw {
    public sealed class Statistics {
        public int codes, clears, longest;
        public int[] widths = new int[4];
    }
    public record Encoded(int[] payload, Statistics stats) {
    }
    public static Dictionary<string, int> CreateDictionary() {
        Dictionary<string, int> result = new();
        for (int i = 0; i < 256; i++)
            result[((char)i).ToString()] = i;
        return result;
    }
    public sealed class Encoder {
        public BitIo.Writer writer = new BitIo.Writer();
        public Statistics stats = new Statistics();
        public int since;
        public void Emit(int code, int length) {
            int width = Math.Min(12, BitIo.Bits(258 + since));
            writer.Write(code, width);
            stats.codes++;
            stats.widths[width - 9]++;
            stats.longest = Math.Max(stats.longest, length);
            if (code == 256) {
                stats.clears++;
                since = 0;
            } else
                since++;
        }
    }
    public static Encoded Encode(int[] data) {
        Encoder e = new Encoder();
        Dictionary<string, int> dictionary = CreateDictionary();
        int next = 258;
        e.Emit(256, 0);
        string sequence = "";
        foreach (int value in data) {
            string character = ((char)value).ToString(), extended = sequence + character;
            if (dictionary.ContainsKey(extended)) {
                sequence = extended;
                continue;
            }
            e.Emit(dictionary[sequence], sequence.Length);
            dictionary[extended] = next++;
            if (next == 4096) {
                e.Emit(256, 0);
                dictionary = CreateDictionary();
                next = 258;
            }
            sequence = character;
        }
        if (sequence.Length != 0)
            e.Emit(dictionary[sequence], sequence.Length);
        e.Emit(257, 0);
        return new Encoded(e.writer.Finish(), e.stats);
    }
    public static List<string> DecodedDictionary() {
        List<string> result = new();
        for (int i = 0; i < 256; i++)
            result.Add(((char)i).ToString());
        result.Add(null);
        result.Add(null);
        return result;
    }
    public static int[] Decode(int[] payload, long size) {
        BitIo.Reader reader = new BitIo.Reader(payload, false);
        List<string> dictionary = DecodedDictionary();
        List<int> output = new();
        int previous = -1, since = 0;
        while (true) {
            int count = since, code = reader.Read(Math.Min(12, BitIo.Bits(258 + count)), output.Count);
            if (code == 256) {
                dictionary = DecodedDictionary();
                previous = -1;
                since = 0;
                continue;
            }
            since++;
            if (code == 257) {
                if (output.Count < size)
                    throw new BitIo.DecodeError("early_end", output.Count);
                return BitIo.Array(output);
            }
            if (count == 3838)
                throw new BitIo.DecodeError("bad_code", output.Count);
            string sequence;
            if (previous == -1) {
                if (code >= 256)
                    throw new BitIo.DecodeError("bad_code", output.Count);
                sequence = dictionary[code];
            } else if (code < dictionary.Count)
                sequence = dictionary[code];
            else if (code == dictionary.Count)
                sequence = dictionary[previous] + dictionary[previous][0];
            else
                throw new BitIo.DecodeError("bad_code", output.Count);
            if ((long)output.Count + sequence.Length > size)
                throw new BitIo.DecodeError("overrun", output.Count);
            for (int i = 0; i < sequence.Length; i++)
                output.Add((int)sequence[i]);
            if (previous != -1)
                dictionary.Add(dictionary[previous] + sequence[0]);
            previous = code;
        }
    }
}
