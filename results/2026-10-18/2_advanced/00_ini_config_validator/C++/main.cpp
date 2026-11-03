#include <algorithm>
#include <cctype>
#include <filesystem>
#include <map>
#include <optional>
#include <regex>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "emitter.hpp"
#include "ini_parser.hpp"
#include "interpolate.hpp"
#include "lexer.hpp"
#include "schema.hpp"

namespace {

const std::string INPUT_DIR = "input";
const std::string OUTPUT_DIR = "output";
const std::set<std::string> NUMERIC_TYPES = {"int", "size", "duration"};
const std::set<std::string> TRUE_WORDS = {"true", "yes", "on", "1"};
const std::set<std::string> FALSE_WORDS = {"false", "no", "off", "0"};
const std::map<std::string, long long> SIZE_FACTORS = {
    {"", 1}, {"b", 1}, {"kb", 1024}, {"mb", 1048576}, {"gb", 1073741824}};
const std::map<std::string, int> DEFAULT_PORTS = {{"http", 80}, {"https", 443}};
const int DAYS_IN_MONTH[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
const std::string IPV4_CHARACTERS = "0123456789.";
const std::string PATH_FORBIDDEN = " \n\t";
const std::regex INT_PATTERN(R"(([+-]?)(?:0[xX]([0-9a-fA-F]{1,10})|([0-9](?:_?[0-9])*)))");
const std::regex SIZE_PATTERN(R"(([0-9]{1,6})(?:\.([0-9]{1,3}))?([A-Za-z]*))");
const std::regex SECONDS_PATTERN("[0-9]{1,6}");
const std::regex DURATION_PATTERN("(?:([0-9]{1,6})h)?(?:([0-9]{1,6})m)?(?:([0-9]{1,6})s)?");
const std::regex LABEL_PATTERN("[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?");
const std::regex SCHEME_PATTERN("[A-Za-z][A-Za-z0-9+.-]*");
const std::regex PORT_PATTERN("[1-9][0-9]{0,4}");
const std::regex DATE_PATTERN("[0-9]{4}-[0-9]{2}-[0-9]{2}");

std::pair<std::string, std::string> split_key(const std::string& key) {
    size_t dot = key.rfind('.');
    return {key.substr(0, dot), key.substr(dot + 1)};
}

bool key_order(const std::string& left, const std::string& right) {
    return split_key(left) < split_key(right);
}

std::string section_of(const std::string& key) {
    return key.substr(0, key.rfind('.'));
}

template <typename Map>
std::vector<std::string> sorted_keys(const Map& map) {
    std::vector<std::string> keys;
    for (const auto& entry : map) {
        keys.push_back(entry.first);
    }
    std::sort(keys.begin(), keys.end(), key_order);
    return keys;
}

std::string to_lower(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(),
                   [](unsigned char character) { return std::tolower(character); });
    return text;
}

std::optional<long long> parse_int(const std::string& text) {
    std::smatch match;
    if (!std::regex_match(text, match, INT_PATTERN)) {
        return std::nullopt;
    }
    long long number;
    if (match[2].matched) {
        number = std::stoll(match[2].str(), nullptr, 16);
    } else {
        std::string digits = match[3].str();
        digits.erase(std::remove(digits.begin(), digits.end(), '_'), digits.end());
        if (digits.size() > 12) {
            return std::nullopt;
        }
        number = std::stoll(digits);
    }
    return match[1] == "-" ? -number : number;
}

std::optional<bool> parse_bool(const std::string& text) {
    std::string lowered = to_lower(text);
    if (TRUE_WORDS.count(lowered) > 0) {
        return true;
    }
    if (FALSE_WORDS.count(lowered) > 0) {
        return false;
    }
    return std::nullopt;
}

std::optional<std::string> parse_enum(const std::string& text,
                                      const std::vector<std::string>& values) {
    std::string lowered = to_lower(text);
    if (std::find(values.begin(), values.end(), lowered) == values.end()) {
        return std::nullopt;
    }
    return lowered;
}

std::optional<long long> parse_size(const std::string& text) {
    std::smatch match;
    if (!std::regex_match(text, match, SIZE_PATTERN)) {
        return std::nullopt;
    }
    auto factor = SIZE_FACTORS.find(to_lower(match[3].str()));
    if (factor == SIZE_FACTORS.end()) {
        return std::nullopt;
    }
    long long whole = std::stoll(match[1].str());
    if (!match[2].matched) {
        return whole * factor->second;
    }
    std::string fraction = match[2].str();
    long long scaled = std::stoll(fraction) * factor->second;
    long long divisor = 1;
    for (size_t i = 0; i < fraction.size(); i++) {
        divisor *= 10;
    }
    if (scaled % divisor != 0) {
        return std::nullopt;
    }
    return whole * factor->second + scaled / divisor;
}

std::optional<long long> parse_duration(const std::string& text) {
    if (std::regex_match(text, SECONDS_PATTERN)) {
        return std::stoll(text);
    }
    std::smatch match;
    if (text.empty() || !std::regex_match(text, match, DURATION_PATTERN)) {
        return std::nullopt;
    }
    auto part = [&match](int index) {
        return match[index].matched ? std::stoll(match[index].str()) : 0LL;
    };
    return part(1) * 3600 + part(2) * 60 + part(3);
}

bool is_ipv4(const std::string& text) {
    std::vector<std::string> parts = split(text, '.');
    if (parts.size() != 4) {
        return false;
    }
    for (const std::string& part : parts) {
        if (part.empty() || part.size() > 3) {
            return false;
        }
        if (part != "0" && part.front() == '0') {
            return false;
        }
        if (std::stoi(part) > 255) {
            return false;
        }
    }
    return true;
}

std::optional<std::string> parse_host(const std::string& text) {
    if (text.find_first_not_of(IPV4_CHARACTERS) == std::string::npos) {
        if (!is_ipv4(text)) {
            return std::nullopt;
        }
        return text;
    }
    if (text.size() > 253) {
        return std::nullopt;
    }
    for (const std::string& label : split(text, '.')) {
        if (!std::regex_match(label, LABEL_PATTERN)) {
            return std::nullopt;
        }
    }
    return to_lower(text);
}

std::optional<std::string> parse_path(const std::string& text) {
    if (text.empty() || text.find_first_of(PATH_FORBIDDEN) != std::string::npos) {
        return std::nullopt;
    }
    bool absolute = text.front() == '/';
    std::vector<std::string> parts;
    for (const std::string& part : split(text, '/')) {
        if (part.empty() || part == ".") {
            continue;
        }
        if (part != "..") {
            parts.push_back(part);
        } else if (!parts.empty() && parts.back() != "..") {
            parts.pop_back();
        } else if (absolute) {
            return std::nullopt;
        } else {
            parts.push_back(part);
        }
    }
    if (absolute) {
        return "/" + join(parts, "/");
    }
    return parts.empty() ? "." : join(parts, "/");
}

std::optional<std::string> parse_url(const std::string& text) {
    size_t separator = text.find("://");
    if (separator == std::string::npos) {
        return std::nullopt;
    }
    std::string scheme = text.substr(0, separator);
    std::string rest = text.substr(separator + 3);
    if (!std::regex_match(scheme, SCHEME_PATTERN) || rest.find_first_of("?#") != std::string::npos) {
        return std::nullopt;
    }
    size_t slash = rest.find('/');
    std::string authority = rest.substr(0, slash);
    std::string path = slash == std::string::npos ? "" : rest.substr(slash + 1);
    size_t colon = authority.find(':');
    std::optional<std::string> host = parse_host(authority.substr(0, colon));
    std::optional<std::string> path_value = parse_path("/" + path);
    if (!host || !path_value) {
        return std::nullopt;
    }
    scheme = to_lower(scheme);
    std::string result = scheme + "://" + *host;
    if (colon != std::string::npos) {
        std::string port = authority.substr(colon + 1);
        if (!std::regex_match(port, PORT_PATTERN) || std::stoi(port) > 65535) {
            return std::nullopt;
        }
        auto default_port = DEFAULT_PORTS.find(scheme);
        if (default_port == DEFAULT_PORTS.end() || default_port->second != std::stoi(port)) {
            result += ":" + port;
        }
    }
    return result + *path_value;
}

bool is_leap_year(int year) {
    return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
}

std::optional<std::string> parse_date(const std::string& text) {
    if (!std::regex_match(text, DATE_PATTERN)) {
        return std::nullopt;
    }
    int year = std::stoi(text.substr(0, 4));
    int month = std::stoi(text.substr(5, 2));
    int day = std::stoi(text.substr(8));
    if (year < 1 || month < 1 || month > 12) {
        return std::nullopt;
    }
    int days = DAYS_IN_MONTH[month - 1];
    if (month == 2 && is_leap_year(year)) {
        days = 29;
    }
    if (day < 1 || day > days) {
        return std::nullopt;
    }
    return text;
}

std::optional<long long> parse_number(const std::string& kind, const std::string& text) {
    if (kind == "int") {
        return parse_int(text);
    }
    if (kind == "size") {
        return parse_size(text);
    }
    return parse_duration(text);
}

std::optional<std::string> parse_text(const std::string& kind, const std::string& text,
                                      const std::vector<std::string>& values) {
    if (kind == "string") {
        return text;
    }
    if (kind == "enum") {
        return parse_enum(text, values);
    }
    if (kind == "host") {
        return parse_host(text);
    }
    if (kind == "path") {
        return parse_path(text);
    }
    if (kind == "url") {
        return parse_url(text);
    }
    return parse_date(text);
}

std::optional<Value> parse_scalar(const std::string& kind, const std::string& text,
                                  const std::vector<std::string>& values) {
    Value value;
    if (NUMERIC_TYPES.count(kind) > 0) {
        std::optional<long long> number = parse_number(kind, text);
        if (!number) {
            return std::nullopt;
        }
        value.number = *number;
    } else if (kind == "bool") {
        std::optional<bool> flag = parse_bool(text);
        if (!flag) {
            return std::nullopt;
        }
        value.flag = *flag;
    } else {
        std::optional<std::string> parsed = parse_text(kind, text, values);
        if (!parsed) {
            return std::nullopt;
        }
        value.text = *parsed;
    }
    return value;
}

std::string checked_text(const std::string& text, bool secret) {
    return secret ? MASK : string_notation(text);
}

class CheckError : public std::runtime_error {
public:
    CheckError(std::string code, const std::string& message)
        : std::runtime_error(message), code(std::move(code)) {}

