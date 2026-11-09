def squared_distance(first, second):
    total = 0.0
    for a, b in zip(first, second):
        difference = a - b
        total += difference * difference
    return total


def assign(points, centers):
    labels = []
    errors = []
    for point in points:
        best = 0
        best_distance = squared_distance(point, centers[0])
        for j in range(1, len(centers)):
            distance = squared_distance(point, centers[j])
            if distance < best_distance:
                best = j
                best_distance = distance
        labels.append(best)
        errors.append(best_distance)
    return labels, errors


def mean_point(points):
    totals = [0.0] * len(points[0])
    for point in points:
        for component, value in enumerate(point):
            totals[component] += value
    return [total / len(points) for total in totals]


def cluster_sizes(labels, k):
    sizes = [0] * k
    for label in labels:
        sizes[label] += 1
    return sizes


def cluster_center(points, labels, j):
    return mean_point([point for point, label in zip(points, labels) if label == j])


def cluster_centers(points, labels, k):
    return [cluster_center(points, labels, j) for j in range(k)]


def refill(labels, errors, k):
    sizes = cluster_sizes(labels, k)
    reseeds = 0
    for j in range(k):
        if sizes[j] > 0:
            continue
        chosen = None
        for i, label in enumerate(labels):
            if sizes[label] >= 2 and (chosen is None or errors[i] > errors[chosen]):
                chosen = i
        sizes[labels[chosen]] -= 1
        sizes[j] += 1
        labels[chosen] = j
        errors[chosen] = 0.0
        reseeds += 1
    return reseeds


class LloydResult:
    def __init__(self, labels, centers, iterations, converged, reseeds):
        self.labels = labels
        self.centers = centers
        self.iterations = iterations
        self.converged = converged
        self.reseeds = reseeds


def lloyd(points, initial_centers, max_iterations):
    k = len(initial_centers)
    labels, errors = assign(points, initial_centers)
    iterations = 0
    reseeds = 0
    converged = False
    while iterations < max_iterations and not converged:
        reseeds += refill(labels, errors, k)
        centers = cluster_centers(points, labels, k)
        iterations += 1
        new_labels, errors = assign(points, centers)
        converged = new_labels == labels
        labels = new_labels
    reseeds += refill(labels, errors, k)
    centers = cluster_centers(points, labels, k)
    return LloydResult(labels, centers, iterations, converged, reseeds)


def sse(points, labels, centers):
    total = 0.0
    for point, label in zip(points, labels):
        total += squared_distance(point, centers[label])
    return total
