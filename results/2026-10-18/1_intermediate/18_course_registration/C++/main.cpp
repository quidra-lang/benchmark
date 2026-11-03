#include <algorithm>
#include <array>
#include <cctype>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using namespace std;

const array<string, 7> DAYS{"MO", "TU", "WE", "TH", "FR", "SA", "SU"};
const map<char, int> GRADE_POINTS{{'A', 4}, {'B', 3}, {'C', 2}, {'D', 1}, {'F', 0}};

struct CommandError : runtime_error {
    using runtime_error::runtime_error;
};

struct ParseError : runtime_error {
    ParseError() : runtime_error("invalid prerequisite") {}
};

string time_text(int minutes) {
    ostringstream out;
    out << setfill('0') << setw(2) << minutes / 60
        << ':' << setw(2) << minutes % 60;
    return out.str();
}

string rate_text(int count, int capacity) {
    return capacity ? to_string(count * 100 / capacity) + "%" : "n/a";
}

bool course_word(const string& word) {
    static const regex pattern("[A-Z]{2,4}[0-9]{3}");
    return regex_match(word, pattern);
}

bool year_word(const string& word) {
    return word.size() == 2 && word[0] == 'Y' &&
           word[1] >= '1' && word[1] <= '9';
}

vector<string> split(const string& input, char delimiter) {
    vector<string> parts;
    istringstream stream(input);
    string part;
    while (getline(stream, part, delimiter)) parts.push_back(part);
    return parts;
}

template <typename... Args>
string words(const Args&... args) {
    ostringstream out;
    bool first = true;
    ((out << (first ? "" : " ") << args, first = false), ...);
    return out.str();
}

struct Record {
    char grade;
    int credits;
};

struct Student;

struct Expression {
    enum class Kind { Always, Word, And, Or };
    Kind kind;
    string word;
    vector<shared_ptr<Expression>> children;
    set<string> references;

    explicit Expression(Kind k) : kind(k) {}

    static shared_ptr<Expression> leaf(const string& value) {
        auto expression = make_shared<Expression>(Kind::Word);
        expression->word = value;
        if (!year_word(value)) expression->references.insert(value);
        return expression;
    }

    static shared_ptr<Expression> combine(Kind kind,
                                           const vector<shared_ptr<Expression>>& items) {
        vector<shared_ptr<Expression>> flat;
        for (const auto& item : items) {
            if (item->kind == kind) {
                flat.insert(flat.end(), item->children.begin(), item->children.end());
            } else {
                flat.push_back(item);
            }
        }
        if (flat.size() == 1) return flat.front();
        auto result = make_shared<Expression>(kind);
        result->children = move(flat);
        for (const auto& child : result->children) {
            result->references.insert(child->references.begin(), child->references.end());
        }
        return result;
    }

    string canonical() const {
        if (kind == Kind::Always) return "-";
        if (kind == Kind::Word) return word;
        string result;
        for (const auto& child : children) {
            if (!result.empty()) result += kind == Kind::And ? "&" : "|";
            string text = child->canonical();
            if (kind == Kind::And && child->kind == Kind::Or) text = "(" + text + ")";
            result += text;
        }
        return result;
    }

    bool evaluate(const Student& student) const;
};

class PrerequisiteParser {
    vector<string> tokens;
    size_t position = 0;

    string peek() const {
        return position < tokens.size() ? tokens[position] : "";
    }

    shared_ptr<Expression> factor() {
        string token = peek();
        if (token.empty() || token == "&" || token == "|" || token == ")")
            throw ParseError();
        ++position;
        if (token == "(") {
            auto inner = expression();
            if (peek() != ")") throw ParseError();
            ++position;
            return inner;
        }
        return Expression::leaf(token);
    }

    shared_ptr<Expression> term() {
        vector<shared_ptr<Expression>> parts{factor()};
        while (peek() == "&") {
            ++position;
            parts.push_back(factor());
        }
        return Expression::combine(Expression::Kind::And, parts);
    }

