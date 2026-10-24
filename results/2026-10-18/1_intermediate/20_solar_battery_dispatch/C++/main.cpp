#include <algorithm>
#include <cctype>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

using i64 = std::int64_t;
using Settings = std::unordered_map<std::string, i64>;
using Prices = std::vector<std::pair<std::string, i64>>;

const std::vector<std::string> SETTING_NAMES = {
    "CAPACITY", "INITIAL", "CHARGE", "DISCHARGE", "CEFF", "DEFF",
    "RESERVE", "COST", "EXPORT", "FEEDIN", "FIXED", "DEMAND", "PVSCALE"
};
const std::map<std::string, std::pair<i64, i64>> SETTING_RANGES = {
    {"CAPACITY", {1, 100000}}, {"INITIAL", {0, 100}},
    {"CHARGE", {1, 20000}}, {"DISCHARGE", {1, 20000}},
    {"CEFF", {1, 100}}, {"DEFF", {1, 100}},
    {"RESERVE", {0, 100}}, {"COST", {0, 100000}},
    {"EXPORT", {0, 100000}}, {"FEEDIN", {0, 10000}},
    {"FIXED", {0, 100000}}, {"DEMAND", {0, 100000}},
    {"PVSCALE", {0, 300}}
};
const std::map<std::string, std::pair<i64, i64>> STRATEGY_RANGES = {
    {"TOU", {1, 100}}, {"PEAKSHAVE", {0, 100000}}, {"BACKUP", {0, 100}}
};
const std::array<std::string, 8> FLOW_NAMES = {
    "PV>LOAD", "PV>BATTERY", "PV>GRID", "PV>CURTAIL",
    "BATTERY>LOAD", "BATTERY>GRID", "GRID>LOAD", "GRID>BATTERY"
};
const std::array<std::string, 7> DAY_NAMES = {
    "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"
};

struct CommandError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

std::vector<std::string> words(const std::string& line) {
    std::istringstream input(line);
    std::vector<std::string> result;
    for (std::string token; input >> token;) result.push_back(token);
    return result;
}

i64 number(const std::string& s) { return std::stoll(s); }
std::string str(i64 n) { return std::to_string(n); }

i64 value(const Settings& settings, const std::string& key) {
    return settings.at(key);
}
i64 priceOf(const Prices& prices, const std::string& name) {
    for (const auto& [key, price] : prices) if (key == name) return price;
    throw std::logic_error("undefined tariff period");
}

std::string money(i64 amount) {
    i64 cents = std::llabs(amount);
    std::ostringstream out;
    if (amount < 0) out << '-';
    out << cents / 100 << '.' << std::setw(2) << std::setfill('0') << cents % 100;
    return out.str();
}
std::string percentage(i64 numerator, i64 denominator) {
    i64 percent = denominator ? (10000 * numerator / denominator) : 0;
    std::ostringstream out;
    out << percent / 100 << '.' << std::setw(2) << std::setfill('0') << percent % 100;
    return out.str();
}
i64 ceiling(i64 numerator, i64 denominator) {
    return (numerator + denominator - 1) / denominator;
}
std::string padded(const std::string& field, int width) {
    return field.size() < static_cast<std::size_t>(width)
        ? std::string(width - field.size(), ' ') + field : field;
}
std::string tableRow(const std::vector<std::string>& values,
                     const std::vector<int>& widths) {
    std::string line;
    for (std::size_t i = 0; i < values.size(); ++i) line += padded(values[i], widths[i]);
    return line;
}
std::string bar(i64 width) {
    return "|" + std::string(static_cast<std::size_t>(width), '#')
               + std::string(static_cast<std::size_t>(20 - width), '.') + "|";
}
std::pair<std::string, std::string> tariffExtremes(const Prices& prices) {
    std::string cheapest = prices.front().first;
    std::string peak = cheapest;
    for (const auto& [name, cost] : prices) {
        if (cost < priceOf(prices, cheapest)) cheapest = name;
        if (cost > priceOf(prices, peak)) peak = name;
    }
    return {cheapest, peak};
}

struct Strategy {
    std::string name;
    std::optional<i64> parameter;
};
std::string strategyText(const Strategy& strategy) {
    return strategy.name + (strategy.parameter ? " " + str(*strategy.parameter) : "");
}
void requireCount(const std::vector<std::string>& values, std::size_t expected) {
    if (values.size() != expected) throw CommandError("wrong number of arguments");
}
std::vector<Strategy> readStrategies(const std::vector<std::string>& tokens) {
    std::vector<Strategy> result;
    for (std::size_t i = 0; i < tokens.size();) {
        std::string name = tokens[i++];
        if (name == "SELF" || name == "EXPORTPEAK") {
            result.push_back({name, std::nullopt});
            continue;
        }
        auto it = STRATEGY_RANGES.find(name);
        if (it == STRATEGY_RANGES.end()) throw CommandError("unknown strategy " + name);
        if (i == tokens.size()) throw CommandError("missing parameter for " + name);
        i64 parameter = number(tokens[i++]);
        if (parameter < it->second.first || parameter > it->second.second)
            throw CommandError("invalid parameter for " + name);
        result.push_back({name, parameter});
    }
    return result;
}
Strategy oneStrategy(const std::vector<std::string>& tokens) {
    auto result = readStrategies(tokens);
    if (result.size() != 1) throw CommandError("wrong number of arguments");
    return result.front();
}
std::vector<i64> checkedRange(i64 low, i64 high, i64 step,
                              std::pair<i64, i64> limits) {
    if (low < limits.first || high > limits.second || high < low || step < 1 ||
        (high - low) / step + 1 > 20) throw CommandError("invalid range");
    std::vector<i64> values;
    for (i64 i = low; i <= high; i += step) values.push_back(i);
    return values;
}

