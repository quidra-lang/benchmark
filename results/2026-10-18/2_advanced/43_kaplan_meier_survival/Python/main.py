"""Deterministic survival analysis and the five specified file reports."""

from itertools import combinations, groupby
from math import exp, log, sqrt
from pathlib import Path

import cox
from dataset import read_dataset
from estimators import kaplan_meier, life_table, row_at
from group_tests import WEIGHTS, combine_strata, weighted_test
from numerics import Z95, chi_square_p, inverse, solve, total
from plot import curve_lines


def number(value, digits=4):
    if value is None:
        return "NA"
    return f"{value:z.{digits}f}"


def day(value):
    return "NA" if value is None else str(value)


def build_collections(subjects, groups):
    collections = {
        group: [subject for subject in subjects if subject["group"] == group]
        for group in groups
    }
    collections["all"] = subjects
    return collections


def percentile_time(rows, threshold, column="survival"):
    for row in rows:
        value = 0.0 if row["survival"] == 0.0 else row[column]
        if value is not None and value <= threshold:
            return row["time"]
    return None


def restricted_mean(rows, tau):
    selected = [row for row in rows if row["time"] <= tau]
    times = [0] + [row["time"] for row in selected] + [tau]
    survival = [1.0] + [row["survival"] for row in selected]
    rectangles = [value * (times[i + 1] - times[i])
                  for i, value in enumerate(survival)]
    tails = [0.0] * len(rectangles)
    tails[-1] = rectangles[-1]
    for i in range(len(tails) - 2, -1, -1):
        tails[i] = rectangles[i] + tails[i + 1]
    variance = 0.0
    for i, row in enumerate(selected, 1):
        risk = row["risk"]
        events = row["events"]
        variance += tails[i] * tails[i] * (events / (risk * (risk - events)))
    estimate = tails[0]
    error = sqrt(variance)
    return estimate, error, estimate - Z95 * error, estimate + Z95 * error


def collection_summary(subjects, params):
    rows = kaplan_meier(subjects)
    life = life_table(subjects, *params["life_table"])
    events = sum(subject["event"] for subject in subjects)
    person_days = sum(subject["time"] for subject in subjects)
    rate = 1000 * events / person_days
    eta = Z95 / sqrt(events)
    reverse = [dict(subject, event=1 - subject["event"]) for subject in subjects]
    followup = percentile_time(kaplan_meier(reverse), 0.5)
    life_median = None
    previous_survival = 1.0
    for row in life:
        if row["survival"] <= 0.5:
            life_median = (row["start"] + params["life_table"][0]
                           * (previous_survival - 0.5)
                           / (previous_survival - row["survival"]))
            break
        previous_survival = row["survival"]
    percentiles = []
    for percentile, threshold in ((25, 0.75), (50, 0.5), (75, 0.25)):
        percentiles.append((
            percentile,
            percentile_time(rows, threshold),
            percentile_time(rows, threshold, "lower"),
            percentile_time(rows, threshold, "upper"),
        ))
    return {
        "rows": rows,
        "life": life,
        "subjects": len(subjects),
        "events": events,
        "censored": len(subjects) - events,
        "maximum": max(subject["time"] for subject in subjects),
        "person_days": person_days,
        "rate": rate,
        "rate_lower": exp(log(rate) - eta),
        "rate_upper": exp(log(rate) + eta),
        "followup": followup,
        "life_median": life_median,
        "percentiles": percentiles,
        "rmst": restricted_mean(rows, params["tau"]),
    }


