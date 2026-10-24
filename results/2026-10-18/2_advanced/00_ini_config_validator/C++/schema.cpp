#include "schema.hpp"

#include <algorithm>

#include "lexer.hpp"

namespace {

const std::string WILDCARD = "*";

}  // namespace

Spec::Spec(int line, const std::vector<std::string>& words)
    : line(line), pattern(words[0]), kind(words[1]) {
    size_t dot = pattern.rfind('.');
    key = pattern.substr(dot + 1);
    section_parts = split(pattern.substr(0, dot), '.');
    wildcard = std::find(section_parts.begin(), section_parts.end(), WILDCARD) !=
               section_parts.end();
    for (size_t i = 2; i < words.size(); i++) {
        add_attribute(words[i]);
    }
}

void Spec::add_attribute(const std::string& attribute) {
    size_t equals = attribute.find('=');
    std::string name = attribute.substr(0, equals);
    std::string argument = equals == std::string::npos ? "" : attribute.substr(equals + 1);
    if (name == "required") {
        required = true;
    } else if (name == "secret") {
        secret = true;
    } else if (name == "unique") {
        unique = true;
    } else if (name == "fixed") {
        fixed = true;
    } else if (name == "default") {
        default_value = argument;
    } else if (name == "range") {
        size_t dots = argument.find("..");
        range = Range{argument.substr(0, dots), argument.substr(dots + 2)};
    } else if (name == "values") {
        values = split(argument, ',');
    } else if (name == "item") {
        item = argument;
    } else if (name == "alias") {
        aliases = split(argument, ',');
    } else if (name == "when") {
        when = argument;
    } else if (name == "le") {
        le = argument;
    }
}

bool Spec::matches(const std::string& section) const {
    std::vector<std::string> parts = split(section, '.');
    if (parts.size() != section_parts.size()) {
        return false;
    }
    for (size_t i = 0; i < parts.size(); i++) {
        if (section_parts[i] != WILDCARD && section_parts[i] != parts[i]) {
            return false;
        }
    }
    return true;
}

Schema::Schema(std::vector<Spec> specs) : specs_(std::move(specs)) {
    for (const Spec& spec : specs_) {
        if (!spec.wildcard) {
            exact_[spec.pattern] = &spec;
        }
    }
}

const Spec* Schema::spec_for(const std::string& full_key) const {
    auto found = exact_.find(full_key);
    if (found != exact_.end()) {
        return found->second;
    }
    size_t dot = full_key.rfind('.');
    std::string section = full_key.substr(0, dot);
    std::string key = full_key.substr(dot + 1);
    for (const Spec& spec : specs_) {
        if (spec.wildcard && spec.key == key && spec.matches(section)) {
            return &spec;
        }
    }
    return nullptr;
}

std::vector<std::string> Schema::target_keys(const Spec& spec,
                                             const std::set<std::string>& sections) const {
    if (!spec.wildcard) {
        return {spec.pattern};
    }
    std::vector<std::string> keys;
    for (const std::string& section : sections) {
        std::string key = section + "." + spec.key;
        if (spec.matches(section) && spec_for(key) == &spec) {
            keys.push_back(key);
        }
    }
    return keys;
}

Schema load_schema(const std::string& path) {
    std::vector<Spec> specs;
    int number = 0;
    for (const std::string& line : read_lines(path)) {
        number++;
        if (!trim(line).empty() && line.front() != '#') {
            specs.emplace_back(number, split(line, ' '));
        }
    }
    return Schema(std::move(specs));
}