struct InputData {
    Settings initialSettings;
    Prices initialPrices;
    int dayCount = 0;
    std::vector<i64> loads, basePV;
    std::vector<std::string> dayNames, periods;
    std::vector<bool> weekendDays;
    std::vector<std::string> commands;

    static std::vector<std::string> readPeriodHours(const std::vector<std::string>& tokens) {
        std::vector<std::string> hours;
        for (std::size_t i = 0; i < tokens.size(); i += 2) {
            i64 start = number(tokens[i]);
            i64 end = i + 2 < tokens.size() ? number(tokens[i + 2]) : 24;
            for (i64 h = start; h < end; ++h) hours.push_back(tokens[i + 1]);
        }
        return hours;
    }

    explicit InputData(std::istream& stream) {
        auto read = [&]() {
            std::string line;
            std::getline(stream, line);
            return words(line);
        };
        auto battery = read();
        auto grid = read();
        std::vector<i64> settings;
        for (std::size_t i = 1; i < battery.size(); ++i) settings.push_back(number(battery[i]));
        for (std::size_t i = 1; i < grid.size(); ++i) settings.push_back(number(grid[i]));
        settings.push_back(100);
        for (std::size_t i = 0; i < SETTING_NAMES.size(); ++i)
            initialSettings[SETTING_NAMES[i]] = settings[i];

        int periodCount = static_cast<int>(number(read()[1]));
        for (int i = 0; i < periodCount; ++i) {
            auto row = read();
            initialPrices.emplace_back(row[0], number(row[1]));
        }
        auto wdTokens = read();
        auto weTokens = read();
        auto weekday = readPeriodHours({wdTokens.begin() + 1, wdTokens.end()});
        auto weekend = readPeriodHours({weTokens.begin() + 1, weTokens.end()});

        int profileCount = static_cast<int>(number(read()[1]));
        std::unordered_map<std::string, std::vector<i64>> profiles;
        for (int i = 0; i < profileCount; ++i) {
            auto row = read();
            std::vector<i64> numbers;
            for (std::size_t j = 2; j < row.size(); ++j) numbers.push_back(number(row[j]));
            profiles.emplace(row[0] + "/" + row[1], std::move(numbers));
        }
        dayCount = static_cast<int>(number(read()[1]));
        for (int day = 0; day < dayCount; ++day) {
            auto row = read();
            const auto& load = profiles.at("LOAD/" + row[0]);
            const auto& pv = profiles.at("PV/" + row[2]);
            for (i64 item : load) loads.push_back(item * number(row[1]) / 100);
            for (i64 item : pv) basePV.push_back(item * number(row[3]) / 100);
        }
        auto holidayLine = read();
        std::unordered_set<int> holidays;
        for (std::size_t i = 2; i < holidayLine.size(); ++i)
            holidays.insert(static_cast<int>(number(holidayLine[i])));
        int overrideCount = static_cast<int>(number(read()[1]));
        for (int i = 0; i < overrideCount; ++i) {
            auto row = read();
            auto index = static_cast<std::size_t>((number(row[0]) - 1) * 24 + number(row[1]));
            loads[index] = number(row[2]);
            basePV[index] = number(row[3]);
        }
        for (int day = 1; day <= dayCount; ++day) {
            bool holiday = holidays.count(day) != 0;
            bool weekendDay = holiday || (day - 1) % 7 >= 5;
            weekendDays.push_back(weekendDay);
            dayNames.push_back(holiday ? "HOL" : DAY_NAMES[(day - 1) % 7]);
            const auto& schedule = weekendDay ? weekend : weekday;
            periods.insert(periods.end(), schedule.begin(), schedule.end());
        }
        for (std::string line; std::getline(stream, line);) {
            if (!line.empty()) commands.push_back(line);
        }
    }
};

struct HourRecord {
    i64 index = 0, day = 0, hour = 0;
    std::string period;
    i64 load = 0, pv = 0, soc = 0;
    std::array<i64, 8> flows{};
    i64 charge = 0, discharge = 0, imported = 0, exported = 0, curtailed = 0;
    i64 drawn = 0, shortfall = 0, loss = 0;
    i64 importCost = 0, exportIncome = 0, netCost = 0;

    HourRecord(i64 index_, std::string period_, i64 load_, i64 pv_, i64 soc_,
               std::array<i64, 8> flows_, i64 drawn_, i64 shortfall_, i64 loss_,
               i64 price, i64 feedin)
        : index(index_), day(index_ / 24 + 1), hour(index_ % 24),
          period(std::move(period_)), load(load_), pv(pv_), soc(soc_),
          flows(flows_), drawn(drawn_), shortfall(shortfall_), loss(loss_) {
        charge = flows[1] + flows[7];
        discharge = flows[4] + flows[5];
        imported = flows[6] + flows[7];
        exported = flows[2] + flows[5];
        curtailed = flows[3];
        importCost = imported * price / 100000;
        exportIncome = exported * feedin / 100000;
        netCost = importCost - exportIncome;
    }
};

