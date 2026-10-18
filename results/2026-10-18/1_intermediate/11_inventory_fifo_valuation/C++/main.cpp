#include <algorithm>
#include <iomanip>
#include <iostream>
#include <map>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using namespace std;

const vector<string> categories = {
    "received", "returned", "adjusted-in", "adjusted-out",
    "shipped", "written-down", "expired", "recalled"
};

using Amount = long long;

Amount number(const string& text) {
    return stoll(text);
}

Amount cents(string text) {
    text.erase(remove(text.begin(), text.end(), '.'), text.end());
    return stoll(text);
}

string money(Amount amount) {
    ostringstream out;
    if (amount < 0) {
        out << '-';
        amount = -amount;
    }
    out << amount / 100 << '.' << setfill('0') << setw(2) << amount % 100;
    return out.str();
}

string signedQuantity(Amount quantity) {
    return (quantity > 0 ? "+" : "") + to_string(quantity);
}

string signedMoney(Amount amount) {
    return (amount > 0 ? "+" : "") + money(amount);
}

string margin(Amount profit, Amount revenue) {
    if (revenue == 0) {
        return "n/a";
    }
    Amount tenths = (profit < 0 ? -profit : profit) * 1000 / revenue;
    return (profit < 0 && tenths > 0 ? "-" : "") +
           to_string(tenths / 10) + "." + to_string(tenths % 10) + "%";
}

struct CardEntry {
    Amount day;
    string kind;
    string warehouse;
    Amount quantity;
    Amount value;
};

struct Item {
    string code;
    string name;
    Amount level;
    optional<Amount> lastCost;
    vector<CardEntry> card;
};

struct Lot {
    int number;
    string item;
    string warehouse;
    string kind;
    Amount day;
    Amount initialQuantity;
    Amount initialCost;
    Amount removed = 0;
};

struct StockLot {
    int lot;
    Amount quantity;
    Amount cost;
};

struct Part {
    int lot;
    Amount quantity;
    Amount cost;
};

struct Order {
    int number;
    string warehouse;
    string item;
    Amount day;
    Amount price;
    Amount ordered;
    Amount shipped = 0;
    Amount backorder = 0;
    Amount cancelled = 0;
    Amount returned = 0;
    Amount revenue = 0;
    Amount cogs = 0;
    vector<Part> issues;
};

struct Total {
    Amount quantity = 0;
    Amount value = 0;
};

struct Sale {
    Amount quantity = 0;
    Amount revenue = 0;
    Amount cogs = 0;
};

class Inventory {
    Amount day = 1;
    map<string, map<string, map<int, StockLot>>> stock;
    map<string, Item> items;
    vector<Lot> lots;
    vector<Order> orders;
    map<string, Total> totals;
    vector<string> output;

    template<class... Args>
    void emit(int indent, const Args&... parts) {
        ostringstream out;
        out << string(indent, ' ');
        bool first = true;
        ((out << (exchange(first, false) ? "" : " ") << parts), ...);
        output.push_back(out.str());
    }

    void error(const string& reason) {
        throw runtime_error(reason);
    }

    void warehouse(const string& code) {
        if (stock.find(code) == stock.end()) {
            error("unknown warehouse " + code);
        }
    }

    Item& item(const string& code) {
        auto found = items.find(code);
        if (found == items.end()) {
            error("unknown item " + code);
        }
        return found->second;
    }

    Item& pair(const string& warehouseCode, const string& code) {
        warehouse(warehouseCode);
        return item(code);
    }

    Order& order(const string& text) {
        Amount id = number(text);
        if (id < 1 || id > static_cast<Amount>(orders.size())) {
            error("unknown order " + text);
        }
        return orders[static_cast<size_t>(id - 1)];
    }

    Lot& lot(const string& text) {
        Amount id = number(text);
        if (id < 1 || id > static_cast<Amount>(lots.size())) {
            error("unknown lot " + text);
        }
        return lots[static_cast<size_t>(id - 1)];
    }

    void requireQuantity(Amount quantity) {
        if (quantity == 0) {
            error("invalid quantity");
        }
    }

    const map<int, StockLot>& holdings(const string& warehouseCode, const string& code) const {
        static const map<int, StockLot> empty;
        auto w = stock.find(warehouseCode);
        if (w == stock.end()) {
            return empty;
        }
        auto entry = w->second.find(code);
        return entry == w->second.end() ? empty : entry->second;
    }

