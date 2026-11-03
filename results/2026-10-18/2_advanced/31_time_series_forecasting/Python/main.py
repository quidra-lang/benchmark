"""Monthly demand decomposition, forecasting, diagnostics and inventory planning."""

from itertools import product
from math import ceil, floor, log, sqrt

import autoregression
import smoothing
from decomposition import decompose, least_squares_line, mean, sample_variance, total
from evaluation import accuracy, rank_models, seasonal_scale, winkler
from series_io import next_month, read_inputs, real, write_lines


METHODS = ("naive", "snaive", "drift", "ses", "holt", "damped", "hw_add", "hw_mult",
           "decomp_add", "decomp_mult", "ar")
MODELS = METHODS + ("combo",)
SMOOTHING_PARAMETERS = {
    "ses": ("alpha",), "holt": ("alpha", "beta"),
    "damped": ("alpha", "beta", "phi"),
    "hw_add": ("alpha", "beta", "gamma"), "hw_mult": ("alpha", "beta", "gamma"),
}
INTERVAL_FIELDS = ("forecast", "lo80", "hi80", "lo95", "hi95")
ACCURACY_FIELDS = ("me", "mae", "rmse", "mape", "smape", "mase", "fva", "cv_rmse",
                   "cover80", "cover95", "winkler80", "winkler95", "rank")


def rmse(errors):
    return sqrt(total(error * error for error in errors) / len(errors))


def interpolate_missing(raw):
    result = [None if value is None else float(value) for value in raw]
    left = 0
    while left < len(raw) - 1:
        right = left + 1
        while raw[right] is None:
            right += 1
        for t in range(left + 1, right):
            result[t] = raw[left] + (raw[right] - raw[left]) * (t - left) / (right - left)
        left = right
    return result


def future_periods(last, horizon):
    periods = []
    for _ in range(horizon):
        last = next_month(last)
        periods.append(last)
    return periods


def prepare_series(record, events, settings):
    season = settings["season"]
    periods = record["periods"]
    raw = record["raw"]
    values = interpolate_missing(raw)
    missing = {t for t, value in enumerate(raw) if value is None}
    decomposition = decompose(values, season)
    trend = decomposition["trend"]
    additive = decomposition["additive"]
    residuals = decomposition["residual_add"]
    defined = decomposition["defined"]
    average = mean([residuals[t] for t in defined])
    deviation = sqrt(sample_variance([residuals[t] for t in defined]))
    past = {t: events[period] for t, period in enumerate(periods) if period in events}
    outliers = {t: (residuals[t] - average) / deviation for t in defined
                if t not in missing and t not in past
                and abs(residuals[t] - average) > settings["outlier"] * deviation}
    grouped = {}
    for t, kind in past.items():
        grouped.setdefault(kind, []).append(t)
    lifts = {kind: {"occurrences": len(times),
                    "lift": mean([values[t] / (trend[t] + additive[t % season]) for t in times])}
             for kind, times in grouped.items()}
    corrected = [trend[t] + additive[t % season] if t in past or t in outliers else value
                 for t, value in enumerate(values)]
    variance_r = sample_variance([residuals[t] for t in defined])
    variance_t = sample_variance([trend[t] + residuals[t] for t in defined])
    variance_s = sample_variance([additive[t % season] + residuals[t] for t in defined])
    return {"periods": periods, "raw": raw, "values": values, "corrected": corrected,
            "future_periods": future_periods(periods[-1], settings["horizon"]),
            "missing": missing, "past": past, "events": events, "outliers": outliers,
            "lifts": lifts, "decomposition": decomposition,
            "strength_trend": max(0.0, 1 - variance_r / variance_t),
            "strength_seasonal": max(0.0, 1 - variance_r / variance_s)}


def decomposition_prediction(model, time):
    base = model["intercept"] + model["slope"] * (time + 1)
    seasonal = model["seasonal"][time % model["season"]]
    return base + seasonal if model["name"] == "decomp_add" else base * seasonal


