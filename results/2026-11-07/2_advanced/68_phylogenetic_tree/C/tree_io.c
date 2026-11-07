#include "phylogeny.h"
static char *formatted(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int n = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = malloc((size_t)n + 1);
    vsnprintf(out, (size_t)n + 1, pattern, args);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *out = formatted(pattern, args);
    va_end(args);
    return out;
}
void text(Text *out, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *part = formatted(pattern, args);
    va_end(args);
    size_t count = strlen(part);
    if (out->length + count + 1 > out->capacity) {
        out->capacity = 2 * (out->length + count + 1);
        out->data = realloc(out->data, out->capacity);
    }
    memcpy(out->data + out->length, part, count + 1);
    out->length += count;
    free(part);
}
void line(Lines *out, const char *pattern, ...) {
    if (out->count == out->capacity) {
        out->capacity = out->capacity ? out->capacity * 2 : 32;
        out->values = realloc(out->values, (size_t)out->capacity * sizeof(char *));
    }
    va_list args;
    va_start(args, pattern);
    out->values[out->count++] = formatted(pattern, args);
    va_end(args);
}
char *read_line(FILE *input) {
    Text out = {0};
    int c;
    while ((c = fgetc(input)) != EOF && c != '\n')
        text(&out, "%c", c);
    if (c == EOF && out.length == 0) {
        free(out.data);
        return NULL;
    }
    if (!out.data)
        text(&out, "");
    return out.data;
}
char *real(double value, int digits) {
    char *out = format("%.*f", digits, value);
    if (out[0] == '-') {
        int zero = 1;
        for (int i = 1; out[i]; ++i)
            if (out[i] != '0' && out[i] != '.')
                zero = 0;
        if (zero)
            memmove(out, out + 1, strlen(out));
    }
    return out;
}
char *symbols(Mask mask, int size) {
    char *out = malloc((size_t)size + 1);
    for (int t = 0; t < size; ++t)
        out[t] = mask & (1u << t) ? '*' : '.';
    out[size] = 0;
    return out;
}
static Rooted ordered_root(const Tree *tree, char names[16][21], int outgroup) {
    Rooted root = rooted(tree, outgroup);
    const char *minimum[32] = {0};
    for (int i = root.count - 1; i >= 0; --i) {
        int node = root.order[i];
        if (node < tree->size)
            minimum[node] = names[node];
        else {
            for (int j = 1; j < root.child_count[node]; ++j) {
                int child = root.children[node][j], k = j;
                while (k > 0 && strcmp(minimum[root.children[node][k - 1]], minimum[child]) > 0) {
                    root.children[node][k] = root.children[node][k - 1];
                    --k;
                }
                root.children[node][k] = child;
            }
            minimum[node] = minimum[root.children[node][0]];
        }
    }
    return root;
}
static void render(Text *out, const Tree *tree, const Rooted *root, char names[16][21], int node,
                   int lengths, const int *support) {
    if (node < tree->size)
        text(out, "%s", names[node]);
    else {
        text(out, "(");
        for (int i = 0; i < root->child_count[node]; ++i) {
            if (i)
                text(out, ",");
            render(out, tree, root, names, root->children[node][i], lengths, support);
        }
        text(out, ")");
        if (support && node != root->root)
            text(out, "%d", support[root->masks[node]]);
    }
    if (lengths && node != root->root)
        text(out, ":%s", real(tree->length[node][root->parent[node]], 5));
}
char *newick(const Tree *tree, char names[16][21], int outgroup, int lengths, const int *support) {
    Rooted root = ordered_root(tree, names, outgroup);
    Text out = {0};
    render(&out, tree, &root, names, root.root, lengths, support);
    text(&out, ";");
    return out.data;
}
static void draw(Lines *out, const Tree *tree, const Rooted *root, char names[16][21],
                 const int *support, int node, const char *prefix) {
    for (int i = 0; i < root->child_count[node]; ++i) {
        int child = root->children[node][i], last = i + 1 == root->child_count[node];
        char *label =
            child < tree->size ? names[child] : format("[%d]", support[root->masks[child]]);
        line(out, "%s%s%s", prefix, last ? "`-- " : "|-- ", label);
        char *next = format("%s%s", prefix, last ? "    " : "|   ");
        draw(out, tree, root, names, support, child, next);
        free(next);
    }
}
Lines cladogram(const Tree *tree, char names[16][21], int outgroup, const int *support) {
    Rooted root = ordered_root(tree, names, outgroup);
    Lines out = {0};
    line(&out, "*");
    draw(&out, tree, &root, names, support, root.root, "");
    return out;
}
void save(const char *name, const Lines *lines) {
    char *path = format("output/%s", name);
    FILE *out = fopen(path, "w");
    for (int i = 0; i < lines->count; ++i)
        fprintf(out, "%s\n", lines->values[i]);
    fclose(out);
    free(path);
}
