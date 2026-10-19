"""Build 4-D straight-line trajectories and evaluate positions along them."""

import math


def leg_vector(first, second, speed):
    dx = second["x"] - first["x"]
    dy = second["y"] - first["y"]
    distance = math.sqrt(dx * dx + dy * dy) / 10
    duration = distance * 3600 / speed
    return (
        distance, duration,
        (dx / 10) / duration,
        (dy / 10) / duration,
    )


def make_segment(leg, phase, start, end, location, velocity, number):
    dt = end - start
    finish = tuple(
        location[i] + velocity[i] * dt for i in range(3)
    )
    return {
        "number": number,
        "leg": leg,
        "phase": phase,
        "ts": start,
        "te": end,
        "start": location,
        "velocity": velocity,
        "end": finish,
    }


def build_trajectory(plan, aircraft_types):
    """A change of altitude occurs first; remaining leg time is level flight."""
    waypoints = plan["waypoints"]
    current = plan["departure"] + plan["delay"]
    level = plan["level"] + plan["offset"]
    segments = []
    route_length = 0.0
    times = [(current, level)]
    aircraft_type = aircraft_types[plan["type"]]
    for leg in range(1, len(waypoints)):
        start = waypoints[leg - 1]
        stop = waypoints[leg]
        length, duration, vx, vy = leg_vector(start, stop, plan["speed"])
        route_length += length
        target = (
            level if stop["level"] is None
            else stop["level"] + plan["offset"]
        )
        x, y = start["x"] / 10, start["y"] / 10
        if target == level:
            part = make_segment(
                leg, "LVL", current, current + duration,
                (x, y, level * 100), (vx, vy, 0.0), len(segments) + 1,
            )
            # The final horizontal coordinates are the input waypoint.
            part["end"] = (stop["x"] / 10, stop["y"] / 10, target * 100)
            segments.append(part)
        else:
            climbing = target > level
            rate = aircraft_type["climb"] if climbing else aircraft_type["descent"]
            vz = rate / 60 if climbing else -(rate / 60)
            climb_time = abs(target - level) * 6000 / rate
            phase = "CLB" if climbing else "DES"
            change = make_segment(
                leg, phase, current, current + climb_time,
                (x, y, level * 100), (vx, vy, vz), len(segments) + 1,
            )
            change["end"] = (
                x + vx * climb_time, y + vy * climb_time, target * 100
            )
            segments.append(change)
            level_part = make_segment(
                leg, "LVL", current + climb_time, current + duration,
                change["end"], (vx, vy, 0.0), len(segments) + 1,
            )
            level_part["end"] = (
                stop["x"] / 10, stop["y"] / 10, target * 100
            )
            segments.append(level_part)
        current += duration
        level = target
        times.append((current, level))
    return {
        "segments": segments,
        "arrival": current,
        "length": route_length,
        "waypoint_times": times,
    }


def position(segment, time):
    elapsed = time - segment["ts"]
    return tuple(
        segment["start"][i] + segment["velocity"][i] * elapsed
        for i in range(3)
    )


def active_segment(trajectory, time):
    """Return the first segment on [ts, te), or None outside flight."""
    segments = trajectory["segments"]
    if not (segments[0]["ts"] <= time < segments[-1]["te"]):
        return None
    for segment in segments:
        if segment["ts"] <= time < segment["te"]:
            return segment
    return None


def current_position(trajectory, time):
    segment = active_segment(trajectory, time)
    if segment is None:
        return None
    return position(segment, time), segment