def km_table_lines(name, subjects, summary, params):
    lines = [
        f"group {name} subjects {summary['subjects']} events {summary['events']}"
        f" censored {summary['censored']} max_time {summary['maximum']}",
        f"person_days {summary['person_days']} rate {number(summary['rate'])}"
        f" lower {number(summary['rate_lower'])} upper {number(summary['rate_upper'])}",
        f"followup_median {day(summary['followup'])}",
        f"life_table_median {number(summary['life_median'])}",
    ]
    for percentile, time, lower, upper in summary["percentiles"]:
        lines.append(f"percentile {percentile} time {day(time)}"
                     f" lower {day(lower)} upper {day(upper)}")
    estimate, error, lower, upper = summary["rmst"]
    lines.append(f"rmst tau {params['tau']} estimate {number(estimate)}"
                 f" se {number(error)} lower {number(lower)} upper {number(upper)}")
    for time in params["report_times"]:
        row = row_at(summary["rows"], time)
        risk = sum(subject["time"] >= time for subject in subjects)
        events = sum(subject["time"] <= time and subject["event"] == 1
                     for subject in subjects)
        lines.append(
            f"at {time} at_risk {risk} events {events}"
            f" survival {number(row['survival'])} std_err {number(row['se'])}"
            f" lower {number(row['lower'])} upper {number(row['upper'])}"
            f" cum_hazard {number(row['hazard'])} hazard_se {number(row['hazard_se'])}"
        )
    columns = ("time", "at_risk", "events", "censored", "survival",
               "std_err", "lower", "upper", "cum_haz", "haz_se")
    lines.append("".join(f"{name:>9}" for name in columns))
    for row in summary["rows"]:
        fields = [str(row[key]) for key in ("time", "risk", "events", "censored")]
        fields.extend(number(row[key]) for key in (
            "survival", "se", "lower", "upper", "hazard", "hazard_se"
        ))
        lines.append("".join(f"{value:>9}" for value in fields))
    return lines


def life_table_lines(summaries):
    lines = ["group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard"]
    for name, summary in summaries.items():
        for row in summary["life"]:
            fields = [name, f"{row['start']}-{row['end']}"]
            fields.extend(str(row[key]) for key in ("risk", "events", "withdrawn"))
            fields.append(number(row["exposed"], 1))
            fields.extend(number(row[key]) for key in ("q", "survival", "se", "hazard"))
            lines.append(",".join(fields))
    return lines


