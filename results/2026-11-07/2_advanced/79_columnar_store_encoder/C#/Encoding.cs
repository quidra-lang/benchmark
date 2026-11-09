using System;
using System.Collections.Generic;
using System.Linq;
using TextEncoding = System.Text.Encoding;
public static class Encoding {
    public static readonly List<string> METHODS =
        new() { "PLAIN", "DICTIONARY", "RLE", "DELTA_BINARY_PACKED", "DELTA_LENGTH_BYTE_ARRAY" };
    public record Bounds(SchemaIo.Value low, SchemaIo.Value high);
    public static List<int> Candidates(string kind) => kind == "BOOL"     ? new() { 0, 2 }
                                                       : kind == "STRING" ? new() { 0, 1, 4 }
                                                                          : new() { 0, 1, 3 };
    public static byte[] DeltaEncode(List<long> values) {
        Bitstream.Writer writer = new();
        writer.Uleb(128);
        writer.Uleb(4);
        writer.Uleb(values.Count);
        writer.Zigzag(values.Count == 0 ? 0 : values[0]);
        List<long> deltas = new();
        for (int i = 1; i < values.Count; i++)
            deltas.Add(values[i] - values[i - 1]);
        for (int start = 0; start < deltas.Count; start += 128) {
            List<long> block = deltas.Skip(start).Take(128).ToList();
            long minimum = block.Min();
            writer.Zigzag(minimum);
            List<List<long>> miniblocks = new();
            int[] widths = new int[4];
            for (int t = 0; t < 4; t++) {
                List<long> mini = new();
                long maximum = 0;
                for (int j = 32 * t; j < Math.Min(32 * (t + 1), block.Count); j++) {
                    long value = block[j] - minimum;
                    mini.Add(value);
                    maximum = Math.Max(maximum, value);
                }
                widths[t] = Bitstream.Bits(maximum);
                writer.ByteValue(widths[t]);
                miniblocks.Add(mini);
            }
            for (int t = 0; t < 4; t++)
                if (miniblocks[t].Count != 0) {
                    List<long> mini = miniblocks[t];
                    while (mini.Count < 32)
                        mini.Add(0);
                    writer.Bytes(Bitstream.Pack(mini, widths[t]));
                }
        }
        return writer.Value();
    }
    public static List<long> DeltaDecode(Bitstream.Reader reader) {
        int blockSize = (int)reader.Uleb(), miniblockCount = (int)reader.Uleb(),
            count = (int)reader.Uleb();
        long first = reader.Zigzag();
        List<long> values = new();
        if (count > 0)
            values.Add(first);
        int miniblockSize = blockSize / miniblockCount;
        while (values.Count < count) {
            long minimum = reader.Zigzag();
            int[] widths = new int[miniblockCount];
            for (int i = 0; i < widths.Length; i++)
                widths[i] = reader.ByteValue();
            foreach (int width in widths) {
                if (values.Count == count)
                    break;
                List<long> differences = Bitstream.Unpack(reader, width, miniblockSize);
                int remaining = Math.Min(miniblockSize, count - values.Count);
                for (int i = 0; i < remaining; i++)
                    values.Add(values[^1] + minimum + differences[i]);
            }
        }
        return values;
    }
    public static byte[] EncodeValues(string kind, int method, List<SchemaIo.Value> values,
                                      List<SchemaIo.Value> dictionary) {
        Bitstream.Writer writer = new();
        if (method == 0) {
            if (kind == "INT" || kind == "DATE")
                foreach (SchemaIo.NumberValue value in values)
                    writer.Integer(value.value);
            else if (kind == "STRING")
                foreach (SchemaIo.TextValue value in values) {
                    writer.Integer(value.value.Length);
                    writer.Bytes(TextEncoding.ASCII.GetBytes(value.value));
                }
            else {
                List<long> bits = values.Cast<SchemaIo.BoolValue>()
                                      .Select(value => value.value ? 1L : 0L)
                                      .ToList();
                while (bits.Count % 8 != 0)
                    bits.Add(0);
                writer.Bytes(Bitstream.Pack(bits, 1));
            }
        } else if (method == 1) {
            Dictionary<SchemaIo.Value, int> ranks = new();
            for (int i = 0; i < dictionary.Count; i++)
                ranks[dictionary[i]] = i;
            int width = Bitstream.Bits(dictionary.Count - 1);
            writer.ByteValue(width);
            writer.Bytes(
                Bitstream.HybridEncode(values.Select(value => (long)ranks[value]).ToList(), width));
        } else if (method == 2) {
            List<long> bits =
                values.Cast<SchemaIo.BoolValue>().Select(value => value.value ? 1L : 0L).ToList();
            byte[] encoded = Bitstream.HybridEncode(bits, 1);
            writer.Integer(encoded.Length);
            writer.Bytes(encoded);
        } else if (method == 3)
            writer.Bytes(DeltaEncode(
                values.Cast<SchemaIo.NumberValue>().Select(value => value.value).ToList()));
        else {
            writer.Bytes(DeltaEncode(values.Cast<SchemaIo.TextValue>()
                                         .Select(value => (long)value.value.Length)
                                         .ToList()));
            foreach (SchemaIo.TextValue value in values)
                writer.Bytes(TextEncoding.ASCII.GetBytes(value.value));
        }
        return writer.Value();
    }
    public static List<SchemaIo.Value> DecodeValues(Bitstream.Reader reader, string kind,
                                                    int method, int count,
                                                    List<SchemaIo.Value> dictionary) {
        List<SchemaIo.Value> values = new();
        if (method == 0) {
            if (kind == "INT" || kind == "DATE")
                for (int i = 0; i < count; i++)
                    values.Add(new SchemaIo.NumberValue(reader.Integer(true)));
            else if (kind == "STRING")
                for (int i = 0; i < count; i++)
                    values.Add(new SchemaIo.TextValue(
                        TextEncoding.ASCII.GetString(reader.Read((int)reader.Integer()))));
            else {
                List<long> bits = Bitstream.Unpack(reader, 1, (count + 7) / 8 * 8);
                for (int i = 0; i < count; i++)
                    values.Add(new SchemaIo.BoolValue(bits[i] != 0));
            }
        } else if (method == 1) {
            int width = reader.ByteValue();
            foreach (long index in Bitstream.HybridDecode(reader, width, count))
                values.Add(dictionary[(int)index]);
        } else if (method == 2) {
            Bitstream.Reader encoded = new(reader.Read((int)reader.Integer()));
            foreach (long value in Bitstream.HybridDecode(encoded, 1, count))
                values.Add(new SchemaIo.BoolValue(value != 0));
        } else if (method == 3)
            foreach (long value in DeltaDecode(reader))
                values.Add(new SchemaIo.NumberValue(value));
        else
            foreach (long length in DeltaDecode(reader))
                values.Add(
                    new SchemaIo.TextValue(TextEncoding.ASCII.GetString(reader.Read((int)length))));
        return values;
    }
    public static byte[] EncodeStatistics(string kind, Bounds bounds) {
        Bitstream.Writer writer = new();
        writer.ByteValue(bounds == null ? 0 : 1);
        if (bounds != null)
            foreach (SchemaIo.Value value in new[] { bounds.low, bounds.high })
                if (kind == "INT" || kind == "DATE")
                    writer.Zigzag(((SchemaIo.NumberValue)value).value);
                else if (kind == "STRING") {
                    string text = ((SchemaIo.TextValue)value).value;
                    writer.Uleb(text.Length);
                    writer.Bytes(TextEncoding.ASCII.GetBytes(text));
                } else
                    writer.ByteValue(((SchemaIo.BoolValue)value).value ? 1 : 0);
        return writer.Value();
    }
    public static Bounds DecodeStatistics(Bitstream.Reader reader, string kind) {
        if (reader.ByteValue() == 0)
            return null;
        List<SchemaIo.Value> values = new();
        for (int i = 0; i < 2; i++)
            if (kind == "INT" || kind == "DATE")
                values.Add(new SchemaIo.NumberValue(reader.Zigzag()));
            else if (kind == "STRING")
                values.Add(new SchemaIo.TextValue(
                    TextEncoding.ASCII.GetString(reader.Read((int)reader.Uleb()))));
            else
                values.Add(new SchemaIo.BoolValue(reader.ByteValue() != 0));
        return new(values[0], values[1]);
    }
}
