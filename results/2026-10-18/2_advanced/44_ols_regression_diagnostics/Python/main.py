"""Fit the requested regressions and write the five deterministic reports."""

from math import floor, log, sqrt
from pathlib import Path

import dataframe
import diagnostics
from formula import Design, Model
from inference import f_pvalue, four, probability, significance, t_pvalue, t_quantile
from qr_solver import Fit, ordered_sum


def table(header, rows, marks=None):
    rows = [[str(field) for field in row] for row in rows]
    all_rows = [header] + rows
    widths = [max(len(row[column]) for row in all_rows if column < len(row))
              for column in range(len(header))]
    if marks is None:
        marks = [""] * len(rows)
    lines = []
    for row, mark in zip(all_rows, [""] + marks):
        line = row[0].ljust(widths[0])
        for column, field in enumerate(row[1:], 1):
            line += "  " + field.rjust(widths[column])
        if mark:
            line += " " + mark
        lines.append(line.rstrip())
    return lines


def numeric_summary(data, numeric):
    rows = []
    for column in numeric:
        values = [row[column] for row in data.rows if row[column] is not None]
        count = len(values)
        mean = ordered_sum(values) / count
        variance = ordered_sum((value - mean) * (value - mean)
                               for value in values) / (count - 1)
        rows.append([column, count, len(data.rows) - count, four(mean),
                     four(sqrt(variance)), four(min(values)), four(max(values))])
    return table(["column", "n", "missing", "Mean", "SD", "Min", "Max"], rows)


def categorical_summary(data):
    lines = []
    for column in data.columns:
        if data.kinds[column] != "categorical":
            continue
        counts = {}
        present = 0
        for row in data.rows:
            value = row[column]
            if value is not None:
                present += 1
                counts[value] = counts.get(value, 0) + 1
        levels = ", ".join(f"{label} {counts[label]}" for label in sorted(counts))
        lines.append(f"{column}: {present} values, {len(data.rows) - present} missing, "
                     f"{len(counts)} levels: {levels}")
    return lines


def correlations(data, numeric):
    rows = []
    for a in numeric:
        fields = [a]
        for b in numeric:
            pairs = [(row[a], row[b]) for row in data.rows
                     if row[a] is not None and row[b] is not None]
            mean_x = ordered_sum(x for x, y in pairs) / len(pairs)
            mean_y = ordered_sum(y for x, y in pairs) / len(pairs)
            cross = ordered_sum((x - mean_x) * (y - mean_y) for x, y in pairs)
            square_x = ordered_sum((x - mean_x) * (x - mean_x) for x, y in pairs)
            square_y = ordered_sum((y - mean_y) * (y - mean_y) for x, y in pairs)
            fields.append(four(cross / sqrt(square_x * square_y)))
        rows.append(fields)
    return table(["column"] + numeric, rows)


def data_summary(data):
    numeric = [column for column in data.columns if data.kinds[column] == "numeric"]
    lines = [f"Data: {len(data.rows)} rows, {len(data.columns)} columns",
             "", "Numeric columns:"]
    lines.extend(numeric_summary(data, numeric))
    lines.extend(["", "Categorical columns:"])
    lines.extend(categorical_summary(data))
    lines.extend(["", "Correlations (pairwise complete observations):"])
    lines.extend(correlations(data, numeric))
    lines.append("")
    return lines


def information_criteria(fitted):
    n = fitted.n
    log_weights = ordered_sum(log(weight) for weight in fitted.weights)
    likelihood = 0.5 * (log_weights - n * (
        log(2.0 * 3.141592653589793) + 1.0 - log(n) + log(fitted.rss)
    ))
    aic = -2.0 * likelihood + 2.0 * (fitted.rank + 1)
    bic = -2.0 * likelihood + log(n) * (fitted.rank + 1)
    return likelihood, aic, bic


def residual_quantile(values, proportion):
    position = (len(values) - 1) * proportion
    index = floor(position)
    if index + 1 < len(values):
        return values[index] + (position - index) * (values[index + 1] - values[index])
    return values[index]


