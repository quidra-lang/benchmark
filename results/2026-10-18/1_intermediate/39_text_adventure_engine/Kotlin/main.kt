import java.io.Writer

val directions = listOf("north", "south", "east", "west", "up", "down")

fun direction(word: String) = directions.indexOfFirst { word == it || word == it.take(1) }

fun words(line: String) =
    line.lowercase().split(' ').filter { it.isNotEmpty() && it != "the" && it != "a" && it != "an" }

fun all(phrase: List<String>) = phrase.size == 1 && phrase[0] == "all"

fun tail(words: List<String>, at: Int) = words.drop(at).joinToString(" ")

class CommandFailure(message: String) : RuntimeException(message)

fun fail(message: String): Nothing = throw CommandFailure(message)

enum class PlaceKind {
    NOWHERE,
    FLOOR,
    PLAYER,
    INSIDE,
}

data class Place(val kind: PlaceKind, val index: Int = 0)

val nowhere = Place(PlaceKind.NOWHERE)
val player = Place(PlaceKind.PLAYER)

fun inside(item: Int) = Place(PlaceKind.INSIDE, item)

fun roomFloor(room: Int) = Place(PlaceKind.FLOOR, room)

enum class ContainerState {
    OPEN,
    CLOSED,
    LOCKED,
}

enum class EndStatus {
    PLAYING,
    WON,
    DEAD,
}

data class Exit(val destination: Int, val key: Int? = null, val locked: Boolean = false)

class State(rooms: Int, items: Int) {
    var room = 0
    var bonus = 0
    var moves = 0
    var darkness = 0
    var ended = EndStatus.PLAYING
    val places = Array(items) { nowhere }
    val containers = Array(items) { ContainerState.OPEN }
    val fuel = IntArray(items)
    val lit = BooleanArray(items)
    val visited = BooleanArray(rooms)
    val exits = Array(rooms) { arrayOfNulls<Exit>(6) }
    val flags = mutableSetOf<String>()

    constructor(source: State) : this(source.visited.size, source.places.size) {
        room = source.room
        bonus = source.bonus
        moves = source.moves
        darkness = source.darkness
        ended = source.ended
        source.places.copyInto(places)
        source.containers.copyInto(containers)
        source.fuel.copyInto(fuel)
        source.lit.copyInto(lit)
        source.visited.copyInto(visited)
        flags.addAll(source.flags)
        for (i in exits.indices) source.exits[i].copyInto(exits[i])
    }
}

class Room {
    var name = ""
    var dark = false
    val description = mutableListOf<String>()
}

class Item(id: String) {
    var name = ""
    val nouns = mutableSetOf(id)
    val nameWords = mutableSetOf<String>()
    val details = mutableListOf<String>()
    var weight = 0
    var treasure = 0
    var capacity = 0
    var key: Int? = null
    var light = false
    var fixed = false
}

data class Trigger(val enter: Boolean, val first: Int, val second: Int = 0) {
    companion object {
        fun onEnter(room: Int) = Trigger(true, room)

        fun onUse(first: Int, second: Int) = Trigger(false, first, second)
    }
}

data class Condition(val flag: String, val on: Boolean)

sealed interface Effect

data class Message(val text: String) : Effect

data class OpenExit(val room: Int, val direction: Int, val destination: Int) : Effect

data class MoveItem(val item: Int, val place: Place) : Effect

data class SetFlag(val flag: String, val on: Boolean) : Effect

data class Points(val amount: Int) : Effect

data class Rule(val trigger: Trigger, val condition: Condition?, val effect: Effect)

data class RuleResult(val executed: Int, val message: Boolean)

data class Treasures(val points: Int, val stored: Int, val total: Int)

