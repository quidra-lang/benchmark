#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CANVAS_SIDE 2001
#define COORDINATE_OFFSET 1000

typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;
typedef struct {
    Allocation *head;
} Arena;
typedef enum {
    NUMBER,
    VARIABLE,
    QUOTED,
    WORD,
    SYMBOL,
    SIGN_MINUS,
    OPERATOR_MINUS
} TokenKind;
typedef struct {
    TokenKind kind;
    char *text;
    int line;
} Token;
typedef struct {
    Token *items;
    int count, capacity;
} Tokens;
typedef struct {
    char **items;
    int count, capacity;
} Strings;
typedef struct Expression Expression;
typedef struct Command Command;
typedef struct Procedure Procedure;
typedef struct {
    Expression **items;
    int count, capacity;
} Arguments;
typedef struct PrintItem {
    char *word;
    Expression *expression;
    struct PrintItem *next;
} PrintItem;
struct Expression {
    Token token;
    int kind, code;
    Arguments arguments;
    Procedure *procedure;
};
struct Command {
    Token token;
    int code;
    char *quoted;
    Arguments expressions;
    Command *blocks[2];
    int block_count;
    PrintItem *prints, *last_print;
    Procedure *procedure;
    Command *next;
};
struct Procedure {
    Token token;
    Strings parameters;
    Tokens tokens;
    Command *commands;
    Procedure *next;
    bool traced;
};
typedef struct {
    Tokens *tokens;
    int position;
    bool inside;
} Parser;
typedef struct {
    char *name;
    long long value;
} Variable;
typedef struct {
    Procedure *procedure;
    Variable *variables;
    int count, capacity, test;
} Environment;
typedef struct RuntimeAllocation {
    void *pointer;
    struct RuntimeAllocation *next;
} RuntimeAllocation;
typedef struct {
    int kind;
    long long value;
} Flow;
typedef struct {
    bool present;
    long long value;
} Value;
typedef struct {
    char *text;
    size_t length, capacity;
    RuntimeAllocation *allocation;
} Buffer;
typedef struct {
    int x, y;
} Point;
enum {
    E_NUMBER,
    E_VARIABLE,
    E_NEGATE,
    E_BINARY,
    E_FUNCTION,
    E_CALL
};
enum {
    FD,
    BK,
    RT,
    LT,
    SETH,
    PU,
    PD,
    PE,
    SETPEN,
    SETXY,
    SETX,
    SETY,
    HOME,
    CS,
    CLEAN,
    FILL,
    LABEL,
    SNAPSHOT,
    REPEAT,
    FOR,
    WHILE,
    IF,
    IFELSE,
    TEST,
    IFTRUE,
    IFFALSE,
    STOP,
    OUTPUT,
    MAKE,
    LOCAL,
    LOCALMAKE,
    TRACE,
    UNTRACE,
    SEED,
    PRINT,
    XCOR,
    YCOR,
    HEADING,
    REPCOUNT,
    RANDOM,
    ABS,
    NOT,
    AND,
    OR,
    MAXIMUM,
    MINIMUM,
    TO,
    END,
    MOD,
    CALL,
    MULTIPRINT
};
typedef struct {
    const char *name, *inputs;
    int code;
    bool function;
} Primitive;
static const Primitive primitives[] = {
    {"FD", "E", FD, false},
    {"FORWARD", "E", FD, false},
    {"BK", "E", BK, false},
    {"BACK", "E", BK, false},
    {"RT", "E", RT, false},
    {"RIGHT", "E", RT, false},
    {"LT", "E", LT, false},
    {"LEFT", "E", LT, false},
    {"SETH", "E", SETH, false},
    {"SETHEADING", "E", SETH, false},
    {"PU", "", PU, false},
    {"PENUP", "", PU, false},
    {"PD", "", PD, false},
    {"PENDOWN", "", PD, false},
    {"PE", "", PE, false},
    {"PENERASE", "", PE, false},
    {"SETPEN", "E", SETPEN, false},
    {"SETXY", "EE", SETXY, false},
    {"SETX", "E", SETX, false},
    {"SETY", "E", SETY, false},
    {"HOME", "", HOME, false},
    {"CS", "", CS, false},
    {"CLEARSCREEN", "", CS, false},
    {"CLEAN", "", CLEAN, false},
    {"FILL", "", FILL, false},
    {"LABEL", "P", LABEL, false},
    {"SNAPSHOT", "", SNAPSHOT, false},
    {"REPEAT", "EL", REPEAT, false},
    {"FOR", "QEEL", FOR, false},
    {"WHILE", "EL", WHILE, false},
    {"IF", "EL", IF, false},
    {"IFELSE", "ELL", IFELSE, false},
    {"TEST", "E", TEST, false},
    {"IFTRUE", "L", IFTRUE, false},
    {"IFT", "L", IFTRUE, false},
    {"IFFALSE", "L", IFFALSE, false},
    {"IFF", "L", IFFALSE, false},
    {"STOP", "", STOP, false},
    {"OUTPUT", "E", OUTPUT, false},
    {"OP", "E", OUTPUT, false},
    {"MAKE", "QE", MAKE, false},
    {"LOCAL", "Q", LOCAL, false},
    {"LOCALMAKE", "QE", LOCALMAKE, false},
    {"TRACE", "Q", TRACE, false},
    {"UNTRACE", "Q", UNTRACE, false},
    {"SEED", "E", SEED, false},
    {"PRINT", "P", PRINT, false},
    {"PR", "P", PRINT, false},
    {"XCOR", "", XCOR, true},
    {"YCOR", "", YCOR, true},
    {"HEADING", "", HEADING, true},
    {"REPCOUNT", "", REPCOUNT, true},
    {"RANDOM", "E", RANDOM, true},
    {"ABS", "E", ABS, true},
    {"NOT", "E", NOT, true},
    {"AND", "EE", AND, true},
    {"OR", "EE", OR, true},
    {"MAX", "EE", MAXIMUM, true},
    {"MIN", "EE", MINIMUM, true},
    {"TO", "", TO, false},
    {"END", "", END, false},
    {"MOD", "", MOD, false}
};
static Arena syntax;
static jmp_buf program_error;
static Procedure *procedures, *last_procedure;
static Environment environments[101];
static int environment_count;
static RuntimeAllocation *runtime_allocations;
static bool running;
static long long *repetitions;
static int repetition_count, repetition_capacity;
static unsigned char canvas[CANVAS_SIDE][CANVAS_SIDE];
static int row_counts[CANVAS_SIDE], column_counts[CANVAS_SIDE], mark_count;
static int *marked_positions, marked_count, marked_capacity;
static int min_x, min_y, max_x, max_y, turtle_x, turtle_y, heading, pen;
static unsigned char pen_character;
static long long random_state;
static const int direction_x[] = {0, 1, 1, 1, 0, -1, -1, -1}, direction_y[] = {1, 1, 0, -1, -1, -1, 0, 1};

