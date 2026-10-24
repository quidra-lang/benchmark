#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <iostream>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Cents = std::int64_t;

struct CommandError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

enum class AccountType { Asset, Liability, Equity, Revenue, Expense, ContraAsset };
enum class Category { Journal, Recurring, Reversal, Closing, Reopen, Depreciation, Interest, Writeoff };

const std::array<std::string, 6> typeNames = {
    "ASSET", "LIABILITY", "EQUITY", "REVENUE", "EXPENSE", "CONTRA_ASSET"
};
const std::array<std::string, 8> categoryNames = {
    "journal", "recurring", "reversal", "closing", "reopen", "depreciation", "interest", "writeoff"
};
constexpr int lastDay = 36524;

std::string label(AccountType type) { return typeNames[static_cast<std::size_t>(type)]; }
std::string label(Category category) { return categoryNames[static_cast<std::size_t>(category)]; }

AccountType parseType(const std::string& text) {
    return static_cast<AccountType>(std::find(typeNames.begin(), typeNames.end(), text) - typeNames.begin());
}

AccountType accountClass(AccountType type) {
    return type == AccountType::ContraAsset ? AccountType::Asset : type;
}

int normalSign(AccountType type) {
    return type == AccountType::Asset || type == AccountType::Expense ? 1 : -1;
}

bool incomeType(AccountType type) { return type == AccountType::Revenue || type == AccountType::Expense; }
bool startsWith(const std::string& text, const std::string& prefix) { return text.compare(0, prefix.size(), prefix) == 0; }

std::string padded(int value, std::size_t width = 2) {
    std::string text = std::to_string(value);
    return std::string(width > text.size() ? width - text.size() : 0, '0') + text;
}

std::string money(Cents value) {
    Cents magnitude = value < 0 ? -value : value;
    return (value < 0 ? "-" : "") + std::to_string(magnitude / 100) + "." + padded(static_cast<int>(magnitude % 100));
}

Cents parseMoney(const std::string& text) {
    auto dot = text.find('.');
    return std::stoll(text.substr(0, dot)) * 100 + std::stoll(text.substr(dot + 1));
}

bool leap(int year) { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0); }

int monthLength(int year, int month) {
    constexpr std::array<int, 12> lengths = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return lengths[month - 1] + (month == 2 && leap(year) ? 1 : 0);
}

int dayNumber(int year, int month, int day) {
    int result = day - 1;
    for (int y = 2000; y < year; ++y) result += leap(y) ? 366 : 365;
    for (int m = 1; m < month; ++m) result += monthLength(year, m);
    return result;
}

struct CalendarDate { int year, month, day; };

CalendarDate calendar(int number) {
    int year = 2000, month = 1;
    while (number >= (leap(year) ? 366 : 365)) {
        number -= leap(year) ? 366 : 365;
        ++year;
    }
    while (number >= monthLength(year, month)) {
        number -= monthLength(year, month);
        ++month;
    }
    return {year, month, number + 1};
}

std::string dateText(int number) {
    auto date = calendar(number);
    return padded(date.year, 4) + "-" + padded(date.month) + "-" + padded(date.day);
}

int checkedDate(const std::string& text) {
    int year = std::stoi(text.substr(0, 4)), month = std::stoi(text.substr(5, 2)), day = std::stoi(text.substr(8, 2));
    if (year < 2000 || year > 2099 || month < 1 || month > 12 || day < 1 || day > monthLength(year, month)) {
        throw CommandError("invalid date " + text);
    }
    return dayNumber(year, month, day);
}

std::pair<int, int> checkedRange(const std::string& first, const std::string& last) {
    int start = checkedDate(first), end = checkedDate(last);
    if (start > end) throw CommandError("invalid range " + first + " " + last);
    return {start, end};
}

