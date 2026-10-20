#include <algorithm>
#include <functional>
#include <iostream>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>

using std::string;
using std::vector;

const vector<string> types{"BUG", "TASK", "STORY"};
const vector<string> priorities{"LOW", "MEDIUM", "HIGH", "CRITICAL"};
const std::map<string, vector<string>> workflows{
    {"BUG", {"OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED", "CLOSED", "REOPENED"}},
    {"TASK", {"OPEN", "IN_PROGRESS", "DONE"}},
    {"STORY", {"BACKLOG", "READY", "IN_PROGRESS", "REVIEW", "DONE"}}
};
const std::map<string, std::set<std::pair<string, string>>> transitions{
    {"BUG", {{"OPEN", "TRIAGED"}, {"TRIAGED", "IN_PROGRESS"}, {"IN_PROGRESS", "REVIEW"},
        {"REVIEW", "IN_PROGRESS"}, {"REVIEW", "RESOLVED"}, {"RESOLVED", "CLOSED"},
        {"RESOLVED", "REOPENED"}, {"CLOSED", "REOPENED"}, {"REOPENED", "IN_PROGRESS"}}},
    {"TASK", {{"OPEN", "IN_PROGRESS"}, {"IN_PROGRESS", "OPEN"}, {"IN_PROGRESS", "DONE"}}},
    {"STORY", {{"BACKLOG", "READY"}, {"READY", "BACKLOG"}, {"READY", "IN_PROGRESS"},
        {"IN_PROGRESS", "REVIEW"}, {"REVIEW", "IN_PROGRESS"}, {"REVIEW", "DONE"}}}
};
const std::set<string> done_states{"RESOLVED", "CLOSED", "DONE"};
const std::set<int> estimates{0, 1, 2, 3, 5, 8, 13, 21};
const std::set<string> equality{"=", "!="};
const std::set<string> ordered{"=", "!=", "<", "<=", ">", ">="};
const std::map<string, std::set<string>> field_operators{
    {"id", ordered}, {"type", equality}, {"status", equality}, {"priority", ordered},
    {"assignee", equality}, {"reviewer", equality}, {"estimate", ordered}, {"sprint", equality},
    {"comments", ordered}, {"blocked", equality}, {"done", equality}, {"title", {"~"}}
};

bool has(const vector<string>& values, const string& value) {
    return std::find(values.begin(), values.end(), value) != values.end();
}

string join(const vector<string>& values, const string& separator) {
    string result;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i) result += separator;
        result += values[i];
    }
    return result;
}

string lower(string text) {
    for (char& c : text) if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    return text;
}

bool is_number(const string& value) {
    return !value.empty() && value.size() <= 6 && std::all_of(value.begin(), value.end(), [](char c) { return c >= '0' && c <= '9'; });
}

using FieldValue = std::variant<std::monostate, int, string>;

FieldValue nullable(const string& value) { return value.empty() ? FieldValue{} : FieldValue{value}; }
FieldValue nullable(std::optional<int> value) { return value ? FieldValue{*value} : FieldValue{}; }

string display(const FieldValue& value) {
    if (std::holds_alternative<std::monostate>(value)) return "-";
    if (std::holds_alternative<int>(value)) return std::to_string(std::get<int>(value));
    return std::get<string>(value);
}

string yes_no(bool value) { return value ? "yes" : "no"; }

string number_list(const std::set<int>& numbers) {
    vector<string> text;
    for (int n : numbers) text.push_back(std::to_string(n));
    return text.empty() ? "-" : join(text, ",");
}

bool compare(const FieldValue& actual, const string& op, const FieldValue& expected) {
    if (op == "=") return actual == expected;
    if (op == "!=") return actual != expected;
    if (std::holds_alternative<std::monostate>(actual)) return false;
    if (op == "<") return actual < expected;
    if (op == "<=") return actual <= expected;
    if (op == ">") return actual > expected;
    return actual >= expected;
}

