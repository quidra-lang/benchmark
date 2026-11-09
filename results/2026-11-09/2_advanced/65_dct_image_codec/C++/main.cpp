#include "codec.hpp"
struct Component {
    int identifier = 0, h = 0, v = 0, tq = 0, td = 0, ta = 0;
};
struct Block {
    int mcu, component, bx, by;
};
struct Interval {
    int first, count;
};
struct Layout {
    int width = 0, height = 0, restart = 0, hmax = 0, vmax = 0, mx = 0, my = 0, mcus = 0,
        blocks_per_mcu = 0;
    std::array<Component, 3> components{};
    std::array<Key, 3> factors{};
    std::vector<Block> blocks;
    std::vector<Interval> intervals;
    Layout() = default;
    Layout(int width, int height, std::array<Component, 3> components, int restart)
        : width(width), height(height), restart(restart), components(components) {
        for (int k = 0; k < 3; ++k) {
            factors[k] = {components[k].h, components[k].v};
            hmax = std::max(hmax, components[k].h);
            vmax = std::max(vmax, components[k].v);
            blocks_per_mcu += components[k].h * components[k].v;
        }
        mx = (width + 8 * hmax - 1) / (8 * hmax);
        my = (height + 8 * vmax - 1) / (8 * vmax);
        mcus = mx * my;
        for (int mcu = 0; mcu < mcus; ++mcu)
            for (int k = 0; k < 3; ++k)
                for (int v = 0; v < components[k].v; ++v)
                    for (int h = 0; h < components[k].h; ++h)
                        blocks.push_back({mcu, k, components[k].h * (mcu % mx) + h,
                                          components[k].v * (mcu / mx) + v});
        int step = restart ? restart : mcus;
        for (int first = 0; first < mcus; first += step)
            intervals.push_back({first, std::min(step, mcus - first)});
    }
};
static std::array<Component, 3> standard_components(int h, int v) {
    return {{{1, h, v, 0, 0, 0}, {2, 1, 1, 1, 1, 1}, {3, 1, 1, 1, 1, 1}}};
}
struct Prepared {
    Layout layout;
    std::array<Plane, 3> planes;
    Quantization quantization;
    std::vector<Sequence> coefficients;
};
struct Symbol {
    Key table;
    int value, extra, width;
};
struct Encoded {
    Prepared prepared;
    Tables tables;
    Frequencies frequencies;
    std::vector<I> differences;
    std::vector<int> block_bits;
    std::vector<std::array<int, 4>> intervals;
    Bytes data;
    int header_bytes = 0, scan_bytes = 0, padding = 0, stuffed = 0;
};
struct Segment {
    int position;
    std::string name;
    int length;
};
struct Decoded {
    Layout layout;
    Quantization quantization;
    Tables tables;
    std::vector<Sequence> coefficients;
    std::array<Plane, 3> planes, full_planes;
    Image image;
    std::vector<Segment> segments;
    std::vector<std::string> states;
    int scan_start = 0, scan_bytes = 0;
};
static void append(Bytes &first, const Bytes &second) {
    first.insert(first.end(), second.begin(), second.end());
}
static void word(Bytes &bytes, int value) {
    bytes.push_back(value / 256);
    bytes.push_back(value % 256);
}
static int read_word(const Bytes &bytes, int position) {
    return 256 * bytes[position] + bytes[position + 1];
}
static Bytes segment(int marker, const Bytes &contents) {
    Bytes out{255, marker};
    word(out, int(contents.size()) + 2);
    append(out, contents);
    return out;
}
static int read_symbol(BitReader &reader, const Huffman &table) {
    int code = 0;
    for (int length = 1; length <= 16; ++length) {
        code = 2 * code + reader.bit();
        for (int symbol : table.symbols)
            if (table.lengths[symbol] == length && table.codes[symbol] == code)
                return symbol;
    }
    throw DecodeError{"code"};
}
static Sequence decode_block(BitReader &reader, int index, Component component,
                             const Tables &tables, std::array<I, 3> &predictors) {
    Sequence out{};
    int size = read_symbol(reader, tables.at({0, component.td}));
    I difference = amplitude(reader.read(size), size);
    predictors[index] += difference;
    out[0] = predictors[index];
    int i = 1;
    while (i <= 63) {
        int symbol = read_symbol(reader, tables.at({1, component.ta}));
        if (symbol == 0)
            break;
        int run = symbol / 16, width = symbol % 16;
        i += run;
        if (i > 63)
            throw DecodeError{"index"};
        if (width > 0)
            out[i] = amplitude(reader.read(width), width);
        ++i;
    }
    return out;
}
class Codec {
    const SourceTables &source;
    Bytes header(const Prepared &prepared, const Tables &tables) const {
        const Layout &layout = prepared.layout;
        Bytes out{255, 0xd8}, contents;
        for (int id = 0; id < 2; ++id) {
            contents.push_back(id);
            for (I value : zigzag(prepared.quantization.at(id)))
                contents.push_back(int(value));
        }
        append(out, segment(0xdb, contents));
        contents = {8};
        word(contents, layout.height);
        word(contents, layout.width);
        contents.push_back(3);
        for (Component component : layout.components) {
            contents.push_back(component.identifier);
            contents.push_back(16 * component.h + component.v);
            contents.push_back(component.tq);
        }
        append(out, segment(0xc0, contents));
        contents.clear();
        for (Key key : table_keys) {
            const Huffman &table = tables.at(key);
            contents.push_back(16 * key.first + key.second);
            contents.insert(contents.end(), table.counts.begin(), table.counts.end());
            append(contents, table.symbols);
        }
        append(out, segment(0xc4, contents));
        if (layout.restart) {
            contents.clear();
            word(contents, layout.restart);
            append(out, segment(0xdd, contents));
        }
        contents = {3};
        for (Component component : layout.components) {
            contents.push_back(component.identifier);
            contents.push_back(16 * component.td + component.ta);
        }
        append(contents, {0, 63, 0});
        append(out, segment(0xda, contents));
        return out;
    }
    void restore(Decoded &decoded) const {
        const Layout &layout = decoded.layout;
        for (int k = 0; k < 3; ++k) {
            decoded.planes[k] = {
                8 * layout.components[k].h * layout.mx, 8 * layout.components[k].v * layout.my, {}};
            decoded.planes[k].pixels.resize(decoded.planes[k].width * decoded.planes[k].height);
        }
        for (int number = 0; number < int(layout.blocks.size()); ++number) {
            Block block = layout.blocks[number];
            Matrix values = inverse_dct(
                dequantize(decoded.coefficients[number],
                           decoded.quantization.at(layout.components[block.component].tq)),
                source.transform);
            Plane &plane = decoded.planes[block.component];
            for (int y = 0; y < 8; ++y)
                for (int x = 0; x < 8; ++x)
                    plane.pixels[(8 * block.by + y) * plane.width + 8 * block.bx + x] =
                        values[y][x];
        }
        decoded.full_planes = upsample(decoded.planes, layout.factors, layout.width, layout.height);
        decoded.image = combine_rgb(decoded.full_planes);
    }

