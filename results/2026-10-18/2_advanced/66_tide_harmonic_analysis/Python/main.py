"""Hourly tide-gauge harmonic analysis and multi-station reporting.

Run as python3 Python/main.py from the task directory.
The program reads input/ and writes its five text/CSV files under output/.
"""

import math
from datetime import timedelta

from cleaning import detect_spikes, prepare_record
from harmonic_fit import PI, fit, select_constituents
from predict import find_extrema, label_extrema, predict_height, predict_hours
from records import (
    date_at_hour, datetime_at_hour, datetime_at_minute, epoch_hours,
    noon_hour, read_all_inputs,
)
from report import decimal, optional, render_plot, write_lines


DOODSON_WEIGHTS = (0, 2, 1, 1, 2, 0, 1, 1, 0, 2,
                   0, 1, 1, 0, 1, 0, 0, 1, 0, 1)
FOUR_LEADING_CONSTITUENTS = ("M2", "S2", "K1", "O1")


def average(values):
    return sum(values) / len(values)


def mean_square(values):
    return sum(value * value for value in values) / len(values)


def rms(values):
    return math.sqrt(mean_square(values))


def residual_statistics(observed, usable, model):
    """Fit residual diagnostics from the usable observation hours."""
    residuals = {
        hour: observed[hour] - predict_height(model, hour)
        for hour in usable
    }
    n = len(usable)
    dimension = model["unknowns"]
    squared = sum(residuals[hour] * residuals[hour] for hour in usable)
    degrees = n - dimension
    residual_variance = squared / degrees
    observed_mean = average([observed[hour] for hour in usable])
    total_variation = sum(
        (observed[hour] - observed_mean) ** 2 for hour in usable
    )
    paired_hours = [hour for hour in usable if hour + 1 in residuals]
    lag_numerator = sum(
        residuals[hour] * residuals[hour + 1] for hour in paired_hours
    )
    lag_denominator = sum(
        residuals[hour] ** 2 for hour in paired_hours
    )
    return {
        "residuals": residuals,
        "squared": squared,
        "variance": residual_variance,
        "dof": degrees,
        "rms": math.sqrt(squared / n),
        "max_abs": max(abs(v) for v in residuals.values()),
        "explained_percent": 100 * (1 - squared / total_variation),
        "lag1": lag_numerator / lag_denominator,
    }


def constituent_errors(model, residual_variance, minimum_snr):
    """Amplitude/phase standard errors from the inverse normal matrix."""
    inverse = model["inverse"]
    results = {}
    for name, constant in model["constants"].items():
        a, b = constant["a"], constant["b"]
        amplitude = constant["amplitude"]
        ia, ib = constant["index_a"], constant["index_b"]
        va = residual_variance * inverse[ia][ia]
        vb = residual_variance * inverse[ib][ib]
        cab = residual_variance * inverse[ia][ib]
        amplitude_error = math.sqrt(
            a * a * va + b * b * vb + 2 * a * b * cab
        ) / amplitude
        phase_error = (
            math.sqrt(b * b * va + a * a * vb - 2 * a * b * cab)
            / (amplitude * amplitude) * 180 / PI
        )
        snr = (amplitude / amplitude_error) ** 2
        results[name] = {
            "amplitude_error": amplitude_error,
            "phase_error": phase_error,
            "snr": snr,
            "significant": "yes" if snr >= minimum_snr else "no",
        }
    return results


def largest_residuals(residuals, limit):
    ordered = sorted(residuals, key=lambda t: (-abs(residuals[t]), t))
    return ordered[:limit]


