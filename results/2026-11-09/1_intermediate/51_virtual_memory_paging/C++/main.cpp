#include <algorithm>
#include <cctype>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <memory>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
using namespace std;

const vector<string> policies = {"FIFO",  "LRU",    "LFU",     "NRU",    "AGING",
                                 "CLOCK", "ECLOCK", "WSCLOCK", "RANDOM", "OPT"};
vector<string> output;
vector<string> words(const string &line) {
    istringstream input(line);
    vector<string> result;
    string word;
    while (input >> word)
        result.push_back(word);
    return result;
}
string hexAddress(int value) {
    ostringstream s;
    s << "0x" << uppercase << hex << value;
    return s.str();
}
int address(const string &s) {
    return stoi(s.substr(2), nullptr, 16);
}
string decimal(int64_t value) {
    ostringstream s;
    s << value / 100 << '.' << setw(2) << setfill('0') << value % 100;
    return s.str();
}
string ratio(int64_t x, int64_t y) {
    return decimal(y == 0 ? 0 : x * 10000 / y) + "%";
}
bool knownPolicy(const string &p) {
    return find(policies.begin(), policies.end(), p) != policies.end();
}
struct Config {
    int page = 256, frames = 4, tlb = 4, sets = 1, tick = 0, tau = 8;
    int64_t seed = 1;
    string policy = "FIFO", scope = "GLOBAL", asid = "OFF";
    string description() const {
        return "SYSTEM page=" + to_string(page) + " frames=" + to_string(frames) +
               " tlb=" + to_string(tlb) + " sets=" + to_string(sets) + " policy=" + policy +
               " scope=" + scope + " asid=" + asid + " tick=" + to_string(tick) +
               " tau=" + to_string(tau) + " seed=" + to_string(seed);
    }
};
Config settings(const vector<string> &tokens) {
    Config c;
    set<string> seen;
    const set<string> keys = {"page",  "frames", "tlb",  "sets", "policy",
                              "scope", "asid",   "tick", "tau",  "seed"};
    for (size_t i = 1; i < tokens.size(); i++) {
        size_t eq = tokens[i].find('=');
        string key = tokens[i].substr(0, eq), value = tokens[i].substr(eq + 1);
        if (!keys.count(key))
            throw runtime_error("unknown key " + key);
        if (!seen.insert(key).second)
            throw runtime_error("duplicate key " + key);
        bool valid = false;
        if (key == "policy") {
            valid = knownPolicy(value);
            if (valid)
                c.policy = value;
        } else if (key == "scope") {
            valid = value == "GLOBAL" || value == "LOCAL";
            if (valid)
                c.scope = value;
        } else if (key == "asid") {
            valid = value == "ON" || value == "OFF";
            if (valid)
                c.asid = value;
        } else {
            int64_t n = stoll(value);
            if (key == "page")
                valid = n >= 16 && n <= 4096 && (n & (n - 1)) == 0;
            else if (key == "frames")
                valid = n >= 1 && n <= 16;
            else if (key == "tlb" || key == "sets")
                valid = n >= 1 && n <= 8;
            else if (key == "tick")
                valid = n >= 0 && n <= 1000;
            else if (key == "tau")
                valid = n >= 1 && n <= 1000;
            else
                valid = n >= 1 && n <= 2147483646LL;
            if (valid) {
                if (key == "page")
                    c.page = int(n);
                else if (key == "frames")
                    c.frames = int(n);
                else if (key == "tlb")
                    c.tlb = int(n);
                else if (key == "sets")
                    c.sets = int(n);
                else if (key == "tick")
                    c.tick = int(n);
                else if (key == "tau")
                    c.tau = int(n);
                else
                    c.seed = n;
            }
        }
        if (!valid)
            throw runtime_error("invalid " + key);
    }
    if (c.tlb % c.sets != 0)
        throw runtime_error("invalid sets");
    return c;
}
struct Page {
    int pid, number;
    int frame = -1, slot = -1, R = 0, M = 0, load = 0, last = 0, uses = 0, age = 0, references = 0;
    bool ro = false, locked = false, ever = false;
    string label() const {
        return "P" + to_string(pid) + ":" + to_string(number);
    }
};
struct Process {
    int pid, accesses = 0, faults = 0, writebacks = 0, segfaults = 0, protfaults = 0, peak = 0,
             hand = 0;
    bool exited = false;
    vector<Page> pages;
    vector<int> history;
    Process(int pid, int count) : pid(pid) {
        for (int i = 0; i < count; i++)
            pages.push_back(Page{pid, i});
    }
    int resident() const {
        return int(
            count_if(pages.begin(), pages.end(), [](const Page &p) { return p.frame >= 0; }));
    }
};
struct Access {
    int pid;
    string op;
    int address;
};
struct Log {
    string kind;
    int pid;
    string op;
    int a, b;
};
class Simulation {
  public:
    Config c;
    map<int, Process> processes;
    vector<Page *> frames;
    vector<vector<Page *>> tlb;
    map<int, Page *> swap;
    vector<Access> future;
    int cursor = -1, time = 0, faults = 0, zero = 0, swapin = 0, tlbhits = 0, writebacks = 0,
        switches = 0, previous = -1, hand = 0;
    int64_t random;
    bool fixed = false, trace = false, silent;
    vector<bool> faultHistory;
    vector<Log> log;
    Simulation(Config config, vector<Access> references, bool quiet)
        : c(config), frames(c.frames, nullptr), tlb(c.sets), future(move(references)),
          random(c.seed), silent(quiet) {
    }
    void emit(const string &text) {
        if (!silent)
            output.push_back(text);
    }
    Process &process(int pid) {
        auto it = processes.find(pid);
        if (it == processes.end())
            throw runtime_error("unknown process " + to_string(pid));
        if (it->second.exited)
            throw runtime_error("process " + to_string(pid) + " exited");
        return it->second;
    }
    int quota(int pid) const {
        int index = int(distance(processes.begin(), processes.find(pid)));
        return c.frames / int(processes.size()) +
               (index < c.frames % int(processes.size()) ? 1 : 0);
    }
    void declare(int pid, int count) {
        if (fixed)
            throw runtime_error("processes are fixed");
        if (processes.count(pid))
            throw runtime_error("duplicate process " + to_string(pid));
        if (count < 1 || count > 256)
            throw runtime_error("invalid page count");
        if (processes.size() >= 8 || (c.scope == "LOCAL" && int(processes.size()) == c.frames))
            throw runtime_error("too many processes");
        processes.emplace(pid, Process(pid, count));
    }
    void invalidate(Page *page) {
        for (vector<Page *> &set : tlb)
            set.erase(remove(set.begin(), set.end(), page), set.end());
    }
    void write(Page *p) {
        writebacks++;
        processes.at(p->pid).writebacks++;
        p->M = 0;
        if (p->slot < 0) {
            int slot = 0;
            while (swap.count(slot))
                slot++;
            p->slot = slot;
            swap[slot] = p;
        }
    }
    int nextUse(const Page *p) const {
        for (int i = cursor + 1; i < int(future.size()); i++) {
            const Access &a = future[i];
            if (a.pid == p->pid && a.address / c.page == p->number)
                return i;
        }
        return numeric_limits<int>::max();
    }
    int choose(vector<int> candidates, Process &owner) {
        vector<int> unlocked;
        for (int f : candidates)
            if (!frames[f]->locked)
                unlocked.push_back(f);
        if (!unlocked.empty())
            candidates = unlocked;
        if (c.policy == "RANDOM") {
            random = random * 48271LL % 2147483647LL;
            return candidates[random % candidates.size()];
        }
        if (c.policy != "CLOCK" && c.policy != "ECLOCK" && c.policy != "WSCLOCK") {
            auto rank = [&](int f) -> pair<int, int> {
                const Page &p = *frames[f];
                if (c.policy == "FIFO")
                    return {p.load, 0};
                if (c.policy == "LRU")
                    return {p.last, 0};
                if (c.policy == "LFU")
                    return {p.uses, p.load};
                if (c.policy == "NRU")
                    return {2 * p.R + p.M, f};
                if (c.policy == "AGING")
                    return {p.age, p.load};
                return {-nextUse(&p), f};
            };
            return *min_element(candidates.begin(), candidates.end(),
                                [&](int a, int b) { return rank(a) < rank(b); });
        }
        int h = c.scope == "GLOBAL" ? hand : owner.hand;
        sort(candidates.begin(), candidates.end(), [&](int a, int b) {
            return (a - h + c.frames) % c.frames < (b - h + c.frames) % c.frames;
        });
        int chosen = -1;
        if (c.policy == "CLOCK") {
            while (chosen < 0)
                for (int f : candidates) {
                    if (frames[f]->R == 0) {
                        chosen = f;
                        break;
                    }
                    frames[f]->R = 0;
                }
        } else if (c.policy == "ECLOCK") {
            while (chosen < 0) {
                for (int f : candidates)
                    if (frames[f]->R == 0 && frames[f]->M == 0) {
                        chosen = f;
                        break;
                    }
                if (chosen >= 0)
                    break;
                for (int f : candidates) {
                    if (frames[f]->R == 0 && frames[f]->M == 1) {
                        chosen = f;
                        break;
                    }
                    frames[f]->R = 0;
                }
            }
        } else {
            for (int f : candidates) {
                Page *p = frames[f];
                if (p->R == 1) {
                    p->R = 0;
                    p->last = time;
                } else if (time - p->last > c.tau) {
                    if (p->M == 0) {
                        chosen = f;
                        break;
                    }
                    write(p);
                }
            }
            if (chosen < 0) {
                for (int f : candidates)
                    if (frames[f]->M == 0) {
                        chosen = f;
                        break;
                    }
                if (chosen < 0)
                    chosen = candidates[0];
            }
        }
        if (c.scope == "GLOBAL")
            hand = (chosen + 1) % c.frames;
        else
            owner.hand = (chosen + 1) % c.frames;
        return chosen;
    }
    void access(int pid, const string &op, int addr) {
        fixed = true;
        cursor++;
        Process &owner = process(pid);
        if (addr >= int(owner.pages.size()) * c.page) {
            owner.segfaults++;
            emit("SEGFAULT P" + to_string(pid) + " " + hexAddress(addr));
            return;
        }
        Page *p = &owner.pages[addr / c.page];
        if (op == "W" && p->ro) {
            owner.protfaults++;
            emit("PROTFAULT P" + to_string(pid) + " " + hexAddress(addr));
            return;
        }
        time++;
        owner.accesses++;
        bool switched = previous >= 0 && previous != pid;
        if (switched) {
            switches++;
            if (c.asid == "OFF")
                for (vector<Page *> &set : tlb)
                    set.clear();
        }
        previous = pid;
        vector<Page *> &set = tlb[p->number % c.sets];
        auto found = find(set.begin(), set.end(), p);
        bool hit = found != set.end(), fault = false;
        if (hit)
            set.erase(found);
        string result;
        if (hit) {
            tlbhits++;
            result = "TLBHIT";
        } else if (p->frame >= 0)
            result = "HIT";
        else {
            fault = true;
            faults++;
            owner.faults++;
            if (p->slot >= 0) {
                swapin++;
                result = "FAULT SWAPIN";
            } else {
                zero++;
                result = "FAULT ZERO";
            }
            int frame = -1;
            bool mayUseFree = c.scope == "GLOBAL" || owner.resident() < quota(pid);
            if (mayUseFree)
                for (int i = 0; i < c.frames; i++)
                    if (frames[i] == nullptr) {
                        frame = i;
                        break;
                    }
            if (frame < 0) {
                vector<int> candidates;
                for (int i = 0; i < c.frames; i++)
                    if (frames[i] && (c.scope == "GLOBAL" || frames[i]->pid == pid))
                        candidates.push_back(i);
                frame = choose(candidates, owner);
                Page *victim = frames[frame];
                result += " evict=" + victim->label();
                invalidate(victim);
                if (victim->M == 1) {
                    write(victim);
                    result += " writeback";
                }
                victim->frame = -1;
            }
            frames[frame] = p;
            p->frame = frame;
            p->load = time;
            p->uses = 0;
            p->M = 0;
            p->age = 0;
            owner.peak = max(owner.peak, owner.resident());
        }
        if (int(set.size()) == c.tlb / c.sets)
            set.erase(set.begin());
        set.push_back(p);
        p->R = 1;
        if (op == "W")
            p->M = 1;
        p->last = time;
        p->uses++;
        p->ever = true;
        p->references++;
        owner.history.push_back(p->number);
        faultHistory.push_back(fault);
        log.push_back({"ACCESS", pid, op, addr, 0});
        bool interrupt = c.tick > 0 && time % c.tick == 0;
        if (interrupt)
            for (Page *page : frames)
                if (page) {
                    page->age = page->age / 2 + 128 * page->R;
                    page->R = 0;
                }
        if (trace) {
            emit("t=" + to_string(time) + " P" + to_string(pid) + " " + op + " " +
                 hexAddress(addr) + " page=" + to_string(p->number) + " frame=" +
                 to_string(p->frame) + " phys=" + hexAddress(p->frame * c.page + addr % c.page) +
                 " " + result + (switched ? " switch" : ""));
            if (interrupt)
                emit("t=" + to_string(time) + " tick");
        }
    }
    void exitProcess(int pid) {
        Process &p = process(pid);
        int count = 0, slots = 0;
        for (Page &page : p.pages) {
            if (page.frame >= 0) {
                frames[page.frame] = nullptr;
                page.frame = -1;
                count++;
            }
            invalidate(&page);
            if (page.slot >= 0) {
                swap.erase(page.slot);
                page.slot = -1;
                slots++;
            }
        }
        p.exited = true;
        log.push_back({"EXIT", pid, "", 0, 0});
        emit("EXIT P" + to_string(pid) + " freed=" + to_string(count) +
             " slots=" + to_string(slots));
    }
    void attributes(const string &cmd, int pid, int first, int last, const string &protection) {
        Process &p = process(pid);
        if (first > last || last >= int(p.pages.size()))
            throw runtime_error("invalid page range");
        for (int i = first; i <= last; i++) {
            if (cmd == "PROTECT")
                p.pages[i].ro = protection == "RO";
            else
                p.pages[i].locked = cmd == "LOCK";
        }
        if (cmd != "PROTECT")
            log.push_back({cmd, pid, "", first, last});
    }
    void clean() {
        int count = 0;
        for (Page *p : frames)
            if (p && p->M == 1) {
                write(p);
                count++;
            }
        log.push_back({"CLEAN", 0, "", 0, 0});
        emit("CLEAN written=" + to_string(count));
    }
    unique_ptr<Simulation> rerun(const string &policy, int count) {
        Config config = c;
        config.policy = policy;
        config.frames = count;
        vector<Access> references;
        for (const Log &e : log)
            if (e.kind == "ACCESS")
                references.push_back({e.pid, e.op, e.a});
        auto replay = make_unique<Simulation>(config, references, true);
        for (const auto &entry : processes)
            replay->declare(entry.first, int(entry.second.pages.size()));
        for (const Log &e : log) {
            if (e.kind == "ACCESS")
                replay->access(e.pid, e.op, e.a);
            else if (e.kind == "EXIT")
                replay->exitProcess(e.pid);
            else if (e.kind == "CLEAN")
                replay->clean();
            else
                replay->attributes(e.kind, e.pid, e.a, e.b, "");
        }
        return replay;
    }
    void summary() {
        emit("SUMMARY policy=" + c.policy + " scope=" + c.scope + " time=" + to_string(time));
        int seg = 0, prot = 0;
        for (const auto &entry : processes) {
            seg += entry.second.segfaults;
            prot += entry.second.protfaults;
        }
        emit("total faults=" + to_string(faults) + " zero=" + to_string(zero) +
             " swapin=" + to_string(swapin) + " faultrate=" + ratio(faults, time) +
             " tlbhits=" + to_string(tlbhits) + " tlbrate=" + ratio(tlbhits, time) +
             " writebacks=" + to_string(writebacks) + " switches=" + to_string(switches) +
             " segfaults=" + to_string(seg) + " protfaults=" + to_string(prot));
        for (const auto &entry : processes) {
            const Process &p = entry.second;
            emit("P" + to_string(p.pid) + " accesses=" + to_string(p.accesses) +
                 " faults=" + to_string(p.faults) + " writebacks=" + to_string(p.writebacks) +
                 " segfaults=" + to_string(p.segfaults) + " protfaults=" + to_string(p.protfaults) +
                 " resident=" + to_string(p.resident()) + " peak=" + to_string(p.peak) +
                 (c.scope == "LOCAL" ? " quota=" + to_string(quota(p.pid)) : "") +
                 (p.exited ? " exited" : ""));
        }
    }
    void frameDump() {
        int used =
            int(count_if(frames.begin(), frames.end(), [](Page *p) { return p != nullptr; }));
        emit("FRAMES used=" + to_string(used) + "/" + to_string(c.frames));
        for (int i = 0; i < c.frames; i++) {
            Page *p = frames[i];
            if (!p)
                emit(to_string(i) + " free");
            else
                emit(to_string(i) + " " + p->label() + " R=" + to_string(p->R) +
                     " M=" + to_string(p->M) + " load=" + to_string(p->load) +
                     " last=" + to_string(p->last) + " uses=" + to_string(p->uses) +
                     " age=" + to_string(p->age) + (p->locked ? " locked" : ""));
        }
        if (c.policy == "CLOCK" || c.policy == "ECLOCK" || c.policy == "WSCLOCK") {
            if (c.scope == "GLOBAL")
                emit("hand=" + to_string(hand));
            else {
                string text = "hand";
                for (const auto &entry : processes)
                    text += " P" + to_string(entry.first) + "=" + to_string(entry.second.hand);
                emit(text);
            }
        }
    }
    void pageTable(int pid) {
        Process &p = process(pid);
        emit("PAGETABLE P" + to_string(pid) + " pages=" + to_string(p.pages.size()) +
             " resident=" + to_string(p.resident()));
        for (const Page &page : p.pages)
            if (page.ever) {
                string info = page.frame >= 0
                                  ? "frame=" + to_string(page.frame) + " R=" + to_string(page.R) +
                                        " M=" + to_string(page.M)
                              : page.slot >= 0 ? "swap=" + to_string(page.slot)
                                               : "zero";
                emit(to_string(page.number) + " " + info + (page.ro ? " RO" : "") +
                     (page.locked ? " locked" : ""));
            }
    }
    void tlbDump() {
        int used = 0;
        for (const auto &set : tlb)
            used += int(set.size());
        emit("TLB used=" + to_string(used) + "/" + to_string(c.tlb) + " sets=" + to_string(c.sets));
        for (int i = 0; i < c.sets; i++) {
            string text = "set " + to_string(i) + ":";
            for (auto it = tlb[i].rbegin(); it != tlb[i].rend(); ++it)
                text += " " + (*it)->label() + "->" + to_string((*it)->frame);
            emit(text);
        }
    }
    void compare() {
        emit("COMPARE accesses=" + to_string(time) + " frames=" + to_string(c.frames));
        map<string, pair<int, int>> scores;
        for (const string &policy : policies) {
            auto r = rerun(policy, c.frames);
            scores[policy] = {r->faults, r->writebacks};
            emit(policy + " faults=" + to_string(r->faults) +
                 " writebacks=" + to_string(r->writebacks) + " tlbhits=" + to_string(r->tlbhits));
        }
        vector<string> ranking = policies;
        stable_sort(ranking.begin(), ranking.end(),
                    [&](const string &a, const string &b) { return scores[a] < scores[b]; });
        string text = "ranking";
        for (const string &p : ranking)
            text += " " + p;
        emit(text);
    }
    void execute(const vector<string> &t) {
        string cmd = t[0];
        if (isdigit(static_cast<unsigned char>(cmd[0]))) {
            access(stoi(cmd), t[1], address(t[2]));
            return;
        }
        if (cmd == "PROCESS")
            declare(stoi(t[1]), stoi(t[2]));
        else if (cmd == "EXIT")
            exitProcess(stoi(t[1]));
        else if (cmd == "PROTECT" || cmd == "LOCK" || cmd == "UNLOCK")
            attributes(cmd, stoi(t[1]), stoi(t[2]), stoi(t[3]), t.size() > 4 ? t[4] : "");
        else if (cmd == "TRACE")
            trace = t[1] == "ON";
        else if (cmd == "SUMMARY")
            summary();
        else if (cmd == "FRAMES")
            frameDump();
        else if (cmd == "PAGETABLE")
            pageTable(stoi(t[1]));
        else if (cmd == "TLB")
            tlbDump();
        else if (cmd == "SWAP") {
            emit("SWAP used=" + to_string(swap.size()));
            for (const auto &entry : swap)
                emit(to_string(entry.first) + " " + entry.second->label());
        } else if (cmd == "CLEAN")
            clean();
        else if (cmd == "COMPARE")
            compare();
        else if (cmd == "CURVE") {
            string policy = t[1];
            int lo = stoi(t[2]), hi = stoi(t[3]);
            if (!knownPolicy(policy))
                throw runtime_error("unknown policy");
            if (lo < 1 || lo > hi || hi > 16 || (c.scope == "LOCAL" && lo < int(processes.size())))
                throw runtime_error("invalid frame range");
            emit("CURVE " + policy + " frames=" + to_string(lo) + ".." + to_string(hi));
            int prior = numeric_limits<int>::max();
            for (int f = lo; f <= hi; f++) {
                int value = rerun(policy, f)->faults;
                emit("F=" + to_string(f) + " faults=" + to_string(value) +
                     (value > prior ? " ANOMALY" : ""));
                prior = value;
            }
        } else if (cmd == "EAT") {
            int64_t total = stoll(t[1]) * time + stoll(t[2]) * (2LL * time - tlbhits) +
                            stoll(t[3]) * (swapin + writebacks);
            emit(time == 0 ? "EAT accesses=0"
                           : "EAT accesses=" + to_string(time) + " total=" + to_string(total) +
                                 " average=" + decimal(total * 100 / time));
        } else if (cmd == "TIMELINE") {
            int w = stoi(t[1]);
            if (w < 1)
                throw runtime_error("invalid window");
            string text = "TIMELINE window=" + to_string(w);
            for (int i = 0; i < int(faultHistory.size()); i += w) {
                int count = 0;
                for (int j = i; j < min(i + w, int(faultHistory.size())); j++)
                    if (faultHistory[j])
                        count++;
                text += " " + to_string(count);
            }
            emit(text);
        } else if (cmd == "WSET") {
            int pid = stoi(t[1]);
            Process &p = process(pid);
            int w = stoi(t[2]);
            if (w < 1)
                throw runtime_error("invalid window");
            set<int> pages(p.history.begin() + max(0, int(p.history.size()) - w), p.history.end());
            string text = "WSET P" + to_string(pid) + " window=" + to_string(w) +
                          " size=" + to_string(pages.size());
            for (int page : pages)
                text += " " + to_string(page);
            emit(text);
        } else if (cmd == "HOT") {
            int pid = stoi(t[1]);
            Process &p = process(pid);
            int k = stoi(t[2]);
            if (k < 1)
                throw runtime_error("invalid count");
            vector<Page *> pages;
            for (Page &page : p.pages)
                if (page.references > 0)
                    pages.push_back(&page);
            sort(pages.begin(), pages.end(), [](Page *a, Page *b) {
                return a->references != b->references ? a->references > b->references
                                                      : a->number < b->number;
            });
            string text = "HOT P" + to_string(pid);
            for (int i = 0; i < min(k, int(pages.size())); i++)
                text += " " + to_string(pages[i]->number) + ":" + to_string(pages[i]->references);
            emit(text);
        }
    }
};
int main() {
    int n;
    cin >> n;
    string line;
    getline(cin, line);
    vector<vector<string>> commands;
    for (int i = 0; i < n; i++) {
        getline(cin, line);
        vector<string> t = words(line);
        if (t[0] == "LOOP") {
            int start = address(t[3]), interval = stoi(t[4]), length = stoi(t[5]),
                repeats = stoi(t[6]);
            for (int r = 0; r < repeats; r++)
                for (int j = 0; j < length; j++)
                    commands.push_back({t[1], t[2], hexAddress(start + j * interval)});
        } else if (t[0] == "RAND") {
            int lo = address(t[2]), hi = address(t[3]), count = stoi(t[4]), rate = stoi(t[6]);
            int64_t x = stoll(t[5]);
            for (int j = 0; j < count; j++) {
                x = x * 48271LL % 2147483647LL;
                int addr = lo + int(x % (hi - lo));
                x = x * 48271LL % 2147483647LL;
                commands.push_back({t[1], x % 100 < rate ? "W" : "R", hexAddress(addr)});
            }
        } else
            commands.push_back(t);
    }
    unique_ptr<Simulation> simulation;
    for (int i = 0; i < int(commands.size()); i++) {
        const vector<string> &t = commands[i];
        try {
            if (t[0] == "SYSTEM") {
                simulation.reset();
                Config c = settings(t);
                vector<Access> future;
                for (int j = i + 1; j < int(commands.size()) && commands[j][0] != "SYSTEM"; j++) {
                    const vector<string> &entry = commands[j];
                    if (isdigit(static_cast<unsigned char>(entry[0][0])))
                        future.push_back({stoi(entry[0]), entry[1], address(entry[2])});
                }
                simulation = make_unique<Simulation>(c, future, false);
                output.push_back(c.description());
            } else if (!simulation)
                output.push_back("ERROR no system");
            else
                simulation->execute(t);
        } catch (const runtime_error &e) {
            output.push_back("ERROR " + string(e.what()));
        }
    }
    for (const string &text : output)
        cout << text << '\n';
}
