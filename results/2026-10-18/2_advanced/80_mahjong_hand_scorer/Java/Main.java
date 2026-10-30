import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    static final List<String> WAIT_ORDER = List.of("ryanmen", "kanchan", "penchan", "shanpon",
                                                   "tanki", "single", "thirteen"),
                              WIN_ORDER = List.of("dealer_ron", "dealer_tsumo", "nondealer_ron",
                                                  "nondealer_tsumo");
    record Rules(boolean openTanyao, boolean redFives, boolean doubleYakuman, boolean kazoeYakuman,
                 boolean kiriage, int honba) {}
    record Record(String label, Map<String, String> fields) {}
    record Facts(List<Scoring.Triplet> triplets, List<Integer> sequences,
                 List<List<Integer>> concealedSequences) {}
    record Winning(List<String> lines, int points) {}
    record Acceptance(int kind, int remaining) {}
    record WaitScore(int kind, int points) {}
    static List<Record> readRecords(String filename) throws Exception {
        List<Record> records = new ArrayList<>();
        for (String line :
             Files.readAllLines(Path.of("input", filename), StandardCharsets.US_ASCII)) {
            String[] parts = line.split(" ");
            Map<String, String> fields = new HashMap<>();
            for (int i = 1; i < parts.length; i++) {
                int equals = parts[i].indexOf('=');
                fields.put(parts[i].substring(0, equals), parts[i].substring(equals + 1));
            }
            records.add(new Record(parts[0], fields));
        }
        return records;
    }
    static Map<String, Rules> readRules() throws Exception {
        Map<String, Rules> rules = new LinkedHashMap<>();
        for (Record record : readRecords("rules.txt")) {
            Map<String, String> f = record.fields();
            rules.put(record.label(),
                      new Rules(f.get("open_tanyao").equals("yes"),
                                f.get("red_fives").equals("yes"),
                                f.get("double_yakuman").equals("yes"),
                                f.get("kazoe_yakuman").equals("yes"),
                                f.get("kiriage").equals("yes"), Integer.parseInt(f.get("honba"))));
        }
        return rules;
    }
    static final class Meld {
        String kind;
        List<Tiles.Tile> tiles;
        List<Integer> block = new ArrayList<>();
        Meld(String text) {
            kind = text.substring(0, 1);
            tiles = Tiles.parse(text.substring(1));
            if (tiles != null)
                for (Tiles.Tile tile : tiles)
                    block.add(tile.kind());
            Collections.sort(block);
        }
        boolean valid() {
            if (kind.equals("C"))
                return block.size() == 3 && block.getFirst() < 27 && block.getFirst() % 9 <= 6 &&
                    block.get(1) == block.getFirst() + 1 && block.get(2) == block.getFirst() + 2;
            if (!List.of("P", "K", "A").contains(kind))
                return false;
            return block.size() == (kind.equals("P") ? 3 : 4) && new HashSet<>(block).size() == 1;
        }
    }
    static final class Situation {
        String label, ruleName, by, seat, discarder, round;
        Rules rules;
        List<Tiles.Tile> hand, win, dora, ura, discards, allTiles;
        List<Meld> melds = new ArrayList<>();
        Set<String> flags = new HashSet<>();
        int seatTile, roundTile, kanCount, honba, sticks, winningTile;
        int[] handCounts, concealedCounts, meldCounts, allCounts;
        boolean closed, riichi;
        Situation(String label, Map<String, String> fields, Map<String, Rules> rules) {
            this.label = label;
            ruleName = fields.get("rules");
            this.rules = rules.get(ruleName);
            hand = Tiles.parse(fields.get("hand"));
            win = Tiles.parse(fields.get("win"));
            if (!fields.get("melds").equals("-"))
                for (String text : fields.get("melds").split(","))
                    melds.add(new Meld(text));
            dora = Tiles.parse(fields.get("dora"));
            ura = Tiles.parse(fields.get("ura"), true);
            discards = Tiles.parse(fields.get("discards"), true);
            by = fields.get("by");
            seat = fields.get("seat");
            discarder = fields.get("from");
            round = fields.get("round");
            seatTile = Tiles.windTile(seat);
            roundTile = Tiles.windTile(round);
            if (!fields.get("flags").equals("-"))
                flags.addAll(Arrays.asList(fields.get("flags").split(",")));
            closed = true;
            for (Meld meld : melds) {
                if (!meld.kind.equals("A"))
                    closed = false;
                if (meld.kind.equals("K") || meld.kind.equals("A"))
                    kanCount++;
            }
            riichi = flags.contains("riichi") || flags.contains("double_riichi");
            honba = Integer.parseInt(fields.get("honba"));
            sticks = Integer.parseInt(fields.get("sticks"));
        }
        void prepare() {
            winningTile = win.getFirst().kind();
            handCounts = Tiles.counts(hand);
            List<Tiles.Tile> concealed = new ArrayList<>(hand);
            concealed.addAll(win);
            concealedCounts = Tiles.counts(concealed);
            List<Tiles.Tile> meldTiles = new ArrayList<>();
            for (Meld meld : melds)
                meldTiles.addAll(meld.tiles);
            meldCounts = Tiles.counts(meldTiles);
            allTiles = new ArrayList<>(concealed);
            allTiles.addAll(meldTiles);
            allCounts = Tiles.counts(allTiles);
        }
    }
    static final class WaitingHand {
        String label;
        Map<String, String> fields;
        Rules rules;
        List<Tiles.Tile> hand, dora, discards, visible;
        int[] counts, knownCounts;
        WaitingHand(Record record, Map<String, Rules> rules) {
            label = record.label();
            fields = record.fields();
            this.rules = rules.get(fields.get("rules"));
            hand = Tiles.parse(fields.get("hand"));
            dora = Tiles.parse(fields.get("dora"));
            discards = Tiles.parse(fields.get("discards"), true);
            visible = Tiles.parse(fields.get("visible"), true);
        }
    }
    static final class Candidate {
        String formType, form, wait, category = "none";
        int pair;
        List<List<Integer>> sets;
        List<Integer> winningBlock;
        List<Yaku.Item> yaku = new ArrayList<>(), yakuman = new ArrayList<>(),
                        fuItems = new ArrayList<>();
        int multiplier, han, fu, fuTotal, base, dora, aka, ura;
        Candidate(String formType, int pair, List<List<Integer>> sets, List<Integer> winningBlock,
                  String form, String wait) {
            this.formType = formType;
            this.pair = pair;
            this.sets = sets;
            this.winningBlock = winningBlock;
            this.form = form;
            this.wait = wait;
        }
    }
    static String copyError(List<Tiles.Tile> allTiles, Rules rules) {
        int[] reds = new int[3];
        for (Tiles.Tile tile : allTiles)
            if (tile.red())
                reds[tile.kind() / 9]++;
        if (!rules.redFives() && (reds[0] + reds[1] + reds[2] > 0))
            return "red five not allowed";
        int[] counts = Tiles.counts(allTiles);
        for (int kind = 0; kind < 34; kind++)
            if (counts[kind] >= 5)
                return "too many copies of " + Tiles.name(kind);
        for (int suit = 0; suit < 3; suit++)
            if (reds[suit] >= 2)
                return "too many copies of 0" + Tiles.SUITS.charAt(suit);
        return null;
    }
    static String validateSituation(Situation s) {
        if (s.hand == null || s.win == null || s.dora == null || s.ura == null ||
            s.discards == null)
            return "bad tile notation";
        for (Meld meld : s.melds)
            if (meld.tiles == null)
                return "bad tile notation";
        if (s.win.size() != 1)
            return "bad tile notation";
        if (s.melds.size() >= 5)
            return "bad meld";
        for (Meld meld : s.melds)
            if (!meld.valid())
                return "bad meld";
        if (s.hand.size() != 13 - 3 * s.melds.size())
            return "wrong tile count";
        s.prepare();
        List<Tiles.Tile> observed = new ArrayList<>(s.allTiles);
        observed.addAll(s.dora);
        observed.addAll(s.ura);
        observed.addAll(s.discards);
        String error = copyError(observed, s.rules);
        if (error != null)
            return error;
        if (s.by.equals("tsumo") && !s.discarder.equals("-") ||
            s.by.equals("ron") && (s.discarder.equals("-") || s.discarder.equals(s.seat)))
            return "invalid discarder";
        Set<String> f = s.flags;
        for (String flag : Yaku.FLAGS)
            if (f.contains(flag)) {
                boolean valid = switch (flag) {
                    case "riichi" -> s.closed;
                    case "double_riichi" -> s.closed && !f.contains("riichi");
                    case "ippatsu" -> s.riichi && !f.contains("rinshan");
                    case "haitei" -> s.by.equals("tsumo") && !f.contains("rinshan");
                    case "houtei" -> s.by.equals("ron") && !f.contains("chankan");
                    case "rinshan" -> s.by.equals("tsumo") && s.kanCount >= 1;
                    case "chankan" -> s.by.equals("ron");
                    case "tenhou" ->
                        s.seat.equals("E") && s.by.equals("tsumo") && s.melds.isEmpty() &&
                            f.size() == 1;
                    default ->
                        !s.seat.equals("E") && s.by.equals("tsumo") && s.melds.isEmpty() &&
                            f.size() == 1;
                };
                if (!valid)
                    return "invalid flag " + flag;
            }
        if (s.dora.size() != 1 + s.kanCount)
            return "invalid dora indicators";
        if (s.riichi && s.ura.size() != s.dora.size() || !s.riichi && !s.ura.isEmpty())
            return "invalid ura indicators";
        if (s.riichi && s.sticks == 0)
            return "invalid sticks";
        if (!Decomposition.winning(s.concealedCounts, s.melds.size()))
            return "not a winning hand";
        return null;
    }
    static String validateWaiting(WaitingHand hand) {
        if (hand.hand == null || hand.dora == null || hand.discards == null || hand.visible == null)
            return "bad tile notation";
        if (hand.hand.size() != 13)
            return "wrong tile count";
        List<Tiles.Tile> observed = new ArrayList<>(hand.hand);
        observed.addAll(hand.dora);
        observed.addAll(hand.discards);
        observed.addAll(hand.visible);
        String error = copyError(observed, hand.rules);
        if (error == null) {
            hand.counts = Tiles.counts(hand.hand);
            hand.knownCounts = Tiles.counts(observed);
        }
        return error;
    }
    static List<Candidate> candidates(Situation s) {
        List<Candidate> result = new ArrayList<>();
        int winning = s.winningTile;
        int[] counts = s.concealedCounts;
        for (Decomposition.Form split : Decomposition.standard(counts, s.melds.size())) {
            List<List<Integer>> blocks = new ArrayList<>();
            blocks.add(List.of(split.pair(), split.pair()));
            blocks.addAll(split.sets());
            Set<List<Integer>> choices = new LinkedHashSet<>();
            for (List<Integer> block : blocks)
                if (block.contains(winning))
                    choices.add(block);
            for (List<Integer> chosen : choices) {
                List<String> parts = new ArrayList<>(List.of("standard"));
                boolean marked = false;
                for (List<Integer> block : blocks) {
                    String notation = Tiles.block(block);
                    if (block.equals(chosen) && !marked) {
                        notation += "*";
                        marked = true;
                    }
                    parts.add(notation);
                }
                for (Meld meld : s.melds)
                    parts.add(meld.kind + Tiles.block(meld.block));
                String wait = Decomposition.waitShape("standard", chosen, winning, s.handCounts);
                result.add(new Candidate("standard", split.pair(), split.sets(), chosen,
                                         String.join(" ", parts), wait));
            }
        }
        if (s.melds.isEmpty() && Decomposition.sevenPairs(counts)) {
            List<String> parts = new ArrayList<>(List.of("chiitoitsu"));
            for (int kind = 0; kind < 34; kind++)
                if (counts[kind] > 0)
                    parts.add(Tiles.block(List.of(kind, kind)) + (kind == winning ? "*" : ""));
            result.add(
                new Candidate("chiitoitsu", -1, List.of(), null, String.join(" ", parts), "tanki"));
        }
        if (s.melds.isEmpty() && Decomposition.thirteenOrphans(counts)) {
            List<String> parts = new ArrayList<>(List.of("kokushi"));
            for (int kind : Tiles.YAOCHUU)
                parts.add(Tiles.block(Collections.nCopies(counts[kind], kind)) +
                          (kind == winning ? "*" : ""));
            String wait = Decomposition.waitShape("kokushi", null, winning, s.handCounts);
            result.add(
                new Candidate("kokushi", -1, List.of(), null, String.join(" ", parts), wait));
        }
        result.sort(Comparator.comparing(candidate -> candidate.form));
        return result;
    }
    static Facts blockFacts(Situation s, Candidate candidate) {
        List<Scoring.Triplet> triplets = new ArrayList<>();
        List<Integer> sequences = new ArrayList<>();
        List<List<Integer>> concealedSequences = new ArrayList<>();
        for (List<Integer> block : candidate.sets)
            if (block.getFirst().equals(block.getLast()))
                triplets.add(new Scoring.Triplet(
                    block, s.by.equals("tsumo") || !block.equals(candidate.winningBlock), false));
            else {
                sequences.add(block.getFirst());
                concealedSequences.add(block);
            }
        for (Meld meld : s.melds)
            if (meld.kind.equals("C"))
                sequences.add(meld.block.getFirst());
            else
                triplets.add(new Scoring.Triplet(meld.block, meld.kind.equals("A"),
                                                 meld.kind.equals("K") || meld.kind.equals("A")));
        return new Facts(triplets, sequences, concealedSequences);
    }
    static Set<String> yakumanNames(Situation s, Candidate candidate, Set<Integer> kinds,
                                    List<Scoring.Triplet> triplets) {
        Set<String> names = new HashSet<>();
        for (String name : List.of("tenhou", "chiihou"))
            if (s.flags.contains(name))
                names.add(name);
        boolean honors = true, terminals = true, green = true;
        Set<Integer> suits = new HashSet<>();
        for (int kind : kinds) {
            honors &= Tiles.honor(kind);
            terminals &= Tiles.terminal(kind);
            green &= Tiles.GREEN.contains(kind);
            suits.add(kind / 9);
        }
        if (honors)
            names.add("tsuuiisou");
        if (terminals)
            names.add("chinroutou");
        if (green)
            names.add("ryuuiisou");
        if (s.melds.isEmpty() && suits.size() == 1 && !suits.contains(3)) {
            int start = suits.iterator().next() * 9;
            boolean chuuren = s.allCounts[start] >= 3 && s.allCounts[start + 8] >= 3;
            for (int i = 1; i <= 7; i++)
                chuuren &= s.allCounts[start + i] >= 1;
            if (chuuren) {
                int[] initial = Arrays.copyOfRange(s.handCounts, start, start + 9);
                names.add(Arrays.equals(initial, new int[] {3, 1, 1, 1, 1, 1, 1, 1, 3})
                              ? "junsei_chuuren"
                              : "chuuren");
            }
        }
        if (candidate.formType.equals("kokushi"))
            names.add(candidate.wait.equals("thirteen") ? "kokushi_13" : "kokushi");
        if (candidate.formType.equals("standard")) {
            int concealed = 0, dragons = 0, winds = 0, kans = 0;
            for (Scoring.Triplet triplet : triplets) {
                if (triplet.concealed())
                    concealed++;
                if (triplet.kan())
                    kans++;
                int kind = triplet.kinds().getFirst();
                if (kind >= 31)
                    dragons++;
                else if (kind >= 27)
                    winds++;
            }
            if (concealed == 4)
                names.add(candidate.wait.equals("tanki") ? "suuankou_tanki" : "suuankou");
            if (dragons == 3)
                names.add("daisangen");
            if (winds == 4)
                names.add("daisuushii");
            if (winds == 3 && candidate.pair >= 27 && candidate.pair <= 30)
                names.add("shousuushii");
            if (kans == 4)
                names.add("suukantsu");
        }
        return names;
    }
    static Set<String> ordinaryNames(Situation s, Candidate c, Set<Integer> kinds, Facts facts) {
        Set<String> names = new HashSet<>();
        for (String flag : Yaku.FLAGS.subList(0, 7))
            if (s.flags.contains(flag))
                names.add(flag);
        if (s.closed && s.by.equals("tsumo"))
            names.add("menzen_tsumo");
        boolean simple = true, yaochuu = true, honors = false;
        Set<Integer> numberSuits = new HashSet<>();
        for (int kind : kinds) {
            simple &= !Tiles.yaochuu(kind);
            yaochuu &= Tiles.yaochuu(kind);
            honors |= Tiles.honor(kind);
            if (kind < 27)
                numberSuits.add(kind / 9);
        }
        if (simple && (s.closed || s.rules.openTanyao()))
            names.add("tanyao");
        if (yaochuu)
            names.add("honroutou");
        if (numberSuits.size() == 1)
            names.add(honors ? "honitsu" : "chinitsu");
        if (c.formType.equals("chiitoitsu"))
            names.add("chiitoitsu");
        if (!c.formType.equals("standard"))
            return names;
        boolean yakuhaiPair = c.pair >= 31 || c.pair == s.seatTile || c.pair == s.roundTile;
        if (s.closed && s.melds.isEmpty() && facts.concealedSequences().size() == 4 &&
            !yakuhaiPair && c.wait.equals("ryanmen"))
            names.add("pinfu");
        Map<List<Integer>, Integer> repeated = new HashMap<>();
        for (List<Integer> block : facts.concealedSequences())
            repeated.merge(block, 1, Integer::sum);
        int pairs = 0;
        boolean duplicate = false;
        for (int count : repeated.values()) {
            pairs += count / 2;
            duplicate |= count >= 2;
        }
        if (s.closed && facts.concealedSequences().size() == 4 && pairs == 2)
            names.add("ryanpeikou");
        else if (s.closed && duplicate)
            names.add("iipeikou");
        Set<Integer> tripletKinds = new HashSet<>();
        int concealed = 0, kans = 0, dragons = 0;
        for (Scoring.Triplet triplet : facts.triplets()) {
            int kind = triplet.kinds().getFirst();
            tripletKinds.add(kind);
            if (triplet.concealed())
                concealed++;
            if (triplet.kan())
                kans++;
            if (kind >= 31)
                dragons++;
        }
        int[] valued = {31, 32, 33, s.seatTile, s.roundTile};
        String[] valuedNames = {"haku", "hatsu", "chun", "jikaze", "bakaze"};
        for (int i = 0; i < valued.length; i++)
            if (tripletKinds.contains(valued[i]))
                names.add(valuedNames[i]);
        if (facts.triplets().size() == 4)
            names.add("toitoi");
        if (concealed == 3)
            names.add("sanankou");
        Set<Integer> sequenceKinds = new HashSet<>(facts.sequences());
        for (int start = 0; start < 7; start++)
            if (sequenceKinds.contains(start) && sequenceKinds.contains(start + 9) &&
                sequenceKinds.contains(start + 18))
                names.add("sanshoku_doujun");
        for (int number = 0; number < 9; number++)
            if (tripletKinds.contains(number) && tripletKinds.contains(number + 9) &&
                tripletKinds.contains(number + 18))
                names.add("sanshoku_doukou");
        for (int suit = 0; suit < 3; suit++)
            if (sequenceKinds.contains(suit * 9) && sequenceKinds.contains(suit * 9 + 3) &&
                sequenceKinds.contains(suit * 9 + 6))
                names.add("ittsu");
        List<List<Integer>> blocks = new ArrayList<>();
        blocks.add(List.of(c.pair, c.pair));
        blocks.addAll(c.sets);
        for (Meld meld : s.melds)
            blocks.add(meld.block);
        boolean outside = !facts.sequences().isEmpty();
        for (List<Integer> block : blocks) {
            boolean contains = false;
            for (int kind : block)
                contains |= Tiles.yaochuu(kind);
            outside &= contains;
        }
        if (outside)
            names.add(honors ? "chanta" : "junchan");
        if (kans == 3)
            names.add("sankantsu");
        if (dragons == 2 && c.pair >= 31)
            names.add("shousangen");
        return names;
    }
    static Candidate evaluateCandidate(Situation s, Candidate candidate) {
        Set<Integer> kinds = new HashSet<>();
        for (int kind = 0; kind < 34; kind++)
            if (s.allCounts[kind] > 0)
                kinds.add(kind);
        Facts facts = blockFacts(s, candidate);
        Set<String> names = yakumanNames(s, candidate, kinds, facts.triplets());
        candidate.yakuman = Yaku.yakuman(names, s.rules.doubleYakuman());
        if (!candidate.yakuman.isEmpty()) {
            for (Yaku.Item item : candidate.yakuman)
                candidate.multiplier += item.value();
            candidate.base = 8000 * candidate.multiplier;
            candidate.category = "yakuman";
            return candidate;
        }
        names = ordinaryNames(s, candidate, kinds, facts);
        candidate.yaku = Yaku.ordinary(names, s.closed);
        for (Tiles.Tile tile : s.dora)
            candidate.dora += s.allCounts[Tiles.nextDora(tile.kind())];
        for (Tiles.Tile tile : s.ura)
            candidate.ura += s.allCounts[Tiles.nextDora(tile.kind())];
        for (Tiles.Tile tile : s.allTiles)
            if (tile.red())
                candidate.aka++;
        Scoring.Fu fu = Scoring.fuBreakdown(candidate.formType, candidate.pair, facts.triplets(),
                                            candidate.wait, s.closed, s.by, s.seatTile, s.roundTile,
                                            names.contains("pinfu"));
        candidate.fuItems = fu.items();
        candidate.fuTotal = fu.total();
        candidate.fu = fu.rounded();
        if (!candidate.yaku.isEmpty()) {
            candidate.han = candidate.dora + candidate.aka + candidate.ura;
            for (Yaku.Item item : candidate.yaku)
                candidate.han += item.value();
            Scoring.Limit limit = Scoring.limit(candidate.han, candidate.fu, s.rules);
            candidate.category = limit.category();
            candidate.base = limit.base();
        }
        return candidate;
    }
    static List<Candidate> evaluateCandidates(Situation s) {
        List<Candidate> result = candidates(s);
        for (Candidate candidate : result)
            evaluateCandidate(s, candidate);
        return result;
    }
    static int compareCandidates(Candidate a, Candidate b) {
        int compared = Integer.compare(b.base, a.base);
        if (compared != 0)
            return compared;
        compared = Boolean.compare(!b.yakuman.isEmpty(), !a.yakuman.isEmpty());
        if (compared != 0)
            return compared;
        if (a.yakuman.isEmpty() && b.yakuman.isEmpty()) {
            compared = Integer.compare(b.han, a.han);
            if (compared != 0)
                return compared;
            compared = Integer.compare(b.fu, a.fu);
            if (compared != 0)
                return compared;
        }
        return a.form.compareTo(b.form);
    }
    static Candidate bestCandidate(List<Candidate> candidates) {
        Candidate best = null;
        for (Candidate candidate : candidates)
            if (candidate.base >= 1 && (best == null || compareCandidates(candidate, best) < 0))
                best = candidate;
        return best;
    }
    static String names(List<Yaku.Item> items, String separator) {
        List<String> names = new ArrayList<>();
        for (Yaku.Item item : items)
            names.add(item.name());
        return String.join(separator, names);
    }
    static String candidateLine(Candidate c) {
        String evaluation = !c.yakuman.isEmpty() ? "yakuman " + c.multiplier + " base " + c.base +
                                                       " yaku " + names(c.yakuman, ",")
                            : c.yaku.isEmpty()   ? "no_yaku"
                                                 : "han " + c.han + " fu " + c.fu + " base " +
                                                       c.base + " yaku " + names(c.yaku, ",");
        return "CANDIDATE " + c.form + " = " + c.wait + " " + evaluation;
    }
    static Winning winningLines(Situation s, Candidate c) {
        List<String> lines = new ArrayList<>(List.of("FORM " + c.form, "WAIT " + c.wait));
        if (!c.yakuman.isEmpty()) {
            for (Yaku.Item item : c.yakuman)
                lines.add("YAKUMAN " + item.name() + " " + item.value());
            lines.add("SCORE yakuman " + c.multiplier + " base " + c.base);
        } else {
            for (Yaku.Item item : c.yaku)
                lines.add("YAKU " + item.name() + " " + item.value());
            lines.add("DORA dora " + c.dora + " aka " + c.aka + " ura " + c.ura);
            for (Yaku.Item item : c.fuItems)
                lines.add("FU " + item.name() + " " + item.value());
            lines.add("FU total " + c.fuTotal + " " + c.fu);
            lines.add("SCORE han " + c.han + " fu " + c.fu + " limit " + c.category + " base " +
                      c.base);
        }
        Scoring.Payments p = Scoring.payments(c.base, s.seat.equals("E"), s.by);
        if (s.by.equals("ron"))
            lines.add("PAY ron " + p.ron());
        else if (s.seat.equals("E"))
            lines.add("PAY tsumo all " + p.nondealer());
        else
            lines.add("PAY tsumo dealer " + p.dealer() + " nondealer " + p.nondealer());
        int honba = s.honba * s.rules.honba(), sticks = s.sticks * 1000,
            gain = p.points() + honba + sticks;
        lines.add("BONUS honba " + honba + " sticks " + sticks);
        lines.add("TOTAL points " + p.points() + " gain " + gain);
        int[] delta = new int[4];
        if (s.by.equals("ron"))
            delta[Tiles.WINDS.indexOf(s.discarder)] = -p.ron() - honba;
        else
            for (int i = 0; i < 4; i++)
                if (i != Tiles.WINDS.indexOf(s.seat))
                    delta[i] = -(i == 0 ? p.dealer() : p.nondealer()) - honba / 3;
        delta[Tiles.WINDS.indexOf(s.seat)] = gain;
        List<String> changes = new ArrayList<>();
        for (int i = 0; i < 4; i++)
            changes.add(Tiles.WINDS.charAt(i) + " " + (delta[i] > 0 ? "+" : "") + delta[i]);
        lines.add("DELTA " + String.join(" ", changes));
        return new Winning(lines, p.points());
    }
    static Situation hypothetical(WaitingHand hand, int winning, String method,
                                  Map<String, Rules> rules) {
        Map<String, String> fields = new HashMap<>(hand.fields);
        fields.put("melds", "-");
        fields.put("win", Tiles.name(winning));
        fields.put("by", method);
        fields.put("from", method.equals("tsumo")           ? "-"
                           : fields.get("seat").equals("E") ? "S"
                                                            : "E");
        fields.put("flags", fields.get("riichi").equals("yes") ? "riichi" : "-");
        fields.put("ura", "-");
        fields.put("honba", "0");
        fields.put("sticks", "0");
        Situation s = new Situation(hand.label, fields, rules);
        s.prepare();
        return s;
    }
    static final class Counts {
        Map<String, Integer> values = new HashMap<>();
        int get(String key) { return values.getOrDefault(key, 0); }
        void add(String key, int amount) { values.put(key, get(key) + amount); }
        String named(List<String> names) {
            List<String> pieces = new ArrayList<>();
            for (String name : names)
                pieces.add(name + " " + get(name));
            return String.join(" ", pieces);
        }
    }
    static final class Reports {
        Map<String, Rules> rules;
        List<Record> situations, hands;
        Counts stats = new Counts(), winCounts = new Counts(), waitCounts = new Counts(),
               limitCounts = new Counts(), yakuCounts = new Counts();
        Map<Integer, Integer> hanCounts = new TreeMap<>(), fuCounts = new TreeMap<>();
        Map<String, Counts> ruleCounts = new LinkedHashMap<>();
        int maximum;
        String maximumHand = "-";
        List<String> summary = new ArrayList<>(List.of("hand,han,fu,points,yaku"));
        Reports(Map<String, Rules> rules) throws Exception {
            this.rules = rules;
            situations = readRecords("hands.txt");
            hands = readRecords("waits.txt");
            for (String name : rules.keySet())
                ruleCounts.put(name, new Counts());
        }
        void recordWin(Situation s, Candidate c, int points) {
            stats.add("wins", 1);
            stats.add("points", points);
            ruleCounts.get(s.ruleName).add("wins", 1);
            ruleCounts.get(s.ruleName).add("points", points);
            winCounts.add((s.seat.equals("E") ? "dealer_" : "nondealer_") + s.by, 1);
            waitCounts.add(c.wait, 1);
            limitCounts.add(c.category, 1);
            List<Yaku.Item> names = c.yakuman.isEmpty() ? c.yaku : c.yakuman;
            for (Yaku.Item item : names)
                yakuCounts.add(item.name(), 1);
            String han, fu;
            if (!c.yakuman.isEmpty()) {
                han = "Y" + c.multiplier;
                fu = "-";
            } else {
                han = Integer.toString(c.han);
                fu = Integer.toString(c.fu);
                hanCounts.merge(c.han, 1, Integer::sum);
                fuCounts.merge(c.fu, 1, Integer::sum);
            }
            summary.add(s.label + "," + han + "," + fu + "," + points + "," + names(names, ";"));
            if (points > maximum) {
                maximum = points;
                maximumHand = s.label;
            }
        }
        List<String> scores() {
            List<String> lines = new ArrayList<>();
            for (Record record : situations) {
                Situation s = new Situation(record.label(), record.fields(), rules);
                ruleCounts.get(s.ruleName).add("hands", 1);
                lines.add("HAND " + s.label);
                String error = validateSituation(s);
                if (error != null) {
                    stats.add("errors", 1);
                    lines.add("ERROR " + error);
                    summary.add(s.label + ",-,-,0,ERROR");
                    continue;
                }
                List<Integer> waiting =
                    Decomposition.waitingTiles(s.handCounts, s.meldCounts, s.melds.size());
                List<String> waitingNames = new ArrayList<>();
                for (int kind : waiting)
                    waitingNames.add(Tiles.name(kind));
                lines.add("WAITS " + String.join(" ", waitingNames));
                List<Candidate> evaluated = evaluateCandidates(s);
                for (Candidate candidate : evaluated)
                    lines.add(candidateLine(candidate));
                boolean furiten = false;
                if (s.by.equals("ron"))
                    for (Tiles.Tile tile : s.discards)
                        if (waiting.contains(tile.kind()))
                            furiten = true;
                if (furiten) {
                    stats.add("furiten", 1);
                    lines.add("RESULT furiten");
                    summary.add(s.label + ",-,-,0,FURITEN");
                    continue;
                }
                Candidate best = bestCandidate(evaluated);
                if (best == null) {
                    stats.add("no_yaku", 1);
                    lines.add("RESULT no_yaku");
                    summary.add(s.label + ",-,-,0,NO_YAKU");
                    continue;
                }
                Winning report = winningLines(s, best);
                lines.addAll(report.lines());
                recordWin(s, best, report.points());
            }
            lines.addAll(scoreStatistics());
            return lines;
        }
        List<String> scoreStatistics() {
            List<String> lines = new ArrayList<>(
                List.of("STATS hands " + situations.size() + " wins " + stats.get("wins") +
                            " furiten " + stats.get("furiten") + " no_yaku " +
                            stats.get("no_yaku") + " errors " + stats.get("errors"),
                        "WINS " + winCounts.named(WIN_ORDER),
                        "WAIT_COUNT " + waitCounts.named(WAIT_ORDER)));
            for (Map.Entry<Integer, Integer> entry : hanCounts.entrySet())
                lines.add("HAN_COUNT " + entry.getKey() + " " + entry.getValue());
            for (Map.Entry<Integer, Integer> entry : fuCounts.entrySet())
                lines.add("FU_COUNT " + entry.getKey() + " " + entry.getValue());
            for (String category : Yaku.CATEGORIES)
                lines.add("LIMIT " + category + " " + limitCounts.get(category));
            List<String> names = new ArrayList<>();
            for (Yaku.Definition definition : Yaku.YAKU)
                names.add(definition.name());
            for (Yaku.Item item : Yaku.YAKUMAN)
                names.add(item.name());
            for (String name : names)
                if (yakuCounts.get(name) > 0)
                    lines.add("YAKU_COUNT " + name + " " + yakuCounts.get(name));
            lines.add("POINTS total " + stats.get("points") + " max " + maximum + " hand " +
                      maximumHand);
            for (Map.Entry<String, Counts> entry : ruleCounts.entrySet())
                lines.add("RULE " + entry.getKey() + " " +
                          entry.getValue().named(List.of("hands", "wins", "points")));
            return lines;
        }
        List<Acceptance> acceptance(WaitingHand hand, int current) {
            List<Acceptance> result = new ArrayList<>();
            int[] counts = hand.counts.clone();
            for (int kind = 0; kind < 34; kind++) {
                if (counts[kind] >= 4)
                    continue;
                counts[kind]++;
                int[] numbers = Shanten.numbers(counts);
                boolean advancing =
                    Math.min(numbers[0], Math.min(numbers[1], numbers[2])) < current;
                counts[kind]--;
                if (advancing)
                    result.add(new Acceptance(kind, 4 - hand.knownCounts[kind]));
            }
            return result;
        }
        List<String> tenpaiLines(WaitingHand hand, List<Acceptance> waiting, boolean furiten) {
            List<String> lines = new ArrayList<>();
            String[] methods = {"ron", "tsumo"};
            WaitScore[] best = new WaitScore[2];
            for (Acceptance tile : waiting) {
                String[] results = new String[2];
                for (int i = 0; i < 2; i++) {
                    if (i == 0 && furiten) {
                        results[i] = "furiten";
                        continue;
                    }
                    Situation s = hypothetical(hand, tile.kind(), methods[i], rules);
                    Candidate candidate = bestCandidate(evaluateCandidates(s));
                    if (candidate == null) {
                        results[i] = "no_yaku";
                        continue;
                    }
                    int points =
                        Scoring.payments(candidate.base, s.seat.equals("E"), methods[i]).points();
                    results[i] = Integer.toString(points);
                    if (best[i] == null || points > best[i].points())
                        best[i] = new WaitScore(tile.kind(), points);
                }
                lines.add("WAIT " + Tiles.name(tile.kind()) + " left " + tile.remaining() +
                          " ron " + results[0] + " tsumo " + results[1]);
            }
            String[] choices = new String[2];
            for (int i = 0; i < 2; i++)
                choices[i] =
                    best[i] == null ? "none" : Tiles.name(best[i].kind()) + " " + best[i].points();
            lines.add("BEST ron " + choices[0] + " tsumo " + choices[1]);
            return lines;
        }
        List<String> waits() {
            List<String> lines = new ArrayList<>();
            Counts statistics = new Counts();
            int[] counts = new int[7];
            for (Record record : hands) {
                WaitingHand hand = new WaitingHand(record, rules);
                lines.add("HAND " + hand.label);
                String error = validateWaiting(hand);
                if (error != null) {
                    statistics.add("errors", 1);
                    lines.add("ERROR " + error);
                    continue;
                }
                int[] numbers = Shanten.numbers(hand.counts);
                int current = Math.min(numbers[0], Math.min(numbers[1], numbers[2]));
                counts[current]++;
                lines.add("SHANTEN standard " + numbers[0] + " chiitoitsu " + numbers[1] +
                          " kokushi " + numbers[2]);
                List<Acceptance> accepted = acceptance(hand, current);
                int total = 0;
                for (Acceptance tile : accepted)
                    total += tile.remaining();
                if (current != 0) {
                    StringBuilder line =
                        new StringBuilder("ACCEPT kinds " + accepted.size() + " tiles " + total);
                    for (Acceptance tile : accepted)
                        line.append(" ")
                            .append(Tiles.name(tile.kind()))
                            .append(":")
                            .append(tile.remaining());
                    lines.add(line.toString());
                    continue;
                }
                statistics.add("tenpai", 1);
                Set<Integer> discarded = new HashSet<>();
                for (Tiles.Tile tile : hand.discards)
                    discarded.add(tile.kind());
                boolean furiten = false;
                for (Acceptance tile : accepted)
                    if (discarded.contains(tile.kind()))
                        furiten = true;
                if (furiten)
                    statistics.add("furiten", 1);
                lines.add("TENPAI kinds " + accepted.size() + " tiles " + total + " furiten " +
                          (furiten ? "yes" : "no"));
                lines.addAll(tenpaiLines(hand, accepted, furiten));
            }
            lines.add("STATS hands " + hands.size() + " errors " + statistics.get("errors") +
                      " tenpai " + statistics.get("tenpai") + " furiten " +
                      statistics.get("furiten"));
            for (int i = 0; i < 7; i++)
                lines.add("SHANTEN_COUNT " + i + " " + counts[i]);
            return lines;
        }
        void write() throws Exception {
            List<String> scores = scores(), waits = waits();
            Files.createDirectories(Path.of("output"));
            Files.writeString(Path.of("output/scores.txt"), String.join("\n", scores) + "\n",
                              StandardCharsets.US_ASCII);
            Files.writeString(Path.of("output/waits.txt"), String.join("\n", waits) + "\n",
                              StandardCharsets.US_ASCII);
            Files.writeString(Path.of("output/summary.csv"), String.join("\n", summary) + "\n",
                              StandardCharsets.US_ASCII);
        }
    }
    public static void main(String[] args) throws Exception { new Reports(readRules()).write(); }
}
