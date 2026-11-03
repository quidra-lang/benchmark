"""Fit and evaluate deterministic Gaussian mixtures in two dimensions."""

from collections import Counter
from fractions import Fraction
from itertools import combinations, permutations
import math

from dataset import read_all
from em import (
    point_xy, responsibilities, run_em,
)
from gaussian import (
    bhattacharyya, eigen_data, mahalanobis, weighted_log_density,
)
from kmeans import distance, distance2, run_kmeans
from report import LEVELS, dec, framed, optional, values, write_blocks, write_lines


PARAMETERS = {
    "FULL": lambda k: 6 * k - 1,
    "TIED": lambda k: 3 * k + 2,
    "DIAG": lambda k: 5 * k - 1,
    "SPHERICAL": lambda k: 4 * k - 1,
}


def rounded_four(number):
    """Use the written 4-decimal value for rankings and selection ties."""
    return float(dec(number))


def estimate_models(points, initial, params):
    models = []
    n = len(points)
    for count in params["ks"]:
        for type_index, type_name in enumerate(params["types"]):
            trained = run_em(
                points, initial[count], type_name, params["iterations"],
                params["epsilon"], params["settle"],
            )
            likelihood = trained["loglik"]
            parameter_count = PARAMETERS[type_name](count)
            bic = -2 * likelihood + parameter_count * math.log(n)
            aic = -2 * likelihood + 2 * parameter_count
            assignment = []
            entropy = 0.0
            sizes = [0] * count
            for record in trained["records"]:
                r = record["responsibilities"]
                chosen = max(range(count), key=lambda j: (r[j], -j)) + 1
                assignment.append(chosen)
                sizes[chosen - 1] += 1
                entropy += -sum(
                    value * math.log(value) for value in r if value > 0
                )
            trained.update({
                "k": count, "type": type_name, "type_index": type_index,
                "parameter_count": parameter_count,
                "bic": bic, "aic": aic, "icl": bic + 2 * entropy,
                "entropy": entropy, "mean_entropy": entropy / n,
                "assignment": assignment, "sizes": sizes,
            })
            models.append(trained)
    return models


def ranking(models, criterion):
    return sorted(
        models,
        key=lambda model: (
            rounded_four(model[criterion]),
            model["parameter_count"], model["k"], model["type_index"]
        ),
    )


def model_key(model):
    return model["k"], model["type"]


def build_rankings(models):
    ranked = {criterion: ranking(models, criterion)
              for criterion in ("bic", "aic", "icl")}
    ranks = {
        criterion: {model_key(model): index
                    for index, model in enumerate(ranked[criterion], 1)}
        for criterion in ranked
    }
    return ranked, ranks


def kmeans_all(points, initial, params):
    return {
        k: run_kmeans(points, initial[k]["means"],
                      params["kmeans_iterations"])
        for k in params["ks"]
    }


def contingency(left, right, rows, columns):
    table = [[0] * columns for _ in range(rows)]
    for a, b in zip(left, right):
        table[a - 1][b - 1] += 1
    return table


def choose2(n):
    return n * (n - 1) // 2


def adjusted_rand(left, right, rows, columns):
    table = contingency(left, right, rows, columns)
    shared = sum(choose2(value) for row in table for value in row)
    a = sum(choose2(sum(row)) for row in table)
    b = sum(choose2(sum(table[r][c] for r in range(rows)))
            for c in range(columns))
    total = choose2(len(left))
    numerator = 2 * (total * shared - a * b)
    denominator = total * (a + b) - 2 * a * b
    return Fraction(1, 1) if denominator == 0 else Fraction(
        numerator, denominator
    )


def ari_str(fraction):
    return f"{fraction.numerator}/{fraction.denominator} {dec(float(fraction))}"


def sqdistance(a, b):
    dx, dy = a[0] - b[0], a[1] - b[1]
    return dx * dx + dy * dy


