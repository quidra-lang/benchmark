#include "bond.hpp"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <numeric>
#include <stdexcept>

namespace {
const Lines types{"FIXED", "ZERO", "AMORT", "FRN"};
const Lines bucketNames{"0-1Y", "1-3Y", "3-5Y", "5-10Y", "10Y+"};
const std::set<int> frequencies{1, 2, 4, 12};
const std::set<std::string> daycounts{"30/360", "30E/360", "ACT/360", "ACT/365F", "ACT/ACT"};
const std::set<std::string> businessRules{"FOLLOWING", "MODIFIED_FOLLOWING", "PRECEDING", "UNADJUSTED"};
struct InputError : std::runtime_error { using std::runtime_error::runtime_error; };
Lines split(const std::string& text, char delimiter) {
    Lines result; std::size_t start = 0, end;
    while ((end = text.find(delimiter, start)) != std::string::npos) { result.push_back(text.substr(start, end - start)); start = end + 1; }
    result.push_back(text.substr(start)); return result;
}
std::string join(const Lines& fields, const std::string& delimiter = " ") {
    std::string line; for (std::size_t i = 0; i < fields.size(); ++i) { if (i != 0) line += delimiter; line += fields[i]; } return line;
}
Lines readLines(const std::string& name) { std::ifstream input("input/" + name); Lines result; for (std::string line; std::getline(input, line);) result.push_back(line); return result; }
struct Row { int line; Lines fields; };
std::vector<Row> readRows(const std::string& name) {
    Lines lines = readLines(name); std::vector<Row> rows; for (std::size_t i = 1; i < lines.size(); ++i) rows.push_back({static_cast<int>(i) + 1, split(lines[i], ',')}); return rows;
}
Integer rounded(Integer numerator, Integer denominator) { return (2 * numerator + denominator) / (2 * denominator); }
Integer thousandths(const std::string& text) { Lines p = split(text, '.'); return std::stoll(p[0]) * 1000 + std::stoll(p[1]); }
std::string decimal(double value, int places) {
    Integer scale = 1; for (int i = 0; i < places; ++i) scale *= 10;
    double magnitude = value < 0 ? -value : value; Integer n = static_cast<Integer>(magnitude * scale + 0.5);
    std::string tail = std::to_string(n % scale);
    return (value < 0 && n != 0 ? "-" : "") + std::to_string(n / scale) + "." + std::string(places - tail.size(), '0') + tail;
}
std::string hundredths(Integer value) {
    if (value < 0) return "-" + hundredths(-value);
    std::string tail = std::to_string(value % 100); return std::to_string(value / 100) + "." + std::string(2 - tail.size(), '0') + tail;
}
std::string percent(double rate) { return decimal(rate * 100, 4); }
std::string amount(double cents) { return decimal(cents / 100, 2); }
void save(const std::string& name, const Lines& lines) { std::ofstream output("output/" + name, std::ios::binary); for (const std::string& line : lines) output << line << '\n'; }
void append(Lines& target, const Lines& source) { target.insert(target.end(), source.begin(), source.end()); }
struct ErrorLog {
    Lines lines;
    void add(const std::string& file, int line, const std::string& key, const std::string& message) { lines.push_back(file + ":" + std::to_string(line) + ": " + key + ": " + message); }
};
struct Scenario { std::string name; std::vector<double> deltas; };
struct RawScenario { int line; std::string name; std::vector<int> shifts; };
struct Parameters {
    int valuation = 0, settlementDays = 0;
    std::vector<RawScenario> scenarios;
    std::vector<Lines> limits;
    explicit Parameters(const Lines& lines) {
        for (std::size_t i = 0; i < lines.size(); ++i) {
            Lines fields = split(lines[i], ' ');
            if (fields[0] == "valuation_date") valuation = parseDate(fields[1]);
            else if (fields[0] == "settlement_days") settlementDays = std::stoi(fields[1]);
            else if (fields[0] == "scenario") { RawScenario scenario{static_cast<int>(i) + 1, fields[1], {}}; for (std::size_t j = 2; j < fields.size(); ++j) scenario.shifts.push_back(std::stoi(fields[j])); scenarios.push_back(std::move(scenario)); }
            else limits.emplace_back(fields.begin() + 1, fields.end());
        }
    }
};
std::vector<Pillar> validatePillars(int settlement, ErrorLog& errors) {
    std::set<std::string> seen; std::vector<Pillar> result;
    for (const Row& row : readRows("curve_quotes.csv")) {
        const Lines& f = row.fields; std::string error;
        if (!seen.insert(f[0]).second) error = "duplicate pillar";
        else if (!validDate(f[0])) error = "invalid date";
        else if (parseDate(f[0]) <= settlement) error = "pillar not after settlement";
        else if (!frequencies.count(std::stoi(f[2]))) error = "invalid frequency";
        if (!error.empty()) errors.add("curve_quotes.csv", row.line, f[0], error);
        else result.push_back({parseDate(f[0]), std::stoi(f[1]), std::stoi(f[2])});
    }
    std::sort(result.begin(), result.end(), [](const Pillar& a, const Pillar& b) { return a.maturity < b.maturity; }); return result;
}
std::vector<Scenario> validateScenarios(const std::vector<RawScenario>& raw, std::size_t pillars, ErrorLog& errors) {
    std::set<std::string> seen; std::vector<Scenario> result;
    for (const RawScenario& source : raw) {
        std::string error;
        if (!seen.insert(source.name).second) error = "duplicate scenario";
        else if (source.shifts.size() != pillars) error = "wrong number of shifts";
        if (!error.empty()) errors.add("params.txt", source.line, source.name, error);
        else { Scenario scenario{source.name, {}}; for (int shift : source.shifts) scenario.deltas.push_back(shift * 0.0001); result.push_back(std::move(scenario)); }
    }
    return result;
}
Options parseOptions(const std::string& type, const std::string& text) {
    Options result; std::set<std::string> seen;
    if (text != "-") for (const std::string& item : split(text, ';')) {
        std::size_t equal = item.find('='); std::string key = item.substr(0, equal), value = equal == std::string::npos ? "" : item.substr(equal + 1);
        bool allowed = key == "EOM" || key == "LONG" || (type == "FIXED" && key == "CALL") || (type == "AMORT" && key == "SINK") || (type == "FRN" && (key == "LAG" || key == "CAP" || key == "FLOOR"));
        if (!allowed || (!seen.insert(key).second && key != "SINK" && key != "CALL")) throw InputError("invalid option");
        if (key == "EOM") result.eom = true;
        else if (key == "LONG") result.longStub = true;
        else if (key == "LAG") result.lag = std::stoi(value);
        else if (key == "CAP") result.cap = std::stoi(value);
        else if (key == "FLOOR") result.floor = std::stoi(value);
        else { Lines fields = split(value, ':'); auto& list = key == "SINK" ? result.sinks : result.calls; list.push_back({fields[0], key == "SINK" ? std::stoll(fields[1]) : thousandths(fields[1])}); }
    }
    if (type == "FRN" && (result.lag < 1 || result.lag > 5 || result.cap > 1200 || result.floor > (result.cap < 0 ? 1200 : result.cap))) throw InputError("invalid option");
    return result;
}
std::vector<std::pair<int, Integer>> scheduleItems(const std::vector<std::pair<std::string, Integer>>& items, const std::vector<int>& dates, const std::string& reason) {
    std::set<int> inside(dates.begin() + 1, dates.end() - 1); std::vector<std::pair<int, Integer>> result;
    for (const auto& [text, value] : items) {
        if (!validDate(text)) throw InputError(reason);
        int day = parseDate(text); if (!inside.count(day) || (!result.empty() && day <= result.back().first)) throw InputError(reason); result.push_back({day, value});
    }
    return result;
}
Bond parseBond(const Lines& f, const Calendar& calendar, const std::map<int, int>& fixings) {
    if (std::find(types.begin(), types.end(), f[1]) == types.end()) throw InputError("unknown type");
    if (!validDate(f[2]) || !validDate(f[3])) throw InputError("invalid date");
    int issue = parseDate(f[2]), maturity = parseDate(f[3]), coupon = std::stoi(f[4]), frequency = std::stoi(f[5]); Integer face = std::stoll(f[8]);
    if (maturity <= issue) throw InputError("maturity not after issue");
    if (!frequencies.count(frequency)) throw InputError("invalid frequency");
    if (!daycounts.count(f[6])) throw InputError("unknown day count");
    if (!businessRules.count(f[7])) throw InputError("unknown business day rule");
    if (face % 100000 != 0 || face > 10000000) throw InputError("invalid face");
    if (coupon > 1200 || (f[1] == "ZERO" && coupon != 0)) throw InputError("invalid coupon");
    Bond bond{f[0], f[1], issue, maturity, coupon, frequency, f[6], f[7], face, {}, {}, {}, {}, {}};
    bond.options = parseOptions(bond.type, f[9]); bond.schedule = couponSchedule(issue, maturity, frequency, bond.options.eom, bond.options.longStub);
    auto sinks = scheduleItems(bond.options.sinks, bond.schedule, "invalid sinking fund"); Integer total = 0;
    for (const auto& [day, value] : sinks) { if (value == 0) throw InputError("invalid sinking fund"); total += value; bond.sinks[day] = value; }
    if (bond.type == "AMORT" && (total == 0 || total >= face)) throw InputError("invalid sinking fund");
    bond.calls = scheduleItems(bond.options.calls, bond.schedule, "invalid call schedule");
    for (const auto& [day, price] : bond.calls) if (price < 100000 || price > 110000) throw InputError("invalid call schedule");
    Integer opening = face;
    for (std::size_t i = 1; i < bond.schedule.size(); ++i) {
        int start = bond.schedule[i - 1], end = bond.schedule[i], rate = bond.type == "ZERO" ? 0 : coupon;
        if (bond.type == "FRN") {
            int fixing = calendar.move(calendar.adjust(start, bond.bdc), -bond.options.lag); auto found = fixings.upper_bound(fixing);
            if (found == fixings.begin()) throw InputError("missing fixing"); --found; rate += found->second;
            if (bond.options.floor >= 0) rate = std::max(rate, bond.options.floor); if (bond.options.cap >= 0) rate = std::min(rate, bond.options.cap);
        }
        Fraction fraction = yearFraction(bond.daycount, start, end); Integer principal = i + 1 == bond.schedule.size() ? opening : bond.sinks.count(end) ? bond.sinks.at(end) : 0;
        Integer interest = rounded(opening * rate * fraction.numerator, 10000 * fraction.denominator);
        bond.periods.push_back({static_cast<int>(i), start, end, calendar.adjust(end, bond.bdc), fraction, rate, opening, interest, principal}); opening -= principal;
    }
    return bond;
}
std::map<std::string, Bond> validateBonds(const Calendar& calendar, const std::map<int, int>& fixings, ErrorLog& errors) {
    std::map<std::string, Bond> bonds; std::set<std::string> seen;
    for (const Row& row : readRows("bonds.csv")) try {
        if (!seen.insert(row.fields[0]).second) throw InputError("duplicate id");
        Bond bond = parseBond(row.fields, calendar, fixings); bonds.emplace(bond.code, std::move(bond));
    } catch (const InputError& e) { errors.add("bonds.csv", row.line, row.fields[0], e.what()); }
    return bonds;
}
struct Valuation {
    const Bond* bond = nullptr;
    Integer clean = 0, outstanding = 0, accruedAmount = 0, cleanAmount = 0, unitValue = 0;
    std::vector<Period> remaining, cashflows;
    std::vector<Flow> flows;
    YieldPricer pricer;
    double accrued = 0, target = 0, fraction = 0, ytm = 0, ytw = 0, wal = 0, curveClean = 0, spread = 0;
    Risk risk;
    int workout = 0, nextPayment = 0;
    Valuation() = default;
    Valuation(const Bond& source, Integer price, int settlement) : bond(&source), clean(price), workout(source.maturity) {
        std::size_t index = 0; while (source.periods[index].end <= settlement) ++index;
        remaining.assign(source.periods.begin() + index, source.periods.end()); const Period& current = remaining.front(); outstanding = current.opening;
        Fraction elapsed = yearFraction(source.daycount, current.start, settlement); accrued = current.rate * static_cast<double>(elapsed.numerator) / (100 * elapsed.denominator);
        accruedAmount = rounded(outstanding * current.rate * elapsed.numerator, 10000 * elapsed.denominator); cleanAmount = rounded(outstanding * clean, 100000); unitValue = cleanAmount + accruedAmount;
        target = clean / 1000.0 + accrued; Fraction rest = yearFraction(source.daycount, settlement, current.end); fraction = source.frequency * rest.value();
        std::vector<double> yieldFlows;
        for (const Period& period : remaining) { yieldFlows.push_back(static_cast<double>(period.cash())); if (period.cash() >= 1) { cashflows.push_back(period); flows.push_back({period.payment - settlement, static_cast<double>(period.cash())}); } }
        pricer = {std::move(yieldFlows), fraction, source.frequency, outstanding}; nextPayment = cashflows.front().payment;
    }
    void analyze(const ZeroCurve& curve, int settlement) {
        ytm = pricer.solve(target); ytw = ytm; risk = pricer.risk(ytm);
        for (const auto& [day, price] : bond->calls) if (day > settlement) {
            std::vector<double> coupons;
            for (const Period& period : remaining) { coupons.push_back(static_cast<double>(period.coupon)); if (period.end == day) { coupons.back() += rounded(period.opening * price, 100000); break; } }
            double callYield = YieldPricer{coupons, fraction, bond->frequency, outstanding}.solve(target); if (callYield < ytw) { ytw = callYield; workout = day; }
        }
        Integer principalDays = 0; for (const Period& period : cashflows) principalDays += period.principal * (period.payment - settlement);
        wal = static_cast<double>(principalDays) / (365 * outstanding); curveClean = curve.presentValue(flows) * 100 / outstanding - accrued; spread = zSpread(curve, flows, static_cast<double>(unitValue));
    }
};
std::map<std::string, Valuation> validatePrices(const std::map<std::string, Bond>& bonds, int settlement, ErrorLog& errors) {
    std::set<std::string> seen; std::map<std::string, Valuation> result;
    for (const Row& row : readRows("prices.csv")) {
        const std::string& code = row.fields[0]; bool duplicate = !seen.insert(code).second;
        try {
            auto found = bonds.find(code); if (found == bonds.end()) throw InputError("unknown bond"); if (duplicate) throw InputError("duplicate price");
            const Bond& bond = found->second; if (bond.issue > settlement || settlement >= bond.maturity) throw InputError("not outstanding");
            Valuation value(bond, thousandths(row.fields[1]), settlement); if (!(value.pricer.dirty(0) > value.target && value.target > value.pricer.dirty(1))) throw InputError("yield out of range"); result.emplace(code, std::move(value));
        } catch (const InputError& e) { errors.add("prices.csv", row.line, code, e.what()); }
    }
    return result;
}
struct Position {
    Valuation* valuation;
    Integer units = 0, book = 0;
    const Bond& bond() const { return *valuation->bond; }
    Integer value() const { return units * valuation->unitValue; }
    Integer face() const { return units * bond().face; }
    Integer outstanding() const { return units * valuation->outstanding; }
    Integer gain() const { return units * valuation->cleanAmount - book; }
    double dv01() const { return valuation->risk.dv01 * units * valuation->outstanding / 10000; }
    double presentValue(const ZeroCurve& curve) const { return units * curve.presentValue(valuation->flows, valuation->spread); }
};
std::map<std::pair<std::string, std::string>, Position> validateHoldings(const std::map<std::string, Bond>& bonds, std::map<std::string, Valuation>& prices, ErrorLog& errors) {
    std::map<std::pair<std::string, std::string>, Position> positions;
    for (const Row& row : readRows("holdings.csv")) {
        const Lines& f = row.fields;
        try {
            if (!bonds.count(f[1])) throw InputError("unknown bond"); if (!prices.count(f[1])) throw InputError("no price"); Integer face = std::stoll(f[2]); const Bond& bond = bonds.at(f[1]);
            if (face % bond.face != 0) throw InputError("invalid face"); Integer units = face / bond.face;
            auto [where, added] = positions.try_emplace({f[0], f[1]}, Position{&prices.at(f[1])}); Position& position = where->second; position.units += units; position.book += rounded(units * position.valuation->outstanding * thousandths(f[3]), 100000);
        } catch (const InputError& e) { errors.add("holdings.csv", row.line, f[1], e.what()); }
    }
    return positions;
}
struct GroupTotals {
    int count = 0; Integer value = 0; double duration = 0, dv01 = 0;
    void add(const Position& position) { ++count; value += position.value(); duration += static_cast<double>(position.value()) * position.valuation->risk.modified; dv01 += position.dv01(); }
};
struct ScenarioResult { std::string name; std::vector<double> values, pnls; double total = 0, pnl = 0; };
struct Portfolio {
    std::string name;
    std::vector<Position*> positions;
    Integer totalValue = 0, face = 0, outstanding = 0, book = 0, gain = 0, income = 0;
    double ytm = 0, modified = 0, convexity = 0, spread = 0, dv01 = 0, cashYield = 0, baseValue = 0, effective = 0;
    std::vector<double> baseValues, keyRates;
    std::array<GroupTotals, 4> typeTotals;
    std::array<GroupTotals, 5> buckets;
    std::map<int, std::pair<Integer, Integer>> ladder;
    std::vector<ScenarioResult> scenarios;
    double weight(Integer value) const { return static_cast<double>(value) * 100 / totalValue; }
    double presentValue(const ZeroCurve& curve) const { double total = 0; for (const Position* p : positions) total += p->presentValue(curve); return total; }
    double duration(const ZeroCurve& curve, int pillar) const {
        std::vector<double> down(curve.rates.size()), up(curve.rates.size());
        for (std::size_t i = 0; i < down.size(); ++i) if (pillar < 0 || static_cast<int>(i) == pillar) { down[i] = -0.0001; up[i] = 0.0001; }
        return (presentValue(curve.shifted(down)) - presentValue(curve.shifted(up))) / (2 * 0.0001 * baseValue);
    }
    void analyze(const ZeroCurve& curve, const std::vector<Scenario>& shocks, int settlement) {
        std::vector<Flow> allFlows;
        for (Position* p : positions) {
            Valuation& v = *p->valuation; Integer value = p->value(); totalValue += value; face += p->face(); outstanding += p->outstanding(); book += p->book; gain += p->gain();
            ytm += static_cast<double>(value) * v.ytm; modified += static_cast<double>(value) * v.risk.modified; convexity += static_cast<double>(value) * v.risk.convexity; spread += static_cast<double>(value) * v.spread; dv01 += p->dv01();
            for (std::size_t i = 0; i < v.flows.size(); ++i) {
                const Flow& flow = v.flows[i]; const Period& period = v.cashflows[i]; allFlows.push_back({flow.days, p->units * flow.amount});
                if (flow.days <= 365) income += p->units * period.coupon;
                auto& year = ladder[civilDate(period.payment)[0]]; year.first += p->units * period.coupon; year.second += p->units * period.principal;
            }
            int type = static_cast<int>(std::find(types.begin(), types.end(), p->bond().type) - types.begin()); typeTotals[type].add(*p);
            int days = p->bond().maturity - settlement, bucket = 0; const std::array<int, 4> bounds{365, 1095, 1825, 3650}; while (bucket < 4 && days >= bounds[bucket]) ++bucket; buckets[bucket].add(*p);
            double base = p->presentValue(curve); baseValues.push_back(base); baseValue += base;
        }
        ytm /= totalValue; modified /= totalValue; convexity /= totalValue; spread /= totalValue;
        cashYield = bisect([&](double rate) { return ZeroCurve{{0}, {rate}}.presentValue(allFlows); }, 0, 1, static_cast<double>(totalValue));
        effective = duration(curve, -1); for (std::size_t i = 0; i < curve.rates.size(); ++i) keyRates.push_back(duration(curve, static_cast<int>(i)));
        std::vector<Scenario> all{{"BASE", std::vector<double>(curve.rates.size())}}; all.insert(all.end(), shocks.begin(), shocks.end());
        for (const Scenario& shock : all) {
            ZeroCurve shifted = curve.shifted(shock.deltas); ScenarioResult result{shock.name, {}, {}, 0, 0};
            for (std::size_t i = 0; i < positions.size(); ++i) { double value = positions[i]->presentValue(shifted); result.values.push_back(value); result.pnls.push_back(value - baseValues[i]); result.total += value; }
            result.pnl = result.total - baseValue; scenarios.push_back(std::move(result));
        }
    }
    std::string groupLine(const std::string& kind, const std::string& label, const GroupTotals& group) const {
        return join({kind, label, "positions", std::to_string(group.count), "value", hundredths(group.value), "weight", decimal(weight(group.value), 4), "duration", decimal(group.duration / totalValue, 4), "dv01", decimal(group.dv01, 2)});
    }
    Lines report() const {
        Lines lines{"portfolio " + name};
        for (const Position* p : positions) {
            const Valuation& v = *p->valuation;
            lines.push_back(join({"position", p->bond().code, "face", hundredths(p->face()), "outstanding", hundredths(p->outstanding()), "clean", decimal(v.clean / 1000.0, 6), "value", hundredths(p->value()), "weight", decimal(weight(p->value()), 4), "book", hundredths(p->book), "gain", hundredths(p->gain()), "ytm", percent(v.ytm), "modified", decimal(v.risk.modified, 4), "dv01", decimal(p->dv01(), 2)}));
        }
        lines.push_back(join({"total", "positions", std::to_string(positions.size()), "face", hundredths(face), "outstanding", hundredths(outstanding), "value", hundredths(totalValue), "book", hundredths(book), "gain", hundredths(gain), "income", hundredths(income)}));
        lines.push_back(join({"risk", "ytm", percent(ytm), "yield", percent(cashYield), "modified", decimal(modified, 4), "convexity", decimal(convexity, 4), "zspread", percent(spread), "dv01", decimal(dv01, 2)}));
        Lines durationLine{"curve", "effective", decimal(effective, 4), "krd"}; for (double value : keyRates) durationLine.push_back(decimal(value, 4)); lines.push_back(join(durationLine));
        for (std::size_t i = 0; i < types.size(); ++i) lines.push_back(groupLine("type", types[i], typeTotals[i]));
        for (std::size_t i = 0; i < bucketNames.size(); ++i) lines.push_back(groupLine("bucket", bucketNames[i], buckets[i]));
        Integer coupons = 0, principal = 0;
        for (const auto& [year, values] : ladder) { lines.push_back(join({"ladder", std::to_string(year), "coupon", hundredths(values.first), "principal", hundredths(values.second), "total", hundredths(values.first + values.second)})); coupons += values.first; principal += values.second; }
        lines.push_back(join({"ladder", "total", "coupon", hundredths(coupons), "principal", hundredths(principal), "total", hundredths(coupons + principal)}));
        if (scenarios.size() > 1) {
            std::size_t worst = 1; for (std::size_t i = 2; i < scenarios.size(); ++i) if (scenarios[i].pnl < scenarios[worst].pnl) worst = i;
            const ScenarioResult& stress = scenarios[worst]; std::vector<std::size_t> order(positions.size()); std::iota(order.begin(), order.end(), 0);
            std::sort(order.begin(), order.end(), [&](std::size_t a, std::size_t b) { return stress.pnls[a] != stress.pnls[b] ? stress.pnls[a] < stress.pnls[b] : positions[a]->bond().code < positions[b]->bond().code; });
            Lines parts{"stress", "worst", stress.name, "pnl", amount(stress.pnl), "losers"}; for (std::size_t i = 0; i < std::min<std::size_t>(3, order.size()); ++i) { parts.push_back(positions[order[i]]->bond().code); parts.push_back(amount(stress.pnls[order[i]])); } lines.push_back(join(parts));
        }
        return lines;
    }
    Lines scenarioLines() const {
        Lines lines;
        for (const ScenarioResult& result : scenarios) { for (std::size_t i = 0; i < positions.size(); ++i) lines.push_back(join({name, result.name, positions[i]->bond().code, amount(result.values[i]), amount(result.pnls[i])}, ",")); lines.push_back(join({name, result.name, "*", amount(result.total), amount(result.pnl)}, ",")); }
        return lines;
    }
    Lines compliance(const std::vector<Lines>& limits, int settlement) const {
        Lines lines; int breaches = 0;
        for (const Lines& limit : limits) {
            Lines parts{name, limit[0]}; bool breach = false;
            if (limit[0] == "position_weight") {
                const Position* largest = positions.front(); for (const Position* p : positions) if (p->value() > largest->value()) largest = p;
                Integer value = std::stoll(limit[1]); append(parts, {largest->bond().code, decimal(weight(largest->value()), 4), "limit", hundredths(value)}); breach = largest->value() * 10000 > value * totalValue;
            } else if (limit[0] == "type_weight") {
                std::size_t index = std::find(types.begin(), types.end(), limit[1]) - types.begin(); Integer value = std::stoll(limit[2]); append(parts, {limit[1], decimal(weight(typeTotals[index].value), 4), "limit", hundredths(value)}); breach = typeTotals[index].value * 10000 > value * totalValue;
            } else if (limit[0] == "max_maturity") {
                int years = std::stoi(limit[1]), count = 0; for (const Position* p : positions) count += p->bond().maturity - settlement > 365 * years; append(parts, {std::to_string(years) + "Y", "positions", std::to_string(count)}); breach = count > 0;
            } else if (limit[0] == "min_yield") { Integer value = std::stoll(limit[1]); append(parts, {percent(ytm), "limit", hundredths(value)}); breach = ytm * 10000 < value; }
            else if (limit[0] == "duration") { Integer low = std::stoll(limit[1]), high = std::stoll(limit[2]); append(parts, {decimal(modified, 4), "range", hundredths(low), hundredths(high)}); breach = modified < low / 100.0 || modified > high / 100.0; }
            else { Integer value = std::stoll(limit[1]); append(parts, {decimal(dv01, 2), "limit", hundredths(value)}); breach = dv01 * 100 > value; }
            parts.push_back(breach ? "BREACH" : "PASS"); breaches += breach; lines.push_back(join(parts));
        }
        lines.push_back(name + " breaches " + std::to_string(breaches)); return lines;
    }
};
Lines cashflowLines(const std::map<std::string, Bond>& bonds) {
    Lines lines{"bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal"};
    for (const auto& [code, bond] : bonds) for (const Period& p : bond.periods) if (p.cash() >= 1) lines.push_back(join({code, std::to_string(p.number), formatDate(p.start), formatDate(p.end), formatDate(p.payment), decimal(p.fraction.value(), 6), std::to_string(p.rate), std::to_string(p.opening), std::to_string(p.coupon), std::to_string(p.principal)}, ","));
    return lines;
}
Lines analyticsLines(const std::map<std::string, Valuation>& prices) {
    Lines lines{"bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread"};
    for (const auto& [code, v] : prices) lines.push_back(join({code, decimal(v.clean / 1000.0, 6), decimal(v.accrued, 6), decimal(v.target, 6), percent(v.ytm), percent(v.ytw), formatDate(v.workout), formatDate(v.nextPayment), decimal(v.wal, 4), decimal(v.risk.macaulay, 4), decimal(v.risk.modified, 4), decimal(v.risk.convexity, 4), decimal(v.risk.dv01, 6), decimal(v.curveClean, 6), percent(v.spread)}, ","));
    return lines;
}
Lines curveLines(int valuation, int settlement, const std::vector<Pillar>& pillars, const ZeroCurve& curve) {
    Lines lines{"valuation " + formatDate(valuation) + " settlement " + formatDate(settlement)}; int previous = 0;
    for (std::size_t i = 0; i < pillars.size(); ++i) {
        const Pillar& p = pillars[i]; int day = curve.days[i]; lines.push_back(join({"pillar", formatDate(p.maturity), "days", std::to_string(day), "frequency", std::to_string(p.frequency), "par", hundredths(p.coupon), "zero", percent(curve.rates[i]), "df", decimal(curve.discount(day), 6), "forward", percent(curve.forward(previous, day))})); previous = day;
    }
    for (int year = 1; year <= curve.days.back() / 365; ++year) { int day = 365 * year; lines.push_back(join({"grid", std::to_string(year) + "Y", "days", std::to_string(day), "zero", percent(curve.zero(day)), "df", decimal(curve.discount(day), 6), "forward", percent(curve.forward(day - 365, day))})); }
    return lines;
}
}
int main() {
    Parameters params(readLines("params.txt")); Calendar calendar; for (const std::string& text : readLines("calendar.txt")) calendar.holidays.insert(parseDate(text));
    std::map<int, int> fixings; for (const Row& row : readRows("fixings.csv")) fixings[parseDate(row.fields[0])] = std::stoi(row.fields[1]);
    int settlement = calendar.move(params.valuation, params.settlementDays); ErrorLog errors;
    std::vector<Pillar> pillars = validatePillars(settlement, errors); std::vector<Scenario> scenarios = validateScenarios(params.scenarios, pillars.size(), errors);
    std::map<std::string, Bond> bonds = validateBonds(calendar, fixings, errors); std::map<std::string, Valuation> prices = validatePrices(bonds, settlement, errors);
    auto positions = validateHoldings(bonds, prices, errors); ZeroCurve curve = bootstrap(settlement, pillars);
    for (auto& [code, value] : prices) value.analyze(curve, settlement);
    std::map<std::string, std::vector<Position*>> groups; for (auto& [key, position] : positions) groups[key.first].push_back(&position);
    Lines report, scenarioRows{"portfolio,scenario,bond,value,pnl"}, compliance;
    for (auto& [name, members] : groups) { Portfolio portfolio{name, members}; portfolio.analyze(curve, scenarios, settlement); append(report, portfolio.report()); append(scenarioRows, portfolio.scenarioLines()); append(compliance, portfolio.compliance(params.limits, settlement)); }
    std::filesystem::create_directories("output"); save("errors.txt", errors.lines); save("cashflows.csv", cashflowLines(bonds)); save("analytics.csv", analyticsLines(prices)); save("curve.txt", curveLines(params.valuation, settlement, pillars, curve)); save("portfolio.txt", report); save("scenarios.csv", scenarioRows); save("compliance.txt", compliance);
}
