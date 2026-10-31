import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

public class Main {
    static final Dice UNARMED = new Dice(1, 2);
    static final List<String> USAGE = List.of("picked", "quaffed", "read", "eaten", "wielded", "worn");
    static final Map<String, String> COMMAND_CLASSES = Map.of("quaff", "potion", "read", "scroll", "wield", "weapon", "wear", "armor", "eat", "food");
    static List<String[]> read(String name) throws Exception {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII).stream().map(line -> line.split(" ")).toList();
    }
    static String decimal(int a, int b) { if (b == 0) return "-"; int z = (20 * a + b) / (2 * b); return z / 10 + "." + z % 10; }
    static int[] exploration(Level level) {
        int explored = 0, total = 0;
        for (int y = 0; y < level.height; y++) for (int x = 0; x < level.width; x++) if (level.terrain[y][x] != ' ') { total++; if (level.memory[y][x] != ' ') explored++; }
        return new int[] {explored, total};
    }
    static final class Config {
        final int generationSeed, gameSeed, width, height, minSize, maxSplit, roomMin, roomMax, levels, monsterBase, monsterStep, itemBase, itemStep, sleepChance, wakeChance, radius, maxHp, regenInterval, foodStart, foodMax, foodHungry, foodWeak, packLimit;
        final Dice hitDie;
        final List<String> startItems;
        final int[] xpLevels;
        final Set<Integer> checkpoints;
        Config(List<String[]> rows) {
            Map<String, List<String>> values = new HashMap<>();
            for (String[] row : rows) values.put(row[0], List.of(row).subList(1, row.length));
            generationSeed = number(values, "seed", 0); gameSeed = number(values, "seed", 1);
            width = number(values, "map", 0); height = number(values, "map", 1);
            minSize = number(values, "bsp", 0); maxSplit = number(values, "bsp", 1);
            roomMin = number(values, "room", 0); roomMax = number(values, "room", 1); levels = number(values, "levels", 0);
            monsterBase = number(values, "monsters", 0); monsterStep = number(values, "monsters", 1);
            itemBase = number(values, "items", 0); itemStep = number(values, "items", 1);
            sleepChance = number(values, "sleep", 0); wakeChance = number(values, "sleep", 1); radius = number(values, "fov", 0);
            maxHp = number(values, "player", 0); regenInterval = number(values, "player", 1); hitDie = Dice.parse(values.get("hitdie").getFirst());
            foodStart = number(values, "food", 0); foodMax = number(values, "food", 1); foodHungry = number(values, "food", 2); foodWeak = number(values, "food", 3);
            packLimit = number(values, "pack", 0); startItems = values.get("start");
            xpLevels = values.get("xp").stream().mapToInt(Integer::parseInt).toArray(); checkpoints = values.get("checkpoints").stream().map(Integer::parseInt).collect(Collectors.toSet());
        }
        static int number(Map<String, List<String>> values, String key, int index) { return Integer.parseInt(values.get(key).get(index)); }
    }
    record Command(String name, String argument) {}
    static List<Command> commands(List<String[]> rows) {
        List<Command> commands = new ArrayList<>();
        for (String[] row : rows) {
            String name = row[0], argument = name.equals("wait") || row.length < 2 ? null : row[1];
            int count = name.equals("wait") ? row.length == 2 ? Integer.parseInt(row[1]) : 1 : row.length == 3 ? Integer.parseInt(row[2]) : 1;
            for (int i = 0; i < count; i++) commands.add(new Command(name, argument));
        }
        return commands;
    }
    static final class Player {
        int x, y, depth = 1, hp, maxHp, level = 1, xp, gold, satiation, poison;
        final List<Item> pack = new ArrayList<>();
        Item weapon, armor;
        Player(Config config, Position arrival) { x = arrival.x(); y = arrival.y(); hp = maxHp = config.maxHp; satiation = config.foodStart; }
        int defense() { return armor == null ? 10 : 10 + armor.kind.armor + armor.bonus; }
    }
    static final class AttackStats {
        int count, hits, criticals, damage;
        void record(Attack attack) { count++; if (!attack.outcome().equals("miss")) { hits++; damage += attack.damage(); } if (attack.outcome().equals("critical")) criticals++; }
        String line(String label) { return label + " " + count + " hits " + hits + " criticals " + criticals + " damage " + damage + " accuracy " + decimal(100 * hits, count); }
    }
    static final class Game {
        final Config config;
        final List<MonsterType> monsterTypes;
        final List<ItemType> itemTypes;
        final List<Command> commands;
        final Minstd generationRng, rng;
        final List<Level> levels = new ArrayList<>();
        final Player player;
        int turn = 1, succeeded, failed, unused, moves, poisonDamage, starvationDamage;
        final List<String> messages = new ArrayList<>(), mapLines = new ArrayList<>();
        boolean[][] visible;
        int[][] distance;
        String result, cause;
        final AttackStats playerAttacks = new AttackStats(), monsterAttacks = new AttackStats();
        final int[] usage = new int[6];
        final Map<String, Integer> kills = new LinkedHashMap<>();
        Game(Config config, List<MonsterType> monsterTypes, List<ItemType> itemTypes, List<Command> commands) {
            this.config = config; this.monsterTypes = monsterTypes; this.itemTypes = itemTypes; this.commands = commands;
            generationRng = new Minstd(config.generationSeed); rng = new Minstd(config.gameSeed);
            buildLevels(); player = new Player(config, levels.getFirst().arrival); giveStartItems();
            for (MonsterType kind : monsterTypes) kills.put(kind.name, 0);
        }
        void buildLevels() {
            DungeonGen generator = new DungeonGen(generationRng, config.minSize, config.maxSplit, config.roomMin, config.roomMax);
            for (int depth = 1; depth <= config.levels; depth++) {
                Level level = generator.generate(depth, config.width, config.height);
                if (depth < config.levels) level.terrain[level.target.y()][level.target.x()] = '>';
                else level.items.add(new Item(ItemType.amulet(), level.target.x(), level.target.y()));
                placeMonsters(level); placeItems(level); levels.add(level);
            }
        }
        void placeMonsters(Level level) {
            int count = config.monsterBase + config.monsterStep * (level.depth - 1);
            List<MonsterType> candidates = monsterTypes.stream().filter(kind -> kind.minDepth <= level.depth && level.depth <= kind.maxDepth).toList();
            int[] weights = candidates.stream().mapToInt(kind -> kind.weight).toArray();
            for (int number = 1; number <= count; number++) {
                MonsterType kind = candidates.get(generationRng.select(weights)); RoomCell cell;
                do { cell = level.drawRoom(generationRng); } while (cell.room() == level.arrivalRoom || level.terrain[cell.y()][cell.x()] != '.' || level.monsterAt(cell.x(), cell.y()) != null);
                int hp = kind.hp.roll(generationRng); boolean asleep = generationRng.draw() % 100 < config.sleepChance;
                level.monsters.add(new Monster(number, kind, cell.x(), cell.y(), hp, asleep));
            }
            level.monstersCreated = count;
        }
        void placeItems(Level level) {
            int count = config.itemBase + config.itemStep * (level.depth - 1);
            List<ItemType> candidates = itemTypes.stream().filter(kind -> kind.minDepth <= level.depth && level.depth <= kind.maxDepth).toList();
            int[] weights = candidates.stream().mapToInt(kind -> kind.weight).toArray();
            for (int i = 0; i < count; i++) {
                ItemType kind = candidates.get(generationRng.select(weights)); RoomCell cell;
                do { cell = level.drawRoom(generationRng); } while (level.terrain[cell.y()][cell.x()] != '.' || level.itemAt(cell.x(), cell.y()) != null);
                int amount = kind.category.equals("gold") ? kind.dice.roll(generationRng) : 0;
                level.items.add(new Item(kind, cell.x(), cell.y(), amount));
            }
            level.itemsPlaced = level.items.size();
        }
        void giveStartItems() {
            Map<String, ItemType> kinds = new HashMap<>(); for (ItemType kind : itemTypes) kinds.put(kind.name, kind);
            for (String name : config.startItems) {
                Item item = new Item(kinds.get(name), player.x, player.y); player.pack.add(item);
                if (item.kind.category.equals("weapon") && player.weapon == null) player.weapon = item;
                if (item.kind.category.equals("armor") && player.armor == null) player.armor = item;
            }
        }
        Level currentLevel() { return levels.get(player.depth - 1); }
        void say(String text) { messages.add(String.format(Locale.ROOT, "%04d %s", turn, text)); }
        String hunger() { return player.satiation > config.foodHungry ? "normal" : player.satiation > config.foodWeak ? "hungry" : player.satiation > 0 ? "weak" : "starving"; }
        void finish(String result, String cause) { this.result = result; this.cause = cause; }
        void die(String cause) { say("You die."); finish("died", cause); }
        void updateView() {
            Level level = currentLevel(); visible = Fov.fieldOfView(level, player.x, player.y, config.radius);
            for (int y = 0; y < level.height; y++) for (int x = 0; x < level.width; x++) if (visible[y][x]) { Item item = level.itemAt(x, y); level.memory[y][x] = item == null ? level.terrain[y][x] : item.symbol(); }
            for (Monster monster : level.monsters) { boolean seen = visible[monster.y][monster.x]; if (seen && !monster.wasVisible) say("You see the " + monster.kind.name + "."); monster.wasVisible = seen; }
        }
        void run() {
            updateView();
            for (Command command : commands) {
                if (result != null) unused++;
                else if (!execute(command)) failed++;
                else { succeeded++; if (result == null) advanceTurn(); }
            }
            if (result == null) finish("alive", "commands_exhausted");
        }
        void advanceTurn() {
            updateView(); monstersAct(); if (result != null) return;
            endTurn(); if (result != null) return;
            if (config.checkpoints.contains(turn)) writeCheckpoint(); turn++;
        }
        boolean execute(Command command) {
            return switch (command.name()) {
                case "move" -> { int[] direction = Fov.DIRECTIONS[Fov.NAMES.indexOf(command.argument())]; yield move(direction[0], direction[1]); }
                case "wait" -> true;
                case "pickup" -> pickup();
                case "descend" -> descend();
                default -> useItem(command.name(), Integer.parseInt(command.argument()));
            };
        }
        boolean move(int dx, int dy) {
            Level level = currentLevel(); int x = player.x + dx, y = player.y + dy;
            if (!Fov.passable(level, x, y)) { say("You bump into a wall."); return false; }
            if (!Fov.canMove(level, player.x, player.y, dx, dy)) { say("You cannot move diagonally through a door."); return false; }
            Monster monster = level.monsterAt(x, y); if (monster != null) { playerAttack(level, monster); return true; }
            player.x = x; player.y = y; moves++; Item item = level.itemAt(x, y);
            if (item != null) say("You see " + item.referenceName() + " here."); else if (level.terrain[y][x] == '>') say("There is a staircase down here.");
            return true;
        }
        boolean pickup() {
            Level level = currentLevel(); Item item = level.itemAt(player.x, player.y);
            if (item == null) { say("There is nothing here."); return false; }
            if (item.kind.category.equals("gold")) { player.gold += item.amount; say("You pick up " + item.displayName() + "."); }
            else if (item.kind.category.equals("amulet")) { say("You pick up the amulet."); say("You win!"); finish("won", "amulet"); }
            else if (player.pack.size() >= config.packLimit) { say("Your pack is full."); return false; }
            else { player.pack.add(item); say("You pick up the " + item.displayName() + " (" + player.pack.size() + ")."); }
            level.items.remove(item); level.picked++; usage[0]++; return true;
        }
        boolean descend() {
            if (currentLevel().terrain[player.y][player.x] != '>') { say("There are no stairs here."); return false; }
            player.depth++; Position arrival = currentLevel().arrival; player.x = arrival.x(); player.y = arrival.y(); say("You descend to depth " + player.depth + "."); return true;
        }
        boolean useItem(String name, int number) {
            if (number > player.pack.size()) { say("You do not have that item."); return false; }
            Item item = player.pack.get(number - 1);
            if (!item.kind.category.equals(COMMAND_CLASSES.get(name))) { say("You cannot " + name + " that."); return false; }
            return switch (name) { case "quaff" -> quaff(item); case "read" -> readScroll(item); case "wield" -> wield(item); case "wear" -> wear(item); default -> eat(item); };
        }
        boolean quaff(Item item) {
            player.pack.remove(item); usage[1]++; say("You quaff the " + item.displayName() + ".");
            switch (item.kind.effect) {
                case "heal" -> { player.hp += item.kind.dice.roll(rng); if (player.hp > player.maxHp) { player.maxHp++; player.hp = player.maxHp; } player.poison = 0; say("You feel better."); }
                case "poison" -> { player.poison += item.kind.poisonTurns; say("You feel very sick."); }
                case "level" -> { say("You feel more experienced."); if (player.level <= config.xpLevels.length) gainXp(config.xpLevels[player.level - 1] - player.xp); }
            }
            return true;
        }
        boolean readScroll(Item item) {
            Level level = currentLevel(); player.pack.remove(item); usage[2]++; say("You read the " + item.displayName() + ".");
            switch (item.kind.effect) {
                case "mapping" -> { for (int y = 0; y < level.height; y++) for (int x = 0; x < level.width; x++) if (level.terrain[y][x] != ' ' && level.memory[y][x] == ' ') level.memory[y][x] = level.terrain[y][x]; say("A map forms in your mind."); }
                case "teleport" -> { RoomCell cell; do { cell = level.drawRoom(rng); } while (cell.x() == player.x && cell.y() == player.y || level.monsterAt(cell.x(), cell.y()) != null); player.x = cell.x(); player.y = cell.y(); say("You are teleported."); }
                case "enchant_weapon" -> { if (player.weapon == null) say("Your hands twitch."); else { say("Your " + player.weapon.displayName() + " glows blue."); player.weapon.bonus++; } }
                case "enchant_armor" -> { if (player.armor == null) say("Your skin tingles."); else { say("Your " + player.armor.displayName() + " glows silver."); player.armor.bonus++; } }
            }
            return true;
        }
        boolean wield(Item item) { if (item == player.weapon) { say("You are already wielding that."); return false; } player.weapon = item; usage[4]++; say("You are now wielding the " + item.displayName() + "."); return true; }
        boolean wear(Item item) { if (item == player.armor) { say("You are already wearing that."); return false; } player.armor = item; usage[5]++; say("You are now wearing the " + item.displayName() + "."); return true; }
        boolean eat(Item item) { player.pack.remove(item); usage[3]++; player.satiation = Math.min(player.satiation + item.kind.nutrition, config.foodMax); say("You eat the " + item.displayName() + "."); return true; }
        void playerAttack(Level level, Monster monster) {
            Item weapon = player.weapon; monster.asleep = false;
            int toHit = player.level + (weapon == null ? 0 : weapon.kind.toHit + weapon.bonus), bonus = weapon == null ? 0 : weapon.bonus;
            Dice dice = weapon == null ? UNARMED : weapon.kind.dice; if (hunger().equals("weak") || hunger().equals("starving")) toHit -= 2;
            String name = monster.kind.name; Attack attack = Combat.resolve(rng, toHit, monster.kind.defense, dice, bonus); playerAttacks.record(attack);
            if (attack.outcome().equals("miss")) { say("You miss the " + name + "."); return; }
            say("You hit the " + name + (attack.outcome().equals("critical") ? " hard for " : " for ") + attack.damage() + "."); monster.hp -= attack.damage();
            if (monster.hp <= 0) { say("You kill the " + name + "."); level.monsters.remove(monster); level.kills++; kills.put(name, kills.get(name) + 1); gainXp(monster.kind.xp); }
        }
        void gainXp(int amount) {
            player.xp += amount;
            while (player.level <= config.xpLevels.length && player.xp >= config.xpLevels[player.level - 1]) { player.level++; int gained = config.hitDie.roll(rng); player.maxHp += gained; player.hp += gained; say("Welcome to level " + player.level + "."); }
        }
        void monsterAttack(Monster monster) {
            MonsterType kind = monster.kind; Attack attack = Combat.resolve(rng, kind.toHit, player.defense(), kind.damage, 0); monsterAttacks.record(attack);
            if (attack.outcome().equals("miss")) { say("The " + kind.name + " misses you."); return; }
            say("The " + kind.name + (attack.outcome().equals("critical") ? " hits you hard for " : " hits you for ") + attack.damage() + "."); player.hp -= attack.damage();
            if (player.hp <= 0) die("killed_by " + kind.name); else if (kind.poisonous) { player.poison += 5; say("You are poisoned."); }
        }
        void monstersAct() {
            Level level = currentLevel(); distance = Fov.distances(level, player.x, player.y);
            for (Monster monster : level.monsters) {
                monster.energy += monster.kind.speed;
                while (monster.energy >= 2) { monster.energy -= 2; monsterAction(level, monster); if (result != null) return; }
            }
        }
        void monsterAction(Level level, Monster monster) {
            boolean sees = visible[monster.y][monster.x];
            if (monster.asleep) { if (sees && rng.draw() % 100 < config.wakeChance) { monster.asleep = false; say("The " + monster.kind.name + " wakes up."); } }
            else if (monster.kind.stationary) { if (canAttack(level, monster)) monsterAttack(monster); }
            else if (monster.kind.erratic && rng.draw() % 2 == 0) wander(level, monster);
            else if (sees) chase(level, monster);
            else wander(level, monster);
        }
        boolean canAttack(Level level, Monster monster) { int dx = player.x - monster.x, dy = player.y - monster.y; return Math.max(Math.abs(dx), Math.abs(dy)) == 1 && Fov.canMove(level, monster.x, monster.y, dx, dy); }
        void wander(Level level, Monster monster) {
            int[] direction = Fov.DIRECTIONS[rng.draw() % 8];
            if (!Fov.canMove(level, monster.x, monster.y, direction[0], direction[1])) return;
            int x = monster.x + direction[0], y = monster.y + direction[1];
            if (x == player.x && y == player.y) monsterAttack(monster); else if (level.monsterAt(x, y) == null) { monster.x = x; monster.y = y; }
        }
        void chase(Level level, Monster monster) {
            if (canAttack(level, monster)) { monsterAttack(monster); return; }
            int here = distance[monster.y][monster.x], bestDistance = 0; Position best = null;
            for (int[] direction : Fov.DIRECTIONS) {
                if (!Fov.canMove(level, monster.x, monster.y, direction[0], direction[1])) continue;
                int x = monster.x + direction[0], y = monster.y + direction[1], next = distance[y][x];
                if (next < 0 || here >= 0 && next >= here || level.monsterAt(x, y) != null || x == player.x && y == player.y) continue;
                if (best == null || next < bestDistance) { best = new Position(x, y); bestDistance = next; }
            }
            if (best != null) { monster.x = best.x(); monster.y = best.y(); }
        }
        void endTurn() {
            for (Monster monster : currentLevel().monsters) if (monster.kind.regenerates && monster.hp < monster.maxHp) monster.hp++;
            if (player.poison > 0) { player.hp--; poisonDamage++; if (player.hp <= 0) { die("poison"); return; } player.poison--; if (player.poison == 0) say("You feel less sick."); }
            if (player.satiation == 0) { player.hp--; starvationDamage++; if (player.hp <= 0) { die("starvation"); return; } }
            else { String before = hunger(); player.satiation--; String after = hunger(); if (!after.equals(before)) say(switch (after) { case "hungry" -> "You are getting hungry."; case "weak" -> "You feel weak from hunger."; default -> "You are starving."; }); }
            if (turn % config.regenInterval == 0 && player.poison == 0 && player.satiation > 0 && player.hp < player.maxHp) player.hp++;
        }
        char viewSymbol(Level level, int x, int y) {
            if (x == player.x && y == player.y) return '@'; Monster monster = level.monsterAt(x, y); if (monster != null) return monster.kind.symbol;
            Item item = level.itemAt(x, y); return item == null ? level.terrain[y][x] : item.symbol();
        }
        List<String> mapRows(Level level, boolean current) {
            String border = "+" + "-".repeat(level.width) + "+"; List<String> lines = new ArrayList<>(List.of(border));
            for (int y = 0; y < level.height; y++) { StringBuilder row = new StringBuilder("|"); for (int x = 0; x < level.width; x++) row.append(current && visible[y][x] ? viewSymbol(level, x, y) : level.memory[y][x]); row.append('|'); lines.add(row.toString()); }
            lines.add(border); return lines;
        }
        String status() { return "STATUS hp " + player.hp + "/" + player.maxHp + " level " + player.level + " xp " + player.xp + " defense " + player.defense() + " gold " + player.gold + " food " + player.satiation + " " + hunger() + " poison " + player.poison; }
        void writeCheckpoint() { mapLines.add("CHECKPOINT turn " + turn + " depth " + player.depth); mapLines.addAll(mapRows(currentLevel(), true)); mapLines.add(status()); }
        List<String> finalBlock() {
            List<String> lines = new ArrayList<>(List.of("FINAL turn " + succeeded + " depth " + player.depth));
            for (Level level : levels.subList(0, player.depth)) { int[] explored = exploration(level); lines.add("LEVEL " + level.depth + " explored " + explored[0] + "/" + explored[1]); lines.addAll(mapRows(level, level.depth == player.depth)); }
            lines.add(status()); return lines;
        }
        String itemLabel(Item item) { return item == null ? "-" : item.displayName(); }
        List<String> stats() {
            List<String> lines = new ArrayList<>(List.of("result " + result, "cause " + cause, "turns " + succeeded, "depth " + player.depth, "level " + player.level, "xp " + player.xp, "hp " + player.hp + "/" + player.maxHp, "defense " + player.defense(), "gold " + player.gold, "food " + player.satiation + " " + hunger(), "poison " + player.poison,
                "weapon " + itemLabel(player.weapon), "armor " + itemLabel(player.armor), "commands " + commands.size() + " executed " + succeeded + " failed " + failed + " unused " + unused, "moves " + moves, playerAttacks.line("player_attacks"), monsterAttacks.line("monster_attacks"), "poison_damage " + poisonDamage + " starvation_damage " + starvationDamage));
            List<String> usages = new ArrayList<>(); for (int i = 0; i < usage.length; i++) usages.add(USAGE.get(i) + " " + usage[i]); lines.add(String.join(" ", usages)); lines.add("kills " + kills.values().stream().mapToInt(Integer::intValue).sum());
            for (MonsterType kind : monsterTypes) if (kills.get(kind.name) > 0) lines.add("KILL " + kind.name + " " + kills.get(kind.name));
            for (Level level : levels) { int[] explored = exploration(level); lines.add("LEVEL " + level.depth + " rooms " + level.rooms.size() + " explored " + explored[0] + "/" + explored[1] + " " + decimal(100 * explored[0], explored[1]) + " monsters " + level.kills + "/" + level.monstersCreated + " items " + level.picked + "/" + level.itemsPlaced); }
            for (int i = 0; i < player.pack.size(); i++) { Item item = player.pack.get(i); lines.add("INVENTORY " + (i + 1) + " " + item.displayName() + (item == player.weapon ? " (wielded)" : item == player.armor ? " (worn)" : "")); }
            return lines;
        }
    }
    public static void main(String[] args) throws Exception {
        Config config = new Config(read("config.txt")); List<MonsterType> monsters = read("monsters.txt").stream().map(MonsterType::new).toList(); List<ItemType> items = read("items.txt").stream().map(ItemType::parse).toList();
        Game game = new Game(config, monsters, items, commands(read("commands.txt"))); game.run();
        List<String> maps = new ArrayList<>(game.mapLines); maps.addAll(game.finalBlock());
        Map<String, List<String>> files = Map.of("messages.txt", game.messages, "maps.txt", maps, "stats.txt", game.stats()); Files.createDirectories(Path.of("output"));
        for (var entry : files.entrySet()) Files.writeString(Path.of("output", entry.getKey()), entry.getValue().isEmpty() ? "" : String.join("\n", entry.getValue()) + "\n", StandardCharsets.US_ASCII);
    }
}
