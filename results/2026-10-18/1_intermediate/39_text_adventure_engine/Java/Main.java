import java.io.*;
import java.util.*;

public class Main {
    static final String[] DIRECTIONS = {"north", "south", "east", "west", "up", "down"};

    static int direction(String word) {
        for (int i = 0; i < DIRECTIONS.length; i++)
            if (word.equals(DIRECTIONS[i]) || word.equals(DIRECTIONS[i].substring(0, 1))) return i;
        return -1;
    }
    static List<String> words(String line) {
        var result = new ArrayList<>(List.of(line.toLowerCase(Locale.ROOT).split(" +")));
        result.removeIf(word -> word.equals("the") || word.equals("a") || word.equals("an"));
        return result;
    }
    static boolean all(List<String> phrase) { return phrase.size() == 1 && phrase.getFirst().equals("all"); }
    static String tail(List<String> words, int at) { return String.join(" ", words.subList(at, words.size())); }

    static class Failure extends RuntimeException {
        Failure(String format, Object... args) { super(String.format(Locale.ROOT, format, args)); }
    }

    enum PlaceKind { NOWHERE, FLOOR, PLAYER, INSIDE }
    record Place(PlaceKind kind, int index) {}
    static final Place NOWHERE = new Place(PlaceKind.NOWHERE, 0);
    static final Place PLAYER = new Place(PlaceKind.PLAYER, 0);
    static Place inside(int item) { return new Place(PlaceKind.INSIDE, item); }
    static Place floor(int room) { return new Place(PlaceKind.FLOOR, room); }
    enum ContainerState { OPEN, CLOSED, LOCKED }
    enum EndStatus { PLAYING, WON, DEAD }
    record Exit(int destination, Integer key, boolean locked) {}

    static class State {
        int room, bonus, moves, darkness;
        EndStatus ended = EndStatus.PLAYING;
        final Place[] places;
        final ContainerState[] containers;
        final int[] fuel;
        final boolean[] lit, visited;
        final Exit[][] exits;
        final Set<String> flags;

        State(int rooms, int items) {
            places = new Place[items]; Arrays.fill(places, NOWHERE);
            containers = new ContainerState[items]; Arrays.fill(containers, ContainerState.OPEN);
            fuel = new int[items]; lit = new boolean[items]; visited = new boolean[rooms];
            exits = new Exit[rooms][6]; flags = new HashSet<>();
        }
        State(State source) {
            room = source.room; bonus = source.bonus; moves = source.moves; darkness = source.darkness; ended = source.ended;
            places = source.places.clone(); containers = source.containers.clone(); fuel = source.fuel.clone();
            lit = source.lit.clone(); visited = source.visited.clone(); flags = new HashSet<>(source.flags);
            exits = new Exit[source.exits.length][];
            for (int i = 0; i < exits.length; i++) exits[i] = source.exits[i].clone();
        }
    }
    static class Room {
        String name = "";
        boolean dark;
        final List<String> description = new ArrayList<>();
    }
    static class Item {
        String name = "";
        final Set<String> nouns = new HashSet<>(), nameWords = new HashSet<>();
        final List<String> details = new ArrayList<>();
        int weight, treasure, capacity;
        Integer key;
        boolean light, fixed;
        Item(String id) { nouns.add(id); }
    }

    record Trigger(boolean enter, int first, int second) {
        static Trigger enter(int room) { return new Trigger(true, room, 0); }
        static Trigger use(int first, int second) { return new Trigger(false, first, second); }
    }
    record Condition(String flag, boolean on) {}
    sealed interface Effect permits Message, OpenExit, MoveItem, SetFlag, Points {}
    record Message(String text) implements Effect {}
    record OpenExit(int room, int direction, int destination) implements Effect {}
    record MoveItem(int item, Place place) implements Effect {}
    record SetFlag(String flag, boolean on) implements Effect {}
    record Points(int amount) implements Effect {}
    record Rule(Trigger trigger, Condition condition, Effect effect) {}
    record RuleResult(int executed, boolean message) {}
    record Treasures(int points, int stored, int total) {}

