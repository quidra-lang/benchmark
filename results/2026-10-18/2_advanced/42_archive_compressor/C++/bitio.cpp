#include "archive.hpp"
int bits(std::uint32_t value) {
    int count = 0;
    while (value) {
        ++count;
        value >>= 1;
    }
    return count;
}
void BitWriter::write(std::uint32_t value, int width) {
    for (int shift = width - 1; shift >= 0; --shift) {
        if (count % 8 == 0)
            bytes.push_back(0);
        bytes.back() |= Byte(((value >> shift) & 1) << (7 - count % 8));
        ++count;
    }
}
std::uint32_t BitReader::read(int width) {
    if (!zero_extend && position + std::size_t(width) > bytes.size() * 8)
        throw DecodeError{"end_of_data"};
    std::uint32_t value = 0;
    for (int i = 0; i < width; ++i) {
        value <<= 1;
        if (position < bytes.size() * 8)
            value |= (bytes[position / 8] >> (7 - position % 8)) & 1;
        ++position;
    }
    return value;
}