    std::string code;
};

CheckError invalid_value(const std::string& key, const std::string& kind,
                         const std::vector<std::string>& values, const std::string& display) {
    if (kind == "enum") {
        return CheckError("E_ENUM", key + ": " + display + " is not one of " + join(values, ","));
    }
    return CheckError("E_TYPE", key + ": " + display + " is not a valid " + kind);
}

std::optional<Value> bound_value(const std::string& kind, const std::string& text) {
    if (text.empty()) {
        return std::nullopt;
    }
    if (kind == "string" || kind == "list") {
        Value bound;
        bound.number = std::stoll(text);
        return bound;
    }
    return parse_scalar(kind, text, {});
}

void check_range(const std::string& key, const Spec& spec, const Value& value) {
    std::optional<Value> lower = bound_value(spec.kind, spec.range->lower);
    std::optional<Value> upper = bound_value(spec.kind, spec.range->upper);
    std::string measure_kind = spec.kind;
    Value measure = value;
    std::string display;
    if (spec.kind == "string") {
        measure_kind = "int";
        measure.number = static_cast<long long>(value.text.size());
        display = "length " + std::to_string(measure.number);
    } else if (spec.kind == "list") {
        measure_kind = "int";
        measure.number = static_cast<long long>(value.items.size());
        display = "count " + std::to_string(measure.number);
    } else {
        display = spec.secret ? MASK : value_notation(spec.kind, "", value);
    }
    auto less = [&measure_kind](const Value& left, const Value& right) {
        return measure_kind == "date" ? left.text < right.text : left.number < right.number;
    };
    auto bound_text = [&measure_kind](const std::optional<Value>& bound) {
        return bound ? value_notation(measure_kind, "", *bound) : "";
    };
    if ((lower && less(measure, *lower)) || (upper && less(*upper, measure))) {
        throw CheckError("E_RANGE", key + ": " + display + " is out of range " +
                                        bound_text(lower) + ".." + bound_text(upper));
    }
}

class Library {
public:
    explicit Library(std::string directory) : directory_(std::move(directory)) {}

