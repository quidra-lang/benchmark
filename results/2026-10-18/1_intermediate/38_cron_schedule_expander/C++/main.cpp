#include <algorithm>
#include <array>
#include <iostream>
#include <iterator>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using namespace std;

const array<string, 7> weekdays = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};
const array<string, 12> months = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"};
const array<string, 5> fieldNames = {"minute", "hour", "day-of-month", "month", "day-of-week"};
const array<pair<int, int>, 5> limits = {{{0, 59}, {0, 23}, {1, 31}, {1, 12}, {0, 7}}};
const map<string, string> macros = {
    {"@yearly", "0 0 1 1 *"}, {"@annually", "0 0 1 1 *"}, {"@monthly", "0 0 1 * *"},
    {"@weekly", "0 0 * * 0"}, {"@daily", "0 0 * * *"}, {"@midnight", "0 0 * * *"}, {"@hourly", "0 * * * *"}
};
struct CommandError : runtime_error { using runtime_error::runtime_error; };
[[noreturn]] void fail(const string& reason) { throw CommandError(reason); }
string pad(int value) { return (value < 10 ? "0" : "") + to_string(value); }
bool digits(const string& text, size_t minimum, size_t maximum) {
    return text.size() >= minimum && text.size() <= maximum &&
        all_of(text.begin(), text.end(), [](char ch) { return ch >= '0' && ch <= '9'; });
}
vector<string> words(const string& line) {
    istringstream input(line);
    vector<string> result;
    for (string word; input >> word;) result.push_back(word);
    return result;
}
vector<string> split(const string& text, char separator) {
    vector<string> result;
    size_t start = 0;
    for (;;) {
        const size_t end = text.find(separator, start);
        result.push_back(text.substr(start, end == string::npos ? end : end - start));
        if (end == string::npos) return result;
        start = end + 1;
    }
}
string join(const vector<string>& parts, const string& separator = " ") {
    string result;
    for (const auto& part : parts) { if (!result.empty()) result += separator; result += part; }
    return result;
}
bool leap(int year) { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0); }
int monthLength(int year, int month) {
    static const array<int, 12> lengths = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return lengths[month - 1] + (month == 2 && leap(year));
}
int leapCount(int year) { return year / 4 - year / 100 + year / 400; }
int yearStart(int year) { return 365 * (year - 2000) + leapCount(year - 1) - leapCount(1999); }
int dayNumber(int year, int month, int day) {
    int result = yearStart(year) + day - 1;
    for (int index = 1; index < month; ++index) result += monthLength(year, index);
    return result;
}
struct CivilDate { int number, year, month, day, weekday, length; };
CivilDate civil(int number) {
    int year = 2000 + number / 366;
    while (yearStart(year + 1) <= number) ++year;
    int remaining = number - yearStart(year), month = 1;
    while (remaining >= monthLength(year, month)) remaining -= monthLength(year, month++);
    return {number, year, month, remaining + 1, (number + 6) % 7, monthLength(year, month)};
}
string dateText(const CivilDate& date) { return to_string(date.year) + "-" + pad(date.month) + "-" + pad(date.day); }
string timeText(int minute) { return pad(minute / 60) + ":" + pad(minute % 60); }
string dateNotation(int day) { const auto date = civil(day); return dateText(date) + " " + weekdays[date.weekday].substr(0, 3); }
string datetimeNotation(int minute) {
    const auto date = civil(minute / 1440);
    return dateText(date) + " " + timeText(minute % 1440) + " " + weekdays[date.weekday].substr(0, 3);
}
string spanText(int minutes) { return to_string(minutes / 1440) + "d" + pad(minutes % 1440 / 60) + "h" + pad(minutes % 60) + "m"; }
int parseDate(const string& text, const string& reason = "invalid date") {
    if (text.size() != 10 || text[4] != '-' || text[7] != '-' || !digits(text.substr(0, 4), 4, 4) ||
        !digits(text.substr(5, 2), 2, 2) || !digits(text.substr(8), 2, 2)) fail(reason);
    const int year = stoi(text.substr(0, 4)), month = stoi(text.substr(5, 2)), day = stoi(text.substr(8));
    if (year < 2001 || year > 2098 || month < 1 || month > 12 || day < 1 || day > monthLength(year, month)) fail(reason);
    return dayNumber(year, month, day);
}
int parseDatetime(const string& date, const string& time) {
    const int day = parseDate(date, "invalid datetime");
    if (time.size() != 5 || time[2] != ':' || !digits(time.substr(0, 2), 2, 2) || !digits(time.substr(3), 2, 2)) fail("invalid datetime");
    const int hour = stoi(time.substr(0, 2)), minute = stoi(time.substr(3));
    if (hour > 23 || minute > 59) fail("invalid datetime");
    return day * 1440 + hour * 60 + minute;
}
pair<int, int> parseMonth(const string& text) {
    if (text.size() != 7 || text[4] != '-' || !digits(text.substr(0, 4), 4, 4) || !digits(text.substr(5), 2, 2)) fail("invalid month");
    const int year = stoi(text.substr(0, 4)), month = stoi(text.substr(5));
    if (year < 2001 || year > 2098 || month < 1 || month > 12) fail("invalid month");
    return {year, month};
}
int boundedNumber(const string& text, size_t length, int maximum, const string& reason) {
    if (!digits(text, 1, length) || text.front() == '0' || stoi(text) > maximum) fail(reason);
    return stoi(text);
}

