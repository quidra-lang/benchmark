"""Seismic STA/LTA detection, hypocenter relocation and earthquake catalog.

Inputs are read from input/; the six required output files are written
under output/ without printing or requiring non-standard Python modules.
"""

from collections import Counter, defaultdict, deque
from pathlib import Path
import math

from associator import associate
from locator import (
    PI, distance, error_ellipse, geiger, residuals, rms, run_location,
)
from magnitude import (
    class_number, frequency_statistics, magnitude_class,
    median, per_pick_magnitude,
)
from picker import detect_station
from waveform_io import load_inputs


def decimal(value, places):
    """Fixed decimal notation with symmetric rounding and no negative zero."""
    formatted = f"{value:.{places}f}"
    return formatted[1:] if formatted.startswith("-") and float(formatted) == 0 else formatted


def time_notation(sample):
    return f"{sample // 100}.{sample % 100:02d}"


def write_lines(name, lines):
    target = Path("output") / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n", encoding="ascii")


def collect_picks(stations, params):
    picks = []
    for station in stations:
        picks.extend(detect_station(station, params))
    return sorted(
        picks, key=lambda p: (p["sample"], p["station_obj"]["order"])
    )


def station_ordered(picks):
    return sorted(picks, key=lambda pick: pick["station_obj"]["order"])


def candidate_observations(picks, corrections=None):
    return [
        (pick["station_obj"],
         pick["time"] - (corrections or {}).get(pick["station"], 0))
        for pick in station_ordered(picks)
    ]


def locate_candidates(candidates, params):
    """Perform the two location passes, dropping outliers simultaneously."""
    events = []
    minimum = params["min_stations"]
    limit = params["residual_limit"]
    for candidate in candidates:
        initial_picks = station_ordered(candidate["picks"])
        first_pass = run_location(candidate_observations(initial_picks), params)
        candidate["passes"].append((initial_picks, first_pass))
        dropped = []
        retained = []
        for pick, error in zip(initial_picks, first_pass["residuals"]):
            if abs(error) > limit:
                dropped.append((pick, error))
            else:
                retained.append(pick)
        candidate["dropped"] = dropped

        if dropped and len(retained) < minimum:
            candidate["rejected"] = True
            for pick in initial_picks:
                pick["state"] = "rejected"
            continue
        if dropped:
            adopted = run_location(candidate_observations(retained), params)
            candidate["passes"].append((retained, adopted))
        else:
            adopted = first_pass

        number = len(events) + 1
        candidate["event"] = number
        for pick, error in zip(retained, adopted["residuals"]):
            pick["state"] = "used"
            pick["event"] = number
            pick["first_residual"] = error
        for pick, _ in dropped:
            pick["state"] = "dropped"
            pick["event"] = number
        events.append({
            "number": number,
            "candidate": candidate,
            "used": retained,
            "first": adopted,
            "solution": adopted["solution"],
            "final": None,
        })
    return events


def station_time_corrections(events, stations):
    """Average first-stage residuals in event order for every station."""
    collected = defaultdict(list)
    for event in events:
        for pick in event["used"]:
            collected[pick["station"]].append(pick["first_residual"])
    return {
        station["code"]: (
            sum(collected[station["code"]]) / len(collected[station["code"]])
            if collected[station["code"]] else 0.0
        )
        for station in stations
    }


def azimuth_gap(solution, picks):
    """Maximum circular angular separation between used station bearings."""
    x, y, _, _ = solution
    angles = []
    for pick in picks:
        station = pick["station_obj"]
        angle = math.atan2(station["x"] - x, station["y"] - y) * 180 / PI
        if angle < 0:
            angle += 360
        angles.append(angle)
    angles.sort()
    gaps = [angles[i + 1] - angles[i] for i in range(len(angles) - 1)]
    gaps.append(angles[0] + 360 - angles[-1])
    return max(gaps)


