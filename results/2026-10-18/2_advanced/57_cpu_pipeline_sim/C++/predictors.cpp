#include "simulator.hpp"
std::optional<I> BTB::lookup(I pc) const {
    const auto &entry = entries[(pc / 4) % entries.size()];
    return entry && entry->first == pc ? std::optional<I>(entry->second) : std::nullopt;
}
void BTB::insert(I pc, I target) {
    entries[(pc / 4) % entries.size()] = std::make_pair(pc, target);
}
void RAS::push(I value) {
    if (depth == 0)
        return;
    if (int(stack.size()) == depth)
        stack.erase(stack.begin());
    stack.push_back(value);
}
std::optional<I> RAS::pop() {
    if (stack.empty())
        return {};
    const I value = stack.back();
    stack.pop_back();
    return value;
}
static int updated(int counter, bool taken) {
    return taken ? std::min(3, counter + 1) : std::max(0, counter - 1);
}
DirectionPredictor::DirectionPredictor(Predictor value) : definition(std::move(value)) {
    const auto &p = definition.parameters;
    const std::string &scheme = definition.scheme;
    if (scheme == "ONEBIT" || scheme == "TWOBIT" || scheme == "GSHARE")
        table.assign(p[0], scheme == "ONEBIT" ? 0 : 1);
    if (scheme == "TOURNAMENT") {
        local.assign(p[0], 1);
        global.assign(p[1], 1);
        chooser.assign(p[3], 1);
    }
}
bool DirectionPredictor::prediction(I pc, I target) const {
    const std::string &s = definition.scheme;
    const I index = pc / 4;
    if (s == "STATIC_NT" || s == "PERFECT")
        return false;
    if (s == "BTFN")
        return target < pc;
    if (s == "ONEBIT")
        return table[index % table.size()] == 1;
    if (s == "TWOBIT")
        return table[index % table.size()] >= 2;
    if (s == "GSHARE")
        return table[(index ^ history) % table.size()] >= 2;
    return chooser[index % chooser.size()] >= 2 ? global[(index ^ history) % global.size()] >= 2
                                                : local[index % local.size()] >= 2;
}
void DirectionPredictor::update(I pc, bool taken) {
    const std::string &s = definition.scheme;
    const auto &p = definition.parameters;
    const I index = pc / 4;
    if (s == "STATIC_NT" || s == "BTFN" || s == "PERFECT")
        return;
    if (s == "TOURNAMENT") {
        const int l = int(index % local.size()), g = int((index ^ history) % global.size()),
                  ch = int(index % chooser.size());
        if ((local[l] >= 2) != (global[g] >= 2))
            chooser[ch] = updated(chooser[ch], (global[g] >= 2) == taken);
        local[l] = updated(local[l], taken);
        global[g] = updated(global[g], taken);
        history = (2 * history + int(taken)) % (1 << p[2]);
    } else {
        const int t = int((s == "GSHARE" ? (index ^ history) : index) % table.size());
        table[t] = s == "ONEBIT" ? int(taken) : updated(table[t], taken);
        if (s == "GSHARE")
            history = (2 * history + int(taken)) % (1 << p[1]);
    }
}
int DirectionPredictor::bits() const {
    const auto &p = definition.parameters;
    const std::string &s = definition.scheme;
    if (s == "ONEBIT")
        return p[0];
    if (s == "TWOBIT")
        return 2 * p[0];
    if (s == "GSHARE")
        return 2 * p[0] + p[1];
    if (s == "TOURNAMENT")
        return 2 * (p[0] + p[1] + p[3]) + p[2];
    return 0;
}
