import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

public final class Main {
    static final String WAVE_COLUMNS = "wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives";
    static final List<String> INCOME_FIELDS = List.of("bounty", "reward", "interest", "early", "refund");
    static List<String> read(String name) throws IOException { return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII); }
    static void write(String name, List<String> lines) throws IOException { Files.writeString(Path.of("output", name), lines.isEmpty() ? "" : String.join("\n", lines) + "\n", StandardCharsets.US_ASCII); }
    static String oneDecimal(long numerator, long denominator) { if (denominator == 0) return "-"; long rounded = (20 * numerator + denominator) / (2 * denominator); return rounded / 10 + "." + rounded % 10; }
    static char digit(int count) { return count == 0 ? '.' : count < 10 ? (char) ('0' + count) : '*'; }
    static String csv(List<?> values) { return String.join(",", values.stream().map(Object::toString).toList()); }
    static List<String> ruled(char[][] rows) {
        StringBuilder ruler = new StringBuilder("  ");
        for (int x = 0; x < rows[0].length; x++) ruler.append(x % 10);
        List<String> lines = new ArrayList<>(List.of(ruler.toString()));
        for (int y = 0; y < rows.length; y++) lines.add(y % 10 + " " + new String(rows[y]));
        return lines;
    }

    static final class Params {
        final int gold, lives, interestRate, interestCap, sellRate, start, interval, early;
        final Set<Integer> snapshots = new HashSet<>();
        Params(List<String> lines) {
            List<String[]> fields = lines.stream().map(line -> line.split(" ")).toList();
            gold = Integer.parseInt(fields.get(0)[1]); lives = Integer.parseInt(fields.get(1)[1]);
            interestRate = Integer.parseInt(fields.get(2)[1]); interestCap = Integer.parseInt(fields.get(2)[2]); sellRate = Integer.parseInt(fields.get(3)[1]);
            start = Integer.parseInt(fields.get(4)[1]); interval = Integer.parseInt(fields.get(4)[2]); early = Integer.parseInt(fields.get(5)[1]);
            for (int i = 1; i < fields.get(6).length; i++) snapshots.add(Integer.parseInt(fields.get(6)[i]));
        }
    }
    record Action(int tick, String command, List<String> arguments) {
        static Action parse(String line) { List<String> fields = List.of(line.split(" ")); return new Action(Integer.parseInt(fields.get(0)), fields.get(1), fields.subList(2, fields.size())); }
    }
    static final class WaveRecord {
        final int number, start;
        final Wave plan;
        final int[] released;
        final Map<Integer, Integer> towerDamage = new HashMap<>();
        int end, spawned, peak, kills, leaks, livesLost, bounty, reward, interest, gold, lives;
        String status = "";
        WaveRecord(int number, Wave plan, int start) { this.number = number; this.plan = plan; this.start = start; released = new int[plan.groups.size()]; }
        boolean allReleased() { for (int i = 0; i < released.length; i++) if (released[i] != plan.groups.get(i).count()) return false; return true; }
        void close(String status, int tick, int gold, int lives) { this.status = status; end = tick; this.gold = gold; this.lives = lives; }
        String row(int towerCount) {
            List<Object> values = new ArrayList<>(List.of(number, start, end, status, spawned, peak, kills, leaks, livesLost, bounty, reward, interest, gold, lives));
            for (int number = 1; number <= towerCount; number++) values.add(towerDamage.getOrDefault(number, 0));
            return csv(values);
        }
    }

    static final class Game {
        final GridMap grid;
        final Map<String, TowerType> towerTypes = new HashMap<>();
        final Map<String, EnemyType> enemyTypes;
        final List<Wave> waves;
        final Params params;
        final Point exitCenter;
        final List<Tower> towers = new ArrayList<>();
        final List<Enemy> enemies = new ArrayList<>(), allEnemies = new ArrayList<>();
        List<Projectile> projectiles = new ArrayList<>();
        final List<WaveRecord> records = new ArrayList<>();
        final Map<String, Integer> income = new LinkedHashMap<>();
        final List<String> events = new ArrayList<>(), snapshots = new ArrayList<>();
        final int[][] killCounts;
        DistanceField field;
        WaveRecord active;
        Integer nextStart;
        String outcome;
        int tick, gold, lives, projectileCount, spent, done, refused;

        Game(GridMap grid, List<TowerType> towerTypes, WaveData waveData, Params params) {
            this.grid = grid; for (TowerType type : towerTypes) this.towerTypes.put(type.name(), type);
            enemyTypes = waveData.types(); waves = waveData.waves(); this.params = params; exitCenter = grid.exit.center();
            gold = params.gold; lives = params.lives; nextStart = params.start; field = new DistanceField(grid, Set.of()); killCounts = new int[grid.height][grid.width];
            for (String name : INCOME_FIELDS) income.put(name, 0);
        }
        void record(Object... parts) { events.add(tick + (parts.length == 0 ? "" : " " + String.join(" ", Arrays.stream(parts).map(Object::toString).toList()))); }
        void addIncome(String name, int amount) { income.put(name, income.get(name) + amount); }
        List<Tower> standingTowers() { return towers.stream().filter(Tower::standing).toList(); }
        Set<Cell> towerCells() { Set<Cell> cells = new HashSet<>(); for (Tower tower : standingTowers()) cells.add(tower.cell); return cells; }
        Tower towerAt(Cell cell) { for (Tower tower : towers) if (tower.standing() && tower.cell.equals(cell)) return tower; return null; }
        Tower standingTower(String text) { int number = Integer.parseInt(text); return number >= 1 && number <= towers.size() && towers.get(number - 1).standing() ? towers.get(number - 1) : null; }
        List<Enemy> groundEnemies() { return enemies.stream().filter(enemy -> !enemy.flying()).toList(); }

        void run(List<Action> actions) {
            int index = 0;
            while (true) {
                tick++;
                while (index < actions.size() && actions.get(index).tick == tick) perform(actions.get(index++));
                spawnEnemies(); moveEnemies();
                if (outcome != null) break;
                fireTowers(); moveProjectiles(); checkWaveEnd();
                if (params.snapshots.contains(tick)) snapshots.addAll(block("SNAPSHOT"));
                if (outcome != null) break;
            }
            snapshots.addAll(finalBlock());
        }
        void perform(Action action) {
            boolean success = switch (action.command) {
                case "BUILD" -> build(action.arguments);
                case "UPGRADE" -> upgrade(action.arguments);
                case "SELL" -> sell(action.arguments);
                case "TARGET" -> setTarget(action.arguments);
                default -> callWave();
            };
            if (success) done++; else refused++;
        }
        String buildRefusal(String name, Cell cell) {
            if (!towerTypes.containsKey(name)) return "type";
            if (!grid.inside(cell)) return "bounds";
            if (!grid.buildable(cell)) return "terrain";
            if (towerAt(cell) != null) return "tower";
            if (gold < towerTypes.get(name).levels().getFirst().cost()) return "gold";
            List<Enemy> walkers = groundEnemies();
            for (Enemy enemy : walkers) if (enemy.cell.equals(cell) || enemy.next.equals(cell)) return "enemy";
            Set<Cell> blocked = towerCells(); blocked.add(cell);
            DistanceField trial = new DistanceField(grid, blocked);
            for (Cell spawn : grid.spawns) if (trial.at(spawn) < 0) return "blocked";
            for (Enemy enemy : walkers) if (trial.at(enemy.next) < 0) return "blocked";
            return null;
        }
        boolean build(List<String> args) {
            String name = args.get(0); Cell cell = new Cell(Integer.parseInt(args.get(1)), Integer.parseInt(args.get(2)));
            String reason = buildRefusal(name, cell);
            if (reason != null) { record("BUILD_REFUSED", name, args.get(1), args.get(2), reason); return false; }
            TowerType kind = towerTypes.get(name); int cost = kind.levels().getFirst().cost();
            Tower tower = new Tower(towers.size() + 1, kind, cell, tick); towers.add(tower); gold -= cost; spent += cost;
            record("BUILD", "T" + tower.number, name, cell.x(), cell.y(), "cost", cost, "gold", gold); updateField(); return true;
        }
        boolean upgrade(List<String> args) {
            Tower tower = standingTower(args.getFirst()); String reason;
            if (tower == null) reason = "notower";
            else if (tower.level == tower.kind.levels().size()) reason = "maxlevel";
            else if (gold < tower.kind.levels().get(tower.level).cost()) reason = "gold";
            else {
                int cost = tower.kind.levels().get(tower.level).cost(); gold -= cost; spent += cost; tower.level++; tower.investment += cost;
                record("UPGRADE", "T" + tower.number, "level", tower.level, "cost", cost, "gold", gold); return true;
            }
            record("UPGRADE_REFUSED", "T" + args.getFirst(), reason); return false;
        }
        boolean sell(List<String> args) {
            Tower tower = standingTower(args.getFirst());
            if (tower == null) { record("SELL_REFUSED", "T" + args.getFirst(), "notower"); return false; }
            int rate = tick == tower.built ? 100 : params.sellRate, refund = tower.investment * rate / 100;
            tower.sold = tick; gold += refund; addIncome("refund", refund); record("SELL", "T" + tower.number, "refund", refund, "gold", gold); updateField(); return true;
        }
        boolean setTarget(List<String> args) {
            Tower tower = standingTower(args.get(0)); String reason;
            if (tower == null) reason = "notower";
            else if (!Towers.TARGET_MODES.contains(args.get(1))) reason = "mode";
            else { tower.mode = args.get(1); record("TARGET", "T" + tower.number, tower.mode); return true; }
            record("TARGET_REFUSED", "T" + args.get(0), reason); return false;
        }
        boolean callWave() {
            if (active != null) { record("CALL_REFUSED", "active"); return false; }
            int bonus = (nextStart - tick) * params.early; gold += bonus; addIncome("early", bonus); nextStart = tick;
            record("CALL", records.size() + 1, "bonus", bonus, "gold", gold); return true;
        }
        void updateField() {
            DistanceField before = field; field = new DistanceField(grid, towerCells());
            for (int i = 0; i < grid.spawns.size(); i++) { Cell spawn = grid.spawns.get(i); if (before.at(spawn) != field.at(spawn)) record("REPATH", i + 1, before.at(spawn), field.at(spawn)); }
        }
        void startWave() {
            Wave plan = waves.get(records.size()); active = new WaveRecord(records.size() + 1, plan, tick); records.add(active); nextStart = null;
            record("WAVE_START", active.number, "enemies", plan.enemyCount());
        }
        void addEnemy(Enemy enemy) { enemies.add(enemy); allEnemies.add(enemy); active.spawned++; enemy.kind.spawned++; }
        void removeEnemy(Enemy enemy) { enemy.alive = false; enemies.remove(enemy); }
        void spawnEnemies() {
            if (nextStart != null && tick == nextStart) startWave();
            if (active == null) return;
            for (int i = 0; i < active.plan.groups.size(); i++) {
                Group group = active.plan.groups.get(i); int released = active.released[i];
                if (released == group.count() || group.spawnTick(active.start, released) != tick) continue;
                active.released[i]++; Cell spawn = grid.spawns.get(group.spawn() - 1); Enemy enemy = new Enemy(allEnemies.size() + 1, group.kind(), group.multiplier());
                if (enemy.flying()) enemy.point = spawn.center(); else { enemy.cell = spawn; enemy.next = field.next(spawn); }
                addEnemy(enemy); record("SPAWN", "E" + enemy.number, enemy.kind.name, group.spawn(), "hp", enemy.hp);
            }
            active.peak = Math.max(active.peak, enemies.size());
        }
        void moveEnemies() { for (Enemy enemy : new ArrayList<>(enemies)) { moveEnemy(enemy); if (outcome != null) return; } }
        void moveEnemy(Enemy enemy) {
            if (enemy.burn.active()) {
                Tower source = towers.get(enemy.burn.source - 1); int damage = Math.min(enemy.hp, enemy.burn.strength); enemy.hp -= damage; credit(source, enemy, damage); enemy.burn.advanceTime();
                if (enemy.hp == 0) { kill(enemy, source); return; }
            }
            enemy.hp = Math.min(enemy.hp + enemy.kind.regen, enemy.maxHp);
            int speed = enemy.slowedSpeed(); if (enemy.slow.active()) enemy.slow.advanceTime();
            boolean arrived;
            if (enemy.flying()) { Combat.Advance movement = Combat.advance(enemy.point, exitCenter, speed); enemy.point = movement.point(); arrived = movement.arrived(); }
            else arrived = walk(enemy, speed);
            if (arrived) leak(enemy);
        }
        boolean walk(Enemy enemy, int speed) {
            if (grid.water(enemy.occupiedCell())) speed /= 2;
            while (speed > 0) {
                int rest = 100 - enemy.progress;
                if (speed < rest) { enemy.progress += speed; speed = 0; }
                else { speed -= rest; enemy.cell = enemy.next; enemy.progress = 0; if (enemy.cell.equals(grid.exit)) return true; enemy.next = field.next(enemy.cell); }
            }
            return false;
        }
        void leak(Enemy enemy) {
            removeEnemy(enemy); int lost = Math.min(lives, enemy.kind.lives); lives -= lost; active.leaks++; active.livesLost += lost; enemy.kind.leaks++;
            record("LEAK", "E" + enemy.number, enemy.kind.name, "lives", lives);
            if (lives == 0) { record("DEFEAT"); outcome = "defeat"; active.close("lost", tick, gold, lives); active = null; }
        }
        void fireTowers() {
            for (Tower tower : standingTowers()) {
                if (tick < tower.ready) continue;
                Enemy target = tower.selectTarget(enemies, field);
                if (target != null) {
                    projectileCount++; projectiles.add(new Projectile(projectileCount, tower, target)); tower.shots++; tower.ready = tick + tower.stats().interval(); record("SHOT", "T" + tower.number, "E" + target.number);
                }
            }
        }
        void moveProjectiles() {
            List<Projectile> flying = new ArrayList<>();
            for (Projectile projectile : projectiles) {
                Enemy target = allEnemies.get(projectile.target - 1); if (target.alive) projectile.aim = target.position();
                if (projectile.fly()) impact(projectile); else flying.add(projectile);
            }
            projectiles = flying;
        }
        void impact(Projectile projectile) {
            Tower tower = towers.get(projectile.tower - 1); Enemy target = allEnemies.get(projectile.target - 1); List<Enemy> victims;
            if (projectile.stats.splash() == 0) victims = target.alive ? List.of(target) : List.of();
            else victims = enemies.stream().filter(enemy -> Towers.canAim(projectile.targets, enemy) && Combat.squaredDistance(enemy.position(), projectile.aim) <= (long) projectile.stats.splash() * projectile.stats.splash()).toList();
            if (victims.isEmpty()) tower.fizzles++;
            for (Enemy enemy : victims) {
                tower.hits++; int damage = Combat.damage(enemy.hp, projectile.stats.power(), enemy.kind.armor); enemy.hp -= damage; credit(tower, enemy, damage);
                if (enemy.hp == 0) { kill(enemy, tower); continue; }
                if (projectile.stats.slowRate() > 0) enemy.slow.receive(projectile.stats.slowRate(), projectile.stats.slowTime(), 0);
                if (projectile.stats.burnAmount() > 0) enemy.burn.receive(projectile.stats.burnAmount(), projectile.stats.burnTime(), tower.number);
            }
        }
        void credit(Tower tower, Enemy enemy, int damage) { tower.damage += damage; enemy.kind.damage += damage; active.towerDamage.merge(tower.number, damage, Integer::sum); }
        void kill(Enemy enemy, Tower tower) {
            removeEnemy(enemy); Cell cell = enemy.occupiedCell(); killCounts[cell.y()][cell.x()]++; int bounty = enemy.kind.bounty;
            tower.kills++; active.kills++; enemy.kind.kills++; gold += bounty; active.bounty += bounty; addIncome("bounty", bounty);
            record("KILL", "E" + enemy.number, enemy.kind.name, "T" + tower.number, "bounty", bounty, "gold", gold);
            for (int i = 0; i < enemy.kind.splitCount; i++) { Enemy child = enemy.split(allEnemies.size() + 1); addEnemy(child); record("SPAWN", "E" + child.number, child.kind.name, "E" + enemy.number, "hp", child.hp); }
        }
        void checkWaveEnd() {
            if (active == null || !enemies.isEmpty() || !active.allReleased()) return;
            WaveRecord wave = active; int reward = wave.plan.reward; gold += reward; int interest = Math.min(params.interestCap, gold * params.interestRate / 100); gold += interest;
            wave.reward = reward; wave.interest = interest; addIncome("reward", reward); addIncome("interest", interest); active = null;
            record("WAVE_END", wave.number, "reward", reward, "interest", interest, "gold", gold);
            if (wave.number == waves.size()) { record("VICTORY"); outcome = "victory"; }
            else nextStart = tick + params.interval;
            wave.close("cleared", tick, gold, lives);
        }
        char[][] mapPicture() {
            char[][] rows = grid.rows.stream().map(String::toCharArray).toArray(char[][]::new);
            for (Cell spawn : grid.spawns) for (Cell cell : field.path(spawn)) if (grid.terrain(cell) == '.' || grid.terrain(cell) == '~') rows[cell.y()][cell.x()] = '+';
            for (Tower tower : standingTowers()) rows[tower.cell.y()][tower.cell.x()] = tower.kind.symbol();
            Map<Cell, List<Enemy>> occupants = new HashMap<>();
            for (Enemy enemy : enemies) occupants.computeIfAbsent(enemy.occupiedCell(), key -> new ArrayList<>()).add(enemy);
            for (var entry : occupants.entrySet()) rows[entry.getKey().y()][entry.getKey().x()] = entry.getValue().size() == 1 ? entry.getValue().getFirst().kind.symbol : '*';
            return rows;
        }
        char[][] flowPicture() {
            char[][] rows = new char[grid.height][grid.width];
            for (int y = 0; y < grid.height; y++) for (int x = 0; x < grid.width; x++) {
                Cell cell = new Cell(x, y); char terrain = grid.terrain(cell); Tower tower = towerAt(cell);
                rows[y][x] = terrain == '#' || terrain == 'E' ? terrain : tower != null ? tower.kind.symbol() : field.at(cell) < 0 ? '?' : "^>v<".charAt(field.direction(cell));
            }
            return rows;
        }
        char[][] coveragePicture() {
            char[][] rows = new char[grid.height][grid.width]; List<Tower> standing = standingTowers();
            for (int y = 0; y < grid.height; y++) for (int x = 0; x < grid.width; x++) {
                Cell cell = new Cell(x, y); Tower tower = towerAt(cell);
                if (grid.rock(cell)) rows[y][x] = '#';
                else if (tower != null) rows[y][x] = tower.kind.symbol();
                else { int count = 0; for (Tower other : standing) if (other.inRange(cell.center())) count++; rows[y][x] = digit(count); }
            }
            return rows;
        }
        char[][] killsPicture() {
            char[][] rows = new char[grid.height][grid.width];
            for (int y = 0; y < grid.height; y++) for (int x = 0; x < grid.width; x++) rows[y][x] = killCounts[y][x] > 0 ? digit(killCounts[y][x]) : grid.rock(new Cell(x, y)) ? '#' : '.';
            return rows;
        }
        List<String> block(String label) {
            String next = active == null && outcome == null ? nextStart.toString() : "-";
            List<String> lines = new ArrayList<>(List.of(label + " " + tick + " wave " + records.size() + " next " + next + " gold " + gold + " lives " + lives));
            lines.addAll(ruled(mapPicture()));
            for (int i = 0; i < grid.spawns.size(); i++) lines.add("PATH " + (i + 1) + " length " + field.at(grid.spawns.get(i)));
            for (Tower tower : standingTowers()) lines.add("T" + tower.number + " " + tower.kind.name() + " " + tower.cell.x() + " " + tower.cell.y() + " level " + tower.level + " mode " + tower.mode + " ready " + tower.ready);
            for (Enemy enemy : enemies) { Point point = enemy.position(); lines.add("E" + enemy.number + " " + enemy.kind.name + " " + point.x() + " " + point.y() + " hp " + enemy.hp + "/" + enemy.maxHp + " slow " + enemy.slow.strength + " " + enemy.slow.remaining + " burn " + enemy.burn.strength + " " + enemy.burn.remaining); }
            for (Projectile projectile : projectiles) lines.add("P" + projectile.number + " T" + projectile.tower + " E" + projectile.target + " " + projectile.position.x() + " " + projectile.position.y());
            return lines;
        }
        List<String> finalBlock() {
            List<String> lines = block("FINAL"); lines.add("FLOW"); lines.addAll(ruled(flowPicture())); lines.add("COVERAGE"); lines.addAll(ruled(coveragePicture())); lines.add("KILLS"); lines.addAll(ruled(killsPicture())); return lines;
        }
        List<String> waveLines() {
            StringBuilder header = new StringBuilder(WAVE_COLUMNS); for (Tower tower : towers) header.append(",T").append(tower.number);
            List<String> lines = new ArrayList<>(List.of(header.toString())); for (WaveRecord wave : records) lines.add(wave.row(towers.size())); return lines;
        }
        String mvpLine() {
            Tower best = null; for (Tower tower : towers) if (best == null || tower.damage > best.damage) best = tower;
            return best == null ? "mvp -" : "mvp T" + best.number + " damage " + best.damage;
        }
        String towerLine(Tower tower, int totalDamage) {
            String state = tower.standing() ? "active" : "sold " + tower.sold;
            return "TOWER T" + tower.number + " " + tower.kind.name() + " " + tower.cell.x() + " " + tower.cell.y() + " level " + tower.level + " mode " + tower.mode + " " + state + " shots " + tower.shots + " hits " + tower.hits + " fizzles " + tower.fizzles + " kills " + tower.kills + " damage " + tower.damage + " per_shot " + oneDecimal(tower.damage, tower.shots) + " share " + oneDecimal(100L * tower.damage, totalDamage) + " invested " + tower.investment;
        }
        List<String> summaryLines(int actionCount) {
            List<WaveRecord> cleared = records.stream().filter(wave -> wave.status.equals("cleared")).toList();
            long perfect = cleared.stream().filter(wave -> wave.leaks == 0).count();
            int spawned = 0, killed = 0, leaked = 0, totalDamage = 0;
            for (EnemyType type : enemyTypes.values()) { spawned += type.spawned; killed += type.kills; leaked += type.leaks; }
            for (Tower tower : towers) totalDamage += tower.damage;
            long score = 10L * killed + 100L * lives + 50 * perfect + gold;
            List<String> incomeParts = new ArrayList<>(); for (String name : INCOME_FIELDS) incomeParts.add(name + " " + income.get(name));
            List<String> lines = new ArrayList<>(List.of("outcome " + outcome, "ticks " + tick, "waves " + cleared.size() + "/" + waves.size() + " perfect " + perfect, "lives " + lives + "/" + params.lives, "gold " + gold,
                "enemies spawned " + spawned + " killed " + killed + " leaked " + leaked, "income " + String.join(" ", incomeParts), "spent " + spent, "damage " + totalDamage,
                "actions total " + actionCount + " done " + done + " refused " + refused + " unused " + (actionCount - done - refused), "score " + score, mvpLine()));
            for (EnemyType type : enemyTypes.values()) lines.add("ENEMY " + type.name + " spawned " + type.spawned + " killed " + type.kills + " leaked " + type.leaks + " damage " + type.damage);
            for (Tower tower : towers) lines.add(towerLine(tower, totalDamage));
            return lines;
        }
    }

    public static void main(String[] args) throws IOException {
        GridMap grid = GridMap.read(); List<TowerType> towerTypes = Towers.parse(read("towers.txt")); WaveData waveData = Enemies.parse(read("waves.txt"));
        List<Action> actions = read("actions.txt").stream().map(Action::parse).toList(); Params params = new Params(read("params.txt"));
        Game game = new Game(grid, towerTypes, waveData, params); game.run(actions); Files.createDirectories(Path.of("output"));
        write("events.txt", game.events); write("waves.csv", game.waveLines()); write("snapshots.txt", game.snapshots); write("summary.txt", game.summaryLines(actions.size()));
    }
}