def quality_for_event(event, params):
    """Location covariance, station geometry, quality grade and jackknife."""
    final = event["final"]
    solution = final["solution"]
    used = event["used"]
    velocity = params["velocity"]
    observations = event["observations"]
    ellipse = error_ellipse(solution, observations, velocity)
    gap = azimuth_gap(solution, used)
    x, y, z, _ = solution
    dmin = min(
        math.sqrt((p["station_obj"]["x"] - x) ** 2
                  + (p["station_obj"]["y"] - y) ** 2)
        for p in used
    )
    thresholds_a = params["quality_a"]
    thresholds_b = params["quality_b"]
    def fits(boundaries):
        return (
            gap <= boundaries[0] and
            final["rms"] <= boundaries[1] and
            ellipse["smaj"] <= boundaries[2]
        )
    grade = "A" if fits(thresholds_a) else "B" if fits(thresholds_b) else "C"
    first = event["first"]["solution"]
    shift_horizontal = math.sqrt(
        (solution[0] - first[0]) ** 2
        + (solution[1] - first[1]) ** 2
    )
    shift_depth = solution[2] - first[2]

    jackknife = []
    for index, pick in enumerate(used):
        remaining = [
            observation for j, observation in enumerate(observations)
            if j != index
        ]
        run = geiger(solution, remaining, velocity)
        alternative = run["solution"]
        dx, dy, dz = (
            alternative[axis] - solution[axis] for axis in range(3)
        )
        shift = math.sqrt(dx * dx + dy * dy)
        jackknife.append({
            "code": pick["station"], "dx": dx, "dy": dy,
            "dz": dz, "shift": shift,
        })
    maximum = max(jackknife, key=lambda item: item["shift"])
    return {
        **ellipse,
        "gap": gap, "dmin": dmin, "grade": grade,
        "dh": shift_horizontal, "dz": shift_depth,
        "jackknife": jackknife, "max_jack": maximum,
    }


def relocate_events(events, stations, params, corrections):
    """Apply station corrections and run eight Geiger iterations again."""
    for event in events:
        obs = candidate_observations(event["used"], corrections)
        event["observations"] = obs
        event["start_rms"] = rms(
            event["first"]["solution"], obs, params["velocity"]
        )
        final = geiger(event["first"]["solution"], obs, params["velocity"])
        event["final"] = final
        event["solution"] = final["solution"]
        for pick, value in zip(event["used"], final["residuals"]):
            pick["residual"] = value
        event["quality"] = quality_for_event(event, params)


def compute_magnitudes(events, stations, params):
    """Local and duration magnitudes; then station and event corrections."""
    residuals_by_station = defaultdict(list)
    for event in events:
        all_duration = []
        local = []
        event["magnitudes"] = []
        for pick in event["used"]:
            station = pick["station_obj"]
            radius_km = distance(event["solution"], station) / 1000
            data = per_pick_magnitude(pick, radius_km, params)
            data["pick"] = pick
            all_duration.append(data["md"])
            if data["ml"] is not None:
                local.append(data["ml"])
            event["magnitudes"].append(data)
        event["ml"] = median(local) if local else None
        event["md"] = median(all_duration)
        for item in event["magnitudes"]:
            if item["ml"] is not None:
                residuals_by_station[item["pick"]["station"]].append(
                    item["ml"] - event["ml"]
                )

    corrections = {}
    for station in stations:
        values = residuals_by_station[station["code"]]
        corrections[station["code"]] = sum(values) / len(values) if values else 0.0
    for event in events:
        corrected = [
            item["ml"] - corrections[item["pick"]["station"]]
            for item in event["magnitudes"] if item["ml"] is not None
        ]
        event["ml_corrected"] = median(corrected) if corrected else None
    return corrections, residuals_by_station


def travel_time_regression(events, params):
    """Uncorrected pick travel-time regression against hypocentral distance."""
    points = []
    for event in events:
        t0 = event["solution"][3]
        for pick in event["used"]:
            d = distance(event["solution"], pick["station_obj"]) / 1000
            points.append((d, pick["time"] - t0))
    n = len(points)
    sd = sum(d for d, _ in points)
    st = sum(t for _, t in points)
    sdd = sum(d * d for d, _ in points)
    sdt = sum(d * t for d, t in points)
    slope = (n * sdt - sd * st) / (n * sdd - sd * sd)
    intercept = (st - slope * sd) / n
    residual_sum = sum(
        (t - intercept - slope * d) ** 2 for d, t in points
    )
    return {
        "n": n, "velocity": 1000 / slope,
        "intercept": intercept, "rms": math.sqrt(residual_sum / n),
    }


