using System;
using System.Collections.Generic;
using System.Linq;

static class Program
{
    private static readonly string[] RateSettings =
    {
        "STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED",
        "UIRATE", "MATCH", "MATCHMAX", "GARNCAP"
    };

    private static readonly (string Name, long Value)[] InitialSettings =
    {
        ("STATE", 500), ("SUPP", 2200), ("SSRATE", 620),
        ("MEDRATE", 145), ("ADDMED", 90), ("UIRATE", 270),
        ("MATCH", 5000), ("MATCHMAX", 600), ("GARNCAP", 2500),
        ("SSBASE", 16860000), ("ADDBASE", 20000000),
        ("UIBASE", 700000), ("RETIRECAP", 2300000),
        ("ALLOWANCE", 15000), ("NIGHT", 100)
    };

    private static readonly string[] Fields =
    {
        "R", "O", "D", "N", "P", "accrued", "salary", "leave", "deduction",
        "sales", "commission", "earnings", "bonus", "gross", "retirement", "health",
        "federal", "supplemental", "state", "social", "medicare", "garnishment",
        "net", "employer_social", "employer_medicare", "unemployment", "match",
        "employer", "W", "Y", "F", "J"
    };

    private static readonly string[] Weekdays = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };

    private sealed class PayrollError : Exception
    {
        public PayrollError(string message) : base(message) {}
    }

    private static long Cents(string text)
    {
        var parts = text.Split('.');
        return long.Parse(parts[0]) * 100 + long.Parse(parts[1]);
    }

    private static string Money(long value) => $"{value / 100}.{value % 100:00}";
    private static string RateText(long value) => Money(value) + "%";
    private static string Duration(long minutes) => $"{minutes / 60}:{minutes % 60:00}";
    private static string Clock(int minutes) => $"{minutes / 60:00}:{minutes % 60:00}";
    private static string Weekday(int day) => Weekdays[(day - 1) % 7];
    private static int PeriodOf(int day) => (day - 1) / 14 + 1;

    private static Dictionary<string, long> EmptyTotals() =>
        Fields.ToDictionary(field => field, _ => 0L);

    private static Dictionary<string, long> SumStubs(IEnumerable<Dictionary<string, long>> stubs)
    {
        var result = EmptyTotals();
        foreach (var stub in stubs)
            foreach (string field in Fields)
                result[field] += stub[field];
        return result;
    }

    private static long Progressive(SortedDictionary<long, long> table, long amount)
    {
        var pairs = table.ToArray();
        long numerator = 0;
        for (int i = 0; i < pairs.Length; ++i)
        {
            long lower = pairs[i].Key;
            if (lower >= amount) break;
            long upper = i + 1 < pairs.Length ? pairs[i + 1].Key : amount;
            numerator += pairs[i].Value * (Math.Min(amount, upper) - lower);
        }
        return numerator / 10000;
    }

    private sealed class Garnishment
    {
        public long Rate;
        public long Balance;

        public Garnishment(long rate, long balance)
        {
            Rate = rate;
            Balance = balance;
        }
    }

    private readonly record struct Shift(int Start, int End);

    private sealed class Stub
    {
        public Dictionary<string, long> Values = EmptyTotals();
        public List<long> Balances = new();
        public long GarnishmentBalance;
        public long PtoBalance;

        public long this[string field]
        {
            get => Values[field];
            set => Values[field] = value;
        }
    }

    private sealed class StubRecord
    {
        public Stub Stub;
        public string Department;

        public StubRecord(Stub stub, string department)
        {
            Stub = stub;
            Department = department;
        }
    }

    private sealed class Employee
    {
        public int Id;
        public string Department;
        public string Kind;
        public long Base;
        public bool Active = true;
        public long Retirement;
        public long Health;
        public long Allowances;
        public long Extra;
        public List<Garnishment> Garnishments = new();
        public long Bonus;
        public long PtoBalance;
        public Dictionary<int, List<Shift>> Shifts = new();
        public Dictionary<int, int> Pto = new();
        public HashSet<int> Leave = new();
        public Dictionary<int, long> Sales = new();
        public SortedDictionary<int, StubRecord> Stubs = new();
        public Dictionary<string, long> Ytd = EmptyTotals();
        public int Periods;

        public Employee(int id, string department, string kind, long base)
        {
            Id = id;
            Department = department;
            Kind = kind;
            Base = base;
        }

        public long GarnishmentBalance => Garnishments.Sum(order => order.Balance);
    }

    private readonly record struct Daily(
        long Worked, long Regular, long Overtime, long Double, long Night, long Pto);

    private sealed class Payroll
    {
        private readonly Dictionary<string, long> settings =
            InitialSettings.ToDictionary(entry => entry.Name, entry => entry.Value);
        private readonly SortedDictionary<long, long> brackets = new();
        private readonly SortedDictionary<long, long> tiers = new();
        private readonly HashSet<int> holidays = new();
        private readonly SortedDictionary<int, Employee> employees = new();
        private readonly List<string> output = new();
        private int closed;

        private void Emit(int indent, params object[] parts)
        {
            output.Add(new string(' ', indent) + string.Join(" ", parts.Select(part => part.ToString())));
        }

        private Employee GetEmployee(string text, bool active = false, string? kind = null)
        {
            int id = int.Parse(text);
            if (!employees.TryGetValue(id, out var employee))
                throw new PayrollError("unknown employee " + text);
            if (active && !employee.Active)
                throw new PayrollError("terminated employee " + text);
            if (kind != null && employee.Kind != kind)
                throw new PayrollError("not " + kind.ToLowerInvariant() + " " + text);
            return employee;
        }

        private int CheckDay(string text)
        {
            int day = int.Parse(text);
            if (day < 1 || day > 364) throw new PayrollError("invalid day " + text);
            int period = PeriodOf(day);
            if (period <= closed) throw new PayrollError($"period closed {period}");
            return day;
        }

        private static int CheckPeriod(string text)
        {
            int period = int.Parse(text);
            if (period < 1 || period > 26) throw new PayrollError("invalid period " + text);
            return period;
        }

        private static long CheckRate(string text)
        {
            long rate = Cents(text);
            if (rate > 10000) throw new PayrollError("invalid rate " + text);
            return rate;
        }

        private static long CheckAmount(string text)
        {
            long amount = Cents(text);
            if (amount == 0) throw new PayrollError("invalid amount");
            return amount;
        }

        private static int CheckTime(string text)
        {
            string[] parts = text.Split(':');
            int hour = int.Parse(parts[0]), minute = int.Parse(parts[1]);
            if (hour > 23 || minute > 59) throw new PayrollError("invalid time " + text);
            return hour * 60 + minute;
        }

        private Daily DailyBreakdown(Employee employee, int day)
        {
            var shifts = employee.Shifts.GetValueOrDefault(day) ?? new List<Shift>();
            long worked = shifts.Sum(shift => shift.End - shift.Start);
            long night = 0;
            foreach (var shift in shifts)
            {
                night += Math.Max(0, Math.Min(shift.End, 360) - shift.Start);
                night += Math.Max(0, shift.End - Math.Max(shift.Start, 1320));
            }
            long pto = employee.Pto.GetValueOrDefault(day);
            if (day % 7 == 0 || holidays.Contains(day))
                return new Daily(worked, 0, 0, worked, night, pto);
            return new Daily(
                worked, Math.Min(worked, 480),
                Math.Min(Math.Max(0, worked - 480), 240),
                Math.Max(0, worked - 720), night, pto
            );
        }

        private (long[] Values, long WeeklyOvertime) Weekly(Employee employee, int week)
        {
            var result = new long[5];
            for (int day = 7 * week - 6; day <= 7 * week; ++day)
            {
                var current = DailyBreakdown(employee, day);
                result[0] += current.Regular;
                result[1] += current.Overtime;
                result[2] += current.Double;
                result[3] += current.Night;
                result[4] += current.Pto;
            }
            long overtime = Math.Max(0, result[0] - 2400);
            result[0] -= overtime;
            result[1] += overtime;
            return (result, overtime);
        }

        private long[] Breakdown(Employee employee, int period)
        {
            var first = Weekly(employee, 2 * period - 1).Values;
            var second = Weekly(employee, 2 * period).Values;
            return first.Zip(second, (a, b) => a + b).ToArray();
        }

        private Stub? Calculate(Employee employee, int period)
        {
            var stub = new Stub();
            if (employee.Kind == "HOURLY")
            {
                var hours = Breakdown(employee, period);
                for (int i = 0; i < 5; ++i)
                    stub[Fields[i]] = hours[i];
                long weighted = 2 * (hours[0] + hours[4]) + 3 * hours[1] + 4 * hours[2];
                stub["earnings"] = (weighted * employee.Base + 2 * hours[3] * settings["NIGHT"]) / 120;
            }
            else if (employee.Kind == "SALARIED")
            {
                if (employee.Active)
                {
                    stub["salary"] = employee.Base / 26;
                    stub["leave"] = employee.Leave.Count(day =>
                        PeriodOf(day) == period && !holidays.Contains(day));
                    stub["deduction"] = stub["leave"] * (employee.Base / 260);
                    stub["earnings"] = stub["salary"] - stub["deduction"];
                }
            }
            else
            {
                stub["sales"] = employee.Sales.GetValueOrDefault(period);
                stub["commission"] = Progressive(tiers, stub["sales"]);
                stub["earnings"] = stub["commission"] + (employee.Active ? employee.Base : 0);
            }

            stub["bonus"] = employee.Bonus;
            long gross = stub["earnings"] + stub["bonus"];
            if (gross == 0) return null;
            stub["gross"] = gross;

            long remaining = gross;
            void Deduct(string field, long amount)
            {
                long deduction = Math.Min(amount, remaining);
                stub[field] = deduction;
                remaining -= deduction;
            }

            long retirementRoom = Math.Max(0, settings["RETIRECAP"] - employee.Ytd["retirement"]);
            Deduct("retirement", Math.Min(gross * employee.Retirement / 10000, retirementRoom));
            Deduct("health", employee.Health);
            stub["W"] = remaining;
            long baseTaxable = Math.Max(0, stub["earnings"] - stub["retirement"] - stub["health"]);
            long allowanceTaxable = Math.Max(0, baseTaxable - employee.Allowances * settings["ALLOWANCE"]);
            Deduct("federal", Progressive(brackets, allowanceTaxable) + employee.Extra);
            Deduct("supplemental", (stub["W"] - baseTaxable) * settings["SUPP"] / 10000);
            Deduct("state", stub["W"] * settings["STATE"] / 10000);

            long medicareWages = gross - stub["health"];
            long socialWages = Math.Min(medicareWages, Math.Max(0, settings["SSBASE"] - employee.Ytd["Y"]));
            long additional = Math.Max(0, Math.Min(medicareWages,
                employee.Ytd["F"] + medicareWages - settings["ADDBASE"]));
            stub["F"] = medicareWages;
            stub["Y"] = socialWages;
            Deduct("social", socialWages * settings["SSRATE"] / 10000);
            Deduct("medicare",
                medicareWages * settings["MEDRATE"] / 10000 + additional * settings["ADDMED"] / 10000);

            long disposable = remaining;
            long cap = disposable * settings["GARNCAP"] / 10000;
            long garnished = 0;
            foreach (var order in employee.Garnishments)
            {
                long taken = Math.Min(disposable * order.Rate / 10000,
                    Math.Min(order.Balance, cap - garnished));
                garnished += taken;
                stub.Balances.Add(order.Balance - taken);
            }
            stub["garnishment"] = garnished;
            stub.GarnishmentBalance = stub.Balances.Sum();
            stub["net"] = remaining - garnished;
            stub["employer_social"] = socialWages * settings["SSRATE"] / 10000;
            stub["employer_medicare"] = medicareWages * settings["MEDRATE"] / 10000;
            stub["J"] = Math.Min(medicareWages, Math.Max(0, settings["UIBASE"] - employee.Ytd["J"]));
            stub["unemployment"] = stub["J"] * settings["UIRATE"] / 10000;
            long eligibleMatch = Math.Min(stub["retirement"], gross * settings["MATCHMAX"] / 10000);
            stub["match"] = eligibleMatch * settings["MATCH"] / 10000;
            stub["employer"] =
                stub["employer_social"] + stub["employer_medicare"] +
                stub["unemployment"] + stub["match"];

            if (employee.Kind == "HOURLY")
                stub["accrued"] = Math.Min(960 - employee.PtoBalance,
                    (stub["R"] + stub["O"] + stub["D"]) / 20);
            stub.PtoBalance = employee.PtoBalance + stub["accrued"];
            return stub;
        }

        private static object[] HoursParts(IEnumerable<long> values)
        {
            string[] labels = { "reg", "ot", "dbl", "night", "pto" };
            var parts = new List<object>();
            foreach (var (label, value) in labels.Zip(values))
            {
                parts.Add(label);
                parts.Add(Duration(value));
            }
            return parts.ToArray();
        }

        private void StubBlock(Employee employee, Dictionary<string, long> stub,
                               long ptoBalance, long garnishmentBalance, int indent)
        {
            if (employee.Kind == "HOURLY")
            {
                Emit(indent, new object[] { "hours" }.Concat(
                    HoursParts(new[] { stub["R"], stub["O"], stub["D"], stub["N"], stub["P"] })
                ).ToArray());
                Emit(indent, "pto", "accrued", Duration(stub["accrued"]),
                     "balance", Duration(ptoBalance));
            }
            else if (employee.Kind == "SALARIED")
            {
                Emit(indent, "salary", Money(stub["salary"]), "leave", stub["leave"],
                     "deduction", Money(stub["deduction"]));
            }
            else
            {
                Emit(indent, "sales", Money(stub["sales"]), "commission", Money(stub["commission"]));
            }

            string[] deductions = {
                "earnings", "bonus", "gross", "retirement", "health", "federal",
                "supplemental", "state", "social", "medicare"
            };
            foreach (string field in deductions)
                Emit(indent, field == "social" ? "social-security" : field, Money(stub[field]));
            Emit(indent, "garnishment", Money(stub["garnishment"]),
                 "balance", Money(garnishmentBalance));
            Emit(indent, "net", Money(stub["net"]));
            Emit(indent, "employer", "social-security", Money(stub["employer_social"]),
                 "medicare", Money(stub["employer_medicare"]),
                 "unemployment", Money(stub["unemployment"]),
                 "match", Money(stub["match"]));
        }

        private void PrintStub(Employee employee, int period, Stub stub, string department)
        {
            Emit(2, "STUB", employee.Id, department, employee.Kind, "period", period);
            StubBlock(employee, stub.Values, stub.PtoBalance, stub.GarnishmentBalance, 4);
        }

        private void ShowHours(Employee employee, int period)
        {
            Emit(0, "HOURS", employee.Id, "period", period);
            bool found = false;
            for (int day = 14 * period - 13; day <= 14 * period; ++day)
            {
                var shifts = employee.Shifts.GetValueOrDefault(day) ?? new List<Shift>();
                if (shifts.Count == 0 && !employee.Pto.ContainsKey(day)) continue;
                var daily = DailyBreakdown(employee, day);
                var parts = new List<object> { "day", day, Weekday(day) };
                if (holidays.Contains(day)) parts.Add("holiday");
                foreach (var shift in shifts.OrderBy(item => item.Start))
                    parts.Add($"{Clock(shift.Start)}-{Clock(shift.End)}");
                parts.AddRange(new object[] { "total", Duration(daily.Worked) });
                parts.AddRange(HoursParts(new long[] {
                    daily.Regular, daily.Overtime, daily.Double, daily.Night, daily.Pto
                }));
                Emit(2, parts.ToArray());
                found = true;
            }
            if (!found) Emit(2, "(none)");
            foreach (int week in new[] { 2 * period - 1, 2 * period })
            {
                var (values, overtime) = Weekly(employee, week);
                Emit(2, new object[] { "week", week }
                    .Concat(HoursParts(values))
                    .Concat(new object[] { "weekly-ot", Duration(overtime) }).ToArray());
            }
            Emit(2, new object[] { "total" }.Concat(HoursParts(Breakdown(employee, period))).ToArray());
        }

        private void Run(int period)
        {
            closed = period;
            Emit(0, "RUN", period, "days", $"{14 * period - 13}-{14 * period}");
            int paid = 0, skipped = 0;
            var created = new List<Dictionary<string, long>>();
            foreach (var employee in employees.Values)
            {
                var stub = Calculate(employee, period);
                if (stub == null)
                {
                    if (employee.Active) skipped++;
                    continue;
                }

                PrintStub(employee, period, stub, employee.Department);
                employee.Bonus = 0;
                employee.PtoBalance = stub.PtoBalance;
                for (int i = 0; i < employee.Garnishments.Count; ++i)
                    employee.Garnishments[i].Balance = stub.Balances[i];
                foreach (string field in Fields)
                    employee.Ytd[field] += stub[field];
                employee.Periods++;
                employee.Stubs[period] = new StubRecord(stub, employee.Department);
                created.Add(stub.Values);
                paid++;
            }
            var total = SumStubs(created);
            Emit(2, "TOTAL", "paid", paid, "skipped", skipped, "gross", Money(total["gross"]),
                 "deductions", Money(total["gross"] - total["net"]),
                 "net", Money(total["net"]), "employer", Money(total["employer"]));
        }

        private void Journal(int period)
        {
            var stubs = employees.Values
                .Where(employee => employee.Stubs.ContainsKey(period))
                .Select(employee => employee.Stubs[period].Stub.Values);
            var total = SumStubs(stubs);
            var rows = new (string Side, string Label, long Amount)[] {
                ("debit", "wages", total["gross"]),
                ("debit", "employer-tax", total["employer_social"] + total["employer_medicare"] + total["unemployment"]),
                ("debit", "retirement-match", total["match"]),
                ("credit", "retirement", total["retirement"] + total["match"]),
                ("credit", "health", total["health"]),
                ("credit", "federal", total["federal"] + total["supplemental"]),
                ("credit", "state", total["state"]),
                ("credit", "fica", total["social"] + total["medicare"] + total["employer_social"] + total["employer_medicare"]),
                ("credit", "unemployment", total["unemployment"]),
                ("credit", "garnishment", total["garnishment"]),
                ("credit", "net-pay", total["net"])
            };
            Emit(0, "JOURNAL", period, "stubs", employees.Values.Count(employee => employee.Stubs.ContainsKey(period)));
            foreach (var row in rows)
                Emit(2, row.Side, row.Label, Money(row.Amount));
            Emit(2, "total", "debit", Money(rows.Where(row => row.Side == "debit").Sum(row => row.Amount)),
                 "credit", Money(rows.Where(row => row.Side == "credit").Sum(row => row.Amount)));
        }

        private void ReportLine(string department, IEnumerable<Dictionary<string, long>> stubs)
        {
            var all = stubs.ToList();
            var total = SumStubs(all);
            long taxes = total["federal"] + total["supplemental"] +
                         total["state"] + total["social"] + total["medicare"];
            Emit(2, department, "stubs", all.Count, "gross", Money(total["gross"]),
                 "pretax", Money(total["retirement"] + total["health"]),
                 "taxes", Money(taxes), "garnishment", Money(total["garnishment"]),
                 "net", Money(total["net"]), "employer", Money(total["employer"]));
        }

        private void Command(string command, string[] a)
        {
            if (command == "SET")
            {
                string name = a[0];
                if (!settings.ContainsKey(name)) throw new PayrollError("unknown setting " + name);
                bool rate = RateSettings.Contains(name);
                long value = rate ? CheckRate(a[1]) : Cents(a[1]);
                long old = settings[name];
                settings[name] = value;
                Emit(0, "SET", name, rate ? RateText(old) : Money(old), "->",
                     rate ? RateText(value) : Money(value));
            }
            else if (command == "BRACKET" || command == "TIER")
            {
                long rate = CheckRate(a[1]);
                var table = command == "BRACKET" ? brackets : tiers;
                long lower = Cents(a[0]);
                string action = table.ContainsKey(lower) ? "replaced" : "added";
                table[lower] = rate;
                Emit(0, command, Money(lower), RateText(rate), action);
            }
            else if (command == "EMP")
            {
                int id = int.Parse(a[0]);
                if (employees.ContainsKey(id)) throw new PayrollError("duplicate employee " + a[0]);
                long amount = CheckAmount(a[3]);
                employees[id] = new Employee(id, a[1], a[2], amount);
                Emit(0, "EMP", id, a[1], a[2], Money(amount));
            }
            else if (command is "RATE" or "DEPT" or "BENEFIT" or "W4" or "GARNISH" or "TERM" or "BONUS")
            {
                var employee = GetEmployee(a[0], active: true);
                switch (command)
                {
                    case "RATE":
                        long baseAmount = CheckAmount(a[1]);
                        long previous = employee.Base;
                        employee.Base = baseAmount;
                        Emit(0, "RATE", employee.Id, Money(previous), "->", Money(baseAmount));
                        break;
                    case "DEPT":
                        if (a[1] == employee.Department)
                            throw new PayrollError("same department " + a[1]);
                        string old = employee.Department;
                        employee.Department = a[1];
                        Emit(0, "DEPT", employee.Id, old, "->", a[1]);
                        break;
                    case "BENEFIT":
                        long retirement = CheckRate(a[1]);
                        employee.Retirement = retirement;
                        employee.Health = Cents(a[2]);
                        Emit(0, "BENEFIT", employee.Id, "retirement", RateText(retirement),
                             "health", Money(employee.Health));
                        break;
                    case "W4":
                        employee.Allowances = long.Parse(a[1]);
                        employee.Extra = Cents(a[2]);
                        Emit(0, "W4", employee.Id, "allowances", employee.Allowances,
                             "extra", Money(employee.Extra));
                        break;
                    case "GARNISH":
                        long rate = CheckRate(a[1]);
                        long balance = CheckAmount(a[2]);
                        employee.Garnishments.Add(new Garnishment(rate, balance));
                        Emit(0, "GARNISH", employee.Id, "order", employee.Garnishments.Count,
                             RateText(rate), "balance", Money(balance));
                        break;
                    case "TERM":
                        employee.Active = false;
                        Emit(0, "TERM", employee.Id);
                        break;
                    case "BONUS":
                        long bonus = CheckAmount(a[1]);
                        employee.Bonus += bonus;
                        Emit(0, "BONUS", employee.Id, Money(bonus), "pending", Money(employee.Bonus));
                        break;
                }
            }
            else if (command == "HOLIDAY")
            {
                int day = CheckDay(a[0]);
                if (holidays.Contains(day)) throw new PayrollError("duplicate holiday " + a[0]);
                holidays.Add(day);
                Emit(0, "HOLIDAY", day, Weekday(day));
            }
            else if (command is "TIME" or "UNTIME" or "PTO" or "LEAVE" or "SALES")
            {
                string kind = command == "LEAVE" ? "SALARIED" :
                              command == "SALES" ? "COMMISSION" : "HOURLY";
                var employee = GetEmployee(a[0], active: true, kind: kind);
                int day = CheckDay(a[1]);
                switch (command)
                {
                    case "TIME":
                        int start = CheckTime(a[2]);
                        int end = CheckTime(a[3]);
                        if (start >= end) throw new PayrollError($"invalid shift {a[2]}-{a[3]}");
                        var shifts = employee.Shifts.GetValueOrDefault(day) ?? new List<Shift>();
                        foreach (var shift in shifts.OrderBy(shift => shift.Start))
                        {
                            if (start < shift.End && shift.Start < end)
                                throw new PayrollError($"overlapping shift {Clock(shift.Start)}-{Clock(shift.End)}");
                        }
                        if (shifts.Sum(shift => shift.End - shift.Start) + end - start > 960)
                            throw new PayrollError($"daily limit {a[0]} {a[1]}");
                        if (!employee.Shifts.ContainsKey(day))
                            employee.Shifts[day] = shifts;
                        shifts.Add(new Shift(start, end));
                        Emit(0, "TIME", employee.Id, "day", day,
                             $"{Clock(start)}-{Clock(end)}", Duration(end - start));
                        break;
                    case "UNTIME":
                        int startTime = CheckTime(a[2]);
                        var existing = employee.Shifts.GetValueOrDefault(day) ?? new List<Shift>();
                        int index = existing.FindIndex(shift => shift.Start == startTime);
                        if (index < 0) throw new PayrollError($"no shift {a[0]} {a[1]} {a[2]}");
                        var removed = existing[index];
                        existing.RemoveAt(index);
                        Emit(0, "UNTIME", employee.Id, "day", day,
                             $"{Clock(removed.Start)}-{Clock(removed.End)}");
                        break;
                    case "PTO":
                        string[] timeParts = a[2].Split(':');
                        int hour = int.Parse(timeParts[0]), minute = int.Parse(timeParts[1]);
                        int length = hour * 60 + minute;
                        if (minute > 59 || length < 1 || length > 480)
                            throw new PayrollError("invalid duration " + a[2]);
                        if (employee.Pto.ContainsKey(day))
                            throw new PayrollError($"duplicate pto {a[0]} {a[1]}");
                        if (length > employee.PtoBalance)
                            throw new PayrollError($"insufficient pto {a[0]} {Duration(employee.PtoBalance)}");
                        employee.Pto[day] = length;
                        employee.PtoBalance -= length;
                        Emit(0, "PTO", employee.Id, "day", day, Duration(length),
                             "balance", Duration(employee.PtoBalance));
                        break;
                    case "LEAVE":
                        if (day % 7 == 0 || day % 7 == 6 || holidays.Contains(day))
                            throw new PayrollError("not workday " + a[1]);
                        if (employee.Leave.Contains(day))
                            throw new PayrollError($"duplicate leave {a[0]} {a[1]}");
                        employee.Leave.Add(day);
                        Emit(0, "LEAVE", employee.Id, "day", day, Weekday(day));
                        break;
                    case "SALES":
                        long amount = CheckAmount(a[2]);
                        int period = PeriodOf(day);
                        employee.Sales[period] = employee.Sales.GetValueOrDefault(period) + amount;
                        Emit(0, "SALES", employee.Id, "day", day, Money(amount),
                             "period", period, "total", Money(employee.Sales[period]));
                        break;
                }
            }
            else if (command == "HOURS")
            {
                var employee = GetEmployee(a[0], kind: "HOURLY");
                int period = CheckPeriod(a[1]);
                ShowHours(employee, period);
            }
            else if (command == "RUN")
            {
                int period = int.Parse(a[0]);
                if (period != closed + 1 || period > 26)
                    throw new PayrollError("invalid period " + a[0]);
                Run(period);
            }
            else if (command == "PREVIEW")
            {
                var employee = GetEmployee(a[0]);
                int period = closed + 1;
                var stub = Calculate(employee, period);
                Emit(0, "PREVIEW", employee.Id, "period", period);
                if (stub == null) Emit(2, "no pay");
                else PrintStub(employee, period, stub, employee.Department);
            }
            else if (command == "REPRINT")
            {
                var employee = GetEmployee(a[0]);
                int period = CheckPeriod(a[1]);
                if (!employee.Stubs.TryGetValue(period, out var record))
                    throw new PayrollError($"no stub {a[0]} {a[1]}");
                Emit(0, "REPRINT", employee.Id, period);
                PrintStub(employee, period, record.Stub, record.Department);
            }
            else if (command == "YTD")
            {
                var employee = GetEmployee(a[0]);
                Emit(0, "YTD", employee.Id, employee.Department, employee.Kind,
                     employee.Active ? "active" : "terminated", "periods", employee.Periods);
                StubBlock(employee, employee.Ytd, employee.PtoBalance,
                          employee.GarnishmentBalance, 2);
                Emit(2, "wages", "federal", Money(employee.Ytd["W"]),
                     "social-security", Money(employee.Ytd["Y"]),
                     "medicare", Money(employee.Ytd["F"]),
                     "unemployment", Money(employee.Ytd["J"]));
                Emit(2, "retirement-room",
                     Money(Math.Max(0, settings["RETIRECAP"] - employee.Ytd["retirement"])),
                     "pending-bonus", Money(employee.Bonus));
            }
            else if (command == "JOURNAL")
            {
                int period = int.Parse(a[0]);
                if (period < 1 || period > closed)
                    throw new PayrollError("no run " + a[0]);
                Journal(period);
            }
            else if (command == "REPORT")
            {
                var departments = new SortedDictionary<string, List<Dictionary<string, long>>>();
                var all = new List<Dictionary<string, long>>();
                foreach (var employee in employees.Values)
                {
                    foreach (var record in employee.Stubs.Values)
                    {
                        if (!departments.ContainsKey(record.Department))
                            departments[record.Department] = new();
                        departments[record.Department].Add(record.Stub.Values);
                        all.Add(record.Stub.Values);
                    }
                }
                Emit(0, "REPORT", "period", closed);
                foreach (var entry in departments)
                    ReportLine(entry.Key, entry.Value);
                ReportLine("total", all);
            }
            else if (command == "TOP")
            {
                int count = int.Parse(a[0]);
                var ranking = employees.Values.Where(employee => employee.Periods > 0)
                    .OrderByDescending(employee => employee.Ytd["gross"]).ThenBy(employee => employee.Id)
                    .Take(count).ToArray();
                Emit(0, "TOP", count);
                int rank = 0;
                foreach (var employee in ranking)
                    Emit(2, ++rank, employee.Id, employee.Department, "gross",
                         Money(employee.Ytd["gross"]), "net", Money(employee.Ytd["net"]));
                if (employees.Values.All(employee => employee.Periods == 0))
                    Emit(2, "(none)");
            }
            else if (command == "EMPLOYEES")
            {
                Emit(0, "EMPLOYEES");
                foreach (var employee in employees.Values)
                {
                    Emit(2, employee.Id, employee.Department, employee.Kind, Money(employee.Base),
                         employee.Active ? "active" : "terminated",
                         "retirement", RateText(employee.Retirement),
                         "health", Money(employee.Health), "allowances", employee.Allowances,
                         "extra", Money(employee.Extra), "bonus", Money(employee.Bonus));
                    for (int i = 0; i < employee.Garnishments.Count; ++i)
                    {
                        var order = employee.Garnishments[i];
                        Emit(4, "garnish", i + 1, RateText(order.Rate),
                             "balance", Money(order.Balance));
                    }
                }
                if (employees.Count == 0) Emit(2, "(none)");
            }
            else if (command == "CONFIG")
            {
                Emit(0, "CONFIG");
                foreach (var setting in InitialSettings)
                {
                    long value = settings[setting.Name];
                    Emit(2, setting.Name, RateSettings.Contains(setting.Name) ?
                         RateText(value) : Money(value));
                }
                foreach (var entry in brackets)
                    Emit(2, "bracket", Money(entry.Key), RateText(entry.Value));
                foreach (var entry in tiers)
                    Emit(2, "tier", Money(entry.Key), RateText(entry.Value));
            }
        }

        public void Execute(string line)
        {
            var parts = line.Split(' ');
            try
            {
                Command(parts[0], parts.Skip(1).ToArray());
            }
            catch (PayrollError error)
            {
                Emit(0, "ERROR", error.Message);
            }
        }

        public void Print()
        {
            foreach (string line in output)
                Console.WriteLine(line);
        }
    }

    private static void Main()
    {
        int count = int.Parse(Console.ReadLine()!);
        var payroll = new Payroll();
        for (int i = 0; i < count; ++i)
            payroll.Execute(Console.ReadLine()!);
        payroll.Print();
    }
}
