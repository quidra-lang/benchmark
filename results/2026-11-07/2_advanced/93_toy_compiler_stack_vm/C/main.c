#include "compiler.h"
typedef struct Allocation {
    void *value;
    struct Allocation *next;
} Allocation;
static Allocation *allocations;
void *ml_alloc(size_t size) {
    void *value = calloc(1, size ? size : 1);
    Allocation *record = malloc(sizeof(*record));
    if (!value || !record)
        exit(1);
    record->value = value;
    record->next = allocations;
    allocations = record;
    return value;
}
void *ml_grow(void *items, int *capacity, size_t size, int count) {
    int next = *capacity ? *capacity * 2 : 8;
    void *result = ml_alloc((size_t)next * size);
    if (count)
        memcpy(result, items, (size_t)count * size);
    *capacity = next;
    return result;
}
char *ml_text(const char *text, size_t length) {
    char *result = ml_alloc(length + 1);
    memcpy(result, text, length);
    return result;
}
char *ml_format(const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int count = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    char *result = ml_alloc((size_t)count + 1);
    vsnprintf(result, (size_t)count + 1, format, args);
    va_end(args);
    return result;
}
void ml_cleanup(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations->value);
        free(allocations);
        allocations = next;
    }
}
void text_add(Text *text, const char *value) {
    size_t length = strlen(value);
    while ((size_t)text->capacity < (size_t)text->count + length + 1)
        text->items = ml_grow(text->items, &text->capacity, 1, text->count);
    memcpy(text->items + text->count, value, length + 1);
    text->count += (int)length;
}
void text_char(Text *text, char c) {
    char value[2] = {c, 0};
    text_add(text, value);
}
char *text_value(Text *text) {
    if (!text->items)
        return ml_text("", 0);
    return text->items;
}
static const char *rule_names[] = {"const-jump", "not-compare", "not-jump",   "invert-branch",
                                   "thread",     "jump-next",   "unreachable"};