def model_statistics(fitted, confidence):
    n = fitted.n
    rank = fitted.rank
    degrees = n - rank
    sigma = sqrt(fitted.rss / degrees)
    weight_sum = ordered_sum(fitted.weights)
    mean = ordered_sum(fitted.weights[i] * fitted.response[i]
                       for i in range(n)) / weight_sum
    tss = ordered_sum(fitted.weights[i] * (fitted.response[i] - mean)
                      * (fitted.response[i] - mean) for i in range(n))
    r_squared = 1.0 - fitted.rss / tss
    adjusted = 1.0 - (1.0 - r_squared) * (n - 1) / degrees
    statistic = ((tss - fitted.rss) / (rank - 1)) / (fitted.rss / degrees)
    pvalue = f_pvalue(statistic, rank - 1, degrees)
    likelihood, aic, bic = information_criteria(fitted)
    press = ordered_sum(
        (fitted.weighted_residual[i] / (1.0 - fitted.leverage[i]))
        * (fitted.weighted_residual[i] / (1.0 - fitted.leverage[i]))
        for i in range(n)
    )
    residuals = sorted(fitted.weighted_residual)
    quantiles = [residual_quantile(residuals, proportion)
                 for proportion in (0.0, 0.25, 0.5, 0.75, 1.0)]
    return {"df": degrees, "sigma": sigma, "weight_sum": weight_sum,
            "tss": tss, "r_squared": r_squared, "adjusted": adjusted,
            "f": statistic, "p": pvalue, "ll": likelihood, "aic": aic,
            "bic": bic, "press": press, "predicted": 1.0 - press / tss,
            "quantiles": quantiles, "critical": t_quantile(confidence, degrees)}


def coefficient_inference(fitted, stats):
    accepted = {column: k for k, column in enumerate(fitted.accepted)}
    omega = [fitted.weighted_residual[i] * fitted.weighted_residual[i]
             / ((1.0 - fitted.leverage[i]) * (1.0 - fitted.leverage[i]))
             for i in range(fitted.n)]
    results = []
    for column, estimate in enumerate(fitted.beta):
        if estimate is None:
            results.append(dict.fromkeys(("estimate", "se", "t", "p", "lower",
                                          "upper", "robust_se", "robust_t", "robust_p")))
            continue
        k = accepted[column]
        standard_error = stats["sigma"] * sqrt(fitted.variance[k])
        tvalue = estimate / standard_error
        pvalue = t_pvalue(tvalue, stats["df"])
        half_width = stats["critical"] * standard_error
        robust_error = sqrt(ordered_sum(omega[i] * fitted.g[i][k] * fitted.g[i][k]
                                        for i in range(fitted.n)))
        robust_t = estimate / robust_error
        results.append({"estimate": estimate, "se": standard_error, "t": tvalue,
                        "p": pvalue, "lower": estimate - half_width,
                        "upper": estimate + half_width, "robust_se": robust_error,
                        "robust_t": robust_t, "robust_p": t_pvalue(robust_t, stats["df"])})
    return results


def sequential_anova(design, fitted):
    results = []
    residual_degrees = fitted.n - fitted.rank
    for index, term in enumerate(design.model.terms):
        effects = [k for k, column in enumerate(fitted.accepted)
                   if design.columns[column].term_index == index]
        degrees = len(effects)
        if degrees == 0:
            continue
        squares = ordered_sum(fitted.effects[k] * fitted.effects[k] for k in effects)
        mean_square = squares / degrees
        statistic = mean_square / (fitted.rss / residual_degrees)
        results.append({"name": term.name, "df": degrees, "ss": squares,
                        "ms": mean_square, "f": statistic,
                        "p": f_pvalue(statistic, degrees, residual_degrees)})
    return results


def fit_subset(design, term_indices, tolerance):
    return Fit(design.subset_matrix(term_indices), design.response,
               design.weights, tolerance)


def marginal_tests(design, fitted, term_indices, tolerance):
    results = []
    residual_degrees = fitted.n - fitted.rank
    for index in design.model.removable(term_indices):
        remaining = tuple(other for other in term_indices if other != index)
        reduced = fit_subset(design, remaining, tolerance)
        degrees = fitted.rank - reduced.rank
        squares = reduced.rss - fitted.rss
        statistic = None
        pvalue = None
        if degrees > 0:
            statistic = (squares / degrees) / (fitted.rss / residual_degrees)
            pvalue = f_pvalue(statistic, degrees, residual_degrees)
        results.append({"index": index, "name": design.model.terms[index].name,
                        "df": degrees, "ss": squares, "rss": reduced.rss,
                        "f": statistic, "p": pvalue})
    return results