static void *allocate(size_t size) {
    void *pointer = calloc(1, size ? size : 1);
    Allocation *entry = malloc(sizeof *entry);
    if (!pointer || !entry) exit(EXIT_FAILURE);
    *entry = (Allocation){pointer, syntax.head};
    syntax.head = entry;
    return pointer;
}

static void clear_syntax(void) {
    while (syntax.head) {
        Allocation *next = syntax.head->next;
        free(syntax.head->pointer);
        free(syntax.head);
        syntax.head = next;
    }
}

static char *part(const char *text, size_t length) {
    char *result = allocate(length + 1);
    memcpy(result, text, length);
    return result;
}

static char *copy(const char *text) {
    return part(text, strlen(text));
}

static RuntimeAllocation *runtime_allocate(size_t size) {
    RuntimeAllocation *entry = malloc(sizeof *entry);
    if (!entry) exit(EXIT_FAILURE);
    entry->pointer = malloc(size ? size : 1);
    if (!entry->pointer) exit(EXIT_FAILURE);
    entry->next = runtime_allocations;
    runtime_allocations = entry;
    return entry;
}

static void runtime_release(RuntimeAllocation *entry) {
    if (!entry) return;
    runtime_allocations = entry->next;
    free(entry->pointer);
    free(entry);
}

static void error(int line, const char *format, ...) {
    va_list args;
    va_start(args, format);
    printf("ERROR line %d: ", line);
    vprintf(format, args);
    putchar('\n');
    va_end(args);
    if (running) for (int i = environment_count - 1; i > 0;) {
        const char *name = environments[i].procedure->token.text;
        int end = i - 1;
        while (end > 0 && !strcmp(environments[end].procedure->token.text, name)) end--;
        printf("  in %s", name);
        if (i - end > 1) printf(" x%d", i - end);
        putchar('\n');
        i = end;
    }
    longjmp(program_error, 1);
}

static void add_token(Tokens *tokens, Token token) {
    if (tokens->count == tokens->capacity) {
        int capacity = tokens->capacity ? 2 * tokens->capacity : 16;
        Token *items = allocate((size_t)capacity * sizeof *items);
        if (tokens->count) memcpy(items, tokens->items, (size_t)tokens->count * sizeof *items);
        tokens->items = items;
        tokens->capacity = capacity;
    }
    tokens->items[tokens->count++] = token;
}

static void add_string(Strings *strings, char *text) {
    if (strings->count == strings->capacity) {
        int capacity = strings->capacity ? 2 * strings->capacity : 8;
        char **items = allocate((size_t)capacity * sizeof *items);
        if (strings->count) memcpy(items, strings->items, (size_t)strings->count * sizeof *items);
        strings->items = items;
        strings->capacity = capacity;
    }
    strings->items[strings->count++] = text;
}

static void add_argument(Arguments *arguments, Expression *expression) {
    if (arguments->count == arguments->capacity) {
        int capacity = arguments->capacity ? 2 * arguments->capacity : 4;
        Expression **items = allocate((size_t)capacity * sizeof *items);
        if (arguments->count) memcpy(items, arguments->items, (size_t)arguments->count * sizeof *items);
        arguments->items = items;
        arguments->capacity = capacity;
    }
    arguments->items[arguments->count++] = expression;
}

