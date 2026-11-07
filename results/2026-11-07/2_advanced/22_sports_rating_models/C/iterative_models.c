#include "ratings.h"

double bradley_terry(int n, const Match *matches, int count, Integer iterations, double *strengths) {
    int wins[30] = {0}, home_wins = 0;
    for (int k = 0; k < count; ++k) {
        wins[matches[k].home] += matches[k].y2;
        wins[matches[k].away] += 2 - matches[k].y2;
        home_wins += matches[k].y2;
    }
    for (int i = 0; i < n; ++i) strengths[i] = 1;
    double theta = 1;
    for (Integer iteration = 0; iteration < iterations; ++iteration) {
        double zeta[30] = {0};
        for (int k = 0; k < count; ++k) {
            int home = matches[k].home, away = matches[k].away;
            double denominator = theta * strengths[home] + strengths[away];
            zeta[home] += theta / denominator;
            zeta[away] += 1 / denominator;
        }
        for (int i = 0; i < n; ++i) strengths[i] = (wins[i] / 2.0) / zeta[i];
        double total = 0;
        for (int i = 0; i < n; ++i) total += strengths[i];
        for (int i = 0; i < n; ++i) strengths[i] = strengths[i] * n / total;
        double denominator = 0;
        for (int k = 0; k < count; ++k) {
            int home = matches[k].home, away = matches[k].away;
            denominator += strengths[home] / (theta * strengths[home] + strengths[away]);
        }
        theta = (home_wins / 2.0) / denominator;
    }
    return theta;
}

void offense_defense(int n, const Match *matches, int count, Integer iterations, double *offense, double *defense, double *ratings) {
    int points[30][30] = {{0}};
    for (int k = 0; k < count; ++k) {
        Match match = matches[k];
        points[match.home][match.away] += match.away_score;
        points[match.away][match.home] += match.home_score;
    }
    for (int i = 0; i < n; ++i) defense[i] = 1;
    for (Integer iteration = 0; iteration < iterations; ++iteration) {
        for (int j = 0; j < n; ++j) {
            double total = 0;
            for (int i = 0; i < n; ++i) total += points[i][j] / defense[i];
            offense[j] = total;
        }
        for (int i = 0; i < n; ++i) {
            double total = 0;
            for (int j = 0; j < n; ++j) total += points[i][j] / offense[j];
            defense[i] = total;
        }
    }
    for (int i = 0; i < n; ++i) ratings[i] = offense[i] / defense[i];
}
