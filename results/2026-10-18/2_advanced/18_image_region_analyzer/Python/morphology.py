NEIGHBORHOOD = ((0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1))


def is_foreground(mask, x, y):
    return 0 <= y < len(mask) and 0 <= x < len(mask[y]) and mask[y][x]


def erode(mask, offsets):
    return [
        [all(is_foreground(mask, x + dx, y + dy) for dx, dy in offsets) for x in range(len(row))]
        for y, row in enumerate(mask)
    ]


def dilate(mask, offsets):
    return [
        [any(is_foreground(mask, x - dx, y - dy) for dx, dy in offsets) for x in range(len(row))]
        for y, row in enumerate(mask)
    ]


def opening(mask, offsets):
    return dilate(erode(mask, offsets), offsets)


def closing(mask, offsets):
    return erode(dilate(mask, offsets), offsets)


def neighbor_bits(pixels, x, y):
    return [(x + dx, y + dy) in pixels for dx, dy in NEIGHBORHOOD]


def transitions(bits):
    return sum(1 for index in range(8) if not bits[index] and bits[(index + 1) % 8])


def crossing_number(pixels, x, y):
    return transitions(neighbor_bits(pixels, x, y))


def removable(bits, first_step):
    if not 2 <= sum(bits) <= 6 or transitions(bits) != 1:
        return False
    p2, p4, p6, p8 = bits[0], bits[2], bits[4], bits[6]
    if first_step:
        return not (p2 and p4 and p6) and not (p4 and p6 and p8)
    return not (p2 and p4 and p8) and not (p2 and p6 and p8)


def thinning_step(skeleton, first_step):
    removed = [
        (x, y) for x, y in skeleton
        if removable(neighbor_bits(skeleton, x, y), first_step)
    ]
    skeleton.difference_update(removed)
    return len(removed) > 0


def thin(pixels):
    skeleton = set(pixels)
    while True:
        removed_first = thinning_step(skeleton, True)
        removed_second = thinning_step(skeleton, False)
        if not removed_first and not removed_second:
            return skeleton
