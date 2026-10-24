private class Problem(val text: String) : RuntimeException(text)

private fun fail(s: String): Nothing = throw Problem("error: $s")

private fun signed(n: Int) = if (n >= 0) "+$n" else "$n"

private fun decimal(n: Int, d: Int): String {
    val h = n.toLong()*100/d
    return "${h/100}.${(h%100).toString().padStart(2,'0')}"
}

private fun leap(y: Int) = y%4 == 0 && (y%100 != 0 || y%400 == 0)

private fun monthDays(y: Int, m: Int) = if (m == 2 && leap(y)) 29 else intArrayOf(31,28,31,30,31,30,31,31,30,31,30,31)[m-1]

private fun date(text: String): Int {
    val y = text.substring(0,4).toInt()
    val m = text.substring(5,7).toInt()
    val d = text.substring(8,10).toInt()
    if (m !in 1..12 || d !in 1..monthDays(y,m)) fail("invalid date $text")
    var day = 0
    for (year in 2000 until y) day += if (leap(year)) 366 else 365
    for (month in 1 until m) day += monthDays(y,month)
    return day+d-1
}

private fun dateText(day: Int): String {
    var left = day
    var y = 2000
    while (left >= if (leap(y)) 366 else 365) {
        left -= if (leap(y)) 366 else 365
        y++
    }
    var m = 1
    while (left >= monthDays(y,m)) {
        left -= monthDays(y,m)
        m++
    }
    return "$y-${m.toString().padStart(2,'0')}-${(left+1).toString().padStart(2,'0')} ${listOf("Mon","Tue","Wed","Thu","Fri","Sat","Sun")[(day+5)%7]}"
}

private data class Task(val base: Int,val resource: String,val units: Int,var notBefore: Int = 0,var crash: Pair<Int,Int>? = null,var used: Int = 0,var pert: List<Int>? = null) {
    val duration get() = base-used
}

private data class Dep(val a: String,val b: String,val kind: String,val lag: Int)

private data class Times(val duration: Int,val es: Int,val ef: Int,var ls: Int = 0,var lf: Int = 0,var tf: Int = 0,var ff: Int = 0)

private data class Schedule(val times: Map<String,Times>,val total: Int)

private data class Baseline(val total: Int,val times: Map<String,Pair<Int,Int>>)

