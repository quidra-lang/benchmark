import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

public class Main {
    private static final Set<String> RATE_SETTINGS = Set.of(
        "STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED",
        "UIRATE", "MATCH", "MATCHMAX", "GARNCAP"
    );
    private static final LinkedHashMap<String, Long> INITIAL = new LinkedHashMap<>();
    static {
        INITIAL.put("STATE", 500L);
        INITIAL.put("SUPP", 2200L);
        INITIAL.put("SSRATE", 620L);
        INITIAL.put("MEDRATE", 145L);
        INITIAL.put("ADDMED", 90L);
        INITIAL.put("UIRATE", 270L);
        INITIAL.put("MATCH", 5000L);
        INITIAL.put("MATCHMAX", 600L);
        INITIAL.put("GARNCAP", 2500L);
        INITIAL.put("SSBASE", 16860000L);
        INITIAL.put("ADDBASE", 20000000L);
        INITIAL.put("UIBASE", 700000L);
        INITIAL.put("RETIRECAP", 2300000L);
        INITIAL.put("ALLOWANCE", 15000L);
        INITIAL.put("NIGHT", 100L);
    }

    private static final List<String> FIELDS = List.of(
        "R", "O", "D", "N", "P", "accrued", "salary", "leave", "deduction",
        "sales", "commission", "earnings", "bonus", "gross", "retirement",
        "health", "federal", "supplemental", "state", "social", "medicare",
        "garnishment", "net", "employer_social", "employer_medicare",
        "unemployment", "match", "employer", "W", "Y", "F", "J"
    );
    private static final String[] WEEKDAYS = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};

    private static class PayrollError extends RuntimeException {
        PayrollError(String message) { super(message); }
    }

    private static long cents(String text) {
        int dot = text.indexOf('.');
        return Long.parseLong(text.substring(0, dot)) * 100 +
               Long.parseLong(text.substring(dot + 1));
    }

    private static String money(long value) {
        return (value / 100) + "." + String.format("%02d", value % 100);
    }

    private static String rateText(long value) { return money(value) + "%"; }

    private static String duration(long minutes) {
        return (minutes / 60) + ":" + String.format("%02d", minutes % 60);
    }

    private static String clock(int minutes) {
        return String.format("%02d:%02d", minutes / 60, minutes % 60);
    }

    private static String weekday(int day) { return WEEKDAYS[(day - 1) % 7]; }
    private static int periodOf(int day) { return (day - 1) / 14 + 1; }

    private static Map<String, Long> emptyTotals() {
        Map<String, Long> result = new HashMap<>();
        for (String field : FIELDS) result.put(field, 0L);
        return result;
    }

    private static Map<String, Long> sumStubs(List<Map<String, Long>> stubs) {
        Map<String, Long> totals = emptyTotals();
        for (Map<String, Long> stub : stubs) {
            for (String field : FIELDS)
                totals.merge(field, stub.get(field), Long::sum);
        }
        return totals;
    }

    private static long progressive(TreeMap<Long, Long> table, long amount) {
        List<Map.Entry<Long, Long>> pairs = new ArrayList<>(table.entrySet());
        long numerator = 0;
        for (int i = 0; i < pairs.size(); ++i) {
            long lower = pairs.get(i).getKey();
            if (lower >= amount) break;
            long upper = i + 1 < pairs.size() ? pairs.get(i + 1).getKey() : amount;
            numerator += pairs.get(i).getValue() * (Math.min(amount, upper) - lower);
        }
        return numerator / 10000;
    }

    private record Shift(int start, int end) {}
    private record Daily(long worked, long regular, long overtime, long doubleTime,
                         long night, long pto) {
        long[] classified() { return new long[] {regular, overtime, doubleTime, night, pto}; }
    }
    private record Week(long[] values, long overtime) {}
    private record Row(String side, String label, long amount) {}

    private static final class Garnishment {
        long rate;
        long balance;

        Garnishment(long rate, long balance) {
            this.rate = rate;
            this.balance = balance;
        }
    }

    private static final class Stub {
        Map<String, Long> values = emptyTotals();
        List<Long> balances = new ArrayList<>();
        long garnishmentBalance;
        long ptoBalance;

        long get(String field) { return values.get(field); }
        void set(String field, long value) { values.put(field, value); }
    }

    private record StubRecord(Stub stub, String department) {}

    private static final class Employee {
        final int id;
        String department;
        final String kind;
        long base;
        boolean active = true;
        long retirement;
        long health;
        long allowances;
        long extra;
        List<Garnishment> garnishments = new ArrayList<>();
        long bonus;
        long ptoBalance;
        Map<Integer, List<Shift>> shifts = new HashMap<>();
        Map<Integer, Integer> pto = new HashMap<>();
        Set<Integer> leave = new HashSet<>();
        Map<Integer, Long> sales = new HashMap<>();
        Map<Integer, StubRecord> stubs = new HashMap<>();
        Map<String, Long> ytd = emptyTotals();
        int periods;

        Employee(int id, String department, String kind, long base) {
            this.id = id;
            this.department = department;
            this.kind = kind;
            this.base = base;
        }

        long garnishBalance() {
            long result = 0;
            for (Garnishment order : garnishments) result += order.balance;
            return result;
        }
    }

    private static final class Payroll {
        private final LinkedHashMap<String, Long> settings = new LinkedHashMap<>(INITIAL);
        private final TreeMap<Long, Long> brackets = new TreeMap<>();
        private final TreeMap<Long, Long> tiers = new TreeMap<>();
        private final Set<Integer> holidays = new HashSet<>();
        private final TreeMap<Integer, Employee> employees = new TreeMap<>();
        private final List<String> output = new ArrayList<>();
        private int closed;

        private void emit(int indent, Object... parts) {
            List<String> words = new ArrayList<>();
            for (Object part : parts) words.add(String.valueOf(part));
            output.add(" ".repeat(indent) + String.join(" ", words));
        }

        private void emitParts(int indent, List<?> parts) {
            emit(indent, parts.toArray());
        }

        private Employee employee(String text, boolean active, String kind) {
            Employee person = employees.get(Integer.parseInt(text));
            if (person == null) throw new PayrollError("unknown employee " + text);
            if (active && !person.active) throw new PayrollError("terminated employee " + text);
            if (kind != null && !person.kind.equals(kind))
                throw new PayrollError("not " + kind.toLowerCase() + " " + text);
            return person;
        }

        private Employee employee(String text) { return employee(text, false, null); }

        private int checkDay(String text) {
            int day = Integer.parseInt(text);
            if (day < 1 || day > 364) throw new PayrollError("invalid day " + text);
            int period = periodOf(day);
            if (period <= closed) throw new PayrollError("period closed " + period);
            return day;
        }

        private static int checkPeriod(String text) {
            int period = Integer.parseInt(text);
            if (period < 1 || period > 26) throw new PayrollError("invalid period " + text);
            return period;
        }

        private static long checkRate(String text) {
            long value = cents(text);
            if (value > 10000) throw new PayrollError("invalid rate " + text);
            return value;
        }

        private static long checkAmount(String text) {
            long value = cents(text);
            if (value == 0) throw new PayrollError("invalid amount");
            return value;
        }

        private static int checkTime(String text) {
            int hour = Integer.parseInt(text.substring(0, 2));
            int minute = Integer.parseInt(text.substring(3));
            if (hour > 23 || minute > 59) throw new PayrollError("invalid time " + text);
            return hour * 60 + minute;
        }

        private Daily daily(Employee person, int day) {
            List<Shift> shifts = person.shifts.getOrDefault(day, Collections.emptyList());
            long worked = 0, night = 0;
            for (Shift shift : shifts) {
                worked += shift.end() - shift.start();
                night += Math.max(0, Math.min(shift.end(), 360) - shift.start());
                night += Math.max(0, shift.end() - Math.max(shift.start(), 1320));
            }
            long pto = person.pto.getOrDefault(day, 0);
            if (day % 7 == 0 || holidays.contains(day))
                return new Daily(worked, 0, 0, worked, night, pto);
            return new Daily(worked, Math.min(worked, 480),
                             Math.min(Math.max(worked - 480, 0), 240),
                             Math.max(worked - 720, 0), night, pto);
        }

        private Week weekly(Employee person, int week) {
            long[] result = new long[5];
            for (int day = 7 * week - 6; day <= 7 * week; ++day) {
                long[] values = daily(person, day).classified();
                for (int i = 0; i < 5; ++i) result[i] += values[i];
            }
            long overtime = Math.max(0, result[0] - 2400);
            result[0] -= overtime;
            result[1] += overtime;
            return new Week(result, overtime);
        }

        private long[] breakdown(Employee person, int period) {
            long[] first = weekly(person, 2 * period - 1).values();
            long[] second = weekly(person, 2 * period).values();
            for (int i = 0; i < 5; ++i) first[i] += second[i];
            return first;
        }

        private Stub calculate(Employee person, int period) {
            Stub stub = new Stub();
            if (person.kind.equals("HOURLY")) {
                long[] hours = breakdown(person, period);
                for (int i = 0; i < 5; ++i) stub.set(FIELDS.get(i), hours[i]);
                long weighted = 2 * (hours[0] + hours[4]) + 3 * hours[1] + 4 * hours[2];
                stub.set("earnings", (weighted * person.base +
                         2 * hours[3] * settings.get("NIGHT")) / 120);
            } else if (person.kind.equals("SALARIED")) {
                if (person.active) {
                    stub.set("salary", person.base / 26);
                    long leave = person.leave.stream().filter(day ->
                        periodOf(day) == period && !holidays.contains(day)).count();
                    stub.set("leave", leave);
                    stub.set("deduction", leave * (person.base / 260));
                    stub.set("earnings", stub.get("salary") - stub.get("deduction"));
                }
            } else {
                stub.set("sales", person.sales.getOrDefault(period, 0L));
                stub.set("commission", progressive(tiers, stub.get("sales")));
                stub.set("earnings", stub.get("commission") + (person.active ? person.base : 0));
            }

            stub.set("bonus", person.bonus);
            long gross = stub.get("earnings") + stub.get("bonus");
            if (gross == 0) return null;
            stub.set("gross", gross);

            long remaining = gross;
            long retirementRoom = Math.max(0, settings.get("RETIRECAP") - person.ytd.get("retirement"));
            remaining = deduct(stub, "retirement",
                Math.min(gross * person.retirement / 10000, retirementRoom), remaining);
            remaining = deduct(stub, "health", person.health, remaining);
            stub.set("W", remaining);
            long baseTaxable = Math.max(0,
                stub.get("earnings") - stub.get("retirement") - stub.get("health"));
            long allowanceTaxable = Math.max(0, baseTaxable - person.allowances * settings.get("ALLOWANCE"));
            remaining = deduct(stub, "federal",
                progressive(brackets, allowanceTaxable) + person.extra, remaining);
            remaining = deduct(stub, "supplemental",
                (stub.get("W") - baseTaxable) * settings.get("SUPP") / 10000, remaining);
            remaining = deduct(stub, "state",
                stub.get("W") * settings.get("STATE") / 10000, remaining);

            long medicareWages = gross - stub.get("health");
            long socialWages = Math.min(medicareWages,
                Math.max(0, settings.get("SSBASE") - person.ytd.get("Y")));
            long additional = Math.max(0, Math.min(medicareWages,
                person.ytd.get("F") + medicareWages - settings.get("ADDBASE")));
            stub.set("F", medicareWages);
            stub.set("Y", socialWages);
            remaining = deduct(stub, "social",
                socialWages * settings.get("SSRATE") / 10000, remaining);
            remaining = deduct(stub, "medicare",
                medicareWages * settings.get("MEDRATE") / 10000 +
                additional * settings.get("ADDMED") / 10000, remaining);

            long disposable = remaining;
            long cap = disposable * settings.get("GARNCAP") / 10000;
            long garnished = 0;
            for (Garnishment order : person.garnishments) {
                long taken = Math.min(disposable * order.rate / 10000,
                    Math.min(order.balance, cap - garnished));
                garnished += taken;
                stub.balances.add(order.balance - taken);
            }
            stub.set("garnishment", garnished);
            stub.garnishmentBalance = stub.balances.stream().mapToLong(Long::longValue).sum();
            stub.set("net", remaining - garnished);
            stub.set("employer_social", socialWages * settings.get("SSRATE") / 10000);
            stub.set("employer_medicare", medicareWages * settings.get("MEDRATE") / 10000);
            stub.set("J", Math.min(medicareWages,
                Math.max(0, settings.get("UIBASE") - person.ytd.get("J"))));
            stub.set("unemployment", stub.get("J") * settings.get("UIRATE") / 10000);
            long eligibleMatch = Math.min(stub.get("retirement"),
                                          gross * settings.get("MATCHMAX") / 10000);
            stub.set("match", eligibleMatch * settings.get("MATCH") / 10000);
            stub.set("employer", stub.get("employer_social") + stub.get("employer_medicare") +
                    stub.get("unemployment") + stub.get("match"));
            if (person.kind.equals("HOURLY"))
                stub.set("accrued", Math.min(960 - person.ptoBalance,
                         (stub.get("R") + stub.get("O") + stub.get("D")) / 20));
            stub.ptoBalance = person.ptoBalance + stub.get("accrued");
            return stub;
        }

        private static long deduct(Stub stub, String field, long amount, long remaining) {
            long deduction = Math.min(amount, remaining);
            stub.set(field, deduction);
            return remaining - deduction;
        }

        private static List<Object> hoursParts(long[] hours) {
            String[] labels = {"reg", "ot", "dbl", "night", "pto"};
            List<Object> parts = new ArrayList<>();
            for (int i = 0; i < 5; ++i) {
                parts.add(labels[i]);
                parts.add(duration(hours[i]));
            }
            return parts;
        }

        private void stubBlock(Employee person, Map<String, Long> values,
                               long ptoBalance, long garnishBalance, int indent) {
            if (person.kind.equals("HOURLY")) {
                long[] hours = new long[5];
                for (int i = 0; i < 5; ++i) hours[i] = values.get(FIELDS.get(i));
                List<Object> parts = new ArrayList<>();
                parts.add("hours");
                parts.addAll(hoursParts(hours));
                emitParts(indent, parts);
                emit(indent, "pto", "accrued", duration(values.get("accrued")),
                     "balance", duration(ptoBalance));
            } else if (person.kind.equals("SALARIED")) {
                emit(indent, "salary", money(values.get("salary")), "leave", values.get("leave"),
                     "deduction", money(values.get("deduction")));
            } else {
                emit(indent, "sales", money(values.get("sales")),
                     "commission", money(values.get("commission")));
            }
            for (String field : List.of(
                    "earnings", "bonus", "gross", "retirement", "health", "federal",
                    "supplemental", "state", "social", "medicare")) {
                emit(indent, field.equals("social") ? "social-security" : field,
                     money(values.get(field)));
            }
            emit(indent, "garnishment", money(values.get("garnishment")),
                 "balance", money(garnishBalance));
            emit(indent, "net", money(values.get("net")));
            emit(indent, "employer", "social-security", money(values.get("employer_social")),
                 "medicare", money(values.get("employer_medicare")),
                 "unemployment", money(values.get("unemployment")),
                 "match", money(values.get("match")));
        }

        private void printStub(Employee person, int period, Stub stub, String department) {
            emit(2, "STUB", person.id, department, person.kind, "period", period);
            stubBlock(person, stub.values, stub.ptoBalance, stub.garnishmentBalance, 4);
        }

        private void showHours(Employee person, int period) {
            emit(0, "HOURS", person.id, "period", period);
            boolean found = false;
            for (int day = 14 * period - 13; day <= 14 * period; ++day) {
                List<Shift> shifts = new ArrayList<>(person.shifts.getOrDefault(day, List.of()));
                if (shifts.isEmpty() && !person.pto.containsKey(day)) continue;
                shifts.sort(Comparator.comparingInt(Shift::start));
                Daily daily = daily(person, day);
                List<Object> parts = new ArrayList<>(List.of("day", day, weekday(day)));
                if (holidays.contains(day)) parts.add("holiday");
                for (Shift shift : shifts)
                    parts.add(clock(shift.start()) + "-" + clock(shift.end()));
                parts.add("total");
                parts.add(duration(daily.worked()));
                parts.addAll(hoursParts(daily.classified()));
                emitParts(2, parts);
                found = true;
            }
            if (!found) emit(2, "(none)");
            for (int week : new int[] {2 * period - 1, 2 * period}) {
                Week breakdown = weekly(person, week);
                List<Object> parts = new ArrayList<>(List.of("week", week));
                parts.addAll(hoursParts(breakdown.values()));
                parts.add("weekly-ot");
                parts.add(duration(breakdown.overtime()));
                emitParts(2, parts);
            }
            List<Object> parts = new ArrayList<>();
            parts.add("total");
            parts.addAll(hoursParts(breakdown(person, period)));
            emitParts(2, parts);
        }

        private void run(int period) {
            closed = period;
            emit(0, "RUN", period, "days", (14 * period - 13) + "-" + (14 * period));
            int paid = 0, skipped = 0;
            List<Map<String, Long>> stubs = new ArrayList<>();
            for (Employee person : employees.values()) {
                Stub stub = calculate(person, period);
                if (stub == null) {
                    if (person.active) ++skipped;
                    continue;
                }
                printStub(person, period, stub, person.department);
                person.bonus = 0;
                person.ptoBalance = stub.ptoBalance;
                for (int i = 0; i < person.garnishments.size(); ++i)
                    person.garnishments.get(i).balance = stub.balances.get(i);
                for (String field : FIELDS)
                    person.ytd.merge(field, stub.get(field), Long::sum);
                ++person.periods;
                person.stubs.put(period, new StubRecord(stub, person.department));
                stubs.add(stub.values);
                ++paid;
            }
            Map<String, Long> totals = sumStubs(stubs);
            emit(2, "TOTAL", "paid", paid, "skipped", skipped,
                 "gross", money(totals.get("gross")),
                 "deductions", money(totals.get("gross") - totals.get("net")),
                 "net", money(totals.get("net")), "employer", money(totals.get("employer")));
        }

        private void journal(int period) {
            List<Map<String, Long>> stubs = new ArrayList<>();
            for (Employee person : employees.values()) {
                StubRecord record = person.stubs.get(period);
                if (record != null) stubs.add(record.stub().values);
            }
            Map<String, Long> sum = sumStubs(stubs);
            List<Row> rows = List.of(
                new Row("debit", "wages", sum.get("gross")),
                new Row("debit", "employer-tax",
                    sum.get("employer_social") + sum.get("employer_medicare") + sum.get("unemployment")),
                new Row("debit", "retirement-match", sum.get("match")),
                new Row("credit", "retirement", sum.get("retirement") + sum.get("match")),
                new Row("credit", "health", sum.get("health")),
                new Row("credit", "federal", sum.get("federal") + sum.get("supplemental")),
                new Row("credit", "state", sum.get("state")),
                new Row("credit", "fica", sum.get("social") + sum.get("medicare") +
                    sum.get("employer_social") + sum.get("employer_medicare")),
                new Row("credit", "unemployment", sum.get("unemployment")),
                new Row("credit", "garnishment", sum.get("garnishment")),
                new Row("credit", "net-pay", sum.get("net"))
            );
            emit(0, "JOURNAL", period, "stubs", stubs.size());
            long debit = 0, credit = 0;
            for (Row row : rows) {
                emit(2, row.side(), row.label(), money(row.amount()));
                if (row.side().equals("debit")) debit += row.amount();
                else credit += row.amount();
            }
            emit(2, "total", "debit", money(debit), "credit", money(credit));
        }

        private void reportLine(String department, List<Map<String, Long>> stubs) {
            Map<String, Long> sum = sumStubs(stubs);
            long taxes = sum.get("federal") + sum.get("supplemental") + sum.get("state") +
                         sum.get("social") + sum.get("medicare");
            emit(2, department, "stubs", stubs.size(), "gross", money(sum.get("gross")),
                 "pretax", money(sum.get("retirement") + sum.get("health")),
                 "taxes", money(taxes), "garnishment", money(sum.get("garnishment")),
                 "net", money(sum.get("net")), "employer", money(sum.get("employer")));
        }

        private void command(String command, String[] a) {
            switch (command) {
            case "SET": {
                String name = a[0];
                if (!settings.containsKey(name))
                    throw new PayrollError("unknown setting " + name);
                boolean rate = RATE_SETTINGS.contains(name);
                long value = rate ? checkRate(a[1]) : cents(a[1]);
                long previous = settings.get(name);
                settings.put(name, value);
                emit(0, "SET", name, rate ? rateText(previous) : money(previous), "->",
                     rate ? rateText(value) : money(value));
                break;
            }
            case "BRACKET":
            case "TIER": {
                long rate = checkRate(a[1]);
                TreeMap<Long, Long> table = command.equals("BRACKET") ? brackets : tiers;
                long lower = cents(a[0]);
                String action = table.containsKey(lower) ? "replaced" : "added";
                table.put(lower, rate);
                emit(0, command, money(lower), rateText(rate), action);
                break;
            }
            case "EMP": {
                int id = Integer.parseInt(a[0]);
                if (employees.containsKey(id))
                    throw new PayrollError("duplicate employee " + a[0]);
                long base = checkAmount(a[3]);
                employees.put(id, new Employee(id, a[1], a[2], base));
                emit(0, "EMP", id, a[1], a[2], money(base));
                break;
            }
            case "RATE":
            case "DEPT":
            case "BENEFIT":
            case "W4":
            case "GARNISH":
            case "TERM":
            case "BONUS": {
                Employee person = employee(a[0], true, null);
                switch (command) {
                case "RATE": {
                    long amount = checkAmount(a[1]);
                    long previous = person.base;
                    person.base = amount;
                    emit(0, "RATE", person.id, money(previous), "->", money(amount));
                    break;
                }
                case "DEPT": {
                    if (person.department.equals(a[1]))
                        throw new PayrollError("same department " + a[1]);
                    String previous = person.department;
                    person.department = a[1];
                    emit(0, "DEPT", person.id, previous, "->", a[1]);
                    break;
                }
                case "BENEFIT": {
                    long rate = checkRate(a[1]);
                    person.retirement = rate;
                    person.health = cents(a[2]);
                    emit(0, "BENEFIT", person.id, "retirement", rateText(rate),
                         "health", money(person.health));
                    break;
                }
                case "W4":
                    person.allowances = Long.parseLong(a[1]);
                    person.extra = cents(a[2]);
                    emit(0, "W4", person.id, "allowances", person.allowances,
                         "extra", money(person.extra));
                    break;
                case "GARNISH": {
                    long rate = checkRate(a[1]);
                    long balance = checkAmount(a[2]);
                    person.garnishments.add(new Garnishment(rate, balance));
                    emit(0, "GARNISH", person.id, "order", person.garnishments.size(),
                         rateText(rate), "balance", money(balance));
                    break;
                }
                case "TERM":
                    person.active = false;
                    emit(0, "TERM", person.id);
                    break;
                default: {
                    long bonus = checkAmount(a[1]);
                    person.bonus += bonus;
                    emit(0, "BONUS", person.id, money(bonus), "pending", money(person.bonus));
                    break;
                }
                }
                break;
            }
            case "HOLIDAY": {
                int day = checkDay(a[0]);
                if (holidays.contains(day)) throw new PayrollError("duplicate holiday " + a[0]);
                holidays.add(day);
                emit(0, "HOLIDAY", day, weekday(day));
                break;
            }
            case "TIME":
            case "UNTIME":
            case "PTO":
            case "LEAVE":
            case "SALES": {
                String kind = command.equals("LEAVE") ? "SALARIED" :
                              command.equals("SALES") ? "COMMISSION" : "HOURLY";
                Employee person = employee(a[0], true, kind);
                int day = checkDay(a[1]);
                switch (command) {
                case "TIME": {
                    int start = checkTime(a[2]), end = checkTime(a[3]);
                    if (start >= end)
                        throw new PayrollError("invalid shift " + a[2] + "-" + a[3]);
                    List<Shift> shifts = new ArrayList<>(person.shifts.getOrDefault(day, List.of()));
                    shifts.sort(Comparator.comparingInt(Shift::start));
                    for (Shift shift : shifts) {
                        if (start < shift.end() && shift.start() < end) {
                            throw new PayrollError("overlapping shift " +
                                clock(shift.start()) + "-" + clock(shift.end()));
                        }
                    }
                    int worked = end - start;
                    for (Shift shift : shifts) worked += shift.end() - shift.start();
                    if (worked > 960)
                        throw new PayrollError("daily limit " + a[0] + " " + a[1]);
                    person.shifts.computeIfAbsent(day, key -> new ArrayList<>())
                                 .add(new Shift(start, end));
                    emit(0, "TIME", person.id, "day", day,
                         clock(start) + "-" + clock(end), duration(end - start));
                    break;
                }
                case "UNTIME": {
                    int start = checkTime(a[2]);
                    List<Shift> shifts = person.shifts.getOrDefault(day, List.of());
                    Shift found = null;
                    for (Shift shift : shifts) {
                        if (shift.start() == start) { found = shift; break; }
                    }
                    if (found == null)
                        throw new PayrollError("no shift " + a[0] + " " + a[1] + " " + a[2]);
                    shifts.remove(found);
                    emit(0, "UNTIME", person.id, "day", day,
                         clock(found.start()) + "-" + clock(found.end()));
                    break;
                }
                case "PTO": {
                    int hour = Integer.parseInt(a[2].substring(0, 2));
                    int minute = Integer.parseInt(a[2].substring(3));
                    int length = hour * 60 + minute;
                    if (minute > 59 || length < 1 || length > 480)
                        throw new PayrollError("invalid duration " + a[2]);
                    if (person.pto.containsKey(day))
                        throw new PayrollError("duplicate pto " + a[0] + " " + a[1]);
                    if (length > person.ptoBalance)
                        throw new PayrollError("insufficient pto " + a[0] + " " + duration(person.ptoBalance));
                    person.pto.put(day, length);
                    person.ptoBalance -= length;
                    emit(0, "PTO", person.id, "day", day, duration(length),
                         "balance", duration(person.ptoBalance));
                    break;
                }
                case "LEAVE": {
                    if (day % 7 == 0 || day % 7 == 6 || holidays.contains(day))
                        throw new PayrollError("not workday " + a[1]);
                    if (person.leave.contains(day))
                        throw new PayrollError("duplicate leave " + a[0] + " " + a[1]);
                    person.leave.add(day);
                    emit(0, "LEAVE", person.id, "day", day, weekday(day));
                    break;
                }
                default: {
                    long amount = checkAmount(a[2]);
                    int period = periodOf(day);
                    person.sales.merge(period, amount, Long::sum);
                    emit(0, "SALES", person.id, "day", day, money(amount),
                         "period", period, "total", money(person.sales.get(period)));
                }
                }
                break;
            }
            case "HOURS": {
                Employee person = employee(a[0], false, "HOURLY");
                showHours(person, checkPeriod(a[1]));
                break;
            }
            case "RUN": {
                int period = Integer.parseInt(a[0]);
                if (period != closed + 1 || period > 26)
                    throw new PayrollError("invalid period " + a[0]);
                run(period);
                break;
            }
            case "PREVIEW": {
                Employee person = employee(a[0]);
                int period = closed + 1;
                Stub stub = calculate(person, period);
                emit(0, "PREVIEW", person.id, "period", period);
                if (stub == null) emit(2, "no pay");
                else printStub(person, period, stub, person.department);
                break;
            }
            case "REPRINT": {
                Employee person = employee(a[0]);
                int period = checkPeriod(a[1]);
                StubRecord record = person.stubs.get(period);
                if (record == null)
                    throw new PayrollError("no stub " + a[0] + " " + a[1]);
                emit(0, "REPRINT", person.id, period);
                printStub(person, period, record.stub(), record.department());
                break;
            }
            case "YTD": {
                Employee person = employee(a[0]);
                emit(0, "YTD", person.id, person.department, person.kind,
                     person.active ? "active" : "terminated", "periods", person.periods);
                stubBlock(person, person.ytd, person.ptoBalance, person.garnishBalance(), 2);
                emit(2, "wages", "federal", money(person.ytd.get("W")),
                     "social-security", money(person.ytd.get("Y")),
                     "medicare", money(person.ytd.get("F")),
                     "unemployment", money(person.ytd.get("J")));
                emit(2, "retirement-room",
                     money(Math.max(0, settings.get("RETIRECAP") - person.ytd.get("retirement"))),
                     "pending-bonus", money(person.bonus));
                break;
            }
            case "JOURNAL": {
                int period = Integer.parseInt(a[0]);
                if (period < 1 || period > closed)
                    throw new PayrollError("no run " + a[0]);
                journal(period);
                break;
            }
            case "REPORT": {
                TreeMap<String, List<Map<String, Long>>> departments = new TreeMap<>();
                List<Map<String, Long>> all = new ArrayList<>();
                for (Employee person : employees.values()) {
                    for (StubRecord record : person.stubs.values()) {
                        departments.computeIfAbsent(record.department(), key -> new ArrayList<>())
                                   .add(record.stub().values);
                        all.add(record.stub().values);
                    }
                }
                emit(0, "REPORT", "period", closed);
                for (Map.Entry<String, List<Map<String, Long>>> entry : departments.entrySet())
                    reportLine(entry.getKey(), entry.getValue());
                reportLine("total", all);
                break;
            }
            case "TOP": {
                int count = Integer.parseInt(a[0]);
                List<Employee> ranking = new ArrayList<>();
                for (Employee person : employees.values())
                    if (person.periods > 0) ranking.add(person);
                ranking.sort(Comparator.comparingLong(
                    (Employee person) -> person.ytd.get("gross")).reversed()
                    .thenComparingInt(person -> person.id));
                emit(0, "TOP", count);
                for (int i = 0; i < Math.min(count, ranking.size()); ++i) {
                    Employee person = ranking.get(i);
                    emit(2, i + 1, person.id, person.department, "gross",
                         money(person.ytd.get("gross")), "net", money(person.ytd.get("net")));
                }
                if (ranking.isEmpty()) emit(2, "(none)");
                break;
            }
            case "EMPLOYEES": {
                emit(0, "EMPLOYEES");
                for (Employee person : employees.values()) {
                    emit(2, person.id, person.department, person.kind, money(person.base),
                         person.active ? "active" : "terminated",
                         "retirement", rateText(person.retirement),
                         "health", money(person.health),
                         "allowances", person.allowances,
                         "extra", money(person.extra), "bonus", money(person.bonus));
                    for (int i = 0; i < person.garnishments.size(); ++i) {
                        Garnishment order = person.garnishments.get(i);
                        emit(4, "garnish", i + 1, rateText(order.rate),
                             "balance", money(order.balance));
                    }
                }
                if (employees.isEmpty()) emit(2, "(none)");
                break;
            }
            case "CONFIG": {
                emit(0, "CONFIG");
                for (Map.Entry<String, Long> entry : settings.entrySet()) {
                    boolean rate = RATE_SETTINGS.contains(entry.getKey());
                    emit(2, entry.getKey(), rate ? rateText(entry.getValue()) : money(entry.getValue()));
                }
                for (Map.Entry<Long, Long> entry : brackets.entrySet())
                    emit(2, "bracket", money(entry.getKey()), rateText(entry.getValue()));
                for (Map.Entry<Long, Long> entry : tiers.entrySet())
                    emit(2, "tier", money(entry.getKey()), rateText(entry.getValue()));
                break;
            }
            default:
                break;
            }
        }

        void execute(String line) {
            String[] parts = line.split(" ");
            try {
                command(parts[0], Arrays.copyOfRange(parts, 1, parts.length));
            } catch (PayrollError error) {
                emit(0, "ERROR", error.getMessage());
            }
        }

        void print() {
            for (String line : output) System.out.println(line);
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        Payroll payroll = new Payroll();
        for (int i = 0; i < count; ++i) payroll.execute(input.readLine());
        payroll.print();
    }
}