fun readRule(
    w: List<String>,
    start: Int,
    trigger: Trigger,
    rooms: Map<String, Int>,
    items: Map<String, Int>,
): Rule {
    var at = start
    var condition: Condition? = null
    if (w[at] == "IF" || w[at] == "UNLESS") {
        condition = Condition(w[at + 1], w[at] == "IF")
        at += 2
    }
    val effect =
        when (w[at]) {
            "MESSAGE" -> Message(tail(w, at + 1))
            "OPEN" ->
                OpenExit(rooms.getValue(w[at + 1]), direction(w[at + 2]), rooms.getValue(w[at + 3]))
            "REMOVE" -> MoveItem(items.getValue(w[at + 1]), nowhere)
            "ADD" -> MoveItem(items.getValue(w[at + 1]), roomFloor(rooms.getValue(w[at + 2])))
            "SET",
            "CLEAR" -> SetFlag(w[at + 1], w[at] == "SET")
            "POINTS" -> Points(w[at + 1].toInt())
            else -> error("Invalid world")
        }
    return Rule(trigger, condition, effect)
}

enum class Verb {
    GO,
    LOOK,
    EXAMINE,
    TAKE,
    DROP,
    PUT,
    INVENTORY,
    OPEN,
    CLOSE,
    UNLOCK,
    LOCK,
    USE,
    LIGHT,
    EXTINGUISH,
    WAIT,
    SCORE,
    SAVE,
    RESTORE,
    VERBOSE,
    BRIEF;

    val text
        get() = name.lowercase()

    fun noArguments() =
        when (this) {
            LOOK,
            INVENTORY,
            WAIT,
            SCORE,
            SAVE,
            RESTORE,
            VERBOSE,
            BRIEF -> true
            else -> false
        }

    fun action() =
        when (this) {
            GO,
            TAKE,
            DROP,
            PUT,
            OPEN,
            CLOSE,
            UNLOCK,
            LOCK,
            USE,
            LIGHT,
            EXTINGUISH,
            WAIT -> true
            else -> false
        }

    companion object {
        fun parse(word: String): Verb? =
            when (word) {
                "go",
                "walk",
                "run" -> GO
                "look",
                "l" -> LOOK
                "examine",
                "x",
                "inspect",
                "read" -> EXAMINE
                "take",
                "get",
                "grab" -> TAKE
                "drop",
                "discard" -> DROP
                "put",
                "insert",
                "place" -> PUT
                "inventory",
                "inv",
                "i" -> INVENTORY
                "open" -> OPEN
                "close",
                "shut" -> CLOSE
                "unlock" -> UNLOCK
                "lock" -> LOCK
                "use",
                "apply" -> USE
                "light",
                "ignite" -> LIGHT
                "extinguish",
                "douse",
                "snuff" -> EXTINGUISH
                "wait",
                "z" -> WAIT
                "score" -> SCORE
                "save" -> SAVE
                "restore",
                "load" -> RESTORE
                "verbose" -> VERBOSE
                "brief" -> BRIEF
                else -> null
            }
    }
}

class Adventure(definitions: List<List<String>>) {
    val rooms: Array<Room>
    val items: Array<Item>
    val rules = mutableListOf<Rule>()
    val vocabulary = mutableSetOf<String>()
    val output = mutableListOf<String>()
    var trophy = 0
    var maxWeight = 0
    var state: State
    var saved: State? = null
    var pronoun: Int? = null
    var previous: String? = null
    var verbose = false

