#pragma once

#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "ini_parser.hpp"

class Expander {
public:
    Expander(std::map<std::string, std::string> values, std::map<std::string, Origin> origins);

    std::optional<std::string> expand(const std::string& key);
    const std::vector<Diagnostic>& diagnostics() const { return diagnostics_; }

private:
    std::map<std::string, std::string> values_;
    std::map<std::string, Origin> origins_;
    std::map<std::string, std::optional<std::string>> results_;
    std::vector<std::string> in_progress_;
    std::set<std::string> cycle_keys_;
    std::vector<Diagnostic> diagnostics_;

    void report(const Origin& origin, const std::string& code, const std::string& message);
    std::optional<std::string> evaluate(const std::string& key);
    void report_cycle(const std::string& target);
};
