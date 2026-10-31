#include "smoothing.h"
Optional loo_score(const double *observed, const Optional *predictions, int count) {
    double total = 0;
    for (int i = 0; i < count; ++i) {
        if (!predictions[i].defined)
            return (Optional){0};
        double error = observed[i] - predictions[i].value;
        total += error * error;
    }
    return some(total / (double)count);
}
double gcv_score(const double *observed, const double *fitted, int count, double edf) {
    double rss = 0;
    for (int i = 0; i < count; ++i) {
        double error = observed[i] - fitted[i];
        rss += error * error;
    }
    double tau = 1 - edf / (double)count;
    return rss / (double)count / (tau * tau);
}
int selected_candidate(const Optional *scores, int count) {
    int best = -1;
    for (int i = 0; i < count; ++i)
        if (scores[i].defined && (best < 0 || scores[i].value < scores[best].value))
            best = i;
    return best;
}