struct Totals {
    i64 count = 0, load = 0, pv = 0, charge = 0, discharge = 0;
    i64 imported = 0, exported = 0, curtailed = 0, drawn = 0;
    i64 loss = 0, shortfall = 0, importCost = 0, exportIncome = 0, netCost = 0;
    std::array<i64, 8> flows{};

    void add(const HourRecord& record) {
        ++count;
        load += record.load; pv += record.pv;
        charge += record.charge; discharge += record.discharge;
        imported += record.imported; exported += record.exported;
        curtailed += record.curtailed; drawn += record.drawn;
        loss += record.loss; shortfall += record.shortfall;
        importCost += record.importCost; exportIncome += record.exportIncome;
        netCost += record.netCost;
        for (std::size_t i = 0; i < flows.size(); ++i) flows[i] += record.flows[i];
    }
};

struct SimulationResult {
    Strategy strategy;
    Settings settings;
    Prices prices;
    i64 startSOC, reserve, endSOC = 0, peak = 0, demandCharge = 0, bill = 0;
    std::string sufficiency;
    std::vector<HourRecord> hours;
    std::vector<Totals> daily, byPeriod;
    Totals total;

    SimulationResult(Strategy strategy_, Settings settings_, Prices prices_,
                     i64 start, i64 reserve_, std::vector<HourRecord> records)
        : strategy(std::move(strategy_)), settings(std::move(settings_)),
          prices(std::move(prices_)), startSOC(start), reserve(reserve_),
          hours(std::move(records)) {
        for (std::size_t i = 0; i < hours.size(); ++i) {
            if (i % 24 == 0) daily.emplace_back();
            const auto& record = hours[i];
            daily.back().add(record);
            total.add(record);
            peak = std::max(peak, record.imported);
        }
        byPeriod.resize(prices.size());
        for (const auto& record : hours) {
            for (std::size_t i = 0; i < prices.size(); ++i) {
                if (prices[i].first == record.period) {
                    byPeriod[i].add(record);
                    break;
                }
            }
        }
        endSOC = hours.back().soc;
        demandCharge = peak * value(settings, "DEMAND") / 1000;
        bill = total.netCost + value(settings, "FIXED") + demandCharge;
        sufficiency = percentage(std::max<i64>(0, total.load - total.imported), total.load);
    }
};

struct Simulator {
    const InputData& data;
    Strategy strategy;
    Settings settings;
    Prices prices;
    std::optional<std::pair<i64, i64>> outage;
    i64 capacity, ceff, deff, reserve, startSOC, soc;
    std::string cheapest, peak;
    bool arbitrage;

    Simulator(const InputData& data_, Strategy strategy_, Settings settings_, Prices prices_,
              std::optional<std::pair<i64, i64>> outage_ = std::nullopt)
        : data(data_), strategy(std::move(strategy_)), settings(std::move(settings_)),
          prices(std::move(prices_)), outage(outage_),
          capacity(value(settings, "CAPACITY")), ceff(value(settings, "CEFF")),
          deff(value(settings, "DEFF")), reserve(0), startSOC(0), soc(0),
          arbitrage(false) {
        i64 reservePercent = value(settings, "RESERVE");
        if (strategy.name == "BACKUP") reservePercent = std::max(reservePercent, *strategy.parameter);
        reserve = capacity * reservePercent / 100;
        startSOC = capacity * value(settings, "INITIAL") / 100;
        soc = startSOC;
        auto extremes = tariffExtremes(prices);
        cheapest = extremes.first; peak = extremes.second;
        arbitrage = strategy.name == "EXPORTPEAK" &&
                    value(settings, "FEEDIN") > priceOf(prices, cheapest);
    }

    i64 dischargeTarget(i64 deficit, const std::string& period) const {
        if (strategy.name == "TOU") return period == peak ? deficit : 0;
        if (strategy.name == "PEAKSHAVE") return std::max<i64>(0, deficit - *strategy.parameter);
        if (arbitrage && period == cheapest && period != peak) return 0;
        return deficit;
    }

    i64 gridCharge(const std::string& period, i64 pvCharge, i64 gridLoad) {
        i64 headroom = value(settings, "CHARGE") - pvCharge;
        std::optional<i64> target;
        if (strategy.name == "TOU" && period == cheapest && period != peak) {
            target = capacity * *strategy.parameter / 100;
        } else if (strategy.name == "PEAKSHAVE" && period == cheapest) {
            target = capacity;
            headroom = std::min(headroom, std::max<i64>(0, *strategy.parameter - gridLoad));
        } else if (strategy.name == "BACKUP" && period == cheapest) {
            target = reserve;
        } else if (arbitrage && period == cheapest && period != peak) {
            target = capacity;
        }
        if (!target) return 0;
        i64 amount = std::min(headroom,
                              ceiling(100 * std::max<i64>(0, *target - soc), ceff));
        soc += amount * ceff / 100;
        return amount;
    }

