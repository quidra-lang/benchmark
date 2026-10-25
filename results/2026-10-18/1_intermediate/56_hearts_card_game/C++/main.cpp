#include <algorithm>
#include <array>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <initializer_list>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>
#include <vector>

using CardSet = std::set<int>;

const std::string SEATS = "NESW";
const std::string SUITS = "CDSH";
const std::string RANKS = "23456789TJQKA";
constexpr int TWO_OF_CLUBS = 0;
constexpr int JD = 22;
constexpr int QS = 36;
constexpr int KS = 37;
constexpr int AS = 38;

enum class Strategy { Basic, Low, High, Smart, Moon };
const std::array<std::string, 5> STRATEGY_NAMES = {"BASIC", "LOW", "HIGH", "SMART", "MOON"};

enum class State { None, Between, Passing, Playing };

class CommandError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

[[noreturn]] void fail(const std::string& reason) { throw CommandError(reason); }

bool one_of(std::string_view word, std::initializer_list<std::string_view> choices) {
    return std::find(choices.begin(), choices.end(), word) != choices.end();
}

std::string seat_name(int seat) { return std::string(1, SEATS[seat]); }

std::string card_text(int card) { return {RANKS[card % 13], SUITS[card / 13]}; }

std::string cards_text(const CardSet& cards) {
    std::string text;
    for (int card : cards) {
        if (!text.empty()) text += ' ';
        text += card_text(card);
    }
    return text.empty() ? "-" : text;
}

std::string direction_name(char code) {
    switch (code) {
    case 'L': return "LEFT";
    case 'R': return "RIGHT";
    case 'A': return "ACROSS";
    default: return "HOLD";
    }
}

std::string strategy_name(Strategy strategy) {
    return STRATEGY_NAMES[static_cast<std::size_t>(strategy)];
}

int seat_value(const std::string& word) {
    if (word.size() != 1 || SEATS.find(word[0]) == std::string::npos) fail("bad seat " + word);
    return static_cast<int>(SEATS.find(word[0]));
}

int card_value(const std::string& word) {
    if (word.size() != 2 || RANKS.find(word[0]) == std::string::npos ||
        SUITS.find(word[1]) == std::string::npos) {
        fail("bad card " + word);
    }
    return static_cast<int>(SUITS.find(word[1]) * 13 + RANKS.find(word[0]));
}

Strategy strategy_value(const std::string& word) {
    auto found = std::find(STRATEGY_NAMES.begin(), STRATEGY_NAMES.end(), word);
    if (found == STRATEGY_NAMES.end()) fail("bad value " + word);
    return static_cast<Strategy>(found - STRATEGY_NAMES.begin());
}

int bounded(const std::string& word, int low, int high) {
    int value = 0;
    const char* end = word.data() + word.size();
    auto [last, error] = std::from_chars(word.data(), end, value);
    if (error != std::errc() || last != end || value < low || value > high) {
        fail("bad value " + word);
    }
    return value;
}

bool by_rank(int a, int b) {
    return std::make_pair(a % 13, a / 13) < std::make_pair(b % 13, b / 13);
}

bool by_rank_descending(int a, int b) {
    return std::make_pair(-(a % 13), a / 13) < std::make_pair(-(b % 13), b / 13);
}

int lowest(const CardSet& cards) { return *std::min_element(cards.begin(), cards.end(), by_rank); }

int highest(const CardSet& cards) {
    return *std::min_element(cards.begin(), cards.end(), by_rank_descending);
}

std::vector<int> sorted_cards(const CardSet& cards, bool (*order)(int, int)) {
    std::vector<int> sorted(cards.begin(), cards.end());
    std::sort(sorted.begin(), sorted.end(), order);
    return sorted;
}

template <typename Predicate>
CardSet filter_cards(const CardSet& cards, Predicate predicate) {
    CardSet result;
    std::copy_if(cards.begin(), cards.end(), std::inserter(result, result.end()), predicate);
    return result;
}

int count_suit(const CardSet& cards, int suit) {
    return static_cast<int>(
        std::count_if(cards.begin(), cards.end(), [suit](int card) { return card / 13 == suit; }));
}

bool penalty(int card) { return card == QS || card / 13 == 3; }

template <typename T>
std::string pairs(const std::string& label, const std::array<T, 4>& values) {
    std::ostringstream out;
    out << label;
    for (int seat = 0; seat < 4; ++seat) out << ' ' << SEATS[seat] << ' ' << values[seat];
    return out.str();
}