    init {
        val roomIds =
            definitions
                .filter { it[0] == "ROOM" }
                .map { it[1] }
                .withIndex()
                .associate { it.value to it.index }
        val itemNames = definitions.filter { it[0] == "ITEM" }.map { it[1] }.sorted()
        val itemIds = itemNames.withIndex().associate { it.value to it.index }
        rooms = Array(roomIds.size) { Room() }
        items = Array(itemNames.size) { Item(itemNames[it]) }
        state = State(rooms.size, items.size)
        for (w in definitions) when (w[0]) {
            "ROOM" -> {
                val room = rooms[roomIds.getValue(w[1])]
                room.dark = w[2] == "DARK"
                room.name = tail(w, if (room.dark) 3 else 2)
            }
            "DESC" -> rooms[roomIds.getValue(w[1])].description.add(tail(w, 2))
            "EXIT" ->
                state.exits[roomIds.getValue(w[1])][direction(w[2])] =
                    Exit(
                        roomIds.getValue(w[3]),
                        if (w.size > 4) itemIds.getValue(w[5]) else null,
                        w.size > 4,
                    )
            "ITEM" -> {
                val x = itemIds.getValue(w[1])
                state.places[x] =
                    when (w[2]) {
                        "PLAYER" -> player
                        "NOWHERE" -> nowhere
                        else -> roomFloor(roomIds.getValue(w[2]))
                    }
                val item = items[x]
                item.weight = w[3].toInt()
                var at = 4
                if (w[at] == "TREASURE") {
                    item.treasure = w[at + 1].toInt()
                    at += 2
                }
                if (w[at] == "LIGHT") {
                    item.light = true
                    state.fuel[x] = w[at + 1].toInt()
                    at += 2
                }
                if (w[at] == "CONTAINER") {
                    item.capacity = w[at + 1].toInt()
                    at += 2
                    if (w[at] == "CLOSED") {
                        state.containers[x] = ContainerState.CLOSED
                        at++
                    }
                    if (w[at] == "LOCKED") {
                        item.key = itemIds.getValue(w[at + 1])
                        state.containers[x] = ContainerState.LOCKED
                        at += 2
                    }
                }
                if (w[at] == "FIXED") {
                    item.fixed = true
                    at++
                }
                item.name = tail(w, at)
                item.nameWords.addAll(w.drop(at))
            }
            "INSIDE" -> state.places[itemIds.getValue(w[1])] = inside(itemIds.getValue(w[2]))
            "ALIAS" -> items[itemIds.getValue(w[1])].nouns.add(w[2])
            "DETAIL" -> items[itemIds.getValue(w[1])].details.add(tail(w, 2))
            "RULE" ->
                rules.add(
                    readRule(
                        w,
                        3,
                        Trigger.onUse(itemIds.getValue(w[1]), itemIds.getValue(w[2])),
                        roomIds,
                        itemIds,
                    ),
                )
            "ENTER" ->
                rules.add(readRule(w, 2, Trigger.onEnter(roomIds.getValue(w[1])), roomIds, itemIds))
            "TROPHY" -> trophy = roomIds.getValue(w[1])
            "START" -> state.room = roomIds.getValue(w[1])
            "MAXWEIGHT" -> maxWeight = w[1].toInt()
        }
        state.visited[state.room] = true
        for (item in items) {
            vocabulary.addAll(item.nouns)
            vocabulary.addAll(item.nameWords)
        }
    }

    fun say(text: String) {
        output.add(text)
    }

    fun floor() = roomFloor(state.room)

    fun direct(place: Place) = items.indices.filter { state.places[it] == place }

    fun reachable(item: Int, root: Place): Boolean {
        var place = state.places[item]
        while (place.kind == PlaceKind.INSIDE) {
            if (state.containers[place.index] != ContainerState.OPEN) return false
            place = state.places[place.index]
        }
        return place == root
    }

    fun carried(item: Int) = reachable(item, player)

    fun roomItem(item: Int) = reachable(item, floor())

    fun isLit() =
        !rooms[state.room].dark ||
            items.indices.any { state.lit[it] && (carried(it) || roomItem(it)) }

    fun totalWeight(item: Int): Int = items[item].weight + placeWeight(inside(item))

    fun placeWeight(place: Place): Int = direct(place).sumOf { totalWeight(it) }

    fun within(item: Int, ancestor: Int): Boolean {
        var place = state.places[item]
        while (place.kind == PlaceKind.INSIDE) {
            if (place.index == ancestor) return true
            place = state.places[place.index]
        }
        return false
    }

    fun stored(item: Int): Boolean {
        var place = state.places[item]
        while (place.kind == PlaceKind.INSIDE) place = state.places[place.index]
        return place == roomFloor(trophy)
    }

    fun treasures(): Treasures {
        var points = 0
        var storedCount = 0
        var total = 0
        for (i in items.indices) if (items[i].treasure > 0) {
            total++
            if (stored(i)) {
                storedCount++
                points += items[i].treasure
            }
        }
        return Treasures(points, storedCount, total)
    }

    fun score() = treasures().points + state.bonus

    fun displayName(item: Int): String {
        val annotations = mutableListOf<String>()
        if (items[item].capacity > 0) annotations.add(state.containers[item].name.lowercase())
        if (state.lit[item]) annotations.add("lit")
        return items[item].name +
            if (annotations.isEmpty()) "" else " (${annotations.joinToString(", ")})"
    }