def fit_ar(values, settings):
    candidates = []
    for kind in autoregression.KINDS:
        transformed, offset = autoregression.difference(values, settings["season"], kind)
        average, variance, _ = autoregression.autocorrelation(transformed, 0)
        candidates.append({"kind": kind, "values": transformed, "offset": offset,
                           "mean": average, "variance": variance})
    chosen = min(range(len(candidates)), key=lambda i: (candidates[i]["variance"], i))
    selected = candidates[chosen]
    transformed = selected["values"]
    average, variance, correlations = autoregression.autocorrelation(transformed, settings["max_lag"])
    coefficients, partial, variances = autoregression.durbin_levinson(correlations)
    aic = [len(transformed) * log(variance * variances[p]) + 2 * p
           for p in range(settings["max_ar"] + 1)]
    order = min(range(len(aic)), key=lambda p: (aic[p], p))
    fitted_coefficients = coefficients[order]
    return {"kind": selected["kind"], "differenced": transformed,
            "offset": selected["offset"], "mean": average, "order": order,
            "variances": [candidate["variance"] for candidate in candidates],
            "sigma2": variance * variances[order], "aic": aic,
            "coefficients": fitted_coefficients, "correlations": correlations,
            "partial": partial,
            "residuals": autoregression.residuals(transformed, average, fitted_coefficients)}


def fit_method(name, values, settings):
    season = settings["season"]
    count = len(values)
    model = {"name": name, "series": values, "season": season}
    if name == "naive":
        errors = [values[t] - values[t - 1] for t in range(1, count)]
    elif name == "snaive":
        errors = [values[t] - values[t - season] for t in range(season, count)]
    elif name == "drift":
        model["slope"] = (values[-1] - values[0]) / (count - 1)
        errors = [values[t] - values[t - 1] - model["slope"] for t in range(1, count)]
    elif name in SMOOTHING_PARAMETERS:
        names = SMOOTHING_PARAMETERS[name]
        best = None
        for combination in product(*(settings[key] for key in names)):
            parameters = dict(zip(names, combination))
            residuals, states = smoothing.recurse(name, values, season, parameters)
            score = total(error * error for error in residuals)
            if best is None or score < best[0]:
                best = score, parameters, residuals, states
        _, model["parameters"], errors, model["states"] = best
    elif name in ("decomp_add", "decomp_mult"):
        components = decompose(values, season)
        additive = name == "decomp_add"
        indices = components["additive" if additive else "multiplicative"]
        adjusted = [value - indices[t % season] if additive else value / indices[t % season]
                    for t, value in enumerate(values)]
        model["intercept"], model["slope"] = least_squares_line(adjusted)
        model["seasonal"] = indices
        errors = [value - decomposition_prediction(model, t) for t, value in enumerate(values)]
    else:
        model.update(fit_ar(values, settings))
        errors = model["residuals"]
    model["residuals"] = errors
    return model


def combination_model(models, values, season):
    return {"name": "combo", "members": models, "series": values, "season": season}


def forecast(model, origin, steps):
    name = model["name"]
    values = model["series"]
    season = model["season"]
    if name == "combo":
        predictions = [forecast(member, origin, steps) for member in model["members"]]
        return [total(row[i] for row in predictions) / len(predictions) for i in range(steps)]
    if name == "naive":
        return [values[origin - 1]] * steps
    if name == "snaive":
        return [values[origin - season + i % season] for i in range(steps)]
    if name == "drift":
        slope = (values[origin - 1] - values[0]) / (origin - 1)
        return [values[origin - 1] + step * slope for step in range(1, steps + 1)]
    if name in SMOOTHING_PARAMETERS:
        return smoothing.forecast(name, model["states"][origin], model["parameters"],
                                  origin, steps, season)
    if name in ("decomp_add", "decomp_mult"):
        return [decomposition_prediction(model, origin + step) for step in range(steps)]
    return autoregression.forecast(values, model["differenced"], model["offset"], model["kind"],
                                   model["mean"], model["coefficients"], origin, steps, season)


