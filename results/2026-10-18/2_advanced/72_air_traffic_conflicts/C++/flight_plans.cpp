#include "airspace.hpp"
static Names split(const std::string &text, char separator) {
    Names out;
    std::istringstream input(text);
    std::string word;
    while (std::getline(input, word, separator))
        out.push_back(word);
    return out;
}
Input read_inputs() {
    Input out;
    std::ifstream aircraft("input/aircraft.txt");
    AircraftType type;
    while (aircraft >> type.name >> type.climb >> type.descent >> type.minimum)
        out.types.push_back(type);
    std::map<std::string, int> types;
    for (int i = 0; i < int(out.types.size()); ++i)
        types[out.types[i].name] = i;
    std::ifstream sectors("input/sectors.txt");
    Sector sector;
    while (sectors >> sector.name >> sector.x1 >> sector.y1 >> sector.x2 >> sector.y2 >>
           sector.lower >> sector.upper >> sector.capacity)
        out.sectors.push_back(sector);
    std::ifstream flights("input/flights.csv");
    std::string text;
    std::getline(flights, text);
    while (std::getline(flights, text)) {
        Names row = split(text, ',');
        Plan plan;
        plan.callsign = row[0];
        plan.type = types.at(row[1]);
        plan.departure = std::stoll(row[2]);
        plan.level = std::stoll(row[3]);
        plan.speed_initial = plan.speed = std::stoi(row[4]);
        for (const std::string &point : split(row[5], ' ')) {
            Names fields = split(point, ':');
            plan.waypoints.push_back({std::stoi(fields[0]), std::stoi(fields[1]),
                                      fields.size() == 3
                                          ? std::optional<Integer>(std::stoll(fields[2]))
                                          : std::nullopt});
        }
        out.plans.push_back(plan);
    }
    std::sort(out.plans.begin(), out.plans.end(),
              [](const Plan &a, const Plan &b) { return a.callsign < b.callsign; });
    std::ifstream settings("input/params.txt");
    std::vector<std::vector<Integer>> values;
    while (std::getline(settings, text)) {
        std::istringstream row(text);
        std::string key;
        row >> key;
        std::vector<Integer> v;
        Integer value;
        while (row >> value)
            v.push_back(value);
        values.push_back(v);
    }
    Params &p = out.params;
    p.horizontal = values[0][0];
    p.vertical = values[0][1];
    p.lookahead = values[1][0];
    p.max_delay = values[2][0];
    p.level_min = values[3][0];
    p.level_max = values[3][1];
    p.sample_start = values[4][0];
    p.sample_end = values[4][1];
    for (int i = 0; i < 6; ++i)
        p.radar[i] = values[5][i];
    p.snapshots = values[6];
    p.leader = values[7][0];
    p.alert = values[8][0];
    return out;
}
std::vector<Integer> flight_levels(const Plan &plan) {
    std::vector<Integer> out{plan.level + plan.offset};
    for (const Waypoint &waypoint : plan.waypoints)
        if (waypoint.level)
            out.push_back(*waypoint.level + plan.offset);
    return out;
}