    shared_ptr<Expression> expression() {
        vector<shared_ptr<Expression>> parts{term()};
        while (peek() == "|") {
            ++position;
            parts.push_back(term());
        }
        return Expression::combine(Expression::Kind::Or, parts);
    }

public:
    explicit PrerequisiteParser(const string& text) {
        size_t index = 0;
        while (index < text.size()) {
            char ch = text[index];
            if (ch == '&' || ch == '|' || ch == '(' || ch == ')') {
                tokens.emplace_back(1, ch);
                ++index;
                continue;
            }
            size_t first = index;
            while (index < text.size() && isalnum(static_cast<unsigned char>(text[index])))
                ++index;
            if (first == index) throw ParseError();
            string value = text.substr(first, index - first);
            if (!course_word(value) && !year_word(value)) throw ParseError();
            tokens.push_back(move(value));
        }
    }

    shared_ptr<Expression> parse() {
        auto result = expression();
        if (position != tokens.size()) throw ParseError();
        return result;
    }
};

shared_ptr<Expression> prerequisite(const string& code, const string& text) {
    if (text == "-") return make_shared<Expression>(Expression::Kind::Always);
    shared_ptr<Expression> expression;
    try {
        expression = PrerequisiteParser(text).parse();
    } catch (const ParseError&) {
        throw CommandError("invalid prereq " + code);
    }
    if (expression->references.count(code))
        throw CommandError("self prereq " + code);
    return expression;
}

struct Slot {
    int day;
    int start;
    int end;
    string original;

    explicit Slot(const string& text) : day(-1), start(0), end(0), original(text) {
        string prefix = text.substr(0, 2);
        for (int i = 0; i < static_cast<int>(DAYS.size()); ++i) {
            if (DAYS[i] == prefix) day = i;
        }
        int start_hour = stoi(text.substr(2, 2));
        int start_minute = stoi(text.substr(4, 2));
        int end_hour = stoi(text.substr(7, 2));
        int end_minute = stoi(text.substr(9, 2));
        start = 60 * start_hour + start_minute;
        end = 60 * end_hour + end_minute;
        if (day < 0 || start_hour > 23 || end_hour > 23 ||
            start_minute > 59 || end_minute > 59 || start >= end)
            throw CommandError("invalid slot " + text);
    }

    bool overlaps(const Slot& other) const {
        return day == other.day && start < other.end && other.start < end;
    }

    string text() const { return time_text(start) + "-" + time_text(end); }
};

struct Course {
    string code;
    int credits;
    int capacity;
    vector<Slot> slots;
    shared_ptr<Expression> required;
    bool open = true;
    set<string> enrolled;
    vector<string> waitlist;
    set<string> conflicts;

    Course(string code, int credits, int capacity, vector<Slot> slots,
           shared_ptr<Expression> required)
        : code(move(code)), credits(credits), capacity(capacity),
          slots(move(slots)), required(move(required)) {}

    string status() const { return open ? "open" : "closed"; }

    int weekly() const {
        int total = 0;
        for (const Slot& slot : slots) total += slot.end - slot.start;
        return total;
    }

    string department() const { return code.substr(0, code.size() - 3); }
};

struct Student {
    string id;
    int year;
    int limit;
    map<string, Record> records;
    map<string, char> passed;
    set<string> courses;
    set<string> waiting;
    int credits = 0;
    vector<pair<int, string>> history;

    Student(string id, int year, int limit, map<string, Record> records)
        : id(move(id)), year(year), limit(limit), records(move(records)) {
        for (const auto& [code, record] : this->records) {
            if (record.grade == 'A' || record.grade == 'B' || record.grade == 'C')
                passed[code] = record.grade;
        }
    }

    int earned() const {
        int result = 0;
        for (const auto& [code, record] : records) {
            if (record.grade != 'F') result += record.credits;
        }
        return result;
    }

    string gpa() const {
        if (records.empty()) return "n/a";
        int points = 0, credits_sum = 0;
        for (const auto& [code, record] : records) {
            points += GRADE_POINTS.at(record.grade) * record.credits;
            credits_sum += record.credits;
        }
        int rounded = (200 * points + credits_sum) / (2 * credits_sum);
        ostringstream out;
        out << rounded / 100 << '.' << setfill('0') << setw(2) << rounded % 100;
        return out.str();
    }
};