def cross_validate(model, settings):
    values = model["series"]
    horizon = settings["horizon"]
    counts = [0] * horizon
    squared = [0.0] * horizon
    absolute = [0.0] * horizon
    for origin in range(settings["cv_start"], len(values)):
        predictions = forecast(model, origin, min(horizon, len(values) - origin))
        for i, prediction in enumerate(predictions):
            error = values[origin + i] - prediction
            counts[i] += 1
            squared[i] += error * error
            absolute[i] += abs(error)
    sigma = [sqrt(value / count) for value, count in zip(squared, counts)]
    mae = [value / count for value, count in zip(absolute, counts)]
    holdout = settings["holdout"]
    cv_rmse = sqrt(total(squared[:holdout]) / sum(counts[:holdout]))
    return {"counts": counts, "sigma": sigma, "mae": mae, "cv_rmse": cv_rmse}


def interval_rows(predicted, sigma, coefficients, multipliers=None):
    if multipliers is None:
        multipliers = [1.0] * len(predicted)
    low_factor, high_factor = coefficients
    rows = []
    for value, error, multiplier in zip(predicted, sigma, multipliers):
        rows.append({"forecast": value * multiplier,
                     "lo80": (value - low_factor * error) * multiplier,
                     "hi80": (value + low_factor * error) * multiplier,
                     "lo95": (value - high_factor * error) * multiplier,
                     "hi95": (value + high_factor * error) * multiplier})
    return rows


def evaluate_holdout(models, cvs, actual, training, settings):
    scale = seasonal_scale(training, settings["season"])
    metrics = {}
    intervals = {}
    for name in MODELS:
        predicted = forecast(models[name], len(training), len(actual))
        rows = interval_rows(predicted, cvs[name]["sigma"], settings["interval"])
        intervals[name] = rows
        measures = accuracy(actual, predicted, scale)
        measures["cv_rmse"] = cvs[name]["cv_rmse"]
        measures["cover80"] = sum(row["lo80"] <= value <= row["hi80"]
                                  for row, value in zip(rows, actual))
        measures["cover95"] = sum(row["lo95"] <= value <= row["hi95"]
                                  for row, value in zip(rows, actual))
        measures["winkler80"] = total(winkler(value, row["lo80"], row["hi80"], 10)
                                     for row, value in zip(rows, actual)) / len(actual)
        measures["winkler95"] = total(winkler(value, row["lo95"], row["hi95"], 40)
                                     for row, value in zip(rows, actual)) / len(actual)
        metrics[name] = measures
    naive_mae = metrics["naive"]["mae"]
    for measures in metrics.values():
        measures["fva"] = 100 * (naive_mae - measures["mae"]) / naive_mae
    ranking = rank_models(MODELS, metrics)
    for rank, name in enumerate(ranking, 1):
        metrics[name]["rank"] = rank
    return metrics, intervals, ranking[0]