enum class SpecialKind { LastDay, LastWeekday, BeforeLast, NearestWeekday, NthWeekday, LastOccurrence };
struct Special { SpecialKind kind; string text; int number = 0, weekday = 0; };
struct Field {
    set<int> values;
    vector<Special> specials;
    bool unrestricted = false;

    Field() = default;
    Field(const string& text, int index) : unrestricted(text.front() == '*') {
        const auto [minimum, maximum] = limits[index];
        const auto error = [&](const string& reason) { fail(fieldNames[index] + " " + reason); };
        const auto natural = [&](const string& text, int low, int high) {
            if (!digits(text, 1, 2)) error("invalid value");
            const int number = stoi(text);
            if (number < low || number > high) error("out of range");
            return number;
        };
        const auto value = [&](const string& text) {
            if (index == 3 || index == 4) {
                const int count = index == 3 ? 12 : 7;
                for (int i = 0; i < count; ++i) {
                    string name = (index == 3 ? months[i] : weekdays[i]).substr(0, 3);
                    for (char& ch : name) if (ch >= 'a' && ch <= 'z') ch -= 'a' - 'A';
                    if (text == name) return i + (index == 3);
                }
            }
            return natural(text, minimum, maximum);
        };
        const auto special = [&](SpecialKind kind, string canonical, int number = 0, int weekday = 0) {
            if (none_of(specials.begin(), specials.end(), [&](const Special& item) { return item.text == canonical; }))
                specials.push_back({kind, move(canonical), number, weekday});
        };
        for (const string& item : split(text, ',')) {
            if (item.empty()) error("empty item");
            if (index == 2 && (item.front() == 'L' || item.back() == 'W')) {
                if (item == "L") special(SpecialKind::LastDay, "L");
                else if (item == "LW") special(SpecialKind::LastWeekday, "LW");
                else if (item.rfind("L-", 0) == 0) {
                    const int number = natural(item.substr(2), 1, 30);
                    special(SpecialKind::BeforeLast, "L-" + to_string(number), number);
                } else if (item.back() == 'W') {
                    const int number = natural(item.substr(0, item.size() - 1), 1, 31);
                    special(SpecialKind::NearestWeekday, to_string(number) + "W", number);
                } else error("invalid value");
                continue;
            }
            const size_t hash = item.find('#');
            if (index == 4 && hash != string::npos) {
                const int weekday = value(item.substr(0, hash)) % 7;
                const string part = item.substr(hash + 1);
                if (!digits(part, 1, 1)) error("invalid value");
                const int number = stoi(part);
                if (number < 1 || number > 5) error("out of range");
                special(SpecialKind::NthWeekday, to_string(weekday) + "#" + to_string(number), number, weekday);
                continue;
            }
            if (index == 4 && item.size() >= 2 && item.back() == 'L') {
                const int weekday = value(item.substr(0, item.size() - 1)) % 7;
                special(SpecialKind::LastOccurrence, to_string(weekday) + "L", 0, weekday);
                continue;
            }
            const size_t slash = item.find('/');
            const string base = item.substr(0, slash);
            int first, last, step = 1;
            if (base == "*") { first = minimum; last = maximum; }
            else if (const size_t dash = base.find('-'); dash != string::npos) {
                first = value(base.substr(0, dash)); last = value(base.substr(dash + 1));
                if (first > last) error("invalid range");
            } else { first = value(base); last = slash == string::npos ? first : maximum; }
            if (slash != string::npos) {
                const string part = item.substr(slash + 1);
                if (!digits(part, 1, 2) || stoi(part) < 1) error("invalid step");
                step = stoi(part);
            }
            for (int number = first; number <= last; number += step) values.insert(index == 4 ? number % 7 : number);
        }
    }
};

