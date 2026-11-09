#include "mesh.hpp"
Lines read_lines(const std::string &path) {
    std::ifstream file(path);
    Lines lines;
    std::string line;
    while (std::getline(file, line))
        lines.push_back(line);
    return lines;
}
Lines words(const std::string &line) {
    std::istringstream stream(line);
    Lines out;
    std::string word;
    while (stream >> word)
        out.push_back(word);
    return out;
}
bool integer_word(const std::string &word) {
    std::size_t first = !word.empty() && word[0] == '-' ? 1 : 0;
    if (first == word.size())
        return false;
    for (std::size_t i = first; i < word.size(); ++i)
        if (word[i] < '0' || word[i] > '9')
            return false;
    return true;
}
Object read_object() {
    Object out;
    std::string current = "default";
    for (const std::string &line : read_lines("input/model.obj")) {
        ++out.lines;
        if (line.empty() || line[0] == '#')
            continue;
        const Lines tokens = words(line);
        const std::string &key = tokens[0];
        std::string error;
        if (key == "v") {
            if (tokens.size() != 4 || !integer_word(tokens[1]) || !integer_word(tokens[2]) ||
                !integer_word(tokens[3]))
                error = "bad_vertex";
            else
                out.vertices.push_back({std::stoll(tokens[1]), std::stoll(tokens[2]), std::stoll(tokens[3])});
        } else if (key == "f") {
            Polygon polygon;
            polygon.line = out.lines;
            if (tokens.size() < 4)
                error = "short_face";
            else
                for (std::size_t i = 1; i < tokens.size(); ++i) {
                    const std::string vertex = tokens[i].substr(0, tokens[i].find('/'));
                    if (!integer_word(vertex) || std::stoll(vertex) == 0) {
                        error = "bad_index";
                        break;
                    }
                    const Integer index = std::stoll(vertex),
                                  number = index > 0 ? index : Integer(out.vertices.size()) + index;
                    if (number < 1 || number >= Integer(out.vertices.size())) {
                        error = "out_of_range";
                        break;
                    }
                    polygon.vertices.push_back(int(number));
                }
            if (error.empty()) {
                auto group = std::find(out.groups.begin(), out.groups.end(), current);
                if (group == out.groups.end()) {
                    out.groups.push_back(current);
                    polygon.group = out.groups.size() - 1;
                } else
                    polygon.group = group - out.groups.begin();
                out.polygons.push_back(std::move(polygon));
            }
        } else if (key == "g")
            current = tokens.size() > 1 ? tokens[1] : "default";
        else if (key == "vt" || key == "vn" || key == "s" || key == "o" || key == "usemtl" || key == "mtllib")
            ++out.ignored;
        else
            error = "unknown_keyword";
        if (!error.empty())
            out.errors.push_back({out.lines, error});
    }
    return out;
}
void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream file("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        file << line << '\n';
}
void write_object(const std::vector<Point> &points, const std::vector<Face> &faces, const Lines &groups) {
    Lines lines = {"# vertices " + std::to_string(points.size() - 1) + " faces " +
                   std::to_string(faces.size())};
    for (std::size_t i = 1; i < points.size(); ++i)
        lines.push_back("v " + point_text(points[i]));
    int group = -1;
    for (const Face &face : faces) {
        if (face.group != group) {
            group = face.group;
            lines.push_back("g " + groups[group]);
        }
        lines.push_back("f " + std::to_string(face.vertices[0]) + " " + std::to_string(face.vertices[1]) +
                        " " + std::to_string(face.vertices[2]));
    }
    write_lines("repaired.obj", lines);
}
