import java.util.ArrayDeque

private val TYPES = listOf("BUG", "TASK", "STORY")
private val PRIORITIES = listOf("LOW", "MEDIUM", "HIGH", "CRITICAL")
private val WORKFLOWS = mapOf(
    "BUG" to listOf("OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED", "CLOSED", "REOPENED"),
    "TASK" to listOf("OPEN", "IN_PROGRESS", "DONE"),
    "STORY" to listOf("BACKLOG", "READY", "IN_PROGRESS", "REVIEW", "DONE")
)
private val TRANSITIONS = mapOf(
    "BUG" to setOf("OPEN>TRIAGED", "TRIAGED>IN_PROGRESS", "IN_PROGRESS>REVIEW", "REVIEW>IN_PROGRESS",
        "REVIEW>RESOLVED", "RESOLVED>CLOSED", "RESOLVED>REOPENED", "CLOSED>REOPENED", "REOPENED>IN_PROGRESS"),
    "TASK" to setOf("OPEN>IN_PROGRESS", "IN_PROGRESS>OPEN", "IN_PROGRESS>DONE"),
    "STORY" to setOf("BACKLOG>READY", "READY>BACKLOG", "READY>IN_PROGRESS", "IN_PROGRESS>REVIEW",
        "REVIEW>IN_PROGRESS", "REVIEW>DONE")
)
private val EQUALITY = setOf("=", "!=")
private val ORDERED = EQUALITY + setOf("<", "<=", ">", ">=")
private val FIELD_OPERATORS = mapOf(
    "id" to ORDERED, "type" to EQUALITY, "status" to EQUALITY, "priority" to ORDERED,
    "assignee" to EQUALITY, "reviewer" to EQUALITY, "estimate" to ORDERED,
    "sprint" to EQUALITY, "comments" to ORDERED, "blocked" to EQUALITY,
    "done" to EQUALITY, "title" to setOf("~")
)

private class CommandError(message: String) : RuntimeException(message)
private fun display(value: Any?) = value?.toString() ?: "-"
private fun yesNo(value: Boolean) = if (value) "yes" else "no"
private fun numberList(numbers: Collection<Int>) = numbers.sorted().joinToString(",").ifEmpty { "-" }

private class Issue(val number: Int, val type: String, var priority: String, val title: String) {
    var state = WORKFLOWS.getValue(type).first()
    var assignee: String? = null
    var reviewer: String? = null
    var estimate: Int? = null
    var sprint: String? = null
    var comments = 0
    val blocks = mutableSetOf<Int>()
    val blockers = mutableSetOf<Int>()
    var duplicate: Int? = null
    val duplicates = mutableSetOf<Int>()
    val history = mutableListOf<String>()
    fun done() = state in setOf("RESOLVED", "CLOSED", "DONE")
    fun points() = estimate ?: 0
    fun level() = PRIORITIES.indexOf(priority)
}

private class Sprint(val name: String) {
    var phase = "PLANNED"
    var start = 0
    var end = 0
    var velocity = 0
    val records = mutableMapOf<Int, Int>()
}

private class QueryParser(
    private val tokens: List<String>,
    private val conditions: List<((Issue) -> Boolean)?>
) {
    private var position = 0
    private fun accept(token: String): Boolean {
        if (tokens.getOrNull(position) != token) return false
        position++
        return true
    }

    fun expression(): (Issue) -> Boolean {
        var node = term()
        while (accept("OR")) {
            val left = node
            val right = term()
            node = { left(it) || right(it) }
        }
        return node
    }

    private fun term(): (Issue) -> Boolean {
        var node = factor()
        while (accept("AND")) {
            val left = node
            val right = factor()
            node = { left(it) && right(it) }
        }
        return node
    }

    private fun factor(): (Issue) -> Boolean {
        if (accept("NOT")) {
            val operand = factor()
            return { !operand(it) }
        }
        if (accept("(")) {
            val node = expression()
            accept(")")
            return node
        }
        return conditions[position++]!!
    }
}

private class Tracker {
    private var day = 1
    private val users = mutableSetOf<String>()
    private val issues = mutableMapOf<Int, Issue>()
    private val sprints = linkedMapOf<String, Sprint>()

