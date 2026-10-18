#include <algorithm>
#include <array>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

using std::string;
using std::vector;
const vector<string> types = {"MOTORCYCLE", "CAR", "ECAR", "VAN", "BUS"};
const vector<string> kindNames = {"MOTO", "COMPACT", "LARGE", "EV"};
const vector<vector<int>> preferences = {{0,1,2}, {1,2}, {3,1,2}, {2}, {2}};
struct Spot { int level, number, kind, vehicle = -1; bool closed = false; };
struct Vehicle {
    string plate;
    int type, spot, entry, energy = 0, charge = 0, validation = 0;
    bool paid = false;
    int payment = 0, parking = 0, night = 0;
};
struct Waiting { string plate; int type, joined; };
struct Bill { int parking, night, lost, charge, total, due; };
struct Record { int entry, exit, type, total; string location; bool lost; };
struct Counts { int entries = 0, exits = 0, refused = 0, revenue = 0, stay = 0; };
struct Revenue { int exits = 0, parking = 0, night = 0, lost = 0, charge = 0, total = 0; };
string timeText(int t) {
    int hour = t%1440/60, minute = t%60;
    return std::to_string(t/1440+1) + "-" + (hour < 10 ? "0" : "") + std::to_string(hour) + ":" + (minute < 10 ? "0" : "") + std::to_string(minute);
}
string duration(int t) { return std::to_string(t/60) + ":" + (t%60 < 10 ? "0" : "") + std::to_string(t%60); }
string tenth(int q) { return std::to_string(q/10) + "." + std::to_string(q%10); }
int lookup(const vector<string> &names, const string &s) {
    vector<string>::const_iterator it = std::find(names.begin(),names.end(),s);
    return it == names.end() ? -1 : int(it-names.begin());
}
struct Garage {
    int now = 0, peak = 0, peakTime = 0;
    std::array<int,5> rates = {100,200,200,300,600}, caps = {800,1600,1600,2400,4800};
    std::array<int,3> fees = {300,2000,30};
    vector<Spot> spots;
    vector<vector<int>> levels;
    vector<Vehicle> vehicles;
    vector<Waiting> queue;
    std::map<string,int> parked, passes;
    std::map<string,vector<Record>> histories;
    std::array<Counts,5> totals{};
    std::map<int,std::array<Counts,5>> daily;
    std::array<Revenue,5> revenue{};
    vector<string> output;