struct Cron {
    string original, expanded;
    array<Field, 5> fields;
    vector<int> times;
    bool useOr;

    explicit Cron(vector<string> tokens) : original(join(tokens)) {
        if (tokens.size() == 1 && tokens[0].front() == '@') {
            const auto found = macros.find(tokens[0]);
            if (found == macros.end()) fail("unknown macro");
            tokens = words(found->second);
        }
        if (tokens.size() != 5) fail("field count");
        expanded = join(tokens);
        for (int index = 0; index < 5; ++index) fields[index] = Field(tokens[index], index);
        useOr = !fields[2].unrestricted && !fields[4].unrestricted;
        for (int hour : fields[1].values) for (int minute : fields[0].values) times.push_back(hour * 60 + minute);
    }
    pair<bool, bool> days(const CivilDate& date) const {
        const auto nearest = [&](int day) {
            const int weekday = (date.number - date.day + day + 6) % 7;
            if (weekday == 6) return day == 1 ? 3 : day - 1;
            if (weekday == 0) return day == date.length ? day - 2 : day + 1;
            return day;
        };
        bool dom = fields[2].values.count(date.day), dow = fields[4].values.count(date.weekday);
        for (const auto& item : fields[2].specials) {
            switch (item.kind) {
                case SpecialKind::LastDay: dom |= date.day == date.length; break;
                case SpecialKind::LastWeekday: dom |= date.day == nearest(date.length); break;
                case SpecialKind::BeforeLast: dom |= date.day == date.length - item.number; break;
                case SpecialKind::NearestWeekday: dom |= item.number <= date.length && date.day == nearest(item.number); break;
                default: break;
            }
        }
        for (const auto& item : fields[4].specials) {
            dow |= date.weekday == item.weekday && (item.kind == SpecialKind::NthWeekday ?
                (date.day - 1) / 7 + 1 == item.number : date.day + 7 > date.length);
        }
        return {dom, dow};
    }
    bool dayMatches(bool dom, bool dow) const { return useOr ? dom || dow : dom && dow; }
    bool scheduled(const CivilDate& date) const {
        const auto [dom, dow] = days(date);
        return fields[3].values.count(date.month) && dayMatches(dom, dow);
    }
    vector<string> reasons(int minute, const set<int>& holidays) const {
        const auto date = civil(minute / 1440);
        const auto [dom, dow] = days(date);
        const bool day = dayMatches(dom, dow);
        vector<string> result;
        if (!fields[0].values.count(minute % 60)) result.push_back("minute");
        if (!fields[1].values.count(minute % 1440 / 60)) result.push_back("hour");
        if (!day && !dom) result.push_back("day-of-month");
        if (!fields[3].values.count(date.month)) result.push_back("month");
        if (!day && !dow) result.push_back("day-of-week");
        if (holidays.count(date.number)) result.push_back("excluded");
        return result;
    }
    template<class Visitor>
    void eachFire(int low, int high, const set<int>& holidays, Visitor visit, bool reverse = false) const {
        const int first = low / 1440, last = high / 1440, step = reverse ? -1 : 1;
        for (int day = reverse ? last : first; reverse ? day >= first : day <= last; day += step) {
            if (holidays.count(day) || !scheduled(civil(day))) continue;
            for (size_t index = 0; index < times.size(); ++index) {
                const int minute = 1440 * day + times[reverse ? times.size() - 1 - index : index];
                if (low <= minute && minute <= high && !visit(minute)) return;
            }
        }
    }
};

