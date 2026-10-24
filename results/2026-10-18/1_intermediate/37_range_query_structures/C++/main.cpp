#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <numeric>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

using namespace std;
using Integer = int64_t;
using Values = vector<Integer>;
using Lines = vector<string>;

enum class Operation { Sum, Min, Max, Gcd };
enum class Kind { Seg, Lazy, Fen, Rfen, Sparse, Sqrt, Persist };
const array<string, 7> names{"SEG", "LAZY", "FEN", "RFEN", "SPARSE", "SQRT", "PERSIST"};
const array<string, 4> operations{"SUM", "MIN", "MAX", "GCD"};
const array<string, 4> labels{"sum", "min", "max", "gcd"};
struct CommandError : runtime_error { using runtime_error::runtime_error; };
struct Span {
    int left = 0, right = -1;
    int middle() const { return (left + right) / 2; }
    bool leaf() const { return left == right; }
    bool covers(Span other) const { return left <= other.left && other.right <= right; }
};
struct Answer { Integer value = 0; int visited = 0; };
struct Aggregate {
    Integer sum = 0, minimum = 0, maximum = 0;
    string text() const { return "sum=" + to_string(sum) + " min=" + to_string(minimum) + " max=" + to_string(maximum); }
};
struct Counts { int visited = 0, covered = 0, pushes = 0; };
struct LazyAnswer { Aggregate value; Counts counts; };
struct BlockAnswer { Integer sum; int whole, cells; };
struct Report { string text; Values values; };

int lowbit(int value) { return value & -value; }
int floorLog(int value) { int result = 0; while ((1 << (result + 1)) <= value) ++result; return result; }
int integerSqrt(int value) { int result = 1; while ((result + 1) * (result + 1) <= value) ++result; return result; }
template<class T> string joined(const vector<T>& values) {
    ostringstream out;
    for (size_t index = 0; index < values.size(); ++index) {
        if (index) out << ' ';
        out << values[index];
    }
    return out.str();
}
template<class T> vector<T> slice(const vector<T>& values, int first, int end) {
    return vector<T>(values.begin() + first, values.begin() + end);
}
Integer combine(Operation operation, Integer a, Integer b) {
    switch (operation) {
        case Operation::Sum: return a + b;
        case Operation::Min: return min(a, b);
        case Operation::Max: return max(a, b);
        case Operation::Gcd: return gcd(a, b);
    }
    throw logic_error("Invalid operation");
}
Aggregate merge(Aggregate a, Aggregate b) { return {a.sum + b.sum, min(a.minimum, b.minimum), max(a.maximum, b.maximum)}; }
Aggregate direct(const Values& values, Span range) {
    auto first = values.begin() + range.left, end = values.begin() + range.right + 1;
    return {accumulate(first, end, Integer{0}), *min_element(first, end), *max_element(first, end)};
}
string measured(Answer answer) { return "sum=" + to_string(answer.value) + " visited=" + to_string(answer.visited); }

class SegmentTree {
    struct Node { Span span; Integer value = 0; };
    int n, maxNode = 0;
    vector<Node> nodes;
    void build(const Values& values, int index, Span span) {
        maxNode = max(maxNode, index);
        nodes[index].span = span;
        if (span.leaf()) nodes[index].value = operation == Operation::Gcd ? abs(values[span.left]) : values[span.left];
        else {
            build(values, 2 * index, {span.left, span.middle()});
            build(values, 2 * index + 1, {span.middle() + 1, span.right});
            pull(index);
        }
    }
    void pull(int index) { nodes[index].value = combine(operation, nodes[2 * index].value, nodes[2 * index + 1].value); }
public:
    Operation operation;
    SegmentTree(const Values& values, Operation op) : n(static_cast<int>(values.size())), nodes(4 * n), operation(op) { build(values, 1, {0, n - 1}); }
    Integer root() const { return nodes[1].value; }
    Answer query(Span range, int index = 1) const {
        const Node& node = nodes[index];
        if (range.covers(node.span)) return {node.value, 1};
        Answer answer;
        if (range.right <= node.span.middle()) answer = query(range, 2 * index);
        else if (range.left > node.span.middle()) answer = query(range, 2 * index + 1);
        else {
            Answer left = query(range, 2 * index), right = query(range, 2 * index + 1);
            answer = {combine(operation, left.value, right.value), left.visited + right.visited};
        }
        ++answer.visited;
        return answer;
    }
    int update(int position, Integer value, int index = 1) {
        Node& node = nodes[index];
        if (node.span.leaf()) { node.value = operation == Operation::Gcd ? abs(value) : value; return 1; }
        int visited = update(position, value, position <= node.span.middle() ? 2 * index : 2 * index + 1);
        pull(index);
        return visited + 1;
    }
    string buildLine() const { return "SEG BUILD " + operations[static_cast<int>(operation)] + " nodes=" + to_string(2 * n - 1) + " maxnode=" + to_string(maxNode) + " root=" + to_string(root()); }
    Lines dump() const {
        Lines rows{"SEG DUMP " + operations[static_cast<int>(operation)] + " nodes=" + to_string(2 * n - 1)};
        for (int index = 1; index <= maxNode; ++index) {
            const Node& node = nodes[index];
            if (node.span.right >= 0) rows.push_back("NODE " + to_string(index) + " " + to_string(node.span.left) + " " + to_string(node.span.right) + " " + to_string(node.value));
        }
        return rows;
    }
};

