#include <algorithm>
#include <array>
#include <deque>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using namespace std;

constexpr array<const char*, 4> STATIONS{"GRILL", "FRY", "COLD", "BAR"};
constexpr array<const char*, 4> COURSES{"DRINK", "STARTER", "MAIN", "DESSERT"};

int station_index(const string& name) {
    for (int i = 0; i < 4; ++i)
        if (name == STATIONS[i]) return i;
    return -1;
}

int course_index(const string& name) {
    for (int i = 0; i < 4; ++i)
        if (name == COURSES[i]) return i;
    return -1;
}

long long cents(const string& text) {
    size_t point = text.find('.');
    return stoll(text.substr(0, point)) * 100 + stoll(text.substr(point + 1));
}

string money(long long amount) {
    ostringstream out;
    out << amount / 100 << '.' << setw(2) << setfill('0') << amount % 100;
    return out.str();
}

string clock_text(int elapsed) {
    int minutes = 660 + elapsed;
    ostringstream out;
    out << setw(2) << setfill('0') << minutes / 60 << ':'
        << setw(2) << minutes % 60;
    return out.str();
}

long long rounded(long long amount, int rate) {
    return (amount * rate + 50) / 100;
}

struct Check;

struct Table {
    int number;
    int seats;
    Check* check = nullptr;
};

struct Server {
    string name;
    int load = 0;
    int parties = 0;
    long long sales = 0;
    long long tips = 0;
};

struct MenuItem {
    string name;
    int station;
    int prep;
    long long price;
    int course;
    optional<int> stock;
};

struct OrderLine {
    int number;
    Check* check;
    int seat;
    string name;
    int quantity;
    int station;
    int prep;
    long long price;
    int course;
    string state = "ORDERED";
    optional<string> comp;
    int fire = 0;
    int ready = 0;
    bool started = false;

    long long amount() const {
        return comp ? 0 : price * quantity;
    }
    string tag() const { return "#" + to_string(number); }
};

struct Check {
    string party;
    int size;
    Table* table;
    Server* server;
    int since;
    vector<OrderLine*> lines;
    long long paid = 0;
    int discount = 0;
    bool closed = false;

    vector<OrderLine*> active() const {
        vector<OrderLine*> result;
        for (OrderLine* line : lines)
            if (line->state != "VOID") result.push_back(line);
        return result;
    }

    array<long long, 6> amounts() const {
        long long subtotal = 0;
        for (OrderLine* line : lines)
            if (line->state != "VOID") subtotal += line->amount();
        long long discount_amount = rounded(subtotal, discount);
        long long after = subtotal - discount_amount;
        long long service = size >= 6 ? rounded(after, 18) : 0;
        long long tax = rounded(after, 8);
        long long total = after + service + tax;
        return {subtotal, discount_amount, service, tax, total, total - paid};
    }
};

struct Station {
    string name;
    int capacity;
    bool up = true;
    deque<OrderLine*> queue;
    vector<OrderLine*> cooking;
    int tickets = 0;
    long long ticket_total = 0;
    int ticket_max = 0;
    int remakes = 0;
};

struct Waiting {
    string party;
    int size;
    int joined;
};

class Restaurant {
    int now = 0;
    map<int, Table> tables;
    vector<unique_ptr<Server>> servers;
    set<string> server_names;
    vector<Waiting> waiting;
    map<string, Check*> seated;
    map<string, MenuItem> menu;
    vector<unique_ptr<Check>> checks;
    vector<unique_ptr<OrderLine>> lines;
    array<Station, 4> stations{{
        {"GRILL", 1}, {"FRY", 1}, {"COLD", 1}, {"BAR", 2}
    }};
    int happy_rate = 0;
    optional<int> happy_until;
    int guests = 0;
    int parties = 0;
    int closed = 0;
    long long stay_total = 0;
    array<long long, 4> sales{};
    array<long long, 5> totals{};
    map<string, long long> payments{{"CASH", 0}, {"CARD", 0}};
    long long tips = 0;
    int comps = 0;
    long long comp_amount = 0;
    int voids = 0;
    map<string, long long> served;
    vector<string> output;

    [[noreturn]] static void fail(const string& error) {
        throw runtime_error(error);
    }

    template <typename... Args>
    void emit(const Args&... parts) {
        ostringstream out;
        bool first = true;
        ((out << (first ? "" : " ") << parts, first = false), ...);
        output.push_back(out.str());
    }

