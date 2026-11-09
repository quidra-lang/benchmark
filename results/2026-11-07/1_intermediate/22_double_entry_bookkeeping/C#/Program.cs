using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

class Program
{
    sealed class CommandError(string message) : Exception(message) { }
    enum AccountType { Asset, Liability, Equity, Revenue, Expense, ContraAsset }
    enum EntryKind { Journal, Recurring, Reversal, Closing, Reopen, Depreciation, Interest, Writeoff }

    readonly record struct BookDate(int Year, int Month, int Day)
    {
        static readonly int[] MonthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        public static int DaysInMonth(int year, int month) =>
            MonthLengths[month - 1] + (month == 2 && year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 1 : 0);
        public int Number
        {
            get
            {
                int previous = Year - 1;
                int days = 365 * (Year - 2000) + previous / 4 - 1999 / 4
                    - previous / 100 + 1999 / 100 + previous / 400 - 1999 / 400;
                for (int month = 1; month < Month; month++) days += DaysInMonth(Year, month);
                return days + Day - 1;
            }
        }
        public static BookDate Parse(string text)
        {
            int year = int.Parse(text[..4]), month = int.Parse(text[5..7]), day = int.Parse(text[8..]);
            if (year < 2000 || year > 2099 || month < 1 || month > 12 || day < 1 || day > DaysInMonth(year, month))
                throw new CommandError($"invalid date {text}");
            return new(year, month, day);
        }
        public BookDate AddMonths(int count)
        {
            int offset = Month - 1 + count, year = Year + offset / 12, month = offset % 12 + 1;
            return new(year, month, Math.Min(Day, DaysInMonth(year, month)));
        }
        public override string ToString() => $"{Year:D4}-{Month:D2}-{Day:D2}";
    }

    sealed class Account(string code, AccountType type, string name)
    {
        public string Code { get; } = code;
        public AccountType Type { get; } = type;
        public string Name { get; } = name;
        public bool Active { get; set; } = true;
        public int Sign => Type is AccountType.Asset or AccountType.Expense ? 1 : -1;
        public AccountType Class => Type == AccountType.ContraAsset ? AccountType.Asset : Type;
    }
    sealed record Line(bool Debit, string Code, long Amount, string? Partner = null)
    {
        public long Difference => Debit ? Amount : -Amount;
        public string Side => Debit ? "DR" : "CR";
    }
    sealed class Entry(string id, BookDate date, EntryKind kind, string memo, Line[] lines, int sequence)
    {
        public string Id { get; } = id;
        public BookDate Date { get; } = date;
        public EntryKind Kind { get; } = kind;
        public string Memo { get; } = memo;
        public Line[] Lines { get; } = lines;
        public int Sequence { get; } = sequence;
        public string? ReversedBy { get; set; }
        public string? Reverses { get; set; }
        public long Amount => Lines.Where(line => line.Debit).Sum(line => line.Amount);
        public string Category => Kind.ToString().ToLowerInvariant();
    }
    sealed class Template(string memo, Line[] lines)
    {
        public string Memo { get; } = memo;
        public Line[] Lines { get; } = lines;
        public int Uses { get; set; }
    }
    sealed class Draft(bool journal, string key, string? date, string memo)
    {
        public bool Journal { get; } = journal;
        public string Kind => Journal ? "journal" : "template";
        public string Key { get; } = key;
        public string? Date { get; } = date;
        public string Memo { get; } = memo;
        public List<Line> Lines { get; } = [];
    }
    readonly record struct Totals(long Debit, long Credit)
    {
        public long Difference => Debit - Credit;
        public Totals Add(Line line) => line.Debit ? this with { Debit = Debit + line.Amount } : this with { Credit = Credit + line.Amount };
    }
    sealed class OpenItem(Entry entry, long original, long remaining)
    {
        public Entry Entry { get; } = entry;
        public long Original { get; } = original;
        public long Remaining { get; set; } = remaining;
    }
    sealed class Settlement
    {
        public Queue<OpenItem> Items { get; } = new();
        public long Unapplied { get; set; }
    }
    sealed record CloseRecord(BookDate Date, Entry? Entry);

