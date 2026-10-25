using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

sealed class CommandError(string message) : Exception(message);

enum Phase { Idle, Insurance, Play }
enum Finish { Bust, Surrender, Charlie }
enum Outcome { Blackjack, Win, Charlie, Push, Lose, Bust, Surrender }
enum PlayerAction { Hit, Stand, Double, Split, Surrender }
enum DoubleRule { Any, Hard9, Hard10 }

readonly record struct Card(int Code)
{
    public int Rank => Code % 13;
    public int Suit => Code / 13;
    public int Points => Math.Min(Rank + 1, 10);
    public bool Black => Suit is 0 or 3;
    public override string ToString() => $"{"A23456789TJQK"[Rank]}{"CDHS"[Suit]}";
}

static class Format
{
    public static long Integer(string word, long minimum, long maximum)
    {
        if (word.Length is < 1 or > 10 || word.Length > 1 && word[0] == '0')
            throw new CommandError($"bad value {word}");
        long value = 0;
        foreach (char ch in word)
        {
            if (ch is < '0' or > '9') throw new CommandError($"bad value {word}");
            value = value * 10 + ch - '0';
        }
        if (value < minimum || value > maximum) throw new CommandError($"bad value {word}");
        return value;
    }

    public static string Choice(string word, params string[] choices) => choices.Contains(word)
        ? word : throw new CommandError($"bad value {word}");
    public static string Signed(long value) => (value >= 0 ? "+" : "") + value;
    public static string Switch(bool enabled) => enabled ? "ON" : "OFF";
    public static string Action(PlayerAction action) => action.ToString().ToLowerInvariant();

    public static (int Value, bool Soft) Total(IReadOnlyList<Card> cards)
    {
        int sum = 0;
        bool ace = false;
        foreach (Card card in cards) { sum += card.Points; ace |= card.Rank == 0; }
        bool soft = ace && sum + 10 <= 21;
        return (sum + (soft ? 10 : 0), soft);
    }

    public static bool Blackjack(IReadOnlyList<Card> cards, bool split = false) =>
        !split && cards.Count == 2 && Total(cards).Value == 21;

    public static string Hand(IReadOnlyList<Card> cards, bool split = false)
    {
        var (value, soft) = Total(cards);
        string status = Blackjack(cards, split) ? "blackjack"
            : value > 21 ? $"bust {value}" : soft ? $"soft {value}" : value.ToString();
        return $"{string.Join(" ", cards)} ({status})";
    }
}

sealed record Rules
{
    public bool HitSoft17 { get; init; }
    public int Penetration { get; init; } = 75;
    public int Minimum { get; init; } = 10;
    public int Maximum { get; init; } = 500;
    public bool SixToFive { get; init; }
    public bool DoubleAfterSplit { get; init; } = true;
    public DoubleRule Doubling { get; init; } = DoubleRule.Any;
    public int Hands { get; init; } = 4;
    public bool ResplitAces { get; init; }
    public bool Surrender { get; init; } = true;
    public int Charlie { get; init; }
    public int SideMaximum { get; init; } = 25;

    public Rules Changed(string name, string word) => name switch
    {
        "DEALER" => this with { HitSoft17 = Format.Choice(word, "S17", "H17") == "H17" },
        "PEN" => this with { Penetration = (int)Format.Integer(word, 50, 90) },
        "MIN" => this with { Minimum = (int)Format.Integer(word, 1, 10000) },
        "MAX" => this with { Maximum = (int)Format.Integer(word, 1, 10000) },
        "BJ" => this with { SixToFive = Format.Choice(word, "3:2", "6:5") == "6:5" },
        "DAS" => this with { DoubleAfterSplit = Format.Choice(word, "ON", "OFF") == "ON" },
        "DOUBLE" => this with
        {
            Doubling = Format.Choice(word, "ANY", "9-11", "10-11") switch
            {
                "ANY" => DoubleRule.Any, "9-11" => DoubleRule.Hard9, _ => DoubleRule.Hard10
            }
        },
        "HANDS" => this with { Hands = (int)Format.Integer(word, 1, 4) },
        "RSA" => this with { ResplitAces = Format.Choice(word, "ON", "OFF") == "ON" },
        "SURRENDER" => this with { Surrender = Format.Choice(word, "ON", "OFF") == "ON" },
        "CHARLIE" => this with { Charlie = Format.Choice(word, "0", "5", "6", "7")[0] - '0' },
        "SIDEMAX" => this with { SideMaximum = (int)Format.Integer(word, 0, 1000) },
        _ => throw new CommandError($"unknown rule {name}")
    };

