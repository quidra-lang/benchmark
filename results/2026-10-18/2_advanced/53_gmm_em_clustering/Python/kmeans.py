"""Deterministic k-means updates and squared-distance inertia."""


def distance2(point, mean):
    dx = point["x"] - mean[0]
    dy = point["y"] - mean[1]
    return dx * dx + dy * dy


def distance(a, b):
    dx, dy = a[0] - b[0], a[1] - b[1]
    return (dx * dx + dy * dy) ** 0.5


def assignments(points, centers):
    return [
        min(range(len(centers)), key=lambda k: (
            distance2(point, centers[k]), k
        )) + 1 for point in points
    ]


def run_kmeans(points, initial_centers, max_iterations):
    centers = list(initial_centers)
    assigned = assignments(points, centers)
    iterations = 0
    for t in range(1, max_iterations + 1):
        new_centers = []
        for k in range(1, len(centers) + 1):
            members = [point for point, cluster in zip(points, assigned)
                       if cluster == k]
            if not members:
                new_centers.append(centers[k - 1])
            else:
                new_centers.append((
                    sum(point["x"] for point in members) / len(members),
                    sum(point["y"] for point in members) / len(members),
                ))
        centers = new_centers
        new_assignment = assignments(points, centers)
        iterations = t
        if new_assignment == assigned:
            assigned = new_assignment
            break
        assigned = new_assignment
    inertia = sum(
        distance2(point, centers[cluster - 1])
        for point, cluster in zip(points, assigned)
    )
    return {
        "centers": centers, "assignment": assigned,
        "iterations": iterations, "inertia": inertia,
        "sizes": [assigned.count(k) for k in range(1, len(centers) + 1)],
    }
