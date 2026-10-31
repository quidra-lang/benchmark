#include "regression.h"
static char *substring(const char *first, size_t length) {
    char *out = resize(NULL, length + 1);
    memcpy(out, first, length);
    out[length] = 0;
    return out;
}
static Lines split(const char *source, const char *delimiter) {
    Lines out = {0};
    const char *first = source;
    while (true) {
        const char *next = strstr(first, delimiter);
        line_push(&out, next ? substring(first, (size_t)(next - first)) : text(first));
        if (!next)
            break;
        first = next + strlen(delimiter);
    }
    return out;
}
static Factor parse_factor(const char *name, const Dataframe *data) {
    Factor out = {.name = text(name), .power = 1};
    char *column = text(name);
    if (!strncmp(name, "C(", 2)) {
        out.categorical = true;
        free(column);
        column = substring(name + 2, strlen(name) - 3);
    } else if (!strncmp(name, "I(", 2)) {
        const char *caret = strchr(name, '^');
        free(column);
        column = substring(name + 2, (size_t)(caret - name) - 2);
        out.power = atoi(caret + 1);
    }
    while (strcmp(data->names.data[out.column], column))
        ++out.column;
    free(column);
    return out;
}
static bool factor_member(const Term *term, const char *name) {
    for (int i = 0; i < term->count; ++i)
        if (!strcmp(term->factors[i].name, name))
            return true;
    return false;
}
static bool same_term(const Term *a, const Term *b) {
    if (a->count != b->count)
        return false;
    for (int i = 0; i < a->count; ++i)
        if (!factor_member(b, a->factors[i].name))
            return false;
    return true;
}
Formula parse_formula(const char *line, const Dataframe *data) {
    Formula out = {.weight = -1};
    const char *weights = strstr(line, " weights=");
    out.raw = weights ? substring(line, (size_t)(weights - line)) : text(line);
    if (weights) {
        out.weight = 0;
        while (strcmp(data->names.data[out.weight], weights + 9))
            ++out.weight;
    }
    Lines sides = split(out.raw, " ~ ");
    while (strcmp(data->names.data[out.response], sides.data[0]))
        ++out.response;
    Lines expressions = split(sides.data[1], " + ");
    for (int expression_index = 0; expression_index < expressions.count; ++expression_index) {
        const char *expression = expressions.data[expression_index];
        bool star = strchr(expression, '*') != NULL;
        Lines factor_names = split(expression, star ? "*" : ":");
        for (int count = 1; count <= factor_names.count; ++count)
            for (int mask = 1; mask < (1 << factor_names.count); ++mask) {
                int selected = 0;
                for (int j = 0; j < factor_names.count; ++j)
                    if (mask & (1 << j))
                        ++selected;
                if ((star && selected != count) ||
                    (!star && (count != factor_names.count || mask != (1 << factor_names.count) - 1)))
                    continue;
                Term term = {.name = text("")};
                for (int j = 0; j < factor_names.count; ++j)
                    if (mask & (1 << j)) {
                        term.factors[term.count++] = parse_factor(factor_names.data[j], data);
                        char *next = format("%s%s%s", term.name, *term.name ? ":" : "", factor_names.data[j]);
                        free(term.name);
                        term.name = next;
                    }
                bool duplicate = false;
                for (int i = 0; i < out.count; ++i)
                    if (same_term(&out.terms[i], &term))
                        duplicate = true;
                if (duplicate) {
                    for (int j = 0; j < term.count; ++j)
                        free(term.factors[j].name);
                    free(term.name);
                } else {
                    out.terms = resize(out.terms, (size_t)(out.count + 1) * sizeof(Term));
                    out.terms[out.count++] = term;
                }
            }
        lines_free(&factor_names);
    }
    lines_free(&expressions);
    lines_free(&sides);
    return out;
}
bool contained(const Term *a, const Term *b) {
    if (a->count >= b->count)
        return false;
    for (int i = 0; i < a->count; ++i)
        if (!factor_member(b, a->factors[i].name))
            return false;
    return true;
}
char *formula_text(const Formula *formula, const IntList *terms, const Dataframe *data) {
    char *out = format("%s ~ ", data->names.data[formula->response]);
    if (!terms->count) {
        char *next = format("%s1", out);
        free(out);
        return next;
    }
    for (int i = 0; i < terms->count; ++i) {
        char *next = format("%s%s%s", out, i ? " + " : "", formula->terms[terms->data[i]].name);
        free(out);
        out = next;
    }
    return out;
}
Vector record_values(const Column *columns, int count, const Record *record) {
    Vector out = vector_new(count);
    for (int j = 0; j < count; ++j) {
        double value = 1;
        for (int i = 0; i < columns[j].count; ++i) {
            const Component *component = &columns[j].components[i];
            double part = component->categorical
                              ? (!strcmp(record->cells[component->column].label, component->label) ? 1 : 0)
                              : record->cells[component->column].number;
            if (!component->categorical) {
                if (component->power == 2)
                    part = part * part;
                else if (component->power == 3)
                    part = part * part * part;
            }
            value = value * part;
        }
        out.data[j] = value;
    }
    return out;
}
static int string_compare(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}
Design *build_design(Formula formula, const Dataframe *data) {
    Design *out = calloc(1, sizeof(Design));
    out->formula = formula;
    bool variables[12] = {0};
    variables[formula.response] = true;
    if (formula.weight >= 0)
        variables[formula.weight] = true;
    for (int t = 0; t < formula.count; ++t)
        for (int f = 0; f < formula.terms[t].count; ++f)
            variables[formula.terms[t].factors[f].column] = true;
    for (int i = 0; i < data->count; ++i) {
        bool complete = true;
        for (int j = 0; j < data->names.count; ++j)
            if (variables[j] && data->rows[i].cells[j].missing)
                complete = false;
        if (complete)
            int_push(&out->used, i);
    }
    for (int t = 0; t < formula.count; ++t)
        for (int f = 0; f < formula.terms[t].count; ++f) {
            Factor factor = formula.terms[t].factors[f];
            if (!factor.categorical || out->levels[factor.column].count)
                continue;
            Lines *levels = &out->levels[factor.column];
            for (int i = 0; i < out->used.count; ++i) {
                const char *label = data->rows[out->used.data[i]].cells[factor.column].label;
                bool found = false;
                for (int j = 0; j < levels->count; ++j)
                    if (!strcmp(levels->data[j], label))
                        found = true;
                if (!found)
                    line_push(levels, text(label));
            }
            qsort(levels->data, (size_t)levels->count, sizeof(char *), string_compare);
        }
    out->columns[out->count++] = (Column){.name = text("(Intercept)"), .term = -1};
    for (int t = 0; t < formula.count; ++t) {
        const Term *term = &formula.terms[t];
        int component_counts[3], product = 1;
        for (int f = 0; f < term->count; ++f) {
            Factor factor = term->factors[f];
            component_counts[f] = factor.categorical ? out->levels[factor.column].count - 1 : 1;
            product *= component_counts[f];
        }
        for (int index = 0; index < product; ++index) {
            int remainder = index;
            Column column = {.name = text(""), .term = t};
            for (int f = 0; f < term->count; ++f) {
                Factor factor = term->factors[f];
                int choice = remainder % component_counts[f];
                remainder /= component_counts[f];
                Component component = {
                    .column = factor.column, .power = factor.power, .categorical = factor.categorical};
                if (factor.categorical) {
                    component.label = out->levels[factor.column].data[choice + 1];
                    component.name = format("%s%s", factor.name, component.label);
                } else
                    component.name = text(factor.name);
                column.components[column.count++] = component;
                char *next = format("%s%s%s", column.name, *column.name ? ":" : "", component.name);
                free(column.name);
                column.name = next;
            }
            out->columns[out->count++] = column;
        }
    }
    out->x = matrix_new(out->used.count, out->count);
    out->y = vector_new(out->used.count);
    out->weights = vector_new(out->used.count);
    for (int i = 0; i < out->used.count; ++i) {
        const Record *record = &data->rows[out->used.data[i]];
        Vector values = record_values(out->columns, out->count, record);
        for (int j = 0; j < out->count; ++j)
            AT(out->x, i, j) = values.data[j];
        free(values.data);
        out->y.data[i] = record->cells[formula.response].number;
        out->weights.data[i] = formula.weight < 0 ? 1 : record->cells[formula.weight].number;
    }
    return out;
}
IntList selected_columns(const Design *design, const IntList *terms) {
    IntList out = {0};
    int_push(&out, 0);
    for (int j = 1; j < design->count; ++j)
        if (int_contains(terms, design->columns[j].term))
            int_push(&out, j);
    return out;
}
bool predictable(const Design *design, const Record *record) {
    for (int t = 0; t < design->formula.count; ++t)
        for (int f = 0; f < design->formula.terms[t].count; ++f) {
            Factor factor = design->formula.terms[t].factors[f];
            if (record->cells[factor.column].missing)
                return false;
            if (factor.categorical) {
                bool found = false;
                for (int i = 0; i < design->levels[factor.column].count; ++i)
                    if (!strcmp(design->levels[factor.column].data[i], record->cells[factor.column].label))
                        found = true;
                if (!found)
                    return false;
            }
        }
    return true;
}
