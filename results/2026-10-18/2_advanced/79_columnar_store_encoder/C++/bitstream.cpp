#include "columnar.hpp"
int Reader::byte() { return data[position++]; }
Bytes Reader::read(std::size_t count) {
    Bytes result(data.begin() + position, data.begin() + position + count);
    position += count;
    return result;
}
std::string Reader::string(std::size_t count) {
    std::string result(data.begin() + position, data.begin() + position + count);
    position += count;
    return result;
}
Number Reader::uleb() {
    Number value = 0;
    int shift = 0;
    for (;;) {
        int b = byte();
        value |= Number(b & 127) << shift;
        if (b < 128)
            return value;
        shift += 7;
    }
}
Number Reader::zigzag() {
    Number value = uleb();
    return value % 2 == 0 ? value / 2 : -(value + 1) / 2;
}
Number Reader::integer(bool signed_value) {
    Number value = 0;
    for (int i = 0; i < 4; ++i)
        value |= Number(byte()) << (8 * i);
    return signed_value && value >= (Number(1) << 31) ? value - (Number(1) << 32) : value;
}
void write_uleb(Bytes &out, Number value) {
    while (value >= 128) {
        out.push_back(std::uint8_t(value % 128 + 128));
        value /= 128;
    }
    out.push_back(std::uint8_t(value));
}
void write_zigzag(Bytes &out, Number value) {
    write_uleb(out, value >= 0 ? 2 * value : -2 * value - 1);
}
void write_integer(Bytes &out, Number value) {
    if (value < 0)
        value += Number(1) << 32;
    for (int i = 0; i < 4; ++i)
        out.push_back(std::uint8_t((value >> (8 * i)) & 255));
}
int bits(Number value) {
    int width = 0;
    while (value) {
        value >>= 1;
        ++width;
    }
    return width;
}
Bytes pack(const Numbers &values, int width) {
    Bytes out;
    std::uint64_t buffer = 0;
    int occupied = 0;
    for (Number value : values) {
        buffer |= std::uint64_t(value) << occupied;
        occupied += width;
        while (occupied >= 8) {
            out.push_back(std::uint8_t(buffer & 255));
            buffer >>= 8;
            occupied -= 8;
        }
    }
    return out;
}
Numbers unpack(Reader &reader, int width, int count) {
    Numbers out;
    std::uint64_t buffer = 0, mask = (std::uint64_t(1) << width) - 1;
    int occupied = 0;
    for (int i = 0; i < count; ++i) {
        while (occupied < width) {
            buffer |= std::uint64_t(reader.byte()) << occupied;
            occupied += 8;
        }
        out.push_back(Number(buffer & mask));
        buffer >>= width;
        occupied -= width;
    }
    return out;
}
Number adler32(const Bytes &data) {
    Number first = 1, second = 0;
    for (int byte : data) {
        first = (first + byte) % 65521;
        second = (second + first) % 65521;
    }
    return second * 65536 + first;
}
Bytes hybrid_encode(const Numbers &values, int width) {
    std::vector<int> runs(values.size());
    for (int i = int(values.size()) - 1; i >= 0; --i)
        runs[i] = 1 + (i + 1 < int(values.size()) && values[i] == values[i + 1] ? runs[i + 1] : 0);
    Bytes out;
    for (int i = 0; i < int(values.size());) {
        if (runs[i] >= 8) {
            write_uleb(out, 2 * runs[i]);
            for (int j = 0; j < (width + 7) / 8; ++j)
                out.push_back(std::uint8_t((values[i] >> (8 * j)) & 255));
            i += runs[i];
        } else {
            int end = i, groups = 0;
            do {
                end += 8;
                ++groups;
            } while (end < int(values.size()) && groups < 63 && runs[end] < 8);
            write_uleb(out, 2 * groups + 1);
            Numbers block(end - i);
            for (int j = i; j < std::min(end, int(values.size())); ++j)
                block[j - i] = values[j];
            append(out, pack(block, width));
            i = end;
        }
    }
    return out;
}
Numbers hybrid_decode(Reader &reader, int width, int count) {
    Numbers out;
    while (int(out.size()) < count) {
        Number header = reader.uleb();
        if (header % 2 == 0) {
            Number value = 0;
            for (int i = 0; i < (width + 7) / 8; ++i)
                value |= Number(reader.byte()) << (8 * i);
            out.insert(out.end(), std::size_t(header / 2), value);
        } else {
            Numbers block = unpack(reader, width, int((header - 1) / 2 * 8));
            out.insert(out.end(), block.begin(), block.end());
        }
    }
    out.resize(count);
    return out;
}
std::string hex(const Bytes &data) {
    std::ostringstream out;
    out << std::hex << std::setfill('0');
    for (int byte : data)
        out << std::setw(2) << byte;
    return out.str();
}
std::string checksum_text(Number value) {
    std::ostringstream out;
    out << std::hex << std::setw(8) << std::setfill('0') << value;
    return out.str();
}
