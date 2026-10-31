#include "sat.hpp"
#include <filesystem>
struct Solution {
    Preprocess reduced;
    std::vector<Model> models;
    Statistics stats;
    Lines trace;
    int rounds = 0, removed = 0;
    std::string stop = "preprocess";
    std::string status() const {
        return models.empty() ? "UNSAT" : "SAT";
    }
};
Solution solve(const Formula &formula, int limit) {
    Solution out;
    out.reduced = preprocess(formula, limit == 1);
    out.removed = out.reduced.removed_count();
    if (out.reduced.conflict)
        return out;
    std::vector<Clause> clauses;
    for (const WorkingClause &clause : out.reduced.clauses)
        clauses.push_back(clause.literals);
    while (int(out.models.size()) < limit) {
        ++out.rounds;
        Round round = dpll_round(formula.variables, clauses);
        out.stats.add(round.stats);
        if (out.rounds == 1)
            out.trace = round.events;
        if (!round.sat) {
            out.stop = "all";
            return out;
        }
        Model model = round.values;
        Clause block;
        for (int x = 1; x <= formula.variables; ++x) {
            if (out.reduced.fixed[x] >= 0)
                model[x] = out.reduced.fixed[x];
            else
                block.push_back(model[x] ? -x : x);
        }
        out.models.push_back(std::move(model));
        clauses.push_back(std::move(block));
    }
    out.stop = "limit";
    return out;
}
std::map<std::string, Graph> read_graphs() {
    std::map<std::string, Graph> graphs;
    const Lines lines = read_lines("input/graphs.txt");
    for (std::size_t i = 0; i < lines.size(); ++i) {
        if (lines[i].empty() || lines[i][0] == '#')
            continue;
        const Lines header = words(lines[i]);
        Graph graph;
        graph.name = header[1];
        graph.vertices = std::stoi(header[2]);
        graph.degrees.resize(graph.vertices + 1);
        std::set<std::pair<int, int>> seen;
        while (++i < lines.size() && lines[i] != "END") {
            if (!graph.error.empty())
                continue;
            const Lines tokens = words(lines[i]);
            std::string reason;
            if (tokens.size() != 2 || !well_number(tokens[0]) || !well_number(tokens[1]))
                reason = "bad edge line";
            else {
                const int a = std::stoi(tokens[0]), b = std::stoi(tokens[1]);
                const auto edge = std::minmax(a, b);
                if (a < 1 || a > graph.vertices || b < 1 || b > graph.vertices)
                    reason = "vertex out of range";
                else if (a == b)
                    reason = "self loop";
                else if (!seen.insert(edge).second)
                    reason = "duplicate edge";
                else {
                    graph.edges.push_back(edge);
                    ++graph.degrees[a];
                    ++graph.degrees[b];
                }
            }
            if (!reason.empty())
                graph.error = reason + " at line " + number(i + 1);
        }
        std::sort(graph.edges.begin(), graph.edges.end());
        graphs.emplace(graph.name, std::move(graph));
    }
    return graphs;
}
std::vector<int> greedy(const Graph &graph) {
    std::vector<int> order(graph.vertices), colors(graph.vertices + 1);
    std::iota(order.begin(), order.end(), 1);
    std::sort(order.begin(), order.end(), [&](int a, int b) {
        return graph.degrees[a] != graph.degrees[b] ? graph.degrees[a] > graph.degrees[b] : a < b;
    });
    for (int vertex : order) {
        std::set<int> used;
        for (const auto &edge : graph.edges) {
            if (edge.first == vertex)
                used.insert(colors[edge.second]);
            if (edge.second == vertex)
                used.insert(colors[edge.first]);
        }
        int color = 1;
        while (used.count(color))
            ++color;
        colors[vertex] = color;
    }
    return std::vector<int>(colors.begin() + 1, colors.end());
}
std::string graph_line(const Graph &graph) {
    const std::vector<int> colors = greedy(graph);
    return items("graph",
                 {{"vertices", number(graph.vertices)},
                  {"edges", number(graph.edges.size())},
                  {"max_degree", number(*std::max_element(graph.degrees.begin(), graph.degrees.end()))},
                  {"greedy", number(*std::max_element(colors.begin(), colors.end()))}});
}
struct Job {
    std::string command, error;
    int limit = 1, a = 0, b = 0;
    const Graph *graph = nullptr;
    Formula formula;
};
Job validate(const Lines &tokens, const std::map<std::string, Graph> &graphs) {
    Job job;
    job.command = tokens[0];
    const std::map<std::string, int> counts = {{"SOLVE", 1},  {"ENUM", 2},  {"CORE", 1},     {"QUEENS", 2},
                                               {"PIGEON", 3}, {"COLOR", 3}, {"CHROMATIC", 2}};
    const auto count = counts.find(job.command);
    if (count == counts.end()) {
        job.error = "unknown command " + job.command;
        return job;
    }
    if (int(tokens.size()) != count->second + 1) {
        job.error = "wrong argument count";
        return job;
    }
    const bool file = job.command == "SOLVE" || job.command == "ENUM" || job.command == "CORE";
    const bool graph = job.command == "COLOR" || job.command == "CHROMATIC";
    for (std::size_t i = 1; i < tokens.size(); ++i) {
        const std::string &token = tokens[i];
        if (i == 1 && file) {
            bool valid = token.size() >= 5 && token.size() <= 24 && token.substr(token.size() - 4) == ".cnf";
            if (valid)
                for (char c : token.substr(0, token.size() - 4))
                    if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'))
                        valid = false;
            if (!valid) {
                job.error = "bad file name " + token;
                return job;
            }
        } else if (i == 1 && graph) {
            const auto found = graphs.find(token);
            if (found == graphs.end())
                job.error = "unknown graph " + token;
            else if (!found->second.error.empty())
                job.error = "invalid graph " + token + ": " + found->second.error;
            else
                job.graph = &found->second;
            if (!job.error.empty())
                return job;
        } else {
            if (!well_number(token)) {
                job.error = "bad number " + token;
                return job;
            }
            const int value = std::stoi(token);
            const bool limit = (job.command == "ENUM" && i == 2) || (job.command == "QUEENS" && i == 2) ||
                               ((job.command == "PIGEON" || job.command == "COLOR") && i == 3);
            const int maximum = limit ? 200 : graph ? 6 : 8;
            if (value < 1 || value > maximum) {
                job.error = "out of range " + token;
                return job;
            }
            if (limit)
                job.limit = value;
            else if (job.command == "PIGEON" && i == 2)
                job.b = value;
            else
                job.a = value;
        }
    }
    if (file) {
        CnfInput input = read_cnf(tokens[1]);
        job.error = input.error;
        job.formula = std::move(input.formula);
    } else if (job.command == "QUEENS")
        job.formula = queens_formula(job.a);
    else if (job.command == "PIGEON")
        job.formula = pigeon_formula(job.a, job.b);
    else if (job.command == "COLOR")
        job.formula = color_formula(*job.graph, job.a);
    return job;
}
int true_count(const Clause &clause, const Model &model) {
    int count = 0;
    for (int literal : clause)
        if (model[std::abs(literal)] == (literal > 0 ? 1 : 0))
            ++count;
    return count;
}
bool satisfied(const Formula &formula, const Model &model) {
    for (const Clause &clause : formula.clauses)
        if (!true_count(clause, model))
            return false;
    return true;
}
Lines analysis(const Formula &formula, const Solution &solution, bool extended) {
    Lines lines;
    if (solution.models.empty())
        return lines;
    int bad_model = 0, bad_clause = 0;
    for (std::size_t i = 0; i < solution.models.size() && !bad_model; ++i)
        for (std::size_t j = 0; j < formula.clauses.size(); ++j)
            if (!true_count(formula.clauses[j], solution.models[i])) {
                bad_model = i + 1;
                bad_clause = j + 1;
                break;
            }
    if (bad_model)
        lines.push_back(
            items("verify failed", {{"model", number(bad_model)}, {"clause", number(bad_clause)}}));
    else {
        std::map<int, int> counts;
        for (const Clause &clause : formula.clauses)
            ++counts[true_count(clause, solution.models[0])];
        lines.push_back(items("verify ok", {{"models", number(solution.models.size())},
                                            {"clauses", number(formula.clauses.size())},
                                            {"true_literals", frequency_list(counts)}}));
    }
    std::vector<int> flips;
    Model model = solution.models[0];
    for (int x = 1; x <= formula.variables; ++x) {
        model[x] = 1 - model[x];
        if (satisfied(formula, model))
            flips.push_back(x);
        model[x] = 1 - model[x];
    }
    lines.push_back(items("flips", {{"safe", number(flips.size())}, {"variables", number_list(flips)}}));
    if (extended && solution.models.size() >= 2) {
        int pairs = 0, minimum = formula.variables, maximum = 0;
        for (std::size_t i = 0; i < solution.models.size(); ++i)
            for (std::size_t j = i + 1; j < solution.models.size(); ++j) {
                int distance = 0;
                for (int x = 1; x <= formula.variables; ++x)
                    if (solution.models[i][x] != solution.models[j][x])
                        ++distance;
                ++pairs;
                minimum = std::min(minimum, distance);
                maximum = std::max(maximum, distance);
            }
        lines.push_back(items("diversity", {{"pairs", number(pairs)},
                                            {"min_distance", number(minimum)},
                                            {"max_distance", number(maximum)}}));
    }
    if (extended && solution.stop == "all") {
        std::vector<int> backbone;
        for (int x = 1; x <= formula.variables; ++x) {
            bool same = true;
            for (const Model &other : solution.models)
                if (other[x] != model[x])
                    same = false;
            if (same)
                backbone.push_back(model[x] ? x : -x);
        }
        lines.push_back(
            items("backbone", {{"size", number(backbone.size())}, {"literals", number_list(backbone)}}));
    }
    return lines;
}
std::string search_line(const Statistics &stats) {
    return items("search", {{"decisions", number(stats.decisions)},
                            {"propagations", number(stats.propagations)},
                            {"conflicts", number(stats.conflicts)},
                            {"max_depth", number(stats.max_depth)}});
}
void append(Lines &target, const Lines &source) {
    target.insert(target.end(), source.begin(), source.end());
}
Lines regular_result(const Job &job, const Solution &solution) {
    const Formula &formula = job.formula;
    const Preprocess &reduced = solution.reduced;
    Lines lines;
    if (job.command == "COLOR")
        lines.push_back(graph_line(*job.graph));
    std::map<int, int> lengths;
    int literals = 0;
    for (const Clause &clause : formula.clauses) {
        ++lengths[clause.size()];
        literals += clause.size();
    }
    lines.push_back(items("formula", {{"variables", number(formula.variables)},
                                      {"clauses", number(formula.clauses.size())},
                                      {"literals", number(literals)},
                                      {"lengths", frequency_list(lengths)}}));
    lines.push_back(items("preprocess", {{"pure", reduced.pure ? "on" : "off"},
                                         {"tautologies", number(reduced.tautologies)},
                                         {"duplicate_literals", number(reduced.duplicate_literals)},
                                         {"unit_fixed", number(reduced.unit_fixed)},
                                         {"unit_removed", number(reduced.unit_removed)},
                                         {"subsumed", number(reduced.subsumed)},
                                         {"pure_fixed", number(reduced.pure_fixed)},
                                         {"pure_removed", number(reduced.pure_removed)},
                                         {"removed", number(solution.removed)}}));
    auto removed = reduced.removed;
    for (auto &record : removed)
        std::sort(record.begin(), record.end());
    lines.push_back(items("removed_clauses", {{"tautology", number_list(removed[0])},
                                              {"unit", number_list(removed[1])},
                                              {"subsumed", number_list(removed[2])},
                                              {"pure", number_list(removed[3])}}));
    if (reduced.conflict)
        lines.push_back(items("simplified", {{"empty_clause", number(reduced.empty_clause)}}));
    else {
        lengths.clear();
        literals = 0;
        for (const WorkingClause &clause : reduced.clauses) {
            ++lengths[clause.literals.size()];
            literals += clause.literals.size();
        }
        std::vector<int> fixed;
        for (int x = 1; x <= formula.variables; ++x)
            if (reduced.fixed[x] >= 0)
                fixed.push_back(reduced.fixed[x] ? x : -x);
        lines.push_back(items("simplified", {{"clauses", number(reduced.clauses.size())},
                                             {"literals", number(literals)},
                                             {"lengths", frequency_list(lengths)},
                                             {"fixed", number(fixed.size())},
                                             {"active", number(formula.variables - fixed.size())}}));
        lines.push_back(items("fixed", {{"literals", number_list(fixed)}}));
    }
    lines.push_back(items("result " + solution.status(), {{"models", number(solution.models.size())},
                                                          {"rounds", number(solution.rounds)},
                                                          {"stop", solution.stop}}));
    lines.push_back(search_line(solution.stats));
    if (solution.rounds) {
        std::string trace;
        for (std::size_t i = 0; i < std::min<std::size_t>(12, solution.trace.size()); ++i) {
            if (i)
                trace += " ";
            trace += solution.trace[i];
        }
        if (solution.trace.size() > 12)
            trace += " +" + number(solution.trace.size() - 12);
        lines.push_back("trace " + (trace.empty() ? "-" : trace));
    }
    append(lines, analysis(formula, solution, true));
    if (job.command == "CORE" && solution.models.empty()) {
        std::vector<bool> keep(formula.clauses.size(), true);
        Statistics tests;
        for (std::size_t i = 0; i < keep.size(); ++i) {
            Formula trial;
            trial.variables = formula.variables;
            for (std::size_t j = 0; j < keep.size(); ++j)
                if (keep[j] && j != i)
                    trial.clauses.push_back(formula.clauses[j]);
            const Solution test = solve(trial, 1);
            tests.add(test.stats);
            if (test.models.empty())
                keep[i] = false;
        }
        std::vector<int> core;
        for (std::size_t i = 0; i < keep.size(); ++i)
            if (keep[i])
                core.push_back(i + 1);
        lines.push_back(items("core", {{"size", number(core.size())},
                                       {"decisions", number(tests.decisions)},
                                       {"conflicts", number(tests.conflicts)},
                                       {"clauses", number_list(core)}}));
    }
    return lines;
}
struct BoardClass {
    std::vector<int> canonical;
    int orbit = 0, found = 0, first = 0;
};
std::pair<std::vector<int>, int> queen_canonical(const std::vector<int> &columns) {
    const int n = columns.size();
    std::set<std::vector<int>> boards;
    for (int transform = 0; transform < 8; ++transform) {
        std::vector<int> board(n);
        for (int r = 1; r <= n; ++r) {
            const int c = columns[r - 1];
            const std::array<std::pair<int, int>, 8> positions = {{{r, c},
                                                                   {c, n + 1 - r},
                                                                   {n + 1 - r, n + 1 - c},
                                                                   {n + 1 - c, r},
                                                                   {r, n + 1 - c},
                                                                   {n + 1 - r, c},
                                                                   {c, r},
                                                                   {n + 1 - c, n + 1 - r}}};
            board[positions[transform].first - 1] = positions[transform].second;
        }
        boards.insert(board);
    }
    return {*boards.begin(), int(boards.size())};
}
std::vector<int> color_canonical(const std::vector<int> &colors) {
    std::map<int, int> names;
    std::vector<int> canonical;
    for (int color : colors) {
        if (!names.count(color))
            names[color] = names.size() + 1;
        canonical.push_back(names[color]);
    }
    return canonical;
}
Lines puzzle_board(int index, const Job &job, const Solution &solution, int colors) {
    Lines lines;
    const bool queens = job.command == "QUEENS", pigeon = job.command == "PIGEON";
    if (queens)
        lines.push_back(items("QUEENS", {{"job", number(index)}, {"n", number(job.a)}}));
    else if (pigeon)
        lines.push_back(
            items("PIGEON", {{"job", number(index)}, {"pigeons", number(job.a)}, {"holes", number(job.b)}}));
    else {
        const Graph &graph = *job.graph;
        lines.push_back(items(job.command, {{"job", number(index)},
                                            {"graph", graph.name},
                                            {"vertices", number(graph.vertices)},
                                            {"edges", number(graph.edges.size())},
                                            {"colors", number(colors)}}));
        const auto greedy_colors = greedy(graph);
        lines.push_back(
            items("greedy", {{"used", number(*std::max_element(greedy_colors.begin(), greedy_colors.end()))},
                             {"colors", number_list(greedy_colors)}}));
    }
    std::vector<BoardClass> classes;
    for (std::size_t i = 0; i < solution.models.size(); ++i) {
        const std::vector<int> positions =
            decode(solution.models[i], queens || pigeon ? job.a : job.graph->vertices,
                   queens   ? job.a
                   : pigeon ? job.b
                            : colors);
        if (pigeon) {
            std::vector<int> empty;
            for (int h = 1; h <= job.b; ++h)
                if (std::find(positions.begin(), positions.end(), h) == positions.end())
                    empty.push_back(h);
            lines.push_back(items("assignment " + number(i + 1),
                                  {{"holes", number_list(positions)}, {"empty", number_list(empty)}}));
            continue;
        }
        const auto canonical =
            queens ? queen_canonical(positions) : std::make_pair(color_canonical(positions), 0);
        std::size_t category = 0;
        while (category < classes.size() && classes[category].canonical != canonical.first)
            ++category;
        const bool first = category == classes.size();
        if (first)
            classes.push_back({canonical.first, canonical.second, 0, int(i + 1)});
        ++classes[category].found;
        if (queens) {
            lines.push_back(items("solution " + number(i + 1),
                                  {{"columns", number_list(positions)}, {"class", number(category + 1)}}));
            if (first)
                append(lines, board_lines(positions));
        } else {
            std::set<int> used(positions.begin(), positions.end());
            std::vector<int> sizes(colors);
            for (int color : positions)
                ++sizes[color - 1];
            lines.push_back(items("coloring " + number(i + 1), {{"colors", number_list(positions)},
                                                                {"used", number(used.size())},
                                                                {"sizes", number_list(sizes)},
                                                                {"class", number(category + 1)}}));
        }
    }
    for (std::size_t i = 0; i < classes.size(); ++i) {
        const BoardClass &category = classes[i];
        std::vector<std::pair<std::string, std::string>> fields;
        if (queens)
            fields.push_back({"orbit", number(category.orbit)});
        fields.push_back({"found", number(category.found)});
        fields.push_back({"first", number(category.first)});
        fields.push_back({"canonical", number_list(category.canonical)});
        lines.push_back(items("class " + number(i + 1), fields));
    }
    if (pigeon) {
        int expected = job.a <= job.b ? 1 : 0;
        if (expected)
            for (int i = 0; i < job.a; ++i)
                expected *= job.b - i;
        lines.push_back(items("summary", {{"assignments", number(solution.models.size())},
                                          {"stop", solution.stop},
                                          {"expected", number(expected)}}));
    } else
        lines.push_back(
            items("summary", {{queens ? "solutions" : "colorings", number(solution.models.size())},
                              {"stop", solution.stop},
                              {"classes", number(classes.size())}}));
    return lines;
}
struct Record {
    int index;
    std::string command, status;
    Statistics stats;
    int variables, clauses, removed, models, rounds;
};
int main() {
    std::filesystem::create_directories("output");
    const std::map<std::string, Graph> graphs = read_graphs();
    std::vector<Lines> results, models, boards;
    Lines csv = {
        "job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds"};
    std::vector<Record> records;
    int index = 0, errors = 0;
    for (const std::string &raw : read_lines("input/jobs.txt")) {
        if (raw.empty() || raw[0] == '#')
            continue;
        ++index;
        const std::string header = "JOB " + number(index) + " " + raw;
        Lines result = {header};
        Job job = validate(words(raw), graphs);
        if (!job.error.empty()) {
            result.push_back("error " + job.error);
            results.push_back(result);
            ++errors;
            continue;
        }
        Solution solution;
        int colors = job.a;
        if (job.command == "CHROMATIC") {
            result.push_back(graph_line(*job.graph));
            Statistics aggregate;
            int removed = 0, rounds = 0;
            for (colors = 1; colors <= job.a; ++colors) {
                job.formula = color_formula(*job.graph, colors);
                solution = solve(job.formula, 1);
                aggregate.add(solution.stats);
                removed += solution.removed;
                rounds += solution.rounds;
                result.push_back(items("attempt", {{"k", number(colors)},
                                                   {"clauses", number(job.formula.clauses.size())},
                                                   {"removed", number(solution.removed)},
                                                   {"result", solution.status()},
                                                   {"stop", solution.stop},
                                                   {"decisions", number(solution.stats.decisions)},
                                                   {"propagations", number(solution.stats.propagations)},
                                                   {"conflicts", number(solution.stats.conflicts)},
                                                   {"max_depth", number(solution.stats.max_depth)}}));
                if (!solution.models.empty())
                    break;
            }
            colors = std::min(colors, job.a);
            result.push_back(items("result " + solution.status(),
                                   {{"chromatic", solution.models.empty() ? "-" : number(colors)},
                                    {"attempts", number(colors)}}));
            solution.stats = aggregate;
            solution.removed = removed;
            solution.rounds = rounds;
            result.push_back(search_line(aggregate));
            append(result, analysis(job.formula, solution, false));
        } else {
            solution = solve(job.formula, job.limit);
            append(result, regular_result(job, solution));
        }
        results.push_back(result);
        if (!solution.models.empty()) {
            Lines paragraph = {header};
            for (std::size_t i = 0; i < solution.models.size(); ++i) {
                paragraph.push_back("model " + number(i + 1));
                append(paragraph, model_lines(solution.models[i]));
            }
            models.push_back(paragraph);
        }
        if (job.command == "QUEENS" || job.command == "PIGEON" || job.command == "COLOR" ||
            job.command == "CHROMATIC")
            boards.push_back(puzzle_board(index, job, solution, colors));
        const Record record = {index,
                               job.command,
                               solution.status(),
                               solution.stats,
                               job.formula.variables,
                               int(job.formula.clauses.size()),
                               solution.removed,
                               int(solution.models.size()),
                               solution.rounds};
        records.push_back(record);
        csv.push_back(number(index) + "," + job.command + "," + record.status + "," +
                      number(record.variables) + "," + number(record.clauses) + "," + number(record.removed) +
                      "," + number(record.stats.decisions) + "," + number(record.stats.propagations) + "," +
                      number(record.stats.conflicts) + "," + number(record.stats.max_depth) + "," +
                      number(record.models) + "," + number(record.rounds));
    }
    Statistics totals;
    int sat = 0, model_total = 0, round_total = 0, removed_total = 0;
    for (const Record &record : records) {
        sat += record.status == "SAT";
        totals.add(record.stats);
        model_total += record.models;
        round_total += record.rounds;
        removed_total += record.removed;
    }
    Lines summary = {items("SUMMARY", {{"jobs", number(index)},
                                       {"sat", number(sat)},
                                       {"unsat", number(records.size() - sat)},
                                       {"error", number(errors)}}),
                     items("totals", {{"models", number(model_total)},
                                      {"rounds", number(round_total)},
                                      {"decisions", number(totals.decisions)},
                                      {"propagations", number(totals.propagations)},
                                      {"conflicts", number(totals.conflicts)},
                                      {"removed_clauses", number(removed_total)}})};
    for (const std::string command : {"SOLVE", "ENUM", "CORE", "QUEENS", "PIGEON", "COLOR", "CHROMATIC"}) {
        int jobs = 0, command_sat = 0;
        Statistics stats;
        for (const Record &record : records)
            if (record.command == command) {
                ++jobs;
                command_sat += record.status == "SAT";
                stats.add(record.stats);
            }
        if (jobs)
            summary.push_back(items("command " + command, {{"jobs", number(jobs)},
                                                           {"sat", number(command_sat)},
                                                           {"unsat", number(jobs - command_sat)},
                                                           {"decisions", number(stats.decisions)},
                                                           {"propagations", number(stats.propagations)},
                                                           {"conflicts", number(stats.conflicts)}}));
    }
    if (!records.empty()) {
        const Record *hardest = &records[0], *deepest = hardest, *busiest = hardest;
        for (const Record &record : records) {
            if (record.stats.conflicts > hardest->stats.conflicts)
                hardest = &record;
            if (record.stats.max_depth > deepest->stats.max_depth)
                deepest = &record;
            if (record.stats.propagations > busiest->stats.propagations)
                busiest = &record;
        }
        summary.push_back(items(
            "hardest", {{"job", number(hardest->index)}, {"conflicts", number(hardest->stats.conflicts)}}));
        summary.push_back(items(
            "deepest", {{"job", number(deepest->index)}, {"max_depth", number(deepest->stats.max_depth)}}));
        summary.push_back(items("busiest", {{"job", number(busiest->index)},
                                            {"propagations", number(busiest->stats.propagations)}}));
    }
    results.push_back(summary);
    write_paragraphs("results.txt", results);
    write_paragraphs("models.txt", models);
    write_paragraphs("boards.txt", boards);
    write_lines("stats.csv", csv);
}