int monthsAfter(int number, int count) {
    auto original = calendar(number);
    int offset = original.month - 1 + count;
    int year = original.year + offset / 12, month = offset % 12 + 1;
    return dayNumber(year, month, std::min(original.day, monthLength(year, month)));
}

struct Account {
    std::string code, name;
    AccountType type;
    bool active = true;
};

struct Line {
    bool debit;
    std::string code;
    Cents amount;
    std::optional<std::string> partner;
    Cents difference() const { return debit ? amount : -amount; }
    std::string side() const { return debit ? "DR" : "CR"; }
};

Cents lineTotal(const std::vector<Line>& lines, bool debit = true) {
    Cents total = 0;
    for (const auto& line : lines) if (line.debit == debit) total += line.amount;
    return total;
}

struct Entry {
    std::string id;
    int day;
    Category category;
    std::string memo;
    std::vector<Line> lines;
    std::size_t sequence;
    std::optional<std::string> reversedBy, reverses;
};

struct Template {
    std::string memo;
    std::vector<Line> lines;
    int uses = 0;
};

struct Draft {
    bool journal;
    std::string key, date, memo;
    std::vector<Line> lines;
};

struct CloseRecord { int day; Entry* entry; };
struct Totals {
    Cents debit = 0, credit = 0;
    Cents difference() const { return debit - credit; }
};
using TotalsByCode = std::map<std::string, Totals>;

Totals getTotals(const TotalsByCode& totals, const std::string& code) {
    auto found = totals.find(code);
    return found == totals.end() ? Totals{} : found->second;
}

struct OpenItem { const Entry* entry; Cents original, remaining; };
struct Settlement { std::deque<OpenItem> items; Cents unapplied = 0; };

class Books {
    std::map<std::string, Account> accounts;
    std::deque<Entry> entries;
    std::map<std::string, Entry*> entryIds;
    std::map<std::string, Template> templates;
    std::optional<Draft> draft;
    std::vector<CloseRecord> closes;
    int closeCount = 0, depreciationCount = 0, interestCount = 0, writeoffCount = 0;

    template<class... Parts>
    void indented(int indent, const Parts&... parts) const {
        std::cout << std::string(indent, ' ');
        bool first = true;
        ((std::cout << (first ? "" : " ") << parts, first = false), ...);
        std::cout << '\n';
    }

    template<class... Parts>
    void emit(const Parts&... parts) const { indented(0, parts...); }

    Account& account(const std::string& code, std::optional<AccountType> type = std::nullopt) {
        auto found = accounts.find(code);
        if (found == accounts.end()) throw CommandError("unknown account " + code);
        if (type && found->second.type != *type) throw CommandError("wrong type " + code + " " + label(*type));
        return found->second;
    }

    Entry& entry(const std::string& id) {
        auto found = entryIds.find(id);
        if (found == entryIds.end()) throw CommandError("unknown entry " + id);
        return *found->second;
    }

    void active(const std::vector<std::string>& codes) const {
        for (const auto& code : codes) if (!accounts.at(code).active) throw CommandError("inactive account " + code);
    }

    void activeLines(const std::vector<Line>& lines) const {
        for (const auto& line : lines) if (!accounts.at(line.code).active) throw CommandError("inactive account " + line.code);
    }

    void checkClosed(int day) const {
        if (!closes.empty() && day <= closes.back().day) throw CommandError("period closed " + dateText(day));
    }

    std::string closedText() const { return closes.empty() ? "none" : dateText(closes.back().day); }

    std::vector<std::string> ancestors(const std::string& code) const {
        std::vector<std::string> result;
        for (std::size_t length = 1; length < code.size(); ++length) {
            auto prefix = code.substr(0, length);
            if (accounts.count(prefix)) result.push_back(prefix);
        }
        return result;
    }

    std::string parent(const std::string& code) const {
        auto values = ancestors(code);
        return values.empty() ? "none" : values.back();
    }

    std::string top(const std::string& code) const {
        auto values = ancestors(code);
        return values.empty() ? code : values.front();
    }

