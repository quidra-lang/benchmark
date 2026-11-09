private class Problem(val text: String) : RuntimeException(text)

private fun fail(s: String): Nothing = throw Problem("error: $s")

private fun number(s: String): Int? = if (s.length in 1..4 && s.all {
    it in '0'..'9'
}
&& (s.length == 1 || s[0] != '0')) s.toInt() else null

private data class Version(val core: List<Int>,val pre: List<String> = emptyList()) : Comparable<Version> {
    val text get() = core.joinToString(".")+if (pre.isEmpty()) "" else "-"+pre.joinToString(".")
    override fun compareTo(other: Version): Int {
        for (i in 0..2) if (core[i] != other.core[i]) return core[i].compareTo(other.core[i])
        if (pre.isEmpty() || other.pre.isEmpty()) return if (pre.isEmpty()) {
            if (other.pre.isEmpty()) 0 else 1
        } else -1
        for (i in 0 until minOf(pre.size,other.pre.size)) {
            val a = pre[i]
            val b = other.pre[i]
            if (a == b) continue
            val na = a.all {
                it in '0'..'9'
            }
            val nb = b.all {
                it in '0'..'9'
            }
            return if (na && nb) a.toInt().compareTo(b.toInt()) else if (na != nb) {
                if (na) -1 else 1
            } else a.compareTo(b)
        }
        return pre.size.compareTo(other.pre.size)
    }
}

private fun version(s: String): Version? {
    val p = s.split('-')
    if (p.size !in 1..2) return null
    val parts = p[0].split('.')
    if (parts.size != 3) return null
    val core = parts.map {
        number(it) ?: return null
    }
    val pre = if (p.size == 2) p[1].split('.') else emptyList()
    for (id in pre) if (id.isEmpty() || !id.all {
        it in 'a'..'z' || it in '0'..'9'
    }
    || (id.all {
        it in '0'..'9'
    }
    && number(id) == null)) return null
    return Version(core,pre)
}

private fun checkedVersion(s: String) = version(s) ?: fail("invalid version '$s'")

private data class Comparator(val op: String,val version: Version) {
    fun accepts(v: Version): Boolean {
        val d = v.compareTo(version)
        return when(op) {
            "=" -> d == 0
            ">" -> d > 0
            ">=" -> d >= 0
            "<" -> d < 0
            else -> d <= 0
        }
    }
}

private data class Alternative(val comparisons: List<Comparator>,val prereleaseCores: Set<List<Int>>)

private data class Constraint(val alternatives: List<Alternative>) {
    fun accepts(v: Version) = alternatives.any {
        (v.pre.isEmpty() || v.core in it.prereleaseCores) && it.comparisons.all {
            c -> c.accepts(v)
        }
    }
    fun normal() = alternatives.joinToString(" || ") {
        a -> a.comparisons.joinToString(" ") {
            it.op+it.version.text
        }.ifEmpty {
            "*"
        }
    }
}

private fun constraint(text: String): Constraint {
    fun invalid(): Nothing = fail("invalid constraint '$text'")
    val alternatives = mutableListOf<Alternative>()
    for (alternative in text.split(" || ")) {
        val comparisons = mutableListOf<Comparator>()
        val prereleaseCores = mutableSetOf<List<Int>>()
        for (term in alternative.split(' ')) {
            val op = listOf(">=","<=",">","<","=","^","~").firstOrNull {
                term.startsWith(it)
            }?: ""
            val pattern = term.drop(op.length)
            var k: Int
            val lower: Version
            if ('-' in pattern) {
                lower = version(pattern) ?: invalid()
                if (lower.pre.isEmpty()) invalid()
                k = 3
                prereleaseCores.add(lower.core)
            } else {
                val parts = pattern.split('.')
                if (parts.size !in 1..3) invalid()
                val core = mutableListOf<Int>()
                var wildcard = false
                for (part in parts) {
                    if (part == "x" || part == "*") wildcard = true else {
                        val n = number(part) ?: invalid()
                        if (wildcard) invalid()
                        core.add(n)
                    }
                }
                k = core.size
                while (core.size < 3) core.add(0)
                lower = Version(core)
            }
            fun upper(i: Int): Version {
                val core = lower.core.toMutableList()
                core[i-1]++
                for (j in i..2) core[j] = 0
                return Version(core)
            }
            fun add(op: String,v: Version) {
                comparisons.add(Comparator(op,v))
            }
            if (k == 0) {
                if (op == ">" || op == "<") add("<",Version(listOf(0,0,0),listOf("0")))
            } else when(op) {
                "","=" -> if (k == 3) add("=",lower) else {
                    add(">=",lower)
                    add("<",upper(k))
                }
                ">" -> add(if (k == 3) ">" else ">=",if (k == 3) lower else upper(k))
                "<=" -> add(if (k == 3) "<=" else "<",if (k == 3) lower else upper(k))
                ">=","<" -> add(op,lower)
                "~" -> {
                    add(">=",lower)
                    add("<",upper(if (k >= 2) 2 else 1))
                }
                "^" -> {
                    add(">=",lower)
                    add("<",upper(if (lower.core[0] != 0 || k == 1) 1 else if (lower.core[1] != 0 || k == 2) 2 else 3))
                }
            }
        }
        alternatives.add(Alternative(comparisons,prereleaseCores))
    }
    return Constraint(alternatives)
}