static bool name(const char *text) {
    if (*text < 'A' || *text > 'Z') return false;
    for (const char *p = text + 1; *p; p++) if (!(*p >= 'A' && *p <= 'Z') && !(*p >= '0' && *p <= '9') && *p != '_') return false;
    return true;
}

static const Primitive *primitive(const char *name) {
    for (size_t i = 0; i < sizeof primitives / sizeof *primitives; i++) if (!strcmp(primitives[i].name, name)) return &primitives[i];
    return NULL;
}

static Procedure *procedure(const char *name) {
    for (Procedure *p = procedures; p; p = p->next) if (!strcmp(p->token.text, name)) return p;
    return NULL;
}

static Tokens lex(const char *source, int line) {
    const char *comment = strchr(source, ';');
    char *text = part(source, comment ? (size_t)(comment - source) : strlen(source));
    for (char *p = text; *p; p++) if (*p >= 'a' && *p <= 'z') *p = (char)(*p - 'a' + 'A');
    Tokens tokens = {0};
    for (int i = 0; text[i];) {
        char c = text[i];
        if (c == ' ') {
            i++;
            continue;
        }
        if (strchr("[]()+*/=", c)) {
            add_token(&tokens, (Token){SYMBOL, part(text + i, 1), line});
            i++;
        } else if (c == '<' || c == '>') {
            int length = text[i + 1] && (text[i + 1] == '=' || (c == '<' && text[i + 1] == '>')) ? 2 : 1;
            add_token(&tokens, (Token){SYMBOL, part(text + i, (size_t)length), line});
            i += length;
        } else if (c == '-') {
            bool sign = (i == 0 || strchr(" [(", text[i - 1])) && text[i + 1] && text[i + 1] != ' ';
            add_token(&tokens, (Token){sign ? SIGN_MINUS : OPERATOR_MINUS, "-", line});
            i++;
        } else {
            int start = i;
            while (text[i] && !strchr(" []()+-*/=<>", text[i])) i++;
            char *word = part(text + start, (size_t)(i - start));
            TokenKind kind;
            bool numeric = true;
            for (char *p = word; *p; p++) if (*p < '0' || *p > '9') numeric = false;
            if (numeric) kind = NUMBER;
            else if (*word == ':' && name(word + 1)) kind = VARIABLE;
            else if (*word == '"' && name(word + 1)) kind = QUOTED;
            else if (name(word)) kind = WORD;
            else {
                error(line, "bad token '%s'", word);
                return tokens;
            }
            add_token(&tokens, (Token){kind, word, line});
        }
    }
    return tokens;
}

static Token *peek(Parser *parser) {
    return parser->position < parser->tokens->count ? &parser->tokens->items[parser->position] : NULL;
}

static bool is(Parser *parser, const char *text) {
    Token *next = peek(parser);
    return next && !strcmp(next->text, text);
}

static bool unknown(Token token) {
    return token.kind == WORD && !primitive(token.text) && !procedure(token.text);
}

static Token input(Parser *parser, Token owner) {
    Token *next = peek(parser);
    if (!next || !strcmp(next->text, "]") || !strcmp(next->text, ")")) error(owner.line, "not enough inputs to %s", owner.text);
    if (unknown(*next)) error(next->line, "I don't know how to %s", next->text);
    return *next;
}

static void reject(Token owner, Token next) {
    error(next.line, "%s doesn't like %s as input", owner.text, next.text);
}
static Expression *expression(Parser *parser, Token owner);
static Command *parse_command(Parser *parser);

static Expression *new_expression(Token token, int kind) {
    Expression *result = allocate(sizeof *result);
    result->token = token;
    result->kind = kind;
    return result;
}

static Command *new_command(Token token, int code) {
    Command *result = allocate(sizeof *result);
    result->token = token;
    result->code = code;
    return result;
}

static void append_command(Command **first, Command **last, Command *command) {
    if (*last) (*last)->next = command;
    else *first = command;
    *last = command;
}

static Command *sequence(Parser *parser) {
    Command *first = NULL, *last = NULL;
    while (peek(parser)) {
        if (is(parser, "]")) error(peek(parser)->line, "unexpected ]");
        append_command(&first, &last, parse_command(parser));
    }
    return first;
}

static Command *block(Parser *parser, Token owner) {
    Token opener = input(parser, owner);
    if (strcmp(opener.text, "[")) reject(owner, opener);
    parser->position++;
    Command *first = NULL, *last = NULL;
    while (peek(parser) && !is(parser, "]")) append_command(&first, &last, parse_command(parser));
    if (!peek(parser)) error(opener.line, "missing ]");
    parser->position++;
    return first;
}

static char *quoted(Parser *parser, Token owner) {
    Token next = input(parser, owner);
    if (next.kind != QUOTED) reject(owner, next);
    parser->position++;
    return next.text + 1;
}

static PrintItem *print_item(Parser *parser, Token owner) {
    Token next = input(parser, owner);
    PrintItem *item = allocate(sizeof *item);
    if (next.kind == QUOTED) {
        parser->position++;
        item->word = next.text + 1;
    } else item->expression = expression(parser, owner);
    return item;
}

