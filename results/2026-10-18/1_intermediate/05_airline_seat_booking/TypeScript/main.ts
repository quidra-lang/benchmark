import { readFileSync } from "node:fs";

type Seat = { id: string; row: number; letter: string; block: number; kind: string; cabin: string };
type Cabin = { start: number; end: number; blocks: string[]; seats: string[] };
type Model = { name: string; base: number; limit: number; cabins: Map<string, Cabin>; seats: Map<string, Seat>; exits: Set<number>; blocked: Set<string> };
type Passenger = { name: string; type: string; pref: string; cabin: string; seat: string; infant: string; adult: string; pnr: string; order: number };
type Booking = { pnr: string; flight: string; passengers: Passenger[]; checked: boolean };
type Flight = { name: string; model: Model; blocked: Set<string>; limits: Map<string, number>; closed: boolean; bookings: Booking[]; volunteers: Passenger[] };

class Invalid extends Error {}

function fail(message: string): never {
    throw new Invalid(message);
}

const classes = ["F", "J", "Y"];
const tierOrder = ["PLATINUM", "GOLD", "SILVER", "NONE"];

function seatOrder(a: Seat, b: Seat): number {
    return a.row - b.row || a.letter.charCodeAt(0) - b.letter.charCodeAt(0);
}

function display(passenger: Passenger): string {
    return passenger.type === "INFANT" ? "LAP" : passenger.seat || "UNASSIGNED";
}

function loadFactor(seated: number, seats: number): string {
    const value = Math.floor(seated * 1000 / seats);
    return Math.floor(value / 10) + "." + value % 10 + "%";
}

class BookingSystem {
    models = new Map<string, Model>();
    flights = new Map<string, Flight>();
    bookings = new Map<string, Booking>();
    tiers = new Map<string, string>();
    used = new Set<string>();
    defining: Model | null = null;
    serial = 0;

    tier(name: string): string {
        return this.tiers.get(name) ?? "NONE";
    }

    passengers(flight: Flight): Passenger[] {
        return flight.bookings.flatMap(booking => booking.passengers);
    }

    getFlight(name: string, open: boolean = false): Flight {
        const flight = this.flights.get(name);
        if (!flight) {
            fail("unknown flight " + name);
        }
        if (open && flight.closed) {
            fail("flight " + name + " is closed");
        }
        return flight;
    }

    getBooking(pnr: string, open: boolean = false): Booking {
        const booking = this.bookings.get(pnr);
        if (!booking || !booking.passengers.length) {
            fail("unknown PNR " + pnr);
        }
        this.getFlight(booking.flight, open);
        return booking;
    }

    getPassenger(pnr: string, name: string, open: boolean = true): Passenger {
        const booking = this.getBooking(pnr, open);
        const passenger = booking.passengers.find(person => person.name === name);
        if (!passenger) {
            fail("no passenger " + name + " in " + pnr);
        }
        return passenger;
    }

    cabin(flight: Flight, name: string): Cabin {
        const cabin = flight.model.cabins.get(name);
        if (!cabin) {
            fail("no cabin " + name + " on " + flight.name);
        }
        return cabin;
    }

    booked(flight: Flight, cabin: string): number {
        return this.passengers(flight).filter(person => person.type !== "INFANT" && person.cabin === cabin).length;
    }

    fits(flight: Flight, people: Passenger[], seats: string[], cabin: string = "", vacated: Passenger[] = []): boolean {
        const ignored = new Set([...people, ...vacated]);
        const existing = this.passengers(flight).filter(person => person.seat && !ignored.has(person));
        const occupied = new Set(existing.map(person => person.seat));
        const infants = new Set<string>();
        for (const person of existing.filter(person => person.infant)) {
            const seat = flight.model.seats.get(person.seat)!;
            infants.add(seat.row + ":" + seat.block);
        }
        for (let i = 0; i < people.length; i++) {
            const person = people[i];
            const seat = flight.model.seats.get(seats[i]);
            if (!seat || seat.cabin !== (cabin || person.cabin) || flight.blocked.has(seat.id) || occupied.has(seat.id)) {
                return false;
            }
            if ((person.type === "CHILD" || person.infant) && flight.model.exits.has(seat.row)) {
                return false;
            }
            const key = seat.row + ":" + seat.block;
            if (person.infant && infants.has(key)) {
                return false;
            }
            if (person.infant) {
                infants.add(key);
            }
            occupied.add(seat.id);
        }
        return true;
    }

