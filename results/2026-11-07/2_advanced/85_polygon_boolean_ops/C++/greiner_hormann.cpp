#include "geometry.hpp"
#include <algorithm>
#include <map>
struct Inserted {
    Fraction position;
    GhNode *node;
};
GhGraph::GhGraph(const Rings &first, const Rings &second) : rings{first, second} {
    std::array<std::vector<std::vector<std::vector<Inserted>>>, 2> slots;
    for (int side = 0; side < 2; ++side) {
        slots[side].resize(rings[side].size());
        for (std::size_t i = 0; i < rings[side].size(); ++i)
            slots[side][i].resize(rings[side][i].points.size());
    }
    for (std::size_t i = 0; i < first.size(); ++i)
        for (std::size_t e = 0; e < first[i].points.size(); ++e)
            for (std::size_t j = 0; j < second.size(); ++j)
                for (std::size_t f = 0; f < second[j].points.size(); ++f) {
                    std::optional<Intersection> value =
                        crossing(first[i].edges[e], second[j].edges[f]);
                    if (!value)
                        continue;
                    nodeStorage.push_back(std::make_unique<GhNode>(
                        GhNode{value->point, 0, nullptr, false, first[i].edges[e]}));
                    GhNode *a = nodeStorage.back().get();
                    nodeStorage.push_back(std::make_unique<GhNode>(
                        GhNode{value->point, 1, nullptr, false, second[j].edges[f]}));
                    GhNode *b = nodeStorage.back().get();
                    crossingStorage.push_back(
                        std::make_unique<Crossing>(Crossing{value->point, a, b}));
                    a->crossing = b->crossing = crossingStorage.back().get();
                    a->other = b;
                    b->other = a;
                    slots[0][i][e].push_back({value->first, a});
                    slots[1][j][f].push_back({value->second, b});
                }
    for (int side = 0; side < 2; ++side)
        for (std::size_t i = 0; i < rings[side].size(); ++i) {
            const Ring &ring = rings[side][i];
            std::vector<GhNode *> list;
            for (std::size_t e = 0; e < ring.points.size(); ++e) {
                nodeStorage.push_back(std::make_unique<GhNode>(
                    GhNode{ring.points[e], side, nullptr, false, ring.edges[e]}));
                list.push_back(nodeStorage.back().get());
                std::vector<Inserted> &inserted = slots[side][i][e];
                std::sort(inserted.begin(), inserted.end(),
                          [](const Inserted &a, const Inserted &b) {
                              return a.position.compare(b.position) < 0;
                          });
                for (const Inserted &value : inserted)
                    list.push_back(value.node);
            }
            bool state = interior(ring.points[0], rings[1 - side]);
            initialInside[side].push_back(state);
            if (state) {
                if (side == 0)
                    ++na;
                else
                    ++nb;
            }
            for (std::size_t k = 0; k < list.size(); ++k) {
                GhNode *node = list[k];
                node->previous = list[(k + list.size() - 1) % list.size()];
                node->next = list[(k + 1) % list.size()];
                if (node->crossing) {
                    node->entering = !state;
                    state = !state;
                    if (side == 0)
                        crossings.push_back(node->crossing);
                }
            }
            nodes[side].push_back(std::move(list));
        }
}
Rings GhGraph::traverse(bool invertFirst, bool invertSecond) const {
    bool inverted[2] = {invertFirst, invertSecond};
    std::vector<bool> visited(crossingStorage.size());
    std::map<const Crossing *, std::size_t> numbers;
    for (std::size_t i = 0; i < crossingStorage.size(); ++i)
        numbers[crossingStorage[i].get()] = i;
    Rings result;
    for (Crossing *start : crossings) {
        if (visited[numbers.at(start)])
            continue;
        Ring ring;
        GhNode *current = start->first;
        for (;;) {
            visited[numbers.at(current->crossing)] = true;
            ring.points.push_back(current->point);
            bool forward = current->entering != inverted[current->side];
            GhNode *moving = current;
            for (;;) {
                GhNode *next = forward ? moving->next : moving->previous;
                ring.edges.push_back(forward ? moving->outgoing : reverseLine(next->outgoing));
                moving = next;
                if (moving->crossing)
                    break;
                ring.points.push_back(moving->point);
            }
            if (moving->crossing == start)
                break;
            current = moving->other;
        }
        result.push_back(std::move(ring));
    }
    for (int side = 0; side < 2; ++side)
        for (std::size_t i = 0; i < rings[side].size(); ++i) {
            bool crossing = false;
            for (const GhNode *node : nodes[side][i])
                crossing = crossing || node->crossing != nullptr;
            if (!crossing && initialInside[side][i] != inverted[side])
                result.push_back(rings[side][i]);
        }
    return result;
}
