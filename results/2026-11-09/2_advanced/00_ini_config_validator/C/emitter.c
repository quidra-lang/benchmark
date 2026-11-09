#include "emitter.h"
#include <inttypes.h>
#include <sys/stat.h>
#include <errno.h>

char *string_notation(const char *text) {
    Buffer buffer = {0};
    buffer_char(&buffer, '"');
    for (; *text; ++text) {
        switch (*text) {
            case '\\': buffer_text(&buffer, "\\\\"); break;
            case '"': buffer_text(&buffer, "\\\""); break;
            case '\n': buffer_text(&buffer, "\\n"); break;
            case '\t': buffer_text(&buffer, "\\t"); break;
            default: buffer_char(&buffer, *text);
        }
    }
    buffer_char(&buffer, '"');
    return buffer_result(&buffer);
}

char *value_notation(Value value) {
    if (value.kind == TYPE_STRING) return string_notation(value.text);
    if (value.kind == TYPE_BOOL) return value.number ? "true" : "false";
    if (value.kind == TYPE_INT || value.kind == TYPE_SIZE || value.kind == TYPE_DURATION)
        return format("%" PRId64, value.number);
    if (value.kind != TYPE_LIST) return value.text;
    Buffer buffer = {0};
    buffer_char(&buffer, '[');
    for (size_t i = 0; i < value.count; ++i) {
        if (i) buffer_text(&buffer, ", ");
        buffer_text(&buffer, value_notation(value.items[i]));
    }
    buffer_char(&buffer, ']');
    return buffer_result(&buffer);
}

const char *shown(const OutputKey *output) {
    return output->spec && output->spec->secret ? "********" : output->notation;
}

static void line(Buffer *buffer, const char *text) {
    buffer_text(buffer, text);
    buffer_char(buffer, '\n');
}

static void normalized_block(Buffer *buffer, Profile *profile) {
    line(buffer, format("profile %s", profile->name));
    Strings keys = output_keys(profile->outputs);
    char *previous = NULL;
    for (size_t i = 0; i < keys.len; ++i) {
        OutputKey *output = &profile->outputs.data[output_index(profile->outputs, keys.data[i])];
        char *section = section_of(output->key);
        if (!previous || strcmp(previous, section)) {
            line(buffer, format("[%s]", section));
            previous = section;
        }
        line(buffer, format("%s = %s", name_of(output->key), shown(output)));
    }
}

static void diagnostics_block(Buffer *buffer, Profile *profile) {
    line(buffer, format("profile %s errors %d warnings %d", profile->name, profile->errors, profile->warnings));
    for (size_t i = 0; i < profile->diagnostics.len; ++i) {
        Diagnostic diagnostic = profile->diagnostics.data[i];
        line(buffer, format("%s %s %s", origin_text(diagnostic.origin), diagnostic.code, diagnostic.message));
    }
}

static void report_block(Buffer *buffer, Profile *profile) {
    line(buffer, format("profile %s", profile->name));
    line(buffer, "includes");
    for (size_t i = 0; i < profile->tree.len; ++i) {
        TreeLine branch = profile->tree.data[i];
        for (int j = 0; j < 2 + 2 * branch.depth; ++j) buffer_char(buffer, ' ');
        line(buffer, branch.text);
    }
    line(buffer, "overridden");
    bool any = false;
    Strings keys = output_keys(profile->outputs);
    for (size_t i = 0; i < keys.len; ++i) {
        OutputKey output = profile->outputs.data[output_index(profile->outputs, keys.data[i])];
        if (output.definition.history.len < 2) continue;
        Strings history = {0};
        for (size_t j = 0; j < output.definition.history.len; ++j)
            PUSH(history, origin_text(output.definition.history.data[j]));
        line(buffer, format("  %s: %s", output.key, join_strings(history, " -> ")));
        any = true;
    }
    if (!any) line(buffer, "  (none)");
    line(buffer, format("keys %zu documents %d manifest %d defaults %d", profile->outputs.len,
                        profile->document_keys, profile->manifest_keys, profile->default_keys));
    line(buffer, format("dropped %zu", profile->dropped));
    line(buffer, format("errors %d warnings %d", profile->errors, profile->warnings));
}

static void diff_block(Buffer *buffer, ProfileDiff diff) {
    line(buffer, format("diff %s -> %s: %d added, %d removed, %d changed",
                        diff.first, diff.second, diff.added, diff.removed, diff.changed));
    for (size_t i = 0; i < diff.entries.len; ++i) {
        DiffEntry entry = diff.entries.data[i];
        if (entry.mark == '~')
            line(buffer, format("~ %s: %s -> %s", entry.key, shown(entry.before), shown(entry.after)));
        else
            line(buffer, format("%c %s = %s", entry.mark, entry.key,
                                shown(entry.mark == '+' ? entry.after : entry.before)));
    }
}

static void write_file(const char *name, Buffer *buffer) {
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file) exit(EXIT_FAILURE);
    const char *text = buffer_result(buffer);
    size_t length = strlen(text);
    if (fwrite(text, 1, length, file) != length) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
}

void write_outputs(Profiles profiles, Diffs diffs) {
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    Buffer normalized = {0}, diagnostics = {0}, report_buffer = {0}, differences = {0};
    for (size_t i = 0; i < profiles.len; ++i) {
        if (i) {
            buffer_char(&normalized, '\n');
            buffer_char(&diagnostics, '\n');
            buffer_char(&report_buffer, '\n');
        }
        normalized_block(&normalized, profiles.data[i]);
        diagnostics_block(&diagnostics, profiles.data[i]);
        report_block(&report_buffer, profiles.data[i]);
    }
    for (size_t i = 0; i < diffs.len; ++i) {
        if (i) buffer_char(&differences, '\n');
        diff_block(&differences, diffs.data[i]);
    }
    write_file("normalized.txt", &normalized);
    write_file("diagnostics.txt", &diagnostics);
    write_file("diff.txt", &differences);
    write_file("report.txt", &report_buffer);
}