    public override string ToString()
    {
        string doubling = Doubling switch { DoubleRule.Any => "ANY", DoubleRule.Hard9 => "9-11", _ => "10-11" };
        return $"rules DEALER {(HitSoft17 ? "H17" : "S17")} PEN {Penetration} MIN {Minimum} MAX {Maximum}"
            + $" BJ {(SixToFive ? "6:5" : "3:2")} DAS {Format.Switch(DoubleAfterSplit)} DOUBLE {doubling}"
            + $" HANDS {Hands} RSA {Format.Switch(ResplitAces)} SURRENDER {Format.Switch(Surrender)}"
            + $" CHARLIE {Charlie} SIDEMAX {SideMaximum}";
    }
}

sealed class Hand(IEnumerable<Card> cards, long bet, bool split = false, bool splitAces = false)
{
    public List<Card> Cards { get; } = [.. cards];
    public long Bet = bet;
    public bool Split { get; } = split;
    public bool SplitAces { get; } = splitAces;
    public bool Finished;
    public Finish? Reason;
    public bool Natural => Format.Blackjack(Cards, Split);
    public override string ToString() => Format.Hand(Cards, Split);
}

sealed class Statistics
{
    public int Rounds, Hands, Wins, Losses, Pushes, Blackjacks, Busts, Surrenders, Doubles, Splits;
    public override string ToString() => $"rounds {Rounds} hands {Hands} wins {Wins} losses {Losses} pushes {Pushes}"
        + $" blackjacks {Blackjacks} busts {Busts} surrenders {Surrenders} doubles {Doubles} splits {Splits}";
}

sealed class Player(string name, int seat, long bankroll)
{
    public string Name { get; } = name;
    public int Seat { get; } = seat;
    public long Bankroll = bankroll;
    public long Bet, Side, Insurance, Net;
    public Statistics Stats { get; } = new();
    public List<Hand> Hands { get; } = [];
    public string HandName(int index) => $"{Name}[{index + 1}]";
}

sealed class Table
{
    static readonly HashSet<string> Commands = new(StringComparer.Ordinal)
    {
        "SHOE", "RULE", "RULES", "PLAYER", "LEAVE", "REBUY", "BET", "SIDE", "DEAL", "INSURANCE",
        "HIT", "STAND", "DOUBLE", "SPLIT", "SURRENDER", "HINT", "AUTO", "STATUS", "COUNT", "STATS"
    };
    Rules rules = new();
    readonly Player?[] seats = new Player?[7];
    List<Player> participants = [];
    Phase phase = Phase.Idle;
    int round, dealerBlackjacks, dealerBusts;
    int decks, drawn, running, insuranceTurn;
    long random = 1;
    Card[] shoe = [];
    readonly List<Card> dealer = [];
    bool holeRevealed;
    readonly List<string> output = [];

    IEnumerable<Player> Players => seats.OfType<Player>();
    int Cut => shoe.Length * rules.Penetration / 100;
    Player Find(string name) => Players.FirstOrDefault(p => p.Name == name)
        ?? throw new CommandError($"unknown player {name}");
    void Emit(string line) => output.Add(line);

