using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

sealed class CommandError : Exception
{
    public CommandError(string message) : base(message) { }
}

sealed class Room
{
    public int Number { get; }
    public string Kind { get; }
    public long Rate { get; set; }
    public bool Clean { get; set; } = true;

    public Room(int number, string kind, long rate)
    {
        Number = number;
        Kind = kind;
        Rate = rate;
    }
}

sealed record Season(int Start, int End, int Percentage);

sealed class Night
{
    public int Day { get; }
    public int Room { get; set; }
    public long Rate { get; }

    public Night(int day, int room, long rate)
    {
        Day = day;
        Room = room;
        Rate = rate;
    }
}

sealed record Charge(string Item, long Amount);

sealed record Bill(long Lodging, long Discount, long Penalty, long Extras,
                   long Tax, long Total);

sealed class Reservation
{
    public string Id { get; }
    public string Guest { get; }
    public Room Room { get; set; }
    public int Arrival { get; set; }
    public int Departure { get; set; }
    public List<Night> Nights { get; set; }
    public string Status { get; set; } = "booked";
    public List<Charge> Extras { get; } = new();
    public long Deposit { get; set; }
    public long Paid { get; set; }
    public int? Posting { get; set; }
    public long Fee { get; set; }
    public (int Day, long Rate)? Penalty { get; set; }
    public Bill? FinalBill { get; set; }

    public Reservation(string id, string guest, Room room, int arrival,
                       int departure, List<Night> nights)
    {
        Id = id;
        Guest = guest;
        Room = room;
        Arrival = arrival;
        Departure = departure;
        Nights = nights;
    }

    public long Lodging() => Nights.Sum(night => night.Rate);
    public long FirstRate() => Nights[0].Rate;
}

sealed record WaitingEntry(string Id, string Guest, string Kind, int Arrival, int Departure);

sealed class HotelDesk
{
    private static readonly string[] RoomTypes = { "SINGLE", "DOUBLE", "SUITE" };
    private static readonly string[] Weekdays = { "SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI" };
    private static readonly int[] NormalMonths = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    private readonly SortedDictionary<int, Room> rooms = new();
    private readonly List<Season> seasons = new();
    private readonly HashSet<(int Day, int Room)> blocks = new();
    private readonly Dictionary<(int Day, int Room), (Reservation Reservation, long Rate)> occupied = new();
    private readonly Dictionary<string, Reservation> reservationsById = new();
    private readonly List<Reservation> reservations = new();
    private readonly List<WaitingEntry> waitlist = new();
    private readonly HashSet<string> usedIds = new();
    private readonly List<string> output = new();
    private int today = DateNumber("2026-01-01");

    public IReadOnlyList<string> Output => output;

    private static bool Leap(int year)
        => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

    private static int DaysInMonth(int year, int month)
        => month == 2 && Leap(year) ? 29 : NormalMonths[month - 1];

    private static int DaysInYear(int year) => Leap(year) ? 366 : 365;

    private static int DateNumber(string text)
    {
        int year = int.Parse(text.Substring(0, 4), CultureInfo.InvariantCulture);
        int month = int.Parse(text.Substring(5, 2), CultureInfo.InvariantCulture);
        int day = int.Parse(text.Substring(8, 2), CultureInfo.InvariantCulture);
        if (year < 2000 || year > 2099 || month < 1 || month > 12 ||
            day < 1 || day > DaysInMonth(year, month))
            throw new CommandError("invalid date " + text);

        int number = 0;
        for (int previous = 2000; previous < year; ++previous)
            number += DaysInYear(previous);
        for (int priorMonth = 1; priorMonth < month; ++priorMonth)
            number += DaysInMonth(year, priorMonth);
        return number + day - 1;
    }

    private static string DateText(int number)
    {
        int year = 2000;
        while (number >= DaysInYear(year))
        {
            number -= DaysInYear(year);
            ++year;
        }
        int month = 1;
        while (number >= DaysInMonth(year, month))
        {
            number -= DaysInMonth(year, month);
            ++month;
        }
        return $"{year:D4}-{month:D2}-{number + 1:D2}";
    }

    private static string DateWeekday(int day)
        => DateText(day) + " " + Weekdays[day % 7];

