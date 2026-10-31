using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static readonly List<string> METHODS =
        public["GLOBAL", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"];
    public static readonly List<string> RANKINGS =
        public["POPULAR", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"];
    public static Ratings.Data data;
    public static Ratings.Settings settings;
    public static Neighborhood.Model neighborhood;
    public static Factorization.Model svd, als;
    public static double[] userBias, itemBias, rmse, mae, train;
    public static int users, items, tests, neighbors, listSize, topN;
    public static List<int> popularity, evaluated;
    public static List<HashSet<int>> relevant = new();
    public static List<List<List<int>>> lists = new();
    public static List<Factorization.Log> logs = new();
    public static Prediction[][] predictions;
    public static double[][] clipped, errors;
    public static int[] clipCount, fallbackCount;
    public record Prediction(double value, bool fallback, int count, double meanSimilarity, int neighbor) {
    }
    public static string Real(double value) {
        return Report.Real(value);
    }
    public static string Integers(int[] values) {
        List<string> words = new();
        foreach (int value in values)
            words.Add(Convert.ToString(value));
        return string.Join(" ", words);
    }
    public static Ratings.Item Item(int i) {
        return data.catalog[data.items[i]];
    }
    public static double Baseline(int u, int i) {
        return (data.mean + userBias[u]) + itemBias[i];
    }
    public static double Training(int method) {
        double sum = 0;
        foreach (Ratings.Rating row in data.training) {
            double value = method == 0 ? data.mean : Baseline(row.user, row.item), error = row.rating - value;
            sum += error * error;
        }
        return Math.Sqrt(sum / data.training.Count);
    }
    public static void Baseline() {
        userBias = new double[users];
        itemBias = new double[items];
        for (int sweep = 1; sweep <= 10; sweep++) {
            for (int i = 0; i < items; i++) {
                double sum = 0;
                foreach (int u in data.byItem[i])
                    sum += data.ratings[u][i] - data.mean - userBias[u];
                itemBias[i] = sum / (settings.Decimal("BIAS_REG", 0) + data.itemCounts[i]);
            }
            for (int u = 0; u < users; u++) {
                double sum = 0;
                foreach (int i in data.byUser[u])
                    sum += data.ratings[u][i] - data.mean - itemBias[i];
                userBias[u] = sum / (settings.Decimal("BIAS_REG", 1) + data.userCounts[u]);
            }
            logs.Add(new Factorization.Log("BASELINE", sweep, Training(1)));
        }
    }
    public static Prediction Predict(int method, int u, int i, int count) {
        double baselineValue = Baseline(u, i);
        if (method == 0)
            return new Prediction(data.mean, false, 0, 0, -1);
        if (method == 1)
            return new Prediction(baselineValue, false, 0, 0, -1);
        if (method == 5)
            return new Prediction(svd.Predict(u, i), false, 0, 0, -1);
        if (method == 6)
            return new Prediction(als.Predict(u, i), false, 0, 0, -1);
        if (method == 4) {
            double slopeNumerator = 0;
            int slopeDenominator = 0;
            foreach (int j in data.byUser[u]) {
                int common = neighborhood.common[i][j];
                if (common > 0) {
                    double deviation =
                        (double)neighborhood.differences[i][j] / (common + settings.Integer("SHRINKAGE"));
                    slopeNumerator += (deviation + data.ratings[u][j]) * common;
                    slopeDenominator += common;
                }
            }
            return slopeDenominator == 0 ? new Prediction(baselineValue, true, 0, 0, -1)
                                         : new Prediction(slopeNumerator / slopeDenominator, false, 0, 0, -1);
        }
        double[] similarities = method == 2 ? neighborhood.users[u] : neighborhood.items[i];
        List<int> candidates = new();
        foreach (int index in method == 2 ? data.byItem[i] : data.byUser[u])
            if (similarities[index] > settings.Number("MIN_SIMILARITY"))
                candidates.Add(index);
        if (candidates.Count == 0)
            return new Prediction(baselineValue, true, 0, 0, -1);
        List<int> selected = Neighborhood.Select(similarities, candidates, count);
        double numerator = 0, denominator = 0;
        foreach (int index in selected) {
            double rating = method == 2 ? data.ratings[index][i] - data.userMeans[index]
                                        : data.ratings[u][index] - data.itemMeans[index];
            numerator += similarities[index] * rating;
            denominator += similarities[index];
        }
        double mean = method == 2 ? data.userMeans[u] : data.itemMeans[i];
        return new Prediction(mean + numerator / denominator, false, selected.Count,
                              denominator / selected.Count,
                              method == 2 ? data.users[selected[0]] : data.items[selected[0]]);
    }
    public static List<int> Ranked(int method, int u) {
        List<int> cached = lists[method][u];
        if (cached != null)
            return cached;
        List<int> result = new();
        foreach (int i in popularity)
            if (data.ratings[u][i] == 0)
                result.Add(i);
        if (method > 0) {
            double[] values = new double[items];
            foreach (int i in result)
                values[i] = Predict(method, u, i, neighbors).value;
            result.Sort((a, b) => {
                int comparison = values[b].CompareTo(values[a]);
                return comparison != 0 ? comparison : a.CompareTo(b);
            });
        }
        lists[method][u] = result;
        return result;
    }
    public static void Prepare() {
        popularity = new();
        for (int i = 0; i < items; i++)
            popularity.Add(i);
        popularity.Sort((a, b) => {
            int comparison = data.itemCounts[b].CompareTo(data.itemCounts[a]);
            if (comparison == 0)
                comparison = data.itemMeans[b].CompareTo(data.itemMeans[a]);
            return comparison != 0 ? comparison : a.CompareTo(b);
        });
        for (int method = 0; method < 7; method++) {
            List<List<int>> rows = new();
            for (int u = 0; u < users; u++)
                rows.Add(null);
            lists.Add(rows);
        }
        for (int u = 0; u < users; u++)
            relevant.Add(new());
        foreach (Ratings.Rating row in data.test)
            if (row.rating >= 4)
                relevant[row.user].Add(row.item);
        evaluated = new();
        for (int u = 0; u < users; u++)
            if (relevant[u].Count != 0)
                evaluated.Add(u);
        predictions = Enumerable.Range(0, 7)
                          .Select(
                              _ => new Prediction[tests])
                          .ToArray();
        clipped = Enumerable.Range(0, 7)
                      .Select(
                          _ => new double[tests])
                      .ToArray();
        errors = Enumerable.Range(0, 7)
                     .Select(
                         _ => new double[tests])
                     .ToArray();
        clipCount = new int[7];
        fallbackCount = new int[7];
        rmse = new double[7];
        mae = new double[7];
        train = new double[7];
        for (int method = 0; method < 7; method++) {
            double square = 0, absolute = 0;
            for (int t = 0; t < tests; t++) {
                Ratings.Rating row = data.test[t];
                Prediction prediction = Predict(method, row.user, row.item, neighbors);
                predictions[method][t] = prediction;
                clipped[method][t] = Evaluation.Clip(prediction.value);
                errors[method][t] = clipped[method][t] - row.rating;
                square += errors[method][t] * errors[method][t];
                absolute += Math.Abs(errors[method][t]);
                if (prediction.value < 1 || prediction.value > 5)
                    clipCount[method]++;
                if (prediction.fallback)
                    fallbackCount[method]++;
            }
            rmse[method] = Math.Sqrt(square / tests);
            mae[method] = absolute / tests;
        }
        train[0] = Training(0);
        train[1] = logs[9].rmse;
        train[5] = svd.log[^1].rmse;
        train[6] = als.log[^1].rmse;
    }
    public static List<string> PredictionReport() {
        List<string> output = new(["user,item,actual," + string.Join(",", METHODS)]);
        for (int t = 0; t < tests; t++) {
            Ratings.Rating row = data.test[t];
            string line = data.users[row.user] + "," + data.items[row.item] + "," + row.rating;
            for (int method = 0; method < 7; method++)
                line += "," + Real(clipped[method][t]);
            output.Add(line);
        }
        return output;
    }
    public static void Section(List<string> output, List<string> lines) {
        if (output.Count != 0)
            output.Add("");
        output.AddRange(lines);
    }
    public static List<string> Genres(bool test) {
        SortedSet<string> genres = new(StringComparer.Ordinal);
        if (test) {
            foreach (Ratings.Rating row in data.test)
                genres.UnionWith(Item(row.item).genres);
        } else
            for (int i = 0; i < items; i++)
                genres.UnionWith(Item(i).genres);
        return new(genres);
    }
    public static string Counts(string label, int[] values) {
        int[] sorted = values.ToArray();
        Array.Sort(sorted);
        return label + " min " + sorted[0] + " median " +
               Real((sorted[(sorted.Length - 1) / 2] + sorted[sorted.Length / 2]) / 2.0) + " max " +
               sorted[sorted.Length - 1];
    }
    public static int Group(int count, int[] boundaries) {
        int group = 0;
        foreach (int boundary in boundaries)
            if (count >= boundary)
                group++;
        return group;
    }
    public static string MetricPairs(List<int> indices, bool absolute) {
        string line = "";
        for (int method = 0; method < 7; method++) {
            List<double> values = new();
            foreach (int t in indices)
                values.Add(errors[method][t]);
            line += " " + METHODS[method] + " " +
                    Real(absolute ? Evaluation.Mae(values) : Evaluation.Rmse(values));
        }
        return line;
    }
    public static List<string> ErrorGroups(bool user) {
        int[] boundaries = settings.List(user ? "USER_GROUPS" : "ITEM_GROUPS");
        List<string> output = new([(user ? "user" : "item") + "_groups bounds " + Integers(boundaries)]);
        for (int g = 0; g <= boundaries.Length; g++) {
            List<int> indices = new();
            for (int t = 0; t < tests; t++) {
                Ratings.Rating row = data.test[t];
                int count = user ? data.userCounts[row.user] : data.itemCounts[row.item];
                if (Group(count, boundaries) == g)
                    indices.Add(t);
            }
            output.Add("group " + (g + 1) + " from " + (g == 0 ? 1 : boundaries[g - 1]) + " to " +
                       (g == boundaries.Length ? "-" : Convert.ToString(boundaries[g] - 1)) + " pairs " +
                       indices.Count + MetricPairs(indices, false));
        }
        return output;
    }
    public static List<string> RatingEvaluation() {
        List<string> output = new();
        int[] histogram = new int[5];
        long first = long.MaxValue, last = 0;
        foreach (Ratings.Rating row in data.training) {
            histogram[row.rating - 1]++;
            first = Math.Min(first, row.time);
            last = Math.Max(last, row.time);
        }
        Section(output, [
            "data users " + users + " items " + items + " catalog " + data.catalog.Count + " ratings " +
                data.training.Count + " test " + tests,
            "density " + Real((double)data.training.Count / (users * items)) + " global_mean " +
                Real(data.mean),
            "histogram " + Integers(histogram), Counts("user_ratings", data.userCounts),
            Counts("item_ratings", data.itemCounts), "timestamps first " + first + " last " + last,
            "cold_items " + (data.catalog.Count - items),
            "similarities user_pairs " + neighborhood.userPairs + " usable " + neighborhood.userUsable +
                " item_pairs " + neighborhood.itemPairs + " usable " + neighborhood.itemUsable +
                " slope_pairs " + neighborhood.slopePairs
        ]);
        List<string> part = new(["genre_stats"]);
        foreach (string genre in Genres(false)) {
            int count = 0, ratings = 0, high = 0;
            for (int i = 0; i < items; i++)
                if (Item(i).genres.Contains(genre)) {
                    count++;
                    ratings += data.itemCounts[i];
                    foreach (int u in data.byItem[i])
                        if (data.ratings[u][i] >= 4)
                            high++;
                }
            part.Add("genre " + genre + " items " + count + " ratings " + ratings + " high " + high);
        }
        Section(output, part);
        int buckets = settings.Integer("TIME_BUCKETS");
        part = new(["time_buckets " + buckets]);
        for (int bucket = 0; bucket < buckets; bucket++) {
            int count = 0, sum = 0;
            HashSet<int> selected = new();
            foreach (Ratings.Rating row in data.training)
                if ((row.time - first) * buckets / (last - first + 1) == bucket) {
                    count++;
                    sum += row.rating;
                    selected.Add(row.user);
                }
            part.Add("bucket " + (bucket + 1) + " ratings " + count + " users " + selected.Count + " mean " +
                     Real(count == 0 ? double.NaN : (double)sum / count));
        }
        Section(output, part);
        part = new(["rating_metrics"]);
        for (int method = 0; method < 7; method++)
            part.Add(METHODS[method] + " rmse " + Real(rmse[method]) + " mae " + Real(mae[method]) +
                     " clipped " + clipCount[method] + " fallback " + fallbackCount[method]);
        Section(output, part);
        part = new(["generalization"]);
        foreach (int method in new int[] { 0, 1, 5, 6 })
            part.Add(METHODS[method] + " train " + Real(train[method]) + " test " + Real(rmse[method]) +
                     " gap " + Real(rmse[method] - train[method]));
        Section(output, part);
        part = new(["neighborhoods k " + neighbors]);
        for (int method = 2; method <= 3; method++) {
            int withNeighbors = 0, count = 0;
            double similarities = 0;
            foreach (Prediction prediction in predictions[method])
                if (!prediction.fallback) {
                    withNeighbors++;
                    count += prediction.count;
                    similarities += prediction.meanSimilarity;
                }
            part.Add(
                METHODS[method] + " predictions " + tests + " with_neighbors " + withNeighbors +
                " mean_neighbors " + Real(withNeighbors == 0 ? double.NaN : (double)count / withNeighbors) +
                " mean_similarity " + Real(withNeighbors == 0 ? double.NaN : similarities / withNeighbors));
        }
        Section(output, part);
        double actualMean = 0;
        foreach (Ratings.Rating row in data.test)
            actualMean += row.rating;
        actualMean /= tests;
        double actualVariance = 0;
        foreach (Ratings.Rating row in data.test)
            actualVariance += (row.rating - actualMean) * (row.rating - actualMean);
        part = new(["prediction_stats actual mean " + Real(actualMean) + " std " +
                    Real(Math.Sqrt(actualVariance / tests))]);
        for (int method = 0; method < 7; method++) {
            double mean = 0;
            foreach (double value in clipped[method])
                mean += value;
            mean /= tests;
            double variance = 0, covariance = 0;
            bool constant = true;
            for (int t = 0; t < tests; t++) {
                double delta = clipped[method][t] - mean;
                variance += delta * delta;
                covariance += delta * (data.test[t].rating - actualMean);
                if (clipped[method][t] != clipped[method][0])
                    constant = false;
            }
            part.Add(METHODS[method] + " mean " + Real(mean) + " std " + Real(Math.Sqrt(variance / tests)) +
                     " correlation " +
                     Real(constant || actualVariance == 0
                              ? double.NaN
                              : covariance / Math.Sqrt(variance * actualVariance)));
        }
        Section(output, part);
        part = new(["error_bins edges 0.5 1.0 1.5 2.0"]);
        for (int method = 0; method < 7; method++) {
            int[] bins = new int[5];
            foreach (double error in errors[method])
                bins[Math.Min(4, (int)Math.Floor(Math.Abs(error) * 2))]++;
            part.Add(METHODS[method] + " " + Integers(bins));
        }
        Section(output, part);
        part = new(["comparison"]);
        for (int a = 0; a < 7; a++)
            for (int b = a + 1; b < 7; b++) {
                int wins = 0, ties = 0, losses = 0;
                for (int t = 0; t < tests; t++) {
                    double left = Math.Abs(errors[a][t]), right = Math.Abs(errors[b][t]);
                    if (left < right)
                        wins++;
                    else if (left == right)
                        ties++;
                    else
                        losses++;
                }
                part.Add(METHODS[a] + " " + METHODS[b] + " wins " + wins + " ties " + ties + " losses " +
                         losses);
            }
        Section(output, part);
        Section(output, ErrorGroups(true));
        Section(output, ErrorGroups(false));
        part = new(["by_rating"]);
        for (int value = 1; value <= 5; value++) {
            List<int> indices = new();
            for (int t = 0; t < tests; t++)
                if (data.test[t].rating == value)
                    indices.Add(t);
            part.Add("rating " + value + " pairs " + indices.Count + MetricPairs(indices, true));
        }
        Section(output, part);
        part = new(["genres"]);
        foreach (string genre in Genres(true)) {
            List<int> indices = new();
            for (int t = 0; t < tests; t++)
                if (Item(data.test[t].item).genres.Contains(genre))
                    indices.Add(t);
            part.Add("genre " + genre + " pairs " + indices.Count + MetricPairs(indices, false));
        }
        Section(output, part);
        return output;
    }
    public static double Log2(double value) {
        return Math.Log(value) / Math.Log(2);
    }
    public static List<string> RankingEvaluation() {
        int count = evaluated.Count, relevantCount = 0;
        foreach (int u in evaluated)
            relevantCount += relevant[u].Count;
        List<string> output = new(["ranking users " + count + " relevant " + relevantCount]);
        foreach (int cutoff in settings.List("CUTOFFS")) {
            output.Add("cutoff " + cutoff);
            for (int method = 0; method < 7; method++) {
                int hits = 0, hitUsers = 0;
                double recall = 0, ndcg = 0, ap = 0, rr = 0;
                foreach (int u in evaluated) {
                    Evaluation.Metrics m = Evaluation.Ranking(Ranked(method, u), relevant[u], cutoff);
                    hits += m.hits;
                    if (m.hits > 0)
                        hitUsers++;
                    recall += m.recall;
                    ndcg += m.ndcg;
                    ap += m.ap;
                    rr += m.rr;
                }
                output.Add("  " + RANKINGS[method] + " precision " + Real((double)hits / (cutoff * count)) +
                           " recall " + Real(recall / count) + " ndcg " + Real(ndcg / count) + " map " +
                           Real(ap / count) + " mrr " + Real(rr / count) + " hit_rate " +
                           Real((double)hitUsers / count));
            }
        }
        List<string> part = new(["beyond_accuracy top_n " + topN + " head " + (items / 5)]);
        HashSet<int> head = new(popularity.GetRange(0, items / 5 - (0)));
        for (int method = 0; method < 7; method++) {
            HashSet<int> coverage = new();
            int diversity = 0, popular = 0, tail = 0;
            double novelty = 0, similarity = 0;
            foreach (int u in evaluated) {
                List<int> list = Ranked(method, u).GetRange(0, topN - (0));
                coverage.UnionWith(list);
                HashSet<string> genres = new();
                double nov = 0, ils = 0;
                foreach (int i in list) {
                    genres.UnionWith(Item(i).genres);
                    popular += data.itemCounts[i];
                    if (!head.Contains(i))
                        tail++;
                    nov += Log2((double)users / data.itemCounts[i]);
                }
                diversity += genres.Count;
                novelty += nov / topN;
                for (int a = 0; a < topN - 1; a++)
                    for (int b = a + 1; b < topN; b++) {
                        double sim = neighborhood.items[list[a]][list[b]];
                        if (!double.IsNaN(sim))
                            ils += sim;
                    }
                similarity += ils / (topN * (topN - 1) / 2);
            }
            part.Add(RANKINGS[method] + " coverage " + Real((double)coverage.Count / items) + " diversity " +
                     Real((double)diversity / count) + " novelty " + Real(novelty / count) + " popularity " +
                     Real((double)popular / (topN * count)) + " long_tail " +
                     Real((double)tail / (topN * count)) + " similarity " + Real(similarity / count));
        }
        Section(output, part);
        int[] boundaries = settings.List("USER_GROUPS");
        part = new(["ranking_groups top_n " + topN + " bounds " + Integers(boundaries)]);
        for (int g = 0; g <= boundaries.Length; g++) {
            List<int> selected = new();
            foreach (int u in evaluated)
                if (Group(data.userCounts[u], boundaries) == g)
                    selected.Add(u);
            string line = "group " + (g + 1) + " users " + selected.Count;
            for (int method = 0; method < 7; method++) {
                double sum = 0;
                foreach (int u in selected)
                    sum += Evaluation.Ranking(Ranked(method, u), relevant[u], topN).ndcg;
                line += " " + RANKINGS[method] + " " +
                        Real(selected.Count == 0 ? double.NaN : sum / selected.Count);
            }
            part.Add(line);
        }
        Section(output, part);
        part = new(["agreement top_n " + topN]);
        for (int a = 0; a < 7; a++)
            for (int b = a + 1; b < 7; b++) {
                double sum = 0;
                foreach (int u in evaluated) {
                    HashSet<int> common = new(Ranked(a, u).GetRange(0, topN - (0)));
                    common.IntersectWith(Ranked(b, u).GetRange(0, topN - (0)));
                    sum += (double)common.Count / (2 * topN - common.Count);
                }
                part.Add(RANKINGS[a] + " " + RANKINGS[b] + " jaccard " + Real(sum / count));
            }
        Section(output, part);
        return output;
    }
    public static List<int> Ordered(double[] values, bool descending) {
        List<int> result = new();
        for (int i = 0; i < values.Length; i++)
            result.Add(i);
        result.Sort((a, b) => {
            int comparison = descending ? values[b].CompareTo(values[a]) : values[a].CompareTo(values[b]);
            return comparison != 0 ? comparison : a.CompareTo(b);
        });
        return result;
    }
    public static List<string> GridAndBiases() {
        List<string> output = new(["neighbor_grid"]);
        int[] grid = settings.List("NEIGHBOR_GRID"), best = { grid[0], grid[0] };
        double[] bestError = { double.PositiveInfinity, double.PositiveInfinity };
        foreach (int count in grid) {
            string line = "k " + count;
            for (int method = 2; method <= 3; method++) {
                List<double> errors = new();
                foreach (Ratings.Rating row in data.test)
                    errors.Add(Evaluation.Clip(Predict(method, row.user, row.item, count).value) -
                               row.rating);
                double error = Evaluation.Rmse(errors);
                line += " " + METHODS[method] + " " + Real(error);
                if (error < bestError[method - 2]) {
                    bestError[method - 2] = error;
                    best[method - 2] = count;
                }
            }
            output.Add(line);
        }
        output.Add("best USER_KNN " + best[0] + " ITEM_KNN " + best[1]);
        List<string> part = new(["biases"]);
        for (int kind = 0; kind < 4; kind++) {
            bool item = kind < 2, descending = kind % 2 == 0;
            double[] bias = item ? itemBias : userBias;
            List<int> order = Ordered(bias, descending);
            for (int position = 0; position < listSize; position++) {
                int index = order[position];
                string label = (item ? "item" : "user") + (descending ? "_high" : "_low");
                part.Add(label + " " + (item ? data.items[index] : data.users[index]) + " bias " +
                         Real(bias[index]) + " count " +
                         (item ? data.itemCounts[index] : data.userCounts[index]) + " mean " +
                         Real(item ? data.itemMeans[index] : data.userMeans[index]) +
                         (item ? " " + Item(index).title : ""));
            }
        }
        Section(output, part);
        return output;
    }
    public static List<string> EvaluationReport() {
        List<string> output = RatingEvaluation();
        Section(output, RankingEvaluation());
        Section(output, GridAndBiases());
        return output;
    }
    public static List<string> GenrePreference(int u, bool liked, Dictionary<string, int> counts) {
        foreach (int i in data.byUser[u])
            if (liked ? data.ratings[u][i] >= 4 : data.ratings[u][i] <= 2)
                foreach (string genre in Item(i).genres)
                    counts[genre] = counts.GetValueOrDefault(genre, 0) + 1;
        List<string> genres = new(counts.Keys);
        genres.Sort((a, b) => {
            int comparison = counts[b].CompareTo(counts[a]);
            return comparison != 0 ? comparison : string.CompareOrdinal(a, b);
        });
        return new(genres.GetRange(0, Math.Min(3, genres.Count) - (0)));
    }
    public static string GenreLine(string label, List<string> genres, Dictionary<string, int> counts) {
        string line = label;
        foreach (string genre in genres)
            line += " " + genre + " " + counts[genre];
        return genres.Count == 0 ? line + " -" : line;
    }
    public static string PopularLine(int position, int i) {
        return "  " + position + " " + data.items[i] + " count " + data.itemCounts[i] + " mean " +
               Real(data.itemMeans[i]) + " " + Item(i).title;
    }
    public static List<string> RecommendationReport() {
        List<string> output = new();
        foreach (int id in settings.List("RECOMMEND_USERS")) {
            List<string> part = new();
            if (!data.userIndex.ContainsKey(id)) {
                part.Add("user " + id + " unknown");
                part.Add("list POPULAR");
                for (int position = 0; position < topN; position++)
                    part.Add(PopularLine(position + 1, popularity[position]));
                Section(output, part);
                continue;
            }
            int u = data.userIndex[id];
            part.Add("user " + id + " ratings " + data.userCounts[u] + " mean " + Real(data.userMeans[u]) +
                     " bias " + Real(userBias[u]));
            Dictionary<string, int> likedCounts = new(), dislikedCounts = new();
            List<string> liked = GenrePreference(u, true, likedCounts),
                         disliked = GenrePreference(u, false, dislikedCounts);
            part.Add(GenreLine("liked_genres", liked, likedCounts));
            part.Add(GenreLine("disliked_genres", disliked, dislikedCounts));
            List<Ratings.Rating> recent = new();
            foreach (Ratings.Rating row in data.training)
                if (row.user == u)
                    recent.Add(row);
            recent.Sort((a, b) => {
                int comparison = b.time.CompareTo(a.time);
                return comparison != 0 ? comparison : a.item.CompareTo(b.item);
            });
            string line = "recent";
            for (int position = 0; position < Math.Min(3, recent.Count); position++) {
                Ratings.Rating row = recent[position];
                line += " " + data.items[row.item] + " " + row.rating;
            }
            part.Add(line);
            List<int> candidates = new();
            for (int v = 0; v < users; v++)
                if (neighborhood.users[u][v] > settings.Number("MIN_SIMILARITY"))
                    candidates.Add(v);
            foreach (int v in Neighborhood.Select(neighborhood.users[u], candidates, listSize))
                part.Add("neighbor " + data.users[v] + " similarity " + Real(neighborhood.users[u][v]) +
                         " common " + neighborhood.userCommon[u][v]);
            for (int t = 0; t < tests; t++) {
                Ratings.Rating row = data.test[t];
                if (row.user != u)
                    continue;
                line = "heldout " + data.items[row.item] + " actual " + row.rating;
                for (int method = 0; method < 7; method++)
                    line += " " + Real(clipped[method][t]);
                part.Add(line);
            }
            for (int method = 0; method < 7; method++) {
                List<int> list = Ranked(method, u).GetRange(0, topN - (0));
                int matches = 0;
                foreach (int i in list) {
                    bool match = false;
                    foreach (string genre in liked)
                        if (Item(i).genres.Contains(genre))
                            match = true;
                    if (match)
                        matches++;
                }
                part.Add("list " + RANKINGS[method] + " genre_match " + matches);
                for (int position = 0; position < topN; position++) {
                    int i = list[position];
                    if (method == 0)
                        part.Add(PopularLine(position + 1, i));
                    else {
                        Prediction prediction = Predict(method, u, i, neighbors);
                        line = "  " + (position + 1) + " " + data.items[i] + " " + Real(prediction.value);
                        if (method == 2 || method == 3)
                            line +=
                                " via " + (prediction.fallback ? "-" : Convert.ToString(prediction.neighbor));
                        part.Add(line + " " + Item(i).title);
                    }
                }
            }
            Section(output, part);
        }
        return output;
    }
    public static List<string> SimilarReport() {
        List<string> output = new();
        foreach (int id in settings.List("SIMILAR_ITEMS")) {
            int i = data.itemIndex[id];
            List<string> part = new(["item " + id + " ratings " + data.itemCounts[i] + " mean " +
                                     Real(data.itemMeans[i]) + " bias " + Real(itemBias[i]) + " genres " +
                                     Item(i).genreText + " title " + Item(i).title]);
            for (int kind = 0; kind < 4; kind++) {
                part.Add(["cosine", "factors", "co_rated", "slope_one"][kind]);
                double[] values = new double[items];
                List<int> candidates = new();
                for (int j = 0; j < items; j++)
                    if (j != i) {
                        if (kind == 0) {
                            values[j] = neighborhood.items[i][j];
                            if (!double.IsNaN(values[j]))
                                candidates.Add(j);
                        } else if (kind == 1) {
                            values[j] = Factorization.Dot(svd.items[i], svd.items[j]) /
                                        Math.Sqrt(Factorization.Dot(svd.items[i], svd.items[i]) *
                                                  Factorization.Dot(svd.items[j], svd.items[j]));
                            candidates.Add(j);
                        } else if (neighborhood.common[i][j] > 0) {
                            values[j] = kind == 2
                                            ? neighborhood.common[i][j]
                                            : (double)neighborhood.differences[j][i] /
                                                  (neighborhood.common[j][i] + settings.Integer("SHRINKAGE"));
                            candidates.Add(j);
                        }
                    }
                public int type = kind;
                candidates.Sort((a, b) => {
                    int comparison = values[b].CompareTo(values[a]);
                    if (comparison == 0 && type == 3)
                        comparison = neighborhood.common[i][b].CompareTo(neighborhood.common[i][a]);
                    return comparison != 0 ? comparison : a.CompareTo(b);
                });
                for (int position = 0; position < Math.Min(listSize, candidates.Count); position++) {
                    int j = candidates[position];
                    string line = "  " + (position + 1) + " " + data.items[j];
                    if (kind < 2)
                        line += " similarity " + Real(values[j]);
                    if (kind == 0 || kind == 2)
                        line += " common " + neighborhood.common[i][j];
                    if (kind == 3)
                        line += " difference " + neighborhood.differences[j][i] + " common " +
                                neighborhood.common[j][i];
                    part.Add(line + " " + Item(j).title);
                }
            }
            Section(output, part);
        }
        return output;
    }
    public static List<string> TrainingReport() {
        List<string> output = new(["method,epoch,train_rmse"]);
        foreach (Factorization.Log log in logs)
            output.Add(log.method + "," + log.epoch + "," + Real(log.rmse));
        return output;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        data = Ratings.Read();
        settings = data.settings;
        users = data.users.Count;
        items = data.items.Count;
        tests = data.test.Count;
        neighbors = settings.Integer("NEIGHBORS");
        listSize = settings.Integer("LIST_SIZE");
        topN = settings.Integer("TOP_N");
        Baseline();
        neighborhood = Neighborhood.Compute(data);
        svd = Factorization.Svd(data);
        als = Factorization.Als(data, userBias, itemBias);
        logs.AddRange(svd.log);
        logs.AddRange(als.log);
        Prepare();
        Report.Write("predictions.csv", PredictionReport());
        Report.Write("evaluation.txt", EvaluationReport());
        Report.Write("recommendations.txt", RecommendationReport());
        Report.Write("similar_items.txt", SimilarReport());
        Report.Write("training_log.csv", TrainingReport());
    }
}
