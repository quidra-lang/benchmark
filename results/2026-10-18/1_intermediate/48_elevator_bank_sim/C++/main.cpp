#include <cstdlib>
#include <utility>
#include <algorithm>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
using namespace std;
using Integer  =  long long;
const vector<string> policies {
    "COST", "NEAREST", "ROUND", "ETA"
};
const vector<string> keys {
    "FLOORS", "CARS", "CAPACITY", "DOOR", "START", "POLICY", "ZONES", "PARK", "PATIENCE", "BYPASS", "PERIOD", "LIMIT",
    "COMPARE"
};
const map<string, int> argCounts {
    {
        "CALL", 3
    }, {
        "CANCEL", 1
    }, {
        "OUT", 1
    }, {
        "IN", 1
    }, {
        "HOLD", 2
    }, {
        "FIRE", 1
    }, {
        "RESET", 0
    }, {
        "WHERE", 1
    }, {
        "STATUS", 0
    }
};
int sign(int x) {
    return (x > 0) - (x < 0);
}
string num(Integer x) {
    return to_string(x);
}
string avg(Integer total, Integer count) {
    if (!count) return "-";
    Integer c  =  total * 100 / count;
    return num(c / 100) + "." + (c % 100 < 10 ? "0" : "") + num(c % 100);
}
string join(const vector<string>& xs) {
    if (xs.empty()) return "-";
    string s;
    for (const string& x : xs) {
        if (!s.empty()) s += ',';
        s += x;
    }
    return s;
}
vector<string> split(const string& text) {
    istringstream in(text);
    vector<string> r;
    string x;
    while (in >> x) r.push_back(x);
    return r;
}
bool contains(const vector<string>& xs, const string& x) {
    return find(xs.begin(), xs.end(), x) != xs.end();
}
void require(bool bad, const string& message) {
    if (bad) throw runtime_error(message);
}
struct Config {
    int floors  =  0, cars  =  0, capacity  =  0, door  =  0, park  =  -1, patience  =  -1, bypass  =  100, period  =  -1, limit  =  1000;
    vector<int> starts, homes;
    vector<pair<int, int>> zones;
    string policy  =  "COST";
    vector<string> compare;
    bool serves(int i, int a, int b) const {
        return zones[i].first <= min(a, b) && max(a, b) <= zones[i].second;
    }
};
Config configuration(const vector<vector<string>>& lines) {
    map<string, vector<string>> entries;
    for (const vector<string>& line : lines) {
        const string& k  =  line[0];
        require(!contains(keys, k), "unknown key " + k);
        require(entries.count(k), "duplicate key " + k);
        entries[k]  =  vector<string>(line.begin()+1, line.end());
    }
    for (int i  =  0; i < 5; ++i) require(!entries.count(keys[i]), "missing key " + keys[i]);
    Config c;
    for (const string& k : keys) {
        if (!entries.count(k)) continue;
        const vector<string>& a  =  entries[k];
        int n  =  k == "START" || k == "ZONES" ? c.cars : k == "PARK" ? c.cars + 1 : 1;
        require(k == "COMPARE" ? a.empty() || a.size() > 4 : (int)a.size() != n, "wrong number of values for " + k);
        auto bounded  =  [&](const string& text, int lo, int hi) {
            int x  =  stoi(text);
            require(x < lo || x > hi, "bad value for " + k);
            return x;
        };
        if (k == "FLOORS") c.floors  =  bounded(a[0], 2, 50);
        else if (k == "CARS") c.cars  =  bounded(a[0], 1, 8);
        else if (k == "CAPACITY") c.capacity  =  bounded(a[0], 1, 20);
        else if (k == "DOOR") c.door  =  bounded(a[0], 1, 9);
        else if (k == "START") for (const string& x : a) c.starts.push_back(bounded(x, 1, c.floors));
        else if (k == "POLICY") {
            require(!contains(policies, a[0]), "bad value for POLICY");
            c.policy  =  a[0];
        }
        else if (k == "ZONES") for (const string& x : a) {
            size_t p  =  x.find(':');
            int lo  =  stoi(x.substr(0, p)), hi  =  stoi(x.substr(p+1));
            require(lo < 1 || lo >= hi || hi > c.floors, "bad value for ZONES");
            c.zones.emplace_back(lo, hi);
        }
        else if (k == "PARK") {
            c.park  =  bounded(a[0], 0, 100);
            for (int i  =  1; i < (int)a.size(); ++i) c.homes.push_back(bounded(a[i], 1, c.floors));
        }
        else if (k == "PATIENCE") c.patience  =  bounded(a[0], 1, 1000);
        else if (k == "BYPASS") c.bypass  =  bounded(a[0], 50, 100);
        else if (k == "PERIOD") c.period  =  bounded(a[0], 1, 1000);
        else if (k == "LIMIT") c.limit  =  bounded(a[0], 1, 5000);
        else {
            set<string> seen;
            for (const string& p : a) {
                require(!contains(policies, p) || seen.count(p), "bad value for COMPARE");
                seen.insert(p);
            }
            c.compare  =  a;
        }
    }
    if (c.zones.empty()) c.zones.assign(c.cars, {
        1, c.floors
    });
    for (int i  =  0; i < c.cars; ++i) {
        auto [lo, hi]  =  c.zones[i];
        require(c.starts[i] < lo || c.starts[i] > hi, "car " + num(i+1) + " starts outside its zone");
        require(c.park >= 0 && (c.homes[i] < lo || c.homes[i] > hi), "car " + num(i+1) + " home outside its zone");
    }
    return c;
}
struct Event {
    int time;
    string command;
    vector<int> values;
};
vector<Event> validate(const Config& c, const vector<pair<int, vector<string>>>& raw) {
    vector<Event> accepted;
    int last  =  0, groups  =  0;
    bool fire  =  false;
    set<int> out;
    for (const auto& line : raw) {
        int t  =  stoi(line.second[0]);
        string cmd  =  line.second[1], error;
        vector<int> v;
        if (!argCounts.count(cmd)) error  =  "unknown command " + cmd;
        else if ((int)line.second.size()-2 != argCounts.at(cmd)) error  =  "wrong number of arguments for " + cmd;
        else if (t < last) error  =  "time goes backwards";
        else {
            for (int i  =  2; i < (int)line.second.size(); ++i) v.push_back(stoi(line.second[i]));
            int a  =  v.empty() ? 0 : v[0], b  =  v.size()>1 ? v[1] : 0;
            if (cmd == "CALL") {
                bool served  =  false;
                for (int i  =  0; i < c.cars; ++i) served |= c.serves(i, a, b);
                if (a<1 || a>c.floors || b<1 || b>c.floors) error = "bad floor";
                else if (a == b) error = "same floor";
                else if (v[2]<1 || v[2]>99) error = "bad count";
                else if (!served) error = "no car serves " + num(a) + "->" + num(b);
                else if (fire) error = "fire service active";
            }
            else if (cmd == "CANCEL" || cmd == "WHERE") {
                if (a<1 || a>groups) error = "unknown group";
            }
            else if (cmd == "OUT" || cmd == "IN" || cmd == "HOLD") {
                if (a<1 || a>c.cars) error = "bad car";
                else if (cmd == "OUT" && out.count(a)) error = "car " + num(a) + " already out";
                else if (cmd == "IN" && !out.count(a)) error = "car " + num(a) + " already in";
                else if (cmd == "HOLD" && (b<1 || b>9)) error = "bad ticks";
            }
            else if (cmd == "FIRE") {
                if (a<1 || a>c.floors) error = "bad floor";
                else if (fire) error = "fire already active";
            }
            else if (cmd == "RESET" && !fire) error = "fire not active";
        }
        if (!error.empty()) {
            cout << "line " << line.first << ": " << error << '\n';
            continue;
        }
        accepted.push_back({
            t, cmd, v
        });
        last = t;
        if (cmd == "CALL") ++groups;
        if (cmd == "OUT") out.insert(v[0]);
        if (cmd == "IN") out.erase(v[0]);
        if (cmd == "FIRE") fire = true;
        if (cmd == "RESET") fire = false;
    }
    return accepted;
}
struct Group {
    int a, b, n, time, waiting, car = -1, boarded = 0, delivered = 0, lost = 0, lastBoard = -1, lastAlight = -1, maxWait = 0;
    Integer wait = 0, travel = 0;
    set<int> cars;
    int direction() const {
        return sign(b-a);
    }
};
struct Passenger {
    int group, count, time;
};
struct Car {
    int floor, direction = 0, door = 0, idle = 0;
    bool inService = true;
    vector<Passenger> passengers;
    vector<int> calls;
    Integer distance = 0, stops = 0, boarded = 0, busy = 0, energy = 0;
    int load() const {
        int n = 0;
        for (const Passenger& p:passengers) n += p.count;
        return n;
    }
};
struct Result {
    vector<Group> groups;
    vector<Car> cars;
    Integer delivered = 0, abandoned = 0, evacuated = 0, wait = 0, travel = 0;
    int maxWait = 0, end = 0;
    bool aborted = false;
};
class Simulation {
    const Config& c;
    const vector<Event>& input;
    string policy;
    bool logging;
    Result r;
    vector<int> pending;
    int time = 0, evacuation = 0, round = -1;
    bool fire = false;
    void emit(const string& s) const {
        if (logging) cout << time << ' ' << s << '\n';
    }
    set<int> targets(const Car& car) const {
        set<int> s;
        for (const Passenger& p:car.passengers) s.insert(r.groups[p.group].b);
        for (int g:car.calls) s.insert(r.groups[g].a);
        return s;
    }
    void remove(int gi) {
        Group& g = r.groups[gi];
        vector<int>& list = g.car<0?pending:r.cars[g.car].calls;
        list.erase(std::remove(list.begin(), list.end(), gi), list.end());
        g.car = -1;
    }
    int cost(const Car& car, const Group& g) const {
        int f = car.floor, d = car.direction, x = g.a;
        if (policy == "NEAREST" || !d) return abs(f-x);
        set<int> s = targets(car);
        int distance, via = 0;
        if (g.direction() == d && (x-f)*d >= 0) {
            distance = abs(x-f);
            for (int y:s) if ((y-f)*d>0 && (x-y)*d>0) ++via;
        } else {
            int m = f;
            for (int y:s) m = d>0?max(m, y):min(m, y);
            distance = abs(f-m)+abs(m-x);
            for (int y:s) if ((y-f)*d>0) ++via;
        }
        return distance+(policy == "ETA"?c.door*via+car.door:0);
    }
    bool assign(int gi, int exclude = -1) {
        const Group& g = r.groups[gi];
        vector<int> candidates;
        for (int i = 0;i<c.cars;++i) if (i != exclude && r.cars[i].inService && c.serves(i, g.a, g.b)) candidates.push_back(i);
        if (candidates.empty()) return false;
        int chosen = candidates.front();
        if (policy == "ROUND") {
            for (int i:candidates) if (i>round) {
                chosen = i;
                break;
            }
        } else for (int i:candidates) if (cost(r.cars[i], g)<cost(r.cars[chosen], g)) chosen = i;
        int value = cost(r.cars[chosen], g);
        remove(gi);
        r.groups[gi].car = chosen;
        r.cars[chosen].calls.push_back(gi);
        if (policy == "ROUND") round = chosen;
        emit("E"+num(chosen+1)+" ASSIGN G"+num(gi+1)+(policy == "ROUND"?"":" cost="+num(value)));
        return true;
    }
    void makePending(int g) {
        r.groups[g].car = -1;
        pending.push_back(g);
        emit("PENDING G"+num(g+1));
    }
    void abandon(int gi, const string& word) {
        Group& g = r.groups[gi];
        remove(gi);
        emit(word+" G"+num(gi+1)+" x"+num(g.waiting));
        r.abandoned += g.waiting;
        g.lost += g.waiting;
        g.waiting = 0;
    }
    int choose(const Car& car) const {
        int f = car.floor, d = car.direction;
        set<int> s = targets(car);
        vector<int> calls;
        if (car.load()*100<c.capacity*c.bypass) for (int g:car.calls) if (r.groups[g].a == f) calls.push_back(g);
        if (d) {
            for (int y:s) if ((y-f)*d>0) return d;
            for (int g:calls) if (r.groups[g].direction() == d) return d;
        }
        if (!calls.empty()) return r.groups[calls.front()].direction();
        if (d) for (int y:s) if ((y-f)*d<0) return -d;
        if (!d && !car.calls.empty()) return sign(r.groups[car.calls.front()].a-f);
        return 0;
    }
    void move(Car& car, int n) {
        car.energy += n>0?3+car.load():1;
        car.floor += n;
        ++car.distance;
    }
    void event(const Event& e) {
        int a = e.values.empty()?0:e.values[0], b = e.values.size()>1?e.values[1]:0;
        const string& cmd = e.command;
        if (cmd == "CALL") {
            int n = e.values[2], gi = (int)r.groups.size();
            Group g;
            g.a = a;
            g.b = b;
            g.n = n;
            g.time = time;
            g.waiting = n;
            r.groups.push_back(g);
            emit("CALL G"+num(gi+1)+" "+num(a)+"->"+num(b)+" x"+num(n));
            if (!assign(gi)) makePending(gi);
        }
        else if (cmd == "CANCEL") {
            if (r.groups[a-1].waiting) abandon(a-1,"CANCEL");
            else emit("CANCEL G"+num(a)+" ignored");
        }
        else if (cmd == "OUT") {
            Car& car = r.cars[a-1];
            car.inService = false;
            emit("E"+num(a)+" OUT");
            vector<int> calls = car.calls;
            car.calls.clear();
            for (int g:calls) {
                r.groups[g].car = -1;
                if (!assign(g)) makePending(g);
            }
        }
        else if (cmd == "IN") {
            Car& car = r.cars[a-1];
            car.inService = true;
            car.idle = time;
            emit("E"+num(a)+" IN");
            vector<int> calls = pending;
            pending.clear();
            for (int g:calls) if (!assign(g)) pending.push_back(g);
        }
        else if (cmd == "HOLD") {
            Car& car = r.cars[a-1];
            if (car.door) {
                car.door += b;
                emit("E"+num(a)+" HOLD "+num(car.door));
            } else emit("E"+num(a)+" HOLD ignored");
        }
        else if (cmd == "FIRE") {
            fire = true;
            evacuation = a;
            emit("FIRE "+num(a));
            for (int i = 0;i<(int)r.groups.size();++i) if (r.groups[i].waiting) abandon(i,"ABANDON");
        }
        else if (cmd == "RESET") {
            fire = false;
            emit("RESET");
            for (Car& car:r.cars) car.idle = time;
        }
        else if (cmd == "WHERE") {
            const Group& g = r.groups[a-1];
            vector<string> riding;
            for (int i = 0;i<c.cars;++i) {
                int n = 0;
                for (const Passenger& p:r.cars[i].passengers) if (p.group == a-1) n += p.count;
                if (n) riding.push_back("E"+num(i+1)+"x"+num(n));
            }
            emit("WHERE G"+num(a)+" waiting="+num(g.waiting)+" car="+(!g.waiting?"-":g.car<0?"pending":"E"+num(g.car+1))+" riding="+join(riding)+" delivered="+num(g.delivered)+" lost="+num(g.lost));
        }
        else {
            for (int i = 0;i<c.cars;++i) {
                const Car& car = r.cars[i];
                set<int> stops;
                for (const Passenger& p:car.passengers) stops.insert(r.groups[p.group].b);
                vector<string> ss, gs;
                for (int f:stops)ss.push_back(num(f));
                for (int g:car.calls)gs.push_back("G"+num(g+1));
                emit("STATUS E"+num(i+1)+" floor="+num(car.floor)+" dir="+(car.direction>0?"up":car.direction<0?"down":"idle")+" door="+num(car.door)+" load="+num(car.load())+" stops="+join(ss)+" calls="+join(gs)+" service="+(car.inService?"in":"out"));
            }
            vector<string> ps;
            for (int g:pending)ps.push_back("G"+num(g+1));
            emit("STATUS pending="+join(ps));
        }
    }
    void action(int i) {
        Car& car = r.cars[i];
        bool moved = false;
        if (car.door) --car.door;
        if (!car.door) {
            int f = car.floor, d = car.direction, n = fire?sign(evacuation-f):choose(car);
            bool stop = fire?(n == 0 && !car.passengers.empty()):false;
            if (!fire) {
                for (const Passenger& p:car.passengers) if (r.groups[p.group].b == f)stop = true;
                if (car.load()*100<c.capacity*c.bypass)for (int g:car.calls)if (r.groups[g].a == f && r.groups[g].direction() == n)stop = true;
            }
            if (stop) {
                emit("E"+num(i+1)+" OPEN "+num(f));
                car.door = c.door;
                ++car.stops;
                car.energy += 2;
                vector<Passenger> riding;
                for (const Passenger& p:car.passengers) {
                    Group& g = r.groups[p.group];
                    if (g.b == f) {
                        emit("E"+num(i+1)+" ALIGHT G"+num(p.group+1)+" x"+num(p.count));
                        g.delivered += p.count;
                        g.lastAlight = time;
                        g.wait += (p.time-g.time)*p.count;
                        g.travel += (time-g.time)*p.count;
                        g.maxWait = max(g.maxWait, p.time-g.time);
                        r.delivered += p.count;
                        r.wait += (p.time-g.time)*p.count;
                        r.travel += (time-g.time)*p.count;
                        r.maxWait = max(r.maxWait, p.time-g.time);
                    } else if (fire) {
                        emit("E"+num(i+1)+" EVACUATE G"+num(p.group+1)+" x"+num(p.count));
                        g.lost += p.count;
                        r.evacuated += p.count;
                    } else riding.push_back(p);
                }
                car.passengers = riding;
                if (!fire) {
                    n = choose(car);
                    if (n)car.direction = n;
                    vector<int> calls;
                    for (int g:car.calls)if (r.groups[g].a == f && r.groups[g].direction() == n)calls.push_back(g);
                    for (int gi:calls) {
                        Group& g = r.groups[gi];
                        int k = min(c.capacity-car.load(), g.waiting);
                        if (k) {
                            car.passengers.push_back({
                                gi, k, time
                            });
                            g.waiting -= k;
                            g.boarded += k;
                            g.lastBoard = time;
                            g.cars.insert(i+1);
                            car.boarded += k;
                            emit("E"+num(i+1)+" BOARD G"+num(gi+1)+" x"+num(k));
                        }
                        if (!g.waiting)remove(gi);
                        else {
                            emit("E"+num(i+1)+" LEFT G"+num(gi+1)+" x"+num(g.waiting));
                            assign(gi, i);
                        }
                    }
                }
            } else if (n) {
                car.direction = n;
                move(car, n);
                moved = true;
            }
            else {
                if (d) {
                    emit("E"+num(i+1)+" IDLE "+num(f));
                    car.direction = 0;
                    car.idle = time;
                }
                if (!fire && car.inService && c.park >= 0 && f != c.homes[i] && time-car.idle >= c.park) {
                    move(car, sign(c.homes[i]-f));
                    moved = true;
                    if (car.floor == c.homes[i])emit("E"+num(i+1)+" PARK "+num(car.floor));
                }
            }
        }
        if (car.door || moved)++car.busy;
    }
    public:
    Simulation(const Config& config, const vector<Event>& events, string p, bool log):c(config), input(events), policy(std::move(p)),
    logging(log) {
        for (int f:c.starts) {
            Car car;
            car.floor = f;
            r.cars.push_back(car);
        }
    }
    Result run() {
        size_t cursor = 0;
        for (time = 0;time <= c.limit;++time) {
            if (c.patience >= 0)for (int i = 0;i<(int)r.groups.size();++i)if (r.groups[i].waiting && time == r.groups[i].time+c.patience)abandon(i,
            "ABANDON");
            while (cursor<input.size() && input[cursor].time == time)event(input[cursor++]);
            for (int i = 0;i<c.cars;++i)action(i);
            r.end = time;
            bool done = cursor == input.size();
            for (int i = 0;i<c.cars;++i) {
                const Car& car = r.cars[i];
                done = done && !car.door && car.passengers.empty() && car.calls.empty() && (fire?car.floor == evacuation:!car.inService || c.park<0 || car.floor == c.homes[i]);
            }
            if (done) {
                emit("END");
                break;
            }
            if (time == c.limit) {
                emit("ABORT");
                r.aborted = true;
            }
        }
        return r;
    }
};
void aggregate(const string& label, const vector<Group>& gs) {
    Integer passengers = 0, delivered = 0, wait = 0;
    for (const Group& g:gs) {
        passengers += g.n;
        delivered += g.delivered;
        wait += g.wait;
    }
    cout<<label<<": groups="<<gs.size()<<" passengers="<<passengers<<" delivered="<<delivered<<" avg_wait="<<avg(wait,
    delivered)<<'\n';
}
void statistics(const Config& c, const Result& r) {
    Integer passengers = 0;
    map<int, vector<Group>> floors, periods;
    for (int i = 0;i<(int)r.groups.size();++i) {
        const Group& g = r.groups[i];
        passengers += g.n;
        vector<string> cs;
        for (int car:g.cars)cs.push_back(num(car));
        cout<<"G"<<i+1<<" t="<<g.time<<' '<<g.a<<"->"<<g.b<<" n="<<g.n<<" delivered="<<g.delivered<<" lost="<<g.lost
        <<" wait="<<(g.boarded == g.n?num(g.lastBoard-g.time):"-")<<" travel="<<(g.delivered == g.n?num(g.lastAlight-g.time):"-")
        <<" cars="<<join(cs)<<'\n';
        floors[g.a].push_back(g);
        if (c.period >= 0)periods[g.time/c.period].push_back(g);
    }
    for (int i = 0;i<c.cars;++i) {
        const Car& car = r.cars[i];
        Integer u = car.busy*1000/(r.end+1);
        cout<<"E"<<i+1<<" distance="<<car.distance<<" stops="<<car.stops<<" boarded="<<car.boarded<<" busy="<<car.busy
        <<" util="<<u/10<<'.'<<u%10<<"% energy="<<car.energy<<'\n';
    }
    for (const auto& entry:floors)aggregate("F"+num(entry.first), entry.second);
    for (const auto& entry:periods) {
        int k = entry.first;
        aggregate("P"+num(k)+" "+num(k*c.period)+"-"+num(k*c.period+c.period-1), entry.second);
    }
    cout<<"summary: groups="<<r.groups.size()<<" passengers="<<passengers<<" delivered="<<r.delivered<<" abandoned="
    <<r.abandoned<<" evacuated="<<r.evacuated<<" avg_wait="<<avg(r.wait, r.delivered)<<" avg_travel="<<avg(r.travel, r.delivered)
    <<" max_wait="<<(r.delivered?num(r.maxWait):"-")<<" end="<<r.end<<'\n';
}
struct Scenario {
    string name;
    Config config;
    Result result;
    bool valid = false;
};
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int q;
    cin>>q;
    string line;
    getline(cin, line);
    int lineNumber = 1;
    vector<Scenario> scenarios;
    while (q--) {
        getline(cin, line);
        ++lineNumber;
        Scenario s;
        s.name = split(line)[1];
        vector<vector<string>> settings;
        vector<pair<int, vector<string>>> raw;
        while (getline(cin, line)) {
            ++lineNumber;
            if (line == "END")break;
            vector<string> w = split(line);
            if (w[0][0] >= '0' && w[0][0] <= '9')raw.push_back({
                lineNumber, w
            });
            else settings.push_back(w);
        }
        cout<<"== "<<s.name<<" ==\n";
        try {
            s.config = configuration(settings);
        } catch (const runtime_error& e) {
            cout<<"error: "<<e.what()<<'\n';
            scenarios.push_back(s);
            continue;
        }
        s.valid = true;
        const Config& c = s.config;
        cout<<"config: floors="<<c.floors<<" cars="<<c.cars<<" capacity="<<c.capacity<<" door="<<c.door<<" policy="
        <<c.policy<<" park="<<(c.park<0?"off":num(c.park))<<" patience="<<(c.patience<0?"off":num(c.patience))<<" bypass="
        <<c.bypass<<" period="<<(c.period<0?"off":num(c.period))<<" limit="<<c.limit<<" compare="<<join(c.compare)
        <<'\n';
        for (int i = 0;i<c.cars;++i)cout<<"E"<<i+1<<": start="<<c.starts[i]<<" zone="<<c.zones[i].first<<'-'<<c.zones[i].second
        <<" home="<<(c.park<0?"-":num(c.homes[i]))<<'\n';
        vector<Event> input = validate(c, raw);
        s.result = Simulation(c, input, c.policy, true).run();
        statistics(c, s.result);
        for (const string& policy:c.compare) {
            Result r = Simulation(c, input, policy, false).run();
            cout<<"compare "<<policy<<": delivered="<<r.delivered<<" avg_wait="<<avg(r.wait, r.delivered)<<" avg_travel="
            <<avg(r.travel, r.delivered)<<" max_wait="<<(r.delivered?num(r.maxWait):"-")<<" end="<<r.end<<" status="<<(r.aborted?"abort":"end")
            <<'\n';
        }
        scenarios.push_back(s);
    }
    vector<int> ranked;
    for (int i = 0;i<(int)scenarios.size();++i)if (scenarios[i].valid && !scenarios[i].result.aborted && scenarios[i].result.delivered)ranked.push_back(i);
    stable_sort(ranked.begin(), ranked.end(), [&](int a, int b) {
        const Result& x = scenarios[a].result;const Result& y = scenarios[b].result;Integer d = x.wait*y.delivered-y.wait*x.delivered;if (d)return d<0;return x.travel*y.delivered<y.travel*x.delivered;
    });
    cout<<"== ranking ==\n";
    for (int i = 0;i<(int)ranked.size();++i) {
        const Scenario& s = scenarios[ranked[i]];
        const Result& r = s.result;
        cout<<i+1<<". "<<s.name<<" policy="<<s.config.policy<<" avg_wait="<<avg(r.wait, r.delivered)<<" avg_travel="
        <<avg(r.travel, r.delivered)<<" max_wait="<<r.maxWait<<'\n';
    }
    for (int i = 0;i<(int)scenarios.size();++i)if (find(ranked.begin(), ranked.end(), i) == ranked.end())cout<<"- "<<scenarios[i].name
    <<' '<<(!scenarios[i].valid?"invalid":scenarios[i].result.aborted?"aborted":"empty")<<'\n';
    cout<<"== policies ==\n";
    for (const string& p:policies) {
        int n = 0;
        Integer delivered = 0, wait = 0, travel = 0;
        for (int i:ranked)if (scenarios[i].config.policy == p) {
            ++n;
            delivered += scenarios[i].result.delivered;
            wait += scenarios[i].result.wait;
            travel += scenarios[i].result.travel;
        }
        if (n)cout<<p<<": runs="<<n<<" avg_wait="<<avg(wait, delivered)<<" avg_travel="<<avg(travel, delivered)<<'\n';
    }
}
