import java.io.File
data class NameKey(val scope: Int?, val name: String)
data class CallSite(val name: String, val arguments: List<Expr>, val scope: Int?, val position: Position)
class StaticError(val position: Position, val reason: String) : Exception(reason)
class Preparation(val program: Program) {
    val globals = mutableSetOf("FILENAME", "FNR", "FS", "NF", "NR", "OFS", "ORS", "SUBSEP");
    val arrays = mutableSetOf<NameKey>();
    val uses = mutableListOf<Pair<NameKey, Position>>();
    val calls = mutableListOf<CallSite>();
    val lines = mutableMapOf<Int, Int>();
    val functions = mutableMapOf<String, Int>()
    fun key(scope: Int?, name: String): NameKey = NameKey(if (scope != null && program.functions[scope].parameters.any {
        it.first == name
    }) scope else null, name)
    fun name(scope: Int?, name: String, position: Position, array: Boolean) {
        val key = key(scope, name);
        if (key.scope == null) globals.add(name);
        if (array) arrays.add(key);
        uses.add(key to position)
    }
    fun expression(expression: Expr, scope: Int?) {
        when (val kind = expression.kind) {
            is ExprKind.Name -> name(scope, kind.name, expression.position, false)
            is ExprKind.Index -> {
                name(scope, kind.name, expression.position, true);
                for (index in kind.indices) this.expression(index, scope)
            }
            is ExprKind.Field -> this.expression(kind.index, scope)
            is ExprKind.Parentheses -> this.expression(kind.body, scope)
            is ExprKind.Unary -> this.expression(kind.body, scope)
            is ExprKind.Increment -> this.expression(kind.target, scope)
            is ExprKind.Binary -> {
                this.expression(kind.left, scope);
                this.expression(kind.right, scope)
            }
            is ExprKind.Assignment -> {
                this.expression(kind.target, scope);
                this.expression(kind.right, scope)
            }
            is ExprKind.Conditional -> {
                this.expression(kind.condition, scope);
                this.expression(kind.yes, scope);
                this.expression(kind.no, scope)
            }
            is ExprKind.Member -> {
                for (index in kind.indices) this.expression(index, scope);
                name(scope, kind.name, kind.namePosition, true)
            }
            is ExprKind.Call -> {
                if (!kind.builtin) calls.add(CallSite(kind.name, kind.arguments, scope, expression.position));
                for (argument in kind.arguments) this.expression(argument, scope);
                if (kind.builtin && kind.name == "split") arrays.add(key(scope, (kind.arguments[1].kind as ExprKind.Name).name))
            }
            is ExprKind.Getline -> {
                kind.target?.let {
                    this.expression(it, scope)
                };
                kind.file?.let {
                    this.expression(it, scope)
                }
            }
            else -> Unit
        }
    }
    fun statement(statement: Stmt, scope: Int?) {
        if (statement.kind !is StmtKind.Block && statement.kind != StmtKind.Empty) lines[statement.position.line] = 0
        when (val kind = statement.kind) {
            is StmtKind.Block -> for (child in kind.statements) this.statement(child, scope)
            is StmtKind.Expression -> expression(kind.expression, scope)
            is StmtKind.Conditional -> {
                expression(kind.condition, scope);
                this.statement(kind.yes, scope);
                kind.no?.let {
                    this.statement(it, scope)
                }
            }
            is StmtKind.While -> {
                expression(kind.condition, scope);
                this.statement(kind.body, scope)
            }
            is StmtKind.Do -> {
                this.statement(kind.body, scope);
                expression(kind.condition, scope)
            }
            is StmtKind.For -> {
                for (value in listOfNotNull(kind.initial, kind.condition, kind.update)) expression(value, scope);
                this.statement(kind.body, scope)
            }
            is StmtKind.ForIn -> {
                name(scope, kind.variable, kind.variablePosition, false);
                name(scope, kind.array, kind.arrayPosition, true);
                this.statement(kind.body, scope)
            }
            is StmtKind.Output -> {
                for (argument in kind.arguments) expression(argument, scope);
                kind.redirect?.let {
                    expression(it.expression, scope)
                }
            }
            is StmtKind.Delete -> {
                name(scope, kind.name, kind.namePosition, true);
                for (index in kind.indices ?: emptyList()) expression(index, scope)
            }
            is StmtKind.Exit -> kind.expression?.let {
                expression(it, scope)
            }
            is StmtKind.Return -> kind.expression?.let {
                expression(it, scope)
            }
            else -> Unit
        }
    }
    fun analyze() {
        val errors = mutableListOf<Triple<Position, Int, String>>()
        for ((i, function) in program.functions.withIndex()) {
            if (function.name in functions) errors.add(Triple(function.position, 0, "function ${function.name} redefined")) else functions[function.name] = i
            val parameters = mutableSetOf<String>()
            for ((name, position) in function.parameters) {
                if (!parameters.add(name)) errors.add(Triple(position, 1, "duplicate parameter $name"));
                uses.add(NameKey(i, name) to position)
            }
            statement(function.body, i)
        }
        for (rule in program.rules) {
            rule.start?.let {
                expression(it, null)
            };
            rule.end?.let {
                expression(it, null)
            };
            rule.action?.let {
                statement(it, null)
            }
        }
        for ((key, position) in uses) {
            if (key.name in functions) errors.add(Triple(position, 2, "function ${key.name} used as variable"))
        }
        val links = mutableListOf<Pair<NameKey, NameKey>>()
        for (call in calls) {
            val callee = functions[call.name]
            if (callee == null) errors.add(Triple(call.position, 3, "undefined function ${call.name}"))
            else {
                val parameters = program.functions[callee].parameters;
                if (call.arguments.size > parameters.size) errors.add(Triple(call.position, 4, "too many arguments to ${call.name}"));
                for ((argument, parameter) in call.arguments.zip(parameters)) {
                    val name = argument.kind as? ExprKind.Name;
                    if (name != null) links.add(key(call.scope, name.name) to NameKey(callee, parameter.first))
                }
            }
        }
        val error = errors.minWithOrNull(compareBy<Triple<Position, Int, String>> {
            it.first
        }.thenBy {
            it.second
        })
        if (error != null) throw StaticError(error.first, error.third)
        while (true) {
            var changed = false;
            for ((a, b) in links) {
                if (a in arrays || b in arrays) {
                    if (arrays.add(a)) changed = true;
                    if (arrays.add(b)) changed = true
                }
            };
            if (!changed) break
        }
    }
}
class AwkArray {
    val elements = mutableMapOf<String, Value>()
}
sealed interface Cell
class ScalarCell(val value: Value) : Cell
class ArrayCell(val array: AwkArray) : Cell
sealed interface Location {
    data class Variable(val frame: Int?, val name: String) : Location
    data class Element(val array: AwkArray, val key: String) : Location
    data class Field(val index: Int) : Location
}
class Flow(val kind: String, val value: Value = Value.Uninitialized) : Exception()
data class MainInput(val file: Int, val lines: List<String>, var position: Int = 0)
class Runtime(val program: Program, val preparation: Preparation, val arguments: Arguments) {
    val fields = Fields();
    val streams = Streams();
    val globals = mutableMapOf<String, Cell>();
    val locals = mutableListOf<MutableMap<String, Cell>>();
    var operand = 0;
    var current: MainInput? = null;
    var phase = "BEGIN";
    var status = 0
    val rules = IntArray(program.rules.size);
    val ranges = BooleanArray(program.rules.size);
    val calls = IntArray(program.functions.size);
    val active = IntArray(program.functions.size);
    val depths = IntArray(program.functions.size)
    init {
        for (name in preparation.globals) globals[name] = if (NameKey(null, name) in preparation.arrays) ArrayCell(AwkArray()) else ScalarCell(Value.Uninitialized);
        for ((name, value) in listOf("FS" to Value.Text(" "), "OFS" to Value.Text(" "), "ORS" to Value.Text(10.toChar().toString()), "SUBSEP" to Value.Text(28.toChar().toString()), "NR" to Value.Number(0), "FNR" to Value.Number(0), "FILENAME" to Value.Text(""))) globals[name] = ScalarCell(value)
    }
    fun frame(name: String): Int? = if (locals.lastOrNull()?.containsKey(name) == true) locals.lastIndex else null
    fun cell(frame: Int?, name: String): Cell? = if (frame == null) globals[name] else locals[frame][name]
    fun array(name: String): AwkArray = (cell(frame(name), name) as ArrayCell).array
    fun value(frame: Int?, name: String): Value = if (frame == null && name == "NF") Value.Number(fields.values.size) else (cell(frame, name) as? ScalarCell)?.value ?: Value.Uninitialized
    fun global(name: String): Value = value(null, name)
    fun key(expressions: List<Expr>): String {
        val keys = expressions.map {
            expression(it).text
        };
        return keys.joinToString(global("SUBSEP").text)
    }
    fun location(expression: Expr): Location = when (val kind = expression.kind) {
        is ExprKind.Name -> Location.Variable(frame(kind.name), kind.name)
        is ExprKind.Index -> {
            val key = key(kind.indices);
            Location.Element(array(kind.name), key)
        }
        is ExprKind.Field -> {
            val number = this.expression(kind.index).number;
            if (number < 0) throw RuntimeError(expression.position, "negative field index");
            Location.Field(number)
        }
        else -> error("not an lvalue")
    }
    fun read(location: Location): Value = when (location) {
        is Location.Variable -> value(location.frame, location.name);
        is Location.Element -> location.array.elements.getOrPut(location.key) {
            Value.Uninitialized
        };
        is Location.Field -> fields.get(location.index)
    }
    fun store(location: Location, value: Value, position: Position): Value {
        when (location) {
            is Location.Variable -> if (location.frame == null && location.name == "NF") {
                val n = value.number;
                if (n < 0) throw RuntimeError(position, "negative NF");
                fields.nf(n, global("OFS").text)
            } else if (location.frame != null) locals[location.frame][location.name] = ScalarCell(value) else {
                preparation.globals.add(location.name);
                globals[location.name] = ScalarCell(value)
            }
            is Location.Element -> location.array.elements[location.key] = value
            is Location.Field -> fields.assign(location.index, value, global("FS").text, global("OFS").text)
        }
        return read(location)
    }
    fun arithmetic(op: String, a: Int, b: Int, position: Position): Value {
        if (op in listOf("/", "%") && b == 0) throw RuntimeError(position, "division by zero")
        if (op == "^" && b < 0) throw RuntimeError(position, "negative exponent")
        val value = when (op) {
            "+" -> a + b;
            "-" -> a - b;
            "*" -> a * b;
            "/" -> a / b;
            "%" -> a % b;
            else -> {
                var result = 1;
                var base = a;
                var exponent = b;
                while (exponent > 0) {
                    if (exponent % 2 == 1) result *= base;
                    exponent /= 2;
                    if (exponent > 0) base *= base
                };
                result
            }
        }
        return Value.Number(value)
    }
    fun expression(expression: Expr): Value {
        val position = expression.position
        return when (val kind = expression.kind) {
            is ExprKind.Number -> Value.Number(kind.value)
            is ExprKind.Text -> Value.Text(kind.value)
            is ExprKind.Name, is ExprKind.Index, is ExprKind.Field -> read(location(expression))
            is ExprKind.Parentheses -> this.expression(kind.body)
            is ExprKind.Unary -> {
                val value = this.expression(kind.body);
                Value.Number(if (kind.op == "-") -value.number else if (kind.op == "+") value.number else if (value.truth) 0 else 1)
            }
            is ExprKind.Binary -> {
                val a = this.expression(kind.left)
                if (kind.op == "||" && a.truth) Value.Number(1) else if (kind.op == "&&" && !a.truth) Value.Number(0)
                else {
                    val b = this.expression(kind.right);
                    if (kind.op in listOf("||", "&&")) Value.Number(if (b.truth) 1 else 0) else if (kind.op == "concat") Value.Text(a.text + b.text) else if (kind.op in listOf("<", "<=", "==", "!=", ">=", ">")) {
                        val order = a.compare(b);
                        val result = when (kind.op) {
                            "<" -> order < 0;
                            "<=" -> order <= 0;
                            "==" -> order == 0;
                            "!=" -> order != 0;
                            ">=" -> order >= 0;
                            else -> order > 0
                        };
                        Value.Number(if (result) 1 else 0)
                    } else arithmetic(kind.op, a.number, b.number, position)
                }
            }
            is ExprKind.Assignment -> {
                val location = location(kind.target);
                val b = this.expression(kind.right);
                val value = if (kind.op == "=") b else arithmetic(kind.op.take(1), read(location).number, b.number, position);
                store(location, value, position)
            }
            is ExprKind.Increment -> {
                val location = location(kind.target);
                val value = read(location).number;
                store(location, Value.Number(value + kind.delta), position);
                Value.Number(if (kind.prefix) value + kind.delta else value)
            }
            is ExprKind.Conditional -> this.expression(if (this.expression(kind.condition).truth) kind.yes else kind.no)
            is ExprKind.Member -> {
                val key = key(kind.indices);
                Value.Number(if (key in array(kind.name).elements) 1 else 0)
            }
            is ExprKind.Call -> if (kind.builtin) builtin(kind.name, kind.arguments, position) else call(kind.name, kind.arguments)
            is ExprKind.Getline -> {
                val pair = if (kind.file != null) streams.getline(this.expression(kind.file).text) else if (phase == "END") 0 to null else {
                    val line = nextRecord();
                    (if (line == null) 0 else 1) to line
                }
                val line = pair.second
                if (line != null) {
                    if (kind.target != null) store(location(kind.target), Value.input(line), position) else fields.set(line, global("FS").text)
                }
                Value.Number(pair.first)
            }
        }
    }
    fun builtin(name: String, arguments: List<Expr>, position: Position): Value {
        if (name == "length") {
            if (arguments.isEmpty()) return Value.Number(fields.record.text.length);
            val single = arguments[0].kind as? ExprKind.Name;
            if (single != null) {
                val cell = cell(frame(single.name), single.name);
                if (cell is ArrayCell) return Value.Number(cell.array.elements.size)
            };
            return Value.Number(expression(arguments[0]).text.length)
        }
        if (name == "split") {
            val text = expression(arguments[0]).text;
            val separator = if (arguments.size == 3) expression(arguments[2]).text else global("FS").text;
            val array = array((arguments[1].kind as ExprKind.Name).name);
            val pieces = splitText(text, separator);
            array.elements.clear();
            for ((i, piece) in pieces.withIndex()) array.elements[(i + 1).toString()] = Value.input(piece);
            return Value.Number(pieces.size)
        }
        val values = arguments.map {
            expression(it)
        };
        return if (name == "close") Value.Number(streams.close(values[0].text)) else Builtins.scalar(name, values, position)
    }
    fun call(name: String, arguments: List<Expr>): Value {
        val index = preparation.functions.getValue(name);
        val function = program.functions[index];
        val local = mutableMapOf<String, Cell>()
        for ((i, parameter) in function.parameters.withIndex()) {
            local[parameter.first] = if (NameKey(index, parameter.first) in preparation.arrays) ArrayCell(if (i < arguments.size) array((arguments[i].kind as ExprKind.Name).name) else AwkArray()) else ScalarCell(if (i < arguments.size) expression(arguments[i]) else Value.Uninitialized)
        }
        calls[index]++;
        active[index]++;
        depths[index] = maxOf(depths[index], active[index]);
        locals.add(local)
        try {
            statement(function.body);
            return Value.Uninitialized
        } catch (flow: Flow) {
            if (flow.kind == "return") return flow.value;
            throw flow
        } finally {
            locals.removeAt(locals.lastIndex);
            active[index]--
        }
    }
    fun output(printf: Boolean, arguments: List<Expr>, redirect: Redirect?, position: Position) {
        val values = arguments.map {
            expression(it)
        }
        val text = if (printf) Builtins.format(values, position) else (if (values.isEmpty()) listOf(fields.record) else values).joinToString(global("OFS").text) {
            it.text
        } + global("ORS").text
        if (redirect != null) {
            val name = expression(redirect.expression).text;
            if (!validFile(name) || name in listOf("stdout.txt", "stats.txt")) throw RuntimeError(redirect.position, "invalid output file name");
            streams.output(name, redirect.append, text)
        } else streams.output(null, false, text)
    }
    fun loopBody(body: Stmt): Boolean = try {
        statement(body);
        true
    } catch (flow: Flow) {
        when (flow.kind) {
            "continue" -> true;
            "break" -> false;
            else -> throw flow
        }
    }
    fun statement(statement: Stmt) {
        val position = statement.position
        if (statement.kind !is StmtKind.Block && statement.kind != StmtKind.Empty) preparation.lines[position.line] = preparation.lines.getValue(position.line) + 1
        when (val kind = statement.kind) {
            is StmtKind.Block -> for (child in kind.statements) this.statement(child)
            StmtKind.Empty -> Unit
            is StmtKind.Expression -> {
                expression(kind.expression)
            }
            is StmtKind.Conditional -> if (expression(kind.condition).truth) this.statement(kind.yes) else kind.no?.let {
                this.statement(it)
            }
            is StmtKind.While -> {
                while (expression(kind.condition).truth) {
                    if (!loopBody(kind.body)) break
                }
            }
            is StmtKind.Do -> {
                do {
                    if (!loopBody(kind.body)) break
                } while (expression(kind.condition).truth)
            }
            is StmtKind.For -> {
                kind.initial?.let {
                    expression(it)
                };
                while (kind.condition == null || expression(kind.condition).truth) {
                    if (!loopBody(kind.body)) break;
                    kind.update?.let {
                        expression(it)
                    }
                }
            }
            is StmtKind.ForIn -> {
                val keys = array(kind.array).elements.keys.sortedWith(keyOrder);
                for (key in keys) {
                    store(Location.Variable(frame(kind.variable), kind.variable), Value.input(key), kind.variablePosition);
                    if (!loopBody(kind.body)) break
                }
            }
            is StmtKind.Output -> output(kind.printf, kind.arguments, kind.redirect, position)
            is StmtKind.Delete -> {
                val key = kind.indices?.let {
                    key(it)
                };
                val array = array(kind.name);
                if (key == null) array.elements.clear() else array.elements.remove(key)
            }
            StmtKind.Next -> {
                if (phase == "BEGIN" || phase == "END") throw RuntimeError(position, "next used in BEGIN or END");
                throw Flow("next")
            }
            StmtKind.Break -> throw Flow("break")
            StmtKind.Continue -> throw Flow("continue")
            is StmtKind.Exit -> {
                kind.expression?.let {
                    status = expression(it).number
                };
                throw Flow("exit")
            }
            is StmtKind.Return -> throw Flow("return", kind.expression?.let {
                expression(it)
            } ?: Value.Uninitialized)
        }
    }
    fun nextRecord(): String? {
        while (true) {
            val input = current
            if (input != null && input.position < input.lines.size) {
                val line = input.lines[input.position++];
                arguments.files[input.file].records++;
                val nr = global("NR").number + 1;
                val fnr = global("FNR").number + 1;
                globals["NR"] = ScalarCell(Value.Number(nr));
                globals["FNR"] = ScalarCell(Value.Number(fnr));
                return line
            }
            if (operand == arguments.operands.size) return null
            when (val next = arguments.operands[operand++]) {
                is Operand.Assignment -> {
                    preparation.globals.add(next.name);
                    globals[next.name] = ScalarCell(Value.input(next.value))
                }
                is Operand.Input -> {
                    globals["FILENAME"] = ScalarCell(Value.Text(next.name));
                    globals["FNR"] = ScalarCell(Value.Number(0));
                    current = MainInput(next.index, readFile(next.name)!!)
                }
            }
        }
    }
    fun testRule(rule: Rule, index: Int): Boolean {
        if (rule.kind == "all") return true
        if (rule.kind == "range") {
            if (!ranges[index] && expression(rule.start!!).truth) ranges[index] = true;
            val matched = ranges[index];
            if (matched && expression(rule.end!!).truth) ranges[index] = false;
            return matched
        }
        return expression(rule.start!!).truth
    }
    fun execute() {
        for ((name, value) in arguments.options) {
            preparation.globals.add(name);
            globals[name] = ScalarCell(Value.input(value))
        }
        var exiting = false
        for ((i, rule) in program.rules.withIndex()) {
            if (rule.kind == "BEGIN") {
                rules[i]++;
                try {
                    statement(rule.action!!)
                } catch (flow: Flow) {
                    if (flow.kind != "exit") throw flow;
                    exiting = true;
                    break
                }
            }
        }
        phase = "rules"
        if (!exiting && program.rules.any {
            it.kind != "BEGIN"
        }) {
            records@ while (true) {
                val record = nextRecord() ?: break;
                fields.set(record, global("FS").text)
                for ((i, rule) in program.rules.withIndex()) {
                    if (rule.kind in listOf("BEGIN", "END")) continue
                    try {
                        if (testRule(rule, i)) {
                            rules[i]++;
                            if (rule.action != null) statement(rule.action) else streams.output(null, false, fields.record.text + global("ORS").text)
                        }
                    }
                    catch (flow: Flow) {
                        if (flow.kind == "next") continue@records;
                        if (flow.kind == "exit") break@records;
                        throw flow
                    }
                }
            }
        }
        phase = "END"
        for ((i, rule) in program.rules.withIndex()) {
            if (rule.kind == "END") {
                rules[i]++;
                try {
                    statement(rule.action!!)
                } catch (flow: Flow) {
                    if (flow.kind != "exit") throw flow;
                    break
                }
            }
        }
    }
    fun report(status: String) {
        streams.save()
        val lines = mutableListOf(status, "[inputs]")
        for (file in arguments.files) lines.add("${file.name} records=${file.records}")
        lines.add("[getline]")
        for (input in streams.inputs) lines.add(if (input.opened) "${input.name} reads=${input.reads}" else "${input.name} missing")
        lines.add("[rules]")
        for ((i, rule) in program.rules.withIndex()) lines.add("${rule.position} ${rule.kind} count=${rules[i]}")
        lines.add("[functions]")
        for ((i, function) in program.functions.withIndex()) lines.add("${function.name} calls=${calls[i]} depth=${depths[i]}")
        lines.addAll(listOf("[outputs]", "stdout.txt writes=${streams.writes} bytes=${streams.stdout.length}"))
        for (output in streams.outputs) lines.add("${output.name} writes=${output.writes} bytes=${output.text.length}")
        lines.add("[lines]")
        for (line in preparation.lines.keys.sorted()) lines.add("$line count=${preparation.lines.getValue(line)}")
        lines.add("[globals]")
        for (name in preparation.globals.sorted()) {
            val cell = globals[name];
            val display = if (cell is ArrayCell) "array (${cell.array.elements.size})" else global(name).display;
            lines.add("$name = $display")
        }
        saveStats(lines)
    }
}
fun saveStats(lines: List<String>) {
    File("output").mkdirs();
    File("output/stats.txt").writeText(lines.joinToString("\n") + "\n")
}
fun failure(status: String) {
    File("output").mkdirs();
    File("output/stdout.txt").writeText("");
    saveStats(listOf(status))
}
fun main() {
    val program = try {
        Parser(Lexer.lex(File("input/program.awk").readText())).program()
    } catch (error: SyntaxError) {
        failure("status: syntax error at ${error.position}");
        return
    }
    val preparation = Preparation(program)
    try {
        preparation.analyze()
    } catch (error: StaticError) {
        failure("status: error at ${error.position}: ${error.reason}");
        return
    }
    val runtime = Runtime(program, preparation, arguments(File("input/args.txt").readText()))
    val status = try {
        runtime.execute();
        "status: exit ${runtime.status}"
    } catch (error: RuntimeError) {
        "status: runtime error at ${error.position}: ${error.reason}"
    }
    runtime.report(status)
}