struct Issue {
    int number;
    string type, priority, title, state;
    string assignee, reviewer, sprint;
    std::optional<int> estimate, duplicate;
    int comments = 0;
    std::set<int> blocks, blockers, duplicates;
    vector<string> history;

    Issue(int n, string kind, string priority, string title)
        : number(n), type(std::move(kind)), priority(std::move(priority)), title(std::move(title)), state(workflows.at(type)[0]) {}

    bool done() const { return done_states.count(state); }
    int points() const { return estimate.value_or(0); }
    int level() const { return static_cast<int>(std::find(priorities.begin(), priorities.end(), priority) - priorities.begin()); }
};

struct Sprint {
    string name;
    string phase = "PLANNED";
    int start = 0, end = 0, velocity = 0;
    std::map<int, int> records;
};

using Predicate = std::function<bool(const Issue&)>;

class QueryParser {
    const vector<string>& tokens;
    const vector<Predicate>& conditions;
    std::size_t position = 0;

    bool accept(const string& token) {
        if (position == tokens.size() || tokens[position] != token) return false;
        ++position;
        return true;
    }

    Predicate factor() {
        if (accept("NOT")) {
            Predicate operand = factor();
            return [operand](const Issue& issue) { return !operand(issue); };
        }
        if (accept("(")) {
            Predicate node = expression();
            accept(")");
            return node;
        }
        return conditions[position++];
    }

    Predicate term() {
        Predicate node = factor();
        while (accept("AND")) {
            Predicate left = node, right = factor();
            node = [left, right](const Issue& issue) { return left(issue) && right(issue); };
        }
        return node;
    }

public:
    QueryParser(const vector<string>& tokens, const vector<Predicate>& conditions) : tokens(tokens), conditions(conditions) {}

    Predicate expression() {
        Predicate node = term();
        while (accept("OR")) {
            Predicate left = node, right = term();
            node = [left, right](const Issue& issue) { return left(issue) || right(issue); };
        }
        return node;
    }
};

class Tracker {
    int day = 1;
    std::set<string> users;
    std::map<int, Issue> issues;
    std::map<string, Sprint> sprints;
    vector<string> sprint_order;
    vector<string> output;

    void emit(string line) { output.push_back(std::move(line)); }

    Issue& issue(int n) {
        auto it = issues.find(n);
        if (it == issues.end()) throw std::runtime_error("unknown issue");
        return it->second;
    }

    string user(const string& spec) {
        if (spec == "-") return "";
        if (!users.count(spec)) throw std::runtime_error("unknown user");
        return spec;
    }

    Sprint& sprint(const string& name) {
        auto it = sprints.find(name);
        if (it == sprints.end()) throw std::runtime_error("unknown sprint");
        return it->second;
    }

    void not_done(const Issue& issue) const { if (issue.done()) throw std::runtime_error("issue done"); }

    vector<int> unfinished_blockers(const Issue& issue) const {
        vector<int> result;
        for (int n : issue.blockers) if (!issues.at(n).done()) result.push_back(n);
        return result;
    }

    bool blocked(const Issue& issue) const { return !issue.done() && !unfinished_blockers(issue).empty(); }

    int wip(const string& user) const {
        int count = 0;
        for (const auto& [n, issue] : issues) if (issue.assignee == user && issue.state == "IN_PROGRESS") ++count;
        return count;
    }

    Sprint* active() {
        for (auto& [name, sprint] : sprints) if (sprint.phase == "ACTIVE") return &sprint;
        return nullptr;
    }

    vector<Issue*> members(const Sprint& sprint) {
        vector<Issue*> result;
        for (auto& [n, issue] : issues) if (issue.sprint == sprint.name) result.push_back(&issue);
        return result;
    }

    int remaining(const Sprint& sprint) {
        int total = 0;
        for (const Issue* issue : members(sprint)) if (!issue->done()) total += issue->points();
        return total;
    }