    static void remove_from(deque<OrderLine*>& queue, OrderLine* line) {
        auto found = find(queue.begin(), queue.end(), line);
        if (found != queue.end()) queue.erase(found);
    }

    Table& table(const string& text, bool occupied = false) {
        int number = stoi(text);
        auto found = tables.find(number);
        if (found == tables.end()) fail("unknown table " + text);
        if (occupied && !found->second.check) fail("table " + text + " is free");
        return found->second;
    }

    OrderLine& line(const string& text) {
        int number = stoi(text);
        if (number < 1 || number > static_cast<int>(lines.size()))
            fail("unknown line " + text);
        return *lines[number - 1];
    }

    static void unlocked(const Check& check) {
        if (check.paid)
            fail("check for table " + to_string(check.table->number) + " is locked");
    }

    void modification(const OrderLine& order) {
        if (order.state == "VOID") fail(order.tag() + " is void");
        if (order.check->closed) fail(order.tag() + " is on a closed check");
        unlocked(*order.check);
    }

    static void all_served(const Check& check) {
        int unserved = 0;
        for (OrderLine* line : check.lines)
            if (line->state != "VOID" && line->state != "SERVED") ++unserved;
        if (unserved)
            fail("table " + to_string(check.table->number) + " has " +
                 to_string(unserved) + " unserved items");
    }

    Table* select_table(int size) {
        Table* best = nullptr;
        for (auto& [number, table] : tables) {
            if (!table.check && table.seats >= size &&
                (!best || table.seats < best->seats ||
                 (table.seats == best->seats && table.number < best->number))) {
                best = &table;
            }
        }
        return best;
    }

    Check& seat_party(const string& party, int size, Table& target) {
        Server* assigned = nullptr;
        for (const auto& server : servers) {
            if (!assigned || server->load < assigned->load)
                assigned = server.get();
        }
        checks.push_back(make_unique<Check>(
            Check{party, size, &target, assigned, now}
        ));
        Check& check = *checks.back();
        target.check = &check;
        seated[party] = &check;
        ++assigned->load;
        ++assigned->parties;
        guests += size;
        ++parties;
        return check;
    }

    void process_waitlist() {
        vector<Waiting> remaining;
        for (const Waiting& entry : waiting) {
            Table* target = select_table(entry.size);
            if (!target) {
                remaining.push_back(entry);
            } else {
                Check& check = seat_party(entry.party, entry.size, *target);
                emit("SEATED", entry.party, entry.size, "table", target->number,
                     "server", check.server->name, "waited", now - entry.joined);
            }
        }
        waiting = move(remaining);
    }

    void close_check(Check& check) {
        auto amounts = check.amounts();
        for (OrderLine* line : check.active())
            sales[line->course] += line->amount();
        for (size_t i = 0; i < totals.size(); ++i)
            totals[i] += amounts[i];
        int stay = now - check.since;
        ++closed;
        stay_total += stay;
        check.server->sales += amounts[4];
        --check.server->load;
        check.closed = true;
        check.table->check = nullptr;
        seated.erase(check.party);
        emit("FREE", "table", check.table->number, check.party, "stayed", stay);
        process_waitlist();
    }

    void start_station(int station_index, int when) {
        Station& station = stations[station_index];
        while (station.up && !station.queue.empty() &&
               static_cast<int>(station.cooking.size()) < station.capacity) {
            OrderLine* order = station.queue.front();
            station.queue.pop_front();
            order->state = "COOKING";
            order->started = true;
            order->ready = when + order->prep;
            station.cooking.push_back(order);
        }
    }

    void start_all(int when) {
        for (int i = 0; i < 4; ++i) start_station(i, when);
    }

    static map<int, long long> seat_subtotals(const Check& check) {
        map<int, long long> subtotals;
        for (OrderLine* line : check.active())
            subtotals[line->seat] += line->amount();
        return subtotals;
    }

    static map<int, long long> allocate(const map<int, long long>& values, int rate) {
        map<int, long long> amounts;
        long long subtotal = 0, allocated = 0;
        vector<int> ranking;
        for (auto [seat, value] : values) {
            amounts[seat] = value * rate / 100;
            subtotal += value;
            allocated += amounts[seat];
            ranking.push_back(seat);
        }
        long long extra = rounded(subtotal, rate) - allocated;
        sort(ranking.begin(), ranking.end(), [&](int a, int b) {
            long long rem_a = values.at(a) * rate % 100;
            long long rem_b = values.at(b) * rate % 100;
            return rem_a != rem_b ? rem_a > rem_b : a < b;
        });
        for (int i = 0; i < extra; ++i) ++amounts[ranking[i]];
        return amounts;
    }