def cluster_events(events, params):
    """Connected components in space-time adjacency; IDs by first event."""
    distance_limit, time_limit = params["cluster"]
    neighbors = defaultdict(set)
    for i, first in enumerate(events):
        for second in events[i + 1:]:
            a, b = first["solution"], second["solution"]
            if abs(a[3] - b[3]) > time_limit:
                continue
            spatial = math.sqrt(
                sum((a[axis] - b[axis]) ** 2 for axis in range(3))
            )
            if spatial <= distance_limit:
                neighbors[first["number"]].add(second["number"])
                neighbors[second["number"]].add(first["number"])
    unvisited = {event["number"] for event in events}
    clusters = []
    indexed = {event["number"]: event for event in events}
    while unvisited:
        first = min(unvisited)
        unvisited.remove(first)
        queue = deque([first])
        members = []
        while queue:
            number = queue.popleft()
            members.append(number)
            for other in sorted(neighbors[number]):
                if other in unvisited:
                    unvisited.remove(other)
                    queue.append(other)
        members.sort()
        number = len(clusters) + 1
        for item in members:
            indexed[item]["cluster"] = number
        cluster = {"number": number, "members": members}
        if len(members) >= 2:
            cluster["center"] = tuple(
                sum(indexed[item]["solution"][axis] for item in members)
                / len(members) for axis in range(3)
            )
            origins = [indexed[item]["solution"][3] for item in members]
            cluster["span"] = max(origins) - min(origins)
        clusters.append(cluster)
    return clusters


def reassociate_unassigned(picks, events, corrections, params):
    """Use corrected prediction residuals without modifying event solutions."""
    station_set = {
        event["number"]: {pick["station"] for pick in event["used"]}
        for event in events
    }
    added = []
    for pick in picks:
        if pick["state"] != "unassociated":
            continue
        choices = []
        for event in events:
            number = event["number"]
            if pick["station"] in station_set[number]:
                continue
            predicted = (
                event["solution"][3]
                + distance(event["solution"], pick["station_obj"])
                  / params["velocity"]
                + corrections[pick["station"]]
            )
            residual = pick["time"] - predicted
            if abs(residual) <= params["residual_limit"]:
                choices.append((abs(residual), number, residual))
        if not choices:
            continue
        _, number, residual = min(choices)
        pick["state"] = "added"
        pick["event"] = number
        pick["residual"] = residual
        station_set[number].add(pick["station"])
        added.append(pick)
    return added


def build_picks_file(picks):
    """Write the full pick list in global sample/station order."""
    result = [
        "station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual"
    ]
    for pick in picks:
        status = pick["state"]
        output_number = pick["event"] if status in ("used", "dropped", "added") else 0
        error = (
            decimal(pick["residual"], 4) if status in ("used", "added")
            else "-"
        )
        result.append(",".join(map(str, (
            pick["station"], pick["sample"], time_notation(pick["sample"]),
            pick["duration"], decimal(pick["ratio"], 2),
            pick["amplitude"], "yes" if pick["clipped"] else "no",
            output_number, status, error,
        ))))
    return result


def format_solution(label, solution, residual_rms, index=None):
    x, y, z, t0 = solution
    return (
        f"{label}{' ' + str(index) if index is not None else ''} "
        f"x={decimal(x, 1)} y={decimal(y, 1)} z={decimal(z, 1)} "
        f"t0={decimal(t0, 3)} rms={decimal(residual_rms, 4)}"
    )


def location_pass_lines(number, picks, run, velocity):
    """Render first/second grid-to-Geiger location passes in a candidate."""
    grid = run["grid"]
    result = [
        f"PASS {number} stations={','.join(pick['station'] for pick in picks)}",
        format_solution("GRID", grid["solution"], grid["rms"]),
        "PROFILE " + " ".join(
            decimal(value, 4) for _, value in grid["profile"]
        ),
    ]
    result.extend(
        format_solution("ITER", record["solution"], record["rms"],
                        record["number"])
        for record in run["trace"]
    )
    for pick, residual in zip(picks, run["residuals"]):
        d = distance(run["solution"], pick["station_obj"])
        result.append(
            f"RES {pick['station']} dist={decimal(d, 1)} "
            f"tt={decimal(d / velocity, 4)} "
            f"obs={time_notation(pick['sample'])} "
            f"res={decimal(residual, 4)}"
        )
    return result


