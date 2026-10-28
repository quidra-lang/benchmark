#include "archive.h"
void *resize(void *memory, size_t size) {
    void *out = realloc(memory, size ? size : 1);
    if (!out)
        exit(1);
    return out;
}
void byte_push(Bytes *bytes, Byte value) {
    if (bytes->count == bytes->capacity) {
        bytes->capacity = bytes->capacity ? 2 * bytes->capacity : 32;
        bytes->data = resize(bytes->data, bytes->capacity);
    }
    bytes->data[bytes->count++] = value;
}
void bytes_append(Bytes *target, const Byte *values, size_t count) {
    for (size_t i = 0; i < count; ++i)
        byte_push(target, values[i]);
}
Bytes bytes_copy(const Bytes *bytes) {
    Bytes out = {0};
    bytes_append(&out, bytes->data, bytes->count);
    return out;
}
void bytes_free(Bytes *bytes) {
    free(bytes->data);
    *bytes = (Bytes){0};
}
int bits(uint32_t value) {
    int count = 0;
    while (value) {
        ++count;
        value >>= 1;
    }
    return count;
}
void bit_write(BitWriter *writer, uint32_t value, int width) {
    for (int shift = width - 1; shift >= 0; --shift) {
        if (writer->count % 8 == 0)
            byte_push(&writer->bytes, 0);
        writer->bytes.data[writer->bytes.count - 1] |=
            (Byte)(((value >> shift) & 1) << (7 - writer->count % 8));
        ++writer->count;
    }
}
uint32_t bit_read(BitReader *reader, int width) {
    if (reader->error)
        return 0;
    if (!reader->zero_extend && reader->position + (size_t)width > reader->bytes->count * 8) {
        reader->error = "end_of_data";
        return 0;
    }
    uint32_t value = 0;
    for (int i = 0; i < width; ++i) {
        value <<= 1;
        if (reader->position < reader->bytes->count * 8)
            value |= (reader->bytes->data[reader->position / 8] >> (7 - reader->position % 8)) & 1;
        ++reader->position;
    }
    return value;
}
