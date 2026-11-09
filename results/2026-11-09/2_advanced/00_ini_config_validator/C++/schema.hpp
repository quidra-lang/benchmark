#pragma once

#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

struct Range {
    std::string lower;
    std::string upper;
};

struct Spec {
    int line;
    std::string pattern;
    std::string key;
    std::vector<std::string> section_parts;
    bool wildcard = false;
    std::string kind;
    bool required = false;
    bool secret = false;
    bool unique = false;
    bool fixed = false;
    std::optional<std::string> default_value;
    std::optional<Range> range;
    std::vector<std::string> values;
    std::string item = "string";
    std::vector<std::string> aliases;
    std::optional<std::string> when;
    std::optional<std::string> le;

    Spec(int line, const std::vector<std::string>& words);

    bool matches(const std::string& section) const;

private:
    void add_attribute(const std::string& attribute);
};

class Schema {
public:
    explicit Schema(std::vector<Spec> specs);

    const std::vector<Spec>& specs() const { return specs_; }
    const Spec* spec_for(const std::string& full_key) const;
    std::vector<std::string> target_keys(const Spec& spec,
                                         const std::set<std::string>& sections) const;

private:
    std::vector<Spec> specs_;
    std::map<std::string, const Spec*> exact_;
};

Schema load_schema(const std::string& path);