def partition_metrics(points, labels, count):
    """Silhouette, Calinski-Harabasz and Davies-Bouldin by assigned partition."""
    sizes = [labels.count(j) for j in range(1, count + 1)]
    occupied = [j for j in range(1, count + 1) if sizes[j - 1]]
    if len(occupied) < 2:
        return {
            "silhouette": None, "cluster_silhouettes": {},
            "ch": None, "db": None,
        }
    clusters = {
        k: [i for i, label in enumerate(labels) if label == k]
        for k in occupied
    }
    centroids = {}
    for k, indices in clusters.items():
        centroids[k] = (
            sum(points[i]["x"] for i in indices) / len(indices),
            sum(points[i]["y"] for i in indices) / len(indices),
        )
    distances = []
    for i, point in enumerate(points):
        row = []
        for j, other in enumerate(points):
            row.append(math.sqrt(sqdistance(point_xy(point), point_xy(other))))
        distances.append(row)
    silhouetted = []
    for i, current in enumerate(labels):
        member = clusters[current]
        if len(member) == 1:
            silhouetted.append(0.0)
            continue
        own = sum(distances[i][j] for j in member if j != i)
        own /= len(member) - 1
        other = min(
            sum(distances[i][j] for j in clusters[k]) / len(clusters[k])
            for k in occupied if k != current
        )
        silhouetted.append((other - own) / max(own, other))
    center = (
        sum(p["x"] for p in points) / len(points),
        sum(p["y"] for p in points) / len(points),
    )
    between = sum(
        sizes[k - 1] * sqdistance(centroids[k], center) for k in occupied
    )
    within = sum(
        sqdistance(point_xy(point), centroids[labels[i]])
        for i, point in enumerate(points)
    )
    g = len(occupied)
    ch = (between / (g - 1)) / (within / (len(points) - g))
    scattered = {
        k: sum(
            math.sqrt(sqdistance(point_xy(points[i]), centroids[k]))
            for i in clusters[k]
        ) / len(clusters[k])
        for k in occupied
    }
    db = sum(
        max(
            (scattered[k] + scattered[j])
            / math.sqrt(sqdistance(centroids[k], centroids[j]))
            for j in occupied if j != k
        )
        for k in occupied
    ) / g
    return {
        "silhouette": sum(silhouetted) / len(points),
        "cluster_silhouettes": {
            k: sum(silhouetted[i] for i in clusters[k]) / len(clusters[k])
            for k in occupied
        },
        "ch": ch, "db": db,
    }


def parents(previous, current):
    table = contingency(previous["assignment"], current["assignment"],
                        previous["k"], current["k"])
    answer, shared = [], []
    for col in range(current["k"]):
        counts = [table[row][col] for row in range(previous["k"])]
        if sum(counts) == 0:
            answer.append("-")
            shared.append(0)
        else:
            row = max(range(previous["k"]), key=lambda k: (counts[k], -k))
            answer.append(row + 1)
            shared.append(counts[row])
    return answer, shared


def best_matching(left, right, k):
    table = contingency(left, right, k, k)
    candidates = permutations(range(1, k + 1))
    best = max(
        candidates,
        key=lambda perm: (
            sum(table[perm[j] - 1][j] for j in range(k)),
            tuple(-x for x in perm),
        ),
    )
    agreement = sum(table[best[j] - 1][j] for j in range(k))
    return best, agreement, table


def component_details(model, points, edges, metrics):
    """Principal axes, Mahalanobis containment and chi-square GOF histograms."""
    k_count = model["k"]
    components = []
    covariances = model["model"]["covariances"]
    means = model["model"]["means"]
    records = model["records"]
    for k in range(k_count):
        member_indices = [i for i, label in enumerate(model["assignment"])
                          if label == k + 1]
        geometry = eigen_data(covariances[k])
        squared = [
            mahalanobis(point_xy(point), means[k], covariances[k])
            for point in points
        ]
        distances = [math.sqrt(squared[i]) for i in member_indices]
        boundaries = [0.0] + edges + [float("inf")]
        observed = []
        expected = []
        for left, right in zip(boundaries, boundaries[1:]):
            observed.append(sum(left <= value < right for value in distances))
            start_probability = math.exp(-left * left / 2)
            end_probability = 0.0 if math.isinf(right) else math.exp(-right * right / 2)
            expected.append(
                len(member_indices) * (start_probability - end_probability)
            )
        chi_square = sum(
            (o - e) * (o - e) / e for o, e in zip(observed, expected)
        )
        components.append({
            "number": k + 1,
            "weight": model["model"]["weights"][k],
            "mean": means[k],
            "cov": covariances[k],
            "size": len(member_indices),
            "soft_size": sum(row["responsibilities"][k] for row in records),
            "inside_one": sum(squared[i] <= 1 for i in member_indices),
            "inside_two": sum(squared[i] <= 4 for i in member_indices),
            "silhouette": metrics["cluster_silhouettes"].get(k + 1),
            "observed": observed, "expected": expected,
            "chi_square": chi_square,
            **geometry,
        })
    return components