    void cmd_table(const vector<string>& a) {
        int number = stoi(a[0]), seats = stoi(a[1]);
        if (tables.count(number))
            fail("table " + a[0] + " already exists");
        tables.emplace(number, Table{number, seats});
        emit("TABLE", number, "seats", seats);
        process_waitlist();
    }

    void cmd_staff(const vector<string>& a) {
        string name = a[0];
        if (server_names.count(name)) fail(name + " is already on duty");
        servers.push_back(make_unique<Server>(Server{name}));
        server_names.insert(name);
        emit("STAFF", name);
    }

    void cmd_seat(const vector<string>& a) {
        string party = a[0];
        int size = stoi(a[1]);
        if (seated.count(party))
            fail(party + " is already seated at table " +
                 to_string(seated.at(party)->table->number));
        for (const Waiting& entry : waiting)
            if (entry.party == party) fail(party + " is already waiting");
        bool capacity = false;
        for (const auto& [number, table] : tables)
            if (table.seats >= size) capacity = true;
        if (!capacity) fail("no table for party of " + a[1]);
        if (servers.empty()) fail("no server on duty");
        Table* target = select_table(size);
        if (!target) {
            waiting.push_back(Waiting{party, size, now});
            emit("WAIT", party, size, "position", waiting.size());
        } else {
            Check& check = seat_party(party, size, *target);
            emit("SEAT", party, size, "table", target->number,
                 "server", check.server->name);
        }
    }

    void cmd_cancel(const vector<string>& a) {
        for (size_t i = 0; i < waiting.size(); ++i) {
            if (waiting[i].party == a[0]) {
                Waiting entry = waiting[i];
                waiting.erase(waiting.begin() + i);
                emit("CANCEL", entry.party, entry.size, "waited", now - entry.joined);
                return;
            }
        }
        fail(a[0] + " is not waiting");
    }

    void cmd_move(const vector<string>& a) {
        Table& source = table(a[0]);
        Table& destination = table(a[1]);
        if (!source.check) fail("table " + a[0] + " is free");
        if (destination.check) fail("table " + a[1] + " is occupied");
        Check& check = *source.check;
        if (destination.seats < check.size)
            fail("table " + a[1] + " is too small for " + check.party);
        source.check = nullptr;
        destination.check = &check;
        check.table = &destination;
        emit("MOVE", check.party, "table", a[0], "->", a[1]);
        process_waitlist();
    }

    void cmd_menu(const vector<string>& a) {
        int station = station_index(a[1]);
        if (station < 0) fail("unknown station " + a[1]);
        int course = course_index(a[4]);
        if (course < 0) fail("unknown course " + a[4]);
        int prep = stoi(a[2]);
        long long price = cents(a[3]);
        auto found = menu.find(a[0]);
        bool existing = found != menu.end();
        if (existing) {
            found->second.station = station;
            found->second.prep = prep;
            found->second.price = price;
            found->second.course = course;
        } else {
            menu.emplace(a[0], MenuItem{a[0], station, prep, price, course});
        }
        emit("MENU", existing ? "UPDATE" : "ADD", a[0], a[1],
             a[2], a[3], a[4]);
    }

    void cmd_stock(const vector<string>& a) {
        auto found = menu.find(a[0]);
        if (found == menu.end()) fail("unknown item " + a[0]);
        found->second.stock = stoi(a[1]);
        emit("STOCK", a[0], a[1]);
    }

    void cmd_happy(const vector<string>& a) {
        happy_rate = stoi(a[0]);
        happy_until = now + stoi(a[1]);
        emit("HAPPY", a[0] + "%", "until", clock_text(*happy_until));
    }

    void cmd_items(const vector<string>&) {
        emit("ITEMS", menu.size());
        vector<const MenuItem*> items;
        for (const auto& [name, item] : menu) items.push_back(&item);
        sort(items.begin(), items.end(), [](const MenuItem* a, const MenuItem* b) {
            return a->course != b->course ? a->course < b->course : a->name < b->name;
        });
        for (const MenuItem* item : items)
            emit(COURSES[item->course], item->name, STATIONS[item->station],
                 item->prep, money(item->price),
                 item->stock ? to_string(*item->stock) : "-");
    }

