#include "interpolate.h"
#include "ini_parser.h"

typedef struct {
    Configuration configuration;
    Diagnostics *diagnostics;
    char **results;
    unsigned char *state;
    bool *cycle;
    int *stack;
    size_t depth;
} Expander;

static char *expand(Expander *expander, int index) {
    if (expander->state[index] == 2) return expander->results[index];
    expander->state[index] = 1;
    expander->stack[expander->depth++] = index;
    Entry entry = expander->configuration.data[index];
    const char *raw = entry.definition.raw;
    Buffer result = {0};
    bool failed = false;
    for (size_t position = 0; raw[position];) {
        if (raw[position] != '$' || raw[position + 1] != '{') {
            buffer_char(&result, raw[position] == LITERAL_DOLLAR ? '$' : raw[position]);
            ++position;
            continue;
        }
        const char *close = strchr(raw + position + 2, '}');
        char *reference = close ? slice(raw, position + 2, (size_t)(close - raw) - position - 2) : "";
        if (!close || !is_section_name(reference)) {
            report(expander->diagnostics, entry.definition.origin, "E_BAD_REF",
                   format("%s: invalid reference", entry.key));
            failed = true;
            break;
        }
        char *target = strchr(reference, '.') ? reference : format("%s.%s", section_of(entry.key), reference);
        int target_index = configuration_index(expander->configuration, target);
        if (target_index < 0) {
            report(expander->diagnostics, entry.definition.origin, "E_UNDEFINED",
                   format("%s: undefined reference %s", entry.key, target));
            failed = true;
            break;
        }
        char *expanded = NULL;
        if (expander->state[target_index] == 1) {
            size_t start = 0;
            while (expander->stack[start] != target_index) ++start;
            Strings path = {0};
            for (size_t i = start; i < expander->depth; ++i) {
                int member = expander->stack[i];
                expander->cycle[member] = true;
                PUSH(path, expander->configuration.data[member].key);
            }
            PUSH(path, target);
            report(expander->diagnostics, expander->configuration.data[target_index].definition.origin,
                   "E_CYCLE", format("interpolation cycle %s", join_strings(path, " -> ")));
        } else {
            expanded = expand(expander, target_index);
        }
        if (!expanded) {
            if (!expander->cycle[index])
                report(expander->diagnostics, entry.definition.origin, "E_DEPENDENCY",
                       format("%s: depends on failed key %s", entry.key, target));
            failed = true;
            break;
        }
        buffer_text(&result, expanded);
        position = (size_t)(close - raw) + 1;
    }
    --expander->depth;
    expander->state[index] = 2;
    expander->results[index] = failed ? NULL : buffer_result(&result);
    return expander->results[index];
}

char **expand_configuration(Configuration configuration, Diagnostics *diagnostics) {
    size_t count = configuration.len ? configuration.len : 1;
    Expander expander = {.configuration = configuration, .diagnostics = diagnostics};
    expander.results = checked_realloc(NULL, count * sizeof *expander.results);
    expander.state = checked_realloc(NULL, count * sizeof *expander.state);
    expander.cycle = checked_realloc(NULL, count * sizeof *expander.cycle);
    expander.stack = checked_realloc(NULL, count * sizeof *expander.stack);
    memset(expander.state, 0, count * sizeof *expander.state);
    memset(expander.cycle, 0, count * sizeof *expander.cycle);
    Strings keys = configuration_keys(configuration);
    for (size_t i = 0; i < keys.len; ++i) expand(&expander, configuration_index(configuration, keys.data[i]));
    return expander.results;
}
