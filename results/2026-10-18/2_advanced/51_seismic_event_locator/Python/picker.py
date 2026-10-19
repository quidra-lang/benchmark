"""Integer STA/LTA triggering, onset revision, amplitude and clipping."""

from statistics import median


def detect_station(station, params):
    """Compute station statistics and threshold picks from squared residuals."""
    sample = station["samples"]
    length = len(sample)
    mean = sum(sample) // length
    detrended = [value - mean for value in sample]
    energy = [value * value for value in detrended]
    sw = params["sta_window"]
    lw = params["lta_window"]
    trigger_on_num, trigger_on_den = params["trigger_on"]
    trigger_off_num, trigger_off_den = params["trigger_off"]
    prefix = [0]
    for value in energy:
        prefix.append(prefix[-1] + value)
    picks = []
    triggers = 0
    short_triggers = 0
    on = False
    beginning = None
    ratios = []

    def finish(end):
        nonlocal triggers, short_triggers
        triggers += 1
        duration = end - beginning
        if duration < params["min_duration"]:
            short_triggers += 1
            return
        position = beginning
        threshold = beginning - sw + 1
        while position - 1 >= threshold and energy[position - 1] >= params["noise_level"]:
            position -= 1
        last = min(position + params["amplitude_window"], length)
        amplitude = max(abs(detrended[j]) for j in range(position, last))
        clipped = any(abs(sample[j]) >= params["clip_level"] for j in range(position, last))
        peak_ratio = max(ratios)
        picks.append({
            "station": station["code"], "station_obj": station,
            "sample": station["start"] + position,
            "time": (station["start"] + position) / 100,
            "duration": duration,
            "ratio": peak_ratio, "amplitude": amplitude,
            "clipped": clipped,
            "state": "unassociated", "event": None, "residual": None,
            "assigned": False,
        })

    for i in range(sw + lw - 1, length):
        sta = prefix[i + 1] - prefix[i - sw + 1]
        lta = prefix[i - sw + 1] - prefix[i - sw - lw + 1]
        if not on:
            if sta * lw * trigger_on_den >= trigger_on_num * lta * sw:
                on = True
                beginning = i
                ratios = [(sta * lw) / (lta * sw)]
        else:
            if sta * lw * trigger_off_den < trigger_off_num * lta * sw:
                finish(i)
                on = False
            else:
                ratios.append((sta * lw) / (lta * sw))
    if on:
        finish(length)
    station["mean"] = mean
    station["noise"] = median(abs(value) for value in detrended)
    station["peak"] = max(abs(value) for value in detrended)
    station["clipped_samples"] = sum(
        abs(value) >= params["clip_level"] for value in sample
    )
    station["triggers"] = triggers
    station["short_triggers"] = short_triggers
    station["picks"] = picks
    return picks