    choose(flight: Flight, person: Passenger, cabin: string = person.cabin): string {
        const candidates = this.cabin(flight, cabin).seats.filter(seat => this.fits(flight, [person], [seat], cabin));
        const preferred = candidates.find(seat => flight.model.seats.get(seat)!.kind === person.pref);
        return preferred ?? candidates[0] ?? "";
    }

    reassign(flight: Flight): string[] {
        const output: string[] = [];
        for (const person of this.passengers(flight)) {
            if (person.type !== "INFANT" && !person.seat) {
                const seat = this.choose(flight, person);
                if (seat) {
                    person.seat = seat;
                    output.push("REASSIGNED " + person.pnr + " " + person.name + " " + seat);
                }
            }
        }
        return output;
    }

    assign(flight: Flight, people: Passenger[], cabinName: string): string {
        if (people.length === 1) {
            people[0].seat = this.choose(flight, people[0]);
            return "SINGLE";
        }
        const cabin = this.cabin(flight, cabinName);
        const k = people.length;
        const adopt = (seats: string[]): boolean => {
            if (!this.fits(flight, people, seats)) {
                return false;
            }
            people.forEach((person, i) => person.seat = seats[i]);
            return true;
        };
        for (const stage of ["BLOCK", "ROW"]) {
            for (let row = cabin.start; row <= cabin.end; row++) {
                const blocks = stage === "BLOCK" ? cabin.blocks : [cabin.blocks.join("")];
                for (const block of blocks) {
                    for (let start = 0; start + k <= block.length; start++) {
                        const seats = block.slice(start, start + k).split("").map(letter => row + letter);
                        if (adopt(seats)) {
                            return stage;
                        }
                    }
                }
            }
        }
        for (let h = 2; h <= k; h++) {
            const width = Math.floor((k + h - 1) / h);
            const height = Math.floor((k + width - 1) / width);
            for (let row = cabin.start; row + height - 1 <= cabin.end; row++) {
                for (const block of cabin.blocks) {
                    for (let start = 0; start + width <= block.length; start++) {
                        const seats = Array.from({ length: k }, (_, j) => (row + Math.floor(j / width)) + block[start + j % width]);
                        if (adopt(seats)) {
                            return "STACK";
                        }
                    }
                }
            }
        }
        for (const person of people) {
            person.seat = this.choose(flight, person);
        }
        return "SPLIT";
    }

    targets(person: Passenger): Passenger[] {
        const booking = this.bookings.get(person.pnr)!;
        return booking.passengers.filter(other => other === person || person.infant === other.name);
    }

    remove(flight: Flight, targets: Passenger[]): void {
        const removed = new Set(targets);
        for (const person of targets) {
            if (person.type === "INFANT") {
                const adult = this.bookings.get(person.pnr)!.passengers.find(other => other.name === person.adult);
                if (adult) {
                    adult.infant = "";
                }
            }
        }
        for (const booking of flight.bookings) {
            booking.passengers = booking.passengers.filter(person => !removed.has(person));
        }
        flight.volunteers = flight.volunteers.filter(person => !removed.has(person));
    }

