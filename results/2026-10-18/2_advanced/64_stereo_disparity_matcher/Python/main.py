"""Integer-only stereo disparity estimation and its seven benchmark outputs."""

from collections import Counter
from fractions import Fraction
from pathlib import Path

from aggregation import DIRECTIONS, cumulative_costs
from costs import census, cost_volume, texture
from evaluation import REGION_ORDER, evaluate, ratio, truth_regions
from pgm_io import read_parameters, read_pgm, write_pgm
from refinement import depth_hundredths, subpixel, two_decimals


METHODS = ("sad", "ssd", "census", "sgm", "fusion", "wta_final", "sgm_final")
SELECTION_METHODS = METHODS[:4]
REASONS = (("textureless", 50), ("nonunique", 100), ("outside", 150),
           ("mismatch", 200), ("occluded", 255))
SOURCES = ("kept", "median", "background", "interpolated", "none")


def lower_median(values):
    return sorted(values)[(len(values) - 1) // 2]


def coordinates(width, height):
    for y in range(height):
        for x in range(width):
            yield x, y, y * width + x


def neighbors4(p, width, height):
    y, x = divmod(p, width)
    return [yy * width + xx for xx, yy in
            ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))
            if 0 <= xx < width and 0 <= yy < height]


def select_disparities(volume, strengths, width, height, params):
    minimum = params["disparity_min"]
    maximum = params["disparity_max"]
    candidates = range(minimum, maximum + 1)
    right = [None] * len(volume)
    for x, y, p in coordinates(width, height):
        available = [d for d in candidates if x + d < width]
        if available:
            right[p] = min(available, key=lambda d: (volume[p + d][d - minimum], d))

    image = [0] * len(volume)
    reasons = [0] * len(volume)
    margins = [0] * len(volume)
    differences = [0] * 4
    bounds = 0
    for x, y, p in coordinates(width, height):
        costs = volume[p]
        best = min(candidates, key=lambda d: (costs[d - minimum], d))
        first = costs[best - minimum]
        second = min(costs[d - minimum] for d in candidates if abs(d - best) >= 2)
        bounds += best == minimum or best == maximum

        def consistent(disparity):
            return (x >= disparity
                    and abs(disparity - right[p - disparity]) <= params["lr_max_diff"])

        if strengths[p] < params["texture_threshold"]:
            reason = 50
        elif 100 * second <= (100 + params["uniqueness"]) * first:
            reason = 100
        elif x < best:
            reason = 150
        elif not consistent(best):
            reason = 200 if any(consistent(d) for d in candidates) else 255
        else:
            reason = 0
            image[p] = best
            margins[p] = second - first
        reasons[p] = reason
        if reason in (0, 200, 255):
            difference = abs(best - right[p - best])
            differences[min(difference, 3)] += 1
    return {"image": image, "reasons": reasons, "margins": margins,
            "lr": differences, "bounds": bounds}


def choose_windows(left, right, cl, cr, strengths, width, height, truth, regions, params):
    selected = {}
    sweeps = []
    for kind in SELECTION_METHODS[:3]:
        best_key = None
        for window in params[kind + "_windows"]:
            volume = cost_volume(left, right, cl, cr, width, height, kind, window,
                                 params["disparity_min"], params["disparity_max"])
            selection = select_disparities(volume, strengths, width, height, params)
            selection["window"] = window
            metrics = evaluate(selection["image"], truth, regions["nonocc"])
            sweeps.append({"kind": kind, "window": window, "metrics": metrics,
                           "valid": sum(value != 0 for value in selection["image"])})
            key = metrics["bad1"], metrics["bad2"]
            if best_key is None or key < best_key:
                best_key = key
                selected[kind] = selection
    return selected, sweeps


def semi_global(left, right, cl, cr, strengths, width, height, truth, regions, params):
    base = cost_volume(left, right, cl, cr, width, height,
                       params["sgm_cost"], params["sgm_window"],
                       params["disparity_min"], params["disparity_max"])
    progress = []
    for number, total in enumerate(cumulative_costs(
            base, left, width, height, params["sgm_paths"],
            params["p1"], params["p2"], params["p2_gamma"]), 1):
        selected = select_disparities(total, strengths, width, height, params)
        metrics = evaluate(selected["image"], truth, regions["nonocc"])
        progress.append({"number": number, "metrics": metrics,
                         "valid": sum(value != 0 for value in selected["image"])})
    selected["window"] = params["sgm_window"]
    return selected, total, progress


