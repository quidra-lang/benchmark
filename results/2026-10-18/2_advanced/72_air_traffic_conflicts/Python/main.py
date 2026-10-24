"""4-D air-traffic conflict detection, resolution, and operational reports.

Execute from the task directory with python3 Python/main.py.
All nine outputs are written below output/; stdout is never used.
"""

from collections import Counter, defaultdict
import math

from conflict import all_conflicts, loss_interval, pair_conflicts
from flight_plans import clone_plan, load_all
from report import chart, decimal, named, signed, write_lines
from resolution import manoeuvres, priority_order, propose
from trajectory import (
    active_segment, build_trajectory, current_position, position,
)


PI = 3.141592653589793


def sample_times(params):
    return list(range(params["sample_start"], params["sample_end"], 60))


def pair_name(first, second):
    a, b = sorted((first, second))
    return f"{a}-{b}"


def find_blockers(changed, new_trajectory, partner, trajectories, unresolved,
                  conflict_start, params):
    """Block any conflict with partner, or any new near-term conflict."""
    blockers = []
    for other in sorted(trajectories):
        if other == changed:
            continue
        names = sorted((changed, other))
        if tuple(names) in unresolved:
            continue
        first = new_trajectory if names[0] == changed else trajectories[names[0]]
        second = new_trajectory if names[1] == changed else trajectories[names[1]]
        for conflict in pair_conflicts(
                names[0], first, names[1], second,
                params["dh"], params["dv"]):
            if (other == partner
                    or conflict["start"] < conflict_start + params["lookahead"]):
                blockers.append(conflict)
    return min(
        blockers,
        key=lambda item: (item["start"], *item["pair"]),
        default=None,
    )


def resolve_conflicts(initial_plans, types, params):
    """Try cumulative manoeuvres until every remaining pair is unresolved."""
    plans = {code: clone_plan(plan) for code, plan in initial_plans.items()}
    trajectories = {
        code: build_trajectory(plan, types)
        for code, plan in plans.items()
    }
    unresolved_pairs = set()
    resolved_pairs = set()
    rounds = []
    unresolved_conflicts = []
    while True:
        conflicts = all_conflicts(trajectories, params["dh"], params["dv"])
        target = next(
            (conflict for conflict in conflicts
             if conflict["pair"] not in unresolved_pairs),
            None,
        )
        if target is None:
            break
        names = target["pair"]
        first, second = priority_order(plans[names[0]], plans[names[1]])
        round_record = {
            "number": len(rounds) + 1, "target": target,
            "trials": [], "accepted": None,
        }
        for aircraft, partner in ((first, second), (second, first)):
            if round_record["accepted"] is not None:
                break
            for name, amount in manoeuvres(params["max_delay"]):
                proposal = propose(plans[aircraft], name, amount, types, params)
                entry = {"aircraft": aircraft, "name": name}
                if proposal is None:
                    entry["status"] = "infeasible"
                else:
                    new_trajectory = build_trajectory(proposal, types)
                    blocker = find_blockers(
                        aircraft, new_trajectory, partner, trajectories,
                        unresolved_pairs, target["start"], params,
                    )
                    if blocker is not None:
                        entry["status"] = "blocked"
                        entry["blocker"] = blocker
                    else:
                        entry["status"] = "accepted"
                        proposal["history"].append(name)
                        plans[aircraft] = proposal
                        trajectories[aircraft] = new_trajectory
                        round_record["accepted"] = entry
                round_record["trials"].append(entry)
                if entry["status"] == "accepted":
                    break
        if round_record["accepted"] is None:
            unresolved_pairs.add(names)
            unresolved_conflicts.append(target)
        else:
            resolved_pairs.add(names)
        rounds.append(round_record)
    return (
        plans, trajectories, rounds, unresolved_pairs,
        resolved_pairs, unresolved_conflicts,
    )


def segment_track(segment):
    vx, vy, _ = segment["velocity"]
    angle = math.atan2(vx, vy) * 180 / PI
    return angle + 360 if angle < 0 else angle