private data class Rule(val name: String,val text: String,val constraint: Constraint)

private class Release(val version: Version,val deps: List<Rule>,val conflicts: List<Rule>,var yanked: Boolean = false)

private data class Requirement(val rule: Rule,val origin: Pair<String,Release>? = null)

private data class Snapshot(val requests: List<Rule>,val installed: Map<String,Release>)

private class Manager {
    val registry = sortedMapOf<String,MutableList<Release>>()
    var requests = emptyList<Rule>()
    var installed = sortedMapOf<String,Release>()
    val held = mutableSetOf<String>()
    val advisories = sortedMapOf<String,Rule>()
    val history = mutableListOf<Snapshot>()
    fun releases(n: String) = registry[n]?.sortedByDescending {
        it.version
    }?: emptyList()
    fun registered(n: String,v: String) = registry[n]?.firstOrNull {
        it.version.text == v
    }?: fail("$n@$v is not registered")
    fun checkInstalled(n: String) = installed[n] ?: fail("$n is not installed")
    fun applicable(n: String,v: Version) = advisories.filterValues {
        it.name == n && it.constraint.accepts(v)
    }.keys.toList()
    fun display(n: String,r: Release): String {
        val flags = mutableListOf<String>()
        if (r.yanked) flags.add("yanked")
        if (installed[n]?.version == r.version) flags.add("installed")
        return "$n@${r.version.text}"+if (flags.isEmpty()) "" else flags.joinToString(", ",prefix=" (",postfix=")")
    }
    fun resolve(newRequests: List<Rule>,preferred: Set<String>,audit: Boolean): Pair<Map<String,Release>?,List<String>> {
        val selected = sortedMapOf<String,Release>()
        val origins = mutableMapOf<String,Requirement>()
        var failureDepth = -1
        var failure = emptyList<String>()
        fun chain(r: Requirement): List<String> {
            val origin = r.origin
            return if (origin == null) listOf("requested ${r.rule.name} ${r.rule.text}") else chain(origins.getValue(origin.first))+"${origin.first}@${origin.second.version.text} requires ${r.rule.name} ${r.rule.text}"
        }
        fun record(r: Requirement,reason: String,other: String? = null) {
            if (selected.size > failureDepth) {
                failureDepth = selected.size
                failure = listOf("UNSATISFIABLE")+chain(r).map {
                    "  $it"
                }+"  $reason"+(other?.let {
                    chain(origins.getValue(it)).map {
                        line -> "    $line"
                    }
                }?: emptyList())
            }
        }
        fun usable(n: String,r: Release) = (!r.yanked || installed[n]?.version == r.version) && (!audit || applicable(n,r.version).isEmpty())
        fun search(queue: List<Requirement>): Boolean {
            if (queue.isEmpty()) return true
            val r = queue.first()
            val n = r.rule.name
            val rest = queue.drop(1)
            val old = selected[n]
            if (old != null) {
                if (r.rule.constraint.accepts(old.version)) return search(rest)
                record(r,"$n@${old.version.text} was selected by:",n)
                return false
            }
            val candidates: MutableList<Release>
            if (n in held) {
                val fixed = installed.getValue(n)
                if (!r.rule.constraint.accepts(fixed.version) || !usable(n,fixed)) {
                    record(r,"$n@${fixed.version.text} is held")
                    return false
                }
                candidates = mutableListOf(fixed)
            } else {
                candidates = releases(n).filter {
                    r.rule.constraint.accepts(it.version) && usable(n,it)
                }.toMutableList()
                if (n in preferred) {
                    val index = candidates.indexOfFirst {
                        it.version == installed[n]?.version
                    }
                    if (index >= 0) candidates.add(0,candidates.removeAt(index))
                }
                if (candidates.isEmpty()) {
                    record(r,"no version of $n matches ${r.rule.text}")
                    return false
                }
            }
            for (candidate in candidates) {
                val conflict = selected.entries.firstOrNull {
                    (q,w) -> candidate.conflicts.any {
                        it.name == q && it.constraint.accepts(w.version)
                    }
                    || w.conflicts.any {
                        it.name == n && it.constraint.accepts(candidate.version)
                    }
                }
                if (conflict != null) {
                    record(r,"$n@${candidate.version.text} conflicts with ${conflict.key}@${conflict.value.version.text}, which was selected by:",conflict.key)
                    continue
                }
                selected[n] = candidate
                origins[n] = r
                if (search(candidate.deps.map {
                    Requirement(it,n to candidate)
                }+rest)) return true
                selected.remove(n)
                origins.remove(n)
            }
            return false
        }
        return if (search(newRequests.map {
            Requirement(it)
        })) selected.toSortedMap() to emptyList() else null to failure
    }
    fun plan(next: Map<String,Release>): List<String> {
        val out = mutableListOf<String>()
        val counts = IntArray(4)
        val remaining = next.keys.toSortedSet()
        while (remaining.isNotEmpty()) {
            val n = remaining.first {
                next.getValue(it).deps.none {
                    d -> d.name in remaining
                }
            }
            remaining.remove(n)
            val v = next.getValue(n).version
            val old = installed[n]?.version
            if (old == null) {
                out.add("install $n@${v.text}")
                counts[0]++
            } else if (v != old) {
                val up = v > old
                out.add("${if (up) "upgrade" else "downgrade"} $n ${old.text} -> ${v.text}")
                counts[if (up) 1 else 2]++
            }
        }
        remaining.addAll(installed.keys-next.keys)
        while (remaining.isNotEmpty()) {
            val n = remaining.first {
                name -> remaining.none {
                    q -> installed.getValue(q).deps.any {
                        it.name == name
                    }
                }
            }
            remaining.remove(n)
            out.add("remove $n@${installed.getValue(n).version.text}")
            counts[3]++
        }
        if (out.isEmpty()) out.add("no changes") else out.add("${counts[0]} installed, ${counts[1]} upgraded, ${counts[2]} downgraded, ${counts[3]} removed")
        return out
    }
    fun update(newRequests: List<Rule>,next: Map<String,Release>) {
        history.add(Snapshot(requests,installed.toMap()))
        requests = newRequests
        installed = next.toSortedMap()
        held.retainAll(installed.keys)
    }
    fun parent(n: String) = installed.entries.first {
        (_,r) -> r.deps.any {
            it.name == n
        }
    }.key
    fun command(line: String): List<String> {
        val clauses = line.split("; ")
        val w = clauses[0].split(' ')
        val c = w[0]
        val a = w.drop(1)
        val out = mutableListOf<String>()
        fun rest(i: Int) = a.drop(i).joinToString(" ")
        when(c) {
            "PKG" -> {
                val v = checkedVersion(a[1])
                if (registry[a[0]]?.any {
                    it.version == v
                }
                == true) fail("${a[0]}@${a[1]} is already registered")
                val deps = mutableListOf<Rule>()
                val conflicts = mutableListOf<Rule>()
                for (clause in clauses.drop(1)) {
                    val words = clause.split(' ')
                    val text = words.drop(2).joinToString(" ")
                    val rule = Rule(words[1],text,constraint(text))
                    if (words[0] == "DEP") deps.add(rule) else conflicts.add(rule)
                }
                registry.getOrPut(a[0]) {
                    mutableListOf()
                }.add(Release(v,deps,conflicts))
                return listOf("registered ${a[0]}@${a[1]}")
            }
            "YANK","INFO" -> {
                val r = registered(a[0],a[1])
                if (c == "YANK") {
                    if (r.yanked) fail("${a[0]}@${a[1]} is already yanked")
                    r.yanked = true
                    return listOf("yanked ${a[0]}@${a[1]}")
                }
                out.add(display(a[0],r))
                out.addAll(r.deps.map {
                    "  requires ${it.name} ${it.text}"
                })
                out.addAll(r.conflicts.map {
                    "  conflicts with ${it.name} ${it.text}"
                })
                out.addAll(applicable(a[0],r.version).map {
                    "  advisory $it"
                })
                return out
            }
            "VERSIONS" -> {
                val con = if (a.size > 1) constraint(rest(1)) else null
                if (a[0] !in registry) fail("unknown package ${a[0]}")
                out.addAll(releases(a[0]).filter {
                    con == null || con.accepts(it.version)
                }.map {
                    display(a[0],it)
                })
                return out.ifEmpty {
                    listOf("no matching versions")
                }
            }
            "DEPENDENTS" -> {
                val v = if (a.size > 1) checkedVersion(a[1]) else null
                for (n in registry.keys) for (r in releases(n)) for (d in r.deps) if (d.name == a[0] && (v == null || d.constraint.accepts(v))) out.add("$n@${r.version.text} requires ${d.name} ${d.text}")
                return out.ifEmpty {
                    listOf("no dependents")
                }
            }
            "COMPARE" -> {
                val x = checkedVersion(a[0])
                val y = checkedVersion(a[1])
                return listOf("${a[0]} ${if (x < y) "<" else if (x > y) ">" else "="} ${a[1]}")
            }
            "MATCH" -> {
                val v = checkedVersion(a[0])
                val con = constraint(rest(1))
                return listOf(if (con.accepts(v)) "yes" else "no")
            }
            "RANGE" -> return listOf(constraint(rest(0)).normal())
            "INSTALL","SIMULATE" -> {
                val text = if (a.size > 1) rest(1) else "*"
                val con = constraint(text)
                if (a[0] !in registry) fail("unknown package ${a[0]}")
                val rule = Rule(a[0],text,con)
                val nextRequests = requests.toMutableList()
                val i = nextRequests.indexOfFirst {
                    it.name == a[0]
                }
                if (i < 0) nextRequests.add(rule) else nextRequests[i] = rule
                val (next,failure) = resolve(nextRequests,installed.keys,false)
                if (next == null) return failure
                val plan = plan(next)
                if (c == "INSTALL") update(nextRequests,next)
                return plan
            }
            "REMOVE" -> {
                val n = a[0]
                if (requests.none {
                    it.name == n
                }) {
                    if (n in installed) fail("$n is required by ${parent(n)}") else fail("$n is not installed")
                }
                val nextRequests = requests.filter {
                    it.name != n
                }
                val keep = nextRequests.map {
                    it.name
                }.toMutableSet()
                while (true) {
                    val next = keep.flatMap {
                        installed.getValue(it).deps.map {
                            d -> d.name
                        }
                    }
                    if (!keep.addAll(next)) break
                }
                if (n in keep) {
                    out.add("$n@${installed.getValue(n).version.text} is still required by ${parent(n)}")
                    update(nextRequests,installed)
                } else {
                    val next = installed.filterKeys {
                        it in keep
                    }
                    out.addAll(plan(next))
                    update(nextRequests,next)
                }
                return out
            }
            "UPGRADE" -> {
                if (a.isNotEmpty()) checkInstalled(a[0])
                val preferred = if (a.isEmpty()) emptySet() else installed.keys-a[0]
                val (next,failure) = resolve(requests,preferred,false)
                if (next == null) return failure
                out.addAll(plan(next))
                update(requests,next)
                return out
            }
            "ROLLBACK" -> {
                if (history.isEmpty()) fail("nothing to roll back")
                val snapshot = history.removeAt(history.lastIndex)
                out.addAll(plan(snapshot.installed))
                requests = snapshot.requests
                installed = snapshot.installed.toSortedMap()
                held.retainAll(installed.keys)
                return out
            }
            "HOLD" -> {
                val r = checkInstalled(a[0])
                if (!held.add(a[0])) fail("${a[0]} is already held")
                return listOf("held ${a[0]}@${r.version.text}")
            }
            "UNHOLD" -> {
                if (!held.remove(a[0])) fail("${a[0]} is not held")
                return listOf("released ${a[0]}")
            }
            "WHY" -> {
                val n = a[0]
                val r = checkInstalled(n)
                val roots = requests.map {
                    it.name
                }.toSortedSet()
                if (n in roots) return listOf("$n@${r.version.text} is explicitly installed")
                val seen = roots.toMutableSet()
                val queue = ArrayDeque<String>()
                queue.addAll(roots)
                val parents = mutableMapOf<String,String>()
                while (queue.isNotEmpty()) {
                    val u = queue.removeFirst()
                    for (v in installed.getValue(u).deps.map {
                        it.name
                    }.sorted()) if (seen.add(v)) {
                        parents[v] = u
                        queue.addLast(v)
                    }
                }
                val path = mutableListOf(n)
                while (path.last() !in roots) path.add(parents.getValue(path.last()))
                return listOf(path.asReversed().joinToString(" -> ") {
                    "$it@${installed.getValue(it).version.text}"
                })
            }
            "TREE" -> {
                if (a.isNotEmpty()) checkInstalled(a[0])
                val roots = if (a.isEmpty()) requests.map {
                    it.name
                }.sorted() else listOf(a[0])
                if (roots.isEmpty()) return listOf("(empty)")
                val seen = mutableSetOf<String>()
                fun visit(n: String,text: String?,prefix: String,indent: String) {
                    val r = installed.getValue(n)
                    val body = prefix+"$n@${r.version.text}"+(text?.let {
                        " [$it]"
                    }?: "")
                    if (!seen.add(n)) {
                        out.add("$body (*)")
                        return
                    }
                    out.add(body)
                    for ((i,d) in r.deps.withIndex()) {
                        val last = i == r.deps.lastIndex
                        visit(d.name,d.text,indent+if (last) "`-- " else "|-- ",indent+if (last) "    " else "|   ")
                    }
                }
                for (n in roots) visit(n,requests.firstOrNull {
                    it.name == n
                }?.text,"","")
                return out
            }
            "OUTDATED" -> {
                for ((n,r) in installed) {
                    val constraints = requests.filter {
                        it.name == n
                    }.map {
                        it.constraint
                    }+installed.values.flatMap {
                        it.deps
                    }.filter {
                        it.name == n
                    }.map {
                        it.constraint
                    }
                    val versions = releases(n)
                    val wanted = versions.first {
                        (!it.yanked || it.version == r.version) && constraints.all {
                            con -> con.accepts(it.version)
                        }
                    }
                    val latest = versions.firstOrNull {
                        !it.yanked && it.version.pre.isEmpty()
                    }
                    if (wanted.version != r.version || (latest != null && latest.version > r.version)) out.add("$n ${r.version.text} ${wanted.version.text} ${latest?.version?.text ?: "-"}")
                }
                return out.ifEmpty {
                    listOf("all packages are up to date")
                }
            }
            "LOCK" -> return installed.map {
                (n,r) -> "$n@${r.version.text}"
            }.ifEmpty {
                listOf("(empty)")
            }
            "STATUS" -> {
                out.addAll(requests.map {
                    "${it.name} ${it.text} -> ${installed.getValue(it.name).version.text}"
                }.ifEmpty {
                    listOf("no requests")
                })
                out.add("${installed.size} installed, ${held.size} held, ${history.size} snapshots")
                return out
            }
            "ADVISORY" -> {
                if (a[0] in advisories) fail("advisory ${a[0]} already exists")
                val text = rest(2)
                val con = constraint(text)
                advisories[a[0]] = Rule(a[1],text,con)
                return listOf("advisory ${a[0]} recorded")
            }
            "AUDIT" -> {
                if (a.isNotEmpty()) {
                    val (next,failure) = resolve(requests,installed.keys,true)
                    if (next == null) return failure
                    out.addAll(plan(next))
                    update(requests,next)
                    return out
                }
                for ((n,r) in installed) {
                    val ids = applicable(n,r.version)
                    if (ids.isEmpty()) continue
                    val fix = releases(n).asReversed().firstOrNull {
                        it.version > r.version && it.version.pre.isEmpty() && !it.yanked && applicable(n,it.version).isEmpty()
                    }
                    out.add("$n@${r.version.text}: ${ids.joinToString(", ")} "+if (fix == null) "(no fix)" else "(fix: ${fix.version.text})")
                }
                return out.ifEmpty {
                    listOf("no known vulnerabilities")
                }
            }
        }
        return out
    }
}

fun main() {
    val manager = Manager()
    repeat(readLine()!!.toInt()) {
        try {
            manager.command(readLine()!!).forEach(::println)
        } catch (p: Problem) {
            println(p.text)
        }
    }
}