    define(name: string, args: string[]): string[] {
        if (name === "AIRCRAFT") {
            this.defining = {
                name: args[0], base: Number(args[1]), limit: Number(args[2]),
                cabins: new Map<string, Cabin>(), seats: new Map<string, Seat>(),
                exits: new Set<number>(), blocked: new Set<string>()
            };
            return [];
        }
        const model = this.defining!;
        if (name === "CABIN") {
            const blocks = args.slice(3);
            const start = Number(args[1]);
            const end = Number(args[2]);
            const seats: string[] = [];
            for (let row = start; row <= end; row++) {
                blocks.forEach((block, blockIndex) => {
                    block.split("").forEach((letter, i) => {
                        const window = blockIndex === 0 && i === 0 || blockIndex === blocks.length - 1 && i === block.length - 1;
                        const kind = window ? "W" : i === 0 || i === block.length - 1 ? "A" : "M";
                        const id = row + letter;
                        seats.push(id);
                        model.seats.set(id, { id, row, letter, block: blockIndex, kind, cabin: args[0] });
                    });
                });
            }
            model.cabins.set(args[0], { start, end, blocks, seats });
        } else if (name === "EXIT") {
            model.exits = new Set(args.map(Number));
        } else if (name === "BLOCKED") {
            model.blocked = new Set(args);
        } else {
            this.models.set(model.name, model);
            this.defining = null;
            const counts = classes.filter(cabin => model.cabins.has(cabin)).map(cabin =>
                cabin + " " + model.cabins.get(cabin)!.seats.filter(seat => !model.blocked.has(seat)).length);
            return ["AIRCRAFT " + model.name + " " + counts.join(" ")];
        }
        return [];
    }

    book(args: string[]): string[] {
        const [pnr, flightName, cabinName] = args;
        if (this.used.has(pnr)) {
            fail("duplicate PNR " + pnr);
        }
        const flight = this.getFlight(flightName, true);
        this.cabin(flight, cabinName);
        const people = args.slice(3).map((token, i) => {
            const [name, type, pref = ""] = token.split(":");
            return { name, type, pref, cabin: cabinName, seat: "", infant: "", adult: "", pnr, order: this.serial * 10 + i };
        });
        const seen = new Set<string>();
        for (const person of people) {
            if (seen.has(person.name)) {
                fail("duplicate name " + person.name + " in " + pnr);
            }
            seen.add(person.name);
        }
        const existing = new Set(this.passengers(flight).map(person => person.name));
        for (const person of people) {
            if (existing.has(person.name)) {
                fail(person.name + " already on " + flight.name);
            }
        }
        const adults = people.filter(person => person.type === "ADULT");
        const infants = people.filter(person => person.type === "INFANT");
        if (!adults.length) {
            fail("no adult in " + pnr);
        }
        if (infants.length > adults.length) {
            fail("too many infants in " + pnr);
        }
        const seated = people.filter(person => person.type !== "INFANT");
        if (this.booked(flight, cabinName) + seated.length > flight.limits.get(cabinName)!) {
            fail("limit exceeded for " + flight.name + " " + cabinName);
        }
        infants.forEach((infant, i) => {
            infant.adult = adults[i].name;
            adults[i].infant = infant.name;
        });
        const booking = { pnr, flight: flight.name, passengers: people, checked: false };
        this.serial++;
        this.bookings.set(pnr, booking);
        flight.bookings.push(booking);
        this.used.add(pnr);
        const method = this.assign(flight, seated, cabinName);
        return ["BOOKED " + pnr + " " + flight.name + " " + cabinName + " " + method + " " +
            people.map(person => person.name + ":" + display(person)).join(" ")];
    }