def sector_contains(sector, location):
    x, y, z = location
    return (
        sector["x1"] / 10 <= x < sector["x2"] / 10
        and sector["y1"] / 10 <= y < sector["y2"] / 10
        and sector["lower"] * 100 <= z < sector["upper"] * 100
    )


def classify_conflicts(conflicts, sectors, final_pairs, resolved_pairs,
                       horizontal_separation, final=False):
    """Attach phases, direction, severity, sector and outcome at the CPA."""
    for conflict in conflicts:
        piece = conflict["closest"]
        a, b = piece["a_segment"], piece["b_segment"]
        tc = piece["tc"]
        pa, pb = position(a, tc), position(b, tc)
        track_a, track_b = segment_track(a), segment_track(b)
        separation = abs(track_a - track_b)
        if separation > 180:
            separation = 360 - separation
        avx, avy, _ = a["velocity"]
        bvx, bvy, _ = b["velocity"]
        product = avx * bvx + avy * bvy
        cross = avx * bvy - avy * bvx
        if product * product > cross * cross:
            geometry = "head_on" if product < 0 else "trailing"
        else:
            geometry = "crossing"
        distance = piece["distance"]
        if 10 * distance < 4 * horizontal_separation:
            severity = "HIGH"
        elif 10 * distance < 7 * horizontal_separation:
            severity = "MEDIUM"
        else:
            severity = "LOW"
        midpoint = tuple((pa[i] + pb[i]) / 2 for i in range(3))
        sector = next(
            (item["name"] for item in sectors
             if sector_contains(item, midpoint)),
            "-",
        )
        if final or conflict["pair"] in final_pairs:
            outcome = "remaining"
        elif conflict["pair"] in resolved_pairs:
            outcome = "resolved"
        else:
            outcome = "indirect"
        conflict.update({
            "level_a": pa[2] / 100, "level_b": pb[2] / 100,
            "track_a": track_a, "track_b": track_b,
            "angle": separation, "geometry": geometry,
            "severity": severity, "sector": sector, "outcome": outcome,
        })


def conflicts_by_aircraft(conflicts):
    result = defaultdict(list)
    for conflict in conflicts:
        a, b = conflict["pair"]
        result[a].append((conflict, b))
        result[b].append((conflict, a))
    return result


def active_conflicts(conflicts, time):
    return [
        conflict for conflict in conflicts
        if conflict["start"] <= time < conflict["end"]
    ]


def trajectories_csv(trajectories):
    lines = [
        "callsign,segment,leg,phase,t_start,t_end,"
        "x_start,y_start,fl_start,x_end,y_end,fl_end",
    ]
    for code in sorted(trajectories):
        for segment in trajectories[code]["segments"]:
            start, end = segment["start"], segment["end"]
            fields = [
                code, str(segment["number"]), str(segment["leg"]),
                segment["phase"], decimal(segment["ts"]), decimal(segment["te"]),
                decimal(start[0]), decimal(start[1]), str(round(start[2] / 100)),
                decimal(end[0]), decimal(end[1]), str(round(end[2] / 100)),
            ]
            lines.append(",".join(fields))
    return lines


