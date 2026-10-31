import java.util.Locale

private val DAYS = listOf("MO", "TU", "WE", "TH", "FR", "SA", "SU")
private val POINTS = mapOf('A' to 4, 'B' to 3, 'C' to 2, 'D' to 1, 'F' to 0)
private val COURSE_WORD = Regex("^[A-Z]{2,4}[0-9]{3}$")
private val YEAR_WORD = Regex("^Y[1-9]$")
private val TOKENS = Regex("[A-Z0-9]+|[&|()]")

private class CommandError(message: String) : RuntimeException(message)
private class ParseError : RuntimeException()

private fun fail(reason: String): Nothing = throw CommandError(reason)
private fun timeText(minutes: Int) =
    String.format(Locale.ROOT, "%02d:%02d", minutes / 60, minutes % 60)
private fun rateText(count: Int, capacity: Int) =
    if (capacity == 0) "n/a" else (count * 100 / capacity).toString() + "%"
private fun isYear(word: String) = YEAR_WORD.matches(word)

private enum class Kind { TRUE, WORD, AND, OR }

private class Expr(
    val kind: Kind,
    val word: String = "",
    val children: List<Expr> = emptyList()
) {
    val references: Set<String> =
        if (kind == Kind.WORD && !isYear(word)) setOf(word)
        else children.flatMap { it.references }.toSet()

    fun canonical(): String = when (kind) {
        Kind.TRUE -> "-"
        Kind.WORD -> word
        Kind.AND, Kind.OR -> children.joinToString(if (kind == Kind.AND) "&" else "|") { child ->
            val text = child.canonical()
            if (kind == Kind.AND && child.kind == Kind.OR) "(" + text + ")" else text
        }
    }

    fun evaluate(student: Student): Boolean = when (kind) {
        Kind.TRUE -> true
        Kind.WORD -> if (isYear(word)) student.year >= word[1].digitToInt()
                     else student.passedGrade(word) != null
        Kind.AND -> children.all { it.evaluate(student) }
        Kind.OR -> children.any { it.evaluate(student) }
    }
}

private fun combine(kind: Kind, children: List<Expr>): Expr {
    val flat = children.flatMap { if (it.kind == kind) it.children else listOf(it) }
    return if (flat.size == 1) flat[0] else Expr(kind, children = flat)
}

private class Parser(text: String) {
    private val tokens = TOKENS.findAll(text).map { it.value }.toList()
    private var position = 0

    init {
        if (tokens.isEmpty() ||
            tokens.any { it !in listOf("&", "|", "(", ")") &&
                         !COURSE_WORD.matches(it) && !YEAR_WORD.matches(it) }) {
            throw ParseError()
        }
    }

    private fun peek() = tokens.getOrNull(position)

    private fun factor(): Expr {
        val token = peek() ?: throw ParseError()
        if (token == "&" || token == "|" || token == ")") throw ParseError()
        position++
        if (token == "(") {
            val node = expression()
            if (peek() != ")") throw ParseError()
            position++
            return node
        }
        return Expr(Kind.WORD, token)
    }

    private fun term(): Expr {
        val children = mutableListOf(factor())
        while (peek() == "&") {
            position++
            children.add(factor())
        }
        return combine(Kind.AND, children)
    }

    private fun expression(): Expr {
        val children = mutableListOf(term())
        while (peek() == "|") {
            position++
            children.add(term())
        }
        return combine(Kind.OR, children)
    }

    fun parse(): Expr {
        val node = expression()
        if (position != tokens.size) throw ParseError()
        return node
    }
}

private fun prerequisite(code: String, text: String): Expr {
    if (text == "-") return Expr(Kind.TRUE)
    val expr = try {
        Parser(text).parse()
    } catch (_: ParseError) {
        fail("invalid prereq " + code)
    }
    if (code in expr.references) fail("self prereq " + code)
    return expr
}

private data class Slot(val day: Int, val start: Int, val end: Int, val original: String) {
    fun overlaps(other: Slot) =
        day == other.day && start < other.end && other.start < end
    fun display() = timeText(start) + "-" + timeText(end)
}

