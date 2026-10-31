#include <ctype.h>
#include <inttypes.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Machine Machine;

typedef struct {
    char type;
    int64_t number;
    char *text;
} Value;

typedef struct {
    int *items;
    int count;
    int capacity;
} IntVec;

typedef struct {
    Value *items;
    int count;
    int capacity;
} ValueVec;

typedef struct {
    int kind;
    int expr;
} PrintItem;

typedef struct {
    PrintItem *items;
    int count;
    int capacity;
} PrintVec;

typedef struct {
    char kind;
    char text[256];
    Value value;
} Token;

typedef struct {
    int kind;
    char type;
    char name[32];
    Value value;
    IntVec args;
} Expression;

typedef struct {
    int number;
    IntVec body;
} Clause;

typedef struct {
    char kind[16];
    int line;
    int next;
    int expr;
    int target;
    IntVec targets;
    IntVec expressions;
    ValueVec values;
    IntVec numbers;
    Clause clauses[2];
    int clause_count;
    PrintVec items;
    char name[8];
    char mode[12];
} Statement;

typedef struct {
    int dims;
    int bounds[2];
    int count;
    Value *values;
} BasicArray;

typedef struct {
    char name[8];
    int index;
} Address;

typedef struct {
    int kind;
    int position;
    char name[8];
    int limit;
    int step;
} Frame;

struct Machine {
    Expression *expressions;
    int expression_count;
    int expression_capacity;
    Statement *statements;
    int statement_count;
    int statement_capacity;
    Token tokens[256];
    int token_count;
    int position;
    IntVec sequence;
    int entries[10000];
    Value vars[572];
    char present[572];
    BasicArray *arrays[572];
    Frame stack[100];
    int stack_count;
    ValueVec data;
    IntVec data_lines;
    int data_position;
    char *inputs[200];
    int input_count;
    int input_position;
    int64_t random_state;
    int handler;
    int handling;
    int remembered;
    int err;
    int erl;
    char buffer[2048];
    int buffer_length;
    void **allocations;
    int allocation_count;
    int allocation_capacity;
    char failure[128];
    jmp_buf jump;
};

void *allocate(Machine *m, size_t size) {
    void *memory = calloc(1, size ? size : 1);
    if (!memory) {
        fputs("out of memory\n", stderr);
        exit(1);
    }
    if (m->allocation_count == m->allocation_capacity) {
        m->allocation_capacity = m->allocation_capacity ? m->allocation_capacity * 2 : 64;
        m->allocations = realloc(m->allocations,
                                  (size_t)m->allocation_capacity * sizeof(void *));
        if (!m->allocations) exit(1);
    }
    m->allocations[m->allocation_count++] = memory;
    return memory;
}

char *copy(Machine *m, const char *text) {
    size_t size = strlen(text) + 1;
    char *result = allocate(m, size);
    memcpy(result, text, size);
    return result;
}

void int_push(IntVec *items, int number) {
    if (items->count == items->capacity) {
        items->capacity = items->capacity ? items->capacity * 2 : 4;
        items->items = realloc(items->items, sizeof(int) * (size_t)items->capacity);
        if (!items->items) exit(1);
    }
    items->items[items->count++] = number;
}

void value_push(ValueVec *items, Value value) {
    if (items->count == items->capacity) {
        items->capacity = items->capacity ? items->capacity * 2 : 4;
        items->items = realloc(items->items, sizeof(Value) * (size_t)items->capacity);
        if (!items->items) exit(1);
    }
    items->items[items->count++] = value;
}

void print_push(PrintVec *items, PrintItem item) {
    if (items->count == items->capacity) {
        items->capacity = items->capacity ? items->capacity * 2 : 4;
        items->items = realloc(items->items, sizeof(PrintItem) * (size_t)items->capacity);
        if (!items->items) exit(1);
    }
    items->items[items->count++] = item;
}

Value integer_value(int64_t n) {
    return (Value){.type = 'I', .number = n, .text = NULL};
}

Value text_value(char *text) {
    return (Value){.type = 'S', .number = 0, .text = text};
}

int is_variable(const char *name) {
    size_t size = strlen(name);
    if (size < 1 || size > 3 || name[0] < 'A' || name[0] > 'Z') return 0;
    if (size == 1) return 1;
    if (size == 2) return (name[1] >= '0' && name[1] <= '9') || name[1] == '$';
    return name[1] >= '0' && name[1] <= '9' && name[2] == '$';
}

int variable_index(const char *name) {
    int column = name[0] - 'A';
    int digit = name[1] >= '0' && name[1] <= '9' ? name[1] - '0' + 1 : 0;
    int string = name[strlen(name) - 1] == '$';
    return (column * 11 + digit) * 2 + string;
}

char name_type(const char *name) {
    return name[strlen(name) - 1] == '$' ? 'S' : 'I';
}

Value zero_value(Machine *m, const char *name) {
    return name_type(name) == 'S' ? text_value(copy(m, "")) : integer_value(0);
}

void fail(Machine *m, const char *reason) {
    snprintf(m->failure, sizeof(m->failure), "%s", reason);
    longjmp(m->jump, 1);
}

void syntax(Machine *m) {
    fail(m, "SYNTAX ERROR");
}

int checked(Machine *m, int64_t number) {
    if (number < -32768 || number > 32767) fail(m, "OVERFLOW");
    return (int)number;
}

int find_function(const char *name) {
    const char *names[] = {
        "ABS", "SGN", "INT", "SQR", "RND", "LEN", "ASC", "VAL",
        "CHR$", "STR$", "LEFT$", "RIGHT$", "MID$", "INSTR"
    };
    for (int i = 0; i < 14; ++i)
        if (strcmp(name, names[i]) == 0) return i;
    return -1;
}