def conflict_lines(label, conflicts, trajectories, params):
    result = [f"CONFLICTS plan={label} count={len(conflicts)}"]
    for number, conflict in enumerate(conflicts, 1):
        piece = conflict["closest"]
        result.append(
            f"CONFLICT {number} {conflict['name']} "
            f"start={decimal(conflict['start'])} "
            f"end={decimal(conflict['end'])} "
            f"duration={decimal(conflict['end'] - conflict['start'])} "
            f"outcome={conflict['outcome']}"
        )
        result.append(
            f"  CPA t={decimal(piece['tc'])} "
            f"dist={decimal(piece['distance'])} "
            f"vert={decimal(piece['vertical'], 1)} "
            f"levels={decimal(conflict['level_a'], 2)}/"
            f"{decimal(conflict['level_b'], 2)} "
            f"tracks={decimal(conflict['track_a'], 1)}/"
            f"{decimal(conflict['track_b'], 1)} "
            f"angle={decimal(conflict['angle'], 1)}"
        )
        result.append(
            f"  TYPE geometry={conflict['geometry']} "
            f"phases={piece['a_segment']['phase']}/"
            f"{piece['b_segment']['phase']} "
            f"segments={piece['a_segment']['number']}/"
            f"{piece['b_segment']['number']} "
            f"sector={conflict['sector']} severity={conflict['severity']}"
        )
        for section in conflict["pieces"]:
            result.append(
                f"  PIECE {section['a_segment']['number']}/"
                f"{section['b_segment']['number']} "
                f"{decimal(section['lo'])} {decimal(section['hi'])}"
            )
    geometry = Counter(conflict["geometry"] for conflict in conflicts)
    severity = Counter(conflict["severity"] for conflict in conflicts)
    closest = min((c["closest"]["distance"] for c in conflicts), default=None)
    result.append(
        "SUMMARY " + named(
            count=len(conflicts),
            total=decimal(sum(c["end"] - c["start"] for c in conflicts)),
            min_dist=decimal(closest) if closest is not None else "-",
            head_on=geometry["head_on"], crossing=geometry["crossing"],
            trailing=geometry["trailing"],
            high=severity["HIGH"], medium=severity["MEDIUM"],
            low=severity["LOW"],
        )
    )
    flights = conflicts_by_aircraft(conflicts)
    for code in sorted(flights):
        involvement = flights[code]
        result.append(
            f"FLIGHT {code} " + named(
                conflicts=len(involvement),
                first=decimal(min(item[0]["start"] for item in involvement)),
                partners=",".join(sorted({item[1] for item in involvement})),
            )
        )
    result.append(
        f"TIMELINE from={params['sample_start']} "
        f"to={params['sample_end']} step=60"
    )
    for code in sorted(flights):
        symbols = []
        for time in sample_times(params):
            if active_segment(trajectories[code], time) is None:
                symbols.append(".")
            elif any(
                    c["start"] <= time < c["end"]
                    for c, _ in flights[code]):
                symbols.append("X")
            else:
                symbols.append("-")
        result.append(code + " " + "".join(symbols))
    return result


def resolution_lines(initial, final, trajectories_initial, trajectories_final,
                     initial_conflicts, final_conflicts, rounds,
                     unresolved_conflicts):
    result = []
    for record in rounds:
        target = record["target"]
        result.append(
            f"ROUND {record['number']} {target['name']} "
            f"start={decimal(target['start'])} "
            f"end={decimal(target['end'])} "
            f"dist={decimal(target['closest']['distance'])}"
        )
        for trial in record["trials"]:
            line = f"  TRY {trial['aircraft']} {trial['name']} {trial['status']}"
            if trial["status"] == "blocked":
                blocker = trial["blocker"]
                line += f" {blocker['name']} start={decimal(blocker['start'])}"
            result.append(line)
        accepted = record["accepted"]
        if accepted is None:
            result.append("  RESULT unresolved")
        else:
            result.append(
                f"  RESULT resolved {accepted['aircraft']} {accepted['name']}"
            )
    initial_count = Counter(
        code for conflict in initial_conflicts for code in conflict["pair"]
    )
    final_count = Counter(
        code for conflict in final_conflicts for code in conflict["pair"]
    )
    total_extra = 0.0
    for code in sorted(final):
        old, new = initial[code], final[code]
        old_arrival = trajectories_initial[code]["arrival"]
        new_arrival = trajectories_final[code]["arrival"]
        extra = new_arrival - old_arrival
        total_extra += extra
        manoeuvres_text = ",".join(new["history"]) if new["history"] else "-"
        result.append(
            f"FLIGHT {code} "
            f"departure={new['departure'] + new['delay']} "
            f"delay={new['delay']} level={signed(new['offset'])} "
            f"speed={old['speed']}->{new['speed']} "
            f"arrival={decimal(old_arrival)}->{decimal(new_arrival)} "
            f"extra={decimal(extra)} "
            f"length={decimal(trajectories_final[code]['length'])} "
            f"conflicts={initial_count[code]}->{final_count[code]} "
            f"manoeuvres={manoeuvres_text}"
        )
    for conflict in unresolved_conflicts:
        result.append(
            f"UNRESOLVED {conflict['name']} "
            f"start={decimal(conflict['start'])} "
            f"dist={decimal(conflict['closest']['distance'])}"
        )
    attempts = [trial for record in rounds for trial in record["trials"]]
    accepted = [record["accepted"] for record in rounds if record["accepted"]]
    result.append(
        "TOTAL " + named(
            rounds=len(rounds), resolved=len(accepted),
            unresolved=len(unresolved_conflicts),
            level=sum(t["name"].startswith("level_") for t in accepted),
            speed=sum(t["name"] == "speed_down" for t in accepted),
            delay=sum(t["name"].startswith("delay_") for t in accepted),
            total_delay=sum(plan["delay"] for plan in final.values()),
            total_extra=decimal(total_extra), trials=len(attempts),
            infeasible=sum(t["status"] == "infeasible" for t in attempts),
            blocked=sum(t["status"] == "blocked" for t in attempts),
        )
    )
    return result


