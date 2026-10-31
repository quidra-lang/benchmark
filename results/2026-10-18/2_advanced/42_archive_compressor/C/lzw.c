#include "archive.h"
static void emit(BitWriter *writer, LzwStats *stats, int *counter, int code) {
    int width = bits((uint32_t)(258 + *counter));
    if (width > 12)
        width = 12;
    bit_write(writer, (uint32_t)code, width);
    ++stats->codes;
    ++stats->widths[width - 9];
    if (code == 256) {
        ++stats->clears;
        *counter = 0;
    } else
        ++*counter;
}
Bytes lzw_encode(const Bytes *data, LzwStats *stats) {
    int prefix[4096] = {0}, length[4096] = {0};
    Byte suffix[4096] = {0};
    for (int i = 0; i < 256; ++i)
        length[i] = 1;
    int next = 258, counter = 0, current = -1;
    BitWriter writer = {0};
    emit(&writer, stats, &counter, 256);
    for (size_t i = 0; i < data->count; ++i) {
        Byte byte = data->data[i];
        if (current < 0) {
            current = byte;
            continue;
        }
        int candidate = -1;
        for (int code = 258; code < next; ++code)
            if (prefix[code] == current && suffix[code] == byte) {
                candidate = code;
                break;
            }
        if (candidate >= 0)
            current = candidate;
        else {
            emit(&writer, stats, &counter, current);
            if (length[current] > stats->longest)
                stats->longest = length[current];
            prefix[next] = current;
            suffix[next] = byte;
            length[next] = length[current] + 1;
            if (++next == 4096) {
                emit(&writer, stats, &counter, 256);
                next = 258;
            }
            current = byte;
        }
    }
    if (current >= 0) {
        emit(&writer, stats, &counter, current);
        if (length[current] > stats->longest)
            stats->longest = length[current];
    }
    emit(&writer, stats, &counter, 257);
    return writer.bytes;
}
static int expand(int code, const int *prefix, const Byte *suffix, Byte *output) {
    Byte reverse[4096];
    int length = 0;
    while (code >= 258) {
        reverse[length++] = suffix[code];
        code = prefix[code];
    }
    reverse[length++] = (Byte)code;
    for (int i = 0; i < length; ++i)
        output[i] = reverse[length - 1 - i];
    return length;
}
const char *lzw_decode(const Bytes *payload, uint32_t size, Bytes *output) {
    int prefix[4096] = {0};
    Byte suffix[4096] = {0}, entry[4096];
    int next = 258, previous = -1, counter = 0;
    BitReader reader = {.bytes = payload};
    while (true) {
        int before = counter, width = bits((uint32_t)(258 + counter));
        if (width > 12)
            width = 12;
        int code = (int)bit_read(&reader, width);
        if (reader.error)
            return reader.error;
        if (code == 256) {
            next = 258;
            previous = -1;
            counter = 0;
            continue;
        }
        ++counter;
        if (code == 257)
            return output->count < size ? "early_end" : NULL;
        if (before == 3838)
            return "bad_code";
        int length = 0;
        if (previous < 0) {
            if (code >= 256)
                return "bad_code";
            entry[length++] = (Byte)code;
        } else if (code < next)
            length = expand(code, prefix, suffix, entry);
        else if (code == next) {
            length = expand(previous, prefix, suffix, entry);
            entry[length] = entry[0];
            ++length;
        } else
            return "bad_code";
        if (output->count + (size_t)length > size)
            return "overrun";
        bytes_append(output, entry, (size_t)length);
        if (previous >= 0) {
            prefix[next] = previous;
            suffix[next++] = entry[0];
        }
        previous = code;
    }
}