    static Rule readRule(List<String> w, int at, Trigger trigger, Map<String, Integer> rooms, Map<String, Integer> items) {
        Condition condition = null;
        if (w.get(at).equals("IF") || w.get(at).equals("UNLESS")) {
            condition = new Condition(w.get(at + 1), w.get(at).equals("IF")); at += 2;
        }
        Effect effect = switch (w.get(at)) {
            case "MESSAGE" -> new Message(tail(w, at + 1));
            case "OPEN" -> new OpenExit(rooms.get(w.get(at + 1)), direction(w.get(at + 2)), rooms.get(w.get(at + 3)));
            case "REMOVE" -> new MoveItem(items.get(w.get(at + 1)), NOWHERE);
            case "ADD" -> new MoveItem(items.get(w.get(at + 1)), floor(rooms.get(w.get(at + 2))));
            case "SET", "CLEAR" -> new SetFlag(w.get(at + 1), w.get(at).equals("SET"));
            case "POINTS" -> new Points(Integer.parseInt(w.get(at + 1)));
            default -> throw new AssertionError();
        };
        return new Rule(trigger, condition, effect);
    }

    enum Verb {
        GO, LOOK, EXAMINE, TAKE, DROP, PUT, INVENTORY, OPEN, CLOSE, UNLOCK, LOCK, USE, LIGHT, EXTINGUISH,
        WAIT, SCORE, SAVE, RESTORE, VERBOSE, BRIEF;

        String text() { return name().toLowerCase(Locale.ROOT); }
        boolean noArguments() {
            return switch (this) { case LOOK, INVENTORY, WAIT, SCORE, SAVE, RESTORE, VERBOSE, BRIEF -> true; default -> false; };
        }
        boolean action() {
            return switch (this) {
                case GO, TAKE, DROP, PUT, OPEN, CLOSE, UNLOCK, LOCK, USE, LIGHT, EXTINGUISH, WAIT -> true;
                default -> false;
            };
        }
        static Verb parse(String word) {
            return switch (word) {
                case "go", "walk", "run" -> GO; case "look", "l" -> LOOK;
                case "examine", "x", "inspect", "read" -> EXAMINE; case "take", "get", "grab" -> TAKE;
                case "drop", "discard" -> DROP; case "put", "insert", "place" -> PUT;
                case "inventory", "inv", "i" -> INVENTORY; case "open" -> OPEN; case "close", "shut" -> CLOSE;
                case "unlock" -> UNLOCK; case "lock" -> LOCK; case "use", "apply" -> USE;
                case "light", "ignite" -> LIGHT; case "extinguish", "douse", "snuff" -> EXTINGUISH;
                case "wait", "z" -> WAIT; case "score" -> SCORE; case "save" -> SAVE;
                case "restore", "load" -> RESTORE; case "verbose" -> VERBOSE; case "brief" -> BRIEF;
                default -> null;
            };
        }
    }

    static class Adventure {
        final Room[] rooms;
        final Item[] items;
        final List<Rule> rules = new ArrayList<>();
        final Set<String> vocabulary = new HashSet<>();
        final List<String> output = new ArrayList<>();
        int trophy, maxWeight;
        State state, saved;
        Integer pronoun;
        String previous;
        boolean verbose;