def inside_segment_sector(segment, sector):
    """Clip a linearly moving segment to the sector's half-open 3-D box."""
    start = segment["start"]
    velocity = segment["velocity"]
    limits = (
        (sector["x1"] / 10, sector["x2"] / 10),
        (sector["y1"] / 10, sector["y2"] / 10),
        (sector["lower"] * 100, sector["upper"] * 100),
    )
    lo, hi = segment["ts"], segment["te"]
    for axis, (low, high) in enumerate(limits):
        p, v = start[axis], velocity[axis]
        if v == 0:
            if not low <= p < high:
                return None
        else:
            r1 = (low - p) / v
            r2 = (high - p) / v
            lo = max(lo, segment["ts"] + min(r1, r2))
            hi = min(hi, segment["ts"] + max(r1, r2))
    return (lo, hi) if hi - lo > 1e-6 else None


def sector_transits(trajectories, sectors):
    """Join adjacent in-sector segment intervals and assign handoff neighbors."""
    all_transits = []
    for code in sorted(trajectories):
        aircraft_transits = []
        for sector in sectors:
            combined = []
            for segment in trajectories[code]["segments"]:
                interval = inside_segment_sector(segment, sector)
                if interval is None:
                    continue
                lo, hi = interval
                if combined and lo - combined[-1][1] <= 1e-6:
                    combined[-1] = (combined[-1][0], hi)
                else:
                    combined.append((lo, hi))
            for entry, exit_time in combined:
                aircraft_transits.append({
                    "callsign": code, "sector": sector["name"],
                    "sector_index": sector["index"],
                    "entry": entry, "exit": exit_time,
                    "from": "-", "to": "-",
                })
        aircraft_transits.sort(
            key=lambda tr: (tr["entry"], tr["sector_index"])
        )
        for prev, later in zip(aircraft_transits, aircraft_transits[1:]):
            if abs(later["entry"] - prev["exit"]) <= 1e-6:
                prev["to"] = later["sector"]
                later["from"] = prev["sector"]
        all_transits.extend(aircraft_transits)
    return all_transits


def transit_lines(transits):
    rows = ["callsign,sector,entry,exit,duration,from,to"]
    for item in transits:
        rows.append(",".join((
            item["callsign"], item["sector"],
            decimal(item["entry"]), decimal(item["exit"]),
            decimal(item["exit"] - item["entry"]),
            item["from"], item["to"],
        )))
    return rows


def occupancy_table(trajectories, sectors, times):
    """At each sample, an aircraft may contribute to multiple sectors."""
    result = {sector["name"]: [0] * len(times) for sector in sectors}
    for i, time in enumerate(times):
        for code in sorted(trajectories):
            observed = current_position(trajectories[code], time)
            if observed is None:
                continue
            point, _ = observed
            for sector in sectors:
                if sector_contains(sector, point):
                    result[sector["name"]][i] += 1
    return result


