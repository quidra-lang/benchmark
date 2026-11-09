#include "knn.hpp"
#include <algorithm>
#include <cmath>

Scaling computeScaling(const Rows& rows, const std::string& method) {
    Scaling result;
    for (int feature = 0; feature < static_cast<int>(rows[0]->values.size()); ++feature) {
        double center = 0, scale = 0;
        if (method == "standard") {
            for (const Row* row : rows) center += row->values[feature]; center /= rows.size();
            if (rows.size() > 1) { for (const Row* row : rows) scale += (row->values[feature] - center) * (row->values[feature] - center); scale = std::sqrt(scale / (rows.size() - 1)); }
        } else {
            double low = rows[0]->values[feature], high = low;
            for (const Row* row : rows) { low = std::min(low,row->values[feature]); high = std::max(high,row->values[feature]); }
            center = low; scale = high - low;
        }
        result.centers.push_back(center); result.scales.push_back(scale);
    }
    return result;
}
Vector Scaling::transform(const Row& row, const Indices& features) const {
    Vector result; for (int feature : features) result.push_back(scales[feature] > 0 ? (row.values[feature] - centers[feature]) / scales[feature] : 0); return result;
}