def cross_validate(observed, usable, first, last, constituents, rayleigh,
                   final_residuals):
    """Hold out the latter half of the record and assess model skill."""
    midpoint = first + (last - first) // 2
    training = [t for t in usable if t <= midpoint]
    testing = [t for t in usable if t > midpoint]
    selected, _ = select_constituents(
        constituents, training[-1] - training[0], rayleigh
    )
    validation_model = fit(observed, training, selected)
    errors = [
        observed[t] - predict_height(validation_model, t) for t in testing
    ]
    test_squared = sum(error * error for error in errors)
    test_mean = average([observed[t] for t in testing])
    test_variation = sum(
        (observed[t] - test_mean) ** 2 for t in testing
    )
    in_sample_squared = sum(final_residuals[t] ** 2 for t in testing)
    return {
        "midpoint": midpoint,
        "training_count": len(training),
        "testing_count": len(testing),
        "constituents": len(selected),
        "rms": math.sqrt(test_squared / len(testing)),
        "in_sample_rms": math.sqrt(in_sample_squared / len(testing)),
        "skill": 1 - test_squared / test_variation,
    }


def residual_events(usable, residuals, threshold, minimum_hours):
    """Group consecutive positive and negative threshold exceedances."""
    events = []
    current = []
    current_sign = None

    def flush():
        if len(current) < minimum_hours:
            return
        if current_sign == "positive":
            peak = max(current, key=lambda t: (residuals[t], -t))
        else:
            peak = min(current, key=lambda t: (residuals[t], t))
        events.append({
            "kind": current_sign,
            "start": current[0],
            "end": current[-1],
            "peak": peak,
            "value": residuals[peak],
        })

    for t in usable:
        value = residuals[t]
        sign = ("positive" if value > threshold else
                "negative" if value < -threshold else None)
        consecutive = bool(current) and t == current[-1] + 1
        if sign is not None and sign == current_sign and consecutive:
            current.append(t)
        else:
            flush()
            current = [t] if sign is not None else []
            current_sign = sign
    flush()
    return events


def daily_means(cleaning, model, epoch):
    """Doodson X0 39-point weighted averages centered on each day's noon."""
    first, last = cleaning["first"], cleaning["last"]
    usable = set(cleaning["usable"])
    observed = cleaning["values"]
    start_date = date_at_hour(epoch, first)
    stop_date = date_at_hour(epoch, last)
    current_date = start_date
    results = []
    while current_date <= stop_date:
        noon = noon_hour(epoch, current_date)
        if noon - 19 >= first and noon + 19 <= last:
            weighted = 0.0
            missing = 0
            for offset in range(-19, 20):
                time = noon + offset
                if time in usable:
                    value = observed[time]
                else:
                    value = predict_height(model, time)
                    missing += 1
                weighted += DOODSON_WEIGHTS[abs(offset)] * value
            results.append({
                "date": current_date,
                "level": weighted / 30,
                "filled": missing,
            })
        current_date += timedelta(days=1)
    heights = [entry["level"] for entry in results]
    mean_height = average(heights)
    mean_day = (len(results) - 1) / 2
    numerator = sum(
        (i - mean_day) * (height - mean_height)
        for i, height in enumerate(heights)
    )
    denominator = sum(
        (i - mean_day) ** 2 for i in range(len(results))
    )
    highest = max(results, key=lambda row: (row["level"], -row["date"].toordinal()))
    lowest = min(results, key=lambda row: (row["level"], row["date"].toordinal()))
    return {
        "rows": results,
        "days": len(results),
        "average": mean_height,
        "slope_mm_per_day": 1000 * numerator / denominator,
        "max": highest,
        "min": lowest,
    }


def daily_extrema(extrema, start_date, days):
    """Daily high/low counts and extreme tidal ranges for the prediction window."""
    table = []
    for offset in range(days):
        day = start_date + timedelta(days=offset)
        highs = [e for e in extrema if e["date"] == day and e["kind"] == "high"]
        lows = [e for e in extrema if e["date"] == day and e["kind"] == "low"]
        hhw = max((e["height"] for e in highs), default=None)
        llw = min((e["height"] for e in lows), default=None)
        span = None if hhw is None or llw is None else hhw - llw
        table.append({
            "date": day, "high_waters": len(highs), "low_waters": len(lows),
            "hhw": hhw, "llw": llw, "range": span,
        })
    return table


def tidal_classification(form_number):
    if form_number < 0.25:
        return "semidiurnal"
    if form_number < 1.5:
        return "mixed_semidiurnal"
    if form_number < 3.0:
        return "mixed_diurnal"
    return "diurnal"