typedef struct {
    const char *name;
    int first_line;
    StringList lines;
    NumberList input;
} Source;
typedef struct {
    Source *items;
    int count, capacity;
} SourceList;
typedef struct {
    Position position;
    const char *message;
} Warning;
typedef struct {
    Warning *items;
    int count, capacity;
} WarningList;
static void reachable_visit(Symbol *function, SymbolList *reachable) {
    if (symbol_member(*reachable, function))
        return;
    PUSH(*reachable, function);
    for (int i = 0; i < function->calls.count; ++i)
        reachable_visit(function->calls.items[i], reachable);
}
static SymbolList reachable_functions(Program *p) {
    SymbolList result = {0};
    reachable_visit(name_lookup(p->names, "main"), &result);
    return result;
}
static void unreachable_warnings(Statement *s, void *context) {
    WarningList *warnings = context;
    if (equal(s->kind, "block"))
        for (int i = 0; i < s->statements.count; ++i)
            if (!can_complete(s->statements.items[i])) {
                if (i + 1 < s->statements.count) {
                    Warning warning = {s->statements.items[i + 1]->token.position,
                                       "unreachable statement"};
                    PUSH(*warnings, warning);
                }
                break;
            }
}
static int warning_compare(const void *left, const void *right) {
    const Warning *a = left;
    const Warning *b = right;
    return earlier(a->position, b->position) ? -1 : earlier(b->position, a->position) ? 1 : 0;
}
static WarningList collect_warnings(Program *p, SymbolList reachable) {
    WarningList result = {0};
    for (int i = 0; i < p->symbols.count; ++i) {
        Symbol *symbol = p->symbols.items[i];
        if (!equal(symbol->kind, "function") && !symbol->reads) {
            Warning warning = {
                symbol->declaration->name.position,
                ml_format("unused %s '%s'",
                          equal(symbol->kind, "parameter") ? "parameter" : "variable",
                          symbol->name)};
            PUSH(result, warning);
        }
    }
    for (int i = 0; i < p->functions.count; ++i) {
        Declaration *f = p->functions.items[i];
        if (!symbol_member(reachable, f->symbol)) {
            Warning warning = {f->name.position,
                               ml_format("function '%s' is never called", f->name.spelling)};
            PUSH(result, warning);
        }
        walk_statements(f->body, unreachable_warnings, &result);
    }
    if (result.count > 1)
        qsort(result.items, (size_t)result.count, sizeof(Warning), warning_compare);
    return result;
}
static bool literal(Expr *e) { return equal(e->kind, "integer") || equal(e->kind, "boolean"); }
static bool in_range(int64_t value) { return value >= -2147483648LL && value <= 2147483647LL; }
static Expr *folded_literal(Expr *e, int64_t value) {
    Expr *result = new_expr(e->type == TOY_BOOL ? "boolean" : "integer", e->token);
    result->type = e->type;
    result->value = value;
    return result;
}
static bool constant_binary(const char *op, int64_t a, int64_t b, int64_t *result) {
    if (equal(op, "+") || equal(op, "-") || equal(op, "*")) {
        *result = equal(op, "+") ? a + b : equal(op, "-") ? a - b : a * b;
        return in_range(*result);
    }
    if (equal(op, "/") || equal(op, "%")) {
        if (!b)
            return false;
        int64_t quotient = a / b;
        *result = equal(op, "/") ? quotient : a - quotient * b;
        return equal(op, "%") || in_range(*result);
    }
    bool answer = equal(op, "<")    ? a < b
                  : equal(op, "<=") ? a <= b
                  : equal(op, ">")  ? a > b
                  : equal(op, ">=") ? a >= b
                  : equal(op, "==") ? a == b
                  : equal(op, "!=") ? a != b
                  : equal(op, "&&") ? (a != 0 && b != 0)
                                    : (a != 0 || b != 0);
    *result = answer ? 1 : 0;
    return true;
}
static Expr *fold_expression(Expr *e, int *count) {
    if (!e)
        return NULL;
    for (int i = 0; i < e->children.count; ++i)
        e->children.items[i] = fold_expression(e->children.items[i], count);
    if (equal(e->kind, "unary") && literal(e->children.items[0])) {
        int64_t value = equal(e->token.spelling, "-") ? -e->children.items[0]->value
                                                      : (e->children.items[0]->value == 0);
        if (!in_range(value))
            return e;
        ++*count;
        return folded_literal(e, value);
    }
    if (!equal(e->kind, "binary"))
        return e;
    Expr *left = e->children.items[0];
    Expr *right = e->children.items[1];
    const char *op = e->token.spelling;
    if (literal(left) && literal(right)) {
        int64_t value;
        if (constant_binary(op, left->value, right->value, &value)) {
            ++*count;
            return folded_literal(e, value);
        }
    }
    if (literal(left)) {
        if ((equal(op, "&&") && left->value == 0) || (equal(op, "||") && left->value != 0)) {
            ++*count;
            return folded_literal(e, left->value);
        }
        if ((equal(op, "&&") && left->value != 0) || (equal(op, "||") && left->value == 0) ||
            (equal(op, "+") && left->value == 0) || (equal(op, "*") && left->value == 1)) {
            ++*count;
            return right;
        }
    }
    if (literal(right) &&
        ((equal(op, "+") && right->value == 0) || (equal(op, "-") && right->value == 0) ||
         (equal(op, "*") && right->value == 1) || (equal(op, "/") && right->value == 1) ||
         (equal(op, "&&") && right->value != 0) || (equal(op, "||") && right->value == 0))) {
        ++*count;
        return left;
    }
    return e;
}
static Statement *fold_statement(Statement *s, int *count) {
    if (!s)
        return NULL;
    if (equal(s->kind, "if")) {
        s->condition = fold_expression(s->condition, count);
        if (literal(s->condition)) {
            Statement *replacement = s->condition->value ? fold_statement(s->yes, count)
                                     : s->no             ? fold_statement(s->no, count)
                                                         : new_statement("empty", s->token);
            ++*count;
            return replacement;
        }
        s->yes = fold_statement(s->yes, count);
        s->no = fold_statement(s->no, count);
    } else if (equal(s->kind, "while")) {
        s->condition = fold_expression(s->condition, count);
        if (literal(s->condition) && !s->condition->value) {
            ++*count;
            return new_statement("empty", s->token);
        }
        s->body = fold_statement(s->body, count);
    } else if (equal(s->kind, "for")) {
        s->init = fold_statement(s->init, count);
        s->condition = fold_expression(s->condition, count);
        s->update = fold_statement(s->update, count);
        s->body = fold_statement(s->body, count);
    } else if (equal(s->kind, "block"))
        for (int i = 0; i < s->statements.count; ++i)
            s->statements.items[i] = fold_statement(s->statements.items[i], count);
    else if (equal(s->kind, "declaration"))
        s->declaration->initializer = fold_expression(s->declaration->initializer, count);
    else if (equal(s->kind, "assignment")) {
        s->index = fold_expression(s->index, count);
        s->expr = fold_expression(s->expr, count);
    } else if (equal(s->kind, "call") || equal(s->kind, "return"))
        s->expr = fold_expression(s->expr, count);
    else if (equal(s->kind, "print"))
        for (int i = 0; i < s->expressions.count; ++i)
            s->expressions.items[i] = fold_expression(s->expressions.items[i], count);
    return s;
}
static int fold_program(Program *p, SymbolList reachable) {
    int count = 0;
    for (int i = 0; i < p->globals.count; ++i)
        p->globals.items[i]->initializer =
            fold_expression(p->globals.items[i]->initializer, &count);
    for (int i = 0; i < p->functions.count; ++i)
        if (symbol_member(reachable, p->functions.items[i]->symbol))
            p->functions.items[i]->body = fold_statement(p->functions.items[i]->body, &count);
    return count;
}
static const char *inverse(const char *op) { return equal(op, "JUMPF") ? "JUMPT" : "JUMPF"; }
static bool branch_taken(const char *op, int64_t value) {
    return (equal(op, "JUMPF") && value == 0) || (equal(op, "JUMPT") && value != 0);
}
static void delete_instruction(Unit *unit, int index) {
    memmove(unit->code.items + index, unit->code.items + index + 1,
            (size_t)(unit->code.count - index - 1) * sizeof(Instruction));
    --unit->code.count;
    for (int i = 0; i < unit->code.count; ++i)
        if (jump(unit->code.items[i].op) && unit->code.items[i].a > index)
            --unit->code.items[i].a;
}
static const char *negated(const char *op) {
    const char *names[] = {"LT", "GE", "LE", "GT", "EQ", "NE"};
    for (int i = 0; i < 6; ++i)
        if (equal(op, names[i]))
            return names[i ^ 1];
    return NULL;
}
static void optimize(Unit *unit, int *counts) {
    bool *targets = ml_alloc(((size_t)unit->code.count + 1) * sizeof(*targets));
    while (true) {
        memset(targets, 0, ((size_t)unit->code.count + 1) * sizeof(*targets));
        for (int i = 0; i < unit->code.count; ++i)
            if (jump(unit->code.items[i].op))
                targets[unit->code.items[i].a] = true;
        bool applied = false;
        for (int i = 0; i < unit->code.count; ++i) {
            Instruction a = unit->code.items[i], b = {0};
            bool free = i + 1 < unit->code.count && !targets[i + 1];
            if (i + 1 < unit->code.count)
                b = unit->code.items[i + 1];
            int rule = -1;
            if (equal(a.op, "PUSH") && free && conditional(b.op)) {
                if (branch_taken(b.op, a.a)) {
                    unit->code.items[i] = (Instruction){"JUMP", b.a, 0, b.position, NULL};
                    delete_instruction(unit, i + 1);
                } else {
                    delete_instruction(unit, i + 1);
                    delete_instruction(unit, i);
                }
                rule = 0;
            } else if (negated(a.op) && free && equal(b.op, "NOT")) {
                unit->code.items[i].op = negated(a.op);
                delete_instruction(unit, i + 1);
                rule = 1;
            } else if (equal(a.op, "NOT") && free && conditional(b.op)) {
                unit->code.items[i] = (Instruction){inverse(b.op), b.a, 0, b.position, NULL};
                delete_instruction(unit, i + 1);
                rule = 2;
            } else if (conditional(a.op) && a.a == i + 2 && free && equal(b.op, "JUMP")) {
                unit->code.items[i] = (Instruction){inverse(a.op), b.a, 0, a.position, NULL};
                delete_instruction(unit, i + 1);
                rule = 3;
            } else {
                if (jump(a.op) && a.a < unit->code.count) {
                    int t = (int)a.a;
                    Instruction target = unit->code.items[t];
                    int next = -1;
                    if (equal(target.op, "JUMP"))
                        next = (int)target.a;
                    else if (equal(target.op, "PUSH") && t + 1 < unit->code.count &&
                             conditional(unit->code.items[t + 1].op))
                        next = branch_taken(unit->code.items[t + 1].op, target.a)
                                   ? (int)unit->code.items[t + 1].a
                                   : t + 2;
                    if (next >= 0 && next != t) {
                        unit->code.items[i].a = next;
                        rule = 4;
                    }
                }
                if (rule < 0 && jump(a.op) && a.a == i + 1) {
                    if (equal(a.op, "JUMP"))
                        delete_instruction(unit, i);
                    else
                        unit->code.items[i] = (Instruction){"POP", 0, 0, a.position, NULL};
                    rule = 5;
                }
                if (rule < 0 && transfer(a.op) && free) {
                    delete_instruction(unit, i + 1);
                    rule = 6;
                }
            }
            if (rule >= 0) {
                ++counts[rule];
                applied = true;
                break;
            }
        }
        if (!applied)
            return;
    }
}
static int arrange(UnitList units) {
    int start = 0;
    for (int i = 0; i < units.count; ++i) {
        units.items[i]->start = start;
        start += units.items[i]->code.count;
    }
    for (int i = 0; i < units.count; ++i)
        for (int j = 0; j < units.items[i]->code.count; ++j) {
            Instruction *instruction = &units.items[i]->code.items[j];
            if (equal(instruction->op, "CALL"))
                for (int k = 1; k < units.count; ++k)
                    if (units.items[k]->function == instruction->callee) {
                        instruction->a = units.items[k]->start;
                        break;
                    }
        }
    return start;
}
static int stack_effect(Instruction i) {
    if (word_in("PUSH LOADG LOADL READ", i.op))
        return 1;
    if (word_in("POP STOREG STOREL JUMPF JUMPT RETV ADD SUB MUL DIV MOD LT LE GT GE EQ NE", i.op))
        return -1;
    if (equal(i.op, "STOREA"))
        return -2;
    if (equal(i.op, "CALL"))
        return -(int)i.b + (i.callee->type != TOY_VOID);
    if (equal(i.op, "PRINT"))
        return -(int)i.a;
    return 0;
}
static void analyze_unit(Unit *unit) {
    int n = unit->code.count;
    bool *leaders = ml_alloc((size_t)n * sizeof(*leaders));
    leaders[0] = true;
    for (int i = 0; i < n; ++i) {
        Instruction instruction = unit->code.items[i];
        if (jump(instruction.op) && instruction.a < n)
            leaders[instruction.a] = true;
        if ((jump(instruction.op) || transfer(instruction.op)) && i + 1 < n)
            leaders[i + 1] = true;
    }
    IntList indices = {0};
    for (int i = 0; i < n; ++i)
        if (leaders[i])
            PUSH(indices, i);
    int *block_of = ml_alloc((size_t)n * sizeof(*block_of));
    for (int k = 0; k < indices.count; ++k) {
        int first = indices.items[k],
            last = k + 1 < indices.count ? indices.items[k + 1] - 1 : n - 1;
        for (int i = first; i <= last; ++i)
            block_of[i] = k;
        BasicBlock block = {0};
        block.first = first;
        block.last = last;
        PUSH(unit->blocks, block);
    }
    for (int k = 0; k < unit->blocks.count; ++k) {
        BasicBlock *block = &unit->blocks.items[k];
        Instruction last = unit->code.items[block->last];
        int successors[2], count = 0;
        if (equal(last.op, "JUMP"))
            successors[count++] = (int)last.a;
        else if (conditional(last.op)) {
            successors[count++] = block->last + 1;
            successors[count++] = (int)last.a;
        } else if (!transfer(last.op))
            successors[count++] = block->last + 1;
        for (int i = 0; i < count; ++i)
            if (successors[i] < n) {
                int id = block_of[successors[i]];
                if (!block->successor_count || block->successors[0] != id)
                    block->successors[block->successor_count++] = id;
            }
    }
    int *depths = ml_alloc((size_t)n * sizeof(*depths));
    for (int i = 0; i < n; ++i)
        depths[i] = -1;
    depths[0] = 0;
    IntList queue = {0};
    PUSH(queue, 0);
    for (int head = 0; head < queue.count; ++head) {
        int i = queue.items[head];
        Instruction instruction = unit->code.items[i];
        int depth = depths[i] + stack_effect(instruction);
        if (depth > unit->stack)
            unit->stack = depth;
        int next[2], count = 0;
        if (!transfer(instruction.op) && i + 1 < n)
            next[count++] = i + 1;
        if (jump(instruction.op) && instruction.a < n)
            next[count++] = (int)instruction.a;
        for (int j = 0; j < count; ++j)
            if (depths[next[j]] < 0) {
                depths[next[j]] = depth;
                PUSH(queue, next[j]);
            }
    }
}
static bool recursive_visit(Symbol *current, Symbol *function, SymbolList *seen) {
    PUSH(*seen, current);
    for (int i = 0; i < current->calls.count; ++i) {
        Symbol *callee = current->calls.items[i];
        if (callee == function)
            return true;
        if (!symbol_member(*seen, callee) && recursive_visit(callee, function, seen))
            return true;
    }
    return false;
}
static bool recursive(Symbol *function) {
    SymbolList seen = {0};
    return recursive_visit(function, function, &seen);
}
static char *spelling(Instruction instruction, int start) {
    Text result = {0};
    text_add(&result, instruction.op);
    int64_t a = instruction.a + (jump(instruction.op) ? start : 0);
    if (word_in("PUSH LOADG STOREG LOADL STOREL LOADA STOREA JUMP JUMPF JUMPT CALL ENTER PRINT",
                instruction.op))
        text_add(&result, ml_format(" %lld", (long long)a));
    if (word_in("LOADA STOREA CALL", instruction.op))
        text_add(&result, ml_format(" %lld", (long long)instruction.b));
    return text_value(&result);
}
static int string_compare(const void *left, const void *right) {
    return strcmp(*(char *const *)left, *(char *const *)right);
}
static char *callees(Symbol *function) {
    StringList names = {0};
    for (int i = 0; i < function->calls.count; ++i)
        PUSH(names, (char *)function->calls.items[i]->name);
    if (!names.count)
        return "-";
    if (names.count > 1)
        qsort(names.items, (size_t)names.count, sizeof(char *), string_compare);
    Text result = {0};
    for (int i = 0; i < names.count; ++i) {
        if (i)
            text_char(&result, ',');
        text_add(&result, names.items[i]);
    }
    return text_value(&result);
}
static void listing(FILE *output, Program *p, UnitList before, UnitList after, int before_count,
                    int after_count) {
    if (!p->globals.count)
        fputs("globals: none\n", output);
    else {
        fputs("globals:\n", output);
        for (int i = 0; i < p->globals.count; ++i) {
            Declaration *d = p->globals.items[i];
            fprintf(output, "  %d %s %s\n", d->symbol->address, d->name.spelling,
                    d->array ? ml_format("int[%lld]", (long long)d->size.integer)
                             : type_text(d->type));
        }
    }
    fputs("functions:\n", output);
    for (int i = 0; i < after.count; ++i) {
        Unit *unit = after.items[i];
        char *signature = "";
        char *calls = "main";
        const char *suffix = "";
        if (unit->function) {
            Declaration *f = unit->function;
            Text types = {0};
            for (int j = 0; j < f->parameters.count; ++j) {
                if (j)
                    text_char(&types, ',');
                text_add(&types, type_text(f->parameters.items[j]->type));
            }
            signature = ml_format(" %s(%s)", type_text(f->type), text_value(&types));
            calls = callees(f->symbol);
            if (recursive(f->symbol))
                suffix = " recursive";
        }
        fprintf(
            output, "  %s%s address=%d->%d size=%d->%d slots=%d stack=%d blocks=%d calls=%s%s\n",
            unit->name, signature, before.items[i]->start, unit->start, before.items[i]->code.count,
            unit->code.count, unit->slots, unit->stack, unit->blocks.count, calls, suffix);
        if (unit->function)
            for (int j = 0; j < unit->function->slots.count; ++j) {
                Symbol *symbol = unit->function->slots.items[j];
                fprintf(output, "    slot %d %s %s\n", j, symbol->name, type_text(symbol->type));
            }
    }
    fputs("references:\n", output);
    for (int pass = 0; pass < 2; ++pass) {
        DeclarationList declarations = pass ? p->functions : p->globals;
        for (int i = 0; i < declarations.count; ++i) {
            Declaration *d = declarations.items[i];
            bool lines[1001] = {0};
            for (int j = 0; j < d->symbol->reference_lines.count; ++j)
                lines[d->symbol->reference_lines.items[j]] = true;
            fprintf(output, "  %s defined %d used", d->name.spelling, d->name.position.line);
            bool any = false;
            for (int j = 1; j <= 1000; ++j)
                if (lines[j]) {
                    fprintf(output, " %d", j);
                    any = true;
                }
            if (!any)
                fputs(" -", output);
            fputc('\n', output);
        }
    }
    for (int pass = 0; pass < 2; ++pass) {
        UnitList units = pass ? after : before;
        fprintf(output, "%s peephole: %d instructions\n", pass ? "after" : "before",
                pass ? after_count : before_count);
        for (int i = 0; i < units.count; ++i) {
            Unit *unit = units.items[i];
            fprintf(output, "%s:\n", unit->name);
            for (int j = 0; j < unit->code.count; ++j)
                fprintf(output, "%5d  %s\n", unit->start + j,
                        spelling(unit->code.items[j], unit->start));
        }
    }
    fputs("control flow:\n", output);
    for (int i = 0; i < after.count; ++i) {
        Unit *unit = after.items[i];
        fprintf(output, "  %s\n", unit->name);
        for (int k = 0; k < unit->blocks.count; ++k) {
            BasicBlock block = unit->blocks.items[k];
            fprintf(output, "    B%d %d-%d", k, unit->start + block.first,
                    unit->start + block.last);
            if (block.successor_count) {
                fputs(" ->", output);
                for (int j = 0; j < block.successor_count; ++j)
                    fprintf(output, " B%d", block.successors[j]);
            }
            fputc('\n', output);
        }
    }
}
typedef struct {
    const char *name;
    int count, id;
} Ranked;
typedef struct {
    Ranked *items;
    int count, capacity;
} RankList;
static int rank_name_compare(const void *left, const void *right) {
    const Ranked *a = left;
    const Ranked *b = right;
    return a->count != b->count ? b->count - a->count : strcmp(a->name, b->name);
}
static int rank_id_compare(const void *left, const void *right) {
    const Ranked *a = left;
    const Ranked *b = right;
    return a->count != b->count ? b->count - a->count : a->id - b->id;
}
static void rank_increment(RankList *list, const char *name, int count) {
    for (int i = 0; i < list->count; ++i)
        if (equal(list->items[i].name, name)) {
            list->items[i].count += count;
            return;
        }
    Ranked record = {name, count, 0};
    PUSH(*list, record);
}
typedef struct {
    const char *from, *to;
    int count;
} PairRow;
typedef struct {
    PairRow *items;
    int count, capacity;
} PairRows;
static int pair_compare(const void *left, const void *right) {
    const PairRow *a = left;
    const PairRow *b = right;
    if (a->count != b->count)
        return b->count - a->count;
    int order = strcmp(a->from, b->from);
    return order ? order : strcmp(a->to, b->to);
}
static int sum_rules(const int *rules) {
    int result = 0;
    for (int i = 0; i < 7; ++i)
        result += rules[i];
    return result;
}
static bool same_behavior(RunResult *a, RunResult *b) {
    if ((a->error != NULL) != (b->error != NULL))
        return false;
    if (a->error && !equal(a->error, b->error))
        return false;
    if (a->output.count != b->output.count)
        return false;
    for (int i = 0; i < a->output.count; ++i)
        if (!equal(a->output.items[i], b->output.items[i]))
            return false;
    return true;
}
static void statistics(FILE *output, UnitList units, int before_count, int after_count, int folds,
                       const int *rules, RunResult *run, RunResult *comparison) {
    fprintf(output, "code: %d -> %d\nfolds: %d\npeephole: %d\n", before_count, after_count, folds,
            sum_rules(rules));
    for (int i = 0; i < 7; ++i)
        fprintf(output, "  %s %d\n", rule_names[i], rules[i]);
    fprintf(
        output,
        "executed: %d\nexecuted before peephole: %d\nbehaviour: %s\nmax call depth: %d\nmax stack: %d\nopcodes:\n",
        run->executed, comparison->executed, same_behavior(run, comparison) ? "same" : "different",
        run->maximum_depth, run->maximum_stack);
    ExecutableList code = flatten(units);
    RankList opcodes = {0}, functions = {0};
    int *function_counts = ml_alloc((size_t)units.count * sizeof(int));
    int line_counts[1001] = {0};
    bool line_code[1001] = {0};
    for (int pc = 0; pc < code.count; ++pc) {
        Executable current = code.items[pc];
        int count = run->counts[pc];
        rank_increment(&opcodes, current.instruction.op, count);
        if (units.items[current.unit]->function)
            function_counts[current.unit] += count;
        line_counts[current.instruction.position.line] += count;
        line_code[current.instruction.position.line] = true;
    }
    if (opcodes.count > 1)
        qsort(opcodes.items, (size_t)opcodes.count, sizeof(Ranked), rank_name_compare);
    for (int i = 0; i < opcodes.count; ++i)
        if (opcodes.items[i].count)
            fprintf(output, "  %s %d\n", opcodes.items[i].name, opcodes.items[i].count);
    fputs("functions:\n", output);
    for (int i = 1; i < units.count; ++i) {
        Ranked record = {units.items[i]->name, function_counts[i], i};
        PUSH(functions, record);
    }
    if (functions.count > 1)
        qsort(functions.items, (size_t)functions.count, sizeof(Ranked), rank_name_compare);
    for (int i = 0; i < functions.count; ++i) {
        Ranked record = functions.items[i];
        fprintf(output, "  %s calls=%d executed=%d\n", record.name, run->calls[record.id],
                record.count);
    }
    fputs("calls:\n", output);
    PairRows pairs = {0};
    for (int i = 0; i < run->pairs.count; ++i) {
        CallPair pair = run->pairs.items[i];
        PairRow row = {units.items[pair.from]->name, units.items[pair.to]->name, pair.count};
        PUSH(pairs, row);
    }
    if (pairs.count > 1)
        qsort(pairs.items, (size_t)pairs.count, sizeof(PairRow), pair_compare);
    for (int i = 0; i < pairs.count; ++i)
        fprintf(output, "  %s -> %s %d\n", pairs.items[i].from, pairs.items[i].to,
                pairs.items[i].count);
    RankList positive = {0};
    IntList negative = {0};
    int lines = 0;
    for (int i = 1; i <= 1000; ++i)
        if (line_code[i]) {
            ++lines;
            if (line_counts[i]) {
                Ranked record = {NULL, line_counts[i], i};
                PUSH(positive, record);
            } else
                PUSH(negative, i);
        }
    if (positive.count > 1)
        qsort(positive.items, (size_t)positive.count, sizeof(Ranked), rank_id_compare);
    fputs("hot lines:\n", output);
    for (int i = 0; i < positive.count && i < 5; ++i)
        fprintf(output, "  line %d: %d\n", positive.items[i].id, positive.items[i].count);
    fprintf(output, "coverage: %d of %d lines\nnot executed:", positive.count, lines);
    if (!negative.count)
        fputs(" none", output);
    else
        for (int i = 0; i < negative.count; ++i)
            fprintf(output, " %d", negative.items[i]);
    fputs("\nhot spots:\n", output);
    RankList pcs = {0};
    for (int pc = 0; pc < code.count; ++pc)
        if (run->counts[pc]) {
            Ranked record = {NULL, run->counts[pc], pc};
            PUSH(pcs, record);
        }
    if (pcs.count > 1)
        qsort(pcs.items, (size_t)pcs.count, sizeof(Ranked), rank_id_compare);
    for (int i = 0; i < pcs.count && i < 5; ++i) {
        int pc = pcs.items[i].id;
        fprintf(output, "  pc=%d count=%d %s\n", pc, run->counts[pc],
                spelling(code.items[pc].instruction, 0));
    }
}
static void position_display(FILE *output, Position position, StringList lines) {
    fprintf(output, "  %s\n", lines.items[position.line - 1]);
    for (int i = 0; i < position.column + 1; ++i)
        fputc(' ', output);
    fputs("^\n", output);
}
static void runtime_diagnostics(FILE *output, UnitList units, RunResult *run, StringList lines) {
    ExecutableList code = flatten(units);
    Executable instruction = code.items[run->fault_pc];
    fprintf(output, "runtime error %s: %s in %s\n", position_text(instruction.instruction.position),
            run->error, units.items[instruction.unit]->name);
    position_display(output, instruction.instruction.position, lines);
    int count = run->returns.count > 0 ? run->returns.count - 1 : 0, shown = 0;
    for (int i = run->returns.count - 1; i >= 1 && shown < 5; --i) {
        Executable caller = code.items[run->returns.items[i] - 1];
        fprintf(output, "  called from %s at %s\n", units.items[caller.unit]->name,
                position_text(caller.instruction.position));
        ++shown;
    }
    if (count > shown)
        fprintf(output, "  ... %d more\n", count - shown);
}
static StringList read_lines(const char *path) {
    StringList result = {0};
    FILE *input = fopen(path, "r");
    if (!input)
        return result;
    Text line = {0};
    int c;
    while ((c = fgetc(input)) != EOF) {
        if (c == '\n') {
            char *value = text_value(&line);
            PUSH(result, value);
            line = (Text){0};
        } else
            text_char(&line, (char)c);
    }
    fclose(input);
    return result;
}
typedef struct {
    const char *values[5];
} TableRow;
typedef struct {
    TableRow *items;
    int count, capacity;
} Table;
int main(void) {
    StringList lines = read_lines("input/program.src");
    SourceList programs = {0};
    for (int i = 0; i < lines.count; ++i) {
        if (strncmp(lines.items[i], "#program ", 9) == 0) {
            Source source = {0};
            source.name = lines.items[i] + 9;
            source.first_line = i + 2;
            PUSH(programs, source);
        } else
            PUSH(programs.items[programs.count - 1].lines, lines.items[i]);
    }
    StringList input_lines = read_lines("input/input.txt");
    Source *current = NULL;
    for (int i = 0; i < input_lines.count; ++i) {
        const char *line = input_lines.items[i];
        if (strncmp(line, "#input ", 7) == 0) {
            current = NULL;
            for (int j = 0; j < programs.count; ++j)
                if (equal(programs.items[j].name, line + 7))
                    current = &programs.items[j];
        } else {
            const char *at = line;
            while (*at) {
                char *end;
                int64_t value = strtoll(at, &end, 10);
                PUSH(current->input, value);
                at = *end ? end + 1 : end;
            }
        }
    }
    mkdir("output", 0777);
    FILE *listing_output = fopen("output/listing.txt", "w");
    FILE *value_output = fopen("output/output.txt", "w");
    FILE *diagnostics = fopen("output/diagnostics.txt", "w");
    FILE *stats = fopen("output/stats.txt", "w");
    if (!listing_output || !value_output || !diagnostics || !stats) {
        ml_cleanup();
        return 1;
    }
    int compiled = 0, runtime_errors = 0, total_folds = 0, total_executed = 0, lexical_errors = 0,
        syntax_errors = 0, semantic_errors = 0, total_rules[7] = {0};
    Table table = {0};
    TableRow header = {{"program", "status", "code", "executed", "output"}};
    PUSH(table, header);
    for (int program_index = 0; program_index < programs.count; ++program_index) {
        Source *source = &programs.items[program_index];
        fprintf(listing_output, "== program %s ==\n", source->name);
        fprintf(value_output, "== program %s ==\n", source->name);
        fprintf(diagnostics, "== program %s ==\n", source->name);
        fprintf(stats, "== program %s ==\n", source->name);
        CompileContext *context = ml_alloc(sizeof(*context));
        if (setjmp(context->jump)) {
            if (equal(context->kind, "lexical"))
                ++lexical_errors;
            else if (equal(context->kind, "syntax"))
                ++syntax_errors;
            else
                ++semantic_errors;
            fputs("not compiled\n", listing_output);
            fputs("not compiled\n", stats);
            fprintf(diagnostics, "%s error %s: %s\n", context->kind,
                    position_text(context->position), context->message);
            position_display(diagnostics, context->position, lines);
            fputs("status: compile error\n", diagnostics);
            TableRow row = {{source->name, ml_format("%s error", context->kind), "-", "-", "-"}};
            PUSH(table, row);
            continue;
        }
        Parser parser = {0};
        parser.tokens = tokenize(source->lines, source->first_line, context);
        parser.context = context;
        Program *p = parse(&parser);
        Semantics semantics = {0};
        semantics.program = p;
        semantics.context = context;
        analyze(&semantics);
        ++compiled;
        SymbolList reachable = reachable_functions(p);
        WarningList warnings = collect_warnings(p, reachable);
        for (int i = 0; i < warnings.count; ++i)
            fprintf(diagnostics, "warning %s: %s\n", position_text(warnings.items[i].position),
                    warnings.items[i].message);
        int folds = fold_program(p, reachable);
        Generation generated = generate(p, reachable);
        UnitList before = generated.units;
        int before_count = arrange(before);
        UnitList after = {0};
        int rules[7] = {0};
        for (int i = 0; i < before.count; ++i) {
            Unit *original = before.items[i];
            Unit *unit = ml_alloc(sizeof(*unit));
            unit->name = original->name;
            unit->function = original->function;
            unit->slots = original->slots;
            for (int j = 0; j < original->code.count; ++j)
                PUSH(unit->code, original->code.items[j]);
            optimize(unit, rules);
            analyze_unit(unit);
            PUSH(after, unit);
        }
        int after_count = arrange(after);
        listing(listing_output, p, before, after, before_count, after_count);
        RunResult *run = execute(after, generated.cells, source->input);
        RunResult *comparison = execute(before, generated.cells, source->input);
        for (int i = 0; i < run->output.count; ++i)
            fprintf(value_output, "%s\n", run->output.items[i]);
        const char *status = "ok";
        if (run->error) {
            ++runtime_errors;
            status = "runtime error";
            runtime_diagnostics(diagnostics, after, run, lines);
        }
        fprintf(diagnostics, "status: %s\n", status);
        statistics(stats, after, before_count, after_count, folds, rules, run, comparison);
        total_folds += folds;
        total_executed += run->executed;
        for (int i = 0; i < 7; ++i)
            total_rules[i] += rules[i];
        TableRow row = {{source->name, status, ml_format("%d", after_count),
                         ml_format("%d", run->executed), ml_format("%d", run->output.count)}};
        PUSH(table, row);
    }
    fprintf(
        stats,
        "== summary ==\nprograms: %d\ncompiled: %d\ncompile errors: lexical %d syntax %d semantic %d\nruntime errors: %d\nfolds: %d\npeephole: %d\n",
        programs.count, compiled, lexical_errors, syntax_errors, semantic_errors, runtime_errors,
        total_folds, sum_rules(total_rules));
    for (int i = 0; i < 7; ++i)
        fprintf(stats, "  %s %d\n", rule_names[i], total_rules[i]);
    fprintf(stats, "executed: %d\n", total_executed);
    size_t widths[5] = {0};
    for (int i = 0; i < table.count; ++i)
        for (int j = 0; j < 5; ++j) {
            size_t length = strlen(table.items[i].values[j]);
            if (length > widths[j])
                widths[j] = length;
        }
    for (int i = 0; i < table.count; ++i) {
        fputs("  ", stats);
        for (int j = 0; j < 5; ++j) {
            if (j)
                fputs("  ", stats);
            const char *value = table.items[i].values[j];
            size_t padding = widths[j] - strlen(value);
            if (j >= 2)
                for (size_t k = 0; k < padding; ++k)
                    fputc(' ', stats);
            fputs(value, stats);
            if (j < 2)
                for (size_t k = 0; k < padding; ++k)
                    fputc(' ', stats);
        }
        fputc('\n', stats);
    }
    fclose(listing_output);
    fclose(value_output);
    fclose(diagnostics);
    fclose(stats);
    ml_cleanup();
    return 0;
}
