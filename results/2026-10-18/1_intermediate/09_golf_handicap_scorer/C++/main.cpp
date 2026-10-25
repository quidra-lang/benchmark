#include <algorithm>
#include <array>
#include <cstdlib>
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

int round_half_up(long long numerator, long long denominator) {
    return static_cast<int>((2 * numerator + denominator >= 0)
        ? (2 * numerator + denominator) / (2 * denominator)
        : -((-2 * numerator - denominator + 2 * denominator - 1) / (2 * denominator)));
}

int round_half_away(long long numerator, long long denominator) {
    return numerator < 0 ? -round_half_up(-numerator, denominator)
                         : round_half_up(numerator, denominator);
}

string decimal_display(int value, const string& negative_sign = "-") {
    string sign = value < 0 ? negative_sign : "";
    value = abs(value);
    return sign + to_string(value / 10) + "." + to_string(value % 10);
}

string index_display(optional<int> value) {
    return value ? decimal_display(*value, "+") : "none";
}

string handicap_display(optional<int> value) {
    if (!value) return "none";
    return *value < 0 ? "+" + to_string(-*value) : to_string(*value);
}

string average_display(long long total, int count) {
    if (count == 0) return "-";
    long long hundredths = total * 100 / count;
    return to_string(hundredths / 100) + "." +
           (hundredths % 100 < 10 ? "0" : "") + to_string(hundredths % 100);
}

template <typename Range>
long long sum(const Range& values) {
    return accumulate(values.begin(), values.end(), 0LL);
}

string join(const vector<string>& parts, const string& separator = " ") {
    string result;
    for (const string& part : parts) {
        if (!result.empty()) result += separator;
        result += part;
    }
    return result;
}

array<int, 18> allocate(int handicap, const array<int, 18>& stroke_indexes) {
    array<int, 18> strokes{};
    int quotient = abs(handicap) / 18;
    int remainder = abs(handicap) % 18;
    for (int hole = 0; hole < 18; ++hole) {
        strokes[hole] = handicap >= 0
            ? quotient + (stroke_indexes[hole] <= remainder)
            : -quotient - (stroke_indexes[hole] >= 19 - remainder);
    }
    return strokes;
}

array<long long, 5> countback(const vector<int>& values) {
    array<long long, 5> result{};
    for (int hole = 0; hole < 18; ++hole) {
        result[0] += values[hole];
        if (hole >= 9) result[1] += values[hole];
        if (hole >= 12) result[2] += values[hole];
        if (hole >= 15) result[3] += values[hole];
    }
    result[4] = values[17];
    return result;
}

vector<string> ranked(vector<string> identifiers, const map<string, vector<int>>& values,
                      bool larger = false) {
    sort(identifiers.begin(), identifiers.end(), [&](const string& a, const string& b) {
        auto left = countback(values.at(a));
        auto right = countback(values.at(b));
        return left != right ? (larger ? left > right : left < right) : a < b;
    });
    return identifiers;
}

string match_status(int lead) {
    return lead == 0 ? "AS" : to_string(abs(lead)) + (lead > 0 ? " UP" : " DN");
}

struct Course;
struct Tee {
    string id;
    int rating;
    int slope;
    int handicap(int index, const Course& course) const;
};

struct Course {
    string id;
    array<int, 18> pars;
    array<int, 18> stroke_indexes;
    int par;
    map<string, Tee> tees;
};

int Tee::handicap(int index, const Course& course) const {
    return round_half_up(1LL * index * slope + 113LL * (rating - 10 * course.par), 1130);
}

struct Calculation {
    int lowest;
    int average;
    int adjustment;
    optional<int> low;
    bool hard;
    bool soft;
    bool maximum;
};

struct Player;
struct Round {
    Course* course;
    Tee* tee;
    int day;
    array<int, 18> scores;
    optional<int> previous_index;
    size_t previous_records;
    optional<Calculation> previous_calculation;
    optional<int> handicap;
    array<int, 18> adjusted{};
    int ags = 0;
    int differential = 0;
    int exceptional = 0;

    Round(const Player& player, Course* course, Tee* tee, int day,
          const array<int, 18>& scores);
    vector<optional<int>> nets(const array<int, 18>& strokes) const;
    vector<int> points(const vector<optional<int>>& nets) const;
    bool complete() const;
};

struct Eligible {
    int number;
    const Round* record;
    int adjusted;
};