int signature(int function, const char *types) {
    if (function <= 4 || function == 8 || function == 9)
        return strcmp(types, "I") == 0;
    if (function == 5 || function == 6 || function == 7)
        return strcmp(types, "S") == 0;
    if (function == 10 || function == 11)
        return strcmp(types, "SI") == 0;
    if (function == 12)
        return strcmp(types, "SI") == 0 || strcmp(types, "SII") == 0;
    return function == 13 && strcmp(types, "SS") == 0;
}

int token_digit(char c) {
    return c >= '0' && c <= '9';
}

int token_upper(char c) {
    return c >= 'A' && c <= 'Z';
}

void tokenize(Machine *m, const char *source) {
    int pos = 0;
    m->token_count = 0;
    m->position = 0;
    while (source[pos]) {
        char c = source[pos];
        if (c == ' ') {
            ++pos;
            continue;
        }
        Token token = {0};
        int start = pos;
        if (c == '"') {
            ++pos;
            while (source[pos] && source[pos] != '"') ++pos;
            if (!source[pos]) syntax(m);
            token.kind = 'S';
            int width = pos - start + 1;
            memcpy(token.text, source + start, (size_t)width);
            char temp[256] = {0};
            memcpy(temp, source + start + 1, (size_t)(width - 2));
            token.value = text_value(copy(m, temp));
            ++pos;
        } else if (token_digit(c)) {
            while (token_digit(source[pos])) ++pos;
            token.kind = 'I';
            memcpy(token.text, source + start, (size_t)(pos - start));
            int64_t n = 0;
            for (int i = start; i < pos; ++i) {
                n = n * 10 + source[i] - '0';
                if (n > 32767) syntax(m);
            }
            token.value = integer_value(n);
        } else if (token_upper(c)) {
            if (strncmp(source + pos, "REM", 3) == 0) {
                strcpy(token.text, "REM");
                token.kind = 'W';
                token.value = text_value(copy(m, "REM"));
                m->tokens[m->token_count++] = token;
                break;
            }
            while (token_upper(source[pos]) || token_digit(source[pos])) ++pos;
            if (source[pos] == '$') ++pos;
            token.kind = 'W';
            memcpy(token.text, source + start, (size_t)(pos - start));
            token.value = text_value(copy(m, token.text));
        } else {
            if (!strchr("+-*/^=<>() ,;:", c)) syntax(m);
            token.kind = 'P';
            token.text[0] = c;
            ++pos;
            if ((c == '<' || c == '>') && source[pos] &&
                ((c == '<' && source[pos] == '>') || source[pos] == '=')) {
                token.text[1] = source[pos++];
            }
            token.value = text_value(copy(m, token.text));
        }
        m->tokens[m->token_count++] = token;
        if (m->token_count >= 255) syntax(m);
    }
    Token end = {0};
    end.kind = 'E';
    m->tokens[m->token_count++] = end;
}

Token *peek(Machine *m) {
    return &m->tokens[m->position];
}

int at(Machine *m, const char *word) {
    Token *token = peek(m);
    return (token->kind == 'W' || token->kind == 'P') &&
           strcmp(token->text, word) == 0;
}

int take(Machine *m, const char *word) {
    if (!at(m, word)) return 0;
    ++m->position;
    return 1;
}

void expect(Machine *m, const char *word) {
    if (!take(m, word)) syntax(m);
}

int number_token(Machine *m) {
    if (peek(m)->kind != 'I') syntax(m);
    return (int)m->tokens[m->position++].value.number;
}

int add_expression(Machine *m, Expression expression) {
    if (m->expression_count == m->expression_capacity) {
        m->expression_capacity = m->expression_capacity ? m->expression_capacity * 2 : 64;
        m->expressions = realloc(m->expressions,
            sizeof(Expression) * (size_t)m->expression_capacity);
        if (!m->expressions) exit(1);
    }
    int id = m->expression_count++;
    m->expressions[id] = expression;
    return id;
}

int add_statement(Machine *m, Statement statement) {
    if (m->statement_count == m->statement_capacity) {
        m->statement_capacity = m->statement_capacity ? m->statement_capacity * 2 : 64;
        m->statements = realloc(m->statements,
            sizeof(Statement) * (size_t)m->statement_capacity);
        if (!m->statements) exit(1);
    }
    int id = m->statement_count++;
    m->statements[id] = statement;
    return id;
}

int expression_node(Machine *m, const char *kind, char type, const char *name,
                    IntVec args) {
    Expression result = {0};
    result.kind = strcmp(kind, "constant") == 0 ? 0 :
                  strcmp(kind, "variable") == 0 ? 1 :
                  strcmp(kind, "array") == 0 ? 2 :
                  strcmp(kind, "builtin") == 0 ? 3 :
                  strcmp(kind, "unary") == 0 ? 4 :
                  strcmp(kind, "call") == 0 ? 5 : 6;
    result.type = type;
    strncpy(result.name, name, sizeof(result.name) - 1);
    result.args = args;
    return add_expression(m, result);
}

int constant(Machine *m, Value value) {
    Expression expr = {0};
    expr.kind = 0;
    expr.type = value.type;
    expr.value = value;
    return add_expression(m, expr);
}

int unary(Machine *m, const char *word, int arg) {
    IntVec args = {0};
    int_push(&args, arg);
    return expression_node(m, "unary", 'I', word, args);
}

int binary(Machine *m, char type, const char *op, int left, int right) {
    IntVec args = {0};
    int_push(&args, left);
    int_push(&args, right);
    return expression_node(m, "binary", type, op, args);
}

int parse_expression(Machine *m, int level);

int integer(Machine *m, int level) {
    int result = parse_expression(m, level);
    if (m->expressions[result].type != 'I') syntax(m);
    return result;
}

