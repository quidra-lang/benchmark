#include "codec.h"
void write_bits(BitWriter *writer, int value, int width) {
    for (int shift = width - 1; shift >= 0; --shift) {
        writer->buffer = 2 * writer->buffer + ((value >> shift) & 1);
        ++writer->pending;
        if (writer->pending == 8) {
            byte(&writer->data, writer->buffer);
            if (writer->buffer == 255) {
                byte(&writer->data, 0);
                ++writer->stuffed;
            }
            writer->buffer = writer->pending = 0;
        }
    }
}
void pad(BitWriter *writer) {
    if (writer->pending) {
        int width = 8 - writer->pending;
        writer->padding += width;
        write_bits(writer, (1 << width) - 1, width);
    }
}
void restart(BitWriter *writer, int number) {
    pad(writer);
    byte(&writer->data, 255);
    byte(&writer->data, 0xd0 + number % 8);
}
int read_bit(BitReader *reader) {
    if (reader->error)
        return 0;
    if (!reader->remaining) {
        int value = reader->data->data[reader->position];
        if (value == 255) {
            if (reader->data->data[reader->position + 1] != 0) {
                reader->error = "marker";
                return 0;
            }
            reader->position += 2;
        } else
            ++reader->position;
        reader->buffer = value;
        reader->remaining = 8;
    }
    --reader->remaining;
    return (reader->buffer >> reader->remaining) & 1;
}
int read_bits(BitReader *reader, int width) {
    int value = 0;
    for (int i = 0; i < width; ++i) {
        value = 2 * value + read_bit(reader);
        if (reader->error)
            break;
    }
    return value;
}
void discard(BitReader *reader) { reader->buffer = reader->remaining = 0; }
int find_resync(const Bytes *data, int position) {
    for (int offset = position; offset + 1 < data->count; ++offset)
        if (data->data[offset] == 255 &&
            ((data->data[offset + 1] >= 0xd0 && data->data[offset + 1] <= 0xd7) ||
             data->data[offset + 1] == 0xd9))
            return offset;
    return data->count - 2;
}
