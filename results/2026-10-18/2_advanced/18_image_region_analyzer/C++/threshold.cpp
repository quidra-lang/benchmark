#include "regions.hpp"

Histogram::Histogram(const Image& image) : maxval(image.maxval), pixels(image.width * image.height), minimum(image.maxval), maximum(0), median(-1), mode(0), levels(0), binWidth((image.maxval + 8) / 8), total(0), counts(image.maxval + 1), belowCounts(image.maxval + 1), belowSums(image.maxval + 1) {
    for (int value : image.pixels) ++counts[value];
    Integer count = 0;
    for (int value = 0; value <= maxval; ++value) {
        count += counts[value]; total += value * counts[value];
        belowCounts[value] = count; belowSums[value] = total;
        if (counts[value]) { minimum = std::min(minimum, value); maximum = value; ++levels; }
        if (median < 0 && 2 * count >= pixels) median = value;
        if (counts[value] > counts[mode]) mode = value;
    }
    for (int start = 0; start <= maxval; start += binWidth) { Integer frequency = 0; for (int value = start; value <= maxval && value < start + binWidth; ++value) frequency += counts[value]; bins.push_back(frequency); }
}
Otsu otsu(const Histogram& histogram) {
    Otsu result{histogram.minimum, histogram.minimum, {}};
    for (int cutoff = 0; cutoff < histogram.maxval; ++cutoff) {
        Integer below = histogram.belowCounts[cutoff], sumBelow = histogram.belowSums[cutoff], above = histogram.pixels - below, sumAbove = histogram.total - sumBelow;
        if (histogram.counts[cutoff] && above) result.candidates.push_back({cutoff, below, sumBelow, above, sumAbove, sumBelow * sumBelow * above + sumAbove * sumAbove * below, below * above});
    }
    std::sort(result.candidates.begin(), result.candidates.end(), [](const Candidate& first, const Candidate& second) {
        Integer q1 = first.numerator / first.denominator, q2 = second.numerator / second.denominator;
        if (q1 != q2) return q1 > q2;
        Integer left = (first.numerator % first.denominator) * second.denominator, right = (second.numerator % second.denominator) * first.denominator;
        return left != right ? left > right : first.cutoff < second.cutoff;
    });
    if (!result.candidates.empty()) { result.cutoff = result.candidates.front().cutoff; int following = result.cutoff + 1; while (!histogram.counts[following]) ++following; result.upper = following - 1; }
    return result;
}
std::pair<int, int> isodata(const Histogram& histogram) {
    int cutoff = static_cast<int>(histogram.total / histogram.pixels), iterations = 0;
    while (true) {
        Integer below = histogram.belowCounts[cutoff], sumBelow = histogram.belowSums[cutoff], above = histogram.pixels - below, sumAbove = histogram.total - sumBelow;
        if (!below || !above) break;
        int following = static_cast<int>((sumBelow * above + sumAbove * below) / (2 * below * above));
        ++iterations;
        if (following == cutoff) break;
        cutoff = following;
        if (iterations == 100) break;
    }
    return {cutoff, iterations};
}
