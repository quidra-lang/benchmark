#include "truss.hpp"

static std::string real(double value, int digits = 4) {
    std::ostringstream stream;
    stream << std::fixed << std::setprecision(digits) << value;
    std::string text = stream.str();
    if (text[0] == '-' && std::stod(text) == 0)
        text.erase(0, 1);
    return text;
}
static double rounded(double value) { return std::stod(real(value)); }
static int extreme(const Vector &values, bool minimum = false) {
    int chosen = 0;
    double best = rounded(values[0]);
    for (int i = 1; i < int(values.size()); ++i) {
        double value = rounded(values[i]);
        if (minimum ? value < best : value > best) {
            chosen = i;
            best = value;
        }
    }
    return chosen;
}
static void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream file("output/" + name);
    for (const std::string &text : lines)
        file << text << '\n';
}
struct System {
    std::vector<Properties> properties;
    Matrix matrix, free_matrix, lower;
    std::optional<int> unstable;
    int removed;
};
struct Canvas {
    int x0, y1, horizontal, vertical, width, height;
    Names grid;
    Canvas(const std::vector<Node> &nodes, int wc, int hc) : horizontal(wc), vertical(hc) {
        x0 = nodes[0].x;
        y1 = nodes[0].y;
        int x1 = x0, y0 = y1;
        for (const Node &node : nodes) {
            x0 = std::min(x0, node.x);
            x1 = std::max(x1, node.x);
            y0 = std::min(y0, node.y);
            y1 = std::max(y1, node.y);
        }
        width = int(std::floor(double(x1 - x0) / wc + 0.5)) + 5;
        height = int(std::floor(double(y1 - y0) / hc + 0.5)) + 5;
        grid = Names(height, std::string(width, ' '));
    }
    std::pair<int, int> position(double x, double y) const {
        return {int(std::floor((x - x0) / horizontal + 0.5)) + 2,
                int(std::floor((y1 - y) / vertical + 0.5)) + 2};
    }
    void put(std::pair<int, int> point, char character) {
        if (point.first >= 0 && point.first < width && point.second >= 0 && point.second < height)
            grid[point.second][point.first] = character;
    }
    void segment(std::pair<int, int> first, std::pair<int, int> last, char character) {
        int c = first.first, r = first.second;
        int dc = std::abs(last.first - c), dr = -std::abs(last.second - r);
        int sc = c < last.first ? 1 : -1, sr = r < last.second ? 1 : -1, error = dc + dr;
        for (;;) {
            put({c, r}, character);
            if (c == last.first && r == last.second)
                break;
            int twice = 2 * error;
            if (twice >= dr) {
                error += dr;
                c += sc;
            }
            if (twice <= dc) {
                error += dc;
                r += sr;
            }
        }
    }
    void append_frame(Lines &out) const {
        std::string border = "+" + std::string(width, '-') + "+";
        out.push_back(border);
        for (const std::string &row : grid)
            out.push_back("|" + row + "|");
        out.push_back(border);
    }
};
class Truss {
    Model model;
    int degrees;
    Indices order, numbers, free, restrained, choices, governing_cases;
    std::vector<std::set<int>> neighbors;
    std::vector<std::array<int, 2>> node_dofs, owners;
    std::vector<std::array<int, 3>> support_directions;
    Vector prescribed, limits, governing;
    Matrix uses;
    std::vector<Geometry> geometry;
    Names group_names;
    std::vector<Indices> group_members;
    System final_system;
    std::vector<Result> results, combinations;
    std::map<int, Result> units;
    double weight = 0;
    Lines history;