    void Shuffle()
    {
        shoe = Enumerable.Range(0, 52 * decks).Select(i => new Card(i % 52)).ToArray();
        for (int i = shoe.Length - 1; i >= 1; i--)
        {
            random = random * 48271 % 2147483647;
            int j = (int)(random % (i + 1));
            (shoe[i], shoe[j]) = (shoe[j], shoe[i]);
        }
        drawn = running = 0;
    }

    void CountCard(Card card) => running += card.Points is >= 2 and <= 6 ? 1 : card.Points is 1 or 10 ? -1 : 0;
    Card Draw(bool faceUp = true)
    {
        Card card = shoe[drawn++];
        if (faceUp) CountCard(card);
        return card;
    }

    void RevealDealer()
    {
        if (!holeRevealed) { CountCard(dealer[1]); holeRevealed = true; }
        Emit($"dealer: {Format.Hand(dealer)}");
    }

    (Player Player, int Index, Hand Hand)? Current()
    {
        foreach (Player player in participants)
            for (int i = 0; i < player.Hands.Count; i++)
                if (!player.Hands[i].Finished) return (player, i, player.Hands[i]);
        return null;
    }

    void FinishCheck(Player player, Hand hand)
    {
        int value = Format.Total(hand.Cards).Value;
        if (value > 21) { hand.Reason = Finish.Bust; hand.Finished = true; }
        else if (rules.Charlie != 0 && hand.Cards.Count == rules.Charlie)
        {
            hand.Reason = Finish.Charlie;
            hand.Finished = true;
        }
        else if (value == 21) hand.Finished = true;
        else if (hand.SplitAces && hand.Cards.Count == 2)
            hand.Finished = !(hand.Cards.All(c => c.Rank == 0) && rules.ResplitAces && player.Hands.Count < rules.Hands);
    }

    void Settle(bool dealerNatural = false)
    {
        int dealerTotal = Format.Total(dealer).Value;
        foreach (Player player in participants)
        {
            for (int i = 0; i < player.Hands.Count; i++)
            {
                Hand hand = player.Hands[i];
                int value = Format.Total(hand.Cards).Value;
                Outcome result = dealerNatural ? (hand.Natural ? Outcome.Push : Outcome.Lose)
                    : hand.Natural ? Outcome.Blackjack : hand.Reason switch
                    {
                        Finish.Bust => Outcome.Bust, Finish.Surrender => Outcome.Surrender, Finish.Charlie => Outcome.Charlie,
                        _ => dealerTotal > 21 || value > dealerTotal ? Outcome.Win : value == dealerTotal ? Outcome.Push : Outcome.Lose
                    };
                long profit = result switch
                {
                    Outcome.Blackjack => rules.SixToFive ? hand.Bet * 6 / 5 : hand.Bet * 3 / 2,
                    Outcome.Win or Outcome.Charlie => hand.Bet,
                    Outcome.Push => 0,
                    Outcome.Surrender => hand.Bet / 2 - hand.Bet,
                    _ => -hand.Bet
                };
                player.Bankroll += hand.Bet + profit;
                player.Net += profit;
                player.Stats.Hands++;
                if (result is Outcome.Blackjack or Outcome.Win or Outcome.Charlie) player.Stats.Wins++;
                else if (result == Outcome.Push) player.Stats.Pushes++;
                else player.Stats.Losses++;
                if (result == Outcome.Blackjack) player.Stats.Blackjacks++;
                if (result == Outcome.Bust) player.Stats.Busts++;
                if (result == Outcome.Surrender) player.Stats.Surrenders++;
                Emit($"{player.HandName(i)} {result.ToString().ToLowerInvariant()} {Format.Signed(profit)}");
            }
            Emit($"{player.Name} bankroll {player.Bankroll}");
        }
        foreach (Player player in Players) player.Bet = player.Side = 0;
        phase = Phase.Idle;
    }

