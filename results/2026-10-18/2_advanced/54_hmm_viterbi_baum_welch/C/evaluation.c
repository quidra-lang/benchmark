#include "hmm.h"
char *fraction(I numerator, I denominator) {
    if (!denominator)
        return "-";
    if (denominator < 0) {
        numerator = -numerator;
        denominator = -denominator;
    }
    I a = numerator < 0 ? -numerator : numerator, b = denominator;
    while (b) {
        I remainder = a % b;
        a = b;
        b = remainder;
    }
    return format("%" PRId64 "/%" PRId64, numerator / a, denominator / a);
}
void accumulate(Confusion *matrix, Path truth, Path prediction) {
    for (int i = 0; i < truth.count; ++i)
        ++matrix->data[truth.data[i]][prediction.data[i]];
}
I correct(Path truth, Path prediction) {
    I out = 0;
    for (int i = 0; i < truth.count; ++i)
        out += truth.data[i] == prediction.data[i];
    return out;
}
Lines matrix_lines(Model model, Confusion matrix) {
    int width = 1;
    for (int i = 0; i < model.k; ++i)
        for (int j = 0; j < model.k; ++j) {
            int size = snprintf(NULL, 0, "%" PRId64, matrix.data[i][j]);
            if (size > width)
                width = size;
        }
    Lines out = {0};
    char *header = " ";
    for (int i = 0; i < model.k; ++i)
        header = format("%s %*c", header, width, model.states[i]);
    line(&out, "%s", header);
    for (int i = 0; i < model.k; ++i) {
        char *row = format("%c", model.states[i]);
        for (int j = 0; j < model.k; ++j)
            row = format("%s %*" PRId64, row, width, matrix.data[i][j]);
        line(&out, "%s", row);
    }
    return out;
}
Lines metric_lines(Model model, Confusion matrix) {
    I rows[4] = {0}, columns[4] = {0}, total = 0, correct_count = 0, expected = 0;
    for (int i = 0; i < model.k; ++i)
        for (int j = 0; j < model.k; ++j) {
            rows[i] += matrix.data[i][j];
            columns[j] += matrix.data[i][j];
        }
    for (int i = 0; i < model.k; ++i) {
        total += rows[i];
        correct_count += matrix.data[i][i];
        expected += rows[i] * columns[i];
    }
    Lines out = {0};
    line(&out, "ACCURACY %s", fraction(correct_count, total));
    line(&out, "KAPPA %s", fraction(total * correct_count - expected, total * total - expected));
    for (int i = 0; i < model.k; ++i)
        line(&out, "STATE %c precision %s recall %s f1 %s", model.states[i],
             fraction(matrix.data[i][i], columns[i]), fraction(matrix.data[i][i], rows[i]),
             fraction(2 * matrix.data[i][i], columns[i] + rows[i]));
    return out;
}
Runs runs(Path path) {
    Runs out = {.data = allocate(path.count, sizeof(Run))};
    if (!path.count)
        return out;
    int start = 1, state = path.data[0];
    for (int t = 1; t < path.count; ++t)
        if (path.data[t] != state) {
            out.data[out.count++] = (Run){state, start, t};
            start = t + 1;
            state = path.data[t];
        }
    out.data[out.count++] = (Run){state, start, path.count};
    return out;
}
MatchCounts region_counts(Regions predicted, Regions truth) {
    MatchCounts out = {.predicted = predicted.count, .truth = truth.count};
    for (int i = 0; i < predicted.count; ++i)
        for (int j = 0; j < truth.count; ++j)
            if (predicted.data[i].start <= truth.data[j].end &&
                truth.data[j].start <= predicted.data[i].end) {
                ++out.matched_predicted;
                break;
            }
    for (int i = 0; i < truth.count; ++i)
        for (int j = 0; j < predicted.count; ++j)
            if (truth.data[i].start <= predicted.data[j].end &&
                predicted.data[j].start <= truth.data[i].end) {
                ++out.matched_truth;
                break;
            }
    return out;
}
MatchCounts boundary_counts(Path predicted, Path truth, int tolerance) {
    int a[300], b[300], ac = 0, bc = 0;
    for (int t = 1; t < predicted.count; ++t)
        if (predicted.data[t] != predicted.data[t - 1])
            a[ac++] = t + 1;
    for (int t = 1; t < truth.count; ++t)
        if (truth.data[t] != truth.data[t - 1])
            b[bc++] = t + 1;
    MatchCounts out = {.predicted = ac, .truth = bc};
    for (int i = 0; i < ac; ++i)
        for (int j = 0; j < bc; ++j)
            if (abs(a[i] - b[j]) <= tolerance) {
                ++out.matched_predicted;
                break;
            }
    for (int i = 0; i < bc; ++i)
        for (int j = 0; j < ac; ++j)
            if (abs(b[i] - a[j]) <= tolerance) {
                ++out.matched_truth;
                break;
            }
    return out;
}
