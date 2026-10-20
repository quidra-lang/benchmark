#include <algorithm>
#include <cctype>
#include <functional>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
using namespace std;
using Vec = vector<int>;
struct Process { int id, created; Vec maximum, allocation; };
struct Waiting { int id; Vec value; int since; };
struct Event { int command; string kind; int id; Vec value; int waited; };
struct State {
    Vec total, available;
    map<int, Process> processes;
    vector<Waiting> queue;
    vector<Event> history;
};
struct Check { Vec sequence, remaining; };
struct Decision { string reason; Vec sequence; };
State state;
map<string, State> snapshots;
string mode = "AVOID", policy = "ALLOC";
bool tracing = false, autodetect = false;
int commandNumber;
const vector<string> kinds = {"granted", "blocked", "unblocked", "released", "finished", "aborted", "cancelled"};
void emit(string line) {
    while (!line.empty() && line.back() == ' ') line.pop_back();
    cout << line << '\n';
}
string pn(int id) { return "P" + to_string(id); }
string join(const vector<string>& items, const string& separator) {
    string text;
    for (const string& item : items) { if (!text.empty()) text += separator; text += item; }
    return text;
}
string vl(const Vec& v) { vector<string> parts; for (int x : v) parts.push_back(to_string(x)); return "(" + join(parts, ",") + ")"; }
string pl(const Vec& v) { vector<string> parts; for (int x : v) parts.push_back(pn(x)); return join(parts, " "); }
string type(int i) { return string(1, char('A' + i)); }
Vec add(Vec a, const Vec& b) { for (size_t i = 0; i < a.size(); ++i) a[i] += b[i]; return a; }
Vec sub(Vec a, const Vec& b) { for (size_t i = 0; i < a.size(); ++i) a[i] -= b[i]; return a; }
int sum(const Vec& v) { return accumulate(v.begin(), v.end(), 0); }
bool fits(const Vec& a, const Vec& b) { for (size_t i = 0; i < a.size(); ++i) if (a[i] > b[i]) return false; return true; }
Vec need(const Process& p) { return sub(p.maximum, p.allocation); }
void fail(const string& message) { throw runtime_error(message); }
const Waiting* waiting(int id) { for (const Waiting& w : state.queue) if (w.id == id) return &w; return nullptr; }
Vec requestOf(int id) { const Waiting* w = waiting(id); return w ? w->value : Vec(state.total.size()); }
Process& require(int id, bool unblocked) {
    if (!state.processes.count(id)) fail("unknown process " + pn(id));
    if (unblocked && waiting(id)) fail("process " + pn(id) + " is blocked");
    return state.processes.at(id);
}
Vec parseVector(const vector<string>& words, size_t start) {
    if (words.size() - start != state.total.size()) fail("wrong vector length");
    Vec v; for (size_t i = start; i < words.size(); ++i) v.push_back(stoi(words[i])); return v;
}
Check check(Vec work, bool detecting, bool traced, const set<int>& excluded = {}) {
    Vec remaining, idle, sequence;
    for (const auto& item : state.processes) {
        const Process& p = item.second;
        if (excluded.count(p.id)) work = add(work, p.allocation);
        else if (detecting && sum(p.allocation) == 0) idle.push_back(p.id);
        else remaining.push_back(p.id);
    }
    string prefix = detecting ? "[detect]" : "[safety]";
    if (traced) emit(prefix + " start work=" + vl(work) + (idle.empty() ? "" : " idle " + pl(idle)));
    while (true) {
        int chosen = -1;
        for (int id : remaining) if (fits(detecting ? requestOf(id) : need(state.processes.at(id)), work)) { chosen = id; break; }
        if (chosen < 0) break;
        work = add(work, state.processes.at(chosen).allocation);
        remaining.erase(find(remaining.begin(), remaining.end(), chosen)); sequence.push_back(chosen);
        if (traced) emit(prefix + " " + pn(chosen) + " can finish, work=" + vl(work));
    }
    if (traced && !remaining.empty()) emit(prefix + " stuck work=" + vl(work) + " remaining " + pl(remaining));
    return {sequence, remaining};
}
Vec detect(bool traced) { return check(state.available, true, traced).remaining; }
string rejection(const Process& p, const Vec& v) {
    if (waiting(p.id)) return "process " + pn(p.id) + " is blocked";
    if (sum(v) == 0) return "zero vector";
    if (!fits(v, need(p))) return "request exceeds need";
    if (mode == "ORDER") {
        int last = -1;
        for (size_t i = 0; i < v.size(); ++i) if (p.allocation[i] > 0) last = int(i);
        for (int i = 0; i <= last; ++i) if (v[i] > 0) return "resource order violation";
    }
    return "";
}
Decision decision(Process& p, const Vec& v, bool traced) {
    if (!fits(v, state.available)) return {"insufficient resources", {}};
    if (mode != "AVOID") return {"", {}};
    Vec old = p.allocation; p.allocation = add(old, v);
    Check result = check(sub(state.available, v), false, traced);
    p.allocation = old;
    return {result.remaining.empty() ? "" : "unsafe state", result.sequence};
}
void allocate(Process& p, const Vec& v) { p.allocation = add(p.allocation, v); state.available = sub(state.available, v); }
void record(const string& kind, int id, const Vec& v, int waited = 0) { state.history.push_back({commandNumber, kind, id, v, waited}); }
void retry() {
    vector<Waiting> kept;
    for (const Waiting& w : state.queue) {
        Process& p = state.processes.at(w.id);
        if (decision(p, w.value, tracing).reason.empty()) {
            allocate(p, w.value); emit("unblocked " + pn(w.id) + " " + vl(w.value)); record("unblocked", w.id, w.value, commandNumber - w.since);
        } else kept.push_back(w);
    }
    state.queue = kept;
}
void terminate(int id, const string& kind) {
    Vec released = state.processes.at(id).allocation;
    state.queue.erase(remove_if(state.queue.begin(), state.queue.end(), [id](const Waiting& w) { return w.id == id; }), state.queue.end());
    state.available = add(state.available, released); state.processes.erase(id);
    emit(kind + " " + pn(id) + " released " + vl(released)); record(kind, id, released);
}
void graph(bool resources) {
    int m = int(state.total.size());
    if (resources && any_of(state.total.begin(), state.total.end(), [](int x) { return x != 1; })) fail("not single-instance");
    map<int, vector<pair<int, int>>> edges;
    for (const auto& item : state.processes) edges[item.first] = {};
    bool any = false;
    if (!resources) {
        for (const auto& item : state.processes) {
            int id = item.first; Vec req = requestOf(id);
            for (const auto& other : state.processes) {
                int next = other.first; if (id == next) continue;
                vector<string> labels;
                for (int i = 0; i < m; ++i) if (req[i] > state.available[i] && other.second.allocation[i] > 0) labels.push_back(type(i));
                if (!labels.empty()) { edges[id].push_back({next, -1}); any = true; emit(pn(id) + " -> " + pn(next) + " on " + join(labels, ",")); }
            }
        }
        if (!any) emit("no wait edges");
    } else {
        Vec holders(m, -1);
        for (const auto& item : state.processes) for (int i = 0; i < m; ++i) if (item.second.allocation[i] > 0) holders[i] = item.first;
        for (int i = 0; i < m; ++i) if (holders[i] >= 0) emit("assign " + type(i) + " -> " + pn(holders[i]));
        for (const auto& item : state.processes) {
            int id = item.first; Vec req = requestOf(id);
            for (int i = 0; i < m; ++i) if (req[i] > 0) { emit("request " + pn(id) + " -> " + type(i)); if (holders[i] >= 0) edges[id].push_back({holders[i], i}); }
        }
        for (const auto& item : state.processes) {
            int id = item.first; Vec req = requestOf(id), n = need(item.second);
            for (int i = 0; i < m; ++i) if (n[i] > 0 && req[i] == 0) emit("claim " + pn(id) + " -> " + type(i));
        }
    }
    map<Vec, string> cycles;
    for (const auto& item : state.processes) {
        int start = item.first; set<int> visited{start};
        function<void(int, Vec, vector<string>)> search = [&](int current, Vec key, vector<string> labels) {
            for (const pair<int, int>& edge : edges[current]) {
                int next = edge.first; if (next < start) continue;
                Vec nextKey = key; vector<string> nextLabels = labels;
                if (resources) { nextKey.push_back(edge.second); nextLabels.push_back(type(edge.second)); }
                nextKey.push_back(next); nextLabels.push_back(pn(next));
                if (next == start) {
                    if (resources || visited.size() > 1) cycles[nextKey] = "cycle: " + join(nextLabels, " -> ");
                } else if (!visited.count(next)) { visited.insert(next); search(next, nextKey, nextLabels); visited.erase(next); }
            }
        };
        search(start, {start}, {pn(start)});
    }
    for (const auto& cycle : cycles) emit(cycle.second);
    if (cycles.empty()) emit("no cycles");
}
string table(const Vec& values) {
    ostringstream text;
    for (size_t i = 0; i < values.size(); ++i) { if (i) text << ' '; text << setw(int(to_string(state.total[i]).size())) << values[i]; }
    return text.str();
}
void showState() {
    ostringstream names;
    for (size_t i = 0; i < state.total.size(); ++i) { if (i) names << ' '; names << setw(int(to_string(state.total[i]).size())) << type(int(i)); }
    string name = names.str(); vector<string> headings = {"Allocation", "Max", "Need", "Request"}; Vec widths;
    for (const string& h : headings) widths.push_back(int(max(h.size(), name.size())));
    auto row = [&](const string& heading, const vector<string>& fields) {
        ostringstream line; line << left << setw(9) << heading;
        for (int i = 0; i < 4; ++i) line << "  " << setw(widths[i]) << fields[i];
        emit(line.str());
    };
    row("Process", headings); row("", {name, name, name, name});
    for (const auto& item : state.processes) { const Process& p = item.second; row(pn(p.id), {table(p.allocation), table(p.maximum), table(need(p)), table(requestOf(p.id))}); }
    row("Available", {table(state.available), "", "", ""}); row("Total", {table(state.total), "", "", ""});
    vector<string> queue;
    for (const Waiting& w : state.queue) queue.push_back(pn(w.id) + " " + vl(w.value) + " since t=" + to_string(w.since));
    emit("blocked queue: " + (queue.empty() ? "empty" : join(queue, ", ")));
}
void stats() {
    for (size_t i = 0; i < state.total.size(); ++i) {
        int total = state.total[i], used = total - state.available[i], requested = 0;
        for (const Waiting& w : state.queue) requested += w.value[i];
        int percent = used * 1000 / total;
        emit(type(int(i)) + ": allocated " + to_string(used) + "/" + to_string(total) + " (" + to_string(percent / 10) + "." + to_string(percent % 10) + "%), requested " + to_string(requested));
    }
    vector<string> counts;
    for (const string& kind : kinds) { int n = 0; for (const Event& e : state.history) if (e.kind == kind) ++n; counts.push_back(kind + " " + to_string(n)); }
    emit("events: " + join(counts, ", "));
    int waits = 0, total = 0;
    for (const Event& e : state.history) if (e.kind == "unblocked") { ++waits; total += e.waited; }
    if (waits == 0) emit("waits: none");
    else { int average = total * 100 / waits; ostringstream line; line << "waits: " << waits << " unblocked, total " << total << ", average " << average / 100 << '.' << setfill('0') << setw(2) << average % 100; emit(line.str()); }
}
void execute(const vector<string>& w) {
    string c = w[0];
    if (c == "MODE" || c == "POLICY" || c == "TRACE" || c == "AUTODETECT") {
        if (c == "MODE") mode = w[1];
        if (c == "POLICY") policy = w[1];
        if (c == "TRACE") tracing = w[1] == "ON";
        if (c == "AUTODETECT") autodetect = w[1] == "ON";
        transform(c.begin(), c.end(), c.begin(), [](unsigned char ch) { return char(tolower(ch)); }); emit(c + " " + w[1]); return;
    }
    if (c == "RESOURCES") {
        Vec v; for (size_t i = 1; i < w.size(); ++i) v.push_back(stoi(w[i])); state = State{}; state.total = state.available = v; emit("resources " + vl(v)); return;
    }
    if (c == "PROCESS" || c == "CLAIM" || c == "REQUEST" || c == "WHATIF" || c == "RELEASE") {
        int id = stoi(w[1]); Vec v = parseVector(w, 2); string name = pn(id);
        if (c == "PROCESS") {
            if (state.processes.count(id)) fail("duplicate process " + name);
            if (!fits(v, state.total)) fail("max exceeds total");
            state.processes[id] = {id, commandNumber, v, Vec(v.size())}; emit("process " + name + " max " + vl(v)); return;
        }
        Process& p = require(id, c == "CLAIM" || c == "RELEASE");
        if (c == "CLAIM") {
            if (!fits(p.allocation, v)) fail("claim below allocation");
            if (!fits(v, state.total)) fail("max exceeds total");
            Vec old = p.maximum; p.maximum = v; bool unsafe = mode == "AVOID" && !check(state.available, false, tracing).remaining.empty(); p.maximum = old;
            if (unsafe) fail("claim makes state unsafe");
            p.maximum = v; emit("claim " + name + " max " + vl(v)); retry(); return;
        }
        if (c == "RELEASE") {
            if (sum(v) == 0) fail("zero vector");
            if (!fits(v, p.allocation)) fail("release exceeds allocation");
            p.allocation = sub(p.allocation, v); state.available = add(state.available, v); emit("released " + name + " " + vl(v)); record("released", id, v); retry(); return;
        }
        string reject = rejection(p, v), prefix = "whatif " + name + " " + vl(v);
        if (!reject.empty()) { if (c == "REQUEST") fail(reject); emit(prefix + ": rejected (" + reject + ")"); return; }
        Decision d = decision(p, v, tracing);
        if (c == "WHATIF") emit(!d.reason.empty() ? prefix + ": blocked (" + d.reason + ")" : prefix + ": granted" + (mode == "AVOID" ? ", safe sequence " + pl(d.sequence) : ""));
        else if (d.reason.empty()) { allocate(p, v); emit("granted " + name + " " + vl(v)); record("granted", id, v); }
        else { state.queue.push_back({id, v, commandNumber}); emit("blocked " + name + " " + vl(v) + ": " + d.reason); record("blocked", id, v); if (autodetect) { Vec dead = detect(tracing); if (!dead.empty()) emit("deadlock detected: " + pl(dead)); } }
        return;
    }
    if (c == "ADD" || c == "REMOVE") {
        Vec v = parseVector(w, 1); if (sum(v) == 0) fail("zero vector");
        if (c == "ADD") { state.total = add(state.total, v); state.available = add(state.available, v); emit("added " + vl(v) + " total " + vl(state.total)); retry(); }
        else {
            if (!fits(v, state.available)) fail("remove exceeds available");
            Vec total = sub(state.total, v), available = sub(state.available, v);
            if (find(total.begin(), total.end(), 0) != total.end()) fail("total must stay positive");
            for (const auto& item : state.processes) if (!fits(item.second.maximum, total)) fail("max exceeds total");
            if (mode == "AVOID" && !check(available, false, tracing).remaining.empty()) fail("removal makes state unsafe");
            state.total = total; state.available = available; emit("removed " + vl(v) + " total " + vl(total));
        }
        return;
    }
    if (c == "FINISH" || c == "ABORT") { int id = stoi(w[1]); require(id, c == "FINISH"); terminate(id, c == "FINISH" ? "finished" : "aborted"); retry(); }
    else if (c == "CANCEL") {
        int id = stoi(w[1]); require(id, false); const Waiting* entry = waiting(id);
        if (!entry) fail("process " + pn(id) + " is not blocked");
        Vec value = entry->value; state.queue.erase(remove_if(state.queue.begin(), state.queue.end(), [id](const Waiting& r) { return r.id == id; }), state.queue.end()); emit("cancelled " + pn(id) + " " + vl(value)); record("cancelled", id, value);
    } else if (c == "MAXGRANT") {
        int id = stoi(w[1]); Process& p = require(id, true); Vec result(state.total.size()), n = need(p);
        for (size_t i = 0; i < result.size(); ++i) { Vec v(result.size()); for (int amount = n[i]; amount > 0; --amount) { v[i] = amount; if (rejection(p, v).empty() && decision(p, v, false).reason.empty()) { result[i] = amount; break; } } }
        emit("maxgrant " + pn(id) + ": " + vl(result));
    } else if (c == "SAFE") {
        if (state.processes.empty()) emit("safe: no processes");
        else { Check r = check(state.available, false, tracing); emit(r.remaining.empty() ? "safe: " + pl(r.sequence) : "unsafe: " + pl(r.remaining) + " cannot finish"); }
    } else if (c == "SEQUENCES") {
        if (state.processes.empty()) { emit("safe sequences: no processes"); return; }
        int count = 0, limit = stoi(w[1]); Vec path; vector<string> found; set<int> used;
        function<void(Vec)> search = [&](Vec work) {
            if (path.size() == state.processes.size()) { ++count; if (int(found.size()) < limit) found.push_back(pl(path)); return; }
            for (const auto& item : state.processes) if (!used.count(item.first) && fits(need(item.second), work)) { used.insert(item.first); path.push_back(item.first); search(add(work, item.second.allocation)); path.pop_back(); used.erase(item.first); }
        };
        search(state.available); emit("safe sequences: " + to_string(count)); for (const string& line : found) emit(line);
    } else if (c == "DEFICIT") {
        vector<string> values;
        for (size_t i = 0; i < state.total.size(); ++i) {
            int limit = 0; for (const auto& item : state.processes) limit += need(item.second)[i]; string value = "-";
            for (int x = 0; x <= limit; ++x) { Vec work = state.available; work[i] += x; if (check(work, false, false).remaining.empty()) { value = to_string(x); break; } }
            values.push_back(value);
        }
        emit("deficit: (" + join(values, ",") + ")");
    } else if (c == "STATE") showState();
    else if (c == "STATS") stats();
    else if (c == "DETECT") { Vec dead = detect(tracing); emit(dead.empty() ? "no deadlock" : "deadlocked: " + pl(dead)); }
    else if (c == "VICTIMS") {
        Vec dead = detect(false); if (dead.empty()) { emit("no deadlock"); return; }
        vector<Vec> groups;
        for (int mask = 1; mask < (1 << dead.size()); ++mask) { Vec group; for (size_t i = 0; i < dead.size(); ++i) if (mask & (1 << i)) group.push_back(dead[i]); groups.push_back(group); }
        auto held = [](const Vec& ids) { int n = 0; for (int id : ids) n += sum(state.processes.at(id).allocation); return n; };
        sort(groups.begin(), groups.end(), [&](const Vec& a, const Vec& b) { if (a.size() != b.size()) return a.size() < b.size(); int x = held(a), y = held(b); return x != y ? x < y : a < b; });
        for (const Vec& group : groups) if (check(state.available, true, false, set<int>(group.begin(), group.end())).remaining.empty()) { emit("victims: " + pl(group)); break; }
    } else if (c == "RECOVER") {
        Vec dead = detect(tracing); int count = 0;
        if (w.size() > 1) { for (int id : dead) { terminate(id, "aborted"); ++count; } if (count) retry(); }
        else while (!dead.empty()) {
            int victim = dead.front();
            for (int id : dead) {
                const Process& a = state.processes.at(id); const Process& b = state.processes.at(victim); bool better;
                if (policy == "ALLOC") better = sum(a.allocation) < sum(b.allocation) || (sum(a.allocation) == sum(b.allocation) && id > victim);
                else if (policy == "NEED") better = sum(need(a)) > sum(need(b)) || (sum(need(a)) == sum(need(b)) && id > victim);
                else better = a.created > b.created;
                if (better) victim = id;
            }
            terminate(victim, "aborted"); retry(); ++count; dead = detect(tracing);
        }
        emit(count ? "recovered: " + to_string(count) + " aborted" : "no deadlock");
    } else if (c == "WAITGRAPH") graph(false);
    else if (c == "GRAPH") graph(true);
    else if (c == "HISTORY") {
        bool any = false;
        for (const Event& e : state.history) {
            if (w.size() > 1 && !(isdigit(static_cast<unsigned char>(w[1][0])) ? e.id == stoi(w[1]) : e.kind == w[1])) continue;
            emit("t=" + to_string(e.command) + " " + e.kind + " " + pn(e.id) + " " + vl(e.value) + (e.kind == "unblocked" ? " waited " + to_string(e.waited) : "")); any = true;
        }
        if (!any) emit("no events");
    } else if (c == "SNAPSHOT") { snapshots[w[1]] = state; emit("saved " + w[1]); }
    else if (c == "RESTORE") { if (!snapshots.count(w[1])) fail("unknown snapshot " + w[1]); state = snapshots.at(w[1]); emit("restored " + w[1]); }
}
int main() {
    int n; cin >> n; string line; getline(cin, line);
    for (commandNumber = 1; commandNumber <= n; ++commandNumber) {
        getline(cin, line); istringstream input(line); vector<string> words; string word;
        while (input >> word) words.push_back(word);
        try { execute(words); } catch (const runtime_error& error) { emit("error: " + string(error.what())); }
    }
}
