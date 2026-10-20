using System;
using System.Collections.Generic;
using System.Linq;

enum PlaceKind { Nowhere, Room, Player, Inside }
readonly record struct Place(PlaceKind Kind, int Index = 0);
enum ContainerState { Open, Closed, Locked }
enum EndStatus { None, Won, Dead }
enum Verb { Go, Look, Examine, Take, Drop, Put, Inventory, Open, Close, Unlock, Lock, Use, Light, Extinguish, Wait, Score, Save, Restore, Verbose, Brief }
readonly record struct Exit(int Destination, int? Key, bool Locked);
abstract record Effect;
sealed record Message(string Text) : Effect;
sealed record OpenExit(int Room, int Direction, int Destination) : Effect;
sealed record MoveItem(int Item, Place Place) : Effect;
sealed record FlagChange(string Flag, bool On) : Effect;
sealed record Points(int Amount) : Effect;
sealed record Rule(string? Flag, bool Required, Effect Effect);
sealed record UseRule(int First, int Second, Rule Rule);
sealed class CommandFailure(string message) : Exception(message);

sealed class Room(string id)
{
    public string Id { get; } = id;
    public string Name = "";
    public bool Dark;
    public List<string> Descriptions { get; } = [];
    public List<Rule> Enter { get; } = [];
}

sealed class Item(string id)
{
    public string Id { get; } = id;
    public string Name = "";
    public int Weight;
    public int? Treasure, Capacity, Key;
    public bool Light, Fixed;
    public HashSet<string> Nouns { get; } = new(StringComparer.Ordinal) { id };
    public HashSet<string> NameWords { get; } = new(StringComparer.Ordinal);
    public List<string> Details { get; } = [];
}

sealed class GameState(int rooms, int items)
{
    public int Room, Bonus, Moves, Darkness;
    public EndStatus End;
    public Place[] Places = new Place[items];
    public ContainerState[] Containers = new ContainerState[items];
    public int[] Fuel = new int[items];
    public bool[] Lit = new bool[items], Visited = new bool[rooms];
    public Exit?[,] Exits = new Exit?[rooms, 6];
    public HashSet<string> Flags = new(StringComparer.Ordinal);

    public GameState Copy() => new(Visited.Length, Places.Length)
    {
        Room = Room, Bonus = Bonus, Moves = Moves, Darkness = Darkness, End = End,
        Places = (Place[])Places.Clone(), Containers = (ContainerState[])Containers.Clone(),
        Fuel = (int[])Fuel.Clone(), Lit = (bool[])Lit.Clone(), Visited = (bool[])Visited.Clone(),
        Exits = (Exit?[,])Exits.Clone(), Flags = new(Flags, StringComparer.Ordinal)
    };
}

sealed class Adventure
{
    static readonly string[] Directions = ["north", "south", "east", "west", "up", "down"];
    static readonly Dictionary<string, Verb> Verbs = MakeVerbs();
    static readonly Place Player = new(PlaceKind.Player);
    readonly Room[] rooms;
    readonly Item[] items;
    readonly List<UseRule> useRules = [];
    readonly HashSet<string> vocabulary = new(StringComparer.Ordinal);
    readonly int trophy, maxWeight;
    GameState state;
    GameState? saved;
    int? pronoun;
    string? previous;
    bool verbose;
    List<string> output = [];

    static Dictionary<string, Verb> MakeVerbs()
    {
        string[] groups = ["go walk run", "look l", "examine x inspect read", "take get grab", "drop discard",
            "put insert place", "inventory inv i", "open", "close shut", "unlock", "lock", "use apply",
            "light ignite", "extinguish douse snuff", "wait z", "score", "save", "restore load", "verbose", "brief"];
        Dictionary<string, Verb> result = new(StringComparer.Ordinal);
        for (int i = 0; i < groups.Length; i++)
            foreach (string word in groups[i].Split(' ')) result[word] = (Verb)i;
        return result;
    }

    static int? Direction(string word)
    {
        for (int i = 0; i < Directions.Length; i++)
            if (word == Directions[i] || word == Directions[i][..1]) return i;
        return null;
    }

