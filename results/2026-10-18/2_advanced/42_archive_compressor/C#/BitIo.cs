using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class BitIo {
    public static string Repeat(this string s, int count) => string.Concat(Enumerable.Repeat(s, count));
    public static bool Matches(this string s, string pattern) =>
        System.Text.RegularExpressions.Regex.IsMatch(s, "\\A(?:" + pattern + ")\\z");
    public static TValue GetOrAdd<TKey, TValue>(this IDictionary<TKey, TValue> map, TKey key,
                                                Func<TKey, TValue> factory) {
        if (!map.TryGetValue(key, out TValue value)) {
            value = factory(key);
            map[key] = value;
        }
        return value;
    }

    public sealed class DecodeError : Exception {
        public string kind;
        public int position;
        public DecodeError(string kind, int position) {
            this.kind = kind;
            this.position = position;
        }
    }
    public static int Bits(int value) {
        int count = 0;
        while (value != 0) {
            count++;
            value >> >= 1;
        }
        return count;
    }
    public sealed class Writer {
        public List<int> bytes = new();
        public int current, used, count;
        public void Write(int value, int width) {
            for (int i = width - 1; i >= 0; i--) {
                current = (current << 1) | ((value >>> i) & 1);
                used++;
                count++;
                if (used == 8) {
                    bytes.Add(current);
                    current = 0;
                    used = 0;
                }
            }
        }
        public int[] Finish() {
            List<int> result = new(bytes);
            if (used > 0)
                result.Add(current << (8 - used));
            int[] data = new int[result.Count];
            for (int i = 0; i < data.Length; i++)
                data[i] = result[i];
            return data;
        }
    }
    public sealed class Reader {
        public int[] data;
        public int position;
        public bool zero;
        public Reader(int[] data, bool zero) {
            this.data = data;
            this.zero = zero;
        }
        public int Read(int width, int output) {
            if (!zero && (long)position + width > 8L * data.Length)
                throw new DecodeError("end_of_data", output);
            int result = 0;
            for (int i = 0; i < width; i++) {
                int bit = position < 8L * data.Length ? (data[position / 8] >>> (7 - position % 8)) & 1 : 0;
                position++;
                result = (result << 1) | bit;
            }
            return result;
        }
    }
    public static int[] Array(List<int> values) {
        int[] result = new int[values.Count];
        for (int i = 0; i < result.Length; i++)
            result[i] = values[i];
        return result;
    }
}