    private fun issue(text: String) = issues[text.toInt()] ?: throw CommandError("unknown issue")
    private fun sprint(name: String) = sprints[name] ?: throw CommandError("unknown sprint")
    private fun user(spec: String): String? {
        if (spec == "-") return null
        if (spec !in users) throw CommandError("unknown user")
        return spec
    }
    private fun notDone(issue: Issue) {
        if (issue.done()) throw CommandError("issue done")
    }
    private fun orderedIssues() = issues.values.sortedBy { it.number }
    private fun unfinished(issue: Issue) = issue.blockers.filter { !issues.getValue(it).done() }.sorted()
    private fun blocked(issue: Issue) = !issue.done() && unfinished(issue).isNotEmpty()
    private fun wip(user: String?) = issues.values.count { it.assignee == user && it.state == "IN_PROGRESS" }
    private fun activeSprint() = sprints.values.firstOrNull { it.phase == "ACTIVE" }
    private fun members(sprint: Sprint) = orderedIssues().filter { it.sprint == sprint.name }
    private fun remaining(sprint: Sprint) = members(sprint).filter { !it.done() }.sumOf { it.points() }
    private fun summary(sprint: Sprint): String {
        val members = members(sprint)
        return "issues ${members.size} points ${members.sumOf { it.points() }}"
    }
    private fun record(issue: Issue, content: String) { issue.history.add("day $day $content") }
    private fun blockedBefore(numbers: Collection<Int>) = numbers.associateWith { blocked(issues.getValue(it)) }
    private fun notify(before: Map<Int, Boolean>, output: MutableList<String>) {
        for (number in before.keys.sorted()) {
            val after = blocked(issues.getValue(number))
            if (after != before.getValue(number)) output.add("${if (after) "BLOCKED" else "UNBLOCKED"} $number")
        }
    }
    private fun changeState(issue: Issue, target: String, output: MutableList<String>) {
        val before = blockedBefore(issue.blocks)
        output.add("MOVE ${issue.number} ${issue.state} $target")
        record(issue, "MOVE ${issue.state} $target")
        issue.state = target
        notify(before, output)
    }
    private fun reaches(start: Int, goal: Int): Boolean {
        val pending = ArrayDeque<Int>()
        val visited = mutableSetOf<Int>()
        pending.add(start)
        while (pending.isNotEmpty()) {
            val number = pending.removeFirst()
            if (number == goal) return true
            if (visited.add(number)) pending.addAll(issues.getValue(number).blocks)
        }
        return false
    }

    private fun compare(actual: Int?, expected: Int?, operator: String): Boolean = when (operator) {
        "=" -> actual == expected
        "!=" -> actual != expected
        "<" -> actual != null && actual < expected!!
        "<=" -> actual != null && actual <= expected!!
        ">" -> actual != null && actual > expected!!
        else -> actual != null && actual >= expected!!
    }

    private fun condition(token: String): (Issue) -> Boolean {
        val field = token.takeWhile { it in 'a'..'z' }
        val rest = token.substring(field.length)
        val operator = listOf(">=", "<=", "!=", "=", "<", ">", "~").firstOrNull { rest.startsWith(it) }
        val text = operator?.let { rest.substring(it.length) } ?: ""
        if (field.isEmpty() || operator == null || text.isEmpty()) throw CommandError("syntax near $token")
        val operators = FIELD_OPERATORS[field] ?: throw CommandError("unknown field $field")
        if (operator !in operators) throw CommandError("bad operator $token")
        val none = text == "-" && field in setOf("assignee", "reviewer", "estimate", "sprint") && operator in EQUALITY
        var numeric: Int? = null
        var string: String? = if (none) null else text
        val valid = when (field) {
            "id", "estimate", "comments" -> if (none) true else {
                if (Regex("[0-9]{1,6}").matches(text)) { numeric = text.toInt(); true } else false
            }
            "priority" -> if (text in PRIORITIES) { numeric = PRIORITIES.indexOf(text); true } else false
            "type" -> text in TYPES
            "status" -> WORKFLOWS.values.any { text in it }
            "assignee", "reviewer" -> none || text in users
            "sprint" -> none || text in sprints
            "blocked", "done" -> text == "yes" || text == "no"
            "title" -> { string = text.lowercase(); true }
            else -> false
        }
        if (!valid) throw CommandError("bad value $token")
        val expectedNumber = numeric
        val expectedString = string
        return { issue ->
            if (field in setOf("id", "estimate", "comments", "priority")) {
                val actual = when (field) {
                    "id" -> issue.number
                    "estimate" -> issue.estimate
                    "comments" -> issue.comments
                    else -> issue.level()
                }
                compare(actual, expectedNumber, operator)
            } else {
                val actual = when (field) {
                    "type" -> issue.type
                    "status" -> issue.state
                    "assignee" -> issue.assignee
                    "reviewer" -> issue.reviewer
                    "sprint" -> issue.sprint
                    "blocked" -> yesNo(blocked(issue))
                    "done" -> yesNo(issue.done())
                    else -> issue.title.lowercase()
                }
                when (operator) {
                    "~" -> actual!!.contains(expectedString!!)
                    "=" -> actual == expectedString
                    else -> actual != expectedString
                }
            }
        }
    }