    string summary(const Sprint& sprint) {
        vector<Issue*> entries = members(sprint);
        int total = 0;
        for (const Issue* issue : entries) total += issue->points();
        return "issues " + std::to_string(entries.size()) + " points " + std::to_string(total);
    }

    void record(Issue& issue, const string& text) { issue.history.push_back("day " + std::to_string(day) + " " + text); }

    std::map<int, bool> blocked_states(const std::set<int>& numbers) const {
        std::map<int, bool> result;
        for (int n : numbers) result[n] = blocked(issues.at(n));
        return result;
    }

    void notify(const std::map<int, bool>& before) {
        for (const auto& [n, previous] : before) {
            bool after = blocked(issues.at(n));
            if (previous != after) emit(string(after ? "BLOCKED " : "UNBLOCKED ") + std::to_string(n));
        }
    }

    void change_state(Issue& issue, const string& target) {
        std::map<int, bool> before = blocked_states(issue.blocks);
        emit("MOVE " + std::to_string(issue.number) + " " + issue.state + " " + target);
        record(issue, "MOVE " + issue.state + " " + target);
        issue.state = target;
        notify(before);
    }

    bool reaches(int start, int goal) const {
        vector<int> pending{start};
        std::set<int> seen;
        while (!pending.empty()) {
            int n = pending.back(); pending.pop_back();
            if (n == goal) return true;
            if (!seen.insert(n).second) continue;
            const std::set<int>& next = issues.at(n).blocks;
            pending.insert(pending.end(), next.begin(), next.end());
        }
        return false;
    }

    FieldValue field_value(const Issue& issue, const string& field) const {
        if (field == "id") return issue.number;
        if (field == "type") return issue.type;
        if (field == "status") return issue.state;
        if (field == "priority") return issue.level();
        if (field == "assignee") return nullable(issue.assignee);
        if (field == "reviewer") return nullable(issue.reviewer);
        if (field == "estimate") return nullable(issue.estimate);
        if (field == "sprint") return nullable(issue.sprint);
        if (field == "comments") return issue.comments;
        if (field == "blocked") return yes_no(blocked(issue));
        if (field == "done") return yes_no(issue.done());
        return lower(issue.title);
    }

    FieldValue condition_value(const string& token, const string& field, const string& op, const string& value) const {
        if (value == "-" && equality.count(op) && (field == "assignee" || field == "reviewer" || field == "estimate" || field == "sprint")) return {};
        if ((field == "id" || field == "estimate" || field == "comments") && is_number(value)) return std::stoi(value);
        if (field == "priority" && has(priorities, value)) return static_cast<int>(std::find(priorities.begin(), priorities.end(), value) - priorities.begin());
        if (field == "type" && has(types, value)) return value;
        if (field == "status") for (const auto& [type, states] : workflows) if (has(states, value)) return value;
        if ((field == "assignee" || field == "reviewer") && users.count(value)) return value;
        if (field == "sprint" && sprints.count(value)) return value;
        if ((field == "blocked" || field == "done") && (value == "yes" || value == "no")) return value;
        if (field == "title") return lower(value);
        throw std::runtime_error("bad value " + token);
    }

    Predicate condition(const string& token) const {
        std::size_t length = 0;
        while (length < token.size() && token[length] >= 'a' && token[length] <= 'z') ++length;
        string field = token.substr(0, length), rest = token.substr(length), op;
        for (const string& candidate : {">=", "<=", "!=", "=", "<", ">", "~"})
            if (rest.compare(0, candidate.size(), candidate) == 0) { op = candidate; break; }
        string text = rest.substr(op.size());
        if (field.empty() || op.empty() || text.empty()) throw std::runtime_error("syntax near " + token);
        auto allowed = field_operators.find(field);
        if (allowed == field_operators.end()) throw std::runtime_error("unknown field " + field);
        if (!allowed->second.count(op)) throw std::runtime_error("bad operator " + token);
        FieldValue expected = condition_value(token, field, op, text);
        return [this, field, op, expected](const Issue& issue) {
            FieldValue actual = field_value(issue, field);
            return op == "~" ? std::get<string>(actual).find(std::get<string>(expected)) != string::npos : compare(actual, op, expected);
        };
    }