    std::vector<const Entry*> ordered(int first = 0, int last = lastDay) const {
        std::vector<const Entry*> result;
        for (const auto& entry : entries) if (first <= entry.day && entry.day <= last) result.push_back(&entry);
        std::sort(result.begin(), result.end(), [](const Entry* a, const Entry* b) {
            return a->day == b->day ? a->sequence < b->sequence : a->day < b->day;
        });
        return result;
    }

    TotalsByCode aggregate(int first = 0, int last = lastDay, bool operating = false) const {
        TotalsByCode result;
        for (const auto& entry : entries) {
            if (entry.day < first || entry.day > last ||
                (operating && (entry.category == Category::Closing || entry.category == Category::Reopen))) continue;
            for (const auto& line : entry.lines) {
                auto& total = result[line.code];
                (line.debit ? total.debit : total.credit) += line.amount;
            }
        }
        return result;
    }

    Cents balance(const std::string& code, int day = lastDay) const {
        Cents difference = 0;
        for (const auto& entry : entries) {
            if (entry.day > day) continue;
            for (const auto& line : entry.lines) if (line.code == code) difference += line.difference();
        }
        return difference * normalSign(accounts.at(code).type);
    }

    Cents dailySum(const std::string& code, int first, int last) const {
        std::vector<Cents> changes(last - first + 1);
        Cents running = 0, sum = 0;
        int sign = normalSign(accounts.at(code).type);
        for (const auto& entry : entries) {
            if (entry.day > last) continue;
            for (const auto& line : entry.lines) {
                if (line.code != code) continue;
                Cents value = sign * line.difference();
                if (entry.day < first) running += value;
                else changes[entry.day - first] += value;
            }
        }
        for (Cents change : changes) { running += change; sum += running; }
        return sum;
    }

    Entry& post(const std::string& id, int day, Category category, const std::string& memo, const std::vector<Line>& lines) {
        entries.push_back({id, day, category, memo, lines, entries.size() + 1, std::nullopt, std::nullopt});
        Entry& posted = entries.back();
        entryIds[id] = &posted;
        return posted;
    }

    Entry& reverseEntry(Entry& original, int day, Category category, const std::string& memo) {
        auto lines = original.lines;
        for (auto& line : lines) line.debit = !line.debit;
        Entry& posted = post(original.id + "-R", day, category, memo, lines);
        original.reversedBy = posted.id;
        posted.reverses = original.id;
        return posted;
    }

    std::map<std::string, Settlement> settlements(const std::string& code, int day) const {
        std::map<std::string, Settlement> result;
        int sign = normalSign(accounts.at(code).type);
        for (const Entry* entry : ordered(0, day)) {
            for (const auto& line : entry->lines) {
                if (line.code != code || !line.partner) continue;
                auto& settled = result[*line.partner];
                Cents value = sign * line.difference();
                if (value > 0) {
                    Cents applied = std::min(value, settled.unapplied);
                    settled.unapplied -= applied;
                    if (value > applied) settled.items.push_back({entry, value, value - applied});
                } else {
                    Cents remaining = -value;
                    while (remaining > 0 && !settled.items.empty()) {
                        auto& item = settled.items.front();
                        Cents applied = std::min(remaining, item.remaining);
                        remaining -= applied;
                        item.remaining -= applied;
                        if (item.remaining == 0) settled.items.pop_front();
                    }
                    settled.unapplied += remaining;
                }
            }
        }
        return result;
    }

    void openDraft(bool journal, const std::string& key, const std::string& date, const std::string& memo) {
        if (draft) emit("DISCARD", draft->key, "lines", draft->lines.size());
        draft = Draft{journal, key, date, memo, {}};
    }

