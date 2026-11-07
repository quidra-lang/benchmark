using System;

static class Combat
{
    public sealed record Advance(Point Point, bool Arrived);
    public static long SquaredDistance(Point first, Point second) { long dx = first.X - second.X, dy = first.Y - second.Y; return dx * dx + dy * dy; }
    public static int Isqrt(long value)
    {
        long low = 0, high = value + 1;
        while (low + 1 < high) { long middle = (low + high) / 2; if (middle <= value / middle) low = middle; else high = middle; }
        return (int)low;
    }
    public static Advance AdvancePoint(Point point, Point goal, int step)
    {
        long dx = goal.X - point.X, dy = goal.Y - point.Y, squared = dx * dx + dy * dy;
        if (squared <= (long)step * step) return new Advance(goal, true);
        int length = Isqrt(squared);
        return new Advance(new Point(point.X + (int)(dx * step / length), point.Y + (int)(dy * step / length)), false);
    }
    public static int Damage(int hp, int power, int armor) => Math.Min(hp, Math.Max(1, power - armor));
}

sealed class Effect
{
    public int Strength, Remaining, Source;
    public bool Active => Remaining > 0;
    public void Receive(int strength, int duration, int source)
    {
        if (strength > Strength) { Strength = strength; Remaining = duration; Source = source; }
        else if (strength == Strength) Remaining = Math.Max(Remaining, duration);
    }
    public void AdvanceTime() { Remaining--; if (Remaining == 0) { Strength = 0; Source = 0; } }
}

sealed class Projectile
{
    public int Number { get; }
    public int Tower { get; }
    public int Target { get; }
    public string Targets { get; }
    public Level Stats { get; }
    public Point Position, Aim;
    public Projectile(int number, Tower tower, Enemy target)
    {
        Number = number; Tower = tower.Number; Target = target.Number; Targets = tower.Kind.Targets; Stats = tower.Stats(); Position = tower.Center(); Aim = target.Position();
    }
    public bool Fly()
    {
        if (Stats.ShotSpeed == 0) return true;
        Combat.Advance movement = Combat.AdvancePoint(Position, Aim, Stats.ShotSpeed);
        Position = movement.Point;
        return movement.Arrived;
    }
}