def period_table(sectors, samples, occupancy_initial, occupancy_final,
                 transits_initial, transits_final):
    """Group exactly five one-minute sample times into five-minute periods."""
    rows = []
    for sector in sectors:
        code, capacity = sector["name"], sector["capacity"]
        for i in range(0, len(samples), 5):
            first, last = samples[i], samples[i] + 300
            initial_values = occupancy_initial[code][i:i + 5]
            final_values = occupancy_final[code][i:i + 5]
            initial_peak = max(initial_values)
            final_peak = max(final_values)
            initial_entries = sum(
                item["sector"] == code and first <= item["entry"] < last
                for item in transits_initial
            )
            final_entries = sum(
                item["sector"] == code and first <= item["entry"] < last
                for item in transits_final
            )
            status = (
                "OVER" if final_peak > capacity else
                "RELIEVED" if initial_peak > capacity else "OK"
            )
            rows.append({
                "sector": code, "period": i // 5 + 1,
                "start": first, "end": last,
                "entries_initial": initial_entries,
                "entries_final": final_entries,
                "peak_initial": initial_peak,
                "peak_final": final_peak,
                "mean_final": sum(final_values) / 5,
                "capacity": capacity, "status": status,
            })
    return rows


def sector_load_lines(rows):
    output = [
        "sector,period,start,end,entries_initial,entries_final,"
        "peak_initial,peak_final,mean_final,capacity,status"
    ]
    for item in rows:
        output.append(",".join((
            item["sector"], str(item["period"]),
            str(item["start"]), str(item["end"]),
            str(item["entries_initial"]), str(item["entries_final"]),
            str(item["peak_initial"]), str(item["peak_final"]),
            decimal(item["mean_final"], 1),
            str(item["capacity"]), item["status"],
        )))
    return output


def level_usage(trajectories):
    """Count aircraft and summed durations by flight level of LVL segments."""
    result = {}
    for code in sorted(trajectories):
        for segment in trajectories[code]["segments"]:
            if segment["phase"] != "LVL":
                continue
            level = round(segment["start"][2] / 100)
            if level not in result:
                result[level] = {"flights": set(), "time": 0.0}
            result[level]["flights"].add(code)
            result[level]["time"] += segment["te"] - segment["ts"]
    return result


def sector_report(sectors, samples, occupancy_initial, occupancy_final,
                  transits_initial, transits_final, periods,
                  conflicts_initial, conflicts_final, trajectories_initial,
                  trajectories_final):
    """Sector occupancy charts, per-sector statistics, levels and handoffs."""
    output = []
    for sector in sectors:
        code, capacity = sector["name"], sector["capacity"]
        output.append(
            f"SECTOR {code} "
            f"x={sector['x1']}..{sector['x2']} "
            f"y={sector['y1']}..{sector['y2']} "
            f"fl={sector['lower']}..{sector['upper']} capacity={capacity}"
        )
        for label, transits, occupancies, conflicts in (
            ("INITIAL", transits_initial, occupancy_initial, conflicts_initial),
            ("FINAL", transits_final, occupancy_final, conflicts_final),
        ):
            matching = [t for t in transits if t["sector"] == code]
            dwell = sum(t["exit"] - t["entry"] for t in matching)
            period_peaks = [
                max(occupancies[code][index:index + 5])
                for index in range(0, len(samples), 5)
            ]
            output.append(
                label + " " + named(
                    entries=len(matching), time=decimal(dwell),
                    mean=decimal(dwell / len(matching)) if matching else "-",
                    peak=max(occupancies[code]),
                    over=sum(peak > capacity for peak in period_peaks),
                    conflicts=sum(c["sector"] == code for c in conflicts),
                )
            )
        height = max(capacity + 1, max(occupancy_final[code]))
        cells = []
        for level in range(height, 0, -1):
            cells.append("".join(
                "#" if value >= level else "-" if level == capacity else "."
                for value in occupancy_final[code]
            ))
        output.extend(chart(cells))

    before, after = level_usage(trajectories_initial), level_usage(
        trajectories_final
    )
    output.append("LEVELS")
    for level in sorted(set(before) | set(after), reverse=True):
        initial = before.get(level, {"flights": set(), "time": 0.0})
        final = after.get(level, {"flights": set(), "time": 0.0})
        output.append(
            f"LEVEL {level} "
            f"flights={len(initial['flights'])}->{len(final['flights'])} "
            f"time={decimal(initial['time'])}->{decimal(final['time'])}"
        )
    handoffs = Counter(
        (entry["sector"], entry["to"])
        for entry in transits_final if entry["to"] != "-"
    )
    order = {sector["name"]: sector["index"] for sector in sectors}
    output.append(f"HANDOFFS plan=final count={sum(handoffs.values())}")
    for source, destination in sorted(
            handoffs, key=lambda pair: (order[pair[0]], order[pair[1]])):
        output.append(f"HANDOFF {source} {destination} {handoffs[source, destination]}")
    return output