    void cmd_order(const vector<string>& a) {
        Table& target = table(a[0], true);
        Check& check = *target.check;
        unlocked(check);
        int seat = stoi(a[1]), quantity = stoi(a[3]);
        if (seat > check.size)
            fail("seat " + a[1] + " out of range for table " + a[0]);
        auto found = menu.find(a[2]);
        if (found == menu.end()) fail("unknown item " + a[2]);
        MenuItem& item = found->second;
        if (item.stock && *item.stock < quantity)
            fail("only " + to_string(*item.stock) + " " + item.name + " left");
        bool happy = item.course == 0 && happy_until && now < *happy_until;
        long long unit_price = item.price - (happy ? rounded(item.price, happy_rate) : 0);
        int number = static_cast<int>(lines.size()) + 1;
        lines.push_back(make_unique<OrderLine>(
            OrderLine{number, &check, seat, item.name, quantity,
                      item.station, item.prep, unit_price, item.course}
        ));
        OrderLine& order = *lines.back();
        check.lines.push_back(&order);
        string text = "ORDER " + order.tag() + " table " + a[0] + " seat " +
                      a[1] + " " + item.name + " x" + a[3] +
                      " " + money(order.amount());
        if (happy) text += " HAPPY";
        emit(text);
        if (item.stock) {
            *item.stock -= quantity;
            if (*item.stock == 0) emit("SOLDOUT", item.name);
        }
    }

    void cmd_fire(const vector<string>& a) {
        Check& check = *table(a[0], true).check;
        int course = course_index(a[1]);
        if (course < 0) fail("unknown course " + a[1]);
        vector<OrderLine*> selected;
        for (OrderLine* line : check.lines)
            if (line->course == course && line->state == "ORDERED") selected.push_back(line);
        if (selected.empty())
            fail("nothing to fire for " + a[1] + " at table " + a[0]);
        if (course == 2 || course == 3) {
            for (int earlier = 1; earlier < course; ++earlier) {
                for (OrderLine* line : check.lines)
                    if (line->course == earlier && line->state == "ORDERED")
                        fail("fire " + string(COURSES[earlier]) + " first");
            }
        }
        string text = "FIRE table " + a[0] + " " + a[1];
        for (OrderLine* line : selected) {
            line->state = "QUEUED";
            line->fire = now;
            stations[line->station].queue.push_back(line);
            text += " " + line->tag();
        }
        emit(text);
        start_all(now);
    }

    void cmd_tick(const vector<string>& a) {
        int target = now + stoi(a[0]);
        emit("TICK", clock_text(target));
        while (true) {
            int completion = -1;
            for (const Station& station : stations) {
                for (OrderLine* order : station.cooking) {
                    if (completion < 0 || order->ready < completion)
                        completion = order->ready;
                }
            }
            if (completion < 0 || completion > target) break;
            for (Station& station : stations) {
                vector<OrderLine*> finished;
                for (OrderLine* order : station.cooking)
                    if (order->ready == completion) finished.push_back(order);
                sort(finished.begin(), finished.end(), [](OrderLine* a, OrderLine* b) {
                    return a->number < b->number;
                });
                for (OrderLine* order : finished) {
                    station.cooking.erase(
                        find(station.cooking.begin(), station.cooking.end(), order));
                    order->state = "READY";
                    int ticket = completion - order->fire;
                    ++station.tickets;
                    station.ticket_total += ticket;
                    station.ticket_max = max(station.ticket_max, ticket);
                    emit("READY", clock_text(completion), station.name, order->tag(),
                         order->name, "x" + to_string(order->quantity), "table",
                         order->check->table->number, "seat", order->seat);
                }
            }
            start_all(completion);
        }
        now = target;
    }

    void cmd_serve(const vector<string>& a) {
        Check& check = *table(a[0], true).check;
        vector<OrderLine*> selected;
        for (OrderLine* order : check.lines)
            if (order->state == "READY") selected.push_back(order);
        if (selected.empty()) fail("nothing ready for table " + a[0]);
        string text = "SERVE table " + a[0];
        for (OrderLine* order : selected) {
            order->state = "SERVED";
            served[order->name] += order->quantity;
            text += " " + order->tag();
        }
        emit(text);
    }