class LazyTree {
    struct Node { Span span; Aggregate value; optional<Integer> assignment; Integer addition = 0; };
    int n;
    vector<Node> nodes;
    void pull(int index) { nodes[index].value = merge(nodes[2 * index].value, nodes[2 * index + 1].value); }
    void build(const Values& values, int index, Span span) {
        nodes[index].span = span;
        if (span.leaf()) nodes[index].value = {values[span.left], values[span.left], values[span.left]};
        else {
            build(values, 2 * index, {span.left, span.middle()});
            build(values, 2 * index + 1, {span.middle() + 1, span.right});
            pull(index);
        }
    }
    void apply(int index, Integer value, bool assignment) {
        Node& node = nodes[index];
        Integer length = node.span.right - node.span.left + 1;
        if (assignment) node.value = {value * length, value, value};
        else { node.value.sum += value * length; node.value.minimum += value; node.value.maximum += value; }
        if (!node.span.leaf()) {
            if (assignment) { node.assignment = value; node.addition = 0; }
            else node.addition += value;
        }
    }
    int push(int index) {
        Node& node = nodes[index];
        if (!node.assignment && node.addition == 0) return 0;
        for (int child : {2 * index, 2 * index + 1}) {
            if (node.assignment) apply(child, *node.assignment, true);
            if (node.addition != 0) apply(child, node.addition, false);
        }
        node.assignment.reset(); node.addition = 0;
        return 1;
    }
    void updateAt(Span range, Integer value, bool assignment, int index, Counts& counts) {
        ++counts.visited;
        Span span = nodes[index].span;
        if (range.covers(span)) { ++counts.covered; apply(index, value, assignment); return; }
        counts.pushes += push(index);
        if (range.left <= span.middle()) updateAt(range, value, assignment, 2 * index, counts);
        if (range.right > span.middle()) updateAt(range, value, assignment, 2 * index + 1, counts);
        pull(index);
    }
    Aggregate queryAt(Span range, int index, Counts& counts) {
        ++counts.visited;
        Span span = nodes[index].span;
        if (range.covers(span)) return nodes[index].value;
        counts.pushes += push(index);
        if (range.right <= span.middle()) return queryAt(range, 2 * index, counts);
        if (range.left > span.middle()) return queryAt(range, 2 * index + 1, counts);
        Aggregate left = queryAt(range, 2 * index, counts), right = queryAt(range, 2 * index + 1, counts);
        return merge(left, right);
    }
public:
    explicit LazyTree(const Values& values) : n(static_cast<int>(values.size())), nodes(4 * n) { build(values, 1, {0, n - 1}); }
    Counts update(Span range, Integer value, bool assignment) { Counts counts; updateAt(range, value, assignment, 1, counts); return counts; }
    LazyAnswer query(Span range) { Counts counts; Aggregate value = queryAt(range, 1, counts); return {value, counts}; }
    string buildLine() const { return "LAZY BUILD nodes=" + to_string(2 * n - 1) + " " + nodes[1].value.text(); }
    Lines dump() const {
        Lines rows{"LAZY DUMP nodes=" + to_string(2 * n - 1)};
        for (size_t index = 1; index < nodes.size(); ++index) {
            const Node& node = nodes[index];
            if (node.span.right < 0) continue;
            rows.push_back("NODE " + to_string(index) + " " + to_string(node.span.left) + " " + to_string(node.span.right) + " " + node.value.text()
                + " assign=" + (node.assignment ? to_string(*node.assignment) : "-") + " add=" + to_string(node.addition));
        }
        return rows;
    }
};

