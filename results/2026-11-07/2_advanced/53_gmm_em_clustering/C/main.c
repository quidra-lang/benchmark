#include "mixture.h"
typedef struct {
    Fit fit;
    int k, type_order, parameters, assigned[300], sizes[4];
    double bic, aic, icl, entropy, entropies[300];
} Summary;
typedef struct {
    I data[4][4];
    int rows, columns;
} Table;
typedef struct {
    I numerator, denominator;
} Fraction;
typedef struct {
    bool available, cluster_available[4];
    double silhouette, ch, db, cluster[4];
} Evaluation;
typedef struct {
    int data[4][4], sizes[4], count;
} Groups;
typedef struct {
    int x, y;
    bool inside;
} Cell;
static char *join(char *const *values, int count, const char *separator) {
    size_t length = 1;
    for (int i = 0; i < count; ++i)
        length += strlen(values[i]) + (i ? strlen(separator) : 0);
    char *out = allocate(length, 1);
    size_t offset = 0;
    for (int i = 0; i < count; ++i) {
        if (i) {
            size_t n = strlen(separator);
            memcpy(out + offset, separator, n);
            offset += n;
        }
        size_t n = strlen(values[i]);
        memcpy(out + offset, values[i], n);
        offset += n;
    }
    return out;
}
static char *integers(const int *values, int count, int offset) {
    char **strings = allocate(count, sizeof(char *));
    for (int i = 0; i < count; ++i)
        strings[i] = format("%d", values[i] + offset);
    return join(strings, count, " ");
}
static char *reals(const double *values, int count) {
    char **strings = allocate(count, sizeof(char *));
    for (int i = 0; i < count; ++i)
        strings[i] = real(values[i], 4);
    return join(strings, count, " ");
}
static char *optional_real(bool available, double value) {
    return available ? real(value, 4) : "-";
}
static int parameter_count(int k, Type type) {
    return type == FULL ? 6 * k - 1 : type == TIED ? 3 * k + 2 : type == DIAG ? 5 * k - 1 : 4 * k - 1;
}
static void summarize(Summary *out, int type_order, int n) {
    Fit *fit = &out->fit;
    out->k = fit->model.k;
    out->parameters = parameter_count(out->k, fit->model.type);
    out->type_order = type_order;
    out->entropy = 0;
    memset(out->sizes, 0, sizeof(out->sizes));
    for (int i = 0; i < n; ++i) {
        Record record = fit->e.records[i];
        int chosen = 0;
        double entropy = 0;
        for (int k = 0; k < out->k; ++k) {
            if (record.responsibility[k] > record.responsibility[chosen])
                chosen = k;
            if (record.responsibility[k] > 0)
                entropy -= record.responsibility[k] * log(record.responsibility[k]);
        }
        out->assigned[i] = chosen;
        ++out->sizes[chosen];
        out->entropies[i] = entropy;
        out->entropy += entropy;
    }
    out->bic = -2 * fit->e.loglik + out->parameters * log(n);
    out->aic = -2 * fit->e.loglik + 2 * out->parameters;
    out->icl = out->bic + 2 * out->entropy;
}
static double criterion(const Summary *model, int which) {
    return which == 0 ? model->bic : which == 1 ? model->aic : model->icl;
}
static bool rank_less(const Summary *a, const Summary *b, int which) {
    I x = rounded(criterion(a, which), 4), y = rounded(criterion(b, which), 4);
    if (x != y)
        return x < y;
    if (a->parameters != b->parameters)
        return a->parameters < b->parameters;
    if (a->k != b->k)
        return a->k < b->k;
    return a->type_order < b->type_order;
}
static void ranked(const Summary *models, int count, int which, int *result) {
    for (int i = 0; i < count; ++i) {
        int j = i;
        while (j > 0 && rank_less(&models[i], &models[result[j - 1]], which)) {
            result[j] = result[j - 1];
            --j;
        }
        result[j] = i;
    }
}
static Table contingency(const int *a, int rows, const int *b, int columns, int count) {
    Table out = {.rows = rows, .columns = columns};
    for (int i = 0; i < count; ++i)
        ++out.data[a[i]][b[i]];
    return out;
}
static I choose(I n) {
    return n * (n - 1) / 2;
}
static Fraction ari(Table table) {
    I cells = 0, rows = 0, columns = 0, total = 0;
    for (int a = 0; a < table.rows; ++a) {
        I sum = 0;
        for (int b = 0; b < table.columns; ++b) {
            cells += choose(table.data[a][b]);
            sum += table.data[a][b];
        }
        rows += choose(sum);
        total += sum;
    }
    for (int b = 0; b < table.columns; ++b) {
        I sum = 0;
        for (int a = 0; a < table.rows; ++a)
            sum += table.data[a][b];
        columns += choose(sum);
    }
    I z = choose(total), numerator = 2 * (z * cells - rows * columns),
      denominator = z * (rows + columns) - 2 * rows * columns;
    if (!denominator)
        return (Fraction){1, 1};
    if (denominator < 0) {
        numerator = -numerator;
        denominator = -denominator;
    }
    I a = numerator < 0 ? -numerator : numerator, b = denominator;
    while (b) {
        I remainder = a % b;
        a = b;
        b = remainder;
    }
    return (Fraction){numerator / a, denominator / a};
}
static char *fraction_text(Fraction value) {
    return format("%" PRId64 "/%" PRId64 " %s", value.numerator, value.denominator,
                  real((double)value.numerator / (double)value.denominator, 4));
}
static Evaluation evaluate(const Point *points, int n, const int *labels, int k) {
    int counts[4] = {0};
    Vec centers[4] = {0}, global = {0};
    for (int i = 0; i < n; ++i) {
        ++counts[labels[i]];
        centers[labels[i]].x += points[i].xy.x;
        centers[labels[i]].y += points[i].xy.y;
        global.x += points[i].xy.x;
        global.y += points[i].xy.y;
    }
    int groups = 0;
    for (int j = 0; j < k; ++j)
        if (counts[j]) {
            ++groups;
            centers[j].x /= counts[j];
            centers[j].y /= counts[j];
        }
    global.x /= n;
    global.y /= n;
    Evaluation out = {0};
    if (groups < 2)
        return out;
    out.available = true;
    double cluster_sum[4] = {0}, silhouette = 0;
    for (int i = 0; i < n; ++i) {
        double value = 0;
        if (counts[labels[i]] > 1) {
            double sums[4] = {0};
            for (int j = 0; j < n; ++j)
                if (j != i)
                    sums[labels[j]] += distance(points[i].xy, points[j].xy);
            double a = sums[labels[i]] / (counts[labels[i]] - 1), b = INFINITY;
            for (int j = 0; j < k; ++j)
                if (j != labels[i] && counts[j]) {
                    double candidate = sums[j] / counts[j];
                    if (candidate < b)
                        b = candidate;
                }
            value = (b - a) / (a > b ? a : b);
        }
        silhouette += value;
        cluster_sum[labels[i]] += value;
    }
    out.silhouette = silhouette / n;
    for (int j = 0; j < k; ++j)
        if (counts[j]) {
            out.cluster_available[j] = true;
            out.cluster[j] = cluster_sum[j] / counts[j];
        }
    double between = 0, within = 0;
    for (int j = 0; j < k; ++j)
        if (counts[j])
            between += counts[j] * distance2(centers[j], global);
    for (int i = 0; i < n; ++i)
        within += distance2(points[i].xy, centers[labels[i]]);
    out.ch = (between / (groups - 1)) / (within / (n - groups));
    double scatter[4] = {0};
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
                if (b != a && counts[b]) {
                    double value = (scatter[a] + scatter[b]) / distance(centers[a], centers[b]);
                    if (value > maximum)
                        maximum = value;
                }
            db += maximum;
        }
    out.db = db / groups;
    return out;
}
static bool next_permutation(int *values, int count) {
    int i = count - 2;
    while (i >= 0 && values[i] >= values[i + 1])
        --i;
    if (i < 0)
        return false;
    int j = count - 1;
    while (values[j] <= values[i])
        --j;
    int swap = values[i];
    values[i] = values[j];
    values[j] = swap;
    for (int a = i + 1, b = count - 1; a < b; ++a, --b) {
        swap = values[a];
        values[a] = values[b];
        values[b] = swap;
    }
    return true;
}
static void matching(Table table, int *best) {
    int permutation[4] = {0, 1, 2, 3};
    I maximum = -1;
    do {
        I agreement = 0;
        for (int j = 0; j < table.rows; ++j)
            agreement += table.data[permutation[j]][j];
        if (agreement > maximum) {
            maximum = agreement;
            memcpy(best, permutation, table.rows * sizeof(int));
        }
    } while (next_permutation(permutation, table.rows));
}
static Groups merge_groups(Groups groups, int a, int b) {
    for (int i = 0; i < groups.sizes[b]; ++i)
        groups.data[a][groups.sizes[a]++] = groups.data[b][i];
    for (int i = 1; i < groups.sizes[a]; ++i) {
        int value = groups.data[a][i], j = i;
        while (j > 0 && groups.data[a][j - 1] > value) {
            groups.data[a][j] = groups.data[a][j - 1];
            --j;
        }
        groups.data[a][j] = value;
    }
    for (int i = b; i < groups.count - 1; ++i) {
        memcpy(groups.data[i], groups.data[i + 1], 4 * sizeof(int));
        groups.sizes[i] = groups.sizes[i + 1];
    }
    --groups.count;
    return groups;
}
static double group_entropy(const Summary *selected, int count, Groups groups, int *sizes) {
    double total = 0;
    if (sizes)
        memset(sizes, 0, groups.count * sizeof(int));
    for (int i = 0; i < count; ++i) {
        Record record = selected->fit.e.records[i];
        double sums[4] = {0}, entropy = 0;
        for (int g = 0; g < groups.count; ++g) {
            for (int j = 0; j < groups.sizes[g]; ++j)
                sums[g] += record.responsibility[groups.data[g][j]];
            if (sums[g] > 0)
                entropy -= sums[g] * log(sums[g]);
        }
        total += entropy;
        if (sizes) {
            int chosen = 0;
            for (int j = 1; j < groups.count; ++j)
                if (sums[j] > sums[chosen])
                    chosen = j;
            ++sizes[chosen];
        }
    }
    return total;
}
static char *group_name(const int *values, int count) {
    char *names[4];
    for (int i = 0; i < count; ++i)
        names[i] = format("%d", values[i] + 1);
    return join(names, count, "+");
}
static char **grid(int width, int height) {
    char **out = allocate(height, sizeof(char *));
    for (int y = 0; y < height; ++y) {
        out[y] = allocate(width + 1, 1);
        memset(out[y], ' ', width);
    }
    return out;
}
static Vec center(int x, int y, const Params *p, double step_x, double step_y) {
    return (Vec){p->xmin + (x + 0.5) * step_x, p->ymax - (y + 0.5) * step_y};
}
static Cell cell(Vec xy, const Params *p, double step_x, double step_y) {
    double x = floor((xy.x - p->xmin) / step_x), y = floor((p->ymax - xy.y) / step_y);
    if (x < 0 || x >= p->width || y < 0 || y >= p->height)
        return (Cell){0};
    return (Cell){(int)x, (int)y, true};
}
static void sort_points(int *indices, int count, const Summary *selected, bool density) {
    for (int i = 1; i < count; ++i) {
        int value = indices[i], j = i;
        double metric = density ? selected->fit.e.records[value].log_density
                                : selected->fit.e.records[value].responsibility[selected->assigned[value]];
        I key = rounded(metric, 4);
        while (j > 0) {
            int other = indices[j - 1];
            double previous = density
                                  ? selected->fit.e.records[other].log_density
                                  : selected->fit.e.records[other].responsibility[selected->assigned[other]];
            if (rounded(previous, 4) <= key)
                break;
            indices[j] = other;
            --j;
        }
        indices[j] = value;
    }
}
int main(void) {
    mkdir("output", 0777);
    Input *input = allocate(1, sizeof(Input));
    load(input);
    Point *points = input->points;
    Params *p = &input->params;
    int n = input->count, model_count = 0;
    Summary *models = allocate(16, sizeof(Summary));
    Kmeans kmeans[5] = {0};
    for (int ki = 0; ki < p->k_count; ++ki) {
        int k = p->ks[ki];
        kmeans[k] = run_kmeans(points, n, input->initial[k], p->kmeans_max);
        for (int order = 0; order < p->type_count; ++order) {
            Summary *model = &models[model_count++];
            run_em(points, n, input->initial[k], p->types[order], p, &model->fit);
            summarize(model, order, n);
        }
    }
    int bic[16], aic[16], icl[16], aic_rank[16], icl_rank[16];
    ranked(models, model_count, 0, bic);
    ranked(models, model_count, 1, aic);
    ranked(models, model_count, 2, icl);
    for (int i = 0; i < model_count; ++i) {
        aic_rank[aic[i]] = i + 1;
        icl_rank[icl[i]] = i + 1;
    }
    Summary *selected = &models[bic[0]];
    int k = selected->k;
    Type type = selected->fit.model.type;
    Kmeans *km = &kmeans[k];
    int best_k[5] = {0};
    for (int ki = 0; ki < p->k_count; ++ki)
        for (int rank = 0; rank < model_count; ++rank)
            if (models[bic[rank]].k == p->ks[ki]) {
                best_k[p->ks[ki]] = bic[rank];
                break;
            }
    Lines model_file = {0}, trace = {0}, assignments = {0}, selection = {0}, map_file = {0};
    line(&trace, "K,type,iteration,loglik");
    for (int index = 0; index < model_count; ++index) {
        Summary *model = &models[index];
        if (index)
            line(&model_file, "");
        line(&model_file, "model K=%d type=%s", model->k, type_name(model->fit.model.type));
        line(&model_file, "parameters %d", model->parameters);
        line(&model_file, "loglik %s", real(model->fit.e.loglik, 4));
        line(&model_file, "bic %s", real(model->bic, 4));
        line(&model_file, "aic %s", real(model->aic, 4));
        line(&model_file, "icl %s", real(model->icl, 4));
        line(&model_file, "mean_entropy %s", real(model->entropy / n, 4));
        line(&model_file, "settled_at %d", model->fit.settled);
        line(&model_file, "largest_increase iteration %d value %s", model->fit.largest,
             real(model->fit.trace[model->fit.largest] - model->fit.trace[model->fit.largest - 1], 4));
        line(&model_file, "violations %d", model->fit.violation_count);
        line(&model_file, "sizes %s", integers(model->sizes, model->k, 0));
        for (int j = 0; j < model->k; ++j) {
            Component component = model->fit.model.components[j];
            Eigen e = eigen(component.cov);
            line(&model_file, "component %d weight %s mean %s %s cov %s %s %s axes %s %s angle %s", j + 1,
                 real(component.weight, 4), real(component.mean.x, 4), real(component.mean.y, 4),
                 real(component.cov.a, 4), real(component.cov.b, 4), real(component.cov.c, 4),
                 real(e.major, 4), real(e.minor, 4), real(e.angle, 4));
        }
        for (int t = 0; t <= p->iterations; ++t)
            line(&trace, "%d,%s,%d,%s", model->k, type_name(model->fit.model.type), t,
                 real(model->fit.trace[t], 4));
    }
    line(&assignments, "id,component,max_responsibility,log_density,kmeans_cluster");
    for (int i = 0; i < n; ++i)
        line(&assignments, "%s,%d,%s,%s,%d", points[i].id, selected->assigned[i] + 1,
             real(selected->fit.e.records[i].responsibility[selected->assigned[i]], 4),
             real(selected->fit.e.records[i].log_density, 4), km->assignment[i] + 1);
    line(&selection, "ranking by bic");
    line(&selection, "rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank");
    for (int rank = 0; rank < model_count; ++rank) {
        int index = bic[rank];
        Summary *model = &models[index];
        double delta = (double)(rounded(model->bic, 4) - rounded(selected->bic, 4)) / 10000;
        line(&selection, "%d %d %s %d %s %s %s %s %d %s %d", rank + 1, model->k,
             type_name(model->fit.model.type), model->parameters, real(model->fit.e.loglik, 4),
             real(model->bic, 4), real(delta, 4), real(model->aic, 4), aic_rank[index], real(model->icl, 4),
             icl_rank[index]);
    }
    line(&selection, "selected K=%d type=%s", k, type_name(type));
    line(&selection, "best_aic K=%d type=%s", models[aic[0]].k, type_name(models[aic[0]].fit.model.type));
    line(&selection, "best_icl K=%d type=%s", models[icl[0]].k, type_name(models[icl[0]].fit.model.type));
    line(&selection, "");
    line(&selection, "best K per type");
    for (int ti = 0; ti < p->type_count; ++ti) {
        int best[3] = {0};
        int *rankings[] = {bic, aic, icl};
        for (int which = 0; which < 3; ++which)
            for (int rank = 0; rank < model_count; ++rank) {
                int index = rankings[which][rank];
                if (models[index].fit.model.type == p->types[ti]) {
                    best[which] = models[index].k;
                    break;
                }
            }
        line(&selection, "%s bic %d aic %d icl %d", type_name(p->types[ti]), best[0], best[1], best[2]);
    }
    for (int ki = 0; ki < p->k_count; ++ki) {
        int count = p->ks[ki];
        Summary *model = &models[best_k[count]];
        Kmeans *current = &kmeans[count];
        Evaluation a = evaluate(points, n, model->assigned, count),
                   b = evaluate(points, n, current->assignment, count);
        line(&selection, "");
        line(&selection, "K=%d type=%s bic %s", count, type_name(model->fit.model.type), real(model->bic, 4));
        line(&selection, "  kmeans iterations %d inertia %s", current->iterations, real(current->inertia, 4));
        line(&selection, "  ari %s",
             fraction_text(ari(contingency(model->assigned, count, current->assignment, count, n))));
        line(&selection, "  silhouette gmm %s kmeans %s", optional_real(a.available, a.silhouette),
             optional_real(b.available, b.silhouette));
        line(&selection, "  calinski_harabasz gmm %s kmeans %s", optional_real(a.available, a.ch),
             optional_real(b.available, b.ch));
        line(&selection, "  davies_bouldin gmm %s kmeans %s", optional_real(a.available, a.db),
             optional_real(b.available, b.db));
        if (ki) {
            int previous = p->ks[ki - 1];
            Table table = contingency(models[best_k[previous]].assigned, previous, model->assigned, count, n);
            char *parents[4];
            int shared[4];
            for (int j = 0; j < count; ++j) {
                int parent = 0;
                for (int i = 1; i < previous; ++i)
                    if (table.data[i][j] > table.data[parent][j])
                        parent = i;
                parents[j] = table.data[parent][j] ? format("%d", parent + 1) : "-";
                shared[j] = (int)table.data[parent][j];
            }
            line(&selection, "  parents K=%d %s shared %s", previous, join(parents, count, " "),
                 integers(shared, count, 0));
        }
    }
    line(&selection, "");
    line(&selection, "violations");
    int violation_count = 0;
    for (int mi = 0; mi < model_count; ++mi) {
        Summary *model = &models[mi];
        for (int i = 0; i < model->fit.violation_count; ++i) {
            int t = model->fit.violations[i];
            ++violation_count;
            line(&selection, "K=%d type=%s iteration %d previous %s current %s", model->k,
                 type_name(model->fit.model.type), t, real(model->fit.trace[t - 1], 4),
                 real(model->fit.trace[t], 4));
        }
    }
    if (!violation_count)
        line(&selection, "none");
    line(&selection, "");
    line(&selection, "selected components");
    Evaluation selected_evaluation = evaluate(points, n, selected->assigned, k);
    for (int j = 0; j < k; ++j) {
        Component component = selected->fit.model.components[j];
        Eigen e = eigen(component.cov);
        double soft = 0;
        int inside1 = 0, inside2 = 0, bins = p->gof_count + 1;
        int *observed = allocate(bins, sizeof(int));
        for (int i = 0; i < n; ++i) {
            soft += selected->fit.e.records[i].responsibility[j];
            if (selected->assigned[i] == j) {
                double q = mahalanobis(points[i].xy, component.mean, component.cov), radius = sqrt(q);
                inside1 += q <= 1;
                inside2 += q <= 4;
                int bin = 0;
                while (bin < p->gof_count && radius >= p->gof[bin])
                    ++bin;
                ++observed[bin];
            }
        }
        double *expected = allocate(bins, sizeof(double));
        double chi = 0;
        for (int bin = 0; bin < bins; ++bin) {
            double low = bin ? p->gof[bin - 1] : 0,
                   upper = bin < p->gof_count ? exp(-p->gof[bin] * p->gof[bin] / 2) : 0,
                   value = selected->sizes[j] * (exp(-low * low / 2) - upper);
            expected[bin] = value;
            chi += (observed[bin] - value) * (observed[bin] - value) / value;
        }
        line(&selection, "component %d weight %s size %d soft_size %s mean %s %s", j + 1,
             real(component.weight, 4), selected->sizes[j], real(soft, 4), real(component.mean.x, 4),
             real(component.mean.y, 4));
        line(&selection, "  cov %s %s %s corr %s", real(component.cov.a, 4), real(component.cov.b, 4),
             real(component.cov.c, 4), real(e.correlation, 4));
        line(&selection, "  eigen %s %s direction %s %s angle %s", real(e.leading, 4), real(e.trailing, 4),
             real(e.direction.x, 4), real(e.direction.y, 4), real(e.angle, 4));
        line(&selection, "  axes_1sigma %s %s axes_2sigma %s %s", real(e.major, 4), real(e.minor, 4),
             real(2 * e.major, 4), real(2 * e.minor, 4));
        line(&selection, "  inside_1sigma %d inside_2sigma %d area_1sigma %s", inside1, inside2,
             real(e.area, 4));
        line(&selection, "  silhouette %s",
             optional_real(selected_evaluation.cluster_available[j], selected_evaluation.cluster[j]));
        line(&selection, "  gof observed %s expected %s chi2 %s", integers(observed, bins, 0),
             reals(expected, bins), real(chi, 4));
    }
    line(&selection, "");
    line(&selection, "overlap");
    if (k == 1)
        line(&selection, "none");
    for (int a = 0; a < k; ++a)
        for (int b = a + 1; b < k; ++b) {
            double d = bhattacharyya(selected->fit.model.components[a], selected->fit.model.components[b]),
                   shared = 0;
            for (int i = 0; i < n; ++i)
                shared += selected->fit.e.records[i].responsibility[a] *
                          selected->fit.e.records[i].responsibility[b];
            line(&selection, "%d-%d bhattacharyya %s coefficient %s shared %s", a + 1, b + 1, real(d, 4),
                 real(exp(-d), 4), real(shared, 4));
        }
    Groups groups = {.count = k};
    for (int j = 0; j < k; ++j) {
        groups.data[j][0] = j;
        groups.sizes[j] = 1;
    }
    line(&selection, "");
    line(&selection, "merging");
    line(&selection, "start entropy %s", real(group_entropy(selected, n, groups, NULL), 4));
    for (int step = 1; step < k; ++step) {
        int best_a = 0, best_b = 1;
        I best = INT64_MAX;
        for (int a = 0; a < groups.count; ++a)
            for (int b = a + 1; b < groups.count; ++b) {
                I value = rounded(group_entropy(selected, n, merge_groups(groups, a, b), NULL), 4);
                if (value < best) {
                    best = value;
                    best_a = a;
                    best_b = b;
                }
            }
        char *a = group_name(groups.data[best_a], groups.sizes[best_a]);
        char *b = group_name(groups.data[best_b], groups.sizes[best_b]);
        groups = merge_groups(groups, best_a, best_b);
        int sizes[4];
        double entropy = group_entropy(selected, n, groups, sizes);
        line(&selection, "step %d merge %s %s entropy %s sizes %s", step, a, b, real(entropy, 4),
             integers(sizes, groups.count, 0));
    }
    Table table = contingency(selected->assigned, k, km->assignment, k, n);
    int permutation[4];
    matching(table, permutation);
    I agreement = 0;
    for (int j = 0; j < k; ++j)
        agreement += table.data[permutation[j]][j];
    line(&selection, "");
    line(&selection, "kmeans K=%d", k);
    line(&selection, "iterations %d", km->iterations);
    line(&selection, "inertia %s", real(km->inertia, 4));
    line(&selection, "sizes %s", integers(km->sizes, k, 0));
    for (int j = 0; j < k; ++j)
        line(&selection, "center %d %s %s", j + 1, real(km->centers[j].x, 4), real(km->centers[j].y, 4));
    line(&selection, "contingency");
    for (int a = 0; a < k; ++a) {
        int values[4];
        for (int b = 0; b < k; ++b)
            values[b] = (int)table.data[a][b];
        line(&selection, "%s", integers(values, k, 0));
    }
    line(&selection, "ari %s", fraction_text(ari(table)));
    line(&selection, "matching %s", integers(permutation, k, 1));
    line(&selection, "agreement %" PRId64 "/%d %s", agreement, n, real((double)agreement / n, 4));
    int disagreements = 0;
    for (int i = 0; i < n; ++i)
        if (permutation[km->assignment[i]] != selected->assigned[i]) {
            ++disagreements;
            line(&selection, "disagree %s gmm %d kmeans %d max %s", points[i].id, selected->assigned[i] + 1,
                 km->assignment[i] + 1,
                 real(selected->fit.e.records[i].responsibility[selected->assigned[i]], 4));
        }
    line(&selection, "disagreements %d", disagreements);
    Model initial = {.k = k};
    for (int j = 0; j < k; ++j) {
        Component *component = &initial.components[j];
        component->weight = (double)km->sizes[j] / n;
        component->mean = km->centers[j];
        Cov scatter = {0};
        for (int i = 0; i < n; ++i)
            if (km->assignment[i] == j) {
                double dx = points[i].xy.x - component->mean.x, dy = points[i].xy.y - component->mean.y;
                scatter.a += dx * dx;
                scatter.b += dx * dy;
                scatter.c += dy * dy;
            }
        component->cov = (Cov){scatter.a / km->sizes[j] + p->epsilon, scatter.b / km->sizes[j],
                               scatter.c / km->sizes[j] + p->epsilon};
    }
    Summary *refit = allocate(1, sizeof(Summary));
    run_em(points, n, initial, type, p, &refit->fit);
    summarize(refit, selected->type_order, n);
    line(&selection, "");
    line(&selection, "refit_from_kmeans K=%d type=%s", k, type_name(type));
    line(&selection, "loglik %s bic %s settled_at %d", real(refit->fit.e.loglik, 4), real(refit->bic, 4),
         refit->fit.settled);
    line(&selection, "sizes %s", integers(refit->sizes, k, 0));
    line(&selection, "ari_vs_selected %s",
         fraction_text(ari(contingency(selected->assigned, k, refit->assigned, k, n))));
    line(&selection, "");
    line(&selection, "cross_validation K=%d type=%s folds %d", k, type_name(type), p->folds);
    double total_test = 0;
    Point train[300], test[300];
    Fit *fit = allocate(1, sizeof(Fit));
    Expectation *test_e = allocate(1, sizeof(Expectation));
    for (int fold = 0; fold < p->folds; ++fold) {
        int train_count = 0, test_count = 0;
        for (int i = 0; i < n; ++i)
            if (i % p->folds == fold)
                test[test_count++] = points[i];
            else
                train[train_count++] = points[i];
        run_em(train, train_count, input->initial[k], type, p, fit);
        expectation(test, test_count, fit->model, test_e);
        double score = test_e->loglik / test_count;
        total_test += score;
        line(&selection, "fold %d train %d test %d train_loglik %s test_loglik %s", fold + 1, train_count,
             test_count, real(fit->e.loglik / train_count, 4), real(score, 4));
    }
    line(&selection, "mean_test_loglik %s", real(total_test / p->folds, 4));
    int uncertain[300], outliers[300], uncertain_count = 0, outlier_count = 0;
    for (int i = 0; i < n; ++i) {
        if (selected->fit.e.records[i].responsibility[selected->assigned[i]] < p->uncertain)
            uncertain[uncertain_count++] = i;
        if (selected->fit.e.records[i].log_density < p->low_density)
            outliers[outlier_count++] = i;
    }
    sort_points(uncertain, uncertain_count, selected, false);
    sort_points(outliers, outlier_count, selected, true);
    line(&selection, "");
    line(&selection, "uncertain threshold %s", real(p->uncertain, 4));
    for (int j = 0; j < uncertain_count; ++j) {
        int i = uncertain[j];
        line(&selection, "%s component %d max %s responsibilities %s", points[i].id,
             selected->assigned[i] + 1,
             real(selected->fit.e.records[i].responsibility[selected->assigned[i]], 4),
             reals(selected->fit.e.records[i].responsibility, k));
    }
    line(&selection, "count %d", uncertain_count);
    line(&selection, "");
    line(&selection, "outliers threshold %s", real(p->low_density, 4));
    for (int j = 0; j < outlier_count; ++j) {
        int i = outliers[j], component = selected->assigned[i];
        Component value = selected->fit.model.components[component];
        line(&selection, "%s component %d log_density %s q %s", points[i].id, component + 1,
             real(selected->fit.e.records[i].log_density, 4),
             real(mahalanobis(points[i].xy, value.mean, value.cov), 4));
    }
    line(&selection, "count %d", outlier_count);
    double step_x = (p->xmax - p->xmin) / p->width, step_y = (p->ymax - p->ymin) / p->height;
    int cells = p->width * p->height;
    double *densities = allocate(cells, sizeof(double));
    Record *records = allocate(cells, sizeof(Record));
    double fmax = 0, mass = 0;
    for (int y = 0; y < p->height; ++y)
        for (int x = 0; x < p->width; ++x) {
            int index = y * p->width + x;
            Point point = {.xy = center(x, y, p, step_x, step_y)};
            expectation(&point, 1, selected->fit.model, test_e);
            Record record = test_e->records[0];
            double density = 0;
            for (int j = 0; j < k; ++j)
                density += exp(record.scores[j]);
            densities[index] = density;
            records[index] = record;
            if (density > fmax)
                fmax = density;
            mass += density;
        }
    mass *= step_x;
    mass *= step_y;
    char **density = grid(p->width, p->height);
    char **region = grid(p->width, p->height);
    char **uncertainty = grid(p->width, p->height);
    char **point_map = grid(p->width, p->height);
    int levels[10] = {0};
    const char *characters = " .:-=+*#%@";
    for (int y = 0; y < p->height; ++y)
        for (int x = 0; x < p->width; ++x) {
            int index = y * p->width + x, level = (int)floor(10 * densities[index] / fmax);
            if (level > 9)
                level = 9;
            ++levels[level];
            density[y][x] = characters[level];
            Record record = records[index];
            int chosen = 0;
            double entropy = 0;
            for (int j = 0; j < k; ++j) {
                if (record.scores[j] > record.scores[chosen])
                    chosen = j;
                if (record.responsibility[j] > 0)
                    entropy -= record.responsibility[j] * log(record.responsibility[j]);
            }
            region[y][x] = (char)('1' + chosen);
            if (k >= 2) {
                int value = (int)floor(10 * entropy / log(k));
                if (value < 0)
                    value = 0;
                if (value > 9)
                    value = 9;
                uncertainty[y][x] = characters[value];
            }
            for (int j = 0; j < k; ++j) {
                Component component = selected->fit.model.components[j];
                if (mahalanobis(center(x, y, p, step_x, step_y), component.mean, component.cov) > 4)
                    continue;
                bool contour = false;
                const int offsets[4][2] = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};
                for (int d = 0; d < 4; ++d) {
                    int xx = x + offsets[d][0], yy = y + offsets[d][1];
                    if (xx >= 0 && xx < p->width && yy >= 0 && yy < p->height &&
                        mahalanobis(center(xx, yy, p, step_x, step_y), component.mean, component.cov) > 4)
                        contour = true;
                }
                if (contour)
                    point_map[y][x] = '.';
            }
        }
    for (int j = 0; j < k; ++j) {
        Cell position = cell(selected->fit.model.components[j].mean, p, step_x, step_y);
        if (position.inside)
            density[position.y][position.x] = (char)('1' + j);
    }
    int *occupied = allocate(cells, sizeof(int));
    for (int i = 0; i < cells; ++i)
        occupied[i] = -1;
    int outside = 0;
    for (int i = 0; i < n; ++i) {
        Cell position = cell(points[i].xy, p, step_x, step_y);
        if (!position.inside) {
            ++outside;
            continue;
        }
        int index = position.y * p->width + position.x;
        if (occupied[index] == -1)
            occupied[index] = selected->assigned[i];
        else if (occupied[index] != selected->assigned[i])
            occupied[index] = -2;
        point_map[position.y][position.x] = occupied[index] == -2 ? '*' : (char)('1' + occupied[index]);
    }
    line(&map_file, "density K=%d type=%s", k, type_name(type));
    line(&map_file, "x %s %s y %s %s grid %dx%d", real(p->xmin, 4), real(p->xmax, 4), real(p->ymin, 4),
         real(p->ymax, 4), p->width, p->height);
    line(&map_file, "max_density %s mass_in_map %s", real(fmax, 6), real(mass, 4));
    frame(&map_file, density, p->height, p->width);
    for (int level = 0; level < 10; ++level)
        line(&map_file, "level %d \"%c\" from %s cells %d", level, characters[level],
             real(level * fmax / 10, 6), levels[level]);
    line(&map_file, "");
    line(&map_file, "regions");
    frame(&map_file, region, p->height, p->width);
    line(&map_file, "");
    line(&map_file, "uncertainty");
    frame(&map_file, uncertainty, p->height, p->width);
    line(&map_file, "");
    line(&map_file, "points");
    frame(&map_file, point_map, p->height, p->width);
    line(&map_file, "outside %d", outside);
    save("models.txt", model_file);
    save("loglik_trace.csv", trace);
    save("assignments.csv", assignments);
    save("selection.txt", selection);
    save("density_map.txt", map_file);
    release_all();
    return 0;
}
