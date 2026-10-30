data class Expr(val position: Position, val kind: ExprKind) {
    val lvalue: Boolean get() = kind is ExprKind.Name || kind is ExprKind.Index || kind is ExprKind.Field
}
sealed interface ExprKind {
    data class Number(val value: Int) : ExprKind
    data class Text(val value: String) : ExprKind
    data class Name(val name: String) : ExprKind
    data class Index(val name: String, val indices: List<Expr>) : ExprKind
    data class Field(val index: Expr) : ExprKind
    data class Parentheses(val body: Expr) : ExprKind
    data class Unary(val op: String, val body: Expr) : ExprKind
    data class Binary(val op: String, val left: Expr, val right: Expr) : ExprKind
    data class Assignment(val op: String, val target: Expr, val right: Expr) : ExprKind
    data class Increment(val delta: Int, val prefix: Boolean, val target: Expr) : ExprKind
    data class Conditional(val condition: Expr, val yes: Expr, val no: Expr) : ExprKind
    data class Member(val indices: List<Expr>, val name: String, val namePosition: Position) : ExprKind
    data class Call(val name: String, val builtin: Boolean, val arguments: List<Expr>) : ExprKind
    data class Getline(val target: Expr?, val file: Expr?) : ExprKind
}
data class Stmt(val position: Position, val kind: StmtKind)
data class Redirect(val append: Boolean, val expression: Expr, val position: Position)
sealed interface StmtKind {
    data class Block(val statements: List<Stmt>) : StmtKind
    data object Empty : StmtKind
    data class Expression(val expression: Expr) : StmtKind
    data class Conditional(val condition: Expr, val yes: Stmt, val no: Stmt?) : StmtKind
    data class While(val condition: Expr, val body: Stmt) : StmtKind
    data class Do(val body: Stmt, val condition: Expr) : StmtKind
    data class For(val initial: Expr?, val condition: Expr?, val update: Expr?, val body: Stmt) : StmtKind
    data class ForIn(val variable: String, val variablePosition: Position, val array: String, val arrayPosition: Position, val body: Stmt) : StmtKind
    data class Output(val printf: Boolean, val arguments: List<Expr>, val redirect: Redirect?) : StmtKind
    data class Delete(val name: String, val namePosition: Position, val indices: List<Expr>?) : StmtKind
    data object Next : StmtKind
    data object Break : StmtKind
    data object Continue : StmtKind
    data class Exit(val expression: Expr?) : StmtKind
    data class Return(val expression: Expr?) : StmtKind
}
data class Function(val name: String, val position: Position, val parameters: List<Pair<String, Position>>, val body: Stmt)
data class Rule(val kind: String, val position: Position, val start: Expr?, val end: Expr?, val action: Stmt?)
data class Program(val rules: List<Rule>, val functions: List<Function>)
class Parser(val tokens: List<Token>) {
    var index = 0;
    var function = false;
    var special = false;
    var loops = 0
    val peek: Token get() = tokens[index]
    val text: String get() = peek.text
    fun take(): Token {
        val token = peek;
        if (token.kind != "end") index++;
        return token
    }
    fun expect(text: String): Token {
        if (this.text != text || peek.kind == "end") throw SyntaxError(peek.position);
        return take()
    }
    fun name(): Token {
        if (peek.kind != "name") throw SyntaxError(peek.position);
        return take()
    }
    fun newlines() {
        while (peek.kind == "newline") take()
    }
    fun terminator() {
        if (text == ";" || peek.kind == "newline") take() else if (text != "}") throw SyntaxError(peek.position)
    }
    fun expressions(suppress: Boolean): List<Expr> {
        val result = mutableListOf(expression(suppress));
        while (text == ",") {
            take();
            newlines();
            result.add(expression(suppress))
        };
        return result
    }
    fun expression(suppress: Boolean = false): Expr {
        val left = conditional(suppress);
        if (left.lvalue && text in listOf("=", "+=", "-=", "*=", "/=", "%=", "^=")) {
            val token = take();
            return Expr(token.position, ExprKind.Assignment(token.text, left, expression(suppress)))
        };
        return left
    }
    fun conditional(suppress: Boolean): Expr {
        val condition = binary(1, suppress);
        if (text == "?") {
            val token = take();
            val yes = conditional(suppress);
            expect(":");
            return Expr(token.position, ExprKind.Conditional(condition, yes, conditional(suppress)))
        };
        return condition
    }
    fun binary(minimum: Int, suppress: Boolean): Expr {
        var left = unary(suppress)
        while (true) {
            val explicit = when (text) {
                "||" -> 1;
                "&&" -> 2;
                "in" -> 3;
                "<", "<=", "==", "!=", ">=" -> 4;
                ">" -> if (suppress) 0 else 4;
                "+", "-" -> 6;
                "*", "/", "%" -> 7;
                else -> 0
            }
            val concat = explicit == 0 && (peek.kind in listOf("number", "string", "name", "function", "builtin") || text in listOf("$", "(", "++", "--"));
            val priority = if (concat) 5 else explicit
            if (priority == 0 || priority < minimum) return left
            if (explicit == 3) {
                val token = take();
                val name = this.name();
                left = Expr(token.position, ExprKind.Member(listOf(left), name.text, name.position));
                continue
            }
            val position = peek.position;
            val op = if (concat) "concat" else take().text
            if (op == "||" || op == "&&") newlines()
            left = Expr(position, ExprKind.Binary(op, left, binary(priority + 1, suppress)))
        }
    }
    fun unary(suppress: Boolean): Expr {
        if (text in listOf("!", "-", "+")) {
            val token = take();
            return Expr(token.position, ExprKind.Unary(token.text, unary(suppress)))
        };
        val left = postfix(suppress);
        if (text == "^") {
            val token = take();
            return Expr(token.position, ExprKind.Binary(token.text, left, unary(suppress)))
        };
        return left
    }
    fun prefix(suppress: Boolean): Expr {
        val token = take();
        return Expr(token.position, ExprKind.Increment(if (token.text == "++") 1 else -1, true, lvalue(suppress)))
    }
    fun postfix(suppress: Boolean): Expr {
        if (text == "++" || text == "--") return prefix(suppress);
        val body = atom(suppress);
        if (body.lvalue && (text == "++" || text == "--")) {
            val token = take();
            return Expr(token.position, ExprKind.Increment(if (token.text == "++") 1 else -1, false, body))
        };
        return body
    }
    fun lvalue(suppress: Boolean): Expr {
        if (peek.kind != "name" && text != "$") throw SyntaxError(peek.position);
        return atom(suppress)
    }
    fun atom(suppress: Boolean): Expr {
        val token = peek
        val kind: ExprKind = when (token.kind) {
            "number" -> {
                take();
                ExprKind.Number(token.text.toInt())
            }
            "string" -> {
                take();
                ExprKind.Text(token.value)
            }
            "name" -> {
                take();
                if (text == "[") {
                    take();
                    val indices = expressions(false);
                    expect("]");
                    ExprKind.Index(token.text, indices)
                } else ExprKind.Name(token.text)
            }
            "function", "builtin" -> {
                take();
                val builtin = token.kind == "builtin";
                var arguments: List<Expr> = emptyList()
                if (text == "(") {
                    take();
                    if (text != ")") arguments = expressions(false);
                    expect(")")
                } else if (!builtin || token.text != "length") throw SyntaxError(peek.position)
                if (builtin) {
                    val n = arguments.size;
                    val valid = when (token.text) {
                        "length" -> n <= 1;
                        "substr" -> n == 2 || n == 3;
                        "index" -> n == 2;
                        "split" -> (n == 2 || n == 3) && arguments[1].kind is ExprKind.Name;
                        "sprintf" -> n >= 1;
                        else -> n == 1
                    };
                    if (!valid) throw SyntaxError(token.position)
                }
                ExprKind.Call(token.text, builtin, arguments)
            }
            else -> when (token.text) {
                "$" -> {
                    take();
                    ExprKind.Field(if (text == "++" || text == "--") prefix(suppress) else atom(suppress))
                }
                "(" -> {
                    take();
                    val values = expressions(false);
                    expect(")");
                    if (values.size == 1) ExprKind.Parentheses(values[0]) else {
                        expect("in");
                        val name = this.name();
                        ExprKind.Member(values, name.text, name.position)
                    }
                }
                "getline" -> {
                    take();
                    val target = if (peek.kind == "name" || text == "$") lvalue(suppress) else null;
                    val file = if (text == "<") {
                        take();
                        atom(suppress)
                    } else null;
                    ExprKind.Getline(target, file)
                }
                else -> throw SyntaxError(token.position)
            }
        }
        return Expr(token.position, kind)
    }
    fun block(): Stmt {
        val position = expect("{").position;
        val statements = mutableListOf<Stmt>();
        while (text != "}") {
            if (peek.kind == "newline" || text == ";") take() else statements.add(statement())
        };
        expect("}");
        return Stmt(position, StmtKind.Block(statements))
    }
    fun loopBody(): Stmt {
        newlines();
        loops++;
        val body = statement();
        loops--;
        return body
    }
    fun statement(): Stmt {
        val token = peek;
        val position = token.position
        val kind: StmtKind = when (text) {
            "{" -> return block()
            ";" -> {
                take();
                return Stmt(position, StmtKind.Empty)
            }
            "if" -> {
                take();
                expect("(");
                val condition = expression();
                expect(")");
                newlines();
                val yes = statement();
                newlines();
                val no = if (text == "else") {
                    take();
                    newlines();
                    statement()
                } else null;
                return Stmt(position, StmtKind.Conditional(condition, yes, no))
            }
            "while" -> {
                take();
                expect("(");
                val condition = expression();
                expect(")");
                return Stmt(position, StmtKind.While(condition, loopBody()))
            }
            "do" -> {
                take();
                val body = loopBody();
                newlines();
                expect("while");
                expect("(");
                val condition = expression();
                expect(")");
                StmtKind.Do(body, condition)
            }
            "for" -> {
                take();
                expect("(")
                if (index + 3 < tokens.size && tokens[index].kind == "name" && tokens[index + 1].text == "in" && tokens[index + 2].kind == "name" && tokens[index + 3].text == ")") {
                    val variable = name();
                    take();
                    val array = name();
                    take();
                    return Stmt(position, StmtKind.ForIn(variable.text, variable.position, array.text, array.position, loopBody()))
                }
                val initial = if (text == ";") null else expression();
                expect(";");
                newlines();
                val condition = if (text == ";") null else expression();
                expect(";");
                newlines();
                val update = if (text == ")") null else expression();
                expect(")");
                return Stmt(position, StmtKind.For(initial, condition, update, loopBody()))
            }
            "print", "printf" -> {
                take();
                val printf = token.text == "printf";
                val empty = text in listOf(";", 10.toChar().toString(), "}", ">", ">>");
                var parenthesized = false
                if (text == "(") {
                    var depth = 0;
                    for (i in index until tokens.size) {
                        if (tokens[i].text == "(") depth++ else if (tokens[i].text == ")") {
                            depth--;
                            if (depth == 0) {
                                parenthesized = i + 1 < tokens.size && (tokens[i + 1].text in listOf(";", 10.toChar().toString(), "}", ">", ">>") || tokens[i + 1].kind == "end");
                                break
                            }
                        }
                    }
                }
                if (empty && printf) throw SyntaxError(peek.position)
                val arguments = if (empty) emptyList() else if (parenthesized) {
                    take();
                    val values = expressions(false);
                    expect(")");
                    values
                } else expressions(true)
                val redirect = if (text == ">" || text == ">>") {
                    val op = take();
                    Redirect(op.text == ">>", binary(5, false), op.position)
                } else null
                StmtKind.Output(printf, arguments, redirect)
            }
            "delete" -> {
                take();
                val name = this.name();
                val indices = if (text == "[") {
                    take();
                    val values = expressions(false);
                    expect("]");
                    values
                } else null;
                StmtKind.Delete(name.text, name.position, indices)
            }
            "next" -> {
                take();
                if (special && !function) throw SyntaxError(position);
                StmtKind.Next
            }
            "break", "continue" -> {
                take();
                if (loops == 0) throw SyntaxError(position);
                if (token.text == "break") StmtKind.Break else StmtKind.Continue
            }
            "exit", "return" -> {
                take();
                if (token.text == "return" && !function) throw SyntaxError(position);
                val value = if (text in listOf(";", 10.toChar().toString(), "}")) null else expression();
                if (token.text == "exit") StmtKind.Exit(value) else StmtKind.Return(value)
            }
            else -> StmtKind.Expression(expression())
        }
        terminator();
        return Stmt(position, kind)
    }
    fun program(): Program {
        val rules = mutableListOf<Rule>();
        val functions = mutableListOf<Function>()
        while (peek.kind != "end") {
            if (text == ";" || peek.kind == "newline") {
                take();
                continue
            };
            val position = peek.position
            if (text == "function") {
                take();
                if (peek.kind != "name" && peek.kind != "function") throw SyntaxError(peek.position);
                val name = take();
                expect("(");
                val parameters = mutableListOf<Pair<String, Position>>()
                if (text != ")") {
                    while (true) {
                        val parameter = this.name();
                        parameters.add(parameter.text to parameter.position);
                        if (text != ",") break;
                        take();
                        newlines()
                    }
                }
                expect(")");
                newlines();
                function = true;
                val body = block();
                function = false;
                functions.add(Function(name.text, name.position, parameters, body))
            } else if (text == "BEGIN" || text == "END") {
                val kind = take().text;
                special = true;
                val action = block();
                special = false;
                rules.add(Rule(kind, position, null, null, action))
            }
            else if (text == "{") rules.add(Rule("all", position, null, null, block()))
            else {
                val start = expression();
                val end = if (text == ",") {
                    take();
                    newlines();
                    expression()
                } else null;
                val action = if (text == "{") block() else {
                    if (text != ";" && peek.kind != "newline" && peek.kind != "end") throw SyntaxError(peek.position);
                    null
                };
                rules.add(Rule(if (end == null) "pattern" else "range", position, start, end, action))
            }
        }
        return Program(rules, functions)
    }
}