    HourRecord runHour(i64 index) {
        i64 load = data.loads[index];
        i64 pv = data.basePV[index] * value(settings, "PVSCALE") / 100;
        const auto& period = data.periods[index];
        i64 direct = std::min(load, pv);
        i64 surplus = pv - direct;
        i64 deficit = load - direct;
        i64 pvCharge = std::min({surplus, value(settings, "CHARGE"),
                                 ceiling(100 * (capacity - soc), ceff)});
        soc += pvCharge * ceff / 100;
        surplus -= pvCharge;
        bool isOutage = outage && outage->first <= index && index <= outage->second;
        i64 target = isOutage ? deficit : dischargeTarget(deficit, period);
        i64 lowerBound = isOutage ? 0 : reserve;
        i64 loadDrawn = std::min({ceiling(100 * target, deff), value(settings, "DISCHARGE"),
                                  std::max<i64>(0, soc - lowerBound)});
        i64 loadDischarge = loadDrawn * deff / 100;
        soc -= loadDrawn;
        deficit -= loadDischarge;
        i64 gridLoad = 0, shortfall = 0, pvExport = 0, curtailed = 0;
        i64 gridCharged = 0, exportDrawn = 0, batteryExport = 0;
        if (isOutage) {
            shortfall = deficit;
            curtailed = surplus;
        } else {
            gridLoad = deficit;
            pvExport = std::min(surplus, value(settings, "EXPORT"));
            curtailed = surplus - pvExport;
            gridCharged = gridCharge(period, pvCharge, gridLoad);
            if (arbitrage && period == peak && pvCharge == 0) {
                exportDrawn = std::min({
                    ceiling(100 * (value(settings, "EXPORT") - pvExport), deff),
                    value(settings, "DISCHARGE") - loadDrawn,
                    std::max<i64>(0, soc - reserve)
                });
                batteryExport = exportDrawn * deff / 100;
                soc -= exportDrawn;
            }
        }
        i64 loss = pvCharge - pvCharge * ceff / 100 +
                   gridCharged - gridCharged * ceff / 100 +
                   loadDrawn - loadDischarge + exportDrawn - batteryExport;
        std::array<i64, 8> flows = {
            direct, pvCharge, pvExport, curtailed, loadDischarge,
            batteryExport, gridLoad, gridCharged
        };
        return HourRecord(index, period, load, pv, soc, flows, loadDrawn + exportDrawn,
                          shortfall, loss, priceOf(prices, period), value(settings, "FEEDIN"));
    }

    SimulationResult run() {
        std::vector<HourRecord> records;
        records.reserve(data.loads.size());
        for (std::size_t i = 0; i < data.loads.size(); ++i) records.push_back(runHour(i));
        return SimulationResult(strategy, settings, prices, startSOC, reserve, std::move(records));
    }
};

class DispatchDesk {
    const InputData& data;
    Settings settings;
    Prices prices;
    std::optional<SimulationResult> current;

    const SimulationResult& requireResult() const {
        if (!current) throw CommandError("no run");
        return *current;
    }
    int checkedDay(const std::string& text) const {
        i64 day = number(text);
        if (day < 1 || day > data.dayCount) throw CommandError("invalid day");
        return static_cast<int>(day);
    }
    const SimulationResult& resultWithoutArguments(const std::vector<std::string>& args) const {
        requireCount(args, 0);
        return requireResult();
    }
    std::pair<int, const SimulationResult&> resultForDay(
        const std::vector<std::string>& args) const {
        requireCount(args, 1);
        int day = checkedDay(args[0]);
        return {day, requireResult()};
    }
    SimulationResult simulate(Strategy strategy, Settings settings_, Prices prices_,
                              std::optional<std::pair<i64, i64>> outage = std::nullopt) const {
        return Simulator(data, std::move(strategy), std::move(settings_),
                         std::move(prices_), outage).run();
    }
    SimulationResult simulate(Strategy strategy) const {
        return simulate(std::move(strategy), settings, prices);
    }
    SimulationResult baseline(Settings settings_, Prices prices_) const {
        settings_["CAPACITY"] = 0;
        return simulate({"SELF", std::nullopt}, std::move(settings_), std::move(prices_));
    }

    std::vector<std::string> run(const std::vector<std::string>& args) {
        Strategy strategy = oneStrategy(args);
        current = simulate(strategy);
        const auto& result = *current;
        const auto& total = result.total;
        return {"RUN " + strategyText(strategy) + " bill " + money(result.bill) +
                " import " + str(total.imported) + " export " + str(total.exported) +
                " soc " + str(result.endSOC)};
    }

    std::vector<std::string> setValue(const std::vector<std::string>& args) {
        requireCount(args, 2);
        auto it = SETTING_RANGES.find(args[0]);
        if (it == SETTING_RANGES.end()) throw CommandError("unknown parameter " + args[0]);
        i64 newValue = number(args[1]);
        if (newValue < it->second.first || newValue > it->second.second)
            throw CommandError("invalid value for " + args[0]);
        i64 oldValue = settings.at(args[0]);
        settings[args[0]] = newValue;
        return {"SET " + args[0] + " " + str(oldValue) + " -> " + str(newValue)};
    }

    std::vector<std::string> changePrice(const std::vector<std::string>& args) {
        requireCount(args, 2);
        auto it = std::find_if(prices.begin(), prices.end(), [&](const auto& p) {
            return p.first == args[0];
        });
        if (it == prices.end()) throw CommandError("unknown period " + args[0]);
        i64 newValue = number(args[1]);
        if (newValue < 0 || newValue > 10000)
            throw CommandError("invalid value for " + args[0]);
        i64 oldValue = it->second;
        it->second = newValue;
        auto [cheapest, peak] = tariffExtremes(prices);
        return {"PRICE " + args[0] + " " + str(oldValue) + " -> " + str(newValue) +
                " cheapest " + cheapest + " peak " + peak};
    }

    std::vector<std::string> reset(const std::vector<std::string>& args) {
        requireCount(args, 0);
        settings = data.initialSettings;
        prices = data.initialPrices;
        return {"RESET"};
    }