def candidate_lines(candidates, velocity):
    """Report every attempted location pass and its acceptance or rejection."""
    result = []
    for candidate in candidates:
        first = candidate["first"]
        result.append(
            f"CANDIDATE {candidate['number']} picks={len(candidate['picks'])} "
            f"first={time_notation(first['sample'])}"
        )
        first_picks, first_run = candidate["passes"][0]
        result.extend(location_pass_lines(1, first_picks, first_run, velocity))
        for pick, error in candidate["dropped"]:
            result.append(
                f"DROP {pick['station']} res={decimal(error, 4)}"
            )
        if candidate["rejected"]:
            result.append(
                f"RESULT REJECTED stations="
                f"{len(candidate['picks']) - len(candidate['dropped'])}"
            )
        else:
            if len(candidate["passes"]) == 2:
                second_picks, second_run = candidate["passes"][1]
                result.extend(
                    location_pass_lines(2, second_picks, second_run, velocity)
                )
            result.append(f"RESULT EVENT {candidate['event']}")
    return result


def event_location_lines(event, velocity):
    """Final Geiger trace, station residuals, ellipse, and jackknife."""
    result = [f"EVENT {event['number']}"]
    result.append(
        format_solution(
            "START", event["first"]["solution"], event["start_rms"]
        )
    )
    final = event["final"]
    quality = event["quality"]
    for record in final["trace"]:
        result.append(
            format_solution("ITER", record["solution"], record["rms"],
                            record["number"])
        )
    for pick, correction in zip(event["used"], event["observations"]):
        d = distance(event["solution"], pick["station_obj"])
        offset = pick["time"] - correction[1]
        result.append(
            f"RES {pick['station']} dist={decimal(d, 1)} "
            f"tt={decimal(d / velocity, 4)} "
            f"obs={time_notation(pick['sample'])} "
            f"corr={decimal(offset, 4)} "
            f"res={decimal(pick['residual'], 4)}"
        )
    result.extend([
        f"ELLIPSE smaj={decimal(quality['smaj'], 1)} "
        f"smin={decimal(quality['smin'], 1)} "
        f"az={decimal(quality['az'], 1)} "
        f"erz={decimal(quality['erz'], 1)} "
        f"ert={decimal(quality['ert'], 4)}",
        f"SHIFT dh={decimal(quality['dh'], 1)} "
        f"dz={decimal(quality['dz'], 1)}",
        f"GAP {decimal(quality['gap'], 1)} "
        f"DMIN {decimal(quality['dmin'], 1)} QUALITY {quality['grade']}",
    ])
    for jack in quality["jackknife"]:
        result.append(
            f"JACK {jack['code']} dx={decimal(jack['dx'], 1)} "
            f"dy={decimal(jack['dy'], 1)} dz={decimal(jack['dz'], 1)} "
            f"shift={decimal(jack['shift'], 1)}"
        )
    maximum = quality["max_jack"]
    result.append(
        f"JACKKNIFE max={decimal(maximum['shift'], 1)} "
        f"station={maximum['code']}"
    )
    return result


