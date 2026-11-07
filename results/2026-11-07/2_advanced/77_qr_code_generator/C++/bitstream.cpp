#include "qr.hpp"
const std::string alphanumeric = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
std::string binary(int value, int width) {
    std::string bits(width, '0');
    for (int i = 0; i < width; ++i)
        bits[width - 1 - i] = char('0' + ((value >> i) & 1));
    return bits;
}
void BitWriter::write(int value, int width) { bits += binary(value, width); }
int BitReader::remaining() const { return int(bits.size()) - position; }
int BitReader::read(int width) {
    int value = 0;
    for (int i = 0; i < width; ++i)
        value = 2 * value + bits[position++] - '0';
    return value;
}
std::string from_codewords(const Words &words) {
    BitWriter out;
    for (int value : words)
        out.write(value, 8);
    return out.bits;
}
Words to_codewords(const std::string &bits) {
    Words words;
    BitReader reader{bits};
    while (reader.remaining() >= 8)
        words.push_back(reader.read(8));
    return words;
}
std::string hexadecimal(const Words &words) {
    std::ostringstream out;
    out << std::hex << std::setfill('0');
    for (int value : words)
        out << std::setw(2) << value;
    return out.str();
}