    private static long Cents(string amount)
    {
        int point = amount.IndexOf('.');
        return long.Parse(amount.Substring(0, point), CultureInfo.InvariantCulture) * 100
               + long.Parse(amount.Substring(point + 1), CultureInfo.InvariantCulture);
    }

    private static string Money(long amount)
        => $"{amount / 100}.{amount % 100:00}";

    private void Emit(params object[] parts)
        => output.Add(string.Join(" ", parts));

    private void EmitIndented(params object[] parts)
        => output.Add("  " + string.Join(" ", parts));

    private Room RequireRoom(string text)
    {
        int number = int.Parse(text, CultureInfo.InvariantCulture);
        if (!rooms.TryGetValue(number, out Room? room))
            throw new CommandError("unknown room " + text);
        return room;
    }

    private static void RequireType(string kind)
    {
        if (!RoomTypes.Contains(kind))
            throw new CommandError("invalid type " + kind);
    }

    private void RequireUnused(string id)
    {
        if (usedIds.Contains(id))
            throw new CommandError("duplicate reservation " + id);
    }

    private Reservation RequireReservation(string id, string? status = null)
    {
        if (!reservationsById.TryGetValue(id, out Reservation? reservation))
            throw new CommandError("unknown reservation " + id);
        if (status != null && reservation.Status != status)
            throw new CommandError($"invalid status {id} {reservation.Status}");
        return reservation;
    }

    private (int Arrival, int Departure) Stay(string first, string last)
    {
        int arrival = DateNumber(first);
        int departure = DateNumber(last);
        if (arrival < today)
            throw new CommandError("past date " + first);
        if (departure <= arrival)
            throw new CommandError($"invalid range {first} {last}");
        if (departure - arrival > 30)
            throw new CommandError("too long " + (departure - arrival));
        return (arrival, departure);
    }

    private (int Start, int End) Period(string first, string last,
                                         bool pastRestricted = false, bool limited = true)
    {
        int start = DateNumber(first);
        int end = DateNumber(last);
        if (pastRestricted && start < today)
            throw new CommandError("past date " + first);
        if (end < start)
            throw new CommandError($"invalid range {first} {last}");
        if (limited && end - start + 1 > 31)
            throw new CommandError("too long " + (end - start + 1));
        return (start, end);
    }

    private long NightRate(Room room, int day)
    {
        int percentage = 100;
        for (int i = seasons.Count - 1; i >= 0; --i)
        {
            Season season = seasons[i];
            if (season.Start <= day && day <= season.End)
            {
                percentage = season.Percentage;
                break;
            }
        }
        return room.Rate * percentage / 100;
    }

    private List<Night> Price(Room room, int arrival, int departure)
    {
        List<Night> nights = new();
        for (int day = arrival; day < departure; ++day)
            nights.Add(new Night(day, room.Number, NightRate(room, day)));
        return nights;
    }

    private int? FirstUnavailable(Room room, int arrival, int departure,
                                  Reservation? exceptFor = null)
    {
        for (int day = arrival; day < departure; ++day)
        {
            var key = (day, room.Number);
            if (blocks.Contains(key))
                return day;
            if (occupied.TryGetValue(key, out var holder) &&
                !ReferenceEquals(holder.Reservation, exceptFor))
                return day;
        }
        return null;
    }

    private Room? FreeRoom(string kind, int arrival, int departure,
                           Reservation? exceptFor = null)
    {
        foreach (Room room in rooms.Values)
            if (room.Kind == kind &&
                FirstUnavailable(room, arrival, departure, exceptFor) == null)
                return room;
        return null;
    }

    private Reservation? Inhouse(Room room)
        => reservations.FirstOrDefault(r => r.Status == "inhouse" &&
                                            ReferenceEquals(r.Room, room));

    private void Occupy(Reservation reservation, IEnumerable<Night> nights)
    {
        foreach (Night night in nights)
            occupied[(night.Day, night.Room)] = (reservation, night.Rate);
    }

    private void Release(Reservation reservation, int? first = null)
    {
        foreach (Night night in reservation.Nights)
            if (first == null || night.Day >= first)
                occupied.Remove((night.Day, night.Room));
    }