    close(flight: Flight): string[] {
        const output: string[] = [];
        for (const booking of flight.bookings) {
            if (booking.passengers.length && !booking.checked) {
                output.push("NOSHOW " + booking.pnr + " " + booking.passengers.length);
                this.remove(flight, [...booking.passengers]);
            }
        }
        output.push(...this.reassign(flight));
        let count = 0;
        let total = 0;
        const compensation: Record<string, number> = { F: 500, J: 300, Y: 150 };
        const deny = (person: Passenger, voluntary: boolean): void => {
            let value = compensation[person.cabin] * (voluntary ? 1 : 2);
            if (person.type === "CHILD") {
                value /= 2;
            }
            output.push("DENIED " + (voluntary ? "VOLUNTARY" : "INVOLUNTARY") + " " +
                person.pnr + " " + person.name + " " + person.cabin + " " + value);
            count++;
            total += value;
            this.remove(flight, this.targets(person));
        };
        for (const cabin of classes.filter(cabin => flight.model.cabins.has(cabin))) {
            const volunteers = flight.volunteers.filter(person => person.seat && person.cabin === cabin);
            for (const volunteer of volunteers) {
                const candidates = this.passengers(flight).filter(person => person.type !== "INFANT" && !person.seat && person.cabin === cabin);
                if (candidates.some(person => this.fits(flight, [person], [volunteer.seat], "", [volunteer]))) {
                    deny(volunteer, true);
                    output.push(...this.reassign(flight));
                }
            }
        }
        const unassigned = this.passengers(flight).filter(person => person.type !== "INFANT" && !person.seat);
        for (const person of unassigned) {
            deny(person, false);
        }
        flight.closed = true;
        output.push("CLOSED " + flight.name + " denied " + count + " compensation " + total);
        return output;
    }

