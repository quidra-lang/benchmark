using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Program {
    public static int[] transform;
    public static int[][] basic;
    public static Entropy.Table[][] standard;
    public static ImageIo.Parameters settings;
    public static ImageIo.Image original;
    public static ImageIo.Plane[] originalPlanes;
    public static int quality, restart;
    public static string sampling, mode;
    public static readonly string[] COMPONENT_NAMES = { "Y", "Cb", "Cr" };
    public sealed class Component {
        public int identifier, h, v, tq, td, ta;
        public Component(int identifier, int h, int v, int tq, int td, int ta) {
            this.identifier = identifier;
            this.h = h;
            this.v = v;
            this.tq = tq;
            this.td = td;
            this.ta = ta;
        }
    }
    public record Block(int mcu, int component, int bx, int by) {}
    public record Interval(int first, int count) {}
    public record EncodedInterval(int first, int count, int position, int length) {}
    public record Segment(int position, string name, int length) {}
    public record Symbol(int tableClass, int tableId, int value, int extra, int width) {}
    public sealed class Frame {
        public int width, height, hmax = 1, vmax = 1, mx, my, mcus, blocksPerMcu, restart;
        public Component[] components;
        public int[][] factors = Enumerable.Range(0, 3)
                                     .Select(
                                         _ => new int[2])
                                     .ToArray();
        public List<Block> blocks = new();
        public List<Interval> intervals = new();
        public Frame(int w, int h, Component[] components, int restart) {
            width = w;
            height = h;
            this.components = components;
            this.restart = restart;
            for (int k = 0; k < 3; k++) {
                Component c = components[k];
                hmax = Math.Max(hmax, c.h);
                vmax = Math.Max(vmax, c.v);
                factors[k] = new int[] { c.h, c.v };
                blocksPerMcu += c.h * c.v;
            }
            mx = (w + 8 * hmax - 1) / (8 * hmax);
            my = (h + 8 * vmax - 1) / (8 * vmax);
            mcus = mx * my;
            for (int mcu = 0; mcu < mcus; mcu++)
                for (int k = 0; k < 3; k++)
                    for (int v = 0; v < components[k].v; v++)
                        for (int x = 0; x < components[k].h; x++)
                            blocks.Add(new Block(mcu, k, components[k].h * (mcu % mx) + x,
                                                 components[k].v * (mcu / mx) + v));
            int step = restart == 0 ? mcus : restart;
            for (int first = 0; first < mcus; first += step)
                intervals.Add(new Interval(first, Math.Min(step, mcus - first)));
        }
    }
    public record Prepared(Frame frame, ImageIo.Plane[] planes, int[][] quant,
                           int[][] coefficients) {}
    public sealed class Encoding {
        public Prepared prepared;
        public Entropy.Table[][] tables;
        public int[][][] frequencies;
        public int[] differences, blockBits, data;
        public int headerBytes, scanBytes, paddingBits, stuffedBytes;
        public List<EncodedInterval> intervals = new();
    }
    public sealed class Decoded {
        public Frame frame;
        public int[][] quant = new int [4][];
        public Entropy.Table[][] tables = Enumerable.Range(0, 2)
                                              .Select(
                                                  _ => new Entropy.Table[16])
                                              .ToArray();
        public List<Segment> segments = new();
        public int scanStart, scanBytes;
        public int[][] coefficients;
        public string[] states;
        public ImageIo.Plane[] planes, expanded;
        public ImageIo.Image image;
    }
    public record Key(int quality, string sampling, string mode) {}
    public static readonly Dictionary<Key, Encoding> encodings = new();
    public static readonly Dictionary<Key, Decoded> decodings = new();
    public static Component[] Components(int h, int v) {
        return new Component[] { new Component(1, h, v, 0, 0, 0), new Component(2, 1, 1, 1, 1, 1),
                                 new Component(3, 1, 1, 1, 1, 1) };
    }
    public static int[] ToArray(List<int> values) {
        int[] result = new int[values.Count];
        for (int i = 0; i < result.Length; i++)
            result[i] = values[i];
        return result;
    }
    public static void Append(List<int> output, params int[] values) {
        foreach (int v in values)
            output.Add(v);
    }
    public static void Word(List<int> output, int v) { Append(output, v / 256, v % 256); }
    public static int WordAt(int[] data, int p) { return 256 * data[p] + data[p + 1]; }
    public static void AppendSegment(List<int> output, int marker, List<int> contents) {
        Append(output, 255, marker);
        Word(output, contents.Count + 2);
        output.AddRange(contents);
    }
    public static Prepared Prepare(ImageIo.Image image, int q, string sampling, int restart) {
        int hs = sampling.Equals("444") ? 1 : 2, vs = sampling.Equals("420") ? 2 : 1;
        Frame f = new Frame(image.width, image.height, Components(hs, vs), restart);
        ImageIo.Plane[] planes = Color.Components(Color.Split(image), f.factors, f.mx, f.my);
        int[][] quant = Dct.Tables(basic, q), coefficients = Enumerable.Range(0, f.blocks.Count)
                                                                 .Select(
                                                                     _ => new int[64])
                                                                 .ToArray();
        for (int n = 0; n < f.blocks.Count; n++) {
            Block block = f.blocks[n];
            ImageIo.Plane plane = planes[block.component];
            int[] pixels = new int[64];
            for (int y = 0; y < 8; y++)
                for (int x = 0; x < 8; x++)
                    pixels[8 * y + x] =
                        plane.pixels[(8 * block.by + y) * plane.width + 8 * block.bx + x];
            coefficients[n] = Dct.Zigzag(Dct.Quantize(Dct.Forward(pixels, transform),
                                                      quant[f.components[block.component].tq]));
        }
        return new Prepared(f, planes, quant, coefficients);
    }
    public static int[] Header(Frame f, int[][] quant, Entropy.Table[][] tables) {
        List<int> output = new();
        Append(output, 255, 216);
        List<int> contents = new();
        for (int t = 0; t < 2; t++) {
            contents.Add(t);
            Append(contents, Dct.Zigzag(quant[t]));
        }
        AppendSegment(output, 219, contents);
        contents = new();
        contents.Add(8);
        Word(contents, f.height);
        Word(contents, f.width);
        contents.Add(3);
        foreach (Component c in f.components)
            Append(contents, c.identifier, 16 * c.h + c.v, c.tq);
        AppendSegment(output, 192, contents);
        contents = new();
        for (int t = 0; t < 4; t++) {
            int c = Entropy.CLASSES[t], id = Entropy.IDS[t];
            Entropy.Table table = tables[c][id];
            contents.Add(16 * c + id);
            Append(contents, table.counts);
            Append(contents, table.symbols);
        }
        AppendSegment(output, 196, contents);
        if (f.restart > 0) {
            contents = new();
            Word(contents, f.restart);
            AppendSegment(output, 221, contents);
        }
        contents = new();
        contents.Add(3);
        foreach (Component c in f.components)
            Append(contents, c.identifier, 16 * c.td + c.ta);
        Append(contents, 0, 63, 0);
        AppendSegment(output, 218, contents);
        return ToArray(output);
    }
    public static Encoding EncodePrepared(Prepared prepared, string mode) {
        Encoding result = new Encoding();
        result.prepared = prepared;
        Frame f = prepared.frame;
        result.frequencies =
            Enumerable.Range(0, 2)
                .Select(c => Enumerable.Range(0, 4).Select(t => new int[256]).ToArray())
                .ToArray();
        result.differences = new int[f.blocks.Count];
        result.blockBits = new int[f.blocks.Count];
        List<List<Symbol>> allSymbols = new();
        foreach (Interval interval in f.intervals) {
            int[] predictors = new int[3];
            for (int n = interval.first * f.blocksPerMcu;
                 n < (interval.first + interval.count) * f.blocksPerMcu; n++) {
                Block block = f.blocks[n];
                Component c = f.components[block.component];
                int[] z = prepared.coefficients[n];
                int difference = z[0] - predictors[block.component];
                predictors[block.component] = z[0];
                result.differences[n] = difference;
                int category = Entropy.Category(difference);
                List<Symbol> symbols = new();
                symbols.Add(new Symbol(0, c.td, category, Entropy.Extra(difference), category));
                int run = 0;
                for (int i = 1; i < 64; i++) {
                    int value = z[i];
                    if (value == 0) {
                        run++;
                        continue;
                    }
                    while (run >= 16) {
                        symbols.Add(new Symbol(1, c.ta, 240, 0, 0));
                        run -= 16;
                    }
                    category = Entropy.Category(value);
                    symbols.Add(
                        new Symbol(1, c.ta, 16 * run + category, Entropy.Extra(value), category));
                    run = 0;
                }
                if (run > 0)
                    symbols.Add(new Symbol(1, c.ta, 0, 0, 0));
                foreach (Symbol symbol in symbols)
                    result.frequencies[symbol.tableClass][symbol.tableId][symbol.value]++;
                allSymbols.Add(symbols);
            }
        }
        result.tables = standard;
        if (mode.Equals("optimized")) {
            result.tables = Enumerable.Range(0, 2)
                                .Select(
                                    _ => new Entropy.Table[16])
                                .ToArray();
            for (int t = 0; t < 4; t++) {
                int c = Entropy.CLASSES[t], id = Entropy.IDS[t];
                result.tables[c][id] = Entropy.Optimized(result.frequencies[c][id]);
            }
        }
        int[] header = Header(f, prepared.quant, result.tables);
        Bitstream.Writer writer = new Bitstream.Writer();
        for (int j = 0; j < f.intervals.Count; j++) {
            Interval interval = f.intervals[j];
            if (j > 0)
                writer.Restart(j - 1);
            int start = writer.data.Count;
            for (int n = interval.first * f.blocksPerMcu;
                 n < (interval.first + interval.count) * f.blocksPerMcu; n++)
                foreach (Symbol symbol in allSymbols[n]) {
                    Entropy.Table table = result.tables[symbol.tableClass][symbol.tableId];
                    int length = table.lengths[symbol.value];
                    writer.Write(table.codes[symbol.value], length);
                    writer.Write(symbol.extra, symbol.width);
                    result.blockBits[n] += length + symbol.width;
                }
            writer.Pad();
            result.intervals.Add(new EncodedInterval(
                interval.first, interval.count, header.Length + start, writer.data.Count - start));
        }
        List<int> data = new();
        Append(data, header);
        data.AddRange(writer.data);
        Append(data, 255, 217);
        result.data = ToArray(data);
        result.headerBytes = header.Length;
        result.scanBytes = writer.data.Count;
        result.paddingBits = writer.paddingBits;
        result.stuffedBytes = writer.stuffedBytes;
        return result;
    }
    public static Encoding Encode(ImageIo.Image image, int q, string sampling, string mode,
                                  int restart) {
        return EncodePrepared(Prepare(image, q, sampling, restart), mode);
    }
    public static string SegmentName(int marker) {
        if (marker >= 224 && marker <= 239)
            return "APP" + (marker - 224);
        return marker switch {
            192 => "SOF0",
            196 => "DHT",
            219 => "DQT",
            221 => "DRI",
            218 => "SOS",
            _ => "COM"
        };
    }
    public static Decoded Parse(int[] data) {
        Decoded d = new Decoded();
        int position = 2, width = 0, height = 0, restart = 0;
        Component[] components = new Component[3];
        d.segments.Add(new Segment(0, "SOI", 0));
        while (true) {
            int marker = data[position + 1], length = WordAt(data, position + 2);
            int[] contents = data[(position + 4)..(position + length + 2)];
            d.segments.Add(new Segment(position, SegmentName(marker), length));
            position += length + 2;
            if (marker == 219) {
                for (int offset = 0; offset < contents.Length; offset += 65)
                    d.quant[contents[offset]] = Dct.Unzigzag(contents[(offset + 1)..(offset + 65)]);
            } else if (marker == 196) {
                int offset = 0;
                while (offset < contents.Length) {
                    int c = contents[offset] / 16, id = contents[offset] % 16;
                    int[] counts = contents[(offset + 1)..(offset + 17)];
                    int count = 0;
                    foreach (int value in counts)
                        count += value;
                    d.tables[c][id] =
                        new Entropy.Table(counts, contents[(offset + 17)..(offset + 17 + count)]);
                    offset += 17 + count;
                }
            } else if (marker == 192) {
                height = WordAt(contents, 1);
                width = WordAt(contents, 3);
                for (int k = 0; k < 3; k++) {
                    int offset = 6 + 3 * k, factor = contents[offset + 1];
                    components[k] = new Component(contents[offset], factor / 16, factor % 16,
                                                  contents[offset + 2], 0, 0);
                }
            } else if (marker == 221)
                restart = WordAt(contents, 0);
            else if (marker == 218) {
                for (int k = 0; k < 3; k++) {
                    int table = contents[2 + 2 * k];
                    components[k].td = table / 16;
                    components[k].ta = table % 16;
                }
                break;
            }
        }
        d.frame = new Frame(width, height, components, restart);
        d.scanStart = position;
        d.scanBytes = data.Length - 2 - position;
        d.segments.Add(new Segment(data.Length - 2, "EOI", 0));
        return d;
    }
    public static int ReadSymbol(Bitstream.Reader reader, Entropy.Table table) {
        int code = 0;
        for (int length = 1; length <= 16; length++) {
            code = 2 * code + reader.Bit();
            if (table.decode.TryGetValue((length << 16) | code, out int symbol))
                return symbol;
        }
        throw new Bitstream.DecodeError("code");
    }
    public static int[] DecodeBlock(Bitstream.Reader reader, int k, Component c,
                                    Entropy.Table[][] tables, int[] predictors) {
        int[] z = new int[64];
        int n = ReadSymbol(reader, tables[0][c.td]);
        predictors[k] += Entropy.Amplitude(reader.Read(n), n);
        z[0] = predictors[k];
        int index = 1;
        while (index <= 63) {
            int symbol = ReadSymbol(reader, tables[1][c.ta]);
            if (symbol == 0)
                break;
            int run = symbol / 16;
            n = symbol % 16;
            index += run;
            if (index > 63)
                throw new Bitstream.DecodeError("index");
            if (n > 0)
                z[index] = Entropy.Amplitude(reader.Read(n), n);
            index++;
        }
        return z;
    }
    public static ImageIo.Plane Reconstruct(Frame f, int k, int[][] coefficients, int[][] quant,
                                            int keep) {
        Component c = f.components[k];
        int w = 8 * c.h * f.mx, h = 8 * c.v * f.my;
        int[] plane = new int[w * h];
        Array.Fill(plane, 128);
        for (int n = 0; n < f.blocks.Count; n++) {
            Block b = f.blocks[n];
            if (b.component != k)
                continue;
            int[] pixels =
                Dct.Inverse(Dct.Dequantize(coefficients[n], quant[c.tq], keep), transform);
            for (int y = 0; y < 8; y++)
                Array.Copy(pixels, 8 * y, plane, (8 * b.by + y) * w + 8 * b.bx, 8);
        }
        return new ImageIo.Plane(w, h, plane);
    }
    public static Decoded Decode(int[] data) {
        Decoded d = Parse(data);
        Frame f = d.frame;
        d.coefficients = Enumerable.Range(0, f.blocks.Count)
                             .Select(
                                 _ => new int[64])
                             .ToArray();
        d.states = new string[f.intervals.Count];
        Array.Fill(d.states, "lost");
        Bitstream.Reader reader = new Bitstream.Reader(data, d.scanStart);
        int j = 0;
        while (j < f.intervals.Count) {
            Interval interval = f.intervals[j];
            int[] predictors = new int[3];
            List<int[]> pending = new();
            int currentMcu = interval.first;
            try {
                for (int n = interval.first * f.blocksPerMcu;
                     n < (interval.first + interval.count) * f.blocksPerMcu; n++) {
                    Block b = f.blocks[n];
                    currentMcu = b.mcu;
                    pending.Add(DecodeBlock(reader, b.component, f.components[b.component],
                                            d.tables, predictors));
                }
                reader.Discard();
                int expected = j < f.intervals.Count - 1 ? 208 + j % 8 : 217;
                if (data[reader.position] != 255 || data[reader.position + 1] != expected)
                    throw new Bitstream.DecodeError("sync");
                int first = interval.first * f.blocksPerMcu;
                for (int n = 0; n < pending.Count; n++)
                    d.coefficients[first + n] = pending[n];
                d.states[j] = "ok";
                reader.position += 2;
                j++;
            } catch (Bitstream.DecodeError error) {
                int offset = reader.position;
                reader.Discard();
                int resync = Bitstream.Resync(data, offset);
                d.states[j] = "damaged " + error.kind + " mcu " + currentMcu + " offset " + offset +
                              " resync " + resync;
                int marker = data[resync + 1];
                if (marker == 217)
                    break;
                j = j + 1 + ((marker - 208 - j) % 8 + 8) % 8;
                reader.position = resync + 2;
            }
        }
        d.planes = new ImageIo.Plane[3];
        for (int k = 0; k < 3; k++)
            d.planes[k] = Reconstruct(f, k, d.coefficients, d.quant, 64);
        d.expanded = Color.Upsample(d.planes, f.factors, f.width, f.height);
        d.image = Color.Combine(d.expanded);
        return d;
    }
    public static Encoding Repair(Decoded d) {
        Frame source = d.frame;
        Frame f =
            new Frame(source.width, source.height,
                      Components(source.components[0].h, source.components[0].v), source.restart);
        int[][] q = new int [4][];
        q[0] = d.quant[source.components[0].tq];
        q[1] = d.quant[source.components[1].tq];
        return EncodePrepared(new Prepared(f, null, q, d.coefficients), "optimized");
    }
    public static Encoding GetEncoding(int q, string sampling, string mode) {
        Key key = new Key(q, sampling, mode);
        if (!encodings.ContainsKey(key))
            encodings[key] = Encode(original, q, sampling, mode, restart);
        return encodings[key];
    }
    public static Decoded Decoding(int q, string sampling) {
        Key key = new Key(q, sampling, mode);
        if (!decodings.ContainsKey(key))
            decodings[key] = Decode(GetEncoding(q, sampling, mode).data);
        return decodings[key];
    }
    public static string Psnr(int[] first, int[] second) {
        long error = 0;
        for (int i = 0; i < first.Length; i++) {
            int delta = first[i] - second[i];
            error += (long)delta * delta;
        }
        return error == 0 ? "inf"
                          : (10 * Math.Log10(65025.0 * first.Length / error))
                                .ToString("F2", CultureInfo.InvariantCulture);
    }
    public static string[] Metrics(Decoded d) {
        string[] result = new string[4];
        for (int k = 0; k < 3; k++)
            result[k] = Psnr(originalPlanes[k].pixels, d.expanded[k].pixels);
        result[3] = Psnr(original.pixels, d.image.pixels);
        return result;
    }
    public static long Gcd(long a, long b) {
        while (b != 0) {
            long t = a % b;
            a = b;
            b = t;
        }
        return a;
    }
    public static string Bpp(int bytes) {
        long a = 8L * bytes, b = (long)original.width * original.height, d = Gcd(a, b);
        return a / d + "/" + b / d;
    }
    public static string Integers(int[] values) {
        List<string> result = new();
        foreach (int v in values)
            result.Add(Convert.ToString(v));
        return string.Join(" ", result);
    }
    public static List<string> RateDistortion() {
        List<string> lines = new();
        lines.Add(
            "quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error");
        foreach (int q in settings.Integers("qualities")) {
            Encoding a = GetEncoding(q, sampling, "standard"),
                     b = GetEncoding(q, sampling, "optimized"),
                     selected = GetEncoding(q, sampling, mode);
            Decoded d = Decoding(q, sampling);
            int maximum = 0;
            for (int i = 0; i < original.pixels.Length; i++)
                maximum = Math.Max(maximum, Math.Abs(original.pixels[i] - d.image.pixels[i]));
            lines.Add(q + "," + a.data.Length + "," + b.data.Length + "," +
                      Bpp(selected.data.Length) + "," + string.Join(",", Metrics(d)) + "," +
                      maximum);
        }
        return lines;
    }
    public static int[] BlockErrors(Encoding e, Decoded d, List<string> lines) {
        Frame f = e.prepared.frame;
        int[] errors = new int[f.blocks.Count];
        lines.Add("blocks " + errors.Length);
        for (int n = 0; n < errors.Length; n++) {
            Block b = f.blocks[n];
            ImageIo.Plane source = e.prepared.planes[b.component], restored = d.planes[b.component];
            int error = 0;
            for (int y = 8 * b.by; y < 8 * b.by + 8; y++)
                for (int x = 8 * b.bx; x < 8 * b.bx + 8; x++) {
                    int delta = source.pixels[y * source.width + x] -
                                restored.pixels[y * restored.width + x];
                    error += delta * delta;
                }
            errors[n] = error;
            int[] z = e.prepared.coefficients[n];
            int nonzero = 0, last = 0;
            for (int k = 0; k < 64; k++)
                if (z[k] != 0) {
                    last = k;
                    if (k > 0)
                        nonzero++;
                }
            lines.Add("block " + n + " " + COMPONENT_NAMES[b.component] + " " + b.bx + " " + b.by +
                      " dc " + z[0] + " diff " + e.differences[n] + " nonzero " + nonzero +
                      " last " + last + " bits " + e.blockBits[n] + " sse " + error);
        }
        return errors;
    }
    public static List<string> HuffmanLines(Encoding e) {
        List<string> lines = new();
        for (int t = 0; t < 4; t++) {
            int c = Entropy.CLASSES[t], id = Entropy.IDS[t];
            Entropy.Table table = e.tables[c][id];
            int[] frequencies = e.frequencies[c][id];
            int coded = 0, bits = 0;
            for (int symbol = 0; symbol < 256; symbol++) {
                coded += frequencies[symbol];
                bits += frequencies[symbol] * table.lengths[symbol];
            }
            lines.Add("table " + Entropy.NAMES[t] + " class " + c + " id " + id + " symbols " +
                      table.symbols.Length + " coded " + coded + " bits " + bits);
            lines.Add("counts " + Integers(table.counts));
            foreach (int symbol in table.symbols) {
                int length = table.lengths[symbol];
                string binary = Convert.ToString(table.codes[symbol], 2);
                binary = new string('0', length - binary.Length) + binary;
                lines.Add("symbol " + symbol.ToString("x2", CultureInfo.InvariantCulture) +
                          " length " + length + " code " + binary + " count " +
                          frequencies[symbol]);
            }
        }
        return lines;
    }
    public static ImageIo.Image Thumbnail(Decoded d) {
        Frame f = d.frame;
        int w = (f.width + 7) / 8, h = (f.height + 7) / 8;
        int[] image = new int[3 * w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int[] values = new int[3];
                for (int k = 0; k < 3; k++) {
                    Component c = f.components[k];
                    int bx = x * c.h / f.hmax, by = y * c.v / f.vmax, dc = 0;
                    for (int n = 0; n < f.blocks.Count; n++) {
                        Block b = f.blocks[n];
                        if (b.component == k && b.bx == bx && b.by == by) {
                            dc = d.coefficients[n][0];
                            break;
                        }
                    }
                    values[k] = Color.Clamp(Color.FloorDivide(dc * d.quant[c.tq][0] + 4, 8) + 128);
                }
                int[] rgb = Color.ToRgb(values[0], values[1], values[2]);
                Array.Copy(rgb, 0, image, 3 * (y * w + x), 3);
            }
        return new ImageIo.Image(w, h, image);
    }
    public static List<string> ReferenceReport(Encoding e, Decoded d, int[] errors) {
        Frame f = e.prepared.frame;
        List<string> lines = new();
        lines.Add("image " + f.width + " " + f.height);
        lines.Add("sampling " + sampling + " mcu " + 8 * f.hmax + " " + 8 * f.vmax + " grid " +
                  f.mx + " " + f.my);
        lines.Add("padded " + 8 * f.hmax * f.mx + " " + 8 * f.vmax * f.my);
        int[] counts = new int[3];
        for (int k = 0; k < 3; k++)
            counts[k] = f.components[k].h * f.components[k].v * f.mcus;
        lines.Add("blocks " + Integers(counts));
        lines.Add("restart_interval " + restart + " markers " + (f.intervals.Count - 1));
        lines.Add("huffman " + mode);
        lines.Add("quality " + quality);
        for (int t = 0; t < 2; t++)
            lines.Add("quant " + t + " " + Integers(Dct.Zigzag(e.prepared.quant[t])));
        int[] symbolCounts = new int[4];
        for (int t = 0; t < 4; t++)
            foreach (int count in e.frequencies[Entropy.CLASSES[t]][Entropy.IDS[t]])
                symbolCounts[t] += count;
        lines.Add("symbols " + Integers(symbolCounts));
        lines.Add("eob " + (e.frequencies[1][0][0] + e.frequencies[1][1][0]) + " zrl " +
                  (e.frequencies[1][0][240] + e.frequencies[1][1][240]));
        int zero = 0;
        int[] nonzero = new int[64];
        foreach (int[] z in e.prepared.coefficients) {
            bool any = false;
            for (int k = 0; k < 64; k++)
                if (z[k] != 0) {
                    nonzero[k]++;
                    if (k > 0)
                        any = true;
                }
            if (!any)
                zero++;
        }
        lines.Add("zero_ac_blocks " + zero);
        lines.Add("nonzero " + Integers(nonzero));
        for (int k = 0; k < 3; k++) {
            int bits = 0, nz = 0, error = 0;
            for (int n = 0; n < f.blocks.Count; n++)
                if (f.blocks[n].component == k) {
                    bits += e.blockBits[n];
                    error += errors[n];
                    foreach (int value in e.prepared.coefficients[n])
                        if (value != 0)
                            nz++;
                }
            lines.Add("component " + COMPONENT_NAMES[k] + " bits " + bits + " nonzero " + nz +
                      " sse " + error);
        }
        lines.Add("padding_bits " + e.paddingBits);
        lines.Add("stuffed_bytes " + e.stuffedBytes);
        lines.Add("header_bytes " + e.headerBytes);
        lines.Add("scan_bytes " + e.scanBytes);
        lines.Add("total_bytes " + e.data.Length);
        for (int j = 0; j < e.intervals.Count; j++) {
            EncodedInterval interval = e.intervals[j];
            lines.Add("interval " + j + " " + interval.first + " " + interval.count + " " +
                      interval.position + " " + interval.length);
        }
        int[] histogram = new int[8], edges = { 1, 2, 4, 8, 16, 32, 64 };
        for (int i = 0; i < original.pixels.Length; i++) {
            int error = Math.Abs(original.pixels[i] - d.image.pixels[i]), bin = 0;
            while (bin < 7 && error >= edges[bin])
                bin++;
            histogram[bin]++;
        }
        lines.Add("error_histogram " + Integers(histogram));
        foreach (int keep in settings.Integers("truncate")) {
            ImageIo.Plane plane = Reconstruct(d.frame, 0, d.coefficients, d.quant, keep);
            int[] cropped = new int[f.width * f.height];
            for (int y = 0; y < f.height; y++)
                Array.Copy(plane.pixels, y * plane.width, cropped, y * f.width, f.width);
            lines.Add("truncate " + keep + " " + Psnr(originalPlanes[0].pixels, cropped));
        }
        return lines;
    }
    public static List<string> Comparisons(Encoding reference, Decoded decoded) {
        List<string> lines = new();
        foreach (string s in new string[] { "444", "422", "420" }) {
            Encoding e = GetEncoding(quality, s, mode);
            string[] values = Metrics(Decoding(quality, s));
            lines.Add("sampling_compare " + s + " " + e.data.Length + " " + values[1] + " " +
                      values[2] + " " + values[3]);
        }
        ImageIo.Image previous = original;
        for (int g = 1; g <= settings.Integer("generations"); g++) {
            Encoding e = g == 1 ? reference : Encode(previous, quality, sampling, mode, restart);
            Decoded d = g == 1 ? decoded : Decode(e.data);
            int changed = 0;
            for (int p = 0; p < previous.width * previous.height; p++) {
                bool different = false;
                for (int c = 0; c < 3; c++)
                    if (previous.pixels[3 * p + c] != d.image.pixels[3 * p + c])
                        different = true;
                if (different)
                    changed++;
            }
            lines.Add("generation " + g + " " + e.data.Length + " " +
                      Psnr(original.pixels, d.image.pixels) + " " + changed);
            previous = d.image;
        }
        int lo = 1, hi = 100, target = settings.Integer("target_bytes");
        while (lo < hi) {
            int mid = (lo + hi + 1) / 2, b = GetEncoding(mid, sampling, mode).data.Length;
            lines.Add("rate_control_step " + mid + " " + b);
            if (b <= target)
                lo = mid;
            else
                hi = mid - 1;
        }
        int bytes = GetEncoding(lo, sampling, mode).data.Length;
        lines.Add("rate_control " + lo + " " + bytes + " " + (bytes <= target ? "yes" : "no") +
                  " " + Psnr(original.pixels, Decoding(lo, sampling).image.pixels));
        return lines;
    }
    public static List<string> StreamReport(Decoded d, Encoding repaired, Decoded redone) {
        List<string> lines = new();
        foreach (Segment s in d.segments)
            lines.Add("stream_segment " + s.position + " " + s.name + " " + s.length);
        Frame f = d.frame;
        lines.Add("stream_image " + f.width + " " + f.height);
        foreach (Component c in f.components)
            lines.Add("stream_component " + c.identifier + " " + c.h + " " + c.v + " " + c.tq +
                      " " + c.td + " " + c.ta);
        for (int t = 0; t < 4; t++)
            if (d.quant[t] != null)
                lines.Add("stream_quant " + t + " " + Integers(Dct.Zigzag(d.quant[t])));
        for (int c = 0; c < 2; c++)
            for (int id = 0; id < 16; id++)
                if (d.tables[c][id] != null) {
                    Entropy.Table table = d.tables[c][id];
                    int longest = 16;
                    while (table.counts[longest - 1] == 0)
                        longest--;
                    lines.Add("stream_huffman " + c + " " + id + " symbols " +
                              table.symbols.Length + " longest " + longest);
                }
        int ok = 0, damaged = 0, lost = 0;
        foreach (string state in d.states) {
            if (state.Equals("ok"))
                ok++;
            else if (state.Equals("lost"))
                lost++;
            else
                damaged++;
        }
        lines.Add("stream_restart " + f.restart + " intervals " + f.intervals.Count + " ok " + ok +
                  " damaged " + damaged + " lost " + lost);
        for (int j = 0; j < f.intervals.Count; j++) {
            Interval interval = f.intervals[j];
            lines.Add("stream_interval " + j + " " + interval.first + " " + interval.count + " " +
                      d.states[j]);
        }
        lines.Add("stream_scan_bytes " + d.scanBytes);
        lines.Add("repair " + repaired.data.Length + " " + repaired.headerBytes + " " +
                  repaired.scanBytes + " identical " +
                  (d.image.pixels.SequenceEqual(redone.image.pixels) ? "yes" : "no"));
        return lines;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        original = ImageIo.ReadImage();
        originalPlanes = Color.Split(original);
        settings = ImageIo.ReadParameters();
        ImageIo.Tables tables = ImageIo.ReadTables();
        transform = tables.transform;
        basic = tables.basic;
        standard = tables.huffman;
        quality = settings.Integers("qualities")[0];
        sampling = settings.Text("sampling");
        mode = settings.Text("huffman");
        restart = settings.Integer("restart_interval");
        List<string> rate = RateDistortion();
        Encoding reference = GetEncoding(quality, sampling, mode);
        Decoded decoded = Decoding(quality, sampling);
        List<string> blocks = new();
        int[] errors = BlockErrors(reference, decoded, blocks);
        List<string> report = ReferenceReport(reference, decoded, errors);
        report.AddRange(Comparisons(reference, decoded));
        Decoded stream = Decode(ImageIo.ReadHex());
        Encoding repaired = Repair(stream);
        report.AddRange(StreamReport(stream, repaired, Decode(repaired.data)));
        ImageIo.Text("rate_distortion.csv", rate);
        ImageIo.WriteImage("decoded.ppm", decoded.image);
        ImageIo.WriteHex("bitstream.hex", reference.data);
        ImageIo.WriteImage("thumbnail.ppm", Thumbnail(decoded));
        ImageIo.Text("huffman_tables.txt", HuffmanLines(reference));
        ImageIo.Text("blocks.txt", blocks);
        ImageIo.WriteImage("stream_decoded.ppm", stream.image);
        ImageIo.WriteHex("repaired.hex", repaired.data);
        ImageIo.Text("report.txt", report);
    }
}