    static string Money(long cents)
    {
        long absolute = Math.Abs(cents);
        return $"{(cents < 0 ? "-" : "")}{absolute / 100}.{absolute % 100:D2}";
    }
    static long ParseMoney(string text) => long.Parse(text[..^3]) * 100 + int.Parse(text[^2..]);
    static string TypeName(AccountType type) => type == AccountType.ContraAsset ? "CONTRA_ASSET" : type.ToString().ToUpperInvariant();
    static AccountType ParseType(string text) => text switch
    {
        "ASSET" => AccountType.Asset, "LIABILITY" => AccountType.Liability, "EQUITY" => AccountType.Equity,
        "REVENUE" => AccountType.Revenue, "EXPENSE" => AccountType.Expense, _ => AccountType.ContraAsset
    };
    static bool Prefix(string prefix, string code) => code.StartsWith(prefix, StringComparison.Ordinal);

    sealed class Books
    {
        readonly SortedDictionary<string, Account> accounts = new(StringComparer.Ordinal);
        readonly List<Entry> entries = [];
        readonly Dictionary<string, Entry> entryIds = new(StringComparer.Ordinal);
        readonly SortedDictionary<string, Template> templates = new(StringComparer.Ordinal);
        readonly Stack<CloseRecord> closes = new();
        readonly StringBuilder output = new();
        Draft? draft;
        int closeCount, depreciationCount, interestCount, writeoffCount;

