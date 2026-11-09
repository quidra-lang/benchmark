using System;
using System.Collections.Generic;
using System.Linq;

sealed class EnemyType
{
    public string Name { get; }
    public string Movement { get; }
    public char Symbol { get; }
    public int Hp, Armor, Speed, Bounty, Lives, Regen, SplitCount;
    public EnemyType? SplitInto { get; }
    public int Spawned, Kills, Leaks, Damage;

    public EnemyType(string[] fields, Dictionary<string, EnemyType> known)
    {
        Name = fields[1]; Symbol = fields[2][0]; Movement = fields[3]; Hp = int.Parse(fields[4]); Armor = int.Parse(fields[5]);
        Speed = int.Parse(fields[6]); Bounty = int.Parse(fields[7]); Lives = int.Parse(fields[8]); Regen = int.Parse(fields[9]);
        SplitInto = fields[10] == "-" ? null : known[fields[10]]; SplitCount = int.Parse(fields[11]);
    }
}
sealed record Group(EnemyType Kind, int Spawn, int Count, int Delay, int Interval, int Multiplier)
{
    public static Group Parse(string[] fields, Dictionary<string, EnemyType> known) => new(known[fields[1]], int.Parse(fields[2]), int.Parse(fields[3]), int.Parse(fields[4]), int.Parse(fields[5]), int.Parse(fields[6]));
    public int SpawnTick(int start, int index) => start + Delay + index * Interval;
}
sealed class Wave
{
    public int Reward { get; }
    public List<Group> Groups { get; } = new();
    public Wave(int reward) { Reward = reward; }
    public int EnemyCount => Groups.Sum(group => group.Count);
}
sealed record WaveData(List<EnemyType> Types, List<Wave> Waves);

static class Enemies
{
    public static WaveData Parse(List<string> lines)
    {
        var types = new List<EnemyType>();
        var known = new Dictionary<string, EnemyType>(StringComparer.Ordinal);
        var waves = new List<Wave>();
        foreach (string line in lines)
        {
            string[] fields = line.Split(' ');
            if (fields[0] == "enemy") { var type = new EnemyType(fields, known); types.Add(type); known[type.Name] = type; }
            else if (fields[0] == "wave") waves.Add(new Wave(int.Parse(fields[1])));
            else waves[^1].Groups.Add(Group.Parse(fields, known));
        }
        return new WaveData(types, waves);
    }
}

sealed class Enemy
{
    public int Number { get; }
    public int Multiplier { get; }
    public int MaxHp { get; }
    public EnemyType Kind { get; }
    public Effect Slow { get; } = new();
    public Effect Burn { get; } = new();
    public int Hp, Progress;
    public bool Alive = true;
    public Cell Cell, Next;
    public Point Point;

    public Enemy(int number, EnemyType kind, int multiplier) { Number = number; Kind = kind; Multiplier = multiplier; MaxHp = kind.Hp * multiplier / 100; Hp = MaxHp; }
    public bool Flying => Kind.Movement == "air";
    public Point Position() => Flying ? Point : new Point(100 * Cell.X + (Next.X - Cell.X) * Progress, 100 * Cell.Y + (Next.Y - Cell.Y) * Progress);
    public Cell OccupiedCell() => Flying ? new Cell((Point.X + 50) / 100, (Point.Y + 50) / 100) : Progress < 50 ? Cell : Next;
    public int Remaining(DistanceField field) => Flying ? Combat.Isqrt(Combat.SquaredDistance(Point, field.Grid.Exit.Center())) : 100 * field.At(Next) + 100 - Progress;
    public int SlowedSpeed() => Slow.Active ? Kind.Speed * (100 - Slow.Strength) / 100 : Kind.Speed;
    public Enemy Split(int number)
    {
        var child = new Enemy(number, Kind.SplitInto!, Multiplier);
        child.Cell = Cell; child.Next = Next; child.Progress = Progress; child.Point = Point;
        return child;
    }
}
