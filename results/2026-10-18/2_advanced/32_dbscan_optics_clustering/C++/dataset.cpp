#include "clustering.hpp"
Input read_input() {
    Input input;
    std::ifstream points("input/points.csv");
    std::string line;
    std::getline(points, line);
    while (std::getline(points, line)) {
        std::replace(line.begin(), line.end(), ',', ' ');
        std::istringstream fields(line);
        Point point;
        fields >> point.id >> point.x >> point.y;
        input.points.push_back(point);
    }
    std::sort(input.points.begin(), input.points.end(),
              [](const Point &a, const Point &b) { return a.id < b.id; });
    std::ifstream params("input/params.txt");
    std::vector<std::vector<std::string>> values;
    while (std::getline(params, line)) {
        std::istringstream fields(line);
        std::string key, word;
        fields >> key;
        std::vector<std::string> row;
        while (fields >> word)
            row.push_back(word);
        values.push_back(row);
    }
    Params &p = input.params;
    for (const std::string &value : values[0])
        p.eps.push_back(std::stoi(value));
    p.min_points = std::stoi(values[1][0]);
    p.max_eps = std::stoi(values[2][0]);
    for (const std::string &value : values[3])
        p.extract.push_back(std::stoi(value));
    const std::size_t slash = values[4][0].find('/');
    p.xi_u = std::stoi(values[4][0].substr(0, slash));
    p.xi_v = std::stoi(values[4][0].substr(slash + 1));
    p.xi_size = std::stoi(values[5][0]);
    p.width = std::stoi(values[6][0]);
    p.height = std::stoi(values[6][1]);
    p.kwidth = std::stoi(values[7][0]);
    p.kheight = std::stoi(values[7][1]);
    p.rwidth = std::stoi(values[8][0]);
    return input;
}
Integer distance(const Point &a, const Point &b) {
    const Integer x = Integer(a.x) - b.x, y = Integer(a.y) - b.y;
    return x * x + y * y;
}
