#include <iostream>
#include <string>
#include <vector>
#include <array>

int main() {
    std::array<std::string, 9> maze = {"#############", "#S..#.......#", "#.#.#.###.#.#", "#.#...#...#.#",
        "#.###.#.###.#", "#...#...#...#", "###.#####.#.#", "#.......#..G#", "#############"};
    std::array<int, 117> parent, distance{};
    parent.fill(-1);
    int start = -1, goal = -1;
    for (int i = 0; i < 117; i++) {
        if (maze[i / 13][i % 13] == 'S')
            start = i;
        if (maze[i / 13][i % 13] == 'G')
            goal = i;
    }
    std::vector<int> queue = {start};
    parent[start] = start;
    int dr[] = {-1, 1, 0, 0}, dc[] = {0, 0, -1, 1};
    for (std::size_t head = 0; head < queue.size(); head++) {
        int v = queue[head], r = v / 13, c = v % 13;
        for (int d = 0; d < 4; d++) {
            int rr = r + dr[d], cc = c + dc[d];
            if (rr < 0 || rr >= 9 || cc < 0 || cc >= 13 || maze[rr][cc] == '#')
                continue;
            int w = rr * 13 + cc;
            if (parent[w] < 0) {
                parent[w] = v;
                distance[w] = distance[v] + 1;
                queue.push_back(w);
            }
        }
    }
    for (int v = goal; v != start; v = parent[v])
        if (maze[v / 13][v % 13] == '.')
            maze[v / 13][v % 13] = '*';
    std::cout << "steps: " << distance[goal] << '\n';
    for (const std::string &row : maze)
        std::cout << row << '\n';
}