    private void CreateReservation(string id, string guest, Room room,
                                   int arrival, int departure, bool indented = false)
    {
        var booking = new Reservation(id, guest, room, arrival, departure,
                                      Price(room, arrival, departure));
        reservationsById.Add(id, booking);
        reservations.Add(booking);
        usedIds.Add(id);
        object[] message = {
            "BOOK", id, guest, "room", room.Number, room.Kind,
            DateText(arrival), "->", DateText(departure),
            "nights", departure - arrival, "total", Money(booking.Lodging())
        };
        if (indented)
            EmitIndented(message);
        else
            Emit(message);
    }

    private long GuestTotal(string guest)
        => reservations.Where(r => r.Guest == guest).Sum(r => r.Paid);

    private string Tier(string guest)
    {
        long points = GuestTotal(guest) / 100;
        return points >= 2000 ? "GOLD" : points >= 500 ? "SILVER" : "BRONZE";
    }

    private Bill CalculateBill(Reservation reservation)
    {
        long lodging = reservation.Lodging();
        int percentage = Tier(reservation.Guest) switch
        {
            "GOLD" => 10,
            "SILVER" => 5,
            _ => 0
        };
        long discount = lodging * percentage / 100;
        long penalty = reservation.Penalty?.Rate ?? 0;
        long extras = reservation.Extras.Sum(charge => charge.Amount);
        long subtotal = lodging - discount + penalty + extras;
        long tax = subtotal / 10;
        return new Bill(lodging, discount, penalty, extras, tax, subtotal + tax);
    }

    private static string DepositText(Reservation reservation, long total)
        => total >= reservation.Deposit
            ? $"deposit {Money(reservation.Deposit)} due {Money(total - reservation.Deposit)}"
            : $"deposit {Money(reservation.Deposit)} refund {Money(reservation.Deposit - total)}";

    private void Checkout(Reservation reservation, int day, bool indented = false)
    {
        if (day < reservation.Departure)
        {
            long penaltyRate = reservation.Nights.First(night => night.Day == day).Rate;
            reservation.Penalty = (day, penaltyRate);
            Release(reservation, day);
            reservation.Nights = reservation.Nights.Where(night => night.Day < day).ToList();
            reservation.Departure = day;
        }
        Bill bill = CalculateBill(reservation);
        reservation.FinalBill = bill;
        reservation.Paid = bill.Total;
        reservation.Status = "checkedout";
        reservation.Posting = day;
        reservation.Room.Clean = false;
        string message = $"CHECKOUT {reservation.Id} nights {reservation.Nights.Count} " +
                         $"lodging {Money(bill.Lodging)} discount {Money(bill.Discount)} " +
                         $"penalty {Money(bill.Penalty)} extras {Money(bill.Extras)} " +
                         $"tax {Money(bill.Tax)} total {Money(bill.Total)} " +
                         DepositText(reservation, bill.Total);
        if (indented)
            EmitIndented(message);
        else
            Emit(message);
    }

    private void ProcessWaitlist()
    {
        List<WaitingEntry> remaining = new();
        foreach (WaitingEntry entry in waitlist)
        {
            if (entry.Arrival < today)
            {
                EmitIndented("WAITLIST", entry.Id, "expired");
                continue;
            }
            Room? room = FreeRoom(entry.Kind, entry.Arrival, entry.Departure);
            if (room == null)
                remaining.Add(entry);
            else
                CreateReservation(entry.Id, entry.Guest, room, entry.Arrival, entry.Departure, true);
        }
        waitlist.Clear();
        waitlist.AddRange(remaining);
    }

    private void CmdRoom(string number, string kind, string amount)
    {
        int value = int.Parse(number, CultureInfo.InvariantCulture);
        if (rooms.ContainsKey(value))
            throw new CommandError("duplicate room " + number);
        RequireType(kind);
        rooms.Add(value, new Room(value, kind, Cents(amount)));
        Emit("ROOM", number, kind, amount);
    }

    private void CmdRate(string number, string amount)
    {
        Room room = RequireRoom(number);
        long previous = room.Rate;
        room.Rate = Cents(amount);
        Emit("RATE", number, Money(previous), "->", amount);
    }

    private void CmdSeason(string first, string last, string percent)
    {
        var (start, end) = Period(first, last, limited: false);
        seasons.Add(new Season(start, end, int.Parse(percent, CultureInfo.InvariantCulture)));
        Emit("SEASON", seasons.Count, first, "->", last, percent + "%");
    }