def compute_alerts(trajectories, conflicts, params):
    """Predict straight-line short-term losses at every one-minute sample."""
    observations = defaultdict(list)
    names = sorted(trajectories)
    for time in sample_times(params):
        in_flight = {}
        for code in names:
            value = current_position(trajectories[code], time)
            if value is not None:
                in_flight[code] = value
        active_names = sorted(in_flight)
        for i, first in enumerate(active_names):
            pos_a, seg_a = in_flight[first]
            for second in active_names[i + 1:]:
                pos_b, seg_b = in_flight[second]
                relative = tuple(pos_a[j] - pos_b[j] for j in range(3))
                velocity = tuple(
                    seg_a["velocity"][j] - seg_b["velocity"][j]
                    for j in range(3)
                )
                loss = loss_interval(
                    relative, velocity, 0, params["alert"],
                    params["dh"], params["dv"],
                )
                if loss is not None:
                    observations[(first, second)].append({
                        "time": time, "loss": time + loss["lo"],
                        "distance": loss["distance"],
                    })
    alerts = []
    for pair, events in observations.items():
        groups = []
        for entry in events:
            if groups and entry["time"] - groups[-1][-1]["time"] == 60:
                groups[-1].append(entry)
            else:
                groups.append([entry])
        for group in groups:
            alerts.append({
                "pair": pair, "name": pair_name(*pair),
                "first": group[0]["time"], "last": group[-1]["time"],
                "samples": len(group), "predicted": group[0]["loss"],
                "min_dist": min(item["distance"] for item in group),
            })
    alerts.sort(key=lambda item: (item["first"], *item["pair"]))
    detected = set()
    for alert in alerts:
        matches = [
            index for index, conflict in enumerate(conflicts)
            if conflict["pair"] == alert["pair"]
            and conflict["start"] < alert["last"] + params["alert"]
            and conflict["end"] > alert["first"]
        ]
        alert["matches"] = matches
        alert["lead"] = (
            conflicts[matches[0]]["start"] - alert["first"]
            if matches else None
        )
        detected.update(matches)
    missed = [
        conflict for index, conflict in enumerate(conflicts)
        if index not in detected
    ]
    return alerts, missed


def alert_lines(label, trajectories, conflicts, params):
    alerts, missed = compute_alerts(trajectories, conflicts, params)
    result = [
        f"ALERTS plan={label} horizon={params['alert']} count={len(alerts)}"
    ]
    leads = []
    for index, alert in enumerate(alerts, 1):
        if alert["lead"] is None:
            status = "status=false lead=-"
        else:
            leads.append(alert["lead"])
            status = "status=true lead=" + decimal(alert["lead"])
        result.append(
            f"ALERT {index} {alert['name']} first={alert['first']} "
            f"last={alert['last']} samples={alert['samples']} "
            f"predicted={decimal(alert['predicted'])} "
            f"min_dist={decimal(alert['min_dist'])} {status}"
        )
    for conflict in missed:
        result.append(
            f"MISSED {conflict['name']} "
            f"start={decimal(conflict['start'])} "
            f"end={decimal(conflict['end'])}"
        )
    result.append(
        "SUMMARY " + named(
            alerts=len(alerts), true=len(leads),
            false=len(alerts) - len(leads), missed=len(missed),
            mean_lead=decimal(sum(leads) / len(leads)) if leads else "-",
        )
    )
    return result


