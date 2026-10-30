using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Program {
    public static readonly List<string> WAIT_ORDER =
                                            new List<string> { "ryanmen", "kanchan", "penchan",
                                                               "shanpon", "tanki",   "single",
                                                               "thirteen" },
                                        WIN_ORDER =
                                            new List<string> { "dealer_ron", "dealer_tsumo",
                                                               "nondealer_ron", "nondealer_tsumo" };
    public record Rules(bool openTanyao, bool redFives, bool doubleYakuman, bool kazoeYakuman,
                        bool kiriage, int honba) {}
    public record Record(string label, Dictionary<string, string> fields) {}
    public record Facts(List<Scoring.Triplet> triplets, List<int> sequences,
                        List<List<int>> concealedSequences) {}
    public record Winning(List<string> lines, int points) {}
    public record Acceptance(int kind, int remaining) {}
    public record WaitScore(int kind, int points) {}
    public static List<Record> ReadRecords(string filename) {
        List<Record> records = new();
        foreach (string line in File
                     .ReadAllLines(Path.Combine("input", filename), System.Text.Encoding.ASCII)
                     .ToList()) {
            string[] parts = line.Split(" ");
            Dictionary<string, string> fields = new();
            for (int i = 1; i < parts.Length; i++) {
                int equals = parts[i].IndexOf('=');
                fields[parts[i].Substring(0, equals - (0))] = parts[i].Substring(equals + 1);
            }
            records.Add(new Record(parts[0], fields));
        }
        return records;
    }
    public static Dictionary<string, Rules> ReadRules() {
        Dictionary<string, Rules> rules = new();
        foreach (Record record in ReadRecords("rules.txt")) {
            Dictionary<string, string> f = record.fields;
            rules[record.label] =
                new Rules(f["open_tanyao"].Equals("yes"), f["red_fives"].Equals("yes"),
                          f["double_yakuman"].Equals("yes"), f["kazoe_yakuman"].Equals("yes"),
                          f["kiriage"].Equals("yes"), int.Parse(f["honba"]));
        }
        return rules;
    }
    public sealed class Meld {
        public string kind;
        public List<Tiles.Tile> tiles;
        public List<int> block = new();
        public Meld(string text) {
            kind = text.Substring(0, 1 - (0));
            tiles = Tiles.Parse(text.Substring(1));
            if (tiles != null)
                foreach (Tiles.Tile tile in tiles)
                    block.Add(tile.kind);
            block.Sort();
        }
        public bool Valid() {
            if (kind.Equals("C"))
                return block.Count == 3 && block[0] < 27 && block[0] % 9 <= 6 &&
                       block[1] == block[0] + 1 && block[2] == block[0] + 2;
            if (!new List<string> { "P", "K", "A" }.Contains(kind))
                return false;
            return block.Count == (kind.Equals("P") ? 3 : 4) && new HashSet<int>(block).Count == 1;
        }
    }
    public sealed class Situation {
        public string label, ruleName, by, seat, discarder, round;
        public Rules rules;
        public List<Tiles.Tile> hand, win, dora, ura, discards, allTiles;
        public List<Meld> melds = new();
        public HashSet<string> flags = new();
        public int seatTile, roundTile, kanCount, honba, sticks, winningTile;
        public int[] handCounts, concealedCounts, meldCounts, allCounts;
        public bool closed, riichi;
        public Situation(string label, Dictionary<string, string> fields,
                         Dictionary<string, Rules> rules) {
            this.label = label;
            ruleName = fields["rules"];
            this.rules = rules[ruleName];
            hand = Tiles.Parse(fields["hand"]);
            win = Tiles.Parse(fields["win"]);
            if (!fields["melds"].Equals("-"))
                foreach (string text in fields["melds"].Split(","))
                    melds.Add(new Meld(text));
            dora = Tiles.Parse(fields["dora"]);
            ura = Tiles.Parse(fields["ura"], true);
            discards = Tiles.Parse(fields["discards"], true);
            by = fields["by"];
            seat = fields["seat"];
            discarder = fields["from"];
            round = fields["round"];
            seatTile = Tiles.WindTile(seat);
            roundTile = Tiles.WindTile(round);
            if (!fields["flags"].Equals("-"))
                flags.UnionWith(fields["flags"].Split(",").ToList());
            closed = true;
            foreach (Meld meld in melds) {
                if (!meld.kind.Equals("A"))
                    closed = false;
                if (meld.kind.Equals("K") || meld.kind.Equals("A"))
                    kanCount++;
            }
            riichi = flags.Contains("riichi") || flags.Contains("double_riichi");
            honba = int.Parse(fields["honba"]);
            sticks = int.Parse(fields["sticks"]);
        }
        public void Prepare() {
            winningTile = win[0].kind;
            handCounts = Tiles.Counts(hand);
            List<Tiles.Tile> concealed = new(hand);
            concealed.AddRange(win);
            concealedCounts = Tiles.Counts(concealed);
            List<Tiles.Tile> meldTiles = new();
            foreach (Meld meld in melds)
                meldTiles.AddRange(meld.tiles);
            meldCounts = Tiles.Counts(meldTiles);
            allTiles = new(concealed);
            allTiles.AddRange(meldTiles);
            allCounts = Tiles.Counts(allTiles);
        }
    }
    public sealed class WaitingHand {
        public string label;
        public Dictionary<string, string> fields;
        public Rules rules;
        public List<Tiles.Tile> hand, dora, discards, visible;
        public int[] counts, knownCounts;
        public WaitingHand(Record record, Dictionary<string, Rules> rules) {
            label = record.label;
            fields = record.fields;
            this.rules = rules[fields["rules"]];
            hand = Tiles.Parse(fields["hand"]);
            dora = Tiles.Parse(fields["dora"]);
            discards = Tiles.Parse(fields["discards"], true);
            visible = Tiles.Parse(fields["visible"], true);
        }
    }
    public sealed class Candidate {
        public string formType, form, wait, category = "none";
        public int pair;
        public List<List<int>> sets;
        public List<int> winningBlock;
        public List<Yaku.Item> yaku = new(), yakuman = new(), fuItems = new();
        public int multiplier, han, fu, fuTotal, basePoints, dora, aka, ura;
        public Candidate(string formType, int pair, List<List<int>> sets, List<int> winningBlock,
                         string form, string wait) {
            this.formType = formType;
            this.pair = pair;
            this.sets = sets;
            this.winningBlock = winningBlock;
            this.form = form;
            this.wait = wait;
        }
    }
    public static string CopyError(List<Tiles.Tile> allTiles, Rules rules) {
        int[] reds = new int[3];
        foreach (Tiles.Tile tile in allTiles)
            if (tile.red)
                reds[tile.kind / 9]++;
        if (!rules.redFives && (reds[0] + reds[1] + reds[2] > 0))
            return "red five not allowed";
        int[] counts = Tiles.Counts(allTiles);
        for (int kind = 0; kind < 34; kind++)
            if (counts[kind] >= 5)
                return "too many copies of " + Tiles.Name(kind);
        for (int suit = 0; suit < 3; suit++)
            if (reds[suit] >= 2)
                return "too many copies of 0" + Tiles.SUITS[suit];
        return null;
    }
    public static string ValidateSituation(Situation s) {
        if (s.hand == null || s.win == null || s.dora == null || s.ura == null ||
            s.discards == null)
            return "bad tile notation";
        foreach (Meld meld in s.melds)
            if (meld.tiles == null)
                return "bad tile notation";
        if (s.win.Count != 1)
            return "bad tile notation";
        if (s.melds.Count >= 5)
            return "bad meld";
        foreach (Meld meld in s.melds)
            if (!meld.Valid())
                return "bad meld";
        if (s.hand.Count != 13 - 3 * s.melds.Count)
            return "wrong tile count";
        s.Prepare();
        List<Tiles.Tile> observed = new(s.allTiles);
        observed.AddRange(s.dora);
        observed.AddRange(s.ura);
        observed.AddRange(s.discards);
        string error = CopyError(observed, s.rules);
        if (error != null)
            return error;
        if (s.by.Equals("tsumo") && !s.discarder.Equals("-") ||
            s.by.Equals("ron") && (s.discarder.Equals("-") || s.discarder.Equals(s.seat)))
            return "invalid discarder";
        HashSet<string> f = s.flags;
        foreach (string flag in Yaku.FLAGS)
            if (f.Contains(flag)) {
                bool valid = (flag) switch {
                    "riichi" => s.closed,
                    "double_riichi" => s.closed && !f.Contains("riichi"),
                    "ippatsu" => s.riichi && !f.Contains("rinshan"),
                    "haitei" => s.by.Equals("tsumo") && !f.Contains("rinshan"),
                    "houtei" => s.by.Equals("ron") && !f.Contains("chankan"),
                    "rinshan" => s.by.Equals("tsumo") && s.kanCount >= 1,
                    "chankan" => s.by.Equals("ron"),
                    "tenhou" => s.seat.Equals("E") && s.by.Equals("tsumo") && s.melds.Count == 0 &&
                                f.Count == 1,
                    _ => !s.seat.Equals("E") && s.by.Equals("tsumo") && s.melds.Count == 0 &&
                         f.Count == 1,
                };
                if (!valid)
                    return "invalid flag " + flag;
            }
        if (s.dora.Count != 1 + s.kanCount)
            return "invalid dora indicators";
        if (s.riichi && s.ura.Count != s.dora.Count || !s.riichi && s.ura.Count != 0)
            return "invalid ura indicators";
        if (s.riichi && s.sticks == 0)
            return "invalid sticks";
        if (!Decomposition.Winning(s.concealedCounts, s.melds.Count))
            return "not a winning hand";
        return null;
    }
    public static string ValidateWaiting(WaitingHand hand) {
        if (hand.hand == null || hand.dora == null || hand.discards == null || hand.visible == null)
            return "bad tile notation";
        if (hand.hand.Count != 13)
            return "wrong tile count";
        List<Tiles.Tile> observed = new(hand.hand);
        observed.AddRange(hand.dora);
        observed.AddRange(hand.discards);
        observed.AddRange(hand.visible);
        string error = CopyError(observed, hand.rules);
        if (error == null) {
            hand.counts = Tiles.Counts(hand.hand);
            hand.knownCounts = Tiles.Counts(observed);
        }
        return error;
    }
    public static List<Candidate> Candidates(Situation s) {
        List<Candidate> result = new();
        int winning = s.winningTile;
        int[] counts = s.concealedCounts;
        foreach (Decomposition.Form split in Decomposition.Standard(counts, s.melds.Count)) {
            List<List<int>> blocks = new();
            blocks.Add(new List<int> { split.pair, split.pair });
            blocks.AddRange(split.sets);
            List<List<int>> choices = new();
            foreach (List<int> block in blocks)
                if (block.Contains(winning))
                    if (!choices.Any(other => other.SequenceEqual(block)))
                        choices.Add(block);
            foreach (List<int> chosen in choices) {
                List<string> parts = new(new List<string> { "standard" });
                bool marked = false;
                foreach (List<int> block in blocks) {
                    string notation = Tiles.Block(block);
                    if (block.SequenceEqual(chosen) && !marked) {
                        notation += "*";
                        marked = true;
                    }
                    parts.Add(notation);
                }
                foreach (Meld meld in s.melds)
                    parts.Add(meld.kind + Tiles.Block(meld.block));
                string wait = Decomposition.WaitShape("standard", chosen, winning, s.handCounts);
                result.Add(new Candidate("standard", split.pair, split.sets, chosen,
                                         string.Join(" ", parts), wait));
            }
        }
        if (s.melds.Count == 0 && Decomposition.SevenPairs(counts)) {
            List<string> parts = new(new List<string> { "chiitoitsu" });
            for (int kind = 0; kind < 34; kind++)
                if (counts[kind] > 0)
                    parts.Add(Tiles.Block(new List<int> { kind, kind }) +
                              (kind == winning ? "*" : ""));
            result.Add(
                new Candidate("chiitoitsu", -1, new(), null, string.Join(" ", parts), "tanki"));
        }
        if (s.melds.Count == 0 && Decomposition.ThirteenOrphans(counts)) {
            List<string> parts = new(new List<string> { "kokushi" });
            foreach (int kind in Tiles.YAOCHUU)
                parts.Add(Tiles.Block(Enumerable.Repeat(kind, counts[kind]).ToList()) +
                          (kind == winning ? "*" : ""));
            string wait = Decomposition.WaitShape("kokushi", null, winning, s.handCounts);
            result.Add(new Candidate("kokushi", -1, new(), null, string.Join(" ", parts), wait));
        }
        result.Sort((a, b) => string.CompareOrdinal(a.form, b.form));
        return result;
    }
    public static Facts BlockFacts(Situation s, Candidate candidate) {
        List<Scoring.Triplet> triplets = new();
        List<int> sequences = new();
        List<List<int>> concealedSequences = new();
        foreach (List<int> block in candidate.sets)
            if (block[0].Equals(block[^1]))
                triplets.Add(new Scoring.Triplet(block,
                                                 s.by.Equals("tsumo") ||
                                                     !(candidate.winningBlock != null &&
                                                       block.SequenceEqual(candidate.winningBlock)),
                                                 false));
            else {
                sequences.Add(block[0]);
                concealedSequences.Add(block);
            }
        foreach (Meld meld in s.melds)
            if (meld.kind.Equals("C"))
                sequences.Add(meld.block[0]);
            else
                triplets.Add(new Scoring.Triplet(meld.block, meld.kind.Equals("A"),
                                                 meld.kind.Equals("K") || meld.kind.Equals("A")));
        return new Facts(triplets, sequences, concealedSequences);
    }
    public static HashSet<string> YakumanNames(Situation s, Candidate candidate, HashSet<int> kinds,
                                               List<Scoring.Triplet> triplets) {
        HashSet<string> names = new();
        foreach (string name in new List<string> { "tenhou", "chiihou" })
            if (s.flags.Contains(name))
                names.Add(name);
        bool honors = true, terminals = true, green = true;
        HashSet<int> suits = new();
        foreach (int kind in kinds) {
            honors &= Tiles.Honor(kind);
            terminals &= Tiles.Terminal(kind);
            green &= Tiles.GREEN.Contains(kind);
            suits.Add(kind / 9);
        }
        if (honors)
            names.Add("tsuuiisou");
        if (terminals)
            names.Add("chinroutou");
        if (green)
            names.Add("ryuuiisou");
        if (s.melds.Count == 0 && suits.Count == 1 && !suits.Contains(3)) {
            int start = suits.First() * 9;
            bool chuuren = s.allCounts[start] >= 3 && s.allCounts[start + 8] >= 3;
            for (int i = 1; i <= 7; i++)
                chuuren &= s.allCounts[start + i] >= 1;
            if (chuuren) {
                int[] initial = s.handCounts[(start)..(start + 9)];
                names.Add(initial.SequenceEqual(new int[] { 3, 1, 1, 1, 1, 1, 1, 1, 3 })
                              ? "junsei_chuuren"
                              : "chuuren");
            }
        }
        if (candidate.formType.Equals("kokushi"))
            names.Add(candidate.wait.Equals("thirteen") ? "kokushi_13" : "kokushi");
        if (candidate.formType.Equals("standard")) {
            int concealed = 0, dragons = 0, winds = 0, kans = 0;
            foreach (Scoring.Triplet triplet in triplets) {
                if (triplet.concealed)
                    concealed++;
                if (triplet.kan)
                    kans++;
                int kind = triplet.kinds[0];
                if (kind >= 31)
                    dragons++;
                else if (kind >= 27)
                    winds++;
            }
            if (concealed == 4)
                names.Add(candidate.wait.Equals("tanki") ? "suuankou_tanki" : "suuankou");
            if (dragons == 3)
                names.Add("daisangen");
            if (winds == 4)
                names.Add("daisuushii");
            if (winds == 3 && candidate.pair >= 27 && candidate.pair <= 30)
                names.Add("shousuushii");
            if (kans == 4)
                names.Add("suukantsu");
        }
        return names;
    }
    public static HashSet<string> OrdinaryNames(Situation s, Candidate c, HashSet<int> kinds,
                                                Facts facts) {
        HashSet<string> names = new();
        foreach (string flag in Yaku.FLAGS.GetRange(0, 7 - 0))
            if (s.flags.Contains(flag))
                names.Add(flag);
        if (s.closed && s.by.Equals("tsumo"))
            names.Add("menzen_tsumo");
        bool simple = true, yaochuu = true, honors = false;
        HashSet<int> numberSuits = new();
        foreach (int kind in kinds) {
            simple &= !Tiles.Yaochuu(kind);
            yaochuu &= Tiles.Yaochuu(kind);
            honors |= Tiles.Honor(kind);
            if (kind < 27)
                numberSuits.Add(kind / 9);
        }
        if (simple && (s.closed || s.rules.openTanyao))
            names.Add("tanyao");
        if (yaochuu)
            names.Add("honroutou");
        if (numberSuits.Count == 1)
            names.Add(honors ? "honitsu" : "chinitsu");
        if (c.formType.Equals("chiitoitsu"))
            names.Add("chiitoitsu");
        if (!c.formType.Equals("standard"))
            return names;
        bool yakuhaiPair = c.pair >= 31 || c.pair == s.seatTile || c.pair == s.roundTile;
        if (s.closed && s.melds.Count == 0 && facts.concealedSequences.Count == 4 && !yakuhaiPair &&
            c.wait.Equals("ryanmen"))
            names.Add("pinfu");
        Dictionary<string, int> repeated = new();
        foreach (List<int> block in facts.concealedSequences)
            repeated.AddCount(Tiles.Block(block), 1);
        int pairs = 0;
        bool duplicate = false;
        foreach (int count in repeated.Values) {
            pairs += count / 2;
            duplicate |= count >= 2;
        }
        if (s.closed && facts.concealedSequences.Count == 4 && pairs == 2)
            names.Add("ryanpeikou");
        else if (s.closed && duplicate)
            names.Add("iipeikou");
        HashSet<int> tripletKinds = new();
        int concealed = 0, kans = 0, dragons = 0;
        foreach (Scoring.Triplet triplet in facts.triplets) {
            int kind = triplet.kinds[0];
            tripletKinds.Add(kind);
            if (triplet.concealed)
                concealed++;
            if (triplet.kan)
                kans++;
            if (kind >= 31)
                dragons++;
        }
        int[] valued = { 31, 32, 33, s.seatTile, s.roundTile };
        string[] valuedNames = { "haku", "hatsu", "chun", "jikaze", "bakaze" };
        for (int i = 0; i < valued.Length; i++)
            if (tripletKinds.Contains(valued[i]))
                names.Add(valuedNames[i]);
        if (facts.triplets.Count == 4)
            names.Add("toitoi");
        if (concealed == 3)
            names.Add("sanankou");
        HashSet<int> sequenceKinds = new HashSet<int>(facts.sequences);
        for (int start = 0; start < 7; start++)
            if (sequenceKinds.Contains(start) && sequenceKinds.Contains(start + 9) &&
                sequenceKinds.Contains(start + 18))
                names.Add("sanshoku_doujun");
        for (int number = 0; number < 9; number++)
            if (tripletKinds.Contains(number) && tripletKinds.Contains(number + 9) &&
                tripletKinds.Contains(number + 18))
                names.Add("sanshoku_doukou");
        for (int suit = 0; suit < 3; suit++)
            if (sequenceKinds.Contains(suit * 9) && sequenceKinds.Contains(suit * 9 + 3) &&
                sequenceKinds.Contains(suit * 9 + 6))
                names.Add("ittsu");
        List<List<int>> blocks = new();
        blocks.Add(new List<int> { c.pair, c.pair });
        blocks.AddRange(c.sets);
        foreach (Meld meld in s.melds)
            blocks.Add(meld.block);
        bool outside = facts.sequences.Count != 0;
        foreach (List<int> block in blocks) {
            bool contains = false;
            foreach (int kind in block)
                contains |= Tiles.Yaochuu(kind);
            outside &= contains;
        }
        if (outside)
            names.Add(honors ? "chanta" : "junchan");
        if (kans == 3)
            names.Add("sankantsu");
        if (dragons == 2 && c.pair >= 31)
            names.Add("shousangen");
        return names;
    }
    public static Candidate EvaluateCandidate(Situation s, Candidate candidate) {
        HashSet<int> kinds = new();
        for (int kind = 0; kind < 34; kind++)
            if (s.allCounts[kind] > 0)
                kinds.Add(kind);
        Facts facts = BlockFacts(s, candidate);
        HashSet<string> names = YakumanNames(s, candidate, kinds, facts.triplets);
        candidate.yakuman = Yaku.Yakuman(names, s.rules.doubleYakuman);
        if (candidate.yakuman.Count != 0) {
            foreach (Yaku.Item item in candidate.yakuman)
                candidate.multiplier += item.value;
            candidate.basePoints = 8000 * candidate.multiplier;
            candidate.category = "yakuman";
            return candidate;
        }
        names = OrdinaryNames(s, candidate, kinds, facts);
        candidate.yaku = Yaku.Ordinary(names, s.closed);
        foreach (Tiles.Tile tile in s.dora)
            candidate.dora += s.allCounts[Tiles.NextDora(tile.kind)];
        foreach (Tiles.Tile tile in s.ura)
            candidate.ura += s.allCounts[Tiles.NextDora(tile.kind)];
        foreach (Tiles.Tile tile in s.allTiles)
            if (tile.red)
                candidate.aka++;
        Scoring.Fu fu =
            Scoring.FuBreakdown(candidate.formType, candidate.pair, facts.triplets, candidate.wait,
                                s.closed, s.by, s.seatTile, s.roundTile, names.Contains("pinfu"));
        candidate.fuItems = fu.items;
        candidate.fuTotal = fu.total;
        candidate.fu = fu.rounded;
        if (candidate.yaku.Count != 0) {
            candidate.han = candidate.dora + candidate.aka + candidate.ura;
            foreach (Yaku.Item item in candidate.yaku)
                candidate.han += item.value;
            Scoring.Limit limit = Scoring.DetermineLimit(candidate.han, candidate.fu, s.rules);
            candidate.category = limit.category;
            candidate.basePoints = limit.basePoints;
        }
        return candidate;
    }
    public static List<Candidate> EvaluateCandidates(Situation s) {
        List<Candidate> result = Candidates(s);
        foreach (Candidate candidate in result)
            EvaluateCandidate(s, candidate);
        return result;
    }
    public static int CompareCandidates(Candidate a, Candidate b) {
        int compared = b.basePoints.CompareTo(a.basePoints);
        if (compared != 0)
            return compared;
        compared = (b.yakuman.Count != 0).CompareTo(a.yakuman.Count != 0);
        if (compared != 0)
            return compared;
        if (a.yakuman.Count == 0 && b.yakuman.Count == 0) {
            compared = b.han.CompareTo(a.han);
            if (compared != 0)
                return compared;
            compared = b.fu.CompareTo(a.fu);
            if (compared != 0)
                return compared;
        }
        return string.CompareOrdinal(a.form, b.form);
    }
    public static Candidate BestCandidate(List<Candidate> candidates) {
        Candidate best = null;
        foreach (Candidate candidate in candidates)
            if (candidate.basePoints >= 1 &&
                (best == null || CompareCandidates(candidate, best) < 0))
                best = candidate;
        return best;
    }
    public static string Names(List<Yaku.Item> items, string separator) {
        List<string> names = new();
        foreach (Yaku.Item item in items)
            names.Add(item.name);
        return string.Join(separator, names);
    }
    public static string CandidateLine(Candidate c) {
        string evaluation = c.yakuman.Count != 0
                                ? "yakuman " + c.multiplier + " base " + c.basePoints + " yaku " +
                                      Names(c.yakuman, ",")
                            : c.yaku.Count == 0 ? "no_yaku"
                                                : "han " + c.han + " fu " + c.fu + " base " +
                                                      c.basePoints + " yaku " + Names(c.yaku, ",");
        return "CANDIDATE " + c.form + " = " + c.wait + " " + evaluation;
    }
    public static Winning WinningLines(Situation s, Candidate c) {
        List<string> lines = new(new List<string> { "FORM " + c.form, "WAIT " + c.wait });
        if (c.yakuman.Count != 0) {
            foreach (Yaku.Item item in c.yakuman)
                lines.Add("YAKUMAN " + item.name + " " + item.value);
            lines.Add("SCORE yakuman " + c.multiplier + " base " + c.basePoints);
        } else {
            foreach (Yaku.Item item in c.yaku)
                lines.Add("YAKU " + item.name + " " + item.value);
            lines.Add("DORA dora " + c.dora + " aka " + c.aka + " ura " + c.ura);
            foreach (Yaku.Item item in c.fuItems)
                lines.Add("FU " + item.name + " " + item.value);
            lines.Add("FU total " + c.fuTotal + " " + c.fu);
            lines.Add("SCORE han " + c.han + " fu " + c.fu + " limit " + c.category + " base " +
                      c.basePoints);
        }
        Scoring.Payments p = Scoring.ComputePayments(c.basePoints, s.seat.Equals("E"), s.by);
        if (s.by.Equals("ron"))
            lines.Add("PAY ron " + p.ron);
        else if (s.seat.Equals("E"))
            lines.Add("PAY tsumo all " + p.nondealer);
        else
            lines.Add("PAY tsumo dealer " + p.dealer + " nondealer " + p.nondealer);
        int honba = s.honba * s.rules.honba, sticks = s.sticks * 1000,
            gain = p.points + honba + sticks;
        lines.Add("BONUS honba " + honba + " sticks " + sticks);
        lines.Add("TOTAL points " + p.points + " gain " + gain);
        int[] delta = new int[4];
        if (s.by.Equals("ron"))
            delta[Tiles.WINDS.IndexOf(s.discarder)] = -p.ron - honba;
        else
            for (int i = 0; i < 4; i++)
                if (i != Tiles.WINDS.IndexOf(s.seat))
                    delta[i] = -(i == 0 ? p.dealer : p.nondealer) - honba / 3;
        delta[Tiles.WINDS.IndexOf(s.seat)] = gain;
        List<string> changes = new();
        for (int i = 0; i < 4; i++)
            changes.Add(Tiles.WINDS[i] + " " + (delta[i] > 0 ? "+" : "") + delta[i]);
        lines.Add("DELTA " + string.Join(" ", changes));
        return new Winning(lines, p.points);
    }
    public static Situation Hypothetical(WaitingHand hand, int winning, string method,
                                         Dictionary<string, Rules> rules) {
        Dictionary<string, string> fields = new HashMap<>(hand.fields);
        fields["melds"] = "-";
        fields["win"] = Tiles.Name(winning);
        fields["by"] = method;
        fields["from"] = method.Equals("tsumo") ? "-" : fields["seat"].Equals("E") ? "S" : "E";
        fields["flags"] = fields["riichi"].Equals("yes") ? "riichi" : "-";
        fields["ura"] = "-";
        fields["honba"] = "0";
        fields["sticks"] = "0";
        Situation s = new Situation(hand.label, fields, rules);
        s.Prepare();
        return s;
    }
    public sealed class Counts {
        public Dictionary<string, int> values = new();
        public int Get(string key) { return values.GetValueOrDefault(key, 0); }
        public void Add(string key, int amount) { values[key] = Get(key) + amount; }
        public string Named(List<string> names) {
            List<string> pieces = new();
            foreach (string name in names)
                pieces.Add(name + " " + Get(name));
            return string.Join(" ", pieces);
        }
    }
    public sealed class Reports {
        public Dictionary<string, Rules> rules;
        public List<Record> situations, hands;
        public Counts stats = new Counts(), winCounts = new Counts(), waitCounts = new Counts(),
                      limitCounts = new Counts(), yakuCounts = new Counts();
        public SortedDictionary<int, int> hanCounts = new(), fuCounts = new();
        public Dictionary<string, Counts> ruleCounts = new();
        public int maximum;
        public string maximumHand = "-";
        public List<string> summary = new(new List<string> { "hand,han,fu,points,yaku" });
        public Reports(Dictionary<string, Rules> rules) {
            this.rules = rules;
            situations = ReadRecords("hands.txt");
            hands = ReadRecords("waits.txt");
            foreach (string name in rules.Keys)
                ruleCounts[name] = new Counts();
        }
        public void RecordWin(Situation s, Candidate c, int points) {
            stats.Add("wins", 1);
            stats.Add("points", points);
            ruleCounts[s.ruleName].Add("wins", 1);
            ruleCounts[s.ruleName].Add("points", points);
            winCounts.Add((s.seat.Equals("E") ? "dealer_" : "nondealer_") + s.by, 1);
            waitCounts.Add(c.wait, 1);
            limitCounts.Add(c.category, 1);
            List<Yaku.Item> names = c.yakuman.Count == 0 ? c.yaku : c.yakuman;
            foreach (Yaku.Item item in names)
                yakuCounts.Add(item.name, 1);
            string han, fu;
            if (c.yakuman.Count != 0) {
                han = "Y" + c.multiplier;
                fu = "-";
            } else {
                han = Convert.ToString(c.han);
                fu = Convert.ToString(c.fu);
                hanCounts.AddCount(c.han, 1);
                fuCounts.AddCount(c.fu, 1);
            }
            summary.Add(s.label + "," + han + "," + fu + "," + points + "," + Names(names, ";"));
            if (points > maximum) {
                maximum = points;
                maximumHand = s.label;
            }
        }
        public List<string> Scores() {
            List<string> lines = new();
            foreach (Record record in situations) {
                Situation s = new Situation(record.label, record.fields, rules);
                ruleCounts[s.ruleName].Add("hands", 1);
                lines.Add("HAND " + s.label);
                string error = ValidateSituation(s);
                if (error != null) {
                    stats.Add("errors", 1);
                    lines.Add("ERROR " + error);
                    summary.Add(s.label + ",-,-,0,ERROR");
                    continue;
                }
                List<int> waiting =
                    Decomposition.WaitingTiles(s.handCounts, s.meldCounts, s.melds.Count);
                List<string> waitingNames = new();
                foreach (int kind in waiting)
                    waitingNames.Add(Tiles.Name(kind));
                lines.Add("WAITS " + string.Join(" ", waitingNames));
                List<Candidate> evaluated = EvaluateCandidates(s);
                foreach (Candidate candidate in evaluated)
                    lines.Add(CandidateLine(candidate));
                bool furiten = false;
                if (s.by.Equals("ron"))
                    foreach (Tiles.Tile tile in s.discards)
                        if (waiting.Contains(tile.kind))
                            furiten = true;
                if (furiten) {
                    stats.Add("furiten", 1);
                    lines.Add("RESULT furiten");
                    summary.Add(s.label + ",-,-,0,FURITEN");
                    continue;
                }
                Candidate best = BestCandidate(evaluated);
                if (best == null) {
                    stats.Add("no_yaku", 1);
                    lines.Add("RESULT no_yaku");
                    summary.Add(s.label + ",-,-,0,NO_YAKU");
                    continue;
                }
                Winning report = WinningLines(s, best);
                lines.AddRange(report.lines);
                RecordWin(s, best, report.points);
            }
            lines.AddRange(ScoreStatistics());
            return lines;
        }
        public List<string> ScoreStatistics() {
            List<string> lines = new(new List<string> {
                "STATS hands " + situations.Count + " wins " + stats.Get("wins") + " furiten " +
                    stats.Get("furiten") + " no_yaku " + stats.Get("no_yaku") + " errors " +
                    stats.Get("errors"),
                "WINS " + winCounts.Named(WIN_ORDER), "WAIT_COUNT " + waitCounts.Named(WAIT_ORDER)
            });
            foreach (KeyValuePair<int, int> entry in hanCounts)
                lines.Add("HAN_COUNT " + entry.Key + " " + entry.Value);
            foreach (KeyValuePair<int, int> entry in fuCounts)
                lines.Add("FU_COUNT " + entry.Key + " " + entry.Value);
            foreach (string category in Yaku.CATEGORIES)
                lines.Add("LIMIT " + category + " " + limitCounts.Get(category));
            List<string> names = new();
            foreach (Yaku.Definition definition in Yaku.YAKU)
                names.Add(definition.name);
            foreach (Yaku.Item item in Yaku.YAKUMAN)
                names.Add(item.name);
            foreach (string name in names)
                if (yakuCounts.Get(name) > 0)
                    lines.Add("YAKU_COUNT " + name + " " + yakuCounts.Get(name));
            lines.Add("POINTS total " + stats.Get("points") + " max " + maximum + " hand " +
                      maximumHand);
            foreach (KeyValuePair<string, Counts> entry in ruleCounts)
                lines.Add("RULE " + entry.Key + " " +
                          entry.Value.Named(new List<string> { "hands", "wins", "points" }));
            return lines;
        }
        public List<Acceptance> FindAcceptance(WaitingHand hand, int current) {
            List<Acceptance> result = new();
            int[] counts = hand.counts.ToArray();
            for (int kind = 0; kind < 34; kind++) {
                if (counts[kind] >= 4)
                    continue;
                counts[kind]++;
                int[] numbers = Shanten.Numbers(counts);
                bool advancing = Math.Min(numbers[0], Math.Min(numbers[1], numbers[2])) < current;
                counts[kind]--;
                if (advancing)
                    result.Add(new Acceptance(kind, 4 - hand.knownCounts[kind]));
            }
            return result;
        }
        public List<string> TenpaiLines(WaitingHand hand, List<Acceptance> waiting, bool furiten) {
            List<string> lines = new();
            string[] methods = { "ron", "tsumo" };
            WaitScore[] best = new WaitScore[2];
            foreach (Acceptance tile in waiting) {
                string[] results = new string[2];
                for (int i = 0; i < 2; i++) {
                    if (i == 0 && furiten) {
                        results[i] = "furiten";
                        continue;
                    }
                    Situation s = Hypothetical(hand, tile.kind, methods[i], rules);
                    Candidate candidate = BestCandidate(EvaluateCandidates(s));
                    if (candidate == null) {
                        results[i] = "no_yaku";
                        continue;
                    }
                    int points =
                        Scoring
                            .ComputePayments(candidate.basePoints, s.seat.Equals("E"), methods[i])
                            .points;
                    results[i] = Convert.ToString(points);
                    if (best[i] == null || points > best[i].points)
                        best[i] = new WaitScore(tile.kind, points);
                }
                lines.Add("WAIT " + Tiles.Name(tile.kind) + " left " + tile.remaining + " ron " +
                          results[0] + " tsumo " + results[1]);
            }
            string[] choices = new string[2];
            for (int i = 0; i < 2; i++)
                choices[i] =
                    best[i] == null ? "none" : Tiles.Name(best[i].kind) + " " + best[i].points;
            lines.Add("BEST ron " + choices[0] + " tsumo " + choices[1]);
            return lines;
        }
        public List<string> Waits() {
            List<string> lines = new();
            Counts statistics = new Counts();
            int[] counts = new int[7];
            foreach (Record record in hands) {
                WaitingHand hand = new WaitingHand(record, rules);
                lines.Add("HAND " + hand.label);
                string error = ValidateWaiting(hand);
                if (error != null) {
                    statistics.Add("errors", 1);
                    lines.Add("ERROR " + error);
                    continue;
                }
                int[] numbers = Shanten.Numbers(hand.counts);
                int current = Math.Min(numbers[0], Math.Min(numbers[1], numbers[2]));
                counts[current]++;
                lines.Add("SHANTEN standard " + numbers[0] + " chiitoitsu " + numbers[1] +
                          " kokushi " + numbers[2]);
                List<Acceptance> accepted = FindAcceptance(hand, current);
                int total = 0;
                foreach (Acceptance tile in accepted)
                    total += tile.remaining;
                if (current != 0) {
                    StringBuilder line =
                        new StringBuilder("ACCEPT kinds " + accepted.Count + " tiles " + total);
                    foreach (Acceptance tile in accepted)
                        line.Append(" ")
                            .Append(Tiles.Name(tile.kind))
                            .Append(":")
                            .Append(tile.remaining);
                    lines.Add(line.ToString());
                    continue;
                }
                statistics.Add("tenpai", 1);
                HashSet<int> discarded = new();
                foreach (Tiles.Tile tile in hand.discards)
                    discarded.Add(tile.kind);
                bool furiten = false;
                foreach (Acceptance tile in accepted)
                    if (discarded.Contains(tile.kind))
                        furiten = true;
                if (furiten)
                    statistics.Add("furiten", 1);
                lines.Add("TENPAI kinds " + accepted.Count + " tiles " + total + " furiten " +
                          (furiten ? "yes" : "no"));
                lines.AddRange(TenpaiLines(hand, accepted, furiten));
            }
            lines.Add("STATS hands " + hands.Count + " errors " + statistics.Get("errors") +
                      " tenpai " + statistics.Get("tenpai") + " furiten " +
                      statistics.Get("furiten"));
            for (int i = 0; i < 7; i++)
                lines.Add("SHANTEN_COUNT " + i + " " + counts[i]);
            return lines;
        }
        public void Write() {
            List<string> scores = Scores(), waits = Waits();
            Directory.CreateDirectory(Path.Combine("output"));
            File.WriteAllText(Path.Combine("output/scores.txt"), string.Join("\n", scores) + "\n",
                              System.Text.Encoding.ASCII);
            File.WriteAllText(Path.Combine("output/waits.txt"), string.Join("\n", waits) + "\n",
                              System.Text.Encoding.ASCII);
            File.WriteAllText(Path.Combine("output/summary.csv"), string.Join("\n", summary) + "\n",
                              System.Text.Encoding.ASCII);
        }
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        new Reports(ReadRules()).Write();
    }
}
public static class CountHelpers {
    public static void AddCount<K>(this IDictionary<K, int> counts, K key, int amount) {
        counts.TryGetValue(key, out int value);
        counts[key] = value + amount;
    }
}
