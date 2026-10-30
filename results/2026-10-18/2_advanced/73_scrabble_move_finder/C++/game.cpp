#include "scrabble.hpp"
void shuffle(std::string &bag, Minstd &random) {
    for (int i = int(bag.size()) - 1; i >= 1; --i) {
        int j = int(random.next() % (i + 1));
        std::swap(bag[i], bag[j]);
    }
}
std::string make_bag(const Counts &counts, Minstd &random) {
    std::string out;
    for (int tile = 0; tile < 27; ++tile)
        out.append(counts[tile], tile_order[tile]);
    shuffle(out, random);
    return out;
}
std::string draw(std::string &bag, int count) {
    std::string out;
    while (count-- > 0 && !bag.empty()) {
        out += bag.back();
        bag.pop_back();
    }
    return out;
}
std::string exchange(std::string &bag, std::string returned, Minstd &random) {
    std::string drawn = draw(bag, int(returned.size()));
    std::sort(returned.begin(), returned.end());
    bag += returned;
    shuffle(bag, random);
    return drawn;
}
int points(const std::string &collection, const Counts &values) {
    int out = 0;
    for (char tile : collection)
        out += values[tile_index(tile)];
    return out;
}