    void DealerTurn()
    {
        RevealDealer();
        bool mustPlay = participants.Any(p => p.Hands.Any(h => h.Reason is null && !h.Natural));
        bool drew = false;
        if (mustPlay)
        {
            while (true)
            {
                var (value, soft) = Format.Total(dealer);
                if (!(value <= 16 || value == 17 && soft && rules.HitSoft17)) break;
                dealer.Add(Draw());
                drew = true;
                Emit($"dealer hits: {Format.Hand(dealer)}");
            }
        }
        if (drew && Format.Total(dealer).Value > 21) dealerBusts++;
        Settle();
    }

    void Advance()
    {
        while (Current() is { } turn)
        {
            if (turn.Hand.Cards.Count != 1) return;
            turn.Hand.Cards.Add(Draw());
            Emit($"{turn.Player.HandName(turn.Index)}: {turn.Hand}");
            FinishCheck(turn.Player, turn.Hand);
            if (!turn.Hand.Finished) return;
        }
        DealerTurn();
    }

    void Peek()
    {
        bool natural = Format.Blackjack(dealer);
        Emit($"dealer peeks: {(natural ? "blackjack" : "no blackjack")}");
        foreach (Player player in participants.Where(p => p.Insurance != 0))
        {
            long profit = player.Insurance * (natural ? 2 : -1);
            player.Bankroll += player.Insurance + profit;
            player.Net += profit;
            Emit($"{player.Name} insurance {Format.Signed(profit)}");
        }
        if (natural)
        {
            dealerBlackjacks++;
            RevealDealer();
            Settle(true);
        }
        else { phase = Phase.Play; Advance(); }
    }

    void Deal()
    {
        if (drawn >= Cut) { Shuffle(); Emit("shuffle"); }
        Emit($"round {++round}");
        participants = Players.Where(p => p.Bet != 0).ToList();
        foreach (Player player in participants)
        {
            player.Bankroll -= player.Bet + player.Side;
            player.Insurance = 0;
            player.Stats.Rounds++;
            player.Hands.Clear();
            player.Hands.Add(new Hand([Draw()], player.Bet));
        }
        dealer.Clear();
        dealer.Add(Draw());
        foreach (Player player in participants)
        {
            Hand hand = player.Hands[0];
            hand.Cards.Add(Draw());
            hand.Finished = hand.Natural;
        }
        dealer.Add(Draw(false));
        holeRevealed = false;
        foreach (Player player in participants) Emit($"{player.HandName(0)}: {player.Hands[0]}");
        Emit($"dealer: {dealer[0]} ??");
        foreach (Player player in participants.Where(p => p.Side != 0))
        {
            Card first = player.Hands[0].Cards[0], second = player.Hands[0].Cards[1];
            var (result, multiplier) = first.Rank != second.Rank ? ("lose", -1)
                : first.Suit == second.Suit ? ("perfect", 25) : first.Black == second.Black ? ("colored", 12) : ("mixed", 6);
            long profit = player.Side * multiplier;
            player.Bankroll += player.Side + profit;
            player.Net += profit;
            Emit($"{player.Name} side {result} {Format.Signed(profit)}");
        }
        if (dealer[0].Points == 1)
        {
            phase = Phase.Insurance;
            insuranceTurn = 0;
            Emit("insurance offered");
        }
        else if (dealer[0].Points == 10) Peek();
        else { phase = Phase.Play; Advance(); }
    }

    string? ActionError(PlayerAction action, Player player, Hand hand)
    {
        switch (action)
        {
            case PlayerAction.Hit:
                if (hand.SplitAces) return "split aces";
                break;
            case PlayerAction.Double:
                if (hand.SplitAces) return "split aces";
                if (hand.Cards.Count != 2) return "two cards only";
                var (value, soft) = Format.Total(hand.Cards);
                if (rules.Doubling != DoubleRule.Any && (soft || value < (rules.Doubling == DoubleRule.Hard9 ? 9 : 10) || value > 11)
                    || !rules.DoubleAfterSplit && hand.Split) return "double not allowed";
                if (player.Bankroll < hand.Bet) return "insufficient funds";
                break;
            case PlayerAction.Split:
                if (hand.Cards.Count != 2) return "two cards only";
                if (hand.Cards[0].Points != hand.Cards[1].Points) return "not a pair";
                if (player.Hands.Count >= rules.Hands) return "hand limit";
                if (player.Bankroll < hand.Bet) return "insufficient funds";
                break;
            case PlayerAction.Surrender:
                if (!rules.Surrender || hand.Split) return "surrender not allowed";
                if (hand.Cards.Count != 2) return "two cards only";
                break;
        }
        return null;
    }