def calculate_datums(extrema, day_table):
    """Compute HHW/LLW datums and the tidal range from refined extrema."""
    highs = [entry for entry in extrema if entry["kind"] == "high"]
    lows = [entry for entry in extrema if entry["kind"] == "low"]
    hhw = [entry["hhw"] for entry in day_table if entry["hhw"] is not None]
    llw = [entry["llw"] for entry in day_table if entry["llw"] is not None]
    mhhw = average(hhw)
    mllw = average(llw)
    mhw = average([entry["height"] for entry in highs])
    mlw = average([entry["height"] for entry in lows])
    return {
        "mhhw": mhhw, "mllw": mllw, "mhw": mhw, "mlw": mlw,
        "mtl": (mhw + mlw) / 2,
        "dtl": (mhhw + mllw) / 2,
        "mn": mhw - mlw,
        "gt": mhhw - mllw,
        "highs": highs, "lows": lows,
    }


def calculate_asymmetry(extrema, constant_by_name):
    """Flood/ebb duration and the M4-to-M2 overtide phase relationship."""
    rises = []
    falls = []
    for previous, current in zip(extrema, extrema[1:]):
        elapsed = current["rounded"] - previous["rounded"]
        if previous["kind"] == "low" and current["kind"] == "high":
            rises.append(elapsed)
        if previous["kind"] == "high" and current["kind"] == "low":
            falls.append(elapsed)
    m2 = constant_by_name["M2"]
    m4 = constant_by_name["M4"]
    phase = (2 * m2["phase"] - m4["phase"]) % 360
    return {
        "rise_minutes": average(rises),
        "fall_minutes": average(falls),
        "m4_m2_ratio": m4["amplitude"] / m2["amplitude"],
        "relative_phase": phase,
        "dominance": "flood" if phase < 180 else "ebb",
    }


def spring_neap_events(constants, prediction_hour, prediction_length):
    """Enumerate all tidal-beat extrema within the requested forecast interval."""
    m2 = constants["M2"]
    s2 = constants["S2"]
    delta_speed = s2["speed"] - m2["speed"]
    delta_phase = s2["phase"] - m2["phase"]
    first_real = (delta_speed * prediction_hour - delta_phase) / 180
    last_real = (
        delta_speed * (prediction_hour + prediction_length) - delta_phase
    ) / 180
    minimum_q = math.ceil(min(first_real, last_real))
    maximum_q = math.floor(max(first_real, last_real))
    results = []
    for q in range(minimum_q, maximum_q + 1):
        hour = (delta_phase + 180 * q) / delta_speed
        if prediction_hour <= hour <= prediction_hour + prediction_length:
            results.append({
                "kind": "spring" if q % 2 == 0 else "neap",
                "minute": math.floor(hour * 60 + 0.5),
            })
    return results


def summarize_characteristics(model, extrema, daily, hourly, prediction_hour,
                              prediction_length):
    """Describe form, datums, extremes, overtides and exceedance."""
    constants = model["constants"]
    form = ((constants["K1"]["amplitude"] + constants["O1"]["amplitude"])
            / (constants["M2"]["amplitude"] + constants["S2"]["amplitude"]))
    datums = calculate_datums(extrema, daily)
    asymmetry = calculate_asymmetry(extrema, constants)
    highest = max(datums["highs"], key=lambda e: (e["height"], -e["rounded"]))
    lowest = min(datums["lows"], key=lambda e: (e["height"], e["rounded"]))
    complete_days = [row for row in daily if row["range"] is not None]
    widest = max(complete_days, key=lambda row: (row["range"],
                                                -row["date"].toordinal()))
    narrowest = min(complete_days, key=lambda row: (row["range"],
                                                   row["date"].toordinal()))
    count = len(hourly)
    amp_sum = sum(constants[row["name"]]["amplitude"]
                  for row in model["selected"])
    return {
        **datums, **asymmetry,
        "form_number": form,
        "type": tidal_classification(form),
        "spring": 2 * (constants["M2"]["amplitude"] + constants["S2"]["amplitude"]),
        "neap": 2 * (constants["M2"]["amplitude"] - constants["S2"]["amplitude"]),
        "hat": model["mean_level"] + amp_sum,
        "lat": model["mean_level"] - amp_sum,
        "highest": highest, "lowest": lowest,
        "widest": widest, "narrowest": narrowest,
        "above_mhhw": 100 * sum(v > datums["mhhw"] for v in hourly) / count,
        "below_mllw": 100 * sum(v < datums["mllw"] for v in hourly) / count,
        "spring_neap": spring_neap_events(constants, prediction_hour,
                                         prediction_length),
    }