private fun slot(text: String): Slot {
    val day = DAYS.indexOf(text.substring(0, 2))
    val sh = text.substring(2, 4).toInt()
    val sm = text.substring(4, 6).toInt()
    val eh = text.substring(7, 9).toInt()
    val em = text.substring(9, 11).toInt()
    val start = sh * 60 + sm
    val end = eh * 60 + em
    if (day == -1 || sh > 23 || sm > 59 || eh > 23 || em > 59 || start >= end) {
        fail("invalid slot " + text)
    }
    return Slot(day, start, end, text)
}

private class Course(
    val code: String,
    val credits: Int,
    var capacity: Int,
    val slots: List<Slot>,
    var prerequisite: Expr
) {
    var open = true
    val enrolled = mutableSetOf<String>()
    val waitlist = mutableListOf<String>()
    val conflicts = mutableSetOf<String>()

    fun status() = if (open) "open" else "closed"
    fun weekly() = slots.sumOf { it.end - it.start }
    fun department() = code.dropLast(3)
}

private data class GradeRecord(val grade: Char, val credits: Int)

private class Student(
    val id: String,
    val year: Int,
    var limit: Int,
    val records: Map<String, GradeRecord>
) {
    val courses = mutableSetOf<String>()
    val waiting = mutableSetOf<String>()
    var credits = 0
    val history = mutableListOf<Pair<Int, String>>()

    fun passedGrade(code: String): Char? =
        records[code]?.grade?.takeIf { it == 'A' || it == 'B' || it == 'C' }

    fun earned() = records.values.sumOf { if (it.grade == 'F') 0 else it.credits }

    fun gpa(): String {
        if (records.isEmpty()) return "n/a"
        val points = records.values.sumOf { POINTS.getValue(it.grade) * it.credits }
        val total = records.values.sumOf { it.credits }
        val rounded = (200 * points + total) / (2 * total)
        return String.format(Locale.ROOT, "%d.%02d", rounded / 100, rounded % 100)
    }
}

private data class Decision(val kind: String, val extra: List<String> = emptyList()) {
    fun display() = (listOf(kind) + extra).joinToString(" ")
}

private class Registrar {
    private val courses = mutableMapOf<String, Course>()
    private val students = mutableMapOf<String, Student>()
    private var commandNumber = 0
    val output = mutableListOf<String>()

    private fun emit(vararg parts: Any, indented: Boolean = false) {
        output.add((if (indented) "  " else "") + parts.joinToString(" "))
    }

    private fun student(id: String): Student =
        students[id] ?: fail("unknown student " + id)

    private fun course(code: String): Course =
        courses[code] ?: fail("unknown course " + code)

    private fun record(student: Student, event: String) {
        student.history.add(commandNumber to event)
    }

    private fun conflict(student: Student, course: Course, excluded: String? = null) =
        student.courses.filter { it != excluded && it in course.conflicts }.minOrNull()

    private fun eligibility(student: Student, course: Course, excluded: String? = null): Decision {
        if (!course.open) return Decision("course closed")
        if (course.code in student.courses) return Decision("already enrolled")
        if (course.code in student.waiting) return Decision("already waitlisted")
        val grade = student.passedGrade(course.code)
        if (grade != null) return Decision("already completed", listOf(grade.toString()))
        if (!course.prerequisite.evaluate(student)) return Decision("prereq not met")
        val occupied = conflict(student, course, excluded)
        if (occupied != null) return Decision("time conflict", listOf(occupied))
        val credits = student.credits + course.credits -
                      (if (excluded == null) 0 else courses.getValue(excluded).credits)
        if (credits > student.limit) {
            return Decision("credit limit", listOf(credits.toString(), student.limit.toString()))
        }
        return Decision("OK")
    }

    private fun waitPosition(student: Student, course: Course) =
        1 + course.waitlist.count { students.getValue(it).year >= student.year }