    const Document* find(const std::string& name) {
        auto found = documents_.find(name);
        if (found == documents_.end()) {
            std::string path = directory_ + "/" + name + ".ini";
            std::optional<Document> document;
            if (std::filesystem::is_regular_file(path)) {
                document = parse_document(name, read_lines(path));
            }
            found = documents_.emplace(name, document).first;
        }
        return found->second ? &*found->second : nullptr;
    }

private:
    std::string directory_;
    std::map<std::string, std::optional<Document>> documents_;
};

struct Inheritance {
    std::string parent;
    Origin origin;
};

class Profile {
public:
    Profile(int number, const std::string& line) : number_(number) {
        std::vector<std::string> words = split(line, ' ');
        result_.name = words[0];
        root_ = words[1];
        overrides_.assign(words.begin() + 2, words.end());
    }

    ProfileResult process(const Schema& schema, Library& library,
                          const std::vector<ProfileResult>& earlier) {
        apply(library, root_, {root_});
        apply_overrides();
        inherit_sections();
        resolve_aliases(schema);
        std::set<std::string> sections = fill_defaults(schema);
        std::set<std::string> configured;
        for (const auto& entry : configuration_) {
            configured.insert(entry.first);
        }
        check_types(schema, expand_values());
        check_order();
        check_required(schema, sections, configured);
        check_fixed(earlier);
        summarize(configured.size());
        return result_;
    }

private:
    int number_;
    std::string root_;
    std::vector<std::string> overrides_;
    std::map<std::string, Definition> configuration_;
    int definition_count_ = 0;
    std::map<std::string, Inheritance> parents_;
    std::set<Diagnostic> reported_;
    ProfileResult result_;