        Adventure(List<List<String>> definitions) {
            var roomIds = new LinkedHashMap<String, Integer>();
            var itemNames = new ArrayList<String>();
            for (var w : definitions) {
                if (w.getFirst().equals("ROOM")) roomIds.put(w.get(1), roomIds.size());
                if (w.getFirst().equals("ITEM")) itemNames.add(w.get(1));
            }
            itemNames.sort(Comparator.naturalOrder());
            var itemIds = new HashMap<String, Integer>();
            rooms = new Room[roomIds.size()]; Arrays.setAll(rooms, i -> new Room());
            items = new Item[itemNames.size()];
            for (int i = 0; i < items.length; i++) { items[i] = new Item(itemNames.get(i)); itemIds.put(itemNames.get(i), i); }
            state = new State(rooms.length, items.length);
            for (var w : definitions) {
                switch (w.getFirst()) {
                    case "ROOM" -> {
                        var room = rooms[roomIds.get(w.get(1))]; room.dark = w.get(2).equals("DARK");
                        room.name = tail(w, room.dark ? 3 : 2);
                    }
                    case "DESC" -> rooms[roomIds.get(w.get(1))].description.add(tail(w, 2));
                    case "EXIT" -> state.exits[roomIds.get(w.get(1))][direction(w.get(2))] =
                        new Exit(roomIds.get(w.get(3)), w.size() > 4 ? itemIds.get(w.get(5)) : null, w.size() > 4);
                    case "ITEM" -> {
                        int x = itemIds.get(w.get(1)), at = 4;
                        state.places[x] = switch (w.get(2)) {
                            case "PLAYER" -> PLAYER; case "NOWHERE" -> NOWHERE; default -> Main.floor(roomIds.get(w.get(2)));
                        };
                        var item = items[x]; item.weight = Integer.parseInt(w.get(3));
                        if (w.get(at).equals("TREASURE")) { item.treasure = Integer.parseInt(w.get(at + 1)); at += 2; }
                        if (w.get(at).equals("LIGHT")) { item.light = true; state.fuel[x] = Integer.parseInt(w.get(at + 1)); at += 2; }
                        if (w.get(at).equals("CONTAINER")) {
                            item.capacity = Integer.parseInt(w.get(at + 1)); at += 2;
                            if (w.get(at).equals("CLOSED")) { state.containers[x] = ContainerState.CLOSED; at++; }
                            if (w.get(at).equals("LOCKED")) { item.key = itemIds.get(w.get(at + 1)); state.containers[x] = ContainerState.LOCKED; at += 2; }
                        }
                        if (w.get(at).equals("FIXED")) { item.fixed = true; at++; }
                        item.name = tail(w, at); item.nameWords.addAll(w.subList(at, w.size()));
                    }
                    case "INSIDE" -> state.places[itemIds.get(w.get(1))] = inside(itemIds.get(w.get(2)));
                    case "ALIAS" -> items[itemIds.get(w.get(1))].nouns.add(w.get(2));
                    case "DETAIL" -> items[itemIds.get(w.get(1))].details.add(tail(w, 2));
                    case "RULE" -> rules.add(readRule(w, 3, Trigger.use(itemIds.get(w.get(1)), itemIds.get(w.get(2))), roomIds, itemIds));
                    case "ENTER" -> rules.add(readRule(w, 2, Trigger.enter(roomIds.get(w.get(1))), roomIds, itemIds));
                    case "TROPHY" -> trophy = roomIds.get(w.get(1)); case "START" -> state.room = roomIds.get(w.get(1));
                    case "MAXWEIGHT" -> maxWeight = Integer.parseInt(w.get(1)); default -> throw new AssertionError();
                }
            }
            state.visited[state.room] = true;
            for (var item : items) { vocabulary.addAll(item.nouns); vocabulary.addAll(item.nameWords); }
        }

