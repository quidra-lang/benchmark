#include "ecg.h"
Integer integer_sqrt(Integer value) {
    if (!value)
        return 0;
    Integer high = 1;
    while (high <= value / high)
        high *= 2;
    Integer low = high / 2;
    while (low + 1 < high) {
        Integer middle = low + (high - low) / 2;
        if (middle <= value / middle)
            low = middle;
        else
            high = middle;
    }
    return low;
}
Integer root(Integer numerator, Integer denominator) {
    return floor_div(integer_sqrt(floor_div(40000 * numerator, denominator)) + 1, 2);
}
Integer mean_scaled(const Values *values) {
    Integer sum = 0;
    for (int i = 0; i < values->count; ++i)
        sum += values->data[i];
    return rdiv(100 * sum, values->count);
}
Integer mean_hr(const Values *intervals) {
    Integer sum = 0;
    for (int i = 0; i < intervals->count; ++i)
        sum += intervals->data[i];
    return rdiv(6000000 * (Integer)intervals->count, sum);
}
Integer sample_deviation(const Values *values, Integer multiplier) {
    Integer sum = 0, squares = 0;
    for (int i = 0; i < values->count; ++i) {
        Integer value = values->data[i];
        sum += value;
        squares += value * value;
    }
    Integer count = values->count;
    return root(count * squares - sum * sum, multiplier * count * (count - 1));
}
Integer rms(const Values *values) {
    Integer squares = 0;
    for (int i = 0; i < values->count; ++i)
        squares += values->data[i] * values->data[i];
    return root(squares, values->count);
}
static int compare(const void *left, const void *right) {
    Integer a = *(const Integer *)left, b = *(const Integer *)right;
    return (a > b) - (a < b);
}
Histogram histogram(const Values *intervals) {
    Histogram out = {0};
    Integer *bins = resize(NULL, (size_t)intervals->count * sizeof(Integer));
    for (int i = 0; i < intervals->count; ++i)
        bins[i] = floor_div(16 * intervals->data[i], 125);
    if (intervals->count > 1)
        qsort(bins, (size_t)intervals->count, sizeof(Integer), compare);
    out.data = resize(NULL, (size_t)intervals->count * sizeof(Bin));
    for (int i = 0; i < intervals->count; ++i) {
        if (!out.count || out.data[out.count - 1].bin != bins[i])
            out.data[out.count++] = (Bin){bins[i], 0};
        ++out.data[out.count - 1].count;
    }
    free(bins);
    return out;
}
Ranges ranges(const bool *flags, int count) {
    Ranges out = {0};
    out.data = resize(NULL, (size_t)count * sizeof(Range));
    int first = 0;
    while (first < count) {
        if (!flags[first]) {
            ++first;
            continue;
        }
        int last = first;
        while (last + 1 < count && flags[last + 1])
            ++last;
        out.data[out.count++] = (Range){first, last};
        first = last + 1;
    }
    return out;
}
