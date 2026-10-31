#include "stereo.h"
char *hundredths(I value) { return format("%lld.%02lld", value / 100, value % 100); }
char *two_decimals(I numerator, I denominator) {
    return hundredths((200 * numerator + denominator) / (2 * denominator));
}
I depth_hundredths(I disparity, I focal, I baseline) {
    return (200 * focal * baseline + disparity) / (2 * disparity);
}
Refined subpixel(I disparity, const I *costs, const Params *p) {
    int index = (int)disparity - p->minimum;
    I a = 0, b = 1;
    if (p->minimum < disparity && disparity < p->maximum && costs[index - 1] > costs[index] &&
        costs[index + 1] >= costs[index]) {
        a = costs[index - 1] - costs[index + 1];
        b = 2 * (costs[index - 1] - 2 * costs[index] + costs[index + 1]);
    }
    I rounded = (200 * (disparity * b + a) + b) / (2 * b);
    return (Refined){hundredths(rounded), two_decimals(100 * p->focal * p->baseline, rounded)};
}