def location_file(picks, candidates, events, stations, time_corrections,
                  regression, clusters, added, params):
    result = candidate_lines(candidates, params["velocity"])
    result.append("CORRECTIONS")
    for station in stations:
        code = station["code"]
        number = sum(
            pick["state"] == "used" and pick["station"] == code for pick in picks
        )
        result.append(
            f"{code} n={number} correction={decimal(time_corrections[code], 4)}"
        )
    for event in events:
        result.extend(event_location_lines(event, params["velocity"]))
    result.append(
        f"FIT n={regression['n']} "
        f"velocity={decimal(regression['velocity'], 1)} "
        f"intercept={decimal(regression['intercept'], 4)} "
        f"rms={decimal(regression['rms'], 4)}"
    )
    indexed = {event["number"]: event for event in events}
    for cluster in clusters:
        if len(cluster["members"]) < 2:
            continue
        cx, cy, cz = cluster["center"]
        result.append(
            f"CLUSTER {cluster['number']} "
            f"events={','.join(map(str, cluster['members']))} "
            f"x={decimal(cx, 1)} y={decimal(cy, 1)} "
            f"z={decimal(cz, 1)} span={decimal(cluster['span'], 3)}"
        )
    result.append("ADDED")
    for pick in added:
        result.append(
            f"{pick['station']} sample={pick['sample']} "
            f"event={pick['event']} res={decimal(pick['residual'], 4)}"
        )
    result.append(
        f"SUMMARY picks={len(picks)} candidates={len(candidates)} "
        f"events={len(events)} "
        f"rejected={sum(item['rejected'] for item in candidates)} "
        f"unassociated={sum(pick['state'] == 'unassociated' for pick in picks)}"
    )
    depths = [event["solution"][2] for event in events]
    result.append(
        f"DEPTH min={decimal(min(depths), 1)} "
        f"median={decimal(median(depths), 1)} "
        f"max={decimal(max(depths), 1)}"
    )
    quality = Counter(event["quality"]["grade"] for event in events)
    result.append(
        f"QUALITY A={quality['A']} B={quality['B']} C={quality['C']} "
        f"mean_rms={decimal(sum(event['final']['rms'] for event in events) / len(events), 4)}"
    )
    return result


def catalog_rows(events):
    """Output each event once with rounded geometry, magnitudes, and cluster."""
    result = [
        "event,origin_time,x,y,depth,rms,stations,gap,dmin,"
        "smaj,smin,azimuth,erz,ml,md,quality,cluster"
    ]
    for event in events:
        x, y, z, origin = event["solution"]
        q = event["quality"]
        fields = (
            event["number"], decimal(origin, 3),
            decimal(x, 1), decimal(y, 1), decimal(z, 1),
            decimal(event["final"]["rms"], 4),
            len(event["used"]),
            decimal(q["gap"], 1), decimal(q["dmin"], 1),
            decimal(q["smaj"], 1), decimal(q["smin"], 1),
            decimal(q["az"], 1), decimal(q["erz"], 1),
            decimal(event["ml"], 2) if event["ml"] is not None else "-",
            decimal(event["md"], 2), q["grade"], event["cluster"],
        )
        result.append(",".join(map(str, fields)))
    return result


def magnitude_class_counts(events):
    return frequency_statistics(events)


def display_coordinate(value, digits):
    """Recover exact scaled decimal integer from already-rounded notation."""
    text = decimal(value, digits)
    sign = -1 if text.startswith("-") else 1
    parts = text.lstrip("-").split(".")
    return sign * (int(parts[0]) * (10 ** digits) + int(parts[1]))


def plot_frame(width):
    return "+" + "-" * width + "+"


def draw_timeline(events, params):
    duration, width, low, high, height = params["timeline"]
    rows = [[" "] * width for _ in range(height)]
    for event in events:
        if event["ml"] is None:
            continue
        t = display_coordinate(event["solution"][3], 3)
        magnitude = display_coordinate(event["ml"], 2)
        if not (0 <= t < 1000 * duration and magnitude >= 100 * low):
            continue
        column = t * width // (1000 * duration)
        level = (magnitude - 100 * low) * height // (100 * (high - low))
        level = min(level, height - 1)
        for index in range(level + 1):
            row = height - 1 - index
            if index == level:
                rows[row][column] = "o"
            elif rows[row][column] == " ":
                rows[row][column] = "|"
    return [
        f"TIMELINE t=0..{duration} ML={low}..{high}",
        plot_frame(width),
        *["|" + "".join(row) + "|" for row in rows],
        plot_frame(width),
    ]