struct Player {
    string id;
    string name;
    optional<int> index;
    vector<Round> rounds;
    vector<pair<int, int>> records;
    optional<Calculation> calculation;

    optional<pair<int, int>> low_index(int day) const {
        optional<pair<int, int>> lowest;
        for (auto [date, value] : records) {
            if (day - 365 <= date && date < day) {
                pair<int, int> candidate{value, date};
                if (!lowest || candidate < *lowest) lowest = candidate;
            }
        }
        return lowest;
    }

    vector<Eligible> eligible() const {
        vector<Eligible> selected;
        int reduction = 0;
        int start = max(0, static_cast<int>(rounds.size()) - 20);
        for (int i = static_cast<int>(rounds.size()) - 1; i >= start; --i) {
            reduction += rounds[i].exceptional;
            selected.push_back({i + 1, &rounds[i], rounds[i].differential - reduction});
        }
        reverse(selected.begin(), selected.end());
        return selected;
    }

    pair<vector<Eligible>, int> counting(vector<Eligible> selected) const {
        int n = static_cast<int>(selected.size());
        if (n < 3) return {{}, 0};
        const array<int, 8> limits{5, 8, 11, 14, 16, 18, 19, 20};
        int k = 1;
        while (n > limits[k - 1]) ++k;
        sort(selected.begin(), selected.end(), [](const Eligible& a, const Eligible& b) {
            return a.adjusted != b.adjusted ? a.adjusted < b.adjusted
                                            : a.number > b.number;
        });
        selected.resize(k);
        int adjustment = n == 3 ? -20 : (n == 4 || n == 6 ? -10 : 0);
        return {selected, adjustment};
    }

    void update_index(int day) {
        auto [selected, adjustment] = counting(eligible());
        if (selected.empty()) {
            calculation.reset();
            return;
        }
        long long total = 0;
        for (const Eligible& entry : selected) total += entry.adjusted;
        int average = round_half_away(total, selected.size());
        int candidate = average + adjustment;
        auto low_record = low_index(day);
        optional<int> low = low_record ? optional<int>(low_record->first) : nullopt;
        bool soft = false, hard = false, maximum = false;
        if (low) {
            if (candidate - *low > 30) {
                candidate = *low + 30 + (candidate - *low - 30) / 2;
                soft = true;
            }
            if (candidate - *low > 50) {
                candidate = *low + 50;
                hard = true;
            }
        }
        if (candidate > 540) {
            candidate = 540;
            maximum = true;
        }
        index = candidate;
        calculation = Calculation{static_cast<int>(selected.size()), average, adjustment,
                                  low, hard, soft, maximum};
    }
};

Round::Round(const Player& player, Course* c, Tee* t, int d,
             const array<int, 18>& raw)
    : course(c), tee(t), day(d), scores(raw), previous_index(player.index),
      previous_records(player.records.size()),
      previous_calculation(player.calculation),
      handicap(player.index ? optional<int>(t->handicap(*player.index, *c)) : nullopt) {
    auto strokes = allocate(handicap.value_or(0), c->stroke_indexes);
    for (int hole = 0; hole < 18; ++hole) {
        int limit = handicap ? c->pars[hole] + 2 + strokes[hole] : c->pars[hole] + 5;
        adjusted[hole] = raw[hole] == -1 ? c->pars[hole] + strokes[hole]
                         : raw[hole] == 0 ? limit : min(raw[hole], limit);
        ags += adjusted[hole];
    }
    differential = round_half_away(113LL * (10 * ags - t->rating), t->slope);
    if (player.index && *player.index - differential >= 70) {
        exceptional = *player.index - differential >= 100 ? 20 : 10;
    }
}

vector<optional<int>> Round::nets(const array<int, 18>& strokes) const {
    vector<optional<int>> result;
    for (int i = 0; i < 18; ++i)
        result.push_back(scores[i] > 0 ? optional<int>(scores[i] - strokes[i]) : nullopt);
    return result;
}

vector<int> Round::points(const vector<optional<int>>& nets) const {
    vector<int> result;
    for (int i = 0; i < 18; ++i)
        result.push_back(nets[i] ? max(0, course->pars[i] + 2 - *nets[i]) : 0);
    return result;
}

bool Round::complete() const {
    return all_of(scores.begin(), scores.end(), [](int score) { return score > 0; });
}

struct Event {
    string id;
    string format;
    Course* course;
    Tee* tee;
    int day;
    int allowance;
    vector<Player*> players;
};