def radar_cell(location, params):
    x, y, _ = location
    rx0, ry0, rx1, ry1, width, height = params["radar"]
    col = math.floor((10 * x - rx0) * width / (rx1 - rx0))
    bottom_row = math.floor((10 * y - ry0) * height / (ry1 - ry0))
    if 0 <= col < width and 0 <= bottom_row < height:
        return col, height - 1 - bottom_row
    return None


def radar_image(trajectories, conflicts, time, params):
    """Plot primary aircraft characters, overlaps, and lead positions."""
    width, height = params["radar"][4:]
    grid = [["."] * width for _ in range(height)]
    positions = {}
    collision_cells = defaultdict(list)
    for code in sorted(trajectories):
        observed = current_position(trajectories[code], time)
        if observed is None:
            continue
        pos, segment = observed
        cell = radar_cell(pos, params)
        positions[code] = {"position": pos, "segment": segment, "cell": cell}
        if cell is not None:
            collision_cells[cell].append(code)

    conflicts_at_time = active_conflicts(conflicts, time)
    conflicted_names = {
        code for conflict in conflicts_at_time for code in conflict["pair"]
    }
    for (col, row), names in collision_cells.items():
        if len(names) > 1:
            grid[row][col] = str(len(names))
        else:
            name = names[0]
            ch = name[0]
            grid[row][col] = ch.lower() if name in conflicted_names else ch

    for code in sorted(positions):
        predicted = current_position(trajectories[code], time + params["leader"])
        if predicted is None:
            continue
        cell = radar_cell(predicted[0], params)
        if cell is not None:
            col, row = cell
            if grid[row][col] == ".":
                grid[row][col] = "*"
    return positions, conflicts_at_time, ["".join(row) for row in grid]


def radar_snapshot_lines(label, trajectories, conflicts, time, params):
    positions, active, grid = radar_image(trajectories, conflicts, time, params)
    result = [
        f"RADAR plan={label} t={time} "
        f"aircraft={len(positions)} conflicts={len(active)}"
    ]
    result.extend(chart(grid))
    for code in sorted(positions):
        entry = positions[code]
        x, y, z = entry["position"]
        seg = entry["segment"]
        cell = entry["cell"]
        cell_text = f"{cell[0]},{cell[1]}" if cell is not None else "outside"
        result.append(
            f"{code} x={decimal(x)} y={decimal(y)} "
            f"fl={decimal(z / 100, 2)} "
            f"track={decimal(segment_track(seg), 1)} "
            f"phase={seg['phase']} cell={cell_text}"
        )
    for conflict in active:
        first, second = conflict["pair"]
        pa = positions[first]["position"]
        pb = positions[second]["position"]
        dx = pa[0] - pb[0]
        dy = pa[1] - pb[1]
        result.append(
            f"CONFLICT {conflict['name']} "
            f"dist={decimal(math.sqrt(dx * dx + dy * dy))} "
            f"vert={decimal(abs(pa[2] - pb[2]), 1)}"
        )
    return result


def radar_density_lines(label, trajectories, params):
    width, height = params["radar"][4:]
    density = [[0] * width for _ in range(height)]
    for time in sample_times(params):
        for code in sorted(trajectories):
            observed = current_position(trajectories[code], time)
            if observed is None:
                continue
            cell = radar_cell(observed[0], params)
            if cell is not None:
                density[cell[1]][cell[0]] += 1
    biggest = max(max(row) for row in density)
    result = [
        f"DENSITY plan={label} from={params['sample_start']} "
        f"to={params['sample_end']} step=60 max={biggest}"
    ]
    result.extend(chart([
        "".join("." if count == 0 else
                str(count) if count < 10 else "#" for count in row)
        for row in density
    ]))
    return result


