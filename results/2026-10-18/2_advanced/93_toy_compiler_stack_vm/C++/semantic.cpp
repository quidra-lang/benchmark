#include "compiler.hpp"
static std::vector<std::unique_ptr<Symbol>> symbols;
static void semantic_error(Position pos, const std::string &message) {
    throw CompileError{"semantic", message, pos};
}
Symbol *Semantics::symbol(Declaration *d, const std::string &kind) {
    symbols.push_back(std::make_unique<Symbol>());
    Symbol *result = symbols.back().get();
    result->name = d->name.spelling;
    result->type = d->type;
    result->kind = kind;
    result->declaration = d;
    result->array = d->array;
    result->size = static_cast<int>(d->size.integer);
    d->symbol = result;
    program->symbols.push_back(result);
    return result;
}
Symbol *Semantics::lookup(Token token, bool read) {
    Symbol *result = nullptr;
    for (auto scope = scopes.rbegin(); scope != scopes.rend(); ++scope) {
        auto found = scope->find(token.spelling);
        if (found != scope->end()) {
            result = found->second;
            break;
        }
    }
    if (!result) {
        auto found = program->names.find(token.spelling);
        if (found != program->names.end())
            result = found->second;
    }
    if (result) {
        result->references.push_back(token.position);
        if (read)
            ++result->reads;
    }
    return result;
}
Symbol *Semantics::variable(Token token, bool array, bool read) {
    Symbol *result = lookup(token, read);
    const std::string &name = token.spelling;
    if (!result)
        semantic_error(token.position, "undeclared identifier '" + name + "'");
    if (result->kind == "function")
        semantic_error(token.position, "'" + name + "' is a function, not a variable");
    if (array && !result->array)
        semantic_error(token.position, "'" + name + "' is not an array");
    if (!array && result->array)
        semantic_error(token.position, "array '" + name + "' used without index");
    return result;
}
std::string Semantics::expression(Expr *e, bool statement) {
    std::string type, name = e->token.spelling;
    Position pos = e->token.position;
    if (e->kind == "integer" || e->kind == "read")
        type = "int";
    else if (e->kind == "boolean")
        type = "bool";
    else if (e->kind == "variable") {
        e->referent = variable(e->token, false, true);
        type = e->referent->type;
    } else if (e->kind == "array") {
        e->referent = variable(e->token, true, true);
        if (expression(e->children[0]) != "int")
            semantic_error(pos, "index of '" + name + "' must be int");
        type = "int";
    } else if (e->kind == "call") {
        Symbol *found = lookup(e->token, true);
        if (!found)
            semantic_error(pos, "undeclared function '" + name + "'");
        if (found->kind != "function")
            semantic_error(pos, "'" + name + "' is not a function");
        e->referent = found;
        if (function)
            function->symbol->calls.insert(found);
        const auto &parameters = found->declaration->parameters;
        if (parameters.size() != e->children.size())
            semantic_error(pos, "wrong number of arguments to '" + name + "' (expected " +
                                    std::to_string(parameters.size()) + ", found " +
                                    std::to_string(e->children.size()) + ")");
        for (size_t i = 0; i < parameters.size(); ++i)
            if (expression(e->children[i]) != parameters[i]->type)
                semantic_error(pos, "argument " + std::to_string(i + 1) + " of '" + name +
                                        "' must be " + parameters[i]->type);
        if (!statement && found->type == "void")
            semantic_error(pos, "void function '" + name + "' used as a value");
        type = found->type;
    } else if (e->kind == "unary") {
        type = expression(e->children[0]);
        std::string required = e->token.spelling == "-" ? "int" : "bool";
        if (type != required)
            semantic_error(pos, "operator '" + e->token.spelling + "' requires " + required +
                                    " operand");
    } else if (e->kind == "binary") {
        std::string left = expression(e->children[0]);
        std::string right = expression(e->children[1]);
        const std::string &op = e->token.spelling;
        if (word_in("+ - * / % < <= > >=", op)) {
            if (left != "int" || right != "int")
                semantic_error(pos, "operator '" + op + "' requires int operands");
            type = word_in("< <= > >=", op) ? "bool" : "int";
        } else if (op == "==" || op == "!=") {
            if (left != right)
                semantic_error(pos, "operator '" + op + "' requires operands of the same type");
            type = "bool";
        } else {
            if (left != "bool" || right != "bool")
                semantic_error(pos, "operator '" + op + "' requires bool operands");
            type = "bool";
        }
    }
    e->type = type;
    return type;
}
bool can_complete(Statement *s) {
    if (word_in("return break continue", s->kind))
        return false;
    if (s->kind == "block") {
        for (Statement *child : s->statements)
            if (!can_complete(child))
                return false;
        return true;
    }
    if (s->kind == "if")
        return !s->no || can_complete(s->yes) || can_complete(s->no);
    return true;
}
void Semantics::declaration(Declaration *d) {
    const std::string &name = d->name.spelling;
    Position pos = d->name.position;
    if (d->type == "void")
        semantic_error(pos, "variable '" + name + "' cannot have type void");
    if (scopes.back().count(name))
        semantic_error(pos, "redeclaration of '" + name + "'");
    if (d->initializer && expression(d->initializer) != d->type)
        semantic_error(pos, "type mismatch in initialization of '" + name + "'");
    scopes.back()[name] = symbol(d, "local");
}
void Semantics::statement(Statement *s) {
    Position pos = s->token.position;
    if (s->kind == "declaration")
        declaration(s->declaration);
    else if (s->kind == "assignment") {
        const std::string &name = s->token.spelling;
        s->referent = variable(s->token, s->index != nullptr, false);
        if (s->index && expression(s->index) != "int")
            semantic_error(pos, "index of '" + name + "' must be int");
        if (expression(s->expr) != s->referent->type)
            semantic_error(pos, "type mismatch in assignment to '" + name + "'");
    } else if (s->kind == "call")
        expression(s->expr, true);
    else if (s->kind == "if" || s->kind == "while") {
        if (expression(s->condition) != "bool")
            semantic_error(pos, "condition of '" + s->kind + "' must be bool");
        if (s->kind == "if") {
            statement(s->yes);
            if (s->no)
                statement(s->no);
        } else {
            ++loops;
            statement(s->body);
            --loops;
        }
    } else if (s->kind == "for") {
        scopes.emplace_back();
        if (s->init)
            statement(s->init);
        if (s->condition && expression(s->condition) != "bool")
            semantic_error(pos, "condition of 'for' must be bool");
        if (s->update)
            statement(s->update);
        ++loops;
        statement(s->body);
        --loops;
        scopes.pop_back();
    } else if (s->kind == "break" || s->kind == "continue") {
        if (!loops)
            semantic_error(pos, "'" + s->kind + "' outside loop");
    } else if (s->kind == "return") {
        const std::string &name = function->name.spelling;
        if (function->type == "void") {
            if (s->expr)
                semantic_error(pos, "function '" + name + "' must not return a value");
        } else {
            if (!s->expr)
                semantic_error(pos, "function '" + name + "' must return a value");
            if (expression(s->expr) != function->type)
                semantic_error(pos, "return value of '" + name + "' must be " + function->type);
        }
    } else if (s->kind == "print") {
        for (size_t i = 0; i < s->expressions.size(); ++i)
            if (expression(s->expressions[i]) != "int")
                semantic_error(pos,
                               "argument " + std::to_string(i + 1) + " of 'print' must be int");
    } else if (s->kind == "block") {
        scopes.emplace_back();
        for (Statement *child : s->statements)
            statement(child);
        scopes.pop_back();
    }
}
void Semantics::analyze() {
    for (Declaration *d : program->declarations) {
        const std::string &name = d->name.spelling;
        Position pos = d->name.position;
        if (!d->function) {
            if (d->array) {
                if (d->type != "int")
                    semantic_error(pos, "array '" + name + "' must have element type int");
                if (d->size.integer == 0)
                    semantic_error(d->size.position,
                                   "array '" + name + "' must have a positive size");
            } else if (d->type == "void")
                semantic_error(pos, "variable '" + name + "' cannot have type void");
        }
        if (program->names.count(name))
            semantic_error(pos, "redeclaration of '" + name + "'");
        if (d->function) {
            std::set<std::string> seen;
            for (Declaration *parameter : d->parameters) {
                const std::string &pname = parameter->name.spelling;
                if (parameter->type == "void")
                    semantic_error(parameter->name.position,
                                   "parameter '" + pname + "' cannot have type void");
                if (!seen.insert(pname).second)
                    semantic_error(parameter->name.position, "redeclaration of '" + pname + "'");
            }
            program->names[name] = symbol(d, "function");
        } else {
            if (d->initializer) {
                Expr *first = nullptr;
                std::function<void(Expr *)> visit = [&](Expr *e) {
                    if (word_in("variable array call read", e->kind) &&
                        (!first || earlier(e->token.position, first->token.position)))
                        first = e;
                    for (Expr *child : e->children)
                        visit(child);
                };
                visit(d->initializer);
                if (first)
                    semantic_error(first->token.position, "global initializer must be constant");
                if (expression(d->initializer) != d->type)
                    semantic_error(pos, "type mismatch in initialization of '" + name + "'");
            }
            program->names[name] = symbol(d, "global");
        }
    }
    auto main = program->names.find("main");
    if (main == program->names.end() || main->second->kind != "function")
        semantic_error(program->end.position, "no main function");
    Declaration *entry = main->second->declaration;
    if (entry->type != "void" || !entry->parameters.empty())
        semantic_error(entry->name.position, "main must be declared as 'void main()'");
    for (Declaration *f : program->functions) {
        function = f;
        scopes = {std::map<std::string, Symbol *>()};
        for (Declaration *parameter : f->parameters)
            scopes[0][parameter->name.spelling] = symbol(parameter, "parameter");
        for (Statement *child : f->body->statements)
            statement(child);
        if (f->type != "void" && can_complete(f->body))
            semantic_error(f->name.position,
                           "missing return in function '" + f->name.spelling + "'");
    }
}
