record Dice(int count, int sides) {
    int roll(Minstd rng) { return rng.roll(count, sides); }
    static Dice parse(String token) {
        String[] parts = token.split("d");
        return new Dice(Integer.parseInt(parts[0]), Integer.parseInt(parts[1]));
    }
}
record Attack(String outcome, int damage) {}
final class Combat {
    static Attack resolve(Minstd rng, int toHit, int defense, Dice dice, int bonus) {
        int roll = 1 + rng.rnd(20);
        if (roll == 1) return new Attack("miss", 0);
        if (roll == 20) return new Attack("critical", Math.max(1, dice.roll(rng) + dice.roll(rng) + bonus));
        if (roll + toHit >= defense) return new Attack("hit", Math.max(1, dice.roll(rng) + bonus));
        return new Attack("miss", 0);
    }
}