    fun itemTree(place: Place, depth: Int) {
        for (item in direct(place)) {
            say("  ".repeat(depth) + displayName(item))
            if (items[item].capacity > 0 && state.containers[item] == ContainerState.OPEN)
                itemTree(inside(item), depth + 1)
        }
    }

    fun describe(full: Boolean) {
        if (!isLit()) {
            say("It is pitch dark.")
            return
        }
        say(rooms[state.room].name)
        if (full) output.addAll(rooms[state.room].description)
        val exits =
            (0..5).mapNotNull { d ->
                state.exits[state.room][d]?.let {
                    directions[d] + if (it.locked) " (locked)" else ""
                }
            }
        say("Exits: " + if (exits.isEmpty()) "none" else exits.joinToString(", "))
        if (direct(floor()).isNotEmpty()) {
            say("You see:")
            itemTree(floor(), 1)
        }
    }

    fun names(selected: List<Int>) = selected.joinToString(", ") { items[it].name }

    fun resolve(phrase: List<String>): Int {
        val lit = isLit()
        if (phrase.size == 1 && phrase[0] == "it") {
            val item = pronoun ?: fail("I don't know what \"it\" refers to.")
            if (!carried(item) && !(lit && roomItem(item))) fail("You can't see any such thing.")
            return item
        }
        for (word in phrase) if (word !in vocabulary) fail("I don't know the word \"$word\".")
        val matches =
            items.indices.filter { i ->
                (carried(i) || lit && roomItem(i)) &&
                    phrase.last() in items[i].nouns &&
                    items[i].nameWords.containsAll(phrase.dropLast(1))
            }
        if (matches.isEmpty()) fail("You can't see any such thing.")
        if (matches.size > 1) fail("Which do you mean: ${names(matches)}?")
        pronoun = matches[0]
        return matches[0]
    }

    fun runRules(trigger: Trigger): RuleResult {
        var executed = 0
        var message = false
        for (rule in rules) {
            val condition = rule.condition
            if (
                rule.trigger != trigger ||
                    condition != null && (condition.flag in state.flags) != condition.on
            )
                continue
            executed++
            when (val effect = rule.effect) {
                is Message -> {
                    say(effect.text)
                    message = true
                }
                is OpenExit -> state.exits[effect.room][effect.direction] = Exit(effect.destination)
                is MoveItem -> state.places[effect.item] = effect.place
                is SetFlag ->
                    if (effect.on) state.flags.add(effect.flag) else state.flags.remove(effect.flag)
                is Points -> state.bonus += effect.amount
            }
        }
        return RuleResult(executed, message)
    }

    fun turn(baseline: Boolean) {
        state.moves++
        val nearby = BooleanArray(items.size) { carried(it) || roomItem(it) }
        for (i in items.indices) if (state.lit[i]) {
            state.fuel[i]--
            if (state.fuel[i] == 0) {
                state.lit[i] = false
                if (nearby[i]) say("The ${items[i].name} goes out.")
            }
        }
        val lit = isLit()
        if (baseline && !lit) say("It is now pitch dark.") else if (!baseline && lit) describe(true)
        state.darkness = if (lit) 0 else state.darkness + 1
        if (state.darkness == 2) say("You hear something moving in the dark.")
        if (state.darkness == 3) state.ended = EndStatus.DEAD
        val treasure = treasures()
        if (
            state.ended == EndStatus.PLAYING &&
                treasure.total > 0 &&
                treasure.stored == treasure.total
        )
            state.ended = EndStatus.WON
        if (state.ended != EndStatus.PLAYING) {
            say(
                if (state.ended == EndStatus.DEAD) "*** You have died ***"
                else "*** You have won ***",
            )
            say("You scored ${treasure.points + state.bonus} points in ${state.moves} moves.")
        }
    }

    fun requireContainer(item: Int) {
        if (items[item].capacity == 0) fail("The ${items[item].name} is not a container.")
        if (state.containers[item] != ContainerState.OPEN)
            fail("The ${items[item].name} is closed.")
    }