static void add_print(Command *command, PrintItem *item) {
    if (command->last_print) command->last_print->next = item;
    else command->prints = item;
    command->last_print = item;
}

static Command *parse_command(Parser *parser) {
    Token token = parser->tokens->items[parser->position++];
    if (!strcmp(token.text, "(") && peek(parser) && peek(parser)->kind == WORD && (is(parser, "PRINT") || is(parser, "PR"))) {
        Token print = parser->tokens->items[parser->position++];
        Command *command = new_command(print, MULTIPRINT);
        while (!is(parser, ")")) {
            if (!peek(parser) || is(parser, "]")) error(token.line, "missing )");
            add_print(command, print_item(parser, print));
        }
        parser->position++;
        return command;
    }
    if (token.kind == WORD && (!strcmp(token.text, "TO") || !strcmp(token.text, "END"))) error(token.line, "misplaced %s", token.text);
    const Primitive *p = token.kind == WORD ? primitive(token.text) : NULL;
    if (p && !p->function && p->code != MOD) {
        if (!parser->inside && (p->code == STOP || p->code == OUTPUT || p->code == LOCAL || p->code == LOCALMAKE)) error(token.line, "can only use %s inside a procedure", token.text);
        Command *command = new_command(token, p->code);
        for (const char *kind = p->inputs; *kind; kind++) switch (*kind) {
            case 'E':
                add_argument(&command->expressions, expression(parser, token));
                break;
            case 'L':
                command->blocks[command->block_count++] = block(parser, token);
                break;
            case 'Q':
                command->quoted = quoted(parser, token);
                break;
            case 'P':
                add_print(command, print_item(parser, token));
                break;
        }
        if ((p->code == TRACE || p->code == UNTRACE) && !procedure(command->quoted)) error(parser->tokens->items[parser->position - 1].line, "I don't know how to %s", command->quoted);
        return command;
    }
    Procedure *proc = token.kind == WORD ? procedure(token.text) : NULL;
    if (proc) {
        Command *command = new_command(token, CALL);
        command->procedure = proc;
        for (int i = 0; i < proc->parameters.count; i++) add_argument(&command->expressions, expression(parser, token));
        return command;
    }
    if (unknown(token)) error(token.line, "I don't know how to %s", token.text);
    error(token.line, "you don't say what to do with %s", token.text);
    return NULL;
}

static Expression *term(Parser *parser, Token owner) {
    Token token = input(parser, owner);
    parser->position++;
    if (token.kind == NUMBER || token.kind == VARIABLE) return new_expression(token, token.kind == NUMBER ? E_NUMBER : E_VARIABLE);
    if (!strcmp(token.text, "-")) {
        Expression *result = new_expression(token, E_NEGATE);
        add_argument(&result->arguments, term(parser, token));
        return result;
    }
    if (!strcmp(token.text, "(")) {
        Expression *result = expression(parser, token);
        if (!is(parser, ")")) error(token.line, "missing )");
        parser->position++;
        return result;
    }
    if (token.kind == WORD) {
        const Primitive *p = primitive(token.text);
        Procedure *proc = procedure(token.text);
        if ((p && p->function) || proc) {
            Expression *result = new_expression(token, p ? E_FUNCTION : E_CALL);
            result->procedure = proc;
            if (p) result->code = p->code;
            int count = p ? (int)strlen(p->inputs) : proc->parameters.count;
            for (int i = 0; i < count; i++) add_argument(&result->arguments, expression(parser, token));
            return result;
        }
    }
    reject(owner, token);
    return NULL;
}

static Expression *binary(Expression *left, Token operation, Expression *right) {
    Expression *result = new_expression(operation, E_BINARY);
    add_argument(&result->arguments, left);
    add_argument(&result->arguments, right);
    return result;
}

static Expression *product(Parser *parser, Token owner) {
    Expression *result = term(parser, owner);
    while (is(parser, "*") || is(parser, "/") || is(parser, "MOD")) {
        Token operation = parser->tokens->items[parser->position++];
        result = binary(result, operation, term(parser, operation));
    }
    return result;
}

static Expression *sum(Parser *parser, Token owner) {
    Expression *result = product(parser, owner);
    while (is(parser, "+") || (is(parser, "-") && peek(parser)->kind == OPERATOR_MINUS)) {
        Token operation = parser->tokens->items[parser->position++];
        result = binary(result, operation, product(parser, operation));
    }
    return result;
}

static Expression *expression(Parser *parser, Token owner) {
    Expression *result = sum(parser, owner);
    while (is(parser, "=") || is(parser, "<>") || is(parser, "<") || is(parser, ">") || is(parser, "<=") || is(parser, ">=")) {
        Token operation = parser->tokens->items[parser->position++];
        result = binary(result, operation, sum(parser, operation));
    }
    return result;
}

static int variable_index(Environment *environment, const char *name) {
    for (int i = 0; i < environment->count; i++) if (!strcmp(environment->variables[i].name, name)) return i;
    return -1;
}

