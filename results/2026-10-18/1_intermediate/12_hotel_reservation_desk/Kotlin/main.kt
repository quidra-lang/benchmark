private val roomTypes = listOf("SINGLE", "DOUBLE", "SUITE")
private val weekdays = listOf("SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI")

private class Fault(message: String) : RuntimeException(message)

private fun leap(year: Int) = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
private fun months(year: Int) = listOf(
    31, if (leap(year)) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
)

private fun dateNumber(text: String): Int {
    val year = text.substring(0, 4).toInt()
    val month = text.substring(5, 7).toInt()
    val day = text.substring(8, 10).toInt()
    if (year !in 2000..2099 || month !in 1..12) throw Fault("invalid date $text")
    val lengths = months(year)
    if (day !in 1..lengths[month - 1]) throw Fault("invalid date $text")
    var result = 0
    for (y in 2000 until year) result += if (leap(y)) 366 else 365
    for (m in 0 until month - 1) result += lengths[m]
    return result + day - 1
}

private fun dateText(value: Int): String {
    var number = value
    var year = 2000
    while (number >= (if (leap(year)) 366 else 365)) {
        number -= if (leap(year)) 366 else 365
        year++
    }
    var month = 1
    for (days in months(year)) {
        if (number < days) break
        number -= days
        month++
    }
    return "%04d-%02d-%02d".format(year, month, number + 1)
}

private fun dated(day: Int) = "${dateText(day)} ${weekdays[day % 7]}"
private fun cents(text: String) = text.substringBefore('.').toLong() * 100 +
    text.substringAfter('.').toLong()
private fun money(value: Long) = "${value / 100}.${(value % 100).toString().padStart(2, '0')}"

private data class Season(val first: Int, val last: Int, val percentage: Int)
private class Room(val number: Int, val type: String, var rate: Long) {
    var clean = true
}
private data class Night(val day: Int, val room: Int, val rate: Long)
private data class Extra(val item: String, val amount: Long)
private data class Waiting(
    val id: String, val guest: String, val type: String,
    val arrival: Int, val departure: Int
)
private data class Occupied(val reservation: Reservation, val rate: Long)
private data class Bill(
    val lodging: Long, val discount: Long, val penalty: Long,
    val extras: Long, val tax: Long, val total: Long
)
private data class Daily(val available: Long, val occupied: Long, val revenue: Long) {
    operator fun plus(other: Daily) = Daily(
        available + other.available, occupied + other.occupied, revenue + other.revenue
    )
}

private class Reservation(
    val id: String, val guest: String, var room: Room, var arrival: Int,
    var departure: Int, var nights: MutableList<Night>
) {
    var status = "booked"
    val extras = mutableListOf<Extra>()
    var deposit = 0L
    var paid = 0L
    var posting: Int? = null
    var fee = 0L
    var penaltyDay: Int? = null
    var penaltyRate = 0L
    var bill: Bill? = null

    fun lodging() = nights.sumOf { it.rate }
    fun firstRate() = nights.first().rate
}

private class HotelDesk {
    private var today = dateNumber("2026-01-01")
    private val rooms = sortedMapOf<Int, Room>()
    private val seasons = mutableListOf<Season>()
    private val blocks = mutableSetOf<Pair<Int, Int>>()
    private val reservations = linkedMapOf<String, Reservation>()
    private val waitlist = mutableListOf<Waiting>()
    private val used = mutableSetOf<String>()
    private val occupied = mutableMapOf<Pair<Int, Int>, Occupied>()
    val output = mutableListOf<String>()

    private fun emit(indent: Int, vararg parts: Any) {
        output += " ".repeat(indent) + parts.joinToString(" ") { it.toString() }
    }

    private fun room(text: String) =
        rooms[text.toInt()] ?: throw Fault("unknown room $text")

    private fun checkType(type: String) {
        if (type !in roomTypes) throw Fault("invalid type $type")
    }

    private fun checkId(id: String) {
        if (id in used) throw Fault("duplicate reservation $id")
    }

    private fun reservation(id: String, status: String? = null): Reservation {
        val value = reservations[id] ?: throw Fault("unknown reservation $id")
        if (status != null && value.status != status)
            throw Fault("invalid status $id ${value.status}")
        return value
    }

    private fun stay(first: String, last: String): Pair<Int, Int> {
        val arrival = dateNumber(first)
        val departure = dateNumber(last)
        if (arrival < today) throw Fault("past date $first")
        if (departure <= arrival) throw Fault("invalid range $first $last")
        if (departure - arrival > 30) throw Fault("too long ${departure - arrival}")
        return arrival to departure
    }