    public Adventure(List<string[]> definitions)
    {
        rooms = definitions.Where(x => x[0] == "ROOM").Select(x => new Room(x[1])).ToArray();
        items = definitions.Where(x => x[0] == "ITEM").Select(x => new Item(x[1]))
            .OrderBy(x => x.Id, StringComparer.Ordinal).ToArray();
        var roomIndex = rooms.Select((x, i) => (x.Id, i)).ToDictionary(x => x.Id, x => x.i, StringComparer.Ordinal);
        var itemIndex = items.Select((x, i) => (x.Id, i)).ToDictionary(x => x.Id, x => x.i, StringComparer.Ordinal);
        state = new(rooms.Length, items.Length);
        Place InitialPlace(string text) => text switch
        {
            "PLAYER" => Player, "NOWHERE" => new(PlaceKind.Nowhere), _ => new(PlaceKind.Room, roomIndex[text])
        };
        Rule ParseRule(string[] words, int index)
        {
            string? flag = null;
            bool required = true;
            if (words[index] is "IF" or "UNLESS")
            {
                required = words[index] == "IF"; flag = words[index + 1]; index += 2;
            }
            Effect effect = words[index] switch
            {
                "MESSAGE" => new Message(string.Join(' ', words.Skip(index + 1))),
                "OPEN" => new OpenExit(roomIndex[words[index + 1]], Direction(words[index + 2])!.Value, roomIndex[words[index + 3]]),
                "REMOVE" => new MoveItem(itemIndex[words[index + 1]], new(PlaceKind.Nowhere)),
                "ADD" => new MoveItem(itemIndex[words[index + 1]], new(PlaceKind.Room, roomIndex[words[index + 2]])),
                "SET" => new FlagChange(words[index + 1], true),
                "CLEAR" => new FlagChange(words[index + 1], false),
                "POINTS" => new Points(int.Parse(words[index + 1])),
                _ => throw new InvalidOperationException()
            };
            return new(flag, required, effect);
        }
        foreach (string[] words in definitions)
        {
            switch (words[0])
            {
                case "ROOM":
                {
                    Room room = rooms[roomIndex[words[1]]];
                    room.Dark = words[2] == "DARK";
                    room.Name = string.Join(' ', words.Skip(room.Dark ? 3 : 2));
                    break;
                }
                case "DESC": rooms[roomIndex[words[1]]].Descriptions.Add(string.Join(' ', words.Skip(2))); break;
                case "EXIT":
                    state.Exits[roomIndex[words[1]], Direction(words[2])!.Value] =
                        new Exit(roomIndex[words[3]], words.Length > 4 ? itemIndex[words[5]] : null, words.Length > 4);
                    break;
                case "ITEM":
                {
                    int x = itemIndex[words[1]], index = 4;
                    Item item = items[x];
                    state.Places[x] = InitialPlace(words[2]); item.Weight = int.Parse(words[3]);
                    if (words[index] == "TREASURE") { item.Treasure = int.Parse(words[index + 1]); index += 2; }
                    if (words[index] == "LIGHT") { item.Light = true; state.Fuel[x] = int.Parse(words[index + 1]); index += 2; }
                    if (words[index] == "CONTAINER")
                    {
                        item.Capacity = int.Parse(words[index + 1]); index += 2;
                        if (words[index] == "CLOSED") { state.Containers[x] = ContainerState.Closed; index++; }
                        if (words[index] == "LOCKED") { item.Key = itemIndex[words[index + 1]]; state.Containers[x] = ContainerState.Locked; index += 2; }
                    }
                    if (words[index] == "FIXED") { item.Fixed = true; index++; }
                    item.Name = string.Join(' ', words.Skip(index)); item.NameWords.UnionWith(words.Skip(index));
                    break;
                }
                case "INSIDE": state.Places[itemIndex[words[1]]] = new(PlaceKind.Inside, itemIndex[words[2]]); break;
                case "ALIAS": items[itemIndex[words[1]]].Nouns.Add(words[2]); break;
                case "DETAIL": items[itemIndex[words[1]]].Details.Add(string.Join(' ', words.Skip(2))); break;
                case "RULE": useRules.Add(new(itemIndex[words[1]], itemIndex[words[2]], ParseRule(words, 3))); break;
                case "ENTER": rooms[roomIndex[words[1]]].Enter.Add(ParseRule(words, 2)); break;
                case "TROPHY": trophy = roomIndex[words[1]]; break;
                case "START": state.Room = roomIndex[words[1]]; break;
                case "MAXWEIGHT": maxWeight = int.Parse(words[1]); break;
            }
        }
        state.Visited[state.Room] = true;
        foreach (Item item in items) { vocabulary.UnionWith(item.Nouns); vocabulary.UnionWith(item.NameWords); }
    }

