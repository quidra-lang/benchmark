#include "interpolate.hpp"

#include <algorithm>

#include "lexer.hpp"

Expander::Expander(std::map<std::string, std::string> values,
                   std::map<std::string, Origin> origins)
    : values_(std::move(values)), origins_(std::move(origins)) {}

void Expander::report(const Origin& origin, const std::string& code, const std::string& message) {
    diagnostics_.push_back({origin.document, origin.line, code, message});
}

std::optional<std::string> Expander::expand(const std::string& key) {
    auto found = results_.find(key);
    if (found != results_.end()) {
        return found->second;
    }
    in_progress_.push_back(key);
    std::optional<std::string> result = evaluate(key);
    in_progress_.pop_back();
    results_[key] = result;
    return result;
}

std::optional<std::string> Expander::evaluate(const std::string& key) {
    const std::string& value = values_.at(key);
    const Origin& origin = origins_.at(key);
    std::string section = key.substr(0, key.rfind('.'));
    std::string result;
    size_t position = 0;
    while (position < value.size()) {
        if (value.compare(position, 2, "${") != 0) {
            char character = value[position];
            result += character == LITERAL_DOLLAR ? '$' : character;
            position++;
            continue;
        }
        size_t close = value.find('}', position + 2);
        std::string reference =
            close == std::string::npos ? "" : value.substr(position + 2, close - position - 2);
        if (close == std::string::npos || !is_section_name(reference)) {
            report(origin, "E_BAD_REF", key + ": invalid reference");
            return std::nullopt;
        }
        std::string target =
            reference.find('.') != std::string::npos ? reference : section + "." + reference;
        if (values_.count(target) == 0) {
            report(origin, "E_UNDEFINED", key + ": undefined reference " + target);
            return std::nullopt;
        }
        std::optional<std::string> expanded;
        if (std::find(in_progress_.begin(), in_progress_.end(), target) != in_progress_.end()) {
            report_cycle(target);
        } else {
            expanded = expand(target);
        }
        if (!expanded) {
            if (cycle_keys_.count(key) == 0) {
                report(origin, "E_DEPENDENCY", key + ": depends on failed key " + target);
            }
            return std::nullopt;
        }
        result += *expanded;
        position = close + 1;
    }
    return result;
}

void Expander::report_cycle(const std::string& target) {
    auto start = std::find(in_progress_.begin(), in_progress_.end(), target);
    std::vector<std::string> path(start, in_progress_.end());
    path.push_back(target);
    report(origins_.at(target), "E_CYCLE", "interpolation cycle " + join(path, " -> "));
    cycle_keys_.insert(path.begin(), path.end());
}