bool Expression::evaluate(const Student& student) const {
    if (kind == Kind::Always) return true;
    if (kind == Kind::Word) {
        return year_word(word) ? student.year >= word[1] - '0' :
                                student.passed.count(word) != 0;
    }
    if (kind == Kind::And) {
        for (const auto& child : children) {
            if (!child->evaluate(student)) return false;
        }
        return true;
    }
    for (const auto& child : children) {
        if (child->evaluate(student)) return true;
    }
    return false;
}

struct Decision {
    string kind;
    vector<string> extra;
};

class Registrar {
    map<string, Course> courses;
    map<string, Student> students;
    int command_number = 0;
    vector<string> output;

    void emit(const string& text, bool indented = false) {
        output.push_back(indented ? "  " + text : text);
    }

    Student& student(const string& id) {
        auto it = students.find(id);
        if (it == students.end()) throw CommandError("unknown student " + id);
        return it->second;
    }

    Course& course(const string& code) {
        auto it = courses.find(code);
        if (it == courses.end()) throw CommandError("unknown course " + code);
        return it->second;
    }

    void record(Student& s, const string& event) {
        s.history.emplace_back(command_number, event);
    }

    string conflict(const Student& s, const Course& c,
                    const string& excluded = "") const {
        for (const string& code : s.courses) {
            if (code != excluded && c.conflicts.count(code)) return code;
        }
        return "";
    }

    Decision eligibility(const Student& s, const Course& c,
                         const string& excluded = "") const {
        if (!c.open) return {"course closed", {}};
        if (s.courses.count(c.code)) return {"already enrolled", {}};
        if (s.waiting.count(c.code)) return {"already waitlisted", {}};
        auto past = s.passed.find(c.code);
        if (past != s.passed.end())
            return {"already completed", {string(1, past->second)}};
        if (!c.required->evaluate(s)) return {"prereq not met", {}};
        string conflicted = conflict(s, c, excluded);
        if (!conflicted.empty()) return {"time conflict", {conflicted}};
        int credits = s.credits + c.credits;
        if (!excluded.empty()) credits -= courses.at(excluded).credits;
        if (credits > s.limit)
            return {"credit limit", {to_string(credits), to_string(s.limit)}};
        return {"OK", {}};
    }

    int wait_position(const Student& s, const Course& c) const {
        int position = 1;
        for (const string& id : c.waitlist) {
            if (students.at(id).year >= s.year) ++position;
        }
        return position;
    }

    Decision request(const Student& s, const Course& c) const {
        Decision result = eligibility(s, c);
        if (result.kind != "OK") return result;
        if (c.enrolled.size() < static_cast<size_t>(c.capacity))
            return {"enroll", {}};
        if (s.waiting.size() >= 3) return {"waitlist limit", {}};
        return {"waitlist", {to_string(wait_position(s, c))}};
    }

    static string decision_text(const Decision& decision) {
        string result = decision.kind;
        for (const string& value : decision.extra) result += " " + value;
        return result;
    }

    [[noreturn]] void fail_request(const Decision& decision,
                                   const Student& s, const Course& c) {
        string message = words(decision.kind, s.id, c.code);
        for (const string& extra : decision.extra) message += " " + extra;
        throw CommandError(message);
    }

    void enroll(Student& s, Course& c) {
        c.enrolled.insert(s.id);
        s.courses.insert(c.code);
        s.credits += c.credits;
    }

    void withdraw(Student& s, Course& c) {
        c.enrolled.erase(s.id);
        s.courses.erase(c.code);
        s.credits -= c.credits;
    }

    void unlist(Student& s, Course& c) {
        c.waitlist.erase(remove(c.waitlist.begin(), c.waitlist.end(), s.id),
                         c.waitlist.end());
        s.waiting.erase(c.code);
    }

    void promotion() {
        for (auto& [code, c] : courses) {
            if (!c.open) continue;
            vector<string> waiting = c.waitlist;
            for (const string& id : waiting) {
                if (c.enrolled.size() >= static_cast<size_t>(c.capacity)) break;
                Student& s = students.at(id);
                if (!conflict(s, c).empty() || s.credits + c.credits > s.limit) continue;
                unlist(s, c);
                enroll(s, c);
                record(s, "promote " + code);
                emit(words("PROMOTE", s.id, code, "enrolled",
                           to_string(c.enrolled.size()) + "/" + to_string(c.capacity),
                           "credits", to_string(s.credits) + "/" + to_string(s.limit)), true);
            }
        }
    }