    static void Fail(string message) => throw new CommandFailure(message);
    void Say(string text) => output.Add(text);
    Place Floor => new(PlaceKind.Room, state.Room);
    int[] Direct(Place place) => Enumerable.Range(0, items.Length).Where(x => state.Places[x] == place).ToArray();
    HashSet<int> Reachable(Place place)
    {
        HashSet<int> result = [];
        void Visit(Place source)
        {
            foreach (int x in Direct(source))
            {
                result.Add(x);
                if (items[x].Capacity.HasValue && state.Containers[x] == ContainerState.Open) Visit(new(PlaceKind.Inside, x));
            }
        }
        Visit(place);
        return result;
    }
    HashSet<int> Carried() => Reachable(Player);
    bool IsLit() => !rooms[state.Room].Dark || Reachable(Player).Concat(Reachable(Floor)).Any(x => state.Lit[x]);
    HashSet<int> Visible()
    {
        HashSet<int> result = Carried();
        if (IsLit()) result.UnionWith(Reachable(Floor));
        return result;
    }
    int TotalWeight(int x) => items[x].Weight + ContentWeight(x);
    int ContentWeight(int x) => Direct(new(PlaceKind.Inside, x)).Sum(TotalWeight);
    int CarriedWeight() => Direct(Player).Sum(TotalWeight);
    bool Within(int x, int container)
    {
        while (state.Places[x].Kind == PlaceKind.Inside)
        {
            x = state.Places[x].Index;
            if (x == container) return true;
        }
        return false;
    }
    bool Stored(int x)
    {
        while (state.Places[x].Kind == PlaceKind.Inside) x = state.Places[x].Index;
        return state.Places[x] == new Place(PlaceKind.Room, trophy);
    }
    (int Points, int Stored, int Total) Treasures()
    {
        int points = 0, stored = 0, total = 0;
        for (int x = 0; x < items.Length; x++) if (items[x].Treasure is int value)
        {
            total++;
            if (Stored(x)) { points += value; stored++; }
        }
        return (points, stored, total);
    }
    int Score => Treasures().Points + state.Bonus;
    string DisplayName(int x)
    {
        List<string> annotations = [];
        if (items[x].Capacity.HasValue) annotations.Add(state.Containers[x].ToString().ToLowerInvariant());
        if (state.Lit[x]) annotations.Add("lit");
        return items[x].Name + (annotations.Count == 0 ? "" : " (" + string.Join(", ", annotations) + ")");
    }
    void ItemTree(Place place, int depth)
    {
        foreach (int x in Direct(place))
        {
            Say(new string(' ', depth * 2) + DisplayName(x));
            if (items[x].Capacity.HasValue && state.Containers[x] == ContainerState.Open) ItemTree(new(PlaceKind.Inside, x), depth + 1);
        }
    }
    void Describe(bool full)
    {
        if (!IsLit()) { Say("It is pitch dark."); return; }
        Room room = rooms[state.Room];
        Say(room.Name);
        if (full) output.AddRange(room.Descriptions);
        List<string> exits = [];
        for (int d = 0; d < 6; d++) if (state.Exits[state.Room, d] is Exit exit)
            exits.Add(Directions[d] + (exit.Locked ? " (locked)" : ""));
        Say("Exits: " + (exits.Count == 0 ? "none" : string.Join(", ", exits)));
        if (Direct(Floor).Length > 0) { Say("You see:"); ItemTree(Floor, 1); }
    }
    int Resolve(string[] phrase)
    {
        HashSet<int> visible = Visible();
        if (phrase.Length == 1 && phrase[0] == "it")
        {
            if (!pronoun.HasValue) Fail("I don't know what \"it\" refers to.");
            if (!visible.Contains(pronoun!.Value)) Fail("You can't see any such thing.");
            return pronoun.Value;
        }
        foreach (string word in phrase) if (!vocabulary.Contains(word)) Fail($"I don't know the word \"{word}\".");
        int[] matches = Enumerable.Range(0, items.Length).Where(x => visible.Contains(x) && items[x].Nouns.Contains(phrase[^1]) &&
            phrase.Take(phrase.Length - 1).All(items[x].NameWords.Contains)).ToArray();
        if (matches.Length == 0) Fail("You can't see any such thing.");
        if (matches.Length > 1) Fail("Which do you mean: " + string.Join(", ", matches.Select(x => items[x].Name)) + "?");
        pronoun = matches[0];
        return matches[0];
    }
    void Examine(int x)
    {
        Item item = items[x];
        if (item.Details.Count == 0) Say($"You see nothing special about the {item.Name}."); else output.AddRange(item.Details);
        if (item.Light) Say($"It is {(state.Lit[x] ? "lit" : "unlit")} (fuel {state.Fuel[x]}).");
        if (item.Capacity.HasValue)
        {
            if (state.Containers[x] == ContainerState.Locked) Say("It is locked.");
            else if (state.Containers[x] == ContainerState.Closed) Say("It is closed.");
            else if (Direct(new(PlaceKind.Inside, x)).Length == 0) Say("It is empty.");
            else { Say("It contains:"); ItemTree(new(PlaceKind.Inside, x), 1); }
        }
        if (item.Treasure is int points) Say($"It is a treasure worth {points} points.");
        Say($"It weighs {TotalWeight(x)}.");
    }

