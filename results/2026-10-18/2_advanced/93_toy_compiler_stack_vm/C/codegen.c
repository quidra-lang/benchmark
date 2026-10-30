#include "compiler.h"
bool jump(const char *op) { return word_in("JUMP JUMPF JUMPT", op); }
bool conditional(const char *op) { return equal(op, "JUMPF") || equal(op, "JUMPT"); }
bool transfer(const char *op) { return word_in("JUMP RET RETV HALT", op); }
static void emit(Generator *g, const char *op, int64_t a, int64_t b, Position pos,
                 Declaration *callee) {
    Instruction instruction = {op, a, b, pos, callee};
    PUSH(g->unit->code, instruction);
}
static int label(Generator *g) {
    int id = g->labels.count;
    PUSH(g->labels, -1);
    return id;
}
static void place(Generator *g, int id) { g->labels.items[id] = g->unit->code.count; }
static void to(Generator *g, const char *op, int id, Position pos) {
    emit(g, op, id, 0, pos, NULL);
}
static void patch(Generator *g) {
    for (int i = 0; i < g->unit->code.count; ++i)
        if (jump(g->unit->code.items[i].op))
            g->unit->code.items[i].a = g->labels.items[g->unit->code.items[i].a];
}
static void expression(Generator *g, Expr *e) {
    Position pos = e->token.position;
    if (equal(e->kind, "integer") || equal(e->kind, "boolean"))
        emit(g, "PUSH", e->value, 0, pos, NULL);
    else if (equal(e->kind, "read"))
        emit(g, "READ", 0, 0, pos, NULL);
    else if (equal(e->kind, "variable")) {
        Symbol *s = e->referent;
        bool global = equal(s->kind, "global");
        emit(g, global ? "LOADG" : "LOADL", global ? s->address : s->slot, 0, pos, NULL);
    } else if (equal(e->kind, "array")) {
        expression(g, e->children.items[0]);
        emit(g, "LOADA", e->referent->address, e->referent->size, pos, NULL);
    } else if (equal(e->kind, "call")) {
        for (int i = 0; i < e->children.count; ++i)
            expression(g, e->children.items[i]);
        emit(g, "CALL", 0, e->children.count, pos, e->referent->declaration);
    } else if (equal(e->kind, "unary")) {
        expression(g, e->children.items[0]);
        emit(g, equal(e->token.spelling, "-") ? "NEG" : "NOT", 0, 0, pos, NULL);
    } else if (equal(e->kind, "binary")) {
        const char *op = e->token.spelling;
        if (equal(op, "&&") || equal(op, "||")) {
            int first = label(g);
            int last = label(g);
            expression(g, e->children.items[0]);
            to(g, equal(op, "&&") ? "JUMPF" : "JUMPT", first, pos);
            expression(g, e->children.items[1]);
            to(g, "JUMP", last, pos);
            place(g, first);
            emit(g, "PUSH", equal(op, "||"), 0, pos, NULL);
            place(g, last);
        } else {
            expression(g, e->children.items[0]);
            expression(g, e->children.items[1]);
            const char *operators[] = {"+", "-", "*", "/", "%", "<", "<=", ">", ">=", "==", "!="};
            const char *names[] = {"ADD", "SUB", "MUL", "DIV", "MOD", "LT",
                                   "LE",  "GT",  "GE",  "EQ",  "NE"};
            for (int i = 0; i < 11; ++i)
                if (equal(op, operators[i])) {
                    emit(g, names[i], 0, 0, pos, NULL);
                    break;
                }
        }
    }
}
static void statement(Generator *g, Statement *s) {
    if (!s)
        return;
    Position pos = s->token.position;
    if (equal(s->kind, "declaration")) {
        Declaration *d = s->declaration;
        if (d->initializer)
            expression(g, d->initializer);
        else
            emit(g, "PUSH", 0, 0, d->name.position, NULL);
        emit(g, "STOREL", d->symbol->slot, 0, d->name.position, NULL);
    } else if (equal(s->kind, "assignment")) {
        Symbol *symbol = s->referent;
        if (s->index) {
            expression(g, s->index);
            expression(g, s->expr);
            emit(g, "STOREA", symbol->address, symbol->size, pos, NULL);
        } else {
            expression(g, s->expr);
            bool global = equal(symbol->kind, "global");
            emit(g, global ? "STOREG" : "STOREL", global ? symbol->address : symbol->slot, 0, pos,
                 NULL);
        }
    } else if (equal(s->kind, "call")) {
        expression(g, s->expr);
        if (s->expr->type != TOY_VOID)
            emit(g, "POP", 0, 0, pos, NULL);
    } else if (equal(s->kind, "print")) {
        for (int i = 0; i < s->expressions.count; ++i)
            expression(g, s->expressions.items[i]);
        emit(g, "PRINT", s->expressions.count, 0, pos, NULL);
    } else if (equal(s->kind, "return")) {
        if (s->expr)
            expression(g, s->expr);
        emit(g, s->expr ? "RETV" : "RET", 0, 0, pos, NULL);
    } else if (equal(s->kind, "block"))
        for (int i = 0; i < s->statements.count; ++i)
            statement(g, s->statements.items[i]);
    else if (equal(s->kind, "if")) {
        int other = label(g);
        expression(g, s->condition);
        to(g, "JUMPF", other, pos);
        statement(g, s->yes);
        if (s->no) {
            int last = label(g);
            to(g, "JUMP", last, pos);
            place(g, other);
            statement(g, s->no);
            place(g, last);
        } else
            place(g, other);
    } else if (equal(s->kind, "while")) {
        int first = label(g);
        int last = label(g);
        place(g, first);
        expression(g, s->condition);
        to(g, "JUMPF", last, pos);
        Loop loop = {last, first};
        PUSH(g->loops, loop);
        statement(g, s->body);
        --g->loops.count;
        to(g, "JUMP", first, pos);
        place(g, last);
    } else if (equal(s->kind, "for")) {
        int first = label(g);
        int update = label(g);
        int last = label(g);
        statement(g, s->init);
        place(g, first);
        if (s->condition) {
            expression(g, s->condition);
            to(g, "JUMPF", last, pos);
        }
        Loop loop = {last, update};
        PUSH(g->loops, loop);
        statement(g, s->body);
        --g->loops.count;
        place(g, update);
        statement(g, s->update);
        to(g, "JUMP", first, pos);
        place(g, last);
    } else if (equal(s->kind, "break") || equal(s->kind, "continue")) {
        Loop loop = g->loops.items[g->loops.count - 1];
        to(g, "JUMP", equal(s->kind, "break") ? loop.leave : loop.again, pos);
    }
}
void walk_statements(Statement *s, void (*visit)(Statement *, void *), void *context) {
    if (!s)
        return;
    visit(s, context);
    for (int i = 0; i < s->statements.count; ++i)
        walk_statements(s->statements.items[i], visit, context);
    Statement *extra[] = {s->yes, s->no, s->body, s->init, s->update};
    for (int i = 0; i < 5; ++i)
        walk_statements(extra[i], visit, context);
}
static void local_collect(Statement *s, void *context) {
    if (equal(s->kind, "declaration")) {
        DeclarationList *locals = context;
        PUSH(*locals, s->declaration);
    }
}
static int local_compare(const void *left, const void *right) {
    Declaration *a = *(Declaration *const *)left;
    Declaration *b = *(Declaration *const *)right;
    if (earlier(a->name.position, b->name.position))
        return -1;
    return earlier(b->name.position, a->name.position) ? 1 : 0;
}
Generation generate(Program *p, SymbolList reachable) {
    Generation result = {0};
    for (int i = 0; i < p->globals.count; ++i) {
        Declaration *d = p->globals.items[i];
        d->symbol->address = result.cells;
        result.cells += d->array ? (int)d->size.integer : 1;
    }
    Unit *init = ml_alloc(sizeof(*init));
    init->name = "<init>";
    Generator g = {0};
    g.unit = init;
    for (int i = 0; i < p->globals.count; ++i) {
        Declaration *d = p->globals.items[i];
        if (d->initializer) {
            expression(&g, d->initializer);
            emit(&g, "STOREG", d->symbol->address, 0, d->name.position, NULL);
        }
    }
    Declaration *main = name_lookup(p->names, "main")->declaration;
    emit(&g, "CALL", 0, 0, main->name.position, main);
    emit(&g, "HALT", 0, 0, main->name.position, NULL);
    patch(&g);
    PUSH(result.units, init);
    for (int i = 0; i < p->functions.count; ++i) {
        Declaration *f = p->functions.items[i];
        if (!symbol_member(reachable, f->symbol))
            continue;
        for (int j = 0; j < f->parameters.count; ++j)
            PUSH(f->slots, f->parameters.items[j]->symbol);
        DeclarationList locals = {0};
        walk_statements(f->body, local_collect, &locals);
        if (locals.count > 1)
            qsort(locals.items, (size_t)locals.count, sizeof(Declaration *), local_compare);
        for (int j = 0; j < locals.count; ++j)
            PUSH(f->slots, locals.items[j]->symbol);
        for (int j = 0; j < f->slots.count; ++j)
            f->slots.items[j]->slot = j;
        Unit *unit = ml_alloc(sizeof(*unit));
        unit->name = f->name.spelling;
        unit->function = f;
        unit->slots = f->slots.count;
        Generator function = {0};
        function.unit = unit;
        emit(&function, "ENTER", unit->slots, 0, f->name.position, NULL);
        statement(&function, f->body);
        if (f->type == TOY_VOID)
            emit(&function, "RET", 0, 0, f->body->close.position, NULL);
        patch(&function);
        PUSH(result.units, unit);
    }
    return result;
}
