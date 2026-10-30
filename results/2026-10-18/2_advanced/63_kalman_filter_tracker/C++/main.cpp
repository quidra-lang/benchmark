#include "tracker.hpp"
struct Target {
    int number;
    std::map<int, Position> positions;
};
struct Input {
    Params params;
    std::vector<std::vector<Position>> measurements{{}};
    Vector times{0};
    std::vector<Target> targets;
};
static Input read_inputs() {
    Input out;
    std::ifstream measurements("input/measurements.csv");
    std::string text;
    std::getline(measurements, text);
    while (std::getline(measurements, text)) {
        std::replace(text.begin(), text.end(), ',', ' ');
        std::istringstream row(text);
        int scan;
        double time, x, y;
        row >> scan >> time >> x >> y;
        if (scan >= int(out.measurements.size())) {
            out.measurements.resize(scan + 1);
            out.times.resize(scan + 1);
        }
        out.times[scan] = time;
        out.measurements[scan].push_back({x, y});
    }
    std::ifstream truth("input/truth.csv");
    std::getline(truth, text);
    while (std::getline(truth, text)) {
        std::replace(text.begin(), text.end(), ',', ' ');
        std::istringstream row(text);
        int target, scan;
        double x, y;
        row >> target >> scan >> x >> y;
        if (out.targets.empty() || out.targets.back().number != target)
            out.targets.push_back({target, {}});
        out.targets.back().positions[scan] = {x, y};
    }
    std::ifstream settings("input/params.txt");
    Params &p = out.params;
    while (std::getline(settings, text)) {
        std::istringstream row(text);
        std::string key;
        row >> key;
        if (key == "MODEL") {
            std::string model;
            row >> model;
            p.ca = model == "CA";
        } else if (key == "Q_CV")
            row >> p.q_cv;
        else if (key == "Q_CA")
            row >> p.q_ca;
        else if (key == "SIGMA")
            row >> p.sigma;
        else if (key == "INIT_VELOCITY_VARIANCE")
            row >> p.velocity;
        else if (key == "INIT_ACCELERATION_VARIANCE")
            row >> p.acceleration;
        else if (key == "GATE")
            row >> p.gate;
        else if (key == "CONFIRM")
            row >> p.confirm >> p.window;
        else if (key == "DELETE")
            row >> p.deletion;
        else if (key == "ABG")
            for (double &value : p.abg)
                row >> value;
        else if (key == "IMM_Q")
            for (double &value : p.imm_q)
                row >> value;
        else if (key == "IMM_TRANSITION")
            for (auto &values : p.transition)
                for (double &value : values)
                    row >> value;
        else if (key == "IMM_INITIAL")
            for (double &value : p.imm_initial)
                row >> value;
        else if (key == "MATCH_DISTANCE")
            row >> p.delta;
        else if (key == "OSPA_CUTOFF")
            row >> p.cutoff;
        else if (key == "CONSISTENCY_BOUND")
            row >> p.bound;
        else if (key == "NIS_EDGES") {
            double value;
            while (row >> value)
                p.edges.push_back(value);
        } else if (key == "PLOT_X")
            row >> p.xmin >> p.xmax;
        else if (key == "PLOT_Y")
            row >> p.ymin >> p.ymax;
        else if (key == "PLOT_SIZE")
            row >> p.width >> p.height;
    }
    return out;
}
static Position position(const Estimate &x) { return {x[0], x[1]}; }
static Estimate estimate(const Vector &x) { return {x[0], x[1], x[2], x[3]}; }
static std::string optional(int value) { return value < 0 ? "-" : std::to_string(value); }
static const std::array<std::string, 5> filters{"cv", "ca", "abg", "imm", "rts"};
static std::string listed(const std::string &key, const Lines &values) {
    std::string out = key;
    for (const std::string &value : values)
        out += " " + value;
    return values.empty() ? out + " none" : out;
}
static std::string scores(const std::array<double, 5> &values) {
    std::string out;
    int best = 0;
    for (int i = 0; i < 5; ++i) {
        if (i)
            out += " ";
        out += filters[i] + " " + real(values[i]);
        if (std::stod(real(values[i])) < std::stod(real(values[best])))
            best = i;
    }
    return out + " best " + filters[best];
}
static void frame(Lines &out, const Lines &grid) {
    std::string border = "+" + std::string(grid[0].size(), '-') + "+";
    out.push_back(border);
    for (const std::string &row : grid)
        out.push_back("|" + row + "|");
    out.push_back(border);
}
struct Track {
    int number, birth, last_hit, confirmed = -1, deleted = -1, hits = 1, misses = 0, status = 0,
                                 target = -1, longest_gap = 0;
    Kalman filter;
    std::vector<std::optional<Position>> observations;
    std::map<int, double> nis;
    std::array<std::vector<Estimate>, 5> estimates;
    std::vector<Matrix> covariances;
    Vector high;
    std::array<double, 2> logs{};
    std::vector<int> primary_matches;
    double path = 0, mean_distance = 0;
    int common = 0;
    Track(int number, int scan, Position point, const Params &p, int scans)
        : number(number), birth(scan), last_hit(scan),
          filter(p.ca, p.ca ? p.q_ca : p.q_cv, p, point), observations(scans + 1),
          covariances(scans + 1), high(scans + 1), primary_matches(scans + 1, -1) {
        observations[scan] = point;
        for (auto &values : estimates)
            values.resize(scans + 1);
    }
};
struct Result {
    int track = -1, common = 0, velocity_count = 0, inside = 0;
    std::array<double, 5> position{}, velocity{};
    double nees = 0;
};
class Analysis {
    const Input &input;
    const Params &p;
    int scans, primary;
    std::vector<Track> tracks;
    std::vector<int> evaluated;
    Lines track_rows{"track,scan,x,y,vx,vy,status"}, log;
    int conflict_m = 0, conflict_t = 0, greedy_differences = 0;
    std::array<std::vector<std::vector<int>>, 5> labels;
    std::array<Vector, 5> ospa_values;
    std::vector<std::array<int, 2>> sizes;
    std::vector<int> matched_tracks;
    std::vector<Result> results;
    std::array<double, 5> overall_position{}, overall_velocity{};
    std::array<std::vector<Continuity>, 5> continuities;
    void tracking() {
        for (int scan = 1; scan <= scans; ++scan) {
            std::vector<int> live;
            for (int i = 0; i < int(tracks.size()); ++i)
                if (tracks[i].status != 2)
                    live.push_back(i);
            const auto &measurements = input.measurements[scan];
            int rows = int(live.size()), columns = int(measurements.size());
            if (scan > 1)
                for (int index : live)
                    tracks[index].filter.predict(input.times[scan] - input.times[scan - 1]);
            Matrix costs = zeros(rows, columns);
            std::vector<std::vector<bool>> usable(rows, std::vector<bool>(columns));
            std::vector<std::vector<Innovation>> innovations(rows,
                                                             std::vector<Innovation>(columns));
            std::vector<int> row_gates(rows), column_gates(columns);
            std::vector<Pair> candidates;
            Lines gates;
            for (int i = 0; i < rows; ++i)
                for (int j = 0; j < columns; ++j) {
                    Innovation innovation = tracks[live[i]].filter.innovation(measurements[j]);
                    if (innovation.distance <= p.gate) {
                        costs[i][j] = innovation.distance;
                        usable[i][j] = true;
                        innovations[i][j] = innovation;
                        ++row_gates[i];
                        ++column_gates[j];
                        candidates.push_back({i, j});
                        gates.push_back(std::to_string(tracks[live[i]].number) + ":" +
                                        std::to_string(j + 1) + "=" + real(innovation.distance));
                    }
                }
            const std::vector<Pair> assigned = optimal_assignment(costs, usable);
            std::sort(candidates.begin(), candidates.end(), [&](Pair a, Pair b) {
                if (costs[a.first][a.second] != costs[b.first][b.second])
                    return costs[a.first][a.second] < costs[b.first][b.second];
                return a < b;
            });
            std::vector<bool> used_rows(rows), used_columns(columns);
            std::vector<Pair> greedy;
            for (Pair pair : candidates)
                if (!used_rows[pair.first] && !used_columns[pair.second]) {
                    greedy.push_back(pair);
                    used_rows[pair.first] = true;
                    used_columns[pair.second] = true;
                }
            std::sort(greedy.begin(), greedy.end());
            greedy_differences += assigned != greedy;
            std::vector<int> matches(rows, -1);
            std::fill(used_columns.begin(), used_columns.end(), false);
            Lines assignment_items, greedy_items, missed, confirmed, deleted, new_items;
            for (Pair pair : assigned) {
                matches[pair.first] = pair.second;
                used_columns[pair.second] = true;
                assignment_items.push_back(std::to_string(tracks[live[pair.first]].number) + ":" +
                                           std::to_string(pair.second + 1));
            }
            for (Pair pair : greedy)
                greedy_items.push_back(std::to_string(tracks[live[pair.first]].number) + ":" +
                                       std::to_string(pair.second + 1));
            for (int row = 0; row < rows; ++row) {
                Track &track = tracks[live[row]];
                int column = matches[row];
                if (column >= 0) {
                    track.filter.update(innovations[row][column]);
                    track.observations[scan] = measurements[column];
                    track.nis[scan] = costs[row][column];
                    track.last_hit = scan;
                    ++track.hits;
                    track.misses = 0;
                } else {
                    ++track.misses;
                    missed.push_back(std::to_string(track.number));
                }
                if (track.status == 1) {
                    if (track.misses >= p.deletion) {
                        track.status = 2;
                        track.deleted = scan;
                        deleted.push_back(std::to_string(track.number));
                    }
                } else if (track.hits >= p.confirm) {
                    track.status = 1;
                    track.confirmed = scan;
                    confirmed.push_back(std::to_string(track.number));
                } else if (scan - track.birth + 1 >= p.window) {
                    track.status = 2;
                    track.deleted = scan;
                    deleted.push_back(std::to_string(track.number));
                }
            }
            std::vector<int> processed = live;
            for (int j = 0; j < columns; ++j)
                if (!used_columns[j]) {
                    int index = int(tracks.size());
                    tracks.emplace_back(index + 1, scan, measurements[j], p, scans);
                    processed.push_back(index);
                    new_items.push_back(std::to_string(index + 1) + ":" + std::to_string(j + 1));
                }
            int cm = 0, ct = 0, tentative = 0, confirmed_count = 0;
            for (int value : column_gates)
                cm += value >= 2;
            for (int value : row_gates)
                ct += value >= 2;
            conflict_m += cm;
            conflict_t += ct;
            for (const Track &track : tracks) {
                tentative += track.status == 0;
                confirmed_count += track.status == 1;
            }
            line(log, "scan ", scan, " tracks ", rows, " measurements ", columns);
            log.push_back(listed("gate", gates));
            log.push_back(listed("assign", assignment_items));
            log.push_back(listed("greedy", greedy_items));
            log.push_back(listed("missed", missed));
            log.push_back(listed("new", new_items));
            log.push_back(listed("confirmed", confirmed));
            log.push_back(listed("deleted", deleted));
            line(log, "status tentative ", tentative, " confirmed ", confirmed_count);
            line(log, "conflicts measurements ", cm, " tracks ", ct);
            for (int index : processed) {
                const Track &track = tracks[index];
                line(track_rows, track.number, ",", scan, ",", real(track.filter.x[0]), ",",
                     real(track.filter.x[1]), ",", real(track.filter.x[2]), ",",
                     real(track.filter.x[3]), ",",
                     track.status == 0   ? "tentative"
                     : track.status == 1 ? "confirmed"
                                         : "deleted");
            }
        }
        for (int i = 0; i < int(tracks.size()); ++i)
            if (tracks[i].confirmed >= 0)
                evaluated.push_back(i);
    }
    void compared_filters() {
        for (int index : evaluated) {
            Track &track = tracks[index];
            std::vector<History> primary_history;
            for (int kind = 0; kind < 2; ++kind) {
                Kalman filter(kind == 1, kind == 1 ? p.q_ca : p.q_cv, p,
                              *track.observations[track.birth]);
                std::vector<History> history;
                double likelihood = 0;
                for (int scan = track.birth; scan <= track.last_hit; ++scan) {
                    if (scan > track.birth) {
                        filter.predict(input.times[scan] - input.times[scan - 1]);
                        if (track.observations[scan])
                            likelihood +=
                                filter.update(filter.innovation(*track.observations[scan]));
                    }
                    track.estimates[kind][scan] = estimate(filter.x);
                    history.push_back({filter.x, filter.xp, filter.P, filter.Pp, filter.F});
                    if (kind == primary)
                        track.covariances[scan] = filter.P;
                }
                track.logs[kind] = likelihood;
                if (kind == primary)
                    primary_history = std::move(history);
            }
            const std::vector<Vector> smoothed = smooth(primary_history);
            for (int scan = track.birth; scan <= track.last_hit; ++scan)
                track.estimates[4][scan] = estimate(smoothed[scan - track.birth]);
            std::array<double, 6> abg{(*track.observations[track.birth])[0],
                                      (*track.observations[track.birth])[1],
                                      0,
                                      0,
                                      0,
                                      0};
            IMM imm(p, *track.observations[track.birth]);
            int gap = 0;
            for (int scan = track.birth; scan <= track.last_hit; ++scan) {
                if (scan > track.birth) {
                    double t = input.times[scan] - input.times[scan - 1];
                    for (int axis = 0; axis < 2; ++axis) {
                        double position = abg[axis], velocity = abg[axis + 2],
                               acceleration = abg[axis + 4];
                        position = position + t * velocity + t * t * acceleration / 2;
                        velocity = velocity + t * acceleration;
                        if (track.observations[scan]) {
                            double residual = (*track.observations[scan])[axis] - position;
                            position = position + p.abg[0] * residual;
                            velocity = velocity + p.abg[1] * residual / t;
                            acceleration = acceleration + 2 * p.abg[2] * residual / (t * t);
                        }
                        abg[axis] = position;
                        abg[axis + 2] = velocity;
                        abg[axis + 4] = acceleration;
                    }
                    imm.step(t, track.observations[scan]);
                }
                track.estimates[2][scan] = {abg[0], abg[1], abg[2], abg[3]};
                track.estimates[3][scan] = imm.estimate();
                track.high[scan] = imm.probabilities[1];
                gap = track.observations[scan] ? 0 : gap + 1;
                track.longest_gap = std::max(track.longest_gap, gap);
                if (scan > track.birth)
                    track.path += distance(position(track.estimates[4][scan - 1]),
                                           position(track.estimates[4][scan]));
            }
        }
    }
    void scan_evaluation() {
        for (int kind = 0; kind < 5; ++kind)
            labels[kind].assign(input.targets.size(), std::vector<int>(scans + 1, -1));
        for (int scan = 1; scan <= scans; ++scan) {
            std::vector<int> active, targets;
            for (int index : evaluated)
                if (tracks[index].birth <= scan && scan <= tracks[index].last_hit)
                    active.push_back(index);
            std::vector<Position> truth;
            for (int b = 0; b < int(input.targets.size()); ++b)
                if (input.targets[b].positions.count(scan)) {
                    targets.push_back(b);
                    truth.push_back(input.targets[b].positions.at(scan));
                }
            sizes.push_back({int(targets.size()), int(active.size())});
            for (int kind = 0; kind < 5; ++kind) {
                Matrix costs = zeros(int(active.size()), int(targets.size()));
                std::vector<std::vector<bool>> usable(active.size(),
                                                      std::vector<bool>(targets.size()));
                std::vector<Position> estimates;
                for (int i = 0; i < int(active.size()); ++i) {
                    estimates.push_back(position(tracks[active[i]].estimates[kind][scan]));
                    for (int j = 0; j < int(targets.size()); ++j) {
                        double value = distance(estimates.back(), truth[j]);
                        if (value <= p.delta) {
                            costs[i][j] = value;
                            usable[i][j] = true;
                        }
                    }
                }
                for (Pair pair : optimal_assignment(costs, usable)) {
                    int index = active[pair.first], target = targets[pair.second];
                    labels[kind][target][scan] = tracks[index].number;
                    if (kind == primary)
                        tracks[index].primary_matches[scan] = target;
                }
                ospa_values[kind].push_back(ospa(estimates, truth, p.cutoff));
            }
        }
        for (int kind = 0; kind < 5; ++kind)
            for (int b = 0; b < int(input.targets.size()); ++b) {
                std::vector<int> sequence;
                for (const auto &entry : input.targets[b].positions)
                    sequence.push_back(labels[kind][b][entry.first]);
                continuities[kind].push_back(continuity(sequence));
            }
    }
    void match_tracks() {
        int rows = int(evaluated.size()), columns = int(input.targets.size());
        Matrix costs = zeros(rows, columns);
        std::vector<std::vector<bool>> usable(rows, std::vector<bool>(columns));
        for (int i = 0; i < rows; ++i) {
            const Track &track = tracks[evaluated[i]];
            for (int b = 0; b < columns; ++b) {
                const auto &truth = input.targets[b].positions;
                double sum = 0;
                int count = 0;
                bool close = false;
                for (int scan = 1; scan <= scans; ++scan) {
                    bool in_track = track.birth <= scan && scan <= track.last_hit,
                         in_target = truth.count(scan) > 0;
                    if (!in_track && !in_target)
                        continue;
                    ++count;
                    if (in_track && in_target) {
                        double value =
                            distance(position(track.estimates[primary][scan]), truth.at(scan));
                        sum += std::min(p.cutoff, value);
                        close = close || value < p.cutoff;
                    } else
                        sum += p.cutoff;
                }
                if (close) {
                    usable[i][b] = true;
                    costs[i][b] = sum / count;
                }
            }
        }
        matched_tracks.assign(columns, -1);
        for (Pair pair : optimal_assignment(costs, usable)) {
            Track &track = tracks[evaluated[pair.first]];
            track.target = pair.second;
            track.mean_distance = costs[pair.first][pair.second];
            matched_tracks[pair.second] = evaluated[pair.first];
            for (const auto &entry : input.targets[pair.second].positions)
                track.common += track.birth <= entry.first && entry.first <= track.last_hit;
        }
    }
    void errors() {
        results.resize(input.targets.size());
        std::array<double, 5> position_sum{}, velocity_sum{};
        int position_count = 0, velocity_count = 0;
        for (int b = 0; b < int(input.targets.size()); ++b) {
            if (matched_tracks[b] < 0)
                continue;
            Track &track = tracks[matched_tracks[b]];
            Result &result = results[b];
            result.track = matched_tracks[b];
            const auto &truth = input.targets[b].positions;
            std::array<double, 5> ps{}, vs{};
            double nees_sum = 0;
            for (const auto &entry : truth) {
                int scan = entry.first;
                if (scan < track.birth || scan > track.last_hit)
                    continue;
                ++result.common;
                ++position_count;
                std::optional<Position> velocity;
                if (truth.count(scan - 1) && truth.count(scan + 1)) {
                    double interval = input.times[scan + 1] - input.times[scan - 1];
                    velocity = Position{(truth.at(scan + 1)[0] - truth.at(scan - 1)[0]) / interval,
                                        (truth.at(scan + 1)[1] - truth.at(scan - 1)[1]) / interval};
                    ++result.velocity_count;
                    ++velocity_count;
                }
                for (int kind = 0; kind < 5; ++kind) {
                    const Estimate &x = track.estimates[kind][scan];
                    double pe = squared_distance(position(x), entry.second);
                    ps[kind] += pe;
                    position_sum[kind] += pe;
                    if (velocity) {
                        double ve = squared_distance({x[2], x[3]}, *velocity);
                        vs[kind] += ve;
                        velocity_sum[kind] += ve;
                    }
                }
                const Estimate &x = track.estimates[primary][scan];
                Matrix covariance{{track.covariances[scan][0][0], track.covariances[scan][0][1]},
                                  {track.covariances[scan][1][0], track.covariances[scan][1][1]}};
                double nees = quadratic2({x[0] - entry.second[0], x[1] - entry.second[1]},
                                         inverse(covariance));
                nees_sum += nees;
                result.inside += nees <= p.bound;
            }
            for (int kind = 0; kind < 5; ++kind) {
                result.position[kind] = std::sqrt(ps[kind] / result.common);
                result.velocity[kind] = std::sqrt(vs[kind] / result.velocity_count);
            }
            result.nees = nees_sum / result.common;
        }
        for (int kind = 0; kind < 5; ++kind) {
            overall_position[kind] = std::sqrt(position_sum[kind] / position_count);
            overall_velocity[kind] = std::sqrt(velocity_sum[kind] / velocity_count);
        }
    }
    Lines evaluation_report() const {
        Lines out;
        int measurements = 0, false_tracks = 0, used = 0, lost = 0;
        for (int scan = 1; scan <= scans; ++scan)
            measurements += int(input.measurements[scan].size());
        for (int index : evaluated) {
            const Track &track = tracks[index];
            false_tracks += std::none_of(track.primary_matches.begin(), track.primary_matches.end(),
                                         [](int value) { return value >= 0; });
            used += track.hits;
        }
        for (int value : matched_tracks)
            lost += value < 0;
        line(out, "summary");
        line(out, "scans ", scans);
        line(out, "measurements ", measurements);
        line(out, "targets ", input.targets.size());
        line(out, "tracks_created ", tracks.size());
        line(out, "tracks_confirmed ", evaluated.size());
        line(out, "false_tracks ", false_tracks);
        line(out, "missed_targets ", lost);
        line(out, "measurements_used ", used);
        line(out, "conflict_measurements ", conflict_m);
        line(out, "conflict_tracks ", conflict_t);
        line(out, "greedy_differences ", greedy_differences);
        line(out, "");
        line(out, "targets");
        for (const Target &target : input.targets) {
            int first = target.positions.begin()->first, last = target.positions.rbegin()->first;
            double path = 0;
            for (int scan = first + 1; scan <= last; ++scan)
                path += distance(target.positions.at(scan - 1), target.positions.at(scan));
            line(out, "target ", target.number, " first ", first, " last ", last, " scans ",
                 target.positions.size(), " path ", real(path), " mean_speed ",
                 real(path / (input.times[last] - input.times[first])));
        }
        line(out, "");
        line(out, "tracks");
        for (int index : evaluated) {
            const Track &track = tracks[index];
            double sum = 0;
            int inside = 0;
            for (const auto &entry : track.nis) {
                sum += entry.second;
                inside += entry.second <= p.bound;
            }
            line(out, "track ", track.number, " birth ", track.birth, " confirmed ",
                 track.confirmed, " end ", track.last_hit, " deleted ", optional(track.deleted),
                 " hits ", track.hits, " misses ", track.last_hit - track.birth + 1 - track.hits,
                 " longest_gap ", track.longest_gap, " path ", real(track.path), " nis ",
                 real(sum / track.nis.size()), " nis_inside ", inside, "/", track.nis.size());
        }
        line(out, "");
        line(out, "matching");
        for (int index : evaluated) {
            const Track &track = tracks[index];
            std::string row =
                "track " + std::to_string(track.number) + " target " +
                (track.target < 0 ? "-" : std::to_string(input.targets[track.target].number));
            if (track.target >= 0)
                row += " common " + std::to_string(track.common) + " mean_distance " +
                       real(track.mean_distance);
            int count = 0;
            Lines segments;
            for (int scan = track.birth; scan <= track.last_hit; ++scan) {
                int target = track.primary_matches[scan];
                if (target < 0)
                    continue;
                int first = scan;
                while (scan < track.last_hit && track.primary_matches[scan + 1] == target)
                    ++scan;
                count += scan - first + 1;
                segments.push_back(std::to_string(first) + "-" + std::to_string(scan) + ":" +
                                   std::to_string(input.targets[target].number));
            }
            row += " matched_scans " + std::to_string(count) + " " + listed("segments", segments);
            out.push_back(row);
        }
        line(out, "");
        line(out, "rmse");
        for (int b = 0; b < int(input.targets.size()); ++b) {
            const Result &result = results[b];
            if (result.track < 0) {
                line(out, "target ", input.targets[b].number, " track -");
                continue;
            }
            line(out, "target ", input.targets[b].number, " track ", tracks[result.track].number,
                 " common ", result.common, " ", scores(result.position));
            line(out, "target ", input.targets[b].number, " velocity ", result.velocity_count, " ",
                 scores(result.velocity));
        }
        line(out, "overall position ", scores(overall_position));
        line(out, "overall velocity ", scores(overall_velocity));
        line(out, "");
        line(out, "consistency");
        for (int b = 0; b < int(input.targets.size()); ++b) {
            const Result &result = results[b];
            if (result.track < 0)
                line(out, "target ", input.targets[b].number, " track -");
            else
                line(out, "target ", input.targets[b].number, " track ",
                     tracks[result.track].number, " nees ", real(result.nees), " inside ",
                     result.inside, "/", result.common);
        }
        std::vector<int> observed(p.edges.size() + 1);
        int nis_count = 0;
        for (int index : evaluated)
            for (const auto &entry : tracks[index].nis) {
                ++nis_count;
                int bin = int(std::upper_bound(p.edges.begin(), p.edges.end(), entry.second) -
                              p.edges.begin());
                ++observed[bin];
            }
        std::string histogram = "nis_histogram total " + std::to_string(nis_count) + " observed";
        for (int value : observed)
            histogram += " " + std::to_string(value);
        histogram += " expected";
        double lower = 0;
        for (int bin = 0; bin < int(observed.size()); ++bin) {
            double upper_probability = bin == int(p.edges.size()) ? 0 : std::exp(-p.edges[bin] / 2);
            histogram += " " + real(nis_count * (std::exp(-lower / 2) - upper_probability));
            if (bin < int(p.edges.size()))
                lower = p.edges[bin];
        }
        out.push_back(histogram);
        line(out, "");
        line(out, "models");
        for (int index : evaluated) {
            const Track &track = tracks[index];
            line(out, "track ", track.number, " updates ", track.nis.size(), " cv ",
                 real(track.logs[0]), " ca ", real(track.logs[1]), " better ",
                 track.logs[0] >= track.logs[1] ? "cv" : "ca");
        }
        line(out, "");
        line(out, "ospa cutoff ", real(p.cutoff), " order 2");
        line(out, "scan targets tracks cv ca abg imm rts");
        for (int scan = 1; scan <= scans; ++scan) {
            std::string row = std::to_string(scan) + " " + std::to_string(sizes[scan - 1][0]) +
                              " " + std::to_string(sizes[scan - 1][1]);
            for (int kind = 0; kind < 5; ++kind)
                row += " " + real(ospa_values[kind][scan - 1]);
            out.push_back(row);
        }
        std::string means = "mean";
        for (int kind = 0; kind < 5; ++kind) {
            double sum = 0;
            for (double value : ospa_values[kind])
                sum += value;
            means += " " + real(sum / scans);
        }
        out.push_back(means);
        line(out, "");
        line(out, "continuity");
        for (int kind = 0; kind < 5; ++kind) {
            int covered = 0, breaks = 0, swaps = 0;
            for (Continuity value : continuities[kind]) {
                covered += value.covered;
                breaks += value.breaks;
                swaps += value.swaps;
            }
            line(out, filters[kind], " covered ", covered, " breaks ", breaks, " swaps ", swaps);
            for (int b = 0; b < int(input.targets.size()); ++b) {
                Continuity value = continuities[kind][b];
                line(out, "  target ", input.targets[b].number, " scans ",
                     input.targets[b].positions.size(), " covered ", value.covered, " breaks ",
                     value.breaks, " swaps ", value.swaps, " delay ", optional(value.delay));
            }
        }
        line(out, "");
        line(out, "imm");
        for (int index : evaluated) {
            const Track &track = tracks[index];
            double sum = 0;
            int maximum = track.birth, count = 0;
            Lines segments;
            for (int scan = track.birth; scan <= track.last_hit; ++scan) {
                sum += track.high[scan];
                if (track.high[scan] > track.high[maximum])
                    maximum = scan;
                count += track.high[scan] > 0.5;
            }
            for (int scan = track.birth; scan <= track.last_hit; ++scan)
                if (track.high[scan] > 0.5) {
                    int first = scan;
                    while (scan < track.last_hit && track.high[scan + 1] > 0.5)
                        ++scan;
                    segments.push_back(std::to_string(first) + "-" + std::to_string(scan));
                }
            line(out, "track ", track.number, " mean_high ",
                 real(sum / (track.last_hit - track.birth + 1)), " max_high ",
                 real(track.high[maximum]), " at ", maximum, " high_scans ", count, " ",
                 listed("segments", segments));
        }
        return out;
    }
    char character(int evaluated_index) const {
        return char(evaluated_index < 26 ? 'A' + evaluated_index : 'a' + evaluated_index - 26);
    }
    std::optional<Pair> cell(Position point) const {
        double dx = (p.xmax - p.xmin) / p.width, dy = (p.ymax - p.ymin) / p.height;
        int column = int(std::floor((point[0] - p.xmin) / dx)),
            row = int(std::floor((p.ymax - point[1]) / dy));
        if (column < 0 || column >= p.width || row < 0 || row >= p.height)
            return {};
        return Pair{row, column};
    }
    Lines plots() const {
        Lines out;
        line(out, "tracks x ", real(p.xmin), " ", real(p.xmax), " y ", real(p.ymin), " ",
             real(p.ymax), " size ", p.width, " ", p.height);
        Lines grid(p.height, std::string(p.width, ' '));
        for (const Target &target : input.targets)
            for (const auto &entry : target.positions)
                if (auto location = cell(entry.second))
                    grid[location->first][location->second] = '.';
        for (int i = 0; i < int(evaluated.size()); ++i) {
            const Track &track = tracks[evaluated[i]];
            for (int scan = track.birth; scan <= track.last_hit; ++scan)
                if (auto location = cell(position(track.estimates[4][scan])))
                    grid[location->first][location->second] = character(i);
        }
        frame(out, grid);
        for (int i = 0; i < int(evaluated.size()); ++i) {
            const Track &track = tracks[evaluated[i]];
            line(out, character(i), " track ", track.number, " target ",
                 track.target < 0 ? "-" : std::to_string(input.targets[track.target].number));
        }
        line(out, "");
        line(out, "measurements");
        std::vector<std::vector<int>> counts(p.height, std::vector<int>(p.width));
        for (int scan = 1; scan <= scans; ++scan)
            for (Position point : input.measurements[scan])
                if (auto location = cell(point))
                    ++counts[location->first][location->second];
        for (int row = 0; row < p.height; ++row)
            for (int column = 0; column < p.width; ++column) {
                int count = counts[row][column];
                grid[row][column] = count == 0 ? ' ' : count >= 10 ? '#' : char('0' + count);
            }
        frame(out, grid);
        line(out, "");
        line(out, "timeline");
        std::map<int, char> characters;
        for (int i = 0; i < int(evaluated.size()); ++i)
            characters[tracks[evaluated[i]].number] = character(i);
        for (int b = 0; b < int(input.targets.size()); ++b) {
            std::string timeline(scans, ' ');
            for (const auto &entry : input.targets[b].positions) {
                int label = labels[primary][b][entry.first];
                timeline[entry.first - 1] = label < 0 ? '.' : characters.at(label);
            }
            line(out, input.targets[b].number, " |", timeline, "|");
        }
        line(out, "");
        line(out, "ospa ", filters[primary]);
        Lines ospa_grid(10, std::string(scans, ' '));
        for (int scan = 0; scan < scans; ++scan) {
            int height = int(std::floor(10 * ospa_values[primary][scan] / p.cutoff));
            for (int row = 0; row < 10; ++row)
                if (height >= 10 - row)
                    ospa_grid[row][scan] = '#';
        }
        frame(out, ospa_grid);
        return out;
    }
    static void save(const std::string &name, const Lines &lines) {
        std::ofstream output("output/" + name);
        for (const std::string &line : lines)
            output << line << '\n';
    }

  public:
    explicit Analysis(const Input &input)
        : input(input), p(input.params), scans(int(input.measurements.size()) - 1),
          primary(p.ca ? 1 : 0) {}
    void run() {
        tracking();
        compared_filters();
        scan_evaluation();
        match_tracks();
        errors();
        std::filesystem::create_directories("output");
        save("tracks.csv", track_rows);
        save("association_log.txt", log);
        Lines smoothed{"track,scan,x,y,vx,vy"};
        for (int index : evaluated) {
            const Track &track = tracks[index];
            for (int scan = track.birth; scan <= track.last_hit; ++scan) {
                const Estimate &x = track.estimates[4][scan];
                line(smoothed, track.number, ",", scan, ",", real(x[0]), ",", real(x[1]), ",",
                     real(x[2]), ",", real(x[3]));
            }
        }
        save("smoothed.csv", smoothed);
        save("evaluation.txt", evaluation_report());
        save("track_plot.txt", plots());
    }
};
int main() {
    Input input = read_inputs();
    Analysis analysis(input);
    analysis.run();
}
