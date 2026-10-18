#include <algorithm>
#include <array>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using std::string;
using std::vector;
struct Seat { int row, cabin, block, position, kind; char letter; };
struct Cabin { int from = 0, to = 0; vector<string> blocks; };
struct Aircraft {
    string model;
    int base = 0, limit = 0;
    std::array<Cabin, 3> cabins;
    vector<Seat> seats;
    vector<bool> blocked;
    std::array<int, 2600> lookup;
    std::array<bool, 100> exits{};
    std::array<int, 3> capacity{};
    Aircraft() { lookup.fill(-1); }
};
struct Flight {
    string name;
    int model;
    bool closed = false;
    std::array<int, 3> limit{};
    vector<bool> blocked;
    vector<int> occupants, passengers, volunteers;
};
struct Booking { string pnr; int flight; bool checked = false; vector<int> people; };
struct Person {
    string name;
    int booking, type, preference = -1, cabin, seat = -1, lap = -1;
    bool active = true, volunteer = false;
};
vector<Aircraft> aircraft;
vector<Flight> flights;
vector<Booking> bookings;
vector<Person> people;
std::map<string, int> modelIds, flightIds, bookingIds, tiers;
Aircraft building;
const string classes = "FJY";
const vector<string> typeNames = {"ADULT", "CHILD", "INFANT"};
const vector<string> tierNames = {"PLATINUM", "GOLD", "SILVER", "NONE"};