    std::vector<std::string> config(const std::vector<std::string>& args) const {
        requireCount(args, 0);
        std::string battery = "BATTERY", grid = "GRID";
        for (std::size_t i = 0; i < 12; ++i) {
            std::string name = SETTING_NAMES[i];
            std::transform(name.begin(), name.end(), name.begin(), [](char c) {
                return static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
            });
            std::string part = " " + name + " " + str(value(settings, SETTING_NAMES[i]));
            (i < 8 ? battery : grid) += part;
        }
        std::string tariff = "TARIFF";
        for (const auto& [name, cost] : prices) tariff += " " + name + " " + str(cost);
        auto [cheapest, peak] = tariffExtremes(prices);
        return {battery, grid, "SOLAR pvscale " + str(value(settings, "PVSCALE")),
                tariff + " cheapest " + cheapest + " peak " + peak};
    }

    std::vector<std::string> noBattery(const std::vector<std::string>& args) const {
        requireCount(args, 0);
        auto result = baseline(settings, prices);
        const auto& total = result.total;
        return {"NOBATTERY bill " + money(result.bill) +
                " import " + str(total.imported) + " export " + str(total.exported) +
                " curtailed " + str(total.curtailed) + " peak " + str(result.peak)};
    }

    std::vector<std::string> compare(const std::vector<std::string>& args) const {
        auto strategies = readStrategies(args);
        if (strategies.empty()) throw CommandError("wrong number of arguments");
        auto noBattery = baseline(settings, prices);
        std::vector<SimulationResult> trials;
        trials.reserve(strategies.size());
        for (const auto& strategy : strategies) trials.push_back(simulate(strategy));
        std::stable_sort(trials.begin(), trials.end(), [](const auto& a, const auto& b) {
            return a.bill < b.bill;
        });
        std::vector<std::string> result = {"COMPARE baseline " + money(noBattery.bill)};
        for (std::size_t i = 0; i < trials.size(); ++i) {
            const auto& trial = trials[i];
            result.push_back(str(i + 1) + ". " + strategyText(trial.strategy) +
                             " bill " + money(trial.bill) +
                             " saving " + money(noBattery.bill - trial.bill) +
                             " sufficiency " + trial.sufficiency + "%");
        }
        return result;
    }

    std::vector<std::string> size(const std::vector<std::string>& args) const {
        requireCount(args, 3);
        auto capacities = checkedRange(number(args[0]), number(args[1]), number(args[2]),
                                       SETTING_RANGES.at("CAPACITY"));
        auto noBattery = baseline(settings, prices);
        std::vector<std::string> lines;
        std::optional<i64> bestCapacity;
        i64 bestCost = 0, bestSaving = 0;
        for (i64 capacity : capacities) {
            Settings trialSettings = settings;
            trialSettings["CAPACITY"] = capacity;
            auto trial = simulate({"SELF", std::nullopt}, trialSettings, prices);
            i64 saving = noBattery.bill - trial.bill;
            i64 cost = capacity * value(trialSettings, "COST") / 1000;
            std::string payback = "never";
            if (saving > 0) {
                i64 tenths = 10 * cost / saving;
                payback = str(tenths / 10) + "." + str(tenths % 10);
                if (!bestCapacity || cost * bestSaving < bestCost * saving) {
                    bestCapacity = capacity;
                    bestCost = cost;
                    bestSaving = saving;
                }
            }
            lines.push_back("SIZE " + str(capacity) + " bill " + money(trial.bill) +
                            " saving " + money(saving) + " cost " + money(cost) +
                            " payback " + payback);
        }
        lines.push_back("BEST " + (bestCapacity ? str(*bestCapacity) : "none"));
        return lines;
    }

    std::vector<std::string> sweep(const std::vector<std::string>& args) const {
        if (args.size() < 5) throw CommandError("wrong number of arguments");
        auto it = SETTING_RANGES.find(args[0]);
        if (it == SETTING_RANGES.end()) throw CommandError("unknown parameter " + args[0]);
        auto values = checkedRange(number(args[1]), number(args[2]), number(args[3]), it->second);
        Strategy strategy = oneStrategy({args.begin() + 4, args.end()});
        std::vector<std::string> lines;
        i64 bestBill = 0, bestValue = 0;
        bool found = false;
        for (i64 settingValue : values) {
            Settings trialSettings = settings;
            trialSettings[args[0]] = settingValue;
            auto trial = simulate(strategy, trialSettings, prices);
            auto noBattery = baseline(trialSettings, prices);
            if (!found || trial.bill < bestBill) {
                found = true;
                bestBill = trial.bill;
                bestValue = settingValue;
            }
            lines.push_back("SWEEP " + args[0] + " " + str(settingValue) +
                            " bill " + money(trial.bill) +
                            " saving " + money(noBattery.bill - trial.bill) +
                            " sufficiency " + trial.sufficiency + "%");
        }
        lines.push_back("BEST " + str(bestValue));
        return lines;
    }

