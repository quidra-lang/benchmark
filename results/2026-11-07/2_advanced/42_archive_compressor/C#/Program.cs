using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    static List<string> manifestNames = new();
    public static readonly List<string> METHODS = ["STORE", "LZW", "LZ77", "LZH", "ARITH"], STATUSES = [
        "ok", "repaired", "checksum", "error", "unsupported", "truncated", "bad_header"
    ];
    public sealed class Lzh {
        public int[] payload;
        public bool dynamicWriter;
        public int fixedBits, tableBits, codeBits, halvings, litUsed, litMax, offsetUsed, offsetMax;
        public int[] slots;
    }
    public static int[] Fixed(int count) {
        int width = BitIo.Bits(count - 1), shorter = (1 << width) - count;
        int[] result = new int[count];
        for (int i = 0; i < count; i++)
            result[i] = i < shorter ? width - 1 : width;
        return result;
    }
    public static void WriteTable(BitIo.Writer writer, int[] lengths) {
        int s = 0;
        while (s < lengths.Length) {
            if (lengths[s] > 0) {
                writer.Write(lengths[s], 4);
                s++;
            } else {
                int count = 1;
                while (count < 256 && s + count < lengths.Length && lengths[s + count] == 0)
                    count++;
                writer.Write(0, 4);
                writer.Write(count - 1, 8);
                s += count;
            }
        }
    }
    public static int[] ReadTable(BitIo.Reader reader, int count, int position) {
        int[] lengths = new int[count];
        int s = 0;
        while (s < count) {
            int value = reader.Read(4, position);
            if (value > 0)
                lengths[s++] = value;
            else {
                int run = reader.Read(8, position) + 1;
                if (s + run > count)
                    throw new BitIo.DecodeError("bad_table", position);
                s += run;
            }
        }
        int used = 0, only = 0, sum = 0;
        foreach (int value in lengths)
            if (value > 0) {
                used++;
                only = value;
                sum += 1 << (15 - value);
            }
        if ((used == 1 && only != 1) || (used >= 2 && sum != (1 << 15)))
            throw new BitIo.DecodeError("bad_table", position);
        return lengths;
    }
    public static void Symbol(BitIo.Writer writer, int symbol, int[] lengths, int[] codes) {
        writer.Write(codes[symbol], lengths[symbol]);
    }
    public static int ReadSymbol(BitIo.Reader reader, int[] lengths, int[] codes, int position) {
        int maximum = 0;
        foreach (int length in lengths)
            maximum = Math.Max(maximum, length);
        if (maximum == 0)
            throw new BitIo.DecodeError("bad_code", position);
        int code = 0;
        for (int width = 1; width <= maximum; width++) {
            code = (code << 1) | reader.Read(1, position);
            for (int s = 0; s < lengths.Length; s++)
                if (lengths[s] == width && codes[s] == code)
                    return s;
        }
        throw new BitIo.DecodeError("bad_code", position);
    }
    public static void Tokens(BitIo.Writer writer, List<Lz77.Token> tokens, int[] p, int[] q) {
        int[] pc = Huffman.Canonical(p), qc = Huffman.Canonical(q);
        foreach (Lz77.Token t in tokens) {
            if (t.literal >= 0)
                Symbol(writer, t.literal, p, pc);
            else {
                Symbol(writer, 256 + t.length - 3, p, pc);
                int u = t.distance - 1, slot = BitIo.Bits(u);
                Symbol(writer, slot, q, qc);
                if (slot >= 2)
                    writer.Write(u - (1 << (slot - 1)), slot - 1);
            }
        }
    }
    public static Lzh EncodeLzh(List<Lz77.Token> tokens, int b, int k, int maximum) {
        int[] pFrequency = new int[256 + (1 << k)], qFrequency = new int[b + 1];
        foreach (Lz77.Token t in tokens) {
            if (t.literal >= 0)
                pFrequency[t.literal]++;
            else {
                pFrequency[256 + t.length - 3]++;
                qFrequency[BitIo.Bits(t.distance - 1)]++;
            }
        }
        Huffman.Limited p = Huffman.LimitLengths(pFrequency, maximum),
                        q = Huffman.LimitLengths(qFrequency, maximum);
        Lzh result = new Lzh();
        result.slots = qFrequency;
        result.halvings = p.halvings + q.halvings;
        foreach (int value in p.lengths)
            if (value > 0) {
                result.litUsed++;
                result.litMax = Math.Max(result.litMax, value);
            }
        foreach (int value in q.lengths)
            if (value > 0) {
                result.offsetUsed++;
                result.offsetMax = Math.Max(result.offsetMax, value);
            }
        int[] fp = Fixed(pFrequency.Length), fq = Fixed(qFrequency.Length);
        BitIo.Writer fixedWriter = new BitIo.Writer();
        Tokens(fixedWriter, tokens, fp, fq);
        result.fixedBits = fixedWriter.count;
        BitIo.Writer tables = new BitIo.Writer();
        WriteTable(tables, p.lengths);
        WriteTable(tables, q.lengths);
        result.tableBits = tables.count;
        BitIo.Writer dynamicWriter = new BitIo.Writer();
        Tokens(dynamicWriter, tokens, p.lengths, q.lengths);
        result.codeBits = dynamicWriter.count;
        result.dynamicWriter = result.fixedBits > result.tableBits + result.codeBits;
        BitIo.Writer writer = new BitIo.Writer();
        writer.Write(result.dynamicWriter ? 1 : 0, 1);
        if (result.dynamicWriter) {
            WriteTable(writer, p.lengths);
            WriteTable(writer, q.lengths);
            Tokens(writer, tokens, p.lengths, q.lengths);
        } else
            Tokens(writer, tokens, fp, fq);
        result.payload = writer.Finish();
        return result;
    }
    public static int[] EncodeLz77(List<Lz77.Token> tokens, int b, int k) {
        BitIo.Writer writer = new BitIo.Writer();
        foreach (Lz77.Token t in tokens)
            if (t.literal >= 0) {
                writer.Write(0, 1);
                writer.Write(t.literal, 8);
            } else {
                writer.Write(1, 1);
                writer.Write(t.distance - 1, b);
                writer.Write(t.length - 3, k);
            }
        return writer.Finish();
    }
    public static int[] Decode(int method, int[] payload, long size, int b, int k) {
        if (method == 1)
            return Lzw.Decode(payload, size);
        if (method == 4)
            return ArithCoder.Decode(payload, size);
        List<int> output = new();
        if (method == 0) {
            foreach (int value in payload) {
                if (output.Count == size)
                    break;
                output.Add(value);
            }
            if (output.Count < size)
                throw new BitIo.DecodeError("end_of_data", output.Count);
            return BitIo.Array(output);
        }
        BitIo.Reader reader = new BitIo.Reader(payload, false);
        int[] p = null, q = null, pc = null, qc = null;
        if (method == 3) {
            if (reader.Read(1, 0) == 1) {
                p = ReadTable(reader, 256 + (1 << k), 0);
                q = ReadTable(reader, b + 1, 0);
            } else {
                p = Fixed(256 + (1 << k));
                q = Fixed(b + 1);
            }
            pc = Huffman.Canonical(p);
            qc = Huffman.Canonical(q);
        }
        while (output.Count < size) {
            if (method == 2) {
                if (reader.Read(1, output.Count) == 0)
                    output.Add(reader.Read(8, output.Count));
                else {
                    int distance = reader.Read(b, output.Count) + 1,
                        length = reader.Read(k, output.Count) + 3;
                    Lz77.Copy(output, distance, length, size);
                }
            } else {
                int t = ReadSymbol(reader, p, pc, output.Count);
                if (t < 256)
                    output.Add(t);
                else {
                    int length = t - 253, slot = ReadSymbol(reader, q, qc, output.Count),
                        u = slot <= 1 ? slot : (1 << (slot - 1)) + reader.Read(slot - 1, output.Count);
                    Lz77.Copy(output, u + 1, length, size);
                }
            }
        }
        return BitIo.Array(output);
    }
    public sealed class Encoded {
        public int[][] payloads;
        public int best;
        public Lzw.Statistics lzw;
        public List<Lz77.Token> tokens;
        public Lzh lzh;
        public ArithCoder.Encoded arith;
    }
    public static Encoded Encode(int[] data, int b, int k, int m) {
        Encoded result = new Encoded();
        result.tokens = Lz77.Split(data, b, k);
        Lzw.Encoded lzw = Lzw.Encode(data);
        result.lzw = lzw.stats;
        result.lzh = EncodeLzh(result.tokens, b, k, m);
        result.arith = ArithCoder.Encode(data);
        result.payloads = new int[][] { data.ToArray(), lzw.payload, EncodeLz77(result.tokens, b, k),
                                        result.lzh.payload, result.arith.payload };
        for (int i = 1; i < 5; i++)
            if (result.payloads[i].Length < result.payloads[result.best].Length)
                result.best = i;
        return result;
    }
    public static long Adler(int[] data) {
        long s1 = 1, s2 = 0;
        foreach (int x in data) {
            s1 = (s1 + x) % 65521;
            s2 = (s2 + s1) % 65521;
        }
        return s2 * 65536 + s1;
    }
    public static long Mod(long value) {
        return (value % 65521 + 65521) % 65521;
    }
    public static long Power(long value, int exponent) {
        long result = 1;
        while (exponent > 0) {
            if ((exponent & 1) != 0)
                result = result * value % 65521;
            value = value * value % 65521;
            exponent >> >= 1;
        }
        return result;
    }
    public record Repair(int position, int before, int after) {
    }
    public static Repair TryRepair(int[] data, long stored, long computed) {
        long a = Mod(stored % 65536 - computed % 65536), b = Mod(stored / 65536 - computed / 65536);
        int delta;
        if (a >= 1 && a <= 255)
            delta = (int)a;
        else if (a >= 65266 && a <= 65520)
            delta = (int)a - 65521;
        else
            return null;
        long t = b * Power(Mod(delta), 65519) % 65521;
        if (t < 1 || t > data.Length)
            return null;
        int p = data.Length - (int)t, before = data[p], after = before + delta;
        if (after < 0 || after > 255)
            return null;
        data[p] = after;
        if (Adler(data) == stored)
            return new Repair(p, before, after);
        data[p] = before;
        return null;
    }
    public static void Integer(List<int> output, long value, int width) {
        for (int i = width - 1; i >= 0; i--)
            output.Add((int)((value >>> (8 * i)) & 255));
    }
    public static long Integer(int[] data, int position, int width) {
        long value = 0;
        for (int i = 0; i < width; i++)
            value = value * 256 + data[position + i];
        return value;
    }
    public static int[] Ascii(string text) {
        int[] data = new int[text.Length];
        for (int i = 0; i < data.Length; i++)
            data[i] = text[i];
        return data;
    }
    public record Item(string name, int[] data, Encoded encoded) {
    }
    public static int[] Archive(List<Item> items, int b, int k) {
        List<int> output = new();
        foreach (int value in Ascii("TXAR"))
            output.Add(value);
        output.Add(b);
        output.Add(k);
        Integer(output, items.Count, 2);
        foreach (Item item in items) {
            int start = output.Count, method = item.encoded.best;
            output.Add(item.name.Length);
            foreach (int value in Ascii(item.name))
                output.Add(value);
            output.Add(method);
            Integer(output, item.data.Length, 4);
            int[] payload = item.encoded.payloads[method];
            Integer(output, payload.Length, 4);
            Integer(output, Adler(item.data), 4);
            int sum = 0;
            for (int i = start; i < output.Count; i++)
                sum += output[i];
            output.Add(sum % 256);
            foreach (int value in payload)
                output.Add(value);
        }
        return BitIo.Array(output);
    }
    public sealed class Entry {
        public int number, method;
        public long offset, start, original, compressed, stored, computed;
        public string name = "", status, detail = "";
        public bool valid, headerTruncated;
        public int[] data;
    }
    public sealed class Parsed {
        public string error;
        public int length, b, k, declared, trailing;
        public bool stopped;
        public List<Entry> entries = new();
    }
    public static Parsed Parse(int[] data) {
        Parsed result = new Parsed();
        result.length = data.Length;
        if (data.Length < 8 || data[0] != 'T' || data[1] != 'X' || data[2] != 'A' || data[3] != 'R') {
            result.error = "bad_magic";
            return result;
        }
        result.b = data[4];
        result.k = data[5];
        if (result.b < 6 || result.b > 12 || result.k < 2 || result.k > 5) {
            result.error = "bad_params";
            return result;
        }
        result.declared = (int)Integer(data, 6, 2);
        long position = 8;
        for (int number = 1; number <= result.declared; number++) {
            Entry e = new Entry();
            e.number = number;
            e.offset = position;
            result.entries.Add(e);
            if (position >= data.Length || position + 15 + data[(int)position] > data.Length) {
                e.status = "truncated";
                e.headerTruncated = true;
                result.stopped = true;
                break;
            }
            int pos = (int)position, m = data[pos];
            StringBuilder name = new StringBuilder();
            for (int i = 0; i < m; i++)
                name.Append((char)data[pos + 1 + i]);
            e.name = name.ToString();
            int cursor = pos + 1 + m;
            e.method = data[cursor++];
            e.original = Integer(data, cursor, 4);
            cursor += 4;
            e.compressed = Integer(data, cursor, 4);
            cursor += 4;
            e.stored = Integer(data, cursor, 4);
            cursor += 4;
            int sum = 0;
            for (int i = pos; i < cursor; i++)
                sum += data[i];
            e.start = cursor + 1;
            long next = e.start + e.compressed;
            if (sum % 256 != data[cursor] || !e.name.Matches("[a-z0-9._-]{1,32}")) {
                e.status = "bad_header";
                position = next;
                if (position > data.Length) {
                    result.stopped = true;
                    break;
                }
                continue;
            }
            e.valid = true;
            if (next > data.Length) {
                e.status = "truncated";
                result.stopped = true;
                break;
            }
            if (e.method >= 5)
                e.status = "unsupported";
            else {
                try {
                    e.data = Decode(e.method, data[(int)e.start..(int)next], e.original, result.b, result.k);
                    e.computed = Adler(e.data);
                    if (e.computed == e.stored)
                        e.status = "ok";
                    else {
                        Repair repaired = TryRepair(e.data, e.stored, e.computed);
                        if (repaired == null) {
                            e.status = "checksum";
                            e.detail = " stored " + Hex(e.stored, 8) + " computed " + Hex(e.computed, 8);
                        } else {
                            e.status = "repaired";
                            e.detail = " byte " + repaired.position + " from " + repaired.before + " to " +
                                       repaired.after;
                        }
                    }
                } catch (BitIo.DecodeError error) {
                    e.status = "error";
                    e.detail = " " + error.kind + " at " + error.position;
                }
            }
            position = next;
        }
        result.trailing = result.stopped ? 0 : data.Length - (int)position;
        return result;
    }
    public static int Verify(Parsed parsed, List<Item> items) {
        int count = 0;
        for (int i = 0; i < parsed.entries.Count; i++) {
            Entry e = parsed.entries[i];
            if (e.status.Equals("ok") && Enumerable.SequenceEqual(e.data, items[i].data))
                count++;
        }
        return count;
    }
    public static string Hex(long value, int width) {
        string text = value.ToString("x", CultureInfo.InvariantCulture);
        return "0".Repeat(Math.Max(0, width - text.Length)) + text;
    }
    public static List<string> Hexadecimal(int[] data) {
        List<string> lines = new();
        for (int start = 0; start < data.Length; start += 32) {
            StringBuilder line = new StringBuilder();
            for (int i = start; i < Math.Min(data.Length, start + 32); i++)
                line.Append(Hex(data[i], 2));
            lines.Add(line.ToString());
        }
        return lines;
    }
    public static string Ratio(long compressed, long original) {
        return original == 0 ? "-" : Convert.ToString(1000 * compressed / original);
    }
    public static string Method(int number) {
        return number < 5 ? METHODS[number] : "#" + number;
    }
    public static string Integers(int[] data) {
        List<string> values = new();
        foreach (int value in data)
            values.Add(Convert.ToString(value));
        return string.Join(" ", values);
    }
    public static List<string> TextLines(int[] data) {
        if (data.Length == 0)
            return new();
        StringBuilder text = new StringBuilder();
        foreach (int value in data)
            text.Append((char)value);
        string[] lines = text.ToString().Substring(0, text.Length - 1).Split('\n');
        return lines.ToList();
    }
    public static void Write(string name, List<string> lines) {
        string text = lines.Count == 0 ? "" : string.Join("\n", lines) + "\n";
        File.WriteAllText(Path.Combine("output", name), text, Encoding.ASCII);
    }
    public static void Creation(List<Item> items, int[] created, int b, int k, int m) {
        List<string> sizes = new(["params offset_bits " + b + " length_bits " + k + " window " + (1 << b) +
                                  " lookahead " + ((1 << k) + 2) + " max_code_length " + m]),
                     analysis = new();
        long original = 0, bestTotal = 0;
        long[] totals = new long[5];
        int[] chosen = new int[5];
        foreach (Item item in items) {
            int n = item.data.Length;
            Encoded e = item.encoded;
            string line = "file " + item.name + " original " + n;
            original += n;
            for (int i = 0; i < 5; i++) {
                int size = e.payloads[i].Length;
                totals[i] += size;
                line += " " + METHODS[i] + " " + size + " " + Ratio(size, n);
            }
            line += " best " + METHODS[e.best];
            sizes.Add(line);
            bestTotal += e.payloads[e.best].Length;
            chosen[e.best]++;
            Lzw.Statistics l = e.lzw;
            analysis.Add("lzw " + item.name + " codes " + l.codes + " clears " + l.clears + " widths " +
                         Integers(l.widths) + " longest " + l.longest);
            int literals = 0, matches = 0, matched = 0, longest = 0, farthest = 0;
            foreach (Lz77.Token token in e.tokens)
                if (token.literal >= 0)
                    literals++;
                else {
                    matches++;
                    matched += token.length;
                    longest = Math.Max(longest, token.length);
                    farthest = Math.Max(farthest, token.distance);
                }
            analysis.Add("lz77 " + item.name + " tokens " + e.tokens.Count + " literals " + literals +
                         " matches " + matches + " matched " + matched + " longest " + longest +
                         " farthest " + farthest);
            Lzh h = e.lzh;
            analysis.Add("lzh " + item.name + " mode " + (h.dynamicWriter ? "dynamic" : "fixed") +
                         " fixed_bits " + h.fixedBits + " table_bits " + h.tableBits + " code_bits " +
                         h.codeBits + " halvings " + h.halvings + " litlen_used " + h.litUsed +
                         " litlen_max " + h.litMax + " offset_used " + h.offsetUsed + " offset_max " +
                         h.offsetMax);
            analysis.Add("slots " + item.name + " " + Integers(h.slots));
            analysis.Add("arith " + item.name + " bits " + e.arith.bits + " contexts " + e.arith.contexts +
                         " rescales " + e.arith.rescales);
        }
        string aggregateLine = "total original " + original;
        for (int i = 0; i < 5; i++)
            aggregateLine += " " + METHODS[i] + " " + totals[i] + " " + Ratio(totals[i], original);
        sizes.Add(aggregateLine + " best " + bestTotal + " " + Ratio(bestTotal, original));
        aggregateLine = "chosen";
        for (int i = 0; i < 5; i++)
            aggregateLine += " " + METHODS[i] + " " + chosen[i];
        sizes.Add(aggregateLine);
        sizes.Add("archive bytes " + created.Length + " entries " + items.Count + " ratio " +
                  Ratio(created.Length, original));
        Parsed parsed = Parse(created);
        sizes.Add("verify entries " + parsed.entries.Count + " ok " + Verify(parsed, items));
        Write("sizes.txt", sizes);
        Write("analysis.txt", analysis);
        Write("archive.hex", Hexadecimal(created));
    }
    public static List<string> Listing(Parsed p) {
        if (p.error != null)
            return new(["archive bytes " + p.length + " error " + p.error]);
        List<string> output = new(["archive bytes " + p.length + " offset_bits " + p.b + " length_bits " +
                                   p.k + " entries " + p.declared]);
        long[][] totals = Enumerable.Range(0, 5)
                              .Select(
                                  _ => new long[3])
                              .ToArray();
        int valid = 0;
        foreach (Entry e in p.entries) {
            string line = "entry " + e.number + " offset " + e.offset;
            if (!e.valid) {
                output.Add(line + (e.headerTruncated ? " truncated header" : " bad_header"));
                continue;
            }
            valid++;
            output.Add(line + " method " + Method(e.method) + " original " + e.original + " compressed " +
                       e.compressed + " ratio " + Ratio(e.compressed, e.original) + " adler " +
                       Hex(e.stored, 8) + " name " + e.name);
            if (e.method < 5) {
                totals[e.method][0]++;
                totals[e.method][1] += e.original;
                totals[e.method][2] += e.compressed;
            }
        }
        for (int i = 0; i < 5; i++)
            output.Add("method " + METHODS[i] + " entries " + totals[i][0] + " original " + totals[i][1] +
                       " compressed " + totals[i][2] + " ratio " + Ratio(totals[i][2], totals[i][1]));
        output.Add("end listed " + valid + " of " + p.declared + " stop " +
                   (p.stopped ? "truncated" : "complete") + " trailing " + p.trailing);
        return output;
    }
    public static List<string> TestReport(Parsed p) {
        List<string> output = new();
        if (p.error != null) {
            output.Add("archive error " + p.error);
            return output;
        }
        Dictionary<string, int> counts = new();
        foreach (Entry e in p.entries) {
            counts[e.status] = counts.GetValueOrDefault(e.status, 0) + 1;
            string line = "entry " + e.number + " offset " + e.offset;
            if (!e.valid)
                line += " status " + (e.headerTruncated ? "truncated header" : "bad_header");
            else {
                line += " name " + e.name + " method " + Method(e.method) + " status " + e.status;
                if (e.status.Equals("truncated"))
                    line += " payload have " + (p.length - e.start) + " need " + e.compressed;
                else
                    line += e.detail;
            }
            output.Add(line);
        }
        string summaryLine = "summary entries " + p.declared + " checked " + p.entries.Count;
        foreach (string status in STATUSES)
            summaryLine += " " + status + " " + counts.GetValueOrDefault(status, 0);
        output.Add(summaryLine + " missing " + (p.declared - p.entries.Count) + " trailing " + p.trailing);
        return output;
    }
    public static void Compare(string name, List<string> old, List<string> fresh, List<string> output) {
        if (old.SequenceEqual(fresh)) {
            output.Add("same " + name + " lines " + old.Count);
            return;
        }
        int first = 0;
        while (first < Math.Min(old.Count, fresh.Count) && old[first].Equals(fresh[first]))
            first++;
        int a = old.Count, b = fresh.Count;
        int[][] lcs = Enumerable.Range(0, a + 1)
                          .Select(
                              _ => new int[b + 1])
                          .ToArray();
        for (int oldIndex = a - 1; oldIndex >= 0; oldIndex--)
            for (int newIndex = b - 1; newIndex >= 0; newIndex--)
                lcs[oldIndex][newIndex] =
                    old[oldIndex].Equals(fresh[newIndex])
                        ? lcs[oldIndex + 1][newIndex + 1] + 1
                        : Math.Max(lcs[oldIndex + 1][newIndex], lcs[oldIndex][newIndex + 1]);
        int i = 0, j = 0, removed = 0, added = 0;
        List<string> edits = new();
        while (i < a || j < b) {
            if (i < a && j < b && old[i].Equals(fresh[j])) {
                i++;
                j++;
            } else if (j == b || (i < a && lcs[i + 1][j] >= lcs[i][j + 1])) {
                edits.Add("-" + (i + 1) + ":" + old[i]);
                removed++;
                i++;
            } else {
                edits.Add("+" + (j + 1) + ":" + fresh[j]);
                added++;
                j++;
            }
        }
        output.Add("differs " + name + " first_line " + (first + 1) + " archive_lines " + a +
                   " manifest_lines " + b + " removed " + removed + " added " + added);
        output.AddRange(edits);
    }
    public static void Salvage(Parsed parsed, Dictionary<string, int[]> originals, int manifestB,
                               int manifestK, int maximum) {
        List<Item> salvaged = new();
        List<string> extracted = new(), comparison = new(), report = TestReport(parsed);
        HashSet<string> present = new();
        int b = parsed.error == null ? parsed.b : manifestB, k = parsed.error == null ? parsed.k : manifestK;
        long total = 0;
        foreach (Entry e in parsed.entries)
            if (e.status.Equals("ok") || e.status.Equals("repaired")) {
                present.Add(e.name);
                List<string> lines = TextLines(e.data);
                int words = 0, longest = 0;
                foreach (string line in lines) {
                    longest = Math.Max(longest, line.Length);
                    for (int i = 0; i < line.Length; i++)
                        if (line[i] != ' ' && (i == 0 || line[i - 1] == ' '))
                            words++;
                }
                extracted.Add("file " + e.name + " bytes " + e.data.Length + " lines " + lines.Count +
                              " words " + words + " longest " + longest);
                extracted.AddRange(lines);
                if (!originals.ContainsKey(e.name))
                    comparison.Add("archive_only " + e.name);
                else
                    Compare(e.name, lines, TextLines(originals[e.name]), comparison);
                Encoded encoded = Encode(e.data, b, k, maximum);
                salvaged.Add(new Item(e.name, e.data, encoded));
                total += e.data.Length;
                report.Add("salvage " + e.name + " method " + Method(encoded.best) + " compressed " +
                           encoded.payloads[encoded.best].Length + " was " + Method(e.method) + " " +
                           e.compressed);
            }
        foreach (string name in manifestNames)
            if (!present.Contains(name))
                comparison.Add("new " + name);
        int[] archive = Archive(salvaged, b, k);
        report.Add("salvaged entries " + salvaged.Count + " bytes " + archive.Length + " original " + total +
                   " verified " + Verify(Parse(archive), salvaged));
        Write("test_report.txt", report);
        Write("extracted.txt", extracted);
        Write("compare.txt", comparison);
        Write("salvaged.hex", Hexadecimal(archive));
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        List<string> manifest =
            File.ReadAllLines(Path.Combine("input/manifest.txt"), Encoding.ASCII).ToList();
        int b = int.Parse(manifest[0].Split(' ')[1]), k = int.Parse(manifest[1].Split(' ')[1]),
            m = int.Parse(manifest[2].Split(' ')[1]);
        Dictionary<string, int[]> originals = new(StringComparer.Ordinal);
        List<Item> items = new();
        for (int i = 3; i < manifest.Count; i++) {
            string name = manifest[i].Split(' ')[1];
            byte[] bytes = File.ReadAllBytes(Path.Combine("input/files", name));
            int[] data = new int[bytes.Length];
            for (int j = 0; j < data.Length; j++)
                data[j] = bytes[j] & 255;
            originals[name] = data;
            manifestNames.Add(name);
            items.Add(new Item(name, data, Encode(data, b, k, m)));
        }
        Directory.CreateDirectory(Path.Combine("output"));
        Creation(items, Archive(items, b, k), b, k, m);
        string hex =
            string.Join("", File.ReadAllLines(Path.Combine("input/archive.hex"), Encoding.ASCII).ToList());
        int[] given = new int[hex.Length / 2];
        for (int i = 0; i < given.Length; i++)
            given[i] = Convert.ToInt32(hex.Substring(2 * i, (2 * i + 2) - (2 * i)), 16);
        Parsed parsed = Parse(given);
        Write("listing.txt", Listing(parsed));
        Salvage(parsed, originals, b, k, m);
    }
}
