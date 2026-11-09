#include "boosting.hpp"
double Stump::output(const Vector &row) const {
    std::size_t bin = 0;
    for (double threshold : thresholds)
        bin += row[feature] > threshold;
    return values[bin];
}
Search prepare(const Rows &rows, int bins) {
    Search out;
    for (std::size_t j = 0; j < rows[0].values.size(); ++j) {
        Feature feature;
        feature.order.resize(rows.size());
        std::iota(feature.order.begin(), feature.order.end(), 0);
        std::stable_sort(feature.order.begin(), feature.order.end(),
                         [&](int a, int b) { return rows[a].values[j] < rows[b].values[j]; });
        feature.thresholds.push_back(rows[feature.order[0]].values[j] - 1);
        feature.ends.push_back(0);
        for (std::size_t i = 1; i < feature.order.size(); ++i) {
            const double left = rows[feature.order[i - 1]].values[j],
                         right = rows[feature.order[i]].values[j];
            if (left != right) {
                feature.thresholds.push_back((left + right) / 2);
                feature.ends.push_back(i);
            }
        }
        if (bins > 0)
            for (int b = 1; b < bins; ++b) {
                const int r = b * int(rows.size()) / bins;
                feature.cuts.push_back(
                    (rows[feature.order[r - 1]].values[j] + rows[feature.order[r]].values[j]) / 2);
            }
        out.features.push_back(std::move(feature));
    }
    return out;
}
static Candidate choose(const std::vector<Candidate> &candidates) {
    double minimum = candidates[0].error;
    for (const Candidate &candidate : candidates)
        minimum = std::min(minimum, candidate.error);
    for (const Candidate &candidate : candidates)
        if (candidate.error <= minimum + 0.000000001)
            return candidate;
    return candidates[0];
}
Candidate discrete_stump(const Rows &rows, const Search &search, const Vector &weights) {
    double positive = 0, negative = 0;
    for (std::size_t i = 0; i < rows.size(); ++i)
        if (rows[i].label == 1)
            positive += weights[i];
        else
            negative += weights[i];
    std::vector<Candidate> candidates;
    for (std::size_t j = 0; j < search.features.size(); ++j) {
        const Feature &feature = search.features[j];
        int position = 0;
        double lp = 0, ln = 0;
        for (std::size_t k = 0; k < feature.thresholds.size(); ++k) {
            while (position < feature.ends[k]) {
                const int i = feature.order[position++];
                if (rows[i].label == 1)
                    lp += weights[i];
                else
                    ln += weights[i];
            }
            for (int polarity : Ints{1, -1})
                candidates.push_back(
                    {{int(j), {feature.thresholds[k]}, {double(-polarity), double(polarity)}},
                     polarity == 1 ? lp + (negative - ln) : ln + (positive - lp),
                     polarity});
        }
    }
    return choose(candidates);
}
Candidate regression_stump(const Rows &rows, const Search &search, const Vector &targets,
                           const Vector &weights) {
    double w = 0, s = 0, q = 0;
    for (std::size_t i = 0; i < rows.size(); ++i) {
        w += weights[i];
        s += weights[i] * targets[i];
        q += weights[i] * targets[i] * targets[i];
    }
    std::vector<Candidate> candidates;
    for (std::size_t j = 0; j < search.features.size(); ++j) {
        const Feature &feature = search.features[j];
        int position = 0;
        double wl = 0, sl = 0;
        for (std::size_t k = 0; k < feature.thresholds.size(); ++k) {
            while (position < feature.ends[k]) {
                const int i = feature.order[position++];
                wl += weights[i];
                sl += weights[i] * targets[i];
            }
            const double wr = w - wl, sr = s - sl, al = k == 0 ? 0 : sl / wl, ar = sr / wr,
                         g = k == 0 ? sr * sr / wr : sl * sl / wl + sr * sr / wr;
            candidates.push_back({{int(j), {feature.thresholds[k]}, {al, ar}}, q - g, 0});
        }
    }
    return choose(candidates);
}
Candidate multiclass_stump(const Rows &rows, const Search &search, const Vector &weights, int classes) {
    double w = 0;
    Vector totals(classes);
    for (std::size_t i = 0; i < rows.size(); ++i) {
        w += weights[i];
        totals[rows[i].label - 1] += weights[i];
    }
    std::vector<Candidate> candidates;
    for (std::size_t j = 0; j < search.features.size(); ++j) {
        const Feature &feature = search.features[j];
        int position = 0;
        Vector left(classes);
        for (std::size_t k = 0; k < feature.thresholds.size(); ++k) {
            while (position < feature.ends[k]) {
                const int i = feature.order[position++];
                left[rows[i].label - 1] += weights[i];
            }
            Vector right(classes);
            for (int c = 0; c < classes; ++c)
                right[c] = totals[c] - left[c];
            int a = 0, b = 0;
            for (int c = 1; c < classes; ++c) {
                if (left[c] > left[a])
                    a = c;
                if (right[c] > right[b])
                    b = c;
            }
            candidates.push_back({{int(j), {feature.thresholds[k]}, {double(a + 1), double(b + 1)}},
                                  w - (left[a] + right[b]),
                                  0});
        }
    }
    return choose(candidates);
}
RealCandidate real_stump(const Rows &rows, const Search &search, const Vector &weights, int bins,
                         double smoothing) {
    std::vector<RealCandidate> candidates;
    for (std::size_t j = 0; j < search.features.size(); ++j) {
        Vector positive(bins), negative(bins);
        const Vector &cuts = search.features[j].cuts;
        for (std::size_t i = 0; i < rows.size(); ++i) {
            int bin = 0;
            for (double cut : cuts)
                bin += rows[i].values[j] > cut;
            (rows[i].label == 1 ? positive : negative)[bin] += weights[i];
        }
        double sum = 0;
        Vector values(bins);
        for (int b = 0; b < bins; ++b) {
            sum += std::sqrt(positive[b] * negative[b]);
            values[b] = 0.5 * std::log((positive[b] + smoothing) / (negative[b] + smoothing));
        }
        candidates.push_back({{int(j), cuts, values}, 2 * sum});
    }
    double minimum = candidates[0].z;
    for (const auto &candidate : candidates)
        minimum = std::min(minimum, candidate.z);
    for (const auto &candidate : candidates)
        if (candidate.z <= minimum + 0.000000001)
            return candidate;
    return candidates[0];
}
