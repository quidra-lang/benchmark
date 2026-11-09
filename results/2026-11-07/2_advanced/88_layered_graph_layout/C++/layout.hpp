#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <limits>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Order = std::vector<int>;
using Orders = std::vector<Order>;
using Lines = std::vector<std::string>;
template <class... Parts> std::string text(const Parts &...parts) {
    std::ostringstream out;
    (out << ... << parts);
    return out.str();
}
std::string join(const Lines &items, const std::string &separator = " ");
Lines readLines(const std::string &path);
Lines words(const std::string &line);
void append(Lines &to, const Lines &from);
enum class Direction { TB, BT, LR, RL };
struct Settings {
    bool coffman = false, promotion = false, median = false, sifting = false, reduce = false;
    int width = 4, sweeps = 12, nodeSep = 2, dummySep = 1, layerGap = 3, restarts = 0;
    std::int64_t seed = 1;
    Direction direction = Direction::TB;
    bool set(const std::string &name, const std::string &value);
    Lines values() const;
};
extern const Lines settingNames;
const char *directionName(Direction direction);
bool vertical(Direction direction);
struct NodeData {
    int id;
    std::string label;
};
struct RawEdge {
    int from, to;
};
struct Block {
    std::string name;
    Settings settings;
    std::vector<NodeData> nodes;
    std::vector<RawEdge> edges;
    bool hasPath = false;
    int pathFrom = 0, pathTo = 0, selfLoops = 0, duplicates = 0, errorLine = 0;
    std::string error;
};
std::vector<Block> readBlocks();
struct Cell {
    int row, column;
};
struct Pixel {
    unsigned char lines = 0;
    char arrow = 0, box = 0;
    bool highlighted = false;
};
struct Canvas {
    int mainLength = 0, secondaryLength = 0, rows = 0, columns = 0;
    Direction direction = Direction::TB;
    std::vector<Pixel> cells;
    Canvas() = default;
    Canvas(int mainLength, int secondaryLength, Direction direction);
    Cell map(int main, int secondary) const;
    Pixel &at(Cell cell);
    const Pixel &at(Cell cell) const;
    void line(int main, int secondary, unsigned char kind);
    void mainLine(int main, int secondary);
    void secondaryLine(int main, int secondary);
    void segment(int start, int gap, int upper, int lower, int offset);
    void highlight(Cell from, Cell to);
    int crossingCells() const;
    char character(Cell cell) const;
    Lines drawing(const std::string &name) const;
};
struct Edge {
    int from = 0, to = 0, upper = 0, lower = 0;
    bool reversed = false, transitive = false;
    Order chain, segments;
    int span = 0, crossings = 0, bends = 0, length = 0;
    std::vector<Cell> route;
};
struct Vertex {
    std::string name;
    int layer = 0, width = 1, left = 0, right = 0, x = 0;
    Order upper, lower;
};
struct Segment {
    int upper, lower, edge, gap, offset = 0;
};
struct Promotion {
    int round, node, difference;
};
struct LayeringResult {
    Order height, labels;
    int dummiesBefore = 0, rounds = 0;
    std::vector<Promotion> promotions;
};
struct Sweep {
    int run, number, moved, swaps, crossings;
};
struct Sift {
    int round, moves, crossings;
};
struct BKVariant {
    Order root, aligned;
    int blocks = 0, width = 0, low = 0, high = 0;
};
struct Coordinates {
    std::set<std::pair<int, int>> marked;
    std::array<BKVariant, 4> variants;
    int smallest = 0;
};
extern const std::array<const char *, 4> variantNames;
struct Layout {
    const Block *block = nullptr;
    int nodes = 0;
    std::vector<Vertex> vertices;
    std::vector<Edge> edges;
    std::vector<Segment> segments;
    Orders gaps, orders, scc;
    Order acyclic;
    LayeringResult layering;
    Coordinates coordinates;
    std::vector<Sweep> sweeps;
    std::vector<Sift> sifts;
    int bestRun = 0, bestSweep = 0, initialCrossings = 0, adoptedCrossings = 0, finalCrossings = 0,
        brute = 0;
    int sources = 0, sinks = 0, isolated = 0, components = 0;
    Order tracks, gapWidths, bandStarts, thickness, path;
    int mainLength = 0, secondaryLength = 0;
    Canvas canvas;
};
Order acyclic(int nodes, const std::vector<Edge> &edges);
LayeringResult assignLayers(const Orders &predecessors, const Orders &successors,
                            const Settings &settings);
Order positions(const Orders &orders, int count);
int gapCrossings(const std::vector<Segment> &segments, const Order &indices, const Order &positions,
                 int width);
int totalCrossings(const Layout &layout, const Orders &orders);
int bruteCrossings(Layout &layout, const Orders &orders, bool countEdges);
int adjacentCost(const Layout &layout, int left, int right, const Order &positions);
int floorDiv(int a, int b);
Coordinates coordinates(Layout &layout);
