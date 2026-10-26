#include "ratings.hpp"

std::pair<Values, double> bradleyTerry(int count, const Matches& matches, Integer iterations) {
    Values wins(count), strengths(count, 1); double homeWins = 0, theta = 1;
    for (const Match& match : matches) { wins[match.home] += match.result(); wins[match.away] += 1 - match.result(); homeWins += match.result(); }
    for (Integer iteration = 0; iteration < iterations; ++iteration) {
        Values zeta(count);
        for (const Match& match : matches) { double denominator = theta * strengths[match.home] + strengths[match.away]; zeta[match.home] += theta / denominator; zeta[match.away] += 1 / denominator; }
        for (int i = 0; i < count; ++i) strengths[i] = wins[i] / zeta[i];
        double sum = 0; for (double strength : strengths) sum += strength;
        for (double& strength : strengths) strength = strength * count / sum;
        double denominator = 0; for (const Match& match : matches) denominator += strengths[match.home] / (theta * strengths[match.home] + strengths[match.away]);
        theta = homeWins / denominator;
    }
    return {strengths, theta};
}
OffenseDefense offenseDefense(int count, const Matches& matches, Integer iterations) {
    std::vector<Integers> points(count, Integers(count)); OffenseDefense fit{Values(count), Values(count, 1), Values(count)};
    for (const Match& match : matches) { points[match.home][match.away] += match.awayScore; points[match.away][match.home] += match.homeScore; }
    for (Integer iteration = 0; iteration < iterations; ++iteration) {
        for (int j = 0; j < count; ++j) { double sum = 0; for (int i = 0; i < count; ++i) sum += points[i][j] / fit.defense[i]; fit.offense[j] = sum; }
        for (int i = 0; i < count; ++i) { double sum = 0; for (int j = 0; j < count; ++j) sum += points[i][j] / fit.offense[j]; fit.defense[i] = sum; }
    }
    for (int i = 0; i < count; ++i) fit.ratings[i] = fit.offense[i] / fit.defense[i];
    return fit;
}