    void query(const string& text);
    void link(const string& command, const vector<string>& args);
    void sprint_command(const vector<string>& args);
    void dispatch(const string& command, const vector<string>& args);

public:
    vector<string> execute(const string& line) {
        output.clear();
        std::istringstream input(line);
        string command, word;
        input >> command;
        vector<string> args;
        while (input >> word) args.push_back(word);
        try { dispatch(command, args); }
        catch (const std::runtime_error& error) { emit("ERROR " + string(error.what())); }
        Sprint* sprint = active();
        if (sprint) sprint->records[day] = remaining(*sprint);
        return output;
    }
};

void Tracker::query(const string& text) {
    vector<string> tokens;
    string current;
    for (char c : text) {
        if (c == ' ' || c == '(' || c == ')') {
            if (!current.empty()) { tokens.push_back(current); current.clear(); }
            if (c != ' ') tokens.emplace_back(1, c);
        } else current += c;
    }
    if (!current.empty()) tokens.push_back(current);
    vector<Predicate> conditions(tokens.size());
    bool operand = true;
    int depth = 0;
    for (std::size_t i = 0; i < tokens.size(); ++i) {
        const string& token = tokens[i];
        if (operand) {
            if (token == "(") ++depth;
            else if (token == "AND" || token == "OR" || token == ")") throw std::runtime_error("syntax near " + token);
            else if (token != "NOT") { conditions[i] = condition(token); operand = false; }
        } else if (token == "AND" || token == "OR") operand = true;
        else if (token == ")" && depth > 0) --depth;
        else throw std::runtime_error("syntax near " + token);
    }
    if (operand || depth != 0) throw std::runtime_error("syntax at end");
    Predicate matches = QueryParser(tokens, conditions).expression();
    vector<const Issue*> found;
    for (const auto& [n, issue] : issues) if (matches(issue)) found.push_back(&issue);
    std::sort(found.begin(), found.end(), [](const Issue* a, const Issue* b) {
        return a->level() != b->level() ? a->level() > b->level() : a->number < b->number;
    });
    emit("QUERY " + std::to_string(found.size()));
    for (const Issue* i : found) emit(std::to_string(i->number) + " " + i->type + " " + i->priority + " " + i->state
        + " " + display(nullable(i->assignee)) + " " + display(nullable(i->estimate)) + " " + i->title);
}

void Tracker::link(const string& command, const vector<string>& args) {
    const string& relation = args[1];
    if (command == "UNLINK" ? relation != "BLOCKS" : relation != "BLOCKS" && relation != "DUPLICATES")
        throw std::runtime_error("bad link");
    Issue& a = issue(std::stoi(args[0]));
    Issue& b = issue(std::stoi(args[2]));
    string a_text = std::to_string(a.number), b_text = std::to_string(b.number);
    if (command == "UNLINK") {
        if (!a.blocks.count(b.number)) throw std::runtime_error("no link");
        std::map<int, bool> before = blocked_states({b.number});
        a.blocks.erase(b.number);
        b.blockers.erase(a.number);
        record(a, "UNLINK BLOCKS " + b_text);
        record(b, "UNLINK BLOCKED_BY " + a_text);
        emit("UNLINK " + a_text + " BLOCKS " + b_text);
        notify(before);
        return;
    }
    if (a.number == b.number) throw std::runtime_error("self link");
    if (relation == "BLOCKS") {
        if (a.blocks.count(b.number)) throw std::runtime_error("link exists");
        if (reaches(b.number, a.number)) throw std::runtime_error("cycle");
        not_done(b);
        std::map<int, bool> before = blocked_states({b.number});
        a.blocks.insert(b.number);
        b.blockers.insert(a.number);
        record(a, "LINK BLOCKS " + b_text);
        record(b, "LINK BLOCKED_BY " + a_text);
        emit("LINK " + a_text + " BLOCKS " + b_text);
        notify(before);
    } else {
        if (a.type != b.type) throw std::runtime_error("type mismatch");
        not_done(a);
        if (b.duplicate) throw std::runtime_error("target is duplicate");
        a.duplicate = b.number;
        b.duplicates.insert(a.number);
        record(a, "LINK DUPLICATES " + b_text);
        record(b, "LINK DUPLICATED_BY " + a_text);
        emit("LINK " + a_text + " DUPLICATES " + b_text);
        change_state(a, a.type == "BUG" ? "CLOSED" : "DONE");
        if (!a.sprint.empty() && sprints.at(a.sprint).phase != "ENDED") {
            record(a, "SPRINT REMOVE " + a.sprint);
            a.sprint.clear();
        }
    }
}

