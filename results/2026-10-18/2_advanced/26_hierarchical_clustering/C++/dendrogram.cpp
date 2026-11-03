#include "clustering.hpp"

std::vector<std::pair<int, int>> orderedChildren(const std::vector<Merge>& merges, int count) {
    Indices minimum(count);
    std::iota(minimum.begin(), minimum.end(), 0);
    std::vector<std::pair<int, int>> children;
    for (const Merge& merge : merges) {
        children.push_back(minimum[merge.a] < minimum[merge.b] ? std::pair<int, int>{merge.a, merge.b} : std::pair<int, int>{merge.b, merge.a});
        minimum.push_back(std::min(minimum[merge.a], minimum[merge.b]));
    }
    return children;
}
Indices leafOrder(const std::vector<std::pair<int, int>>& children, int count) {
    Indices order, pending{count + static_cast<int>(children.size()) - 1};
    while (!pending.empty()) {
        int node = pending.back(); pending.pop_back();
        if (node < count) order.push_back(node);
        else { pending.push_back(children[node - count].second); pending.push_back(children[node - count].first); }
    }
    return order;
}
int columnPosition(double height, double maximum, int width) {
    double position = std::floor(height / maximum * width);
    return position > width ? width + 1 : static_cast<int>(position);
}
Lines dendrogramRows(const std::vector<Merge>& merges, const std::vector<std::pair<int, int>>& children, const Indices& order, const Lines& ids, const Lines& labels, double maximum, const Indices& cuts, int width) {
    int count = static_cast<int>(order.size());
    std::vector<Indices> grid(count, Indices(width + 1, 0));
    Indices anchor(2 * count - 1, 0), columns;
    for (int row = 0; row < count; ++row) anchor[order[row]] = row;
    for (int x : cuts) if (x <= width) for (int row = 0; row < count; ++row) grid[row][x] = std::max(grid[row][x], 1);
    for (const Merge& merge : merges) columns.push_back(columnPosition(merge.height, maximum, width));
    for (std::size_t step = 0; step < merges.size(); ++step) {
        int upper = children[step].first, lower = children[step].second, x = columns[step];
        grid[anchor[upper]][x] = grid[anchor[lower]][x] = 4;
        for (int row = anchor[upper] + 1; row < anchor[lower]; ++row) grid[row][x] = std::max(grid[row][x], 3);
        for (int child : {upper, lower}) {
            int start = child < count ? 0 : columns[child - count] + 1;
            for (int position = start; position < x; ++position) grid[anchor[child]][position] = std::max(grid[anchor[child]][position], 2);
        }
        anchor[count + step] = (anchor[upper] + anchor[lower]) / 2;
    }
    std::size_t idWidth = 0, labelWidth = 0;
    for (const std::string& id : ids) idWidth = std::max(idWidth, id.size());
    for (const std::string& label : labels) labelWidth = std::max(labelWidth, label.size());
    Lines rows;
    const std::string marks = " :-|+";
    for (int row = 0; row < count; ++row) {
        int leaf = order[row];
        std::string line = ids[leaf] + std::string(idWidth - ids[leaf].size(), ' ') + " " + labels[leaf] + std::string(labelWidth - labels[leaf].size(), ' ') + " ";
        for (int mark : grid[row]) line += marks[mark];
        line.erase(line.find_last_not_of(' ') + 1);
        rows.push_back(line);
    }
    std::string scale(idWidth + labelWidth + 2, ' ');
    for (int x = 0; x <= width; ++x) scale += x % 10 == 0 ? '+' : '-';
    rows.push_back(scale);
    return rows;
}