    private fun period(
        first: String, last: String, past: Boolean = false, limited: Boolean = true
    ): Pair<Int, Int> {
        val start = dateNumber(first)
        val end = dateNumber(last)
        if (past && start < today) throw Fault("past date $first")
        if (end < start) throw Fault("invalid range $first $last")
        if (limited && end - start + 1 > 31)
            throw Fault("too long ${end - start + 1}")
        return start to end
    }

    private fun nightRate(room: Room, day: Int): Long {
        val percentage = seasons.asReversed().firstOrNull {
            it.first <= day && day <= it.last
        }?.percentage ?: 100
        return room.rate * percentage / 100
    }

    private fun price(room: Room, arrival: Int, departure: Int) =
        (arrival until departure).map {
            Night(it, room.number, nightRate(room, it))
        }.toMutableList()

    private fun unavailable(
        room: Room, arrival: Int, departure: Int, exceptFor: Reservation? = null
    ): Int? {
        for (day in arrival until departure) {
            val slot = day to room.number
            if (slot in blocks) return day
            val occupant = occupied[slot]
            if (occupant != null && occupant.reservation !== exceptFor) return day
        }
        return null
    }

    private fun freeRoom(
        type: String, arrival: Int, departure: Int, exceptFor: Reservation? = null
    ) = rooms.values.firstOrNull {
        it.type == type && unavailable(it, arrival, departure, exceptFor) == null
    }

    private fun inhouse(room: Room) = reservations.values.firstOrNull {
        it.room === room && it.status == "inhouse"
    }

    private fun occupy(reservation: Reservation, nights: List<Night>) {
        for (night in nights) occupied[night.day to night.room] =
            Occupied(reservation, night.rate)
    }

    private fun release(reservation: Reservation, from: Int? = null) {
        for (night in reservation.nights)
            if (from == null || night.day >= from)
                occupied.remove(night.day to night.room)
    }

    private fun create(
        id: String, guest: String, room: Room,
        arrival: Int, departure: Int, indent: Int = 0
    ) {
        val r = Reservation(id, guest, room, arrival, departure, price(room, arrival, departure))
        reservations[id] = r
        used += id
        occupy(r, r.nights)
        emit(indent, "BOOK", id, guest, "room", room.number, room.type,
             dateText(arrival), "->", dateText(departure), "nights",
             departure - arrival, "total", money(r.lodging()))
    }

    private fun guestTotal(guest: String) =
        reservations.values.filter { it.guest == guest }.sumOf { it.paid }

    private fun tier(guest: String) = when {
        guestTotal(guest) / 100 >= 2000 -> "GOLD"
        guestTotal(guest) / 100 >= 500 -> "SILVER"
        else -> "BRONZE"
    }

    private fun bill(r: Reservation): Bill {
        val lodging = r.lodging()
        val percentage = when (tier(r.guest)) {
            "GOLD" -> 10
            "SILVER" -> 5
            else -> 0
        }
        val discount = lodging * percentage / 100
        val extras = r.extras.sumOf { it.amount }
        val subtotal = lodging - discount + r.penaltyRate + extras
        val tax = subtotal / 10
        return Bill(lodging, discount, r.penaltyRate, extras, tax, subtotal + tax)
    }

    private fun deposit(r: Reservation, amount: Long) = if (amount >= r.deposit) {
        "deposit ${money(r.deposit)} due ${money(amount - r.deposit)}"
    } else {
        "deposit ${money(r.deposit)} refund ${money(r.deposit - amount)}"
    }

    private fun checkout(r: Reservation, day: Int, indent: Int = 0) {
        if (day < r.departure) {
            val penalty = r.nights.first { it.day == day }
            r.penaltyDay = day
            r.penaltyRate = penalty.rate
            release(r, day)
            r.nights.removeAll { it.day >= day }
            r.departure = day
        }
        val result = bill(r)
        r.bill = result
        r.paid = result.total
        r.status = "checkedout"
        r.posting = day
        r.room.clean = false
        emit(indent, "CHECKOUT", r.id, "nights", r.nights.size,
             "lodging", money(result.lodging), "discount", money(result.discount),
             "penalty", money(result.penalty), "extras", money(result.extras),
             "tax", money(result.tax), "total", money(result.total), deposit(r, result.total))
    }

