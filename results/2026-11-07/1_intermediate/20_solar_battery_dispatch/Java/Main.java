import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

public final class Main {
    private static final String[] SETTING_NAMES = {
        "CAPACITY", "INITIAL", "CHARGE", "DISCHARGE", "CEFF", "DEFF",
        "RESERVE", "COST", "EXPORT", "FEEDIN", "FIXED", "DEMAND", "PVSCALE"
    };
    private static final String[] DAY_NAMES = {
        "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"
    };
    private static final String[] FLOW_NAMES = {
        "PV>LOAD", "PV>BATTERY", "PV>GRID", "PV>CURTAIL",
        "BATTERY>LOAD", "BATTERY>GRID", "GRID>LOAD", "GRID>BATTERY"
    };
    private static final Map<String, long[]> SETTING_RANGES = Map.ofEntries(
        Map.entry("CAPACITY", new long[]{1, 100000}),
        Map.entry("INITIAL", new long[]{0, 100}),
        Map.entry("CHARGE", new long[]{1, 20000}),
        Map.entry("DISCHARGE", new long[]{1, 20000}),
        Map.entry("CEFF", new long[]{1, 100}),
        Map.entry("DEFF", new long[]{1, 100}),
        Map.entry("RESERVE", new long[]{0, 100}),
        Map.entry("COST", new long[]{0, 100000}),
        Map.entry("EXPORT", new long[]{0, 100000}),
        Map.entry("FEEDIN", new long[]{0, 10000}),
        Map.entry("FIXED", new long[]{0, 100000}),
        Map.entry("DEMAND", new long[]{0, 100000}),
        Map.entry("PVSCALE", new long[]{0, 300})
    );
    private static final Map<String, long[]> STRATEGY_RANGES = Map.of(
        "TOU", new long[]{1, 100},
        "PEAKSHAVE", new long[]{0, 100000},
        "BACKUP", new long[]{0, 100}
    );

