#include "qr.h"
struct MemoryBlock {
    MemoryBlock *next;
    size_t used, capacity;
    max_align_t alignment;
    unsigned char data[];
};
Memory permanent = {0};
Memory *memory = &permanent;
void *allocate(size_t size) {
    size_t alignment = _Alignof(max_align_t);
    size = (size + alignment - 1) / alignment * alignment;
    if (!memory->head || memory->head->capacity - memory->head->used < size) {
        size_t capacity = size > 65536 ? size : 65536;
        MemoryBlock *block = malloc(sizeof(*block) + capacity);
        if (!block)
            exit(1);
        block->next = memory->head;
        block->used = 0;
        block->capacity = capacity;
        memory->head = block;
    }
    void *result = memory->head->data + memory->head->used;
    memory->head->used += size;
    memset(result, 0, size);
    return result;
}
void clear_memory(Memory *pool) {
    while (pool->head) {
        MemoryBlock *next = pool->head->next;
        free(pool->head);
        pool->head = next;
    }
}
char *substring(const char *source, size_t length) {
    char *result = allocate(length + 1);
    memcpy(result, source, length);
    return result;
}
char *copy_text(const char *source) { return substring(source, strlen(source)); }
char *format(const char *pattern, ...) {
    va_list arguments, copy;
    va_start(arguments, pattern);
    va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, arguments);
    va_end(arguments);
    return result;
}
Names split(const char *source, const char *separator) {
    Names out = {0};
    size_t length = strlen(separator);
    const char *start = source;
    for (;;) {
        const char *end = strstr(start, separator);
        Names_add(&out, end ? substring(start, (size_t)(end - start)) : copy_text(start));
        if (!end)
            return out;
        start = end + length;
    }
}
char *join(Names values, const char *separator) {
    size_t length = 1;
    for (size_t i = 0; i < values.count; ++i)
        length += strlen(values.items[i]) + (i ? strlen(separator) : 0);
    char *out = allocate(length), *at = out;
    for (size_t i = 0; i < values.count; ++i) {
        if (i) {
            size_t n = strlen(separator);
            memcpy(at, separator, n);
            at += n;
        }
        size_t n = strlen(values.items[i]);
        memcpy(at, values.items[i], n);
        at += n;
    }
    return out;
}
char *trim(const char *source) {
    while (*source == ' ')
        ++source;
    size_t length = strlen(source);
    while (length && source[length - 1] == ' ')
        --length;
    return substring(source, length);
}
Names read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file)
        exit(1);
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    rewind(file);
    char *source = allocate((size_t)length + 1);
    fread(source, 1, (size_t)length, file);
    fclose(file);
    Names lines = split(source, "\n");
    if (length && source[length - 1] == '\n')
        --lines.count;
    return lines;
}