    command(line: string): string[] {
        const [name, ...args] = line.split(" ");
        if (["AIRCRAFT", "CABIN", "EXIT", "BLOCKED", "END"].includes(name)) {
            return this.define(name, args);
        }
        if (name === "FLIGHT") {
            if (this.flights.has(args[0])) {
                fail("duplicate flight " + args[0]);
            }
            const model = this.models.get(args[1]);
            if (!model) {
                fail("unknown aircraft " + args[1]);
            }
            const limits = new Map<string, number>();
            const items: string[] = [];
            for (const cabin of classes.filter(cabin => model.cabins.has(cabin))) {
                const count = model.cabins.get(cabin)!.seats.filter(seat => !model.blocked.has(seat)).length;
                const limit = Math.floor(count * (100 + Number(args[2])) / 100);
                limits.set(cabin, limit);
                items.push(cabin, count + "/" + limit);
            }
            this.flights.set(args[0], {
                name: args[0], model, blocked: new Set(model.blocked), limits,
                closed: false, bookings: [], volunteers: []
            });
            return ["FLIGHT " + args[0] + " " + model.name + " " + items.join(" ")];
        }
        if (name === "BOOK") {
            return this.book(args);
        }
        if (name === "STATUS") {
            this.tiers.set(args[0], args[1]);
            return ["STATUS " + args.join(" ")];
        }
        if (name === "FIND") {
            const items: string[] = [];
            for (const flight of this.flights.values()) {
                const person = this.passengers(flight).find(person => person.name === args[0]);
                if (person) {
                    items.push(flight.name + " " + person.pnr + " " + person.cabin + " " + display(person) + (flight.closed ? " CLOSED" : " OPEN"));
                }
            }
            return ["FIND " + args[0] + " " + this.tier(args[0]) + " " + items.length, ...items];
        }
        if (name === "INFO") {
            const booking = this.getBooking(args[0]);
            return ["INFO " + booking.pnr + " " + booking.flight + " " + booking.passengers.length +
                (booking.checked ? " CHECKED" : " NOT-CHECKED"),
                ...booking.passengers.map(person => person.name + " " + person.type + " " + person.cabin + " " + display(person))];
        }
        if (["SEAT", "SWAP", "CANCEL", "CHECKIN", "VOLUNTEER"].includes(name)) {
            const booking = this.getBooking(args[0], true);
            const flight = this.getFlight(booking.flight);
            if (name === "CHECKIN") {
                if (booking.checked) {
                    fail(booking.pnr + " already checked in");
                }
                booking.checked = true;
                return ["CHECKIN " + booking.pnr + " " + booking.passengers.length];
            }
            if (name === "CANCEL") {
                const targets = args.length === 1 ? [...booking.passengers] : this.targets(this.getPassenger(args[0], args[1]));
                const remaining = booking.passengers.filter(person => !targets.includes(person));
                if (args.length === 2 && remaining.length && !remaining.some(person => person.type === "ADULT")) {
                    fail(booking.pnr + " would have no adult");
                }
                const output = ["CANCELLED " + booking.pnr + " " + targets.map(person => person.name).join(" ")];
                this.remove(flight, targets);
                return [...output, ...this.reassign(flight)];
            }
            const person = this.getPassenger(args[0], args[1]);
            if (name === "SWAP") {
                const other = this.getPassenger(args[2], args[3]);
                if (person === other) {
                    fail("cannot swap " + person.name + " with itself");
                }
                for (const p of [person, other]) {
                    if (p.type === "INFANT") {
                        fail("infant " + p.name + " has no seat");
                    }
                }
                if (booking.flight !== this.bookings.get(other.pnr)!.flight) {
                    fail(args[0] + " and " + args[2] + " are on different flights");
                }
                if (person.cabin !== other.cabin) {
                    fail(person.name + " and " + other.name + " are in different cabins");
                }
                for (const p of [person, other]) {
                    if (!p.seat) {
                        fail(p.name + " has no seat");
                    }
                }
                if (!this.fits(flight, [person, other], [other.seat, person.seat])) {
                    fail("swap of " + person.name + " and " + other.name + " breaks seating rules");
                }
                [person.seat, other.seat] = [other.seat, person.seat];
                return ["SWAPPED " + person.pnr + " " + person.name + " " + person.seat + " " + other.pnr +
                    " " + other.name + " " + other.seat, ...this.reassign(flight)];
            }
            if (name === "VOLUNTEER") {
                if (person.type !== "ADULT" || person.infant) {
                    fail(person.name + " cannot volunteer");
                }
                if (!person.seat) {
                    fail(person.name + " has no seat");
                }
                if (flight.volunteers.includes(person)) {
                    fail(person.name + " already volunteered");
                }
                flight.volunteers.push(person);
                return ["VOLUNTEER " + person.pnr + " " + person.name + " " + person.seat];
            }
            if (person.type === "INFANT") {
                fail("infant " + person.name + " has no seat");
            }
            const seat = flight.model.seats.get(args[2]);
            if (!seat || seat.cabin !== person.cabin) {
                fail("no seat " + args[2] + " in cabin " + person.cabin);
            }
            if (flight.blocked.has(seat.id)) {
                fail("seat " + seat.id + " is blocked");
            }
            if (this.passengers(flight).some(other => other.seat === seat.id)) {
                fail("seat " + seat.id + " is occupied");
            }
            if ((person.type === "CHILD" || person.infant) && flight.model.exits.has(seat.row)) {
                fail("exit row " + seat.row + " not allowed for " + person.name);
            }
            if (!this.fits(flight, [person], [seat.id])) {
                fail("infant limit reached at " + seat.id);
            }
            const old = person.seat;
            person.seat = seat.id;
            return ["MOVED " + person.pnr + " " + person.name + " " + old + " -> " + seat.id, ...this.reassign(flight)];
        }
        const modifying = ["UPGRADE", "CLOSE", "BLOCK", "UNBLOCK"].includes(name);
        const flight = this.getFlight(args[0], modifying);
        if (name === "CLOSE") {
            return this.close(flight);
        }
        if (name === "UPGRADE") {
            const cabins = classes.filter(cabin => flight.model.cabins.has(cabin));
            const output: string[] = [];
            let count = 0;
            for (let i = 0; i + 1 < cabins.length; i++) {
                const [higher, lower] = cabins.slice(i, i + 2);
                const targets = this.passengers(flight).filter(person => person.cabin === lower && person.type === "ADULT" &&
                    !person.infant && this.tier(person.name) !== "NONE");
                targets.sort((a, b) => tierOrder.indexOf(this.tier(a.name)) - tierOrder.indexOf(this.tier(b.name)) || a.order - b.order);
                for (const person of targets) {
                    if (this.booked(flight, higher) >= flight.limits.get(higher)!) {
                        break;
                    }
                    const seat = this.choose(flight, person, higher);
                    if (!seat) {
                        break;
                    }
                    const old = person.seat || "UNASSIGNED";
                    person.cabin = higher;
                    person.seat = seat;
                    output.push("UPGRADED " + person.pnr + " " + person.name + " " + lower + " " + old + " -> " + higher + " " + seat);
                    count++;
                }
            }
            return [...output, ...this.reassign(flight), "UPGRADE " + flight.name + " " + count];
        }
        if (name === "BLOCK" || name === "UNBLOCK") {
            const seat = args[1];
            if (!flight.model.seats.has(seat)) {
                fail("no seat " + seat + " on " + flight.name);
            }
            const blocked = flight.blocked.has(seat);
            if (name === "BLOCK" && blocked) {
                fail("seat " + seat + " is blocked");
            }
            if (name === "UNBLOCK" && !blocked) {
                fail("seat " + seat + " is not blocked");
            }
            const output = [name + " " + flight.name + " " + seat];
            if (name === "BLOCK") {
                flight.blocked.add(seat);
                const person = this.passengers(flight).find(person => person.seat === seat);
                if (person) {
                    person.seat = "";
                    person.seat = this.choose(flight, person);
                    output.push("DISPLACED " + person.pnr + " " + person.name + " " + seat + " -> " + (person.seat || "UNASSIGNED"));
                }
            } else {
                flight.blocked.delete(seat);
            }
            return [...output, ...this.reassign(flight)];
        }
        return this.inspect(name, flight, args);
    }

