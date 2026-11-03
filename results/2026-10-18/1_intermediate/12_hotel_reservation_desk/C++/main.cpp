#include <algorithm>
#include <array>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using namespace std;
using Money = long long;

const array<string, 3> room_types{"SINGLE", "DOUBLE", "SUITE"};
const array<string, 7> weekdays{"SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI"};
const array<int, 12> normal_months{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

bool leap(int year) {
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

int days_in_month(int year, int month) {
    return month == 2 && leap(year) ? 29 : normal_months[month - 1];
}

int year_length(int year) {
    return leap(year) ? 366 : 365;
}

int date_number(const string& text) {
    int year = stoi(text.substr(0, 4));
    int month = stoi(text.substr(5, 2));
    int day = stoi(text.substr(8, 2));
    if (year < 2000 || year > 2099 || month < 1 || month > 12 ||
        day < 1 || day > days_in_month(year, month))
        throw runtime_error("invalid date " + text);

    int number = 0;
    for (int y = 2000; y < year; ++y) number += year_length(y);
    for (int m = 1; m < month; ++m) number += days_in_month(year, m);
    return number + day - 1;
}

string date_text(int number) {
    int year = 2000;
    while (number >= year_length(year)) {
        number -= year_length(year);
        ++year;
    }
    int month = 1;
    while (number >= days_in_month(year, month)) {
        number -= days_in_month(year, month);
        ++month;
    }
    ostringstream out;
    out << setw(4) << setfill('0') << year << '-'
        << setw(2) << month << '-' << setw(2) << (number + 1);
    return out.str();
}

string date_weekday(int day) {
    return date_text(day) + " " + weekdays[day % 7];
}

Money cents(const string& text) {
    size_t point = text.find('.');
    return stoll(text.substr(0, point)) * 100 + stoll(text.substr(point + 1));
}

string money(Money cents_amount) {
    ostringstream out;
    out << cents_amount / 100 << '.' << setw(2) << setfill('0') << cents_amount % 100;
    return out.str();
}

struct Room {
    int number;
    string kind;
    Money rate;
    bool clean = true;
};

struct Season {
    int first;
    int last;
    int percentage;
};

struct Night {
    int day;
    int room;
    Money rate;
};

struct Bill {
    Money lodging;
    Money discount;
    Money penalty;
    Money extras;
    Money tax;
    Money total;
};

struct Reservation {
    string id;
    string guest;
    Room* room;
    int arrival;
    int departure;
    vector<Night> nights;
    string status = "booked";
    vector<pair<string, Money>> extras;
    Money deposit = 0;
    Money paid = 0;
    optional<int> posting;
    Money fee = 0;
    optional<pair<int, Money>> penalty;
    optional<Bill> bill;

    Reservation(string identifier, string guest_name, Room* booked_room,
                int first, int last, vector<Night> assigned)
        : id(move(identifier)), guest(move(guest_name)), room(booked_room),
          arrival(first), departure(last), nights(move(assigned)) {}

    Money lodging() const {
        Money value = 0;
        for (const Night& night : nights) value += night.rate;
        return value;
    }
    Money first_rate() const {
        return nights.front().rate;
    }
};

struct WaitingEntry {
    string id;
    string guest;
    string kind;
    int arrival;
    int departure;
};

class HotelDesk {
    int today = date_number("2026-01-01");
    map<int, Room> rooms;
    vector<Season> seasons;
    set<pair<int, int>> blocked;
    map<string, Reservation> reservations;
    vector<string> reservation_order;
    vector<WaitingEntry> waitlist;
    set<string> used_ids;
    map<pair<int, int>, pair<Reservation*, Money>> occupied;
    vector<string> output;

    template<typename... Args>
    void emit(bool indented, const Args&... args) {
        ostringstream out;
        out << (indented ? "  " : "");
        bool first = true;
        ((out << (first ? "" : " ") << args, first = false), ...);
        output.push_back(out.str());
    }

    template<typename... Args>
    void say(const Args&... args) { emit(false, args...); }

    template<typename... Args>
    void say_indented(const Args&... args) { emit(true, args...); }

    static void require_type(const string& kind) {
        if (find(room_types.begin(), room_types.end(), kind) == room_types.end())
            throw runtime_error("invalid type " + kind);
    }

    Room& require_room(const string& text) {
        auto it = rooms.find(stoi(text));
        if (it == rooms.end()) throw runtime_error("unknown room " + text);
        return it->second;
    }

    void require_unused(const string& id) {
        if (used_ids.count(id)) throw runtime_error("duplicate reservation " + id);
    }

    Reservation& require_reservation(const string& id, const string& status = "") {
        auto it = reservations.find(id);
        if (it == reservations.end()) throw runtime_error("unknown reservation " + id);
        if (!status.empty() && it->second.status != status)
            throw runtime_error("invalid status " + id + " " + it->second.status);
        return it->second;
    }

    pair<int, int> stay(const string& first, const string& last) {
        int arrival = date_number(first);
        int departure = date_number(last);
        if (arrival < today) throw runtime_error("past date " + first);
        if (departure <= arrival)
            throw runtime_error("invalid range " + first + " " + last);
        if (departure - arrival > 30)
            throw runtime_error("too long " + to_string(departure - arrival));
        return {arrival, departure};
    }

    pair<int, int> period(const string& first, const string& last,
                          bool past_restricted = false, bool limited = true) {
        int start = date_number(first);
        int end = date_number(last);
        if (past_restricted && start < today)
            throw runtime_error("past date " + first);
        if (end < start) throw runtime_error("invalid range " + first + " " + last);
        if (limited && end - start + 1 > 31)
            throw runtime_error("too long " + to_string(end - start + 1));
        return {start, end};
    }

    Money night_rate(const Room& room, int day) const {
        for (auto it = seasons.rbegin(); it != seasons.rend(); ++it)
            if (it->first <= day && day <= it->last)
                return room.rate * it->percentage / 100;
        return room.rate;
    }

    vector<Night> price(const Room& room, int first, int last) const {
        vector<Night> nights;
        for (int day = first; day < last; ++day)
            nights.push_back({day, room.number, night_rate(room, day)});
        return nights;
    }

    optional<int> first_unavailable(const Room& room, int first, int last,
                                    const Reservation* except_for = nullptr) const {
        for (int day = first; day < last; ++day) {
            pair<int, int> key{day, room.number};
            if (blocked.count(key)) return day;
            auto holder = occupied.find(key);
            if (holder != occupied.end() && holder->second.first != except_for)
                return day;
        }
        return nullopt;
    }

    Room* free_room(const string& kind, int first, int last,
                     const Reservation* except_for = nullptr) {
        for (auto& [number, room] : rooms)
            if (room.kind == kind &&
                !first_unavailable(room, first, last, except_for))
                return &room;
        return nullptr;
    }

    Reservation* inhouse(const Room& room) {
        for (const string& id : reservation_order) {
            Reservation& reservation = reservations.at(id);
            if (reservation.status == "inhouse" && reservation.room == &room)
                return &reservation;
        }
        return nullptr;
    }

    void occupy(Reservation& reservation, const vector<Night>& nights) {
        for (const Night& night : nights)
            occupied[{night.day, night.room}] = {&reservation, night.rate};
    }

    void release(const Reservation& reservation, optional<int> first = nullopt) {
        for (const Night& night : reservation.nights)
            if (!first || night.day >= *first)
                occupied.erase({night.day, night.room});
    }

    void create_reservation(const string& id, const string& guest,
                            Room& room, int arrival, int departure, bool indent = false) {
        auto nights = price(room, arrival, departure);
        auto inserted = reservations.emplace(
            piecewise_construct,
            forward_as_tuple(id),
            forward_as_tuple(id, guest, &room, arrival, departure, move(nights))
        );
        Reservation& reservation = inserted.first->second;
        reservation_order.push_back(id);
        used_ids.insert(id);
        occupy(reservation, reservation.nights);
        emit(indent, "BOOK", id, guest, "room", room.number, room.kind,
             date_text(arrival), "->", date_text(departure), "nights", departure - arrival,
             "total", money(reservation.lodging()));
    }

    Money guest_total(const string& guest) const {
        Money paid = 0;
        for (const auto& [id, reservation] : reservations)
            if (reservation.guest == guest) paid += reservation.paid;
        return paid;
    }

    string tier(const string& guest) const {
        Money points = guest_total(guest) / 100;
        return points >= 2000 ? "GOLD" : points >= 500 ? "SILVER" : "BRONZE";
    }

    Bill calculate_bill(const Reservation& reservation) const {
        Money lodging = reservation.lodging();
        string category = tier(reservation.guest);
        int percentage = category == "GOLD" ? 10 : category == "SILVER" ? 5 : 0;
        Money discount = lodging * percentage / 100;
        Money penalty = reservation.penalty ? reservation.penalty->second : 0;
        Money extras = 0;
        for (const auto& entry : reservation.extras) extras += entry.second;
        Money subtotal = lodging - discount + penalty + extras;
        Money tax = subtotal / 10;
        return {lodging, discount, penalty, extras, tax, subtotal + tax};
    }

    string deposit_parts(const Reservation& reservation, Money total) const {
        if (total >= reservation.deposit)
            return "deposit " + money(reservation.deposit) + " due " +
                   money(total - reservation.deposit);
        return "deposit " + money(reservation.deposit) + " refund " +
               money(reservation.deposit - total);
    }

    void check_out(Reservation& reservation, int day, bool indent = false) {
        if (day < reservation.departure) {
            auto night = find_if(reservation.nights.begin(), reservation.nights.end(),
                                 [day](const Night& item) { return item.day == day; });
            Money penalty = night->rate;
            reservation.penalty = make_pair(day, penalty);
            release(reservation, day);
            reservation.nights.erase(
                remove_if(reservation.nights.begin(), reservation.nights.end(),
                          [day](const Night& item) { return item.day >= day; }),
                reservation.nights.end());
            reservation.departure = day;
        }
        Bill bill = calculate_bill(reservation);
        reservation.bill = bill;
        reservation.paid = bill.total;
        reservation.status = "checkedout";
        reservation.posting = day;
        reservation.room->clean = false;
        emit(indent, "CHECKOUT", reservation.id, "nights", reservation.nights.size(),
             "lodging", money(bill.lodging), "discount", money(bill.discount),
             "penalty", money(bill.penalty), "extras", money(bill.extras),
             "tax", money(bill.tax), "total", money(bill.total),
             deposit_parts(reservation, bill.total));
    }

    void process_waitlist() {
        vector<WaitingEntry> remaining;
        for (const WaitingEntry& entry : waitlist) {
            if (entry.arrival < today) {
                say_indented("WAITLIST", entry.id, "expired");
                continue;
            }
            Room* room = free_room(entry.kind, entry.arrival, entry.departure);
            if (!room) remaining.push_back(entry);
            else create_reservation(entry.id, entry.guest, *room,
                                    entry.arrival, entry.departure, true);
        }
        waitlist = move(remaining);
    }

    void cmd_room(const vector<string>& a) {
        int number = stoi(a[0]);
        if (rooms.count(number)) throw runtime_error("duplicate room " + a[0]);
        require_type(a[1]);
        rooms.emplace(number, Room{number, a[1], cents(a[2])});
        say("ROOM", a[0], a[1], a[2]);
    }

    void cmd_rate(const vector<string>& a) {
        Room& room = require_room(a[0]);
        Money previous = room.rate;
        room.rate = cents(a[1]);
        say("RATE", a[0], money(previous), "->", a[1]);
    }

    void cmd_season(const vector<string>& a) {
        auto [first, last] = period(a[0], a[1], false, false);
        seasons.push_back({first, last, stoi(a[2])});
        say("SEASON", seasons.size(), a[0], "->", a[1], a[2] + "%");
    }

    void cmd_block(const vector<string>& a) {
        Room& room = require_room(a[0]);
        auto [first, last] = period(a[1], a[2], true);
        for (int day = first; day <= last; ++day)
            if (occupied.count({day, room.number}))
                throw runtime_error("room unavailable " + a[0] + " " + date_text(day));
        int added = 0;
        for (int day = first; day <= last; ++day)
            added += blocked.insert({day, room.number}).second;
        say("BLOCK", a[0], a[1], "->", a[2], "added", added);
    }

    void cmd_unblock(const vector<string>& a) {
        Room& room = require_room(a[0]);
        auto [first, last] = period(a[1], a[2], true);
        int removed = 0;
        for (int day = first; day <= last; ++day)
            removed += static_cast<int>(blocked.erase({day, room.number}));
        say("UNBLOCK", a[0], a[1], "->", a[2], "removed", removed);
    }

    void cmd_clean(const vector<string>& a) {
        Room& room = require_room(a[0]);
        if (room.clean) throw runtime_error("already clean " + a[0]);
        room.clean = true;
        say("CLEAN", a[0]);
    }

    void cmd_today(const vector<string>& a) {
        int day = date_number(a[0]);
        if (day < today) throw runtime_error("past date " + a[0]);
        say("TODAY", date_weekday(day));
        vector<Reservation*> departing, absent;
        for (auto& [id, reservation] : reservations)
            if (reservation.status == "inhouse" && reservation.departure < day)
                departing.push_back(&reservation);
        sort(departing.begin(), departing.end(), [](const auto* x, const auto* y) {
            return tie(x->departure, x->id) < tie(y->departure, y->id);
        });
        for (Reservation* reservation : departing)
            check_out(*reservation, reservation->departure, true);

        for (auto& [id, reservation] : reservations)
            if (reservation.status == "booked" && reservation.arrival < day)
                absent.push_back(&reservation);
        sort(absent.begin(), absent.end(), [](const auto* x, const auto* y) {
            return tie(x->arrival, x->id) < tie(y->arrival, y->id);
        });
        for (Reservation* reservation : absent) {
            release(*reservation);
            reservation->fee = reservation->first_rate();
            reservation->paid = reservation->fee;
            reservation->status = "noshow";
            reservation->posting = reservation->arrival;
            say_indented("NOSHOW", reservation->id, reservation->guest, "fee",
                         money(reservation->fee), deposit_parts(*reservation, reservation->fee));
        }
        today = day;
    }

    void cmd_book(const vector<string>& a) {
        require_unused(a[0]);
        require_type(a[2]);
        auto [arrival, departure] = stay(a[3], a[4]);
        Room* room = free_room(a[2], arrival, departure);
        if (!room)
            throw runtime_error("no availability " + a[2] + " " + a[3] + " " + a[4]);
        create_reservation(a[0], a[1], *room, arrival, departure);
    }

    void cmd_bookroom(const vector<string>& a) {
        require_unused(a[0]);
        Room& room = require_room(a[2]);
        auto [arrival, departure] = stay(a[3], a[4]);
        auto unavailable = first_unavailable(room, arrival, departure);
        if (unavailable)
            throw runtime_error("room unavailable " + a[2] + " " + date_text(*unavailable));
        create_reservation(a[0], a[1], room, arrival, departure);
    }

    void cmd_waitlist(const vector<string>& a) {
        require_unused(a[0]);
        require_type(a[2]);
        auto [arrival, departure] = stay(a[3], a[4]);
        Room* room = free_room(a[2], arrival, departure);
        if (room) create_reservation(a[0], a[1], *room, arrival, departure);
        else {
            waitlist.push_back({a[0], a[1], a[2], arrival, departure});
            used_ids.insert(a[0]);
            say("WAITLIST", a[0], "queued position", waitlist.size());
        }
    }

    void cmd_modify(const vector<string>& a) {
        Reservation& reservation = require_reservation(a[0], "booked");
        auto [arrival, departure] = stay(a[1], a[2]);
        Room* room = reservation.room;
        string choice = "kept";
        if (first_unavailable(*room, arrival, departure, &reservation)) {
            Room* available = free_room(room->kind, arrival, departure, &reservation);
            if (!available)
                throw runtime_error("no availability " + room->kind + " " + a[1] + " " + a[2]);
            room = available;
            choice = "reassigned";
        }
        vector<Night> nights = price(*room, arrival, departure);
        release(reservation);
        reservation.room = room;
        reservation.arrival = arrival;
        reservation.departure = departure;
        reservation.nights = move(nights);
        occupy(reservation, reservation.nights);
        say("MODIFY", a[0], "room", room->number, choice, a[1], "->", a[2],
            "nights", departure - arrival, "total", money(reservation.lodging()));
    }

    void cmd_cancel(const vector<string>& a) {
        auto waiting = find_if(waitlist.begin(), waitlist.end(),
                               [&](const WaitingEntry& entry) { return entry.id == a[0]; });
        if (waiting != waitlist.end()) {
            waitlist.erase(waiting);
            say("CANCEL", a[0], "waitlist removed");
            return;
        }
        Reservation& reservation = require_reservation(a[0], "booked");
        int days = reservation.arrival - today;
        Money first = reservation.first_rate();
        Money fee = days >= 7 ? 0 : days >= 1 ? first / 2 : first;
        release(reservation);
        reservation.fee = fee;
        reservation.paid = fee;
        reservation.status = "cancelled";
        reservation.posting = today;
        say("CANCEL", a[0], "days", days, "fee", money(fee),
            deposit_parts(reservation, fee));
    }

    void cmd_checkin(const vector<string>& a) {
        Reservation& reservation = require_reservation(a[0], "booked");
        if (reservation.arrival != today)
            throw runtime_error("not arrival date " + a[0] + " " + date_text(reservation.arrival));
        Reservation* occupant = inhouse(*reservation.room);
        if (occupant)
            throw runtime_error("room occupied " + to_string(reservation.room->number) +
                                " " + occupant->id);
        if (!reservation.room->clean)
            throw runtime_error("room dirty " + to_string(reservation.room->number));
        reservation.status = "inhouse";
        say("CHECKIN", a[0], reservation.guest, "room", reservation.room->number,
            "until", date_text(reservation.departure));
    }

    void cmd_move(const vector<string>& a) {
        Reservation& reservation = require_reservation(a[0], "inhouse");
        Room& room = require_room(a[1]);
        Room* previous = reservation.room;
        if (&room == previous) throw runtime_error("same room " + a[1]);
        vector<Night> remaining;
        for (const Night& night : reservation.nights)
            if (night.day >= today) remaining.push_back(night);
        if (remaining.empty()) throw runtime_error("no remaining nights " + a[0]);
        auto unavailable = first_unavailable(room, remaining.front().day,
                                             reservation.departure, &reservation);
        if (unavailable)
            throw runtime_error("room unavailable " + a[1] + " " + date_text(*unavailable));
        Reservation* occupant = inhouse(room);
        if (occupant)
            throw runtime_error("room occupied " + a[1] + " " + occupant->id);
        if (!room.clean) throw runtime_error("room dirty " + a[1]);
        release(reservation, today);
        for (Night& night : reservation.nights)
            if (night.day >= today) night.room = room.number;
        vector<Night> changed;
        for (const Night& night : reservation.nights)
            if (night.day >= today) changed.push_back(night);
        occupy(reservation, changed);
        previous->clean = false;
        reservation.room = &room;
        say("MOVE", a[0], previous->number, "->", room.number, "nights", remaining.size());
    }

    void cmd_extend(const vector<string>& a) {
        Reservation& reservation = require_reservation(a[0], "inhouse");
        int departure = date_number(a[1]);
        if (departure <= reservation.departure)
            throw runtime_error("invalid range " + date_text(reservation.departure) + " " + a[1]);
        if (departure - reservation.arrival > 30)
            throw runtime_error("too long " + to_string(departure - reservation.arrival));
        auto unavailable = first_unavailable(*reservation.room,
                                             reservation.departure, departure, &reservation);
        if (unavailable)
            throw runtime_error("room unavailable " + to_string(reservation.room->number) +
                                " " + date_text(*unavailable));
        vector<Night> nights = price(*reservation.room, reservation.departure, departure);
        reservation.nights.insert(reservation.nights.end(), nights.begin(), nights.end());
        occupy(reservation, nights);
        reservation.departure = departure;
        say("EXTEND", a[0], "until", a[1], "nights", reservation.nights.size(),
            "total", money(reservation.lodging()));
    }

    void cmd_charge(const vector<string>& a) {
        Reservation& reservation = require_reservation(a[0], "inhouse");
        Money value = cents(a[1]);
        if (value == 0) throw runtime_error("invalid amount");
        reservation.extras.emplace_back(a[2], value);
        Money total = 0;
        for (const auto& charge : reservation.extras) total += charge.second;
        say("CHARGE", a[0], a[2], a[1], "extras", money(total));
    }

    void cmd_pay(const vector<string>& a) {
        Reservation& reservation = require_reservation(a[0]);
        if (reservation.status != "booked" && reservation.status != "inhouse")
            throw runtime_error("invalid status " + a[0] + " " + reservation.status);
        Money value = cents(a[1]);
        if (value == 0) throw runtime_error("invalid amount");
        reservation.deposit += value;
        say("PAY", a[0], a[1], "deposit", money(reservation.deposit));
    }

    void cmd_checkout(const vector<string>& a) {
        check_out(require_reservation(a[0], "inhouse"), today);
    }

    void cmd_invoice(const vector<string>& a) {
        Reservation& reservation = require_reservation(a[0]);
        say("INVOICE", reservation.id, reservation.guest, "room",
            reservation.room->number, reservation.room->kind, reservation.status);
        if (reservation.status == "cancelled" || reservation.status == "noshow") {
            say_indented(reservation.status == "cancelled" ? "cancellation" : "noshow",
                         "fee", money(reservation.fee));
            say_indented("total", money(reservation.fee));
            say_indented(deposit_parts(reservation, reservation.fee));
            return;
        }
        for (const Night& night : reservation.nights)
            say_indented(date_weekday(night.day), "room", night.room, money(night.rate));
        Bill bill = reservation.bill ? *reservation.bill : calculate_bill(reservation);
        say_indented("lodging", money(bill.lodging));
        say_indented("discount", money(bill.discount));
        if (reservation.penalty)
            say_indented("penalty", date_weekday(reservation.penalty->first),
                         money(bill.penalty));
        for (const auto& charge : reservation.extras)
            say_indented("extra", charge.first, money(charge.second));
        say_indented("tax", money(bill.tax));
        say_indented("total", money(bill.total));
        say_indented(deposit_parts(reservation, bill.total));
    }

    void cmd_avail(const vector<string>& a) {
        require_type(a[0]);
        auto [first, last] = period(a[1], a[2]);
        say("AVAIL", a[0], a[1], "->", a[2]);
        for (int day = first; day <= last; ++day) {
            ostringstream line;
            vector<int> free;
            for (const auto& [number, room] : rooms) {
                if (room.kind != a[0] ||
                    blocked.count({day, number}) || occupied.count({day, number}))
                    continue;
                free.push_back(number);
            }
            line << date_weekday(day) << " free " << free.size();
            for (int number : free) line << ' ' << number;
            say_indented(line.str());
        }
    }

    string occupancy_parts(const vector<const Room*>& selected, int day) const {
        int blocked_count = 0, occupied_count = 0;
        for (const Room* room : selected) {
            blocked_count += blocked.count({day, room->number}) != 0;
            occupied_count += occupied.count({day, room->number}) != 0;
        }
        int available = static_cast<int>(selected.size()) - blocked_count;
        string rate = available ? to_string(occupied_count * 100 / available) + "%" : "n/a";
        return "rooms " + to_string(selected.size()) + " blocked " +
               to_string(blocked_count) + " occupied " + to_string(occupied_count) +
               " rate " + rate;
    }

    void cmd_occupancy(const vector<string>& a) {
        int day = date_number(a[0]);
        vector<const Room*> all;
        for (const auto& [number, room] : rooms) all.push_back(&room);
        say("OCCUPANCY", date_weekday(day), occupancy_parts(all, day));
        for (const string& kind : room_types) {
            vector<const Room*> selected;
            for (const auto& [number, room] : rooms)
                if (room.kind == kind) selected.push_back(&room);
            if (!selected.empty())
                say_indented(kind, occupancy_parts(selected, day));
        }
    }

    tuple<int, int, Money> daily_values(int day) const {
        int available = static_cast<int>(rooms.size()), occupied_count = 0;
        Money revenue = 0;
        for (const auto& [number, room] : rooms) {
            available -= blocked.count({day, number}) != 0;
            auto holder = occupied.find({day, number});
            if (holder != occupied.end()) {
                ++occupied_count;
                revenue += holder->second.second;
            }
        }
        return {available, occupied_count, revenue};
    }

    static string metrics_parts(int available, int occupied_count, Money revenue) {
        string rate = available ?
            to_string(occupied_count * 100 / available) + "%" : "n/a";
        string adr = occupied_count ? money(revenue / occupied_count) : "n/a";
        string revpar = available ? money(revenue / available) : "n/a";
        return "sold " + to_string(occupied_count) + "/" + to_string(available) +
               " rate " + rate + " revenue " + money(revenue) +
               " adr " + adr + " revpar " + revpar;
    }

    void cmd_stats(const vector<string>& a) {
        auto [first, last] = period(a[0], a[1]);
        int total_available = 0, total_occupied = 0;
        Money total_revenue = 0;
        say("STATS", a[0], "->", a[1]);
        for (int day = first; day <= last; ++day) {
            auto [available, taken, revenue] = daily_values(day);
            total_available += available;
            total_occupied += taken;
            total_revenue += revenue;
            say_indented(date_weekday(day), metrics_parts(available, taken, revenue));
        }
        say_indented("total", metrics_parts(total_available, total_occupied, total_revenue));
    }

    void cmd_rooms() {
        say("ROOMS", date_weekday(today), "rooms", rooms.size());
        for (const auto& [number, room] : rooms) {
            ostringstream line;
            line << number << ' ' << room.kind << " base " << money(room.rate)
                 << " tonight " << money(night_rate(room, today))
                 << (room.clean ? " clean" : " dirty");
            Reservation* occupant = inhouse(room);
            if (occupant) line << " occupied " << occupant->id;
            else if (blocked.count({today, number})) line << " blocked";
            else line << " vacant";
            const Reservation* upcoming = nullptr;
            for (const auto& [id, reservation] : reservations) {
                if (reservation.status != "booked" || reservation.room != &room) continue;
                if (!upcoming || reservation.arrival < upcoming->arrival ||
                    (reservation.arrival == upcoming->arrival && reservation.id < upcoming->id))
                    upcoming = &reservation;
            }
            if (upcoming) line << " next " << upcoming->id
                               << ' ' << date_text(upcoming->arrival);
            say_indented(line.str());
        }
    }

    void cmd_list(const vector<string>& a) {
        vector<const Reservation*> entries;
        for (const auto& [id, reservation] : reservations)
            if (reservation.status == a[0]) entries.push_back(&reservation);
        sort(entries.begin(), entries.end(), [](const auto* x, const auto* y) {
            return tie(x->arrival, x->id) < tie(y->arrival, y->id);
        });
        say("LIST", a[0], entries.size());
        for (const Reservation* reservation : entries)
            say_indented(reservation->id, reservation->guest, "room",
                         reservation->room->number, date_text(reservation->arrival),
                         "->", date_text(reservation->departure));
    }

    void cmd_queue() {
        say("QUEUE", waitlist.size());
        for (size_t i = 0; i < waitlist.size(); ++i) {
            const WaitingEntry& entry = waitlist[i];
            say_indented(i + 1, entry.id, entry.guest, entry.kind,
                         date_text(entry.arrival), "->", date_text(entry.departure));
        }
    }

    void cmd_schedule(const vector<string>& a) {
        int day = date_number(a[0]);
        vector<const Reservation*> arrivals, departures;
        for (const auto& [id, r] : reservations) {
            if (r.arrival == day && r.status != "cancelled") arrivals.push_back(&r);
            if (r.departure == day &&
                (r.status == "booked" || r.status == "inhouse" || r.status == "checkedout"))
                departures.push_back(&r);
        }
        say("SCHEDULE", date_weekday(day), "arrivals", arrivals.size(),
            "departures", departures.size());
        for (const Reservation* r : arrivals)
            say_indented("arrival", r->id, r->guest, "room", r->room->number, r->status);
        for (const Reservation* r : departures)
            say_indented("departure", r->id, r->guest, "room", r->room->number, r->status);
    }

    void cmd_guest(const vector<string>& a) {
        bool found = false;
        for (const string& id : reservation_order)
            if (reservations.at(id).guest == a[0]) found = true;
        if (!found) throw runtime_error("unknown guest " + a[0]);
        say("GUEST", a[0]);
        for (const string& id : reservation_order) {
            const Reservation& r = reservations.at(id);
            if (r.guest != a[0]) continue;
            bool active = r.status == "booked" || r.status == "inhouse";
            say_indented(r.id, "room", r.room->number, r.room->kind,
                         date_text(r.arrival), "->", date_text(r.departure), r.status,
                         active ? "deposit" : "paid",
                         money(active ? r.deposit : r.paid));
        }
        Money paid = guest_total(a[0]);
        say_indented("total paid", money(paid), "points", paid / 100, "tier", tier(a[0]));
    }

    void cmd_revenue(const vector<string>& a) {
        auto [first, last] = period(a[0], a[1], false, false);
        Money lodging = 0, discount = 0, penalty = 0, extras = 0, tax = 0;
        Money cancellations = 0, noshows = 0;
        int checkouts = 0, cancel_count = 0, no_show_count = 0;
        for (const auto& [id, r] : reservations) {
            if (!r.posting || *r.posting < first || *r.posting > last) continue;
            if (r.status == "checkedout") {
                ++checkouts;
                const Bill& bill = *r.bill;
                lodging += bill.lodging;
                discount += bill.discount;
                penalty += bill.penalty;
                extras += bill.extras;
                tax += bill.tax;
            } else if (r.status == "cancelled") {
                cancellations += r.fee;
                ++cancel_count;
            } else if (r.status == "noshow") {
                noshows += r.fee;
                ++no_show_count;
            }
        }
        say("REVENUE", a[0], "->", a[1]);
        say_indented("lodging", money(lodging));
        say_indented("discount", money(discount));
        say_indented("penalty", money(penalty));
        say_indented("extras", money(extras));
        say_indented("tax", money(tax));
        say_indented("cancellation", money(cancellations));
        say_indented("noshow", money(noshows));
        say_indented("total", money(lodging - discount + penalty + extras + tax +
                                    cancellations + noshows));
        say_indented("checkouts", checkouts, "cancellations", cancel_count,
                     "noshows", no_show_count);
    }

public:
    void execute(const string& line) {
        istringstream input(line);
        vector<string> a;
        string command, word;
        input >> command;
        while (input >> word) a.push_back(word);
        try {
            if (command == "ROOM") cmd_room(a);
            else if (command == "RATE") cmd_rate(a);
            else if (command == "SEASON") cmd_season(a);
            else if (command == "BLOCK") cmd_block(a);
            else if (command == "UNBLOCK") cmd_unblock(a);
            else if (command == "CLEAN") cmd_clean(a);
            else if (command == "TODAY") cmd_today(a);
            else if (command == "BOOK") cmd_book(a);
            else if (command == "BOOKROOM") cmd_bookroom(a);
            else if (command == "WAITLIST") cmd_waitlist(a);
            else if (command == "MODIFY") cmd_modify(a);
            else if (command == "CANCEL") cmd_cancel(a);
            else if (command == "CHECKIN") cmd_checkin(a);
            else if (command == "MOVE") cmd_move(a);
            else if (command == "EXTEND") cmd_extend(a);
            else if (command == "CHARGE") cmd_charge(a);
            else if (command == "PAY") cmd_pay(a);
            else if (command == "CHECKOUT") cmd_checkout(a);
            else if (command == "INVOICE") cmd_invoice(a);
            else if (command == "AVAIL") cmd_avail(a);
            else if (command == "OCCUPANCY") cmd_occupancy(a);
            else if (command == "STATS") cmd_stats(a);
            else if (command == "ROOMS") cmd_rooms();
            else if (command == "LIST") cmd_list(a);
            else if (command == "QUEUE") cmd_queue();
            else if (command == "SCHEDULE") cmd_schedule(a);
            else if (command == "GUEST") cmd_guest(a);
            else if (command == "REVENUE") cmd_revenue(a);
        } catch (const runtime_error& error) {
            say("ERROR", error.what());
        }
        process_waitlist();
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
    HotelDesk desk;
    string line;
    for (int i = 0; i < count; ++i) {
        getline(cin, line);
        desk.execute(line);
    }
    desk.print();
}
