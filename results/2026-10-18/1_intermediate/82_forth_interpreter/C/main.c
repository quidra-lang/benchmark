#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;
static Allocation *permanent;

static void *allocate(size_t size) {
    void *pointer = calloc(1, size ? size : 1);
    Allocation *a = malloc(sizeof *a);
    if (!pointer || !a) exit(EXIT_FAILURE);
    *a = (Allocation){pointer, permanent};
    permanent = a;
    return pointer;
}

static void *grow(void *old, int count, int *capacity, size_t size) {
    int next = *capacity ? *capacity * 2 : 8;
    void *items = allocate((size_t)next * size);
    if (count) memcpy(items, old, (size_t)count * size);
    *capacity = next;
    return items;
}

static char *part(const char *text, size_t length) {
    char *result = allocate(length + 1);
    memcpy(result, text, length);
    return result;
}

static char upper_char(char c) {
    return c >= 'a' && c <= 'z' ? (char)(c - 'a' + 'A') : c;
}

static char *upper(const char *text) {
    char *result = part(text, strlen(text));
    for (char *p = result; *p; p++) *p = upper_char(*p);
    return result;
}

static bool equal(const char *a, const char *b) {
    return strcmp(a, b) == 0;
}

static bool listed(const char *word, const char *list) {
    size_t length = strlen(word);
    for (const char *at = list; *at;) {
        const char *end = strchr(at, ' ');
        size_t n = end ? (size_t)(end - at) : strlen(at);
        if (n == length && !memcmp(at, word, n)) return true;
        if (!end) break;
        at = end + 1;
    }
    return false;
}
static const char *COMPILE_ONLY = "IF ELSE THEN DO ?DO LOOP +LOOP LEAVE UNLOOP I J BEGIN UNTIL WHILE REPEAT AGAIN CASE OF ENDOF ENDCASE EXIT RECURSE DOES> ; >R R> R@ ABORT\" ['] {:";
static const char *INTERPRET_ONLY = ": :NONAME FORGET";
static const char *BOTH = ".\" ( \\ TO IS";
typedef struct RuntimeAllocation {
    void *pointer;
    struct RuntimeAllocation *next;
} RuntimeAllocation;
static RuntimeAllocation *runtime_allocations;

static RuntimeAllocation *runtime_allocate(size_t size) {
    RuntimeAllocation *a = malloc(sizeof *a);
    if (!a) exit(EXIT_FAILURE);
    a->pointer = calloc(1, size ? size : 1);
    if (!a->pointer) exit(EXIT_FAILURE);
    a->next = runtime_allocations;
    runtime_allocations = a;
    return a;
}

static void runtime_release(RuntimeAllocation *a) {
    runtime_allocations = a->next;
    free(a->pointer);
    free(a);
}

static void runtime_restore(RuntimeAllocation *checkpoint) {
    while (runtime_allocations != checkpoint) runtime_release(runtime_allocations);
}
typedef struct ErrorContext {
    jmp_buf jump;
    struct ErrorContext *previous;
    bool line;
} ErrorContext;
static ErrorContext *error_context;
static const char *failure_word;
static char failure_reason[201];
static long long failure_code;

static void raise_error(const char *word, long long code, bool catchable, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    vsnprintf(failure_reason, sizeof failure_reason, pattern, args);
    va_end(args);
    failure_word = word;
    failure_code = code;
    ErrorContext *context = error_context;
    while (context && !context->line && !catchable) context = context->previous;
    if (!context) exit(EXIT_FAILURE);
    error_context = context;
    longjmp(context->jump, 1);
}

static void error(const char *word, const char *reason, long long code) {
    raise_error(word, code, true, "%s", reason);
}

static void syntax_error(const char *word, const char *reason) {
    raise_error(word, 0, false, "%s", reason);
}
typedef struct Word Word;
typedef struct {
    const char *kind, *spelling, *text;
    long long value;
    int target, local, *locals, local_count;
    Word *word;
} Instruction;
typedef struct {
    Instruction *items;
    int count, capacity;
} Code;
typedef struct {
    const char *name;
    int index;
} Local;
struct Word {
    const char *name, *raw, *kind;
    long long here, value, address, deferred, xt;
    Word *does_owner, *previous;
    int does_start, dictionary_index;
    Code code;
    Local *locals;
    int local_count, local_capacity, local_bindings;
};
typedef struct Entry {
    const char *name;
    Word *latest;
    struct Entry *next;
} Entry;
#define DICTIONARY_BUCKETS 4093
static Entry *entries[DICTIONARY_BUCKETS];

static unsigned long name_hash(const char *name) {
    unsigned long hash = 5381;
    for (; *name; name++) hash = hash * 33 + (unsigned char)upper_char(*name);
    return hash;
}