struct EventData {
    map<string, const Round*> rounds;
    map<string, int> handicaps;
    map<string, vector<optional<int>>> nets;
    map<string, vector<int>> points;
};

class GolfScorer {
    map<string, Course> courses;
    map<string, Player> players;
    map<string, Event> events;
    vector<string> output;

    template <typename... Parts>
    void emit(const Parts&... parts) {
        ostringstream out;
        bool first = true;
        ((out << (exchange(first, false) ? "" : " ") << parts), ...);
        output.push_back(out.str());
    }

    Player& player(const string& id) {
        auto found = players.find(id);
        if (found == players.end()) throw runtime_error("unknown player");
        return found->second;
    }

    Course& course(const string& id) {
        auto found = courses.find(id);
        if (found == courses.end()) throw runtime_error("unknown course");
        return found->second;
    }

    pair<Course*, Tee*> tee(const string& course_id, const string& tee_id) {
        Course& c = course(course_id);
        auto found = c.tees.find(tee_id);
        if (found == c.tees.end()) throw runtime_error("unknown tee");
        return {&c, &found->second};
    }

    void register_course(const vector<string>& a) {
        const string& id = a[0];
        if (courses.count(id)) throw runtime_error("duplicate course");
        array<int, 18> pars{}, indexes{};
        for (int i = 0; i < 18; ++i) {
            pars[i] = stoi(a[i + 1]);
            indexes[i] = stoi(a[i + 19]);
        }
        bool valid = all_of(pars.begin(), pars.end(),
                            [](int par) { return par >= 3 && par <= 5; });
        auto ordered = indexes;
        sort(ordered.begin(), ordered.end());
        for (int i = 0; i < 18; ++i) valid &= ordered[i] == i + 1;
        if (!valid) throw runtime_error("invalid course");
        courses.emplace(id, Course{id, pars, indexes, static_cast<int>(sum(pars)), {}});
    }

    void register_tee(const vector<string>& a) {
        Course& c = course(a[0]);
        if (c.tees.count(a[1])) throw runtime_error("duplicate tee");
        int rating = stoi(a[2]), slope = stoi(a[3]);
        if (rating < 500 || rating > 900 || slope < 55 || slope > 155)
            throw runtime_error("invalid tee");
        c.tees.emplace(a[1], Tee{a[1], rating, slope});
    }

    void register_player(const vector<string>& a) {
        if (players.count(a[0])) throw runtime_error("duplicate player");
        optional<int> index = a.size() == 3 ? optional<int>(stoi(a[2])) : nullopt;
        if (index && (*index < -100 || *index > 540)) throw runtime_error("invalid index");
        players.emplace(a[0], Player{a[0], a[1], index, {}, {}, nullopt});
    }

    void add_round(const vector<string>& a) {
        Player& p = player(a[0]);
        auto [c, t] = tee(a[1], a[2]);
        int day = stoi(a[3]);
        if (!p.rounds.empty() && day < p.rounds.back().day)
            throw runtime_error("invalid day");
        array<int, 18> scores{};
        int unplayed = 0;
        for (int i = 0; i < 18; ++i) {
            scores[i] = a[i + 4] == "X" ? 0 : (a[i + 4] == "-" ? -1 : stoi(a[i + 4]));
            unplayed += scores[i] == -1;
        }
        if (unplayed >= 5) throw runtime_error("too few holes");
        p.rounds.emplace_back(p, c, t, day, scores);
        const Round& record = p.rounds.back();
        p.update_index(day);
        if (p.index) p.records.push_back({day, *p.index});
        vector<string> parts{"round", p.id, to_string(p.rounds.size()) + ":", "ags",
                             to_string(record.ags), "diff", decimal_display(record.differential)};
        if (record.exceptional) {
            parts.push_back("exceptional");
            parts.push_back(decimal_display(-record.exceptional));
        }
        parts.push_back("index");
        parts.push_back(index_display(p.index));
        emit(join(parts));
    }

    void remove(const vector<string>& a) {
        Player& p = player(a[0]);
        if (p.rounds.empty()) throw runtime_error("no rounds");
        size_t number = p.rounds.size();
        Round record = p.rounds.back();
        p.rounds.pop_back();
        p.index = record.previous_index;
        p.records.resize(record.previous_records);
        p.calculation = record.previous_calculation;
        emit("removed", p.id, to_string(number) + ":", "index", index_display(p.index));
    }