int target(Machine *m) {
    Token token = *peek(m);
    if (token.kind != 'W' || !is_variable(token.text)) syntax(m);
    ++m->position;
    IntVec args = {0};
    int array = take(m, "(");
    if (array) {
        int_push(&args, integer(m, 0));
        if (take(m, ",")) int_push(&args, integer(m, 0));
        expect(m, ")");
    }
    return expression_node(m, array ? "array" : "variable",
                           name_type(token.text), token.text, args);
}

int primary(Machine *m) {
    Token token = *peek(m);
    if (token.kind == 'I' || token.kind == 'S') {
        ++m->position;
        return constant(m, token.value);
    }
    if (take(m, "(")) {
        int result = parse_expression(m, 0);
        expect(m, ")");
        return result;
    }
    if (token.kind == 'W' && is_variable(token.text)) return target(m);
    if (take(m, "ERR")) return expression_node(m, "builtin", 'I', "ERR", (IntVec){0});
    if (take(m, "ERL")) return expression_node(m, "builtin", 'I', "ERL", (IntVec){0});
    int function = token.kind == 'W' ? find_function(token.text) : -1;
    if (function >= 0) {
        ++m->position;
        expect(m, "(");
        IntVec args = {0};
        int_push(&args, parse_expression(m, 0));
        while (take(m, ",")) int_push(&args, parse_expression(m, 0));
        expect(m, ")");
        char types[32] = {0};
        if (args.count >= 31) syntax(m);
        for (int i = 0; i < args.count; ++i)
            types[i] = m->expressions[args.items[i]].type;
        if (!signature(function, types)) syntax(m);
        return expression_node(m, "call", name_type(token.text), token.text, args);
    }
    syntax(m);
    return -1;
}

int is_operator(int level, const char *op) {
    if (level == 0) return strcmp(op, "OR") == 0;
    if (level == 1) return strcmp(op, "AND") == 0;
    if (level == 3) return strcmp(op, "=") == 0 || strcmp(op, "<>") == 0 ||
        strcmp(op, "<") == 0 || strcmp(op, ">") == 0 ||
        strcmp(op, "<=") == 0 || strcmp(op, ">=") == 0;
    if (level == 4) return strcmp(op, "+") == 0 || strcmp(op, "-") == 0;
    if (level == 5) return strcmp(op, "*") == 0 || strcmp(op, "/") == 0 ||
        strcmp(op, "MOD") == 0;
    return level == 7 && strcmp(op, "^") == 0;
}

int parse_expression(Machine *m, int level) {
    if (level == 2 && take(m, "NOT")) return unary(m, "NOT", integer(m, 2));
    if (level == 6 && take(m, "-")) return unary(m, "-", integer(m, 6));
    if (level == 8) return primary(m);
    int left = parse_expression(m, level + 1);
    while (is_operator(level, peek(m)->text)) {
        char op[16];
        strcpy(op, peek(m)->text);
        ++m->position;
        int right = parse_expression(m, level == 7 ? 6 : level + 1);
        char type = m->expressions[left].type;
        if (type != m->expressions[right].type ||
            (type == 'S' && level != 3 && strcmp(op, "+") != 0)) syntax(m);
        left = binary(m, level == 3 ? 'I' : type, op, left, right);
        if (level == 7) break;
    }
    return left;
}

Statement new_statement(const char *kind) {
    Statement s = {0};
    strncpy(s.kind, kind, sizeof(s.kind) - 1);
    s.next = -1;
    s.expr = -1;
    s.target = -1;
    s.clauses[0].number = s.clauses[1].number = -1;
    return s;
}

IntVec parse_list(Machine *m, int in_clause);
int parse_statement(Machine *m, int in_clause);

Clause parse_clause(Machine *m) {
    Clause result = {0};
    result.number = -1;
    if (peek(m)->kind == 'I') result.number = number_token(m);
    else result.body = parse_list(m, 1);
    return result;
}