def connected_regions(image, width, height, maximum_difference):
    visited = set()
    components = []
    for start, value in enumerate(image):
        if not value or start in visited:
            continue
        visited.add(start)
        stack = [start]
        component = []
        while stack:
            p = stack.pop()
            component.append(p)
            for q in neighbors4(p, width, height):
                if (image[q] and q not in visited
                        and abs(image[q] - image[p]) <= maximum_difference):
                    visited.add(q)
                    stack.append(q)
        components.append(component)
    return components


def remove_speckles(image, width, height, params):
    components = connected_regions(image, width, height, params["speckle_range"])
    result = list(image)
    removed = [part for part in components if len(part) < params["speckle_size"]]
    for part in removed:
        for p in part:
            result[p] = 0
    return result, len(removed), sum(map(len, removed))


def median_filter(image, width, height):
    result = [0] * len(image)
    for x, y, p in coordinates(width, height):
        if not image[p]:
            continue
        values = [image[yy * width + xx]
                  for yy in range(max(0, y - 1), min(height, y + 2))
                  for xx in range(max(0, x - 1), min(width, x + 2))
                  if image[yy * width + xx]]
        result[p] = lower_median(values)
    return result


def ray_values(image, width, height, x, y, directions):
    values = []
    for dx, dy in directions:
        xx, yy = x + dx, y + dy
        while 0 <= xx < width and 0 <= yy < height:
            value = image[yy * width + xx]
            if value:
                values.append(value)
                break
            xx += dx
            yy += dy
    return values


def postprocess(selection, width, height, params):
    original = selection["image"]
    filtered, removed_count, removed_pixels = remove_speckles(original, width, height, params)
    medians = median_filter(filtered, width, height)
    result = list(medians)
    sources = ["none"] * len(original)
    for x, y, p in coordinates(width, height):
        if medians[p]:
            sources[p] = "kept" if medians[p] == original[p] else "median"
        elif selection["reasons"][p] in (150, 255):
            values = ray_values(medians, width, height, x, y, ((-1, 0), (1, 0)))
            if values:
                result[p] = min(values)
                sources[p] = "background"
        else:
            values = ray_values(medians, width, height, x, y, DIRECTIONS)
            if values:
                result[p] = lower_median(values)
                sources[p] = "interpolated"
    return {"image": result, "sources": sources,
            "speckles": removed_count, "speckle_pixels": removed_pixels,
            "median_changed": sum(a != b for a, b in zip(filtered, medians)),
            "background": sources.count("background"),
            "interpolated": sources.count("interpolated"),
            "unfilled": sources.count("none")}


def fuse(selections, minimum_votes):
    size = len(selections["sad"]["image"])
    result = [0] * size
    votes = Counter()
    for p in range(size):
        candidates = [selections[name]["image"][p] for name in SELECTION_METHODS
                      if selections[name]["image"][p]]
        votes[len(candidates)] += 1
        if candidates:
            median = lower_median(candidates)
            if sum(abs(value - median) <= 1 for value in candidates) >= minimum_votes:
                result[p] = median
    return {"image": result, "votes": votes}


