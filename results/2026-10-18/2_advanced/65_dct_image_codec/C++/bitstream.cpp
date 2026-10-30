#include "codec.hpp"
void BitWriter::write(int value, int width) {
    for (int shift = width - 1; shift >= 0; --shift) {
        buffer = 2 * buffer + ((value >> shift) & 1);
        ++pending;
        if (pending == 8) {
            data.push_back(buffer);
            if (buffer == 255) {
                data.push_back(0);
                ++stuffed;
            }
            buffer = pending = 0;
        }
    }
}
void BitWriter::pad() {
    if (pending) {
        int width = 8 - pending;
        padding += width;
        write((1 << width) - 1, width);
    }
}
void BitWriter::restart(int number) {
    pad();
    data.push_back(255);
    data.push_back(0xd0 + number % 8);
}
int BitReader::bit() {
    if (!remaining) {
        int value = data[position];
        if (value == 255) {
            if (data[position + 1] != 0)
                throw DecodeError{"marker"};
            position += 2;
        } else
            ++position;
        buffer = value;
        remaining = 8;
    }
    --remaining;
    return (buffer >> remaining) & 1;
}
int BitReader::read(int width) {
    int value = 0;
    for (int i = 0; i < width; ++i)
        value = 2 * value + bit();
    return value;
}
void BitReader::discard() { buffer = remaining = 0; }
int find_resync(const Bytes &data, int position) {
    for (int offset = position; offset + 1 < int(data.size()); ++offset)
        if (data[offset] == 255 &&
            ((data[offset + 1] >= 0xd0 && data[offset + 1] <= 0xd7) || data[offset + 1] == 0xd9))
            return offset;
    return int(data.size()) - 2;
}
