#include <iostream>
#include <string>
#include <vector>
#include <array>
#include <algorithm>
#include <map>
#include <sstream>

int main() {
    const std::array<std::string, 13> lines = {"date,region,product,quantity,unit_price", "2026-04-01,north,notebook,10,200",
        "2026-04-01,east,marker,6,150", "2026-04-01,south,eraser,25,80", "2026-04-02,west,stapler,4,600",
        "2026-04-02,north,marker,8,150", "2026-04-02,east,notebook,9,200", "2026-04-03,south,stapler,3,600",
        "2026-04-03,west,eraser,15,80", "2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600",
        "2026-04-04,south,notebook,6,200", "2026-04-04,west,marker,8,150"};
    std::map<std::string, int> regions, products, days;
    int total = 0;
    for (int i = 1; i < 13; i++) {
        std::istringstream input(lines[i]);
        std::array<std::string, 5> fields;
        for (std::string &field : fields)
            std::getline(input, field, ',');
        int quantity = std::stoi(fields[3]), amount = quantity * std::stoi(fields[4]);
        total += amount;
        regions[fields[1]] += amount;
        products[fields[2]] += quantity;
        days[fields[0]] += amount;
    }
    std::vector<std::pair<std::string, int>> ranked(regions.begin(), regions.end());
    std::sort(ranked.begin(), ranked.end(), [](const std::pair<std::string, int> &a, const std::pair<std::string,
        int> &b) {
        return a.second != b.second ? a.second > b.second : a.first < b.first;
    });
    std::cout << "total: " << total << '\n';
    for (const std::pair<std::string, int> &r : ranked)
        std::cout << r.first << ": " << r.second << '\n';
    for (const std::pair<const std::string, int> &p : products)
        std::cout << p.first << ": " << p.second << '\n';
    std::string best;
    int best_total = -1;
    for (const std::pair<const std::string, int> &day : days)
        if (day.second > best_total) {
            best = day.first;
            best_total = day.second;
        }
    std::cout << "best day: " << best << " (" << best_total << ")\n";
}