static bool same_name(const char *a, const char *b) {
    while (*a && *b && upper_char(*a) == upper_char(*b)) {
        a++;
        b++;
    }
    return *a == *b;
}

static Entry *entry(const char *name, bool create) {
    size_t bucket = name_hash(name) % DICTIONARY_BUCKETS;
    for (Entry *e = entries[bucket]; e; e = e->next) if (same_name(e->name, name)) return e;
    if (!create) return NULL;
    Entry *e = allocate(sizeof *e);
    e->name = upper(name);
    e->next = entries[bucket];
    entries[bucket] = e;
    return e;
}

static Word *find(const char *name) {
    Entry *e = entry(name, false);
    return e ? e->latest : NULL;
}
typedef struct {
    Word **items;
    int count, capacity;
} Words;
static Words dictionary, execution_tokens;

static void add_word(Words *words, Word *word) {
    if (words->count == words->capacity) words->items = grow(words->items, words->count, &words->capacity, sizeof(Word *));
    words->items[words->count++] = word;
}

static Word *new_word(const char *name, const char *raw, const char *kind, long long here) {
    Word *word = allocate(sizeof *word);
    word->name = name;
    word->raw = raw;
    word->kind = kind;
    word->here = here;
    word->dictionary_index = -1;
    return word;
}

static void define_word(Word *word) {
    Entry *e = entry(word->name, true);
    word->previous = e->latest;
    word->dictionary_index = dictionary.count;
    add_word(&dictionary, word);
    e->latest = word;
}
typedef struct {
    int *items;
    int count, capacity;
} Integers;

static void add_integer(Integers *values, int value) {
    if (values->count == values->capacity) values->items = grow(values->items, values->count, &values->capacity, sizeof(int));
    values->items[values->count++] = value;
}
typedef struct {
    const char *kind;
    int index, begin;
    Integers exits;
} Control;
static Control *controls;
static int control_count, control_capacity;
static Word *compiling;
static long long data[1000], returns[1000], memory[10000];
static int data_count, return_count, memory_count = 1, definition_depth;
static const char *input_line;
static size_t position;

static char *read_word(void) {
    while (input_line[position] == ' ') position++;
    if (!input_line[position]) return NULL;
    size_t first = position;
    while (input_line[position] && input_line[position] != ' ') position++;
    return part(input_line + first, position - first);
}

static const char *read_name(const char *owner) {
    char *name = read_word();
    if (!name) error(owner, "missing name", -16);
    return name;
}

static int digit_value(char c) {
    c = upper_char(c);
    return c >= '0' && c <= '9' ? c - '0' : c >= 'A' && c <= 'Z' ? c - 'A' + 10 : 36;
}

static bool parse_number(const char *raw, long long radix, long long *value) {
    size_t length = strlen(raw);
    if (length == 3 && raw[0] == '\'' && raw[2] == '\'') {
        *value = (unsigned char)raw[1];
        return true;
    }
    const char *text = raw;
    if (*text && strchr("$#%", *text)) {
        radix = *text == '$' ? 16 : *text == '#' ? 10 : 2;
        text++;
    } else if (radix < 2 || radix > 36) return false;
    bool negative = *text == '-';
    if (negative) text++;
    if (!*text) return false;
    for (const char *p = text; *p; p++) if (digit_value(*p) >= radix) return false;
    long long result = 0;
    for (; *text; text++) result = result * radix + digit_value(*text);
    *value = negative ? -result : result;
    return true;
}

static bool number(const char *raw, long long *value) {
    size_t length = strlen(raw);
    bool direct = (length == 3 && raw[0] == '\'' && raw[2] == '\'') || (*raw && strchr("$#%", *raw));
    if (!direct && (memory[0] < 2 || memory[0] > 36)) error(raw, "invalid base", -40);
    return parse_number(raw, memory[0], value);
}

static void check_name(const char *raw) {
    const char *name = upper(raw);
    long long value;
    if (listed(name, COMPILE_ONLY) || listed(name, INTERPRET_ONLY) || listed(name, BOTH) || parse_number(raw, 10, &value)) error(raw, "invalid name", -19);
}

static void push(long long value, const char *word) {
    if (data_count == 1000) error(word, "stack overflow", -3);
    data[data_count++] = value;
}

static void pop_values(int count, const char *word, long long *values) {
    if (data_count < count) error(word, "stack underflow", -4);
    if (count) memcpy(values, data + data_count - count, (size_t)count * sizeof(long long));
    data_count -= count;
}

static long long pop(const char *word) {
    if (!data_count) error(word, "stack underflow", -4);
    return data[--data_count];
}

static void return_push(long long value, const char *word) {
    if (return_count == 1000) error(word, "return stack overflow", -5);
    returns[return_count++] = value;
}

static void need_return(int count, const char *word) {
    if (return_count < count) error(word, "return stack underflow", -6);
}

