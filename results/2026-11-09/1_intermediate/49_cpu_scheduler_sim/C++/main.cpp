#include <cstdlib>
#include <utility>
#include <algorithm>
#include <array>
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
using Integer  =  long long;
using Parameters  =  map<string, Integer>;
const vector<string> algorithms {
    "FCFS","SJF","SRTF","RR","PRIORITY","HRRN","EDF","LOTTERY","MLFQ"
};
const vector<string> parameterKeys {
    "cs","q","k","s","seed"
};
const map<string, pair<Integer, Integer>> ranges {
    {
        "cs", {
            0, 5
        }
    }, {
        "q", {
            1, 20
        }
    }, {
        "k", {
            1, 50
        }
    }, {
        "s", {
            0, 500
        }
    }, {
        "seed", {
            1, 2147483646
        }
    }
};
const map<string, vector<string>> used {
    {
        "FCFS", {
            "cs"
        }
    }, {
        "SJF", {
            "cs"
        }
    }, {
        "SRTF", {
            "cs"
        }
    }, {
        "RR", {
            "cs","q"
        }
    }, {
        "PRIORITY", {
            "cs","k"
        }
    }, {
        "HRRN", {
            "cs"
        }
    }, {
        "EDF", {
            "cs"
        }
    }, {
        "LOTTERY", {
            "cs","q","seed"
        }
    }, {
        "MLFQ", {
            "cs","s"
        }
    }
};
const vector<string> metricNames {
    "turnaround","waiting","response"
};
string num(Integer n) {
    return to_string(n);
}
bool contains(const vector<string>& xs, const string& x) {
    return find(xs.begin(), xs.end(), x) != xs.end();
}
void require(bool bad, const string& message) {
    if (bad)throw runtime_error(message);
}
string truncated(Integer u, Integer v) {
    Integer c = 100*u/v;
    return num(c/100)+"."+(c%100<10?"0":"")+num(c%100);
}
vector<string> split(const string& line) {
    istringstream input(line);
    vector<string> words;
    string word;
    while (input>>word)words.push_back(word);
    return words;
}
Parameters parameters(const vector<string>& words, const string& algo = "", const string& preset = "") {
    Parameters p {
        {
            "cs", 0
        }, {
            "q", 4
        }, {
            "k", 5
        }, {
            "s", 0
        }, {
            "seed", 1
        }
    };
    set<string> seen;
    if (!preset.empty())seen.insert(preset);
    for (const string& word:words) {
        size_t at = word.find('=');
        string key = word.substr(0, at);
        Integer value = stoll(word.substr(at+1));
        require(!ranges.count(key),"unknown key "+key);
        require(!algo.empty() && !contains(used.at(algo), key),"key "+key+" not allowed for "+algo);
        require(seen.count(key),"duplicate key "+key);
        auto [lo, hi] = ranges.at(key);
        require(value<lo || value>hi,"invalid "+key);
        seen.insert(key);
        p[key] = value;
    }
    return p;
}
string notation(const Parameters& p, const string& algo = "") {
    string s;
    for (const string& k:algo.empty()?parameterKeys:used.at(algo)) {
        if (!s.empty())s += ' ';
        s += k+"="+num(p.at(k));
    }
    return s;
}
struct Process {
    string id;
    int arrival, priority, deadline = -1;
    vector<int> bursts;
};
struct Burst {
    int length, ready, start = -1, end = -1, slices = 0;
};
struct Job {
    Process process;
    string state = "FUTURE";
    int burst = 0, left, effective, wait = 0, level = 0, usage = 0, enqueue = 0, start = -1, finish = -1;
    vector<Burst> records;
    string timeline;
};
array<Integer, 3> metrics(const Job& j) {
    Integer turnaround = j.finish-j.process.arrival;
    return {
        turnaround, turnaround-accumulate(j.process.bursts.begin(), j.process.bursts.end(), 0), j.start-j.process.arrival
    };
}
struct Result {
    vector<Job> jobs;
    vector<string> labels, events, snapshot;
    vector<string> modes;
    map<string, int> counts;
    vector<int> queueLengths;
    int switches = 0, end = 0, busy = 0, switching = 0, idle = 0, met = 0, missed = 0;
    array<Integer, 3> totals {
    };
};
class Simulation {
    string algo, cpu = "IDLE";
    Parameters p;
    Result r;
    array<vector<int>, 3> queues;
    int current = -1, previous = -1, switchLeft = 0, runLength = 0, time = 0, snapshotTime;
    Integer random;
    vector<int> ready() const {
        vector<int> result;
        for (const vector<int>& q:queues)result.insert(result.end(), q.begin(), q.end());
        return result;
    }
    void event(const string& name, const string& detail = "") {
        r.events.push_back(num(time)+" "+name+(detail.empty()?"":" "+detail));
        ++r.counts[name];
    }
    void enqueue(int i) {
        Job& j = r.jobs[i];
        j.state = "READY";
        j.enqueue = time;
        queues[algo == "MLFQ"?j.level:0].push_back(i);
    }
    void fresh(int i) {
        Job& j = r.jobs[i];
        j.records.push_back({
            j.left, time
        });
        enqueue(i);
    }
    void start() {
        Job& j = r.jobs[current];
        cpu = "RUN";
        j.state = "RUN";
        runLength = 0;
        if (j.start<0)j.start = time;
        if (j.records.back().start<0)j.records.back().start = time;
    }
    int absolute(int i) const {
        const Process& process = r.jobs[i].process;
        return process.deadline<0?2147483647:process.arrival+process.deadline;
    }
    vector<string> snapshot() const {
        vector<string> output {
            cpu == "IDLE"?"CPU IDLE":"CPU "+cpu+" "+r.jobs[current].process.id
        };
        for (int q = 0;q<(algo == "MLFQ"?3:1);++q) {
            string s = "QUEUE"+(algo == "MLFQ"?num(q):"")+" ";
            if (queues[q].empty())s += "none";
            else for (int i:queues[q]) {
                if (s.back() != ' ')s += ' ';
                s += r.jobs[i].process.id;
            }
            output.push_back(s);
        }
        for (const Job& j:r.jobs) {
            string s = j.process.id+" "+j.state;
            if (j.state == "FUTURE")s += " at="+num(j.process.arrival);
            else if (j.state == "DONE")s += " at="+num(j.finish);
            else {
                s += " burst="+num(j.burst+1)+" left="+num(j.left);
                if (algo == "PRIORITY")s += " prio="+num(j.effective);
                if (algo == "MLFQ")s += " level="+num(j.level)+" used="+num(j.usage);
            }
            output.push_back(s);
        }
        return output;
    }
    bool preempts() const {
        const Job& j = r.jobs[current];
        for (int i:ready()) {
            const Job& q = r.jobs[i];
            if (algo == "SRTF" && q.left<j.left)return true;
            if (algo == "PRIORITY" && q.effective<j.effective)return true;
            if (algo == "EDF" && absolute(i)<absolute(current))return true;
            if (algo == "MLFQ" && q.level<j.level)return true;
        }
        return false;
    }
    int select() {
        vector<int> list = ready();
        int chosen = list[0];
        if (algo == "LOTTERY") {
            random = random*48271%2147483647;
            int tickets = 0;
            for (int i:list)tickets += 10-r.jobs[i].process.priority;
            Integer draw = random%tickets;
            for (int i:list) {
                draw -= 10-r.jobs[i].process.priority;
                if (draw<0)return i;
            }
        }
        for (int i:list) {
            const Job& a = r.jobs[i];
            const Job& b = r.jobs[chosen];
            bool better = false;
            if (algo == "SJF" || algo == "SRTF")better = a.left<b.left;
            else if (algo == "PRIORITY")better = a.effective<b.effective;
            else if (algo == "HRRN")better = (Integer)(time-a.enqueue+a.left)*b.left>(Integer)(time-b.enqueue+b.left)*a.left;
            else if (algo == "EDF")better = absolute(i)<absolute(chosen);
            if (better)chosen = i;
        }
        return chosen;
    }
    public:
    Simulation(const vector<Process>& processes, string algorithm, Parameters params, int snapshotAt = -1):algo(std::move(algorithm)),
    p(std::move(params)), snapshotTime(snapshotAt), random(p.at("seed")) {
        for (const Process& process:processes) {
            Job j;
            j.process = process;
            j.left = process.bursts[0];
            j.effective = process.priority;
            r.jobs.push_back(j);
        }
    }
    Result run() {
        for (time = 0;;++time) {
            if (algo == "PRIORITY")for (int i:queues[0]) {
                Job& j = r.jobs[i];
                if (++j.wait == p["k"]) {
                    j.wait = 0;
                    if (j.effective)event("AGE", j.process.id+" "+num(--j.effective));
                }
            }
            for (int i = 0;i<(int)r.jobs.size();++i) {
                Job& j = r.jobs[i];
                if (j.state == "IO" && !j.left) {
                    ++j.burst;
                    j.left = j.process.bursts[j.burst];
                    fresh(i);
                    event("IODONE", j.process.id);
                }
            }
            for (int i = 0;i<(int)r.jobs.size();++i) {
                Job& j = r.jobs[i];
                if (j.state == "FUTURE" && j.process.arrival == time) {
                    fresh(i);
                    event("ARRIVE", j.process.id);
                }
            }
            if (cpu == "SWITCH" && !switchLeft) {
                start();
                event("START", r.jobs[current].process.id);
            }
            else if (cpu == "RUN") {
                Job& j = r.jobs[current];
                if (!j.left && j.burst == (int)j.process.bursts.size()-1) {
                    j.state = "DONE";
                    j.finish = time;
                    event("DONE", j.process.id);
                    cpu = "IDLE";
                }
                else {
                    bool demoted = false;
                    if (algo == "MLFQ" && j.level<2 && j.usage == (j.level == 0?4:8)) {
                        ++j.level;
                        j.usage = 0;
                        demoted = true;
                        event("DEMOTE", j.process.id+" "+num(j.level));
                    }
                    if (!j.left) {
                        ++j.burst;
                        j.left = j.process.bursts[j.burst];
                        j.state = "IO";
                        cpu = "IDLE";
                        event("IO", j.process.id+" "+num(j.left));
                    }
                    else if (demoted) {
                        enqueue(current);
                        cpu = "IDLE";
                    }
                    else if ((algo == "RR" || algo == "LOTTERY") && runLength == p["q"]) {
                        enqueue(current);
                        cpu = "IDLE";
                        event("EXPIRE", j.process.id);
                    }
                    else if (preempts()) {
                        enqueue(current);
                        cpu = "IDLE";
                        event("PREEMPT", j.process.id);
                    }
                }
            }
            if (all_of(r.jobs.begin(), r.jobs.end(), [](const Job& j) {
                return j.state == "DONE";
            })) {
                r.end = time;
                if (r.snapshot.empty() && snapshotTime >= 0)r.snapshot = snapshot();
                break;
            }
            if (algo == "MLFQ" && p["s"] && time>0 && time%p["s"] == 0) {
                vector<int> all = ready();
                queues[0] = all;
                queues[1].clear();
                queues[2].clear();
                for (Job& j:r.jobs) {
                    j.level = 0;
                    j.usage = 0;
                }
                event("BOOST");
            }
            if (cpu == "IDLE" && !ready().empty()) {
                current = select();
                Job& j = r.jobs[current];
                vector<int>& q = queues[algo == "MLFQ"?j.level:0];
                q.erase(find(q.begin(), q.end(), current));
                j.effective = j.process.priority;
                j.wait = 0;
                ++j.records.back().slices;
                bool change = current != previous;
                if (change)++r.switches;
                if (change && p["cs"]) {
                    cpu = "SWITCH";
                    j.state = "SWITCH";
                    switchLeft = (int)p["cs"];
                    event("SWITCH", j.process.id);
                } else {
                    start();
                    event("DISPATCH", j.process.id);
                }
            }
            if (time == snapshotTime)r.snapshot = snapshot();
            r.queueLengths.push_back((int)ready().size());
            r.modes.push_back(cpu);
            for (Job& j:r.jobs)j.timeline += j.state == "RUN"?'#':j.state == "SWITCH"?'s':j.state == "READY"?'.':j.state == "IO"?'i':'-';
            if (cpu == "RUN") {
                Job& j = r.jobs[current];
                --j.left;
                ++runLength;
                ++j.usage;
                previous = current;
                r.labels.push_back(j.process.id);
                ++r.busy;
                if (!j.left)j.records.back().end = time+1;
            }
            else if (cpu == "SWITCH") {
                --switchLeft;
                r.labels.push_back("CS");
                ++r.switching;
            } else {
                r.labels.push_back("IDLE");
                ++r.idle;
            }
            for (Job& j:r.jobs)if (j.state == "IO")--j.left;
        }
        for (const Job& j:r.jobs) {
            array<Integer, 3> m = metrics(j);
            for (int k = 0;k<3;++k)r.totals[k] += m[k];
            if (j.process.deadline >= 0) {
                if (j.finish <= j.process.arrival+j.process.deadline)++r.met;
                else ++r.missed;
            }
        }
        return r;
    }
};
string describe(const Process& p) {
    string s = p.id+" arrival="+num(p.arrival)+" priority="+num(p.priority)+" deadline="+(p.deadline<0?"none":num(p.deadline))+" bursts=";
    for (int i = 0;i<(int)p.bursts.size();++i) {
        if (i)s += ',';
        s += (i%2?"I":"C")+num(p.bursts[i]);
    }
    return s;
}
void tableRow(const vector<string>& columns) {
    cout<<left<<setw(8)<<columns[0];
    for (int i = 1;i<(int)columns.size();++i)cout<<' '<<right<<setw(8)<<columns[i];
    cout<<'\n';
}
class Scheduler {
    map<string, Process> registry;
    vector<Process> processes() const {
        vector<Process> ps;
        for (const auto& entry:registry)ps.push_back(entry.second);
        return ps;
    }
    Process& process(const string& id) {
        auto it = registry.find(id);
        require(it == registry.end(),"unknown process "+id);
        return it->second;
    }
    string util(const Result& r) const {
        return truncated(r.busy*100, r.end);
    }
    string average(const Result& r, int k) const {
        return truncated(r.totals[k], registry.size());
    }
    void single(const string& c, const string& algo, const vector<string>& a, const Parameters& p, const vector<Process>& ps) {
        Result r = Simulation(ps, algo, p, c == "SNAPSHOT"?stoi(a[1]):-1).run();
        string header = c+" "+algo+" "+notation(p, algo);
        if (c == "TIMELINE") {
            require(r.end>100,"too long "+num(r.end));
            cout<<header<<" end="<<r.end<<'\n';
            for (const Job& j:r.jobs)cout<<left<<setw(8)<<j.process.id<<' '<<j.timeline<<'\n';
            return;
        }
        if (c == "SNAPSHOT") {
            cout<<header<<" t="<<a[1]<<'\n';
            for (const string& line:r.snapshot)cout<<line<<'\n';
            return;
        }
        cout<<header<<'\n';
        if (c == "TRACE") {
            for (const string& e:r.events)cout<<e<<'\n';
            cout<<"END "<<r.end<<'\n';
        }
        else if (c == "BURSTS") {
            for (const Job& j:r.jobs)for (int i = 0;i<(int)j.records.size();++i) {
                const Burst& b = j.records[i];
                cout<<j.process.id<<" #"<<i+1<<" len="<<b.length<<" ready="<<b.ready<<" start="<<b.start<<" end="<<b.end<<" wait="
                <<b.end-b.ready-b.length<<" slices="<<b.slices<<'\n';
            }
        }
        else if (c == "WINDOW") {
            int w = stoi(a[1]);
            for (int start = 0;start<r.end;start += w) {
                int end = min(start+w, r.end), busy = 0, sw = 0, idle = 0;
                map<string, int> counts;
                for (int t = start;t<end;++t) {
                    const string& label = r.labels[t];
                    if (r.modes[t] == "SWITCH")++sw;
                    else if (r.modes[t] == "IDLE")++idle;
                    else {
                        ++busy;
                        ++counts[label];
                    }
                }
                string top = "none";
                int count = 0;
                for (const auto& entry:counts)if (entry.second>count) {
                    top = entry.first;
                    count = entry.second;
                }
                cout<<start<<'-'<<end<<" busy="<<busy<<" switch="<<sw<<" idle="<<idle<<" util="<<truncated(busy*100, end-start)
                <<" top="<<top<<'\n';
            }
        }
        else if (c == "STATS") {
            for (int k = 0;k<3;++k) {
                vector<Integer> vs;
                for (const Job& j:r.jobs)vs.push_back(metrics(j)[k]);
                vector<Integer> sorted = vs;
                sort(sorted.begin(), sorted.end());
                int n = (int)vs.size(), lo = (int)(min_element(vs.begin(), vs.end())-vs.begin()), hi = (int)(max_element(vs.begin(), vs.end())-vs.begin());
                Integer doubled = n%2?2*sorted[n/2]:sorted[n/2-1]+sorted[n/2];
                cout<<metricNames[k]<<" min="<<vs[lo]<<" ("<<ps[lo].id<<") max="<<vs[hi]<<" ("<<ps[hi].id<<") median="<<doubled/2
                <<'.'<<(doubled%2?5:0)<<" total="<<r.totals[k]<<'\n';
            }
        }
        else if (c == "RUN") {
            vector<string> segments;
            for (int t = 0;t<r.end;) {
                int end = t+1;
                while (end<r.end && r.labels[end] == r.labels[t])++end;
                segments.push_back("["+num(t)+"-"+num(end)+" "+r.labels[t]+"]");
                t = end;
            }
            for (int i = 0;i<(int)segments.size();i += 8) {
                cout<<"GANTT ";
                for (int j = i;j<min(i+8, (int)segments.size());++j)cout<<segments[j];
                cout<<'\n';
            }
            for (const Job& j:r.jobs) {
                array<Integer, 3> m = metrics(j);
                int slices = 0;
                for (const Burst& b:j.records)slices += b.slices;
                cout<<j.process.id<<" arrival="<<j.process.arrival<<" done="<<j.finish<<" turnaround="<<m[0]<<" waiting="<<m[1]
                <<" response="<<m[2]<<" slices="<<slices;
                if (j.process.deadline >= 0) {
                    int deadline = j.process.arrival+j.process.deadline;
                    cout<<" deadline="<<deadline<<" late="<<max(0, j.finish-deadline);
                }
                cout<<'\n';
            }
            cout<<"AVERAGE turnaround="<<average(r, 0)<<" waiting="<<average(r, 1)<<" response="<<average(r, 2)<<'\n';
            cout<<"CPU end="<<r.end<<" busy="<<r.busy<<" switch="<<r.switching<<" idle="<<r.idle<<" switches="<<r.switches
            <<" util="<<util(r)<<'\n';
            cout<<"QUEUE max="<<*max_element(r.queueLengths.begin(), r.queueLengths.end())<<" avg="<<truncated(accumulate(r.queueLengths.begin(),
            r.queueLengths.end(), 0LL), r.end)<<'\n';
            cout<<"EVENTS preempt="<<r.counts["PREEMPT"]<<" expire="<<r.counts["EXPIRE"]<<" demote="<<r.counts["DEMOTE"]
            <<" boost="<<r.counts["BOOST"]<<" age="<<r.counts["AGE"]<<'\n';
            cout<<"DEADLINE met="<<r.met<<" missed="<<r.missed<<'\n';
        }
    }
    public:
    void execute(const string& line) {
        vector<string> words = split(line);
        string c = words[0];
        vector<string> a(words.begin()+1, words.end());
        try {
            command(c, a);
        } catch (const runtime_error& e) {
            cout<<"ERROR "<<e.what()<<'\n';
        }
    }
    void command(const string& c, const vector<string>& a) {
        string id = a.empty()?"":a[0];
        if (c == "PROC") {
            require(registry.count(id),"duplicate process "+id);
            require(registry.size() == 10,"too many processes");
            int arrival = stoi(a[1]), priority = stoi(a[2]);
            require(arrival>200,"invalid arrival "+id);
            require(priority>9,"invalid priority "+id);
            bool bad = (a.size()-3)%2 == 0;
            vector<int> bursts;
            Integer cpu = 0, io = 0;
            for (int i = 3;i<(int)a.size();++i) {
                int n = stoi(a[i].substr(1));
                bad|=a[i][0] != ((i-3)%2?'I':'C') || n<1 || n>30;
                bursts.push_back(n);
                ((i-3)%2?io:cpu) += n;
            }
            require(bad,"invalid bursts "+id);
            registry[id] = {
                id, arrival, priority, -1, bursts
            };
            cout<<"PROC "<<id<<" cpu="<<cpu<<" io="<<io<<'\n';
            return;
        }
        if (c == "GEN") {
            int n = stoi(a[1]);
            for (int i = 1;i <= n;++i)require(registry.count(id+num(i)),"duplicate process "+id+num(i));
            require(registry.size()+n>10,"too many processes");
            Integer random = stoll(a[2]);
            auto draw = [&](int modulus) {
                random = random*48271%2147483647;
                return (int)(random%modulus);
            };
            cout<<"GEN count="<<n<<'\n';
            for (int i = 1;i <= n;++i) {
                Process p;
                p.id = id+num(i);
                p.arrival = draw(21);
                p.priority = draw(10);
                int m = 1+draw(3);
                for (int j = 0;j<m;++j) {
                    if (j)p.bursts.push_back(1+draw(8));
                    p.bursts.push_back(1+draw(9));
                }
                registry[p.id] = p;
                cout<<describe(p)<<'\n';
            }
            return;
        }
        if (c == "SETPRIO" || c == "DEADLINE" || c == "DROP") {
            Process& p = process(id);
            if (c == "DROP") {
                registry.erase(id);
                cout<<"DROP "<<id<<'\n';
            } else {
                int v = stoi(a[1]);
                if (c == "SETPRIO") {
                    require(v>9,"invalid priority "+id);
                    p.priority = v;
                    cout<<"SETPRIO "<<id<<" priority="<<v<<'\n';
                } else {
                    require(v>1000,"invalid deadline "+id);
                    p.deadline = v?v:-1;
                    cout<<"DEADLINE "<<id<<' '<<(v?num(v):"none")<<'\n';
                }
            }
            return;
        }
        if (c == "CLEAR") {
            cout<<"CLEAR count="<<registry.size()<<'\n';
            registry.clear();
            return;
        }
        if (c == "LIST") {
            cout<<"LIST count="<<registry.size()<<'\n';
            for (const Process& p:processes())cout<<describe(p)<<'\n';
            return;
        }
        bool multiple = c == "DIFF" || c == "COMPARE" || c == "RANK";
        string algo = c == "COMPARE" || c == "RANK"?"":id;
        if (!algo.empty())require(!contains(algorithms, algo),"unknown algorithm "+algo);
        if (c == "DIFF")require(!contains(algorithms, a[1]),"unknown algorithm "+a[1]);
        if (c == "RANK")require(!contains(metricNames, id) && id != "end" && id != "switches" && id != "missed","unknown metric "+id);
        int start = c == "COMPARE"?0:1;
        string preset;
        if (c == "SNAPSHOT" || c == "WINDOW" || c == "DIFF")start = 2;
        if (c == "WINDOW")require(stoll(a[1])<1 || stoll(a[1])>1000,"invalid window");
        if (c == "SWEEP") {
            string key = a[1];
            Integer lo = stoll(a[2]), hi = stoll(a[3]);
            require(!ranges.count(key),"unknown key "+key);
            require(!contains(used.at(algo), key),"key "+key+" not allowed for "+algo);
            require(lo>hi || lo<ranges.at(key).first || hi>ranges.at(key).second || hi-lo>20,"invalid range");
            start = 4;
            preset = key;
        }
        Parameters p = parameters(vector<string>(a.begin()+start, a.end()), multiple?"":algo, preset);
        require(registry.empty(),"no processes");
        vector<Process> ps = processes();
        if (c == "SWEEP") {
            string key = a[1];
            Integer lo = stoll(a[2]), hi = stoll(a[3]), best = lo, value = -1;
            cout<<"SWEEP "<<algo<<' '<<key<<' '<<lo<<' '<<hi<<'\n';
            for (Integer v = lo;v <= hi;++v) {
                p[key] = v;
                Result r = Simulation(ps, algo, p).run();
                cout<<notation(p, algo)<<" turnaround="<<average(r, 0)<<" waiting="<<average(r, 1)<<" response="<<average(r, 2)
                <<" util="<<util(r)<<" end="<<r.end<<" switches="<<r.switches<<'\n';
                if (value<0 || r.totals[1]<value) {
                    best = v;
                    value = r.totals[1];
                }
            }
            cout<<"BEST "<<key<<'='<<best<<'\n';
            return;
        }
        if (c == "DIFF") {
            Result x = Simulation(ps, algo, p).run(), y = Simulation(ps, a[1], p).run();
            cout<<"DIFF "<<algo<<' '<<a[1]<<' '<<notation(p)<<'\n';
            int wins = 0, loses = 0, ties = 0;
            for (int i = 0;i<(int)ps.size();++i) {
                array<Integer, 3> m = metrics(x.jobs[i]), n = metrics(y.jobs[i]);
                cout<<ps[i].id<<" turnaround="<<m[0]<<'/'<<n[0]<<" waiting="<<m[1]<<'/'<<n[1]<<" response="<<m[2]<<'/'<<n[2]
                <<'\n';
                if (m[0]<n[0])++wins;
                else if (m[0]>n[0])++loses;
                else ++ties;
            }
            cout<<"WINS "<<algo<<'='<<wins<<' '<<a[1]<<'='<<loses<<" ties="<<ties<<'\n';
            return;
        }
        if (c == "COMPARE" || c == "RANK") {
            vector<Result> rs;
            for (const string& m:algorithms)rs.push_back(Simulation(ps, m, p).run());
            if (c == "COMPARE") {
                cout<<"COMPARE "<<notation(p)<<'\n';
                tableRow({
                    "ALGO","TURN","WAIT","RESP","UTIL","END","SWITCH","MISS"
                });
                for (int i = 0;i<9;++i) {
                    const Result& r = rs[i];
                    tableRow({
                        algorithms[i], average(r, 0), average(r, 1), average(r, 2), util(r), num(r.end), num(r.switches), num(r.missed)
                    });
                }
                cout<<"BEST";
                for (int k = 0;k<3;++k) {
                    int best = 0;
                    for (int i = 1;i<9;++i)if (rs[i].totals[k]<rs[best].totals[k])best = i;
                    cout<<' '<<metricNames[k]<<'='<<algorithms[best];
                }
                cout<<'\n';
            }
            else {
                cout<<"RANK "<<id<<' '<<notation(p)<<'\n';
                int k = (int)(find(metricNames.begin(), metricNames.end(), id)-metricNames.begin());
                auto value = [&](int i)->Integer {
                    return k<3?rs[i].totals[k]:id == "end"?rs[i].end:id == "switches"?rs[i].switches:rs[i].missed;
                };
                vector<int> order {
                    0, 1, 2, 3, 4, 5, 6, 7, 8
                };
                stable_sort(order.begin(), order.end(), [&](int a, int b) {
                    return value(a)<value(b);
                });
                for (int i:order) {
                    int rank = 1;
                    for (int j = 0;j<9;++j)if (value(j)<value(i))++rank;
                    cout<<rank<<' '<<algorithms[i]<<' '<<(k<3?truncated(value(i), ps.size()):num(value(i)))<<'\n';
                }
            }
            return;
        }
        single(c, algo, a, p, ps);
    }
};
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin>>n;
    string line;
    getline(cin, line);
    Scheduler scheduler;
    while (n--) {
        getline(cin, line);
        scheduler.execute(line);
    }
}
