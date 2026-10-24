#include <stdbool.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum { STRING, LIST, HASH, SET, ZSET } Type;
typedef struct { char *name, *text; int score; } Member;
typedef struct { char *items[100]; int count; } List;
typedef struct { Member items[100]; int count; } Collection;
typedef struct {
    char *key;
    Type type;
    int expiry;
    union { char *string; List list; Collection members; } value;
} Record;
typedef struct { Record *items[100]; int count; } Database;
typedef struct { char *name; Database *database; } Snapshot;
typedef struct { const char **items; int count, capacity; } Strings;
typedef struct { int first, last; } Range;
typedef struct { int infinity, value; bool exclusive; } Bound;

static Database *database, *stack[20];
static Snapshot snapshots[20];
static int current_time, depth, snapshot_count;
static jmp_buf command_error;
static const char *type_names[] = { "string", "list", "hash", "set", "zset" };
static const char *wrong_type = "WRONGTYPE Operation against a key holding the wrong kind of value";
static const char *not_integer = "ERR value is not an integer or out of range";
static const char *positive = "ERR value is out of range, must be positive";

static void *allocate(size_t size) {
    void *result = malloc(size);
    if (!result) exit(EXIT_FAILURE);
    return result;
}
static char *copy_string(const char *text) {
    char *result = allocate(strlen(text) + 1);
    return strcpy(result, text);
}
static void fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    fputs("(error) ", stdout);
    vprintf(format, args);
    va_end(args);
    putchar('\n');
    longjmp(command_error, 1);
}
static bool equal_case(const char *a, const char *b) {
    while (*a && *b) {
        int x = *a++, y = *b++;
        if (x >= 'a' && x <= 'z') x -= 'a' - 'A';
        if (y >= 'a' && y <= 'z') y -= 'a' - 'A';
        if (x != y) return false;
    }
    return *a == *b;
}
static bool split_line(const char *line, char *buffer, char **args, int *count) {
    int input = 0, output = 0;
    *count = 0;
    while (line[input]) {
        while (line[input] == ' ') ++input;
        if (!line[input]) break;
        args[(*count)++] = buffer + output;
        if (line[input] == '"') {
            ++input;
            while (line[input] && line[input] != '"') {
                if (line[input] == '\\') {
                    ++input;
                    if (line[input] != '\\' && line[input] != '"') return false;
                }
                buffer[output++] = line[input++];
            }
            if (line[input] != '"') return false;
            ++input;
            if (line[input] && line[input] != ' ') return false;
        } else {
            while (line[input] && line[input] != ' ') buffer[output++] = line[input++];
        }
        buffer[output++] = '\0';
    }
    return true;
}
static bool parse_integer(const char *text, int *value) {
    if (!strcmp(text, "0")) { *value = 0; return true; }
    bool negative = *text == '-';
    if (negative) ++text;
    size_t length = strlen(text);
    if (length < 1 || length > 9 || *text < '1' || *text > '9') return false;
    int result = 0;
    for (; *text; ++text) {
        if (*text < '0' || *text > '9') return false;
        result = result * 10 + *text - '0';
    }
    *value = negative ? -result : result;
    return true;
}
static int integer(const char *text) {
    int value;
    if (!parse_integer(text, &value)) fail("%s", not_integer);
    return value;
}
static int incremented(int old, int change) {
    int result = old + change;
    if (result < -999999999 || result > 999999999) fail("ERR increment or decrement would overflow");
    return result;
}
static Range normalize(int length, int start, int stop) {
    if (start < 0) start += length;
    if (stop < 0) stop += length;
    if (start < 0) start = 0;
    if (stop >= length) stop = length - 1;
    return (Range){ start, stop };
}
static Bound bound(const char *text) {
    if (!strcmp(text, "-inf")) return (Bound){ -1, 0, false };
    if (!strcmp(text, "+inf")) return (Bound){ 1, 0, false };
    bool exclusive = *text == '(';
    int value;
    if (!parse_integer(text + exclusive, &value)) fail("ERR min or max is not a float");
    return (Bound){ 0, value, exclusive };
}
static void quoted(const char *text) {
    if (!text) { fputs("(nil)", stdout); return; }
    putchar('"');
    for (; *text; ++text) {
        if (*text == '"' || *text == '\\') putchar('\\');
        putchar(*text);
    }
    putchar('"');
}
static void reply_string(const char *text) { quoted(text); putchar('\n'); }
static void reply_integer(int value) { printf("(integer) %d\n", value); }
static void append(Strings *strings, const char *text) {
    if (strings->count == strings->capacity) {
        strings->capacity = strings->capacity ? 2 * strings->capacity : 16;
        const char **items = realloc(strings->items, (size_t)strings->capacity * sizeof(*items));
        if (!items) exit(EXIT_FAILURE);
        strings->items = items;
    }
    strings->items[strings->count++] = text;
}
static void reply_array(const Strings *strings) {
    if (!strings->count) { puts("(empty array)"); return; }
    int width = 1;
    for (int n = strings->count; n >= 10; n /= 10) ++width;
    for (int i = 0; i < strings->count; ++i) {
        printf("%*d) ", width, i + 1);
        quoted(strings->items[i]);
        putchar('\n');
    }
}
static int string_order(const void *a, const void *b) {
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}
static void sort_strings(Strings *strings) {
    if (strings->count > 1) qsort(strings->items, (size_t)strings->count, sizeof(*strings->items), string_order);
}
static Record *find(const Database *db, const char *key) {
    for (int i = 0; i < db->count; ++i) if (!strcmp(db->items[i]->key, key)) return db->items[i];
    return NULL;
}
static Record *checked(const char *key, Type type) {
    Record *record = find(database, key);
    if (record && record->type != type) fail("%s", wrong_type);
    return record;
}
static Record *new_record(const char *key, Type type) {
    Record *record = allocate(sizeof(*record));
    *record = (Record){ .key = copy_string(key), .type = type, .expiry = -1 };
    if (type == STRING) record->value.string = copy_string("");
    else if (type == LIST) record->value.list = (List){0};
    else record->value.members = (Collection){0};
    return record;
}
static Record *ensure(const char *key, Type type) {
    Record *record = find(database, key);
    if (!record) database->items[database->count++] = record = new_record(key, type);
    return record;
}
static void free_record(Record *record) {
    free(record->key);
    if (record->type == STRING) free(record->value.string);
    else if (record->type == LIST) {
        for (int i = 0; i < record->value.list.count; ++i) free(record->value.list.items[i]);
    } else {
        for (int i = 0; i < record->value.members.count; ++i) {
            free(record->value.members.items[i].name);
            free(record->value.members.items[i].text);
        }
    }
    free(record);
}
static bool delete_key(Database *db, const char *key) {
    for (int i = 0; i < db->count; ++i) if (!strcmp(db->items[i]->key, key)) {
        free_record(db->items[i]);
        memmove(db->items + i, db->items + i + 1, (size_t)(--db->count - i) * sizeof(*db->items));
        return true;
    }
    return false;
}
static void replace_record(Record *record) {
    delete_key(database, record->key);
    database->items[database->count++] = record;
}
static void write_string(Record *record, const char *text) {
    char *copy = copy_string(text);
    free(record->value.string);
    record->value.string = copy;
}
static void replace_string(const char *key, const char *text, int expiry) {
    Record *record = new_record(key, STRING);
    write_string(record, text);
    record->expiry = expiry;
    replace_record(record);
}
static Record *copy_record(const Record *source) {
    Record *record = allocate(sizeof(*record));
    *record = *source;
    record->key = copy_string(source->key);
    if (source->type == STRING) record->value.string = copy_string(source->value.string);
    else if (source->type == LIST) {
        for (int i = 0; i < source->value.list.count; ++i) record->value.list.items[i] = copy_string(source->value.list.items[i]);
    } else {
        for (int i = 0; i < source->value.members.count; ++i) {
            Member *member = &record->value.members.items[i];
            member->name = copy_string(member->name);
            if (member->text) member->text = copy_string(member->text);
        }
    }
    return record;
}
static Database *copy_database(const Database *source) {
    Database *copy = allocate(sizeof(*copy));
    copy->count = source->count;
    for (int i = 0; i < source->count; ++i) copy->items[i] = copy_record(source->items[i]);
    return copy;
}
static void free_database(Database *db) {
    for (int i = 0; i < db->count; ++i) free_record(db->items[i]);
    free(db);
}
static int expire_keys(void) {
    int removed = 0;
    for (int i = database->count - 1; i >= 0; --i) {
        Record *record = database->items[i];
        if (record->expiry >= 0 && record->expiry <= current_time) {
            delete_key(database, record->key);
            ++removed;
        }
    }
    return removed;
}
static int member_index(const Collection *members, const char *name) {
    for (int i = 0; i < members->count; ++i) if (!strcmp(members->items[i].name, name)) return i;
    return -1;
}
static bool put_member(Collection *members, const char *name, const char *text, int score) {
    int index = member_index(members, name);
    bool added = index < 0;
    if (added) {
        index = members->count++;
        members->items[index] = (Member){ .name = copy_string(name) };
    }
    Member *member = &members->items[index];
    free(member->text);
    member->text = text ? copy_string(text) : NULL;
    member->score = score;
    return added;
}
static bool remove_member(Collection *members, const char *name) {
    int index = member_index(members, name);
    if (index < 0) return false;
    free(members->items[index].name);
    free(members->items[index].text);
    memmove(members->items + index, members->items + index + 1, (size_t)(--members->count - index) * sizeof(*members->items));
    return true;
}
static int member_order(const void *a, const void *b) {
    return strcmp((*(Member *const *)a)->name, (*(Member *const *)b)->name);
}
static int score_order(const void *a, const void *b) {
    const Member *x = *(Member *const *)a, *y = *(Member *const *)b;
    return x->score != y->score ? (x->score < y->score ? -1 : 1) : strcmp(x->name, y->name);
}
static int sorted_members(Record *record, Member **items, bool scores) {
    int count = record ? record->value.members.count : 0;
    for (int i = 0; i < count; ++i) items[i] = &record->value.members.items[i];
    if (count > 1) qsort(items, (size_t)count, sizeof(*items), scores ? score_order : member_order);
    return count;
}
static char *remove_element(List *list, int index) {
    char *element = list->items[index];
    memmove(list->items + index, list->items + index + 1, (size_t)(--list->count - index) * sizeof(*list->items));
    return element;
}
static void insert_element(List *list, int index, const char *element) {
    memmove(list->items + index + 1, list->items + index, (size_t)(list->count - index) * sizeof(*list->items));
    list->items[index] = copy_string(element);
    ++list->count;
}
static void remove_empty(Record *record) {
    if (record && record->type != STRING && (record->type == LIST ? record->value.list.count : record->value.members.count) == 0)
        delete_key(database, record->key);
}

