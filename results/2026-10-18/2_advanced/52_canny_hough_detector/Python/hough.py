"""Integer Hough voting for line bins and circle centers with peak tests."""

from collections import Counter, defaultdict
from fractions import Fraction


def rho(point, angle, trig, step):
    x, y = point
    cosine, sine = trig[angle]
    return (x * cosine + y * sine) // (16384 * step)


def circle_points(radius):
    points = set()
    a, b, error = radius, 0, 1 - radius
    while a >= b:
        points.update((
            (a, b), (b, a), (-b, a), (-a, b),
            (-a, -b), (-b, -a), (b, -a), (a, -b),
        ))
        b += 1
        if error < 0:
            error += 2 * b + 1
        else:
            a -= 1
            error += 2 * (b - a) + 1
    return points


def circle_votes(edges, width, height, params):
    """Vote by translating every circle offset around each edge pixel."""
    cells = {}
    outlines = {}
    for radius in range(params["circle_min_radius"],
                        params["circle_max_radius"] + 1):
        offsets = circle_points(radius)
        outlines[radius] = offsets
        votes = Counter()
        for x, y in edges:
            for dx, dy in offsets:
                cx, cy = x + dx, y + dy
                if 0 <= cx < width and 0 <= cy < height:
                    votes[(cx, cy)] += 1
        cells[radius] = votes
    return cells, outlines


def circle_peaks(cells, outlines, width, height, minimum):
    candidates = []
    peaks = []
    for radius, votes in cells.items():
        outline_count = len(outlines[radius])
        for y in range(height):
            for x in range(width):
                count = votes[(x, y)]
                if 100 * count < minimum * outline_count:
                    continue
                candidates.append((radius, x, y, count))
                before = (radius, y, x)
                peak = True
                for other_radius in range(
                    max(min(cells), radius - 2),
                    min(max(cells), radius + 2) + 1,
                ):
                    other_outline_size = len(outlines[other_radius])
                    for yy in range(max(0, y - 2), min(height - 1, y + 2) + 1):
                        for xx in range(max(0, x - 2), min(width - 1, x + 2) + 1):
                            if (other_radius, xx, yy) == (radius, x, y):
                                continue
                            other_count = cells[other_radius][(xx, yy)]
                            left = count * other_outline_size
                            right = other_count * outline_count
                            other_before = (other_radius, yy, xx) < before
                            if left < right or (left == right and other_before):
                                peak = False
                                break
                        if not peak:
                            break
                    if not peak:
                        break
                if peak:
                    peaks.append((radius, x, y, count))
    peaks.sort(key=lambda item: (
        -Fraction(item[3], len(outlines[item[0]])),
        item[0], item[2], item[1],
    ))
    return candidates, peaks


def line_votes(edges, trig, step):
    votes = Counter()
    for point in edges:
        for angle in range(180):
            votes[(angle, rho(point, angle, trig, step))] += 1
    return votes


def line_peaks(votes, threshold):
    peaks = []
    for cell, count in votes.items():
        if count < threshold:
            continue
        angle, rho_value = cell
        peak = True
        for other_angle in range(max(0, angle - 2), min(179, angle + 2) + 1):
            for other_rho in range(rho_value - 2, rho_value + 3):
                other = (other_angle, other_rho)
                if other == cell:
                    continue
                other_count = votes[other]
                if other_count > count or (other_count == count and other < cell):
                    peak = False
                    break
            if not peak:
                break
        if peak:
            peaks.append((angle, rho_value, count))
    peaks.sort(key=lambda item: (-item[2], item[0], item[1]))
    return peaks


def vote_image(votes, width, height, trig, step):
    corners = ((0, 0), (width - 1, 0), (0, height - 1),
               (width - 1, height - 1))
    limits = [rho(point, angle, trig, step)
              for angle in range(180) for point in corners]
    lowest, highest = min(limits), max(limits)
    maximum = max(votes.values(), default=0)
    image = []
    for rho_value in range(lowest, highest + 1):
        image.append([
            255 * votes[(angle, rho_value)] // maximum if maximum else 0
            for angle in range(180)
        ])
    return image, maximum