    private fun request(student: Student, course: Course): Decision {
        val result = eligibility(student, course)
        if (result.kind != "OK") return result
        if (course.enrolled.size < course.capacity) return Decision("enroll")
        if (student.waiting.size >= 3) return Decision("waitlist limit")
        return Decision("waitlist", listOf(waitPosition(student, course).toString()))
    }

    private fun failRequest(result: Decision, student: Student, course: Course): Nothing =
        fail((listOf(result.kind, student.id, course.code) + result.extra).joinToString(" "))

    private fun enroll(student: Student, course: Course) {
        course.enrolled.add(student.id)
        student.courses.add(course.code)
        student.credits += course.credits
    }

    private fun withdraw(student: Student, course: Course) {
        course.enrolled.remove(student.id)
        student.courses.remove(course.code)
        student.credits -= course.credits
    }

    private fun unlist(student: Student, course: Course) {
        course.waitlist.remove(student.id)
        student.waiting.remove(course.code)
    }

    private fun promotion() {
        for (code in courses.keys.sorted()) {
            val course = courses.getValue(code)
            if (!course.open) continue
            for (id in course.waitlist.toList()) {
                if (course.enrolled.size >= course.capacity) break
                val student = students.getValue(id)
                if (conflict(student, course) != null ||
                    student.credits + course.credits > student.limit) continue
                unlist(student, course)
                enroll(student, course)
                record(student, "promote " + code)
                emit("PROMOTE", id, code, "enrolled",
                     course.enrolled.size.toString() + "/" + course.capacity,
                     "credits", student.credits.toString() + "/" + student.limit,
                     indented = true)
            }
        }
    }

    private fun cmdCourse(a: List<String>) {
        val code = a[0]
        if (courses.containsKey(code)) fail("duplicate course " + code)
        val slots = if (a[3] == "-") emptyList() else a[3].split(',').map(::slot)
        for (i in slots.indices) {
            for (j in i + 1 until slots.size) {
                if (slots[i].overlaps(slots[j])) {
                    fail("overlapping slots " + slots[i].original + " " + slots[j].original)
                }
            }
        }
        val required = prerequisite(code, a[4])
        val course = Course(code, a[1].toInt(), a[2].toInt(), slots, required)
        for ((otherCode, other) in courses) {
            if (slots.any { first -> other.slots.any { second -> first.overlaps(second) } }) {
                course.conflicts.add(otherCode)
                other.conflicts.add(code)
            }
        }
        courses[code] = course
        emit("COURSE", code, "credits", a[1], "capacity", a[2],
             "meetings", slots.size, "weekly", timeText(course.weekly()),
             "prereq", required.canonical())
    }

    private fun cmdStudent(a: List<String>) {
        val id = a[0]
        if (students.containsKey(id)) fail("duplicate student " + id)
        val records = linkedMapOf<String, GradeRecord>()
        if (a[3] != "-") {
            for (entry in a[3].split(',')) {
                val (code, gradeText, creditsText) = entry.split(':')
                val grade = gradeText.single()
                if (grade !in POINTS) fail("invalid grade " + id + " " + code + " " + grade)
                if (code in records) fail("duplicate record " + id + " " + code)
                records[code] = GradeRecord(grade, creditsText.toInt())
            }
        }
        val student = Student(id, a[1].toInt(), a[2].toInt(), records)
        students[id] = student
        emit("STUDENT", id, "year", a[1], "limit", a[2],
             "records", records.size, "earned", student.earned(), "gpa", student.gpa())
    }

    private fun cmdEnroll(a: List<String>) {
        val student = student(a[0])
        val course = course(a[1])
        val result = request(student, course)
        if (result.kind != "enroll" && result.kind != "waitlist") {
            failRequest(result, student, course)
        }
        if (result.kind == "enroll") {
            enroll(student, course)
            record(student, "enroll " + course.code)
            emit("ENROLL", student.id, course.code, "enrolled",
                 course.enrolled.size.toString() + "/" + course.capacity,
                 "credits", student.credits.toString() + "/" + student.limit)
        } else {
            val position = result.extra[0].toInt()
            course.waitlist.add(position - 1, student.id)
            student.waiting.add(course.code)
            record(student, "waitlist " + course.code + " " + position)
            emit("ENROLL", student.id, course.code, "waitlist", position)
        }
    }