    private fun processWaitlist() {
        val remaining = mutableListOf<Waiting>()
        for (entry in waitlist) {
            if (entry.arrival < today) {
                emit(2, "WAITLIST", entry.id, "expired")
            } else {
                val room = freeRoom(entry.type, entry.arrival, entry.departure)
                if (room == null)
                    remaining += entry
                else
                    create(entry.id, entry.guest, room, entry.arrival, entry.departure, 2)
            }
        }
        waitlist.clear()
        waitlist.addAll(remaining)
    }

    private fun book(t: List<String>, specific: Boolean, waiting: Boolean) {
        checkId(t[1])
        val fixedRoom = if (specific) room(t[3]) else null
        val type = fixedRoom?.type ?: t[3]
        if (!specific) checkType(type)
        val (arrival, departure) = stay(t[4], t[5])
        val selected = if (specific) {
            val found = fixedRoom!!
            val invalid = unavailable(found, arrival, departure)
            if (invalid != null)
                throw Fault("room unavailable ${t[3]} ${dateText(invalid)}")
            found
        } else freeRoom(type, arrival, departure)
        if (selected == null && !waiting)
            throw Fault("no availability $type ${t[4]} ${t[5]}")
        if (selected == null) {
            waitlist += Waiting(t[1], t[2], type, arrival, departure)
            used += t[1]
            emit(0, "WAITLIST", t[1], "queued position", waitlist.size)
        } else create(t[1], t[2], selected, arrival, departure)
    }

    private fun changeBlock(t: List<String>, blocking: Boolean) {
        val room = room(t[1])
        val (first, last) = period(t[2], t[3], past = true)
        if (blocking) {
            for (day in first..last) {
                if ((day to room.number) in occupied)
                    throw Fault("room unavailable ${t[1]} ${dateText(day)}")
            }
        }
        var changed = 0
        for (day in first..last) {
            val slot = day to room.number
            if (if (blocking) blocks.add(slot) else blocks.remove(slot)) changed++
        }
        emit(0, if (blocking) "BLOCK" else "UNBLOCK",
             t[1], t[2], "->", t[3], if (blocking) "added" else "removed", changed)
    }

    private fun advance(t: List<String>) {
        val day = dateNumber(t[1])
        if (day < today) throw Fault("past date ${t[1]}")
        emit(0, "TODAY", dated(day))
        val departing = reservations.values
            .filter { it.status == "inhouse" && it.departure < day }
            .sortedWith(compareBy<Reservation> { it.departure }.thenBy { it.id })
        for (r in departing) checkout(r, r.departure, 2)
        val absent = reservations.values
            .filter { it.status == "booked" && it.arrival < day }
            .sortedWith(compareBy<Reservation> { it.arrival }.thenBy { it.id })
        for (r in absent) {
            release(r)
            r.fee = r.firstRate()
            r.paid = r.fee
            r.status = "noshow"
            r.posting = r.arrival
            emit(2, "NOSHOW", r.id, r.guest, "fee", money(r.fee), deposit(r, r.fee))
        }
        today = day
    }

    private fun modify(t: List<String>) {
        val r = reservation(t[1], "booked")
        val (arrival, departure) = stay(t[2], t[3])
        var room = r.room
        var changed = "kept"
        if (unavailable(room, arrival, departure, r) != null) {
            room = freeRoom(room.type, arrival, departure, r)
                ?: throw Fault("no availability ${r.room.type} ${t[2]} ${t[3]}")
            changed = "reassigned"
        }
        val nights = price(room, arrival, departure)
        release(r)
        r.room = room
        r.arrival = arrival
        r.departure = departure
        r.nights = nights
        occupy(r, nights)
        emit(0, "MODIFY", t[1], "room", room.number, changed, t[2], "->", t[3],
             "nights", departure - arrival, "total", money(r.lodging()))
    }

    private fun cancel(t: List<String>) {
        val index = waitlist.indexOfFirst { it.id == t[1] }
        if (index >= 0) {
            waitlist.removeAt(index)
            emit(0, "CANCEL", t[1], "waitlist removed")
            return
        }
        val r = reservation(t[1], "booked")
        val days = r.arrival - today
        val fee = when {
            days >= 7 -> 0L
            days >= 1 -> r.firstRate() / 2
            else -> r.firstRate()
        }
        release(r)
        r.fee = fee
        r.paid = fee
        r.status = "cancelled"
        r.posting = today
        emit(0, "CANCEL", t[1], "days", days, "fee", money(fee), deposit(r, fee))
    }