std::array<int, 4> ranking(const std::array<int, 4>& scores) {
    std::array<int, 4> seats = {0, 1, 2, 3};
    std::stable_sort(seats.begin(), seats.end(),
                     [&scores](int a, int b) { return scores[a] < scores[b]; });
    return seats;
}

class Generator {
public:
    explicit Generator(std::int64_t seed) : state_(seed) {}

    std::int64_t draw() {
        state_ = 48271 * state_ % 2147483647;
        return state_;
    }

    void shuffle(std::vector<int>& deck) {
        for (int i = static_cast<int>(deck.size()) - 1; i > 0; --i) {
            int j = static_cast<int>(draw() % (i + 1));
            std::swap(deck[i], deck[j]);
        }
    }

private:
    std::int64_t state_;
};

bool switch_value(const std::string& word) {
    if (!one_of(word, {"ON", "OFF"})) fail("bad value " + word);
    return word == "ON";
}

std::string switch_text(bool on) { return on ? "ON" : "OFF"; }

struct Rules {
    int target = 100;
    int limit = 100;
    std::string moon = "ADD";
    bool jack = false;
    bool qs_break = false;
    bool blood = false;
    std::string pass = "LRAH";

    Rules with(const std::string& name, const std::string& word) const {
        Rules next = *this;
        if (name == "TARGET") {
            next.target = bounded(word, 1, 1000);
        } else if (name == "LIMIT") {
            next.limit = bounded(word, 1, 100);
        } else if (name == "MOON") {
            if (!one_of(word, {"ADD", "SUB", "AUTO"})) fail("bad value " + word);
            next.moon = word;
        } else if (name == "JACK") {
            next.jack = switch_value(word);
        } else if (name == "QSBREAK") {
            next.qs_break = switch_value(word);
        } else if (name == "BLOOD") {
            next.blood = switch_value(word);
        } else if (name == "PASS") {
            if (word.empty() || word.size() > 8 ||
                word.find_first_not_of("LRAH") != std::string::npos) {
                fail("bad value " + word);
            }
            next.pass = word;
        } else {
            fail("unknown rule " + name);
        }
        return next;
    }

    std::string text() const {
        return "rules TARGET " + std::to_string(target) + " LIMIT " + std::to_string(limit) +
               " MOON " + moon + " JACK " + switch_text(jack) + " QSBREAK " +
               switch_text(qs_break) + " BLOOD " + switch_text(blood) + " PASS " + pass;
    }
};

struct Stats {
    int tricks = 0;
    int hearts = 0;
    int queens = 0;
    int moons = 0;

    Stats& operator+=(const Stats& other) {
        tricks += other.tricks;
        hearts += other.hearts;
        queens += other.queens;
        moons += other.moons;
        return *this;
    }

    std::string text() const {
        return "tricks " + std::to_string(tricks) + " hearts " + std::to_string(hearts) +
               " queens " + std::to_string(queens) + " moons " + std::to_string(moons);
    }
};

struct Play {
    int seat;
    int card;
};

using Trick = std::vector<Play>;

int trick_winner(const Trick& plays) {
    int led = plays[0].card / 13;
    const Play* best = &plays[0];
    for (const Play& play : plays) {
        if (play.card / 13 == led && play.card % 13 > best->card % 13) best = &play;
    }
    return best->seat;
}

std::string plays_text(const Trick& plays) {
    std::string text;
    for (const Play& play : plays) {
        if (!text.empty()) text += ' ';
        text += seat_name(play.seat) + " " + card_text(play.card);
    }
    return text;
}

struct LogLine {
    int level;
    std::string text;
};

struct HandRecord {
    int number;
    char pass_code;
    std::array<int, 4> points;
    std::optional<int> shooter;
    std::vector<std::string> record;
};

struct Round {
    std::array<CardSet, 4> hands;
    std::array<CardSet, 4> taken;
    std::vector<Trick> tricks;
    std::array<int, 4> trick_counts{};
    Trick current;
    int leader = 0;
    bool broken = false;
    std::vector<std::string> record;
};

struct Snapshot {
    Round round;
    std::size_t log_length;
    Play play;
};

struct Game {
    Game(const Rules& rules, const std::array<Strategy, 4>& bots, Generator generator)
        : rules(rules), bots(bots), generator(generator) {}

    const Rules& rules;
    const std::array<Strategy, 4>& bots;
    Generator generator;
    State state = State::Between;
    int number = 0;
    char pass_code = 'L';
    std::array<int, 4> scores{};
    std::array<Stats, 4> stats{};
    std::map<int, CardSet> stacked;
    std::map<int, CardSet> passes;
    Round round;
    std::vector<Snapshot> undo_stack;
    std::vector<HandRecord> history;
    std::vector<LogLine> log;