    private void CmdBlock(string number, string first, string last)
    {
        Room room = RequireRoom(number);
        var (start, end) = Period(first, last, pastRestricted: true);
        for (int day = start; day <= end; ++day)
            if (occupied.ContainsKey((day, room.Number)))
                throw new CommandError($"room unavailable {number} {DateText(day)}");
        int added = 0;
        for (int day = start; day <= end; ++day)
            if (blocks.Add((day, room.Number))) ++added;
        Emit("BLOCK", number, first, "->", last, "added", added);
    }

    private void CmdUnblock(string number, string first, string last)
    {
        Room room = RequireRoom(number);
        var (start, end) = Period(first, last, pastRestricted: true);
        int removed = 0;
        for (int day = start; day <= end; ++day)
            if (blocks.Remove((day, room.Number))) ++removed;
        Emit("UNBLOCK", number, first, "->", last, "removed", removed);
    }

    private void CmdClean(string number)
    {
        Room room = RequireRoom(number);
        if (room.Clean)
            throw new CommandError("already clean " + number);
        room.Clean = true;
        Emit("CLEAN", number);
    }

    private void CmdToday(string text)
    {
        int day = DateNumber(text);
        if (day < today)
            throw new CommandError("past date " + text);
        Emit("TODAY", DateWeekday(day));
        foreach (Reservation r in reservations
                     .Where(r => r.Status == "inhouse" && r.Departure < day)
                     .OrderBy(r => r.Departure).ThenBy(r => r.Id, StringComparer.Ordinal)
                     .ToList())
            Checkout(r, r.Departure, true);

        foreach (Reservation r in reservations
                     .Where(r => r.Status == "booked" && r.Arrival < day)
                     .OrderBy(r => r.Arrival).ThenBy(r => r.Id, StringComparer.Ordinal)
                     .ToList())
        {
            Release(r);
            r.Fee = r.FirstRate();
            r.Paid = r.Fee;
            r.Status = "noshow";
            r.Posting = r.Arrival;
            EmitIndented($"NOSHOW {r.Id} {r.Guest} fee {Money(r.Fee)} {DepositText(r, r.Fee)}");
        }
        today = day;
    }

    private void CmdBook(string id, string guest, string kind, string first, string last)
    {
        RequireUnused(id);
        RequireType(kind);
        var (arrival, departure) = Stay(first, last);
        Room? room = FreeRoom(kind, arrival, departure);
        if (room == null)
            throw new CommandError($"no availability {kind} {first} {last}");
        CreateReservation(id, guest, room, arrival, departure);
    }

    private void CmdBookroom(string id, string guest, string number, string first, string last)
    {
        RequireUnused(id);
        Room room = RequireRoom(number);
        var (arrival, departure) = Stay(first, last);
        int? unavailable = FirstUnavailable(room, arrival, departure);
        if (unavailable != null)
            throw new CommandError($"room unavailable {number} {DateText(unavailable.Value)}");
        CreateReservation(id, guest, room, arrival, departure);
    }

    private void CmdWaitlist(string id, string guest, string kind, string first, string last)
    {
        RequireUnused(id);
        RequireType(kind);
        var (arrival, departure) = Stay(first, last);
        Room? room = FreeRoom(kind, arrival, departure);
        if (room != null)
            CreateReservation(id, guest, room, arrival, departure);
        else
        {
            waitlist.Add(new WaitingEntry(id, guest, kind, arrival, departure));
            usedIds.Add(id);
            Emit("WAITLIST", id, "queued position", waitlist.Count);
        }
    }

    private void CmdModify(string id, string first, string last)
    {
        Reservation booking = RequireReservation(id, "booked");
        var (arrival, departure) = Stay(first, last);
        Room room = booking.Room;
        string choice = "kept";
        if (FirstUnavailable(room, arrival, departure, booking) != null)
        {
            Room? alternate = FreeRoom(room.Kind, arrival, departure, booking);
            if (alternate == null)
                throw new CommandError($"no availability {room.Kind} {first} {last}");
            room = alternate;
            choice = "reassigned";
        }
        List<Night> nights = Price(room, arrival, departure);
        Release(booking);
        booking.Room = room;
        booking.Arrival = arrival;
        booking.Departure = departure;
        booking.Nights = nights;
        Occupy(booking, nights);
        Emit("MODIFY", id, "room", room.Number, choice, first, "->", last,
             "nights", departure - arrival, "total", Money(booking.Lodging()));
    }