        void Emit(string text) => output.Append(text).Append('\n');
        string Closed => closes.Count == 0 ? "none" : closes.Peek().Date.ToString();
        Account GetAccount(string code) => accounts.TryGetValue(code, out var account) ? account : throw new CommandError($"unknown account {code}");
        Entry GetEntry(string id) => entryIds.TryGetValue(id, out var entry) ? entry : throw new CommandError($"unknown entry {id}");
        Account RequireType(string code, AccountType type)
        {
            var account = GetAccount(code);
            if (account.Type != type) throw new CommandError($"wrong type {code} {TypeName(type)}");
            return account;
        }
        static void Active(IEnumerable<Account> sequence)
        {
            foreach (var account in sequence)
                if (!account.Active) throw new CommandError($"inactive account {account.Code}");
        }
        void CheckClosed(BookDate date)
        {
            if (closes.Count > 0 && date.Number <= closes.Peek().Date.Number) throw new CommandError($"period closed {date}");
        }
        static (BookDate Start, BookDate End) Range(string start, string end)
        {
            var a = BookDate.Parse(start);
            var b = BookDate.Parse(end);
            if (a.Number > b.Number) throw new CommandError($"invalid range {start} {end}");
            return (a, b);
        }
        IEnumerable<Entry> Ordered(int start = 0, int end = int.MaxValue) => entries
            .Where(entry => entry.Date.Number >= start && entry.Date.Number <= end)
            .OrderBy(entry => entry.Date.Number).ThenBy(entry => entry.Sequence);
        Dictionary<string, Totals> Aggregate(int start = 0, int end = int.MaxValue, bool operating = false)
        {
            var result = new Dictionary<string, Totals>(StringComparer.Ordinal);
            foreach (var entry in entries)
            {
                if (entry.Date.Number < start || entry.Date.Number > end || operating && (entry.Kind is EntryKind.Closing or EntryKind.Reopen)) continue;
                foreach (var line in entry.Lines) result[line.Code] = result.GetValueOrDefault(line.Code).Add(line);
            }
            return result;
        }
        long Balance(Account account, int end = int.MaxValue) =>
            entries.Where(entry => entry.Date.Number <= end).Sum(entry => entry.Lines.Where(line => line.Code == account.Code).Sum(line => line.Difference)) * account.Sign;
        long DailySum(Account account, int start, int end)
        {
            long sum = 0;
            foreach (var entry in entries)
            {
                if (entry.Date.Number > end) continue;
                long change = entry.Lines.Where(line => line.Code == account.Code).Sum(line => line.Difference) * account.Sign;
                sum += change * (end - Math.Max(start, entry.Date.Number) + 1);
            }
            return sum;
        }
        string Parent(string code) => accounts.Keys.Where(other => other != code && Prefix(other, code)).OrderByDescending(other => other.Length).FirstOrDefault() ?? "none";
        string Top(string code) => accounts.Keys.First(other => Prefix(other, code));
        Entry Post(string id, BookDate date, EntryKind kind, string memo, IEnumerable<Line> lines)
        {
            var entry = new Entry(id, date, kind, memo, lines.ToArray(), entries.Count + 1);
            entries.Add(entry);
            entryIds.Add(id, entry);
            return entry;
        }
        Entry Reverse(Entry original, BookDate date, EntryKind kind, string memo)
        {
            var entry = Post(original.Id + "-R", date, kind, memo, original.Lines.Select(line => line with { Debit = !line.Debit }));
            original.ReversedBy = entry.Id;
            entry.Reverses = original.Id;
            return entry;
        }
        static Totals LineTotals(IEnumerable<Line> lines)
        {
            var total = new Totals();
            foreach (var line in lines) total = total.Add(line);
            return total;
        }
        SortedDictionary<string, Settlement> Settlements(Account account, int date)
        {
            var result = new SortedDictionary<string, Settlement>(StringComparer.Ordinal);
            foreach (var entry in Ordered(end: date))
            foreach (var line in entry.Lines)
            {
                if (line.Code != account.Code || line.Partner is null) continue;
                if (!result.TryGetValue(line.Partner, out var settlement)) result.Add(line.Partner, settlement = new());
                long signed = line.Difference * account.Sign;
                if (signed > 0)
                {
                    long applied = Math.Min(signed, settlement.Unapplied);
                    settlement.Unapplied -= applied;
                    if (signed > applied) settlement.Items.Enqueue(new(entry, signed, signed - applied));
                }
                else
                {
                    long remaining = -signed;
                    while (remaining > 0 && settlement.Items.Count > 0)
                    {
                        var item = settlement.Items.Peek();
                        long applied = Math.Min(remaining, item.Remaining);
                        item.Remaining -= applied;
                        remaining -= applied;
                        if (item.Remaining == 0) settlement.Items.Dequeue();
                    }
                    settlement.Unapplied += remaining;
                }
            }
            return result;
        }
        long Section(string heading, AccountType[] types, int sign, Dictionary<string, Totals> totals, long? earnings = null)
        {
            var targets = accounts.Values.Where(account => types.Contains(account.Type)).ToArray();
            long Display(Account account) => totals.GetValueOrDefault(account.Code).Difference * sign;
            long total = targets.Sum(Display) + (earnings ?? 0);
            Emit($"  {heading} {Money(total)}");
            foreach (var group in targets.GroupBy(account => Top(account.Code)).OrderBy(group => group.Key, StringComparer.Ordinal))
            {
                if (!group.Any(account => Display(account) != 0)) continue;
                Emit($"    {group.Key} {accounts[group.Key].Name} {Money(group.Sum(Display))}");
                foreach (var account in group)
                    if (Display(account) != 0) Emit($"      {account.Code} {account.Name} {Money(Display(account))}");
            }
            if (earnings is not null) Emit($"    current earnings {Money(earnings.Value)}");
            return total;
        }

