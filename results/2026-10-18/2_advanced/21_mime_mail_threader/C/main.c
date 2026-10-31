#include "mail.h"

typedef struct Allocation { struct Allocation *next; max_align_t alignment; } Allocation;
static Allocation *allocations;

static void release_all(void) {
    while (allocations) { Allocation *next = allocations->next; free(allocations); allocations = next; }
}
void *allocate(size_t bytes) {
    static bool registered;
    if (!registered) { atexit(release_all); registered = true; }
    Allocation *block = calloc(1, sizeof(*block) + bytes);
    if (!block) exit(EXIT_FAILURE);
    block->next = allocations;
    allocations = block;
    return block + 1;
}
static char *formatted(const char *pattern, va_list arguments) {
    va_list copy;
    va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    if (length < 0) exit(EXIT_FAILURE);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, arguments);
    return result;
}
char *format(const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *result = formatted(pattern, arguments);
    va_end(arguments);
    return result;
}
void text_add(Text *text, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *part = formatted(pattern, arguments);
    va_end(arguments);
    size_t length = strlen(part);
    if (text->size + length + 1 > text->capacity) {
        size_t capacity = text->capacity ? 2 * text->capacity : 64;
        while (capacity < text->size + length + 1) capacity *= 2;
        char *data = allocate(capacity);
        if (text->size) memcpy(data, text->data, text->size);
        text->data = data;
        text->capacity = capacity;
    }
    memcpy(text->data + text->size, part, length + 1);
    text->size += length;
}
void add_line(Lines *lines, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *line = formatted(pattern, arguments);
    va_end(arguments);
    if (lines->count == lines->capacity) {
        int capacity = lines->capacity ? 2 * lines->capacity : 32;
        char **items = allocate((size_t)capacity * sizeof(*items));
        if (lines->count) memcpy(items, lines->items, (size_t)lines->count * sizeof(*items));
        lines->items = items;
        lines->capacity = capacity;
    }
    lines->items[lines->count++] = line;
}
char *slice(const char *text, size_t start, size_t length) {
    char *result = allocate(length + 1);
    memcpy(result, text + start, length);
    return result;
}
static char lower_char(char character) { return character >= 'A' && character <= 'Z' ? (char)(character + 'a' - 'A') : character; }
char *lowercase(const char *text) {
    char *result = slice(text, 0, strlen(text));
    for (char *character = result; *character; ++character) *character = lower_char(*character);
    return result;
}
bool equal_case(const char *first, const char *second) {
    while (*first && *second) if (lower_char(*first++) != lower_char(*second++)) return false;
    return *first == *second;
}
bool whitespace(char character) { return character == ' ' || character == '\t'; }
char *strip(const char *text) {
    size_t start = 0, end = strlen(text);
    while (start < end && whitespace(text[start])) ++start;
    while (end > start && whitespace(text[end - 1])) --end;
    return slice(text, start, end - start);
}
char *rstrip(const char *text) {
    size_t end = strlen(text);
    while (end && whitespace(text[end - 1])) --end;
    return slice(text, 0, end);
}
Lines split_text(const char *text, char separator) {
    Lines result = {0};
    size_t start = 0;
    for (size_t i = 0;; ++i) if (!text[i] || text[i] == separator) {
        add_line(&result, "%s", slice(text, start, i - start));
        if (!text[i]) break;
        start = i + 1;
    }
    return result;
}
Lines split_words(const char *text) {
    Lines result = {0};
    size_t position = 0;
    while (text[position]) {
        while (whitespace(text[position])) ++position;
        if (!text[position]) break;
        size_t start = position;
        while (text[position] && !whitespace(text[position])) ++position;
        add_line(&result, "%s", slice(text, start, position - start));
    }
    return result;
}
char *join(Lines lines, const char *separator) {
    Text result = {0};
    for (int i = 0; i < lines.count; ++i) text_add(&result, "%s%s", i ? separator : "", lines.items[i]);
    return result.data ? result.data : "";
}
char *collapse_whitespace(const char *text) { return join(split_words(text), " "); }

