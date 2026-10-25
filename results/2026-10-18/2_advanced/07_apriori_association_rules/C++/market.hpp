#pragma once
#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

using Integer = std::int64_t;
using Items = std::vector<std::string>;
using Itemsets = std::vector<Items>;
using Supports = std::map<Items, Integer>;
using Counts = std::map<std::string, Integer>;
using Baskets = std::vector<Items>;
using Taxonomy = std::map<std::string, std::string>;
struct Fraction {
    Integer numerator, denominator;
    Fraction(Integer numerator = 0, Integer denominator = 1);
    Fraction operator+(Fraction other) const;
    Fraction operator-(Fraction other) const;
    Fraction operator*(Fraction other) const;
    Fraction operator/(Fraction other) const;
    int compare(Fraction other) const;
    bool operator<(Fraction other) const { return compare(other) < 0; }
    bool operator>(Fraction other) const { return compare(other) > 0; }
    bool operator<=(Fraction other) const { return compare(other) <= 0; }
    bool operator>=(Fraction other) const { return compare(other) >= 0; }
    bool operator==(Fraction other) const { return numerator == other.numerator && denominator == other.denominator; }
};
struct Product { std::string name, category; Integer price; };
struct Transaction {
    std::string tid, customer;
    int day;
    Counts counts;
    bool add(const std::string& product);
    Items products() const;
    Integer units() const;
};
std::vector<Items> readRecords(const std::string& name);
bool contains(const Items& items, const Items& subset);
Items extendedBasket(const Items& items, const Taxonomy& taxonomy);
Items united(Items first, const Items& second);
struct CandidateLevel { int joined, excluded, pruned; Itemsets itemsets; };
Itemsets smallerSubsets(const Items& itemset);
CandidateLevel generateCandidates(const Itemsets& previous, int size, const Taxonomy* taxonomy);
Supports countSupports(const Baskets& baskets, const Itemsets& candidates);
Integer countSupport(const Baskets& baskets, const Items& itemset);
struct GrowthResult { int headers = 0, nodes = 0, conditionalTrees = 0, conditionalNodes = 0; Supports itemsets; };
GrowthResult fpGrowth(const Baskets& baskets, Integer minimum, int maximum);
struct Rule {
    Items itemset, antecedent, consequent;
    Integer count;
    Fraction support, confidence, lift, leverage, improvement;
    std::optional<Fraction> conviction;
    int rank = 0;
    Rule(Items itemset, Items antecedent, Items consequent, Integer count, Integer total, Integer a, Integer b);
};
struct RuleSet { Integer generated = 0, productive = 0; std::vector<Rule> rules; };
Fraction liftOf(Integer total, Integer together, Integer first, Integer second);
bool meetsThresholds(Fraction confidence, Fraction lift, Fraction minimumConfidence, Fraction minimumLift);
bool ruleBefore(const Rule& first, const Rule& second);
std::string fractionText(Fraction value);
std::string percentText(Integer part, Integer whole);
std::string moneyText(Integer cents);
std::string itemsetText(const Items& itemset);
std::string ruleArrow(const Rule& rule);
Items rulesCsv(const std::vector<Rule>& rules);
void writeReport(const std::string& name, const Items& lines);