static const char *modes[] = {"NUMERIC", "ALPHANUMERIC", "BYTE"};
static const char *levels = "LMQH";
static int minimum(int a, int b) { return a < b ? a : b; }
static int count_width(int mode, int version) {
    const int widths[2][3] = {{10, 9, 8}, {12, 11, 16}};
    return widths[version == 10][mode];
}
static int data_width(int mode, int count) {
    const int remainder[] = {0, 4, 7};
    return mode == 0   ? 10 * (count / 3) + remainder[count % 3]
           : mode == 1 ? 11 * (count / 2) + 6 * (count % 2)
                       : 8 * count;
}
static bool encodable(int mode, char c) {
    return mode == 0   ? c >= '0' && c <= '9'
           : mode == 1 ? strchr(alphanumeric, c) != NULL
                       : c >= 32 && c <= 126;
}
static bool encodable_text(int mode, const char *source) {
    for (int i = 0; source[i]; ++i)
        if (!encodable(mode, source[i]))
            return false;
    return true;
}
static int segment_width(int mode, int count, int version) {
    return 4 + count_width(mode, version) + data_width(mode, count);
}
typedef struct {
    int mode;
    char *characters;
} Segment;
typedef struct {
    Segment segments[400];
    int count, bits;
} Split;
static Split mixed_segments(const char *source, int version) {
    int invalid[3][401] = {0}, length = (int)strlen(source), costs[401] = {0}, starts[401] = {0},
        choices[401] = {0};
    for (int i = 0; i < length; ++i)
        for (int mode = 0; mode < 3; ++mode)
            invalid[mode][i + 1] = invalid[mode][i] + !encodable(mode, source[i]);
    for (int end = 1; end <= length; ++end) {
        costs[end] = 1000000;
        for (int start = 0; start < end; ++start)
            for (int mode = 0; mode < 3; ++mode)
                if (invalid[mode][end] == invalid[mode][start]) {
                    int cost = costs[start] + segment_width(mode, end - start, version);
                    if (cost < costs[end]) {
                        costs[end] = cost;
                        starts[end] = start;
                        choices[end] = mode;
                    }
                }
    }
    Split out = {.bits = costs[length]};
    for (int end = length; end; end = starts[end])
        out.segments[out.count++] =
            (Segment){choices[end], substring(source + starts[end], (size_t)(end - starts[end]))};
    for (int i = 0; i < out.count / 2; ++i) {
        Segment saved = out.segments[i];
        out.segments[i] = out.segments[out.count - 1 - i];
        out.segments[out.count - 1 - i] = saved;
    }
    return out;
}
typedef struct {
    char *bits;
    int terminator, zero_fill, pad_bytes;
} Padding;
static Padding pad_bits(const char *bits, int capacity) {
    int length = (int)strlen(bits);
    Padding out = {.terminator = minimum(4, capacity - length)};
    out.bits = allocate((size_t)capacity + 1);
    memcpy(out.bits, bits, (size_t)length);
    for (int i = 0; i < out.terminator; ++i)
        out.bits[length++] = '0';
    out.zero_fill = (8 - length % 8) % 8;
    for (int i = 0; i < out.zero_fill; ++i)
        out.bits[length++] = '0';
    out.pad_bytes = (capacity - length) / 8;
    for (int i = 0; i < out.pad_bytes; ++i) {
        memcpy(out.bits + length, i % 2 == 0 ? "11101100" : "00010001", 8);
        length += 8;
    }
    return out;
}
typedef struct {
    int block, position;
} Placement;
typedef struct {
    int degree, data, capacity, total;
    Words lengths;
    Placement placement[512];
    int placement_count;
} BlockLayout;
static BlockLayout block_layout(int e, int b1, int k1, int b2, int k2) {
    BlockLayout out = {.degree = e};
    for (int i = 0; i < b1; ++i)
        word_add(&out.lengths, k1);
    for (int i = 0; i < b2; ++i)
        word_add(&out.lengths, k2);
    int maximum = 0;
    for (int i = 0; i < out.lengths.count; ++i) {
        int length = out.lengths.items[i];
        out.data += length;
        if (length > maximum)
            maximum = length;
    }
    out.capacity = 8 * out.data;
    out.total = out.data + e * out.lengths.count;
    for (int i = 0; i < maximum; ++i)
        for (int b = 0; b < out.lengths.count; ++b)
            if (i < out.lengths.items[b])
                out.placement[out.placement_count++] = (Placement){b, i};
    for (int i = 0; i < e; ++i)
        for (int b = 0; b < out.lengths.count; ++b)
            out.placement[out.placement_count++] = (Placement){b, out.lengths.items[b] + i};
    return out;
}
typedef struct {
    Names lines;
    char *decoded;
    int blocks[3], corrected_positions;
} Attempt;
typedef struct {
    BlockLayout tables[11][4];
    Words alignments[11];
    Geometry geometries[11];
    ReedSolomon rs;
} Codec;
static Matrix rotate(const Matrix *symbol) {
    Matrix out = {.size = symbol->size};
    for (int y = 0; y < out.size; ++y)
        for (int x = 0; x < out.size; ++x)
            out.cells[y][x] = symbol->cells[out.size - 1 - x][y];
    return out;
}
static Matrix transpose(const Matrix *symbol) {
    Matrix out = {.size = symbol->size};
    for (int y = 0; y < out.size; ++y)
        for (int x = 0; x < out.size; ++x)
            out.cells[y][x] = symbol->cells[x][y];
    return out;
}
static int finder_rotation(const Matrix *symbol) {
    int n = symbol->size, best = 100, chosen = 0;
    Point corners[] = {{n - 7, n - 7}, {n - 7, 0}, {0, 0}, {0, n - 7}};
    for (int k = 0; k < 4; ++k) {
        int score = 0;
        for (int y = 0; y < 7; ++y)
            for (int x = 0; x < 7; ++x) {
                int dx = abs(x - 3), dy = abs(y - 3);
                score +=
                    symbol->cells[corners[k].y + y][corners[k].x + x] == ((dx > dy ? dx : dy) != 2);
            }
        if (score < best) {
            best = score;
            chosen = k;
        }
    }
    return chosen;
}
static void parse_data(Attempt *attempt, const char *bits, int version) {
    BitReader reader = {bits, (int)strlen(bits), 0};
    char decoded[4097] = {0};
    int decoded_length = 0, end = 0;
    while (remaining(&reader) >= 4) {
        int indicator = read_bits(&reader, 4);
        if (!indicator)
            break;
        int mode = indicator == 1 ? 0 : indicator == 2 ? 1 : indicator == 4 ? 2 : -1;
        if (mode < 0) {
            Names_add(&attempt->lines, format("parse failed indicator %s", binary(indicator, 4)));
            return;
        }
        int width = count_width(mode, version);
        if (remaining(&reader) < width) {
            Names_add(&attempt->lines, format("parse failed length %s", modes[mode]));
            return;
        }
        int count = read_bits(&reader, width);
        if (remaining(&reader) < data_width(mode, count)) {
            Names_add(&attempt->lines, format("parse failed length %s", modes[mode]));
            return;
        }
        int left = count;
        bool valid = true;
        while (left) {
            int group = minimum(mode == 0 ? 3 : mode == 1 ? 2 : 1, left), widths[] = {0, 4, 7, 10};
            int value = read_bits(&reader, mode == 0   ? widths[group]
                                           : mode == 1 ? (group == 2 ? 11 : 6)
                                                       : 8);
            if (mode == 0) {
                int maximum = group == 3 ? 1000 : group == 2 ? 100 : 10;
                if (value >= maximum)
                    valid = false;
                else {
                    char digits[4];
                    snprintf(digits, sizeof(digits), "%0*d", group, value);
                    memcpy(decoded + decoded_length, digits, (size_t)group);
                    decoded_length += group;
                }
            } else if (mode == 1) {
                if (value >= (group == 2 ? 2025 : 45))
                    valid = false;
                else {
                    if (group == 2)
                        decoded[decoded_length++] = alphanumeric[value / 45];
                    decoded[decoded_length++] = alphanumeric[value % 45];
                }
            } else {
                if (value < 32 || value > 126)
                    valid = false;
                else
                    decoded[decoded_length++] = (char)value;
            }
            if (!valid)
                break;
            left -= group;
        }
        if (!valid) {
            Names_add(&attempt->lines, format("parse failed value %s", modes[mode]));
            return;
        }
        Names_add(&attempt->lines, format("segment %s %d", modes[mode], count));
        end = reader.position;
    }
    Padding expected = pad_bits(substring(bits, (size_t)end), (int)strlen(bits));
    Names_add(&attempt->lines, format("padding %s", !strcmp(expected.bits, bits) ? "ok" : "bad"));
    attempt->decoded = copy_text(decoded);
    Names_add(&attempt->lines, format("text \"%s\"", decoded));
}
static int hamming(int value) {
    int count = 0;
    while (value) {
        value &= value - 1;
        ++count;
    }
    return count;
}
typedef struct {
    int distance, level, mask;
} Nearest;
static Nearest nearest_format(int value) {
    Nearest best = {100, 0, 0};
    for (int level = 0; level < 4; ++level)
        for (int mask = 0; mask < 8; ++mask) {
            int distance = hamming(value ^ format_information(level, mask));
            if (distance < best.distance)
                best = (Nearest){distance, level, mask};
        }
    return best;
}
static Nearest nearest_version(int value) {
    Nearest best = {100, 7, 0};
    for (int v = 7; v <= 40; ++v) {
        int distance = hamming(value ^ version_information(v));
        if (distance < best.distance)
            best = (Nearest){distance, v, 0};
    }
    return best;
}
static Attempt attempt(Codec *codec, const Matrix *symbol) {
    Attempt out = {0};
    int version = (symbol->size - 17) / 4;
    Positions positions[2];
    format_positions(symbol->size, positions);
    int f1 = read_value(symbol, &positions[0]), f2 = read_value(symbol, &positions[1]);
    Nearest first = nearest_format(f1), second = nearest_format(f2),
            chosen = second.distance < first.distance ? second : first;
    char *prefix = format("format %s %s distance %d %d", binary(f1, 15), binary(f2, 15),
                          first.distance, second.distance);
    if (chosen.distance > 3) {
        Names_add(&out.lines, format("%s unreadable", prefix));
        return out;
    }
    int level = chosen.level, mask = chosen.mask;
    Names_add(&out.lines, format("%s level %c mask %d", prefix, levels[level], mask));
    if (version >= 7) {
        version_positions(symbol->size, positions);
        int g1 = read_value(symbol, &positions[0]), g2 = read_value(symbol, &positions[1]);
        first = nearest_version(g1);
        second = nearest_version(g2);
        chosen = second.distance < first.distance ? second : first;
        prefix = format("version %s %s distance %d %d", binary(g1, 18), binary(g2, 18),
                        first.distance, second.distance);
        if (chosen.distance > 3) {
            Names_add(&out.lines, format("%s unreadable", prefix));
            return out;
        }
        Names_add(&out.lines, format("%s decoded %d", prefix, chosen.level));
        if (chosen.level != version)
            return out;
    }
    Geometry *g = &codec->geometries[version];
    BlockLayout *layout = &codec->tables[version][level];
    Matrix unmasked = apply_mask(*symbol, &g->order, mask);
    char *bits = allocate((size_t)8 * (size_t)layout->total + 1);
    for (int i = 0; i < 8 * layout->total; ++i) {
        Point p = g->order.items[i];
        bits[i] = (char)('0' + unmasked.cells[p.y][p.x]);
    }
    Words words = to_codewords(bits), blocks[16] = {0}, data = {0};
    for (int b = 0; b < layout->lengths.count; ++b)
        blocks[b].count = layout->lengths.items[b] + layout->degree;
    for (int i = 0; i < layout->placement_count; ++i) {
        Placement p = layout->placement[i];
        blocks[p.block].items[p.position] = words.items[i];
    }
    bool failed = false;
    for (int b = 0; b < layout->lengths.count; ++b) {
        Correction result = correct(&codec->rs, &blocks[b], layout->degree);
        prefix = format("block %d syndromes %s", b, hexadecimal(&result.syndromes));
        if (!result.success) {
            Names_add(&out.lines, format("%s failed", prefix));
            ++out.blocks[2];
            failed = true;
        } else {
            if (!result.positions.count) {
                Names_add(&out.lines, format("%s ok", prefix));
                ++out.blocks[0];
            } else {
                Names positions_text = {0};
                for (int i = 0; i < result.positions.count; ++i)
                    Names_add(&positions_text, format("%d", result.positions.items[i]));
                Names_add(&out.lines, format("%s corrected %s", prefix, join(positions_text, " ")));
                ++out.blocks[1];
                out.corrected_positions += result.positions.count;
            }
            for (int i = 0; i < layout->lengths.items[b]; ++i)
                word_add(&data, result.corrected.items[i]);
        }
    }
    if (!failed)
        parse_data(&out, from_codewords(&data), version);
    return out;
}
static Attempt decode(Codec *codec, Matrix symbol) {
    int rotations = finder_rotation(&symbol);
    for (int i = 0; i < rotations; ++i)
        symbol = rotate(&symbol);
    Attempt adopted = attempt(codec, &symbol);
    bool mirrored = false;
    if (!adopted.decoded) {
        Matrix reflected = transpose(&symbol);
        Attempt other = attempt(codec, &reflected);
        if (other.decoded) {
            adopted = other;
            mirrored = true;
        }
    }
    Names lines = {0};
    Names_add(&lines,
              format("orientation rotations %d mirrored %s", rotations, mirrored ? "yes" : "no"));
    for (size_t i = 0; i < adopted.lines.count; ++i)
        Names_add(&lines, adopted.lines.items[i]);
    adopted.lines = lines;
    return adopted;
}
typedef struct {
    char *identifier, *level_token, *mode_token, *version_token, *mask_token, *characters;
    int mode, version, level, bit_count;
    bool boosted, cached[2];
    Split splits[2];
} Request;
static Split *request_split(Request *request, int v) {
    int category = v == 10;
    if (!request->cached[category]) {
        request->cached[category] = true;
        request->splits[category] =
            request->mode == 3
                ? mixed_segments(request->characters, v)
                : (Split){.segments = {{request->mode, request->characters}},
                          .count = 1,
                          .bits =
                              segment_width(request->mode, (int)strlen(request->characters), v)};
    }
    return &request->splits[category];
}
static char *prepare(Request *request, Codec *codec) {
    size_t level_length = strlen(request->level_token);
    bool valid_level = level_length >= 1 && level_length <= 2 &&
                       strchr(levels, request->level_token[0]) &&
                       (level_length == 1 || request->level_token[1] == '+');
    if (!valid_level)
        return format("level %s", request->level_token);
    if (strcmp(request->mode_token, "NUMERIC") && strcmp(request->mode_token, "ALPHANUMERIC") &&
        strcmp(request->mode_token, "BYTE") && strcmp(request->mode_token, "AUTO") &&
        strcmp(request->mode_token, "MIXED"))
        return format("mode %s", request->mode_token);
    bool valid_version = !strcmp(request->version_token, "AUTO");
    for (int i = 1; i <= 10; ++i)
        valid_version |= !strcmp(request->version_token, format("%d", i));
    if (!valid_version)
        return format("version %s", request->version_token);
    bool valid_mask = !strcmp(request->mask_token, "AUTO");
    for (int i = 0; i < 8; ++i)
        valid_mask |= !strcmp(request->mask_token, format("%d", i));
    if (!valid_mask)
        return format("mask %s", request->mask_token);
    if (!*request->characters)
        return "text";
    request->mode = !strcmp(request->mode_token, "NUMERIC")        ? 0
                    : !strcmp(request->mode_token, "ALPHANUMERIC") ? 1
                    : !strcmp(request->mode_token, "BYTE")         ? 2
                                                                   : 3;
    if (request->mode < 2)
        for (int i = 0; request->characters[i]; ++i)
            if (!encodable(request->mode, request->characters[i]))
                return format("charset position %d", i);
    if (!strcmp(request->mode_token, "AUTO")) {
        request->mode = 0;
        while (!encodable_text(request->mode, request->characters))
            ++request->mode;
    }
    int base = (int)(strchr(levels, request->level_token[0]) - levels),
        first = !strcmp(request->version_token, "AUTO") ? 1 : atoi(request->version_token),
        last = !strcmp(request->version_token, "AUTO") ? 10 : first, bits = 0, capacity = 0;
    for (int v = first; v <= last; ++v) {
        bits = request_split(request, v)->bits;
        capacity = codec->tables[v][base].capacity;
        if (bits <= capacity) {
            request->version = v;
            break;
        }
    }
    if (!request->version)
        return format("capacity bits %d capacity %d", bits, capacity);
    request->bit_count = request_split(request, request->version)->bits;
    request->level = base;
    if (level_length == 2)
        for (int level = base; level < 4; ++level)
            if (request->bit_count <= codec->tables[request->version][level].capacity)
                request->level = level;
    request->boosted = request->level != base;
    return NULL;
}
typedef struct {
    Request *request;
    Geometry *geometry;
    BlockLayout *layout;
    char *raw_bits;
    Names trace;
    Padding padding;
    Words blocks[16], codewords;
    Penalty scores[8];
    int mask, dark;
    Matrix symbol;
} Encoding;
static void encode(Encoding *out, Request *request, Codec *codec) {
    out->request = request;
    out->geometry = &codec->geometries[request->version];
    out->layout = &codec->tables[request->version][request->level];
    BitWriter writer = {0};
    const int indicators[] = {1, 2, 4}, widths[] = {0, 4, 7, 10};
    Split *split = request_split(request, request->version);
    for (int s = 0; s < split->count; ++s) {
        Segment segment = split->segments[s];
        int mode = segment.mode, count = (int)strlen(segment.characters),
            width = count_width(mode, request->version);
        write_bits(&writer, indicators[mode], 4);
        write_bits(&writer, count, width);
        Names_add(&out->trace, format("segment %s indicator %s count %d %s", modes[mode],
                                      binary(indicators[mode], 4), count, binary(count, width)));
        int step = mode == 0 ? 3 : mode == 1 ? 2 : 1;
        for (int start = 0; start < count; start += step) {
            int length = minimum(step, count - start), value, group_width;
            char *characters = substring(segment.characters + start, (size_t)length);
            if (mode == 0) {
                value = atoi(characters);
                group_width = widths[length];
            } else if (mode == 1) {
                value = (int)(strchr(alphanumeric, characters[0]) - alphanumeric);
                group_width = 6;
                if (length == 2) {
                    value = 45 * value + (int)(strchr(alphanumeric, characters[1]) - alphanumeric);
                    group_width = 11;
                }
            } else {
                value = (unsigned char)characters[0];
                group_width = 8;
            }
            write_bits(&writer, value, group_width);
            Names_add(&out->trace,
                      format("group %d %s \"%s\"", value, binary(value, group_width), characters));
        }
    }
    out->raw_bits = copy_text(writer.bits);
    out->padding = pad_bits(out->raw_bits, out->layout->capacity);
    Words data = to_codewords(out->padding.bits);
    int start = 0;
    for (int b = 0; b < out->layout->lengths.count; ++b) {
        int length = out->layout->lengths.items[b];
        Words block = {0};
        for (int i = 0; i < length; ++i)
            word_add(&block, data.items[start++]);
        Words ec = parity(&codec->rs, &block, out->layout->degree);
        for (int i = 0; i < ec.count; ++i)
            word_add(&block, ec.items[i]);
        out->blocks[b] = block;
    }
    for (int i = 0; i < out->layout->placement_count; ++i) {
        Placement p = out->layout->placement[i];
        word_add(&out->codewords, out->blocks[p.block].items[p.position]);
    }
    Matrix unmasked = out->geometry->symbol;
    char *bits = from_codewords(&out->codewords);
    for (int i = 0; bits[i]; ++i) {
        Point p = out->geometry->order.items[i];
        unmasked.cells[p.y][p.x] = (unsigned char)(bits[i] - '0');
    }
    int best = 1000000;
    for (int mask = 0; mask < 8; ++mask) {
        Matrix candidate = apply_mask(unmasked, &out->geometry->order, mask);
        Positions positions[2];
        format_positions(candidate.size, positions);
        for (int p = 0; p < 2; ++p)
            write_value(&candidate, &positions[p], format_information(request->level, mask));
        out->scores[mask] = penalties(&candidate);
        bool chosen = !strcmp(request->mask_token, "AUTO") ? penalty_total(out->scores[mask]) < best
                                                           : atoi(request->mask_token) == mask;
        if (chosen) {
            best = penalty_total(out->scores[mask]);
            out->mask = mask;
            out->symbol = candidate;
        }
    }
    for (int y = 0; y < out->symbol.size; ++y)
        for (int x = 0; x < out->symbol.size; ++x)
            out->dark += out->symbol.cells[y][x];
}
typedef struct {
    char *identifier, *kind;
    int x, y, width, height, color;
} Operation;
VECTOR(Operations, Operation)
typedef struct {
    char *name;
    Matrix symbol;
} Scan;
typedef struct {
    Request requests[40];
    int request_count, quiet, scale;
    Operations damage;
    Scan scans[20];
    int scan_count;
} Inputs;
static void read_inputs(Inputs *inputs, Codec *codec) {
    init_reed_solomon(&codec->rs);
    Names lines = read_lines("input/requests.txt");
    for (size_t i = 0; i < lines.count; ++i) {
        char *colon = strchr(lines.items[i], ':');
        Names f = split(substring(lines.items[i], (size_t)(colon - lines.items[i])), " ");
        inputs->requests[inputs->request_count++] = (Request){.identifier = f.items[0],
                                                              .level_token = f.items[1],
                                                              .mode_token = f.items[2],
                                                              .version_token = f.items[3],
                                                              .mask_token = f.items[4],
                                                              .characters = colon + 1};
    }
    lines = read_lines("input/params.txt");
    inputs->quiet = atoi(split(lines.items[0], " ").items[1]);
    inputs->scale = atoi(split(lines.items[1], " ").items[1]);
    lines = read_lines("input/tables.txt");
    for (size_t i = 0; i < lines.count; ++i) {
        Names f = split(lines.items[i], " ");
        int v = atoi(f.items[1]);
        if (!strcmp(f.items[0], "block")) {
            int level = (int)(strchr(levels, f.items[2][0]) - levels);
            codec->tables[v][level] =
                block_layout(atoi(f.items[3]), atoi(f.items[4]), atoi(f.items[5]), atoi(f.items[6]),
                             atoi(f.items[7]));
        } else
            for (size_t j = 2; j < f.count; ++j)
                word_add(&codec->alignments[v], atoi(f.items[j]));
    }
    for (int v = 1; v <= 10; ++v)
        function_matrix(&codec->geometries[v], v, &codec->alignments[v]);
    lines = read_lines("input/damage.txt");
    for (size_t i = 0; i < lines.count; ++i) {
        Names f = split(lines.items[i], " ");
        Operation op = {.identifier = f.items[0], .kind = f.items[1]};
        if (!strcmp(op.kind, "flip") || !strcmp(op.kind, "fill")) {
            op.x = atoi(f.items[2]);
            op.y = atoi(f.items[3]);
        }
        if (!strcmp(op.kind, "fill")) {
            op.width = atoi(f.items[4]);
            op.height = atoi(f.items[5]);
            op.color = !strcmp(f.items[6], "dark");
        }
        Operations_add(&inputs->damage, op);
    }
    lines = read_lines("input/scans.txt");
    for (size_t i = 0; i < lines.count;) {
        Scan *scan = &inputs->scans[inputs->scan_count++];
        scan->name = split(lines.items[i++], " ").items[1];
        scan->symbol.size = (int)strlen(lines.items[i]);
        for (int y = 0; y < scan->symbol.size; ++y) {
            for (int x = 0; x < scan->symbol.size; ++x)
                scan->symbol.cells[y][x] = lines.items[i][x] == '#';
            ++i;
        }
    }
}
static void write_lines(FILE *file, Names lines) {
    for (size_t i = 0; i < lines.count; ++i)
        fprintf(file, "%s\n", lines.items[i]);
}
static void codes_lines(FILE *file, Encoding *e, Codec *codec) {
    Request *q = e->request;
    Geometry *g = e->geometry;
    BlockLayout *layout = e->layout;
    fprintf(file, "symbol version %d level %c mask %d size %d\n", q->version, levels[q->level],
            e->mask, g->symbol.size);
    Split *split = request_split(q, q->version);
    fprintf(file, "segments %d", split->count);
    for (int i = 0; i < split->count; ++i)
        fprintf(file, " %s:%zu", modes[split->segments[i].mode],
                strlen(split->segments[i].characters));
    fputc('\n', file);
    fprintf(file, "bits data %d capacity %d alternatives", q->bit_count, layout->capacity);
    for (int mode = 0; mode < 3; ++mode)
        fprintf(file, " %s %s", modes[mode],
                encodable_text(mode, q->characters)
                    ? format("%d", segment_width(mode, (int)strlen(q->characters), q->version))
                    : "-");
    fprintf(file, " MIXED %d\n",
            q->mode == 3 ? q->bit_count : mixed_segments(q->characters, q->version).bits);
    fputs("fits", file);
    for (int level = 0; level < 4; ++level) {
        int fitting = 0;
        for (int v = 1; v <= 10; ++v)
            if (request_split(q, v)->bits <= codec->tables[v][level].capacity) {
                fitting = v;
                break;
            }
        fprintf(file, " %c %s", levels[level], fitting ? format("%d", fitting) : "-");
    }
    fputc('\n', file);
    fprintf(file, "modules function %d data %d remainder %d dark %d\n",
            g->symbol.size * g->symbol.size - g->order.count, g->order.count,
            g->order.count - 8 * layout->total, e->dark);
    fprintf(file, "format %s version %s\n", binary(format_information(q->level, e->mask), 15),
            q->version >= 7 ? binary(version_information(q->version), 18) : "none");
    for (int mask = 0; mask < 8; ++mask) {
        Penalty p = e->scores[mask];
        fprintf(file, "penalty %d n1 %d n2 %d n3 %d n4 %d total %d\n", mask, p.n1, p.n2, p.n3, p.n4,
                penalty_total(p));
    }
    write_lines(file, symbol_lines(&e->symbol));
}
static void codeword_lines(FILE *file, const Encoding *e) {
    Request *q = e->request;
    BlockLayout *layout = e->layout;
    fprintf(file, "request %s version %d level %c blocks %d data %d ec_per_block %d total %d\n",
            q->identifier, q->version, levels[q->level], layout->lengths.count, layout->data,
            layout->degree, layout->total);
    for (int b = 0; b < layout->lengths.count; ++b) {
        Words data = {0}, ec = {0};
        for (int i = 0; i < layout->lengths.items[b]; ++i)
            word_add(&data, e->blocks[b].items[i]);
        for (int i = layout->lengths.items[b]; i < e->blocks[b].count; ++i)
            word_add(&ec, e->blocks[b].items[i]);
        fprintf(file, "block %d data %s\nblock %d ec %s\n", b, hexadecimal(&data), b,
                hexadecimal(&ec));
    }
    fprintf(file, "interleaved %s\n", hexadecimal(&e->codewords));
}
static void bitstream_lines(FILE *file, const Encoding *e) {
    fprintf(file, "request %s version %d bits %d capacity %d\n", e->request->identifier,
            e->request->version, e->request->bit_count, e->layout->capacity);
    write_lines(file, e->trace);
    fprintf(file, "terminator %d zero_fill %d pad_bytes %d\n", e->padding.terminator,
            e->padding.zero_fill, e->padding.pad_bytes);
}
typedef struct {
    Matrix symbol;
    char *description;
} Image;
static Image read_image(const char *path) {
    Names lines = read_lines(path), dimensions = split(lines.items[1], " ");
    int width = atoi(dimensions.items[0]), height = atoi(dimensions.items[1]), left = width,
        right = 0, top = height;
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x)
            if (lines.items[y + 2][x] == '1') {
                if (x < left)
                    left = x;
                if (x > right)
                    right = x;
                if (y < top)
                    top = y;
            }
    int run = 0;
    while (left + run < width && lines.items[top + 2][left + run] == '1')
        ++run;
    int unit = run / 7;
    Image out = {.symbol = {.size = (right - left + 1) / unit}};
    for (int y = 0; y < out.symbol.size; ++y)
        for (int x = 0; x < out.symbol.size; ++x)
            out.symbol.cells[y][x] =
                (unsigned char)(lines.items[top + unit * y + 2][left + unit * x] - '0');
    bool well_formed = true;
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            int expected = 0;
            if (x >= left && x < left + unit * out.symbol.size && y >= top &&
                y < top + unit * out.symbol.size)
                expected = out.symbol.cells[(y - top) / unit][(x - left) / unit];
            well_formed &= lines.items[y + 2][x] - '0' == expected;
        }
    out.description = format("image %d %d quiet %d scale %d size %d %s", width, height, left / unit,
                             unit, out.symbol.size, well_formed ? "ok" : "bad");
    return out;
}
static Matrix damaged_symbol(const Encoding *e, Operations operations, FILE *file) {
    Matrix symbol = e->symbol;
    int n = symbol.size;
    for (size_t i = 0; i < operations.count; ++i) {
        Operation op = operations.items[i];
        if (!strcmp(op.kind, "flip"))
            symbol.cells[op.y][op.x] ^= 1;
        else if (!strcmp(op.kind, "fill"))
            for (int y = op.y; y < op.y + op.height; ++y)
                for (int x = op.x; x < op.x + op.width; ++x)
                    symbol.cells[y][x] = (unsigned char)op.color;
    }
    int counts[5] = {0};
    bool damaged[16][256] = {0};
    for (int y = 0; y < n; ++y)
        for (int x = 0; x < n; ++x)
            if (symbol.cells[y][x] != e->symbol.cells[y][x]) {
                int area = e->geometry->areas.cells[y][x];
                if (area != AREA_DATA)
                    ++counts[area - 1];
                else {
                    int index = e->geometry->indices[y][x];
                    if (index < 8 * e->layout->total) {
                        ++counts[3];
                        Placement p = e->layout->placement[index / 8];
                        damaged[p.block][p.position] = true;
                    } else
                        ++counts[4];
                }
            }
    for (size_t i = 0; i < operations.count; ++i) {
        Operation op = operations.items[i];
        if (!strcmp(op.kind, "rotate"))
            symbol = rotate(&symbol);
        else if (!strcmp(op.kind, "mirror"))
            symbol = transpose(&symbol);
    }
    int changed = 0;
    for (int i = 0; i < 5; ++i)
        changed += counts[i];
    fprintf(
        file,
        "check damaged operations %zu\ndamage changed %d function %d format %d version %d data %d remainder %d\n",
        operations.count, changed, counts[0], counts[1], counts[2], counts[3], counts[4]);
    fputs("errors", file);
    for (int b = 0; b < e->layout->lengths.count; ++b) {
        int count = 0;
        for (int i = 0; i < 256; ++i)
            count += damaged[b][i];
        fprintf(file, " %d", count);
    }
    fprintf(file, " limit %d\n", e->layout->degree / 2);
    return symbol;
}
static int tolerance(const Encoding *e, Codec *codec, int color) {
    int n = e->symbol.size;
    Memory *parent = memory;
    for (int side = 1; side <= n; ++side) {
        Memory work = {0};
        memory = &work;
        Matrix symbol = e->symbol;
        int start = (n - side) / 2;
        for (int y = start; y < start + side; ++y)
            for (int x = start; x < start + side; ++x)
                symbol.cells[y][x] = (unsigned char)color;
        Attempt result = decode(codec, symbol);
        bool same = result.decoded && !strcmp(result.decoded, e->request->characters);
        clear_memory(&work);
        memory = parent;
        if (!same)
            return side - 1;
    }
    return n;
}
typedef struct {
    int encoded, boosted, segments, data, ec, modules, dark, corrected_positions;
    int errors[7], mode_counts[4], level_counts[4], versions[11], masks[8], checks[3], blocks[3],
        scans[2];
} Summary;
static void record_encoding(Summary *s, const Encoding *e) {
    ++s->encoded;
    s->boosted += e->request->boosted;
    ++s->mode_counts[e->request->mode];
    ++s->level_counts[e->request->level];
    ++s->versions[e->request->version];
    ++s->masks[e->mask];
    s->segments += e->request->splits[e->request->version == 10].count;
    s->data += e->layout->data;
    s->ec += e->layout->degree * e->layout->lengths.count;
    s->modules += e->symbol.size * e->symbol.size;
    s->dark += e->dark;
}
static const char *record_check(Summary *s, const Attempt *attempt, const char *expected) {
    int status = !attempt->decoded ? 2 : !strcmp(attempt->decoded, expected) ? 0 : 1;
    ++s->checks[status];
    for (int i = 0; i < 3; ++i)
        s->blocks[i] += attempt->blocks[i];
    s->corrected_positions += attempt->corrected_positions;
    return status == 0 ? "ok" : status == 1 ? "mismatch" : "failed";
}
static void summary_report(FILE *file, const Summary *s, int requests) {
    int errors = 0;
    for (int i = 0; i < 7; ++i)
        errors += s->errors[i];
    const char *kinds[] = {"level", "mode", "version", "mask", "text", "charset", "capacity"};
    fprintf(file, "requests %d encoded %d errors %d\nerror_kinds", requests, s->encoded, errors);
    for (int i = 0; i < 7; ++i)
        fprintf(file, " %s %d", kinds[i], s->errors[i]);
    fputs("\nmodes", file);
    for (int i = 0; i < 4; ++i)
        fprintf(file, " %s %d", i < 3 ? modes[i] : "MIXED", s->mode_counts[i]);
    fputs("\nlevels", file);
    for (int i = 0; i < 4; ++i)
        fprintf(file, " %c %d", levels[i], s->level_counts[i]);
    fprintf(file, " boosted %d\nversions", s->boosted);
    for (int i = 1; i <= 10; ++i)
        fprintf(file, " %d", s->versions[i]);
    fputs("\nmasks", file);
    for (int i = 0; i < 8; ++i)
        fprintf(file, " %d", s->masks[i]);
    fprintf(
        file,
        "\nsegments %d data_codewords %d ec_codewords %d\nmodules %d dark %d\nchecks %d ok %d mismatch %d failed %d\nblocks ok %d corrected %d failed %d codewords %d\nscans %d decoded %d failed %d\n",
        s->segments, s->data, s->ec, s->modules, s->dark,
        s->checks[0] + s->checks[1] + s->checks[2], s->checks[0], s->checks[1], s->checks[2],
        s->blocks[0], s->blocks[1], s->blocks[2], s->corrected_positions, s->scans[0] + s->scans[1],
        s->scans[0], s->scans[1]);
}
static void check_lines(FILE *file, const Encoding *e, Codec *codec, const Inputs *inputs,
                        Operations operations, Summary *summary) {
    char *path = format("output/qr_%s.pbm", e->request->identifier);
    FILE *image_file = fopen(path, "wb");
    fputs(pbm_text(&e->symbol, inputs->quiet, inputs->scale), image_file);
    fclose(image_file);
    Image image = read_image(path);
    fprintf(file, "request %s\n%s\ncheck clean\n", e->request->identifier, image.description);
    Attempt clean = decode(codec, image.symbol);
    write_lines(file, clean.lines);
    fprintf(file, "result %s\n", record_check(summary, &clean, e->request->characters));
    if (operations.count) {
        Matrix damaged = damaged_symbol(e, operations, file);
        Attempt result = decode(codec, damaged);
        write_lines(file, result.lines);
        fprintf(file, "result %s\n", record_check(summary, &result, e->request->characters));
    }
    int light = tolerance(e, codec, 0), dark = tolerance(e, codec, 1);
    fprintf(file, "tolerance light %d dark %d\n", light, dark);
}
static void capacity_report(FILE *file, Codec *codec) {
    for (int v = 1; v <= 10; ++v) {
        Geometry *g = &codec->geometries[v];
        int total = codec->tables[v][0].total;
        fprintf(file, "version %d size %d data_modules %d codewords %d remainder %d alignment", v,
                g->symbol.size, g->order.count, total, g->order.count - 8 * total);
        if (!codec->alignments[v].count)
            fputs(" none", file);
        else
            for (int i = 0; i < codec->alignments[v].count; ++i)
                fprintf(file, " %d", codec->alignments[v].items[i]);
        fputc('\n', file);
        for (int level = 0; level < 4; ++level) {
            BlockLayout *layout = &codec->tables[v][level];
            int maxima[3] = {0};
            for (int mode = 0; mode < 3; ++mode)
                while (segment_width(mode, maxima[mode] + 1, v) <= layout->capacity)
                    ++maxima[mode];
            fprintf(
                file,
                "level %c blocks %d data %d ec_per_block %d numeric %d alphanumeric %d byte %d\n",
                levels[level], layout->lengths.count, layout->data, layout->degree, maxima[0],
                maxima[1], maxima[2]);
        }
    }
}
int main(void) {
    Codec *codec = allocate(sizeof(*codec));
    Inputs *inputs = allocate(sizeof(*inputs));
    read_inputs(inputs, codec);
    Summary summary = {0};
    mkdir("output", 0777);
    FILE *codes = fopen("output/codes.txt", "wb"), *words = fopen("output/codewords.txt", "wb"),
         *bits = fopen("output/bitstream.txt", "wb"), *checks = fopen("output/selfcheck.txt", "wb");
    const char *kinds[] = {"level", "mode", "version", "mask", "text", "charset", "capacity"};
    for (int q = 0; q < inputs->request_count; ++q) {
        Memory work = {0};
        memory = &work;
        Request *request = &inputs->requests[q];
        fprintf(codes, "request %s\n", request->identifier);
        char *error = prepare(request, codec);
        if (error) {
            fprintf(codes, "error %s\n", error);
            for (int i = 0; i < 7; ++i) {
                size_t length = strlen(kinds[i]);
                if (!strncmp(error, kinds[i], length) &&
                    (error[length] == '\0' || error[length] == ' ')) {
                    ++summary.errors[i];
                    break;
                }
            }
        } else {
            Encoding *encoding = allocate(sizeof(*encoding));
            encode(encoding, request, codec);
            codes_lines(codes, encoding, codec);
            codeword_lines(words, encoding);
            bitstream_lines(bits, encoding);
            record_encoding(&summary, encoding);
            Operations operations = {0};
            for (size_t i = 0; i < inputs->damage.count; ++i)
                if (!strcmp(inputs->damage.items[i].identifier, request->identifier))
                    Operations_add(&operations, inputs->damage.items[i]);
            check_lines(checks, encoding, codec, inputs, operations, &summary);
        }
        clear_memory(&work);
        memory = &permanent;
    }
    fclose(codes);
    fclose(words);
    fclose(bits);
    fclose(checks);
    FILE *scans = fopen("output/scans.txt", "wb");
    for (int i = 0; i < inputs->scan_count; ++i) {
        Memory work = {0};
        memory = &work;
        Scan *scan = &inputs->scans[i];
        fprintf(scans, "scan %s size %d\n", scan->name, scan->symbol.size);
        Attempt result = decode(codec, scan->symbol);
        write_lines(scans, result.lines);
        fprintf(scans, "result %s\n", result.decoded ? "decoded" : "failed");
        ++summary.scans[result.decoded ? 0 : 1];
        clear_memory(&work);
        memory = &permanent;
    }
    fclose(scans);
    FILE *capacity = fopen("output/capacity.txt", "wb");
    capacity_report(capacity, codec);
    fclose(capacity);
    FILE *totals = fopen("output/summary.txt", "wb");
    summary_report(totals, &summary, inputs->request_count);
    fclose(totals);
    clear_memory(&permanent);
    return 0;
}