static void set_variable(Environment *environment, char *name, long long value) {
    int index = variable_index(environment, name);
    if (index >= 0) {
        environment->variables[index].value = value;
        return;
    }
    if (environment->count == environment->capacity) {
        environment->capacity = environment->capacity ? environment->capacity * 2 : 8;
        Variable *next = realloc(environment->variables, (size_t)environment->capacity * sizeof *next);
        if (!next) exit(EXIT_FAILURE);
        environment->variables = next;
    }
    environment->variables[environment->count++] = (Variable){name, value};
}

static void make(char *name, long long value) {
    for (int i = environment_count - 1; i > 0; i--) if (variable_index(&environments[i], name) >= 0) {
        set_variable(&environments[i], name, value);
        return;
    }
    set_variable(&environments[0], name, value);
}

static long long variable(Token token) {
    for (int i = environment_count - 1; i >= 0; i--) {
        int index = variable_index(&environments[i], token.text + 1);
        if (index >= 0) return environments[i].variables[index].value;
    }
    error(token.line, "%s has no value", token.text + 1);
    return 0;
}
static long long evaluate(Expression *expression);
static Flow execute(Command *commands);

static Value call(Token token, Procedure *proc, const long long *values) {
    int depth = environment_count - 1;
    if (depth == 100) error(token.line, "recursion too deep");
    bool trace = proc->traced;
    if (trace) {
        for (int i = 0; i < 2 * depth; i++) putchar(' ');
        printf("( %s", token.text);
        for (int i = 0; i < proc->parameters.count; i++) printf(" %lld", values[i]);
        puts(" )");
    }
    Environment *environment = &environments[environment_count++];
    *environment = (Environment){0};
    environment->procedure = proc;
    environment->test = -1;
    for (int i = 0; i < proc->parameters.count; i++) set_variable(environment, proc->parameters.items[i], values[i]);
    Flow flow = execute(proc->commands);
    free(environment->variables);
    *environment = (Environment){0};
    environment_count--;
    Value result = {flow.kind == 2, flow.value};
    if (trace) {
        for (int i = 0; i < 2 * depth; i++) putchar(' ');
        printf("%s", token.text);
        if (result.present) printf(" outputs %lld\n", result.value);
        else puts(" stops");
    }
    return result;
}

static long long evaluate(Expression *e) {
    Token token = e->token;
    if (e->kind == E_NUMBER) return atoll(token.text);
    if (e->kind == E_VARIABLE) return variable(token);
    if (e->kind == E_NEGATE) return -evaluate(e->arguments.items[0]);
    if (e->kind == E_BINARY) {
        long long a = evaluate(e->arguments.items[0]);
        long long b = evaluate(e->arguments.items[1]);
        const char *op = token.text;
        if ((!strcmp(op, "/") || !strcmp(op, "MOD")) && !b) error(token.line, "%s doesn't like 0 as input", op);
        if (!strcmp(op, "+")) return a + b;
        if (!strcmp(op, "-")) return a - b;
        if (!strcmp(op, "*")) return a * b;
        if (!strcmp(op, "/")) return a / b;
        if (!strcmp(op, "MOD")) return a % b;
        if (!strcmp(op, "=")) return a == b;
        if (!strcmp(op, "<>")) return a != b;
        if (!strcmp(op, "<")) return a < b;
        if (!strcmp(op, ">")) return a > b;
        if (!strcmp(op, "<=")) return a <= b;
        return a >= b;
    }
    RuntimeAllocation *allocation = e->arguments.count ? runtime_allocate((size_t)e->arguments.count * sizeof(long long)) : NULL;
    long long *values = allocation ? allocation->pointer : NULL;
    for (int i = 0; i < e->arguments.count; i++) values[i] = evaluate(e->arguments.items[i]);
    long long a = e->arguments.count ? values[0] : 0, b = e->arguments.count > 1 ? values[1] : 0, result = 0;
    if (e->kind == E_CALL) {
        Value value = call(token, e->procedure, values);
        if (!value.present) error(token.line, "%s did not output", token.text);
        result = value.value;
    } else switch (e->code) {
        case XCOR:
            result = turtle_x;
            break;
        case YCOR:
            result = turtle_y;
            break;
        case HEADING:
            result = heading;
            break;
        case REPCOUNT:
            if (!repetition_count) error(token.line, "REPCOUNT outside REPEAT");
            result = repetitions[repetition_count - 1];
            break;
        case RANDOM:
            if (a < 1) error(token.line, "RANDOM doesn't like %lld as input", a);
            random_state = random_state * 48271 % 2147483647;
            result = random_state % a;
            break;
        case ABS:
            result = a < 0 ? -a : a;
            break;
        case NOT:
            result = a == 0;
            break;
        case AND:
            result = a != 0 && b != 0;
            break;
        case OR:
            result = a != 0 || b != 0;
            break;
        case MAXIMUM:
            result = a > b ? a : b;
            break;
        case MINIMUM:
            result = a < b ? a : b;
            break;
    }
    runtime_release(allocation);
    return result;
}