    void report(const Origin& origin, const std::string& code, const std::string& message) {
        reported_.insert({origin.document, origin.line, code, message});
    }

    void define(const std::string& key, const std::string& value, const Origin& origin) {
        definition_count_++;
        std::vector<Origin> history;
        auto current = configuration_.find(key);
        if (current != configuration_.end()) {
            history = current->second.history;
        }
        if (history.empty() || history.back() != origin) {
            history.push_back(origin);
        }
        configuration_[key] = Definition{value, origin, definition_count_, history};
    }

    void apply(Library& library, const std::string& name, const std::vector<std::string>& chain) {
        const Document* document = library.find(name);
        result_.tree.push_back({static_cast<int>(chain.size()) - 1, name});
        reported_.insert(document->diagnostics.begin(), document->diagnostics.end());
        for (const Statement& statement : document->statements) {
            Origin origin{name, statement.line};
            switch (statement.kind) {
            case StatementKind::Assign:
                define(statement.target, statement.value, origin);
                break;
            case StatementKind::Append:
                append(statement.target, statement.value, origin);
                break;
            case StatementKind::Unset:
                unset(statement.target, origin);
                break;
            case StatementKind::Inherit:
                parents_[statement.target] = Inheritance{statement.value, origin};
                break;
            case StatementKind::Include:
                include(library, statement.target, chain, origin);
                break;
            }
        }
    }

    void append(const std::string& key, const std::string& value, const Origin& origin) {
        auto current = configuration_.find(key);
        if (current != configuration_.end() && !current->second.value.empty()) {
            define(key, current->second.value + "," + value, origin);
        } else {
            define(key, value, origin);
        }
    }

    void unset(const std::string& key, const Origin& origin) {
        if (configuration_.erase(key) == 0) {
            report(origin, "W_UNSET", key + " is not set");
        }
    }

    void include(Library& library, const std::string& name, const std::vector<std::string>& chain,
                 const Origin& origin) {
        int depth = static_cast<int>(chain.size());
        auto position = std::find(chain.begin(), chain.end(), name);
        if (position != chain.end()) {
            std::vector<std::string> path(position, chain.end());
            path.push_back(name);
            report(origin, "E_INCLUDE_CYCLE", "include cycle " + join(path, " -> "));
            result_.tree.push_back({depth, name + " (cycle)"});
        } else if (library.find(name) == nullptr) {
            report(origin, "E_INCLUDE_MISSING", "missing document " + name);
            result_.tree.push_back({depth, name + " (missing)"});
        } else {
            std::vector<std::string> extended = chain;
            extended.push_back(name);
            apply(library, name, extended);
        }
    }

