#include "formula.h"
static ElementTypes element_types(const Node *node) {
    Type type = T_ORDINARY;
    if (node->kind == K_SYMBOL) {
        if (strchr("+-*", node->value[0]))
            type = T_BINARY;
        else if (strchr("=<>:", node->value[0]))
            type = T_RELATION;
        else if (strchr("([", node->value[0]))
            type = T_OPEN;
        else if (strchr(")]!", node->value[0]))
            type = T_CLOSE;
        else if (strchr(",;", node->value[0]))
            type = T_PUNCTUATION;
    } else if (node->kind == K_COMMAND)
        type = symbol_info(node->value)->type;
    else if (node->kind == K_DELIM)
        return (ElementTypes){T_OPEN, T_CLOSE};
    else if (node->kind == K_SCRIPT)
        return element_types(node->base);
    else if (node->kind == K_OVERSET || node->kind == K_UNDERSET)
        return element_types(node->items.data[1]);
    return (ElementTypes){type, type};
}
static bool word_element(const Node *node) {
    if (node->kind == K_SCRIPT)
        return word_element(node->base);
    return node->kind == K_COMMAND &&
           (greek_name(node->value + 1) || !strcmp(node->value, "\\infty"));
}
static bool alphanumeric(const Node *node) {
    if (node->kind == K_IDENTIFIER || node->kind == K_NUMBER || word_element(node))
        return true;
    if (node->kind == K_SCRIPT)
        return alphanumeric(node->base);
    return node->kind == K_ACCENT && contains_word("overline hat vec dot tilde", node->value) &&
           alphanumeric(node->items.data[0]);
}
Spacing spacing(const NodeList *nodes, bool script, Params params) {
    Spacing out = {0};
    out.types = allocate((size_t)nodes->count * sizeof *out.types);
    out.gaps = allocate((size_t)(nodes->count ? nodes->count - 1 : 0) * sizeof *out.gaps);
    for (int i = 0; i < nodes->count; ++i)
        out.types[i] = element_types(nodes->data[i]);
    for (int i = 0; i < nodes->count; ++i) {
        Type previous = i ? out.types[i - 1].right : T_ORDINARY;
        if (out.types[i].left == T_BINARY &&
            (!i || previous == T_BINARY || previous == T_OPERATOR || previous == T_RELATION ||
             previous == T_OPEN || previous == T_PUNCTUATION))
            out.types[i] = (ElementTypes){T_ORDINARY, T_ORDINARY};
        Type current = out.types[i].left;
        if (i && (current == T_RELATION || current == T_CLOSE || current == T_PUNCTUATION) &&
            out.types[i - 1].right == T_BINARY)
            out.types[i - 1] = (ElementTypes){T_ORDINARY, T_ORDINARY};
    }
    if (nodes->count && out.types[nodes->count - 1].right == T_BINARY)
        out.types[nodes->count - 1] = (ElementTypes){T_ORDINARY, T_ORDINARY};
    static const char table[7][8] = {"01BR000", "11-R000", "BB--B--", "RR-0R00",
                                     "00-0000", "01BR000", "PP-PPPP"};
    for (int i = 0; i + 1 < nodes->count; ++i) {
        if (alphanumeric(nodes->data[i]) && alphanumeric(nodes->data[i + 1]) &&
            (word_element(nodes->data[i]) || word_element(nodes->data[i + 1])))
            out.gaps[i] = 1;
        else {
            char entry = table[out.types[i].right][out.types[i + 1].left];
            if (entry == '1')
                out.gaps[i] = 1;
            if (!script) {
                if (entry == 'B')
                    out.gaps[i] = params.bin_space;
                else if (entry == 'R')
                    out.gaps[i] = params.rel_space;
                else if (entry == 'P')
                    out.gaps[i] = params.punct_space;
            }
        }
    }
    return out;
}
void spacing_free(Spacing *spacing) {
    free(spacing->types);
    free(spacing->gaps);
}
Box *row_box(BoxPool *pool, Box *const *children, int count, const int *gaps,
             const char *description, const char *const *roles) {
    int ascent = 0, descent_value = 0, width = 0;
    for (int i = 0; i < count; ++i) {
        if (children[i]->baseline > ascent)
            ascent = children[i]->baseline;
        int child_descent = descent(children[i]);
        if (child_descent > descent_value)
            descent_value = child_descent;
        width += children[i]->width;
        if (i + 1 < count)
            width += gaps[i];
    }
    Box *out = new_box(pool, width, ascent + descent_value + 1, ascent, copy_text(description));
    int x = 0;
    for (int i = 0; i < count; ++i) {
        box_add(out, children[i], x, ascent - children[i]->baseline, roles ? roles[i] : "");
        x += children[i]->width;
        if (i + 1 < count)
            x += gaps[i];
    }
    return out;
}