def magnitude_file(events, stats, params):
    """Magnitudes by pick, station bias corrections, FMD and ML/MD regression."""
    result = []
    for event in events:
        ml = "-" if event["ml"] is None else decimal(event["ml"], 2)
        available = sum(item["ml"] is not None for item in event["magnitudes"])
        result.append(
            f"EVENT {event['number']} ML={ml} n={available} "
            f"MD={decimal(event['md'], 2)}"
        )
        for item in event["magnitudes"]:
            pick = item["pick"]
            prefix = (
                f"{pick['station']} r={decimal(item['r'], 3)} "
                f"amp={pick['amplitude']} "
            )
            if item["ml"] is None:
                result.append(
                    prefix + f"clipped dur={pick['duration']} "
                    f"md={decimal(item['md'], 2)}"
                )
            else:
                result.append(
                    prefix + f"ml={decimal(item['ml'], 2)} "
                    f"res={decimal(item['ml'] - event['ml'], 2)} "
                    f"dur={pick['duration']} md={decimal(item['md'], 2)}"
                )
    result.append("CORRECTED")
    for event in events:
        result.append(
            f"EVENT {event['number']} MLC="
            + ("-" if event["ml_corrected"] is None
               else decimal(event["ml_corrected"], 2))
        )
    result.append("FMD")
    classes = stats["classes"]
    for value in range(min(classes), max(classes) + 1):
        result.append(
            f"M={magnitude_class(value)} N={classes[value]} "
            f"CUM={sum(count for key, count in classes.items() if key >= value)}"
        )
    result.extend([
        "MC " + magnitude_class(stats["completeness"]),
        f"BVALUE {decimal(stats['bvalue'], 3)} "
        f"SIGMA {decimal(stats['sigma'], 3)} N {stats['nb']}",
        f"AVALUE {decimal(stats['avalue'], 3)}",
    ])
    relation = stats["mlmd"]
    result.append(
        f"MLMD n={relation['n']} slope={decimal(relation['slope'], 3)} "
        f"intercept={decimal(relation['intercept'], 3)} "
        f"r={decimal(relation['r'], 3)} "
        f"mean_diff={decimal(relation['mean_diff'], 3)}"
    )
    result.extend(draw_timeline(events, params))
    return result


def station_file(stations, params, magnitude_corrections,
                 station_magnitude_residuals):
    """Six descriptive rows per station, including first/final location residuals."""
    result = []
    for station in stations:
        code = station["code"]
        picks = station["picks"]
        states = Counter(pick["state"] for pick in picks)
        used = [pick for pick in picks if pick["state"] == "used"]
        if used:
            before = math.sqrt(
                sum(pick["first_residual"] ** 2 for pick in used) / len(used)
            )
            after = math.sqrt(
                sum(pick["residual"] ** 2 for pick in used) / len(used)
            )
            before_s, after_s = decimal(before, 4), decimal(after, 4)
        else:
            before_s = after_s = "-"
        result.extend([
            f"STATION {code} x={station['x']} y={station['y']} "
            f"elevation={station['elevation']}",
            f"SAMPLES start={station['start']} count={len(station['samples'])} "
            f"mean={station['mean']} noise={decimal(station['noise'], 1)} "
            f"peak={station['peak']} clipped={station['clipped_samples']}",
            f"TRIGGERS total={station['triggers']} "
            f"short={station['short_triggers']} picks={len(picks)}",
            "PICKS " + " ".join(
                f"{name}={states[name]}"
                for name in ("used", "dropped", "added", "rejected", "unassociated")
            ),
            f"RESIDUALS n={len(used)} rms={before_s} "
            f"correction={decimal(station['time_correction'], 4)} after={after_s}",
            f"MAGNITUDES n={len(station_magnitude_residuals[code])} "
            f"correction={decimal(magnitude_corrections[code], 2)}",
        ])
    return result


def event_symbol(event):
    if event["ml"] is None:
        return "?"
    scaled = display_coordinate(event["ml"], 2)
    if scaled < 100:
        return "."
    if scaled < 200:
        return "o"
    if scaled < 300:
        return "O"
    return "@"


def place_point(grid, position, symbol):
    if position is None:
        return
    column, row = position
    current = grid[row][column]
    ranks = {" ": -1, "?": 0, ".": 1, "o": 2, "O": 3, "@": 4, "^": 5}
    if ranks[symbol] > ranks[current]:
        grid[row][column] = symbol