class Fenwick {
public:
    Values tree;
    explicit Fenwick(const Values& values = {}) : tree(values.size() + 1) {
        copy(values.begin(), values.end(), tree.begin() + 1);
        for (int position = 1; position < static_cast<int>(tree.size()); ++position) {
            int parent = position + lowbit(position);
            if (parent < static_cast<int>(tree.size())) tree[parent] += tree[position];
        }
    }
    int add(int position, Integer value) {
        int visited = 0;
        for (; position < static_cast<int>(tree.size()); position += lowbit(position)) { tree[position] += value; ++visited; }
        return visited;
    }
    Answer prefix(int position) const {
        Answer answer;
        for (; position >= 1; position -= lowbit(position)) { answer.value += tree[position]; ++answer.visited; }
        return answer;
    }
    Answer range(Span span) const {
        Answer right = prefix(span.right + 1), left = prefix(span.left);
        return {right.value - left.value, right.visited + left.visited};
    }
    Answer lower(Integer rest) const {
        int size = static_cast<int>(tree.size()) - 1, position = 0, visited = 0;
        for (int step = 1 << floorLog(size); step >= 1; step /= 2) {
            if (position + step <= size) {
                ++visited;
                if (tree[position + step] < rest) { rest -= tree[position + step]; position += step; }
            }
        }
        return {position < size ? position : -1, visited};
    }
    string text() const { return joined(slice(tree, 1, static_cast<int>(tree.size()))); }
};
struct FenwickArray {
    Values values;
    Fenwick bit;
    explicit FenwickArray(const Values& values) : values(values), bit(values) {}
    int add(int index, Integer value) { values[index] += value; return bit.add(index + 1, value); }
    string buildLine() const { return "FEN BUILD n=" + to_string(values.size()) + " total=" + to_string(accumulate(values.begin(), values.end(), Integer{0})); }
    Lines dump() const { return {"FEN DUMP n=" + to_string(values.size()), "T " + bit.text()}; }
};
class RangeFenwick {
    int n;
    Fenwick first, second;
    Answer prefix(int position) const {
        Answer a = first.prefix(position), b = second.prefix(position);
        return {position * a.value - b.value, a.visited + b.visited};
    }
public:
    explicit RangeFenwick(const Values& values) : n(static_cast<int>(values.size())) {
        Values differences(n), weighted(n);
        for (int index = 0; index < n; ++index) {
            differences[index] = values[index] - (index == 0 ? 0 : values[index - 1]);
            weighted[index] = differences[index] * index;
        }
        first = Fenwick(differences); second = Fenwick(weighted);
    }
    int add(Span span, Integer value) {
        int visited = first.add(span.left + 1, value);
        visited += first.add(span.right + 2, -value);
        visited += second.add(span.left + 1, value * span.left);
        visited += second.add(span.right + 2, -value * (span.right + 1));
        return visited;
    }
    Answer query(Span span) const {
        Answer right = prefix(span.right + 1), left = prefix(span.left);
        return {right.value - left.value, right.visited + left.visited};
    }
    string buildLine() const { return "RFEN BUILD n=" + to_string(n) + " total=" + to_string(prefix(n).value); }
    Lines dump() const { return {"RFEN DUMP n=" + to_string(n), "B1 " + first.text(), "B2 " + second.text()}; }
};
class SparseTable {
    Values values;
    vector<vector<int>> minima, maxima;
public:
    struct Result {
        Integer minimum, maximum;
        int minpos, maxpos, level;
        string text() const { return "min=" + to_string(minimum) + " minpos=" + to_string(minpos) + " max=" + to_string(maximum) + " maxpos=" + to_string(maxpos) + " level=" + to_string(level); }
    };
    explicit SparseTable(const Values& source) : values(source) {
        vector<int> indices(values.size());
        iota(indices.begin(), indices.end(), 0);
        minima.push_back(indices); maxima.push_back(indices);
        for (int width = 2; width <= static_cast<int>(values.size()); width *= 2) {
            vector<int> lows, highs;
            for (int index = 0; index + width <= static_cast<int>(values.size()); ++index) {
                int a = minima.back()[index], b = minima.back()[index + width / 2];
                int c = maxima.back()[index], d = maxima.back()[index + width / 2];
                lows.push_back(values[a] <= values[b] ? a : b);
                highs.push_back(values[c] >= values[d] ? c : d);
            }
            minima.push_back(move(lows)); maxima.push_back(move(highs));
        }
    }
    Result query(Span span) const {
        int level = floorLog(span.right - span.left + 1), end = span.right - (1 << level) + 1;
        int a = minima[level][span.left], b = minima[level][end], c = maxima[level][span.left], d = maxima[level][end];
        int low = values[a] <= values[b] ? a : b, high = values[c] >= values[d] ? c : d;
        return {values[low], values[high], low, high, level};
    }
    string buildLine() const {
        size_t entries = 0;
        for (const auto& row : minima) entries += row.size();
        return "SPARSE BUILD levels=" + to_string(minima.size()) + " entries=" + to_string(entries);
    }
    Lines dump() const {
        Lines rows{"SPARSE DUMP levels=" + to_string(minima.size())};
        for (size_t level = 0; level < minima.size(); ++level) {
            rows.push_back("MIN " + to_string(level) + " " + joined(minima[level]));
            rows.push_back("MAX " + to_string(level) + " " + joined(maxima[level]));
        }
        return rows;
    }
};
class SquareRoot {
    int n;
    Values raw, tags, sums;
    struct Split { vector<int> cells, whole; };
    Split split(Span span) const {
        int left = span.left / block, right = span.right / block;
        Split result;
        if (left == right) {
            for (int index = span.left; index <= span.right; ++index) result.cells.push_back(index);
        } else {
            for (int index = span.left; index < (left + 1) * block; ++index) result.cells.push_back(index);
            for (int index = right * block; index <= span.right; ++index) result.cells.push_back(index);
            for (int index = left + 1; index < right; ++index) result.whole.push_back(index);
        }
        return result;
    }
public:
    int block;
    SquareRoot(const Values& values, int width) : n(static_cast<int>(values.size())), raw(values), tags((n + width - 1) / width), sums(tags.size()), block(width) {
        for (int index = 0; index < n; ++index) sums[index / block] += raw[index];
    }
    BlockAnswer add(Span span, Integer value) {
        Split parts = split(span);
        for (int index : parts.cells) { raw[index] += value; sums[index / block] += value; }
        for (int index : parts.whole) { tags[index] += value; sums[index] += value * block; }
        return {0, static_cast<int>(parts.whole.size()), static_cast<int>(parts.cells.size())};
    }
    BlockAnswer query(Span span) const {
        Split parts = split(span);
        Integer value = 0;
        for (int index : parts.cells) value += raw[index] + tags[index / block];
        for (int index : parts.whole) value += sums[index];
        return {value, static_cast<int>(parts.whole.size()), static_cast<int>(parts.cells.size())};
    }
    string buildLine() const { return "SQRT BUILD block=" + to_string(block) + " blocks=" + to_string(tags.size()); }
    Lines dump() const {
        Lines rows{"SQRT DUMP block=" + to_string(block) + " blocks=" + to_string(tags.size())};
        for (int index = 0; index < static_cast<int>(tags.size()); ++index) {
            int first = index * block, end = min(first + block, n);
            rows.push_back("BLOCK " + to_string(index) + " " + to_string(first) + " " + to_string(end - 1)
                + " add=" + to_string(tags[index]) + " sum=" + to_string(sums[index]) + " " + joined(slice(raw, first, end)));
        }
        return rows;
    }
};