    void postDraft() {
        if (!draft) throw CommandError("no open entry");
        Draft block = std::move(*draft);
        draft.reset();
        int day = 0;
        if (block.journal) {
            if (entryIds.count(block.key)) throw CommandError("duplicate entry " + block.key);
            day = checkedDate(block.date);
            checkClosed(day);
        } else if (templates.count(block.key)) throw CommandError("duplicate template " + block.key);
        if (block.lines.size() < 2) throw CommandError("too few lines " + block.key);
        for (const auto& line : block.lines) {
            auto& found = account(line.code);
            if (block.journal && !found.active) throw CommandError("inactive account " + line.code);
            if (line.amount == 0) throw CommandError("zero amount " + line.code);
        }
        Cents debit = lineTotal(block.lines), credit = lineTotal(block.lines, false);
        if (debit != credit) throw CommandError("unbalanced " + block.key + " debit " + money(debit) + " credit " + money(credit));
        if (block.journal) {
            auto& posted = post(block.key, day, Category::Journal, block.memo, block.lines);
            emit("POST", posted.id, dateText(day), "lines", posted.lines.size(), "amount", money(debit));
        } else {
            templates.emplace(block.key, Template{block.memo, block.lines});
            emit("TEMPLATE", block.key, "lines", block.lines.size(), "amount", money(debit));
        }
    }

    void close(int day, const std::string& equity) {
        checkClosed(day);
        account(equity, AccountType::Equity);
        active({equity});
        auto totals = aggregate(0, day);
        std::vector<std::string> targets;
        for (const auto& [code, found] : accounts) {
            if (incomeType(found.type) && getTotals(totals, code).difference() != 0) targets.push_back(code);
        }
        active(targets);
        std::vector<Line> lines;
        Cents income = 0;
        for (const auto& code : targets) {
            Cents value = getTotals(totals, code).difference();
            lines.push_back({value < 0, code, value < 0 ? -value : value, std::nullopt});
            income -= value;
        }
        if (income != 0) lines.push_back({income < 0, equity, income < 0 ? -income : income, std::nullopt});
        ++closeCount;
        Entry* posted = nullptr;
        if (!lines.empty()) posted = &post("CLOSE-" + std::to_string(closeCount), day, Category::Closing, "closing", lines);
        closes.push_back({day, posted});
        if (posted) emit("CLOSE", dateText(day), "entry", posted->id, "lines", lines.size(), "net income", money(income));
        else emit("CLOSE", dateText(day), "no entry");
    }

    Cents section(const std::string& heading, const std::set<AccountType>& types, int sign,
                  const TotalsByCode& totals, std::optional<Cents> earnings = std::nullopt) const {
        std::map<std::string, std::vector<std::pair<std::string, Cents>>> groups;
        Cents total = earnings.value_or(0);
        for (const auto& [code, found] : accounts) {
            if (!types.count(found.type)) continue;
            Cents value = sign * getTotals(totals, code).difference();
            groups[top(code)].push_back({code, value});
            total += value;
        }
        indented(2, heading, money(total));
        for (const auto& [root, group] : groups) {
            bool nonzero = false;
            Cents subtotal = 0;
            for (const auto& item : group) { nonzero = nonzero || item.second != 0; subtotal += item.second; }
            if (!nonzero) continue;
            indented(4, root, accounts.at(root).name, money(subtotal));
            for (const auto& [code, value] : group) if (value != 0) indented(6, code, accounts.at(code).name, money(value));
        }
        if (earnings) indented(4, "current earnings", money(*earnings));
        return total;
    }

    void ledger(const std::string& code, int first, int last) const {
        const auto& found = accounts.at(code);
        Cents running = balance(code, first - 1), debit = 0, credit = 0;
        emit("LEDGER", code, found.name, dateText(first), dateText(last));
        indented(2, "opening", money(running));
        for (const Entry* entry : ordered(first, last)) {
            for (const auto& line : entry->lines) {
                if (line.code != code) continue;
                running += normalSign(found.type) * line.difference();
                (line.debit ? debit : credit) += line.amount;
                indented(2, dateText(entry->day), entry->id, line.side(), money(line.amount), "balance", money(running), entry->memo);
            }
        }
        int days = last - first + 1;
        indented(2, "ending", money(running), "debits", money(debit), "credits", money(credit),
                 "days", days, "average", money(dailySum(code, first, last) / days));
    }

