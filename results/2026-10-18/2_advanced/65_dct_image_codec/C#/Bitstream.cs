using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Bitstream {
    public sealed class DecodeError : Exception {
        public readonly string kind;
        public DecodeError(string kind) : base(kind) { this.kind = kind; }
    }
    public sealed class Writer {
        public readonly List<int> data = new();
        public int buffer, pending, paddingBits, stuffedBytes;
        public void Write(int value, int width) {
            for (int shift = width - 1; shift >= 0; shift--) {
                buffer = 2 * buffer + ((value >> shift) & 1);
                pending++;
                if (pending == 8) {
                    data.Add(buffer);
                    if (buffer == 255) {
                        data.Add(0);
                        stuffedBytes++;
                    }
                    buffer = pending = 0;
                }
            }
        }
        public void Pad() {
            if (pending != 0) {
                int width = 8 - pending;
                paddingBits += width;
                Write((1 << width) - 1, width);
            }
        }
        public void Restart(int number) {
            Pad();
            data.Add(255);
            data.Add(208 + number % 8);
        }
    }
    public sealed class Reader {
        public readonly int[] data;
        public int position, buffer, remaining;
        public Reader(int[] data, int position) {
            this.data = data;
            this.position = position;
        }
        public int Bit() {
            if (remaining == 0) {
                int value = data[position];
                if (value == 255) {
                    if (data[position + 1] != 0)
                        throw new DecodeError("marker");
                    position += 2;
                } else
                    position++;
                buffer = value;
                remaining = 8;
            }
            remaining--;
            return (buffer >> remaining) & 1;
        }
        public int Read(int width) {
            int value = 0;
            for (int i = 0; i < width; i++)
                value = 2 * value + Bit();
            return value;
        }
        public void Discard() { buffer = remaining = 0; }
    }
    public static int Resync(int[] data, int position) {
        for (int q = position; q < data.Length - 1; q++)
            if (data[q] == 255 && (data[q + 1] >= 208 && data[q + 1] <= 215 || data[q + 1] == 217))
                return q;
        throw new InvalidOperationException();
    }
}