    std::vector<std::string> outage(const std::vector<std::string>& args) const {
        requireCount(args, 3);
        int day = checkedDay(args[0]);
        i64 start = number(args[1]), end = number(args[2]);
        if (start < 0 || start > end || end > 23) throw CommandError("invalid hours");
        const auto& current = requireResult();
        i64 first = (day - 1) * 24 + start;
        i64 last = (day - 1) * 24 + end;
        auto result = simulate(current.strategy, current.settings, current.prices,
                               std::make_pair(first, last));
        i64 before = first > 0 ? result.hours[first - 1].soc : result.startSOC;
        std::vector<std::string> lines = {
            "OUTAGE day " + str(day) + " hours " + str(start) + "-" + str(end) +
                " strategy " + strategyText(result.strategy) + " soc " + str(before),
            "hour   load     pv  disch    soc  short   curt"
        };
        Totals total;
        for (i64 i = first; i <= last; ++i) {
            const auto& r = result.hours[i];
            total.add(r);
            lines.push_back(tableRow({str(r.hour), str(r.load), str(r.pv),
                                      str(r.discharge), str(r.soc), str(r.shortfall),
                                      str(r.curtailed)}, {4, 7, 7, 7, 7, 7, 7}));
        }
        std::string served = total.load
            ? percentage(total.load - total.shortfall, total.load) : "100.00";
        lines.push_back("TOTAL load " + str(total.load) +
                        " unserved " + str(total.shortfall) +
                        " served " + served + "% bill " + money(result.bill));
        return lines;
    }

    std::vector<std::string> diff(const std::vector<std::string>& args) const {
        if (args.size() < 2) throw CommandError("wrong number of arguments");
        int day = checkedDay(args[0]);
        Strategy strategy = oneStrategy({args.begin() + 1, args.end()});
        const auto& current = requireResult();
        auto comparison = simulate(strategy, current.settings, current.prices);
        std::vector<std::string> lines = {
            "DIFF day " + str(day) + " " + data.dayNames[day - 1] + " " +
                strategyText(current.strategy) + " vs " + strategyText(strategy),
            "hour   imp1   imp2   exp1   exp2   soc1   soc2"
        };
        for (int hour = 0; hour < 24; ++hour) {
            const auto& r1 = current.hours[(day - 1) * 24 + hour];
            const auto& r2 = comparison.hours[(day - 1) * 24 + hour];
            lines.push_back(tableRow({str(r1.hour), str(r1.imported), str(r2.imported),
                                      str(r1.exported), str(r2.exported),
                                      str(r1.soc), str(r2.soc)}, {4, 7, 7, 7, 7, 7, 7}));
        }
        i64 cost1 = current.daily[day - 1].netCost;
        i64 cost2 = comparison.daily[day - 1].netCost;
        lines.push_back("TOTAL cost1 " + money(cost1) + " cost2 " + money(cost2) +
                        " difference " + money(cost2 - cost1));
        return lines;
    }

    std::vector<std::string> hourly(const std::vector<std::string>& args) const {
        auto [day, result] = resultForDay(args);
        std::vector<std::string> lines = {
            "HOURLY day " + str(day) + " " + data.dayNames[day - 1] +
                " strategy " + strategyText(result.strategy),
            "hour   load     pv charge  disch    soc import export   curt"
        };
        std::vector<int> widths = {4, 7, 7, 7, 7, 7, 7, 7, 7};
        for (int hour = 0; hour < 24; ++hour) {
            const auto& r = result.hours[(day - 1) * 24 + hour];
            lines.push_back(tableRow({str(r.hour), str(r.load), str(r.pv), str(r.charge),
                                      str(r.discharge), str(r.soc), str(r.imported),
                                      str(r.exported), str(r.curtailed)}, widths));
        }
        const auto& t = result.daily[day - 1];
        lines.push_back(tableRow({"sum", str(t.load), str(t.pv), str(t.charge),
                                  str(t.discharge), "", str(t.imported),
                                  str(t.exported), str(t.curtailed)}, widths));
        return lines;
    }

    std::vector<std::string> daily(const std::vector<std::string>& args) const {
        const auto& result = resultWithoutArguments(args);
        std::vector<std::string> lines = {
            "DAILY strategy " + strategyText(result.strategy),
            "day name    load      pv  import  export    curt     soc      cost"
        };
        for (int day = 1; day <= data.dayCount; ++day) {
            const auto& t = result.daily[day - 1];
            const auto& last = result.hours[day * 24 - 1];
            lines.push_back(tableRow({str(day), data.dayNames[day - 1], str(t.load),
                                      str(t.pv), str(t.imported), str(t.exported),
                                      str(t.curtailed), str(last.soc), money(t.netCost)},
                                     {3, 5, 8, 8, 8, 8, 8, 8, 10}));
        }
        const auto& total = result.total;
        lines.push_back("TOTAL load " + str(total.load) + " pv " + str(total.pv) +
                        " import " + str(total.imported) + " export " + str(total.exported) +
                        " curtailed " + str(total.curtailed) + " cost " + money(total.netCost));
        return lines;
    }

    std::vector<std::string> bill(const std::vector<std::string>& args) const {
        const auto& result = resultWithoutArguments(args);
        std::vector<std::string> lines = {
            "BILL strategy " + strategyText(result.strategy) + " days " + str(data.dayCount)
        };
        for (std::size_t i = 0; i < result.prices.size(); ++i) {
            const auto& t = result.byPeriod[i];
            lines.push_back("IMPORT " + result.prices[i].first + " " + str(t.imported) +
                            " Wh " + money(t.importCost));
        }
        lines.push_back("EXPORT " + str(result.total.exported) +
                        " Wh " + money(-result.total.exportIncome));
        lines.push_back("FIXED " + money(value(result.settings, "FIXED")));
        lines.push_back("DEMAND " + str(result.peak) +
                        " Wh " + money(result.demandCharge));
        lines.push_back("TOTAL " + money(result.bill));
        return lines;
    }