def overlaps(model, points):
    components = []
    for first, second in combinations(range(model["k"]), 2):
        distance_value, coefficient = bhattacharyya(
            model["model"]["means"][first],
            model["model"]["covariances"][first],
            model["model"]["means"][second],
            model["model"]["covariances"][second],
        )
        shared = sum(
            row["responsibilities"][first] *
            row["responsibilities"][second]
            for row in model["records"]
        )
        components.append({
            "first": first + 1, "second": second + 1,
            "distance": distance_value,
            "coefficient": coefficient, "shared": shared,
        })
    return components


def cluster_entropy(clusters, records):
    entropy = 0.0
    for row in records:
        for cluster in clusters:
            probability = sum(row["responsibilities"][k - 1] for k in cluster)
            if probability > 0:
                entropy -= probability * math.log(probability)
    return entropy


def merging_steps(model):
    """Greedily merge the pair that minimizes entropy rounded to four places."""
    clusters = [(k,) for k in range(1, model["k"] + 1)]
    start_entropy = cluster_entropy(clusters, model["records"])
    steps = []
    while len(clusters) > 1:
        candidates = []
        for i in range(len(clusters)):
            for j in range(i + 1, len(clusters)):
                proposed = clusters.copy()
                proposed[i] = tuple(sorted(clusters[i] + clusters[j]))
                del proposed[j]
                proposed.sort(key=lambda row: row[0])
                new_entropy = cluster_entropy(proposed, model["records"])
                candidates.append((rounded_four(new_entropy), i, j,
                                   new_entropy, proposed))
        _, i, j, new_entropy, merged = min(
            candidates, key=lambda row: row[:3]
        )
        assigned = []
        for record in model["records"]:
            probabilities = [
                sum(record["responsibilities"][k - 1] for k in cluster)
                for cluster in merged
            ]
            assigned.append(
                max(range(len(merged)),
                    key=lambda k: (probabilities[k], -k))
            )
        sizes = [assigned.count(k) for k in range(len(merged))]
        steps.append({
            "first": "+".join(map(str, clusters[i])),
            "second": "+".join(map(str, clusters[j])),
            "entropy": new_entropy,
            "sizes": sizes,
        })
        clusters = merged
    return start_entropy, steps


def refit_from_kmeans(model, kmeans, points, settings):
    initial = {"weights": [], "means": [], "covariances": []}
    k = model["k"]
    for cluster in range(1, k + 1):
        members = [
            point for point, label in zip(points, kmeans["assignment"])
            if label == cluster
        ]
        cx, cy = kmeans["centers"][cluster - 1]
        count = len(members)
        initial["weights"].append(count / len(points))
        initial["means"].append((cx, cy))
        a = sum((p["x"] - cx) ** 2 for p in members) / count
        b = sum((p["x"] - cx) * (p["y"] - cy) for p in members) / count
        c = sum((p["y"] - cy) ** 2 for p in members) / count
        initial["covariances"].append(
            (a + settings["epsilon"], b, c + settings["epsilon"])
        )
    result = run_em(points, initial, model["type"], settings["iterations"],
                    settings["epsilon"], settings["settle"])
    assignment = [
        max(range(k), key=lambda j: (r["responsibilities"][j], -j)) + 1
        for r in result["records"]
    ]
    return {
        **result,
        "assignment": assignment,
        "sizes": [assignment.count(i) for i in range(1, k + 1)],
        "bic": -2 * result["loglik"] + model["parameter_count"] * math.log(len(points)),
        "ari": adjusted_rand(model["assignment"], assignment, k, k),
    }


def cross_validate(model, points, init, settings):
    folds = settings["cv_folds"]
    rows = []
    for f in range(folds):
        training = [p for i, p in enumerate(points) if i % folds != f]
        testing = [p for i, p in enumerate(points) if i % folds == f]
        fitted = run_em(training, init[model["k"]], model["type"],
                        settings["iterations"], settings["epsilon"],
                        settings["settle"])
        test_records, total_loglik = responsibilities(testing, fitted["model"])
        rows.append({
            "fold": f + 1, "train": len(training), "test": len(testing),
            "train_loglik": fitted["loglik"] / len(training),
            "test_loglik": total_loglik / len(testing),
        })
    return rows, sum(row["test_loglik"] for row in rows) / folds