struct PersistentNode {
    Integer sum;
    shared_ptr<const PersistentNode> left, right;
};
using Root = shared_ptr<const PersistentNode>;
class PersistentTree {
    int n;
    Root node(Integer value, Root left = nullptr, Root right = nullptr) {
        ++created;
        return make_shared<const PersistentNode>(PersistentNode{value, move(left), move(right)});
    }
    Root build(const Values& values, Span span) {
        if (span.leaf()) return node(values[span.left]);
        Root left = build(values, {span.left, span.middle()}), right = build(values, {span.middle() + 1, span.right});
        return node(left->sum + right->sum, left, right);
    }
    Root copyPath(Root previous, Span span, int index, Integer value, bool addition) {
        if (span.leaf()) return node(addition ? previous->sum + value : value);
        Root left = previous->left, right = previous->right;
        if (index <= span.middle()) left = copyPath(left, {span.left, span.middle()}, index, value, addition);
        else right = copyPath(right, {span.middle() + 1, span.right}, index, value, addition);
        return node(left->sum + right->sum, left, right);
    }
    Answer queryAt(Root root, Span span, Span range) const {
        if (range.covers(span)) return {root->sum, 1};
        Answer answer;
        if (range.right <= span.middle()) answer = queryAt(root->left, {span.left, span.middle()}, range);
        else if (range.left > span.middle()) answer = queryAt(root->right, {span.middle() + 1, span.right}, range);
        else {
            Answer left = queryAt(root->left, {span.left, span.middle()}, range);
            Answer right = queryAt(root->right, {span.middle() + 1, span.right}, range);
            answer = {left.value + right.value, left.visited + right.visited};
        }
        ++answer.visited;
        return answer;
    }
public:
    int created = 0;
    vector<Root> roots;
    explicit PersistentTree(const Values& values) : n(static_cast<int>(values.size())) { roots.push_back(build(values, {0, n - 1})); }
    int fork(int version, int index, Integer value, bool addition = false) {
        int before = created;
        roots.push_back(copyPath(roots[version], {0, n - 1}, index, value, addition));
        return created - before;
    }
    Answer query(int version, Span span) const { return queryAt(roots[version], {0, n - 1}, span); }
};
class Persistence {
    static Values distinct(Values values) {
        sort(values.begin(), values.end());
        values.erase(unique(values.begin(), values.end()), values.end());
        return values;
    }
    Values domain;
    PersistentTree prefixes;
public:
    PersistentTree positions;
    explicit Persistence(const Values& values) : domain(distinct(values)), prefixes(Values(domain.size())), positions(values) {
        for (int index = 0; index < static_cast<int>(values.size()); ++index) {
            int rank = static_cast<int>(lower_bound(domain.begin(), domain.end(), values[index]) - domain.begin());
            prefixes.fork(index, rank, 1, true);
        }
    }
    Answer kth(Span span, int k) const {
        Root upper = prefixes.roots[span.right + 1], lower = prefixes.roots[span.left];
        int left = 0, right = static_cast<int>(domain.size()) - 1, visited = 1;
        while (left < right) {
            int middle = (left + right) / 2;
            Integer count = upper->left->sum - lower->left->sum;
            if (k <= count) { upper = upper->left; lower = lower->left; right = middle; }
            else { k -= static_cast<int>(count); upper = upper->right; lower = lower->right; left = middle + 1; }
            ++visited;
        }
        return {domain[left], visited};
    }
    string buildLine() const { return "PERSIST BUILD nodes=" + to_string(positions.created) + " distinct=" + to_string(domain.size()) + " valuenodes=" + to_string(prefixes.created); }
    string nodeLine() const { return "PERSIST NODES versions=" + to_string(positions.roots.size()) + " position=" + to_string(positions.created) + " value=" + to_string(prefixes.created); }
};

