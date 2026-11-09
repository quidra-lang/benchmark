import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class Main {
    static final int LAST_DAY = 36524;

    static class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    enum AccountType {
        ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE, CONTRA_ASSET;

        AccountType typeClass() { return this == CONTRA_ASSET ? ASSET : this; }
        int sign() { return this == ASSET || this == EXPENSE ? 1 : -1; }
        boolean temporary() { return this == REVENUE || this == EXPENSE; }
    }

    enum Category {
        JOURNAL, RECURRING, REVERSAL, CLOSING, REOPEN, DEPRECIATION, INTEREST, WRITEOFF;

        String text() { return name().toLowerCase(Locale.ROOT); }
    }

    static long parseMoney(String text) {
        int dot = text.indexOf('.');
        return Long.parseLong(text.substring(0, dot)) * 100 + Long.parseLong(text.substring(dot + 1));
    }

    static String money(long value) {
        long magnitude = Math.abs(value);
        return (value < 0 ? "-" : "") + magnitude / 100 + String.format(Locale.ROOT, ".%02d", magnitude % 100);
    }

    static boolean leap(int year) { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0); }
    static int yearLength(int year) { return leap(year) ? 366 : 365; }

    static int monthLength(int year, int month) {
        int[] lengths = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
        return month == 2 && leap(year) ? 29 : lengths[month - 1];
    }

    static int dayNumber(int year, int month, int day) {
        int number = day - 1;
        for (int y = 2000; y < year; y++) number += yearLength(y);
        for (int m = 1; m < month; m++) number += monthLength(year, m);
        return number;
    }

    record CalendarDate(int year, int month, int day) {}
    record DayRange(int first, int last) {}

    static CalendarDate calendar(int number) {
        int year = 2000, month = 1;
        while (number >= yearLength(year)) { number -= yearLength(year); year++; }
        while (number >= monthLength(year, month)) { number -= monthLength(year, month); month++; }
        return new CalendarDate(year, month, number + 1);
    }

    static String dateText(int number) {
        CalendarDate date = calendar(number);
        return String.format(Locale.ROOT, "%04d-%02d-%02d", date.year, date.month, date.day);
    }

    static int parseDate(String text) {
        int year = Integer.parseInt(text.substring(0, 4));
        int month = Integer.parseInt(text.substring(5, 7)), day = Integer.parseInt(text.substring(8));
        if (year < 2000 || year > 2099 || month < 1 || month > 12 || day < 1 || day > monthLength(year, month)) {
            throw new CommandError("invalid date " + text);
        }
        return dayNumber(year, month, day);
    }

    static DayRange dateRange(String first, String last) {
        int start = parseDate(first), end = parseDate(last);
        if (start > end) throw new CommandError("invalid range " + first + " " + last);
        return new DayRange(start, end);
    }

    static int monthsAfter(int number, int offset) {
        CalendarDate date = calendar(number);
        int total = date.month - 1 + offset;
        int year = date.year + total / 12, month = total % 12 + 1;
        return dayNumber(year, month, Math.min(date.day, monthLength(year, month)));
    }

    static class Account {
        final String code, name;
        final AccountType type;
        boolean active = true;

        Account(String code, AccountType type, String name) {
            this.code = code;
            this.type = type;
            this.name = name;
        }
    }

    record Totals(long debit, long credit) {
        static final Totals ZERO = new Totals(0, 0);
        long difference() { return debit - credit; }
        Totals plus(Totals other) { return new Totals(debit + other.debit, credit + other.credit); }
        Totals add(boolean isDebit, long amount) {
            return isDebit ? new Totals(debit + amount, credit) : new Totals(debit, credit + amount);
        }
    }

    record Line(boolean debit, Account account, long amount, String partner) {
        Line(boolean debit, Account account, long amount) { this(debit, account, amount, null); }
        long difference() { return debit ? amount : -amount; }
        String side() { return debit ? "DR" : "CR"; }
    }

    static class Lines {
        final List<Line> items;
        final Map<Account, Totals> accounts;
        final long amount;

        Lines(List<Line> items) {
            this.items = List.copyOf(items);
            Map<Account, Totals> totals = new HashMap<>();
            long debit = 0;
            for (Line line : items) {
                totals.put(line.account, totals.getOrDefault(line.account, Totals.ZERO).add(line.debit, line.amount));
                if (line.debit) debit += line.amount;
            }
            accounts = Map.copyOf(totals);
            amount = debit;
        }

        Totals totals(Account account) { return accounts.getOrDefault(account, Totals.ZERO); }
    }

    record DraftLine(boolean debit, String code, long amount, String partner) {}

    static class Draft {
        final boolean journal;
        final String key, date, memo;
        final List<DraftLine> lines = new ArrayList<>();

        Draft(boolean journal, String key, String date, String memo) {
            this.journal = journal;
            this.key = key;
            this.date = date;
            this.memo = memo;
        }

        Totals totals() {
            Totals totals = Totals.ZERO;
            for (DraftLine line : lines) totals = totals.add(line.debit, line.amount);
            return totals;
        }
    }

    static class Entry {
        final String id, memo;
        final int day, sequence;
        final Category category;
        final Lines lines;
        Entry reverses, reversedBy;

        Entry(String id, int day, Category category, String memo, Lines lines, int sequence) {
            this.id = id;
            this.day = day;
            this.category = category;
            this.memo = memo;
            this.lines = lines;
            this.sequence = sequence;
        }
    }

    static class Template {
        final String memo;
        final Lines lines;
        int uses;

        Template(String memo, Lines lines) { this.memo = memo; this.lines = lines; }
    }

    record CloseRecord(int day, Entry entry) {}

    static class OpenItem {
        final Entry entry;
        final long original;
        long remaining;

        OpenItem(Entry entry, long original, long remaining) {
            this.entry = entry;
            this.original = original;
            this.remaining = remaining;
        }
    }

    static class Settlement {
        final Deque<OpenItem> items = new ArrayDeque<>();
        long unapplied;
    }

    record Displayed(Account account, long amount) {}

    static class Book {
        final TreeMap<String, Account> accounts = new TreeMap<>();
        final List<Entry> entries = new ArrayList<>();
        final Map<String, Entry> entryIds = new HashMap<>();
        final TreeMap<String, Template> templates = new TreeMap<>();
        final Deque<CloseRecord> closes = new ArrayDeque<>();
        final PrintWriter output;
        Draft draft;
        int closeCount, depreciationCount, interestCount, writeoffCount;

        Book(PrintWriter output) { this.output = output; }
        void emit(String format, Object... arguments) { output.printf(Locale.ROOT, format + "\n", arguments); }

        Account account(String code) {
            Account account = accounts.get(code);
            if (account == null) throw new CommandError("unknown account " + code);
            return account;
        }

        Account requireType(String code, AccountType type) {
            Account account = account(code);
            if (account.type != type) throw new CommandError("wrong type " + code + " " + type);
            return account;
        }

        void active(Account... selected) {
            for (Account account : selected) if (!account.active) throw new CommandError("inactive account " + account.code);
        }

        void activeLines(Lines lines) {
            for (Line line : lines.items) active(line.account);
        }

        void checkOpen(int day) {
            if (!closes.isEmpty() && day <= closes.getLast().day) throw new CommandError("period closed " + dateText(day));
        }

        String closedText() { return closes.isEmpty() ? "none" : dateText(closes.getLast().day); }

        String parent(String code) {
            for (int length = code.length() - 1; length > 0; length--) {
                String prefix = code.substring(0, length);
                if (accounts.containsKey(prefix)) return prefix;
            }
            return "none";
        }

        String top(String code) {
            for (int length = 1; length < code.length(); length++) {
                String prefix = code.substring(0, length);
                if (accounts.containsKey(prefix)) return prefix;
            }
            return code;
        }

        List<Entry> ordered() {
            List<Entry> ordered = new ArrayList<>(entries);
            ordered.sort(Comparator.comparingInt((Entry entry) -> entry.day).thenComparingInt(entry -> entry.sequence));
            return ordered;
        }

        Map<Account, Totals> totals(int first, int last, boolean operating) {
            Map<Account, Totals> totals = new HashMap<>();
            for (Entry entry : entries) {
                if (entry.day < first || entry.day > last || operating && (entry.category == Category.CLOSING || entry.category == Category.REOPEN)) continue;
                for (var item : entry.lines.accounts.entrySet()) totals.merge(item.getKey(), item.getValue(), Totals::plus);
            }
            return totals;
        }

        Totals accountTotals(Account account, int first, int last) {
            Totals totals = Totals.ZERO;
            for (Entry entry : entries) if (first <= entry.day && entry.day <= last) totals = totals.plus(entry.lines.totals(account));
            return totals;
        }

        long balance(Account account, int day) { return account.type.sign() * accountTotals(account, 0, day).difference(); }

        long dailySum(Account account, int first, int last) {
            long[] changes = new long[last - first + 1];
            long running = 0, sum = 0;
            for (Entry entry : entries) {
                if (entry.day > last) continue;
                long value = account.type.sign() * entry.lines.totals(account).difference();
                if (entry.day < first) running += value;
                else changes[entry.day - first] += value;
            }
            for (long change : changes) { running += change; sum += running; }
            return sum;
        }

        Entry post(String id, int day, Category category, String memo, Lines lines) {
            Entry entry = new Entry(id, day, category, memo, lines, entries.size() + 1);
            entries.add(entry);
            entryIds.put(id, entry);
            return entry;
        }

        Entry reverse(Entry original, int day, Category category, String memo) {
            List<Line> items = new ArrayList<>();
            for (Line line : original.lines.items) items.add(new Line(!line.debit, line.account, line.amount, line.partner));
            Entry entry = post(original.id + "-R", day, category, memo, new Lines(items));
            original.reversedBy = entry;
            entry.reverses = original;
            return entry;
        }

        TreeMap<String, Settlement> settlements(Account account, int day) {
            TreeMap<String, Settlement> settlements = new TreeMap<>();
            for (Entry entry : ordered()) {
                if (entry.day > day) continue;
                for (Line line : entry.lines.items) {
                    if (line.account != account || line.partner == null) continue;
                    Settlement settled = settlements.computeIfAbsent(line.partner, ignored -> new Settlement());
                    long value = account.type.sign() * line.difference();
                    if (value > 0) {
                        long applied = Math.min(value, settled.unapplied);
                        settled.unapplied -= applied;
                        if (value > applied) settled.items.addLast(new OpenItem(entry, value, value - applied));
                    } else {
                        long payment = -value;
                        while (payment > 0 && !settled.items.isEmpty()) {
                            OpenItem item = settled.items.getFirst();
                            long applied = Math.min(payment, item.remaining);
                            payment -= applied;
                            item.remaining -= applied;
                            if (item.remaining == 0) settled.items.removeFirst();
                        }
                        settled.unapplied += payment;
                    }
                }
            }
            return settlements;
        }

        void postDraft() {
            if (draft == null) throw new CommandError("no open entry");
            Draft block = draft;
            draft = null;
            int day = 0;
            if (block.journal) {
                if (entryIds.containsKey(block.key)) throw new CommandError("duplicate entry " + block.key);
                day = parseDate(block.date);
                checkOpen(day);
            } else if (templates.containsKey(block.key)) throw new CommandError("duplicate template " + block.key);
            if (block.lines.size() < 2) throw new CommandError("too few lines " + block.key);
            List<Line> items = new ArrayList<>();
            for (DraftLine line : block.lines) {
                Account account = account(line.code);
                if (block.journal) active(account);
                if (line.amount == 0) throw new CommandError("zero amount " + line.code);
                items.add(new Line(line.debit, account, line.amount, line.partner));
            }
            Totals totals = block.totals();
            if (totals.debit != totals.credit) throw new CommandError("unbalanced " + block.key + " debit " + money(totals.debit) + " credit " + money(totals.credit));
            Lines lines = new Lines(items);
            if (block.journal) {
                post(block.key, day, Category.JOURNAL, block.memo, lines);
                emit("POST %s %s lines %d amount %s", block.key, dateText(day), items.size(), money(lines.amount));
            } else {
                templates.put(block.key, new Template(block.memo, lines));
                emit("TEMPLATE %s lines %d amount %s", block.key, items.size(), money(lines.amount));
            }
        }

        long section(String heading, Set<AccountType> types, int sign, Map<Account, Totals> totals, Long earnings) {
            TreeMap<String, List<Displayed>> groups = new TreeMap<>();
            long total = earnings == null ? 0 : earnings;
            for (Account account : accounts.values()) {
                if (!types.contains(account.type)) continue;
                long value = sign * totals.getOrDefault(account, Totals.ZERO).difference();
                groups.computeIfAbsent(top(account.code), ignored -> new ArrayList<>()).add(new Displayed(account, value));
                total += value;
            }
            emit("  %s %s", heading, money(total));
            for (var group : groups.entrySet()) {
                long subtotal = 0;
                boolean nonzero = false;
                for (Displayed item : group.getValue()) { subtotal += item.amount; nonzero |= item.amount != 0; }
                if (!nonzero) continue;
                Account root = accounts.get(group.getKey());
                emit("    %s %s %s", root.code, root.name, money(subtotal));
                for (Displayed item : group.getValue()) {
                    if (item.amount != 0) emit("      %s %s %s", item.account.code, item.account.name, money(item.amount));
                }
            }
            if (earnings != null) emit("    current earnings %s", money(earnings));
            return total;
        }

        void agingRow(String partner, long[] values) {
            long balance = values[0] + values[1] + values[2] + values[3] - values[4];
            emit("  %s 0-30 %s 31-60 %s 61-90 %s 91+ %s unapplied %s balance %s", partner,
                 money(values[0]), money(values[1]), money(values[2]), money(values[3]), money(values[4]), money(balance));
        }

        void execute(String[] words) {
            switch (words[0]) {
                case "ACCOUNT" -> {
                    String code = words[1];
                    if (accounts.containsKey(code)) throw new CommandError("duplicate account " + code);
                    AccountType type = AccountType.valueOf(words[2]);
                    for (Account other : accounts.values()) {
                        if ((code.startsWith(other.code) || other.code.startsWith(code)) && type.typeClass() != other.type.typeClass()) {
                            throw new CommandError("class mismatch " + code + " " + other.code);
                        }
                    }
                    accounts.put(code, new Account(code, type, words[3]));
                    emit("ACCOUNT %s %s %s parent %s", code, type, words[3], parent(code));
                }
                case "DEACTIVATE" -> {
                    Account account = account(words[1]);
                    if (!account.active) throw new CommandError("already inactive " + account.code);
                    long value = balance(account, LAST_DAY);
                    if (value != 0) throw new CommandError("nonzero balance " + account.code + " " + money(value));
                    account.active = false;
                    emit("DEACTIVATE %s %s", account.code, account.name);
                }
                case "JOURNAL", "TEMPLATE" -> {
                    if (draft != null) emit("DISCARD %s lines %d", draft.key, draft.lines.size());
                    boolean journal = words[0].equals("JOURNAL");
                    draft = new Draft(journal, words[1], journal ? words[2] : null, words[journal ? 3 : 2]);
                }
                case "DR", "CR" -> {
                    if (draft == null) throw new CommandError("no open entry");
                    draft.lines.add(new DraftLine(words[0].equals("DR"), words[1], parseMoney(words[2]), words.length == 4 ? words[3] : null));
                }
                case "POST" -> postDraft();
                case "DRAFT" -> {
                    if (draft == null) throw new CommandError("no open entry");
                    Totals totals = draft.totals();
                    emit("DRAFT %s %s lines %d debit %s credit %s difference %s", draft.journal ? "journal" : "template", draft.key,
                         draft.lines.size(), money(totals.debit), money(totals.credit), money(totals.difference()));
                }
                case "REVERSE" -> {
                    Entry original = entryIds.get(words[1]);
                    if (original == null) throw new CommandError("unknown entry " + words[1]);
                    if (original.category == Category.REVERSAL || original.category == Category.CLOSING || original.category == Category.REOPEN) {
                        throw new CommandError("cannot reverse " + original.id);
                    }
                    if (original.reversedBy != null) throw new CommandError("already reversed " + original.id);
                    int day = parseDate(words[2]);
                    if (day < original.day) throw new CommandError("reverse before entry " + original.id + " " + dateText(original.day));
                    checkOpen(day);
                    activeLines(original.lines);
                    Entry entry = reverse(original, day, Category.REVERSAL, original.memo);
                    emit("REVERSE %s entry %s %s amount %s", original.id, entry.id, dateText(day), money(entry.lines.amount));
                }
                case "RECUR" -> {
                    Template model = templates.get(words[1]);
                    if (model == null) throw new CommandError("unknown template " + words[1]);
                    int day = parseDate(words[2]), count = Integer.parseInt(words[3]);
                    if (count == 0) throw new CommandError("invalid count");
                    checkOpen(day);
                    activeLines(model.lines);
                    emit("RECUR %s count %d", words[1], count);
                    for (int offset = 0; offset < count; offset++) {
                        Entry entry = post(words[1] + "-" + ++model.uses, monthsAfter(day, offset), Category.RECURRING, model.memo, model.lines);
                        emit("  POST %s %s lines %d amount %s", entry.id, dateText(entry.day), entry.lines.items.size(), money(entry.lines.amount));
                    }
                }
                case "DEPRECIATE" -> {
                    int day = parseDate(words[1]);
                    checkOpen(day);
                    Account asset = requireType(words[2], AccountType.ASSET);
                    Account contra = requireType(words[3], AccountType.CONTRA_ASSET);
                    Account expense = requireType(words[4], AccountType.EXPENSE);
                    active(contra, expense);
                    long cost = balance(asset, day), accumulated = balance(contra, day);
                    long amount = cost > 0 ? Math.min(cost / Integer.parseInt(words[5]), cost - accumulated) : 0;
                    if (amount <= 0) throw new CommandError("nothing to depreciate " + asset.code);
                    Lines lines = new Lines(List.of(new Line(true, expense, amount), new Line(false, contra, amount)));
                    Entry entry = post("DEP-" + ++depreciationCount, day, Category.DEPRECIATION, "depreciation", lines);
                    emit("DEPRECIATE %s entry %s %s amount %s accumulated %s book %s", asset.code, entry.id, dateText(day),
                         money(amount), money(accumulated + amount), money(cost - accumulated - amount));
                }
                case "INTEREST" -> {
                    Account account = account(words[1]);
                    if (account.type != AccountType.ASSET && account.type != AccountType.LIABILITY) throw new CommandError("not interest bearing " + account.code);
                    Account offset = requireType(words[2], account.type == AccountType.ASSET ? AccountType.REVENUE : AccountType.EXPENSE);
                    DayRange range = dateRange(words[3], words[4]);
                    checkOpen(range.last);
                    active(account, offset);
                    long sum = dailySum(account, range.first, range.last), amount = sum * Integer.parseInt(words[5]) / 3650000;
                    if (amount <= 0) throw new CommandError("no interest " + account.code);
                    boolean asset = account.type == AccountType.ASSET;
                    Lines lines = new Lines(List.of(new Line(true, asset ? account : offset, amount), new Line(false, asset ? offset : account, amount)));
                    Entry entry = post("INT-" + ++interestCount, range.last, Category.INTEREST, "interest", lines);
                    int days = range.last - range.first + 1;
                    emit("INTEREST %s entry %s %s days %d average %s amount %s", account.code, entry.id, dateText(range.last), days, money(sum / days), money(amount));
                }
                case "WRITEOFF" -> {
                    int day = parseDate(words[1]);
                    checkOpen(day);
                    Account account = requireType(words[2], AccountType.ASSET), expense = requireType(words[3], AccountType.EXPENSE);
                    active(account, expense);
                    int age = Integer.parseInt(words[4]);
                    TreeMap<String, Long> targets = new TreeMap<>();
                    long total = 0;
                    for (var group : settlements(account, day).entrySet()) {
                        long amount = 0;
                        for (OpenItem item : group.getValue().items) if (day - item.entry.day > age) amount += item.remaining;
                        if (amount > 0) { targets.put(group.getKey(), amount); total += amount; }
                    }
                    if (total == 0) throw new CommandError("nothing to write off " + account.code);
                    List<Line> items = new ArrayList<>();
                    items.add(new Line(true, expense, total));
                    for (var target : targets.entrySet()) items.add(new Line(false, account, target.getValue(), target.getKey()));
                    Entry entry = post("WO-" + ++writeoffCount, day, Category.WRITEOFF, "writeoff", new Lines(items));
                    emit("WRITEOFF %s entry %s %s partners %d amount %s", account.code, entry.id, dateText(day), targets.size(), money(total));
                    for (var target : targets.entrySet()) emit("  %s %s", target.getKey(), money(target.getValue()));
                }
                case "CLOSE" -> {
                    int day = parseDate(words[1]);
                    checkOpen(day);
                    Account equity = requireType(words[2], AccountType.EQUITY);
                    active(equity);
                    Map<Account, Totals> totals = totals(0, day, false);
                    List<Account> targets = new ArrayList<>();
                    for (Account account : accounts.values()) {
                        if (account.type.temporary() && totals.getOrDefault(account, Totals.ZERO).difference() != 0) targets.add(account);
                    }
                    for (Account account : targets) active(account);
                    List<Line> items = new ArrayList<>();
                    long income = 0;
                    for (Account account : targets) {
                        long value = totals.get(account).difference();
                        items.add(new Line(value < 0, account, Math.abs(value)));
                        income -= value;
                    }
                    if (income != 0) items.add(new Line(income < 0, equity, Math.abs(income)));
                    closeCount++;
                    Entry entry = items.isEmpty() ? null : post("CLOSE-" + closeCount, day, Category.CLOSING, "closing", new Lines(items));
                    closes.addLast(new CloseRecord(day, entry));
                    if (entry == null) emit("CLOSE %s no entry", dateText(day));
                    else emit("CLOSE %s entry %s lines %d net income %s", dateText(day), entry.id, items.size(), money(income));
                }
                case "REOPEN" -> {
                    if (closes.isEmpty()) throw new CommandError("nothing to reopen");
                    CloseRecord record = closes.getLast();
                    String detail = "no entry";
                    if (record.entry != null) {
                        activeLines(record.entry.lines);
                        detail = "entry " + reverse(record.entry, record.day, Category.REOPEN, "reopen").id;
                    }
                    closes.removeLast();
                    emit("REOPEN %s %s closed %s", dateText(record.day), detail, closedText());
                }
                case "LEDGER" -> {
                    Account account = account(words[1]);
                    DayRange range = dateRange(words[2], words[3]);
                    long running = balance(account, range.first - 1);
                    Totals totals = Totals.ZERO;
                    emit("LEDGER %s %s %s %s", account.code, account.name, words[2], words[3]);
                    emit("  opening %s", money(running));
                    for (Entry entry : ordered()) {
                        if (entry.day < range.first || entry.day > range.last) continue;
                        for (Line line : entry.lines.items) {
                            if (line.account != account) continue;
                            totals = totals.add(line.debit, line.amount);
                            running += account.type.sign() * line.difference();
                            emit("  %s %s %s %s balance %s %s", dateText(entry.day), entry.id, line.side(), money(line.amount), money(running), entry.memo);
                        }
                    }
                    int days = range.last - range.first + 1;
                    emit("  ending %s debits %s credits %s days %d average %s", money(running), money(totals.debit), money(totals.credit),
                         days, money(dailySum(account, range.first, range.last) / days));
                }
                case "ACTIVITY" -> {
                    Account account = account(words[1]);
                    int year = Integer.parseInt(words[2]);
                    Totals totals = Totals.ZERO;
                    emit("ACTIVITY %s %s %d", account.code, account.name, year);
                    for (int month = 1; month <= 12; month++) {
                        int first = dayNumber(year, month, 1), last = dayNumber(year, month, monthLength(year, month));
                        Totals current = accountTotals(account, first, last);
                        totals = totals.plus(current);
                        emit("  %04d-%02d debit %s credit %s balance %s", year, month, money(current.debit), money(current.credit), money(balance(account, last)));
                    }
                    emit("  total debit %s credit %s", money(totals.debit), money(totals.credit));
                }
                case "TRIAL" -> {
                    int day = parseDate(words[1]);
                    Map<Account, Totals> totals = totals(0, day, false);
                    long debit = 0, credit = 0;
                    emit("TRIAL %s", words[1]);
                    for (Account account : accounts.values()) {
                        long value = totals.getOrDefault(account, Totals.ZERO).difference();
                        if (value == 0) continue;
                        if (value > 0) debit += value; else credit -= value;
                        emit("  %s %s %s %s", account.code, account.name, value > 0 ? "debit" : "credit", money(Math.abs(value)));
                    }
                    emit("  total debit %s credit %s", money(debit), money(credit));
                }
                case "INCOME" -> {
                    DayRange range = dateRange(words[1], words[2]);
                    Map<Account, Totals> totals = totals(range.first, range.last, true);
                    emit("INCOME %s %s", words[1], words[2]);
                    long revenue = section("REVENUE", Set.of(AccountType.REVENUE), -1, totals, null);
                    long expense = section("EXPENSE", Set.of(AccountType.EXPENSE), 1, totals, null);
                    emit("  NET INCOME %s", money(revenue - expense));
                }
                case "BALANCE" -> {
                    int day = parseDate(words[1]);
                    Map<Account, Totals> totals = totals(0, day, false);
                    long earnings = 0;
                    for (Account account : accounts.values()) if (account.type.temporary()) earnings -= totals.getOrDefault(account, Totals.ZERO).difference();
                    emit("BALANCE %s", words[1]);
                    long assets = section("ASSETS", Set.of(AccountType.ASSET, AccountType.CONTRA_ASSET), 1, totals, null);
                    long liabilities = section("LIABILITIES", Set.of(AccountType.LIABILITY), -1, totals, null);
                    long equity = section("EQUITY", Set.of(AccountType.EQUITY), -1, totals, earnings);
                    if (assets == liabilities + equity) emit("  check ok");
                    else emit("  check mismatch %s", money(assets - liabilities - equity));
                }
                case "ROLLUP" -> {
                    int day = parseDate(words[2]);
                    List<Account> targets = accounts.values().stream().filter(account -> account.code.startsWith(words[1])).toList();
                    emit("ROLLUP %s %s", words[1], words[2]);
                    if (targets.isEmpty()) { emit("  (none)"); return; }
                    Map<Account, Totals> totals = totals(0, day, false);
                    Totals postings = Totals.ZERO;
                    for (Account account : targets) {
                        int depth = 0;
                        long subtotal = 0;
                        for (Account other : targets) {
                            if (other != account && account.code.startsWith(other.code)) depth++;
                            if (other.code.startsWith(account.code)) subtotal += totals.getOrDefault(other, Totals.ZERO).difference();
                        }
                        Totals own = totals.getOrDefault(account, Totals.ZERO);
                        emit("%s%s %s own %s total %s", " ".repeat(2 * (1 + depth)), account.code, account.name,
                             money(account.type.sign() * own.difference()), money(account.type.sign() * subtotal));
                        postings = postings.plus(own);
                    }
                    emit("  postings debit %s credit %s", money(postings.debit), money(postings.credit));
                }
                case "AGING", "ITEMS" -> {
                    Account account = account(words[1]);
                    boolean aging = words[0].equals("AGING");
                    int day = parseDate(words[aging ? 2 : 3]);
                    TreeMap<String, Settlement> settlements = settlements(account, day);
                    if (aging) {
                        emit("AGING %s %s %s", account.code, account.name, words[2]);
                        long[] totals = new long[5];
                        for (var group : settlements.entrySet()) {
                            Settlement settled = group.getValue();
                            if (settled.items.isEmpty() && settled.unapplied == 0) continue;
                            long[] values = {0, 0, 0, 0, settled.unapplied};
                            for (OpenItem item : settled.items) {
                                int age = day - item.entry.day, bucket = age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3;
                                values[bucket] += item.remaining;
                            }
                            agingRow(group.getKey(), values);
                            for (int i = 0; i < 5; i++) totals[i] += values[i];
                        }
                        agingRow("total", totals);
                    } else {
                        Settlement settled = settlements.getOrDefault(words[2], new Settlement());
                        emit("ITEMS %s %s %s %s", account.code, account.name, words[2], words[3]);
                        long remaining = 0;
                        for (OpenItem item : settled.items) {
                            emit("  %s %s amount %s open %s age %d", dateText(item.entry.day), item.entry.id, money(item.original), money(item.remaining), day - item.entry.day);
                            remaining += item.remaining;
                        }
                        emit("  unapplied %s balance %s", money(settled.unapplied), money(remaining - settled.unapplied));
                    }
                }
                case "ENTRY" -> {
                    Entry entry = entryIds.get(words[1]);
                    if (entry == null) throw new CommandError("unknown entry " + words[1]);
                    emit("ENTRY %s %s %s %s", entry.id, dateText(entry.day), entry.category.text(), entry.memo);
                    for (Line line : entry.lines.items) {
                        String partner = line.partner == null ? "" : " " + line.partner;
                        emit("  %s %s %s %s%s", line.side(), line.account.code, line.account.name, money(line.amount), partner);
                    }
                    emit("  total %s", money(entry.lines.amount));
                    if (entry.reverses != null) emit("  reverses %s", entry.reverses.id);
                    if (entry.reversedBy != null) emit("  reversed by %s", entry.reversedBy.id);
                }
                case "DAYBOOK" -> {
                    DayRange range = dateRange(words[1], words[2]);
                    long total = 0;
                    int count = 0;
                    emit("DAYBOOK %s %s", words[1], words[2]);
                    for (Entry entry : ordered()) {
                        if (entry.day < range.first || entry.day > range.last) continue;
                        total += entry.lines.amount;
                        count++;
                        emit("  %s %s %s %s %s", dateText(entry.day), entry.id, entry.category.text(), money(entry.lines.amount), entry.memo);
                    }
                    emit("  total entries %d amount %s", count, money(total));
                }
                case "ACCOUNTS" -> {
                    Map<Account, Totals> totals = totals(0, LAST_DAY, false);
                    emit("ACCOUNTS");
                    for (Account account : accounts.values()) {
                        emit("  %s %s %s parent %s balance %s %s", account.code, account.type, account.name, parent(account.code),
                             money(account.type.sign() * totals.getOrDefault(account, Totals.ZERO).difference()), account.active ? "active" : "inactive");
                    }
                    if (accounts.isEmpty()) emit("  (none)");
                }
                case "TEMPLATES" -> {
                    emit("TEMPLATES");
                    for (var item : templates.entrySet()) {
                        Template model = item.getValue();
                        emit("  %s %s lines %d amount %s used %d", item.getKey(), model.memo, model.lines.items.size(), money(model.lines.amount), model.uses);
                    }
                    if (templates.isEmpty()) emit("  (none)");
                }
                case "STATUS" -> {
                    long inactive = accounts.values().stream().filter(account -> !account.active).count();
                    emit("STATUS accounts %d inactive %d entries %d templates %d closed %s open %s", accounts.size(), inactive, entries.size(),
                         templates.size(), closedText(), draft == null ? "none" : draft.key);
                }
            }
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        PrintWriter output = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8)));
        int count = Integer.parseInt(input.readLine());
        Book book = new Book(output);
        for (int i = 0; i < count; i++) {
            try { book.execute(input.readLine().split(" ")); }
            catch (CommandError error) { book.emit("ERROR %s", error.getMessage()); }
        }
        output.flush();
    }
}
