"""Pan-Tompkins-style ECG beat detection, matching, HRV analysis and plots.

The input and output directory paths are relative to the benchmark task root.
All the signal and reporting calculations use integer arithmetic exclusively.
"""

from collections import Counter

from detector import find_peaks, initial_levels, thresholds, width_ms
from filters import filter_ecg
from hrv import (
    consecutive_ranges, linked_sequences, nn_statistics, rr_statistics,
)
from report import four, fraction, maybe_two, ratio, rdiv, scale, two
from signal_io import read_annotations, read_ecg, read_params, write_lines


LABELS = ("N", "V", "A")
PEAK_CLASSES = ("qrs", "searchback", "twave", "refractory", "noise")


def detect_beats(peaks, signals, params):
    """Classify integrated peaks with RR-dependent search-back and thresholds."""
    initial = initial_levels(signals)
    levels = initial.copy()
    registered = []
    intervals = []
    ra1 = 200
    ra2 = 200
    refractory = params["refractory_ms"] // 5
    twave = params["twave_ms"] // 5

    def register(peak):
        nonlocal ra1, ra2
        if registered:
            elapsed = peak["time"] - registered[-1]["time"]
            intervals.append(elapsed)
            if len(intervals) > 8:
                intervals.pop(0)
            ra1 = sum(intervals) // len(intervals)
            if 92 * ra1 <= 100 * elapsed <= 116 * ra1:
                ra2 = ra1
        registered.append(peak)

    def update(peak, category):
        if category == "signal":
            levels["spki"] = (peak["peak_i"] + 7 * levels["spki"]) // 8
            levels["spkf"] = (peak["peak_f"] + 7 * levels["spkf"]) // 8
        elif category == "noise":
            levels["npki"] = (peak["peak_i"] + 7 * levels["npki"]) // 8
            levels["npkf"] = (peak["peak_f"] + 7 * levels["npkf"]) // 8
        else:
            levels["spki"] = (peak["peak_i"] + 3 * levels["spki"]) // 4
            levels["spkf"] = (peak["peak_f"] + 3 * levels["spkf"]) // 4

    def search_back(time):
        while True:
            last_time = registered[-1]["time"] if registered else 0
            if time - last_time <= ra2 * params["searchback_percent"] // 100:
                break
            current_thresholds = thresholds(levels)
            candidates = [
                p for p in peaks
                if p["class"] == "noise"
                and last_time < p["time"] < time
                and p["peak_i"] > current_thresholds["thi2"]
                and p["peak_f"] > current_thresholds["thf2"]
            ]
            if not candidates:
                break
            chosen = max(candidates, key=lambda p: (p["peak_i"], -p["time"]))
            update(chosen, "searchback")
            chosen["class"] = "searchback"
            register(chosen)

    for peak in peaks:
        time = peak["time"]
        search_back(time)
        threshold = thresholds(levels)
        peak["thr_i"] = threshold["thi1"]
        peak["thr_f"] = threshold["thf1"]
        last = registered[-1] if registered else None
        if last is not None and time - last["time"] < refractory:
            peak["class"] = "refractory"
            continue
        if peak["peak_i"] > threshold["thi1"] and peak["peak_f"] > threshold["thf1"]:
            if (last is not None and time - last["time"] < twave
                    and 2 * peak["slope"] < last["slope"]):
                peak["class"] = "twave"
                update(peak, "noise")
            else:
                peak["class"] = "qrs"
                update(peak, "signal")
                register(peak)
        else:
            peak["class"] = "noise"
            update(peak, "noise")

    search_back(len(signals["integrated"]))
    return {
        "peaks": peaks, "registered": registered,
        "initial": initial, "final": levels.copy(),
        "thresholds": thresholds(levels), "ra1": ra1, "ra2": ra2,
    }


def build_beat_list(registered, band, params):
    """Correct filter delay, measure QRS width, and classify premature beats."""
    beats = []
    for peak in registered:
        number = len(beats) + 1
        sample = max(0, peak["r"] - 21)
        rr = 5 * (sample - beats[-1]["sample"]) if beats else None
        width = width_ms(band, peak["r"])
        label = "N"
        if number >= 10:
            previous_eight = sum(
                beats[k - 1]["rr"] for k in range(number - 8, number)
            )
            if 800 * rr < params["premature_percent"] * previous_eight:
                label = "V" if width > params["qrs_width_ms"] else "A"
        beats.append({
            "number": number, "peak": peak, "sample": sample,
            "rr": rr, "hr": rdiv(6000000, rr) if rr is not None else None,
            "width": width, "label": label,
            "method": "threshold" if peak["class"] == "qrs" else "searchback",
            "annotation": None, "offset": None,
        })
    return beats