    fun putItem(item: Int, container: Int) {
        if (within(container, item))
            fail("The ${items[container].name} is inside the ${items[item].name}.")
        if (state.places[item] == inside(container))
            fail("The ${items[item].name} is already in the ${items[container].name}.")
        val weight =
            placeWeight(inside(container)) + if (within(item, container)) 0 else totalWeight(item)
        if (weight > items[container].capacity)
            fail("The ${items[item].name} doesn't fit in the ${items[container].name}.")
        state.places[item] = inside(container)
    }

    fun take(target: List<String>, from: List<String>): Boolean {
        if (!isLit()) fail("It is pitch dark.")
        val container = if (from.isEmpty()) null else resolve(from).also { requireContainer(it) }
        val source = container?.let(::inside) ?: floor()
        if (all(target)) {
            val candidates = direct(source).filter { !items[it].fixed }
            if (candidates.isEmpty())
                fail(
                    if (container == null) "There is nothing here to take."
                    else "There is nothing in the ${items[container].name} to take.",
                )
            var taken = false
            for (item in candidates) {
                if (!carried(item) && placeWeight(player) + totalWeight(item) > maxWeight)
                    say("${items[item].name}: You can't carry any more.")
                else {
                    state.places[item] = player
                    say("${items[item].name}: Taken.")
                    taken = true
                }
            }
            return taken
        }
        val item = resolve(target)
        if (container != null && state.places[item] != source)
            fail("The ${items[item].name} is not in the ${items[container].name}.")
        if (state.places[item] == player) fail("You already have the ${items[item].name}.")
        if (items[item].fixed) fail("The ${items[item].name} is fixed in place.")
        if (!carried(item) && placeWeight(player) + totalWeight(item) > maxWeight)
            fail("You can't carry any more.")
        state.places[item] = player
        say("Taken.")
        return true
    }

    fun drop(target: List<String>) {
        if (all(target)) {
            val candidates = direct(player)
            if (candidates.isEmpty()) fail("You are empty-handed.")
            for (item in candidates) {
                state.places[item] = floor()
                say("${items[item].name}: Dropped.")
            }
        } else {
            val item = resolve(target)
            if (!carried(item)) fail("You aren't carrying the ${items[item].name}.")
            state.places[item] = floor()
            say("Dropped.")
        }
    }

    fun put(first: List<String>, second: List<String>): Boolean {
        val item = if (all(first)) null else resolve(first)
        val container = resolve(second)
        if (item != null) {
            if (!carried(item)) fail("You aren't carrying the ${items[item].name}.")
            if (item == container) fail("You can't put the ${items[item].name} inside itself.")
        }
        requireContainer(container)
        if (item != null) {
            putItem(item, container)
            say("You put the ${items[item].name} in the ${items[container].name}.")
            return true
        }
        val candidates = direct(player).filter { it != container }
        if (candidates.isEmpty()) fail("You have nothing to put in the ${items[container].name}.")
        var moved = false
        for (candidate in candidates) {
            val message =
                try {
                    putItem(candidate, container)
                    moved = true
                    "Done."
                } catch (failure: CommandFailure) {
                    failure.message.orEmpty()
                }
            say("${items[candidate].name}: $message")
        }
        return moved
    }

    fun keyCheck(key: Int, phrase: List<String>) {
        if (phrase.isEmpty()) {
            if (!carried(key)) fail("You don't have the right key.")
            say("(with the ${items[key].name})")
        } else {
            val item = resolve(phrase)
            if (!carried(item)) fail("You aren't carrying the ${items[item].name}.")
            if (item != key) fail("The ${items[item].name} doesn't fit.")
        }
    }

