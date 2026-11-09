#include "segments.hpp"
#include <fstream>
#include <stdexcept>

Lines readLines(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("cannot read " + path);
    Lines result;
    std::string line;
    while (std::getline(file, line)) result.push_back(line);
    if (file.bad()) throw std::runtime_error("cannot read " + path);
    return result;
}
Lines split(const std::string& value, char separator) {
    Lines result;
    std::istringstream stream(value);
    std::string part;
    while (std::getline(stream, part, separator)) result.push_back(part);
    return result;
}
Params readParams(const std::string& path) {
    std::map<std::string, Lines> entries;
    for (const std::string& line : readLines(path)) {
        Lines words = split(line, ' ');
        entries[words.front()] = Lines(words.begin() + 1, words.end());
    }
    Params result{
        std::stoi(entries.at("REFERENCE_DAY")[0]), std::stoi(entries.at("SNAPSHOT_DAY")[0]), std::stoi(entries.at("OUTCOME_DAYS")[0]),
        std::stoi(entries.at("K_RANGE")[0]), std::stoi(entries.at("K_RANGE")[1]), entries.at("METHODS"),
        std::stoi(entries.at("RESTARTS")[0]), std::stoi(entries.at("MAX_ITERATIONS")[0]), std::stoll(entries.at("SEED")[0]),
        std::stoi(entries.at("SUBSAMPLES")[0]), std::stoi(entries.at("SUBSAMPLE_PERCENT")[0]), std::stod(entries.at("OUTLIER_SD")[0]),
        std::stoi(entries.at("OVERDUE_FACTOR")[0]), {}, std::stoi(entries.at("TOP_CATEGORIES")[0]), std::stoi(entries.at("TOP_CUSTOMERS")[0]),
        std::stoi(entries.at("PERIOD_DAYS")[0]), std::stoi(entries.at("PERIODS")[0])};
    for (const std::string& word : entries.at("ORDER_BINS")) result.orderBins.push_back(std::stoll(word));
    return result;
}
TransactionData readTransactions(const std::string& path) {
    Lines lines = readLines(path);
    TransactionData result;
    std::set<std::string> seen;
    for (std::size_t i = 1; i < lines.size(); ++i) {
        Lines fields = split(lines[i], ',');
        Transaction row{fields[0], std::stoi(fields[1]), fields[2], fields[3], std::stoll(fields[4])};
        ++result.rowCount;
        result.customers.insert(row.customer);
        if (!seen.insert(lines[i]).second) ++result.duplicates;
        else if (row.amount == 0) ++result.free;
        else result.validRows.push_back(std::move(row));
    }
    return result;
}
std::vector<Order> groupOrders(const std::vector<Transaction>& rows, int first, int last) {
    std::vector<Order> orders;
    std::map<std::string, std::size_t> positions;
    for (const Transaction& row : rows) {
        if (row.day < first || row.day > last) continue;
        std::map<std::string, std::size_t>::const_iterator found = positions.find(row.orderId);
        if (found == positions.end()) {
            positions.emplace(row.orderId, orders.size());
            orders.push_back({row.orderId, row.customer, row.day, 0, {}});
        }
        Order& order = orders[positions.at(row.orderId)];
        order.day = std::min(order.day, row.day);
        order.net += row.amount;
        order.rows.push_back(&row);
    }
    return orders;
}
CustomerOrders ordersByCustomer(const std::vector<Order>& orders, bool validOnly) {
    CustomerOrders result;
    for (const Order& order : orders) if (!validOnly || order.net > 0) result[order.customer].push_back(&order);
    return result;
}
