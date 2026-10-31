#include "bayes.hpp"
static std::string real(double value) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(4) << value;
    return out.str() == "-0.0000" ? "0.0000" : out.str();
}
static const char *yes(bool value) { return value ? "yes" : "no"; }
static bool contains(const Vars &values, int variable) {
    return std::find(values.begin(), values.end(), variable) != values.end();
}
static Vars united(Vars a, const Vars &b) {
    a.insert(a.end(), b.begin(), b.end());
    std::sort(a.begin(), a.end());
    a.erase(std::unique(a.begin(), a.end()), a.end());
    return a;
}
static Vars difference(const Vars &a, const Vars &b) {
    Vars out;
    for (int variable : a)
        if (!contains(b, variable))
            out.push_back(variable);
    return out;
}
static Vars observed(const Evidence &evidence) {
    Vars out;
    for (const auto &entry : evidence)
        out.push_back(entry.first);
    std::sort(out.begin(), out.end());
    return out;
}
static void append(Lines &out, const Lines &other) {
    out.insert(out.end(), other.begin(), other.end());
}
static void block(Lines &out, const Lines &other) {
    if (!out.empty())
        out.push_back("");
    append(out, other);
}
static int variable_id(const Network &network, const std::string &name) {
    return int(std::find(network.names.begin(), network.names.end(), name) - network.names.begin());
}
struct Params {
    double alpha;
    bool given;
    Vars order;
    I limit, seed;
    std::vector<bool> sources;
};
static Params parameters(const Input &input) {
    Params out;
    out.alpha = std::stod(split(input.settings[0])[1]);
    out.given = split(input.settings[1])[1] == "GIVEN";
    Names order = split(input.settings[2]);
    for (int i = 1; i < int(order.size()); ++i)
        out.order.push_back(variable_id(input.network, order[i]));
    out.limit = std::stoll(split(input.settings[3])[1]);
    out.seed = std::stoll(split(input.settings[4])[1]);
    for (int i = 0; i < int(input.network.names.size()); ++i)
        out.sources.push_back(split(input.settings[5 + i])[2] == "GIVEN");
    return out;
}
struct SumResult {
    Factor distribution;
    double probability;
    std::array<std::vector<double>, 15> marginals;
};
struct Posterior {
    Vars relevant, eliminate;
    std::vector<Factor> initial;
    std::array<Plan, 2> plans;
    SumResult result{Factor{{}, {}, nullptr}, 0, {}};
};
struct Analysis {
    Input input;
    Network &network;
    Params p;
    Minstd random;
    int size;
    Vars variables, sizes, topological, depths;
    std::vector<Vars> children, ancestors, descendants, spouses, blankets;
    std::vector<Counts> counts;
    std::vector<CPT> learned, cpts;
    std::vector<double> likelihoods;
    std::vector<I> parameter_counts;
    std::vector<Factor> factors;
    std::map<std::pair<int, Vars>, double> family_scores;
    explicit Analysis(Input data)
        : input(std::move(data)), network(input.network), p(parameters(input)), random(p.seed),
          size(int(network.names.size())) {
        variables.resize(size);
        std::iota(variables.begin(), variables.end(), 0);
        for (const Names &states : network.states)
            sizes.push_back(int(states.size()));
        children.resize(size);
        for (int parent : variables)
            for (int child : variables)
                if (contains(network.parents[child], parent))
                    children[parent].push_back(child);
        std::array<bool, 15> selected{};
        while (int(topological.size()) < size) {
            for (int v : variables)
                if (!selected[v]) {
                    bool ready = true;
                    for (int parent : network.parents[v])
                        ready = ready && selected[parent];
                    if (ready) {
                        topological.push_back(v);
                        selected[v] = true;
                        break;
                    }
                }
        }
        depths.resize(size);
        for (int v : topological)
            for (int parent : network.parents[v])
                depths[v] = std::max(depths[v], depths[parent] + 1);
        for (int v : variables) {
            ancestors.push_back(closure(network.parents[v], network.parents));
            descendants.push_back(closure(children[v], children));
            Vars immediate = united(network.parents[v], children[v]), all_parents;
            for (int child : children[v])
                all_parents = united(all_parents, network.parents[child]);
            spouses.push_back(difference(difference(all_parents, immediate), {v}));
            blankets.push_back(united(immediate, spouses.back()));
            counts.push_back(count_samples(v, network.parents[v], input.samples, sizes));
            learned.push_back(learn(counts.back(), p.alpha));
            cpts.push_back(p.sources[v] ? *network.expert[v] : learned.back());
            likelihoods.push_back(log_likelihood(counts.back(), cpts.back()));
            parameter_counts.push_back(parameter_count(counts.back()));
            factors.push_back(cpt_factor(v, network.parents[v], cpts.back(), sizes));
        }
    }
    Vars closure(const Vars &initial, const std::vector<Vars> &links) const {
        std::array<bool, 15> reached{};
        Vars pending;
        for (int v : initial)
            if (!reached[v]) {
                reached[v] = true;
                pending.push_back(v);
            }
        while (!pending.empty()) {
            int v = pending.back();
            pending.pop_back();
            for (int neighbor : links[v])
                if (!reached[neighbor]) {
                    reached[neighbor] = true;
                    pending.push_back(neighbor);
                }
        }
        Vars out;
        for (int v : variables)
            if (reached[v])
                out.push_back(v);
        return out;
    }
    std::string sequence(const Vars &values) const {
        if (values.empty())
            return "-";
        std::string out;
        for (int v : values) {
            if (!out.empty())
                out += ' ';
            out += network.names[v];
        }
        return out;
    }
    std::string assignment_text(const Assignment &assignment, const Vars &scope) const {
        if (scope.empty())
            return "-";
        std::string out;
        for (int v : scope) {
            if (!out.empty())
                out += ' ';
            out += network.names[v] + "=" + network.states[v][assignment[v]];
        }
        return out;
    }
    Evidence evidence(const Names &fields) const {
        Evidence out;
        for (const std::string &field : fields) {
            std::size_t equal = field.find('=');
            int variable = variable_id(network, field.substr(0, equal));
            std::string state = field.substr(equal + 1);
            int value = int(
                std::find(network.states[variable].begin(), network.states[variable].end(), state) -
                network.states[variable].begin());
            out.push_back({variable, value});
        }
        return out;
    }
    std::pair<Vars, Evidence> query_parts(const Names &fields) const {
        auto separator = std::find(fields.begin(), fields.end(), "|");
        Vars query;
        for (auto at = fields.begin(); at != separator; ++at)
            query.push_back(variable_id(network, *at));
        Evidence values;
        if (separator != fields.end())
            values = evidence(Names(separator + 1, fields.end()));
        return {query, values};
    }
    std::array<Plan, 2> plans(const std::vector<Factor> &initial, const Vars &eliminate) const {
        return {make_plan(initial, eliminate, false, p.order, sizes),
                make_plan(initial, eliminate, true, p.order, sizes)};
    }
    SumResult sum_result(const std::vector<Factor> &initial, const Plan &plan,
                         const Vars &query) const {
        Factor factor = execute(initial, plan, sizes).final;
        double probability = total(factor.values);
        for (double &value : factor.values)
            value /= probability;
        SumResult out{factor, probability, {}};
        for (int v : query)
            out.marginals[v].resize(sizes[v]);
        for (I index = 0; index < I(factor.values.size()); ++index) {
            Assignment assignment = decode(index, factor.variables, sizes);
            for (int v : query)
                out.marginals[v][assignment[v]] += factor.values[std::size_t(index)];
        }
        return out;
    }
    Posterior posterior(const Vars &query, const Evidence &evidence) const {
        Posterior out;
        out.relevant = closure(united(query, observed(evidence)), network.parents);
        out.eliminate = difference(difference(out.relevant, query), observed(evidence));
        for (int v : out.relevant)
            out.initial.push_back(factors[v].reduced(evidence));
        out.plans = plans(out.initial, out.eliminate);
        out.result = sum_result(out.initial, out.plans[p.given ? 1 : 0], query);
        return out;
    }
    double joint(const Assignment &assignment, const Vars &scope) const {
        double probability = 1;
        for (int v : scope)
            probability *=
                cpts[v][parent_row(network.parents[v], assignment, sizes)][assignment[v]];
        return probability;
    }
    std::pair<I, std::string> query_enumeration(const Posterior &result, Vars query,
                                                const Evidence &evidence) const {
        Vars free = difference(result.relevant, observed(evidence));
        I count = entry_count(free, sizes);
        if (count > p.limit)
            return {count, "skipped"};
        std::sort(query.begin(), query.end());
        std::vector<double> values(std::size_t(entry_count(query, sizes)));
        Assignment initial{};
        for (const auto &entry : evidence)
            initial[entry.first] = entry.second;
        for (I index = 0; index < count; ++index) {
            Assignment assignment = decode(index, free, sizes, initial);
            values[parent_row(query, assignment, sizes)] += joint(assignment, result.relevant);
        }
        double probability = total(values);
        bool agreement =
            std::abs(std::log(probability) - std::log(result.result.probability)) <= 1e-9;
        for (int i = 0; i < int(values.size()); ++i)
            agreement = agreement && std::abs(values[i] / probability -
                                              result.result.distribution.values[i]) <= 1e-9;
        return {count, agreement ? "agree" : "disagree"};
    }
    Lines elimination_lines(const Vars &relevant, const Vars &eliminate,
                            const std::array<Plan, 2> &plans, bool agreement,
                            const std::pair<I, std::string> &enumeration) const {
        Lines out;
        line(out, "relevant ", sequence(relevant));
        line(out, "pruned ", sequence(difference(variables, relevant)));
        line(out, "eliminate ", sequence(eliminate));
        for (int method = 0; method < 2; ++method) {
            line(out, "order ", method ? "given" : "minfill");
            for (const Step &step : plans[method].steps)
                line(out, "step ", network.names[step.variable], " fill ", step.fill, " scope ",
                     sequence(step.scope), " entries ", step.size);
            line(out, "cost max ", plans[method].maximum, " total ", plans[method].total);
        }
        line(out, "used ", p.given ? "given" : "minfill");
        line(out, "orders_agree ", yes(agreement));
        line(out, "enumeration ", enumeration.first, " ", enumeration.second);
        return out;
    }
    Lines marginal_lines(const std::string &prefix, const Vars &query,
                         const std::array<std::vector<double>, 15> &marginals) const {
        Lines out;
        for (int v : query) {
            std::ostringstream row;
            row << prefix << ' ' << network.names[v];
            for (int state = 0; state < sizes[v]; ++state)
                row << ' ' << network.states[v][state] << ' ' << real(marginals[v][state]);
            out.push_back(row.str());
        }
        return out;
    }
    std::pair<Lines, Lines> answer_query(const Vars &query, const Evidence &evidence) const {
        Posterior result = posterior(query, evidence);
        Lines out;
        line(out, "log_evidence ", real(std::log(result.result.probability)));
        if (!evidence.empty()) {
            double conflict = 0;
            for (const auto &entry : evidence)
                conflict += std::log(posterior({}, Evidence{entry}).result.probability);
            conflict -= std::log(result.result.probability);
            line(out, "conflict ", real(conflict));
        }
        if (query.size() >= 2) {
            const Factor &distribution = result.result.distribution;
            for (I index = 0; index < I(distribution.values.size()); ++index)
                line(out, "joint ",
                     assignment_text(decode(index, distribution.variables, sizes),
                                     distribution.variables),
                     " ", real(distribution.values[std::size_t(index)]));
        }
        append(out, marginal_lines("marginal", query, result.result.marginals));
        for (int i = 0; i < int(evidence.size()); ++i) {
            Evidence reduced = evidence;
            reduced.erase(reduced.begin() + i);
            Posterior without = posterior(query, reduced);
            double shift = 0;
            for (int v : query)
                for (int state = 0; state < sizes[v]; ++state)
                    shift = std::max(shift, std::abs(result.result.marginals[v][state] -
                                                     without.result.marginals[v][state]));
            line(out, "drop ", network.names[evidence[i].first], "=",
                 network.states[evidence[i].first][evidence[i].second], " shift ", real(shift));
        }
        SumResult first = sum_result(result.initial, result.plans[0], query),
                  second = sum_result(result.initial, result.plans[1], query);
        bool agreement =
            std::abs(std::log(first.probability) - std::log(second.probability)) <= 1e-9;
        for (int i = 0; i < int(first.distribution.values.size()); ++i)
            agreement = agreement && std::abs(first.distribution.values[i] -
                                              second.distribution.values[i]) <= 1e-9;
        return {out, elimination_lines(result.relevant, result.eliminate, result.plans, agreement,
                                       query_enumeration(result, query, evidence))};
    }
    std::pair<Lines, Lines> answer_mpe(const Evidence &evidence) const {
        std::vector<Factor> initial;
        for (const Factor &factor : factors)
            initial.push_back(factor.reduced(evidence));
        Vars eliminate = difference(variables, observed(evidence));
        std::array<Plan, 2> orders = plans(initial, eliminate);
        std::array<double, 2> maxima{};
        std::array<Assignment, 2> assignments;
        for (int method = 0; method < 2; ++method) {
            Execution result = execute(initial, orders[method], sizes, true);
            maxima[method] = result.final.values[0];
            assignments[method] = traceback(result, sizes);
            for (const auto &entry : evidence)
                assignments[method][entry.first] = entry.second;
        }
        int method = p.given ? 1 : 0;
        double maximum = maxima[method],
               probability = evidence.empty() ? 1 : posterior({}, evidence).result.probability;
        const Assignment &assignment = assignments[method];
        Lines out;
        line(out, "assignment ", assignment_text(assignment, variables));
        line(out, "log_joint ", real(std::log(maximum)));
        line(out, "log_evidence ", real(std::log(probability)));
        line(out, "posterior ", real(maximum / probability));
        for (int v : eliminate) {
            Plan plan = make_plan(initial, difference(eliminate, {v}), p.given, p.order, sizes);
            Factor factor = execute(initial, plan, sizes, true).final;
            int alternative = -1;
            for (int state = 0; state < sizes[v]; ++state)
                if (state != assignment[v] &&
                    (alternative < 0 || factor.values[state] > factor.values[alternative]))
                    alternative = state;
            line(out, "margin ", network.names[v], " ", network.states[v][alternative], " ",
                 real(std::log(maximum) - std::log(factor.values[alternative])));
        }
        bool agreement = assignments[0] == assignments[1] &&
                         std::abs(std::log(maxima[0]) - std::log(maxima[1])) <= 1e-9;
        I count = entry_count(eliminate, sizes);
        std::string enumeration = "skipped";
        if (count <= p.limit) {
            double best = -1;
            Assignment best_assignment{}, initial_assignment{};
            for (const auto &entry : evidence)
                initial_assignment[entry.first] = entry.second;
            for (I index = 0; index < count; ++index) {
                Assignment candidate = decode(index, eliminate, sizes, initial_assignment);
                double value = joint(candidate, variables);
                if (value > best) {
                    best = value;
                    best_assignment = candidate;
                }
            }
            enumeration = best_assignment == assignment &&
                                  std::abs(std::log(best) - std::log(maximum)) <= 1e-9
                              ? "agree"
                              : "disagree";
        }
        return {out,
                elimination_lines(variables, eliminate, orders, agreement, {count, enumeration})};
    }
    std::pair<Lines, Lines> answer_sample(int number, const Vars &query, const Evidence &evidence,
                                          const std::vector<I> &counts) {
        auto exact = posterior(query, evidence).result.marginals;
        Lines out = marginal_lines("exact", query, exact), csv;
        std::array<std::vector<double>, 15> weights;
        for (int v : query)
            weights[v].resize(sizes[v]);
        double weight = 0, squared_weight = 0;
        int checkpoint = 0;
        for (I index = 1; index <= counts.back(); ++index) {
            auto generated =
                weighted_sample(topological, network.parents, cpts, sizes, evidence, random);
            weight += generated.second;
            squared_weight += generated.second * generated.second;
            for (int v : query)
                weights[v][generated.first[v]] += generated.second;
            if (index != counts[checkpoint])
                continue;
            double maximum_error = 0;
            for (int v : query)
                for (int state = 0; state < sizes[v]; ++state) {
                    double estimate = weights[v][state] / weight,
                           error = std::abs(estimate - exact[v][state]);
                    maximum_error = std::max(maximum_error, error);
                    line(csv, number, ",", index, ",", network.names[v], ",",
                         network.states[v][state], ",", real(estimate), ",", real(exact[v][state]),
                         ",", real(error));
                }
            line(out, "after ", index, " weight ", real(weight), " ess ",
                 real(weight * weight / squared_weight), " max_error ", real(maximum_error));
            ++checkpoint;
        }
        return {out, csv};
    }
    Lines answer_predict(int variable) const {
        int size = sizes[variable];
        std::vector<std::vector<I>> confusion(size, std::vector<I>(size));
        double log_likelihood = 0;
        for (const Assignment &sample : input.samples) {
            Assignment assignment = sample;
            std::vector<double> probabilities;
            for (int state = 0; state < size; ++state) {
                assignment[variable] = state;
                double value =
                    cpts[variable][parent_row(network.parents[variable], assignment, sizes)][state];
                for (int child : children[variable])
                    value *= cpts[child][parent_row(network.parents[child], assignment, sizes)]
                                 [assignment[child]];
                probabilities.push_back(value);
            }
            double denominator = total(probabilities);
            for (double &value : probabilities)
                value /= denominator;
            int predicted = 0;
            for (int state = 1; state < size; ++state)
                if (probabilities[state] > probabilities[predicted])
                    predicted = state;
            int actual = sample[variable];
            ++confusion[actual][predicted];
            log_likelihood += std::log(probabilities[actual]);
        }
        I correct = 0;
        for (int state = 0; state < size; ++state)
            correct += confusion[state][state];
        Lines out;
        line(out, "blanket ", sequence(blankets[variable]));
        line(out, "accuracy ", correct, "/", input.samples.size(), " ",
             real(double(correct) / double(input.samples.size())));
        line(out, "log_loss ", real(-log_likelihood / double(input.samples.size())));
        std::ostringstream heading;
        heading << "predicted";
        for (const std::string &state : network.states[variable])
            heading << ' ' << state;
        out.push_back(heading.str());
        for (int actual = 0; actual < size; ++actual) {
            std::ostringstream row;
            row << "actual " << network.states[variable][actual];
            for (I count : confusion[actual])
                row << ' ' << count;
            out.push_back(row.str());
        }
        return out;
    }
    Vars reachable(Vars x, Vars z) const {
        std::sort(x.begin(), x.end());
        std::sort(z.begin(), z.end());
        Vars ancestors = closure(z, network.parents);
        std::array<std::array<bool, 2>, 15> visited{};
        std::deque<std::pair<int, int>> pending;
        for (int v : x) {
            visited[v][0] = true;
            pending.push_back({v, 0});
        }
        auto add = [&](int v, int direction) {
            if (!visited[v][direction]) {
                visited[v][direction] = true;
                pending.push_back({v, direction});
            }
        };
        while (!pending.empty()) {
            auto position = pending.front();
            pending.pop_front();
            int v = position.first, direction = position.second;
            if (direction == 0 && !contains(z, v)) {
                for (int parent : network.parents[v])
                    add(parent, 0);
                for (int child : children[v])
                    add(child, 1);
            } else if (direction == 1) {
                if (!contains(z, v))
                    for (int child : children[v])
                        add(child, 1);
                if (contains(ancestors, v))
                    for (int parent : network.parents[v])
                        add(parent, 0);
            }
        }
        Vars out;
        for (int v : variables)
            if ((visited[v][0] || visited[v][1]) && !contains(x, v) && !contains(z, v))
                out.push_back(v);
        return out;
    }
    std::tuple<double, double, I> mutual_information(const Vars &x, const Vars &y, Vars z) const {
        std::sort(z.begin(), z.end());
        Vars scope = united(united(x, y), z), xz = united(x, z), yz = united(y, z);
        std::map<I, I> count_scope, count_xz, count_yz, count_z;
        for (const Assignment &sample : input.samples) {
            ++count_scope[parent_row(scope, sample, sizes)];
            ++count_xz[parent_row(xz, sample, sizes)];
            ++count_yz[parent_row(yz, sample, sizes)];
            ++count_z[parent_row(z, sample, sizes)];
        }
        double information = 0;
        for (const auto &entry : count_scope) {
            Assignment assignment = decode(entry.first, scope, sizes);
            I observed = entry.second, nxz = count_xz.at(parent_row(xz, assignment, sizes)),
              nyz = count_yz.at(parent_row(yz, assignment, sizes)),
              nz = count_z.at(parent_row(z, assignment, sizes));
            double argument = double(observed * nz) / double(nxz * nyz);
            information += (double(observed) / double(input.samples.size())) * std::log(argument);
        }
        I degrees =
            (entry_count(x, sizes) - 1) * (entry_count(y, sizes) - 1) * entry_count(z, sizes);
        return {information, 2 * double(input.samples.size()) * information, degrees};
    }
    Lines answer_dsep(const std::vector<Vars> &groups) const {
        const Vars &x = groups[0], &y = groups[1];
        Vars z = groups.size() == 3 ? groups[2] : Vars{};
        Vars reached = reachable(x, z);
        bool separated = true;
        for (int v : y)
            if (contains(reached, v))
                separated = false;
        auto statistics = mutual_information(x, y, z);
        Lines out;
        line(out, "result ", separated ? "separated" : "connected");
        line(out, "reachable ", sequence(reached));
        line(out, "data cmi ", real(std::get<0>(statistics)), " g2 ", real(std::get<1>(statistics)),
             " df ", std::get<2>(statistics));
        return out;
    }
    Lines answer_blanket(int variable) const {
        Vars rest = difference(variables, united(blankets[variable], {variable})),
             reached = reachable({variable}, blankets[variable]);
        bool separated = true;
        for (int v : rest)
            if (contains(reached, v))
                separated = false;
        Lines out;
        line(out, "parents ", sequence(network.parents[variable]));
        line(out, "children ", sequence(children[variable]));
        line(out, "spouses ", sequence(spouses[variable]));
        line(out, "blanket ", sequence(blankets[variable]));
        line(out, "rest ", sequence(rest));
        line(out, "rest_separated ", yes(separated));
        return out;
    }
    std::optional<Vars> path(int start, int finish,
                             std::optional<std::pair<int, int>> ignored = {}) const {
        std::array<bool, 15> visited{};
        std::array<int, 15> previous{};
        previous.fill(-1);
        visited[start] = true;
        std::deque<int> pending = {start};
        while (!pending.empty()) {
            int v = pending.front();
            pending.pop_front();
            for (int child : children[v]) {
                if ((ignored && *ignored == std::make_pair(v, child)) || visited[child])
                    continue;
                visited[child] = true;
                previous[child] = v;
                if (child == finish) {
                    Vars result;
                    for (int at = finish; at >= 0; at = previous[at])
                        result.push_back(at);
                    std::reverse(result.begin(), result.end());
                    return result;
                }
                pending.push_back(child);
            }
        }
        return {};
    }
    double family(int variable, Vars parents) {
        std::sort(parents.begin(), parents.end());
        auto key = std::make_pair(variable, parents);
        auto entry = family_scores.find(key);
        if (entry == family_scores.end())
            entry =
                family_scores
                    .emplace(key, family_score(variable, parents, input.samples, sizes, p.alpha))
                    .first;
        return entry->second;
    }
    Lines answer_edge(const std::string &operation, int x, int y) {
        bool exists = contains(network.parents[y], x);
        if (operation == "ADD" && exists)
            return {"result exists"};
        if (operation != "ADD" && !exists)
            return {"result missing"};
        std::optional<Vars> cycle;
        if (operation == "ADD") {
            auto route = path(y, x);
            if (route) {
                cycle = Vars{x};
                cycle->insert(cycle->end(), route->begin(), route->end());
            }
        } else if (operation == "REVERSE") {
            auto route = path(x, y, std::make_pair(x, y));
            if (route) {
                cycle = Vars{y};
                cycle->insert(cycle->end(), route->begin(), route->end());
            }
        }
        if (cycle) {
            std::ostringstream row;
            row << "result cycle ";
            for (int i = 0; i < int(cycle->size()); ++i) {
                if (i)
                    row << " -> ";
                row << network.names[(*cycle)[i]];
            }
            return {row.str()};
        }
        double before_y = family(y, network.parents[y]);
        Vars parents_y = operation == "ADD" ? united(network.parents[y], {x})
                                            : difference(network.parents[y], {x});
        double after_y = family(y, parents_y), change = after_y - before_y;
        Lines out = {"result ok"};
        line(out, "family ", network.names[y], " before ", real(before_y), " after ",
             real(after_y));
        if (operation == "REVERSE") {
            double before_x = family(x, network.parents[x]),
                   after_x = family(x, united(network.parents[x], {y}));
            change = (after_y - before_y) + (after_x - before_x);
            line(out, "family ", network.names[x], " before ", real(before_x), " after ",
                 real(after_x));
        }
        line(out, "delta ", real(change), " ", change > 0 ? "improves" : "worsens");
        return out;
    }
    Lines cpt_lines() const {
        Lines out;
        for (int v : variables) {
            line(out, "variable ", network.names[v], " source ",
                 p.sources[v] ? "GIVEN" : "LEARNED");
            std::ostringstream states;
            states << "states";
            for (const std::string &state : network.states[v])
                states << ' ' << state;
            out.push_back(states.str());
            line(out, "parents ", sequence(network.parents[v]));
            for (int r = 0; r < int(counts[v].size()); ++r) {
                Assignment assignment = decode(r, network.parents[v], sizes);
                std::ostringstream row;
                row << "row " << assignment_text(assignment, network.parents[v]) << " counts";
                for (I count : counts[v][r])
                    row << ' ' << count;
                row << " probs";
                for (double probability : cpts[v][r])
                    row << ' ' << real(probability);
                out.push_back(row.str());
            }
            double bic = likelihoods[v] -
                         double(parameter_counts[v]) * std::log(double(input.samples.size())) / 2;
            line(out, "loglik ", real(likelihoods[v]), " parameters ", parameter_counts[v], " bic ",
                 real(bic));
            Posterior model = posterior({v}, {});
            std::ostringstream marginal;
            marginal << "marginal model";
            for (double value : model.result.marginals[v])
                marginal << ' ' << real(value);
            marginal << " data";
            for (int state = 0; state < sizes[v]; ++state) {
                I count = 0;
                for (const std::vector<I> &row : counts[v])
                    count += row[state];
                marginal << ' ' << real(double(count) / double(input.samples.size()));
            }
            out.push_back(marginal.str());
            if (!p.sources[v]) {
                std::string difference = "-";
                if (network.expert[v]) {
                    double maximum = 0;
                    for (int r = 0; r < int(learned[v].size()); ++r)
                        for (int state = 0; state < sizes[v]; ++state)
                            maximum = std::max(maximum, std::abs(learned[v][r][state] -
                                                                 (*network.expert[v])[r][state]));
                    difference = real(maximum);
                }
                line(out, "given_difference ", difference);
            }
            out.push_back("");
        }
        double likelihood = total(likelihoods);
        I parameters = std::accumulate(parameter_counts.begin(), parameter_counts.end(), I(0));
        double bic = likelihood - double(parameters) * std::log(double(input.samples.size())) / 2;
        line(out, "network samples ", input.samples.size(), " pseudocount ", real(p.alpha),
             " loglik ", real(likelihood), " parameters ", parameters, " bic ", real(bic));
        return out;
    }
    Lines structure_summary() const {
        auto orders = plans(factors, variables);
        std::array<int, 2> widths{};
        for (int method = 0; method < 2; ++method)
            for (const Step &step : orders[method].steps)
                widths[method] = std::max(widths[method], int(step.scope.size()) - 1);
        Graph graph = interaction_graph(factors);
        int moral_edges = 0, edges = 0;
        Vars roots, leaves;
        for (int v : variables) {
            edges += int(network.parents[v].size());
            if (network.parents[v].empty())
                roots.push_back(v);
            if (children[v].empty())
                leaves.push_back(v);
            for (int w = v + 1; w < size; ++w)
                moral_edges += graph.adjacent[v][w];
        }
        Lines out;
        line(out, "variables ", size, " edges ", edges);
        line(out, "topological_order ", sequence(topological));
        line(out, "roots ", sequence(roots));
        line(out, "leaves ", sequence(leaves));
        line(out, "moral_edges ", moral_edges, " width minfill ", widths[0], " given ", widths[1]);
        for (int v : variables)
            line(out, "variable ", network.names[v], " states ", sizes[v], " parents ",
                 network.parents[v].size(), " children ", children[v].size(), " depth ", depths[v],
                 " ancestors ", ancestors[v].size(), " descendants ", descendants[v].size(),
                 " blanket ", blankets[v].size());
        return out;
    }
    static void save(const std::string &name, const Lines &lines) {
        std::ofstream out("output/" + name);
        for (const std::string &line : lines)
            out << line << '\n';
    }
    void run() {
        Lines cpts = cpt_lines(), answers, elimination, structure = structure_summary(),
              sampling = {"query,samples,variable,state,estimate,exact,abs_error"};
        for (int index = 0; index < int(input.queries.size()); ++index) {
            const std::string &query_line = input.queries[index];
            Names fields = split(query_line);
            std::string kind = fields[0];
            fields.erase(fields.begin());
            Lines heading;
            line(heading, "query ", index + 1, " ", query_line);
            if (kind == "QUERY") {
                auto parts = query_parts(fields);
                auto result = answer_query(parts.first, parts.second);
                Lines answer = heading, steps = heading;
                append(answer, result.first);
                append(steps, result.second);
                block(answers, answer);
                block(elimination, steps);
            } else if (kind == "MPE") {
                auto result = answer_mpe(evidence(fields));
                Lines answer = heading, steps = heading;
                append(answer, result.first);
                append(steps, result.second);
                block(answers, answer);
                block(elimination, steps);
            } else if (kind == "SAMPLE") {
                auto counts_at = std::find(fields.begin(), fields.end(), "COUNTS");
                auto parts = query_parts(Names(fields.begin(), counts_at));
                std::vector<I> counts;
                for (auto at = counts_at + 1; at != fields.end(); ++at)
                    counts.push_back(std::stoll(*at));
                auto result = answer_sample(index + 1, parts.first, parts.second, counts);
                Lines answer = heading;
                append(answer, result.first);
                block(answers, answer);
                append(sampling, result.second);
            } else if (kind == "PREDICT") {
                Lines answer = heading;
                append(answer, answer_predict(variable_id(network, fields[0])));
                block(answers, answer);
            } else {
                Lines result;
                if (kind == "DSEP") {
                    std::vector<Vars> groups(1);
                    for (const std::string &field : fields) {
                        if (field == "|")
                            groups.emplace_back();
                        else
                            groups.back().push_back(variable_id(network, field));
                    }
                    result = answer_dsep(groups);
                } else if (kind == "BLANKET")
                    result = answer_blanket(variable_id(network, fields[0]));
                else
                    result = answer_edge(fields[0], variable_id(network, fields[1]),
                                         variable_id(network, fields[2]));
                append(heading, result);
                block(structure, heading);
            }
        }
        std::filesystem::create_directories("output");
        save("cpts.txt", cpts);
        save("structure.txt", structure);
        save("answers.txt", answers);
        save("elimination.txt", elimination);
        save("sampling.csv", sampling);
    }
};
int main() {
    Analysis analysis(read_inputs());
    analysis.run();
}
