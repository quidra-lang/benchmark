#include "regression.hpp"
#include <filesystem>
static std::string number(int value) {
    return std::to_string(value);
}
static std::string join(const Lines &values, const std::string &separator) {
    std::string out;
    for (const std::string &value : values) {
        if (!out.empty())
            out += separator;
        out += value;
    }
    return out;
}
static void extend(Lines &out, const Lines &lines) {
    out.insert(out.end(), lines.begin(), lines.end());
}
struct TableRow {
    Lines fields;
    std::string mark;
};
static Lines table(const Lines &header, const std::vector<TableRow> &rows) {
    std::vector<std::size_t> widths(header.size());
    for (std::size_t j = 0; j < header.size(); ++j)
        widths[j] = header[j].size();
    for (const TableRow &row : rows)
        for (std::size_t j = 0; j < row.fields.size(); ++j)
            widths[j] = std::max(widths[j], row.fields[j].size());
    auto render = [&](const TableRow &row) {
        std::string out;
        for (std::size_t j = 0; j < row.fields.size(); ++j) {
            if (j == 0)
                out = row.fields[j] + std::string(widths[j] - row.fields[j].size(), ' ');
            else
                out += "  " + std::string(widths[j] - row.fields[j].size(), ' ') + row.fields[j];
        }
        if (!row.mark.empty())
            out += " " + row.mark;
        while (!out.empty() && out.back() == ' ')
            out.pop_back();
        return out;
    };
    Lines out = {render({header, ""})};
    for (const TableRow &row : rows)
        out.push_back(render(row));
    return out;
}
struct Statistics {
    int n = 0, df = 0;
    double sigma = 0, tss = 0, r2 = 0, adjusted = 0, f = 0, f_p = 1, loglik = 0, aic = 0, bic = 0, press = 0,
           predicted = 0, critical = 0;
    std::array<double, 5> quantiles{};
};
static Statistics statistics(const Vector &y, const Vector &weights, const Fit &model, const Params &p) {
    Statistics out;
    out.n = y.size();
    out.df = out.n - model.rank;
    out.sigma = std::sqrt(model.rss / out.df);
    double weight_sum = 0, response_sum = 0, log_weights = 0;
    for (std::size_t i = 0; i < y.size(); ++i) {
        weight_sum += weights[i];
        response_sum += weights[i] * y[i];
        log_weights += std::log(weights[i]);
    }
    const double mean = response_sum / weight_sum;
    for (std::size_t i = 0; i < y.size(); ++i)
        out.tss += weights[i] * (y[i] - mean) * (y[i] - mean);
    out.r2 = 1 - model.rss / out.tss;
    out.adjusted = 1 - (1 - out.r2) * (out.n - 1) / out.df;
    if (model.rank > 1) {
        out.f = ((out.tss - model.rss) / (model.rank - 1)) / (model.rss / out.df);
        out.f_p = p_f(out.f, model.rank - 1, out.df);
    }
    out.loglik = 0.5 * (log_weights - out.n * (std::log(2 * 3.141592653589793) + 1 - std::log(double(out.n)) +
                                               std::log(model.rss)));
    out.aic = -2 * out.loglik + 2 * (model.rank + 1);
    out.bic = -2 * out.loglik + std::log(double(out.n)) * (model.rank + 1);
    for (std::size_t i = 0; i < y.size(); ++i) {
        const double value = model.weighted_residuals[i] / (1 - model.leverage[i]);
        out.press += value * value;
    }
    out.predicted = 1 - out.press / out.tss;
    Vector residuals = model.weighted_residuals;
    std::sort(residuals.begin(), residuals.end());
    for (int q = 0; q < 5; ++q) {
        const double g = (out.n - 1) * (double(q) / 4);
        const int k = int(std::floor(g));
        out.quantiles[q] =
            k + 1 < out.n ? residuals[k] + (g - k) * (residuals[k + 1] - residuals[k]) : residuals[k];
    }
    out.critical = t_quantile(p.confidence, out.df);
    return out;
}
struct SubsetFit {
    Fit model;
    Statistics stats;
};
static Matrix columns(const Matrix &matrix, const std::vector<int> &indices) {
    Matrix out(matrix.size(), Vector(indices.size()));
    for (std::size_t i = 0; i < matrix.size(); ++i)
        for (std::size_t j = 0; j < indices.size(); ++j)
            out[i][j] = matrix[i][indices[j]];
    return out;
}
static SubsetFit fit_subset(const Design &design, const std::vector<int> &terms, const Params &p) {
    SubsetFit out;
    out.model = fit(columns(design.x, selected_columns(design, terms)), design.y, design.weights, p.rank_tol);
    out.stats = statistics(design.y, design.weights, out.model, p);
    return out;
}
struct Marginal {
    int term = 0, degrees = 0;
    double ss = 0, rss = 0, f = 0, p = 0;
};
static std::vector<Marginal> marginal(const Design &design, const std::vector<int> &terms, const Fit &model,
                                      const Statistics &stats, const Params &p) {
    std::vector<Marginal> out;
    for (int term : terms) {
        bool removable = true;
        for (int other : terms)
            if (contained(design.formula.terms[term], design.formula.terms[other]))
                removable = false;
        if (!removable)
            continue;
        std::vector<int> remaining;
        for (int other : terms)
            if (other != term)
                remaining.push_back(other);
        const SubsetFit smaller = fit_subset(design, remaining, p);
        Marginal test;
        test.term = term;
        test.degrees = model.rank - smaller.model.rank;
        test.rss = smaller.model.rss;
        test.ss = test.rss - model.rss;
        if (test.degrees > 0) {
            test.f = (test.ss / test.degrees) / (model.rss / stats.df);
            test.p = p_f(test.f, test.degrees, stats.df);
        }
        out.push_back(test);
    }
    return out;
}
static Lines data_summary(const Dataframe &data) {
    Lines out = {"Data: " + number(data.rows.size()) + " rows, " + number(data.names.size()) + " columns", "",
                 "Numeric columns:"};
    std::vector<int> numeric;
    std::vector<TableRow> rows;
    for (std::size_t j = 0; j < data.names.size(); ++j)
        if (!data.categorical[j]) {
            numeric.push_back(j);
            Vector values;
            double sum = 0;
            for (const Record &row : data.rows)
                if (!row[j].missing) {
                    values.push_back(row[j].number);
                    sum += row[j].number;
                }
            const double mean = sum / values.size();
            double squares = 0;
            for (double value : values)
                squares += (value - mean) * (value - mean);
            rows.push_back({{data.names[j], number(values.size()), number(data.rows.size() - values.size()),
                             real(mean), real(std::sqrt(squares / (values.size() - 1))),
                             real(*std::min_element(values.begin(), values.end())),
                             real(*std::max_element(values.begin(), values.end()))},
                            ""});
        }
    extend(out, table({"column", "n", "missing", "Mean", "SD", "Min", "Max"}, rows));
    out.push_back("");
    out.push_back("Categorical columns:");
    for (std::size_t j = 0; j < data.names.size(); ++j)
        if (data.categorical[j]) {
            std::map<std::string, int> counts;
            int present = 0;
            for (const Record &row : data.rows)
                if (!row[j].missing) {
                    ++counts[row[j].label];
                    ++present;
                }
            Lines levels;
            for (const auto &entry : counts)
                levels.push_back(entry.first + " " + number(entry.second));
            out.push_back(data.names[j] + ": " + number(present) + " values, " +
                          number(data.rows.size() - present) + " missing, " + number(counts.size()) +
                          " levels: " + join(levels, ", "));
        }
    out.push_back("");
    out.push_back("Correlations (pairwise complete observations):");
    Lines header = {"column"};
    for (int column : numeric)
        header.push_back(data.names[column]);
    rows.clear();
    for (int a : numeric) {
        Lines fields = {data.names[a]};
        for (int b : numeric) {
            std::vector<std::pair<double, double>> pairs;
            double sum_x = 0, sum_y = 0;
            for (const Record &row : data.rows)
                if (!row[a].missing && !row[b].missing) {
                    pairs.push_back({row[a].number, row[b].number});
                    sum_x += row[a].number;
                    sum_y += row[b].number;
                }
            const double mean_x = sum_x / pairs.size(), mean_y = sum_y / pairs.size();
            double xy = 0, xx = 0, yy = 0;
            for (const auto &pair : pairs) {
                const double x = pair.first - mean_x, y = pair.second - mean_y;
                xy += x * y;
                xx += x * x;
                yy += y * y;
            }
            fields.push_back(real(xy / std::sqrt(xx * yy)));
        }
        rows.push_back({fields, ""});
    }
    extend(out, table(header, rows));
    out.push_back("");
    return out;
}
struct Model {
    Design design;
    Fit fit_;
    Statistics stats;
    Diagnostics diag;
    std::vector<int> terms;
    std::vector<Marginal> drops;
    int predicted = 0, with_actual = 0, covered = 0;
    double error_squares = 0;
};
static Lines model_summary(Model &model, const Input &input, int index) {
    const Design &design = model.design;
    const Fit &fit_ = model.fit_;
    const Statistics &stats = model.stats;
    const Diagnostics &diag = model.diag;
    const int n = design.y.size(), rank = fit_.rank;
    Lines terms, aliases;
    for (const Term &term : design.formula.terms)
        terms.push_back(term.name);
    for (std::size_t j = 0; j < design.columns.size(); ++j)
        if (fit_.alias[j])
            aliases.push_back(design.columns[j].name);
    Lines out = {"Model " + number(index) + ": " + design.formula.raw,
                 "Terms: " + join(terms, ", "),
                 "Weights: " + (design.formula.weight < 0 ? "none" : input.data.names[design.formula.weight]),
                 "Observations: " + number(n) + " used, " + number(input.data.rows.size() - n) + " dropped",
                 "Columns: " + number(design.columns.size()) + ", rank " + number(rank) +
                     ", aliased: " + (aliases.empty() ? "none" : join(aliases, ", ")),
                 "",
                 "Residuals: Min " + real(stats.quantiles[0]) + ", 1Q " + real(stats.quantiles[1]) +
                     ", Median " + real(stats.quantiles[2]) + ", 3Q " + real(stats.quantiles[3]) + ", Max " +
                     real(stats.quantiles[4]),
                 "",
                 "Coefficients:"};
    Vector standard_errors(design.columns.size()), robust(design.columns.size());
    std::vector<int> accepted_index(design.columns.size(), -1);
    for (int k = 0; k < rank; ++k) {
        const int j = fit_.accepted[k];
        accepted_index[j] = k;
        standard_errors[j] = stats.sigma * std::sqrt(fit_.variance[k]);
        double sum = 0;
        for (int i = 0; i < n; ++i) {
            const double h = fit_.leverage[i], eps = fit_.weighted_residuals[i],
                         omega = eps * eps / ((1 - h) * (1 - h));
            sum += omega * fit_.g[i][k] * fit_.g[i][k];
        }
        robust[j] = std::sqrt(sum);
    }
    std::vector<TableRow> rows;
    for (std::size_t j = 0; j < design.columns.size(); ++j) {
        if (fit_.alias[j])
            rows.push_back({{design.columns[j].name, "NA", "NA", "NA", "NA"}, ""});
        else {
            const double t = fit_.coefficients[j] / standard_errors[j], p = p_t(t, stats.df);
            rows.push_back({{design.columns[j].name, real(fit_.coefficients[j]), real(standard_errors[j]),
                             real(t), p_format(p)},
                            significance(p)});
        }
    }
    extend(out, table({"term", "Estimate", "Std. Error", "t value", "Pr(>|t|)"}, rows));
    extend(
        out,
        {"---", "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1", "",
         "Residual standard error: " + real(stats.sigma) + " on " + number(stats.df) + " degrees of freedom",
         "Multiple R-squared: " + real(stats.r2) + ", Adjusted R-squared: " + real(stats.adjusted),
         "F-statistic: " + real(stats.f) + " on " + number(rank - 1) + " and " + number(stats.df) +
             " DF, p-value: " + p_format(stats.f_p),
         "Log-likelihood: " + real(stats.loglik) + ", AIC: " + real(stats.aic) + ", BIC: " + real(stats.bic),
         "PRESS: " + real(stats.press) + ", Predicted R-squared: " + real(stats.predicted), "",
         "Confidence intervals (level " + real(input.params.confidence) + ", t " + real(stats.critical) +
             "):"});
    rows.clear();
    for (std::size_t j = 0; j < design.columns.size(); ++j)
        rows.push_back(
            {{design.columns[j].name,
              fit_.alias[j] ? "NA" : real(fit_.coefficients[j] - stats.critical * standard_errors[j]),
              fit_.alias[j] ? "NA" : real(fit_.coefficients[j] + stats.critical * standard_errors[j])},
             ""});
    extend(out, table({"term", "Lower", "Upper"}, rows));
    extend(out, {"", "Robust standard errors (HC3):"});
    rows.clear();
    for (std::size_t j = 0; j < design.columns.size(); ++j) {
        if (fit_.alias[j])
            rows.push_back({{design.columns[j].name, "NA", "NA", "NA"}, ""});
        else {
            const double t = fit_.coefficients[j] / robust[j], p = p_t(t, stats.df);
            rows.push_back(
                {{design.columns[j].name, real(robust[j]), real(t), p_format(p)}, significance(p)});
        }
    }
    extend(out, table({"term", "Std. Error", "t value", "Pr(>|t|)"}, rows));
    extend(out, {"", "Analysis of variance (sequential):"});
    rows.clear();
    for (std::size_t term = 0; term < design.formula.terms.size(); ++term) {
        int degrees = 0;
        double sum = 0;
        for (int k = 0; k < rank; ++k)
            if (design.columns[fit_.accepted[k]].term == int(term)) {
                ++degrees;
                sum += fit_.effects[k] * fit_.effects[k];
            }
        if (!degrees)
            continue;
        const double mean = sum / degrees, f = mean / (fit_.rss / stats.df), p = p_f(f, degrees, stats.df);
        rows.push_back(
            {{design.formula.terms[term].name, number(degrees), real(sum), real(mean), real(f), p_format(p)},
             significance(p)});
    }
    rows.push_back({{"Residuals", number(stats.df), real(fit_.rss), real(fit_.rss / stats.df)}, ""});
    extend(out, table({"term", "Df", "Sum Sq", "Mean Sq", "F value", "Pr(>F)"}, rows));
    extend(out, {"", "Marginal F tests (drop one term):"});
    rows.clear();
    for (const Marginal &drop : model.drops)
        rows.push_back(
            {{design.formula.terms[drop.term].name, number(drop.degrees), real(drop.ss), real(drop.rss),
              drop.degrees ? real(drop.f) : "NA", drop.degrees ? p_format(drop.p) : "NA"},
             drop.degrees ? significance(drop.p) : ""});
    extend(out, table({"term", "Df", "Sum Sq", "RSS", "F value", "Pr(>F)"}, rows));
    extend(out, {"", "Variance inflation factors:"});
    rows.clear();
    for (int k = 1; k < rank; ++k) {
        const int target = fit_.accepted[k];
        std::vector<int> other;
        for (int column : fit_.accepted)
            if (column != target)
                other.push_back(column);
        Vector response(n);
        double weighted_sum = 0, weight_sum = 0;
        for (int i = 0; i < n; ++i) {
            response[i] = design.x[i][target];
            weighted_sum += design.weights[i] * response[i];
            weight_sum += design.weights[i];
        }
        const Fit auxiliary = fit(columns(design.x, other), response, design.weights, input.params.rank_tol);
        const double mean = weighted_sum / weight_sum;
        double tss = 0;
        for (int i = 0; i < n; ++i)
            tss += design.weights[i] * (response[i] - mean) * (response[i] - mean);
        const double r2 = 1 - auxiliary.rss / tss, vif = 1 / (1 - r2);
        rows.push_back({{design.columns[target].name, real(vif)}, vif > input.params.vif ? "high" : ""});
    }
    extend(out, table({"column", "VIF"}, rows));
    extend(out, {"", "Diagnostics:",
                 "Durbin-Watson: " + real(diag.durbin) + " (" +
                     (diag.durbin < input.params.durbin       ? "positive autocorrelation"
                      : diag.durbin > 4 - input.params.durbin ? "negative autocorrelation"
                                                              : "no autocorrelation") +
                     ")",
                 "Breusch-Pagan: " + real(diag.bp) + " on " + number(diag.bp_df) +
                     " DF, p-value: " + p_format(diag.bp_p) + " (" +
                     (diag.bp_p < input.params.breusch ? "heteroscedastic" : "homoscedastic") + ")",
                 "Jarque-Bera: " + real(diag.jb) + " on 2 DF, p-value: " + p_format(diag.jb_p) +
                     ", skewness " + real(diag.skewness) + ", kurtosis " + real(diag.kurtosis) + " (" +
                     (diag.jb_p < input.params.normality ? "non-normal" : "normal") + ")"});
    Matrix augmented = columns(design.x, fit_.accepted);
    for (int i = 0; i < n; ++i) {
        augmented[i].push_back(fit_.fitted[i] * fit_.fitted[i]);
        augmented[i].push_back(fit_.fitted[i] * fit_.fitted[i] * fit_.fitted[i]);
    }
    const Fit reset = fit(augmented, design.y, design.weights, input.params.rank_tol);
    const int q = reset.rank - rank, df = n - reset.rank;
    const double reset_f = ((fit_.rss - reset.rss) / q) / (reset.rss / df);
    out.push_back("RESET (powers 2 and 3): F " + real(reset_f) + " on " + number(q) + " and " + number(df) +
                  " DF, p-value: " + p_format(p_f(reset_f, q, df)));
    int outlier = 0;
    for (int i = 1; i < n; ++i)
        if (std::abs(diag.studentized[i]) > std::abs(diag.studentized[outlier]))
            outlier = i;
    const double unadjusted = p_t(diag.studentized[outlier], stats.df - 1);
    out.push_back("Outlier test: row " + number(design.used[outlier] + 1) + ", studentized " +
                  real(diag.studentized[outlier]) + ", unadjusted p-value: " + p_format(unadjusted) +
                  ", Bonferroni p-value: " + p_format(std::min(1.0, n * unadjusted)));
    out.push_back("Flagged rows: leverage " + number(diag.flag_counts[0]) + ", outlier " +
                  number(diag.flag_counts[1]) + ", cooks " + number(diag.flag_counts[2]) + ", dffits " +
                  number(diag.flag_counts[3]) + ", any " + number(diag.any));
    out.push_back("Largest Cook's distances:");
    std::vector<int> order(n);
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [&](int a, int b) {
        return diag.cooks[a] != diag.cooks[b] ? diag.cooks[a] > diag.cooks[b] : a < b;
    });
    for (int index_ = 0; index_ < std::min(3, n); ++index_) {
        const int i = order[index_];
        out.push_back("row " + number(design.used[i] + 1) + ": cooks_d " + real(diag.cooks[i]) +
                      ", leverage " + real(fit_.leverage[i]) + ", studentized " + real(diag.studentized[i]) +
                      ", flags " + diag.flags[i]);
    }
    out.push_back("Largest absolute DFBETAS:");
    rows.clear();
    for (int k = 0; k < rank; ++k) {
        int largest = 0;
        for (int i = 1; i < n; ++i)
            if (std::abs(diag.dfbetas[i][k]) > std::abs(diag.dfbetas[largest][k]))
                largest = i;
        rows.push_back({{design.columns[fit_.accepted[k]].name, number(design.used[largest] + 1),
                         real(diag.dfbetas[largest][k])},
                        ""});
    }
    extend(out, table({"column", "row", "DFBETAS"}, rows));
    return out;
}
static Lines prediction_lines(Model &model, const Dataframe &prediction, int index) {
    Lines out;
    const Fit &fit_ = model.fit_;
    const Statistics &stats = model.stats;
    for (std::size_t i = 0; i < prediction.rows.size(); ++i) {
        const Record &record = prediction.rows[i];
        const std::string prefix = number(index) + "," + number(i + 1);
        if (!predictable(model.design, record)) {
            out.push_back(prefix + ",NA,NA,NA,NA,NA,NA,NA,NA,NA");
            continue;
        }
        ++model.predicted;
        const Vector values = record_values(model.design.columns, record);
        double value = 0;
        for (int k = 0; k < fit_.rank; ++k)
            value += values[fit_.accepted[k]] * fit_.coefficients[fit_.accepted[k]];
        double squares = 0;
        for (int k = 0; k < fit_.rank; ++k) {
            double sum = 0;
            for (int m = 0; m < fit_.rank; ++m)
                sum += values[fit_.accepted[m]] * fit_.inverse[m][k];
            squares += sum * sum;
        }
        const double se = stats.sigma * std::sqrt(squares), confidence = stats.critical * se,
                     interval = stats.critical * std::sqrt(stats.sigma * stats.sigma + se * se);
        std::string line = prefix + "," + real(value) + "," + real(se) + "," + real(value - confidence) +
                           "," + real(value + confidence) + "," + real(value - interval) + "," +
                           real(value + interval);
        if (record[model.design.formula.response].missing)
            line += ",NA,NA,NA";
        else {
            ++model.with_actual;
            const double actual = record[model.design.formula.response].number, error = actual - value;
            const bool covered = value - interval <= actual && actual <= value + interval;
            model.covered += covered;
            model.error_squares += error * error;
            line += "," + real(actual) + "," + real(error) + "," + (covered ? "yes" : "no");
        }
        out.push_back(line);
    }
    return out;
}
static Lines selection(const Model &model, const Input &input) {
    const Design &design = model.design;
    const Params &p = input.params;
    std::vector<int> terms = model.terms;
    Lines out = {"Backward elimination (model 1, alpha " + real(p.alpha) + ", rows " +
                 number(design.y.size()) + ")"};
    int step = 1;
    while (true) {
        const SubsetFit current = fit_subset(design, terms, p);
        out.push_back("Step " + number(step) + ": " + formula_text(design.formula, terms, input.data) +
                      " (RSS " + real(current.model.rss) + ", df " + number(current.stats.df) + ", AIC " +
                      real(current.stats.aic) + ")");
        if (terms.empty()) {
            out.push_back("  stop: no removable terms");
            break;
        }
        const auto drops = marginal(design, terms, current.model, current.stats, p);
        int selected = -1;
        double largest = -1;
        for (const Marginal &drop : drops) {
            out.push_back("  - " + design.formula.terms[drop.term].name + ": F " + real(drop.f) + " on " +
                          number(drop.degrees) + " and " + number(current.stats.df) + " DF, p-value " +
                          p_format(drop.p));
            if (drop.p > largest) {
                largest = drop.p;
                selected = drop.term;
            }
        }
        if (largest > p.alpha) {
            out.push_back("  remove " + design.formula.terms[selected].name);
            terms.erase(std::find(terms.begin(), terms.end(), selected));
            ++step;
        } else {
            out.push_back("  stop: largest p-value " + p_format(largest) + " is not above " + real(p.alpha));
            break;
        }
    }
    out.push_back("Final model: " + formula_text(design.formula, terms, input.data));
    extend(out, {"", "Forward selection by AIC (model 1, rows " + number(design.y.size()) + ")"});
    terms.clear();
    step = 1;
    while (true) {
        const SubsetFit current = fit_subset(design, terms, p);
        out.push_back("Step " + number(step) + ": " + formula_text(design.formula, terms, input.data) +
                      " (AIC " + real(current.stats.aic) + ")");
        std::vector<int> candidates;
        for (std::size_t term = 0; term < design.formula.terms.size(); ++term)
            if (std::find(terms.begin(), terms.end(), term) == terms.end()) {
                bool eligible = true;
                for (std::size_t other = 0; other < design.formula.terms.size(); ++other)
                    if (contained(design.formula.terms[other], design.formula.terms[term]) &&
                        std::find(terms.begin(), terms.end(), other) == terms.end())
                        eligible = false;
                if (eligible)
                    candidates.push_back(term);
            }
        if (candidates.empty()) {
            out.push_back("  stop: no candidate terms remain");
            break;
        }
        int selected = -1;
        double smallest = 0;
        for (int candidate : candidates) {
            std::vector<int> trial = terms;
            trial.push_back(candidate);
            std::sort(trial.begin(), trial.end());
            const double aic = fit_subset(design, trial, p).stats.aic;
            out.push_back("  + " + design.formula.terms[candidate].name + ": AIC " + real(aic));
            if (selected < 0 || aic < smallest) {
                selected = candidate;
                smallest = aic;
            }
        }
        if (smallest < current.stats.aic) {
            out.push_back("  add " + design.formula.terms[selected].name);
            terms.push_back(selected);
            std::sort(terms.begin(), terms.end());
            ++step;
        } else {
            out.push_back("  stop: no candidate lowers the AIC");
            break;
        }
    }
    out.push_back("Final model: " + formula_text(design.formula, terms, input.data));
    struct Candidate {
        int mask;
        std::vector<int> terms;
        double bic, aic;
        int rank;
    };
    std::vector<Candidate> candidates;
    for (int mask = 0; mask < (1 << design.formula.terms.size()); ++mask) {
        std::vector<int> included;
        for (std::size_t term = 0; term < design.formula.terms.size(); ++term)
            if (mask & (1 << term))
                included.push_back(term);
        bool hierarchical = true;
        for (int term : included)
            for (std::size_t other = 0; other < design.formula.terms.size(); ++other)
                if (contained(design.formula.terms[other], design.formula.terms[term]) &&
                    !(mask & (1 << other)))
                    hierarchical = false;
        if (!hierarchical)
            continue;
        const SubsetFit candidate = fit_subset(design, included, p);
        candidates.push_back(
            {mask, included, candidate.stats.bic, candidate.stats.aic, candidate.model.rank});
    }
    std::sort(candidates.begin(), candidates.end(), [](const Candidate &a, const Candidate &b) {
        return a.bic != b.bic ? a.bic < b.bic : a.mask < b.mask;
    });
    extend(out, {"", "Best subsets by BIC (model 1, rows " + number(design.y.size()) + ", subsets " +
                         number(candidates.size()) + ")"});
    for (int i = 0; i < std::min(p.best_subsets, int(candidates.size())); ++i) {
        const Candidate &candidate = candidates[i];
        out.push_back(number(i + 1) + ". BIC " + real(candidate.bic) + ", AIC " + real(candidate.aic) +
                      ", rank " + number(candidate.rank) + ": " +
                      formula_text(design.formula, candidate.terms, input.data));
    }
    return out;
}
struct Plot {
    std::vector<std::vector<int>> counts;
    std::vector<int> rows;
};
static Plot count_plot(const Vector &horizontal, const Vector &vertical, double low, double high,
                       const Params &p) {
    Plot out;
    out.counts = std::vector<std::vector<int>>(p.plot_height, std::vector<int>(p.plot_width));
    out.rows.resize(p.plot_height);
    for (std::size_t i = 0; i < horizontal.size(); ++i) {
        const int column =
            std::min(int(std::floor((horizontal[i] - low) / (high - low) * p.plot_width)), p.plot_width - 1);
        const int row = std::max(
            0, std::min(p.plot_height - 1,
                        int(std::floor((p.plot_limit - vertical[i]) / (2 * p.plot_limit) * p.plot_height))));
        ++out.counts[row][column];
        ++out.rows[row];
    }
    return out;
}
static Lines frame(const Plot &plot, const Params &p) {
    const std::string border = "+" + std::string(p.plot_width, '-') + "+";
    Lines out = {border};
    for (int row = 0; row < p.plot_height; ++row) {
        std::string line = "|";
        for (int count : plot.counts[row])
            line += count >= 10 ? '*' : count > 0 ? char('0' + count) : row == p.plot_height / 2 ? '-' : '.';
        out.push_back(line + "|");
    }
    out.push_back(border);
    return out;
}
static Lines residual_plots(const std::vector<Model> &models, const Params &p) {
    Lines out;
    for (std::size_t index = 0; index < models.size(); ++index) {
        if (index)
            out.push_back("");
        const Model &model = models[index];
        const double low = *std::min_element(model.fit_.fitted.begin(), model.fit_.fitted.end()),
                     high = *std::max_element(model.fit_.fitted.begin(), model.fit_.fitted.end()),
                     max_h = *std::max_element(model.fit_.leverage.begin(), model.fit_.leverage.end());
        out.push_back("Model " + number(index + 1) + ": studentized residuals vs fitted values");
        out.push_back("fitted " + real(low) + " to " + real(high) + ", studentized " + real(-p.plot_limit) +
                      " to " + real(p.plot_limit));
        const Plot plot = count_plot(model.fit_.fitted, model.diag.studentized, low, high, p);
        extend(out, frame(plot, p));
        int above = 0, below = 0, outside = 0;
        for (double value : model.diag.studentized) {
            above += value > 2;
            below += value < -2;
            outside += std::abs(value) > p.plot_limit;
        }
        out.push_back("points: " + number(model.design.y.size()) + ", above +2: " + number(above) +
                      ", below -2: " + number(below) + ", outside range: " + number(outside));
        out.push_back("Histogram of studentized residuals:");
        const int maximum = *std::max_element(plot.rows.begin(), plot.rows.end());
        for (int row = 0; row < p.plot_height; ++row) {
            const int length = (plot.rows[row] * 40 + maximum - 1) / maximum;
            std::string line = real(p.plot_limit - 2 * p.plot_limit * (row + 1) / p.plot_height) + " to " +
                               real(p.plot_limit - 2 * p.plot_limit * row / p.plot_height) + ": " +
                               number(plot.rows[row]);
            if (length)
                line += " " + std::string(length, '#');
            out.push_back(line);
        }
        out.push_back("Model " + number(index + 1) + ": studentized residuals vs leverage");
        out.push_back("leverage 0.0000 to " + real(max_h) + ", studentized " + real(-p.plot_limit) + " to " +
                      real(p.plot_limit));
        extend(out, frame(count_plot(model.fit_.leverage, model.diag.studentized, 0, max_h, p), p));
    }
    return out;
}
static void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream file("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        file << line << '\n';
}
int main() {
    std::filesystem::create_directories("output");
    const Input input = read_input();
    std::vector<Model> models;
    for (const std::string &line : input.formulas) {
        Model model;
        model.design = build_design(parse_formula(line, input.data), input.data);
        model.fit_ = fit(model.design.x, model.design.y, model.design.weights, input.params.rank_tol);
        model.stats = statistics(model.design.y, model.design.weights, model.fit_, input.params);
        model.diag = diagnostics(model.design.x, model.design.weights, model.fit_, input.params);
        model.terms.resize(model.design.formula.terms.size());
        std::iota(model.terms.begin(), model.terms.end(), 0);
        model.drops = marginal(model.design, model.terms, model.fit_, model.stats, input.params);
        models.push_back(std::move(model));
    }
    Lines summary = data_summary(input.data),
          diagnostic_lines = {"model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags"},
          prediction = {
              "model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered"};
    for (std::size_t i = 0; i < models.size(); ++i) {
        Model &model = models[i];
        if (i)
            summary.push_back("");
        extend(summary, model_summary(model, input, i + 1));
        extend(prediction, prediction_lines(model, input.prediction, i + 1));
        for (std::size_t row = 0; row < model.design.y.size(); ++row)
            diagnostic_lines.push_back(number(i + 1) + "," + number(model.design.used[row] + 1) + "," +
                                       real(model.fit_.fitted[row]) + "," + real(model.fit_.residuals[row]) +
                                       "," + real(model.fit_.leverage[row]) + "," +
                                       real(model.diag.studentized[row]) + "," + real(model.diag.cooks[row]) +
                                       "," + real(model.diag.dffits[row]) + "," + model.diag.flags[row]);
    }
    extend(summary, {"", "Model comparison:"});
    std::vector<TableRow> comparison;
    for (std::size_t i = 0; i < models.size(); ++i) {
        const Model &model = models[i];
        comparison.push_back({{number(i + 1), number(model.design.y.size()), number(model.fit_.rank),
                               real(model.stats.sigma), real(model.stats.r2), real(model.stats.adjusted),
                               real(model.stats.predicted), real(model.stats.aic), real(model.stats.bic)},
                              ""});
    }
    extend(summary, table({"model", "n", "rank", "sigma", "R-squared", "Adj. R-squared", "Pred. R-squared",
                           "AIC", "BIC"},
                          comparison));
    extend(summary, {"", "Prediction check:"});
    for (std::size_t i = 0; i < models.size(); ++i) {
        const Model &model = models[i];
        summary.push_back(
            "model " + number(i + 1) + ": " + number(model.predicted) + " predicted, " +
            number(model.with_actual) + " with actual values, RMSE " +
            (model.with_actual ? real(std::sqrt(model.error_squares / model.with_actual)) : "NA") +
            ", inside prediction interval " + number(model.covered));
    }
    write_lines("summary.txt", summary);
    write_lines("diagnostics.csv", diagnostic_lines);
    write_lines("selection.txt", selection(models[0], input));
    write_lines("predictions.csv", prediction);
    write_lines("residual_plot.txt", residual_plots(models, input.params));
}