static int address(long long value, const char *word) {
    if (value < 0 || value % 8 || value / 8 >= memory_count) error(word, "invalid address", -9);
    return (int)(value / 8);
}

static long long xt(Word *word) {
    if (!word->xt) {
        add_word(&execution_tokens, word);
        word->xt = execution_tokens.count;
    }
    return word->xt;
}

static Word *token(long long value, const char *word) {
    if (value < 1 || value > execution_tokens.count) error(word, "invalid argument", -24);
    return execution_tokens.items[(int)value - 1];
}
typedef struct {
    char *text;
    size_t length, capacity, trailing;
} Pending;
static Pending pending;

static void write_char(char c) {
    if (c == ' ') {
        pending.trailing++;
        return;
    }
    size_t needed = pending.length + pending.trailing + 2;
    if (needed > pending.capacity) {
        size_t capacity = pending.capacity ? pending.capacity : 64;
        while (capacity < needed) capacity *= 2;
        char *next = realloc(pending.text, capacity);
        if (!next) exit(EXIT_FAILURE);
        pending.text = next;
        pending.capacity = capacity;
    }
    memset(pending.text + pending.length, ' ', pending.trailing);
    pending.length += pending.trailing;
    pending.trailing = 0;
    pending.text[pending.length++] = c;
    pending.text[pending.length] = '\0';
}

static void write_text(const char *text) {
    for (; *text; text++) write_char(*text);
}

static void write_spaces(long long count) {
    if (count > 0) pending.trailing += (size_t)count;
}

static void flush(void) {
    if (pending.length) fwrite(pending.text, 1, pending.length, stdout);
    putchar('\n');
    pending.length = pending.trailing = 0;
    if (pending.text) pending.text[0] = '\0';
}

static void output_number(long long value, const char *word, char text[64]) {
    long long radix = memory[0];
    if (radix < 2 || radix > 36) error(word, "invalid base", -40);
    unsigned long long magnitude = (unsigned long long)(value < 0 ? -value : value);
    int count = 0;
    do {
        int digit = (int)(magnitude % (unsigned long long)radix);
        text[count++] = (char)(digit < 10 ? '0' + digit : 'A' + digit - 10);
        magnitude /= (unsigned long long)radix;
    }
    while (magnitude);
    if (value < 0) text[count++] = '-';
    text[count] = '\0';
    for (int i = 0; i < count / 2; i++) {
        char c = text[i];
        text[i] = text[count - i - 1];
        text[count - i - 1] = c;
    }
}

static Instruction *emit(const char *kind, const char *spelling) {
    if (compiling->code.count == compiling->code.capacity) compiling->code.items = grow(compiling->code.items, compiling->code.count, &compiling->code.capacity, sizeof(Instruction));
    Instruction *instruction = &compiling->code.items[compiling->code.count++];
    *instruction = (Instruction){0};
    instruction->kind = kind;
    instruction->spelling = spelling;
    return instruction;
}

static void add_control(const char *kind, int index, int begin) {
    if (control_count == control_capacity) controls = grow(controls, control_count, &control_capacity, sizeof(Control));
    controls[control_count++] = (Control) {
        kind, index, begin, {0}
    };
}

static Control *top(const char *word, const char *kinds) {
    if (!control_count || !listed(controls[control_count - 1].kind, kinds)) syntax_error(word, "control structure mismatch");
    return &controls[control_count - 1];
}

static int local_index(const Word *word, const char *name) {
    for (int i = word->local_bindings - 1; i >= 0; i--) if (same_name(word->locals[i].name, name)) return word->locals[i].index;
    return -1;
}

static int add_local(Word *word, const char *name) {
    if (word->local_bindings == word->local_capacity) word->locals = grow(word->locals, word->local_bindings, &word->local_capacity, sizeof(Local));
    int index = word->local_count++;
    word->locals[word->local_bindings++] = (Local){upper(name), index};
    return index;
}

