#include "compiler.h"
const char *type_text(ToyType type) {
    return type == TOY_INT ? "int" : type == TOY_BOOL ? "bool" : "void";
}
NameEntry *name_add(NameEntry *names, const char *name, Symbol *symbol) {
    NameEntry *result = ml_alloc(sizeof(*result));
    result->name = name;
    result->symbol = symbol;
    result->next = names;
    return result;
}
Symbol *name_lookup(NameEntry *names, const char *name) {
    for (; names; names = names->next)
        if (equal(names->name, name))
            return names->symbol;
    return NULL;
}
bool symbol_member(SymbolList list, Symbol *symbol) {
    for (int i = 0; i < list.count; ++i)
        if (list.items[i] == symbol)
            return true;
    return false;
}
static void error(Semantics *s, Position pos, const char *message) {
    compile_fail(s->context, "semantic", pos, message);
}
static Symbol *symbol(Semantics *s, Declaration *d, const char *kind) {
    Symbol *result = ml_alloc(sizeof(*result));
    result->name = d->name.spelling;
    result->type = d->type;
    result->kind = kind;
    result->declaration = d;
    result->array = d->array;
    result->size = (int)d->size.integer;
    d->symbol = result;
    PUSH(s->program->symbols, result);
    return result;
}
static Symbol *lookup(Semantics *s, Token token, bool read) {
    Symbol *result = NULL;
    for (Scope *at = s->scope; at; at = at->parent) {
        result = name_lookup(at->names, token.spelling);
        if (result)
            break;
    }
    if (!result)
        result = name_lookup(s->program->names, token.spelling);
    if (result) {
        PUSH(result->reference_lines, token.position.line);
        if (read)
            ++result->reads;
    }
    return result;
}
static Symbol *variable(Semantics *s, Token token, bool array, bool read) {
    Symbol *result = lookup(s, token, read);
    const char *name = token.spelling;
    if (!result)
        error(s, token.position, ml_format("undeclared identifier '%s'", name));
    if (equal(result->kind, "function"))
        error(s, token.position, ml_format("'%s' is a function, not a variable", name));
    if (array && !result->array)
        error(s, token.position, ml_format("'%s' is not an array", name));
    if (!array && result->array)
        error(s, token.position, ml_format("array '%s' used without index", name));
    return result;
}
static ToyType expression(Semantics *s, Expr *e, bool statement) {
    ToyType type = TOY_INT;
    const char *name = e->token.spelling;
    Position pos = e->token.position;
    if (equal(e->kind, "integer") || equal(e->kind, "read"))
        type = TOY_INT;
    else if (equal(e->kind, "boolean"))
        type = TOY_BOOL;
    else if (equal(e->kind, "variable")) {
        e->referent = variable(s, e->token, false, true);
        type = e->referent->type;
    } else if (equal(e->kind, "array")) {
        e->referent = variable(s, e->token, true, true);
        if (expression(s, e->children.items[0], false) != TOY_INT)
            error(s, pos, ml_format("index of '%s' must be int", name));
        type = TOY_INT;
    } else if (equal(e->kind, "call")) {
        Symbol *found = lookup(s, e->token, true);
        if (!found)
            error(s, pos, ml_format("undeclared function '%s'", name));
        if (!equal(found->kind, "function"))
            error(s, pos, ml_format("'%s' is not a function", name));
        e->referent = found;
        if (s->function && !symbol_member(s->function->symbol->calls, found))
            PUSH(s->function->symbol->calls, found);
        DeclarationList params = found->declaration->parameters;
        if (params.count != e->children.count)
            error(s, pos,
                  ml_format("wrong number of arguments to '%s' (expected %d, found %d)", name,
                            params.count, e->children.count));
        for (int i = 0; i < params.count; ++i)
            if (expression(s, e->children.items[i], false) != params.items[i]->type)
                error(s, pos,
                      ml_format("argument %d of '%s' must be %s", i + 1, name,
                                type_text(params.items[i]->type)));
        if (!statement && found->type == TOY_VOID)
            error(s, pos, ml_format("void function '%s' used as a value", name));
        type = found->type;
    } else if (equal(e->kind, "unary")) {
        type = expression(s, e->children.items[0], false);
        ToyType required = equal(e->token.spelling, "-") ? TOY_INT : TOY_BOOL;
        if (type != required)
            error(s, pos,
                  ml_format("operator '%s' requires %s operand", e->token.spelling,
                            type_text(required)));
    } else if (equal(e->kind, "binary")) {
        ToyType left = expression(s, e->children.items[0], false);
        ToyType right = expression(s, e->children.items[1], false);
        const char *op = e->token.spelling;
        if (word_in("+ - * / % < <= > >=", op)) {
            if (left != TOY_INT || right != TOY_INT)
                error(s, pos, ml_format("operator '%s' requires int operands", op));
            type = word_in("< <= > >=", op) ? TOY_BOOL : TOY_INT;
        } else if (equal(op, "==") || equal(op, "!=")) {
            if (left != right)
                error(s, pos, ml_format("operator '%s' requires operands of the same type", op));
            type = TOY_BOOL;
        } else {
            if (left != TOY_BOOL || right != TOY_BOOL)
                error(s, pos, ml_format("operator '%s' requires bool operands", op));
            type = TOY_BOOL;
        }
    }
    e->type = type;
    return type;
}
bool can_complete(Statement *s) {
    if (word_in("return break continue", s->kind))
        return false;
    if (equal(s->kind, "block")) {
        for (int i = 0; i < s->statements.count; ++i)
            if (!can_complete(s->statements.items[i]))
                return false;
        return true;
    }
    if (equal(s->kind, "if"))
        return !s->no || can_complete(s->yes) || can_complete(s->no);
    return true;
}
static void open_scope(Semantics *s) {
    Scope *next = ml_alloc(sizeof(*next));
    next->parent = s->scope;
    s->scope = next;
}
static void declaration(Semantics *s, Declaration *d) {
    const char *name = d->name.spelling;
    Position pos = d->name.position;
    if (d->type == TOY_VOID)
        error(s, pos, ml_format("variable '%s' cannot have type void", name));
    if (name_lookup(s->scope->names, name))
        error(s, pos, ml_format("redeclaration of '%s'", name));
    if (d->initializer && expression(s, d->initializer, false) != d->type)
        error(s, pos, ml_format("type mismatch in initialization of '%s'", name));
    s->scope->names = name_add(s->scope->names, name, symbol(s, d, "local"));
}
static void statement(Semantics *s, Statement *n) {
    Position pos = n->token.position;
    if (equal(n->kind, "declaration"))
        declaration(s, n->declaration);
    else if (equal(n->kind, "assignment")) {
        const char *name = n->token.spelling;
        n->referent = variable(s, n->token, n->index != NULL, false);
        if (n->index && expression(s, n->index, false) != TOY_INT)
            error(s, pos, ml_format("index of '%s' must be int", name));
        if (expression(s, n->expr, false) != n->referent->type)
            error(s, pos, ml_format("type mismatch in assignment to '%s'", name));
    } else if (equal(n->kind, "call"))
        expression(s, n->expr, true);
    else if (equal(n->kind, "if") || equal(n->kind, "while")) {
        if (expression(s, n->condition, false) != TOY_BOOL)
            error(s, pos, ml_format("condition of '%s' must be bool", n->kind));
        if (equal(n->kind, "if")) {
            statement(s, n->yes);
            if (n->no)
                statement(s, n->no);
        } else {
            ++s->loops;
            statement(s, n->body);
            --s->loops;
        }
    } else if (equal(n->kind, "for")) {
        open_scope(s);
        if (n->init)
            statement(s, n->init);
        if (n->condition && expression(s, n->condition, false) != TOY_BOOL)
            error(s, pos, "condition of 'for' must be bool");
        if (n->update)
            statement(s, n->update);
        ++s->loops;
        statement(s, n->body);
        --s->loops;
        s->scope = s->scope->parent;
    } else if (equal(n->kind, "break") || equal(n->kind, "continue")) {
        if (!s->loops)
            error(s, pos, ml_format("'%s' outside loop", n->kind));
    } else if (equal(n->kind, "return")) {
        const char *name = s->function->name.spelling;
        if (s->function->type == TOY_VOID) {
            if (n->expr)
                error(s, pos, ml_format("function '%s' must not return a value", name));
        } else {
            if (!n->expr)
                error(s, pos, ml_format("function '%s' must return a value", name));
            if (expression(s, n->expr, false) != s->function->type)
                error(s, pos,
                      ml_format("return value of '%s' must be %s", name,
                                type_text(s->function->type)));
        }
    } else if (equal(n->kind, "print")) {
        for (int i = 0; i < n->expressions.count; ++i)
            if (expression(s, n->expressions.items[i], false) != TOY_INT)
                error(s, pos, ml_format("argument %d of 'print' must be int", i + 1));
    } else if (equal(n->kind, "block")) {
        open_scope(s);
        for (int i = 0; i < n->statements.count; ++i)
            statement(s, n->statements.items[i]);
        s->scope = s->scope->parent;
    }
}
static Expr *first_nonconstant(Expr *e) {
    Expr *first = word_in("variable array call read", e->kind) ? e : NULL;
    for (int i = 0; i < e->children.count; ++i) {
        Expr *candidate = first_nonconstant(e->children.items[i]);
        if (candidate && (!first || earlier(candidate->token.position, first->token.position)))
            first = candidate;
    }
    return first;
}
void analyze(Semantics *s) {
    Program *p = s->program;
    for (int i = 0; i < p->declarations.count; ++i) {
        Declaration *d = p->declarations.items[i];
        const char *name = d->name.spelling;
        Position pos = d->name.position;
        if (!d->function) {
            if (d->array) {
                if (d->type != TOY_INT)
                    error(s, pos, ml_format("array '%s' must have element type int", name));
                if (d->size.integer == 0)
                    error(s, d->size.position,
                          ml_format("array '%s' must have a positive size", name));
            } else if (d->type == TOY_VOID)
                error(s, pos, ml_format("variable '%s' cannot have type void", name));
        }
        if (name_lookup(p->names, name))
            error(s, pos, ml_format("redeclaration of '%s'", name));
        if (d->function) {
            for (int j = 0; j < d->parameters.count; ++j) {
                Declaration *param = d->parameters.items[j];
                const char *pname = param->name.spelling;
                if (param->type == TOY_VOID)
                    error(s, param->name.position,
                          ml_format("parameter '%s' cannot have type void", pname));
                for (int k = 0; k < j; ++k)
                    if (equal(pname, d->parameters.items[k]->name.spelling))
                        error(s, param->name.position, ml_format("redeclaration of '%s'", pname));
            }
            p->names = name_add(p->names, name, symbol(s, d, "function"));
        } else {
            if (d->initializer) {
                Expr *first = first_nonconstant(d->initializer);
                if (first)
                    error(s, first->token.position, "global initializer must be constant");
                if (expression(s, d->initializer, false) != d->type)
                    error(s, pos, ml_format("type mismatch in initialization of '%s'", name));
            }
            p->names = name_add(p->names, name, symbol(s, d, "global"));
        }
    }
    Symbol *main = name_lookup(p->names, "main");
    if (!main || !equal(main->kind, "function"))
        error(s, p->end.position, "no main function");
    if (main->type != TOY_VOID || main->declaration->parameters.count)
        error(s, main->declaration->name.position, "main must be declared as 'void main()'");
    for (int i = 0; i < p->functions.count; ++i) {
        Declaration *f = p->functions.items[i];
        s->function = f;
        s->scope = NULL;
        open_scope(s);
        for (int j = 0; j < f->parameters.count; ++j) {
            Declaration *param = f->parameters.items[j];
            s->scope->names =
                name_add(s->scope->names, param->name.spelling, symbol(s, param, "parameter"));
        }
        for (int j = 0; j < f->body->statements.count; ++j)
            statement(s, f->body->statements.items[j]);
        if (f->type != TOY_VOID && can_complete(f->body))
            error(s, f->name.position,
                  ml_format("missing return in function '%s'", f->name.spelling));
    }
}
