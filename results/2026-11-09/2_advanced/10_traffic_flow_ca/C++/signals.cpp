#include "traffic.hpp"
#include <sstream>
#include <utility>

Junction::Junction(std::string node, int offset, const Lines& tokens) : node(std::move(node)), offset(offset) {
    for (const std::string& token : tokens) {
        auto colon = token.find(':'); Phase phase{std::stoi(token.substr(0,colon)),token.substr(colon + 1),{}};
        if (phase.token != "-") { std::istringstream list(phase.token); std::string id; while (std::getline(list,id,',')) phase.greens.insert(id); }
        cycle += phase.duration; phases.push_back(phase);
    }
}
bool Junction::green(const std::string& segment, int step) const {
    if (phases.empty()) return true; int time = (step - 1 + offset) % cycle;
    for (const Phase& phase : phases) { if (time < phase.duration) return phase.greens.count(segment) != 0; time -= phase.duration; } return false;
}
Lines Junction::planLines() const {
    if (phases.empty()) return {"JUNCTION " + node + " unsignalized"};
    Lines lines{"JUNCTION " + node + " signal cycle " + std::to_string(cycle) + " offset " + std::to_string(offset)}; int start = 0;
    for (int j = 0; j < static_cast<int>(phases.size()); ++j) { int end = start + phases[j].duration - 1; lines.push_back("  PHASE " + std::to_string(j + 1) + " " + std::to_string(start) + "-" + std::to_string(end) + " " + phases[j].token); start = end + 1; } return lines;
}