    void show_index(const vector<string>& a) {
        Player& p = player(a[0]);
        vector<string> parts{"index", p.id + ":", index_display(p.index), "rounds",
                             to_string(p.rounds.size())};
        if (p.calculation) {
            const Calculation& calc = *p.calculation;
            parts.insert(parts.end(), {"lowest", to_string(calc.lowest),
                                       "average", decimal_display(calc.average),
                                       "adjustment", decimal_display(calc.adjustment)});
            if (calc.low) {
                parts.push_back("low");
                parts.push_back(index_display(calc.low));
            }
            if (calc.hard) parts.insert(parts.end(), {"hard", "cap"});
            else if (calc.soft) parts.insert(parts.end(), {"soft", "cap"});
            if (calc.maximum) parts.push_back("maximum");
        }
        emit(join(parts));
    }

    void history(const vector<string>& a) {
        Player& p = player(a[0]);
        auto eligible = p.eligible();
        auto [selected, ignored_adjustment] = p.counting(eligible);
        set<int> counted;
        for (const Eligible& entry : selected) counted.insert(entry.number);
        emit("history", p.id + ":", "rounds", p.rounds.size());
        for (const Eligible& entry : eligible) {
            const Round& r = *entry.record;
            vector<string> parts{to_string(entry.number), "day", to_string(r.day),
                                 r.course->id, r.tee->id, "ags", to_string(r.ags),
                                 "diff", decimal_display(r.differential)};
            if (entry.adjusted != r.differential)
                parts.insert(parts.end(), {"adjusted", decimal_display(entry.adjusted)});
            if (counted.count(entry.number)) parts.push_back("*");
            emit(join(parts));
        }
    }

    void lowindex(const vector<string>& a) {
        Player& p = player(a[0]);
        int day = stoi(a[1]);
        auto low = p.low_index(day);
        if (!low) emit("lowindex", p.id, a[1] + ":", "none");
        else emit("lowindex", p.id, a[1] + ":", index_display(low->first),
                  "day", low->second);
    }

    void coursehcp(const vector<string>& a) {
        Player& p = player(a[0]);
        auto [c, t] = tee(a[1], a[2]);
        if (!p.index) throw runtime_error("no index");
        int handicap = t->handicap(*p.index, *c);
        vector<string> parts{"coursehcp", p.id, c->id, t->id + ":",
                             handicap_display(handicap), "strokes"};
        for (int stroke : allocate(handicap, c->stroke_indexes))
            parts.push_back(to_string(stroke));
        emit(join(parts));
    }

    void hcptable(const vector<string>& a) {
        auto [c, t] = tee(a[0], a[1]);
        int first = stoi(a[2]), last = stoi(a[3]);
        if (first < -100 || last > 540 || first > last)
            throw runtime_error("invalid index");
        emit("hcptable", c->id, t->id + ":", index_display(first), "to",
             index_display(last));
        int start = first, handicap = t->handicap(first, *c);
        for (int i = first + 1; i <= last; ++i) {
            int next = t->handicap(i, *c);
            if (next != handicap) {
                emit(index_display(start), "to", index_display(i - 1) + ":",
                     handicap_display(handicap));
                start = i;
                handicap = next;
            }
        }
        emit(index_display(start), "to", index_display(last) + ":",
             handicap_display(handicap));
    }

    void card_total(const string& label, const Round& r,
                    const array<int, 18>& strokes, const vector<optional<int>>& nets,
                    const vector<int>& points, int first, int last) {
        int pars = 0, scores = 0, adjusted = 0, allocated = 0, net = 0, pts = 0;
        bool complete = true;
        for (int i = first; i < last; ++i) {
            pars += r.course->pars[i];
            complete &= r.scores[i] > 0;
            if (r.scores[i] > 0) scores += r.scores[i];
            adjusted += r.adjusted[i];
            allocated += strokes[i];
            if (nets[i]) net += *nets[i];
            pts += points[i];
        }
        emit(label, pars, complete ? to_string(scores) : "-", adjusted, allocated,
             complete ? to_string(net) : "-", pts);
    }

