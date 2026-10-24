#ifndef SCHEMA_H
#define SCHEMA_H
#include "main.h"

struct Spec {
    int line;
    char *pattern, *section, *key;
    Kind kind, item;
    bool wildcard, required, secret, unique, fixed;
    char *default_value, *lower, *upper, *when, *le;
    Strings values, aliases;
};
VECTOR(Spec *, Specs);
typedef struct { Specs specs; } Schema;
Kind kind_from_name(const char *name);
const char *kind_name(Kind kind);
Schema load_schema(const char *path);
bool spec_matches(const Spec *spec, const char *section);
Spec *spec_for(const Schema *schema, const char *key);
Strings target_keys(const Schema *schema, Spec *spec, Strings sections);
#endif
