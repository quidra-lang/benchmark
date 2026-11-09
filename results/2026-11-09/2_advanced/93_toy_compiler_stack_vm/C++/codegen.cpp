#include "compiler.hpp"
bool jump(const std::string &op) { return op == "JUMP" || op == "JUMPF" || op == "JUMPT"; }
bool conditional(const std::string &op) { return op == "JUMPF" || op == "JUMPT"; }
bool transfer(const std::string &op) { return word_in("JUMP RET RETV HALT", op); }
void Generator::emit(const std::string &op, int64_t a, int64_t b, Position pos,
                     Declaration *callee) {
    unit->code.push_back({op, a, b, pos, callee});
}
int Generator::label() {
    labels.push_back(-1);
    return static_cast<int>(labels.size()) - 1;
}
void Generator::place(int id) { labels[id] = static_cast<int>(unit->code.size()); }
void Generator::to(const std::string &op, int id, Position pos) { emit(op, id, 0, pos); }
void Generator::patch() {
    for (Instruction &instruction : unit->code)
        if (jump(instruction.op))
            instruction.a = labels[instruction.a];
}
void Generator::expression(Expr *e) {
    Position pos = e->token.position;
    if (e->kind == "integer" || e->kind == "boolean")
        emit("PUSH", e->value, 0, pos);
    else if (e->kind == "read")
        emit("READ", 0, 0, pos);
    else if (e->kind == "variable") {
        Symbol *s = e->referent;
        emit(s->kind == "global" ? "LOADG" : "LOADL", s->kind == "global" ? s->address : s->slot, 0,
             pos);
    } else if (e->kind == "array") {
        expression(e->children[0]);
        emit("LOADA", e->referent->address, e->referent->size, pos);
    } else if (e->kind == "call") {
        for (Expr *argument : e->children)
            expression(argument);
        emit("CALL", 0, static_cast<int64_t>(e->children.size()), pos, e->referent->declaration);
    } else if (e->kind == "unary") {
        expression(e->children[0]);
        emit(e->token.spelling == "-" ? "NEG" : "NOT", 0, 0, pos);
    } else if (e->kind == "binary") {
        const std::string &op = e->token.spelling;
        if (op == "&&" || op == "||") {
            int first = label();
            int last = label();
            expression(e->children[0]);
            to(op == "&&" ? "JUMPF" : "JUMPT", first, pos);
            expression(e->children[1]);
            to("JUMP", last, pos);
            place(first);
            emit("PUSH", op == "||", 0, pos);
            place(last);
        } else {
            expression(e->children[0]);
            expression(e->children[1]);
            static const std::map<std::string, std::string> ops = {
                {"+", "ADD"}, {"-", "SUB"}, {"*", "MUL"}, {"/", "DIV"}, {"%", "MOD"}, {"<", "LT"},
                {"<=", "LE"}, {">", "GT"},  {">=", "GE"}, {"==", "EQ"}, {"!=", "NE"}};
            emit(ops.at(op), 0, 0, pos);
        }
    }
}
void Generator::statement(Statement *s) {
    if (!s)
        return;
    Position pos = s->token.position;
    if (s->kind == "declaration") {
        Declaration *d = s->declaration;
        if (d->initializer)
            expression(d->initializer);
        else
            emit("PUSH", 0, 0, d->name.position);
        emit("STOREL", d->symbol->slot, 0, d->name.position);
    } else if (s->kind == "assignment") {
        Symbol *symbol = s->referent;
        if (s->index) {
            expression(s->index);
            expression(s->expr);
            emit("STOREA", symbol->address, symbol->size, pos);
        } else {
            expression(s->expr);
            emit(symbol->kind == "global" ? "STOREG" : "STOREL",
                 symbol->kind == "global" ? symbol->address : symbol->slot, 0, pos);
        }
    } else if (s->kind == "call") {
        expression(s->expr);
        if (s->expr->type != "void")
            emit("POP", 0, 0, pos);
    } else if (s->kind == "print") {
        for (Expr *e : s->expressions)
            expression(e);
        emit("PRINT", static_cast<int64_t>(s->expressions.size()), 0, pos);
    } else if (s->kind == "return") {
        if (s->expr)
            expression(s->expr);
        emit(s->expr ? "RETV" : "RET", 0, 0, pos);
    } else if (s->kind == "block")
        for (Statement *child : s->statements)
            statement(child);
    else if (s->kind == "if") {
        int other = label();
        expression(s->condition);
        to("JUMPF", other, pos);
        statement(s->yes);
        if (s->no) {
            int last = label();
            to("JUMP", last, pos);
            place(other);
            statement(s->no);
            place(last);
        } else
            place(other);
    } else if (s->kind == "while") {
        int first = label();
        int last = label();
        place(first);
        expression(s->condition);
        to("JUMPF", last, pos);
        loops.push_back({last, first});
        statement(s->body);
        loops.pop_back();
        to("JUMP", first, pos);
        place(last);
    } else if (s->kind == "for") {
        int first = label();
        int update = label();
        int last = label();
        statement(s->init);
        place(first);
        if (s->condition) {
            expression(s->condition);
            to("JUMPF", last, pos);
        }
        loops.push_back({last, update});
        statement(s->body);
        loops.pop_back();
        place(update);
        statement(s->update);
        to("JUMP", first, pos);
        place(last);
    } else if (s->kind == "break" || s->kind == "continue")
        to("JUMP", s->kind == "break" ? loops.back().first : loops.back().second, pos);
}
void walk_statements(Statement *s, const std::function<void(Statement *)> &visit) {
    if (!s)
        return;
    visit(s);
    for (Statement *child : s->statements)
        walk_statements(child, visit);
    for (Statement *child : {s->yes, s->no, s->body, s->init, s->update})
        walk_statements(child, visit);
}
std::pair<std::vector<Unit>, int> generate(Program &program, const std::set<Symbol *> &reachable) {
    int cells = 0;
    for (Declaration *d : program.globals) {
        d->symbol->address = cells;
        cells += d->array ? static_cast<int>(d->size.integer) : 1;
    }
    std::vector<Unit> units;
    Unit init;
    init.name = "<init>";
    Generator initial{&init, {}, {}};
    for (Declaration *d : program.globals)
        if (d->initializer) {
            initial.expression(d->initializer);
            initial.emit("STOREG", d->symbol->address, 0, d->name.position);
        }
    Declaration *main = program.names.at("main")->declaration;
    initial.emit("CALL", 0, 0, main->name.position, main);
    initial.emit("HALT", 0, 0, main->name.position);
    initial.patch();
    units.push_back(std::move(init));
    for (Declaration *f : program.functions)
        if (reachable.count(f->symbol)) {
            for (Declaration *parameter : f->parameters)
                f->slots.push_back(parameter->symbol);
            std::vector<Declaration *> locals;
            walk_statements(f->body, [&](Statement *s) {
                if (s->kind == "declaration")
                    locals.push_back(s->declaration);
            });
            std::sort(locals.begin(), locals.end(), [](Declaration *a, Declaration *b) {
                return earlier(a->name.position, b->name.position);
            });
            for (Declaration *d : locals)
                f->slots.push_back(d->symbol);
            for (size_t i = 0; i < f->slots.size(); ++i)
                f->slots[i]->slot = static_cast<int>(i);
            Unit unit;
            unit.name = f->name.spelling;
            unit.function = f;
            unit.slots = static_cast<int>(f->slots.size());
            Generator generator{&unit, {}, {}};
            generator.emit("ENTER", unit.slots, 0, f->name.position);
            generator.statement(f->body);
            if (f->type == "void")
                generator.emit("RET", 0, 0, f->body->close.position);
            generator.patch();
            units.push_back(std::move(unit));
        }
    return {units, cells};
}