def inspect_station(station, observed, constituents, settings, prediction_hour):
    """Run preliminary cleaning, a full fit and every station diagnostic."""
    code = station["code"]
    cleaning = prepare_record(observed, settings["flat_run"])
    values = cleaning["values"]
    selected, statuses = select_constituents(
        constituents, cleaning["length"], settings["rayleigh"]
    )
    preliminary = fit(values, cleaning["candidates"], selected)
    prelim_residuals = {
        t: values[t] - predict_height(preliminary, t)
        for t in cleaning["candidates"]
    }
    cleaning["prefit_rms"] = rms(
        [prelim_residuals[t] for t in cleaning["candidates"]]
    )
    detect_spikes(cleaning, prelim_residuals, settings)
    final_model = fit(values, cleaning["usable"], selected)
    residual = residual_statistics(values, cleaning["usable"], final_model)
    errors = constituent_errors(
        final_model, residual["variance"], settings["snr_min"]
    )
    validation = cross_validate(
        values, cleaning["usable"], cleaning["first"], cleaning["last"],
        constituents, settings["rayleigh"], residual["residuals"],
    )
    surges = residual_events(
        cleaning["usable"], residual["residuals"],
        settings["surge_threshold"], settings["surge_hours"],
    )
    means = daily_means(cleaning, final_model, settings["epoch"])
    length = settings["prediction_hours"]
    hourly = predict_hours(final_model, prediction_hour, length)
    extrema, raw = find_extrema(
        final_model, prediction_hour, length,
        settings["grid_minutes"], settings["min_range"],
    )
    label_extrema(extrema, settings["epoch"])
    days = daily_extrema(extrema, settings["prediction_start"].date(),
                         length // 24)
    characteristics = summarize_characteristics(
        final_model, extrema, days, hourly, prediction_hour, length
    )
    return {
        "code": code, "name": station["name"],
        "cleaning": cleaning, "status": statuses,
        "model": final_model, "residual": residual,
        "errors": errors, "validation": validation,
        "surges": surges, "daily_means": means,
        "hourly": hourly, "extrema": extrema, "raw_extrema": raw,
        "daily": days, "characteristics": characteristics,
    }


def nearest_reference_lag(extrema, reference):
    """Measure each extrema time against the nearest reference of its kind."""
    offsets = []
    for item in extrema:
        closest = min(reference, key=lambda ref: (
            abs(ref["rounded"] - item["rounded"]), ref["rounded"]
        ))
        offsets.append(item["rounded"] - closest["rounded"])
    return average(offsets)


def compare_stations(stations, settings):
    """Forecast extrema lags, tidal ranges and harmonic phase relationships."""
    reference = stations[settings["reference"]]
    reference_char = reference["characteristics"]
    comparisons = []
    for code, station in stations.items():
        if code == settings["reference"]:
            continue
        own = station["characteristics"]
        ref_high = reference_char["highs"]
        ref_low = reference_char["lows"]
        comparison = {
            "code": code,
            "hw_lag_min": nearest_reference_lag(own["highs"], ref_high),
            "lw_lag_min": nearest_reference_lag(own["lows"], ref_low),
            "range_ratio": own["gt"] / reference_char["gt"],
            "mtl_diff": own["mtl"] - reference_char["mtl"],
            "constituents": [],
        }
        for name in FOUR_LEADING_CONSTITUENTS:
            current = station["model"]["constants"][name]
            reference_constant = reference["model"]["constants"][name]
            phase_difference = current["phase"] - reference_constant["phase"]
            if phase_difference > 180:
                phase_difference -= 360
            if phase_difference <= -180:
                phase_difference += 360
            comparison["constituents"].append({
                "name": name,
                "amplitude_ratio": (current["amplitude"]
                                    / reference_constant["amplitude"]),
                "phase_diff": phase_difference,
                "time_lag_min": phase_difference / current["speed"] * 60,
            })
        comparisons.append(comparison)
    return comparisons


def correlation_at_lag(residual_a, residual_b, usable_a, lag):
    """Pearson correlation of overlapping usable residuals at the given lag."""
    pairs = [
        (residual_a[t], residual_b[t + lag])
        for t in usable_a if t + lag in residual_b
    ]
    count = len(pairs)
    mean_x = average([p[0] for p in pairs])
    mean_y = average([p[1] for p in pairs])
    covariance = sum(
        (x - mean_x) * (y - mean_y) for x, y in pairs
    )
    variance_x = sum((x - mean_x) ** 2 for x, _ in pairs)
    variance_y = sum((y - mean_y) ** 2 for _, y in pairs)
    return covariance / math.sqrt(variance_x * variance_y), count


def cross_station_correlations(stations, station_order, max_lag):
    results = []
    for first_index in range(len(station_order)):
        first_code = station_order[first_index]
        first = stations[first_code]
        for second_code in station_order[first_index + 1:]:
            second = stations[second_code]
            by_lag = {}
            for lag in range(-max_lag, max_lag + 1):
                by_lag[lag] = correlation_at_lag(
                    first["residual"]["residuals"],
                    second["residual"]["residuals"],
                    first["cleaning"]["usable"],
                    lag,
                )
            best_lag = max(
                by_lag, key=lambda lag: (by_lag[lag][0], -abs(lag), -lag)
            )
            results.append({
                "first": first_code, "second": second_code,
                "lag_zero": by_lag[0][0], "lag": best_lag,
                "best": by_lag[best_lag][0], "pairs": by_lag[best_lag][1],
            })
    return results


def create_cleaning_lines(stations, order, settings):
    """Report every excluded hour and the tests used to exclude it."""
    result = []
    epoch = settings["epoch"]
    stamp = lambda hour: datetime_at_hour(epoch, hour)
    for code in order:
        station = stations[code]
        cleaning = station["cleaning"]
        reasons = cleaning["reasons"]
        first = cleaning["first"]
        last = cleaning["last"]
        result.append(f"station={code} name={station['name']}")
        result.append(
            f"span start={stamp(first)} end={stamp(last)} "
            f"hours={last - first + 1} record_length={cleaning['length']}"
        )
        result.append(
            f"counts rows={cleaning['rows']} "
            f"numeric={len(cleaning['numeric_times'])} "
            f"na={sum(reason == 'na' for reason in reasons.values())} "
            f"absent={sum(reason == 'absent' for reason in reasons.values())} "
            f"flat={sum(reason == 'flat' for reason in reasons.values())} "
            f"spikes={len(cleaning['spikes'])} "
            f"usable={len(cleaning['usable'])}"
        )
        for flat in cleaning["flat_runs"]:
            result.append(
                f"flat start={stamp(flat['start'])} "
                f"end={stamp(flat['end'])} "
                f"value={decimal(flat['value'], 3)} "
                f"removed={flat['end'] - flat['start']}"
            )
        result.append(
            f"spike_test window={settings['spike_window']} "
            f"candidates={len(cleaning['candidates'])} "
            f"tested={cleaning['tested']} "
            f"prefit_rms={decimal(cleaning['prefit_rms'], 4)}"
        )
        for spike in cleaning["spikes"]:
            result.append(
                f"spike time={stamp(spike['time'])} "
                f"value={decimal(spike['value'], 3)} "
                f"residual={decimal(spike['residual'], 4)} "
                f"median={decimal(spike['median'], 4)} "
                f"mad={decimal(spike['mad'], 4)} "
                f"limit={decimal(spike['limit'], 4)}"
            )
        for gap in cleaning["gaps"]:
            result.append(
                f"gap start={stamp(gap['start'])} "
                f"end={stamp(gap['end'])} "
                f"hours={gap['end'] - gap['start'] + 1} "
                f"cause={gap['cause']}"
            )
    return result


def create_constituent_lines(stations, order, constituents):
    """One CSV row for every station and constituent, fitted or rejected."""
    result = [
        "station,constituent,speed,status,amplitude,phase,"
        "amplitude_error,phase_error,snr,significant"
    ]
    for code in order:
        station = stations[code]
        for constituent in constituents:
            name = constituent["name"]
            speed = decimal(constituent["speed"], 7)
            status = station["status"][name]
            if status != "fitted":
                result.append(f"{code},{name},{speed},{status},,,,,,")
                continue
            constant = station["model"]["constants"][name]
            error = station["errors"][name]
            result.append(",".join([
                code, name, speed, "fitted",
                decimal(constant["amplitude"], 4),
                decimal(constant["phase"], 2),
                decimal(error["amplitude_error"], 4),
                decimal(error["phase_error"], 2),
                decimal(error["snr"], 1),
                error["significant"],
            ]))
    return result


def create_prediction_lines(stations, order, settings, prediction_hour):
    """Hourly station levels from the start to the end of the forecast."""
    result = ["time," + ",".join(order)]
    epoch = settings["epoch"]
    for offset in range(settings["prediction_hours"] + 1):
        timestamp = datetime_at_hour(epoch, prediction_hour + offset)
        result.append(
            timestamp + "," + ",".join(
                decimal(stations[code]["hourly"][offset], 3)
                for code in order
            )
        )
    return result


def create_extrema_lines(stations, order, settings):
    """Print parabolically refined tidal extrema and one row per forecast date."""
    result = []
    for code in order:
        station = stations[code]
        extrema = station["extrema"]
        raw = station["raw_extrema"]
        result.append(
            f"station={code} extremes={len(extrema)} raw={raw} "
            f"removed={raw - len(extrema)}"
        )
        for i, item in enumerate(extrema):
            change = (
                "none" if i == 0 else
                decimal(item["height"] - extrema[i - 1]["height"], 3)
            )
            result.append(
                f"{datetime_at_minute(settings['epoch'], item['rounded'])} "
                f"{item['label']} {decimal(item['height'], 3)} change={change}"
            )
        for row in station["daily"]:
            result.append(
                f"day date={row['date'].isoformat()} "
                f"high_waters={row['high_waters']} "
                f"low_waters={row['low_waters']} "
                f"hhw={optional(row['hhw'], 3)} "
                f"llw={optional(row['llw'], 3)} "
                f"range={optional(row['range'], 3)}"
            )
    return result


def create_station_summary_header(station, settings):
    """Record, fit, residual and cross-validation summaries for one station."""
    cleaning = station["cleaning"]
    model = station["model"]
    residual = station["residual"]
    epoch = settings["epoch"]
    stamp = lambda hour: datetime_at_hour(epoch, hour)
    result = [
        f"[station {station['code']}] {station['name']}",
        f"record first={stamp(cleaning['first'])} "
        f"last={stamp(cleaning['last'])} "
        f"length={cleaning['length']} usable={len(cleaning['usable'])}",
        f"fit constituents={len(model['selected'])} "
        f"unknowns={model['unknowns']} dof={residual['dof']} "
        f"mean_level={decimal(model['mean_level'], 4)}",
        f"residual rms={decimal(residual['rms'], 4)} "
        f"max_abs={decimal(residual['max_abs'], 4)} "
        f"explained_percent={decimal(residual['explained_percent'], 4)} "
        f"lag1_autocorrelation={decimal(residual['lag1'], 4)}",
    ]
    for rank, time in enumerate(largest_residuals(
            residual["residuals"], settings["top_residuals"]), 1):
        result.append(
            f"top_residual rank={rank} time={stamp(time)} "
            f"observed={decimal(cleaning['values'][time], 3)} "
            f"fitted={decimal(predict_height(model, time), 4)} "
            f"residual={decimal(residual['residuals'][time], 4)}"
        )
    validation = station["validation"]
    result.append(
        f"validation split={stamp(validation['midpoint'])} "
        f"train={validation['training_count']} "
        f"test={validation['testing_count']} "
        f"constituents={validation['constituents']} "
        f"rms={decimal(validation['rms'], 4)} "
        f"in_sample_rms={decimal(validation['in_sample_rms'], 4)} "
        f"skill={decimal(validation['skill'], 4)}"
    )
    return result


def create_characteristics_lines(station, settings):
    """Hydrographic datums, spring/neap predictions and residual surge events."""
    c = station["characteristics"]
    epoch = settings["epoch"]
    minute_stamp = lambda minute: datetime_at_minute(epoch, minute)
    hour_stamp = lambda hour: datetime_at_hour(epoch, hour)
    lines = [
        f"form_number={decimal(c['form_number'], 4)} type={c['type']}",
        f"ranges spring={decimal(c['spring'], 3)} "
        f"neap={decimal(c['neap'], 3)} "
        f"mn={decimal(c['mn'], 3)} gt={decimal(c['gt'], 3)}",
        f"asymmetry rise_minutes={decimal(c['rise_minutes'], 1)} "
        f"fall_minutes={decimal(c['fall_minutes'], 1)} "
        f"m4_m2_ratio={decimal(c['m4_m2_ratio'], 4)} "
        f"relative_phase={decimal(c['relative_phase'], 2)} "
        f"dominance={c['dominance']}",
        f"datums mhhw={decimal(c['mhhw'], 3)} "
        f"mhw={decimal(c['mhw'], 3)} "
        f"mtl={decimal(c['mtl'], 3)} "
        f"dtl={decimal(c['dtl'], 3)} "
        f"mlw={decimal(c['mlw'], 3)} "
        f"mllw={decimal(c['mllw'], 3)}",
        f"bounds hat={decimal(c['hat'], 3)} lat={decimal(c['lat'], 3)}",
        f"window high_waters={len(c['highs'])} low_waters={len(c['lows'])} "
        f"highest={decimal(c['highest']['height'], 3)} "
        f"highest_time={minute_stamp(c['highest']['rounded'])} "
        f"lowest={decimal(c['lowest']['height'], 3)} "
        f"lowest_time={minute_stamp(c['lowest']['rounded'])}",
        f"daily_range widest={decimal(c['widest']['range'], 3)} "
        f"widest_date={c['widest']['date'].isoformat()} "
        f"narrowest={decimal(c['narrowest']['range'], 3)} "
        f"narrowest_date={c['narrowest']['date'].isoformat()}",
        f"exceedance above_mhhw={decimal(c['above_mhhw'], 2)} "
        f"below_mllw={decimal(c['below_mllw'], 2)}",
    ]
    for event in c["spring_neap"]:
        lines.append(f"{event['kind']} time={minute_stamp(event['minute'])}")
    lines.append(
        f"surges count={len(station['surges'])} "
        f"threshold={decimal(settings['surge_threshold'], 3)} "
        f"min_hours={settings['surge_hours']}"
    )
    for surge in station["surges"]:
        lines.append(
            f"surge type={surge['kind']} "
            f"start={hour_stamp(surge['start'])} "
            f"end={hour_stamp(surge['end'])} "
            f"hours={surge['end'] - surge['start'] + 1} "
            f"peak={decimal(surge['value'], 4)} "
            f"peak_time={hour_stamp(surge['peak'])}"
        )
    return lines


def create_daily_mean_lines(station):
    """Print the Doodson daily trend followed by each filtered daily average."""
    daily = station["daily_means"]
    result = [
        f"daily_mean days={daily['days']} "
        f"average={decimal(daily['average'], 4)} "
        f"slope_mm_per_day={decimal(daily['slope_mm_per_day'], 3)} "
        f"max={decimal(daily['max']['level'], 4)} "
        f"max_date={daily['max']['date'].isoformat()} "
        f"min={decimal(daily['min']['level'], 4)} "
        f"min_date={daily['min']['date'].isoformat()}",
    ]
    for row in daily["rows"]:
        result.append(
            f"daily_mean date={row['date'].isoformat()} "
            f"level={decimal(row['level'], 4)} filled={row['filled']}"
        )
    return result


def create_comparison_lines(comparisons, reference):
    """Differences in tidal amplitudes, phases, lags and tidal datums."""
    result = [f"[comparison] reference={reference}"]
    for item in comparisons:
        code = item["code"]
        result.append(
            f"{code} tide "
            f"hw_lag_min={decimal(item['hw_lag_min'], 1)} "
            f"lw_lag_min={decimal(item['lw_lag_min'], 1)} "
            f"range_ratio={decimal(item['range_ratio'], 4)} "
            f"mtl_diff={decimal(item['mtl_diff'], 3)}"
        )
        for constant in item["constituents"]:
            result.append(
                f"{code} {constant['name']} "
                f"amplitude_ratio={decimal(constant['amplitude_ratio'], 4)} "
                f"phase_diff={decimal(constant['phase_diff'], 2)} "
                f"time_lag_min={decimal(constant['time_lag_min'], 1)}"
            )
    return result


def create_correlation_lines(correlations, settings):
    result = [f"[correlation] max_lag={settings['correlation_lag']}"]
    for record in correlations:
        result.append(
            f"{record['first']}-{record['second']} "
            f"lag0={decimal(record['lag_zero'], 4)} "
            f"best_lag={record['lag']} "
            f"best={decimal(record['best'], 4)} "
            f"pairs={record['pairs']}"
        )
    return result


def create_plot_lines(stations, settings, prediction_hour):
    """Plot the requested station with markers for high and low waters."""
    code = settings["plot_code"]
    station = stations[code]
    result = [
        f"[plot] station={code} "
        f"start={datetime_at_hour(settings['epoch'], prediction_hour)} "
        f"hours={settings['plot_hours']} step_cm={settings['plot_step']}",
    ]
    result.extend(render_plot(
        station["model"], station["extrema"], prediction_hour,
        settings["plot_hours"], settings["plot_top"],
        settings["plot_bottom"], settings["plot_step"],
    ))
    return result


def create_summary_lines(stations, order, settings, prediction_hour):
    """Assemble every summary section in the required fixed sequence."""
    result = []
    for code in order:
        station = stations[code]
        result.extend(create_station_summary_header(station, settings))
        result.extend(create_characteristics_lines(station, settings))
        result.extend(create_daily_mean_lines(station))
    comparisons = compare_stations(stations, settings)
    result.extend(create_comparison_lines(comparisons, settings["reference"]))
    correlations = cross_station_correlations(
        stations, order, settings["correlation_lag"]
    )
    result.extend(create_correlation_lines(correlations, settings))
    result.extend(create_plot_lines(stations, settings, prediction_hour))
    return result


def main():
    """Read, fit, forecast and write results without printing to the terminal."""
    settings, constituents, observations = read_all_inputs()
    order = [station["code"] for station in settings["stations"]]
    start_hour = epoch_hours(settings["epoch"], settings["prediction_start"])
    stations = {}
    for station in settings["stations"]:
        code = station["code"]
        stations[code] = inspect_station(
            station, observations[code], constituents, settings, start_hour
        )

    write_lines(
        "cleaning.txt",
        create_cleaning_lines(stations, order, settings),
    )
    write_lines(
        "constituents.csv",
        create_constituent_lines(stations, order, constituents),
    )
    write_lines(
        "predictions.csv",
        create_prediction_lines(stations, order, settings, start_hour),
    )
    write_lines(
        "extremes.txt",
        create_extrema_lines(stations, order, settings),
    )
    write_lines(
        "summary.txt",
        create_summary_lines(stations, order, settings, start_hour),
    )


if __name__ == "__main__":
    main()