    void cmd_course(const vector<string>& a) {
        const string& code = a[0];
        if (courses.count(code)) throw CommandError("duplicate course " + code);
        vector<Slot> slots;
        if (a[3] != "-") {
            for (const string& token : split(a[3], ',')) slots.emplace_back(token);
        }
        for (size_t i = 0; i < slots.size(); ++i) {
            for (size_t j = i + 1; j < slots.size(); ++j) {
                if (slots[i].overlaps(slots[j]))
                    throw CommandError(words("overlapping slots",
                                             slots[i].original, slots[j].original));
            }
        }
        auto required = prerequisite(code, a[4]);
        Course new_course(code, stoi(a[1]), stoi(a[2]), move(slots), required);
        for (auto& [other_code, other] : courses) {
            bool overlaps = false;
            for (const Slot& first : new_course.slots) {
                for (const Slot& second : other.slots) {
                    if (first.overlaps(second)) overlaps = true;
                }
            }
            if (overlaps) {
                new_course.conflicts.insert(other_code);
                other.conflicts.insert(code);
            }
        }
        int weekly = new_course.weekly();
        int meetings = static_cast<int>(new_course.slots.size());
        courses.emplace(code, move(new_course));
        emit(words("COURSE", code, "credits", a[1], "capacity", a[2],
                   "meetings", meetings, "weekly", time_text(weekly),
                   "prereq", required->canonical()));
    }

    void cmd_student(const vector<string>& a) {
        const string& id = a[0];
        if (students.count(id)) throw CommandError("duplicate student " + id);
        map<string, Record> records;
        if (a[3] != "-") {
            for (const string& text : split(a[3], ',')) {
                vector<string> fields = split(text, ':');
                const string& code = fields[0];
                char grade = fields[1][0];
                if (!GRADE_POINTS.count(grade))
                    throw CommandError(words("invalid grade", id, code, grade));
                if (records.count(code))
                    throw CommandError(words("duplicate record", id, code));
                records[code] = {grade, stoi(fields[2])};
            }
        }
        int count = static_cast<int>(records.size());
        Student s(id, stoi(a[1]), stoi(a[2]), move(records));
        emit(words("STUDENT", id, "year", a[1], "limit", a[2],
                   "records", count, "earned", s.earned(), "gpa", s.gpa()));
        students.emplace(id, move(s));
    }

    void cmd_enroll(const vector<string>& a) {
        Student& s = student(a[0]);
        Course& c = course(a[1]);
        Decision decision = request(s, c);
        if (decision.kind != "enroll" && decision.kind != "waitlist")
            fail_request(decision, s, c);
        if (decision.kind == "enroll") {
            enroll(s, c);
            record(s, "enroll " + c.code);
            emit(words("ENROLL", s.id, c.code, "enrolled",
                       to_string(c.enrolled.size()) + "/" + to_string(c.capacity),
                       "credits", to_string(s.credits) + "/" + to_string(s.limit)));
        } else {
            int position = stoi(decision.extra[0]);
            c.waitlist.insert(c.waitlist.begin() + position - 1, s.id);
            s.waiting.insert(c.code);
            record(s, words("waitlist", c.code, position));
            emit(words("ENROLL", s.id, c.code, "waitlist", position));
        }
    }

    void cmd_check(const vector<string>& a) {
        Student& s = student(a[0]);
        Course& c = course(a[1]);
        emit(words("CHECK", s.id, c.code, decision_text(request(s, c))));
    }

    void cmd_options(const vector<string>& a) {
        Student& s = student(a[0]);
        emit(words("OPTIONS", s.id, "courses", courses.size()));
        for (const auto& [code, c] : courses)
            emit(words(code, decision_text(request(s, c))), true);
    }