def inventory_plan(model, demands, policy, settings):
    lead = policy["lead_time"]
    review = policy["review"]
    protection = lead + review
    values = model["series"]
    errors = []
    for origin in range(settings["cv_start"], len(values) - protection + 1):
        predictions = forecast(model, origin, protection)
        errors.append(total(values[origin + i] - prediction for i, prediction in enumerate(predictions)))
    safety = policy["service"] * rmse(errors)
    reviews = list(range(1, len(demands) - protection + 2, review))
    end = reviews[-1] - 1 + protection
    on_hand = float(policy["on_hand"])
    outstanding = 0
    receipts = {}
    rows = []
    orders = 0
    ordered = 0
    for step in range(1, end + 1):
        receipt = receipts.pop(step, 0)
        on_hand += receipt
        outstanding -= receipt
        row = {"step": step, "receipt": receipt, "demand": demands[step - 1]}
        if step in reviews:
            position = on_hand + outstanding
            target = total(demands[step - 1:step - 1 + protection]) + safety
            quantity = max(0, ceil(target - position))
            row["review"] = {"position": position, "target": target, "order": quantity}
            if quantity > 0:
                orders += 1
                ordered += quantity
                outstanding += quantity
                receipts[step + lead] = quantity
        on_hand -= demands[step - 1]
        row["on_hand"] = on_hand
        row["status"] = "short" if on_hand < 0 else "low" if on_hand < safety else "ok"
        rows.append(row)
    return {"safety": safety, "rows": rows, "orders": orders, "ordered": ordered,
            "short_periods": sum(row["status"] == "short" for row in rows),
            "lowest": min(row["on_hand"] for row in rows),
            "average": mean([row["on_hand"] for row in rows])}


def yearly_totals(periods, actual, future, demands):
    years = {}
    for period, value in zip(periods, actual):
        row = years.setdefault(period[:4], {"actual_months": 0, "actual": 0.0,
                                           "forecast_months": 0, "forecast": 0.0})
        row["actual_months"] += 1
        row["actual"] += value
    for period, value in zip(future, demands):
        row = years.setdefault(period[:4], {"actual_months": 0, "actual": 0.0,
                                           "forecast_months": 0, "forecast": 0.0})
        row["forecast_months"] += 1
        row["forecast"] += value
    previous = None
    result = []
    for year in sorted(years):
        row = years[year]
        row["year"] = year
        row["total"] = row["actual"] + row["forecast"]
        complete = row["actual_months"] + row["forecast_months"] == 12
        row["growth"] = None
        if complete and previous is not None and previous["actual_months"] + previous["forecast_months"] == 12:
            row["growth"] = 100 * (row["total"] - previous["total"]) / previous["total"]
        result.append(row)
        previous = row
    return result


def residual_diagnostics(errors, lags):
    count = len(errors)
    average = mean(errors)
    centered = [error - average for error in errors]
    squared = total(value * value for value in centered)
    m2 = squared / count
    m3 = total(value * value * value for value in centered) / count
    m4 = total(value * value * value * value for value in centered) / count
    sd = sqrt(squared / (count - 1))
    dw = total((errors[i] - errors[i - 1]) * (errors[i] - errors[i - 1])
               for i in range(1, count)) / total(value * value for value in errors)
    skewness = m3 / (m2 * sqrt(m2))
    kurtosis = m4 / (m2 * m2) - 3
    jb = count / 6 * (skewness * skewness + kurtosis * kurtosis / 4)
    return {"count": count, "mean": average, "sd": sd, "dw": dw,
            "skewness": skewness, "kurtosis": kurtosis, "jb": jb,
            "ljung_box": autoregression.ljung_box(errors, lags)}


def analyze(record, events, policy, settings):
    data = prepare_series(record, events, settings)
    training_count = len(data["values"]) - settings["holdout"]
    training = data["corrected"][:training_count]
    actual = data["values"][training_count:]
    models = {name: fit_method(name, training, settings) for name in METHODS}
    cvs = {name: cross_validate(models[name], settings) for name in METHODS}
    selected = sorted(METHODS, key=lambda name: (cvs[name]["cv_rmse"], METHODS.index(name)))[:settings["combo"]]
    members = [name for name in METHODS if name in selected]
    models["combo"] = combination_model([models[name] for name in members], training, settings["season"])
    cvs["combo"] = cross_validate(models["combo"], settings)
    metrics, intervals, best = evaluate_holdout(models, cvs, actual, training, settings)
    final_names = members if best == "combo" else [best]
    final_fits = {name: fit_method(name, data["corrected"], settings) for name in final_names}
    final = (combination_model(list(final_fits.values()), data["corrected"], settings["season"])
             if best == "combo" else final_fits[best])
    final_cv = cross_validate(final, settings)
    future = forecast(final, len(data["values"]), settings["horizon"])
    multipliers = [data["lifts"][events[period]]["lift"] if period in events else 1.0
                   for period in data["future_periods"]]
    future_rows = interval_rows(future, final_cv["sigma"], settings["interval"], multipliers)
    demands = [row["forecast"] for row in future_rows]
    data.update({"training_count": training_count, "models": models, "cv": cvs,
                 "members": members, "metrics": metrics, "intervals": intervals,
                 "best": best, "final_fits": final_fits, "future_rows": future_rows,
                 "policy": policy, "plan": inventory_plan(final, demands, policy, settings),
                 "years": yearly_totals(data["periods"], data["values"], data["future_periods"], demands),
                 "residual_diagnostics": {name: residual_diagnostics(models[name]["residuals"], settings["ljung_box"])
                                          for name in METHODS}})
    return data


