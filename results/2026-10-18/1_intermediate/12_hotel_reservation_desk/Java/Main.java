import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.stream.Collectors;

public class Main {
    private static final List<String> ROOM_TYPES = List.of("SINGLE", "DOUBLE", "SUITE");
    private static final String[] WEEKDAYS = {"SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI"};

    private static final class CommandError extends RuntimeException {
        CommandError(String message) {
            super(message);
        }
    }

    private static boolean leap(int year) {
        return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    }

    private static int[] monthLengths(int year) {
        return new int[]{31, leap(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    }

    private static int dayNumber(String text) {
        String[] parts = text.split("-");
        int year = Integer.parseInt(parts[0]);
        int month = Integer.parseInt(parts[1]);
        int day = Integer.parseInt(parts[2]);
        if (year < 2000 || year > 2099 || month < 1 || month > 12) {
            throw new CommandError("invalid date " + text);
        }
        int[] lengths = monthLengths(year);
        if (day < 1 || day > lengths[month - 1]) {
            throw new CommandError("invalid date " + text);
        }
        int number = day - 1;
        for (int previous = 2000; previous < year; ++previous) {
            number += leap(previous) ? 366 : 365;
        }
        for (int previous = 0; previous < month - 1; ++previous) {
            number += lengths[previous];
        }
        return number;
    }

    private static String dateText(int number) {
        int year = 2000;
        while (true) {
            int days = leap(year) ? 366 : 365;
            if (number < days) {
                break;
            }
            number -= days;
            ++year;
        }
        int month = 1;
        for (int days : monthLengths(year)) {
            if (number < days) {
                break;
            }
            number -= days;
            ++month;
        }
        return String.format(Locale.ROOT, "%04d-%02d-%02d", year, month, number + 1);
    }

    private static String dateWeekday(int day) {
        return dateText(day) + " " + WEEKDAYS[day % 7];
    }

    private static long cents(String text) {
        String[] parts = text.split("\\.");
        return Long.parseLong(parts[0]) * 100 + Long.parseLong(parts[1]);
    }

    private static String money(long value) {
        return String.format(Locale.ROOT, "%d.%02d", value / 100, value % 100);
    }

    private static String line(Object... parts) {
        return Arrays.stream(parts).map(String::valueOf).collect(Collectors.joining(" "));
    }

    private static final class Room {
        final int number;
        final String kind;
        long rate;
        boolean clean = true;

        Room(int number, String kind, long rate) {
            this.number = number;
            this.kind = kind;
            this.rate = rate;
        }
    }

    private record Night(int day, int room, long rate) {}
    private record Season(int start, int end, int percentage) {}
    private record NightKey(int day, int room) {}
    private record Occupied(Reservation reservation, long rate) {}
    private record Extra(String item, long amount) {}
    private record WaitingEntry(String id, String guest, String kind, int arrival, int departure) {}
    private record Bill(long lodging, long discount, long penalty, long extras, long tax, long total) {}

    private static final class Reservation {
        final String id;
        final String guest;
        Room room;
        int arrival;
        int departure;
        List<Night> nights;
        String status = "booked";
        final List<Extra> extras = new ArrayList<>();
        long deposit;
        long paid;
        Integer posting;
        long fee;
        Night penalty;
        Bill bill;

        Reservation(String id, String guest, Room room, int arrival, int departure, List<Night> nights) {
            this.id = id;
            this.guest = guest;
            this.room = room;
            this.arrival = arrival;
            this.departure = departure;
            this.nights = nights;
        }

        long lodging() {
            return nights.stream().mapToLong(Night::rate).sum();
        }

        long firstRate() {
            return nights.get(0).rate();
        }
    }

    private static final class HotelDesk {
        private int today = dayNumber("2026-01-01");
        private final TreeMap<Integer, Room> rooms = new TreeMap<>();
        private final List<Season> seasons = new ArrayList<>();
        private final Set<NightKey> blocks = new HashSet<>();
        private final Map<String, Reservation> reservations = new LinkedHashMap<>();
        private final List<WaitingEntry> waitlist = new ArrayList<>();
        private final Set<String> usedIds = new HashSet<>();
        private final Map<NightKey, Occupied> occupied = new HashMap<>();
        private final List<String> output = new ArrayList<>();

        private void emit(Object... parts) {
            output.add(line(parts));
        }

        private void emitIndented(Object... parts) {
            output.add("  " + line(parts));
        }

        private Room requireRoom(String text) {
            Room room = rooms.get(Integer.parseInt(text));
            if (room == null) {
                throw new CommandError("unknown room " + text);
            }
            return room;
        }

        private void requireType(String kind) {
            if (!ROOM_TYPES.contains(kind)) {
                throw new CommandError("invalid type " + kind);
            }
        }

        private void requireUnused(String id) {
            if (usedIds.contains(id)) {
                throw new CommandError("duplicate reservation " + id);
            }
        }

        private Reservation reservation(String id, String requiredStatus) {
            Reservation reservation = reservations.get(id);
            if (reservation == null) {
                throw new CommandError("unknown reservation " + id);
            }
            if (requiredStatus != null && !reservation.status.equals(requiredStatus)) {
                throw new CommandError("invalid status " + id + " " + reservation.status);
            }
            return reservation;
        }

        private int[] stay(String first, String last) {
            int arrival = dayNumber(first);
            int departure = dayNumber(last);
            if (arrival < today) {
                throw new CommandError("past date " + first);
            }
            if (departure <= arrival) {
                throw new CommandError("invalid range " + first + " " + last);
            }
            if (departure - arrival > 30) {
                throw new CommandError("too long " + (departure - arrival));
            }
            return new int[]{arrival, departure};
        }

        private int[] period(String first, String last, boolean pastRestricted, boolean limited) {
            int start = dayNumber(first);
            int end = dayNumber(last);
            if (pastRestricted && start < today) {
                throw new CommandError("past date " + first);
            }
            if (end < start) {
                throw new CommandError("invalid range " + first + " " + last);
            }
            if (limited && end - start + 1 > 31) {
                throw new CommandError("too long " + (end - start + 1));
            }
            return new int[]{start, end};
        }

        private long nightRate(Room room, int day) {
            int percentage = 100;
            for (int i = seasons.size() - 1; i >= 0; --i) {
                Season season = seasons.get(i);
                if (season.start() <= day && day <= season.end()) {
                    percentage = season.percentage();
                    break;
                }
            }
            return room.rate * percentage / 100;
        }

        private List<Night> price(Room room, int arrival, int departure) {
            List<Night> nights = new ArrayList<>();
            for (int day = arrival; day < departure; ++day) {
                nights.add(new Night(day, room.number, nightRate(room, day)));
            }
            return nights;
        }

        private Integer firstUnavailable(
            Room room, int arrival, int departure, Reservation exceptFor
        ) {
            for (int day = arrival; day < departure; ++day) {
                NightKey key = new NightKey(day, room.number);
                if (blocks.contains(key)) {
                    return day;
                }
                Occupied night = occupied.get(key);
                if (night != null && night.reservation() != exceptFor) {
                    return day;
                }
            }
            return null;
        }

        private Room freeRoom(
            String kind, int arrival, int departure, Reservation exceptFor
        ) {
            for (Room room : rooms.values()) {
                if (room.kind.equals(kind) &&
                    firstUnavailable(room, arrival, departure, exceptFor) == null) {
                    return room;
                }
            }
            return null;
        }

        private Reservation inhouse(Room room) {
            for (Reservation reservation : reservations.values()) {
                if (reservation.status.equals("inhouse") && reservation.room == room) {
                    return reservation;
                }
            }
            return null;
        }

        private void occupy(Reservation reservation, List<Night> nights) {
            for (Night night : nights) {
                occupied.put(new NightKey(night.day(), night.room()),
                             new Occupied(reservation, night.rate()));
            }
        }

        private void release(Reservation reservation, Integer first) {
            for (Night night : reservation.nights) {
                if (first == null || night.day() >= first) {
                    occupied.remove(new NightKey(night.day(), night.room()));
                }
            }
        }

        private void createReservation(
            String id, String guest, Room room, int arrival, int departure, boolean indent
        ) {
            List<Night> nights = price(room, arrival, departure);
            Reservation reservation = new Reservation(id, guest, room, arrival, departure, nights);
            reservations.put(id, reservation);
            usedIds.add(id);
            occupy(reservation, nights);
            Object[] parts = {
                "BOOK", id, guest, "room", room.number, room.kind,
                dateText(arrival), "->", dateText(departure), "nights", departure - arrival,
                "total", money(reservation.lodging())
            };
            if (indent) {
                emitIndented(parts);
            } else {
                emit(parts);
            }
        }

        private long guestTotal(String guest) {
            return reservations.values().stream()
                .filter(reservation -> reservation.guest.equals(guest))
                .mapToLong(reservation -> reservation.paid).sum();
        }

        private String tier(String guest) {
            long points = guestTotal(guest) / 100;
            return points >= 2000 ? "GOLD" : points >= 500 ? "SILVER" : "BRONZE";
        }

        private Bill calculateBill(Reservation reservation) {
            long lodging = reservation.lodging();
            int percentage = switch (tier(reservation.guest)) {
                case "GOLD" -> 10;
                case "SILVER" -> 5;
                default -> 0;
            };
            long discount = lodging * percentage / 100;
            long penalty = reservation.penalty == null ? 0 : reservation.penalty.rate();
            long extras = reservation.extras.stream().mapToLong(Extra::amount).sum();
            long subtotal = lodging - discount + penalty + extras;
            long tax = subtotal / 10;
            return new Bill(lodging, discount, penalty, extras, tax, subtotal + tax);
        }

        private Object[] depositParts(Reservation reservation, long total) {
            if (total >= reservation.deposit) {
                return new Object[]{
                    "deposit", money(reservation.deposit),
                    "due", money(total - reservation.deposit)
                };
            }
            return new Object[]{
                "deposit", money(reservation.deposit),
                "refund", money(reservation.deposit - total)
            };
        }

        private void checkOut(Reservation reservation, int day, boolean indent) {
            if (day < reservation.departure) {
                for (Night night : reservation.nights) {
                    if (night.day() == day) {
                        reservation.penalty = night;
                        break;
                    }
                }
                release(reservation, day);
                reservation.nights.removeIf(night -> night.day() >= day);
                reservation.departure = day;
            }
            Bill bill = calculateBill(reservation);
            reservation.bill = bill;
            reservation.paid = bill.total();
            reservation.status = "checkedout";
            reservation.posting = day;
            reservation.room.clean = false;
            List<Object> parts = new ArrayList<>(Arrays.asList(
                "CHECKOUT", reservation.id, "nights", reservation.nights.size(),
                "lodging", money(bill.lodging()), "discount", money(bill.discount()),
                "penalty", money(bill.penalty()), "extras", money(bill.extras()),
                "tax", money(bill.tax()), "total", money(bill.total())
            ));
            parts.addAll(Arrays.asList(depositParts(reservation, bill.total())));
            if (indent) {
                emitIndented(parts.toArray());
            } else {
                emit(parts.toArray());
            }
        }

        private void processWaitlist() {
            List<WaitingEntry> remaining = new ArrayList<>();
            for (WaitingEntry entry : waitlist) {
                if (entry.arrival() < today) {
                    emitIndented("WAITLIST", entry.id(), "expired");
                } else {
                    Room room = freeRoom(entry.kind(), entry.arrival(), entry.departure(), null);
                    if (room == null) {
                        remaining.add(entry);
                    } else {
                        createReservation(
                            entry.id(), entry.guest(), room, entry.arrival(), entry.departure(), true
                        );
                    }
                }
            }
            waitlist.clear();
            waitlist.addAll(remaining);
        }

        private void cmdRoom(String[] a) {
            int number = Integer.parseInt(a[0]);
            if (rooms.containsKey(number)) {
                throw new CommandError("duplicate room " + a[0]);
            }
            requireType(a[1]);
            rooms.put(number, new Room(number, a[1], cents(a[2])));
            emit("ROOM", a[0], a[1], a[2]);
        }

        private void cmdRate(String[] a) {
            Room room = requireRoom(a[0]);
            long previous = room.rate;
            room.rate = cents(a[1]);
            emit("RATE", a[0], money(previous), "->", a[1]);
        }

        private void cmdSeason(String[] a) {
            int[] dates = period(a[0], a[1], false, false);
            seasons.add(new Season(dates[0], dates[1], Integer.parseInt(a[2])));
            emit("SEASON", seasons.size(), a[0], "->", a[1], a[2] + "%");
        }

        private void cmdBlock(String[] a) {
            Room room = requireRoom(a[0]);
            int[] dates = period(a[1], a[2], true, true);
            for (int day = dates[0]; day <= dates[1]; ++day) {
                if (occupied.containsKey(new NightKey(day, room.number))) {
                    throw new CommandError("room unavailable " + a[0] + " " + dateText(day));
                }
            }
            int added = 0;
            for (int day = dates[0]; day <= dates[1]; ++day) {
                if (blocks.add(new NightKey(day, room.number))) {
                    ++added;
                }
            }
            emit("BLOCK", a[0], a[1], "->", a[2], "added", added);
        }

        private void cmdUnblock(String[] a) {
            Room room = requireRoom(a[0]);
            int[] dates = period(a[1], a[2], true, true);
            int removed = 0;
            for (int day = dates[0]; day <= dates[1]; ++day) {
                if (blocks.remove(new NightKey(day, room.number))) {
                    ++removed;
                }
            }
            emit("UNBLOCK", a[0], a[1], "->", a[2], "removed", removed);
        }

        private void cmdClean(String[] a) {
            Room room = requireRoom(a[0]);
            if (room.clean) {
                throw new CommandError("already clean " + a[0]);
            }
            room.clean = true;
            emit("CLEAN", a[0]);
        }

        private void cmdToday(String[] a) {
            int day = dayNumber(a[0]);
            if (day < today) {
                throw new CommandError("past date " + a[0]);
            }
            emit("TODAY", dateWeekday(day));
            List<Reservation> departing = reservations.values().stream()
                .filter(r -> r.status.equals("inhouse") && r.departure < day)
                .sorted(Comparator.comparingInt((Reservation r) -> r.departure).thenComparing(r -> r.id))
                .toList();
            for (Reservation reservation : departing) {
                checkOut(reservation, reservation.departure, true);
            }
            List<Reservation> absent = reservations.values().stream()
                .filter(r -> r.status.equals("booked") && r.arrival < day)
                .sorted(Comparator.comparingInt((Reservation r) -> r.arrival).thenComparing(r -> r.id))
                .toList();
            for (Reservation reservation : absent) {
                release(reservation, null);
                reservation.fee = reservation.firstRate();
                reservation.paid = reservation.fee;
                reservation.status = "noshow";
                reservation.posting = reservation.arrival;
                List<Object> parts = new ArrayList<>(Arrays.asList(
                    "NOSHOW", reservation.id, reservation.guest, "fee", money(reservation.fee)
                ));
                parts.addAll(Arrays.asList(depositParts(reservation, reservation.fee)));
                emitIndented(parts.toArray());
            }
            today = day;
        }

        private void cmdBook(String[] a) {
            requireUnused(a[0]);
            requireType(a[2]);
            int[] dates = stay(a[3], a[4]);
            Room room = freeRoom(a[2], dates[0], dates[1], null);
            if (room == null) {
                throw new CommandError("no availability " + a[2] + " " + a[3] + " " + a[4]);
            }
            createReservation(a[0], a[1], room, dates[0], dates[1], false);
        }

        private void cmdBookRoom(String[] a) {
            requireUnused(a[0]);
            Room room = requireRoom(a[2]);
            int[] dates = stay(a[3], a[4]);
            Integer unavailable = firstUnavailable(room, dates[0], dates[1], null);
            if (unavailable != null) {
                throw new CommandError("room unavailable " + a[2] + " " + dateText(unavailable));
            }
            createReservation(a[0], a[1], room, dates[0], dates[1], false);
        }

        private void cmdWaitlist(String[] a) {
            requireUnused(a[0]);
            requireType(a[2]);
            int[] dates = stay(a[3], a[4]);
            Room room = freeRoom(a[2], dates[0], dates[1], null);
            if (room != null) {
                createReservation(a[0], a[1], room, dates[0], dates[1], false);
            } else {
                waitlist.add(new WaitingEntry(a[0], a[1], a[2], dates[0], dates[1]));
                usedIds.add(a[0]);
                emit("WAITLIST", a[0], "queued position", waitlist.size());
            }
        }

        private void cmdModify(String[] a) {
            Reservation reservation = reservation(a[0], "booked");
            int[] dates = stay(a[1], a[2]);
            Room room = reservation.room;
            String choice = "kept";
            if (firstUnavailable(room, dates[0], dates[1], reservation) != null) {
                room = freeRoom(room.kind, dates[0], dates[1], reservation);
                if (room == null) {
                    throw new CommandError(
                        "no availability " + reservation.room.kind + " " + a[1] + " " + a[2]
                    );
                }
                choice = "reassigned";
            }
            List<Night> nights = price(room, dates[0], dates[1]);
            release(reservation, null);
            reservation.room = room;
            reservation.arrival = dates[0];
            reservation.departure = dates[1];
            reservation.nights = nights;
            occupy(reservation, nights);
            emit("MODIFY", a[0], "room", room.number, choice, a[1], "->", a[2],
                 "nights", dates[1] - dates[0], "total", money(reservation.lodging()));
        }

        private void cmdCancel(String[] a) {
            for (int i = 0; i < waitlist.size(); ++i) {
                if (waitlist.get(i).id().equals(a[0])) {
                    waitlist.remove(i);
                    emit("CANCEL", a[0], "waitlist removed");
                    return;
                }
            }
            Reservation reservation = reservation(a[0], "booked");
            int days = reservation.arrival - today;
            long firstRate = reservation.firstRate();
            long fee = days >= 7 ? 0 : days >= 1 ? firstRate / 2 : firstRate;
            release(reservation, null);
            reservation.fee = fee;
            reservation.paid = fee;
            reservation.status = "cancelled";
            reservation.posting = today;
            List<Object> parts = new ArrayList<>(Arrays.asList(
                "CANCEL", a[0], "days", days, "fee", money(fee)
            ));
            parts.addAll(Arrays.asList(depositParts(reservation, fee)));
            emit(parts.toArray());
        }

        private void cmdCheckin(String[] a) {
            Reservation reservation = reservation(a[0], "booked");
            if (reservation.arrival != today) {
                throw new CommandError(
                    "not arrival date " + a[0] + " " + dateText(reservation.arrival)
                );
            }
            Reservation occupant = inhouse(reservation.room);
            if (occupant != null) {
                throw new CommandError(
                    "room occupied " + reservation.room.number + " " + occupant.id
                );
            }
            if (!reservation.room.clean) {
                throw new CommandError("room dirty " + reservation.room.number);
            }
            reservation.status = "inhouse";
            emit("CHECKIN", a[0], reservation.guest, "room", reservation.room.number,
                 "until", dateText(reservation.departure));
        }

        private void cmdMove(String[] a) {
            Reservation reservation = reservation(a[0], "inhouse");
            Room room = requireRoom(a[1]);
            Room previous = reservation.room;
            if (room == previous) {
                throw new CommandError("same room " + a[1]);
            }
            List<Night> remaining = reservation.nights.stream()
                .filter(night -> night.day() >= today).toList();
            if (remaining.isEmpty()) {
                throw new CommandError("no remaining nights " + a[0]);
            }
            Integer unavailable = firstUnavailable(
                room, remaining.get(0).day(), reservation.departure, reservation
            );
            if (unavailable != null) {
                throw new CommandError("room unavailable " + a[1] + " " + dateText(unavailable));
            }
            Reservation occupant = inhouse(room);
            if (occupant != null) {
                throw new CommandError("room occupied " + a[1] + " " + occupant.id);
            }
            if (!room.clean) {
                throw new CommandError("room dirty " + a[1]);
            }
            release(reservation, today);
            List<Night> updated = new ArrayList<>();
            for (Night night : reservation.nights) {
                updated.add(night.day() >= today
                    ? new Night(night.day(), room.number, night.rate()) : night);
            }
            reservation.nights = updated;
            occupy(reservation, updated.stream().filter(night -> night.day() >= today).toList());
            previous.clean = false;
            reservation.room = room;
            emit("MOVE", a[0], previous.number, "->", a[1], "nights", remaining.size());
        }

        private void cmdExtend(String[] a) {
            Reservation reservation = reservation(a[0], "inhouse");
            int departure = dayNumber(a[1]);
            if (departure <= reservation.departure) {
                throw new CommandError(
                    "invalid range " + dateText(reservation.departure) + " " + a[1]
                );
            }
            if (departure - reservation.arrival > 30) {
                throw new CommandError("too long " + (departure - reservation.arrival));
            }
            Integer unavailable = firstUnavailable(
                reservation.room, reservation.departure, departure, reservation
            );
            if (unavailable != null) {
                throw new CommandError(
                    "room unavailable " + reservation.room.number + " " + dateText(unavailable)
                );
            }
            List<Night> nights = price(reservation.room, reservation.departure, departure);
            reservation.nights.addAll(nights);
            occupy(reservation, nights);
            reservation.departure = departure;
            emit("EXTEND", a[0], "until", a[1], "nights", reservation.nights.size(),
                 "total", money(reservation.lodging()));
        }

        private void cmdCharge(String[] a) {
            Reservation reservation = reservation(a[0], "inhouse");
            long value = cents(a[1]);
            if (value == 0) {
                throw new CommandError("invalid amount");
            }
            reservation.extras.add(new Extra(a[2], value));
            long extras = reservation.extras.stream().mapToLong(Extra::amount).sum();
            emit("CHARGE", a[0], a[2], a[1], "extras", money(extras));
        }

        private void cmdPay(String[] a) {
            Reservation reservation = reservation(a[0], null);
            if (!reservation.status.equals("booked") && !reservation.status.equals("inhouse")) {
                throw new CommandError("invalid status " + a[0] + " " + reservation.status);
            }
            long value = cents(a[1]);
            if (value == 0) {
                throw new CommandError("invalid amount");
            }
            reservation.deposit += value;
            emit("PAY", a[0], a[1], "deposit", money(reservation.deposit));
        }

        private void cmdCheckout(String[] a) {
            checkOut(reservation(a[0], "inhouse"), today, false);
        }

        private void cmdInvoice(String[] a) {
            Reservation reservation = reservation(a[0], null);
            emit("INVOICE", a[0], reservation.guest, "room", reservation.room.number,
                 reservation.room.kind, reservation.status);
            if (reservation.status.equals("cancelled") || reservation.status.equals("noshow")) {
                String label = reservation.status.equals("cancelled") ? "cancellation" : "noshow";
                emitIndented(label, "fee", money(reservation.fee));
                emitIndented("total", money(reservation.fee));
                emitIndented(depositParts(reservation, reservation.fee));
                return;
            }
            for (Night night : reservation.nights) {
                emitIndented(dateWeekday(night.day()), "room", night.room(), money(night.rate()));
            }
            Bill bill = reservation.bill != null ? reservation.bill : calculateBill(reservation);
            emitIndented("lodging", money(bill.lodging()));
            emitIndented("discount", money(bill.discount()));
            if (reservation.penalty != null) {
                emitIndented(
                    "penalty", dateWeekday(reservation.penalty.day()), money(bill.penalty())
                );
            }
            for (Extra extra : reservation.extras) {
                emitIndented("extra", extra.item(), money(extra.amount()));
            }
            emitIndented("tax", money(bill.tax()));
            emitIndented("total", money(bill.total()));
            emitIndented(depositParts(reservation, bill.total()));
        }

        private void cmdAvail(String[] a) {
            requireType(a[0]);
            int[] dates = period(a[1], a[2], false, true);
            List<Integer> numbers = rooms.values().stream()
                .filter(room -> room.kind.equals(a[0]))
                .map(room -> room.number).sorted().toList();
            emit("AVAIL", a[0], a[1], "->", a[2]);
            for (int day = dates[0]; day <= dates[1]; ++day) {
                List<Object> parts = new ArrayList<>(Arrays.asList(dateWeekday(day), "free"));
                List<Integer> free = new ArrayList<>();
                for (int number : numbers) {
                    NightKey key = new NightKey(day, number);
                    if (!blocks.contains(key) && !occupied.containsKey(key)) {
                        free.add(number);
                    }
                }
                parts.add(free.size());
                parts.addAll(free);
                emitIndented(parts.toArray());
            }
        }

        private Object[] occupancyParts(List<Integer> numbers, int day) {
            int blocked = 0;
            int occupiedCount = 0;
            for (int number : numbers) {
                NightKey key = new NightKey(day, number);
                blocked += blocks.contains(key) ? 1 : 0;
                occupiedCount += occupied.containsKey(key) ? 1 : 0;
            }
            int available = numbers.size() - blocked;
            String rate = available > 0 ? occupiedCount * 100 / available + "%" : "n/a";
            return new Object[]{
                "rooms", numbers.size(), "blocked", blocked,
                "occupied", occupiedCount, "rate", rate
            };
        }

        private void cmdOccupancy(String[] a) {
            int day = dayNumber(a[0]);
            List<Integer> numbers = new ArrayList<>(rooms.keySet());
            List<Object> parts = new ArrayList<>(Arrays.asList("OCCUPANCY", dateWeekday(day)));
            parts.addAll(Arrays.asList(occupancyParts(numbers, day)));
            emit(parts.toArray());
            for (String kind : ROOM_TYPES) {
                List<Integer> selected = rooms.values().stream()
                    .filter(room -> room.kind.equals(kind)).map(room -> room.number).toList();
                if (!selected.isEmpty()) {
                    List<Object> line = new ArrayList<>();
                    line.add(kind);
                    line.addAll(Arrays.asList(occupancyParts(selected, day)));
                    emitIndented(line.toArray());
                }
            }
        }

        private long[] dailyValues(int day) {
            int available = rooms.size();
            int occupiedCount = 0;
            long revenue = 0;
            for (int number : rooms.keySet()) {
                NightKey key = new NightKey(day, number);
                if (blocks.contains(key)) --available;
                Occupied entry = occupied.get(key);
                if (entry != null) {
                    ++occupiedCount;
                    revenue += entry.rate();
                }
            }
            return new long[]{available, occupiedCount, revenue};
        }

        private Object[] metricsParts(long available, long occupiedCount, long revenue) {
            String rate = available > 0 ? occupiedCount * 100 / available + "%" : "n/a";
            String average = occupiedCount > 0 ? money(revenue / occupiedCount) : "n/a";
            String revpar = available > 0 ? money(revenue / available) : "n/a";
            return new Object[]{
                "sold", occupiedCount + "/" + available, "rate", rate,
                "revenue", money(revenue), "adr", average, "revpar", revpar
            };
        }

        private void cmdStats(String[] a) {
            int[] dates = period(a[0], a[1], false, true);
            long[] totals = {0, 0, 0};
            emit("STATS", a[0], "->", a[1]);
            for (int day = dates[0]; day <= dates[1]; ++day) {
                long[] values = dailyValues(day);
                for (int i = 0; i < 3; ++i) totals[i] += values[i];
                List<Object> parts = new ArrayList<>(Arrays.asList(dateWeekday(day)));
                parts.addAll(Arrays.asList(metricsParts(values[0], values[1], values[2])));
                emitIndented(parts.toArray());
            }
            List<Object> parts = new ArrayList<>(Arrays.asList("total"));
            parts.addAll(Arrays.asList(metricsParts(totals[0], totals[1], totals[2])));
            emitIndented(parts.toArray());
        }

        private void cmdRooms(String[] a) {
            emit("ROOMS", dateWeekday(today), "rooms", rooms.size());
            for (Room room : rooms.values()) {
                List<Object> parts = new ArrayList<>(Arrays.asList(
                    room.number, room.kind, "base", money(room.rate),
                    "tonight", money(nightRate(room, today)), room.clean ? "clean" : "dirty"
                ));
                Reservation occupant = inhouse(room);
                if (occupant != null) {
                    parts.add("occupied");
                    parts.add(occupant.id);
                } else if (blocks.contains(new NightKey(today, room.number))) {
                    parts.add("blocked");
                } else {
                    parts.add("vacant");
                }
                Reservation upcoming = null;
                for (Reservation entry : reservations.values()) {
                    if (entry.status.equals("booked") && entry.room == room &&
                        (upcoming == null || entry.arrival < upcoming.arrival)) {
                        upcoming = entry;
                    }
                }
                if (upcoming != null) {
                    parts.addAll(Arrays.asList("next", upcoming.id, dateText(upcoming.arrival)));
                }
                emitIndented(parts.toArray());
            }
        }

        private void cmdList(String[] a) {
            List<Reservation> selected = reservations.values().stream()
                .filter(r -> r.status.equals(a[0]))
                .sorted(Comparator.comparingInt((Reservation r) -> r.arrival).thenComparing(r -> r.id))
                .toList();
            emit("LIST", a[0], selected.size());
            for (Reservation reservation : selected) {
                emitIndented(
                    reservation.id, reservation.guest, "room", reservation.room.number,
                    dateText(reservation.arrival), "->", dateText(reservation.departure)
                );
            }
        }

        private void cmdQueue(String[] a) {
            emit("QUEUE", waitlist.size());
            for (int i = 0; i < waitlist.size(); ++i) {
                WaitingEntry entry = waitlist.get(i);
                emitIndented(
                    i + 1, entry.id(), entry.guest(), entry.kind(),
                    dateText(entry.arrival()), "->", dateText(entry.departure())
                );
            }
        }

        private void cmdSchedule(String[] a) {
            int day = dayNumber(a[0]);
            List<Reservation> arrivals = reservations.values().stream()
                .filter(r -> r.arrival == day && !r.status.equals("cancelled"))
                .sorted(Comparator.comparing(r -> r.id)).toList();
            List<Reservation> departures = reservations.values().stream()
                .filter(r -> r.departure == day &&
                    (r.status.equals("booked") || r.status.equals("inhouse") ||
                     r.status.equals("checkedout")))
                .sorted(Comparator.comparing(r -> r.id)).toList();
            emit("SCHEDULE", dateWeekday(day), "arrivals", arrivals.size(),
                 "departures", departures.size());
            for (Reservation reservation : arrivals) {
                emitIndented(
                    "arrival", reservation.id, reservation.guest, "room",
                    reservation.room.number, reservation.status
                );
            }
            for (Reservation reservation : departures) {
                emitIndented(
                    "departure", reservation.id, reservation.guest, "room",
                    reservation.room.number, reservation.status
                );
            }
        }

        private void cmdGuest(String[] a) {
            List<Reservation> selected = reservations.values().stream()
                .filter(r -> r.guest.equals(a[0])).toList();
            if (selected.isEmpty()) {
                throw new CommandError("unknown guest " + a[0]);
            }
            emit("GUEST", a[0]);
            for (Reservation reservation : selected) {
                boolean deposit = reservation.status.equals("booked") ||
                                  reservation.status.equals("inhouse");
                emitIndented(
                    reservation.id, "room", reservation.room.number, reservation.room.kind,
                    dateText(reservation.arrival), "->", dateText(reservation.departure),
                    reservation.status, deposit ? "deposit" : "paid",
                    money(deposit ? reservation.deposit : reservation.paid)
                );
            }
            long total = guestTotal(a[0]);
            emitIndented("total paid", money(total), "points", total / 100, "tier", tier(a[0]));
        }

        private void cmdRevenue(String[] a) {
            int[] dates = period(a[0], a[1], false, false);
            long lodging = 0, discount = 0, penalty = 0, extras = 0, tax = 0;
            long cancellations = 0, noshows = 0;
            int checkouts = 0, cancelled = 0, absent = 0;
            for (Reservation reservation : reservations.values()) {
                if (reservation.posting == null ||
                    reservation.posting < dates[0] || reservation.posting > dates[1]) {
                    continue;
                }
                switch (reservation.status) {
                    case "checkedout":
                        ++checkouts;
                        lodging += reservation.bill.lodging();
                        discount += reservation.bill.discount();
                        penalty += reservation.bill.penalty();
                        extras += reservation.bill.extras();
                        tax += reservation.bill.tax();
                        break;
                    case "cancelled":
                        ++cancelled;
                        cancellations += reservation.fee;
                        break;
                    case "noshow":
                        ++absent;
                        noshows += reservation.fee;
                        break;
                    default:
                        break;
                }
            }
            emit("REVENUE", a[0], "->", a[1]);
            emitIndented("lodging", money(lodging));
            emitIndented("discount", money(discount));
            emitIndented("penalty", money(penalty));
            emitIndented("extras", money(extras));
            emitIndented("tax", money(tax));
            emitIndented("cancellation", money(cancellations));
            emitIndented("noshow", money(noshows));
            emitIndented("total", money(
                lodging - discount + penalty + extras + tax + cancellations + noshows
            ));
            emitIndented("checkouts", checkouts, "cancellations", cancelled, "noshows", absent);
        }

        public void execute(String commandLine) {
            String[] fields = commandLine.split(" ");
            String command = fields[0];
            String[] arguments = Arrays.copyOfRange(fields, 1, fields.length);
            try {
                switch (command) {
                    case "ROOM" -> cmdRoom(arguments);
                    case "RATE" -> cmdRate(arguments);
                    case "SEASON" -> cmdSeason(arguments);
                    case "BLOCK" -> cmdBlock(arguments);
                    case "UNBLOCK" -> cmdUnblock(arguments);
                    case "CLEAN" -> cmdClean(arguments);
                    case "TODAY" -> cmdToday(arguments);
                    case "BOOK" -> cmdBook(arguments);
                    case "BOOKROOM" -> cmdBookRoom(arguments);
                    case "WAITLIST" -> cmdWaitlist(arguments);
                    case "MODIFY" -> cmdModify(arguments);
                    case "CANCEL" -> cmdCancel(arguments);
                    case "CHECKIN" -> cmdCheckin(arguments);
                    case "MOVE" -> cmdMove(arguments);
                    case "EXTEND" -> cmdExtend(arguments);
                    case "CHARGE" -> cmdCharge(arguments);
                    case "PAY" -> cmdPay(arguments);
                    case "CHECKOUT" -> cmdCheckout(arguments);
                    case "INVOICE" -> cmdInvoice(arguments);
                    case "AVAIL" -> cmdAvail(arguments);
                    case "OCCUPANCY" -> cmdOccupancy(arguments);
                    case "STATS" -> cmdStats(arguments);
                    case "ROOMS" -> cmdRooms(arguments);
                    case "LIST" -> cmdList(arguments);
                    case "QUEUE" -> cmdQueue(arguments);
                    case "SCHEDULE" -> cmdSchedule(arguments);
                    case "GUEST" -> cmdGuest(arguments);
                    case "REVENUE" -> cmdRevenue(arguments);
                    default -> { }
                }
            } catch (CommandError error) {
                emit("ERROR", error.getMessage());
            }
            processWaitlist();
        }

        public void print() {
            for (String line : output) {
                System.out.println(line);
            }
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        HotelDesk desk = new HotelDesk();
        for (int i = 0; i < count; ++i) {
            desk.execute(input.readLine());
        }
        desk.print();
    }
}
