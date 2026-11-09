#include "formatter.h"
void docs_push(Docs *docs, Doc *doc) {
    if (docs->count == docs->capacity) {
        docs->capacity = docs->capacity ? docs->capacity * 2 : 8;
        docs->data = resize(docs->data, (size_t)docs->capacity * sizeof *docs->data);
    }
    docs->data[docs->count++] = doc;
}
Doc *doc_marker(DocPool *pool, DocKind kind) {
    Doc *out = allocate(sizeof *out);
    out->kind = kind;
    docs_push(&pool->docs, out);
    return out;
}
Doc *doc_text(DocPool *pool, const char *value) {
    Doc *out = doc_marker(pool, D_TEXT);
    out->value = copy_text(value);
    return out;
}
static void normalized_add(DocPool *pool, Docs *out, Doc *doc) {
    if (!doc)
        return;
    if (doc->kind == D_CONCAT) {
        for (int i = 0; i < doc->children.count; ++i)
            normalized_add(pool, out, doc->children.data[i]);
        return;
    }
    if (doc->kind == D_TEXT) {
        if (!*doc->value)
            return;
        if (out->count && out->data[out->count - 1]->kind == D_TEXT) {
            Doc *merged = doc_marker(pool, D_TEXT);
            merged->value = format_text("%s%s", out->data[out->count - 1]->value, doc->value);
            out->data[out->count - 1] = merged;
            return;
        }
    }
    docs_push(out, doc);
}
Doc *doc_cat(DocPool *pool, Docs docs) {
    Docs out = {0};
    for (int i = 0; i < docs.count; ++i)
        normalized_add(pool, &out, docs.data[i]);
    free(docs.data);
    if (!out.count) {
        free(out.data);
        return doc_text(pool, "");
    }
    if (out.count == 1) {
        Doc *result = out.data[0];
        free(out.data);
        return result;
    }
    Doc *result = doc_marker(pool, D_CONCAT);
    result->children = out;
    return result;
}
Doc *concat(DocPool *pool, int count, ...) {
    Docs docs = {0};
    va_list args;
    va_start(args, count);
    for (int i = 0; i < count; ++i)
        docs_push(&docs, va_arg(args, Doc *));
    va_end(args);
    return doc_cat(pool, docs);
}
static bool force_broken(const Doc *doc) {
    if (doc->kind == D_HARDLINE || doc->kind == D_BREAK_PARENT)
        return true;
    for (int i = 0; i < doc->children.count; ++i)
        if (force_broken(doc->children.data[i]))
            return true;
    return false;
}
Doc *doc_group(DocPool *pool, Doc *child) {
    Doc *out = doc_marker(pool, D_GROUP);
    docs_push(&out->children, child);
    out->forced = force_broken(child);
    return out;
}
Doc *doc_nest(DocPool *pool, int amount, Doc *child) {
    Doc *out = doc_marker(pool, D_NEST);
    out->number = amount;
    docs_push(&out->children, child);
    return out;
}
Doc *doc_align(DocPool *pool, Doc *child) {
    Doc *out = doc_marker(pool, D_ALIGN);
    docs_push(&out->children, child);
    return out;
}
Doc *doc_suffix(DocPool *pool, const char *value) {
    Doc *out = doc_marker(pool, D_SUFFIX);
    out->value = copy_text(value);
    return out;
}
Doc *doc_if_break(DocPool *pool, const char *broken, const char *flat) {
    Doc *out = doc_marker(pool, D_IF_BREAK);
    out->value = copy_text(broken);
    out->other = copy_text(flat);
    return out;
}
GroupMetrics group_metrics(const Doc *doc) {
    GroupMetrics out = {0};
    if (doc->kind == D_GROUP) {
        ++out.groups;
        if (doc->mode != MODE_FLAT)
            ++out.broken;
        if (doc->mode == MODE_FORCED)
            ++out.forced;
    }
    for (int i = 0; i < doc->children.count; ++i) {
        GroupMetrics count = group_metrics(doc->children.data[i]);
        out.groups += count.groups;
        out.broken += count.broken;
        out.forced += count.forced;
    }
    return out;
}
void doc_pool_free(DocPool *pool) {
    for (int i = 0; i < pool->docs.count; ++i) {
        Doc *doc = pool->docs.data[i];
        free(doc->value);
        free(doc->other);
        free(doc->children.data);
        free(doc);
    }
    free(pool->docs.data);
}