typedef enum { LITERAL, ANY, STAR, CLASS } PartKind;
typedef struct { PartKind kind; char literal; bool characters[128], negated; } Part;
typedef struct { Part parts[201]; int count; } Pattern;
static Pattern parse_pattern(const char *text) {
    Pattern pattern = {0};
    for (int i = 0; text[i]; ++i) {
        Part *part = &pattern.parts[pattern.count++];
        char character = text[i];
        if (character == '\\') {
            if (!text[++i]) fail("ERR invalid pattern");
            part->literal = text[i];
        } else if (character == '*') part->kind = STAR;
        else if (character == '?') part->kind = ANY;
        else if (character == '[') {
            part->kind = CLASS;
            int end = i + 1;
            while (text[end] && text[end] != ']') ++end;
            if (!text[end]) fail("ERR invalid pattern");
            ++i;
            if (text[i] == '^') { part->negated = true; ++i; }
            if (i == end) fail("ERR invalid pattern");
            while (i < end) {
                int first = (unsigned char)text[i], last = first;
                if (i + 2 < end && text[i + 1] == '-') { last = (unsigned char)text[i + 2]; i += 3; }
                else ++i;
                int low = first < last ? first : last, high = first > last ? first : last;
                for (int c = low; c <= high; ++c) part->characters[c] = true;
            }
        } else part->literal = character;
    }
    return pattern;
}
static bool matches(const Pattern *pattern, const char *text) {
    bool previous[201] = { true }, next[201];
    int length = (int)strlen(text);
    for (int i = 0; i < pattern->count; ++i) {
        const Part *part = &pattern->parts[i];
        memset(next, 0, sizeof(next));
        if (part->kind == STAR) {
            next[0] = previous[0];
            for (int j = 1; j <= length; ++j) next[j] = previous[j] || next[j - 1];
        } else {
            for (int j = 0; j < length; ++j) {
                bool accepts = part->kind == ANY || (part->kind == LITERAL && part->literal == text[j]) ||
                    (part->kind == CLASS && part->characters[(unsigned char)text[j]] != part->negated);
                next[j + 1] = previous[j] && accepts;
            }
        }
        memcpy(previous, next, sizeof(previous));
    }
    return previous[length];
}