int parse_statement(Machine *m, int in_clause) {
    char word[256];
    strcpy(word, peek(m)->text);
    if (in_clause && (strcmp(word, "IF") == 0 || strcmp(word, "FOR") == 0 ||
        strcmp(word, "NEXT") == 0 || strcmp(word, "WHILE") == 0 ||
        strcmp(word, "WEND") == 0 || strcmp(word, "DATA") == 0)) syntax(m);
    Statement s = new_statement(word);
    if (take(m, "REM") || take(m, "RETURN") || take(m, "WEND") ||
        take(m, "END") || take(m, "STOP")) return add_statement(m, s);
    if (take(m, "PRINT")) {
        int last = 0;
        while (peek(m)->kind != 'E' && !at(m, ":") && !at(m, "ELSE")) {
            if (take(m, ";")) {
                print_push(&s.items, (PrintItem){.kind = 1, .expr = -1});
                last = 0;
            } else if (take(m, ",")) {
                print_push(&s.items, (PrintItem){.kind = 2, .expr = -1});
                last = 0;
            } else {
                int mode = at(m, "TAB") ? 3 : at(m, "SPC") ? 4 : 0;
                if (!mode && last) syntax(m);
                int expr;
                if (!mode) expr = parse_expression(m, 0);
                else {
                    ++m->position;
                    expect(m, "(");
                    expr = integer(m, 0);
                    expect(m, ")");
                }
                print_push(&s.items, (PrintItem){.kind = mode, .expr = expr});
                last = !mode;
            }
        }
        return add_statement(m, s);
    }
    if (take(m, "INPUT") || take(m, "READ") || take(m, "DIM")) {
        do {
            int t = target(m);
            if (strcmp(word, "DIM") == 0 && m->expressions[t].kind != 2) syntax(m);
            int_push(&s.targets, t);
        } while (take(m, ","));
        return add_statement(m, s);
    }
    if (take(m, "DATA")) {
        do {
            int negative = take(m, "-");
            Token token = *peek(m);
            if (token.kind != 'I' && (token.kind != 'S' || negative)) syntax(m);
            ++m->position;
            value_push(&s.values, negative ?
                integer_value(-token.value.number) : token.value);
        } while (take(m, ","));
        return add_statement(m, s);
    }
    if (take(m, "IF")) {
        s.expr = integer(m, 0);
        expect(m, "THEN");
        s.clauses[s.clause_count++] = parse_clause(m);
        if (take(m, "ELSE")) s.clauses[s.clause_count++] = parse_clause(m);
        if (peek(m)->kind != 'E') syntax(m);
        return add_statement(m, s);
    }
    if (take(m, "GOTO") || take(m, "GOSUB")) {
        int_push(&s.numbers, number_token(m));
        return add_statement(m, s);
    }
    if (take(m, "ON")) {
        if (take(m, "ERROR")) {
            strcpy(s.kind, "handler");
            expect(m, "GOTO");
            int_push(&s.numbers, number_token(m));
        } else {
            s.expr = integer(m, 0);
            if (take(m, "GOTO")) strcpy(s.mode, "GOTO");
            else {
                expect(m, "GOSUB");
                strcpy(s.mode, "GOSUB");
            }
            do {
                int_push(&s.numbers, number_token(m));
            } while (take(m, ","));
        }
        return add_statement(m, s);
    }
    if (take(m, "RESUME")) {
        if (take(m, "NEXT")) strcpy(s.mode, "NEXT");
        else if (peek(m)->kind == 'I') {
            strcpy(s.mode, "line");
            int_push(&s.numbers, number_token(m));
        }
        return add_statement(m, s);
    }
    if (take(m, "FOR")) {
        Token token = *peek(m);
        if (token.kind != 'W' || !is_variable(token.text) ||
            name_type(token.text) != 'I') syntax(m);
        strcpy(s.name, token.text);
        ++m->position;
        expect(m, "=");
        int_push(&s.expressions, integer(m, 0));
        expect(m, "TO");
        int_push(&s.expressions, integer(m, 0));
        int_push(&s.expressions, take(m, "STEP") ?
                 integer(m, 0) : constant(m, integer_value(1)));
        return add_statement(m, s);
    }
    if (take(m, "NEXT")) {
        if (peek(m)->kind == 'W' && is_variable(peek(m)->text) &&
            name_type(peek(m)->text) == 'I') {
            strcpy(s.name, peek(m)->text);
            ++m->position;
        }
        return add_statement(m, s);
    }
    if (take(m, "WHILE") || take(m, "RANDOMIZE")) {
        s.expr = integer(m, 0);
        return add_statement(m, s);
    }
    if (take(m, "RESTORE")) {
        if (peek(m)->kind == 'I') int_push(&s.numbers, number_token(m));
        return add_statement(m, s);
    }
    take(m, "LET");
    strcpy(s.kind, "assign");
    s.target = target(m);
    expect(m, "=");
    s.expr = parse_expression(m, 0);
    if (m->expressions[s.target].type != m->expressions[s.expr].type) syntax(m);
    return add_statement(m, s);
}

IntVec parse_list(Machine *m, int in_clause) {
    IntVec body = {0};
    int_push(&body, parse_statement(m, in_clause));
    while (take(m, ":")) int_push(&body, parse_statement(m, in_clause));
    return body;
}

IntVec parse(Machine *m, const char *text) {
    tokenize(m, text);
    IntVec body = parse_list(m, 0);
    if (peek(m)->kind != 'E') syntax(m);
    return body;
}

void connect(Machine *m, IntVec body, int after, int line) {
    int next = after;
    for (int i = body.count - 1; i >= 0; --i) {
        int id = body.items[i];
        Statement *s = &m->statements[id];
        s->line = line;
        s->next = next;
        for (int j = 0; j < s->clause_count; ++j)
            connect(m, s->clauses[j].body, next, line);
        next = id;
    }
}

void end_line(Machine *m) {
    while (m->buffer_length > 0 && m->buffer[m->buffer_length - 1] == ' ')
        --m->buffer_length;
    m->buffer[m->buffer_length] = 0;
    puts(m->buffer);
    m->buffer[0] = 0;
    m->buffer_length = 0;
}

void message(Machine *m, const char *text) {
    if (m->buffer_length) end_line(m);
    puts(text);
}

void append(Machine *m, const char *text) {
    size_t length = strlen(text);
    if (m->buffer_length + length >= sizeof(m->buffer)) exit(1);
    memcpy(m->buffer + m->buffer_length, text, length);
    m->buffer_length += (int)length;
    m->buffer[m->buffer_length] = 0;
}

void append_spaces(Machine *m, int n) {
    while (n-- > 0) append(m, " ");
}

Value get(Machine *m, const char *name) {
    int index = variable_index(name);
    return m->present[index] ? m->vars[index] : zero_value(m, name);
}

void declare(Machine *m, const char *name, const int *bounds, int dimensions) {
    int index = variable_index(name);
    BasicArray *array = allocate(m, sizeof(BasicArray));
    array->dims = dimensions;
    array->count = 1;
    for (int i = 0; i < dimensions; ++i) {
        array->bounds[i] = bounds[i];
        array->count *= bounds[i] + 1;
    }
    array->values = allocate(m, (size_t)array->count * sizeof(Value));
    Value initial = zero_value(m, name);
    for (int i = 0; i < array->count; ++i) array->values[i] = initial;
    m->arrays[index] = array;
}

Value evaluate(Machine *m, int id);

