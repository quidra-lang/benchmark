from collections import deque


NOISE = -1
UNDECIDED = -2


def dbscan(neighborhoods, min_pts):
    core = [len(neighbors) >= min_pts for neighbors in neighborhoods]
    labels = [UNDECIDED] * len(neighborhoods)
    cluster = 0
    for point in range(len(neighborhoods)):
        if labels[point] != UNDECIDED:
            continue
        if not core[point]:
            labels[point] = NOISE
            continue
        labels[point] = cluster
        queue = deque(neighborhoods[point])
        while queue:
            other = queue.popleft()
            if labels[other] == NOISE:
                labels[other] = cluster
            elif labels[other] == UNDECIDED:
                labels[other] = cluster
                if core[other]:
                    queue.extend(neighborhoods[other])
        cluster += 1
    return labels, core
