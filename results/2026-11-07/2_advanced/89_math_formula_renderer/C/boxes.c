#include "formula.h"
static const SymbolInfo symbols[] = {{"\\alpha", "alpha", T_ORDINARY},
                                     {"\\beta", "beta", T_ORDINARY},
                                     {"\\gamma", "gamma", T_ORDINARY},
                                     {"\\delta", "delta", T_ORDINARY},
                                     {"\\epsilon", "epsilon", T_ORDINARY},
                                     {"\\zeta", "zeta", T_ORDINARY},
                                     {"\\eta", "eta", T_ORDINARY},
                                     {"\\theta", "theta", T_ORDINARY},
                                     {"\\iota", "iota", T_ORDINARY},
                                     {"\\kappa", "kappa", T_ORDINARY},
                                     {"\\lambda", "lambda", T_ORDINARY},
                                     {"\\mu", "mu", T_ORDINARY},
                                     {"\\nu", "nu", T_ORDINARY},
                                     {"\\xi", "xi", T_ORDINARY},
                                     {"\\pi", "pi", T_ORDINARY},
                                     {"\\rho", "rho", T_ORDINARY},
                                     {"\\sigma", "sigma", T_ORDINARY},
                                     {"\\tau", "tau", T_ORDINARY},
                                     {"\\upsilon", "upsilon", T_ORDINARY},
                                     {"\\phi", "phi", T_ORDINARY},
                                     {"\\chi", "chi", T_ORDINARY},
                                     {"\\psi", "psi", T_ORDINARY},
                                     {"\\omega", "omega", T_ORDINARY},
                                     {"\\Gamma", "Gamma", T_ORDINARY},
                                     {"\\Delta", "Delta", T_ORDINARY},
                                     {"\\Theta", "Theta", T_ORDINARY},
                                     {"\\Lambda", "Lambda", T_ORDINARY},
                                     {"\\Xi", "Xi", T_ORDINARY},
                                     {"\\Pi", "Pi", T_ORDINARY},
                                     {"\\Sigma", "Sigma", T_ORDINARY},
                                     {"\\Upsilon", "Upsilon", T_ORDINARY},
                                     {"\\Phi", "Phi", T_ORDINARY},
                                     {"\\Psi", "Psi", T_ORDINARY},
                                     {"\\Omega", "Omega", T_ORDINARY},
                                     {"\\cdot", "*", T_BINARY},
                                     {"\\times", "x", T_BINARY},
                                     {"\\pm", "+-", T_BINARY},
                                     {"\\mp", "-+", T_BINARY},
                                     {"\\leq", "<=", T_RELATION},
                                     {"\\geq", ">=", T_RELATION},
                                     {"\\neq", "!=", T_RELATION},
                                     {"\\approx", "~=", T_RELATION},
                                     {"\\to", "->", T_RELATION},
                                     {"\\infty", "oo", T_ORDINARY},
                                     {"\\ldots", "...", T_ORDINARY},
                                     {"\\cdots", "...", T_ORDINARY},
                                     {"\\quad", "  ", T_ORDINARY},
                                     {"\\,", " ", T_ORDINARY},
                                     {"\\{", "{", T_OPEN},
                                     {"\\}", "}", T_CLOSE},
                                     {"\\sin", "sin", T_OPERATOR},
                                     {"\\cos", "cos", T_OPERATOR},
                                     {"\\tan", "tan", T_OPERATOR},
                                     {"\\log", "log", T_OPERATOR},
                                     {"\\ln", "ln", T_OPERATOR},
                                     {"\\exp", "exp", T_OPERATOR},
                                     {"\\det", "det", T_OPERATOR},
                                     {"\\lim", "lim", T_OPERATOR},
                                     {"\\max", "max", T_OPERATOR},
                                     {"\\min", "min", T_OPERATOR},
                                     {"\\sum", "sum", T_OPERATOR},
                                     {"\\prod", "prod", T_OPERATOR},
                                     {"\\int", "int", T_OPERATOR}};
