"""Train the seven recommenders and write all five deterministic reports."""

from bisect import bisect_right
from collections import namedtuple
from itertools import combinations
from math import log2, sqrt
from pathlib import Path

from evaluation import clip, mae, ranking_metrics, rmse, sequential_sum, training_rmse
from factorization import dot, train_als, train_svd
from neighborhood import Neighborhood, largest_neighbors
from ratings import read_inputs
from report import optional, real, write_lines


METHODS = ("GLOBAL", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS")
RANKINGS = ("POPULAR",) + METHODS[1:]
KNN_METHODS = ("USER_KNN", "ITEM_KNN")
Prediction = namedtuple(
    "Prediction", "value fallback neighbors similarity top", defaults=(False, 0, 0.0, None)
)


def separate_sections(sections):
    lines = []
    for section in sections:
        if lines:
            lines.append("")
        lines.extend(section)
    return lines


def count_summary(counts):
    ordered = sorted(counts)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        median = ordered[middle]
    else:
        median = (ordered[middle - 1] + ordered[middle]) / 2
    return f"min {ordered[0]} median {real(median)} max {ordered[-1]}"


class Recommender:
    def __init__(self, data):
        self.data = data
        self.params = data.params
        self.neighborhood = Neighborhood(data, self.params["shrinkage"])
        self.user_bias = dict.fromkeys(data.users, 0.0)
        self.item_bias = dict.fromkeys(data.items, 0.0)
        self.popularity = sorted(
            data.items,
            key=lambda item: (-data.item_counts[item], -data.item_means[item], item),
        )
        self.head = len(data.items) // 5
        self.popular_items = set(self.popularity[:self.head])
        self.log = []
        self.train_errors = {}
        self.predictions = {method: [] for method in METHODS}
        self.clipped = {method: [] for method in METHODS}
        self.errors = {method: [] for method in METHODS}
        self.metrics = {}
        self.relevant = {}
        self.rankings = {}
        self.ranking_predictions = {}

    def baseline(self, user, item):
        return (self.data.mean + self.user_bias[user]) + self.item_bias[item]

    def train(self):
        data = self.data
        item_reg, user_reg = self.params["bias_reg"]
        self.train_errors["GLOBAL"] = training_rmse(data.training, lambda u, i: data.mean)
        for sweep in range(1, 11):
            for item in data.items:
                total = 0.0
                for user, rating in data.by_item[item].items():
                    total += rating - data.mean - self.user_bias[user]
                self.item_bias[item] = total / (item_reg + data.item_counts[item])
            for user in data.users:
                total = 0.0
                for item, rating in data.by_user[user].items():
                    total += rating - data.mean - self.item_bias[item]
                self.user_bias[user] = total / (user_reg + data.user_counts[user])
            error = training_rmse(data.training, self.baseline)
            self.log.append(("BASELINE", sweep, error))
        self.train_errors["BASELINE"] = self.log[-1][2]
        self.svd, log = train_svd(data)
        self.log.extend(log)
        self.train_errors["SVD"] = log[-1][2]
        self.als, log = train_als(data, self.user_bias, self.item_bias)
        self.log.extend(log)
        self.train_errors["ALS"] = log[-1][2]

    def user_prediction(self, user, item, size):
        candidates = []
        for other in self.data.by_item[item]:
            similarity = self.neighborhood.user_similarity(user, other)
            if similarity is not None and similarity[0] > self.params["min_similarity"]:
                candidates.append((other, similarity[0]))
        selected = largest_neighbors(candidates, size)
        if not selected:
            return Prediction(self.baseline(user, item), fallback=True)
        numerator = denominator = 0.0
        for other, similarity in selected:
            rating = self.data.by_item[item][other]
            numerator += similarity * (rating - self.data.user_means[other])
            denominator += similarity
        value = self.data.user_means[user] + numerator / denominator
        return Prediction(value, False, len(selected), denominator / len(selected), selected[0][0])

    def item_prediction(self, user, item, size):
        candidates = []
        for other in self.data.by_user[user]:
            similarity = self.neighborhood.item_similarity(item, other)
            if similarity is not None and similarity[0] > self.params["min_similarity"]:
                candidates.append((other, similarity[0]))
        selected = largest_neighbors(candidates, size)
        if not selected:
            return Prediction(self.baseline(user, item), fallback=True)
        numerator = denominator = 0.0
        for other, similarity in selected:
            rating = self.data.by_user[user][other]
            numerator += similarity * (rating - self.data.item_means[other])
            denominator += similarity
        value = self.data.item_means[item] + numerator / denominator
        return Prediction(value, False, len(selected), denominator / len(selected), selected[0][0])

    def slope_prediction(self, user, item):
        numerator = 0.0
        denominator = 0
        for other, rating in self.data.by_user[user].items():
            count = self.neighborhood.common_count(item, other)
            if count:
                deviation = self.neighborhood.deviation(item, other)
                numerator += (deviation + rating) * count
                denominator += count
        if denominator == 0:
            return Prediction(self.baseline(user, item), fallback=True)
        return Prediction(numerator / denominator)

    def predict(self, method, user, item, size=None):
        if size is None:
            size = self.params["neighbors"]
        if method == "GLOBAL":
            return Prediction(self.data.mean)
        if method == "BASELINE":
            return Prediction(self.baseline(user, item))
        if method == "USER_KNN":
            return self.user_prediction(user, item, size)
        if method == "ITEM_KNN":
            return self.item_prediction(user, item, size)
        if method == "SLOPE_ONE":
            return self.slope_prediction(user, item)
        if method == "SVD":
            return Prediction(self.svd.predict(user, item))
        if method == "ALS":
            return Prediction(self.als.predict(user, item))
        raise ValueError(f"Unknown prediction method: {method}")

    def predict_tests(self):
        lines = ["user,item,actual," + ",".join(METHODS)]
        for user, item, actual in self.data.test:
            fields = [str(user), str(item), str(actual)]
            for method in METHODS:
                prediction = self.predict(method, user, item)
                clipped = clip(prediction.value)
                self.predictions[method].append(prediction)
                self.clipped[method].append(clipped)
                self.errors[method].append(clipped - actual)
                fields.append(real(clipped))
            lines.append(",".join(fields))
        for method in METHODS:
            predictions = self.predictions[method]
            self.metrics[method] = (
                rmse(self.errors[method]),
                mae(self.errors[method]),
                sum(p.value < 1 or p.value > 5 for p in predictions),
                sum(p.fallback for p in predictions),
            )
        return lines

    def prepare_rankings(self):
        relevant = {}
        for user, item, rating in self.data.test:
            if rating >= 4:
                relevant.setdefault(user, set()).add(item)
        self.relevant = {user: relevant[user] for user in sorted(relevant)}
        requested = set(self.params["recommend_users"]) & set(self.data.users)
        for user in sorted(set(self.relevant) | requested):
            rated = self.data.by_user[user]
            candidates = [item for item in self.data.items if item not in rated]
            lists = {"POPULAR": [item for item in self.popularity if item not in rated]}
            predictions = {}
            for method in METHODS[1:]:
                values = {item: self.predict(method, user, item) for item in candidates}
                predictions[method] = values
                lists[method] = sorted(candidates, key=lambda item: (-values[item].value, item))
            self.rankings[user] = lists
            self.ranking_predictions[user] = predictions

    def data_summary(self):
        data = self.data
        histogram = [0] * 5
        for user, item, rating, timestamp in data.training:
            histogram[rating - 1] += 1
        first = min(row[3] for row in data.training)
        last = max(row[3] for row in data.training)
        theta = self.params["min_similarity"]
        user_usable = sum(value[0] > theta for value in self.neighborhood.user.values())
        item_usable = sum(value[0] > theta for value in self.neighborhood.item.values())
        return [
            f"data users {len(data.users)} items {len(data.items)} catalog {len(data.titles)} "
            f"ratings {len(data.training)} test {len(data.test)}",
            f"density {real(len(data.training) / (len(data.users) * len(data.items)))} "
            f"global_mean {real(data.mean)}",
            "histogram " + " ".join(map(str, histogram)),
            "user_ratings " + count_summary(data.user_counts.values()),
            "item_ratings " + count_summary(data.item_counts.values()),
            f"timestamps first {first} last {last}",
            f"cold_items {len(data.titles) - len(data.items)}",
            f"similarities user_pairs {len(self.neighborhood.user)} usable {user_usable} "
            f"item_pairs {len(self.neighborhood.item)} usable {item_usable} "
            f"slope_pairs {len(self.neighborhood.counts)}",
        ]

    def genre_summary(self):
        data = self.data
        genres = sorted({genre for item in data.items for genre in data.genres[item]})
        lines = ["genre_stats"]
        for genre in genres:
            items = [item for item in data.items if genre in data.genres[item]]
            ratings = sum(data.item_counts[item] for item in items)
            high = sum(rating >= 4 for item in items for rating in data.by_item[item].values())
            lines.append(f"genre {genre} items {len(items)} ratings {ratings} high {high}")
        return lines

    def time_summary(self):
        buckets = self.params["time_buckets"]
        counts = [0] * buckets
        totals = [0] * buckets
        users = [set() for _ in range(buckets)]
        first = min(row[3] for row in self.data.training)
        last = max(row[3] for row in self.data.training)
        for user, item, rating, timestamp in self.data.training:
            bucket = (timestamp - first) * buckets // (last - first + 1)
            counts[bucket] += 1
            totals[bucket] += rating
            users[bucket].add(user)
        lines = [f"time_buckets {buckets}"]
        for bucket in range(buckets):
            count = counts[bucket]
            mean = totals[bucket] / count if count else None
            lines.append(
                f"bucket {bucket + 1} ratings {count} users {len(users[bucket])} mean {real(mean)}"
            )
        return lines

    def rating_metrics(self):
        lines = ["rating_metrics"]
        for method in METHODS:
            error, absolute, clipped, fallback = self.metrics[method]
            lines.append(
                f"{method} rmse {real(error)} mae {real(absolute)} "
                f"clipped {clipped} fallback {fallback}"
            )
        return lines

    def generalization(self):
        lines = ["generalization"]
        for method in ("GLOBAL", "BASELINE", "SVD", "ALS"):
            train = self.train_errors[method]
            test = self.metrics[method][0]
            lines.append(f"{method} train {real(train)} test {real(test)} gap {real(test - train)}")
        return lines

    def neighborhood_usage(self):
        lines = [f"neighborhoods k {self.params['neighbors']}"]
        for method in KNN_METHODS:
            used = [p for p in self.predictions[method] if not p.fallback]
            count = len(used)
            mean_count = sum(p.neighbors for p in used) / count if count else None
            similarity = sequential_sum(p.similarity for p in used) / count if count else None
            lines.append(
                f"{method} predictions {len(self.data.test)} with_neighbors {count} "
                f"mean_neighbors {real(mean_count)} mean_similarity {real(similarity)}"
            )
        return lines

    def prediction_statistics(self):
        actual = [row[2] for row in self.data.test]
        count = len(actual)
        actual_mean = sum(actual) / count
        actual_variation = sequential_sum(
            (rating - actual_mean) * (rating - actual_mean) for rating in actual
        )
        actual_std = sqrt(actual_variation / count)
        lines = [f"prediction_stats actual mean {real(actual_mean)} std {real(actual_std)}"]
        for method in METHODS:
            values = self.clipped[method]
            mean = sequential_sum(values) / count
            variation = sequential_sum((value - mean) * (value - mean) for value in values)
            standard_deviation = sqrt(variation / count)
            correlation = None
            if min(values) != max(values) and min(actual) != max(actual):
                covariance = sequential_sum(
                    (value - mean) * (rating - actual_mean)
                    for value, rating in zip(values, actual)
                )
                correlation = covariance / sqrt(variation * actual_variation)
            lines.append(
                f"{method} mean {real(mean)} std {real(standard_deviation)} "
                f"correlation {real(correlation)}"
            )
        return lines

    def error_bins(self):
        lines = ["error_bins edges 0.5 1.0 1.5 2.0"]
        for method in METHODS:
            bins = [0] * 5
            for error in self.errors[method]:
                bins[bisect_right((0.5, 1.0, 1.5, 2.0), abs(error))] += 1
            lines.append(method + " " + " ".join(map(str, bins)))
        return lines

    def comparison(self):
        lines = ["comparison"]
        for first, second in combinations(METHODS, 2):
            wins = ties = losses = 0
            for left, right in zip(self.errors[first], self.errors[second]):
                if abs(left) < abs(right):
                    wins += 1
                elif abs(left) == abs(right):
                    ties += 1
                else:
                    losses += 1
            lines.append(f"{first} {second} wins {wins} ties {ties} losses {losses}")
        return lines

    def errors_for(self, indices, metric=rmse):
        return " ".join(
            f"{method} {real(metric([self.errors[method][index] for index in indices]))}"
            for method in METHODS
        )

    def group_errors(self, kind):
        bounds = self.params[kind + "_groups"]
        counts = self.data.user_counts if kind == "user" else self.data.item_counts
        field = 0 if kind == "user" else 1
        groups = [[] for _ in range(len(bounds) + 1)]
        for index, row in enumerate(self.data.test):
            groups[bisect_right(bounds, counts[row[field]])].append(index)
        lines = [kind + "_groups bounds " + " ".join(map(str, bounds))]
        for number, indices in enumerate(groups):
            lower = 1 if number == 0 else bounds[number - 1]
            upper = bounds[number] - 1 if number < len(bounds) else None
            lines.append(
                f"group {number + 1} from {lower} to {optional(upper)} pairs {len(indices)} "
                + self.errors_for(indices)
            )
        return lines

    def rating_errors(self):
        lines = ["by_rating"]
        for rating in range(1, 6):
            indices = [index for index, row in enumerate(self.data.test) if row[2] == rating]
            lines.append(f"rating {rating} pairs {len(indices)} " + self.errors_for(indices, mae))
        return lines

    def genre_errors(self):
        genres = sorted({
            genre for _, item, _ in self.data.test for genre in self.data.genres[item]
        })
        lines = ["genres"]
        for genre in genres:
            indices = [
                index for index, row in enumerate(self.data.test)
                if genre in self.data.genres[row[1]]
            ]
            lines.append(f"genre {genre} pairs {len(indices)} " + self.errors_for(indices))
        return lines

    def user_ranking_metrics(self, method, user, cutoff):
        return ranking_metrics(self.rankings[user][method], self.relevant[user], cutoff)

    def ranking_evaluation(self):
        count = len(self.relevant)
        relevant_count = sum(len(items) for items in self.relevant.values())
        lines = [f"ranking users {count} relevant {relevant_count}"]
        for cutoff in self.params["cutoffs"]:
            lines.append(f"cutoff {cutoff}")
            for method in RANKINGS:
                metrics = [
                    self.user_ranking_metrics(method, user, cutoff) for user in self.relevant
                ]
                precision = sum(metric[0] for metric in metrics) / (cutoff * count)
                recall = sequential_sum(metric[1] for metric in metrics) / count
                ndcg = sequential_sum(metric[2] for metric in metrics) / count
                average_precision = sequential_sum(metric[3] for metric in metrics) / count
                reciprocal_rank = sequential_sum(metric[4] for metric in metrics) / count
                hit_rate = sum(metric[0] >= 1 for metric in metrics) / count
                lines.append(
                    f"  {method} precision {real(precision)} recall {real(recall)} "
                    f"ndcg {real(ndcg)} map {real(average_precision)} "
                    f"mrr {real(reciprocal_rank)} hit_rate {real(hit_rate)}"
                )
        return lines

    def beyond_accuracy(self):
        data = self.data
        size = self.params["top_n"]
        count = len(self.relevant)
        pair_count = size * (size - 1) // 2
        lines = [f"beyond_accuracy top_n {size} head {self.head}"]
        for method in RANKINGS:
            distinct = set()
            diversity = popularity = long_tail = 0
            novelty = similarity = 0.0
            for user in self.relevant:
                ranked = self.rankings[user][method][:size]
                distinct.update(ranked)
                diversity += len({genre for item in ranked for genre in data.genres[item]})
                novelty += sequential_sum(
                    log2(len(data.users) / data.item_counts[item]) for item in ranked
                ) / size
                popularity += sum(data.item_counts[item] for item in ranked)
                long_tail += sum(item not in self.popular_items for item in ranked)
                pair_similarity = 0.0
                for first, second in combinations(ranked, 2):
                    value = self.neighborhood.item_similarity(first, second)
                    pair_similarity += value[0] if value is not None else 0.0
                similarity += pair_similarity / pair_count
            lines.append(
                f"{method} coverage {real(len(distinct) / len(data.items))} "
                f"diversity {real(diversity / count)} novelty {real(novelty / count)} "
                f"popularity {real(popularity / (size * count))} "
                f"long_tail {real(long_tail / (size * count))} "
                f"similarity {real(similarity / count)}"
            )
        return lines

    def ranking_groups(self):
        size = self.params["top_n"]
        bounds = self.params["user_groups"]
        groups = [[] for _ in range(len(bounds) + 1)]
        for user in self.relevant:
            groups[bisect_right(bounds, self.data.user_counts[user])].append(user)
        lines = [f"ranking_groups top_n {size} bounds " + " ".join(map(str, bounds))]
        for number, users in enumerate(groups, 1):
            fields = [f"group {number} users {len(users)}"]
            for method in RANKINGS:
                mean = None
                if users:
                    mean = sequential_sum(
                        self.user_ranking_metrics(method, user, size)[2] for user in users
                    ) / len(users)
                fields.append(f"{method} {real(mean)}")
            lines.append(" ".join(fields))
        return lines

    def agreement(self):
        size = self.params["top_n"]
        lines = [f"agreement top_n {size}"]
        for first, second in combinations(RANKINGS, 2):
            total = 0.0
            for user in self.relevant:
                left = set(self.rankings[user][first][:size])
                right = set(self.rankings[user][second][:size])
                total += len(left & right) / len(left | right)
            lines.append(f"{first} {second} jaccard {real(total / len(self.relevant))}")
        return lines

    def neighbor_grid(self):
        lines = ["neighbor_grid"]
        errors = {method: {} for method in KNN_METHODS}
        for size in self.params["neighbor_grid"]:
            fields = [f"k {size}"]
            for method in KNN_METHODS:
                residuals = []
                for user, item, actual in self.data.test:
                    prediction = self.predict(method, user, item, size)
                    residuals.append(clip(prediction.value) - actual)
                error = rmse(residuals)
                errors[method][size] = error
                fields.append(f"{method} {real(error)}")
            lines.append(" ".join(fields))
        fields = ["best"]
        for method in KNN_METHODS:
            best = min(errors[method], key=lambda size: (errors[method][size], size))
            fields.append(f"{method} {best}")
        lines.append(" ".join(fields))
        return lines

    def bias_lists(self):
        size = self.params["list_size"]
        data = self.data
        lines = ["biases"]
        for kind, ids, biases, counts, means in (
            ("item", data.items, self.item_bias, data.item_counts, data.item_means),
            ("user", data.users, self.user_bias, data.user_counts, data.user_means),
        ):
            for label, sign in (("high", -1), ("low", 1)):
                ordered = sorted(
                    ids, key=lambda identity: (sign * biases[identity], identity)
                )[:size]
                for identity in ordered:
                    line = (
                        f"{kind}_{label} {identity} bias {real(biases[identity])} "
                        f"count {counts[identity]} mean {real(means[identity])}"
                    )
                    if kind == "item":
                        line += " " + data.titles[identity]
                    lines.append(line)
        return lines

    def evaluation_report(self):
        return separate_sections([
            self.data_summary(),
            self.genre_summary(),
            self.time_summary(),
            self.rating_metrics(),
            self.generalization(),
            self.neighborhood_usage(),
            self.prediction_statistics(),
            self.error_bins(),
            self.comparison(),
            self.group_errors("user"),
            self.group_errors("item"),
            self.rating_errors(),
            self.genre_errors(),
            self.ranking_evaluation(),
            self.beyond_accuracy(),
            self.ranking_groups(),
            self.agreement(),
            self.neighbor_grid(),
            self.bias_lists(),
        ])

    def preferred_genres(self, user, liked):
        counts = {}
        for item, rating in self.data.by_user[user].items():
            qualifies = rating >= 4 if liked else rating <= 2
            if qualifies:
                for genre in self.data.genres[item]:
                    counts[genre] = counts.get(genre, 0) + 1
        return sorted(counts.items(), key=lambda entry: (-entry[1], entry[0]))[:3]

    def popularity_line(self, rank, item):
        data = self.data
        return (
            f"  {rank} {item} count {data.item_counts[item]} "
            f"mean {real(data.item_means[item])} {data.titles[item]}"
        )

    def recommendation_line(self, user, method, rank, item):
        if method == "POPULAR":
            return self.popularity_line(rank, item)
        prediction = self.ranking_predictions[user][method][item]
        line = f"  {rank} {item} {real(prediction.value)}"
        if method in KNN_METHODS:
            line += " via " + optional(prediction.top)
        return line + " " + self.data.titles[item]

    def known_user_recommendations(self, user):
        data = self.data
        size = self.params["top_n"]
        lines = [
            f"user {user} ratings {data.user_counts[user]} mean {real(data.user_means[user])} "
            f"bias {real(self.user_bias[user])}"
        ]
        liked = self.preferred_genres(user, True)
        disliked = self.preferred_genres(user, False)
        for label, genres in (("liked_genres", liked), ("disliked_genres", disliked)):
            entries = " ".join(f"{genre} {count}" for genre, count in genres)
            lines.append(label + " " + (entries or "-"))
        recent = sorted(
            (row for row in data.training if row[0] == user),
            key=lambda row: (-row[3], row[1]),
        )[:3]
        lines.append("recent " + " ".join(f"{item} {rating}" for _, item, rating, _ in recent))
        candidates = []
        for other in data.users:
            similarity = self.neighborhood.user_similarity(user, other)
            if similarity is not None and similarity[0] > self.params["min_similarity"]:
                candidates.append((other, similarity[0]))
        for other, similarity in largest_neighbors(candidates, self.params["list_size"]):
            common = self.neighborhood.user_similarity(user, other)[1]
            lines.append(f"neighbor {other} similarity {real(similarity)} common {common}")
        for index, (held_user, item, rating) in enumerate(data.test):
            if held_user == user:
                values = " ".join(real(self.clipped[method][index]) for method in METHODS)
                lines.append(f"heldout {item} actual {rating} {values}")
        liked_names = {genre for genre, count in liked}
        for method in RANKINGS:
            ranked = self.rankings[user][method][:size]
            matched = sum(
                any(genre in liked_names for genre in data.genres[item]) for item in ranked
            )
            lines.append(f"list {method} genre_match {matched}")
            for rank, item in enumerate(ranked, 1):
                lines.append(self.recommendation_line(user, method, rank, item))
        return lines

    def recommendations(self):
        sections = []
        for user in self.params["recommend_users"]:
            if user in self.data.by_user:
                sections.append(self.known_user_recommendations(user))
            else:
                lines = [f"user {user} unknown", "list POPULAR"]
                for rank, item in enumerate(self.popularity[:self.params["top_n"]], 1):
                    lines.append(self.popularity_line(rank, item))
                sections.append(lines)
        return separate_sections(sections)

    def similar_items(self):
        data = self.data
        size = self.params["list_size"]
        factors = self.svd.items
        norms = {item: dot(factors[item], factors[item]) for item in data.items}
        sections = []
        for item in self.params["similar_items"]:
            lines = [
                f"item {item} ratings {data.item_counts[item]} mean {real(data.item_means[item])} "
                f"bias {real(self.item_bias[item])} genres {data.genre_text[item]} "
                f"title {data.titles[item]}",
                "cosine",
            ]
            candidates = []
            for other in data.items:
                value = self.neighborhood.item_similarity(item, other)
                if value is not None:
                    candidates.append((other, value[0]))
            for rank, (other, similarity) in enumerate(largest_neighbors(candidates, size), 1):
                common = self.neighborhood.item_similarity(item, other)[1]
                lines.append(
                    f"  {rank} {other} similarity {real(similarity)} "
                    f"common {common} {data.titles[other]}"
                )
            candidates = []
            for other in data.items:
                if other != item:
                    cosine = dot(factors[item], factors[other]) / sqrt(norms[item] * norms[other])
                    candidates.append((other, cosine))
            lines.append("factors")
            for rank, (other, similarity) in enumerate(largest_neighbors(candidates, size), 1):
                lines.append(f"  {rank} {other} similarity {real(similarity)} {data.titles[other]}")
            common_items = [
                other for other in data.items
                if self.neighborhood.common_count(item, other) >= 1
            ]
            ordered = sorted(
                common_items,
                key=lambda other: (-self.neighborhood.common_count(item, other), other),
            )
            lines.append("co_rated")
            for rank, other in enumerate(ordered[:size], 1):
                common = self.neighborhood.common_count(item, other)
                lines.append(f"  {rank} {other} common {common} {data.titles[other]}")
            ordered = sorted(
                common_items,
                key=lambda other: (
                    -self.neighborhood.deviation(other, item),
                    -self.neighborhood.common_count(other, item),
                    other,
                ),
            )
            lines.append("slope_one")
            for rank, other in enumerate(ordered[:size], 1):
                difference = self.neighborhood.difference(other, item)
                common = self.neighborhood.common_count(other, item)
                lines.append(
                    f"  {rank} {other} difference {difference} common {common} {data.titles[other]}"
                )
            sections.append(lines)
        return separate_sections(sections)

    def training_log(self):
        return ["method,epoch,train_rmse"] + [
            f"{method},{epoch},{real(error)}" for method, epoch, error in self.log
        ]


def main():
    recommender = Recommender(read_inputs())
    recommender.train()
    predictions = recommender.predict_tests()
    recommender.prepare_rankings()
    outputs = {
        "predictions.csv": predictions,
        "evaluation.txt": recommender.evaluation_report(),
        "recommendations.txt": recommender.recommendations(),
        "similar_items.txt": recommender.similar_items(),
        "training_log.csv": recommender.training_log(),
    }
    for filename, lines in outputs.items():
        write_lines(Path("output") / filename, lines)


if __name__ == "__main__":
    main()
