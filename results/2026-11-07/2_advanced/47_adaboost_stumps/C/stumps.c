#include "boosting.h"
double stump_output(const Stump *stump, const double *values) {
    int bin = 0;
    for (int k = 0; k < stump->nthresholds; ++k)
        bin += values[stump->feature] > stump->thresholds[k];
    return stump->values[bin];
}
Search *prepare(const Rows *rows, int bins) {
    Search *out = calloc(1, sizeof *out);
    out->d = rows->d;
    for (int j = 0; j < rows->d; ++j) {
        Feature *f = &out->features[j];
        for (int i = 0; i < rows->n; ++i) {
            int position = i;
            while (position > 0 && rows->rows[i].values[j] < rows->rows[f->order[position - 1]].values[j]) {
                f->order[position] = f->order[position - 1];
                --position;
            }
            f->order[position] = i;
        }
        f->thresholds[f->n] = rows->rows[f->order[0]].values[j] - 1;
        f->ends[f->n++] = 0;
        for (int i = 1; i < rows->n; ++i) {
            const double left = rows->rows[f->order[i - 1]].values[j],
                         right = rows->rows[f->order[i]].values[j];
            if (left != right) {
                f->thresholds[f->n] = (left + right) / 2;
                f->ends[f->n++] = i;
            }
        }
        for (int b = 1; b < bins; ++b) {
            const int r = b * rows->n / bins;
            f->cuts[b - 1] = (rows->rows[f->order[r - 1]].values[j] + rows->rows[f->order[r]].values[j]) / 2;
        }
    }
    return out;
}
static Candidate choose(Candidate *candidates, int count) {
    double minimum = candidates[0].error;
    for (int i = 1; i < count; ++i)
        if (candidates[i].error < minimum)
            minimum = candidates[i].error;
    Candidate out = candidates[0];
    for (int i = 0; i < count; ++i)
        if (candidates[i].error <= minimum + 0.000000001) {
            out = candidates[i];
            break;
        }
    free(candidates);
    return out;
}
static Stump single(int feature, double threshold, double left, double right) {
    Stump out = {.feature = feature, .nthresholds = 1};
    out.thresholds[0] = threshold;
    out.values[0] = left;
    out.values[1] = right;
    return out;
}
Candidate discrete_stump(const Rows *rows, const Search *search, const double *weights) {
    double positive = 0, negative = 0;
    for (int i = 0; i < rows->n; ++i)
        if (rows->rows[i].label == 1)
            positive += weights[i];
        else
            negative += weights[i];
    Candidate *candidates = malloc((size_t)rows->n * (size_t)rows->d * 2 * sizeof *candidates);
    int count = 0;
    for (int j = 0; j < search->d; ++j) {
        const Feature *f = &search->features[j];
        int position = 0;
        double lp = 0, ln = 0;
        for (int k = 0; k < f->n; ++k) {
            while (position < f->ends[k]) {
                const int i = f->order[position++];
                if (rows->rows[i].label == 1)
                    lp += weights[i];
                else
                    ln += weights[i];
            }
            for (int sign = 1; sign >= -1; sign -= 2)
                candidates[count++] =
                    (Candidate){single(j, f->thresholds[k], -sign, sign),
                                sign == 1 ? lp + (negative - ln) : ln + (positive - lp), sign};
        }
    }
    return choose(candidates, count);
}
Candidate regression_stump(const Rows *rows, const Search *search, const double *targets,
                           const double *weights) {
    double w = 0, s = 0, q = 0;
    for (int i = 0; i < rows->n; ++i) {
        w += weights[i];
        s += weights[i] * targets[i];
        q += weights[i] * targets[i] * targets[i];
    }
    Candidate *candidates = malloc((size_t)rows->n * (size_t)rows->d * sizeof *candidates);
    int count = 0;
    for (int j = 0; j < search->d; ++j) {
        const Feature *f = &search->features[j];
        int position = 0;
        double wl = 0, sl = 0;
        for (int k = 0; k < f->n; ++k) {
            while (position < f->ends[k]) {
                const int i = f->order[position++];
                wl += weights[i];
                sl += weights[i] * targets[i];
            }
            const double wr = w - wl, sr = s - sl, al = k == 0 ? 0 : sl / wl, ar = sr / wr,
                         g = k == 0 ? sr * sr / wr : sl * sl / wl + sr * sr / wr;
            candidates[count++] = (Candidate){single(j, f->thresholds[k], al, ar), q - g, 0};
        }
    }
    return choose(candidates, count);
}
Candidate multiclass_stump(const Rows *rows, const Search *search, const double *weights, int classes) {
    double w = 0, totals[6] = {0};
    for (int i = 0; i < rows->n; ++i) {
        w += weights[i];
        totals[rows->rows[i].label - 1] += weights[i];
    }
    Candidate *candidates = malloc((size_t)rows->n * (size_t)rows->d * sizeof *candidates);
    int count = 0;
    for (int j = 0; j < search->d; ++j) {
        const Feature *f = &search->features[j];
        int position = 0;
        double left[6] = {0};
        for (int k = 0; k < f->n; ++k) {
            while (position < f->ends[k]) {
                const int i = f->order[position++];
                left[rows->rows[i].label - 1] += weights[i];
            }
            double right[6];
            for (int c = 0; c < classes; ++c)
                right[c] = totals[c] - left[c];
            int a = 0, b = 0;
            for (int c = 1; c < classes; ++c) {
                if (left[c] > left[a])
                    a = c;
                if (right[c] > right[b])
                    b = c;
            }
            candidates[count++] =
                (Candidate){single(j, f->thresholds[k], a + 1, b + 1), w - (left[a] + right[b]), 0};
        }
    }
    return choose(candidates, count);
}
RealCandidate real_stump(const Rows *rows, const Search *search, const double *weights, int bins,
                         double smoothing) {
    RealCandidate candidates[10];
    for (int j = 0; j < search->d; ++j) {
        double positive[10] = {0}, negative[10] = {0};
        const Feature *f = &search->features[j];
        for (int i = 0; i < rows->n; ++i) {
            int bin = 0;
            for (int b = 0; b < bins - 1; ++b)
                bin += rows->rows[i].values[j] > f->cuts[b];
            if (rows->rows[i].label == 1)
                positive[bin] += weights[i];
            else
                negative[bin] += weights[i];
        }
        RealCandidate *candidate = &candidates[j];
        memset(candidate, 0, sizeof *candidate);
        candidate->stump.feature = j;
        candidate->stump.nthresholds = bins - 1;
        memcpy(candidate->stump.thresholds, f->cuts, (size_t)(bins - 1) * sizeof(double));
        double sum = 0;
        for (int b = 0; b < bins; ++b) {
            sum += sqrt(positive[b] * negative[b]);
            candidate->stump.values[b] = 0.5 * log((positive[b] + smoothing) / (negative[b] + smoothing));
        }
        candidate->z = 2 * sum;
    }
    double minimum = candidates[0].z;
    for (int j = 1; j < search->d; ++j)
        if (candidates[j].z < minimum)
            minimum = candidates[j].z;
    for (int j = 0; j < search->d; ++j)
        if (candidates[j].z <= minimum + 0.000000001)
            return candidates[j];
    return candidates[0];
}
