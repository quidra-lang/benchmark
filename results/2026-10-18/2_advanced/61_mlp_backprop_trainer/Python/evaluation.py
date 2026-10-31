"""Fixed-point output, exact rounded ratios, confusion matrices and digit maps."""

from collections import Counter


def real(value, places):
    result = f"{value:.{places}f}"
    return result[1:] if result.startswith("-") and float(result) == 0 else result


def ratio(numerator, denominator):
    if denominator == 0:
        return "-"
    rounded = (20000 * numerator + denominator) // (2 * denominator)
    return f"{rounded // 10000}.{rounded % 10000:04d}"


def best_two(scores):
    return sorted(
        range(len(scores)), key=lambda index: (-scores[index], index)
    )[:2]


def confusion(outcomes, classes):
    table = [[0] * classes for _ in range(classes)]
    for outcome in outcomes:
        table[outcome["label"]][outcome["predicted"]] += 1
    return table


def class_measures(table, klass):
    support = sum(table[klass])
    predicted = sum(row[klass] for row in table)
    true = table[klass][klass]
    return {
        "support": support, "predicted": predicted,
        "precision": ratio(true, predicted),
        "recall": ratio(true, support),
        "f1": ratio(2 * true, support + predicted),
    }


def level_maps(levels, width, height):
    """Place the level maps for all classes side-by-side, one row at a time."""
    return [
        " ".join(
            "".join(str(level[row * width + column])
                    for column in range(width))
            for level in levels
        ) for row in range(height)
    ]


def ascii_image(pixels, width):
    return [
        "".join("#" if pixel == "1" else "." for pixel in pixels[i:i + width])
        for i in range(0, len(pixels), width)
    ]


def binary_frequency(images, label, pixels):
    chosen = [image for image in images if image["label"] == label]
    if not chosen:
        return [0] * pixels
    return [
        min(9, (10 * sum(image["pixels"][i] == "1"
                         for image in chosen)) // len(chosen))
        for i in range(pixels)
    ]