    private fun checkin(t: List<String>) {
        val r = reservation(t[1], "booked")
        if (r.arrival != today)
            throw Fault("not arrival date ${t[1]} ${dateText(r.arrival)}")
        val occupant = inhouse(r.room)
        if (occupant != null)
            throw Fault("room occupied ${r.room.number} ${occupant.id}")
        if (!r.room.clean) throw Fault("room dirty ${r.room.number}")
        r.status = "inhouse"
        emit(0, "CHECKIN", t[1], r.guest, "room", r.room.number, "until", dateText(r.departure))
    }

    private fun move(t: List<String>) {
        val r = reservation(t[1], "inhouse")
        val room = room(t[2])
        val previous = r.room
        if (room === previous) throw Fault("same room ${t[2]}")
        val remaining = r.nights.filter { it.day >= today }
        if (remaining.isEmpty()) throw Fault("no remaining nights ${t[1]}")
        val invalid = unavailable(room, remaining.first().day, r.departure, r)
        if (invalid != null) throw Fault("room unavailable ${t[2]} ${dateText(invalid)}")
        val occupant = inhouse(room)
        if (occupant != null)
            throw Fault("room occupied ${t[2]} ${occupant.id}")
        if (!room.clean) throw Fault("room dirty ${t[2]}")
        release(r, today)
        r.nights = r.nights.map { n ->
            if (n.day >= today) n.copy(room = room.number) else n
        }.toMutableList()
        occupy(r, r.nights.filter { it.day >= today })
        previous.clean = false
        r.room = room
        emit(0, "MOVE", t[1], previous.number, "->", room.number, "nights", remaining.size)
    }

    private fun extend(t: List<String>) {
        val r = reservation(t[1], "inhouse")
        val departure = dateNumber(t[2])
        if (departure <= r.departure)
            throw Fault("invalid range ${dateText(r.departure)} ${t[2]}")
        if (departure - r.arrival > 30) throw Fault("too long ${departure - r.arrival}")
        val invalid = unavailable(r.room, r.departure, departure, r)
        if (invalid != null)
            throw Fault("room unavailable ${r.room.number} ${dateText(invalid)}")
        val nights = price(r.room, r.departure, departure)
        r.nights.addAll(nights)
        occupy(r, nights)
        r.departure = departure
        emit(0, "EXTEND", t[1], "until", t[2], "nights", r.nights.size,
             "total", money(r.lodging()))
    }

    private fun charge(t: List<String>) {
        val r = reservation(t[1], "inhouse")
        val amount = cents(t[2])
        if (amount == 0L) throw Fault("invalid amount")
        r.extras += Extra(t[3], amount)
        emit(0, "CHARGE", t[1], t[3], t[2], "extras",
             money(r.extras.sumOf { it.amount }))
    }

    private fun pay(t: List<String>) {
        val r = reservation(t[1])
        if (r.status != "booked" && r.status != "inhouse")
            throw Fault("invalid status ${t[1]} ${r.status}")
        val amount = cents(t[2])
        if (amount == 0L) throw Fault("invalid amount")
        r.deposit += amount
        emit(0, "PAY", t[1], t[2], "deposit", money(r.deposit))
    }

    private fun invoice(t: List<String>) {
        val r = reservation(t[1])
        emit(0, "INVOICE", t[1], r.guest, "room", r.room.number, r.room.type, r.status)
        if (r.status == "cancelled" || r.status == "noshow") {
            emit(2, if (r.status == "cancelled") "cancellation" else "noshow",
                 "fee", money(r.fee))
            emit(2, "total", money(r.fee))
            emit(2, deposit(r, r.fee))
            return
        }
        for (night in r.nights)
            emit(2, dated(night.day), "room", night.room, money(night.rate))
        val bill = if (r.status == "checkedout") r.bill!! else bill(r)
        emit(2, "lodging", money(bill.lodging))
        emit(2, "discount", money(bill.discount))
        if (r.penaltyDay != null)
            emit(2, "penalty", dated(r.penaltyDay!!), money(bill.penalty))
        for (extra in r.extras) emit(2, "extra", extra.item, money(extra.amount))
        emit(2, "tax", money(bill.tax))
        emit(2, "total", money(bill.total))
        emit(2, deposit(r, bill.total))
    }

    private fun roomNumbers(type: String? = null): List<Int> =
        rooms.values.filter { type == null || it.type == type }.map { it.number }

