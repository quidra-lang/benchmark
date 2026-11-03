PREVIOUS_NEIGHBORS = {
    4: ((-1, 0), (0, -1)),
    8: ((-1, 0), (-1, -1), (0, -1), (1, -1)),
}


class Labeling:
    def __init__(self, labels, count, provisional):
        self.labels = labels
        self.count = count
        self.provisional = provisional


def find(parents, label):
    while parents[label] != label:
        parents[label] = parents[parents[label]]
        label = parents[label]
    return label


def union(parents, first, second):
    first_root = find(parents, first)
    second_root = find(parents, second)
    if first_root != second_root:
        parents[max(first_root, second_root)] = min(first_root, second_root)


def label_components(mask, connectivity):
    height = len(mask)
    width = len(mask[0])
    provisional = [[0] * width for _ in range(height)]
    parents = [0]
    for y in range(height):
        for x in range(width):
            if not mask[y][x]:
                continue
            neighbors = []
            for dx, dy in PREVIOUS_NEIGHBORS[connectivity]:
                nx = x + dx
                ny = y + dy
                if 0 <= nx < width and 0 <= ny and mask[ny][nx]:
                    neighbors.append(provisional[ny][nx])
            if neighbors:
                provisional[y][x] = neighbors[0]
                for other in neighbors[1:]:
                    union(parents, neighbors[0], other)
            else:
                provisional[y][x] = len(parents)
                parents.append(len(parents))
    numbers = [0] * len(parents)
    labels = [[0] * width for _ in range(height)]
    count = 0
    for y in range(height):
        for x in range(width):
            if provisional[y][x] == 0:
                continue
            root = find(parents, provisional[y][x])
            if numbers[root] == 0:
                count += 1
                numbers[root] = count
            labels[y][x] = numbers[root]
    return Labeling(labels, count, len(parents) - 1)


def occupied(mask, x, y):
    return 0 <= y < len(mask) and 0 <= x < len(mask[y]) and mask[y][x]


def bit_quad_euler(mask, connectivity):
    singles = 0
    triples = 0
    diagonals = 0
    for y in range(-1, len(mask)):
        for x in range(-1, len(mask[0])):
            top_left = occupied(mask, x, y)
            top_right = occupied(mask, x + 1, y)
            bottom_left = occupied(mask, x, y + 1)
            bottom_right = occupied(mask, x + 1, y + 1)
            count = top_left + top_right + bottom_left + bottom_right
            if count == 1:
                singles += 1
            elif count == 3:
                triples += 1
            elif count == 2 and (top_left and bottom_right or top_right and bottom_left):
                diagonals += 1
    if connectivity == 8:
        return (singles - triples - 2 * diagonals) // 4
    return (singles - triples + 2 * diagonals) // 4
