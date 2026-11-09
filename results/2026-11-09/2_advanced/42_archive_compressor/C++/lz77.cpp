#include "archive.hpp"
bool Token::match() const {
    return length > 0;
}
std::vector<Token> tokenize(const Bytes &data, int offset_bits, int length_bits) {
    const int window = 1 << offset_bits, lookahead = (1 << length_bits) + 2;
    std::vector<Token> out;
    int position = 0;
    while (position < int(data.size())) {
        int best = 0, distance = 0;
        const int maximum = std::min(lookahead, int(data.size()) - position);
        for (int d = 1; d <= std::min(window, position); ++d) {
            int length = 0;
            while (length < maximum && data[position + length] == data[position + length - d])
                ++length;
            if (length > best) {
                best = length;
                distance = d;
            }
        }
        if (best >= 3) {
            out.push_back({0, distance, best});
            position += best;
        } else
            out.push_back({data[position++], 0, 0});
    }
    return out;
}
void output_match(Bytes &output, std::uint32_t size, int distance, int length) {
    if (std::size_t(distance) > output.size())
        throw DecodeError{"bad_offset"};
    if (output.size() + std::size_t(length) > size)
        throw DecodeError{"overrun"};
    for (int i = 0; i < length; ++i)
        output.push_back(output[output.size() - distance]);
}