    System system(int removed = -1) const {
        System out;
        out.properties = member_properties(model, choices, geometry);
        out.matrix = assemble(geometry, out.properties, degrees, removed);
        for (int row : free) {
            Vector values;
            for (int column : free)
                values.push_back(out.matrix[row][column]);
            out.free_matrix.push_back(values);
        }
        Cholesky factorization = cholesky(out.free_matrix, free);
        out.lower = std::move(factorization.lower);
        out.unstable = factorization.unstable;
        out.removed = removed;
        return out;
    }
    Vector displacement(const System &structure, const Vector &force,
                        bool settlement = false) const {
        Vector out(degrees), right;
        for (int degree : restrained)
            out[degree] = settlement ? prescribed[degree] : 0;
        for (int degree : free) {
            double value = force[degree];
            for (int fixed : restrained)
                value -= structure.matrix[degree][fixed] * out[fixed];
            right.push_back(value);
        }
        Vector solution = solve(structure.lower, right);
        for (int i = 0; i < int(free.size()); ++i)
            out[free[i]] = solution[i];
        return out;
    }
    Result case_result(const System &structure, const LoadCase &load_case) const {
        Loading loading = load_vectors(load_case, geometry, structure.properties, node_dofs,
                                       degrees, structure.removed);
        Vector motion = displacement(structure, loading.total, loading.settlement);
        return {load_case.name, motion,
                axial_forces(geometry, structure.properties, motion, loading.temperature,
                             structure.removed),
                reactions(structure.matrix, motion, loading.total, restrained), loading.external};
    }
    std::vector<Result> analyze(const System &structure) const {
        std::vector<Result> out;
        for (const LoadCase &load_case : model.cases)
            out.push_back(case_result(structure, load_case));
        for (const Combination &combination : model.combinations)
            out.push_back(superpose(combination, out));
        return out;
    }
    Result removal_result(const System &structure, const Combination &combination) const {
        std::vector<Result> cases(model.cases.size());
        std::set<int> needed;
        for (const auto &term : combination.terms)
            needed.insert(term.first);
        for (int i = 0; i < int(model.cases.size()); ++i)
            if (needed.count(i))
                cases[i] = case_result(structure, model.cases[i]);
        return superpose(combination, cases);
    }
    const Result &result(const std::string &name) const {
        for (const Result &item : results)
            if (item.name == name)
                return item;
        return results[0];
    }
    const Result &unit_result(int node) {
        auto found = units.find(node);
        if (found != units.end())
            return found->second;
        Vector force(degrees);
        force[node_dofs[node][1]] = -1000;
        Vector motion = displacement(final_system, force);
        Result unit{
            "unit", motion,
            axial_forces(geometry, final_system.properties, motion, Vector(model.members.size())),
            reactions(final_system.matrix, motion, force, restrained), force};
        return units.emplace(node, std::move(unit)).first->second;
    }
    Vector magnitudes(const Result &item) const {
        Vector out;
        for (const auto &dofs : node_dofs) {
            double x = item.displacement[dofs[0]], y = item.displacement[dofs[1]];
            out.push_back(std::sqrt(x * x + y * y));
        }
        return out;
    }
    std::pair<int, int> metrics(const Indices &mapping) const {
        int bandwidth = 0, profile = 0;
        for (const Member &member : model.members)
            bandwidth = std::max(bandwidth, std::abs(mapping[member.start] - mapping[member.end]));
        for (int i = 0; i < int(model.nodes.size()); ++i) {
            int low = mapping[i];
            for (int adjacent : neighbors[i])
                low = std::min(low, mapping[adjacent]);
            profile += mapping[i] - low;
        }
        return {bandwidth, profile};
    }
    void design_sections() {
        int last_round = 0;
        bool converged = false;
        for (int round = 1; round <= 10; ++round) {
            last_round = round;
            final_system = system();
            results = analyze(final_system);
            combinations.assign(results.begin() + model.cases.size(), results.end());
            limits.clear();
            uses.clear();
            Vector all_uses;
            weight = 0;
            for (int m = 0; m < int(model.members.size()); ++m) {
                limits.push_back(slenderness_limit(m, combinations,
                                                   model.settings.compression_limit,
                                                   model.settings.tension_limit));
                Vector member_uses;
                for (const Result &combination : combinations) {
                    double value =
                        utilization(combination.forces[m], final_system.properties[m], geometry[m]);
                    member_uses.push_back(value);
                    all_uses.push_back(value);
                }
                uses.push_back(member_uses);
                weight += member_weight(final_system.properties[m], geometry[m]);
            }
            Indices next;
            std::vector<std::array<int, 3>> changes;
            for (int group = 0; group < int(group_names.size()); ++group) {
                int selected =
                    select_section(group_members[group], model.sections, final_system.properties,
                                   geometry, combinations, limits);
                next.push_back(selected);
                int current = choices[group_members[group][0]];
                if (selected != current)
                    changes.push_back({group, current, selected});
            }
            int maximum = extreme(all_uses), member = maximum / int(combinations.size()),
                combination = maximum % int(combinations.size());
            line(history, "round ", round, " weight ", real(weight / 1000), " max_utilization ",
                 real(all_uses[maximum]), " at ", model.members[member].id, " ",
                 combinations[combination].name, " changes ", changes.size());
            for (const auto &change : changes) {
                Vector values;
                for (int m : group_members[change[0]])
                    for (double value : uses[m])
                        values.push_back(value);
                line(history, "change ", group_names[change[0]], " ",
                     model.sections[change[1]].name, " ", model.sections[change[2]].name,
                     " utilization ", real(values[extreme(values)]));
            }
            if (changes.empty()) {
                converged = true;
                break;
            }
            if (round == 10)
                break;
            for (int group = 0; group < int(group_names.size()); ++group)
                for (int m : group_members[group])
                    choices[m] = next[group];
        }
        line(history, "result ", converged ? "converged" : "not_converged", " rounds ", last_round);
        for (const Vector &values : uses) {
            int chosen = extreme(values);
            governing_cases.push_back(chosen);
            governing.push_back(values[chosen]);
        }
    }
    Lines design_report() const {
        Lines out = history;
        for (int group = 0; group < int(group_names.size()); ++group) {
            Vector values;
            for (int m : group_members[group])
                values.push_back(governing[m]);
            int m = group_members[group][extreme(values)];
            line(out, "group ", group_names[group], " section ", model.sections[choices[m]].name,
                 " members ", group_members[group].size(), " utilization ", real(governing[m]),
                 " at ", model.members[m].id);
        }
        for (int m = 0; m < int(model.members.size()); ++m) {
            double ratio = slenderness(final_system.properties[m], geometry[m]);
            line(out, "member ", model.members[m].id, " group ", model.members[m].group,
                 " section ", model.sections[choices[m]].name, " utilization ", real(governing[m]),
                 " governing ", combinations[governing_cases[m]].name, " slenderness ", real(ratio),
                 " limit ", real(limits[m]), " ",
                 governing[m] <= 1 && ratio <= limits[m] ? "ok" : "over");
        }
        Indices rank(model.members.size());
        std::iota(rank.begin(), rank.end(), 0);
        std::stable_sort(rank.begin(), rank.end(), [&](int a, int b) {
            return rounded(governing[a]) > rounded(governing[b]);
        });
        for (int i = 0; i < std::min(5, int(rank.size())); ++i)
            line(out, "rank ", i + 1, " member ", model.members[rank[i]].id, " utilization ",
                 real(governing[rank[i]]));
        for (int m = 0; m < int(model.members.size()); ++m) {
            Vector values;
            for (const Result &combination : combinations)
                values.push_back(combination.forces[m] / 1000);
            int high = extreme(values), low = extreme(values, true);
            line(out, "envelope ", model.members[m].id, " max ", real(values[high]), " ",
                 combinations[high].name, " min ", real(values[low]), " ", combinations[low].name);
        }
        for (int section = 0; section < int(model.sections.size()); ++section) {
            int count = 0;
            double length = 0;
            for (int m = 0; m < int(model.members.size()); ++m)
                if (choices[m] == section) {
                    ++count;
                    length += geometry[m].length;
                }
            if (count)
                line(out, "section ", model.sections[section].name, " members ", count, " length ",
                     real(length));
        }
        line(out, "weight ", real(weight / 1000));
        return out;
    }
    Lines analysis_report() {
        Lines out;
        line(out, "model nodes ", model.nodes.size(), " members ", model.members.size(),
             " supports ", model.supports.size(), " free_dofs ", free.size(), " restrained_dofs ",
             restrained.size(), " indeterminacy ",
             int(model.members.size() + restrained.size()) - degrees);
        std::ostringstream sequence;
        sequence << "renumbering";
        for (int node : order)
            sequence << ' ' << model.nodes[node].id;
        out.push_back(sequence.str());
        Indices original(model.nodes.size());
        std::iota(original.begin(), original.end(), 0);
        auto before = metrics(original), after = metrics(numbers);
        line(out, "bandwidth before ", before.first, " after ", after.first);
        line(out, "profile before ", before.second, " after ", after.second);
        for (int m = 0; m < int(model.members.size()); ++m) {
            const Member &member = model.members[m];
            const Geometry &g = geometry[m];
            line(out, "member ", member.id, " nodes ", model.nodes[member.start].id, " ",
                 model.nodes[member.end].id, " length ", real(g.length), " cos ", real(g.cosine, 6),
                 " sin ", real(g.sine, 6));
        }
        for (int index = 0; index < int(results.size()); ++index) {
            const Result &item = results[index];
            Vector moves = magnitudes(item);
            int chosen = extreme(moves);
            double energy = 0, scale = 1;
            std::array<double, 2> reaction{}, external{};
            for (int m = 0; m < int(model.members.size()); ++m) {
                const Properties &p = final_system.properties[m];
                energy +=
                    item.forces[m] * item.forces[m] * geometry[m].length / (2 * p.young * p.area);
            }
            for (const auto &dofs : node_dofs)
                for (int axis = 0; axis < 2; ++axis) {
                    int degree = dofs[axis];
                    reaction[axis] += item.reactions[degree];
                    external[axis] += item.external[degree];
                    scale = std::max(scale, std::abs(item.reactions[degree]));
                    scale = std::max(scale, std::abs(item.external[degree]));
                }
            line(out, index < int(model.cases.size()) ? "case " : "combination ", item.name,
                 " equilibrium ",
                 equilibrium_residual(item, geometry) <= 0.000001 * scale ? "ok" : "failed",
                 " max_displacement ", real(moves[chosen]), " at ", model.nodes[chosen].id,
                 " energy ", real(energy / 1000), " reactions ", real(reaction[0] / 1000), " ",
                 real(reaction[1] / 1000), " loads ", real(external[0] / 1000), " ",
                 real(external[1] / 1000));
        }
        for (const auto &direction : support_directions) {
            Vector values;
            bool uplift = false;
            for (const Result &combination : combinations) {
                values.push_back(combination.reactions[direction[2]] / 1000);
                if (combination.reactions[direction[2]] < 0)
                    uplift = true;
            }
            int high = extreme(values), low = extreme(values, true);
            std::ostringstream text;
            text << "reaction_envelope " << model.nodes[direction[0]].id << ' '
                 << "xy"[direction[1]] << " max " << real(values[high]) << ' '
                 << combinations[high].name << " min " << real(values[low]) << ' '
                 << combinations[low].name;
            if (direction[1])
                text << " uplift " << (uplift ? "yes" : "no");
            out.push_back(text.str());
        }
        for (int node = 0; node < int(model.nodes.size()); ++node) {
            Vector values;
            for (const Result &combination : combinations)
                values.push_back(magnitudes(combination)[node]);
            int chosen = extreme(values);
            line(out, "displacement_envelope ", model.nodes[node].id, " max ", real(values[chosen]),
                 " ", combinations[chosen].name);
        }
        const Result &deflection = result(model.settings.deflection);
        Indices anchors;
        for (int i = 0; i < int(model.settings.deck.size()); ++i) {
            int node = model.settings.deck[i];
            for (const auto &direction : support_directions)
                if (direction[0] == node && direction[1] == 1)
                    anchors.push_back(i);
        }
        for (int span = 1; span < int(anchors.size()); ++span) {
            int a = anchors[span - 1], b = anchors[span];
            int na = model.settings.deck[a], nb = model.settings.deck[b];
            double va = deflection.displacement[node_dofs[na][1]],
                   vb = deflection.displacement[node_dofs[nb][1]];
            Vector values;
            for (int k = a + 1; k < b; ++k) {
                int node = model.settings.deck[k];
                values.push_back(
                    std::abs(deflection.displacement[node_dofs[node][1]] -
                             (va + (vb - va) * (model.nodes[node].x - model.nodes[na].x) /
                                       (model.nodes[nb].x - model.nodes[na].x))));
            }
            int chosen = extreme(values), nt = model.settings.deck[a + 1 + chosen];
            double limit =
                double(model.nodes[nb].x - model.nodes[na].x) / model.settings.deflection_ratio;
            line(out, "deflection ", deflection.name, " span ", model.nodes[na].id, " ",
                 model.nodes[nb].id, " max ", real(values[chosen]), " at ", model.nodes[nt].id,
                 " limit ", real(limit), " ", values[chosen] <= limit ? "ok" : "exceeded");
            const Result &unit = unit_result(nt);
            double work = 0;
            for (int m = 0; m < int(model.members.size()); ++m) {
                const Properties &p = final_system.properties[m];
                work += deflection.forces[m] * (unit.forces[m] / 1000) * geometry[m].length /
                        (p.young * p.area);
            }
            double stiffness = -deflection.displacement[node_dofs[nt][1]];
            line(out, "virtual_work ", deflection.name, " node ", model.nodes[nt].id, " stiffness ",
                 real(stiffness), " virtual ", real(work), " ",
                 std::abs(work - stiffness) <= 0.000001 * std::max(1.0, std::abs(stiffness))
                     ? "ok"
                     : "failed");
        }
        const Combination *removal = nullptr;
        for (const Combination &item : model.combinations)
            if (item.name == model.settings.removal)
                removal = &item;
        for (int removed = 0; removed < int(model.members.size()); ++removed) {
            System structure = system(removed);
            if (structure.unstable) {
                const auto &owner = owners[*structure.unstable];
                line(out, "removal ", model.members[removed].id, " unstable at ",
                     model.nodes[owner[0]].id, " ", "xy"[owner[1]]);
            } else {
                Result item = removal_result(structure, *removal);
                Vector values;
                Indices remaining;
                for (int m = 0; m < int(model.members.size()); ++m)
                    if (m != removed) {
                        remaining.push_back(m);
                        values.push_back(
                            utilization(item.forces[m], structure.properties[m], geometry[m]));
                    }
                int high = extreme(values), m = remaining[high];
                Vector moves = magnitudes(item);
                int node = extreme(moves);
                line(out, "removal ", model.members[removed].id, " stable max_utilization ",
                     real(values[high]), " at ", model.members[m].id, " max_displacement ",
                     real(moves[node]), " at ", model.nodes[node].id);
            }
        }
        return out;
    }
    double ordinate(const Vector &values, int x) const {
        const Indices &deck = model.settings.deck;
        if (x < model.nodes[deck.front()].x || x > model.nodes[deck.back()].x)
            return 0;
        if (x == model.nodes[deck.back()].x)
            return values.back();
        int k = 0;
        while (model.nodes[deck[k + 1]].x <= x)
            ++k;
        return values[k] + (values[k + 1] - values[k]) * (x - model.nodes[deck[k]].x) /
                               (model.nodes[deck[k + 1]].x - model.nodes[deck[k]].x);
    }
    Vector vehicle(const Vector &values, const Indices &positions) const {
        Vector out;
        for (int p : positions) {
            double value = 0;
            for (const Axle &axle : model.settings.axles)
                value += axle.load * ordinate(values, p - axle.offset);
            out.push_back(value);
        }
        return out;
    }
    Lines influence_report() {
        Lines out;
        const Indices &deck = model.settings.deck;
        Matrix member_lines(model.members.size()), reaction_lines(degrees);
        for (int node : deck) {
            const Result &unit = unit_result(node);
            for (int m = 0; m < int(model.members.size()); ++m)
                member_lines[m].push_back(unit.forces[m] / 1000);
            for (int degree : restrained)
                reaction_lines[degree].push_back(unit.reactions[degree] / 1000);
        }
        for (int m : model.settings.influence) {
            const Vector &values = member_lines[m];
            line(out, "influence ", model.members[m].id);
            double positive = 0, negative = 0;
            for (int k = 0; k < int(deck.size()); ++k) {
                line(out, "node ", model.nodes[deck[k]].id, " ", real(values[k]));
                if (values[k] > 0)
                    positive += values[k];
                else if (values[k] < 0)
                    negative += values[k];
            }
            int high = extreme(values), low = extreme(values, true);
            line(out, "max ", real(values[high]), " at ", model.nodes[deck[high]].id, " min ",
                 real(values[low]), " at ", model.nodes[deck[low]].id, " positive ", real(positive),
                 " negative ", real(negative));
            Vector crossings;
            for (int k = 0; k + 1 < int(deck.size()); ++k)
                if ((values[k] > 0 && values[k + 1] < 0) || (values[k] < 0 && values[k + 1] > 0))
                    crossings.push_back(model.nodes[deck[k]].x +
                                        (model.nodes[deck[k + 1]].x - model.nodes[deck[k]].x) *
                                            values[k] / (values[k] - values[k + 1]));
            std::ostringstream text;
            text << "crossings " << crossings.size();
            for (double value : crossings)
                text << ' ' << real(value, 1);
            out.push_back(text.str());
        }
        Indices positions;
        for (int p = model.nodes[deck.front()].x;
             p <= model.nodes[deck.back()].x + model.settings.axles.back().offset;
             p += model.settings.vehicle_step)
            positions.push_back(p);
        line(out, "vehicle axles ", model.settings.axles.size(), " positions ", positions.size());
        Vector tension, compression;
        for (int m = 0; m < int(model.members.size()); ++m) {
            Vector effects = vehicle(member_lines[m], positions);
            int high = extreme(effects), low = extreme(effects, true);
            tension.push_back(effects[high]);
            compression.push_back(effects[low]);
            line(out, "vehicle_member ", model.members[m].id, " max ", real(effects[high]), " at ",
                 positions[high], " min ", real(effects[low]), " at ", positions[low]);
        }
        for (const auto &direction : support_directions) {
            Vector effects = vehicle(reaction_lines[direction[2]], positions);
            int high = extreme(effects), low = extreme(effects, true);
            line(out, "vehicle_reaction ", model.nodes[direction[0]].id, " ", "xy"[direction[1]],
                 " max ", real(effects[high]), " at ", positions[high], " min ", real(effects[low]),
                 " at ", positions[low]);
        }
        const Result &dead = result(model.settings.rating);
        Vector ratings;
        std::vector<std::pair<int, std::string>> rating_owners;
        for (int m = 0; m < int(model.members.size()); ++m) {
            const Properties &p = final_system.properties[m];
            double nd = dead.forces[m] / 1000;
            double pt = p.area * p.yield_stress / 1000;
            double pc =
                std::min(p.area * p.yield_stress, buckling(p, geometry[m], p.inertia)) / 1000;
            std::string t = "none", c = "none";
            if (rounded(tension[m]) > 0) {
                double value = (pt - model.settings.dead_factor * nd) /
                               (model.settings.vehicle_factor * tension[m]);
                t = real(value);
                ratings.push_back(value);
                rating_owners.emplace_back(m, "tension");
            }
            if (rounded(compression[m]) < 0) {
                double value = (pc + model.settings.dead_factor * nd) /
                               (model.settings.vehicle_factor * (-compression[m]));
                c = real(value);
                ratings.push_back(value);
                rating_owners.emplace_back(m, "compression");
            }
            line(out, "rating ", model.members[m].id, " tension ", t, " compression ", c);
        }
        int low = extreme(ratings, true);
        line(out, "rating_min ", real(ratings[low]), " at ",
             model.members[rating_owners[low].first].id, " ", rating_owners[low].second);
        return out;
    }
    Lines vibration_report() const {
        Lines out;
        const Result &loading = result(model.settings.vibration);
        Vector masses, free_masses;
        double total_mass = 0;
        for (const auto &dofs : node_dofs) {
            double mass = -loading.external[dofs[1]] / 9.81;
            masses.push_back(mass);
            total_mass += mass;
        }
        for (int degree : free)
            free_masses.push_back(masses[owners[degree][0]]);
        line(out, "vibration ", loading.name, " mass ", real(total_mass), " iterations ",
             model.settings.iterations);
        Matrix modes;
        for (int mode = 1; mode <= model.settings.modes; ++mode) {
            Vector x(free.size(), 1);
            for (int iteration = 0; iteration < model.settings.iterations; ++iteration) {
                for (const Vector &phi : modes) {
                    double beta = 0;
                    for (int i = 0; i < int(free.size()); ++i)
                        beta += phi[i] * free_masses[i] * x[i];
                    for (int i = 0; i < int(free.size()); ++i)
                        x[i] = x[i] - beta * phi[i];
                }
                Vector right(free.size());
                for (int i = 0; i < int(free.size()); ++i)
                    right[i] = free_masses[i] * x[i];
                Vector y = solve(final_system.lower, right);
                double norm = 0;
                for (int i = 0; i < int(free.size()); ++i)
                    norm += free_masses[i] * y[i] * y[i];
                norm = std::sqrt(norm);
                for (int i = 0; i < int(free.size()); ++i)
                    x[i] = y[i] / norm;
            }
            modes.push_back(x);
            double numerator = 0, denominator = 0;
            for (int i = 0; i < int(free.size()); ++i) {
                double kx = 0;
                for (int j = 0; j < int(free.size()); ++j)
                    kx += final_system.free_matrix[i][j] * x[j];
                numerator += x[i] * kx;
                denominator += free_masses[i] * x[i] * x[i];
            }
            double frequency = std::sqrt(1000 * (numerator / denominator)) / (2 * pi);
            line(out, "mode ", mode, " frequency ", real(frequency), " period ",
                 real(1 / frequency));
            int peak = 0;
            for (int i = 1; i < int(free.size()); ++i)
                if (std::abs(x[i]) > std::abs(x[peak]))
                    peak = i;
            Vector normalized(degrees);
            for (int i = 0; i < int(free.size()); ++i)
                normalized[free[i]] = x[i] / x[peak];
            for (int node = 0; node < int(model.nodes.size()); ++node)
                line(out, "node ", model.nodes[node].id, " ", real(normalized[node_dofs[node][0]]),
                     " ", real(normalized[node_dofs[node][1]]));
        }
        return out;
    }
    Lines drawing_report() const {
        Lines out;
        for (const Drawing &drawing : model.settings.drawings) {
            Canvas canvas(model.nodes, drawing.horizontal, drawing.vertical);
            const Result &item = result(drawing.name);
            std::vector<std::pair<int, int>> original, deformed;
            for (int node = 0; node < int(model.nodes.size()); ++node) {
                const Node &point = model.nodes[node];
                original.push_back(canvas.position(point.x, point.y));
                deformed.push_back(canvas.position(
                    point.x + drawing.magnification * item.displacement[node_dofs[node][0]],
                    point.y + drawing.magnification * item.displacement[node_dofs[node][1]]));
            }
            for (const Member &member : model.members)
                canvas.segment(original[member.start], original[member.end], '.');
            for (const auto &point : original)
                canvas.put(point, '+');
            for (const Member &member : model.members)
                canvas.segment(deformed[member.start], deformed[member.end], '*');
            for (const auto &point : deformed)
                canvas.put(point, 'o');
            line(out, "drawing ", drawing.name, " magnification ", drawing.magnification,
                 " columns ", canvas.width, " rows ", canvas.height);
            canvas.append_frame(out);
        }
        Canvas canvas(model.nodes, model.settings.map_horizontal, model.settings.map_vertical);
        std::vector<std::pair<int, int>> points;
        for (const Node &node : model.nodes)
            points.push_back(canvas.position(node.x, node.y));
        for (int m = 0; m < int(model.members.size()); ++m) {
            const Member &member = model.members[m];
            char character =
                governing[m] >= 1 ? '#' : char('0' + int(std::floor(10 * governing[m])));
            canvas.segment(points[member.start], points[member.end], character);
        }
        for (const auto &point : points)
            canvas.put(point, 'o');
        line(out, "utilization_map columns ", canvas.width, " rows ", canvas.height);
        canvas.append_frame(out);
        return out;
    }