    private void CmdCancel(string id)
    {
        int position = waitlist.FindIndex(entry => entry.Id == id);
        if (position >= 0)
        {
            waitlist.RemoveAt(position);
            Emit("CANCEL", id, "waitlist removed");
            return;
        }
        Reservation booking = RequireReservation(id, "booked");
        int days = booking.Arrival - today;
        long firstRate = booking.FirstRate();
        long fee = days >= 7 ? 0 : days >= 1 ? firstRate / 2 : firstRate;
        Release(booking);
        booking.Fee = fee;
        booking.Paid = fee;
        booking.Status = "cancelled";
        booking.Posting = today;
        Emit($"CANCEL {id} days {days} fee {Money(fee)} {DepositText(booking, fee)}");
    }

    private void CmdCheckin(string id)
    {
        Reservation booking = RequireReservation(id, "booked");
        if (booking.Arrival != today)
            throw new CommandError($"not arrival date {id} {DateText(booking.Arrival)}");
        Reservation? occupant = Inhouse(booking.Room);
        if (occupant != null)
            throw new CommandError($"room occupied {booking.Room.Number} {occupant.Id}");
        if (!booking.Room.Clean)
            throw new CommandError($"room dirty {booking.Room.Number}");
        booking.Status = "inhouse";
        Emit("CHECKIN", id, booking.Guest, "room", booking.Room.Number,
             "until", DateText(booking.Departure));
    }

    private void CmdMove(string id, string number)
    {
        Reservation booking = RequireReservation(id, "inhouse");
        Room room = RequireRoom(number);
        Room previous = booking.Room;
        if (ReferenceEquals(room, previous))
            throw new CommandError("same room " + number);
        List<Night> remaining = booking.Nights.Where(night => night.Day >= today).ToList();
        if (remaining.Count == 0)
            throw new CommandError("no remaining nights " + id);
        int? unavailable = FirstUnavailable(room, remaining[0].Day, booking.Departure, booking);
        if (unavailable != null)
            throw new CommandError($"room unavailable {number} {DateText(unavailable.Value)}");
        Reservation? occupant = Inhouse(room);
        if (occupant != null)
            throw new CommandError($"room occupied {number} {occupant.Id}");
        if (!room.Clean)
            throw new CommandError("room dirty " + number);
        Release(booking, today);
        foreach (Night night in remaining)
            night.Room = room.Number;
        Occupy(booking, remaining);
        previous.Clean = false;
        booking.Room = room;
        Emit("MOVE", id, previous.Number, "->", room.Number, "nights", remaining.Count);
    }

    private void CmdExtend(string id, string text)
    {
        Reservation booking = RequireReservation(id, "inhouse");
        int departure = DateNumber(text);
        if (departure <= booking.Departure)
            throw new CommandError($"invalid range {DateText(booking.Departure)} {text}");
        if (departure - booking.Arrival > 30)
            throw new CommandError("too long " + (departure - booking.Arrival));
        int? unavailable = FirstUnavailable(booking.Room, booking.Departure, departure, booking);
        if (unavailable != null)
            throw new CommandError($"room unavailable {booking.Room.Number} {DateText(unavailable.Value)}");
        List<Night> nights = Price(booking.Room, booking.Departure, departure);
        booking.Nights.AddRange(nights);
        Occupy(booking, nights);
        booking.Departure = departure;
        Emit("EXTEND", id, "until", text, "nights", booking.Nights.Count,
             "total", Money(booking.Lodging()));
    }

    private void CmdCharge(string id, string amount, string item)
    {
        Reservation booking = RequireReservation(id, "inhouse");
        long value = Cents(amount);
        if (value == 0)
            throw new CommandError("invalid amount");
        booking.Extras.Add(new Charge(item, value));
        Emit("CHARGE", id, item, amount, "extras",
             Money(booking.Extras.Sum(charge => charge.Amount)));
    }

