#include "ratings.h"

double expected_score(double home, double away, double advantage) {
    return 1 / (1 + pow(10, (away - home - advantage) / 400));
}
static double multiplier(const Match *match, double home, double away, double advantage) {
    int goals = abs(match->margin);
    if (!goals) return 1;
    double difference = match->margin > 0 ? home + advantage - away : away - home - advantage;
    return log(goals + 1) * 2.2 / (0.001 * difference + 2.2);
}
EloRun run_elo(int n, const Match *matches, int count, Integer k, Integer home, Integer initial) {
    EloRun run = {0};
    for (int i = 0; i < n; ++i) run.ratings[i] = (double)initial;
    for (int i = 0; i < count; ++i) {
        const Match *match = &matches[i];
        double first = run.ratings[match->home], second = run.ratings[match->away];
        double expected = expected_score(first, second, (double)home);
        double weight = multiplier(match, first, second, (double)home);
        double change = (double)k * weight * (match_result(match) - expected);
        run.ratings[match->home] = first + change;
        run.ratings[match->away] = second - change;
        run.expected[i] = expected;
        run.changes[i] = change;
        if (i + 1 == count || matches[i + 1].round != match->round) memcpy(run.round_ratings[match->round - 1], run.ratings, (size_t)n * sizeof(double));
    }
    return run;
}