    int point(int card) const {
        if (card == QS) return 13;
        if (card / 13 == 3) return 1;
        return card == JD && rules.jack ? -10 : 0;
    }

    int points(const CardSet& cards) const {
        int sum = 0;
        for (int card : cards) sum += point(card);
        return sum;
    }

    int trick_points(const Trick& plays) const {
        int sum = 0;
        for (const Play& play : plays) sum += point(play.card);
        return sum;
    }

    void write(int level, const std::string& line) {
        log.push_back({level, line});
        if (level > 0) round.record.push_back(line);
    }

    void deal() {
        ++number;
        pass_code = rules.pass[(number - 1) % rules.pass.size()];
        round = Round();
        CardSet used;
        std::vector<int> free;
        for (int seat = 0; seat < 4; ++seat) {
            auto found = stacked.find(seat);
            if (found == stacked.end()) {
                free.push_back(seat);
            } else {
                round.hands[seat] = found->second;
                used.insert(found->second.begin(), found->second.end());
            }
        }
        std::vector<int> deck;
        for (int card = 0; card < 52; ++card) {
            if (!used.count(card)) deck.push_back(card);
        }
        generator.shuffle(deck);
        for (std::size_t i = 0; i < deck.size(); ++i) {
            round.hands[free[i % free.size()]].insert(deck[i]);
        }
        stacked.clear();
        passes.clear();
        undo_stack.clear();
        write(1, "hand " + std::to_string(number) + " pass " + direction_name(pass_code));
        for (int seat = 0; seat < 4; ++seat) {
            write(2, seat_name(seat) + ": " + cards_text(round.hands[seat]));
        }
        if (pass_code == 'H') {
            begin_play();
        } else {
            state = State::Passing;
        }
    }

    void begin_play() {
        state = State::Playing;
        for (int seat = 0; seat < 4; ++seat) {
            if (round.hands[seat].count(TWO_OF_CLUBS)) round.leader = seat;
        }
        write(2, "lead " + seat_name(round.leader));
    }

    void pass_cards(int seat, const CardSet& cards) {
        for (int card : cards) round.hands[seat].erase(card);
        passes[seat] = cards;
        write(2, seat_name(seat) + " passes " + cards_text(cards));
        if (passes.size() == 4) {
            int offset = pass_code == 'L' ? 1 : pass_code == 'R' ? 3 : 2;
            for (const auto& [source, passed] : passes) {
                round.hands[(source + offset) % 4].insert(passed.begin(), passed.end());
            }
            begin_play();
        }
    }

    int actor() const { return (round.leader + static_cast<int>(round.current.size())) % 4; }

    CardSet legal() const {
        const CardSet& hand = round.hands[actor()];
        if (round.current.empty()) {
            if (round.tricks.empty()) return {TWO_OF_CLUBS};
            CardSet non_hearts = filter_cards(hand, [](int card) { return card / 13 != 3; });
            return !round.broken && !non_hearts.empty() ? non_hearts : hand;
        }
        int suit = round.current[0].card / 13;
        CardSet followers = filter_cards(hand, [suit](int card) { return card / 13 == suit; });
        if (!followers.empty()) return followers;
        if (round.tricks.empty() && !rules.blood) {
            CardSet safe = filter_cards(hand, [](int card) { return !penalty(card); });
            if (!safe.empty()) return safe;
        }
        return hand;
    }

    CardSet choose_pass(int seat) const {
        const CardSet& hand = round.hands[seat];
        std::vector<int> low = sorted_cards(hand, by_rank);
        std::vector<int> high = sorted_cards(hand, by_rank_descending);
        std::vector<int> hearts;
        std::copy_if(high.begin(), high.end(), std::back_inserter(hearts),
                     [](int card) { return card / 13 == 3; });
        std::vector<int> special;
        for (int card : {QS, KS, AS}) {
            if (hand.count(card)) special.push_back(card);
        }
        std::vector<int> order;
        switch (bots[seat]) {
        case Strategy::Low:
            order = high;
            break;
        case Strategy::High:
            order = low;
            break;
        case Strategy::Moon:
            std::copy_if(low.begin(), low.end(), std::back_inserter(order),
                         [](int card) { return card / 13 != 3; });
            std::copy_if(low.begin(), low.end(), std::back_inserter(order),
                         [](int card) { return card / 13 == 3; });
            break;
        case Strategy::Smart: {
            bool is_protected = hand.count(QS) && count_suit(hand, 2) >= 5;
            if (!is_protected) order = special;
            int clubs = count_suit(hand, 0);
            int diamonds = count_suit(hand, 1);
            if (clubs > 0 || diamonds > 0) {
                int suit = diamonds > 0 && (clubs == 0 || diamonds < clubs) ? 1 : 0;
                std::copy_if(high.begin(), high.end(), std::back_inserter(order),
                             [suit](int card) { return card / 13 == suit; });
            }
            order.insert(order.end(), hearts.begin(), hearts.end());
            order.insert(order.end(), high.begin(), high.end());
            break;
        }
        case Strategy::Basic:
            order = special;
            order.insert(order.end(), hearts.begin(), hearts.end());
            order.insert(order.end(), high.begin(), high.end());
            break;
        }
        CardSet chosen;
        for (int card : order) {
            if (chosen.size() == 3) break;
            chosen.insert(card);
        }
        return chosen;
    }

