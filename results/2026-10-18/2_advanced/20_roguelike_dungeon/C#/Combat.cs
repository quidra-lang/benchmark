using System;

sealed record Dice(int Count, int Sides) {
    public int Roll(Minstd rng) => rng.Roll(Count, Sides);
    public static Dice Parse(string token) {
        string[] parts = token.Split('d');
        return new Dice(int.Parse(parts[0]), int.Parse(parts[1]));
    }
}
sealed record Attack(string Outcome, int Damage);
static class Combat {
    public static Attack Resolve(Minstd rng, int toHit, int defense, Dice dice, int bonus) {
        int roll = 1 + rng.Rnd(20);
        if (roll == 1) return new Attack("miss", 0);
        if (roll == 20) return new Attack("critical", Math.Max(1, dice.Roll(rng) + dice.Roll(rng) + bonus));
        if (roll + toHit >= defense) return new Attack("hit", Math.Max(1, dice.Roll(rng) + bonus));
        return new Attack("miss", 0);
    }
}
