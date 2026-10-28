#include "mesh.hpp"
bool directed(const Face &face, int a, int b) {
    for (int i = 0; i < 3; ++i)
        if (face.vertices[i] == a && face.vertices[(i + 1) % 3] == b)
            return true;
    return false;
}
void flip(Face &face) {
    std::swap(face.vertices[1], face.vertices[2]);
}
void orient_faces(std::vector<Face> &faces, const Topology &topology) {
    std::vector<bool> visited(faces.size());
    for (std::size_t first = 0; first < faces.size(); ++first)
        if (!visited[first]) {
            std::vector<int> queue = {int(first)};
            visited[first] = true;
            for (std::size_t position = 0; position < queue.size(); ++position) {
                const int f = queue[position];
                const auto vertices = faces[f].vertices;
                for (int i = 0; i < 3; ++i) {
                    const int a = vertices[i], b = vertices[(i + 1) % 3];
                    const Edge &edge = topology.edges[edge_index(topology, a, b)];
                    if (edge.faces.size() != 2)
                        continue;
                    const int other = edge.faces[0] == f ? edge.faces[1] : edge.faces[0];
                    if (visited[other])
                        continue;
                    if (directed(faces[other], a, b))
                        flip(faces[other]);
                    visited[other] = true;
                    queue.push_back(other);
                }
            }
        }
}
std::vector<int> inconsistent_edges(const std::vector<Face> &faces, const Topology &topology) {
    std::vector<int> out;
    for (std::size_t e = 0; e < topology.edges.size(); ++e) {
        const Edge &edge = topology.edges[e];
        if (edge.faces.size() == 2 &&
            directed(faces[edge.faces[0]], edge.a, edge.b) == directed(faces[edge.faces[1]], edge.a, edge.b))
            out.push_back(e);
    }
    return out;
}
