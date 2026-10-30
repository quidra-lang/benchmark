class Symbol(val name: Name, val type: ToyType, val variable: Variable?, val function: Function?, val parameter: Boolean = false) {
    val references = mutableListOf<Position>();
    var reads = 0
}
fun canComplete(statement: Stmt): Boolean = when (val s = statement.kind) {
    is StmtKind.ReturnValue -> false;
    StmtKind.BreakLoop, StmtKind.ContinueLoop -> false;
    is StmtKind.Block -> s.statements.all {
        canComplete(it)
    };
    is StmtKind.Conditional -> s.no == null || canComplete(s.yes) || canComplete(s.no);
    else -> true
}
class Semantic {
    val symbols = mutableListOf<Symbol>();
    val globals = mutableMapOf<String, Int>();
    val scopes = mutableListOf<MutableMap<String, Int>>();
    val calls = mutableMapOf<Int, MutableSet<Int>>();
    var current: Function? = null
    fun failure(position: Position, reason: String): CompileError = CompileError("semantic", position, reason)
    fun add(variable: Variable, parameter: Boolean = false): Int {
        val id = symbols.size;
        variable.id = id;
        symbols.add(Symbol(variable.name, variable.type, variable, null, parameter));
        return id
    }
    fun add(function: Function): Int {
        val id = symbols.size;
        function.id = id;
        symbols.add(Symbol(function.name, function.type, null, function));
        return id
    }
    fun forbidden(expression: Expr): List<Position> = when (val e = expression.kind) {
        is ExprKind.VariableRef -> listOf(expression.position);
        ExprKind.Read -> listOf(expression.position);
        is ExprKind.Element -> listOf(expression.position) + forbidden(e.index);
        is ExprKind.Call -> listOf(expression.position) + e.arguments.flatMap {
            forbidden(it)
        };
        is ExprKind.Unary -> forbidden(e.value);
        is ExprKind.Binary -> forbidden(e.left) + forbidden(e.right);
        else -> emptyList()
    }
    fun analyze(program: Program) {
        for (declaration in program.declarations) {
            when (declaration) {
                is Top.VariableDecl -> {
                    val variable = declaration.variable;
                    val name = variable.name
                    if (variable.size != null) {
                        if (variable.type != ToyType.INT) throw failure(name.position, "array '${name.text}' must have element type int");
                        if (variable.size == 0) throw failure(variable.sizePosition!!, "array '${name.text}' must have a positive size")
                    }
                    else if (variable.type == ToyType.VOID) throw failure(name.position, "variable '${name.text}' cannot have type void")
                    if (name.text in globals) throw failure(name.position, "redeclaration of '${name.text}'")
                    val initializer = variable.initializer
                    if (initializer != null) {
                        forbidden(initializer).minOrNull()?.let {
                            throw failure(it, "global initializer must be constant")
                        };
                        if (this.expression(initializer) != variable.type) throw failure(name.position, "type mismatch in initialization of '${name.text}'")
                    }
                    globals[name.text] = add(variable)
                }
                is Top.FunctionDecl -> {
                    val function = declaration.function
                    if (function.name.text in globals) throw failure(function.name.position, "redeclaration of '${function.name.text}'")
                    val names = mutableSetOf<String>()
                    for (parameter in function.parameters) {
                        if (parameter.type == ToyType.VOID) throw failure(parameter.name.position, "parameter '${parameter.name.text}' cannot have type void");
                        if (!names.add(parameter.name.text)) throw failure(parameter.name.position, "redeclaration of '${parameter.name.text}'")
                    }
                    globals[function.name.text] = add(function)
                }
            }
        }
        val main = globals["main"]?.let {
            symbols[it].function
        } ?: throw failure(program.end, "no main function")
        if (main.type != ToyType.VOID || main.parameters.isNotEmpty()) throw failure(main.name.position, "main must be declared as 'void main()'")
        for (declaration in program.declarations) if (declaration is Top.FunctionDecl) {
            val function = declaration.function;
            current = function;
            scopes.clear();
            scopes.add(mutableMapOf());
            calls[function.id] = mutableSetOf()
            for (parameter in function.parameters) scopes[0][parameter.name.text] = add(parameter, true)
            for (statement in (function.body.kind as StmtKind.Block).statements) this.statement(statement, 0)
            if (function.type != ToyType.VOID && canComplete(function.body)) throw failure(function.name.position, "missing return in function '${function.name.text}'")
        }
        current = null;
        scopes.clear()
    }
    fun lookup(name: Name, read: Boolean, call: Boolean = false): Int {
        val id = scopes.asReversed().firstNotNullOfOrNull {
            it[name.text]
        } ?: globals[name.text] ?: throw failure(name.position, "undeclared ${if (call) "function" else "identifier"} '${name.text}'")
        symbols[id].references.add(name.position);
        if (read) symbols[id].reads++;
        return id
    }
    fun variable(name: Name, array: Boolean, read: Boolean): Int {
        val id = lookup(name, read);
        val symbol = symbols[id]
        if (symbol.function != null) throw failure(name.position, "'${name.text}' is a function, not a variable")
        if (!array && symbol.variable!!.size != null) throw failure(name.position, "array '${name.text}' used without index")
        if (array && symbol.variable!!.size == null) throw failure(name.position, "'${name.text}' is not an array")
        return id
    }
    fun expression(expression: Expr, callStatement: Boolean = false): ToyType {
        val type = when (val e = expression.kind) {
            is ExprKind.Integer -> ToyType.INT;
            ExprKind.Read -> ToyType.INT
            is ExprKind.BooleanValue -> ToyType.BOOL
            is ExprKind.VariableRef -> {
                val id = variable(e.name, false, true);
                expression.reference = id;
                symbols[id].type
            }
            is ExprKind.Element -> {
                val id = variable(e.name, true, true);
                expression.reference = id;
                if (this.expression(e.index) != ToyType.INT) throw failure(e.name.position, "index of '${e.name.text}' must be int");
                ToyType.INT
            }
            is ExprKind.Call -> {
                val id = lookup(e.name, true, true);
                expression.reference = id
                val function = symbols[id].function ?: throw failure(e.name.position, "'${e.name.text}' is not a function")
                if (e.arguments.size != function.parameters.size) throw failure(e.name.position, "wrong number of arguments to '${e.name.text}' (expected ${function.parameters.size}, found ${e.arguments.size})")
                for ((k, argument) in e.arguments.withIndex()) if (this.expression(argument) != function.parameters[k].type) throw failure(e.name.position, "argument ${k + 1} of '${e.name.text}' must be ${function.parameters[k].type.text}")
                if (!callStatement && function.type == ToyType.VOID) throw failure(e.name.position, "void function '${e.name.text}' used as a value")
                current?.let {
                    calls.getOrPut(it.id) {
                        mutableSetOf()
                    }.add(id)
                };
                function.type
            }
            is ExprKind.Unary -> {
                val found = this.expression(e.value);
                val required = if (e.op == "-") ToyType.INT else ToyType.BOOL;
                if (found != required) throw failure(expression.position, "operator '${e.op}' requires ${required.text} operand");
                found
            }
            is ExprKind.Binary -> {
                val a = this.expression(e.left);
                val b = this.expression(e.right)
                if (e.op in listOf("+", "-", "*", "/", "%", "<", "<=", ">", ">=")) {
                    if (a != ToyType.INT || b != ToyType.INT) throw failure(expression.position, "operator '${e.op}' requires int operands");
                    if (e.op in listOf("+", "-", "*", "/", "%")) ToyType.INT else ToyType.BOOL
                }
                else if (e.op in listOf("==", "!=")) {
                    if (a != b) throw failure(expression.position, "operator '${e.op}' requires operands of the same type");
                    ToyType.BOOL
                }
                else {
                    if (a != ToyType.BOOL || b != ToyType.BOOL) throw failure(expression.position, "operator '${e.op}' requires bool operands");
                    ToyType.BOOL
                }
            }
        }
        expression.type = type;
        return type
    }
    fun statement(statement: Stmt, loops: Int) {
        when (val s = statement.kind) {
            is StmtKind.Declaration -> {
                val variable = s.variable;
                val name = variable.name
                if (variable.type == ToyType.VOID) throw failure(name.position, "variable '${name.text}' cannot have type void")
                if (name.text in scopes.last()) throw failure(name.position, "redeclaration of '${name.text}'")
                val initializer = variable.initializer;
                if (initializer != null && this.expression(initializer) != variable.type) throw failure(name.position, "type mismatch in initialization of '${name.text}'")
                scopes.last()[name.text] = add(variable)
            }
            is StmtKind.Assignment -> {
                val id = variable(s.name, s.index != null, false);
                statement.reference = id;
                if (s.index != null && this.expression(s.index) != ToyType.INT) throw failure(s.name.position, "index of '${s.name.text}' must be int");
                if (this.expression(s.value) != symbols[id].type) throw failure(s.name.position, "type mismatch in assignment to '${s.name.text}'")
            }
            is StmtKind.Call -> this.expression(s.value, true)
            is StmtKind.Conditional -> {
                if (this.expression(s.condition) != ToyType.BOOL) throw failure(statement.position, "condition of 'if' must be bool");
                this.statement(s.yes, loops);
                s.no?.let {
                    this.statement(it, loops)
                }
            }
            is StmtKind.WhileLoop -> {
                if (this.expression(s.condition) != ToyType.BOOL) throw failure(statement.position, "condition of 'while' must be bool");
                this.statement(s.body, loops + 1)
            }
            is StmtKind.ForLoop -> {
                scopes.add(mutableMapOf());
                s.initial?.let {
                    this.statement(it, loops)
                };
                if (s.condition != null && this.expression(s.condition) != ToyType.BOOL) throw failure(statement.position, "condition of 'for' must be bool");
                s.update?.let {
                    this.statement(it, loops)
                };
                this.statement(s.body, loops + 1);
                scopes.removeAt(scopes.lastIndex)
            }
            StmtKind.BreakLoop -> if (loops == 0) throw failure(statement.position, "'break' outside loop")
            StmtKind.ContinueLoop -> if (loops == 0) throw failure(statement.position, "'continue' outside loop")
            is StmtKind.ReturnValue -> {
                val function = current!!
                if (function.type == ToyType.VOID && s.value != null) throw failure(statement.position, "function '${function.name.text}' must not return a value")
                if (function.type != ToyType.VOID) {
                    val value = s.value ?: throw failure(statement.position, "function '${function.name.text}' must return a value");
                    if (this.expression(value) != function.type) throw failure(statement.position, "return value of '${function.name.text}' must be ${function.type.text}")
                }
            }
            is StmtKind.Print -> for ((k, value) in s.values.withIndex()) if (this.expression(value) != ToyType.INT) throw failure(statement.position, "argument ${k + 1} of 'print' must be int")
            is StmtKind.Block -> {
                scopes.add(mutableMapOf());
                for (value in s.statements) this.statement(value, loops);
                scopes.removeAt(scopes.lastIndex)
            }
            StmtKind.Empty -> Unit
        }
    }
}