    void Perform(PlayerAction action)
    {
        var (player, index, hand) = Current()!.Value;
        string name = player.HandName(index);
        if (action == PlayerAction.Split)
        {
            Card first = hand.Cards[0], second = hand.Cards[1];
            bool aces = hand.SplitAces || first.Points == 1;
            player.Bankroll -= hand.Bet;
            player.Stats.Splits++;
            Emit($"{name} splits {first} {second}");
            var replacement = new Hand([first], hand.Bet, true, aces);
            player.Hands[index] = replacement;
            player.Hands.Insert(index + 1, new Hand([second], hand.Bet, true, aces));
            replacement.Cards.Add(Draw());
            Emit($"{name}: {replacement}");
            FinishCheck(player, replacement);
        }
        else if (action is PlayerAction.Stand or PlayerAction.Surrender)
        {
            hand.Finished = true;
            if (action == PlayerAction.Surrender) hand.Reason = Finish.Surrender;
            Emit($"{name} {(action == PlayerAction.Stand ? "stands" : "surrenders")}: {hand}");
        }
        else
        {
            if (action == PlayerAction.Double)
            {
                player.Bankroll -= hand.Bet;
                hand.Bet *= 2;
                player.Stats.Doubles++;
            }
            hand.Cards.Add(Draw());
            Emit($"{name} {(action == PlayerAction.Double ? "doubles" : "hits")}: {hand}");
            FinishCheck(player, hand);
            if (action == PlayerAction.Double) hand.Finished = true;
        }
        Advance();
    }

    PlayerAction Recommend()
    {
        var (player, _, hand) = Current()!.Value;
        bool Possible(PlayerAction action) => ActionError(action, player, hand) is null;
        int up = dealer[0].Points == 1 ? 11 : dealer[0].Points;
        if (hand.SplitAces) return Possible(PlayerAction.Split) ? PlayerAction.Split : PlayerAction.Stand;
        if (hand.Cards.Count == 2 && hand.Cards[0].Points == hand.Cards[1].Points && Possible(PlayerAction.Split))
        {
            int pair = hand.Cards[0].Points;
            if (pair is 1 or 8 || pair == 9 && up is not (7 or 10 or 11)
                || pair is 2 or 3 or 7 && up <= 7 || pair == 6 && up <= 6 || pair == 4 && up is 5 or 6)
                return PlayerAction.Split;
        }
        var (value, soft) = Format.Total(hand.Cards);
        string symbol = "H";
        if (soft)
        {
            if (value >= 19) symbol = "S";
            else if (value == 18) symbol = up is >= 3 and <= 6 ? "Ds" : up is 2 or 7 or 8 ? "S" : "H";
            else if (value == 17 && up is >= 3 and <= 6 || value is 15 or 16 && up is >= 4 and <= 6
                || value is 13 or 14 && up is 5 or 6) symbol = "D";
        }
        else
        {
            if (value >= 17) symbol = "S";
            else if (value >= 13) symbol = up <= 6 ? "S" : value == 16 && up >= 9 || value == 15 && up == 10 ? "R" : "H";
            else if (value == 12) symbol = up is >= 4 and <= 6 ? "S" : "H";
            else if (value == 11 && up <= 10 || value == 10 && up <= 9 || value == 9 && up is >= 3 and <= 6) symbol = "D";
        }
        return symbol switch
        {
            "S" => PlayerAction.Stand,
            "D" => Possible(PlayerAction.Double) ? PlayerAction.Double : PlayerAction.Hit,
            "Ds" => Possible(PlayerAction.Double) ? PlayerAction.Double : PlayerAction.Stand,
            "R" => Possible(PlayerAction.Surrender) ? PlayerAction.Surrender : PlayerAction.Hit,
            _ => PlayerAction.Hit
        };
    }