    void cmd_rush(const vector<string>& a) {
        OrderLine& order = line(a[0]);
        if (order.state != "QUEUED") fail(order.tag() + " is not queued");
        Station& station = stations[order.station];
        remove_from(station.queue, &order);
        station.queue.push_front(&order);
        emit("RUSH", order.tag(), station.name);
    }

    void cmd_remake(const vector<string>& a) {
        OrderLine& order = line(a[0]);
        if (order.check->closed) fail(order.tag() + " is on a closed check");
        if (order.state != "READY" && order.state != "SERVED")
            fail(order.tag() + " is not ready or served");
        Station& station = stations[order.station];
        order.state = "QUEUED";
        order.fire = now;
        station.queue.push_front(&order);
        ++station.remakes;
        emit("REMAKE", order.tag(), order.name, station.name);
        start_station(order.station, now);
    }

    void cmd_void(const vector<string>& a) {
        OrderLine& order = line(a[0]);
        if (order.state == "VOID") fail(order.tag() + " is already void");
        if (order.started) fail(order.tag() + " has already started");
        if (order.state == "QUEUED")
            remove_from(stations[order.station].queue, &order);
        order.state = "VOID";
        MenuItem& item = menu.at(order.name);
        if (item.stock) *item.stock += order.quantity;
        ++voids;
        emit("VOID", order.tag(), order.name, "x" + to_string(order.quantity));
    }

    void cmd_station(const vector<string>& a) {
        int index = station_index(a[0]);
        if (index < 0) fail("unknown station " + a[0]);
        Station& station = stations[index];
        if (a[1] == "DOWN" && !station.up)
            fail("station " + a[0] + " is already down");
        if (a[1] == "UP" && station.up)
            fail("station " + a[0] + " is not down");
        station.up = a[1] == "UP";
        if (station.up) start_station(index, now);
        emit("STATION", a[0], a[1]);
    }

    void cmd_comp(const vector<string>& a) {
        OrderLine& order = line(a[0]);
        modification(order);
        if (order.comp) fail(order.tag() + " is already comped");
        long long amount = order.amount();
        emit("COMP", order.tag(), order.name, money(amount), a[1]);
        ++comps;
        comp_amount += amount;
        order.comp = a[1];
    }

    void cmd_transfer(const vector<string>& a) {
        OrderLine& order = line(a[0]);
        modification(order);
        int seat = stoi(a[1]), table_number = order.check->table->number;
        if (seat > order.check->size)
            fail("seat " + a[1] + " out of range for table " + to_string(table_number));
        if (seat == order.seat)
            fail(order.tag() + " is already on seat " + a[1]);
        emit("TRANSFER", order.tag(), "seat", order.seat, "->", seat);
        order.seat = seat;
    }

    void cmd_discount(const vector<string>& a) {
        Check& check = *table(a[0], true).check;
        unlocked(check);
        check.discount = stoi(a[1]);
        emit("DISCOUNT", "table", a[0], a[1] + "%");
    }

    void cmd_bill(const vector<string>& a) {
        Check& check = *table(a[0], true).check;
        emit("BILL", "table", a[0], check.party, "guests", check.size);
        auto subtotals = seat_subtotals(check);
        for (auto [seat, subtotal] : subtotals) {
            emit("SEAT", seat, money(subtotal));
            for (OrderLine* order : check.lines) {
                if (order->seat != seat || order->state == "VOID") continue;
                string text = order->tag() + " " + order->name + " x" +
                              to_string(order->quantity) + " " + money(order->amount());
                if (order->comp) text += " COMP " + *order->comp;
                emit(text);
            }
        }
        auto amounts = check.amounts();
        emit("SUBTOTAL", money(amounts[0]));
        if (check.discount)
            emit("DISCOUNT", to_string(check.discount) + "%", money(amounts[1]));
        if (check.size >= 6) emit("SERVICE", money(amounts[2]));
        emit("TAX", money(amounts[3]));
        emit("TOTAL", money(amounts[4]));
        if (check.paid) {
            emit("PAID", money(check.paid));
            emit("DUE", money(amounts[5]));
        }
    }