string naturalList(vector<string> parts, const string& conjunction = "and") {
    if (parts.empty()) return "";
    if (parts.size() == 1) return parts[0];
    const string last = parts.back();
    parts.pop_back();
    return join(parts, ", ") + " " + conjunction + " " + last;
}
string valueList(const set<int>& values, int index, const string& conjunction = "and") {
    const auto label = [&](int value) { return index == 3 ? months[value - 1] : index == 4 ? weekdays[value] : to_string(value); };
    const vector<int> ordered(values.begin(), values.end());
    vector<string> parts;
    for (size_t first = 0; first < ordered.size();) {
        size_t end = first + 1;
        while (end < ordered.size() && ordered[end] == ordered[end - 1] + 1) ++end;
        if (end - first >= 3) parts.push_back(label(ordered[first]) + " through " + label(ordered[end - 1]));
        else for (size_t i = first; i < end; ++i) parts.push_back(label(ordered[i]));
        first = end;
    }
    return naturalList(move(parts), conjunction);
}
optional<int> stepped(const set<int>& values, int maximum) {
    if (values.size() < 2 || *values.begin() != 0) return nullopt;
    const int step = *next(values.begin());
    if (step < 2 || values.size() != static_cast<size_t>(maximum / step + 1)) return nullopt;
    int expected = 0;
    for (int value : values) { if (value != expected) return nullopt; expected += step; }
    return step;
}
string description(const Cron& cron) {
    const auto& minutes = cron.fields[0].values;
    const auto& hours = cron.fields[1].values;
    const auto& dom = cron.fields[2];
    const auto& month = cron.fields[3].values;
    const auto& dow = cron.fields[4];
    string time;
    if (cron.times.size() <= 4) {
        vector<string> parts;
        for (int minute : cron.times) parts.push_back(timeText(minute));
        time = "At " + naturalList(move(parts));
    } else {
        const auto minuteStep = stepped(minutes, 59), hourStep = stepped(hours, 23);
        if (minutes.size() == 60) time = "Every minute";
        else if (minuteStep) time = "Every " + to_string(*minuteStep) + " minutes";
        else if (minutes.size() == 1) time = "At minute " + to_string(*minutes.begin());
        else time = "At minutes " + valueList(minutes, 0);
        if (hours.size() == 24) { if (time.rfind("At minute", 0) == 0) time += " of every hour"; }
        else if (hourStep) time += ", every " + to_string(*hourStep) + " hours";
        else if (*hours.rbegin() - *hours.begin() + 1 == static_cast<int>(hours.size()))
            time += ", between " + pad(*hours.begin()) + ":00 and " + pad(*hours.rbegin()) + ":59";
        else time += ", during hours " + valueList(hours, 1);
    }
    vector<string> domParts;
    if (!dom.values.empty()) domParts.push_back(dom.values.size() == 1 ? "day " + to_string(*dom.values.begin()) : "days " + valueList(dom.values, 2));
    for (const auto& item : dom.specials) {
        switch (item.kind) {
            case SpecialKind::LastDay: domParts.push_back("the last day"); break;
            case SpecialKind::LastWeekday: domParts.push_back("the last weekday"); break;
            case SpecialKind::BeforeLast:
                domParts.push_back(to_string(item.number) + (item.number == 1 ? " day" : " days") + " before the last day"); break;
            case SpecialKind::NearestWeekday: domParts.push_back("the weekday nearest day " + to_string(item.number)); break;
            default: break;
        }
    }
    const string domClause = naturalList(move(domParts)) + " of the month";
    const auto dowClause = [&](const string& conjunction = "and") {
        static const array<string, 5> ordinals = {"1st", "2nd", "3rd", "4th", "5th"};
        vector<string> parts;
        if (!dow.values.empty()) parts.push_back(valueList(dow.values, 4, conjunction));
        for (const auto& item : dow.specials) {
            const string occurrence = item.kind == SpecialKind::NthWeekday ? ordinals[item.number - 1] : "last";
            parts.push_back("the " + occurrence + " " + weekdays[item.weekday]);
        }
        return naturalList(move(parts), conjunction) + (dow.specials.empty() ? "" : " of the month");
    };
    const bool domFull = dom.values.size() == 31, dowFull = dow.values.size() == 7;
    string day;
    if (cron.useOr) {
        if (!domFull && !dowFull) day = ", on " + domClause + " or on " + dowClause();
    } else if (!domFull && !dowFull) day = ", on " + domClause + " if it is " + dowClause("or");
    else if (!domFull) day = ", on " + domClause;
    else if (!dowFull) day = ", on " + dowClause();
    return time + day + (month.size() == 12 ? "" : ", in " + valueList(month, 3));
}