Address address(Machine *m, int expr_id) {
    Expression expr = m->expressions[expr_id];
    Address loc = {0};
    strcpy(loc.name, expr.name);
    loc.index = -1;
    if (expr.kind == 1) return loc;
    int bounds[2] = {0};
    for (int i = 0; i < expr.args.count; ++i)
        bounds[i] = (int)evaluate(m, expr.args.items[i]).number;
    int slot = variable_index(loc.name);
    if (!m->arrays[slot]) {
        int defaults[2] = {10, 10};
        declare(m, loc.name, defaults, expr.args.count);
    }
    BasicArray *array = m->arrays[slot];
    if (expr.args.count != array->dims) fail(m, "SUBSCRIPT OUT OF RANGE");
    int offset = 0;
    for (int i = 0; i < expr.args.count; ++i) {
        if (bounds[i] < 0 || bounds[i] > array->bounds[i])
            fail(m, "SUBSCRIPT OUT OF RANGE");
        offset = offset * (array->bounds[i] + 1) + bounds[i];
    }
    loc.index = offset;
    return loc;
}

Value load(Machine *m, Address address) {
    return address.index < 0 ? get(m, address.name) :
        m->arrays[variable_index(address.name)]->values[address.index];
}

void store(Machine *m, Address address, Value value) {
    int slot = variable_index(address.name);
    if (address.index < 0) {
        m->vars[slot] = value;
        m->present[slot] = 1;
    } else {
        m->arrays[slot]->values[address.index] = value;
    }
}

int64_t integer_power(Machine *m, int64_t base, int64_t exponent) {
    if (exponent < 0) fail(m, "ILLEGAL FUNCTION CALL");
    int64_t result = 1;
    while (exponent > 0) {
        if (exponent % 2) result = checked(m, result * base);
        exponent /= 2;
        if (exponent) base = checked(m, base * base);
    }
    return result;
}

int compare(Value a, Value b) {
    if (a.type == 'S') {
        int order = strcmp(a.text, b.text);
        return (order > 0) - (order < 0);
    }
    return (a.number > b.number) - (a.number < b.number);
}

Value call(Machine *m, const char *name, const Value *args, int count) {
    int64_t n = args[0].number;
    const char *s = args[0].type == 'S' ? args[0].text : "";
    int64_t k = count > 1 ? args[1].number : 0;
    if (strcmp(name, "ABS") == 0)
        return integer_value(checked(m, n < 0 ? -n : n));
    if (strcmp(name, "SGN") == 0)
        return integer_value((n > 0) - (n < 0));
    if (strcmp(name, "INT") == 0) return integer_value(n);
    if (strcmp(name, "SQR") == 0) {
        if (n < 0) fail(m, "ILLEGAL FUNCTION CALL");
        int64_t root = 0;
        while ((root + 1) * (root + 1) <= n) ++root;
        return integer_value(root);
    }
    if (strcmp(name, "RND") == 0) {
        if (n < 1) fail(m, "ILLEGAL FUNCTION CALL");
        m->random_state = m->random_state * 48271 % 2147483647;
        return integer_value(m->random_state % n + 1);
    }
    if (strcmp(name, "LEN") == 0) return integer_value((int64_t)strlen(s));
    if (strcmp(name, "ASC") == 0) {
        if (!*s) fail(m, "ILLEGAL FUNCTION CALL");
        return integer_value((unsigned char)s[0]);
    }
    if (strcmp(name, "VAL") == 0) {
        while (*s == ' ') ++s;
        int sign = 1;
        if (*s == '-' || *s == '+') sign = *s++ == '-' ? -1 : 1;
        if (!token_digit(*s)) return integer_value(0);
        int64_t result = 0;
        while (token_digit(*s)) {
            result = result * 10 + *s++ - '0';
            if (result > 32768) fail(m, "OVERFLOW");
        }
        return integer_value(checked(m, sign * result));
    }
    if (strcmp(name, "CHR$") == 0) {
        if (n < 32 || n > 126) fail(m, "ILLEGAL FUNCTION CALL");
        char text[2] = {(char)n, 0};
        return text_value(copy(m, text));
    }
    if (strcmp(name, "STR$") == 0) {
        char text[32];
        snprintf(text, sizeof(text), "%" PRId64, n);
        return text_value(copy(m, text));
    }
    if (strcmp(name, "LEFT$") == 0 || strcmp(name, "RIGHT$") == 0) {
        if (k < 0) fail(m, "ILLEGAL FUNCTION CALL");
        size_t length = strlen(s);
        size_t amount = (size_t)k < length ? (size_t)k : length;
        char *result = allocate(m, amount + 1);
        const char *source = strcmp(name, "LEFT$") == 0 ? s : s + length - amount;
        memcpy(result, source, amount);
        return text_value(result);
    }
    if (strcmp(name, "MID$") == 0) {
        int64_t length = count == 3 ? args[2].number : (int64_t)strlen(s);
        if (k < 1 || length < 0) fail(m, "ILLEGAL FUNCTION CALL");
        size_t size = strlen(s);
        size_t offset = (size_t)(k - 1) < size ? (size_t)(k - 1) : size;
        size_t amount = (size_t)length < size - offset ? (size_t)length : size - offset;
        char *result = allocate(m, amount + 1);
        memcpy(result, s + offset, amount);
        return text_value(result);
    }
    if (strcmp(name, "INSTR") == 0) {
        const char *found = strstr(s, args[1].text);
        return integer_value(found ? found - s + 1 : 0);
    }
    fail(m, "ILLEGAL FUNCTION CALL");
    return integer_value(0);
}

