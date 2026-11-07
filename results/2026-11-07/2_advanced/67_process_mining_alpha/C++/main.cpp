#include "mining.hpp"

static I sum(const std::vector<I> &values) {
    return std::accumulate(values.begin(), values.end(), I(0));
}
static Fraction mean(const std::vector<I> &values) { return {sum(values), I(values.size())}; }
static void append(Lines &to, const Lines &from) { to.insert(to.end(), from.begin(), from.end()); }
template <class K> static std::vector<K> ranked(const std::map<K, I> &counts) {
    std::vector<K> keys;
    for (const auto &entry : counts)
        keys.push_back(entry.first);
    std::sort(keys.begin(), keys.end(), [&](const K &a, const K &b) {
        return counts.at(a) != counts.at(b) ? counts.at(a) > counts.at(b) : a < b;
    });
    return keys;
}
static Names sorted_names(const std::set<std::string> &values) {
    return {values.begin(), values.end()};
}
struct Variant {
    Trace trace;
    std::vector<int> cases;
    bool keep;
};
struct Discovery {
    Net net;
    Names activities, starts, ends;
    std::vector<Candidate> pairs;
    I candidates = 0, causal = 0;
};
struct Exploration {
    I markings = 0, edges = 0, unsafe = 0, deadlocks = 0, stuck = 0;
    bool final = false;
    Names dead;
    Counts follows;
};
struct Prefix {
    I weight = 0;
    std::set<std::string> followers;
};
struct Study {
    Input input;
    Net reference;
    I minimum, limit, positive, kept_cases = 0, kept_events = 0;
    Fraction dependency_threshold, relative, loop1_threshold, loop2_threshold, and_threshold;
    Lines errors;
    std::vector<Event> events;
    std::vector<Case> cases;
    Names activities, resources;
    Log log, filtered;
    Counts counts;
    std::vector<Variant> variants;
    std::vector<int> variant_by_case;
    std::vector<Replay> reference_replays;
    std::vector<std::pair<std::string, Net>> nets;
    std::map<Trace, Prefix> prefixes;

