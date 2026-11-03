#include "regression.hpp"
Diagnostics diagnostics(const Matrix &x, const Vector &weights, const Fit &model, const Params &params) {
    const int n = x.size(), r = model.rank, df = n - r;
    const double sigma = std::sqrt(model.rss / df);
    Diagnostics out;
    out.standardized.resize(n);
    out.studentized.resize(n);
    out.cooks.resize(n);
    out.dffits.resize(n);
    out.flags.resize(n);
    out.dfbetas = Matrix(n, Vector(r));
    for (int i = 0; i < n; ++i) {
        const double h = model.leverage[i], eps = model.weighted_residuals[i],
                     z = eps / (sigma * std::sqrt(1 - h)),
                     student = z * std::sqrt(double(df - 1) / (df - z * z));
        out.standardized[i] = z;
        out.studentized[i] = student;
        out.cooks[i] = z * z * h / (r * (1 - h));
        out.dffits[i] = student * std::sqrt(h / (1 - h));
        const std::array<bool, 4> flags = {
            h > params.leverage * r / n, std::abs(student) > params.studentized,
            out.cooks[i] > params.cook / n,
            std::abs(out.dffits[i]) > params.dffits * std::sqrt(double(r) / n)};
        for (int flag = 0; flag < 4; ++flag)
            if (flags[flag]) {
                ++out.flag_counts[flag];
                out.flags[i] += "HOCF"[flag];
            }
        if (out.flags[i].empty())
            out.flags[i] = "-";
        else
            ++out.any;
        const double deleted_sigma = sigma * std::sqrt((df - z * z) / (df - 1));
        for (int k = 0; k < r; ++k)
            out.dfbetas[i][k] =
                model.g[i][k] * eps / (1 - h) / (deleted_sigma * std::sqrt(model.variance[k]));
    }
    double difference_sum = 0;
    for (int i = 1; i < n; ++i) {
        const double difference = model.weighted_residuals[i] - model.weighted_residuals[i - 1];
        difference_sum += difference * difference;
    }
    out.durbin = difference_sum / model.rss;
    Matrix accepted(n, Vector(r));
    Vector square(n), ones(n, 1);
    double square_sum = 0;
    for (int i = 0; i < n; ++i) {
        square[i] = model.weighted_residuals[i] * model.weighted_residuals[i];
        square_sum += square[i];
        for (int k = 0; k < r; ++k)
            accepted[i][k] = x[i][model.accepted[k]];
    }
    const Fit auxiliary = fit(accepted, square, ones, params.rank_tol);
    const double mean = square_sum / n;
    double tss = 0;
    for (double value : square)
        tss += (value - mean) * (value - mean);
    out.bp = n * (1 - auxiliary.rss / tss);
    out.bp_df = auxiliary.rank - 1;
    out.bp_p = p_chi(out.bp, out.bp_df);
    double eps_sum = 0;
    for (double value : model.weighted_residuals)
        eps_sum += value;
    const double eps_mean = eps_sum / n;
    double second = 0, third = 0, fourth = 0;
    for (double value : model.weighted_residuals) {
        const double delta = value - eps_mean;
        second += delta * delta;
        third += delta * delta * delta;
        fourth += delta * delta * delta * delta;
    }
    second /= n;
    third /= n;
    fourth /= n;
    out.skewness = third / (second * std::sqrt(second));
    out.kurtosis = fourth / (second * second);
    out.jb = double(n) / 6 * (out.skewness * out.skewness + (out.kurtosis - 3) * (out.kurtosis - 3) / 4);
    out.jb_p = p_chi(out.jb, 2);
    return out;
}