    void cmd_split(const vector<string>& a) {
        Check& check = *table(a[0], true).check;
        long long due = check.amounts()[5];
        if (due == 0) fail("nothing to split for table " + a[0]);
        if (a[1] == "EVEN") {
            int count = stoi(a[2]);
            if (count > check.size)
                fail("cannot split table " + a[0] + " " + a[2] + " ways");
            emit("SPLIT", "table", a[0], "EVEN", count, "due", money(due));
            for (int payer = 1; payer <= count; ++payer)
                emit("PAYER", payer, money(due / count + (payer <= due % count)));
            return;
        }
        if (check.paid) fail("table " + a[0] + " has payments");
        auto subtotals = seat_subtotals(check);
        auto discounts = allocate(subtotals, check.discount);
        map<int, long long> after, services, taxes;
        for (auto [seat, subtotal] : subtotals)
            after[seat] = subtotal - discounts[seat];
        if (check.size >= 6) services = allocate(after, 18);
        else for (auto [seat, subtotal] : subtotals) services[seat] = 0;
        taxes = allocate(after, 8);
        emit("SPLIT", "table", a[0], "BYSEAT", "total", money(check.amounts()[4]));
        for (auto [seat, subtotal] : subtotals) {
            long long part = after[seat] + services[seat] + taxes[seat];
            emit("SEAT", seat, "subtotal", money(subtotal),
                 "discount", money(discounts[seat]), "service", money(services[seat]),
                 "tax", money(taxes[seat]), "total", money(part));
        }
    }

    void cmd_pay(const vector<string>& a) {
        Check& check = *table(a[0], true).check;
        if (!payments.count(a[1])) fail("unknown method " + a[1]);
        all_served(check);
        long long due = check.amounts()[5];
        if (due == 0) fail("nothing to pay for table " + a[0]);
        long long value = cents(a[2]);
        long long applied = min(value, due);
        check.paid += applied;
        payments[a[1]] += applied;
        if (value < due) {
            emit("PAY", "table", a[0], a[1], a[2], "remaining", money(due - value));
        } else {
            long long excess = value - due;
            emit("PAY", "table", a[0], a[1], a[2],
                 a[1] == "CASH" ? "change" : "tip", money(excess));
            if (a[1] == "CARD") {
                tips += excess;
                check.server->tips += excess;
            }
            close_check(check);
        }
    }

    void cmd_close(const vector<string>& a) {
        Check& check = *table(a[0], true).check;
        all_served(check);
        long long due = check.amounts()[5];
        if (due) fail("table " + a[0] + " still owes " + money(due));
        close_check(check);
    }

    void cmd_status(const vector<string>& a) {
        Check& check = *table(a[0], true).check;
        emit("STATUS", "table", a[0], check.party, "guests", check.size,
             "since", clock_text(check.since));
        for (OrderLine* order : check.lines) {
            string text = order->tag() + " seat " + to_string(order->seat) + " " +
                          order->name + " x" + to_string(order->quantity) + " " +
                          COURSES[order->course] + " " + order->state;
            if (order->state == "COOKING") text += " until " + clock_text(order->ready);
            if (order->comp) text += " COMP " + *order->comp;
            emit(text);
        }
    }

    void cmd_kitchen(const vector<string>&) {
        emit("KITCHEN", clock_text(now));
        for (const Station& station : stations) {
            vector<OrderLine*> cooking = station.cooking;
            sort(cooking.begin(), cooking.end(), [](OrderLine* a, OrderLine* b) {
                return a->ready != b->ready ? a->ready < b->ready : a->number < b->number;
            });
            string cooking_text, queue_text;
            for (OrderLine* order : cooking) {
                if (!cooking_text.empty()) cooking_text += " ";
                cooking_text += order->tag() + "@" + clock_text(order->ready);
            }
            for (OrderLine* order : station.queue) {
                if (!queue_text.empty()) queue_text += " ";
                queue_text += order->tag();
            }
            emit(station.name, station.up ? "up" : "down", "cooking",
                 cooking_text.empty() ? "-" : cooking_text, "queue",
                 queue_text.empty() ? "-" : queue_text);
        }
    }

