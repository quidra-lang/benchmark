#include "mrp.hpp"
#include <algorithm>

Integer lotSize(const Item& item, int week, Integer projected, const Values& receipts, const Values& gross, int horizon) {
    Integer quantity = item.safety - projected;
    if (item.rule == "LFL") return quantity;
    if (item.rule == "FOQ") return (quantity + item.first - 1) / item.first * item.first;
    if (item.rule == "MIN") return (std::max(quantity, item.first) + item.second - 1) / item.second * item.second;
    int end = static_cast<int>(std::min<Integer>(week + item.first - 1, horizon));
    for (int later = week + 1; later <= end; ++later) { projected += receipts[later] - gross[later]; quantity = std::max(quantity, item.safety - projected); }
    return quantity;
}