class Grid {
    vector<Values> tree;
    Answer prefix(int row, int column) const {
        Answer answer;
        for (int y = row; y >= 1; y -= lowbit(y)) {
            for (int x = column; x >= 1; x -= lowbit(x)) { answer.value += tree[y][x]; ++answer.visited; }
        }
        return answer;
    }
public:
    int height, width;
    Grid(int h, int w, const Values& values) : tree(h + 1, Values(w + 1)), height(h), width(w) {
        for (int index = 0; index < static_cast<int>(values.size()); ++index) add(index / width, index % width, values[index]);
    }
    int add(int row, int column, Integer value) {
        int visited = 0;
        for (int y = row + 1; y <= height; y += lowbit(y)) {
            for (int x = column + 1; x <= width; x += lowbit(x)) { tree[y][x] += value; ++visited; }
        }
        return visited;
    }
    Answer query(int top, int left, int bottom, int right) const {
        Answer a = prefix(bottom + 1, right + 1), b = prefix(top, right + 1), c = prefix(bottom + 1, left), d = prefix(top, left);
        return {a.value - b.value - c.value + d.value, a.visited + b.visited + c.visited + d.visited};
    }
    Lines dump() const {
        Lines rows{"GRID DUMP rows=" + to_string(height) + " cols=" + to_string(width)};
        for (int row = 1; row <= height; ++row) rows.push_back("ROW " + to_string(row) + " " + joined(slice(tree[row], 1, width + 1)));
        return rows;
    }
};
Lines mo(const Values& values, const vector<Span>& ranges) {
    int block = integerSqrt(static_cast<int>(values.size()));
    vector<int> order(ranges.size()), answers(ranges.size());
    iota(order.begin(), order.end(), 0);
    sort(order.begin(), order.end(), [&](int a, int b) {
        int first = ranges[a].left / block, second = ranges[b].left / block;
        if (first != second) return first < second;
        if (ranges[a].right != ranges[b].right) return first % 2 == 0 ? ranges[a].right < ranges[b].right : ranges[a].right > ranges[b].right;
        return a < b;
    });
    unordered_map<Integer, int> frequency;
    int left = 0, right = -1, moves = 0;
    auto add = [&](int index) { ++frequency[values[index]]; ++moves; };
    auto remove = [&](int index) { auto entry = frequency.find(values[index]); if (--entry->second == 0) frequency.erase(entry); ++moves; };
    for (int index : order) {
        Span range = ranges[index];
        while (left > range.left) add(--left);
        while (right < range.right) add(++right);
        while (left < range.left) remove(left++);
        while (right > range.right) remove(right--);
        answers[index] = static_cast<int>(frequency.size());
    }
    for (int& index : order) ++index;
    Lines rows{"MO queries=" + to_string(ranges.size()) + " block=" + to_string(block) + " moves=" + to_string(moves), "ORDER " + joined(order)};
    for (int index = 0; index < static_cast<int>(ranges.size()); ++index) {
        rows.push_back("ANSWER " + to_string(index + 1) + " " + to_string(ranges[index].left) + " " + to_string(ranges[index].right) + " distinct=" + to_string(answers[index]));
    }
    return rows;
}