def variance_inflation(design, fitted, stats, params):
    results = []
    for column in fitted.accepted[1:]:
        response = [row[column] for row in fitted.matrix]
        others = [index for index in fitted.accepted if index != column]
        matrix = [[row[index] for index in others] for row in fitted.matrix]
        auxiliary = Fit(matrix, response, fitted.weights, params["RANK_TOL"])
        mean = ordered_sum(fitted.weights[i] * response[i]
                           for i in range(fitted.n)) / stats["weight_sum"]
        tss = ordered_sum(fitted.weights[i] * (response[i] - mean)
                          * (response[i] - mean) for i in range(fitted.n))
        r_squared = 1.0 - auxiliary.rss / tss
        vif = 1.0 / (1.0 - r_squared)
        results.append((design.columns[column].name, vif, vif > params["VIF"]))
    return results


def reset_test(fitted, tolerance):
    matrix = []
    for i, row in enumerate(fitted.matrix):
        value = fitted.fitted[i]
        matrix.append([row[column] for column in fitted.accepted]
                      + [value * value, value * value * value])
    augmented = Fit(matrix, fitted.response, fitted.weights, tolerance)
    added_degrees = augmented.rank - fitted.rank
    residual_degrees = fitted.n - augmented.rank
    statistic = ((fitted.rss - augmented.rss) / added_degrees) / (
        augmented.rss / residual_degrees
    )
    return statistic, added_degrees, residual_degrees, f_pvalue(
        statistic, added_degrees, residual_degrees
    )


def diagnostic_decisions(design, fitted, diagnostic, params):
    rows = diagnostic["rows"]
    dw = diagnostic["dw"]
    if dw < params["DURBIN_WATSON"]:
        dw_label = "positive autocorrelation"
    elif dw > 4.0 - params["DURBIN_WATSON"]:
        dw_label = "negative autocorrelation"
    else:
        dw_label = "no autocorrelation"
    bp_label = ("heteroscedastic" if diagnostic["bp"][2] < params["BREUSCH_PAGAN"]
                else "homoscedastic")
    jb_label = "non-normal" if diagnostic["jb"][1] < params["NORMALITY"] else "normal"
    outlier = max(range(fitted.n), key=lambda i: abs(rows[i]["studentized"]))
    unadjusted = t_pvalue(rows[outlier]["studentized"], fitted.n - fitted.rank - 1)
    bonferroni = min(1.0, fitted.n * unadjusted)
    largest_cooks = sorted(range(fitted.n), key=lambda i: (-rows[i]["cooks"], i))[:3]
    largest_dfbetas = []
    for k, column in enumerate(fitted.accepted):
        index = max(range(fitted.n), key=lambda i: abs(rows[i]["dfbetas"][k]))
        largest_dfbetas.append((design.columns[column].name, design.row_numbers[index],
                                rows[index]["dfbetas"][k]))
    counts = {flag: sum(flag in row["flags"] for row in rows) for flag in "HOCF"}
    counts["any"] = sum(row["flags"] != "-" for row in rows)
    return {"dw_label": dw_label, "bp_label": bp_label, "jb_label": jb_label,
            "outlier": outlier, "unadjusted": unadjusted, "bonferroni": bonferroni,
            "largest_cooks": largest_cooks, "largest_dfbetas": largest_dfbetas,
            "counts": counts}


def prediction_report(number, design, fitted, stats, prediction_data):
    lines = []
    predicted_count = 0
    actual_count = 0
    covered_count = 0
    squared_errors = 0.0
    for row_number, record in enumerate(prediction_data.rows, 1):
        fields = [str(number), str(row_number)]
        if not design.predictable(record):
            lines.append(",".join(fields + ["NA"] * 9))
            continue
        predicted_count += 1
        values = design.values(record)
        predicted = ordered_sum(values[column] * fitted.beta[column]
                                for column in fitted.accepted)
        u = [ordered_sum(values[fitted.accepted[m]] * fitted.inverse[m][k]
                         for m in range(fitted.rank)) for k in range(fitted.rank)]
        standard_error = stats["sigma"] * sqrt(ordered_sum(value * value for value in u))
        confidence_width = stats["critical"] * standard_error
        prediction_width = stats["critical"] * sqrt(
            stats["sigma"] * stats["sigma"] + standard_error * standard_error
        )
        lower = predicted - prediction_width
        upper = predicted + prediction_width
        fields.extend(four(value) for value in (
            predicted, standard_error, predicted - confidence_width,
            predicted + confidence_width, lower, upper
        ))
        actual = record.get(design.model.response)
        if actual is None:
            fields.extend(["NA", "NA", "NA"])
        else:
            actual_count += 1
            error = actual - predicted
            squared_errors = squared_errors + error * error
            covered = lower <= actual <= upper
            covered_count += int(covered)
            fields.extend([four(actual), four(error), "yes" if covered else "no"])
        lines.append(",".join(fields))
    rmse = sqrt(squared_errors / actual_count) if actual_count else None
    check = (predicted_count, actual_count, rmse, covered_count)
    return lines, check


