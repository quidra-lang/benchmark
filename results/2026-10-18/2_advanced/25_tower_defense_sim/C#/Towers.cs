using System;
using System.Collections.Generic;
using System.Linq;

sealed record Level(int Cost, int Range, int Power, int Interval, int ShotSpeed, int Splash, int SlowRate, int SlowTime, int BurnAmount, int BurnTime)
{
    public static Level Parse(string line)
    {
        int[] values = line.Split(' ').Skip(1).Select(int.Parse).ToArray();
        return new Level(values[0], values[1], values[2], values[3], values[4], values[5], values[6], values[7], values[8], values[9]);
    }
}
sealed record TowerType(string Name, char Symbol, string Targets, List<Level> Levels);

static class Towers
{
    public static readonly HashSet<string> TargetModes = new(StringComparer.Ordinal) { "FIRST", "LAST", "STRONGEST", "WEAKEST", "CLOSEST" };
    public static List<TowerType> Parse(List<string> lines)
    {
        var types = new List<TowerType>();
        for (int index = 0; index < lines.Count;)
        {
            string[] fields = lines[index].Split(' ');
            int count = int.Parse(fields[4]);
            var levels = new List<Level>();
            for (int i = 1; i <= count; i++) levels.Add(Level.Parse(lines[index + i]));
            types.Add(new TowerType(fields[1], fields[2][0], fields[3], levels));
            index += count + 1;
        }
        return types;
    }
    public static bool CanAim(string targets, Enemy enemy) => targets == "both" || targets == enemy.Kind.Movement;
}

sealed class Tower
{
    public int Number { get; }
    public TowerType Kind { get; }
    public Cell Cell { get; }
    public int Built { get; }
    public int Level = 1;
    public string Mode = "FIRST";
    public int Ready, Investment;
    public int? Sold;
    public int Shots, Hits, Fizzles, Kills, Damage;

    public Tower(int number, TowerType kind, Cell cell, int tick)
    {
        Number = number; Kind = kind; Cell = cell; Built = tick; Ready = tick; Investment = kind.Levels[0].Cost;
    }
    public Level Stats() => Kind.Levels[Level - 1];
    public Point Center() => Cell.Center();
    public bool Standing => Sold == null;
    public bool InRange(Point point) => Combat.SquaredDistance(Center(), point) <= (long)Stats().Range * Stats().Range;
    long TargetKey(Enemy enemy, DistanceField field) => Mode switch
    {
        "FIRST" => enemy.Remaining(field),
        "LAST" => -enemy.Remaining(field),
        "STRONGEST" => -enemy.Hp,
        "WEAKEST" => enemy.Hp,
        _ => Combat.SquaredDistance(Center(), enemy.Position())
    };
    public Enemy? SelectTarget(List<Enemy> enemies, DistanceField field)
    {
        Enemy? best = null;
        long bestKey = 0;
        foreach (Enemy enemy in enemies)
        {
            if (!Towers.CanAim(Kind.Targets, enemy) || !InRange(enemy.Position())) continue;
            long key = TargetKey(enemy, field);
            if (best == null || key < bestKey || key == bestKey && enemy.Number < best.Number) { best = enemy; bestKey = key; }
        }
        return best;
    }
}