static void compile(const char *raw, const char *word) {
    int at = compiling->code.count;
    if (equal(word, "IF")) {
        emit("zerojump", raw);
        add_control("IF", at, 0);
    } else if (equal(word, "ELSE")) {
        Control *c = top(raw, "IF");
        emit("jump", raw);
        compiling->code.items[c->index].target = at + 1;
        c->kind = "ELSE";
        c->index = at;
    } else if (equal(word, "THEN")) {
        Control *c = top(raw, "IF ELSE");
        compiling->code.items[c->index].target = at;
        control_count--;
    } else if (equal(word, "BEGIN")) add_control("BEGIN", at, at);
    else if (equal(word, "UNTIL") || equal(word, "AGAIN")) {
        Control *c = top(raw, "BEGIN");
        emit(equal(word, "UNTIL") ? "zerojump" : "jump", raw)->target = c->begin;
        control_count--;
    } else if (equal(word, "WHILE")) {
        Control *c = top(raw, "BEGIN");
        emit("zerojump", raw);
        c->kind = "WHILE";
        c->index = at;
    } else if (equal(word, "REPEAT")) {
        Control *c = top(raw, "WHILE");
        emit("jump", raw)->target = c->begin;
        compiling->code.items[c->index].target = at + 1;
        control_count--;
    } else if (equal(word, "DO") || equal(word, "?DO")) {
        emit(word, raw);
        add_control(word, at, at + 1);
    } else if (equal(word, "LOOP") || equal(word, "+LOOP")) {
        Control *c = top(raw, "DO ?DO");
        emit(word, raw)->target = c->begin;
        compiling->code.items[c->index].target = at + 1;
        for (int i = 0; i < c->exits.count; i++) compiling->code.items[c->exits.items[i]].target = at + 1;
        control_count--;
    } else if (equal(word, "LEAVE")) {
        Control *loop = NULL;
        for (int i = control_count - 1; i >= 0; i--) if (equal(controls[i].kind, "DO") || equal(controls[i].kind, "?DO")) {
            loop = &controls[i];
            break;
        }
        if (!loop) syntax_error(raw, "control structure mismatch");
        emit("LEAVE", raw);
        add_integer(&loop->exits, at);
    } else if (equal(word, "CASE")) add_control("CASE", at, 0);
    else if (equal(word, "OF")) {
        top(raw, "CASE");
        emit("OF", raw);
        add_control("OF", at, 0);
    } else if (equal(word, "ENDOF")) {
        Control *of = top(raw, "OF");
        int index = of->index;
        control_count--;
        Control *c = top(raw, "CASE");
        emit("jump", raw);
        compiling->code.items[index].target = at + 1;
        add_integer(&c->exits, at);
    } else if (equal(word, "ENDCASE")) {
        Control *c = top(raw, "CASE");
        emit("DROP", raw);
        for (int i = 0; i < c->exits.count; i++) compiling->code.items[c->exits.items[i]].target = at + 1;
        control_count--;
    } else if (equal(word, "EXIT")) emit("EXIT", raw);
    else if (equal(word, "RECURSE")) emit("call", raw)->word = compiling;
    else if (equal(word, "DOES>")) {
        if (control_count) syntax_error(raw, "control structure mismatch");
        emit("DOES>", raw);
    } else if (listed(word, ">R R> R@ I J UNLOOP")) emit(word, raw);
    else if (equal(word, "[']")) {
        const char *name = read_name(raw);
        Word *target = find(name);
        if (!target) error(name, "undefined word", -13);
        emit("push", raw)->value = xt(target);
    } else if (equal(word, "{:")) {
        const char **names = allocate((strlen(input_line) + 1) * sizeof(char *));
        int count = 0;
        bool closed = false;
        char *name;
        while ((name = read_word())) {
            if (same_name(name, ":}")) {
                closed = true;
                break;
            }
            names[count++] = name;
        }
        if (!closed) syntax_error(raw, "unterminated locals");
        int *locals = allocate((size_t)count * sizeof(int));
        int local_count = 0;
        for (int i = 0; i < count; i++) {
            if (equal(names[i], "--")) break;
            check_name(names[i]);
            locals[local_count++] = add_local(compiling, names[i]);
        }
        Instruction *instruction = emit("locals", raw);
        instruction->locals = locals;
        instruction->local_count = local_count;
    } else if (equal(word, ";")) {
        if (control_count) {
            const char *kind = controls[control_count - 1].kind;
            if (equal(kind, "ELSE")) kind = "IF";
            if (equal(kind, "WHILE")) kind = "BEGIN";
            raise_error(raw, 0, false, "unclosed %s", kind);
        }
        Word *complete = compiling;
        compiling = NULL;
        if (equal(complete->name, ":NONAME")) push(xt(complete), raw);
        else define_word(complete);
    } else {
        int local = local_index(compiling, word);
        if (local >= 0) emit("local", raw)->local = local;
        else {
            Word *target = find(word);
            if (target) emit("call", raw)->word = target;
            else {
                long long value;
                if (!number(raw, &value)) error(raw, "undefined word", -13);
                emit("push", raw)->value = value;
            }
        }
    }
}
static void execute(Word *word, const char *spelling);

static void assign(const char *raw, bool deferred) {
    const char *name = read_name(raw);
    int local = !deferred && compiling ? local_index(compiling, name) : -1;
    if (local >= 0) {
        emit("setlocal", raw)->local = local;
        return;
    }
    Word *target = find(name);
    if (!target) error(name, "undefined word", -13);
    if (!equal(target->kind, deferred ? "defer" : "value")) syntax_error(name, deferred ? "not deferred" : "not a value");
    if (compiling) emit(deferred ? "is" : "to", raw)->word = target;
    else {
        long long value = pop(raw);
        if (deferred) {
            token(value, raw);
            target->deferred = value;
        } else memory[target->address / 8] = value;
    }
}

