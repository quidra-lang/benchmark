import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public final class Main {
    static final List<String> METHODS = List.of("STORE", "LZW", "LZ77", "LZH", "ARITH"),
                              STATUSES = List.of("ok", "repaired", "checksum", "error", "unsupported",
                                                 "truncated", "bad_header");
    static final class Lzh {
        int[] payload;
        boolean dynamic;
        int fixedBits, tableBits, codeBits, halvings, litUsed, litMax, offsetUsed, offsetMax;
        int[] slots;
    }
    static int[] fixed(int count) {
        int width = BitIo.bits(count - 1), shorter = (1 << width) - count;
        int[] result = new int[count];
        for (int i = 0; i < count; i++)
            result[i] = i < shorter ? width - 1 : width;
        return result;
    }
    static void writeTable(BitIo.Writer writer, int[] lengths) {
        int s = 0;
        while (s < lengths.length) {
            if (lengths[s] > 0) {
                writer.write(lengths[s], 4);
                s++;
            } else {
                int count = 1;
                while (count < 256 && s + count < lengths.length && lengths[s + count] == 0)
                    count++;
                writer.write(0, 4);
                writer.write(count - 1, 8);
                s += count;
            }
        }
    }
    static int[] readTable(BitIo.Reader reader, int count, int position) {
        int[] lengths = new int[count];
        int s = 0;
        while (s < count) {
            int value = reader.read(4, position);
            if (value > 0)
                lengths[s++] = value;
            else {
                int run = reader.read(8, position) + 1;
                if (s + run > count)
                    throw new BitIo.DecodeError("bad_table", position);
                s += run;
            }
        }
        int used = 0, only = 0, sum = 0;
        for (int value : lengths)
            if (value > 0) {
                used++;
                only = value;
                sum += 1 << (15 - value);
            }
        if ((used == 1 && only != 1) || (used >= 2 && sum != (1 << 15)))
            throw new BitIo.DecodeError("bad_table", position);
        return lengths;
    }
    static void symbol(BitIo.Writer writer, int symbol, int[] lengths, int[] codes) {
        writer.write(codes[symbol], lengths[symbol]);
    }
    static int readSymbol(BitIo.Reader reader, int[] lengths, int[] codes, int position) {
        int maximum = 0;
        for (int length : lengths)
            maximum = Math.max(maximum, length);
        if (maximum == 0)
            throw new BitIo.DecodeError("bad_code", position);
        int code = 0;
        for (int width = 1; width <= maximum; width++) {
            code = (code << 1) | reader.read(1, position);
            for (int s = 0; s < lengths.length; s++)
                if (lengths[s] == width && codes[s] == code)
                    return s;
        }
        throw new BitIo.DecodeError("bad_code", position);
    }
    static void tokens(BitIo.Writer writer, List<Lz77.Token> tokens, int[] p, int[] q) {
        int[] pc = Huffman.canonical(p), qc = Huffman.canonical(q);
        for (Lz77.Token t : tokens) {
            if (t.literal() >= 0)
                symbol(writer, t.literal(), p, pc);
            else {
                symbol(writer, 256 + t.length() - 3, p, pc);
                int u = t.distance() - 1, slot = BitIo.bits(u);
                symbol(writer, slot, q, qc);
                if (slot >= 2)
                    writer.write(u - (1 << (slot - 1)), slot - 1);
            }
        }
    }
    static Lzh lzh(List<Lz77.Token> tokens, int b, int k, int maximum) {
        int[] pFrequency = new int[256 + (1 << k)], qFrequency = new int[b + 1];
        for (Lz77.Token t : tokens) {
            if (t.literal() >= 0)
                pFrequency[t.literal()]++;
            else {
                pFrequency[256 + t.length() - 3]++;
                qFrequency[BitIo.bits(t.distance() - 1)]++;
            }
        }
        Huffman.Limited p = Huffman.limited(pFrequency, maximum), q = Huffman.limited(qFrequency, maximum);
        Lzh result = new Lzh();
        result.slots = qFrequency;
        result.halvings = p.halvings() + q.halvings();
        for (int value : p.lengths())
            if (value > 0) {
                result.litUsed++;
                result.litMax = Math.max(result.litMax, value);
            }
        for (int value : q.lengths())
            if (value > 0) {
                result.offsetUsed++;
                result.offsetMax = Math.max(result.offsetMax, value);
            }
        int[] fp = fixed(pFrequency.length), fq = fixed(qFrequency.length);
        BitIo.Writer fixed = new BitIo.Writer();
        tokens(fixed, tokens, fp, fq);
        result.fixedBits = fixed.count;
        BitIo.Writer tables = new BitIo.Writer();
        writeTable(tables, p.lengths());
        writeTable(tables, q.lengths());
        result.tableBits = tables.count;
        BitIo.Writer dynamic = new BitIo.Writer();
        tokens(dynamic, tokens, p.lengths(), q.lengths());
        result.codeBits = dynamic.count;
        result.dynamic = result.fixedBits > result.tableBits + result.codeBits;
        BitIo.Writer writer = new BitIo.Writer();
        writer.write(result.dynamic ? 1 : 0, 1);
        if (result.dynamic) {
            writeTable(writer, p.lengths());
            writeTable(writer, q.lengths());
            tokens(writer, tokens, p.lengths(), q.lengths());
        } else
            tokens(writer, tokens, fp, fq);
        result.payload = writer.finish();
        return result;
    }
    static int[] lz77(List<Lz77.Token> tokens, int b, int k) {
        BitIo.Writer writer = new BitIo.Writer();
        for (Lz77.Token t : tokens)
            if (t.literal() >= 0) {
                writer.write(0, 1);
                writer.write(t.literal(), 8);
            } else {
                writer.write(1, 1);
                writer.write(t.distance() - 1, b);
                writer.write(t.length() - 3, k);
            }
        return writer.finish();
    }
    static int[] decode(int method, int[] payload, long size, int b, int k) {
        if (method == 1)
            return Lzw.decode(payload, size);
        if (method == 4)
            return ArithCoder.decode(payload, size);
        List<Integer> output = new ArrayList<>();
        if (method == 0) {
            for (int value : payload) {
                if (output.size() == size)
                    break;
                output.add(value);
            }
            if (output.size() < size)
                throw new BitIo.DecodeError("end_of_data", output.size());
            return BitIo.array(output);
        }
        BitIo.Reader reader = new BitIo.Reader(payload, false);
        int[] p = null, q = null, pc = null, qc = null;
        if (method == 3) {
            if (reader.read(1, 0) == 1) {
                p = readTable(reader, 256 + (1 << k), 0);
                q = readTable(reader, b + 1, 0);
            } else {
                p = fixed(256 + (1 << k));
                q = fixed(b + 1);
            }
            pc = Huffman.canonical(p);
            qc = Huffman.canonical(q);
        }
        while (output.size() < size) {
            if (method == 2) {
                if (reader.read(1, output.size()) == 0)
                    output.add(reader.read(8, output.size()));
                else {
                    int distance = reader.read(b, output.size()) + 1, length =
                                                                          reader.read(k, output.size()) + 3;
                    Lz77.copy(output, distance, length, size);
                }
            } else {
                int t = readSymbol(reader, p, pc, output.size());
                if (t < 256)
                    output.add(t);
                else {
                    int length = t - 253, slot = readSymbol(reader, q, qc, output.size()),
                        u = slot <= 1 ? slot : (1 << (slot - 1)) + reader.read(slot - 1, output.size());
                    Lz77.copy(output, u + 1, length, size);
                }
            }
        }
        return BitIo.array(output);
    }
    static final class Encoded {
        int[][] payloads;
        int best;
        Lzw.Statistics lzw;
        List<Lz77.Token> tokens;
        Lzh lzh;
        ArithCoder.Encoded arith;
    }
    static Encoded encode(int[] data, int b, int k, int m) {
        Encoded result = new Encoded();
        result.tokens = Lz77.split(data, b, k);
        Lzw.Encoded lzw = Lzw.encode(data);
        result.lzw = lzw.stats();
        result.lzh = lzh(result.tokens, b, k, m);
        result.arith = ArithCoder.encode(data);
        result.payloads = new int[][] {data.clone(), lzw.payload(), lz77(result.tokens, b, k),
                                       result.lzh.payload, result.arith.payload()};
        for (int i = 1; i < 5; i++)
            if (result.payloads[i].length < result.payloads[result.best].length)
                result.best = i;
        return result;
    }
    static long adler(int[] data) {
        long s1 = 1, s2 = 0;
        for (int x : data) {
            s1 = (s1 + x) % 65521;
            s2 = (s2 + s1) % 65521;
        }
        return s2 * 65536 + s1;
    }
    static long mod(long value) {
        return Math.floorMod(value, 65521);
    }
    static long power(long value, int exponent) {
        long result = 1;
        while (exponent > 0) {
            if ((exponent & 1) != 0)
                result = result * value % 65521;
            value = value * value % 65521;
            exponent >>>= 1;
        }
        return result;
    }
    record Repair(int position, int before, int after) {}
    static Repair repair(int[] data, long stored, long computed) {
        long a = mod(stored % 65536 - computed % 65536), b = mod(stored / 65536 - computed / 65536);
        int delta;
        if (a >= 1 && a <= 255)
            delta = (int)a;
        else if (a >= 65266 && a <= 65520)
            delta = (int)a - 65521;
        else
            return null;
        long t = b * power(mod(delta), 65519) % 65521;
        if (t < 1 || t > data.length)
            return null;
        int p = data.length - (int)t, before = data[p], after = before + delta;
        if (after < 0 || after > 255)
            return null;
        data[p] = after;
        if (adler(data) == stored)
            return new Repair(p, before, after);
        data[p] = before;
        return null;
    }
    static void integer(List<Integer> output, long value, int width) {
        for (int i = width - 1; i >= 0; i--)
            output.add((int)((value >>> (8 * i)) & 255));
    }
    static long integer(int[] data, int position, int width) {
        long value = 0;
        for (int i = 0; i < width; i++)
            value = value * 256 + data[position + i];
        return value;
    }
    static int[] ascii(String text) {
        int[] data = new int[text.length()];
        for (int i = 0; i < data.length; i++)
            data[i] = text.charAt(i);
        return data;
    }
    record Item(String name, int[] data, Encoded encoded) {}
    static int[] archive(List<Item> items, int b, int k) {
        List<Integer> output = new ArrayList<>();
        for (int value : ascii("TXAR"))
            output.add(value);
        output.add(b);
        output.add(k);
        integer(output, items.size(), 2);
        for (Item item : items) {
            int start = output.size(), method = item.encoded().best;
            output.add(item.name().length());
            for (int value : ascii(item.name()))
                output.add(value);
            output.add(method);
            integer(output, item.data().length, 4);
            int[] payload = item.encoded().payloads[method];
            integer(output, payload.length, 4);
            integer(output, adler(item.data()), 4);
            int sum = 0;
            for (int i = start; i < output.size(); i++)
                sum += output.get(i);
            output.add(sum % 256);
            for (int value : payload)
                output.add(value);
        }
        return BitIo.array(output);
    }
    static final class Entry {
        int number, method;
        long offset, start, original, compressed, stored, computed;
        String name = "", status, detail = "";
        boolean valid, headerTruncated;
        int[] data;
    }
    static final class Parsed {
        String error;
        int length, b, k, declared, trailing;
        boolean stopped;
        List<Entry> entries = new ArrayList<>();
    }
    static Parsed parse(int[] data) {
        Parsed result = new Parsed();
        result.length = data.length;
        if (data.length < 8 || data[0] != 'T' || data[1] != 'X' || data[2] != 'A' || data[3] != 'R') {
            result.error = "bad_magic";
            return result;
        }
        result.b = data[4];
        result.k = data[5];
        if (result.b < 6 || result.b > 12 || result.k < 2 || result.k > 5) {
            result.error = "bad_params";
            return result;
        }
        result.declared = (int)integer(data, 6, 2);
        long position = 8;
        for (int number = 1; number <= result.declared; number++) {
            Entry e = new Entry();
            e.number = number;
            e.offset = position;
            result.entries.add(e);
            if (position >= data.length || position + 15 + data[(int)position] > data.length) {
                e.status = "truncated";
                e.headerTruncated = true;
                result.stopped = true;
                break;
            }
            int pos = (int)position, m = data[pos];
            StringBuilder name = new StringBuilder();
            for (int i = 0; i < m; i++)
                name.append((char)data[pos + 1 + i]);
            e.name = name.toString();
            int cursor = pos + 1 + m;
            e.method = data[cursor++];
            e.original = integer(data, cursor, 4);
            cursor += 4;
            e.compressed = integer(data, cursor, 4);
            cursor += 4;
            e.stored = integer(data, cursor, 4);
            cursor += 4;
            int sum = 0;
            for (int i = pos; i < cursor; i++)
                sum += data[i];
            e.start = cursor + 1;
            long next = e.start + e.compressed;
            if (sum % 256 != data[cursor] || !e.name.matches("[a-z0-9._-]{1,32}")) {
                e.status = "bad_header";
                position = next;
                if (position > data.length) {
                    result.stopped = true;
                    break;
                }
                continue;
            }
            e.valid = true;
            if (next > data.length) {
                e.status = "truncated";
                result.stopped = true;
                break;
            }
            if (e.method >= 5)
                e.status = "unsupported";
            else {
                try {
                    e.data = decode(e.method, Arrays.copyOfRange(data, (int)e.start, (int)next), e.original,
                                    result.b, result.k);
                    e.computed = adler(e.data);
                    if (e.computed == e.stored)
                        e.status = "ok";
                    else {
                        Repair repaired = repair(e.data, e.stored, e.computed);
                        if (repaired == null) {
                            e.status = "checksum";
                            e.detail = " stored " + hex(e.stored, 8) + " computed " + hex(e.computed, 8);
                        } else {
                            e.status = "repaired";
                            e.detail = " byte " + repaired.position() + " from " + repaired.before() +
                                       " to " + repaired.after();
                        }
                    }
                } catch (BitIo.DecodeError error) {
                    e.status = "error";
                    e.detail = " " + error.kind + " at " + error.position;
                }
            }
            position = next;
        }
        result.trailing = result.stopped ? 0 : data.length - (int)position;
        return result;
    }
    static int verify(Parsed parsed, List<Item> items) {
        int count = 0;
        for (int i = 0; i < parsed.entries.size(); i++) {
            Entry e = parsed.entries.get(i);
            if (e.status.equals("ok") && Arrays.equals(e.data, items.get(i).data()))
                count++;
        }
        return count;
    }
    static String hex(long value, int width) {
        String text = Long.toHexString(value);
        return "0".repeat(Math.max(0, width - text.length())) + text;
    }
    static List<String> hexadecimal(int[] data) {
        List<String> lines = new ArrayList<>();
        for (int start = 0; start < data.length; start += 32) {
            StringBuilder line = new StringBuilder();
            for (int i = start; i < Math.min(data.length, start + 32); i++)
                line.append(hex(data[i], 2));
            lines.add(line.toString());
        }
        return lines;
    }
    static String ratio(long compressed, long original) {
        return original == 0 ? "-" : Long.toString(1000 * compressed / original);
    }
    static String method(int number) {
        return number < 5 ? METHODS.get(number) : "#" + number;
    }
    static String integers(int[] data) {
        List<String> values = new ArrayList<>();
        for (int value : data)
            values.add(Integer.toString(value));
        return String.join(" ", values);
    }
    static List<String> textLines(int[] data) {
        if (data.length == 0)
            return new ArrayList<>();
        StringBuilder text = new StringBuilder();
        for (int value : data)
            text.append((char)value);
        String[] lines = text.substring(0, text.length() - 1).split("\n", -1);
        return new ArrayList<>(Arrays.asList(lines));
    }
    static void write(String name, List<String> lines) throws IOException {
        String text = lines.isEmpty() ? "" : String.join("\n", lines) + "\n";
        Files.writeString(Path.of("output", name), text, StandardCharsets.US_ASCII);
    }
    static void creation(List<Item> items, int[] created, int b, int k, int m) throws IOException {
        List<String> sizes = new ArrayList<>(List.of("params offset_bits " + b + " length_bits " + k +
                                                     " window " + (1 << b) + " lookahead " + ((1 << k) + 2) +
                                                     " max_code_length " + m)),
                     analysis = new ArrayList<>();
        long original = 0, bestTotal = 0;
        long[] totals = new long[5];
        int[] chosen = new int[5];
        for (Item item : items) {
            int n = item.data().length;
            Encoded e = item.encoded();
            String line = "file " + item.name() + " original " + n;
            original += n;
            for (int i = 0; i < 5; i++) {
                int size = e.payloads[i].length;
                totals[i] += size;
                line += " " + METHODS.get(i) + " " + size + " " + ratio(size, n);
            }
            line += " best " + METHODS.get(e.best);
            sizes.add(line);
            bestTotal += e.payloads[e.best].length;
            chosen[e.best]++;
            Lzw.Statistics l = e.lzw;
            analysis.add("lzw " + item.name() + " codes " + l.codes + " clears " + l.clears + " widths " +
                         integers(l.widths) + " longest " + l.longest);
            int literals = 0, matches = 0, matched = 0, longest = 0, farthest = 0;
            for (Lz77.Token token : e.tokens)
                if (token.literal() >= 0)
                    literals++;
                else {
                    matches++;
                    matched += token.length();
                    longest = Math.max(longest, token.length());
                    farthest = Math.max(farthest, token.distance());
                }
            analysis.add("lz77 " + item.name() + " tokens " + e.tokens.size() + " literals " + literals +
                         " matches " + matches + " matched " + matched + " longest " + longest +
                         " farthest " + farthest);
            Lzh h = e.lzh;
            analysis.add("lzh " + item.name() + " mode " + (h.dynamic ? "dynamic" : "fixed") +
                         " fixed_bits " + h.fixedBits + " table_bits " + h.tableBits + " code_bits " +
                         h.codeBits + " halvings " + h.halvings + " litlen_used " + h.litUsed +
                         " litlen_max " + h.litMax + " offset_used " + h.offsetUsed + " offset_max " +
                         h.offsetMax);
            analysis.add("slots " + item.name() + " " + integers(h.slots));
            analysis.add("arith " + item.name() + " bits " + e.arith.bits() + " contexts " +
                         e.arith.contexts() + " rescales " + e.arith.rescales());
        }
        String line = "total original " + original;
        for (int i = 0; i < 5; i++)
            line += " " + METHODS.get(i) + " " + totals[i] + " " + ratio(totals[i], original);
        sizes.add(line + " best " + bestTotal + " " + ratio(bestTotal, original));
        line = "chosen";
        for (int i = 0; i < 5; i++)
            line += " " + METHODS.get(i) + " " + chosen[i];
        sizes.add(line);
        sizes.add("archive bytes " + created.length + " entries " + items.size() + " ratio " +
                  ratio(created.length, original));
        Parsed parsed = parse(created);
        sizes.add("verify entries " + parsed.entries.size() + " ok " + verify(parsed, items));
        write("sizes.txt", sizes);
        write("analysis.txt", analysis);
        write("archive.hex", hexadecimal(created));
    }
    static List<String> listing(Parsed p) {
        if (p.error != null)
            return new ArrayList<>(List.of("archive bytes " + p.length + " error " + p.error));
        List<String> output = new ArrayList<>(List.of("archive bytes " + p.length + " offset_bits " + p.b +
                                                      " length_bits " + p.k + " entries " + p.declared));
        long[][] totals = new long[5][3];
        int valid = 0;
        for (Entry e : p.entries) {
            String line = "entry " + e.number + " offset " + e.offset;
            if (!e.valid) {
                output.add(line + (e.headerTruncated ? " truncated header" : " bad_header"));
                continue;
            }
            valid++;
            output.add(line + " method " + method(e.method) + " original " + e.original + " compressed " +
                       e.compressed + " ratio " + ratio(e.compressed, e.original) + " adler " +
                       hex(e.stored, 8) + " name " + e.name);
            if (e.method < 5) {
                totals[e.method][0]++;
                totals[e.method][1] += e.original;
                totals[e.method][2] += e.compressed;
            }
        }
        for (int i = 0; i < 5; i++)
            output.add("method " + METHODS.get(i) + " entries " + totals[i][0] + " original " + totals[i][1] +
                       " compressed " + totals[i][2] + " ratio " + ratio(totals[i][2], totals[i][1]));
        output.add("end listed " + valid + " of " + p.declared + " stop " +
                   (p.stopped ? "truncated" : "complete") + " trailing " + p.trailing);
        return output;
    }
    static List<String> testReport(Parsed p) {
        List<String> output = new ArrayList<>();
        if (p.error != null) {
            output.add("archive error " + p.error);
            return output;
        }
        Map<String, Integer> counts = new HashMap<>();
        for (Entry e : p.entries) {
            counts.put(e.status, counts.getOrDefault(e.status, 0) + 1);
            String line = "entry " + e.number + " offset " + e.offset;
            if (!e.valid)
                line += " status " + (e.headerTruncated ? "truncated header" : "bad_header");
            else {
                line += " name " + e.name + " method " + method(e.method) + " status " + e.status;
                if (e.status.equals("truncated"))
                    line += " payload have " + (p.length - e.start) + " need " + e.compressed;
                else
                    line += e.detail;
            }
            output.add(line);
        }
        String line = "summary entries " + p.declared + " checked " + p.entries.size();
        for (String status : STATUSES)
            line += " " + status + " " + counts.getOrDefault(status, 0);
        output.add(line + " missing " + (p.declared - p.entries.size()) + " trailing " + p.trailing);
        return output;
    }
    static void compare(String name, List<String> old, List<String> fresh, List<String> output) {
        if (old.equals(fresh)) {
            output.add("same " + name + " lines " + old.size());
            return;
        }
        int first = 0;
        while (first < Math.min(old.size(), fresh.size()) && old.get(first).equals(fresh.get(first)))
            first++;
        int a = old.size(), b = fresh.size();
        int[][] lcs = new int[a + 1][b + 1];
        for (int i = a - 1; i >= 0; i--)
            for (int j = b - 1; j >= 0; j--)
                lcs[i][j] = old.get(i).equals(fresh.get(j)) ? lcs[i + 1][j + 1] + 1
                                                            : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
        int i = 0, j = 0, removed = 0, added = 0;
        List<String> edits = new ArrayList<>();
        while (i < a || j < b) {
            if (i < a && j < b && old.get(i).equals(fresh.get(j))) {
                i++;
                j++;
            } else if (j == b || (i < a && lcs[i + 1][j] >= lcs[i][j + 1])) {
                edits.add("-" + (i + 1) + ":" + old.get(i));
                removed++;
                i++;
            } else {
                edits.add("+" + (j + 1) + ":" + fresh.get(j));
                added++;
                j++;
            }
        }
        output.add("differs " + name + " first_line " + (first + 1) + " archive_lines " + a +
                   " manifest_lines " + b + " removed " + removed + " added " + added);
        output.addAll(edits);
    }
    static void salvage(Parsed parsed, Map<String, int[]> originals, int manifestB, int manifestK,
                        int maximum) throws IOException {
        List<Item> salvaged = new ArrayList<>();
        List<String> extracted = new ArrayList<>(), comparison = new ArrayList<>(),
                     report = testReport(parsed);
        Set<String> present = new HashSet<>();
        int b = parsed.error == null ? parsed.b : manifestB, k = parsed.error == null ? parsed.k : manifestK;
        long total = 0;
        for (Entry e : parsed.entries)
            if (e.status.equals("ok") || e.status.equals("repaired")) {
                present.add(e.name);
                List<String> lines = textLines(e.data);
                int words = 0, longest = 0;
                for (String line : lines) {
                    longest = Math.max(longest, line.length());
                    for (int i = 0; i < line.length(); i++)
                        if (line.charAt(i) != ' ' && (i == 0 || line.charAt(i - 1) == ' '))
                            words++;
                }
                extracted.add("file " + e.name + " bytes " + e.data.length + " lines " + lines.size() +
                              " words " + words + " longest " + longest);
                extracted.addAll(lines);
                if (!originals.containsKey(e.name))
                    comparison.add("archive_only " + e.name);
                else
                    compare(e.name, lines, textLines(originals.get(e.name)), comparison);
                Encoded encoded = encode(e.data, b, k, maximum);
                salvaged.add(new Item(e.name, e.data, encoded));
                total += e.data.length;
                report.add("salvage " + e.name + " method " + method(encoded.best) + " compressed " +
                           encoded.payloads[encoded.best].length + " was " + method(e.method) + " " +
                           e.compressed);
            }
        for (String name : originals.keySet())
            if (!present.contains(name))
                comparison.add("new " + name);
        int[] archive = archive(salvaged, b, k);
        report.add("salvaged entries " + salvaged.size() + " bytes " + archive.length + " original " + total +
                   " verified " + verify(parse(archive), salvaged));
        write("test_report.txt", report);
        write("extracted.txt", extracted);
        write("compare.txt", comparison);
        write("salvaged.hex", hexadecimal(archive));
    }
    public static void main(String[] args) throws IOException {
        List<String> manifest = Files.readAllLines(Path.of("input/manifest.txt"), StandardCharsets.US_ASCII);
        int b = Integer.parseInt(manifest.get(0).split(" ")[1]),
            k = Integer.parseInt(manifest.get(1).split(" ")[1]),
            m = Integer.parseInt(manifest.get(2).split(" ")[1]);
        Map<String, int[]> originals = new LinkedHashMap<>();
        List<Item> items = new ArrayList<>();
        for (int i = 3; i < manifest.size(); i++) {
            String name = manifest.get(i).split(" ")[1];
            byte[] bytes = Files.readAllBytes(Path.of("input/files", name));
            int[] data = new int[bytes.length];
            for (int j = 0; j < data.length; j++)
                data[j] = bytes[j] & 255;
            originals.put(name, data);
            items.add(new Item(name, data, encode(data, b, k, m)));
        }
        Files.createDirectories(Path.of("output"));
        creation(items, archive(items, b, k), b, k, m);
        String hex =
            String.join("", Files.readAllLines(Path.of("input/archive.hex"), StandardCharsets.US_ASCII));
        int[] given = new int[hex.length() / 2];
        for (int i = 0; i < given.length; i++)
            given[i] = Integer.parseInt(hex.substring(2 * i, 2 * i + 2), 16);
        Parsed parsed = parse(given);
        write("listing.txt", listing(parsed));
        salvage(parsed, originals, b, k, m);
    }
}
