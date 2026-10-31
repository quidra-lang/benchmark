#include "mesh.hpp"
int Loop::length() const {
    return int(vertices.size()) - (closed ? 0 : 1);
}
int edge_index(const Topology &topology, int a, int b) {
    if (a > b)
        std::swap(a, b);
    auto edge = std::lower_bound(
        topology.edges.begin(), topology.edges.end(), std::make_pair(a, b),
        [](const Edge &e, const std::pair<int, int> &key) { return std::make_pair(e.a, e.b) < key; });
    return edge != topology.edges.end() && edge->a == a && edge->b == b ? int(edge - topology.edges.begin())
                                                                        : -1;
}
Topology analyze(const std::vector<Face> &faces, int vertices) {
    Topology out;
    std::map<std::pair<int, int>, std::vector<int>> table;
    out.vertex_faces.resize(vertices + 1);
    out.vertex_edges.resize(vertices + 1);
    out.neighbors.resize(vertices + 1);
    out.fans.resize(vertices + 1);
    out.fan_components.resize(vertices + 1);
    out.face_component.assign(faces.size(), -1);
    for (std::size_t f = 0; f < faces.size(); ++f) {
        const auto &v = faces[f].vertices;
        for (int vertex : v)
            out.vertex_faces[vertex].push_back(f);
        for (int i = 0; i < 3; ++i)
            table[std::minmax(v[i], v[(i + 1) % 3])].push_back(f);
    }
    for (const auto &entry : table) {
        const int index = out.edges.size(), a = entry.first.first, b = entry.first.second;
        out.edges.push_back({a, b, entry.second});
        out.vertex_edges[a].push_back(index);
        out.vertex_edges[b].push_back(index);
        out.neighbors[a].push_back(b);
        out.neighbors[b].push_back(a);
    }
    for (auto &neighbors : out.neighbors)
        std::sort(neighbors.begin(), neighbors.end());
    for (std::size_t first = 0; first < faces.size(); ++first)
        if (out.face_component[first] < 0) {
            const int component = out.component_faces.size();
            std::vector<int> queue = {int(first)};
            out.face_component[first] = component;
            for (std::size_t position = 0; position < queue.size(); ++position) {
                const auto &v = faces[queue[position]].vertices;
                for (int i = 0; i < 3; ++i) {
                    const Edge &edge = out.edges[edge_index(out, v[i], v[(i + 1) % 3])];
                    for (int next : edge.faces)
                        if (out.face_component[next] < 0) {
                            out.face_component[next] = component;
                            queue.push_back(next);
                        }
                }
            }
            std::sort(queue.begin(), queue.end());
            out.component_faces.push_back(queue);
        }
    out.component_vertices.resize(out.component_faces.size());
    out.component_edges.resize(out.component_faces.size());
    out.component_nonmanifold_vertices.resize(out.component_faces.size());
    for (std::size_t c = 0; c < out.component_faces.size(); ++c) {
        std::set<int> used;
        for (int f : out.component_faces[c])
            used.insert(faces[f].vertices.begin(), faces[f].vertices.end());
        out.component_vertices[c].assign(used.begin(), used.end());
    }
    for (std::size_t e = 0; e < out.edges.size(); ++e)
        out.component_edges[out.face_component[out.edges[e].faces[0]]].push_back(e);
    for (int vertex = 1; vertex <= vertices; ++vertex) {
        std::vector<bool> visited(faces.size());
        std::map<int, int> per_component;
        for (int first : out.vertex_faces[vertex])
            if (!visited[first]) {
                std::vector<int> queue = {first};
                visited[first] = true;
                for (std::size_t position = 0; position < queue.size(); ++position)
                    for (int e : out.vertex_edges[vertex]) {
                        const Edge &edge = out.edges[e];
                        if (std::find(edge.faces.begin(), edge.faces.end(), queue[position]) ==
                            edge.faces.end())
                            continue;
                        for (int next : edge.faces)
                            if (!visited[next]) {
                                visited[next] = true;
                                queue.push_back(next);
                            }
                    }
                ++out.fans[vertex];
                ++per_component[out.face_component[first]];
            }
        for (const auto &entry : per_component) {
            out.fan_components[vertex].push_back(entry.first);
            if (entry.second >= 2)
                out.component_nonmanifold_vertices[entry.first].push_back(vertex);
        }
    }
    return out;
}
std::vector<Loop> trace_loops(const Topology &topology) {
    std::vector<Loop> loops;
    std::vector<bool> used(topology.edges.size());
    for (std::size_t component = 0; component < topology.component_faces.size(); ++component)
        for (int first : topology.component_edges[component]) {
            const Edge &edge = topology.edges[first];
            if (edge.faces.size() != 1 || used[first])
                continue;
            used[first] = true;
            Loop loop;
            loop.component = component;
            loop.vertices = {edge.a, edge.b};
            while (loop.vertices.back() != edge.a) {
                const int x = loop.vertices.back();
                int selected = -1, other = 0;
                for (int e : topology.vertex_edges[x]) {
                    const Edge &candidate = topology.edges[e];
                    if (used[e] || candidate.faces.size() != 1 ||
                        topology.face_component[candidate.faces[0]] != int(component))
                        continue;
                    const int y = candidate.a == x ? candidate.b : candidate.a;
                    if (selected < 0 || y < other) {
                        selected = e;
                        other = y;
                    }
                }
                if (selected < 0)
                    break;
                used[selected] = true;
                loop.vertices.push_back(other);
            }
            loop.closed = loop.vertices.back() == edge.a;
            if (loop.closed)
                loop.vertices.pop_back();
            loops.push_back(std::move(loop));
        }
    return loops;
}