        void say(String text) { output.add(text); }
        void sayf(String format, Object... args) { say(String.format(Locale.ROOT, format, args)); }
        Place floor() { return Main.floor(state.room); }
        List<Integer> direct(Place place) {
            var result = new ArrayList<Integer>();
            for (int i = 0; i < items.length; i++) if (state.places[i].equals(place)) result.add(i);
            return result;
        }
        boolean reachable(int item, Place root) {
            Place place = state.places[item];
            while (place.kind == PlaceKind.INSIDE) {
                if (state.containers[place.index] != ContainerState.OPEN) return false;
                place = state.places[place.index];
            }
            return place.equals(root);
        }
        boolean carried(int item) { return reachable(item, PLAYER); }
        boolean roomItem(int item) { return reachable(item, floor()); }
        boolean isLit() {
            if (!rooms[state.room].dark) return true;
            for (int i = 0; i < items.length; i++) if (state.lit[i] && (carried(i) || roomItem(i))) return true;
            return false;
        }
        int totalWeight(int item) { return items[item].weight + placeWeight(inside(item)); }
        int placeWeight(Place place) { int total = 0; for (int item : direct(place)) total += totalWeight(item); return total; }
        boolean within(int item, int ancestor) {
            for (Place place = state.places[item]; place.kind == PlaceKind.INSIDE; place = state.places[place.index])
                if (place.index == ancestor) return true;
            return false;
        }
        boolean stored(int item) {
            Place place = state.places[item];
            while (place.kind == PlaceKind.INSIDE) place = state.places[place.index];
            return place.equals(Main.floor(trophy));
        }
        Treasures treasures() {
            int points = 0, stored = 0, total = 0;
            for (int i = 0; i < items.length; i++) if (items[i].treasure > 0) {
                total++; if (stored(i)) { stored++; points += items[i].treasure; }
            }
            return new Treasures(points, stored, total);
        }
        int score() { return treasures().points + state.bonus; }
        String displayName(int item) {
            var annotations = new ArrayList<String>();
            if (items[item].capacity > 0) annotations.add(state.containers[item].name().toLowerCase(Locale.ROOT));
            if (state.lit[item]) annotations.add("lit");
            return items[item].name + (annotations.isEmpty() ? "" : " (" + String.join(", ", annotations) + ")");
        }
        void itemTree(Place place, int depth) {
            for (int item : direct(place)) {
                say("  ".repeat(depth) + displayName(item));
                if (items[item].capacity > 0 && state.containers[item] == ContainerState.OPEN) itemTree(inside(item), depth + 1);
            }
        }
        void describe(boolean full) {
            if (!isLit()) { say("It is pitch dark."); return; }
            say(rooms[state.room].name);
            if (full) output.addAll(rooms[state.room].description);
            var exits = new ArrayList<String>();
            for (int d = 0; d < 6; d++) {
                var exit = state.exits[state.room][d];
                if (exit != null) exits.add(DIRECTIONS[d] + (exit.locked ? " (locked)" : ""));
            }
            say("Exits: " + (exits.isEmpty() ? "none" : String.join(", ", exits)));
            if (!direct(floor()).isEmpty()) { say("You see:"); itemTree(floor(), 1); }
        }
        String names(List<Integer> selected) { return String.join(", ", selected.stream().map(i -> items[i].name).toList()); }
        int resolve(List<String> phrase) {
            boolean lit = isLit();
            if (phrase.size() == 1 && phrase.getFirst().equals("it")) {
                if (pronoun == null) throw new Failure("I don't know what \"it\" refers to.");
                if (!carried(pronoun) && !(lit && roomItem(pronoun))) throw new Failure("You can't see any such thing.");
                return pronoun;
            }
            for (String word : phrase) if (!vocabulary.contains(word)) throw new Failure("I don't know the word \"%s\".", word);
            var matches = new ArrayList<Integer>();
            for (int i = 0; i < items.length; i++) {
                var item = items[i];
                if (!(carried(i) || lit && roomItem(i)) || !item.nouns.contains(phrase.getLast())) continue;
                if (item.nameWords.containsAll(phrase.subList(0, phrase.size() - 1))) matches.add(i);
            }
            if (matches.isEmpty()) throw new Failure("You can't see any such thing.");
            if (matches.size() > 1) throw new Failure("Which do you mean: %s?", names(matches));
            pronoun = matches.getFirst(); return pronoun;
        }
        RuleResult runRules(Trigger trigger) {
            int executed = 0; boolean message = false;
            for (Rule rule : rules) {
                if (!rule.trigger.equals(trigger) || rule.condition != null && state.flags.contains(rule.condition.flag) != rule.condition.on) continue;
                executed++;
                switch (rule.effect) {
                    case Message effect -> { say(effect.text); message = true; }
                    case OpenExit effect -> state.exits[effect.room][effect.direction] = new Exit(effect.destination, null, false);
                    case MoveItem effect -> state.places[effect.item] = effect.place;
                    case SetFlag effect -> { if (effect.on) state.flags.add(effect.flag); else state.flags.remove(effect.flag); }
                    case Points effect -> state.bonus += effect.amount;
                }
            }
            return new RuleResult(executed, message);
        }
        void turn(boolean baseline) {
            state.moves++;
            boolean[] nearby = new boolean[items.length];
            for (int i = 0; i < items.length; i++) nearby[i] = carried(i) || roomItem(i);
            for (int i = 0; i < items.length; i++) if (state.lit[i]) {
                state.fuel[i]--;
                if (state.fuel[i] == 0) { state.lit[i] = false; if (nearby[i]) sayf("The %s goes out.", items[i].name); }
            }
            boolean lit = isLit();
            if (baseline && !lit) say("It is now pitch dark."); else if (!baseline && lit) describe(true);
            state.darkness = lit ? 0 : state.darkness + 1;
            if (state.darkness == 2) say("You hear something moving in the dark.");
            if (state.darkness == 3) state.ended = EndStatus.DEAD;
            var treasure = treasures();
            if (state.ended == EndStatus.PLAYING && treasure.total > 0 && treasure.stored == treasure.total) state.ended = EndStatus.WON;
            if (state.ended != EndStatus.PLAYING) {
                say(state.ended == EndStatus.DEAD ? "*** You have died ***" : "*** You have won ***");
                sayf("You scored %d points in %d moves.", treasure.points + state.bonus, state.moves);
            }
        }
        void requireContainer(int item) {
            if (items[item].capacity == 0) throw new Failure("The %s is not a container.", items[item].name);
            if (state.containers[item] != ContainerState.OPEN) throw new Failure("The %s is closed.", items[item].name);
        }
        void putItem(int item, int container) {
            if (within(container, item)) throw new Failure("The %s is inside the %s.", items[container].name, items[item].name);
            if (state.places[item].equals(inside(container))) throw new Failure("The %s is already in the %s.", items[item].name, items[container].name);
            int weight = placeWeight(inside(container)) + (within(item, container) ? 0 : totalWeight(item));
            if (weight > items[container].capacity) throw new Failure("The %s doesn't fit in the %s.", items[item].name, items[container].name);
            state.places[item] = inside(container);
        }
        boolean take(List<String> target, List<String> from) {
            if (!isLit()) throw new Failure("It is pitch dark.");
            Integer container = null;
            Place source = floor();
            if (!from.isEmpty()) { container = resolve(from); requireContainer(container); source = inside(container); }
            if (all(target)) {
                var candidates = direct(source); candidates.removeIf(i -> items[i].fixed);
                if (candidates.isEmpty()) {
                    if (container == null) throw new Failure("There is nothing here to take.");
                    throw new Failure("There is nothing in the %s to take.", items[container].name);
                }
                boolean taken = false;
                for (int item : candidates) {
                    if (!carried(item) && placeWeight(PLAYER) + totalWeight(item) > maxWeight) sayf("%s: You can't carry any more.", items[item].name);
                    else { state.places[item] = PLAYER; sayf("%s: Taken.", items[item].name); taken = true; }
                }
                return taken;
            }
            int item = resolve(target);
            if (container != null && !state.places[item].equals(source)) throw new Failure("The %s is not in the %s.", items[item].name, items[container].name);
            if (state.places[item].equals(PLAYER)) throw new Failure("You already have the %s.", items[item].name);
            if (items[item].fixed) throw new Failure("The %s is fixed in place.", items[item].name);
            if (!carried(item) && placeWeight(PLAYER) + totalWeight(item) > maxWeight) throw new Failure("You can't carry any more.");
            state.places[item] = PLAYER; say("Taken."); return true;
        }
        void drop(List<String> target) {
            if (all(target)) {
                var candidates = direct(PLAYER);
                if (candidates.isEmpty()) throw new Failure("You are empty-handed.");
                for (int item : candidates) { state.places[item] = floor(); sayf("%s: Dropped.", items[item].name); }
            } else {
                int item = resolve(target);
                if (!carried(item)) throw new Failure("You aren't carrying the %s.", items[item].name);
                state.places[item] = floor(); say("Dropped.");
            }
        }
        boolean put(List<String> first, List<String> second) {
            Integer item = all(first) ? null : resolve(first);
            int container = resolve(second);
            if (item != null) {
                if (!carried(item)) throw new Failure("You aren't carrying the %s.", items[item].name);
                if (item == container) throw new Failure("You can't put the %s inside itself.", items[item].name);
            }
            requireContainer(container);
            if (item != null) { putItem(item, container); sayf("You put the %s in the %s.", items[item].name, items[container].name); return true; }
            var candidates = direct(PLAYER); candidates.removeIf(i -> i == container);
            if (candidates.isEmpty()) throw new Failure("You have nothing to put in the %s.", items[container].name);
            boolean moved = false;
            for (int candidate : candidates) {
                String message = "Done.";
                try { putItem(candidate, container); moved = true; } catch (Failure failure) { message = failure.getMessage(); }
                sayf("%s: %s", items[candidate].name, message);
            }
            return moved;
        }
        void keyCheck(int key, List<String> phrase) {
            if (phrase.isEmpty()) {
                if (!carried(key)) throw new Failure("You don't have the right key.");
                sayf("(with the %s)", items[key].name);
            } else {
                int item = resolve(phrase);
                if (!carried(item)) throw new Failure("You aren't carrying the %s.", items[item].name);
                if (item != key) throw new Failure("The %s doesn't fit.", items[item].name);
            }
        }
        void changeLock(List<String> target, List<String> keyPhrase, boolean locking) {
            int d = target.size() == 1 ? direction(target.getFirst()) : -1;
            String status = locking ? "already locked" : "not locked";
            if (d >= 0) {
                var exit = state.exits[state.room][d];
                if (exit == null) throw new Failure("There is no exit %s.", DIRECTIONS[d]);
                if (exit.key == null) throw new Failure("The way %s has no lock.", DIRECTIONS[d]);
                if (exit.locked == locking) throw new Failure("The way %s is %s.", DIRECTIONS[d], status);
                keyCheck(exit.key, keyPhrase);
                state.exits[state.room][d] = new Exit(exit.destination, exit.key, locking);
                var opposite = state.exits[exit.destination][d ^ 1];
                if (opposite != null && opposite.destination == state.room && Objects.equals(opposite.key, exit.key))
                    state.exits[exit.destination][d ^ 1] = new Exit(opposite.destination, opposite.key, locking);
            } else {
                int item = resolve(target);
                if (items[item].capacity == 0 || items[item].key == null) throw new Failure("The %s has no lock.", items[item].name);
                if ((state.containers[item] == ContainerState.LOCKED) == locking) throw new Failure("The %s is %s.", items[item].name, status);
                if (locking && state.containers[item] == ContainerState.OPEN) throw new Failure("You must close the %s first.", items[item].name);
                keyCheck(items[item].key, keyPhrase);
                state.containers[item] = locking ? ContainerState.LOCKED : ContainerState.CLOSED;
            }
            say(locking ? "Locked." : "Unlocked.");
        }
        void examine(int item) {
            if (items[item].details.isEmpty()) sayf("You see nothing special about the %s.", items[item].name);
            else output.addAll(items[item].details);
            if (items[item].light) sayf("It is %s (fuel %d).", state.lit[item] ? "lit" : "unlit", state.fuel[item]);
            if (items[item].capacity > 0) switch (state.containers[item]) {
                case LOCKED -> say("It is locked."); case CLOSED -> say("It is closed.");
                case OPEN -> {
                    if (direct(inside(item)).isEmpty()) say("It is empty."); else { say("It contains:"); itemTree(inside(item), 1); }
                }
            }
            if (items[item].treasure > 0) sayf("It is a treasure worth %d points.", items[item].treasure);
            sayf("It weighs %d.", totalWeight(item));
        }
        void execute(Verb verb, List<String> first, List<String> second, int d) {
            boolean baseline = isLit(), success = true;
            switch (verb) {
                case GO -> {
                    var exit = state.exits[state.room][d];
                    if (exit == null) throw new Failure("You can't go that way.");
                    if (exit.locked) throw new Failure("The way %s is locked.", DIRECTIONS[d]);
                    state.room = exit.destination; baseline = isLit();
                    describe(verbose || !state.visited[state.room]); state.visited[state.room] = true;
                    runRules(Trigger.enter(state.room));
                }
                case LOOK -> describe(true); case EXAMINE -> examine(resolve(first));
                case TAKE -> success = take(first, second); case DROP -> drop(first); case PUT -> success = put(first, second);
                case INVENTORY -> {
                    if (direct(PLAYER).isEmpty()) say("You are empty-handed.");
                    else { say("You are carrying:"); itemTree(PLAYER, 1); sayf("Total weight: %d/%d", placeWeight(PLAYER), maxWeight); }
                }
                case OPEN -> {
                    int item = resolve(first);
                    if (items[item].capacity == 0) throw new Failure("You can't open the %s.", items[item].name);
                    if (state.containers[item] == ContainerState.OPEN) throw new Failure("The %s is already open.", items[item].name);
                    if (state.containers[item] == ContainerState.LOCKED) throw new Failure("The %s is locked.", items[item].name);
                    state.containers[item] = ContainerState.OPEN;
                    var children = direct(inside(item));
                    if (children.isEmpty()) say("Opened."); else sayf("Opening the %s reveals %s.", items[item].name, names(children));
                }
                case CLOSE -> {
                    int item = resolve(first);
                    if (items[item].capacity == 0) throw new Failure("You can't close the %s.", items[item].name);
                    if (state.containers[item] != ContainerState.OPEN) throw new Failure("The %s is already closed.", items[item].name);
                    state.containers[item] = ContainerState.CLOSED; say("Closed.");
                }
                case LOCK, UNLOCK -> changeLock(first, second, verb == Verb.LOCK);
                case USE -> {
                    int a = resolve(first), b = resolve(second);
                    if (!carried(a)) throw new Failure("You aren't carrying the %s.", items[a].name);
                    var result = runRules(Trigger.use(a, b));
                    if (result.executed == 0) throw new Failure("Nothing happens.");
                    if (!result.message) say("Done.");
                }
                case LIGHT, EXTINGUISH -> {
                    int item = resolve(first); boolean lighting = verb == Verb.LIGHT;
                    if (!items[item].light) throw new Failure("You can't %s the %s.", verb.text(), items[item].name);
                    if (state.lit[item] == lighting) throw new Failure("The %s is %s.", items[item].name, lighting ? "already lit" : "not lit");
                    if (lighting && state.fuel[item] == 0) throw new Failure("The %s has no fuel.", items[item].name);
                    state.lit[item] = lighting; sayf("The %s is now %s.", items[item].name, lighting ? "lit" : "out");
                }
                case WAIT -> say("Time passes.");
                case SCORE -> {
                    var treasure = treasures();
                    sayf("You have scored %d points (treasure %d, bonus %d) in %d moves.", treasure.points + state.bonus, treasure.points, state.bonus, state.moves);
                    sayf("Treasures stored: %d of %d.", treasure.stored, treasure.total);
                }
                case SAVE -> { saved = new State(state); say("Game saved."); }
                case RESTORE -> {
                    if (saved == null) throw new Failure("There is no saved game.");
                    state = new State(saved); say("Game restored."); describe(true);
                }
                case VERBOSE -> { verbose = true; say("Verbose mode."); } case BRIEF -> { verbose = false; say("Brief mode."); }
            }
            if (success && verb.action()) turn(baseline);
        }
        void interpret(List<String> input) {
            if (input.isEmpty()) throw new Failure("I beg your pardon?");
            boolean directionWord = direction(input.getFirst()) >= 0;
            Verb verb = directionWord ? Verb.GO : Verb.parse(input.getFirst());
            if (verb == null) throw new Failure("I don't know the verb \"%s\".", input.getFirst());
            if (state.ended != EndStatus.PLAYING && verb != Verb.RESTORE) throw new Failure("The game is over.");
            List<String> first = input.subList(directionWord ? 0 : 1, input.size()), second = List.of();
            int d = -1;
            if (verb == Verb.LOOK && !first.isEmpty()) {
                if (!first.getFirst().equals("at")) throw new Failure("I don't understand that.");
                verb = Verb.EXAMINE; first = first.subList(1, first.size());
            }
            if (verb.noArguments()) {
                if (!first.isEmpty()) throw new Failure("I don't understand that.");
            } else {
                if (first.isEmpty()) {
                    if (verb == Verb.GO) throw new Failure("Which way do you want to go?");
                    throw new Failure("What do you want to %s?", verb.text());
                }
                if (verb == Verb.GO) {
                    if (first.size() == 1) d = direction(first.getFirst());
                    if (d < 0) throw new Failure("I don't understand that.");
                } else {
                    int split = -1;
                    for (int i = 0; i < first.size(); i++) {
                        String word = first.get(i);
                        boolean matches = switch (verb) {
                            case PUT -> word.equals("in") || word.equals("into"); case USE -> word.equals("on") || word.equals("with");
                            case LOCK, UNLOCK -> word.equals("with"); case TAKE -> word.equals("from"); default -> false;
                        };
                        if (matches) { split = i; break; }
                    }
                    if (split >= 0) {
                        if (split == 0 || split + 1 == first.size()) throw new Failure("I don't understand that.");
                        second = first.subList(split + 1, first.size()); first = first.subList(0, split);
                    } else if (verb == Verb.PUT || verb == Verb.USE) throw new Failure("I don't understand that.");
                }
            }
            execute(verb, first, second, d);
        }
        void process(String line) {
            say("> " + line);
            try {
                var input = words(line);
                if (!input.isEmpty() && (input.getFirst().equals("again") || input.getFirst().equals("g"))) {
                    if (input.size() != 1) throw new Failure("I don't understand that.");
                    if (previous == null) throw new Failure("There is nothing to repeat.");
                    input = words(previous);
                } else previous = line;
                interpret(input);
            } catch (Failure failure) { say(failure.getMessage()); }
        }
        void flush(BufferedWriter writer) throws IOException {
            for (String line : output) { writer.write(line); writer.write('\n'); }
            output.clear();
        }
    }

    public static void main(String[] args) throws IOException {
        var input = new BufferedReader(new InputStreamReader(System.in));
        var definitions = new ArrayList<List<String>>();
        String line;
        while (!(line = input.readLine()).equals("BEGIN")) definitions.add(List.of(line.split(" ")));
        var game = new Adventure(definitions);
        var output = new BufferedWriter(new OutputStreamWriter(System.out));
        game.describe(true); game.flush(output);
        while (!(line = input.readLine()).equals("QUIT")) { game.process(line); game.flush(output); }
        game.sayf("Final score: %d points in %d moves.", game.score(), game.state.moves);
        game.flush(output); output.flush();
    }
}
