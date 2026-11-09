#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <functional>
#include <map>
#include <numeric>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Sample = std::vector<Integer>;
using Values = std::vector<double>;
using Lines = std::vector<std::string>;
using Indices = std::vector<std::size_t>;
template<class... Parts> std::string text(const Parts&... parts) {
    std::ostringstream stream;
    (stream << ... << parts);
    return stream.str();
}
template<class... Parts> void add(Lines& lines, const Parts&... parts) { lines.push_back(text(parts...)); }
template<class T> std::string join(const std::vector<T>& values, const std::string& separator = " ") {
    std::ostringstream stream;
    for (std::size_t i = 0; i < values.size(); ++i) { if (i) stream << separator; stream << values[i]; }
    return stream.str();
}
struct Group { std::string name; Sample values; };
struct Settings { Integer seed; int bootstrap, permutations, confidence, pilot, simulations, innerPermutations, bins; };
struct Dataset { std::vector<Group> groups; Sample before, after, differences; std::vector<std::pair<int, int>> pairs; Settings settings; };
Dataset loadDataset();
class Minstd {
    Integer state;
public:
    explicit Minstd(Integer seed) : state(seed) {}
    Integer draw();
    std::size_t below(std::size_t limit);
    void shuffle(Indices& values);
};
Integer sum(const Sample& values);
double sequentialSum(const Values& values);
double mean(const Sample& values);
Integer doubledMedian(Sample values);
double median(const Sample& values);
double trimmedMean(Sample values);
struct Moments { double sd, second, third, fourth; };
Moments moments(const Sample& values);
double sd(const Sample& values);
double mad(const Sample& values);
Integer quantileNumerator(Sample values, int percent);
Sample winsorized(const Sample& values);
double meanDifference(const Sample& first, const Sample& second);
double medianRatio(const Sample& first, const Sample& second);
double hodgesLehmann(const Sample& first, const Sample& second);
double pooledSd(const Sample& first, const Sample& second);
double cohenD(const Sample& first, const Sample& second);
double correlation(const Sample& first, const Sample& second);
std::array<double, 4> groupStatistics(const Sample& sample);
std::array<double, 4> pairStatistics(const Sample& first, const Sample& second);
Indices resampleIndices(Minstd& generator, std::size_t size);
std::vector<Indices> ordinaryIndices(Minstd& generator, std::size_t size, int count);
std::vector<Indices> balancedIndices(Minstd& generator, std::size_t size, int count);
Sample without(const Sample& values, std::size_t index);
std::pair<double, double> meanAndSe(const Values& values);
double phi(double value);
double phiInverse(double probability);
std::pair<Integer, Integer> reduced(Integer numerator, Integer denominator);
Integer contrast(const Sample& first, const Sample& second);
Sample doubledRanks(const Sample& values);
std::map<Integer, Integer> valueCounts(const Sample& values);
std::vector<Sample> divide(const Sample& values, const std::vector<std::size_t>& sizes);
bool nextChoice(Indices& choice, std::size_t total);
struct Anova { double between, within, f; std::vector<double> means; std::size_t count; };
Anova anova(const std::vector<Sample>& samples);
double kruskal(const std::vector<Sample>& rankGroups, double correction);
std::string realText(double value);
std::string pValue(Integer numerator, Integer denominator);
std::string numberList(const Indices& numbers);
int binNumber(double value, double low, double high, int bins);
std::string bar(int count, int top);
void writeLines(const std::string& name, const Lines& lines);