def analyze_model(number, design, params, prediction_data):
    fitted = Fit(design.matrix, design.response, design.weights, params["RANK_TOL"])
    stats = model_statistics(fitted, params["CONFIDENCE"])
    diagnostic = diagnostics.calculate(fitted, params)
    prediction_lines, prediction_check = prediction_report(
        number, design, fitted, stats, prediction_data
    )
    return {"number": number, "design": design, "fit": fitted, "stats": stats,
            "coefficients": coefficient_inference(fitted, stats),
            "anova": sequential_anova(design, fitted),
            "marginal": marginal_tests(design, fitted,
                                       tuple(range(len(design.model.terms))),
                                       params["RANK_TOL"]),
            "vif": variance_inflation(design, fitted, stats, params),
            "diagnostics": diagnostic,
            "decisions": diagnostic_decisions(design, fitted, diagnostic, params),
            "reset": reset_test(fitted, params["RANK_TOL"]),
            "predictions": prediction_lines, "prediction_check": prediction_check}


def coefficient_tables(report, confidence):
    names = [column.name for column in report["design"].columns]
    coefficients = report["coefficients"]
    rows = [[name, four(coef["estimate"]), four(coef["se"]), four(coef["t"]),
             probability(coef["p"])] for name, coef in zip(names, coefficients)]
    marks = [significance(coef["p"]) for coef in coefficients]
    ordinary = table(["term", "Estimate", "Std. Error", "t value", "Pr(>|t|)"], rows, marks)
    rows = [[name, four(coef["lower"]), four(coef["upper"])]
            for name, coef in zip(names, coefficients)]
    intervals = [f"Confidence intervals (level {four(confidence)}, "
                 f"t {four(report['stats']['critical'])}):"]
    intervals.extend(table(["term", "Lower", "Upper"], rows))
    rows = [[name, four(coef["robust_se"]), four(coef["robust_t"]),
             probability(coef["robust_p"])] for name, coef in zip(names, coefficients)]
    marks = [significance(coef["robust_p"]) for coef in coefficients]
    robust = table(["term", "Std. Error", "t value", "Pr(>|t|)"], rows, marks)
    return ordinary, intervals, robust


def anova_tables(report):
    stats = report["stats"]
    fitted = report["fit"]
    rows = [[entry["name"], entry["df"], four(entry["ss"]), four(entry["ms"]),
             four(entry["f"]), probability(entry["p"])] for entry in report["anova"]]
    marks = [significance(entry["p"]) for entry in report["anova"]]
    rows.append(["Residuals", stats["df"], four(fitted.rss), four(fitted.rss / stats["df"])])
    sequential = table(["term", "Df", "Sum Sq", "Mean Sq", "F value", "Pr(>F)"],
                       rows, marks + [""])
    rows = [[entry["name"], entry["df"], four(entry["ss"]), four(entry["rss"]),
             four(entry["f"]), probability(entry["p"])] for entry in report["marginal"]]
    marks = [significance(entry["p"]) for entry in report["marginal"]]
    marginal = table(["term", "Df", "Sum Sq", "RSS", "F value", "Pr(>F)"], rows, marks)
    return sequential, marginal


