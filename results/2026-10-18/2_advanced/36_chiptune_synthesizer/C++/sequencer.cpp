#include "synthesizer.hpp"
int samples_per_tick(const Song &song, int tempo) {
    return song.rate * 5 / (tempo * 2);
}
NextRow next_row(const Song &song, int position, int row) {
    const Row &cells = song.patterns.at(song.order[position])[row];
    int jump = -1, break_ = -1;
    bool stop = false;
    for (const Cell &cell : cells) {
        const Effect &e = cell.effect;
        if (e.name == "F" && e.argument == 0)
            stop = true;
        else if (e.name == "B")
            jump = e.argument;
        else if (e.name == "D")
            break_ = e.argument;
    }
    if (jump >= 0 || break_ >= 0)
        return {jump >= 0 ? jump : position + 1, break_ >= 0 && break_ < 64 ? break_ : 0, stop};
    return row < 63 ? NextRow{position, row + 1, stop} : NextRow{position + 1, 0, stop};
}
std::vector<std::array<bool, 64>> reachable(const Song &song) {
    std::vector<std::array<bool, 64>> result(song.order.size());
    int position = 0, row = 0;
    while (position < int(song.order.size()) && !result[position][row]) {
        result[position][row] = true;
        const NextRow next = next_row(song, position, row);
        if (next.stop)
            break;
        position = next.position;
        row = next.row;
    }
    return result;
}