void Tracker::sprint_command(const vector<string>& args) {
    const string& operation = args[0];
    const string& name = args[1];
    if (operation == "NEW") {
        if (sprints.count(name)) throw std::runtime_error("sprint exists");
        sprints.emplace(name, Sprint{name});
        sprint_order.push_back(name);
        emit("SPRINT NEW " + name);
        return;
    }
    Sprint& s = sprint(name);
    if (operation == "ADD" || operation == "REMOVE") {
        Issue& i = issue(std::stoi(args[2]));
        if (s.phase == "ENDED") throw std::runtime_error("sprint ended");
        if (operation == "ADD") {
            not_done(i);
            if (!i.sprint.empty() && sprints.at(i.sprint).phase != "ENDED") throw std::runtime_error("in sprint " + i.sprint);
            if (i.state == "BACKLOG") throw std::runtime_error("not ready");
            i.sprint = name;
        } else {
            if (i.sprint != name) throw std::runtime_error("not in sprint");
            not_done(i);
            i.sprint.clear();
        }
        record(i, "SPRINT " + operation + " " + name);
        emit("SPRINT " + operation + " " + name + " " + std::to_string(i.number) + " " + summary(s));
    } else if (operation == "START") {
        if (s.phase != "PLANNED") throw std::runtime_error("sprint not planned");
        Sprint* current = active();
        if (current) throw std::runtime_error("sprint active " + current->name);
        if (members(s).empty()) throw std::runtime_error("sprint empty");
        s.phase = "ACTIVE";
        s.start = day;
        int points = remaining(s);
        s.records[day] = points;
        emit("SPRINT START " + name + " day " + std::to_string(day) + " " + summary(s) + " remaining " + std::to_string(points));
    } else {
        if (s.phase != "ACTIVE") throw std::runtime_error("sprint not active");
        s.records[day] = remaining(s);
        vector<Issue*> returned;
        int done = 0;
        s.velocity = 0;
        for (Issue* i : members(s)) {
            if (i->done()) { ++done; s.velocity += i->points(); }
            else returned.push_back(i);
        }
        s.phase = "ENDED";
        s.end = day;
        emit("SPRINT END " + name + " day " + std::to_string(day) + " velocity " + std::to_string(s.velocity)
            + " done " + std::to_string(done) + " returned " + std::to_string(returned.size()));
        for (Issue* i : returned) {
            i->sprint.clear();
            record(*i, "SPRINT RETURN " + name);
            emit("RETURNED " + std::to_string(i->number));
        }
    }
}

