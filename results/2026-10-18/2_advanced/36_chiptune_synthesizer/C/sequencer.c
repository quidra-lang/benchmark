#include "synthesizer.h"
int samples_per_tick(const Song *song, int tempo) {
    return song->rate * 5 / (tempo * 2);
}
NextRow next_row(const Song *song, int position, int row) {
    const Cell *cells = song->patterns[song->order[position]]->rows[row];
    int jump = -1, break_ = -1;
    bool stop = false;
    for (int k = 0; k < 4; ++k) {
        Effect e = cells[k].effect;
        if (!strcmp(e.name, "F") && !e.argument)
            stop = true;
        else if (!strcmp(e.name, "B"))
            jump = e.argument;
        else if (!strcmp(e.name, "D"))
            break_ = e.argument;
    }
    if (jump >= 0 || break_ >= 0)
        return (NextRow){jump >= 0 ? jump : position + 1, break_ >= 0 && break_ < 64 ? break_ : 0, stop};
    return row < 63 ? (NextRow){position, row + 1, stop} : (NextRow){position + 1, 0, stop};
}
void reachable(const Song *song, bool result[64][64]) {
    int position = 0, row = 0;
    while (position < song->order_count && !result[position][row]) {
        result[position][row] = true;
        NextRow next = next_row(song, position, row);
        if (next.stop)
            break;
        position = next.position;
        row = next.row;
    }
}