def model_blocks(models):
    blocks = []
    for trained in models:
        mixture = trained["model"]
        block = [
            f"model K={trained['k']} type={trained['type']}",
            f"parameters {trained['parameter_count']}",
            f"loglik {dec(trained['loglik'])}",
            f"bic {dec(trained['bic'])}",
            f"aic {dec(trained['aic'])}",
            f"icl {dec(trained['icl'])}",
            f"mean_entropy {dec(trained['mean_entropy'])}",
            f"settled_at {trained['settled_at']}",
            f"largest_increase iteration {trained['largest_increase'][0]} "
            f"value {dec(trained['largest_increase'][1])}",
            f"violations {len(trained['violations'])}",
            "sizes " + values(trained["sizes"]),
        ]
        for index in range(trained["k"]):
            geometry = eigen_data(mixture["covariances"][index])
            block.append(
                f"component {index + 1} weight {dec(mixture['weights'][index])} "
                f"mean {values(mixture['means'][index])} "
                f"cov {values(mixture['covariances'][index])} "
                f"axes {values(geometry['axes'])} angle {dec(geometry['angle'])}"
            )
        blocks.append(block)
    return blocks


def trace_lines(models, iterations):
    rows = ["K,type,iteration,loglik"]
    for trained in models:
        for step, score in enumerate(trained["trace"]):
            rows.append(
                f"{trained['k']},{trained['type']},{step},{dec(score)}"
            )
    return rows


def assignment_lines(selected, kmeans, points):
    rows = ["id,component,max_responsibility,log_density,kmeans_cluster"]
    for index, point in enumerate(points):
        record = selected["records"][index]
        rows.append(
            f"{point['id']},{selected['assignment'][index]},"
            f"{dec(max(record['responsibilities']))},"
            f"{dec(record['log_density'])},"
            f"{kmeans['assignment'][index]}"
        )
    return rows


def ranking_block(models, ranks):
    ordered = ranks["ordered"]
    bic_ranked = ordered["bic"]
    best = bic_ranked[0]
    baseline = rounded_four(best["bic"])
    block = [
        "ranking by bic",
        "rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank",
    ]
    for position, model in enumerate(bic_ranked, 1):
        key = model_key(model)
        block.append(
            f"{position} {model['k']} {model['type']} "
            f"{model['parameter_count']} {dec(model['loglik'])} "
            f"{dec(model['bic'])} "
            f"{dec(rounded_four(model['bic']) - baseline)} "
            f"{dec(model['aic'])} {ranks['aic'][key]} "
            f"{dec(model['icl'])} {ranks['icl'][key]}"
        )
    for label, criterion in (
        ("selected", "bic"), ("best_aic", "aic"), ("best_icl", "icl")
    ):
        model = ordered[criterion][0]
        block.append(
            f"{label} K={model['k']} type={model['type']}"
        )
    return block


def best_per_type_block(models, settings):
    block = ["best K per type"]
    for kind in settings["types"]:
        by_type = [model for model in models if model["type"] == kind]
        block.append(
            f"{kind} bic {ranking(by_type, 'bic')[0]['k']} "
            f"aic {ranking(by_type, 'aic')[0]['k']} "
            f"icl {ranking(by_type, 'icl')[0]['k']}"
        )
    return block


