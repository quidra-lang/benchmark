enum class ToyType(val text: String) {
    INT("int"), BOOL("bool"), VOID("void");
    companion object {
        fun read(text: String): ToyType? = entries.firstOrNull {
            it.text == text
        }
    }
}
data class Name(val text: String, val position: Position)
class Variable(val type: ToyType, val name: Name, var initializer: Expr? = null, val size: Int? = null, val sizePosition: Position? = null) {
    var id = -1;
    var address = -1;
    var slot = -1
}
class Function(val type: ToyType, val name: Name, val parameters: List<Variable>, val body: Stmt) {
    var id = -1
}
sealed interface Top {
    data class VariableDecl(val variable: Variable) : Top
    data class FunctionDecl(val function: Function) : Top
}
data class Program(val declarations: List<Top>, val end: Position)
class Expr(val position: Position, var kind: ExprKind) {
    var reference: Int? = null;
    var type: ToyType? = null
}
sealed interface ExprKind {
    data class Integer(val value: Long) : ExprKind
    data class BooleanValue(val value: Boolean) : ExprKind
    data object Read : ExprKind
    data class VariableRef(val name: Name) : ExprKind
    data class Element(val name: Name, val index: Expr) : ExprKind
    data class Call(val name: Name, val arguments: List<Expr>) : ExprKind
    data class Unary(val op: String, val value: Expr) : ExprKind
    data class Binary(val op: String, val left: Expr, val right: Expr) : ExprKind
}
class Stmt(val position: Position, var kind: StmtKind) {
    var reference: Int? = null
}
sealed interface StmtKind {
    data class Block(val statements: List<Stmt>, val close: Position) : StmtKind
    data class Declaration(val variable: Variable) : StmtKind
    data class Assignment(val name: Name, val index: Expr?, val value: Expr) : StmtKind
    data class Call(val value: Expr) : StmtKind
    data class Conditional(val condition: Expr, val yes: Stmt, val no: Stmt?) : StmtKind
    data class WhileLoop(val condition: Expr, val body: Stmt) : StmtKind
    data class ForLoop(val initial: Stmt?, val condition: Expr?, val update: Stmt?, val body: Stmt) : StmtKind
    data object BreakLoop : StmtKind
    data object ContinueLoop : StmtKind
    data class ReturnValue(val value: Expr?) : StmtKind
    data class Print(val values: List<Expr>) : StmtKind
    data object Empty : StmtKind
}
class Parser(val tokens: List<Token>) {
    var index = 0
    val peek: Token get() = tokens[index]
    val text: String get() = peek.text
    fun failure(): CompileError = CompileError("syntax", peek.position, if (peek.kind == "end") "unexpected end of program" else "unexpected '$text'")
    fun take(): Token {
        val token = peek;
        if (token.kind != "end") index++;
        return token
    }
    fun expect(text: String): Token {
        if (this.text != text) throw failure();
        return take()
    }
    fun name(): Name {
        if (peek.kind != "identifier") throw failure();
        val token = take();
        return Name(token.text, token.position)
    }
    fun type(): ToyType {
        val type = ToyType.read(text) ?: throw failure();
        take();
        return type
    }
    fun program(): Program {
        val declarations = mutableListOf<Top>()
        while (peek.kind != "end") {
            val type = this.type();
            val name = name()
            if (text == "(") {
                take();
                val parameters = mutableListOf<Variable>();
                if (text != ")") {
                    while (true) {
                        val t = this.type();
                        val n = this.name();
                        parameters.add(Variable(t, n));
                        if (text != ",") break;
                        take()
                    }
                };
                expect(")");
                declarations.add(Top.FunctionDecl(Function(type, name, parameters, block())))
            } else {
                var initial: Expr? = null;
                var size: Int? = null;
                var sizePosition: Position? = null
                if (text == "[") {
                    take();
                    if (peek.kind != "integer") throw failure();
                    sizePosition = peek.position;
                    size = take().text.toInt();
                    expect("]")
                } else if (text == "=") {
                    take();
                    initial = expression()
                };
                expect(";");
                declarations.add(Top.VariableDecl(Variable(type, name, initial, size, sizePosition)))
            }
        }
        return Program(declarations, peek.position)
    }
    fun declaration(required: Boolean): Stmt {
        val position = peek.position;
        val type = this.type();
        val name = this.name();
        var initializer: Expr? = null;
        if (text == "=") {
            take();
            initializer = expression()
        } else if (required) expect("=");
        return Stmt(position, StmtKind.Declaration(Variable(type, name, initializer)))
    }
    fun block(): Stmt {
        val position = expect("{").position;
        val statements = mutableListOf<Stmt>()
        while (text != "}") {
            if (ToyType.read(text) != null) {
                val s = declaration(false);
                expect(";");
                statements.add(s)
            } else statements.add(statement())
        };
        val close = take().position;
        return Stmt(position, StmtKind.Block(statements, close))
    }
    fun statement(): Stmt {
        val position = peek.position
        return when (text) {
            "{" -> block()
            "if" -> {
                take();
                expect("(");
                val condition = expression();
                expect(")");
                val yes = statement();
                val no = if (text == "else") {
                    take();
                    statement()
                } else null;
                Stmt(position, StmtKind.Conditional(condition, yes, no))
            }
            "while" -> {
                take();
                expect("(");
                val condition = expression();
                expect(")");
                Stmt(position, StmtKind.WhileLoop(condition, statement()))
            }
            "for" -> {
                take();
                expect("(");
                val initial = if (text == ";") null else if (ToyType.read(text) != null) declaration(true) else simple();
                expect(";");
                val condition = if (text == ";") null else expression();
                expect(";");
                val update = if (text == ")") null else simple();
                expect(")");
                Stmt(position, StmtKind.ForLoop(initial, condition, update, statement()))
            }
            "break", "continue" -> {
                val keyword = take().text;
                expect(";");
                Stmt(position, if (keyword == "break") StmtKind.BreakLoop else StmtKind.ContinueLoop)
            }
            "return" -> {
                take();
                val value = if (text == ";") null else expression();
                expect(";");
                Stmt(position, StmtKind.ReturnValue(value))
            }
            "print" -> {
                take();
                expect("(");
                val values = mutableListOf(expression());
                while (text == ",") {
                    take();
                    values.add(expression())
                };
                expect(")");
                expect(";");
                Stmt(position, StmtKind.Print(values))
            }
            else -> {
                val result = simple();
                expect(";");
                result
            }
        }
    }
    fun simple(): Stmt {
        val position = peek.position
        if (text == "read") {
            take();
            expect("(");
            expect(")");
            return Stmt(position, StmtKind.Call(Expr(position, ExprKind.Read)))
        }
        val name = this.name();
        if (text == "(") return Stmt(position, StmtKind.Call(Expr(position, ExprKind.Call(name, arguments()))))
        var index: Expr? = null;
        if (text == "[") {
            take();
            index = expression();
            expect("]")
        };
        expect("=");
        return Stmt(position, StmtKind.Assignment(name, index, expression()))
    }
    fun arguments(): List<Expr> {
        expect("(");
        val values = mutableListOf<Expr>();
        if (text != ")") {
            values.add(expression());
            while (text == ",") {
                take();
                values.add(expression())
            }
        };
        expect(")");
        return values
    }
    fun priority(op: String): Int = when (op) {
        "||" -> 1;
        "&&" -> 2;
        "==", "!=" -> 3;
        "<", "<=", ">", ">=" -> 4;
        "+", "-" -> 5;
        "*", "/", "%" -> 6;
        else -> 0
    }
    fun expression(minimum: Int = 1): Expr {
        var left = unary();
        while (priority(text) >= minimum) {
            val op = take();
            val right = expression(priority(op.text) + 1);
            left = Expr(op.position, ExprKind.Binary(op.text, left, right))
        };
        return left
    }
    fun unary(): Expr {
        if (text in listOf("-", "!")) {
            val op = take();
            return Expr(op.position, ExprKind.Unary(op.text, unary()))
        };
        return primary()
    }
    fun primary(): Expr {
        val token = peek
        if (token.kind == "integer") {
            take();
            return Expr(token.position, ExprKind.Integer(token.text.toLong()))
        }
        if (text in listOf("true", "false")) {
            take();
            return Expr(token.position, ExprKind.BooleanValue(token.text == "true"))
        }
        if (text == "read") {
            take();
            expect("(");
            expect(")");
            return Expr(token.position, ExprKind.Read)
        }
        if (text == "(") {
            take();
            val value = expression();
            expect(")");
            return value
        }
        val name = this.name();
        if (text == "(") return Expr(token.position, ExprKind.Call(name, arguments()))
        if (text == "[") {
            take();
            val index = expression();
            expect("]");
            return Expr(token.position, ExprKind.Element(name, index))
        };
        return Expr(token.position, ExprKind.VariableRef(name))
    }
}