    bool queen_played() const {
        for (const CardSet& cards : round.taken) {
            if (cards.count(QS)) return true;
        }
        return std::any_of(round.current.begin(), round.current.end(),
                           [](const Play& play) { return play.card == QS; });
    }

    bool others_took_penalty(int seat) const {
        for (int other = 0; other < 4; ++other) {
            const CardSet& cards = round.taken[other];
            if (other != seat && std::any_of(cards.begin(), cards.end(), penalty)) return true;
        }
        return false;
    }

    int choose_play() const {
        int seat = actor();
        const CardSet& hand = round.hands[seat];
        CardSet playable = legal();
        Strategy strategy = bots[seat];
        if (strategy == Strategy::Low) return lowest(playable);
        if (strategy == Strategy::High) return highest(playable);
        if (strategy == Strategy::Moon && others_took_penalty(seat)) strategy = Strategy::Basic;
        if (round.current.empty()) {
            if (strategy == Strategy::Smart && !queen_played() && !hand.count(QS)) {
                CardSet small_spades = filter_cards(
                    playable, [](int card) { return card / 13 == 2 && card % 13 < 10; });
                if (!small_spades.empty()) return lowest(small_spades);
            }
            int chosen_suit = -1;
            int chosen_count = 0;
            for (int suit = 0; suit < 4; ++suit) {
                int count = count_suit(playable, suit);
                if (count == 0) continue;
                bool better =
                    strategy == Strategy::Moon ? count > chosen_count : count < chosen_count;
                if (chosen_suit < 0 || better) {
                    chosen_suit = suit;
                    chosen_count = count;
                }
            }
            CardSet suited = filter_cards(
                playable, [chosen_suit](int card) { return card / 13 == chosen_suit; });
            return strategy == Strategy::Moon ? highest(suited) : lowest(suited);
        }
        int led = round.current[0].card / 13;
        if (count_suit(hand, led) > 0) {
            int winning = 0;
            for (const Play& play : round.current) {
                if (play.card / 13 == led) winning = std::max(winning, play.card % 13);
            }
            if (strategy == Strategy::Moon) {
                int high = highest(playable);
                return high % 13 > winning ? high : lowest(playable);
            }
            CardSet lower =
                filter_cards(playable, [winning](int card) { return card % 13 < winning; });
            if (!lower.empty()) return highest(lower);
            if (strategy == Strategy::Smart && round.current.size() == 3) {
                CardSet without_queen = playable;
                without_queen.erase(QS);
                return without_queen.empty() ? QS : highest(without_queen);
            }
            return lowest(playable);
        }
        if (strategy == Strategy::Moon) {
            CardSet safe = filter_cards(playable, [](int card) { return !penalty(card); });
            return lowest(safe.empty() ? playable : safe);
        }
        if (playable.count(QS)) return QS;
        if (strategy == Strategy::Smart && !queen_played()) {
            if (playable.count(AS)) return AS;
            if (playable.count(KS)) return KS;
        }
        CardSet hearts = filter_cards(playable, [](int card) { return card / 13 == 3; });
        return highest(hearts.empty() ? playable : hearts);
    }

    std::string trick_line(const Trick& plays, std::size_t number) const {
        return "trick " + std::to_string(number) + ": " + plays_text(plays) + " -> " +
               seat_name(trick_winner(plays)) + " " + std::to_string(trick_points(plays));
    }

    void play(int card) {
        int seat = actor();
        undo_stack.push_back({round, log.size(), {seat, card}});
        round.hands[seat].erase(card);
        round.current.push_back({seat, card});
        if (card / 13 == 3 || (card == QS && rules.qs_break)) round.broken = true;
        if (round.current.size() == 4) {
            int winner = trick_winner(round.current);
            for (const Play& played : round.current) round.taken[winner].insert(played.card);
            ++round.trick_counts[winner];
            round.tricks.push_back(round.current);
            write(2, trick_line(round.current, round.tricks.size()));
            round.current.clear();
            round.leader = winner;
            if (round.tricks.size() == 13) finish_hand();
        }
    }