    private fun availability(t: List<String>) {
        checkType(t[1])
        val (start, end) = period(t[2], t[3])
        val numbers = roomNumbers(t[1])
        emit(0, "AVAIL", t[1], t[2], "->", t[3])
        for (day in start..end) {
            val free = numbers.filter { n ->
                (day to n) !in blocks && (day to n) !in occupied
            }
            emit(2, dated(day), "free", free.size, *free.map { it as Any }.toTypedArray())
        }
    }

    private fun occupancyParts(numbers: List<Int>, day: Int): String {
        val blocked = numbers.count { (day to it) in blocks }
        val sold = numbers.count { (day to it) in occupied }
        val available = numbers.size - blocked
        val rate = if (available == 0) "n/a" else "${sold * 100 / available}%"
        return "rooms ${numbers.size} blocked $blocked occupied $sold rate $rate"
    }

    private fun occupancy(t: List<String>) {
        val day = dateNumber(t[1])
        emit(0, "OCCUPANCY", dated(day), occupancyParts(roomNumbers(), day))
        for (type in roomTypes) {
            val numbers = roomNumbers(type)
            if (numbers.isNotEmpty()) emit(2, type, occupancyParts(numbers, day))
        }
    }

    private fun daily(day: Int): Daily {
        var available = 0L
        var sold = 0L
        var revenue = 0L
        for (room in rooms.values) {
            val slot = day to room.number
            if (slot !in blocks) available++
            val night = occupied[slot]
            if (night != null) {
                sold++
                revenue += night.rate
            }
        }
        return Daily(available, sold, revenue)
    }

    private fun metrics(day: Daily): String {
        val rate = if (day.available == 0L) "n/a" else "${day.occupied * 100 / day.available}%"
        val adr = if (day.occupied == 0L) "n/a" else money(day.revenue / day.occupied)
        val revpar = if (day.available == 0L) "n/a" else money(day.revenue / day.available)
        return "sold ${day.occupied}/${day.available} rate $rate revenue ${money(day.revenue)} adr $adr revpar $revpar"
    }

    private fun stats(t: List<String>) {
        val (first, last) = period(t[1], t[2])
        var total = Daily(0, 0, 0)
        emit(0, "STATS", t[1], "->", t[2])
        for (day in first..last) {
            val values = daily(day)
            total += values
            emit(2, dated(day), metrics(values))
        }
        emit(2, "total", metrics(total))
    }

    private fun showRooms() {
        emit(0, "ROOMS", dated(today), "rooms", rooms.size)
        for (room in rooms.values) {
            val occupant = inhouse(room)
            val situation = when {
                occupant != null -> "occupied ${occupant.id}"
                (today to room.number) in blocks -> "blocked"
                else -> "vacant"
            }
            var text = "${room.number} ${room.type} base ${money(room.rate)} " +
                "tonight ${money(nightRate(room, today))} ${if (room.clean) "clean" else "dirty"} $situation"
            val upcoming = reservations.values.filter {
                it.status == "booked" && it.room === room
            }.minWithOrNull(compareBy<Reservation> { it.arrival }.thenBy { it.id })
            if (upcoming != null)
                text += " next ${upcoming.id} ${dateText(upcoming.arrival)}"
            emit(2, text)
        }
    }

    private fun listReservations(t: List<String>) {
        val entries = reservations.values.filter { it.status == t[1] }
            .sortedWith(compareBy<Reservation> { it.arrival }.thenBy { it.id })
        emit(0, "LIST", t[1], entries.size)
        for (r in entries)
            emit(2, r.id, r.guest, "room", r.room.number,
                 dateText(r.arrival), "->", dateText(r.departure))
    }

    private fun showQueue() {
        emit(0, "QUEUE", waitlist.size)
        for ((i, e) in waitlist.withIndex())
            emit(2, i + 1, e.id, e.guest, e.type,
                 dateText(e.arrival), "->", dateText(e.departure))
    }

    private fun schedule(t: List<String>) {
        val day = dateNumber(t[1])
        val arrivals = reservations.values.filter {
            it.arrival == day && it.status != "cancelled"
        }.sortedBy { it.id }
        val departures = reservations.values.filter {
            it.departure == day && it.status in listOf("booked", "inhouse", "checkedout")
        }.sortedBy { it.id }
        emit(0, "SCHEDULE", dated(day), "arrivals", arrivals.size,
             "departures", departures.size)
        for (r in arrivals)
            emit(2, "arrival", r.id, r.guest, "room", r.room.number, r.status)
        for (r in departures)
            emit(2, "departure", r.id, r.guest, "room", r.room.number, r.status)
    }