def per_k_blocks(models, means, points, settings):
    blocks = []
    previous = None
    for count in settings["ks"]:
        selected = ranking([model for model in models if model["k"] == count],
                           "bic")[0]
        kmeans = means[count]
        ari = adjusted_rand(
            selected["assignment"], kmeans["assignment"], count, count
        )
        gmm_stats = partition_metrics(points, selected["assignment"], count)
        kmeans_stats = partition_metrics(points, kmeans["assignment"], count)
        block = [
            f"K={count} type={selected['type']} bic {dec(selected['bic'])}",
            f"  kmeans iterations {kmeans['iterations']} inertia {dec(kmeans['inertia'])}",
            f"  ari {ari_str(ari)}",
            f"  silhouette gmm {optional(gmm_stats['silhouette'])} "
            f"kmeans {optional(kmeans_stats['silhouette'])}",
            f"  calinski_harabasz gmm {optional(gmm_stats['ch'])} "
            f"kmeans {optional(kmeans_stats['ch'])}",
            f"  davies_bouldin gmm {optional(gmm_stats['db'])} "
            f"kmeans {optional(kmeans_stats['db'])}",
        ]
        if previous is not None:
            parents_list, shares = parents(previous, selected)
            block.append(
                f"  parents K={previous['k']} "
                + " ".join(map(str, parents_list))
                + " shared " + values(shares)
            )
        previous = selected
        blocks.append(block)
    return blocks


def violation_block(models):
    rows = ["violations"]
    for model in models:
        for t in model["violations"]:
            rows.append(
                f"K={model['k']} type={model['type']} iteration {t} "
                f"previous {dec(model['trace'][t - 1])} "
                f"current {dec(model['trace'][t])}"
            )
    if len(rows) == 1:
        rows.append("none")
    return rows


def components_block(components):
    lines = ["selected components"]
    for component in components:
        k = component["number"]
        x, y = component["mean"]
        a, b, c = component["cov"]
        sx, sy = component["axes"]
        dx, dy = component["direction"]
        lines += [
            f"component {k} weight {dec(component['weight'])} "
            f"size {component['size']} soft_size {dec(component['soft_size'])} "
            f"mean {dec(x)} {dec(y)}",
            f"  cov {values((a, b, c))} corr {dec(component['correlation'])}",
            f"  eigen {dec(component['leading'])} {dec(component['trailing'])} "
            f"direction {dec(dx)} {dec(dy)} angle {dec(component['angle'])}",
            f"  axes_1sigma {dec(sx)} {dec(sy)} "
            f"axes_2sigma {dec(2 * sx)} {dec(2 * sy)}",
            f"  inside_1sigma {component['inside_one']} "
            f"inside_2sigma {component['inside_two']} "
            f"area_1sigma {dec(component['area'])}",
            f"  silhouette {optional(component['silhouette'])}",
            f"  gof observed {values(component['observed'])} "
            f"expected {values(component['expected'])} "
            f"chi2 {dec(component['chi_square'])}",
        ]
    return lines


def overlap_block(overlap):
    lines = ["overlap"]
    for pair in overlap:
        lines.append(
            f"{pair['first']}-{pair['second']} "
            f"bhattacharyya {dec(pair['distance'])} "
            f"coefficient {dec(pair['coefficient'])} shared {dec(pair['shared'])}"
        )
    if not overlap:
        lines.append("none")
    return lines


def merging_block(initial_entropy, steps):
    lines = ["merging", f"start entropy {dec(initial_entropy)}"]
    for index, step in enumerate(steps, 1):
        lines.append(
            f"step {index} merge {step['first']} {step['second']} "
            f"entropy {dec(step['entropy'])} sizes {values(step['sizes'])}"
        )
    return lines


def kmeans_block(model, means, points):
    n = len(points)
    count = model["k"]
    ari = adjusted_rand(model["assignment"], means["assignment"], count, count)
    matching, agreement, table = best_matching(
        model["assignment"], means["assignment"], count
    )
    rows = [
        f"kmeans K={count}",
        f"iterations {means['iterations']}",
        f"inertia {dec(means['inertia'])}",
        "sizes " + values(means["sizes"]),
    ]
    for index, center in enumerate(means["centers"], 1):
        rows.append(f"center {index} {values(center)}")
    rows.append("contingency")
    rows += [values(row) for row in table]
    rows.extend([
        "ari " + ari_str(ari),
        "matching " + values(matching),
        f"agreement {agreement}/{n} {dec(agreement / n)}",
    ])
    disagree = []
    for i, point in enumerate(points):
        component = model["assignment"][i]
        cluster = means["assignment"][i]
        if matching[cluster - 1] != component:
            disagree.append(
                f"disagree {point['id']} gmm {component} "
                f"kmeans {cluster} "
                f"max {dec(max(model['records'][i]['responsibilities']))}"
            )
    rows += disagree
    rows.append(f"disagreements {len(disagree)}")
    return rows


