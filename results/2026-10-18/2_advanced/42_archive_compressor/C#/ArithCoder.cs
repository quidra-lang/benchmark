using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class ArithCoder {
    public sealed class Table {
        public int[] frequencies = new int[257];
        public int total = 257, rescales;
        public Table() {
            System.Array.Fill(frequencies, 1);
        }
        public int Cumulative(int symbol) {
            int sum = 0;
            for (int i = 0; i < symbol; i++)
                sum += frequencies[i];
            return sum;
        }
        public int[] Locate(int value) {
            int cumulative = 0;
            for (int symbol = 0; symbol < 257; symbol++) {
                if (value < cumulative + frequencies[symbol])
                    return new int[] { symbol, cumulative, frequencies[symbol] };
                cumulative += frequencies[symbol];
            }
            throw new InvalidOperationException();
        }
        public void Update(int symbol) {
            frequencies[symbol] += 32;
            total += 32;
            if (total >= 8192) {
                total = 0;
                for (int i = 0; i < 257; i++) {
                    frequencies[i] = (frequencies[i] + 1) / 2;
                    total += frequencies[i];
                }
                rescales++;
            }
        }
    }
    public record Encoded(int[] payload, int bits, int contexts, int rescales) {
    }
    public sealed class Encoder {
        public BitIo.Writer writer = new BitIo.Writer();
        public int follow;
        public void Emit(int bit) {
            writer.Write(bit, 1);
            for (int i = 0; i < follow; i++)
                writer.Write(1 - bit, 1);
            follow = 0;
        }
    }
    public static Encoded Encode(int[] data) {
        Encoder e = new Encoder();
        Dictionary<int, Table> tables = new();
        int low = 0, high = 65535, context = 10;
        for (int index = 0; index <= data.Length; index++) {
            int symbol = index == data.Length ? 256 : data[index];
            Table table = tables.GetOrAdd(context, key => new Table());
            int cumulative = table.Cumulative(symbol), span = high - low + 1;
            high = low + span * (cumulative + table.frequencies[symbol]) / table.total - 1;
            low += span * cumulative / table.total;
            while (true) {
                if (high < 32768)
                    e.Emit(0);
                else if (low >= 32768) {
                    e.Emit(1);
                    low -= 32768;
                    high -= 32768;
                } else if (low >= 16384 && high < 49152) {
                    e.follow++;
                    low -= 16384;
                    high -= 16384;
                } else
                    break;
                low *= 2;
                high = 2 * high + 1;
            }
            if (symbol != 256) {
                table.Update(symbol);
                context = symbol;
            }
        }
        e.follow++;
        e.Emit(low < 16384 ? 0 : 1);
        int rescales = 0;
        foreach (Table t in tables.Values)
            rescales += t.rescales;
        return new Encoded(e.writer.Finish(), e.writer.count, tables.Count, rescales);
    }
    public static int[] Decode(int[] payload, long size) {
        BitIo.Reader reader = new BitIo.Reader(payload, true);
        Dictionary<int, Table> tables = new();
        List<int> output = new();
        int low = 0, high = 65535, value = reader.Read(16, 0), context = 10;
        while (true) {
            Table table = tables.GetOrAdd(context, key => new Table());
            int span = high - low + 1, quantile = ((value - low + 1) * table.total - 1) / span;
            int[] found = table.Locate(quantile);
            int symbol = found[0], cumulative = found[1], frequency = found[2];
            high = low + span * (cumulative + frequency) / table.total - 1;
            low += span * cumulative / table.total;
            while (true) {
                if (high < 32768) {
                } else if (low >= 32768) {
                    low -= 32768;
                    high -= 32768;
                    value -= 32768;
                } else if (low >= 16384 && high < 49152) {
                    low -= 16384;
                    high -= 16384;
                    value -= 16384;
                } else
                    break;
                low *= 2;
                high = 2 * high + 1;
                value = 2 * value + reader.Read(1, output.Count);
            }
            if (symbol == 256) {
                if (output.Count < size)
                    throw new BitIo.DecodeError("early_end", output.Count);
                return BitIo.Array(output);
            }
            if (output.Count == size)
                throw new BitIo.DecodeError("overrun", output.Count);
            output.Add(symbol);
            table.Update(symbol);
            context = symbol;
        }
    }
}
