#include "smoothing.hpp"
static double sum(const Vector &values) {
    double result = 0;
    for (double value : values)
        result += value;
    return result;
}
static double rss(const Vector &observed, const Vector &fitted) {
    double result = 0;
    for (std::size_t i = 0; i < observed.size(); ++i) {
        const double residual = observed[i] - fitted[i];
        result += residual * residual;
    }
    return result;
}
static std::pair<Vector, std::vector<IsoBlock>> pava(const Data &data, const std::string &direction) {
    std::vector<IsoBlock> blocks;
    for (int i = 0; i < int(data.x.size()); ++i) {
        blocks.push_back({i, i, data.y[i], 1});
        while (blocks.size() >= 2) {
            const IsoBlock &a = blocks[blocks.size() - 2], &b = blocks.back();
            const bool violate = direction == "increasing" ? a.sum * b.count > b.sum * a.count
                                                           : a.sum * b.count < b.sum * a.count;
            if (!violate)
                break;
            const IsoBlock merged{a.first, b.last, a.sum + b.sum, a.count + b.count};
            blocks.pop_back();
            blocks.back() = merged;
        }
    }
    Vector fitted(data.x.size());
    for (const IsoBlock &b : blocks)
        for (int i = b.first; i <= b.last; ++i)
            fitted[i] = double(b.sum) / double(100 * b.count);
    return {fitted, blocks};
}
static std::size_t nearest(const Data &data, int position) {
    std::size_t best = 0;
    for (std::size_t i = 1; i < data.x.size(); ++i)
        if (std::abs(data.x[i] - position) < std::abs(data.x[best] - position))
            best = i;
    return best;
}
Fit make_fit(const Data &data, const Method &method, const Parameter &parameter, const std::string &direction,
             int robust_iterations, bool full) {
    Fit fit;
    fit.data = data;
    fit.method = method;
    fit.parameter = parameter;
    const std::size_t n = data.x.size();
    if (method.kind == Kind::linear) {
        fit.xbar = sum(data.real_x) / double(n);
        const double ybar = sum(data.real_y) / double(n);
        double sxy = 0;
        for (std::size_t i = 0; i < n; ++i) {
            fit.sxx += (data.real_x[i] - fit.xbar) * (data.real_x[i] - fit.xbar);
            sxy += (data.real_x[i] - fit.xbar) * (data.real_y[i] - ybar);
        }
        fit.slope = sxy / fit.sxx;
        fit.intercept = ybar - fit.slope * fit.xbar;
        fit.edf = 2;
        for (std::size_t i = 0; i < n; ++i) {
            fit.fitted.push_back(fit.intercept + fit.slope * data.real_x[i]);
            fit.leverage.push_back(1 / double(n) +
                                   (data.real_x[i] - fit.xbar) * (data.real_x[i] - fit.xbar) / fit.sxx);
        }
    } else if (method.kind == Kind::mean || method.kind == Kind::median) {
        const std::size_t k = (parameter.integer - 1) / 2;
        for (std::size_t i = 0; i < n; ++i) {
            const std::size_t radius = std::min({k, i, n - 1 - i}), count = 2 * radius + 1;
            Integer total = 0;
            std::vector<int> values;
            for (std::size_t j = i - radius; j <= i + radius; ++j) {
                total += data.y[j];
                values.push_back(data.y[j]);
            }
            if (method.kind == Kind::mean) {
                fit.fitted.push_back(double(total) / double(100 * count));
                fit.leverage.push_back(1 / double(count));
            } else {
                std::sort(values.begin(), values.end());
                fit.fitted.push_back(double(values[radius]) / 100);
            }
        }
        if (method.kind == Kind::mean)
            fit.edf = sum(fit.leverage);
    } else if (method.kind == Kind::nw || method.kind == Kind::ll) {
        if (full) {
            for (int position : data.x) {
                const KernelResult local = kernel_estimate(data, method.kernel, parameter.integer, position,
                                                           method.kind == Kind::ll);
                if (!local.estimate) {
                    fit.defined = false;
                    break;
                }
                fit.fitted.push_back(*local.estimate);
                fit.leverage.push_back(*local.leverage);
            }
            if (fit.defined)
                fit.edf = sum(fit.leverage);
        }
    } else if (method.kind == Kind::loess) {
        if (full) {
            const LoessFit local = loess_fit(data, parameter.integer, method.degree, robust_iterations);
            fit.fitted = local.fitted;
            fit.leverage = local.leverage;
            fit.rho = local.rho;
            fit.robust = local.iterations;
            fit.edf = local.edf;
        } else
            fit.rho.assign(n, 1);
    } else if (method.kind == Kind::spline) {
        fit.spline = std::make_shared<Spline>(data.x, parameter.value);
        fit.spline_values = fit.spline->fit(data.real_y);
        fit.fitted = fit.spline_values.fitted;
        if (full) {
            fit.leverage = fit.spline->leverage();
            fit.edf = sum(fit.leverage);
        }
    } else {
        fit.direction = direction;
        if (direction == "auto") {
            const auto increasing = pava(data, "increasing"), decreasing = pava(data, "decreasing");
            fit.increasing_rss = rss(data.real_y, increasing.first);
            fit.decreasing_rss = rss(data.real_y, decreasing.first);
            fit.direction = fit.increasing_rss <= fit.decreasing_rss ? "increasing" : "decreasing";
            const auto &selected = fit.direction == "increasing" ? increasing : decreasing;
            fit.fitted = selected.first;
            fit.blocks = selected.second;
        } else {
            const auto selected = pava(data, direction);
            fit.fitted = selected.first;
            fit.blocks = selected.second;
        }
        fit.edf = double(fit.blocks.size());
        fit.parameter.text = fit.direction;
    }
    return fit;
}
Optional estimate(const Fit &fit, int position) {
    const Kind kind = fit.method.kind;
    const double x0 = double(position) / 100;
    if (kind == Kind::linear)
        return fit.intercept + fit.slope * x0;
    if (kind == Kind::mean || kind == Kind::median)
        return fit.fitted[nearest(fit.data, position)];
    if (kind == Kind::nw || kind == Kind::ll)
        return kernel_estimate(fit.data, fit.method.kernel, fit.parameter.integer, position, kind == Kind::ll)
            .estimate;
    if (kind == Kind::loess)
        return local_fit(fit.data, position, fit.parameter.integer, fit.method.degree, fit.rho).value;
    if (kind == Kind::spline)
        return fit.spline->evaluate(fit.spline_values, position);
    const auto found = std::upper_bound(fit.data.x.begin(), fit.data.x.end(), position);
    return fit.fitted[found == fit.data.x.begin() ? 0 : std::size_t(found - fit.data.x.begin() - 1)];
}
Vector weights(const Fit &fit, int position) {
    const Data &data = fit.data;
    const std::size_t n = data.x.size();
    const Kind kind = fit.method.kind;
    Vector result(n);
    if (kind == Kind::linear) {
        const double x0 = double(position) / 100;
        for (std::size_t j = 0; j < n; ++j)
            result[j] = 1 / double(n) + (x0 - fit.xbar) * (data.real_x[j] - fit.xbar) / fit.sxx;
    } else if (kind == Kind::mean) {
        const std::size_t c = nearest(data, position),
                          radius = std::min({std::size_t((fit.parameter.integer - 1) / 2), c, n - 1 - c});
        for (std::size_t j = c - radius; j <= c + radius; ++j)
            result[j] = 1 / double(2 * radius + 1);
    } else if (kind == Kind::nw || kind == Kind::ll)
        result = kernel_estimate(data, fit.method.kernel, fit.parameter.integer, position, kind == Kind::ll)
                     .weights;
    else if (kind == Kind::loess)
        result = local_fit(data, position, fit.parameter.integer, fit.method.degree, fit.rho).weights;
    else if (kind == Kind::spline)
        result = fit.spline->weights(position);
    return result;
}
static Data subset(const Data &data, const std::function<bool(std::size_t)> &keep) {
    Data out;
    for (std::size_t i = 0; i < data.x.size(); ++i)
        if (keep(i)) {
            out.x.push_back(data.x[i]);
            out.y.push_back(data.y[i]);
            out.real_x.push_back(data.real_x[i]);
            out.real_y.push_back(data.real_y[i]);
        }
    return out;
}
static Optional cross_validation(const Data &data, const Method &method, const Parameter &parameter,
                                 const std::string &direction, int folds) {
    std::vector<Optional> predictions(data.x.size());
    if (folds == 0) {
        for (std::size_t i = 0; i < data.x.size(); ++i) {
            const Data training = subset(data, [&](std::size_t j) { return j != i; });
            const Fit fit = make_fit(training, method, parameter, direction, 0, false);
            predictions[i] = estimate(fit, data.x[i]);
        }
    } else {
        for (int fold = 0; fold < folds; ++fold) {
            const Data training = subset(data, [&](std::size_t j) { return int(j % folds) != fold; });
            const Fit fit = make_fit(training, method, parameter, direction, 0, false);
            for (std::size_t i = 0; i < data.x.size(); ++i)
                if (int(i % folds) == fold)
                    predictions[i] = estimate(fit, data.x[i]);
        }
    }
    return loo_score(data.real_y, predictions);
}
static std::vector<Method> methods(const Params &p) {
    std::vector<Method> out = {{"linear", Kind::linear, {}, 0, {}},
                               {"running_mean", Kind::mean, {}, 0, {}},
                               {"running_median", Kind::median, {}, 0, {}}};
    for (const std::string &kernel : p.rows[1])
        out.push_back({"nw_" + kernel, Kind::nw, kernel, 0, {}});
    for (const std::string &kernel : p.rows[1])
        out.push_back({"ll_" + kernel, Kind::ll, kernel, 0, {}});
    for (const std::string &degree : p.rows[3])
        out.push_back({"loess" + degree, Kind::loess, {}, std::stoi(degree), {}});
    out.push_back({"spline", Kind::spline, {}, 0, {}});
    out.push_back({"isotonic", Kind::isotonic, {}, 0, {}});
    for (Method &m : out) {
        const int row = m.kind == Kind::mean || m.kind == Kind::median ? 0
                        : m.kind == Kind::nw || m.kind == Kind::ll     ? 2
                        : m.kind == Kind::loess                        ? 4
                        : m.kind == Kind::spline                       ? 6
                                                                       : -1;
        if (row < 0)
            continue;
        for (const std::string &text : p.rows[row])
            m.candidates.push_back({text, std::stod(text),
                                    row == 0               ? std::stoi(text)
                                    : row == 2 || row == 4 ? hundredths(text)
                                                           : 0});
    }
    return out;
}
static std::string real_text(Optional value, int digits = 4) {
    if (!value)
        return "NA";
    std::ostringstream out;
    out << std::fixed << std::setprecision(digits) << *value;
    std::string text = out.str();
    if (text[0] == '-' &&
        std::all_of(text.begin() + 1, text.end(), [](char c) { return c == '0' || c == '.'; }))
        text.erase(text.begin());
    return text;
}
static std::string position_text(int value) {
    const Integer magnitude = value < 0 ? -Integer(value) : Integer(value);
    std::ostringstream out;
    out << (value < 0 ? "-" : "") << magnitude / 100 << '.' << std::setw(2) << std::setfill('0')
        << magnitude % 100;
    return out.str();
}
static std::string number(Integer value) {
    return std::to_string(value);
}
static std::string join(const Lines &values, const std::string &delimiter) {
    std::string result;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i)
            result += delimiter;
        result += values[i];
    }
    return result;
}
static std::size_t method_index(const std::vector<Method> &methods_, const std::string &name) {
    for (std::size_t i = 0; i < methods_.size(); ++i)
        if (methods_[i].name == name)
            return i;
    return methods_.size();
}
struct Diagnostic {
    Vector residuals;
    double rss = 0, r2 = 0, dw = 0, z = 0;
    Optional df, rse, nonlinear;
    std::array<double, 5> acf{}, quantiles{};
    int runs = 0, positive = 0, negative = 0, turning = 0;
    std::size_t largest = 0;
};
static Diagnostic diagnose(const Fit &fit, double linear_rss, const std::vector<Optional> &grid) {
    Diagnostic d;
    const std::size_t n = fit.data.x.size();
    double mean = sum(fit.data.real_y) / double(n), tss = 0;
    for (std::size_t i = 0; i < n; ++i) {
        const double residual = fit.data.real_y[i] - fit.fitted[i];
        d.residuals.push_back(residual);
        d.rss += residual * residual;
        tss += (fit.data.real_y[i] - mean) * (fit.data.real_y[i] - mean);
        if (std::abs(residual) > std::abs(d.residuals[d.largest]))
            d.largest = i;
    }
    d.r2 = 1 - d.rss / tss;
    if (fit.edf) {
        d.df = double(n) - *fit.edf;
        d.rse = std::sqrt(d.rss / (*d.df));
        if (fit.method.kind != Kind::linear && *fit.edf > 2)
            d.nonlinear = ((linear_rss - d.rss) / (*fit.edf - 2)) / (d.rss / (*d.df));
    }
    const double residual_mean = sum(d.residuals) / double(n);
    double denominator = 0;
    for (double residual : d.residuals)
        denominator += (residual - residual_mean) * (residual - residual_mean);
    for (std::size_t k = 1; k <= 5; ++k) {
        double numerator = 0;
        for (std::size_t i = 0; i + k < n; ++i)
            numerator += (d.residuals[i] - residual_mean) * (d.residuals[i + k] - residual_mean);
        d.acf[k - 1] = numerator / denominator;
    }
    double dw = 0;
    for (std::size_t i = 1; i < n; ++i)
        dw += (d.residuals[i] - d.residuals[i - 1]) * (d.residuals[i] - d.residuals[i - 1]);
    d.dw = dw / d.rss;
    int sign = 0;
    for (double residual : d.residuals) {
        if (residual == 0)
            continue;
        const int current = residual > 0 ? 1 : -1;
        if (current > 0)
            ++d.positive;
        else
            ++d.negative;
        if (current != sign) {
            ++d.runs;
            sign = current;
        }
    }
    const Integer nonzero = d.positive + d.negative, product = 2 * Integer(d.positive) * d.negative;
    const double mu = 1 + double(product) / double(nonzero),
                 variance = double(product * (product - nonzero)) / double(nonzero * nonzero * (nonzero - 1));
    d.z = (double(d.runs) - mu) / std::sqrt(variance);
    Vector sorted = d.residuals;
    std::sort(sorted.begin(), sorted.end());
    for (std::size_t k = 0; k < 5; ++k) {
        const std::size_t j = (n - 1) * k / 4, remainder = (n - 1) * k - 4 * j;
        d.quantiles[k] =
            remainder == 0 ? sorted[j] : sorted[j] + double(remainder) / 4 * (sorted[j + 1] - sorted[j]);
    }
    Optional previous;
    int previous_sign = 0;
    for (Optional value : grid) {
        if (!value)
            continue;
        if (previous) {
            const double delta = *value - *previous;
            if (delta != 0) {
                const int current = delta > 0 ? 1 : -1;
                if (previous_sign && current != previous_sign)
                    ++d.turning;
                previous_sign = current;
            }
        }
        previous = value;
    }
    return d;
}
struct SelectionRow {
    std::size_t method, candidate;
    Optional score, edf;
    bool selected;
};
struct Study {
    Series series;
    std::vector<Fit> fits;
    std::vector<Optional> loo, kfold;
    std::vector<SelectionRow> selection;
    std::vector<int> grid;
    std::vector<std::vector<Optional>> estimates;
    std::vector<Diagnostic> diagnostics;
    std::vector<std::size_t> ranking;
    std::size_t best = 0, outlier = 0;
    Vector standardized, cook;
};
static Study study(const Series &series, const Params &p, const std::vector<Method> &methods_,
                   std::size_t series_index) {
    Study out;
    out.series = series;
    const int robust = std::stoi(p.rows[5][0]), folds = std::stoi(p.rows[7][0]);
    for (std::size_t m = 0; m < methods_.size(); ++m) {
        const Method &method = methods_[m];
        const std::string direction = p.rows[8][series_index];
        Parameter parameter{"-", 0, 0};
        Optional score;
        if (!method.candidates.empty()) {
            std::vector<Optional> scores, edfs;
            for (const Parameter &candidate : method.candidates) {
                const Fit fit = make_fit(series.data, method, candidate, direction, 0, true);
                scores.push_back(method.kind == Kind::spline
                                     ? Optional(gcv_score(series.data.real_y, fit.fitted, *fit.edf))
                                     : cross_validation(series.data, method, candidate, direction, 0));
                edfs.push_back(fit.edf);
            }
            const std::size_t selected = selected_candidate(scores);
            parameter = method.candidates[selected];
            score = scores[selected];
            for (std::size_t c = 0; c < scores.size(); ++c)
                out.selection.push_back({m, c, scores[c], edfs[c], c == selected});
        }
        Fit fit = make_fit(series.data, method, parameter, direction, robust, true);
        if (method.kind == Kind::linear || method.kind == Kind::spline || method.kind == Kind::isotonic)
            out.loo.push_back(cross_validation(series.data, method, parameter, fit.direction, 0));
        else
            out.loo.push_back(score);
        out.kfold.push_back(cross_validation(series.data, method, parameter, fit.direction, folds));
        out.fits.push_back(std::move(fit));
    }
    const Data &data = series.data;
    const int count = std::stoi(p.rows[9][0]);
    for (int k = 0; k < count; ++k)
        out.grid.push_back(data.x.front() + k * (data.x.back() - data.x.front()) / (count - 1));
    for (const Fit &fit : out.fits) {
        std::vector<Optional> values;
        for (int position : out.grid)
            values.push_back(estimate(fit, position));
        out.estimates.push_back(values);
    }
    const double linear_rss = rss(data.real_y, out.fits[0].fitted);
    for (std::size_t m = 0; m < out.fits.size(); ++m)
        out.diagnostics.push_back(diagnose(out.fits[m], linear_rss, out.estimates[m]));
    out.ranking.resize(methods_.size());
    std::iota(out.ranking.begin(), out.ranking.end(), 0);
    std::sort(out.ranking.begin(), out.ranking.end(), [&](std::size_t a, std::size_t b) {
        return *out.loo[a] != *out.loo[b] ? *out.loo[a] < *out.loo[b] : a < b;
    });
    out.best = out.ranking[0];
    for (std::size_t m : out.ranking)
        if (methods_[m].kind != Kind::median && methods_[m].kind != Kind::isotonic) {
            out.outlier = m;
            break;
        }
    const Fit &fit = out.fits[out.outlier];
    const Diagnostic &d = out.diagnostics[out.outlier];
    out.standardized.assign(data.x.size(), 0);
    out.cook.assign(data.x.size(), 0);
    for (std::size_t i = 0; i < data.x.size(); ++i)
        if (fit.leverage[i] < 1) {
            const double t = d.residuals[i] / (*d.rse * std::sqrt(1 - fit.leverage[i]));
            out.standardized[i] = t;
            out.cook[i] = t * t * fit.leverage[i] / ((1 - fit.leverage[i]) * (*fit.edf));
        }
    return out;
}
static double standard_error(const Fit &fit, const Diagnostic &diagnostic, int position) {
    const Vector values = weights(fit, position);
    double total = 0;
    for (double value : values)
        total += value * value;
    return *diagnostic.rse * std::sqrt(total);
}
static void extend(Lines &out, const Lines &lines) {
    out.insert(out.end(), lines.begin(), lines.end());
}
static Lines diagnostics_lines(const Study &s, const Params &p, const std::vector<Method> &methods_) {
    const Data &data = s.series.data;
    const auto limits = std::minmax_element(data.y.begin(), data.y.end());
    Lines out = {"series " + s.series.name + " n " + number(data.x.size()) + " x " +
                 position_text(data.x.front()) + " " + position_text(data.x.back()) + " y " +
                 position_text(*limits.first) + " " + position_text(*limits.second)};
    for (std::size_t m = 0; m < methods_.size(); ++m) {
        const Fit &fit = s.fits[m];
        const Diagnostic &d = s.diagnostics[m];
        std::string first =
            "method " + methods_[m].name + " parameter " + fit.parameter.text + " loo " + real_text(s.loo[m]);
        if (methods_[m].kind == Kind::spline) {
            for (const SelectionRow &row : s.selection)
                if (row.method == m && row.selected)
                    first += " gcv " + real_text(row.score);
        }
        out.push_back(first);
        out.push_back("  rss " + real_text(d.rss) + " edf " + real_text(fit.edf) + " df " + real_text(d.df) +
                      " rse " + real_text(d.rse) + " r2 " + real_text(d.r2) + " f_nonlinear " +
                      real_text(d.nonlinear));
        std::string acf = "  acf";
        for (double value : d.acf)
            acf += " " + real_text(value);
        out.push_back(acf + " dw " + real_text(d.dw));
        out.push_back("  runs " + number(d.runs) + " positive " + number(d.positive) + " negative " +
                      number(d.negative) + " z " + real_text(d.z));
        out.push_back("  max_residual " + real_text(d.residuals[d.largest]) + " at " +
                      position_text(data.x[d.largest]) + " turning " + number(d.turning));
        std::string quantiles = "  quantiles";
        for (double value : d.quantiles)
            quantiles += " " + real_text(value);
        out.push_back(quantiles);
        if (methods_[m].kind == Kind::loess) {
            for (std::size_t i = 0; i < fit.robust.size(); ++i) {
                const Robust &r = fit.robust[i];
                out.push_back("  robust " + number(i + 1) + " scale " + real_text(r.scale) + " zero_weight " +
                              number(r.zero) + " max_change " + real_text(r.change));
            }
            std::string zero = "  zero_weight_points";
            bool any = false;
            for (std::size_t i = 0; i < fit.rho.size(); ++i)
                if (fit.rho[i] == 0) {
                    zero += " " + position_text(data.x[i]);
                    any = true;
                }
            out.push_back(zero + (any ? "" : " none"));
        }
    }
    out.push_back("ranking");
    for (std::size_t rank = 0; rank < s.ranking.size(); ++rank) {
        const std::size_t m = s.ranking[rank];
        out.push_back("  " + number(rank + 1) + " " + methods_[m].name + " " + real_text(s.loo[m]) +
                      " kfold " + real_text(s.kfold[m]));
    }
    out.push_back("agreement with " + methods_[s.best].name);
    for (std::size_t m = 0; m < methods_.size(); ++m) {
        if (m == s.best)
            continue;
        std::size_t count = 0, at = 0;
        double squared = 0, maximum = -1;
        for (std::size_t k = 0; k < s.grid.size(); ++k)
            if (s.estimates[m][k] && s.estimates[s.best][k]) {
                ++count;
                const double delta = std::abs(*s.estimates[m][k] - *s.estimates[s.best][k]);
                squared += delta * delta;
                if (delta > maximum) {
                    maximum = delta;
                    at = k;
                }
            }
        out.push_back("  " + methods_[m].name + " points " + number(count) + " rms " +
                      real_text(std::sqrt(squared / double(count))) + " max " + real_text(maximum) + " at " +
                      position_text(s.grid[at]));
    }
    const std::size_t spline_index = method_index(methods_, "spline");
    double maximum = 0, minimum = 0;
    std::size_t max_at = 1, min_at = 1;
    for (std::size_t k = 1; k + 1 < s.grid.size(); ++k) {
        const double slope = (*s.estimates[spline_index][k + 1] - *s.estimates[spline_index][k - 1]) /
                             (double(s.grid[k + 1] - s.grid[k - 1]) / 100);
        if (k == 1 || slope > maximum) {
            maximum = slope;
            max_at = k;
        }
        if (k == 1 || slope < minimum) {
            minimum = slope;
            min_at = k;
        }
    }
    out.push_back("slope spline max " + real_text(maximum) + " at " + position_text(s.grid[max_at]) +
                  " min " + real_text(minimum) + " at " + position_text(s.grid[min_at]));
    const Fit &fit = s.fits[s.outlier];
    const Diagnostic &d = s.diagnostics[s.outlier];
    const double threshold = double(hundredths(p.rows[12][0])) / 100;
    out.push_back("outliers method " + methods_[s.outlier].name + " threshold " +
                  position_text(hundredths(p.rows[12][0])));
    std::vector<std::size_t> outliers, influence;
    for (std::size_t i = 0; i < data.x.size(); ++i)
        if (fit.leverage[i] < 1) {
            influence.push_back(i);
            if (std::abs(s.standardized[i]) > threshold)
                outliers.push_back(i);
        }
    std::sort(outliers.begin(), outliers.end(), [&](std::size_t a, std::size_t b) {
        return std::abs(s.standardized[a]) != std::abs(s.standardized[b])
                   ? std::abs(s.standardized[a]) > std::abs(s.standardized[b])
                   : a < b;
    });
    if (outliers.empty())
        out.push_back("  none");
    for (std::size_t i : outliers)
        out.push_back("  x " + position_text(data.x[i]) + " y " + position_text(data.y[i]) + " fit " +
                      real_text(fit.fitted[i]) + " residual " + real_text(d.residuals[i]) + " standardized " +
                      real_text(s.standardized[i]));
    out.push_back("influence method " + methods_[s.outlier].name);
    std::sort(influence.begin(), influence.end(), [&](std::size_t a, std::size_t b) {
        return s.cook[a] != s.cook[b] ? s.cook[a] > s.cook[b] : a < b;
    });
    for (std::size_t k = 0; k < std::min<std::size_t>(3, influence.size()); ++k) {
        const std::size_t i = influence[k];
        out.push_back("  x " + position_text(data.x[i]) + " lev " + real_text(fit.leverage[i]) + " cook " +
                      real_text(s.cook[i]));
    }
    out.push_back("bands");
    const double z = std::stod(p.rows[10][0]);
    for (const std::string &name : p.rows[11]) {
        const std::size_t m = method_index(methods_, name);
        double total = 0;
        std::size_t count = 0, coverage = 0;
        for (std::size_t k = 0; k < s.grid.size(); ++k)
            if (s.estimates[m][k]) {
                total += standard_error(s.fits[m], s.diagnostics[m], s.grid[k]);
                ++count;
            }
        for (std::size_t i = 0; i < data.x.size(); ++i) {
            const double se = standard_error(s.fits[m], s.diagnostics[m], data.x[i]),
                         rse = *s.diagnostics[m].rse;
            if (std::abs(s.diagnostics[m].residuals[i]) <= z * std::sqrt(rse * rse + se * se))
                ++coverage;
        }
        out.push_back("  " + name + " mean_se " + real_text(total / double(count)) + " coverage " +
                      number(coverage) + " of " + number(data.x.size()));
    }
    return out;
}
static Lines framed(const Lines &rows) {
    const std::string frame = "+" + std::string(rows[0].size(), '-') + "+";
    Lines out = {frame};
    for (const std::string &row : rows)
        out.push_back("|" + row + "|");
    out.push_back(frame);
    return out;
}
static int clamped_row(double value, int height) {
    return value < 0 ? 0 : value >= double(height) ? height - 1 : int(value);
}
static Lines plot_lines(const Study &s, const Params &p, const std::vector<Method> &methods_) {
    const Data &data = s.series.data;
    const int width = std::stoi(p.rows[16][0]), height = std::stoi(p.rows[16][1]), xa = data.x.front(),
              xb = data.x.back();
    const auto limits = std::minmax_element(data.y.begin(), data.y.end());
    const int ya = *limits.first, yb = *limits.second;
    const double ymin = double(ya) / 100, ymax = double(yb) / 100;
    Lines out = {"plot " + s.series.name + " size " + number(width) + "x" + number(height) + " x " +
                 position_text(xa) + " " + position_text(xb) + " y " + position_text(ya) + " " +
                 position_text(yb)};
    std::string legend = "legend . data";
    for (std::size_t m = 0; m < p.rows[15].size(); ++m)
        legend += " " + number(m + 1) + " " + p.rows[15][m];
    out.push_back(legend);
    Lines rows(height, std::string(width, ' '));
    std::vector<int> columns;
    for (std::size_t i = 0; i < data.x.size(); ++i) {
        const int col = std::min(width - 1, width * (data.x[i] - xa) / (xb - xa)),
                  row = std::min(height - 1, height * (yb - data.y[i]) / (yb - ya));
        columns.push_back(col);
        rows[row][col] = '.';
    }
    for (std::size_t m = 0; m < p.rows[15].size(); ++m) {
        const std::size_t method = method_index(methods_, p.rows[15][m]);
        const char digit = char('1' + m);
        for (int col = 0; col < width; ++col) {
            const int position = xa + (2 * col + 1) * (xb - xa) / (2 * width);
            const Optional value = estimate(s.fits[method], position);
            if (!value)
                continue;
            const int row = clamped_row(double(height) * (ymax - *value) / (ymax - ymin), height);
            char &cell = rows[row][col];
            cell = cell == ' ' || cell == '.' || cell == digit ? digit : '*';
        }
    }
    extend(out, framed(rows));
    Integer dots = 0, curves = 0, overlaps = 0;
    for (const std::string &row : rows)
        for (char c : row) {
            if (c == '.')
                ++dots;
            else if (c == '*')
                ++overlaps;
            else if (c >= '1' && c <= '9')
                ++curves;
        }
    out.push_back("cells data " + number(dots) + " curve " + number(curves) + " overlap " + number(overlaps));
    out.push_back("");
    const Diagnostic &d = s.diagnostics[s.best];
    double limit = 0;
    for (double residual : d.residuals)
        limit = std::max(limit, std::abs(residual));
    out.push_back("residuals " + s.series.name + " method " + methods_[s.best].name + " limit " +
                  real_text(limit));
    rows.assign(height, std::string(width, ' '));
    rows[height / 2].assign(width, '-');
    for (std::size_t i = 0; i < data.x.size(); ++i) {
        const double pi = double(height) * ((limit - d.residuals[i]) / (2 * limit));
        rows[clamped_row(pi, height)][columns[i]] = 'o';
    }
    extend(out, framed(rows));
    out.push_back("");
    out.push_back("histogram " + s.series.name + " method " + methods_[s.outlier].name);
    std::array<Integer, 14> counts{};
    for (std::size_t i = 0; i < data.x.size(); ++i)
        if (s.fits[s.outlier].leverage[i] < 1) {
            const double t = s.standardized[i];
            const std::size_t bin = t < -3 ? 0 : t >= 3 ? 13 : 1 + std::size_t((t + 3) / 0.5);
            ++counts[bin];
        }
    for (int bin = 0; bin < 14; ++bin) {
        const std::string lower = bin == 0 ? "-inf" : real_text(-3 + 0.5 * (bin - 1), 2),
                          upper = bin == 13 ? "inf" : real_text(-3 + 0.5 * bin, 2);
        out.push_back(lower + " " + upper + " " + number(counts[bin]) + " |" + std::string(counts[bin], '#'));
    }
    return out;
}
static void write(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        out << line << '\n';
}
int main() {
    const Input input = read_input();
    const Params &p = input.params;
    const std::vector<Method> methods_ = methods(p);
    std::vector<Study> studies;
    for (std::size_t i = 0; i < input.series.size(); ++i)
        studies.push_back(study(input.series[i], p, methods_, i));
    Lines selection = {"series,method,parameter,score,edf,selected"}, fits, predictions,
          bands = {"series,method,x,fit,se,lower,upper"}, diagnostics, isotonic, plots;
    std::string header = "series,x";
    for (const Method &method : methods_)
        header += "," + method.name;
    fits.push_back(header);
    predictions.push_back(header);
    Integer random = std::stoll(p.rows[13][2]);
    const int repetitions = std::stoi(p.rows[13][0]), trim = std::stoi(p.rows[13][1]);
    const double z = std::stod(p.rows[10][0]);
    for (std::size_t series = 0; series < studies.size(); ++series) {
        const Study &s = studies[series];
        const Data &data = s.series.data;
        for (const SelectionRow &row : s.selection)
            selection.push_back(s.series.name + "," + methods_[row.method].name + "," +
                                methods_[row.method].candidates[row.candidate].text + "," +
                                real_text(row.score) + "," + real_text(row.edf) + "," +
                                (row.selected ? "1" : "0"));
        for (std::size_t k = 0; k < s.grid.size(); ++k) {
            std::string line = s.series.name + "," + position_text(s.grid[k]);
            for (const auto &values : s.estimates)
                line += "," + real_text(values[k]);
            fits.push_back(line);
        }
        for (const std::string &name : p.rows[11]) {
            const std::size_t m = method_index(methods_, name);
            for (std::size_t k = 0; k < s.grid.size(); ++k) {
                const Optional value = s.estimates[m][k];
                if (!value) {
                    bands.push_back(s.series.name + "," + name + "," + position_text(s.grid[k]) +
                                    ",NA,NA,NA,NA");
                    continue;
                }
                const double se = standard_error(s.fits[m], s.diagnostics[m], s.grid[k]);
                bands.push_back(s.series.name + "," + name + "," + position_text(s.grid[k]) + "," +
                                real_text(value) + "," + real_text(se) + "," + real_text(*value - z * se) +
                                "," + real_text(*value + z * se));
            }
        }
        const std::size_t m = method_index(methods_, "spline");
        const Fit &spline = s.fits[m];
        const Diagnostic &diagnostic = s.diagnostics[m];
        const double mean = sum(diagnostic.residuals) / double(data.x.size());
        Vector centered;
        for (double residual : diagnostic.residuals)
            centered.push_back(residual - mean);
        std::vector<Vector> bootstrap(s.grid.size());
        for (int b = 0; b < repetitions; ++b) {
            Vector sampled;
            for (std::size_t i = 0; i < data.x.size(); ++i) {
                random = (48271 * random) % 2147483647;
                const std::size_t index = random % data.x.size();
                sampled.push_back(spline.fitted[i] + centered[index]);
            }
            const SplineValues fit = spline.spline->fit(sampled);
            for (std::size_t k = 0; k < s.grid.size(); ++k)
                bootstrap[k].push_back(spline.spline->evaluate(fit, s.grid[k]));
        }
        for (std::size_t k = 0; k < s.grid.size(); ++k) {
            Vector values = bootstrap[k];
            const double average = sum(values) / double(repetitions);
            double total = 0;
            for (double value : values)
                total += (value - average) * (value - average);
            const double se = std::sqrt(total / double(repetitions - 1));
            std::sort(values.begin(), values.end());
            bands.push_back(s.series.name + ",spline_bootstrap," + position_text(s.grid[k]) + "," +
                            real_text(s.estimates[m][k]) + "," + real_text(se) + "," +
                            real_text(values[trim]) + "," + real_text(values[repetitions - trim - 1]));
        }
        if (series) {
            diagnostics.push_back("");
            isotonic.push_back("");
        }
        extend(diagnostics, diagnostics_lines(s, p, methods_));
        const std::size_t iso = method_index(methods_, "isotonic");
        const Fit &fit = s.fits[iso];
        std::string first =
            "series " + s.series.name + " direction " + fit.direction + " mode " + p.rows[8][series];
        if (p.rows[8][series] == "auto")
            first += " rss_increasing " + real_text(fit.increasing_rss) + " rss_decreasing " +
                     real_text(fit.decreasing_rss);
        isotonic.push_back(first);
        isotonic.push_back("blocks " + number(fit.blocks.size()) + " rss " +
                           real_text(s.diagnostics[iso].rss) + " loo " + real_text(s.loo[iso]));
        for (std::size_t j = 0; j < fit.blocks.size(); ++j) {
            const IsoBlock &block = fit.blocks[j];
            isotonic.push_back("block " + number(j + 1) + " x " + position_text(data.x[block.first]) + " " +
                               position_text(data.x[block.last]) + " count " + number(block.count) +
                               " value " + real_text(double(block.sum) / double(100 * block.count)));
        }
    }
    for (const TestPoint &point : input.tests) {
        const auto found = std::find_if(studies.begin(), studies.end(),
                                        [&](const Study &s) { return s.series.name == point.series; });
        std::string line = point.series + "," + position_text(point.x);
        for (const Fit &fit : found->fits)
            line += "," + real_text(estimate(fit, point.x));
        predictions.push_back(line);
    }
    for (const std::string &name : p.rows[14]) {
        if (!plots.empty())
            plots.push_back("");
        const auto found = std::find_if(studies.begin(), studies.end(),
                                        [&](const Study &s) { return s.series.name == name; });
        extend(plots, plot_lines(*found, p, methods_));
    }
    write("selection.csv", selection);
    write("fits.csv", fits);
    write("predictions.csv", predictions);
    write("bands.csv", bands);
    write("diagnostics.txt", diagnostics);
    write("isotonic.txt", isotonic);
    write("plots.txt", plots);
}