    void cmd_floor(const vector<string>&) {
        int occupied = 0;
        for (const auto& [number, table] : tables)
            if (table.check) ++occupied;
        emit("FLOOR", clock_text(now), "free", tables.size() - occupied,
             "seated", occupied, "waiting", waiting.size());
        for (auto& [number, table] : tables) {
            if (!table.check) {
                emit("table", number, "seats", table.seats, "free");
                continue;
            }
            Check& check = *table.check;
            string text = "table " + to_string(number) + " seats " + to_string(table.seats) +
                          " " + check.party + " guests " + to_string(check.size) +
                          " server " + check.server->name + " since " +
                          clock_text(check.since) + " items " +
                          to_string(check.active().size()) + " total " +
                          money(check.amounts()[4]);
            if (check.paid) text += " paid " + money(check.paid);
            emit(text);
        }
        int position = 0;
        for (const Waiting& entry : waiting)
            emit("WAITING", ++position, entry.party, entry.size,
                 "since", clock_text(entry.joined));
    }

    void cmd_report(const vector<string>&) {
        emit("REPORT", clock_text(now));
        emit("COVERS", guests, "parties", parties);
        emit("TURNS", closed, "avg_stay",
             closed ? to_string(stay_total / closed) : "-");
        emit("SALES", "DRINK", money(sales[0]), "STARTER", money(sales[1]),
             "MAIN", money(sales[2]), "DESSERT", money(sales[3]));
        emit("TOTALS", "subtotal", money(totals[0]), "discount", money(totals[1]),
             "service", money(totals[2]), "tax", money(totals[3]),
             "total", money(totals[4]));
        emit("PAYMENTS", "cash", money(payments["CASH"]),
             "card", money(payments["CARD"]), "tips", money(tips));
        emit("COMPS", comps, money(comp_amount), "VOIDS", voids);
        vector<pair<string, long long>> top(served.begin(), served.end());
        sort(top.begin(), top.end(), [](const auto& a, const auto& b) {
            return a.second != b.second ? a.second > b.second : a.first < b.first;
        });
        for (size_t i = 0; i < min<size_t>(3, top.size()); ++i)
            emit("TOP", i + 1, top[i].first, top[i].second);
        for (const Station& station : stations)
            emit(station.name, "tickets", station.tickets, "avg",
                 station.tickets ? to_string(station.ticket_total / station.tickets) : "-",
                 "max", station.tickets ? to_string(station.ticket_max) : "-",
                 "remakes", station.remakes);
        for (const auto& server : servers)
            emit("SERVER", server->name, "tables", server->load, "parties",
                 server->parties, "sales", money(server->sales), "tips",
                 money(server->tips));
    }

public:
    void execute(const string& input) {
        istringstream source(input);
        vector<string> parts;
        for (string part; source >> part;) parts.push_back(part);
        if (parts.empty()) return;
        string command = parts.front();
        vector<string> a(parts.begin() + 1, parts.end());
        try {
            if (command == "TABLE") cmd_table(a);
            else if (command == "STAFF") cmd_staff(a);
            else if (command == "SEAT") cmd_seat(a);
            else if (command == "CANCEL") cmd_cancel(a);
            else if (command == "MOVE") cmd_move(a);
            else if (command == "MENU") cmd_menu(a);
            else if (command == "STOCK") cmd_stock(a);
            else if (command == "HAPPY") cmd_happy(a);
            else if (command == "ITEMS") cmd_items(a);
            else if (command == "ORDER") cmd_order(a);
            else if (command == "FIRE") cmd_fire(a);
            else if (command == "TICK") cmd_tick(a);
            else if (command == "SERVE") cmd_serve(a);
            else if (command == "RUSH") cmd_rush(a);
            else if (command == "REMAKE") cmd_remake(a);
            else if (command == "VOID") cmd_void(a);
            else if (command == "STATION") cmd_station(a);
            else if (command == "COMP") cmd_comp(a);
            else if (command == "TRANSFER") cmd_transfer(a);
            else if (command == "DISCOUNT") cmd_discount(a);
            else if (command == "BILL") cmd_bill(a);
            else if (command == "SPLIT") cmd_split(a);
            else if (command == "PAY") cmd_pay(a);
            else if (command == "CLOSE") cmd_close(a);
            else if (command == "STATUS") cmd_status(a);
            else if (command == "KITCHEN") cmd_kitchen(a);
            else if (command == "FLOOR") cmd_floor(a);
            else if (command == "REPORT") cmd_report(a);
        } catch (const runtime_error& error) {
            emit("ERROR", error.what());
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
    Restaurant restaurant;
    string command;
    for (int i = 0; i < count; ++i) {
        getline(cin, command);
        restaurant.execute(command);
    }
    restaurant.print();
}
