using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Program
{
    const string WaveColumns = "wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives";
    static readonly string[] IncomeFields = { "bounty", "reward", "interest", "early", "refund" };
    static List<string> Read(string name) => File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    static void Write(string name, List<string> lines) => File.WriteAllText(Path.Combine("output", name), lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);
    static string OneDecimal(long numerator, long denominator) { if (denominator == 0) return "-"; long rounded = (20 * numerator + denominator) / (2 * denominator); return rounded / 10 + "." + rounded % 10; }
    static char Digit(int count) => count == 0 ? '.' : count < 10 ? (char)('0' + count) : '*';
    static List<string> Ruled(char[][] rows)
    {
        var lines = new List<string> { "  " + new string(Enumerable.Range(0, rows[0].Length).Select(x => (char)('0' + x % 10)).ToArray()) };
        for (int y = 0; y < rows.Length; y++) lines.Add(y % 10 + " " + new string(rows[y]));
        return lines;
    }

    sealed class Params
    {
        public int Gold, Lives, InterestRate, InterestCap, SellRate, Start, Interval, Early;
        public HashSet<int> Snapshots { get; }
        public Params(List<string> lines)
        {
            string[][] fields = lines.Select(line => line.Split(' ')).ToArray();
            Gold = int.Parse(fields[0][1]); Lives = int.Parse(fields[1][1]); InterestRate = int.Parse(fields[2][1]); InterestCap = int.Parse(fields[2][2]);
            SellRate = int.Parse(fields[3][1]); Start = int.Parse(fields[4][1]); Interval = int.Parse(fields[4][2]); Early = int.Parse(fields[5][1]);
            Snapshots = fields[6].Skip(1).Select(int.Parse).ToHashSet();
        }
    }
    sealed record Action(int Tick, string Command, List<string> Arguments)
    {
        public static Action Parse(string line) { string[] fields = line.Split(' '); return new Action(int.Parse(fields[0]), fields[1], fields.Skip(2).ToList()); }
    }
    sealed class WaveRecord
    {
        public int Number { get; }
        public int Start { get; }
        public Wave Plan { get; }
        public int[] Released { get; }
        public Dictionary<int, int> TowerDamage { get; } = new();
        public int End, Spawned, Peak, Kills, Leaks, LivesLost, Bounty, Reward, Interest, Gold, Lives;
        public string Status = "";
        public WaveRecord(int number, Wave plan, int start) { Number = number; Plan = plan; Start = start; Released = new int[plan.Groups.Count]; }
        public bool AllReleased() { for (int i = 0; i < Released.Length; i++) if (Released[i] != Plan.Groups[i].Count) return false; return true; }
        public void Close(string status, int tick, int gold, int lives) { Status = status; End = tick; Gold = gold; Lives = lives; }
        public string Row(int towerCount)
        {
            var values = new List<object> { Number, Start, End, Status, Spawned, Peak, Kills, Leaks, LivesLost, Bounty, Reward, Interest, Gold, Lives };
            for (int number = 1; number <= towerCount; number++) values.Add(TowerDamage.GetValueOrDefault(number));
            return string.Join(",", values);
        }
    }

    sealed class Game
    {
        readonly GridMap grid;
        readonly Dictionary<string, TowerType> towerTypes;
        readonly List<EnemyType> enemyTypes;
        readonly List<Wave> waves;
        readonly Params parameters;
        readonly Point exitCenter;
        readonly List<Tower> towers = new();
        readonly List<Enemy> enemies = new(), allEnemies = new();
        List<Projectile> projectiles = new();
        readonly List<WaveRecord> records = new();
        readonly Dictionary<string, int> income = new(StringComparer.Ordinal);
        readonly int[][] killCounts;
        DistanceField field;
        WaveRecord? active;
        int? nextStart;
        string? outcome;
        int tick, gold, lives, projectileCount, spent, done, refused;
        public List<string> Events { get; } = new();
        public List<string> Snapshots { get; } = new();

        public Game(GridMap grid, List<TowerType> towerTypes, WaveData data, Params parameters)
        {
            this.grid = grid; this.towerTypes = towerTypes.ToDictionary(type => type.Name, StringComparer.Ordinal); enemyTypes = data.Types; waves = data.Waves; this.parameters = parameters;
            exitCenter = grid.Exit.Center(); gold = parameters.Gold; lives = parameters.Lives; nextStart = parameters.Start; field = new DistanceField(grid, new HashSet<Cell>());
            killCounts = Enumerable.Range(0, grid.Height).Select(_ => new int[grid.Width]).ToArray();
            foreach (string name in IncomeFields) income[name] = 0;
        }
        void Record(params object[] parts) => Events.Add(tick + (parts.Length == 0 ? "" : " " + string.Join(" ", parts)));
        void AddIncome(string name, int amount) => income[name] += amount;
        List<Tower> StandingTowers() => towers.Where(tower => tower.Standing).ToList();
        HashSet<Cell> TowerCells() => StandingTowers().Select(tower => tower.Cell).ToHashSet();
        Tower? TowerAt(Cell cell) => towers.FirstOrDefault(tower => tower.Standing && tower.Cell == cell);
        Tower? StandingTower(string text) { int number = int.Parse(text); return number >= 1 && number <= towers.Count && towers[number - 1].Standing ? towers[number - 1] : null; }
        List<Enemy> GroundEnemies() => enemies.Where(enemy => !enemy.Flying).ToList();

        public void Run(List<Action> actions)
        {
            int index = 0;
            while (true)
            {
                tick++;
                while (index < actions.Count && actions[index].Tick == tick) Perform(actions[index++]);
                SpawnEnemies(); MoveEnemies();
                if (outcome != null) break;
                FireTowers(); MoveProjectiles(); CheckWaveEnd();
                if (parameters.Snapshots.Contains(tick)) Snapshots.AddRange(Block("SNAPSHOT"));
                if (outcome != null) break;
            }
            Snapshots.AddRange(FinalBlock());
        }
        void Perform(Action action)
        {
            bool success = action.Command switch
            {
                "BUILD" => Build(action.Arguments),
                "UPGRADE" => Upgrade(action.Arguments),
                "SELL" => Sell(action.Arguments),
                "TARGET" => SetTarget(action.Arguments),
                _ => CallWave()
            };
            if (success) done++; else refused++;
        }
        string? BuildRefusal(string name, Cell cell)
        {
            if (!towerTypes.ContainsKey(name)) return "type";
            if (!grid.Inside(cell)) return "bounds";
            if (!grid.Buildable(cell)) return "terrain";
            if (TowerAt(cell) != null) return "tower";
            if (gold < towerTypes[name].Levels[0].Cost) return "gold";
            List<Enemy> walkers = GroundEnemies();
            foreach (Enemy enemy in walkers) if (enemy.Cell == cell || enemy.Next == cell) return "enemy";
            HashSet<Cell> blocked = TowerCells(); blocked.Add(cell);
            var trial = new DistanceField(grid, blocked);
            foreach (Cell spawn in grid.Spawns) if (trial.At(spawn) < 0) return "blocked";
            foreach (Enemy enemy in walkers) if (trial.At(enemy.Next) < 0) return "blocked";
            return null;
        }
        bool Build(List<string> args)
        {
            string name = args[0]; var cell = new Cell(int.Parse(args[1]), int.Parse(args[2]));
            string? reason = BuildRefusal(name, cell);
            if (reason != null) { Record("BUILD_REFUSED", name, args[1], args[2], reason); return false; }
            TowerType kind = towerTypes[name]; int cost = kind.Levels[0].Cost;
            var tower = new Tower(towers.Count + 1, kind, cell, tick); towers.Add(tower); gold -= cost; spent += cost;
            Record("BUILD", "T" + tower.Number, name, cell.X, cell.Y, "cost", cost, "gold", gold); UpdateField(); return true;
        }
        bool Upgrade(List<string> args)
        {
            Tower? tower = StandingTower(args[0]); string reason;
            if (tower == null) reason = "notower";
            else if (tower.Level == tower.Kind.Levels.Count) reason = "maxlevel";
            else if (gold < tower.Kind.Levels[tower.Level].Cost) reason = "gold";
            else
            {
                int cost = tower.Kind.Levels[tower.Level].Cost; gold -= cost; spent += cost; tower.Level++; tower.Investment += cost;
                Record("UPGRADE", "T" + tower.Number, "level", tower.Level, "cost", cost, "gold", gold); return true;
            }
            Record("UPGRADE_REFUSED", "T" + args[0], reason); return false;
        }
        bool Sell(List<string> args)
        {
            Tower? tower = StandingTower(args[0]);
            if (tower == null) { Record("SELL_REFUSED", "T" + args[0], "notower"); return false; }
            int rate = tick == tower.Built ? 100 : parameters.SellRate, refund = tower.Investment * rate / 100;
            tower.Sold = tick; gold += refund; AddIncome("refund", refund); Record("SELL", "T" + tower.Number, "refund", refund, "gold", gold); UpdateField(); return true;
        }
        bool SetTarget(List<string> args)
        {
            Tower? tower = StandingTower(args[0]); string reason;
            if (tower == null) reason = "notower";
            else if (!Towers.TargetModes.Contains(args[1])) reason = "mode";
            else { tower.Mode = args[1]; Record("TARGET", "T" + tower.Number, tower.Mode); return true; }
            Record("TARGET_REFUSED", "T" + args[0], reason); return false;
        }
        bool CallWave()
        {
            if (active != null) { Record("CALL_REFUSED", "active"); return false; }
            int bonus = (nextStart!.Value - tick) * parameters.Early; gold += bonus; AddIncome("early", bonus); nextStart = tick;
            Record("CALL", records.Count + 1, "bonus", bonus, "gold", gold); return true;
        }
        void UpdateField()
        {
            DistanceField before = field; field = new DistanceField(grid, TowerCells());
            for (int i = 0; i < grid.Spawns.Count; i++) { Cell spawn = grid.Spawns[i]; if (before.At(spawn) != field.At(spawn)) Record("REPATH", i + 1, before.At(spawn), field.At(spawn)); }
        }
        void StartWave()
        {
            Wave plan = waves[records.Count]; active = new WaveRecord(records.Count + 1, plan, tick); records.Add(active); nextStart = null;
            Record("WAVE_START", active.Number, "enemies", plan.EnemyCount);
        }
        void AddEnemy(Enemy enemy) { enemies.Add(enemy); allEnemies.Add(enemy); active!.Spawned++; enemy.Kind.Spawned++; }
        void RemoveEnemy(Enemy enemy) { enemy.Alive = false; enemies.Remove(enemy); }
        void SpawnEnemies()
        {
            if (nextStart != null && tick == nextStart) StartWave();
            if (active == null) return;
            for (int i = 0; i < active.Plan.Groups.Count; i++)
            {
                Group group = active.Plan.Groups[i]; int released = active.Released[i];
                if (released == group.Count || group.SpawnTick(active.Start, released) != tick) continue;
                active.Released[i]++; Cell spawn = grid.Spawns[group.Spawn - 1]; var enemy = new Enemy(allEnemies.Count + 1, group.Kind, group.Multiplier);
                if (enemy.Flying) enemy.Point = spawn.Center(); else { enemy.Cell = spawn; enemy.Next = field.Next(spawn); }
                AddEnemy(enemy); Record("SPAWN", "E" + enemy.Number, enemy.Kind.Name, group.Spawn, "hp", enemy.Hp);
            }
            active.Peak = Math.Max(active.Peak, enemies.Count);
        }
        void MoveEnemies() { foreach (Enemy enemy in enemies.ToArray()) { MoveEnemy(enemy); if (outcome != null) return; } }
        void MoveEnemy(Enemy enemy)
        {
            if (enemy.Burn.Active)
            {
                Tower source = towers[enemy.Burn.Source - 1]; int damage = Math.Min(enemy.Hp, enemy.Burn.Strength); enemy.Hp -= damage; Credit(source, enemy, damage); enemy.Burn.AdvanceTime();
                if (enemy.Hp == 0) { Kill(enemy, source); return; }
            }
            enemy.Hp = Math.Min(enemy.Hp + enemy.Kind.Regen, enemy.MaxHp);
            int speed = enemy.SlowedSpeed(); if (enemy.Slow.Active) enemy.Slow.AdvanceTime();
            bool arrived;
            if (enemy.Flying) { Combat.Advance movement = Combat.AdvancePoint(enemy.Point, exitCenter, speed); enemy.Point = movement.Point; arrived = movement.Arrived; }
            else arrived = Walk(enemy, speed);
            if (arrived) Leak(enemy);
        }
        bool Walk(Enemy enemy, int speed)
        {
            if (grid.Water(enemy.OccupiedCell())) speed /= 2;
            while (speed > 0)
            {
                int rest = 100 - enemy.Progress;
                if (speed < rest) { enemy.Progress += speed; speed = 0; }
                else { speed -= rest; enemy.Cell = enemy.Next; enemy.Progress = 0; if (enemy.Cell == grid.Exit) return true; enemy.Next = field.Next(enemy.Cell); }
            }
            return false;
        }
        void Leak(Enemy enemy)
        {
            RemoveEnemy(enemy); int lost = Math.Min(lives, enemy.Kind.Lives); lives -= lost; active!.Leaks++; active.LivesLost += lost; enemy.Kind.Leaks++;
            Record("LEAK", "E" + enemy.Number, enemy.Kind.Name, "lives", lives);
            if (lives == 0) { Record("DEFEAT"); outcome = "defeat"; active.Close("lost", tick, gold, lives); active = null; }
        }
        void FireTowers()
        {
            foreach (Tower tower in StandingTowers())
            {
                if (tick < tower.Ready) continue;
                Enemy? target = tower.SelectTarget(enemies, field);
                if (target != null)
                {
                    projectileCount++; projectiles.Add(new Projectile(projectileCount, tower, target)); tower.Shots++; tower.Ready = tick + tower.Stats().Interval; Record("SHOT", "T" + tower.Number, "E" + target.Number);
                }
            }
        }
        void MoveProjectiles()
        {
            var flying = new List<Projectile>();
            foreach (Projectile projectile in projectiles)
            {
                Enemy target = allEnemies[projectile.Target - 1]; if (target.Alive) projectile.Aim = target.Position();
                if (projectile.Fly()) Impact(projectile); else flying.Add(projectile);
            }
            projectiles = flying;
        }
        void Impact(Projectile projectile)
        {
            Tower tower = towers[projectile.Tower - 1]; Enemy target = allEnemies[projectile.Target - 1]; List<Enemy> victims;
            if (projectile.Stats.Splash == 0) victims = target.Alive ? new List<Enemy> { target } : new List<Enemy>();
            else victims = enemies.Where(enemy => Towers.CanAim(projectile.Targets, enemy) && Combat.SquaredDistance(enemy.Position(), projectile.Aim) <= (long)projectile.Stats.Splash * projectile.Stats.Splash).ToList();
            if (victims.Count == 0) tower.Fizzles++;
            foreach (Enemy enemy in victims)
            {
                tower.Hits++; int damage = Combat.Damage(enemy.Hp, projectile.Stats.Power, enemy.Kind.Armor); enemy.Hp -= damage; Credit(tower, enemy, damage);
                if (enemy.Hp == 0) { Kill(enemy, tower); continue; }
                if (projectile.Stats.SlowRate > 0) enemy.Slow.Receive(projectile.Stats.SlowRate, projectile.Stats.SlowTime, 0);
                if (projectile.Stats.BurnAmount > 0) enemy.Burn.Receive(projectile.Stats.BurnAmount, projectile.Stats.BurnTime, tower.Number);
            }
        }
        void Credit(Tower tower, Enemy enemy, int damage)
        {
            tower.Damage += damage; enemy.Kind.Damage += damage;
            active!.TowerDamage[tower.Number] = active.TowerDamage.GetValueOrDefault(tower.Number) + damage;
        }
        void Kill(Enemy enemy, Tower tower)
        {
            RemoveEnemy(enemy); Cell cell = enemy.OccupiedCell(); killCounts[cell.Y][cell.X]++; int bounty = enemy.Kind.Bounty;
            tower.Kills++; active!.Kills++; enemy.Kind.Kills++; gold += bounty; active.Bounty += bounty; AddIncome("bounty", bounty);
            Record("KILL", "E" + enemy.Number, enemy.Kind.Name, "T" + tower.Number, "bounty", bounty, "gold", gold);
            for (int i = 0; i < enemy.Kind.SplitCount; i++) { Enemy child = enemy.Split(allEnemies.Count + 1); AddEnemy(child); Record("SPAWN", "E" + child.Number, child.Kind.Name, "E" + enemy.Number, "hp", child.Hp); }
        }
        void CheckWaveEnd()
        {
            if (active == null || enemies.Count > 0 || !active.AllReleased()) return;
            WaveRecord wave = active; int reward = wave.Plan.Reward; gold += reward; int interest = Math.Min(parameters.InterestCap, gold * parameters.InterestRate / 100); gold += interest;
            wave.Reward = reward; wave.Interest = interest; AddIncome("reward", reward); AddIncome("interest", interest); active = null;
            Record("WAVE_END", wave.Number, "reward", reward, "interest", interest, "gold", gold);
            if (wave.Number == waves.Count) { Record("VICTORY"); outcome = "victory"; }
            else nextStart = tick + parameters.Interval;
            wave.Close("cleared", tick, gold, lives);
        }
        char[][] MapPicture()
        {
            char[][] rows = grid.Rows.Select(row => row.ToCharArray()).ToArray();
            foreach (Cell spawn in grid.Spawns) foreach (Cell cell in field.Path(spawn)) if (grid.Terrain(cell) is '.' or '~') rows[cell.Y][cell.X] = '+';
            foreach (Tower tower in StandingTowers()) rows[tower.Cell.Y][tower.Cell.X] = tower.Kind.Symbol;
            foreach (var group in enemies.GroupBy(enemy => enemy.OccupiedCell())) rows[group.Key.Y][group.Key.X] = group.Count() == 1 ? group.First().Kind.Symbol : '*';
            return rows;
        }
        char[][] FlowPicture()
        {
            char[][] rows = Enumerable.Range(0, grid.Height).Select(_ => new char[grid.Width]).ToArray();
            for (int y = 0; y < grid.Height; y++) for (int x = 0; x < grid.Width; x++)
            {
                var cell = new Cell(x, y); char terrain = grid.Terrain(cell); Tower? tower = TowerAt(cell);
                rows[y][x] = terrain is '#' or 'E' ? terrain : tower != null ? tower.Kind.Symbol : field.At(cell) < 0 ? '?' : "^>v<"[field.Direction(cell)];
            }
            return rows;
        }
        char[][] CoveragePicture()
        {
            char[][] rows = Enumerable.Range(0, grid.Height).Select(_ => new char[grid.Width]).ToArray();
            List<Tower> standing = StandingTowers();
            for (int y = 0; y < grid.Height; y++) for (int x = 0; x < grid.Width; x++)
            {
                var cell = new Cell(x, y); Tower? tower = TowerAt(cell);
                rows[y][x] = grid.Rock(cell) ? '#' : tower != null ? tower.Kind.Symbol : Digit(standing.Count(other => other.InRange(cell.Center())));
            }
            return rows;
        }
        char[][] KillsPicture()
        {
            char[][] rows = Enumerable.Range(0, grid.Height).Select(_ => new char[grid.Width]).ToArray();
            for (int y = 0; y < grid.Height; y++) for (int x = 0; x < grid.Width; x++) rows[y][x] = killCounts[y][x] > 0 ? Digit(killCounts[y][x]) : grid.Rock(new Cell(x, y)) ? '#' : '.';
            return rows;
        }
        List<string> Block(string label)
        {
            string next = active == null && outcome == null ? nextStart!.Value.ToString(CultureInfo.InvariantCulture) : "-";
            var lines = new List<string> { $"{label} {tick} wave {records.Count} next {next} gold {gold} lives {lives}" };
            lines.AddRange(Ruled(MapPicture()));
            for (int i = 0; i < grid.Spawns.Count; i++) lines.Add($"PATH {i + 1} length {field.At(grid.Spawns[i])}");
            foreach (Tower tower in StandingTowers()) lines.Add($"T{tower.Number} {tower.Kind.Name} {tower.Cell.X} {tower.Cell.Y} level {tower.Level} mode {tower.Mode} ready {tower.Ready}");
            foreach (Enemy enemy in enemies)
            {
                Point point = enemy.Position();
                lines.Add($"E{enemy.Number} {enemy.Kind.Name} {point.X} {point.Y} hp {enemy.Hp}/{enemy.MaxHp} slow {enemy.Slow.Strength} {enemy.Slow.Remaining} burn {enemy.Burn.Strength} {enemy.Burn.Remaining}");
            }
            foreach (Projectile projectile in projectiles) lines.Add($"P{projectile.Number} T{projectile.Tower} E{projectile.Target} {projectile.Position.X} {projectile.Position.Y}");
            return lines;
        }
        List<string> FinalBlock()
        {
            List<string> lines = Block("FINAL"); lines.Add("FLOW"); lines.AddRange(Ruled(FlowPicture())); lines.Add("COVERAGE"); lines.AddRange(Ruled(CoveragePicture())); lines.Add("KILLS"); lines.AddRange(Ruled(KillsPicture())); return lines;
        }
        public List<string> WaveLines()
        {
            string header = WaveColumns + string.Concat(towers.Select(tower => ",T" + tower.Number));
            var lines = new List<string> { header }; lines.AddRange(records.Select(wave => wave.Row(towers.Count))); return lines;
        }
        string MvpLine()
        {
            Tower? best = null; foreach (Tower tower in towers) if (best == null || tower.Damage > best.Damage) best = tower;
            return best == null ? "mvp -" : $"mvp T{best.Number} damage {best.Damage}";
        }
        static string TowerLine(Tower tower, int totalDamage)
        {
            string state = tower.Standing ? "active" : "sold " + tower.Sold;
            return $"TOWER T{tower.Number} {tower.Kind.Name} {tower.Cell.X} {tower.Cell.Y} level {tower.Level} mode {tower.Mode} {state} shots {tower.Shots} hits {tower.Hits} fizzles {tower.Fizzles} kills {tower.Kills} damage {tower.Damage} per_shot {OneDecimal(tower.Damage, tower.Shots)} share {OneDecimal(100L * tower.Damage, totalDamage)} invested {tower.Investment}";
        }
        public List<string> SummaryLines(int actionCount)
        {
            var cleared = records.Where(wave => wave.Status == "cleared").ToList();
            int perfect = cleared.Count(wave => wave.Leaks == 0);
            int spawned = enemyTypes.Sum(type => type.Spawned), killed = enemyTypes.Sum(type => type.Kills), leaked = enemyTypes.Sum(type => type.Leaks), totalDamage = towers.Sum(tower => tower.Damage);
            long score = 10L * killed + 100L * lives + 50L * perfect + gold;
            var lines = new List<string>
            {
                "outcome " + outcome, "ticks " + tick, $"waves {cleared.Count}/{waves.Count} perfect {perfect}", $"lives {lives}/{parameters.Lives}", "gold " + gold,
                $"enemies spawned {spawned} killed {killed} leaked {leaked}", "income " + string.Join(" ", IncomeFields.Select(name => name + " " + income[name])), "spent " + spent, "damage " + totalDamage,
                $"actions total {actionCount} done {done} refused {refused} unused {actionCount - done - refused}", "score " + score, MvpLine()
            };
            foreach (EnemyType type in enemyTypes) lines.Add($"ENEMY {type.Name} spawned {type.Spawned} killed {type.Kills} leaked {type.Leaks} damage {type.Damage}");
            foreach (Tower tower in towers) lines.Add(TowerLine(tower, totalDamage));
            return lines;
        }
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        GridMap grid = GridMap.Read(); List<TowerType> towerTypes = Towers.Parse(Read("towers.txt")); WaveData data = Enemies.Parse(Read("waves.txt"));
        List<Action> actions = Read("actions.txt").Select(Action.Parse).ToList(); var parameters = new Params(Read("params.txt"));
        var game = new Game(grid, towerTypes, data, parameters); game.Run(actions); Directory.CreateDirectory("output");
        Write("events.txt", game.Events); Write("waves.csv", game.WaveLines()); Write("snapshots.txt", game.Snapshots); Write("summary.txt", game.SummaryLines(actions.Count));
    }
}
