using System;

sealed class MonsterType {
    public readonly string Name;
    public readonly char Symbol;
    public readonly int MinDepth, MaxDepth, Weight, ToHit, Defense, Speed, Xp;
    public readonly Dice Hp, Damage;
    public readonly bool Erratic, Stationary, Regenerates, Poisonous;
    public MonsterType(string[] tokens) {
        Name = tokens[0]; Symbol = tokens[1][0];
        MinDepth = int.Parse(tokens[2]); MaxDepth = int.Parse(tokens[3]); Weight = int.Parse(tokens[4]);
        Hp = Dice.Parse(tokens[5]); ToHit = int.Parse(tokens[6]); Defense = int.Parse(tokens[7]);
        Damage = Dice.Parse(tokens[8]); Speed = int.Parse(tokens[9]); Xp = int.Parse(tokens[10]);
        Erratic = tokens[11].Contains('E'); Stationary = tokens[11].Contains('S'); Regenerates = tokens[11].Contains('R'); Poisonous = tokens[11].Contains('P');
    }
}
sealed class ItemType {
    public readonly string Category, Name;
    public readonly int MinDepth, MaxDepth, Weight;
    public Dice DamageDice;
    public int ToHit, Armor, PoisonTurns, Nutrition;
    public string Effect;
    public ItemType(string category, string name, int minDepth, int maxDepth, int weight) {
        Category = category; Name = name; MinDepth = minDepth; MaxDepth = maxDepth; Weight = weight;
    }
    public static ItemType Parse(string[] tokens) {
        ItemType kind = new(tokens[0], tokens[1], int.Parse(tokens[2]), int.Parse(tokens[3]), int.Parse(tokens[4]));
        switch (kind.Category) {
            case "weapon": kind.DamageDice = Dice.Parse(tokens[5]); kind.ToHit = int.Parse(tokens[6]); break;
            case "armor": kind.Armor = int.Parse(tokens[5]); break;
            case "potion":
                kind.Effect = tokens[5];
                if (kind.Effect == "heal") kind.DamageDice = Dice.Parse(tokens[6]);
                else if (kind.Effect == "poison") kind.PoisonTurns = int.Parse(tokens[6]);
                break;
            case "scroll": kind.Effect = tokens[5]; break;
            case "food": kind.Nutrition = int.Parse(tokens[5]); break;
            case "gold": kind.DamageDice = Dice.Parse(tokens[5]); break;
        }
        return kind;
    }
    public static ItemType Amulet() => new("amulet", "amulet", 0, 0, 0);
}
sealed class Monster {
    public readonly int Number, MaxHp;
    public readonly MonsterType Kind;
    public int X, Y, Hp, Energy;
    public bool Asleep, WasVisible;
    public Monster(int number, MonsterType kind, int x, int y, int hp, bool asleep) {
        Number = number; Kind = kind; X = x; Y = y; Hp = hp; MaxHp = hp; Asleep = asleep;
    }
}
sealed class Item {
    public readonly ItemType Kind;
    public readonly int X, Y, Amount;
    public int Bonus;
    public Item(ItemType kind, int x, int y, int amount = 0) { Kind = kind; X = x; Y = y; Amount = amount; }
    public char Symbol() => Kind.Category switch {
        "weapon" => ')', "armor" => '[', "potion" => '!', "scroll" => '?', "food" => '%', "gold" => '$', "amulet" => '"', _ => throw new ArgumentException()
    };
    public string DisplayName() {
        string name = Kind.Name.Replace('_', ' ');
        if (Kind.Category is "weapon" or "armor") return "+" + Bonus + " " + name;
        return Kind.Category == "gold" ? Amount + " gold" : name;
    }
    public string ReferenceName() => Kind.Category == "gold" ? DisplayName() : "the " + DisplayName();
}