    void apply_overrides() {
        for (const std::string& assignment : overrides_) {
            size_t equals = assignment.find('=');
            define(assignment.substr(0, equals), assignment.substr(equals + 1),
                   Origin{"manifest", number_});
        }
    }

    void inherit_sections() {
        std::map<std::string, std::vector<std::pair<std::string, Definition>>> own_keys;
        for (const auto& [key, definition] : configuration_) {
            auto [section, name] = split_key(key);
            own_keys[section].emplace_back(name, definition);
        }
        for (const auto& [section, inheritance] : parents_) {
            std::vector<std::string> chain{section};
            while (parents_.count(chain.back()) > 0 &&
                   std::find(chain.begin(), chain.end(), parents_.at(chain.back()).parent) ==
                       chain.end()) {
                chain.push_back(parents_.at(chain.back()).parent);
            }
            auto last = parents_.find(chain.back());
            if (last != parents_.end()) {
                std::vector<std::string> path = chain;
                path.push_back(last->second.parent);
                report(inheritance.origin, "E_INHERIT_CYCLE",
                       "inheritance cycle " + join(path, " -> "));
                continue;
            }
            if (parents_.count(inheritance.parent) == 0 && own_keys.count(inheritance.parent) == 0) {
                report(inheritance.origin, "W_PARENT_EMPTY",
                       "section " + section + " inherits from empty section " + inheritance.parent);
            }
            for (size_t i = 1; i < chain.size(); i++) {
                auto ancestor = own_keys.find(chain[i]);
                if (ancestor == own_keys.end()) {
                    continue;
                }
                for (const auto& [name, definition] : ancestor->second) {
                    configuration_.emplace(section + "." + name, definition);
                }
            }
        }
    }

    void resolve_aliases(const Schema& schema) {
        for (const Spec& spec : schema.specs()) {
            std::vector<std::string> aliases;
            for (const std::string& alias : spec.aliases) {
                if (configuration_.count(alias) > 0) {
                    aliases.push_back(alias);
                }
            }
            if (aliases.empty()) {
                continue;
            }
            std::vector<std::string> candidates;
            if (configuration_.count(spec.pattern) > 0) {
                candidates.push_back(spec.pattern);
            }
            candidates.insert(candidates.end(), aliases.begin(), aliases.end());
            std::string winner = candidates.front();
            for (const std::string& candidate : candidates) {
                if (configuration_.at(candidate).number > configuration_.at(winner).number) {
                    winner = candidate;
                }
            }
            Definition chosen = configuration_.at(winner);
            for (const std::string& candidate : candidates) {
                const Origin& origin = configuration_.at(candidate).origin;
                if (candidate != spec.pattern) {
                    report(origin, "W_DEPRECATED",
                           candidate + " is deprecated, use " + spec.pattern);
                }
                if (candidate != winner) {
                    report(origin, "W_SHADOWED",
                           candidate + " is superseded by " + winner + " at " +
                               origin_text(chosen.origin));
                }
            }
            configuration_[spec.pattern] = chosen;
            for (const std::string& alias : aliases) {
                configuration_.erase(alias);
            }
        }
    }

    std::set<std::string> fill_defaults(const Schema& schema) {
        std::set<std::string> sections;
        for (const auto& entry : configuration_) {
            sections.insert(section_of(entry.first));
        }
        for (const Spec& spec : schema.specs()) {
            if (!spec.default_value) {
                continue;
            }
            for (const std::string& key : schema.target_keys(spec, sections)) {
                if (configuration_.count(key) == 0) {
                    define(key, *spec.default_value, Origin{"schema", spec.line});
                }
            }
        }
        return sections;
    }