    void cmd_drop(const vector<string>& a) {
        Student& s = student(a[0]);
        Course& c = course(a[1]);
        if (s.courses.count(c.code)) {
            withdraw(s, c);
            record(s, "drop " + c.code);
            emit(words("DROP", s.id, c.code, "enrolled",
                       to_string(c.enrolled.size()) + "/" + to_string(c.capacity),
                       "credits", to_string(s.credits) + "/" + to_string(s.limit)));
        } else if (s.waiting.count(c.code)) {
            unlist(s, c);
            record(s, "drop " + c.code + " waitlist");
            emit(words("DROP", s.id, c.code, "waitlist removed"));
        } else {
            throw CommandError(words("not registered", s.id, c.code));
        }
        promotion();
    }

    void cmd_swap(const vector<string>& a) {
        Student& s = student(a[0]);
        Course& from = course(a[1]);
        Course& to = course(a[2]);
        if (!s.courses.count(from.code))
            throw CommandError(words("not enrolled", s.id, from.code));
        if (from.code == to.code) throw CommandError("same course " + from.code);
        Decision eligibility_result = eligibility(s, to, from.code);
        if (eligibility_result.kind != "OK")
            fail_request(eligibility_result, s, to);
        if (to.enrolled.size() >= static_cast<size_t>(to.capacity))
            throw CommandError("course full " + to.code);
        withdraw(s, from);
        enroll(s, to);
        record(s, words("swap", from.code, to.code));
        emit(words("SWAP", s.id, from.code, "->", to.code, "credits",
                   to_string(s.credits) + "/" + to_string(s.limit)));
        promotion();
    }

    void cmd_close(const vector<string>& a) {
        Course& c = course(a[0]);
        if (!c.open) throw CommandError("already closed " + c.code);
        c.open = false;
        emit(words("CLOSE", c.code, "enrolled",
                   to_string(c.enrolled.size()) + "/" + to_string(c.capacity),
                   "waitlist", c.waitlist.size()));
    }

    void cmd_open(const vector<string>& a) {
        Course& c = course(a[0]);
        if (c.open) throw CommandError("already open " + c.code);
        c.open = true;
        emit(words("OPEN", c.code, "enrolled",
                   to_string(c.enrolled.size()) + "/" + to_string(c.capacity),
                   "waitlist", c.waitlist.size()));
        promotion();
    }

    void cmd_capacity(const vector<string>& a) {
        Course& c = course(a[0]);
        int capacity = stoi(a[1]);
        if (capacity < static_cast<int>(c.enrolled.size()))
            throw CommandError(words("capacity below enrollment", c.code,
                                     c.enrolled.size()));
        int previous = c.capacity;
        c.capacity = capacity;
        emit(words("CAPACITY", c.code, previous, "->", capacity));
        promotion();
    }

    void cmd_limit(const vector<string>& a) {
        Student& s = student(a[0]);
        int limit = stoi(a[1]);
        if (limit < s.credits)
            throw CommandError(words("limit below enrolled", s.id, s.credits));
        int previous = s.limit;
        s.limit = limit;
        emit(words("LIMIT", s.id, previous, "->", limit));
        promotion();
    }

    void cmd_prereq(const vector<string>& a) {
        Course& c = course(a[0]);
        auto expression = prerequisite(c.code, a[1]);
        c.required = expression;
        emit(words("PREREQ", c.code, expression->canonical()));
        vector<string> waiting = c.waitlist;
        for (const string& id : waiting) {
            Student& s = students.at(id);
            if (!expression->evaluate(s)) {
                unlist(s, c);
                record(s, "unlist " + c.code);
                emit(words("UNLIST", s.id, c.code), true);
            }
        }
    }

    void cmd_cancel(const vector<string>& a) {
        Course& c = course(a[0]);
        string code = c.code;
        emit(words("CANCEL", code, "enrolled", c.enrolled.size(),
                   "waitlist", c.waitlist.size()));
        for (const string& id : c.enrolled) {
            Student& s = students.at(id);
            s.courses.erase(code);
            s.credits -= c.credits;
            record(s, "cancel " + code);
        }
        for (const string& id : c.waitlist) {
            Student& s = students.at(id);
            s.waiting.erase(code);
            record(s, "cancel " + code + " waitlist");
        }
        for (const string& other : c.conflicts)
            courses.at(other).conflicts.erase(code);
        courses.erase(code);
        promotion();
    }