    private fun query(text: String, output: MutableList<String>) {
        val tokens = Regex("[()]|[^ ()]+").findAll(text).map { it.value }.toList()
        val conditions = mutableListOf<((Issue) -> Boolean)?>()
        var operand = true
        var depth = 0
        for (token in tokens) {
            var predicate: ((Issue) -> Boolean)? = null
            if (operand) when (token) {
                "NOT" -> Unit
                "(" -> depth++
                "AND", "OR", ")" -> throw CommandError("syntax near $token")
                else -> { predicate = condition(token); operand = false }
            } else when (token) {
                "AND", "OR" -> operand = true
                ")" -> if (depth > 0) depth-- else throw CommandError("syntax near $token")
                else -> throw CommandError("syntax near $token")
            }
            conditions.add(predicate)
        }
        if (operand || depth != 0) throw CommandError("syntax at end")
        val predicate = QueryParser(tokens, conditions).expression()
        val matches = issues.values.filter(predicate).sortedWith(compareByDescending<Issue> { it.level() }.thenBy { it.number })
        output.add("QUERY ${matches.size}")
        for (issue in matches) output.add("${issue.number} ${issue.type} ${issue.priority} ${issue.state} " +
            "${display(issue.assignee)} ${display(issue.estimate)} ${issue.title}")
    }

    private fun sprintCommand(words: List<String>, output: MutableList<String>) {
        val action = words[1]
        val name = words[2]
        if (action == "NEW") {
            if (name in sprints) throw CommandError("sprint exists")
            sprints[name] = Sprint(name)
            output.add("SPRINT NEW $name")
            return
        }
        val sprint = sprint(name)
        when (action) {
            "ADD", "REMOVE" -> {
                val issue = issue(words[3])
                if (sprint.phase == "ENDED") throw CommandError("sprint ended")
                if (action == "ADD") {
                    notDone(issue)
                    if (issue.sprint != null && sprints.getValue(issue.sprint!!).phase != "ENDED") {
                        throw CommandError("in sprint ${issue.sprint}")
                    }
                    if (issue.state == "BACKLOG") throw CommandError("not ready")
                    issue.sprint = name
                } else {
                    if (issue.sprint != name) throw CommandError("not in sprint")
                    notDone(issue)
                    issue.sprint = null
                }
                record(issue, "SPRINT $action $name")
                output.add("SPRINT $action $name ${issue.number} ${summary(sprint)}")
            }
            "START" -> {
                if (sprint.phase != "PLANNED") throw CommandError("sprint not planned")
                activeSprint()?.let { throw CommandError("sprint active ${it.name}") }
                if (members(sprint).isEmpty()) throw CommandError("sprint empty")
                sprint.phase = "ACTIVE"
                sprint.start = day
                sprint.records[day] = remaining(sprint)
                output.add("SPRINT START $name day $day ${summary(sprint)} remaining ${remaining(sprint)}")
            }
            "END" -> {
                if (sprint.phase != "ACTIVE") throw CommandError("sprint not active")
                sprint.records[day] = remaining(sprint)
                val members = members(sprint)
                val finished = members.filter { it.done() }
                val returned = members.filter { !it.done() }
                sprint.velocity = finished.sumOf { it.points() }
                sprint.phase = "ENDED"
                sprint.end = day
                output.add("SPRINT END $name day $day velocity ${sprint.velocity} done ${finished.size} returned ${returned.size}")
                for (issue in returned) {
                    issue.sprint = null
                    record(issue, "SPRINT RETURN $name")
                    output.add("RETURNED ${issue.number}")
                }
            }
        }
    }

