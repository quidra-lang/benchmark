import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.regex.Pattern;

public class Main {
    private static final List<String> TYPES = List.of("FIXED", "ZERO", "AMORT", "FRN");
    private static final List<String> BUCKETS = List.of("0-1Y", "1-3Y", "3-5Y", "5-10Y", "10Y+");
    private static final Set<Integer> FREQUENCIES = Set.of(1, 2, 4, 12);
    private static final Set<String> DAYCOUNTS = Set.of("30/360", "30E/360", "ACT/360", "ACT/365F", "ACT/ACT");
    private static final Set<String> BUSINESS_RULES = Set.of("FOLLOWING", "MODIFIED_FOLLOWING", "PRECEDING", "UNADJUSTED");
    private static class InputError extends RuntimeException { InputError(String message) { super(message); } }
    private record Row(int line, String[] fields) {}
    private static String[] split(String text, char delimiter) { return text.split(Pattern.quote(String.valueOf(delimiter)), -1); }
    private static List<String> read(String name) throws IOException { return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII); }
    private static List<Row> rows(String name) throws IOException {
        List<String> lines = read(name); List<Row> result = new ArrayList<>(); for (int i = 1; i < lines.size(); i++) result.add(new Row(i + 1, split(lines.get(i), ','))); return result;
    }
    private static long rounded(long numerator, long denominator) { return (2 * numerator + denominator) / (2 * denominator); }
    private static long thousandths(String text) { String[] parts = split(text, '.'); return Long.parseLong(parts[0]) * 1000 + Long.parseLong(parts[1]); }
    private static String decimal(double value, int places) {
        long scale = 1; for (int i = 0; i < places; i++) scale *= 10;
        long n = (long) ((value < 0 ? -value : value) * scale + 0.5); String tail = Long.toString(n % scale);
        return (value < 0 && n != 0 ? "-" : "") + n / scale + "." + "0".repeat(places - tail.length()) + tail;
    }
    private static String hundredths(long value) {
        if (value < 0) return "-" + hundredths(-value); String tail = Long.toString(value % 100); return value / 100 + "." + "0".repeat(2 - tail.length()) + tail;
    }
    private static String percent(double rate) { return decimal(rate * 100, 4); }
    private static String amount(double cents) { return decimal(cents / 100, 2); }
    private static void save(String name, List<String> lines) throws IOException {
        StringBuilder text = new StringBuilder(); for (String line : lines) text.append(line).append('\n'); Files.writeString(Path.of("output", name), text, StandardCharsets.US_ASCII);
    }
    private static class ErrorLog {
        final List<String> lines = new ArrayList<>();
        void add(String file, int line, String key, String message) { lines.add(file + ":" + line + ": " + key + ": " + message); }
    }
    private record Scenario(String name, double[] deltas) {}
    private record RawScenario(int line, String name, List<Integer> shifts) {}
    private static class Parameters {
        int valuation, settlementDays;
        final List<RawScenario> scenarios = new ArrayList<>();
        final List<String[]> limits = new ArrayList<>();
        Parameters(List<String> lines) {
            for (int i = 0; i < lines.size(); i++) {
                String[] f = split(lines.get(i), ' ');
                switch (f[0]) {
                    case "valuation_date" -> valuation = Dates.parse(f[1]);
                    case "settlement_days" -> settlementDays = Integer.parseInt(f[1]);
                    case "scenario" -> { List<Integer> shifts = new ArrayList<>(); for (int j = 2; j < f.length; j++) shifts.add(Integer.parseInt(f[j])); scenarios.add(new RawScenario(i + 1, f[1], shifts)); }
                    case "limit" -> limits.add(Arrays.copyOfRange(f, 1, f.length));
                    default -> throw new IllegalArgumentException(f[0]);
                }
            }
        }
    }
    private static class Fixings {
        final int[] dates, rates;
        Fixings(List<Row> rows) { dates = new int[rows.size()]; rates = new int[rows.size()]; for (int i = 0; i < rows.size(); i++) { dates[i] = Dates.parse(rows.get(i).fields()[0]); rates[i] = Integer.parseInt(rows.get(i).fields()[1]); } }
        Integer latest(int day) {
            int low = 0, high = dates.length;
            while (low < high) { int middle = (low + high) / 2; if (dates[middle] <= day) low = middle + 1; else high = middle; } return low == 0 ? null : rates[low - 1];
        }
    }
    private record RawOption(String date, long value) {}
    private record DatedOption(int day, long value) {}
    private static class Options {
        boolean eom, longStub;
        int lag = -1, cap = -1, floor = -1;
        final List<RawOption> sinks = new ArrayList<>(), calls = new ArrayList<>();
    }
    private record Period(int number, int start, int end, int payment, Fraction fraction, int rate, long opening, long coupon, long principal) { long cash() { return coupon + principal; } }
    private static class Bond {
        final String code, type, daycount, bdc;
        final int issue, maturity, coupon, frequency;
        final long face;
        Options options = new Options();
        List<Integer> schedule = new ArrayList<>();
        final Map<Integer, Long> sinks = new HashMap<>();
        List<DatedOption> calls = new ArrayList<>();
        final List<Period> periods = new ArrayList<>();
        Bond(String code, String type, int issue, int maturity, int coupon, int frequency, String daycount, String bdc, long face) {
            this.code = code; this.type = type; this.issue = issue; this.maturity = maturity; this.coupon = coupon; this.frequency = frequency; this.daycount = daycount; this.bdc = bdc; this.face = face;
        }
    }
    private static List<Pillar> validatePillars(int settlement, ErrorLog errors) throws IOException {
        Set<String> seen = new HashSet<>(); List<Pillar> result = new ArrayList<>();
        for (Row row : rows("curve_quotes.csv")) {
            String[] f = row.fields(); String error = "";
            if (!seen.add(f[0])) error = "duplicate pillar";
            else if (!Dates.valid(f[0])) error = "invalid date";
            else if (Dates.parse(f[0]) <= settlement) error = "pillar not after settlement";
            else if (!FREQUENCIES.contains(Integer.parseInt(f[2]))) error = "invalid frequency";
            if (!error.isEmpty()) errors.add("curve_quotes.csv", row.line(), f[0], error); else result.add(new Pillar(Dates.parse(f[0]), Integer.parseInt(f[1]), Integer.parseInt(f[2])));
        }
        result.sort(Comparator.comparingInt(Pillar::maturity)); return result;
    }
    private static List<Scenario> validateScenarios(List<RawScenario> raw, int pillars, ErrorLog errors) {
        Set<String> seen = new HashSet<>(); List<Scenario> result = new ArrayList<>();
        for (RawScenario source : raw) {
            String error = !seen.add(source.name()) ? "duplicate scenario" : source.shifts().size() != pillars ? "wrong number of shifts" : "";
            if (!error.isEmpty()) errors.add("params.txt", source.line(), source.name(), error);
            else result.add(new Scenario(source.name(), source.shifts().stream().mapToDouble(s -> s * 0.0001).toArray()));
        }
        return result;
    }
    private static Options parseOptions(String type, String text) {
        Options result = new Options(); Set<String> seen = new HashSet<>();
        if (!text.equals("-")) for (String item : split(text, ';')) {
            int equal = item.indexOf('='); String key = equal < 0 ? item : item.substring(0, equal), value = equal < 0 ? "" : item.substring(equal + 1);
            boolean allowed = key.equals("EOM") || key.equals("LONG") || type.equals("FIXED") && key.equals("CALL") || type.equals("AMORT") && key.equals("SINK") || type.equals("FRN") && Set.of("LAG", "CAP", "FLOOR").contains(key);
            if (!allowed || !seen.add(key) && !key.equals("SINK") && !key.equals("CALL")) throw new InputError("invalid option");
            switch (key) {
                case "EOM" -> result.eom = true;
                case "LONG" -> result.longStub = true;
                case "LAG" -> result.lag = Integer.parseInt(value);
                case "CAP" -> result.cap = Integer.parseInt(value);
                case "FLOOR" -> result.floor = Integer.parseInt(value);
                default -> { String[] p = split(value, ':'); (key.equals("SINK") ? result.sinks : result.calls).add(new RawOption(p[0], key.equals("SINK") ? Long.parseLong(p[1]) : thousandths(p[1]))); }
            }
        }
        if (type.equals("FRN") && (result.lag < 1 || result.lag > 5 || result.cap > 1200 || result.floor > (result.cap < 0 ? 1200 : result.cap))) throw new InputError("invalid option"); return result;
    }
    private static List<DatedOption> scheduleItems(List<RawOption> items, List<Integer> dates, String reason) {
        Set<Integer> inside = new HashSet<>(dates.subList(1, dates.size() - 1)); List<DatedOption> result = new ArrayList<>();
        for (RawOption item : items) {
            if (!Dates.valid(item.date())) throw new InputError(reason);
            int day = Dates.parse(item.date()); if (!inside.contains(day) || !result.isEmpty() && day <= result.getLast().day()) throw new InputError(reason); result.add(new DatedOption(day, item.value()));
        }
        return result;
    }
    private static Bond parseBond(String[] f, Calendar calendar, Fixings fixings) {
        if (!TYPES.contains(f[1])) throw new InputError("unknown type");
        if (!Dates.valid(f[2]) || !Dates.valid(f[3])) throw new InputError("invalid date");
        int issue = Dates.parse(f[2]), maturity = Dates.parse(f[3]), coupon = Integer.parseInt(f[4]), frequency = Integer.parseInt(f[5]); long face = Long.parseLong(f[8]);
        if (maturity <= issue) throw new InputError("maturity not after issue");
        if (!FREQUENCIES.contains(frequency)) throw new InputError("invalid frequency");
        if (!DAYCOUNTS.contains(f[6])) throw new InputError("unknown day count");
        if (!BUSINESS_RULES.contains(f[7])) throw new InputError("unknown business day rule");
        if (face % 100000 != 0 || face > 10000000) throw new InputError("invalid face");
        if (coupon > 1200 || f[1].equals("ZERO") && coupon != 0) throw new InputError("invalid coupon");
        Bond bond = new Bond(f[0], f[1], issue, maturity, coupon, frequency, f[6], f[7], face); bond.options = parseOptions(bond.type, f[9]);
        bond.schedule = Schedule.build(issue, maturity, frequency, bond.options.eom, bond.options.longStub);
        List<DatedOption> sinks = scheduleItems(bond.options.sinks, bond.schedule, "invalid sinking fund"); long total = 0;
        for (DatedOption sink : sinks) { if (sink.value() == 0) throw new InputError("invalid sinking fund"); total += sink.value(); bond.sinks.put(sink.day(), sink.value()); }
        if (bond.type.equals("AMORT") && (total == 0 || total >= face)) throw new InputError("invalid sinking fund");
        bond.calls = scheduleItems(bond.options.calls, bond.schedule, "invalid call schedule");
        for (DatedOption call : bond.calls) if (call.value() < 100000 || call.value() > 110000) throw new InputError("invalid call schedule");
        long opening = face;
        for (int i = 1; i < bond.schedule.size(); i++) {
            int start = bond.schedule.get(i - 1), end = bond.schedule.get(i), rate = bond.type.equals("ZERO") ? 0 : coupon;
            if (bond.type.equals("FRN")) {
                int day = calendar.move(calendar.adjust(start, bond.bdc), -bond.options.lag); Integer fixing = fixings.latest(day); if (fixing == null) throw new InputError("missing fixing"); rate += fixing;
                if (bond.options.floor >= 0) rate = Math.max(rate, bond.options.floor); if (bond.options.cap >= 0) rate = Math.min(rate, bond.options.cap);
            }
            Fraction fraction = Daycount.between(bond.daycount, start, end); long principal = i + 1 == bond.schedule.size() ? opening : bond.sinks.getOrDefault(end, 0L);
            long interest = rounded(opening * rate * fraction.numerator(), 10000 * fraction.denominator());
            bond.periods.add(new Period(i, start, end, calendar.adjust(end, bond.bdc), fraction, rate, opening, interest, principal)); opening -= principal;
        }
        return bond;
    }
    private static Map<String, Bond> validateBonds(Calendar calendar, Fixings fixings, ErrorLog errors) throws IOException {
        Map<String, Bond> bonds = new TreeMap<>(); Set<String> seen = new HashSet<>();
        for (Row row : rows("bonds.csv")) try { if (!seen.add(row.fields()[0])) throw new InputError("duplicate id"); Bond bond = parseBond(row.fields(), calendar, fixings); bonds.put(bond.code, bond); }
        catch (InputError error) { errors.add("bonds.csv", row.line(), row.fields()[0], error.getMessage()); }
        return bonds;
    }
    private static class Valuation {
        final Bond bond;
        final long clean, outstanding, accruedAmount, cleanAmount, unitValue;
        final List<Period> remaining, cashflows = new ArrayList<>();
        final List<Flow> flows = new ArrayList<>();
        final YieldPricer pricer;
        final double accrued, target, fraction;
        double ytm, ytw, wal, curveClean, spread;
        Risk risk;
        int workout, nextPayment;
        Valuation(Bond bond, long clean, int settlement) {
            this.bond = bond; this.clean = clean; workout = bond.maturity; int index = 0; while (bond.periods.get(index).end() <= settlement) index++;
            remaining = new ArrayList<>(bond.periods.subList(index, bond.periods.size())); Period current = remaining.getFirst(); outstanding = current.opening();
            Fraction elapsed = Daycount.between(bond.daycount, current.start(), settlement); accrued = current.rate() * (double) elapsed.numerator() / (100 * elapsed.denominator());
            accruedAmount = rounded(outstanding * current.rate() * elapsed.numerator(), 10000 * elapsed.denominator()); cleanAmount = rounded(outstanding * clean, 100000); unitValue = cleanAmount + accruedAmount;
            target = clean / 1000.0 + accrued; Fraction rest = Daycount.between(bond.daycount, settlement, current.end()); fraction = bond.frequency * rest.value();
            List<Double> yieldFlows = new ArrayList<>();
            for (Period period : remaining) { yieldFlows.add((double) period.cash()); if (period.cash() >= 1) { cashflows.add(period); flows.add(new Flow(period.payment() - settlement, period.cash())); } }
            pricer = new YieldPricer(yieldFlows, fraction, bond.frequency, outstanding); nextPayment = cashflows.getFirst().payment();
        }
        void analyze(ZeroCurve curve, int settlement) {
            ytm = pricer.solve(target); ytw = ytm; risk = pricer.measure(ytm);
            for (DatedOption call : bond.calls) if (call.day() > settlement) {
                List<Double> values = new ArrayList<>();
                for (Period period : remaining) { values.add((double) period.coupon()); if (period.end() == call.day()) { values.set(values.size() - 1, values.getLast() + rounded(period.opening() * call.value(), 100000)); break; } }
                double callYield = new YieldPricer(values, fraction, bond.frequency, outstanding).solve(target); if (callYield < ytw) { ytw = callYield; workout = call.day(); }
            }
            long principalDays = 0; for (Period period : cashflows) principalDays += period.principal() * (period.payment() - settlement);
            wal = (double) principalDays / (365 * outstanding); curveClean = curve.presentValue(flows, 0) * 100 / outstanding - accrued; spread = curve.spread(flows, unitValue);
        }
    }
    private static Map<String, Valuation> validatePrices(Map<String, Bond> bonds, int settlement, ErrorLog errors) throws IOException {
        Map<String, Valuation> result = new TreeMap<>(); Set<String> seen = new HashSet<>();
        for (Row row : rows("prices.csv")) {
            String code = row.fields()[0]; boolean duplicate = !seen.add(code);
            try {
                Bond bond = bonds.get(code); if (bond == null) throw new InputError("unknown bond"); if (duplicate) throw new InputError("duplicate price");
                if (bond.issue > settlement || settlement >= bond.maturity) throw new InputError("not outstanding");
                Valuation value = new Valuation(bond, thousandths(row.fields()[1]), settlement); if (!(value.pricer.dirty(0) > value.target && value.target > value.pricer.dirty(1))) throw new InputError("yield out of range"); result.put(code, value);
            } catch (InputError error) { errors.add("prices.csv", row.line(), code, error.getMessage()); }
        }
        return result;
    }
    private static class Position {
        final Valuation valuation;
        long units, book;
        Position(Valuation valuation) { this.valuation = valuation; }
        Bond bond() { return valuation.bond; }
        long value() { return units * valuation.unitValue; }
        long face() { return units * bond().face; }
        long outstanding() { return units * valuation.outstanding; }
        long gain() { return units * valuation.cleanAmount - book; }
        double dv01() { return valuation.risk.dv01() * units * valuation.outstanding / 10000; }
        double presentValue(ZeroCurve curve) { return units * curve.presentValue(valuation.flows, valuation.spread); }
    }
    private static Map<String, Map<String, Position>> validateHoldings(Map<String, Bond> bonds, Map<String, Valuation> prices, ErrorLog errors) throws IOException {
        Map<String, Map<String, Position>> groups = new TreeMap<>();
        for (Row row : rows("holdings.csv")) {
            String[] f = row.fields();
            try {
                if (!bonds.containsKey(f[1])) throw new InputError("unknown bond"); Valuation valuation = prices.get(f[1]); if (valuation == null) throw new InputError("no price");
                long face = Long.parseLong(f[2]); if (face % valuation.bond.face != 0) throw new InputError("invalid face"); long units = face / valuation.bond.face;
                Position position = groups.computeIfAbsent(f[0], key -> new TreeMap<>()).computeIfAbsent(f[1], key -> new Position(valuation)); position.units += units; position.book += rounded(units * valuation.outstanding * thousandths(f[3]), 100000);
            } catch (InputError error) { errors.add("holdings.csv", row.line(), f[1], error.getMessage()); }
        }
        return groups;
    }
    private static class GroupTotals {
        int count; long value; double duration, dv01;
        void add(Position position) { count++; value += position.value(); duration += (double) position.value() * position.valuation.risk.modified(); dv01 += position.dv01(); }
    }
    private static class ScenarioResult {
        final String name;
        final List<Double> values = new ArrayList<>(), pnls = new ArrayList<>();
        double total, pnl;
        ScenarioResult(String name) { this.name = name; }
    }
    private static class Portfolio {
        final String name;
        final List<Position> positions;
        long totalValue, face, outstanding, book, gain, income;
        double ytm, modified, convexity, spread, dv01, cashYield, baseValue, effective;
        final List<Double> baseValues = new ArrayList<>(), keyRates = new ArrayList<>();
        final GroupTotals[] typeTotals = new GroupTotals[4], buckets = new GroupTotals[5];
        final Map<Integer, long[]> ladder = new TreeMap<>();
        final List<ScenarioResult> scenarios = new ArrayList<>();
        Portfolio(String name, List<Position> positions) { this.name = name; this.positions = positions; for (int i = 0; i < typeTotals.length; i++) typeTotals[i] = new GroupTotals(); for (int i = 0; i < buckets.length; i++) buckets[i] = new GroupTotals(); }
        double weight(long value) { return (double) value * 100 / totalValue; }
        double presentValue(ZeroCurve curve) { double total = 0; for (Position position : positions) total += position.presentValue(curve); return total; }
        double rateDuration(ZeroCurve curve, int pillar) {
            double[] down = new double[curve.rates.length], up = new double[curve.rates.length];
            for (int i = 0; i < down.length; i++) if (pillar < 0 || i == pillar) { down[i] = -0.0001; up[i] = 0.0001; }
            return (presentValue(curve.shifted(down)) - presentValue(curve.shifted(up))) / (2 * 0.0001 * baseValue);
        }
        void analyze(ZeroCurve curve, List<Scenario> shocks, int settlement) {
            List<Flow> allFlows = new ArrayList<>(); int[] bounds = {365, 1095, 1825, 3650};
            for (Position p : positions) {
                Valuation v = p.valuation; long value = p.value(); totalValue += value; face += p.face(); outstanding += p.outstanding(); book += p.book; gain += p.gain();
                ytm += (double) value * v.ytm; modified += (double) value * v.risk.modified(); convexity += (double) value * v.risk.convexity(); spread += (double) value * v.spread; dv01 += p.dv01();
                for (int i = 0; i < v.flows.size(); i++) {
                    Flow flow = v.flows.get(i); Period period = v.cashflows.get(i); allFlows.add(new Flow(flow.days(), p.units * flow.amount()));
                    if (flow.days() <= 365) income += p.units * period.coupon();
                    long[] year = ladder.computeIfAbsent(Dates.civil(period.payment()).getYear(), key -> new long[2]); year[0] += p.units * period.coupon(); year[1] += p.units * period.principal();
                }
                typeTotals[TYPES.indexOf(p.bond().type)].add(p); int days = p.bond().maturity - settlement, bucket = 0; while (bucket < bounds.length && days >= bounds[bucket]) bucket++; buckets[bucket].add(p);
                double base = p.presentValue(curve); baseValues.add(base); baseValue += base;
            }
            ytm /= totalValue; modified /= totalValue; convexity /= totalValue; spread /= totalValue;
            cashYield = Bisection.solve(rate -> new ZeroCurve(new int[]{0}, new double[]{rate}).presentValue(allFlows, 0), 0, 1, totalValue);
            effective = rateDuration(curve, -1); for (int i = 0; i < curve.rates.length; i++) keyRates.add(rateDuration(curve, i));
            List<Scenario> all = new ArrayList<>(); all.add(new Scenario("BASE", new double[curve.rates.length])); all.addAll(shocks);
            for (Scenario shock : all) {
                ZeroCurve shifted = curve.shifted(shock.deltas()); ScenarioResult result = new ScenarioResult(shock.name());
                for (int i = 0; i < positions.size(); i++) { double value = positions.get(i).presentValue(shifted); result.values.add(value); result.pnls.add(value - baseValues.get(i)); result.total += value; }
                result.pnl = result.total - baseValue; scenarios.add(result);
            }
        }
        String groupLine(String kind, String label, GroupTotals group) {
            return kind + " " + label + " positions " + group.count + " value " + hundredths(group.value) + " weight " + decimal(weight(group.value), 4) + " duration " + decimal(group.duration / totalValue, 4) + " dv01 " + decimal(group.dv01, 2);
        }
        List<String> report() {
            List<String> lines = new ArrayList<>(); lines.add("portfolio " + name);
            for (Position p : positions) {
                Valuation v = p.valuation;
                lines.add("position " + p.bond().code + " face " + hundredths(p.face()) + " outstanding " + hundredths(p.outstanding()) + " clean " + decimal(v.clean / 1000.0, 6) + " value " + hundredths(p.value()) + " weight " + decimal(weight(p.value()), 4) + " book " + hundredths(p.book) + " gain " + hundredths(p.gain()) + " ytm " + percent(v.ytm) + " modified " + decimal(v.risk.modified(), 4) + " dv01 " + decimal(p.dv01(), 2));
            }
            lines.add("total positions " + positions.size() + " face " + hundredths(face) + " outstanding " + hundredths(outstanding) + " value " + hundredths(totalValue) + " book " + hundredths(book) + " gain " + hundredths(gain) + " income " + hundredths(income));
            lines.add("risk ytm " + percent(ytm) + " yield " + percent(cashYield) + " modified " + decimal(modified, 4) + " convexity " + decimal(convexity, 4) + " zspread " + percent(spread) + " dv01 " + decimal(dv01, 2));
            lines.add("curve effective " + decimal(effective, 4) + " krd " + String.join(" ", keyRates.stream().map(value -> decimal(value, 4)).toList()));
            for (int i = 0; i < TYPES.size(); i++) lines.add(groupLine("type", TYPES.get(i), typeTotals[i]));
            for (int i = 0; i < BUCKETS.size(); i++) lines.add(groupLine("bucket", BUCKETS.get(i), buckets[i]));
            long coupons = 0, principal = 0;
            for (Map.Entry<Integer, long[]> row : ladder.entrySet()) {
                long[] values = row.getValue(); lines.add("ladder " + row.getKey() + " coupon " + hundredths(values[0]) + " principal " + hundredths(values[1]) + " total " + hundredths(values[0] + values[1])); coupons += values[0]; principal += values[1];
            }
            lines.add("ladder total coupon " + hundredths(coupons) + " principal " + hundredths(principal) + " total " + hundredths(coupons + principal));
            if (scenarios.size() > 1) {
                int worst = 1; for (int i = 2; i < scenarios.size(); i++) if (scenarios.get(i).pnl < scenarios.get(worst).pnl) worst = i;
                ScenarioResult stress = scenarios.get(worst); List<Integer> order = new ArrayList<>(); for (int i = 0; i < positions.size(); i++) order.add(i);
                order.sort(Comparator.comparingDouble((Integer i) -> stress.pnls.get(i)).thenComparing(i -> positions.get(i).bond().code));
                List<String> losers = new ArrayList<>(); for (int i : order.subList(0, Math.min(3, order.size()))) losers.add(positions.get(i).bond().code + " " + amount(stress.pnls.get(i)));
                lines.add("stress worst " + stress.name + " pnl " + amount(stress.pnl) + " losers " + String.join(" ", losers));
            }
            return lines;
        }
        List<String> scenarioLines() {
            List<String> lines = new ArrayList<>();
            for (ScenarioResult result : scenarios) {
                for (int i = 0; i < positions.size(); i++) lines.add(String.join(",", name, result.name, positions.get(i).bond().code, amount(result.values.get(i)), amount(result.pnls.get(i))));
                lines.add(String.join(",", name, result.name, "*", amount(result.total), amount(result.pnl)));
            }
            return lines;
        }
        List<String> compliance(List<String[]> limits, int settlement) {
            List<String> lines = new ArrayList<>(); int breaches = 0;
            for (String[] limit : limits) {
                boolean breach; String detail;
                switch (limit[0]) {
                    case "position_weight" -> {
                        Position largest = positions.getFirst(); for (Position p : positions) if (p.value() > largest.value()) largest = p;
                        long bound = Long.parseLong(limit[1]); detail = largest.bond().code + " " + decimal(weight(largest.value()), 4) + " limit " + hundredths(bound); breach = largest.value() * 10000 > bound * totalValue;
                    }
                    case "type_weight" -> {
                        long bound = Long.parseLong(limit[2]), value = typeTotals[TYPES.indexOf(limit[1])].value; detail = limit[1] + " " + decimal(weight(value), 4) + " limit " + hundredths(bound); breach = value * 10000 > bound * totalValue;
                    }
                    case "max_maturity" -> {
                        int years = Integer.parseInt(limit[1]), count = 0; for (Position p : positions) if (p.bond().maturity - settlement > 365 * years) count++;
                        detail = years + "Y positions " + count; breach = count > 0;
                    }
                    case "min_yield" -> { long bound = Long.parseLong(limit[1]); detail = percent(ytm) + " limit " + hundredths(bound); breach = ytm * 10000 < bound; }
                    case "duration" -> {
                        long low = Long.parseLong(limit[1]), high = Long.parseLong(limit[2]); detail = decimal(modified, 4) + " range " + hundredths(low) + " " + hundredths(high); breach = modified < low / 100.0 || modified > high / 100.0;
                    }
                    case "dv01" -> { long bound = Long.parseLong(limit[1]); detail = decimal(dv01, 2) + " limit " + hundredths(bound); breach = dv01 * 100 > bound; }
                    default -> throw new IllegalArgumentException(limit[0]);
                }
                lines.add(name + " " + limit[0] + " " + detail + " " + (breach ? "BREACH" : "PASS")); if (breach) breaches++;
            }
            lines.add(name + " breaches " + breaches); return lines;
        }
    }
    private static List<String> cashflowLines(Map<String, Bond> bonds) {
        List<String> lines = new ArrayList<>(List.of("bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal"));
        for (Bond bond : bonds.values()) for (Period p : bond.periods) if (p.cash() >= 1) lines.add(String.join(",", bond.code, Integer.toString(p.number()), Dates.format(p.start()), Dates.format(p.end()), Dates.format(p.payment()), decimal(p.fraction().value(), 6), Integer.toString(p.rate()), Long.toString(p.opening()), Long.toString(p.coupon()), Long.toString(p.principal())));
        return lines;
    }
    private static List<String> analyticsLines(Map<String, Valuation> prices) {
        List<String> lines = new ArrayList<>(List.of("bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread"));
        for (Valuation v : prices.values()) lines.add(String.join(",", v.bond.code, decimal(v.clean / 1000.0, 6), decimal(v.accrued, 6), decimal(v.target, 6), percent(v.ytm), percent(v.ytw), Dates.format(v.workout), Dates.format(v.nextPayment), decimal(v.wal, 4), decimal(v.risk.macaulay(), 4), decimal(v.risk.modified(), 4), decimal(v.risk.convexity(), 4), decimal(v.risk.dv01(), 6), decimal(v.curveClean, 6), percent(v.spread)));
        return lines;
    }
    private static List<String> curveLines(int valuation, int settlement, List<Pillar> pillars, ZeroCurve curve) {
        List<String> lines = new ArrayList<>(); lines.add("valuation " + Dates.format(valuation) + " settlement " + Dates.format(settlement)); int previous = 0;
        for (int i = 0; i < pillars.size(); i++) {
            Pillar pillar = pillars.get(i); int day = curve.days[i];
            lines.add("pillar " + Dates.format(pillar.maturity()) + " days " + day + " frequency " + pillar.frequency() + " par " + hundredths(pillar.coupon()) + " zero " + percent(curve.rates[i]) + " df " + decimal(curve.discount(day, 0), 6) + " forward " + percent(curve.forward(previous, day))); previous = day;
        }
        for (int year = 1; year <= curve.days[curve.days.length - 1] / 365; year++) { int day = year * 365; lines.add("grid " + year + "Y days " + day + " zero " + percent(curve.zero(day)) + " df " + decimal(curve.discount(day, 0), 6) + " forward " + percent(curve.forward(day - 365, day))); }
        return lines;
    }
    public static void main(String[] args) throws IOException {
        Parameters params = new Parameters(read("params.txt")); Calendar calendar = new Calendar(); for (String date : read("calendar.txt")) calendar.holidays.add(Dates.parse(date)); Fixings fixings = new Fixings(rows("fixings.csv"));
        int settlement = calendar.move(params.valuation, params.settlementDays); ErrorLog errors = new ErrorLog();
        List<Pillar> pillars = validatePillars(settlement, errors); List<Scenario> scenarios = validateScenarios(params.scenarios, pillars.size(), errors);
        Map<String, Bond> bonds = validateBonds(calendar, fixings, errors); Map<String, Valuation> prices = validatePrices(bonds, settlement, errors); Map<String, Map<String, Position>> groups = validateHoldings(bonds, prices, errors);
        ZeroCurve curve = ZeroCurve.bootstrap(settlement, pillars); for (Valuation value : prices.values()) value.analyze(curve, settlement);
        List<String> report = new ArrayList<>(), scenarioRows = new ArrayList<>(List.of("portfolio,scenario,bond,value,pnl")), compliance = new ArrayList<>();
        for (Map.Entry<String, Map<String, Position>> group : groups.entrySet()) {
            Portfolio portfolio = new Portfolio(group.getKey(), new ArrayList<>(group.getValue().values())); portfolio.analyze(curve, scenarios, settlement); report.addAll(portfolio.report()); scenarioRows.addAll(portfolio.scenarioLines()); compliance.addAll(portfolio.compliance(params.limits, settlement));
        }
        Files.createDirectories(Path.of("output")); save("errors.txt", errors.lines); save("cashflows.csv", cashflowLines(bonds)); save("analytics.csv", analyticsLines(prices)); save("curve.txt", curveLines(params.valuation, settlement, pillars, curve)); save("portfolio.txt", report); save("scenarios.csv", scenarioRows); save("compliance.txt", compliance);
    }
}