  public:
    explicit Truss(Model input)
        : model(std::move(input)), degrees(2 * int(model.nodes.size())),
          neighbors(model.nodes.size()) {
        for (const Member &member : model.members) {
            neighbors[member.start].insert(member.end);
            neighbors[member.end].insert(member.start);
            choices.push_back(member.section);
        }
        auto key = [&](int node) {
            return std::make_pair(neighbors[node].size(), model.nodes[node].id);
        };
        int first = 0;
        for (int node = 1; node < int(model.nodes.size()); ++node)
            if (key(node) < key(first))
                first = node;
        order.push_back(first);
        std::set<int> visited{first};
        for (int i = 0; i < int(order.size()); ++i) {
            Indices following;
            for (int node : neighbors[order[i]])
                if (!visited.count(node))
                    following.push_back(node);
            std::sort(following.begin(), following.end(),
                      [&](int a, int b) { return key(a) < key(b); });
            for (int node : following) {
                visited.insert(node);
                order.push_back(node);
            }
        }
        std::reverse(order.begin(), order.end());
        numbers.resize(model.nodes.size());
        for (int i = 0; i < int(order.size()); ++i)
            numbers[order[i]] = i;
        node_dofs.resize(model.nodes.size());
        owners.resize(degrees);
        prescribed.resize(degrees);
        for (int node = 0; node < int(model.nodes.size()); ++node)
            for (int axis = 0; axis < 2; ++axis) {
                int degree = 2 * numbers[node] + axis;
                node_dofs[node][axis] = degree;
                owners[degree] = {node, axis};
            }
        for (const Support &support : model.supports)
            for (int axis = 0; axis < 2; ++axis)
                if (support.fixed[axis]) {
                    int degree = node_dofs[support.node][axis];
                    prescribed[degree] = support.prescribed[axis];
                    support_directions.push_back({support.node, axis, degree});
                    restrained.push_back(degree);
                }
        std::sort(restrained.begin(), restrained.end());
        for (int degree = 0; degree < degrees; ++degree)
            if (!std::binary_search(restrained.begin(), restrained.end(), degree))
                free.push_back(degree);
        geometry = member_geometry(model, node_dofs);
        for (int m = 0; m < int(model.members.size()); ++m) {
            auto found = std::find(group_names.begin(), group_names.end(), model.members[m].group);
            if (found == group_names.end()) {
                group_names.push_back(model.members[m].group);
                group_members.push_back({m});
            } else
                group_members[found - group_names.begin()].push_back(m);
        }
    }
    void run() {
        design_sections();
        std::filesystem::create_directories("output");
        write_lines("analysis.txt", analysis_report());
        write_lines("design.txt", design_report());
        write_lines("influence.txt", influence_report());
        write_lines("vibration.txt", vibration_report());
        write_lines("drawing.txt", drawing_report());
        Lines displacements{"case,node,dx,dy"}, forces{"case,member,force,stress,utilization"},
            reaction{"case,node,rx,ry"};
        for (const Result &item : results) {
            for (int node = 0; node < int(model.nodes.size()); ++node)
                line(displacements, item.name, ",", model.nodes[node].id, ",",
                     real(item.displacement[node_dofs[node][0]]), ",",
                     real(item.displacement[node_dofs[node][1]]));
            for (int m = 0; m < int(model.members.size()); ++m)
                line(forces, item.name, ",", model.members[m].id, ",", real(item.forces[m] / 1000),
                     ",", real(item.forces[m] / final_system.properties[m].area), ",",
                     real(utilization(item.forces[m], final_system.properties[m], geometry[m])));
            for (const Support &support : model.supports)
                line(reaction, item.name, ",", model.nodes[support.node].id, ",",
                     real(item.reactions[node_dofs[support.node][0]] / 1000), ",",
                     real(item.reactions[node_dofs[support.node][1]] / 1000));
        }
        write_lines("displacements.csv", displacements);
        write_lines("member_forces.csv", forces);
        write_lines("reactions.csv", reaction);
    }
};
int main() { Truss(read_model()).run(); }
