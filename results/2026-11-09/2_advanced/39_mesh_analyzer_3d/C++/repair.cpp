#include "mesh.hpp"
std::vector<Face> triangulate(const Object &object) {
    std::vector<Face> out;
    for (std::size_t p = 0; p < object.polygons.size(); ++p) {
        const Polygon &polygon = object.polygons[p];
        for (std::size_t i = 1; i + 1 < polygon.vertices.size(); ++i)
            out.push_back({{polygon.vertices[0], polygon.vertices[i], polygon.vertices[i + 1]},
                           int(p + 1),
                           polygon.line,
                           polygon.group,
                           int(out.size() + 1)});
    }
    return out;
}
static Integer floor_div(Integer a, Integer b) {
    Integer quotient = a / b;
    if (a % b < 0)
        --quotient;
    return quotient;
}
Cleanup cleanup(const Object &object, const Options &options) {
    Cleanup out;
    out.snapped = object.vertices;
    out.representative.resize(object.vertices.size());
    out.new_number.resize(object.vertices.size());
    for (std::size_t v = 1; v < out.snapped.size(); ++v) {
        for (Integer &coordinate : out.snapped[v])
            coordinate = options.snap * floor_div(2 * coordinate + options.snap, 2 * options.snap);
        if (out.snapped[v] != object.vertices[v])
            ++out.snapped_count;
        out.representative[v] = v;
        if (options.merge)
            for (std::size_t earlier = 1; earlier < v; ++earlier)
                if (out.snapped[earlier] == out.snapped[v]) {
                    out.representative[v] = earlier;
                    break;
                }
        if (out.representative[v] != int(v))
            ++out.merged_count;
    }
    const auto triangles = triangulate(object);
    out.triangles = triangles.size();
    std::set<std::array<int, 3>> seen;
    std::set<int> used;
    for (Face face : triangles) {
        for (int &vertex : face.vertices)
            vertex = out.representative[vertex];
        auto key = face.vertices;
        std::sort(key.begin(), key.end());
        std::string reason;
        if (key[0] == key[1] || key[1] == key[2])
            reason = "repeated";
        else if (options.degenerate && normal(face, out.snapped) == Point{0, 0, 0})
            reason = "zero_area";
        else if (options.duplicates && seen.count(key))
            reason = "duplicate";
        if (!reason.empty())
            out.removed.push_back({face.triangle, face.polygon, face.line, reason});
        else {
            seen.insert(key);
            used.insert(face.vertices.begin(), face.vertices.end());
            out.faces.push_back(face);
        }
    }
    for (std::size_t v = 1; v < out.snapped.size(); ++v)
        if ((options.keep_unused && out.representative[v] == int(v)) ||
            (!options.keep_unused && used.count(v))) {
            out.new_number[v] = out.points.size();
            out.points.push_back(out.snapped[v]);
        }
    for (Face &face : out.faces)
        for (int &vertex : face.vertices)
            vertex = out.new_number[vertex];
    return out;
}
std::vector<Face> fill_faces(const Loop &loop, int group) {
    std::vector<Face> out;
    for (std::size_t i = 1; i + 1 < loop.vertices.size(); ++i)
        out.push_back({{loop.vertices[0], loop.vertices[i + 1], loop.vertices[i]}, 0, 0, group, 0});
    return out;
}