    private void CmdPay(string id, string amount)
    {
        Reservation booking = RequireReservation(id);
        if (booking.Status is not ("booked" or "inhouse"))
            throw new CommandError($"invalid status {id} {booking.Status}");
        long value = Cents(amount);
        if (value == 0)
            throw new CommandError("invalid amount");
        booking.Deposit += value;
        Emit("PAY", id, amount, "deposit", Money(booking.Deposit));
    }

    private void CmdCheckout(string id)
        => Checkout(RequireReservation(id, "inhouse"), today);

    private void CmdInvoice(string id)
    {
        Reservation booking = RequireReservation(id);
        Emit("INVOICE", id, booking.Guest, "room", booking.Room.Number,
             booking.Room.Kind, booking.Status);
        if (booking.Status is "cancelled" or "noshow")
        {
            EmitIndented(booking.Status == "cancelled" ? "cancellation" : "noshow",
                         "fee", Money(booking.Fee));
            EmitIndented("total", Money(booking.Fee));
            EmitIndented(DepositText(booking, booking.Fee));
            return;
        }
        foreach (Night night in booking.Nights)
            EmitIndented(DateWeekday(night.Day), "room", night.Room, Money(night.Rate));
        Bill bill = booking.FinalBill ?? CalculateBill(booking);
        EmitIndented("lodging", Money(bill.Lodging));
        EmitIndented("discount", Money(bill.Discount));
        if (booking.Penalty != null)
            EmitIndented("penalty", DateWeekday(booking.Penalty.Value.Day),
                         Money(bill.Penalty));
        foreach (Charge extra in booking.Extras)
            EmitIndented("extra", extra.Item, Money(extra.Amount));
        EmitIndented("tax", Money(bill.Tax));
        EmitIndented("total", Money(bill.Total));
        EmitIndented(DepositText(booking, bill.Total));
    }

    private void CmdAvail(string kind, string first, string last)
    {
        RequireType(kind);
        var (start, end) = Period(first, last);
        List<Room> choices = rooms.Values.Where(room => room.Kind == kind).ToList();
        Emit("AVAIL", kind, first, "->", last);
        for (int day = start; day <= end; ++day)
        {
            List<int> available = choices
                .Where(room => !blocks.Contains((day, room.Number)) &&
                               !occupied.ContainsKey((day, room.Number)))
                .Select(room => room.Number).ToList();
            string details = string.Join(" ", available);
            EmitIndented($"{DateWeekday(day)} free {available.Count}" +
                         (available.Count > 0 ? " " + details : ""));
        }
    }

    private string OccupancyParts(IReadOnlyCollection<Room> choices, int day)
    {
        int blocked = choices.Count(room => blocks.Contains((day, room.Number)));
        int taken = choices.Count(room => occupied.ContainsKey((day, room.Number)));
        int available = choices.Count - blocked;
        string percent = available > 0 ? $"{taken * 100 / available}%" : "n/a";
        return $"rooms {choices.Count} blocked {blocked} occupied {taken} rate {percent}";
    }

    private void CmdOccupancy(string text)
    {
        int day = DateNumber(text);
        Emit($"OCCUPANCY {DateWeekday(day)} {OccupancyParts(rooms.Values.ToList(), day)}");
        foreach (string kind in RoomTypes)
        {
            List<Room> choices = rooms.Values.Where(room => room.Kind == kind).ToList();
            if (choices.Count > 0)
                EmitIndented($"{kind} {OccupancyParts(choices, day)}");
        }
    }

    private (int Available, int Occupied, long Revenue) DailyValues(int day)
    {
        int available = rooms.Count - rooms.Keys.Count(number => blocks.Contains((day, number)));
        int taken = 0;
        long revenue = 0;
        foreach (int number in rooms.Keys)
        {
            if (occupied.TryGetValue((day, number), out var holder))
            {
                ++taken;
                revenue += holder.Rate;
            }
        }
        return (available, taken, revenue);
    }

    private static string MetricsParts(int available, int taken, long revenue)
    {
        string percent = available > 0 ? $"{taken * 100 / available}%" : "n/a";
        string average = taken > 0 ? Money(revenue / taken) : "n/a";
        string revpar = available > 0 ? Money(revenue / available) : "n/a";
        return $"sold {taken}/{available} rate {percent} revenue {Money(revenue)} " +
               $"adr {average} revpar {revpar}";
    }