  public:
    explicit Codec(const SourceTables &source) : source(source) {}
    Prepared prepare(const Image &image, int quality, int sampling, int restart) const {
        int h = sampling == 444 ? 1 : 2, v = sampling == 420 ? 2 : 1;
        Prepared out;
        out.layout = Layout(image.width, image.height, standard_components(h, v), restart);
        out.planes =
            component_planes(split_planes(image), out.layout.factors, out.layout.mx, out.layout.my);
        out.quantization = quantization_tables(source.basic, quality);
        for (Block block : out.layout.blocks) {
            const Plane &plane = out.planes[block.component];
            Matrix values{};
            for (int y = 0; y < 8; ++y)
                for (int x = 0; x < 8; ++x)
                    values[y][x] =
                        plane.pixels[(8 * block.by + y) * plane.width + 8 * block.bx + x];
            out.coefficients.push_back(zigzag(quantize(
                forward(values, source.transform), out.quantization.at(block.component ? 1 : 0))));
        }
        return out;
    }
    Encoded encode_prepared(const Prepared &prepared, bool optimized) const {
        Encoded out;
        out.prepared = prepared;
        const Layout &layout = prepared.layout;
        for (Key key : table_keys)
            out.frequencies[key] = {};
        std::vector<std::vector<Symbol>> symbols(prepared.coefficients.size());
        out.differences.resize(symbols.size());
        for (Interval interval : layout.intervals) {
            std::array<I, 3> predictors{};
            for (int number = interval.first * layout.blocks_per_mcu;
                 number < (interval.first + interval.count) * layout.blocks_per_mcu; ++number) {
                Block block = layout.blocks[number];
                Component component = layout.components[block.component];
                const Sequence &sequence = prepared.coefficients[number];
                I difference = sequence[0] - predictors[block.component];
                predictors[block.component] = sequence[0];
                out.differences[number] = difference;
                Key extra = extra_bits(difference);
                std::vector<Symbol> &block_symbols = symbols[number];
                block_symbols.push_back(
                    {{0, component.td}, extra.second, extra.first, extra.second});
                int run = 0;
                for (int i = 1; i < 64; ++i) {
                    I value = sequence[i];
                    if (!value) {
                        ++run;
                        continue;
                    }
                    while (run >= 16) {
                        block_symbols.push_back({{1, component.ta}, 0xf0, 0, 0});
                        run -= 16;
                    }
                    extra = extra_bits(value);
                    block_symbols.push_back(
                        {{1, component.ta}, 16 * run + extra.second, extra.first, extra.second});
                    run = 0;
                }
                if (run)
                    block_symbols.push_back({{1, component.ta}, 0, 0, 0});
                for (Symbol symbol : block_symbols)
                    ++out.frequencies[symbol.table][symbol.value];
            }
        }
        for (Key key : table_keys)
            out.tables[key] =
                optimized ? optimized_table(out.frequencies[key]) : source.huffman.at(key);
        Bytes header_bytes = header(prepared, out.tables);
        BitWriter writer;
        out.block_bits.assign(symbols.size(), 0);
        for (int j = 0; j < int(layout.intervals.size()); ++j) {
            Interval interval = layout.intervals[j];
            if (j > 0)
                writer.restart(j - 1);
            int start = int(writer.data.size());
            for (int number = interval.first * layout.blocks_per_mcu;
                 number < (interval.first + interval.count) * layout.blocks_per_mcu; ++number)
                for (Symbol symbol : symbols[number]) {
                    const Huffman &table = out.tables.at(symbol.table);
                    writer.write(table.codes[symbol.value], table.lengths[symbol.value]);
                    writer.write(symbol.extra, symbol.width);
                    out.block_bits[number] += table.lengths[symbol.value] + symbol.width;
                }
            writer.pad();
            out.intervals.push_back({interval.first, interval.count,
                                     int(header_bytes.size()) + start,
                                     int(writer.data.size()) - start});
        }
        out.header_bytes = int(header_bytes.size());
        out.scan_bytes = int(writer.data.size());
        out.padding = writer.padding;
        out.stuffed = writer.stuffed;
        out.data = std::move(header_bytes);
        append(out.data, writer.data);
        append(out.data, {255, 0xd9});
        return out;
    }
    Encoded encode(const Image &image, int quality, int sampling, bool optimized,
                   int restart) const {
        return encode_prepared(prepare(image, quality, sampling, restart), optimized);
    }
    Decoded decode(const Bytes &bytes) const {
        Decoded out;
        int position = 2, width = 0, height = 0, restart = 0;
        std::array<Component, 3> components{};
        out.segments.push_back({0, "SOI", 0});
        while (true) {
            int marker = bytes[position + 1], length = read_word(bytes, position + 2),
                start = position + 4, end = position + length + 2;
            std::string name = marker >= 0xe0 && marker <= 0xef
                                   ? "APP" + std::to_string(marker - 0xe0)
                               : marker == 0xc0 ? "SOF0"
                               : marker == 0xc4 ? "DHT"
                               : marker == 0xdb ? "DQT"
                               : marker == 0xdd ? "DRI"
                               : marker == 0xda ? "SOS"
                                                : "COM";
            out.segments.push_back({position, name, length});
            if (marker == 0xdb) {
                for (int p = start; p < end; p += 65) {
                    int id = bytes[p];
                    Matrix table{};
                    const auto order = zigzag_order();
                    for (int i = 0; i < 64; ++i)
                        table[order[i].first][order[i].second] = bytes[p + 1 + i];
                    out.quantization[id] = table;
                }
            } else if (marker == 0xc4) {
                int p = start;
                while (p < end) {
                    int identifier = bytes[p++];
                    std::array<int, 16> counts{};
                    int total = 0;
                    for (int &count : counts) {
                        count = bytes[p++];
                        total += count;
                    }
                    Bytes symbols(bytes.begin() + p, bytes.begin() + p + total);
                    p += total;
                    out.tables[{identifier / 16, identifier % 16}] = Huffman(counts, symbols);
                }
            } else if (marker == 0xc0) {
                height = read_word(bytes, start + 1);
                width = read_word(bytes, start + 3);
                for (int k = 0; k < 3; ++k) {
                    int p = start + 6 + 3 * k;
                    components[k] = {
                        bytes[p], bytes[p + 1] / 16, bytes[p + 1] % 16, bytes[p + 2], 0, 0};
                }
            } else if (marker == 0xdd)
                restart = read_word(bytes, start);
            else if (marker == 0xda) {
                for (int k = 0; k < 3; ++k) {
                    int p = start + 1 + 2 * k;
                    components[k].td = bytes[p + 1] / 16;
                    components[k].ta = bytes[p + 1] % 16;
                }
            }
            position = end;
            if (marker == 0xda)
                break;
        }
        out.scan_start = position;
        out.scan_bytes = int(bytes.size()) - 2 - position;
        out.segments.push_back({int(bytes.size()) - 2, "EOI", 0});
        out.layout = Layout(width, height, components, restart);
        out.coefficients.resize(out.layout.blocks.size());
        out.states.assign(out.layout.intervals.size(), "lost");
        BitReader reader(bytes, position);
        int j = 0;
        while (j < int(out.layout.intervals.size())) {
            Interval interval = out.layout.intervals[j];
            int first = interval.first * out.layout.blocks_per_mcu,
                last = (interval.first + interval.count) * out.layout.blocks_per_mcu,
                mcu = interval.first;
            std::array<I, 3> predictors{};
            std::vector<Sequence> temporary;
            try {
                for (int number = first; number < last; ++number) {
                    Block block = out.layout.blocks[number];
                    mcu = block.mcu;
                    temporary.push_back(decode_block(reader, block.component,
                                                     components[block.component], out.tables,
                                                     predictors));
                }
                reader.discard();
                int expected = j + 1 < int(out.layout.intervals.size()) ? 0xd0 + j % 8 : 0xd9;
                if (bytes[reader.position] != 255 || bytes[reader.position + 1] != expected) {
                    mcu = interval.first + interval.count - 1;
                    throw DecodeError{"sync"};
                }
                std::copy(temporary.begin(), temporary.end(), out.coefficients.begin() + first);
                out.states[j] = "ok";
                reader.position += 2;
                ++j;
            } catch (const DecodeError &error) {
                int offset = reader.position;
                reader.discard();
                int resync = find_resync(bytes, offset);
                out.states[j] = "damaged " + error.kind + " mcu " + std::to_string(mcu) +
                                " offset " + std::to_string(offset) + " resync " +
                                std::to_string(resync);
                if (bytes[resync + 1] == 0xd9)
                    break;
                int marker = bytes[resync + 1] - 0xd0;
                int remainder = marker - j - 8 * int(floor_div(marker - j, 8));
                int next = j + 1 + remainder;
                reader.position = resync + 2;
                j = next;
            }
        }
        restore(out);
        return out;
    }
};
static std::string psnr(const std::vector<I> &a, const std::vector<I> &b) {
    I error = 0;
    for (int i = 0; i < int(a.size()); ++i) {
        I difference = a[i] - b[i];
        error += difference * difference;
    }
    if (!error)
        return "inf";
    double value = 10 * std::log10(65025.0 * double(a.size()) / double(error));
    std::ostringstream out;
    out << std::fixed << std::setprecision(2) << value;
    return out.str();
}
static std::vector<I> channels(const Image &image) {
    std::vector<I> out;
    out.reserve(3 * image.pixels.size());
    for (Pixel pixel : image.pixels)
        out.insert(out.end(), pixel.begin(), pixel.end());
    return out;
}
struct Quality {
    std::array<std::string, 3> planes;
    std::string rgb;
    I maximum = 0;
};
static Quality quality(const Image &original, const Decoded &decoded) {
    Quality out;
    const auto planes = split_planes(original);
    for (int k = 0; k < 3; ++k)
        out.planes[k] = psnr(planes[k].pixels, decoded.full_planes[k].pixels);
    const std::vector<I> before = channels(original), after = channels(decoded.image);
    out.rgb = psnr(before, after);
    for (int i = 0; i < int(before.size()); ++i)
        out.maximum = std::max(out.maximum, std::llabs(before[i] - after[i]));
    return out;
}
static std::string fraction(I a, I b) {
    I divisor = std::gcd(a, b);
    return std::to_string(a / divisor) + "/" + std::to_string(b / divisor);
}
static Matrix block_values(const Plane &plane, Block block) {
    Matrix out{};
    for (int y = 0; y < 8; ++y)
        for (int x = 0; x < 8; ++x)
            out[y][x] = plane.pixels[(8 * block.by + y) * plane.width + 8 * block.bx + x];
    return out;
}
static std::vector<I> block_errors(const Encoded &encoded, const Decoded &decoded) {
    std::vector<I> out;
    for (Block block : encoded.prepared.layout.blocks) {
        Matrix a = block_values(encoded.prepared.planes[block.component], block),
               b = block_values(decoded.planes[block.component], block);
        I sum = 0;
        for (int y = 0; y < 8; ++y)
            for (int x = 0; x < 8; ++x) {
                I difference = a[y][x] - b[y][x];
                sum += difference * difference;
            }
        out.push_back(sum);
    }
    return out;
}
static Image thumbnail(const Decoded &decoded) {
    const Layout &layout = decoded.layout;
    Image out{(layout.width + 7) / 8, (layout.height + 7) / 8, {}};
    out.pixels.resize(out.width * out.height);
    std::array<std::map<Key, I>, 3> dc;
    for (int i = 0; i < int(layout.blocks.size()); ++i) {
        Block block = layout.blocks[i];
        dc[block.component][{block.bx, block.by}] = decoded.coefficients[i][0];
    }
    for (int y = 0; y < out.height; ++y)
        for (int x = 0; x < out.width; ++x) {
            Pixel pixel{};
            for (int k = 0; k < 3; ++k) {
                Component component = layout.components[k];
                Key position{x * component.h / layout.hmax, y * component.v / layout.vmax};
                I value = dc[k].at(position), divisor = decoded.quantization.at(component.tq)[0][0];
                pixel[k] = clamp(floor_div(value * divisor + 4, 8) + 128);
            }
            out.pixels[y * out.width + x] = to_rgb(pixel);
        }
    return out;
}
static std::string hex_symbol(int value) {
    const char *digits = "0123456789abcdef";
    std::string out;
    out += digits[value / 16];
    out += digits[value % 16];
    return out;
}
static Lines huffman_report(const Encoded &encoded) {
    Lines out;
    for (int index = 0; index < 4; ++index) {
        Key key = table_keys[index];
        const Huffman &table = encoded.tables.at(key);
        const auto &frequencies = encoded.frequencies.at(key);
        I coded = 0, bits = 0;
        for (int symbol : table.symbols) {
            coded += frequencies[symbol];
            bits += frequencies[symbol] * table.lengths[symbol];
        }
        line(out, "table ", table_names[index], " class ", key.first, " id ", key.second,
             " symbols ", table.symbols.size(), " coded ", coded, " bits ", bits);
        std::string row = "counts";
        for (int count : table.counts)
            row += " " + std::to_string(count);
        out.push_back(row);
        for (int symbol : table.symbols) {
            std::string code;
            for (int bit = table.lengths[symbol] - 1; bit >= 0; --bit)
                code += ((table.codes[symbol] >> bit) & 1) ? '1' : '0';
            line(out, "symbol ", hex_symbol(symbol), " length ", table.lengths[symbol], " code ",
                 code, " count ", frequencies[symbol]);
        }
    }
    return out;
}
static const std::array<std::string, 3> component_names{"Y", "Cb", "Cr"};
static Lines blocks_report(const Encoded &encoded, const std::vector<I> &errors) {
    Lines out;
    line(out, "blocks ", encoded.prepared.layout.blocks.size());
    for (int number = 0; number < int(encoded.prepared.layout.blocks.size()); ++number) {
        Block block = encoded.prepared.layout.blocks[number];
        const Sequence &sequence = encoded.prepared.coefficients[number];
        int nonzero = 0, last = 0;
        for (int i = 1; i < 64; ++i)
            if (sequence[i]) {
                ++nonzero;
                last = i;
            }
        line(out, "block ", number, " ", component_names[block.component], " ", block.bx, " ",
             block.by, " dc ", sequence[0], " diff ", encoded.differences[number], " nonzero ",
             nonzero, " last ", last, " bits ", encoded.block_bits[number], " sse ",
             errors[number]);
    }
    return out;
}
static Lines reference_report(const Encoded &encoded, int sampling, int quality, bool optimized,
                              const std::vector<I> &errors) {
    const Layout &layout = encoded.prepared.layout;
    Lines out;
    line(out, "image ", layout.width, " ", layout.height);
    line(out, "sampling ", sampling, " mcu ", 8 * layout.hmax, " ", 8 * layout.vmax, " grid ",
         layout.mx, " ", layout.my);
    line(out, "padded ", 8 * layout.hmax * layout.mx, " ", 8 * layout.vmax * layout.my);
    std::array<I, 3> counts{}, bits{}, nonzero{}, sse{};
    std::array<I, 64> frequency{};
    I zero_ac = 0;
    for (int number = 0; number < int(layout.blocks.size()); ++number) {
        Block block = layout.blocks[number];
        ++counts[block.component];
        bits[block.component] += encoded.block_bits[number];
        sse[block.component] += errors[number];
        bool any = false;
        for (int i = 0; i < 64; ++i)
            if (encoded.prepared.coefficients[number][i]) {
                ++nonzero[block.component];
                ++frequency[i];
                if (i > 0)
                    any = true;
            }
        zero_ac += !any;
    }
    line(out, "blocks ", counts[0], " ", counts[1], " ", counts[2]);
    line(out, "restart_interval ", layout.restart, " markers ", layout.intervals.size() - 1);
    line(out, "huffman ", optimized ? "optimized" : "standard");
    line(out, "quality ", quality);
    for (int id = 0; id < 2; ++id) {
        std::string row = "quant " + std::to_string(id);
        for (I value : zigzag(encoded.prepared.quantization.at(id)))
            row += " " + std::to_string(value);
        out.push_back(row);
    }
    std::string symbols = "symbols";
    I eob = 0, zrl = 0;
    for (Key key : table_keys) {
        I count = 0;
        for (I value : encoded.frequencies.at(key))
            count += value;
        symbols += " " + std::to_string(count);
        if (key.first == 1) {
            eob += encoded.frequencies.at(key)[0];
            zrl += encoded.frequencies.at(key)[0xf0];
        }
    }
    out.push_back(symbols);
    line(out, "eob ", eob, " zrl ", zrl);
    line(out, "zero_ac_blocks ", zero_ac);
    std::string row = "nonzero";
    for (I value : frequency)
        row += " " + std::to_string(value);
    out.push_back(row);
    for (int k = 0; k < 3; ++k)
        line(out, "component ", component_names[k], " bits ", bits[k], " nonzero ", nonzero[k],
             " sse ", sse[k]);
    line(out, "padding_bits ", encoded.padding);
    line(out, "stuffed_bytes ", encoded.stuffed);
    line(out, "header_bytes ", encoded.header_bytes);
    line(out, "scan_bytes ", encoded.scan_bytes);
    line(out, "total_bytes ", encoded.data.size());
    for (int j = 0; j < int(encoded.intervals.size()); ++j) {
        const auto &interval = encoded.intervals[j];
        line(out, "interval ", j, " ", interval[0], " ", interval[1], " ", interval[2], " ",
             interval[3]);
    }
    return out;
}
int main() {
    const Image image = read_ppm("input/image.ppm");
    const Params p = read_params();
    const SourceTables source = read_tables();
    Codec codec(source);
    Lines rates{
        "quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error"};
    Encoded reference;
    Decoded reference_decoded;
    for (int index = 0; index < int(p.qualities.size()); ++index) {
        int q = p.qualities[index];
        const Prepared prepared = codec.prepare(image, q, p.sampling, p.restart);
        Encoded standard = codec.encode_prepared(prepared, false),
                optimized = codec.encode_prepared(prepared, true);
        Encoded selected = p.optimized ? optimized : standard;
        Decoded decoded = codec.decode(selected.data);
        Quality result = quality(image, decoded);
        line(rates, q, ",", standard.data.size(), ",", optimized.data.size(), ",",
             fraction(8 * I(selected.data.size()), image.width * image.height), ",",
             result.planes[0], ",", result.planes[1], ",", result.planes[2], ",", result.rgb, ",",
             result.maximum);
        if (index == 0) {
            reference = std::move(selected);
            reference_decoded = std::move(decoded);
        }
    }
    const std::vector<I> errors = block_errors(reference, reference_decoded);
    Lines report = reference_report(reference, p.sampling, p.qualities[0], p.optimized, errors);
    std::array<I, 8> histogram{};
    const std::vector<I> before = channels(image), after = channels(reference_decoded.image);
    for (int i = 0; i < int(before.size()); ++i) {
        I error = std::llabs(before[i] - after[i]);
        int bin = error == 0   ? 0
                  : error == 1 ? 1
                  : error < 4  ? 2
                  : error < 8  ? 3
                  : error < 16 ? 4
                  : error < 32 ? 5
                  : error < 64 ? 6
                               : 7;
        ++histogram[bin];
    }
    std::string histogram_line = "error_histogram";
    for (I value : histogram)
        histogram_line += " " + std::to_string(value);
    report.push_back(histogram_line);
    const auto original_planes = split_planes(image);
    for (int keep : p.truncate) {
        Plane plane = reference_decoded.planes[0];
        std::fill(plane.pixels.begin(), plane.pixels.end(), 0);
        for (int number = 0; number < int(reference_decoded.layout.blocks.size()); ++number) {
            Block block = reference_decoded.layout.blocks[number];
            if (block.component != 0)
                continue;
            Matrix values = inverse_dct(dequantize(reference_decoded.coefficients[number],
                                                   reference_decoded.quantization.at(
                                                       reference_decoded.layout.components[0].tq),
                                                   keep),
                                        source.transform);
            for (int y = 0; y < 8; ++y)
                for (int x = 0; x < 8; ++x)
                    plane.pixels[(8 * block.by + y) * plane.width + 8 * block.bx + x] =
                        values[y][x];
        }
        std::vector<I> cropped;
        for (int y = 0; y < image.height; ++y)
            for (int x = 0; x < image.width; ++x)
                cropped.push_back(plane.pixels[y * plane.width + x]);
        line(report, "truncate ", keep, " ", psnr(original_planes[0].pixels, cropped));
    }
    for (int sampling : {444, 422, 420}) {
        Encoded encoded = codec.encode(image, p.qualities[0], sampling, p.optimized, p.restart);
        Quality result = quality(image, codec.decode(encoded.data));
        line(report, "sampling_compare ", sampling, " ", encoded.data.size(), " ", result.planes[1],
             " ", result.planes[2], " ", result.rgb);
    }
    Image previous = image;
    for (int generation = 1; generation <= p.generations; ++generation) {
        Encoded encoded =
            codec.encode(previous, p.qualities[0], p.sampling, p.optimized, p.restart);
        Decoded decoded = codec.decode(encoded.data);
        int changed = 0;
        for (int i = 0; i < int(previous.pixels.size()); ++i)
            changed += previous.pixels[i] != decoded.image.pixels[i];
        line(report, "generation ", generation, " ", encoded.data.size(), " ",
             psnr(before, channels(decoded.image)), " ", changed);
        previous = std::move(decoded.image);
    }
    int lo = 1, hi = 100;
    while (lo < hi) {
        int mid = (lo + hi + 1) / 2;
        Encoded encoded = codec.encode(image, mid, p.sampling, p.optimized, p.restart);
        line(report, "rate_control_step ", mid, " ", encoded.data.size());
        if (int(encoded.data.size()) <= p.target)
            lo = mid;
        else
            hi = mid - 1;
    }
    const Encoded controlled = codec.encode(image, lo, p.sampling, p.optimized, p.restart);
    line(report, "rate_control ", lo, " ", controlled.data.size(), " ",
         int(controlled.data.size()) <= p.target ? "yes" : "no", " ",
         quality(image, codec.decode(controlled.data)).rgb);
    const Bytes stream = read_hex("input/stream.hex");
    const Decoded damaged = codec.decode(stream);
    for (const Segment &segment : damaged.segments)
        line(report, "stream_segment ", segment.position, " ", segment.name, " ", segment.length);
    line(report, "stream_image ", damaged.layout.width, " ", damaged.layout.height);
    for (Component component : damaged.layout.components)
        line(report, "stream_component ", component.identifier, " ", component.h, " ", component.v,
             " ", component.tq, " ", component.td, " ", component.ta);
    for (const auto &entry : damaged.quantization) {
        std::string row = "stream_quant " + std::to_string(entry.first);
        for (I value : zigzag(entry.second))
            row += " " + std::to_string(value);
        report.push_back(row);
    }
    for (const auto &entry : damaged.tables) {
        int longest = 0;
        for (int length = 1; length <= 16; ++length)
            if (entry.second.counts[length - 1])
                longest = length;
        line(report, "stream_huffman ", entry.first.first, " ", entry.first.second, " symbols ",
             entry.second.symbols.size(), " longest ", longest);
    }
    int ok = 0, damaged_count = 0, lost = 0;
    for (const std::string &state : damaged.states) {
        ok += state == "ok";
        lost += state == "lost";
        damaged_count += state.rfind("damaged ", 0) == 0;
    }
    line(report, "stream_restart ", damaged.layout.restart, " intervals ",
         damaged.layout.intervals.size(), " ok ", ok, " damaged ", damaged_count, " lost ", lost);
    for (int j = 0; j < int(damaged.states.size()); ++j) {
        Interval interval = damaged.layout.intervals[j];
        line(report, "stream_interval ", j, " ", interval.first, " ", interval.count, " ",
             damaged.states[j]);
    }
    line(report, "stream_scan_bytes ", damaged.scan_bytes);
    Prepared repair;
    repair.layout =
        Layout(damaged.layout.width, damaged.layout.height,
               standard_components(damaged.layout.components[0].h, damaged.layout.components[0].v),
               damaged.layout.restart);
    repair.quantization[0] = damaged.quantization.at(damaged.layout.components[0].tq);
    repair.quantization[1] = damaged.quantization.at(damaged.layout.components[1].tq);
    repair.coefficients = damaged.coefficients;
    const Encoded repaired = codec.encode_prepared(repair, true);
    const Decoded repaired_decoded = codec.decode(repaired.data);
    line(report, "repair ", repaired.data.size(), " ", repaired.header_bytes, " ",
         repaired.scan_bytes, " identical ",
         repaired_decoded.image.pixels == damaged.image.pixels ? "yes" : "no");
    std::filesystem::create_directories("output");
    save("rate_distortion.csv", rates);
    write_ppm("decoded.ppm", reference_decoded.image);
    write_hex("bitstream.hex", reference.data);
    write_ppm("thumbnail.ppm", thumbnail(reference_decoded));
    save("huffman_tables.txt", huffman_report(reference));
    save("blocks.txt", blocks_report(reference, errors));
    write_ppm("stream_decoded.ppm", damaged.image);
    write_hex("repaired.hex", repaired.data);
    save("report.txt", report);
}
