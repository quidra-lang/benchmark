#include "seismic.hpp"
#include <filesystem>
struct Jack {
    int station;
    double dx, dy, dz, shift;
};
struct Event {
    Ids used;
    Run first, final;
    Observations observations;
    Ellipse error{};
    double start_rms = 0, gap = 0, dmin = 0, dh = 0, dz = 0;
    char quality = 'C';
    std::vector<Jack> jack;
    int max_jack = 0, cluster = 0;
    std::vector<PickMagnitude> magnitudes;
    std::optional<double> ml, mlc;
    double md = 0;
};
static std::string decimal(double value, int digits) {
    const I amount = scaled(value, digits);
    I factor = 1;
    for (int i = 0; i < digits; ++i)
        factor *= 10;
    std::ostringstream out;
    if (amount < 0)
        out << '-';
    out << std::abs(amount) / factor;
    if (digits)
        out << '.' << std::setfill('0') << std::setw(digits) << std::abs(amount) % factor;
    return out.str();
}
static std::string time_text(I value) {
    std::ostringstream out;
    out << value / 100 << '.' << std::setfill('0') << std::setw(2) << value % 100;
    return out.str();
}
static std::string optional_decimal(std::optional<double> value) {
    return value ? decimal(*value, 2) : "-";
}
static const char *state_text(State state) {
    static const char *names[] = {"used", "dropped", "added", "rejected", "unassociated"};
    return names[int(state)];
}
static Observations observations(const Ids &ids, const std::vector<Pick> &picks,
                                 const std::vector<Station> &stations, bool corrected = false) {
    Observations out;
    for (int id : ids) {
        const Pick &pick = picks[id];
        out.push_back({pick.station, pick.time() - (corrected ? stations[pick.station].correction : 0)});
    }
    return out;
}
static void solution_line(std::ostream &out, const std::string &label, const Solution &q, double error) {
    out << label << " x=" << decimal(q[0], 1) << " y=" << decimal(q[1], 1) << " z=" << decimal(q[2], 1)
        << " t0=" << decimal(q[3], 3) << " rms=" << decimal(error, 4) << '\n';
}
static void trace_lines(std::ostream &out, const Run &run) {
    for (int i = 0; i < 8; ++i)
        solution_line(out, "ITER " + std::to_string(i + 1), run.trace[i].solution, run.trace[i].rms);
}
static void pass_lines(std::ostream &out, int pass, const Ids &ids, const Run &run,
                       const std::vector<Pick> &picks, const std::vector<Station> &stations,
                       const Params &p) {
    out << "PASS " << pass << " stations=";
    for (int i = 0; i < int(ids.size()); ++i)
        out << (i ? "," : "") << stations[picks[ids[i]].station].code;
    out << '\n';
    solution_line(out, "GRID", run.grid, run.grid_rms);
    out << "PROFILE";
    for (double value : run.profile)
        out << ' ' << decimal(value, 4);
    out << '\n';
    trace_lines(out, run);
    for (int i = 0; i < int(ids.size()); ++i) {
        const Pick &pick = picks[ids[i]];
        const Station &s = stations[pick.station];
        const double d = distance(run.solution, s);
        out << "RES " << s.code << " dist=" << decimal(d, 1) << " tt=" << decimal(d / p.velocity, 4)
            << " obs=" << time_text(pick.sample) << " res=" << decimal(run.residual[i], 4) << '\n';
    }
}
struct Position {
    I column, row;
    bool valid = false;
};
using Grid = std::vector<std::string>;
static std::string position_text(Position p) {
    return p.valid ? std::to_string(p.column) + "," + std::to_string(p.row) : "outside";
}
static Position map_position(I x, I y, const Params &p) {
    if (x < 10 * p.area[0] || x >= 10 * p.area[1] || y < 10 * p.area[2] || y >= 10 * p.area[3])
        return {};
    return {floor_div((x - 10 * p.area[0]) * p.map_size[0], 10 * (p.area[1] - p.area[0])),
            p.map_size[1] - 1 - floor_div((y - 10 * p.area[2]) * p.map_size[1], 10 * (p.area[3] - p.area[2])),
            true};
}
static Position section_position(I coordinate, I z, I low, I high, const Params &p) {
    if (coordinate < 10 * low || coordinate >= 10 * high || z >= 10 * p.section[0])
        return {};
    return {floor_div((coordinate - 10 * low) * p.map_size[0], 10 * (high - low)),
            floor_div(z * p.section[1], 10 * p.section[0]), true};
}
static char symbol(const Event &event) {
    if (!event.ml)
        return '?';
    const I h = scaled(*event.ml, 2);
    return h < 100 ? '.' : h < 200 ? 'o' : h < 300 ? 'O' : '@';
}
static void place(Grid &grid, Position p, char value) {
    if (!p.valid)
        return;
    const std::string priority = " ?.oO@^";
    char &current = grid[p.row][p.column];
    if (priority.find(value) > priority.find(current))
        current = value;
}
static void draw(std::ostream &out, const Grid &grid) {
    const std::string frame = "+" + std::string(grid.front().size(), '-') + "+";
    out << frame << '\n';
    for (const auto &line : grid)
        out << '|' << line << "|\n";
    out << frame << '\n';
}
int main() {
    std::filesystem::create_directories("output");
    Params p{};
    std::vector<Station> stations;
    load(stations, p);
    std::vector<Pick> picks;
    for (int s = 0; s < int(stations.size()); ++s) {
        auto detected = detect_station(stations[s], s, p);
        picks.insert(picks.end(), detected.begin(), detected.end());
    }
    std::stable_sort(picks.begin(), picks.end(), [](const Pick &a, const Pick &b) {
        return a.sample < b.sample || (a.sample == b.sample && a.station < b.station);
    });
    auto candidates = associate(picks, p);
    std::vector<Event> events;
    std::ofstream locations("output/locations.txt");
    int rejected = 0;
    for (int ci = 0; ci < int(candidates.size()); ++ci) {
        Candidate &candidate = candidates[ci];
        std::sort(candidate.picks.begin(), candidate.picks.end(),
                  [&](int a, int b) { return picks[a].station < picks[b].station; });
        const Run first = locate(observations(candidate.picks, picks, stations), stations, p);
        candidate.passes.push_back(first);
        for (int i = 0; i < int(candidate.picks.size()); ++i) {
            if (std::abs(first.residual[i]) > p.limit) {
                candidate.dropped.push_back(candidate.picks[i]);
                candidate.drop_residual.push_back(first.residual[i]);
            } else
                candidate.retained.push_back(candidate.picks[i]);
        }
        locations << "CANDIDATE " << ci + 1 << " picks=" << candidate.picks.size()
                  << " first=" << time_text(picks[candidate.first].sample) << '\n';
        pass_lines(locations, 1, candidate.picks, first, picks, stations, p);
        for (int i = 0; i < int(candidate.dropped.size()); ++i)
            locations << "DROP " << stations[picks[candidate.dropped[i]].station].code
                      << " res=" << decimal(candidate.drop_residual[i], 4) << '\n';
        if (!candidate.dropped.empty() && candidate.retained.size() < std::size_t(p.minimum)) {
            candidate.rejected = true;
            ++rejected;
            for (int id : candidate.picks)
                picks[id].state = State::rejected;
            locations << "RESULT REJECTED stations=" << candidate.retained.size() << '\n';
            continue;
        }
        Run adopted = first;
        if (!candidate.dropped.empty()) {
            adopted = locate(observations(candidate.retained, picks, stations), stations, p);
            candidate.passes.push_back(adopted);
            pass_lines(locations, 2, candidate.retained, adopted, picks, stations, p);
        }
        candidate.event = events.size() + 1;
        for (int i = 0; i < int(candidate.retained.size()); ++i) {
            Pick &pick = picks[candidate.retained[i]];
            pick.state = State::used;
            pick.event = candidate.event;
            pick.first_residual = adopted.residual[i];
            Station &s = stations[pick.station];
            ++s.used;
            s.correction += pick.first_residual;
            s.first_square += pick.first_residual * pick.first_residual;
        }
        for (int id : candidate.dropped) {
            picks[id].state = State::dropped;
            picks[id].event = candidate.event;
        }
        Event event;
        event.used = candidate.retained;
        event.first = std::move(adopted);
        events.push_back(std::move(event));
        locations << "RESULT EVENT " << candidate.event << '\n';
    }
    locations << "CORRECTIONS\n";
    for (Station &s : stations) {
        if (s.used)
            s.correction /= s.used;
        locations << s.code << " n=" << s.used << " correction=" << decimal(s.correction, 4) << '\n';
    }
    for (int ei = 0; ei < int(events.size()); ++ei) {
        Event &event = events[ei];
        event.observations = observations(event.used, picks, stations, true);
        event.start_rms = rms(event.first.solution, event.observations, stations, p.velocity);
        event.final = geiger(event.first.solution, event.observations, stations, p.velocity);
        const Solution &q = event.final.solution;
        event.error = ellipse(q, event.observations, stations, p.velocity);
        Values angles;
        event.dmin = std::numeric_limits<double>::infinity();
        for (int i = 0; i < int(event.used.size()); ++i) {
            Pick &pick = picks[event.used[i]];
            Station &s = stations[pick.station];
            pick.residual = event.final.residual[i];
            s.final_square += pick.residual * pick.residual;
            double angle = std::atan2(s.x - q[0], s.y - q[1]) * 180 / pi;
            if (angle < 0)
                angle += 360;
            angles.push_back(angle);
            const double dx = s.x - q[0], dy = s.y - q[1];
            event.dmin = std::min(event.dmin, std::sqrt(dx * dx + dy * dy));
        }
        std::sort(angles.begin(), angles.end());
        event.gap = angles.front() + 360 - angles.back();
        for (int i = 1; i < int(angles.size()); ++i)
            event.gap = std::max(event.gap, angles[i] - angles[i - 1]);
        auto fits = [&](const auto &bounds) {
            return event.gap <= bounds[0] && event.final.rms <= bounds[1] && event.error.smaj <= bounds[2];
        };
        event.quality = fits(p.qa) ? 'A' : fits(p.qb) ? 'B' : 'C';
        const double dx = q[0] - event.first.solution[0], dy = q[1] - event.first.solution[1];
        event.dh = std::sqrt(dx * dx + dy * dy);
        event.dz = q[2] - event.first.solution[2];
        for (int omitted = 0; omitted < int(event.used.size()); ++omitted) {
            Observations remaining;
            for (int j = 0; j < int(event.used.size()); ++j)
                if (j != omitted)
                    remaining.push_back(event.observations[j]);
            const Solution alternative = geiger(q, remaining, stations, p.velocity).solution;
            const double x = alternative[0] - q[0], y = alternative[1] - q[1], z = alternative[2] - q[2];
            event.jack.push_back({picks[event.used[omitted]].station, x, y, z, std::sqrt(x * x + y * y)});
            if (event.jack.back().shift > event.jack[event.max_jack].shift)
                event.max_jack = omitted;
        }
        locations << "EVENT " << ei + 1 << '\n';
        solution_line(locations, "START", event.first.solution, event.start_rms);
        trace_lines(locations, event.final);
        for (int id : event.used) {
            const Pick &pick = picks[id];
            const Station &s = stations[pick.station];
            const double d = distance(q, s);
            locations << "RES " << s.code << " dist=" << decimal(d, 1) << " tt=" << decimal(d / p.velocity, 4)
                      << " obs=" << time_text(pick.sample) << " corr=" << decimal(s.correction, 4)
                      << " res=" << decimal(pick.residual, 4) << '\n';
        }
        const Ellipse &e = event.error;
        locations << "ELLIPSE smaj=" << decimal(e.smaj, 1) << " smin=" << decimal(e.smin, 1)
                  << " az=" << decimal(e.az, 1) << " erz=" << decimal(e.erz, 1)
                  << " ert=" << decimal(e.ert, 4) << '\n';
        locations << "SHIFT dh=" << decimal(event.dh, 1) << " dz=" << decimal(event.dz, 1) << '\n';
        locations << "GAP " << decimal(event.gap, 1) << " DMIN " << decimal(event.dmin, 1) << " QUALITY "
                  << event.quality << '\n';
        for (const Jack &jack : event.jack)
            locations << "JACK " << stations[jack.station].code << " dx=" << decimal(jack.dx, 1)
                      << " dy=" << decimal(jack.dy, 1) << " dz=" << decimal(jack.dz, 1)
                      << " shift=" << decimal(jack.shift, 1) << '\n';
        const Jack &maximum = event.jack[event.max_jack];
        locations << "JACKKNIFE max=" << decimal(maximum.shift, 1)
                  << " station=" << stations[maximum.station].code << '\n';
    }
    for (Event &event : events) {
        Values local, duration;
        for (int id : event.used) {
            const Pick &pick = picks[id];
            const auto value =
                magnitude(pick, distance(event.final.solution, stations[pick.station]) / 1000, p);
            event.magnitudes.push_back(value);
            duration.push_back(value.md);
            if (value.ml)
                local.push_back(*value.ml);
        }
        if (!local.empty())
            event.ml = median(local);
        event.md = median(duration);
        for (int i = 0; i < int(event.used.size()); ++i)
            if (event.magnitudes[i].ml) {
                Station &s = stations[picks[event.used[i]].station];
                s.mag_correction += *event.magnitudes[i].ml - *event.ml;
                ++s.mag_count;
            }
    }
    for (Station &s : stations)
        if (s.mag_count)
            s.mag_correction /= s.mag_count;
    for (Event &event : events) {
        Values corrected;
        for (int i = 0; i < int(event.used.size()); ++i)
            if (event.magnitudes[i].ml)
                corrected.push_back(*event.magnitudes[i].ml -
                                    stations[picks[event.used[i]].station].mag_correction);
        if (!corrected.empty())
            event.mlc = median(corrected);
    }
    std::vector<std::pair<double, double>> points;
    double sd = 0, st = 0, sdd = 0, sdt = 0;
    for (const Event &event : events)
        for (int id : event.used) {
            const Pick &pick = picks[id];
            const double d = distance(event.final.solution, stations[pick.station]) / 1000,
                         t = pick.time() - event.final.solution[3];
            points.push_back({d, t});
            sd += d;
            st += t;
            sdd += d * d;
            sdt += d * t;
        }
    const double n = points.size(), slope = (n * sdt - sd * st) / (n * sdd - sd * sd),
                 intercept = (st - slope * sd) / n;
    double ss = 0;
    for (auto point : points) {
        const double r = point.second - intercept - slope * point.first;
        ss += r * r;
    }
    locations << "FIT n=" << points.size() << " velocity=" << decimal(1000 / slope, 1)
              << " intercept=" << decimal(intercept, 4) << " rms=" << decimal(std::sqrt(ss / n), 4) << '\n';
    int cluster_count = 0;
    for (int first = 0; first < int(events.size()); ++first) {
        if (events[first].cluster)
            continue;
        ++cluster_count;
        Ids members{first};
        events[first].cluster = cluster_count;
        for (int head = 0; head < int(members.size()); ++head) {
            const auto &a = events[members[head]].final.solution;
            for (int j = 0; j < int(events.size()); ++j) {
                if (events[j].cluster)
                    continue;
                const auto &b = events[j].final.solution;
                double d2 = 0;
                for (int axis = 0; axis < 3; ++axis)
                    d2 += (a[axis] - b[axis]) * (a[axis] - b[axis]);
                if (std::abs(a[3] - b[3]) <= p.cluster[1] && std::sqrt(d2) <= p.cluster[0]) {
                    events[j].cluster = cluster_count;
                    members.push_back(j);
                }
            }
        }
        std::sort(members.begin(), members.end());
        if (members.size() > 1) {
            Solution center{};
            double low = events[members.front()].final.solution[3], high = low;
            locations << "CLUSTER " << cluster_count << " events=";
            for (int i = 0; i < int(members.size()); ++i) {
                locations << (i ? "," : "") << members[i] + 1;
                const auto &q = events[members[i]].final.solution;
                for (int axis = 0; axis < 3; ++axis)
                    center[axis] += q[axis];
                low = std::min(low, q[3]);
                high = std::max(high, q[3]);
            }
            locations << " x=" << decimal(center[0] / members.size(), 1)
                      << " y=" << decimal(center[1] / members.size(), 1)
                      << " z=" << decimal(center[2] / members.size(), 1) << " span=" << decimal(high - low, 3)
                      << '\n';
        }
    }
    std::vector<std::array<bool, 12>> station_sets(events.size());
    for (int ei = 0; ei < int(events.size()); ++ei)
        for (int id : events[ei].used)
            station_sets[ei][picks[id].station] = true;
    locations << "ADDED\n";
    for (Pick &pick : picks) {
        if (pick.state != State::unassociated)
            continue;
        int selected = -1;
        double best = std::numeric_limits<double>::infinity(), residual = 0;
        for (int ei = 0; ei < int(events.size()); ++ei) {
            if (station_sets[ei][pick.station])
                continue;
            const auto &q = events[ei].final.solution;
            const double rho = pick.time() - q[3] - distance(q, stations[pick.station]) / p.velocity -
                               stations[pick.station].correction;
            if (std::abs(rho) <= p.limit && std::abs(rho) < best) {
                best = std::abs(rho);
                selected = ei;
                residual = rho;
            }
        }
        if (selected >= 0) {
            pick.state = State::added;
            pick.event = selected + 1;
            pick.residual = residual;
            station_sets[selected][pick.station] = true;
            locations << stations[pick.station].code << " sample=" << pick.sample << " event=" << pick.event
                      << " res=" << decimal(pick.residual, 4) << '\n';
        }
    }
    int unassociated = 0;
    for (const Pick &pick : picks)
        unassociated += pick.state == State::unassociated;
    Values depths;
    std::array<int, 3> quality{};
    double total_rms = 0;
    for (const Event &event : events) {
        depths.push_back(event.final.solution[2]);
        ++quality[event.quality - 'A'];
        total_rms += event.final.rms;
    }
    locations << "SUMMARY picks=" << picks.size() << " candidates=" << candidates.size()
              << " events=" << events.size() << " rejected=" << rejected << " unassociated=" << unassociated
              << '\n';
    locations << "DEPTH min=" << decimal(*std::min_element(depths.begin(), depths.end()), 1)
              << " median=" << decimal(median(depths), 1)
              << " max=" << decimal(*std::max_element(depths.begin(), depths.end()), 1) << '\n';
    locations << "QUALITY A=" << quality[0] << " B=" << quality[1] << " C=" << quality[2]
              << " mean_rms=" << decimal(total_rms / events.size(), 4) << '\n';
    std::ofstream pick_file("output/picks.csv"), catalog("output/catalog.csv"), mag("output/magnitudes.txt"),
        station_file("output/stations.txt"), map_file("output/map.txt");
    pick_file << "station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual\n";
    for (const Pick &pick : picks)
        pick_file << stations[pick.station].code << ',' << pick.sample << ',' << time_text(pick.sample) << ','
                  << pick.duration << ',' << decimal(pick.ratio, 2) << ',' << pick.amplitude << ','
                  << (pick.clipped ? "yes" : "no") << ',' << pick.event << ',' << state_text(pick.state)
                  << ','
                  << ((pick.state == State::used || pick.state == State::added) ? decimal(pick.residual, 4)
                                                                                : "-")
                  << '\n';
    catalog
        << "event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster\n";
    Values local, duration;
    for (int ei = 0; ei < int(events.size()); ++ei) {
        const Event &event = events[ei];
        const auto &q = event.final.solution;
        const auto &e = event.error;
        catalog << ei + 1 << ',' << decimal(q[3], 3) << ',' << decimal(q[0], 1) << ',' << decimal(q[1], 1)
                << ',' << decimal(q[2], 1) << ',' << decimal(event.final.rms, 4) << ',' << event.used.size()
                << ',' << decimal(event.gap, 1) << ',' << decimal(event.dmin, 1) << ',' << decimal(e.smaj, 1)
                << ',' << decimal(e.smin, 1) << ',' << decimal(e.az, 1) << ',' << decimal(e.erz, 1) << ','
                << optional_decimal(event.ml) << ',' << decimal(event.md, 2) << ',' << event.quality << ','
                << event.cluster << '\n';
        int available = 0;
        for (const auto &value : event.magnitudes)
            available += value.ml.has_value();
        mag << "EVENT " << ei + 1 << " ML=" << optional_decimal(event.ml) << " n=" << available
            << " MD=" << decimal(event.md, 2) << '\n';
        for (int i = 0; i < int(event.used.size()); ++i) {
            const auto &value = event.magnitudes[i];
            const Pick &pick = picks[event.used[i]];
            mag << stations[pick.station].code << " r=" << decimal(value.radius, 3)
                << " amp=" << pick.amplitude;
            if (value.ml)
                mag << " ml=" << decimal(*value.ml, 2) << " res=" << decimal(*value.ml - *event.ml, 2);
            else
                mag << " clipped";
            mag << " dur=" << pick.duration << " md=" << decimal(value.md, 2) << '\n';
        }
        if (event.ml) {
            local.push_back(*event.ml);
            duration.push_back(event.md);
        }
    }
    mag << "CORRECTED\n";
    for (int ei = 0; ei < int(events.size()); ++ei)
        mag << "EVENT " << ei + 1 << " MLC=" << optional_decimal(events[ei].mlc) << '\n';
    const Frequency f = frequency(local, duration);
    mag << "FMD\n";
    for (I t = f.counts.begin()->first; t <= f.counts.rbegin()->first; ++t) {
        int count = 0, cumulative = 0;
        for (auto entry : f.counts) {
            if (entry.first == t)
                count = entry.second;
            if (entry.first >= t)
                cumulative += entry.second;
        }
        mag << "M=" << class_text(t) << " N=" << count << " CUM=" << cumulative << '\n';
    }
    mag << "MC " << class_text(f.completeness) << "\nBVALUE " << decimal(f.b, 3) << " SIGMA "
        << decimal(f.sigma, 3) << " N " << f.nb << "\nAVALUE " << decimal(f.a, 3) << '\n';
    mag << "MLMD n=" << f.n << " slope=" << decimal(f.slope, 3) << " intercept=" << decimal(f.intercept, 3)
        << " r=" << decimal(f.r, 3) << " mean_diff=" << decimal(f.mean_diff, 3) << '\n';
    const auto &t = p.timeline;
    Grid timeline(t[4], std::string(t[1], ' '));
    for (const Event &event : events) {
        if (!event.ml)
            continue;
        const I time = scaled(event.final.solution[3], 3), h = scaled(*event.ml, 2);
        if (time < 0 || time >= 1000 * t[0] || h < 100 * t[2])
            continue;
        const I col = floor_div(time * t[1], 1000 * t[0]),
                level = std::min(t[4] - 1, floor_div((h - 100 * t[2]) * t[4], 100 * (t[3] - t[2])));
        for (I k = 0; k <= level; ++k) {
            char &cell = timeline[t[4] - 1 - k][col];
            if (k == level)
                cell = 'o';
            else if (cell == ' ')
                cell = '|';
        }
    }
    mag << "TIMELINE t=0.." << t[0] << " ML=" << t[2] << ".." << t[3] << '\n';
    draw(mag, timeline);
    for (int si = 0; si < int(stations.size()); ++si) {
        const Station &s = stations[si];
        std::array<int, 5> states{};
        int count = 0;
        for (const Pick &pick : picks)
            if (pick.station == si) {
                ++states[int(pick.state)];
                ++count;
            }
        station_file << "STATION " << s.code << " x=" << s.x << " y=" << s.y << " elevation=" << s.elevation
                     << '\n';
        station_file << "SAMPLES start=" << s.start << " count=" << s.samples.size() << " mean=" << s.mean
                     << " noise=" << decimal(s.noise, 1) << " peak=" << s.peak << " clipped=" << s.clipped
                     << '\n';
        station_file << "TRIGGERS total=" << s.triggers << " short=" << s.short_triggers << " picks=" << count
                     << '\n';
        station_file << "PICKS used=" << states[0] << " dropped=" << states[1] << " added=" << states[2]
                     << " rejected=" << states[3] << " unassociated=" << states[4] << '\n';
        station_file << "RESIDUALS n=" << s.used
                     << " rms=" << (s.used ? decimal(std::sqrt(s.first_square / s.used), 4) : "-")
                     << " correction=" << decimal(s.correction, 4)
                     << " after=" << (s.used ? decimal(std::sqrt(s.final_square / s.used), 4) : "-") << '\n';
        station_file << "MAGNITUDES n=" << s.mag_count << " correction=" << decimal(s.mag_correction, 2)
                     << '\n';
    }
    Grid map(p.map_size[1], std::string(p.map_size[0], ' ')),
        ew(p.section[1], std::string(p.map_size[0], ' ')), ns = ew;
    std::vector<std::array<Position, 3>> positions;
    for (const Event &event : events) {
        const I x = scaled(event.final.solution[0], 1), y = scaled(event.final.solution[1], 1),
                z = scaled(event.final.solution[2], 1);
        const std::array<Position, 3> points = {map_position(x, y, p),
                                                section_position(x, z, p.area[0], p.area[1], p),
                                                section_position(y, z, p.area[2], p.area[3], p)};
        positions.push_back(points);
        place(map, points[0], symbol(event));
        place(ew, points[1], symbol(event));
        place(ns, points[2], symbol(event));
    }
    std::vector<Position> station_positions;
    for (const Station &s : stations) {
        const Position point = map_position(10 * s.x, 10 * s.y, p);
        station_positions.push_back(point);
        place(map, point, '^');
    }
    map_file << "MAP x=" << p.area[0] << ".." << p.area[1] << " y=" << p.area[2] << ".." << p.area[3] << '\n';
    draw(map_file, map);
    map_file << "SECTION EW x=" << p.area[0] << ".." << p.area[1] << " z=0.." << p.section[0] << '\n';
    draw(map_file, ew);
    map_file << "SECTION NS y=" << p.area[2] << ".." << p.area[3] << " z=0.." << p.section[0] << '\n';
    draw(map_file, ns);
    map_file << "LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML\n";
    for (int i = 0; i < int(stations.size()); ++i)
        map_file << "STATION " << stations[i].code << " map=" << position_text(station_positions[i]) << '\n';
    for (int i = 0; i < int(events.size()); ++i)
        map_file << "EVENT " << i + 1 << ' ' << symbol(events[i]) << " map=" << position_text(positions[i][0])
                 << " ew=" << position_text(positions[i][1]) << " ns=" << position_text(positions[i][2])
                 << '\n';
}
