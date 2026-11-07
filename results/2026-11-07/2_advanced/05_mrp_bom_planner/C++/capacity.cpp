#include "mrp.hpp"
#include <algorithm>

Centers readCenters(Lines& errors) {
    Centers centers;
    for (const Row& row : readRows("workcenters.csv")) {
        const Lines& f = row.fields; Integer minutes = std::stoll(f[1]), efficiency = std::stoll(f[2]); std::string error;
        if (centers.count(f[0])) error = "duplicate center " + f[0];
        else if (efficiency < 50 || efficiency > 150) error = "bad efficiency " + f[2];
        if (!error.empty()) inputError(errors, "workcenters.csv", row.line, error);
        else centers.emplace(f[0], Center{f[0], minutes, efficiency, minutes * efficiency / 100, f[3]});
    }
    return centers;
}
Routings readRoutings(const Items& items, const Centers& centers, const Bom& bom, Lines& errors) {
    Routings routings;
    for (const Row& row : readRows("routings.csv")) {
        const Lines& f = row.fields; int number = std::stoi(f[1]); Integer run = std::stoll(f[4]); std::string error;
        if (!items.count(f[0])) error = "unknown item " + f[0];
        else if (!centers.count(f[2])) error = "unknown center " + f[2];
        else if (!bom.manufactured(f[0])) error = "purchased item " + f[0];
        else if (run < 1) error = "bad run time " + f[4];
        else if (routings.count(f[0]) && std::any_of(routings.at(f[0]).begin(), routings.at(f[0]).end(), [&](const Operation& old) { return old.number == number; })) error = "duplicate " + f[0] + " operation " + f[1];
        if (!error.empty()) inputError(errors, "routings.csv", row.line, error);
        else routings[f[0]].push_back({f[0], f[2], number, std::stoll(f[3]), run});
    }
    for (auto& [id, operations] : routings) std::sort(operations.begin(), operations.end(), [](const Operation& a, const Operation& b) { return a.number < b.number; });
    return routings;
}
int operationWeek(int receipt, int lead, int index, int count) { return std::max(receipt - lead + index * lead / count, 1); }
Values levelLoads(const Values& loads, Integer available) {
    Values leveled(loads.size()); Integer carry = 0;
    for (std::size_t week = loads.size() - 1; week > 1; --week) { Integer total = loads[week] + carry; leveled[week] = std::min(total, available); carry = total - leveled[week]; }
    leveled[1] = loads[1] + carry; return leveled;
}
