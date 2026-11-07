#include "formula.h"
static void draw_box(TextLines *grid, const Box *box, int x, int y) {
    for (int i = 0; i < box->drawn_count; ++i) {
        const Drawn *drawn = &box->drawn[i];
        for (int j = 0; drawn->value[j]; ++j)
            if (drawn->value[j] != ' ')
                grid->data[y + drawn->y][x + drawn->x + j] = drawn->value[j];
    }
    for (int i = 0; i < box->children.count; ++i) {
        const Placement *child = &box->children.data[i];
        draw_box(grid, child->box, x + child->x, y + child->y);
    }
}
TextLines draw_canvas(const Placements *roots, int width, int height) {
    TextLines out = {0};
    for (int y = 0; y < height; ++y)
        lines_push(&out, repeated(' ', width));
    for (int i = 0; i < roots->count; ++i) {
        const Placement *root = &roots->data[i];
        draw_box(&out, root->box, root->x, root->y);
    }
    for (int y = 0; y < height; ++y)
        trim_right(out.data[y]);
    return out;
}
void kinds_add(KindCounts *kinds, const char *name, int count) {
    for (int i = 0; i < kinds->count; ++i)
        if (!strcmp(kinds->data[i].name, name)) {
            kinds->data[i].count += count;
            return;
        }
    if (kinds->count == kinds->capacity) {
        kinds->capacity = kinds->capacity ? kinds->capacity * 2 : 16;
        kinds->data = resize(kinds->data, (size_t)kinds->capacity * sizeof *kinds->data);
    }
    kinds->data[kinds->count++] = (KindCount){copy_text(name), count};
}
void kinds_free(KindCounts *kinds) {
    for (int i = 0; i < kinds->count; ++i)
        free(kinds->data[i].name);
    free(kinds->data);
}
static void describe_box(BoxDescription *out, const Placement *placement, int x, int y, int level) {
    x += placement->x;
    y += placement->y;
    const Box *box = placement->box;
    char *indent = repeated(' ', 2 * level);
    lines_push(&out->lines,
               format_text("%s%s%s x=%d y=%d w=%d h=%d b=%d", indent, placement->role,
                           box->description, x, y, box->width, box->height, box->baseline));
    free(indent);
    if (level + 1 > out->depth)
        out->depth = level + 1;
    char *kind = copy_text(box->description);
    char *space = strchr(kind, ' ');
    if (space)
        *space = 0;
    kinds_add(&out->kinds, kind, 1);
    free(kind);
    for (int i = 0; i < box->children.count; ++i)
        describe_box(out, &box->children.data[i], x, y, level + 1);
}
BoxDescription describe_boxes(const Placements *roots) {
    BoxDescription out = {0};
    for (int i = 0; i < roots->count; ++i)
        describe_box(&out, &roots->data[i], 0, 0, 0);
    return out;
}