typedef enum {
    C_SET, C_GET, C_MSET, C_MGET, C_INCR, C_DECR, C_INCRBY, C_DECRBY, C_APPEND, C_STRLEN, C_GETRANGE,
    C_LPUSH, C_RPUSH, C_LPOP, C_RPOP, C_LRANGE, C_LLEN, C_LINDEX, C_LSET, C_LREM, C_LTRIM, C_LINSERT,
    C_HSET, C_HGET, C_HDEL, C_HGETALL, C_HLEN, C_HEXISTS, C_HKEYS, C_HVALS, C_HINCRBY,
    C_SADD, C_SREM, C_SISMEMBER, C_SMEMBERS, C_SCARD, C_SINTER, C_SUNION, C_SDIFF,
    C_SINTERSTORE, C_SUNIONSTORE, C_SDIFFSTORE,
    C_ZADD, C_ZSCORE, C_ZINCRBY, C_ZREM, C_ZCARD, C_ZRANK, C_ZRANGE, C_ZRANGEBYSCORE,
    C_DEL, C_EXISTS, C_TYPE, C_RENAME, C_RENAMENX, C_KEYS, C_EXPIRE, C_TTL, C_PERSIST, C_TICK,
    C_TIME, C_DBSIZE, C_FLUSH, C_INFO, C_BEGIN, C_COMMIT, C_ROLLBACK, C_SNAPSHOT, C_RESTORE, COMMAND_COUNT
} Command;
typedef struct { const char *name; int minimum, maximum, parity; } Format;
static const Format formats[COMMAND_COUNT] = {
    {"SET",2,100,-1}, {"GET",1,1,-1}, {"MSET",2,100,0}, {"MGET",1,100,-1},
    {"INCR",1,1,-1}, {"DECR",1,1,-1}, {"INCRBY",2,2,-1}, {"DECRBY",2,2,-1},
    {"APPEND",2,2,-1}, {"STRLEN",1,1,-1}, {"GETRANGE",3,3,-1},
    {"LPUSH",2,100,-1}, {"RPUSH",2,100,-1}, {"LPOP",1,2,-1}, {"RPOP",1,2,-1},
    {"LRANGE",3,3,-1}, {"LLEN",1,1,-1}, {"LINDEX",2,2,-1}, {"LSET",3,3,-1},
    {"LREM",3,3,-1}, {"LTRIM",3,3,-1}, {"LINSERT",4,4,-1},
    {"HSET",3,100,1}, {"HGET",2,2,-1}, {"HDEL",2,100,-1}, {"HGETALL",1,1,-1},
    {"HLEN",1,1,-1}, {"HEXISTS",2,2,-1}, {"HKEYS",1,1,-1}, {"HVALS",1,1,-1}, {"HINCRBY",3,3,-1},
    {"SADD",2,100,-1}, {"SREM",2,100,-1}, {"SISMEMBER",2,2,-1}, {"SMEMBERS",1,1,-1},
    {"SCARD",1,1,-1}, {"SINTER",1,100,-1}, {"SUNION",1,100,-1}, {"SDIFF",1,100,-1},
    {"SINTERSTORE",2,100,-1}, {"SUNIONSTORE",2,100,-1}, {"SDIFFSTORE",2,100,-1},
    {"ZADD",3,100,1}, {"ZSCORE",2,2,-1}, {"ZINCRBY",3,3,-1}, {"ZREM",2,100,-1},
    {"ZCARD",1,1,-1}, {"ZRANK",2,2,-1}, {"ZRANGE",3,4,-1}, {"ZRANGEBYSCORE",3,4,-1},
    {"DEL",1,100,-1}, {"EXISTS",1,100,-1}, {"TYPE",1,1,-1}, {"RENAME",2,2,-1},
    {"RENAMENX",2,2,-1}, {"KEYS",1,1,-1}, {"EXPIRE",2,3,-1}, {"TTL",1,1,-1},
    {"PERSIST",1,1,-1}, {"TICK",1,1,-1}, {"TIME",0,0,-1}, {"DBSIZE",0,0,-1},
    {"FLUSH",0,0,-1}, {"INFO",0,0,-1}, {"BEGIN",0,0,-1}, {"COMMIT",0,0,-1},
    {"ROLLBACK",0,0,-1}, {"SNAPSHOT",1,1,-1}, {"RESTORE",1,1,-1}
};