def model_lines(model):
    name = model["name"]
    residuals = model["residuals"]
    common = f"rmse {real(rmse(residuals))} residuals {len(residuals)}"
    if name in ("naive", "snaive"):
        return [f"{name} {common}"]
    if name == "drift":
        return [f"drift slope {real(model['slope'])} {common}"]
    if name in SMOOTHING_PARAMETERS:
        parameters = " ".join(f"{key} {real(model['parameters'][key])}" for key in SMOOTHING_PARAMETERS[name])
        level, slope, seasonal = model["states"][-1]
        first = f"{name} {parameters} {common} level {real(level)}"
        if name != "ses":
            first += f" slope {real(slope)}"
        lines = [first]
        if seasonal is not None:
            origin = len(model["series"])
            values = [seasonal[(origin + i) % model["season"]] for i in range(model["season"])]
            lines.append(name + " seasonal " + " ".join(real(value) for value in values))
        return lines
    if name in ("decomp_add", "decomp_mult"):
        return [f"{name} intercept {real(model['intercept'])} slope {real(model['slope'])} {common}",
                name + " seasonal " + " ".join(real(value) for value in model["seasonal"])]
    variance = " ".join(f"{kind} {real(value)}" for kind, value in zip(autoregression.KINDS, model["variances"]))
    coefficients = " ".join(real(value) for value in model["coefficients"]) or "none"
    return ["ar variance " + variance,
            f"ar difference {model['kind']} n {len(model['differenced'])} mean {real(model['mean'])} "
            f"order {model['order']} sigma2 {real(model['sigma2'])} {common}",
            "ar aic " + " ".join(real(value) for value in model["aic"]),
            "ar coefficients " + coefficients]


def decomposition_lines(analyses, settings):
    lines = ["series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag"]
    season = settings["season"]
    for name, data in analyses.items():
        decomposition = data["decomposition"]
        for t, period in enumerate(data["periods"]):
            if t in data["past"]:
                flag = data["past"][t]
            elif t in data["missing"]:
                flag = "missing"
            elif t in data["outliers"]:
                flag = "outlier"
            else:
                flag = "ok"
            values = [data["values"][t], data["corrected"][t], decomposition["trend"][t],
                      decomposition["additive"][t % season], decomposition["residual_add"][t],
                      decomposition["multiplicative"][t % season], decomposition["residual_mult"][t]]
            lines.append(",".join([name, period] + [real(value) for value in values] + [flag]))
    return lines


