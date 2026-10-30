using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
public static class Bitstream {
    public static readonly string ALPHANUMERIC = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
    public static string Binary(int value, int width) {
        StringBuilder result = new StringBuilder();
        for (int bit = width - 1; bit >= 0; bit--)
            result.Append((value >>> bit) & 1);
        return result.ToString();
    }
    public sealed class Writer {
        public StringBuilder bits = new StringBuilder();
        public void Write(int value, int width) { bits.Append(Binary(value, width)); }
        public string Value() { return bits.ToString(); }
    }
    public sealed class Reader {
        public string bits;
        public int position;
        public Reader(string bits) { this.bits = bits; }
        public int Remaining() { return bits.Length - position; }
        public int Read(int width) {
            int value = 0;
            for (int i = 0; i < width; i++)
                value = (value << 1) | (bits[position++] - '0');
            return value;
        }
    }
    public static int[] ToCodewords(string bits) {
        int[] words = new int[bits.Length / 8];
        Reader reader = new Reader(bits);
        for (int i = 0; i < words.Length; i++)
            words[i] = reader.Read(8);
        return words;
    }
    public static string FromCodewords(int[] words) {
        Writer writer = new Writer();
        foreach (int word in words)
            writer.Write(word, 8);
        return writer.Value();
    }
    public static string Hexadecimal(int[] words) {
        StringBuilder result = new StringBuilder();
        foreach (int word in words) {
            result.Append("0123456789abcdef"[word >>> 4]);
            result.Append("0123456789abcdef"[word & 15]);
        }
        return result.ToString();
    }
}