Value evaluate(Machine *m, int id) {
    Expression expr = m->expressions[id];
    if (expr.kind == 0) return expr.value;
    if (expr.kind == 1 || expr.kind == 2) return load(m, address(m, id));
    if (expr.kind == 3)
        return integer_value(strcmp(expr.name, "ERR") == 0 ? m->err : m->erl);
    if (expr.kind == 4) {
        int64_t a = evaluate(m, expr.args.items[0]).number;
        return integer_value(strcmp(expr.name, "NOT") == 0 ? ~a : checked(m, -a));
    }
    Value args[8] = {0};
    for (int i = 0; i < expr.args.count; ++i)
        args[i] = evaluate(m, expr.args.items[i]);
    if (expr.kind == 5) return call(m, expr.name, args, expr.args.count);
    Value a = args[0], b = args[1];
    const char *op = expr.name;
    if (strcmp(op, "=") == 0 || strcmp(op, "<>") == 0 ||
        strcmp(op, "<") == 0 || strcmp(op, ">") == 0 ||
        strcmp(op, "<=") == 0 || strcmp(op, ">=") == 0) {
        int cmp = compare(a, b);
        int yes = strcmp(op, "=") == 0 ? cmp == 0 :
                  strcmp(op, "<>") == 0 ? cmp != 0 :
                  strcmp(op, "<") == 0 ? cmp < 0 :
                  strcmp(op, ">") == 0 ? cmp > 0 :
                  strcmp(op, "<=") == 0 ? cmp <= 0 : cmp >= 0;
        return integer_value(yes ? -1 : 0);
    }
    if (expr.type == 'S') {
        size_t len = strlen(a.text) + strlen(b.text);
        if (len > 255) fail(m, "STRING TOO LONG");
        char *text = allocate(m, len + 1);
        strcpy(text, a.text);
        strcat(text, b.text);
        return text_value(text);
    }
    int64_t x = a.number, y = b.number;
    if (strcmp(op, "+") == 0) return integer_value(checked(m, x + y));
    if (strcmp(op, "-") == 0) return integer_value(checked(m, x - y));
    if (strcmp(op, "*") == 0) return integer_value(checked(m, x * y));
    if (strcmp(op, "/") == 0 || strcmp(op, "MOD") == 0) {
        if (y == 0) fail(m, "DIVISION BY ZERO");
        return integer_value(strcmp(op, "MOD") == 0 ? x % y : checked(m, x / y));
    }
    if (strcmp(op, "^") == 0) return integer_value(integer_power(m, x, y));
    if (strcmp(op, "AND") == 0) return integer_value(x & y);
    if (strcmp(op, "OR") == 0) return integer_value(x | y);
    fail(m, "ILLEGAL FUNCTION CALL");
    return integer_value(0);
}

int lookup(Machine *m, int number) {
    if (number < 0 || number >= 10000 || m->entries[number] < 0)
        fail(m, "UNDEFINED LINE NUMBER");
    return m->entries[number];
}

void push_frame(Machine *m, Frame frame) {
    if (m->stack_count == 100) fail(m, "OUT OF MEMORY");
    m->stack[m->stack_count++] = frame;
}

int search(Machine *m, int kind, const char *name) {
    for (int i = m->stack_count - 1; i >= 0; --i) {
        Frame *f = &m->stack[i];
        if (f->kind == 3) break;
        if (f->kind == kind && (!*name || strcmp(f->name, name) == 0)) return i;
    }
    return -1;
}

int matching(Machine *m, int id, const char *open, const char *close) {
    int start = 0, depth = 0;
    for (int i = 0; i < m->sequence.count; ++i)
        if (m->sequence.items[i] == id) {
            start = i + 1;
            break;
        }
    for (int i = start; i < m->sequence.count; ++i) {
        Statement *s = &m->statements[m->sequence.items[i]];
        if (strcmp(s->kind, open) == 0) ++depth;
        else if (strcmp(s->kind, close) == 0) {
            if (!depth) return s->next;
            --depth;
        }
    }
    char error[80];
    snprintf(error, sizeof(error), "%s WITHOUT %s", open, close);
    fail(m, error);
    return -1;
}

int subroutine(Machine *m, int number, int after) {
    int destination = lookup(m, number);
    push_frame(m, (Frame){.kind = 3, .position = after});
    return destination;
}

