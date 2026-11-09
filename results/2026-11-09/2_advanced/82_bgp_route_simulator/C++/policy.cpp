#include "bgp.hpp"
#include <algorithm>
#include <stdexcept>
std::uint32_t community(const std::string &text) {
    if (text == "NO_EXPORT")
        return noExport;
    std::size_t colon = text.find(':');
    return static_cast<std::uint32_t>(std::stoul(text.substr(0, colon)) * 65536 +
                                      std::stoul(text.substr(colon + 1)));
}
std::string communityText(std::uint32_t value) {
    return value == noExport ? "NO_EXPORT"
                             : std::to_string(value >> 16) + ":" + std::to_string(value & 65535);
}
std::set<std::uint32_t> communities(const std::vector<std::string> &parts, std::size_t start) {
    std::set<std::uint32_t> result;
    for (std::size_t i = start; i < parts.size(); ++i)
        result.insert(community(parts[i]));
    return result;
}
std::string communitiesText(const std::set<std::uint32_t> &values) {
    std::vector<std::string> parts;
    for (std::uint32_t value : values)
        parts.push_back(communityText(value));
    return parts.empty() ? "-" : join(parts, ",");
}
std::set<std::uint32_t> Rule::edit(std::set<std::uint32_t> values) const {
    for (const Edit &operation : edits)
        if (operation.add)
            values.insert(operation.community);
        else
            values.erase(operation.community);
    return values;
}
bool Policies::permitted(const std::string &name, Prefix value) const {
    for (const PrefixEntry &entry : lists.at(name))
        if (entry.low <= value.length && value.length <= entry.high &&
            entry.prefix.contains(value.address))
            return entry.permit;
    return false;
}
Rule *Policies::named(const std::string &name) {
    for (Rule &rule : rules)
        if (rule.name == name)
            return &rule;
    throw std::runtime_error("unknown rule");
}
Rule *Policies::applied(const std::string &direction, Session *session, Prefix value,
                        const Attribute &attribute) {
    for (Rule &rule : rules) {
        if (!rule.active || rule.owner != session->owner->number || rule.direction != direction)
            continue;
        if (rule.target != "*" &&
            rule.target != std::to_string(session->link->other(session->owner)->number) &&
            rule.target != session->link->name)
            continue;
        bool match = true;
        for (const Condition &condition : rule.conditions) {
            const std::string &v = condition.value;
            if (condition.kind == "PREFIX")
                match = permitted(v, value);
            else if (condition.kind == "CONTAINS")
                match = std::find(attribute.path.begin(), attribute.path.end(), std::stoi(v)) !=
                        attribute.path.end();
            else if (condition.kind == "ORIGINAS")
                match = (attribute.path.empty() ? session->owner->number : attribute.path.back()) ==
                        std::stoi(v);
            else if (condition.kind == "LENGTH") {
                std::size_t dash = v.find('-');
                match = std::stoi(v.substr(0, dash)) <= static_cast<int>(attribute.path.size()) &&
                        static_cast<int>(attribute.path.size()) <= std::stoi(v.substr(dash + 1));
            } else
                match = attribute.communities.count(community(v)) != 0;
            if (!match)
                break;
        }
        if (match)
            return &rule;
    }
    return nullptr;
}
Policies readPolicies() {
    Policies policies;
    for (const std::string &line : readLines("input/policies.txt")) {
        std::vector<std::string> a = words(line);
        if (a[0] == "PLIST") {
            Prefix value = prefix(a[3]);
            int low = value.length, high = value.length;
            bool ge = false, le = false;
            for (std::size_t i = 4; i < a.size(); i += 2)
                if (a[i] == "GE") {
                    low = std::stoi(a[i + 1]);
                    ge = true;
                } else {
                    high = std::stoi(a[i + 1]);
                    le = true;
                }
            if (ge && !le)
                high = 32;
            policies.lists[a[1]].push_back({a[2] == "PERMIT", value, low, high});
            continue;
        }
        Rule rule;
        rule.name = a[1];
        rule.active = a[2] == "ON";
        rule.owner = std::stoi(a[3]);
        rule.direction = a[4];
        rule.target = a[5];
        std::size_t i = 6;
        while (a[i] != "THEN") {
            rule.conditions.push_back({a[i], a[i + 1]});
            i += 2;
        }
        ++i;
        while (i < a.size()) {
            std::string kind = a[i++];
            if (kind == "DENY")
                rule.deny = true;
            else if (kind == "ALLOW")
                rule.allow = true;
            else if (kind == "LOCALPREF") {
                rule.preference = std::stoi(a[i++]);
                rule.hasPreference = true;
            } else if (kind == "MED") {
                rule.med = std::stoi(a[i++]);
                rule.hasMed = true;
            } else if (kind == "PREPEND")
                rule.prepend = std::stoi(a[i++]);
            else
                rule.edits.push_back({kind == "ADD", community(a[i++])});
        }
        policies.rules.push_back(std::move(rule));
    }
    return policies;
}
