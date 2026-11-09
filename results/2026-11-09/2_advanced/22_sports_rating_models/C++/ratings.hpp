#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Values = std::vector<double>;
using Integers = std::vector<int>;
using Lines = std::vector<std::string>;
template<class... Parts> std::string text(const Parts&... parts) { std::ostringstream stream; (stream << ... << parts); return stream.str(); }
template<class... Parts> void add(Lines& lines, const Parts&... parts) { lines.push_back(text(parts...)); }
struct Fraction {
    Integer numerator = 0, denominator = 1;
    Fraction(Integer numerator = 0, Integer denominator = 1);
    double real() const { return static_cast<double>(numerator) / static_cast<double>(denominator); }
};
Fraction operator+(Fraction first, Fraction second);
Fraction operator-(Fraction first, Fraction second);
Fraction operator*(Fraction value, Integer multiplier);
Fraction operator/(Fraction value, Integer divisor);
bool operator<(Fraction first, Fraction second);
bool operator>(Fraction first, Fraction second);
bool operator==(Fraction first, Fraction second);
using Fractions = std::vector<Fraction>;
std::string fixed(double value, int places = 4);
std::string fixed(Fraction value, int places = 4);
Integer decimalValue(double value, int places);
std::string fractionText(Fraction value);
std::string fractionWithReal(Fraction value);
void writeLines(const std::string& name, const Lines& lines);
struct Team { std::string id, name; };
struct Match {
    int round, home, away, homeScore, awayScore;
    int margin() const { return homeScore - awayScore; }
    int doubledResult() const { return homeScore > awayScore ? 2 : homeScore == awayScore ? 1 : 0; }
    double result() const { return doubledResult() / 2.0; }
};
using Matches = std::vector<Match>;
struct Settings {
    Integer winPoints, drawPoints, seed, closeMargin, eloK, eloHome, eloInitial, btIterations, odIterations, linkIterations, upsets;
    int formLength, holdoutRound, bins, simulations, top, bottom;
    double exponent;
    std::vector<Integer> gridK, gridHome;
};
struct Season { std::vector<Team> teams; Matches matches; Settings settings; };
Season readSeason();
Matches matchesBefore(const Matches& matches, int round);
double expectedScore(double home, double away, double advantage);
struct EloRun { Values ratings, expected, changes; std::vector<Values> rounds; };
EloRun runElo(int count, const Matches& matches, Integer coefficient, Integer advantage, Integer initial);
Values colleyRatings(int count, const Matches& matches);
std::pair<Values, double> masseyRatings(int count, const Matches& matches);
std::pair<Values, double> bradleyTerry(int count, const Matches& matches, Integer iterations);
struct OffenseDefense { Values offense, defense, ratings; };
OffenseDefense offenseDefense(int count, const Matches& matches, Integer iterations);
double sigma(double value);
std::pair<double, double> fitLink(const Values& features, const Values& results, Integer iterations);
double logLoss(double probability, double result);
double brierScore(double probability, double result);
Fraction correctness(double probability, int doubledResult);
Fraction kendallTau(const Fractions& first, const Fractions& second);
Fraction spearmanRho(const Fractions& first, const Fractions& second);
