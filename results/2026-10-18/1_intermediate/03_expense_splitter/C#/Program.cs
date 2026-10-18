using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

static class CollectionExtensions {
    public static bool IsEmpty<T>(this ICollection<T> values) => values.Count == 0;
    public static bool IsEmpty(this string value) => value.Length == 0;
}
class Program {
    record Amount(long Value, string Currency);
    record Member(bool Active, long Day);
    record Part(string Name, long Value);
    record Settlement(long Day, long Record, string From, string To, Amount Amount, long Total);
    record Entry(long Day, long Record, string Label, long Change);
    record Transfer(string From, string To, long Amount);
    class Expense {
        public string id = "", category = "", mode = "";
        public Amount amount = new(0,"");
        public List<Part> payers = new(), participants = new();
        public long[] contributions = Array.Empty<long>(), shares = Array.Empty<long>();
        public long day, record, total, interval, next, copies;
    }
    class Problem : Exception {
        public Problem(string message) : base(message) {}
    }
    readonly SortedDictionary<string,Member> members = new(StringComparer.Ordinal);
    readonly SortedDictionary<string,long> currencies = new(StringComparer.Ordinal), budgets = new(StringComparer.Ordinal);
    readonly Dictionary<string,Expense> expenses = new(StringComparer.Ordinal);
    readonly HashSet<string> used = new(StringComparer.Ordinal);
    readonly List<Settlement> settlements = new();
    long day = 1, serial = 0;
    static void Fail(string message) { throw new Problem(message); }
    static long Money(string s) {
        int p = s.IndexOf('.');
        return long.Parse(s.Substring(0,p))*100+long.Parse(s.Substring(p+1));
    }
    static Amount ParseAmount(string s) {
        string[] parts = s.Split('@');
        return new Amount(Money(parts[0]),parts.Length == 2 ? parts[1] : "");
    }
    static string Pad(long n, int width) {
        string s = System.Convert.ToString(n,CultureInfo.InvariantCulture);
        return new string('0',Math.Max(0,width-s.Length))+s;
    }
    static string Fmt(long n) { return n/100+"."+Pad(n%100,2); }
    static string Signed(long n) { return n > 0 ? "+"+Fmt(n) : n < 0 ? "-"+Fmt(-n) : "0.00"; }
    static string Rate(long n) { return n/10000+"."+Pad(n%10000,4); }
    static string Percent(long p, long w) { return Fmt(p*10000/w)+"%"; }
    static string Note(Amount a) { return a.Currency.IsEmpty() ? "" : " ["+Fmt(a.Value)+" "+a.Currency+"]"; }
    void Registered(string name) {
        if (!members.ContainsKey(name)) Fail("unknown member "+name);
    }
    void Active(string name) {
        Registered(name);
        if (!members[name].Active) Fail("inactive member "+name);
    }
    long ConvertAmount(Amount a) {
        if (a.Currency.IsEmpty()) return a.Value;
        if (!currencies.ContainsKey(a.Currency)) Fail("unknown currency "+a.Currency);
        return (a.Value*currencies[a.Currency]+5000)/10000;
    }
    Expense GetExpense(string id) {
        Expense e = expenses.GetValueOrDefault(id);
        if (e == null) Fail("unknown expense "+id);
        return e;
    }
    void Thawed(Expense e) {
        foreach (Part p in e.payers) {
            if (!members[p.Name].Active) Fail("inactive member "+p.Name);
        }
        foreach (Part p in e.participants) {
            if (!members[p.Name].Active) Fail("inactive member "+p.Name);
        }
    }
    static long[] Distribute(long total, List<long> weights) {
        long sum = weights.Sum();
        long[] result = new long[weights.Count], remainders = new long[weights.Count];
        List<int> order = new();
        long allocated = 0;
        for (int i = 0; i < weights.Count; i++) {
            result[i] = total*weights[i]/sum;
            remainders[i] = total*weights[i]%sum;
            allocated += result[i];
            order.Add(i);
        }
        order = order.OrderByDescending(i => remainders[i]).ThenBy(i => i).ToList();
        for (int i = 0; i < total-allocated; i++) result[order[i]]++;
        return result;
    }
    static List<long> Weights(List<Part> parts) { return parts.Select(p => p.Value).ToList(); }
    void Compute(Expense e) {
        long a = e.amount.Value;
        e.total = ConvertAmount(e.amount);
        long sum = e.participants.Sum(p => p.Value);
        long[] portions = new long[e.participants.Count];
        if (e.mode.Equals("EXACT")) {
            if (sum != a) Fail("splits do not add up");
            for (int i = 0; i < portions.Length; i++) portions[i] = e.participants[i].Value;
        } else if (e.mode.Equals("PERCENT") || e.mode.Equals("SHARES")) {
            if (e.mode.Equals("PERCENT") && sum != 10000 || e.mode.Equals("SHARES") && sum == 0) Fail("splits do not add up");
            portions = Distribute(a,Weights(e.participants));
        } else {
            long extras = e.mode.Equals("ADJUST") ? sum : 0;
            if (extras > a) Fail("splits do not add up");
            int k = portions.Length;
            for (int i = 0; i < k; i++) {
                portions[i] = (a-extras)/k+(i < (a-extras)%k ? 1 : 0)+(e.mode.Equals("ADJUST") ? e.participants[i].Value : 0);
            }
        }
        e.shares = Distribute(e.total,portions.ToList());
        e.contributions = Distribute(e.total,Weights(e.payers));
    }
    Expense Build(string[] tokens) {
        Active(tokens[2]);
        Expense e = new Expense();
        e.amount = ParseAmount(tokens[3]);
        long total = ConvertAmount(e.amount);
        if (e.amount.Value == 0 || total == 0) Fail("invalid amount");
        e.category = tokens[4];
        e.mode = tokens[5];
        e.payers = new List<Part> { new Part(tokens[2],e.amount.Value) };
        e.participants = new();
        HashSet<string> seen = new(StringComparer.Ordinal);
        if (e.mode.Equals("EQUAL") && tokens[6].Equals("ALL")) {
            foreach (var member in members) {
                if (member.Value.Active) e.participants.Add(new Part(member.Key,0));
            }
        } else {
            for (int i = 6; i < tokens.Length; i++) {
                string[] part = tokens[i].Split(':');
                Active(part[0]);
                if (!seen.Add(part[0])) Fail("duplicate member "+part[0]);
                long value = part.Length == 1 ? 0 : e.mode.Equals("EXACT") || e.mode.Equals("ADJUST") ? Money(part[1]) : long.Parse(part[1]);
                e.participants.Add(new Part(part[0],value));
            }
        }
        Compute(e);
        return e;
    }
    List<Expense> Chronological() {
        return expenses.Values.OrderBy(e => e.day).ThenBy(e => e.record).ToList();
    }
    static bool Includes(Expense e, string name) {
        return e.payers.Any(p => p.Name == name) || e.participants.Any(p => p.Name == name);
    }
    SortedDictionary<string,long> Net(Expense e) {
        SortedDictionary<string,long> result = new(StringComparer.Ordinal);
        for (int i = 0; i < e.payers.Count; i++) AddBalance(result,e.payers[i].Name,e.contributions[i]);
        for (int i = 0; i < e.participants.Count; i++) AddBalance(result,e.participants[i].Name,-e.shares[i]);
        return result;
    }
    static void AddBalance(IDictionary<string,long> values, string name, long change) {
        values[name] = (values.TryGetValue(name,out long old) ? old : 0)+change;
    }
    SortedDictionary<string,long> Balances() {
        SortedDictionary<string,long> result = new(StringComparer.Ordinal);
        foreach (string name in members.Keys) result[name] = 0L;
        foreach (Expense e in expenses.Values) {
            foreach (var item in Net(e)) AddBalance(result,item.Key,item.Value);
        }
        foreach (Settlement s in settlements) {
            AddBalance(result,s.From,s.Total);
            AddBalance(result,s.To,-s.Total);
        }
        return result;
    }
    List<string> ActiveNames() { return members.Where(p => p.Value.Active).Select(p => p.Key).ToList(); }
    SortedDictionary<string,long> CategoryTotals() {
        SortedDictionary<string,long> result = new(StringComparer.Ordinal);
        foreach (Expense e in expenses.Values) AddBalance(result,e.category,e.total);
        return result;
    }
    void Warning(Expense e, List<string> output) {
        long? budget = budgets.TryGetValue(e.category,out long limit) ? limit : null;
        long spent = CategoryTotals().GetValueOrDefault(e.category);
        if (budget != null && spent > budget.Value) output.Add("  WARNING "+e.category+" over budget by "+Fmt(spent-budget.Value));
    }
    static string Pairs(List<Part> people, long[] values) {
        List<string> parts = new();
        for (int i = 0; i < people.Count; i++) parts.Add(people[i].Name+" "+Fmt(values[i]));
        return string.Join(" + ",parts);
    }
    static List<Transfer> Greedy(IDictionary<string,long> balances) {
        SortedDictionary<string,long> work = new SortedDictionary<string,long>(balances,StringComparer.Ordinal);
        List<Transfer> result = new();
        while (true) {
            string from = "", to = "";
            long minimum = 0, maximum = 0;
            foreach (var item in work) {
                if (item.Value < minimum) {
                    minimum = item.Value;
                    from = item.Key;
                }
                if (item.Value > maximum) {
                    maximum = item.Value;
                    to = item.Key;
                }
            }
            if (minimum == 0) break;
            long value = Math.Min(-minimum,maximum);
            result.Add(new Transfer(from,to,value));
            work[from] = minimum+value;
            work[to] = maximum-value;
        }
        return result;
    }
    long[][] Debts(List<string> names) {
        int n = names.Count;
        Dictionary<string,int> index = new(StringComparer.Ordinal);
        for (int i = 0; i < n; i++) index[names[i]] = i;
        long[][] result = Enumerable.Range(0,n).Select(_ => new long[n]).ToArray();
        foreach (Expense e in expenses.Values) {
            SortedDictionary<string,long> amounts = Net(e);
            List<string> borrowers = amounts.Where(p => p.Value < 0).Select(p => p.Key).ToList();
            List<string> lenders = amounts.Where(p => p.Value > 0).Select(p => p.Key).ToList();
            int a = 0, b = 0;
            while (a < borrowers.Count && b < lenders.Count) {
                string x = borrowers[a], y = lenders[b];
                long value = Math.Min(-amounts[x],amounts[y]);
                int i = index[x], j = index[y];
                result[i][j] += value;
                result[j][i] -= value;
                amounts[x] = amounts[x]+value;
                amounts[y] = amounts[y]-value;
                if (amounts[x] == 0) a++;
                if (amounts[y] == 0) b++;
            }
        }
        foreach (Settlement s in settlements) {
            int i = index[s.From], j = index[s.To];
            result[i][j] -= s.Total;
            result[j][i] += s.Total;
        }
        return result;
    }
    static List<int> Indexes(int mask, int n) {
        List<int> result = new();
        for (int i = 0; i < n; i++) {
            if ((mask&(1<<i)) != 0) result.Add(i);
        }
        return result;
    }
    static bool LexLess(List<int> a, List<int> b) {
        for (int i = 0; i < Math.Min(a.Count,b.Count); i++) {
            if (!a[i].Equals(b[i])) return a[i] < b[i];
        }
        return a.Count < b.Count;
    }
    List<string> Execute(string line) {
        string[] t = line.Split(' ');
        string command = t[0];
        List<string> output = new();
        switch (command) {
            case "DAY": {
                long d = long.Parse(t[1]);
                if (d <= day) Fail("invalid day "+t[1]);
                output.Add("DAY "+d);
                while (true) {
                    Expense template = expenses.Values.Where(e => e.interval > 0 && e.next <= d)
                        .OrderBy(e => e.next).ThenBy(e => e.record).FirstOrDefault();
                    if (template == null) break;
                    bool active = true;
                    foreach (Part p in template.payers) active &= members[p.Name].Active;
                    foreach (Part p in template.participants) active &= members[p.Name].Active;
                    if (!active || ConvertAmount(template.amount) == 0) {
                        template.interval = 0;
                        output.Add("  CANCEL "+template.id);
                    } else {
                        Expense copy = new Expense();
                        copy.id = template.id+"#"+(template.copies+2);
                        copy.day = template.next;
                        copy.record = ++serial;
                        copy.amount = template.amount;
                        copy.category = template.category;
                        copy.mode = template.mode;
                        copy.payers = template.payers;
                        copy.participants = template.participants;
                        Compute(copy);
                        expenses[copy.id] = copy;
                        used.Add(copy.id);
                        template.copies++;
                        template.next += template.interval;
                        output.Add("  RECUR "+copy.id+" "+Fmt(copy.total));
                        Warning(copy,output);
                    }
                }
                day = d;
                break;
            }
            case "MEMBER": {
                Member old = members.GetValueOrDefault(t[1]);
                if (old != null && old.Active) Fail("duplicate member "+t[1]);
                members[t[1]] = new Member(true,day);
                output.Add("MEMBER "+t[1]+(old == null ? " joined" : " rejoined"));
                break;
            }
            case "LEAVE": {
                Active(t[1]);
                if (Balances()[t[1]] != 0) Fail("member has a balance "+t[1]);
                members[t[1]] = new Member(false,day);
                output.Add("LEAVE "+t[1]);
                break;
            }
            case "CURRENCY": {
                long value = long.Parse(t[2]);
                long? old = currencies.TryGetValue(t[1],out long previous) ? previous : null;
                currencies[t[1]] = value;
                output.Add("CURRENCY "+t[1]+" "+Rate(value)+(old == null ? "" : " was "+Rate(old.Value)));
                break;
            }
            case "EXPENSE":
            case "EDIT": {
                Expense old = null;
                if (command.Equals("EXPENSE")) {
                    if (used.Contains(t[1])) Fail("duplicate id "+t[1]);
                } else {
                    old = GetExpense(t[1]);
                    Thawed(old);
                }
                Expense e = Build(t);
                e.id = t[1];
                e.day = old == null ? day : old.day;
                e.record = old == null ? ++serial : old.record;
                if (old != null) {
                    e.interval = old.interval;
                    e.next = old.next;
                    e.copies = old.copies;
                }
                expenses[e.id] = e;
                used.Add(e.id);
                output.Add(command+" "+e.id+" "+Fmt(e.total)+Note(e.amount)+" = "+Pairs(e.participants,e.shares));
                Warning(e,output);
                break;
            }
            case "PAYERS": {
                Expense e = GetExpense(t[1]);
                Thawed(e);
                List<Part> payers = new();
                HashSet<string> seen = new(StringComparer.Ordinal);
                long total = 0;
                for (int i = 2; i < t.Length; i++) {
                    string[] p = t[i].Split(':');
                    Active(p[0]);
                    if (!seen.Add(p[0])) Fail("duplicate member "+p[0]);
                    long value = Money(p[1]);
                    payers.Add(new Part(p[0],value));
                    total += value;
                }
                if (total != e.amount.Value) Fail("payers do not add up");
                long[] contributions = Distribute(e.total,Weights(payers));
                e.payers = payers;
                e.contributions = contributions;
                output.Add("PAYERS "+e.id+" "+Fmt(e.total)+Note(e.amount)+" = "+Pairs(payers,contributions));
                break;
            }
            case "DELETE": {
                Expense e = GetExpense(t[1]);
                Thawed(e);
                expenses.Remove(e.id);
                output.Add("DELETE "+e.id);
                break;
            }
            case "RECURRING": {
                Expense e = GetExpense(t[1]);
                e.interval = long.Parse(t[2]);
                e.next = day+e.interval;
                output.Add("RECURRING "+e.id+(e.interval == 0 ? " stopped" : " interval "+e.interval+" next "+e.next));
                break;
            }
            case "SETTLE": {
                Active(t[1]);
                Active(t[2]);
                if (t[1].Equals(t[2])) Fail("same member "+t[1]);
                Amount a = ParseAmount(t[3]);
                long total = ConvertAmount(a);
                if (a.Value == 0 || total == 0) Fail("invalid amount");
                settlements.Add(new Settlement(day,++serial,t[1],t[2],a,total));
                output.Add("SETTLE "+t[1]+" -> "+t[2]+" "+Fmt(total)+Note(a));
                break;
            }
            case "BUDGET": {
                long value = Money(t[2]);
                if (value == 0) budgets.Remove(t[1]);
                else budgets[t[1]] = value;
                output.Add("BUDGET "+t[1]+(value == 0 ? " removed" : " "+Fmt(value)));
                break;
            }
            case "BALANCES": {
                output.Add("BALANCES");
                IDictionary<string,long> balances = Balances();
                foreach (string name in ActiveNames()) output.Add("  "+name+" "+Signed(balances[name]));
                break;
            }
            case "OWES":
            case "MATRIX": {
                if (command.Equals("OWES")) Registered(t[1]);
                List<string> names = members.Keys.ToList();
                long[][] debt = Debts(names);
                output.Add(command.Equals("OWES") ? "OWES "+t[1] : "MATRIX");
                if (command.Equals("OWES")) {
                    int i = names.IndexOf(t[1]);
                    for (int j = 0; j < names.Count; j++) {
                        if (debt[i][j] > 0) output.Add("  "+t[1]+" owes "+names[j]+" "+Fmt(debt[i][j]));
                        if (debt[i][j] < 0) output.Add("  "+names[j]+" owes "+t[1]+" "+Fmt(-debt[i][j]));
                    }
                } else {
                    List<string> active = ActiveNames();
                    if (active.IsEmpty()) output.Add("  (none)");
                    else {
                        int l = active.Max(name => name.Length), width = l;
                        foreach (string a in active) {
                            foreach (string b in active) width = Math.Max(width,a.Equals(b) ? 1 : Fmt(Math.Max(0,debt[names.IndexOf(a)][names.IndexOf(b)])).Length);
                        }
                        StringBuilder header = new StringBuilder(new string(' ',l));
                        foreach (string name in active) header.Append("  ").Append(new string(' ',width-name.Length)).Append(name);
                        output.Add(header.ToString());
                        foreach (string a in active) {
                            StringBuilder row = new StringBuilder(a+new string(' ',l-a.Length));
                            foreach (string b in active) {
                                string cell = a.Equals(b) ? "-" : Fmt(Math.Max(0,debt[names.IndexOf(a)][names.IndexOf(b)]));
                                row.Append("  ").Append(new string(' ',width-cell.Length)).Append(cell);
                            }
                            output.Add(row.ToString());
                        }
                    }
                }
                break;
            }
            case "HISTORY": {
                Registered(t[1]);
                List<Entry> entries = new();
                foreach (Expense e in expenses.Values) {
                    if (Includes(e,t[1])) entries.Add(new Entry(e.day,e.record,e.id,Net(e)[t[1]]));
                }
                foreach (Settlement s in settlements) {
                    if (s.From.Equals(t[1]) || s.To.Equals(t[1])) entries.Add(new Entry(s.Day,s.Record,s.From+"->"+s.To,s.From.Equals(t[1]) ? s.Total : -s.Total));
                }
                entries = entries.OrderBy(e => e.Day).ThenBy(e => e.Record).ToList();
                output.Add("HISTORY "+t[1]);
                long balance = 0;
                foreach (Entry e in entries) {
                    balance += e.Change;
                    output.Add("  day "+e.Day+" "+e.Label+" "+Signed(e.Change)+" balance "+Signed(balance));
                }
                break;
            }
            case "CATEGORY": {
                output.Add("CATEGORY");
                SortedDictionary<string,long> totals = CategoryTotals();
                long all = totals.Values.Sum();
                List<string> categories = totals.Keys.OrderByDescending(name => totals[name]).ThenBy(name => name,StringComparer.Ordinal).ToList();
                foreach (string category in categories) {
                    long total = totals[category];
                    output.Add("  "+category+" "+Fmt(total)+" "+Percent(total,all));
                    SortedDictionary<string,long> shares = new(StringComparer.Ordinal);
                    foreach (Expense e in expenses.Values) {
                        if (e.category.Equals(category)) {
                            for (int i = 0; i < e.participants.Count; i++) AddBalance(shares,e.participants[i].Name,e.shares[i]);
                        }
                    }
                    foreach (string name in shares.Keys.Where(name => shares[name] != 0).OrderByDescending(name => shares[name]).ThenBy(name => name,StringComparer.Ordinal).ToList()) {
                        output.Add("    "+name+" "+Fmt(shares[name])+" "+Percent(shares[name],total));
                    }
                }
                break;
            }
            case "BUDGETS": {
                output.Add("BUDGETS");
                SortedDictionary<string,long> totals = CategoryTotals();
                foreach (var budget in budgets) {
                    long spent = totals.GetValueOrDefault(budget.Key), b = budget.Value;
                    output.Add("  "+budget.Key+" spent "+Fmt(spent)+" budget "+Fmt(b)+" used "+Percent(spent,b)+
                        (spent <= b ? " left "+Fmt(b-spent) : " over "+Fmt(spent-b)));
                }
                break;
            }
            case "TOTALS": {
                output.Add("TOTALS");
                foreach (string name in members.Keys) {
                    long paid = 0, share = 0, sent = 0, received = 0;
                    foreach (Expense e in expenses.Values) {
                        for (int i = 0; i < e.payers.Count; i++) {
                            if (e.payers[i].Name.Equals(name)) paid += e.contributions[i];
                        }
                        for (int i = 0; i < e.participants.Count; i++) {
                            if (e.participants[i].Name.Equals(name)) share += e.shares[i];
                        }
                    }
                    foreach (Settlement s in settlements) {
                        if (s.From.Equals(name)) sent += s.Total;
                        if (s.To.Equals(name)) received += s.Total;
                    }
                    output.Add("  "+name+" paid "+Fmt(paid)+" share "+Fmt(share)+" sent "+Fmt(sent)+" received "+Fmt(received));
                }
                foreach (string currency in currencies.Keys) {
                    List<Expense> group = expenses.Values.Where(e => e.amount.Currency == currency).ToList();
                    if (!group.IsEmpty()) output.Add("  currency "+currency+" expenses "+group.Count+" amount "+Fmt(group.Sum(e => e.amount.Value))+" base "+Fmt(group.Sum(e => e.total)));
                }
                output.Add("  expenses "+expenses.Count+" total "+Fmt(expenses.Values.Sum(e => e.total))+
                    " settlements "+settlements.Count+" total "+Fmt(settlements.Sum(s => s.Total)));
                break;
            }
            case "MEMBERS": {
                output.Add("MEMBERS");
                foreach (var m in members) {
                    long count = expenses.Values.Count(e => Includes(e,m.Key));
                    output.Add("  "+m.Key+(m.Value.Active ? " active" : " left")+" day "+m.Value.Day+" expenses "+count);
                }
                break;
            }
            case "EXPENSES": {
                if (t[1].Equals("MEMBER")) Registered(t[2]);
                output.Add(line);
                long count = 0, total = 0;
                foreach (Expense e in Chronological()) {
                    bool matches = t[1] switch {
                        "CATEGORY" => e.category.Equals(t[2]),
                        "MEMBER" => Includes(e,t[2]),
                        "DAYS" => e.day >= long.Parse(t[2]) && e.day <= long.Parse(t[3]),
                        _ => true
                    };
                    if (matches) {
                        output.Add("  day "+e.day+" "+e.id+" "+e.category+" "+Fmt(e.total)+" by "+string.Join(",",e.payers.Select(p => p.Name).ToList()));
                        count++;
                        total += e.total;
                    }
                }
                output.Add("  count "+count+" total "+Fmt(total));
                break;
            }
            case "PERIODS": {
                long k = long.Parse(t[1]);
                output.Add("PERIODS "+k);
                SortedDictionary<long,List<Expense>> groups = new();
                foreach (Expense e in expenses.Values) {
                    long key = (e.day-1)/k;
                    if (!groups.TryGetValue(key,out var group)) {
                        group = new List<Expense>();
                        groups[key] = group;
                    }
                    group.Add(e);
                }
                foreach (var group in groups) {
                    long i = group.Key;
                    output.Add("  days "+(i*k+1)+"-"+(i*k+k)+" expenses "+group.Value.Count+" total "+Fmt(group.Value.Sum(e => e.total)));
                }
                break;
            }
            case "SHOW": {
                Expense e = GetExpense(t[1]);
                output.Add("SHOW "+e.id);
                output.Add("  day "+e.day+" category "+e.category+" mode "+e.mode+" total "+Fmt(e.total)+Note(e.amount));
                for (int i = 0; i < e.payers.Count; i++) output.Add("  paid "+e.payers[i].Name+" "+Fmt(e.contributions[i]));
                long sum = e.participants.Sum(p => p.Value);
                for (int i = 0; i < e.participants.Count; i++) {
                    Part p = e.participants[i];
                    string suffix = e.mode switch {
                        "EXACT" => " "+Fmt(p.Value),
                        "PERCENT" => " "+Fmt(p.Value)+"%",
                        "SHARES" => " "+p.Value+"/"+sum,
                        "ADJUST" => " +"+Fmt(p.Value),
                        _ => ""
                    };
                    output.Add("  share "+p.Name+" "+Fmt(e.shares[i])+suffix);
                }
                if (e.interval > 0) output.Add("  recurring interval "+e.interval+" next "+e.next);
                break;
            }
            case "SIMPLIFY": {
                SortedDictionary<string,long> all = Balances();
                foreach (string key in all.Keys.Where(key => all[key] == 0).ToList()) all.Remove(key);
                if (t[1].Equals("GREEDY")) {
                    List<Transfer> transfers = Greedy(all);
                    output.Add("SIMPLIFY GREEDY transfers "+transfers.Count);
                    foreach (Transfer x in transfers) output.Add("  "+x.From+" -> "+x.To+" "+Fmt(x.Amount));
                } else {
                    List<string> names = all.Keys.ToList();
                    int n = names.Count;
                    if (n > 12) Fail("too many members");
                    int size = 1<<n;
                    long[] sums = new long[size];
                    int[] dp = new int[size];
                    Array.Fill(dp,-1000);
                    dp[0] = 0;
                    for (int mask = 1; mask < size; mask++) {
                        int bit = System.Numerics.BitOperations.TrailingZeroCount((uint)mask);
                        sums[mask] = sums[mask^(1<<bit)]+all[names[bit]];
                        int first = mask&-mask;
                        for (int sub = mask; sub > 0; sub = (sub-1)&mask) {
                            if ((sub&first) != 0 && sums[sub] == 0) dp[mask] = Math.Max(dp[mask],1+dp[mask^sub]);
                        }
                    }
                    int remaining = size-1;
                    List<int> groups = new();
                    while (remaining != 0) {
                        int first = remaining&-remaining, best = 0;
                        for (int sub = remaining; sub > 0; sub = (sub-1)&remaining) {
                            if ((sub&first) != 0 && sums[sub] == 0 && 1+dp[remaining^sub] == dp[remaining] &&
                                (best == 0 || LexLess(Indexes(sub,n),Indexes(best,n)))) best = sub;
                        }
                        groups.Add(best);
                        remaining ^= best;
                    }
                    List<List<Transfer>> transfers = new();
                    foreach (int group in groups) {
                        SortedDictionary<string,long> amounts = new(StringComparer.Ordinal);
                        foreach (int i in Indexes(group,n)) amounts[names[i]] = all[names[i]];
                        transfers.Add(Greedy(amounts));
                    }
                    output.Add("SIMPLIFY OPTIMAL transfers "+transfers.Sum(group => group.Count)+" groups "+groups.Count);
                    for (int i = 0; i < groups.Count; i++) {
                        List<string> groupNames = Indexes(groups[i],n).Select(index => names[index]).ToList();
                        output.Add("  group "+string.Join(" ",groupNames));
                        foreach (Transfer x in transfers[i]) output.Add("    "+x.From+" -> "+x.To+" "+Fmt(x.Amount));
                    }
                }
                break;
            }
        }
        if (new HashSet<string> { "BALANCES","OWES","HISTORY","CATEGORY","BUDGETS","MEMBERS","PERIODS" }.Contains(command) && output.Count == 1) {
            output.Add("  (none)");
        }
        return output;
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var app = new Program();
        int count = int.Parse(Console.ReadLine()!,CultureInfo.InvariantCulture);
        for (int i = 0; i < count; i++) {
            try {
                foreach (string line in app.Execute(Console.ReadLine()!)) Console.WriteLine(line);
            } catch (Problem problem) {
                Console.WriteLine("ERROR "+problem.Message);
            }
        }
    }
}