    private fun cmdCheck(a: List<String>) {
        val student = student(a[0])
        val course = course(a[1])
        emit("CHECK", student.id, course.code, request(student, course).display())
    }

    private fun cmdOptions(a: List<String>) {
        val student = student(a[0])
        emit("OPTIONS", student.id, "courses", courses.size)
        for (code in courses.keys.sorted()) {
            emit(code, request(student, courses.getValue(code)).display(), indented = true)
        }
    }

    private fun cmdDrop(a: List<String>) {
        val student = student(a[0])
        val course = course(a[1])
        when {
            course.code in student.courses -> {
                withdraw(student, course)
                record(student, "drop " + course.code)
                emit("DROP", student.id, course.code, "enrolled",
                     course.enrolled.size.toString() + "/" + course.capacity,
                     "credits", student.credits.toString() + "/" + student.limit)
            }
            course.code in student.waiting -> {
                unlist(student, course)
                record(student, "drop " + course.code + " waitlist")
                emit("DROP", student.id, course.code, "waitlist removed")
            }
            else -> fail("not registered " + student.id + " " + course.code)
        }
        promotion()
    }

    private fun cmdSwap(a: List<String>) {
        val student = student(a[0])
        val source = course(a[1])
        val destination = course(a[2])
        if (source.code !in student.courses) {
            fail("not enrolled " + student.id + " " + source.code)
        }
        if (source.code == destination.code) fail("same course " + source.code)
        val eligibility = eligibility(student, destination, source.code)
        if (eligibility.kind != "OK") failRequest(eligibility, student, destination)
        if (destination.enrolled.size >= destination.capacity) {
            fail("course full " + destination.code)
        }
        withdraw(student, source)
        enroll(student, destination)
        record(student, "swap " + source.code + " " + destination.code)
        emit("SWAP", student.id, source.code, "->", destination.code,
             "credits", student.credits.toString() + "/" + student.limit)
        promotion()
    }

    private fun cmdClose(a: List<String>) {
        val course = course(a[0])
        if (!course.open) fail("already closed " + course.code)
        course.open = false
        emit("CLOSE", course.code, "enrolled",
             course.enrolled.size.toString() + "/" + course.capacity,
             "waitlist", course.waitlist.size)
    }

    private fun cmdOpen(a: List<String>) {
        val course = course(a[0])
        if (course.open) fail("already open " + course.code)
        course.open = true
        emit("OPEN", course.code, "enrolled",
             course.enrolled.size.toString() + "/" + course.capacity,
             "waitlist", course.waitlist.size)
        promotion()
    }

    private fun cmdCapacity(a: List<String>) {
        val course = course(a[0])
        val capacity = a[1].toInt()
        if (capacity < course.enrolled.size) {
            fail("capacity below enrollment " + course.code + " " + course.enrolled.size)
        }
        val previous = course.capacity
        course.capacity = capacity
        emit("CAPACITY", course.code, previous, "->", capacity)
        promotion()
    }

    private fun cmdLimit(a: List<String>) {
        val student = student(a[0])
        val limit = a[1].toInt()
        if (limit < student.credits) {
            fail("limit below enrolled " + student.id + " " + student.credits)
        }
        val previous = student.limit
        student.limit = limit
        emit("LIMIT", student.id, previous, "->", limit)
        promotion()
    }

    private fun cmdPrereq(a: List<String>) {
        val course = course(a[0])
        val required = prerequisite(course.code, a[1])
        course.prerequisite = required
        emit("PREREQ", course.code, required.canonical())
        for (id in course.waitlist.toList()) {
            val student = students.getValue(id)
            if (!required.evaluate(student)) {
                unlist(student, course)
                record(student, "unlist " + course.code)
                emit("UNLIST", student.id, course.code, indented = true)
            }
        }
    }

