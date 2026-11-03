#include "market.hpp"
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>

static std::string padded(Integer value, int width) { std::ostringstream out; out << std::setfill('0') << std::setw(width) << value; return out.str(); }
std::string fractionText(Fraction value) {
    Integer numerator = value.numerator < 0 ? -value.numerator : value.numerator, scaled = 10000 * numerator / value.denominator;
    std::string decimal = std::to_string(scaled / 10000) + "." + padded(scaled % 10000,4);
    return (value.numerator < 0 ? "-" : "") + std::to_string(numerator) + "/" + std::to_string(value.denominator) + "=" + (value.numerator < 0 && scaled > 0 ? "-" : "") + decimal;
}
std::string percentText(Integer part, Integer whole) { Integer scaled = 10000 * part / whole; return std::to_string(scaled / 100) + "." + padded(scaled % 100,2) + "%"; }
std::string moneyText(Integer cents) { return std::to_string(cents / 100) + "." + padded(cents % 100,2); }
std::string itemsetText(const Items& items) { std::string result; for (const std::string& item : items) { if (!result.empty()) result += "+"; result += item; } return result; }
std::string ruleArrow(const Rule& rule) { return itemsetText(rule.antecedent) + " -> " + itemsetText(rule.consequent); }
Items rulesCsv(const std::vector<Rule>& rules) {
    Items result{"rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement"};
    for (const Rule& rule : rules) {
        Items fields{std::to_string(rule.rank),itemsetText(rule.antecedent),itemsetText(rule.consequent),std::to_string(rule.count),fractionText(rule.support),fractionText(rule.confidence),fractionText(rule.lift),fractionText(rule.leverage),rule.conviction ? fractionText(*rule.conviction) : "INF",fractionText(rule.improvement)};
        std::string line; for (const std::string& field : fields) { if (!line.empty()) line += ","; line += field; } result.push_back(line);
    }
    return result;
}
void writeReport(const std::string& name, const Items& lines) { std::filesystem::create_directories("output"); std::ofstream file("output/" + name,std::ios::binary); for (const std::string& line : lines) file << line << '\n'; }
