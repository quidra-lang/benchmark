#include "reinforcement.hpp"
Integer floor_div(Integer a, Integer b) {
    return a / b - (a % b < 0 ? 1 : 0);
}
Integer absolute(Integer value) {
    return value < 0 ? -value : value;
}
World read_world() {
    const Lines lines = read_lines("input/world.txt");
    World w;
    std::string word;
    std::istringstream first(lines[0]), second(lines[1]);
    first >> word >> w.rows;
    second >> word >> w.cols;
    for (int r = 0; r < w.rows; ++r)
        w.cells += lines[r + 2];
    w.index.assign(w.cells.size(), -1);
    w.terminal_index.assign(w.cells.size(), -1);
    w.rewards.assign(w.cells.size(), 0);
    for (int cell = 0; cell < int(w.cells.size()); ++cell) {
        const char kind = w.cells[cell];
        if (kind == '#')
            continue;
        if (kind == 'G' || kind == 'P') {
            w.terminal_index[cell] = w.terminals.size();
            w.terminals.push_back(cell);
        } else {
            w.index[cell] = w.states.size();
            w.states.push_back(cell);
            if (kind == 'S')
                w.start = cell;
        }
    }
    const std::string wind = lines[w.rows + 2].substr(5);
    for (char c : wind)
        w.wind.push_back(c - '0');
    std::istringstream rewards(lines[w.rows + 3]);
    rewards >> word;
    for (int cell : w.terminals)
        rewards >> w.rewards[cell];
    w.moves.resize(w.states.size());
    for (std::size_t state = 0; state < w.states.size(); ++state)
        for (int d = 0; d < 4; ++d)
            w.moves[state][d] = move_cell(w, w.states[state], d);
    return w;
}
bool terminal(const World &w, int cell) {
    return w.terminal_index[cell] >= 0;
}
std::string ending(const World &w, int cell) {
    return terminal(w, cell) ? w.cells[cell] == 'G' ? "goal" : "pit" : "timeout";
}
int move_cell(const World &w, int cell, int direction) {
    const std::array<int, 4> offsets = {-w.cols, 1, w.cols, -1};
    int next = cell + offsets[direction];
    if (w.cells[next] == '#')
        next = cell;
    if (terminal(w, next))
        return next;
    for (int i = 0; i < w.wind[cell % w.cols]; ++i) {
        if (w.cells[next - w.cols] == '#')
            break;
        next -= w.cols;
        if (terminal(w, next))
            break;
    }
    return next;
}
Integer reward(const World &w, int cell, Integer step_reward) {
    return terminal(w, cell) ? w.rewards[cell] : step_reward;
}
std::vector<Transition> Model::transitions(int state, int action) const {
    const Integer p = world->cells[world->states[state]] == '~' ? ice_slip : floor_slip;
    const std::array<Integer, 3> weights = {q - 2 * p, p, p};
    const std::array<int, 3> directions = {action, (action + 1) % 4, (action + 3) % 4};
    std::vector<Transition> result;
    for (int i = 0; i < 3; ++i)
        if (weights[i] > 0)
            result.push_back({world->moves[state][directions[i]], weights[i]});
    return result;
}
Integer Random::draw() {
    value = (48271 * value) % 2147483647;
    return value;
}
std::pair<int, Integer> step(const Model &model, int state, int action, Random &random) {
    const Integer p = model.world->cells[model.world->states[state]] == '~' ? model.ice_slip
                                                                            : model.floor_slip,
                  t = random.draw() % model.q;
    const int direction = t < model.q - 2 * p ? action
                          : t < model.q - p   ? (action + 1) % 4
                                              : (action + 3) % 4;
    const int cell = model.world->moves[state][direction];
    return {cell, reward(*model.world, cell, model.step_reward)};
}