    static bool All(string[] phrase) => phrase.Length == 1 && phrase[0] == "all";
    void RequireContainer(int x)
    {
        if (!items[x].Capacity.HasValue) Fail($"The {items[x].Name} is not a container.");
        if (state.Containers[x] != ContainerState.Open) Fail($"The {items[x].Name} is closed.");
    }
    bool Take(string[] target, string[]? from)
    {
        if (!IsLit()) Fail("It is pitch dark.");
        int? container = null;
        Place source = Floor;
        if (from is not null)
        {
            container = Resolve(from); RequireContainer(container.Value);
            source = new(PlaceKind.Inside, container.Value);
        }
        if (All(target))
        {
            int[] candidates = Direct(source).Where(x => !items[x].Fixed).ToArray();
            if (candidates.Length == 0) Fail(container.HasValue ? $"There is nothing in the {items[container.Value].Name} to take." : "There is nothing here to take.");
            bool taken = false;
            foreach (int x in candidates)
            {
                if (!Carried().Contains(x) && CarriedWeight() + TotalWeight(x) > maxWeight)
                    Say($"{items[x].Name}: You can't carry any more.");
                else { state.Places[x] = Player; taken = true; Say($"{items[x].Name}: Taken."); }
            }
            return taken;
        }
        int item = Resolve(target);
        if (container.HasValue && state.Places[item] != source) Fail($"The {items[item].Name} is not in the {items[container.Value].Name}.");
        if (state.Places[item] == Player) Fail($"You already have the {items[item].Name}.");
        if (items[item].Fixed) Fail($"The {items[item].Name} is fixed in place.");
        if (!Carried().Contains(item) && CarriedWeight() + TotalWeight(item) > maxWeight) Fail("You can't carry any more.");
        state.Places[item] = Player; Say("Taken.");
        return true;
    }
    void Drop(string[] target)
    {
        if (All(target))
        {
            int[] direct = Direct(Player);
            if (direct.Length == 0) Fail("You are empty-handed.");
            foreach (int x in direct) { state.Places[x] = Floor; Say($"{items[x].Name}: Dropped."); }
            return;
        }
        int item = Resolve(target);
        if (!Carried().Contains(item)) Fail($"You aren't carrying the {items[item].Name}.");
        state.Places[item] = Floor; Say("Dropped.");
    }
    string? PutItem(int x, int y)
    {
        if (Within(y, x)) return $"The {items[y].Name} is inside the {items[x].Name}.";
        if (state.Places[x] == new Place(PlaceKind.Inside, y)) return $"The {items[x].Name} is already in the {items[y].Name}.";
        int weight = ContentWeight(y) + (Within(x, y) ? 0 : TotalWeight(x));
        if (weight > items[y].Capacity!.Value) return $"The {items[x].Name} doesn't fit in the {items[y].Name}.";
        state.Places[x] = new(PlaceKind.Inside, y);
        return null;
    }
    bool Put(string[] first, string[] second)
    {
        if (All(first))
        {
            int y = Resolve(second); RequireContainer(y);
            int[] candidates = Direct(Player).Where(x => x != y).ToArray();
            if (candidates.Length == 0) Fail($"You have nothing to put in the {items[y].Name}.");
            bool moved = false;
            foreach (int x in candidates)
            {
                string? reason = PutItem(x, y);
                if (reason is null) moved = true;
                Say(items[x].Name + ": " + (reason ?? "Done."));
            }
            return moved;
        }
        int item = Resolve(first), container = Resolve(second);
        if (!Carried().Contains(item)) Fail($"You aren't carrying the {items[item].Name}.");
        if (item == container) Fail($"You can't put the {items[item].Name} inside itself.");
        RequireContainer(container);
        string? failure = PutItem(item, container);
        if (failure is not null) Fail(failure);
        Say($"You put the {items[item].Name} in the {items[container].Name}.");
        return true;
    }
    void Open(int x)
    {
        string name = items[x].Name;
        if (!items[x].Capacity.HasValue) Fail($"You can't open the {name}.");
        if (state.Containers[x] == ContainerState.Open) Fail($"The {name} is already open.");
        if (state.Containers[x] == ContainerState.Locked) Fail($"The {name} is locked.");
        state.Containers[x] = ContainerState.Open;
        int[] children = Direct(new(PlaceKind.Inside, x));
        Say(children.Length == 0 ? "Opened." : $"Opening the {name} reveals " + string.Join(", ", children.Select(y => items[y].Name)) + ".");
    }
    void Close(int x)
    {
        if (!items[x].Capacity.HasValue) Fail($"You can't close the {items[x].Name}.");
        if (state.Containers[x] != ContainerState.Open) Fail($"The {items[x].Name} is already closed.");
        state.Containers[x] = ContainerState.Closed; Say("Closed.");
    }
    void CheckKey(int key, string[]? phrase)
    {
        if (phrase is not null)
        {
            int x = Resolve(phrase);
            if (!Carried().Contains(x)) Fail($"You aren't carrying the {items[x].Name}.");
            if (x != key) Fail($"The {items[x].Name} doesn't fit.");
        }
        else
        {
            if (!Carried().Contains(key)) Fail("You don't have the right key.");
            Say($"(with the {items[key].Name})");
        }
    }
    void Lock(string[] target, string[]? keyPhrase, bool locking)
    {
        int? direction = target.Length == 1 ? Direction(target[0]) : null;
        if (direction is int d)
        {
            Exit? possible = state.Exits[state.Room, d];
            if (!possible.HasValue) Fail($"There is no exit {Directions[d]}.");
            Exit exit = possible!.Value;
            if (!exit.Key.HasValue) Fail($"The way {Directions[d]} has no lock.");
            if (exit.Locked == locking) Fail($"The way {Directions[d]} is {(locking ? "already locked" : "not locked")}.");
            CheckKey(exit.Key!.Value, keyPhrase);
            state.Exits[state.Room, d] = exit with { Locked = locking };
            if (state.Exits[exit.Destination, d ^ 1] is Exit opposite && opposite.Destination == state.Room && opposite.Key == exit.Key)
                state.Exits[exit.Destination, d ^ 1] = opposite with { Locked = locking };
        }
        else
        {
            int x = Resolve(target);
            if (!items[x].Capacity.HasValue || !items[x].Key.HasValue) Fail($"The {items[x].Name} has no lock.");
            if ((state.Containers[x] == ContainerState.Locked) == locking)
                Fail($"The {items[x].Name} is {(locking ? "already locked" : "not locked")}.");
            if (locking && state.Containers[x] == ContainerState.Open) Fail($"You must close the {items[x].Name} first.");
            CheckKey(items[x].Key!.Value, keyPhrase);
            state.Containers[x] = locking ? ContainerState.Locked : ContainerState.Closed;
        }
        Say(locking ? "Locked." : "Unlocked.");
    }
    (int Executed, bool Message) RunRules(IEnumerable<Rule> rules)
    {
        int executed = 0;
        bool message = false;
        foreach (Rule rule in rules)
        {
            if (rule.Flag is not null && state.Flags.Contains(rule.Flag) != rule.Required) continue;
            executed++;
            switch (rule.Effect)
            {
                case Message effect: Say(effect.Text); message = true; break;
                case OpenExit effect: state.Exits[effect.Room, effect.Direction] = new Exit(effect.Destination, null, false); break;
                case MoveItem effect: state.Places[effect.Item] = effect.Place; break;
                case FlagChange effect:
                    if (effect.On) state.Flags.Add(effect.Flag); else state.Flags.Remove(effect.Flag);
                    break;
                case Points effect: state.Bonus += effect.Amount; break;
            }
        }
        return (executed, message);
    }
    void Use(string[] first, string[] second)
    {
        int x = Resolve(first), y = Resolve(second);
        if (!Carried().Contains(x)) Fail($"You aren't carrying the {items[x].Name}.");
        var result = RunRules(useRules.Where(rule => rule.First == x && rule.Second == y).Select(rule => rule.Rule));
        if (result.Executed == 0) Fail("Nothing happens.");
        if (!result.Message) Say("Done.");
    }
    void Light(int x, bool lighting)
    {
        string verb = lighting ? "light" : "extinguish", name = items[x].Name;
        if (!items[x].Light) Fail($"You can't {verb} the {name}.");
        if (state.Lit[x] == lighting) Fail($"The {name} is {(lighting ? "already lit" : "not lit")}.");
        if (lighting && state.Fuel[x] == 0) Fail($"The {name} has no fuel.");
        state.Lit[x] = lighting;
        Say($"The {name} is now {(lighting ? "lit" : "out")}.");
    }
    bool Move(int direction)
    {
        Exit? possible = state.Exits[state.Room, direction];
        if (!possible.HasValue) Fail("You can't go that way.");
        Exit exit = possible!.Value;
        if (exit.Locked) Fail($"The way {Directions[direction]} is locked.");
        state.Room = exit.Destination;
        bool baseline = IsLit();
        Describe(verbose || !state.Visited[state.Room]);
        state.Visited[state.Room] = true;
        RunRules(rooms[state.Room].Enter);
        return baseline;
    }
    void Turn(bool baseline)
    {
        state.Moves++;
        HashSet<int> reachable = Carried(); reachable.UnionWith(Reachable(Floor));
        for (int x = 0; x < items.Length; x++) if (state.Lit[x])
        {
            state.Fuel[x]--;
            if (state.Fuel[x] == 0)
            {
                state.Lit[x] = false;
                if (reachable.Contains(x)) Say($"The {items[x].Name} goes out.");
            }
        }
        bool lit = IsLit();
        if (baseline && !lit) Say("It is now pitch dark.");
        else if (!baseline && lit) Describe(true);
        state.Darkness = lit ? 0 : state.Darkness + 1;
        if (state.Darkness == 2) Say("You hear something moving in the dark.");
        if (state.Darkness == 3) state.End = EndStatus.Dead;
        var treasure = Treasures();
        if (state.End == EndStatus.None && treasure.Total > 0 && treasure.Stored == treasure.Total) state.End = EndStatus.Won;
        if (state.End != EndStatus.None)
        {
            Say(state.End == EndStatus.Dead ? "*** You have died ***" : "*** You have won ***");
            Say($"You scored {treasure.Points + state.Bonus} points in {state.Moves} moves.");
        }
    }
    void Run(Verb verb, string[] first, string[]? second = null, int direction = 0)
    {
        bool baseline = IsLit(), success = true;
        switch (verb)
        {
            case Verb.Go: baseline = Move(direction); break;
            case Verb.Look: Describe(true); break;
            case Verb.Examine: Examine(Resolve(first)); break;
            case Verb.Take: success = Take(first, second); break;
            case Verb.Drop: Drop(first); break;
            case Verb.Put: success = Put(first, second!); break;
            case Verb.Open: Open(Resolve(first)); break;
            case Verb.Close: Close(Resolve(first)); break;
            case Verb.Unlock: Lock(first, second, false); break;
            case Verb.Lock: Lock(first, second, true); break;
            case Verb.Use: Use(first, second!); break;
            case Verb.Light: Light(Resolve(first), true); break;
            case Verb.Extinguish: Light(Resolve(first), false); break;
            case Verb.Wait: Say("Time passes."); break;
            case Verb.Inventory:
                if (Direct(Player).Length == 0) Say("You are empty-handed.");
                else { Say("You are carrying:"); ItemTree(Player, 1); Say($"Total weight: {CarriedWeight()}/{maxWeight}"); }
                break;
            case Verb.Score:
                var treasure = Treasures();
                Say($"You have scored {treasure.Points + state.Bonus} points (treasure {treasure.Points}, bonus {state.Bonus}) in {state.Moves} moves.");
                Say($"Treasures stored: {treasure.Stored} of {treasure.Total}.");
                break;
            case Verb.Save: saved = state.Copy(); Say("Game saved."); break;
            case Verb.Restore:
                if (saved is null) Fail("There is no saved game.");
                state = saved!.Copy(); Say("Game restored."); Describe(true);
                break;
            case Verb.Verbose: verbose = true; Say("Verbose mode."); break;
            case Verb.Brief: verbose = false; Say("Brief mode."); break;
        }
        if (success && verb is Verb.Go or Verb.Take or Verb.Drop or Verb.Put or Verb.Open or Verb.Close or Verb.Unlock or Verb.Lock or Verb.Use or Verb.Light or Verb.Extinguish or Verb.Wait)
            Turn(baseline);
    }
    static string[] Words(string line) => line.ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries)
        .Where(word => word is not ("the" or "a" or "an")).ToArray();
    void Interpret(string[] words)
    {
        if (words.Length == 0) Fail("I beg your pardon?");
        if (Direction(words[0]).HasValue) words = ["go", .. words];
        if (!Verbs.TryGetValue(words[0], out Verb verb)) Fail($"I don't know the verb \"{words[0]}\".");
        string[] rest = words[1..];
        if (state.End != EndStatus.None && verb != Verb.Restore) Fail("The game is over.");
        if (verb == Verb.Look && rest.Length > 0)
        {
            if (rest[0] != "at") Fail("I don't understand that.");
            verb = Verb.Examine; rest = rest[1..];
        }
        if (verb is Verb.Look or Verb.Inventory or Verb.Wait or Verb.Score or Verb.Save or Verb.Restore or Verb.Verbose or Verb.Brief)
        {
            if (rest.Length != 0) Fail("I don't understand that.");
            Run(verb, rest); return;
        }
        if (rest.Length == 0) Fail(verb == Verb.Go ? "Which way do you want to go?" : $"What do you want to {verb.ToString().ToLowerInvariant()}?");
        if (verb == Verb.Go)
        {
            int? direction = rest.Length == 1 ? Direction(rest[0]) : null;
            if (!direction.HasValue) Fail("I don't understand that.");
            Run(verb, rest, direction: direction!.Value); return;
        }
        string[] prepositions = verb switch
        {
            Verb.Put => ["in", "into"], Verb.Use => ["on", "with"],
            Verb.Lock or Verb.Unlock when rest.Contains("with") => ["with"],
            Verb.Take when rest.Contains("from") => ["from"], _ => []
        };
        if (prepositions.Length == 0) { Run(verb, rest); return; }
        int split = Array.FindIndex(rest, prepositions.Contains);
        if (split <= 0 || split == rest.Length - 1) Fail("I don't understand that.");
        Run(verb, rest[..split], rest[(split + 1)..]);
    }
    public List<string> Start()
    {
        output = []; Describe(true); return output;
    }
    public List<string> Process(string line)
    {
        output = []; Say("> " + line);
        try
        {
            string[] words = Words(line);
            if (words.Length > 0 && words[0] is "again" or "g")
            {
                if (words.Length != 1) Fail("I don't understand that.");
                if (previous is null) Fail("There is nothing to repeat.");
                words = Words(previous!);
            }
            else previous = line;
            Interpret(words);
        }
        catch (CommandFailure failure) { Say(failure.Message); }
        return output;
    }
    public string FinalScore() => $"Final score: {Score} points in {state.Moves} moves.";
}

static class Program
{
    static void Main()
    {
        List<string[]> definitions = [];
        for (string line = Console.ReadLine()!; line != "BEGIN"; line = Console.ReadLine()!) definitions.Add(line.Split(' '));
        Adventure adventure = new(definitions);
        foreach (string row in adventure.Start()) Console.WriteLine(row);
        for (string line = Console.ReadLine()!; line != "QUIT"; line = Console.ReadLine()!)
            foreach (string row in adventure.Process(line)) Console.WriteLine(row);
        Console.WriteLine(adventure.FinalScore());
    }
}