def plotted_positions(event, params):
    """Chart coordinates from *displayed* 1-decimal catalog coordinates."""
    x, y, z = (display_coordinate(value, 1)
               for value in event["solution"][:3])
    left, right, bottom, top = params["map_area"]
    width, map_height = params["map_size"]
    depth_limit, section_height = params["section"]
    xy_valid = (10 * left <= x < 10 * right
                and 10 * bottom <= y < 10 * top)
    map_position = None
    if xy_valid:
        col = (x - 10 * left) * width // (10 * (right - left))
        row = map_height - 1 - (y - 10 * bottom) * map_height // (10 * (top - bottom))
        map_position = col, row
    section_z = z * section_height // (10 * depth_limit)
    ew_position = (
        ((x - 10 * left) * width // (10 * (right - left)), section_z)
        if 10 * left <= x < 10 * right and z < 10 * depth_limit else None
    )
    ns_position = (
        ((y - 10 * bottom) * width // (10 * (top - bottom)), section_z)
        if 10 * bottom <= y < 10 * top and z < 10 * depth_limit else None
    )
    return {"map": map_position, "ew": ew_position, "ns": ns_position}


def station_map_point(station, params):
    left, right, bottom, top = params["map_area"]
    width, height = params["map_size"]
    x, y = station["x"], station["y"]
    if not (left <= x < right and bottom <= y < top):
        return None
    return (
        (x - left) * width // (right - left),
        height - 1 - (y - bottom) * height // (top - bottom),
    )


def position_text(position):
    return "outside" if position is None else f"{position[0]},{position[1]}"


def map_file(events, stations, params):
    """Priority-based epicenter and orthogonal section plots with coordinates."""
    left, right, bottom, top = params["map_area"]
    width, map_height = params["map_size"]
    depth_limit, section_height = params["section"]
    grids = {
        "map": [[" "] * width for _ in range(map_height)],
        "ew": [[" "] * width for _ in range(section_height)],
        "ns": [[" "] * width for _ in range(section_height)],
    }
    locations = {}
    for event in events:
        place = plotted_positions(event, params)
        locations[event["number"]] = place
        symbol = event_symbol(event)
        for kind in ("map", "ew", "ns"):
            place_point(grids[kind], place[kind], symbol)

    station_locations = {}
    for station in stations:
        position = station_map_point(station, params)
        station_locations[station["code"]] = position
        place_point(grids["map"], position, "^")

    result = []
    for kind, heading in (
        ("map", f"MAP x={left}..{right} y={bottom}..{top}"),
        ("ew", f"SECTION EW x={left}..{right} z=0..{depth_limit}"),
        ("ns", f"SECTION NS y={bottom}..{top} z=0..{depth_limit}"),
    ):
        result.append(heading)
        result.append(plot_frame(width))
        result.extend("|" + "".join(row) + "|" for row in grids[kind])
        result.append(plot_frame(width))
    result.append("LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML")
    for station in stations:
        result.append(
            f"STATION {station['code']} map="
            f"{position_text(station_locations[station['code']])}"
        )
    for event in events:
        points = locations[event["number"]]
        result.append(
            f"EVENT {event['number']} {event_symbol(event)} "
            f"map={position_text(points['map'])} "
            f"ew={position_text(points['ew'])} "
            f"ns={position_text(points['ns'])}"
        )
    return result


def main():
    """Run the seismic network processing stages and write six result files."""
    stations, params = load_inputs()
    picks = collect_picks(stations, params)
    candidates = associate(
        picks, params["association_window"], params["min_stations"]
    )
    events = locate_candidates(candidates, params)
    time_corrections = station_time_corrections(events, stations)
    for station in stations:
        station["time_correction"] = time_corrections[station["code"]]
    relocate_events(events, stations, params, time_corrections)
    magnitude_corrections, magnitude_residuals = compute_magnitudes(
        events, stations, params
    )
    regression = travel_time_regression(events, params)
    clusters = cluster_events(events, params)
    added = reassociate_unassigned(picks, events, time_corrections, params)
    statistics = magnitude_class_counts(events)

    write_lines("picks.csv", build_picks_file(picks))
    write_lines("locations.txt", location_file(
        picks, candidates, events, stations, time_corrections,
        regression, clusters, added, params,
    ))
    write_lines("catalog.csv", catalog_rows(events))
    write_lines("magnitudes.txt", magnitude_file(events, statistics, params))
    write_lines("stations.txt", station_file(
        stations, params, magnitude_corrections, magnitude_residuals,
    ))
    write_lines("map.txt", map_file(events, stations, params))


if __name__ == "__main__":
    main()
