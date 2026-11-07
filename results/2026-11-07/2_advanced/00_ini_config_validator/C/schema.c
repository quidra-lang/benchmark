#include "schema.h"

static const char *type_names[] = {
    "string", "int", "bool", "enum", "size", "duration", "host", "path", "url", "date", "list"
};

Kind kind_from_name(const char *name) {
    for (int i = TYPE_STRING; i <= TYPE_LIST; ++i)
        if (!strcmp(name, type_names[i])) return (Kind)i;
    exit(EXIT_FAILURE);
}

const char *kind_name(Kind kind) { return type_names[kind]; }

Schema load_schema(const char *path) {
    Schema schema = {0};
    char *text = read_file(path);
    if (!text) exit(EXIT_FAILURE);
    Strings lines = file_lines(text);
    for (size_t i = 0; i < lines.len; ++i) {
        char *line = lines.data[i];
        if (!*trim_spaces(line) || *line == '#') continue;
        Strings words = split(line, ' ');
        Spec *spec = checked_realloc(NULL, sizeof *spec);
        *spec = (Spec){.line = (int)i + 1, .pattern = words.data[0],
                       .kind = kind_from_name(words.data[1]), .item = TYPE_STRING};
        spec->section = section_of(spec->pattern);
        spec->key = copy_text(name_of(spec->pattern));
        spec->wildcard = strchr(spec->section, '*') != NULL;
        for (size_t j = 2; j < words.len; ++j) {
            char *attribute = copy_text(words.data[j]), *equal = strchr(attribute, '=');
            char *argument = equal ? equal + 1 : "";
            if (equal) *equal = '\0';
            if (!strcmp(attribute, "required")) spec->required = true;
            else if (!strcmp(attribute, "secret")) spec->secret = true;
            else if (!strcmp(attribute, "unique")) spec->unique = true;
            else if (!strcmp(attribute, "fixed")) spec->fixed = true;
            else if (!strcmp(attribute, "default")) spec->default_value = argument;
            else if (!strcmp(attribute, "range")) {
                char *separator = strstr(argument, "..");
                spec->lower = slice(argument, 0, (size_t)(separator - argument));
                spec->upper = copy_text(separator + 2);
            } else if (!strcmp(attribute, "values")) spec->values = split(argument, ',');
            else if (!strcmp(attribute, "alias")) spec->aliases = split(argument, ',');
            else if (!strcmp(attribute, "item")) spec->item = kind_from_name(argument);
            else if (!strcmp(attribute, "when")) spec->when = argument;
            else if (!strcmp(attribute, "le")) spec->le = argument;
        }
        PUSH(schema.specs, spec);
    }
    return schema;
}

bool spec_matches(const Spec *spec, const char *section) {
    Strings pattern = split(spec->section, '.'), parts = split(section, '.');
    if (pattern.len != parts.len) return false;
    for (size_t i = 0; i < parts.len; ++i)
        if (strcmp(pattern.data[i], "*") && strcmp(pattern.data[i], parts.data[i])) return false;
    return true;
}

Spec *spec_for(const Schema *schema, const char *key) {
    for (size_t i = 0; i < schema->specs.len; ++i) {
        Spec *spec = schema->specs.data[i];
        if (!spec->wildcard && !strcmp(spec->pattern, key)) return spec;
    }
    char *section = section_of(key);
    for (size_t i = 0; i < schema->specs.len; ++i) {
        Spec *spec = schema->specs.data[i];
        if (spec->wildcard && !strcmp(spec->key, name_of(key)) && spec_matches(spec, section)) return spec;
    }
    return NULL;
}

Strings target_keys(const Schema *schema, Spec *spec, Strings sections) {
    Strings result = {0};
    if (!spec->wildcard) {
        PUSH(result, spec->pattern);
        return result;
    }
    for (size_t i = 0; i < sections.len; ++i) {
        char *key = format("%s.%s", sections.data[i], spec->key);
        if (spec_matches(spec, sections.data[i]) && spec_for(schema, key) == spec) PUSH(result, key);
    }
    if (result.len > 1) qsort(result.data, result.len, sizeof *result.data, key_comparator);
    return result;
}
