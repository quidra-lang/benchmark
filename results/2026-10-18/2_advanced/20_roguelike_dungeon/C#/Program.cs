using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Program {
    static readonly Dice Unarmed = new(1, 2);
    static readonly string[] UsageNames = ["picked", "quaffed", "read", "eaten", "wielded", "worn"];
    static readonly Dictionary<string, string> CommandClasses = new(StringComparer.Ordinal) { ["quaff"] = "potion", ["read"] = "scroll", ["wield"] = "weapon", ["wear"] = "armor", ["eat"] = "food" };
    static List<string[]> ReadRows(string name) => File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).Select(line => line.Split(' ')).ToList();
    static string Decimal(int a, int b) {
        if (b == 0) return "-";
        int z = (20 * a + b) / (2 * b);
        return z / 10 + "." + z % 10;
    }
    static (int Explored, int Total) Exploration(Level level) {
        int explored = 0, total = 0;
        for (int y = 0; y < level.Height; y++) for (int x = 0; x < level.Width; x++) if (level.Terrain[y][x] != ' ') { total++; if (level.Memory[y][x] != ' ') explored++; }
        return (explored, total);
    }
    sealed class Config {
        public readonly int GenerationSeed, GameSeed, Width, Height, MinSize, MaxSplit, RoomMin, RoomMax, Levels, MonsterBase, MonsterStep, ItemBase, ItemStep, SleepChance, WakeChance, Radius, MaxHp, RegenInterval, FoodStart, FoodMax, FoodHungry, FoodWeak, PackLimit;
        public readonly Dice HitDie;
        public readonly List<string> StartItems;
        public readonly int[] XpLevels;
        public readonly HashSet<int> Checkpoints;
        public Config(List<string[]> rows) {
            Dictionary<string, List<string>> values = rows.ToDictionary(row => row[0], row => row.Skip(1).ToList(), StringComparer.Ordinal);
            int Number(string key, int index) => int.Parse(values[key][index]);
            GenerationSeed = Number("seed", 0); GameSeed = Number("seed", 1);
            Width = Number("map", 0); Height = Number("map", 1); MinSize = Number("bsp", 0); MaxSplit = Number("bsp", 1);
            RoomMin = Number("room", 0); RoomMax = Number("room", 1); Levels = Number("levels", 0);
            MonsterBase = Number("monsters", 0); MonsterStep = Number("monsters", 1); ItemBase = Number("items", 0); ItemStep = Number("items", 1);
            SleepChance = Number("sleep", 0); WakeChance = Number("sleep", 1); Radius = Number("fov", 0);
            MaxHp = Number("player", 0); RegenInterval = Number("player", 1); HitDie = Dice.Parse(values["hitdie"][0]);
            FoodStart = Number("food", 0); FoodMax = Number("food", 1); FoodHungry = Number("food", 2); FoodWeak = Number("food", 3);
            PackLimit = Number("pack", 0); StartItems = values["start"]; XpLevels = values["xp"].Select(int.Parse).ToArray(); Checkpoints = values["checkpoints"].Select(int.Parse).ToHashSet();
        }
    }
    sealed record Command(string Name, string Argument);
    static List<Command> ExpandCommands(List<string[]> rows) {
        List<Command> commands = new();
        foreach (string[] row in rows) {
            string name = row[0], argument = name == "wait" || row.Length < 2 ? null : row[1];
            int count = name == "wait" ? row.Length == 2 ? int.Parse(row[1]) : 1 : row.Length == 3 ? int.Parse(row[2]) : 1;
            for (int i = 0; i < count; i++) commands.Add(new Command(name, argument));
        }
        return commands;
    }
    sealed class Player {
        public int X, Y, Depth = 1, Hp, MaxHp, Level = 1, Xp, Gold, Satiation, Poison;
        public readonly List<Item> Pack = new();
        public Item Weapon, Armor;
        public Player(Config config, Position arrival) { X = arrival.X; Y = arrival.Y; Hp = MaxHp = config.MaxHp; Satiation = config.FoodStart; }
        public int Defense() => Armor == null ? 10 : 10 + Armor.Kind.Armor + Armor.Bonus;
    }
    sealed class AttackStats {
        int count, hits, criticals, damage;
        public void Record(Attack attack) {
            count++;
            if (attack.Outcome != "miss") { hits++; damage += attack.Damage; }
            if (attack.Outcome == "critical") criticals++;
        }
        public string Line(string label) => label + " " + count + " hits " + hits + " criticals " + criticals + " damage " + damage + " accuracy " + Decimal(100 * hits, count);
    }
    sealed class Game {
        readonly Config config;
        readonly List<MonsterType> monsterTypes;
        readonly List<ItemType> itemTypes;
        readonly List<Command> commands;
        readonly Minstd generationRng, rng;
        readonly List<Level> levels = new();
        readonly Player player;
        int turn = 1, succeeded, failed, unused, moves, poisonDamage, starvationDamage;
        public readonly List<string> Messages = new(), MapLines = new();
        bool[][] visible;
        int[][] distance;
        string result, cause;
        readonly AttackStats playerAttacks = new(), monsterAttacks = new();
        readonly int[] usage = new int[6];
        readonly Dictionary<string, int> kills = new(StringComparer.Ordinal);
        public Game(Config config, List<MonsterType> monsterTypes, List<ItemType> itemTypes, List<Command> commands) {
            this.config = config; this.monsterTypes = monsterTypes; this.itemTypes = itemTypes; this.commands = commands;
            generationRng = new Minstd(config.GenerationSeed); rng = new Minstd(config.GameSeed);
            BuildLevels(); player = new Player(config, levels[0].Arrival); GiveStartItems();
            foreach (MonsterType kind in monsterTypes) kills[kind.Name] = 0;
        }
        void BuildLevels() {
            DungeonGen generator = new(generationRng, config.MinSize, config.MaxSplit, config.RoomMin, config.RoomMax);
            for (int depth = 1; depth <= config.Levels; depth++) {
                Level level = generator.Generate(depth, config.Width, config.Height);
                if (depth < config.Levels) level.Terrain[level.Target.Y][level.Target.X] = '>';
                else level.Items.Add(new Item(ItemType.Amulet(), level.Target.X, level.Target.Y));
                PlaceMonsters(level); PlaceItems(level); levels.Add(level);
            }
        }
        void PlaceMonsters(Level level) {
            int count = config.MonsterBase + config.MonsterStep * (level.Depth - 1);
            List<MonsterType> candidates = monsterTypes.Where(kind => kind.MinDepth <= level.Depth && level.Depth <= kind.MaxDepth).ToList();
            int[] weights = candidates.Select(kind => kind.Weight).ToArray();
            for (int number = 1; number <= count; number++) {
                MonsterType kind = candidates[generationRng.Select(weights)];
                RoomCell cell;
                do { cell = level.DrawRoom(generationRng); } while (cell.Room == level.ArrivalRoom || level.Terrain[cell.Y][cell.X] != '.' || level.MonsterAt(cell.X, cell.Y) != null);
                int hp = kind.Hp.Roll(generationRng);
                bool asleep = generationRng.Draw() % 100 < config.SleepChance;
                level.Monsters.Add(new Monster(number, kind, cell.X, cell.Y, hp, asleep));
            }
            level.MonstersCreated = count;
        }
        void PlaceItems(Level level) {
            int count = config.ItemBase + config.ItemStep * (level.Depth - 1);
            List<ItemType> candidates = itemTypes.Where(kind => kind.MinDepth <= level.Depth && level.Depth <= kind.MaxDepth).ToList();
            int[] weights = candidates.Select(kind => kind.Weight).ToArray();
            for (int i = 0; i < count; i++) {
                ItemType kind = candidates[generationRng.Select(weights)];
                RoomCell cell;
                do { cell = level.DrawRoom(generationRng); } while (level.Terrain[cell.Y][cell.X] != '.' || level.ItemAt(cell.X, cell.Y) != null);
                int amount = kind.Category == "gold" ? kind.DamageDice.Roll(generationRng) : 0;
                level.Items.Add(new Item(kind, cell.X, cell.Y, amount));
            }
            level.ItemsPlaced = level.Items.Count;
        }
        void GiveStartItems() {
            Dictionary<string, ItemType> kinds = itemTypes.ToDictionary(kind => kind.Name, StringComparer.Ordinal);
            foreach (string name in config.StartItems) {
                Item item = new(kinds[name], player.X, player.Y); player.Pack.Add(item);
                if (item.Kind.Category == "weapon" && player.Weapon == null) player.Weapon = item;
                if (item.Kind.Category == "armor" && player.Armor == null) player.Armor = item;
            }
        }
        Level CurrentLevel() => levels[player.Depth - 1];
        void Say(string text) => Messages.Add(turn.ToString("D4") + " " + text);
        string Hunger() => player.Satiation > config.FoodHungry ? "normal" : player.Satiation > config.FoodWeak ? "hungry" : player.Satiation > 0 ? "weak" : "starving";
        void Finish(string result, string cause) { this.result = result; this.cause = cause; }
        void Die(string cause) { Say("You die."); Finish("died", cause); }
        void UpdateView() {
            Level level = CurrentLevel();
            visible = Fov.FieldOfView(level, player.X, player.Y, config.Radius);
            for (int y = 0; y < level.Height; y++) for (int x = 0; x < level.Width; x++) if (visible[y][x]) {
                Item item = level.ItemAt(x, y);
                level.Memory[y][x] = item == null ? level.Terrain[y][x] : item.Symbol();
            }
            foreach (Monster monster in level.Monsters) {
                bool seen = visible[monster.Y][monster.X];
                if (seen && !monster.WasVisible) Say("You see the " + monster.Kind.Name + ".");
                monster.WasVisible = seen;
            }
        }
        public void Run() {
            UpdateView();
            foreach (Command command in commands) {
                if (result != null) unused++;
                else if (!Execute(command)) failed++;
                else { succeeded++; if (result == null) AdvanceTurn(); }
            }
            if (result == null) Finish("alive", "commands_exhausted");
        }
        void AdvanceTurn() {
            UpdateView(); MonstersAct();
            if (result != null) return;
            EndTurn();
            if (result != null) return;
            if (config.Checkpoints.Contains(turn)) WriteCheckpoint();
            turn++;
        }
        bool Execute(Command command) {
            switch (command.Name) {
                case "move": int[] direction = Fov.Directions[Array.IndexOf(Fov.Names, command.Argument)]; return Move(direction[0], direction[1]);
                case "wait": return true;
                case "pickup": return Pickup();
                case "descend": return Descend();
                default: return UseItem(command.Name, int.Parse(command.Argument));
            }
        }
        bool Move(int dx, int dy) {
            Level level = CurrentLevel();
            int x = player.X + dx, y = player.Y + dy;
            if (!Fov.Passable(level, x, y)) { Say("You bump into a wall."); return false; }
            if (!Fov.CanMove(level, player.X, player.Y, dx, dy)) { Say("You cannot move diagonally through a door."); return false; }
            Monster monster = level.MonsterAt(x, y);
            if (monster != null) { PlayerAttack(level, monster); return true; }
            player.X = x; player.Y = y; moves++;
            Item item = level.ItemAt(x, y);
            if (item != null) Say("You see " + item.ReferenceName() + " here.");
            else if (level.Terrain[y][x] == '>') Say("There is a staircase down here.");
            return true;
        }
        bool Pickup() {
            Level level = CurrentLevel();
            Item item = level.ItemAt(player.X, player.Y);
            if (item == null) { Say("There is nothing here."); return false; }
            if (item.Kind.Category == "gold") { player.Gold += item.Amount; Say("You pick up " + item.DisplayName() + "."); }
            else if (item.Kind.Category == "amulet") { Say("You pick up the amulet."); Say("You win!"); Finish("won", "amulet"); }
            else if (player.Pack.Count >= config.PackLimit) { Say("Your pack is full."); return false; }
            else { player.Pack.Add(item); Say("You pick up the " + item.DisplayName() + " (" + player.Pack.Count + ")."); }
            level.Items.Remove(item); level.Picked++; usage[0]++;
            return true;
        }
        bool Descend() {
            if (CurrentLevel().Terrain[player.Y][player.X] != '>') { Say("There are no stairs here."); return false; }
            player.Depth++;
            Position arrival = CurrentLevel().Arrival; player.X = arrival.X; player.Y = arrival.Y;
            Say("You descend to depth " + player.Depth + ".");
            return true;
        }
        bool UseItem(string name, int number) {
            if (number > player.Pack.Count) { Say("You do not have that item."); return false; }
            Item item = player.Pack[number - 1];
            if (item.Kind.Category != CommandClasses[name]) { Say("You cannot " + name + " that."); return false; }
            return name switch { "quaff" => Quaff(item), "read" => ReadScroll(item), "wield" => Wield(item), "wear" => Wear(item), _ => Eat(item) };
        }
        bool Quaff(Item item) {
            player.Pack.Remove(item); usage[1]++; Say("You quaff the " + item.DisplayName() + ".");
            switch (item.Kind.Effect) {
                case "heal":
                    player.Hp += item.Kind.DamageDice.Roll(rng);
                    if (player.Hp > player.MaxHp) { player.MaxHp++; player.Hp = player.MaxHp; }
                    player.Poison = 0; Say("You feel better."); break;
                case "poison": player.Poison += item.Kind.PoisonTurns; Say("You feel very sick."); break;
                case "level": Say("You feel more experienced."); if (player.Level <= config.XpLevels.Length) GainXp(config.XpLevels[player.Level - 1] - player.Xp); break;
            }
            return true;
        }
        bool ReadScroll(Item item) {
            Level level = CurrentLevel();
            player.Pack.Remove(item); usage[2]++; Say("You read the " + item.DisplayName() + ".");
            switch (item.Kind.Effect) {
                case "mapping":
                    for (int y = 0; y < level.Height; y++) for (int x = 0; x < level.Width; x++) if (level.Terrain[y][x] != ' ' && level.Memory[y][x] == ' ') level.Memory[y][x] = level.Terrain[y][x];
                    Say("A map forms in your mind."); break;
                case "teleport":
                    RoomCell cell;
                    do { cell = level.DrawRoom(rng); } while (cell.X == player.X && cell.Y == player.Y || level.MonsterAt(cell.X, cell.Y) != null);
                    player.X = cell.X; player.Y = cell.Y; Say("You are teleported."); break;
                case "enchant_weapon":
                    if (player.Weapon == null) Say("Your hands twitch.");
                    else { Say("Your " + player.Weapon.DisplayName() + " glows blue."); player.Weapon.Bonus++; }
                    break;
                case "enchant_armor":
                    if (player.Armor == null) Say("Your skin tingles.");
                    else { Say("Your " + player.Armor.DisplayName() + " glows silver."); player.Armor.Bonus++; }
                    break;
            }
            return true;
        }
        bool Wield(Item item) {
            if (item == player.Weapon) { Say("You are already wielding that."); return false; }
            player.Weapon = item; usage[4]++; Say("You are now wielding the " + item.DisplayName() + "."); return true;
        }
        bool Wear(Item item) {
            if (item == player.Armor) { Say("You are already wearing that."); return false; }
            player.Armor = item; usage[5]++; Say("You are now wearing the " + item.DisplayName() + "."); return true;
        }
        bool Eat(Item item) {
            player.Pack.Remove(item); usage[3]++; player.Satiation = Math.Min(player.Satiation + item.Kind.Nutrition, config.FoodMax); Say("You eat the " + item.DisplayName() + "."); return true;
        }
        void PlayerAttack(Level level, Monster monster) {
            Item weapon = player.Weapon;
            monster.Asleep = false;
            int toHit = player.Level + (weapon == null ? 0 : weapon.Kind.ToHit + weapon.Bonus), bonus = weapon == null ? 0 : weapon.Bonus;
            Dice dice = weapon == null ? Unarmed : weapon.Kind.DamageDice;
            if (Hunger() is "weak" or "starving") toHit -= 2;
            string name = monster.Kind.Name;
            Attack attack = Combat.Resolve(rng, toHit, monster.Kind.Defense, dice, bonus);
            playerAttacks.Record(attack);
            if (attack.Outcome == "miss") { Say("You miss the " + name + "."); return; }
            Say("You hit the " + name + (attack.Outcome == "critical" ? " hard for " : " for ") + attack.Damage + ".");
            monster.Hp -= attack.Damage;
            if (monster.Hp <= 0) { Say("You kill the " + name + "."); level.Monsters.Remove(monster); level.Kills++; kills[name]++; GainXp(monster.Kind.Xp); }
        }
        void GainXp(int amount) {
            player.Xp += amount;
            while (player.Level <= config.XpLevels.Length && player.Xp >= config.XpLevels[player.Level - 1]) {
                player.Level++;
                int gained = config.HitDie.Roll(rng); player.MaxHp += gained; player.Hp += gained;
                Say("Welcome to level " + player.Level + ".");
            }
        }
        void MonsterAttack(Monster monster) {
            MonsterType kind = monster.Kind;
            Attack attack = Combat.Resolve(rng, kind.ToHit, player.Defense(), kind.Damage, 0);
            monsterAttacks.Record(attack);
            if (attack.Outcome == "miss") { Say("The " + kind.Name + " misses you."); return; }
            Say("The " + kind.Name + (attack.Outcome == "critical" ? " hits you hard for " : " hits you for ") + attack.Damage + ".");
            player.Hp -= attack.Damage;
            if (player.Hp <= 0) Die("killed_by " + kind.Name);
            else if (kind.Poisonous) { player.Poison += 5; Say("You are poisoned."); }
        }
        void MonstersAct() {
            Level level = CurrentLevel();
            distance = Fov.Distances(level, player.X, player.Y);
            foreach (Monster monster in level.Monsters) {
                monster.Energy += monster.Kind.Speed;
                while (monster.Energy >= 2) { monster.Energy -= 2; MonsterAction(level, monster); if (result != null) return; }
            }
        }
        void MonsterAction(Level level, Monster monster) {
            bool sees = visible[monster.Y][monster.X];
            if (monster.Asleep) {
                if (sees && rng.Draw() % 100 < config.WakeChance) { monster.Asleep = false; Say("The " + monster.Kind.Name + " wakes up."); }
            }
            else if (monster.Kind.Stationary) { if (CanAttack(level, monster)) MonsterAttack(monster); }
            else if (monster.Kind.Erratic && rng.Draw() % 2 == 0) Wander(level, monster);
            else if (sees) Chase(level, monster);
            else Wander(level, monster);
        }
        bool CanAttack(Level level, Monster monster) {
            int dx = player.X - monster.X, dy = player.Y - monster.Y;
            return Math.Max(Math.Abs(dx), Math.Abs(dy)) == 1 && Fov.CanMove(level, monster.X, monster.Y, dx, dy);
        }
        void Wander(Level level, Monster monster) {
            int[] direction = Fov.Directions[rng.Draw() % 8];
            if (!Fov.CanMove(level, monster.X, monster.Y, direction[0], direction[1])) return;
            int x = monster.X + direction[0], y = monster.Y + direction[1];
            if (x == player.X && y == player.Y) MonsterAttack(monster);
            else if (level.MonsterAt(x, y) == null) { monster.X = x; monster.Y = y; }
        }
        void Chase(Level level, Monster monster) {
            if (CanAttack(level, monster)) { MonsterAttack(monster); return; }
            int here = distance[monster.Y][monster.X], bestDistance = 0;
            Position? best = null;
            foreach (int[] direction in Fov.Directions) {
                if (!Fov.CanMove(level, monster.X, monster.Y, direction[0], direction[1])) continue;
                int x = monster.X + direction[0], y = monster.Y + direction[1], next = distance[y][x];
                if (next < 0 || here >= 0 && next >= here || level.MonsterAt(x, y) != null || x == player.X && y == player.Y) continue;
                if (best == null || next < bestDistance) { best = new Position(x, y); bestDistance = next; }
            }
            if (best.HasValue) { monster.X = best.Value.X; monster.Y = best.Value.Y; }
        }
        void EndTurn() {
            foreach (Monster monster in CurrentLevel().Monsters) if (monster.Kind.Regenerates && monster.Hp < monster.MaxHp) monster.Hp++;
            if (player.Poison > 0) {
                player.Hp--; poisonDamage++;
                if (player.Hp <= 0) { Die("poison"); return; }
                player.Poison--;
                if (player.Poison == 0) Say("You feel less sick.");
            }
            if (player.Satiation == 0) {
                player.Hp--; starvationDamage++;
                if (player.Hp <= 0) { Die("starvation"); return; }
            } else {
                string before = Hunger(); player.Satiation--;
                string after = Hunger();
                if (after != before) Say(after switch { "hungry" => "You are getting hungry.", "weak" => "You feel weak from hunger.", _ => "You are starving." });
            }
            if (turn % config.RegenInterval == 0 && player.Poison == 0 && player.Satiation > 0 && player.Hp < player.MaxHp) player.Hp++;
        }
        char ViewSymbol(Level level, int x, int y) {
            if (x == player.X && y == player.Y) return '@';
            Monster monster = level.MonsterAt(x, y);
            if (monster != null) return monster.Kind.Symbol;
            Item item = level.ItemAt(x, y);
            return item == null ? level.Terrain[y][x] : item.Symbol();
        }
        List<string> MapRows(Level level, bool current) {
            string border = "+" + new string('-', level.Width) + "+";
            List<string> lines = [border];
            for (int y = 0; y < level.Height; y++) {
                StringBuilder row = new("|");
                for (int x = 0; x < level.Width; x++) row.Append(current && visible[y][x] ? ViewSymbol(level, x, y) : level.Memory[y][x]);
                row.Append('|'); lines.Add(row.ToString());
            }
            lines.Add(border);
            return lines;
        }
        string Status() => "STATUS hp " + player.Hp + "/" + player.MaxHp + " level " + player.Level + " xp " + player.Xp + " defense " + player.Defense() + " gold " + player.Gold + " food " + player.Satiation + " " + Hunger() + " poison " + player.Poison;
        void WriteCheckpoint() { MapLines.Add("CHECKPOINT turn " + turn + " depth " + player.Depth); MapLines.AddRange(MapRows(CurrentLevel(), true)); MapLines.Add(Status()); }
        public List<string> FinalBlock() {
            List<string> lines = ["FINAL turn " + succeeded + " depth " + player.Depth];
            foreach (Level level in levels.Take(player.Depth)) {
                var explored = Exploration(level);
                lines.Add("LEVEL " + level.Depth + " explored " + explored.Explored + "/" + explored.Total);
                lines.AddRange(MapRows(level, level.Depth == player.Depth));
            }
            lines.Add(Status());
            return lines;
        }
        static string ItemLabel(Item item) => item == null ? "-" : item.DisplayName();
        public List<string> Stats() {
            List<string> lines = ["result " + result, "cause " + cause, "turns " + succeeded, "depth " + player.Depth, "level " + player.Level, "xp " + player.Xp,
                "hp " + player.Hp + "/" + player.MaxHp, "defense " + player.Defense(), "gold " + player.Gold, "food " + player.Satiation + " " + Hunger(), "poison " + player.Poison,
                "weapon " + ItemLabel(player.Weapon), "armor " + ItemLabel(player.Armor), "commands " + commands.Count + " executed " + succeeded + " failed " + failed + " unused " + unused, "moves " + moves,
                playerAttacks.Line("player_attacks"), monsterAttacks.Line("monster_attacks"), "poison_damage " + poisonDamage + " starvation_damage " + starvationDamage];
            lines.Add(string.Join(" ", UsageNames.Select((name, i) => name + " " + usage[i])));
            lines.Add("kills " + kills.Values.Sum());
            foreach (MonsterType kind in monsterTypes) if (kills[kind.Name] > 0) lines.Add("KILL " + kind.Name + " " + kills[kind.Name]);
            foreach (Level level in levels) {
                var explored = Exploration(level);
                lines.Add("LEVEL " + level.Depth + " rooms " + level.Rooms.Count + " explored " + explored.Explored + "/" + explored.Total + " " + Decimal(100 * explored.Explored, explored.Total) + " monsters " + level.Kills + "/" + level.MonstersCreated + " items " + level.Picked + "/" + level.ItemsPlaced);
            }
            for (int i = 0; i < player.Pack.Count; i++) {
                Item item = player.Pack[i];
                lines.Add("INVENTORY " + (i + 1) + " " + item.DisplayName() + (item == player.Weapon ? " (wielded)" : item == player.Armor ? " (worn)" : ""));
            }
            return lines;
        }
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Config config = new(ReadRows("config.txt"));
        List<MonsterType> monsters = ReadRows("monsters.txt").Select(tokens => new MonsterType(tokens)).ToList();
        List<ItemType> items = ReadRows("items.txt").Select(ItemType.Parse).ToList();
        Game game = new(config, monsters, items, ExpandCommands(ReadRows("commands.txt")));
        game.Run();
        List<string> maps = new(game.MapLines);
        maps.AddRange(game.FinalBlock());
        Dictionary<string, List<string>> files = new() { ["messages.txt"] = game.Messages, ["maps.txt"] = maps, ["stats.txt"] = game.Stats() };
        Directory.CreateDirectory("output");
        foreach (var pair in files) File.WriteAllText(Path.Combine("output", pair.Key), pair.Value.Count == 0 ? "" : string.Join("\n", pair.Value) + "\n", Encoding.ASCII);
    }
}