def diagnostic_summary(report):
    design = report["design"]
    fitted = report["fit"]
    diagnostic = report["diagnostics"]
    decisions = report["decisions"]
    rows = diagnostic["rows"]
    bp, bp_degrees, bp_pvalue = diagnostic["bp"]
    jb, jb_pvalue, skewness, kurtosis = diagnostic["jb"]
    reset, reset_degrees, reset_residual_df, reset_pvalue = report["reset"]
    outlier = decisions["outlier"]
    counts = decisions["counts"]
    lines = ["Diagnostics:",
             f"Durbin-Watson: {four(diagnostic['dw'])} ({decisions['dw_label']})",
             f"Breusch-Pagan: {four(bp)} on {bp_degrees} DF, "
             f"p-value: {probability(bp_pvalue)} ({decisions['bp_label']})",
             f"Jarque-Bera: {four(jb)} on 2 DF, p-value: {probability(jb_pvalue)}, "
             f"skewness {four(skewness)}, kurtosis {four(kurtosis)} ({decisions['jb_label']})",
             f"RESET (powers 2 and 3): F {four(reset)} on {reset_degrees} and "
             f"{reset_residual_df} DF, p-value: {probability(reset_pvalue)}",
             f"Outlier test: row {design.row_numbers[outlier]}, "
             f"studentized {four(rows[outlier]['studentized'])}, "
             f"unadjusted p-value: {probability(decisions['unadjusted'])}, "
             f"Bonferroni p-value: {probability(decisions['bonferroni'])}",
             f"Flagged rows: leverage {counts['H']}, outlier {counts['O']}, "
             f"cooks {counts['C']}, dffits {counts['F']}, any {counts['any']}",
             "Largest Cook's distances:"]
    for i in decisions["largest_cooks"]:
        lines.append(f"row {design.row_numbers[i]}: cooks_d {four(rows[i]['cooks'])}, "
                     f"leverage {four(fitted.leverage[i])}, "
                     f"studentized {four(rows[i]['studentized'])}, flags {rows[i]['flags']}")
    lines.append("Largest absolute DFBETAS:")
    lines.extend(table(["column", "row", "DFBETAS"],
                       [[name, row_number, four(value)]
                        for name, row_number, value in decisions["largest_dfbetas"]]))
    return lines


def model_summary(report, total_rows, confidence):
    design = report["design"]
    fitted = report["fit"]
    stats = report["stats"]
    aliases = ", ".join(design.columns[j].name for j in fitted.aliases) or "none"
    quantiles = stats["quantiles"]
    coefficients, intervals, robust = coefficient_tables(report, confidence)
    sequential, marginal = anova_tables(report)
    lines = [f"Model {report['number']}: {design.model.original}",
             "Terms: " + ", ".join(term.name for term in design.model.terms),
             f"Weights: {design.model.weight or 'none'}",
             f"Observations: {fitted.n} used, {total_rows - fitted.n} dropped",
             f"Columns: {fitted.p}, rank {fitted.rank}, aliased: {aliases}", "",
             f"Residuals: Min {four(quantiles[0])}, 1Q {four(quantiles[1])}, "
             f"Median {four(quantiles[2])}, 3Q {four(quantiles[3])}, Max {four(quantiles[4])}",
             "", "Coefficients:"]
    lines.extend(coefficients)
    lines.extend(["---", "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1", "",
                  f"Residual standard error: {four(stats['sigma'])} on {stats['df']} degrees of freedom",
                  f"Multiple R-squared: {four(stats['r_squared'])}, "
                  f"Adjusted R-squared: {four(stats['adjusted'])}",
                  f"F-statistic: {four(stats['f'])} on {fitted.rank - 1} and "
                  f"{stats['df']} DF, p-value: {probability(stats['p'])}",
                  f"Log-likelihood: {four(stats['ll'])}, AIC: {four(stats['aic'])}, BIC: {four(stats['bic'])}",
                  f"PRESS: {four(stats['press'])}, Predicted R-squared: {four(stats['predicted'])}", ""])
    lines.extend(intervals)
    lines.extend(["", "Robust standard errors (HC3):"])
    lines.extend(robust)
    lines.extend(["", "Analysis of variance (sequential):"])
    lines.extend(sequential)
    lines.extend(["", "Marginal F tests (drop one term):"])
    lines.extend(marginal)
    lines.extend(["", "Variance inflation factors:"])
    lines.extend(table(["column", "VIF"], [[name, four(value)]
                                          for name, value, high in report["vif"]],
                       ["high" if high else "" for name, value, high in report["vif"]]))
    lines.append("")
    lines.extend(diagnostic_summary(report))
    return lines


def comparison_summary(reports):
    rows = []
    for report in reports:
        fitted = report["fit"]
        stats = report["stats"]
        rows.append([report["number"], fitted.n, fitted.rank, four(stats["sigma"]),
                     four(stats["r_squared"]), four(stats["adjusted"]),
                     four(stats["predicted"]), four(stats["aic"]), four(stats["bic"])])
    return table(["model", "n", "rank", "sigma", "R-squared", "Adj. R-squared",
                  "Pred. R-squared", "AIC", "BIC"], rows)