    private void CmdStats(string first, string last)
    {
        var (start, end) = Period(first, last);
        int sumAvailable = 0, sumTaken = 0;
        long sumRevenue = 0;
        Emit("STATS", first, "->", last);
        for (int day = start; day <= end; ++day)
        {
            var (available, taken, revenue) = DailyValues(day);
            sumAvailable += available;
            sumTaken += taken;
            sumRevenue += revenue;
            EmitIndented($"{DateWeekday(day)} {MetricsParts(available, taken, revenue)}");
        }
        EmitIndented($"total {MetricsParts(sumAvailable, sumTaken, sumRevenue)}");
    }

    private void CmdRooms()
    {
        Emit("ROOMS", DateWeekday(today), "rooms", rooms.Count);
        foreach (Room room in rooms.Values)
        {
            string line = $"{room.Number} {room.Kind} base {Money(room.Rate)} " +
                          $"tonight {Money(NightRate(room, today))} " +
                          (room.Clean ? "clean" : "dirty");
            Reservation? occupant = Inhouse(room);
            if (occupant != null)
                line += " occupied " + occupant.Id;
            else if (blocks.Contains((today, room.Number)))
                line += " blocked";
            else
                line += " vacant";

            Reservation? upcoming = reservations
                .Where(r => r.Status == "booked" && ReferenceEquals(r.Room, room))
                .OrderBy(r => r.Arrival).FirstOrDefault();
            if (upcoming != null)
                line += $" next {upcoming.Id} {DateText(upcoming.Arrival)}";
            EmitIndented(line);
        }
    }

    private void CmdList(string status)
    {
        var matching = reservations.Where(r => r.Status == status)
            .OrderBy(r => r.Arrival).ThenBy(r => r.Id, StringComparer.Ordinal).ToList();
        Emit("LIST", status, matching.Count);
        foreach (Reservation booking in matching)
            EmitIndented(booking.Id, booking.Guest, "room", booking.Room.Number,
                         DateText(booking.Arrival), "->", DateText(booking.Departure));
    }

    private void CmdQueue()
    {
        Emit("QUEUE", waitlist.Count);
        for (int i = 0; i < waitlist.Count; ++i)
        {
            WaitingEntry entry = waitlist[i];
            EmitIndented(i + 1, entry.Id, entry.Guest, entry.Kind,
                         DateText(entry.Arrival), "->", DateText(entry.Departure));
        }
    }

    private void CmdSchedule(string text)
    {
        int day = DateNumber(text);
        var arrivals = reservations
            .Where(r => r.Arrival == day && r.Status != "cancelled")
            .OrderBy(r => r.Id, StringComparer.Ordinal).ToList();
        var departures = reservations
            .Where(r => r.Departure == day &&
                        (r.Status == "booked" || r.Status == "inhouse" || r.Status == "checkedout"))
            .OrderBy(r => r.Id, StringComparer.Ordinal).ToList();
        Emit("SCHEDULE", DateWeekday(day), "arrivals", arrivals.Count,
             "departures", departures.Count);
        foreach (Reservation booking in arrivals)
            EmitIndented("arrival", booking.Id, booking.Guest,
                         "room", booking.Room.Number, booking.Status);
        foreach (Reservation booking in departures)
            EmitIndented("departure", booking.Id, booking.Guest,
                         "room", booking.Room.Number, booking.Status);
    }

    private void CmdGuest(string guest)
    {
        List<Reservation> entries = reservations.Where(r => r.Guest == guest).ToList();
        if (entries.Count == 0)
            throw new CommandError("unknown guest " + guest);
        Emit("GUEST", guest);
        foreach (Reservation booking in entries)
        {
            bool open = booking.Status == "booked" || booking.Status == "inhouse";
            EmitIndented(booking.Id, "room", booking.Room.Number, booking.Room.Kind,
                         DateText(booking.Arrival), "->", DateText(booking.Departure),
                         booking.Status, open ? "deposit" : "paid",
                         Money(open ? booking.Deposit : booking.Paid));
        }
        long total = GuestTotal(guest);
        EmitIndented("total paid", Money(total), "points", total / 100, "tier", Tier(guest));
    }