    std::map<std::string, std::optional<std::string>> expand_values() {
        std::map<std::string, std::string> values;
        std::map<std::string, Origin> origins;
        for (const auto& [key, definition] : configuration_) {
            values[key] = definition.value;
            origins[key] = definition.origin;
        }
        Expander expander(values, origins);
        std::map<std::string, std::optional<std::string>> results;
        for (const std::string& key : sorted_keys(configuration_)) {
            results[key] = expander.expand(key);
        }
        reported_.insert(expander.diagnostics().begin(), expander.diagnostics().end());
        return results;
    }

    void check_types(const Schema& schema,
                     const std::map<std::string, std::optional<std::string>>& results) {
        for (const auto& [key, text] : results) {
            if (!text) {
                continue;
            }
            const Definition& definition = configuration_.at(key);
            const Spec* spec = schema.spec_for(key);
            if (spec == nullptr) {
                report(definition.origin, "W_UNKNOWN", key + " is not in the schema");
                Value value;
                value.text = *text;
                result_.outputs.emplace(key, OutputKey(definition, nullptr, value));
                continue;
            }
            try {
                Value value = normalize(key, *spec, *text, definition.origin);
                result_.outputs.emplace(key, OutputKey(definition, spec, value));
            } catch (const CheckError& error) {
                report(definition.origin, error.code, error.what());
            }
        }
    }

    Value normalize(const std::string& key, const Spec& spec, const std::string& text,
                    const Origin& origin) {
        Value value;
        if (spec.kind == "list") {
            value = normalize_list(key, spec, text, origin);
        } else {
            std::optional<Value> parsed = parse_scalar(spec.kind, text, spec.values);
            if (!parsed) {
                throw invalid_value(key, spec.kind, spec.values, checked_text(text, spec.secret));
            }
            value = *parsed;
        }
        if (spec.range) {
            check_range(key, spec, value);
        }
        return value;
    }

    Value normalize_list(const std::string& key, const Spec& spec, const std::string& text,
                         const Origin& origin) {
        Value list;
        if (trim(text).empty()) {
            return list;
        }
        std::vector<std::string> items;
        bool has_empty = false;
        for (const std::string& part : split(text, ',')) {
            std::string item = trim(part);
            if (item.empty()) {
                has_empty = true;
            } else {
                items.push_back(item);
            }
        }
        if (has_empty) {
            report(origin, "W_EMPTY_ITEM", key + ": empty list item ignored");
        }
        for (const std::string& item : items) {
            std::optional<Value> parsed = parse_scalar(spec.item, item, spec.values);
            if (!parsed) {
                std::string display = "item " + checked_text(item, spec.secret);
                throw invalid_value(key, spec.item, spec.values, display);
            }
            list.items.push_back(*parsed);
        }
        if (!spec.unique) {
            return list;
        }
        Value unique_list;
        std::set<std::string> notations;
        for (const Value& item : list.items) {
            if (notations.insert(value_notation(spec.item, "", item)).second) {
                unique_list.items.push_back(item);
            }
        }
        if (unique_list.items.size() < list.items.size()) {
            report(origin, "W_DUPLICATE_ITEM", key + ": duplicate items removed");
        }
        return unique_list;
    }

    void check_order() {
        std::vector<std::string> reported;
        for (const auto& [key, output] : result_.outputs) {
            if (output.spec == nullptr || !output.spec->le) {
                continue;
            }
            std::string limit_key = section_of(key) + "." + *output.spec->le;
            auto limit = result_.outputs.find(limit_key);
            if (limit == result_.outputs.end() || NUMERIC_TYPES.count(limit->second.kind) == 0) {
                continue;
            }
            if (output.value.number > limit->second.value.number) {
                report(output.definition.origin, "E_ORDER",
                       key + ": " + shown(output) + " is greater than " + limit_key + " (" +
                           shown(limit->second) + ")");
                reported.push_back(key);
            }
        }
        for (const std::string& key : reported) {
            result_.outputs.erase(key);
        }
    }