void Tracker::dispatch(const string& command, const vector<string>& args) {
    if (command == "DAY") {
        int next = std::stoi(args[0]);
        if (next < day) throw std::runtime_error("day backwards");
        day = next;
        emit("DAY " + std::to_string(day));
        return;
    }
    if (command == "USER") {
        if (users.count(args[0])) throw std::runtime_error("user exists");
        users.insert(args[0]);
        emit("USER " + args[0]);
        return;
    }
    if (command == "CREATE") {
        int number = std::stoi(args[0]);
        if (issues.count(number)) throw std::runtime_error("issue exists");
        if (!has(types, args[1])) throw std::runtime_error("bad type");
        if (!has(priorities, args[2])) throw std::runtime_error("bad priority");
        string title = join(vector<string>(args.begin() + 3, args.end()), " ");
        Issue& i = issues.emplace(number, Issue(number, args[1], args[2], title)).first->second;
        record(i, "CREATE " + i.type + " " + i.priority);
        emit("CREATE " + std::to_string(number) + " " + i.type + " " + i.priority + " " + i.state);
        return;
    }
    if (command == "SPRINT") { sprint_command(args); return; }
    if (command == "QUERY") { query(join(args, " ")); return; }
    if (command == "LINK" || command == "UNLINK") { link(command, args); return; }
    if (command == "BOARD") {
        emit("BOARD");
        for (const string& type : types) {
            string line = type;
            for (const string& state : workflows.at(type)) {
                int count = 0;
                for (const auto& [n, i] : issues) if (i.type == type && i.state == state) ++count;
                line += " " + state + " " + std::to_string(count);
            }
            emit(line);
        }
        int done = 0;
        for (const auto& [n, i] : issues) if (i.done()) ++done;
        emit("TOTAL " + std::to_string(issues.size()) + " open " + std::to_string(issues.size() - done) + " done " + std::to_string(done));
        return;
    }
    if (command == "WORKLOAD") {
        emit("WORKLOAD " + std::to_string(users.size()));
        for (const string& user : users) {
            int assigned = 0, in_progress = 0, review = 0, reviewing = 0, points = 0;
            for (const auto& [n, i] : issues) {
                if (i.assignee == user && !i.done()) {
                    ++assigned; points += i.points();
                    if (i.state == "IN_PROGRESS") ++in_progress;
                    if (i.state == "REVIEW") ++review;
                }
                if (i.reviewer == user && i.state == "REVIEW") ++reviewing;
            }
            emit(user + " assigned " + std::to_string(assigned) + " in_progress " + std::to_string(in_progress)
                + " review " + std::to_string(review) + " reviewing " + std::to_string(reviewing) + " points " + std::to_string(points));
        }
        return;
    }
    if (command == "SPRINTS") {
        emit("SPRINTS " + std::to_string(sprints.size()));
        for (const string& name : sprint_order) {
            Sprint& s = sprints.at(name);
            string line = name + " " + s.phase;
            if (s.phase == "PLANNED") line += " " + summary(s);
            else if (s.phase == "ACTIVE") line += " start " + std::to_string(s.start) + " " + summary(s) + " remaining " + std::to_string(remaining(s));
            else line += " start " + std::to_string(s.start) + " end " + std::to_string(s.end) + " velocity " + std::to_string(s.velocity);
            emit(line);
        }
        return;
    }
    if (command == "BURNDOWN") {
        Sprint& s = sprint(args[0]);
        if (s.phase == "PLANNED") throw std::runtime_error("sprint not started");
        int last = s.phase == "ACTIVE" ? day : s.end;
        emit("BURNDOWN " + s.name + " " + s.phase + " days " + std::to_string(last - s.start + 1));
        int value = 0;
        for (int d = s.start; d <= last; ++d) {
            auto it = s.records.find(d);
            if (it != s.records.end()) value = it->second;
            emit("day " + std::to_string(d) + " " + std::to_string(value));
        }
        return;
    }
    Issue& i = issue(std::stoi(args[0]));
    string number = std::to_string(i.number);
    if (command == "SHOW") {
        emit("ISSUE " + number + " " + i.type + " " + i.priority + " " + i.state + " blocked " + yes_no(blocked(i)));
        emit("TITLE " + i.title);
        emit("PEOPLE assignee " + display(nullable(i.assignee)) + " reviewer " + display(nullable(i.reviewer)));
        emit("PLAN estimate " + display(nullable(i.estimate)) + " sprint " + display(nullable(i.sprint)) + " comments " + std::to_string(i.comments));
        emit("LINKS blocks " + number_list(i.blocks) + " blocked_by " + number_list(i.blockers)
            + " duplicate_of " + display(nullable(i.duplicate)) + " duplicated_by " + number_list(i.duplicates));
        return;
    }
    if (command == "HISTORY") {
        emit("HISTORY " + number + " " + std::to_string(i.history.size()));
        for (const string& entry : i.history) emit(entry);
        return;
    }
    const string& value = args[1];
    if (command == "PRIORITY") {
        if (!has(priorities, value)) throw std::runtime_error("bad priority");
        not_done(i);
        if (i.priority == value) throw std::runtime_error("no change");
        string previous = i.priority;
        i.priority = value;
        record(i, "PRIORITY " + previous + " " + value);
        emit("PRIORITY " + number + " " + previous + " " + value);
    } else if (command == "ASSIGN" || command == "REVIEWER") {
        string owner = user(value);
        not_done(i);
        string& destination = command == "ASSIGN" ? i.assignee : i.reviewer;
        if (destination == owner) throw std::runtime_error("no change");
        if (command == "ASSIGN") {
            if (owner.empty() && (i.state == "IN_PROGRESS" || i.state == "REVIEW")) throw std::runtime_error("assignee required");
            if (i.state == "IN_PROGRESS" && wip(owner) >= 3) throw std::runtime_error("wip limit " + value);
            if (i.state == "REVIEW" && owner == i.reviewer) throw std::runtime_error("reviewer is assignee");
        } else {
            if (owner.empty() && i.state == "REVIEW") throw std::runtime_error("reviewer required");
            if (i.state == "REVIEW" && owner == i.assignee) throw std::runtime_error("reviewer is assignee");
        }
        destination = owner;
        record(i, command + " " + value);
        emit(command + " " + number + " " + value);
    } else if (command == "ESTIMATE") {
        int points = std::stoi(value);
        if (!estimates.count(points)) throw std::runtime_error("bad estimate");
        not_done(i);
        if (i.estimate == points) throw std::runtime_error("no change");
        string previous = display(nullable(i.estimate));
        i.estimate = points;
        record(i, "ESTIMATE " + previous + " " + std::to_string(points));
        emit("ESTIMATE " + number + " " + previous + " " + std::to_string(points));
    } else if (command == "COMMENT") {
        user(value);
        ++i.comments;
        record(i, "COMMENT " + value + " " + join(vector<string>(args.begin() + 2, args.end()), " "));
        emit("COMMENT " + number + " " + std::to_string(i.comments));
    } else if (command == "MOVE") {
        if (i.duplicate) throw std::runtime_error("duplicate of " + std::to_string(*i.duplicate));
        if (!has(workflows.at(i.type), value)) throw std::runtime_error("bad state");
        if (!transitions.at(i.type).count({i.state, value})) throw std::runtime_error("cannot move " + i.state + " to " + value);
        if (value == "IN_PROGRESS") {
            Sprint* current = active();
            if (i.type == "STORY" && (!current || i.sprint != current->name)) throw std::runtime_error("not in active sprint");
            if (i.assignee.empty()) throw std::runtime_error("no assignee");
            if (wip(i.assignee) >= 3) throw std::runtime_error("wip limit " + i.assignee);
        }
        if (value == "REVIEW") {
            if (i.reviewer.empty()) throw std::runtime_error("no reviewer");
            if (i.reviewer == i.assignee) throw std::runtime_error("reviewer is assignee");
        }
        if (value == "DONE" || value == "RESOLVED") {
            vector<int> blockers = unfinished_blockers(i);
            if (!blockers.empty()) throw std::runtime_error("blocked by " + std::to_string(blockers[0]));
        }
        if (value == "READY" && !i.estimate) throw std::runtime_error("no estimate");
        change_state(i, value);
    }
}

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int count;
    std::cin >> count;
    string line;
    std::getline(std::cin, line);
    Tracker tracker;
    for (int n = 0; n < count; ++n) {
        std::getline(std::cin, line);
        for (const string& output : tracker.execute(line)) std::cout << output << '\n';
    }
}
