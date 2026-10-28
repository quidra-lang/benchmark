#include "spatial.hpp"
Integer area(Box b) {
    return (b.x2 - b.x1) * (b.y2 - b.y1);
}
Box mbr(Box a, Box b) {
    return {std::min(a.x1, b.x1), std::min(a.y1, b.y1), std::max(a.x2, b.x2), std::max(a.y2, b.y2)};
}
Integer enlargement(Box a, Box b) {
    return area(mbr(a, b)) - area(a);
}
bool intersects(Box a, Box b) {
    return a.x1 <= b.x2 && b.x1 <= a.x2 && a.y1 <= b.y2 && b.y1 <= a.y2;
}
bool contains(Box a, Box b) {
    return a.x1 <= b.x1 && b.x2 <= a.x2 && a.y1 <= b.y1 && b.y2 <= a.y2;
}
Integer overlap(Box a, Box b) {
    const Integer w = std::min(a.x2, b.x2) - std::max(a.x1, b.x1),
                  h = std::min(a.y2, b.y2) - std::max(a.y1, b.y1);
    return w > 0 && h > 0 ? w * h : 0;
}
Integer distance(Integer x, Integer y, Box b) {
    const Integer dx = x < b.x1   ? b.x1 - x
                       : x > b.x2 ? x - b.x2
                                  : 0,
                  dy = y < b.y1   ? b.y1 - y
                       : y > b.y2 ? y - b.y2
                                  : 0;
    return dx * dx + dy * dy;
}
Box RNode::box() const {
    Box out = entries[0].box;
    for (std::size_t i = 1; i < entries.size(); ++i)
        out = mbr(out, entries[i].box);
    return out;
}
RTree::RTree(int max, int min) : root(std::make_shared<RNode>()), maximum(max), minimum(min) {
}
std::shared_ptr<RNode> RTree::split(const std::shared_ptr<RNode> &node) {
    const auto old = node->entries;
    int first = 0, second = 1;
    Integer largest = area(mbr(old[0].box, old[1].box)) - area(old[0].box) - area(old[1].box);
    for (std::size_t i = 0; i + 1 < old.size(); ++i)
        for (std::size_t j = i + 1; j < old.size(); ++j) {
            const Integer value = area(mbr(old[i].box, old[j].box)) - area(old[i].box) - area(old[j].box);
            if (value > largest) {
                largest = value;
                first = i;
                second = j;
            }
        }
    std::vector<Entry> a{old[first]}, b{old[second]}, rest;
    for (std::size_t i = 0; i < old.size(); ++i)
        if (int(i) != first && int(i) != second)
            rest.push_back(old[i]);
    Box ba = a[0].box, bb = b[0].box;
    while (!rest.empty()) {
        if (int(a.size() + rest.size()) == minimum) {
            a.insert(a.end(), rest.begin(), rest.end());
            break;
        }
        if (int(b.size() + rest.size()) == minimum) {
            b.insert(b.end(), rest.begin(), rest.end());
            break;
        }
        int chosen = 0;
        Integer difference = -1;
        for (std::size_t i = 0; i < rest.size(); ++i) {
            const Integer x = enlargement(ba, rest[i].box), y = enlargement(bb, rest[i].box),
                          value = x > y ? x - y : y - x;
            if (value > difference) {
                difference = value;
                chosen = i;
            }
        }
        const Entry entry = rest[chosen];
        rest.erase(rest.begin() + chosen);
        const Integer d1 = enlargement(ba, entry.box), d2 = enlargement(bb, entry.box);
        const bool left =
            d1 < d2 || (d1 == d2 && (area(ba) < area(bb) || (area(ba) == area(bb) && a.size() <= b.size())));
        if (left) {
            a.push_back(entry);
            ba = mbr(ba, entry.box);
        } else {
            b.push_back(entry);
            bb = mbr(bb, entry.box);
        }
    }
    node->entries = std::move(a);
    auto sibling = std::make_shared<RNode>();
    sibling->level = node->level;
    sibling->parent = node->parent;
    sibling->entries = std::move(b);
    for (Entry &entry : node->entries)
        if (entry.child)
            entry.child->parent = node.get();
    for (Entry &entry : sibling->entries)
        if (entry.child)
            entry.child->parent = sibling.get();
    return sibling;
}
void RTree::insert(Entry entry, int level) {
    auto node = root;
    while (node->level > level) {
        std::size_t chosen = 0;
        for (std::size_t i = 1; i < node->entries.size(); ++i) {
            const Box a = node->entries[i].box, b = node->entries[chosen].box;
            if (std::make_tuple(enlargement(a, entry.box), area(a), i) <
                std::make_tuple(enlargement(b, entry.box), area(b), chosen))
                chosen = i;
        }
        node = node->entries[chosen].child;
    }
    node->entries.push_back(entry);
    if (entry.child)
        entry.child->parent = node.get();
    while (true) {
        std::shared_ptr<RNode> sibling;
        if (int(node->entries.size()) > maximum)
            sibling = split(node);
        RNode *parent = node->parent;
        if (!parent) {
            if (sibling) {
                root = std::make_shared<RNode>();
                root->level = node->level + 1;
                root->entries = {{node->box(), 0, 0, node}, {sibling->box(), 0, 0, sibling}};
                node->parent = root.get();
                sibling->parent = root.get();
            }
            break;
        }
        for (Entry &parent_entry : parent->entries)
            if (parent_entry.child.get() == node.get()) {
                parent_entry.box = node->box();
                break;
            }
        if (sibling) {
            parent->entries.push_back({sibling->box(), 0, 0, sibling});
            sibling->parent = parent;
        }
        node = parent->shared_from_this();
    }
}
std::shared_ptr<RNode> RTree::leaf(Point point) const {
    std::function<std::shared_ptr<RNode>(std::shared_ptr<RNode>)> find =
        [&](std::shared_ptr<RNode> node) -> std::shared_ptr<RNode> {
        if (node->level == 0) {
            for (const Entry &entry : node->entries)
                if (entry.id == point.id)
                    return node;
            return {};
        }
        for (const Entry &entry : node->entries)
            if (contains(entry.box, point.box())) {
                const auto result = find(entry.child);
                if (result)
                    return result;
            }
        return {};
    };
    return find(root);
}
void RTree::erase(Point point) {
    auto node = leaf(point);
    node->entries.erase(std::find_if(node->entries.begin(), node->entries.end(),
                                     [&](const Entry &entry) { return entry.id == point.id; }));
    std::vector<std::shared_ptr<RNode>> removed;
    while (node.get() != root.get()) {
        auto parent = node->parent->shared_from_this();
        const auto position =
            std::find_if(parent->entries.begin(), parent->entries.end(),
                         [&](const Entry &entry) { return entry.child.get() == node.get(); });
        if (int(node->entries.size()) < minimum) {
            parent->entries.erase(position);
            removed.push_back(node);
        } else
            position->box = node->box();
        node = parent;
    }
    for (const auto &old : removed) {
        const auto entries = old->entries;
        for (const Entry &entry : entries)
            insert(entry, old->level);
    }
    while (root->level > 0 && root->entries.size() == 1) {
        auto child = root->entries[0].child;
        root = std::move(child);
        root->parent = nullptr;
    }
}
void RTree::bulk(std::vector<Entry> entries) {
    int level = 0;
    while (true) {
        const int pages = (entries.size() + maximum - 1) / maximum;
        int slabs = 1;
        while (slabs * slabs < pages)
            ++slabs;
        std::sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) {
            return std::make_tuple(a.box.x1 + a.box.x2, a.box.y1 + a.box.y2, a.number) <
                   std::make_tuple(b.box.x1 + b.box.x2, b.box.y1 + b.box.y2, b.number);
        });
        std::vector<std::shared_ptr<RNode>> nodes;
        for (std::size_t start = 0; start < entries.size(); start += slabs * maximum) {
            const std::size_t end = std::min(entries.size(), start + slabs * maximum);
            std::sort(entries.begin() + start, entries.begin() + end, [](const Entry &a, const Entry &b) {
                return std::make_tuple(a.box.y1 + a.box.y2, a.box.x1 + a.box.x2, a.number) <
                       std::make_tuple(b.box.y1 + b.box.y2, b.box.x1 + b.box.x2, b.number);
            });
            for (std::size_t begin = start; begin < end; begin += maximum) {
                auto node = std::make_shared<RNode>();
                node->level = level;
                node->entries.assign(entries.begin() + begin,
                                     entries.begin() + std::min(end, begin + maximum));
                for (Entry &entry : node->entries)
                    if (entry.child)
                        entry.child->parent = node.get();
                nodes.push_back(std::move(node));
            }
        }
        if (nodes.size() == 1) {
            root = nodes[0];
            root->parent = nullptr;
            return;
        }
        entries.clear();
        for (std::size_t i = 0; i < nodes.size(); ++i)
            entries.push_back({nodes[i]->box(), 0, int(i), nodes[i]});
        ++level;
    }
}