    private fun cmdCancel(a: List<String>) {
        val course = course(a[0])
        val code = course.code
        emit("CANCEL", code, "enrolled", course.enrolled.size,
             "waitlist", course.waitlist.size)
        for (id in course.enrolled) {
            val student = students.getValue(id)
            student.courses.remove(code)
            student.credits -= course.credits
            record(student, "cancel " + code)
        }
        for (id in course.waitlist) {
            val student = students.getValue(id)
            student.waiting.remove(code)
            record(student, "cancel " + code + " waitlist")
        }
        for (other in course.conflicts) {
            courses.getValue(other).conflicts.remove(code)
        }
        courses.remove(code)
        promotion()
    }

    private fun cmdRoster(a: List<String>) {
        val course = course(a[0])
        emit("ROSTER", course.code, course.status(), "enrolled",
             course.enrolled.size.toString() + "/" + course.capacity,
             "waitlist", course.waitlist.size)
        for (id in course.enrolled.sorted()) {
            emit("enrolled", id, "year", students.getValue(id).year, indented = true)
        }
        for ((index, id) in course.waitlist.withIndex()) {
            emit("waitlist", index + 1, id, "year", students.getValue(id).year, indented = true)
        }
    }

    private fun studentSlots(student: Student, day: Int): List<Triple<Int, Int, String>> =
        student.courses.flatMap { code ->
            courses.getValue(code).slots.filter { it.day == day }
                .map { Triple(it.start, it.end, code) }
        }.sortedWith(compareBy({ it.first }, { it.second }, { it.third }))

    private fun cmdSchedule(a: List<String>) {
        val student = student(a[0])
        val weekly = student.courses.sumOf { courses.getValue(it).weekly() }
        emit("SCHEDULE", student.id, "courses", student.courses.size,
             "credits", student.credits, "weekly", timeText(weekly))
        for ((day, name) in DAYS.withIndex()) {
            val slots = studentSlots(student, day)
            if (slots.isEmpty()) continue
            val row = buildList<String> {
                add(name)
                for ((start, end, code) in slots) {
                    add(timeText(start) + "-" + timeText(end))
                    add(code)
                }
            }
            emit(row.joinToString(" "), indented = true)
        }
        val tba = student.courses.filter { courses.getValue(it).slots.isEmpty() }.sorted()
        if (tba.isNotEmpty()) emit("TBA " + tba.joinToString(" "), indented = true)
    }

    private fun cmdFree(a: List<String>) {
        val student = student(a[0])
        val day = DAYS.indexOf(a[1])
        if (day < 0) fail("invalid day " + a[1])
        val occupied = studentSlots(student, day).mapNotNull { (start, end, _) ->
            val first = maxOf(480, start)
            val last = minOf(1320, end)
            if (first < last) first to last else null
        }
        val free = mutableListOf<Pair<Int, Int>>()
        var cursor = 480
        for ((start, end) in occupied) {
            if (cursor < start) free.add(cursor to start)
            cursor = maxOf(cursor, end)
        }
        if (cursor < 1320) free.add(cursor to 1320)
        val minutes = free.sumOf { it.second - it.first }
        val parts = free.map { timeText(it.first) + "-" + timeText(it.second) }
        emit((listOf("FREE", student.id, a[1], "total", timeText(minutes)) +
              parts).joinToString(" "))
    }

    private fun cmdInfo(a: List<String>) {
        val course = course(a[0])
        emit("INFO", course.code, course.status(), "credits", course.credits,
             "capacity", course.capacity, "prereq", course.prerequisite.canonical())
        val slots = course.slots.sortedWith(compareBy({ it.day }, { it.start }))
        if (slots.isEmpty()) {
            emit("meet TBA", indented = true)
        } else {
            for (slot in slots) {
                emit("meet", DAYS[slot.day], slot.display(), indented = true)
            }
        }
        val requiredBy = courses.values.filter {
            course.code in it.prerequisite.references
        }.map { it.code }.sorted()
        emit("required by", if (requiredBy.isEmpty()) "none" else requiredBy.joinToString(" "),
             indented = true)
    }