static void execute(Command command, int count, char **args) {
    Strings reply = {0};
    char number[16];
    switch (command) {
    case C_SET: {
        enum { NX = 1, XX = 2, EX = 4, KEEP = 8, GET = 16 };
        int options = 0, seconds = 0;
        const char *seconds_text = NULL;
        for (int i = 2; i < count; ++i) {
            int option = equal_case(args[i], "NX") ? NX : equal_case(args[i], "XX") ? XX :
                equal_case(args[i], "EX") ? EX : equal_case(args[i], "KEEPTTL") ? KEEP : equal_case(args[i], "GET") ? GET : 0;
            if (!option || (options & option)) fail("ERR syntax error");
            options |= option;
            if (option == EX) {
                if (++i == count) fail("ERR syntax error");
                seconds_text = args[i];
            }
        }
        if (((options & NX) && (options & XX)) || ((options & EX) && (options & KEEP))) fail("ERR syntax error");
        if (options & EX) {
            seconds = integer(seconds_text);
            if (seconds <= 0) fail("ERR invalid expire time in 'set' command");
        }
        Record *old = options & GET ? checked(args[0], STRING) : find(database, args[0]);
        bool change = !((options & NX) && old) && !((options & XX) && !old);
        char *previous = (options & GET) && old ? copy_string(old->value.string) : NULL;
        if (change) {
            int expiry = options & EX ? current_time + seconds : ((options & KEEP) && old ? old->expiry : -1);
            replace_string(args[0], args[1], expiry);
        }
        if (options & GET) reply_string(previous);
        else if (change) puts("OK");
        else reply_string(NULL);
        free(previous);
        break;
    }
    case C_GET: case C_STRLEN: {
        Record *record = checked(args[0], STRING);
        if (command == C_GET) reply_string(record ? record->value.string : NULL);
        else reply_integer(record ? (int)strlen(record->value.string) : 0);
        break;
    }
    case C_MSET:
        for (int i = 0; i < count; i += 2) replace_string(args[i], args[i + 1], -1);
        puts("OK");
        break;
    case C_MGET:
        for (int i = 0; i < count; ++i) {
            Record *record = find(database, args[i]);
            append(&reply, record && record->type == STRING ? record->value.string : NULL);
        }
        reply_array(&reply);
        break;
    case C_INCR: case C_DECR: case C_INCRBY: case C_DECRBY: {
        int change = command == C_INCR ? 1 : command == C_DECR ? -1 : integer(args[1]);
        if (command == C_DECRBY) change = -change;
        Record *record = checked(args[0], STRING);
        int old = record ? integer(record->value.string) : 0, result = incremented(old, change);
        snprintf(number, sizeof(number), "%d", result);
        write_string(ensure(args[0], STRING), number);
        reply_integer(result);
        break;
    }
    case C_APPEND: {
        Record *record = checked(args[0], STRING);
        size_t old_length = record ? strlen(record->value.string) : 0, added = strlen(args[1]);
        char *text = allocate(old_length + added + 1);
        if (record) memcpy(text, record->value.string, old_length);
        memcpy(text + old_length, args[1], added + 1);
        record = ensure(args[0], STRING);
        free(record->value.string);
        record->value.string = text;
        reply_integer((int)(old_length + added));
        break;
    }
    case C_GETRANGE: {
        int start = integer(args[1]), stop = integer(args[2]);
        Record *record = checked(args[0], STRING);
        const char *text = record ? record->value.string : "";
        Range range = normalize((int)strlen(text), start, stop);
        int length = range.first <= range.last ? range.last - range.first + 1 : 0;
        char result[1001];
        if (length) memcpy(result, text + range.first, (size_t)length);
        result[length] = '\0';
        reply_string(result);
        break;
    }
    case C_LPUSH: case C_RPUSH: {
        checked(args[0], LIST);
        List *list = &ensure(args[0], LIST)->value.list;
        for (int i = 1; i < count; ++i) insert_element(list, command == C_LPUSH ? 0 : list->count, args[i]);
        reply_integer(list->count);
        break;
    }
    case C_LPOP: case C_RPOP: {
        int wanted = 1;
        if (count == 2 && (!parse_integer(args[1], &wanted) || wanted < 0)) fail("%s", positive);
        Record *record = checked(args[0], LIST);
        if (!record) { reply_string(NULL); break; }
        List *list = &record->value.list;
        if (wanted > list->count) wanted = list->count;
        for (int i = 0; i < wanted; ++i) append(&reply, remove_element(list, command == C_LPOP ? 0 : list->count - 1));
        remove_empty(record);
        if (count == 1) reply_string(reply.items[0]);
        else reply_array(&reply);
        for (int i = 0; i < reply.count; ++i) free((void *)reply.items[i]);
        break;
    }
    case C_LRANGE: case C_LTRIM: {
        int start = integer(args[1]), stop = integer(args[2]);
        Record *record = checked(args[0], LIST);
        List *list = record ? &record->value.list : NULL;
        Range range = normalize(list ? list->count : 0, start, stop);
        if (command == C_LRANGE) {
            for (int i = range.first; i <= range.last; ++i) append(&reply, list->items[i]);
            reply_array(&reply);
        } else {
            if (list) {
                int kept = 0;
                for (int i = 0; i < list->count; ++i) {
                    if (i >= range.first && i <= range.last) list->items[kept++] = list->items[i];
                    else free(list->items[i]);
                }
                list->count = kept;
                remove_empty(record);
            }
            puts("OK");
        }
        break;
    }
    case C_LLEN: {
        Record *record = checked(args[0], LIST);
        reply_integer(record ? record->value.list.count : 0);
        break;
    }
    case C_LINDEX: case C_LSET: {
        int index = integer(args[1]);
        Record *record = checked(args[0], LIST);
        if (command == C_LSET && !record) fail("ERR no such key");
        int length = record ? record->value.list.count : 0;
        if (index < 0) index += length;
        bool valid = index >= 0 && index < length;
        if (command == C_LINDEX) reply_string(valid ? record->value.list.items[index] : NULL);
        else {
            if (!valid) fail("ERR index out of range");
            free(record->value.list.items[index]);
            record->value.list.items[index] = copy_string(args[2]);
            puts("OK");
        }
        break;
    }
    case C_LREM: {
        int wanted = integer(args[1]);
        Record *record = checked(args[0], LIST);
        int removed = 0;
        if (record) {
            List *list = &record->value.list;
            int limit = wanted < 0 ? -wanted : wanted;
            for (int i = wanted < 0 ? list->count - 1 : 0;
                 i >= 0 && i < list->count && (!limit || removed < limit);) {
                if (!strcmp(list->items[i], args[2])) {
                    free(remove_element(list, i));
                    ++removed;
                    if (wanted < 0) --i;
                } else i += wanted < 0 ? -1 : 1;
            }
            remove_empty(record);
        }
        reply_integer(removed);
        break;
    }
    case C_LINSERT: {
        bool before = equal_case(args[1], "BEFORE");
        if (!before && !equal_case(args[1], "AFTER")) fail("ERR syntax error");
        Record *record = checked(args[0], LIST);
        if (!record) { reply_integer(0); break; }
        List *list = &record->value.list;
        int index = 0;
        while (index < list->count && strcmp(list->items[index], args[2])) ++index;
        if (index == list->count) reply_integer(-1);
        else {
            insert_element(list, index + !before, args[3]);
            reply_integer(list->count);
        }
        break;
    }
    case C_HSET: case C_SADD: case C_ZADD: {
        int scores[100];
        if (command == C_ZADD) for (int i = 1; i < count; i += 2) scores[i] = integer(args[i]);
        Type type = command == C_HSET ? HASH : command == C_SADD ? SET : ZSET;
        checked(args[0], type);
        Collection *members = &ensure(args[0], type)->value.members;
        int added = 0;
        for (int i = 1; i < count; i += command == C_SADD ? 1 : 2) {
            const char *name = command == C_ZADD ? args[i + 1] : args[i];
            added += put_member(members, name, command == C_HSET ? args[i + 1] : NULL, command == C_ZADD ? scores[i] : 0);
        }
        reply_integer(added);
        break;
    }
    case C_HGET: case C_HEXISTS: case C_SISMEMBER: case C_ZSCORE: {
        Type type = command == C_SISMEMBER ? SET : command == C_ZSCORE ? ZSET : HASH;
        Record *record = checked(args[0], type);
        int index = record ? member_index(&record->value.members, args[1]) : -1;
        if (command == C_HEXISTS || command == C_SISMEMBER) reply_integer(index >= 0);
        else if (index < 0) reply_string(NULL);
        else if (command == C_HGET) reply_string(record->value.members.items[index].text);
        else {
            snprintf(number, sizeof(number), "%d", record->value.members.items[index].score);
            reply_string(number);
        }
        break;
    }
    case C_HDEL: case C_SREM: case C_ZREM: {
        Type type = command == C_HDEL ? HASH : command == C_SREM ? SET : ZSET;
        Record *record = checked(args[0], type);
        int removed = 0;
        if (record) {
            for (int i = 1; i < count; ++i) removed += remove_member(&record->value.members, args[i]);
            remove_empty(record);
        }
        reply_integer(removed);
        break;
    }
    case C_HGETALL: case C_HKEYS: case C_HVALS: case C_SMEMBERS: {
        Record *record = checked(args[0], command == C_SMEMBERS ? SET : HASH);
        Member *members[100];
        int length = sorted_members(record, members, false);
        for (int i = 0; i < length; ++i) {
            if (command != C_HVALS) append(&reply, members[i]->name);
            if (command == C_HVALS || command == C_HGETALL) append(&reply, members[i]->text);
        }
        reply_array(&reply);
        break;
    }
    case C_HLEN: case C_SCARD: case C_ZCARD: {
        Record *record = checked(args[0], command == C_HLEN ? HASH : command == C_SCARD ? SET : ZSET);
        reply_integer(record ? record->value.members.count : 0);
        break;
    }
    case C_HINCRBY: case C_ZINCRBY: {
        bool hash = command == C_HINCRBY;
        int change = integer(args[hash ? 2 : 1]), old = 0;
        const char *name = args[hash ? 1 : 2];
        Record *record = checked(args[0], hash ? HASH : ZSET);
        int index = record ? member_index(&record->value.members, name) : -1;
        if (index >= 0) {
            Member *member = &record->value.members.items[index];
            if (hash) {
                if (!parse_integer(member->text, &old)) fail("ERR hash value is not an integer");
            } else old = member->score;
        }
        int result = incremented(old, change);
        snprintf(number, sizeof(number), "%d", result);
        put_member(&ensure(args[0], hash ? HASH : ZSET)->value.members, name, hash ? number : NULL, hash ? 0 : result);
        if (hash) reply_integer(result);
        else reply_string(number);
        break;
    }
    case C_SINTER: case C_SUNION: case C_SDIFF:
    case C_SINTERSTORE: case C_SUNIONSTORE: case C_SDIFFSTORE: {
        bool store = command >= C_SINTERSTORE;
        int first = store ? 1 : 0;
        bool unite = command == C_SUNION || command == C_SUNIONSTORE;
        bool intersect = command == C_SINTER || command == C_SINTERSTORE;
        for (int i = first; i < count; ++i) checked(args[i], SET);
        for (int i = first; i < (unite ? count : first + 1); ++i) {
            Record *record = find(database, args[i]);
            if (!record) continue;
            for (int j = 0; j < record->value.members.count; ++j) {
                const char *name = record->value.members.items[j].name;
                bool keep = true;
                if (!unite) for (int k = first + 1; k < count; ++k) {
                    Record *other = find(database, args[k]);
                    bool present = other && member_index(&other->value.members, name) >= 0;
                    if (intersect != present) { keep = false; break; }
                }
                if (keep) append(&reply, name);
            }
        }
        sort_strings(&reply);
        int unique = 0;
        for (int i = 0; i < reply.count; ++i)
            if (!unique || strcmp(reply.items[i], reply.items[unique - 1])) reply.items[unique++] = reply.items[i];
        reply.count = unique;
        if (store) {
            if (!unique) delete_key(database, args[0]);
            else {
                Record *result = new_record(args[0], SET);
                for (int i = 0; i < unique; ++i) put_member(&result->value.members, reply.items[i], NULL, 0);
                replace_record(result);
            }
            reply_integer(unique);
        } else reply_array(&reply);
        break;
    }
    case C_ZRANK: {
        Record *record = checked(args[0], ZSET);
        Member *members[100];
        int length = sorted_members(record, members, true), rank = 0;
        while (rank < length && strcmp(members[rank]->name, args[1])) ++rank;
        if (rank == length) reply_string(NULL);
        else reply_integer(rank);
        break;
    }
    case C_ZRANGE: case C_ZRANGEBYSCORE: {
        bool scores = count == 4;
        if (scores && !equal_case(args[3], "WITHSCORES")) fail("ERR syntax error");
        int start = 0, stop = -1;
        Bound minimum = {0}, maximum = {0};
        if (command == C_ZRANGE) { start = integer(args[1]); stop = integer(args[2]); }
        else { minimum = bound(args[1]); maximum = bound(args[2]); }
        Record *record = checked(args[0], ZSET);
        Member *members[100];
        char score_text[100][16];
        int length = sorted_members(record, members, true);
        Range range = normalize(length, start, stop);
        for (int i = 0; i < length; ++i) {
            int score = members[i]->score;
            bool keep = command == C_ZRANGE ? i >= range.first && i <= range.last :
                (minimum.infinity < 0 || (!minimum.infinity && (score > minimum.value || (!minimum.exclusive && score == minimum.value)))) &&
                (maximum.infinity > 0 || (!maximum.infinity && (score < maximum.value || (!maximum.exclusive && score == maximum.value))));
            if (!keep) continue;
            append(&reply, members[i]->name);
            if (scores) {
                snprintf(score_text[i], sizeof(score_text[i]), "%d", score);
                append(&reply, score_text[i]);
            }
        }
        reply_array(&reply);
        break;
    }
    case C_DEL: case C_EXISTS: {
        int result = 0;
        for (int i = 0; i < count; ++i) result += command == C_DEL ? delete_key(database, args[i]) : find(database, args[i]) != NULL;
        reply_integer(result);
        break;
    }
    case C_TYPE: {
        Record *record = find(database, args[0]);
        puts(record ? type_names[record->type] : "none");
        break;
    }
    case C_RENAME: case C_RENAMENX: {
        Record *record = find(database, args[0]);
        if (!record) fail("ERR no such key");
        bool blocked = command == C_RENAMENX && find(database, args[1]);
        if (!blocked && strcmp(args[0], args[1])) {
            Record *moved = copy_record(record);
            free(moved->key);
            moved->key = copy_string(args[1]);
            delete_key(database, args[0]);
            replace_record(moved);
        }
        if (command == C_RENAME) puts("OK");
        else reply_integer(!blocked);
        break;
    }
    case C_KEYS: {
        Pattern pattern = parse_pattern(args[0]);
        for (int i = 0; i < database->count; ++i)
            if (matches(&pattern, database->items[i]->key)) append(&reply, database->items[i]->key);
        sort_strings(&reply);
        reply_array(&reply);
        break;
    }
    case C_EXPIRE: {
        const char *condition = count == 3 ? args[2] : NULL;
        if (condition && !equal_case(condition, "NX") && !equal_case(condition, "XX") && !equal_case(condition, "GT") && !equal_case(condition, "LT"))
            fail("ERR Unsupported option %s", condition);
        int seconds = integer(args[1]), expiry = current_time + seconds;
        Record *record = find(database, args[0]);
        bool apply = record != NULL;
        if (record && condition) {
            int old = record->expiry;
            if (equal_case(condition, "NX")) apply = old < 0;
            else if (equal_case(condition, "XX")) apply = old >= 0;
            else if (equal_case(condition, "GT")) apply = old >= 0 && expiry > old;
            else apply = old < 0 || expiry < old;
        }
        if (apply) {
            if (seconds <= 0) delete_key(database, args[0]);
            else record->expiry = expiry;
        }
        reply_integer(apply);
        break;
    }
    case C_TTL: case C_PERSIST: {
        Record *record = find(database, args[0]);
        if (command == C_TTL) reply_integer(!record ? -2 : record->expiry < 0 ? -1 : record->expiry - current_time);
        else {
            bool changed = record && record->expiry >= 0;
            if (changed) record->expiry = -1;
            reply_integer(changed);
        }
        break;
    }
    case C_TICK: {
        int ticks = integer(args[0]);
        if (ticks <= 0) fail("%s", positive);
        current_time += ticks;
        reply_integer(expire_keys());
        break;
    }
    case C_TIME: reply_integer(current_time); break;
    case C_DBSIZE: reply_integer(database->count); break;
    case C_FLUSH:
        for (int i = 0; i < database->count; ++i) free_record(database->items[i]);
        database->count = 0;
        puts("OK");
        break;
    case C_INFO: {
        int types[5] = {0}, expires = 0;
        for (int i = 0; i < database->count; ++i) {
            ++types[database->items[i]->type];
            expires += database->items[i]->expiry >= 0;
        }
        printf("keys=%d,expires=%d,string=%d,list=%d,hash=%d,set=%d,zset=%d,time=%d,depth=%d,snapshots=%d\n",
               database->count, expires, types[STRING], types[LIST], types[HASH], types[SET], types[ZSET], current_time, depth, snapshot_count);
        break;
    }
    case C_BEGIN:
        stack[depth++] = copy_database(database);
        puts("OK");
        break;
    case C_COMMIT: case C_ROLLBACK:
        if (!depth) fail("ERR no transaction");
        if (command == C_COMMIT) free_database(stack[--depth]);
        else {
            free_database(database);
            database = stack[--depth];
            expire_keys();
        }
        puts("OK");
        break;
    case C_SNAPSHOT: case C_RESTORE: {
        int index = 0;
        while (index < snapshot_count && strcmp(snapshots[index].name, args[0])) ++index;
        if (command == C_RESTORE) {
            if (index == snapshot_count) fail("ERR no such snapshot");
            Database *restored = copy_database(snapshots[index].database);
            free_database(database);
            database = restored;
            expire_keys();
        } else {
            Database *saved = copy_database(database);
            if (index == snapshot_count) {
                snapshots[index].name = copy_string(args[0]);
                ++snapshot_count;
            } else free_database(snapshots[index].database);
            snapshots[index].database = saved;
        }
        puts("OK");
        break;
    }
    case COMMAND_COUNT: break;
    }
    free(reply.items);
}

