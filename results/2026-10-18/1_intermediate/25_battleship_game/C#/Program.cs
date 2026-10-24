#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

enum GamePhase { Setup, Battle, Over }
enum Strategy { Hunt, Prob, Random }
enum ViewKind { Reef, Unattacked, Miss, Hit, Sunk }
enum ShotKind { Already, Miss, Hit, Sunk }
enum LogMode { Normal, Match, Silent }
readonly record struct Rules(bool Salvo, bool Chain, bool Touch);
readonly record struct Choice(int Cell, string Info);
readonly record struct Shot(ShotKind Kind, int Ship = -1)
{
    public bool IsHit => Kind is ShotKind.Hit or ShotKind.Sunk;
    public string Text => Kind == ShotKind.Sunk ? $"SUNK {Board.ShipNames[Ship]}" : Kind.ToString().ToUpperInvariant();
}
sealed class CommandError(string message) : Exception(message);

static class Board
{
    public static readonly string[] ShipNames = ["CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER"];
    public static readonly int[] Lengths = [5, 4, 3, 3, 2];
    public const string Symbols = "CBRSD";
    public static readonly int[][] Around = Enumerable.Range(0, 100).Select(cell =>
    {
        var neighbors = new List<int>();
        for (int dr = -1; dr <= 1; dr++)
            for (int dc = -1; dc <= 1; dc++)
            {
                int next = Step(cell, dr, dc);
                if ((dr != 0 || dc != 0) && next >= 0) neighbors.Add(next);
            }
        return neighbors.ToArray();
    }).ToArray();

    public static int Step(int cell, int dr, int dc)
    {
        int row = cell / 10 + dr, column = cell % 10 + dc;
        return row >= 0 && row < 10 && column >= 0 && column < 10 ? row * 10 + column : -1;
    }
    public static string Cell(int cell) => $"{(char)('A' + cell / 10)}{cell % 10 + 1}";
    public static int ParseCell(string text) => (text[0] - 'A') * 10 + int.Parse(text.AsSpan(1)) - 1;
    public static string Range(int[] cells) => $"{Cell(cells[0])}-{Cell(cells[^1])}";
    public static long Next(long state) => 48271 * state % 2147483647;
    public static string Name(Strategy strategy) => strategy.ToString().ToUpperInvariant();
    public static Strategy ParseStrategy(string text) => Enum.Parse<Strategy>(text, true);
    public static string Switch(bool value) => value ? "ON" : "OFF";
    public static int[]? Positions(int start, bool horizontal, int length)
    {
        if (horizontal ? start % 10 + length > 10 : start / 10 + length > 10) return null;
        return Enumerable.Range(0, length).Select(i => start + i * (horizontal ? 1 : 10)).ToArray();
    }
    public static bool Touches(int[] first, int[] second) => first.Any(cell => Around[cell].Any(second.Contains));
}

sealed class Player(long seed)
{
    public int[][] Ships { get; } = Enumerable.Range(0, 5).Select(_ => Array.Empty<int>()).ToArray();
    public int[] Owner { get; } = Enumerable.Repeat(-1, 100).ToArray();
    public bool[] Attacked { get; } = new bool[100];
    public List<int> Candidates { get; } = [];
    public long Random = seed;
    public Strategy? Controller;
    public bool TorpedoUsed, SonarUsed;
    public long Shots, Hits, Sinks, Turns, Streak, BestStreak, Wins;
    public bool Sunk(int ship) => Ships[ship].Length > 0 && Ships[ship].All(cell => Attacked[cell]);
    public int Placed => Ships.Count(cells => cells.Length > 0);
    public int Afloat => Enumerable.Range(0, 5).Count(ship => Ships[ship].Length > 0 && !Sunk(ship));

    public void SetShip(int ship, int[] cells)
    {
        foreach (int cell in Ships[ship]) Owner[cell] = -1;
        Ships[ship] = cells;
        foreach (int cell in cells) Owner[cell] = ship;
    }
    public void ClearFleet()
    {
        for (int ship = 0; ship < 5; ship++) SetShip(ship, []);
    }
    public void Record(Shot shot)
    {
        Shots++;
        if (shot.IsHit) { Hits++; Streak++; BestStreak = Math.Max(BestStreak, Streak); }
        else Streak = 0;
        if (shot.Kind == ShotKind.Sunk) Sinks++;
    }
}