    inspect(name: string, flight: Flight, args: string[]): string[] {
        const people = this.passengers(flight);
        const seated = people.filter(person => person.seat).sort((a, b) =>
            seatOrder(flight.model.seats.get(a.seat)!, flight.model.seats.get(b.seat)!));
        const unassigned = people.filter(person => person.type !== "INFANT" && !person.seat);
        const cabins = classes.filter(cabin => flight.model.cabins.has(cabin));
        if (name === "MAP") {
            const occupied = new Set(seated.map(person => person.seat));
            const output = ["MAP " + flight.name];
            for (const cabinName of cabins) {
                const cabin = flight.model.cabins.get(cabinName)!;
                output.push("CABIN " + cabinName, "   " + cabin.blocks.join(" "));
                for (let row = cabin.start; row <= cabin.end; row++) {
                    const blocks = cabin.blocks.map(block => block.split("").map(letter => {
                        const id = row + letter;
                        return flight.blocked.has(id) ? "#" : occupied.has(id) ? "X" : flight.model.exits.has(row) ? "E" : ".";
                    }).join(""));
                    output.push(String(row).padStart(2, " ") + " " + blocks.join(" "));
                }
            }
            return output;
        }
        if (name === "AVAIL") {
            const cabin = this.cabin(flight, args[1]);
            const occupied = new Set(seated.map(person => person.seat));
            const free = cabin.seats.filter(seat => !flight.blocked.has(seat) && !occupied.has(seat)).map(seat => flight.model.seats.get(seat)!);
            return ["AVAIL " + flight.name + " " + args[1] + " free " + free.length + " W " + free.filter(seat => seat.kind === "W").length +
                " M " + free.filter(seat => seat.kind === "M").length + " A " + free.filter(seat => seat.kind === "A").length +
                " EXIT " + free.filter(seat => flight.model.exits.has(seat.row)).length];
        }
        if (name === "MANIFEST") {
            const infants = people.filter(person => person.type === "INFANT").length;
            const output = ["MANIFEST " + flight.name + " seated " + seated.length + " unassigned " + unassigned.length + " infants " + infants];
            for (const person of [...seated, ...unassigned]) {
                let line = (person.seat || "---") + " " + person.cabin + " " + person.pnr + " " + person.name + " " + person.type;
                if (person.infant) {
                    line += " +" + person.infant;
                }
                if (this.tier(person.name) !== "NONE") {
                    line += " " + this.tier(person.name);
                }
                if (this.bookings.get(person.pnr)!.checked) {
                    line += " CHECKED";
                }
                if (flight.volunteers.includes(person)) {
                    line += " VOL";
                }
                output.push(line);
            }
            return output;
        }
        if (name === "LOADFACTOR") {
            const output = ["LOADFACTOR " + flight.name];
            let totalSeated = 0;
            let totalSeats = 0;
            for (const cabin of cabins) {
                const count = seated.filter(person => person.cabin === cabin).length;
                const seats = flight.model.cabins.get(cabin)!.seats.filter(seat => !flight.blocked.has(seat)).length;
                totalSeated += count;
                totalSeats += seats;
                output.push(cabin + " " + count + "/" + seats + " " + loadFactor(count, seats) + " booked " +
                    this.booked(flight, cabin) + "/" + flight.limits.get(cabin));
            }
            output.push("ALL " + totalSeated + "/" + totalSeats + " " + loadFactor(totalSeated, totalSeats));
            return output;
        }
        if (name === "BALANCE") {
            let weight = 0;
            let moment = 0;
            for (const person of seated) {
                const value = (person.type === "ADULT" ? 80 : 40) + (person.infant ? 10 : 0);
                weight += value;
                moment += value * (flight.model.seats.get(person.seat)!.row - flight.model.base);
            }
            const limit = flight.model.limit;
            const verdict = moment < -limit ? "NOSE-HEAVY" : moment > limit ? "TAIL-HEAVY" : "OK";
            return ["BALANCE " + flight.name + " weight " + weight + " moment " + moment + " limit " + limit + " " + verdict];
        }
        const entries = seated.map(person => {
            const booking = this.bookings.get(person.pnr)!;
            const seat = flight.model.seats.get(person.seat)!;
            let group = "";
            let key: number[];
            if (booking.passengers.some(p => p.type === "INFANT")) {
                group = "PRE";
                key = [0, seat.row, seat.letter.charCodeAt(0)];
            } else if (person.cabin !== "Y") {
                group = "CABIN";
                key = [1, seat.row, seat.letter.charCodeAt(0)];
            } else if (["PLATINUM", "GOLD"].includes(this.tier(person.name))) {
                group = "TIER";
                key = [2, seat.row, seat.letter.charCodeAt(0)];
            } else {
                const zone = Math.floor((seat.row - flight.model.cabins.get("Y")!.start) / 5) + 1;
                group = "ZONE" + zone;
                key = [3, -zone, ["W", "M", "A"].indexOf(seat.kind), -seat.row, seat.letter.charCodeAt(0)];
            }
            return { person, group, key };
        });
        entries.sort((a, b) => {
            for (let i = 0; i < Math.min(a.key.length, b.key.length); i++) {
                if (a.key[i] !== b.key[i]) {
                    return a.key[i] - b.key[i];
                }
            }
            return 0;
        });
        return ["BOARDING " + flight.name + " " + entries.length, ...entries.map((entry, i) =>
            (i + 1) + " " + entry.group + " " + entry.person.seat + " " + entry.person.pnr + " " + entry.person.name)];
    }
}

const lines = readFileSync(0, "utf8").split("\n");
const system = new BookingSystem();
const output: string[] = [];
for (let i = 1; i <= Number(lines[0]); i++) {
    try {
        output.push(...system.command(lines[i]));
    } catch (error) {
        if (!(error instanceof Invalid)) {
            throw error;
        }
        output.push("ERROR " + error.message);
    }
}
if (output.length) {
    process.stdout.write(output.join("\n") + "\n");
}
