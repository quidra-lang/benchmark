#include "stereo.hpp"
std::string hundredths(I value) {
    std::string fraction = std::to_string(value % 100);
    return std::to_string(value / 100) + "." + (fraction.size() == 1 ? "0" : "") + fraction;
}
std::string two_decimals(I numerator, I denominator) {
    return hundredths((200 * numerator + denominator) / (2 * denominator));
}
I depth_hundredths(I disparity, I focal, I baseline) {
    return (200 * focal * baseline + disparity) / (2 * disparity);
}
std::pair<std::string, std::string> subpixel(I disparity, const Image &costs, const Params &p) {
    int index = int(disparity) - p.minimum;
    I a = 0, b = 1;
    if (p.minimum < disparity && disparity < p.maximum && costs[index - 1] > costs[index] &&
        costs[index + 1] >= costs[index]) {
        a = costs[index - 1] - costs[index + 1];
        b = 2 * (costs[index - 1] - 2 * costs[index] + costs[index + 1]);
    }
    I rounded = (200 * (disparity * b + a) + b) / (2 * b);
    return {hundredths(rounded), two_decimals(100 * p.focal * p.baseline, rounded)};
}