static void set_cell(int x, int y, unsigned char mark) {
    int xx = x + COORDINATE_OFFSET, yy = y + COORDINATE_OFFSET;
    unsigned char old = canvas[yy][xx];
    if (!old && mark) {
        if (marked_count == marked_capacity) {
            marked_capacity = marked_capacity ? marked_capacity * 2 : 1024;
            int *next = realloc(marked_positions, (size_t)marked_capacity * sizeof *next);
            if (!next) exit(EXIT_FAILURE);
            marked_positions = next;
        }
        marked_positions[marked_count++] = yy * CANVAS_SIDE + xx;
        row_counts[yy]++;
        column_counts[xx]++;
        if (!mark_count) {
            min_x = max_x = x;
            min_y = max_y = y;
        } else {
            if (x < min_x) min_x = x;
            if (x > max_x) max_x = x;
            if (y < min_y) min_y = y;
            if (y > max_y) max_y = y;
        }
        mark_count++;
    }
    canvas[yy][xx] = mark;
    if (old && !mark) {
        row_counts[yy]--;
        column_counts[xx]--;
        mark_count--;
        if (mark_count) {
            while (!column_counts[min_x + COORDINATE_OFFSET]) min_x++;
            while (!column_counts[max_x + COORDINATE_OFFSET]) max_x--;
            while (!row_counts[min_y + COORDINATE_OFFSET]) min_y++;
            while (!row_counts[max_y + COORDINATE_OFFSET]) max_y--;
        }
    }
}

static void clear_canvas(void) {
    for (int i = 0; i < marked_count; i++) {
        int index = marked_positions[i];
        canvas[index / CANVAS_SIDE][index % CANVAS_SIDE] = 0;
    }
    if (mark_count) {
        memset(row_counts, 0, sizeof row_counts);
        memset(column_counts, 0, sizeof column_counts);
    }
    mark_count = marked_count = 0;
}

static void apply(int x, int y) {
    if (pen == 0) set_cell(x, y, pen_character);
    else if (pen == 2) set_cell(x, y, 0);
}

static void forward(long long n) {
    int dx = direction_x[heading / 45], dy = direction_y[heading / 45];
    if (n < 0) {
        dx = -dx;
        dy = -dy;
        n = -n;
    }
    apply(turtle_x, turtle_y);
    for (long long i = 0; i < n; i++) {
        turtle_x += dx;
        turtle_y += dy;
        apply(turtle_x, turtle_y);
    }
}

static long long floor_divide(long long a, long long b) {
    long long result = a / b;
    return a < 0 && a % b ? result - 1 : result;
}

static void move(int x, int y) {
    int old_x = turtle_x, old_y = turtle_y, dx = x - old_x, dy = y - old_y, steps = abs(dx) > abs(dy) ? abs(dx) : abs(dy);
    if (!steps) apply(old_x, old_y);
    else for (int i = 0; i <= steps; i++) apply(old_x + (int)floor_divide(2LL * i * dx + steps, 2LL * steps), old_y + (int)floor_divide(2LL * i * dy + steps, 2LL * steps));
    turtle_x = x;
    turtle_y = y;
}

static void fill(void) {
    if (!mark_count || canvas[turtle_y + COORDINATE_OFFSET][turtle_x + COORDINATE_OFFSET]) return;
    int x1 = min_x, x2 = max_x, y1 = min_y, y2 = max_y;
    if (turtle_x < x1 || turtle_x > x2 || turtle_y < y1 || turtle_y > y2) return;
    size_t capacity = (size_t)(x2 - x1 + 1) * (y2 - y1 + 1);
    Point *queue = malloc(capacity * sizeof *queue);
    if (!queue) exit(EXIT_FAILURE);
    size_t head = 0, tail = 0;
    queue[tail++] = (Point){turtle_x, turtle_y};
    set_cell(turtle_x, turtle_y, pen_character);
    const int dx[] = {-1, 1, 0, 0}, dy[] = {0, 0, -1, 1};
    while (head < tail) {
        Point point = queue[head++];
        for (int d = 0; d < 4; d++) {
            int x = point.x + dx[d], y = point.y + dy[d];
            if (x >= x1 && x <= x2 && y >= y1 && y <= y2 && !canvas[y + COORDINATE_OFFSET][x + COORDINATE_OFFSET]) {
                set_cell(x, y, pen_character);
                queue[tail++] = (Point){x, y};
            }
        }
    }
    free(queue);
}

static void picture(void) {
    if (!mark_count) {
        puts("CANVAS 0 0 0");
        return;
    }
    printf("CANVAS %d %d %d\n", max_x - min_x + 1, max_y - min_y + 1, mark_count);
    for (int y = max_y; y >= min_y; y--) {
        int end = max_x;
        while (end >= min_x && !canvas[y + COORDINATE_OFFSET][end + COORDINATE_OFFSET]) end--;
        for (int x = min_x; x <= end; x++) {
            unsigned char mark = canvas[y + COORDINATE_OFFSET][x + COORDINATE_OFFSET];
            putchar(mark ? mark : ' ');
        }
        putchar('\n');
    }
}

static char *item(PrintItem *item, char number[32]) {
    if (item->word) return item->word;
    long long value = evaluate(item->expression);
    snprintf(number, 32, "%lld", value);
    return number;
}

