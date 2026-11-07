#include "aligner.h"
static char *formatted(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int count = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = malloc((size_t)count + 1);
    vsnprintf(out, (size_t)count + 1, pattern, args);
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
    if (c == EOF && !out.length) {
        free(out.data);
        return NULL;
    }
    if (!out.data)
        text(&out, "");
    return out.data;
}
char *ratio(I numerator, I denominator) {
    if (!denominator)
        return "-";
    I scaled = (10000 * numerator + denominator / 2) / denominator;
    return format("%lld.%04lld", (long long)(scaled / 10000), (long long)(scaled % 10000));
}
Lines sam_header(const Input *input) {
    Lines out = {0};
    line(&out, "@HD\tVN:1.6\tSO:unsorted");
    for (int r = 0; r < input->reference_count; ++r)
        line(&out, "@SQ\tSN:%s\tLN:%d", input->references[r].name, input->references[r].length);
    line(&out, "@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0");
    return out;
}
char *sam_record(const Result *result, const Input *input, int maximum_alternatives) {
    const Read *read = &result->read;
    if (!result->mapped)
        return format("%s\t4\t*\t0\t0\t*\t*\t0\t0\t%s\t%s\tYM:Z:%s", read->name, read->bases,
                      read->quality, result->reason);
    const Alignment *a = &result->primary;
    char *quality = malloc((size_t)read->length + 1);
    for (int i = 0; i < read->length; ++i)
        quality[i] = read->quality[a->strand ? read->length - i - 1 : i];
    quality[read->length] = 0;
    Text out = {0};
    text(
        &out,
        "%s\t%d\t%s\t%d\t%d\t%s\t*\t0\t0\t%s\t%s\tNM:i:%d\tMD:Z:%s\tAS:i:%d\tX0:i:%d\tX1:i:%d\tYM:Z:%s",
        read->name, a->strand ? 16 : 0, input->references[a->reference].name, a->position + 1,
        result->mapq, a->cigar, a->strand ? reverse_complement(read->bases) : read->bases, quality,
        a->nm, a->md, result->score, result->x0, result->x1, result->method);
    if (result->other_count >= 1 && result->other_count <= maximum_alternatives) {
        text(&out, "\tXA:Z:");
        for (int i = 0; i < result->other_count; ++i) {
            const Alignment *other = &result->others[i];
            text(&out, "%s,%c%d,%s,%d;", input->references[other->reference].name,
                 other->strand ? '-' : '+', other->position + 1, other->cigar, other->nm);
        }
    }
    free(quality);
    return out.data;
}
void save(const char *name, const Lines *lines) {
    char *path = format("output/%s", name);
    FILE *out = fopen(path, "w");
    for (int i = 0; i < lines->count; ++i)
        fprintf(out, "%s\n", lines->values[i]);
    fclose(out);
    free(path);
}