int execute(Machine *m, int id) {
    Statement *s = &m->statements[id];
    int next = s->next;
    if (strcmp(s->kind, "REM") == 0 || strcmp(s->kind, "DATA") == 0)
        return next;
    if (strcmp(s->kind, "assign") == 0) {
        Address place = address(m, s->target);
        store(m, place, evaluate(m, s->expr));
    } else if (strcmp(s->kind, "PRINT") == 0) {
        for (int i = 0; i < s->items.count; ++i) {
            PrintItem *item = &s->items.items[i];
            if (item->kind == 2) {
                append_spaces(m, 10 - m->buffer_length % 10);
            } else if (item->kind != 1) {
                Value value = evaluate(m, item->expr);
                if (item->kind == 0) {
                    if (value.type == 'S') append(m, value.text);
                    else {
                        char text[32];
                        snprintf(text, sizeof(text), "%" PRId64, value.number);
                        append(m, text);
                    }
                } else {
                    int n = (int)value.number;
                    if (n < 0) fail(m, "ILLEGAL FUNCTION CALL");
                    append_spaces(m, item->kind == 4 ? n :
                                  n > m->buffer_length ? n - m->buffer_length : 0);
                }
            }
        }
        if (!s->items.count ||
            (s->items.items[s->items.count - 1].kind != 1 &&
             s->items.items[s->items.count - 1].kind != 2))
            end_line(m);
    } else if (strcmp(s->kind, "INPUT") == 0 || strcmp(s->kind, "READ") == 0) {
        for (int i = 0; i < s->targets.count; ++i) {
            int id = s->targets.items[i];
            Address place = address(m, id);
            Value value;
            if (strcmp(s->kind, "READ") == 0) {
                if (m->data_position == m->data.count) fail(m, "OUT OF DATA");
                value = m->data.items[m->data_position++];
                if (value.type != m->expressions[id].type)
                    fail(m, "TYPE MISMATCH");
            } else {
                for (;;) {
                    if (m->input_position == m->input_count) fail(m, "INPUT PAST END");
                    char *text = m->inputs[m->input_position++];
                    if (m->expressions[id].type == 'S') {
                        value = text_value(text);
                        break;
                    }
                    const char *p = text;
                    if (*p == '-') ++p;
                    int valid = *p != 0;
                    for (; *p; ++p) if (!token_digit(*p)) valid = 0;
                    if (valid) {
                        int64_t number = 0;
                        int negative = text[0] == '-';
                        p = text + negative;
                        for (; *p; ++p) {
                            number = number * 10 + *p - '0';
                            if (number > 32768) { valid = 0; break; }
                        }
                        number = negative ? -number : number;
                        if (valid && number >= -32768 && number <= 32767) {
                            value = integer_value(number);
                            break;
                        }
                    }
                    message(m, "?REDO FROM START");
                }
            }
            store(m, place, value);
        }
    } else if (strcmp(s->kind, "RESTORE") == 0) {
        if (!s->numbers.count) m->data_position = 0;
        else {
            int line = s->numbers.items[0];
            lookup(m, line);
            m->data_position = m->data.count;
            for (int i = 0; i < m->data.count; ++i)
                if (m->data_lines.items[i] >= line) {
                    m->data_position = i;
                    break;
                }
        }
    } else if (strcmp(s->kind, "IF") == 0) {
        int branch = evaluate(m, s->expr).number != 0 ? 0 : 1;
        if (branch < s->clause_count) {
            Clause *clause = &s->clauses[branch];
            next = clause->number >= 0 ? lookup(m, clause->number) :
                   clause->body.items[0];
        }
    } else if (strcmp(s->kind, "GOTO") == 0) {
        next = lookup(m, s->numbers.items[0]);
    } else if (strcmp(s->kind, "GOSUB") == 0) {
        next = subroutine(m, s->numbers.items[0], next);
    } else if (strcmp(s->kind, "ON") == 0) {
        int n = (int)evaluate(m, s->expr).number;
        if (n < 0) fail(m, "ILLEGAL FUNCTION CALL");
        if (n >= 1 && n <= s->numbers.count) {
            int number = s->numbers.items[n - 1];
            next = strcmp(s->mode, "GOTO") == 0 ?
                   lookup(m, number) : subroutine(m, number, next);
        }
    } else if (strcmp(s->kind, "RETURN") == 0) {
        int found = m->stack_count - 1;
        while (found >= 0 && m->stack[found].kind != 3) --found;
        if (found < 0) fail(m, "RETURN WITHOUT GOSUB");
        next = m->stack[found].position;
        m->stack_count = found;
    } else if (strcmp(s->kind, "FOR") == 0) {
        int values[3];
        for (int i = 0; i < 3; ++i)
            values[i] = (int)evaluate(m, s->expressions.items[i]).number;
        int start = values[0], end = values[1], step = values[2];
        if (!step) fail(m, "ILLEGAL FUNCTION CALL");
        int found = search(m, 1, s->name);
        if (found >= 0) m->stack_count = found;
        int slot = variable_index(s->name);
        m->vars[slot] = integer_value(start);
        m->present[slot] = 1;
        if (step > 0 ? start > end : start < end) {
            next = matching(m, id, "FOR", "NEXT");
        } else {
            Frame frame = {.kind = 1, .position = next, .limit = end, .step = step};
            strcpy(frame.name, s->name);
            push_frame(m, frame);
        }
    } else if (strcmp(s->kind, "NEXT") == 0) {
        int found = search(m, 1, s->name);
        if (found < 0) fail(m, "NEXT WITHOUT FOR");
        m->stack_count = found + 1;
        Frame frame = m->stack[found];
        int value = checked(m, get(m, frame.name).number + frame.step);
        int slot = variable_index(frame.name);
        m->vars[slot] = integer_value(value);
        m->present[slot] = 1;
        if (frame.step > 0 ? value > frame.limit : value < frame.limit)
            --m->stack_count;
        else next = frame.position;
    } else if (strcmp(s->kind, "WHILE") == 0) {
        if (evaluate(m, s->expr).number)
            push_frame(m, (Frame){.kind = 2, .position = id});
        else next = matching(m, id, "WHILE", "WEND");
    } else if (strcmp(s->kind, "WEND") == 0) {
        int found = search(m, 2, "");
        if (found < 0) fail(m, "WEND WITHOUT WHILE");
        next = m->stack[found].position;
        m->stack_count = found;
    } else if (strcmp(s->kind, "DIM") == 0) {
        for (int i = 0; i < s->targets.count; ++i) {
            Expression *target = &m->expressions[s->targets.items[i]];
            int slot = variable_index(target->name);
            if (m->arrays[slot]) fail(m, "DUPLICATE DEFINITION");
            int bounds[2] = {0};
            int count = 1;
            for (int j = 0; j < target->args.count; ++j) {
                bounds[j] = (int)evaluate(m, target->args.items[j]).number;
                if (bounds[j] < 0) fail(m, "ILLEGAL FUNCTION CALL");
                count *= bounds[j] + 1;
            }
            if (count > 10000) fail(m, "OUT OF MEMORY");
            declare(m, target->name, bounds, target->args.count);
        }
    } else if (strcmp(s->kind, "RANDOMIZE") == 0) {
        int n = (int)evaluate(m, s->expr).number;
        if (n < 1) fail(m, "ILLEGAL FUNCTION CALL");
        m->random_state = n;
    } else if (strcmp(s->kind, "handler") == 0) {
        if (s->numbers.items[0]) lookup(m, s->numbers.items[0]);
        m->handler = s->numbers.items[0];
    } else if (strcmp(s->kind, "RESUME") == 0) {
        if (!m->handling) fail(m, "RESUME WITHOUT ERROR");
        next = strcmp(s->mode, "line") == 0 ? lookup(m, s->numbers.items[0]) :
               strcmp(s->mode, "NEXT") == 0 ?
               m->statements[m->remembered].next : m->remembered;
        m->handling = 0;
    } else if (strcmp(s->kind, "STOP") == 0) {
        char text[80];
        snprintf(text, sizeof(text), "BREAK IN LINE %d", s->line);
        message(m, text);
        return -1;
    } else if (strcmp(s->kind, "END") == 0) {
        return -1;
    }
    return next;
}

