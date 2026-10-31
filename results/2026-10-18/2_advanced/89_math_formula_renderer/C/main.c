#include "formula.h"
static int maximum(int a, int b) { return a > b ? a : b; }
static int minimum(int a, int b) { return a < b ? a : b; }
static void append_owned(TextLines *to, TextLines *from) {
    for (int i = 0; i < from->count; ++i)
        lines_push(to, from->data[i]);
    free(from->data);
    *from = (TextLines){0};
}
typedef struct {
    char *data;
    size_t length, capacity;
} String;
static void string_add(String *string, const char *text) {
    size_t length = strlen(text), size = string->length + length + 1;
    if (size > string->capacity) {
        size_t capacity = string->capacity ? string->capacity : 64;
        while (capacity < size)
            capacity *= 2;
        string->data = resize(string->data, capacity);
        string->capacity = capacity;
    }
    memcpy(string->data + string->length, text, length + 1);
    string->length += length;
}
static void string_owned(String *string, char *text) {
    string_add(string, text);
    free(text);
}
static char *string_take(String *string) { return string->data ? string->data : copy_text(""); }
typedef struct {
    int number;
    char *source, *tag_string;
    TokenList tokens;
    NodeList nodes;
    NodePool pool;
    Token *tag, *label;
    Issue error;
    IssueList warnings;
} Formula;
typedef struct {
    Params params;
    References references;
    BoxPool pool;
} Typesetter;
static Box *typeset(Typesetter *typesetter, const Node *node, bool script);
static BoxList typeset_boxes(Typesetter *typesetter, const NodeList *nodes, bool script) {
    BoxList out = {0};
    for (int i = 0; i < nodes->count; ++i)
        box_push(&out, typeset(typesetter, nodes->data[i], script));
    return out;
}
static Box *typeset(Typesetter *typesetter, const Node *node, bool script) {
    BoxPool *pool = &typesetter->pool;
    Kind kind = node->kind;
    if (kind == K_IDENTIFIER || kind == K_NUMBER || kind == K_SYMBOL || kind == K_COMMAND ||
        kind == K_TEXT || kind == K_REFERENCE)
        return atom_box(pool, node, script, &typesetter->references);
    if (kind == K_ROW) {
        Spacing space = spacing(&node->items, script, typesetter->params);
        BoxList children = typeset_boxes(typesetter, &node->items, script);
        Box *out = row_box(pool, children.data, children.count, space.gaps, "row", NULL);
        spacing_free(&space);
        free(children.data);
        return out;
    }
    if (kind == K_SCRIPT) {
        Box *base = typeset(typesetter, node->base, script),
            *sub = node->sub ? typeset(typesetter, node->sub, true) : NULL,
            *sup = node->sup ? typeset(typesetter, node->sup, true) : NULL;
        int sw = sub ? sub->width : 0, sh = sub ? sub->height : 0, pw = sup ? sup->width : 0,
            ph = sup ? sup->height : 0;
        bool stacked =
            !script && ((node->base->kind == K_COMMAND &&
                         contains_word("\\sum \\prod \\lim \\max \\min", node->base->value)) ||
                        (node->base->kind == K_ACCENT &&
                         contains_word("overbrace underbrace", node->base->value)));
        if (stacked) {
            int width = maximum(base->width, maximum(sw, pw));
            Box *out = new_box(pool, width, ph + base->height + sh, ph + base->baseline,
                               copy_text("limits"));
            box_add(out, base, center(base, width), ph, "base: ");
            if (sub)
                box_add(out, sub, center(sub, width), ph + base->height, "sub: ");
            if (sup)
                box_add(out, sup, center(sup, width), 0, "sup: ");
            return out;
        }
        int top_sup = (base->baseline ? 0 : -1) - ph + 1,
            top_sub = base->height - (descent(base) > 0 ? 1 : 0),
            top = sup ? minimum(0, top_sup) : 0,
            bottom = sub ? maximum(base->height - 1, top_sub + sh - 1) : base->height - 1;
        Box *out = new_box(pool, base->width + maximum(sw, pw), bottom - top + 1,
                           base->baseline - top, copy_text("scripts"));
        box_add(out, base, 0, -top, "base: ");
        if (sub)
            box_add(out, sub, base->width, top_sub - top, "sub: ");
        if (sup)
            box_add(out, sup, base->width, top_sup - top, "sup: ");
        return out;
    }
    if (kind == K_FRAC) {
        Box *numerator = typeset(typesetter, node->items.data[0], script),
            *denominator = typeset(typesetter, node->items.data[1], script);
        if (!script) {
            int width = maximum(numerator->width, denominator->width) + 2;
            Box *out = new_box(pool, width, numerator->height + 1 + denominator->height,
                               numerator->height, copy_text("frac"));
            box_add(out, numerator, center(numerator, width), 0, "num: ");
            box_add(out, denominator, center(denominator, width), numerator->height + 1, "den: ");
            box_draw_owned(out, repeated('-', width), 0, numerator->height);
            return out;
        }
        if (node->items.data[0]->kind == K_ROW || node->items.data[0]->kind == K_FRAC)
            numerator = delimit(pool, numerator, "(", ")");
        if (node->items.data[1]->kind == K_ROW || node->items.data[1]->kind == K_FRAC)
            denominator = delimit(pool, denominator, "(", ")");
        Box *slash = new_box(pool, 1, 1, 0, copy_text("atom \"/\""));
        box_draw(slash, "/", 0, 0);
        Box *children[3] = {numerator, slash, denominator};
        int gaps[2] = {0, 0};
        const char *roles[3] = {"num: ", "", "den: "};
        return row_box(pool, children, 3, gaps, "slash", roles);
    }
    if (kind == K_BINOM) {
        Box *upper = typeset(typesetter, node->items.data[0], script),
            *lower = typeset(typesetter, node->items.data[1], script);
        int width = maximum(upper->width, lower->width), height = upper->height + 1 + lower->height;
        Box *out = new_box(pool, width + 2, height, upper->height, copy_text("binom"));
        box_add(out, upper, center(upper, width) + 1, 0, "upper: ");
        box_add(out, lower, center(lower, width) + 1, upper->height + 1, "lower: ");
        draw_delimiter(out, "(", 0, height);
        draw_delimiter(out, ")", width + 1, height);
        return out;
    }
    if (kind == K_OVERSET || kind == K_UNDERSET) {
        Box *placed = typeset(typesetter, node->items.data[0], true),
            *base = typeset(typesetter, node->items.data[1], script);
        int width = maximum(placed->width, base->width);
        bool over = kind == K_OVERSET;
        Box *out = new_box(pool, width, placed->height + base->height,
                           base->baseline + (over ? placed->height : 0),
                           copy_text(over ? "overset" : "underset"));
        if (over) {
            box_add(out, placed, center(placed, width), 0, "over: ");
            box_add(out, base, center(base, width), placed->height, "base: ");
        } else {
            box_add(out, base, center(base, width), 0, "base: ");
            box_add(out, placed, center(placed, width), base->height, "under: ");
        }
        return out;
    }
    if (kind == K_SQRT || kind == K_ROOT) {
        Box *body = typeset(typesetter, node->items.data[node->items.count - 1], script),
            *index = NULL;
        int extra = 0, top = 0;
        if (kind == K_ROOT) {
            index = typeset(typesetter, node->items.data[0], true);
            extra = maximum(0, index->width - 1);
            top = maximum(0, index->height - body->height);
        }
        int height = body->height;
        Box *out = new_box(pool, extra + height + 1 + body->width, height + 1 + top,
                           body->baseline + 1 + top, copy_text(index ? "root" : "sqrt"));
        box_draw_owned(out, repeated('_', body->width), extra + height + 1, top);
        box_draw(out, "\\", extra, height + top);
        for (int r = 1; r <= height; ++r)
            box_draw(out, "/", extra + height - r + 1, r + top);
        if (index) {
            box_add(out, index, 0, height - index->height + top, "index: ");
            box_add(out, body, extra + height + 1, 1 + top, "body: ");
        } else
            box_add(out, body, extra + height + 1, 1 + top, "");
        return out;
    }
    if (kind == K_DELIM)
        return delimit(pool, typeset(typesetter, node->items.data[0], script), node->left,
                       node->right);
    if (kind == K_MATRIX) {
        int rows = node->rows.count, columns = node->rows.data[0].count;
        BoxList *cells = allocate((size_t)rows * sizeof *cells);
        int *widths = allocate((size_t)columns * sizeof *widths),
            *ascents = allocate((size_t)rows * sizeof *ascents),
            *descents = allocate((size_t)rows * sizeof *descents),
            *xs = allocate((size_t)columns * sizeof *xs), *ys = allocate((size_t)rows * sizeof *ys);
        for (int i = 0; i < rows; ++i) {
            cells[i] = typeset_boxes(typesetter, &node->rows.data[i], script);
            for (int j = 0; j < columns; ++j) {
                const Box *box = cells[i].data[j];
                widths[j] = maximum(widths[j], box->width);
                ascents[i] = maximum(ascents[i], box->baseline);
                descents[i] = maximum(descents[i], descent(box));
            }
        }
        int body_width = 0, body_height = 0;
        for (int j = 0; j < columns; ++j) {
            xs[j] = body_width;
            body_width += widths[j] + (j + 1 < columns ? typesetter->params.col_gap : 0);
        }
        for (int i = 0; i < rows; ++i) {
            ys[i] = body_height;
            body_height +=
                ascents[i] + descents[i] + 1 + (i + 1 < rows ? typesetter->params.row_gap : 0);
        }
        bool plain = !strcmp(node->value, "matrix"), cases = !strcmp(node->value, "cases");
        int shift = plain ? 0 : 2, width = body_width + (plain ? 0 : cases ? 2 : 4);
        Box *out = new_box(pool, width, body_height, (body_height - 1) / 2,
                           format_text("%s rows=%d cols=%d", node->value, rows, columns));
        for (int i = 0; i < rows; ++i) {
            for (int j = 0; j < columns; ++j) {
                Box *box = cells[i].data[j];
                int offset = cases ? 0 : center(box, widths[j]);
                char *role = format_text("cell %d,%d: ", i + 1, j + 1);
                box_add(out, box, xs[j] + offset + shift, ys[i] + ascents[i] - box->baseline, role);
                free(role);
            }
            free(cells[i].data);
        }
        if (!strcmp(node->value, "pmatrix")) {
            draw_delimiter(out, "(", 0, body_height);
            draw_delimiter(out, ")", body_width + 3, body_height);
        } else if (!strcmp(node->value, "bmatrix")) {
            draw_delimiter(out, "[", 0, body_height);
            draw_delimiter(out, "]", body_width + 3, body_height);
        } else if (!strcmp(node->value, "vmatrix")) {
            draw_delimiter(out, "|", 0, body_height);
            draw_delimiter(out, "|", body_width + 3, body_height);
        } else if (cases)
            draw_delimiter(out, "\\{", 0, body_height);
        free(cells);
        free(widths);
        free(ascents);
        free(descents);
        free(xs);
        free(ys);
        return out;
    }
    Box *body = typeset(typesetter, node->items.data[0], script);
    int width = body->width, baseline = body->baseline + 1;
    if (contains_word("hat dot tilde", node->value))
        width = maximum(width, 1);
    else if (!strcmp(node->value, "vec"))
        width = maximum(width, 2);
    else if (contains_word("overbrace underbrace", node->value))
        width += 2;
    if (!strcmp(node->value, "underbrace"))
        baseline = body->baseline;
    Box *out = new_box(pool, width, body->height + 1, baseline, copy_text(node->value));
    if (!strcmp(node->value, "overline")) {
        box_draw_owned(out, repeated('_', body->width), 0, 0);
        box_add(out, body, 0, 1, "");
    } else if (contains_word("hat dot tilde", node->value)) {
        box_draw(out,
                 !strcmp(node->value, "hat")   ? "^"
                 : !strcmp(node->value, "dot") ? "."
                                               : "~",
                 (width - 1) / 2, 0);
        box_add(out, body, 0, 1, "");
    } else if (!strcmp(node->value, "vec")) {
        char *dashes = repeated('-', width - 1);
        box_draw_owned(out, format_text("%s>", dashes), 0, 0);
        free(dashes);
        box_add(out, body, 0, 1, "");
    } else if (!strcmp(node->value, "overbrace")) {
        char *dashes = repeated('-', body->width);
        box_draw_owned(out, format_text("/%s\\", dashes), 0, 0);
        free(dashes);
        box_add(out, body, 1, 1, "");
    } else {
        box_add(out, body, 1, 0, "");
        char *dashes = repeated('-', body->width);
        box_draw_owned(out, format_text("\\%s/", dashes), 0, body->height);
        free(dashes);
    }
    return out;
}
static void issue_push(IssueList *issues, Issue issue) {
    if (issues->count == issues->capacity) {
        issues->capacity = issues->capacity ? issues->capacity * 2 : 8;
        issues->data = resize(issues->data, (size_t)issues->capacity * sizeof *issues->data);
    }
    issues->data[issues->count++] = issue;
}
static void collect_node_warnings(Formula *formula, const Node *node,
                                  const References *references) {
    if (!node)
        return;
    if (node->kind == K_IDENTIFIER && command_name(node->value))
        issue_push(&formula->warnings,
                   (Issue){node->column, format_text("%s is a command name; write \\%s",
                                                     node->value, node->value)});
    if (node->kind == K_REFERENCE && !find_reference(references, node->value))
        issue_push(&formula->warnings,
                   (Issue){node->column, format_text("undefined reference \"%s\"", node->value)});
    if (node->kind == K_DELIM && strcmp(node->left, ".") && strcmp(node->right, ".")) {
        const char *expected = !strcmp(node->left, "(")     ? ")"
                               : !strcmp(node->left, "[")   ? "]"
                               : !strcmp(node->left, "|")   ? "|"
                               : !strcmp(node->left, "\\{") ? "\\}"
                                                            : "";
        if (strcmp(expected, node->right))
            issue_push(&formula->warnings,
                       (Issue){node->right_column, format_text("\\left%s closed by \\right%s",
                                                               node->left, node->right)});
    }
    for (int i = 0; i < node->items.count; ++i)
        collect_node_warnings(formula, node->items.data[i], references);
    collect_node_warnings(formula, node->base, references);
    collect_node_warnings(formula, node->sub, references);
    collect_node_warnings(formula, node->sup, references);
    for (int i = 0; i < node->rows.count; ++i)
        for (int j = 0; j < node->rows.data[i].count; ++j)
            collect_node_warnings(formula, node->rows.data[i].data[j], references);
}
static int compare_issues(const void *left, const void *right) {
    const Issue *a = left, *b = right;
    return (a->column > b->column) - (a->column < b->column);
}
static const char *construct_name(Kind kind) {
    return kind == K_ROW        ? "row"
           : kind == K_FRAC     ? "frac"
           : kind == K_BINOM    ? "binom"
           : kind == K_OVERSET  ? "overset"
           : kind == K_UNDERSET ? "underset"
           : kind == K_SQRT     ? "sqrt"
                                : "root";
}
static char *tree(const Node *node) {
    Kind kind = node->kind;
    if (kind == K_IDENTIFIER || kind == K_NUMBER || kind == K_COMMAND)
        return copy_text(node->value);
    if (kind == K_SYMBOL)
        return format_text("'%s'", node->value);
    if (kind == K_TEXT)
        return format_text("\"%s\"", node->value);
    if (kind == K_REFERENCE)
        return format_text("(eqref \"%s\")", node->value);
    String out = {0};
    if (kind == K_SCRIPT) {
        string_add(&out, node->sub ? (node->sup ? "(subsup " : "(sub ") : "(sup ");
        string_owned(&out, tree(node->base));
        if (node->sub) {
            string_add(&out, " ");
            string_owned(&out, tree(node->sub));
        }
        if (node->sup) {
            string_add(&out, " ");
            string_owned(&out, tree(node->sup));
        }
        string_add(&out, ")");
        return string_take(&out);
    }
    if (kind == K_DELIM) {
        char *left =
                 strlen(node->left) == 1 ? format_text("'%s'", node->left) : copy_text(node->left),
             *right = strlen(node->right) == 1 ? format_text("'%s'", node->right)
                                               : copy_text(node->right);
        string_owned(&out, format_text("(delim %s %s ", left, right));
        free(left);
        free(right);
        string_owned(&out, tree(node->items.data[0]));
        string_add(&out, ")");
        return string_take(&out);
    }
    string_add(&out, "(");
    string_add(&out, kind == K_MATRIX || kind == K_ACCENT ? node->value : construct_name(kind));
    if (kind == K_MATRIX)
        for (int i = 0; i < node->rows.count; ++i) {
            string_add(&out, " [");
            for (int j = 0; j < node->rows.data[i].count; ++j) {
                if (j)
                    string_add(&out, " ");
                string_owned(&out, tree(node->rows.data[i].data[j]));
            }
            string_add(&out, "]");
        }
    else
        for (int i = 0; i < node->items.count; ++i) {
            string_add(&out, " ");
            string_owned(&out, tree(node->items.data[i]));
        }
    string_add(&out, ")");
    return string_take(&out);
}
static char *linear(const Typesetter *typesetter, const Node *node, bool script);
static char *parenthesize(const Typesetter *typesetter, const Node *node, bool script,
                          bool include_script) {
    char *value = linear(typesetter, node, script);
    if (node->kind == K_ROW || node->kind == K_FRAC || (include_script && node->kind == K_SCRIPT)) {
        char *out = format_text("(%s)", value);
        free(value);
        return out;
    }
    return value;
}
static char *linear(const Typesetter *typesetter, const Node *node, bool script) {
    Kind kind = node->kind;
    if (kind == K_IDENTIFIER || kind == K_NUMBER || kind == K_SYMBOL || kind == K_TEXT)
        return copy_text(node->value);
    if (kind == K_REFERENCE) {
        const char *value = find_reference(&typesetter->references, node->value);
        return copy_text(value ? value : "(??)");
    }
    if (kind == K_COMMAND)
        return copy_text(symbol_info(node->value)->display);
    String out = {0};
    if (kind == K_ROW) {
        Spacing space = spacing(&node->items, script, typesetter->params);
        for (int i = 0; i < node->items.count; ++i) {
            if (i)
                string_owned(&out, repeated(' ', space.gaps[i - 1]));
            string_owned(&out, linear(typesetter, node->items.data[i], script));
        }
        spacing_free(&space);
        return string_take(&out);
    }
    if (kind == K_FRAC) {
        string_owned(&out, parenthesize(typesetter, node->items.data[0], script, false));
        string_add(&out, "/");
        string_owned(&out, parenthesize(typesetter, node->items.data[1], script, false));
        return string_take(&out);
    }
    if (kind == K_SCRIPT) {
        string_owned(&out, parenthesize(typesetter, node->base, script, true));
        if (node->sub) {
            string_add(&out, "_");
            string_owned(&out, parenthesize(typesetter, node->sub, true, false));
        }
        if (node->sup) {
            string_add(&out, "^");
            string_owned(&out, parenthesize(typesetter, node->sup, true, false));
        }
        return string_take(&out);
    }
    if (kind == K_DELIM) {
        string_add(&out, delimiter_string(node->left));
        string_owned(&out, linear(typesetter, node->items.data[0], script));
        string_add(&out, delimiter_string(node->right));
        return string_take(&out);
    }
    if (kind == K_MATRIX) {
        string_add(&out, node->value);
        string_add(&out, "[");
        for (int i = 0; i < node->rows.count; ++i) {
            if (i)
                string_add(&out, "; ");
            for (int j = 0; j < node->rows.data[i].count; ++j) {
                if (j)
                    string_add(&out, ", ");
                string_owned(&out, linear(typesetter, node->rows.data[i].data[j], script));
            }
        }
        string_add(&out, "]");
        return string_take(&out);
    }
    string_add(&out, kind == K_ACCENT ? node->value : construct_name(kind));
    string_add(&out, "(");
    bool first_script = kind == K_OVERSET || kind == K_UNDERSET || kind == K_ROOT;
    for (int i = 0; i < node->items.count; ++i) {
        if (i)
            string_add(&out, ", ");
        string_owned(
            &out, linear(typesetter, node->items.data[i], i == 0 && first_script ? true : script));
    }
    string_add(&out, ")");
    return string_take(&out);
}
typedef struct {
    int start, end, indent, width;
} Line;
typedef struct {
    Line *data;
    int count, capacity;
} LineList;
static void line_push(LineList *lines, Line line) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? lines->capacity * 2 : 8;
        lines->data = resize(lines->data, (size_t)lines->capacity * sizeof *lines->data);
    }
    lines->data[lines->count++] = line;
}
static int line_width(const BoxList *boxes, const int *gaps, int start, int end) {
    int width = 0;
    for (int i = start; i < end; ++i) {
        width += boxes->data[i]->width;
        if (i + 1 < end)
            width += gaps[i];
    }
    return width;
}
static LineList break_lines(const NodeList *nodes, const BoxList *boxes, const Spacing *space,
                            Params params, int mode) {
    bool *breaks = allocate((size_t)nodes->count * sizeof *breaks);
    for (int i = 1; i < nodes->count; ++i)
        breaks[i] = space->types[i].left == T_RELATION ||
                    (mode >= 2 && nodes->data[i]->kind == K_SYMBOL &&
                     (!strcmp(nodes->data[i]->value, "+") || !strcmp(nodes->data[i]->value, "-")) &&
                     space->types[i].left == T_BINARY) ||
                    (mode == 3 && space->types[i - 1].right == T_PUNCTUATION);
    LineList out = {0};
    int alignment = -1, relation_width = 0;
    for (int start = 0; start < nodes->count;) {
        int indent = 0;
        if (start) {
            indent = params.indent;
            if (alignment >= 0)
                indent = alignment + (space->types[start].left == T_RELATION
                                          ? 0
                                          : relation_width + params.rel_space);
        }
        int shortest = -1, chosen = -1;
        for (int end = start + 1; end <= nodes->count; ++end)
            if (end == nodes->count || breaks[end]) {
                if (shortest < 0)
                    shortest = end;
                if (indent + line_width(boxes, space->gaps, start, end) <= params.width)
                    chosen = end;
            }
        if (chosen < 0)
            chosen = shortest;
        line_push(&out,
                  (Line){start, chosen, indent, line_width(boxes, space->gaps, start, chosen)});
        if (!start)
            for (int i = 0; i < chosen; ++i)
                if (space->types[i].left == T_RELATION) {
                    alignment = line_width(boxes, space->gaps, 0, i) + (i ? space->gaps[i - 1] : 0);
                    relation_width = boxes->data[i]->width;
                    break;
                }
        start = chosen;
    }
    free(breaks);
    return out;
}
typedef struct {
    Placements roots;
    LineList lines;
    int width, height;
} PlacedFormula;
static PlacedFormula place_formula(Typesetter *typesetter, const Formula *formula) {
    Spacing space = spacing(&formula->nodes, false, typesetter->params);
    BoxList boxes = typeset_boxes(typesetter, &formula->nodes, false);
    PlacedFormula out = {0};
    for (int mode = 1; mode <= 3; ++mode) {
        free(out.lines.data);
        out.lines = break_lines(&formula->nodes, &boxes, &space, typesetter->params, mode);
        bool fits = true;
        for (int i = 0; i < out.lines.count; ++i)
            if (out.lines.data[i].indent + out.lines.data[i].width > typesetter->params.width)
                fits = false;
        if (fits || mode == 3)
            break;
    }
    for (int i = 0; i < out.lines.count; ++i) {
        const Line *line = &out.lines.data[i];
        char *description = format_text("line %d", i + 1);
        Box *box = row_box(&typesetter->pool, boxes.data + line->start, line->end - line->start,
                           space.gaps + line->start, description, NULL);
        free(description);
        placements_push(&out.roots, box, line->indent, out.height, "");
        out.width = maximum(out.width, line->indent + box->width);
        out.height += box->height;
    }
    if (formula->tag_string) {
        Box *tag = new_box(&typesetter->pool, (int)strlen(formula->tag_string), 1, 0,
                           format_text("tag \"%s\"", formula->tag_string));
        box_draw(tag, formula->tag_string, 0, 0);
        int x = typesetter->params.width - tag->width;
        const Placement *last = &out.roots.data[out.roots.count - 1];
        int y = last->y + last->box->baseline;
        if (x < last->x + last->box->width + 2)
            y = out.height++;
        placements_push(&out.roots, tag, x, y, "");
        out.width = maximum(out.width, x + tag->width);
    }
    free(boxes.data);
    spacing_free(&space);
    return out;
}
static void diagnostic(TextLines *out, const Formula *formula, Issue issue, bool warning) {
    lines_push(out, format_text("formula %d, column %d: %s%s", formula->number, issue.column,
                                warning ? "warning: " : "", issue.message));
    lines_push(out, format_text("  %s", formula->source));
    char *indent = repeated(' ', issue.column + 1);
    lines_push(out, format_text("%s^", indent));
    free(indent);
}
static void write_lines(const char *name, const TextLines *lines) {
    char *path = format_text("output/%s", name);
    FILE *output = fopen(path, "wb");
    free(path);
    if (!output)
        exit(EXIT_FAILURE);
    for (int i = 0; i < lines->count; ++i)
        if (fputs(lines->data[i], output) == EOF || fputc('\n', output) == EOF)
            exit(EXIT_FAILURE);
    if (fclose(output))
        exit(EXIT_FAILURE);
}
static int compare_kinds(const void *left, const void *right) {
    const KindCount *a = left, *b = right;
    return strcmp(a->name, b->name);
}
int main(void) {
    Params params = {0};
    TextLines param_lines = read_lines("input/params.txt");
    for (int i = 0; i < param_lines.count; ++i) {
        char *name = param_lines.data[i], *separator = strchr(name, ' ');
        *separator = 0;
        int value = atoi(separator + 1);
        if (!strcmp(name, "width"))
            params.width = value;
        else if (!strcmp(name, "indent"))
            params.indent = value;
        else if (!strcmp(name, "rel_space"))
            params.rel_space = value;
        else if (!strcmp(name, "bin_space"))
            params.bin_space = value;
        else if (!strcmp(name, "punct_space"))
            params.punct_space = value;
        else if (!strcmp(name, "col_gap"))
            params.col_gap = value;
        else
            params.row_gap = value;
    }
    lines_free(&param_lines);
    TextLines sources = read_lines("input/formulas.txt");
    Formula *formulas = allocate((size_t)sources.count * sizeof *formulas);
    for (int i = 0; i < sources.count; ++i) {
        Formula *formula = &formulas[i];
        formula->number = i + 1;
        formula->source = sources.data[i];
        formula->tokens = tokenize(formula->source, &formula->error);
        if (!formula->error.message)
            formula->error = check_braces(&formula->tokens);
        if (!formula->error.message) {
            Parser parser = {0};
            parser.tokens = &formula->tokens;
            parser.end = (int)strlen(formula->source) + 1;
            parser.pool = &formula->pool;
            formula->nodes = parse_elements(&parser, true, false);
            if (!parser.error.message && parser_peek(&parser).kind != K_EOF)
                parser_unexpected(&parser, parser_peek(&parser));
            formula->tag = parser.tag;
            formula->label = parser.label;
            formula->error = parser.error;
        }
    }
    Typesetter typesetter = {0};
    typesetter.params = params;
    typesetter.references.data =
        allocate((size_t)sources.count * sizeof *typesetter.references.data);
    typesetter.references.capacity = sources.count;
    int counter = 0;
    for (int i = 0; i < sources.count; ++i) {
        Formula *formula = &formulas[i];
        if (formula->error.message)
            continue;
        if (formula->tag)
            formula->tag_string = format_text("(%s)", formula->tag->value);
        else if (formula->label)
            formula->tag_string = format_text("(%d)", ++counter);
    }
    for (int i = 0; i < sources.count; ++i) {
        Formula *formula = &formulas[i];
        if (formula->error.message || !formula->label)
            continue;
        if (find_reference(&typesetter.references, formula->label->value))
            issue_push(&formula->warnings,
                       (Issue){formula->label->column,
                               format_text("duplicate label \"%s\"", formula->label->value)});
        else
            typesetter.references.data[typesetter.references.count++] =
                (Reference){formula->label->value, formula->tag_string};
    }
    TextLines rendered = {0}, boxes_report = {0}, trees = {0}, errors = {0};
    int total_boxes = 0, max_depth = 0, valid = 0, warning_count = 0, overfull_count = 0;
    KindCounts kinds = {0};
    for (int i = 0; i < sources.count; ++i) {
        Formula *formula = &formulas[i];
        if (i)
            lines_add(&rendered, "");
        lines_push(&rendered, format_text("formula %d", formula->number));
        if (formula->error.message) {
            lines_add(&rendered, "(error)");
            lines_push(&boxes_report, format_text("formula %d: error", formula->number));
            lines_push(&trees, format_text("formula %d: error", formula->number));
            diagnostic(&errors, formula, formula->error, false);
            continue;
        }
        ++valid;
        for (int j = 0; j < formula->nodes.count; ++j)
            collect_node_warnings(formula, formula->nodes.data[j], &typesetter.references);
        if (formula->warnings.count > 1)
            qsort(formula->warnings.data, (size_t)formula->warnings.count,
                  sizeof *formula->warnings.data, compare_issues);
        warning_count += formula->warnings.count;
        for (int j = 0; j < formula->warnings.count; ++j)
            diagnostic(&errors, formula, formula->warnings.data[j], true);
        PlacedFormula placed = place_formula(&typesetter, formula);
        TextLines drawing = draw_canvas(&placed.roots, placed.width, placed.height);
        append_owned(&rendered, &drawing);
        BoxDescription description = describe_boxes(&placed.roots);
        total_boxes += description.lines.count;
        max_depth = maximum(max_depth, description.depth);
        for (int j = 0; j < description.kinds.count; ++j)
            kinds_add(&kinds, description.kinds.data[j].name, description.kinds.data[j].count);
        lines_push(&boxes_report,
                   format_text("formula %d: lines=%d width=%d height=%d boxes=%d depth=%d",
                               formula->number, placed.lines.count, placed.width, placed.height,
                               description.lines.count, description.depth));
        append_owned(&boxes_report, &description.lines);
        kinds_free(&description.kinds);
        TextLines parts = {0};
        for (int j = 0; j < formula->nodes.count; ++j)
            lines_push(&parts, tree(formula->nodes.data[j]));
        char *notation = join_texts(&parts, " ");
        lines_push(&trees, format_text("formula %d: %s", formula->number, notation));
        free(notation);
        lines_free(&parts);
        Node row = {0};
        row.kind = K_ROW;
        row.items = formula->nodes;
        char *linear_notation = trim_right(linear(&typesetter, &row, false));
        if (*linear_notation)
            lines_push(&trees, format_text("  linear: %s", linear_notation));
        else
            lines_add(&trees, "  linear:");
        free(linear_notation);
        if (formula->tag_string)
            lines_push(&trees, format_text("  tag: %s", formula->tag_string));
        for (int j = 0; j < placed.lines.count; ++j) {
            const Line *line = &placed.lines.data[j];
            if (line->indent + line->width > params.width) {
                ++overfull_count;
                lines_push(&errors, format_text("formula %d: line %d is overfull (width %d > %d)",
                                                formula->number, j + 1, line->indent + line->width,
                                                params.width));
            }
        }
        placements_free(&placed.roots);
        free(placed.lines.data);
        box_pool_free(&typesetter.pool);
        typesetter.pool = (BoxPool){0};
    }
    lines_push(&boxes_report,
               format_text("summary: boxes=%d max_depth=%d", total_boxes, max_depth));
    if (kinds.count > 1)
        qsort(kinds.data, (size_t)kinds.count, sizeof *kinds.data, compare_kinds);
    for (int i = 0; i < kinds.count; ++i)
        lines_push(&boxes_report, format_text("  %s: %d", kinds.data[i].name, kinds.data[i].count));
    lines_push(&errors, format_text("formulas=%d rendered=%d errors=%d warnings=%d overfull=%d",
                                    sources.count, valid, sources.count - valid, warning_count,
                                    overfull_count));
    mkdir("output", 0755);
    write_lines("rendered.txt", &rendered);
    write_lines("boxes.txt", &boxes_report);
    write_lines("trees.txt", &trees);
    write_lines("errors.txt", &errors);
    for (int i = 0; i < sources.count; ++i) {
        Formula *formula = &formulas[i];
        free(formula->tag_string);
        tokens_free(&formula->tokens);
        free(formula->nodes.data);
        node_pool_free(&formula->pool);
        free(formula->error.message);
        for (int j = 0; j < formula->warnings.count; ++j)
            free(formula->warnings.data[j].message);
        free(formula->warnings.data);
    }
    free(formulas);
    free(typesetter.references.data);
    lines_free(&sources);
    lines_free(&rendered);
    lines_free(&boxes_report);
    lines_free(&trees);
    lines_free(&errors);
    kinds_free(&kinds);
    return 0;
}
