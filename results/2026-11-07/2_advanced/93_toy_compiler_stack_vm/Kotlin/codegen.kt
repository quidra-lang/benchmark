data class Instruction(var op: String, val operands: MutableList<Long>, val position: Position, val callee: Int? = null) {
    fun snapshot(): Instruction = copy(operands = operands.toMutableList())
}
data class CodeUnit(val name: String, val function: Function?, val slots: List<Variable>, val code: List<Instruction>)
class Label {
    var position: Int? = null
    val patches = mutableListOf<Int>()
}
class Codegen(val semantic: Semantic) {
    var code = mutableListOf<Instruction>()
    fun emit(op: String, args: List<Long>, position: Position, callee: Int? = null) {
        code.add(Instruction(op, args.toMutableList(), position, callee))
    }
    fun jump(op: String, label: Label, position: Position) {
        val i = code.size
        emit(op, listOf((label.position ?: 0).toLong()), position)
        if (label.position == null) label.patches.add(i)
    }
    fun mark(label: Label) {
        label.position = code.size
        for (i in label.patches) code[i].operands[0] = code.size.toLong()
    }
    fun expression(expression: Expr) {
        when (val e = expression.kind) {
            is ExprKind.Integer -> emit("PUSH", listOf(e.value), expression.position)
            is ExprKind.BooleanValue -> emit("PUSH", listOf(if (e.value) 1L else 0L), expression.position)
            ExprKind.Read -> emit("READ", emptyList(), expression.position)
            is ExprKind.VariableRef -> {
                val variable = semantic.symbols[expression.reference!!].variable!!
                emit(if (variable.address >= 0) "LOADG" else "LOADL", listOf((if (variable.address >= 0) variable.address else variable.slot).toLong()), expression.position)
            }
            is ExprKind.Element -> {
                this.expression(e.index)
                val variable = semantic.symbols[expression.reference!!].variable!!
                emit("LOADA", listOf(variable.address.toLong(), variable.size!!.toLong()), expression.position)
            }
            is ExprKind.Call -> {
                for (argument in e.arguments) this.expression(argument)
                emit("CALL", listOf(0L, e.arguments.size.toLong()), expression.position, expression.reference)
            }
            is ExprKind.Unary -> {
                this.expression(e.value)
                emit(if (e.op == "-") "NEG" else "NOT", emptyList(), expression.position)
            }
            is ExprKind.Binary -> {
                this.expression(e.left)
                if (e.op in listOf("&&", "||")) {
                    val alternate = Label()
                    val end = Label()
                    jump(if (e.op == "&&") "JUMPF" else "JUMPT", alternate, expression.position)
                    this.expression(e.right)
                    jump("JUMP", end, expression.position)
                    mark(alternate)
                    emit("PUSH", listOf(if (e.op == "&&") 0L else 1L), expression.position)
                    mark(end)
                }
                else {
                    this.expression(e.right)
                    emit(mapOf("+" to "ADD", "-" to "SUB", "*" to "MUL", "/" to "DIV", "%" to "MOD", "<" to "LT", "<=" to "LE", ">" to "GT", ">=" to "GE", "==" to "EQ", "!=" to "NE").getValue(e.op), emptyList(), expression.position)
                }
            }
        }
    }
    fun statement(statement: Stmt, breakLabel: Label? = null, continueLabel: Label? = null) {
        when (val s = statement.kind) {
            StmtKind.Empty -> Unit
            is StmtKind.Block -> for (value in s.statements) this.statement(value, breakLabel, continueLabel)
            is StmtKind.Declaration -> {
                val variable = s.variable
                variable.initializer?.let {
                    this.expression(it)
                } ?: emit("PUSH", listOf(0), variable.name.position)
                emit("STOREL", listOf(variable.slot.toLong()), variable.name.position)
            }
            is StmtKind.Assignment -> {
                val variable = semantic.symbols[statement.reference!!].variable!!
                s.index?.let {
                    this.expression(it)
                }
                this.expression(s.value)
                if (s.index != null) emit("STOREA", listOf(variable.address.toLong(), variable.size!!.toLong()), statement.position) else emit(if (variable.address >= 0) "STOREG" else "STOREL", listOf((if (variable.address >= 0) variable.address else variable.slot).toLong()), statement.position)
            }
            is StmtKind.Call -> {
                this.expression(s.value)
                if (s.value.type != ToyType.VOID) emit("POP", emptyList(), statement.position)
            }
            is StmtKind.Print -> {
                for (value in s.values) this.expression(value)
                emit("PRINT", listOf(s.values.size.toLong()), statement.position)
            }
            is StmtKind.Conditional -> {
                val alternate = Label()
                this.expression(s.condition)
                jump("JUMPF", alternate, statement.position)
                this.statement(s.yes, breakLabel, continueLabel)
                if (s.no != null) {
                    val end = Label()
                    jump("JUMP", end, statement.position)
                    mark(alternate)
                    this.statement(s.no, breakLabel, continueLabel)
                    mark(end)
                } else mark(alternate)
            }
            is StmtKind.WhileLoop -> {
                val start = Label()
                val end = Label()
                mark(start)
                this.expression(s.condition)
                jump("JUMPF", end, statement.position)
                this.statement(s.body, end, start)
                jump("JUMP", start, statement.position)
                mark(end)
            }
            is StmtKind.ForLoop -> {
                s.initial?.let {
                    this.statement(it, breakLabel, continueLabel)
                }
                val start = Label()
                val next = Label()
                val end = Label()
                mark(start)
                s.condition?.let {
                    this.expression(it)
                    jump("JUMPF", end, statement.position)
                }
                this.statement(s.body, end, next)
                mark(next)
                s.update?.let {
                    this.statement(it, breakLabel, continueLabel)
                }
                jump("JUMP", start, statement.position)
                mark(end)
            }
            StmtKind.BreakLoop -> jump("JUMP", breakLabel!!, statement.position)
            StmtKind.ContinueLoop -> jump("JUMP", continueLabel!!, statement.position)
            is StmtKind.ReturnValue -> if (s.value != null) {
                this.expression(s.value)
                emit("RETV", emptyList(), statement.position)
            } else emit("RET", emptyList(), statement.position)
        }
    }
    fun declarations(statement: Stmt): List<Variable> = when (val s = statement.kind) {
        is StmtKind.Declaration -> listOf(s.variable)
        is StmtKind.Block -> s.statements.flatMap {
            declarations(it)
        }
        is StmtKind.Conditional -> declarations(s.yes) + (s.no?.let {
            declarations(it)
        } ?: emptyList())
        is StmtKind.WhileLoop -> declarations(s.body)
        is StmtKind.ForLoop -> (s.initial?.let {
            declarations(it)
        } ?: emptyList()) + declarations(s.body) + (s.update?.let {
            declarations(it)
        } ?: emptyList())
        else -> emptyList()
    }
    fun generate(program: Program, reachable: Set<Int>): Pair<List<CodeUnit>, Int> {
        var area = 0
        val units = mutableListOf<CodeUnit>()
        for (declaration in program.declarations) if (declaration is Top.VariableDecl) {
            declaration.variable.address = area
            area += declaration.variable.size ?: 1
        }
        for (declaration in program.declarations) if (declaration is Top.VariableDecl) declaration.variable.initializer?.let {
            this.expression(it)
            emit("STOREG", listOf(declaration.variable.address.toLong()), declaration.variable.name.position)
        }
        val mainID = semantic.globals.getValue("main")
        val main = semantic.symbols[mainID].function!!
        emit("CALL", listOf(0, 0), main.name.position, mainID)
        emit("HALT", emptyList(), main.name.position)
        units.add(CodeUnit("<init>", null, emptyList(), code.toList()))
        for (declaration in program.declarations) if (declaration is Top.FunctionDecl && declaration.function.id in reachable) {
            val function = declaration.function
            val slots = function.parameters + declarations(function.body).sortedBy {
                it.name.position
            }
            for ((i, variable) in slots.withIndex()) variable.slot = i
            code = mutableListOf()
            emit("ENTER", listOf(slots.size.toLong()), function.name.position)
            this.statement(function.body)
            if (function.type == ToyType.VOID) emit("RET", emptyList(), (function.body.kind as StmtKind.Block).close)
            units.add(CodeUnit(function.name.text, function, slots, code.toList()))
        }
        return Pair(units, area)
    }
}
