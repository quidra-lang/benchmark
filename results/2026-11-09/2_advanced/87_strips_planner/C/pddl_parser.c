#include "planner.h"
void *allocate(size_t size) {
    void *data = calloc(1, size ? size : 1);
    if (!data)
        exit(EXIT_FAILURE);
    return data;
}
void *resize(void *data, size_t size) {
    void *next = realloc(data, size ? size : 1);
    if (!next)
        exit(EXIT_FAILURE);
    return next;
}
char *copy_text(const char *text) {
    size_t size = strlen(text) + 1;
    char *out = allocate(size);
    memcpy(out, text, size);
    return out;
}
char *format_text(const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (length < 0)
        exit(EXIT_FAILURE);
    char *out = allocate((size_t)length + 1);
    vsnprintf(out, (size_t)length + 1, format, args);
    va_end(args);
    return out;
}
void int_push(IntList *list, int value) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? list->capacity * 2 : 8;
        list->data = resize(list->data, (size_t)list->capacity * sizeof *list->data);
    }
    list->data[list->count++] = value;
}
bool int_has(const IntList *list, int value) {
    for (int i = 0; i < list->count; ++i)
        if (list->data[i] == value)
            return true;
    return false;
}
void int_add(IntList *list, int value) {
    if (!int_has(list, value))
        int_push(list, value);
}
IntList int_copy(const IntList *list) {
    IntList out = {0};
    if (list->count) {
        out.count = out.capacity = list->count;
        out.data = allocate((size_t)out.count * sizeof *out.data);
        memcpy(out.data, list->data, (size_t)out.count * sizeof *out.data);
    }
    return out;
}
void int_free(IntList *list) {
    free(list->data);
    *list = (IntList){0};
}
void lines_push(TextLines *lines, char *text) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? lines->capacity * 2 : 16;
        lines->data = resize(lines->data, (size_t)lines->capacity * sizeof *lines->data);
    }
    lines->data[lines->count++] = text;
}
void lines_add(TextLines *lines, const char *text) { lines_push(lines, copy_text(text)); }
void lines_append(TextLines *lines, const TextLines *from) {
    for (int i = 0; i < from->count; ++i)
        lines_add(lines, from->data[i]);
}
void lines_free(TextLines *lines) {
    for (int i = 0; i < lines->count; ++i)
        free(lines->data[i]);
    free(lines->data);
    *lines = (TextLines){0};
}
TextLines read_lines(const char *path) {
    FILE *input = fopen(path, "rb");
    if (!input)
        exit(EXIT_FAILURE);
    TextLines out = {0};
    char *line = NULL;
    size_t length = 0, capacity = 0;
    int c;
    while ((c = fgetc(input)) != EOF) {
        if (c == '\n') {
            if (!line)
                line = allocate(1);
            line[length] = 0;
            lines_push(&out, line);
            line = NULL;
            length = capacity = 0;
        } else {
            if (length + 1 >= capacity) {
                capacity = capacity ? capacity * 2 : 128;
                line = resize(line, capacity);
            }
            line[length++] = (char)c;
        }
    }
    if (ferror(input))
        exit(EXIT_FAILURE);
    if (length) {
        line[length] = 0;
        lines_push(&out, line);
    } else
        free(line);
    fclose(input);
    return out;
}
char *join_texts(const TextLines *texts, const char *separator) {
    size_t size = 1, separator_size = strlen(separator);
    for (int i = 0; i < texts->count; ++i)
        size += strlen(texts->data[i]) + (i ? separator_size : 0);
    char *out = allocate(size), *at = out;
    for (int i = 0; i < texts->count; ++i) {
        if (i) {
            memcpy(at, separator, separator_size);
            at += separator_size;
        }
        size_t length = strlen(texts->data[i]);
        memcpy(at, texts->data[i], length);
        at += length;
    }
    *at = 0;
    return out;
}
typedef struct {
    char *name;
    uint64_t hash;
} Symbol;
static Symbol *symbols;
static int symbol_count, symbol_capacity, *symbol_slots, symbol_slot_count;
static Atom *atoms;
static int atom_count, atom_capacity, *atom_slots, atom_slot_count;
static uint64_t text_hash(const char *text) {
    uint64_t hash = UINT64_C(1469598103934665603);
    for (const unsigned char *p = (const unsigned char *)text; *p; ++p) {
        hash ^= *p;
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}
static void rehash_symbols(int size) {
    free(symbol_slots);
    symbol_slots = allocate((size_t)size * sizeof *symbol_slots);
    symbol_slot_count = size;
    for (int i = 0; i < symbol_count; ++i) {
        int slot = (int)(symbols[i].hash & (uint64_t)(size - 1));
        while (symbol_slots[slot])
            slot = (slot + 1) & (size - 1);
        symbol_slots[slot] = i + 1;
    }
}
int symbol(const char *name) {
    if (!symbol_slot_count || (symbol_count + 1) * 10 > symbol_slot_count * 7)
        rehash_symbols(symbol_slot_count ? symbol_slot_count * 2 : 128);
    uint64_t hash = text_hash(name);
    int slot = (int)(hash & (uint64_t)(symbol_slot_count - 1));
    while (symbol_slots[slot]) {
        int id = symbol_slots[slot] - 1;
        if (symbols[id].hash == hash && !strcmp(symbols[id].name, name))
            return id;
        slot = (slot + 1) & (symbol_slot_count - 1);
    }
    if (symbol_count == symbol_capacity) {
        symbol_capacity = symbol_capacity ? symbol_capacity * 2 : 64;
        symbols = resize(symbols, (size_t)symbol_capacity * sizeof *symbols);
    }
    int id = symbol_count++;
    symbols[id] = (Symbol){copy_text(name), hash};
    symbol_slots[slot] = id + 1;
    return id;
}
const char *symbol_name(int id) { return symbols[id].name; }
IntList split_words(const char *text) {
    IntList out = {0};
    const char *at = text;
    while (*at) {
        while (*at == ' ' || *at == '\n')
            ++at;
        if (!*at)
            break;
        const char *start = at;
        while (*at && *at != ' ' && *at != '\n')
            ++at;
        size_t size = (size_t)(at - start);
        char *word = allocate(size + 1);
        memcpy(word, start, size);
        word[size] = 0;
        int_push(&out, symbol(word));
        free(word);
    }
    return out;
}
char *join_words(const IntList *words, const char *separator) {
    TextLines items = {0};
    for (int i = 0; i < words->count; ++i)
        lines_add(&items, symbol_name(words->data[i]));
    char *out = join_texts(&items, separator);
    lines_free(&items);
    return out;
}
static uint64_t atom_hash(int predicate, const IntList *terms) {
    uint64_t hash = (uint64_t)(unsigned)predicate + UINT64_C(1469598103934665603);
    for (int i = 0; i < terms->count; ++i) {
        hash ^= (uint64_t)(unsigned)terms->data[i] + 1;
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}
static void rehash_atoms(int size) {
    free(atom_slots);
    atom_slots = allocate((size_t)size * sizeof *atom_slots);
    atom_slot_count = size;
    for (int i = 0; i < atom_count; ++i) {
        int slot = (int)(atom_hash(atoms[i].predicate, &atoms[i].terms) & (uint64_t)(size - 1));
        while (atom_slots[slot])
            slot = (slot + 1) & (size - 1);
        atom_slots[slot] = i + 1;
    }
}
int intern_atom(int predicate, const IntList *terms) {
    if (!atom_slot_count || (atom_count + 1) * 10 > atom_slot_count * 7)
        rehash_atoms(atom_slot_count ? atom_slot_count * 2 : 256);
    int slot = (int)(atom_hash(predicate, terms) & (uint64_t)(atom_slot_count - 1));
    while (atom_slots[slot]) {
        int id = atom_slots[slot] - 1;
        const Atom *atom = &atoms[id];
        if (atom->predicate == predicate && atom->terms.count == terms->count &&
            (!terms->count ||
             !memcmp(atom->terms.data, terms->data, (size_t)terms->count * sizeof *terms->data)))
            return id;
        slot = (slot + 1) & (atom_slot_count - 1);
    }
    if (atom_count == atom_capacity) {
        atom_capacity = atom_capacity ? atom_capacity * 2 : 128;
        atoms = resize(atoms, (size_t)atom_capacity * sizeof *atoms);
    }
    int id = atom_count++;
    atoms[id] = (Atom){predicate, int_copy(terms)};
    atom_slots[slot] = id + 1;
    return id;
}
const Atom *get_atom(int id) { return &atoms[id]; }
char *atom_text(int id) {
    const Atom *atom = get_atom(id);
    char *terms = join_words(&atom->terms, " ");
    char *out =
        format_text("(%s%s%s)", symbol_name(atom->predicate), atom->terms.count ? " " : "", terms);
    free(terms);
    return out;
}
char *literal_text(Literal literal) {
    char *atom = atom_text(literal.atom);
    if (!literal.negative)
        return atom;
    char *out = format_text("(not %s)", atom);
    free(atom);
    return out;
}
void symbols_destroy(void) {
    for (int i = 0; i < symbol_count; ++i)
        free(symbols[i].name);
    for (int i = 0; i < atom_count; ++i)
        int_free(&atoms[i].terms);
    free(symbols);
    free(symbol_slots);
    free(atoms);
    free(atom_slots);
}
typedef struct Expression {
    int word;
    struct Expression **list;
    int count, capacity;
} Expression;
static Expression *read_expression(const IntList *tokens, int *at) {
    int token = tokens->data[(*at)++];
    Expression *out = allocate(sizeof *out);
    out->word = token;
    if (strcmp(symbol_name(token), "("))
        return out;
    out->word = -1;
    while (strcmp(symbol_name(tokens->data[*at]), ")")) {
        if (out->count == out->capacity) {
            out->capacity = out->capacity ? out->capacity * 2 : 8;
            out->list = resize(out->list, (size_t)out->capacity * sizeof *out->list);
        }
        out->list[out->count++] = read_expression(tokens, at);
    }
    ++*at;
    return out;
}
static void expression_free(Expression *expression) {
    for (int i = 0; i < expression->count; ++i)
        expression_free(expression->list[i]);
    free(expression->list);
    free(expression);
}
static IntList tokens_from(const char *path) {
    TextLines lines = read_lines(path);
    IntList out = {0};
    for (int i = 0; i < lines.count; ++i) {
        char *at = lines.data[i];
        while (*at && *at != ';') {
            if (*at == ' ') {
                ++at;
                continue;
            }
            char *start = at;
            size_t length;
            if (*at == '(' || *at == ')') {
                ++at;
                length = 1;
            } else {
                while (*at && *at != ';' && *at != ' ' && *at != '(' && *at != ')')
                    ++at;
                length = (size_t)(at - start);
            }
            char saved = start[length];
            start[length] = 0;
            int_push(&out, symbol(start));
            start[length] = saved;
        }
    }
    lines_free(&lines);
    return out;
}
static IntList expression_words(const Expression *expression, int first) {
    IntList out = {0};
    for (int i = first; i < expression->count; ++i)
        int_push(&out, expression->list[i]->word);
    return out;
}
static void typed_push(TypedList *list, Typed value) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? list->capacity * 2 : 8;
        list->data = resize(list->data, (size_t)list->capacity * sizeof *list->data);
    }
    list->data[list->count++] = value;
}
static TypedList typed_list(const IntList *tokens) {
    TypedList out = {0};
    IntList pending = {0};
    for (int i = 0; i < tokens->count; ++i) {
        if (!strcmp(symbol_name(tokens->data[i]), "-")) {
            int type = tokens->data[++i];
            for (int j = 0; j < pending.count; ++j)
                typed_push(&out, (Typed){pending.data[j], type});
            pending.count = 0;
        } else
            int_push(&pending, tokens->data[i]);
    }
    int object = symbol("object");
    for (int i = 0; i < pending.count; ++i)
        typed_push(&out, (Typed){pending.data[i], object});
    int_free(&pending);
    return out;
}
static int parse_atom(const Expression *expression) {
    IntList terms = expression_words(expression, 1);
    int out = intern_atom(expression->list[0]->word, &terms);
    int_free(&terms);
    return out;
}
static Literal parse_literal(const Expression *expression) {
    if (!strcmp(symbol_name(expression->list[0]->word), "not"))
        return (Literal){parse_atom(expression->list[1]), true};
    return (Literal){parse_atom(expression), false};
}
static void literal_push(LiteralList *list, Literal value) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? list->capacity * 2 : 8;
        list->data = resize(list->data, (size_t)list->capacity * sizeof *list->data);
    }
    list->data[list->count++] = value;
}
static void read_literals(const Expression *expression, LiteralList *literals, Value *cost) {
    bool conjunction = !strcmp(symbol_name(expression->list[0]->word), "and");
    int count = conjunction ? expression->count - 1 : 1;
    for (int i = 0; i < count; ++i) {
        const Expression *entry = conjunction ? expression->list[i + 1] : expression;
        if (cost && !strcmp(symbol_name(entry->list[0]->word), "increase"))
            *cost = strtoll(symbol_name(entry->list[2]->word), NULL, 10);
        else
            literal_push(literals, parse_literal(entry));
    }
}
Domain read_domain(void) {
    IntList tokens = tokens_from("input/domain.txt");
    int at = 0;
    Expression *root = read_expression(&tokens, &at);
    int_free(&tokens);
    Domain out = {0};
    out.name = root->list[1]->list[1]->word;
    int object = symbol("object");
    int_push(&out.types, object);
    for (int i = 2; i < root->count; ++i) {
        const Expression *section = root->list[i];
        const char *kind = symbol_name(section->list[0]->word);
        if (!strcmp(kind, ":types")) {
            IntList words = expression_words(section, 1);
            for (int j = 0; j < words.count; ++j)
                if (strcmp(symbol_name(words.data[j]), "-") &&
                    !int_has(&out.types, words.data[j])) {
                    int_push(&out.types, words.data[j]);
                    typed_push(&out.parents, (Typed){words.data[j], object});
                }
            TypedList declared = typed_list(&words);
            for (int j = 0; j < declared.count; ++j)
                for (int k = 0; k < out.parents.count; ++k)
                    if (declared.data[j].name == out.parents.data[k].name)
                        out.parents.data[k].type = declared.data[j].type;
            int_free(&words);
            free(declared.data);
        } else if (!strcmp(kind, ":predicates")) {
            for (int j = 1; j < section->count; ++j) {
                const Expression *entry = section->list[j];
                Predicate *predicate = &out.predicates[out.predicate_count++];
                predicate->name = entry->list[0]->word;
                IntList words = expression_words(entry, 1);
                TypedList types = typed_list(&words);
                for (int k = 0; k < types.count; ++k)
                    int_push(&predicate->types, types.data[k].type);
                int_free(&words);
                free(types.data);
            }
        } else if (!strcmp(kind, ":action")) {
            Schema *schema = &out.actions[out.action_count++];
            schema->name = section->list[1]->word;
            schema->cost = 1;
            for (int j = 2; j < section->count; j += 2) {
                const char *field = symbol_name(section->list[j]->word);
                const Expression *value = section->list[j + 1];
                if (!strcmp(field, ":parameters")) {
                    IntList words = expression_words(value, 0);
                    schema->parameters = typed_list(&words);
                    int_free(&words);
                } else if (!strcmp(field, ":precondition"))
                    read_literals(value, &schema->conditions, NULL);
                else if (!strcmp(field, ":effect"))
                    read_literals(value, &schema->effects, &schema->cost);
            }
        }
    }
    expression_free(root);
    return out;
}
Problem *read_problems(int *count) {
    IntList tokens = tokens_from("input/problems.txt");
    int at = 0;
    Problem *out = allocate(8 * sizeof *out);
    *count = 0;
    while (at < tokens.count) {
        Expression *root = read_expression(&tokens, &at);
        Problem *problem = &out[(*count)++];
        problem->name = root->list[1]->list[1]->word;
        for (int i = 2; i < root->count; ++i) {
            const Expression *section = root->list[i];
            const char *kind = symbol_name(section->list[0]->word);
            if (!strcmp(kind, ":objects")) {
                IntList words = expression_words(section, 1);
                problem->objects = typed_list(&words);
                int_free(&words);
            } else if (!strcmp(kind, ":init"))
                for (int j = 1; j < section->count; ++j)
                    int_push(&problem->initial, parse_atom(section->list[j]));
            else if (!strcmp(kind, ":goal")) {
                const Expression *value = section->list[1];
                if (!strcmp(symbol_name(value->list[0]->word), "and"))
                    for (int j = 1; j < value->count; ++j)
                        int_push(&problem->goals, parse_atom(value->list[j]));
                else
                    int_push(&problem->goals, parse_atom(value));
            }
        }
        expression_free(root);
    }
    int_free(&tokens);
    return out;
}
void domain_free(Domain *domain) {
    int_free(&domain->types);
    free(domain->parents.data);
    for (int i = 0; i < domain->predicate_count; ++i)
        int_free(&domain->predicates[i].types);
    for (int i = 0; i < domain->action_count; ++i) {
        free(domain->actions[i].parameters.data);
        free(domain->actions[i].conditions.data);
        free(domain->actions[i].effects.data);
    }
    lines_free(&domain->diagnostics);
}
void problem_free(Problem *problem) {
    free(problem->objects.data);
    int_free(&problem->initial);
    int_free(&problem->goals);
    lines_free(&problem->diagnostics);
}