    vector<int> fifo(const string& warehouseCode, const string& code) const {
        vector<int> ids;
        for (const auto& [id, current] : holdings(warehouseCode, code)) {
            ids.push_back(id);
        }
        sort(ids.begin(), ids.end(), [&](int a, int b) {
            if (lots[a - 1].day != lots[b - 1].day) {
                return lots[a - 1].day < lots[b - 1].day;
            }
            return a < b;
        });
        return ids;
    }

    Amount quantity(const string& warehouseCode, const string& code) const {
        Amount result = 0;
        for (const auto& [id, current] : holdings(warehouseCode, code)) {
            result += current.quantity;
        }
        return result;
    }

    Amount totalQuantity(const string& code) const {
        Amount result = 0;
        for (const auto& [w, contents] : stock) {
            result += quantity(w, code);
        }
        return result;
    }

    Amount backorder(const string& code) const {
        Amount result = 0;
        for (const Order& current : orders) {
            if (current.item == code) {
                result += current.backorder;
            }
        }
        return result;
    }

    Total allStocks() const {
        Total result;
        for (const auto& [w, contents] : stock) {
            for (const auto& [code, held] : contents) {
                for (const auto& [id, current] : held) {
                    result.quantity += current.quantity;
                    result.value += current.quantity * current.cost;
                }
            }
        }
        return result;
    }

    void requireStock(const string& warehouseCode, const string& code, Amount needed) {
        Amount available = quantity(warehouseCode, code);
        if (available < needed) {
            error("insufficient stock " + warehouseCode + " " + code + " " + to_string(available));
        }
    }

    void cardEntry(const string& code, const string& kind, const string& w,
                   Amount quantityChange, Amount valueChange) {
        items.at(code).card.push_back({day, kind, w, quantityChange, valueChange});
    }

    void accumulate(const string& category, Amount quantityChange, Amount valueChange) {
        totals[category].quantity += quantityChange;
        totals[category].value += valueChange;
    }

    void addStock(const string& w, int id, Amount quantityChange, Amount cost) {
        StockLot& entry = stock.at(w)[lots[id - 1].item][id];
        if (entry.lot == 0) {
            entry = {id, quantityChange, cost};
        } else {
            entry.quantity += quantityChange;
        }
    }

    int createLot(const string& w, const string& code, Amount receiptDay,
                  Amount q, Amount cost, const string& kind) {
        int id = static_cast<int>(lots.size()) + 1;
        lots.push_back({id, code, w, kind, receiptDay, q, cost, 0});
        addStock(w, id, q, cost);
        return id;
    }

    std::pair<vector<Part>, Amount> issue(const string& w, const string& code, Amount q) {
        vector<Part> parts;
        Amount cost = 0;
        for (int id : fifo(w, code)) {
            if (q == 0) {
                break;
            }
            StockLot& current = stock.at(w).at(code).at(id);
            Amount taken = min(q, current.quantity);
            parts.push_back({id, taken, current.cost});
            cost += taken * current.cost;
            current.quantity -= taken;
            q -= taken;
            if (current.quantity == 0) {
                stock.at(w).at(code).erase(id);
            }
        }
        return {parts, cost};
    }

    Amount fulfil(Order& current, Amount q, const string& kind) {
        if (q == 0) {
            return 0;
        }
        auto [parts, cost] = issue(current.warehouse, current.item, q);
        current.shipped += q;
        current.backorder -= q;
        current.revenue += q * current.price;
        current.cogs += cost;
        current.issues.insert(current.issues.end(), parts.begin(), parts.end());
        accumulate("shipped", q, cost);
        cardEntry(current.item, kind, current.warehouse, -q, -cost);
        return cost;
    }

    void allocate(const string& w, const string& code) {
        Amount available = quantity(w, code);
        for (Order& current : orders) {
            if (available == 0) {
                break;
            }
            if (current.warehouse != w || current.item != code || current.backorder == 0) {
                continue;
            }
            Amount q = min(available, current.backorder);
            Amount cost = fulfil(current, q, "fill");
            Amount revenue = q * current.price;
            available -= q;
            emit(2, "FILL", "order", current.number, "qty", q,
                 "revenue", money(revenue), "cogs", money(cost),
                 "profit", money(revenue - cost), "backorder", current.backorder);
        }
    }

