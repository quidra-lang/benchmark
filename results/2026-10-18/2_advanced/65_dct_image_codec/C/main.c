#include "codec.h"
typedef struct {
    int identifier, h, v, tq, td, ta;
} Component;
typedef struct {
    int mcu, component, bx, by;
} Block;
typedef struct {
    int first, count;
} Interval;
typedef struct {
    int width, height, restart, hmax, vmax, mx, my, mcus, blocks_per_mcu;
    Component components[3];
    Pair factors[3];
    Block *blocks;
    int block_count;
    Interval *intervals;
    int interval_count;
} Layout;
static Layout layout(int width, int height, const Component components[3], int restart_interval) {
    Layout out = {0};
    out.width = width;
    out.height = height;
    out.restart = restart_interval;
    memcpy(out.components, components, sizeof(out.components));
    for (int k = 0; k < 3; ++k) {
        out.factors[k] = (Pair){components[k].h, components[k].v};
        if (components[k].h > out.hmax)
            out.hmax = components[k].h;
        if (components[k].v > out.vmax)
            out.vmax = components[k].v;
        out.blocks_per_mcu += components[k].h * components[k].v;
    }
    out.mx = (width + 8 * out.hmax - 1) / (8 * out.hmax);
    out.my = (height + 8 * out.vmax - 1) / (8 * out.vmax);
    out.mcus = out.mx * out.my;
    out.blocks = allocate((size_t)(out.mcus * out.blocks_per_mcu), sizeof(Block));
    for (int mcu = 0; mcu < out.mcus; ++mcu)
        for (int k = 0; k < 3; ++k)
            for (int v = 0; v < components[k].v; ++v)
                for (int h = 0; h < components[k].h; ++h)
                    out.blocks[out.block_count++] =
                        (Block){mcu, k, components[k].h * (mcu % out.mx) + h,
                                components[k].v * (mcu / out.mx) + v};
    int step = restart_interval ? restart_interval : out.mcus;
    out.intervals = allocate((size_t)((out.mcus + step - 1) / step), sizeof(Interval));
    for (int first = 0; first < out.mcus; first += step)
        out.intervals[out.interval_count++] =
            (Interval){first, first + step < out.mcus ? step : out.mcus - first};
    return out;
}
static Layout standard_layout(int width, int height, int h, int v, int restart_interval) {
    Component components[3] = {{1, h, v, 0, 0, 0}, {2, 1, 1, 1, 1, 1}, {3, 1, 1, 1, 1, 1}};
    return layout(width, height, components, restart_interval);
}
typedef struct {
    Layout layout;
    Plane planes[3];
    Quantization quantization;
    Sequence *coefficients;
} Prepared;
typedef struct {
    Pair table;
    int value, extra, width;
} Symbol;
typedef struct {
    Symbol values[65];
    int count;
} Symbols;
typedef struct {
    Prepared *prepared;
    Tables tables;
    Frequencies frequencies;
    I *differences;
    int *block_bits;
    int (*intervals)[4];
    Bytes data;
    int header_bytes, scan_bytes, padding, stuffed;
} Encoded;
typedef struct {
    int position;
    char *name;
    int length;
} Segment;
typedef struct {
    Layout layout;
    Quantization quantization;
    Tables tables;
    Sequence *coefficients;
    Plane planes[3], full_planes[3];
    Image image;
    Segment *segments;
    int segment_count;
    char **states;
    int scan_start, scan_bytes;
} Decoded;
static void word(Bytes *bytes, int value) {
    byte(bytes, value / 256);
    byte(bytes, value % 256);
}
static int read_word(const Bytes *bytes, int position) {
    return 256 * bytes->data[position] + bytes->data[position + 1];
}
static void bytes(Bytes *out, const int *values, int count) {
    for (int i = 0; i < count; ++i)
        byte(out, values[i]);
}
static Bytes segment(int marker, Bytes contents) {
    Bytes out = {0};
    byte(&out, 255);
    byte(&out, marker);
    word(&out, contents.count + 2);
    append(&out, &contents);
    return out;
}
static int read_symbol(BitReader *reader, const Huffman *table) {
    int code = 0;
    for (int length = 1; length <= 16; ++length) {
        code = 2 * code + read_bit(reader);
        if (reader->error)
            return 0;
        for (int i = 0; i < table->symbol_count; ++i) {
            int symbol = table->symbols[i];
            if (table->lengths[symbol] == length && table->codes[symbol] == code)
                return symbol;
        }
    }
    reader->error = "code";
    return 0;
}
static bool decode_block(BitReader *reader, int index, Component component, const Tables *tables,
                         I predictors[3], Sequence *out) {
    memset(out, 0, sizeof(*out));
    int size = read_symbol(reader, &tables->values[0][component.td]);
    if (reader->error)
        return false;
    int bits = read_bits(reader, size);
    if (reader->error)
        return false;
    predictors[index] += amplitude(bits, size);
    out->values[0] = predictors[index];
    int i = 1;
    while (i <= 63) {
        int symbol = read_symbol(reader, &tables->values[1][component.ta]);
        if (reader->error)
            return false;
        if (symbol == 0)
            break;
        int run = symbol / 16, width = symbol % 16;
        i += run;
        if (i > 63) {
            reader->error = "index";
            return false;
        }
        if (width > 0) {
            bits = read_bits(reader, width);
            if (reader->error)
                return false;
            out->values[i] = amplitude(bits, width);
        }
        ++i;
    }
    return true;
}
static Bytes header(const Prepared *prepared, const Tables *tables) {
    const Layout *layout = &prepared->layout;
    Bytes out = {0}, contents = {0};
    byte(&out, 255);
    byte(&out, 0xd8);
    for (int id = 0; id < 2; ++id) {
        byte(&contents, id);
        Sequence sequence = zigzag(prepared->quantization.values[id]);
        for (int k = 0; k < 64; ++k)
            byte(&contents, (int)sequence.values[k]);
    }
    Bytes part = segment(0xdb, contents);
    append(&out, &part);
    contents = (Bytes){0};
    byte(&contents, 8);
    word(&contents, layout->height);
    word(&contents, layout->width);
    byte(&contents, 3);
    for (int k = 0; k < 3; ++k) {
        Component component = layout->components[k];
        byte(&contents, component.identifier);
        byte(&contents, 16 * component.h + component.v);
        byte(&contents, component.tq);
    }
    part = segment(0xc0, contents);
    append(&out, &part);
    contents = (Bytes){0};
    for (int i = 0; i < 4; ++i) {
        Pair key = table_keys[i];
        const Huffman *table = &tables->values[key.first][key.second];
        byte(&contents, 16 * key.first + key.second);
        bytes(&contents, table->counts, 16);
        bytes(&contents, table->symbols, table->symbol_count);
    }
    part = segment(0xc4, contents);
    append(&out, &part);
    if (layout->restart) {
        contents = (Bytes){0};
        word(&contents, layout->restart);
        part = segment(0xdd, contents);
        append(&out, &part);
    }
    contents = (Bytes){0};
    byte(&contents, 3);
    for (int k = 0; k < 3; ++k) {
        Component component = layout->components[k];
        byte(&contents, component.identifier);
        byte(&contents, 16 * component.td + component.ta);
    }
    int tail[3] = {0, 63, 0};
    bytes(&contents, tail, 3);
    part = segment(0xda, contents);
    append(&out, &part);
    return out;
}
static void restore(Decoded *decoded, const SourceTables *source) {
    const Layout *layout = &decoded->layout;
    for (int k = 0; k < 3; ++k) {
        int width = 8 * layout->components[k].h * layout->mx,
            height = 8 * layout->components[k].v * layout->my;
        decoded->planes[k] = (Plane){width, height, allocate((size_t)(width * height), sizeof(I))};
    }
    for (int number = 0; number < layout->block_count; ++number) {
        Block block = layout->blocks[number];
        Matrix values = inverse_dct(
            dequantize(decoded->coefficients[number],
                       decoded->quantization.values[layout->components[block.component].tq], 64),
            source->transform);
        Plane *plane = &decoded->planes[block.component];
        for (int y = 0; y < 8; ++y)
            for (int x = 0; x < 8; ++x)
                plane->pixels[(8 * block.by + y) * plane->width + 8 * block.bx + x] =
                    values.values[y][x];
    }
    upsample(decoded->planes, layout->factors, layout->width, layout->height, decoded->full_planes);
    decoded->image = combine_rgb(decoded->full_planes);
}
static Prepared *prepare(Image image, int quality, int sampling, int restart_interval,
                         const SourceTables *source) {
    int h = sampling == 444 ? 1 : 2, v = sampling == 420 ? 2 : 1;
    Prepared *out = allocate(1, sizeof(Prepared));
    out->layout = standard_layout(image.width, image.height, h, v, restart_interval);
    Plane original[3];
    split_planes(image, original);
    component_planes(original, out->layout.factors, out->layout.mx, out->layout.my, out->planes);
    out->quantization = quantization_tables(source->basic, quality);
    out->coefficients = allocate((size_t)out->layout.block_count, sizeof(Sequence));
    for (int number = 0; number < out->layout.block_count; ++number) {
        Block block = out->layout.blocks[number];
        Plane plane = out->planes[block.component];
        Matrix values = {0};
        for (int y = 0; y < 8; ++y)
            for (int x = 0; x < 8; ++x)
                values.values[y][x] =
                    plane.pixels[(8 * block.by + y) * plane.width + 8 * block.bx + x];
        out->coefficients[number] = zigzag(quantize(
            forward(values, source->transform), out->quantization.values[block.component ? 1 : 0]));
    }
    return out;
}
static Encoded *encode_prepared(Prepared *prepared, bool optimized, const SourceTables *source) {
    Encoded *out = allocate(1, sizeof(Encoded));
    out->prepared = prepared;
    const Layout *layout = &prepared->layout;
    Symbols *symbols = allocate((size_t)layout->block_count, sizeof(Symbols));
    out->differences = allocate((size_t)layout->block_count, sizeof(I));
    for (int j = 0; j < layout->interval_count; ++j) {
        Interval interval = layout->intervals[j];
        I predictors[3] = {0};
        for (int number = interval.first * layout->blocks_per_mcu;
             number < (interval.first + interval.count) * layout->blocks_per_mcu; ++number) {
            Block block = layout->blocks[number];
            Component component = layout->components[block.component];
            Sequence sequence = prepared->coefficients[number];
            I difference = sequence.values[0] - predictors[block.component];
            predictors[block.component] = sequence.values[0];
            out->differences[number] = difference;
            Pair extra = extra_bits(difference);
            Symbols *block_symbols = &symbols[number];
            block_symbols->values[block_symbols->count++] =
                (Symbol){{0, component.td}, extra.second, extra.first, extra.second};
            int run = 0;
            for (int i = 1; i < 64; ++i) {
                I value = sequence.values[i];
                if (!value) {
                    ++run;
                    continue;
                }
                while (run >= 16) {
                    block_symbols->values[block_symbols->count++] =
                        (Symbol){{1, component.ta}, 0xf0, 0, 0};
                    run -= 16;
                }
                extra = extra_bits(value);
                block_symbols->values[block_symbols->count++] =
                    (Symbol){{1, component.ta}, 16 * run + extra.second, extra.first, extra.second};
                run = 0;
            }
            if (run)
                block_symbols->values[block_symbols->count++] =
                    (Symbol){{1, component.ta}, 0, 0, 0};
            for (int i = 0; i < block_symbols->count; ++i) {
                Symbol symbol = block_symbols->values[i];
                ++out->frequencies.values[symbol.table.first][symbol.table.second][symbol.value];
            }
        }
    }
    for (int i = 0; i < 4; ++i) {
        Pair key = table_keys[i];
        out->tables.values[key.first][key.second] =
            optimized ? optimized_table(out->frequencies.values[key.first][key.second])
                      : source->huffman.values[key.first][key.second];
    }
    Bytes header_bytes = header(prepared, &out->tables);
    BitWriter writer = {0};
    out->block_bits = allocate((size_t)layout->block_count, sizeof(int));
    out->intervals = allocate((size_t)layout->interval_count, sizeof(*out->intervals));
    for (int j = 0; j < layout->interval_count; ++j) {
        Interval interval = layout->intervals[j];
        if (j > 0)
            restart(&writer, j - 1);
        int start = writer.data.count;
        for (int number = interval.first * layout->blocks_per_mcu;
             number < (interval.first + interval.count) * layout->blocks_per_mcu; ++number)
            for (int i = 0; i < symbols[number].count; ++i) {
                Symbol symbol = symbols[number].values[i];
                const Huffman *table = &out->tables.values[symbol.table.first][symbol.table.second];
                write_bits(&writer, table->codes[symbol.value], table->lengths[symbol.value]);
                write_bits(&writer, symbol.extra, symbol.width);
                out->block_bits[number] += table->lengths[symbol.value] + symbol.width;
            }
        pad(&writer);
        out->intervals[j][0] = interval.first;
        out->intervals[j][1] = interval.count;
        out->intervals[j][2] = header_bytes.count + start;
        out->intervals[j][3] = writer.data.count - start;
    }
    out->header_bytes = header_bytes.count;
    out->scan_bytes = writer.data.count;
    out->padding = writer.padding;
    out->stuffed = writer.stuffed;
    out->data = header_bytes;
    append(&out->data, &writer.data);
    byte(&out->data, 255);
    byte(&out->data, 0xd9);
    return out;
}
static Encoded *encode(Image image, int quality, int sampling, bool optimized, int restart_interval,
                       const SourceTables *source) {
    return encode_prepared(prepare(image, quality, sampling, restart_interval, source), optimized,
                           source);
}
static Decoded *decode(const Bytes *data, const SourceTables *source) {
    Decoded *out = allocate(1, sizeof(Decoded));
    int position = 2, width = 0, height = 0, restart_interval = 0;
    Component components[3] = {0};
    out->segments = allocate((size_t)data->count / 4 + 2, sizeof(Segment));
    out->segments[out->segment_count++] = (Segment){0, "SOI", 0};
    while (true) {
        int marker = data->data[position + 1], length = read_word(data, position + 2),
            start = position + 4, end = position + length + 2;
        char *name = marker >= 0xe0 && marker <= 0xef ? format("APP%d", marker - 0xe0)
                     : marker == 0xc0                 ? "SOF0"
                     : marker == 0xc4                 ? "DHT"
                     : marker == 0xdb                 ? "DQT"
                     : marker == 0xdd                 ? "DRI"
                     : marker == 0xda                 ? "SOS"
                                                      : "COM";
        out->segments[out->segment_count++] = (Segment){position, name, length};
        if (marker == 0xdb) {
            for (int p = start; p < end; p += 65) {
                int id = data->data[p];
                Matrix table = {0};
                Pair order[64];
                zigzag_order(order);
                for (int i = 0; i < 64; ++i)
                    table.values[order[i].first][order[i].second] = data->data[p + 1 + i];
                out->quantization.values[id] = table;
                out->quantization.defined[id] = true;
            }
        } else if (marker == 0xc4) {
            int p = start;
            while (p < end) {
                int identifier = data->data[p++], counts[16], symbols[256], total = 0;
                for (int i = 0; i < 16; ++i) {
                    counts[i] = data->data[p++];
                    total += counts[i];
                }
                for (int i = 0; i < total; ++i)
                    symbols[i] = data->data[p++];
                out->tables.values[identifier / 16][identifier % 16] =
                    huffman(counts, symbols, total);
            }
        } else if (marker == 0xc0) {
            height = read_word(data, start + 1);
            width = read_word(data, start + 3);
            for (int k = 0; k < 3; ++k) {
                int p = start + 6 + 3 * k;
                components[k] = (Component){data->data[p],
                                            data->data[p + 1] / 16,
                                            data->data[p + 1] % 16,
                                            data->data[p + 2],
                                            0,
                                            0};
            }
        } else if (marker == 0xdd)
            restart_interval = read_word(data, start);
        else if (marker == 0xda) {
            for (int k = 0; k < 3; ++k) {
                int p = start + 1 + 2 * k;
                components[k].td = data->data[p + 1] / 16;
                components[k].ta = data->data[p + 1] % 16;
            }
        }
        position = end;
        if (marker == 0xda)
            break;
    }
    out->scan_start = position;
    out->scan_bytes = data->count - 2 - position;
    out->segments[out->segment_count++] = (Segment){data->count - 2, "EOI", 0};
    out->layout = layout(width, height, components, restart_interval);
    const Layout *layout = &out->layout;
    out->coefficients = allocate((size_t)layout->block_count, sizeof(Sequence));
    out->states = allocate((size_t)layout->interval_count, sizeof(char *));
    for (int i = 0; i < layout->interval_count; ++i)
        out->states[i] = "lost";
    BitReader reader = {data, position, 0, 0, NULL};
    int j = 0;
    while (j < layout->interval_count) {
        Interval interval = layout->intervals[j];
        int first = interval.first * layout->blocks_per_mcu,
            last = (interval.first + interval.count) * layout->blocks_per_mcu, mcu = interval.first;
        I predictors[3] = {0};
        Sequence temporary[192];
        reader.error = NULL;
        for (int number = first; number < last; ++number) {
            Block block = layout->blocks[number];
            mcu = block.mcu;
            if (!decode_block(&reader, block.component, components[block.component], &out->tables,
                              predictors, &temporary[number - first]))
                break;
        }
        if (!reader.error) {
            discard(&reader);
            int expected = j + 1 < layout->interval_count ? 0xd0 + j % 8 : 0xd9;
            if (data->data[reader.position] != 255 || data->data[reader.position + 1] != expected) {
                mcu = interval.first + interval.count - 1;
                reader.error = "sync";
            }
        }
        if (!reader.error) {
            memcpy(out->coefficients + first, temporary, (size_t)(last - first) * sizeof(Sequence));
            out->states[j] = "ok";
            reader.position += 2;
            ++j;
        } else {
            int offset = reader.position;
            discard(&reader);
            int resync = find_resync(data, offset);
            out->states[j] =
                format("damaged %s mcu %d offset %d resync %d", reader.error, mcu, offset, resync);
            if (data->data[resync + 1] == 0xd9)
                break;
            int marker = data->data[resync + 1] - 0xd0,
                remainder = marker - j - 8 * (int)floor_div(marker - j, 8);
            reader.position = resync + 2;
            j = j + 1 + remainder;
        }
    }
    restore(out, source);
    return out;
}
static char *psnr(const I *a, const I *b, int count) {
    I error = 0;
    for (int i = 0; i < count; ++i) {
        I difference = a[i] - b[i];
        error += difference * difference;
    }
    return error ? format("%.2f", 10 * log10(65025.0 * count / (double)error)) : "inf";
}
static I *channels(Image image) {
    I *out = allocate((size_t)(3 * image.width * image.height), sizeof(I));
    for (int i = 0; i < image.width * image.height; ++i)
        for (int c = 0; c < 3; ++c)
            out[3 * i + c] = image.pixels[i].values[c];
    return out;
}
typedef struct {
    char *planes[3], *rgb;
    I maximum;
} Quality;
static Quality quality(Image original, const Decoded *decoded) {
    Quality out = {0};
    Plane planes[3];
    split_planes(original, planes);
    for (int k = 0; k < 3; ++k)
        out.planes[k] = psnr(planes[k].pixels, decoded->full_planes[k].pixels,
                             original.width * original.height);
    I *before = channels(original), *after = channels(decoded->image);
    int count = 3 * original.width * original.height;
    out.rgb = psnr(before, after, count);
    for (int i = 0; i < count; ++i) {
        I difference = llabs(before[i] - after[i]);
        if (difference > out.maximum)
            out.maximum = difference;
    }
    return out;
}
static char *fraction(I a, I b) {
    I x = a, y = b;
    while (y) {
        I next = x % y;
        x = y;
        y = next;
    }
    return format("%lld/%lld", a / x, b / x);
}
static Matrix block_values(Plane plane, Block block) {
    Matrix out = {0};
    for (int y = 0; y < 8; ++y)
        for (int x = 0; x < 8; ++x)
            out.values[y][x] = plane.pixels[(8 * block.by + y) * plane.width + 8 * block.bx + x];
    return out;
}
static I *block_errors(const Encoded *encoded, const Decoded *decoded) {
    int count = encoded->prepared->layout.block_count;
    I *out = allocate((size_t)count, sizeof(I));
    for (int number = 0; number < count; ++number) {
        Block block = encoded->prepared->layout.blocks[number];
        Matrix a = block_values(encoded->prepared->planes[block.component], block),
               b = block_values(decoded->planes[block.component], block);
        for (int y = 0; y < 8; ++y)
            for (int x = 0; x < 8; ++x) {
                I difference = a.values[y][x] - b.values[y][x];
                out[number] += difference * difference;
            }
    }
    return out;
}
static Image thumbnail(const Decoded *decoded) {
    const Layout *layout = &decoded->layout;
    Image out = {(layout->width + 7) / 8, (layout->height + 7) / 8, NULL};
    out.pixels = allocate((size_t)(out.width * out.height), sizeof(Pixel));
    I dc[3][8][8] = {0};
    for (int i = 0; i < layout->block_count; ++i) {
        Block block = layout->blocks[i];
        dc[block.component][block.by][block.bx] = decoded->coefficients[i].values[0];
    }
    for (int y = 0; y < out.height; ++y)
        for (int x = 0; x < out.width; ++x) {
            Pixel pixel = {0};
            for (int k = 0; k < 3; ++k) {
                Component component = layout->components[k];
                int bx = x * component.h / layout->hmax, by = y * component.v / layout->vmax;
                I value = dc[k][by][bx],
                  divisor = decoded->quantization.values[component.tq].values[0][0];
                pixel.values[k] = clamp(floor_div(value * divisor + 4, 8) + 128);
            }
            out.pixels[y * out.width + x] = to_rgb(pixel);
        }
    return out;
}
static Lines huffman_report(const Encoded *encoded) {
    Lines out = {0};
    for (int index = 0; index < 4; ++index) {
        Pair key = table_keys[index];
        const Huffman *table = &encoded->tables.values[key.first][key.second];
        const I *frequencies = encoded->frequencies.values[key.first][key.second];
        I coded = 0, bits = 0;
        for (int i = 0; i < table->symbol_count; ++i) {
            int symbol = table->symbols[i];
            coded += frequencies[symbol];
            bits += frequencies[symbol] * table->lengths[symbol];
        }
        line(&out, "table %s class %d id %d symbols %d coded %lld bits %lld", table_names[index],
             key.first, key.second, table->symbol_count, coded, bits);
        char *row = "counts";
        for (int i = 0; i < 16; ++i)
            row = joined(row, format(" %d", table->counts[i]));
        line(&out, "%s", row);
        for (int i = 0; i < table->symbol_count; ++i) {
            int symbol = table->symbols[i], length = table->lengths[symbol];
            char code[17];
            for (int bit = length - 1; bit >= 0; --bit)
                code[length - 1 - bit] = ((table->codes[symbol] >> bit) & 1) ? '1' : '0';
            code[length] = 0;
            line(&out, "symbol %02x length %d code %s count %lld", symbol, length, code,
                 frequencies[symbol]);
        }
    }
    return out;
}
static const char *component_names[3] = {"Y", "Cb", "Cr"};
static Lines blocks_report(const Encoded *encoded, const I *errors) {
    Lines out = {0};
    const Layout *layout = &encoded->prepared->layout;
    line(&out, "blocks %d", layout->block_count);
    for (int number = 0; number < layout->block_count; ++number) {
        Block block = layout->blocks[number];
        Sequence sequence = encoded->prepared->coefficients[number];
        int nonzero = 0, last = 0;
        for (int i = 1; i < 64; ++i)
            if (sequence.values[i]) {
                ++nonzero;
                last = i;
            }
        line(&out, "block %d %s %d %d dc %lld diff %lld nonzero %d last %d bits %d sse %lld",
             number, component_names[block.component], block.bx, block.by, sequence.values[0],
             encoded->differences[number], nonzero, last, encoded->block_bits[number],
             errors[number]);
    }
    return out;
}
static Lines reference_report(const Encoded *encoded, int sampling, int quality_value,
                              bool optimized, const I *errors) {
    const Layout *layout = &encoded->prepared->layout;
    Lines out = {0};
    line(&out, "image %d %d", layout->width, layout->height);
    line(&out, "sampling %d mcu %d %d grid %d %d", sampling, 8 * layout->hmax, 8 * layout->vmax,
         layout->mx, layout->my);
    line(&out, "padded %d %d", 8 * layout->hmax * layout->mx, 8 * layout->vmax * layout->my);
    I counts[3] = {0}, bits[3] = {0}, nonzero[3] = {0}, sse[3] = {0}, frequency[64] = {0},
      zero_ac = 0;
    for (int number = 0; number < layout->block_count; ++number) {
        Block block = layout->blocks[number];
        ++counts[block.component];
        bits[block.component] += encoded->block_bits[number];
        sse[block.component] += errors[number];
        bool any = false;
        for (int i = 0; i < 64; ++i)
            if (encoded->prepared->coefficients[number].values[i]) {
                ++nonzero[block.component];
                ++frequency[i];
                if (i > 0)
                    any = true;
            }
        zero_ac += !any;
    }
    line(&out, "blocks %lld %lld %lld", counts[0], counts[1], counts[2]);
    line(&out, "restart_interval %d markers %d", layout->restart, layout->interval_count - 1);
    line(&out, "huffman %s", optimized ? "optimized" : "standard");
    line(&out, "quality %d", quality_value);
    for (int id = 0; id < 2; ++id) {
        char *row = format("quant %d", id);
        Sequence sequence = zigzag(encoded->prepared->quantization.values[id]);
        for (int i = 0; i < 64; ++i)
            row = joined(row, format(" %lld", sequence.values[i]));
        line(&out, "%s", row);
    }
    char *symbols = "symbols";
    I eob = 0, zrl = 0;
    for (int i = 0; i < 4; ++i) {
        Pair key = table_keys[i];
        const I *values = encoded->frequencies.values[key.first][key.second];
        I count = 0;
        for (int symbol = 0; symbol < 256; ++symbol)
            count += values[symbol];
        symbols = joined(symbols, format(" %lld", count));
        if (key.first == 1) {
            eob += values[0];
            zrl += values[0xf0];
        }
    }
    line(&out, "%s", symbols);
    line(&out, "eob %lld zrl %lld", eob, zrl);
    line(&out, "zero_ac_blocks %lld", zero_ac);
    char *row = "nonzero";
    for (int i = 0; i < 64; ++i)
        row = joined(row, format(" %lld", frequency[i]));
    line(&out, "%s", row);
    for (int k = 0; k < 3; ++k)
        line(&out, "component %s bits %lld nonzero %lld sse %lld", component_names[k], bits[k],
             nonzero[k], sse[k]);
    line(&out, "padding_bits %d", encoded->padding);
    line(&out, "stuffed_bytes %d", encoded->stuffed);
    line(&out, "header_bytes %d", encoded->header_bytes);
    line(&out, "scan_bytes %d", encoded->scan_bytes);
    line(&out, "total_bytes %d", encoded->data.count);
    for (int j = 0; j < layout->interval_count; ++j)
        line(&out, "interval %d %d %d %d %d", j, encoded->intervals[j][0], encoded->intervals[j][1],
             encoded->intervals[j][2], encoded->intervals[j][3]);
    return out;
}
int main(void) {
    Image image = read_ppm("input/image.ppm");
    Params p = read_params();
    const SourceTables *source = read_tables();
    Lines rates = {0};
    line(&rates,
         "quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error");
    Encoded *reference = NULL;
    Decoded *reference_decoded = NULL;
    for (int index = 0; index < p.quality_count; ++index) {
        int q = p.qualities[index];
        Prepared *prepared = prepare(image, q, p.sampling, p.restart, source);
        Encoded *standard = encode_prepared(prepared, false, source),
                *optimized = encode_prepared(prepared, true, source),
                *selected = p.optimized ? optimized : standard;
        Decoded *decoded = decode(&selected->data, source);
        Quality result = quality(image, decoded);
        line(&rates, "%d,%d,%d,%s,%s,%s,%s,%s,%lld", q, standard->data.count, optimized->data.count,
             fraction(8 * (I)selected->data.count, image.width * image.height), result.planes[0],
             result.planes[1], result.planes[2], result.rgb, result.maximum);
        if (index == 0) {
            reference = selected;
            reference_decoded = decoded;
        }
    }
    I *errors = block_errors(reference, reference_decoded);
    Lines report = reference_report(reference, p.sampling, p.qualities[0], p.optimized, errors);
    I histogram[8] = {0}, *before = channels(image), *after = channels(reference_decoded->image);
    int channel_count = 3 * image.width * image.height;
    for (int i = 0; i < channel_count; ++i) {
        I error = llabs(before[i] - after[i]);
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
    char *histogram_line = "error_histogram";
    for (int i = 0; i < 8; ++i)
        histogram_line = joined(histogram_line, format(" %lld", histogram[i]));
    line(&report, "%s", histogram_line);
    Plane original_planes[3];
    split_planes(image, original_planes);
    for (int index = 0; index < p.truncate_count; ++index) {
        int keep = p.truncate[index];
        Plane plane = reference_decoded->planes[0];
        plane.pixels = allocate((size_t)(plane.width * plane.height), sizeof(I));
        for (int number = 0; number < reference_decoded->layout.block_count; ++number) {
            Block block = reference_decoded->layout.blocks[number];
            if (block.component != 0)
                continue;
            Matrix values =
                inverse_dct(dequantize(reference_decoded->coefficients[number],
                                       reference_decoded->quantization
                                           .values[reference_decoded->layout.components[0].tq],
                                       keep),
                            source->transform);
            for (int y = 0; y < 8; ++y)
                for (int x = 0; x < 8; ++x)
                    plane.pixels[(8 * block.by + y) * plane.width + 8 * block.bx + x] =
                        values.values[y][x];
        }
        I *cropped = allocate((size_t)(image.width * image.height), sizeof(I));
        for (int y = 0; y < image.height; ++y)
            for (int x = 0; x < image.width; ++x)
                cropped[y * image.width + x] = plane.pixels[y * plane.width + x];
        line(&report, "truncate %d %s", keep,
             psnr(original_planes[0].pixels, cropped, image.width * image.height));
    }
    int samplings[3] = {444, 422, 420};
    for (int i = 0; i < 3; ++i) {
        int sampling = samplings[i];
        Encoded *encoded = encode(image, p.qualities[0], sampling, p.optimized, p.restart, source);
        Quality result = quality(image, decode(&encoded->data, source));
        line(&report, "sampling_compare %d %d %s %s %s", sampling, encoded->data.count,
             result.planes[1], result.planes[2], result.rgb);
    }
    Image previous = image;
    for (int generation = 1; generation <= p.generations; ++generation) {
        Encoded *encoded =
            encode(previous, p.qualities[0], p.sampling, p.optimized, p.restart, source);
        Decoded *decoded = decode(&encoded->data, source);
        int changed = 0;
        for (int i = 0; i < previous.width * previous.height; ++i) {
            bool different = false;
            for (int c = 0; c < 3; ++c)
                different =
                    different || previous.pixels[i].values[c] != decoded->image.pixels[i].values[c];
            changed += different;
        }
        line(&report, "generation %d %d %s %d", generation, encoded->data.count,
             psnr(before, channels(decoded->image), channel_count), changed);
        previous = decoded->image;
    }
    int lo = 1, hi = 100;
    while (lo < hi) {
        int mid = (lo + hi + 1) / 2;
        Encoded *encoded = encode(image, mid, p.sampling, p.optimized, p.restart, source);
        line(&report, "rate_control_step %d %d", mid, encoded->data.count);
        if (encoded->data.count <= p.target)
            lo = mid;
        else
            hi = mid - 1;
    }
    Encoded *controlled = encode(image, lo, p.sampling, p.optimized, p.restart, source);
    line(&report, "rate_control %d %d %s %s", lo, controlled->data.count,
         controlled->data.count <= p.target ? "yes" : "no",
         quality(image, decode(&controlled->data, source)).rgb);
    Bytes stream = read_hex("input/stream.hex");
    Decoded *damaged = decode(&stream, source);
    for (int i = 0; i < damaged->segment_count; ++i) {
        Segment segment = damaged->segments[i];
        line(&report, "stream_segment %d %s %d", segment.position, segment.name, segment.length);
    }
    line(&report, "stream_image %d %d", damaged->layout.width, damaged->layout.height);
    for (int k = 0; k < 3; ++k) {
        Component component = damaged->layout.components[k];
        line(&report, "stream_component %d %d %d %d %d %d", component.identifier, component.h,
             component.v, component.tq, component.td, component.ta);
    }
    for (int id = 0; id < 4; ++id)
        if (damaged->quantization.defined[id]) {
            char *row = format("stream_quant %d", id);
            Sequence sequence = zigzag(damaged->quantization.values[id]);
            for (int i = 0; i < 64; ++i)
                row = joined(row, format(" %lld", sequence.values[i]));
            line(&report, "%s", row);
        }
    for (int kind = 0; kind < 2; ++kind)
        for (int id = 0; id < 16; ++id) {
            const Huffman *table = &damaged->tables.values[kind][id];
            if (!table->defined)
                continue;
            int longest = 0;
            for (int length = 1; length <= 16; ++length)
                if (table->counts[length - 1])
                    longest = length;
            line(&report, "stream_huffman %d %d symbols %d longest %d", kind, id,
                 table->symbol_count, longest);
        }
    int ok = 0, damaged_count = 0, lost = 0;
    for (int j = 0; j < damaged->layout.interval_count; ++j) {
        char *state = damaged->states[j];
        ok += strcmp(state, "ok") == 0;
        lost += strcmp(state, "lost") == 0;
        damaged_count += strncmp(state, "damaged ", 8) == 0;
    }
    line(&report, "stream_restart %d intervals %d ok %d damaged %d lost %d",
         damaged->layout.restart, damaged->layout.interval_count, ok, damaged_count, lost);
    for (int j = 0; j < damaged->layout.interval_count; ++j) {
        Interval interval = damaged->layout.intervals[j];
        line(&report, "stream_interval %d %d %d %s", j, interval.first, interval.count,
             damaged->states[j]);
    }
    line(&report, "stream_scan_bytes %d", damaged->scan_bytes);
    Prepared *repair = allocate(1, sizeof(Prepared));
    repair->layout = standard_layout(damaged->layout.width, damaged->layout.height,
                                     damaged->layout.components[0].h,
                                     damaged->layout.components[0].v, damaged->layout.restart);
    repair->quantization.values[0] = damaged->quantization.values[damaged->layout.components[0].tq];
    repair->quantization.values[1] = damaged->quantization.values[damaged->layout.components[1].tq];
    repair->quantization.defined[0] = repair->quantization.defined[1] = true;
    repair->coefficients = damaged->coefficients;
    Encoded *repaired = encode_prepared(repair, true, source);
    Decoded *repaired_decoded = decode(&repaired->data, source);
    bool identical = true;
    for (int i = 0; i < damaged->image.width * damaged->image.height; ++i)
        for (int c = 0; c < 3; ++c)
            identical = identical && repaired_decoded->image.pixels[i].values[c] ==
                                         damaged->image.pixels[i].values[c];
    line(&report, "repair %d %d %d identical %s", repaired->data.count, repaired->header_bytes,
         repaired->scan_bytes, identical ? "yes" : "no");
    mkdir("output", 0777);
    save("rate_distortion.csv", rates);
    write_ppm("decoded.ppm", reference_decoded->image);
    write_hex("bitstream.hex", reference->data);
    write_ppm("thumbnail.ppm", thumbnail(reference_decoded));
    save("huffman_tables.txt", huffman_report(reference));
    save("blocks.txt", blocks_report(reference, errors));
    write_ppm("stream_decoded.ppm", damaged->image);
    write_hex("repaired.hex", repaired->data);
    save("report.txt", report);
    return 0;
}