static Lines read_lines(const char *name) {
    FILE *file = fopen(format("input/%s", name), "rb");
    if (!file) exit(EXIT_FAILURE);
    Lines lines = {0};
    Text line = {0};
    int character;
    while ((character = fgetc(file)) != EOF) {
        if (character == '\n') {
            add_line(&lines, "%s", line.data ? line.data : "");
            line.size = 0;
            if (line.data) line.data[0] = '\0';
        } else text_add(&line, "%c", character);
    }
    if (ferror(file)) exit(EXIT_FAILURE);
    fclose(file);
    return lines;
}
static SourceLines *read_mailbox(int *count) {
    Lines source = read_lines("mailbox.mbox");
    SourceLines *messages = allocate(500 * sizeof(*messages));
    int capacities[500] = {0};
    *count = 0;
    for (int i = 0; i < source.count; ++i) {
        char *line = source.items[i];
        if (!strncmp(line, "From ", 5)) { ++*count; continue; }
        SourceLines *message = &messages[*count - 1];
        int *capacity = &capacities[*count - 1];
        if (message->count == *capacity) {
            *capacity = *capacity ? 2 * *capacity : 32;
            SourceLine *items = allocate((size_t)*capacity * sizeof(*items));
            if (message->count) memcpy(items, message->items, (size_t)message->count * sizeof(*items));
            message->items = items;
        }
        int arrows = 0;
        while (line[arrows] == '>') ++arrows;
        if (arrows && !strncmp(line + arrows, "From ", 5)) ++line;
        message->items[message->count++] = (SourceLine){i + 1, line};
    }
    for (int i = 0; i < *count; ++i) if (messages[i].count && !messages[i].items[messages[i].count - 1].text[0]) --messages[i].count;
    return messages;
}
static void split_sections(SourceLines lines, SourceLines *head, SourceLines *body) {
    *head = lines;
    *body = (SourceLines){0};
    for (int i = 0; i < lines.count; ++i) if (!lines.items[i].text[0]) {
        head->count = i;
        body->items = lines.items + i + 1;
        body->count = lines.count - i - 1;
        return;
    }
}
static bool is_message_id(const char *text) {
    size_t size = strlen(text);
    if (size < 3 || text[0] != '<' || text[size - 1] != '>' || text[1] == '@' || text[size - 2] == '@') return false;
    int ats = 0;
    for (size_t i = 1; i + 1 < size; ++i) {
        if ((unsigned char)text[i] < 33 || (unsigned char)text[i] > 126 || strchr("<>()\"\\", text[i])) return false;
        ats += text[i] == '@';
    }
    return ats == 1;
}
static Lines extract_ids(const char *text) {
    Lines result = {0};
    const char *start = strchr(text, '<');
    while (start) {
        const char *end = strchr(start + 1, '>');
        if (!end) break;
        char *id = slice(start, 0, (size_t)(end - start + 1));
        if (is_message_id(id)) add_line(&result, "%s", id);
        start = strchr(end + 1, '<');
    }
    return result;
}
static void add_entity(Entities *entities, Entity *entity) {
    if (entities->count == entities->capacity) {
        int capacity = entities->capacity ? 2 * entities->capacity : 8;
        Entity **items = allocate((size_t)capacity * sizeof(*items));
        if (entities->count) memcpy(items, entities->items, (size_t)entities->count * sizeof(*items));
        entities->items = items;
        entities->capacity = capacity;
    }
    entities->items[entities->count++] = entity;
}
static Entity *parse_entity(Message *message, char *number, Header header, SourceLines lines, bool mime) {
    Entity *entity = allocate(sizeof(*entity));
    entity->number = number; entity->type = "text"; entity->subtype = "plain"; entity->content = "";
    char *value = header_value(&header, "Content-Type");
    if (mime && value) {
        Parameters parsed = parse_parameters(value, true);
        if (!parsed.valid) add_line(&message->problems, "bad Content-Type in part %s", number);
        else { entity->type = parsed.type; entity->subtype = parsed.subtype; entity->parameters = parsed; }
    }
    value = header_value(&header, "Content-Disposition");
    if (mime && value) {
        Parameters parsed = parse_parameters(value, false);
        if (!parsed.valid) add_line(&message->problems, "bad Content-Disposition in part %s", number);
        else { entity->disposition = parsed.type; entity->filename = parameter(&parsed, "filename"); }
    }
    if (!entity->filename || !entity->filename[0]) entity->filename = parameter(&entity->parameters, "name");
    char *charset = parameter(&entity->parameters, "charset");
    if (!strcmp(entity->type, "text") && charset && !equal_case(charset, "us-ascii")) add_line(&message->problems, "unsupported charset \"%s\" in part %s", lowercase(charset), number);
    if (mime && !strcmp(entity->type, "multipart")) {
        char *boundary = parameter(&entity->parameters, "boundary");
        if (!boundary || !boundary[0]) add_line(&message->problems, "missing boundary in part %s", number);
        else {
            entity->split = true;
            char *opening = format("--%s", boundary), *closing = format("--%s--", boundary);
            SourceLines *parts = allocate((size_t)(lines.count + 1) * sizeof(*parts));
            int part_count = 0;
            bool closed = false;
            for (int i = 0; i < lines.count; ++i) {
                char *text = rstrip(lines.items[i].text);
                if (!strcmp(text, closing)) { closed = true; break; }
                if (!strcmp(text, opening)) { parts[part_count++].items = lines.items + i + 1; }
                else if (part_count) ++parts[part_count - 1].count;
            }
            if (!part_count) add_line(&message->problems, "no parts in part %s", number);
            else if (!closed) add_line(&message->problems, "unterminated multipart in part %s", number);
            for (int i = 0; i < part_count; ++i) {
                SourceLines head, body;
                split_sections(parts[i], &head, &body);
                Header child_header = parse_fields(head);
                for (int j = 0; j < child_header.invalid_count; ++j) add_line(&message->problems, "bad header line %d", child_header.invalid[j]);
                add_entity(&entity->children, parse_entity(message, format("%s.%d", number, i + 1), child_header, body, true));
            }
            return entity;
        }
    }
    Lines body = {0};
    for (int i = 0; i < lines.count; ++i) add_line(&body, "%s", lines.items[i].text);
    char *original = join(body, "\n");
    value = header_value(&header, "Content-Transfer-Encoding");
    char *encoding = mime && value ? lowercase(value) : "7bit";
    if (!strcmp(encoding, "base64")) {
        entity->content = decode_base64_body(original);
        if (!entity->content) { add_line(&message->problems, "bad base64 in part %s", number); entity->content = ""; }
    } else if (!strcmp(encoding, "quoted-printable")) {
        Decoded decoded = decode_quoted_printable(original);
        entity->content = decoded.text;
        if (decoded.error) add_line(&message->problems, "bad quoted-printable in part %s", number);
    } else {
        entity->content = original;
        if (strcmp(encoding, "7bit") && strcmp(encoding, "8bit") && strcmp(encoding, "binary")) add_line(&message->problems, "unknown encoding \"%s\" in part %s", encoding, number);
    }
    return entity;
}
static Lines read_recipients(Message *message, const Header *header, const char *name) {
    Lines result = {0};
    char *value = header_value(header, name);
    if (!value) return result;
    Addresses parsed = parse_addresses(value);
    if (!parsed.valid) { add_line(&message->problems, "bad %s", name); return result; }
    for (int i = 0; i < parsed.count; ++i) {
        Address address = parsed.items[i];
        if (!address.group) add_line(&result, "%s", address.mailbox.address);
        else for (int j = 0; j < address.count; ++j) add_line(&result, "%s", address.members[j].address);
    }
    if (parsed.encoding_error) add_line(&message->problems, "bad encoded word in %s", name);
    return result;
}
static void process_message(Message *message, SourceLines lines, Message *earlier, int earlier_count) {
    const char *checked[] = {"From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References", "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition"};
    SourceLines head, body;
    split_sections(lines, &head, &body);
    Header header = parse_fields(head);
    for (int i = 0; i < header.invalid_count; ++i) add_line(&message->problems, "bad header line %d", header.invalid[i]);
    for (int i = 0; i < 12; ++i) if (header_count(&header, checked[i]) > 1) add_line(&message->problems, "duplicate %s", checked[i]);
    char *value = header_value(&header, "From");
    if (!value) add_line(&message->problems, "missing From");
    else {
        Addresses parsed = parse_addresses(value);
        if (!parsed.valid || parsed.count != 1 || parsed.items[0].group) add_line(&message->problems, "bad From");
        else {
            message->sender = allocate(sizeof(Mailbox));
            *message->sender = parsed.items[0].mailbox;
            if (parsed.encoding_error) add_line(&message->problems, "bad encoded word in From");
        }
    }
    message->to = read_recipients(message, &header, "To");
    message->cc = read_recipients(message, &header, "Cc");
    value = header_value(&header, "Subject");
    Decoded subject = decode_unstructured(value ? value : "");
    message->subject = subject.text;
    if (subject.error) add_line(&message->problems, "bad encoded word in Subject");
    message->base_subject = message->subject;
    while (strlen(message->base_subject) >= 3 && equal_case(slice(message->base_subject, 0, 3), "re:")) {
        message->base_subject += 3;
        while (message->base_subject[0] == ' ') ++message->base_subject;
        message->reply = true;
    }
    value = header_value(&header, "Date");
    if (!value) add_line(&message->problems, "missing Date");
    else {
        message->date = parse_date(value);
        if (!message->date.valid) add_line(&message->problems, "%s", message->date.error);
    }
    message->id = "";
    value = header_value(&header, "Message-ID");
    if (!value) add_line(&message->problems, "missing Message-ID");
    else if (!is_message_id(value)) add_line(&message->problems, "bad Message-ID");
    else {
        int duplicate = -1;
        for (int i = 0; i < earlier_count; ++i) if (!strcmp(value, earlier[i].id)) { duplicate = i; break; }
        if (duplicate >= 0) add_line(&message->problems, "Message-ID already used by message %d", earlier[duplicate].number);
        else message->id = value;
    }
    value = header_value(&header, "References");
    message->references = extract_ids(value ? value : "");
    value = header_value(&header, "In-Reply-To");
    Lines replies = extract_ids(value ? value : "");
    if (replies.count && (!message->references.count || strcmp(message->references.items[message->references.count - 1], replies.items[0]))) add_line(&message->references, "%s", replies.items[0]);
    bool mime = false;
    value = header_value(&header, "MIME-Version");
    if (value) {
        char *comments = remove_comments(value);
        if (comments) {
            Text compact = {0};
            for (char *character = comments; *character; ++character) if (!whitespace(*character)) text_add(&compact, "%c", *character);
            mime = !strcmp(compact.data ? compact.data : "", "1.0");
        }
        if (!mime) add_line(&message->problems, "bad MIME-Version");
    }
    message->body = parse_entity(message, "1", header, body, mime);
}