class Laboratory {
    Values values, original;
    optional<SegmentTree> segment;
    optional<LazyTree> lazy;
    optional<FenwickArray> fen;
    optional<RangeFenwick> rfen;
    optional<SparseTable> sparse;
    optional<SquareRoot> sqrt;
    optional<Persistence> persist;
    optional<Grid> grid;
    bool built(Kind kind) const {
        switch (kind) {
            case Kind::Seg: return segment.has_value();
            case Kind::Lazy: return lazy.has_value();
            case Kind::Fen: return fen.has_value();
            case Kind::Rfen: return rfen.has_value();
            case Kind::Sparse: return sparse.has_value();
            case Kind::Sqrt: return sqrt.has_value();
            case Kind::Persist: return persist.has_value();
        }
        return false;
    }
    int checkIndex(Integer index) const {
        if (index < 0 || index >= static_cast<Integer>(values.size())) throw CommandError("BAD INDEX " + to_string(index));
        return static_cast<int>(index);
    }
    Span checkRange(Integer left, Integer right) const {
        int l = checkIndex(left), r = checkIndex(right);
        if (l > r) throw CommandError("BAD RANGE " + to_string(l) + " " + to_string(r));
        return {l, r};
    }
    int checkVersion(Integer version) const {
        if (version < 0 || version >= static_cast<Integer>(persist->positions.roots.size())) throw CommandError("BAD VERSION " + to_string(version));
        return static_cast<int>(version);
    }
    void checkCell(int row, int column) const {
        if (row < 0 || row >= grid->height || column < 0 || column >= grid->width) throw CommandError("BAD CELL " + to_string(row) + " " + to_string(column));
    }
    string build(Kind kind, Operation operation = Operation::Sum, int block = 1) {
        switch (kind) {
            case Kind::Seg: segment.emplace(values, operation); return segment->buildLine();
            case Kind::Lazy: lazy.emplace(values); return lazy->buildLine();
            case Kind::Fen: fen.emplace(values); return fen->buildLine();
            case Kind::Rfen: rfen.emplace(values); return rfen->buildLine();
            case Kind::Sparse: sparse.emplace(values); return sparse->buildLine();
            case Kind::Sqrt: sqrt.emplace(values, block); return sqrt->buildLine();
            case Kind::Persist: persist.emplace(values); return persist->buildLine();
        }
        throw logic_error("Invalid structure");
    }
    Report describe(Kind kind, Span span, int version = -1) {
        switch (kind) {
            case Kind::Seg: {
                Answer answer = segment->query(span);
                return {labels[static_cast<int>(segment->operation)] + "=" + to_string(answer.value) + " visited=" + to_string(answer.visited), {answer.value}};
            }
            case Kind::Lazy: {
                LazyAnswer answer = lazy->query(span);
                return {answer.value.text() + " visited=" + to_string(answer.counts.visited) + " pushes=" + to_string(answer.counts.pushes), {answer.value.sum, answer.value.minimum, answer.value.maximum}};
            }
            case Kind::Fen: { Answer answer = fen->bit.range(span); return {measured(answer), {answer.value}}; }
            case Kind::Rfen: { Answer answer = rfen->query(span); return {measured(answer), {answer.value}}; }
            case Kind::Sparse: {
                SparseTable::Result answer = sparse->query(span);
                return {answer.text(), {answer.minimum, answer.maximum}};
            }
            case Kind::Sqrt: {
                BlockAnswer answer = sqrt->query(span);
                return {"sum=" + to_string(answer.sum) + " whole=" + to_string(answer.whole) + " cells=" + to_string(answer.cells), {answer.sum}};
            }
            case Kind::Persist: {
                if (version < 0) version = static_cast<int>(persist->positions.roots.size()) - 1;
                Answer answer = persist->positions.query(version, span);
                return {measured(answer), {answer.value}};
            }
        }
        throw logic_error("Invalid structure");
    }
    Lines dump(Kind kind) const {
        switch (kind) {
            case Kind::Seg: return segment->dump();
            case Kind::Lazy: return lazy->dump();
            case Kind::Fen: return fen->dump();
            case Kind::Rfen: return rfen->dump();
            case Kind::Sparse: return sparse->dump();
            case Kind::Sqrt: return sqrt->dump();
            case Kind::Persist: throw logic_error("PERSIST has no DUMP");
        }
        throw logic_error("Invalid structure");
    }
    Lines check(Span span) {
        Aggregate expected = direct(values, span);
        Integer common = 0;
        for (int index = span.left; index <= span.right; ++index) common = gcd(common, values[index]);
        Lines rows{"CHECK " + to_string(span.left) + " " + to_string(span.right) + " " + expected.text() + " gcd=" + to_string(common)};
        int ok = 0, different = 0;
        for (int index = 0; index < 7; ++index) {
            Kind kind = static_cast<Kind>(index);
            if (!built(kind)) continue;
            Values comparison{expected.sum};
            if (kind == Kind::Seg) comparison = {array<Integer, 4>{expected.sum, expected.minimum, expected.maximum, common}[static_cast<int>(segment->operation)]};
            else if (kind == Kind::Lazy) comparison = {expected.sum, expected.minimum, expected.maximum};
            else if (kind == Kind::Sparse) comparison = {expected.minimum, expected.maximum};
            Report report = describe(kind, span);
            bool matches = report.values == comparison;
            if (matches) ++ok; else ++different;
            string prefix = kind == Kind::Persist ? "version=" + to_string(persist->positions.roots.size() - 1) + " " : "";
            rows.push_back(names[index] + (matches ? " OK " : " DIFF ") + prefix + report.text);
        }
        rows.push_back("RESULT ok=" + to_string(ok) + " diff=" + to_string(different));
        return rows;
    }
    void change(Span span, Integer value, bool assignment = false) {
        for (int index = span.left; index <= span.right; ++index) values[index] = assignment ? value : values[index] + value;
    }
    static Values arguments(const vector<string>& words, size_t start) {
        Values result;
        for (size_t index = start; index < words.size(); ++index) result.push_back(stoll(words[index]));
        return result;
    }
public:
    explicit Laboratory(Values source) : values(source), original(move(source)) {}
    Lines execute(const string& line) {
        istringstream input(line);
        vector<string> words;
        for (string word; input >> word;) words.push_back(move(word));
        const string& command = words[0];
        if (command == "LOAD") {
            int removed = 0;
            for (int index = 0; index < 7; ++index) removed += built(static_cast<Kind>(index));
            values = arguments(words, 1); original = values;
            segment.reset(); lazy.reset(); fen.reset(); rfen.reset(); sparse.reset(); sqrt.reset(); persist.reset();
            return {"LOAD n=" + to_string(values.size()) + " removed=" + to_string(removed)};
        }
        if (command == "RESET") {
            values = original;
            Operation operation = segment ? segment->operation : Operation::Sum;
            int block = sqrt ? sqrt->block : 1, rebuilt = 0;
            for (int index = 0; index < 7; ++index) {
                Kind kind = static_cast<Kind>(index);
                if (built(kind)) { build(kind, operation, block); ++rebuilt; }
            }
            return {"RESET rebuilt=" + to_string(rebuilt)};
        }
        if (command == "ARRAY" || command == "CHECK") {
            Span span = checkRange(stoll(words[1]), stoll(words[2]));
            return command == "CHECK" ? check(span) : Lines{line + " " + joined(slice(values, span.left, span.right + 1))};
        }
        if (command == "MO") {
            vector<Span> ranges;
            for (size_t index = 1; index < words.size(); index += 2) ranges.push_back(checkRange(stoll(words[index]), stoll(words[index + 1])));
            return mo(values, ranges);
        }
        const string& action = words[1];
        if (command == "GRID") {
            Values args = arguments(words, 2);
            if (action == "BUILD") {
                int h = static_cast<int>(args[0]), w = static_cast<int>(args[1]), count = static_cast<int>(args.size()) - 2;
                if (count != h * w) throw CommandError("BAD COUNT " + to_string(count) + " " + to_string(h * w));
                Values cells = slice(args, 2, static_cast<int>(args.size()));
                grid.emplace(h, w, cells);
                return {"GRID BUILD rows=" + to_string(h) + " cols=" + to_string(w) + " total=" + to_string(accumulate(cells.begin(), cells.end(), Integer{0}))};
            }
            if (!grid) throw CommandError("NOT BUILT GRID");
            if (action == "DUMP") return grid->dump();
            int row = static_cast<int>(args[0]), column = static_cast<int>(args[1]);
            checkCell(row, column);
            if (action == "ADD") return {line + " visited=" + to_string(grid->add(row, column, args[2]))};
            int bottom = static_cast<int>(args[2]), right = static_cast<int>(args[3]);
            checkCell(bottom, right);
            if (row > bottom || column > right) throw CommandError("BAD RECT " + joined(args));
            return {line + " " + measured(grid->query(row, column, bottom, right))};
        }
        auto found = find(names.begin(), names.end(), command);
        Kind kind = static_cast<Kind>(found - names.begin());
        if (action == "BUILD") {
            Operation operation = Operation::Sum;
            int block = 1;
            if (kind == Kind::Seg) {
                auto match = find(operations.begin(), operations.end(), words[2]);
                if (match == operations.end()) throw CommandError("BAD OP " + words[2]);
                operation = static_cast<Operation>(match - operations.begin());
            } else if (kind == Kind::Sqrt) {
                block = words.size() == 3 ? stoi(words[2]) : integerSqrt(static_cast<int>(values.size()));
                if (block > static_cast<int>(values.size())) throw CommandError("BAD BLOCK " + to_string(block));
            }
            return {build(kind, operation, block)};
        }
        if (!built(kind)) throw CommandError("NOT BUILT " + command);
        if (action == "DUMP") return dump(kind);
        Values args = arguments(words, 2);
        if (kind == Kind::Persist) {
            if (action == "NODES") return {persist->nodeLine()};
            if (action == "KTH") {
                Span span = checkRange(args[0], args[1]);
                Integer k = args[2];
                if (k < 1 || k > span.right - span.left + 1) throw CommandError("BAD K " + to_string(k));
                Answer answer = persist->kth(span, static_cast<int>(k));
                return {line + " value=" + to_string(answer.value) + " visited=" + to_string(answer.visited)};
            }
            int version = checkVersion(args[0]);
            if (action == "SET") {
                int index = checkIndex(args[1]), next = static_cast<int>(persist->positions.roots.size());
                int created = persist->positions.fork(version, index, args[2]);
                return {line + " version=" + to_string(next) + " created=" + to_string(created)};
            }
            Span span = checkRange(args[1], args[2]);
            return {line + " " + describe(kind, span, version).text};
        }
        if (kind == Kind::Fen && action == "LOWER") {
            auto negative = find_if(fen->values.begin(), fen->values.end(), [](Integer value) { return value < 0; });
            if (negative != fen->values.end()) throw CommandError("NEGATIVE " + to_string(negative - fen->values.begin()));
            Answer answer = fen->bit.lower(args[0]);
            return {line + " index=" + (answer.value < 0 ? "none" : to_string(answer.value)) + " visited=" + to_string(answer.visited)};
        }
        if (kind == Kind::Seg && action == "UPDATE") {
            int index = checkIndex(args[0]), visited = segment->update(index, args[1]);
            values[index] = args[1];
            return {line + " root=" + to_string(segment->root()) + " visited=" + to_string(visited)};
        }
        if (kind == Kind::Fen && (action == "ADD" || action == "PREFIX")) {
            int index = checkIndex(args[0]);
            if (action == "PREFIX") return {line + " " + measured(fen->bit.prefix(index + 1))};
            int visited = fen->add(index, args[1]);
            values[index] += args[1];
            return {line + " visited=" + to_string(visited)};
        }
        Span span = checkRange(args[0], args[1]);
        if (action == "ADD" || action == "ASSIGN") {
            Integer value = args[2];
            bool assignment = action == "ASSIGN";
            string details;
            if (kind == Kind::Lazy) {
                Counts counts = lazy->update(span, value, assignment);
                details = "visited=" + to_string(counts.visited) + " covered=" + to_string(counts.covered) + " pushes=" + to_string(counts.pushes);
            } else if (kind == Kind::Rfen) details = "visited=" + to_string(rfen->add(span, value));
            else {
                BlockAnswer answer = sqrt->add(span, value);
                details = "whole=" + to_string(answer.whole) + " cells=" + to_string(answer.cells);
            }
            change(span, value, assignment);
            return {line + " " + details};
        }
        return {line + " " + describe(kind, span).text};
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int size, commands;
    cin >> size;
    Values values(size);
    for (Integer& value : values) cin >> value;
    cin >> commands;
    Laboratory laboratory(move(values));
    string line;
    getline(cin, line);
    for (int index = 0; index < commands; ++index) {
        getline(cin, line);
        if (!line.empty() && line.back() == '\r') line.pop_back();
        try { for (const string& row : laboratory.execute(line)) cout << row << '\n'; }
        catch (const CommandError& error) { cout << "ERROR " << error.what() << '\n'; }
    }
}