    private fun guest(t: List<String>) {
        val entries = reservations.values.filter { it.guest == t[1] }
        if (entries.isEmpty()) throw Fault("unknown guest ${t[1]}")
        emit(0, "GUEST", t[1])
        for (r in entries) {
            val pending = r.status == "booked" || r.status == "inhouse"
            emit(2, r.id, "room", r.room.number, r.room.type,
                 dateText(r.arrival), "->", dateText(r.departure), r.status,
                 if (pending) "deposit" else "paid",
                 money(if (pending) r.deposit else r.paid))
        }
        val total = guestTotal(t[1])
        emit(2, "total paid", money(total), "points", total / 100, "tier", tier(t[1]))
    }

    private fun revenue(t: List<String>) {
        val (first, last) = period(t[1], t[2], limited = false)
        val posted = reservations.values.filter { it.posting != null && it.posting!! in first..last }
        val done = posted.filter { it.status == "checkedout" }
        val cancelled = posted.filter { it.status == "cancelled" }
        val absent = posted.filter { it.status == "noshow" }
        val lodging = done.sumOf { it.bill!!.lodging }
        val discount = done.sumOf { it.bill!!.discount }
        val penalty = done.sumOf { it.bill!!.penalty }
        val extras = done.sumOf { it.bill!!.extras }
        val tax = done.sumOf { it.bill!!.tax }
        val cancellations = cancelled.sumOf { it.fee }
        val noshows = absent.sumOf { it.fee }
        emit(0, "REVENUE", t[1], "->", t[2])
        for ((label, amount) in listOf(
            "lodging" to lodging, "discount" to discount, "penalty" to penalty,
            "extras" to extras, "tax" to tax, "cancellation" to cancellations,
            "noshow" to noshows
        )) emit(2, label, money(amount))
        emit(2, "total", money(lodging - discount + penalty + extras + tax + cancellations + noshows))
        emit(2, "checkouts", done.size, "cancellations", cancelled.size, "noshows", absent.size)
    }

    private fun run(t: List<String>) {
        when (t[0]) {
            "ROOM" -> {
                val number = t[1].toInt()
                if (number in rooms) throw Fault("duplicate room ${t[1]}")
                checkType(t[2])
                rooms[number] = Room(number, t[2], cents(t[3]))
                emit(0, "ROOM", t[1], t[2], t[3])
            }
            "RATE" -> {
                val room = room(t[1])
                val previous = room.rate
                room.rate = cents(t[2])
                emit(0, "RATE", t[1], money(previous), "->", t[2])
            }
            "SEASON" -> {
                val (first, last) = period(t[1], t[2], limited = false)
                seasons += Season(first, last, t[3].toInt())
                emit(0, "SEASON", seasons.size, t[1], "->", t[2], "${t[3]}%")
            }
            "BLOCK" -> changeBlock(t, true)
            "UNBLOCK" -> changeBlock(t, false)
            "CLEAN" -> {
                val room = room(t[1])
                if (room.clean) throw Fault("already clean ${t[1]}")
                room.clean = true
                emit(0, "CLEAN", t[1])
            }
            "TODAY" -> advance(t)
            "BOOK" -> book(t, false, false)
            "BOOKROOM" -> book(t, true, false)
            "WAITLIST" -> book(t, false, true)
            "MODIFY" -> modify(t)
            "CANCEL" -> cancel(t)
            "CHECKIN" -> checkin(t)
            "MOVE" -> move(t)
            "EXTEND" -> extend(t)
            "CHARGE" -> charge(t)
            "PAY" -> pay(t)
            "CHECKOUT" -> checkout(reservation(t[1], "inhouse"), today)
            "INVOICE" -> invoice(t)
            "AVAIL" -> availability(t)
            "OCCUPANCY" -> occupancy(t)
            "STATS" -> stats(t)
            "ROOMS" -> showRooms()
            "LIST" -> listReservations(t)
            "QUEUE" -> showQueue()
            "SCHEDULE" -> schedule(t)
            "GUEST" -> guest(t)
            "REVENUE" -> revenue(t)
        }
    }

    fun process(line: String) {
        try {
            run(line.split(' '))
        } catch (fault: Fault) {
            emit(0, "ERROR", fault.message ?: "")
        }
        processWaitlist()
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val hotel = HotelDesk()
    repeat(input.readLine().toInt()) { hotel.process(input.readLine()) }
    val output = System.out.bufferedWriter()
    for (line in hotel.output) {
        output.write(line)
        output.newLine()
    }
    output.flush()
}