    void card(const vector<string>& a) {
        Player& p = player(a[0]);
        int number = stoi(a[1]);
        if (number > static_cast<int>(p.rounds.size()))
            throw runtime_error("unknown round");
        const Round& r = p.rounds[number - 1];
        auto strokes = allocate(r.handicap.value_or(0), r.course->stroke_indexes);
        auto nets = r.nets(strokes);
        auto points = r.points(nets);
        emit("card", p.id, a[1] + ":", r.course->id, r.tee->id,
             "day", r.day, "handicap", handicap_display(r.handicap));
        for (int i = 0; i < 18; ++i) {
            string score = r.scores[i] == 0 ? "X" : r.scores[i] == -1 ? "-"
                                                                    : to_string(r.scores[i]);
            emit(i + 1, r.course->pars[i], r.course->stroke_indexes[i], score,
                 r.adjusted[i], strokes[i], nets[i] ? to_string(*nets[i]) : "-", points[i]);
            if (i == 8) card_total("OUT", r, strokes, nets, points, 0, 9);
            if (i == 17) {
                card_total("IN", r, strokes, nets, points, 9, 18);
                card_total("TOTAL", r, strokes, nets, points, 0, 18);
            }
        }
        emit("ags", r.ags, "diff", decimal_display(r.differential));
    }

    void stats(const vector<string>& a) {
        Player& p = player(a[0]);
        const array<string, 7> labels{"eagles", "birdies", "pars", "bogeys",
                                      "doubles", "others", "pickups"};
        array<int, 7> counts{};
        array<int, 6> par_total{}, par_count{};
        int best = 0;
        long long complete_total = 0;
        int complete_count = 0;
        for (const Round& r : p.rounds) {
            if (r.complete()) {
                int total = static_cast<int>(sum(r.scores));
                if (complete_count == 0 || total < best) best = total;
                complete_total += total;
                ++complete_count;
            }
            for (int i = 0; i < 18; ++i) {
                int score = r.scores[i], par = r.course->pars[i];
                if (score == 0) ++counts[6];
                else if (score > 0) {
                    int category = max(0, min(score - par + 2, 5));
                    ++counts[category];
                    par_total[par] += score;
                    ++par_count[par];
                }
            }
        }
        vector<string> parts{"stats", p.id + ":", "rounds", to_string(p.rounds.size()),
                             "best", complete_count ? to_string(best) : "-",
                             "average", average_display(complete_total, complete_count)};
        for (int i = 0; i < 7; ++i) {
            parts.push_back(labels[i]);
            parts.push_back(to_string(counts[i]));
        }
        for (int par = 3; par <= 5; ++par) {
            parts.push_back("par" + to_string(par));
            parts.push_back(average_display(par_total[par], par_count[par]));
        }
        emit(join(parts));
    }

    void holestats(const vector<string>& a) {
        Course& c = course(a[0]);
        array<int, 18> scores{}, totals{}, rank{};
        int rounds = 0;
        for (const auto& [id, p] : players)
            for (const Round& r : p.rounds)
                if (r.course == &c) {
                    ++rounds;
                    for (int i = 0; i < 18; ++i)
                        if (r.scores[i] > 0) {
                            ++scores[i];
                            totals[i] += r.scores[i];
                        }
                }
        vector<int> holes(18);
        iota(holes.begin(), holes.end(), 0);
        sort(holes.begin(), holes.end(), [&](int left, int right) {
            if (!scores[left]) return !scores[right] && left < right;
            if (!scores[right]) return true;
            long long a = 1LL * (totals[left] - c.pars[left] * scores[left]) * scores[right];
            long long b = 1LL * (totals[right] - c.pars[right] * scores[right]) * scores[left];
            return a != b ? a > b : left < right;
        });
        for (int i = 0; i < 18; ++i) rank[holes[i]] = i + 1;
        emit("holestats", c.id + ":", "rounds", rounds);
        for (int i = 0; i < 18; ++i)
            emit(i + 1, "par", c.pars[i], "si", c.stroke_indexes[i], "scores", scores[i],
                 "avg", average_display(totals[i], scores[i]), "rank", rank[i]);
    }

    void show_players(const vector<string>&) {
        vector<const Player*> order;
        for (const auto& [id, p] : players) order.push_back(&p);
        sort(order.begin(), order.end(), [](const Player* a, const Player* b) {
            if (a->index.has_value() != b->index.has_value()) return a->index.has_value();
            if (a->index && a->index != b->index) return *a->index < *b->index;
            return a->id < b->id;
        });
        emit("players", order.size());
        for (const Player* p : order)
            emit(p->id, p->name, index_display(p->index), "rounds", p->rounds.size());
    }

