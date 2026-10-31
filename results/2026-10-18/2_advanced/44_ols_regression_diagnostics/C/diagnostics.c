#include "regression.h"
Diagnostics diagnostics(const Matrix *x, const Vector *weights, const Fit *model, const Params *params) {
    int n = x->rows, r = model->rank, df = n - r;
    double sigma = sqrt(model->rss / df);
    Diagnostics out = {0};
    out.standardized = vector_new(n);
    out.studentized = vector_new(n);
    out.cooks = vector_new(n);
    out.dffits = vector_new(n);
    out.dfbetas = matrix_new(n, r);
    for (int i = 0; i < n; ++i) {
        double h = model->leverage.data[i], eps = model->weighted_residuals.data[i],
               z = eps / (sigma * sqrt(1 - h)), student = z * sqrt((double)(df - 1) / (df - z * z));
        out.standardized.data[i] = z;
        out.studentized.data[i] = student;
        out.cooks.data[i] = z * z * h / (r * (1 - h));
        out.dffits.data[i] = student * sqrt(h / (1 - h));
        bool flags[] = {h > params->leverage * r / n, fabs(student) > params->studentized,
                        out.cooks.data[i] > params->cook / n,
                        fabs(out.dffits.data[i]) > params->dffits * sqrt((double)r / n)};
        char flag_string[5];
        int count = 0;
        for (int flag = 0; flag < 4; ++flag)
            if (flags[flag]) {
                ++out.flag_counts[flag];
                flag_string[count++] = "HOCF"[flag];
            }
        flag_string[count] = 0;
        if (count) {
            line_push(&out.flags, text(flag_string));
            ++out.any;
        } else
            line_push(&out.flags, text("-"));
        double deleted_sigma = sigma * sqrt((df - z * z) / (df - 1));
        for (int k = 0; k < r; ++k)
            AT(out.dfbetas, i, k) =
                AT(model->g, i, k) * eps / (1 - h) / (deleted_sigma * sqrt(model->variance.data[k]));
    }
    double difference_sum = 0;
    for (int i = 1; i < n; ++i) {
        double difference = model->weighted_residuals.data[i] - model->weighted_residuals.data[i - 1];
        difference_sum += difference * difference;
    }
    out.durbin = difference_sum / model->rss;
    Matrix accepted = matrix_new(n, r);
    Vector square = vector_new(n), ones = vector_new(n);
    double square_sum = 0;
    for (int i = 0; i < n; ++i) {
        ones.data[i] = 1;
        square.data[i] = model->weighted_residuals.data[i] * model->weighted_residuals.data[i];
        square_sum += square.data[i];
        for (int k = 0; k < r; ++k)
            AT(accepted, i, k) = AT(*x, i, model->accepted.data[k]);
    }
    Fit auxiliary = fit(&accepted, &square, &ones, params->rank_tol);
    double mean = square_sum / n, tss = 0;
    for (int i = 0; i < n; ++i)
        tss += (square.data[i] - mean) * (square.data[i] - mean);
    out.bp = n * (1 - auxiliary.rss / tss);
    out.bp_df = auxiliary.rank - 1;
    out.bp_p = p_chi(out.bp, out.bp_df);
    fit_free(&auxiliary);
    free(accepted.data);
    free(square.data);
    free(ones.data);
    double eps_sum = 0;
    for (int i = 0; i < n; ++i)
        eps_sum += model->weighted_residuals.data[i];
    double eps_mean = eps_sum / n, second = 0, third = 0, fourth = 0;
    for (int i = 0; i < n; ++i) {
        double delta = model->weighted_residuals.data[i] - eps_mean;
        second += delta * delta;
        third += delta * delta * delta;
        fourth += delta * delta * delta * delta;
    }
    second /= n;
    third /= n;
    fourth /= n;
    out.skewness = third / (second * sqrt(second));
    out.kurtosis = fourth / (second * second);
    out.jb = (double)n / 6 * (out.skewness * out.skewness + (out.kurtosis - 3) * (out.kurtosis - 3) / 4);
    out.jb_p = p_chi(out.jb, 2);
    (void)weights;
    return out;
}
void diagnostics_free(Diagnostics *out) {
    free(out->standardized.data);
    free(out->studentized.data);
    free(out->cooks.data);
    free(out->dffits.data);
    lines_free(&out->flags);
    free(out->dfbetas.data);
    *out = (Diagnostics){0};
}