[[noreturn]] void fail(const string &message) { throw std::runtime_error(message); }
vector<string> split(const string &s, char delimiter = ' ') {
    vector<string> result;
    std::size_t start = 0;
    for (std::size_t i = 0; i <= s.size(); ++i) {
        if (i == s.size() || s[i] == delimiter) {
            result.push_back(s.substr(start, i - start));
            start = i + 1;
        }
    }
    return result;
}
string join(const vector<string> &items, const string &separator) {
    string result;
    for (std::size_t i = 0; i < items.size(); ++i) {
        if (i) result += separator;
        result += items[i];
    }
    return result;
}
template <typename... Values> string text(const Values &...values) {
    std::ostringstream out;
    (out << ... << values);
    return out.str();
}
int cabinId(const string &s) { return int(classes.find(s[0])); }
int tier(int person) {
    std::map<string, int>::const_iterator it = tiers.find(people[person].name);
    return it == tiers.end() ? 3 : it->second;
}
int seatKey(const string &s) { return std::stoi(s.substr(0, s.size() - 1)) * 26 + s.back() - 'A'; }
string seatName(const Aircraft &a, int index) { return index < 0 ? "UNASSIGNED" : text(a.seats[index].row, a.seats[index].letter); }
int flightId(const string &name, bool open = false) {
    std::map<string, int>::const_iterator it = flightIds.find(name);
    if (it == flightIds.end()) fail("unknown flight " + name);
    if (open && flights[it->second].closed) fail("flight " + name + " is closed");
    return it->second;
}
int activeCount(int booking) {
    int count = 0;
    for (int id : bookings[booking].people) count += people[id].active;
    return count;
}
int bookingId(const string &pnr, bool open = false) {
    std::map<string, int>::const_iterator it = bookingIds.find(pnr);
    if (it == bookingIds.end() || !activeCount(it->second)) fail("unknown PNR " + pnr);
    int id = it->second;
    if (open && flights[bookings[id].flight].closed) fail("flight " + flights[bookings[id].flight].name + " is closed");
    return id;
}
int passengerId(int booking, const string &name) {
    for (int id : bookings[booking].people) if (people[id].active && people[id].name == name) return id;
    fail("no passenger " + name + " in " + bookings[booking].pnr);
}
int resolve(const string &pnr, const string &name) { return passengerId(bookingId(pnr, true), name); }
bool hasInfant(int id) { return people[id].type == 0 && people[id].lap >= 0 && people[people[id].lap].active; }
bool bookingInfants(int booking) {
    for (int id : bookings[booking].people) if (people[id].active && people[id].type == 2) return true;
    return false;
}
int bookedCount(int flight, int cabin) {
    int count = 0;
    for (int id : flights[flight].passengers) if (people[id].active && people[id].type != 2 && people[id].cabin == cabin) ++count;
    return count;
}
bool contains(const vector<int> &items, int value) { return std::find(items.begin(), items.end(), value) != items.end(); }
bool exitAllowed(int id, const Aircraft &a, int seat) { return !a.exits[a.seats[seat].row] || people[id].type == 0 && !hasInfant(id); }
bool infantAllowed(int flight, int id, int seat, const vector<int> &moving, const vector<std::pair<int, int>> &proposed) {
    if (!hasInfant(id)) return true;
    const Flight &f = flights[flight];
    const Aircraft &a = aircraft[f.model];
    const Seat &s = a.seats[seat];
    const string &letters = a.cabins[s.cabin].blocks[s.block];
    for (char letter : letters) {
        int peer = a.lookup[s.row * 26 + letter - 'A'], owner = f.occupants[peer];
        if (owner >= 0 && owner != id && !contains(moving, owner) && hasInfant(owner)) return false;
    }
    for (const std::pair<int, int> &assignment : proposed) {
        int other = assignment.first;
        const Seat &target = a.seats[assignment.second];
        if (other != id && hasInfant(other) && target.row == s.row && target.block == s.block) return false;
    }
    return true;
}
bool fits(int flight, const vector<int> &ids, const vector<int> &seats, const vector<int> &vacated = {}) {
    const Flight &f = flights[flight];
    const Aircraft &a = aircraft[f.model];
    vector<int> moving = ids;
    moving.insert(moving.end(), vacated.begin(), vacated.end());
    vector<std::pair<int, int>> proposed;
    for (int i = 0; i < int(ids.size()); ++i) proposed.push_back({ids[i], seats[i]});
    for (int i = 0; i < int(ids.size()); ++i) {
        int seat = seats[i], owner = f.occupants[seat];
        if (f.blocked[seat] || owner >= 0 && !contains(moving, owner) || !exitAllowed(ids[i], a, seat) || !infantAllowed(flight, ids[i], seat, moving, proposed)) return false;
    }
    return true;
}
int chooseSeat(int flight, int id, int cabin) {
    const Flight &f = flights[flight];
    const Aircraft &a = aircraft[f.model];
    int first = -1;
    for (int seat = 0; seat < int(a.seats.size()); ++seat) {
        if (a.seats[seat].cabin != cabin || f.blocked[seat] || f.occupants[seat] >= 0 || !exitAllowed(id, a, seat) || !infantAllowed(flight, id, seat, {}, {})) continue;
        if (first < 0) first = seat;
        if (people[id].preference < 0 || a.seats[seat].kind == people[id].preference) return seat;
    }
    return first;
}
void seatPerson(int flight, int id, int seat) {
    Flight &f = flights[flight];
    if (people[id].seat >= 0) f.occupants[people[id].seat] = -1;
    people[id].seat = seat;
    if (seat >= 0) f.occupants[seat] = id;
}
void reassign(int flight, vector<string> &out) {
    const Aircraft &a = aircraft[flights[flight].model];
    for (int id : flights[flight].passengers) {
        if (!people[id].active || people[id].type == 2 || people[id].seat >= 0) continue;
        int seat = chooseSeat(flight, id, people[id].cabin);
        if (seat < 0) continue;
        seatPerson(flight, id, seat);
        out.push_back("REASSIGNED " + bookings[people[id].booking].pnr + " " + people[id].name + " " + seatName(a, seat));
    }
}
void removePerson(int id) {
    if (!people[id].active) return;
    int lap = people[id].lap;
    if (people[id].type == 0 && lap >= 0) removePerson(lap);
    if (people[id].type == 2 && lap >= 0) people[lap].lap = -1;
    seatPerson(bookings[people[id].booking].flight, id, -1);
    people[id].active = false;
    people[id].volunteer = false;
    people[id].lap = -1;
}
string passengerResult(int id) {
    return people[id].type == 2 ? "LAP" : seatName(aircraft[flights[bookings[people[id].booking].flight].model], people[id].seat);
}
string assignBooking(int flight, int cabin, const vector<int> &ids) {
    if (ids.size() == 1) {
        seatPerson(flight, ids[0], chooseSeat(flight, ids[0], cabin));
        return "SINGLE";
    }
    const Aircraft &a = aircraft[flights[flight].model];
    const Cabin &c = a.cabins[cabin];
    int count = int(ids.size());
    for (int stage = 0; stage < 3; ++stage) {
        int firstHeight = stage == 2 ? 2 : 1, lastHeight = stage == 2 ? count : 1;
        for (int height = firstHeight; height <= lastHeight; ++height) {
            int width = stage == 2 ? (count + height - 1) / height : count;
            int usedRows = (count + width - 1) / width;
            for (int row = c.from; row + usedRows - 1 <= c.to; ++row) {
                vector<string> blocks = stage == 1 ? vector<string>{join(c.blocks, "")} : c.blocks;
                for (const string &block : blocks) {
                    for (int x = 0; x + width <= int(block.size()); ++x) {
                        vector<int> candidate;
                        for (int j = 0; j < count; ++j) candidate.push_back(a.lookup[(row + j / width) * 26 + block[x + j % width] - 'A']);
                        if (!fits(flight, ids, candidate)) continue;
                        for (int j = 0; j < count; ++j) seatPerson(flight, ids[j], candidate[j]);
                        return vector<string>{"BLOCK", "ROW", "STACK"}[stage];
                    }
                }
            }
        }
    }
    for (int id : ids) seatPerson(flight, id, chooseSeat(flight, id, cabin));
    return "SPLIT";
}
vector<string> execute(const vector<string> &v) {
    const string &command = v[0];
    vector<string> out;
    if (command == "AIRCRAFT") {
        building = Aircraft{};
        building.model = v[1];
        building.base = std::stoi(v[2]);
        building.limit = std::stoi(v[3]);
    } else if (command == "CABIN") {
        int cabin = cabinId(v[1]);
        Cabin &c = building.cabins[cabin];
        c.from = std::stoi(v[2]);
        c.to = std::stoi(v[3]);
        c.blocks.assign(v.begin() + 4, v.end());
        for (int row = c.from; row <= c.to; ++row) {
            for (int block = 0; block < int(c.blocks.size()); ++block) {
                const string &letters = c.blocks[block];
                for (int position = 0; position < int(letters.size()); ++position) {
                    char letter = letters[position];
                    int kind = block == 0 && position == 0 || block + 1 == int(c.blocks.size()) && position + 1 == int(letters.size()) ? 0 : position == 0 || position + 1 == int(letters.size()) ? 2 : 1;
                    building.lookup[row * 26 + letter - 'A'] = int(building.seats.size());
                    building.seats.push_back({row, cabin, block, position, kind, letter});
                    building.blocked.push_back(false);
                }
            }
        }
    } else if (command == "EXIT") {
        for (int i = 1; i < int(v.size()); ++i) building.exits[std::stoi(v[i])] = true;
    } else if (command == "BLOCKED") {
        for (int i = 1; i < int(v.size()); ++i) building.blocked[building.lookup[seatKey(v[i])]] = true;
    } else if (command == "END") {
        for (int i = 0; i < int(building.seats.size()); ++i) if (!building.blocked[i]) ++building.capacity[building.seats[i].cabin];
        string line = "AIRCRAFT " + building.model;
        for (int cabin = 0; cabin < 3; ++cabin) if (building.cabins[cabin].from) line += text(" ", classes[cabin], " ", building.capacity[cabin]);
        modelIds[building.model] = int(aircraft.size());
        aircraft.push_back(std::move(building));
        out.push_back(line);
    } else if (command == "FLIGHT") {
        if (flightIds.count(v[1])) fail("duplicate flight " + v[1]);
        if (!modelIds.count(v[2])) fail("unknown aircraft " + v[2]);
        Flight f;
        f.name = v[1];
        f.model = modelIds[v[2]];
        const Aircraft &a = aircraft[f.model];
        f.blocked = a.blocked;
        f.occupants.assign(a.seats.size(), -1);
        string line = "FLIGHT " + f.name + " " + a.model;
        for (int cabin = 0; cabin < 3; ++cabin) {
            f.limit[cabin] = a.capacity[cabin] * (100 + std::stoi(v[3])) / 100;
            if (a.cabins[cabin].from) line += text(" ", classes[cabin], " ", a.capacity[cabin], "/", f.limit[cabin]);
        }
        flightIds[f.name] = int(flights.size());
        flights.push_back(std::move(f));
        out.push_back(line);
    } else if (command == "BOOK") {
        if (bookingIds.count(v[1])) fail("duplicate PNR " + v[1]);
        int flight = flightId(v[2], true), cabin = cabinId(v[3]);
        const Aircraft &a = aircraft[flights[flight].model];
        if (!a.cabins[cabin].from) fail("no cabin " + v[3] + " on " + v[2]);
        vector<Person> draft;
        std::set<string> names;
        vector<int> adults, infants;
        for (int i = 4; i < int(v.size()); ++i) {
            vector<string> fields = split(v[i], ':');
            if (!names.insert(fields[0]).second) fail("duplicate name " + fields[0] + " in " + v[1]);
            int type = int(std::find(typeNames.begin(), typeNames.end(), fields[1]) - typeNames.begin());
            Person p;
            p.name = fields[0];
            p.type = type;
            p.cabin = cabin;
            p.booking = int(bookings.size());
            if (fields.size() == 3) p.preference = int(string("WMA").find(fields[2]));
            if (type == 0) adults.push_back(int(draft.size()));
            if (type == 2) infants.push_back(int(draft.size()));
            draft.push_back(p);
        }
        for (const Person &p : draft) {
            for (int id : flights[flight].passengers) if (people[id].active && people[id].name == p.name) fail(p.name + " already on " + v[2]);
        }
        if (adults.empty()) fail("no adult in " + v[1]);
        if (infants.size() > adults.size()) fail("too many infants in " + v[1]);
        if (bookedCount(flight, cabin) + int(draft.size() - infants.size()) > flights[flight].limit[cabin]) fail("limit exceeded for " + v[2] + " " + v[3]);
        int base = int(people.size());
        for (int i = 0; i < int(infants.size()); ++i) {
            draft[adults[i]].lap = base + infants[i];
            draft[infants[i]].lap = base + adults[i];
        }
        Booking b{v[1], flight, false, {}};
        vector<int> needs;
        for (const Person &p : draft) {
            int id = int(people.size());
            people.push_back(p);
            b.people.push_back(id);
            flights[flight].passengers.push_back(id);
            if (p.type != 2) needs.push_back(id);
        }
        bookingIds[b.pnr] = int(bookings.size());
        bookings.push_back(b);
        string method = assignBooking(flight, cabin, needs);
        string line = "BOOKED " + b.pnr + " " + v[2] + " " + v[3] + " " + method;
        for (int id : b.people) line += " " + people[id].name + ":" + passengerResult(id);
        out.push_back(line);
    } else if (command == "STATUS") {
        tiers[v[1]] = int(std::find(tierNames.begin(), tierNames.end(), v[2]) - tierNames.begin());
        out.push_back("STATUS " + v[1] + " " + v[2]);
    } else if (command == "FIND") {
        int membership = tiers.count(v[1]) ? tiers[v[1]] : 3;
        vector<string> found;
        for (const Flight &f : flights) {
            for (int id : f.passengers) {
                const Person &p = people[id];
                if (p.active && p.name == v[1]) found.push_back(text(f.name, " ", bookings[p.booking].pnr, " ", classes[p.cabin], " ", passengerResult(id), f.closed ? " CLOSED" : " OPEN"));
            }
        }
        out.push_back(text("FIND ", v[1], " ", tierNames[membership], " ", found.size()));
        out.insert(out.end(), found.begin(), found.end());
    } else if (command == "SEAT") {
        int id = resolve(v[1], v[2]);
        Person &p = people[id];
        int flight = bookings[p.booking].flight;
        Flight &f = flights[flight];
        const Aircraft &a = aircraft[f.model];
        if (p.type == 2) fail("infant " + p.name + " has no seat");
        int seat = a.lookup[seatKey(v[3])];
        if (seat < 0 || a.seats[seat].cabin != p.cabin) fail("no seat " + v[3] + " in cabin " + classes[p.cabin]);
        if (f.blocked[seat]) fail("seat " + v[3] + " is blocked");
        if (f.occupants[seat] >= 0) fail("seat " + v[3] + " is occupied");
        if (!exitAllowed(id, a, seat)) fail(text("exit row ", a.seats[seat].row, " not allowed for ", p.name));
        if (!infantAllowed(flight, id, seat, {}, {})) fail("infant limit reached at " + v[3]);
        string old = seatName(a, p.seat);
        seatPerson(flight, id, seat);
        out.push_back("MOVED " + v[1] + " " + v[2] + " " + old + " -> " + v[3]);
        reassign(flight, out);
    } else if (command == "SWAP") {
        int first = resolve(v[1], v[2]);
        int second = resolve(v[3], v[4]);
        if (first == second) fail("cannot swap " + v[2] + " with itself");
        for (int id : {first, second}) if (people[id].type == 2) fail("infant " + people[id].name + " has no seat");
        int flight = bookings[people[first].booking].flight;
        if (flight != bookings[people[second].booking].flight) fail(v[1] + " and " + v[3] + " are on different flights");
        if (people[first].cabin != people[second].cabin) fail(v[2] + " and " + v[4] + " are in different cabins");
        for (int id : {first, second}) if (people[id].seat < 0) fail(people[id].name + " has no seat");
        int oldFirst = people[first].seat, oldSecond = people[second].seat;
        if (!fits(flight, {first, second}, {oldSecond, oldFirst})) fail("swap of " + v[2] + " and " + v[4] + " breaks seating rules");
        flights[flight].occupants[oldFirst] = flights[flight].occupants[oldSecond] = -1;
        people[first].seat = people[second].seat = -1;
        seatPerson(flight, first, oldSecond);
        seatPerson(flight, second, oldFirst);
        const Aircraft &a = aircraft[flights[flight].model];
        out.push_back("SWAPPED " + v[1] + " " + v[2] + " " + seatName(a, oldSecond) + " " + v[3] + " " + v[4] + " " + seatName(a, oldFirst));
        reassign(flight, out);
    } else if (command == "CANCEL") {
        int booking = bookingId(v[1], true), target = v.size() == 3 ? passengerId(booking, v[2]) : -1;
        vector<int> removed;
        for (int id : bookings[booking].people) if (people[id].active && (target < 0 || id == target || people[target].type == 0 && people[target].lap == id)) removed.push_back(id);
        int remaining = 0, adults = 0;
        for (int id : bookings[booking].people) {
            if (people[id].active && !contains(removed, id)) {
                ++remaining;
                adults += people[id].type == 0;
            }
        }
        if (target >= 0 && remaining && !adults) fail(v[1] + " would have no adult");
        string line = "CANCELLED " + v[1];
        for (int id : removed) line += " " + people[id].name;
        for (int id : removed) removePerson(id);
        out.push_back(line);
        reassign(bookings[booking].flight, out);
    } else if (command == "CHECKIN" || command == "VOLUNTEER" || command == "INFO") {
        int booking = bookingId(v[1], command != "INFO");
        Booking &b = bookings[booking];
        if (command == "CHECKIN") {
            if (b.checked) fail(v[1] + " already checked in");
            b.checked = true;
            out.push_back(text("CHECKIN ", b.pnr, " ", activeCount(booking)));
        } else if (command == "INFO") {
            out.push_back(text("INFO ", b.pnr, " ", flights[b.flight].name, " ", activeCount(booking), b.checked ? " CHECKED" : " NOT-CHECKED"));
            for (int id : b.people) if (people[id].active) out.push_back(text(people[id].name, " ", typeNames[people[id].type], " ", classes[people[id].cabin], " ", passengerResult(id)));
        } else {
            int id = passengerId(booking, v[2]);
            Person &p = people[id];
            if (p.type != 0 || hasInfant(id)) fail(p.name + " cannot volunteer");
            if (p.seat < 0) fail(p.name + " has no seat");
            if (p.volunteer) fail(p.name + " already volunteered");
            p.volunteer = true;
            flights[b.flight].volunteers.push_back(id);
            out.push_back("VOLUNTEER " + b.pnr + " " + p.name + " " + passengerResult(id));
        }
    } else {
        bool modifying = command == "UPGRADE" || command == "CLOSE" || command == "BLOCK" || command == "UNBLOCK";
        int flight = flightId(v[1], modifying);
        Flight &f = flights[flight];
        const Aircraft &a = aircraft[f.model];
        if (command == "BLOCK" || command == "UNBLOCK") {
            int seat = a.lookup[seatKey(v[2])];
            if (seat < 0) fail("no seat " + v[2] + " on " + f.name);
            if (command == "BLOCK" && f.blocked[seat]) fail("seat " + v[2] + " is blocked");
            if (command == "UNBLOCK" && !f.blocked[seat]) fail("seat " + v[2] + " is not blocked");
            f.blocked[seat] = command == "BLOCK";
            out.push_back(command + " " + f.name + " " + v[2]);
            int id = f.occupants[seat];
            if (command == "BLOCK" && id >= 0) {
                seatPerson(flight, id, -1);
                seatPerson(flight, id, chooseSeat(flight, id, people[id].cabin));
                out.push_back("DISPLACED " + bookings[people[id].booking].pnr + " " + people[id].name + " " + v[2] + " -> " + passengerResult(id));
            }
            reassign(flight, out);
        } else if (command == "UPGRADE") {
            vector<int> cabins;
            for (int c = 0; c < 3; ++c) if (a.cabins[c].from) cabins.push_back(c);
            int upgraded = 0;
            for (int pair = 0; pair + 1 < int(cabins.size()); ++pair) {
                int higher = cabins[pair], lower = cabins[pair + 1], booked = bookedCount(flight, higher);
                vector<std::pair<int, int>> targets;
                for (int id : f.passengers) if (people[id].active && people[id].cabin == lower && people[id].type == 0 && !hasInfant(id) && tier(id) < 3) targets.push_back({tier(id), id});
                std::stable_sort(targets.begin(), targets.end(), [](const std::pair<int, int> &x, const std::pair<int, int> &y) { return x.first < y.first; });
                for (const std::pair<int, int> &target : targets) {
                    if (booked >= f.limit[higher]) break;
                    int id = target.second, seat = chooseSeat(flight, id, higher);
                    if (seat < 0) break;
                    string old = passengerResult(id);
                    people[id].cabin = higher;
                    seatPerson(flight, id, seat);
                    ++booked;
                    ++upgraded;
                    out.push_back(text("UPGRADED ", bookings[people[id].booking].pnr, " ", people[id].name, " ", classes[lower], " ", old, " -> ", classes[higher], " ", seatName(a, seat)));
                }
            }
            reassign(flight, out);
            out.push_back(text("UPGRADE ", f.name, " ", upgraded));
        } else if (command == "CLOSE") {
            for (int b = 0; b < int(bookings.size()); ++b) {
                if (bookings[b].flight != flight || bookings[b].checked || !activeCount(b)) continue;
                out.push_back(text("NOSHOW ", bookings[b].pnr, " ", activeCount(b)));
                for (int id : bookings[b].people) removePerson(id);
            }
            reassign(flight, out);
            int denied = 0, compensation = 0;
            const int voluntary[] = {500, 300, 150}, involuntary[] = {1000, 600, 300};
            for (int cabin = 0; cabin < 3; ++cabin) {
                vector<int> targets;
                for (int id : f.volunteers) if (people[id].active && people[id].volunteer && people[id].seat >= 0 && people[id].cabin == cabin) targets.push_back(id);
                for (int id : targets) {
                    int seat = people[id].seat;
                    bool useful = false;
                    for (int other : f.passengers) {
                        if (people[other].active && people[other].type != 2 && people[other].cabin == cabin && people[other].seat < 0 && fits(flight, {other}, {seat}, {id})) useful = true;
                    }
                    if (!useful) continue;
                    out.push_back(text("DENIED VOLUNTARY ", bookings[people[id].booking].pnr, " ", people[id].name, " ", classes[cabin], " ", voluntary[cabin]));
                    ++denied;
                    compensation += voluntary[cabin];
                    removePerson(id);
                    reassign(flight, out);
                }
            }
            for (int id : f.passengers) {
                if (!people[id].active || people[id].type == 2 || people[id].seat >= 0) continue;
                int cabin = people[id].cabin, value = involuntary[cabin] / (people[id].type == 1 ? 2 : 1);
                out.push_back(text("DENIED INVOLUNTARY ", bookings[people[id].booking].pnr, " ", people[id].name, " ", classes[cabin], " ", value));
                ++denied;
                compensation += value;
                removePerson(id);
            }
            f.closed = true;
            out.push_back(text("CLOSED ", f.name, " denied ", denied, " compensation ", compensation));
        } else if (command == "MAP") {
            out.push_back("MAP " + f.name);
            for (int cabin = 0; cabin < 3; ++cabin) {
                const Cabin &c = a.cabins[cabin];
                if (!c.from) continue;
                out.push_back(text("CABIN ", classes[cabin]));
                out.push_back("   " + join(c.blocks, " "));
                for (int row = c.from; row <= c.to; ++row) {
                    string line = text(row < 10 ? " " : "", row, " ");
                    for (int block = 0; block < int(c.blocks.size()); ++block) {
                        if (block) line += " ";
                        for (char letter : c.blocks[block]) {
                            int seat = a.lookup[row * 26 + letter - 'A'];
                            line += f.blocked[seat] ? '#' : f.occupants[seat] >= 0 ? 'X' : a.exits[row] ? 'E' : '.';
                        }
                    }
                    out.push_back(line);
                }
            }
        } else if (command == "MANIFEST") {
            int seated = 0, unassigned = 0, infants = 0;
            vector<int> order;
            for (int owner : f.occupants) if (owner >= 0) order.push_back(owner);
            seated = int(order.size());
            for (int id : f.passengers) {
                if (!people[id].active) continue;
                if (people[id].type == 2) ++infants;
                else if (people[id].seat < 0) {
                    ++unassigned;
                    order.push_back(id);
                }
            }
            out.push_back(text("MANIFEST ", f.name, " seated ", seated, " unassigned ", unassigned, " infants ", infants));
            for (int id : order) {
                const Person &p = people[id];
                const Booking &b = bookings[p.booking];
                string line = text(p.seat < 0 ? "---" : seatName(a, p.seat), " ", classes[p.cabin], " ", b.pnr, " ", p.name, " ", typeNames[p.type]);
                if (hasInfant(id)) line += " +" + people[p.lap].name;
                if (tier(id) < 3) line += " " + tierNames[tier(id)];
                if (b.checked) line += " CHECKED";
                if (p.volunteer) line += " VOL";
                out.push_back(line);
            }
        } else if (command == "LOADFACTOR") {
            out.push_back("LOADFACTOR " + f.name);
            int allSeated = 0, allSeats = 0;
            for (int cabin = 0; cabin < 3; ++cabin) {
                if (!a.cabins[cabin].from) continue;
                int seats = 0, seated = 0;
                for (int i = 0; i < int(a.seats.size()); ++i) {
                    if (a.seats[i].cabin != cabin) continue;
                    seats += !f.blocked[i];
                    seated += f.occupants[i] >= 0;
                }
                int factor = seated * 1000 / seats;
                out.push_back(text(classes[cabin], " ", seated, "/", seats, " ", factor / 10, ".", factor % 10, "% booked ", bookedCount(flight, cabin), "/", f.limit[cabin]));
                allSeated += seated;
                allSeats += seats;
            }
            int factor = allSeated * 1000 / allSeats;
            out.push_back(text("ALL ", allSeated, "/", allSeats, " ", factor / 10, ".", factor % 10, "%"));
        } else if (command == "BALANCE") {
            int weight = 0, moment = 0;
            for (int id : f.occupants) {
                if (id < 0) continue;
                int value = people[id].type == 0 ? 80 : 40;
                if (hasInfant(id)) value += 10;
                weight += value;
                moment += value * (a.seats[people[id].seat].row - a.base);
            }
            string verdict = moment < -a.limit ? "NOSE-HEAVY" : moment > a.limit ? "TAIL-HEAVY" : "OK";
            out.push_back(text("BALANCE ", f.name, " weight ", weight, " moment ", moment, " limit ", a.limit, " ", verdict));
        } else if (command == "BOARDING") {
            struct Item { int id, group, zone, kind, row; char letter; };
            vector<Item> order;
            for (int id : f.occupants) {
                if (id < 0) continue;
                const Person &p = people[id];
                const Seat &s = a.seats[p.seat];
                int group = bookingInfants(p.booking) ? 0 : p.cabin < 2 ? 1 : tier(id) < 2 ? 2 : 3;
                int zone = group == 3 ? (s.row - a.cabins[2].from) / 5 + 1 : 0;
                order.push_back({id, group, zone, s.kind, s.row, s.letter});
            }
            std::sort(order.begin(), order.end(), [](const Item &x, const Item &y) {
                if (x.group != y.group) return x.group < y.group;
                if (x.group == 3) {
                    if (x.zone != y.zone) return x.zone > y.zone;
                    if (x.kind != y.kind) return x.kind < y.kind;
                    if (x.row != y.row) return x.row > y.row;
                } else if (x.row != y.row) return x.row < y.row;
                return x.letter < y.letter;
            });
            out.push_back(text("BOARDING ", f.name, " ", order.size()));
            for (int i = 0; i < int(order.size()); ++i) {
                const Item &item = order[i];
                const Person &p = people[item.id];
                string group = item.group == 3 ? text("ZONE", item.zone) : vector<string>{"PRE", "CABIN", "TIER"}[item.group];
                out.push_back(text(i + 1, " ", group, " ", seatName(a, p.seat), " ", bookings[p.booking].pnr, " ", p.name));
            }
        } else if (command == "AVAIL") {
            int cabin = cabinId(v[2]);
            if (!a.cabins[cabin].from) fail("no cabin " + v[2] + " on " + f.name);
            int free = 0, exits = 0;
            std::array<int, 3> kinds{};
            for (int i = 0; i < int(a.seats.size()); ++i) {
                const Seat &s = a.seats[i];
                if (s.cabin != cabin || f.blocked[i] || f.occupants[i] >= 0) continue;
                ++free;
                ++kinds[s.kind];
                exits += a.exits[s.row];
            }
            out.push_back(text("AVAIL ", f.name, " ", classes[cabin], " free ", free, " W ", kinds[0], " M ", kinds[1], " A ", kinds[2], " EXIT ", exits));
        }
    }
    return out;
}
int main() {
    string line;
    std::getline(std::cin, line);
    int count = std::stoi(line);
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        try {
            vector<string> out = execute(split(line));
            for (const string &result : out) std::cout << result << '\n';
        } catch (const std::runtime_error &error) { std::cout << "ERROR " << error.what() << '\n'; }
    }
}