static void process(const char *raw) {
    const char *word = upper(raw);
    if (equal(word, "\\")) {
        position = strlen(input_line);
        return;
    }
    if (equal(word, "(")) {
        const char *end = strchr(input_line + position, ')');
        if (!end) syntax_error(raw, "unterminated comment");
        position = (size_t)(end - input_line) + 1;
        return;
    }
    if (!compiling && listed(word, COMPILE_ONLY)) syntax_error(raw, "compile only");
    if (compiling && listed(word, INTERPRET_ONLY)) syntax_error(raw, "interpret only");
    if (equal(word, ".\"") || equal(word, "ABORT\"")) {
        const char *end = input_line[position] ? strchr(input_line + position + 1, '"') : NULL;
        if (!end) syntax_error(raw, "unterminated string");
        const char *text = part(input_line + position + 1, (size_t)(end - input_line - position - 1));
        position = (size_t)(end - input_line) + 1;
        if (compiling) emit(equal(word, ".\"") ? "write" : "abortstring", raw)->text = text;
        else write_text(text);
        return;
    }
    if (equal(word, "TO") || equal(word, "IS")) {
        assign(raw, equal(word, "IS"));
        return;
    }
    if (equal(word, ":") || equal(word, ":NONAME")) {
        const char *name = equal(word, ":") ? read_name(raw) : raw;
        if (equal(word, ":")) check_name(name);
        compiling = new_word(equal(word, ":") ? upper(name) : ":NONAME", name, "colon", memory_count * 8LL);
        control_count = 0;
        return;
    }
    if (equal(word, "FORGET")) {
        const char *name = read_name(raw);
        Word *found = find(name);
        if (!found || found->dictionary_index < 0) error(name, "undefined word", -13);
        int index = found->dictionary_index;
        memory_count = (int)(found->here / 8);
        for (int i = dictionary.count - 1; i >= index; i--) {
            Word *removed = dictionary.items[i];
            entry(removed->name, false)->latest = removed->previous;
        }
        dictionary.count = index;
        return;
    }
    if (compiling) {
        compile(raw, word);
        return;
    }
    Word *target = find(word);
    if (target) execute(target, raw);
    else {
        long long value;
        if (!number(raw, &value)) error(raw, "undefined word", -13);
        push(value, raw);
    }
}

static void definition(Word *word, int start, const char *spelling) {
    if (definition_depth == 100) error(spelling, "nesting too deep", -7);
    definition_depth++;
    int return_depth = return_count;
    RuntimeAllocation *allocation = runtime_allocate((size_t)word->local_count * sizeof(long long));
    long long *locals = allocation->pointer;
    int pc = start;
    while (pc < word->code.count) {
        Instruction *instruction = &word->code.items[pc++];
        const char *raw = instruction->spelling, *kind = instruction->kind;
        if (equal(kind, "push")) push(instruction->value, raw);
        else if (equal(kind, "local")) push(locals[instruction->local], raw);
        else if (equal(kind, "setlocal")) locals[instruction->local] = pop(raw);
        else if (equal(kind, "locals")) {
            int count = instruction->local_count;
            if (data_count < count) error(raw, "stack underflow", -4);
            for (int i = 0; i < count; i++) locals[instruction->locals[i]] = data[data_count - count + i];
            data_count -= count;
        } else if (equal(kind, "call")) execute(instruction->word, raw);
        else if (equal(kind, "write")) write_text(instruction->text);
        else if (equal(kind, "abortstring")) {
            if (pop(raw)) error(raw, instruction->text, -2);
        } else if (equal(kind, "jump")) pc = instruction->target;
        else if (equal(kind, "zerojump")) {
            if (!pop(raw)) pc = instruction->target;
        } else if (equal(kind, "DO") || equal(kind, "?DO")) {
            long long values[2];
            pop_values(2, raw, values);
            if (equal(kind, "?DO") && values[0] == values[1]) pc = instruction->target;
            else {
                return_push(values[0], raw);
                return_push(values[1], raw);
            }
        } else if (equal(kind, "LOOP") || equal(kind, "+LOOP")) {
            long long step = equal(kind, "LOOP") ? 1 : pop(raw);
            need_return(2, raw);
            long long index = returns[return_count - 1], limit = returns[return_count - 2], before = index - limit, after = index + step - limit;
            if ((before < 0) != (after < 0)) return_count -= 2;
            else {
                returns[return_count - 1] = index + step;
                pc = instruction->target;
            }
        } else if (equal(kind, "LEAVE")) {
            need_return(2, raw);
            return_count -= 2;
            pc = instruction->target;
        } else if (equal(kind, "OF")) {
            long long values[2];
            pop_values(2, raw, values);
            if (values[0] != values[1]) {
                push(values[0], raw);
                pc = instruction->target;
            }
        } else if (equal(kind, "DROP")) pop(raw);
        else if (equal(kind, ">R")) return_push(pop(raw), raw);
        else if (equal(kind, "R>")) {
            need_return(1, raw);
            push(returns[--return_count], raw);
        } else if (equal(kind, "R@") || equal(kind, "I")) {
            need_return(1, raw);
            push(returns[return_count - 1], raw);
        } else if (equal(kind, "J")) {
            need_return(3, raw);
            push(returns[return_count - 3], raw);
        } else if (equal(kind, "UNLOOP")) {
            need_return(2, raw);
            return_count -= 2;
        } else if (equal(kind, "to")) memory[instruction->word->address / 8] = pop(raw);
        else if (equal(kind, "is")) {
            long long value = pop(raw);
            token(value, raw);
            instruction->word->deferred = value;
        } else if (equal(kind, "EXIT")) pc = word->code.count;
        else if (equal(kind, "DOES>")) {
            if (!dictionary.count || !equal(dictionary.items[dictionary.count - 1]->kind, "create")) error(raw, "no CREATE word", -31);
            Word *created = dictionary.items[dictionary.count - 1];
            created->does_owner = word;
            created->does_start = pc;
            pc = word->code.count;
        }
    }
    if (return_count > return_depth) return_count = return_depth;
    definition_depth--;
    runtime_release(allocation);
}

