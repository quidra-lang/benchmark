#include "airspace.hpp"

constexpr double pi = 3.141592653589793;
static const std::array<std::string, 3> geometry_names = {"head_on", "crossing", "trailing"};
static const std::array<std::string, 3> severity_names = {"HIGH", "MEDIUM", "LOW"};
struct Trial {
    int flight;
    std::string name, status;
    std::optional<Conflict> blocker;
};
struct Round {
    Conflict target;
    std::vector<Trial> trials;
    std::optional<Trial> accepted;
};
struct Transit {
    int flight, sector;
    double entry, exit;
    int previous = -1, next = -1;
};
struct Period {
    int sector;
    std::size_t number;
    Integer start, end;
    std::array<int, 2> entries{}, peak{};
    double mean;
    std::string status;
};
struct Alert {
    Pair pair;
    Integer first, last;
    int samples;
    double predicted, distance;
    std::optional<double> lead;
};
using Occupancy = std::vector<std::vector<int>>;
static bool active(const Conflict &conflict, double time) {
    return conflict.start <= time && time < conflict.end;
}
static double track(const Segment &segment) {
    double angle = std::atan2(segment.velocity[0], segment.velocity[1]) * 180 / pi;
    return angle < 0 ? angle + 360 : angle;
}
static bool contains(const Sector &sector, const Point &point) {
    return double(sector.x1) / 10 <= point[0] && point[0] < double(sector.x2) / 10 &&
           double(sector.y1) / 10 <= point[1] && point[1] < double(sector.y2) / 10 &&
           double(sector.lower) * 100 <= point[2] && point[2] < double(sector.upper) * 100;
}
static std::optional<std::pair<double, double>> inside(const Segment &segment,
                                                       const Sector &sector) {
    Point low = {double(sector.x1) / 10, double(sector.y1) / 10, double(sector.lower) * 100};
    Point high = {double(sector.x2) / 10, double(sector.y2) / 10, double(sector.upper) * 100};
    double first = segment.start_time, last = segment.end_time;
    for (int axis = 0; axis < 3; ++axis) {
        double p = segment.start[axis], v = segment.velocity[axis];
        if (v == 0) {
            if (!(low[axis] <= p && p < high[axis]))
                return {};
        } else {
            double r1 = (low[axis] - p) / v, r2 = (high[axis] - p) / v;
            first = std::max(first, segment.start_time + std::min(r1, r2));
            last = std::min(last, segment.start_time + std::max(r1, r2));
        }
    }
    if (last - first > 1e-6)
        return std::make_pair(first, last);
    return {};
}
class Traffic {
    Input input;
    std::array<std::vector<Plan>, 2> plans;
    std::array<std::vector<Trajectory>, 2> trajectories;
    std::array<std::vector<Conflict>, 2> conflicts;
    std::set<Pair> unresolved, resolved, final_pairs;
    std::vector<Round> rounds;
    std::vector<Conflict> unresolved_conflicts;
    std::array<std::vector<Transit>, 2> transits;
    std::array<Occupancy, 2> occupancy;
    std::vector<Period> periods;
    std::vector<Integer> samples;

