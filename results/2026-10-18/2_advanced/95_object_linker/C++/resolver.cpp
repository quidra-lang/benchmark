#include "linker.hpp"
Resolution resolve_name(const std::string &name, const std::vector<Symbol *> &entries,
                        bool script) {
    Resolution result;
    result.name = name;
    std::set<Object *> seen;
    for (Symbol *symbol : entries) {
        if (symbol->location == "undef") {
            result.references.push_back(symbol);
            if (seen.insert(symbol->object).second)
                result.referrers.push_back(symbol->object->name);
        } else if (symbol->location == "common")
            result.common.push_back(symbol);
        else if (symbol->binding == "global")
            result.strong.push_back(symbol);
        else
            result.weak.push_back(symbol);
    }
    if (script) {
        result.kind = "script";
        result.definer = "*script*";
    } else if (!result.strong.empty()) {
        result.kind = "global";
        result.definition = result.strong[0];
        result.definer = result.definition->object->name;
    } else if (!result.common.empty()) {
        result.kind = "common";
        for (Symbol *symbol : result.common) {
            result.size = std::max(result.size, symbol->size);
            result.alignment = std::max(result.alignment, symbol->alignment);
        }
        for (Symbol *symbol : result.common)
            if (symbol->size == result.size) {
                result.definer = symbol->object->name;
                break;
            }
    } else if (!result.weak.empty()) {
        result.kind = "weak";
        result.definition = result.weak[0];
        result.definer = result.definition->object->name;
    } else {
        result.kind = "weakundef";
        for (Symbol *symbol : result.references)
            if (symbol->binding == "global") {
                result.kind = "undefined";
                break;
            }
    }
    return result;
}
std::vector<std::string> strong_definers(const Resolution &resolution, bool script) {
    std::vector<std::string> result;
    if (script)
        result.push_back("*script*");
    for (Symbol *symbol : resolution.strong)
        result.push_back(symbol->object->name);
    return result;
}