def refit_block(model, refit):
    return [
        f"refit_from_kmeans K={model['k']} type={model['type']}",
        f"loglik {dec(refit['loglik'])} bic {dec(refit['bic'])} "
        f"settled_at {refit['settled_at']}",
        "sizes " + values(refit["sizes"]),
        "ari_vs_selected " + ari_str(refit["ari"]),
    ]


def crossvalidation_block(model, cv, mean, settings):
    rows = [
        f"cross_validation K={model['k']} type={model['type']} "
        f"folds {settings['cv_folds']}",
    ]
    for item in cv:
        rows.append(
            f"fold {item['fold']} train {item['train']} test {item['test']} "
            f"train_loglik {dec(item['train_loglik'])} "
            f"test_loglik {dec(item['test_loglik'])}"
        )
    rows.append(f"mean_test_loglik {dec(mean)}")
    return rows


def uncertainty_block(selected, points, threshold):
    uncertain = [
        i for i, row in enumerate(selected["records"])
        if max(row["responsibilities"]) < threshold
    ]
    uncertain.sort(key=lambda i: (
        rounded_four(max(selected["records"][i]["responsibilities"])), i
    ))
    lines = [f"uncertain threshold {dec(threshold)}"]
    for i in uncertain:
        row = selected["records"][i]
        lines.append(
            f"{points[i]['id']} component {selected['assignment'][i]} "
            f"max {dec(max(row['responsibilities']))} "
            f"responsibilities {values(row['responsibilities'])}"
        )
    lines.append(f"count {len(uncertain)}")
    return lines


def outliers_block(selected, points, threshold):
    outliers = [
        i for i, row in enumerate(selected["records"])
        if row["log_density"] < threshold
    ]
    outliers.sort(key=lambda i: (
        rounded_four(selected["records"][i]["log_density"]), i
    ))
    lines = [f"outliers threshold {dec(threshold)}"]
    for i in outliers:
        row = selected["records"][i]
        k = selected["assignment"][i] - 1
        quadratic = mahalanobis(
            point_xy(points[i]), selected["model"]["means"][k],
            selected["model"]["covariances"][k],
        )
        lines.append(
            f"{points[i]['id']} component {k + 1} "
            f"log_density {dec(row['log_density'])} q {dec(quadratic)}"
        )
    lines.append(f"count {len(outliers)}")
    return lines


def selection_blocks(models, selected, all_means, points, initial, settings):
    ranked, ranks = build_rankings(models)
    ranks["ordered"] = ranked
    blocks = [
        ranking_block(models, ranks),
        best_per_type_block(models, settings),
    ]
    blocks += per_k_blocks(models, all_means, points, settings)
    blocks.append(violation_block(models))
    metrics = partition_metrics(
        points, selected["assignment"], selected["k"]
    )
    components = component_details(
        selected, points, settings["gof_edges"], metrics
    )
    blocks.append(components_block(components))
    blocks.append(overlap_block(overlaps(selected, points)))
    entropy, merges = merging_steps(selected)
    blocks.append(merging_block(entropy, merges))
    means = all_means[selected["k"]]
    blocks.append(kmeans_block(selected, means, points))
    refit = refit_from_kmeans(selected, means, points, settings)
    blocks.append(refit_block(selected, refit))
    cv, mean = cross_validate(selected, points, initial, settings)
    blocks.append(crossvalidation_block(selected, cv, mean, settings))
    blocks.append(uncertainty_block(selected, points, settings["uncertain"]))
    blocks.append(outliers_block(selected, points, settings["low_density"]))
    return blocks


def map_center(row, col, xmin, ymax, dx, dy):
    return xmin + (col + 0.5) * dx, ymax - (row + 0.5) * dy


def map_density_and_responsibility(model, coordinates):
    mixture = model["model"]
    scores = [
        weighted_log_density(
            coordinates, mixture["weights"][k],
            mixture["means"][k], mixture["covariances"][k],
        ) for k in range(model["k"])
    ]
    maximum = max(scores)
    unnormalized = [math.exp(value - maximum) for value in scores]
    normalizer = sum(unnormalized)
    density = math.exp(maximum) * normalizer
    r = [value / normalizer for value in unnormalized]
    winner = max(range(model["k"]), key=lambda k: (scores[k], -k)) + 1
    return density, r, winner