def fitted_model_lines(analyses, settings):
    lines = []
    for name, data in analyses.items():
        lines.extend([f"series {name}",
                      f"data observations {len(data['values'])} train {data['training_count']} "
                      f"holdout {settings['holdout']} missing {len(data['missing'])} "
                      f"outliers {len(data['outliers'])} events {len(data['past'])}"])
        for kind, lift in data["lifts"].items():
            lines.append(f"event {kind} occurrences {lift['occurrences']} lift {real(lift['lift'])}")
        for t, score in data["outliers"].items():
            lines.append(f"outlier {data['periods'][t]} value {real(data['values'][t])} "
                         f"expected {real(data['corrected'][t])} score {real(score)}")
        lines.append(f"strength trend {real(data['strength_trend'])} seasonal {real(data['strength_seasonal'])}")
        for method in METHODS:
            lines.extend(model_lines(data["models"][method]))
        lines.append("combo members " + " ".join(data["members"]))
        lines.append(f"best {data['best']} rmse {real(data['metrics'][data['best']]['rmse'])}")
        for model in data["final_fits"].values():
            lines.extend("final " + line for line in model_lines(model))
    return lines


def forecast_lines(analyses):
    lines = ["series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95"]
    for name, data in analyses.items():
        start = data["training_count"]
        for method in MODELS:
            for i, row in enumerate(data["intervals"][method]):
                prefix = [name, "holdout", method, data["periods"][start + i], str(data["raw"][start + i])]
                lines.append(",".join(prefix + [real(row[key]) for key in INTERVAL_FIELDS]))
        for period, row in zip(data["future_periods"], data["future_rows"]):
            prefix = [name, "future", data["best"], period, "NA"]
            lines.append(",".join(prefix + [real(row[key]) for key in INTERVAL_FIELDS]))
    return lines


def accuracy_lines(analyses):
    lines = ["series,method," + ",".join(ACCURACY_FIELDS)]
    for name, data in analyses.items():
        for method in MODELS:
            values = data["metrics"][method]
            fields = [str(values[key]) if key in ("cover80", "cover95", "rank") else real(values[key])
                      for key in ACCURACY_FIELDS]
            lines.append(",".join([name, method] + fields))
    return lines


def cross_validation_lines(analyses):
    lines = ["series,method,step,origins,mae,rmse"]
    for name, data in analyses.items():
        for method in MODELS:
            cv = data["cv"][method]
            for i, count in enumerate(cv["counts"]):
                lines.append(f"{name},{method},{i + 1},{count},{real(cv['mae'][i])},{real(cv['sigma'][i])}")
    return lines


def correlation_bar(value, band):
    width = floor(abs(value) * 20 + 0.5)
    threshold = floor(band * 20 + 0.5)
    bar = [" "] * 41
    bar[20 - threshold] = ":"
    bar[20 + threshold] = ":"
    bar[20] = "|"
    if value > 0:
        for index in range(21, 21 + width):
            bar[index] = "#"
    elif value < 0:
        for index in range(20 - width, 20):
            bar[index] = "#"
    return "".join(bar)


def correlogram_lines(analyses):
    lines = []
    for name, data in analyses.items():
        ar = data["models"]["ar"]
        count = len(ar["differenced"])
        band = 2 / sqrt(count)
        lines.append(f"series {name} difference {ar['kind']} n {count} band {real(band)}")
        for label, sequence in (("acf", ar["correlations"]), ("pacf", ar["partial"])):
            for lag in range(1, len(sequence)):
                value = sequence[lag]
                line = f"{label} {lag:2d} {real(value):>7} [{correlation_bar(value, band)}]"
                lines.append(line + (" *" if abs(value) > band else ""))
        for method in METHODS:
            stats = data["residual_diagnostics"][method]
            lines.append(f"residuals {method} n {stats['count']} mean {real(stats['mean'])} "
                         f"sd {real(stats['sd'])} dw {real(stats['dw'])} skewness {real(stats['skewness'])} "
                         f"kurtosis {real(stats['kurtosis'])} jb {real(stats['jb'])}")
            lines.append(f"ljung_box {method} " + " ".join(
                f"lag {lag} q {real(q)} p {real(p)}" for lag, q, p in stats["ljung_box"]
            ))
    return lines


def chart_rows(data):
    start = data["training_count"]
    rows = []
    for i, row in enumerate(data["intervals"][data["best"]]):
        rows.append({**row, "period": data["periods"][start + i], "actual": data["values"][start + i]})
    for period, row in zip(data["future_periods"], data["future_rows"]):
        rows.append({**row, "period": period, "actual": None})
    return rows