def baseline_summary(name, subjects):
    count = len(subjects)
    mean = sum(subject["age"] for subject in subjects) / count
    deviation = sqrt(total((subject["age"] - mean) * (subject["age"] - mean)
                           for subject in subjects) / (count - 1))
    ages = sorted(subject["age"] for subject in subjects)
    median = (ages[(count - 1) // 2] + ages[count // 2]) / 2
    males = sum(subject["sex"] == "M" for subject in subjects)
    stages = [sum(subject["stage"] == stage for subject in subjects)
              for stage in range(1, 5)]
    return (f"  group {name} subjects {count} age_mean {number(mean)}"
            f" age_sd {number(deviation)} age_median {number(median, 1)}"
            f" male {males} stage {' '.join(map(str, stages))}")


def kruskal_wallis(subjects, groups, collections):
    ranked = sorted(subjects, key=lambda subject: subject["age"])
    ranks = {}
    ties = 0
    position = 0
    for _, equal_age in groupby(ranked, key=lambda subject: subject["age"]):
        batch = list(equal_age)
        end = position + len(batch)
        rank = (position + 1 + end) / 2
        for subject in batch:
            ranks[subject["id"]] = rank
        size = len(batch)
        ties += size * size * size - size
        position = end
    weighted = 0.0
    for group in groups:
        rank_sum = total(ranks[subject["id"]] for subject in collections[group])
        weighted += rank_sum * rank_sum / len(collections[group])
    count = len(subjects)
    raw = 12 * weighted / (count * (count + 1)) - 3 * (count + 1)
    return raw / (1 - ties / (count * count * count - count))


def contingency_test(subjects, groups, collections, variable):
    levels = sorted({subject[variable] for subject in subjects})
    counts = [sum(subject[variable] == level for subject in subjects) for level in levels]
    statistic = 0.0
    for group in groups:
        members = collections[group]
        for level, column_count in zip(levels, counts):
            observed = sum(subject[variable] == level for subject in members)
            expected = len(members) * column_count / len(subjects)
            statistic += (observed - expected) * (observed - expected) / expected
    return statistic, (len(groups) - 1) * (len(levels) - 1)


def baseline_lines(subjects, groups, collections):
    lines = ["baseline"]
    lines.extend(baseline_summary(name, rows) for name, rows in collections.items())
    statistic = kruskal_wallis(subjects, groups, collections)
    degrees = len(groups) - 1
    lines.append(f"  age kruskal_wallis chisq {number(statistic)} df {degrees}"
                 f" p {number(chi_square_p(statistic, degrees))}")
    for variable in ("sex", "stage"):
        statistic, degrees = contingency_test(subjects, groups, collections, variable)
        lines.append(f"  {variable} chisq {number(statistic)} df {degrees}"
                     f" p {number(chi_square_p(statistic, degrees))}")
    return lines


def group_lines(test):
    lines = []
    for index, group in enumerate(test["groups"]):
        observed = test["observed"][index]
        expected = test["expected"][index]
        lines.append(
            f"  group {group} events {test['events'][index]}"
            f" observed {number(observed)} expected {number(expected)}"
            f" o_minus_e {number(observed - expected)}"
            f" variance {number(test['covariance'][index][index])}"
        )
    return lines


def test_fields(test):
    return (f"chisq {number(test['statistic'])} df {test['degrees']}"
            f" p {number(test['p'])}")


def overall_lines(subjects, groups):
    lines = []
    tests = {}
    for weight in WEIGHTS:
        test = weighted_test(subjects, groups, weight, len(subjects))
        tests[weight] = test
        lines.append(f"test {weight} {test_fields(test)}")
        lines.extend(group_lines(test))
    logrank = tests["logrank"]
    trend = total((g + 1) * (observed - expected)
                  for g, (observed, expected) in enumerate(
                      zip(logrank["observed"], logrank["expected"])))
    variance = total(total(((g + 1) * (h + 1)) * logrank["covariance"][g][h]
                           for h in range(len(groups)))
                     for g in range(len(groups)))
    statistic = trend * trend / variance
    lines.append(f"test logrank_trend chisq {number(statistic)} df 1"
                 f" p {number(chi_square_p(statistic, 1))}")
    return lines


def stratified_lines(subjects, groups, variable):
    levels = sorted({subject[variable] for subject in subjects})
    strata = [[subject for subject in subjects if subject[variable] == level]
              for level in levels]
    lines = []
    for weight in WEIGHTS:
        tests = [weighted_test(rows, groups, weight, len(subjects)) for rows in strata]
        combined = combine_strata(tests, groups)
        lines.append(f"stratified {weight} by {variable} {test_fields(combined)}")
        for level, rows, test in zip(levels, strata, tests):
            events = sum(subject["event"] for subject in rows)
            lines.append(f"  stratum {level} subjects {len(rows)} events {events}"
                         f" chisq {number(test['statistic'])} p {number(test['p'])}")
        lines.extend(group_lines(combined))
    return lines


def landmark_lines(subjects, groups, landmark):
    selected = [subject for subject in subjects if subject["time"] > landmark]
    test = weighted_test(selected, groups, "logrank", len(subjects))
    return [f"landmark {landmark} subjects {len(selected)} {test_fields(test)}", *group_lines(test)]


def two_group_comparison(subjects, groups, population_size):
    test = weighted_test(subjects, groups, "logrank", population_size)
    observed = test["observed"]
    expected = test["expected"]
    ratio = (observed[1] / expected[1]) / (observed[0] / expected[0])
    variance = 1 / expected[0] + 1 / expected[1]
    logarithm = log(ratio)
    lower = exp(logarithm - Z95 * sqrt(variance))
    upper = exp(logarithm + Z95 * sqrt(variance))
    return dict(test, ratio=ratio, log_ratio=logarithm, variance=variance,
                lower=lower, upper=upper)


def pairwise_lines(subjects, groups):
    pairs = list(combinations(groups, 2))
    tests = []
    for pair in pairs:
        selected = [subject for subject in subjects if subject["group"] in pair]
        tests.append(two_group_comparison(selected, pair, len(subjects)))
    adjusted = [0.0] * len(pairs)
    previous = 0.0
    order = sorted(range(len(pairs)), key=lambda index: tests[index]["p"])
    for rank, index in enumerate(order):
        candidate = (len(pairs) - rank) * tests[index]["p"]
        previous = max(previous, min(1.0, candidate))
        adjusted[index] = previous
    lines = ["pairwise logrank adjust holm"]
    for (first, second), test, correction in zip(pairs, tests, adjusted):
        lines.append(
            f"  {first} {second} chisq {number(test['statistic'])} p {number(test['p'])}"
            f" p_holm {number(correction)} hr {number(test['ratio'])}"
            f" lower {number(test['lower'])} upper {number(test['upper'])}"
        )
    return lines


def subgroup_lines(subjects, groups, variables):
    lines = [f"subgroups reference {groups[0]}"]
    for variable in variables:
        levels = sorted({subject[variable] for subject in subjects})
        for group in groups[1:]:
            tests = []
            for level in levels:
                selected = [subject for subject in subjects
                            if subject[variable] == level
                            and subject["group"] in (groups[0], group)]
                test = two_group_comparison(selected, (groups[0], group), len(subjects))
                tests.append(test)
                events = sum(subject["event"] for subject in selected)
                lines.append(
                    f"  {variable} {level} {group} subjects {len(selected)} events {events}"
                    f" hr {number(test['ratio'])} lower {number(test['lower'])}"
                    f" upper {number(test['upper'])} p {number(test['p'])}"
                )
            weights = [1 / test["variance"] for test in tests]
            mean = total(weight * test["log_ratio"] for weight, test in zip(weights, tests))
            mean /= total(weights)
            statistic = total(weight * (test["log_ratio"] - mean) * (test["log_ratio"] - mean)
                              for weight, test in zip(weights, tests))
            degrees = len(levels) - 1
            lines.append(f"  {variable} {group} heterogeneity chisq {number(statistic)}"
                         f" df {degrees} p {number(chi_square_p(statistic, degrees))}")
    return lines


def difference_fields(difference, error):
    statistic = difference / error
    return (f"difference {number(difference)} se {number(error)}"
            f" lower {number(difference - Z95 * error)}"
            f" upper {number(difference + Z95 * error)} z {number(statistic)}"
            f" p {number(chi_square_p(statistic * statistic, 1))}")


def rmst_difference_lines(groups, summaries, tau):
    lines = [f"rmst_difference tau {tau} reference {groups[0]}"]
    control_mean, control_error, _, _ = summaries[groups[0]]["rmst"]
    for group in groups[1:]:
        mean, error, _, _ = summaries[group]["rmst"]
        difference = mean - control_mean
        combined_error = sqrt(error * error + control_error * control_error)
        lines.append(f"  {group} {difference_fields(difference, combined_error)}")
    return lines


def rate_ratio_lines(groups, summaries):
    lines = [f"rate_ratio reference {groups[0]}"]
    control = summaries[groups[0]]
    for group in groups[1:]:
        summary = summaries[group]
        ratio = summary["rate"] / control["rate"]
        error = sqrt(1 / summary["events"] + 1 / control["events"])
        logarithm = log(ratio)
        statistic = logarithm / error
        lower = exp(logarithm - Z95 * error)
        upper = exp(logarithm + Z95 * error)
        lines.append(f"  {group} ratio {number(ratio)} lower {number(lower)}"
                     f" upper {number(upper)} z {number(statistic)}"
                     f" p {number(chi_square_p(statistic * statistic, 1))}")
    return lines


def survival_difference_lines(groups, summaries, times):
    lines = [f"survival_difference reference {groups[0]}"]
    for time in times:
        control = row_at(summaries[groups[0]]["rows"], time)
        for group in groups[1:]:
            row = row_at(summaries[group]["rows"], time)
            difference = row["survival"] - control["survival"]
            error = sqrt(row["se"] * row["se"] + control["se"] * control["se"])
            lines.append(f"  at {time} {group} {difference_fields(difference, error)}")
    return lines


def comparison_sections(subjects, params, collections, summaries):
    groups = params["groups"]
    return [
        baseline_lines(subjects, groups, collections),
        overall_lines(subjects, groups),
        stratified_lines(subjects, groups, params["strata"]),
        landmark_lines(subjects, groups, params["landmark"]),
        pairwise_lines(subjects, groups),
        subgroup_lines(subjects, groups, params["subgroups"]),
        rmst_difference_lines(groups, summaries, params["tau"]),
        rate_ratio_lines(groups, summaries),
        survival_difference_lines(groups, summaries, params["report_times"]),
    ]


def covariate_vectors(subjects, names):
    vectors = []
    for subject in subjects:
        values = []
        for name in names:
            if name in ("age", "stage"):
                value = subject[name]
            elif name == "male":
                value = int(subject["sex"] == "M")
            else:
                value = int(subject["group"] == name)
            values.append(value)
        vectors.append(values)
    return vectors


def coefficient_fields(coefficient, error):
    statistic = coefficient / error
    lower = exp(coefficient - Z95 * error)
    upper = exp(coefficient + Z95 * error)
    return (f"coef {number(coefficient)} se {number(error)} z {number(statistic)}"
            f" p {number(chi_square_p(statistic * statistic, 1))}"
            f" hr {number(exp(coefficient))} lower {number(lower)} upper {number(upper)}")


def coefficient_lines(names, beta, covariance):
    lines = []
    for index, name in enumerate(names):
        error = sqrt(covariance[index][index])
        lines.append(f"term {name} {coefficient_fields(beta[index], error)}")
    group_indices = [i for i, name in enumerate(names) if name not in ("age", "male", "stage")]
    for first, second in combinations(group_indices, 2):
        coefficient = beta[second] - beta[first]
        error = sqrt(covariance[second][second] + covariance[first][first]
                     - 2 * covariance[first][second])
        lines.append(f"contrast {names[second]} vs {names[first]}"
                     f" {coefficient_fields(coefficient, error)}")
    return lines


def cox_test_lines(subjects, vectors, names, model):
    beta = model["beta"]
    final = model["final"]
    null = model["null"]
    size = len(names)
    likelihood_ratio = 2 * (final["loglik"] - null["loglik"])
    wald = total(beta[c] * total(final["information"][c][d] * beta[d] for d in range(size))
                 for c in range(size))
    solution = solve(null["information"], null["score"])
    score = total(null["score"][c] * solution[c] for c in range(size))
    lines = []
    for label, statistic in (("likelihood_ratio", likelihood_ratio), ("wald", wald), ("score", score)):
        lines.append(f"{label} chisq {number(statistic)} df {size}"
                     f" p {number(chi_square_p(statistic, size))}")
    for index, name in enumerate(names):
        if size == 1:
            likelihood = null["loglik"]
        else:
            reduced = [values[:index] + values[index + 1:] for values in vectors]
            likelihood = cox.fit(subjects, reduced)["final"]["loglik"]
        statistic = 2 * (final["loglik"] - likelihood)
        lines.append(f"drop {name} loglik {number(likelihood)} chisq {number(statistic)}"
                     f" df 1 p {number(chi_square_p(statistic, 1))}")
    return lines


def concordance_line(subjects, vectors, predictors):
    comparable = concordant = tied = 0
    for i, first in enumerate(subjects):
        if not first["event"]:
            continue
        for j, second in enumerate(subjects):
            if i == j:
                continue
            qualifies = (first["time"] < second["time"]
                         or first["time"] == second["time"] and second["event"] == 0)
            if not qualifies:
                continue
            comparable += 1
            if vectors[i] == vectors[j]:
                tied += 1
            elif predictors[i] > predictors[j]:
                concordant += 1
    value = (2 * concordant + tied) / (2 * comparable)
    return (f"concordance {number(value)} comparable {comparable}"
            f" concordant {concordant} tied {tied}")


def proportional_hazards_lines(subjects, vectors, names, evaluation):
    events = sorted((i for i, subject in enumerate(subjects) if subject["event"]),
                    key=lambda i: (subjects[i]["time"], subjects[i]["id"]))
    count = len(events)
    mean_time = sum(subjects[i]["time"] for i in events) / count
    lines = []
    for column, name in enumerate(names):
        residuals = []
        for i in events:
            sums = evaluation["event_sums"][subjects[i]["time"]]
            residuals.append(vectors[i][column] - sums["s1"][column] / sums["s0"])
        mean_residual = total(residuals) / count
        sxy = sxx = syy = 0.0
        for i, residual in zip(events, residuals):
            x = residual - mean_residual
            y = subjects[i]["time"] - mean_time
            sxy += x * y
            sxx += x * x
            syy += y * y
        correlation = sxy / sqrt(sxx * syy)
        statistic = 0.5 * log((1 + correlation) / (1 - correlation)) * sqrt(count - 3)
        lines.append(f"ph_check {name} rho {number(correlation)} z {number(statistic)}"
                     f" p {number(chi_square_p(statistic * statistic, 1))}")
    return lines


def baseline_hazard(evaluation):
    cumulative = 0.0
    rows = []
    for time, sums in sorted(evaluation["event_sums"].items()):
        cumulative += sums["events"] / sums["s0"]
        rows.append((time, cumulative))
    return rows


def hazard_at(rows, time):
    for event_time, hazard in reversed(rows):
        if event_time <= time:
            return hazard
    return 0.0


def residual_lines(subjects, evaluation, hazard, count):
    residuals = []
    for subject, predictor in zip(subjects, evaluation["predictors"]):
        martingale = subject["event"] - hazard_at(hazard, subject["time"]) * exp(predictor)
        if subject["event"]:
            deviance = sqrt(-2 * (martingale + log(1 - martingale)))
        else:
            deviance = sqrt(-2 * martingale)
        if not martingale > 0:
            deviance = -deviance
        residuals.append((subject, martingale, deviance))
    residuals.sort(key=lambda row: (-abs(row[2]), row[0]["id"]))
    lines = [f"residuals top {count}"]
    for subject, martingale, deviance in residuals[:count]:
        lines.append(f"  id {subject['id']} group {subject['group']} time {subject['time']}"
                     f" event {subject['event']} martingale {number(martingale)}"
                     f" deviance {number(deviance)}")
    return lines


def adjusted_survival_lines(vectors, names, beta, groups, times, hazard):
    means = {name: sum(x[column] for x in vectors) / len(vectors)
             for column, name in enumerate(names) if name in ("age", "male", "stage")}
    if means:
        fields = " ".join(f"{name} {number(value)}" for name, value in means.items())
    else:
        fields = "none"
    lines = [f"adjusted_survival mean {fields}"]
    risks = {}
    for group in groups:
        representative = [means[name] if name in means else int(name == group) for name in names]
        risks[group] = exp(total(coefficient * value for coefficient, value in zip(beta, representative)))
    for time in times:
        cumulative = hazard_at(hazard, time)
        fields = " ".join(f"{group} {number(exp(-cumulative * risks[group]))}" for group in groups)
        lines.append(f"  at {time} {fields}")
    medians = []
    for group in groups:
        median = next((time for time, cumulative in hazard
                       if exp(-cumulative * risks[group]) <= 0.5), None)
        medians.append(f"{group} {day(median)}")
    lines.append("  median " + " ".join(medians))
    return lines


def cox_lines(subjects, params):
    names = params["covariates"]
    vectors = covariate_vectors(subjects, names)
    model = cox.fit(subjects, vectors)
    final = model["final"]
    covariance = inverse(final["information"])
    events = sum(subject["event"] for subject in subjects)
    lines = [f"cox covariates {' '.join(names)} subjects {len(subjects)} events {events}"
             f" event_times {len(final['event_sums'])}"]
    for iteration, likelihood, beta in model["iterations"]:
        lines.append(f"iter {iteration} loglik {number(likelihood)} beta"
                     f" {' '.join(number(value) for value in beta)}")
    lines.append(f"final loglik {number(final['loglik'])}"
                 f" null_loglik {number(model['null']['loglik'])}")
    lines.extend(coefficient_lines(names, model["beta"], covariance))
    lines.extend(cox_test_lines(subjects, vectors, names, model))
    lines.append(concordance_line(subjects, vectors, final["predictors"]))
    lines.extend(proportional_hazards_lines(subjects, vectors, names, final))
    hazard = baseline_hazard(final)
    lines.extend(residual_lines(subjects, final, hazard, params["residuals"]))
    lines.extend(adjusted_survival_lines(vectors, names, model["beta"], params["groups"],
                                        params["report_times"], hazard))
    return lines


def plot_lines(params, collections, summaries):
    groups = params["groups"]
    width, height, time_limit, divisions = params["plot"]
    estimates = {group: summaries[group]["rows"] for group in groups}
    legend = " ".join(f"{chr(ord('A') + i)} {group}" for i, group in enumerate(groups))
    lines = [f"km_plot width {width} height {height} time {time_limit}", f"legend {legend}"]
    lines.extend(curve_lines(groups, collections, estimates, width, height, time_limit))
    lines.append(f"time 0 to {time_limit} days, {time_limit // width} days per column")
    times = [i * (time_limit // divisions) for i in range(divisions + 1)]
    lines.append("at_risk " + " ".join(map(str, times)))
    for group in groups:
        counts = [sum(subject["time"] >= time for subject in collections[group]) for time in times]
        lines.append(group + " " + " ".join(map(str, counts)))
    return lines


def write_lines(path, lines):
    path.write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")


def join_sections(sections):
    lines = []
    for section in sections:
        if lines:
            lines.append("")
        lines.extend(section)
    return lines


def main():
    subjects, params = read_dataset(Path("input"))
    collections = build_collections(subjects, params["groups"])
    summaries = {name: collection_summary(rows, params) for name, rows in collections.items()}
    output = Path("output")
    output.mkdir(exist_ok=True)
    tables = [km_table_lines(name, rows, summaries[name], params)
              for name, rows in collections.items()]
    write_lines(output / "km_tables.txt", join_sections(tables))
    write_lines(output / "life_table.csv", life_table_lines(summaries))
    comparisons = comparison_sections(subjects, params, collections, summaries)
    write_lines(output / "tests.txt", join_sections(comparisons))
    write_lines(output / "cox.txt", cox_lines(subjects, params))
    write_lines(output / "km_plot.txt", plot_lines(params, collections, summaries))


if __name__ == "__main__":
    main()
