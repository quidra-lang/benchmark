#include "segments.h"

typedef struct { int labels[400], passes, transfers; Point centers[10]; double sse; } Refined;
typedef struct { const char *method; int number, seeds[10]; Lloyd lloyd; Refined refined; } Run;
typedef struct { int k, labels[400], sizes[10], members[10][400]; Point centers[10]; double sse; } Solution;
typedef struct {
    int k, run_count, bests[3], best, votes, rule_numbers[10];
    Run *runs;
    Solution solution;
    double silhouettes[400], silhouette, ch, db, elbow, hartigan;
    char *names[10];
} Candidate;
typedef struct {
    Transactions data;
    Rules rules;
    Orders reference_orders;
    Customers customers;
    Scaling scaling;
    Point points[400];
    Integer state, total_spend;
    Candidate candidates[11];
    int votes[5], k, numbers[400], scores[400][3], codes[400], others[400];
    Candidate *final;
    double distances[400], other_distances[400], segment_sse[10], jaccard_total[10], jaccard_min[10];
    Integer *overall_categories, *segment_categories[10], segment_spends[10];
    bool *category_present;
    int *rankings[10], ranking_counts[10];
} Analysis;
static const char *criteria[] = {"elbow", "silhouette", "calinski_harabasz", "davies_bouldin", "hartigan"};
static const char *yes_no(bool flag) { return flag ? "yes" : "no"; }
static Points analysis_points(const Analysis *analysis) { return (Points){analysis->points, analysis->customers.count, 6}; }
static Integer draw(Analysis *analysis) { analysis->state = 48271 * analysis->state % 2147483647; return analysis->state; }
static void initial_seeds(Analysis *analysis, Points points, int k, const char *method, int number, int *seeds) {
    int count = 0;
    if (!strcmp(method, "forgy")) {
        bool chosen[400] = {0};
        while (count < k) { int index = (int)(draw(analysis) % points.n); if (!chosen[index]) { chosen[index] = true; seeds[count++] = index; } }
        return;
    }
    if (!strcmp(method, "maximin")) {
        Point center;
        double spreads[400];
        int order[400];
        mean_point(points, center);
        for (int i = 0; i < points.n; ++i) {
            spreads[i] = squared_distance(points.v[i], center, points.dimensions);
            int j = i;
            while (j && spreads[order[j - 1]] > spreads[i]) { order[j] = order[j - 1]; --j; }
            order[j] = i;
        }
        seeds[count++] = order[number - 1];
    } else seeds[count++] = (int)(draw(analysis) % points.n);
    while (count < k) {
        double gaps[400];
        for (int i = 0; i < points.n; ++i) {
            gaps[i] = squared_distance(points.v[i], points.v[seeds[0]], points.dimensions);
            for (int j = 1; j < count; ++j) {
                double trial = squared_distance(points.v[i], points.v[seeds[j]], points.dimensions);
                if (trial < gaps[i]) gaps[i] = trial;
            }
        }
        int chosen = 0;
        if (!strcmp(method, "maximin")) { for (int i = 1; i < points.n; ++i) if (gaps[i] > gaps[chosen]) chosen = i; }
        else {
            double weight = ordered_sum(gaps, points.n), threshold = ((double)draw(analysis) / 2147483647) * weight, cumulative = 0;
            chosen = -1;
            for (int i = 0; i < points.n; ++i) { cumulative += gaps[i]; if (cumulative > threshold) { chosen = i; break; } }
            if (chosen < 0) for (int i = 0; i < points.n; ++i) if (gaps[i] > 0) chosen = i;
        }
        seeds[count++] = chosen;
    }
}
static Refined improve(Points points, const int *original, int k, int limit) {
    Refined result = {0};
    memcpy(result.labels, original, (size_t)points.n * sizeof(int));
    int sizes[10];
    cluster_sizes(result.labels, points.n, k, sizes);
    cluster_centers(points, result.labels, k, result.centers);
    while (result.passes < limit) {
        int changes = 0;
        ++result.passes;
        for (int i = 0; i < points.n; ++i) {
            int own = result.labels[i];
            if (sizes[own] == 1) continue;
            double removal = ((double)sizes[own] / (sizes[own] - 1)) * squared_distance(points.v[i], result.centers[own], points.dimensions);
            int target = -1;
            double cost = 0;
            for (int q = 0; q < k; ++q) if (q != own) {
                double insertion = ((double)sizes[q] / (sizes[q] + 1)) * squared_distance(points.v[i], result.centers[q], points.dimensions);
                if (target < 0 || insertion < cost) { target = q; cost = insertion; }
            }
            if (cost < removal) {
                result.labels[i] = target;
                --sizes[own]; ++sizes[target];
                cluster_center(points, result.labels, own, result.centers[own]);
                cluster_center(points, result.labels, target, result.centers[target]);
                ++changes; ++result.transfers;
            }
        }
        if (!changes) break;
    }
    cluster_centers(points, result.labels, k, result.centers);
    result.sse = sse(points, result.labels, result.centers);
    return result;
}
static Run clustering_run(Analysis *analysis, Points points, int k, const char *method, int number) {
    Run result = {.method = method, .number = number};
    initial_seeds(analysis, points, k, method, number, result.seeds);
    Point initial[10];
    for (int j = 0; j < k; ++j) memcpy(initial[j], points.v[result.seeds[j]], sizeof(Point));
    result.lloyd = lloyd(points, initial, k, analysis->data.settings.iterations);
    result.refined = improve(points, result.lloyd.labels, k, analysis->data.settings.iterations);
    return result;
}
static Solution organize(Points points, const int *labels, int k) {
    Solution result = {.k = k};
    int groups[10][400], sizes[10] = {0}, order[10];
    for (int i = 0; i < points.n; ++i) groups[labels[i]][sizes[labels[i]]++] = i;
    for (int j = 0; j < k; ++j) {
        int i = j;
        while (i && (sizes[order[i - 1]] < sizes[j] || (sizes[order[i - 1]] == sizes[j] && groups[order[i - 1]][0] > groups[j][0]))) { order[i] = order[i - 1]; --i; }
        order[i] = j;
    }
    for (int j = 0; j < k; ++j) {
        result.sizes[j] = sizes[order[j]];
        for (int i = 0; i < result.sizes[j]; ++i) { int number = groups[order[j]][i]; result.members[j][i] = number; result.labels[number] = j; }
    }
    cluster_centers(points, result.labels, k, result.centers);
    result.sse = sse(points, result.labels, result.centers);
    return result;
}
static void fit_candidates(Analysis *analysis) {
    Settings settings = analysis->data.settings;
    Points points = analysis_points(analysis);
    for (int k = settings.min_k; k <= settings.max_k; ++k) {
        Candidate *candidate = &analysis->candidates[k];
        candidate->k = k;
        candidate->runs = allocate((size_t)settings.method_count * settings.restarts * sizeof(Run));
        candidate->best = -1;
        for (int m = 0; m < settings.method_count; ++m) {
            int best = -1;
            for (int t = 1; t <= settings.restarts; ++t) {
                int index = candidate->run_count++;
                candidate->runs[index] = clustering_run(analysis, points, k, settings.methods[m], t);
                if (best < 0 || rounded_key(candidate->runs[index].refined.sse) < rounded_key(candidate->runs[best].refined.sse)) best = index;
            }
            candidate->bests[m] = best;
            if (candidate->best < 0 || rounded_key(candidate->runs[best].refined.sse) < rounded_key(candidate->runs[candidate->best].refined.sse)) candidate->best = best;
        }
        candidate->solution = organize(points, candidate->runs[candidate->best].refined.labels, k);
    }
    double *table = distance_table(points), first = analysis->candidates[settings.min_k].solution.sse, last = analysis->candidates[settings.max_k].solution.sse;
    for (int k = settings.min_k; k <= settings.max_k; ++k) {
        Candidate *candidate = &analysis->candidates[k];
        Solution *solution = &candidate->solution;
        silhouettes(table, solution->labels, solution->sizes, points.n, k, candidate->silhouettes);
        candidate->silhouette = ordered_sum(candidate->silhouettes, points.n) / points.n;
        candidate->ch = calinski_harabasz(points, solution->centers, solution->sizes, k, solution->sse);
        candidate->db = davies_bouldin(points, solution->labels, solution->centers, solution->sizes, k);
        candidate->elbow = elbow(k, settings.min_k, settings.max_k, solution->sse, first, last);
        if (k < settings.max_k) candidate->hartigan = hartigan(solution->sse, analysis->candidates[k + 1].solution.sse, points.n, k);
        for (int j = 0; j < k; ++j) {
            int rule = matching_rule(analysis->rules, solution->centers[j]), repeats = 0;
            for (int earlier = 0; earlier < j; ++earlier) if (candidate->rule_numbers[earlier] == rule + 1) ++repeats;
            candidate->rule_numbers[j] = rule + 1;
            candidate->names[j] = repeats ? format("%s_%d", analysis->rules.items[rule].name, repeats + 1) : analysis->rules.items[rule].name;
        }
    }
    int votes[5] = {settings.min_k + 1, settings.min_k, settings.min_k, settings.min_k, settings.max_k};
    for (int k = settings.min_k; k <= settings.max_k; ++k) {
        Candidate *candidate = &analysis->candidates[k];
        if (k > settings.min_k && k < settings.max_k && rounded_key(candidate->elbow) > rounded_key(analysis->candidates[votes[0]].elbow)) votes[0] = k;
        if (rounded_key(candidate->silhouette) > rounded_key(analysis->candidates[votes[1]].silhouette)) votes[1] = k;
        if (rounded_key(candidate->ch) > rounded_key(analysis->candidates[votes[2]].ch)) votes[2] = k;
        if (rounded_key(candidate->db) < rounded_key(analysis->candidates[votes[3]].db)) votes[3] = k;
        if (k < settings.max_k && votes[4] == settings.max_k && candidate->hartigan <= 10) votes[4] = k;
    }
    for (int v = 0; v < 5; ++v) { analysis->votes[v] = votes[v]; ++analysis->candidates[votes[v]].votes; }
    analysis->k = settings.min_k;
    for (int k = settings.min_k + 1; k <= settings.max_k; ++k) {
        Candidate *candidate = &analysis->candidates[k], *best = &analysis->candidates[analysis->k];
        if (candidate->votes > best->votes || (candidate->votes == best->votes && rounded_key(candidate->silhouette) > rounded_key(best->silhouette))) analysis->k = k;
    }
    analysis->final = &analysis->candidates[analysis->k];
}
static void prepare_final(Analysis *analysis) {
    int n = analysis->customers.count, cats = analysis->data.category_count;
    Solution *solution = &analysis->final->solution;
    analysis->overall_categories = allocate((size_t)cats * sizeof(Integer));
    analysis->category_present = allocate((size_t)cats * sizeof(bool));
    for (int j = 0; j < analysis->k; ++j) {
        analysis->segment_categories[j] = allocate((size_t)cats * sizeof(Integer));
        analysis->rankings[j] = allocate((size_t)cats * sizeof(int));
    }
    for (int i = 0; i < n; ++i) {
        Customer *customer = &analysis->customers.items[i];
        int own = solution->labels[i], other = -1;
        double best = 0;
        analysis->distances[i] = sqrt(squared_distance(customer->point, solution->centers[own], 6));
        for (int j = 0; j < analysis->k; ++j) if (j != own) {
            double value = squared_distance(customer->point, solution->centers[j], 6);
            if (other < 0 || value < best) { other = j; best = value; }
        }
        analysis->others[i] = other; analysis->other_distances[i] = sqrt(best);
        int ranks[3] = {0};
        for (int j = 0; j < n; ++j) {
            Customer *candidate = &analysis->customers.items[j];
            if (candidate->raw[0] > customer->raw[0]) ++ranks[0];
            if (candidate->order_count < customer->order_count) ++ranks[1];
            if (candidate->spend < customer->spend) ++ranks[2];
        }
        for (int s = 0; s < 3; ++s) analysis->scores[i][s] = 1 + 5 * ranks[s] / n;
        analysis->codes[i] = 100 * analysis->scores[i][0] + 10 * analysis->scores[i][1] + analysis->scores[i][2];
        analysis->total_spend += customer->spend; analysis->segment_spends[own] += customer->spend;
        analysis->segment_sse[own] += squared_distance(customer->point, solution->centers[own], 6);
        for (int g = 0; g < cats; ++g) {
            analysis->overall_categories[g] += customer->category_spend[g];
            analysis->segment_categories[own][g] += customer->category_spend[g];
            if (customer->category_present[g]) analysis->category_present[g] = true;
        }
    }
    for (int j = 0; j < analysis->k; ++j) for (int g = 0; g < cats; ++g) {
        if (analysis->segment_categories[j][g] <= 0) continue;
        int position = analysis->ranking_counts[j]++;
        while (position && analysis->segment_categories[j][analysis->rankings[j][position - 1]] < analysis->segment_categories[j][g]) {
            analysis->rankings[j][position] = analysis->rankings[j][position - 1]; --position;
        }
        analysis->rankings[j][position] = g;
    }
}
static char *customer_ids(const Analysis *analysis, const int *numbers, int count) {
    char *result = "";
    for (int i = 0; i < count; ++i) result = format("%s%s%s", result, i ? " " : "", analysis->customers.items[numbers[i]].id);
    return result;
}
static char *segment_numbers(int k) {
    int numbers[10];
    for (int j = 0; j < k; ++j) numbers[j] = j + 1;
    return integers(numbers, k);
}
static Lines feature_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure");
    for (int i = 0; i < analysis->customers.count; ++i) {
        const Customer *customer = &analysis->customers.items[i];
        char *line = format("%s,%d,%d,%s,%s,%d,%d", customer->id, (int)customer->raw[0], customer->order_count, amount(customer->spend), real_text(customer->raw[3]), (int)customer->raw[4], (int)customer->raw[5]);
        for (int f = 0; f < 6; ++f) line = format("%s,%s", line, real_text(customer->point[f]));
        add_line(&lines, "%s", line);
    }
    return lines;
}
static Lines run_lines(const Analysis *analysis) {
    Settings settings = analysis->data.settings;
    Lines lines = {0};
    for (int k = settings.min_k; k <= settings.max_k; ++k) {
        if (k > settings.min_k) add_line(&lines, "");
        const Candidate *candidate = &analysis->candidates[k];
        add_line(&lines, "k %d", k);
        for (int r = 0; r < candidate->run_count; ++r) {
            const Run *run = &candidate->runs[r];
            add_line(&lines, "run %s %d seeds %s iterations %d converged %s reseeds %d sse %s passes %d transfers %d refined %s", run->method, run->number, customer_ids(analysis, run->seeds, k), run->lloyd.iterations, yes_no(run->lloyd.converged), run->lloyd.reseeds, real_text(run->lloyd.sse), run->refined.passes, run->refined.transfers, real_text(run->refined.sse));
        }
        for (int m = 0; m < settings.method_count; ++m) {
            const Run *run = &candidate->runs[candidate->bests[m]];
            add_line(&lines, "best %s restart %d sse %s", run->method, run->number, real_text(run->refined.sse));
        }
        const Run *run = &candidate->runs[candidate->best];
        add_line(&lines, "chosen %s restart %d sse %s", run->method, run->number, real_text(run->refined.sse));
        add_line(&lines, "sizes %s", integers(candidate->solution.sizes, k));
    }
    return lines;
}
static Lines selection_lines(const Analysis *analysis) {
    Settings settings = analysis->data.settings;
    int count = analysis->customers.count;
    Lines lines = {0};
    add_line(&lines, "indices");
    for (int k = settings.min_k; k <= settings.max_k; ++k) {
        const Candidate *candidate = &analysis->candidates[k];
        add_line(&lines, "k=%d sse %s elbow %s silhouette %s calinski_harabasz %s davies_bouldin %s hartigan %s", k, real_text(candidate->solution.sse), real_text(candidate->elbow), real_text(candidate->silhouette), real_text(candidate->ch), real_text(candidate->db), k == settings.max_k ? "-" : real_text(candidate->hartigan));
    }
    add_line(&lines, ""); add_line(&lines, "votes");
    for (int v = 0; v < 5; ++v) add_line(&lines, "%s k=%d", criteria[v], analysis->votes[v]);
    add_line(&lines, "chosen k=%d votes %d", analysis->k, analysis->final->votes);
    add_line(&lines, ""); add_line(&lines, "segments");
    for (int k = settings.min_k; k <= settings.max_k; ++k) {
        const Candidate *candidate = &analysis->candidates[k];
        char *line = format("k=%d", k);
        for (int j = 0; j < k; ++j) line = format("%s %s:%d", line, candidate->names[j], candidate->solution.sizes[j]);
        add_line(&lines, "%s", line);
    }
    add_line(&lines, ""); add_line(&lines, "stability");
    for (int k = settings.min_k; k <= settings.max_k; ++k) {
        const Candidate *candidate = &analysis->candidates[k];
        char *line = format("k=%d", k);
        for (int a = 0; a < settings.method_count; ++a) for (int b = a + 1; b < settings.method_count; ++b) {
            const Run *first = &candidate->runs[candidate->bests[a]], *second = &candidate->runs[candidate->bests[b]];
            line = format("%s %s:%s %s", line, first->method, second->method, real_text(adjusted_rand(first->refined.labels, second->refined.labels, count)));
        }
        line = format("%s final", line);
        for (int m = 0; m < settings.method_count; ++m) {
            const Run *run = &candidate->runs[candidate->bests[m]];
            line = format("%s %s %s", line, run->method, real_text(adjusted_rand(run->refined.labels, candidate->solution.labels, count)));
        }
        add_line(&lines, "%s next %s", line, k == settings.max_k ? "-" : real_text(adjusted_rand(candidate->solution.labels, analysis->candidates[k + 1].solution.labels, count)));
    }
    return lines;
}
static const char *recommendation(const Analysis *analysis, int index) {
    int segment = analysis->final->solution.labels[index];
    for (int r = 0; r < analysis->ranking_counts[segment]; ++r) {
        int category = analysis->rankings[segment][r];
        if (analysis->customers.items[index].category_spend[category] <= 0) return analysis->data.categories[category];
    }
    return "-";
}
static Lines segment_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "customer,segment,name,distance,other,other_distance,silhouette,recommend");
    for (int i = 0; i < analysis->customers.count; ++i) {
        int segment = analysis->final->solution.labels[i];
        add_line(&lines, "%s,%d,%s,%s,%d,%s,%s,%s", analysis->customers.items[i].id, segment + 1, analysis->final->names[segment], real_text(analysis->distances[i]), analysis->others[i] + 1, real_text(analysis->other_distances[i]), real_text(analysis->final->silhouettes[i]), recommendation(analysis, i));
    }
    return lines;
}
static int compare_integer(const void *first, const void *second) {
    Integer a = *(const Integer *)first, b = *(const Integer *)second;
    return (a > b) - (a < b);
}
static int compare_real(const void *first, const void *second) {
    double a = *(const double *)first, b = *(const double *)second;
    return (a > b) - (a < b);
}
static double gini(const Analysis *analysis, const int *members, int count) {
    Integer values[400], total = 0, weighted = 0;
    for (int i = 0; i < count; ++i) values[i] = analysis->customers.items[members ? members[i] : i].spend;
    qsort(values, (size_t)count, sizeof(Integer), compare_integer);
    for (int i = 0; i < count; ++i) { total += values[i]; weighted += (i + 1) * values[i]; }
    return (double)(2 * weighted - (count + 1) * total) / (count * total);
}
static char *related(const Analysis *analysis, const int *members, int count, int k) {
    if (k < analysis->data.settings.min_k || k > analysis->data.settings.max_k) return format("k=%d -", k);
    int counts[10] = {0}, best = 0;
    for (int i = 0; i < count; ++i) ++counts[analysis->candidates[k].solution.labels[members[i]]];
    for (int j = 1; j < k; ++j) if (counts[j] > counts[best]) best = j;
    return format("k=%d segment %d shared %d", k, best + 1, counts[best]);
}
static Lines profile_block(const Analysis *analysis, int segment) {
    const Solution *solution = &analysis->final->solution;
    const int *members = solution->members[segment];
    int count = solution->sizes[segment];
    Integer spend = analysis->segment_spends[segment];
    const double *center = solution->centers[segment];
    Point original;
    original_scale(center, &analysis->scaling, original);
    Lines lines = {0};
    add_line(&lines, "segment %d %s rule %d size %d share %s revenue %s revenue_share %s", segment + 1, analysis->final->names[segment], analysis->final->rule_numbers[segment], count, real_text((double)count / analysis->customers.count), amount(spend), real_text((double)spend / analysis->total_spend));
    add_line(&lines, "  center %s", reals(center, 6));
    char *line = "  value";
    for (int f = 0; f < 6; ++f) line = format("%s %s %s", line, feature_names[f], real_text(original[f]));
    add_line(&lines, "%s", line);
    int traits[6];
    for (int f = 0; f < 6; ++f) {
        int i = f;
        while (i && fabs(center[traits[i - 1]]) < fabs(center[f])) { traits[i] = traits[i - 1]; --i; }
        traits[i] = f;
    }
    add_line(&lines, "  traits %s_%s %s_%s", center[traits[0]] > 0 ? "high" : "low", feature_names[traits[0]], center[traits[1]] > 0 ? "high" : "low", feature_names[traits[1]]);
    Point medians;
    Integer spends[400];
    for (int f = 0; f < 6; ++f) {
        double values[400];
        for (int i = 0; i < count; ++i) values[i] = analysis->customers.items[members[i]].raw[f];
        qsort(values, (size_t)count, sizeof(double), compare_real);
        medians[f] = values[(count - 1) / 2];
    }
    for (int i = 0; i < count; ++i) spends[i] = analysis->customers.items[members[i]].spend;
    qsort(spends, (size_t)count, sizeof(Integer), compare_integer);
    add_line(&lines, "  median recency %d frequency %d monetary %s basket %s categories %d tenure %d", (int)medians[0], (int)medians[1], amount(spends[(count - 1) / 2]), real_text(medians[3]), (int)medians[4], (int)medians[5]);
    add_line(&lines, "  related %s %s", related(analysis, members, count, analysis->k - 1), related(analysis, members, count, analysis->k + 1));
    int order[400];
    for (int i = 0; i < count; ++i) {
        int index = members[i], j = i;
        while (j && analysis->customers.items[order[j - 1]].spend < analysis->customers.items[index].spend) { order[j] = order[j - 1]; --j; }
        order[j] = index;
    }
    line = "  top_customers";
    for (int i = 0; i < count && i < analysis->data.settings.top_customers; ++i) line = format("%s %s %s", line, analysis->customers.items[order[i]].id, amount(analysis->customers.items[order[i]].spend));
    add_line(&lines, "%s", line);
    int cadence = 0, overdue = 0, bins[11] = {0};
    double gap_total = 0, silhouette = 0, scores[3] = {0}, distances[400];
    int negative = 0, modes[556] = {0}, mode = 111;
    for (int i = 0; i < count; ++i) {
        int index = members[i];
        const Customer *customer = &analysis->customers.items[index];
        int frequency = customer->order_count, recency = (int)customer->raw[0], tenure = (int)customer->raw[5];
        if (frequency >= 2) {
            ++cadence; gap_total += (double)(tenure - recency) / (frequency - 1);
            if (recency * (frequency - 1) > analysis->data.settings.overdue_factor * (tenure - recency)) ++overdue;
        }
        for (int o = 0; o < customer->order_count; ++o) {
            int bin = 0;
            for (int b = 0; b < analysis->data.settings.bin_count; ++b) if (customer->orders[o]->net >= 100 * analysis->data.settings.order_bins[b]) ++bin;
            ++bins[bin];
        }
        silhouette += analysis->final->silhouettes[index];
        if (analysis->final->silhouettes[index] < 0) ++negative;
        for (int s = 0; s < 3; ++s) scores[s] += analysis->scores[index][s];
        ++modes[analysis->codes[index]];
        distances[i] = analysis->distances[index];
    }
    for (int code = 111; code <= 555; ++code) if (modes[code] > modes[mode]) mode = code;
    add_line(&lines, "  cadence customers %d mean_gap %s overdue %d", cadence, cadence ? real_text(gap_total / cadence) : "-", overdue);
    add_line(&lines, "  order_sizes %s", integers(bins, analysis->data.settings.bin_count + 1));
    add_line(&lines, "  sse %s share %s", real_text(analysis->segment_sse[segment]), real_text(analysis->segment_sse[segment] / solution->sse));
    add_line(&lines, "  gini %s", real_text(gini(analysis, members, count)));
    Integer gross = 0, returned = 0;
    int cancelled = 0;
    for (int o = 0; o < analysis->reference_orders.count; ++o) {
        const Order *purchase = &analysis->reference_orders.items[o];
        int index = analysis->numbers[purchase->customer];
        if (index < 0 || solution->labels[index] != segment) continue;
        if (purchase->net <= 0) ++cancelled;
        for (int r = 0; r < purchase->row_count; ++r) {
            Integer value = purchase->rows[r]->amount;
            if (value > 0) gross += value; else returned -= value;
        }
    }
    add_line(&lines, "  returns rate %s returned %s cancelled %d", real_text((double)returned / gross), amount(returned), cancelled);
    add_line(&lines, "  silhouette %s negative %d", real_text(silhouette / count), negative);
    add_line(&lines, "  rfm r %s f %s m %s mode %d %d", real_text(scores[0] / count), real_text(scores[1] / count), real_text(scores[2] / count), mode, modes[mode]);
    line = "  categories";
    for (int r = 0; r < analysis->ranking_counts[segment] && r < analysis->data.settings.top_categories; ++r) {
        int g = analysis->rankings[segment][r];
        double share = (double)analysis->segment_categories[segment][g] / spend, lift = share / ((double)analysis->overall_categories[g] / analysis->total_spend);
        line = format("%s %s %s %s", line, analysis->data.categories[g], real_text(share), real_text(lift));
    }
    add_line(&lines, "%s", line);
    int outliers[400], outlier_count = 0;
    if (count >= 2) {
        Moments moments = mean_sd(distances, count);
        double threshold = moments.mean + analysis->data.settings.outlier_sd * moments.sd;
        for (int i = 0; i < count; ++i) if (distances[i] > threshold) outliers[outlier_count++] = members[i];
    }
    add_line(&lines, "  outliers %d%s%s", outlier_count, outlier_count ? " " : "", customer_ids(analysis, outliers, outlier_count));
    return lines;
}
static Lines profiles_lines(const Analysis *analysis) {
    Lines lines = {0};
    add_line(&lines, "segments k=%d customers %d revenue %s gini %s", analysis->k, analysis->customers.count, amount(analysis->total_spend), real_text(gini(analysis, NULL, analysis->customers.count)));
    for (int j = 0; j < analysis->k; ++j) { add_line(&lines, ""); extend(&lines, profile_block(analysis, j)); }
    add_line(&lines, ""); add_line(&lines, "category_mix %s", segment_numbers(analysis->k));
    for (int g = 0; g < analysis->data.category_count; ++g) if (analysis->category_present[g]) {
        char *line = analysis->data.categories[g];
        for (int j = 0; j < analysis->k; ++j) line = format("%s %s", line, real_text((double)analysis->segment_categories[j][g] / analysis->segment_spends[j]));
        add_line(&lines, "%s", line);
    }
    add_line(&lines, ""); add_line(&lines, "rfm_recency %s", segment_numbers(analysis->k));
    for (int score = 5; score >= 1; --score) {
        int counts[10] = {0};
        for (int i = 0; i < analysis->customers.count; ++i) if (analysis->scores[i][0] == score) ++counts[analysis->final->solution.labels[i]];
        add_line(&lines, "r=%d %s", score, integers(counts, analysis->k));
    }
    add_line(&lines, "ari rfm_codes %s", real_text(adjusted_rand(analysis->codes, analysis->final->solution.labels, analysis->customers.count)));
    add_line(&lines, ""); add_line(&lines, "center_distances");
    for (int j = 0; j < analysis->k; ++j) {
        double distances[10];
        for (int other = 0; other < analysis->k; ++other) distances[other] = sqrt(squared_distance(analysis->final->solution.centers[j], analysis->final->solution.centers[other], 6));
        add_line(&lines, "%d %s", j + 1, reals(distances, analysis->k));
    }
    return lines;
}
static void subsamples(Analysis *analysis) {
    int n = analysis->customers.count, size = n * analysis->data.settings.percent / 100;
    for (int j = 0; j < analysis->k; ++j) analysis->jaccard_min[j] = 1;
    for (int b = 0; b < analysis->data.settings.subsamples; ++b) {
        int order[400];
        for (int i = 0; i < n; ++i) order[i] = i;
        for (int t = 0; t < size; ++t) {
            int j = t + (int)(draw(analysis) % (n - t)), saved = order[t];
            order[t] = order[j]; order[j] = saved;
        }
        for (int i = 1; i < size; ++i) {
            int number = order[i], j = i;
            while (j && order[j - 1] > number) { order[j] = order[j - 1]; --j; }
            order[j] = number;
        }
        Point points[400];
        for (int i = 0; i < size; ++i) memcpy(points[i], analysis->points[order[i]], sizeof(Point));
        Lloyd result = lloyd((Points){points, size, 6}, analysis->final->solution.centers, analysis->k, analysis->data.settings.iterations);
        for (int segment = 0; segment < analysis->k; ++segment) {
            double best = 0;
            for (int j = 0; j < analysis->k; ++j) {
                int both = 0, either = 0;
                for (int i = 0; i < size; ++i) {
                    bool expected = analysis->final->solution.labels[order[i]] == segment, actual = result.labels[i] == j;
                    if (expected && actual) ++both;
                    if (expected || actual) ++either;
                }
                double value = either ? (double)both / either : 0;
                if (value > best) best = value;
            }
            analysis->jaccard_total[segment] += best;
            if (best < analysis->jaccard_min[segment]) analysis->jaccard_min[segment] = best;
        }
    }
}
static Lines robustness_lines(Analysis *analysis) {
    Lines lines = {0};
    Settings settings = analysis->data.settings;
    int n = analysis->customers.count;
    add_line(&lines, "subsamples %d size %d", settings.subsamples, n * settings.percent / 100);
    for (int j = 0; j < analysis->k; ++j) add_line(&lines, "segment %d %s mean_jaccard %s min_jaccard %s", j + 1, analysis->final->names[j], real_text(analysis->jaccard_total[j] / settings.subsamples), real_text(analysis->jaccard_min[j]));
    add_line(&lines, ""); add_line(&lines, "ablation");
    for (int omitted = 0; omitted < 6; ++omitted) {
        Point points[400] = {{0}};
        for (int i = 0; i < n; ++i) {
            int component = 0;
            for (int f = 0; f < 6; ++f) if (f != omitted) points[i][component++] = analysis->points[i][f];
        }
        Run run = clustering_run(analysis, (Points){points, n, 5}, analysis->k, "maximin", 1);
        add_line(&lines, "without %s seeds %s iterations %d converged %s transfers %d sse %s ari %s", feature_names[omitted], customer_ids(analysis, run.seeds, analysis->k), run.lloyd.iterations, yes_no(run.lloyd.converged), run.refined.transfers, real_text(run.refined.sse), real_text(adjusted_rand(run.refined.labels, analysis->final->solution.labels, n)));
    }
    const int *members = analysis->final->solution.members[0];
    int count = analysis->final->solution.sizes[0];
    Point points[400];
    for (int i = 0; i < count; ++i) memcpy(points[i], analysis->points[members[i]], sizeof(Point));
    Run run = clustering_run(analysis, (Points){points, count, 6}, 2, "maximin", 1);
    Solution split = organize((Points){points, count, 6}, run.refined.labels, 2);
    int seeds[2] = {members[run.seeds[0]], members[run.seeds[1]]};
    add_line(&lines, "");
    add_line(&lines, "drilldown segment 1 %s size %d seeds %s iterations %d converged %s transfers %d", analysis->final->names[0], count, customer_ids(analysis, seeds, 2), run.lloyd.iterations, yes_no(run.lloyd.converged), run.refined.transfers);
    add_line(&lines, "sse before %s after %s gain %s", real_text(analysis->segment_sse[0]), real_text(run.refined.sse), real_text(analysis->segment_sse[0] - run.refined.sse));
    for (int j = 0; j < 2; ++j) add_line(&lines, "part %d size %d center %s", j + 1, split.sizes[j], reals(split.centers[j], 6));
    return lines;
}
static Lines tracking_lines(Analysis *analysis) {
    Settings settings = analysis->data.settings;
    const Solution *solution = &analysis->final->solution;
    Lines lines = {0};
    add_line(&lines, "periods %d days %d", settings.periods, settings.period_days);
    for (int q = 1; q <= settings.periods; ++q) {
        int first = settings.reference - q * settings.period_days + 1, last = settings.reference - (q - 1) * settings.period_days;
        Integer revenue[10] = {0};
        int active[10] = {0}, acquired[10] = {0};
        for (int i = 0; i < analysis->customers.count; ++i) {
            const Customer *customer = &analysis->customers.items[i];
            int segment = solution->labels[i];
            bool buyer = false;
            for (int o = 0; o < customer->order_count; ++o) if (customer->orders[o]->day >= first && customer->orders[o]->day <= last) { revenue[segment] += customer->orders[o]->net; buyer = true; }
            if (buyer) ++active[segment];
            int initial = settings.reference - (int)customer->raw[5];
            if (initial >= first && initial <= last) ++acquired[segment];
        }
        char *line = format("period %d days %d %d revenue", q, first, last);
        for (int j = 0; j < analysis->k; ++j) line = format("%s %s", line, amount(revenue[j]));
        add_line(&lines, "%s active %s acquired %s", line, integers(active, analysis->k), integers(acquired, analysis->k));
    }
    Orders snapshot_orders = group_orders(&analysis->data, 1, settings.snapshot);
    Customers snapshot = eligible_customers(&analysis->data, snapshot_orders, settings.snapshot);
    standardize(snapshot, &analysis->scaling);
    int previous[400];
    for (int c = 0; c < analysis->data.customer_count; ++c) previous[c] = analysis->k;
    int lost = 0;
    for (int i = 0; i < snapshot.count; ++i) {
        const Customer *customer = &snapshot.items[i];
        double best = squared_distance(customer->point, solution->centers[0], 6);
        int chosen = 0;
        for (int j = 1; j < analysis->k; ++j) {
            double distance = squared_distance(customer->point, solution->centers[j], 6);
            if (distance < best) { best = distance; chosen = j; }
        }
        previous[customer->file_number] = chosen;
        if (analysis->numbers[customer->file_number] < 0) ++lost;
    }
    int migration[11][10] = {{0}}, stayed = 0, moved = 0, fresh = 0;
    Lines changes = {0};
    for (int i = 0; i < analysis->customers.count; ++i) {
        const Customer *customer = &analysis->customers.items[i];
        int current = solution->labels[i], old = previous[customer->file_number];
        ++migration[old][current];
        if (old == analysis->k) ++fresh;
        else if (old == current) ++stayed;
        else { ++moved; add_line(&changes, "%s %d %d", customer->id, old + 1, current + 1); }
    }
    add_line(&lines, ""); add_line(&lines, "migration day %d customers %d", settings.snapshot, snapshot.count);
    add_line(&lines, "from\\to %s", segment_numbers(analysis->k));
    for (int old = 0; old <= analysis->k; ++old) add_line(&lines, "%s %s", old == analysis->k ? "none" : format("%d", old + 1), integers(migration[old], analysis->k));
    add_line(&lines, "moved_customers"); extend(&lines, changes);
    add_line(&lines, "stayed %d moved %d new %d lost %d", stayed, moved, fresh, lost);
    Orders outcome = group_orders(&analysis->data, settings.reference + 1, settings.reference + settings.outcome_days);
    Integer purchases[400] = {0};
    for (int o = 0; o < outcome.count; ++o) if (outcome.items[o].net > 0) purchases[outcome.items[o].customer] += outcome.items[o].net;
    add_line(&lines, ""); add_line(&lines, "outcome days %d %d", settings.reference + 1, settings.reference + settings.outcome_days);
    for (int segment = 0; segment < analysis->k; ++segment) {
        int buyers = 0, count = solution->sizes[segment];
        Integer spend = 0;
        for (int m = 0; m < count; ++m) {
            Integer value = purchases[analysis->customers.items[solution->members[segment][m]].file_number];
            if (value > 0) { ++buyers; spend += value; }
        }
        add_line(&lines, "segment %d %s size %d buyers %d rate %s revenue %s per_customer %s", segment + 1, analysis->final->names[segment], count, buyers, real_text((double)buyers / count), amount(spend), real_text(((double)spend / 100) / count));
    }
    int outsiders = 0;
    Integer spend = 0;
    for (int c = 0; c < analysis->data.customer_count; ++c) if (analysis->numbers[c] < 0 && purchases[c] > 0) { ++outsiders; spend += purchases[c]; }
    add_line(&lines, "unsegmented buyers %d revenue %s", outsiders, amount(spend));
    return lines;
}
static Lines summary_lines(const Analysis *analysis) {
    Lines lines = {0};
    int used = 0, returns = 0, later = 0, valid = 0, excluded = 0;
    for (int r = 0; r < analysis->data.valid_count; ++r) {
        const Row *row = &analysis->data.rows[r];
        if (row->day <= analysis->data.settings.reference) { ++used; if (row->amount < 0) ++returns; } else ++later;
    }
    for (int o = 0; o < analysis->reference_orders.count; ++o) if (analysis->reference_orders.items[o].net > 0) ++valid;
    char *ids = "";
    for (int c = 0; c < analysis->data.customer_count; ++c) if (analysis->numbers[c] < 0) { ids = format("%s%s%s", ids, excluded ? " " : "", analysis->data.ids[c]); ++excluded; }
    add_line(&lines, "rows %d duplicates %d zero %d used %d returns %d later %d", analysis->data.row_count, analysis->data.duplicates, analysis->data.free_rows, used, returns, later);
    add_line(&lines, "orders %d valid %d cancelled %d", analysis->reference_orders.count, valid, analysis->reference_orders.count - valid);
    add_line(&lines, "customers %d clustered %d excluded %d", analysis->data.customer_count, analysis->customers.count, excluded);
    add_line(&lines, "excluded_ids %s", excluded ? ids : "-");
    add_line(&lines, "");
    for (int g = 0; g < analysis->data.category_count; ++g) if (analysis->category_present[g]) {
        int buyers = 0;
        for (int i = 0; i < analysis->customers.count; ++i) if (analysis->customers.items[i].category_spend[g] > 0) ++buyers;
        add_line(&lines, "category %s revenue %s share %s customers %d", analysis->data.categories[g], amount(analysis->overall_categories[g]), real_text((double)analysis->overall_categories[g] / analysis->total_spend), buyers);
    }
    add_line(&lines, "");
    for (int f = 0; f < 6; ++f) add_line(&lines, "feature %s transform %s raw_mean %s raw_sd %s mean %s sd %s", feature_names[f], f >= 1 && f <= 3 ? "sqrt" : "none", real_text(analysis->scaling.raw_mean[f]), real_text(analysis->scaling.raw_sd[f]), real_text(analysis->scaling.mean[f]), real_text(analysis->scaling.sd[f]));
    add_line(&lines, ""); add_line(&lines, "correlation recency frequency monetary basket categories tenure");
    for (int a = 0; a < 6; ++a) {
        double values[6];
        for (int b = 0; b < 6; ++b) values[b] = correlation(analysis_points(analysis), a, b);
        add_line(&lines, "%s %s", feature_names[a], reals(values, 6));
    }
    return lines;
}
int main(void) {
    Analysis *analysis = allocate(sizeof(*analysis));
    analysis->data = read_transactions();
    analysis->rules = read_rules();
    analysis->state = analysis->data.settings.seed;
    analysis->reference_orders = group_orders(&analysis->data, 1, analysis->data.settings.reference);
    analysis->customers = eligible_customers(&analysis->data, analysis->reference_orders, analysis->data.settings.reference);
    analysis->scaling = fit_scaling(analysis->customers);
    standardize(analysis->customers, &analysis->scaling);
    for (int c = 0; c < analysis->data.customer_count; ++c) analysis->numbers[c] = -1;
    for (int i = 0; i < analysis->customers.count; ++i) {
        analysis->numbers[analysis->customers.items[i].file_number] = i;
        memcpy(analysis->points[i], analysis->customers.items[i].point, sizeof(Point));
    }
    fit_candidates(analysis);
    prepare_final(analysis);
    subsamples(analysis);
    write_lines("features.csv", feature_lines(analysis));
    write_lines("runs.txt", run_lines(analysis));
    write_lines("selection.txt", selection_lines(analysis));
    write_lines("segments.csv", segment_lines(analysis));
    write_lines("profiles.txt", profiles_lines(analysis));
    write_lines("robustness.txt", robustness_lines(analysis));
    write_lines("tracking.txt", tracking_lines(analysis));
    write_lines("summary.txt", summary_lines(analysis));
    return 0;
}
