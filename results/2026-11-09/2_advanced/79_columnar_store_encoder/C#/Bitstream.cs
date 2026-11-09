using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
public static class Bitstream {
    public sealed class Writer {
        private MemoryStream output = new();
        public void ByteValue(int value) { output.WriteByte((byte)value); }
        public void Bytes(byte[] values) { output.Write(values); }
        public void Uleb(long value) {
            while (value >= 128) {
                ByteValue((int)(value % 128) + 128);
                value /= 128;
            }
            ByteValue((int)value);
        }
        public void Zigzag(long value) { Uleb(value >= 0 ? 2 * value : -2 * value - 1); }
        public void Integer(long value) {
            for (int i = 0; i < 4; i++)
                ByteValue((int)((value >>> (8 * i)) & 255));
        }
        public int Size() => (int)output.Length;
        public byte[] Value() => output.ToArray();
    }
    public sealed class Reader {
        public byte[] data;
        public int position;
        public Reader(byte[] data, int position = 0) {
            this.data = data;
            this.position = position;
        }
        public byte[] Read(int count) {
            byte[] value = data[position..(position + count)];
            position += count;
            return value;
        }
        public int ByteValue() => data[position++];
        public long Uleb() {
            long value = 0;
            int shift = 0;
            while (true) {
                int b = ByteValue();
                value |= (long)(b & 127) << shift;
                if (b < 128)
                    return value;
                shift += 7;
            }
        }
        public long Zigzag() {
            long value = Uleb();
            return value % 2 == 0 ? value / 2 : -(value + 1) / 2;
        }
        public long Integer(bool signed = false) {
            long value = 0;
            for (int i = 0; i < 4; i++)
                value |= (long)ByteValue() << (8 * i);
            return signed && value >= 0x80000000L ? value - 0x100000000L : value;
        }
    }
    public static int Bits(long value) =>
        value == 0 ? 0 : 64 - System.Numerics.BitOperations.LeadingZeroCount((ulong)value);
    public static byte[] Pack(List<long> values, int width) {
        Writer writer = new();
        long buffer = 0;
        int occupied = 0;
        foreach (long value in values) {
            buffer |= value << occupied;
            occupied += width;
            while (occupied >= 8) {
                writer.ByteValue((int)buffer & 255);
                buffer >> >= 8;
                occupied -= 8;
            }
        }
        return writer.Value();
    }
    public static List<long> Unpack(Reader reader, int width, int count) {
        List<long> values = new();
        long buffer = 0, mask = (1L << width) - 1;
        int occupied = 0;
        for (int i = 0; i < count; i++) {
            while (occupied < width) {
                buffer |= (long)reader.ByteValue() << occupied;
                occupied += 8;
            }
            values.Add(buffer & mask);
            buffer >> >= width;
            occupied -= width;
        }
        return values;
    }
    public static long Adler32(byte[] data) {
        long first = 1, second = 0;
        foreach (byte value in data) {
            first = (first + value) % 65521;
            second = (second + first) % 65521;
        }
        return second * 65536 + first;
    }
    public static byte[] HybridEncode(List<long> values, int width) {
        int count = values.Count;
        int[] runs = new int[count];
        for (int i = count - 1; i >= 0; i--) {
            runs[i] = 1;
            if (i + 1 < count && values[i] == values[i + 1])
                runs[i] += runs[i + 1];
        }
        Writer writer = new();
        int index = 0;
        while (index < count) {
            if (runs[index] >= 8) {
                writer.Uleb(2L * runs[index]);
                for (int j = 0; j < (width + 7) / 8; j++)
                    writer.ByteValue((int)((values[index] >>> (8 * j)) & 255));
                index += runs[index];
            } else {
                int end = index, groups = 0;
                do {
                    end += 8;
                    groups++;
                } while (end < count && groups < 63 && runs[end] < 8);
                writer.Uleb(2L * groups + 1);
                List<long> block = values.Skip(index).Take(Math.Min(end, count) - index).ToList();
                while (block.Count < end - index)
                    block.Add(0);
                writer.Bytes(Pack(block, width));
                index = end;
            }
        }
        return writer.Value();
    }
    public static List<long> HybridDecode(Reader reader, int width, int count) {
        List<long> values = new();
        while (values.Count < count) {
            long header = reader.Uleb();
            if (header % 2 == 0) {
                long value = 0;
                for (int i = 0; i < (width + 7) / 8; i++)
                    value |= (long)reader.ByteValue() << (8 * i);
                for (long i = 0; i < header / 2; i++)
                    values.Add(value);
            } else
                values.AddRange(Unpack(reader, width, (int)((header - 1) / 2) * 8));
        }
        return values.Take(count).ToList();
    }
}
