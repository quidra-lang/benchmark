#include "image.h"

Histogram histogram(const Image *image) {
    Histogram result = {0};
    result.pixels = image->width * image->height;
    result.maxval = image->maxval;
    for (int i = 0; i < result.pixels; ++i) ++result.counts[image->pixels[i]];
    result.minimum = result.maxval;
    int count = 0;
    Integer sum = 0;
    bool median_found = false;
    for (int value = 0; value <= result.maxval; ++value) {
        count += result.counts[value];
        sum += (Integer)value * result.counts[value];
        result.below[value] = count;
        result.sums[value] = sum;
        if (result.counts[value]) {
            if (value < result.minimum) result.minimum = value;
            result.maximum = value;
            ++result.levels;
        }
        if (!median_found && 2 * count >= result.pixels) { result.median = value; median_found = true; }
        if (result.counts[value] > result.counts[result.mode]) result.mode = value;
    }
    result.total = sum;
    result.bin_width = (result.maxval + 8) / 8;
    for (int start = 0; start <= result.maxval; start += result.bin_width) {
        int end = start + result.bin_width;
        if (end > result.maxval + 1) end = result.maxval + 1;
        for (int value = start; value < end; ++value) result.bins[result.bin_count] += result.counts[value];
        ++result.bin_count;
    }
    return result;
}

static Candidate split(const Histogram *histogram, int cutoff) {
    Candidate result = {0};
    result.cutoff = cutoff;
    result.below = histogram->below[cutoff];
    result.sum_below = histogram->sums[cutoff];
    result.above = histogram->pixels - result.below;
    result.sum_above = histogram->total - result.sum_below;
    result.numerator = result.sum_below * result.sum_below * result.above + result.sum_above * result.sum_above * result.below;
    result.denominator = (Integer)result.below * result.above;
    return result;
}

static int rank_order(const void *left, const void *right) {
    const Candidate *first = left, *second = right;
    Integer first_q = first->numerator / first->denominator, second_q = second->numerator / second->denominator;
    if (first_q != second_q) return first_q > second_q ? -1 : 1;
    Integer first_r = first->numerator % first->denominator, second_r = second->numerator % second->denominator;
    Integer a = first_r * second->denominator, b = second_r * first->denominator;
    if (a != b) return a > b ? -1 : 1;
    return first->cutoff - second->cutoff;
}

Otsu otsu(const Histogram *histogram) {
    Otsu result = {0};
    for (int cutoff = 0; cutoff < histogram->maxval; ++cutoff) {
        if (histogram->counts[cutoff] && histogram->below[cutoff] < histogram->pixels) result.candidates[result.count++] = split(histogram, cutoff);
    }
    qsort(result.candidates, (size_t)result.count, sizeof(*result.candidates), rank_order);
    result.cutoff = result.count ? result.candidates[0].cutoff : histogram->minimum;
    result.upper = result.cutoff;
    if (result.count) {
        int following = result.cutoff + 1;
        while (!histogram->counts[following]) ++following;
        result.upper = following - 1;
    }
    return result;
}

int isodata(const Histogram *histogram, int *iterations) {
    int cutoff = (int)(histogram->total / histogram->pixels);
    *iterations = 0;
    while (true) {
        Candidate values = split(histogram, cutoff);
        if (!values.below || !values.above) break;
        int following = (int)((values.sum_below * values.above + values.sum_above * values.below) / (2 * (Integer)values.below * values.above));
        ++*iterations;
        if (following == cutoff) break;
        cutoff = following;
        if (*iterations == 100) break;
    }
    return cutoff;
}
