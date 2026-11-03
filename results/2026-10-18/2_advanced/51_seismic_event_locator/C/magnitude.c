#include "seismic.h"
double logarithm(double value) {
    return log(value) / 2.302585092994046;
}
static int compare(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
double median(const double *values, int count) {
    double *sorted = allocate(count, sizeof(double));
    memcpy(sorted, values, count * sizeof(double));
    qsort(sorted, count, sizeof(double), compare);
    int middle = count / 2;
    return count % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}
PickMagnitude magnitude(Pick pick, double radius, const Params *p) {
    PickMagnitude out = {.radius = radius,
                         .md = p->duration[0] + p->duration[1] * logarithm(pick.duration / 100.0) +
                               p->duration[2] * radius,
                         .has_ml = !pick.clipped};
    if (out.has_ml)
        out.ml = logarithm((double)pick.amplitude) + p->local[0] * logarithm(radius / 100) +
                 p->local[1] * (radius - 100) + p->local[2];
    return out;
}
I scaled(double value, int places) {
    I factor = 1;
    for (int i = 0; i < places; ++i)
        factor *= 10;
    I result = (I)floor(fabs(value) * (double)factor + 0.5);
    return value < 0 ? -result : result;
}
I floor_div(I a, I b) {
    I q = a / b;
    return q - (a % b < 0);
}
char *class_text(I value) {
    I absolute = value < 0 ? -value : value;
    return format("%s%" PRId64 ".%" PRId64, value < 0 ? "-" : "", absolute / 10, absolute % 10);
}
static I class_number(double value) {
    return floor_div(scaled(value, 2) + 5, 10);
}
static int compare_class(const void *a, const void *b) {
    I x = ((const ClassCount *)a)->value, y = ((const ClassCount *)b)->value;
    return (x > y) - (x < y);
}
Frequency frequency(const double *local, const double *duration, int count) {
    Frequency out = {.n = count, .counts = allocate(count, sizeof(ClassCount))};
    for (int i = 0; i < count; ++i) {
        I t = class_number(local[i]);
        int index = 0;
        while (index < out.count && out.counts[index].value != t)
            ++index;
        if (index == out.count)
            out.counts[out.count++] = (ClassCount){t, 0};
        ++out.counts[index].count;
    }
    qsort(out.counts, out.count, sizeof(ClassCount), compare_class);
    int best = -1;
    for (int i = 0; i < out.count; ++i)
        if (out.counts[i].count > best) {
            best = out.counts[i].count;
            out.completeness = out.counts[i].value;
        }
    I total = 0;
    for (int i = 0; i < count; ++i) {
        I t = class_number(local[i]);
        if (t >= out.completeness) {
            ++out.nb;
            total += t;
        }
    }
    double mc = out.completeness / 10.0, mean = total / (10.0 * out.nb);
    out.b = 0.4342944819032518 / (mean - (mc - 0.05));
    out.sigma = out.b / sqrt(out.nb);
    out.a = logarithm(out.nb) + out.b * mc;
    double xm = 0, ym = 0;
    for (int i = 0; i < count; ++i) {
        xm += duration[i];
        ym += local[i];
    }
    xm /= count;
    ym /= count;
    double xx = 0, xy = 0, yy = 0;
    for (int i = 0; i < count; ++i) {
        xx += (duration[i] - xm) * (duration[i] - xm);
        xy += (duration[i] - xm) * (local[i] - ym);
        yy += (local[i] - ym) * (local[i] - ym);
    }
    out.slope = xy / xx;
    out.intercept = ym - out.slope * xm;
    out.r = xy / sqrt(xx * yy);
    out.mean_diff = ym - xm;
    return out;
}