static void process_line(const char *line) {
    char buffer[202], *args[101];
    int count;
    if (!split_line(line, buffer, args, &count)) { puts("Invalid argument(s)"); return; }
    int command = 0;
    while (command < COMMAND_COUNT && !equal_case(args[0], formats[command].name)) ++command;
    if (command == COMMAND_COUNT) fail("ERR unknown command '%s'", args[0]);
    const Format *format = &formats[command];
    --count;
    if (count < format->minimum || count > format->maximum || (format->parity >= 0 && count % 2 != format->parity)) {
        char name[20];
        size_t i = 0;
        for (; format->name[i]; ++i) name[i] = (char)(format->name[i] + 'a' - 'A');
        name[i] = '\0';
        fail("ERR wrong number of arguments for '%s' command", name);
    }
    execute((Command)command, count, args + 1);
}
int main(void) {
    char line[205];
    if (!fgets(line, sizeof(line), stdin)) return 0;
    int commands = atoi(line);
    database = allocate(sizeof(*database));
    database->count = 0;
    for (int i = 0; i < commands && fgets(line, sizeof(line), stdin); ++i) {
        line[strcspn(line, "\r\n")] = '\0';
        if (setjmp(command_error) == 0) process_line(line);
    }
    free_database(database);
    for (int i = 0; i < depth; ++i) free_database(stack[i]);
    for (int i = 0; i < snapshot_count; ++i) {
        free(snapshots[i].name);
        free_database(snapshots[i].database);
    }
    return 0;
}