    void removeParts(const vector<Part>& parts) {
        for (const Part& part : parts) {
            lots[part.lot - 1].removed += part.quantity;
        }
    }

    map<string, Sale> sales() const {
        map<string, Sale> rows;
        for (const Order& current : orders) {
            Sale& row = rows[current.item];
            row.quantity += current.shipped - current.returned;
            row.revenue += current.revenue;
            row.cogs += current.cogs;
        }
        return rows;
    }

    void marginLine(const string& label, const Sale& row) {
        Amount profit = row.revenue - row.cogs;
        emit(2, label, "sold", row.quantity, "revenue", money(row.revenue),
             "cogs", money(row.cogs), "profit", money(profit),
             "margin", margin(profit, row.revenue));
    }

    void agingLine(const string& label, const vector<Amount>& buckets, bool monetary) {
        ostringstream text;
        text << label;
        const vector<string> labels = {"0-30", "31-60", "61-90", "91+"};
        for (size_t i = 0; i < buckets.size(); ++i) {
            text << ' ' << labels[i] << ' '
                 << (monetary ? money(buckets[i]) : to_string(buckets[i]));
        }
        emit(2, text.str());
    }

    void command(const string& cmd, const vector<string>& a) {
        if (cmd == "DAY") {
            Amount next = number(a[0]);
            if (next <= day) {
                error("invalid day " + a[0]);
            }
            day = next;
            emit(0, "DAY", day);

        } else if (cmd == "WAREHOUSE") {
            const string& w = a[0];
            if (stock.find(w) != stock.end()) {
                error("duplicate warehouse " + w);
            }
            stock.emplace(w, map<string, map<int, StockLot>>{});
            emit(0, "WAREHOUSE", w);

        } else if (cmd == "ITEM") {
            const string& code = a[0];
            Amount level = number(a[1]);
            string action = "added";
            auto found = items.find(code);
            if (found != items.end()) {
                found->second.level = level;
                found->second.name = a[2];
                action = "updated";
            } else {
                items.emplace(code, Item{code, a[2], level, nullopt, {}});
            }
            emit(0, "ITEM", code, action, a[2], "level", level);

        } else if (cmd == "RECEIVE") {
            const string& w = a[0];
            const string& code = a[1];
            Item& entry = pair(w, code);
            Amount q = number(a[2]);
            Amount cost = cents(a[3]);
            Amount receiptDay = number(a[4]);
            requireQuantity(q);
            if (receiptDay > day) {
                error("future day " + a[4]);
            }
            int id = createLot(w, code, receiptDay, q, cost, "receive");
            entry.lastCost = cost;
            accumulate("received", q, q * cost);
            cardEntry(code, "receive", w, q, q * cost);
            emit(0, "RECEIVE", w, code, "lot", id, "qty", q, "cost",
                 money(cost), "day", receiptDay, "value", money(q * cost));
            allocate(w, code);

        } else if (cmd == "SHIP") {
            const string& w = a[0];
            const string& code = a[1];
            pair(w, code);
            Amount q = number(a[2]);
            requireQuantity(q);
            int id = static_cast<int>(orders.size()) + 1;
            orders.push_back({id, w, code, day, cents(a[3]), q, 0, q});
            Order& current = orders.back();
            Amount shipped = min(q, quantity(w, code));
            Amount cost = fulfil(current, shipped, "ship");
            emit(0, "SHIP", "order", current.number, w, code, "shipped", shipped,
                 "revenue", money(current.revenue), "cogs", money(cost),
                 "profit", money(current.revenue - cost), "backorder", current.backorder);

        } else if (cmd == "CANCEL") {
            Order& current = order(a[0]);
            if (current.backorder == 0) {
                error("no backorder " + a[0]);
            }
            current.cancelled += current.backorder;
            current.backorder = 0;
            emit(0, "CANCEL", "order", current.number, "qty", current.cancelled);

        } else if (cmd == "TRANSFER") {
            const string& source = a[0];
            const string& destination = a[1];
            const string& code = a[2];
            warehouse(source);
            warehouse(destination);
            if (source == destination) {
                error("same warehouse " + source);
            }
            item(code);
            Amount q = number(a[3]);
            requireQuantity(q);
            requireStock(source, code, q);
            auto [parts, cost] = issue(source, code, q);
            for (const Part& part : parts) {
                addStock(destination, part.lot, part.quantity, part.cost);
            }
            cardEntry(code, "transfer-out", source, -q, -cost);
            cardEntry(code, "transfer-in", destination, q, cost);
            emit(0, "TRANSFER", source, "->", destination, code,
                 "qty", q, "value", money(cost), "lots", parts.size());
            allocate(destination, code);

        } else if (cmd == "ADJUST") {
            const string& w = a[0];
            const string& code = a[1];
            pair(w, code);
            Amount q = number(a[2].substr(1));
            requireQuantity(q);
            if (a[2][0] == '+') {
                Amount cost = cents(a[3]);
                int id = createLot(w, code, day, q, cost, "adjust");
                accumulate("adjusted-in", q, q * cost);
                cardEntry(code, "adjust", w, q, q * cost);
                emit(0, "ADJUST", w, code, "+" + to_string(q),
                     "lot", id, "value", money(q * cost));
                allocate(w, code);
            } else {
                requireStock(w, code, q);
                auto [parts, cost] = issue(w, code, q);
                removeParts(parts);
                accumulate("adjusted-out", q, cost);
                cardEntry(code, "adjust", w, -q, -cost);
                emit(0, "ADJUST", w, code, "-" + to_string(q), "value", money(cost));
            }

        } else if (cmd == "RETURN") {
            Order& current = order(a[0]);
            Amount q = number(a[1]);
            Amount cost = cents(a[2]);
            requireQuantity(q);
            Amount available = current.shipped - current.returned;
            if (q > available) {
                error("return exceeds shipped " + a[0] + " " + to_string(available));
            }
            int id = createLot(current.warehouse, current.item, day, q, cost, "return");
            Amount refund = q * current.price;
            current.returned += q;
            current.revenue -= refund;
            current.cogs -= q * cost;
            accumulate("returned", q, q * cost);
            cardEntry(current.item, "return", current.warehouse, q, q * cost);
            emit(0, "RETURN", "order", current.number, current.warehouse, current.item,
                 "qty", q, "lot", id, "refund", money(refund), "value", money(q * cost));
            allocate(current.warehouse, current.item);

        } else if (cmd == "COUNT") {
            const string& w = a[0];
            const string& code = a[1];
            Item& entry = pair(w, code);
            Amount actual = number(a[2]);
            Amount held = quantity(w, code);
            if (actual == held) {
                emit(0, "COUNT", w, code, "qty", actual, "ok");
            } else if (actual < held) {
                Amount q = held - actual;
                auto [parts, cost] = issue(w, code, q);
                removeParts(parts);
                accumulate("adjusted-out", q, cost);
                cardEntry(code, "count", w, -q, -cost);
                emit(0, "COUNT", w, code, "qty", held, "->", actual,
                     "shortage", q, "value", money(cost));
            } else {
                Amount q = actual - held;
                Amount cost = entry.lastCost.value_or(0);
                int id = createLot(w, code, day, q, cost, "count");
                accumulate("adjusted-in", q, q * cost);
                cardEntry(code, "count", w, q, q * cost);
                emit(0, "COUNT", w, code, "qty", held, "->", actual,
                     "surplus", q, "lot", id, "value", money(q * cost));
                allocate(w, code);
            }

        } else if (cmd == "MARKET") {
            const string& code = a[0];
            item(code);
            Amount price = cents(a[1]);
            Amount changed = 0;
            Amount q = 0;
            Amount loss = 0;
            for (auto& [w, contents] : stock) {
                Amount warehouseLoss = 0;
                auto it = contents.find(code);
                if (it != contents.end()) {
                    for (auto& [id, current] : it->second) {
                        if (current.cost > price) {
                            warehouseLoss += current.quantity * (current.cost - price);
                            changed++;
                            q += current.quantity;
                            current.cost = price;
                        }
                    }
                }
                if (warehouseLoss > 0) {
                    cardEntry(code, "writedown", w, 0, -warehouseLoss);
                }
                loss += warehouseLoss;
            }
            accumulate("written-down", q, loss);
            emit(0, "MARKET", code, "price", money(price),
                 "lots", changed, "qty", q, "loss", money(loss));

        } else if (cmd == "RECALL") {
            Lot& current = lot(a[0]);
            struct Holding {
                string warehouse;
                Amount quantity;
                Amount cost;
            };
            vector<Holding> held;
            for (const auto& [w, contents] : stock) {
                auto it = holdings(w, current.item).find(current.number);
                if (it != holdings(w, current.item).end()) {
                    held.push_back({w, it->second.quantity, it->second.cost});
                }
            }
            if (held.empty()) {
                error("nothing to recall " + a[0]);
            }
            Amount q = 0;
            Amount value = 0;
            for (const Holding& entry : held) {
                q += entry.quantity;
                value += entry.quantity * entry.cost;
                stock.at(entry.warehouse).at(current.item).erase(current.number);
                cardEntry(current.item, "recall", entry.warehouse,
                          -entry.quantity, -entry.quantity * entry.cost);
            }
            current.removed += q;
            accumulate("recalled", q, value);
            emit(0, "RECALL", "lot", current.number, current.item,
                 "qty", q, "value", money(value));
            for (const Holding& entry : held) {
                emit(2, entry.warehouse, "qty", entry.quantity,
                     "value", money(entry.quantity * entry.cost));
            }

        } else if (cmd == "EXPIRE") {
            Amount days = number(a[0]);
            emit(0, "EXPIRE", days);
            Amount totalQ = 0;
            Amount totalValue = 0;
            for (const auto& [code, entry] : items) {
                for (auto& [w, contents] : stock) {
                    auto it = contents.find(code);
                    if (it == contents.end()) {
                        continue;
                    }
                    vector<int> expired;
                    Amount q = 0;
                    Amount value = 0;
                    for (const auto& [id, current] : it->second) {
                        if (day - lots[id - 1].day > days) {
                            expired.push_back(id);
                            q += current.quantity;
                            value += current.quantity * current.cost;
                        }
                    }
                    if (expired.empty()) {
                        continue;
                    }
                    for (int id : expired) {
                        lots[id - 1].removed += it->second.at(id).quantity;
                        it->second.erase(id);
                    }
                    accumulate("expired", q, value);
                    cardEntry(code, "expire", w, -q, -value);
                    totalQ += q;
                    totalValue += value;
                    emit(2, code, w, "lots", expired.size(), "qty", q, "value", money(value));
                }
            }
            emit(2, "total", "qty", totalQ, "value", money(totalValue));

        } else if (cmd == "VALUE" || cmd == "AGING") {
            vector<string> warehouses;
            if (a.empty()) {
                for (const auto& [w, contents] : stock) {
                    warehouses.push_back(w);
                }
            } else {
                warehouse(a[0]);
                warehouses.push_back(a[0]);
            }
            if (cmd == "VALUE") {
                if (a.empty()) {
                    emit(0, "VALUE");
                } else {
                    emit(0, "VALUE", a[0]);
                }
            } else if (a.empty()) {
                emit(0, "AGING", "day", day);
            } else {
                emit(0, "AGING", a[0], "day", day);
            }
            Amount totalQ = 0;
            Amount totalValue = 0;
            vector<Amount> bucketQ(4, 0), bucketV(4, 0);
            for (const auto& [code, entry] : items) {
                Amount q = 0;
                Amount value = 0;
                vector<std::pair<Amount, Amount>> warehouseValues;
                vector<Amount> itemBuckets(4, 0);
                for (const string& w : warehouses) {
                    Amount heldQ = 0;
                    Amount heldValue = 0;
                    for (const auto& [id, current] : holdings(w, code)) {
                        heldQ += current.quantity;
                        heldValue += current.quantity * current.cost;
                        if (cmd == "AGING") {
                            Amount age = day - lots[id - 1].day;
                            size_t bucket = age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3;
                            itemBuckets[bucket] += current.quantity;
                            bucketQ[bucket] += current.quantity;
                            bucketV[bucket] += current.quantity * current.cost;
                        }
                    }
                    q += heldQ;
                    value += heldValue;
                    warehouseValues.push_back({heldQ, heldValue});
                }
                if (q == 0) {
                    continue;
                }
                if (cmd == "VALUE") {
                    emit(2, code, "qty", q, "value", money(value), "avg", money(value / q));
                    if (a.empty()) {
                        for (size_t i = 0; i < warehouses.size(); ++i) {
                            if (warehouseValues[i].first > 0) {
                                emit(4, warehouses[i], "qty", warehouseValues[i].first,
                                     "value", money(warehouseValues[i].second));
                            }
                        }
                    }
                } else {
                    agingLine(code, itemBuckets, false);
                }
                totalQ += q;
                totalValue += value;
            }
            if (cmd == "VALUE") {
                emit(2, "total", "qty", totalQ, "value", money(totalValue));
            } else {
                agingLine("total", bucketQ, false);
                agingLine("value", bucketV, true);
            }

        } else if (cmd == "LOTS") {
            const string& w = a[0];
            const string& code = a[1];
            pair(w, code);
            emit(0, "LOTS", w, code);
            vector<int> ids = fifo(w, code);
            vector<const Order*> pending;
            for (const Order& current : orders) {
                if (current.warehouse == w && current.item == code && current.backorder > 0) {
                    pending.push_back(&current);
                }
            }
            for (int id : ids) {
                const StockLot& current = holdings(w, code).at(id);
                emit(2, "lot", id, "day", lots[id - 1].day,
                     "qty", current.quantity, "cost", money(current.cost),
                     "value", money(current.quantity * current.cost),
                     "age", day - lots[id - 1].day);
            }
            for (const Order* current : pending) {
                emit(2, "backorder", "order", current->number, "qty", current->backorder);
            }
            if (ids.empty() && pending.empty()) {
                emit(2, "(none)");
            }

        } else if (cmd == "REORDER" || cmd == "ITEMS") {
            emit(0, cmd);
            bool found = false;
            for (const auto& [code, entry] : items) {
                Amount q = totalQuantity(code);
                Amount pending = backorder(code);
                if (cmd == "REORDER") {
                    if (q - pending > entry.level) {
                        continue;
                    }
                    emit(2, code, entry.name, "onhand", q,
                         "backorder", pending, "level", entry.level);
                } else {
                    emit(2, code, entry.name, "level", entry.level,
                         "onhand", q, "backorder", pending,
                         "cost", entry.lastCost ? money(*entry.lastCost) : "none");
                }
                found = true;
            }
            if (!found) {
                emit(2, "(none)");
            }

        } else if (cmd == "MARGIN" || cmd == "TOP") {
            auto rows = sales();
            if (cmd == "MARGIN") {
                emit(0, "MARGIN");
                Sale total;
                for (const auto& [code, row] : rows) {
                    marginLine(code, row);
                    total.quantity += row.quantity;
                    total.revenue += row.revenue;
                    total.cogs += row.cogs;
                }
                marginLine("total", total);
            } else {
                Amount k = number(a[0]);
                emit(0, "TOP", k);
                vector<string> codes;
                for (const auto& [code, row] : rows) {
                    codes.push_back(code);
                }
                sort(codes.begin(), codes.end(), [&](const string& left, const string& right) {
                    const Sale& a = rows.at(left);
                    const Sale& b = rows.at(right);
                    Amount leftProfit = a.revenue - a.cogs;
                    Amount rightProfit = b.revenue - b.cogs;
                    if (leftProfit != rightProfit) {
                        return leftProfit > rightProfit;
                    }
                    if (a.revenue != b.revenue) {
                        return a.revenue > b.revenue;
                    }
                    return left < right;
                });
                for (size_t i = 0; i < codes.size() && i < static_cast<size_t>(k); ++i) {
                    const Sale& row = rows.at(codes[i]);
                    Amount profit = row.revenue - row.cogs;
                    emit(2, i + 1, codes[i], "profit", money(profit),
                         "revenue", money(row.revenue), "margin", margin(profit, row.revenue));
                }
                if (codes.empty()) {
                    emit(2, "(none)");
                }
            }

        } else if (cmd == "BACKORDERS") {
            emit(0, "BACKORDERS");
            bool found = false;
            for (const Order& current : orders) {
                if (current.backorder == 0) {
                    continue;
                }
                emit(2, "order", current.number, current.warehouse, current.item, "qty",
                     current.backorder, "day", current.day, "price", money(current.price));
                found = true;
            }
            if (!found) {
                emit(2, "(none)");
            }

        } else if (cmd == "ORDER") {
            Order& current = order(a[0]);
            emit(0, "ORDER", current.number, current.warehouse, current.item,
                 "day", current.day, "price", money(current.price));
            emit(2, "ordered", current.ordered, "shipped", current.shipped,
                 "backorder", current.backorder, "cancelled", current.cancelled,
                 "returned", current.returned);
            for (const Part& part : current.issues) {
                emit(2, "lot", part.lot, "qty", part.quantity, "cost", money(part.cost));
            }
            emit(2, "revenue", money(current.revenue), "cogs",
                 money(current.cogs), "profit", money(current.revenue - current.cogs));

        } else if (cmd == "TRACE") {
            Lot& current = lot(a[0]);
            emit(0, "TRACE", "lot", current.number, current.item, current.kind,
                 current.warehouse, "day", current.day, "qty", current.initialQuantity,
                 "cost", money(current.initialCost));
            for (const auto& [w, contents] : stock) {
                auto entry = holdings(w, current.item).find(current.number);
                if (entry != holdings(w, current.item).end()) {
                    emit(2, "held", w, "qty", entry->second.quantity,
                         "cost", money(entry->second.cost));
                }
            }
            for (const Order& currentOrder : orders) {
                Amount q = 0;
                for (const Part& part : currentOrder.issues) {
                    if (part.lot == current.number) {
                        q += part.quantity;
                    }
                }
                if (q > 0) {
                    emit(2, "order", currentOrder.number, "qty", q);
                }
            }
            if (current.removed > 0) {
                emit(2, "removed", "qty", current.removed);
            }

        } else if (cmd == "CARD") {
            Item& entry = item(a[0]);
            emit(0, "CARD", entry.code, entry.name);
            Amount q = 0;
            Amount value = 0;
            for (const CardEntry& card : entry.card) {
                q += card.quantity;
                value += card.value;
                emit(2, "day", card.day, card.kind, card.warehouse,
                     signedQuantity(card.quantity), signedMoney(card.value),
                     "balance", q, money(value));
            }
            if (entry.card.empty()) {
                emit(2, "(none)");
            }

        } else if (cmd == "STATUS") {
            emit(0, "STATUS");
            for (const auto& [w, contents] : stock) {
                Amount skus = 0;
                Amount q = 0;
                Amount value = 0;
                for (const auto& [code, held] : contents) {
                    if (!held.empty()) {
                        skus++;
                    }
                    for (const auto& [id, current] : held) {
                        q += current.quantity;
                        value += current.quantity * current.cost;
                    }
                }
                Amount pending = 0;
                for (const Order& current : orders) {
                    if (current.warehouse == w) {
                        pending += current.backorder;
                    }
                }
                emit(2, w, "skus", skus, "qty", q, "value", money(value),
                     "backorder", pending);
            }
            if (stock.empty()) {
                emit(2, "(none)");
            }

        } else if (cmd == "SUMMARY") {
            emit(0, "SUMMARY");
            for (const string& category : categories) {
                const Total& total = totals[category];
                emit(2, category, "qty", total.quantity, "value", money(total.value));
            }
            Total total = allStocks();
            emit(2, "on-hand", "qty", total.quantity, "value", money(total.value));
            Amount open = 0;
            Amount pending = 0;
            for (const Order& current : orders) {
                if (current.backorder > 0) {
                    open++;
                }
                pending += current.backorder;
            }
            emit(2, "orders", orders.size(), "open", open, "backorder", pending);
        }
    }

public:
    Inventory() {
        for (const string& category : categories) {
            totals[category] = {};
        }
    }

    void execute(const string& line) {
        istringstream input(line);
        string cmd;
        input >> cmd;
        vector<string> args;
        string token;
        while (input >> token) {
            args.push_back(token);
        }
        try {
            command(cmd, args);
        } catch (const runtime_error& exception) {
            emit(0, "ERROR", exception.what());
        }
    }

    void print() const {
        for (const string& line : output) {
            cout << line << '\n';
        }
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    int count;
    if (!(cin >> count)) {
        return 0;
    }
    string line;
    getline(cin, line);
    Inventory inventory;
    for (int i = 0; i < count && getline(cin, line); ++i) {
        inventory.execute(line);
    }
    inventory.print();
}
