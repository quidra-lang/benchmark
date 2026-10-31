#include "mixture.hpp"
#include <filesystem>
template <typename... T> static void line(Lines &out, const T &...values) {
    std::ostringstream text;
    (text << ... << values);
    out.push_back(text.str());
}
static std::string integers(const Ids &values, int offset = 0) {
    std::string out;
    for (int value : values)
        out += (out.empty() ? "" : " ") + std::to_string(value + offset);
    return out;
}
static std::string reals(const Values &values) {
    std::string out;
    for (double value : values)
        out += (out.empty() ? "" : " ") + real(value);
    return out;
}
static std::string optional_real(std::optional<double> value) {
    return value ? real(*value) : "-";
}
struct Summary {
    Fit fit;
    int k, type_order, parameters;
    double bic, aic, icl, entropy;
    Ids assigned, sizes;
    Values entropies;
};
static int parameter_count(int k, Type type) {
    return type == Type::FULL   ? 6 * k - 1
           : type == Type::TIED ? 3 * k + 2
           : type == Type::DIAG ? 5 * k - 1
                                : 4 * k - 1;
}
static Summary summarize(Fit fit, int type_order, int n) {
    Summary out;
    out.k = fit.model.components.size();
    out.parameters = parameter_count(out.k, fit.model.type);
    out.type_order = type_order;
    out.entropy = 0;
    out.sizes.resize(out.k);
    for (const Record &record : fit.e.records) {
        int chosen = 0;
        double entropy = 0;
        for (int k = 0; k < out.k; ++k) {
            if (record.responsibility[k] > record.responsibility[chosen])
                chosen = k;
            if (record.responsibility[k] > 0)
                entropy -= record.responsibility[k] * std::log(record.responsibility[k]);
        }
        out.assigned.push_back(chosen);
        ++out.sizes[chosen];
        out.entropies.push_back(entropy);
        out.entropy += entropy;
    }
    out.bic = -2 * fit.e.loglik + out.parameters * std::log(n);
    out.aic = -2 * fit.e.loglik + 2 * out.parameters;
    out.icl = out.bic + 2 * out.entropy;
    out.fit = std::move(fit);
    return out;
}
static double criterion(const Summary &model, int which) {
    return which == 0 ? model.bic : which == 1 ? model.aic : model.icl;
}
static Ids ranked(const std::vector<Summary> &models, int which) {
    Ids out(models.size());
    std::iota(out.begin(), out.end(), 0);
    std::sort(out.begin(), out.end(), [&](int a, int b) {
        return std::make_tuple(rounded(criterion(models[a], which)), models[a].parameters, models[a].k,
                               models[a].type_order) < std::make_tuple(rounded(criterion(models[b], which)),
                                                                       models[b].parameters, models[b].k,
                                                                       models[b].type_order);
    });
    return out;
}
using Table = std::vector<std::vector<I>>;
static Table contingency(const Ids &a, int rows, const Ids &b, int columns) {
    Table out(rows, std::vector<I>(columns));
    for (int i = 0; i < int(a.size()); ++i)
        ++out[a[i]][b[i]];
    return out;
}
struct Fraction {
    I numerator, denominator;
};
static Fraction ari(const Table &table) {
    I cells = 0, rows = 0, columns = 0, total = 0;
    const int k = table.size(), m = table[0].size();
    auto choose = [](I value) { return value * (value - 1) / 2; };
    for (const auto &row : table) {
        I sum = 0;
        for (I value : row) {
            cells += choose(value);
            sum += value;
        }
        rows += choose(sum);
        total += sum;
    }
    for (int j = 0; j < m; ++j) {
        I sum = 0;
        for (int i = 0; i < k; ++i)
            sum += table[i][j];
        columns += choose(sum);
    }
    const I z = choose(total);
    I numerator = 2 * (z * cells - rows * columns), denominator = z * (rows + columns) - 2 * rows * columns;
    if (denominator == 0)
        return {1, 1};
    if (denominator < 0) {
        numerator = -numerator;
        denominator = -denominator;
    }
    const I divisor = std::gcd(std::abs(numerator), denominator);
    return {numerator / divisor, denominator / divisor};
}
static std::string fraction_text(Fraction value) {
    return std::to_string(value.numerator) + "/" + std::to_string(value.denominator) + " " +
           real(double(value.numerator) / value.denominator);
}
struct Evaluation {
    std::optional<double> silhouette, ch, db;
    std::vector<std::optional<double>> cluster;
};
static Evaluation evaluate(const std::vector<Point> &points, const Ids &labels, int k) {
    const int n = points.size();
    Ids counts(k);
    std::vector<Vec> centers(k);
    Vec global{};
    for (int i = 0; i < n; ++i) {
        ++counts[labels[i]];
        for (int axis = 0; axis < 2; ++axis) {
            centers[labels[i]][axis] += points[i].xy[axis];
            global[axis] += points[i].xy[axis];
        }
    }
    int groups = 0;
    for (int j = 0; j < k; ++j)
        if (counts[j]) {
            ++groups;
            centers[j][0] /= counts[j];
            centers[j][1] /= counts[j];
        }
    global[0] /= n;
    global[1] /= n;
    Evaluation out;
    out.cluster.resize(k);
    if (groups < 2)
        return out;
    Values cluster_sum(k);
    double silhouette = 0;
    for (int i = 0; i < n; ++i) {
        double value = 0;
        if (counts[labels[i]] > 1) {
            Values sums(k);
            for (int j = 0; j < n; ++j)
                if (j != i)
                    sums[labels[j]] += distance(points[i].xy, points[j].xy);
            const double a = sums[labels[i]] / (counts[labels[i]] - 1);
            double b = std::numeric_limits<double>::infinity();
            for (int j = 0; j < k; ++j)
                if (j != labels[i] && counts[j])
                    b = std::min(b, sums[j] / counts[j]);
            value = (b - a) / std::max(a, b);
        }
        silhouette += value;
        cluster_sum[labels[i]] += value;
    }
    out.silhouette = silhouette / n;
    for (int j = 0; j < k; ++j)
        if (counts[j])
            out.cluster[j] = cluster_sum[j] / counts[j];
    double between = 0, within = 0;
    for (int j = 0; j < k; ++j)
        if (counts[j])
            between += counts[j] * distance2(centers[j], global);
    for (int i = 0; i < n; ++i)
        within += distance2(points[i].xy, centers[labels[i]]);
    out.ch = (between / (groups - 1)) / (within / (n - groups));
    Values scatter(k);
    for (int j = 0; j < k; ++j)
        if (counts[j]) {
            for (int i = 0; i < n; ++i)
                if (labels[i] == j)
                    scatter[j] += distance(points[i].xy, centers[j]);
            scatter[j] /= counts[j];
        }
    double db = 0;
    for (int a = 0; a < k; ++a)
        if (counts[a]) {
            double maximum = 0;
            for (int b = 0; b < k; ++b)
                if (b != a && counts[b])
                    maximum = std::max(maximum, (scatter[a] + scatter[b]) / distance(centers[a], centers[b]));
            db += maximum;
        }
    out.db = db / groups;
    return out;
}
static Ids matching(const Table &table) {
    const int k = table.size();
    Ids permutation(k), best;
    std::iota(permutation.begin(), permutation.end(), 0);
    I maximum = -1;
    do {
        I agreement = 0;
        for (int j = 0; j < k; ++j)
            agreement += table[permutation[j]][j];
        if (agreement > maximum) {
            maximum = agreement;
            best = permutation;
        }
    } while (std::next_permutation(permutation.begin(), permutation.end()));
    return best;
}
using Groups = std::vector<Ids>;
static Groups merge_groups(Groups groups, int a, int b) {
    groups[a].insert(groups[a].end(), groups[b].begin(), groups[b].end());
    std::sort(groups[a].begin(), groups[a].end());
    groups.erase(groups.begin() + b);
    return groups;
}
static double group_entropy(const Summary &selected, const Groups &groups, Ids *sizes = nullptr) {
    double total = 0;
    if (sizes)
        sizes->assign(groups.size(), 0);
    for (const Record &record : selected.fit.e.records) {
        Values sums;
        double entropy = 0;
        for (const Ids &group : groups) {
            double sum = 0;
            for (int k : group)
                sum += record.responsibility[k];
            sums.push_back(sum);
            if (sum > 0)
                entropy -= sum * std::log(sum);
        }
        total += entropy;
        if (sizes) {
            int chosen = 0;
            for (int j = 1; j < int(sums.size()); ++j)
                if (sums[j] > sums[chosen])
                    chosen = j;
            ++(*sizes)[chosen];
        }
    }
    return total;
}
static std::string group_name(const Ids &values) {
    std::string out;
    for (int value : values)
        out += (out.empty() ? "" : "+") + std::to_string(value + 1);
    return out;
}
int main() {
    std::filesystem::create_directories("output");
    const Input input = load();
    const auto &points = input.points;
    const Params &p = input.params;
    const int n = points.size();
    std::vector<Summary> models;
    std::array<Kmeans, 5> kmeans;
    for (int k : p.ks) {
        kmeans[k] = run_kmeans(points, input.initial[k], p.kmeans_max);
        for (int order = 0; order < int(p.types.size()); ++order)
            models.push_back(summarize(run_em(points, input.initial[k], p.types[order], p), order, n));
    }
    const Ids bic = ranked(models, 0), aic = ranked(models, 1), icl = ranked(models, 2);
    Ids aic_rank(models.size()), icl_rank(models.size());
    for (int i = 0; i < int(models.size()); ++i) {
        aic_rank[aic[i]] = i + 1;
        icl_rank[icl[i]] = i + 1;
    }
    const Summary &selected = models[bic[0]];
    const int k = selected.k;
    const Type type = selected.fit.model.type;
    const Kmeans &km = kmeans[k];
    std::array<int, 5> best_k{};
    for (int count : p.ks)
        for (int index : bic)
            if (models[index].k == count) {
                best_k[count] = index;
                break;
            }
    Lines model_file, trace, assignments, selection, map_file;
    line(trace, "K,type,iteration,loglik");
    for (int index = 0; index < int(models.size()); ++index) {
        const Summary &model = models[index];
        if (index)
            line(model_file, "");
        line(model_file, "model K=", model.k, " type=", type_name(model.fit.model.type));
        line(model_file, "parameters ", model.parameters);
        line(model_file, "loglik ", real(model.fit.e.loglik));
        line(model_file, "bic ", real(model.bic));
        line(model_file, "aic ", real(model.aic));
        line(model_file, "icl ", real(model.icl));
        line(model_file, "mean_entropy ", real(model.entropy / n));
        line(model_file, "settled_at ", model.fit.settled);
        line(model_file, "largest_increase iteration ", model.fit.largest, " value ",
             real(model.fit.trace[model.fit.largest] - model.fit.trace[model.fit.largest - 1]));
        line(model_file, "violations ", model.fit.violations.size());
        line(model_file, "sizes ", integers(model.sizes));
        for (int j = 0; j < model.k; ++j) {
            const Component &component = model.fit.model.components[j];
            const Eigen e = eigen(component.cov);
            line(model_file, "component ", j + 1, " weight ", real(component.weight), " mean ",
                 real(component.mean[0]), " ", real(component.mean[1]), " cov ", real(component.cov[0]), " ",
                 real(component.cov[1]), " ", real(component.cov[2]), " axes ", real(e.major), " ",
                 real(e.minor), " angle ", real(e.angle));
        }
        for (int t = 0; t <= p.iterations; ++t)
            line(trace, model.k, ",", type_name(model.fit.model.type), ",", t, ",", real(model.fit.trace[t]));
    }
    line(assignments, "id,component,max_responsibility,log_density,kmeans_cluster");
    for (int i = 0; i < n; ++i)
        line(assignments, points[i].id, ",", selected.assigned[i] + 1, ",",
             real(selected.fit.e.records[i].responsibility[selected.assigned[i]]), ",",
             real(selected.fit.e.records[i].log_density), ",", km.assignment[i] + 1);
    line(selection, "ranking by bic");
    line(selection, "rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank");
    for (int rank = 0; rank < int(bic.size()); ++rank) {
        const int index = bic[rank];
        const Summary &model = models[index];
        const double delta = double(rounded(model.bic) - rounded(selected.bic)) / 10000;
        line(selection, rank + 1, " ", model.k, " ", type_name(model.fit.model.type), " ", model.parameters,
             " ", real(model.fit.e.loglik), " ", real(model.bic), " ", real(delta), " ", real(model.aic), " ",
             aic_rank[index], " ", real(model.icl), " ", icl_rank[index]);
    }
    line(selection, "selected K=", k, " type=", type_name(type));
    line(selection, "best_aic K=", models[aic[0]].k, " type=", type_name(models[aic[0]].fit.model.type));
    line(selection, "best_icl K=", models[icl[0]].k, " type=", type_name(models[icl[0]].fit.model.type));
    line(selection, "");
    line(selection, "best K per type");
    for (Type current : p.types) {
        std::array<int, 3> best{};
        for (int which = 0; which < 3; ++which)
            for (int index : which == 0 ? bic : which == 1 ? aic : icl)
                if (models[index].fit.model.type == current) {
                    best[which] = models[index].k;
                    break;
                }
        line(selection, type_name(current), " bic ", best[0], " aic ", best[1], " icl ", best[2]);
    }
    for (int ki = 0; ki < int(p.ks.size()); ++ki) {
        const int count = p.ks[ki];
        const Summary &model = models[best_k[count]];
        const Kmeans &current = kmeans[count];
        const Evaluation a = evaluate(points, model.assigned, count),
                         b = evaluate(points, current.assignment, count);
        line(selection, "");
        line(selection, "K=", count, " type=", type_name(model.fit.model.type), " bic ", real(model.bic));
        line(selection, "  kmeans iterations ", current.iterations, " inertia ", real(current.inertia));
        line(selection, "  ari ",
             fraction_text(ari(contingency(model.assigned, count, current.assignment, count))));
        line(selection, "  silhouette gmm ", optional_real(a.silhouette), " kmeans ",
             optional_real(b.silhouette));
        line(selection, "  calinski_harabasz gmm ", optional_real(a.ch), " kmeans ", optional_real(b.ch));
        line(selection, "  davies_bouldin gmm ", optional_real(a.db), " kmeans ", optional_real(b.db));
        if (ki) {
            const int previous = p.ks[ki - 1];
            const Table table =
                contingency(models[best_k[previous]].assigned, previous, model.assigned, count);
            std::string parents, shared;
            for (int j = 0; j < count; ++j) {
                int parent = 0;
                for (int i = 1; i < previous; ++i)
                    if (table[i][j] > table[parent][j])
                        parent = i;
                parents += (j ? " " : "") + (table[parent][j] ? std::to_string(parent + 1) : "-");
                shared += (j ? " " : "") + std::to_string(table[parent][j]);
            }
            line(selection, "  parents K=", previous, " ", parents, " shared ", shared);
        }
    }
    line(selection, "");
    line(selection, "violations");
    int violation_count = 0;
    for (const Summary &model : models)
        for (int t : model.fit.violations) {
            ++violation_count;
            line(selection, "K=", model.k, " type=", type_name(model.fit.model.type), " iteration ", t,
                 " previous ", real(model.fit.trace[t - 1]), " current ", real(model.fit.trace[t]));
        }
    if (!violation_count)
        line(selection, "none");
    line(selection, "");
    line(selection, "selected components");
    const Evaluation selected_evaluation = evaluate(points, selected.assigned, k);
    for (int j = 0; j < k; ++j) {
        const Component &component = selected.fit.model.components[j];
        const Eigen e = eigen(component.cov);
        double soft = 0;
        int inside1 = 0, inside2 = 0;
        Ids observed(p.gof.size() + 1);
        for (int i = 0; i < n; ++i) {
            soft += selected.fit.e.records[i].responsibility[j];
            if (selected.assigned[i] == j) {
                const double q = mahalanobis(points[i].xy, component.mean, component.cov),
                             radius = std::sqrt(q);
                inside1 += q <= 1;
                inside2 += q <= 4;
                int bin = 0;
                while (bin < int(p.gof.size()) && radius >= p.gof[bin])
                    ++bin;
                ++observed[bin];
            }
        }
        Values expected;
        double chi = 0;
        for (int bin = 0; bin < int(observed.size()); ++bin) {
            const double low = bin ? p.gof[bin - 1] : 0,
                         upper = bin < int(p.gof.size()) ? std::exp(-p.gof[bin] * p.gof[bin] / 2) : 0,
                         value = selected.sizes[j] * (std::exp(-low * low / 2) - upper);
            expected.push_back(value);
            chi += (observed[bin] - value) * (observed[bin] - value) / value;
        }
        line(selection, "component ", j + 1, " weight ", real(component.weight), " size ", selected.sizes[j],
             " soft_size ", real(soft), " mean ", real(component.mean[0]), " ", real(component.mean[1]));
        line(selection, "  cov ", real(component.cov[0]), " ", real(component.cov[1]), " ",
             real(component.cov[2]), " corr ", real(e.correlation));
        line(selection, "  eigen ", real(e.leading), " ", real(e.trailing), " direction ",
             real(e.direction[0]), " ", real(e.direction[1]), " angle ", real(e.angle));
        line(selection, "  axes_1sigma ", real(e.major), " ", real(e.minor), " axes_2sigma ",
             real(2 * e.major), " ", real(2 * e.minor));
        line(selection, "  inside_1sigma ", inside1, " inside_2sigma ", inside2, " area_1sigma ",
             real(e.area));
        line(selection, "  silhouette ", optional_real(selected_evaluation.cluster[j]));
        line(selection, "  gof observed ", integers(observed), " expected ", reals(expected), " chi2 ",
             real(chi));
    }
    line(selection, "");
    line(selection, "overlap");
    if (k == 1)
        line(selection, "none");
    for (int a = 0; a < k; ++a)
        for (int b = a + 1; b < k; ++b) {
            const double d =
                bhattacharyya(selected.fit.model.components[a], selected.fit.model.components[b]);
            double shared = 0;
            for (const Record &record : selected.fit.e.records)
                shared += record.responsibility[a] * record.responsibility[b];
            line(selection, a + 1, "-", b + 1, " bhattacharyya ", real(d), " coefficient ",
                 real(std::exp(-d)), " shared ", real(shared));
        }
    Groups groups;
    for (int j = 0; j < k; ++j)
        groups.push_back({j});
    line(selection, "");
    line(selection, "merging");
    line(selection, "start entropy ", real(group_entropy(selected, groups)));
    for (int step = 1; step < k; ++step) {
        int best_a = 0, best_b = 1;
        I best = std::numeric_limits<I>::max();
        for (int a = 0; a < int(groups.size()); ++a)
            for (int b = a + 1; b < int(groups.size()); ++b) {
                const I value = rounded(group_entropy(selected, merge_groups(groups, a, b)));
                if (value < best) {
                    best = value;
                    best_a = a;
                    best_b = b;
                }
            }
        const std::string a = group_name(groups[best_a]), b = group_name(groups[best_b]);
        groups = merge_groups(groups, best_a, best_b);
        Ids sizes;
        const double entropy = group_entropy(selected, groups, &sizes);
        line(selection, "step ", step, " merge ", a, " ", b, " entropy ", real(entropy), " sizes ",
             integers(sizes));
    }
    const Table table = contingency(selected.assigned, k, km.assignment, k);
    const Ids permutation = matching(table);
    I agreement = 0;
    for (int j = 0; j < k; ++j)
        agreement += table[permutation[j]][j];
    line(selection, "");
    line(selection, "kmeans K=", k);
    line(selection, "iterations ", km.iterations);
    line(selection, "inertia ", real(km.inertia));
    line(selection, "sizes ", integers(km.sizes));
    for (int j = 0; j < k; ++j)
        line(selection, "center ", j + 1, " ", real(km.centers[j][0]), " ", real(km.centers[j][1]));
    line(selection, "contingency");
    for (const auto &row : table) {
        std::string values;
        for (I value : row)
            values += (values.empty() ? "" : " ") + std::to_string(value);
        line(selection, values);
    }
    line(selection, "ari ", fraction_text(ari(table)));
    line(selection, "matching ", integers(permutation, 1));
    line(selection, "agreement ", agreement, "/", n, " ", real(double(agreement) / n));
    int disagreements = 0;
    for (int i = 0; i < n; ++i)
        if (permutation[km.assignment[i]] != selected.assigned[i]) {
            ++disagreements;
            line(selection, "disagree ", points[i].id, " gmm ", selected.assigned[i] + 1, " kmeans ",
                 km.assignment[i] + 1, " max ",
                 real(selected.fit.e.records[i].responsibility[selected.assigned[i]]));
        }
    line(selection, "disagreements ", disagreements);
    Model initial;
    initial.components.resize(k);
    for (int j = 0; j < k; ++j) {
        Component &component = initial.components[j];
        component.weight = double(km.sizes[j]) / n;
        component.mean = km.centers[j];
        Cov scatter{};
        for (int i = 0; i < n; ++i)
            if (km.assignment[i] == j) {
                const double dx = points[i].xy[0] - component.mean[0],
                             dy = points[i].xy[1] - component.mean[1];
                scatter[0] += dx * dx;
                scatter[1] += dx * dy;
                scatter[2] += dy * dy;
            }
        component.cov = {scatter[0] / km.sizes[j] + p.epsilon, scatter[1] / km.sizes[j],
                         scatter[2] / km.sizes[j] + p.epsilon};
    }
    const Summary refit = summarize(run_em(points, initial, type, p), selected.type_order, n);
    line(selection, "");
    line(selection, "refit_from_kmeans K=", k, " type=", type_name(type));
    line(selection, "loglik ", real(refit.fit.e.loglik), " bic ", real(refit.bic), " settled_at ",
         refit.fit.settled);
    line(selection, "sizes ", integers(refit.sizes));
    line(selection, "ari_vs_selected ",
         fraction_text(ari(contingency(selected.assigned, k, refit.assigned, k))));
    line(selection, "");
    line(selection, "cross_validation K=", k, " type=", type_name(type), " folds ", p.folds);
    double total_test = 0;
    for (int fold = 0; fold < p.folds; ++fold) {
        std::vector<Point> train, test;
        for (int i = 0; i < n; ++i)
            (i % p.folds == fold ? test : train).push_back(points[i]);
        const Fit fit = run_em(train, input.initial[k], type, p);
        const double score = expectation(test, fit.model).loglik / test.size();
        total_test += score;
        line(selection, "fold ", fold + 1, " train ", train.size(), " test ", test.size(), " train_loglik ",
             real(fit.e.loglik / train.size()), " test_loglik ", real(score));
    }
    line(selection, "mean_test_loglik ", real(total_test / p.folds));
    Ids uncertain, outliers;
    for (int i = 0; i < n; ++i) {
        if (selected.fit.e.records[i].responsibility[selected.assigned[i]] < p.uncertain)
            uncertain.push_back(i);
        if (selected.fit.e.records[i].log_density < p.low_density)
            outliers.push_back(i);
    }
    std::stable_sort(uncertain.begin(), uncertain.end(), [&](int a, int b) {
        return rounded(selected.fit.e.records[a].responsibility[selected.assigned[a]]) <
               rounded(selected.fit.e.records[b].responsibility[selected.assigned[b]]);
    });
    std::stable_sort(outliers.begin(), outliers.end(), [&](int a, int b) {
        return rounded(selected.fit.e.records[a].log_density) <
               rounded(selected.fit.e.records[b].log_density);
    });
    line(selection, "");
    line(selection, "uncertain threshold ", real(p.uncertain));
    for (int i : uncertain) {
        Values responsibilities;
        for (int j = 0; j < k; ++j)
            responsibilities.push_back(selected.fit.e.records[i].responsibility[j]);
        line(selection, points[i].id, " component ", selected.assigned[i] + 1, " max ",
             real(selected.fit.e.records[i].responsibility[selected.assigned[i]]), " responsibilities ",
             reals(responsibilities));
    }
    line(selection, "count ", uncertain.size());
    line(selection, "");
    line(selection, "outliers threshold ", real(p.low_density));
    for (int i : outliers) {
        const int j = selected.assigned[i];
        const Component &component = selected.fit.model.components[j];
        line(selection, points[i].id, " component ", j + 1, " log_density ",
             real(selected.fit.e.records[i].log_density), " q ",
             real(mahalanobis(points[i].xy, component.mean, component.cov)));
    }
    line(selection, "count ", outliers.size());
    const double step_x = (p.xmax - p.xmin) / p.width, step_y = (p.ymax - p.ymin) / p.height;
    auto center = [&](int x, int y) { return Vec{p.xmin + (x + 0.5) * step_x, p.ymax - (y + 0.5) * step_y}; };
    auto cell = [&](Vec xy) {
        const double x = std::floor((xy[0] - p.xmin) / step_x);
        const double y = std::floor((p.ymax - xy[1]) / step_y);
        if (x < 0 || x >= p.width || y < 0 || y >= p.height)
            return std::array<int, 2>{-1, -1};
        return std::array<int, 2>{int(x), int(y)};
    };
    auto inside_map = [&](std::array<int, 2> position) {
        return position[0] >= 0 && position[0] < p.width && position[1] >= 0 && position[1] < p.height;
    };
    Values densities;
    std::vector<Record> map_records;
    double fmax = 0, mass = 0;
    for (int y = 0; y < p.height; ++y)
        for (int x = 0; x < p.width; ++x) {
            const Point point{"", center(x, y)};
            const Record record = expectation({point}, selected.fit.model).records[0];
            double density = 0;
            for (int j = 0; j < k; ++j)
                density += std::exp(record.scores[j]);
            densities.push_back(density);
            map_records.push_back(record);
            fmax = std::max(fmax, density);
            mass += density;
        }
    mass *= step_x;
    mass *= step_y;
    Grid density(p.height, std::string(p.width, ' ')), region = density, uncertainty = density,
                                                       point_map = density;
    std::array<int, 10> levels{};
    const std::string characters = " .:-=+*#%@";
    for (int y = 0; y < p.height; ++y)
        for (int x = 0; x < p.width; ++x) {
            const int index = y * p.width + x,
                      level = std::min(9, int(std::floor(10 * densities[index] / fmax)));
            ++levels[level];
            density[y][x] = characters[level];
            const Record &record = map_records[index];
            int chosen = 0;
            double entropy = 0;
            for (int j = 0; j < k; ++j) {
                if (record.scores[j] > record.scores[chosen])
                    chosen = j;
                if (record.responsibility[j] > 0)
                    entropy -= record.responsibility[j] * std::log(record.responsibility[j]);
            }
            region[y][x] = char('1' + chosen);
            if (k >= 2)
                uncertainty[y][x] =
                    characters[std::max(0, std::min(9, int(std::floor(10 * entropy / std::log(k)))))];
            for (int j = 0; j < k; ++j) {
                const Component &component = selected.fit.model.components[j];
                if (mahalanobis(center(x, y), component.mean, component.cov) > 4)
                    continue;
                bool contour = false;
                for (auto offset : std::array<std::array<int, 2>, 4>{{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}}) {
                    const int xx = x + offset[0], yy = y + offset[1];
                    if (inside_map({xx, yy}) &&
                        mahalanobis(center(xx, yy), component.mean, component.cov) > 4)
                        contour = true;
                }
                if (contour)
                    point_map[y][x] = '.';
            }
        }
    for (int j = 0; j < k; ++j) {
        const auto position = cell(selected.fit.model.components[j].mean);
        if (inside_map(position))
            density[position[1]][position[0]] = char('1' + j);
    }
    std::vector<int> occupied(p.width * p.height, -1);
    int outside = 0;
    for (int i = 0; i < n; ++i) {
        const auto position = cell(points[i].xy);
        if (!inside_map(position)) {
            ++outside;
            continue;
        }
        const int index = position[1] * p.width + position[0];
        if (occupied[index] == -1)
            occupied[index] = selected.assigned[i];
        else if (occupied[index] != selected.assigned[i])
            occupied[index] = -2;
        point_map[position[1]][position[0]] = occupied[index] == -2 ? '*' : char('1' + occupied[index]);
    }
    line(map_file, "density K=", k, " type=", type_name(type));
    line(map_file, "x ", real(p.xmin), " ", real(p.xmax), " y ", real(p.ymin), " ", real(p.ymax), " grid ",
         p.width, "x", p.height);
    line(map_file, "max_density ", real(fmax, 6), " mass_in_map ", real(mass));
    frame(map_file, density);
    for (int level = 0; level < 10; ++level)
        line(map_file, "level ", level, " \"", characters[level], "\" from ", real(level * fmax / 10, 6),
             " cells ", levels[level]);
    line(map_file, "");
    line(map_file, "regions");
    frame(map_file, region);
    line(map_file, "");
    line(map_file, "uncertainty");
    frame(map_file, uncertainty);
    line(map_file, "");
    line(map_file, "points");
    frame(map_file, point_map);
    line(map_file, "outside ", outside);
    save("models.txt", model_file);
    save("loglik_trace.csv", trace);
    save("assignments.csv", assignments);
    save("selection.txt", selection);
    save("density_map.txt", map_file);
}
