import java.io.IOException;
import java.util.*;

public final class Main {
    static final List<String> METHODS =
        List.of("GLOBAL", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS");
    static final List<String> RANKINGS =
        List.of("POPULAR", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS");
    static Ratings.Data data;
    static Ratings.Settings settings;
    static Neighborhood.Model neighborhood;
    static Factorization.Model svd, als;
    static double[] userBias, itemBias, rmse, mae, train;
    static int users, items, tests, neighbors, listSize, topN;
    static List<Integer> popularity, evaluated;
    static List<Set<Integer>> relevant = new ArrayList<>();
    static List<List<List<Integer>>> lists = new ArrayList<>();
    static List<Factorization.Log> logs = new ArrayList<>();
    static Prediction[][] predictions;
    static double[][] clipped, errors;
    static int[] clipCount, fallbackCount;
    record Prediction(double value, boolean fallback, int count, double meanSimilarity, int neighbor) {}
    static String real(double value) {
        return Report.real(value);
    }
    static String integers(int[] values) {
        List<String> words = new ArrayList<>();
        for (int value : values)
            words.add(Integer.toString(value));
        return String.join(" ", words);
    }
    static Ratings.Item item(int i) {
        return data.catalog.get(data.items.get(i));
    }
    static double baseline(int u, int i) {
        return (data.mean + userBias[u]) + itemBias[i];
    }
    static double training(int method) {
        double sum = 0;
        for (Ratings.Rating row : data.training) {
            double value = method == 0 ? data.mean : baseline(row.user(), row.item()),
                   error = row.rating() - value;
            sum += error * error;
        }
        return Math.sqrt(sum / data.training.size());
    }
    static void baseline() {
        userBias = new double[users];
        itemBias = new double[items];
        for (int sweep = 1; sweep <= 10; sweep++) {
            for (int i = 0; i < items; i++) {
                double sum = 0;
                for (int u : data.byItem.get(i))
                    sum += data.ratings[u][i] - data.mean - userBias[u];
                itemBias[i] = sum / (settings.decimal("BIAS_REG", 0) + data.itemCounts[i]);
            }
            for (int u = 0; u < users; u++) {
                double sum = 0;
                for (int i : data.byUser.get(u))
                    sum += data.ratings[u][i] - data.mean - itemBias[i];
                userBias[u] = sum / (settings.decimal("BIAS_REG", 1) + data.userCounts[u]);
            }
            logs.add(new Factorization.Log("BASELINE", sweep, training(1)));
        }
    }
    static Prediction predict(int method, int u, int i, int count) {
        double base = baseline(u, i);
        if (method == 0)
            return new Prediction(data.mean, false, 0, 0, -1);
        if (method == 1)
            return new Prediction(base, false, 0, 0, -1);
        if (method == 5)
            return new Prediction(svd.predict(u, i), false, 0, 0, -1);
        if (method == 6)
            return new Prediction(als.predict(u, i), false, 0, 0, -1);
        if (method == 4) {
            double numerator = 0;
            int denominator = 0;
            for (int j : data.byUser.get(u)) {
                int common = neighborhood.common[i][j];
                if (common > 0) {
                    double deviation =
                        (double)neighborhood.differences[i][j] / (common + settings.integer("SHRINKAGE"));
                    numerator += (deviation + data.ratings[u][j]) * common;
                    denominator += common;
                }
            }
            return denominator == 0 ? new Prediction(base, true, 0, 0, -1)
                                    : new Prediction(numerator / denominator, false, 0, 0, -1);
        }
        double[] similarities = method == 2 ? neighborhood.users[u] : neighborhood.items[i];
        List<Integer> candidates = new ArrayList<>();
        for (int index : method == 2 ? data.byItem.get(i) : data.byUser.get(u))
            if (similarities[index] > settings.number("MIN_SIMILARITY"))
                candidates.add(index);
        if (candidates.isEmpty())
            return new Prediction(base, true, 0, 0, -1);
        List<Integer> selected = Neighborhood.select(similarities, candidates, count);
        double numerator = 0, denominator = 0;
        for (int index : selected) {
            double rating = method == 2 ? data.ratings[index][i] - data.userMeans[index]
                                        : data.ratings[u][index] - data.itemMeans[index];
            numerator += similarities[index] * rating;
            denominator += similarities[index];
        }
        double mean = method == 2 ? data.userMeans[u] : data.itemMeans[i];
        return new Prediction(
            mean + numerator / denominator, false, selected.size(), denominator / selected.size(),
            method == 2 ? data.users.get(selected.get(0)) : data.items.get(selected.get(0)));
    }
    static List<Integer> ranked(int method, int u) {
        List<Integer> cached = lists.get(method).get(u);
        if (cached != null)
            return cached;
        List<Integer> result = new ArrayList<>();
        for (int i : popularity)
            if (data.ratings[u][i] == 0)
                result.add(i);
        if (method > 0) {
            double[] values = new double[items];
            for (int i : result)
                values[i] = predict(method, u, i, neighbors).value();
            result.sort((a, b) -> {
                int comparison = Double.compare(values[b], values[a]);
                return comparison != 0 ? comparison : Integer.compare(a, b);
            });
        }
        lists.get(method).set(u, result);
        return result;
    }
    static void prepare() {
        popularity = new ArrayList<>();
        for (int i = 0; i < items; i++)
            popularity.add(i);
        popularity.sort((a, b) -> {
            int comparison = Integer.compare(data.itemCounts[b], data.itemCounts[a]);
            if (comparison == 0)
                comparison = Double.compare(data.itemMeans[b], data.itemMeans[a]);
            return comparison != 0 ? comparison : Integer.compare(a, b);
        });
        for (int method = 0; method < 7; method++) {
            List<List<Integer>> rows = new ArrayList<>();
            for (int u = 0; u < users; u++)
                rows.add(null);
            lists.add(rows);
        }
        for (int u = 0; u < users; u++)
            relevant.add(new HashSet<>());
        for (Ratings.Rating row : data.test)
            if (row.rating() >= 4)
                relevant.get(row.user()).add(row.item());
        evaluated = new ArrayList<>();
        for (int u = 0; u < users; u++)
            if (!relevant.get(u).isEmpty())
                evaluated.add(u);
        predictions = new Prediction[7][tests];
        clipped = new double[7][tests];
        errors = new double[7][tests];
        clipCount = new int[7];
        fallbackCount = new int[7];
        rmse = new double[7];
        mae = new double[7];
        train = new double[7];
        for (int method = 0; method < 7; method++) {
            double square = 0, absolute = 0;
            for (int t = 0; t < tests; t++) {
                Ratings.Rating row = data.test.get(t);
                Prediction prediction = predict(method, row.user(), row.item(), neighbors);
                predictions[method][t] = prediction;
                clipped[method][t] = Evaluation.clip(prediction.value());
                errors[method][t] = clipped[method][t] - row.rating();
                square += errors[method][t] * errors[method][t];
                absolute += Math.abs(errors[method][t]);
                if (prediction.value() < 1 || prediction.value() > 5)
                    clipCount[method]++;
                if (prediction.fallback())
                    fallbackCount[method]++;
            }
            rmse[method] = Math.sqrt(square / tests);
            mae[method] = absolute / tests;
        }
        train[0] = training(0);
        train[1] = logs.get(9).rmse();
        train[5] = svd.log.getLast().rmse();
        train[6] = als.log.getLast().rmse();
    }
    static List<String> predictionReport() {
        List<String> out = new ArrayList<>(List.of("user,item,actual," + String.join(",", METHODS)));
        for (int t = 0; t < tests; t++) {
            Ratings.Rating row = data.test.get(t);
            String line = data.users.get(row.user()) + "," + data.items.get(row.item()) + "," + row.rating();
            for (int method = 0; method < 7; method++)
                line += "," + real(clipped[method][t]);
            out.add(line);
        }
        return out;
    }
    static void section(List<String> out, List<String> lines) {
        if (!out.isEmpty())
            out.add("");
        out.addAll(lines);
    }
    static List<String> genres(boolean test) {
        SortedSet<String> genres = new TreeSet<>();
        if (test) {
            for (Ratings.Rating row : data.test)
                genres.addAll(item(row.item()).genres());
        } else
            for (int i = 0; i < items; i++)
                genres.addAll(item(i).genres());
        return new ArrayList<>(genres);
    }
    static String counts(String label, int[] values) {
        int[] sorted = values.clone();
        Arrays.sort(sorted);
        return label + " min " + sorted[0] + " median " +
            real((sorted[(sorted.length - 1) / 2] + sorted[sorted.length / 2]) / 2.0) + " max " +
            sorted[sorted.length - 1];
    }
    static int group(int count, int[] boundaries) {
        int group = 0;
        for (int boundary : boundaries)
            if (count >= boundary)
                group++;
        return group;
    }
    static String metricPairs(List<Integer> indices, boolean absolute) {
        String line = "";
        for (int method = 0; method < 7; method++) {
            List<Double> values = new ArrayList<>();
            for (int t : indices)
                values.add(errors[method][t]);
            line += " " + METHODS.get(method) + " " +
                    real(absolute ? Evaluation.mae(values) : Evaluation.rmse(values));
        }
        return line;
    }
    static List<String> errorGroups(boolean user) {
        int[] boundaries = settings.list(user ? "USER_GROUPS" : "ITEM_GROUPS");
        List<String> out =
            new ArrayList<>(List.of((user ? "user" : "item") + "_groups bounds " + integers(boundaries)));
        for (int g = 0; g <= boundaries.length; g++) {
            List<Integer> indices = new ArrayList<>();
            for (int t = 0; t < tests; t++) {
                Ratings.Rating row = data.test.get(t);
                int count = user ? data.userCounts[row.user()] : data.itemCounts[row.item()];
                if (group(count, boundaries) == g)
                    indices.add(t);
            }
            out.add("group " + (g + 1) + " from " + (g == 0 ? 1 : boundaries[g - 1]) + " to " +
                    (g == boundaries.length ? "-" : Integer.toString(boundaries[g] - 1)) + " pairs " +
                    indices.size() + metricPairs(indices, false));
        }
        return out;
    }
    static List<String> ratingEvaluation() {
        List<String> out = new ArrayList<>();
        int[] histogram = new int[5];
        long first = Long.MAX_VALUE, last = 0;
        for (Ratings.Rating row : data.training) {
            histogram[row.rating() - 1]++;
            first = Math.min(first, row.time());
            last = Math.max(last, row.time());
        }
        section(out,
                List.of("data users " + users + " items " + items + " catalog " + data.catalog.size() +
                            " ratings " + data.training.size() + " test " + tests,
                        "density " + real((double)data.training.size() / (users * items)) + " global_mean " +
                            real(data.mean),
                        "histogram " + integers(histogram), counts("user_ratings", data.userCounts),
                        counts("item_ratings", data.itemCounts),
                        "timestamps first " + first + " last " + last,
                        "cold_items " + (data.catalog.size() - items),
                        "similarities user_pairs " + neighborhood.userPairs + " usable " +
                            neighborhood.userUsable + " item_pairs " + neighborhood.itemPairs + " usable " +
                            neighborhood.itemUsable + " slope_pairs " + neighborhood.slopePairs));
        List<String> part = new ArrayList<>(List.of("genre_stats"));
        for (String genre : genres(false)) {
            int count = 0, ratings = 0, high = 0;
            for (int i = 0; i < items; i++)
                if (item(i).genres().contains(genre)) {
                    count++;
                    ratings += data.itemCounts[i];
                    for (int u : data.byItem.get(i))
                        if (data.ratings[u][i] >= 4)
                            high++;
                }
            part.add("genre " + genre + " items " + count + " ratings " + ratings + " high " + high);
        }
        section(out, part);
        int buckets = settings.integer("TIME_BUCKETS");
        part = new ArrayList<>(List.of("time_buckets " + buckets));
        for (int bucket = 0; bucket < buckets; bucket++) {
            int count = 0, sum = 0;
            Set<Integer> selected = new HashSet<>();
            for (Ratings.Rating row : data.training)
                if ((row.time() - first) * buckets / (last - first + 1) == bucket) {
                    count++;
                    sum += row.rating();
                    selected.add(row.user());
                }
            part.add("bucket " + (bucket + 1) + " ratings " + count + " users " + selected.size() + " mean " +
                     real(count == 0 ? Double.NaN : (double)sum / count));
        }
        section(out, part);
        part = new ArrayList<>(List.of("rating_metrics"));
        for (int method = 0; method < 7; method++)
            part.add(METHODS.get(method) + " rmse " + real(rmse[method]) + " mae " + real(mae[method]) +
                     " clipped " + clipCount[method] + " fallback " + fallbackCount[method]);
        section(out, part);
        part = new ArrayList<>(List.of("generalization"));
        for (int method : new int[] {0, 1, 5, 6})
            part.add(METHODS.get(method) + " train " + real(train[method]) + " test " + real(rmse[method]) +
                     " gap " + real(rmse[method] - train[method]));
        section(out, part);
        part = new ArrayList<>(List.of("neighborhoods k " + neighbors));
        for (int method = 2; method <= 3; method++) {
            int with = 0, count = 0;
            double similarities = 0;
            for (Prediction prediction : predictions[method])
                if (!prediction.fallback()) {
                    with++;
                    count += prediction.count();
                    similarities += prediction.meanSimilarity();
                }
            part.add(METHODS.get(method) + " predictions " + tests + " with_neighbors " + with +
                     " mean_neighbors " + real(with == 0 ? Double.NaN : (double)count / with) +
                     " mean_similarity " + real(with == 0 ? Double.NaN : similarities / with));
        }
        section(out, part);
        double actualMean = 0;
        for (Ratings.Rating row : data.test)
            actualMean += row.rating();
        actualMean /= tests;
        double actualVariance = 0;
        for (Ratings.Rating row : data.test)
            actualVariance += (row.rating() - actualMean) * (row.rating() - actualMean);
        part = new ArrayList<>(List.of("prediction_stats actual mean " + real(actualMean) + " std " +
                                       real(Math.sqrt(actualVariance / tests))));
        for (int method = 0; method < 7; method++) {
            double mean = 0;
            for (double value : clipped[method])
                mean += value;
            mean /= tests;
            double variance = 0, covariance = 0;
            boolean constant = true;
            for (int t = 0; t < tests; t++) {
                double delta = clipped[method][t] - mean;
                variance += delta * delta;
                covariance += delta * (data.test.get(t).rating() - actualMean);
                if (clipped[method][t] != clipped[method][0])
                    constant = false;
            }
            part.add(METHODS.get(method) + " mean " + real(mean) + " std " +
                     real(Math.sqrt(variance / tests)) + " correlation " +
                     real(constant || actualVariance == 0
                              ? Double.NaN
                              : covariance / Math.sqrt(variance * actualVariance)));
        }
        section(out, part);
        part = new ArrayList<>(List.of("error_bins edges 0.5 1.0 1.5 2.0"));
        for (int method = 0; method < 7; method++) {
            int[] bins = new int[5];
            for (double error : errors[method])
                bins[Math.min(4, (int)Math.floor(Math.abs(error) * 2))]++;
            part.add(METHODS.get(method) + " " + integers(bins));
        }
        section(out, part);
        part = new ArrayList<>(List.of("comparison"));
        for (int a = 0; a < 7; a++)
            for (int b = a + 1; b < 7; b++) {
                int wins = 0, ties = 0, losses = 0;
                for (int t = 0; t < tests; t++) {
                    double left = Math.abs(errors[a][t]), right = Math.abs(errors[b][t]);
                    if (left < right)
                        wins++;
                    else if (left == right)
                        ties++;
                    else
                        losses++;
                }
                part.add(METHODS.get(a) + " " + METHODS.get(b) + " wins " + wins + " ties " + ties +
                         " losses " + losses);
            }
        section(out, part);
        section(out, errorGroups(true));
        section(out, errorGroups(false));
        part = new ArrayList<>(List.of("by_rating"));
        for (int value = 1; value <= 5; value++) {
            List<Integer> indices = new ArrayList<>();
            for (int t = 0; t < tests; t++)
                if (data.test.get(t).rating() == value)
                    indices.add(t);
            part.add("rating " + value + " pairs " + indices.size() + metricPairs(indices, true));
        }
        section(out, part);
        part = new ArrayList<>(List.of("genres"));
        for (String genre : genres(true)) {
            List<Integer> indices = new ArrayList<>();
            for (int t = 0; t < tests; t++)
                if (item(data.test.get(t).item()).genres().contains(genre))
                    indices.add(t);
            part.add("genre " + genre + " pairs " + indices.size() + metricPairs(indices, false));
        }
        section(out, part);
        return out;
    }
    static double log2(double value) {
        return Math.log(value) / Math.log(2);
    }
    static List<String> rankingEvaluation() {
        int count = evaluated.size(), relevantCount = 0;
        for (int u : evaluated)
            relevantCount += relevant.get(u).size();
        List<String> out = new ArrayList<>(List.of("ranking users " + count + " relevant " + relevantCount));
        for (int cutoff : settings.list("CUTOFFS")) {
            out.add("cutoff " + cutoff);
            for (int method = 0; method < 7; method++) {
                int hits = 0, hitUsers = 0;
                double recall = 0, ndcg = 0, ap = 0, rr = 0;
                for (int u : evaluated) {
                    Evaluation.Metrics m = Evaluation.ranking(ranked(method, u), relevant.get(u), cutoff);
                    hits += m.hits();
                    if (m.hits() > 0)
                        hitUsers++;
                    recall += m.recall();
                    ndcg += m.ndcg();
                    ap += m.ap();
                    rr += m.rr();
                }
                out.add("  " + RANKINGS.get(method) + " precision " + real((double)hits / (cutoff * count)) +
                        " recall " + real(recall / count) + " ndcg " + real(ndcg / count) + " map " +
                        real(ap / count) + " mrr " + real(rr / count) + " hit_rate " +
                        real((double)hitUsers / count));
            }
        }
        List<String> part =
            new ArrayList<>(List.of("beyond_accuracy top_n " + topN + " head " + (items / 5)));
        Set<Integer> head = new HashSet<>(popularity.subList(0, items / 5));
        for (int method = 0; method < 7; method++) {
            Set<Integer> coverage = new HashSet<>();
            int diversity = 0, popular = 0, tail = 0;
            double novelty = 0, similarity = 0;
            for (int u : evaluated) {
                List<Integer> list = ranked(method, u).subList(0, topN);
                coverage.addAll(list);
                Set<String> genres = new HashSet<>();
                double nov = 0, ils = 0;
                for (int i : list) {
                    genres.addAll(item(i).genres());
                    popular += data.itemCounts[i];
                    if (!head.contains(i))
                        tail++;
                    nov += log2((double)users / data.itemCounts[i]);
                }
                diversity += genres.size();
                novelty += nov / topN;
                for (int a = 0; a < topN - 1; a++)
                    for (int b = a + 1; b < topN; b++) {
                        double sim = neighborhood.items[list.get(a)][list.get(b)];
                        if (!Double.isNaN(sim))
                            ils += sim;
                    }
                similarity += ils / (topN * (topN - 1) / 2);
            }
            part.add(RANKINGS.get(method) + " coverage " + real((double)coverage.size() / items) +
                     " diversity " + real((double)diversity / count) + " novelty " + real(novelty / count) +
                     " popularity " + real((double)popular / (topN * count)) + " long_tail " +
                     real((double)tail / (topN * count)) + " similarity " + real(similarity / count));
        }
        section(out, part);
        int[] boundaries = settings.list("USER_GROUPS");
        part = new ArrayList<>(List.of("ranking_groups top_n " + topN + " bounds " + integers(boundaries)));
        for (int g = 0; g <= boundaries.length; g++) {
            List<Integer> selected = new ArrayList<>();
            for (int u : evaluated)
                if (group(data.userCounts[u], boundaries) == g)
                    selected.add(u);
            String line = "group " + (g + 1) + " users " + selected.size();
            for (int method = 0; method < 7; method++) {
                double sum = 0;
                for (int u : selected)
                    sum += Evaluation.ranking(ranked(method, u), relevant.get(u), topN).ndcg();
                line += " " + RANKINGS.get(method) + " " +
                        real(selected.isEmpty() ? Double.NaN : sum / selected.size());
            }
            part.add(line);
        }
        section(out, part);
        part = new ArrayList<>(List.of("agreement top_n " + topN));
        for (int a = 0; a < 7; a++)
            for (int b = a + 1; b < 7; b++) {
                double sum = 0;
                for (int u : evaluated) {
                    Set<Integer> common = new HashSet<>(ranked(a, u).subList(0, topN));
                    common.retainAll(ranked(b, u).subList(0, topN));
                    sum += (double)common.size() / (2 * topN - common.size());
                }
                part.add(RANKINGS.get(a) + " " + RANKINGS.get(b) + " jaccard " + real(sum / count));
            }
        section(out, part);
        return out;
    }
    static List<Integer> ordered(double[] values, boolean descending) {
        List<Integer> result = new ArrayList<>();
        for (int i = 0; i < values.length; i++)
            result.add(i);
        result.sort((a, b) -> {
            int comparison =
                descending ? Double.compare(values[b], values[a]) : Double.compare(values[a], values[b]);
            return comparison != 0 ? comparison : Integer.compare(a, b);
        });
        return result;
    }
    static List<String> gridAndBiases() {
        List<String> out = new ArrayList<>(List.of("neighbor_grid"));
        int[] grid = settings.list("NEIGHBOR_GRID"), best = {grid[0], grid[0]};
        double[] bestError = {Double.POSITIVE_INFINITY, Double.POSITIVE_INFINITY};
        for (int count : grid) {
            String line = "k " + count;
            for (int method = 2; method <= 3; method++) {
                List<Double> errors = new ArrayList<>();
                for (Ratings.Rating row : data.test)
                    errors.add(Evaluation.clip(predict(method, row.user(), row.item(), count).value()) -
                               row.rating());
                double error = Evaluation.rmse(errors);
                line += " " + METHODS.get(method) + " " + real(error);
                if (error < bestError[method - 2]) {
                    bestError[method - 2] = error;
                    best[method - 2] = count;
                }
            }
            out.add(line);
        }
        out.add("best USER_KNN " + best[0] + " ITEM_KNN " + best[1]);
        List<String> part = new ArrayList<>(List.of("biases"));
        for (int kind = 0; kind < 4; kind++) {
            boolean item = kind < 2, descending = kind % 2 == 0;
            double[] bias = item ? itemBias : userBias;
            List<Integer> order = ordered(bias, descending);
            for (int position = 0; position < listSize; position++) {
                int index = order.get(position);
                String label = (item ? "item" : "user") + (descending ? "_high" : "_low");
                part.add(label + " " + (item ? data.items.get(index) : data.users.get(index)) + " bias " +
                         real(bias[index]) + " count " +
                         (item ? data.itemCounts[index] : data.userCounts[index]) + " mean " +
                         real(item ? data.itemMeans[index] : data.userMeans[index]) +
                         (item ? " " + item(index).title() : ""));
            }
        }
        section(out, part);
        return out;
    }
    static List<String> evaluationReport() {
        List<String> out = ratingEvaluation();
        section(out, rankingEvaluation());
        section(out, gridAndBiases());
        return out;
    }
    static List<String> genrePreference(int u, boolean liked, Map<String, Integer> counts) {
        for (int i : data.byUser.get(u))
            if (liked ? data.ratings[u][i] >= 4 : data.ratings[u][i] <= 2)
                for (String genre : item(i).genres())
                    counts.put(genre, counts.getOrDefault(genre, 0) + 1);
        List<String> genres = new ArrayList<>(counts.keySet());
        genres.sort((a, b) -> {
            int comparison = Integer.compare(counts.get(b), counts.get(a));
            return comparison != 0 ? comparison : a.compareTo(b);
        });
        return new ArrayList<>(genres.subList(0, Math.min(3, genres.size())));
    }
    static String genreLine(String label, List<String> genres, Map<String, Integer> counts) {
        String line = label;
        for (String genre : genres)
            line += " " + genre + " " + counts.get(genre);
        return genres.isEmpty() ? line + " -" : line;
    }
    static String popularLine(int position, int i) {
        return "  " + position + " " + data.items.get(i) + " count " + data.itemCounts[i] + " mean " +
            real(data.itemMeans[i]) + " " + item(i).title();
    }
    static List<String> recommendationReport() {
        List<String> out = new ArrayList<>();
        for (int id : settings.list("RECOMMEND_USERS")) {
            List<String> part = new ArrayList<>();
            if (!data.userIndex.containsKey(id)) {
                part.add("user " + id + " unknown");
                part.add("list POPULAR");
                for (int position = 0; position < topN; position++)
                    part.add(popularLine(position + 1, popularity.get(position)));
                section(out, part);
                continue;
            }
            int u = data.userIndex.get(id);
            part.add("user " + id + " ratings " + data.userCounts[u] + " mean " + real(data.userMeans[u]) +
                     " bias " + real(userBias[u]));
            Map<String, Integer> likedCounts = new HashMap<>(), dislikedCounts = new HashMap<>();
            List<String> liked = genrePreference(u, true, likedCounts),
                         disliked = genrePreference(u, false, dislikedCounts);
            part.add(genreLine("liked_genres", liked, likedCounts));
            part.add(genreLine("disliked_genres", disliked, dislikedCounts));
            List<Ratings.Rating> recent = new ArrayList<>();
            for (Ratings.Rating row : data.training)
                if (row.user() == u)
                    recent.add(row);
            recent.sort((a, b) -> {
                int comparison = Long.compare(b.time(), a.time());
                return comparison != 0 ? comparison : Integer.compare(a.item(), b.item());
            });
            String line = "recent";
            for (int position = 0; position < Math.min(3, recent.size()); position++) {
                Ratings.Rating row = recent.get(position);
                line += " " + data.items.get(row.item()) + " " + row.rating();
            }
            part.add(line);
            List<Integer> candidates = new ArrayList<>();
            for (int v = 0; v < users; v++)
                if (neighborhood.users[u][v] > settings.number("MIN_SIMILARITY"))
                    candidates.add(v);
            for (int v : Neighborhood.select(neighborhood.users[u], candidates, listSize))
                part.add("neighbor " + data.users.get(v) + " similarity " + real(neighborhood.users[u][v]) +
                         " common " + neighborhood.userCommon[u][v]);
            for (int t = 0; t < tests; t++) {
                Ratings.Rating row = data.test.get(t);
                if (row.user() != u)
                    continue;
                line = "heldout " + data.items.get(row.item()) + " actual " + row.rating();
                for (int method = 0; method < 7; method++)
                    line += " " + real(clipped[method][t]);
                part.add(line);
            }
            for (int method = 0; method < 7; method++) {
                List<Integer> list = ranked(method, u).subList(0, topN);
                int matches = 0;
                for (int i : list) {
                    boolean match = false;
                    for (String genre : liked)
                        if (item(i).genres().contains(genre))
                            match = true;
                    if (match)
                        matches++;
                }
                part.add("list " + RANKINGS.get(method) + " genre_match " + matches);
                for (int position = 0; position < topN; position++) {
                    int i = list.get(position);
                    if (method == 0)
                        part.add(popularLine(position + 1, i));
                    else {
                        Prediction prediction = predict(method, u, i, neighbors);
                        line =
                            "  " + (position + 1) + " " + data.items.get(i) + " " + real(prediction.value());
                        if (method == 2 || method == 3)
                            line += " via " +
                                    (prediction.fallback() ? "-" : Integer.toString(prediction.neighbor()));
                        part.add(line + " " + item(i).title());
                    }
                }
            }
            section(out, part);
        }
        return out;
    }
    static List<String> similarReport() {
        List<String> out = new ArrayList<>();
        for (int id : settings.list("SIMILAR_ITEMS")) {
            int i = data.itemIndex.get(id);
            List<String> part =
                new ArrayList<>(List.of("item " + id + " ratings " + data.itemCounts[i] + " mean " +
                                        real(data.itemMeans[i]) + " bias " + real(itemBias[i]) + " genres " +
                                        item(i).genreText() + " title " + item(i).title()));
            for (int kind = 0; kind < 4; kind++) {
                part.add(List.of("cosine", "factors", "co_rated", "slope_one").get(kind));
                double[] values = new double[items];
                List<Integer> candidates = new ArrayList<>();
                for (int j = 0; j < items; j++)
                    if (j != i) {
                        if (kind == 0) {
                            values[j] = neighborhood.items[i][j];
                            if (!Double.isNaN(values[j]))
                                candidates.add(j);
                        } else if (kind == 1) {
                            values[j] = Factorization.dot(svd.items[i], svd.items[j]) /
                                        Math.sqrt(Factorization.dot(svd.items[i], svd.items[i]) *
                                                  Factorization.dot(svd.items[j], svd.items[j]));
                            candidates.add(j);
                        } else if (neighborhood.common[i][j] > 0) {
                            values[j] = kind == 2
                                            ? neighborhood.common[i][j]
                                            : (double)neighborhood.differences[j][i] /
                                                  (neighborhood.common[j][i] + settings.integer("SHRINKAGE"));
                            candidates.add(j);
                        }
                    }
                final int type = kind;
                candidates.sort((a, b) -> {
                    int comparison = Double.compare(values[b], values[a]);
                    if (comparison == 0 && type == 3)
                        comparison = Integer.compare(neighborhood.common[i][b], neighborhood.common[i][a]);
                    return comparison != 0 ? comparison : Integer.compare(a, b);
                });
                for (int position = 0; position < Math.min(listSize, candidates.size()); position++) {
                    int j = candidates.get(position);
                    String line = "  " + (position + 1) + " " + data.items.get(j);
                    if (kind < 2)
                        line += " similarity " + real(values[j]);
                    if (kind == 0 || kind == 2)
                        line += " common " + neighborhood.common[i][j];
                    if (kind == 3)
                        line += " difference " + neighborhood.differences[j][i] + " common " +
                                neighborhood.common[j][i];
                    part.add(line + " " + item(j).title());
                }
            }
            section(out, part);
        }
        return out;
    }
    static List<String> trainingReport() {
        List<String> out = new ArrayList<>(List.of("method,epoch,train_rmse"));
        for (Factorization.Log log : logs)
            out.add(log.method() + "," + log.epoch() + "," + real(log.rmse()));
        return out;
    }
    public static void main(String[] args) throws IOException {
        data = Ratings.read();
        settings = data.settings;
        users = data.users.size();
        items = data.items.size();
        tests = data.test.size();
        neighbors = settings.integer("NEIGHBORS");
        listSize = settings.integer("LIST_SIZE");
        topN = settings.integer("TOP_N");
        baseline();
        neighborhood = Neighborhood.compute(data);
        svd = Factorization.svd(data);
        als = Factorization.als(data, userBias, itemBias);
        logs.addAll(svd.log);
        logs.addAll(als.log);
        prepare();
        Report.write("predictions.csv", predictionReport());
        Report.write("evaluation.txt", evaluationReport());
        Report.write("recommendations.txt", recommendationReport());
        Report.write("similar_items.txt", similarReport());
        Report.write("training_log.csv", trainingReport());
    }
}
