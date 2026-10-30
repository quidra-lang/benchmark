data class Parsed(val molecule: Molecule, val matchers: List<Matcher>)
data class OpenRing(val atom: Int, val symbol: Pair<Int, Int>?, val column: Int)
object SmilesParser {
    fun organic(text: String): Triple<String, Boolean, Int>? {
        if (text.startsWith("Cl")) return Triple("Cl", false, 2)
        if (text.startsWith("Br")) return Triple("Br", false, 2)
        val c = text.firstOrNull() ?: return null
        if (c in "BCNOPSFI") return Triple(c.toString(), false, 1)
        if (c in "bcnops") return Triple(c.uppercaseChar().toString(), true, 1)
        return null
    }
    fun atom(text: String, column: Int, elements: Elements): Pair<Atom, Int> {
        if (text[0] != '[') {
            val (element, aromatic, n) = organic(text) ?: throw MoleculeError("unexpected character", column)
            return Pair(Atom(element, aromatic, column = column), n)
        }
        val end = text.indexOf(']')
        if (end < 0) throw MoleculeError("unclosed bracket", column)
        val s = text.substring(1, end)
        var i = 0
        while (i < s.length && s[i] in '0'..'9') i++
        if (i >= 4 || i > 0 && s[0] == '0') throw MoleculeError("bad bracket atom", column)
        val mass = if (i == 0) 0 else s.substring(0, i).toInt()
        if (i == s.length) throw MoleculeError("bad bracket atom", column)
        val element: String
        val aromatic: Boolean
        if (s[i] in "bcnops") {
            element = s[i].uppercaseChar().toString(); aromatic = true; i++
        }
        else if (s[i] in 'A'..'Z') {
            val one = s[i].toString()
            if (i + 1 < s.length && s[i + 1] in 'a'..'z' && s.substring(i, i + 2) in elements) {
                element = s.substring(i, i + 2); i += 2
            } else if (one in elements) {
                element = one; i++
            }
            else throw MoleculeError("unknown element", column)
            aromatic = false
        } else throw MoleculeError("bad bracket atom", column)
        if (i < s.length && s[i] == '@') {
            i++; if (i < s.length && s[i] == '@') i++
        }
        var hydrogens = 0
        if (i < s.length && s[i] == 'H') {
            hydrogens = 1; i++
            if (i < s.length && s[i] in '0'..'9') {
                hydrogens = s[i] - '0'; i++
            }
        }
        var charge = 0
        if (i < s.length && s[i] in "+-") {
            val sign = if (s[i] == '+') 1 else -1
            i++
            var amount = 1
            if (i < s.length && s[i] in '1'..'9') {
                amount = s[i] - '0'; i++
            }
            charge = sign * amount
        }
        if (i != s.length) throw MoleculeError("bad bracket atom", column)
        return Pair(Atom(element, aromatic, mass, charge, hydrogens, true, column), end + 1)
    }
    fun symbol(c: Char, pattern: Boolean): Int? = when (c) {
        '-' -> 1
        '=' -> 2
        '#' -> 3
        ':' -> 4
        '~' -> if (pattern) 5 else null
        '/', '\\' -> if (pattern) null else 1
        else -> null
    }
    fun parse(text: String, elements: Elements, pattern: Boolean = false): Parsed {
        val molecule = Molecule()
        val matchers = mutableListOf<Matcher>()
        var current: Int? = null
        var pending: Pair<Int, Int>? = null
        val branches = mutableListOf<Pair<Int, Int>>()
        val rings = mutableMapOf<Int, OpenRing>()
        var i = 0
        fun add(a: Int, b: Int, kind: Int) {
            molecule.bonds.add(Bond(minOf(a, b), maxOf(a, b), kind))
        }
        while (i < text.length) {
            val c = text[i]
            val column = i + 1
            val kind = symbol(c, pattern)
            if (kind != null) {
                if (current == null || pending != null) throw MoleculeError("misplaced bond", column)
                pending = Pair(kind, column); i++
            } else if (c == '(') {
                if (current == null || pending != null || i > 0 && text[i - 1] == '(') throw MoleculeError("misplaced branch", column)
                branches.add(Pair(current!!, column)); i++
            } else if (c == ')') {
                if (branches.isEmpty()) throw MoleculeError("unmatched parenthesis", column)
                pending?.let {
                    throw MoleculeError("dangling bond", it.second)
                }
                if (i > 0 && text[i - 1] == '(') throw MoleculeError("empty branch", column)
                current = branches.removeAt(branches.lastIndex).first; i++
            } else if (c in '0'..'9' || c == '%') {
                val atom = current ?: throw MoleculeError("misplaced ring closure", column)
                val number: Int
                if (c == '%') {
                    if (i + 2 >= text.length || text[i + 1] !in '0'..'9' || text[i + 2] !in '0'..'9') throw MoleculeError("bad ring number", column)
                    number = text.substring(i + 1, i + 3).toInt(); i += 3
                } else {
                    number = c - '0'; i++
                }
                val closing = pending
                pending = null
                val opening = rings.remove(number)
                if (opening != null) {
                    if (opening.atom == atom) throw MoleculeError("self bond", column)
                    if (opening.symbol != null && closing != null && opening.symbol.first != closing.first) throw MoleculeError("ring bond mismatch", column)
                    if (molecule.bonds.any {
                        it.a == minOf(opening.atom, atom) && it.b == maxOf(opening.atom, atom)
                    }) throw MoleculeError("duplicate bond", column)
                    add(opening.atom, atom, (closing ?: opening.symbol)?.first ?: 0)
                } else rings[number] = OpenRing(atom, closing, column)
            } else {
                val atom: Atom
                val length: Int
                if (pattern) {
                    val (matcher, n) = Search.patternAtom(text.substring(i), column)
                    matchers.add(matcher); atom = Atom("", column = column); length = n
                } else {
                    val parsed = this.atom(text.substring(i), column, elements)
                    atom = parsed.first; length = parsed.second
                }
                val next = molecule.atoms.size
                molecule.atoms.add(atom)
                current?.let {
                    add(it, next, pending?.first ?: 0)
                }
                current = next; pending = null; i += length
            }
        }
        pending?.let {
            throw MoleculeError("dangling bond", it.second)
        }
        branches.firstOrNull()?.let {
            throw MoleculeError("unmatched parenthesis", it.second)
        }
        rings.values.minByOrNull {
            it.column
        }?.let {
            throw MoleculeError("unclosed ring", it.column)
        }
        molecule.rebuild()
        return Parsed(molecule, matchers)
    }
}
