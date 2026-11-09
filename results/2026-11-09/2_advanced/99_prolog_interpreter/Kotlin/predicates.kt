fun control(key: Indicator): Boolean = key in setOf(Indicator(",", 2), Indicator("!", 0), Indicator(";", 2), Indicator("->", 2), Indicator(backslash + "+", 1), Indicator("catch", 3)) || key.name == "call" && key.arity in 1..8
val builtinArities = mapOf("findall" to 3, "throw" to 1, "between" to 3, "length" to 2, "true" to 0, "fail" to 0, "false" to 0, "=" to 2, (backslash + "=") to 2, "==" to 2, (backslash + "==") to 2, "var" to 1, "nonvar" to 1, "atom" to 1, "number" to 1, "integer" to 1, "atomic" to 1, "compound" to 1, "callable" to 1, "is_list" to 1, "is" to 2, "=:=" to 2, ("=" + backslash + "=") to 2, "<" to 2, ">" to 2, "=<" to 2, ">=" to 2, "functor" to 3, "arg" to 3, "=.." to 2, "copy_term" to 2, "atom_length" to 2, "atom_chars" to 2, "write" to 1, "writeq" to 1, "nl" to 0)
fun builtin(key: Indicator): Boolean = builtinArities[key.name] == key.arity
fun integer(term: Term, store: Store): Long = when (val value = store.dereference(term)) {
    is Term.Integer -> value.value
    is Term.Variable -> throw PrologError(Term.Atom("instantiation_error"))
    else -> throw PrologError(typeError("integer", value))
}
fun atom(term: Term, store: Store): String = when (val value = store.dereference(term)) {
    is Term.Atom -> value.name
    is Term.Variable -> throw PrologError(Term.Atom("instantiation_error"))
    else -> throw PrologError(typeError("atom", value))
}
fun proper(term: Term, store: Store): List<Term> {
    val (elements, tail) = store.parts(term)
    if (tail == Term.Atom("[]")) return elements
    if (tail is Term.Variable) throw PrologError(Term.Atom("instantiation_error"))
    throw PrologError(typeError("list", term))
}
fun arithmetic(term: Term, store: Store): Long {
    when (val value = store.dereference(term)) {
        is Term.Variable -> throw PrologError(Term.Atom("instantiation_error"))
        is Term.Integer -> return value.value
        is Term.Atom -> throw PrologError(typeError("evaluable", indicatorTerm(Indicator(value.name, 0))))
        is Term.Compound -> {
            val name = value.name
            val args = value.args
            val valid = args.size == 2 && name in listOf("+", "-", "*", "//", "mod", "rem", "min", "max") || args.size == 1 && name in listOf("-", "abs")
            if (!valid) throw PrologError(typeError("evaluable", indicatorTerm(Indicator(name, args.size))))
            val a = arithmetic(args[0], store)
            val b = if (args.size == 2) arithmetic(args[1], store) else 0
            if (name in listOf("//", "mod", "rem") && b == 0L) throw PrologError(Term.Compound("evaluation_error", listOf(Term.Atom("zero_divisor"))))
            val result = when (name) {
                "+" -> a + b
                "-" -> if (args.size == 1) -a else a - b
                "*" -> a * b
                "//" -> a / b
                "rem" -> a % b
                "mod" -> {
                    var quotient = a / b
                    if (a % b != 0L && (a < 0) != (b < 0)) quotient--
                    a - b * quotient
                }
                "abs" -> kotlin.math.abs(a)
                "min" -> minOf(a, b)
                else -> maxOf(a, b)
            }
            if (result !in -2147483648L..2147483647L) throw PrologError(Term.Compound("evaluation_error", listOf(Term.Atom("int_overflow"))))
            return result
        }
    }
}
fun deterministic(key: Indicator, args: List<Term>, store: Store, trail: Trail, output: StringBuilder): Boolean {
    val name = key.name
    when (name) {
        "true" -> return true
        "fail", "false" -> return false
        "=" -> return trail.unify(args[0], args[1], store)
        backslash + "=" -> {
            val mark = trail.mark
            val result = trail.unify(args[0], args[1], store)
            trail.undo(mark, store)
            return !result
        }
        "==", backslash + "==" -> return identical(args[0], args[1], store) == (name == "==")
        "var", "nonvar", "atom", "number", "integer", "atomic", "compound", "callable", "is_list" -> {
            val term = store.dereference(args[0])
            return when (name) {
                "var" -> term is Term.Variable
                "nonvar" -> term !is Term.Variable
                "atom" -> term is Term.Atom
                "number", "integer" -> term is Term.Integer
                "atomic" -> term is Term.Integer || term is Term.Atom
                "compound" -> term is Term.Compound
                "callable" -> term.indicator != null
                else -> store.parts(term).second == Term.Atom("[]")
            }
        }
        "is" -> return trail.unify(args[0], Term.Integer(arithmetic(args[1], store)), store)
        "=:=", "=" + backslash + "=", "<", ">", "=<", ">=" -> {
            val a = arithmetic(args[0], store)
            val b = arithmetic(args[1], store)
            return when (name) {
                "=:=" -> a == b
                "=" + backslash + "=" -> a != b
                "<" -> a < b
                ">" -> a > b
                "=<" -> a <= b
                else -> a >= b
            }
        }
        "functor" -> {
            val term = store.dereference(args[0])
            if (term !is Term.Variable) {
                val functor = if (term is Term.Compound) Term.Atom(term.name) else term
                val arity = if (term is Term.Compound) term.args.size else 0
                return trail.unify(args[1], functor, store) && trail.unify(args[2], Term.Integer(arity.toLong()), store)
            }
            val functor = store.dereference(args[1])
            val arity = store.dereference(args[2])
            if (functor is Term.Variable || arity is Term.Variable) throw PrologError(Term.Atom("instantiation_error"))
            if (functor is Term.Compound) throw PrologError(typeError("atomic", functor))
            if (arity !is Term.Integer) throw PrologError(typeError("integer", arity))
            val n = arity.value
            if (n < 0) throw PrologError(domainError("not_less_than_zero", arity))
            if (n > 255) throw PrologError(Term.Compound("representation_error", listOf(Term.Atom("max_arity"))))
            if (n == 0L) return trail.unify(args[0], functor, store)
            if (functor !is Term.Atom) throw PrologError(typeError("atom", functor))
            return trail.unify(args[0], Term.Compound(functor.name, List(n.toInt()) {
                store.fresh()
            }), store)
        }
        "arg" -> {
            val n = store.dereference(args[0])
            val term = store.dereference(args[1])
            if (n is Term.Variable || term is Term.Variable) throw PrologError(Term.Atom("instantiation_error"))
            if (n !is Term.Integer) throw PrologError(typeError("integer", n))
            if (term !is Term.Compound) throw PrologError(typeError("compound", term))
            return n.value >= 1 && n.value <= term.args.size && trail.unify(term.args[n.value.toInt() - 1], args[2], store)
        }
        "=.." -> {
            val term = store.dereference(args[0])
            if (term !is Term.Variable) {
                val values = if (term is Term.Compound) listOf(Term.Atom(term.name)) + term.args else listOf(term)
                return trail.unify(list(values), args[1], store)
            }
            val values = proper(args[1], store)
            if (values.isEmpty()) throw PrologError(domainError("non_empty_list", Term.Atom("[]")))
            val head = store.dereference(values[0])
            if (head is Term.Variable) throw PrologError(Term.Atom("instantiation_error"))
            if (values.size == 1) {
                if (head is Term.Compound) throw PrologError(typeError("atomic", head))
                return trail.unify(args[0], head, store)
            }
            if (head !is Term.Atom) throw PrologError(typeError("atom", head))
            if (values.size - 1 > 255) throw PrologError(Term.Compound("representation_error", listOf(Term.Atom("max_arity"))))
            return trail.unify(args[0], Term.Compound(head.name, values.drop(1)), store)
        }
        "copy_term" -> return trail.unify(store.copy(args[0]), args[1], store)
        "atom_length" -> {
            val nameValue = atom(args[0], store)
            val n = store.dereference(args[1])
            if (n !is Term.Variable && n !is Term.Integer) throw PrologError(typeError("integer", n))
            return trail.unify(Term.Integer(nameValue.length.toLong()), args[1], store)
        }
        "atom_chars" -> {
            if (store.dereference(args[0]) !is Term.Variable) {
                val nameValue = atom(args[0], store)
                return trail.unify(args[1], list(nameValue.map {
                    Term.Atom(it.toString())
                }), store)
            }
            val values = proper(args[1], store)
            val nameValue = StringBuilder()
            for (source in values) {
                val value = store.dereference(source)
                if (value is Term.Variable) throw PrologError(Term.Atom("instantiation_error"))
                if (value !is Term.Atom || value.name.length != 1) throw PrologError(typeError("character", value))
                nameValue.append(value.name)
            }
            return trail.unify(args[0], Term.Atom(nameValue.toString()), store)
        }
        "write", "writeq" -> {
            output.append(writeTerm(args[0], store, name == "writeq"))
            return true
        }
        "nl" -> {
            output.append(10.toChar())
            return true
        }
        else -> error("unknown builtin")
    }
}
