#include "recommender.hpp"
#include <filesystem>
static const Lines methods = {"GLOBAL", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"},
                   rankings = {"POPULAR", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"};
struct Prediction {
    double value = 0, mean_similarity = 0;
    int neighbors = 0, top = -1;
    bool fallback = false;
};
struct Context {
    const Data &d;
    const Similarities &s;
    const Factors &f;
    const Vector &bu;
    const Vector &bi;
};
static Prediction predict(const Context &c, int method, int u, int i, int size) {
    const Data &d = c.d;
    const double baseline = (d.mean + c.bu[u]) + c.bi[i];
    Prediction out;
    out.value = baseline;
    if (method == 0) {
        out.value = d.mean;
        return out;
    }
    if (method == 1)
        return out;
    if (method == 5) {
        out.value = ((d.mean + c.f.user_bias[u]) + c.f.item_bias[i]) + factor_dot(c.f.p[u], c.f.q[i]);
        return out;
    }
    if (method == 6) {
        out.value = baseline + factor_dot(c.f.x[u], c.f.y[i]);
        return out;
    }
    if (method == 4) {
        double num = 0;
        int den = 0;
        for (std::size_t j = 0; j < d.items.size(); ++j)
            if (d.ratings[u][j] && c.s.common[i][j] >= 1) {
                const int count = c.s.common[i][j];
                const double deviation = double(c.s.difference[i][j]) / (count + d.params.shrinkage);
                num += (deviation + d.ratings[u][j]) * count;
                den += count;
            }
        if (den)
            out.value = num / den;
        else
            out.fallback = true;
        return out;
    }
    std::vector<Neighbor> candidates;
    if (method == 2) {
        for (std::size_t v = 0; v < d.users.size(); ++v)
            if (d.ratings[v][i] && c.s.user[u][v] && *c.s.user[u][v] > d.params.minimum)
                candidates.push_back({int(v), *c.s.user[u][v]});
    } else
        for (std::size_t j = 0; j < d.items.size(); ++j)
            if (d.ratings[u][j] && c.s.item[i][j] && *c.s.item[i][j] > d.params.minimum)
                candidates.push_back({int(j), *c.s.item[i][j]});
    const auto selected = select_neighbors(std::move(candidates), size);
    if (selected.empty()) {
        out.fallback = true;
        return out;
    }
    out.neighbors = selected.size();
    out.top = selected[0].index;
    double num = 0, den = 0;
    for (const Neighbor &neighbor : selected) {
        const int j = neighbor.index;
        num += neighbor.similarity *
               (method == 2 ? d.ratings[j][i] - d.user_mean[j] : d.ratings[u][j] - d.item_mean[j]);
        den += neighbor.similarity;
    }
    out.value = (method == 2 ? d.user_mean[u] : d.item_mean[i]) + num / den;
    out.mean_similarity = den / out.neighbors;
    return out;
}
static bool has(const Item &item, const std::string &genre) {
    return std::find(item.genres.begin(), item.genres.end(), genre) != item.genres.end();
}
static int group(int count, const Ints &bounds) {
    return std::upper_bound(bounds.begin(), bounds.end(), count) - bounds.begin();
}
static double median(Ints values) {
    std::sort(values.begin(), values.end());
    const int n = values.size();
    return n % 2 ? values[n / 2] : double(values[n / 2 - 1] + values[n / 2]) / 2;
}
static void save(const std::string &name, const std::ostringstream &stream) {
    std::istringstream input(stream.str());
    Lines lines;
    std::string line;
    while (std::getline(input, line))
        lines.push_back(line);
    write_lines(name, lines);
}
static std::vector<std::pair<std::string, int>> genres_for(const Data &d, int u, bool liked) {
    std::map<std::string, int> counts;
    for (std::size_t i = 0; i < d.items.size(); ++i)
        if (liked ? d.ratings[u][i] >= 4 : d.ratings[u][i] > 0 && d.ratings[u][i] <= 2)
            for (const std::string &genre : d.items[i].genres)
                ++counts[genre];
    std::vector<std::pair<std::string, int>> out(counts.begin(), counts.end());
    std::sort(out.begin(), out.end(), [](const auto &a, const auto &b) {
        return a.second != b.second ? a.second > b.second : a.first < b.first;
    });
    if (out.size() > 3)
        out.resize(3);
    return out;
}
int main() {
    std::filesystem::create_directories("output");
    const Data d = read_input();
    const Params &p = d.params;
    const int users = d.users.size(), items = d.items.size(), test_count = d.test.size();
    Vector bu(users), bi(items);
    std::vector<Training> training;
    for (int sweep = 1; sweep <= 10; ++sweep) {
        for (int i = 0; i < items; ++i) {
            double sum = 0;
            for (int u = 0; u < users; ++u)
                if (d.ratings[u][i])
                    sum += d.ratings[u][i] - d.mean - bu[u];
            bi[i] = sum / (p.item_reg + d.item_count[i]);
        }
        for (int u = 0; u < users; ++u) {
            double sum = 0;
            for (int i = 0; i < items; ++i)
                if (d.ratings[u][i])
                    sum += d.ratings[u][i] - d.mean - bi[i];
            bu[u] = sum / (p.user_reg + d.user_count[u]);
        }
        double sum = 0;
        for (const Rating &r : d.train) {
            const double error = r.rating - ((d.mean + bu[r.user]) + bi[r.item]);
            sum += error * error;
        }
        training.push_back({"BASELINE", sweep, std::sqrt(sum / d.train.size())});
    }
    const Similarities s = similarities(d);
    const Factors factors = train_factors(d, bu, bi);
    training.insert(training.end(), factors.log.begin(), factors.log.end());
    const Context c{d, s, factors, bu, bi};
    std::vector<std::vector<std::array<Prediction, 7>>> predictions(
        users, std::vector<std::array<Prediction, 7>>(items));
    for (int u = 0; u < users; ++u)
        for (int i = 0; i < items; ++i)
            if (!d.ratings[u][i])
                for (int method = 0; method < 7; ++method)
                    predictions[u][i][method] = predict(c, method, u, i, p.neighbors);
    std::array<Vector, 7> errors, clipped_values;
    std::array<int, 7> clipped{}, fallback{};
    std::ostringstream prediction_file, log_file, evaluation, recommendations, similar;
    prediction_file << "user,item,actual,GLOBAL,BASELINE,USER_KNN,ITEM_KNN,SLOPE_ONE,SVD,ALS\n";
    for (const Rating &r : d.test) {
        prediction_file << d.users[r.user] << ',' << d.items[r.item].id << ',' << r.rating;
        for (int method = 0; method < 7; ++method) {
            const Prediction &value = predictions[r.user][r.item][method];
            const double q = clip(value.value);
            clipped[method] += value.value < 1 || value.value > 5;
            fallback[method] += value.fallback;
            clipped_values[method].push_back(q);
            errors[method].push_back(q - r.rating);
            prediction_file << ',' << real(q);
        }
        prediction_file << '\n';
    }
    log_file << "method,epoch,train_rmse\n";
    for (const Training &entry : training)
        log_file << entry.method << ',' << entry.epoch << ',' << real(entry.rmse) << '\n';
    Ints popularity(items);
    std::iota(popularity.begin(), popularity.end(), 0);
    std::sort(popularity.begin(), popularity.end(), [&](int a, int b) {
        return d.item_count[a] != d.item_count[b] ? d.item_count[a] > d.item_count[b]
               : d.item_mean[a] != d.item_mean[b] ? d.item_mean[a] > d.item_mean[b]
                                                  : a < b;
    });
    std::vector<bool> head(items);
    for (int i = 0; i < items / 5; ++i)
        head[popularity[i]] = true;
    std::vector<std::array<Ints, 7>> lists(users);
    for (int u = 0; u < users; ++u)
        for (int method = 0; method < 7; ++method) {
            Ints &list = lists[u][method];
            if (method == 0) {
                for (int i : popularity)
                    if (!d.ratings[u][i])
                        list.push_back(i);
            } else {
                for (int i = 0; i < items; ++i)
                    if (!d.ratings[u][i])
                        list.push_back(i);
                std::sort(list.begin(), list.end(), [&](int a, int b) {
                    const double x = predictions[u][a][method].value, y = predictions[u][b][method].value;
                    return x != y ? x > y : a < b;
                });
            }
        }
    std::vector<std::set<int>> relevant(users);
    for (const Rating &r : d.test)
        if (r.rating >= 4)
            relevant[r.user].insert(r.item);
    Ints evaluated;
    int relevant_count = 0;
    for (int u = 0; u < users; ++u)
        if (!relevant[u].empty()) {
            evaluated.push_back(u);
            relevant_count += relevant[u].size();
        }
    const int evaluated_count = evaluated.size();
    std::set<std::string> genres, test_genres;
    for (const Item &item : d.items)
        genres.insert(item.genres.begin(), item.genres.end());
    for (const Rating &r : d.test)
        test_genres.insert(d.items[r.item].genres.begin(), d.items[r.item].genres.end());
    std::array<int, 5> histogram{};
    std::int64_t first = d.train[0].time, last = first;
    for (const Rating &r : d.train) {
        ++histogram[r.rating - 1];
        first = std::min(first, r.time);
        last = std::max(last, r.time);
    }
    int user_pairs = 0, user_usable = 0, item_pairs = 0, item_usable = 0, slope_pairs = 0;
    for (int u = 0; u < users - 1; ++u)
        for (int v = u + 1; v < users; ++v)
            if (s.user[u][v]) {
                ++user_pairs;
                user_usable += *s.user[u][v] > p.minimum;
            }
    for (int i = 0; i < items - 1; ++i)
        for (int j = i + 1; j < items; ++j) {
            if (s.item[i][j]) {
                ++item_pairs;
                item_usable += *s.item[i][j] > p.minimum;
            }
            slope_pairs += s.common[i][j] >= 1;
        }
    evaluation << "data users " << users << " items " << items << " catalog " << d.catalog.size()
               << " ratings " << d.train.size() << " test " << test_count << "\ndensity "
               << real(double(d.train.size()) / (users * items)) << " global_mean " << real(d.mean)
               << "\nhistogram";
    for (int value : histogram)
        evaluation << ' ' << value;
    evaluation << "\nuser_ratings min " << *std::min_element(d.user_count.begin(), d.user_count.end())
               << " median " << real(median(d.user_count)) << " max "
               << *std::max_element(d.user_count.begin(), d.user_count.end()) << "\nitem_ratings min "
               << *std::min_element(d.item_count.begin(), d.item_count.end()) << " median "
               << real(median(d.item_count)) << " max "
               << *std::max_element(d.item_count.begin(), d.item_count.end()) << "\ntimestamps first "
               << first << " last " << last << "\ncold_items " << d.catalog.size() - items
               << "\nsimilarities user_pairs " << user_pairs << " usable " << user_usable << " item_pairs "
               << item_pairs << " usable " << item_usable << " slope_pairs " << slope_pairs
               << "\n\ngenre_stats\n";
    for (const std::string &genre : genres) {
        int count = 0, ratings = 0, high = 0;
        for (int i = 0; i < items; ++i)
            if (has(d.items[i], genre)) {
                ++count;
                ratings += d.item_count[i];
                for (int u = 0; u < users; ++u)
                    high += d.ratings[u][i] >= 4;
            }
        evaluation << "genre " << genre << " items " << count << " ratings " << ratings << " high " << high
                   << '\n';
    }
    evaluation << "\ntime_buckets " << p.buckets << '\n';
    for (int bucket = 0; bucket < p.buckets; ++bucket) {
        int count = 0, total = 0;
        std::set<int> seen;
        for (const Rating &r : d.train)
            if ((r.time - first) * p.buckets / (last - first + 1) == bucket) {
                ++count;
                total += r.rating;
                seen.insert(r.user);
            }
        evaluation << "bucket " << bucket + 1 << " ratings " << count << " users " << seen.size() << " mean "
                   << (count ? real(double(total) / count) : "-") << '\n';
    }
    evaluation << "\nrating_metrics\n";
    for (int method = 0; method < 7; ++method)
        evaluation << methods[method] << " rmse " << real(rmse(errors[method])) << " mae "
                   << real(mae(errors[method])) << " clipped " << clipped[method] << " fallback "
                   << fallback[method] << '\n';
    evaluation << "\ngeneralization\n";
    double global_squares = 0;
    for (const Rating &r : d.train)
        global_squares += (r.rating - d.mean) * (r.rating - d.mean);
    for (int method : Ints{0, 1, 5, 6}) {
        const double train = method == 0   ? std::sqrt(global_squares / d.train.size())
                             : method == 1 ? training[9].rmse
                             : method == 5 ? factors.log[p.epochs - 1].rmse
                                           : factors.log.back().rmse;
        const double test = rmse(errors[method]);
        evaluation << methods[method] << " train " << real(train) << " test " << real(test) << " gap "
                   << real(test - train) << '\n';
    }
    evaluation << "\nneighborhoods k " << p.neighbors << '\n';
    for (int method : Ints{2, 3}) {
        int count = 0, total = 0;
        double similarity = 0;
        for (const Rating &r : d.test) {
            const Prediction &value = predictions[r.user][r.item][method];
            if (!value.fallback) {
                ++count;
                total += value.neighbors;
                similarity += value.mean_similarity;
            }
        }
        evaluation << methods[method] << " predictions " << test_count << " with_neighbors " << count
                   << " mean_neighbors " << (count ? real(double(total) / count) : "-") << " mean_similarity "
                   << (count ? real(similarity / count) : "-") << '\n';
    }
    double actual_sum = 0;
    for (const Rating &r : d.test)
        actual_sum += r.rating;
    const double actual_mean = actual_sum / test_count;
    double actual_squares = 0;
    bool actual_same = true;
    for (const Rating &r : d.test) {
        actual_squares += (r.rating - actual_mean) * (r.rating - actual_mean);
        actual_same = actual_same && r.rating == d.test[0].rating;
    }
    evaluation << "\nprediction_stats actual mean " << real(actual_mean) << " std "
               << real(std::sqrt(actual_squares / test_count)) << '\n';
    for (int method = 0; method < 7; ++method) {
        double sum = 0;
        for (double q : clipped_values[method])
            sum += q;
        const double mean = sum / test_count;
        double squares = 0, cross = 0;
        bool same = true;
        for (int t = 0; t < test_count; ++t) {
            const double q = clipped_values[method][t];
            squares += (q - mean) * (q - mean);
            cross += (q - mean) * (d.test[t].rating - actual_mean);
            same = same && q == clipped_values[method][0];
        }
        evaluation << methods[method] << " mean " << real(mean) << " std "
                   << real(std::sqrt(squares / test_count)) << " correlation "
                   << (same || actual_same ? "-" : real(cross / std::sqrt(squares * actual_squares))) << '\n';
    }
    evaluation << "\nerror_bins edges 0.5 1.0 1.5 2.0\n";
    for (int method = 0; method < 7; ++method) {
        std::array<int, 5> bins{};
        for (double error : errors[method]) {
            const double e = std::abs(error);
            ++bins[e < 0.5 ? 0 : e < 1 ? 1 : e < 1.5 ? 2 : e < 2 ? 3 : 4];
        }
        evaluation << methods[method];
        for (int count : bins)
            evaluation << ' ' << count;
        evaluation << '\n';
    }
    evaluation << "\ncomparison\n";
    for (int a = 0; a < 6; ++a)
        for (int b = a + 1; b < 7; ++b) {
            int wins = 0, ties = 0, losses = 0;
            for (int t = 0; t < test_count; ++t) {
                const double x = std::abs(errors[a][t]), y = std::abs(errors[b][t]);
                wins += x < y;
                ties += x == y;
                losses += x > y;
            }
            evaluation << methods[a] << ' ' << methods[b] << " wins " << wins << " ties " << ties
                       << " losses " << losses << '\n';
        }
    for (int kind = 0; kind < 2; ++kind) {
        const Ints &bounds = kind ? p.item_groups : p.user_groups;
        evaluation << '\n' << (kind ? "item_groups" : "user_groups") << " bounds";
        for (int value : bounds)
            evaluation << ' ' << value;
        evaluation << '\n';
        for (int g = 0; g <= int(bounds.size()); ++g) {
            Ints indices;
            for (int t = 0; t < test_count; ++t) {
                const Rating &r = d.test[t];
                const int count = kind ? d.item_count[r.item] : d.user_count[r.user];
                if (group(count, bounds) == g)
                    indices.push_back(t);
            }
            evaluation << "group " << g + 1 << " from " << (g ? bounds[g - 1] : 1) << " to "
                       << (g == int(bounds.size()) ? "-" : std::to_string(bounds[g] - 1)) << " pairs "
                       << indices.size();
            for (int method = 0; method < 7; ++method) {
                Vector values;
                for (int t : indices)
                    values.push_back(errors[method][t]);
                evaluation << ' ' << methods[method] << ' ' << (values.empty() ? "-" : real(rmse(values)));
            }
            evaluation << '\n';
        }
    }
    evaluation << "\nby_rating\n";
    for (int rating = 1; rating <= 5; ++rating) {
        Ints indices;
        for (int t = 0; t < test_count; ++t)
            if (d.test[t].rating == rating)
                indices.push_back(t);
        evaluation << "rating " << rating << " pairs " << indices.size();
        for (int method = 0; method < 7; ++method) {
            Vector values;
            for (int t : indices)
                values.push_back(errors[method][t]);
            evaluation << ' ' << methods[method] << ' ' << (values.empty() ? "-" : real(mae(values)));
        }
        evaluation << '\n';
    }
    evaluation << "\ngenres\n";
    for (const std::string &genre : test_genres) {
        Ints indices;
        for (int t = 0; t < test_count; ++t)
            if (has(d.items[d.test[t].item], genre))
                indices.push_back(t);
        evaluation << "genre " << genre << " pairs " << indices.size();
        for (int method = 0; method < 7; ++method) {
            Vector values;
            for (int t : indices)
                values.push_back(errors[method][t]);
            evaluation << ' ' << methods[method] << ' ' << real(rmse(values));
        }
        evaluation << '\n';
    }
    evaluation << "\nranking users " << evaluated_count << " relevant " << relevant_count << '\n';
    for (int cutoff : p.cutoffs) {
        evaluation << "cutoff " << cutoff << '\n';
        for (int method = 0; method < 7; ++method) {
            int hits = 0, hit_users = 0;
            double recall = 0, ndcg = 0, ap = 0, rr = 0;
            for (int u : evaluated) {
                const auto metrics = ranking_metrics(lists[u][method], relevant[u], cutoff);
                hits += metrics.hits;
                hit_users += metrics.hits > 0;
                recall += metrics.recall;
                ndcg += metrics.ndcg;
                ap += metrics.ap;
                rr += metrics.rr;
            }
            evaluation << "  " << rankings[method] << " precision "
                       << real(double(hits) / (cutoff * evaluated_count)) << " recall "
                       << real(recall / evaluated_count) << " ndcg " << real(ndcg / evaluated_count)
                       << " map " << real(ap / evaluated_count) << " mrr " << real(rr / evaluated_count)
                       << " hit_rate " << real(double(hit_users) / evaluated_count) << '\n';
        }
    }
    evaluation << "\nbeyond_accuracy top_n " << p.top << " head " << items / 5 << '\n';
    for (int method = 0; method < 7; ++method) {
        std::set<int> covered;
        int diversity = 0, popular = 0, tail = 0;
        double novelty = 0, similarity = 0;
        for (int u : evaluated) {
            const Ints &list = lists[u][method];
            std::set<std::string> found;
            double nov = 0, ils = 0;
            for (int rank = 0; rank < p.top; ++rank) {
                const int i = list[rank];
                covered.insert(i);
                found.insert(d.items[i].genres.begin(), d.items[i].genres.end());
                nov += std::log2(double(users) / d.item_count[i]);
                popular += d.item_count[i];
                tail += !head[i];
            }
            diversity += found.size();
            novelty += nov / p.top;
            for (int a = 0; a < p.top - 1; ++a)
                for (int b = a + 1; b < p.top; ++b)
                    ils += s.item[list[a]][list[b]].value_or(0);
            similarity += ils / (p.top * (p.top - 1) / 2);
        }
        evaluation << rankings[method] << " coverage " << real(double(covered.size()) / items)
                   << " diversity " << real(double(diversity) / evaluated_count) << " novelty "
                   << real(novelty / evaluated_count) << " popularity "
                   << real(double(popular) / (p.top * evaluated_count)) << " long_tail "
                   << real(double(tail) / (p.top * evaluated_count)) << " similarity "
                   << real(similarity / evaluated_count) << '\n';
    }
    evaluation << "\nranking_groups top_n " << p.top << " bounds";
    for (int value : p.user_groups)
        evaluation << ' ' << value;
    evaluation << '\n';
    for (int g = 0; g <= int(p.user_groups.size()); ++g) {
        Ints selected;
        for (int u : evaluated)
            if (group(d.user_count[u], p.user_groups) == g)
                selected.push_back(u);
        evaluation << "group " << g + 1 << " users " << selected.size();
        for (int method = 0; method < 7; ++method) {
            double total = 0;
            for (int u : selected)
                total += ranking_metrics(lists[u][method], relevant[u], p.top).ndcg;
            evaluation << ' ' << rankings[method] << ' '
                       << (selected.empty() ? "-" : real(total / selected.size()));
        }
        evaluation << '\n';
    }
    evaluation << "\nagreement top_n " << p.top << '\n';
    for (int a = 0; a < 6; ++a)
        for (int b = a + 1; b < 7; ++b) {
            double total = 0;
            for (int u : evaluated) {
                int common = 0;
                for (int rank = 0; rank < p.top; ++rank)
                    common += std::find(lists[u][b].begin(), lists[u][b].begin() + p.top,
                                        lists[u][a][rank]) != lists[u][b].begin() + p.top;
                total += double(common) / (2 * p.top - common);
            }
            evaluation << rankings[a] << ' ' << rankings[b] << " jaccard " << real(total / evaluated_count)
                       << '\n';
        }
    evaluation << "\nneighbor_grid\n";
    std::array<int, 2> best{};
    std::array<double, 2> smallest{};
    for (int size : p.grid) {
        evaluation << "k " << size;
        for (int kind = 0; kind < 2; ++kind) {
            Vector values;
            for (const Rating &r : d.test)
                values.push_back(clip(predict(c, kind + 2, r.user, r.item, size).value) - r.rating);
            const double value = rmse(values);
            if (!best[kind] || value < smallest[kind]) {
                best[kind] = size;
                smallest[kind] = value;
            }
            evaluation << ' ' << methods[kind + 2] << ' ' << real(value);
        }
        evaluation << '\n';
    }
    evaluation << "best USER_KNN " << best[0] << " ITEM_KNN " << best[1] << "\n\nbiases\n";
    for (int kind = 0; kind < 4; ++kind) {
        const bool item = kind < 2, high = kind % 2 == 0;
        const Vector &bias = item ? bi : bu;
        Ints order(bias.size());
        std::iota(order.begin(), order.end(), 0);
        std::sort(order.begin(), order.end(), [&](int a, int b) {
            return bias[a] != bias[b] ? (high ? bias[a] > bias[b] : bias[a] < bias[b]) : a < b;
        });
        for (int rank = 0; rank < p.list; ++rank) {
            const int index = order[rank];
            evaluation << (item ? "item_" : "user_") << (high ? "high " : "low ")
                       << (item ? d.items[index].id : d.users[index]) << " bias " << real(bias[index])
                       << " count " << (item ? d.item_count[index] : d.user_count[index]) << " mean "
                       << real(item ? d.item_mean[index] : d.user_mean[index]);
            if (item)
                evaluation << ' ' << d.items[index].title;
            evaluation << '\n';
        }
    }
    for (std::size_t request = 0; request < p.users.size(); ++request) {
        if (request)
            recommendations << '\n';
        const int id = p.users[request];
        const auto found = std::lower_bound(d.users.begin(), d.users.end(), id);
        if (found == d.users.end() || *found != id) {
            recommendations << "user " << id << " unknown\nlist POPULAR\n";
            for (int rank = 0; rank < p.top; ++rank) {
                const int i = popularity[rank];
                recommendations << "  " << rank + 1 << ' ' << d.items[i].id << " count " << d.item_count[i]
                                << " mean " << real(d.item_mean[i]) << ' ' << d.items[i].title << '\n';
            }
            continue;
        }
        const int u = found - d.users.begin();
        recommendations << "user " << id << " ratings " << d.user_count[u] << " mean " << real(d.user_mean[u])
                        << " bias " << real(bu[u]) << '\n';
        const auto liked = genres_for(d, u, true), disliked = genres_for(d, u, false);
        for (int kind = 0; kind < 2; ++kind) {
            const auto &values = kind ? disliked : liked;
            recommendations << (kind ? "disliked_genres" : "liked_genres");
            if (values.empty())
                recommendations << " -";
            for (const auto &entry : values)
                recommendations << ' ' << entry.first << ' ' << entry.second;
            recommendations << '\n';
        }
        std::vector<Rating> recent;
        for (const Rating &r : d.train)
            if (r.user == u)
                recent.push_back(r);
        std::sort(recent.begin(), recent.end(), [](const Rating &a, const Rating &b) {
            return a.time != b.time ? a.time > b.time : a.item < b.item;
        });
        recommendations << "recent";
        for (std::size_t index = 0; index < std::min<std::size_t>(3, recent.size()); ++index)
            recommendations << ' ' << d.items[recent[index].item].id << ' ' << recent[index].rating;
        recommendations << '\n';
        std::vector<Neighbor> neighbors;
        for (int v = 0; v < users; ++v)
            if (s.user[u][v] && *s.user[u][v] > p.minimum)
                neighbors.push_back({v, *s.user[u][v]});
        for (const Neighbor &neighbor : select_neighbors(std::move(neighbors), p.list))
            recommendations << "neighbor " << d.users[neighbor.index] << " similarity "
                            << real(neighbor.similarity) << " common " << s.user_common[u][neighbor.index]
                            << '\n';
        for (const Rating &r : d.test)
            if (r.user == u) {
                recommendations << "heldout " << d.items[r.item].id << " actual " << r.rating;
                for (int method = 0; method < 7; ++method)
                    recommendations << ' ' << real(clip(predictions[u][r.item][method].value));
                recommendations << '\n';
            }
        for (int method = 0; method < 7; ++method) {
            const Ints &list = lists[u][method];
            int matches = 0;
            for (int rank = 0; rank < p.top; ++rank) {
                bool matched = false;
                for (const auto &entry : liked)
                    matched = matched || has(d.items[list[rank]], entry.first);
                matches += matched;
            }
            recommendations << "list " << rankings[method] << " genre_match " << matches << '\n';
            for (int rank = 0; rank < p.top; ++rank) {
                const int i = list[rank];
                recommendations << "  " << rank + 1 << ' ' << d.items[i].id;
                if (method == 0)
                    recommendations << " count " << d.item_count[i] << " mean " << real(d.item_mean[i]);
                else {
                    const Prediction &value = predictions[u][i][method];
                    recommendations << ' ' << real(value.value);
                    if (method == 2 || method == 3)
                        recommendations
                            << " via "
                            << (value.top < 0 ? "-"
                                              : std::to_string(method == 2 ? d.users[value.top]
                                                                           : d.items[value.top].id));
                }
                recommendations << ' ' << d.items[i].title << '\n';
            }
        }
    }
    for (std::size_t request = 0; request < p.items.size(); ++request) {
        if (request)
            similar << '\n';
        const int id = p.items[request];
        const int i = std::lower_bound(d.items.begin(), d.items.end(), id,
                                       [](const Item &item, int value) { return item.id < value; }) -
                      d.items.begin();
        similar << "item " << id << " ratings " << d.item_count[i] << " mean " << real(d.item_mean[i])
                << " bias " << real(bi[i]) << " genres " << d.items[i].genre_list << " title "
                << d.items[i].title << '\n';
        for (int kind = 0; kind < 4; ++kind) {
            similar << (kind == 0   ? "cosine"
                        : kind == 1 ? "factors"
                        : kind == 2 ? "co_rated"
                                    : "slope_one")
                    << '\n';
            std::vector<Neighbor> candidates;
            for (int j = 0; j < items; ++j)
                if (j != i) {
                    if (kind == 0) {
                        if (s.item[i][j])
                            candidates.push_back({j, *s.item[i][j]});
                    } else if (kind == 1) {
                        const double value = factor_dot(factors.q[i], factors.q[j]) /
                                             std::sqrt(factor_dot(factors.q[i], factors.q[i]) *
                                                       factor_dot(factors.q[j], factors.q[j]));
                        candidates.push_back({j, value});
                    } else if (s.common[i][j] >= 1)
                        candidates.push_back(
                            {j, kind == 2 ? double(s.common[i][j])
                                          : double(s.difference[j][i]) / (s.common[j][i] + p.shrinkage)});
                }
            std::sort(candidates.begin(), candidates.end(), [&](const Neighbor &a, const Neighbor &b) {
                if (a.similarity != b.similarity)
                    return a.similarity > b.similarity;
                if (kind == 3 && s.common[i][a.index] != s.common[i][b.index])
                    return s.common[i][a.index] > s.common[i][b.index];
                return a.index < b.index;
            });
            for (int rank = 0; rank < std::min(p.list, int(candidates.size())); ++rank) {
                const int j = candidates[rank].index;
                similar << "  " << rank + 1 << ' ' << d.items[j].id;
                if (kind < 2) {
                    similar << " similarity " << real(candidates[rank].similarity);
                    if (kind == 0)
                        similar << " common " << s.common[i][j];
                } else if (kind == 2)
                    similar << " common " << s.common[i][j];
                else
                    similar << " difference " << s.difference[j][i] << " common " << s.common[j][i];
                similar << ' ' << d.items[j].title << '\n';
            }
        }
    }
    save("predictions.csv", prediction_file);
    save("evaluation.txt", evaluation);
    save("recommendations.txt", recommendations);
    save("similar_items.txt", similar);
    save("training_log.csv", log_file);
}
