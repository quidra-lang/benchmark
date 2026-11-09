#include "formatter.h"
static void append_owned(TextLines *to, TextLines *from) {
    for (int i = 0; i < from->count; ++i)
        lines_push(to, from->data[i]);
    free(from->data);
    *from = (TextLines){0};
}
TextLines doc_tree(const Doc *doc, int depth) {
    char *prefix = repeated(' ', 2 * depth);
    TextLines out = {0};
    switch (doc->kind) {
    case D_TEXT:
        lines_push(&out, format_text("%stext \"%s\"", prefix, doc->value));
        break;
    case D_SUFFIX:
        lines_push(&out, format_text("%ssuffix \"%s\"", prefix, doc->value));
        break;
    case D_IF_BREAK:
        lines_push(&out, format_text("%sif_break \"%s\" \"%s\"", prefix, doc->value, doc->other));
        break;
    case D_LINE:
        lines_push(&out, format_text("%sline", prefix));
        break;
    case D_SOFTLINE:
        lines_push(&out, format_text("%ssoftline", prefix));
        break;
    case D_HARDLINE:
        lines_push(&out, format_text("%shardline", prefix));
        break;
    case D_BREAK_PARENT:
        lines_push(&out, format_text("%sbreak_parent", prefix));
        break;
    case D_CONCAT:
        for (int i = 0; i < doc->children.count; ++i) {
            TextLines child = doc_tree(doc->children.data[i], depth);
            append_owned(&out, &child);
        }
        break;
    default: {
        if (doc->kind == D_GROUP)
            lines_push(&out, format_text("%sgroup %s", prefix,
                                         doc->mode == MODE_FLAT    ? "flat"
                                         : doc->mode == MODE_BREAK ? "break"
                                                                   : "forced"));
        else if (doc->kind == D_NEST)
            lines_push(&out, format_text("%snest %d", prefix, doc->number));
        else
            lines_push(&out, format_text("%salign", prefix));
        TextLines child = doc_tree(doc->children.data[0], depth + 1);
        append_owned(&out, &child);
        break;
    }
    }
    free(prefix);
    return out;
}
typedef struct {
    int old_line, new_line, deletes, inserts;
    TextLines operations;
} Hunk;
typedef struct {
    Hunk *data;
    int count, capacity;
} Hunks;
TextLines diff_lines(const TextLines *before, const TextLines *after) {
    int n = before->count, m = after->count;
    size_t stride = (size_t)m + 1;
    int *lcs = allocate(((size_t)n + 1) * stride * sizeof *lcs);
    for (int i = n - 1; i >= 0; --i)
        for (int j = m - 1; j >= 0; --j) {
            size_t at = (size_t)i * stride + (size_t)j;
            int down = lcs[at + stride], right = lcs[at + 1];
            lcs[at] = !strcmp(before->data[i], after->data[j]) ? lcs[at + stride + 1] + 1
                      : down > right                           ? down
                                                               : right;
        }
    Hunks hunks = {0};
    int i = 0, j = 0, deletes = 0, inserts = 0;
    while (i < n || j < m) {
        if (i < n && j < m && !strcmp(before->data[i], after->data[j])) {
            ++i;
            ++j;
            continue;
        }
        Hunk hunk = {i, j, 0, 0, {0}};
        while ((i < n || j < m) && !(i < n && j < m && !strcmp(before->data[i], after->data[j]))) {
            if (j == m || (i < n && lcs[((size_t)i + 1) * stride + (size_t)j] >=
                                        lcs[(size_t)i * stride + (size_t)j + 1])) {
                lines_push(&hunk.operations, format_text("-%s", before->data[i++]));
                ++hunk.deletes;
            } else {
                lines_push(&hunk.operations, format_text("+%s", after->data[j++]));
                ++hunk.inserts;
            }
        }
        deletes += hunk.deletes;
        inserts += hunk.inserts;
        if (hunks.count == hunks.capacity) {
            hunks.capacity = hunks.capacity ? hunks.capacity * 2 : 8;
            hunks.data = resize(hunks.data, (size_t)hunks.capacity * sizeof *hunks.data);
        }
        hunks.data[hunks.count++] = hunk;
    }
    TextLines out = {0};
    lines_push(&out, format_text("hunks=%d deleted=%d inserted=%d", hunks.count, deletes, inserts));
    for (int k = 0; k < hunks.count; ++k) {
        Hunk *hunk = &hunks.data[k];
        lines_push(&out, format_text("@@ -%d,%d +%d,%d @@",
                                     hunk->old_line + (hunk->deletes ? 1 : 0), hunk->deletes,
                                     hunk->new_line + (hunk->inserts ? 1 : 0), hunk->inserts));
        append_owned(&out, &hunk->operations);
    }
    free(hunks.data);
    free(lcs);
    return out;
}