static long long floor_divide(long long a, long long b) {
    long long quotient = a / b, remainder = a % b;
    return remainder && ((remainder < 0) != (b < 0)) ? quotient - 1 : quotient;
}

static void builtin(const char *word, const char *raw) {
    if (listed(word, "+ - * / MOD /MOD MIN MAX = <> < > AND OR XOR")) {
        long long values[2];
        pop_values(2, raw, values);
        long long a = values[0], b = values[1];
        if (listed(word, "/ MOD /MOD")) {
            if (!b) error(raw, "division by zero", -10);
            long long quotient = floor_divide(a, b), remainder = a - b * quotient;
            if (!equal(word, "/")) push(remainder, raw);
            if (!equal(word, "MOD")) push(quotient, raw);
        } else {
            long long result;
            if (equal(word, "+")) result = a + b;
            else if (equal(word, "-")) result = a - b;
            else if (equal(word, "*")) result = a * b;
            else if (equal(word, "MIN")) result = a < b ? a : b;
            else if (equal(word, "MAX")) result = a > b ? a : b;
            else if (equal(word, "=")) result = a == b ? -1 : 0;
            else if (equal(word, "<>")) result = a != b ? -1 : 0;
            else if (equal(word, "<")) result = a < b ? -1 : 0;
            else if (equal(word, ">")) result = a > b ? -1 : 0;
            else if (equal(word, "AND")) result = a & b;
            else if (equal(word, "OR")) result = a | b;
            else result = a ^ b;
            push(result, raw);
        }
    } else if (equal(word, "*/") || equal(word, "*/MOD")) {
        long long values[3];
        pop_values(3, raw, values);
        if (!values[2]) error(raw, "division by zero", -10);
        long long product = values[0] * values[1], quotient = floor_divide(product, values[2]);
        if (equal(word, "*/MOD")) push(product - values[2] * quotient, raw);
        push(quotient, raw);
    } else if (listed(word, "NEGATE ABS 1+ 1- 2* 2/ 0= 0<> 0< 0> INVERT CELLS CELL+")) {
        long long a = pop(raw), result;
        if (equal(word, "NEGATE")) result = -a;
        else if (equal(word, "ABS")) result = a < 0 ? -a : a;
        else if (equal(word, "1+")) result = a + 1;
        else if (equal(word, "1-")) result = a - 1;
        else if (equal(word, "2*")) result = a * 2;
        else if (equal(word, "2/")) result = floor_divide(a, 2);
        else if (equal(word, "0=")) result = a == 0 ? -1 : 0;
        else if (equal(word, "0<>")) result = a != 0 ? -1 : 0;
        else if (equal(word, "0<")) result = a < 0 ? -1 : 0;
        else if (equal(word, "0>")) result = a > 0 ? -1 : 0;
        else if (equal(word, "INVERT")) result = ~a;
        else if (equal(word, "CELLS")) result = a * 8;
        else result = a + 8;
        push(result, raw);
    } else if (equal(word, "WITHIN")) {
        long long values[3];
        pop_values(3, raw, values);
        push(values[1] <= values[0] && values[0] < values[2] ? -1 : 0, raw);
    } else if (listed(word, "TRUE FALSE BL BASE HERE DEPTH")) push(equal(word, "TRUE") ? -1 : equal(word, "BL") ? 32 : equal(word, "HERE") ? memory_count * 8LL : equal(word, "DEPTH") ? data_count : 0, raw);
    else if (listed(word, "DUP ?DUP DROP")) {
        long long a = pop(raw);
        if (!equal(word, "DROP")) {
            push(a, raw);
            if (equal(word, "DUP") || a) push(a, raw);
        }
    } else if (listed(word, "SWAP OVER NIP TUCK 2DUP 2DROP")) {
        long long values[2];
        pop_values(2, raw, values);
        long long a = values[0], b = values[1];
        if (equal(word, "SWAP")) {
            push(b, raw);
            push(a, raw);
        } else if (equal(word, "OVER")) {
            push(a, raw);
            push(b, raw);
            push(a, raw);
        } else if (equal(word, "NIP")) push(b, raw);
        else if (equal(word, "TUCK")) {
            push(b, raw);
            push(a, raw);
            push(b, raw);
        } else if (equal(word, "2DUP")) {
            push(a, raw);
            push(b, raw);
            push(a, raw);
            push(b, raw);
        }
    } else if (equal(word, "ROT") || equal(word, "-ROT")) {
        long long values[3];
        pop_values(3, raw, values);
        const int forward[3] = {1, 2, 0}, reverse[3] = {2, 0, 1};
        const int *order = equal(word, "ROT") ? forward : reverse;
        for (int i = 0; i < 3; i++) push(values[order[i]], raw);
    } else if (equal(word, "2SWAP") || equal(word, "2OVER")) {
        long long values[4];
        pop_values(4, raw, values);
        const int swap[4] = {2, 3, 0, 1}, over[6] = {0, 1, 2, 3, 0, 1};
        const int *order = equal(word, "2SWAP") ? swap : over;
        int count = equal(word, "2SWAP") ? 4 : 6;
        for (int i = 0; i < count; i++) push(values[order[i]], raw);
    } else if (equal(word, "PICK") || equal(word, "ROLL")) {
        long long index = pop(raw);
        if (index < 0) error(raw, "invalid argument", -24);
        if (index >= data_count) error(raw, "stack underflow", -4);
        int at = data_count - 1 - (int)index;
        long long value = data[at];
        if (equal(word, "ROLL")) {
            memmove(data + at, data + at + 1, (size_t)(data_count - at - 1) * sizeof(long long));
            data_count--;
        }
        push(value, raw);
    } else if (equal(word, ".")) {
        long long value = pop(raw);
        char text[64];
        output_number(value, raw, text);
        write_text(text);
        write_char(' ');
    } else if (equal(word, ".R")) {
        long long values[2];
        pop_values(2, raw, values);
        char text[64];
        output_number(values[0], raw, text);
        long long width = values[1] - (long long)strlen(text);
        write_spaces(width);
        write_text(text);
    } else if (equal(word, ".S")) {
        char text[64];
        output_number(data_count, raw, text);
        write_char('<');
        write_text(text);
        write_text("> ");
        for (int i = 0; i < data_count; i++) {
            output_number(data[i], raw, text);
            write_text(text);
            write_char(' ');
        }
    } else if (equal(word, "?")) {
        int at = address(pop(raw), raw);
        char text[64];
        output_number(memory[at], raw, text);
        write_text(text);
        write_char(' ');
    } else if (equal(word, "CR")) flush();
    else if (equal(word, "SPACE")) write_char(' ');
    else if (equal(word, "SPACES")) write_spaces(pop(raw));
    else if (equal(word, "EMIT")) {
        long long value = pop(raw);
        if (value < 32 || value > 126) error(raw, "invalid argument", -24);
        write_char((char)value);
    } else if (equal(word, "!") || equal(word, "+!")) {
        long long values[2];
        pop_values(2, raw, values);
        int at = address(values[1], raw);
        memory[at] = equal(word, "!") ? values[0] : memory[at] + values[0];
    } else if (equal(word, "@")) {
        int at = address(pop(raw), raw);
        push(memory[at], raw);
    } else if (equal(word, ",")) {
        long long value = pop(raw);
        memory[memory_count++] = value;
    } else if (equal(word, "ALLOT")) {
        long long count = pop(raw);
        if (count < 0 || count % 8) error(raw, "invalid argument", -24);
        for (long long i = 0; i < count / 8; i++) memory[memory_count++] = 0;
    } else if (equal(word, "HEX") || equal(word, "DECIMAL")) memory[0] = equal(word, "HEX") ? 16 : 10;
    else if (listed(word, "CREATE VARIABLE CONSTANT VALUE DEFER")) {
        const char *name = read_name(raw);
        check_name(name);
        long long value = equal(word, "CONSTANT") || equal(word, "VALUE") ? pop(raw) : 0;
        const char *kind = equal(word, "CREATE") ? "create" : equal(word, "VARIABLE") ? "variable" : equal(word, "CONSTANT") ? "constant" : equal(word, "VALUE") ? "value" : "defer";
        Word *created = new_word(upper(name), name, kind, memory_count * 8LL);
        created->address = created->here;
        created->value = value;
        define_word(created);
        if (equal(word, "VARIABLE") || equal(word, "VALUE")) memory[memory_count++] = value;
    } else if (equal(word, "'")) {
        const char *name = read_name(raw);
        Word *target = find(name);
        if (!target) error(name, "undefined word", -13);
        push(xt(target), raw);
    } else if (equal(word, "EXECUTE")) {
        Word *target = token(pop(raw), raw);
        execute(target, target->name);
    } else if (equal(word, "CATCH")) {
        Word *target = token(pop(raw), raw);
        int saved_count = data_count, saved_return = return_count, saved_depth = definition_depth;
        RuntimeAllocation *saved = runtime_allocate((size_t)saved_count * sizeof(long long));
        if (saved_count) memcpy(saved->pointer, data, (size_t)saved_count * sizeof(long long));
        ErrorContext context;
        context.previous = error_context;
        context.line = false;
        error_context = &context;
        long long code = 0;
        if (setjmp(context.jump) == 0) execute(target, target->name);
        else {
            runtime_restore(saved);
            data_count = saved_count;
            if (saved_count) memcpy(data, saved->pointer, (size_t)saved_count * sizeof(long long));
            if (return_count > saved_return) return_count = saved_return;
            definition_depth = saved_depth;
            code = failure_code;
        }
        error_context = context.previous;
        runtime_release(saved);
        push(code, raw);
    } else if (equal(word, "THROW")) {
        long long code = pop(raw);
        if (code) raise_error(raw, code, true, "exception %lld", code);
    } else if (equal(word, "ABORT")) error(raw, "aborted", -1);
    else if (equal(word, "WORDS")) {
        for (int i = dictionary.count - 1; i >= 0; i--) {
            write_text(dictionary.items[i]->name);
            write_char(' ');
        }
    }
}