    private static final class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    private static long number(String text) { return Long.parseLong(text); }
    private static long value(Map<String, Long> map, String key) { return map.get(key); }
    private static String money(long cents) {
        long absolute = Math.abs(cents);
        return (cents < 0 ? "-" : "") + absolute / 100 + "." +
            String.format("%02d", absolute % 100);
    }
    private static String percentage(long numerator, long denominator) {
        long value = denominator == 0 ? 0 : 10000 * numerator / denominator;
        return value / 100 + "." + String.format("%02d", value % 100);
    }
    private static long ceiling(long numerator, long denominator) {
        return (numerator + denominator - 1) / denominator;
    }
    private static String bar(long width) {
        return "|" + "#".repeat((int) width) + ".".repeat((int) (20 - width)) + "|";
    }
    private static String row(Object[] cells, int... widths) {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < cells.length; ++i) {
            String text = String.valueOf(cells[i]);
            result.append(" ".repeat(Math.max(0, widths[i] - text.length()))).append(text);
        }
        return result.toString();
    }
    private static String[] words(String line) { return line.split(" "); }
    private static void requireCount(List<String> args, int count) {
        if (args.size() != count) throw new CommandError("wrong number of arguments");
    }
    private static long gcd(long a, long b) {
        while (b != 0) {
            long next = a % b;
            a = b;
            b = next;
        }
        return a;
    }
    private static String[] tariffExtremes(Map<String, Long> prices) {
        String cheapest = prices.keySet().iterator().next();
        String peak = cheapest;
        for (Map.Entry<String, Long> item : prices.entrySet()) {
            if (item.getValue() < prices.get(cheapest)) cheapest = item.getKey();
            if (item.getValue() > prices.get(peak)) peak = item.getKey();
        }
        return new String[]{cheapest, peak};
    }

    private record Strategy(String name, Long parameter) {
        String text() { return parameter == null ? name : name + " " + parameter; }
    }
    private static List<Strategy> strategies(List<String> tokens) {
        List<Strategy> result = new ArrayList<>();
        for (int i = 0; i < tokens.size();) {
            String name = tokens.get(i++);
            if (name.equals("SELF") || name.equals("EXPORTPEAK")) {
                result.add(new Strategy(name, null));
                continue;
            }
            long[] limits = STRATEGY_RANGES.get(name);
            if (limits == null) throw new CommandError("unknown strategy " + name);
            if (i == tokens.size()) throw new CommandError("missing parameter for " + name);
            long parameter = number(tokens.get(i++));
            if (parameter < limits[0] || parameter > limits[1])
                throw new CommandError("invalid parameter for " + name);
            result.add(new Strategy(name, parameter));
        }
        return result;
    }
    private static Strategy oneStrategy(List<String> args) {
        List<Strategy> parsed = strategies(args);
        if (parsed.size() != 1) throw new CommandError("wrong number of arguments");
        return parsed.get(0);
    }
    private static List<Long> checkedRange(long low, long high, long step, long[] limits) {
        if (low < limits[0] || high > limits[1] || high < low || step < 1 ||
            (high - low) / step + 1 > 20) throw new CommandError("invalid range");
        List<Long> result = new ArrayList<>();
        for (long value = low; value <= high; value += step) result.add(value);
        return result;
    }

    private static final class InputData {
        final Map<String, Long> initialSettings = new HashMap<>();
        final LinkedHashMap<String, Long> initialPrices = new LinkedHashMap<>();
        final List<Long> loads = new ArrayList<>();
        final List<Long> basePV = new ArrayList<>();
        final List<String> dayNames = new ArrayList<>();
        final List<String> periods = new ArrayList<>();
        final List<Boolean> weekendDays = new ArrayList<>();
        final List<String> commands = new ArrayList<>();
        final int dayCount;

        private static List<String> periodHours(String[] tokens) {
            List<String> result = new ArrayList<>();
            for (int i = 1; i < tokens.length; i += 2) {
                int start = (int) number(tokens[i]);
                int end = i + 2 < tokens.length ? (int) number(tokens[i + 2]) : 24;
                for (int hour = start; hour < end; ++hour) result.add(tokens[i + 1]);
            }
            return result;
        }

        InputData(BufferedReader reader) throws IOException {
            String[] battery = words(reader.readLine());
            String[] grid = words(reader.readLine());
            List<Long> settings = new ArrayList<>();
            for (int i = 1; i < battery.length; ++i) settings.add(number(battery[i]));
            for (int i = 1; i < grid.length; ++i) settings.add(number(grid[i]));
            settings.add(100L);
            for (int i = 0; i < SETTING_NAMES.length; ++i)
                initialSettings.put(SETTING_NAMES[i], settings.get(i));
            int periodCount = (int) number(words(reader.readLine())[1]);
            for (int i = 0; i < periodCount; ++i) {
                String[] line = words(reader.readLine());
                initialPrices.put(line[0], number(line[1]));
            }
            List<String> weekday = periodHours(words(reader.readLine()));
            List<String> weekend = periodHours(words(reader.readLine()));
            int profileCount = (int) number(words(reader.readLine())[1]);
            Map<String, long[]> profiles = new HashMap<>();
            for (int i = 0; i < profileCount; ++i) {
                String[] line = words(reader.readLine());
                long[] profile = new long[line.length - 2];
                for (int j = 2; j < line.length; ++j) profile[j - 2] = number(line[j]);
                profiles.put(line[0] + "/" + line[1], profile);
            }
            dayCount = (int) number(words(reader.readLine())[1]);
            for (int day = 0; day < dayCount; ++day) {
                String[] line = words(reader.readLine());
                long[] load = profiles.get("LOAD/" + line[0]);
                long[] pv = profiles.get("PV/" + line[2]);
                for (long v : load) loads.add(v * number(line[1]) / 100);
                for (long v : pv) basePV.add(v * number(line[3]) / 100);
            }
            String[] holidayLine = words(reader.readLine());
            Set<Integer> holidays = new HashSet<>();
            for (int i = 2; i < holidayLine.length; ++i)
                holidays.add((int) number(holidayLine[i]));
            int overrideCount = (int) number(words(reader.readLine())[1]);
            for (int i = 0; i < overrideCount; ++i) {
                String[] line = words(reader.readLine());
                int index = (int) ((number(line[0]) - 1) * 24 + number(line[1]));
                loads.set(index, number(line[2]));
                basePV.set(index, number(line[3]));
            }
            for (int day = 1; day <= dayCount; ++day) {
                boolean holiday = holidays.contains(day);
                boolean weekendDay = holiday || (day - 1) % 7 >= 5;
                weekendDays.add(weekendDay);
                dayNames.add(holiday ? "HOL" : DAY_NAMES[(day - 1) % 7]);
                periods.addAll(weekendDay ? weekend : weekday);
            }
            for (String line; (line = reader.readLine()) != null;)
                if (!line.isEmpty()) commands.add(line);
        }
    }

    private static final class HourRecord {
        final int index, day, hour;
        final String period;
        final long load, pv, soc;
        final long[] flows;
        final long charge, discharge, imported, exported, curtailed;
        final long drawn, shortfall, loss, importCost, exportIncome, netCost;

        HourRecord(int index, String period, long load, long pv, long soc, long[] flows,
                   long drawn, long shortfall, long loss, long price, long feedin) {
            this.index = index;
            this.day = index / 24 + 1;
            this.hour = index % 24;
            this.period = period;
            this.load = load;
            this.pv = pv;
            this.soc = soc;
            this.flows = flows;
            this.charge = flows[1] + flows[7];
            this.discharge = flows[4] + flows[5];
            this.imported = flows[6] + flows[7];
            this.exported = flows[2] + flows[5];
            this.curtailed = flows[3];
            this.drawn = drawn;
            this.shortfall = shortfall;
            this.loss = loss;
            this.importCost = imported * price / 100000;
            this.exportIncome = exported * feedin / 100000;
            this.netCost = importCost - exportIncome;
        }
    }

    private static final class Totals {
        long count, load, pv, charge, discharge, imported, exported, curtailed;
        long drawn, loss, shortfall, importCost, exportIncome, netCost;
        final long[] flows = new long[8];

        void add(HourRecord row) {
            ++count;
            load += row.load; pv += row.pv;
            charge += row.charge; discharge += row.discharge;
            imported += row.imported; exported += row.exported;
            curtailed += row.curtailed; drawn += row.drawn;
            loss += row.loss; shortfall += row.shortfall;
            importCost += row.importCost; exportIncome += row.exportIncome;
            netCost += row.netCost;
            for (int i = 0; i < flows.length; ++i) flows[i] += row.flows[i];
        }
    }

    private static final class SimulationResult {
        final Strategy strategy;
        final Map<String, Long> settings;
        final LinkedHashMap<String, Long> prices;
        final long startSOC, reserve, endSOC, peak, demandCharge, bill;
        final String sufficiency;
        final List<HourRecord> hours;
        final List<Totals> daily = new ArrayList<>();
        final LinkedHashMap<String, Totals> byPeriod = new LinkedHashMap<>();
        final Totals total = new Totals();

        SimulationResult(Strategy strategy, Map<String, Long> settings,
                         LinkedHashMap<String, Long> prices, long startSOC,
                         long reserve, List<HourRecord> hours) {
            this.strategy = strategy;
            this.settings = new HashMap<>(settings);
            this.prices = new LinkedHashMap<>(prices);
            this.startSOC = startSOC;
            this.reserve = reserve;
            this.hours = hours;
            for (String name : prices.keySet()) byPeriod.put(name, new Totals());
            long maximum = 0;
            for (int i = 0; i < hours.size(); ++i) {
                if (i % 24 == 0) daily.add(new Totals());
                HourRecord row = hours.get(i);
                daily.get(daily.size() - 1).add(row);
                byPeriod.get(row.period).add(row);
                total.add(row);
                maximum = Math.max(maximum, row.imported);
            }
            peak = maximum;
            endSOC = hours.get(hours.size() - 1).soc;
            demandCharge = peak * value(settings, "DEMAND") / 1000;
            bill = total.netCost + value(settings, "FIXED") + demandCharge;
            sufficiency = percentage(Math.max(0, total.load - total.imported), total.load);
        }
    }

    private static final class Simulator {
        final InputData data;
        final Strategy strategy;
        final Map<String, Long> settings;
        final LinkedHashMap<String, Long> prices;
        final int[] outage;
        final long capacity, ceff, deff, reserve, startSOC;
        final String cheapest, peak;
        final boolean arbitrage;
        long soc;

        Simulator(InputData data, Strategy strategy, Map<String, Long> settings,
                  LinkedHashMap<String, Long> prices, int[] outage) {
            this.data = data;
            this.strategy = strategy;
            this.settings = new HashMap<>(settings);
            this.prices = new LinkedHashMap<>(prices);
            this.outage = outage;
            capacity = value(settings, "CAPACITY");
            ceff = value(settings, "CEFF");
            deff = value(settings, "DEFF");
            long reservePercent = value(settings, "RESERVE");
            if (strategy.name.equals("BACKUP"))
                reservePercent = Math.max(reservePercent, strategy.parameter);
            reserve = capacity * reservePercent / 100;
            startSOC = capacity * value(settings, "INITIAL") / 100;
            soc = startSOC;
            String[] extremes = tariffExtremes(prices);
            cheapest = extremes[0];
            peak = extremes[1];
            arbitrage = strategy.name.equals("EXPORTPEAK") &&
                value(settings, "FEEDIN") > prices.get(cheapest);
        }

        private long dischargeTarget(long deficit, String period) {
            if (strategy.name.equals("TOU")) return period.equals(peak) ? deficit : 0;
            if (strategy.name.equals("PEAKSHAVE"))
                return Math.max(0, deficit - strategy.parameter);
            if (arbitrage && period.equals(cheapest) && !period.equals(peak)) return 0;
            return deficit;
        }

        private long gridCharge(String period, long pvCharge, long gridLoad) {
            long headroom = value(settings, "CHARGE") - pvCharge;
            Long target = null;
            if (strategy.name.equals("TOU") && period.equals(cheapest) && !period.equals(peak)) {
                target = capacity * strategy.parameter / 100;
            } else if (strategy.name.equals("PEAKSHAVE") && period.equals(cheapest)) {
                target = capacity;
                headroom = Math.min(headroom, Math.max(0, strategy.parameter - gridLoad));
            } else if (strategy.name.equals("BACKUP") && period.equals(cheapest)) {
                target = reserve;
            } else if (arbitrage && period.equals(cheapest) && !period.equals(peak)) {
                target = capacity;
            }
            if (target == null) return 0;
            long amount = Math.min(headroom, ceiling(100 * Math.max(0, target - soc), ceff));
            soc += amount * ceff / 100;
            return amount;
        }

        private HourRecord runHour(int index) {
            long load = data.loads.get(index);
            long pv = data.basePV.get(index) * value(settings, "PVSCALE") / 100;
            String period = data.periods.get(index);
            long direct = Math.min(load, pv);
            long surplus = pv - direct;
            long deficit = load - direct;
            long pvCharge = Math.min(Math.min(surplus, value(settings, "CHARGE")),
                ceiling(100 * (capacity - soc), ceff));
            soc += pvCharge * ceff / 100;
            surplus -= pvCharge;
            boolean isOutage = outage != null && outage[0] <= index && index <= outage[1];
            long target = isOutage ? deficit : dischargeTarget(deficit, period);
            long lowerBound = isOutage ? 0 : reserve;
            long loadDrawn = Math.min(Math.min(ceiling(100 * target, deff),
                value(settings, "DISCHARGE")), Math.max(0, soc - lowerBound));
            long loadDischarge = loadDrawn * deff / 100;
            soc -= loadDrawn;
            deficit -= loadDischarge;
            long gridLoad = 0, shortfall = 0, pvExport = 0, curtailed = 0;
            long gridCharge = 0, exportDrawn = 0, batteryExport = 0;
            if (isOutage) {
                shortfall = deficit;
                curtailed = surplus;
            } else {
                gridLoad = deficit;
                pvExport = Math.min(surplus, value(settings, "EXPORT"));
                curtailed = surplus - pvExport;
                gridCharge = gridCharge(period, pvCharge, gridLoad);
                if (arbitrage && period.equals(peak) && pvCharge == 0) {
                    exportDrawn = Math.min(Math.min(
                        ceiling(100 * (value(settings, "EXPORT") - pvExport), deff),
                        value(settings, "DISCHARGE") - loadDrawn),
                        Math.max(0, soc - reserve));
                    batteryExport = exportDrawn * deff / 100;
                    soc -= exportDrawn;
                }
            }
            long loss = pvCharge - pvCharge * ceff / 100 +
                gridCharge - gridCharge * ceff / 100 +
                loadDrawn - loadDischarge + exportDrawn - batteryExport;
            long[] flows = {direct, pvCharge, pvExport, curtailed,
                loadDischarge, batteryExport, gridLoad, gridCharge};
            return new HourRecord(index, period, load, pv, soc, flows,
                loadDrawn + exportDrawn, shortfall, loss, prices.get(period),
                value(settings, "FEEDIN"));
        }

        SimulationResult run() {
            List<HourRecord> records = new ArrayList<>(data.loads.size());
            for (int i = 0; i < data.loads.size(); ++i) records.add(runHour(i));
            return new SimulationResult(strategy, settings, prices, startSOC, reserve, records);
        }
    }

    private static final class DispatchDesk {
        final InputData data;
        Map<String, Long> settings;
        LinkedHashMap<String, Long> prices;
        SimulationResult current;

        DispatchDesk(InputData data) {
            this.data = data;
            this.settings = new HashMap<>(data.initialSettings);
            this.prices = new LinkedHashMap<>(data.initialPrices);
        }
        private SimulationResult requireResult() {
            if (current == null) throw new CommandError("no run");
            return current;
        }
        private int checkedDay(String token) {
            long day = number(token);
            if (day < 1 || day > data.dayCount) throw new CommandError("invalid day");
            return (int) day;
        }
        private SimulationResult withoutArgs(List<String> args) {
            requireCount(args, 0);
            return requireResult();
        }
        private int dayForResult(List<String> args) {
            requireCount(args, 1);
            int day = checkedDay(args.get(0));
            requireResult();
            return day;
        }
        private SimulationResult simulate(Strategy strategy, Map<String, Long> settings,
                                          LinkedHashMap<String, Long> prices, int[] outage) {
            return new Simulator(data, strategy, settings, prices, outage).run();
        }
        private SimulationResult simulate(Strategy strategy) {
            return simulate(strategy, settings, prices, null);
        }
        private SimulationResult baseline(Map<String, Long> settings,
                                          LinkedHashMap<String, Long> prices) {
            Map<String, Long> noBattery = new HashMap<>(settings);
            noBattery.put("CAPACITY", 0L);
            return simulate(new Strategy("SELF", null), noBattery, prices, null);
        }

        private List<String> run(List<String> args) {
            Strategy strategy = oneStrategy(args);
            current = simulate(strategy);
            Totals t = current.total;
            return List.of("RUN " + strategy.text() + " bill " + money(current.bill) +
                " import " + t.imported + " export " + t.exported + " soc " + current.endSOC);
        }
        private List<String> setValue(List<String> args) {
            requireCount(args, 2);
            String key = args.get(0);
            long[] limits = SETTING_RANGES.get(key);
            if (limits == null) throw new CommandError("unknown parameter " + key);
            long next = number(args.get(1));
            if (next < limits[0] || next > limits[1])
                throw new CommandError("invalid value for " + key);
            long old = settings.get(key);
            settings.put(key, next);
            return List.of("SET " + key + " " + old + " -> " + next);
        }
        private List<String> changePrice(List<String> args) {
            requireCount(args, 2);
            String name = args.get(0);
            if (!prices.containsKey(name)) throw new CommandError("unknown period " + name);
            long next = number(args.get(1));
            if (next < 0 || next > 10000)
                throw new CommandError("invalid value for " + name);
            long old = prices.put(name, next);
            String[] extremes = tariffExtremes(prices);
            return List.of("PRICE " + name + " " + old + " -> " + next +
                " cheapest " + extremes[0] + " peak " + extremes[1]);
        }
        private List<String> reset(List<String> args) {
            requireCount(args, 0);
            settings = new HashMap<>(data.initialSettings);
            prices = new LinkedHashMap<>(data.initialPrices);
            return List.of("RESET");
        }
        private List<String> config(List<String> args) {
            requireCount(args, 0);
            StringBuilder battery = new StringBuilder("BATTERY");
            StringBuilder grid = new StringBuilder("GRID");
            for (int i = 0; i < 12; ++i) {
                String name = SETTING_NAMES[i];
                (i < 8 ? battery : grid).append(' ').append(name.toLowerCase())
                    .append(' ').append(settings.get(name));
            }
            StringBuilder tariff = new StringBuilder("TARIFF");
            for (Map.Entry<String, Long> row : prices.entrySet())
                tariff.append(' ').append(row.getKey()).append(' ').append(row.getValue());
            String[] extremes = tariffExtremes(prices);
            tariff.append(" cheapest ").append(extremes[0]).append(" peak ").append(extremes[1]);
            return List.of(battery.toString(), grid.toString(),
                "SOLAR pvscale " + value(settings, "PVSCALE"), tariff.toString());
        }
        private List<String> noBattery(List<String> args) {
            requireCount(args, 0);
            SimulationResult result = baseline(settings, prices);
            Totals t = result.total;
            return List.of("NOBATTERY bill " + money(result.bill) + " import " +
                t.imported + " export " + t.exported + " curtailed " +
                t.curtailed + " peak " + result.peak);
        }
        private List<String> compare(List<String> args) {
            List<Strategy> options = strategies(args);
            if (options.isEmpty()) throw new CommandError("wrong number of arguments");
            SimulationResult noBattery = baseline(settings, prices);
            List<SimulationResult> trials = new ArrayList<>();
            for (Strategy option : options) trials.add(simulate(option));
            trials.sort(Comparator.comparingLong(r -> r.bill));
            List<String> output = new ArrayList<>();
            output.add("COMPARE baseline " + money(noBattery.bill));
            for (int i = 0; i < trials.size(); ++i) {
                SimulationResult r = trials.get(i);
                output.add((i + 1) + ". " + r.strategy.text() +
                    " bill " + money(r.bill) + " saving " + money(noBattery.bill - r.bill) +
                    " sufficiency " + r.sufficiency + "%");
            }
            return output;
        }
        private List<String> size(List<String> args) {
            requireCount(args, 3);
            List<Long> capacities = checkedRange(number(args.get(0)), number(args.get(1)),
                number(args.get(2)), SETTING_RANGES.get("CAPACITY"));
            SimulationResult noBattery = baseline(settings, prices);
            List<String> output = new ArrayList<>();
            Long bestCapacity = null;
            long bestCost = 0, bestSaving = 0;
            for (long capacity : capacities) {
                Map<String, Long> trialSettings = new HashMap<>(settings);
                trialSettings.put("CAPACITY", capacity);
                SimulationResult trial = simulate(new Strategy("SELF", null),
                    trialSettings, prices, null);
                long saving = noBattery.bill - trial.bill;
                long cost = capacity * value(trialSettings, "COST") / 1000;
                String payback = "never";
                if (saving > 0) {
                    long tenths = 10 * cost / saving;
                    payback = tenths / 10 + "." + tenths % 10;
                    if (bestCapacity == null || cost * bestSaving < bestCost * saving) {
                        bestCapacity = capacity;
                        bestCost = cost;
                        bestSaving = saving;
                    }
                }
                output.add("SIZE " + capacity + " bill " + money(trial.bill) +
                    " saving " + money(saving) + " cost " + money(cost) +
                    " payback " + payback);
            }
            output.add("BEST " + (bestCapacity == null ? "none" : bestCapacity));
            return output;
        }
        private List<String> sweep(List<String> args) {
            if (args.size() < 5) throw new CommandError("wrong number of arguments");
            String name = args.get(0);
            long[] limits = SETTING_RANGES.get(name);
            if (limits == null) throw new CommandError("unknown parameter " + name);
            List<Long> values = checkedRange(number(args.get(1)), number(args.get(2)),
                number(args.get(3)), limits);
            Strategy option = oneStrategy(args.subList(4, args.size()));
            List<String> output = new ArrayList<>();
            Long bestValue = null;
            long bestBill = 0;
            for (long v : values) {
                Map<String, Long> trialSettings = new HashMap<>(settings);
                trialSettings.put(name, v);
                SimulationResult trial = simulate(option, trialSettings, prices, null);
                SimulationResult noBattery = baseline(trialSettings, prices);
                if (bestValue == null || trial.bill < bestBill) {
                    bestValue = v;
                    bestBill = trial.bill;
                }
                output.add("SWEEP " + name + " " + v + " bill " + money(trial.bill) +
                    " saving " + money(noBattery.bill - trial.bill) +
                    " sufficiency " + trial.sufficiency + "%");
            }
            output.add("BEST " + bestValue);
            return output;
        }
        private List<String> outage(List<String> args) {
            requireCount(args, 3);
            int day = checkedDay(args.get(0));
            long start = number(args.get(1)), end = number(args.get(2));
            if (start < 0 || start > end || end > 23)
                throw new CommandError("invalid hours");
            SimulationResult previous = requireResult();
            int first = (int) ((day - 1) * 24 + start);
            int last = (int) ((day - 1) * 24 + end);
            SimulationResult result = simulate(previous.strategy, previous.settings,
                previous.prices, new int[]{first, last});
            long before = first > 0 ? result.hours.get(first - 1).soc : result.startSOC;
            List<String> output = new ArrayList<>();
            output.add("OUTAGE day " + day + " hours " + start + "-" + end +
                " strategy " + result.strategy.text() + " soc " + before);
            output.add("hour   load     pv  disch    soc  short   curt");
            Totals total = new Totals();
            for (int i = first; i <= last; ++i) {
                HourRecord r = result.hours.get(i);
                total.add(r);
                output.add(row(new Object[]{r.hour, r.load, r.pv, r.discharge,
                    r.soc, r.shortfall, r.curtailed}, 4, 7, 7, 7, 7, 7, 7));
            }
            String served = total.load == 0 ? "100.00" :
                percentage(total.load - total.shortfall, total.load);
            output.add("TOTAL load " + total.load + " unserved " + total.shortfall +
                " served " + served + "% bill " + money(result.bill));
            return output;
        }
        private List<String> diff(List<String> args) {
            if (args.size() < 2) throw new CommandError("wrong number of arguments");
            int day = checkedDay(args.get(0));
            Strategy option = oneStrategy(args.subList(1, args.size()));
            SimulationResult previous = requireResult();
            SimulationResult comparison = simulate(option, previous.settings,
                previous.prices, null);
            List<String> output = new ArrayList<>();
            output.add("DIFF day " + day + " " + data.dayNames.get(day - 1) + " " +
                previous.strategy.text() + " vs " + option.text());
            output.add("hour   imp1   imp2   exp1   exp2   soc1   soc2");
            for (int hour = 0; hour < 24; ++hour) {
                HourRecord a = previous.hours.get((day - 1) * 24 + hour);
                HourRecord b = comparison.hours.get((day - 1) * 24 + hour);
                output.add(row(new Object[]{a.hour, a.imported, b.imported,
                    a.exported, b.exported, a.soc, b.soc}, 4, 7, 7, 7, 7, 7, 7));
            }
            long before = previous.daily.get(day - 1).netCost;
            long after = comparison.daily.get(day - 1).netCost;
            output.add("TOTAL cost1 " + money(before) + " cost2 " + money(after) +
                " difference " + money(after - before));
            return output;
        }
        private List<String> hourly(List<String> args) {
            int day = dayForResult(args);
            SimulationResult r = requireResult();
            List<String> output = new ArrayList<>();
            output.add("HOURLY day " + day + " " + data.dayNames.get(day - 1) +
                " strategy " + r.strategy.text());
            output.add("hour   load     pv charge  disch    soc import export   curt");
            for (int hour = 0; hour < 24; ++hour) {
                HourRecord h = r.hours.get((day - 1) * 24 + hour);
                output.add(row(new Object[]{h.hour, h.load, h.pv, h.charge,
                    h.discharge, h.soc, h.imported, h.exported, h.curtailed},
                    4, 7, 7, 7, 7, 7, 7, 7, 7));
            }
            Totals t = r.daily.get(day - 1);
            output.add(row(new Object[]{"sum", t.load, t.pv, t.charge,
                t.discharge, "", t.imported, t.exported, t.curtailed},
                4, 7, 7, 7, 7, 7, 7, 7, 7));
            return output;
        }
        private List<String> daily(List<String> args) {
            SimulationResult r = withoutArgs(args);
            List<String> output = new ArrayList<>();
            output.add("DAILY strategy " + r.strategy.text());
            output.add("day name    load      pv  import  export    curt     soc      cost");
            for (int day = 1; day <= data.dayCount; ++day) {
                Totals t = r.daily.get(day - 1);
                HourRecord last = r.hours.get(day * 24 - 1);
                output.add(row(new Object[]{day, data.dayNames.get(day - 1),
                    t.load, t.pv, t.imported, t.exported, t.curtailed,
                    last.soc, money(t.netCost)}, 3, 5, 8, 8, 8, 8, 8, 8, 10));
            }
            Totals t = r.total;
            output.add("TOTAL load " + t.load + " pv " + t.pv + " import " +
                t.imported + " export " + t.exported + " curtailed " +
                t.curtailed + " cost " + money(t.netCost));
            return output;
        }
        private List<String> bill(List<String> args) {
            SimulationResult r = withoutArgs(args);
            List<String> output = new ArrayList<>();
            output.add("BILL strategy " + r.strategy.text() + " days " + data.dayCount);
            for (Map.Entry<String, Totals> entry : r.byPeriod.entrySet()) {
                Totals t = entry.getValue();
                output.add("IMPORT " + entry.getKey() + " " + t.imported +
                    " Wh " + money(t.importCost));
            }
            output.add("EXPORT " + r.total.exported + " Wh " + money(-r.total.exportIncome));
            output.add("FIXED " + money(value(r.settings, "FIXED")));
            output.add("DEMAND " + r.peak + " Wh " + money(r.demandCharge));
            output.add("TOTAL " + money(r.bill));
            return output;
        }
        private List<String> savings(List<String> args) {
            SimulationResult r = withoutArgs(args);
            SimulationResult noBattery = baseline(r.settings, r.prices);
            List<String> output = new ArrayList<>();
            output.add("SAVINGS strategy " + r.strategy.text());
            for (String name : r.byPeriod.keySet()) {
                long before = noBattery.byPeriod.get(name).importCost;
                long after = r.byPeriod.get(name).importCost;
                output.add(name + " " + money(before) + " -> " + money(after) +
                    " saving " + money(before - after));
            }
            long[] before = {-noBattery.total.exportIncome,
                noBattery.demandCharge, noBattery.bill};
            long[] after = {-r.total.exportIncome, r.demandCharge, r.bill};
            String[] names = {"EXPORT", "DEMAND", "TOTAL"};
            for (int i = 0; i < names.length; ++i)
                output.add(names[i] + " " + money(before[i]) + " -> " + money(after[i]) +
                    " saving " + money(before[i] - after[i]));
            return output;
        }
        private List<String> byPeriod(List<String> args) {
            SimulationResult r = withoutArgs(args);
            List<String> output = new ArrayList<>();
            output.add("BYPERIOD strategy " + r.strategy.text());
            for (Map.Entry<String, Totals> entry : r.byPeriod.entrySet()) {
                Totals t = entry.getValue();
                output.add(entry.getKey() + " hours " + t.count + " load " + t.load +
                    " pv " + t.pv + " charge " + t.charge + " discharge " + t.discharge +
                    " import " + t.imported + " export " + t.exported);
            }
            return output;
        }
        private List<String> dayType(List<String> args) {
            SimulationResult r = withoutArgs(args);
            List<String> output = new ArrayList<>();
            output.add("DAYTYPE strategy " + r.strategy.text());
            for (boolean weekend : new boolean[]{false, true}) {
                Totals t = new Totals();
                int days = 0;
                for (int day = 0; day < data.dayCount; ++day) {
                    if (data.weekendDays.get(day) != weekend) continue;
                    ++days;
                    for (int hour = 0; hour < 24; ++hour)
                        t.add(r.hours.get(day * 24 + hour));
                }
                output.add((weekend ? "WEEKEND" : "WEEKDAY") + " days " + days +
                    " load " + t.load / days + " pv " + t.pv / days +
                    " import " + t.imported / days + " export " + t.exported / days +
                    " cost " + money(t.netCost / days));
            }
            return output;
        }
        private List<String> peaks(List<String> args) {
            requireCount(args, 1);
            long count = number(args.get(0));
            if (count < 1) throw new CommandError("invalid count");
            SimulationResult r = requireResult();
            List<HourRecord> records = new ArrayList<>();
            for (HourRecord h : r.hours) if (h.imported > 0) records.add(h);
            records.sort(Comparator.comparingLong((HourRecord h) -> -h.imported)
                .thenComparingInt(h -> h.index));
            List<String> output = new ArrayList<>();
            output.add("PEAKS strategy " + r.strategy.text());
            for (int i = 0; i < records.size() && i < count; ++i) {
                HourRecord h = records.get(i);
                output.add((i + 1) + ". day " + h.day + " hour " + h.hour + " " +
                    h.period + " import " + h.imported + " load " + h.load +
                    " soc " + h.soc);
            }
            if (records.isEmpty()) output.add("none");
            return output;
        }
        private List<String> profile(List<String> args) {
            SimulationResult r = withoutArgs(args);
            List<String> output = new ArrayList<>();
            output.add("PROFILE strategy " + r.strategy.text() + " days " + data.dayCount);
            output.add("hour   load     pv import export    soc");
            for (int hour = 0; hour < 24; ++hour) {
                long load = 0, pv = 0, imported = 0, exported = 0, soc = 0;
                for (int day = 0; day < data.dayCount; ++day) {
                    HourRecord h = r.hours.get(day * 24 + hour);
                    load += h.load;
                    pv += h.pv;
                    imported += h.imported;
                    exported += h.exported;
                    soc += h.soc;
                }
                output.add(row(new Object[]{hour, load / data.dayCount,
                    pv / data.dayCount, imported / data.dayCount,
                    exported / data.dayCount, soc / data.dayCount}, 4, 7, 7, 7, 7, 7));
            }
            return output;
        }
        private List<String> flows(List<String> args) {
            SimulationResult r = withoutArgs(args);
            List<String> output = new ArrayList<>();
            output.add("FLOWS strategy " + r.strategy.text());
            for (int i = 0; i < FLOW_NAMES.length; ++i)
                output.add(FLOW_NAMES[i] + " " + r.total.flows[i]);
            output.add("LOSSES " + r.total.loss);
            output.add("STORED " + (r.endSOC - r.startSOC));
            return output;
        }
        private List<String> selfSuff(List<String> args) {
            SimulationResult r = withoutArgs(args);
            return List.of("SELFSUFF sufficiency " + r.sufficiency +
                "% consumption " + percentage(r.total.flows[0] + r.total.flows[1],
                r.total.pv) + "%");
        }
        private List<String> cycles(List<String> args) {
            SimulationResult r = withoutArgs(args);
            long drawn = r.total.drawn, capacity = value(r.settings, "CAPACITY");
            long common = gcd(drawn, capacity);
            long numerator = drawn / common, denominator = capacity / common;
            long thousandths = 1000 * drawn / capacity;
            String decimal = thousandths / 1000 + "." + String.format("%03d", thousandths % 1000);
            return List.of("CYCLES " + numerator + "/" + denominator + " " + decimal +
                " drawn " + drawn + " losses " + r.total.loss);
        }
        private List<String> usage(List<String> args) {
            SimulationResult r = withoutArgs(args);
            long charging = 0, discharging = 0, idle = 0, full = 0, low = 0;
            long run = 0, longest = 0;
            HourRecord first = null;
            for (HourRecord h : r.hours) {
                if (h.charge > 0) ++charging;
                if (h.drawn > 0) ++discharging;
                if (h.charge == 0 && h.drawn == 0) ++idle;
                if (h.soc == value(r.settings, "CAPACITY")) ++full;
                if (h.soc <= r.reserve) {
                    ++low;
                    ++run;
                    if (run > longest) {
                        longest = run;
                        first = r.hours.get((int) (h.index - run + 1));
                    }
                } else {
                    run = 0;
                }
            }
            String line = "USAGE charging " + charging + " discharging " + discharging +
                " idle " + idle + " full " + full + " low " + low +
                " longest " + longest;
            if (first != null) line += " from day " + first.day + " hour " + first.hour;
            return List.of(line);
        }
        private List<String> histogram(List<String> args) {
            SimulationResult r = withoutArgs(args);
            long[] counts = new long[10];
            long capacity = value(r.settings, "CAPACITY");
            for (HourRecord h : r.hours) ++counts[(int) Math.min(9, 10 * h.soc / capacity)];
            List<String> output = new ArrayList<>();
            output.add("HISTOGRAM strategy " + r.strategy.text());
            for (int i = 0; i < counts.length; ++i)
                output.add(row(new Object[]{10 * i}, 3) + "% " +
                    bar(20 * counts[i] / r.hours.size()) + " " + counts[i]);
            return output;
        }
        private List<String> chart(List<String> args) {
            int day = dayForResult(args);
            SimulationResult r = requireResult();
            long capacity = value(r.settings, "CAPACITY");
            List<String> output = new ArrayList<>();
            output.add("CHART day " + day + " " + data.dayNames.get(day - 1) +
                " strategy " + r.strategy.text());
            for (int hour = 0; hour < 24; ++hour) {
                HourRecord h = r.hours.get((day - 1) * 24 + hour);
                output.add(row(new Object[]{h.hour}, 2) + " " +
                    bar(20 * h.soc / capacity) + " " + percentage(h.soc, capacity) + "%");
            }
            return output;
        }

        List<String> execute(String[] tokens) {
            String command = tokens[0];
            List<String> args = Arrays.asList(tokens).subList(1, tokens.length);
            try {
                return switch (command) {
                    case "RUN" -> run(args);
                    case "SET" -> setValue(args);
                    case "PRICE" -> changePrice(args);
                    case "RESET" -> reset(args);
                    case "CONFIG" -> config(args);
                    case "NOBATTERY" -> noBattery(args);
                    case "COMPARE" -> compare(args);
                    case "SIZE" -> size(args);
                    case "SWEEP" -> sweep(args);
                    case "OUTAGE" -> outage(args);
                    case "DIFF" -> diff(args);
                    case "HOURLY" -> hourly(args);
                    case "DAILY" -> daily(args);
                    case "BILL" -> bill(args);
                    case "SAVINGS" -> savings(args);
                    case "BYPERIOD" -> byPeriod(args);
                    case "DAYTYPE" -> dayType(args);
                    case "PEAKS" -> peaks(args);
                    case "PROFILE" -> profile(args);
                    case "FLOWS" -> flows(args);
                    case "SELFSUFF" -> selfSuff(args);
                    case "CYCLES" -> cycles(args);
                    case "USAGE" -> usage(args);
                    case "HISTOGRAM" -> histogram(args);
                    case "CHART" -> chart(args);
                    default -> List.of("ERROR unknown command " + command);
                };
            } catch (CommandError error) {
                return List.of("ERROR " + error.getMessage());
            }
        }
    }

    public static void main(String[] ignored) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        InputData data = new InputData(reader);
        DispatchDesk desk = new DispatchDesk(data);
        StringBuilder output = new StringBuilder();
        for (String line : data.commands) {
            String[] tokens = words(line);
            if (tokens[0].equals("END")) break;
            for (String result : desk.execute(tokens)) output.append(result).append('\n');
        }
        System.out.print(output);
    }
}
