#include "spc.hpp"
#include <algorithm>
#include <cmath>

Center attributeCenter(int chart, const std::vector<Lot>& lots, const Numbers& numbers) {
    Integer defectives = 0, defects = 0, inspected = 0;
    for (int number : numbers) {
        const Lot& lot = lots[number - 1];
        defectives += lot.defectives; defects += lot.defects; inspected += lot.inspected;
    }
    double fraction = static_cast<double>(defectives) / inspected;
    double value = chart == 0 ? fraction : chart == 1 ? static_cast<double>(defectives) / numbers.size()
        : chart == 2 ? static_cast<double>(defects) / numbers.size() : static_cast<double>(defects) / inspected;
    return {chart,value,fraction};
}

LotPoint attributePoint(const Lot& lot, Center center) {
    double value, sigma, cl = center.value;
    if (center.chart == 0) { value = static_cast<double>(lot.defectives) / lot.inspected; sigma = std::sqrt(cl * (1 - cl) / lot.inspected); }
    else if (center.chart == 1) { value = lot.defectives; sigma = std::sqrt(cl * (1 - center.fraction)); }
    else if (center.chart == 2) { value = lot.defects; sigma = std::sqrt(cl); }
    else { value = static_cast<double>(lot.defects) / lot.inspected; sigma = std::sqrt(cl / lot.inspected); }
    double lcl = std::max(0.0,cl - 3 * sigma), ucl = cl + 3 * sigma;
    return {value,lcl,ucl,(value - cl) / sigma,value > ucl ? "high" : value < lcl ? "low" : "ok"};
}
