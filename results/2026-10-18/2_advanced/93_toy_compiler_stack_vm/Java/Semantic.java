import java.util.*;
final class Semantic {
    static boolean canComplete(Parser.Statement statement) {
        if (statement instanceof Parser.Return || statement instanceof Parser.Flow)
            return false;
        if (statement instanceof Parser.Block block) {
            for (Parser.Statement child : block.statements)
                if (!canComplete(child))
                    return false;
            return true;
        }
        if (statement instanceof Parser.If conditional && conditional.otherwise != null)
            return canComplete(conditional.thenStatement) || canComplete(conditional.otherwise);
        return true;
    }
    List<Parser.Declaration> declarations;
    Lexer.Position end;
    Map<String, Parser.Declaration> globals = new HashMap<>();
    List<Parser.Function> functions = new ArrayList<>();
    List<Parser.VariableDecl> variables = new ArrayList<>();
    List<Map<String, Parser.VariableDecl>> scopes = new ArrayList<>();
    Parser.Function function;
    Semantic(List<Parser.Declaration> declarations, Lexer.Position end) {
        this.declarations = declarations;
        this.end = end;
    }
    void fail(Lexer.Position position, String message) {
        throw new Lexer.CompileError("semantic", position, message);
    }
    Parser.Declaration lookup(String name, Lexer.Position position, boolean read) {
        Parser.Declaration referent = null;
        for (int i = scopes.size() - 1; i >= 0; i--)
            if (scopes.get(i).containsKey(name)) {
                referent = scopes.get(i).get(name);
                break;
            }
        if (referent == null)
            referent = globals.get(name);
        if (referent != null) {
            referent.references.add(position);
            if (read)
                referent.reads++;
        }
        return referent;
    }
    Parser.VariableDecl variable(String name, Lexer.Position position, boolean indexed,
                                 boolean read) {
        Parser.Declaration referent = lookup(name, position, read);
        if (referent == null)
            fail(position, "undeclared identifier '" + name + "'");
        if (referent instanceof Parser.Function)
            fail(position, "'" + name + "' is a function, not a variable");
        Parser.VariableDecl variable = (Parser.VariableDecl)referent;
        boolean array = variable.storage == Parser.Storage.GLOBAL && variable.size != null;
        if (indexed && !array)
            fail(position, "'" + name + "' is not an array");
        if (!indexed && array)
            fail(position, "array '" + name + "' used without index");
        return variable;
    }
    Parser.Type expression(Parser.Expr expression, boolean callStatement) {
        Parser.Type result;
        if (expression instanceof Parser.Literal literal)
            result = literal.type;
        else if (expression instanceof Parser.Read)
            result = Parser.Type.INT;
        else if (expression instanceof Parser.Variable variable) {
            variable.referent = variable(variable.name, variable.position, false, true);
            result = variable.referent.type;
        } else if (expression instanceof Parser.ArrayElement array) {
            array.referent = variable(array.name, array.position, true, true);
            if (expression(array.index, false) != Parser.Type.INT)
                fail(array.position, "index of '" + array.name + "' must be int");
            result = Parser.Type.INT;
        } else if (expression instanceof Parser.Call call) {
            Parser.Declaration referent = lookup(call.name, call.position, true);
            if (referent == null)
                fail(call.position, "undeclared function '" + call.name + "'");
            if (!(referent instanceof Parser.Function))
                fail(call.position, "'" + call.name + "' is not a function");
            call.referent = (Parser.Function)referent;
            function.calls.add(call.referent);
            int expected = call.referent.parameters.size(), found = call.arguments.size();
            if (expected != found)
                fail(call.position, "wrong number of arguments to '" + call.name + "' (expected " +
                                        expected + ", found " + found + ")");
            for (int i = 0; i < found; i++) {
                Parser.Type type = expression(call.arguments.get(i), false);
                Parser.Type required = call.referent.parameters.get(i).type;
                if (type != required)
                    fail(call.position,
                         "argument " + (i + 1) + " of '" + call.name + "' must be " + required);
            }
            if (!callStatement && call.referent.type == Parser.Type.VOID)
                fail(call.position, "void function '" + call.name + "' used as a value");
            result = call.referent.type;
        } else if (expression instanceof Parser.Unary unary) {
            result = expression(unary.operand, false);
            Parser.Type required = unary.operator.equals("-") ? Parser.Type.INT : Parser.Type.BOOL;
            if (result != required)
                fail(unary.position,
                     "operator '" + unary.operator + "' requires " + required + " operand");
        } else {
            Parser.Binary binary = (Parser.Binary)expression;
            Parser.Type left = expression(binary.left, false), right =
                                                                   expression(binary.right, false);
            String operator = binary.operator;
            if (Set.of("+", "-", "*", "/", "%", "<", "<=", ">", ">=").contains(operator)) {
                if (left != Parser.Type.INT || right != Parser.Type.INT)
                    fail(binary.position, "operator '" + operator + "' requires int operands");
                result = Set.of("+", "-", "*", "/", "%").contains(operator) ? Parser.Type.INT
                                                                            : Parser.Type.BOOL;
            } else if (Set.of("==", "!=").contains(operator)) {
                if (left != right)
                    fail(binary.position,
                         "operator '" + operator + "' requires operands of the same type");
                result = Parser.Type.BOOL;
            } else {
                if (left != Parser.Type.BOOL || right != Parser.Type.BOOL)
                    fail(binary.position, "operator '" + operator + "' requires bool operands");
                result = Parser.Type.BOOL;
            }
        }
        expression.type = result;
        return result;
    }
    Parser.Type constantInitializer(Parser.Expr expression) {
        Lexer.Position earliest = null;
        Deque<Parser.Expr> pending = new ArrayDeque<>();
        pending.push(expression);
        while (!pending.isEmpty()) {
            Parser.Expr current = pending.pop();
            if (current instanceof Parser.Variable || current instanceof Parser.ArrayElement ||
                current instanceof Parser.Call || current instanceof Parser.Read)
                if (earliest == null || current.position.compareTo(earliest) < 0)
                    earliest = current.position;
            for (Parser.Expr child : Parser.expressionChildren(current))
                pending.push(child);
        }
        if (earliest != null)
            fail(earliest, "global initializer must be constant");
        return expression(expression, false);
    }
    void statement(Parser.Statement statement, int loopDepth) {
        switch (statement) {
        case Parser.VariableDecl variable -> {
            if (variable.type == Parser.Type.VOID)
                fail(variable.namePosition,
                     "variable '" + variable.name + "' cannot have type void");
            if (scopes.getLast().containsKey(variable.name))
                fail(variable.namePosition, "redeclaration of '" + variable.name + "'");
            if (variable.initializer != null &&
                expression(variable.initializer, false) != variable.type)
                fail(variable.namePosition,
                     "type mismatch in initialization of '" + variable.name + "'");
            variables.add(variable);
            scopes.getLast().put(variable.name, variable);
        }
        case Parser.Assignment assignment -> {
            assignment.referent =
                variable(assignment.name, assignment.position, assignment.index != null, false);
            if (assignment.index != null && expression(assignment.index, false) != Parser.Type.INT)
                fail(assignment.position, "index of '" + assignment.name + "' must be int");
            if (expression(assignment.value, false) != assignment.referent.type)
                fail(assignment.position,
                     "type mismatch in assignment to '" + assignment.name + "'");
        }
        case Parser.CallStatement call -> expression(call.expression, true);
        case Parser.If conditional -> {
            if (expression(conditional.condition, false) != Parser.Type.BOOL)
                fail(conditional.position, "condition of 'if' must be bool");
            statement(conditional.thenStatement, loopDepth);
            if (conditional.otherwise != null)
                statement(conditional.otherwise, loopDepth);
        }
        case Parser.While loop -> {
            if (expression(loop.condition, false) != Parser.Type.BOOL)
                fail(loop.position, "condition of 'while' must be bool");
            statement(loop.body, loopDepth + 1);
        }
        case Parser.For loop -> {
            scopes.add(new HashMap<>());
            if (loop.initial != null)
                statement(loop.initial, loopDepth);
            if (loop.condition != null && expression(loop.condition, false) != Parser.Type.BOOL)
                fail(loop.position, "condition of 'for' must be bool");
            if (loop.update != null)
                statement(loop.update, loopDepth);
            statement(loop.body, loopDepth + 1);
            scopes.removeLast();
        }
        case Parser.Flow flow -> {
            if (loopDepth == 0)
                fail(flow.position(), "'" + flow.kind() + "' outside loop");
        }
        case Parser.Return returned -> {
            if (function.type == Parser.Type.VOID && returned.value != null)
                fail(returned.position, "function '" + function.name + "' must not return a value");
            if (function.type != Parser.Type.VOID) {
                if (returned.value == null)
                    fail(returned.position, "function '" + function.name + "' must return a value");
                if (expression(returned.value, false) != function.type)
                    fail(returned.position,
                         "return value of '" + function.name + "' must be " + function.type);
            }
        }
        case Parser.Print print -> {
            for (int i = 0; i < print.arguments.size(); i++)
                if (expression(print.arguments.get(i), false) != Parser.Type.INT)
                    fail(print.position, "argument " + (i + 1) + " of 'print' must be int");
        }
        case Parser.Block block -> {
            scopes.add(new HashMap<>());
            for (Parser.Statement child : block.statements)
                statement(child, loopDepth);
            scopes.removeLast();
        }
        case Parser.Empty ignored -> {
        }
        }
    }
    Semantic analyze() {
        for (Parser.Declaration declaration : declarations) {
            if (declaration instanceof Parser.VariableDecl variable) {
                if (variable.size != null) {
                    if (variable.type != Parser.Type.INT)
                        fail(variable.namePosition,
                             "array '" + variable.name + "' must have element type int");
                    if (variable.size == 0)
                        fail(variable.sizePosition,
                             "array '" + variable.name + "' must have a positive size");
                } else if (variable.type == Parser.Type.VOID)
                    fail(variable.namePosition,
                         "variable '" + variable.name + "' cannot have type void");
            }
            if (globals.containsKey(declaration.name))
                fail(declaration.namePosition, "redeclaration of '" + declaration.name + "'");
            if (declaration instanceof Parser.VariableDecl variable) {
                if (variable.initializer != null &&
                    constantInitializer(variable.initializer) != variable.type)
                    fail(variable.namePosition,
                         "type mismatch in initialization of '" + variable.name + "'");
                variables.add(variable);
            } else {
                Parser.Function function = (Parser.Function)declaration;
                Set<String> names = new HashSet<>();
                for (Parser.VariableDecl parameter : function.parameters) {
                    if (parameter.type == Parser.Type.VOID)
                        fail(parameter.namePosition,
                             "parameter '" + parameter.name + "' cannot have type void");
                    if (!names.add(parameter.name))
                        fail(parameter.namePosition, "redeclaration of '" + parameter.name + "'");
                    variables.add(parameter);
                }
                functions.add(function);
            }
            globals.put(declaration.name, declaration);
        }
        Parser.Declaration main = globals.get("main");
        if (!(main instanceof Parser.Function))
            fail(end, "no main function");
        Parser.Function mainFunction = (Parser.Function)main;
        if (mainFunction.type != Parser.Type.VOID || !mainFunction.parameters.isEmpty())
            fail(mainFunction.namePosition, "main must be declared as 'void main()'");
        for (Parser.Function function : functions) {
            this.function = function;
            scopes = new ArrayList<>();
            Map<String, Parser.VariableDecl> scope = new HashMap<>();
            for (Parser.VariableDecl parameter : function.parameters)
                scope.put(parameter.name, parameter);
            scopes.add(scope);
            for (Parser.Statement statement : function.body.statements)
                statement(statement, 0);
            if (function.type != Parser.Type.VOID && canComplete(function.body))
                fail(function.namePosition, "missing return in function '" + function.name + "'");
        }
        return this;
    }
}
