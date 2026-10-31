class Trail {
    val bindings = mutableListOf<Int>()
    val mark: Int get() = bindings.size
    fun undo(mark: Int, store: Store) {
        while (bindings.size > mark) store.bindings[bindings.removeAt(bindings.lastIndex)] = null
    }
    fun unify(a: Term, b: Term, store: Store): Boolean {
        val pending = mutableListOf(a to b)
        while (pending.isNotEmpty()) {
            val (first, second) = pending.removeAt(pending.lastIndex)
            val x = store.dereference(first)
            val y = store.dereference(second)
            if (x is Term.Variable) {
                if (y is Term.Variable && y.id == x.id) continue
                store.bindings[x.id] = y
                bindings.add(x.id)
                continue
            }
            if (y is Term.Variable) {
                store.bindings[y.id] = x
                bindings.add(y.id)
                continue
            }
            when {
                x is Term.Integer && y is Term.Integer && x.value == y.value -> Unit
                x is Term.Atom && y is Term.Atom && x.name == y.name -> Unit
                x is Term.Compound && y is Term.Compound && x.name == y.name && x.args.size == y.args.size -> {
                    for (i in x.args.indices.reversed()) pending.add(x.args[i] to y.args[i])
                }
                else -> return false
            }
        }
        return true
    }
}
fun identical(a: Term, b: Term, store: Store): Boolean {
    val pending = mutableListOf(a to b)
    while (pending.isNotEmpty()) {
        val (first, second) = pending.removeAt(pending.lastIndex)
        val x = store.dereference(first)
        val y = store.dereference(second)
        when {
            x is Term.Variable && y is Term.Variable && x.id == y.id -> Unit
            x is Term.Integer && y is Term.Integer && x.value == y.value -> Unit
            x is Term.Atom && y is Term.Atom && x.name == y.name -> Unit
            x is Term.Compound && y is Term.Compound && x.name == y.name && x.args.size == y.args.size -> {
                for (i in x.args.indices.reversed()) pending.add(x.args[i] to y.args[i])
            }
            else -> return false
        }
    }
    return true
}
