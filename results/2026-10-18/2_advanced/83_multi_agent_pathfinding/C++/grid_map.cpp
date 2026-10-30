#include "mapf.hpp"
#include <algorithm>
#include <sstream>
bool Grid::free(int cell) const {
    return cell >= 0 && cell < width * height && rows[cell / width][cell % width] == '.';
}
std::vector<int> Grid::destinations(int cell) const {
    std::vector<int> result = {cell};
    static const int dx[] = {0, 1, 0, -1}, dy[] = {-1, 0, 1, 0};
    int x = cell % width, y = cell / width;
    for (int i = 0; i < 4; ++i) {
        int nx = x + dx[i], ny = y + dy[i];
        if (nx >= 0 && nx < width && ny >= 0 && ny < height && free(ny * width + nx))
            result.push_back(ny * width + nx);
    }
    return result;
}
std::vector<int> Grid::distances(int goal) const {
    std::vector<int> result(width * height, -1), queue = {goal};
    result[goal] = 0;
    for (std::size_t i = 0; i < queue.size(); ++i) {
        int cell = queue[i];
        for (int next : destinations(cell))
            if (result[next] < 0) {
                result[next] = result[cell] + 1;
                queue.push_back(next);
            }
    }
    return result;
}
Grid readGrid() {
    Grid grid;
    std::vector<std::string> lines = readLines("input/map.txt"), dimensions = words(lines[0]);
    grid.width = std::stoi(dimensions[0]);
    grid.height = std::stoi(dimensions[1]);
    grid.rows.assign(lines.begin() + 1, lines.end());
    lines = readLines("input/agents.csv");
    for (std::size_t i = 1; i < lines.size(); ++i) {
        std::string text = lines[i];
        std::replace(text.begin(), text.end(), ',', ' ');
        std::vector<std::string> a = words(text);
        grid.agents.push_back({std::stoi(a[2]) * grid.width + std::stoi(a[1]),
                               std::stoi(a[4]) * grid.width + std::stoi(a[3])});
    }
    for (const Agent &agent : grid.agents)
        grid.distance.push_back(grid.distances(agent.goal));
    return grid;
}