    void line(const string &s) { output.push_back(s); }
    bool error(bool condition, const string &reason) {
        if (condition) line("ERROR " + reason);
        return condition;
    }
    string label(int s) const { return "L" + std::to_string(spots[s].level) + "-" + std::to_string(spots[s].number); }
    string location(const Vehicle &v) const { return label(v.spot) + (v.type == 4 ? ".." + std::to_string(spots[v.spot].number+2) : ""); }
    bool free(int s) const { return !spots[s].closed && spots[s].vehicle < 0; }
    bool validPass(const string &p) const {
        std::map<string,int>::const_iterator found = passes.find(p);
        return found != passes.end() && now/1440+1 <= found->second;
    }
    int spotId(const string &s) const {
        std::size_t dash = s.find('-');
        int level = std::stoi(s.substr(1,dash-1)), number = std::stoi(s.substr(dash+1));
        if (level > int(levels.size()) || number > int(levels[level-1].size())) return -1;
        return levels[level-1][number-1];
    }
    int vehicle(const string &p) {
        std::map<string,int>::const_iterator found = parked.find(p);
        if (error(found == parked.end(),p + " is not parked")) return -1;
        return found->second;
    }
    int waiting(const string &p) const {
        for (int i = 0; i < int(queue.size()); ++i) if (queue[i].plate == p) return i;
        return -1;
    }
    int preference(int type, int kind) const {
        return int(std::find(preferences[type].begin(),preferences[type].end(),kind)-preferences[type].begin());
    }
    int assign(int type) const {
        if (type == 4) {
            for (const vector<int> &level : levels) {
                for (int j = 0; j+2 < int(level.size()); ++j) {
                    int a = level[j], b = level[j+1], c = level[j+2];
                    if (spots[a].kind == 2 && spots[b].kind == 2 && spots[c].kind == 2 && free(a) && free(b) && free(c)) return a;
                }
            }
        } else {
            for (int kind : preferences[type]) {
                for (int i = 0; i < int(spots.size()); ++i) if (spots[i].kind == kind && free(i)) return i;
            }
        }
        return -1;
    }
    void occupy(int id, int s) {
        Vehicle &v = vehicles[id];
        v.spot = s;
        for (int i = 0; i < (v.type == 4 ? 3 : 1); ++i) spots[s+i].vehicle = id;
    }
    void vacate(int id) {
        const Vehicle &v = vehicles[id];
        for (int i = 0; i < (v.type == 4 ? 3 : 1); ++i) spots[v.spot+i].vehicle = -1;
    }
    int park(const string &plate, int type, int spot) {
        int id = int(vehicles.size());
        vehicles.push_back({plate,type,spot,now});
        parked[plate] = id;
        occupy(id,spot);
        ++totals[type].entries;
        ++daily[now/1440+1][type].entries;
        if (int(parked.size()) > peak) {
            peak = int(parked.size());
            peakTime = now;
        }
        return id;
    }
    void refused(int type, int time) {
        ++totals[type].refused;
        ++daily[time/1440+1][type].refused;
    }
    void giveups() {
        vector<Waiting> remaining;
        for (const Waiting &w : queue) {
            if (now-w.joined >= 30) {
                line("GIVEUP " + w.plate + " " + types[w.type] + " " + timeText(w.joined+30));
                refused(w.type,w.joined+30);
            } else remaining.push_back(w);
        }
        queue.swap(remaining);
    }
    void processQueue() {
        vector<Waiting> remaining;
        for (const Waiting &w : queue) {
            int s = assign(w.type);
            if (s < 0) remaining.push_back(w);
            else {
                int id = park(w.plate,w.type,s);
                line("ADMIT " + w.plate + " " + types[w.type] + " " + location(vehicles[id]) + " waited " + duration(now-w.joined));
            }
        }
        queue.swap(remaining);
    }
    std::array<int,2> interval(const Vehicle &v, int from, int freeTime) const {
        int length = now-from;
        if (validPass(v.plate) || length <= freeTime) return {0,0};
        int parking = 0;
        for (int i = 0; i*1440 < length; ++i) {
            int minutes = std::min(length-i*1440,1440)-(i == 0 ? freeTime : 0);
            parking += std::min((minutes+29)/30*rates[v.type],caps[v.type]);
        }
        return {parking,(now/1440-from/1440)*fees[0]};
    }
    Bill bill(const Vehicle &v, bool loss) const {
        std::array<int,2> amount = interval(v,v.paid ? v.payment : v.entry,v.paid ? 15 : 15+v.validation);
        int p = amount[0]+(v.paid ? v.parking : 0), n = amount[1]+(v.paid ? v.night : 0);
        int l = loss ? fees[1] : 0, total = p+n+l+v.charge;
        return {p,n,l,v.charge,total,v.paid ? amount[0]+amount[1] : total};
    }
    void feeLine(const string &heading, const Vehicle &v, Bill b) {
        line(heading + " " + v.plate + " " + location(v) + " stay " + duration(now-v.entry) + " parking " + std::to_string(b.parking) + " night " + std::to_string(b.night) + " lost " + std::to_string(b.lost) + " charge " + std::to_string(b.charge) + " total " + std::to_string(b.total) + " due " + std::to_string(b.due));
    }
    string annotation(const Vehicle &v) const {
        string s;
        if (validPass(v.plate)) s += " PASS";
        if (v.validation) s += " VAL " + std::to_string(v.validation);
        if (v.energy) s += " KWH " + std::to_string(v.energy);
        if (v.paid) s += " PAID";
        return s;
    }
    vector<int> orderedVehicles() const {
        vector<int> ids;
        for (const auto &[plate, id] : parked) ids.push_back(id);
        std::sort(ids.begin(),ids.end(),[this](int a,int b) { return vehicles[a].spot < vehicles[b].spot; });
        return ids;
    }
    void move(int id, int s) {
        string before = location(vehicles[id]);
        vacate(id);
        occupy(id,s);
        line("MOVE " + vehicles[id].plate + " " + before + " -> " + label(s));
    }
    void execute(const vector<string> &a) {
        string cmd = a[0];
        if (cmd == "LEVEL") {
            vector<int> level;
            int counts[4];
            for (int k = 0; k < 4; ++k) {
                counts[k] = std::stoi(a[k+1]);
                for (int i = 0; i < counts[k]; ++i) {
                    level.push_back(int(spots.size()));
                    spots.push_back({int(levels.size())+1,int(level.size()),k});
                }
            }
            levels.push_back(level);
            line("LEVEL " + std::to_string(levels.size()) + " spots " + std::to_string(level.size()) + " MOTO " + a[1] + " COMPACT " + a[2] + " LARGE " + a[3] + " EV " + a[4]);
            processQueue();
        } else if (cmd == "CLOSE" || cmd == "OPEN") {
            int s = spotId(a[1]);
            if (error(s < 0,"unknown spot " + a[1])) return;
            Spot &spot = spots[s];
            if (cmd == "CLOSE") {
                if (error(spot.closed,"spot " + a[1] + " is already closed")) return;
                if (error(spot.vehicle >= 0,"spot " + a[1] + " is occupied by " + (spot.vehicle >= 0 ? vehicles[spot.vehicle].plate : ""))) return;
                spot.closed = true;
            } else {
                if (error(!spot.closed,"spot " + a[1] + " is not closed")) return;
                spot.closed = false;
            }
            line(cmd + " " + a[1] + " " + kindNames[spot.kind]);
            if (cmd == "OPEN") processQueue();
        } else if (cmd == "RATE") {
            int type = lookup(types,a[1]);
            if (error(type < 0,"unknown type " + a[1])) return;
            int rate = std::stoi(a[2]), cap = std::stoi(a[3]);
            if (error(cap < rate,"cap below rate for " + a[1])) return;
            rates[type] = rate;
            caps[type] = cap;
            line("RATE " + a[1] + " " + a[2] + " " + a[3]);
        } else if (cmd == "FEE") {
            int item = lookup({"NIGHT","LOST","KWH"},a[1]);
            if (error(item < 0,"unknown fee " + a[1])) return;
            fees[item] = std::stoi(a[2]);
            line("FEE " + a[1] + " " + a[2]);
        } else if (cmd == "ENTER") {
            int type = lookup(types,a[2]);
            if (error(type < 0,"unknown type " + a[2])) return;
            std::map<string,int>::const_iterator found = parked.find(a[1]);
            if (error(found != parked.end(),a[1] + " is already parked at " + (found != parked.end() ? location(vehicles[found->second]) : ""))) return;
            if (error(waiting(a[1]) >= 0,a[1] + " is already waiting")) return;
            int s = assign(type);
            if (s >= 0) {
                int id = park(a[1],type,s);
                line("ENTER " + a[1] + " " + a[2] + " " + location(vehicles[id]));
            } else if (queue.size() < 3) {
                queue.push_back({a[1],type,now});
                line("WAIT " + a[1] + " " + a[2] + " " + std::to_string(queue.size()));
            } else {
                refused(type,now);
                line("FULL " + a[1] + " " + a[2]);
            }
        } else if (cmd == "LEAVE") {
            int i = waiting(a[1]);
            if (error(i < 0,a[1] + " is not waiting")) return;
            line("LEAVE " + a[1] + " " + types[queue[i].type]);
            queue.erase(queue.begin()+i);
        } else if (cmd == "EXIT" || cmd == "PAY" || cmd == "QUOTE" || cmd == "CHARGE" || cmd == "VALIDATE" || cmd == "MOVE") {
            int id = vehicle(a[1]);
            if (id < 0) return;
            Vehicle &v = vehicles[id];
            if (cmd == "EXIT") {
                bool loss = a.size() == 3;
                if (error(loss && v.paid,a[1] + " has already paid")) return;
                Bill b = bill(v,loss);
                feeLine("EXIT",v,b);
                histories[v.plate].push_back({v.entry,now,v.type,b.total,location(v),loss});
                Counts &all = totals[v.type], &today = daily[now/1440+1][v.type];
                ++all.exits;
                ++today.exits;
                all.stay += now-v.entry;
                all.revenue += b.total;
                today.revenue += b.total;
                Revenue &r = revenue[v.type];
                ++r.exits;
                r.parking += b.parking;
                r.night += b.night;
                r.lost += b.lost;
                r.charge += b.charge;
                r.total += b.total;
                vacate(id);
                parked.erase(v.plate);
                processQueue();
            } else if (cmd == "QUOTE") feeLine("QUOTE",v,bill(v,false));
            else if (cmd == "PAY") {
                if (error(v.paid,a[1] + " has already paid")) return;
                Bill b = bill(v,false);
                v.paid = true;
                v.payment = now;
                v.parking = b.parking;
                v.night = b.night;
                line("PAY " + v.plate + " parking " + std::to_string(b.parking) + " night " + std::to_string(b.night) + " charge " + std::to_string(b.charge) + " total " + std::to_string(b.total));
            } else if (cmd == "CHARGE") {
                if (error(v.type != 2,a[1] + " is not an electric car") || error(spots[v.spot].kind != 3,a[1] + " is not at a charger") || error(v.paid,a[1] + " has already paid")) return;
                int energy = std::stoi(a[2]);
                if (error(v.energy+energy > 100,"charge limit exceeded for " + a[1])) return;
                int cost = energy*fees[2];
                v.energy += energy;
                v.charge += cost;
                line("CHARGE " + v.plate + " kwh " + a[2] + " cost " + std::to_string(cost) + " stay_kwh " + std::to_string(v.energy) + " stay_cost " + std::to_string(v.charge));
            } else if (cmd == "VALIDATE") {
                if (error(v.paid,a[1] + " has already paid")) return;
                int minutes = std::stoi(a[2]);
                if (error(v.validation+minutes > 180,"validation limit exceeded for " + a[1])) return;
                v.validation += minutes;
                line("VALIDATE " + v.plate + " " + a[2] + " total " + std::to_string(v.validation));
            } else {
                if (error(v.type == 4,"bus " + a[1] + " cannot be moved")) return;
                int s = spotId(a[2]);
                if (error(s < 0,"unknown spot " + a[2]) || error(s == v.spot,a[1] + " is already at " + a[2])) return;
                if (error(spots[s].closed,"spot " + a[2] + " is closed")) return;
                if (error(spots[s].vehicle >= 0,"spot " + a[2] + " is occupied by " + (spots[s].vehicle >= 0 ? vehicles[spots[s].vehicle].plate : ""))) return;
                bool usable = std::find(preferences[v.type].begin(),preferences[v.type].end(),spots[s].kind) != preferences[v.type].end();
                if (error(!usable,types[v.type] + " cannot use " + kindNames[spots[s].kind] + " spot " + a[2])) return;
                move(id,s);
                processQueue();
            }
        } else if (cmd == "PASS") {
            int days = std::stoi(a[2]);
            passes[a[1]] = validPass(a[1]) ? passes[a[1]]+days : now/1440+days;
            line("PASS " + a[1] + " until " + std::to_string(passes[a[1]]));
        } else if (cmd == "UNPASS") {
            if (error(!validPass(a[1]),a[1] + " has no pass")) return;
            passes.erase(a[1]);
            line("UNPASS " + a[1]);
        } else if (cmd == "REBALANCE") {
            vector<int> ids = orderedVehicles();
            int moved = 0;
            for (int id : ids) {
                const Vehicle &v = vehicles[id];
                if (v.type == 4) continue;
                int current = preference(v.type,spots[v.spot].kind);
                if (!current) continue;
                int s = assign(v.type);
                if (s >= 0 && preference(v.type,spots[s].kind) < current) {
                    move(id,s);
                    ++moved;
                }
            }
            line("REBALANCE " + std::to_string(moved));
            processQueue();
        } else if (cmd == "WHERE") {
            std::map<string,int>::const_iterator found = parked.find(a[1]);
            int q = waiting(a[1]);
            if (found != parked.end()) {
                const Vehicle &v = vehicles[found->second];
                line("WHERE " + a[1] + " " + location(v) + " " + types[v.type] + " " + timeText(v.entry) + " stay " + duration(now-v.entry) + annotation(v));
            } else if (q >= 0) line("WHERE " + a[1] + " waiting " + std::to_string(q+1));
            else if (histories.count(a[1])) line("WHERE " + a[1] + " gone " + timeText(histories[a[1]].back().exit));
            else error(true,"unknown plate " + a[1]);
        } else if (cmd == "LIST" || cmd == "OVERSTAY") {
            int level = cmd == "LIST" && a.size() == 2 ? std::stoi(a[1]) : 0;
            if (error(level > int(levels.size()),"unknown level " + std::to_string(level))) return;
            vector<int> ids;
            for (int id : orderedVehicles()) {
                if (level && spots[vehicles[id].spot].level != level) continue;
                if (cmd == "OVERSTAY" && now-vehicles[id].entry < std::stoi(a[1])*60) continue;
                ids.push_back(id);
            }
            if (cmd == "OVERSTAY") std::stable_sort(ids.begin(),ids.end(),[this](int a,int b) { return vehicles[a].entry < vehicles[b].entry; });
            line(cmd + (cmd == "OVERSTAY" ? " " + a[1] : "") + " " + std::to_string(ids.size()));
            for (int id : ids) {
                const Vehicle &v = vehicles[id];
                line(location(v) + " " + v.plate + " " + types[v.type] + " " + timeText(v.entry) + (cmd == "LIST" ? annotation(v) : " stay " + duration(now-v.entry)));
            }
        } else if (cmd == "MAP") {
            line("MAP " + std::to_string(levels.size()));
            const string initial = "mcle";
            for (int i = 0; i < int(levels.size()); ++i) {
                string symbols;
                for (int j = 0; j < int(levels[i].size()); ++j) {
                    if (j && j%10 == 0) symbols += ' ';
                    const Spot &s = spots[levels[i][j]];
                    char c = initial[s.kind];
                    if (s.closed) c = '#';
                    else if (s.vehicle >= 0) c += 'A'-'a';
                    symbols += c;
                }
                line("L" + std::to_string(i+1) + " " + symbols);
            }
        } else if (cmd == "OCCUPANCY") {
            line("OCCUPANCY vehicles " + std::to_string(parked.size()) + " waiting " + std::to_string(queue.size()));
            std::array<int,4> allUsed{}, allAvailable{};
            int allClosed = 0;
            for (int i = 0; i < int(levels.size()); ++i) {
                std::array<int,4> used{}, available{};
                int closed = 0;
                for (int id : levels[i]) {
                    const Spot &s = spots[id];
                    if (s.closed) ++closed;
                    else ++available[s.kind];
                    if (s.vehicle >= 0) ++used[s.kind];
                }
                string s = "L" + std::to_string(i+1);
                for (int k = 0; k < 4; ++k) {
                    s += " " + kindNames[k] + " " + std::to_string(used[k]) + "/" + std::to_string(available[k]);
                    allUsed[k] += used[k];
                    allAvailable[k] += available[k];
                }
                allClosed += closed;
                line(s + " closed " + std::to_string(closed));
            }
            string s = "TOTAL";
            int used = 0, available = 0;
            for (int k = 0; k < 4; ++k) {
                s += " " + kindNames[k] + " " + std::to_string(allUsed[k]) + "/" + std::to_string(allAvailable[k]);
                used += allUsed[k];
                available += allAvailable[k];
            }
            line(s + " closed " + std::to_string(allClosed) + " rate " + tenth(available ? used*1000/available : 0) + "%");
        } else if (cmd == "SIGN") {
            std::array<int,4> freeCounts{};
            int buses = 0;
            for (const vector<int> &level : levels) {
                int run = 0;
                for (int id : level) {
                    if (free(id)) ++freeCounts[spots[id].kind];
                    if (free(id) && spots[id].kind == 2) ++run;
                    else {
                        buses += run/3;
                        run = 0;
                    }
                }
                buses += run/3;
            }
            string s = "SIGN";
            for (int k = 0; k < 5; ++k) {
                int count = buses;
                if (k != 4) {
                    count = 0;
                    for (int kind : preferences[k]) count += freeCounts[kind];
                }
                s += " " + types[k] + " " + (count ? std::to_string(count) : "FULL");
            }
            line(s);
        } else if (cmd == "RATES") {
            line("RATES");
            for (int k = 0; k < 5; ++k) line(types[k] + " " + std::to_string(rates[k]) + " " + std::to_string(caps[k]));
            line("NIGHT " + std::to_string(fees[0]) + " LOST " + std::to_string(fees[1]) + " KWH " + std::to_string(fees[2]));
        } else if (cmd == "PASSES") {
            int count = 0;
            for (const auto &[plate, last] : passes) count += now/1440+1 <= last;
            line("PASSES " + std::to_string(count));
            for (const auto &[plate, last] : passes) if (now/1440+1 <= last) line(plate + " until " + std::to_string(last) + (parked.count(plate) ? " IN" : ""));
        } else if (cmd == "HISTORY") {
            std::map<string,vector<Record>>::const_iterator found = histories.find(a[1]);
            if (error(found == histories.end(),"no history for " + a[1])) return;
            int total = 0;
            for (const Record &r : found->second) total += r.total;
            line("HISTORY " + a[1] + " visits " + std::to_string(found->second.size()) + " paid " + std::to_string(total));
            for (const Record &r : found->second) line(timeText(r.entry) + " " + timeText(r.exit) + " " + r.location + " " + types[r.type] + " " + std::to_string(r.total) + (r.lost ? " LOST" : ""));
        } else if (cmd == "REVENUE") {
            line("REVENUE");
            Revenue all;
            for (int k = 0; k <= 5; ++k) {
                Revenue r = k == 5 ? all : revenue[k];
                line((k == 5 ? "TOTAL" : types[k]) + " exits " + std::to_string(r.exits) + " parking " + std::to_string(r.parking) + " night " + std::to_string(r.night) + " lost " + std::to_string(r.lost) + " charge " + std::to_string(r.charge) + " total " + std::to_string(r.total));
                if (k < 5) {
                    all.exits += r.exits;
                    all.parking += r.parking;
                    all.night += r.night;
                    all.lost += r.lost;
                    all.charge += r.charge;
                    all.total += r.total;
                }
            }
        } else if (cmd == "DAILY" || cmd == "STATS") {
            std::array<Counts,5> counts = cmd == "DAILY" ? daily[std::stoi(a[1])] : totals;
            Counts all;
            for (Counts c : counts) {
                all.entries += c.entries;
                all.exits += c.exits;
                all.refused += c.refused;
                all.revenue += c.revenue;
                all.stay += c.stay;
            }
            if (cmd == "DAILY") line("DAILY " + a[1] + " entries " + std::to_string(all.entries) + " exits " + std::to_string(all.exits) + " refused " + std::to_string(all.refused) + " revenue " + std::to_string(all.revenue));
            else line("STATS parked " + std::to_string(parked.size()) + " peak " + std::to_string(peak) + " at " + (peak ? timeText(peakTime) : "-"));
            for (int k = 0; k < (cmd == "DAILY" ? 5 : 6); ++k) {
                Counts c = k == 5 ? all : counts[k];
                string s = (k == 5 ? "ALL" : types[k]) + " entries " + std::to_string(c.entries) + " exits " + std::to_string(c.exits) + " refused " + std::to_string(c.refused);
                s += cmd == "DAILY" ? " revenue " + std::to_string(c.revenue) : " avg_stay " + tenth(c.exits ? c.stay*10/c.exits : 0);
                line(s);
            }
        }
    }
};
int main() {
    string text;
    std::getline(std::cin,text);
    int count = std::stoi(text);
    Garage garage;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin,text);
        std::istringstream input(text);
        int day;
        string time, word;
        input >> day >> time;
        garage.now = (day-1)*1440+std::stoi(time.substr(0,2))*60+std::stoi(time.substr(3));
        vector<string> args;
        while (input >> word) args.push_back(word);
        garage.output.clear();
        garage.giveups();
        garage.execute(args);
        for (const string &line : garage.output) std::cout << line << '\n';
    }
}
