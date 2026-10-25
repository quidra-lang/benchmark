#include "mrp.hpp"
#include <algorithm>
#include <fstream>
#include <functional>
#include <numeric>
#include <tuple>

Lines split(const std::string& text, char delimiter) {
    Lines result; std::size_t start = 0, end;
    while ((end = text.find(delimiter, start)) != std::string::npos) { result.push_back(text.substr(start, end - start)); start = end + 1; }
    result.push_back(text.substr(start)); return result;
}
std::string join(const Lines& values, const std::string& delimiter) {
    std::string result; for (std::size_t i = 0; i < values.size(); ++i) { if (i != 0) result += delimiter; result += values[i]; } return result;
}
Lines readLines(const std::string& name) { std::ifstream file("input/" + name); Lines lines; for (std::string line; std::getline(file, line);) lines.push_back(line); return lines; }
std::vector<Row> readRows(const std::string& name) { Lines lines = readLines(name); std::vector<Row> rows; for (std::size_t i = 1; i < lines.size(); ++i) rows.push_back({static_cast<int>(i) + 1, split(lines[i], ',')}); return rows; }
void inputError(Lines& errors, const std::string& file, int line, const std::string& message) { errors.push_back(file + " line " + std::to_string(line) + ": " + message); }

namespace {
void append(Lines& target, const Lines& source) { target.insert(target.end(), source.begin(), source.end()); }
Integer sum(const Values& values) { return std::accumulate(values.begin(), values.end(), Integer{0}); }
Values weeksOnly(const Values& values) { return Values(values.begin() + 1, values.end()); }
struct ScheduleRow { std::string item; int week; Integer quantity; int line; };
struct Inquiry { std::string id, item; Integer quantity; int week, line; };
std::string scheduleError(const std::string& item, int week, Integer quantity, const Items& items, int horizon) {
    if (!items.count(item)) return "unknown item " + item;
    if (week < 1 || week > horizon) return "week " + std::to_string(week) + " outside horizon";
    if (quantity < 1) return "bad quantity " + std::to_string(quantity);
    return "";
}
std::vector<ScheduleRow> readSchedule(const std::string& name, const Items& items, int horizon, Lines& errors, bool unique) {
    std::vector<ScheduleRow> accepted; std::set<std::pair<std::string, int>> seen;
    for (const Row& row : readRows(name)) {
        ScheduleRow value{row.fields[0], std::stoi(row.fields[1]), std::stoll(row.fields[2]), row.line};
        std::string error = scheduleError(value.item, value.week, value.quantity, items, horizon);
        if (error.empty() && unique && seen.count({value.item, value.week})) error = "duplicate " + value.item + " week " + std::to_string(value.week);
        if (!error.empty()) inputError(errors, name, row.line, error);
        else { accepted.push_back(value); seen.insert({value.item, value.week}); }
    }
    return accepted;
}
std::vector<Inquiry> readInquiries(const Items& items, int horizon, Lines& errors) {
    std::vector<Inquiry> accepted; std::set<std::string> seen;
    for (const Row& row : readRows("orders.csv")) {
        Inquiry value{row.fields[0], row.fields[1], std::stoll(row.fields[2]), std::stoi(row.fields[3]), row.line};
        std::string error = seen.count(value.id) ? "duplicate order " + value.id : scheduleError(value.item, value.week, value.quantity, items, horizon);
        if (!error.empty()) inputError(errors, "orders.csv", row.line, error); else { accepted.push_back(value); seen.insert(value.id); }
    }
    return accepted;
}
enum class DemandKind { Mps, Order, Dependent, Safety };
using RootKey = std::tuple<std::string, int, int, std::string>;
struct Demand {
    std::string item;
    DemandKind kind;
    int week;
    Integer quantity;
    std::string orderId;
    int line = 0;
    std::string parent;
    int parentNumber = 0;
    RootKey rootKey() const { return {item, kind == DemandKind::Mps ? 0 : kind == DemandKind::Order ? 1 : 2, week, orderId}; }
    std::string text() const {
        if (kind == DemandKind::Safety) return "SAFETY " + item;
        if (kind == DemandKind::Mps) return "MPS " + item + " week " + std::to_string(week);
        if (kind == DemandKind::Order) return "ORDER " + orderId + " " + item + " week " + std::to_string(week);
        return parent + " order " + std::to_string(parentNumber) + " week " + std::to_string(week);
    }
};
struct PlannedOrder {
    std::string item;
    int number, receipt;
    Integer quantity;
    int original, release;
};
enum class SupplyKind { Stock, Receipt, Order };
struct Allocation { Demand demand; Integer share; };
struct Supply {
    SupplyKind kind;
    int week;
    Integer quantity;
    int line;
    std::optional<PlannedOrder> order;
    Integer remaining;
    std::vector<Allocation> allocations;
    std::vector<Demand> roots;
    std::string header() const {
        if (kind == SupplyKind::Stock) return "STOCK quantity " + std::to_string(quantity);
        if (kind == SupplyKind::Receipt) return "RECEIPT line " + std::to_string(line) + " week " + std::to_string(week) + " quantity " + std::to_string(quantity);
        return "ORDER " + std::to_string(order->number) + " receipt " + std::to_string(order->receipt) + " release " + std::to_string(order->release) + " quantity " + std::to_string(order->quantity);
    }
    bool serves(const std::string& id) const { return std::any_of(roots.begin(), roots.end(), [&](const Demand& root) { return root.kind == DemandKind::Order && root.orderId == id; }); }
};
struct ItemPlan {
    const Item* item;
    Values receipts, gross, onHand, net, plannedReceipts, plannedReleases;
    std::vector<Demand> demands;
    std::vector<PlannedOrder> orders;
    std::vector<Supply> supplies;
    std::vector<std::size_t> orderSupplies;
    ItemPlan(const Item& value, int horizon, const Values& scheduled) : item(&value), receipts(scheduled), gross(horizon + 1), onHand(horizon + 1), net(horizon + 1), plannedReceipts(horizon + 1), plannedReleases(horizon + 1) {}
    Integer pastDue() const { Integer total = 0; for (const PlannedOrder& order : orders) if (order.original < 1) total += order.quantity; return total; }
};
struct Plan {
    std::map<std::string, ItemPlan> items;
    std::map<std::string, Values> loads, overloads;
};
struct Data {
    Lines errors, pegItems, planningOrder;
    int horizon = 0;
    Integer treeQuantity = 0;
    Items items;
    Bom bom;
    Centers centers;
    Routings routings;
    std::vector<Demand> mps;
    std::vector<Inquiry> inquiries;
    std::map<std::string, int> codes, cumulative;
    std::map<std::string, std::vector<ScheduleRow>> receipts;
    std::map<std::string, Values> scheduled;
    Values weeks;
    Data() {
        for (const std::string& line : readLines("params.txt")) {
            Lines f = split(line, ' '); if (f[0] == "horizon") horizon = std::stoi(f[1]); else if (f[0] == "peg") pegItems.assign(f.begin() + 1, f.end()); else treeQuantity = std::stoll(f[1]);
        }
        items = readItems(errors); bom = readBom(items, errors); centers = readCenters(errors); routings = readRoutings(items, centers, bom, errors);
        auto schedule = readSchedule("mps.csv", items, horizon, errors, true); auto received = readSchedule("receipts.csv", items, horizon, errors, false); inquiries = readInquiries(items, horizon, errors);
        for (const ScheduleRow& row : schedule) mps.push_back({row.item, DemandKind::Mps, row.week, row.quantity, "", 0, "", 0});
        for (const auto& [id, item] : items) { bom.lowLevel(id, codes); bom.cumulative(id, items, cumulative); planningOrder.push_back(id); receipts[id] = {}; scheduled[id] = Values(horizon + 1); }
        std::sort(planningOrder.begin(), planningOrder.end(), [&](const std::string& a, const std::string& b) { return codes.at(a) != codes.at(b) ? codes.at(a) < codes.at(b) : a < b; });
        std::sort(received.begin(), received.end(), [](const ScheduleRow& a, const ScheduleRow& b) { return std::tie(a.week, a.line) < std::tie(b.week, b.line); });
        for (const ScheduleRow& row : received) { receipts.at(row.item).push_back(row); scheduled.at(row.item)[row.week] += row.quantity; }
        weeks.resize(horizon); std::iota(weeks.begin(), weeks.end(), 1);
    }
};
Plan runMrp(const Data& data, const std::vector<Demand>& orderDemands) {
    Plan plan;
    for (const std::string& id : data.planningOrder) plan.items.emplace(id, ItemPlan(data.items.at(id), data.horizon, data.scheduled.at(id)));
    for (const Demand& demand : data.mps) plan.items.at(demand.item).demands.push_back(demand);
    for (const Demand& demand : orderDemands) plan.items.at(demand.item).demands.push_back(demand);
    for (const std::string& id : data.planningOrder) {
        ItemPlan& itemPlan = plan.items.at(id); const Item& item = *itemPlan.item;
        for (const Demand& demand : itemPlan.demands) itemPlan.gross[demand.week] += demand.quantity;
        Integer projected = item.onHand;
        for (int week = 1; week <= data.horizon; ++week) {
            Integer available = projected + itemPlan.receipts[week] - itemPlan.gross[week]; projected = available;
            if (available < item.safety) {
                Integer quantity = lotSize(item, week, available, itemPlan.receipts, itemPlan.gross, data.horizon); int original = week - item.lead, release = std::max(1, original);
                itemPlan.orders.push_back({id, static_cast<int>(itemPlan.orders.size()) + 1, week, quantity, original, release}); itemPlan.net[week] = item.safety - available; itemPlan.plannedReceipts[week] = quantity; itemPlan.plannedReleases[release] += quantity; projected += quantity;
            }
            itemPlan.onHand[week] = projected;
        }
        for (const PlannedOrder& order : itemPlan.orders) for (const Edge& edge : data.bom.children.at(id)) plan.items.at(edge.child).demands.push_back({edge.child, DemandKind::Dependent, order.release, edge.need(order.quantity), "", 0, id, order.number});
    }
    for (const auto& [id, center] : data.centers) plan.loads[id] = Values(data.horizon + 1);
    for (const auto& [id, operations] : data.routings) for (const PlannedOrder& order : plan.items.at(id).orders) for (std::size_t i = 0; i < operations.size(); ++i) {
        const Operation& operation = operations[i]; int week = operationWeek(order.receipt, data.items.at(id).lead, static_cast<int>(i), static_cast<int>(operations.size())); plan.loads.at(operation.center)[week] += operation.minutes(order.quantity);
    }
    for (const auto& [id, center] : data.centers) { Values over(data.horizon + 1); for (int week = 1; week <= data.horizon; ++week) over[week] = std::max<Integer>(0, plan.loads.at(id)[week] - center.available); plan.overloads.emplace(id, std::move(over)); }
    return plan;
}
struct Promise {
    Inquiry inquiry;
    int week = 0, materialWeek = 0;
    std::string reason;
};
std::pair<std::vector<Promise>, Plan> promiseInquiries(const Data& data, const Plan& base) {
    Plan current = base; std::vector<Demand> promised; std::vector<Promise> promises;
    for (const Inquiry& inquiry : data.inquiries) {
        Promise promise{inquiry};
        for (int week = inquiry.week; week <= data.horizon; ++week) {
            Demand demand{inquiry.item, DemandKind::Order, week, inquiry.quantity, inquiry.id, inquiry.line, "", 0}; std::vector<Demand> candidate = promised; candidate.push_back(demand); Plan trial = runMrp(data, candidate); std::string reason;
            for (const std::string& id : data.planningOrder) if (trial.items.at(id).pastDue() > current.items.at(id).pastDue()) { reason = id; break; }
            if (reason.empty()) {
                if (promise.materialWeek == 0) promise.materialWeek = week;
                for (const auto& [id, center] : data.centers) { for (int t = 1; t <= data.horizon; ++t) if (trial.overloads.at(id)[t] > current.overloads.at(id)[t]) { reason = id + " week " + std::to_string(t); break; } if (!reason.empty()) break; }
            }
            if (reason.empty()) { promise.week = week; promised.push_back(demand); current = std::move(trial); break; }
            if (week == inquiry.week) promise.reason = reason;
        }
        promises.push_back(promise);
    }
    return {promises, std::move(current)};
}
const Supply& parentSupply(const Plan& plan, const Demand& demand) {
    const ItemPlan& parent = plan.items.at(demand.parent); return parent.supplies[parent.orderSupplies[demand.parentNumber - 1]];
}
void pegPlan(const Data& data, Plan& plan) {
    for (const std::string& id : data.planningOrder) {
        ItemPlan& itemPlan = plan.items.at(id); const Item& item = *itemPlan.item;
        if (item.onHand > 0) itemPlan.supplies.push_back({SupplyKind::Stock, 0, item.onHand, 0, std::nullopt, item.onHand, {}, {}});
        for (const ScheduleRow& receipt : data.receipts.at(id)) itemPlan.supplies.push_back({SupplyKind::Receipt, receipt.week, receipt.quantity, receipt.line, std::nullopt, receipt.quantity, {}, {}});
        for (const PlannedOrder& order : itemPlan.orders) itemPlan.supplies.push_back({SupplyKind::Order, order.receipt, order.quantity, 0, order, order.quantity, {}, {}});
        std::stable_sort(itemPlan.supplies.begin(), itemPlan.supplies.end(), [](const Supply& a, const Supply& b) { return std::tie(a.week, a.kind, a.line) < std::tie(b.week, b.kind, b.line); });
        std::vector<Demand> demands = itemPlan.demands;
        std::sort(demands.begin(), demands.end(), [](const Demand& a, const Demand& b) { return std::tie(a.week, a.kind, a.line, a.parent, a.parentNumber) < std::tie(b.week, b.kind, b.line, b.parent, b.parentNumber); });
        if (item.safety > 0) demands.insert(demands.begin(), Demand{id, DemandKind::Safety, 0, item.safety, "", 0, "", 0});
        std::size_t index = 0;
        for (const Demand& demand : demands) {
            Integer remaining = demand.quantity;
            while (remaining > 0) { while (itemPlan.supplies[index].remaining == 0) ++index; Supply& supply = itemPlan.supplies[index]; Integer share = std::min(remaining, supply.remaining); supply.allocations.push_back({demand, share}); remaining -= share; supply.remaining -= share; }
        }
        for (std::size_t i = 0; i < itemPlan.supplies.size(); ++i) if (itemPlan.supplies[i].kind == SupplyKind::Order) {
            itemPlan.orderSupplies.push_back(i); Supply& supply = itemPlan.supplies[i]; std::map<RootKey, Demand> roots;
            for (const Allocation& allocation : supply.allocations) {
                const Demand& demand = allocation.demand;
                if (demand.kind == DemandKind::Dependent) { for (const Demand& root : parentSupply(plan, demand).roots) roots.insert_or_assign(root.rootKey(), root); }
                else roots.insert_or_assign(demand.rootKey(), demand);
            }
            for (const auto& [key, demand] : roots) supply.roots.push_back(demand);
        }
    }
}
std::string depthLabel(int depth) { return std::string(depth, '.') + std::to_string(depth); }
Lines gridLines(const Data& data, const Plan& plan) {
    Lines lines;
    for (const std::string& id : data.planningOrder) {
        const ItemPlan& p = plan.items.at(id); const Item& item = *p.item;
        lines.push_back(join({"ITEM", id, "LLC", std::to_string(data.codes.at(id)), "LT", std::to_string(item.lead), "LOT", item.lotLabel(), "SS", std::to_string(item.safety), "OH", std::to_string(item.onHand), item.description}));
        lines.push_back(tableRow("WEEK", data.weeks, 6));
        for (const auto& [label, values] : std::vector<std::pair<std::string, Values>>{{"GROSS", p.gross}, {"RECEIPTS", p.receipts}, {"ON_HAND", p.onHand}, {"NET", p.net}, {"PLAN_RCPT", p.plannedReceipts}, {"PLAN_REL", p.plannedReleases}}) lines.push_back(tableRow(label, weeksOnly(values), 6));
        lines.push_back(join({"TOTAL", "gross", std::to_string(sum(p.gross)), "receipts", std::to_string(sum(p.receipts)), "planned", std::to_string(sum(p.plannedReceipts)), "orders", std::to_string(p.orders.size()), "ending", std::to_string(p.onHand[data.horizon])}));
    }
    return lines;
}
void whereUsed(const Data& data, const std::string& id, int depth, Integer extension, Lines& lines) {
    for (const Edge& edge : data.bom.parents.at(id)) { Integer next = extension * edge.quantity; lines.push_back(join({depthLabel(depth), edge.parent, "qty", std::to_string(edge.quantity), "ext", std::to_string(next)})); whereUsed(data, edge.parent, depth + 1, next, lines); }
}
void allocationLines(const Plan& plan, const Supply& supply, int depth, Lines& lines) {
    for (const Allocation& allocation : supply.allocations) {
        lines.push_back(std::string(2 * depth, ' ') + "ALLOC " + std::to_string(allocation.share) + " " + allocation.demand.text());
        if (supply.kind == SupplyKind::Order && allocation.demand.kind == DemandKind::Dependent) allocationLines(plan, parentSupply(plan, allocation.demand), depth + 1, lines);
    }
}
Lines peggingLines(const Data& data, const Plan& plan) {
    Lines lines;
    for (const std::string& id : data.pegItems) {
        const ItemPlan& item = plan.items.at(id); lines.push_back("PEG " + id + " orders " + std::to_string(item.orders.size())); whereUsed(data, id, 1, 1, lines);
        for (SupplyKind kind : {SupplyKind::Stock, SupplyKind::Receipt, SupplyKind::Order}) for (const Supply& supply : item.supplies) if (supply.kind == kind) {
            lines.push_back(supply.header()); allocationLines(plan, supply, 1, lines); if (supply.remaining > 0) lines.push_back("  EXCESS " + std::to_string(supply.remaining)); for (const Demand& root : supply.roots) lines.push_back("  ROOT " + root.text());
        }
    }
    return lines;
}
void explodeTree(const Data& data, const std::string& id, Integer gross, Integer extension, int depth, Lines& lines, std::map<std::string, Integer>& totals) {
    for (const Edge& edge : data.bom.children.at(id)) {
        const Item& child = data.items.at(edge.child); Integer nextExtension = extension * edge.quantity, nextGross = edge.need(gross); totals[edge.child] += nextGross;
        lines.push_back(join({depthLabel(depth), edge.child, "qty", std::to_string(edge.quantity), "scrap", std::to_string(edge.scrap), "ext", std::to_string(nextExtension), "gross", std::to_string(nextGross), "lt", std::to_string(child.lead), "cum", std::to_string(data.cumulative.at(edge.child)), child.description}));
        explodeTree(data, edge.child, nextGross, nextExtension, depth + 1, lines, totals);
    }
}
Lines treeLines(const Data& data) {
    Lines lines;
    for (const auto& [id, item] : data.items) if (data.bom.topLevel(id)) {
        lines.push_back("TREE " + id + " quantity " + std::to_string(data.treeQuantity)); lines.push_back(join({"0", id, "ext", "1", "gross", std::to_string(data.treeQuantity), "lt", std::to_string(item.lead), "cum", std::to_string(data.cumulative.at(id)), item.description}));
        std::map<std::string, Integer> totals; explodeTree(data, id, data.treeQuantity, 1, 1, lines, totals); for (const auto& [child, quantity] : totals) lines.push_back("SUM " + child + " " + std::to_string(quantity));
        Lines path{id}; std::string current = id;
        while (data.bom.manufactured(current)) { const auto& children = data.bom.children.at(current); const Edge* best = &children.front(); for (const Edge& edge : children) if (data.cumulative.at(edge.child) > data.cumulative.at(best->child)) best = &edge; current = best->child; path.push_back(current); }
        lines.push_back("CRITICAL " + join(path, " -> ") + " cum " + std::to_string(data.cumulative.at(id)));
    }
    return lines;
}
Lines costLines(const Data& data, const Plan& plan, const std::map<std::string, StandardCost>& costs) {
    std::map<std::string, Integer> usages, values; for (const auto& [id, item] : data.items) { usages[id] = sum(plan.items.at(id).gross); values[id] = usages[id] * costs.at(id).total(); }
    auto classes = abcClasses(values); Lines lines{"item,material,labor,total,usage,value,class"};
    for (const auto& [id, item] : data.items) { const StandardCost& cost = costs.at(id); lines.push_back(join({id, money(cost.material), money(cost.labor), money(cost.total()), std::to_string(usages.at(id)), money(values.at(id)), classes.at(id)}, ",")); }
    return lines;
}
Lines exceptionLines(const Data& data, const Plan& plan) {
    Lines messages;
    for (const std::string& id : data.planningOrder) {
        const ItemPlan& p = plan.items.at(id); const Item& item = *p.item;
        if (item.onHand < item.safety) messages.push_back(join({"BELOW_SAFETY", id, "on", "hand", std::to_string(item.onHand), "safety", std::to_string(item.safety)}));
        for (const PlannedOrder& order : p.orders) {
            Lines head{id, "order", std::to_string(order.number), "receipt", std::to_string(order.receipt)};
            if (order.original < 1) { append(head, {"release", std::to_string(order.original), "late", std::to_string(1 - order.original), "quantity", std::to_string(order.quantity)}); messages.push_back("PAST_DUE " + join(head)); }
            else if (order.original == 1) { append(head, {"quantity", std::to_string(order.quantity)}); messages.push_back("RELEASE " + join(head)); }
        }
        Values balances(data.horizon + 1); Integer balance = item.onHand, covered = 0;
        for (int week = 1; week <= data.horizon; ++week) { balance -= p.gross[week]; balances[week] = balance; }
        for (const ScheduleRow& receipt : data.receipts.at(id)) {
            int needWeek = 0; for (int week = 1; week <= data.horizon; ++week) if (balances[week] + covered < item.safety) { needWeek = week; break; }
            std::string head = join({id, "receipt", "line", std::to_string(receipt.line), "week", std::to_string(receipt.week), "quantity", std::to_string(receipt.quantity)});
            if (needWeek == 0) messages.push_back("CANCEL " + head); else if (needWeek < receipt.week) messages.push_back("EXPEDITE " + head + " to " + std::to_string(needWeek)); else if (needWeek > receipt.week) messages.push_back("DEFER " + head + " to " + std::to_string(needWeek));
            covered += receipt.quantity;
        }
        if (data.bom.manufactured(id) && !data.routings.count(id)) messages.push_back("NO_ROUTING " + id);
        if (sum(p.gross) == 0 && item.onHand > 0) messages.push_back("NO_DEMAND " + id + " on hand " + std::to_string(item.onHand));
    }
    for (const auto& [id, center] : data.centers) for (int week = 1; week <= data.horizon; ++week) if (plan.overloads.at(id)[week] > 0) messages.push_back(join({"OVERLOAD", id, "week", std::to_string(week), "load", std::to_string(plan.loads.at(id)[week]), "available", std::to_string(center.available)}));
    Lines lines; for (const std::string& error : data.errors) lines.push_back("ERROR " + error); append(lines, messages);
    const Lines kinds{"BELOW_SAFETY", "PAST_DUE", "RELEASE", "EXPEDITE", "DEFER", "CANCEL", "NO_ROUTING", "NO_DEMAND", "OVERLOAD"};
    Lines totals{"SUMMARY", "errors", std::to_string(data.errors.size())};
    for (const std::string& kind : kinds) {
        std::size_t count = std::count_if(messages.begin(), messages.end(), [&](const std::string& message) { return message.substr(0, message.find(' ')) == kind; });
        std::string lower = kind; for (char& character : lower) if (character >= 'A' && character <= 'Z') character = static_cast<char>(character - 'A' + 'a'); append(totals, {lower, std::to_string(count)});
    }
    lines.push_back(join(totals)); return lines;
}
Lines capacityLines(const Data& data, const Plan& plan) {
    Lines lines, ranked; std::map<std::string, Integer> totals;
    for (const auto& [id, center] : data.centers) {
        const Values& loads = plan.loads.at(id); const Values& over = plan.overloads.at(id); Values leveled = levelLoads(loads, center.available), utilization;
        for (int week = 1; week <= data.horizon; ++week) utilization.push_back(percentage(loads[week], center.available));
        Integer total = sum(loads), available = center.available * data.horizon, backlog = std::max<Integer>(0, leveled[1] - center.available); totals[id] = total; ranked.push_back(id);
        std::size_t peak = total == 0 ? 0 : std::max_element(loads.begin() + 1, loads.end()) - loads.begin(); int overloaded = static_cast<int>(std::count_if(over.begin(), over.end(), [](Integer value) { return value > 0; }));
        lines.push_back(join({"CENTER", id, "minutes", std::to_string(center.minutes), "efficiency", std::to_string(center.efficiency), "available", std::to_string(center.available), center.description}));
        lines.push_back(tableRow("WEEK", data.weeks, 7)); lines.push_back(tableRow("LOAD", weeksOnly(loads), 7)); lines.push_back(tableRow("UTIL", utilization, 7)); lines.push_back(tableRow("OVER", weeksOnly(over), 7)); lines.push_back(tableRow("LEVELED", weeksOnly(leveled), 7));
        lines.push_back(join({"TOTAL", "load", std::to_string(total), "available", std::to_string(available), "utilization", std::to_string(percentage(total, available)), "overloaded", std::to_string(overloaded), "peak", std::to_string(peak), "backlog", std::to_string(backlog)}));
    }
    std::sort(ranked.begin(), ranked.end(), [&](const std::string& a, const std::string& b) { Integer left = totals.at(a) * data.centers.at(b).available, right = totals.at(b) * data.centers.at(a).available; return left != right ? left > right : a < b; });
    for (std::size_t rank = 0; rank < ranked.size(); ++rank) { const std::string& id = ranked[rank]; lines.push_back(join({"RANK", std::to_string(rank + 1), id, "load", std::to_string(totals.at(id)), "utilization", std::to_string(percentage(totals.at(id), data.centers.at(id).available * data.horizon))})); }
    return lines;
}
Lines promiseLines(const Data& data, const std::vector<Promise>& promises, const Plan& base, const Plan& final) {
    Lines lines; int onTime = 0, late = 0, rejected = 0;
    for (const Promise& promise : promises) {
        const Inquiry& inquiry = promise.inquiry; std::string head = join({"ORDER", inquiry.id, inquiry.item, "quantity", std::to_string(inquiry.quantity), "requested", std::to_string(inquiry.week)}); std::string material = promise.materialWeek == 0 ? "none" : std::to_string(promise.materialWeek);
        if (promise.week == 0) { ++rejected; lines.push_back(head + " rejected material " + material + " reason " + promise.reason); continue; }
        if (promise.week == inquiry.week) { ++onTime; lines.push_back(head + " promised " + std::to_string(promise.week)); }
        else { ++late; lines.push_back(head + " promised " + std::to_string(promise.week) + " late " + std::to_string(promise.week - inquiry.week) + " material " + material + " reason " + promise.reason); }
        for (const std::string& id : data.planningOrder) { const ItemPlan& item = final.items.at(id); for (std::size_t index : item.orderSupplies) { const Supply& supply = item.supplies[index]; if (supply.serves(inquiry.id)) { const PlannedOrder& order = *supply.order; lines.push_back("  " + join({"SUPPLY", id, "order", std::to_string(order.number), "receipt", std::to_string(order.receipt), "release", std::to_string(order.release), "quantity", std::to_string(order.quantity)})); } } }
    }
    for (const std::string& id : data.planningOrder) {
        const ItemPlan& before = base.items.at(id); const ItemPlan& after = final.items.at(id); int first = 0;
        for (int week = 1; week <= data.horizon; ++week) if (before.plannedReceipts[week] != after.plannedReceipts[week]) { first = week; break; }
        if (first != 0) lines.push_back(join({"CHANGE", id, "from", std::to_string(first), "planned", std::to_string(sum(before.plannedReceipts)), "->", std::to_string(sum(after.plannedReceipts)), "orders", std::to_string(before.orders.size()), "->", std::to_string(after.orders.size())}));
    }
    lines.push_back(join({"SUMMARY", "orders", std::to_string(promises.size()), "on_time", std::to_string(onTime), "late", std::to_string(late), "rejected", std::to_string(rejected)})); return lines;
}
Lines releaseLines(const Data& data, const Plan& plan) {
    std::vector<PlannedOrder> orders; std::map<std::string, Integer> available;
    for (const std::string& id : data.planningOrder) { for (const PlannedOrder& order : plan.items.at(id).orders) if (order.release == 1) orders.push_back(order); available[id] = data.items.at(id).onHand + data.scheduled.at(id)[1]; }
    std::sort(orders.begin(), orders.end(), [](const PlannedOrder& a, const PlannedOrder& b) { return std::tie(a.original, a.item, a.number) < std::tie(b.original, b.item, b.number); });
    Lines lines; int made = 0, readyCount = 0, bought = 0; Integer purchaseTotal = 0;
    for (const PlannedOrder& order : orders) {
        const Item& item = data.items.at(order.item); std::string head = join({order.item, "order", std::to_string(order.number), "receipt", std::to_string(order.receipt), "quantity", std::to_string(order.quantity)}); if (order.original < 1) head += " late " + std::to_string(1 - order.original);
        if (!data.bom.manufactured(order.item)) { Integer value = order.quantity * item.material; ++bought; purchaseTotal += value; lines.push_back("BUY " + head + " value " + money(value)); continue; }
        ++made; bool ready = true; Lines details; const auto& children = data.bom.children.at(order.item);
        for (const Edge& edge : children) { Integer need = edge.need(order.quantity), have = available.at(edge.child); if (need > have) ready = false; details.push_back("  " + join({"PICK", edge.child, "need", std::to_string(need), "available", std::to_string(have), "short", std::to_string(std::max<Integer>(0, need - have))})); }
        if (ready) { ++readyCount; for (const Edge& edge : children) available.at(edge.child) -= edge.need(order.quantity); }
        auto routing = data.routings.find(order.item);
        if (routing != data.routings.end()) for (std::size_t i = 0; i < routing->second.size(); ++i) { const Operation& operation = routing->second[i]; int week = operationWeek(order.receipt, item.lead, static_cast<int>(i), static_cast<int>(routing->second.size())); details.push_back("  " + join({"OPERATION", std::to_string(operation.number), operation.center, "week", std::to_string(week), "minutes", std::to_string(operation.minutes(order.quantity))})); }
        lines.push_back("MAKE " + head + (ready ? " READY" : " SHORT")); append(lines, details);
    }
    lines.push_back(join({"SUMMARY", "make", std::to_string(made), "ready", std::to_string(readyCount), "short", std::to_string(made - readyCount), "buy", std::to_string(bought), "value", money(purchaseTotal)})); return lines;
}
Lines valueLines(const Data& data, const Plan& plan, const std::map<std::string, StandardCost>& costs) {
    Lines lines{"week,inventory,purchases,labor"};
    for (int week = 1; week <= data.horizon; ++week) {
        Integer inventory = 0, purchases = 0, labor = 0;
        for (const std::string& id : data.planningOrder) { const ItemPlan& p = plan.items.at(id); inventory += p.onHand[week] * costs.at(id).total(); if (data.bom.manufactured(id)) labor += p.plannedReleases[week] * p.item->labor; else purchases += p.plannedReleases[week] * p.item->material; }
        lines.push_back(join({std::to_string(week), money(inventory), money(purchases), money(labor)}, ","));
    }
    return lines;
}
}
int main() {
    Data data; Plan base = runMrp(data, {}); auto [promises, final] = promiseInquiries(data, base); pegPlan(data, final); auto costs = standardCosts(data.items, data.bom, data.planningOrder);
    writeReport("mrp_grid.txt", gridLines(data, final)); writeReport("pegging.txt", peggingLines(data, final)); writeReport("bom_tree.txt", treeLines(data)); writeReport("cost_rollup.csv", costLines(data, final, costs)); writeReport("exceptions.txt", exceptionLines(data, final)); writeReport("capacity.txt", capacityLines(data, final)); writeReport("promises.txt", promiseLines(data, promises, base, final)); writeReport("releases.txt", releaseLines(data, final)); writeReport("value_plan.csv", valueLines(data, final, costs));
}
