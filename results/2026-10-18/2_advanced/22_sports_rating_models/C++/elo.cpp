#include "ratings.hpp"

double expectedScore(double home, double away, double advantage) { return 1 / (1 + std::pow(10.0, (away - home - advantage) / 400)); }
EloRun runElo(int count, const Matches& matches, Integer coefficient, Integer advantage, Integer initial) {
    EloRun run; run.ratings.assign(count, initial);
    for (std::size_t index = 0; index < matches.size(); ++index) {
        const Match& match = matches[index]; double home = run.ratings[match.home], away = run.ratings[match.away];
        double expected = expectedScore(home, away, advantage), multiplier = 1;
        if (match.margin()) { double difference = match.margin() > 0 ? home + advantage - away : away - home - advantage; multiplier = std::log(std::abs(match.margin()) + 1) * 2.2 / (0.001 * difference + 2.2); }
        double change = coefficient * multiplier * (match.result() - expected);
        run.ratings[match.home] = home + change; run.ratings[match.away] = away - change;
        run.expected.push_back(expected); run.changes.push_back(change);
        if (index + 1 == matches.size() || matches[index + 1].round != match.round) run.rounds.push_back(run.ratings);
    }
    return run;
}