static void append(Buffer *buffer, const char *text) {
    size_t length = strlen(text);
    if (buffer->length + length + 1 > buffer->capacity) {
        size_t capacity = buffer->capacity ? buffer->capacity * 2 : 64;
        while (capacity < buffer->length + length + 1) capacity *= 2;
        if (!buffer->allocation) buffer->allocation = runtime_allocate(capacity);
        else {
            void *next = realloc(buffer->allocation->pointer, capacity);
            if (!next) exit(EXIT_FAILURE);
            buffer->allocation->pointer = next;
        }
        buffer->text = buffer->allocation->pointer;
        buffer->capacity = capacity;
    }
    memcpy(buffer->text + buffer->length, text, length + 1);
    buffer->length += length;
}

static void push_repetition(long long value) {
    if (repetition_count == repetition_capacity) {
        repetition_capacity = repetition_capacity ? repetition_capacity * 2 : 8;
        long long *next = realloc(repetitions, (size_t)repetition_capacity * sizeof *next);
        if (!next) exit(EXIT_FAILURE);
        repetitions = next;
    }
    repetitions[repetition_count++] = value;
}

static Flow execute_one(Command *command) {
    Token token = command->token;
    Flow result = {0};
    if (command->code == WHILE) {
        while (evaluate(command->expressions.items[0])) {
            result = execute(command->blocks[0]);
            if (result.kind) return result;
        }
        return result;
    }
    RuntimeAllocation *allocation = command->expressions.count ? runtime_allocate((size_t)command->expressions.count * sizeof(long long)) : NULL;
    long long *values = allocation ? allocation->pointer : NULL;
    for (int i = 0; i < command->expressions.count; i++) values[i] = evaluate(command->expressions.items[i]);
    long long a = command->expressions.count ? values[0] : 0, b = command->expressions.count > 1 ? values[1] : 0;
    Environment *current = &environments[environment_count - 1];
    switch (command->code) {
        case FD:
            forward(a);
            break;
        case BK:
            forward(-a);
            break;
        case RT:
        case LT:
        case SETH:
            {
                if (a % 45) error(token.line, "%s doesn't like %lld as input", token.text, a);
                long long angle = command->code == SETH ? a : command->code == RT ? heading + a : heading - a;
                heading = (int)((angle % 360 + 360) % 360);
                break;
            }
        case PU:
            pen = 1;
            break;
        case PD:
            pen = 0;
            break;
        case PE:
            pen = 2;
            break;
        case SETPEN:
            if (a < 33 || a > 126) error(token.line, "SETPEN doesn't like %lld as input", a);
            pen_character = (unsigned char)a;
            break;
        case SETXY:
            move((int)a, (int)b);
            break;
        case SETX:
            move((int)a, turtle_y);
            break;
        case SETY:
            move(turtle_x, (int)a);
            break;
        case HOME:
            move(0, 0);
            heading = 0;
            break;
        case CS:
            clear_canvas();
            turtle_x = turtle_y = heading = 0;
            break;
        case CLEAN:
            clear_canvas();
            break;
        case FILL:
            fill();
            break;
        case LABEL:
            {
                char number[32];
                const char *text = item(command->prints, number);
                int dx = direction_x[heading / 45], dy = direction_y[heading / 45];
                for (int i = 0; text[i]; i++) set_cell(turtle_x + i * dx, turtle_y + i * dy, (unsigned char)text[i]);
                break;
            }
        case SNAPSHOT:
            picture();
            break;
        case REPEAT:
            if (command->blocks[0]) for (long long i = 1; i <= a; i++) {
                push_repetition(i);
                result = execute(command->blocks[0]);
                repetition_count--;
                if (result.kind) break;
            }
            break;
        case FOR:
            if (!command->blocks[0]) make(command->quoted, b);
            else for (long long i = a;; i += a <= b ? 1 : -1) {
                make(command->quoted, i);
                result = execute(command->blocks[0]);
                if (result.kind || i == b) break;
            }
            break;
        case IF:
            if (a) result = execute(command->blocks[0]);
            break;
        case IFELSE:
            result = execute(command->blocks[a ? 0 : 1]);
            break;
        case TEST:
            current->test = a != 0;
            break;
        case IFTRUE:
        case IFFALSE:
            if (current->test < 0) error(token.line, "%s without TEST", token.text);
            if (current->test == (command->code == IFTRUE)) result = execute(command->blocks[0]);
            break;
        case STOP:
            result.kind = 1;
            break;
        case OUTPUT:
            result = (Flow){2, a};
            break;
        case MAKE:
            make(command->quoted, a);
            break;
        case LOCAL:
            set_variable(current, command->quoted, 0);
            break;
        case LOCALMAKE:
            set_variable(current, command->quoted, a);
            break;
        case TRACE:
            procedure(command->quoted)->traced = true;
            break;
        case UNTRACE:
            procedure(command->quoted)->traced = false;
            break;
        case SEED:
            if (a < 1) error(token.line, "SEED doesn't like %lld as input", a);
            random_state = a;
            break;
        case PRINT:
        case MULTIPRINT:
            {
                Buffer buffer = {0};
                bool first = true;
                for (PrintItem *print = command->prints; print; print = print->next) {
                    if (!first) append(&buffer, " ");
                    char number[32];
                    const char *text = item(print, number);
                    append(&buffer, text);
                    first = false;
                }
                puts(buffer.text ? buffer.text : "");
                runtime_release(buffer.allocation);
                break;
            }
        case CALL:
            {
                Value value = call(token, command->procedure, values);
                if (value.present) error(token.line, "you don't say what to do with %lld", value.value);
                break;
            }
    }
    runtime_release(allocation);
    return result;
}