def forecast_chart(row, low, high):
    def column(value):
        return floor((value - low) / (high - low) * 60 + 0.5)

    cells = [" "] * 61
    for start, stop, symbol in (("lo95", "hi95", "-"), ("lo80", "hi80", "=")):
        for index in range(column(row[start]), column(row[stop]) + 1):
            cells[index] = symbol
    cells[column(row["forecast"])] = "o"
    if row["actual"] is not None:
        cells[column(row["actual"])] = "*"
    return "".join(cells)


def seasonal_profile(value, peak):
    width = floor(abs(value - 1) / peak * 30 + 0.5)
    cells = [" "] * 61
    cells[30] = "|"
    if value > 1:
        for index in range(31, 31 + width):
            cells[index] = "#"
    elif value < 1:
        for index in range(30 - width, 30):
            cells[index] = "#"
    return "".join(cells)


def chart_lines(analyses):
    lines = []
    for name, data in analyses.items():
        rows = chart_rows(data)
        actual = [row["actual"] for row in rows if row["actual"] is not None]
        low = min([row["lo95"] for row in rows] + actual)
        high = max([row["hi95"] for row in rows] + actual)
        lines.extend([f"chart {name} method {data['best']}", f"scale low {real(low)} high {real(high)}"])
        for row in rows:
            lines.append(f"{row['period']} |{forecast_chart(row, low, high)}|")
        seasonal = data["decomposition"]["multiplicative"]
        peak = max(abs(value - 1) for value in seasonal)
        lines.append("profile peak " + real(peak))
        for i, value in enumerate(seasonal, 1):
            lines.append(f"season {i:2d} {real(value)} [{seasonal_profile(value, peak)}]")
    return lines


def plan_lines(analyses):
    lines = []
    for name, data in analyses.items():
        policy, plan = data["policy"], data["plan"]
        lines.extend([f"series {name} method {data['best']}",
                      f"policy on_hand {policy['on_hand']} lead_time {policy['lead_time']} "
                      f"review {policy['review']} service {real(policy['service'])} safety_stock {real(plan['safety'])}"])
        for row in plan["rows"]:
            period = data["future_periods"][row["step"] - 1]
            if "review" in row:
                review = row["review"]
                lines.append(f"review {period} position {real(review['position'])} "
                             f"target {real(review['target'])} order {review['order']}")
            lines.append(f"period {period} demand {real(row['demand'])} receipt {row['receipt']} "
                         f"on_hand {real(row['on_hand'])} status {row['status']}")
        lines.append(f"summary orders {plan['orders']} ordered {plan['ordered']} short_periods {plan['short_periods']} "
                     f"lowest {real(plan['lowest'])} average {real(plan['average'])}")
        for year in data["years"]:
            lines.append(f"year {year['year']} actual_months {year['actual_months']} actual {real(year['actual'])} "
                         f"forecast_months {year['forecast_months']} forecast {real(year['forecast'])} "
                         f"total {real(year['total'])} growth {real(year['growth'])}")
    return lines


def main():
    series, events, policies, settings = read_inputs()
    analyses = {name: analyze(record, events[name], policies[name], settings)
                for name, record in series.items()}
    write_lines("decomposition.csv", decomposition_lines(analyses, settings))
    write_lines("models.txt", fitted_model_lines(analyses, settings))
    write_lines("forecasts.csv", forecast_lines(analyses))
    write_lines("accuracy.csv", accuracy_lines(analyses))
    write_lines("cv.csv", cross_validation_lines(analyses))
    write_lines("correlogram.txt", correlogram_lines(analyses))
    write_lines("chart.txt", chart_lines(analyses))
    write_lines("plan.txt", plan_lines(analyses))


if __name__ == "__main__":
    main()
