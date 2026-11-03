"""Exact-overlap scheduling and quadratic/linear loss-of-separation intervals."""

import math

from trajectory import position


def loss_interval(relative, velocity, time_start, time_end, horizontal, vertical):
    """Intersect strict horizontal and vertical losses, then compute CPA."""
    px, py, pz = relative
    wx, wy, wz = velocity
    qa = wx * wx + wy * wy
    qb = 2 * (px * wx + py * wy)
    qc = px * px + py * py - horizontal * horizontal
    lo, hi = time_start, time_end
    if qa < 1e-12:
        if qc >= 0:
            return None
    else:
        discriminant = qb * qb - 4 * qa * qc
        if discriminant <= 0:
            return None
        root = math.sqrt(discriminant)
        lo = max(lo, time_start + (-qb - root) / (2 * qa))
        hi = min(hi, time_start + (-qb + root) / (2 * qa))
    if wz == 0:
        if abs(pz) >= vertical:
            return None
    else:
        first = (-vertical - pz) / wz
        second = (vertical - pz) / wz
        lo = max(lo, time_start + min(first, second))
        hi = min(hi, time_start + max(first, second))
    if hi - lo <= 1e-6:
        return None
    tc = time_start + (-qb / (2 * qa)) if qa >= 1e-12 else time_start
    tc = min(max(tc, lo), hi)
    elapsed = tc - time_start
    ex = px + wx * elapsed
    ey = py + wy * elapsed
    return {
        "lo": lo,
        "hi": hi,
        "tc": tc,
        "distance": math.sqrt(ex * ex + ey * ey),
        "vertical": abs(pz + wz * elapsed),
    }


def pair_conflicts(name_a, trajectory_a, name_b, trajectory_b, dh, dv):
    """Combine overlapping segment-pair pieces into per-aircraft-pair conflicts."""
    pieces = []
    for a in trajectory_a["segments"]:
        for b in trajectory_b["segments"]:
            t1 = max(a["ts"], b["ts"])
            t2 = min(a["te"], b["te"])
            if t1 >= t2:
                continue
            pa = position(a, t1)
            pb = position(b, t1)
            relative = tuple(pa[i] - pb[i] for i in range(3))
            velocity = tuple(
                a["velocity"][i] - b["velocity"][i] for i in range(3)
            )
            interval = loss_interval(relative, velocity, t1, t2, dh, dv)
            if interval is not None:
                pieces.append({
                    **interval,
                    "a_segment": a,
                    "b_segment": b,
                })
    pieces.sort(key=lambda piece: piece["lo"])
    conflicts = []
    for piece in pieces:
        if not conflicts or piece["lo"] - conflicts[-1]["end"] > 1e-6:
            conflicts.append({
                "pair": (name_a, name_b),
                "name": name_a + "-" + name_b,
                "start": piece["lo"],
                "end": piece["hi"],
                "pieces": [piece],
                "closest": piece,
            })
        else:
            conflict = conflicts[-1]
            conflict["pieces"].append(piece)
            conflict["end"] = piece["hi"]
            if piece["distance"] < conflict["closest"]["distance"] - 1e-9:
                conflict["closest"] = piece
    return conflicts


def all_conflicts(trajectories, dh, dv):
    """Pair order is canonical; conflicts are time-sorted with ASCII tie-breaks."""
    names = sorted(trajectories)
    conflicts = []
    for index, first in enumerate(names):
        for second in names[index + 1:]:
            conflicts.extend(pair_conflicts(
                first, trajectories[first],
                second, trajectories[second], dh, dv,
            ))
    conflicts.sort(key=lambda conflict:
                   (conflict["start"], conflict["pair"][0], conflict["pair"][1]))
    return conflicts
