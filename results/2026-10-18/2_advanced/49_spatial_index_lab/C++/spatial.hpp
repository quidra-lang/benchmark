#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <functional>
#include <map>
#include <memory>
#include <numeric>
#include <queue>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Integer = std::int64_t;
using Lines = std::vector<std::string>;
struct Box {
    Integer x1 = 0, y1 = 0, x2 = 0, y2 = 0;
};
struct Point {
    int id = 0;
    Integer x = 0, y = 0;
    Box box() const {
        return {x, y, x, y};
    }
};
struct Object {
    int id = 0;
    Box box;
};
struct Params {
    int world = 0, bucket = 0, maximum = 0, minimum = 0, grid = 0;
};
struct Command {
    std::string name;
    std::vector<Integer> values;
};
struct Input {
    std::vector<Point> points;
    std::vector<Object> rectangles;
    Params params;
    std::vector<Command> commands;
};
Input read_input();
bool key_less(Point a, Point b, int axis);
struct KDNode {
    Point point;
    int depth;
    std::unique_ptr<KDNode> left, right;
};
std::unique_ptr<KDNode> kd_build(std::vector<Point> points, int depth = 0);
void kd_insert(std::unique_ptr<KDNode> &node, Point point, int depth = 0);
Point kd_minimum(const KDNode &node, int axis);
void kd_delete(std::unique_ptr<KDNode> &node, Point point);
struct QuadNode {
    Integer x = 0, y = 0, size = 0;
    std::vector<Point> points;
    std::array<std::unique_ptr<QuadNode>, 4> children;
    bool leaf() const {
        return !children[0];
    }
};
int destination(const QuadNode &node, Point point);
void quad_insert(QuadNode &node, Point point, int bucket);
void quad_delete(QuadNode &node, Point point, int bucket);
Integer area(Box box);
Box mbr(Box a, Box b);
Integer enlargement(Box a, Box b);
bool intersects(Box a, Box b);
bool contains(Box a, Box b);
Integer overlap(Box a, Box b);
Integer distance(Integer x, Integer y, Box box);
struct RNode;
struct Entry {
    Box box;
    int id = 0, number = 0;
    std::shared_ptr<RNode> child;
};
struct RNode : std::enable_shared_from_this<RNode> {
    int level = 0;
    RNode *parent = nullptr;
    std::vector<Entry> entries;
    Box box() const;
};
struct RTree {
    std::shared_ptr<RNode> root;
    int maximum, minimum;
    RTree(int maximum, int minimum);
    void insert(Entry entry, int level = 0);
    void erase(Point point);
    void bulk(std::vector<Entry> entries);
    std::shared_ptr<RNode> split(const std::shared_ptr<RNode> &node);
    std::shared_ptr<RNode> leaf(Point point) const;
};
struct Grid {
    int world, side, dimension;
    std::vector<std::vector<Point>> cells;
    Grid(int world, int side);
    void insert(Point point);
    void erase(Point point);
};
std::string fraction(Integer numerator, Integer denominator);
std::string ids(const std::vector<int> &values);
void write_lines(const std::string &name, const Lines &lines);