    void cmd_roster(const vector<string>& a) {
        Course& c = course(a[0]);
        emit(words("ROSTER", c.code, c.status(), "enrolled",
                   to_string(c.enrolled.size()) + "/" + to_string(c.capacity),
                   "waitlist", c.waitlist.size()));
        for (const string& id : c.enrolled)
            emit(words("enrolled", id, "year", students.at(id).year), true);
        for (size_t i = 0; i < c.waitlist.size(); ++i) {
            const string& id = c.waitlist[i];
            emit(words("waitlist", i + 1, id, "year", students.at(id).year), true);
        }
    }

    vector<tuple<int, int, string>> student_slots(const Student& s,
                                                   int day) const {
        vector<tuple<int, int, string>> slots;
        for (const string& code : s.courses) {
            for (const Slot& slot : courses.at(code).slots) {
                if (slot.day == day) slots.emplace_back(slot.start, slot.end, code);
            }
        }
        sort(slots.begin(), slots.end());
        return slots;
    }

    void cmd_schedule(const vector<string>& a) {
        Student& s = student(a[0]);
        int weekly = 0;
        for (const string& code : s.courses) weekly += courses.at(code).weekly();
        emit(words("SCHEDULE", s.id, "courses", s.courses.size(), "credits",
                   s.credits, "weekly", time_text(weekly)));
        for (int day = 0; day < static_cast<int>(DAYS.size()); ++day) {
            vector<tuple<int, int, string>> slots = student_slots(s, day);
            if (slots.empty()) continue;
            string text = DAYS[day];
            for (const auto& [start, end, code] : slots)
                text += " " + time_text(start) + "-" + time_text(end) + " " + code;
            emit(text, true);
        }
        string pending = "TBA";
        bool found = false;
        for (const string& code : s.courses) {
            if (courses.at(code).slots.empty()) {
                pending += " " + code;
                found = true;
            }
        }
        if (found) emit(pending, true);
    }

    void cmd_free(const vector<string>& a) {
        Student& s = student(a[0]);
        int day = -1;
        for (int i = 0; i < static_cast<int>(DAYS.size()); ++i) {
            if (DAYS[i] == a[1]) day = i;
        }
        if (day < 0) throw CommandError("invalid day " + a[1]);
        vector<pair<int, int>> occupied;
        for (const auto& [start, end, code] : student_slots(s, day)) {
            int first = max(480, start), last = min(1320, end);
            if (first < last) occupied.emplace_back(first, last);
        }
        vector<pair<int, int>> free_ranges;
        int cursor = 480;
        for (const auto& [start, end] : occupied) {
            if (cursor < start) free_ranges.emplace_back(cursor, start);
            cursor = max(cursor, end);
        }
        if (cursor < 1320) free_ranges.emplace_back(cursor, 1320);
        int minutes = 0;
        for (const auto& [start, end] : free_ranges) minutes += end - start;
        string result = words("FREE", s.id, a[1], "total", time_text(minutes));
        for (const auto& [start, end] : free_ranges)
            result += " " + time_text(start) + "-" + time_text(end);
        emit(result);
    }

    void cmd_info(const vector<string>& a) {
        Course& c = course(a[0]);
        emit(words("INFO", c.code, c.status(), "credits", c.credits,
                   "capacity", c.capacity, "prereq", c.required->canonical()));
        vector<Slot> slots = c.slots;
        sort(slots.begin(), slots.end(), [](const Slot& a, const Slot& b) {
            return tie(a.day, a.start) < tie(b.day, b.start);
        });
        if (slots.empty()) {
            emit("meet TBA", true);
        } else {
            for (const Slot& slot : slots)
                emit(words("meet", DAYS[slot.day], slot.text()), true);
        }
        string result = "required by";
        bool found = false;
        for (const auto& [code, other] : courses) {
            if (other.required->references.count(c.code)) {
                result += " " + code;
                found = true;
            }
        }
        if (!found) result += " none";
        emit(result, true);
    }