        void PostDraft()
        {
            var block = draft ?? throw new CommandError("no open entry");
            draft = null;
            BookDate date = default;
            if (block.Journal)
            {
                if (entryIds.ContainsKey(block.Key)) throw new CommandError($"duplicate entry {block.Key}");
                date = BookDate.Parse(block.Date!);
                CheckClosed(date);
            }
            else if (templates.ContainsKey(block.Key)) throw new CommandError($"duplicate template {block.Key}");
            if (block.Lines.Count < 2) throw new CommandError($"too few lines {block.Key}");
            foreach (var line in block.Lines)
            {
                var account = GetAccount(line.Code);
                if (block.Journal && !account.Active) throw new CommandError($"inactive account {line.Code}");
                if (line.Amount == 0) throw new CommandError($"zero amount {line.Code}");
            }
            var total = LineTotals(block.Lines);
            if (total.Debit != total.Credit) throw new CommandError($"unbalanced {block.Key} debit {Money(total.Debit)} credit {Money(total.Credit)}");
            if (block.Journal)
            {
                var entry = Post(block.Key, date, EntryKind.Journal, block.Memo, block.Lines);
                Emit($"POST {entry.Id} {date} lines {entry.Lines.Length} amount {Money(entry.Amount)}");
            }
            else
            {
                templates.Add(block.Key, new(block.Memo, block.Lines.ToArray()));
                Emit($"TEMPLATE {block.Key} lines {block.Lines.Count} amount {Money(total.Debit)}");
            }
        }
        void Close(BookDate date, string code)
        {
            CheckClosed(date);
            var equity = RequireType(code, AccountType.Equity);
            Active([equity]);
            var totals = Aggregate(end: date.Number);
            var targets = accounts.Values.Where(account => (account.Type is AccountType.Revenue or AccountType.Expense)
                && totals.GetValueOrDefault(account.Code).Difference != 0).ToArray();
            Active(targets);
            var lines = new List<Line>();
            long income = 0;
            foreach (var account in targets)
            {
                long difference = totals.GetValueOrDefault(account.Code).Difference;
                lines.Add(new(difference < 0, account.Code, Math.Abs(difference)));
                income -= difference;
            }
            if (income != 0) lines.Add(new(income < 0, code, Math.Abs(income)));
            closeCount++;
            Entry? entry = lines.Count == 0 ? null : Post($"CLOSE-{closeCount}", date, EntryKind.Closing, "closing", lines);
            closes.Push(new(date, entry));
            Emit(entry is null ? $"CLOSE {date} no entry" : $"CLOSE {date} entry {entry.Id} lines {lines.Count} net income {Money(income)}");
        }
        void Ledger(Account account, BookDate start, BookDate end)
        {
            long running = Balance(account, start.Number - 1), debit = 0, credit = 0;
            Emit($"LEDGER {account.Code} {account.Name} {start} {end}");
            Emit($"  opening {Money(running)}");
            foreach (var entry in Ordered(start.Number, end.Number))
            foreach (var line in entry.Lines)
            {
                if (line.Code != account.Code) continue;
                running += line.Difference * account.Sign;
                if (line.Debit) debit += line.Amount; else credit += line.Amount;
                Emit($"  {entry.Date} {entry.Id} {line.Side} {Money(line.Amount)} balance {Money(running)} {entry.Memo}");
            }
            int days = end.Number - start.Number + 1;
            Emit($"  ending {Money(running)} debits {Money(debit)} credits {Money(credit)} days {days} average {Money(DailySum(account, start.Number, end.Number) / days)}");
        }
        static string AgeColumns(long[] values) =>
            $"0-30 {Money(values[0])} 31-60 {Money(values[1])} 61-90 {Money(values[2])} 91+ {Money(values[3])} unapplied {Money(values[4])} balance {Money(values.Take(4).Sum() - values[4])}";

