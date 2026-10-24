import java.io.*;
import java.util.*;
import java.util.stream.IntStream;

public class Main {
    record Amount(long value, String currency) {}
    record Member(boolean active, long day) {}
    record Part(String name, long value) {}
    record Settlement(long day, long record, String from, String to, Amount amount, long total) {}
    record Entry(long day, long record, String label, long change) {}
    record Transfer(String from, String to, long amount) {}
    static class Expense {
        String id, category, mode;
        Amount amount;
        List<Part> payers, participants;
        long[] contributions, shares;
        long day, record, total, interval, next, copies;
    }
    static class Problem extends RuntimeException {
        Problem(String message) { super(message); }
    }
    final TreeMap<String,Member> members = new TreeMap<>();
    final TreeMap<String,Long> currencies = new TreeMap<>(), budgets = new TreeMap<>();
    final Map<String,Expense> expenses = new LinkedHashMap<>();
    final Set<String> used = new HashSet<>();
    final List<Settlement> settlements = new ArrayList<>();
    long day = 1, serial = 0;
    static void fail(String message) { throw new Problem(message); }
    static long money(String s) { return Long.parseLong(s.replace(".","")); }
    static Amount amount(String s) {
        String[] parts = s.split("@");
        return new Amount(money(parts[0]),parts.length == 2 ? parts[1] : "");
    }
    static String fmt(long n) { return String.format(Locale.ROOT,"%d.%02d",n/100,n%100); }
    static String signed(long n) { return n > 0 ? "+"+fmt(n) : n < 0 ? "-"+fmt(-n) : "0.00"; }
    static String rate(long n) { return String.format(Locale.ROOT,"%d.%04d",n/10000,n%10000); }
    static String percent(long p, long w) { return fmt(p*10000/w)+"%"; }
    static String note(Amount a) { return a.currency().isEmpty() ? "" : " ["+fmt(a.value())+" "+a.currency()+"]"; }
    void registered(String name) {
        if (!members.containsKey(name)) fail("unknown member "+name);
    }
    void active(String name) {
        registered(name);
        if (!members.get(name).active()) fail("inactive member "+name);
    }
    long convert(Amount a) {
        if (a.currency().isEmpty()) return a.value();
        if (!currencies.containsKey(a.currency())) fail("unknown currency "+a.currency());
        return (a.value()*currencies.get(a.currency())+5000)/10000;
    }
    Expense expense(String id) {
        Expense e = expenses.get(id);
        if (e == null) fail("unknown expense "+id);
        return e;
    }
    void thawed(Expense e) {
        for (Part p : e.payers) {
            if (!members.get(p.name()).active()) fail("inactive member "+p.name());
        }
        for (Part p : e.participants) {
            if (!members.get(p.name()).active()) fail("inactive member "+p.name());
        }
    }
    static long[] distribute(long total, List<Long> weights) {
        long sum = weights.stream().mapToLong(Long::longValue).sum();
        long[] result = new long[weights.size()], remainders = new long[weights.size()];
        List<Integer> order = new ArrayList<>();
        long allocated = 0;
        for (int i = 0; i < weights.size(); i++) {
            result[i] = total*weights.get(i)/sum;
            remainders[i] = total*weights.get(i)%sum;
            allocated += result[i];
            order.add(i);
        }
        order.sort(Comparator.<Integer>comparingLong(i -> remainders[i]).reversed().thenComparingInt(i -> i));
        for (int i = 0; i < total-allocated; i++) result[order.get(i)]++;
        return result;
    }
    static List<Long> weights(List<Part> parts) { return parts.stream().map(Part::value).toList(); }
    void compute(Expense e) {
        long a = e.amount.value();
        e.total = convert(e.amount);
        long sum = e.participants.stream().mapToLong(Part::value).sum();
        long[] portions = new long[e.participants.size()];
        if (e.mode.equals("EXACT")) {
            if (sum != a) fail("splits do not add up");
            portions = e.participants.stream().mapToLong(Part::value).toArray();
        } else if (e.mode.equals("PERCENT") || e.mode.equals("SHARES")) {
            if (e.mode.equals("PERCENT") && sum != 10000 || e.mode.equals("SHARES") && sum == 0) fail("splits do not add up");
            portions = distribute(a,weights(e.participants));
        } else {
            long extras = e.mode.equals("ADJUST") ? sum : 0;
            if (extras > a) fail("splits do not add up");
            int k = portions.length;
            for (int i = 0; i < k; i++) {
                portions[i] = (a-extras)/k+(i < (a-extras)%k ? 1 : 0)+(e.mode.equals("ADJUST") ? e.participants.get(i).value() : 0);
            }
        }
        e.shares = distribute(e.total,Arrays.stream(portions).boxed().toList());
        e.contributions = distribute(e.total,weights(e.payers));
    }
    Expense build(String[] tokens) {
        active(tokens[2]);
        Expense e = new Expense();
        e.amount = amount(tokens[3]);
        long total = convert(e.amount);
        if (e.amount.value() == 0 || total == 0) fail("invalid amount");
        e.category = tokens[4];
        e.mode = tokens[5];
        e.payers = List.of(new Part(tokens[2],e.amount.value()));
        e.participants = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        if (e.mode.equals("EQUAL") && tokens[6].equals("ALL")) {
            for (var member : members.entrySet()) {
                if (member.getValue().active()) e.participants.add(new Part(member.getKey(),0));
            }
        } else {
            for (int i = 6; i < tokens.length; i++) {
                String[] part = tokens[i].split(":");
                active(part[0]);
                if (!seen.add(part[0])) fail("duplicate member "+part[0]);
                long value = part.length == 1 ? 0 : e.mode.equals("EXACT") || e.mode.equals("ADJUST") ? money(part[1]) : Long.parseLong(part[1]);
                e.participants.add(new Part(part[0],value));
            }
        }
        compute(e);
        return e;
    }
    List<Expense> chronological() {
        return expenses.values().stream().sorted(Comparator.comparingLong((Expense e) -> e.day).thenComparingLong(e -> e.record)).toList();
    }
    static boolean includes(Expense e, String name) {
        return e.payers.stream().anyMatch(p -> p.name().equals(name)) || e.participants.stream().anyMatch(p -> p.name().equals(name));
    }
    TreeMap<String,Long> net(Expense e) {
        TreeMap<String,Long> result = new TreeMap<>();
        for (int i = 0; i < e.payers.size(); i++) result.merge(e.payers.get(i).name(),e.contributions[i],Long::sum);
        for (int i = 0; i < e.participants.size(); i++) result.merge(e.participants.get(i).name(),-e.shares[i],Long::sum);
        return result;
    }
    TreeMap<String,Long> balances() {
        TreeMap<String,Long> result = new TreeMap<>();
        for (String name : members.keySet()) result.put(name,0L);
        for (Expense e : expenses.values()) net(e).forEach((name,value) -> result.merge(name,value,Long::sum));
        for (Settlement s : settlements) {
            result.merge(s.from(),s.total(),Long::sum);
            result.merge(s.to(),-s.total(),Long::sum);
        }
        return result;
    }
    List<String> activeNames() { return members.entrySet().stream().filter(p -> p.getValue().active()).map(Map.Entry::getKey).toList(); }
    TreeMap<String,Long> categoryTotals() {
        TreeMap<String,Long> result = new TreeMap<>();
        for (Expense e : expenses.values()) result.merge(e.category,e.total,Long::sum);
        return result;
    }
    void warning(Expense e, List<String> output) {
        Long budget = budgets.get(e.category);
        long spent = categoryTotals().getOrDefault(e.category,0L);
        if (budget != null && spent > budget) output.add("  WARNING "+e.category+" over budget by "+fmt(spent-budget));
    }
    static String pairs(List<Part> people, long[] values) {
        return String.join(" + ",IntStream.range(0,people.size()).mapToObj(i -> people.get(i).name()+" "+fmt(values[i])).toList());
    }
    static List<Transfer> greedy(Map<String,Long> balances) {
        TreeMap<String,Long> work = new TreeMap<>(balances);
        List<Transfer> result = new ArrayList<>();
        while (!work.isEmpty()) {
            var sender = Collections.min(work.entrySet(),Map.Entry.comparingByValue());
            var receiver = Collections.max(work.entrySet(),Map.Entry.comparingByValue());
            long minimum = sender.getValue(), maximum = receiver.getValue();
            if (minimum >= 0) break;
            String from = sender.getKey(), to = receiver.getKey();
            long value = Math.min(-minimum,maximum);
            result.add(new Transfer(from,to,value));
            work.put(from,minimum+value);
            work.put(to,maximum-value);
        }
        return result;
    }
    long[][] debts(List<String> names) {
        int n = names.size();
        Map<String,Integer> index = new HashMap<>();
        for (int i = 0; i < n; i++) index.put(names.get(i),i);
        long[][] result = new long[n][n];
        for (Expense e : expenses.values()) {
            TreeMap<String,Long> amounts = net(e);
            List<String> borrowers = amounts.entrySet().stream().filter(p -> p.getValue() < 0).map(Map.Entry::getKey).toList();
            List<String> lenders = amounts.entrySet().stream().filter(p -> p.getValue() > 0).map(Map.Entry::getKey).toList();
            int a = 0, b = 0;
            while (a < borrowers.size() && b < lenders.size()) {
                String x = borrowers.get(a), y = lenders.get(b);
                long value = Math.min(-amounts.get(x),amounts.get(y));
                int i = index.get(x), j = index.get(y);
                result[i][j] += value;
                result[j][i] -= value;
                amounts.put(x,amounts.get(x)+value);
                amounts.put(y,amounts.get(y)-value);
                if (amounts.get(x) == 0) a++;
                if (amounts.get(y) == 0) b++;
            }
        }
        for (Settlement s : settlements) {
            int i = index.get(s.from()), j = index.get(s.to());
            result[i][j] -= s.total();
            result[j][i] += s.total();
        }
        return result;
    }
    static int[] indexes(int mask, int n) {
        return IntStream.range(0,n).filter(i -> (mask&(1<<i)) != 0).toArray();
    }
    List<String> execute(String line) {
        String[] t = line.split(" ");
        String command = t[0];
        List<String> out = new ArrayList<>();
        switch (command) {
            case "DAY": {
                long d = Long.parseLong(t[1]);
                if (d <= day) fail("invalid day "+t[1]);
                out.add("DAY "+d);
                while (true) {
                    Expense template = expenses.values().stream().filter(e -> e.interval > 0 && e.next <= d)
                        .min(Comparator.comparingLong((Expense e) -> e.next).thenComparingLong(e -> e.record)).orElse(null);
                    if (template == null) break;
                    boolean active = template.payers.stream().allMatch(p -> members.get(p.name()).active()) &&
                        template.participants.stream().allMatch(p -> members.get(p.name()).active());
                    if (!active || convert(template.amount) == 0) {
                        template.interval = 0;
                        out.add("  CANCEL "+template.id);
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
                        compute(copy);
                        expenses.put(copy.id,copy);
                        used.add(copy.id);
                        template.copies++;
                        template.next += template.interval;
                        out.add("  RECUR "+copy.id+" "+fmt(copy.total));
                        warning(copy,out);
                    }
                }
                day = d;
                break;
            }
            case "MEMBER": {
                Member old = members.get(t[1]);
                if (old != null && old.active()) fail("duplicate member "+t[1]);
                members.put(t[1],new Member(true,day));
                out.add("MEMBER "+t[1]+(old == null ? " joined" : " rejoined"));
                break;
            }
            case "LEAVE": {
                active(t[1]);
                if (balances().get(t[1]) != 0) fail("member has a balance "+t[1]);
                members.put(t[1],new Member(false,day));
                out.add("LEAVE "+t[1]);
                break;
            }
            case "CURRENCY": {
                long value = Long.parseLong(t[2]);
                Long old = currencies.put(t[1],value);
                out.add("CURRENCY "+t[1]+" "+rate(value)+(old == null ? "" : " was "+rate(old)));
                break;
            }
            case "EXPENSE", "EDIT": {
                Expense old = null;
                if (command.equals("EXPENSE")) {
                    if (used.contains(t[1])) fail("duplicate id "+t[1]);
                } else {
                    old = expense(t[1]);
                    thawed(old);
                }
                Expense e = build(t);
                e.id = t[1];
                e.day = old == null ? day : old.day;
                e.record = old == null ? ++serial : old.record;
                if (old != null) {
                    e.interval = old.interval;
                    e.next = old.next;
                    e.copies = old.copies;
                }
                expenses.put(e.id,e);
                used.add(e.id);
                out.add(command+" "+e.id+" "+fmt(e.total)+note(e.amount)+" = "+pairs(e.participants,e.shares));
                warning(e,out);
                break;
            }
            case "PAYERS": {
                Expense e = expense(t[1]);
                thawed(e);
                List<Part> payers = new ArrayList<>();
                Set<String> seen = new HashSet<>();
                long total = 0;
                for (int i = 2; i < t.length; i++) {
                    String[] p = t[i].split(":");
                    active(p[0]);
                    if (!seen.add(p[0])) fail("duplicate member "+p[0]);
                    long value = money(p[1]);
                    payers.add(new Part(p[0],value));
                    total += value;
                }
                if (total != e.amount.value()) fail("payers do not add up");
                long[] contributions = distribute(e.total,weights(payers));
                e.payers = payers;
                e.contributions = contributions;
                out.add("PAYERS "+e.id+" "+fmt(e.total)+note(e.amount)+" = "+pairs(payers,contributions));
                break;
            }
            case "DELETE": {
                Expense e = expense(t[1]);
                thawed(e);
                expenses.remove(e.id);
                out.add("DELETE "+e.id);
                break;
            }
            case "RECURRING": {
                Expense e = expense(t[1]);
                e.interval = Long.parseLong(t[2]);
                e.next = day+e.interval;
                out.add("RECURRING "+e.id+(e.interval == 0 ? " stopped" : " interval "+e.interval+" next "+e.next));
                break;
            }
            case "SETTLE": {
                active(t[1]);
                active(t[2]);
                if (t[1].equals(t[2])) fail("same member "+t[1]);
                Amount a = amount(t[3]);
                long total = convert(a);
                if (a.value() == 0 || total == 0) fail("invalid amount");
                settlements.add(new Settlement(day,++serial,t[1],t[2],a,total));
                out.add("SETTLE "+t[1]+" -> "+t[2]+" "+fmt(total)+note(a));
                break;
            }
            case "BUDGET": {
                long value = money(t[2]);
                if (value == 0) budgets.remove(t[1]);
                else budgets.put(t[1],value);
                out.add("BUDGET "+t[1]+(value == 0 ? " removed" : " "+fmt(value)));
                break;
            }
            case "BALANCES": {
                out.add("BALANCES");
                Map<String,Long> balances = balances();
                for (String name : activeNames()) out.add("  "+name+" "+signed(balances.get(name)));
                break;
            }
            case "OWES", "MATRIX": {
                if (command.equals("OWES")) registered(t[1]);
                List<String> names = new ArrayList<>(members.keySet());
                long[][] debt = debts(names);
                out.add(command.equals("OWES") ? "OWES "+t[1] : "MATRIX");
                if (command.equals("OWES")) {
                    int i = names.indexOf(t[1]);
                    for (int j = 0; j < names.size(); j++) {
                        if (debt[i][j] > 0) out.add("  "+t[1]+" owes "+names.get(j)+" "+fmt(debt[i][j]));
                        if (debt[i][j] < 0) out.add("  "+names.get(j)+" owes "+t[1]+" "+fmt(-debt[i][j]));
                    }
                } else {
                    List<String> active = activeNames();
                    if (active.isEmpty()) out.add("  (none)");
                    else {
                        int l = active.stream().mapToInt(String::length).max().orElse(0), width = l;
                        for (String a : active) {
                            for (String b : active) width = Math.max(width,a.equals(b) ? 1 : fmt(Math.max(0,debt[names.indexOf(a)][names.indexOf(b)])).length());
                        }
                        StringBuilder header = new StringBuilder(" ".repeat(l));
                        for (String name : active) header.append("  ").append(" ".repeat(width-name.length())).append(name);
                        out.add(header.toString());
                        for (String a : active) {
                            StringBuilder row = new StringBuilder(a+" ".repeat(l-a.length()));
                            for (String b : active) {
                                String cell = a.equals(b) ? "-" : fmt(Math.max(0,debt[names.indexOf(a)][names.indexOf(b)]));
                                row.append("  ").append(" ".repeat(width-cell.length())).append(cell);
                            }
                            out.add(row.toString());
                        }
                    }
                }
                break;
            }
            case "HISTORY": {
                registered(t[1]);
                List<Entry> entries = new ArrayList<>();
                for (Expense e : expenses.values()) {
                    if (includes(e,t[1])) entries.add(new Entry(e.day,e.record,e.id,net(e).get(t[1])));
                }
                for (Settlement s : settlements) {
                    if (s.from().equals(t[1]) || s.to().equals(t[1])) entries.add(new Entry(s.day(),s.record(),s.from()+"->"+s.to(),s.from().equals(t[1]) ? s.total() : -s.total()));
                }
                entries.sort(Comparator.comparingLong(Entry::day).thenComparingLong(Entry::record));
                out.add("HISTORY "+t[1]);
                long balance = 0;
                for (Entry e : entries) {
                    balance += e.change();
                    out.add("  day "+e.day()+" "+e.label()+" "+signed(e.change())+" balance "+signed(balance));
                }
                break;
            }
            case "CATEGORY": {
                out.add("CATEGORY");
                Map<String,Long> totals = categoryTotals();
                long all = totals.values().stream().mapToLong(Long::longValue).sum();
                List<String> categories = totals.keySet().stream().sorted(Comparator.<String>comparingLong(totals::get).reversed().thenComparing(s -> s)).toList();
                for (String category : categories) {
                    long total = totals.get(category);
                    out.add("  "+category+" "+fmt(total)+" "+percent(total,all));
                    TreeMap<String,Long> shares = new TreeMap<>();
                    for (Expense e : expenses.values()) {
                        if (e.category.equals(category)) {
                            for (int i = 0; i < e.participants.size(); i++) shares.merge(e.participants.get(i).name(),e.shares[i],Long::sum);
                        }
                    }
                    for (String name : shares.keySet().stream().filter(name -> shares.get(name) != 0).sorted(Comparator.<String>comparingLong(shares::get).reversed().thenComparing(s -> s)).toList()) {
                        out.add("    "+name+" "+fmt(shares.get(name))+" "+percent(shares.get(name),total));
                    }
                }
                break;
            }
            case "BUDGETS": {
                out.add("BUDGETS");
                Map<String,Long> totals = categoryTotals();
                for (var budget : budgets.entrySet()) {
                    long spent = totals.getOrDefault(budget.getKey(),0L), b = budget.getValue();
                    out.add("  "+budget.getKey()+" spent "+fmt(spent)+" budget "+fmt(b)+" used "+percent(spent,b)+
                        (spent <= b ? " left "+fmt(b-spent) : " over "+fmt(spent-b)));
                }
                break;
            }
            case "TOTALS": {
                out.add("TOTALS");
                for (String name : members.keySet()) {
                    long paid = 0, share = 0, sent = 0, received = 0;
                    for (Expense e : expenses.values()) {
                        for (int i = 0; i < e.payers.size(); i++) {
                            if (e.payers.get(i).name().equals(name)) paid += e.contributions[i];
                        }
                        for (int i = 0; i < e.participants.size(); i++) {
                            if (e.participants.get(i).name().equals(name)) share += e.shares[i];
                        }
                    }
                    sent = settlements.stream().filter(s -> s.from().equals(name)).mapToLong(Settlement::total).sum();
                    received = settlements.stream().filter(s -> s.to().equals(name)).mapToLong(Settlement::total).sum();
                    out.add("  "+name+" paid "+fmt(paid)+" share "+fmt(share)+" sent "+fmt(sent)+" received "+fmt(received));
                }
                for (String currency : currencies.keySet()) {
                    List<Expense> group = expenses.values().stream().filter(e -> e.amount.currency().equals(currency)).toList();
                    if (!group.isEmpty()) out.add("  currency "+currency+" expenses "+group.size()+" amount "+fmt(group.stream().mapToLong(e -> e.amount.value()).sum())+" base "+fmt(group.stream().mapToLong(e -> e.total).sum()));
                }
                out.add("  expenses "+expenses.size()+" total "+fmt(expenses.values().stream().mapToLong(e -> e.total).sum())+
                    " settlements "+settlements.size()+" total "+fmt(settlements.stream().mapToLong(Settlement::total).sum()));
                break;
            }
            case "MEMBERS": {
                out.add("MEMBERS");
                for (var m : members.entrySet()) {
                    long count = expenses.values().stream().filter(e -> includes(e,m.getKey())).count();
                    out.add("  "+m.getKey()+(m.getValue().active() ? " active" : " left")+" day "+m.getValue().day()+" expenses "+count);
                }
                break;
            }
            case "EXPENSES": {
                if (t[1].equals("MEMBER")) registered(t[2]);
                out.add(line);
                long count = 0, total = 0;
                for (Expense e : chronological()) {
                    boolean matches = switch (t[1]) {
                        case "CATEGORY" -> e.category.equals(t[2]);
                        case "MEMBER" -> includes(e,t[2]);
                        case "DAYS" -> e.day >= Long.parseLong(t[2]) && e.day <= Long.parseLong(t[3]);
                        default -> true;
                    };
                    if (matches) {
                        out.add("  day "+e.day+" "+e.id+" "+e.category+" "+fmt(e.total)+" by "+String.join(",",e.payers.stream().map(Part::name).toList()));
                        count++;
                        total += e.total;
                    }
                }
                out.add("  count "+count+" total "+fmt(total));
                break;
            }
            case "PERIODS": {
                long k = Long.parseLong(t[1]);
                out.add("PERIODS "+k);
                TreeMap<Long,List<Expense>> groups = new TreeMap<>();
                for (Expense e : expenses.values()) groups.computeIfAbsent((e.day-1)/k,key -> new ArrayList<>()).add(e);
                for (var group : groups.entrySet()) {
                    long i = group.getKey();
                    out.add("  days "+(i*k+1)+"-"+(i*k+k)+" expenses "+group.getValue().size()+" total "+fmt(group.getValue().stream().mapToLong(e -> e.total).sum()));
                }
                break;
            }
            case "SHOW": {
                Expense e = expense(t[1]);
                out.add("SHOW "+e.id);
                out.add("  day "+e.day+" category "+e.category+" mode "+e.mode+" total "+fmt(e.total)+note(e.amount));
                for (int i = 0; i < e.payers.size(); i++) out.add("  paid "+e.payers.get(i).name()+" "+fmt(e.contributions[i]));
                long sum = e.participants.stream().mapToLong(Part::value).sum();
                for (int i = 0; i < e.participants.size(); i++) {
                    Part p = e.participants.get(i);
                    String suffix = switch (e.mode) {
                        case "EXACT" -> " "+fmt(p.value());
                        case "PERCENT" -> " "+fmt(p.value())+"%";
                        case "SHARES" -> " "+p.value()+"/"+sum;
                        case "ADJUST" -> " +"+fmt(p.value());
                        default -> "";
                    };
                    out.add("  share "+p.name()+" "+fmt(e.shares[i])+suffix);
                }
                if (e.interval > 0) out.add("  recurring interval "+e.interval+" next "+e.next);
                break;
            }
            case "SIMPLIFY": {
                TreeMap<String,Long> all = balances();
                all.entrySet().removeIf(p -> p.getValue() == 0);
                if (t[1].equals("GREEDY")) {
                    List<Transfer> transfers = greedy(all);
                    out.add("SIMPLIFY GREEDY transfers "+transfers.size());
                    for (Transfer x : transfers) out.add("  "+x.from()+" -> "+x.to()+" "+fmt(x.amount()));
                } else {
                    List<String> names = new ArrayList<>(all.keySet());
                    int n = names.size();
                    if (n > 12) fail("too many members");
                    int size = 1<<n;
                    long[] sums = new long[size];
                    int[] dp = new int[size];
                    Arrays.fill(dp,-1000);
                    dp[0] = 0;
                    for (int mask = 1; mask < size; mask++) {
                        int bit = Integer.numberOfTrailingZeros(mask);
                        sums[mask] = sums[mask^(1<<bit)]+all.get(names.get(bit));
                        int first = mask&-mask;
                        for (int sub = mask; sub > 0; sub = (sub-1)&mask) {
                            if ((sub&first) != 0 && sums[sub] == 0) dp[mask] = Math.max(dp[mask],1+dp[mask^sub]);
                        }
                    }
                    int remaining = size-1;
                    List<Integer> groups = new ArrayList<>();
                    while (remaining != 0) {
                        int first = remaining&-remaining, best = 0;
                        for (int sub = remaining; sub > 0; sub = (sub-1)&remaining) {
                            if ((sub&first) != 0 && sums[sub] == 0 && 1+dp[remaining^sub] == dp[remaining] &&
                                (best == 0 || Arrays.compare(indexes(sub,n),indexes(best,n)) < 0)) best = sub;
                        }
                        groups.add(best);
                        remaining ^= best;
                    }
                    List<List<Transfer>> transfers = new ArrayList<>();
                    for (int group : groups) {
                        TreeMap<String,Long> amounts = new TreeMap<>();
                        for (int i : indexes(group,n)) amounts.put(names.get(i),all.get(names.get(i)));
                        transfers.add(greedy(amounts));
                    }
                    out.add("SIMPLIFY OPTIMAL transfers "+transfers.stream().mapToInt(List::size).sum()+" groups "+groups.size());
                    for (int i = 0; i < groups.size(); i++) {
                        List<String> groupNames = Arrays.stream(indexes(groups.get(i),n)).mapToObj(names::get).toList();
                        out.add("  group "+String.join(" ",groupNames));
                        for (Transfer x : transfers.get(i)) out.add("    "+x.from()+" -> "+x.to()+" "+fmt(x.amount()));
                    }
                }
                break;
            }
        }
        if (Set.of("BALANCES","OWES","HISTORY","CATEGORY","BUDGETS","MEMBERS","PERIODS").contains(command) && out.size() == 1) {
            out.add("  (none)");
        }
        return out;
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        Main app = new Main();
        int count = Integer.parseInt(input.readLine());
        for (int i = 0; i < count; i++) {
            try {
                app.execute(input.readLine()).forEach(output::println);
            } catch (Problem problem) {
                output.println("ERROR "+problem.getMessage());
            }
        }
        output.flush();
    }
}
