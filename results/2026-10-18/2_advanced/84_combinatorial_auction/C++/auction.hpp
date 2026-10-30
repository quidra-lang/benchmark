#ifndef AUCTION_HPP
#define AUCTION_HPP
#include <cstdint>
#include <map>
#include <ostream>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Money = std::int64_t;
struct Fraction {
    Money numerator = 0, denominator = 1;
    Fraction(Money = 0, Money = 1);
    Fraction operator+(Fraction) const;
    Fraction operator-(Fraction) const;
    Fraction operator*(Fraction) const;
    Fraction operator/(Fraction) const;
    int compare(Fraction) const;
};
std::ostream &operator<<(std::ostream &, Fraction);
template <typename... Values> std::string text(const Values &...values) {
    std::ostringstream output;
    (output << ... << values);
    return output.str();
}
template <typename... Values> void line(std::vector<std::string> &output, const Values &...values) {
    output.push_back(text(values...));
}
struct Item {
    std::string name;
    Money reserve;
};
struct BidLine {
    std::string name, language;
    std::vector<std::string> bids;
};
struct RawAuction {
    std::string name;
    std::vector<std::string> offered;
    std::vector<BidLine> lines;
};
struct Participant {
    std::string name;
    Money value, bid;
};
struct Group {
    std::string kind, name;
    std::vector<std::string> arguments;
    std::vector<Participant> participants;
};
struct Input {
    std::vector<Item> items;
    std::map<std::string, RawAuction> auctions;
    std::vector<Group> groups;
    std::vector<std::string> runs;
    std::map<std::string, Money> parameters;
};
struct Bid {
    int number, bidder, mask, size;
    Money amount, reserve;
    bool exclusive;
};
using Bids = std::vector<const Bid *>;
Input readInput();
std::vector<std::string> readLines(const std::string &);
std::vector<std::string> words(const std::string &);
struct Improvement {
    int node;
    Money welfare;
    Bids bids;
};
struct SearchResult {
    Money welfare = 0;
    Bids bids;
    int nodes = 0, pruned = 0, leaves = 0, improvements = 0;
    std::vector<Improvement> records;
    std::vector<Fraction> shares;
    std::vector<int> sources;
    Fraction bound;
};
SearchResult solveWdp(const std::vector<Item> &, int, const Bids &);
Bids greedyOrder(Bids);
Bids greedySelect(const Bids &, int = 0);
int population(int);
struct VcgPayment {
    Money value = 0, without = 0, payment = 0, utility = 0;
    Bids won, alternative;
};
std::vector<VcgPayment> vcgPayments(const std::vector<Item> &, int, int, const Bids &, const Bids &,
                                    Money);
struct Critical {
    Money payment;
    int rival;
};
std::map<int, Critical> criticalPayments(const Bids &, const Bids &);
struct Coalition {
    int mask;
    Money welfare;
    Bids bids;
    std::vector<int> members;
};
struct Blocking {
    std::size_t coalition;
    Money payoff, deficit;
    bool minimal;
};
std::vector<Coalition> coalitions(const std::vector<Item> &, int, int, const Bids &);
std::vector<Blocking> blockers(const std::vector<Coalition> &, Money, const std::vector<Money> &);
Money gspPrice(const std::vector<Participant> &, const std::vector<int> &, int);
Fraction slotVcg(const std::vector<Participant> &, const std::vector<int> &,
                 const std::vector<Fraction> &, int);
struct Candidate {
    int mask;
    Money value;
};
std::vector<Candidate> candidates(const Bids &, bool);
Money candidateValue(const std::vector<Candidate> &, int);
struct ClockResult {
    int winner = -1, steps = 0;
    Money price = 0;
    std::vector<Money> drops;
};
ClockResult english(const std::vector<Participant> &, Money, Money);
ClockResult dutch(const std::vector<Participant> &, Money, Money, Money);
std::string join(const std::vector<std::string> &, const std::string &);
std::string bundle(const std::vector<Item> &, int);
std::string numberList(const Bids &);
void writeLines(const std::string &, const std::vector<std::string> &);
#endif