        public void Execute(string text)
        {
            var words = text.Split(' ');
            switch (words[0])
            {
                case "ACCOUNT":
                {
                    string code = words[1];
                    if (accounts.ContainsKey(code)) throw new CommandError($"duplicate account {code}");
                    var account = new Account(code, ParseType(words[2]), words[3]);
                    foreach (var other in accounts.Values)
                        if ((Prefix(code, other.Code) || Prefix(other.Code, code)) && account.Class != other.Class)
                            throw new CommandError($"class mismatch {code} {other.Code}");
                    accounts.Add(code, account);
                    Emit($"ACCOUNT {code} {words[2]} {account.Name} parent {Parent(code)}");
                    break;
                }
                case "DEACTIVATE":
                {
                    var account = GetAccount(words[1]);
                    if (!account.Active) throw new CommandError($"already inactive {account.Code}");
                    long balance = Balance(account);
                    if (balance != 0) throw new CommandError($"nonzero balance {account.Code} {Money(balance)}");
                    account.Active = false;
                    Emit($"DEACTIVATE {account.Code} {account.Name}");
                    break;
                }
                case "JOURNAL":
                case "TEMPLATE":
                    if (draft is not null) Emit($"DISCARD {draft.Key} lines {draft.Lines.Count}");
                    draft = words[0] == "JOURNAL" ? new(true, words[1], words[2], words[3]) : new(false, words[1], null, words[2]);
                    break;
                case "DR":
                case "CR":
                    if (draft is null) throw new CommandError("no open entry");
                    draft.Lines.Add(new(words[0] == "DR", words[1], ParseMoney(words[2]), words.Length == 4 ? words[3] : null));
                    break;
                case "POST": PostDraft(); break;
                case "DRAFT":
                {
                    var block = draft ?? throw new CommandError("no open entry");
                    var total = LineTotals(block.Lines);
                    Emit($"DRAFT {block.Kind} {block.Key} lines {block.Lines.Count} debit {Money(total.Debit)} credit {Money(total.Credit)} difference {Money(total.Difference)}");
                    break;
                }
                case "REVERSE":
                {
                    var original = GetEntry(words[1]);
                    if (original.Kind is EntryKind.Reversal or EntryKind.Closing or EntryKind.Reopen) throw new CommandError($"cannot reverse {original.Id}");
                    if (original.ReversedBy is not null) throw new CommandError($"already reversed {original.Id}");
                    var date = BookDate.Parse(words[2]);
                    if (date.Number < original.Date.Number) throw new CommandError($"reverse before entry {original.Id} {original.Date}");
                    CheckClosed(date);
                    Active(original.Lines.Select(line => accounts[line.Code]));
                    var entry = Reverse(original, date, EntryKind.Reversal, original.Memo);
                    Emit($"REVERSE {original.Id} entry {entry.Id} {date} amount {Money(entry.Amount)}");
                    break;
                }
                case "RECUR":
                {
                    if (!templates.TryGetValue(words[1], out var template)) throw new CommandError($"unknown template {words[1]}");
                    var date = BookDate.Parse(words[2]);
                    int count = int.Parse(words[3]);
                    if (count == 0) throw new CommandError("invalid count");
                    CheckClosed(date);
                    Active(template.Lines.Select(line => accounts[line.Code]));
                    Emit($"RECUR {words[1]} count {count}");
                    for (int month = 0; month < count; month++)
                    {
                        var entry = Post($"{words[1]}-{++template.Uses}", date.AddMonths(month), EntryKind.Recurring, template.Memo, template.Lines);
                        Emit($"  POST {entry.Id} {entry.Date} lines {entry.Lines.Length} amount {Money(entry.Amount)}");
                    }
                    break;
                }
                case "DEPRECIATE":
                {
                    var date = BookDate.Parse(words[1]);
                    CheckClosed(date);
                    var asset = RequireType(words[2], AccountType.Asset);
                    var contra = RequireType(words[3], AccountType.ContraAsset);
                    var expense = RequireType(words[4], AccountType.Expense);
                    Active([contra, expense]);
                    long cost = Balance(asset, date.Number), accumulated = Balance(contra, date.Number);
                    long amount = cost > 0 ? Math.Min(cost / int.Parse(words[5]), cost - accumulated) : 0;
                    if (amount <= 0) throw new CommandError($"nothing to depreciate {asset.Code}");
                    var entry = Post($"DEP-{++depreciationCount}", date, EntryKind.Depreciation, "depreciation", [new(true, expense.Code, amount), new(false, contra.Code, amount)]);
                    Emit($"DEPRECIATE {asset.Code} entry {entry.Id} {date} amount {Money(amount)} accumulated {Money(accumulated + amount)} book {Money(cost - accumulated - amount)}");
                    break;
                }
                case "INTEREST":
                {
                    var account = GetAccount(words[1]);
                    if (account.Type is not (AccountType.Asset or AccountType.Liability)) throw new CommandError($"not interest bearing {account.Code}");
                    var offset = RequireType(words[2], account.Type == AccountType.Asset ? AccountType.Revenue : AccountType.Expense);
                    var (start, end) = Range(words[3], words[4]);
                    CheckClosed(end);
                    Active([account, offset]);
                    long sum = DailySum(account, start.Number, end.Number), amount = sum * int.Parse(words[5]) / 3650000;
                    if (amount <= 0) throw new CommandError($"no interest {account.Code}");
                    string debit = account.Type == AccountType.Asset ? account.Code : offset.Code;
                    string credit = account.Type == AccountType.Asset ? offset.Code : account.Code;
                    var entry = Post($"INT-{++interestCount}", end, EntryKind.Interest, "interest", [new(true, debit, amount), new(false, credit, amount)]);
                    int days = end.Number - start.Number + 1;
                    Emit($"INTEREST {account.Code} entry {entry.Id} {end} days {days} average {Money(sum / days)} amount {Money(amount)}");
                    break;
                }
                case "WRITEOFF":
                {
                    var date = BookDate.Parse(words[1]);
                    CheckClosed(date);
                    var account = RequireType(words[2], AccountType.Asset);
                    var expense = RequireType(words[3], AccountType.Expense);
                    Active([account, expense]);
                    int age = int.Parse(words[4]);
                    var targets = Settlements(account, date.Number).Select(pair => (Partner: pair.Key,
                        Amount: pair.Value.Items.Where(item => date.Number - item.Entry.Date.Number > age).Sum(item => item.Remaining)))
                        .Where(target => target.Amount > 0).ToArray();
                    long total = targets.Sum(target => target.Amount);
                    if (total == 0) throw new CommandError($"nothing to write off {account.Code}");
                    var lines = new List<Line> { new(true, expense.Code, total) };
                    lines.AddRange(targets.Select(target => new Line(false, account.Code, target.Amount, target.Partner)));
                    var entry = Post($"WO-{++writeoffCount}", date, EntryKind.Writeoff, "writeoff", lines);
                    Emit($"WRITEOFF {account.Code} entry {entry.Id} {date} partners {targets.Length} amount {Money(total)}");
                    foreach (var target in targets) Emit($"  {target.Partner} {Money(target.Amount)}");
                    break;
                }
                case "CLOSE": Close(BookDate.Parse(words[1]), words[2]); break;
                case "REOPEN":
                {
                    if (closes.Count == 0) throw new CommandError("nothing to reopen");
                    var record = closes.Peek();
                    string result = "no entry";
                    if (record.Entry is not null)
                    {
                        Active(record.Entry.Lines.Select(line => accounts[line.Code]));
                        result = "entry " + Reverse(record.Entry, record.Date, EntryKind.Reopen, "reopen").Id;
                    }
                    closes.Pop();
                    Emit($"REOPEN {record.Date} {result} closed {Closed}");
                    break;
                }
                case "LEDGER":
                {
                    var account = GetAccount(words[1]);
                    var (start, end) = Range(words[2], words[3]);
                    Ledger(account, start, end);
                    break;
                }
                case "ACTIVITY":
                {
                    var account = GetAccount(words[1]);
                    int year = int.Parse(words[2]);
                    long debit = 0, credit = 0;
                    Emit($"ACTIVITY {account.Code} {account.Name} {year}");
                    for (int month = 1; month <= 12; month++)
                    {
                        int start = new BookDate(year, month, 1).Number, end = new BookDate(year, month, BookDate.DaysInMonth(year, month)).Number;
                        var totals = Aggregate(start, end).GetValueOrDefault(account.Code);
                        debit += totals.Debit;
                        credit += totals.Credit;
                        Emit($"  {year:D4}-{month:D2} debit {Money(totals.Debit)} credit {Money(totals.Credit)} balance {Money(Balance(account, end))}");
                    }
                    Emit($"  total debit {Money(debit)} credit {Money(credit)}");
                    break;
                }
                case "TRIAL":
                {
                    var date = BookDate.Parse(words[1]);
                    var totals = Aggregate(end: date.Number);
                    long debit = 0, credit = 0;
                    Emit($"TRIAL {date}");
                    foreach (var account in accounts.Values)
                    {
                        long difference = totals.GetValueOrDefault(account.Code).Difference;
                        if (difference == 0) continue;
                        if (difference > 0) debit += difference; else credit -= difference;
                        Emit($"  {account.Code} {account.Name} {(difference > 0 ? "debit" : "credit")} {Money(Math.Abs(difference))}");
                    }
                    Emit($"  total debit {Money(debit)} credit {Money(credit)}");
                    break;
                }
                case "INCOME":
                {
                    var (start, end) = Range(words[1], words[2]);
                    var totals = Aggregate(start.Number, end.Number, operating: true);
                    Emit($"INCOME {start} {end}");
                    long revenue = Section("REVENUE", [AccountType.Revenue], -1, totals);
                    long expense = Section("EXPENSE", [AccountType.Expense], 1, totals);
                    Emit($"  NET INCOME {Money(revenue - expense)}");
                    break;
                }
                case "BALANCE":
                {
                    var date = BookDate.Parse(words[1]);
                    var totals = Aggregate(end: date.Number);
                    long earnings = -accounts.Values.Where(account => account.Type is AccountType.Revenue or AccountType.Expense)
                        .Sum(account => totals.GetValueOrDefault(account.Code).Difference);
                    Emit($"BALANCE {date}");
                    long assets = Section("ASSETS", [AccountType.Asset, AccountType.ContraAsset], 1, totals);
                    long liabilities = Section("LIABILITIES", [AccountType.Liability], -1, totals);
                    long equity = Section("EQUITY", [AccountType.Equity], -1, totals, earnings);
                    Emit(assets == liabilities + equity ? "  check ok" : $"  check mismatch {Money(assets - liabilities - equity)}");
                    break;
                }
                case "ROLLUP":
                {
                    var date = BookDate.Parse(words[2]);
                    var targets = accounts.Values.Where(account => Prefix(words[1], account.Code)).ToArray();
                    Emit($"ROLLUP {words[1]} {date}");
                    if (targets.Length == 0) { Emit("  (none)"); break; }
                    var totals = Aggregate(end: date.Number);
                    foreach (var account in targets)
                    {
                        int depth = targets.Count(other => other.Code != account.Code && Prefix(other.Code, account.Code));
                        long subtotal = targets.Where(other => Prefix(account.Code, other.Code)).Sum(other => totals.GetValueOrDefault(other.Code).Difference) * account.Sign;
                        Emit($"{new string(' ', 2 * (1 + depth))}{account.Code} {account.Name} own {Money(totals.GetValueOrDefault(account.Code).Difference * account.Sign)} total {Money(subtotal)}");
                    }
                    Emit($"  postings debit {Money(targets.Sum(account => totals.GetValueOrDefault(account.Code).Debit))} credit {Money(targets.Sum(account => totals.GetValueOrDefault(account.Code).Credit))}");
                    break;
                }
                case "AGING":
                {
                    var account = GetAccount(words[1]);
                    var date = BookDate.Parse(words[2]);
                    Emit($"AGING {account.Code} {account.Name} {date}");
                    var total = new long[5];
                    foreach (var (partner, settlement) in Settlements(account, date.Number))
                    {
                        if (settlement.Items.Count == 0 && settlement.Unapplied == 0) continue;
                        var values = new long[5];
                        foreach (var item in settlement.Items)
                        {
                            int age = date.Number - item.Entry.Date.Number;
                            values[age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3] += item.Remaining;
                        }
                        values[4] = settlement.Unapplied;
                        for (int i = 0; i < 5; i++) total[i] += values[i];
                        Emit($"  {partner} {AgeColumns(values)}");
                    }
                    Emit($"  total {AgeColumns(total)}");
                    break;
                }
                case "ITEMS":
                {
                    var account = GetAccount(words[1]);
                    var date = BookDate.Parse(words[3]);
                    var settlements = Settlements(account, date.Number);
                    var settlement = settlements.TryGetValue(words[2], out var found) ? found : new Settlement();
                    Emit($"ITEMS {account.Code} {account.Name} {words[2]} {date}");
                    foreach (var item in settlement.Items)
                        Emit($"  {item.Entry.Date} {item.Entry.Id} amount {Money(item.Original)} open {Money(item.Remaining)} age {date.Number - item.Entry.Date.Number}");
                    Emit($"  unapplied {Money(settlement.Unapplied)} balance {Money(settlement.Items.Sum(item => item.Remaining) - settlement.Unapplied)}");
                    break;
                }
                case "ENTRY":
                {
                    var entry = GetEntry(words[1]);
                    Emit($"ENTRY {entry.Id} {entry.Date} {entry.Category} {entry.Memo}");
                    foreach (var line in entry.Lines)
                        Emit($"  {line.Side} {line.Code} {accounts[line.Code].Name} {Money(line.Amount)}{(line.Partner is null ? "" : " " + line.Partner)}");
                    Emit($"  total {Money(entry.Amount)}");
                    if (entry.Reverses is not null) Emit($"  reverses {entry.Reverses}");
                    if (entry.ReversedBy is not null) Emit($"  reversed by {entry.ReversedBy}");
                    break;
                }
                case "DAYBOOK":
                {
                    var (start, end) = Range(words[1], words[2]);
                    var selected = Ordered(start.Number, end.Number).ToArray();
                    Emit($"DAYBOOK {start} {end}");
                    foreach (var entry in selected) Emit($"  {entry.Date} {entry.Id} {entry.Category} {Money(entry.Amount)} {entry.Memo}");
                    Emit($"  total entries {selected.Length} amount {Money(selected.Sum(entry => entry.Amount))}");
                    break;
                }
                case "ACCOUNTS":
                {
                    var totals = Aggregate();
                    Emit("ACCOUNTS");
                    foreach (var account in accounts.Values)
                        Emit($"  {account.Code} {TypeName(account.Type)} {account.Name} parent {Parent(account.Code)} balance {Money(totals.GetValueOrDefault(account.Code).Difference * account.Sign)} {(account.Active ? "active" : "inactive")}");
                    if (accounts.Count == 0) Emit("  (none)");
                    break;
                }
                case "TEMPLATES":
                    Emit("TEMPLATES");
                    foreach (var (name, template) in templates)
                        Emit($"  {name} {template.Memo} lines {template.Lines.Length} amount {Money(LineTotals(template.Lines).Debit)} used {template.Uses}");
                    if (templates.Count == 0) Emit("  (none)");
                    break;
                case "STATUS":
                    Emit($"STATUS accounts {accounts.Count} inactive {accounts.Values.Count(account => !account.Active)} entries {entries.Count} templates {templates.Count} closed {Closed} open {draft?.Key ?? "none"}");
                    break;
            }
        }
        public void Process(string text)
        {
            try { Execute(text); }
            catch (CommandError error) { Emit("ERROR " + error.Message); }
        }
        public override string ToString() => output.ToString();
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!);
        var books = new Books();
        for (int i = 0; i < count; i++) books.Process(Console.ReadLine()!);
        Console.Write(books);
    }
}