def summary_report(data, reports, params):
    lines = data_summary(data)
    for index, report in enumerate(reports):
        if index:
            lines.append("")
        lines.extend(model_summary(report, len(data.rows), params["CONFIDENCE"]))
    lines.extend(["", "Model comparison:"])
    lines.extend(comparison_summary(reports))
    lines.extend(["", "Prediction check:"])
    for report in reports:
        predicted, actual, rmse, covered = report["prediction_check"]
        lines.append(f"model {report['number']}: {predicted} predicted, "
                     f"{actual} with actual values, RMSE {four(rmse)}, "
                     f"inside prediction interval {covered}")
    return lines


def diagnostics_csv(reports):
    lines = ["model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags"]
    for report in reports:
        fitted = report["fit"]
        for i, row in enumerate(report["diagnostics"]["rows"]):
            fields = [str(report["number"]), str(report["design"].row_numbers[i])]
            fields.extend(four(value) for value in (
                fitted.fitted[i], fitted.residual[i], fitted.leverage[i],
                row["studentized"], row["cooks"], row["dffits"]
            ))
            lines.append(",".join(fields + [row["flags"]]))
    return lines


def backward_selection(report, params):
    design = report["design"]
    model = design.model
    terms = tuple(range(len(model.terms)))
    alpha = params["ALPHA_REMOVE"]
    lines = [f"Backward elimination (model 1, alpha {four(alpha)}, rows {len(design.rows)})"]
    step = 1
    fitted = report["fit"]
    while True:
        _, aic, _ = information_criteria(fitted)
        degrees = fitted.n - fitted.rank
        lines.append(f"Step {step}: {model.format(terms)} "
                     f"(RSS {four(fitted.rss)}, df {degrees}, AIC {four(aic)})")
        if not terms:
            lines.append("  stop: no removable terms")
            break
        tests = marginal_tests(design, fitted, terms, params["RANK_TOL"])
        for test in tests:
            lines.append(f"  - {test['name']}: F {four(test['f'])} on {test['df']} "
                         f"and {degrees} DF, p-value {probability(test['p'])}")
        largest = max(tests, key=lambda test: test["p"])
        if largest["p"] <= alpha:
            lines.append(f"  stop: largest p-value {probability(largest['p'])} "
                         f"is not above {four(alpha)}")
            break
        lines.append(f"  remove {largest['name']}")
        terms = tuple(index for index in terms if index != largest["index"])
        fitted = fit_subset(design, terms, params["RANK_TOL"])
        step += 1
    lines.append(f"Final model: {model.format(terms)}")
    return lines


def forward_selection(report, params):
    design = report["design"]
    model = design.model
    terms = ()
    lines = [f"Forward selection by AIC (model 1, rows {len(design.rows)})"]
    step = 1
    while True:
        fitted = fit_subset(design, terms, params["RANK_TOL"])
        _, aic, _ = information_criteria(fitted)
        lines.append(f"Step {step}: {model.format(terms)} (AIC {four(aic)})")
        candidates = model.candidates(terms)
        if not candidates:
            lines.append("  stop: no candidate terms remain")
            break
        choices = []
        for index in candidates:
            candidate_terms = tuple(sorted(terms + (index,)))
            candidate = fit_subset(design, candidate_terms, params["RANK_TOL"])
            _, candidate_aic, _ = information_criteria(candidate)
            choices.append((index, candidate_aic, candidate_terms))
            lines.append(f"  + {model.terms[index].name}: AIC {four(candidate_aic)}")
        index, candidate_aic, candidate_terms = min(choices, key=lambda choice: choice[1])
        if candidate_aic >= aic:
            lines.append("  stop: no candidate lowers the AIC")
            break
        lines.append(f"  add {model.terms[index].name}")
        terms = candidate_terms
        step += 1
    lines.append(f"Final model: {model.format(terms)}")
    return lines


