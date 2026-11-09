#include "spatial.hpp"
static Lines split(const std::string &text, char delimiter) {
    std::istringstream stream(text);
    Lines out;
    std::string field;
    while (std::getline(stream, field, delimiter))
        out.push_back(field);
    return out;
}
Input read_input() {
    Input out;
    std::ifstream points("input/points.csv"), rectangles("input/rects.csv"), params("input/params.txt"),
        commands("input/queries.txt");
    std::string line;
    std::getline(points, line);
    while (std::getline(points, line)) {
        const Lines f = split(line, ',');
        out.points.push_back({std::stoi(f[0]), std::stoll(f[1]), std::stoll(f[2])});
    }
    std::getline(rectangles, line);
    while (std::getline(rectangles, line)) {
        const Lines f = split(line, ',');
        out.rectangles.push_back(
            {std::stoi(f[0]), {std::stoll(f[1]), std::stoll(f[2]), std::stoll(f[3]), std::stoll(f[4])}});
    }
    std::string key;
    Params &p = out.params;
    params >> key >> p.world >> key >> p.bucket >> key >> p.maximum >> p.minimum >> key >> p.grid;
    while (std::getline(commands, line)) {
        std::istringstream fields(line);
        Command command;
        fields >> command.name;
        Integer value;
        while (fields >> value)
            command.values.push_back(value);
        out.commands.push_back(std::move(command));
    }
    return out;
}