int error_code(const char *reason) {
    const char *errors[] = {
        "NEXT WITHOUT FOR", "RETURN WITHOUT GOSUB", "OUT OF DATA",
        "ILLEGAL FUNCTION CALL", "OVERFLOW", "OUT OF MEMORY",
        "UNDEFINED LINE NUMBER", "SUBSCRIPT OUT OF RANGE", "DUPLICATE DEFINITION",
        "DIVISION BY ZERO", "TYPE MISMATCH", "STRING TOO LONG",
        "RESUME WITHOUT ERROR", "FOR WITHOUT NEXT", "WHILE WITHOUT WEND",
        "WEND WITHOUT WHILE", "INPUT PAST END"
    };
    const int codes[] = {1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 20, 26, 29, 30, 62};
    for (int i = 0; i < 17; ++i)
        if (strcmp(reason, errors[i]) == 0) return codes[i];
    return 0;
}

void run(Machine *m, const char *contents[], const int line_numbers[], int line_count) {
    IntVec parsed[200] = {0};
    for (int i = 0; i < 10000; ++i) m->entries[i] = -1;
    for (int i = 0; i < line_count; ++i) {
        if (setjmp(m->jump) != 0) {
            printf("ERROR IN LINE %d: SYNTAX ERROR\nREADY\n", line_numbers[i]);
            return;
        }
        parsed[i] = parse(m, contents[i]);
    }
    int following = -1;
    for (int i = line_count - 1; i >= 0; --i) {
        connect(m, parsed[i], following, line_numbers[i]);
        m->entries[line_numbers[i]] = parsed[i].items[0];
        following = parsed[i].items[0];
    }
    for (int i = 0; i < line_count; ++i) {
        for (int j = 0; j < parsed[i].count; ++j) {
            int id = parsed[i].items[j];
            int_push(&m->sequence, id);
            Statement *s = &m->statements[id];
            if (strcmp(s->kind, "DATA") == 0) {
                for (int k = 0; k < s->values.count; ++k) {
                    value_push(&m->data, s->values.items[k]);
                    int_push(&m->data_lines, s->line);
                }
            }
        }
    }
    int position = following;
    while (position >= 0) {
        int current = position;
        if (setjmp(m->jump) == 0) {
            position = execute(m, current);
        } else if (m->handler && !m->handling) {
            m->err = error_code(m->failure);
            m->erl = m->statements[current].line;
            m->remembered = current;
            m->handling = 1;
            position = lookup(m, m->handler);
        } else {
            char text[256];
            snprintf(text, sizeof(text), "ERROR IN LINE %d: %s",
                     m->statements[current].line, m->failure);
            message(m, text);
            position = -1;
        }
    }
    if (m->buffer_length) end_line(m);
    puts("READY");
}

void release(Machine *m) {
    for (int i = 0; i < m->statement_count; ++i) {
        Statement *s = &m->statements[i];
        free(s->targets.items);
        free(s->expressions.items);
        free(s->values.items);
        free(s->numbers.items);
        free(s->items.items);
        for (int j = 0; j < s->clause_count; ++j) free(s->clauses[j].body.items);
    }
    for (int i = 0; i < m->expression_count; ++i)
        free(m->expressions[i].args.items);
    for (int i = 0; i < m->allocation_count; ++i)
        free(m->allocations[i]);
    free(m->allocations);
    free(m->expressions);
    free(m->statements);
    free(m->sequence.items);
    free(m->data.items);
    free(m->data_lines.items);
}

void trim_line(char *line) {
    size_t n = strlen(line);
    while (n && (line[n - 1] == '\n' || line[n - 1] == '\r'))
        line[--n] = 0;
}

int main(void) {
    char input[256];
    if (!fgets(input, sizeof(input), stdin)) return 0;
    int sessions = atoi(input);
    for (int session = 0; session < sessions; ++session) {
        Machine *m = calloc(1, sizeof(Machine));
        if (!m) exit(1);
        m->random_state = 1;
        m->remembered = -1;
        int numbers[200];
        const char *contents[200];
        int count = 0;
        while (fgets(input, sizeof(input), stdin)) {
            trim_line(input);
            if (strcmp(input, "RUN") == 0) break;
            int p = 0;
            while (token_digit(input[p])) ++p;
            int number = atoi(input);
            int index = 0;
            while (index < count && numbers[index] < number) ++index;
            if (index < count && numbers[index] == number) {
                for (int j = index + 1; j < count; ++j) {
                    numbers[j - 1] = numbers[j];
                    contents[j - 1] = contents[j];
                }
                --count;
            }
            if (input[p]) {
                while (input[p] == ' ') ++p;
                for (int j = count; j > index; --j) {
                    numbers[j] = numbers[j - 1];
                    contents[j] = contents[j - 1];
                }
                numbers[index] = number;
                contents[index] = copy(m, input + p);
                ++count;
            }
        }
        while (fgets(input, sizeof(input), stdin)) {
            trim_line(input);
            if (strcmp(input, "END") == 0) break;
            if (m->input_count < 200) m->inputs[m->input_count++] = copy(m, input);
        }
        run(m, contents, numbers, count);
        release(m);
        free(m);
    }
    return 0;
}