    void check_required(const Schema& schema, const std::set<std::string>& sections,
                        const std::set<std::string>& configured) {
        Origin origin{root_, 0};
        for (const Spec& spec : schema.specs()) {
            if (!spec.required) {
                continue;
            }
            for (const std::string& key : schema.target_keys(spec, sections)) {
                if (configured.count(key) > 0) {
                    continue;
                }
                if (!spec.when) {
                    report(origin, "E_REQUIRED", key + " is required");
                    continue;
                }
                std::string condition_key = section_of(key) + "." + *spec.when;
                auto condition = result_.outputs.find(condition_key);
                if (condition != result_.outputs.end() && condition->second.kind == "bool" &&
                    condition->second.value.flag) {
                    report(origin, "E_REQUIRED",
                           key + " is required when " + condition_key + " is true");
                }
            }
        }
    }

    static const ProfileResult* find_reference(const std::vector<ProfileResult>& earlier,
                                               const std::string& key) {
        for (const ProfileResult& profile : earlier) {
            if (profile.outputs.count(key) > 0) {
                return &profile;
            }
        }
        return nullptr;
    }

    void check_fixed(const std::vector<ProfileResult>& earlier) {
        for (auto entry = result_.outputs.begin(); entry != result_.outputs.end();) {
            const auto& [key, output] = *entry;
            const ProfileResult* reference = nullptr;
            if (output.spec != nullptr && output.spec->fixed) {
                reference = find_reference(earlier, key);
            }
            if (reference == nullptr || reference->outputs.at(key).notation == output.notation) {
                ++entry;
                continue;
            }
            report(output.definition.origin, "E_FIXED",
                   key + ": value differs from profile " + reference->name);
            entry = result_.outputs.erase(entry);
        }
    }

    void summarize(size_t configured_count) {
        result_.diagnostics.assign(reported_.begin(), reported_.end());
        for (const Diagnostic& diagnostic : result_.diagnostics) {
            if (diagnostic.code.rfind("E_", 0) == 0) {
                result_.errors++;
            } else {
                result_.warnings++;
            }
        }
        for (const std::string& key : sorted_keys(result_.outputs)) {
            const std::vector<Origin>& history = result_.outputs.at(key).definition.history;
            if (history.size() >= 2) {
                result_.overridden.emplace_back(key, history);
            }
        }
        for (const auto& entry : result_.outputs) {
            const std::string& document = entry.second.definition.origin.document;
            if (document == "manifest") {
                result_.manifest_keys++;
            } else if (document == "schema") {
                result_.default_keys++;
            } else {
                result_.document_keys++;
            }
        }
        result_.dropped = static_cast<int>(configured_count - result_.outputs.size());
    }
};

ProfileDiff compare_profiles(const ProfileResult& first, const ProfileResult& second) {
    ProfileDiff diff;
    diff.first = first.name;
    diff.second = second.name;
    std::set<std::string> keys;
    for (const auto& entry : first.outputs) {
        keys.insert(entry.first);
    }
    for (const auto& entry : second.outputs) {
        keys.insert(entry.first);
    }
    std::vector<std::string> ordered(keys.begin(), keys.end());
    std::sort(ordered.begin(), ordered.end(), key_order);
    for (const std::string& key : ordered) {
        auto before = first.outputs.find(key);
        auto after = second.outputs.find(key);
        if (before == first.outputs.end()) {
            diff.added++;
            diff.entries.push_back({'+', key, nullptr, &after->second});
        } else if (after == second.outputs.end()) {
            diff.removed++;
            diff.entries.push_back({'-', key, &before->second, nullptr});
        } else if (before->second.notation != after->second.notation) {
            diff.changed++;
            diff.entries.push_back({'~', key, &before->second, &after->second});
        }
    }
    return diff;
}

}  // namespace

int main() {
    const Schema schema = load_schema(INPUT_DIR + "/schema.txt");
    Library library(INPUT_DIR + "/conf");
    std::vector<ProfileResult> profiles;
    int number = 0;
    for (const std::string& line : read_lines(INPUT_DIR + "/manifest.txt")) {
        number++;
        Profile profile(number, line);
        profiles.push_back(profile.process(schema, library, profiles));
    }
    std::vector<ProfileDiff> diffs;
    for (size_t i = 1; i < profiles.size(); i++) {
        diffs.push_back(compare_profiles(profiles[i - 1], profiles[i]));
    }
    write_outputs(OUTPUT_DIR, profiles, diffs);
}