def match_annotations(beats, annotations, params):
    """Greedy first-available nearest reference, ties by sample number."""
    tolerance = params["match_ms"] // 5
    for beat in beats:
        candidates = [
            ref for ref in annotations
            if ref["beat"] is None
            and abs(ref["sample"] - beat["sample"]) <= tolerance
        ]
        if not candidates:
            continue
        chosen = min(
            candidates, key=lambda ref:
            (abs(ref["sample"] - beat["sample"]), ref["sample"])
        )
        chosen["beat"] = beat
        beat["annotation"] = chosen
        beat["offset"] = 5 * (beat["sample"] - chosen["sample"])


def write_beats(beats):
    lines = [
        "beat,sample,time_ms,rr_ms,hr_bpm,width_ms,"
        "label,method,ref_sample,ref_label"
    ]
    for beat in beats:
        annotation = beat["annotation"]
        lines.append(",".join(map(str, (
            beat["number"], beat["sample"], 5 * beat["sample"],
            beat["rr"] if beat["rr"] is not None else "-",
            two(beat["hr"]) if beat["hr"] is not None else "-",
            beat["width"], beat["label"], beat["method"],
            annotation["sample"] if annotation is not None else "-",
            annotation["label"] if annotation is not None else "-",
        ))))
    write_lines("beats.csv", lines)


def write_peaks(peaks):
    lines = ["peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class"]
    for index, peak in enumerate(peaks, 1):
        lines.append(",".join(map(str, (
            index, peak["time"], peak["r"], peak["peak_i"],
            peak["peak_f"], peak["slope"],
            peak["thr_i"], peak["thr_f"], peak["class"],
        ))))
    write_lines("peaks.csv", lines)


def write_matching(beats, annotations):
    """Sort matched/FN records before FP records at equal sample numbers."""
    records = []
    for ref in annotations:
        beat = ref["beat"]
        if beat is None:
            row = (
                ref["sample"], ref["label"], "-", "-", "-", "-", "FN", "-"
            )
        else:
            row = (
                ref["sample"], ref["label"], beat["number"],
                beat["sample"], beat["label"], beat["offset"], "TP",
                "yes" if ref["label"] == beat["label"] else "no",
            )
        records.append((ref["sample"], 0, row))
    for beat in beats:
        if beat["annotation"] is None:
            records.append((
                beat["sample"], 1,
                ("-", "-", beat["number"], beat["sample"],
                 beat["label"], "-", "FP", "-"),
            ))
    records.sort(key=lambda record: (record[0], record[1]))
    lines = ["ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree"]
    for _, _, record in records:
        lines.append(",".join(map(str, record)))
    write_lines("matching.csv", lines)