typedef struct { int depth; char *text; bool flowing; } LogicalLine;
typedef struct { LogicalLine *items; int count, capacity; } LogicalLines;
static void add_logical(LogicalLines *lines, int depth, char *text, bool flowing) {
    if (lines->count == lines->capacity) {
        int capacity = lines->capacity ? 2 * lines->capacity : 16;
        LogicalLine *items = allocate((size_t)capacity * sizeof(*items));
        if (lines->count) memcpy(items, lines->items, (size_t)lines->count * sizeof(*items));
        lines->items = items; lines->capacity = capacity;
    }
    lines->items[lines->count++] = (LogicalLine){depth, text, flowing};
}
static char *quote_prefix(int depth) {
    if (!depth) return "";
    char *prefix = allocate((size_t)depth + 2);
    memset(prefix, '>', (size_t)depth);
    prefix[depth] = ' ';
    return prefix;
}
static void wrap(const char *text, const char *prefix, Lines *lines) {
    Lines words = split_words(text);
    char *current = "";
    for (int i = 0; i < words.count; ++i) {
        char *word = words.items[i];
        if (current[0] && strlen(current) + 1 + strlen(word) > 72) { add_line(lines, "%s%s", prefix, current); current = word; }
        else current = current[0] ? format("%s %s", current, word) : word;
    }
    add_line(lines, "%s%s", prefix, current);
}
static Lines flowed_lines(const char *content, bool delete_space) {
    Lines result = {0};
    if (!content[0]) return result;
    Lines source = split_text(content, '\n');
    LogicalLines logical = {0};
    for (int i = 0; i < source.count; ++i) {
        char *text = source.items[i];
        int depth = 0;
        while (text[depth] == '>') ++depth;
        text += depth;
        if (text[0] == ' ') ++text;
        size_t size = strlen(text);
        bool flowing = size && text[size - 1] == ' ' && strcmp(text, "-- ");
        LogicalLine *previous = logical.count ? &logical.items[logical.count - 1] : NULL;
        if (previous && previous->flowing && previous->depth == depth) {
            size_t previous_size = strlen(previous->text);
            char *left = delete_space ? slice(previous->text, 0, previous_size - 1) : previous->text;
            previous->text = format("%s%s", left, text);
            previous->flowing = flowing;
        } else add_logical(&logical, depth, text, flowing);
    }
    for (int i = 0; i < logical.count; ++i) wrap(logical.items[i].text, quote_prefix(logical.items[i].depth), &result);
    return result;
}
static int reference_value(const char *name) {
    const char *names[] = {"amp", "lt", "gt", "quot", "apos", "nbsp"};
    const int values[] = {'&','<','>','"','\'', ' '};
    for (int i = 0; i < 6; ++i) if (!strcmp(name, names[i])) return values[i];
    size_t size = strlen(name);
    if (name[0] == '#' && size >= 2 && size <= 4) {
        for (size_t i = 1; i < size; ++i) if (name[i] < '0' || name[i] > '9') return 0;
        int value = atoi(name + 1);
        if (value >= 32 && value <= 126) return value;
    }
    return 0;
}
static char *replace_references(const char *text) {
    Text result = {0};
    for (size_t position = 0; text[position];) {
        int replacement = 0;
        const char *end = text[position] == '&' ? strchr(text + position + 1, ';') : NULL;
        if (end) replacement = reference_value(slice(text, position + 1, (size_t)(end - text - position - 1)));
        if (replacement) { text_add(&result, "%c", replacement); position = (size_t)(end - text + 1); }
        else text_add(&result, "%c", text[position++]);
    }
    return result.data ? result.data : "";
}
static bool tag_character(char character) { return (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9'); }
static bool paragraph_tag(const char *name) {
    const char *names[] = {"p", "div", "ul", "ol", "table", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6"};
    for (int i = 0; i < 13; ++i) if (!strcmp(name, names[i])) return true;
    return false;
}
static LogicalLines html_blocks(const char *content) {
    LogicalLines blocks = {0};
    int depth = 0;
    Text text = {0};
    char *hide = NULL;
    size_t position = 0;
    while (content[position]) {
        const char *closing = content[position] == '<' ? strchr(content + position + 1, '>') : NULL;
        if (!closing) {
            if (!hide) text_add(&text, "%c", content[position]);
            ++position;
            continue;
        }
        char *inside = slice(content, position + 1, (size_t)(closing - content - position - 1));
        position = (size_t)(closing - content + 1);
        bool end_tag = inside[0] == '/';
        const char *start = inside + end_tag;
        size_t size = 0;
        while (tag_character(start[size])) ++size;
        char *name = lowercase(slice(start, 0, size));
        if (hide) {
            if (end_tag && !strcmp(name, hide)) hide = NULL;
        } else if (!end_tag && (!strcmp(name, "head") || !strcmp(name, "style") || !strcmp(name, "script"))) hide = name;
        else if (!strcmp(name, "br") || (!strcmp(name, "li") && !end_tag)) {
            add_logical(&blocks, depth, text.data ? text.data : "", false);
            text = (Text){0};
            if (!strcmp(name, "li")) text_add(&text, "* ");
        } else if (paragraph_tag(name)) {
            add_logical(&blocks, depth, text.data ? text.data : "", false);
            add_logical(&blocks, depth, "", false);
            text = (Text){0};
            if (!strcmp(name, "blockquote")) {
                if (!end_tag) ++depth;
                else if (depth) --depth;
            }
        }
    }
    add_logical(&blocks, depth, text.data ? text.data : "", false);
    return blocks;
}
static Lines html_lines(const char *content) {
    Lines result = {0};
    LogicalLines blocks = html_blocks(content);
    for (int i = 0; i < blocks.count; ++i) {
        char *text = format("%s", blocks.items[i].text);
        for (char *character = text; *character; ++character) if (*character == '\n') *character = ' ';
        text = replace_references(collapse_whitespace(text));
        size_t start = 0, end = strlen(text);
        while (start < end && text[start] == ' ') ++start;
        while (end > start && text[end - 1] == ' ') --end;
        text = slice(text, start, end - start);
        if (text[0]) wrap(text, quote_prefix(blocks.items[i].depth), &result);
        else if (result.count && result.items[result.count - 1][0]) add_line(&result, "");
    }
    while (result.count && !result.items[result.count - 1][0]) --result.count;
    return result;
}
static Entities collect_text_parts(Entity *entity, bool allow_html) {
    Entities result = {0};
    if (!entity->split) {
        if ((entity->disposition && !strcmp(entity->disposition, "attachment")) || strcmp(entity->type, "text")) return result;
        if (!strcmp(entity->subtype, "plain") || (allow_html && !strcmp(entity->subtype, "html"))) add_entity(&result, entity);
        return result;
    }
    if (!strcmp(entity->subtype, "alternative")) {
        for (int html = 0; html < 2; ++html) {
            for (int i = 0; i < entity->children.count; ++i) {
                Entities parts = collect_text_parts(entity->children.items[i], html != 0);
                if (parts.count) return parts;
            }
        }
        return result;
    }
    for (int i = 0; i < entity->children.count; ++i) {
        Entities parts = collect_text_parts(entity->children.items[i], allow_html);
        for (int j = 0; j < parts.count; ++j) add_entity(&result, parts.items[j]);
    }
    return result;
}
static Lines display_lines(const Entity *entity, char **text_format) {
    if (!strcmp(entity->subtype, "html")) { *text_format = "html"; return html_lines(entity->content); }
    char *format_value = parameter(&entity->parameters, "format");
    if (format_value && equal_case(format_value, "flowed")) {
        *text_format = "flowed";
        char *delsp = parameter(&entity->parameters, "delsp");
        return flowed_lines(entity->content, delsp && equal_case(delsp, "yes"));
    }
    *text_format = "plain";
    return entity->content[0] ? split_text(entity->content, '\n') : (Lines){0};
}
static char *subject_notation(const char *subject) { return subject[0] ? (char *)subject : "(no subject)"; }
static char *date_notation(Date date) { return date.valid ? format_utc(date.seconds) : "invalid"; }
static void paragraph(Lines *target, Lines source) {
    if (target->count) add_line(target, "");
    for (int i = 0; i < source.count; ++i) add_line(target, "%s", source.items[i]);
}
typedef struct { int messages, depth; Lines senders, rows; bool has_dates; Integer first, last; } ThreadStats;
static void walk_thread(Container *container, int number, int depth, const char *prefix, const char *stem, ThreadStats *stats) {
    if (depth > stats->depth) stats->depth = depth;
    Message *message = container->message;
    if (message) {
        ++stats->messages;
        message->thread = number; message->depth = depth;
        message->parent = container->parent ? container->parent->message : NULL;
        if (message->sender) {
            bool present = false;
            for (int i = 0; i < stats->senders.count; ++i) if (!strcmp(stats->senders.items[i], message->sender->address)) present = true;
            if (!present) add_line(&stats->senders, "%s", message->sender->address);
        }
        if (message->date.valid) {
            if (!stats->has_dates || message->date.seconds < stats->first) stats->first = message->date.seconds;
            if (!stats->has_dates || message->date.seconds > stats->last) stats->last = message->date.seconds;
            stats->has_dates = true;
        }
        add_line(&stats->rows, "%s[%d] %s %s %s", prefix, message->number, date_notation(message->date), message->sender ? message->sender->address : "-", subject_notation(message->subject));
    } else if (container->subject) add_line(&stats->rows, "%s[subject] %s", prefix, container->subject);
    else add_line(&stats->rows, "%s[missing] %s", prefix, container->id);
    for (int i = 0; i < container->children.count; ++i) {
        bool last = i + 1 == container->children.count;
        walk_thread(container->children.items[i], number, depth + 1, format("%s%s", stem, last ? "`- " : "+- "), format("%s%s", stem, last ? "   " : "|  "), stats);
    }
}
static Lines thread_report(Container *root, int number) {
    ThreadStats stats = {0};
    walk_thread(root, number, 0, "", "", &stats);
    Lines lines = {0};
    add_line(&lines, "thread %d messages %d depth %d senders %d", number, stats.messages, stats.depth, stats.senders.count);
    if (stats.has_dates) add_line(&lines, "span %s .. %s", format_utc(stats.first), format_utc(stats.last));
    else add_line(&lines, "span -");
    add_line(&lines, "subject %s", subject_notation(root->subject ? root->subject : root_subject(root)));
    for (int i = 0; i < stats.rows.count; ++i) add_line(&lines, "%s", stats.rows.items[i]);
    return lines;
}
static void entity_lines(const Entity *entity, Lines *lines) {
    Text line = {0};
    text_add(&line, "part %s %s/%s", entity->number, entity->type, entity->subtype);
    if (!entity->split) {
        text_add(&line, " %zu", strlen(entity->content));
        if (entity->disposition) text_add(&line, " %s", entity->disposition);
        if (entity->filename && entity->filename[0]) text_add(&line, " \"%s\"", entity->filename);
    }
    add_line(lines, "%s", line.data);
    if (entity->split) for (int i = 0; i < entity->children.count; ++i) entity_lines(entity->children.items[i], lines);
}
static Lines message_report(const Message *message) {
    Lines lines = {0};
    add_line(&lines, "message %d", message->number);
    add_line(&lines, "id %s", message->id[0] ? message->id : "-");
    add_line(&lines, "date %s", date_notation(message->date));
    char *sender = "-";
    if (message->sender) sender = message->sender->name[0] ? format("%s <%s>", message->sender->name, message->sender->address) : message->sender->address;
    add_line(&lines, "from %s", sender);
    add_line(&lines, "to %s", message->to.count ? join(message->to, ", ") : "-");
    add_line(&lines, "cc %s", message->cc.count ? join(message->cc, ", ") : "-");
    add_line(&lines, "subject %s", subject_notation(message->subject));
    add_line(&lines, "refs %s", message->references.count ? join(message->references, " ") : "-");
    add_line(&lines, "thread %d depth %d parent %s", message->thread, message->depth, message->parent ? format("%d", message->parent->number) : "-");
    entity_lines(message->body, &lines);
    return lines;
}
static Lines body_report(const char *request, Message *messages, int count) {
    Lines lines = {0};
    add_line(&lines, "request %s", request);
    Message *message = NULL;
    for (int i = 0; i < count; ++i) if (messages[i].id[0] && !strcmp(messages[i].id, request)) { message = &messages[i]; break; }
    if (!message) { add_line(&lines, "not found"); return lines; }
    Entities parts = collect_text_parts(message->body, true);
    add_line(&lines, "message %d text parts %d", message->number, parts.count);
    for (int i = 0; i < parts.count; ++i) {
        char *text_format;
        Lines display = display_lines(parts.items[i], &text_format);
        int quoted = 0, signature = 0;
        for (int j = 0; j < display.count; ++j) {
            display.items[j] = rstrip(display.items[j]);
            quoted += display.items[j][0] == '>';
            if (!strcmp(display.items[j], "--")) signature = display.count - j - 1;
        }
        add_line(&lines, "part %s %s lines %d quoted %d signature %d", parts.items[i]->number, text_format, display.count, quoted, signature);
        for (int j = 0; j < display.count; ++j) add_line(&lines, "%s%s", display.items[j][0] ? "| " : "|", display.items[j]);
    }
    return lines;
}
typedef struct { char *address, *name; int count, thread_count; bool threads[501], dated; Integer first, last; } SenderStats;
static int sender_order(const void *first, const void *second) {
    const SenderStats *a = first, *b = second;
    return a->count != b->count ? b->count - a->count : strcmp(a->address, b->address);
}
static char *csv_field(char *text) {
    if (!strchr(text, ',') && !strchr(text, '"')) return text;
    Text result = {0};
    text_add(&result, "\"");
    for (char *character = text; *character; ++character) {
        if (*character == '"') text_add(&result, "\"\"");
        else text_add(&result, "%c", *character);
    }
    text_add(&result, "\"");
    return result.data;
}
static Lines senders_report(Message *messages, int count) {
    SenderStats *stats = allocate((size_t)count * sizeof(*stats));
    int sender_count = 0;
    for (int i = 0; i < count; ++i) {
        Message *message = &messages[i];
        if (!message->sender) continue;
        int number = 0;
        while (number < sender_count && strcmp(stats[number].address, message->sender->address)) ++number;
        if (number == sender_count) { stats[number].address = message->sender->address; stats[number].name = ""; ++sender_count; }
        SenderStats *entry = &stats[number];
        ++entry->count;
        if (!entry->threads[message->thread]) { entry->threads[message->thread] = true; ++entry->thread_count; }
        if (message->date.valid) {
            if (!entry->dated || message->date.seconds < entry->first) entry->first = message->date.seconds;
            if (!entry->dated || message->date.seconds > entry->last) entry->last = message->date.seconds;
            entry->dated = true;
        }
        if (message->sender->name[0]) entry->name = message->sender->name;
    }
    if (sender_count > 1) qsort(stats, (size_t)sender_count, sizeof(*stats), sender_order);
    Lines lines = {0};
    add_line(&lines, "address,name,messages,threads,first,last");
    for (int i = 0; i < sender_count; ++i) {
        SenderStats *entry = &stats[i];
        add_line(&lines, "%s,%s,%d,%d,%s,%s", entry->address, csv_field(entry->name), entry->count, entry->thread_count, entry->dated ? format_utc(entry->first) : "-", entry->dated ? format_utc(entry->last) : "-");
    }
    return lines;
}
static Lines malformed_report(Message *messages, int count) {
    int malformed = 0, problems = 0;
    for (int i = 0; i < count; ++i) { malformed += messages[i].problems.count > 0; problems += messages[i].problems.count; }
    Lines lines = {0};
    add_line(&lines, "messages %d malformed %d problems %d", count, malformed, problems);
    for (int i = 0; i < count; ++i) {
        for (int j = 0; j < messages[i].problems.count; ++j) add_line(&lines, "message %d: %s", messages[i].number, messages[i].problems.items[j]);
    }
    return lines;
}
static void write_lines(const char *name, Lines lines) {
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file) exit(EXIT_FAILURE);
    for (int i = 0; i < lines.count; ++i) if (fprintf(file, "%s\n", lines.items[i]) < 0) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
}

int main(void) {
    int count;
    SourceLines *source = read_mailbox(&count);
    Message *messages = allocate((size_t)count * sizeof(*messages));
    for (int i = 0; i < count; ++i) { messages[i].number = i + 1; process_message(&messages[i], source[i], messages, i); }
    Containers roots = build_threads(messages, count);
    Lines threads = {0}, message_lines = {0}, bodies = {0};
    for (int i = 0; i < roots.count; ++i) paragraph(&threads, thread_report(roots.items[i], i + 1));
    for (int i = 0; i < count; ++i) {
        Message *message = &messages[i], *parent = message->parent;
        if (parent && message->date.valid && parent->date.valid && message->date.seconds < parent->date.seconds) add_line(&message->problems, "dated before parent message %d", parent->number);
        paragraph(&message_lines, message_report(message));
    }
    Lines requests = read_lines("requests.txt");
    for (int i = 0; i < requests.count; ++i) paragraph(&bodies, body_report(requests.items[i], messages, count));
    write_lines("threads.txt", threads);
    write_lines("messages.txt", message_lines);
    write_lines("bodies.txt", bodies);
    write_lines("senders.csv", senders_report(messages, count));
    write_lines("malformed.txt", malformed_report(messages, count));
    return 0;
}