    fun changeLock(target: List<String>, keyPhrase: List<String>, locking: Boolean) {
        val d = if (target.size == 1) direction(target[0]) else -1
        val status = if (locking) "already locked" else "not locked"
        if (d >= 0) {
            val exit = state.exits[state.room][d] ?: fail("There is no exit ${directions[d]}.")
            val key = exit.key ?: fail("The way ${directions[d]} has no lock.")
            if (exit.locked == locking) fail("The way ${directions[d]} is $status.")
            keyCheck(key, keyPhrase)
            state.exits[state.room][d] = exit.copy(locked = locking)
            val opposite = state.exits[exit.destination][d xor 1]
            if (opposite != null && opposite.destination == state.room && opposite.key == key)
                state.exits[exit.destination][d xor 1] = opposite.copy(locked = locking)
        } else {
            val item = resolve(target)
            val key = items[item].key
            if (items[item].capacity == 0 || key == null)
                fail("The ${items[item].name} has no lock.")
            if ((state.containers[item] == ContainerState.LOCKED) == locking)
                fail("The ${items[item].name} is $status.")
            if (locking && state.containers[item] == ContainerState.OPEN)
                fail("You must close the ${items[item].name} first.")
            keyCheck(key, keyPhrase)
            state.containers[item] = if (locking) ContainerState.LOCKED else ContainerState.CLOSED
        }
        say(if (locking) "Locked." else "Unlocked.")
    }

    fun examine(item: Int) {
        if (items[item].details.isEmpty())
            say("You see nothing special about the ${items[item].name}.")
        else output.addAll(items[item].details)
        if (items[item].light)
            say("It is ${if (state.lit[item]) "lit" else "unlit"} (fuel ${state.fuel[item]}).")
        if (items[item].capacity > 0)
            when (state.containers[item]) {
                ContainerState.LOCKED -> say("It is locked.")
                ContainerState.CLOSED -> say("It is closed.")
                ContainerState.OPEN ->
                    if (direct(inside(item)).isEmpty()) say("It is empty.")
                    else {
                        say("It contains:")
                        itemTree(inside(item), 1)
                    }
            }
        if (items[item].treasure > 0) say("It is a treasure worth ${items[item].treasure} points.")
        say("It weighs ${totalWeight(item)}.")
    }

    fun execute(verb: Verb, first: List<String>, second: List<String>, d: Int) {
        var baseline = isLit()
        var success = true
        when (verb) {
            Verb.GO -> {
                val exit = state.exits[state.room][d] ?: fail("You can't go that way.")
                if (exit.locked) fail("The way ${directions[d]} is locked.")
                state.room = exit.destination
                baseline = isLit()
                describe(verbose || !state.visited[state.room])
                state.visited[state.room] = true
                runRules(Trigger.onEnter(state.room))
            }
            Verb.LOOK -> describe(true)
            Verb.EXAMINE -> examine(resolve(first))
            Verb.TAKE -> success = take(first, second)
            Verb.DROP -> drop(first)
            Verb.PUT -> success = put(first, second)
            Verb.INVENTORY -> {
                if (direct(player).isEmpty()) say("You are empty-handed.")
                else {
                    say("You are carrying:")
                    itemTree(player, 1)
                    say("Total weight: ${placeWeight(player)}/$maxWeight")
                }
            }
            Verb.OPEN -> {
                val item = resolve(first)
                if (items[item].capacity == 0) fail("You can't open the ${items[item].name}.")
                if (state.containers[item] == ContainerState.OPEN)
                    fail("The ${items[item].name} is already open.")
                if (state.containers[item] == ContainerState.LOCKED)
                    fail("The ${items[item].name} is locked.")
                state.containers[item] = ContainerState.OPEN
                val children = direct(inside(item))
                say(
                    if (children.isEmpty()) "Opened."
                    else "Opening the ${items[item].name} reveals ${names(children)}.",
                )
            }
            Verb.CLOSE -> {
                val item = resolve(first)
                if (items[item].capacity == 0) fail("You can't close the ${items[item].name}.")
                if (state.containers[item] != ContainerState.OPEN)
                    fail("The ${items[item].name} is already closed.")
                state.containers[item] = ContainerState.CLOSED
                say("Closed.")
            }
            Verb.LOCK,
            Verb.UNLOCK -> changeLock(first, second, verb == Verb.LOCK)
            Verb.USE -> {
                val a = resolve(first)
                val b = resolve(second)
                if (!carried(a)) fail("You aren't carrying the ${items[a].name}.")
                val result = runRules(Trigger.onUse(a, b))
                if (result.executed == 0) fail("Nothing happens.")
                if (!result.message) say("Done.")
            }
            Verb.LIGHT,
            Verb.EXTINGUISH -> {
                val item = resolve(first)
                val lighting = verb == Verb.LIGHT
                if (!items[item].light) fail("You can't ${verb.text} the ${items[item].name}.")
                if (state.lit[item] == lighting)
                    fail(
                        "The ${items[item].name} is ${if (lighting) "already lit" else "not lit"}.",
                    )
                if (lighting && state.fuel[item] == 0) fail("The ${items[item].name} has no fuel.")
                state.lit[item] = lighting
                say("The ${items[item].name} is now ${if (lighting) "lit" else "out"}.")
            }
            Verb.WAIT -> say("Time passes.")
            Verb.SCORE -> {
                val treasure = treasures()
                say(
                    "You have scored ${treasure.points + state.bonus} points (treasure ${treasure.points}, bonus ${state.bonus}) in ${state.moves} moves.",
                )
                say("Treasures stored: ${treasure.stored} of ${treasure.total}.")
            }
            Verb.SAVE -> {
                saved = State(state)
                say("Game saved.")
            }
            Verb.RESTORE -> {
                state = State(saved ?: fail("There is no saved game."))
                say("Game restored.")
                describe(true)
            }
            Verb.VERBOSE -> {
                verbose = true
                say("Verbose mode.")
            }
            Verb.BRIEF -> {
                verbose = false
                say("Brief mode.")
            }
        }
        if (success && verb.action()) turn(baseline)
    }