    void register_event(const vector<string>& a) {
        if (events.count(a[0])) throw runtime_error("duplicate event");
        auto [c, t] = tee(a[2], a[3]);
        int allowance = stoi(a[5]);
        if (allowance < 1 || allowance > 100) throw runtime_error("invalid allowance");
        vector<Player*> participants;
        set<string> unique;
        for (size_t i = 6; i < a.size(); ++i) {
            participants.push_back(&player(a[i]));
            unique.insert(a[i]);
        }
        int count = static_cast<int>(participants.size());
        bool valid = a[1] == "MATCH" || a[1] == "NASSAU" ? count == 2
                     : a[1] == "FOURBALL" ? count == 4
                     : a[1] == "BETTERBALL" ? (count == 4 || count == 6 || count == 8)
                     : count >= 2 && count <= 8;
        if (!valid || unique.size() != participants.size())
            throw runtime_error("invalid players");
        events.emplace(a[0], Event{a[0], a[1], c, t, stoi(a[4]), allowance,
                                  move(participants)});
    }

    EventData event_data(const Event& event) const {
        EventData data;
        for (const Player* p : event.players) {
            const Round* found = nullptr;
            for (const Round& r : p->rounds) {
                if (r.course == event.course && r.tee == event.tee && r.day == event.day) {
                    found = &r;
                    break;
                }
            }
            if (!found) throw runtime_error("missing round");
            if (!found->handicap) throw runtime_error("no index");
            data.rounds[p->id] = found;
            data.handicaps[p->id] = round_half_up(1LL * *found->handicap * event.allowance, 100);
        }
        int minimum = 0;
        if (event.format == "MATCH" || event.format == "NASSAU" || event.format == "FOURBALL") {
            minimum = min_element(data.handicaps.begin(), data.handicaps.end(),
                [](const auto& a, const auto& b) { return a.second < b.second; })->second;
        }
        for (const Player* p : event.players) {
            auto strokes = allocate(data.handicaps.at(p->id) - minimum,
                                    event.course->stroke_indexes);
            data.nets[p->id] = data.rounds.at(p->id)->nets(strokes);
            data.points[p->id] = data.rounds.at(p->id)->points(data.nets.at(p->id));
        }
        return data;
    }

    pair<vector<string>, map<string, vector<int>>> event_ranking(
        const Event& event, const EventData& data) const {
        vector<string> ids;
        map<string, vector<int>> values;
        for (const Player* p : event.players) {
            if (event.format == "STROKE" && !data.rounds.at(p->id)->complete()) continue;
            ids.push_back(p->id);
            if (event.format == "STABLEFORD") values[p->id] = data.points.at(p->id);
            else if (event.format == "STROKE") {
                vector<int> v;
                for (const auto& net : data.nets.at(p->id)) v.push_back(*net);
                values[p->id] = move(v);
            } else {
                vector<int> v;
                for (int h = 0; h < 18; ++h) {
                    const auto& net = data.nets.at(p->id)[h];
                    v.push_back(!net || *net > event.course->pars[h] ? -1
                                : *net < event.course->pars[h] ? 1 : 0);
                }
                values[p->id] = move(v);
            }
        }
        return {ranked(ids, values, event.format != "STROKE"), values};
    }

    void individual_results(const Event& event, const EventData& data) {
        auto [order, values] = event_ranking(event, data);
        int position = 1;
        for (const string& id : order) {
            string handicap = handicap_display(data.handicaps.at(id));
            if (event.format == "STROKE")
                emit(position, id, "net", sum(values.at(id)), "gross",
                     sum(data.rounds.at(id)->scores), "hcp", handicap);
            else if (event.format == "STABLEFORD")
                emit(position, id, "points", sum(data.points.at(id)), "hcp", handicap);
            else
                emit(position, id, match_status(static_cast<int>(sum(values.at(id)))),
                     "hcp", handicap);
            ++position;
        }
        if (event.format == "STROKE") {
            vector<string> nr;
            for (const Player* p : event.players)
                if (!data.rounds.at(p->id)->complete()) nr.push_back(p->id);
            sort(nr.begin(), nr.end());
            for (const string& id : nr)
                emit("NR", id, "hcp", handicap_display(data.handicaps.at(id)));
            if (!order.empty()) {
                map<string, vector<int>> gross;
                for (const string& id : order) {
                    auto& scores = data.rounds.at(id)->scores;
                    gross[id] = vector<int>(scores.begin(), scores.end());
                }
                string winner = ranked(order, gross).front();
                emit("gross", winner, sum(gross.at(winner)));
            }
        }
    }

