#include "bayes.hpp"
I parent_row(const Vars &parents, const Assignment &assignment, const Vars &sizes) {
    I row = 0;
    for (int parent : parents)
        row = row * sizes[parent] + assignment[parent];
    return row;
}
double total(const std::vector<double> &values) {
    double out = 0;
    for (double value : values)
        out += value;
    return out;
}
Counts count_samples(int variable, const Vars &parents, const std::vector<Assignment> &samples,
                     const Vars &sizes) {
    I rows = 1;
    for (int parent : parents)
        rows *= sizes[parent];
    Counts counts(static_cast<std::size_t>(rows), std::vector<I>(sizes[variable]));
    for (const Assignment &sample : samples)
        ++counts[parent_row(parents, sample, sizes)][sample[variable]];
    return counts;
}
CPT learn(const Counts &counts, double alpha) {
    CPT out;
    for (const std::vector<I> &row : counts) {
        std::vector<double> probabilities;
        for (I count : row)
            probabilities.push_back(double(count) + alpha);
        double denominator = total(probabilities);
        for (double &value : probabilities)
            value /= denominator;
        out.push_back(probabilities);
    }
    return out;
}
double log_likelihood(const Counts &counts, const CPT &cpt) {
    double out = 0;
    for (int row = 0; row < int(counts.size()); ++row)
        for (int state = 0; state < int(counts[row].size()); ++state)
            if (counts[row][state])
                out += double(counts[row][state]) * std::log(cpt[row][state]);
    return out;
}
I parameter_count(const Counts &counts) { return I(counts[0].size() - 1) * I(counts.size()); }
double family_score(int variable, Vars parents, const std::vector<Assignment> &samples,
                    const Vars &sizes, double alpha) {
    std::sort(parents.begin(), parents.end());
    Counts counts = count_samples(variable, parents, samples, sizes);
    CPT probabilities = learn(counts, alpha);
    return log_likelihood(counts, probabilities) -
           double(parameter_count(counts)) * std::log(double(samples.size())) / 2;
}
