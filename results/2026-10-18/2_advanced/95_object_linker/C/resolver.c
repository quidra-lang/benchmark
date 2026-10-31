#include "linker.h"
static bool string_member(StringList list, const char *value) {
    for (int i = 0; i < list.count; ++i)
        if (equal(list.items[i], value))
            return true;
    return false;
}
Resolution *resolve_name(const char *name, SymbolList entries, bool script) {
    Resolution *result = ml_alloc(sizeof(*result));
    result->name = name;
    result->definer = "-";
    result->alignment = 1;
    for (int i = 0; i < entries.count; ++i) {
        Symbol *symbol = entries.items[i];
        if (equal(symbol->location, "undef")) {
            PUSH(result->references, symbol);
            if (!string_member(result->referrers, symbol->object->name))
                PUSH(result->referrers, (char *)symbol->object->name);
        } else if (equal(symbol->location, "common"))
            PUSH(result->common, symbol);
        else if (equal(symbol->binding, "global"))
            PUSH(result->strong, symbol);
        else
            PUSH(result->weak, symbol);
    }
    if (script) {
        result->kind = "script";
        result->definer = "*script*";
    } else if (result->strong.count) {
        result->kind = "global";
        result->definition = result->strong.items[0];
        result->definer = result->definition->object->name;
    } else if (result->common.count) {
        result->kind = "common";
        for (int i = 0; i < result->common.count; ++i) {
            Symbol *symbol = result->common.items[i];
            if (symbol->size > result->size)
                result->size = symbol->size;
            if (symbol->alignment > result->alignment)
                result->alignment = symbol->alignment;
        }
        for (int i = 0; i < result->common.count; ++i)
            if (result->common.items[i]->size == result->size) {
                result->definer = result->common.items[i]->object->name;
                break;
            }
    } else if (result->weak.count) {
        result->kind = "weak";
        result->definition = result->weak.items[0];
        result->definer = result->definition->object->name;
    } else {
        result->kind = "weakundef";
        for (int i = 0; i < result->references.count; ++i)
            if (equal(result->references.items[i]->binding, "global")) {
                result->kind = "undefined";
                break;
            }
    }
    return result;
}
StringList strong_definers(Resolution *resolution, bool script) {
    StringList result = {0};
    if (script)
        PUSH(result, "*script*");
    for (int i = 0; i < resolution->strong.count; ++i)
        PUSH(result, (char *)resolution->strong.items[i]->object->name);
    return result;
}