    pair<array<string, 2>, vector<int>> match_holes(const Event& event,
                                                     const EventData& data) const {
        vector<string> ids;
        for (const Player* p : event.players) ids.push_back(p->id);
        vector<string> first{ids[0]}, second{ids[event.format == "FOURBALL" ? 2 : 1]};
        if (event.format == "FOURBALL") {
            first.push_back(ids[1]);
            second.push_back(ids[3]);
        }
        array<string, 2> names{join(first, "+"), join(second, "+")};
        vector<int> holes;
        for (int h = 0; h < 18; ++h) {
            auto best = [&](const vector<string>& side) -> optional<int> {
                optional<int> minimum;
                for (const string& id : side) {
                    auto net = data.nets.at(id)[h];
                    if (net && (!minimum || *net < *minimum)) minimum = *net;
                }
                return minimum;
            };
            auto left = best(first), right = best(second);
            int winner = !left ? (!right ? 0 : -1)
                         : !right || *left < *right ? 1
                         : *left > *right ? -1 : 0;
            holes.push_back(winner);
        }
        return {names, holes};
    }

    pair<vector<string>, string> play_match(const array<string, 2>& names,
                                           const vector<int>& holes,
                                           int first, int last) const {
        int lead = 0, remaining = 0;
        vector<string> statuses;
        for (int h = first; h < last; ++h) {
            lead += holes[h];
            statuses.push_back(match_status(lead));
            remaining = last - h - 1;
            if (abs(lead) > remaining || remaining == 0) break;
        }
        if (lead == 0) return {statuses, "AS"};
        string margin = remaining ? to_string(abs(lead)) + "&" + to_string(remaining)
                                  : to_string(abs(lead)) + " UP";
        return {statuses, names[lead > 0 ? 0 : 1] + " " + margin};
    }

    void match_results(const Event& event, const EventData& data) {
        int minimum = min_element(data.handicaps.begin(), data.handicaps.end(),
            [](const auto& a, const auto& b) { return a.second < b.second; })->second;
        vector<string> parts{"strokes"};
        for (const Player* p : event.players) {
            parts.push_back(p->id);
            parts.push_back(to_string(data.handicaps.at(p->id) - minimum));
        }
        emit(join(parts));
        auto [names, holes] = match_holes(event, data);
        if (event.format == "NASSAU") {
            for (auto [label, first, last] :
                 vector<tuple<string, int, int>>{{"front", 0, 9},
                                                 {"back", 9, 18}, {"total", 0, 18}}) {
                emit(label, play_match(names, holes, first, last).second);
            }
        } else {
            auto [statuses, result] = play_match(names, holes, 0, 18);
            emit("status", join(statuses, ", "));
            emit("result", result);
        }
    }

    void betterball_results(const Event& event, const EventData& data) {
        map<string, pair<string, string>> teams;
        map<string, vector<int>> values;
        vector<string> ids;
        for (size_t i = 0; i < event.players.size(); i += 2) {
            string first = event.players[i]->id, second = event.players[i + 1]->id;
            ids.push_back(first);
            teams[first] = {first, second};
            vector<int> points;
            for (int h = 0; h < 18; ++h)
                points.push_back(max(data.points.at(first)[h], data.points.at(second)[h]));
            values[first] = move(points);
        }
        auto order = ranked(ids, values, true);
        for (size_t i = 0; i < order.size(); ++i) {
            auto [first, second] = teams.at(order[i]);
            emit(i + 1, first + "+" + second, "points", sum(values.at(first)), "hcp",
                 handicap_display(data.handicaps.at(first)),
                 handicap_display(data.handicaps.at(second)));
        }
    }

