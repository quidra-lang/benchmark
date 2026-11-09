import java.io.File
fun quote(value: String): String = "\"" + buildString {
    for (c in value) append(when (c) {
        '\\' -> "\\\\"; '"' -> "\\\""; '\n' -> "\\n"; '\t' -> "\\t"; else -> c.toString()
    })
} + "\""
fun valueString(value: Value): String = when (value) {
    is Value.Integer -> value.value.toString()
    is Value.BooleanValue -> value.value.toString()
    is Value.StringValue -> quote(value.value)
    is Value.PairValue -> "(${valueString(value.first)}, ${valueString(value.second)})"
    is Value.ListValue -> value.values.joinToString("; ", "[", "]") {
        valueString(it)
    }
    else -> "<fun>"
}
fun editDistance(a: String, b: String): Int {
    var row = (0..b.length).toList()
    for ((i, x) in a.withIndex()) {
        val next = mutableListOf(i + 1); for ((j, y) in b.withIndex()) next.add(minOf(next[j] + 1, row[j + 1] + 1, row[j] + if (x == y) 0 else 1)); row = next
    }; return row[b.length]
}
class TypePrinter(val unifier: Unifier, val quantified: Set<Int>? = null) {
    val names = mutableMapOf<Int, String>()
    fun write(type: MLType): String = when (val t = unifier.resolve(type)) {
        MLType.IntType -> "int"
        MLType.BoolType -> "bool"
        MLType.StringType -> "string"
        is MLType.Variable -> names.getOrPut(t.id) {
            val k = names.size; "'" + (if (quantified != null && t.id !in quantified) "_" else "") + ('a'.code + k % 26).toChar() + if (k >= 26) (k / 26).toString() else ""
        }
        is MLType.ListType -> wrap(t.element, true) + " list"
        is MLType.PairType -> wrap(t.first, true) + " * " + wrap(t.second, true)
        is MLType.Function -> wrap(t.argument, false) + " -> " + write(t.result)
    }
    fun wrap(type: MLType, pair: Boolean): String {
        val t = unifier.resolve(type); val text = write(t); return if (t is MLType.Function || pair && t is MLType.PairType) "($text)" else text
    }
}
fun errorMessage(error: TypeError, unifier: Unifier): String {
    val printer = TypePrinter(unifier)
    return when (val kind = error.kind) {
        is TypeErrorKind.Message -> kind.text
        is TypeErrorKind.Function -> "expected a function but found ${printer.write(kind.type)}"
        is TypeErrorKind.Check -> {
            var message = "expected ${printer.write(kind.expected)} but found ${printer.write(kind.found)}"
            val failure = kind.failure
            if (failure.occurs) {
                val variable = if (failure.expected is MLType.Variable) failure.expected else failure.found; val other = if (failure.expected is MLType.Variable) failure.found else failure.expected; message += " (infinite type ${printer.write(variable)} = ${printer.write(other)})"
            }
            else if (failure.nested) message += " (${printer.write(failure.expected)} vs ${printer.write(failure.found)})"
            message
        }
    }
}
fun signatureType(type: TypeExpression, unifier: Unifier, variables: MutableMap<String, MLType>): MLType = when (type) {
    is TypeExpression.Primitive -> when (type.name) {
        "int" -> MLType.IntType; "bool" -> MLType.BoolType; else -> MLType.StringType
    }
    is TypeExpression.Variable -> variables.getOrPut(type.name) {
        unifier.fresh()
    }
    is TypeExpression.ListType -> MLType.ListType(signatureType(type.element, unifier, variables))
    is TypeExpression.PairType -> MLType.PairType(signatureType(type.first, unifier, variables), signatureType(type.second, unifier, variables))
    is TypeExpression.Function -> MLType.Function(signatureType(type.argument, unifier, variables), signatureType(type.result, unifier, variables))
}
fun signatureMatches(inferred: MLType, declared: MLType, unifier: Unifier, assigned: MutableMap<Int, MLType>): Boolean {
    val a = unifier.resolve(inferred); val b = unifier.resolve(declared)
    if (a is MLType.Variable) {
        val old = assigned[a.id]; if (old != null) return old == b; assigned[a.id] = b; return true
    }
    return when {
        a is MLType.ListType && b is MLType.ListType -> signatureMatches(a.element, b.element, unifier, assigned)
        a is MLType.PairType && b is MLType.PairType -> signatureMatches(a.first, b.first, unifier, assigned) && signatureMatches(a.second, b.second, unifier, assigned)
        a is MLType.Function && b is MLType.Function -> signatureMatches(a.argument, b.argument, unifier, assigned) && signatureMatches(a.result, b.result, unifier, assigned)
        else -> a == b
    }
}
fun typeSyntax(type: TypeExpression): String {
    fun wrap(t: TypeExpression, pair: Boolean): String {
        val text = typeSyntax(t); return if (t is TypeExpression.Function || pair && t is TypeExpression.PairType) "($text)" else text
    }
    return when (type) {
        is TypeExpression.Primitive -> type.name; is TypeExpression.Variable -> type.name; is TypeExpression.ListType -> wrap(type.element, true) + " list"; is TypeExpression.PairType -> wrap(type.first, true) + " * " + wrap(type.second, true); is TypeExpression.Function -> wrap(type.argument, false) + " -> " + typeSyntax(type.result)
    }
}
fun patternString(p: Pattern): String = when (p) {
    is WildPattern -> "_"
    is NamePattern -> p.name
    is IntPattern -> p.value.toString()
    is BoolPattern -> p.value.toString()
    is StringPattern -> quote(p.value)
    is ListPattern -> p.elements.joinToString("; ", "[", "]") {
        patternString(it)
    }
    is PairPattern -> "(${patternString(p.first)}, ${patternString(p.second)})"
    is ConsPattern -> (if (p.head is ConsPattern) "(${patternString(p.head)})" else patternString(p.head)) + " :: " + patternString(p.tail)
}
fun groupString(group: Group): String = "let " + (if (group.recursive != null) "rec " else "") + group.bindings.joinToString(" and ") {
    binding -> var body = binding.expression; val names = mutableListOf(binding.name); while (body is Lambda) {
        names.add(body.parameter.name ?: "_"); body = body.body
    }; names.joinToString(" ") + " = " + expressionString(body, 0)
}
fun endsInMatch(e: Expr): Boolean = when (e) {
    is Match -> true; is LetIn -> endsInMatch(e.body); is Lambda -> endsInMatch(e.body); is Conditional -> endsInMatch(e.no); else -> false
}
fun expressionString(e: Expr, required: Int): String {
    val strength: Int; val text: String
    when (e) {
        is IntExpr -> {
            strength = 9; text = e.value.toString()
        }
        is BoolExpr -> {
            strength = 9; text = e.value.toString()
        }
        is StringExpr -> {
            strength = 9; text = quote(e.value)
        }
        is NameExpr -> {
            strength = 9; text = e.name
        }
        is Lambda -> {
            var body: Expr = e; val names = mutableListOf<String>(); while (body is Lambda) {
                names.add(body.parameter.name ?: "_"); body = body.body
            }; strength = 0; text = "fun " + names.joinToString(" ") + " -> " + expressionString(body, 0)
        }
        is Apply -> {
            strength = 8; text = expressionString(e.function, 8) + " " + expressionString(e.argument, 9)
        }
        is Binary -> {
            val k = precedence(e.op); val right = rightAssociative(e.op); strength = k; text = expressionString(e.left, k + if (right) 1 else 0) + " " + e.op + " " + expressionString(e.right, k + if (right) 0 else 1)
        }
        is Negate -> {
            strength = 7; text = "-" + expressionString(e.operand, 7)
        }
        is Conditional -> {
            strength = 0; text = "if ${expressionString(e.condition, 0)} then ${expressionString(e.yes, 0)} else ${expressionString(e.no, 0)}"
        }
        is PairExpr -> {
            strength = 9; text = "(${expressionString(e.first, 0)}, ${expressionString(e.second, 0)})"
        }
        is ListExpr -> {
            strength = 9; text = e.elements.joinToString("; ", "[", "]") {
                expressionString(it, 0)
            }
        }
        is LetIn -> {
            strength = 0; text = groupString(e.group) + " in " + expressionString(e.body, 0)
        }
        is Match -> {
            strength = 0; text = "match " + expressionString(e.value, 0) + " with " + e.arms.mapIndexed {
                i, (pattern, body) -> val written = expressionString(body, 0); patternString(pattern) + " -> " + if (i + 1 < e.arms.size && endsInMatch(body)) "($written)" else written
            }.joinToString(" | ")
        }
    }
    return if (strength < required) "($text)" else text
}
fun itemString(item: Item): String = when (item) {
    is Item.Signature -> "val ${item.name} : ${typeSyntax(item.type)};;"; is Item.Declaration -> groupString(item.group) + ";;"; is Item.Expression -> expressionString(item.expression, 0) + ";;"
}
sealed interface Cover {
    data object Wild : Cover
    data class Constructor(val name: String, val arguments: List<Cover> = emptyList()) : Cover
}
fun cover(p: Pattern): Cover = when (p) {
    is WildPattern, is NamePattern -> Cover.Wild
    is IntPattern -> Cover.Constructor("i${p.value}")
    is StringPattern -> Cover.Constructor("s" + quote(p.value))
    is BoolPattern -> Cover.Constructor(p.value.toString())
    is ListPattern -> p.elements.asReversed().fold<Pattern, Cover>(Cover.Constructor("nil")) {
        tail, head -> Cover.Constructor("cons", listOf(cover(head), tail))
    }
    is ConsPattern -> Cover.Constructor("cons", listOf(cover(p.head), cover(p.tail)))
    is PairPattern -> Cover.Constructor("pair", listOf(cover(p.first), cover(p.second)))
}
fun constructorArguments(type: MLType, name: String): List<MLType> = when {
    type is MLType.ListType && name == "cons" -> listOf(type.element, type); type is MLType.PairType -> listOf(type.first, type.second); else -> emptyList()
}
fun specialize(matrix: List<List<Cover>>, name: String, arity: Int): List<List<Cover>> = matrix.mapNotNull {
    row -> when (val first = row[0]) {
        Cover.Wild -> List(arity) {
            Cover.Wild
        } + row.drop(1); is Cover.Constructor -> if (first.name == name) first.arguments + row.drop(1) else null
    }
}
fun useful(matrix: List<List<Cover>>, vector: List<Cover>, types: List<MLType>): Boolean {
    if (vector.isEmpty()) return matrix.isEmpty()
    val first = vector[0]
    if (first is Cover.Constructor) return useful(specialize(matrix, first.name, first.arguments.size), first.arguments + vector.drop(1), constructorArguments(types[0], first.name) + types.drop(1))
    val family = when (types[0]) {
        MLType.BoolType -> listOf("false", "true"); is MLType.ListType -> listOf("nil", "cons"); is MLType.PairType -> listOf("pair"); else -> emptyList()
    }
    val present = matrix.mapNotNull {
        (it[0] as? Cover.Constructor)?.name
    }.toSet()
    if (family.isNotEmpty() && family.all {
        it in present
    }) {
        for (name in family) {
            val arguments = constructorArguments(types[0], name); if (useful(specialize(matrix, name, arguments.size), List(arguments.size) {
                Cover.Wild
            } + vector.drop(1), arguments + types.drop(1))) return true
        }; return false
    }
    return useful(matrix.filter {
        it[0] == Cover.Wild
    }.map {
        it.drop(1)
    }, vector.drop(1), types.drop(1))
}
typealias Scope = Map<String, Position>
data class Reference(val target: Position, val tail: Boolean)
fun patternNames(p: Pattern): List<Pair<String, Position>> = when (p) {
    is NamePattern -> listOf(Pair(p.name, p.position)); is ConsPattern -> patternNames(p.head) + patternNames(p.tail); is PairPattern -> patternNames(p.first) + patternNames(p.second); is ListPattern -> p.elements.flatMap {
        patternNames(it)
    }; else -> emptyList()
}
fun pureReferences(e: Expr, scope: Scope, tail: Boolean): List<Reference> = when (e) {
    is NameExpr -> scope[e.name]?.let {
        listOf(Reference(it, false))
    } ?: emptyList()
    is Lambda -> pureReferences(e.body, if (e.parameter.name != null) scope + (e.parameter.name to e.parameter.position) else scope, false)
    is Apply -> {
        var head: Expr = e; val arguments = mutableListOf<Expr>(); while (head is Apply) {
            arguments.add(head.argument); head = head.function
        }; val references = if (head is NameExpr) scope[head.name]?.let {
            listOf(Reference(it, tail))
        } ?: emptyList() else pureReferences(head, scope, false)
        references + arguments.asReversed().flatMap {
            pureReferences(it, scope, false)
        }
    }
    is Binary -> pureReferences(e.left, scope, false) + pureReferences(e.right, scope, tail && e.op in listOf("&&", "||"))
    is Negate -> pureReferences(e.operand, scope, false)
    is Conditional -> pureReferences(e.condition, scope, false) + pureReferences(e.yes, scope, tail) + pureReferences(e.no, scope, tail)
    is PairExpr -> pureReferences(e.first, scope, false) + pureReferences(e.second, scope, false)
    is ListExpr -> e.elements.flatMap {
        pureReferences(it, scope, false)
    }
    is Match -> pureReferences(e.value, scope, false) + e.arms.flatMap {
        (pattern, body) -> pureReferences(body, scope + patternNames(pattern), tail)
    }
    is LetIn -> {
        val inner = scope + e.group.bindings.associate {
            it.name to it.position
        }; e.group.bindings.flatMap {
            pureReferences(it.expression, if (e.group.recursive != null) inner else scope, false)
        } + pureReferences(e.body, inner, tail)
    }
    else -> emptyList()
}
data class Warning(val position: Position, val order: Int, val message: String)
class Inspection {
    val warnings = mutableListOf<Warning>(); val classifications = mutableMapOf<Position, String>(); val candidates = mutableMapOf<Position, String>()
    fun group(group: Group, scope: Scope, top: Boolean, context: Inference): Scope {
        val inner = scope.toMutableMap()
        for (binding in group.bindings) {
            inner[binding.name] = binding.position; if (!top) candidates[binding.position] = binding.name
        }
        val rhs = if (group.recursive != null) inner else scope
        for (binding in group.bindings) walk(binding.expression, rhs, context)
        if (group.recursive != null) {
            val names = group.bindings.map {
                it.position
            }.toSet(); val references = group.bindings.flatMap {
                pureReferences(it.expression, inner, false)
            }
            if (references.none {
                it.target in names
            }) warnings.add(Warning(group.recursive, 3, "unused rec flag"))
            for (binding in group.bindings) {
                var body = binding.expression; val bodyScope = inner.toMutableMap()
                while (body is Lambda) {
                    val parameter = body.parameter; parameter.name?.let {
                        bodyScope[it] = parameter.position
                    }; body = body.body
                }
                val refs = pureReferences(body, bodyScope, true).filter {
                    it.target in names
                }
                if (refs.isNotEmpty()) classifications[binding.position] = if (refs.all {
                    it.tail
                }) "tail recursive" else "recursive"
            }
        }
        return inner
    }
    fun walk(e: Expr, scope: Scope, context: Inference) {
        when (e) {
            is Lambda -> {
                val inner = scope.toMutableMap(); e.parameter.name?.let {
                    candidates[e.parameter.position] = it; inner[it] = e.parameter.position
                }; walk(e.body, inner, context)
            }
            is Apply -> {
                walk(e.function, scope, context); walk(e.argument, scope, context)
            }
            is PairExpr -> {
                walk(e.first, scope, context); walk(e.second, scope, context)
            }
            is Binary -> {
                walk(e.left, scope, context); walk(e.right, scope, context)
            }
            is Negate -> walk(e.operand, scope, context)
            is Conditional -> {
                walk(e.condition, scope, context); walk(e.yes, scope, context); walk(e.no, scope, context)
            }
            is ListExpr -> e.elements.forEach {
                walk(it, scope, context)
            }
            is LetIn -> {
                val inner = group(e.group, scope, false, context); walk(e.body, inner, context)
            }
            is Match -> {
                val (originalType, patterns) = context.matches.getValue(e.position); val type = context.unifier.resolve(originalType); val matrix = mutableListOf<List<Cover>>()
                for ((i, pattern) in patterns.withIndex()) {
                    val candidate = cover(pattern); if (i > 0 && !useful(matrix, listOf(candidate), listOf(type))) warnings.add(Warning(pattern.position, 2, "this match case is unused")); matrix.add(listOf(candidate))
                }
                if (useful(matrix, listOf(Cover.Wild), listOf(type))) warnings.add(Warning(e.position, 1, "this match is not exhaustive"))
                walk(e.value, scope, context)
                for ((pattern, body) in e.arms) {
                    val names = patternNames(pattern); for ((name, position) in names) candidates[position] = name; walk(body, scope + names, context)
                }
            }
            else -> Unit
        }
    }
    fun finish(references: List<Reference>) {
        val used = references.map {
            it.target
        }.toSet()
        for ((position, name) in candidates) if (!name.startsWith("_") && position !in used) warnings.add(Warning(position, 4, "unused variable '$name'"))
        warnings.sortWith(compareBy<Warning> {
            it.position
        }.thenBy {
            it.order
        })
    }
}
fun inspect(item: Item, scope: Scope, context: Inference): Inspection {
    val inspection = Inspection()
    val references = when (item) {
        is Item.Declaration -> {
            val inner = inspection.group(item.group, scope, true, context); item.group.bindings.flatMap {
                pureReferences(it.expression, if (item.group.recursive != null) inner else scope, false)
            }
        }; is Item.Expression -> {
            inspection.walk(item.expression, scope, context); pureReferences(item.expression, scope, false)
        }; else -> emptyList()
    }
    inspection.finish(references); return inspection
}
fun builtins(unifier: Unifier): Pair<TypeEnvironment, ValueEnvironment> {
    val types = mutableMapOf<String, Scheme>(); val a = unifier.fresh(); val b = unifier.fresh(); val fst = MLType.Function(MLType.PairType(a, b), a); types["fst"] = Scheme(fst, unifier.variables(fst))
    val c = unifier.fresh(); val d = unifier.fresh(); val snd = MLType.Function(MLType.PairType(c, d), d); types["snd"] = Scheme(snd, unifier.variables(snd)); types["not"] = Scheme(MLType.Function(MLType.BoolType, MLType.BoolType)); types["string_of_int"] = Scheme(MLType.Function(MLType.IntType, MLType.StringType))
    val result = unifier.fresh(); val fail = MLType.Function(MLType.StringType, result); types["failwith"] = Scheme(fail, unifier.variables(fail))
    return Pair(types, listOf("fst", "snd", "not", "string_of_int", "failwith").associateWith {
        Value.Builtin(it)
    })
}
fun applyBuiltin(name: String, argument: Value, position: Position): Value = when (name) {
    "fst" -> (argument as Value.PairValue).first
    "snd" -> (argument as Value.PairValue).second
    "not" -> Value.BooleanValue(!(argument as Value.BooleanValue).value)
    "string_of_int" -> Value.StringValue((argument as Value.Integer).value.toString())
    "failwith" -> throw RuntimeError(position, "failure " + quote((argument as Value.StringValue).value))
    else -> error("unknown builtin")
}
data class Signature(val position: Position, val type: TypeExpression)
class Diagnostic(val position: Position, val text: String) : Exception(text)
fun report(position: Position, kind: String, message: String, sources: List<List<String>>, output: MutableList<String>) {
    val name = listOf("prelude.ml", "program.ml")[position.file]; output.add("$name:${position.line}:${position.column}: $kind: $message")
    if (position.line <= sources[position.file].size) {
        output.add("    " + sources[position.file][position.line - 1]); output.add(" ".repeat(position.column + 3) + "^")
    }
}
fun write(name: String, lines: List<String>) {
    File("output").mkdirs(); File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    val fileNames = listOf("prelude.ml", "program.ml"); val texts = fileNames.map {
        File("input/$it").readText()
    }; val sources = texts.map {
        it.split('\n').dropLast(1)
    }; val context = Inference(); val evaluator = Evaluator()
    val initial = builtins(context.unifier); var typeEnvironment = initial.first; var valueEnvironment = initial.second; val scope = mutableMapOf<String, Position>(); val types = mutableListOf<String>(); val values = mutableListOf<String>(); val errors = mutableListOf<String>(); val formatted = mutableListOf<String>(); val statistics = Array(2) {
        IntArray(7)
    }
    for (file in 0..1) {
        types.add("== ${fileNames[file]} =="); values.add("== ${fileNames[file]} =="); formatted.add("(* ${fileNames[file]} *)")
        val pending = mutableMapOf<String, Signature>(); val parser = Parser(Lexer.lex(texts[file], file)); evaluator.calls = 0
        while (parser.peek.kind != "eof") {
            statistics[file][0]++; val item: Item
            try {
                item = parser.item()
            } catch (error: SyntaxError) {
                val token = error.token; val message = when (token.kind) {
                    "invalid" -> token.value; "eof" -> "unexpected end of file"; else -> "unexpected '${token.spelling}'"
                }; statistics[file][2]++; report(token.position, "syntax error", message, sources, errors); parser.recover(); continue
            }
            formatted.add(itemString(item))
            if (item is Item.Signature) {
                val old = pending.put(item.name, Signature(item.position, item.type)); if (old != null) {
                    statistics[file][5]++; report(old.position, "warning", "signature for '${item.name}' is never used", sources, errors)
                }; continue
            }
            context.clear(); val nextTypes: TypeEnvironment; val schemes: List<Scheme>; val expressionType: MLType?
            try {
                if (item is Item.Declaration) {
                    val signatures = item.group.bindings.map {
                        pending.remove(it.name)
                    }; val inferred = context.group(item.group, typeEnvironment, false); val next = inferred.first.toMutableMap(); val checked = inferred.second.toMutableList()
                    for ((i, signature) in signatures.withIndex()) if (signature != null) {
                        val declared = signatureType(signature.type, context.unifier, mutableMapOf())
                        if (!signatureMatches(checked[i].type, declared, context.unifier, mutableMapOf())) {
                            val printer = TypePrinter(context.unifier); throw Diagnostic(item.group.bindings[i].position, "'${item.group.bindings[i].name}' has type ${printer.write(checked[i].type)} but its signature is ${printer.write(declared)}")
                        }
                        checked[i] = Scheme(declared, context.unifier.variables(declared)); next[item.group.bindings[i].name] = checked[i]
                    }
                    nextTypes = next; schemes = checked; expressionType = null
                } else {
                    val expression = (item as Item.Expression).expression; expressionType = context.expression(expression, typeEnvironment); nextTypes = typeEnvironment; schemes = emptyList()
                }
            } catch (error: TypeError) {
                statistics[file][3]++; report(error.position, "type error", errorMessage(error, context.unifier), sources, errors); continue
            } catch (error: Diagnostic) {
                statistics[file][3]++; report(error.position, "type error", error.text, sources, errors); continue
            }
            val inspected = inspect(item, scope, context)
            fun classification(position: Position): String = inspected.classifications[position]?.let {
                " ($it)"
            } ?: ""
            if (item is Item.Declaration) {
                for ((binding, scheme) in item.group.bindings.zip(schemes)) types.add("${binding.name} : ${TypePrinter(context.unifier).write(scheme.type)}" + classification(binding.position))
            }
            else types.add("- : " + TypePrinter(context.unifier).write(expressionType!!))
            for (local in context.locals.sortedBy {
                it.position
            }) types.add("  ${local.name} (${local.position.line}:${local.position.column}) : ${TypePrinter(context.unifier, local.scheme.quantified).write(local.scheme.type)}" + classification(local.position))
            for (warning in inspected.warnings) {
                statistics[file][5]++; report(warning.position, "warning", warning.message, sources, errors)
            }
            val nextValues: ValueEnvironment; val evaluated: List<Value>
            try {
                if (item is Item.Declaration) {
                    val result = evaluator.group(item.group, valueEnvironment); nextValues = result.first; evaluated = result.second
                } else {
                    evaluated = listOf(evaluator.expression((item as Item.Expression).expression, valueEnvironment)); nextValues = valueEnvironment
                }
            }
            catch (error: RuntimeError) {
                statistics[file][4]++; report(error.position, "runtime error", error.reason, sources, errors); continue
            }
            if (item is Item.Declaration) {
                for ((binding, value) in item.group.bindings.zip(evaluated)) {
                    values.add("${binding.name} = ${valueString(value)}"); scope[binding.name] = binding.position
                }; statistics[file][1] += item.group.bindings.size
            } else values.add("- = " + valueString(evaluated[0]))
            typeEnvironment = nextTypes; valueEnvironment = nextValues
        }
        for ((name, signature) in pending.entries.sortedBy {
            it.value.position
        }) {
            statistics[file][5]++; report(signature.position, "warning", "signature for '$name' is never used", sources, errors)
        }
        statistics[file][6] = evaluator.calls
    }
    errors.add("== summary ==")
    for (file in 0..1) {
        val s = statistics[file]; errors.add("${fileNames[file]}: items=${s[0]} bindings=${s[1]} syntax=${s[2]} type=${s[3]} runtime=${s[4]} warnings=${s[5]} calls=${s[6]}")
    }
    write("types.txt", types); write("values.txt", values); write("errors.txt", errors); write("formatted.ml", formatted)
}