    std::vector<std::string> savings(const std::vector<std::string>& args) const {
        const auto& result = resultWithoutArguments(args);
        auto noBattery = baseline(result.settings, result.prices);
        std::vector<std::string> lines = {
            "SAVINGS strategy " + strategyText(result.strategy)
        };
        auto add = [&](const std::string& label, i64 before, i64 after) {
            lines.push_back(label + " " + money(before) + " -> " + money(after) +
                            " saving " + money(before - after));
        };
        for (std::size_t i = 0; i < result.prices.size(); ++i) {
            add(result.prices[i].first, noBattery.byPeriod[i].importCost,
                result.byPeriod[i].importCost);
        }
        add("EXPORT", -noBattery.total.exportIncome, -result.total.exportIncome);
        add("DEMAND", noBattery.demandCharge, result.demandCharge);
        add("TOTAL", noBattery.bill, result.bill);
        return lines;
    }

    std::vector<std::string> byPeriod(const std::vector<std::string>& args) const {
        const auto& result = resultWithoutArguments(args);
        std::vector<std::string> lines = {
            "BYPERIOD strategy " + strategyText(result.strategy)
        };
        for (std::size_t i = 0; i < result.prices.size(); ++i) {
            const auto& t = result.byPeriod[i];
            lines.push_back(result.prices[i].first + " hours " + str(t.count) +
                            " load " + str(t.load) + " pv " + str(t.pv) +
                            " charge " + str(t.charge) + " discharge " + str(t.discharge) +
                            " import " + str(t.imported) + " export " + str(t.exported));
        }
        return lines;
    }

    std::vector<std::string> dayType(const std::vector<std::string>& args) const {
        const auto& result = resultWithoutArguments(args);
        std::vector<std::string> lines = {
            "DAYTYPE strategy " + strategyText(result.strategy)
        };
        for (bool weekend : {false, true}) {
            Totals t;
            i64 days = 0;
            for (std::size_t day = 0; day < data.weekendDays.size(); ++day) {
                if (data.weekendDays[day] != weekend) continue;
                ++days;
                for (int hour = 0; hour < 24; ++hour)
                    t.add(result.hours[day * 24 + hour]);
            }
            lines.push_back(std::string(weekend ? "WEEKEND" : "WEEKDAY") +
                            " days " + str(days) + " load " + str(t.load / days) +
                            " pv " + str(t.pv / days) + " import " + str(t.imported / days) +
                            " export " + str(t.exported / days) +
                            " cost " + money(t.netCost / days));
        }
        return lines;
    }

    std::vector<std::string> peaks(const std::vector<std::string>& args) const {
        requireCount(args, 1);
        i64 count = number(args[0]);
        if (count < 1) throw CommandError("invalid count");
        const auto& result = requireResult();
        std::vector<const HourRecord*> records;
        for (const auto& record : result.hours) {
            if (record.imported > 0) records.push_back(&record);
        }
        std::sort(records.begin(), records.end(), [](const auto* a, const auto* b) {
            return a->imported != b->imported
                ? a->imported > b->imported : a->index < b->index;
        });
        std::vector<std::string> lines = {
            "PEAKS strategy " + strategyText(result.strategy)
        };
        for (std::size_t i = 0; i < records.size() && i < static_cast<std::size_t>(count); ++i) {
            const auto& r = *records[i];
            lines.push_back(str(i + 1) + ". day " + str(r.day) +
                            " hour " + str(r.hour) + " " + r.period +
                            " import " + str(r.imported) + " load " + str(r.load) +
                            " soc " + str(r.soc));
        }
        if (records.empty()) lines.push_back("none");
        return lines;
    }

    std::vector<std::string> profile(const std::vector<std::string>& args) const {
        const auto& result = resultWithoutArguments(args);
        std::vector<std::string> lines = {
            "PROFILE strategy " + strategyText(result.strategy) + " days " + str(data.dayCount),
            "hour   load     pv import export    soc"
        };
        for (int hour = 0; hour < 24; ++hour) {
            i64 load = 0, pv = 0, imported = 0, exported = 0, soc = 0;
            for (int day = 0; day < data.dayCount; ++day) {
                const auto& r = result.hours[day * 24 + hour];
                load += r.load; pv += r.pv; imported += r.imported;
                exported += r.exported; soc += r.soc;
            }
            i64 count = data.dayCount;
            lines.push_back(tableRow({str(hour), str(load / count), str(pv / count),
                                      str(imported / count), str(exported / count),
                                      str(soc / count)}, {4, 7, 7, 7, 7, 7}));
        }
        return lines;
    }

    std::vector<std::string> flows(const std::vector<std::string>& args) const {
        const auto& result = resultWithoutArguments(args);
        std::vector<std::string> lines = {
            "FLOWS strategy " + strategyText(result.strategy)
        };
        for (std::size_t i = 0; i < FLOW_NAMES.size(); ++i) {
            lines.push_back(FLOW_NAMES[i] + " " + str(result.total.flows[i]));
        }
        lines.push_back("LOSSES " + str(result.total.loss));
        lines.push_back("STORED " + str(result.endSOC - result.startSOC));
        return lines;
    }

    std::vector<std::string> selfSuff(const std::vector<std::string>& args) const {
        const auto& result = resultWithoutArguments(args);
        return {"SELFSUFF sufficiency " + result.sufficiency +
                "% consumption " + percentage(result.total.flows[0] +
                                                result.total.flows[1], result.total.pv) + "%"};
    }