sealed record View(ViewKind[] Cells, bool[] Excluded, int[] Remaining)
{
    public bool Candidate(int cell) => cell >= 0 && cell < 100 && Cells[cell] == ViewKind.Unattacked && !Excluded[cell];
}

sealed class Game
{
    public Player[] Players { get; } = [new(1), new(2)];
    public bool[] Reefs = new bool[100];
    public Rules Rules;
    public GamePhase Phase = GamePhase.Setup;
    public int Current, Winner = -1;
    public int Allowance(int player) => Rules.Salvo ? Players[player].Afloat : 1;
    public void SetupCheck() { if (Phase != GamePhase.Setup) throw new CommandError("setup closed"); }
    public void TurnCheck(int player)
    {
        if (Phase == GamePhase.Over) throw new CommandError("game over");
        if (Phase == GamePhase.Setup && Players.Any(p => p.Placed != 5)) throw new CommandError("fleets not ready");
        if (player != Current) throw new CommandError("not your turn");
    }
    public string? PlacementProblem(int player, int[]? cells)
    {
        if (cells is null) return "out of bounds";
        if (cells.Any(cell => Reefs[cell])) return "on reef";
        int first = 5;
        foreach (int cell in cells) if (Players[player].Owner[cell] >= 0) first = Math.Min(first, Players[player].Owner[cell]);
        if (first < 5) return $"overlaps {Board.ShipNames[first]}";
        if (!Rules.Touch)
        {
            foreach (int cell in cells)
                foreach (int neighbor in Board.Around[cell])
                    if (Players[player].Owner[neighbor] >= 0) first = Math.Min(first, Players[player].Owner[neighbor]);
            if (first < 5) return $"touches {Board.ShipNames[first]}";
        }
        return null;
    }
    public long AutoPlace(int player, long seed)
    {
        Player owner = Players[player];
        owner.Random = seed;
        owner.ClearFleet();
        long attempts = 0;
        for (int ship = 0; ship < 5; ship++)
            while (true)
            {
                attempts++;
                int length = Board.Lengths[ship];
                owner.Random = Board.Next(owner.Random);
                bool horizontal = owner.Random % 2 == 0;
                owner.Random = Board.Next(owner.Random);
                int k = (int)(owner.Random % (10 * (11 - length)));
                int start = horizontal ? k / (11 - length) * 10 + k % (11 - length) : k;
                int[] cells = Board.Positions(start, horizontal, length)!;
                if (PlacementProblem(player, cells) is not null) continue;
                owner.SetShip(ship, cells);
                break;
            }
        return attempts;
    }
    public void Layout(int player, string layout)
    {
        string flat = layout.Replace("/", "");
        var ships = new int[5][];
        for (int ship = 0; ship < 5; ship++)
        {
            int[] cells = Enumerable.Range(0, 100).Where(cell => flat[cell] == Board.Symbols[ship]).ToArray();
            string name = Board.ShipNames[ship];
            int length = Board.Lengths[ship];
            if (cells.Length != length) throw new CommandError($"{name} has {cells.Length} cells");
            bool horizontal = Enumerable.Range(0, length).All(i => cells[i] == cells[0] + i && cells[i] / 10 == cells[0] / 10);
            bool vertical = Enumerable.Range(0, length).All(i => cells[i] == cells[0] + 10 * i);
            if (!horizontal && !vertical) throw new CommandError($"{name} not straight");
            if (cells.Any(cell => Reefs[cell])) throw new CommandError($"{name} on reef");
            ships[ship] = cells;
        }
        if (!Rules.Touch)
            for (int first = 0; first < 5; first++)
                for (int second = first + 1; second < 5; second++)
                    if (Board.Touches(ships[first], ships[second])) throw new CommandError($"{Board.ShipNames[first]} touches {Board.ShipNames[second]}");
        Players[player].ClearFleet();
        for (int ship = 0; ship < 5; ship++) Players[player].SetShip(ship, ships[ship]);
    }
    public void PlacedLines(int player, List<string> output)
    {
        for (int ship = 0; ship < 5; ship++) output.Add($"PLACED {player + 1} {Board.ShipNames[ship]} {Board.Range(Players[player].Ships[ship])}");
    }
    public View GetView(int player)
    {
        Player opponent = Players[1 - player];
        bool[] sunk = Enumerable.Range(0, 5).Select(opponent.Sunk).ToArray();
        var cells = new ViewKind[100];
        for (int cell = 0; cell < 100; cell++)
        {
            int ship = opponent.Owner[cell];
            cells[cell] = Reefs[cell] ? ViewKind.Reef : !opponent.Attacked[cell] ? ViewKind.Unattacked :
                ship < 0 ? ViewKind.Miss : sunk[ship] ? ViewKind.Sunk : ViewKind.Hit;
        }
        var excluded = new bool[100];
        if (!Rules.Touch)
            for (int cell = 0; cell < 100; cell++)
                if (cells[cell] == ViewKind.Sunk) foreach (int neighbor in Board.Around[cell]) excluded[neighbor] = true;
        return new View(cells, excluded, Enumerable.Range(0, 5).Where(ship => !sunk[ship]).ToArray());
    }
    public static int[] Scores(View view)
    {
        var scores = new int[100];
        foreach (int ship in view.Remaining)
            for (int start = 0; start < 100; start++)
                foreach (bool horizontal in new[] { true, false })
                {
                    int[]? cells = Board.Positions(start, horizontal, Board.Lengths[ship]);
                    if (cells is null || cells.Any(cell => view.Excluded[cell] || view.Cells[cell] is not (ViewKind.Unattacked or ViewKind.Hit))) continue;
                    int weight = 1 + 10 * cells.Count(cell => view.Cells[cell] == ViewKind.Hit);
                    foreach (int cell in cells) scores[cell] += weight;
                }
        return scores;
    }
    public static int Best(View view, int[] scores)
    {
        int chosen = -1;
        for (int cell = 0; cell < 100; cell++)
            if (view.Cells[cell] == ViewKind.Unattacked && (chosen < 0 || scores[cell] > scores[chosen])) chosen = cell;
        return chosen;
    }
    public Choice Choose(int player, Strategy strategy, bool advanceRandom)
    {
        View view = GetView(player);
        if (strategy == Strategy.Prob)
        {
            int[] scores = Scores(view);
            int chosen = Best(view, scores);
            return new Choice(chosen, scores[chosen].ToString());
        }
        if (strategy == Strategy.Random)
        {
            int[] candidates = Enumerable.Range(0, 100).Where(view.Candidate).ToArray();
            long random = Board.Next(Players[player].Random);
            if (advanceRandom) Players[player].Random = random;
            return new Choice(candidates[(int)(random % candidates.Length)], candidates.Length.ToString());
        }
        for (int cell = 0; cell < 100; cell++)
        {
            if (view.Cells[cell] != ViewKind.Hit) continue;
            foreach ((int dr, int dc) in new[] { (0, 1), (1, 0) })
            {
                int front = Board.Step(cell, dr, dc);
                if (front < 0 || view.Cells[front] != ViewKind.Hit) continue;
                while (front >= 0 && view.Cells[front] == ViewKind.Hit) front = Board.Step(front, dr, dc);
                int back = Board.Step(cell, -dr, -dc);
                if (view.Candidate(front)) return new Choice(front, "LINE");
                if (view.Candidate(back)) return new Choice(back, "LINE");
            }
        }
        List<int> stack = Players[player].Candidates;
        for (int i = stack.Count - 1; i >= 0; i--)
            if (view.Candidate(stack[i])) return new Choice(stack[i], "STACK");
        int shortest = view.Remaining.Min(ship => Board.Lengths[ship]);
        return new Choice(Enumerable.Range(0, 100).First(cell => view.Candidate(cell) && (cell / 10 + cell % 10) % shortest == 0), "PARITY");
    }
    public Shot Shoot(int player, int cell)
    {
        Player owner = Players[player], opponent = Players[1 - player];
        Shot result;
        if (opponent.Attacked[cell]) result = new Shot(ShotKind.Already);
        else
        {
            opponent.Attacked[cell] = true;
            int ship = opponent.Owner[cell];
            result = ship < 0 ? new Shot(ShotKind.Miss) : opponent.Sunk(ship) ? new Shot(ShotKind.Sunk, ship) : new Shot(ShotKind.Hit);
            if (result.Kind == ShotKind.Hit)
                foreach ((int dr, int dc) in new[] { (0, -1), (1, 0), (0, 1), (-1, 0) })
                {
                    int neighbor = Board.Step(cell, dr, dc);
                    if (neighbor >= 0) owner.Candidates.Add(neighbor);
                }
        }
        owner.Record(result);
        return result;
    }
    private void EndTurn(int player, bool hit, LogMode mode, List<string>? output)
    {
        Players[player].Turns++;
        if (Players[1 - player].Afloat == 0)
        {
            Phase = GamePhase.Over; Winner = player; Players[player].Wins++;
            if (mode == LogMode.Normal) output!.Add($"WINNER {player + 1}");
        }
        else Current = Rules.Chain && hit ? player : 1 - player;
    }
    public void ShootTurn(int player, Strategy? strategy, int[]? targets, LogMode mode, List<string>? output)
    {
        int allowance = Allowance(player);
        Phase = GamePhase.Battle;
        bool hit = false;
        for (int i = 0; i < allowance; i++)
        {
            int cell = strategy is Strategy ai ? Choose(player, ai, true).Cell : targets![i];
            Shot result = Shoot(player, cell);
            hit |= result.IsHit;
            if (mode == LogMode.Normal) output!.Add($"SHOT {player + 1} {Board.Cell(cell)} {result.Text}");
            else if (mode == LogMode.Match && result.Kind == ShotKind.Sunk) output!.Add($"SINK {player + 1} {Board.ShipNames[result.Ship]} {Players[player].Shots}");
            if (Players[1 - player].Afloat == 0) break;
        }
        EndTurn(player, hit, mode, output);
    }
    public void Torpedo(int player, int row, bool west, List<string> output)
    {
        Phase = GamePhase.Battle;
        Players[player].TorpedoUsed = true;
        Player opponent = Players[1 - player];
        string result = "MISS";
        bool stoppedAtShip = false, hit = false;
        for (int i = 0; i < 10; i++)
        {
            int cell = row * 10 + (west ? i : 9 - i);
            if (Reefs[cell]) { result = $"REEF {Board.Cell(cell)}"; break; }
            if (opponent.Owner[cell] >= 0)
            {
                Shot shot = Shoot(player, cell);
                result = $"{shot.Text} {Board.Cell(cell)}";
                hit = shot.IsHit; stoppedAtShip = true; break;
            }
            opponent.Attacked[cell] = true;
        }
        if (!stoppedAtShip) Players[player].Record(new Shot(ShotKind.Miss));
        output.Add($"TORPEDO {player + 1} {(char)('A' + row)} {(west ? "W" : "E")} {result}");
        EndTurn(player, hit, LogMode.Normal, output);
    }
    public void Sonar(int player, int cell, List<string> output)
    {
        Phase = GamePhase.Battle;
        Players[player].SonarUsed = true;
        Player opponent = Players[1 - player];
        int count = Board.Around[cell].Append(cell).Count(at => opponent.Owner[at] >= 0 && !opponent.Attacked[at]);
        output.Add($"SONAR {player + 1} {Board.Cell(cell)} {count}");
        EndTurn(player, false, LogMode.Normal, output);
    }
    public void Automatic(List<string> output)
    {
        while (Phase == GamePhase.Battle && Players[Current].Controller is Strategy strategy)
            ShootTurn(Current, strategy, null, LogMode.Normal, output);
    }
    public void Show(int player, bool radar, List<string> output)
    {
        output.Add($"{(radar ? "RADAR" : "BOARD")} {player + 1}");
        output.Add("  1 2 3 4 5 6 7 8 9 10");
        View? view = radar ? GetView(player) : null;
        Player owner = Players[player];
        for (int row = 0; row < 10; row++)
        {
            var symbols = new string[10];
            for (int column = 0; column < 10; column++)
            {
                int cell = row * 10 + column;
                char symbol;
                if (view is not null) symbol = view.Cells[cell] switch { ViewKind.Reef => '~', ViewKind.Unattacked => '.', ViewKind.Miss => 'o', ViewKind.Hit => 'x', _ => '#' };
                else if (Reefs[cell]) symbol = '~';
                else if (owner.Owner[cell] is int ship && ship >= 0) symbol = owner.Attacked[cell] ? char.ToLowerInvariant(Board.Symbols[ship]) : Board.Symbols[ship];
                else symbol = owner.Attacked[cell] ? 'o' : '.';
                symbols[column] = symbol.ToString();
            }
            output.Add($"{(char)('A' + row)} {string.Join(' ', symbols)}");
        }
    }
    public void Density(int player, List<string> output)
    {
        View view = GetView(player);
        int[] scores = Scores(view);
        output.Add($"DENSITY {player + 1}");
        output.Add(" " + string.Concat(Enumerable.Range(1, 10).Select(column => column.ToString().PadLeft(5))));
        for (int row = 0; row < 10; row++)
        {
            string text = ((char)('A' + row)).ToString();
            for (int column = 0; column < 10; column++)
            {
                int cell = row * 10 + column;
                string value = view.Cells[cell] == ViewKind.Unattacked ? scores[cell].ToString() : view.Cells[cell] == ViewKind.Reef ? "~" : "-";
                text += value.PadLeft(5);
            }
            output.Add(text);
        }
        int best = Best(view, scores);
        output.Add($"BEST {Board.Cell(best)} {scores[best]}");
    }
    public void Fleet(int player, List<string> output)
    {
        Player owner = Players[player];
        output.Add($"FLEET {player + 1} afloat {owner.Afloat}");
        for (int ship = 0; ship < 5; ship++)
        {
            int[] cells = owner.Ships[ship];
            output.Add(cells.Length == 0 ? $"{Board.ShipNames[ship]} unplaced" :
                $"{Board.ShipNames[ship]} {Board.Range(cells)} {cells.Count(cell => owner.Attacked[cell])}/{Board.Lengths[ship]} {(owner.Sunk(ship) ? "SUNK" : "AFLOAT")}");
        }
    }
    public string Export(int player) => string.Join('/', Enumerable.Range(0, 10).Select(row =>
        new string(Enumerable.Range(row * 10, 10).Select(cell => Players[player].Owner[cell] < 0 ? '.' : Board.Symbols[Players[player].Owner[cell]]).ToArray())));
    public string Status()
    {
        string text = $"STATUS {Phase.ToString().ToUpperInvariant()} salvo {Board.Switch(Rules.Salvo)} chain {Board.Switch(Rules.Chain)} touch {Board.Switch(Rules.Touch)} reefs {Reefs.Count(value => value)}";
        if (Phase == GamePhase.Setup) return $"{text} placed {Players[0].Placed} {Players[1].Placed}";
        string afloat = $"afloat {Players[0].Afloat} {Players[1].Afloat}";
        return Phase == GamePhase.Battle ? $"{text} turn {Current + 1} shots {Allowance(Current)} {afloat}" : $"{text} winner {Winner + 1} {afloat}";
    }
    public void Stats(List<string> output)
    {
        for (int i = 0; i < 2; i++)
        {
            Player player = Players[i];
            string accuracy = player.Shots == 0 ? "-" : $"{player.Hits * 100 / player.Shots}%";
            output.Add($"STATS {i + 1} shots {player.Shots} hits {player.Hits} sunk {player.Sinks} turns {player.Turns} streak {player.BestStreak} accuracy {accuracy} wins {player.Wins}");
        }
    }
    public Game Match(long firstSeed, long secondSeed, Strategy first, Strategy second, List<string>? sinks = null)
    {
        var game = new Game { Rules = Rules, Reefs = (bool[])Reefs.Clone(), Phase = GamePhase.Battle };
        game.AutoPlace(0, firstSeed); game.AutoPlace(1, secondSeed);
        Strategy[] strategies = [first, second];
        while (game.Phase == GamePhase.Battle)
            game.ShootTurn(game.Current, strategies[game.Current], null, sinks is null ? LogMode.Silent : LogMode.Match, sinks);
        return game;
    }
}

