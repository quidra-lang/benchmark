#pragma once
#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

using Integer = std::int64_t;
using Lines = std::vector<std::string>;
using Values = std::vector<Integer>;
struct Row { int line; Lines fields; };
Lines split(const std::string& text, char delimiter);
std::string join(const Lines& values, const std::string& delimiter = " ");
Lines readLines(const std::string& name);
std::vector<Row> readRows(const std::string& name);
void inputError(Lines& errors, const std::string& file, int line, const std::string& message);
struct Item {
    std::string id;
    int lead;
    std::string rule;
    Integer first, second, safety, onHand, material, labor;
    std::string description;
    std::string lotLabel() const;
};
using Items = std::map<std::string, Item>;
Items readItems(Lines& errors);
struct Edge {
    std::string parent, child;
    Integer quantity, scrap;
    Integer need(Integer units) const;
};
struct Bom {
    std::map<std::string, std::vector<Edge>> children, parents;
    bool manufactured(const std::string& item) const;
    bool topLevel(const std::string& item) const;
    std::optional<Lines> path(const std::string& start, const std::string& goal, std::set<std::string>& visited) const;
    int lowLevel(const std::string& item, std::map<std::string, int>& codes) const;
    int cumulative(const std::string& item, const Items& items, std::map<std::string, int>& times) const;
};
Bom readBom(const Items& items, Lines& errors);
Integer lotSize(const Item& item, int week, Integer projected, const Values& receipts, const Values& gross, int horizon);
struct Center { std::string id; Integer minutes, efficiency, available; std::string description; };
struct Operation {
    std::string item, center;
    int number;
    Integer setup, run;
    Integer minutes(Integer units) const { return setup + units * run; }
};
using Centers = std::map<std::string, Center>;
using Routings = std::map<std::string, std::vector<Operation>>;
Centers readCenters(Lines& errors);
Routings readRoutings(const Items& items, const Centers& centers, const Bom& bom, Lines& errors);
int operationWeek(int receipt, int lead, int index, int count);
Values levelLoads(const Values& loads, Integer available);
struct StandardCost { Integer material, labor; Integer total() const { return material + labor; } };
std::map<std::string, StandardCost> standardCosts(const Items& items, const Bom& bom, const Lines& planningOrder);
std::map<std::string, std::string> abcClasses(const std::map<std::string, Integer>& values);
std::string money(Integer cents);
Integer percentage(Integer part, Integer whole);
std::string tableRow(const std::string& label, const Values& values, int width);
void writeReport(const std::string& name, const Lines& lines);