    private void CmdRevenue(string first, string last)
    {
        var (start, end) = Period(first, last, limited: false);
        List<Reservation> posted = reservations
            .Where(r => r.Posting != null && r.Posting >= start && r.Posting <= end).ToList();
        List<Reservation> checkedOut = posted.Where(r => r.Status == "checkedout").ToList();
        List<Reservation> cancelled = posted.Where(r => r.Status == "cancelled").ToList();
        List<Reservation> absent = posted.Where(r => r.Status == "noshow").ToList();
        long lodging = checkedOut.Sum(r => r.FinalBill!.Lodging);
        long discount = checkedOut.Sum(r => r.FinalBill!.Discount);
        long penalty = checkedOut.Sum(r => r.FinalBill!.Penalty);
        long extras = checkedOut.Sum(r => r.FinalBill!.Extras);
        long tax = checkedOut.Sum(r => r.FinalBill!.Tax);
        long cancellations = cancelled.Sum(r => r.Fee);
        long noshows = absent.Sum(r => r.Fee);
        Emit("REVENUE", first, "->", last);
        EmitIndented("lodging", Money(lodging));
        EmitIndented("discount", Money(discount));
        EmitIndented("penalty", Money(penalty));
        EmitIndented("extras", Money(extras));
        EmitIndented("tax", Money(tax));
        EmitIndented("cancellation", Money(cancellations));
        EmitIndented("noshow", Money(noshows));
        EmitIndented("total", Money(lodging - discount + penalty + extras + tax + cancellations + noshows));
        EmitIndented("checkouts", checkedOut.Count, "cancellations", cancelled.Count,
                     "noshows", absent.Count);
    }

    public void Execute(string line)
    {
        string[] words = line.Split(' ');
        string command = words[0];
        string[] args = words.Skip(1).ToArray();
        try
        {
            switch (command)
            {
                case "ROOM": CmdRoom(args[0], args[1], args[2]); break;
                case "RATE": CmdRate(args[0], args[1]); break;
                case "SEASON": CmdSeason(args[0], args[1], args[2]); break;
                case "BLOCK": CmdBlock(args[0], args[1], args[2]); break;
                case "UNBLOCK": CmdUnblock(args[0], args[1], args[2]); break;
                case "CLEAN": CmdClean(args[0]); break;
                case "TODAY": CmdToday(args[0]); break;
                case "BOOK": CmdBook(args[0], args[1], args[2], args[3], args[4]); break;
                case "BOOKROOM": CmdBookroom(args[0], args[1], args[2], args[3], args[4]); break;
                case "WAITLIST": CmdWaitlist(args[0], args[1], args[2], args[3], args[4]); break;
                case "MODIFY": CmdModify(args[0], args[1], args[2]); break;
                case "CANCEL": CmdCancel(args[0]); break;
                case "CHECKIN": CmdCheckin(args[0]); break;
                case "MOVE": CmdMove(args[0], args[1]); break;
                case "EXTEND": CmdExtend(args[0], args[1]); break;
                case "CHARGE": CmdCharge(args[0], args[1], args[2]); break;
                case "PAY": CmdPay(args[0], args[1]); break;
                case "CHECKOUT": CmdCheckout(args[0]); break;
                case "INVOICE": CmdInvoice(args[0]); break;
                case "AVAIL": CmdAvail(args[0], args[1], args[2]); break;
                case "OCCUPANCY": CmdOccupancy(args[0]); break;
                case "STATS": CmdStats(args[0], args[1]); break;
                case "ROOMS": CmdRooms(); break;
                case "LIST": CmdList(args[0]); break;
                case "QUEUE": CmdQueue(); break;
                case "SCHEDULE": CmdSchedule(args[0]); break;
                case "GUEST": CmdGuest(args[0]); break;
                case "REVENUE": CmdRevenue(args[0], args[1]); break;
            }
        }
        catch (CommandError error)
        {
            Emit("ERROR", error.Message);
        }
        ProcessWaitlist();
    }
}

static class Program
{
    static void Main()
    {
        int count = int.Parse(Console.ReadLine()!, CultureInfo.InvariantCulture);
        HotelDesk desk = new();
        for (int i = 0; i < count; ++i)
            desk.Execute(Console.ReadLine()!);
        foreach (string line in desk.Output)
            Console.WriteLine(line);
    }
}