def plot_maps(model, points, settings):
    """Four maps: density, maximum component, posterior entropy and observations."""
    xmin, xmax = settings["map_x"]
    ymin, ymax = settings["map_y"]
    width, height = settings["map_size"]
    dx = (xmax - xmin) / width
    dy = (ymax - ymin) / height
    coordinates = [
        [map_center(row, col, xmin, ymax, dx, dy)
         for col in range(width)]
        for row in range(height)
    ]
    measures = [
        [map_density_and_responsibility(model, coord) for coord in line]
        for line in coordinates
    ]
    maximum = max(point[0] for row in measures for point in row)
    densities, regions, uncertainty = [], [], []
    level_counts = [0] * 10
    for row in range(height):
        density_line, region_line, uncertainty_line = [], [], []
        for col in range(width):
            density, responsibility, component = measures[row][col]
            level = min(9, math.floor(10 * density / maximum))
            level_counts[level] += 1
            density_line.append(LEVELS[level])
            region_line.append(str(component))
            if model["k"] == 1:
                uncertainty_line.append(" ")
            else:
                entropy = -sum(
                    probability * math.log(probability)
                    for probability in responsibility if probability > 0
                )
                value = max(0, min(9, math.floor(
                    10 * entropy / math.log(model["k"])
                )))
                uncertainty_line.append(LEVELS[value])
        densities.append(density_line)
        regions.append(region_line)
        uncertainty.append(uncertainty_line)
    for k, mean in enumerate(model["model"]["means"], 1):
        col = math.floor((mean[0] - xmin) / dx)
        row = math.floor((ymax - mean[1]) / dy)
        if 0 <= col < width and 0 <= row < height:
            densities[row][col] = str(k)

    point_bins = {}
    outside = 0
    for point, label in zip(points, model["assignment"]):
        col = math.floor((point["x"] - xmin) / dx)
        row = math.floor((ymax - point["y"]) / dy)
        if 0 <= col < width and 0 <= row < height:
            point_bins.setdefault((row, col), set()).add(label)
        else:
            outside += 1
    points_image = []
    for row in range(height):
        cells = []
        for col in range(width):
            assigned = point_bins.get((row, col))
            if assigned:
                cells.append(str(next(iter(assigned)))
                             if len(assigned) == 1 else "*")
                continue
            contour = False
            for k in range(model["k"]):
                mean = model["model"]["means"][k]
                cov = model["model"]["covariances"][k]
                if mahalanobis(coordinates[row][col], mean, cov) > 4:
                    continue
                for r, c in ((row - 1, col), (row + 1, col),
                             (row, col - 1), (row, col + 1)):
                    if (0 <= r < height and 0 <= c < width
                            and mahalanobis(coordinates[r][c], mean, cov) > 4):
                        contour = True
                        break
                if contour:
                    break
            cells.append("." if contour else " ")
        points_image.append(cells)
    mass = sum(point[0] for row in measures for point in row) * dx * dy
    result = [
        f"density K={model['k']} type={model['type']}",
        f"x {dec(xmin)} {dec(xmax)} y {dec(ymin)} {dec(ymax)} "
        f"grid {width}x{height}",
        f"max_density {dec(maximum, 6)} mass_in_map {dec(mass)}",
    ]
    result.extend(framed(densities))
    for level in range(10):
        character = LEVELS[level]
        result.append(
            f'level {level} "{character}" from {dec(level * maximum / 10, 6)} '
            f"cells {level_counts[level]}"
        )
    result += ["", "regions"] + framed(regions)
    result += ["", "uncertainty"] + framed(uncertainty)
    result += ["", "points"] + framed(points_image)
    result.append(f"outside {outside}")
    return result


def main():
    points, initial, settings = read_all()
    models = estimate_models(points, initial, settings)
    selected = ranking(models, "bic")[0]
    means = kmeans_all(points, initial, settings)

    write_blocks("models.txt", model_blocks(models))
    write_lines("loglik_trace.csv", trace_lines(models, settings["iterations"]))
    write_lines("assignments.csv", assignment_lines(
        selected, means[selected["k"]], points
    ))
    write_blocks("selection.txt", selection_blocks(
        models, selected, means, points, initial, settings
    ))
    write_lines("density_map.txt", plot_maps(selected, points, settings))


if __name__ == "__main__":
    main()
