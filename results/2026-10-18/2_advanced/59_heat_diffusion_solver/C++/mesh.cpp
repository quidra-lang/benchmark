#include "heat.hpp"
Mesh read_mesh() {
    Mesh out;
    std::ifstream input("input/plate.txt");
    input >> out.width >> out.height >> out.dx >> out.thickness;
    out.count = out.width * out.height;
    std::string row;
    while (input >> row)
        out.codes += row;
    for (int r = 0; r < out.height; ++r)
        for (int c = 0; c < out.width; ++c) {
            int p = out.cell(r, c);
            out.neighbors.push_back({c > 0 ? p - 1 : -1, c + 1 < out.width ? p + 1 : -1,
                                     r > 0 ? p - out.width : -1,
                                     r + 1 < out.height ? p + out.width : -1});
        }
    return out;
}
std::string Mesh::coordinates(int point) const {
    return std::to_string(point / width) + " " + std::to_string(point % width);
}
std::vector<std::pair<int, int>> Mesh::segment_faces(const std::string &edge, int start,
                                                     int end) const {
    std::vector<std::pair<int, int>> out;
    for (int i = start; i <= end; ++i) {
        if (edge == "left")
            out.emplace_back(cell(i, 0), 0);
        else if (edge == "right")
            out.emplace_back(cell(i, width - 1), 1);
        else if (edge == "top")
            out.emplace_back(cell(0, i), 2);
        else
            out.emplace_back(cell(height - 1, i), 3);
    }
    return out;
}
Ids Mesh::source_cells(int r1, int c1, int r2, int c2) const {
    Ids out;
    for (int r = r1; r <= r2; ++r)
        for (int c = c1; c <= c2; ++c)
            out.push_back(cell(r, c));
    return out;
}