static void execute(Word *word, const char *spelling) {
    while (equal(word->kind, "defer")) {
        if (!word->deferred) error(spelling, "deferred word not set", -21);
        word = token(word->deferred, spelling);
        spelling = word->name;
    }
    if (equal(word->kind, "builtin")) builtin(word->name, spelling);
    else if (equal(word->kind, "colon")) definition(word, 0, spelling);
    else if (equal(word->kind, "constant")) push(word->value, spelling);
    else if (equal(word->kind, "value")) push(memory[word->address / 8], spelling);
    else if (equal(word->kind, "create") || equal(word->kind, "variable")) {
        push(word->address, spelling);
        if (word->does_owner) definition(word->does_owner, word->does_start, spelling);
    }
}

static char *read_line(void) {
    size_t length = 0, capacity = 128;
    char *line = malloc(capacity);
    if (!line) exit(EXIT_FAILURE);
    int c;
    while ((c = getchar()) != EOF && c != '\n') {
        if (length + 1 == capacity) {
            capacity *= 2;
            char *next = realloc(line, capacity);
            if (!next) exit(EXIT_FAILURE);
            line = next;
        }
        line[length++] = (char)c;
    }
    if (c == EOF && !length) {
        free(line);
        return NULL;
    }
    line[length] = '\0';
    return line;
}

