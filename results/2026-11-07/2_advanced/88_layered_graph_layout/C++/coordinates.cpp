#include "layout.hpp"
const std::array<const char *, 4> variantNames{"ul", "ur", "dl", "dr"};
int floorDiv(int a, int b) {
    int value = a / b;
    if (a < 0 && a % b)
        --value;
    return value;
}
static int separation(const Layout &layout, int a, int b) {
    int gap = a < layout.nodes && b < layout.nodes ? layout.block->settings.nodeSep
                                                   : layout.block->settings.dummySep;
    return layout.vertices[a].right + layout.vertices[b].left + 1 + gap;
}
Coordinates coordinates(Layout &layout) {
    Coordinates out;
    int count = static_cast<int>(layout.vertices.size());
    Order pos = positions(layout.orders, count);
    for (std::size_t i = 0; i + 1 < layout.orders.size(); ++i) {
        const Order &upper = layout.orders[i], &lower = layout.orders[i + 1];
        int k0 = 0, start = 0;
        for (std::size_t end = 0; end < lower.size(); ++end) {
            int v = lower[end];
            bool inner = v >= layout.nodes && layout.vertices[v].upper[0] >= layout.nodes;
            if (!inner && end + 1 != lower.size())
                continue;
            int k1 = inner ? pos[layout.vertices[v].upper[0]] : static_cast<int>(upper.size()) - 1;
            for (std::size_t at = static_cast<std::size_t>(start); at <= end; ++at) {
                int w = lower[at];
                for (int u : layout.vertices[w].upper)
                    if (pos[u] < k0 || pos[u] > k1)
                        out.marked.insert(std::minmax(u, w));
            }
            start = static_cast<int>(end + 1);
            k0 = k1;
        }
    }
    for (int variant = 0; variant < 4; ++variant) {
        bool right = variant % 2, down = variant >= 2;
        Order root(count), align(count);
        std::iota(root.begin(), root.end(), 0);
        align = root;
        const auto rank = [&](int v) {
            return right ? static_cast<int>(layout.orders[layout.vertices[v].layer].size()) - 1 -
                               pos[v]
                         : pos[v];
        };
        int layers = static_cast<int>(layout.orders.size());
        for (int offset = 1; offset < layers; ++offset) {
            int layer = down ? layers - 1 - offset : offset;
            int rho = -1;
            Order scan = layout.orders[layer];
            if (right)
                std::reverse(scan.begin(), scan.end());
            for (int v : scan) {
                Order reference = down ? layout.vertices[v].lower : layout.vertices[v].upper;
                if (reference.empty())
                    continue;
                std::sort(reference.begin(), reference.end(),
                          [&](int a, int b) { return rank(a) < rank(b); });
                for (std::size_t median : {(reference.size() - 1) / 2, reference.size() / 2}) {
                    int u = reference[median];
                    if (align[v] == v && !out.marked.count(std::minmax(u, v)) && rho < rank(u)) {
                        align[u] = v;
                        root[v] = root[u];
                        align[v] = root[v];
                        rho = rank(u);
                    }
                }
            }
        }
        std::map<std::pair<int, int>, int> constraints;
        for (Order scan : layout.orders) {
            if (right)
                std::reverse(scan.begin(), scan.end());
            for (std::size_t i = 0; i + 1 < scan.size(); ++i) {
                int a = scan[i], b = scan[i + 1],
                    delta = right ? separation(layout, b, a) : separation(layout, a, b);
                int &weight = constraints[{root[a], root[b]}];
                weight = std::max(weight, delta);
            }
        }
        using Weighted = std::pair<int, int>;
        std::vector<std::vector<Weighted>> incoming(count), outgoing(count);
        for (const auto &entry : constraints) {
            int a = entry.first.first, b = entry.first.second;
            incoming[b].emplace_back(a, entry.second);
            outgoing[a].emplace_back(b, entry.second);
        }
        Order y1(count, -1), y2(count, -1);
        std::function<int(int)> leftmost = [&](int r) {
            if (y1[r] >= 0)
                return y1[r];
            int value = 0;
            for (const Weighted &edge : incoming[r])
                value = std::max(value, leftmost(edge.first) + edge.second);
            return y1[r] = value;
        };
        std::function<int(int)> rightmost = [&](int r) {
            if (y2[r] >= 0)
                return y2[r];
            int value = leftmost(r);
            if (!outgoing[r].empty()) {
                int minimum = std::numeric_limits<int>::max();
                for (const Weighted &edge : outgoing[r])
                    minimum = std::min(minimum, rightmost(edge.first) - edge.second);
                value = std::max(value, minimum);
            }
            return y2[r] = value;
        };
        BKVariant &result = out.variants[variant];
        result.root = root;
        result.blocks = static_cast<int>(std::set<int>(root.begin(), root.end()).size());
        result.aligned.resize(count);
        for (int v = 0; v < count; ++v) {
            int x = rightmost(root[v]);
            if (right)
                x = -x;
            result.aligned[v] = x;
            int low = x - layout.vertices[v].left, high = x + layout.vertices[v].right;
            if (!v || low < result.low)
                result.low = low;
            if (!v || high > result.high)
                result.high = high;
        }
        result.width = result.high - result.low + 1;
    }
    for (int i = 1; i < 4; ++i)
        if (out.variants[i].width < out.variants[out.smallest].width)
            out.smallest = i;
    int bestLow = out.variants[out.smallest].low, bestHigh = out.variants[out.smallest].high;
    for (int i = 0; i < 4; ++i) {
        BKVariant &variant = out.variants[i];
        int shift = i % 2 ? bestHigh - variant.high : bestLow - variant.low;
        for (int &value : variant.aligned)
            value += shift;
    }
    int minimum = 0;
    for (int v = 0; v < count; ++v) {
        std::array<int, 4> values;
        for (int i = 0; i < 4; ++i)
            values[i] = out.variants[i].aligned[v];
        std::sort(values.begin(), values.end());
        layout.vertices[v].x = floorDiv(values[1] + values[2], 2);
        int low = layout.vertices[v].x - layout.vertices[v].left;
        if (!v || low < minimum)
            minimum = low;
    }
    for (Vertex &vertex : layout.vertices)
        vertex.x -= minimum;
    return out;
}
