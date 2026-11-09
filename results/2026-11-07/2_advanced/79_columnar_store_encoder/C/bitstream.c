#include "columnar.h"
Reader reader_create(Bytes data, size_t position) {
    return (Reader){data.items, data.count, position};
}
int read_byte(Reader *reader) { return reader->data[reader->position++]; }
Bytes read_bytes(Reader *reader, size_t count) {
    Bytes out = {.items = allocate(count), .count = count, .capacity = count};
    memcpy(out.items, reader->data + reader->position, count);
    reader->position += count;
    return out;
}
char *read_string(Reader *reader, size_t count) {
    char *out = substring((const char *)reader->data + reader->position, count);
    reader->position += count;
    return out;
}
Number read_uleb(Reader *reader) {
    Number value = 0;
    int shift = 0;
    for (;;) {
        int byte = read_byte(reader);
        value |= (Number)(byte & 127) << shift;
        if (byte < 128)
            return value;
        shift += 7;
    }
}
Number read_zigzag(Reader *reader) {
    Number value = read_uleb(reader);
    return value % 2 == 0 ? value / 2 : -(value + 1) / 2;
}
Number read_integer(Reader *reader, bool signed_value) {
    Number value = 0;
    for (int i = 0; i < 4; ++i)
        value |= (Number)read_byte(reader) << (8 * i);
    return signed_value && value >= (1LL << 31) ? value - (1LL << 32) : value;
}
void write_uleb(Bytes *out, Number value) {
    while (value >= 128) {
        Bytes_add(out, (unsigned char)(value % 128 + 128));
        value /= 128;
    }
    Bytes_add(out, (unsigned char)value);
}
void write_zigzag(Bytes *out, Number value) {
    write_uleb(out, value >= 0 ? 2 * value : -2 * value - 1);
}
void write_integer(Bytes *out, Number value) {
    if (value < 0)
        value += 1LL << 32;
    for (int i = 0; i < 4; ++i)
        Bytes_add(out, (unsigned char)((value >> (8 * i)) & 255));
}
int bits(Number value) {
    int width = 0;
    while (value) {
        value >>= 1;
        ++width;
    }
    return width;
}
Bytes pack(Numbers values, int width) {
    Bytes out = {0};
    unsigned long long buffer = 0;
    int occupied = 0;
    for (size_t i = 0; i < values.count; ++i) {
        buffer |= (unsigned long long)values.items[i] << occupied;
        occupied += width;
        while (occupied >= 8) {
            Bytes_add(&out, (unsigned char)(buffer & 255));
            buffer >>= 8;
            occupied -= 8;
        }
    }
    return out;
}
Numbers unpack(Reader *reader, int width, int count) {
    Numbers out = {0};
    unsigned long long buffer = 0, mask = (1ULL << width) - 1;
    int occupied = 0;
    for (int i = 0; i < count; ++i) {
        while (occupied < width) {
            buffer |= (unsigned long long)read_byte(reader) << occupied;
            occupied += 8;
        }
        Numbers_add(&out, (Number)(buffer & mask));
        buffer >>= width;
        occupied -= width;
    }
    return out;
}
Number adler32(Bytes data) {
    Number a = 1, b = 0;
    for (size_t i = 0; i < data.count; ++i) {
        a = (a + data.items[i]) % 65521;
        b = (b + a) % 65521;
    }
    return b * 65536 + a;
}
Bytes hybrid_encode(Numbers values, int width) {
    int *runs = allocate(values.count * sizeof(int));
    for (size_t i = values.count; i > 0;) {
        --i;
        runs[i] =
            1 + (i + 1 < values.count && values.items[i] == values.items[i + 1] ? runs[i + 1] : 0);
    }
    Bytes out = {0};
    for (size_t i = 0; i < values.count;) {
        if (runs[i] >= 8) {
            write_uleb(&out, 2 * (Number)runs[i]);
            for (int j = 0; j < (width + 7) / 8; ++j)
                Bytes_add(&out, (unsigned char)((values.items[i] >> (8 * j)) & 255));
            i += (size_t)runs[i];
        } else {
            size_t end = i;
            int groups = 0;
            do {
                end += 8;
                ++groups;
            } while (end < values.count && groups < 63 && runs[end] < 8);
            write_uleb(&out, 2 * groups + 1);
            Numbers block = {0};
            for (size_t j = i; j < end; ++j)
                Numbers_add(&block, j < values.count ? values.items[j] : 0);
            append_bytes(&out, pack(block, width));
            i = end;
        }
    }
    return out;
}
Numbers hybrid_decode(Reader *reader, int width, int count) {
    Numbers out = {0};
    while (out.count < (size_t)count) {
        Number header = read_uleb(reader);
        if (header % 2 == 0) {
            Number value = 0;
            for (int i = 0; i < (width + 7) / 8; ++i)
                value |= (Number)read_byte(reader) << (8 * i);
            for (Number i = 0; i < header / 2; ++i)
                Numbers_add(&out, value);
        } else {
            Numbers block = unpack(reader, width, (int)((header - 1) / 2 * 8));
            for (size_t i = 0; i < block.count; ++i)
                Numbers_add(&out, block.items[i]);
        }
    }
    out.count = (size_t)count;
    return out;
}
char *hexadecimal(Bytes data) {
    const char *digits = "0123456789abcdef";
    char *out = allocate(2 * data.count + 1);
    for (size_t i = 0; i < data.count; ++i) {
        out[2 * i] = digits[data.items[i] >> 4];
        out[2 * i + 1] = digits[data.items[i] & 15];
    }
    return out;
}
char *checksum_text(Number checksum) { return format("%08llx", (unsigned long long)checksum); }
