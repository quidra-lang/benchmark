#include "forecasting.hpp"
static const std::vector<std::string> names = {"naive",      "snaive",      "drift",  "ses",
                                               "holt",       "damped",      "hw_add", "hw_mult",
                                               "decomp_add", "decomp_mult", "ar",     "combo"};
static const std::vector<std::string> difference_names = {"none", "first", "seasonal", "both"};
template <class... T> static std::string text(const T &...values) {
    std::ostringstream out;
    bool first = true;
    auto put = [&](const auto &value) {
        if (!first)
            out << ' ';
        first = false;
        out << value;
    };
    (put(values), ...);
    return out.str();
}
static std::string vector_text(const Vector &values) {
    std::string result;
    for (double value : values)
        result += " " + real(value);
    return result;
}
struct Fitted {
    int method = 0, season = 0, difference_kind = 0, order = 0;
    Vector values, residuals, seasonal, differenced, coefficients, aic, variances;
    SmoothParameters parameters;
    Smoothed smoothing;
    Correlation correlation;
    Levinson levinson;
    double intercept = 0, slope = 0, sigma2 = 0;
    Vector forecast(int origin, int steps) const {
        Vector result;
        if (method == 0)
            return Vector(steps, values[origin - 1]);
        if (method == 1) {
            for (int k = 1; k <= steps; ++k)
                result.push_back(values[origin - season + (k - 1) % season]);
            return result;
        }
        if (method == 2) {
            for (int k = 1; k <= steps; ++k)
                result.push_back(values[origin - 1] +
                                 k * ((values[origin - 1] - values[0]) / double(origin - 1)));
            return result;
        }
        if (method >= 3 && method <= 7)
            return smooth_forecast(method, smoothing.states[origin], parameters, origin, steps, season);
        if (method == 8 || method == 9) {
            for (int k = 1; k <= steps; ++k) {
                const int t = origin + k - 1;
                const double value = intercept + slope * (t + 1), component = seasonal[t % season];
                result.push_back(method == 8 ? value + component : value * component);
            }
            return result;
        }
        return ar_forecast(values, differenced, difference_kind, season, origin, steps, correlation.mean,
                           coefficients);
    }
    std::vector<std::string> lines() const {
        const std::string &name = names[method];
        const std::string tail = text("rmse", real(rmse(residuals)), "residuals", residuals.size());
        if (method <= 1)
            return {text(name, tail)};
        if (method == 2)
            return {text(name, "slope", real(slope), tail)};
        if (method >= 3 && method <= 7) {
            std::string line = text(name, "alpha", real(parameters.alpha));
            if (method != 3)
                line += text(" beta", real(parameters.beta));
            if (method == 5)
                line += text(" phi", real(parameters.phi));
            if (method == 6 || method == 7)
                line += text(" gamma", real(parameters.gamma));
            const State &state = smoothing.states.back();
            line += " " + tail + text(" level", real(state.level));
            if (method != 3)
                line += text(" slope", real(state.slope));
            std::vector<std::string> result{line};
            if (method == 6 || method == 7) {
                Vector components;
                for (int i = 0; i < season; ++i)
                    components.push_back(state.seasonal[(values.size() + i) % season]);
                result.push_back(name + " seasonal" + vector_text(components));
            }
            return result;
        }
        if (method == 8 || method == 9)
            return {text(name, "intercept", real(intercept), "slope", real(slope), tail),
                    name + " seasonal" + vector_text(seasonal)};
        return {text("ar variance none", real(variances[0]), "first", real(variances[1]), "seasonal",
                     real(variances[2]), "both", real(variances[3])),
                text("ar difference", difference_names[difference_kind], "n", differenced.size(), "mean",
                     real(correlation.mean), "order", order, "sigma2", real(sigma2), tail),
                "ar aic" + vector_text(aic),
                coefficients.empty() ? "ar coefficients none"
                                     : "ar coefficients" + vector_text(coefficients)};
    }
};
static Fitted fit_method(int method, const Vector &values, const Params &p) {
    Fitted model;
    model.method = method;
    model.values = values;
    model.season = p.season;
    const int size = int(values.size());
    if (method <= 2) {
        if (method == 2)
            model.slope = (values.back() - values[0]) / double(size - 1);
        const int start = method == 1 ? p.season : 1;
        for (int t = start; t < size; ++t)
            model.residuals.push_back(method == 1   ? values[t] - values[t - p.season]
                                      : method == 2 ? values[t] - values[t - 1] - model.slope
                                                    : values[t] - values[t - 1]);
    } else if (method <= 7) {
        double best = std::numeric_limits<double>::infinity();
        auto consider = [&](SmoothParameters parameters) {
            Smoothed result = smooth(method, values, p.season, parameters);
            double sse = 0;
            for (double error : result.residuals)
                sse += error * error;
            if (sse < best) {
                best = sse;
                model.parameters = parameters;
                model.smoothing = std::move(result);
            }
        };
        for (double alpha : p.alpha) {
            if (method == 3) {
                consider({alpha});
                continue;
            }
            for (double beta : p.beta) {
                if (method == 4)
                    consider({alpha, beta});
                else if (method == 5)
                    for (double phi : p.phi)
                        consider({alpha, beta, 0, phi});
                else
                    for (double gamma : p.gamma)
                        consider({alpha, beta, gamma});
            }
        }
        model.residuals = model.smoothing.residuals;
    } else if (method <= 9) {
        const Decomposition decomposition = decompose(values, p.season);
        model.seasonal = method == 8 ? decomposition.additive : decomposition.multiplicative;
        Vector adjusted;
        for (int t = 0; t < size; ++t)
            adjusted.push_back(method == 8 ? values[t] - model.seasonal[t % p.season]
                                           : values[t] / model.seasonal[t % p.season]);
        const auto line = regression(adjusted);
        model.intercept = line.first;
        model.slope = line.second;
        for (int t = 0; t < size; ++t) {
            const double base = model.intercept + model.slope * (t + 1),
                         component = model.seasonal[t % p.season];
            model.residuals.push_back(values[t] - (method == 8 ? base + component : base * component));
        }
    } else {
        double smallest = std::numeric_limits<double>::infinity();
        for (int kind = 0; kind < 4; ++kind) {
            const Vector differenced = difference(values, kind, p.season);
            const Correlation correlation = autocorrelation(differenced, p.max_lag);
            model.variances.push_back(correlation.variance);
            if (correlation.variance < smallest) {
                smallest = correlation.variance;
                model.difference_kind = kind;
                model.differenced = differenced;
                model.correlation = correlation;
            }
        }
        model.levinson = durbin_levinson(model.correlation.acf, p.max_lag);
        double best = std::numeric_limits<double>::infinity();
        for (int order = 0; order <= p.max_ar; ++order) {
            const double value = double(model.differenced.size()) *
                                     std::log(model.correlation.variance * model.levinson.variance[order]) +
                                 2 * order;
            model.aic.push_back(value);
            if (value < best) {
                best = value;
                model.order = order;
            }
        }
        model.sigma2 = model.correlation.variance * model.levinson.variance[model.order];
        for (int j = 1; j <= model.order; ++j)
            model.coefficients.push_back(model.levinson.coefficients[model.order][j]);
        model.residuals = ar_residuals(model.differenced, model.correlation.mean, model.coefficients);
    }
    return model;
}
using Forecaster = std::function<Vector(int, int)>;
struct CrossValidation {
    std::vector<int> counts;
    Vector sigma, mae;
    double rmse;
};
static CrossValidation cross_validate(const Vector &values, const Params &p, const Forecaster &forecast) {
    CrossValidation result{std::vector<int>(p.horizon), Vector(p.horizon), Vector(p.horizon), 0};
    Vector squares(p.horizon), absolute(p.horizon);
    for (int origin = p.cv_start; origin < int(values.size()); ++origin) {
        const int steps = std::min(p.horizon, int(values.size()) - origin);
        const Vector estimates = forecast(origin, steps);
        for (int k = 0; k < steps; ++k) {
            const double error = values[origin + k] - estimates[k];
            ++result.counts[k];
            squares[k] += error * error;
            absolute[k] += std::abs(error);
        }
    }
    for (int k = 0; k < p.horizon; ++k) {
        result.sigma[k] = std::sqrt(squares[k] / result.counts[k]);
        result.mae[k] = absolute[k] / result.counts[k];
    }
    double sum = 0;
    int count = 0;
    for (int k = 0; k < p.holdout; ++k) {
        sum += squares[k];
        count += result.counts[k];
    }
    result.rmse = std::sqrt(sum / count);
    return result;
}
static Vector combination(const std::vector<Fitted> &models, const std::vector<int> &members, int origin,
                          int steps) {
    Vector result(steps);
    for (int index : members) {
        const Vector estimates = models[index].forecast(origin, steps);
        for (int k = 0; k < steps; ++k)
            result[k] += estimates[k];
    }
    for (double &value : result)
        value /= double(members.size());
    return result;
}
struct Outputs {
    std::ofstream decomposition{"output/decomposition.csv"}, models{"output/models.txt"},
        forecasts{"output/forecasts.csv"}, accuracy{"output/accuracy.csv"}, cv{"output/cv.csv"},
        correlogram{"output/correlogram.txt"}, chart{"output/chart.txt"}, plan{"output/plan.txt"};
    Outputs() {
        decomposition
            << "series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag\n";
        forecasts << "series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95\n";
        accuracy
            << "series,method,me,mae,rmse,mape,smape,mase,fva,cv_rmse,cover80,cover95,winkler80,winkler95,rank\n";
        cv << "series,method,step,origins,mae,rmse\n";
    }
};
struct Interval {
    double forecast, lo80, hi80, lo95, hi95;
};
static Interval interval(double forecast, double sigma, const Params &p, double multiplier = 1) {
    return {forecast * multiplier, (forecast - p.z80 * sigma) * multiplier,
            (forecast + p.z80 * sigma) * multiplier, (forecast - p.z95 * sigma) * multiplier,
            (forecast + p.z95 * sigma) * multiplier};
}
static void forecast_row(std::ostream &out, const std::string &name, const std::string &stage,
                         const std::string &model, const std::string &period, const std::string &actual,
                         Interval values) {
    out << name << ',' << stage << ',' << model << ',' << period << ',' << actual << ','
        << real(values.forecast) << ',' << real(values.lo80) << ',' << real(values.hi80) << ','
        << real(values.lo95) << ',' << real(values.hi95) << '\n';
}
static std::string correlation_bar(double correlation, double band) {
    std::string bar(41, ' ');
    const int extent = int(std::floor(std::abs(correlation) * 20 + 0.5)),
              boundary = int(std::floor(band * 20 + 0.5));
    bar[20 - boundary] = bar[20 + boundary] = ':';
    bar[20] = '|';
    if (correlation > 0)
        std::fill(bar.begin() + 21, bar.begin() + 21 + extent, '#');
    else if (correlation < 0)
        std::fill(bar.begin() + 20 - extent, bar.begin() + 20, '#');
    return bar;
}
static void diagnostics(std::ostream &out, const std::string &name, const std::vector<Fitted> &fitted,
                        const Params &p) {
    const Fitted &ar = fitted[10];
    const double band = 2 / std::sqrt(double(ar.differenced.size()));
    out << text("series", name, "difference", difference_names[ar.difference_kind], "n",
                ar.differenced.size(), "band", real(band))
        << '\n';
    for (int partial = 0; partial < 2; ++partial)
        for (int lag = 1; lag <= p.max_lag; ++lag) {
            const double value = partial ? ar.levinson.partial[lag] : ar.correlation.acf[lag];
            out << (partial ? "pacf" : "acf") << ' ' << std::setw(2) << lag << ' ' << std::setw(7)
                << real(value) << " [" << correlation_bar(value, band) << ']';
            if (std::abs(value) > band)
                out << " *";
            out << '\n';
        }
    for (const Fitted &model : fitted) {
        const Vector &residuals = model.residuals;
        const double average = mean(residuals), count = double(residuals.size());
        double s2 = 0, s3 = 0, s4 = 0, squares = 0, differences = 0;
        for (std::size_t i = 0; i < residuals.size(); ++i) {
            const double delta = residuals[i] - average;
            s2 += delta * delta;
            s3 += delta * delta * delta;
            s4 += delta * delta * delta * delta;
            squares += residuals[i] * residuals[i];
            if (i) {
                const double difference_ = residuals[i] - residuals[i - 1];
                differences += difference_ * difference_;
            }
        }
        const double m2 = s2 / count, m3 = s3 / count, m4 = s4 / count, skew = m3 / (m2 * std::sqrt(m2)),
                     kurtosis = m4 / (m2 * m2) - 3, jb = count / 6 * (skew * skew + kurtosis * kurtosis / 4);
        out << text("residuals", names[model.method], "n", residuals.size(), "mean", real(average), "sd",
                    real(std::sqrt(s2 / (count - 1))), "dw", real(differences / squares), "skewness",
                    real(skew), "kurtosis", real(kurtosis), "jb", real(jb))
            << '\n';
        out << "ljung_box " << names[model.method];
        for (int lag : p.ljung_box) {
            const auto test = ljung_box(residuals, lag);
            out << " lag " << lag << " q " << real(test.first) << " p " << real(test.second);
        }
        out << '\n';
    }
}
static void charts(std::ostream &out, const Series &series, int best, const Vector &actual,
                   const std::vector<Interval> &holdout, const std::vector<Interval> &future,
                   const Decomposition &decomposition, const Params &p) {
    std::vector<Interval> rows = holdout;
    rows.insert(rows.end(), future.begin(), future.end());
    double low = rows[0].lo95, high = rows[0].hi95;
    for (const Interval &row : rows) {
        low = std::min(low, row.lo95);
        high = std::max(high, row.hi95);
    }
    for (double value : actual) {
        low = std::min(low, value);
        high = std::max(high, value);
    }
    out << text("chart", series.name, "method", names[best]) << '\n'
        << text("scale low", real(low), "high", real(high)) << '\n';
    auto column = [&](double value) { return int(std::floor((value - low) / (high - low) * 60 + 0.5)); };
    const int first = int(series.raw.size()) - p.holdout;
    for (std::size_t index = 0; index < rows.size(); ++index) {
        const Interval &row = rows[index];
        std::string chart(61, ' ');
        std::fill(chart.begin() + column(row.lo95), chart.begin() + column(row.hi95) + 1, '-');
        std::fill(chart.begin() + column(row.lo80), chart.begin() + column(row.hi80) + 1, '=');
        chart[column(row.forecast)] = 'o';
        if (index < actual.size())
            chart[column(actual[index])] = '*';
        out << series.periods[first + index] << " |" << chart << "|\n";
    }
    double peak = 0;
    for (double value : decomposition.multiplicative)
        peak = std::max(peak, std::abs(value - 1));
    out << text("profile peak", real(peak)) << '\n';
    for (int j = 0; j < p.season; ++j) {
        const double value = decomposition.multiplicative[j];
        const int extent = int(std::floor(std::abs(value - 1) / peak * 30 + 0.5));
        std::string chart(61, ' ');
        chart[30] = '|';
        if (value > 1)
            std::fill(chart.begin() + 31, chart.begin() + 31 + extent, '#');
        else if (value < 1)
            std::fill(chart.begin() + 30 - extent, chart.begin() + 30, '#');
        out << "season " << std::setw(2) << j + 1 << ' ' << real(value) << " [" << chart << "]\n";
    }
}
static void inventory_plan(std::ostream &out, const Series &series, int best, const Vector &corrected,
                           const Vector &actual, const std::vector<Interval> &future, const Inventory &policy,
                           const Params &p, const Forecaster &forecast) {
    const int size = int(corrected.size()), protection = policy.lead_time + policy.review;
    double squares = 0;
    for (int origin = p.cv_start; origin <= size - protection; ++origin) {
        const Vector estimates = forecast(origin, protection);
        double error = 0;
        for (int k = 0; k < protection; ++k)
            error += corrected[origin + k] - estimates[k];
        squares += error * error;
    }
    const double safety = policy.service * std::sqrt(squares / double(size - protection - p.cv_start + 1));
    out << text("series", series.name, "method", names[best]) << '\n'
        << text("policy on_hand", policy.on_hand, "lead_time", policy.lead_time, "review", policy.review,
                "service", real(policy.service), "safety_stock", real(safety))
        << '\n';
    int last = 1;
    for (int k = 1; k - 1 + protection <= p.horizon; k += policy.review)
        last = k;
    const int end = last - 1 + protection;
    std::vector<Integer> receipts(p.horizon + policy.lead_time + 2);
    double stock = double(policy.on_hand), lowest = std::numeric_limits<double>::infinity(), sum = 0;
    Integer outstanding = 0, ordered = 0;
    int orders = 0, short_periods = 0;
    for (int k = 1; k <= end; ++k) {
        const Integer receipt = receipts[k];
        stock += double(receipt);
        outstanding -= receipt;
        if ((k - 1) % policy.review == 0 && k - 1 + protection <= p.horizon) {
            const double position = stock + double(outstanding);
            double demand = 0;
            for (int j = k - 1; j < k - 1 + protection; ++j)
                demand += future[j].forecast;
            const double target = demand + safety;
            const Integer quantity = std::max(Integer(0), Integer(std::ceil(target - position)));
            out << text("review", series.periods[size + k - 1], "position", real(position), "target",
                        real(target), "order", quantity)
                << '\n';
            if (quantity) {
                ++orders;
                ordered += quantity;
                outstanding += quantity;
                receipts[k + policy.lead_time] += quantity;
            }
        }
        stock -= future[k - 1].forecast;
        const std::string status = stock < 0 ? "short" : stock < safety ? "low" : "ok";
        if (stock < 0)
            ++short_periods;
        lowest = std::min(lowest, stock);
        sum += stock;
        out << text("period", series.periods[size + k - 1], "demand", real(future[k - 1].forecast), "receipt",
                    receipt, "on_hand", real(stock), "status", status)
            << '\n';
    }
    out << text("summary orders", orders, "ordered", ordered, "short_periods", short_periods, "lowest",
                real(lowest), "average", real(sum / end))
        << '\n';
    struct Year {
        int actual_months = 0, forecast_months = 0;
        double actual = 0, forecast = 0;
    };
    std::map<std::string, Year> years;
    for (int t = 0; t < size; ++t) {
        Year &year = years[series.periods[t].substr(0, 4)];
        ++year.actual_months;
        year.actual += actual[t];
    }
    for (int k = 0; k < p.horizon; ++k) {
        Year &year = years[series.periods[size + k].substr(0, 4)];
        ++year.forecast_months;
        year.forecast += future[k].forecast;
    }
    bool previous_full = false;
    double previous_total = 0;
    for (const auto &item : years) {
        const Year &year = item.second;
        const double value = year.actual + year.forecast;
        const bool full = year.actual_months + year.forecast_months == 12;
        out << text("year", item.first, "actual_months", year.actual_months, "actual", real(year.actual),
                    "forecast_months", year.forecast_months, "forecast", real(year.forecast), "total",
                    real(value), "growth",
                    full && previous_full ? real(100 * (value - previous_total) / previous_total) : "NA")
            << '\n';
        previous_full = full;
        previous_total = value;
    }
}
static void analyze_series(Series series, const Input &input, Outputs &out) {
    const Params &p = input.params;
    const int size = int(series.raw.size()), training_size = size - p.holdout;
    for (int k = 0; k < p.horizon; ++k)
        series.periods.push_back(next_month(series.periods.back()));
    Vector interpolated = series.raw;
    for (int t = 0; t < size; ++t)
        if (series.missing[t]) {
            int a = t - 1, b = t + 1;
            while (series.missing[a])
                --a;
            while (series.missing[b])
                ++b;
            interpolated[t] = series.raw[a] + (series.raw[b] - series.raw[a]) * double(t - a) / double(b - a);
        }
    const Decomposition decomposition = decompose(interpolated, p.season);
    const int half = p.season / 2;
    Vector residuals(decomposition.residual_add.begin() + half, decomposition.residual_add.end() - half);
    const double residual_mean = mean(residuals), residual_sd = std::sqrt(sample_variance(residuals));
    Vector corrected = interpolated;
    std::vector<bool> outliers(size);
    std::vector<std::string> events(size), kinds;
    std::map<std::string, Vector> lifts;
    int outlier_count = 0, event_count = 0;
    for (int t = 0; t < size; ++t) {
        const auto event = input.events.find({series.name, series.periods[t]});
        if (event != input.events.end()) {
            events[t] = event->second;
            ++event_count;
            if (!lifts.count(event->second))
                kinds.push_back(event->second);
            lifts[event->second].push_back(interpolated[t] /
                                           (decomposition.trend[t] + decomposition.additive[t % p.season]));
        }
        if (t >= half && t < size - half && !series.missing[t] && events[t].empty() &&
            std::abs(decomposition.residual_add[t] - residual_mean) > p.outlier * residual_sd) {
            outliers[t] = true;
            ++outlier_count;
        }
        if (outliers[t] || !events[t].empty())
            corrected[t] = decomposition.trend[t] + decomposition.additive[t % p.season];
        const std::string flag = !events[t].empty()  ? events[t]
                                 : series.missing[t] ? "missing"
                                 : outliers[t]       ? "outlier"
                                                     : "ok";
        out.decomposition
            << series.name << ',' << series.periods[t] << ',' << real(interpolated[t]) << ','
            << real(corrected[t]) << ','
            << (std::isnan(decomposition.trend[t]) ? "NA" : real(decomposition.trend[t])) << ','
            << real(decomposition.additive[t % p.season]) << ','
            << (std::isnan(decomposition.residual_add[t]) ? "NA" : real(decomposition.residual_add[t])) << ','
            << real(decomposition.multiplicative[t % p.season]) << ','
            << (std::isnan(decomposition.residual_mult[t]) ? "NA" : real(decomposition.residual_mult[t]))
            << ',' << flag << '\n';
    }
    Vector trend_residual, season_residual;
    for (int t = half; t < size - half; ++t) {
        trend_residual.push_back(decomposition.trend[t] + decomposition.residual_add[t]);
        season_residual.push_back(decomposition.additive[t % p.season] + decomposition.residual_add[t]);
    }
    const double residual_variance = sample_variance(residuals),
                 strength_trend = std::max(0.0, 1 - residual_variance / sample_variance(trend_residual)),
                 strength_season = std::max(0.0, 1 - residual_variance / sample_variance(season_residual));
    const Vector training(corrected.begin(), corrected.begin() + training_size),
        actual(interpolated.begin() + training_size, interpolated.end());
    std::vector<Fitted> fitted;
    std::vector<CrossValidation> validations;
    for (int method = 0; method < 11; ++method) {
        fitted.push_back(fit_method(method, training, p));
        validations.push_back(cross_validate(training, p, [&, method](int origin, int steps) {
            return fitted[method].forecast(origin, steps);
        }));
    }
    std::vector<int> members(11);
    std::iota(members.begin(), members.end(), 0);
    std::stable_sort(members.begin(), members.end(),
                     [&](int a, int b) { return validations[a].rmse < validations[b].rmse; });
    members.resize(p.combo);
    std::sort(members.begin(), members.end());
    validations.push_back(cross_validate(
        training, p, [&](int origin, int steps) { return combination(fitted, members, origin, steps); }));
    std::vector<Vector> forecasts;
    std::vector<Accuracy> measures;
    std::vector<std::vector<Interval>> intervals;
    const double delta = scale_delta(training, p.season);
    for (int model = 0; model < 12; ++model) {
        forecasts.push_back(model == 11 ? combination(fitted, members, training_size, p.holdout)
                                        : fitted[model].forecast(training_size, p.holdout));
        Accuracy accuracy = evaluate(actual, forecasts.back(), validations[model].sigma, p.z80, p.z95, delta);
        accuracy.cv_rmse = validations[model].rmse;
        measures.push_back(accuracy);
        std::vector<Interval> rows;
        for (int k = 0; k < p.holdout; ++k)
            rows.push_back(interval(forecasts.back()[k], validations[model].sigma[k], p));
        intervals.push_back(rows);
    }
    const int best = rank_accuracy(measures)[0];
    for (Accuracy &accuracy : measures)
        accuracy.fva = 100 * (measures[0].mae - accuracy.mae) / measures[0].mae;
    std::vector<Fitted> final_fitted(11);
    if (best == 11)
        for (int method : members)
            final_fitted[method] = fit_method(method, corrected, p);
    else
        final_fitted[best] = fit_method(best, corrected, p);
    const Forecaster final_forecast = [&](int origin, int steps) {
        return best == 11 ? combination(final_fitted, members, origin, steps)
                          : final_fitted[best].forecast(origin, steps);
    };
    const CrossValidation final_cv = cross_validate(corrected, p, final_forecast);
    const Vector estimates = final_forecast(size, p.horizon);
    std::vector<Interval> future;
    for (int k = 0; k < p.horizon; ++k) {
        double multiplier = 1;
        const auto event = input.events.find({series.name, series.periods[size + k]});
        if (event != input.events.end())
            multiplier = mean(lifts.at(event->second));
        future.push_back(interval(estimates[k], final_cv.sigma[k], p, multiplier));
    }
    out.models << text("series", series.name) << '\n'
               << text("data observations", size, "train", training_size, "holdout", p.holdout, "missing",
                       std::count(series.missing.begin(), series.missing.end(), true), "outliers",
                       outlier_count, "events", event_count)
               << '\n';
    for (const std::string &kind : kinds)
        out.models << text("event", kind, "occurrences", lifts.at(kind).size(), "lift",
                           real(mean(lifts.at(kind))))
                   << '\n';
    for (int t = 0; t < size; ++t)
        if (outliers[t])
            out.models << text("outlier", series.periods[t], "value", real(interpolated[t]), "expected",
                               real(corrected[t]), "score",
                               real((decomposition.residual_add[t] - residual_mean) / residual_sd))
                       << '\n';
    out.models << text("strength trend", real(strength_trend), "seasonal", real(strength_season)) << '\n';
    for (const Fitted &model : fitted)
        write_lines(out.models, model.lines());
    out.models << "combo members";
    for (int method : members)
        out.models << ' ' << names[method];
    out.models << '\n' << text("best", names[best], "rmse", real(measures[best].rmse)) << '\n';
    if (best == 11) {
        for (int method : members)
            for (const std::string &line : final_fitted[method].lines())
                out.models << "final " << line << '\n';
    } else
        for (const std::string &line : final_fitted[best].lines())
            out.models << "final " << line << '\n';
    for (int model = 0; model < 12; ++model) {
        for (int k = 0; k < p.holdout; ++k)
            forecast_row(out.forecasts, series.name, "holdout", names[model],
                         series.periods[training_size + k],
                         std::to_string(Integer(series.raw[training_size + k])), intervals[model][k]);
        const Accuracy &a = measures[model];
        out.accuracy << series.name << ',' << names[model] << ',' << real(a.me) << ',' << real(a.mae) << ','
                     << real(a.rmse) << ',' << real(a.mape) << ',' << real(a.smape) << ',' << real(a.mase)
                     << ',' << real(a.fva) << ',' << real(a.cv_rmse) << ',' << a.cover80 << ',' << a.cover95
                     << ',' << real(a.winkler80) << ',' << real(a.winkler95) << ',' << a.rank << '\n';
        for (int k = 0; k < p.horizon; ++k)
            out.cv << series.name << ',' << names[model] << ',' << k + 1 << ','
                   << validations[model].counts[k] << ',' << real(validations[model].mae[k]) << ','
                   << real(validations[model].sigma[k]) << '\n';
    }
    for (int k = 0; k < p.horizon; ++k)
        forecast_row(out.forecasts, series.name, "future", names[best], series.periods[size + k], "NA",
                     future[k]);
    diagnostics(out.correlogram, series.name, fitted, p);
    charts(out.chart, series, best, actual, intervals[best], future, decomposition, p);
    inventory_plan(out.plan, series, best, corrected, interpolated, future, input.inventory.at(series.name),
                   p, final_forecast);
}
int main() {
    const Input input = read_input();
    Outputs output;
    for (const Series &series : input.series)
        analyze_series(series, input, output);
}