def write_signal_excerpt(samples, signals, params):
    lines = ["sample,ecg,lowpass,bandpass,derivative,squared,integrated"]
    for n in range(params["excerpt_ms"] // 5):
        lines.append(",".join(map(str, (
            n, samples[n],
            signals["lowpass"][n], signals["bandpass"][n],
            signals["derivative"][n], signals["squared"][n],
            signals["integrated"][n],
        ))))
    write_lines("signals_excerpt.csv", lines)


def segment_rows(beats, annotations, peaks, sample_count, params):
    """Per-segment TP/FP/FN, noise-peak counts, beats and RR values."""
    samples_per_segment = params["segment_ms"] // 5
    count = (sample_count + samples_per_segment - 1) // samples_per_segment
    segments = []
    for index in range(count):
        start = index * samples_per_segment
        stop = min((index + 1) * samples_per_segment, sample_count)
        refs = [ref for ref in annotations if start <= ref["sample"] < stop]
        detected = [beat for beat in beats if start <= beat["sample"] < stop]
        matching = sum(ref["beat"] is not None for ref in refs)
        false_positive = sum(beat["annotation"] is None for beat in detected)
        noise_peaks = sum(
            peak["class"] == "noise" and start <= peak["time"] < stop
            for peak in peaks
        )
        rr_values = [beat["rr"] for beat in detected if beat["rr"] is not None]
        segments.append({
            "number": index, "start_ms": 5 * start, "end_ms": 5 * stop,
            "refs": len(refs), "tp": matching, "fp": false_positive,
            "fn": len(refs) - matching, "noise_peaks": noise_peaks,
            "beats": len(detected), "rr_values": rr_values,
        })
    return segments


def classification_confusion(beats, annotations):
    counts = Counter()
    for ref in annotations:
        if ref["beat"] is not None:
            counts[(ref["label"], ref["beat"]["label"])] += 1
        else:
            counts[(ref["label"], "miss")] += 1
    for beat in beats:
        if beat["annotation"] is None:
            counts[("extra", beat["label"])] += 1
    return counts


def matching_errors(beats, annotations):
    events = []
    for beat in beats:
        if beat["annotation"] is None:
            events.append((
                beat["sample"], 0,
                f"false_positive beat={beat['number']} "
                f"sample={beat['sample']} time_ms={5 * beat['sample']} "
                f"label={beat['label']}",
            ))
    for ref in annotations:
        if ref["beat"] is None:
            events.append((
                ref["sample"], 1,
                f"false_negative sample={ref['sample']} "
                f"time_ms={5 * ref['sample']} label={ref['label']}",
            ))
    events.sort(key=lambda item: (item[0], item[1]))
    return [line for _, _, line in events]


def performance_lines(beats, annotations, peaks, detection, params, segments, count):
    """Detector levels, classifier confusion, metrics and segment performance."""
    classes = Counter(peak["class"] for peak in peaks)
    reference_types = Counter(ref["label"] for ref in annotations)
    detected_types = Counter(beat["label"] for beat in beats)
    true_positive = sum(ref["beat"] is not None for ref in annotations)
    false_negative = len(annotations) - true_positive
    false_positive = sum(beat["annotation"] is None for beat in beats)
    initial = detection["initial"]
    final = detection["final"]
    threshold = detection["thresholds"]

    lines = [
        "DETECTOR",
        f"samples {count}",
        f"duration_ms {5 * count}",
        f"peaks {len(peaks)} " + " ".join(
            f"{kind}={classes[kind]}" for kind in PEAK_CLASSES
        ),
        "initial_levels " + " ".join(f"{key}={initial[key]}" for key in initial),
        "final_levels " + " ".join(f"{key}={final[key]}" for key in final),
        f"final_thresholds thr_i={threshold['thi1']} thr_f={threshold['thf1']}",
        f"final_rr_averages rravg1_ms={5 * detection['ra1']} "
        f"rravg2_ms={5 * detection['ra2']}",
        "MATCHING",
        f"tolerance_ms {params['match_ms']}",
        f"references {len(annotations)} " + " ".join(
            f"{label}={reference_types[label]}" for label in LABELS
        ),
        f"detections {len(beats)} " + " ".join(
            f"{label}={detected_types[label]}" for label in LABELS
        ),
        f"true_positives {true_positive}",
        f"false_positives {false_positive}",
        f"false_negatives {false_negative}",
        "sensitivity " + ratio(true_positive, true_positive + false_negative),
        "positive_predictivity " + ratio(true_positive, true_positive + false_positive),
        "detection_error_rate " + ratio(
            false_positive + false_negative, len(annotations)
        ),
    ]
    method_stats = []
    for method in ("threshold", "searchback"):
        selected = [beat for beat in beats if beat["method"] == method]
        method_stats.append(
            f"{method}={sum(beat['annotation'] is not None for beat in selected)}"
            f"/{len(selected)}"
        )
    lines.append("by_method " + " ".join(method_stats))
    offsets = [beat["offset"] for beat in beats if beat["offset"] is not None]
    if offsets:
        lines.append(
            f"offset_ms mean={two(rdiv(100 * sum(offsets), len(offsets)))} "
            f"mean_abs={two(rdiv(100 * sum(abs(v) for v in offsets), len(offsets)))} "
            f"max_abs={max(abs(v) for v in offsets)}"
        )
    else:
        lines.append("offset_ms none")

    confusion = classification_confusion(beats, annotations)
    lines.append("CONFUSION")
    lines.append("ref  " + "".join(f"{label:>6}" for label in LABELS) + "  miss")
    for reference_label in LABELS:
        lines.append(
            reference_label + "    " +
            "".join(f"{confusion[(reference_label, label)]:>6}" for label in LABELS) +
            f"{confusion[(reference_label, 'miss')]:>6}"
        )
    lines.append(
        "extra" + "".join(f"{confusion[('extra', label)]:>6}" for label in LABELS)
    )
    for label, prefix in (("V", "veb"), ("A", "sveb")):
        correct = confusion[(label, label)]
        lines.append(
            f"{prefix}_sensitivity " + ratio(correct, reference_types[label])
        )
        lines.append(
            f"{prefix}_positive_predictivity " + ratio(correct, detected_types[label])
        )
    lines.append(
        f"SEGMENTS segment_ms={params['segment_ms']} segments={len(segments)}"
    )
    for part in segments:
        lines.append(
            f"{part['start_ms']:>6}-{part['end_ms']:>6} "
            f"refs={part['refs']} tp={part['tp']} fp={part['fp']} "
            f"fn={part['fn']} noise_peaks={part['noise_peaks']}"
        )
    lines.append(f"ERRORS count={false_positive + false_negative}")
    lines.extend(matching_errors(beats, annotations))
    return lines


def premature_beat_details(beats):
    """Compute premature percent and post-ectopic compensatory pauses."""
    result = []
    for beat in beats:
        if beat["label"] not in ("V", "A"):
            continue
        k = beat["number"]
        preceding_sum = sum(beats[j - 1]["rr"] for j in range(k - 8, k))
        next_rr = beats[k]["rr"] if k < len(beats) else None
        if next_rr is None:
            compensation = "-"
        else:
            total = beat["rr"] + next_rr
            if 10 * abs(4 * total - preceding_sum) <= preceding_sum:
                compensation = "full"
            elif 4 * total < preceding_sum:
                compensation = "partial"
            else:
                compensation = "long"
        result.append({
            "beat": beat, "next_rr": next_rr,
            "mean": rdiv(100 * preceding_sum, 8),
            "prematurity": rdiv(80000 * beat["rr"], preceding_sum),
            "compensation": compensation,
        })
    return result


def premature_runs(beats):
    """Find separate maximal runs for both premature beat labels."""
    result = []
    for label in ("V", "A"):
        indices = [beat["number"] for beat in beats if beat["label"] == label]
        for first, last in consecutive_ranges(indices):
            length = last - first + 1
            kind = "isolated" if length == 1 else "couplet" if length == 2 else "run"
            result.append({
                "label": label, "first": first, "last": last,
                "length": length, "kind": kind,
                "start_ms": 5 * beats[first - 1]["sample"],
            })
    result.sort(key=lambda event: event["first"])
    return result


def arrhythmia_events(beats, params):
    """Enumerate pauses, brady/tachy ranges and V/N alternation sequences."""
    events = []
    for beat in beats[1:]:
        if beat["rr"] > params["pause_ms"]:
            events.append({
                "kind": "pause",
                "first": beat["number"] - 1,
                "last": beat["number"],
                "rr": beat["rr"],
                "start_ms": 5 * beats[beat["number"] - 2]["sample"],
            })
    for kind, threshold in (("bradycardia", params["brady_ms"]),
                            ("tachycardia", params["tachy_ms"])):
        selected = [
            beat["number"] for beat in beats[1:]
            if (beat["rr"] > threshold if kind == "bradycardia"
                else beat["rr"] < threshold)
        ]
        for first, last in consecutive_ranges(selected):
            if last - first + 1 < 3:
                continue
            intervals = [beats[k - 1]["rr"] for k in range(first, last + 1)]
            events.append({
                "kind": kind, "first": first - 1, "last": last,
                "intervals": len(intervals),
                "mean_hr": rdiv(6000000 * len(intervals), sum(intervals)),
                "start_ms": 5 * beats[first - 2]["sample"],
            })
    v_beats = [beat["number"] for beat in beats if beat["label"] == "V"]
    labels = {beat["number"]: beat["label"] for beat in beats}
    for kind, span in (("bigeminy", 2), ("trigeminy", 3)):
        for chain in linked_sequences(v_beats, span, labels):
            if len(chain) < 3:
                continue
            events.append({
                "kind": kind, "first": chain[0], "last": chain[-1],
                "cycles": len(chain),
                "start_ms": 5 * beats[chain[0] - 1]["sample"],
            })
    order = {"pause": 0, "bradycardia": 1, "tachycardia": 2,
             "bigeminy": 3, "trigeminy": 4}
    events.sort(key=lambda event: (order[event["kind"]], event["first"]))
    return events


def event_line(event):
    kind = event["kind"]
    if kind == "pause":
        return (
            f"pause beats={event['first']}-{event['last']} "
            f"rr_ms={event['rr']} start_ms={event['start_ms']}"
        )
    if kind in ("bradycardia", "tachycardia"):
        return (
            f"{kind} beats={event['first']}-{event['last']} "
            f"intervals={event['intervals']} mean_hr={two(event['mean_hr'])} "
            f"start_ms={event['start_ms']}"
        )
    return (
        f"{kind} beats={event['first']}-{event['last']} "
        f"cycles={event['cycles']} start_ms={event['start_ms']}"
    )


def hrv_lines(beats, segments, params):
    """All RR/NN integer statistics, ectopy, rhythm patterns and trends."""
    rr = rr_statistics(beats)
    nn = nn_statistics(beats)
    lines = [
        "RR", f"beats {len(beats)}",
        f"intervals {rr['count']}",
        f"mean_rr_ms {maybe_two(rr['mean_rr'])}",
    ]
    if rr["shortest"] is None:
        lines.extend([
            "min_rr_ms none", "max_rr_ms none", "mean_hr_bpm none",
        ])
    else:
        shortest_number, shortest_value = rr["shortest"]
        longest_number, longest_value = rr["longest"]
        lines.extend([
            f"min_rr_ms {shortest_value} beat={shortest_number}",
            f"max_rr_ms {longest_value} beat={longest_number}",
            f"mean_hr_bpm {two(rr['mean_hr'])}",
        ])
    lines.extend([
        "NN", f"intervals {nn['e']}",
        f"mean_nn_ms {maybe_two(nn['mean_nn'])}",
        f"sdnn_ms {maybe_two(nn['sdnn'])}",
        f"differences {nn['k']}",
        f"rmssd_ms {maybe_two(nn['rmssd'])}",
        f"sdsd_ms {maybe_two(nn['sdsd'])}",
        f"nn50 {nn['nn50']}",
        f"pnn50 {two(nn['pnn50'])}%" if nn["pnn50"] is not None else "pnn50 none",
        f"sd1_ms {maybe_two(nn['sd1'])}",
        f"sd2_ms {maybe_two(nn['sd2'])}",
        f"HISTOGRAM bin_ms=7.8125 bins={len(nn['histogram'])} "
        f"max={nn['histogram_max']}",
    ])
    for bin_number in sorted(nn["histogram"]):
        count = nn["histogram"][bin_number]
        lines.append(
            f"{four(78125 * bin_number):>10} "
            f"{four(78125 * (bin_number + 1)):>10} "
            f"{count:>3} |" + "#" * count
        )
    if nn["e"] == 0:
        lines.append("triangular_index none")
    else:
        lines.append(
            f"triangular_index {fraction(nn['e'], nn['histogram_max'])} "
            f"{two(nn['triangular_index'])}"
        )

    premature = premature_beat_details(beats)
    counts = Counter(item["beat"]["label"] for item in premature)
    lines.append(
        f"PREMATURE count={len(premature)} V={counts['V']} A={counts['A']}"
    )
    for item in premature:
        beat = item["beat"]
        reference = beat["annotation"]
        lines.append(
            f"beat={beat['number']} sample={beat['sample']} "
            f"label={beat['label']} rr_ms={beat['rr']} "
            f"next_rr_ms={item['next_rr'] if item['next_rr'] is not None else '-'} "
            f"mean_ms={two(item['mean'])} "
            f"prematurity={two(item['prematurity'])}% "
            f"compensation={item['compensation']} width_ms={beat['width']} "
            f"ref={reference['label'] if reference else '-'}"
        )
    runs = premature_runs(beats)
    lines.append(f"RUNS count={len(runs)}")
    for run in runs:
        lines.append(
            f"{run['label']} {run['kind']} "
            f"beats={run['first']}-{run['last']} "
            f"length={run['length']} start_ms={run['start_ms']}"
        )

    events = arrhythmia_events(beats, params)
    lines.append(f"EVENTS count={len(events)}")
    lines.extend(event_line(event) for event in events)

    lines.append(
        f"TREND segment_ms={params['segment_ms']} segments={len(segments)}"
    )
    for segment in segments:
        start, end = segment["start_ms"], segment["end_ms"]
        intervals = segment["rr_values"]
        header = f"{start:>6}-{end:>6} beats={segment['beats']} "
        if not intervals:
            lines.append(header + "mean_hr=none min_hr=none max_hr=none |")
            continue
        mean_hr = rdiv(6000000 * len(intervals), sum(intervals))
        minimum_hr = rdiv(6000000, max(intervals))
        maximum_hr = rdiv(6000000, min(intervals))
        lines.append(
            header + f"mean_hr={two(mean_hr)} min_hr={two(minimum_hr)} "
            f"max_hr={two(maximum_hr)} |" + "#" * rdiv(mean_hr, 500)
        )
    return lines


def draw_axis(columns, marker):
    return "       +" + "".join(
        "+" if marker(index) else "-" for index in range(columns)
    ) + "+"


def draw_labels(heading, markers):
    """Zero-based character positions are eight plus the column number."""
    buffer = list(f"{heading:>6}  ")
    for column, value in markers:
        position = 8 + column
        if len(buffer) < position:
            buffer.extend(" " * (position - len(buffer)))
        for character in value:
            if len(buffer) <= position:
                buffer.append(character)
            else:
                buffer[position] = character
            position += 1
    return "".join(buffer).rstrip()


def waveform_chart(upper, lower, height):
    """Render the benchmark's vertical min/max per-column waveform bars."""
    top = max(upper)
    bottom = min(lower)
    zero = scale(0, top, bottom, height) if bottom <= 0 <= top else None
    lines = []
    for row in range(height):
        if row == 0:
            label = str(top)
        elif row == height - 1:
            label = str(bottom)
        elif row == zero:
            label = "0"
        else:
            label = ""
        cells = []
        for hi, lo in zip(upper, lower):
            if scale(hi, top, bottom, height) <= row <= scale(lo, top, bottom, height):
                cells.append("#")
            elif row == zero:
                cells.append("-")
            else:
                cells.append(" ")
        lines.append(f"{label:>6} |{''.join(cells)}|")
    return lines


def tachogram_chart(beats, height):
    intervals = [beat["rr"] for beat in beats[1:]]
    if not intervals:
        return ["TACHOGRAM intervals=0", "POINCARE points=0"]
    smallest, greatest = min(intervals), max(intervals)
    lines = [
        f"TACHOGRAM intervals={len(intervals)} "
        f"min_ms={smallest} max_ms={greatest} rows={height}"
    ]
    for row in range(height):
        label = str(greatest) if row == 0 else (
            str(smallest) if row == height - 1 else ""
        )
        cells = [
            "*" if scale(value, greatest, smallest, height) == row else " "
            for value in intervals
        ]
        lines.append(f"{label:>6} |{''.join(cells)}|")
    lines.append(draw_axis(len(intervals), lambda j: (j + 2) % 10 == 0))
    lines.append(draw_labels(
        "beat", [
            (j, str(j + 2)) for j in range(len(intervals))
            if (j + 2) % 10 == 0
        ],
    ))
    lines.append(" label |" + "".join(beat["label"] for beat in beats[1:]) + "|")
    return lines


def poincare_chart(beats, size):
    intervals = [beat["rr"] for beat in beats[1:]]
    if not intervals:
        return []
    low, high = min(intervals), max(intervals)
    points = Counter()
    for left, right in zip(intervals, intervals[1:]):
        column = rdiv((left - low) * (size - 1), high - low) if high > low else 0
        row = scale(right, high, low, size)
        points[(row, column)] += 1
    result = [
        f"POINCARE points={len(intervals) - 1} "
        f"size={size} min_ms={low} max_ms={high}"
    ]
    for row in range(size):
        label = str(high) if row == 0 else str(low) if row == size - 1 else ""
        cells = []
        for column in range(size):
            count = points[(row, column)]
            cells.append("." if count == 0 else str(count) if count <= 9 else "#")
        result.append(f"{label:>6} |{''.join(cells)}|")
    result.append(draw_axis(size, lambda _: False))
    text = " " * 8 + str(low)
    high_start = 8 + size - len(str(high))
    result.append(text + " " * max(0, high_start - len(text)) + str(high))
    return result


def average_template(samples, beats, label, height):
    """Baseline-correct beat-aligned average waveform using integer rdiv."""
    n = len(samples)
    chosen = [
        beat for beat in beats
        if beat["label"] == label and 60 <= beat["sample"] <= n - 100
    ]
    count = len(chosen)
    if not count:
        return [f"TEMPLATE {label} beats=0"]
    baseline = [
        sum(samples[beat["sample"] - 60:beat["sample"] - 50])
        for beat in chosen
    ]
    averaged = []
    for offset in range(-60, 100):
        total = sum(
            10 * samples[beat["sample"] + offset] - baseline[index]
            for index, beat in enumerate(chosen)
        )
        averaged.append(rdiv(total, 10 * count))
    maximum = max(averaged)
    minimum = min(averaged)
    max_offset = averaged.index(maximum) - 60
    min_offset = averaged.index(minimum) - 60
    result = [
        f"TEMPLATE {label} beats={count} max_uv={maximum} "
        f"max_ms={5 * max_offset} min_uv={minimum} "
        f"min_ms={5 * min_offset} rows={height}",
    ]
    upper = [max(averaged[2 * i], averaged[2 * i + 1]) for i in range(80)]
    lower = [min(averaged[2 * i], averaged[2 * i + 1]) for i in range(80)]
    result.extend(waveform_chart(upper, lower, height))
    result.append(draw_axis(80, lambda i: i % 10 == 0))
    result.append(draw_labels(
        "ms", [(i, str(10 * i - 300)) for i in range(0, 80, 10)]
    ))
    return result


def chart_lines(samples, beats, params):
    """Tachogram, consecutive RR scattergram and N/V/A averaged waveforms."""
    lines = tachogram_chart(beats, params["chart_rows"])
    lines.extend(poincare_chart(beats, params["poincare_size"]))
    for label in LABELS:
        lines.extend(average_template(samples, beats, label, params["chart_rows"]))
    return lines


def rhythm_strip_lines(samples, beats, annotations, params):
    """Ten-sample min/max envelopes with beat/reference labels per column."""
    start = params["strip_start_ms"] // 5
    count = params["strip_ms"] // 5
    columns = count // 10
    height = params["strip_rows"]
    end = start + count
    excerpt = samples[start:end]
    upper = [
        max(excerpt[10 * col:10 * col + 10]) for col in range(columns)
    ]
    lower = [
        min(excerpt[10 * col:10 * col + 10]) for col in range(columns)
    ]
    lines = [
        f"RHYTHM start_ms={params['strip_start_ms']} "
        f"end_ms={params['strip_start_ms'] + params['strip_ms']} "
        f"columns={columns} rows={height} "
        f"max_uv={max(excerpt)} min_uv={min(excerpt)}",
    ]
    lines.extend(waveform_chart(upper, lower, height))
    lines.append(draw_axis(columns, lambda col: col % 20 == 0))
    lines.append(draw_labels(
        "s", [
            (col, str((params["strip_start_ms"] + 50 * col) // 1000))
            for col in range(0, columns, 20)
        ]
    ))
    beat_markers = [" "] * columns
    ref_markers = [" "] * columns
    for beat in beats:
        if start <= beat["sample"] < end:
            beat_markers[(beat["sample"] - start) // 10] = beat["label"]
    for ref in annotations:
        if start <= ref["sample"] < end:
            ref_markers[(ref["sample"] - start) // 10] = ref["label"]
    lines.append(" beats |" + "".join(beat_markers) + "|")
    lines.append("  refs |" + "".join(ref_markers) + "|")
    return lines


def main():
    """Perform the complete deterministic benchmark and create all eight outputs."""
    samples = read_ecg()
    annotations = read_annotations()
    params = read_params()
    signals = filter_ecg(samples)
    peaks = find_peaks(signals)
    detection = detect_beats(peaks, signals, params)
    beats = build_beat_list(detection["registered"], signals["bandpass"], params)
    match_annotations(beats, annotations, params)
    segments = segment_rows(beats, annotations, peaks, len(samples), params)

    write_beats(beats)
    write_peaks(peaks)
    write_matching(beats, annotations)
    write_signal_excerpt(samples, signals, params)
    write_lines(
        "performance.txt",
        performance_lines(
            beats, annotations, peaks, detection, params, segments, len(samples)
        ),
    )
    write_lines("hrv.txt", hrv_lines(beats, segments, params))
    write_lines("charts.txt", chart_lines(samples, beats, params))
    write_lines(
        "rhythm_strip.txt",
        rhythm_strip_lines(samples, beats, annotations, params),
    )


if __name__ == "__main__":
    main()
