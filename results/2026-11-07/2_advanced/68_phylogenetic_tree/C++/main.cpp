#include "phylogeny.hpp"
static const std::array<std::string, 3> models = {"P", "JC", "K2P"};
static const std::array<std::string, 6> methods = {"NJ_P", "NJ_JC", "NJ_K2P",
                                                   "ME",   "MP",    "CONSENSUS"};
static int bits(Mask mask) {
    int out = 0;
    while (mask) {
        out += int(mask & 1u);
        mask >>= 1;
    }
    return out;
}
static void append(Lines &out, const Lines &values) {
    out.insert(out.end(), values.begin(), values.end());
}
static double sum(const std::vector<double> &values) {
    double out = 0;
    for (double value : values)
        out += value;
    return out;
}
static double square(double value) { return value * value; }
static int support_count(const std::map<Mask, int> &support, Mask mask) {
    auto found = support.find(mask);
    return found == support.end() ? 0 : found->second;
}
static std::vector<Mask> symbol_order(const std::set<Mask> &masks, int size) {
    std::vector<Mask> out(masks.begin(), masks.end());
    std::sort(out.begin(), out.end(),
              [&](Mask a, Mask b) { return symbols(a, size) < symbols(b, size); });
    return out;
}
static int rf(const std::set<Mask> &a, const std::set<Mask> &b) {
    int out = 0;
    for (Mask mask : a)
        out += !b.count(mask);
    for (Mask mask : b)
        out += !a.count(mask);
    return out;
}
struct Params {
    int model = 0, replicates = 0, maximum_missing = 0, low_sites = 0;
    std::int64_t seed = 0;
    double saturation = 0;
    std::string outgroup;
    Names exhaustive;
};
static Params read_parameters() {
    std::ifstream input("input/params.txt");
    std::string text;
    Params out;
    while (std::getline(input, text)) {
        std::istringstream row(text);
        std::string key, value;
        row >> key >> value;
        if (key == "model")
            out.model = int(std::find(models.begin(), models.end(), value) - models.begin());
        else if (key == "outgroup")
            out.outgroup = value;
        else if (key == "replicates")
            out.replicates = std::stoi(value);
        else if (key == "seed")
            out.seed = std::stoll(value);
        else if (key == "max_missing_percent")
            out.maximum_missing = std::stoi(value);
        else if (key == "saturation_distance")
            out.saturation = std::stod(value);
        else if (key == "low_sites")
            out.low_sites = std::stoi(value);
        else {
            out.exhaustive.push_back(value);
            while (row >> value)
                out.exhaustive.push_back(value);
        }
    }
    return out;
}
struct Addition {
    int taxon;
    Mask mask;
    int score, ties;
};
struct Stepwise {
    Tree tree;
    int initial = 0, score = 0, evaluated = 0;
    std::vector<int> taxa;
    std::vector<Addition> additions;
};
struct Move {
    Mask mask;
    int swap;
    double value;
};
struct Search {
    Tree tree;
    double value = 0;
    int evaluated = 0;
    std::vector<Move> moves;
};
struct ExhaustiveRecord {
    Tree tree;
    int score;
    double bme;
    std::string newick;
    std::set<Mask> splits;
};
struct Exhaustive {
    std::vector<int> taxa;
    std::vector<ExhaustiveRecord> records;
    std::vector<int> optimal;
    std::map<int, int> histogram;
    int best_score = 0, best_bme = 0, heuristic = 0;
    double second_bme = 0;
    Tree strict;
};
struct Study {
    Params params;
    std::vector<Record> records;
    Names names, sequences;
    Lines rejected;
    Patterns patterns;
    int size = 0, length = 0, outgroup = 0, minimum = 0, maximum = 0;
    std::vector<int> taxa, minima, nj_scores;
    std::vector<Pair> pairs;
    std::array<Matrix, 3> matrices, patristics;
    std::array<std::vector<Pair>, 3> saturated;
    std::array<Tree, 6> trees;
    std::array<std::vector<double>, 3> site_logs;
    std::map<Mask, int> support;
    Stepwise initial;
    Search me, mp;
    Reconstruction reconstruction;
    Exhaustive exhaustive;
    double me_start = 0;
    Lines bootstrap_lines;
    explicit Study(Params parameters) : params(std::move(parameters)), records(read_fasta()) {
        length = int(records.front().sequence.size());
        std::set<std::string> seen;
        for (const Record &record : records) {
            std::string reason;
            if (!seen.insert(record.name).second)
                reason = "duplicate name";
            if (reason.empty())
                for (int c = 0; c < int(record.sequence.size()); ++c)
                    if (!base_set(record.sequence[c])) {
                        reason = "invalid character " + std::string(1, record.sequence[c]) +
                                 " at column " + std::to_string(c + 1);
                        break;
                    }
            if (reason.empty() && int(record.sequence.size()) != length)
                reason = "length mismatch " + std::to_string(record.sequence.size());
            if (reason.empty()) {
                int missing = 0;
                for (char c : record.sequence)
                    missing += c == '-' || c == 'N';
                if (100 * missing > params.maximum_missing * length)
                    reason = "too many missing " + std::to_string(missing);
            }
            if (reason.empty()) {
                names.push_back(record.name);
                sequences.push_back(record.sequence);
            } else
                line(rejected, "REJECT line ", record.line, " ", record.name, " ", reason);
        }
        size = int(names.size());
        outgroup = int(std::find(names.begin(), names.end(), params.outgroup) - names.begin());
        taxa.resize(size);
        std::iota(taxa.begin(), taxa.end(), 0);
        patterns = Patterns(sequences);
        pairs = all_pairs(sequences, std::vector<int>(length, 1));
        for (int model = 0; model < 3; ++model) {
            auto built = build_matrix(pairs, model, params.saturation);
            matrices[model] = built.first;
            saturated[model] = std::move(built.second);
            trees[model] = neighbor_joining(matrices[model], size, taxa);
            patristics[model] = patristic(trees[model]);
            nj_scores.push_back(score(trees[model], patterns, outgroup));
            site_logs[model] = likelihood_sites(trees[model]);
        }
    }
    Lines summary() const {
        Lines out;
        line(out, "INPUT records ", records.size(), " accepted ", size, " rejected ",
             rejected.size(), " columns ", length);
        append(out, rejected);
        std::vector<std::array<int, 4>> columns(length);
        for (int c = 0; c < length; ++c)
            for (const std::string &sequence : sequences) {
                int base = base_index(sequence[c]);
                if (base >= 0)
                    ++columns[c][base];
            }
        std::array<int, 4> composition{};
        for (int t = 0; t < size; ++t) {
            std::array<int, 4> counts{};
            int ambiguous = 0, missing = 0, unique = 0;
            for (int c = 0; c < length; ++c) {
                char character = sequences[t][c];
                int base = base_index(character);
                if (base >= 0) {
                    ++counts[base];
                    int total = std::accumulate(columns[c].begin(), columns[c].end(), 0);
                    unique += columns[c][base] == 1 && total > 1;
                } else if (character == 'N' || character == '-')
                    ++missing;
                else
                    ++ambiguous;
            }
            int bases = std::accumulate(counts.begin(), counts.end(), 0);
            line(out, "TAXON ", names[t], " bases ", bases, " ambiguous ", ambiguous, " missing ",
                 missing, " unique ", unique, " gc ",
                 real(double(counts[1] + counts[2]) / bases, 4));
            for (int b = 0; b < 4; ++b)
                composition[b] += counts[b];
        }
        Classes classes = classify(sequences);
        line(out, "COLUMNS constant ", classes.constant, " variable ", classes.variable,
             " informative ", classes.informative, " gapped ", classes.gapped, " empty ",
             classes.empty);
        line(out, "PATTERNS ", patterns.text.size());
        int total = std::accumulate(composition.begin(), composition.end(), 0);
        line(out, "COMPOSITION A ", real(double(composition[0]) / total, 4), " C ",
             real(double(composition[1]) / total, 4), " G ",
             real(double(composition[2]) / total, 4), " T ",
             real(double(composition[3]) / total, 4));
        return out;
    }
    double bme(const Tree &tree) const {
        double value = 0;
        std::vector<int> leaves = tree.taxa();
        for (int a : leaves) {
            std::array<double, 32> steps = paths(tree, a, true);
            for (int b : leaves)
                if (a < b)
                    value += std::ldexp(matrices[params.model][a][b], 1 - int(steps[b]));
        }
        return value;
    }
    Stepwise stepwise(const std::vector<int> &order) const {
        Stepwise out;
        out.taxa = order;
        out.tree = star(size, {order[0], order[1], order[2]});
        out.score = out.initial = score(out.tree, patterns, outgroup);
        for (int i = 3; i < int(order.size()); ++i) {
            int best = std::numeric_limits<int>::max(), ties = 0;
            Mask chosen_mask = 0;
            Tree chosen;
            for (const Branch &branch : branches(out.tree, outgroup)) {
                Tree candidate = insert(out.tree, branch.first, branch.second, order[i]);
                int value = score(candidate, patterns, outgroup);
                ++out.evaluated;
                if (value < best) {
                    best = value;
                    chosen = candidate;
                    chosen_mask = branch.mask;
                    ties = 1;
                } else if (value == best)
                    ++ties;
            }
            out.tree = chosen;
            out.score = best;
            out.additions.push_back({order[i], chosen_mask, best, ties});
        }
        return out;
    }
    Search hill_climb(const Tree &start, const std::function<double(const Tree &)> &objective,
                      double value) const {
        Search out;
        out.tree = start;
        out.value = value;
        while (true) {
            bool moved = false;
            for (const Swap &candidate : nni_candidates(out.tree, outgroup)) {
                double result = objective(candidate.tree);
                ++out.evaluated;
                if (result < out.value) {
                    out.tree = candidate.tree;
                    out.value = result;
                    out.moves.push_back({candidate.mask, candidate.number, result});
                    moved = true;
                    break;
                }
            }
            if (!moved)
                break;
        }
        return out;
    }
    Tree consensus(const std::vector<int> &leaves, const std::set<Mask> &clades) const {
        Tree tree(size);
        int root = tree.internal();
        tree.connect(root, outgroup);
        Mask ingroup = 0;
        for (int t : leaves)
            if (t != outgroup)
                ingroup |= 1u << t;
        std::function<void(int, Mask)> fill = [&](int parent, Mask region) {
            std::vector<Mask> children;
            for (Mask candidate : clades)
                if (candidate != region && (candidate & region) == candidate) {
                    bool maximal = true;
                    for (Mask other : clades)
                        if (other != region && candidate != other && (other & region) == other &&
                            (candidate & other) == candidate)
                            maximal = false;
                    if (maximal)
                        children.push_back(candidate);
                }
            Mask covered = 0;
            for (Mask child : children) {
                int node = tree.internal();
                tree.connect(parent, node);
                fill(node, child);
                covered |= child;
            }
            for (int t : leaves)
                if ((region & (1u << t)) && !(covered & (1u << t)))
                    tree.connect(parent, t);
        };
        fill(root, ingroup);
        return tree;
    }
    Exhaustive exhaustive_search(const std::vector<int> &order) const {
        Exhaustive out;
        out.taxa = order;
        std::vector<Tree> forest = {star(size, {order[0], order[1], order[2]})};
        for (int i = 3; i < int(order.size()); ++i) {
            std::vector<Tree> expanded;
            for (const Tree &tree : forest)
                for (const Branch &branch : branches(tree, outgroup))
                    expanded.push_back(insert(tree, branch.first, branch.second, order[i]));
            forest = std::move(expanded);
        }
        out.best_score = std::numeric_limits<int>::max();
        for (const Tree &tree : forest) {
            int value = score(tree, patterns, outgroup);
            out.records.push_back({tree, value, bme(tree), newick(tree, names, outgroup),
                                   Rooted(tree, outgroup).splits(tree)});
            ++out.histogram[value];
            out.best_score = std::min(out.best_score, value);
        }
        for (int i = 0; i < int(out.records.size()); ++i)
            if (out.records[i].score == out.best_score)
                out.optimal.push_back(i);
        std::sort(out.optimal.begin(), out.optimal.end(),
                  [&](int a, int b) { return out.records[a].newick < out.records[b].newick; });
        std::set<Mask> common = out.records[out.optimal[0]].splits;
        for (int index : out.optimal) {
            std::set<Mask> retained;
            for (Mask mask : common)
                if (out.records[index].splits.count(mask))
                    retained.insert(mask);
            common = retained;
        }
        out.strict = consensus(order, common);
        Stepwise heuristic = stepwise(order);
        Search searched = hill_climb(
            heuristic.tree, [&](const Tree &tree) { return score(tree, patterns, outgroup); },
            heuristic.score);
        out.heuristic = int(searched.value);
        std::vector<int> ranked(out.records.size());
        std::iota(ranked.begin(), ranked.end(), 0);
        std::sort(ranked.begin(), ranked.end(), [&](int a, int b) {
            return out.records[a].bme != out.records[b].bme
                       ? out.records[a].bme < out.records[b].bme
                       : out.records[a].newick < out.records[b].newick;
        });
        out.best_bme = ranked[0];
        out.second_bme = out.records[ranked[1]].bme;
        return out;
    }
    std::vector<double> likelihood_sites(const Tree &tree) const {
        Rooted rooted(tree, outgroup);
        std::vector<double> values;
        for (const auto &pattern : patterns.encoded) {
            std::array<std::array<double, 4>, 32> partial{};
            for (auto at = rooted.order.rbegin(); at != rooted.order.rend(); ++at) {
                int node = *at;
                if (node < size) {
                    for (int x = 0; x < 4; ++x)
                        partial[node][x] = bool(pattern[node] & (1u << x));
                } else
                    for (int x = 0; x < 4; ++x) {
                        double product = 1;
                        for (int child : rooted.children[node]) {
                            double exponential = std::exp(-4 * tree.length[node][child] / 3),
                                   subtotal = 0;
                            for (int y = 0; y < 4; ++y) {
                                double probability =
                                    x == y ? 0.25 + 0.75 * exponential : 0.25 - 0.25 * exponential;
                                subtotal += probability * partial[child][y];
                            }
                            product *= subtotal;
                        }
                        partial[node][x] = product;
                    }
            }
            double probability = 0;
            for (int x = 0; x < 4; ++x)
                probability += 0.25 * partial[rooted.root][x];
            values.push_back(std::log(probability));
        }
        std::vector<double> out;
        for (int index : patterns.columns)
            out.push_back(values[index]);
        return out;
    }
    void bounds() {
        std::vector<int> lower;
        for (int i = 0; i < int(patterns.encoded.size()); ++i) {
            const auto &pattern = patterns.encoded[i];
            int low = 4, high = size;
            for (unsigned mask = 1; mask < 16; ++mask) {
                bool covers = true;
                for (int t = 0; t < size; ++t)
                    if (!(mask & pattern[t]))
                        covers = false;
                if (covers)
                    low = std::min(low, bits(mask) - 1);
            }
            for (int b = 0; b < 4; ++b) {
                int misses = 0;
                for (int t = 0; t < size; ++t)
                    misses += !(pattern[t] & (1u << b));
                high = std::min(high, misses);
            }
            lower.push_back(low);
            maximum += high * patterns.weights[i];
        }
        for (int index : patterns.columns) {
            minima.push_back(lower[index]);
            minimum += lower[index];
        }
    }
    void bootstrap() {
        const Tree &main = trees[params.model];
        std::set<Mask> main_splits = Rooted(main, outgroup).splits(main);
        std::int64_t state = params.seed;
        line(bootstrap_lines, "BOOTSTRAP model ", models[params.model], " replicates ",
             params.replicates, " seed ", state);
        int identical = 0;
        for (int b = 1; b <= params.replicates; ++b) {
            std::vector<int> weights(length);
            for (int draw = 0; draw < length; ++draw) {
                state = (48271 * state) % 2147483647;
                ++weights[state % length];
            }
            Matrix matrix =
                build_matrix(all_pairs(sequences, weights), params.model, params.saturation).first;
            Tree tree = neighbor_joining(matrix, size, taxa);
            std::set<Mask> splits = Rooted(tree, outgroup).splits(tree);
            for (Mask mask : splits)
                ++support[mask];
            int difference = rf(main_splits, splits);
            identical += difference == 0;
            int distinct = 0;
            for (int count : weights)
                distinct += count > 0;
            line(bootstrap_lines, "REPLICATE ", b, " distinct ", distinct, " rf ", difference);
        }
        line(bootstrap_lines, "IDENTICAL ", identical);
        for (Mask mask : symbol_order(main_splits, size))
            line(bootstrap_lines, "SUPPORT ", symbols(mask, size), " ",
                 support_count(support, mask));
        std::vector<Mask> ranked;
        std::set<Mask> majority;
        for (const auto &entry : support) {
            ranked.push_back(entry.first);
            if (2 * entry.second > params.replicates)
                majority.insert(entry.first);
        }
        std::sort(ranked.begin(), ranked.end(), [&](Mask a, Mask b) {
            return support.at(a) != support.at(b) ? support.at(a) > support.at(b)
                                                  : symbols(a, size) < symbols(b, size);
        });
        for (Mask mask : ranked)
            line(bootstrap_lines, "SPLIT ", symbols(mask, size), " ", support.at(mask));
        trees[5] = consensus(taxa, majority);
        line(bootstrap_lines, "CONSENSUS ", newick(trees[5], names, outgroup, false, &support));
        for (int removed = 0; removed < size; ++removed)
            if (removed != outgroup) {
                std::vector<int> kept;
                for (int t : taxa)
                    if (t != removed)
                        kept.push_back(t);
                Tree tree = neighbor_joining(matrices[params.model], size, kept);
                std::set<Mask> reduced;
                for (Mask mask : main_splits) {
                    Mask after = mask & ~(1u << removed);
                    if (bits(after) >= 2 && bits(after) <= size - 3)
                        reduced.insert(after);
                }
                line(bootstrap_lines, "JACKKNIFE ", names[removed], " rf ",
                     rf(Rooted(tree, outgroup).splits(tree), reduced));
            }
    }
    void matrix_lines(Lines &out, const Matrix &matrix) const {
        std::size_t width = 0;
        for (const std::string &name : names)
            width = std::max(width, name.size());
        for (int a = 0; a < size; ++a) {
            std::ostringstream row;
            row << std::left << std::setw(int(width)) << names[a];
            for (int b = 0; b < size; ++b)
                row << ' ' << real(matrix[a][b], 5);
            out.push_back(row.str());
        }
    }
    Lines distances_report() const {
        Lines out;
        int sites = 0, transitions = 0, transversions = 0;
        for (const Pair &p : pairs) {
            line(out, "PAIR ", names[p.first], " ", names[p.second], " sites ", p.sites,
                 " transitions ", p.transitions, " transversions ", p.transversions);
            sites += p.sites;
            transitions += p.transitions;
            transversions += p.transversions;
        }
        line(out, "TOTAL sites ", sites, " transitions ", transitions, " transversions ",
             transversions);
        for (int model = 0; model < 3; ++model) {
            out.push_back("");
            line(out, "MODEL ", models[model]);
            matrix_lines(out, matrices[model]);
            for (const Pair &p : saturated[model])
                line(out, "SATURATED ", names[p.first], " ", names[p.second], " sites ", p.sites);
        }
        out.push_back("");
        line(out, "PATRISTIC ", methods[params.model]);
        matrix_lines(out, patristics[params.model]);
        out.push_back("");
        line(out, "ME start ", methods[params.model], " length ", real(me_start, 5));
        for (const Move &move : me.moves)
            line(out, "NNI edge ", symbols(move.mask, size), " swap ", move.swap, " length ",
                 real(move.value, 5));
        line(out, "ME moves ", me.moves.size(), " evaluated ", me.evaluated, " length ",
             real(me.value, 5));
        const ExhaustiveRecord &best = exhaustive.records[exhaustive.best_bme];
        line(out, "EXHAUSTIVE taxa ", exhaustive.taxa.size(), " trees ", exhaustive.records.size(),
             " best ", real(best.bme, 5), " second ", real(exhaustive.second_bme, 5));
        line(out, "BEST ", best.newick, " parsimony ", best.score);
        return out;
    }
    void score_line(Lines &out, const std::string &method, int value) const {
        line(out, "TREE ", method, " score ", value, " ci ", real(double(minimum) / value, 4),
             " ri ", real(double(maximum - value) / (maximum - minimum), 4));
    }
    Lines parsimony_report() const {
        Lines out;
        line(out, "BOUNDS minimum ", minimum, " maximum ", maximum);
        for (int i = 0; i < 3; ++i)
            score_line(out, methods[i], nj_scores[i]);
        line(out, "START ", names[initial.taxa[0]], " ", names[initial.taxa[1]], " ",
             names[initial.taxa[2]], " score ", initial.initial);
        for (const Addition &add : initial.additions)
            line(out, "ADD ", names[add.taxon], " edge ", symbols(add.mask, size), " score ",
                 add.score, " ties ", add.ties);
        line(out, "STEPWISE score ", initial.score, " evaluated ", initial.evaluated);
        for (const Move &move : mp.moves)
            line(out, "NNI edge ", symbols(move.mask, size), " swap ", move.swap, " score ",
                 int(move.value));
        line(out, "SEARCH moves ", mp.moves.size(), " evaluated ", mp.evaluated, " score ",
             int(mp.value));
        score_line(out, "MP", int(mp.value));
        line(out, "MP ", newick(trees[4], names, outgroup, true));
        std::map<int, int> histogram;
        int homoplasy = 0;
        for (int c = 0; c < length; ++c) {
            ++histogram[reconstruction.sites[c]];
            homoplasy += reconstruction.sites[c] > minima[c];
        }
        for (int k = 0; k <= histogram.rbegin()->first; ++k)
            line(out, "CHANGES ", k, " columns ", histogram[k]);
        line(out, "HOMOPLASY columns ", homoplasy, " extra ", int(mp.value) - minimum);
        Rooted rooted(trees[4], outgroup);
        std::map<std::string, std::string> ancestral;
        for (const auto &entry : reconstruction.ancestors)
            ancestral[symbols(
                entry.first == rooted.root ? rooted.ingroup : rooted.masks[entry.first], size)] =
                entry.second;
        for (const auto &entry : ancestral)
            line(out, "ANCESTOR ", entry.first, " ", entry.second);
        out.push_back("");
        line(out, "EXHAUSTIVE taxa ", exhaustive.taxa.size(), " trees ", exhaustive.records.size(),
             " best ", exhaustive.best_score, " optimal ", exhaustive.optimal.size());
        for (const auto &entry : exhaustive.histogram)
            line(out, "SCORE ", entry.first, " trees ", entry.second);
        for (int index : exhaustive.optimal) {
            const auto &record = exhaustive.records[index];
            line(out, "OPTIMAL ", record.newick, " bme ", real(record.bme, 5));
        }
        line(out, "STRICT ", newick(exhaustive.strict, names, outgroup));
        line(out, "HEURISTIC score ", exhaustive.heuristic, " optimal ",
             exhaustive.heuristic == exhaustive.best_score ? "yes" : "no");
        return out;
    }
    Lines likelihood_report() const {
        Lines out;
        line(out, "LIKELIHOOD columns ", length, " patterns ", patterns.text.size());
        for (int i = 0; i < 3; ++i) {
            double total = sum(site_logs[i]);
            line(out, "TREE ", methods[i], " loglik ", real(total, 4), " per_site ",
                 real(total / length, 4));
        }
        for (int a = 0; a < 3; ++a)
            for (int b = a + 1; b < 3; ++b) {
                std::vector<double> deltas;
                for (int c = 0; c < length; ++c)
                    deltas.push_back(site_logs[a][c] - site_logs[b][c]);
                double difference = sum(deltas), average = difference / length, squares = 0;
                for (double value : deltas)
                    squares += square(value - average);
                double error = std::sqrt(double(length) / (length - 1) * squares);
                line(out, "KH ", methods[a], " ", methods[b], " difference ", real(difference, 4),
                     " se ", real(error, 4), " z ", real(difference / error, 4));
            }
        std::vector<int> order(length);
        std::iota(order.begin(), order.end(), 0);
        std::vector<double> rounded;
        for (double value : site_logs[params.model])
            rounded.push_back(std::stod(real(value, 4)));
        std::sort(order.begin(), order.end(), [&](int a, int b) {
            return rounded[a] != rounded[b] ? rounded[a] < rounded[b] : a < b;
        });
        line(out, "LOWEST ", methods[params.model], " sites ", params.low_sites);
        std::vector<int> changes = pattern_scores(trees[params.model], patterns, outgroup);
        for (int i = 0; i < params.low_sites; ++i) {
            int c = order[i], pattern = patterns.columns[c];
            line(out, "SITE ", c + 1, " loglik ", real(site_logs[params.model][c], 4), " changes ",
                 changes[pattern], " pattern ", patterns.text[pattern]);
        }
        return out;
    }
    Lines clock_report() const {
        Lines pairs;
        int rejected = 0;
        for (int a = 0; a < size; ++a)
            if (a != outgroup)
                for (int b = a + 1; b < size; ++b)
                    if (b != outgroup) {
                        int m1 = 0, m2 = 0;
                        for (int c = 0; c < length; ++c) {
                            char x = sequences[a][c], y = sequences[b][c],
                                 o = sequences[outgroup][c];
                            if (base_index(x) >= 0 && base_index(y) >= 0 && base_index(o) >= 0 &&
                                x != y) {
                                m1 += y == o;
                                m2 += x == o;
                            }
                        }
                        int difference = m1 - m2;
                        bool reject = 1000 * difference * difference > 3841 * (m1 + m2);
                        rejected += reject;
                        line(pairs, "RRT ", names[a], " ", names[b], " m1 ", m1, " m2 ", m2,
                             " chi2 ",
                             m1 + m2 ? real(double(difference * difference) / (m1 + m2), 4) : "-",
                             " ", reject ? "reject" : "ok");
                    }
        Lines out;
        line(out, "RELATIVE_RATE outgroup ", names[outgroup], " pairs ", pairs.size(), " rejected ",
             rejected);
        append(out, pairs);
        const Tree &tree = trees[params.model];
        std::array<double, 32> distances = paths(tree, Rooted(tree, outgroup).root);
        double average = 0;
        for (int t = 0; t < size; ++t)
            if (t != outgroup)
                average += distances[t];
        average /= size - 1;
        double deviation = 0;
        for (int t = 0; t < size; ++t)
            if (t != outgroup)
                deviation += square(distances[t] - average);
        deviation = std::sqrt(deviation / (size - 2));
        line(out, "ROOT_TO_TIP ", methods[params.model], " mean ", real(average, 5), " sd ",
             real(deviation, 5), " cv ", real(deviation / average, 4));
        for (int t = 0; t < size; ++t)
            if (t != outgroup)
                line(out, "TIP ", names[t], " ", real(distances[t], 5));
        return out;
    }
    std::vector<int> quartets(const std::set<Mask> &splits) const {
        std::vector<int> out;
        for (int a = 0; a < size; ++a)
            for (int b = a + 1; b < size; ++b)
                for (int c = b + 1; c < size; ++c)
                    for (int d = c + 1; d < size; ++d) {
                        Mask quartet = (1u << a) | (1u << b) | (1u << c) | (1u << d);
                        int topology = 0, index = 0;
                        for (int other : {b, c, d}) {
                            ++index;
                            Mask side = (1u << a) | (1u << other);
                            for (Mask mask : splits) {
                                Mask intersection = mask & quartet;
                                if (intersection == side || intersection == (quartet ^ side)) {
                                    topology = index;
                                    break;
                                }
                            }
                            if (topology)
                                break;
                        }
                        out.push_back(topology);
                    }
        return out;
    }
    Lines comparison_report() const {
        Lines out;
        std::array<std::set<Mask>, 6> splits;
        std::array<std::vector<int>, 6> topologies;
        std::set<Mask> all_clades;
        for (int i = 0; i < 6; ++i) {
            const Tree &tree = trees[i];
            splits[i] = Rooted(tree, outgroup).splits(tree);
            topologies[i] = quartets(splits[i]);
            all_clades.insert(splits[i].begin(), splits[i].end());
            int supported = 0;
            for (Mask mask : splits[i])
                supported += 2 * support_count(support, mask) > params.replicates;
            std::string parsimony = "-", balanced = "-", length_text = "-", negative = "-",
                        residual = "-", likelihood = "-";
            if (i != 5) {
                int value = i < 3    ? nj_scores[i]
                            : i == 4 ? int(mp.value)
                                     : score(tree, patterns, outgroup);
                parsimony = std::to_string(value);
                balanced = real(bme(tree), 5);
            }
            if (i < 3) {
                double total = 0, error = 0;
                for (const Branch &branch : branches(tree, outgroup))
                    total += tree.length[branch.first][branch.second];
                for (int a = 0; a < size; ++a)
                    for (int b = a + 1; b < size; ++b)
                        error += square(matrices[i][a][b] - patristics[i][a][b]);
                length_text = real(total, 5);
                negative = std::to_string(tree.negative);
                residual = real(error, 6);
                likelihood = real(sum(site_logs[i]), 4);
            } else if (i == 4)
                length_text = real(mp.value / length, 5);
            line(out, "TREE ", methods[i], " splits ", splits[i].size(), " supported ", supported,
                 " parsimony ", parsimony, " bme ", balanced, " length ", length_text, " negative ",
                 negative, " sse ", residual, " loglik ", likelihood);
        }
        for (int type = 0; type < 2; ++type) {
            std::ostringstream heading;
            heading << (type ? "QUARTET" : "RF");
            for (const std::string &method : methods)
                heading << ' ' << method;
            out.push_back(heading.str());
            for (int a = 0; a < 6; ++a) {
                std::ostringstream row;
                row << methods[a];
                for (int b = 0; b < 6; ++b) {
                    int difference = 0;
                    if (type) {
                        for (int i = 0; i < int(topologies[a].size()); ++i)
                            difference += topologies[a][i] != topologies[b][i];
                    } else
                        difference = rf(splits[a], splits[b]);
                    row << ' ' << difference;
                }
                out.push_back(row.str());
            }
        }
        std::map<Mask, double> lengths =
            Rooted(trees[params.model], outgroup).branch_lengths(trees[params.model]);
        std::map<Mask, int> changes;
        for (const Branch &branch : branches(trees[4], outgroup)) {
            std::pair<int, int> key = std::minmax(branch.first, branch.second);
            changes[branch.mask] = reconstruction.changes.at(key);
        }
        for (Mask mask : symbol_order(all_clades, size)) {
            std::string marks;
            for (int i = 0; i < 6; ++i)
                marks += splits[i].count(mask) ? '+' : '-';
            line(out, "CLADE ", symbols(mask, size), " support ", support_count(support, mask),
                 " trees ", marks, " length ",
                 lengths.count(mask) ? real(lengths.at(mask), 5) : "-", " changes ",
                 changes.count(mask) ? std::to_string(changes.at(mask)) : "-");
        }
        return out;
    }
    Lines hypotheses_report() const {
        Lines out;
        std::array<std::set<Mask>, 6> splits;
        for (int i = 0; i < 6; ++i)
            splits[i] = Rooted(trees[i], outgroup).splits(trees[i]);
        Mask ingroup = ((1u << size) - 1) ^ (1u << outgroup), exhaustive_ingroup = 0;
        for (int t : exhaustive.taxa)
            if (t != outgroup)
                exhaustive_ingroup |= 1u << t;
        std::ifstream input("input/clades.txt");
        std::string text;
        while (std::getline(input, text)) {
            std::istringstream row(text);
            std::string hypothesis, name, unknown;
            row >> hypothesis;
            Mask mask = 0;
            while (row >> name) {
                auto found = std::find(names.begin(), names.end(), name);
                if (found == names.end()) {
                    if (unknown.empty())
                        unknown = name;
                } else
                    mask |= 1u << int(found - names.begin());
            }
            if (!unknown.empty()) {
                line(out, "INVALID ", hypothesis, " unknown taxon ", unknown);
                continue;
            }
            if (mask & (1u << outgroup)) {
                line(out, "INVALID ", hypothesis, " contains outgroup");
                continue;
            }
            line(out, "CLADE ", hypothesis, " taxa ", bits(mask), " support ",
                 support_count(support, mask));
            for (int i = 0; i < 6; ++i) {
                Mask common = ingroup;
                for (Mask clade : splits[i])
                    if ((clade & mask) == mask && bits(clade) < bits(common))
                        common = clade;
                std::string intruders;
                for (int t = 0; t < size; ++t)
                    if ((common & ~mask) & (1u << t)) {
                        if (!intruders.empty())
                            intruders += ",";
                        intruders += names[t];
                    }
                line(out, "TEST ", hypothesis, " ", methods[i], " monophyletic ",
                     common == mask ? "yes" : "no", " mrca ", bits(common), " intruders ",
                     intruders.empty() ? "-" : intruders);
            }
            Mask subset = mask & exhaustive_ingroup;
            if (bits(subset) < 2 || bits(subset) >= bits(exhaustive_ingroup)) {
                line(out, "SUBSET ", hypothesis, " untestable");
                continue;
            }
            std::array<int, 2> scores = {std::numeric_limits<int>::max(),
                                         std::numeric_limits<int>::max()};
            std::array<double, 2> balanced = {std::numeric_limits<double>::infinity(),
                                              std::numeric_limits<double>::infinity()};
            for (const ExhaustiveRecord &record : exhaustive.records) {
                int side = record.splits.count(subset) ? 0 : 1;
                scores[side] = std::min(scores[side], record.score);
                balanced[side] = std::min(balanced[side], record.bme);
            }
            line(out, "SUBSET ", hypothesis, " taxa ", bits(subset), " with ", scores[0],
                 " without ", scores[1], " bme_with ", real(balanced[0], 5), " bme_without ",
                 real(balanced[1], 5));
        }
        return out;
    }
    void run() {
        me_start = bme(trees[params.model]);
        me = hill_climb(trees[params.model], [&](const Tree &tree) { return bme(tree); }, me_start);
        trees[3] = me.tree;
        std::vector<int> addition_order = {outgroup};
        for (int t : taxa)
            if (t != outgroup)
                addition_order.push_back(t);
        initial = stepwise(addition_order);
        mp = hill_climb(
            initial.tree, [&](const Tree &tree) { return score(tree, patterns, outgroup); },
            initial.score);
        trees[4] = mp.tree;
        reconstruction = reconstruct(trees[4], patterns, outgroup);
        for (const auto &entry : reconstruction.changes)
            trees[4].connect(entry.first.first, entry.first.second, double(entry.second) / length);
        bounds();
        std::vector<int> exhaustive_order = {outgroup};
        for (int t : taxa)
            if (t != outgroup && std::find(params.exhaustive.begin(), params.exhaustive.end(),
                                           names[t]) != params.exhaustive.end())
                exhaustive_order.push_back(t);
        exhaustive = exhaustive_search(exhaustive_order);
        bootstrap();
        Lines newicks, diagrams;
        for (int i = 0; i < 6; ++i) {
            line(newicks, methods[i], " ",
                 newick(trees[i], names, outgroup, i < 3 || i == 4, i == 5 ? &support : nullptr));
            if (i)
                diagrams.push_back("");
            line(diagrams, "TREE ", methods[i]);
            append(diagrams, cladogram(trees[i], names, outgroup, support));
        }
        std::filesystem::create_directories("output");
        save("summary.txt", summary());
        save("distances.txt", distances_report());
        save("trees.nwk", newicks);
        save("cladograms.txt", diagrams);
        save("parsimony.txt", parsimony_report());
        save("likelihood.txt", likelihood_report());
        save("bootstrap.txt", bootstrap_lines);
        save("clock.txt", clock_report());
        save("comparison.txt", comparison_report());
        save("hypotheses.txt", hypotheses_report());
    }
};
int main() {
    Study study(read_parameters());
    study.run();
}
