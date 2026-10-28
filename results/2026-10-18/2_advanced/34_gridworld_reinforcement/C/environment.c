#include "reinforcement.h"
Integer floor_div(Integer a, Integer b) {
    return a / b - (a % b < 0 ? 1 : 0);
}
Integer absolute(Integer value) {
    return value < 0 ? -value : value;
}
World read_world(void) {
    Lines lines = read_lines("input/world.txt");
    World w = {0};
    sscanf(lines.data[0], "ROWS %d", &w.rows);
    sscanf(lines.data[1], "COLS %d", &w.cols);
    int count = w.rows * w.cols;
    w.cells = allocate((size_t)count + 1, 1);
    w.states = allocate(count, sizeof *w.states);
    w.terminals = allocate(count, sizeof *w.terminals);
    w.index = allocate(count, sizeof *w.index);
    w.terminal_index = allocate(count, sizeof *w.terminal_index);
    w.wind = allocate(w.cols, sizeof *w.wind);
    w.rewards = allocate(count, sizeof *w.rewards);
    for (int r = 0; r < w.rows; ++r)
        memcpy(w.cells + r * w.cols, lines.data[r + 2], w.cols);
    for (int cell = 0; cell < count; ++cell) {
        w.index[cell] = -1;
        w.terminal_index[cell] = -1;
        char kind = w.cells[cell];
        if (kind == '#')
            continue;
        if (kind == 'G' || kind == 'P') {
            w.terminal_index[cell] = w.nt;
            w.terminals[w.nt++] = cell;
        } else {
            w.index[cell] = w.n;
            w.states[w.n++] = cell;
            if (kind == 'S')
                w.start = cell;
        }
    }
    for (int c = 0; c < w.cols; ++c)
        w.wind[c] = lines.data[w.rows + 2][5 + c] - '0';
    const char *cursor = lines.data[w.rows + 3] + 8;
    for (int i = 0; i < w.nt; ++i) {
        char *end;
        w.rewards[w.terminals[i]] = strtoll(cursor, &end, 10);
        cursor = end;
    }
    w.moves = allocate(w.n, sizeof *w.moves);
    for (int s = 0; s < w.n; ++s)
        for (int a = 0; a < 4; ++a)
            w.moves[s][a] = move_cell(&w, w.states[s], a);
    return w;
}
bool terminal(const World *w, int cell) {
    return w->terminal_index[cell] >= 0;
}
const char *ending(const World *w, int cell) {
    return terminal(w, cell) ? w->cells[cell] == 'G' ? "goal" : "pit" : "timeout";
}
int move_cell(const World *w, int cell, int action) {
    int offsets[4] = {-w->cols, 1, w->cols, -1};
    int next = cell + offsets[action];
    if (w->cells[next] == '#')
        next = cell;
    if (terminal(w, next))
        return next;
    for (int i = 0; i < w->wind[cell % w->cols]; ++i) {
        if (w->cells[next - w->cols] == '#')
            break;
        next -= w->cols;
        if (terminal(w, next))
            break;
    }
    return next;
}
Integer reward(const World *w, int cell, Integer step_reward) {
    return terminal(w, cell) ? w->rewards[cell] : step_reward;
}
Transitions transitions(const Model *model, int state, int action) {
    Integer p = model->world->cells[model->world->states[state]] == '~' ? model->ice_slip : model->floor_slip;
    Integer weights[3] = {model->q - 2 * p, p, p};
    int directions[3] = {action, (action + 1) % 4, (action + 3) % 4};
    Transitions out = {0};
    for (int i = 0; i < 3; ++i)
        if (weights[i] > 0)
            out.data[out.count++] = (Transition){model->world->moves[state][directions[i]], weights[i]};
    return out;
}
Integer draw(Random *random) {
    random->value = (48271 * random->value) % 2147483647;
    return random->value;
}
Outcome step(const Model *model, int state, int action, Random *random) {
    const World *w = model->world;
    Integer p = w->cells[w->states[state]] == '~' ? model->ice_slip : model->floor_slip,
            t = draw(random) % model->q;
    int direction = t < model->q - 2 * p ? action : t < model->q - p ? (action + 1) % 4 : (action + 3) % 4;
    int cell = w->moves[state][direction];
    return (Outcome){cell, reward(w, cell, model->step_reward)};
}