    std::string callsign(int flight) const { return input.plans[flight].callsign; }
    std::string pair_name(Pair pair) const {
        return callsign(pair.first) + "-" + callsign(pair.second);
    }
    std::string sector_name(int sector) const {
        return sector < 0 ? "-" : input.sectors[sector].name;
    }
    std::string history(int flight) const {
        return plans[1][flight].history.empty() ? "-" : joined(plans[1][flight].history);
    }
    std::optional<Conflict> blocker(int changed, const Trajectory &candidate, int partner,
                                    double start) const {
        std::optional<Conflict> out;
        for (int other = 0; other < int(plans[1].size()); ++other) {
            if (other == changed)
                continue;
            Pair pair = std::minmax(changed, other);
            if (unresolved.count(pair))
                continue;
            const Trajectory &first =
                pair.first == changed ? candidate : trajectories[1][pair.first];
            const Trajectory &second =
                pair.second == changed ? candidate : trajectories[1][pair.second];
            for (const Conflict &item :
                 pair_conflicts(pair.first, first, pair.second, second, input.params))
                if ((other == partner || item.start < start + double(input.params.lookahead)) &&
                    (!out || conflict_before(item, *out)))
                    out = item;
        }
        return out;
    }
    void resolve() {
        const auto choices = manoeuvres(input.params.max_delay);
        for (;;) {
            auto current = all_conflicts(trajectories[1], input.params);
            auto target = std::find_if(current.begin(), current.end(), [&](const Conflict &item) {
                return !unresolved.count(item.pair);
            });
            if (target == current.end())
                break;
            Round record{*target, {}, {}};
            auto priority = priority_order(target->pair.first, target->pair.second, plans[1]);
            for (int index = 0; index < 2 && !record.accepted; ++index) {
                int flight = priority[index], partner = priority[1 - index];
                for (const Manoeuvre &choice : choices) {
                    Trial trial{flight, choice.name, "infeasible", {}};
                    auto proposal = propose(plans[1][flight], choice, input.types, input.params);
                    if (proposal) {
                        Trajectory candidate = build_trajectory(*proposal, input.types);
                        trial.blocker = blocker(flight, candidate, partner, target->start);
                        if (trial.blocker)
                            trial.status = "blocked";
                        else {
                            trial.status = "accepted";
                            proposal->history.push_back(choice.name);
                            plans[1][flight] = std::move(*proposal);
                            trajectories[1][flight] = std::move(candidate);
                            record.accepted = trial;
                        }
                    }
                    record.trials.push_back(trial);
                    if (record.accepted)
                        break;
                }
            }
            if (record.accepted)
                resolved.insert(target->pair);
            else {
                unresolved.insert(target->pair);
                unresolved_conflicts.push_back(*target);
            }
            rounds.push_back(std::move(record));
        }
    }
    void classify(int state) {
        for (Conflict &item : conflicts[state]) {
            const Piece &piece = item.closest;
            const Segment &a = trajectories[state][item.pair.first].segments[piece.first_segment];
            const Segment &b = trajectories[state][item.pair.second].segments[piece.second_segment];
            Point pa = position(a, piece.loss.time), pb = position(b, piece.loss.time), middle;
            item.first_level = pa[2] / 100;
            item.second_level = pb[2] / 100;
            item.first_track = track(a);
            item.second_track = track(b);
            double gap = std::abs(item.first_track - item.second_track);
            item.angle = gap > 180 ? 360 - gap : gap;
            double dot = a.velocity[0] * b.velocity[0] + a.velocity[1] * b.velocity[1];
            double cross = a.velocity[0] * b.velocity[1] - a.velocity[1] * b.velocity[0];
            item.geometry = dot * dot > cross * cross ? (dot < 0 ? 0 : 2) : 1;
            item.severity = 10 * piece.loss.distance < 4 * double(input.params.horizontal)   ? 0
                            : 10 * piece.loss.distance < 7 * double(input.params.horizontal) ? 1
                                                                                             : 2;
            for (int axis = 0; axis < 3; ++axis)
                middle[axis] = (pa[axis] + pb[axis]) / 2;
            item.sector = -1;
            for (int sector = 0; sector < int(input.sectors.size()); ++sector)
                if (contains(input.sectors[sector], middle)) {
                    item.sector = sector;
                    break;
                }
            item.outcome = state == 1 || final_pairs.count(item.pair) ? "remaining"
                           : resolved.count(item.pair)                ? "resolved"
                                                                      : "indirect";
        }
    }
    Lines trajectory_report() const {
        Lines out{
            "callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end"};
        for (int flight = 0; flight < int(plans[1].size()); ++flight)
            for (const Segment &segment : trajectories[1][flight].segments)
                line(out, callsign(flight), ",", segment.number, ",", segment.leg, ",",
                     phase_name(segment.phase), ",", decimal(segment.start_time), ",",
                     decimal(segment.end_time), ",", decimal(segment.start[0]), ",",
                     decimal(segment.start[1]), ",", Integer(segment.start[2] / 100), ",",
                     decimal(segment.end[0]), ",", decimal(segment.end[1]), ",",
                     Integer(segment.end[2] / 100));
        return out;
    }
    std::vector<std::vector<int>> involvement(int state) const {
        std::vector<std::vector<int>> out(input.plans.size());
        for (int i = 0; i < int(conflicts[state].size()); ++i) {
            out[conflicts[state][i].pair.first].push_back(i);
            out[conflicts[state][i].pair.second].push_back(i);
        }
        return out;
    }
    void conflict_report(int state, Lines &out) const {
        const auto &list = conflicts[state];
        line(out, "CONFLICTS plan=", state ? "final" : "initial", " count=", list.size());
        double duration = 0, minimum = 0;
        std::array<int, 3> geometry{}, severity{};
        for (int i = 0; i < int(list.size()); ++i) {
            const Conflict &item = list[i];
            const Piece &piece = item.closest;
            const Segment &a = trajectories[state][item.pair.first].segments[piece.first_segment];
            const Segment &b = trajectories[state][item.pair.second].segments[piece.second_segment];
            line(out, "CONFLICT ", i + 1, " ", pair_name(item.pair), " start=", decimal(item.start),
                 " end=", decimal(item.end), " duration=", decimal(item.end - item.start),
                 " outcome=", item.outcome);
            line(out, "  CPA t=", decimal(piece.loss.time), " dist=", decimal(piece.loss.distance),
                 " vert=", decimal(piece.loss.vertical, 1),
                 " levels=", decimal(item.first_level, 2), "/", decimal(item.second_level, 2),
                 " tracks=", decimal(item.first_track, 1), "/", decimal(item.second_track, 1),
                 " angle=", decimal(item.angle, 1));
            line(out, "  TYPE geometry=", geometry_names[item.geometry],
                 " phases=", phase_name(a.phase), "/", phase_name(b.phase), " segments=", a.number,
                 "/", b.number, " sector=", sector_name(item.sector),
                 " severity=", severity_names[item.severity]);
            for (const Piece &part : item.pieces)
                line(out, "  PIECE ", part.first_segment + 1, "/", part.second_segment + 1, " ",
                     decimal(part.loss.low), " ", decimal(part.loss.high));
            duration += item.end - item.start;
            if (i == 0 || piece.loss.distance < minimum)
                minimum = piece.loss.distance;
            ++geometry[item.geometry];
            ++severity[item.severity];
        }
        line(out, "SUMMARY count=", list.size(), " total=", decimal(duration),
             " min_dist=", list.empty() ? "-" : decimal(minimum), " head_on=", geometry[0],
             " crossing=", geometry[1], " trailing=", geometry[2], " high=", severity[0],
             " medium=", severity[1], " low=", severity[2]);
        const auto involved = involvement(state);
        for (int flight = 0; flight < int(involved.size()); ++flight)
            if (!involved[flight].empty()) {
                std::set<int> partners;
                for (int index : involved[flight]) {
                    Pair pair = list[index].pair;
                    partners.insert(pair.first == flight ? pair.second : pair.first);
                }
                Names names;
                for (int partner : partners)
                    names.push_back(callsign(partner));
                line(out, "FLIGHT ", callsign(flight), " conflicts=", involved[flight].size(),
                     " first=", decimal(list[involved[flight][0]].start),
                     " partners=", joined(names));
            }
        line(out, "TIMELINE from=", input.params.sample_start, " to=", input.params.sample_end,
             " step=60");
        for (int flight = 0; flight < int(involved.size()); ++flight)
            if (!involved[flight].empty()) {
                std::string text;
                for (Integer time : samples) {
                    char character =
                        active_segment(trajectories[state][flight], double(time)) ? '-' : '.';
                    if (character == '-')
                        for (int index : involved[flight])
                            if (active(list[index], double(time))) {
                                character = 'X';
                                break;
                            }
                    text.push_back(character);
                }
                line(out, callsign(flight), " ", text);
            }
    }
    Lines resolution_report() const {
        Lines out;
        int accepted_count = 0, level_count = 0, speed_count = 0, delay_count = 0, trials = 0,
            infeasible_count = 0, blocked_count = 0;
        for (int i = 0; i < int(rounds.size()); ++i) {
            const Round &record = rounds[i];
            const Conflict &target = record.target;
            line(out, "ROUND ", i + 1, " ", pair_name(target.pair),
                 " start=", decimal(target.start), " end=", decimal(target.end),
                 " dist=", decimal(target.closest.loss.distance));
            for (const Trial &trial : record.trials) {
                std::ostringstream row;
                row << "  TRY " << callsign(trial.flight) << ' ' << trial.name << ' '
                    << trial.status;
                if (trial.blocker)
                    row << ' ' << pair_name(trial.blocker->pair)
                        << " start=" << decimal(trial.blocker->start);
                out.push_back(row.str());
                ++trials;
                infeasible_count += trial.status == "infeasible";
                blocked_count += trial.status == "blocked";
            }
            if (record.accepted) {
                const Trial &trial = *record.accepted;
                line(out, "  RESULT resolved ", callsign(trial.flight), " ", trial.name);
                ++accepted_count;
                level_count += trial.name == "level_up" || trial.name == "level_down";
                speed_count += trial.name == "speed_down";
                delay_count += trial.name.rfind("delay_", 0) == 0;
            } else
                out.push_back("  RESULT unresolved");
        }
        const auto initial = involvement(0), final = involvement(1);
        double total_extra = 0;
        Integer total_delay = 0;
        for (int flight = 0; flight < int(plans[1].size()); ++flight) {
            const Plan &old = plans[0][flight], &revised = plans[1][flight];
            double before = trajectories[0][flight].arrival,
                   after = trajectories[1][flight].arrival, extra = after - before;
            total_extra += extra;
            total_delay += revised.delay;
            line(out, "FLIGHT ", callsign(flight), " departure=", revised.departure + revised.delay,
                 " delay=", revised.delay, " level=", signed_integer(revised.offset),
                 " speed=", old.speed, "->", revised.speed, " arrival=", decimal(before), "->",
                 decimal(after), " extra=", decimal(extra),
                 " length=", decimal(trajectories[1][flight].length),
                 " conflicts=", initial[flight].size(), "->", final[flight].size(),
                 " manoeuvres=", history(flight));
        }
        for (const Conflict &item : unresolved_conflicts)
            line(out, "UNRESOLVED ", pair_name(item.pair), " start=", decimal(item.start),
                 " dist=", decimal(item.closest.loss.distance));
        line(out, "TOTAL rounds=", rounds.size(), " resolved=", accepted_count,
             " unresolved=", unresolved_conflicts.size(), " level=", level_count,
             " speed=", speed_count, " delay=", delay_count, " total_delay=", total_delay,
             " total_extra=", decimal(total_extra), " trials=", trials,
             " infeasible=", infeasible_count, " blocked=", blocked_count);
        return out;
    }
    void compute_transits(int state) {
        for (int flight = 0; flight < int(input.plans.size()); ++flight) {
            std::vector<Transit> list;
            for (int sector = 0; sector < int(input.sectors.size()); ++sector) {
                std::vector<std::pair<double, double>> joined_times;
                for (const Segment &segment : trajectories[state][flight].segments) {
                    auto interval = inside(segment, input.sectors[sector]);
                    if (!interval)
                        continue;
                    if (!joined_times.empty() &&
                        interval->first - joined_times.back().second <= 1e-6)
                        joined_times.back().second = interval->second;
                    else
                        joined_times.push_back(*interval);
                }
                for (const auto &interval : joined_times)
                    list.push_back({flight, sector, interval.first, interval.second});
            }
            std::stable_sort(list.begin(), list.end(), [](const Transit &a, const Transit &b) {
                return std::tie(a.entry, a.sector) < std::tie(b.entry, b.sector);
            });
            for (int i = 1; i < int(list.size()); ++i)
                if (std::abs(list[i].entry - list[i - 1].exit) <= 1e-6) {
                    list[i - 1].next = list[i].sector;
                    list[i].previous = list[i - 1].sector;
                }
            transits[state].insert(transits[state].end(), list.begin(), list.end());
        }
    }
    Lines transit_report() const {
        Lines out{"callsign,sector,entry,exit,duration,from,to"};
        for (const Transit &item : transits[1])
            line(out, callsign(item.flight), ",", sector_name(item.sector), ",",
                 decimal(item.entry), ",", decimal(item.exit), ",", decimal(item.exit - item.entry),
                 ",", sector_name(item.previous), ",", sector_name(item.next));
        return out;
    }
    void compute_occupancy(int state) {
        occupancy[state] = Occupancy(input.sectors.size(), std::vector<int>(samples.size()));
        for (std::size_t i = 0; i < samples.size(); ++i)
            for (const Trajectory &trajectory : trajectories[state]) {
                const Segment *segment = active_segment(trajectory, double(samples[i]));
                if (!segment)
                    continue;
                Point point = position(*segment, double(samples[i]));
                for (int sector = 0; sector < int(input.sectors.size()); ++sector)
                    if (contains(input.sectors[sector], point))
                        ++occupancy[state][sector][i];
            }
    }
    void compute_periods() {
        for (int sector = 0; sector < int(input.sectors.size()); ++sector)
            for (std::size_t i = 0; i < samples.size(); i += 5) {
                Period period;
                period.sector = sector;
                period.number = i / 5 + 1;
                period.start = samples[i];
                period.end = period.start + 300;
                int sum = 0;
                for (int state = 0; state < 2; ++state) {
                    for (std::size_t j = i; j < i + 5; ++j) {
                        period.peak[state] =
                            std::max(period.peak[state], occupancy[state][sector][j]);
                        if (state == 1)
                            sum += occupancy[state][sector][j];
                    }
                    for (const Transit &item : transits[state])
                        if (item.sector == sector && double(period.start) <= item.entry &&
                            item.entry < double(period.end))
                            ++period.entries[state];
                }
                period.mean = double(sum) / 5;
                period.status = period.peak[1] > input.sectors[sector].capacity   ? "OVER"
                                : period.peak[0] > input.sectors[sector].capacity ? "RELIEVED"
                                                                                  : "OK";
                periods.push_back(period);
            }
    }
    Lines sector_load_report() const {
        Lines out{
            "sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status"};
        for (const Period &period : periods)
            line(out, sector_name(period.sector), ",", period.number, ",", period.start, ",",
                 period.end, ",", period.entries[0], ",", period.entries[1], ",", period.peak[0],
                 ",", period.peak[1], ",", decimal(period.mean, 1), ",",
                 input.sectors[period.sector].capacity, ",", period.status);
        return out;
    }
    using LevelUsage = std::map<Integer, std::pair<std::set<int>, double>>;
    LevelUsage level_usage(int state) const {
        LevelUsage out;
        for (int flight = 0; flight < int(input.plans.size()); ++flight)
            for (const Segment &segment : trajectories[state][flight].segments)
                if (segment.phase == Phase::Level) {
                    auto &usage = out[Integer(segment.start[2] / 100)];
                    usage.first.insert(flight);
                    usage.second += segment.end_time - segment.start_time;
                }
        return out;
    }
    Lines sector_report() const {
        Lines out;
        for (int sector = 0; sector < int(input.sectors.size()); ++sector) {
            const Sector &s = input.sectors[sector];
            line(out, "SECTOR ", s.name, " x=", s.x1, "..", s.x2, " y=", s.y1, "..", s.y2,
                 " fl=", s.lower, "..", s.upper, " capacity=", s.capacity);
            for (int state = 0; state < 2; ++state) {
                std::size_t entries = 0, conflict_count = 0;
                double dwell = 0;
                int peak = 0, over = 0;
                for (const Transit &item : transits[state])
                    if (item.sector == sector) {
                        ++entries;
                        dwell += item.exit - item.entry;
                    }
                for (int value : occupancy[state][sector])
                    peak = std::max(peak, value);
                for (const Period &period : periods)
                    if (period.sector == sector && period.peak[state] > s.capacity)
                        ++over;
                for (const Conflict &item : conflicts[state])
                    conflict_count += item.sector == sector;
                line(out, state ? "FINAL" : "INITIAL", " entries=", entries,
                     " time=", decimal(dwell),
                     " mean=", entries ? decimal(dwell / double(entries)) : "-", " peak=", peak,
                     " over=", over, " conflicts=", conflict_count);
            }
            Integer height = s.capacity + 1;
            for (int value : occupancy[1][sector])
                height = std::max(height, Integer(value));
            Names grid;
            for (Integer k = height; k >= 1; --k) {
                std::string row;
                for (int value : occupancy[1][sector])
                    row.push_back(value >= k ? '#' : k == s.capacity ? '-' : '.');
                grid.push_back(row);
            }
            frame(out, grid);
        }
        LevelUsage before = level_usage(0), after = level_usage(1);
        std::set<Integer, std::greater<Integer>> levels;
        for (const auto &entry : before)
            levels.insert(entry.first);
        for (const auto &entry : after)
            levels.insert(entry.first);
        out.push_back("LEVELS");
        for (Integer level : levels)
            line(out, "LEVEL ", level, " flights=", before[level].first.size(), "->",
                 after[level].first.size(), " time=", decimal(before[level].second), "->",
                 decimal(after[level].second));
        std::map<Pair, int> handoffs;
        int total = 0;
        for (const Transit &item : transits[1])
            if (item.next >= 0) {
                ++handoffs[{item.sector, item.next}];
                ++total;
            }
        line(out, "HANDOFFS plan=final count=", total);
        for (const auto &entry : handoffs)
            line(out, "HANDOFF ", sector_name(entry.first.first), " ",
                 sector_name(entry.first.second), " ", entry.second);
        return out;
    }
    void alert_report(int state, Lines &out) const {
        std::vector<Alert> alerts;
        for (int first = 0; first < int(input.plans.size()); ++first)
            for (int second = first + 1; second < int(input.plans.size()); ++second) {
                std::vector<Alert> grouped;
                for (Integer time : samples) {
                    const Segment *a = active_segment(trajectories[state][first], double(time));
                    const Segment *b = active_segment(trajectories[state][second], double(time));
                    if (!a || !b)
                        continue;
                    Point pa = position(*a, double(time)), pb = position(*b, double(time)),
                          relative, velocity;
                    for (int axis = 0; axis < 3; ++axis) {
                        relative[axis] = pa[axis] - pb[axis];
                        velocity[axis] = a->velocity[axis] - b->velocity[axis];
                    }
                    auto loss = loss_interval(relative, velocity, 0, double(input.params.alert),
                                              double(input.params.horizontal),
                                              double(input.params.vertical));
                    if (!loss)
                        continue;
                    if (!grouped.empty() && time - grouped.back().last == 60) {
                        Alert &item = grouped.back();
                        item.last = time;
                        ++item.samples;
                        item.distance = std::min(item.distance, loss->distance);
                    } else
                        grouped.push_back({{first, second},
                                           time,
                                           time,
                                           1,
                                           double(time) + loss->low,
                                           loss->distance,
                                           {}});
                }
                alerts.insert(alerts.end(), grouped.begin(), grouped.end());
            }
        std::stable_sort(alerts.begin(), alerts.end(), [](const Alert &a, const Alert &b) {
            return std::tie(a.first, a.pair) < std::tie(b.first, b.pair);
        });
        std::vector<bool> detected(conflicts[state].size(), false);
        for (Alert &alert : alerts)
            for (int i = 0; i < int(conflicts[state].size()); ++i) {
                const Conflict &item = conflicts[state][i];
                if (item.pair == alert.pair &&
                    item.start < double(alert.last + input.params.alert) &&
                    item.end > double(alert.first)) {
                    detected[i] = true;
                    if (!alert.lead)
                        alert.lead = item.start - double(alert.first);
                }
            }
        line(out, "ALERTS plan=", state ? "final" : "initial", " horizon=", input.params.alert,
             " count=", alerts.size());
        double lead_sum = 0;
        int true_count = 0, missed = 0;
        for (int i = 0; i < int(alerts.size()); ++i) {
            const Alert &item = alerts[i];
            line(out, "ALERT ", i + 1, " ", pair_name(item.pair), " first=", item.first,
                 " last=", item.last, " samples=", item.samples,
                 " predicted=", decimal(item.predicted), " min_dist=", decimal(item.distance),
                 " status=", item.lead ? "true" : "false",
                 " lead=", item.lead ? decimal(*item.lead) : "-");
            if (item.lead) {
                lead_sum += *item.lead;
                ++true_count;
            }
        }
        for (int i = 0; i < int(conflicts[state].size()); ++i)
            if (!detected[i]) {
                const Conflict &item = conflicts[state][i];
                ++missed;
                line(out, "MISSED ", pair_name(item.pair), " start=", decimal(item.start),
                     " end=", decimal(item.end));
            }
        line(out, "SUMMARY alerts=", alerts.size(), " true=", true_count,
             " false=", alerts.size() - true_count, " missed=", missed,
             " mean_lead=", true_count ? decimal(lead_sum / true_count) : "-");
    }
    std::optional<Pair> cell(const Point &point) const {
        const auto &r = input.params.radar;
        Integer column = Integer(
            std::floor((10 * point[0] - double(r[0])) * double(r[4]) / double(r[2] - r[0])));
        Integer bottom = Integer(
            std::floor((10 * point[1] - double(r[1])) * double(r[5]) / double(r[3] - r[1])));
        if (column >= 0 && column < r[4] && bottom >= 0 && bottom < r[5])
            return Pair{int(column), int(r[5] - 1 - bottom)};
        return {};
    }
    void radar_snapshot(int state, Integer time, Lines &out) const {
        int width = int(input.params.radar[4]), height = int(input.params.radar[5]);
        Names grid(height, std::string(width, '.'));
        std::vector<int> counts(width * height), first_flight(width * height, -1);
        std::vector<std::optional<Point>> positions(input.plans.size());
        std::vector<const Segment *> segments(input.plans.size(), nullptr);
        std::vector<const Conflict *> active_list;
        std::vector<bool> conflicted(input.plans.size(), false);
        int aircraft = 0;
        for (const Conflict &item : conflicts[state])
            if (active(item, double(time))) {
                active_list.push_back(&item);
                conflicted[item.pair.first] = true;
                conflicted[item.pair.second] = true;
            }
        for (int flight = 0; flight < int(input.plans.size()); ++flight) {
            const Segment *segment = active_segment(trajectories[state][flight], double(time));
            if (!segment)
                continue;
            ++aircraft;
            segments[flight] = segment;
            positions[flight] = position(*segment, double(time));
            auto point = cell(*positions[flight]);
            if (point) {
                int index = point->second * width + point->first;
                ++counts[index];
                first_flight[index] = flight;
            }
        }
        for (int row = 0; row < height; ++row)
            for (int column = 0; column < width; ++column) {
                int index = row * width + column;
                if (counts[index] > 1)
                    grid[row][column] = char('0' + counts[index]);
                else if (counts[index] == 1) {
                    int flight = first_flight[index];
                    char character = callsign(flight)[0];
                    if (conflicted[flight])
                        character = char(character - 'A' + 'a');
                    grid[row][column] = character;
                }
            }
        for (int flight = 0; flight < int(input.plans.size()); ++flight)
            if (positions[flight]) {
                double future = double(time + input.params.leader);
                const Segment *segment = active_segment(trajectories[state][flight], future);
                if (segment) {
                    auto point = cell(position(*segment, future));
                    if (point && grid[point->second][point->first] == '.')
                        grid[point->second][point->first] = '*';
                }
            }
        line(out, "RADAR plan=", state ? "final" : "initial", " t=", time, " aircraft=", aircraft,
             " conflicts=", active_list.size());
        frame(out, grid);
        for (int flight = 0; flight < int(input.plans.size()); ++flight)
            if (positions[flight]) {
                const Point &point = *positions[flight];
                auto location = cell(point);
                std::string location_text = location ? std::to_string(location->first) + "," +
                                                           std::to_string(location->second)
                                                     : "outside";
                line(out, callsign(flight), " x=", decimal(point[0]), " y=", decimal(point[1]),
                     " fl=", decimal(point[2] / 100, 2),
                     " track=", decimal(track(*segments[flight]), 1),
                     " phase=", phase_name(segments[flight]->phase), " cell=", location_text);
            }
        for (const Conflict *item : active_list) {
            const Point &a = *positions[item->pair.first], &b = *positions[item->pair.second];
            double dx = a[0] - b[0], dy = a[1] - b[1];
            line(out, "CONFLICT ", pair_name(item->pair),
                 " dist=", decimal(std::sqrt(dx * dx + dy * dy)),
                 " vert=", decimal(std::abs(a[2] - b[2]), 1));
        }
    }
    void density_report(int state, Lines &out) const {
        int width = int(input.params.radar[4]), height = int(input.params.radar[5]);
        std::vector<Integer> counts(width * height);
        Integer maximum = 0;
        for (Integer time : samples)
            for (const Trajectory &trajectory : trajectories[state]) {
                const Segment *segment = active_segment(trajectory, double(time));
                if (!segment)
                    continue;
                auto point = cell(position(*segment, double(time)));
                if (point)
                    ++counts[point->second * width + point->first];
            }
        Names grid(height, std::string(width, '.'));
        for (int row = 0; row < height; ++row)
            for (int column = 0; column < width; ++column) {
                Integer count = counts[row * width + column];
                maximum = std::max(maximum, count);
                grid[row][column] = count == 0 ? '.' : count < 10 ? char('0' + count) : '#';
            }
        line(out, "DENSITY plan=", state ? "final" : "initial", " from=", input.params.sample_start,
             " to=", input.params.sample_end, " step=60 max=", maximum);
        frame(out, grid);
    }
    Lines strips_report() const {
        Lines out;
        for (int flight = 0; flight < int(input.plans.size()); ++flight) {
            const Plan &plan = plans[1][flight];
            const Trajectory &before = trajectories[0][flight], &after = trajectories[1][flight];
            line(out, "STRIP ", plan.callsign, " type=", input.types[plan.type].name,
                 " waypoints=", plan.waypoints.size(), " length=", decimal(after.length),
                 " manoeuvres=", history(flight));
            for (int k = 0; k < int(plan.waypoints.size()); ++k) {
                const Waypoint &point = plan.waypoints[k];
                line(out, "WPT ", k, " at=", point.x, ":", point.y,
                     " eta=", decimal(before.passing[k].first), "->",
                     decimal(after.passing[k].first), " fl=", before.passing[k].second, "->",
                     after.passing[k].second);
            }
            Names sequence;
            for (const Transit &item : transits[1])
                if (item.flight == flight)
                    sequence.push_back(sector_name(item.sector) + "@" + decimal(item.entry));
            line(out, "SECTORS ", sequence.empty() ? "-" : joined(sequence));
        }
        return out;
    }

