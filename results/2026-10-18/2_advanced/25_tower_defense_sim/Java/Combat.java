final class Combat {
    record Advance(Point point, boolean arrived) {}
    static long squaredDistance(Point first, Point second) { long dx = first.x() - second.x(), dy = first.y() - second.y(); return dx * dx + dy * dy; }
    static int isqrt(long value) {
        long low = 0, high = value + 1;
        while (low + 1 < high) { long middle = (low + high) / 2; if (middle <= value / middle) low = middle; else high = middle; }
        return (int) low;
    }
    static Advance advance(Point point, Point goal, int step) {
        long dx = goal.x() - point.x(), dy = goal.y() - point.y(), squared = dx * dx + dy * dy;
        if (squared <= (long) step * step) return new Advance(goal, true);
        int length = isqrt(squared);
        return new Advance(new Point(point.x() + (int) (dx * step / length), point.y() + (int) (dy * step / length)), false);
    }
    static int damage(int hp, int power, int armor) { return Math.min(hp, Math.max(1, power - armor)); }
}

final class Effect {
    int strength, remaining, source;
    boolean active() { return remaining > 0; }
    void receive(int strength, int duration, int source) {
        if (strength > this.strength) { this.strength = strength; remaining = duration; this.source = source; }
        else if (strength == this.strength) remaining = Math.max(remaining, duration);
    }
    void advanceTime() { remaining--; if (remaining == 0) { strength = 0; source = 0; } }
}

final class Projectile {
    final int number, tower, target;
    final String targets;
    final Level stats;
    Point position, aim;
    Projectile(int number, Tower tower, Enemy target) {
        this.number = number; this.tower = tower.number; this.target = target.number; targets = tower.kind.targets(); stats = tower.stats(); position = tower.center(); aim = target.position();
    }
    boolean fly() {
        if (stats.shotSpeed() == 0) return true;
        Combat.Advance movement = Combat.advance(position, aim, stats.shotSpeed());
        position = movement.point();
        return movement.arrived();
    }
}
