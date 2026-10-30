import java.util.*;
public final class Main {
    static int[] transform;
    static int[][] basic;
    static Entropy.Table[][] standard;
    static ImageIo.Parameters params;
    static ImageIo.Image original;
    static ImageIo.Plane[] originalPlanes;
    static int quality, restart;
    static String sampling, mode;
    static final String[] COMPONENT_NAMES = {"Y", "Cb", "Cr"};
    static final class Component {
        int identifier, h, v, tq, td, ta;
        Component(int identifier, int h, int v, int tq, int td, int ta) {
            this.identifier = identifier;
            this.h = h;
            this.v = v;
            this.tq = tq;
            this.td = td;
            this.ta = ta;
        }
    }
    record Block(int mcu, int component, int bx, int by) {}
    record Interval(int first, int count) {}
    record EncodedInterval(int first, int count, int position, int length) {}
    record Segment(int position, String name, int length) {}
    record Symbol(int tableClass, int tableId, int value, int extra, int width) {}
    static final class Frame {
        int width, height, hmax = 1, vmax = 1, mx, my, mcus, blocksPerMcu, restart;
        Component[] components;
        int[][] factors = new int[3][2];
        List<Block> blocks = new ArrayList<>();
        List<Interval> intervals = new ArrayList<>();
        Frame(int w, int h, Component[] components, int restart) {
            width = w;
            height = h;
            this.components = components;
            this.restart = restart;
            for (int k = 0; k < 3; k++) {
                Component c = components[k];
                hmax = Math.max(hmax, c.h);
                vmax = Math.max(vmax, c.v);
                factors[k] = new int[] {c.h, c.v};
                blocksPerMcu += c.h * c.v;
            }
            mx = (w + 8 * hmax - 1) / (8 * hmax);
            my = (h + 8 * vmax - 1) / (8 * vmax);
            mcus = mx * my;
            for (int mcu = 0; mcu < mcus; mcu++)
                for (int k = 0; k < 3; k++)
                    for (int v = 0; v < components[k].v; v++)
                        for (int x = 0; x < components[k].h; x++)
                            blocks.add(new Block(mcu, k, components[k].h * (mcu % mx) + x,
                                                 components[k].v * (mcu / mx) + v));
            int step = restart == 0 ? mcus : restart;
            for (int first = 0; first < mcus; first += step)
                intervals.add(new Interval(first, Math.min(step, mcus - first)));
        }
    }
    record Prepared(Frame frame, ImageIo.Plane[] planes, int[][] quant, int[][] coefficients) {}
    static final class Encoding {
        Prepared prepared;
        Entropy.Table[][] tables;
        int[][][] frequencies;
        int[] differences, blockBits, data;
        int headerBytes, scanBytes, paddingBits, stuffedBytes;
        List<EncodedInterval> intervals = new ArrayList<>();
    }
    static final class Decoded {
        Frame frame;
        int[][] quant = new int[4][];
        Entropy.Table[][] tables = new Entropy.Table[2][4];
        List<Segment> segments = new ArrayList<>();
        int scanStart, scanBytes;
        int[][] coefficients;
        String[] states;
        ImageIo.Plane[] planes, expanded;
        ImageIo.Image image;
    }
    record Key(int quality, String sampling, String mode) {}
    static final Map<Key, Encoding> encodings = new HashMap<>();
    static final Map<Key, Decoded> decodings = new HashMap<>();
    static Component[] components(int h, int v) {
        return new Component[] {new Component(1, h, v, 0, 0, 0), new Component(2, 1, 1, 1, 1, 1),
                                new Component(3, 1, 1, 1, 1, 1)};
    }
    static int[] array(List<Integer> values) {
        int[] result = new int[values.size()];
        for (int i = 0; i < result.length; i++)
            result[i] = values.get(i);
        return result;
    }
    static void append(List<Integer> output, int... values) {
        for (int v : values)
            output.add(v);
    }
    static void word(List<Integer> output, int v) { append(output, v / 256, v % 256); }
    static int wordAt(int[] data, int p) { return 256 * data[p] + data[p + 1]; }
    static void segment(List<Integer> output, int marker, List<Integer> contents) {
        append(output, 255, marker);
        word(output, contents.size() + 2);
        output.addAll(contents);
    }
    static Prepared prepare(ImageIo.Image image, int q, String sampling, int restart) {
        int hs = sampling.equals("444") ? 1 : 2, vs = sampling.equals("420") ? 2 : 1;
        Frame f = new Frame(image.width(), image.height(), components(hs, vs), restart);
        ImageIo.Plane[] planes = Color.components(Color.split(image), f.factors, f.mx, f.my);
        int[][] quant = Dct.tables(basic, q), coefficients = new int[f.blocks.size()][64];
        for (int n = 0; n < f.blocks.size(); n++) {
            Block block = f.blocks.get(n);
            ImageIo.Plane plane = planes[block.component()];
            int[] pixels = new int[64];
            for (int y = 0; y < 8; y++)
                for (int x = 0; x < 8; x++)
                    pixels[8 * y + x] =
                        plane.pixels()[(8 * block.by() + y) * plane.width() + 8 * block.bx() + x];
            coefficients[n] = Dct.zigzag(Dct.quantize(Dct.forward(pixels, transform),
                                                      quant[f.components[block.component()].tq]));
        }
        return new Prepared(f, planes, quant, coefficients);
    }
    static int[] header(Frame f, int[][] quant, Entropy.Table[][] tables) {
        List<Integer> output = new ArrayList<>();
        append(output, 255, 216);
        List<Integer> contents = new ArrayList<>();
        for (int t = 0; t < 2; t++) {
            contents.add(t);
            append(contents, Dct.zigzag(quant[t]));
        }
        segment(output, 219, contents);
        contents = new ArrayList<>();
        contents.add(8);
        word(contents, f.height);
        word(contents, f.width);
        contents.add(3);
        for (Component c : f.components)
            append(contents, c.identifier, 16 * c.h + c.v, c.tq);
        segment(output, 192, contents);
        contents = new ArrayList<>();
        for (int t = 0; t < 4; t++) {
            int c = Entropy.CLASSES[t], id = Entropy.IDS[t];
            Entropy.Table table = tables[c][id];
            contents.add(16 * c + id);
            append(contents, table.counts);
            append(contents, table.symbols);
        }
        segment(output, 196, contents);
        if (f.restart > 0) {
            contents = new ArrayList<>();
            word(contents, f.restart);
            segment(output, 221, contents);
        }
        contents = new ArrayList<>();
        contents.add(3);
        for (Component c : f.components)
            append(contents, c.identifier, 16 * c.td + c.ta);
        append(contents, 0, 63, 0);
        segment(output, 218, contents);
        return array(output);
    }
    static Encoding encodePrepared(Prepared prepared, String mode) {
        Encoding result = new Encoding();
        result.prepared = prepared;
        Frame f = prepared.frame();
        result.frequencies = new int[2][4][256];
        result.differences = new int[f.blocks.size()];
        result.blockBits = new int[f.blocks.size()];
        List<List<Symbol>> allSymbols = new ArrayList<>();
        for (Interval interval : f.intervals) {
            int[] predictors = new int[3];
            for (int n = interval.first() * f.blocksPerMcu;
                 n < (interval.first() + interval.count()) * f.blocksPerMcu; n++) {
                Block block = f.blocks.get(n);
                Component c = f.components[block.component()];
                int[] z = prepared.coefficients()[n];
                int difference = z[0] - predictors[block.component()];
                predictors[block.component()] = z[0];
                result.differences[n] = difference;
                int category = Entropy.category(difference);
                List<Symbol> symbols = new ArrayList<>();
                symbols.add(new Symbol(0, c.td, category, Entropy.extra(difference), category));
                int run = 0;
                for (int i = 1; i < 64; i++) {
                    int value = z[i];
                    if (value == 0) {
                        run++;
                        continue;
                    }
                    while (run >= 16) {
                        symbols.add(new Symbol(1, c.ta, 240, 0, 0));
                        run -= 16;
                    }
                    category = Entropy.category(value);
                    symbols.add(
                        new Symbol(1, c.ta, 16 * run + category, Entropy.extra(value), category));
                    run = 0;
                }
                if (run > 0)
                    symbols.add(new Symbol(1, c.ta, 0, 0, 0));
                for (Symbol symbol : symbols)
                    result.frequencies[symbol.tableClass()][symbol.tableId()][symbol.value()]++;
                allSymbols.add(symbols);
            }
        }
        result.tables = standard;
        if (mode.equals("optimized")) {
            result.tables = new Entropy.Table[2][4];
            for (int t = 0; t < 4; t++) {
                int c = Entropy.CLASSES[t], id = Entropy.IDS[t];
                result.tables[c][id] = Entropy.optimized(result.frequencies[c][id]);
            }
        }
        int[] header = header(f, prepared.quant(), result.tables);
        Bitstream.Writer writer = new Bitstream.Writer();
        for (int j = 0; j < f.intervals.size(); j++) {
            Interval interval = f.intervals.get(j);
            if (j > 0)
                writer.restart(j - 1);
            int start = writer.data.size();
            for (int n = interval.first() * f.blocksPerMcu;
                 n < (interval.first() + interval.count()) * f.blocksPerMcu; n++)
                for (Symbol symbol : allSymbols.get(n)) {
                    Entropy.Table table = result.tables[symbol.tableClass()][symbol.tableId()];
                    int length = table.lengths[symbol.value()];
                    writer.write(table.codes[symbol.value()], length);
                    writer.write(symbol.extra(), symbol.width());
                    result.blockBits[n] += length + symbol.width();
                }
            writer.pad();
            result.intervals.add(new EncodedInterval(interval.first(), interval.count(),
                                                     header.length + start,
                                                     writer.data.size() - start));
        }
        List<Integer> data = new ArrayList<>();
        append(data, header);
        data.addAll(writer.data);
        append(data, 255, 217);
        result.data = array(data);
        result.headerBytes = header.length;
        result.scanBytes = writer.data.size();
        result.paddingBits = writer.paddingBits;
        result.stuffedBytes = writer.stuffedBytes;
        return result;
    }
    static Encoding encode(ImageIo.Image image, int q, String sampling, String mode, int restart) {
        return encodePrepared(prepare(image, q, sampling, restart), mode);
    }
    static String segmentName(int marker) {
        return marker >= 224 && marker <= 239 ? "APP" + (marker - 224) : switch (marker) {
            case 192 -> "SOF0";
            case 196 -> "DHT";
            case 219 -> "DQT";
            case 221 -> "DRI";
            case 218 -> "SOS";
            default -> "COM";
        };
    }
    static Decoded parse(int[] data) {
        Decoded d = new Decoded();
        int position = 2, width = 0, height = 0, restart = 0;
        Component[] components = new Component[3];
        d.segments.add(new Segment(0, "SOI", 0));
        while (true) {
            int marker = data[position + 1], length = wordAt(data, position + 2);
            int[] contents = Arrays.copyOfRange(data, position + 4, position + length + 2);
            d.segments.add(new Segment(position, segmentName(marker), length));
            position += length + 2;
            if (marker == 219) {
                for (int offset = 0; offset < contents.length; offset += 65)
                    d.quant[contents[offset]] =
                        Dct.unzigzag(Arrays.copyOfRange(contents, offset + 1, offset + 65));
            } else if (marker == 196) {
                int offset = 0;
                while (offset < contents.length) {
                    int c = contents[offset] / 16, id = contents[offset] % 16;
                    int[] counts = Arrays.copyOfRange(contents, offset + 1, offset + 17);
                    int count = 0;
                    for (int value : counts)
                        count += value;
                    d.tables[c][id] = new Entropy.Table(
                        counts, Arrays.copyOfRange(contents, offset + 17, offset + 17 + count));
                    offset += 17 + count;
                }
            } else if (marker == 192) {
                height = wordAt(contents, 1);
                width = wordAt(contents, 3);
                for (int k = 0; k < 3; k++) {
                    int offset = 6 + 3 * k, factor = contents[offset + 1];
                    components[k] = new Component(contents[offset], factor / 16, factor % 16,
                                                  contents[offset + 2], 0, 0);
                }
            } else if (marker == 221)
                restart = wordAt(contents, 0);
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
        d.scanBytes = data.length - 2 - position;
        d.segments.add(new Segment(data.length - 2, "EOI", 0));
        return d;
    }
    static int readSymbol(Bitstream.Reader reader, Entropy.Table table) {
        int code = 0;
        for (int length = 1; length <= 16; length++) {
            code = 2 * code + reader.bit();
            Integer symbol = table.decode.get((length << 16) | code);
            if (symbol != null)
                return symbol;
        }
        throw new Bitstream.DecodeError("code");
    }
    static int[] decodeBlock(Bitstream.Reader reader, int k, Component c, Entropy.Table[][] tables,
                             int[] predictors) {
        int[] z = new int[64];
        int n = readSymbol(reader, tables[0][c.td]);
        predictors[k] += Entropy.amplitude(reader.read(n), n);
        z[0] = predictors[k];
        int index = 1;
        while (index <= 63) {
            int symbol = readSymbol(reader, tables[1][c.ta]);
            if (symbol == 0)
                break;
            int run = symbol / 16;
            n = symbol % 16;
            index += run;
            if (index > 63)
                throw new Bitstream.DecodeError("index");
            if (n > 0)
                z[index] = Entropy.amplitude(reader.read(n), n);
            index++;
        }
        return z;
    }
    static ImageIo.Plane reconstruct(Frame f, int k, int[][] coefficients, int[][] quant,
                                     int keep) {
        Component c = f.components[k];
        int w = 8 * c.h * f.mx, h = 8 * c.v * f.my;
        int[] plane = new int[w * h];
        Arrays.fill(plane, 128);
        for (int n = 0; n < f.blocks.size(); n++) {
            Block b = f.blocks.get(n);
            if (b.component() != k)
                continue;
            int[] pixels =
                Dct.inverse(Dct.dequantize(coefficients[n], quant[c.tq], keep), transform);
            for (int y = 0; y < 8; y++)
                System.arraycopy(pixels, 8 * y, plane, (8 * b.by() + y) * w + 8 * b.bx(), 8);
        }
        return new ImageIo.Plane(w, h, plane);
    }
    static Decoded decode(int[] data) {
        Decoded d = parse(data);
        Frame f = d.frame;
        d.coefficients = new int[f.blocks.size()][64];
        d.states = new String[f.intervals.size()];
        Arrays.fill(d.states, "lost");
        Bitstream.Reader reader = new Bitstream.Reader(data, d.scanStart);
        int j = 0;
        while (j < f.intervals.size()) {
            Interval interval = f.intervals.get(j);
            int[] predictors = new int[3];
            List<int[]> pending = new ArrayList<>();
            int currentMcu = interval.first();
            try {
                for (int n = interval.first() * f.blocksPerMcu;
                     n < (interval.first() + interval.count()) * f.blocksPerMcu; n++) {
                    Block b = f.blocks.get(n);
                    currentMcu = b.mcu();
                    pending.add(decodeBlock(reader, b.component(), f.components[b.component()],
                                            d.tables, predictors));
                }
                reader.discard();
                int expected = j < f.intervals.size() - 1 ? 208 + j % 8 : 217;
                if (data[reader.position] != 255 || data[reader.position + 1] != expected)
                    throw new Bitstream.DecodeError("sync");
                int first = interval.first() * f.blocksPerMcu;
                for (int n = 0; n < pending.size(); n++)
                    d.coefficients[first + n] = pending.get(n);
                d.states[j] = "ok";
                reader.position += 2;
                j++;
            } catch (Bitstream.DecodeError error) {
                int offset = reader.position;
                reader.discard();
                int resync = Bitstream.resync(data, offset);
                d.states[j] = "damaged " + error.kind + " mcu " + currentMcu + " offset " + offset +
                              " resync " + resync;
                int marker = data[resync + 1];
                if (marker == 217)
                    break;
                j = j + 1 + Math.floorMod(marker - 208 - j, 8);
                reader.position = resync + 2;
            }
        }
        d.planes = new ImageIo.Plane[3];
        for (int k = 0; k < 3; k++)
            d.planes[k] = reconstruct(f, k, d.coefficients, d.quant, 64);
        d.expanded = Color.upsample(d.planes, f.factors, f.width, f.height);
        d.image = Color.combine(d.expanded);
        return d;
    }
    static Encoding repair(Decoded d) {
        Frame source = d.frame;
        Frame f =
            new Frame(source.width, source.height,
                      components(source.components[0].h, source.components[0].v), source.restart);
        int[][] q = new int[4][];
        q[0] = d.quant[source.components[0].tq];
        q[1] = d.quant[source.components[1].tq];
        return encodePrepared(new Prepared(f, null, q, d.coefficients), "optimized");
    }
    static Encoding encoding(int q, String sampling, String mode) {
        Key key = new Key(q, sampling, mode);
        if (!encodings.containsKey(key))
            encodings.put(key, encode(original, q, sampling, mode, restart));
        return encodings.get(key);
    }
    static Decoded decoding(int q, String sampling) {
        Key key = new Key(q, sampling, mode);
        if (!decodings.containsKey(key))
            decodings.put(key, decode(encoding(q, sampling, mode).data));
        return decodings.get(key);
    }
    static String psnr(int[] first, int[] second) {
        long error = 0;
        for (int i = 0; i < first.length; i++) {
            int delta = first[i] - second[i];
            error += (long)delta * delta;
        }
        return error == 0
            ? "inf"
            : String.format(Locale.ROOT, "%.2f", 10 * Math.log10(65025.0 * first.length / error));
    }
    static String[] metrics(Decoded d) {
        String[] result = new String[4];
        for (int k = 0; k < 3; k++)
            result[k] = psnr(originalPlanes[k].pixels(), d.expanded[k].pixels());
        result[3] = psnr(original.pixels(), d.image.pixels());
        return result;
    }
    static long gcd(long a, long b) {
        while (b != 0) {
            long t = a % b;
            a = b;
            b = t;
        }
        return a;
    }
    static String bpp(int bytes) {
        long a = 8L * bytes, b = (long)original.width() * original.height(), d = gcd(a, b);
        return a / d + "/" + b / d;
    }
    static String integers(int[] values) {
        StringJoiner result = new StringJoiner(" ");
        for (int v : values)
            result.add(Integer.toString(v));
        return result.toString();
    }
    static List<String> rateDistortion() {
        List<String> lines = new ArrayList<>();
        lines.add(
            "quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error");
        for (int q : params.integers("qualities")) {
            Encoding a = encoding(q, sampling, "standard"), b = encoding(q, sampling, "optimized"),
                     selected = encoding(q, sampling, mode);
            Decoded d = decoding(q, sampling);
            int maximum = 0;
            for (int i = 0; i < original.pixels().length; i++)
                maximum = Math.max(maximum, Math.abs(original.pixels()[i] - d.image.pixels()[i]));
            lines.add(q + "," + a.data.length + "," + b.data.length + "," +
                      bpp(selected.data.length) + "," + String.join(",", metrics(d)) + "," +
                      maximum);
        }
        return lines;
    }
    static int[] blockErrors(Encoding e, Decoded d, List<String> lines) {
        Frame f = e.prepared.frame();
        int[] errors = new int[f.blocks.size()];
        lines.add("blocks " + errors.length);
        for (int n = 0; n < errors.length; n++) {
            Block b = f.blocks.get(n);
            ImageIo.Plane source = e.prepared.planes()[b.component()], restored =
                                                                           d.planes[b.component()];
            int error = 0;
            for (int y = 8 * b.by(); y < 8 * b.by() + 8; y++)
                for (int x = 8 * b.bx(); x < 8 * b.bx() + 8; x++) {
                    int delta = source.pixels()[y * source.width() + x] -
                                restored.pixels()[y * restored.width() + x];
                    error += delta * delta;
                }
            errors[n] = error;
            int[] z = e.prepared.coefficients()[n];
            int nonzero = 0, last = 0;
            for (int k = 0; k < 64; k++)
                if (z[k] != 0) {
                    last = k;
                    if (k > 0)
                        nonzero++;
                }
            lines.add("block " + n + " " + COMPONENT_NAMES[b.component()] + " " + b.bx() + " " +
                      b.by() + " dc " + z[0] + " diff " + e.differences[n] + " nonzero " + nonzero +
                      " last " + last + " bits " + e.blockBits[n] + " sse " + error);
        }
        return errors;
    }
    static List<String> huffmanLines(Encoding e) {
        List<String> lines = new ArrayList<>();
        for (int t = 0; t < 4; t++) {
            int c = Entropy.CLASSES[t], id = Entropy.IDS[t];
            Entropy.Table table = e.tables[c][id];
            int[] frequencies = e.frequencies[c][id];
            int coded = 0, bits = 0;
            for (int symbol = 0; symbol < 256; symbol++) {
                coded += frequencies[symbol];
                bits += frequencies[symbol] * table.lengths[symbol];
            }
            lines.add("table " + Entropy.NAMES[t] + " class " + c + " id " + id + " symbols " +
                      table.symbols.length + " coded " + coded + " bits " + bits);
            lines.add("counts " + integers(table.counts));
            for (int symbol : table.symbols) {
                int length = table.lengths[symbol];
                String binary = Integer.toBinaryString(table.codes[symbol]);
                binary = "0".repeat(length - binary.length()) + binary;
                lines.add("symbol " + String.format(Locale.ROOT, "%02x", symbol) + " length " +
                          length + " code " + binary + " count " + frequencies[symbol]);
            }
        }
        return lines;
    }
    static ImageIo.Image thumbnail(Decoded d) {
        Frame f = d.frame;
        int w = (f.width + 7) / 8, h = (f.height + 7) / 8;
        int[] image = new int[3 * w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int[] values = new int[3];
                for (int k = 0; k < 3; k++) {
                    Component c = f.components[k];
                    int bx = x * c.h / f.hmax, by = y * c.v / f.vmax, dc = 0;
                    for (int n = 0; n < f.blocks.size(); n++) {
                        Block b = f.blocks.get(n);
                        if (b.component() == k && b.bx() == bx && b.by() == by) {
                            dc = d.coefficients[n][0];
                            break;
                        }
                    }
                    values[k] = Color.clamp(Math.floorDiv(dc * d.quant[c.tq][0] + 4, 8) + 128);
                }
                int[] rgb = Color.toRgb(values[0], values[1], values[2]);
                System.arraycopy(rgb, 0, image, 3 * (y * w + x), 3);
            }
        return new ImageIo.Image(w, h, image);
    }
    static List<String> referenceReport(Encoding e, Decoded d, int[] errors) {
        Frame f = e.prepared.frame();
        List<String> lines = new ArrayList<>();
        lines.add("image " + f.width + " " + f.height);
        lines.add("sampling " + sampling + " mcu " + 8 * f.hmax + " " + 8 * f.vmax + " grid " +
                  f.mx + " " + f.my);
        lines.add("padded " + 8 * f.hmax * f.mx + " " + 8 * f.vmax * f.my);
        int[] counts = new int[3];
        for (int k = 0; k < 3; k++)
            counts[k] = f.components[k].h * f.components[k].v * f.mcus;
        lines.add("blocks " + integers(counts));
        lines.add("restart_interval " + restart + " markers " + (f.intervals.size() - 1));
        lines.add("huffman " + mode);
        lines.add("quality " + quality);
        for (int t = 0; t < 2; t++)
            lines.add("quant " + t + " " + integers(Dct.zigzag(e.prepared.quant()[t])));
        int[] symbolCounts = new int[4];
        for (int t = 0; t < 4; t++)
            for (int count : e.frequencies[Entropy.CLASSES[t]][Entropy.IDS[t]])
                symbolCounts[t] += count;
        lines.add("symbols " + integers(symbolCounts));
        lines.add("eob " + (e.frequencies[1][0][0] + e.frequencies[1][1][0]) + " zrl " +
                  (e.frequencies[1][0][240] + e.frequencies[1][1][240]));
        int zero = 0;
        int[] nonzero = new int[64];
        for (int[] z : e.prepared.coefficients()) {
            boolean any = false;
            for (int k = 0; k < 64; k++)
                if (z[k] != 0) {
                    nonzero[k]++;
                    if (k > 0)
                        any = true;
                }
            if (!any)
                zero++;
        }
        lines.add("zero_ac_blocks " + zero);
        lines.add("nonzero " + integers(nonzero));
        for (int k = 0; k < 3; k++) {
            int bits = 0, nz = 0, error = 0;
            for (int n = 0; n < f.blocks.size(); n++)
                if (f.blocks.get(n).component() == k) {
                    bits += e.blockBits[n];
                    error += errors[n];
                    for (int value : e.prepared.coefficients()[n])
                        if (value != 0)
                            nz++;
                }
            lines.add("component " + COMPONENT_NAMES[k] + " bits " + bits + " nonzero " + nz +
                      " sse " + error);
        }
        lines.add("padding_bits " + e.paddingBits);
        lines.add("stuffed_bytes " + e.stuffedBytes);
        lines.add("header_bytes " + e.headerBytes);
        lines.add("scan_bytes " + e.scanBytes);
        lines.add("total_bytes " + e.data.length);
        for (int j = 0; j < e.intervals.size(); j++) {
            EncodedInterval interval = e.intervals.get(j);
            lines.add("interval " + j + " " + interval.first() + " " + interval.count() + " " +
                      interval.position() + " " + interval.length());
        }
        int[] histogram = new int[8], edges = {1, 2, 4, 8, 16, 32, 64};
        for (int i = 0; i < original.pixels().length; i++) {
            int error = Math.abs(original.pixels()[i] - d.image.pixels()[i]), bin = 0;
            while (bin < 7 && error >= edges[bin])
                bin++;
            histogram[bin]++;
        }
        lines.add("error_histogram " + integers(histogram));
        for (int keep : params.integers("truncate")) {
            ImageIo.Plane plane = reconstruct(d.frame, 0, d.coefficients, d.quant, keep);
            int[] cropped = new int[f.width * f.height];
            for (int y = 0; y < f.height; y++)
                System.arraycopy(plane.pixels(), y * plane.width(), cropped, y * f.width, f.width);
            lines.add("truncate " + keep + " " + psnr(originalPlanes[0].pixels(), cropped));
        }
        return lines;
    }
    static List<String> comparisons(Encoding reference, Decoded decoded) {
        List<String> lines = new ArrayList<>();
        for (String s : new String[] {"444", "422", "420"}) {
            Encoding e = encoding(quality, s, mode);
            String[] values = metrics(decoding(quality, s));
            lines.add("sampling_compare " + s + " " + e.data.length + " " + values[1] + " " +
                      values[2] + " " + values[3]);
        }
        ImageIo.Image previous = original;
        for (int g = 1; g <= params.integer("generations"); g++) {
            Encoding e = g == 1 ? reference : encode(previous, quality, sampling, mode, restart);
            Decoded d = g == 1 ? decoded : decode(e.data);
            int changed = 0;
            for (int p = 0; p < previous.width() * previous.height(); p++) {
                boolean different = false;
                for (int c = 0; c < 3; c++)
                    if (previous.pixels()[3 * p + c] != d.image.pixels()[3 * p + c])
                        different = true;
                if (different)
                    changed++;
            }
            lines.add("generation " + g + " " + e.data.length + " " +
                      psnr(original.pixels(), d.image.pixels()) + " " + changed);
            previous = d.image;
        }
        int lo = 1, hi = 100, target = params.integer("target_bytes");
        while (lo < hi) {
            int mid = (lo + hi + 1) / 2, b = encoding(mid, sampling, mode).data.length;
            lines.add("rate_control_step " + mid + " " + b);
            if (b <= target)
                lo = mid;
            else
                hi = mid - 1;
        }
        int bytes = encoding(lo, sampling, mode).data.length;
        lines.add("rate_control " + lo + " " + bytes + " " + (bytes <= target ? "yes" : "no") +
                  " " + psnr(original.pixels(), decoding(lo, sampling).image.pixels()));
        return lines;
    }
    static List<String> streamReport(Decoded d, Encoding repaired, Decoded redone) {
        List<String> lines = new ArrayList<>();
        for (Segment s : d.segments)
            lines.add("stream_segment " + s.position() + " " + s.name() + " " + s.length());
        Frame f = d.frame;
        lines.add("stream_image " + f.width + " " + f.height);
        for (Component c : f.components)
            lines.add("stream_component " + c.identifier + " " + c.h + " " + c.v + " " + c.tq +
                      " " + c.td + " " + c.ta);
        for (int t = 0; t < 4; t++)
            if (d.quant[t] != null)
                lines.add("stream_quant " + t + " " + integers(Dct.zigzag(d.quant[t])));
        for (int c = 0; c < 2; c++)
            for (int id = 0; id < 4; id++)
                if (d.tables[c][id] != null) {
                    Entropy.Table table = d.tables[c][id];
                    int longest = 16;
                    while (table.counts[longest - 1] == 0)
                        longest--;
                    lines.add("stream_huffman " + c + " " + id + " symbols " +
                              table.symbols.length + " longest " + longest);
                }
        int ok = 0, damaged = 0, lost = 0;
        for (String state : d.states) {
            if (state.equals("ok"))
                ok++;
            else if (state.equals("lost"))
                lost++;
            else
                damaged++;
        }
        lines.add("stream_restart " + f.restart + " intervals " + f.intervals.size() + " ok " + ok +
                  " damaged " + damaged + " lost " + lost);
        for (int j = 0; j < f.intervals.size(); j++) {
            Interval interval = f.intervals.get(j);
            lines.add("stream_interval " + j + " " + interval.first() + " " + interval.count() +
                      " " + d.states[j]);
        }
        lines.add("stream_scan_bytes " + d.scanBytes);
        lines.add("repair " + repaired.data.length + " " + repaired.headerBytes + " " +
                  repaired.scanBytes + " identical " +
                  (Arrays.equals(d.image.pixels(), redone.image.pixels()) ? "yes" : "no"));
        return lines;
    }
    public static void main(String[] args) throws Exception {
        original = ImageIo.readImage();
        originalPlanes = Color.split(original);
        params = ImageIo.parameters();
        ImageIo.Tables tables = ImageIo.tables();
        transform = tables.transform();
        basic = tables.basic();
        standard = tables.huffman();
        quality = params.integers("qualities")[0];
        sampling = params.text("sampling");
        mode = params.text("huffman");
        restart = params.integer("restart_interval");
        List<String> rate = rateDistortion();
        Encoding reference = encoding(quality, sampling, mode);
        Decoded decoded = decoding(quality, sampling);
        List<String> blocks = new ArrayList<>();
        int[] errors = blockErrors(reference, decoded, blocks);
        List<String> report = referenceReport(reference, decoded, errors);
        report.addAll(comparisons(reference, decoded));
        Decoded stream = decode(ImageIo.readHex());
        Encoding repaired = repair(stream);
        report.addAll(streamReport(stream, repaired, decode(repaired.data)));
        ImageIo.text("rate_distortion.csv", rate);
        ImageIo.writeImage("decoded.ppm", decoded.image);
        ImageIo.writeHex("bitstream.hex", reference.data);
        ImageIo.writeImage("thumbnail.ppm", thumbnail(decoded));
        ImageIo.text("huffman_tables.txt", huffmanLines(reference));
        ImageIo.text("blocks.txt", blocks);
        ImageIo.writeImage("stream_decoded.ppm", stream.image);
        ImageIo.writeHex("repaired.hex", repaired.data);
        ImageIo.text("report.txt", report);
    }
}