  public:
    explicit Traffic(Input data) : input(std::move(data)) {
        plans[0] = input.plans;
        plans[1] = input.plans;
        for (int state = 0; state < 2; ++state)
            for (const Plan &plan : plans[state])
                trajectories[state].push_back(build_trajectory(plan, input.types));
        for (Integer time = input.params.sample_start; time < input.params.sample_end; time += 60)
            samples.push_back(time);
    }
    void run() {
        conflicts[0] = all_conflicts(trajectories[0], input.params);
        resolve();
        conflicts[1] = all_conflicts(trajectories[1], input.params);
        for (const Conflict &item : conflicts[1])
            final_pairs.insert(item.pair);
        for (int state = 0; state < 2; ++state) {
            classify(state);
            compute_transits(state);
            compute_occupancy(state);
        }
        compute_periods();
        std::filesystem::create_directories("output");
        write_lines("trajectories.csv", trajectory_report());
        Lines conflict_lines;
        conflict_report(0, conflict_lines);
        conflict_report(1, conflict_lines);
        write_lines("conflicts.txt", conflict_lines);
        write_lines("resolutions.txt", resolution_report());
        write_lines("sector_transits.csv", transit_report());
        write_lines("sector_load.csv", sector_load_report());
        write_lines("sector_report.txt", sector_report());
        Lines alerts;
        alert_report(0, alerts);
        alert_report(1, alerts);
        write_lines("alerts.txt", alerts);
        Lines radar;
        for (Integer time : input.params.snapshots) {
            radar_snapshot(0, time, radar);
            radar_snapshot(1, time, radar);
        }
        density_report(0, radar);
        density_report(1, radar);
        write_lines("radar.txt", radar);
        write_lines("strips.txt", strips_report());
    }
};
int main() { Traffic(read_inputs()).run(); }