static void input(const char *text) {
    input_line = text;
    position = 0;
    ErrorContext context;
    context.previous = error_context;
    context.line = true;
    error_context = &context;
    if (setjmp(context.jump) == 0) {
        char *raw;
        while ((raw = read_word())) process(raw);
    } else {
        if (pending.length || pending.trailing) flush();
        printf("ERROR %s: %s\n", failure_word, failure_reason);
        data_count = return_count = definition_depth = 0;
        compiling = NULL;
        control_count = 0;
        runtime_restore(NULL);
    }
    error_context = context.previous;
    if (pending.length || pending.trailing) flush();
}
int main(void) {
    memory[0] = 10;
    const char *names = "+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS";
    for (const char *at = names; *at;) {
        const char *end = strchr(at, ' ');
        size_t length = end ? (size_t)(end - at) : strlen(at);
        const char *name = part(at, length);
        Word *word = new_word(name, name, "builtin", 0);
        entry(name, true)->latest = word;
        if (!end) break;
        at = end + 1;
    }
    char *line;
    while ((line = read_line())) {
        if (equal(line, "BYE")) {
            free(line);
            break;
        }
        input(line);
        free(line);
    }
    if (compiling) printf("ERROR %s: unterminated definition\n", compiling->raw);
    runtime_restore(NULL);
    free(pending.text);
    while (permanent) {
        Allocation *next = permanent->next;
        free(permanent->pointer);
        free(permanent);
        permanent = next;
    }
    return 0;
}