    Play undo_card() {
        Snapshot snapshot = undo_stack.back();
        undo_stack.pop_back();
        round = snapshot.round;
        log.resize(snapshot.log_length);
        return snapshot.play;
    }

    void claim(int seat) {
        CardSet remaining;
        for (CardSet& hand : round.hands) {
            remaining.insert(hand.begin(), hand.end());
            hand.clear();
        }
        int count = 13 - static_cast<int>(round.tricks.size());
        round.taken[seat].insert(remaining.begin(), remaining.end());
        round.trick_counts[seat] += count;
        write(2, "claim " + seat_name(seat) + " tricks " + std::to_string(count) + " points " +
                     std::to_string(points(remaining)));
        finish_hand();
    }

    bool game_over(const std::array<int, 4>& totals) const {
        return number >= rules.limit ||
               *std::max_element(totals.begin(), totals.end()) >= rules.target;
    }

    void finish_hand() {
        std::array<int, 4> hand_points{};
        std::optional<int> shooter;
        for (int seat = 0; seat < 4; ++seat) {
            const CardSet& cards = round.taken[seat];
            hand_points[seat] = points(cards);
            if (std::count_if(cards.begin(), cards.end(), penalty) == 14) shooter = seat;
        }
        if (shooter) {
            int moon_seat = *shooter;
            hand_points[moon_seat] -= 26;
            std::string method = rules.moon;
            if (method == "AUTO") {
                std::array<int, 4> added{};
                for (int seat = 0; seat < 4; ++seat) {
                    added[seat] = scores[seat] + hand_points[seat] + (seat == moon_seat ? 0 : 26);
                }
                method = game_over(added) && ranking(added)[0] != moon_seat ? "SUB" : "ADD";
            }
            if (method == "SUB") {
                hand_points[moon_seat] -= 26;
            } else {
                for (int seat = 0; seat < 4; ++seat) {
                    if (seat != moon_seat) hand_points[seat] += 26;
                }
            }
            write(1, "moon " + seat_name(moon_seat) + " " + method);
        }
        for (int seat = 0; seat < 4; ++seat) {
            const CardSet& cards = round.taken[seat];
            scores[seat] += hand_points[seat];
            stats[seat] += Stats{round.trick_counts[seat], count_suit(cards, 3),
                                 static_cast<int>(cards.count(QS)), shooter == seat ? 1 : 0};
        }
        write(1, pairs("points", hand_points));
        write(1, pairs("scores", scores));
        history.push_back({number, pass_code, hand_points, shooter, round.record});
        bool over = game_over(scores);
        state = over ? State::None : State::Between;
        if (over) {
            write(0, "game over hands " + std::to_string(number));
            std::array<int, 4> order = ranking(scores);
            for (int place = 0; place < 4; ++place) {
                int seat = order[place];
                write(0, "rank " + std::to_string(place + 1) + " " + seat_name(seat) + " " +
                             std::to_string(scores[seat]));
            }
            for (const std::string& line : stats_lines()) write(0, line);
        }
    }

    std::vector<std::string> stats_lines() const {
        std::vector<std::string> lines;
        for (int seat = 0; seat < 4; ++seat) {
            lines.push_back("stats " + seat_name(seat) + " " + stats[seat].text());
        }
        return lines;
    }

    void auto_pass() {
        for (int seat = 0; seat < 4; ++seat) {
            if (!passes.count(seat)) pass_cards(seat, choose_pass(seat));
        }
    }

    void auto_hand() {
        if (state == State::Passing) auto_pass();
        while (state == State::Playing) play(choose_play());
    }

    void auto_game() {
        if (state == State::Passing || state == State::Playing) auto_hand();
        while (state != State::None) {
            deal();
            auto_hand();
        }
    }
};

CardSet distinct_cards(const std::vector<int>& cards) {
    CardSet seen;
    for (int card : cards) {
        if (!seen.insert(card).second) fail("duplicate card " + card_text(card));
    }
    return seen;
}

std::string average_text(long long total, int games) {
    long long numerator = 100 * total;
    long long cents = numerator / games;
    if (numerator % games != 0 && numerator < 0) --cents;
    std::ostringstream out;
    if (cents < 0) out << '-';
    out << std::llabs(cents) / 100 << '.' << std::setw(2) << std::setfill('0')
        << std::llabs(cents) % 100;
    return out.str();
}