def flight_strips(initial, final, trajectories_initial, trajectories_final,
                  transits_final):
    rows = []
    for code in sorted(initial):
        plan = final[code]
        original = trajectories_initial[code]
        revised = trajectories_final[code]
        histories = ",".join(plan["history"]) if plan["history"] else "-"
        rows.append(
            f"STRIP {code} type={plan['type']} "
            f"waypoints={len(plan['waypoints'])} "
            f"length={decimal(revised['length'])} manoeuvres={histories}"
        )
        for index, waypoint in enumerate(plan["waypoints"]):
            (old_time, old_level) = original["waypoint_times"][index]
            (new_time, new_level) = revised["waypoint_times"][index]
            rows.append(
                f"WPT {index} at={waypoint['x']}:{waypoint['y']} "
                f"eta={decimal(old_time)}->{decimal(new_time)} "
                f"fl={old_level}->{new_level}"
            )
        transits = [
            entry for entry in transits_final if entry["callsign"] == code
        ]
        sequence = ",".join(
            f"{entry['sector']}@{decimal(entry['entry'])}"
            for entry in transits
        ) or "-"
        rows.append(f"SECTORS {sequence}")
    return rows


def main():
    """Produce every required report for both unmodified and resolved plans."""
    initial, types, sectors, params = load_all()
    trajectories_initial = {
        code: build_trajectory(plan, types)
        for code, plan in initial.items()
    }
    initial_conflicts = all_conflicts(
        trajectories_initial, params["dh"], params["dv"]
    )
    (final, trajectories_final, rounds, unresolved, resolved,
     unresolved_conflicts) = resolve_conflicts(initial, types, params)
    final_conflicts = all_conflicts(
        trajectories_final, params["dh"], params["dv"]
    )
    final_pairs = {conflict["pair"] for conflict in final_conflicts}
    classify_conflicts(
        initial_conflicts, sectors, final_pairs, resolved, params["dh"]
    )
    classify_conflicts(
        final_conflicts, sectors, final_pairs, resolved, params["dh"], final=True
    )
    initial_transits = sector_transits(trajectories_initial, sectors)
    final_transits = sector_transits(trajectories_final, sectors)
    samples = sample_times(params)
    occupancy_initial = occupancy_table(trajectories_initial, sectors, samples)
    occupancy_final = occupancy_table(trajectories_final, sectors, samples)
    periods = period_table(
        sectors, samples, occupancy_initial, occupancy_final,
        initial_transits, final_transits
    )

    write_lines("trajectories.csv", trajectories_csv(trajectories_final))
    write_lines(
        "conflicts.txt",
        conflict_lines("initial", initial_conflicts, trajectories_initial, params)
        + conflict_lines("final", final_conflicts, trajectories_final, params),
    )
    write_lines(
        "resolutions.txt",
        resolution_lines(
            initial, final, trajectories_initial, trajectories_final,
            initial_conflicts, final_conflicts, rounds, unresolved_conflicts,
        ),
    )
    write_lines("sector_transits.csv", transit_lines(final_transits))
    write_lines("sector_load.csv", sector_load_lines(periods))
    write_lines(
        "sector_report.txt",
        sector_report(
            sectors, samples, occupancy_initial, occupancy_final,
            initial_transits, final_transits, periods,
            initial_conflicts, final_conflicts,
            trajectories_initial, trajectories_final,
        ),
    )
    write_lines(
        "alerts.txt",
        alert_lines("initial", trajectories_initial, initial_conflicts, params)
        + alert_lines("final", trajectories_final, final_conflicts, params),
    )
    radar_lines = []
    for time in params["snapshots"]:
        radar_lines.extend(
            radar_snapshot_lines(
                "initial", trajectories_initial, initial_conflicts, time, params
            )
        )
        radar_lines.extend(
            radar_snapshot_lines(
                "final", trajectories_final, final_conflicts, time, params
            )
        )
    radar_lines.extend(radar_density_lines("initial", trajectories_initial, params))
    radar_lines.extend(radar_density_lines("final", trajectories_final, params))
    write_lines("radar.txt", radar_lines)
    write_lines(
        "strips.txt",
        flight_strips(initial, final, trajectories_initial,
                      trajectories_final, final_transits),
    )


if __name__ == "__main__":
    main()
