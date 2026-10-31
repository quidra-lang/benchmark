#include "mining.hpp"
Net::Net(Names place_names, Names transition_names, std::set<NamePair> arc_names,
         const std::string &initial_name, const std::string &final_name)
    : places(std::move(place_names)), transitions(std::move(transition_names)),
      arcs(std::move(arc_names)) {
    std::sort(transitions.begin(), transitions.end());
    initial = int(std::find(places.begin(), places.end(), initial_name) - places.begin());
    final = int(std::find(places.begin(), places.end(), final_name) - places.begin());
    inputs.resize(transitions.size());
    outputs.resize(transitions.size());
    routes.resize(places.size());
    for (int t = 0; t < int(transitions.size()); ++t)
        for (int p = 0; p < int(places.size()); ++p) {
            if (arcs.count({places[p], transitions[t]})) {
                inputs[t].push_back(p);
                routes[p].push_back(t);
            }
            if (arcs.count({transitions[t], places[p]}))
                outputs[t].push_back(p);
        }
}
bool Net::enabled(const Marking &marking, int transition) const {
    for (int place : inputs[transition])
        if (marking[place] == 0)
            return false;
    return true;
}
Marking Net::fire(Marking marking, int transition) const {
    for (int place : inputs[transition])
        --marking[place];
    for (int place : outputs[transition])
        ++marking[place];
    return marking;
}
Marking Net::initial_marking() const {
    Marking out(places.size());
    out[initial] = 1;
    return out;
}
Marking Net::final_marking() const {
    Marking out(places.size());
    out[final] = 1;
    return out;
}
std::vector<int> Net::enabled_transitions(const Marking &marking) const {
    std::vector<int> out;
    for (int t = 0; t < int(transitions.size()); ++t)
        if (enabled(marking, t))
            out.push_back(t);
    return out;
}
int Net::transition_index(const std::string &name) const {
    auto entry = std::lower_bound(transitions.begin(), transitions.end(), name);
    return entry == transitions.end() || *entry != name ? -1 : int(entry - transitions.begin());
}
Net read_model() {
    std::ifstream input("input/model.txt");
    std::string text, initial, final;
    Names places, transitions;
    std::set<NamePair> arcs;
    while (std::getline(input, text)) {
        std::istringstream row(text);
        std::string key, first, second;
        row >> key >> first;
        if (key == "PLACE")
            places.push_back(first);
        else if (key == "TRANSITION")
            transitions.push_back(first);
        else if (key == "ARC") {
            row >> second;
            arcs.insert({first, second});
        } else if (key == "INITIAL")
            initial = first;
        else
            final = first;
    }
    return Net(places, transitions, arcs, initial, final);
}
Replay::Replay(int places)
    : place_missing(places), place_remaining(places), deviating(places), waiting(places),
      routes(places) {}
Fraction Replay::fitness() const {
    return Fraction(1, 2) * (Fraction(1) - Fraction(missing, consumed)) +
           Fraction(1, 2) * (Fraction(1) - Fraction(remaining, produced));
}
