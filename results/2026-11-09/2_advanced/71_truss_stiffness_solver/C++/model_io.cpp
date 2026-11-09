#include "truss.hpp"
static Names split(const std::string &text, char separator) {
    Names out;
    std::istringstream row(text);
    std::string field;
    while (std::getline(row, field, separator))
        out.push_back(field);
    return out;
}
static std::vector<Names> csv(const std::string &name) {
    std::ifstream input("input/" + name + ".csv");
    std::vector<Names> out;
    std::string text;
    std::getline(input, text);
    while (std::getline(input, text))
        out.push_back(split(text, ','));
    return out;
}
Model read_model() {
    Model out;
    std::map<int, int> nodes, members;
    std::map<std::string, int> sections, materials, cases;
    for (const Names &row : csv("nodes")) {
        int id = std::stoi(row[0]);
        nodes[id] = int(out.nodes.size());
        out.nodes.push_back({id, std::stoi(row[1]), std::stoi(row[2])});
    }
    for (const Names &row : csv("sections")) {
        sections[row[0]] = int(out.sections.size());
        out.sections.push_back({row[0], std::stod(row[1]), std::stod(row[2])});
    }
    for (const Names &row : csv("materials")) {
        materials[row[0]] = int(out.materials.size());
        out.materials.push_back(
            {row[0], std::stod(row[1]), std::stod(row[2]), std::stod(row[3]), std::stod(row[4])});
    }
    for (const Names &row : csv("members")) {
        int id = std::stoi(row[0]);
        members[id] = int(out.members.size());
        out.members.push_back({id, nodes.at(std::stoi(row[1])), nodes.at(std::stoi(row[2])),
                               sections.at(row[3]), materials.at(row[4]), row[5]});
    }
    for (const Names &row : csv("supports"))
        out.supports.push_back({nodes.at(std::stoi(row[0])),
                                {std::stoi(row[1]) != 0, std::stoi(row[2]) != 0},
                                {std::stod(row[3]), std::stod(row[4])}});
    std::ifstream loads("input/loads.txt");
    std::string text;
    while (std::getline(loads, text)) {
        Names row = split(text, ' ');
        if (row[0] == "LOADCASE") {
            cases[row[1]] = int(out.cases.size());
            out.cases.push_back({row[1], {}});
        } else if (row[0] == "END")
            continue;
        else if (row[0] == "COMBINATION") {
            Combination combination{row[1], {}};
            for (int i = 2; i < int(row.size()); i += 2)
                combination.terms.push_back({cases.at(row[i]), std::stod(row[i + 1])});
            out.combinations.push_back(combination);
        } else if (row[0] == "FORCE")
            out.cases.back().lines.push_back({LoadKind::Force, nodes.at(std::stoi(row[1])),
                                              std::stod(row[2]), std::stod(row[3])});
        else if (row[0] == "TEMPERATURE")
            out.cases.back().lines.push_back(
                {LoadKind::Temperature, members.at(std::stoi(row[1])), std::stod(row[2]), 0});
        else
            out.cases.back().lines.push_back(
                {row[0] == "SELFWEIGHT" ? LoadKind::Selfweight : LoadKind::Settlement});
    }
    Settings &p = out.settings;
    std::ifstream settings("input/params.txt");
    while (std::getline(settings, text)) {
        Names row = split(text, ' ');
        if (row[0] == "deck")
            for (int i = 1; i < int(row.size()); ++i)
                p.deck.push_back(nodes.at(std::stoi(row[i])));
        else if (row[0] == "influence")
            p.influence.push_back(members.at(std::stoi(row[1])));
        else if (row[0] == "vehicle") {
            p.vehicle_step = std::stoi(row[1]);
            for (int i = 2; i < int(row.size()); i += 2)
                p.axles.push_back({std::stoi(row[i]), std::stod(row[i + 1])});
        } else if (row[0] == "rating") {
            p.rating = row[1];
            p.dead_factor = std::stod(row[2]);
            p.vehicle_factor = std::stod(row[3]);
        } else if (row[0] == "slenderness") {
            p.compression_limit = std::stod(row[1]);
            p.tension_limit = std::stod(row[2]);
        } else if (row[0] == "deflection") {
            p.deflection = row[1];
            p.deflection_ratio = std::stoi(row[2]);
        } else if (row[0] == "vibration") {
            p.vibration = row[1];
            p.modes = std::stoi(row[2]);
            p.iterations = std::stoi(row[3]);
        } else if (row[0] == "removal")
            p.removal = row[1];
        else if (row[0] == "drawing")
            p.drawings.push_back({row[1], std::stoi(row[2]), std::stoi(row[3]), std::stoi(row[4])});
        else {
            p.map_horizontal = std::stoi(row[1]);
            p.map_vertical = std::stoi(row[2]);
        }
    }
    return out;
}
