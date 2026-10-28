#include "recommender.h"
static const char *methods[] = {"GLOBAL", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"};
static const char *rankings[] = {"POPULAR", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"};
typedef struct {
    double value, mean_similarity;
    int neighbors, top;
    bool fallback;
} Prediction;
typedef struct {
    const Data *d;
    const Similarities *s;
    const Factors *f;
    const double *bu, *bi;
} Context;
static Prediction predict(Context c, int method, int u, int i, int size) {
    const Data *d = c.d;
    const double baseline = (d->mean + c.bu[u]) + c.bi[i];
    Prediction out = {.value = baseline, .top = -1};
    if (method == 0) {
        out.value = d->mean;
        return out;
    }
    if (method == 1)
        return out;
    if (method == 5) {
        out.value = ((d->mean + c.f->user_bias[u]) + c.f->item_bias[i]) +
                    factor_dot(c.f->p[u], c.f->q[i], d->params.factors);
        return out;
    }
    if (method == 6) {
        out.value = baseline + factor_dot(c.f->x[u], c.f->y[i], d->params.factors);
        return out;
    }
    if (method == 4) {
        double num = 0;
        int den = 0;
        for (int j = 0; j < d->ni; ++j)
            if (d->ratings[u][j] && c.s->common[i][j] >= 1) {
                const int count = c.s->common[i][j];
                const double dev = (double)c.s->difference[i][j] / (count + d->params.shrinkage);
                num += (dev + d->ratings[u][j]) * count;
                den += count;
            }
        if (den)
            out.value = num / den;
        else
            out.fallback = true;
        return out;
    }
    Neighbor candidates[300];
    int count = 0;
    if (method == 2) {
        for (int v = 0; v < d->nu; ++v)
            if (d->ratings[v][i] && c.s->user_defined[u][v] && c.s->user[u][v] > d->params.minimum)
                candidates[count++] = (Neighbor){v, c.s->user[u][v]};
    } else
        for (int j = 0; j < d->ni; ++j)
            if (d->ratings[u][j] && c.s->item_defined[i][j] && c.s->item[i][j] > d->params.minimum)
                candidates[count++] = (Neighbor){j, c.s->item[i][j]};
    count = select_neighbors(candidates, count, size);
    if (!count) {
        out.fallback = true;
        return out;
    }
    out.neighbors = count;
    out.top = candidates[0].index;
    double num = 0, den = 0;
    for (int index = 0; index < count; ++index) {
        const Neighbor neighbor = candidates[index];
        const int j = neighbor.index;
        num += neighbor.similarity *
               (method == 2 ? d->ratings[j][i] - d->user_mean[j] : d->ratings[u][j] - d->item_mean[j]);
        den += neighbor.similarity;
    }
    out.value = (method == 2 ? d->user_mean[u] : d->item_mean[i]) + num / den;
    out.mean_similarity = den / count;
    return out;
}
static bool has(const Item *item, const char *genre) {
    return strings_has(item->genres, genre);
}
static int group(int count, Ints bounds) {
    int out = 0;
    for (int i = 0; i < bounds.n; ++i)
        out += count >= bounds.v[i];
    return out;
}
static double median(const int *values, int count) {
    Ints sorted = {.n = count};
    for (int i = 0; i < count; ++i) {
        int position = i;
        while (position > 0 && values[i] < sorted.v[position - 1]) {
            sorted.v[position] = sorted.v[position - 1];
            --position;
        }
        sorted.v[position] = values[i];
    }
    return count % 2 ? sorted.v[count / 2] : (double)(sorted.v[count / 2 - 1] + sorted.v[count / 2]) / 2;
}
static Ints order_values(const double *values, int count, bool high) {
    Ints out = {.n = count};
    for (int i = 0; i < count; ++i) {
        int position = i;
        while (position > 0 &&
               (high ? values[i] > values[out.v[position - 1]] : values[i] < values[out.v[position - 1]])) {
            out.v[position] = out.v[position - 1];
            --position;
        }
        out.v[position] = i;
    }
    return out;
}
static bool ints_has(Ints values, int value, int length) {
    for (int i = 0; i < length; ++i)
        if (values.v[i] == value)
            return true;
    return false;
}
typedef struct {
    char *name;
    int count;
} GenreCount;
typedef struct {
    GenreCount *v;
    int n;
} GenreCounts;
static GenreCounts genres_for(const Data *d, int u, bool liked, Strings genres) {
    GenreCounts out = {.v = calloc((size_t)genres.n, sizeof *out.v)};
    for (int g = 0; g < genres.n; ++g) {
        int count = 0;
        for (int i = 0; i < d->ni; ++i)
            if ((liked ? d->ratings[u][i] >= 4 : d->ratings[u][i] > 0 && d->ratings[u][i] <= 2) &&
                has(&d->items[i], genres.v[g]))
                ++count;
        if (!count)
            continue;
        const GenreCount value = {genres.v[g], count};
        int position = out.n;
        while (position > 0 && (value.count > out.v[position - 1].count ||
                                (value.count == out.v[position - 1].count &&
                                 strcmp(value.name, out.v[position - 1].name) < 0))) {
            out.v[position] = out.v[position - 1];
            --position;
        }
        out.v[position] = value;
        ++out.n;
    }
    if (out.n > 3)
        out.n = 3;
    return out;
}
int main(void) {
    mkdir("output", 0777);
    Data *d = read_input();
    const Params *p = &d->params;
    double bu[200] = {0}, bi[300] = {0};
    Training training[80];
    int ntraining = 0;
    for (int sweep = 1; sweep <= 10; ++sweep) {
        for (int i = 0; i < d->ni; ++i) {
            double sum = 0;
            for (int u = 0; u < d->nu; ++u)
                if (d->ratings[u][i])
                    sum += d->ratings[u][i] - d->mean - bu[u];
            bi[i] = sum / (p->item_reg + d->item_count[i]);
        }
        for (int u = 0; u < d->nu; ++u) {
            double sum = 0;
            for (int i = 0; i < d->ni; ++i)
                if (d->ratings[u][i])
                    sum += d->ratings[u][i] - d->mean - bi[i];
            bu[u] = sum / (p->user_reg + d->user_count[u]);
        }
        double sum = 0;
        for (int t = 0; t < d->nt; ++t) {
            const Rating *r = &d->train[t];
            const double error = r->rating - ((d->mean + bu[r->user]) + bi[r->item]);
            sum += error * error;
        }
        training[ntraining++] = (Training){"BASELINE", sweep, sqrt(sum / d->nt)};
    }
    Similarities *s = similarities(d);
    Factors *f = train_factors(d, bu, bi);
    for (int i = 0; i < f->log_count; ++i)
        training[ntraining++] = f->log[i];
    const Context c = {d, s, f, bu, bi};
    Prediction(*predictions)[300][7] = calloc((size_t)d->nu, sizeof *predictions);
    for (int u = 0; u < d->nu; ++u)
        for (int i = 0; i < d->ni; ++i)
            if (!d->ratings[u][i])
                for (int method = 0; method < 7; ++method)
                    predictions[u][i][method] = predict(c, method, u, i, p->neighbors);
    double errors[7][1000], clipped_values[7][1000];
    int clipped[7] = {0}, fallback[7] = {0};
    Text prediction_file = {0}, log_file = {0}, evaluation = {0}, recommendations = {0}, similar = {0};
    line(&prediction_file, "user,item,actual,GLOBAL,BASELINE,USER_KNN,ITEM_KNN,SLOPE_ONE,SVD,ALS");
    for (int t = 0; t < d->nm; ++t) {
        const Rating *r = &d->test[t];
        add(&prediction_file, "%d,%d,%d", d->users[r->user], d->items[r->item].id, r->rating);
        for (int method = 0; method < 7; ++method) {
            const Prediction value = predictions[r->user][r->item][method];
            const double q = clip(value.value);
            clipped[method] += value.value < 1 || value.value > 5;
            fallback[method] += value.fallback;
            clipped_values[method][t] = q;
            errors[method][t] = q - r->rating;
            add(&prediction_file, ",%s", real(q));
        }
        line(&prediction_file, "");
    }
    line(&log_file, "method,epoch,train_rmse");
    for (int i = 0; i < ntraining; ++i)
        line(&log_file, "%s,%d,%s", training[i].method, training[i].epoch, real(training[i].rmse));
    Ints popularity = {.n = d->ni};
    for (int i = 0; i < d->ni; ++i) {
        int position = i;
        while (position > 0) {
            const int other = popularity.v[position - 1];
            if (!(d->item_count[i] > d->item_count[other] ||
                  (d->item_count[i] == d->item_count[other] && d->item_mean[i] > d->item_mean[other])))
                break;
            popularity.v[position] = other;
            --position;
        }
        popularity.v[position] = i;
    }
    bool head[300] = {0};
    for (int i = 0; i < d->ni / 5; ++i)
        head[popularity.v[i]] = true;
    Ints(*lists)[7] = calloc((size_t)d->nu, sizeof *lists);
    for (int u = 0; u < d->nu; ++u)
        for (int method = 0; method < 7; ++method) {
            Ints *list = &lists[u][method];
            if (!method) {
                for (int rank = 0; rank < d->ni; ++rank) {
                    const int i = popularity.v[rank];
                    if (!d->ratings[u][i])
                        list->v[list->n++] = i;
                }
            } else {
                double values[300] = {0};
                for (int i = 0; i < d->ni; ++i)
                    values[i] = predictions[u][i][method].value;
                const Ints order = order_values(values, d->ni, true);
                for (int rank = 0; rank < d->ni; ++rank) {
                    const int i = order.v[rank];
                    if (!d->ratings[u][i])
                        list->v[list->n++] = i;
                }
            }
        }
    bool (*relevant)[300] = calloc((size_t)d->nu, sizeof *relevant);
    int relevant_count[200] = {0};
    for (int t = 0; t < d->nm; ++t) {
        const Rating *r = &d->test[t];
        if (r->rating >= 4) {
            relevant[r->user][r->item] = true;
            ++relevant_count[r->user];
        }
    }
    Ints evaluated = {0};
    int total_relevant = 0;
    for (int u = 0; u < d->nu; ++u)
        if (relevant_count[u]) {
            evaluated.v[evaluated.n++] = u;
            total_relevant += relevant_count[u];
        }
    Strings genres = {0}, test_genres = {0};
    for (int i = 0; i < d->ni; ++i)
        for (int g = 0; g < d->items[i].genres.n; ++g) {
            const char *name = d->items[i].genres.v[g];
            if (!strings_has(genres, name))
                strings_add(&genres, name);
        }
    for (int t = 0; t < d->nm; ++t) {
        const Item *item = &d->items[d->test[t].item];
        for (int g = 0; g < item->genres.n; ++g)
            if (!strings_has(test_genres, item->genres.v[g]))
                strings_add(&test_genres, item->genres.v[g]);
    }
    strings_sort(genres);
    strings_sort(test_genres);
    int histogram[5] = {0}, user_min = d->user_count[0], user_max = user_min, item_min = d->item_count[0],
        item_max = item_min;
    int64_t first = d->train[0].time, last = first;
    for (int t = 0; t < d->nt; ++t) {
        const Rating *r = &d->train[t];
        ++histogram[r->rating - 1];
        if (r->time < first)
            first = r->time;
        if (r->time > last)
            last = r->time;
    }
    for (int u = 0; u < d->nu; ++u) {
        if (d->user_count[u] < user_min)
            user_min = d->user_count[u];
        if (d->user_count[u] > user_max)
            user_max = d->user_count[u];
    }
    for (int i = 0; i < d->ni; ++i) {
        if (d->item_count[i] < item_min)
            item_min = d->item_count[i];
        if (d->item_count[i] > item_max)
            item_max = d->item_count[i];
    }
    int user_pairs = 0, user_usable = 0, item_pairs = 0, item_usable = 0, slope_pairs = 0;
    for (int u = 0; u < d->nu - 1; ++u)
        for (int v = u + 1; v < d->nu; ++v)
            if (s->user_defined[u][v]) {
                ++user_pairs;
                user_usable += s->user[u][v] > p->minimum;
            }
    for (int i = 0; i < d->ni - 1; ++i)
        for (int j = i + 1; j < d->ni; ++j) {
            if (s->item_defined[i][j]) {
                ++item_pairs;
                item_usable += s->item[i][j] > p->minimum;
            }
            slope_pairs += s->common[i][j] >= 1;
        }
    line(&evaluation, "data users %d items %d catalog %d ratings %d test %d", d->nu, d->ni, d->nc, d->nt,
         d->nm);
    line(&evaluation, "density %s global_mean %s", real((double)d->nt / (d->nu * d->ni)), real(d->mean));
    add(&evaluation, "histogram");
    for (int i = 0; i < 5; ++i)
        add(&evaluation, " %d", histogram[i]);
    line(&evaluation, "");
    line(&evaluation, "user_ratings min %d median %s max %d", user_min, real(median(d->user_count, d->nu)),
         user_max);
    line(&evaluation, "item_ratings min %d median %s max %d", item_min, real(median(d->item_count, d->ni)),
         item_max);
    line(&evaluation, "timestamps first %lld last %lld", (long long)first, (long long)last);
    line(&evaluation, "cold_items %d", d->nc - d->ni);
    line(&evaluation, "similarities user_pairs %d usable %d item_pairs %d usable %d slope_pairs %d",
         user_pairs, user_usable, item_pairs, item_usable, slope_pairs);
    line(&evaluation, "");
    line(&evaluation, "genre_stats");
    for (int g = 0; g < genres.n; ++g) {
        const char *genre = genres.v[g];
        int count = 0, ratings = 0, high = 0;
        for (int i = 0; i < d->ni; ++i)
            if (has(&d->items[i], genre)) {
                ++count;
                ratings += d->item_count[i];
                for (int u = 0; u < d->nu; ++u)
                    high += d->ratings[u][i] >= 4;
            }
        line(&evaluation, "genre %s items %d ratings %d high %d", genre, count, ratings, high);
    }
    line(&evaluation, "");
    line(&evaluation, "time_buckets %d", p->buckets);
    for (int bucket = 0; bucket < p->buckets; ++bucket) {
        int count = 0, total = 0, nseen = 0;
        bool seen[200] = {0};
        for (int t = 0; t < d->nt; ++t) {
            const Rating *r = &d->train[t];
            if ((r->time - first) * p->buckets / (last - first + 1) == bucket) {
                ++count;
                total += r->rating;
                if (!seen[r->user]) {
                    seen[r->user] = true;
                    ++nseen;
                }
            }
        }
        line(&evaluation, "bucket %d ratings %d users %d mean %s", bucket + 1, count, nseen,
             count ? real((double)total / count) : "-");
    }
    line(&evaluation, "");
    line(&evaluation, "rating_metrics");
    for (int method = 0; method < 7; ++method)
        line(&evaluation, "%s rmse %s mae %s clipped %d fallback %d", methods[method],
             real(rmse(errors[method], d->nm)), real(mae(errors[method], d->nm)), clipped[method],
             fallback[method]);
    line(&evaluation, "");
    line(&evaluation, "generalization");
    double global_squares = 0;
    for (int t = 0; t < d->nt; ++t)
        global_squares += (d->train[t].rating - d->mean) * (d->train[t].rating - d->mean);
    const int general_methods[] = {0, 1, 5, 6};
    for (int k = 0; k < 4; ++k) {
        const int method = general_methods[k];
        const double train = method == 0   ? sqrt(global_squares / d->nt)
                             : method == 1 ? training[9].rmse
                             : method == 5 ? f->log[p->epochs - 1].rmse
                                           : f->log[f->log_count - 1].rmse,
                     test = rmse(errors[method], d->nm);
        line(&evaluation, "%s train %s test %s gap %s", methods[method], real(train), real(test),
             real(test - train));
    }
    line(&evaluation, "");
    line(&evaluation, "neighborhoods k %d", p->neighbors);
    for (int method = 2; method <= 3; ++method) {
        int count = 0, total = 0;
        double similarity = 0;
        for (int t = 0; t < d->nm; ++t) {
            const Rating *r = &d->test[t];
            const Prediction value = predictions[r->user][r->item][method];
            if (!value.fallback) {
                ++count;
                total += value.neighbors;
                similarity += value.mean_similarity;
            }
        }
        line(&evaluation, "%s predictions %d with_neighbors %d mean_neighbors %s mean_similarity %s",
             methods[method], d->nm, count, count ? real((double)total / count) : "-",
             count ? real(similarity / count) : "-");
    }
    double actual_sum = 0;
    for (int t = 0; t < d->nm; ++t)
        actual_sum += d->test[t].rating;
    const double actual_mean = actual_sum / d->nm;
    double actual_squares = 0;
    bool actual_same = true;
    for (int t = 0; t < d->nm; ++t) {
        const double delta = d->test[t].rating - actual_mean;
        actual_squares += delta * delta;
        actual_same = actual_same && d->test[t].rating == d->test[0].rating;
    }
    line(&evaluation, "");
    line(&evaluation, "prediction_stats actual mean %s std %s", real(actual_mean),
         real(sqrt(actual_squares / d->nm)));
    for (int method = 0; method < 7; ++method) {
        double sum = 0;
        for (int t = 0; t < d->nm; ++t)
            sum += clipped_values[method][t];
        const double mean = sum / d->nm;
        double squares = 0, cross = 0;
        bool same = true;
        for (int t = 0; t < d->nm; ++t) {
            const double q = clipped_values[method][t];
            squares += (q - mean) * (q - mean);
            cross += (q - mean) * (d->test[t].rating - actual_mean);
            same = same && q == clipped_values[method][0];
        }
        line(&evaluation, "%s mean %s std %s correlation %s", methods[method], real(mean),
             real(sqrt(squares / d->nm)),
             same || actual_same ? "-" : real(cross / sqrt(squares * actual_squares)));
    }
    line(&evaluation, "");
    line(&evaluation, "error_bins edges 0.5 1.0 1.5 2.0");
    for (int method = 0; method < 7; ++method) {
        int bins[5] = {0};
        for (int t = 0; t < d->nm; ++t) {
            const double error = fabs(errors[method][t]);
            ++bins[error < 0.5 ? 0 : error < 1 ? 1 : error < 1.5 ? 2 : error < 2 ? 3 : 4];
        }
        add(&evaluation, "%s", methods[method]);
        for (int bin = 0; bin < 5; ++bin)
            add(&evaluation, " %d", bins[bin]);
        line(&evaluation, "");
    }
    line(&evaluation, "");
    line(&evaluation, "comparison");
    for (int a = 0; a < 6; ++a)
        for (int b = a + 1; b < 7; ++b) {
            int wins = 0, ties = 0, losses = 0;
            for (int t = 0; t < d->nm; ++t) {
                const double x = fabs(errors[a][t]), y = fabs(errors[b][t]);
                wins += x < y;
                ties += x == y;
                losses += x > y;
            }
            line(&evaluation, "%s %s wins %d ties %d losses %d", methods[a], methods[b], wins, ties, losses);
        }
    for (int kind = 0; kind < 2; ++kind) {
        const Ints bounds = kind ? p->item_groups : p->user_groups;
        line(&evaluation, "");
        add(&evaluation, "%s bounds", kind ? "item_groups" : "user_groups");
        for (int i = 0; i < bounds.n; ++i)
            add(&evaluation, " %d", bounds.v[i]);
        line(&evaluation, "");
        for (int g = 0; g <= bounds.n; ++g) {
            Ints indices = {0};
            for (int t = 0; t < d->nm; ++t) {
                const Rating *r = &d->test[t];
                const int count = kind ? d->item_count[r->item] : d->user_count[r->user];
                if (group(count, bounds) == g)
                    indices.v[indices.n++] = t;
            }
            add(&evaluation, "group %d from %d to ", g + 1, g ? bounds.v[g - 1] : 1);
            if (g == bounds.n)
                add(&evaluation, "-");
            else
                add(&evaluation, "%d", bounds.v[g] - 1);
            add(&evaluation, " pairs %d", indices.n);
            for (int method = 0; method < 7; ++method) {
                double values[1000];
                for (int i = 0; i < indices.n; ++i)
                    values[i] = errors[method][indices.v[i]];
                add(&evaluation, " %s %s", methods[method], indices.n ? real(rmse(values, indices.n)) : "-");
            }
            line(&evaluation, "");
        }
    }
    line(&evaluation, "");
    line(&evaluation, "by_rating");
    for (int rating = 1; rating <= 5; ++rating) {
        Ints indices = {0};
        for (int t = 0; t < d->nm; ++t)
            if (d->test[t].rating == rating)
                indices.v[indices.n++] = t;
        add(&evaluation, "rating %d pairs %d", rating, indices.n);
        for (int method = 0; method < 7; ++method) {
            double values[1000];
            for (int i = 0; i < indices.n; ++i)
                values[i] = errors[method][indices.v[i]];
            add(&evaluation, " %s %s", methods[method], indices.n ? real(mae(values, indices.n)) : "-");
        }
        line(&evaluation, "");
    }
    line(&evaluation, "");
    line(&evaluation, "genres");
    for (int g = 0; g < test_genres.n; ++g) {
        const char *genre = test_genres.v[g];
        Ints indices = {0};
        for (int t = 0; t < d->nm; ++t)
            if (has(&d->items[d->test[t].item], genre))
                indices.v[indices.n++] = t;
        add(&evaluation, "genre %s pairs %d", genre, indices.n);
        for (int method = 0; method < 7; ++method) {
            double values[1000];
            for (int i = 0; i < indices.n; ++i)
                values[i] = errors[method][indices.v[i]];
            add(&evaluation, " %s %s", methods[method], real(rmse(values, indices.n)));
        }
        line(&evaluation, "");
    }
    line(&evaluation, "");
    line(&evaluation, "ranking users %d relevant %d", evaluated.n, total_relevant);
    for (int k = 0; k < p->cutoffs.n; ++k) {
        const int cutoff = p->cutoffs.v[k];
        line(&evaluation, "cutoff %d", cutoff);
        for (int method = 0; method < 7; ++method) {
            int hits = 0, hit_users = 0;
            double recall = 0, ndcg = 0, ap = 0, rr = 0;
            for (int index = 0; index < evaluated.n; ++index) {
                const int u = evaluated.v[index];
                const RankingMetrics metrics =
                    ranking_metrics(lists[u][method], relevant[u], relevant_count[u], cutoff);
                hits += metrics.hits;
                hit_users += metrics.hits > 0;
                recall += metrics.recall;
                ndcg += metrics.ndcg;
                ap += metrics.ap;
                rr += metrics.rr;
            }
            line(&evaluation, "  %s precision %s recall %s ndcg %s map %s mrr %s hit_rate %s",
                 rankings[method], real((double)hits / (cutoff * evaluated.n)), real(recall / evaluated.n),
                 real(ndcg / evaluated.n), real(ap / evaluated.n), real(rr / evaluated.n),
                 real((double)hit_users / evaluated.n));
        }
    }
    line(&evaluation, "");
    line(&evaluation, "beyond_accuracy top_n %d head %d", p->top, d->ni / 5);
    for (int method = 0; method < 7; ++method) {
        bool covered[300] = {0};
        int ncovered = 0, diversity = 0, popular = 0, tail = 0;
        double novelty = 0, similarity = 0;
        for (int index = 0; index < evaluated.n; ++index) {
            const int u = evaluated.v[index];
            const Ints list = lists[u][method];
            Strings found = {0};
            double nov = 0, ils = 0;
            for (int rank = 0; rank < p->top; ++rank) {
                const int i = list.v[rank];
                if (!covered[i]) {
                    covered[i] = true;
                    ++ncovered;
                }
                for (int g = 0; g < d->items[i].genres.n; ++g) {
                    const char *name = d->items[i].genres.v[g];
                    if (!strings_has(found, name))
                        strings_add(&found, name);
                }
                nov += log2((double)d->nu / d->item_count[i]);
                popular += d->item_count[i];
                tail += !head[i];
            }
            diversity += found.n;
            for (int g = 0; g < found.n; ++g)
                free(found.v[g]);
            free(found.v);
            novelty += nov / p->top;
            for (int a = 0; a < p->top - 1; ++a)
                for (int b = a + 1; b < p->top; ++b)
                    if (s->item_defined[list.v[a]][list.v[b]])
                        ils += s->item[list.v[a]][list.v[b]];
            similarity += ils / (p->top * (p->top - 1) / 2);
        }
        line(&evaluation, "%s coverage %s diversity %s novelty %s popularity %s long_tail %s similarity %s",
             rankings[method], real((double)ncovered / d->ni), real((double)diversity / evaluated.n),
             real(novelty / evaluated.n), real((double)popular / (p->top * evaluated.n)),
             real((double)tail / (p->top * evaluated.n)), real(similarity / evaluated.n));
    }
    line(&evaluation, "");
    add(&evaluation, "ranking_groups top_n %d bounds", p->top);
    for (int i = 0; i < p->user_groups.n; ++i)
        add(&evaluation, " %d", p->user_groups.v[i]);
    line(&evaluation, "");
    for (int g = 0; g <= p->user_groups.n; ++g) {
        Ints selected = {0};
        for (int i = 0; i < evaluated.n; ++i) {
            const int u = evaluated.v[i];
            if (group(d->user_count[u], p->user_groups) == g)
                selected.v[selected.n++] = u;
        }
        add(&evaluation, "group %d users %d", g + 1, selected.n);
        for (int method = 0; method < 7; ++method) {
            double total = 0;
            for (int i = 0; i < selected.n; ++i) {
                const int u = selected.v[i];
                total += ranking_metrics(lists[u][method], relevant[u], relevant_count[u], p->top).ndcg;
            }
            add(&evaluation, " %s %s", rankings[method], selected.n ? real(total / selected.n) : "-");
        }
        line(&evaluation, "");
    }
    line(&evaluation, "");
    line(&evaluation, "agreement top_n %d", p->top);
    for (int a = 0; a < 6; ++a)
        for (int b = a + 1; b < 7; ++b) {
            double total = 0;
            for (int index = 0; index < evaluated.n; ++index) {
                const int u = evaluated.v[index];
                int common = 0;
                for (int rank = 0; rank < p->top; ++rank)
                    common += ints_has(lists[u][b], lists[u][a].v[rank], p->top);
                total += (double)common / (2 * p->top - common);
            }
            line(&evaluation, "%s %s jaccard %s", rankings[a], rankings[b], real(total / evaluated.n));
        }
    line(&evaluation, "");
    line(&evaluation, "neighbor_grid");
    int best[2] = {0};
    double smallest[2] = {0};
    for (int index = 0; index < p->grid.n; ++index) {
        const int size = p->grid.v[index];
        add(&evaluation, "k %d", size);
        for (int kind = 0; kind < 2; ++kind) {
            double values[1000];
            for (int t = 0; t < d->nm; ++t) {
                const Rating *r = &d->test[t];
                values[t] = clip(predict(c, kind + 2, r->user, r->item, size).value) - r->rating;
            }
            const double value = rmse(values, d->nm);
            if (!best[kind] || value < smallest[kind]) {
                best[kind] = size;
                smallest[kind] = value;
            }
            add(&evaluation, " %s %s", methods[kind + 2], real(value));
        }
        line(&evaluation, "");
    }
    line(&evaluation, "best USER_KNN %d ITEM_KNN %d", best[0], best[1]);
    line(&evaluation, "");
    line(&evaluation, "biases");
    for (int kind = 0; kind < 4; ++kind) {
        const bool item = kind < 2, high = kind % 2 == 0;
        const double *bias = item ? bi : bu;
        const Ints order = order_values(bias, item ? d->ni : d->nu, high);
        for (int rank = 0; rank < p->list; ++rank) {
            const int index = order.v[rank];
            add(&evaluation, "%s_%s %d bias %s count %d mean %s", item ? "item" : "user",
                high ? "high" : "low", item ? d->items[index].id : d->users[index], real(bias[index]),
                item ? d->item_count[index] : d->user_count[index],
                real(item ? d->item_mean[index] : d->user_mean[index]));
            if (item)
                add(&evaluation, " %s", d->items[index].title);
            line(&evaluation, "");
        }
    }
    for (int request = 0; request < p->users.n; ++request) {
        if (request)
            line(&recommendations, "");
        const int id = p->users.v[request];
        int u = -1;
        for (int index = 0; index < d->nu; ++index)
            if (d->users[index] == id)
                u = index;
        if (u < 0) {
            line(&recommendations, "user %d unknown", id);
            line(&recommendations, "list POPULAR");
            for (int rank = 0; rank < p->top; ++rank) {
                const int i = popularity.v[rank];
                line(&recommendations, "  %d %d count %d mean %s %s", rank + 1, d->items[i].id,
                     d->item_count[i], real(d->item_mean[i]), d->items[i].title);
            }
            continue;
        }
        line(&recommendations, "user %d ratings %d mean %s bias %s", id, d->user_count[u],
             real(d->user_mean[u]), real(bu[u]));
        const GenreCounts liked = genres_for(d, u, true, genres), disliked = genres_for(d, u, false, genres);
        for (int kind = 0; kind < 2; ++kind) {
            const GenreCounts values = kind ? disliked : liked;
            add(&recommendations, "%s", kind ? "disliked_genres" : "liked_genres");
            if (!values.n)
                add(&recommendations, " -");
            for (int i = 0; i < values.n; ++i)
                add(&recommendations, " %s %d", values.v[i].name, values.v[i].count);
            line(&recommendations, "");
        }
        Rating recent[300];
        int nrecent = 0;
        for (int t = 0; t < d->nt; ++t)
            if (d->train[t].user == u) {
                const Rating value = d->train[t];
                int position = nrecent;
                while (position > 0 &&
                       (value.time > recent[position - 1].time || (value.time == recent[position - 1].time &&
                                                                   value.item < recent[position - 1].item))) {
                    recent[position] = recent[position - 1];
                    --position;
                }
                recent[position] = value;
                ++nrecent;
            }
        add(&recommendations, "recent");
        for (int index = 0; index < 3 && index < nrecent; ++index)
            add(&recommendations, " %d %d", d->items[recent[index].item].id, recent[index].rating);
        line(&recommendations, "");
        Neighbor neighbors[200];
        int nneighbors = 0;
        for (int v = 0; v < d->nu; ++v)
            if (s->user_defined[u][v] && s->user[u][v] > p->minimum)
                neighbors[nneighbors++] = (Neighbor){v, s->user[u][v]};
        nneighbors = select_neighbors(neighbors, nneighbors, p->list);
        for (int i = 0; i < nneighbors; ++i)
            line(&recommendations, "neighbor %d similarity %s common %d", d->users[neighbors[i].index],
                 real(neighbors[i].similarity), s->user_common[u][neighbors[i].index]);
        for (int t = 0; t < d->nm; ++t) {
            const Rating *r = &d->test[t];
            if (r->user != u)
                continue;
            add(&recommendations, "heldout %d actual %d", d->items[r->item].id, r->rating);
            for (int method = 0; method < 7; ++method)
                add(&recommendations, " %s", real(clip(predictions[u][r->item][method].value)));
            line(&recommendations, "");
        }
        for (int method = 0; method < 7; ++method) {
            const Ints list = lists[u][method];
            int matches = 0;
            for (int rank = 0; rank < p->top; ++rank) {
                bool matched = false;
                for (int g = 0; g < liked.n; ++g)
                    matched = matched || has(&d->items[list.v[rank]], liked.v[g].name);
                matches += matched;
            }
            line(&recommendations, "list %s genre_match %d", rankings[method], matches);
            for (int rank = 0; rank < p->top; ++rank) {
                const int i = list.v[rank];
                add(&recommendations, "  %d %d", rank + 1, d->items[i].id);
                if (!method)
                    add(&recommendations, " count %d mean %s", d->item_count[i], real(d->item_mean[i]));
                else {
                    const Prediction value = predictions[u][i][method];
                    add(&recommendations, " %s", real(value.value));
                    if (method == 2 || method == 3) {
                        add(&recommendations, " via ");
                        if (value.top < 0)
                            add(&recommendations, "-");
                        else
                            add(&recommendations, "%d",
                                method == 2 ? d->users[value.top] : d->items[value.top].id);
                    }
                }
                line(&recommendations, " %s", d->items[i].title);
            }
        }
        free(liked.v);
        free(disliked.v);
    }
    for (int request = 0; request < p->items.n; ++request) {
        if (request)
            line(&similar, "");
        const int id = p->items.v[request];
        int i = 0;
        while (d->items[i].id != id)
            ++i;
        line(&similar, "item %d ratings %d mean %s bias %s genres %s title %s", id, d->item_count[i],
             real(d->item_mean[i]), real(bi[i]), d->items[i].genre_list, d->items[i].title);
        for (int kind = 0; kind < 4; ++kind) {
            line(&similar, "%s",
                 kind == 0   ? "cosine"
                 : kind == 1 ? "factors"
                 : kind == 2 ? "co_rated"
                             : "slope_one");
            Neighbor candidates[300];
            int count = 0;
            for (int j = 0; j < d->ni; ++j)
                if (j != i) {
                    if (kind == 0) {
                        if (s->item_defined[i][j])
                            candidates[count++] = (Neighbor){j, s->item[i][j]};
                    } else if (kind == 1) {
                        const double value = factor_dot(f->q[i], f->q[j], p->factors) /
                                             sqrt(factor_dot(f->q[i], f->q[i], p->factors) *
                                                  factor_dot(f->q[j], f->q[j], p->factors));
                        candidates[count++] = (Neighbor){j, value};
                    } else if (s->common[i][j] >= 1)
                        candidates[count++] = (Neighbor){j, kind == 2 ? (double)s->common[i][j]
                                                                      : (double)s->difference[j][i] /
                                                                            (s->common[j][i] + p->shrinkage)};
                }
            for (int index = 1; index < count; ++index) {
                const Neighbor value = candidates[index];
                int position = index;
                while (position > 0) {
                    const Neighbor previous = candidates[position - 1];
                    bool before = value.similarity > previous.similarity;
                    if (value.similarity == previous.similarity) {
                        if (kind == 3 && s->common[i][value.index] != s->common[i][previous.index])
                            before = s->common[i][value.index] > s->common[i][previous.index];
                        else
                            before = value.index < previous.index;
                    }
                    if (!before)
                        break;
                    candidates[position] = previous;
                    --position;
                }
                candidates[position] = value;
            }
            for (int rank = 0; rank < p->list && rank < count; ++rank) {
                const int j = candidates[rank].index;
                add(&similar, "  %d %d", rank + 1, d->items[j].id);
                if (kind < 2) {
                    add(&similar, " similarity %s", real(candidates[rank].similarity));
                    if (kind == 0)
                        add(&similar, " common %d", s->common[i][j]);
                } else if (kind == 2)
                    add(&similar, " common %d", s->common[i][j]);
                else
                    add(&similar, " difference %d common %d", s->difference[j][i], s->common[j][i]);
                line(&similar, " %s", d->items[j].title);
            }
        }
    }
    write_report("predictions.csv", prediction_file);
    write_report("evaluation.txt", evaluation);
    write_report("recommendations.txt", recommendations);
    write_report("similar_items.txt", similar);
    write_report("training_log.csv", log_file);
    free(prediction_file.data);
    free(log_file.data);
    free(evaluation.data);
    free(recommendations.data);
    free(similar.data);
    free(predictions);
    free(lists);
    free(relevant);
    free(s);
    free(f);
    free(d);
    return 0;
}