class Table {
public:
    std::vector<std::string> command(const std::vector<std::string>& words);

private:
    Rules rules;
    std::array<Strategy, 4> bots = {Strategy::Basic, Strategy::Basic, Strategy::Basic,
                                    Strategy::Basic};
    std::optional<Game> game;

    bool active() const { return game && game->state != State::None; }

    void require_game() const {
        if (!active()) fail("no game");
    }

    void require_hand() const {
        if (!active() || (game->state != State::Passing && game->state != State::Playing)) {
            fail("no hand");
        }
    }

    void require_playing() const {
        if (!active() || game->state != State::Playing) fail("not playing");
    }

    void require_passing() const {
        if (!active() || game->state != State::Passing) fail("not passing");
    }

    void require_between() const {
        require_game();
        if (game->state != State::Between) fail("hand in progress");
    }

    std::vector<std::string> simulate(const std::string& name, int seed, int count) const;
};

std::vector<std::string> Table::simulate(const std::string& name, int seed, int count) const {
    Generator generator(seed);
    if (name == "GAME") {
        Game simulated(rules, bots, generator);
        simulated.auto_game();
        std::vector<std::string> output = {"game seed " + std::to_string(seed)};
        for (const LogLine& line : simulated.log) {
            if (line.level <= count) output.push_back(line.text);
        }
        return output;
    }
    int rounds = name == "ROTATE" ? 4 : 1;
    std::array<std::array<int, 4>, 4> places{};
    std::array<long long, 4> totals{};
    std::array<Stats, 4> stats{};
    int hands = 0;
    for (int rotation = 0; rotation < rounds; ++rotation) {
        std::array<Strategy, 4> strategies{};
        for (int seat = 0; seat < 4; ++seat) strategies[(seat + rotation) % 4] = bots[seat];
        for (int i = 0; i < count; ++i) {
            Game simulated(rules, strategies, generator);
            simulated.auto_game();
            generator = simulated.generator;
            hands += simulated.number;
            std::array<int, 4> order = ranking(simulated.scores);
            for (int original = 0; original < 4; ++original) {
                int actual = (original + rotation) % 4;
                ++places[original][std::find(order.begin(), order.end(), actual) - order.begin()];
                totals[original] += simulated.scores[actual];
                stats[original] += simulated.stats[actual];
            }
        }
    }
    int games = rounds * count;
    std::string label = name == "ROTATE" ? "rotate" : "match";
    std::vector<std::string> output = {label + " seed " + std::to_string(seed) + " games " +
                                       std::to_string(games) + " hands " + std::to_string(hands)};
    for (int seat = 0; seat < 4; ++seat) {
        std::ostringstream line;
        line << SEATS[seat];
        if (name == "ROTATE") line << ' ' << strategy_name(bots[seat]);
        line << " places";
        for (int place : places[seat]) line << ' ' << place;
        line << " total " << totals[seat] << " average " << average_text(totals[seat], games) << ' '
             << stats[seat].text();
        output.push_back(line.str());
    }
    return output;
}