    private fun process(line: String, output: MutableList<String>) {
        val words = line.split(' ')
        when (val command = words[0]) {
            "DAY" -> {
                val next = words[1].toInt()
                if (next < day) throw CommandError("day backwards")
                day = next
                output.add("DAY $day")
            }
            "USER" -> {
                if (!users.add(words[1])) throw CommandError("user exists")
                output.add("USER ${words[1]}")
            }
            "CREATE" -> {
                val number = words[1].toInt()
                if (number in issues) throw CommandError("issue exists")
                if (words[2] !in TYPES) throw CommandError("bad type")
                if (words[3] !in PRIORITIES) throw CommandError("bad priority")
                val issue = Issue(number, words[2], words[3], words.drop(4).joinToString(" "))
                issues[number] = issue
                record(issue, "CREATE ${issue.type} ${issue.priority}")
                output.add("CREATE $number ${issue.type} ${issue.priority} ${issue.state}")
            }
            "PRIORITY" -> {
                val issue = issue(words[1])
                val priority = words[2]
                if (priority !in PRIORITIES) throw CommandError("bad priority")
                notDone(issue)
                if (priority == issue.priority) throw CommandError("no change")
                val old = issue.priority
                issue.priority = priority
                record(issue, "PRIORITY $old $priority")
                output.add("PRIORITY ${issue.number} $old $priority")
            }
            "ASSIGN", "REVIEWER" -> {
                val issue = issue(words[1])
                val spec = words[2]
                val user = user(spec)
                notDone(issue)
                val old = if (command == "ASSIGN") issue.assignee else issue.reviewer
                if (old == user) throw CommandError("no change")
                if (command == "ASSIGN") {
                    if (user == null && issue.state in setOf("IN_PROGRESS", "REVIEW")) throw CommandError("assignee required")
                    if (issue.state == "IN_PROGRESS" && wip(user) >= 3) throw CommandError("wip limit $spec")
                    if (issue.state == "REVIEW" && user == issue.reviewer) throw CommandError("reviewer is assignee")
                    issue.assignee = user
                } else {
                    if (user == null && issue.state == "REVIEW") throw CommandError("reviewer required")
                    if (issue.state == "REVIEW" && user == issue.assignee) throw CommandError("reviewer is assignee")
                    issue.reviewer = user
                }
                record(issue, "$command $spec")
                output.add("$command ${issue.number} $spec")
            }
            "ESTIMATE" -> {
                val issue = issue(words[1])
                val points = words[2].toInt()
                if (points !in setOf(0, 1, 2, 3, 5, 8, 13, 21)) throw CommandError("bad estimate")
                notDone(issue)
                if (issue.estimate == points) throw CommandError("no change")
                val old = display(issue.estimate)
                issue.estimate = points
                record(issue, "ESTIMATE $old $points")
                output.add("ESTIMATE ${issue.number} $old $points")
            }
            "COMMENT" -> {
                val issue = issue(words[1])
                user(words[2])
                issue.comments++
                record(issue, "COMMENT ${words[2]} ${words.drop(3).joinToString(" ")}")
                output.add("COMMENT ${issue.number} ${issue.comments}")
            }
            "MOVE" -> {
                val issue = issue(words[1])
                val target = words[2]
                if (issue.duplicate != null) throw CommandError("duplicate of ${issue.duplicate}")
                if (target !in WORKFLOWS.getValue(issue.type)) throw CommandError("bad state")
                if ("${issue.state}>$target" !in TRANSITIONS.getValue(issue.type)) {
                    throw CommandError("cannot move ${issue.state} to $target")
                }
                if (target == "IN_PROGRESS") {
                    val active = activeSprint()
                    if (issue.type == "STORY" && (active == null || issue.sprint != active.name)) throw CommandError("not in active sprint")
                    if (issue.assignee == null) throw CommandError("no assignee")
                    if (wip(issue.assignee) >= 3) throw CommandError("wip limit ${issue.assignee}")
                }
                if (target == "REVIEW") {
                    if (issue.reviewer == null) throw CommandError("no reviewer")
                    if (issue.reviewer == issue.assignee) throw CommandError("reviewer is assignee")
                }
                if (target in setOf("DONE", "RESOLVED")) {
                    unfinished(issue).firstOrNull()?.let { throw CommandError("blocked by $it") }
                }
                if (target == "READY" && issue.estimate == null) throw CommandError("no estimate")
                changeState(issue, target, output)
            }
            "LINK", "UNLINK" -> {
                val relation = words[2]
                if (relation !in (if (command == "LINK") setOf("BLOCKS", "DUPLICATES") else setOf("BLOCKS"))) throw CommandError("bad link")
                val source = issue(words[1])
                val target = issue(words[3])
                if (command == "UNLINK") {
                    if (target.number !in source.blocks) throw CommandError("no link")
                    val before = blockedBefore(listOf(target.number))
                    source.blocks.remove(target.number)
                    target.blockers.remove(source.number)
                    record(source, "UNLINK BLOCKS ${target.number}")
                    record(target, "UNLINK BLOCKED_BY ${source.number}")
                    output.add("UNLINK ${source.number} BLOCKS ${target.number}")
                    notify(before, output)
                } else {
                    if (source === target) throw CommandError("self link")
                    if (relation == "BLOCKS") {
                        if (target.number in source.blocks) throw CommandError("link exists")
                        if (reaches(target.number, source.number)) throw CommandError("cycle")
                        notDone(target)
                        val before = blockedBefore(listOf(target.number))
                        source.blocks.add(target.number)
                        target.blockers.add(source.number)
                        record(source, "LINK BLOCKS ${target.number}")
                        record(target, "LINK BLOCKED_BY ${source.number}")
                        output.add("LINK ${source.number} BLOCKS ${target.number}")
                        notify(before, output)
                    } else {
                        if (source.type != target.type) throw CommandError("type mismatch")
                        notDone(source)
                        if (target.duplicate != null) throw CommandError("target is duplicate")
                        source.duplicate = target.number
                        target.duplicates.add(source.number)
                        record(source, "LINK DUPLICATES ${target.number}")
                        record(target, "LINK DUPLICATED_BY ${source.number}")
                        output.add("LINK ${source.number} DUPLICATES ${target.number}")
                        changeState(source, if (source.type == "BUG") "CLOSED" else "DONE", output)
                        if (source.sprint != null && sprints.getValue(source.sprint!!).phase != "ENDED") {
                            record(source, "SPRINT REMOVE ${source.sprint}")
                            source.sprint = null
                        }
                    }
                }
            }
            "SPRINT" -> sprintCommand(words, output)
            "QUERY" -> query(words.drop(1).joinToString(" "), output)
            "SHOW" -> {
                val issue = issue(words[1])
                output.add("ISSUE ${issue.number} ${issue.type} ${issue.priority} ${issue.state} blocked ${yesNo(blocked(issue))}")
                output.add("TITLE ${issue.title}")
                output.add("PEOPLE assignee ${display(issue.assignee)} reviewer ${display(issue.reviewer)}")
                output.add("PLAN estimate ${display(issue.estimate)} sprint ${display(issue.sprint)} comments ${issue.comments}")
                output.add("LINKS blocks ${numberList(issue.blocks)} blocked_by ${numberList(issue.blockers)} " +
                    "duplicate_of ${display(issue.duplicate)} duplicated_by ${numberList(issue.duplicates)}")
            }
            "HISTORY" -> {
                val issue = issue(words[1])
                output.add("HISTORY ${issue.number} ${issue.history.size}")
                output.addAll(issue.history)
            }
            "BOARD" -> {
                output.add("BOARD")
                for (type in TYPES) output.add(type + WORKFLOWS.getValue(type).joinToString("") { state ->
                    " $state ${issues.values.count { it.type == type && it.state == state }}"
                })
                val done = issues.values.count { it.done() }
                output.add("TOTAL ${issues.size} open ${issues.size - done} done $done")
            }
            "WORKLOAD" -> {
                output.add("WORKLOAD ${users.size}")
                for (user in users.sorted()) {
                    val assigned = issues.values.filter { it.assignee == user && !it.done() }
                    output.add("$user assigned ${assigned.size} in_progress ${assigned.count { it.state == "IN_PROGRESS" }} " +
                        "review ${assigned.count { it.state == "REVIEW" }} reviewing ${issues.values.count { it.reviewer == user && it.state == "REVIEW" }} " +
                        "points ${assigned.sumOf { it.points() }}")
                }
            }
            "SPRINTS" -> {
                output.add("SPRINTS ${sprints.size}")
                for (sprint in sprints.values) output.add(when (sprint.phase) {
                    "PLANNED" -> "${sprint.name} PLANNED ${summary(sprint)}"
                    "ACTIVE" -> "${sprint.name} ACTIVE start ${sprint.start} ${summary(sprint)} remaining ${remaining(sprint)}"
                    else -> "${sprint.name} ENDED start ${sprint.start} end ${sprint.end} velocity ${sprint.velocity}"
                })
            }
            "BURNDOWN" -> {
                val sprint = sprint(words[1])
                if (sprint.phase == "PLANNED") throw CommandError("sprint not started")
                val last = if (sprint.phase == "ACTIVE") day else sprint.end
                output.add("BURNDOWN ${sprint.name} ${sprint.phase} days ${last - sprint.start + 1}")
                var value = 0
                for (recordDay in sprint.start..last) {
                    value = sprint.records[recordDay] ?: value
                    output.add("day $recordDay $value")
                }
            }
        }
    }

    fun execute(line: String): List<String> {
        val output = mutableListOf<String>()
        try { process(line, output) } catch (error: CommandError) { output.add("ERROR ${error.message}") }
        activeSprint()?.let { it.records[day] = remaining(it) }
        return output
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val tracker = Tracker()
    repeat(input.readLine().toInt()) {
        for (line in tracker.execute(input.readLine())) {
            output.write(line)
            output.newLine()
        }
    }
    output.flush()
}
