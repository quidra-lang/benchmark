import java.util.*;

final class EnemyType {
    final String name, movement;
    final char symbol;
    final int hp, armor, speed, bounty, lives, regen, splitCount;
    final EnemyType splitInto;
    int spawned, kills, leaks, damage;

    EnemyType(String[] fields, Map<String, EnemyType> known) {
        name = fields[1]; symbol = fields[2].charAt(0); movement = fields[3]; hp = Integer.parseInt(fields[4]); armor = Integer.parseInt(fields[5]);
        speed = Integer.parseInt(fields[6]); bounty = Integer.parseInt(fields[7]); lives = Integer.parseInt(fields[8]); regen = Integer.parseInt(fields[9]);
        splitInto = fields[10].equals("-") ? null : known.get(fields[10]); splitCount = Integer.parseInt(fields[11]);
    }
}
record Group(EnemyType kind, int spawn, int count, int delay, int interval, int multiplier) {
    static Group parse(String[] fields, Map<String, EnemyType> known) { return new Group(known.get(fields[1]), Integer.parseInt(fields[2]), Integer.parseInt(fields[3]), Integer.parseInt(fields[4]), Integer.parseInt(fields[5]), Integer.parseInt(fields[6])); }
    int spawnTick(int start, int index) { return start + delay + index * interval; }
}
final class Wave {
    final int reward;
    final List<Group> groups = new ArrayList<>();
    Wave(int reward) { this.reward = reward; }
    int enemyCount() { return groups.stream().mapToInt(Group::count).sum(); }
}
record WaveData(Map<String, EnemyType> types, List<Wave> waves) {}
final class Enemies {
    static WaveData parse(List<String> lines) {
        Map<String, EnemyType> types = new LinkedHashMap<>();
        List<Wave> waves = new ArrayList<>();
        for (String line : lines) {
            String[] fields = line.split(" ");
            if (fields[0].equals("enemy")) { EnemyType type = new EnemyType(fields, types); types.put(type.name, type); }
            else if (fields[0].equals("wave")) waves.add(new Wave(Integer.parseInt(fields[1])));
            else waves.getLast().groups.add(Group.parse(fields, types));
        }
        return new WaveData(types, waves);
    }
}

final class Enemy {
    final int number, multiplier, maxHp;
    final EnemyType kind;
    final Effect slow = new Effect(), burn = new Effect();
    int hp, progress;
    boolean alive = true;
    Cell cell, next;
    Point point;

    Enemy(int number, EnemyType kind, int multiplier) { this.number = number; this.kind = kind; this.multiplier = multiplier; maxHp = kind.hp * multiplier / 100; hp = maxHp; }
    boolean flying() { return kind.movement.equals("air"); }
    Point position() { return flying() ? point : new Point(100 * cell.x() + (next.x() - cell.x()) * progress, 100 * cell.y() + (next.y() - cell.y()) * progress); }
    Cell occupiedCell() { return flying() ? new Cell((point.x() + 50) / 100, (point.y() + 50) / 100) : progress < 50 ? cell : next; }
    int remaining(DistanceField field) { return flying() ? Combat.isqrt(Combat.squaredDistance(point, field.grid.exit.center())) : 100 * field.at(next) + 100 - progress; }
    int slowedSpeed() { return slow.active() ? kind.speed * (100 - slow.strength) / 100 : kind.speed; }
    Enemy split(int number) {
        Enemy child = new Enemy(number, kind.splitInto, multiplier);
        child.cell = cell; child.next = next; child.progress = progress; child.point = point;
        return child;
    }
}
