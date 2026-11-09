import java.util.*;

record Level(int cost, int range, int power, int interval, int shotSpeed, int splash, int slowRate, int slowTime, int burnAmount, int burnTime) {
    static Level parse(String line) {
        int[] values = Arrays.stream(line.split(" ")).skip(1).mapToInt(Integer::parseInt).toArray();
        return new Level(values[0], values[1], values[2], values[3], values[4], values[5], values[6], values[7], values[8], values[9]);
    }
}
record TowerType(String name, char symbol, String targets, List<Level> levels) {}

final class Towers {
    static final Set<String> TARGET_MODES = Set.of("FIRST", "LAST", "STRONGEST", "WEAKEST", "CLOSEST");
    static List<TowerType> parse(List<String> lines) {
        List<TowerType> types = new ArrayList<>();
        for (int index = 0; index < lines.size();) {
            String[] fields = lines.get(index).split(" ");
            int count = Integer.parseInt(fields[4]);
            List<Level> levels = new ArrayList<>();
            for (int i = 1; i <= count; i++) levels.add(Level.parse(lines.get(index + i)));
            types.add(new TowerType(fields[1], fields[2].charAt(0), fields[3], levels));
            index += count + 1;
        }
        return types;
    }
    static boolean canAim(String targets, Enemy enemy) { return targets.equals("both") || targets.equals(enemy.kind.movement); }
}

final class Tower {
    final int number;
    final TowerType kind;
    final Cell cell;
    final int built;
    int level = 1;
    String mode = "FIRST";
    int ready, investment;
    Integer sold;
    int shots, hits, fizzles, kills, damage;

    Tower(int number, TowerType kind, Cell cell, int tick) {
        this.number = number; this.kind = kind; this.cell = cell; built = tick; ready = tick; investment = kind.levels().getFirst().cost();
    }
    Level stats() { return kind.levels().get(level - 1); }
    Point center() { return cell.center(); }
    boolean standing() { return sold == null; }
    boolean inRange(Point point) { return Combat.squaredDistance(center(), point) <= (long) stats().range() * stats().range(); }
    long targetKey(Enemy enemy, DistanceField field) {
        return switch (mode) {
            case "FIRST" -> enemy.remaining(field);
            case "LAST" -> -enemy.remaining(field);
            case "STRONGEST" -> -enemy.hp;
            case "WEAKEST" -> enemy.hp;
            default -> Combat.squaredDistance(center(), enemy.position());
        };
    }
    Enemy selectTarget(List<Enemy> enemies, DistanceField field) {
        Enemy best = null;
        long bestKey = 0;
        for (Enemy enemy : enemies) {
            if (!Towers.canAim(kind.targets(), enemy) || !inRange(enemy.position())) continue;
            long key = targetKey(enemy, field);
            if (best == null || key < bestKey || key == bestKey && enemy.number < best.number) { best = enemy; bestKey = key; }
        }
        return best;
    }
}