def best_subsets(report, params):
    design = report["design"]
    model = design.model
    count = len(model.terms)
    subsets = []
    for mask in range(1 << count):
        terms = tuple(index for index in range(count) if mask & (1 << index))
        if not model.hierarchical(terms):
            continue
        fitted = fit_subset(design, terms, params["RANK_TOL"])
        _, aic, bic = information_criteria(fitted)
        subsets.append((bic, mask, aic, fitted.rank, terms))
    subsets.sort(key=lambda subset: (subset[0], subset[1]))
    lines = [f"Best subsets by BIC (model 1, rows {len(design.rows)}, subsets {len(subsets)})"]
    for position, (bic, mask, aic, rank, terms) in enumerate(subsets[:params["BEST_SUBSETS"]], 1):
        lines.append(f"{position}. BIC {four(bic)}, AIC {four(aic)}, rank {rank}: "
                     f"{model.format(terms)}")
    return lines


def selection_report(report, params):
    return (backward_selection(report, params) + [""]
            + forward_selection(report, params) + [""] + best_subsets(report, params))


def plot_grid(horizontal, vertical, lo, hi, width, height, limit):
    grid = [[0] * width for _ in range(height)]
    for x, y in zip(horizontal, vertical):
        column = min(floor((x - lo) / (hi - lo) * width), width - 1)
        row = floor((limit - y) / (2.0 * limit) * height)
        row = max(0, min(row, height - 1))
        grid[row][column] += 1
    return grid


def plot_frame(grid):
    width = len(grid[0])
    border = "+" + "-" * width + "+"
    lines = [border]
    for index, row in enumerate(grid):
        empty = "-" if index == len(grid) // 2 else "."
        cells = ["*" if count >= 10 else str(count) if count else empty for count in row]
        lines.append("|" + "".join(cells) + "|")
    lines.append(border)
    return lines


def residual_plot(report, params):
    width, height, limit = params["PLOT"]
    number = report["number"]
    fitted = report["fit"]
    studentized = [row["studentized"] for row in report["diagnostics"]["rows"]]
    lo = min(fitted.fitted)
    hi = max(fitted.fitted)
    grid = plot_grid(fitted.fitted, studentized, lo, hi, width, height, limit)
    lines = [f"Model {number}: studentized residuals vs fitted values",
             f"fitted {four(lo)} to {four(hi)}, studentized {four(-limit)} to {four(limit)}"]
    lines.extend(plot_frame(grid))
    above = sum(value > 2.0 for value in studentized)
    below = sum(value < -2.0 for value in studentized)
    outside = sum(abs(value) > limit for value in studentized)
    lines.append(f"points: {fitted.n}, above +2: {above}, below -2: {below}, outside range: {outside}")
    lines.append("Histogram of studentized residuals:")
    counts = [sum(row) for row in grid]
    maximum = max(counts)
    for index, count in enumerate(counts):
        lower = limit - 2.0 * limit * (index + 1) / height
        upper = limit - 2.0 * limit * index / height
        length = (count * 40 + maximum - 1) // maximum
        line = f"{four(lower)} to {four(upper)}: {count}"
        if length:
            line += " " + "#" * length
        lines.append(line)
    hi = max(fitted.leverage)
    lines.extend([f"Model {number}: studentized residuals vs leverage",
                  f"leverage 0.0000 to {four(hi)}, studentized {four(-limit)} to {four(limit)}"])
    grid = plot_grid(fitted.leverage, studentized, 0.0, hi, width, height, limit)
    lines.extend(plot_frame(grid))
    return lines


def predictions_csv(reports):
    lines = ["model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered"]
    for report in reports:
        lines.extend(report["predictions"])
    return lines


def plots_report(reports, params):
    lines = []
    for index, report in enumerate(reports):
        if index:
            lines.append("")
        lines.extend(residual_plot(report, params))
    return lines


def write_reports(contents):
    for filename, lines in contents.items():
        Path("output", filename).write_text("\n".join(lines) + "\n",
                                             encoding="ascii", newline="\n")


def main():
    data = dataframe.read_csv(Path("input", "data.csv"))
    model_lines = dataframe.read_models(Path("input", "model.txt"))
    prediction_data = dataframe.read_csv(Path("input", "predict.csv"), data.kinds)
    params = dataframe.read_params(Path("input", "params.txt"))
    reports = []
    for number, line in enumerate(model_lines, 1):
        design = Design(Model(line), data)
        reports.append(analyze_model(number, design, params, prediction_data))
    write_reports({"summary.txt": summary_report(data, reports, params),
                   "diagnostics.csv": diagnostics_csv(reports),
                   "selection.txt": selection_report(reports[0], params),
                   "predictions.csv": predictions_csv(reports),
                   "residual_plot.txt": plots_report(reports, params)})


if __name__ == "__main__":
    main()
