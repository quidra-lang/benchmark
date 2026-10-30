#include "columnar.h"
const char *methods[5] = {"PLAIN", "DICTIONARY", "RLE", "DELTA_BINARY_PACKED",
                          "DELTA_LENGTH_BYTE_ARRAY"};
Numbers candidates(Type kind) {
    Numbers out = {0};
    Numbers_add(&out, 0);
    if (kind == T_BOOL)
        Numbers_add(&out, 2);
    else {
        Numbers_add(&out, 1);
        Numbers_add(&out, kind == T_STRING ? 4 : 3);
    }
    return out;
}
Bytes delta_encode(Numbers values) {
    Bytes out = {0};
    write_uleb(&out, 128);
    write_uleb(&out, 4);
    write_uleb(&out, (Number)values.count);
    write_zigzag(&out, values.count ? values.items[0] : 0);
    Numbers differences = {0};
    for (size_t i = 1; i < values.count; ++i)
        Numbers_add(&differences, values.items[i] - values.items[i - 1]);
    for (size_t start = 0; start < differences.count; start += 128) {
        size_t end = start + 128 < differences.count ? start + 128 : differences.count;
        Number minimum = differences.items[start];
        for (size_t i = start + 1; i < end; ++i)
            if (differences.items[i] < minimum)
                minimum = differences.items[i];
        write_zigzag(&out, minimum);
        Numbers blocks[4] = {0};
        int widths[4] = {0};
        for (int t = 0; t < 4; ++t) {
            size_t last = start + 32 * (size_t)(t + 1);
            if (last > end)
                last = end;
            for (size_t i = start + 32 * (size_t)t; i < last; ++i) {
                Number value = differences.items[i] - minimum;
                Numbers_add(&blocks[t], value);
                int width = bits(value);
                if (width > widths[t])
                    widths[t] = width;
            }
        }
        for (int t = 0; t < 4; ++t)
            Bytes_add(&out, (unsigned char)widths[t]);
        for (int t = 0; t < 4; ++t)
            if (blocks[t].count) {
                while (blocks[t].count < 32)
                    Numbers_add(&blocks[t], 0);
                append_bytes(&out, pack(blocks[t], widths[t]));
            }
    }
    return out;
}
Numbers delta_decode(Reader *reader) {
    int block_size = (int)read_uleb(reader);
    int miniblock_count = (int)read_uleb(reader);
    int count = (int)read_uleb(reader);
    Number first = read_zigzag(reader);
    Numbers values = {0};
    if (count)
        Numbers_add(&values, first);
    int miniblock_size = block_size / miniblock_count;
    while (values.count < (size_t)count) {
        Number minimum = read_zigzag(reader);
        int *widths = allocate((size_t)miniblock_count * sizeof(int));
        for (int t = 0; t < miniblock_count; ++t)
            widths[t] = read_byte(reader);
        for (int t = 0; t < miniblock_count && values.count < (size_t)count; ++t) {
            Numbers differences = unpack(reader, widths[t], miniblock_size);
            int left = count - (int)values.count, n = left < miniblock_size ? left : miniblock_size;
            for (int i = 0; i < n; ++i)
                Numbers_add(&values,
                            values.items[values.count - 1] + minimum + differences.items[i]);
        }
    }
    return values;
}
Bytes encode_values(Type kind, int method, Values values, Values dictionary) {
    Bytes out = {0};
    Numbers numbers = {0};
    for (size_t i = 0; i < values.count; ++i)
        Numbers_add(&numbers, values.items[i].number);
    if (method == 0) {
        if (kind == T_INT || kind == T_DATE)
            for (size_t i = 0; i < numbers.count; ++i)
                write_integer(&out, numbers.items[i]);
        else if (kind == T_STRING)
            for (size_t i = 0; i < values.count; ++i) {
                char *s = values.items[i].string;
                write_integer(&out, (Number)strlen(s));
                for (size_t j = 0; s[j]; ++j)
                    Bytes_add(&out, (unsigned char)s[j]);
            }
        else {
            while (numbers.count % 8)
                Numbers_add(&numbers, 0);
            out = pack(numbers, 1);
        }
        return out;
    }
    if (method == 1) {
        int width = bits((Number)dictionary.count - 1);
        Bytes_add(&out, (unsigned char)width);
        Numbers ranks = {0};
        for (size_t i = 0; i < values.count; ++i) {
            size_t rank = 0;
            while (!value_equal(dictionary.items[rank], values.items[i]))
                ++rank;
            Numbers_add(&ranks, (Number)rank);
        }
        append_bytes(&out, hybrid_encode(ranks, width));
        return out;
    }
    if (method == 2) {
        Bytes encoded = hybrid_encode(numbers, 1);
        write_integer(&out, (Number)encoded.count);
        append_bytes(&out, encoded);
        return out;
    }
    if (method == 3)
        return delta_encode(numbers);
    Numbers lengths = {0};
    for (size_t i = 0; i < values.count; ++i)
        Numbers_add(&lengths, (Number)strlen(values.items[i].string));
    out = delta_encode(lengths);
    for (size_t i = 0; i < values.count; ++i)
        for (size_t j = 0; values.items[i].string[j]; ++j)
            Bytes_add(&out, (unsigned char)values.items[i].string[j]);
    return out;
}
Values decode_values(Reader *reader, Type kind, int method, int count, Values dictionary) {
    Values out = {0};
    if (method == 0) {
        if (kind == T_INT || kind == T_DATE)
            for (int i = 0; i < count; ++i)
                Values_add(&out, number_value(read_integer(reader, true)));
        else if (kind == T_STRING)
            for (int i = 0; i < count; ++i) {
                size_t length = (size_t)read_integer(reader, false);
                Values_add(&out, string_value(read_string(reader, length)));
            }
        else {
            Numbers values = unpack(reader, 1, (count + 7) / 8 * 8);
            for (int i = 0; i < count; ++i)
                Values_add(&out, number_value(values.items[i] != 0));
        }
        return out;
    }
    if (method == 1) {
        int width = read_byte(reader);
        Numbers ranks = hybrid_decode(reader, width, count);
        for (size_t i = 0; i < ranks.count; ++i)
            Values_add(&out, dictionary.items[ranks.items[i]]);
        return out;
    }
    if (method == 2) {
        size_t length = (size_t)read_integer(reader, false);
        Bytes data = read_bytes(reader, length);
        Reader encoded = reader_create(data, 0);
        Numbers values = hybrid_decode(&encoded, 1, count);
        for (size_t i = 0; i < values.count; ++i)
            Values_add(&out, number_value(values.items[i] != 0));
        return out;
    }
    if (method == 3) {
        Numbers values = delta_decode(reader);
        for (size_t i = 0; i < values.count; ++i)
            Values_add(&out, number_value(values.items[i]));
        return out;
    }
    Numbers lengths = delta_decode(reader);
    for (size_t i = 0; i < lengths.count; ++i)
        Values_add(&out, string_value(read_string(reader, (size_t)lengths.items[i])));
    return out;
}
Bytes encode_statistics(Type kind, Bounds bounds) {
    Bytes out = {0};
    Bytes_add(&out, bounds.present);
    if (!bounds.present)
        return out;
    Value values[] = {bounds.low, bounds.high};
    for (int i = 0; i < 2; ++i) {
        Value v = values[i];
        if (kind == T_INT || kind == T_DATE)
            write_zigzag(&out, v.number);
        else if (kind == T_STRING) {
            write_uleb(&out, (Number)strlen(v.string));
            for (size_t j = 0; v.string[j]; ++j)
                Bytes_add(&out, (unsigned char)v.string[j]);
        } else
            Bytes_add(&out, (unsigned char)v.number);
    }
    return out;
}
Bounds decode_statistics(Reader *reader, Type kind) {
    if (!read_byte(reader))
        return (Bounds){0};
    Value values[2];
    for (int i = 0; i < 2; ++i) {
        if (kind == T_INT || kind == T_DATE)
            values[i] = number_value(read_zigzag(reader));
        else if (kind == T_STRING) {
            size_t length = (size_t)read_uleb(reader);
            values[i] = string_value(read_string(reader, length));
        } else
            values[i] = number_value(read_byte(reader) != 0);
    }
    return (Bounds){true, values[0], values[1]};
}