sealed class Program
{
    private Game game = new();
    private static readonly HashSet<string> SetupCommands = ["PLACE", "REMOVE", "AUTOPLACE", "LAYOUT", "REEF", "SALVO", "CHAIN", "TOUCH"];
    private static readonly HashSet<string> TurnCommands = ["FIRE", "AI", "TORPEDO", "SONAR"];

    public List<string> Execute(string[] words)
    {
        string command = words[0];
        var output = new List<string>();
        if (SetupCommands.Contains(command)) game.SetupCheck();
        if (TurnCommands.Contains(command))
        {
            int player = int.Parse(words[1]) - 1;
            game.TurnCheck(player);
            switch (command)
            {
                case "FIRE":
                    int[] cells = words.Skip(2).Select(Board.ParseCell).ToArray();
                    if (cells.Length != game.Allowance(player)) throw new CommandError($"expected {game.Allowance(player)} shots");
                    foreach (int cell in cells) if (game.Reefs[cell]) throw new CommandError($"reef at {Board.Cell(cell)}");
                    game.ShootTurn(player, null, cells, LogMode.Normal, output); break;
                case "AI": game.ShootTurn(player, Board.ParseStrategy(words[2]), null, LogMode.Normal, output); break;
                case "TORPEDO":
                    if (game.Players[player].TorpedoUsed) throw new CommandError("torpedo used");
                    game.Torpedo(player, words[2][0] - 'A', words[3] == "W", output); break;
                case "SONAR":
                    if (game.Players[player].SonarUsed) throw new CommandError("sonar used");
                    game.Sonar(player, Board.ParseCell(words[2]), output); break;
            }
            game.Automatic(output);
            return output;
        }
        switch (command)
        {
            case "NEW":
            {
                long[] wins = game.Players.Select(player => player.Wins).ToArray();
                game = new Game();
                for (int i = 0; i < 2; i++) game.Players[i].Wins = wins[i];
                output.Add("NEW"); break;
            }
            case "PLACE":
            {
                int player = int.Parse(words[1]) - 1, ship = Array.IndexOf(Board.ShipNames, words[2]);
                if (game.Players[player].Ships[ship].Length > 0) throw new CommandError($"{words[2]} already placed");
                int[]? cells = Board.Positions(Board.ParseCell(words[3]), words[4] == "H", Board.Lengths[ship]);
                if (game.PlacementProblem(player, cells) is string problem) throw new CommandError(problem);
                game.Players[player].SetShip(ship, cells!);
                output.Add($"PLACED {player + 1} {words[2]} {Board.Range(cells!)}"); break;
            }
            case "REMOVE":
            {
                int player = int.Parse(words[1]) - 1, ship = Array.IndexOf(Board.ShipNames, words[2]);
                if (game.Players[player].Ships[ship].Length == 0) throw new CommandError($"{words[2]} not placed");
                game.Players[player].SetShip(ship, []); output.Add($"REMOVED {player + 1} {words[2]}"); break;
            }
            case "AUTOPLACE":
            {
                int player = int.Parse(words[1]) - 1;
                long attempts = game.AutoPlace(player, long.Parse(words[2]));
                output.Add($"AUTOPLACE {player + 1} attempts {attempts}"); game.PlacedLines(player, output); break;
            }
            case "LAYOUT":
            {
                int player = int.Parse(words[1]) - 1;
                game.Layout(player, words[2]); output.Add($"LAYOUT {player + 1}"); game.PlacedLines(player, output); break;
            }
            case "REEF":
            {
                int cell = Board.ParseCell(words[1]);
                if (game.Reefs[cell]) throw new CommandError($"reef exists at {Board.Cell(cell)}");
                for (int player = 0; player < 2; player++)
                    if (game.Players[player].Owner[cell] is int ship && ship >= 0) throw new CommandError($"{Board.Cell(cell)} occupied by {player + 1} {Board.ShipNames[ship]}");
                game.Reefs[cell] = true; output.Add($"REEF {Board.Cell(cell)}"); break;
            }
            case "SALVO": case "CHAIN": case "TOUCH":
                bool enabled = words[1] == "ON";
                game.Rules = command switch { "SALVO" => game.Rules with { Salvo = enabled }, "CHAIN" => game.Rules with { Chain = enabled }, _ => game.Rules with { Touch = enabled } };
                output.Add($"{command} {words[1]}"); break;
            case "CONTROL":
            {
                int player = int.Parse(words[1]) - 1;
                game.Players[player].Controller = words[2] == "HUMAN" ? null : Board.ParseStrategy(words[2]);
                output.Add($"CONTROL {player + 1} {words[2]}"); break;
            }
            case "SEED":
            {
                int player = int.Parse(words[1]) - 1;
                long seed = long.Parse(words[2]);
                game.Players[player].Random = seed;
                output.Add($"SEED {player + 1} {seed}"); break;
            }
            case "RESIGN":
            {
                if (game.Phase != GamePhase.Battle) throw new CommandError("not in battle");
                int player = int.Parse(words[1]) - 1;
                game.Winner = 1 - player; game.Phase = GamePhase.Over; game.Players[game.Winner].Wins++;
                output.Add($"RESIGN {player + 1}"); output.Add($"WINNER {game.Winner + 1}"); break;
            }
            case "HINT":
            {
                if (game.Phase == GamePhase.Over) throw new CommandError("game over");
                int player = int.Parse(words[1]) - 1;
                Choice choice = game.Choose(player, Board.ParseStrategy(words[2]), false);
                output.Add($"HINT {player + 1} {words[2]} {Board.Cell(choice.Cell)} {choice.Info}"); break;
            }
            case "DENSITY":
                if (game.Phase == GamePhase.Over) throw new CommandError("game over");
                game.Density(int.Parse(words[1]) - 1, output); break;
            case "SHOW": case "RADAR": game.Show(int.Parse(words[1]) - 1, command == "RADAR", output); break;
            case "EXPORT":
            {
                int player = int.Parse(words[1]) - 1;
                output.Add($"EXPORT {player + 1} {game.Export(player)}"); break;
            }
            case "FLEET": game.Fleet(int.Parse(words[1]) - 1, output); break;
            case "STATUS": output.Add(game.Status()); break;
            case "STATS": game.Stats(output); break;
            case "MATCH":
            {
                output.Add($"MATCH 1 {words[3]} 2 {words[4]}");
                Game match = game.Match(long.Parse(words[1]), long.Parse(words[2]), Board.ParseStrategy(words[3]), Board.ParseStrategy(words[4]), output);
                output.Add($"RESULT winner {match.Winner + 1} shots {match.Players[0].Shots} {match.Players[1].Shots} hits {match.Players[0].Hits} {match.Players[1].Hits}"); break;
            }
            case "SERIES":
            {
                int count = int.Parse(words[1]); long random = long.Parse(words[2]);
                long[] wins = new long[2], shots = new long[2]; long?[] fastest = new long?[2];
                for (int i = 0; i < count; i++)
                {
                    random = Board.Next(random); long first = random; random = Board.Next(random);
                    Game match = game.Match(first, random, Board.ParseStrategy(words[3]), Board.ParseStrategy(words[4]));
                    wins[match.Winner]++;
                    for (int player = 0; player < 2; player++) shots[player] += match.Players[player].Shots;
                    long winningShots = match.Players[match.Winner].Shots;
                    fastest[match.Winner] = Math.Min(fastest[match.Winner] ?? winningShots, winningShots);
                }
                output.Add($"SERIES {count} wins {wins[0]} {wins[1]} shots {shots[0]} {shots[1]} fastest {fastest[0]?.ToString() ?? "-"} {fastest[1]?.ToString() ?? "-"}"); break;
            }
            case "TOURNEY":
            {
                int count = int.Parse(words[1]); long random = long.Parse(words[2]);
                long[] wins = new long[3], shots = new long[3];
                for (int first = 0; first < 3; first++)
                    for (int second = 0; second < 3; second++)
                    {
                        if (first == second) continue;
                        for (int i = 0; i < count; i++)
                        {
                            random = Board.Next(random); long firstSeed = random; random = Board.Next(random);
                            Game match = game.Match(firstSeed, random, (Strategy)first, (Strategy)second);
                            wins[match.Winner == 0 ? first : second]++;
                            shots[first] += match.Players[0].Shots; shots[second] += match.Players[1].Shots;
                        }
                    }
                output.Add($"TOURNEY {count}");
                int[] ranking = Enumerable.Range(0, 3).OrderByDescending(i => wins[i]).ThenBy(i => shots[i]).ThenBy(i => i).ToArray();
                for (int rank = 0; rank < 3; rank++)
                {
                    int strategy = ranking[rank];
                    output.Add($"{rank + 1} {Board.Name((Strategy)strategy)} wins {wins[strategy]} shots {shots[strategy]}");
                }
                break;
            }
        }
        return output;
    }

    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!);
        var program = new Program();
        for (int i = 0; i < count; i++)
        {
            try { foreach (string line in program.Execute(Console.ReadLine()!.Split(' '))) Console.WriteLine(line); }
            catch (CommandError error) { Console.WriteLine($"ERROR {error.Message}"); }
        }
    }
}