    void Status()
    {
        string line = $"table {phase.ToString().ToLowerInvariant()} round {round}";
        if (phase == Phase.Insurance) line += $" next {participants[insuranceTurn].Name}";
        else if (phase == Phase.Play)
        {
            var turn = Current()!.Value;
            line += $" turn {turn.Player.HandName(turn.Index)}";
        }
        Emit(line);
        if (phase != Phase.Idle) Emit($"dealer: {dealer[0]} ??");
        foreach (Player player in Players)
        {
            Emit($"seat {player.Seat} {player.Name} bankroll {player.Bankroll} bet {player.Bet} side {player.Side}");
            if (phase != Phase.Idle && participants.Contains(player))
                for (int i = 0; i < player.Hands.Count; i++)
                    Emit($"{player.HandName(i)}: {player.Hands[i]} bet {player.Hands[i].Bet}");
        }
    }

    public IReadOnlyList<string> Execute(string[] words)
    {
        output.Clear();
        string command = words[0];
        if (!Commands.Contains(command)) throw new CommandError($"unknown command {command}");
        string first = words.Length > 1 ? words[1] : "", second = words.Length > 2 ? words[2] : "";
        PlayerAction? action = command switch
        {
            "HIT" => PlayerAction.Hit, "STAND" => PlayerAction.Stand, "DOUBLE" => PlayerAction.Double,
            "SPLIT" => PlayerAction.Split, "SURRENDER" => PlayerAction.Surrender, _ => null
        };
        Player? target = null;
        long amount = 0, seed = 0;
        Rules? proposed = null;

        if (command == "SHOE")
        {
            amount = Format.Integer(first, 1, 8);
            seed = Format.Integer(second, 1, 2147483646);
        }
        else if (command == "RULE") proposed = rules.Changed(first, second);
        else if (command == "PLAYER")
        {
            if (first.Length is < 1 or > 8 || first.Any(c => c is < 'A' or > 'Z')) throw new CommandError($"bad name {first}");
            amount = Format.Integer(second, 1, 1000000);
        }
        else if (action is not null || command is "LEAVE" or "REBUY" or "BET" or "SIDE" or "INSURANCE" or "AUTO")
        {
            target = Find(first);
            if (command is "REBUY" or "BET" or "SIDE" or "INSURANCE")
                amount = Format.Integer(second, command == "REBUY" ? 1 : 0, 1000000);
        }
        if (command is "SHOE" or "RULE" or "PLAYER" or "LEAVE" or "REBUY" or "BET" or "SIDE" or "DEAL")
        {
            if (phase != Phase.Idle) throw new CommandError("round in progress");
        }
        else if (command == "INSURANCE")
        {
            if (phase != Phase.Insurance) throw new CommandError("no insurance");
        }
        else if (action is not null || command is "AUTO" or "HINT")
        {
            if (phase == Phase.Idle) throw new CommandError("no round");
            if (phase == Phase.Insurance) throw new CommandError("insurance pending");
        }
        if (action is not null || command == "AUTO")
        {
            var turn = Current()!.Value;
            if (turn.Player != target) throw new CommandError($"waiting for {turn.Player.HandName(turn.Index)}");
            if (action is { } chosen)
            {
                string? error = ActionError(chosen, turn.Player, turn.Hand);
                if (error is not null) throw new CommandError(error);
                Perform(chosen);
            }
            else while (phase == Phase.Play && Current()!.Value.Player == target) Perform(Recommend());
            return output;
        }
        switch (command)
        {
            case "SHOE":
                decks = (int)amount;
                random = seed;
                Shuffle();
                Emit($"shoe {decks} decks {shoe.Length} cards cut {Cut}");
                break;
            case "RULE":
                if (proposed!.Minimum > proposed.Maximum) throw new CommandError("min above max");
                rules = proposed;
                Emit($"rule {first} {second}");
                break;
            case "RULES": Emit(rules.ToString()); break;
            case "PLAYER":
            {
                if (Players.Any(p => p.Name == first)) throw new CommandError("player exists");
                int seat = Array.FindIndex(seats, p => p is null);
                if (seat < 0) throw new CommandError("table full");
                seats[seat] = new Player(first, seat + 1, amount);
                Emit($"{first} sits at seat {seat + 1} with {amount}");
                break;
            }
            case "LEAVE":
                Emit($"{target!.Name} leaves with {target.Bankroll} net {Format.Signed(target.Net)}");
                seats[target.Seat - 1] = null;
                break;
            case "REBUY":
                target!.Bankroll += amount;
                Emit($"{target.Name} rebuys {amount} bankroll {target.Bankroll}");
                break;
            case "BET":
                if (amount != 0)
                {
                    if (amount < rules.Minimum || amount > rules.Maximum) throw new CommandError("bet out of limits");
                    if (amount + target!.Side > target.Bankroll) throw new CommandError("insufficient funds");
                }
                target!.Bet = amount;
                if (amount == 0) target.Side = 0;
                Emit(amount == 0 ? $"{target.Name} bet cleared" : $"{target.Name} bets {amount}");
                break;
            case "SIDE":
                if (amount != 0)
                {
                    if (target!.Bet == 0) throw new CommandError("no bet");
                    if (amount > rules.SideMaximum) throw new CommandError("side out of limits");
                    if (target.Bet + amount > target.Bankroll) throw new CommandError("insufficient funds");
                }
                target!.Side = amount;
                Emit(amount == 0 ? $"{target.Name} side cleared" : $"{target.Name} side {amount}");
                break;
            case "DEAL":
                if (decks == 0) throw new CommandError("no shoe");
                if (!Players.Any(p => p.Bet != 0)) throw new CommandError("no bets");
                Deal();
                break;
            case "INSURANCE":
                if (participants[insuranceTurn] != target) throw new CommandError($"waiting for {participants[insuranceTurn].Name}");
                if (amount > target!.Bet / 2) throw new CommandError("insurance out of limits");
                if (amount > target.Bankroll) throw new CommandError("insufficient funds");
                target.Bankroll -= amount;
                target.Insurance = amount;
                Emit(amount == 0 ? $"{target.Name} declines insurance" : $"{target.Name} insures {amount}");
                if (++insuranceTurn == participants.Count) Peek();
                break;
            case "HINT":
            {
                var turn = Current()!.Value;
                Emit($"hint {turn.Player.HandName(turn.Index)}: {Format.Action(Recommend())}");
                break;
            }
            case "STATUS": Status(); break;
            case "COUNT":
            {
                if (decks == 0) throw new CommandError("no shoe");
                int remaining = shoe.Length - drawn;
                int hundredths = Math.Abs(running) * 5200 / remaining;
                string count = $"{(running < 0 ? "-" : "")}{hundredths / 100}.{hundredths % 100:D2}";
                Emit($"count running {running} true {count} remaining {remaining}");
                break;
            }
            case "STATS":
                if (!Players.Any()) throw new CommandError("no players");
                foreach (Player player in Players) Emit($"stats {player.Name} {player.Stats} net {Format.Signed(player.Net)}");
                Emit($"stats dealer rounds {round} blackjacks {dealerBlackjacks} busts {dealerBusts}");
                break;
        }
        return output;
    }
}

static class Program
{
    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Console.Out.NewLine = "\n";
        int count = int.Parse(Console.ReadLine()!);
        var table = new Table();
        for (int i = 0; i < count; i++)
        {
            try { foreach (string line in table.Execute(Console.ReadLine()!.Split(' '))) Console.WriteLine(line); }
            catch (CommandError error) { Console.WriteLine($"error: {error.Message}"); }
        }
    }
}