    Fraction parameter(const std::string &name) const {
        const std::string &value = input.parameters.at(name);
        std::size_t slash = value.find('/');
        return {std::stoll(value.substr(0, slash)),
                slash == std::string::npos ? 1 : std::stoll(value.substr(slash + 1))};
    }
    Study() : input(read_inputs()), reference(read_model()) {
        minimum = std::stoll(input.parameters.at("filter_min_follows"));
        limit = std::stoll(input.parameters.at("sla_minutes"));
        positive = std::stoll(input.parameters.at("positive_observations"));
        dependency_threshold = parameter("dependency_threshold");
        relative = parameter("relative_to_best");
        loop1_threshold = parameter("loop1_threshold");
        loop2_threshold = parameter("loop2_threshold");
        and_threshold = parameter("and_threshold");
        std::set<std::tuple<std::string, std::string, std::string>> adopted;
        std::set<std::string> activity_names, resource_names;
        for (const Row &row : input.rows) {
            std::optional<I> time = timestamp_minutes(row.timestamp);
            if (!time) {
                line(errors, "ERROR line ", row.line, ": bad timestamp ", row.timestamp);
                continue;
            }
            if (!adopted.insert({row.case_id, row.activity, row.timestamp}).second) {
                line(errors, "ERROR line ", row.line, ": duplicate event ", row.case_id, " ",
                     row.activity, " ", row.timestamp);
                continue;
            }
            events.push_back(
                {row.line, row.case_id, row.activity, row.timestamp, row.resource, *time});
            activity_names.insert(row.activity);
            resource_names.insert(row.resource);
        }
        activities = sorted_names(activity_names);
        resources = sorted_names(resource_names);
        cases = group_cases(events);
        for (const Case &item : cases)
            log.push_back({item.trace, 1});
        counts = directly_follows(log);
    }
    void build_variants() {
        std::map<Trace, std::vector<int>> grouped;
        for (int i = 0; i < int(cases.size()); ++i)
            grouped[cases[i].trace].push_back(i);
        for (const auto &entry : grouped)
            variants.push_back({entry.first, entry.second, true});
        std::sort(variants.begin(), variants.end(), [](const Variant &a, const Variant &b) {
            return a.cases.size() != b.cases.size() ? a.cases.size() > b.cases.size()
                                                    : a.trace < b.trace;
        });
        variant_by_case.resize(cases.size());
        for (int i = 0; i < int(variants.size()); ++i) {
            Variant &v = variants[i];
            for (int j = 1; j < int(v.trace.size()); ++j)
                if (count(counts, v.trace[j - 1], v.trace[j]) < minimum)
                    v.keep = false;
            for (int c : v.cases)
                variant_by_case[c] = i + 1;
            if (v.keep) {
                filtered.push_back({v.trace, I(v.cases.size())});
                kept_cases += I(v.cases.size());
                kept_events += I(v.trace.size() * v.cases.size());
            }
        }
    }
    Lines summary() const {
        Lines out = errors;
        const Event &first =
            *std::min_element(events.begin(), events.end(),
                              [](const Event &a, const Event &b) { return a.time < b.time; });
        const Event &last =
            *std::max_element(events.begin(), events.end(),
                              [](const Event &a, const Event &b) { return a.time < b.time; });
        line(out, "LOG rows ", input.rows.size(), " adopted ", events.size(), " rejected ",
             errors.size(), " cases ", cases.size(), " activities ", activities.size(),
             " resources ", resources.size(), " first ", first.timestamp, " last ", last.timestamp);
        std::map<std::string, I> event_counts, case_counts, starts, ends, rework;
        std::map<std::string, std::vector<I>> waits;
        std::map<std::string, std::set<std::string>> workers;
        std::array<I, 7> weekday_events{}, weekday_starts{}, weekday_ends{};
        std::vector<I> lengths, durations;
        std::map<I, I> days;
        I late = 0;
        for (const Case &item : cases) {
            std::map<std::string, int> occurrences;
            for (const std::string &a : item.trace)
                ++occurrences[a];
            for (const auto &entry : occurrences) {
                ++case_counts[entry.first];
                if (entry.second >= 2)
                    ++rework[entry.first];
            }
            ++starts[item.trace.front()];
            ++ends[item.trace.back()];
            ++weekday_starts[(item.events.front().time / 1440 + 3) % 7];
            ++weekday_ends[(item.events.back().time / 1440 + 3) % 7];
            for (int i = 0; i < int(item.events.size()); ++i) {
                const Event &e = item.events[i];
                ++event_counts[e.activity];
                workers[e.activity].insert(e.resource);
                ++weekday_events[(e.time / 1440 + 3) % 7];
                if (i)
                    waits[e.activity].push_back(e.time - item.events[i - 1].time);
            }
            lengths.push_back(I(item.events.size()));
            durations.push_back(item.duration);
            ++days[item.duration / 1440];
            late += item.duration > limit;
        }
        for (const std::string &a : activities)
            line(out, "ACTIVITY ", a, " events ", event_counts[a], " cases ", case_counts[a],
                 " start ", starts[a], " end ", ends[a], " rework ", rework[a], " wait ",
                 waits[a].empty() ? "-" : fraction(mean(waits[a])), " resources ",
                 workers[a].size(), " model ", reference.transition_index(a) >= 0 ? "yes" : "no");
        for (const auto &entry : std::vector<std::pair<std::string, std::vector<I>>>{
                 {"LENGTH", lengths}, {"DURATION", durations}})
            line(out, entry.first, " min ",
                 *std::min_element(entry.second.begin(), entry.second.end()), " max ",
                 *std::max_element(entry.second.begin(), entry.second.end()), " mean ",
                 fraction(mean(entry.second)), " median ", fraction(median(entry.second)));
        for (I day = 0; day <= days.rbegin()->first; ++day)
            line(out, "DAYS ", day, " cases ", days[day], " share ",
                 percentage(days[day], I(cases.size())));
        line(out, "SLA limit ", limit, " late ", late, " share ",
             percentage(late, I(cases.size())));
        const Names weekdays = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
        for (int i = 0; i < 7; ++i)
            line(out, "WEEKDAY ", weekdays[i], " events ", weekday_events[i], " starts ",
                 weekday_starts[i], " ends ", weekday_ends[i]);
        return out;
    }
    Lines variant_report() const {
        Lines out;
        for (int i = 0; i < int(variants.size()); ++i) {
            const Variant &v = variants[i];
            I duration = 0, late = 0;
            for (int c : v.cases) {
                duration += cases[c].duration;
                late += cases[c].duration > limit;
            }
            int first = v.cases.front();
            line(out, "VARIANT ", i + 1, " count ", v.cases.size(), " share ",
                 percentage(I(v.cases.size()), I(cases.size())), " length ", v.trace.size(),
                 " first ", cases[first].id, " duration ", fraction({duration, I(v.cases.size())}),
                 " late ", late, " fitness ", fraction(reference_replays[first].fitness()), " ",
                 v.keep ? "KEEP" : "DROP", " ", names(v.trace));
        }
        line(out, "FILTER min_follows ", minimum, " variants ", filtered.size(), " of ",
             variants.size(), " cases ", kept_cases, " of ", cases.size(), " events ", kept_events,
             " of ", events.size());
        return out;
    }
    Lines dfg_report() const {
        std::map<std::string, I> starts, ends;
        std::map<std::string, std::vector<I>> durations;
        Counts edge_cases;
        std::map<NamePair, std::vector<I>> waits;
        for (const Case &c : cases) {
            ++starts[c.trace.front()];
            ++ends[c.trace.back()];
            durations[c.trace.back()].push_back(c.duration);
            std::set<NamePair> present;
            for (int i = 1; i < int(c.events.size()); ++i) {
                NamePair pair = {c.trace[i - 1], c.trace[i]};
                present.insert(pair);
                waits[pair].push_back(c.events[i].time - c.events[i - 1].time);
            }
            for (const NamePair &pair : present)
                ++edge_cases[pair];
        }
        Lines out;
        for (const std::string &a : ranked(starts))
            line(out, "START ", a, " count ", starts[a]);
        for (const std::string &a : ranked(ends))
            line(out, "END ", a, " count ", ends[a], " duration ", fraction(mean(durations[a])));
        for (const NamePair &pair : ranked(counts)) {
            const std::vector<I> &values = waits[pair];
            line(out, "EDGE ", pair.first, " ", pair.second, " count ", counts.at(pair), " cases ",
                 edge_cases[pair], " mean ", fraction(mean(values)), " min ",
                 *std::min_element(values.begin(), values.end()), " max ",
                 *std::max_element(values.begin(), values.end()));
        }
        append(out, footprint(activities, [&](const std::string &a, const std::string &b) {
                   return basic_relation(counts, a, b);
               }));
        return out;
    }
    Discovery discover(const Log &source, const Names &names, const Relation &relation) const {
        Discovery result;
        result.activities = names;
        std::set<Candidate> candidates;
        std::vector<Candidate> pending;
        for (int a = 0; a < int(names.size()); ++a)
            for (int b = 0; b < int(names.size()); ++b)
                if (relation(names[a], names[b]) == "->") {
                    ++result.causal;
                    if (relation(names[a], names[a]) == "#" &&
                        relation(names[b], names[b]) == "#") {
                        Candidate pair = {1u << a, 1u << b};
                        if (candidates.insert(pair).second)
                            pending.push_back(pair);
                    }
                }
        for (std::size_t i = 0; i < pending.size(); ++i)
            for (int a = 0; a < int(names.size()); ++a)
                for (int side = 0; side < 2; ++side) {
                    std::optional<Candidate> next =
                        extend_pair(pending[i], a, side, names, relation);
                    if (next && candidates.insert(*next).second)
                        pending.push_back(*next);
                }
        for (Candidate pair : candidates) {
            bool extension = false;
            for (int a = 0; a < int(names.size()); ++a)
                for (int side = 0; side < 2; ++side)
                    if (extend_pair(pair, a, side, names, relation))
                        extension = true;
            if (!extension)
                result.pairs.push_back(pair);
        }
        std::sort(result.pairs.begin(), result.pairs.end(), pair_order);
        result.candidates = I(candidates.size());
        std::set<std::string> starts, ends;
        for (const auto &entry : source) {
            starts.insert(entry.first.front());
            ends.insert(entry.first.back());
        }
        result.starts = sorted_names(starts);
        result.ends = sorted_names(ends);
        Names places = {"start"};
        std::set<NamePair> arcs;
        for (const std::string &a : result.starts)
            arcs.insert({"start", a});
        for (const std::string &a : result.ends)
            arcs.insert({a, "end"});
        for (int i = 0; i < int(result.pairs.size()); ++i) {
            std::string p = "p" + std::to_string(i + 1);
            places.push_back(p);
            for (const std::string &a : mask_names(result.pairs[i].first, names))
                arcs.insert({a, p});
            for (const std::string &b : mask_names(result.pairs[i].second, names))
                arcs.insert({p, b});
        }
        places.push_back("end");
        result.net = Net(places, names, arcs, "start", "end");
        return result;
    }
    static void pair_line(Lines &out, const Discovery &d) {
        line(out, "PAIRS causal ", d.causal, " candidates ", d.candidates, " maximal ",
             d.pairs.size());
    }
    static void net_lines(Lines &out, const Discovery &d) {
        line(out, "PLACE start - ", names(d.starts));
        for (int i = 0; i < int(d.pairs.size()); ++i)
            line(out, "PLACE p", i + 1, " ", names(mask_names(d.pairs[i].first, d.activities)), " ",
                 names(mask_names(d.pairs[i].second, d.activities)));
        line(out, "PLACE end ", names(d.ends), " -");
        const Net &net = d.net;
        for (int t = 0; t < int(net.transitions.size()); ++t) {
            Names in, out_names;
            for (int p : net.inputs[t])
                in.push_back(net.places[p]);
            for (int p : net.outputs[t])
                out_names.push_back(net.places[p]);
            line(out, "TRANSITION ", net.transitions[t], " in ", names(in), " out ",
                 names(out_names));
        }
        line(out, "NET places ", net.places.size(), " transitions ", net.transitions.size(),
             " arcs ", net.arcs.size());
    }
    Lines mine_workflows() {
        Counts filtered_counts = directly_follows(filtered);
        std::set<std::string> present;
        for (const auto &entry : filtered)
            present.insert(entry.first.begin(), entry.first.end());
        Names retained, loops, all = sorted_names(present);
        for (const std::string &a : all)
            (count(filtered_counts, a, a) > 0 ? loops : retained).push_back(a);
        Relation basic = [&](const std::string &a, const std::string &b) {
            return basic_relation(filtered_counts, a, b);
        };
        Discovery alpha = discover(filtered, all, basic);
        Lines out;
        line(out, "LOG variants ", filtered.size(), " cases ", kept_cases, " activities ",
             names(all));
        line(out, "LOOPS ", names(loops));
        line(out, "MINER alpha");
        append(out, footprint(all, basic));
        pair_line(out, alpha);
        net_lines(out, alpha);
        Log reduced;
        for (const auto &entry : filtered) {
            Trace trace;
            for (const std::string &a : entry.first)
                if (!std::binary_search(loops.begin(), loops.end(), a))
                    trace.push_back(a);
            reduced.push_back({trace, entry.second});
        }
        Counts reduced_counts = directly_follows(reduced), triangles = triangle_counts(reduced);
        Relation plus = [&](const std::string &a, const std::string &b) {
            return plus_relation(reduced_counts, triangles, a, b);
        };
        Discovery alpha_plus = discover(reduced, retained, plus);
        line(out, "MINER alpha_plus");
        for (const auto &entry : triangles)
            line(out, "TRIANGLE ", entry.first.first, " ", entry.first.second, " count ",
                 entry.second);
        append(out, footprint(retained, plus));
        pair_line(out, alpha_plus);
        std::set<NamePair> arcs = alpha_plus.net.arcs;
        for (const std::string &t : loops) {
            Candidate pair = {0, 0};
            for (int i = 0; i < int(retained.size()); ++i) {
                if (count(filtered_counts, retained[i], t))
                    pair.first |= 1u << i;
                if (count(filtered_counts, t, retained[i]))
                    pair.second |= 1u << i;
            }
            std::string place = "-";
            for (int i = 0; i < int(alpha_plus.pairs.size()); ++i)
                if (pair.first == alpha_plus.pairs[i].first &&
                    pair.second == alpha_plus.pairs[i].second) {
                    place = "p" + std::to_string(i + 1);
                    arcs.insert({place, t});
                    arcs.insert({t, place});
                    break;
                }
            line(out, "LOOP ", t, " before ", names(mask_names(pair.first, retained)), " after ",
                 names(mask_names(pair.second, retained)), " place ", place);
        }
        alpha_plus.net = Net(alpha_plus.net.places, all, arcs, "start", "end");
        net_lines(out, alpha_plus);
        nets = {{"reference", reference}, {"alpha", alpha.net}, {"alpha_plus", alpha_plus.net}};
        return out;
    }
    Lines heuristic_report() const {
        Lines out;
        Counts triangles = triangle_counts(log);
        std::set<std::string> loops1;
        std::set<NamePair> loops2, edges;
        for (const std::string &a : activities) {
            I n = count(counts, a, a);
            if (!n)
                continue;
            Fraction measure = loop_measure(n);
            bool accept = n >= positive && measure >= loop1_threshold;
            if (accept) {
                loops1.insert(a);
                edges.insert({a, a});
            }
            line(out, "L1 ", a, " count ", n, " measure ", fraction(measure), " ",
                 accept ? "ACCEPT" : "REJECT");
        }
        for (int a = 0; a < int(activities.size()); ++a)
            for (int b = a + 1; b < int(activities.size()); ++b) {
                const std::string &first = activities[a], &second = activities[b];
                I n = count(triangles, first, second) + count(triangles, second, first);
                if (!n || loops1.count(first) || loops1.count(second))
                    continue;
                Fraction measure = loop_measure(n);
                bool accept = n >= positive && measure >= loop2_threshold;
                if (accept)
                    loops2.insert({first, second});
                line(out, "L2 ", first, " ", second, " count ", n, " measure ", fraction(measure),
                     " ", accept ? "ACCEPT" : "REJECT");
            }
        std::map<NamePair, Fraction> measures;
        std::map<std::string, Fraction> best_out, best_in;
        for (const auto &entry : counts)
            if (entry.first.first != entry.first.second) {
                const std::string &a = entry.first.first, &b = entry.first.second;
                Fraction measure = dependency(counts, a, b);
                measures[entry.first] = measure;
                if (!best_out.count(a) || measure > best_out[a])
                    best_out[a] = measure;
                if (!best_in.count(b) || measure > best_in[b])
                    best_in[b] = measure;
            }
        for (const auto &entry : measures) {
            const std::string &a = entry.first.first, &b = entry.first.second;
            Fraction measure = entry.second;
            std::string verdict;
            NamePair unordered = a < b ? NamePair{a, b} : NamePair{b, a};
            if (loops2.count(unordered))
                verdict = "LOOP2";
            else if (count(counts, a, b) < positive)
                verdict = "REJECT_COUNT";
            else if (measure < dependency_threshold)
                verdict = "REJECT_MEASURE";
            else if (best_out[a] - measure > relative && best_in[b] - measure > relative)
                verdict = "REJECT_BEST";
            else
                verdict = "ACCEPT";
            if (verdict == "ACCEPT" || verdict == "LOOP2")
                edges.insert(entry.first);
            line(out, "DEP ", a, " ", b, " count ", count(counts, a, b), " reverse ",
                 count(counts, b, a), " measure ", fraction(measure), " ", verdict);
        }
        std::map<std::string, Names> inputs, outputs;
        for (const NamePair &edge : edges) {
            inputs[edge.second].push_back(edge.first);
            outputs[edge.first].push_back(edge.second);
        }
        for (const std::string &a : activities)
            line(out, "NODE ", a, " in ", names(inputs[a]), " out ", names(outputs[a]));
        for (const std::string &a : activities)
            for (int direction = 0; direction < 2; ++direction) {
                Names list = direction ? inputs[a] : outputs[a];
                list.erase(std::remove(list.begin(), list.end(), a), list.end());
                for (int b = 0; b < int(list.size()); ++b)
                    for (int c = b + 1; c < int(list.size()); ++c) {
                        Fraction measure = direction ? join_measure(counts, a, list[b], list[c])
                                                     : split_measure(counts, a, list[b], list[c]);
                        line(out, direction ? "JOIN " : "SPLIT ", a, " ", list[b], " ", list[c],
                             " measure ", fraction(measure), " ",
                             measure >= and_threshold ? "AND" : "XOR");
                    }
            }
        line(out, "GRAPH activities ", activities.size(), " edges ", edges.size(), " loops1 ",
             loops1.size(), " loops2 ", loops2.size());
        return out;
    }
    Exploration explore(const Net &net) const {
        Exploration result;
        std::vector<Marking> markings = {net.initial_marking()};
        std::map<Marking, int> index = {{markings[0], 0}};
        std::vector<std::vector<int>> enabled_at;
        std::vector<std::tuple<int, int, int>> edges;
        std::set<int> ever;
        for (int from = 0; from < int(markings.size()); ++from) {
            Marking before = markings[from];
            std::vector<int> enabled = net.enabled_transitions(before);
            enabled_at.push_back(enabled);
            if (enabled.empty() && before != net.final_marking())
                ++result.deadlocks;
            for (int t : enabled) {
                ever.insert(t);
                Marking after = net.fire(before, t);
                if (*std::max_element(after.begin(), after.end()) > 1) {
                    ++result.unsafe;
                    continue;
                }
                auto inserted = index.emplace(after, int(markings.size()));
                if (inserted.second)
                    markings.push_back(after);
                edges.push_back({from, t, inserted.first->second});
            }
        }
        std::vector<std::vector<int>> reverse(markings.size());
        for (const auto &edge : edges)
            reverse[std::get<2>(edge)].push_back(std::get<0>(edge));
        std::vector<bool> reaches(markings.size());
        std::vector<int> pending;
        auto final = index.find(net.final_marking());
        result.final = final != index.end();
        if (result.final) {
            pending.push_back(final->second);
            reaches[final->second] = true;
        }
        for (std::size_t i = 0; i < pending.size(); ++i)
            for (int before : reverse[pending[i]])
                if (!reaches[before]) {
                    reaches[before] = true;
                    pending.push_back(before);
                }
        result.markings = I(markings.size());
        result.edges = I(edges.size());
        result.stuck = I(markings.size() - pending.size());
        for (int t = 0; t < int(net.transitions.size()); ++t)
            if (!ever.count(t))
                result.dead.push_back(net.transitions[t]);
        for (const auto &edge : edges)
            for (int u : enabled_at[std::get<2>(edge)])
                result.follows[{net.transitions[std::get<1>(edge)], net.transitions[u]}] = 1;
        return result;
    }
    Lines precision_report(const std::string &name, const Net &net) const {
        I fitted = 0, allowed = 0, escaping = 0;
        std::map<std::string, I> escapes;
        for (const auto &entry : prefixes) {
            Marking marking = net.initial_marking();
            bool fit = true;
            for (const std::string &a : entry.first) {
                int t = net.transition_index(a);
                if (t < 0 || !net.enabled(marking, t)) {
                    fit = false;
                    break;
                }
                marking = net.fire(marking, t);
            }
            if (!fit)
                continue;
            ++fitted;
            for (int t : net.enabled_transitions(marking)) {
                allowed += entry.second.weight;
                if (!entry.second.followers.count(net.transitions[t])) {
                    escaping += entry.second.weight;
                    escapes[net.transitions[t]] += entry.second.weight;
                }
            }
        }
        Lines out;
        line(out, "PRECISION ", name, " prefixes ", fitted, " allowed ", allowed, " escaping ",
             escaping, " precision ",
             fraction(allowed ? Fraction(allowed - escaping, allowed) : Fraction(1)));
        for (const std::string &a : ranked(escapes))
            line(out, "ESCAPE ", name, " ", a, " weight ", escapes[a]);
        return out;
    }
    Replay replay(const Net &net, const Case &item) const {
        Replay result(int(net.places.size()));
        std::vector<std::deque<I>> tokens(net.places.size());
        tokens[net.initial].push_back(item.events.front().time);
        result.produced = 1;
        for (const Event &e : item.events) {
            int t = net.transition_index(e.activity);
            if (t < 0) {
                ++result.skipped;
                continue;
            }
            for (int p : net.inputs[t]) {
                ++result.consumed;
                if (tokens[p].empty()) {
                    ++result.missing;
                    ++result.place_missing[p];
                } else {
                    result.waiting[p].push_back(e.time - tokens[p].front());
                    tokens[p].pop_front();
                    ++result.routes[p][e.activity];
                }
            }
            for (int p : net.outputs[t]) {
                tokens[p].push_back(e.time);
                ++result.produced;
            }
        }
        ++result.consumed;
        if (tokens[net.final].empty()) {
            ++result.missing;
            ++result.place_missing[net.final];
        } else
            tokens[net.final].pop_front();
        for (int p = 0; p < int(net.places.size()); ++p) {
            result.place_remaining[p] = I(tokens[p].size());
            result.remaining += result.place_remaining[p];
            result.deviating[p] = result.place_missing[p] > 0 || !tokens[p].empty();
        }
        return result;
    }
    Lines conformance_report() {
        Lines out;
        line(out, "MODEL places ", reference.places.size(), " transitions ",
             reference.transitions.size(), " arcs ", reference.arcs.size());
        std::vector<Exploration> explored;
        for (const auto &entry : nets) {
            Exploration e = explore(entry.second);
            line(out, "REACHABILITY ", entry.first, " markings ", e.markings, " edges ", e.edges,
                 " unsafe ", e.unsafe, " deadlocks ", e.deadlocks, " stuck ", e.stuck, " final ",
                 e.final ? "yes" : "no", " dead ", names(e.dead), " sound ",
                 e.unsafe == 0 && e.stuck == 0 && e.dead.empty() ? "yes" : "no");
            explored.push_back(std::move(e));
        }
        for (int i = 0; i < int(nets.size()); ++i) {
            const std::string &name = nets[i].first;
            std::set<std::string> universe(activities.begin(), activities.end());
            universe.insert(nets[i].second.transitions.begin(), nets[i].second.transitions.end());
            I differing = 0;
            Lines differences;
            for (const std::string &a : universe)
                for (const std::string &b : universe) {
                    std::string observed = basic_relation(counts, a, b),
                                modeled = basic_relation(explored[i].follows, a, b);
                    if (observed != modeled) {
                        ++differing;
                        if (i == 0 && a <= b)
                            line(differences, "DIFF ", a, " ", b, " log ", observed, " model ",
                                 modeled);
                    }
                }
            I cells = I(universe.size() * universe.size());
            line(out, "FOOTPRINT ", name, " activities ", universe.size(), " cells ", cells,
                 " differing ", differing, " fitness ", fraction({cells - differing, cells}));
            append(out, differences);
        }
        for (const Case &item : cases)
            for (int n = 0; n <= int(item.trace.size()); ++n) {
                Trace prefix(item.trace.begin(), item.trace.begin() + n);
                Prefix &p = prefixes[prefix];
                ++p.weight;
                if (n < int(item.trace.size()))
                    p.followers.insert(item.trace[n]);
            }
        for (const auto &entry : nets)
            append(out, precision_report(entry.first, entry.second));
        for (int i = 0; i < int(nets.size()); ++i) {
            const std::string &name = nets[i].first;
            const Net &net = nets[i].second;
            Replay total(int(net.places.size()));
            I fitting = 0;
            for (const Case &item : cases) {
                Replay r = replay(net, item);
                if (i == 0)
                    reference_replays.push_back(r);
                fitting += r.missing == 0 && r.remaining == 0;
                total.missing += r.missing;
                total.remaining += r.remaining;
                total.consumed += r.consumed;
                total.produced += r.produced;
                total.skipped += r.skipped;
                for (int p = 0; p < int(net.places.size()); ++p) {
                    total.place_missing[p] += r.place_missing[p];
                    total.place_remaining[p] += r.place_remaining[p];
                    total.deviating[p] += r.deviating[p];
                    total.waiting[p].insert(total.waiting[p].end(), r.waiting[p].begin(),
                                            r.waiting[p].end());
                    for (const auto &entry : r.routes[p])
                        total.routes[p][entry.first] += entry.second;
                }
            }
            line(out, "REPLAY ", name, " cases ", cases.size(), " fitting ", fitting, " skipped ",
                 total.skipped, " missing ", total.missing, " remaining ", total.remaining,
                 " consumed ", total.consumed, " produced ", total.produced, " fitness ",
                 fraction(total.fitness()));
            for (int p = 0; p < int(net.places.size()); ++p) {
                const std::vector<I> &waiting = total.waiting[p];
                line(out, "PLACE ", name, " ", net.places[p], " missing ", total.place_missing[p],
                     " remaining ", total.place_remaining[p], " deviating ", total.deviating[p],
                     " tokens ", waiting.size(), " mean ",
                     waiting.empty() ? "-" : fraction(mean(waiting)), " max ",
                     waiting.empty()
                         ? "-"
                         : std::to_string(*std::max_element(waiting.begin(), waiting.end())));
            }
            for (int p = 0; p < int(net.places.size()); ++p)
                if (net.routes[p].size() >= 2) {
                    Names routes;
                    for (int t : net.routes[p])
                        routes.push_back(net.transitions[t] + "=" +
                                         std::to_string(total.routes[p][net.transitions[t]]));
                    line(out, "ROUTE ", name, " ", net.places[p], " ", names(routes));
                }
        }
        return out;
    }
    Lines conformance_csv() const {
        Lines out = {"case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness"};
        for (int i = 0; i < int(cases.size()); ++i) {
            const Replay &r = reference_replays[i];
            line(out, cases[i].id, ",", variant_by_case[i], ",", cases[i].events.size(), ",",
                 r.skipped, ",", r.missing, ",", r.remaining, ",", r.consumed, ",", r.produced, ",",
                 fraction(r.fitness()));
        }
        return out;
    }
    Lines resource_report() const {
        std::map<std::string, I> event_counts, case_counts;
        std::map<std::string, std::map<std::string, I>> work;
        Counts handovers, handover_cases, subcontract, together;
        for (const Case &item : cases) {
            std::set<std::string> workers;
            std::set<NamePair> present;
            for (int i = 0; i < int(item.events.size()); ++i) {
                const Event &e = item.events[i];
                workers.insert(e.resource);
                ++event_counts[e.resource];
                ++work[e.resource][e.activity];
                if (i) {
                    NamePair pair = {item.events[i - 1].resource, e.resource};
                    ++handovers[pair];
                    present.insert(pair);
                }
                if (i >= 2 && item.events[i - 2].resource == e.resource &&
                    item.events[i - 1].resource != e.resource)
                    ++subcontract[{e.resource, item.events[i - 1].resource}];
            }
            for (const std::string &worker : workers)
                ++case_counts[worker];
            for (auto a = workers.begin(); a != workers.end(); ++a)
                for (auto b = std::next(a); b != workers.end(); ++b)
                    ++together[{*a, *b}];
            for (const NamePair &p : present)
                ++handover_cases[p];
        }
        Lines out;
        for (int i = 0; i < int(resources.size()); ++i) {
            const std::string &r = resources[i];
            Names list;
            for (const auto &entry : work[r])
                list.push_back(entry.first + "=" + std::to_string(entry.second));
            line(out, "RESOURCE ", i + 1, " ", r, " events ", event_counts[r], " cases ",
                 case_counts[r], " work ", names(list));
        }
        for (const NamePair &p : ranked(handovers))
            if (p.first != p.second)
                line(out, "HANDOVER ", p.first, " ", p.second, " count ", handovers[p], " cases ",
                     handover_cases[p]);
        std::vector<Names> rows;
        for (const std::string &a : resources) {
            Names row;
            for (const std::string &b : resources)
                row.push_back(std::to_string(count(handovers, a, b)));
            rows.push_back(row);
        }
        append(out, table(rows, 5));
        for (const NamePair &p : ranked(subcontract))
            line(out, "SUBCONTRACT ", p.first, " ", p.second, " count ", subcontract[p]);
        for (const NamePair &p : ranked(together))
            line(out, "TOGETHER ", p.first, " ", p.second, " cases ", together[p]);
        I total = 0, own = 0;
        for (const auto &entry : handovers) {
            total += entry.second;
            if (entry.first.first == entry.first.second)
                own += entry.second;
        }
        line(out, "TOTAL handovers ", total, " self ", own, " other ", total - own);
        return out;
    }
    void run() {
        build_variants();
        Lines workflows = mine_workflows(), conformance = conformance_report();
        std::filesystem::create_directories("output");
        save("log_summary.txt", summary());
        save("variants.txt", variant_report());
        save("dfg.txt", dfg_report());
        save("alpha_net.txt", workflows);
        save("heuristic_net.txt", heuristic_report());
        save("conformance.csv", conformance_csv());
        save("conformance.txt", conformance);
        save("resources.txt", resource_report());
    }
};
int main() {
    Study study;
    study.run();
}