    std::vector<std::string> cycles(const std::vector<std::string>& args) const {
        const auto& result = resultWithoutArguments(args);
        i64 drawn = result.total.drawn;
        i64 capacity = value(result.settings, "CAPACITY");
        i64 common = std::gcd(drawn, capacity);
        i64 numerator = drawn / common, denominator = capacity / common;
        i64 thousandths = 1000 * drawn / capacity;
        std::string decimal = str(thousandths / 1000) + "." +
                              padded(str(thousandths % 1000), 3);
        std::replace(decimal.begin(), decimal.end(), ' ', '0');
        return {"CYCLES " + str(numerator) + "/" + str(denominator) +
                " " + decimal + " drawn " + str(drawn) +
                " losses " + str(result.total.loss)};
    }

    std::vector<std::string> usage(const std::vector<std::string>& args) const {
        const auto& result = resultWithoutArguments(args);
        i64 charging = 0, discharging = 0, idle = 0, full = 0, low = 0;
        i64 run = 0, longest = 0;
        const HourRecord* first = nullptr;
        for (const auto& record : result.hours) {
            charging += record.charge > 0;
            discharging += record.drawn > 0;
            idle += record.charge == 0 && record.drawn == 0;
            full += record.soc == value(result.settings, "CAPACITY");
            if (record.soc <= result.reserve) {
                ++low;
                ++run;
                if (run > longest) {
                    longest = run;
                    first = &result.hours[record.index - run + 1];
                }
            } else {
                run = 0;
            }
        }
        std::string line = "USAGE charging " + str(charging) +
                           " discharging " + str(discharging) + " idle " + str(idle) +
                           " full " + str(full) + " low " + str(low) +
                           " longest " + str(longest);
        if (first) line += " from day " + str(first->day) + " hour " + str(first->hour);
        return {line};
    }

    std::vector<std::string> histogram(const std::vector<std::string>& args) const {
        const auto& result = resultWithoutArguments(args);
        std::array<i64, 10> counts{};
        i64 capacity = value(result.settings, "CAPACITY");
        for (const auto& r : result.hours) {
            ++counts[std::min<i64>(9, 10 * r.soc / capacity)];
        }
        std::vector<std::string> lines = {
            "HISTOGRAM strategy " + strategyText(result.strategy)
        };
        for (int i = 0; i < 10; ++i) {
            i64 width = 20 * counts[i] / result.hours.size();
            lines.push_back(padded(str(i * 10), 3) + "% " + bar(width) +
                            " " + str(counts[i]));
        }
        return lines;
    }

    std::vector<std::string> chart(const std::vector<std::string>& args) const {
        auto [day, result] = resultForDay(args);
        i64 capacity = value(result.settings, "CAPACITY");
        std::vector<std::string> lines = {
            "CHART day " + str(day) + " " + data.dayNames[day - 1] +
                " strategy " + strategyText(result.strategy)
        };
        for (int hour = 0; hour < 24; ++hour) {
            const auto& record = result.hours[(day - 1) * 24 + hour];
            i64 width = 20 * record.soc / capacity;
            lines.push_back(padded(str(record.hour), 2) + " " + bar(width) +
                            " " + percentage(record.soc, capacity) + "%");
        }
        return lines;
    }

public:
    explicit DispatchDesk(const InputData& data_)
        : data(data_), settings(data.initialSettings), prices(data.initialPrices) {}

    std::vector<std::string> execute(const std::vector<std::string>& tokens) {
        const std::string& cmd = tokens[0];
        std::vector<std::string> args(tokens.begin() + 1, tokens.end());
        try {
            if (cmd == "RUN") return run(args);
            if (cmd == "SET") return setValue(args);
            if (cmd == "PRICE") return changePrice(args);
            if (cmd == "RESET") return reset(args);
            if (cmd == "CONFIG") return config(args);
            if (cmd == "NOBATTERY") return noBattery(args);
            if (cmd == "COMPARE") return compare(args);
            if (cmd == "SIZE") return size(args);
            if (cmd == "SWEEP") return sweep(args);
            if (cmd == "OUTAGE") return outage(args);
            if (cmd == "DIFF") return diff(args);
            if (cmd == "HOURLY") return hourly(args);
            if (cmd == "DAILY") return daily(args);
            if (cmd == "BILL") return bill(args);
            if (cmd == "SAVINGS") return savings(args);
            if (cmd == "BYPERIOD") return byPeriod(args);
            if (cmd == "DAYTYPE") return dayType(args);
            if (cmd == "PEAKS") return peaks(args);
            if (cmd == "PROFILE") return profile(args);
            if (cmd == "FLOWS") return flows(args);
            if (cmd == "SELFSUFF") return selfSuff(args);
            if (cmd == "CYCLES") return cycles(args);
            if (cmd == "USAGE") return usage(args);
            if (cmd == "HISTOGRAM") return histogram(args);
            if (cmd == "CHART") return chart(args);
            return {"ERROR unknown command " + cmd};
        } catch (const CommandError& error) {
            return {"ERROR " + std::string(error.what())};
        }
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    InputData data(std::cin);
    DispatchDesk desk(data);
    for (const auto& line : data.commands) {
        auto tokens = words(line);
        if (tokens[0] == "END") break;
        for (const auto& result : desk.execute(tokens)) std::cout << result << '\n';
    }
}
