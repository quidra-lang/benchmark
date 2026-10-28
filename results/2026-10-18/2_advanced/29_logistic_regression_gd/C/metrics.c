#include "regression.h"
char *real(double value, int digits) {
    if (fabs(value) < 0.5 / pow(10.0, digits))
        value = 0;
    int length = snprintf(NULL, 0, "%.*f", digits, value);
    char *result = malloc((size_t)length + 1);
    snprintf(result, (size_t)length + 1, "%.*f", digits, value);
    return result;
}
char *ratio(Integer a, Integer b) {
    if (!b) {
        char *result = malloc(2);
        strcpy(result, "-");
        return result;
    }
    Integer value = (20000 * a + b) / (2 * b);
    char *result = malloc(64);
    snprintf(result, 64, "%" PRId64 ".%04" PRId64, value / 10000, value % 10000);
    return result;
}
static Integer gcd(Integer a, Integer b) {
    while (b) {
        Integer next = a % b;
        a = b;
        b = next;
    }
    return a;
}
char *fraction_text(Fraction fraction) {
    Integer divisor = gcd(fraction.numerator, fraction.denominator);
    char *result = malloc(160);
    snprintf(result, 160, "%" PRId64 "/%" PRId64 " %s", fraction.numerator / divisor,
             fraction.denominator / divisor, ratio(fraction.numerator, fraction.denominator));
    return result;
}
Confusion confusion(Scores probabilities_, const Targets *targets, double threshold) {
    Confusion c = {0};
    for (int i = 0; i < targets->count; ++i) {
        bool predicted = probabilities_.values[i] >= threshold;
        if (targets->values[i]) {
            if (predicted)
                ++c.tp;
            else
                ++c.fn;
        } else {
            if (predicted)
                ++c.fp;
            else
                ++c.tn;
        }
    }
    return c;
}
static Targets sorted_scores(Scores scores, bool descending) {
    Targets result = {.count = scores.count};
    for (int i = 0; i < scores.count; ++i) {
        int at = i;
        while (at && (descending ? scores.values[i] > scores.values[result.values[at - 1]]
                                 : scores.values[i] < scores.values[result.values[at - 1]])) {
            result.values[at] = result.values[at - 1];
            --at;
        }
        result.values[at] = i;
    }
    return result;
}
Fraction auc(Scores scores, const Targets *targets) {
    Targets order = sorted_scores(scores, false);
    Integer positive = 0, ranks = 0;
    for (int i = 0; i < targets->count; ++i)
        positive += targets->values[i];
    for (int first = 0; first < order.count;) {
        int end = first + 1;
        while (end < order.count && scores.values[order.values[end]] == scores.values[order.values[first]])
            ++end;
        for (int i = first; i < end; ++i)
            if (targets->values[order.values[i]])
                ranks += first + 1 + end;
        first = end;
    }
    return (Fraction){ranks - positive * (positive + 1), 2 * positive * (scores.count - positive)};
}
Roc roc(Scores scores, const Targets *targets) {
    Targets order = sorted_scores(scores, true);
    Roc result = {0};
    Integer tp = 0, fp = 0;
    for (int first = 0; first < order.count;) {
        int end = first;
        double threshold = scores.values[order.values[first]];
        while (end < order.count && scores.values[order.values[end]] == threshold) {
            if (targets->values[order.values[end]])
                ++tp;
            else
                ++fp;
            ++end;
        }
        result.points[result.count++] = (RocPoint){threshold, tp, fp};
        first = end;
    }
    return result;
}
