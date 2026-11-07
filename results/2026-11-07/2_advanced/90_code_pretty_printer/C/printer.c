#include "formatter.h"
typedef struct {
    int indent;
    bool flat;
    Doc *doc;
} Command;
typedef struct {
    Command *data;
    int count, capacity;
} Commands;
static void command_push(Commands *commands, Command command) {
    if (commands->count == commands->capacity) {
        commands->capacity = commands->capacity ? commands->capacity * 2 : 64;
        commands->data =
            resize(commands->data, (size_t)commands->capacity * sizeof *commands->data);
    }
    commands->data[commands->count++] = command;
}
static void push_children(Commands *stack, Command command) {
    for (int i = command.doc->children.count - 1; i >= 0; --i)
        command_push(stack, (Command){command.indent, command.flat, command.doc->children.data[i]});
}
static bool fits(int remaining, Command first, const Commands *original) {
    if (remaining < 0)
        return false;
    Commands stack = {0};
    command_push(&stack, first);
    int unused = original->count - 1;
    bool result = true;
    while (stack.count || unused >= 0) {
        if (!stack.count)
            command_push(&stack, original->data[unused--]);
        Command command = stack.data[--stack.count];
        Doc *doc = command.doc;
        bool done = false;
        switch (doc->kind) {
        case D_TEXT:
            remaining -= (int)strlen(doc->value);
            break;
        case D_IF_BREAK:
            remaining -= (int)strlen(command.flat ? doc->other : doc->value);
            break;
        case D_LINE:
            if (!command.flat)
                done = true;
            else
                --remaining;
            break;
        case D_SOFTLINE:
            if (!command.flat)
                done = true;
            break;
        case D_HARDLINE:
            done = true;
            break;
        case D_CONCAT:
            push_children(&stack, command);
            break;
        case D_GROUP:
            command_push(&stack, (Command){command.indent, doc->forced ? false : command.flat,
                                           doc->children.data[0]});
            break;
        case D_NEST:
        case D_ALIGN:
            command_push(&stack, (Command){command.indent, command.flat, doc->children.data[0]});
            break;
        default:
            break;
        }
        if (done)
            break;
        if (remaining < 0) {
            result = false;
            break;
        }
    }
    free(stack.data);
    return result;
}
typedef struct {
    char *data;
    size_t length, capacity;
} LineBuffer;
static void line_add(LineBuffer *line, const char *value) {
    size_t length = strlen(value), size = line->length + length + 1;
    if (size > line->capacity) {
        size_t capacity = line->capacity ? line->capacity : 128;
        while (capacity < size)
            capacity *= 2;
        line->data = resize(line->data, capacity);
        line->capacity = capacity;
    }
    memcpy(line->data + line->length, value, length + 1);
    line->length += length;
}
static void finalize(TextLines *lines, const LineBuffer *current, TextLines *pending, int width,
                     int comment_column) {
    char *line = trim_right(copy_text(current->data ? current->data : ""));
    if (pending->count) {
        char *comments = join_texts(pending, " ");
        size_t length = strlen(line);
        char *spaces = comment_column > 0 && (int)length < comment_column - 1 &&
                               comment_column - 1 + (int)strlen(comments) <= width
                           ? repeated(' ', comment_column - 1 - (int)length)
                           : copy_text(" ");
        char *with_comments = format_text("%s%s%s", line, spaces, comments);
        free(line);
        free(spaces);
        free(comments);
        line = with_comments;
    }
    lines_free(pending);
    lines_push(lines, line);
}
TextLines print_doc(Doc *document, int width, int comment_column) {
    TextLines out = {0}, pending = {0};
    LineBuffer current = {0};
    int column = 0;
    Commands stack = {0};
    command_push(&stack, (Command){0, false, document});
    while (stack.count) {
        Command command = stack.data[--stack.count];
        Doc *doc = command.doc;
        bool newline = false;
        switch (doc->kind) {
        case D_TEXT:
            line_add(&current, doc->value);
            column += (int)strlen(doc->value);
            break;
        case D_IF_BREAK: {
            const char *value = command.flat ? doc->other : doc->value;
            line_add(&current, value);
            column += (int)strlen(value);
            break;
        }
        case D_LINE:
            if (command.flat) {
                line_add(&current, " ");
                ++column;
            } else
                newline = true;
            break;
        case D_SOFTLINE:
            newline = !command.flat;
            break;
        case D_HARDLINE:
            newline = true;
            break;
        case D_CONCAT:
            push_children(&stack, command);
            break;
        case D_NEST:
            command_push(&stack, (Command){command.indent + doc->number, command.flat,
                                           doc->children.data[0]});
            break;
        case D_ALIGN:
            command_push(&stack, (Command){column, command.flat, doc->children.data[0]});
            break;
        case D_SUFFIX:
            lines_add(&pending, doc->value);
            break;
        case D_GROUP: {
            bool flat = true;
            doc->mode = MODE_FLAT;
            if (!command.flat) {
                if (doc->forced) {
                    flat = false;
                    doc->mode = MODE_FORCED;
                } else if (!fits(width - column,
                                 (Command){command.indent, true, doc->children.data[0]}, &stack)) {
                    flat = false;
                    doc->mode = MODE_BREAK;
                }
            }
            command_push(&stack, (Command){command.indent, flat, doc->children.data[0]});
            break;
        }
        default:
            break;
        }
        if (newline) {
            finalize(&out, &current, &pending, width, comment_column);
            current.length = 0;
            if (current.data)
                current.data[0] = 0;
            char *indent = repeated(' ', command.indent);
            line_add(&current, indent);
            free(indent);
            column = command.indent;
        }
    }
    finalize(&out, &current, &pending, width, comment_column);
    free(current.data);
    free(stack.data);
    return out;
}