private class Project {
    val tasks = sortedMapOf<String,Task>()
    val deps = mutableListOf<Dep>()
    val holidays = sortedSetOf<Int>()
    val capacities = sortedMapOf<String,Int>()
    var start: Int? = null
    var deadline: Int? = null
    var baseline: Baseline? = null
    fun task(n: String) = tasks[n] ?: fail("unknown task $n")
    fun preds(n: String) = deps.filter {
        it.b == n
    }.sortedBy {
        it.a
    }
    fun succs(n: String) = deps.filter {
        it.a == n
    }.sortedBy {
        it.b
    }
    // Kahn removal also supplies the exact remainder used to choose a cycle.
    fun order(): Pair<List<String>,String?> {
        val remaining = tasks.keys.toSortedSet()
        val order = mutableListOf<String>()
        while (true) {
            val n = remaining.firstOrNull {
                t -> preds(t).none {
                    it.a in remaining
                }
            }?: break
            remaining.remove(n)
            order.add(n)
        }
        if (remaining.isEmpty()) return order to null
        val walked = mutableListOf(remaining.first())
        while (true) {
            val n = preds(walked.last()).first {
                it.a in remaining
            }.a
            val q = walked.indexOf(n)
            if (q >= 0) {
                val cycle = listOf(n)+walked.drop(q+1).asReversed()
                val k = cycle.indices.minBy {
                    cycle[it]
                }
                val rotated = cycle.drop(k)+cycle.take(k)
                return order to (rotated+rotated.first()).joinToString(" -> ")
            }
            walked.add(n)
        }
    }
    fun schedule(changed: String? = null,duration: Int = 0): Schedule {
        val order = order().first
        val times = sortedMapOf<String,Times>()
        for (n in order) {
            val t = task(n)
            val d = if (n == changed) duration else t.duration
            var es = t.notBefore
            for (e in preds(n)) {
                val p = times.getValue(e.a)
                es = maxOf(es,when(e.kind) {
                    "FS" -> p.ef+e.lag
                    "SS" -> p.es+e.lag
                    else -> p.ef+e.lag-d
                })
            }
            times[n] = Times(d,es,es+d)
        }
        val total = times.values.maxOf {
            it.ef
        }
        for (n in order.asReversed()) {
            val t = times.getValue(n)
            var lf = total
            for (e in succs(n)) {
                val p = times.getValue(e.b)
                lf = minOf(lf,when(e.kind) {
                    "FS" -> p.ls-e.lag
                    "SS" -> p.ls-e.lag+t.duration
                    else -> p.lf-e.lag
                })
            }
            t.lf = lf
            t.ls = lf-t.duration
            t.tf = t.ls-t.es
        }
        val s = Schedule(times,total)
        for (n in order) {
            val t = times.getValue(n)
            t.ff = minOf(total-t.ef,succs(n).minOfOrNull {
                margin(it,s)
            }?: Int.MAX_VALUE)
        }
        return s
    }
    fun margin(e: Dep,s: Schedule): Int {
        val a = s.times.getValue(e.a)
        val b = s.times.getValue(e.b)
        return when(e.kind) {
            "FS" -> b.es-a.ef-e.lag
            "SS" -> b.es-a.es-e.lag
            else -> b.ef-a.ef-e.lag
        }
    }
    fun critical(s: Schedule) = tasks.keys.filter {
        s.times.getValue(it).tf == 0
    }
    fun paths(s: Schedule): List<List<String>> {
        val links = deps.filter {
            s.times.getValue(it.a).tf == 0 && s.times.getValue(it.b).tf == 0 && margin(it,s) == 0
        }
        val result = mutableListOf<List<String>>()
        fun visit(p: List<String>) {
            val next = links.filter {
                it.a == p.last()
            }.map {
                it.b
            }.sorted()
            if (next.isEmpty()) result.add(p) else for (n in next) visit(p+n)
        }
        for (n in critical(s)) if (links.none {
            it.b == n
        }) visit(listOf(n))
        return result
    }
    fun working(d: Int) = (d+5)%7 < 5 && d !in holidays
    fun usage(resource: String,times: Map<String,Pair<Int,Int>>,total: Int) = IntArray(total) {
        day -> tasks.filter {
            (n,t) -> t.resource == resource && day >= times.getValue(n).first && day < times.getValue(n).second
        }.values.sumOf {
            it.units
        }
    }
    fun command(w: List<String>): List<String> {
        val c = w[0]
        val a = w.drop(1)
        fun num(i: Int) = a[i].toInt()
        val out = mutableListOf<String>()
        when(c) {
            "TASK" -> {
                if (a[0] in tasks) fail("task ${a[0]} already exists")
                tasks[a[0]] = Task(num(1),a[2],num(3))
                return listOf("task ${a[0]} added")
            }
            "DEP","UNDEP" -> {
                task(a[0])
                task(a[1])
                val i = deps.indexOfFirst {
                    it.a == a[0] && it.b == a[1]
                }
                if (c == "DEP") {
                    if (a[0] == a[1]) fail("self dependency ${a[0]}")
                    if (i >= 0) fail("dependency ${a[0]} -> ${a[1]} already exists")
                    deps.add(Dep(a[0],a[1],a[2],num(3)))
                    return listOf("dependency ${a[0]} -> ${a[1]} ${a[2]}${signed(num(3))} added")
                }
                if (i < 0) fail("no dependency ${a[0]} -> ${a[1]}")
                deps.removeAt(i)
                return listOf("dependency ${a[0]} -> ${a[1]} removed")
            }
            "REMOVE" -> {
                task(a[0])
                val k = deps.count {
                    it.a == a[0] || it.b == a[0]
                }
                deps.removeAll {
                    it.a == a[0] || it.b == a[0]
                }
                tasks.remove(a[0])
                return listOf("task ${a[0]} removed with $k dependencies")
            }
            "NOTBEFORE" -> {
                task(a[0]).notBefore = num(1)
                return listOf("notbefore ${a[0]} ${a[1]}")
            }
            "CRASHCOST" -> {
                val t = task(a[0])
                if (num(1) >= t.base) fail("crash limit too large for ${a[0]}")
                if (num(1) < t.used) fail("crash limit below used days for ${a[0]}")
                t.crash = num(1) to num(2)
                return listOf("crash ${a[0]} max ${a[1]} cost ${a[2]}")
            }
            "UNCRASH" -> {
                val t = task(a[0])
                out.add("uncrash ${a[0]} restored ${t.used} days")
                t.used = 0
                return out
            }
            "PERT" -> {
                val t = task(a[0])
                val o = num(1)
                val m = num(2)
                val p = num(3)
                if (o > m || m > p) fail("invalid estimate")
                t.pert = listOf(o,m,p)
                return listOf("pert ${a[0]} expected ${decimal(o+4*m+p,6)} variance ${decimal((p-o)*(p-o),36)}")
            }
            "CAPACITY" -> {
                capacities[a[0]] = num(1)
                return listOf("capacity ${a[0]} ${a[1]}")
            }
            "START","HOLIDAY","DEADLINE" -> {
                val d = date(a[0])
                if (c == "HOLIDAY" && d in holidays) fail("duplicate holiday ${a[0]}")
                when(c) {
                    "START" -> start = d
                    "DEADLINE" -> deadline = d
                    else -> holidays.add(d)
                }
                return listOf("${c.lowercase()} ${dateText(d)}")
            }
            "LIST" -> {
                out.add("tasks ${tasks.size}, dependencies ${deps.size}, holidays ${holidays.size}")
                for ((n,t) in tasks) out.add("$n duration ${t.duration} resource ${t.resource} units ${t.units} preds ${preds(n).joinToString(" ") { it.a }.ifEmpty { "none" }}")
                return out
            }
            "SHOW" -> {
                val n = a[0]
                val t = task(n)
                out.add("task $n duration ${t.duration} resource ${t.resource} units ${t.units}"+if (t.notBefore != 0) " notbefore ${t.notBefore}" else "")
                out.add("preds: "+preds(n).joinToString(", ") {
                    "${it.a} ${it.kind}${signed(it.lag)}"
                }.ifEmpty {
                    "none"
                })
                out.add("succs: "+succs(n).joinToString(", ") {
                    "${it.b} ${it.kind}${signed(it.lag)}"
                }.ifEmpty {
                    "none"
                })
                out.add(t.crash?.let {
                    "crash: max ${it.first} used ${t.used} cost ${it.second}"
                }?: "crash: none")
                out.add(t.pert?.joinToString(" ",prefix="pert: ") ?: "pert: none")
                if (order().second != null) out.add("schedule: unavailable") else {
                    val x = schedule().times.getValue(n)
                    out.add("schedule: ES ${x.es} EF ${x.ef} LS ${x.ls} LF ${x.lf} TF ${x.tf} FF ${x.ff}"+if (x.tf == 0) " critical" else "")
                }
                return out
            }
            "IMPACT" -> {
                task(a[0])
                val reached = mutableSetOf(a[0])
                while (true) {
                    val next = deps.filter {
                        it.a in reached
                    }.map {
                        it.b
                    }
                    if (!reached.addAll(next)) break
                }
                reached.remove(a[0])
                return listOf("impact ${a[0]}: "+reached.sorted().joinToString(" ").ifEmpty {
                    "none"
                })
            }
        }
        if (tasks.isEmpty()) fail("no tasks")
        order().second?.let {
            fail("cycle $it")
        }
        when(c) {
            "CALENDAR" -> if (start == null) fail("no start date")
            "LEVEL" -> for ((n,t) in tasks) {
                val cap = capacities[t.resource] ?: num(0)
                if (t.units > cap) fail("capacity $cap too small for $n")
            }
            "LOAD" -> if (tasks.values.none {
                it.resource == a[0]
            }) fail("unknown resource ${a[0]}")
            "WHATIF" -> task(a[0])
            "VARIANCE" -> if (baseline == null) fail("no baseline")
        }
        val s = schedule()
        val byStart = tasks.keys.sortedWith(compareBy<String> {
            s.times.getValue(it).es
        }.thenBy {
            it
        })
        val resources = tasks.values.map {
            it.resource
        }.toSortedSet()
        val initialTimes = s.times.mapValues {
            it.value.es to it.value.ef
        }
        when(c) {
            "CPM" -> {
                val width = maxOf(4,tasks.keys.maxOf {
                    it.length
                })
                out.add("TASK".padEnd(width)+listOf("DUR","ES","EF","LS","LF","TF","FF").joinToString("") {
                    it.padStart(5)
                })
                for (n in tasks.keys) {
                    val x = s.times.getValue(n)
                    out.add(n.padEnd(width)+listOf(x.duration,x.es,x.ef,x.ls,x.lf,x.tf,x.ff).joinToString("") {
                        it.toString().padStart(5)
                    }+if (x.tf == 0) " *" else "")
                }
                out.add("project duration ${s.total}")
            }
            "CRITICAL" -> {
                val paths = paths(s)
                out.add("critical paths: ${paths.size}")
                out.addAll(paths.map {
                    it.joinToString(" -> ")
                })
            }
            "SLACK" -> for ((f,names) in tasks.keys.groupBy {
                s.times.getValue(it).tf
            }.toSortedMap()) out.add("float $f: ${names.joinToString(" ")}")
            "DRAG" -> for (n in critical(s)) out.add("$n drag ${s.total-schedule(n,0).total}")
            "STATS" -> {
                val critical = critical(s).size
                val sum = s.times.values.sumOf {
                    it.tf
                }
                out.add("tasks ${tasks.size}, critical $critical, dependencies ${deps.size} (FS ${deps.count { it.kind == "FS" }}, SS ${deps.count { it.kind == "SS" }}, FF ${deps.count { it.kind == "FF" }})")
                out.add("work "+resources.joinToString(", ") {
                    r -> "$r ${tasks.values.filter { it.resource == r }.sumOf { it.duration*it.units }}"
                })
                out.add("float total $sum, average ${decimal(sum,tasks.size)}")
                out.add("duration ${s.total}, critical share ${decimal(100*critical,tasks.size)}%")
            }
            "CALENDAR" -> {
                val dates = mutableListOf<Int>()
                var day = start!!
                while (dates.size < s.total) {
                    if (working(day)) dates.add(day)
                    day++
                }
                for (n in byStart) {
                    val x = s.times.getValue(n)
                    out.add("$n ${dateText(dates[x.es])} - ${dateText(dates[x.ef-1])}")
                }
                val first = dates.first()
                val last = dates.last()
                out.add("project ${dateText(first)} - ${dateText(last)}, ${s.total} working days, ${last-first+1} calendar days")
                deadline?.let {
                    d -> val count = (minOf(d,last)+1..maxOf(d,last)).count {
                        working(it)
                    }
                    out.add(if (last <= d) "deadline ${dateText(d)} met, $count working days to spare" else "deadline ${dateText(d)} missed by $count working days")
                }
                out.add("holidays in span: "+holidays.filter {
                    it in first..last && (it+5)%7 < 5
                }.joinToString(", ") {
                    dateText(it)
                }.ifEmpty {
                    "none"
                })
            }
            "GANTT" -> {
                if (s.total > 60) fail("chart too wide (${s.total} days)")
                val width = tasks.keys.maxOf {
                    it.length
                }
                out.add(" ".repeat(width)+" |"+(0 until s.total).joinToString("") {
                    (it%10).toString()
                }+"|")
                for (n in byStart) {
                    val x = s.times.getValue(n)
                    val bar = (0 until s.total).map {
                        if (it >= x.es && it < x.ef) {
                            if (x.tf == 0) '=' else '-'
                        } else if (it >= x.ef && it < x.lf) '.' else ' '
                    }.joinToString("")
                    out.add(n.padEnd(width)+" |"+bar+"|")
                }
            }
            "LEVEL" -> {
                val decided = mutableMapOf<String,Pair<Int,Int>>()
                val decision = mutableListOf<String>()
                val dailyUsage = mutableMapOf<Pair<String,Int>,Int>()
                while (decided.size < tasks.size) {
                    val n = tasks.keys.filter {
                        it !in decided && preds(it).all {
                            d -> d.a in decided
                        }
                    }.minWith(compareBy<String> {
                        s.times.getValue(it).ls
                    }.thenBy {
                        it
                    })
                    val t = task(n)
                    var begin = t.notBefore
                    for (e in preds(n)) {
                        val p = decided.getValue(e.a)
                        begin = maxOf(begin,when(e.kind) {
                            "FS" -> p.second+e.lag
                            "SS" -> p.first+e.lag
                            else -> p.second+e.lag-t.duration
                        })
                    }
                    val capacity = capacities[t.resource] ?: num(0)
                    while ((begin until begin+t.duration).any {
                        (dailyUsage[t.resource to it] ?: 0)+t.units > capacity
                    }) begin++
                    val finish = begin+t.duration
                    decided[n] = begin to finish
                    decision.add(n)
                    for (d in begin until finish) dailyUsage[t.resource to d] = (dailyUsage[t.resource to d] ?: 0)+t.units
                }
                val total = decided.values.maxOf {
                    it.second
                }
                out.add("level capacity ${a[0]}: duration ${s.total} -> $total")
                for (n in decision) {
                    val p = decided.getValue(n)
                    out.add("$n start ${p.first} finish ${p.second} shift ${p.first-s.times.getValue(n).es}")
                }
                for (r in resources) out.add("resource $r capacity ${capacities[r] ?: num(0)} peak ${usage(r,initialTimes,s.total).maxOrNull()!!} -> ${usage(r,decided,total).maxOrNull()!!}")
            }
            "LOAD" -> {
                val load = usage(a[0],initialTimes,s.total)
                val peak = load.maxOrNull()!!
                out.add("load ${a[0]}: ${load.joinToString(" ")}")
                out.add("peak $peak on day ${load.indexOf(peak)}")
                capacities[a[0]]?.let {
                    cap -> out.add("capacity $cap exceeded on ${load.count { it > cap }} days")
                }
            }
            "PERTSUM" -> for (path in paths(s)) {
                var expected = 0
                var variance = 0
                for (n in path) {
                    val t = task(n)
                    val p = t.pert ?: listOf(t.duration,t.duration,t.duration)
                    expected += p[0]+4*p[1]+p[2]
                    variance += (p[2]-p[0])*(p[2]-p[0])
                }
                out.add("${path.joinToString(" -> ")}: expected ${decimal(expected,6)} variance ${decimal(variance,36)}")
            }
            "CRASH" -> {
                val budget = num(0)
                var remaining = budget
                var count = 0
                val reason: String
                while (true) {
                    val now = schedule()
                    val candidates = critical(now).filter {
                        n -> val t = task(n)
                        t.crash != null && t.used < t.crash!!.first && schedule(n,t.duration-1).total < now.total
                    }
                    if (candidates.isEmpty()) {
                        reason = "no candidate"
                        break
                    }
                    val n = candidates.minWith(compareBy<String> {
                        task(it).crash!!.second
                    }.thenBy {
                        it
                    })
                    val t = task(n)
                    val cost = t.crash!!.second
                    if (cost > remaining) {
                        reason = "insufficient budget"
                        break
                    }
                    val before = t.duration
                    t.used++
                    remaining -= cost
                    count++
                    out.add("step $count: $n $before -> ${t.duration}, cost $cost, project ${schedule().total}")
                }
                out.add("crash done: $count days, cost ${budget-remaining}, project ${s.total} -> ${schedule().total}, budget left $remaining, $reason")
            }
            "WHATIF" -> {
                val after = schedule(a[0],num(1))
                out.add("whatif ${a[0]} ${task(a[0]).duration} -> ${a[1]}: project ${s.total} -> ${after.total}")
                for (n in tasks.keys) {
                    val x = s.times.getValue(n)
                    val y = after.times.getValue(n)
                    val fields = listOf(Triple("ES",x.es,y.es),Triple("EF",x.ef,y.ef),Triple("TF",x.tf,y.tf)).filter {
                        it.second != it.third
                    }
                    if (fields.isNotEmpty()) out.add(n+fields.joinToString("") {
                        " ${it.first} ${it.second}->${it.third}"
                    })
                }
                val beforeCritical = critical(s)
                val afterCritical = critical(after)
                if (beforeCritical != afterCritical) out.add("critical ${beforeCritical.joinToString(" ")} -> ${afterCritical.joinToString(" ")}")
            }
            "BASELINE" -> {
                baseline = Baseline(s.total,initialTimes)
                out.add("baseline saved: ${tasks.size} tasks, duration ${s.total}")
            }
            "VARIANCE" -> {
                val old = baseline!!
                out.add("variance: duration ${old.total} -> ${s.total} (${signed(s.total-old.total)})")
                for (n in (old.times.keys+tasks.keys).toSortedSet()) {
                    val x = old.times[n]
                    val y = initialTimes[n]
                    if (x == null) out.add("$n new") else if (y == null) out.add("$n removed") else if (x != y) out.add("$n start ${signed(y.first-x.first)} finish ${signed(y.second-x.second)}")
                }
                if (out.size == 1) out.add("no task changes")
            }
        }
        return out
    }
}

fun main() {
    val project = Project()
    repeat(readLine()!!.toInt()) {
        try {
            project.command(readLine()!!.split(' ')).forEach(::println)
        } catch (p: Problem) {
            println(p.text)
        }
    }
}