static Flow execute(Command *commands) {
    for (Command *command = commands; command; command = command->next) {
        Flow result = execute_one(command);
        if (result.kind) return result;
    }
    return (Flow){0};
}

static void run_program(const char *program_name, char **source, int count, int first_line) {
    printf("PROGRAM %s\n", program_name);
    procedures = last_procedure = NULL;
    running = false;
    environment_count = 0;
    if (setjmp(program_error) == 0) {
        Tokens top = {0};
        Procedure *current = NULL;
        for (int i = 0; i < count; i++) {
            int line = first_line + i;
            Tokens tokens = lex(source[i], line);
            if (!tokens.count) continue;
            Token first = tokens.items[0];
            if (first.kind == WORD && !strcmp(first.text, "TO")) {
                if (current) error(line, "TO inside definition of %s", current->token.text);
                if (tokens.count < 2 || tokens.items[1].kind != WORD) error(line, "bad procedure header");
                Token proc_name = tokens.items[1];
                if (primitive(proc_name.text)) error(line, "%s is a primitive", proc_name.text);
                if (procedure(proc_name.text)) error(line, "%s is already defined", proc_name.text);
                Procedure *proc = allocate(sizeof *proc);
                proc->token = proc_name;
                for (int j = 2; j < tokens.count; j++) {
                    Token parameter = tokens.items[j];
                    if (parameter.kind != VARIABLE) error(line, "bad procedure header");
                    for (int k = 0; k < proc->parameters.count; k++) if (!strcmp(proc->parameters.items[k], parameter.text + 1)) error(line, "duplicate input %s", parameter.text);
                    add_string(&proc->parameters, parameter.text + 1);
                }
                if (last_procedure) last_procedure->next = proc;
                else procedures = proc;
                last_procedure = proc;
                current = proc;
            } else if (tokens.count == 1 && first.kind == WORD && !strcmp(first.text, "END")) {
                if (!current) error(line, "END without TO");
                current = NULL;
            } else {
                Tokens *body = current ? &current->tokens : &top;
                for (int j = 0; j < tokens.count; j++) add_token(body, tokens.items[j]);
            }
        }
        if (current) error(current->token.line, "missing END for %s", current->token.text);
        for (Procedure *proc = procedures; proc; proc = proc->next) {
            Parser parser = {&proc->tokens, 0, true};
            proc->commands = sequence(&parser);
        }
        Parser parser = {&top, 0, false};
        Command *commands = sequence(&parser);
        clear_canvas();
        turtle_x = turtle_y = heading = pen = 0;
        pen_character = '*';
        random_state = 1;
        repetition_count = 0;
        environments[0] = (Environment){0};
        environments[0].test = -1;
        environment_count = 1;
        running = true;
        execute(commands);
        const char *pens[] = {"DOWN", "UP", "ERASE"};
        printf("TURTLE %d %d %d %s %c\n", turtle_x, turtle_y, heading, pens[pen], pen_character);
        picture();
    }
    for (int i = 0; i < environment_count; i++) {
        free(environments[i].variables);
        environments[i] = (Environment){0};
    }
    environment_count = 0;
    while (runtime_allocations) runtime_release(runtime_allocations);
    clear_syntax();
    running = false;
}

static char *read_line(void) {
    size_t count = 0, capacity = 128;
    char *line = malloc(capacity);
    int ch;
    if (!line) exit(EXIT_FAILURE);
    while ((ch = getchar()) != EOF && ch != '\n') {
        if (count + 1 == capacity) {
            capacity *= 2;
            char *next = realloc(line, capacity);
            if (!next) exit(EXIT_FAILURE);
            line = next;
        }
        line[count++] = (char)ch;
    }
    if (ch == EOF && !count) {
        free(line);
        return NULL;
    }
    line[count] = '\0';
    return line;
}

int main(void) {
    char **lines = NULL, *line;
    int count = 0, capacity = 0;
    while ((line = read_line())) {
        if (count == capacity) {
            capacity = capacity ? 2 * capacity : 64;
            char **next = realloc(lines, (size_t)capacity * sizeof *next);
            if (!next) exit(EXIT_FAILURE);
            lines = next;
        }
        lines[count++] = line;
    }
    for (int i = 0; i < count && strcmp(lines[i], "#EOF");) {
        const char *program_name = lines[i] + 9;
        int first = ++i;
        while (strcmp(lines[i], "#EOF") && strncmp(lines[i], "#PROGRAM ", 9)) i++;
        run_program(program_name, lines + first, i - first, first + 1);
    }
    clear_canvas();
    free(marked_positions);
    free(repetitions);
    for (int i = 0; i < count; i++) free(lines[i]);
    free(lines);
    return 0;
}
