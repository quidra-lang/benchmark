#include "mahjong.hpp"

bool parseTiles(const std::string &text, bool allowEmpty, Tiles &out) {
    out = Tiles{};
    if (text == "-" && allowEmpty)
        return true;
    if (text.empty() || text == "-")
        return false;
    for (std::size_t i = 0; i < text.size();) {
        std::size_t start = i;
        while (i < text.size() && text[i] >= '0' && text[i] <= '9')
            ++i;
        if (i == start || i == text.size())
            return false;
        std::size_t suit = std::string("mpsz").find(text[i]);
        if (suit == std::string::npos)
            return false;
        for (std::size_t j = start; j < i; ++j) {
            int rank = text[j] - '0';
            bool red = rank == 0;
            if (suit == 3) {
                if (rank < 1 || rank > 7)
                    return false;
            } else if (red)
                rank = 5;
            ++out.counts[9 * suit + rank - 1];
            ++out.size;
            if (red)
                ++out.reds[suit];
        }
        ++i;
    }
    return true;
}
Tiles combineTiles(const Tiles &a, const Tiles &b) {
    Tiles out = a;
    for (int i = 0; i < 34; ++i)
        out.counts[i] += b.counts[i];
    for (int i = 0; i < 3; ++i)
        out.reds[i] += b.reds[i];
    out.size += b.size;
    return out;
}
Tiles addKind(Tiles tiles, int kind) {
    ++tiles.counts[kind];
    ++tiles.size;
    return tiles;
}
std::string tileName(int kind) { return std::to_string(kind % 9 + 1) + "mpsz"[kind / 9]; }
std::string blockNotation(int kind, int size, bool sequence) {
    std::string result;
    for (int i = 0; i < size; ++i)
        result += char('0' + kind % 9 + 1 + (sequence ? i : 0));
    result += "mpsz"[kind / 9];
    return result;
}
std::string Block::notation() const { return blockNotation(kind, kan ? 4 : 3, sequence); }
bool honor(int kind) { return kind >= 27; }
bool terminal(int kind) { return kind < 27 && (kind % 9 == 0 || kind % 9 == 8); }
bool yaochuu(int kind) { return honor(kind) || terminal(kind); }
int nextDora(int kind) {
    if (kind < 27)
        return kind / 9 * 9 + (kind % 9 + 1) % 9;
    if (kind < 31)
        return 27 + (kind - 27 + 1) % 4;
    return 31 + (kind - 31 + 1) % 3;
}