enum class Policy { Allow, Forbid, Replace };
string policyText(Policy policy) {
    return policy == Policy::Allow ? "ALLOW" : policy == Policy::Forbid ? "FORBID" : "REPLACE";
}
Policy parsePolicy(const string& text) {
    if (text == "ALLOW") return Policy::Allow;
    if (text == "FORBID") return Policy::Forbid;
    if (text == "REPLACE") return Policy::Replace;
    fail("invalid policy");
}
struct Job {
    string id;
    Cron cron;
    bool enabled = true;
    int duration = 1;
    Policy policy = Policy::Allow;
};
class Scheduler {
    map<string, Job> jobs;
    set<int> holidays;

    void newId(const string& id) const {
        if (id.empty() || id.size() > 16 || id[0] < 'a' || id[0] > 'z' ||
            !all_of(id.begin(), id.end(), [](char ch) { return (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_'; })) fail("invalid id");
        if (jobs.count(id)) fail("duplicate job");
    }
    Job& existing(const string& id) {
        const auto found = jobs.find(id);
        if (found == jobs.end()) fail("unknown job");
        return found->second;
    }
    pair<int, int> window(const vector<string>& args, size_t start) const {
        const int low = parseDatetime(args[start], args[start + 1]);
        const int high = parseDatetime(args[start + 2], args[start + 3]);
        if (low > high) fail("invalid window");
        if (high - low > 44640) fail("window too long");
        return {low, high};
    }
    vector<int> fireTimes(const Job& job, int low, int high, int limit = 0, bool reverse = false) const {
        vector<int> result;
        job.cron.eachFire(low, high, holidays, [&](int minute) {
            result.push_back(minute);
            return limit == 0 || result.size() < static_cast<size_t>(limit);
        }, reverse);
        return result;
    }
    map<int, vector<string>> grouped(int low, int high) const {
        map<int, vector<string>> groups;
        for (const auto& [id, job] : jobs) if (job.enabled) {
            job.cron.eachFire(low, high, holidays, [&](int minute) { groups[minute].push_back(id); return true; });
        }
        return groups;
    }
    vector<string> simulate(int low, int high) const {
        map<int, int> events;
        vector<string> rows;
        for (const auto& [id, job] : jobs) if (job.enabled) {
            optional<int> lastEnd;
            int started = 0, skipped = 0, replaced = 0, busy = 0;
            job.cron.eachFire(low, high, holidays, [&](int minute) {
                if (lastEnd && *lastEnd > minute) {
                    if (job.policy == Policy::Forbid) { ++skipped; return true; }
                    if (job.policy == Policy::Replace) {
                        ++events[*lastEnd]; --events[minute];
                        busy -= *lastEnd - minute;
                        ++replaced;
                    }
                }
                lastEnd = minute + job.duration;
                ++events[minute]; --events[*lastEnd];
                busy += job.duration;
                ++started;
                return true;
            });
            rows.push_back(id + " " + policyText(job.policy) + " started " + to_string(started) + " skipped " + to_string(skipped) +
                " replaced " + to_string(replaced) + " busy " + to_string(busy));
        }
        int running = 0, peak = 0, earliest = 0;
        for (const auto& [minute, difference] : events) {
            running += difference;
            if (running > peak) { peak = running; earliest = minute; }
        }
        rows.insert(rows.begin(), "SIMULATE " + to_string(rows.size()) + " peak " + to_string(peak) +
            (peak ? " at " + datetimeNotation(earliest) : ""));
        return rows;
    }
    vector<string> week(int first, const string& text) const {
        vector<string> rows;
        int total = 0;
        for (int day = first; day < first + 7; ++day) {
            array<int, 24> hours{};
            const auto date = civil(day);
            if (!holidays.count(day)) for (const auto& [id, job] : jobs) if (job.enabled && job.cron.scheduled(date)) {
                for (int hour : job.cron.fields[1].values) hours[hour] += static_cast<int>(job.cron.fields[0].values.size());
            }
            int count = 0;
            string cells;
            for (int value : hours) { count += value; cells += value == 0 ? '.' : value < 10 ? static_cast<char>('0' + value) : '+'; }
            total += count;
            rows.push_back(dateNotation(day) + " " + cells + " " + to_string(count));
        }
        rows.insert(rows.begin(), "WEEK " + text + " " + to_string(total));
        return rows;
    }
    vector<string> calendar(const Job& job, int year, int month, const string& text) const {
        const int first = dayNumber(year, month, 1), length = monthLength(year, month);
        vector<string> cells((first + 6) % 7, "...");
        int active = 0;
        for (int day = 1; day <= length; ++day) {
            const int number = first + day - 1;
            const char mark = !job.cron.scheduled(civil(number)) ? '-' : holidays.count(number) ? 'x' : '*';
            if (mark == '*') ++active;
            cells.push_back(pad(day) + mark);
        }
        while (cells.size() % 7) cells.push_back("...");
        vector<string> rows = {"CALENDAR " + job.id + " " + text + " days " + to_string(active) + " runs " +
            to_string(active * static_cast<int>(job.cron.times.size())), "Sun Mon Tue Wed Thu Fri Sat"};
        for (size_t index = 0; index < cells.size(); index += 7)
            rows.push_back(join(vector<string>(cells.begin() + index, cells.begin() + index + 7)));
        return rows;
    }
    vector<string> gap(const Job& job, int base) const {
        const auto times = fireTimes(job, base, base + 44640);
        const string prefix = "GAP " + job.id + " runs " + to_string(times.size());
        if (times.size() < 2) return {prefix + " none"};
        map<int, int> counts;
        int shortest = times[1] - times[0], longest = shortest;
        size_t from = 0;
        for (size_t index = 1; index < times.size(); ++index) {
            const int difference = times[index] - times[index - 1];
            ++counts[difference]; shortest = min(shortest, difference);
            if (difference > longest) { longest = difference; from = index - 1; }
        }
        vector<string> rows = {prefix + " shortest " + spanText(shortest) + " longest " + spanText(longest) + " from " +
            datetimeNotation(times[from]) + " to " + datetimeNotation(times[from + 1])};
        for (const auto& [difference, count] : counts) rows.push_back(spanText(difference) + " " + to_string(count));
        return rows;
    }

public:
    vector<string> execute(const string& line);
};

vector<string> Scheduler::execute(const string& line) {
    const auto tokens = words(line);
    const string& command = tokens[0];
    const vector<string> args(tokens.begin() + 1, tokens.end());
    static const map<string, size_t> counts = {
        {"REMOVE", 1}, {"RENAME", 2}, {"ENABLE", 1}, {"DISABLE", 1}, {"RUNTIME", 3}, {"LIST", 0},
        {"EXPAND", 2}, {"DESCRIBE", 1}, {"MATCH", 3}, {"NEXT", 4}, {"PREV", 4}, {"COUNT", 5},
        {"GAP", 3}, {"OVERLAP", 6}, {"TIMELINE", 4}, {"CONFLICTS", 4}, {"WEEK", 1},
        {"CALENDAR", 2}, {"SIMULATE", 4}, {"EXCLUDE", 1}, {"INCLUDE", 1}, {"HOLIDAYS", 0}
    };
    if (command == "JOB" || command == "VALIDATE") {
        if (args.size() < (command == "JOB" ? 2U : 1U)) fail("wrong arguments");
        if (command == "VALIDATE") {
            const Cron cron(args);
            return {"VALID " + cron.expanded + (cron.useOr ? " OR " : " AND ") + to_string(cron.times.size())};
        }
        const string& id = args[0];
        newId(id);
        Cron cron(vector<string>(args.begin() + 1, args.end()));
        jobs.emplace(id, Job{id, move(cron)});
        return {"JOB " + id + " added"};
    }
    const auto expected = counts.find(command);
    if (expected == counts.end()) fail("unknown command");
    if (args.size() != expected->second) fail("wrong arguments");
    if (command == "LIST") {
        vector<string> rows = {"LIST " + to_string(jobs.size())};
        for (const auto& [id, job] : jobs) rows.push_back(id + (job.enabled ? " on " : " off ") + to_string(job.duration) + " " + policyText(job.policy) + " " + job.cron.original);
        return rows;
    }
    if (command == "HOLIDAYS") {
        vector<string> rows = {"HOLIDAYS " + to_string(holidays.size())};
        for (int day : holidays) rows.push_back(dateNotation(day));
        return rows;
    }
    if (command == "EXCLUDE" || command == "INCLUDE") {
        const int day = parseDate(args[0]);
        const bool exclude = command == "EXCLUDE";
        if (static_cast<bool>(holidays.count(day)) == exclude) fail(exclude ? "already excluded" : "not excluded");
        if (exclude) holidays.insert(day); else holidays.erase(day);
        return {command + " " + dateNotation(day) + " holidays " + to_string(holidays.size())};
    }
    if (command == "WEEK") return week(parseDate(args[0]), args[0]);
    if (command == "TIMELINE" || command == "CONFLICTS" || command == "SIMULATE") {
        const auto [low, high] = window(args, 0);
        if (command == "SIMULATE") return simulate(low, high);
        const auto groups = grouped(low, high);
        vector<string> rows;
        int total = 0, peak = 0, shown = 0;
        for (const auto& [minute, ids] : groups) {
            if (command == "TIMELINE") {
                total += static_cast<int>(ids.size());
                for (const auto& id : ids) if (shown < 100) { rows.push_back(datetimeNotation(minute) + " " + id); ++shown; }
            } else if (ids.size() >= 2) {
                ++total; peak = max(peak, static_cast<int>(ids.size()));
                if (shown < 100) { rows.push_back(datetimeNotation(minute) + " " + to_string(ids.size()) + " " + join(ids)); ++shown; }
            }
        }
        rows.insert(rows.begin(), command + " " + to_string(total) + (command == "CONFLICTS" ? " peak " + to_string(peak) : ""));
        if (total > 100) rows.push_back("... " + to_string(total - 100) + " more");
        return rows;
    }
    Job& job = existing(args[0]);
    if (command == "REMOVE") {
        const string id = job.id;
        jobs.erase(id);
        return {"REMOVE " + id};
    }
    if (command == "RENAME") {
        newId(args[1]);
        const string old = job.id;
        auto node = jobs.extract(old);
        node.key() = args[1]; node.mapped().id = args[1];
        jobs.insert(move(node));
        return {"RENAME " + old + " " + args[1]};
    }
    if (command == "ENABLE" || command == "DISABLE") {
        const bool enabled = command == "ENABLE";
        if (job.enabled == enabled) fail(enabled ? "already enabled" : "already disabled");
        job.enabled = enabled;
        return {command + " " + job.id};
    }
    if (command == "RUNTIME") {
        const int duration = boundedNumber(args[1], 4, 1440, "invalid duration");
        const Policy policy = parsePolicy(args[2]);
        job.duration = duration; job.policy = policy;
        return {"RUNTIME " + job.id + " " + to_string(duration) + " " + policyText(policy)};
    }
    if (command == "EXPAND") {
        const auto found = find(fieldNames.begin(), fieldNames.end(), args[1]);
        if (found == fieldNames.end()) fail("invalid field");
        const auto& field = job.cron.fields[found - fieldNames.begin()];
        vector<string> parts = {"EXPAND", job.id, args[1], to_string(field.values.size())};
        for (int value : field.values) parts.push_back(to_string(value));
        for (const auto& special : field.specials) parts.push_back(special.text);
        return {join(parts)};
    }
    if (command == "DESCRIBE") return {"DESCRIBE " + job.id + " " + description(job.cron)};
    if (command == "CALENDAR") {
        const auto [year, month] = parseMonth(args[1]);
        return calendar(job, year, month, args[1]);
    }
    if (command == "OVERLAP") {
        const Job& second = existing(args[1]);
        const auto [low, high] = window(args, 2);
        const auto firstTimes = fireTimes(job, low, high), secondTimes = fireTimes(second, low, high);
        vector<int> shared;
        set_intersection(firstTimes.begin(), firstTimes.end(), secondTimes.begin(), secondTimes.end(), back_inserter(shared));
        string row = "OVERLAP " + job.id + " " + second.id + " " + to_string(shared.size());
        if (!shared.empty()) row += " first " + datetimeNotation(shared.front()) + " last " + datetimeNotation(shared.back());
        return {row};
    }
    if (command == "COUNT") {
        const auto [low, high] = window(args, 1);
        set<int> days;
        int runs = 0;
        job.cron.eachFire(low, high, holidays, [&](int minute) { ++runs; days.insert(minute / 1440); return true; });
        return {"COUNT " + job.id + " runs " + to_string(runs) + " days " + to_string(days.size())};
    }
    const int base = parseDatetime(args[1], args[2]);
    if (command == "MATCH") {
        const auto reasons = job.cron.reasons(base, holidays);
        return {"MATCH " + job.id + " " + datetimeNotation(base) + (reasons.empty() ? " yes" : " no " + join(reasons))};
    }
    if (command == "GAP") return gap(job, base);
    const int count = boundedNumber(args[3], 2, 50, "invalid count");
    const bool reverse = command == "PREV";
    const auto times = fireTimes(job, reverse ? base - 527040 : base + 1, reverse ? base - 1 : base + 527040, count, reverse);
    vector<string> rows = {command + " " + job.id + " " + to_string(times.size())};
    for (int minute : times) rows.push_back(datetimeNotation(minute) + (reverse ? " -" : " +") + spanText(reverse ? base - minute : minute - base));
    if (times.size() < static_cast<size_t>(count)) rows.push_back("NONE");
    return rows;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int count;
    cin >> count;
    string line;
    getline(cin, line);
    Scheduler scheduler;
    for (int index = 0; index < count; ++index) {
        getline(cin, line);
        try { for (const auto& row : scheduler.execute(line)) cout << row << '\n'; }
        catch (const CommandError& error) { cout << "ERROR " << error.what() << '\n'; }
    }
}