def object_measurements(component, image, truth, width, true_counts, params):
    xs = [p % width for p in component]
    ys = [p // width for p in component]
    disparities = [image[p] for p in component]
    median = lower_median(disparities)
    count = len(component)
    total = sum(disparities)
    box = min(xs), min(ys), max(xs), max(ys)
    layer_counts = Counter(truth[p] for p in component if truth[p])
    layer = min(layer_counts, key=lambda g: (-layer_counts[g], g)) if layer_counts else None
    hits = layer_counts[layer] if layer is not None else 0
    union = count + true_counts[layer] - hits if layer is not None else 0
    return {"pixels": count, "box": box, "minimum": min(disparities),
            "maximum": max(disparities), "median": median,
            "mean": two_decimals(total, count),
            "depth": two_decimals(params["focal_length"] * params["baseline"] * count, total),
            "width": two_decimals((box[2] - box[0] + 1) * params["baseline"], median),
            "height": two_decimals((box[3] - box[1] + 1) * params["baseline"], median),
            "truth": layer, "hits": hits, "union": union, "first": min(component)}


def extract_objects(image, truth, width, height, params):
    components = connected_regions(image, width, height, params["object_range"])
    counts = Counter(value for value in truth if value)
    objects = []
    small = 0
    for component in components:
        if len(component) < params["object_min_size"]:
            small += 1
        else:
            objects.append(object_measurements(component, image, truth, width, counts, params))
    objects.sort(key=lambda item: (-item["median"], -item["pixels"], item["first"]))
    detected = {item["truth"] for item in objects
                if item["truth"] is not None and 2 * item["hits"] > item["union"]}
    return objects, small, sorted(counts), detected


def object_lines(objects, small, layers, detected):
    lines = [f"objects {len(objects)} small {small} pixels {sum(o['pixels'] for o in objects)}"]
    for number, item in enumerate(objects, 1):
        truth = (f"truth {item['truth']} iou {ratio(item['hits'], item['union'])}"
                 if item["truth"] is not None else "truth - iou -")
        lines.append(
            f"object {number} pixels {item['pixels']} box "
            + " ".join(map(str, item["box"]))
            + f" disparity {item['minimum']} {item['maximum']} median {item['median']}"
            + f" mean {item['mean']} depth {item['depth']}"
            + f" size {item['width']} {item['height']} {truth}"
        )
    missed = " ".join(str(g) for g in layers if g not in detected) or "-"
    lines.append(f"layers {len(layers)} detected {len(detected)} missed {missed}")
    return lines


def sample_lines(methods, summed_costs, truth, width, params):
    lines = ["x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth"]
    focal, baseline = params["focal_length"], params["baseline"]
    for x, y in params["sample_pixels"]:
        p = y * width + x
        values = [str(x), str(y)]
        values.extend(str(methods[name]["image"][p]) if methods[name]["image"][p] else "-"
                      for name in SELECTION_METHODS)
        disparity = methods["sgm_final"]["image"][p]
        if disparity:
            refined, depth = subpixel(disparity, summed_costs[p], params["disparity_min"],
                                      params["disparity_max"], focal, baseline)
            values.extend((str(disparity), methods["sgm_final"]["sources"][p], refined, depth))
        else:
            values.extend(("-", "none", "-", "-"))
        if truth[p]:
            values.extend((str(truth[p]), two_decimals(focal * baseline, truth[p])))
        else:
            values.extend(("-", "-"))
        lines.append(",".join(values))
    return lines


def image_summary(name, image):
    count = len(image)
    return (f"{name} mean {two_decimals(sum(image), count)} "
            f"min {min(image)} max {max(image)}")


def input_summary(left, right, truth, strengths, width, height, regions, params):
    size = width * height
    delta = [right[p - truth[p]] - left[p] for p in regions["nonocc"]]
    bias_sum = sum(delta)
    bias = two_decimals(abs(bias_sum), len(delta))
    if bias_sum < 0 and bias != "0.00":
        bias = "-" + bias
    return [
        f"image {width} {height}",
        f"disparities {params['disparity_min']} {params['disparity_max']}",
        image_summary("left", left), image_summary("right", right),
        f"texture mean {two_decimals(sum(strengths), size)} "
        f"textureless {sum(value < params['texture_threshold'] for value in strengths)}",
        f"ground_truth known {len(regions['all'])} nonocc {len(regions['nonocc'])} "
        f"occluded {len(regions['occluded'])} disc {len(regions['disc'])} "
        f"unknown {size - len(regions['all'])}",
        f"photometric pixels {len(delta)} mean_abs "
        f"{two_decimals(sum(abs(value) for value in delta), len(delta))} bias {bias}",
    ]


def sweep_lines(sweeps, path_progress):
    lines = []
    for sweep in sweeps:
        score = sweep["metrics"]
        lines.append(f"sweep {sweep['kind']} window {sweep['window']} valid {sweep['valid']} "
                     f"bad1 {ratio(score['bad1'], score['pixels'])} "
                     f"bad2 {ratio(score['bad2'], score['pixels'])}")
    for progress in path_progress:
        score = progress["metrics"]
        lines.append(f"paths {progress['number']} valid {progress['valid']} "
                     f"bad1 {ratio(score['bad1'], score['pixels'])} "
                     f"bad2 {ratio(score['bad2'], score['pixels'])}")
    return lines


def disparity_summary(name, image, width, height):
    values = [value for value in image if value]
    valid = len(values)
    horizontal = 0
    vertical = 0
    for x, y, p in coordinates(width, height):
        if not image[p]:
            continue
        if x + 1 < width and image[p + 1] and abs(image[p] - image[p + 1]) >= 2:
            horizontal += 1
        if y + 1 < height and image[p + width] and abs(image[p] - image[p + width]) >= 2:
            vertical += 1
    distribution = (f"disparity min {min(values)} max {max(values)} "
                    f"median {lower_median(values)} distinct {len(set(values))}"
                    if values else "disparity min - max - median - distinct 0")
    return [f"method {name} valid {valid} invalid {len(image) - valid}", distribution,
            f"jumps horizontal {horizontal} vertical {vertical}"]


def selection_details(method):
    counts = Counter(method["reasons"])
    reasons = " ".join(f"{name} {counts[code]}" for name, code in REASONS)
    differences = method["lr"]
    return [f"window {method['window']} bounds {method['bounds']}",
            "reasons " + reasons,
            f"lr 0 {differences[0]} 1 {differences[1]} 2 {differences[2]} 3+ {differences[3]}"]


def postprocess_details(method, truth, known):
    lines = [
        f"postprocess speckles {method['speckles']} {method['speckle_pixels']} "
        f"median {method['median_changed']} background {method['background']} "
        f"interpolated {method['interpolated']} unfilled {method['unfilled']}"
    ]
    for source in SOURCES:
        region = [p for p in known if method["sources"][p] == source]
        metrics = evaluate(method["image"], truth, region)
        lines.append(f"source {source} pixels {metrics['pixels']} "
                     f"bad1 {ratio(metrics['bad1'], metrics['pixels'])}")
    return lines


def region_line(region, metrics):
    return (f"region {region} pixels {metrics['pixels']} valid {metrics['valid']} "
            f"bad1 {ratio(metrics['bad1'], metrics['pixels'])} "
            f"bad2 {ratio(metrics['bad2'], metrics['pixels'])} "
            f"mae {metrics['mae']} exact {metrics['exact']}")


def depth_error_line(image, truth, nonocc, params):
    focal, baseline = params["focal_length"], params["baseline"]
    errors = [abs(depth_hundredths(image[p], focal, baseline)
                  - depth_hundredths(truth[p], focal, baseline))
              for p in nonocc if image[p]]
    if not errors:
        return "depth_error pixels 0 mean - max -"
    return (f"depth_error pixels {len(errors)} "
            f"mean {two_decimals(sum(errors), 100 * len(errors))} "
            f"max {two_decimals(max(errors), 100)}")


def error_counts_line(image, truth, known):
    counts = Counter(min(abs(image[p] - truth[p]), 4) for p in known if image[p])
    invalid = sum(image[p] == 0 for p in known)
    return (f"errors 0 {counts[0]} 1 {counts[1]} 2 {counts[2]} "
            f"3 {counts[3]} 4+ {counts[4]} invalid {invalid}")


def method_lines(name, method, truth, width, height, regions, metrics, params):
    image = method["image"]
    lines = disparity_summary(name, image, width, height)
    if name in SELECTION_METHODS:
        lines.extend(selection_details(method))
    elif name == "fusion":
        lines.append("votes " + " ".join(f"{n} {method['votes'][n]}" for n in range(5)))
    else:
        lines.extend(postprocess_details(method, truth, regions["all"]))
    for region in REGION_ORDER:
        lines.append(region_line(region, metrics[name][region]))
    lines.append(depth_error_line(image, truth, regions["nonocc"], params))
    lines.append(error_counts_line(image, truth, regions["all"]))
    return lines


def ranking_lines(metrics):
    lines = []
    for region in REGION_ORDER:
        def key(name):
            values = metrics[name][region]
            valid = values["valid"]
            mean = Fraction(values["error_sum"], valid) if valid else Fraction(0)
            return values["bad1"], values["bad2"], valid == 0, mean, METHODS.index(name)
        names = sorted(METHODS, key=key)
        lines.append(f"ranking {region} " + " ".join(names))
    return lines


def occlusion_lines(methods, regions):
    lines = []
    for name in SELECTION_METHODS:
        reasons = methods[name]["reasons"]
        true_positive = sum(reasons[p] in (150, 255) for p in regions["occluded"])
        false_positive = sum(reasons[p] in (150, 255) for p in regions["nonocc"])
        false_negative = len(regions["occluded"]) - true_positive
        lines.append(
            f"occlusion {name} tp {true_positive} fp {false_positive} fn {false_negative} "
            f"precision {ratio(true_positive, true_positive + false_positive)} "
            f"recall {ratio(true_positive, true_positive + false_negative)}"
        )
    return lines


def confidence_lines(methods, truth, nonocc):
    lines = []
    for name in SELECTION_METHODS:
        method = methods[name]
        pixels = [p for p in nonocc if method["image"][p]]
        pixels.sort(key=lambda p: (-method["margins"][p], p))
        for percentage in (25, 50, 75, 100):
            count = (len(pixels) * percentage + 99) // 100
            bad = sum(abs(method["image"][p] - truth[p]) > 1 for p in pixels[:count])
            margin = method["margins"][pixels[count - 1]] if count else "-"
            lines.append(f"confidence {name} {percentage} pixels {count} "
                         f"margin {margin} bad1 {ratio(bad, count)}")
    return lines


def layer_lines(methods, truth, regions):
    lines = []
    counts = Counter(value for value in truth if value)
    for layer in sorted(counts):
        nonocc = [p for p in regions["nonocc"] if truth[p] == layer]
        errors = [evaluate(methods[name]["image"], truth, nonocc)["bad1"] for name in METHODS]
        lines.append(f"layer {layer} pixels {counts[layer]} nonocc {len(nonocc)} bad1 "
                     + " ".join(map(str, errors)))
    return lines


def evaluation_lines(left, right, truth, strengths, width, height, regions,
                     methods, sweeps, path_progress, params):
    metrics = {name: {region: evaluate(methods[name]["image"], truth, regions[region])
                      for region in REGION_ORDER} for name in METHODS}
    lines = input_summary(left, right, truth, strengths, width, height, regions, params)
    lines.extend(sweep_lines(sweeps, path_progress))
    for name in METHODS:
        lines.extend(method_lines(name, methods[name], truth, width, height,
                                  regions, metrics, params))
    lines.extend(ranking_lines(metrics))
    lines.extend(occlusion_lines(methods, regions))
    lines.extend(confidence_lines(methods, truth, regions["nonocc"]))
    lines.extend(layer_lines(methods, truth, regions))
    counts = Counter(methods["sgm_final"]["image"])
    for disparity in range(params["disparity_min"], params["disparity_max"] + 1):
        lines.append(f"histogram {disparity} {counts[disparity]}")
    return lines


def error_image(image, truth):
    pixels = []
    for actual, expected in zip(image, truth):
        if expected == 0:
            pixels.append(0)
        elif actual == 0:
            pixels.append(255)
        else:
            error = abs(actual - expected)
            pixels.append(50 * (min(error, 3) + 1))
    return pixels


def save_text(name, lines):
    Path("output", name).write_text("\n".join(lines) + "\n", encoding="ascii")


def main():
    width, height, left = read_pgm("input/left.pgm")
    _, _, right = read_pgm("input/right.pgm")
    _, _, truth = read_pgm("input/ground_truth.pgm")
    params = read_parameters()
    regions = truth_regions(truth, width, height)
    strengths = texture(left, width, height, params["texture_window"])
    census_left = census(left, width, height)
    census_right = census(right, width, height)

    methods, sweeps = choose_windows(left, right, census_left, census_right, strengths,
                                     width, height, truth, regions, params)
    sgm, summed_costs, progress = semi_global(left, right, census_left, census_right,
                                             strengths, width, height, truth, regions, params)
    methods["sgm"] = sgm
    methods["fusion"] = fuse(methods, params["fusion_min_votes"])
    methods["wta_final"] = postprocess(methods[params["wta_cost"]], width, height, params)
    methods["sgm_final"] = postprocess(sgm, width, height, params)
    objects, small, layers, detected = extract_objects(methods["sgm_final"]["image"], truth,
                                                       width, height, params)

    Path("output").mkdir(exist_ok=True)
    write_pgm("output/disparity_wta.pgm", width, height,
              [8 * value for value in methods["wta_final"]["image"]])
    write_pgm("output/disparity_sgm.pgm", width, height,
              [8 * value for value in methods["sgm_final"]["image"]])
    write_pgm("output/occlusion.pgm", width, height, sgm["reasons"])
    write_pgm("output/error_sgm.pgm", width, height,
              error_image(methods["sgm_final"]["image"], truth))
    save_text("depth.csv", sample_lines(methods, summed_costs, truth, width, params))
    save_text("evaluation.txt", evaluation_lines(left, right, truth, strengths,
                                                width, height, regions, methods,
                                                sweeps, progress, params))
    save_text("objects.txt", object_lines(objects, small, layers, detected))


if __name__ == "__main__":
    main()