    void skins_results(const Event& event, const EventData& data) {
        vector<string> ids;
        map<string, int> totals;
        for (const Player* p : event.players) {
            ids.push_back(p->id);
            totals[p->id] = 0;
        }
        int carry = 0;
        vector<string> last_minimum;
        for (int hole = 0; hole < 18; ++hole) {
            ++carry;
            optional<int> best;
            vector<string> winners;
            for (const string& id : ids) {
                auto net = data.nets.at(id)[hole];
                if (!net) continue;
                if (!best || *net < *best) {
                    best = net;
                    winners = {id};
                } else if (*net == *best) {
                    winners.push_back(id);
                }
            }
            last_minimum = winners;
            if (winners.size() == 1) {
                emit("hole", hole + 1, winners.front(), carry);
                totals[winners.front()] += 100 * carry;
                carry = 0;
            }
        }
        if (carry) {
            auto sharing = last_minimum.empty() ? ids : last_minimum;
            sort(sharing.begin(), sharing.end());
            int share = carry * 100 / sharing.size();
            for (const string& id : sharing) totals[id] += share;
            vector<string> parts{"carry", to_string(carry)};
            parts.insert(parts.end(), sharing.begin(), sharing.end());
            emit(join(parts));
        }
        sort(ids.begin(), ids.end(), [&](const string& a, const string& b) {
            return totals[a] == totals[b] ? a < b : totals[a] > totals[b];
        });
        for (const string& id : ids) {
            int value = totals[id];
            emit(id, to_string(value / 100) + "." +
                 (value % 100 < 10 ? "0" : "") + to_string(value % 100));
        }
    }

    void results(const vector<string>& a) {
        auto found = events.find(a[0]);
        if (found == events.end()) throw runtime_error("unknown event");
        const Event& event = found->second;
        auto data = event_data(event);
        emit("results", event.id + ":", event.format, event.course->id, event.tee->id,
             "day", event.day, "allowance", event.allowance);
        if (event.format == "STROKE" || event.format == "STABLEFORD" ||
            event.format == "PAR") {
            individual_results(event, data);
        } else if (event.format == "BETTERBALL") {
            betterball_results(event, data);
        } else if (event.format == "SKINS") {
            skins_results(event, data);
        } else {
            match_results(event, data);
        }
    }

    void merit(const vector<string>&) {
        map<string, array<int, 3>> tally;
        const array<int, 8> awards{10, 8, 6, 5, 4, 3, 2, 1};
        int counted = 0;
        for (const auto& [id, event] : events) {
            if (event.format != "STROKE" && event.format != "STABLEFORD" &&
                event.format != "PAR") continue;
            EventData data;
            try { data = event_data(event); }
            catch (const runtime_error&) { continue; }
            ++counted;
            auto order = event_ranking(event, data).first;
            for (const Player* p : event.players) ++tally[p->id][2];
            for (size_t i = 0; i < order.size(); ++i) {
                tally[order[i]][0] += awards[i];
                if (i == 0) ++tally[order[i]][1];
            }
        }
        emit("merit:", "events", counted);
        vector<string> ids;
        for (const auto& [id, values] : tally) ids.push_back(id);
        sort(ids.begin(), ids.end(), [&](const string& a, const string& b) {
            if (tally[a][0] != tally[b][0]) return tally[a][0] > tally[b][0];
            if (tally[a][1] != tally[b][1]) return tally[a][1] > tally[b][1];
            return a < b;
        });
        for (size_t i = 0; i < ids.size(); ++i) {
            const auto& row = tally.at(ids[i]);
            emit(i + 1, ids[i], row[0], "wins", row[1], "played", row[2]);
        }
    }

public:
    void execute(const string& line) {
        istringstream in(line);
        string command, part;
        in >> command;
        vector<string> arguments;
        while (in >> part) arguments.push_back(part);
        try {
            if (command == "COURSE") register_course(arguments);
            else if (command == "TEE") register_tee(arguments);
            else if (command == "PLAYER") register_player(arguments);
            else if (command == "ROUND") add_round(arguments);
            else if (command == "REMOVE") remove(arguments);
            else if (command == "INDEX") show_index(arguments);
            else if (command == "HISTORY") history(arguments);
            else if (command == "LOWINDEX") lowindex(arguments);
            else if (command == "COURSEHCP") coursehcp(arguments);
            else if (command == "HCPTABLE") hcptable(arguments);
            else if (command == "CARD") card(arguments);
            else if (command == "STATS") stats(arguments);
            else if (command == "HOLESTATS") holestats(arguments);
            else if (command == "PLAYERS") show_players(arguments);
            else if (command == "EVENT") register_event(arguments);
            else if (command == "RESULTS") results(arguments);
            else if (command == "MERIT") merit(arguments);
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
    string line;
    getline(cin, line);
    GolfScorer scorer;
    for (int i = 0; i < count; ++i) {
        getline(cin, line);
        scorer.execute(line);
    }
    scorer.print();
}