    void cmd_audit(const vector<string>& a) {
        Student& s = student(a[0]);
        emit(words("AUDIT", s.id, "year", s.year, "limit", s.limit));
        for (const auto& [code, record] : s.records)
            emit(words("record", code, record.grade, record.credits), true);
        emit(words("earned", s.earned(), "gpa", s.gpa()), true);
        for (const string& code : s.courses)
            emit(words("enrolled", code, courses.at(code).credits), true);
        emit(words("credits", s.credits, "remaining", s.limit - s.credits), true);
        for (const string& code : s.waiting) {
            const auto& waiting = courses.at(code).waitlist;
            auto it = find(waiting.begin(), waiting.end(), s.id);
            int position = static_cast<int>(distance(waiting.begin(), it)) + 1;
            emit(words("waitlist", code, position), true);
        }
    }

    void cmd_history(const vector<string>& a) {
        Student& s = student(a[0]);
        emit(words("HISTORY", s.id, "events", s.history.size()));
        for (const auto& [number, event] : s.history)
            emit(words(number, event), true);
    }

    void cmd_students(const vector<string>&) {
        emit(words("STUDENTS", students.size()));
        for (const auto& [id, s] : students) {
            emit(words(id, "year", s.year, "credits",
                       to_string(s.credits) + "/" + to_string(s.limit),
                       "courses", s.courses.size(), "waitlists", s.waiting.size()), true);
        }
    }

    string group_counts(const vector<const Course*>& subset) const {
        int enrolled = 0, capacity = 0, waitlisted = 0;
        for (const Course* c : subset) {
            enrolled += static_cast<int>(c->enrolled.size());
            capacity += c->capacity;
            waitlisted += static_cast<int>(c->waitlist.size());
        }
        return words("enrolled", to_string(enrolled) + "/" + to_string(capacity),
                     "rate", rate_text(enrolled, capacity), "waitlisted", waitlisted);
    }

    void cmd_report(const vector<string>&) {
        vector<const Course*> all_courses;
        map<string, vector<const Course*>> departments;
        for (const auto& [code, c] : courses) {
            all_courses.push_back(&c);
            departments[c.department()].push_back(&c);
        }
        emit(words("REPORT", "courses", courses.size(), group_counts(all_courses)));
        for (const auto& [code, c] : courses) {
            emit(words(code, c.status(),
                       to_string(c.enrolled.size()) + "/" + to_string(c.capacity),
                       rate_text(static_cast<int>(c.enrolled.size()), c.capacity),
                       "waitlist", c.waitlist.size()), true);
        }
        for (const auto& [department, subset] : departments)
            emit(words("dept", department, "courses", subset.size(),
                       group_counts(subset)), true);
    }

public:
    void execute(const string& text) {
        ++command_number;
        istringstream input(text);
        string command, argument;
        input >> command;
        vector<string> args;
        while (input >> argument) args.push_back(argument);
        try {
            if (command == "COURSE") cmd_course(args);
            else if (command == "STUDENT") cmd_student(args);
            else if (command == "ENROLL") cmd_enroll(args);
            else if (command == "CHECK") cmd_check(args);
            else if (command == "OPTIONS") cmd_options(args);
            else if (command == "DROP") cmd_drop(args);
            else if (command == "SWAP") cmd_swap(args);
            else if (command == "CLOSE") cmd_close(args);
            else if (command == "OPEN") cmd_open(args);
            else if (command == "CAPACITY") cmd_capacity(args);
            else if (command == "LIMIT") cmd_limit(args);
            else if (command == "PREREQ") cmd_prereq(args);
            else if (command == "CANCEL") cmd_cancel(args);
            else if (command == "ROSTER") cmd_roster(args);
            else if (command == "SCHEDULE") cmd_schedule(args);
            else if (command == "FREE") cmd_free(args);
            else if (command == "INFO") cmd_info(args);
            else if (command == "AUDIT") cmd_audit(args);
            else if (command == "HISTORY") cmd_history(args);
            else if (command == "STUDENTS") cmd_students(args);
            else if (command == "REPORT") cmd_report(args);
        } catch (const CommandError& error) {
            emit("ERROR " + string(error.what()));
        }
    }

    void print() const {
        for (const string& line : output) cout << line << '\n';
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int count;
    cin >> count;
    cin.ignore();
    Registrar registrar;
    string line;
    for (int i = 0; i < count; ++i) {
        getline(cin, line);
        registrar.execute(line);
    }
    registrar.print();
}