    private fun cmdAudit(a: List<String>) {
        val student = student(a[0])
        emit("AUDIT", student.id, "year", student.year, "limit", student.limit)
        for (code in student.records.keys.sorted()) {
            val record = student.records.getValue(code)
            emit("record", code, record.grade, record.credits, indented = true)
        }
        emit("earned", student.earned(), "gpa", student.gpa(), indented = true)
        for (code in student.courses.sorted()) {
            emit("enrolled", code, courses.getValue(code).credits, indented = true)
        }
        emit("credits", student.credits, "remaining", student.limit - student.credits,
             indented = true)
        for (code in student.waiting.sorted()) {
            val position = courses.getValue(code).waitlist.indexOf(student.id) + 1
            emit("waitlist", code, position, indented = true)
        }
    }

    private fun cmdHistory(a: List<String>) {
        val student = student(a[0])
        emit("HISTORY", student.id, "events", student.history.size)
        for ((number, event) in student.history) {
            emit(number, event, indented = true)
        }
    }

    private fun cmdStudents() {
        emit("STUDENTS", students.size)
        for (id in students.keys.sorted()) {
            val student = students.getValue(id)
            emit(id, "year", student.year, "credits",
                 student.credits.toString() + "/" + student.limit,
                 "courses", student.courses.size, "waitlists", student.waiting.size,
                 indented = true)
        }
    }

    private fun groupCounts(selected: Collection<Course>): String {
        val enrolled = selected.sumOf { it.enrolled.size }
        val capacity = selected.sumOf { it.capacity }
        val waiting = selected.sumOf { it.waitlist.size }
        return "enrolled " + enrolled + "/" + capacity + " rate " +
               rateText(enrolled, capacity) + " waitlisted " + waiting
    }

    private fun cmdReport() {
        emit("REPORT", "courses", courses.size, groupCounts(courses.values))
        for (code in courses.keys.sorted()) {
            val course = courses.getValue(code)
            emit(code, course.status(), course.enrolled.size.toString() + "/" + course.capacity,
                 rateText(course.enrolled.size, course.capacity), "waitlist", course.waitlist.size,
                 indented = true)
        }
        val departments = courses.values.groupBy { it.department() }
        for (name in departments.keys.sorted()) {
            val selected = departments.getValue(name)
            emit("dept", name, "courses", selected.size, groupCounts(selected), indented = true)
        }
    }

    fun execute(line: String) {
        commandNumber++
        val tokens = line.split(' ')
        val command = tokens[0]
        val a = tokens.drop(1)
        try {
            when (command) {
                "COURSE" -> cmdCourse(a)
                "STUDENT" -> cmdStudent(a)
                "ENROLL" -> cmdEnroll(a)
                "CHECK" -> cmdCheck(a)
                "OPTIONS" -> cmdOptions(a)
                "DROP" -> cmdDrop(a)
                "SWAP" -> cmdSwap(a)
                "CLOSE" -> cmdClose(a)
                "OPEN" -> cmdOpen(a)
                "CAPACITY" -> cmdCapacity(a)
                "LIMIT" -> cmdLimit(a)
                "PREREQ" -> cmdPrereq(a)
                "CANCEL" -> cmdCancel(a)
                "ROSTER" -> cmdRoster(a)
                "SCHEDULE" -> cmdSchedule(a)
                "FREE" -> cmdFree(a)
                "INFO" -> cmdInfo(a)
                "AUDIT" -> cmdAudit(a)
                "HISTORY" -> cmdHistory(a)
                "STUDENTS" -> cmdStudents()
                "REPORT" -> cmdReport()
            }
        } catch (error: CommandError) {
            emit("ERROR", error.message ?: "")
        }
    }
}

fun main() {
    val count = readln().toInt()
    val registrar = Registrar()
    repeat(count) {
        registrar.execute(readln())
    }
    registrar.output.forEach(::println)
}