std::vector<std::string> Table::command(const std::vector<std::string>& words) {
    const std::string& name = words[0];
    std::vector<std::string> args(words.begin() + 1, words.end());
    if (!one_of(name, {"RULE", "BOT", "SETTINGS", "GAME", "MATCH", "ROTATE", "NEW", "ABANDON",
                       "STACK", "DEAL", "SHOW", "PASS", "PLAY", "AUTO", "UNDO", "CLAIM", "LEGAL",
                       "PREVIEW", "SCORE", "TAKEN", "TRICKS", "VOIDS", "UNSEEN", "STATS",
                       "HISTORY", "REPLAY"})) {
        fail("unknown command " + name);
    }
    if (name == "RULE") {
        Rules changed = rules.with(args[0], args[1]);
        if (active()) fail("game in progress");
        rules = changed;
        return {"rule " + args[0] + " " + args[1]};
    }
    if (name == "BOT") {
        int seat = seat_value(args[0]);
        bots[seat] = strategy_value(args[1]);
        return {"bot " + seat_name(seat) + " " + args[1]};
    }
    if (name == "SETTINGS") {
        std::array<std::string, 4> names;
        for (int seat = 0; seat < 4; ++seat) names[seat] = strategy_name(bots[seat]);
        return {rules.text(), pairs("bots", names)};
    }
    if (name == "GAME" || name == "MATCH" || name == "ROTATE") {
        int seed = bounded(args[0], 1, 2147483646);
        int count = name == "GAME"    ? bounded(args[1], 0, 2)
                    : name == "MATCH" ? bounded(args[1], 1, 50)
                                      : bounded(args[1], 1, 10);
        return simulate(name, seed, count);
    }
    if (name == "NEW") {
        int seed = bounded(args[0], 1, 2147483646);
        if (active()) fail("game in progress");
        game.emplace(rules, bots, Generator(seed));
        return {"new game seed " + std::to_string(seed)};
    }
    if (name == "ABANDON") {
        require_game();
        game.reset();
        return {"game abandoned"};
    }

    int seat = -1;
    std::vector<int> cards;
    if (one_of(name, {"STACK", "PASS", "PLAY", "CLAIM"})) seat = seat_value(args[0]);
    if (one_of(name, {"STACK", "PASS", "PLAY"})) {
        for (std::size_t i = 1; i < args.size(); ++i) cards.push_back(card_value(args[i]));
    }
    if (name == "STACK" && cards.size() != 13) fail("need 13 cards");
    if (name == "AUTO" && !one_of(args[0], {"PASS", "CARD", "TRICK", "HAND", "GAME"})) {
        fail("bad value " + args[0]);
    }

    if (name == "STACK" || name == "DEAL") {
        require_between();
    } else if (name == "SHOW") {
        require_hand();
    } else if (name == "PASS") {
        require_passing();
    } else if (one_of(name, {"PLAY", "UNDO", "CLAIM", "LEGAL", "PREVIEW", "TAKEN", "TRICKS",
                             "VOIDS", "UNSEEN"})) {
        require_playing();
    } else if (one_of(name, {"SCORE", "STATS", "HISTORY", "REPLAY"})) {
        require_game();
    } else if (name == "AUTO") {
        const std::string& mode = args[0];
        if (mode == "PASS") {
            require_passing();
        } else if (mode == "CARD" || mode == "TRICK") {
            require_playing();
        } else if (mode == "HAND") {
            require_hand();
        } else {
            require_game();
        }
    }
    Game& current = *game;
    Round& round = current.round;
    std::size_t before = current.log.size();
    std::vector<std::string> output;
    if (name == "STACK") {
        CardSet stacked = distinct_cards(cards);
        for (int card : cards) {
            for (const auto& [other, held] : current.stacked) {
                if (other != seat && held.count(card)) {
                    fail(card_text(card) + " stacked for " + seat_name(other));
                }
            }
        }
        current.stacked[seat] = stacked;
        return {"stacked " + seat_name(seat)};
    }
    if (name == "DEAL") {
        current.deal();
    } else if (name == "SHOW") {
        for (int other = 0; other < 4; ++other) {
            output.push_back(seat_name(other) + ": " + cards_text(round.hands[other]));
        }
        return output;
    } else if (name == "PASS") {
        if (current.passes.count(seat)) fail(seat_name(seat) + " already passed");
        CardSet chosen = distinct_cards(cards);
        for (int card : cards) {
            if (!round.hands[seat].count(card)) {
                fail(seat_name(seat) + " does not hold " + card_text(card));
            }
        }
        current.pass_cards(seat, chosen);
    } else if (name == "PLAY") {
        int card = cards[0];
        if (seat != current.actor()) fail("waiting for " + seat_name(current.actor()));
        if (!round.hands[seat].count(card)) {
            fail(seat_name(seat) + " does not hold " + card_text(card));
        }
        if (!current.legal().count(card)) {
            if (round.current.empty()) {
                fail(round.tricks.empty() ? "must lead 2C" : "hearts not broken");
            }
            int led = round.current[0].card / 13;
            if (count_suit(round.hands[seat], led) > 0) {
                fail(std::string("must follow ") + SUITS[led]);
            }
            fail("no points on first trick");
        }
        output.push_back(seat_name(seat) + " plays " + card_text(card));
        current.play(card);
    } else if (name == "AUTO") {
        const std::string& mode = args[0];
        if (mode == "PASS") {
            current.auto_pass();
        } else if (mode == "CARD") {
            int actor = current.actor();
            int card = current.choose_play();
            output.push_back(seat_name(actor) + " plays " + card_text(card));
            current.play(card);
        } else if (mode == "TRICK") {
            std::size_t count = round.tricks.size();
            while (current.state == State::Playing && round.tricks.size() == count) {
                current.play(current.choose_play());
            }
        } else if (mode == "HAND") {
            current.auto_hand();
        } else {
            current.auto_game();
        }
    } else if (name == "UNDO") {
        if (current.undo_stack.empty()) fail("nothing to undo");
        Play undone = current.undo_card();
        return {"undo " + seat_name(undone.seat) + " " + card_text(undone.card)};
    } else if (name == "CLAIM") {
        if (seat != current.actor()) fail("waiting for " + seat_name(current.actor()));
        if (!round.current.empty()) fail("trick in progress");
        for (int card : round.hands[seat]) {
            for (int other = 0; other < 4; ++other) {
                if (other == seat) continue;
                for (int other_card : round.hands[other]) {
                    if (other_card / 13 == card / 13 && other_card % 13 > card % 13) {
                        fail("claim rejected");
                    }
                }
            }
        }
        current.claim(seat);
    } else if (name == "LEGAL") {
        return {"legal " + seat_name(current.actor()) + ": " + cards_text(current.legal()) +
                " bot " + card_text(current.choose_play())};
    } else if (name == "PREVIEW") {
        for (int card : current.legal()) {
            Game copy = current;
            std::size_t count = copy.round.tricks.size();
            copy.play(card);
            while (copy.state == State::Playing && copy.round.tricks.size() == count) {
                copy.play(copy.choose_play());
            }
            const Trick& trick = copy.round.tricks.back();
            output.push_back("preview " + card_text(card) + " -> " +
                             seat_name(trick_winner(trick)) + " " +
                             std::to_string(copy.trick_points(trick)));
        }
        return output;
    } else if (name == "SCORE") {
        output.push_back(pairs("scores", current.scores));
        if (current.state == State::Playing) {
            std::array<int, 4> taken{};
            for (int other = 0; other < 4; ++other) {
                taken[other] = current.points(round.taken[other]);
            }
            output.push_back(pairs("taken", taken));
        }
        return output;
    } else if (name == "TAKEN") {
        for (int other = 0; other < 4; ++other) {
            CardSet scoring = filter_cards(
                round.taken[other], [&current](int card) { return current.point(card) != 0; });
            output.push_back(seat_name(other) + ": " + cards_text(scoring));
        }
        return output;
    } else if (name == "TRICKS") {
        for (std::size_t i = 0; i < round.tricks.size(); ++i) {
            output.push_back(current.trick_line(round.tricks[i], i + 1));
        }
        if (!round.current.empty()) output.push_back("current: " + plays_text(round.current));
        if (output.empty()) output.push_back("no tricks");
        return output;
    } else if (name == "VOIDS") {
        std::vector<Trick> tricks = round.tricks;
        if (!round.current.empty()) tricks.push_back(round.current);
        std::array<std::set<int>, 4> voids;
        for (const Trick& trick : tricks) {
            int led = trick[0].card / 13;
            for (const Play& play : trick) {
                if (play.card / 13 != led) voids[play.seat].insert(led);
            }
        }
        std::array<std::string, 4> texts;
        for (int other = 0; other < 4; ++other) {
            for (int suit : voids[other]) texts[other] += SUITS[suit];
            if (texts[other].empty()) texts[other] = "-";
        }
        return {pairs("voids", texts)};
    } else if (name == "UNSEEN") {
        int actor = current.actor();
        CardSet seen = round.hands[actor];
        for (const CardSet& taken : round.taken) seen.insert(taken.begin(), taken.end());
        for (const Play& play : round.current) seen.insert(play.card);
        CardSet unseen;
        for (int card = 0; card < 52; ++card) {
            if (!seen.count(card)) unseen.insert(card);
        }
        return {"unseen " + seat_name(actor) + ": " + cards_text(unseen)};
    } else if (name == "STATS") {
        return current.stats_lines();
    } else if (name == "HISTORY") {
        for (const HandRecord& hand : current.history) {
            std::string line = "hand " + std::to_string(hand.number) + " pass " +
                               direction_name(hand.pass_code) + " " + pairs("points", hand.points);
            if (hand.shooter) line += " moon " + seat_name(*hand.shooter);
            output.push_back(line);
        }
        if (output.empty()) output.push_back("no hands");
        return output;
    } else if (name == "REPLAY") {
        int hand = bounded(args[0], 1, static_cast<int>(current.history.size()));
        return current.history[hand - 1].record;
    }
    for (std::size_t i = before; i < current.log.size(); ++i) output.push_back(current.log[i].text);
    return output;
}

std::vector<std::string> split(const std::string& line) {
    std::vector<std::string> words;
    std::istringstream in(line);
    std::string word;
    while (in >> word) words.push_back(word);
    return words;
}

int main() {
    std::string line;
    std::getline(std::cin, line);
    int count = std::stoi(line);
    Table table;
    for (int i = 0; i < count && std::getline(std::cin, line); ++i) {
        try {
            for (const std::string& text : table.command(split(line))) std::cout << text << '\n';
        } catch (const CommandError& error) {
            std::cout << "error: " << error.what() << '\n';
        }
    }
    return 0;
}
