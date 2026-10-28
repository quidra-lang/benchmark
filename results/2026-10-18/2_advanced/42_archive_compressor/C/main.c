#include "archive.h"
#include <stdarg.h>
#include <sys/stat.h>
static const char *methods[] = {"STORE", "LZW", "LZ77", "LZH", "ARITH"};
static char *text(const char *value) {
    char *out = resize(NULL, strlen(value) + 1);
    strcpy(out, value);
    return out;
}
static char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = resize(NULL, (size_t)length + 1);
    vsnprintf(out, (size_t)length + 1, pattern, args);
    va_end(args);
    return out;
}
static void line_push(Lines *lines, char *line) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? 2 * lines->capacity : 16;
        lines->data = resize(lines->data, lines->capacity * sizeof(char *));
    }
    lines->data[lines->count++] = line;
}
static void lines_extend(Lines *target, const Lines *source) {
    for (size_t i = 0; i < source->count; ++i)
        line_push(target, text(source->data[i]));
}
static void lines_free(Lines *lines) {
    for (size_t i = 0; i < lines->count; ++i)
        free(lines->data[i]);
    free(lines->data);
    *lines = (Lines){0};
}
static Bytes read_bytes(const char *path) {
    Bytes out = {0};
    FILE *file = fopen(path, "rb");
    if (!file)
        return out;
    int byte;
    while ((byte = fgetc(file)) != EOF)
        byte_push(&out, (Byte)byte);
    fclose(file);
    return out;
}
static Lines text_lines(const Bytes *bytes) {
    Lines out = {0};
    size_t first = 0;
    for (size_t i = 0; i < bytes->count; ++i)
        if (bytes->data[i] == 10) {
            size_t length = i - first;
            char *line = resize(NULL, length + 1);
            memcpy(line, bytes->data + first, length);
            line[length] = 0;
            line_push(&out, line);
            first = i + 1;
        }
    return out;
}
static void write_lines(const char *name, const Lines *lines) {
    char *path = format("output/%s", name);
    FILE *file = fopen(path, "wb");
    free(path);
    if (!file)
        return;
    for (size_t i = 0; i < lines->count; ++i) {
        fputs(lines->data[i], file);
        fputc('\n', file);
    }
    fclose(file);
}
static void write_owned(const char *name, Lines lines) {
    write_lines(name, &lines);
    lines_free(&lines);
}
static char *hex8(uint32_t value) {
    return format("%08x", value);
}
static Lines hex_lines(const Bytes *bytes) {
    Lines out = {0};
    const char *digits = "0123456789abcdef";
    for (size_t first = 0; first < bytes->count; first += 32) {
        size_t count = bytes->count - first;
        if (count > 32)
            count = 32;
        char *line = resize(NULL, 2 * count + 1);
        for (size_t i = 0; i < count; ++i) {
            line[2 * i] = digits[bytes->data[first + i] >> 4];
            line[2 * i + 1] = digits[bytes->data[first + i] & 15];
        }
        line[2 * count] = 0;
        line_push(&out, line);
    }
    return out;
}
static uint32_t adler(const Bytes *bytes) {
    uint32_t s1 = 1, s2 = 0;
    for (size_t i = 0; i < bytes->count; ++i) {
        s1 = (s1 + bytes->data[i]) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    return s2 * 65536 + s1;
}
static char *ratio(Integer original, Integer compressed) {
    return original ? format("%lld", (long long)(1000 * compressed / original)) : text("-");
}
static char *method_name(int method) {
    return method < 5 ? text(methods[method]) : format("#%d", method);
}
static void write_table(BitWriter *writer, const int *lengths, int count) {
    int position = 0;
    while (position < count) {
        if (lengths[position])
            bit_write(writer, (uint32_t)lengths[position++], 4);
        else {
            int run = 1;
            while (run < 256 && position + run < count && lengths[position + run] == 0)
                ++run;
            bit_write(writer, 0, 4);
            bit_write(writer, (uint32_t)(run - 1), 8);
            position += run;
        }
    }
}
static const char *read_table(BitReader *reader, int count, int *lengths) {
    int position = 0;
    while (position < count) {
        int value = (int)bit_read(reader, 4);
        if (reader->error)
            return reader->error;
        if (value)
            lengths[position++] = value;
        else {
            int run = (int)bit_read(reader, 8) + 1;
            if (reader->error)
                return reader->error;
            if (position + run > count)
                return "bad_table";
            for (int i = 0; i < run; ++i)
                lengths[position++] = 0;
        }
    }
    int used = 0, only = 0, sum = 0;
    for (int i = 0; i < count; ++i)
        if (lengths[i]) {
            ++used;
            only = lengths[i];
            sum += 1 << (15 - lengths[i]);
        }
    return (used == 1 && only != 1) || (used >= 2 && sum != (1 << 15)) ? "bad_table" : NULL;
}
static void fixed_lengths(int count, int *lengths) {
    int width = bits((uint32_t)(count - 1)), shorter = (1 << width) - count;
    for (int s = 0; s < count; ++s)
        lengths[s] = s < shorter ? width - 1 : width;
}
static int read_symbol(BitReader *reader, const int *lengths, const int *codes, int count) {
    int maximum = 0;
    for (int i = 0; i < count; ++i)
        if (lengths[i] > maximum)
            maximum = lengths[i];
    if (!maximum) {
        reader->error = "bad_code";
        return 0;
    }
    int code = 0;
    for (int width = 1; width <= maximum; ++width) {
        code = 2 * code + (int)bit_read(reader, 1);
        if (reader->error)
            return 0;
        for (int s = 0; s < count; ++s)
            if (lengths[s] == width && codes[s] == code)
                return s;
    }
    reader->error = "bad_code";
    return 0;
}
static void token_part(BitWriter *writer, const Tokens *tokens, const int *lengths, int count,
                       const int *distances, int distance_count) {
    int *codes = canonical_codes(lengths, count), *offset_codes = canonical_codes(distances, distance_count);
    for (size_t i = 0; i < tokens->count; ++i) {
        Token token = tokens->data[i];
        int symbol = token.length ? 256 + token.length - 3 : token.literal;
        bit_write(writer, (uint32_t)codes[symbol], lengths[symbol]);
        if (token.length) {
            int u = token.distance - 1, slot = bits((uint32_t)u);
            bit_write(writer, (uint32_t)offset_codes[slot], distances[slot]);
            if (slot >= 2)
                bit_write(writer, (uint32_t)(u - (1 << (slot - 1))), slot - 1);
        }
    }
    free(codes);
    free(offset_codes);
}
typedef struct {
    bool dynamic;
    int fixed_bits, table_bits, code_bits, halvings, litlen_used, litlen_max, offset_used, offset_max,
        slots[13];
} LzhStats;
static Bytes lzh_encode(const Tokens *tokens, int b, int k, int maximum, LzhStats *stats) {
    int count = 256 + (1 << k), frequency[288] = {0}, offset_frequency[13] = {0};
    for (size_t i = 0; i < tokens->count; ++i) {
        Token token = tokens->data[i];
        ++frequency[token.length ? 256 + token.length - 3 : token.literal];
        if (token.length) {
            int slot = bits((uint32_t)(token.distance - 1));
            ++offset_frequency[slot];
            ++stats->slots[slot];
        }
    }
    Huffman literal = huffman_lengths(frequency, count, maximum),
            distance = huffman_lengths(offset_frequency, b + 1, maximum);
    stats->halvings = literal.halvings + distance.halvings;
    for (int i = 0; i < count; ++i) {
        int length = literal.lengths[i];
        stats->litlen_used += length > 0;
        if (length > stats->litlen_max)
            stats->litlen_max = length;
    }
    for (int i = 0; i <= b; ++i) {
        int length = distance.lengths[i];
        stats->offset_used += length > 0;
        if (length > stats->offset_max)
            stats->offset_max = length;
    }
    BitWriter tables = {0}, dynamic = {0}, fixed = {0};
    write_table(&tables, literal.lengths, count);
    write_table(&tables, distance.lengths, b + 1);
    token_part(&dynamic, tokens, literal.lengths, count, distance.lengths, b + 1);
    int fixed_literal[288], fixed_distance[13];
    fixed_lengths(count, fixed_literal);
    fixed_lengths(b + 1, fixed_distance);
    token_part(&fixed, tokens, fixed_literal, count, fixed_distance, b + 1);
    stats->fixed_bits = (int)fixed.count;
    stats->table_bits = (int)tables.count;
    stats->code_bits = (int)dynamic.count;
    stats->dynamic = stats->fixed_bits > stats->table_bits + stats->code_bits;
    BitWriter writer = {0};
    bit_write(&writer, stats->dynamic, 1);
    if (stats->dynamic) {
        write_table(&writer, literal.lengths, count);
        write_table(&writer, distance.lengths, b + 1);
        token_part(&writer, tokens, literal.lengths, count, distance.lengths, b + 1);
    } else
        token_part(&writer, tokens, fixed_literal, count, fixed_distance, b + 1);
    free(literal.lengths);
    free(distance.lengths);
    bytes_free(&tables.bytes);
    bytes_free(&dynamic.bytes);
    bytes_free(&fixed.bytes);
    return writer.bytes;
}
static Bytes lz77_encode(const Tokens *tokens, int b, int k) {
    BitWriter writer = {0};
    for (size_t i = 0; i < tokens->count; ++i) {
        Token token = tokens->data[i];
        bit_write(&writer, token.length > 0, 1);
        if (token.length) {
            bit_write(&writer, (uint32_t)(token.distance - 1), b);
            bit_write(&writer, (uint32_t)(token.length - 3), k);
        } else
            bit_write(&writer, (uint32_t)token.literal, 8);
    }
    return writer.bytes;
}
static const char *decode(int method, const Bytes *payload, uint32_t original, int b, int k, Bytes *output) {
    if (method == 0) {
        for (size_t i = 0; i < payload->count; ++i) {
            if (output->count == original)
                return NULL;
            byte_push(output, payload->data[i]);
        }
        return output->count < original ? "end_of_data" : NULL;
    }
    if (method == 1)
        return lzw_decode(payload, original, output);
    if (method == 4)
        return arith_decode(payload, original, output);
    BitReader reader = {.bytes = payload};
    if (method == 2) {
        while (output->count < original) {
            int match = (int)bit_read(&reader, 1);
            if (reader.error)
                return reader.error;
            if (!match) {
                Byte byte = (Byte)bit_read(&reader, 8);
                if (reader.error)
                    return reader.error;
                byte_push(output, byte);
            } else {
                int distance = (int)bit_read(&reader, b) + 1;
                if (reader.error)
                    return reader.error;
                int length = (int)bit_read(&reader, k) + 3;
                if (reader.error)
                    return reader.error;
                const char *error = output_match(output, original, distance, length);
                if (error)
                    return error;
            }
        }
        return NULL;
    }
    int count = 256 + (1 << k), lengths[288], offsets[13];
    bool dynamic = bit_read(&reader, 1) != 0;
    if (reader.error)
        return reader.error;
    if (dynamic) {
        const char *error = read_table(&reader, count, lengths);
        if (error)
            return error;
        error = read_table(&reader, b + 1, offsets);
        if (error)
            return error;
    } else {
        fixed_lengths(count, lengths);
        fixed_lengths(b + 1, offsets);
    }
    int *codes = canonical_codes(lengths, count), *offset_codes = canonical_codes(offsets, b + 1);
    const char *error = NULL;
    while (output->count < original) {
        int symbol = read_symbol(&reader, lengths, codes, count);
        if (reader.error) {
            error = reader.error;
            break;
        }
        if (symbol < 256)
            byte_push(output, (Byte)symbol);
        else {
            int length = symbol - 253, slot = read_symbol(&reader, offsets, offset_codes, b + 1);
            if (reader.error) {
                error = reader.error;
                break;
            }
            int u = slot;
            if (slot >= 2) {
                u = (1 << (slot - 1)) + (int)bit_read(&reader, slot - 1);
                if (reader.error) {
                    error = reader.error;
                    break;
                }
            }
            error = output_match(output, original, u + 1, length);
            if (error)
                break;
        }
    }
    free(codes);
    free(offset_codes);
    return error;
}
typedef struct {
    Bytes payloads[5];
    int best;
    Tokens tokens;
    LzwStats lzw;
    LzhStats lzh;
    ArithStats arith;
} Encoded;
static Encoded encode(const Bytes *data, int b, int k, int maximum) {
    Encoded out = {0};
    out.tokens = tokenize(data, b, k);
    out.payloads[0] = bytes_copy(data);
    out.payloads[1] = lzw_encode(data, &out.lzw);
    out.payloads[2] = lz77_encode(&out.tokens, b, k);
    out.payloads[3] = lzh_encode(&out.tokens, b, k, maximum, &out.lzh);
    out.payloads[4] = arith_encode(data, &out.arith);
    for (int method = 1; method < 5; ++method)
        if (out.payloads[method].count < out.payloads[out.best].count)
            out.best = method;
    return out;
}
static void encoded_free(Encoded *encoded) {
    for (int method = 0; method < 5; ++method)
        bytes_free(&encoded->payloads[method]);
    free(encoded->tokens.data);
}
typedef struct {
    char *name;
    Bytes data, payload;
    int method;
} File;
typedef struct {
    File *data;
    size_t count, capacity;
} Files;
static void file_push(Files *files, File file) {
    if (files->count == files->capacity) {
        files->capacity = files->capacity ? 2 * files->capacity : 8;
        files->data = resize(files->data, files->capacity * sizeof(File));
    }
    files->data[files->count++] = file;
}
static void big_endian(Bytes *bytes, uint32_t value, int count) {
    for (int shift = 8 * (count - 1); shift >= 0; shift -= 8)
        byte_push(bytes, (Byte)((value >> shift) & 255));
}
static uint32_t read_integer(const Bytes *bytes, size_t first, int count) {
    uint32_t value = 0;
    for (int i = 0; i < count; ++i)
        value = (value << 8) | bytes->data[first + (size_t)i];
    return value;
}
static Bytes build_archive(const Files *files, int b, int k) {
    Bytes archive = {0};
    bytes_append(&archive, (const Byte *)"TXAR", 4);
    byte_push(&archive, (Byte)b);
    byte_push(&archive, (Byte)k);
    big_endian(&archive, (uint32_t)files->count, 2);
    for (size_t f = 0; f < files->count; ++f) {
        const File *file = &files->data[f];
        size_t first = archive.count;
        byte_push(&archive, (Byte)strlen(file->name));
        bytes_append(&archive, (const Byte *)file->name, strlen(file->name));
        byte_push(&archive, (Byte)file->method);
        big_endian(&archive, (uint32_t)file->data.count, 4);
        big_endian(&archive, (uint32_t)file->payload.count, 4);
        big_endian(&archive, adler(&file->data), 4);
        int sum = 0;
        for (size_t i = first; i < archive.count; ++i)
            sum += archive.data[i];
        byte_push(&archive, (Byte)(sum % 256));
        bytes_append(&archive, file->payload.data, file->payload.count);
    }
    return archive;
}
typedef struct {
    int number, method;
    size_t position, start;
    uint32_t original, compressed, stored, computed;
    char *name;
    const char *status, *error;
    bool valid, header_cut;
    Bytes output;
    size_t error_position, repair_position;
    int repair_from, repair_to;
} Entry;
typedef struct {
    const char *error;
    int b, k, declared;
    size_t size, trailing;
    bool stopped;
    Entry *entries;
    size_t count, capacity;
} Parsed;
static void entry_push(Parsed *parsed, Entry entry) {
    if (parsed->count == parsed->capacity) {
        parsed->capacity = parsed->capacity ? 2 * parsed->capacity : 8;
        parsed->entries = resize(parsed->entries, parsed->capacity * sizeof(Entry));
    }
    parsed->entries[parsed->count++] = entry;
}
static Integer modulo(Integer value, Integer modulus) {
    Integer remainder = value % modulus;
    return remainder < 0 ? remainder + modulus : remainder;
}
static Integer power_mod(Integer value, Integer exponent) {
    Integer result = 1;
    while (exponent) {
        if (exponent % 2)
            result = result * value % 65521;
        value = value * value % 65521;
        exponent /= 2;
    }
    return result;
}
static bool repair(Entry *entry) {
    Integer delta_a = modulo((Integer)(entry->stored % 65536) - (Integer)(entry->computed % 65536), 65521),
            delta_b = modulo((Integer)(entry->stored / 65536) - (Integer)(entry->computed / 65536), 65521),
            delta;
    if (delta_a >= 1 && delta_a <= 255)
        delta = delta_a;
    else if (delta_a >= 65266 && delta_a <= 65520)
        delta = delta_a - 65521;
    else
        return false;
    Integer inverse = power_mod(modulo(delta, 65521), 65519), t = delta_b * inverse % 65521;
    if (t < 1 || t > (Integer)entry->output.count)
        return false;
    size_t position = entry->output.count - (size_t)t;
    int old = entry->output.data[position], value = old + (int)delta;
    if (value < 0 || value > 255)
        return false;
    entry->output.data[position] = (Byte)value;
    if (adler(&entry->output) != entry->stored) {
        entry->output.data[position] = (Byte)old;
        return false;
    }
    entry->repair_position = position;
    entry->repair_from = old;
    entry->repair_to = value;
    return true;
}
static bool valid_name(const char *name, int length) {
    if (length == 0 || length > 32)
        return false;
    for (int i = 0; i < length; ++i) {
        char c = name[i];
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-'))
            return false;
    }
    return true;
}
static Parsed parse(const Bytes *bytes) {
    Parsed out = {.size = bytes->count};
    if (bytes->count < 8 || memcmp(bytes->data, "TXAR", 4)) {
        out.error = "bad_magic";
        return out;
    }
    out.b = bytes->data[4];
    out.k = bytes->data[5];
    if (out.b < 6 || out.b > 12 || out.k < 2 || out.k > 5) {
        out.error = "bad_params";
        return out;
    }
    out.declared = (int)read_integer(bytes, 6, 2);
    size_t position = 8;
    for (int number = 1; number <= out.declared; ++number) {
        Entry entry = {.number = number, .position = position};
        if (position >= bytes->count || position + 15 + bytes->data[position] > bytes->count) {
            entry.status = "truncated";
            entry.header_cut = true;
            entry_push(&out, entry);
            out.stopped = true;
            break;
        }
        int length = bytes->data[position];
        entry.name = resize(NULL, (size_t)length + 1);
        memcpy(entry.name, bytes->data + position + 1, (size_t)length);
        entry.name[length] = 0;
        entry.method = bytes->data[position + 1 + (size_t)length];
        entry.original = read_integer(bytes, position + 2 + (size_t)length, 4);
        entry.compressed = read_integer(bytes, position + 6 + (size_t)length, 4);
        entry.stored = read_integer(bytes, position + 10 + (size_t)length, 4);
        entry.start = position + 15 + (size_t)length;
        size_t next = entry.start + entry.compressed;
        int sum = 0;
        for (size_t i = position; i < entry.start - 1; ++i)
            sum += bytes->data[i];
        if (sum % 256 != bytes->data[entry.start - 1] || !valid_name(entry.name, length)) {
            entry.status = "bad_header";
            position = next;
            entry_push(&out, entry);
            if (position > bytes->count) {
                out.stopped = true;
                break;
            }
            continue;
        }
        entry.valid = true;
        if (next > bytes->count) {
            entry.status = "truncated";
            entry_push(&out, entry);
            out.stopped = true;
            break;
        }
        if (entry.method >= 5)
            entry.status = "unsupported";
        else {
            Bytes payload = {.data = bytes->data + entry.start, .count = entry.compressed};
            entry.error = decode(entry.method, &payload, entry.original, out.b, out.k, &entry.output);
            if (entry.error) {
                entry.status = "error";
                entry.error_position = entry.output.count;
            } else {
                entry.computed = adler(&entry.output);
                entry.status = entry.computed == entry.stored ? "ok"
                               : repair(&entry)               ? "repaired"
                                                              : "checksum";
            }
        }
        entry_push(&out, entry);
        position = next;
    }
    if (!out.stopped)
        out.trailing = bytes->count - position;
    return out;
}
static void parsed_free(Parsed *parsed) {
    for (size_t i = 0; i < parsed->count; ++i) {
        free(parsed->entries[i].name);
        bytes_free(&parsed->entries[i].output);
    }
    free(parsed->entries);
}
static int verified(const Parsed *parsed, const Files *files) {
    int count = 0;
    for (size_t i = 0; i < parsed->count && i < files->count; ++i) {
        const Entry *entry = &parsed->entries[i];
        const Bytes *data = &files->data[i].data;
        count += !strcmp(entry->status, "ok") && entry->output.count == data->count &&
                 (!data->count || !memcmp(entry->output.data, data->data, data->count));
    }
    return count;
}
static Lines listing(const Parsed *parsed) {
    Lines out = {0};
    if (parsed->error) {
        line_push(&out, format("archive bytes %zu error %s", parsed->size, parsed->error));
        return out;
    }
    line_push(&out, format("archive bytes %zu offset_bits %d length_bits %d entries %d", parsed->size,
                           parsed->b, parsed->k, parsed->declared));
    Integer counts[5] = {0}, original[5] = {0}, compressed[5] = {0};
    int listed = 0;
    for (size_t i = 0; i < parsed->count; ++i) {
        const Entry *entry = &parsed->entries[i];
        if (entry->header_cut)
            line_push(&out, format("entry %d offset %zu truncated header", entry->number, entry->position));
        else if (!entry->valid)
            line_push(&out, format("entry %d offset %zu bad_header", entry->number, entry->position));
        else {
            ++listed;
            line_push(
                &out,
                format("entry %d offset %zu method %s original %u compressed %u ratio %s adler %s name %s",
                       entry->number, entry->position, method_name(entry->method), entry->original,
                       entry->compressed, ratio(entry->original, entry->compressed), hex8(entry->stored),
                       entry->name));
            if (entry->method < 5) {
                ++counts[entry->method];
                original[entry->method] += entry->original;
                compressed[entry->method] += entry->compressed;
            }
        }
    }
    for (int method = 0; method < 5; ++method)
        line_push(&out, format("method %s entries %lld original %lld compressed %lld ratio %s",
                               methods[method], (long long)counts[method], (long long)original[method],
                               (long long)compressed[method], ratio(original[method], compressed[method])));
    line_push(&out, format("end listed %d of %d stop %s trailing %zu", listed, parsed->declared,
                           parsed->stopped ? "truncated" : "complete", parsed->trailing));
    return out;
}
static void compare(Lines *out, const char *name, const Lines *old, const Lines *fresh) {
    size_t first = 0;
    while (first < old->count && first < fresh->count && !strcmp(old->data[first], fresh->data[first]))
        ++first;
    if (first == old->count && first == fresh->count) {
        line_push(out, format("same %s lines %zu", name, old->count));
        return;
    }
    size_t a = old->count, b = fresh->count, width = b + 1;
    uint32_t *lcs = calloc((a + 1) * (b + 1), sizeof(uint32_t));
    for (size_t i = a; i > 0;) {
        --i;
        for (size_t j = b; j > 0;) {
            --j;
            lcs[i * width + j] = !strcmp(old->data[i], fresh->data[j]) ? 1 + lcs[(i + 1) * width + j + 1]
                                 : lcs[(i + 1) * width + j] >= lcs[i * width + j + 1]
                                     ? lcs[(i + 1) * width + j]
                                     : lcs[i * width + j + 1];
        }
    }
    Lines edits = {0};
    size_t i = 0, j = 0, removed = 0, added = 0;
    while (i < a || j < b) {
        if (i < a && j < b && !strcmp(old->data[i], fresh->data[j])) {
            ++i;
            ++j;
        } else if (j == b || (i < a && lcs[(i + 1) * width + j] >= lcs[i * width + j + 1])) {
            line_push(&edits, format("-%zu:%s", i + 1, old->data[i]));
            ++i;
            ++removed;
        } else {
            line_push(&edits, format("+%zu:%s", j + 1, fresh->data[j]));
            ++j;
            ++added;
        }
    }
    line_push(out,
              format("differs %s first_line %zu archive_lines %zu manifest_lines %zu removed %zu added %zu",
                     name, first + 1, a, b, removed, added));
    lines_extend(out, &edits);
    lines_free(&edits);
    free(lcs);
}
static bool intact(const Entry *entry) {
    return !strcmp(entry->status, "ok") || !strcmp(entry->status, "repaired");
}
int main(void) {
    mkdir("output", 0777);
    Bytes manifest_bytes = read_bytes("input/manifest.txt");
    Lines manifest = text_lines(&manifest_bytes);
    int b = atoi(strchr(manifest.data[0], ' ') + 1), k = atoi(strchr(manifest.data[1], ' ') + 1),
        maximum = atoi(strchr(manifest.data[2], ' ') + 1);
    Files files = {0};
    Lines sizes = {0}, analysis = {0};
    line_push(&sizes, format("params offset_bits %d length_bits %d window %d lookahead %d max_code_length %d",
                             b, k, 1 << b, (1 << k) + 2, maximum));
    Integer original_total = 0, best_total = 0, totals[5] = {0}, chosen[5] = {0};
    for (size_t i = 3; i < manifest.count; ++i) {
        File file = {.name = text(strchr(manifest.data[i], ' ') + 1)};
        char *path = format("input/files/%s", file.name);
        file.data = read_bytes(path);
        free(path);
        Encoded encoded = encode(&file.data, b, k, maximum);
        file.method = encoded.best;
        file.payload = bytes_copy(&encoded.payloads[file.method]);
        original_total += (Integer)file.data.count;
        best_total += (Integer)file.payload.count;
        ++chosen[file.method];
        char *line = format("file %s original %zu", file.name, file.data.count);
        for (int method = 0; method < 5; ++method) {
            totals[method] += (Integer)encoded.payloads[method].count;
            char *next = format("%s %s %zu %s", line, methods[method], encoded.payloads[method].count,
                                ratio((Integer)file.data.count, (Integer)encoded.payloads[method].count));
            free(line);
            line = next;
        }
        line_push(&sizes, format("%s best %s", line, methods[file.method]));
        free(line);
        LzwStats *lzw = &encoded.lzw;
        line_push(&analysis, format("lzw %s codes %d clears %d widths %d %d %d %d longest %d", file.name,
                                    lzw->codes, lzw->clears, lzw->widths[0], lzw->widths[1], lzw->widths[2],
                                    lzw->widths[3], lzw->longest));
        int literals = 0, matches = 0, matched = 0, longest = 0, farthest = 0;
        for (size_t t = 0; t < encoded.tokens.count; ++t) {
            Token token = encoded.tokens.data[t];
            if (token.length) {
                ++matches;
                matched += token.length;
                if (token.length > longest)
                    longest = token.length;
                if (token.distance > farthest)
                    farthest = token.distance;
            } else
                ++literals;
        }
        line_push(&analysis,
                  format("lz77 %s tokens %zu literals %d matches %d matched %d longest %d farthest %d",
                         file.name, encoded.tokens.count, literals, matches, matched, longest, farthest));
        LzhStats *lzh = &encoded.lzh;
        line_push(
            &analysis,
            format(
                "lzh %s mode %s fixed_bits %d table_bits %d code_bits %d halvings %d litlen_used %d litlen_max %d offset_used %d offset_max %d",
                file.name, lzh->dynamic ? "dynamic" : "fixed", lzh->fixed_bits, lzh->table_bits,
                lzh->code_bits, lzh->halvings, lzh->litlen_used, lzh->litlen_max, lzh->offset_used,
                lzh->offset_max));
        line = format("slots %s", file.name);
        for (int slot = 0; slot <= b; ++slot) {
            char *next = format("%s %d", line, lzh->slots[slot]);
            free(line);
            line = next;
        }
        line_push(&analysis, line);
        line_push(&analysis, format("arith %s bits %d contexts %d rescales %d", file.name, encoded.arith.bits,
                                    encoded.arith.contexts, encoded.arith.rescales));
        file_push(&files, file);
        encoded_free(&encoded);
    }
    char *total = format("total original %lld", (long long)original_total), *choice = text("chosen");
    for (int method = 0; method < 5; ++method) {
        char *next = format("%s %s %lld %s", total, methods[method], (long long)totals[method],
                            ratio(original_total, totals[method]));
        free(total);
        total = next;
        next = format("%s %s %lld", choice, methods[method], (long long)chosen[method]);
        free(choice);
        choice = next;
    }
    line_push(&sizes,
              format("%s best %lld %s", total, (long long)best_total, ratio(original_total, best_total)));
    free(total);
    line_push(&sizes, choice);
    Bytes created = build_archive(&files, b, k);
    Parsed verification = parse(&created);
    line_push(&sizes, format("archive bytes %zu entries %zu ratio %s", created.count, files.count,
                             ratio(original_total, (Integer)created.count)));
    line_push(&sizes,
              format("verify entries %zu ok %d", verification.count, verified(&verification, &files)));
    write_owned("sizes.txt", sizes);
    write_owned("analysis.txt", analysis);
    write_owned("archive.hex", hex_lines(&created));
    parsed_free(&verification);
    bytes_free(&created);
    Bytes hex = read_bytes("input/archive.hex"), given = {0};
    Lines hex_input = text_lines(&hex);
    for (size_t l = 0; l < hex_input.count; ++l) {
        const char *line = hex_input.data[l];
        for (size_t i = 0; line[i]; i += 2) {
            char pair[3] = {line[i], line[i + 1], 0};
            byte_push(&given, (Byte)strtoul(pair, NULL, 16));
        }
    }
    lines_free(&hex_input);
    bytes_free(&hex);
    Parsed parsed = parse(&given);
    write_owned("listing.txt", listing(&parsed));
    Lines tested = {0}, extracted = {0}, comparison = {0};
    Files salvage = {0};
    if (parsed.error)
        line_push(&tested, format("archive error %s", parsed.error));
    else {
        const char *statuses[] = {"ok",          "repaired",  "checksum",  "error",
                                  "unsupported", "truncated", "bad_header"};
        int counts[7] = {0};
        for (size_t i = 0; i < parsed.count; ++i) {
            const Entry *entry = &parsed.entries[i];
            for (int s = 0; s < 7; ++s)
                if (!strcmp(statuses[s], entry->status))
                    ++counts[s];
            if (entry->header_cut)
                line_push(&tested, format("entry %d offset %zu status truncated header", entry->number,
                                          entry->position));
            else if (!entry->valid)
                line_push(&tested,
                          format("entry %d offset %zu status bad_header", entry->number, entry->position));
            else {
                char *line = format("entry %d offset %zu name %s method %s status %s", entry->number,
                                    entry->position, entry->name, method_name(entry->method), entry->status),
                     *details = NULL;
                if (!strcmp(entry->status, "repaired"))
                    details = format(" byte %zu from %d to %d", entry->repair_position, entry->repair_from,
                                     entry->repair_to);
                else if (!strcmp(entry->status, "checksum"))
                    details = format(" stored %s computed %s", hex8(entry->stored), hex8(entry->computed));
                else if (!strcmp(entry->status, "error"))
                    details = format(" %s at %zu", entry->error, entry->error_position);
                else if (!strcmp(entry->status, "truncated"))
                    details =
                        format(" payload have %zu need %u", parsed.size - entry->start, entry->compressed);
                if (details) {
                    line_push(&tested, format("%s%s", line, details));
                    free(line);
                    free(details);
                } else
                    line_push(&tested, line);
            }
        }
        char *summary = format("summary entries %d checked %zu", parsed.declared, parsed.count);
        for (int s = 0; s < 7; ++s) {
            char *next = format("%s %s %d", summary, statuses[s], counts[s]);
            free(summary);
            summary = next;
        }
        line_push(&tested, format("%s missing %zu trailing %zu", summary,
                                  (size_t)parsed.declared - parsed.count, parsed.trailing));
        free(summary);
    }
    int salvage_b = parsed.error ? b : parsed.b, salvage_k = parsed.error ? k : parsed.k;
    Integer salvage_original = 0;
    for (size_t i = 0; i < parsed.count; ++i) {
        const Entry *entry = &parsed.entries[i];
        if (!intact(entry))
            continue;
        Lines lines = text_lines(&entry->output);
        int word_count = 0;
        size_t longest = 0;
        for (size_t j = 0; j < lines.count; ++j) {
            size_t length = strlen(lines.data[j]);
            if (length > longest)
                longest = length;
            bool in_word = false;
            for (size_t t = 0; t < length; ++t) {
                if (lines.data[j][t] == ' ')
                    in_word = false;
                else if (!in_word) {
                    ++word_count;
                    in_word = true;
                }
            }
        }
        line_push(&extracted, format("file %s bytes %zu lines %zu words %d longest %zu", entry->name,
                                     entry->output.count, lines.count, word_count, longest));
        lines_extend(&extracted, &lines);
        size_t found = 0;
        while (found < files.count && strcmp(files.data[found].name, entry->name))
            ++found;
        if (found == files.count)
            line_push(&comparison, format("archive_only %s", entry->name));
        else {
            Lines fresh = text_lines(&files.data[found].data);
            compare(&comparison, entry->name, &lines, &fresh);
            lines_free(&fresh);
        }
        lines_free(&lines);
        Encoded encoded = encode(&entry->output, salvage_b, salvage_k, maximum);
        File file = {text(entry->name), bytes_copy(&entry->output),
                     bytes_copy(&encoded.payloads[encoded.best]), encoded.best};
        line_push(&tested,
                  format("salvage %s method %s compressed %zu was %s %u", entry->name, methods[file.method],
                         file.payload.count, method_name(entry->method), entry->compressed));
        salvage_original += (Integer)file.data.count;
        file_push(&salvage, file);
        encoded_free(&encoded);
    }
    for (size_t i = 0; i < files.count; ++i) {
        bool found = false;
        for (size_t j = 0; j < salvage.count; ++j)
            if (!strcmp(files.data[i].name, salvage.data[j].name))
                found = true;
        if (!found)
            line_push(&comparison, format("new %s", files.data[i].name));
    }
    Bytes salvaged = build_archive(&salvage, salvage_b, salvage_k);
    verification = parse(&salvaged);
    line_push(&tested,
              format("salvaged entries %zu bytes %zu original %lld verified %d", salvage.count,
                     salvaged.count, (long long)salvage_original, verified(&verification, &salvage)));
    write_owned("test_report.txt", tested);
    write_owned("extracted.txt", extracted);
    write_owned("compare.txt", comparison);
    write_owned("salvaged.hex", hex_lines(&salvaged));
    parsed_free(&verification);
    parsed_free(&parsed);
    bytes_free(&given);
    bytes_free(&salvaged);
    for (size_t i = 0; i < files.count; ++i) {
        free(files.data[i].name);
        bytes_free(&files.data[i].data);
        bytes_free(&files.data[i].payload);
    }
    for (size_t i = 0; i < salvage.count; ++i) {
        free(salvage.data[i].name);
        bytes_free(&salvage.data[i].data);
        bytes_free(&salvage.data[i].payload);
    }
    free(files.data);
    free(salvage.data);
    lines_free(&manifest);
    bytes_free(&manifest_bytes);
    return 0;
}
