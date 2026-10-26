final class MonsterType {
    final String name;
    final char symbol;
    final int minDepth, maxDepth, weight, toHit, defense, speed, xp;
    final Dice hp, damage;
    final boolean erratic, stationary, regenerates, poisonous;
    MonsterType(String[] tokens) {
        name = tokens[0]; symbol = tokens[1].charAt(0);
        minDepth = Integer.parseInt(tokens[2]); maxDepth = Integer.parseInt(tokens[3]); weight = Integer.parseInt(tokens[4]);
        hp = Dice.parse(tokens[5]); toHit = Integer.parseInt(tokens[6]); defense = Integer.parseInt(tokens[7]);
        damage = Dice.parse(tokens[8]); speed = Integer.parseInt(tokens[9]); xp = Integer.parseInt(tokens[10]);
        erratic = tokens[11].contains("E"); stationary = tokens[11].contains("S"); regenerates = tokens[11].contains("R"); poisonous = tokens[11].contains("P");
    }
}
final class ItemType {
    final String category, name;
    final int minDepth, maxDepth, weight;
    Dice dice;
    int toHit, armor, poisonTurns, nutrition;
    String effect;
    ItemType(String category, String name, int minDepth, int maxDepth, int weight) {
        this.category = category; this.name = name; this.minDepth = minDepth; this.maxDepth = maxDepth; this.weight = weight;
    }
    static ItemType parse(String[] tokens) {
        ItemType kind = new ItemType(tokens[0], tokens[1], Integer.parseInt(tokens[2]), Integer.parseInt(tokens[3]), Integer.parseInt(tokens[4]));
        switch (kind.category) {
            case "weapon" -> { kind.dice = Dice.parse(tokens[5]); kind.toHit = Integer.parseInt(tokens[6]); }
            case "armor" -> kind.armor = Integer.parseInt(tokens[5]);
            case "potion" -> { kind.effect = tokens[5]; if (kind.effect.equals("heal")) kind.dice = Dice.parse(tokens[6]); else if (kind.effect.equals("poison")) kind.poisonTurns = Integer.parseInt(tokens[6]); }
            case "scroll" -> kind.effect = tokens[5];
            case "food" -> kind.nutrition = Integer.parseInt(tokens[5]);
            case "gold" -> kind.dice = Dice.parse(tokens[5]);
        }
        return kind;
    }
    static ItemType amulet() { return new ItemType("amulet", "amulet", 0, 0, 0); }
}
final class Monster {
    final int number, maxHp;
    final MonsterType kind;
    int x, y, hp, energy;
    boolean asleep, wasVisible;
    Monster(int number, MonsterType kind, int x, int y, int hp, boolean asleep) {
        this.number = number; this.kind = kind; this.x = x; this.y = y; this.hp = hp; maxHp = hp; this.asleep = asleep;
    }
}
final class Item {
    final ItemType kind;
    final int x, y, amount;
    int bonus;
    Item(ItemType kind, int x, int y) { this(kind, x, y, 0); }
    Item(ItemType kind, int x, int y, int amount) { this.kind = kind; this.x = x; this.y = y; this.amount = amount; }
    char symbol() {
        return switch (kind.category) { case "weapon" -> ')'; case "armor" -> '['; case "potion" -> '!'; case "scroll" -> '?'; case "food" -> '%'; case "gold" -> '$'; case "amulet" -> '"'; default -> throw new IllegalArgumentException(); };
    }
    String displayName() {
        String name = kind.name.replace('_', ' ');
        if (kind.category.equals("weapon") || kind.category.equals("armor")) return "+" + bonus + " " + name;
        return kind.category.equals("gold") ? amount + " gold" : name;
    }
    String referenceName() { return kind.category.equals("gold") ? displayName() : "the " + displayName(); }
}