    void agingLine(const std::string& partner, const std::array<Cents, 5>& amounts) const {
        Cents balance = amounts[0] + amounts[1] + amounts[2] + amounts[3] - amounts[4];
        indented(2, partner, "0-30", money(amounts[0]), "31-60", money(amounts[1]), "61-90", money(amounts[2]),
                 "91+", money(amounts[3]), "unapplied", money(amounts[4]), "balance", money(balance));
    }

public:
    void execute(const std::vector<std::string>& words) {
        const auto& command = words[0];
        if (command == "ACCOUNT") {
            const auto& code = words[1];
            if (accounts.count(code)) throw CommandError("duplicate account " + code);
            auto type = parseType(words[2]);
            for (const auto& [other, found] : accounts) {
                if ((startsWith(code, other) || startsWith(other, code)) && accountClass(type) != accountClass(found.type)) {
                    throw CommandError("class mismatch " + code + " " + other);
                }
            }
            accounts.emplace(code, Account{code, words[3], type});
            emit("ACCOUNT", code, label(type), words[3], "parent", parent(code));
        } else if (command == "DEACTIVATE") {
            auto& found = account(words[1]);
            if (!found.active) throw CommandError("already inactive " + found.code);
            Cents value = balance(found.code);
            if (value != 0) throw CommandError("nonzero balance " + found.code + " " + money(value));
            found.active = false;
            emit("DEACTIVATE", found.code, found.name);
        } else if (command == "JOURNAL") {
            openDraft(true, words[1], words[2], words[3]);
        } else if (command == "TEMPLATE") {
            openDraft(false, words[1], "", words[2]);
        } else if (command == "DR" || command == "CR") {
            if (!draft) throw CommandError("no open entry");
            std::optional<std::string> partner = words.size() == 4 ? std::optional<std::string>(words[3]) : std::nullopt;
            draft->lines.push_back({command == "DR", words[1], parseMoney(words[2]), partner});
        } else if (command == "POST") {
            postDraft();
        } else if (command == "DRAFT") {
            if (!draft) throw CommandError("no open entry");
            Cents debit = lineTotal(draft->lines), credit = lineTotal(draft->lines, false);
            emit("DRAFT", draft->journal ? "journal" : "template", draft->key, "lines", draft->lines.size(),
                 "debit", money(debit), "credit", money(credit), "difference", money(debit - credit));
        } else if (command == "REVERSE") {
            auto& original = entry(words[1]);
            if (original.category == Category::Reversal || original.category == Category::Closing || original.category == Category::Reopen) {
                throw CommandError("cannot reverse " + original.id);
            }
            if (original.reversedBy) throw CommandError("already reversed " + original.id);
            int day = checkedDate(words[2]);
            if (day < original.day) throw CommandError("reverse before entry " + original.id + " " + dateText(original.day));
            checkClosed(day);
            activeLines(original.lines);
            auto& posted = reverseEntry(original, day, Category::Reversal, original.memo);
            emit("REVERSE", original.id, "entry", posted.id, dateText(day), "amount", money(lineTotal(posted.lines)));
        } else if (command == "RECUR") {
            auto found = templates.find(words[1]);
            if (found == templates.end()) throw CommandError("unknown template " + words[1]);
            int day = checkedDate(words[2]), count = std::stoi(words[3]);
            if (count == 0) throw CommandError("invalid count");
            checkClosed(day);
            auto& model = found->second;
            activeLines(model.lines);
            emit("RECUR", words[1], "count", count);
            for (int month = 0; month < count; ++month) {
                auto& posted = post(words[1] + "-" + std::to_string(++model.uses), monthsAfter(day, month), Category::Recurring, model.memo, model.lines);
                indented(2, "POST", posted.id, dateText(posted.day), "lines", posted.lines.size(), "amount", money(lineTotal(posted.lines)));
            }
        } else if (command == "DEPRECIATE") {
            int day = checkedDate(words[1]);
            checkClosed(day);
            account(words[2], AccountType::Asset);
            account(words[3], AccountType::ContraAsset);
            account(words[4], AccountType::Expense);
            active({words[3], words[4]});
            Cents cost = balance(words[2], day), accumulated = balance(words[3], day);
            Cents amount = cost > 0 ? std::min(cost / std::stoi(words[5]), cost - accumulated) : 0;
            if (amount <= 0) throw CommandError("nothing to depreciate " + words[2]);
            auto& posted = post("DEP-" + std::to_string(++depreciationCount), day, Category::Depreciation, "depreciation",
                                {{true, words[4], amount, std::nullopt}, {false, words[3], amount, std::nullopt}});
            emit("DEPRECIATE", words[2], "entry", posted.id, dateText(day), "amount", money(amount),
                 "accumulated", money(accumulated + amount), "book", money(cost - accumulated - amount));
        } else if (command == "INTEREST") {
            auto& found = account(words[1]);
            if (found.type != AccountType::Asset && found.type != AccountType::Liability) throw CommandError("not interest bearing " + found.code);
            account(words[2], found.type == AccountType::Asset ? AccountType::Revenue : AccountType::Expense);
            auto [first, last] = checkedRange(words[3], words[4]);
            checkClosed(last);
            active({words[1], words[2]});
            Cents sum = dailySum(found.code, first, last), amount = sum * std::stoi(words[5]) / 3650000;
            if (amount <= 0) throw CommandError("no interest " + found.code);
            bool asset = found.type == AccountType::Asset;
            auto& posted = post("INT-" + std::to_string(++interestCount), last, Category::Interest, "interest",
                                {{true, asset ? words[1] : words[2], amount, std::nullopt},
                                 {false, asset ? words[2] : words[1], amount, std::nullopt}});
            int days = last - first + 1;
            emit("INTEREST", found.code, "entry", posted.id, dateText(last), "days", days, "average", money(sum / days), "amount", money(amount));
        } else if (command == "WRITEOFF") {
            int day = checkedDate(words[1]);
            checkClosed(day);
            account(words[2], AccountType::Asset);
            account(words[3], AccountType::Expense);
            active({words[2], words[3]});
            int age = std::stoi(words[4]);
            std::map<std::string, Cents> targets;
            Cents total = 0;
            for (const auto& [partner, settled] : settlements(words[2], day)) {
                Cents amount = 0;
                for (const auto& item : settled.items) if (day - item.entry->day > age) amount += item.remaining;
                if (amount > 0) { targets[partner] = amount; total += amount; }
            }
            if (total == 0) throw CommandError("nothing to write off " + words[2]);
            std::vector<Line> lines = {{true, words[3], total, std::nullopt}};
            for (const auto& [partner, amount] : targets) lines.push_back({false, words[2], amount, partner});
            auto& posted = post("WO-" + std::to_string(++writeoffCount), day, Category::Writeoff, "writeoff", lines);
            emit("WRITEOFF", words[2], "entry", posted.id, dateText(day), "partners", targets.size(), "amount", money(total));
            for (const auto& [partner, amount] : targets) indented(2, partner, money(amount));
        } else if (command == "CLOSE") {
            close(checkedDate(words[1]), words[2]);
        } else if (command == "REOPEN") {
            if (closes.empty()) throw CommandError("nothing to reopen");
            auto record = closes.back();
            std::string result = "no entry";
            if (record.entry) {
                activeLines(record.entry->lines);
                result = "entry " + reverseEntry(*record.entry, record.day, Category::Reopen, "reopen").id;
            }
            closes.pop_back();
            emit("REOPEN", dateText(record.day), result, "closed", closedText());
        } else if (command == "LEDGER") {
            account(words[1]);
            auto [first, last] = checkedRange(words[2], words[3]);
            ledger(words[1], first, last);
        } else if (command == "ACTIVITY") {
            auto& found = account(words[1]);
            int year = std::stoi(words[2]);
            Cents debit = 0, credit = 0;
            emit("ACTIVITY", found.code, found.name, year);
            for (int month = 1; month <= 12; ++month) {
                int first = dayNumber(year, month, 1), last = dayNumber(year, month, monthLength(year, month));
                auto total = getTotals(aggregate(first, last), found.code);
                debit += total.debit;
                credit += total.credit;
                indented(2, padded(year, 4) + "-" + padded(month), "debit", money(total.debit), "credit", money(total.credit), "balance", money(balance(found.code, last)));
            }
            indented(2, "total debit", money(debit), "credit", money(credit));
        } else if (command == "TRIAL") {
            int day = checkedDate(words[1]);
            auto totals = aggregate(0, day);
            Cents debit = 0, credit = 0;
            emit("TRIAL", dateText(day));
            for (const auto& [code, found] : accounts) {
                Cents value = getTotals(totals, code).difference();
                if (value == 0) continue;
                if (value > 0) debit += value; else credit -= value;
                indented(2, code, found.name, value > 0 ? "debit" : "credit", money(value > 0 ? value : -value));
            }
            indented(2, "total debit", money(debit), "credit", money(credit));
        } else if (command == "INCOME") {
            auto [first, last] = checkedRange(words[1], words[2]);
            auto totals = aggregate(first, last, true);
            emit("INCOME", dateText(first), dateText(last));
            Cents revenue = section("REVENUE", {AccountType::Revenue}, -1, totals);
            Cents expense = section("EXPENSE", {AccountType::Expense}, 1, totals);
            indented(2, "NET INCOME", money(revenue - expense));
        } else if (command == "BALANCE") {
            int day = checkedDate(words[1]);
            auto totals = aggregate(0, day);
            Cents earnings = 0;
            for (const auto& [code, found] : accounts) if (incomeType(found.type)) earnings -= getTotals(totals, code).difference();
            emit("BALANCE", dateText(day));
            Cents assets = section("ASSETS", {AccountType::Asset, AccountType::ContraAsset}, 1, totals);
            Cents liabilities = section("LIABILITIES", {AccountType::Liability}, -1, totals);
            Cents equity = section("EQUITY", {AccountType::Equity}, -1, totals, earnings);
            if (assets == liabilities + equity) indented(2, "check ok");
            else indented(2, "check mismatch", money(assets - liabilities - equity));
        } else if (command == "ROLLUP") {
            int day = checkedDate(words[2]);
            std::vector<std::string> targets;
            for (const auto& [code, found] : accounts) if (startsWith(code, words[1])) targets.push_back(code);
            emit("ROLLUP", words[1], dateText(day));
            if (targets.empty()) { indented(2, "(none)"); return; }
            auto totals = aggregate(0, day);
            Cents debit = 0, credit = 0;
            for (const auto& code : targets) {
                int depth = 0;
                Cents subtotal = 0;
                for (const auto& other : targets) {
                    if (other != code && startsWith(code, other)) ++depth;
                    if (startsWith(other, code)) subtotal += getTotals(totals, other).difference();
                }
                auto own = getTotals(totals, code);
                int sign = normalSign(accounts.at(code).type);
                indented(2 * (1 + depth), code, accounts.at(code).name, "own", money(sign * own.difference()), "total", money(sign * subtotal));
                debit += own.debit;
                credit += own.credit;
            }
            indented(2, "postings debit", money(debit), "credit", money(credit));
        } else if (command == "AGING") {
            auto& found = account(words[1]);
            int day = checkedDate(words[2]);
            emit("AGING", found.code, found.name, dateText(day));
            std::array<Cents, 5> totals{};
            for (const auto& [partner, settled] : settlements(found.code, day)) {
                if (settled.items.empty() && settled.unapplied == 0) continue;
                std::array<Cents, 5> amounts{};
                amounts[4] = settled.unapplied;
                for (const auto& item : settled.items) {
                    int age = day - item.entry->day;
                    amounts[age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3] += item.remaining;
                }
                agingLine(partner, amounts);
                for (std::size_t i = 0; i < amounts.size(); ++i) totals[i] += amounts[i];
            }
            agingLine("total", totals);
        } else if (command == "ITEMS") {
            auto& found = account(words[1]);
            int day = checkedDate(words[3]);
            auto groups = settlements(found.code, day);
            const auto& settled = groups[words[2]];
            emit("ITEMS", found.code, found.name, words[2], dateText(day));
            Cents balance = -settled.unapplied;
            for (const auto& item : settled.items) {
                indented(2, dateText(item.entry->day), item.entry->id, "amount", money(item.original), "open", money(item.remaining), "age", day - item.entry->day);
                balance += item.remaining;
            }
            indented(2, "unapplied", money(settled.unapplied), "balance", money(balance));
        } else if (command == "ENTRY") {
            auto& found = entry(words[1]);
            emit("ENTRY", found.id, dateText(found.day), label(found.category), found.memo);
            for (const auto& line : found.lines) {
                std::string suffix = line.partner ? " " + *line.partner : "";
                indented(2, line.side(), line.code, accounts.at(line.code).name, money(line.amount) + suffix);
            }
            indented(2, "total", money(lineTotal(found.lines)));
            if (found.reverses) indented(2, "reverses", *found.reverses);
            if (found.reversedBy) indented(2, "reversed by", *found.reversedBy);
        } else if (command == "DAYBOOK") {
            auto [first, last] = checkedRange(words[1], words[2]);
            auto selected = ordered(first, last);
            Cents total = 0;
            emit("DAYBOOK", dateText(first), dateText(last));
            for (const Entry* entry : selected) {
                Cents amount = lineTotal(entry->lines);
                indented(2, dateText(entry->day), entry->id, label(entry->category), money(amount), entry->memo);
                total += amount;
            }
            indented(2, "total entries", selected.size(), "amount", money(total));
        } else if (command == "ACCOUNTS") {
            auto totals = aggregate();
            emit("ACCOUNTS");
            for (const auto& [code, found] : accounts) {
                indented(2, code, label(found.type), found.name, "parent", parent(code), "balance",
                         money(normalSign(found.type) * getTotals(totals, code).difference()), found.active ? "active" : "inactive");
            }
            if (accounts.empty()) indented(2, "(none)");
        } else if (command == "TEMPLATES") {
            emit("TEMPLATES");
            for (const auto& [name, model] : templates) {
                indented(2, name, model.memo, "lines", model.lines.size(), "amount", money(lineTotal(model.lines)), "used", model.uses);
            }
            if (templates.empty()) indented(2, "(none)");
        } else if (command == "STATUS") {
            auto inactive = std::count_if(accounts.begin(), accounts.end(), [](const auto& pair) { return !pair.second.active; });
            emit("STATUS accounts", accounts.size(), "inactive", inactive, "entries", entries.size(),
                 "templates", templates.size(), "closed", closedText(), "open", draft ? draft->key : "none");
        }
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int count;
    std::cin >> count;
    std::string text;
    std::getline(std::cin, text);
    Books books;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, text);
        std::istringstream input(text);
        std::vector<std::string> words;
        for (std::string word; input >> word;) words.push_back(word);
        try {
            books.execute(words);
        } catch (const CommandError& error) {
            std::cout << "ERROR " << error.what() << '\n';
        }
    }
}