    fun interpret(input: List<String>) {
        if (input.isEmpty()) fail("I beg your pardon?")
        val directionWord = direction(input[0]) >= 0
        var verb =
            if (directionWord) Verb.GO
            else Verb.parse(input[0]) ?: fail("I don't know the verb \"${input[0]}\".")
        if (state.ended != EndStatus.PLAYING && verb != Verb.RESTORE) fail("The game is over.")
        var first = input.drop(if (directionWord) 0 else 1)
        var second = emptyList<String>()
        var d = -1
        if (verb == Verb.LOOK && first.isNotEmpty()) {
            if (first[0] != "at") fail("I don't understand that.")
            verb = Verb.EXAMINE
            first = first.drop(1)
        }
        if (verb.noArguments()) {
            if (first.isNotEmpty()) fail("I don't understand that.")
        } else {
            if (first.isEmpty())
                fail(
                    if (verb == Verb.GO) "Which way do you want to go?"
                    else "What do you want to ${verb.text}?",
                )
            if (verb == Verb.GO) {
                if (first.size == 1) d = direction(first[0])
                if (d < 0) fail("I don't understand that.")
            } else {
                val split = first.indexOfFirst { word ->
                    when (verb) {
                        Verb.PUT -> word == "in" || word == "into"
                        Verb.USE -> word == "on" || word == "with"
                        Verb.LOCK,
                        Verb.UNLOCK -> word == "with"
                        Verb.TAKE -> word == "from"
                        else -> false
                    }
                }
                if (split >= 0) {
                    if (split == 0 || split + 1 == first.size) fail("I don't understand that.")
                    second = first.drop(split + 1)
                    first = first.take(split)
                } else if (verb == Verb.PUT || verb == Verb.USE) fail("I don't understand that.")
            }
        }
        execute(verb, first, second, d)
    }

    fun process(line: String) {
        say("> $line")
        try {
            var input = words(line)
            if (input.isNotEmpty() && (input[0] == "again" || input[0] == "g")) {
                if (input.size != 1) fail("I don't understand that.")
                input = words(previous ?: fail("There is nothing to repeat."))
            } else previous = line
            interpret(input)
        } catch (failure: CommandFailure) {
            say(failure.message.orEmpty())
        }
    }

    fun flush(writer: Writer) {
        for (line in output) {
            writer.write(line)
            writer.write("\n")
        }
        output.clear()
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val definitions = mutableListOf<List<String>>()
    while (true) {
        val line = input.readLine()
        if (line == "BEGIN") break
        definitions.add(line.split(' '))
    }
    val game = Adventure(definitions)
    val output = System.out.bufferedWriter()
    game.describe(true)
    game.flush(output)
    while (true) {
        val line = input.readLine() ?: break
        if (line == "QUIT") break
        game.process(line)
        game.flush(output)
    }
    game.say("Final score: ${game.score()} points in ${game.state.moves} moves.")
    game.flush(output)
    output.flush()
}