const SymbolInfo *symbol_info(const char *command) {
    for (size_t i = 0; i < sizeof symbols / sizeof *symbols; ++i)
        if (!strcmp(symbols[i].command, command))
            return &symbols[i];
    return NULL;
}
const char *find_reference(const References *references, const char *name) {
    for (int i = 0; i < references->count; ++i)
        if (!strcmp(references->data[i].name, name))
            return references->data[i].value;
    return NULL;
}
void box_push(BoxList *boxes, Box *box) {
    if (boxes->count == boxes->capacity) {
        boxes->capacity = boxes->capacity ? boxes->capacity * 2 : 16;
        boxes->data = resize(boxes->data, (size_t)boxes->capacity * sizeof *boxes->data);
    }
    boxes->data[boxes->count++] = box;
}
Box *new_box(BoxPool *pool, int width, int height, int baseline, char *description) {
    Box *box = allocate(sizeof *box);
    box->width = width;
    box->height = height;
    box->baseline = baseline;
    box->description = description;
    box_push(&pool->boxes, box);
    return box;
}
void placements_push(Placements *placements, Box *box, int x, int y, const char *role) {
    if (placements->count == placements->capacity) {
        placements->capacity = placements->capacity ? placements->capacity * 2 : 8;
        placements->data =
            resize(placements->data, (size_t)placements->capacity * sizeof *placements->data);
    }
    placements->data[placements->count++] = (Placement){box, x, y, copy_text(role)};
}
void placements_free(Placements *placements) {
    for (int i = 0; i < placements->count; ++i)
        free(placements->data[i].role);
    free(placements->data);
}
void box_add(Box *box, Box *child, int x, int y, const char *role) {
    placements_push(&box->children, child, x, y, role);
}
void box_draw_owned(Box *box, char *value, int x, int y) {
    if (box->drawn_count == box->drawn_capacity) {
        box->drawn_capacity = box->drawn_capacity ? box->drawn_capacity * 2 : 8;
        box->drawn = resize(box->drawn, (size_t)box->drawn_capacity * sizeof *box->drawn);
    }
    box->drawn[box->drawn_count++] = (Drawn){value, x, y};
}
void box_draw(Box *box, const char *value, int x, int y) {
    box_draw_owned(box, copy_text(value), x, y);
}
void box_pool_free(BoxPool *pool) {
    for (int i = 0; i < pool->boxes.count; ++i) {
        Box *box = pool->boxes.data[i];
        placements_free(&box->children);
        for (int j = 0; j < box->drawn_count; ++j)
            free(box->drawn[j].value);
        free(box->drawn);
        free(box->description);
        free(box);
    }
    free(pool->boxes.data);
}
int descent(const Box *box) { return box->height - 1 - box->baseline; }
int center(const Box *box, int width) { return (width - box->width) / 2; }
void draw_delimiter(Box *box, const char *value, int x, int height) {
    if (!strcmp(value, "."))
        return;
    char actual = value[strlen(value) - 1];
    for (int y = 0; y < height; ++y) {
        char glyph = actual;
        if (height >= 2 && strchr("(){}", actual)) {
            glyph = '|';
            if (!y)
                glyph = actual == '(' || actual == '{' ? '/' : '\\';
            if (y == height - 1)
                glyph = actual == '(' || actual == '{' ? '\\' : '/';
            if (height >= 3 && y == (height - 1) / 2 && (actual == '{' || actual == '}'))
                glyph = actual == '{' ? '<' : '>';
        }
        char drawn[2] = {glyph, 0};
        box_draw(box, drawn, x, y);
    }
}
const char *delimiter_string(const char *value) {
    return !strcmp(value, ".") ? "" : value + strlen(value) - 1;
}
Box *delimit(BoxPool *pool, Box *body, const char *left, const char *right) {
    int wl = !strcmp(left, ".") ? 0 : 1, wr = !strcmp(right, ".") ? 0 : 1;
    Box *out = new_box(pool, wl + body->width + wr, body->height, body->baseline,
                       format_text("delim %s %s", left, right));
    box_add(out, body, wl, 0, "");
    draw_delimiter(out, left, 0, body->height);
    draw_delimiter(out, right, wl + body->width, body->height);
    return out;
}
Box *atom_box(BoxPool *pool, const Node *node, bool script, const References *references) {
    const char *display = node->value;
    char *description = format_text("%s \"%s\"",
                                    node->kind == K_TEXT        ? "text"
                                    : node->kind == K_REFERENCE ? "eqref"
                                                                : "atom",
                                    node->value);
    if (node->kind == K_REFERENCE) {
        display = find_reference(references, node->value);
        if (!display)
            display = "(??)";
    }
    if (node->kind == K_COMMAND) {
        display = symbol_info(node->value)->display;
        if (!script && contains_word("\\sum \\prod \\int", node->value)) {
            static const char *glyphs[3][3] = {
                {"\\--", " > ", "/--"}, {"___", "| |", "| |"}, {" /", " |", "/ "}};
            int index = !strcmp(node->value, "\\sum") ? 0 : !strcmp(node->value, "\\prod") ? 1 : 2;
            Box *out = new_box(pool, (int)strlen(glyphs[index][0]), 3, 1, description);
            for (int y = 0; y < 3; ++y)
                box_draw(out, glyphs[index][y], 0, y);
            return out;
        }
    }
    Box *out = new_box(pool, (int)strlen(display), 1, 0, description);
    box_draw(out, display, 0, 0);
    return out;
}
