#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <initializer_list>
#include <iostream>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

using Money = std::int64_t;
using Card = int;

class CommandError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

[[noreturn]] void fail(const std::string& reason) { throw CommandError(reason); }

bool one_of(std::string_view word, std::initializer_list<std::string_view> choices) {
    return std::find(choices.begin(), choices.end(), word) != choices.end();
}

std::int64_t integer(const std::string& word, std::int64_t minimum, std::int64_t maximum) {
    if (word.empty() || word.size() > 10 || (word.size() > 1 && word.front() == '0'))
        fail("bad value " + word);
    std::int64_t value = 0;
    for (char ch : word) {
        if (ch < '0' || ch > '9') fail("bad value " + word);
        value = value * 10 + ch - '0';
    }
    if (value < minimum || value > maximum) fail("bad value " + word);
    return value;
}

std::string signed_number(Money value) {
    return (value >= 0 ? "+" : "") + std::to_string(value);
}

int rank(Card card) { return card % 13; }
int suit(Card card) { return card / 13; }
int points(Card card) { return std::min(rank(card) + 1, 10); }
bool black(Card card) { return suit(card) == 0 || suit(card) == 3; }

std::string card_text(Card card) {
    return std::string(1, "A23456789TJQK"[rank(card)]) + "CDHS"[suit(card)];
}

struct Total { int value; bool soft; };

Total total(const std::vector<Card>& cards) {
    int sum = 0;
    bool ace = false;
    for (Card card : cards) {
        sum += points(card);
        ace = ace || rank(card) == 0;
    }
    const bool soft = ace && sum + 10 <= 21;
    return {sum + (soft ? 10 : 0), soft};
}

bool blackjack(const std::vector<Card>& cards, bool split = false) {
    return !split && cards.size() == 2 && total(cards).value == 21;
}

std::string hand_text(const std::vector<Card>& cards, bool split = false) {
    const Total t = total(cards);
    std::ostringstream out;
    for (std::size_t i = 0; i < cards.size(); ++i) {
        if (i) out << ' ';
        out << card_text(cards[i]);
    }
    out << " (";
    if (blackjack(cards, split)) out << "blackjack";
    else {
        if (t.value > 21) out << "bust ";
        else if (t.soft) out << "soft ";
        out << t.value;
    }
    out << ')';
    return out.str();
}

enum class Phase { Idle, Insurance, Play };
enum class Finish { None, Bust, Surrender, Charlie };
enum class Action { Hit, Stand, Double, Split, Surrender };
enum class DoubleRule { Any, Hard9, Hard10 };
enum class Result { Blackjack, Win, Charlie, Push, Lose, Bust, Surrender };

std::optional<Action> parse_action(const std::string& word) {
    if (word == "HIT") return Action::Hit;
    if (word == "STAND") return Action::Stand;
    if (word == "DOUBLE") return Action::Double;
    if (word == "SPLIT") return Action::Split;
    if (word == "SURRENDER") return Action::Surrender;
    return std::nullopt;
}

std::string action_name(Action action) {
    static const std::array<std::string, 5> names{"hit", "stand", "double", "split", "surrender"};
    return names[static_cast<std::size_t>(action)];
}

std::string result_name(Result result) {
    static const std::array<std::string, 7> names{
        "blackjack", "win", "charlie", "push", "lose", "bust", "surrender"
    };
    return names[static_cast<std::size_t>(result)];
}

struct Rules {
    bool hit_soft17 = false;
    int penetration = 75;
    int minimum = 10;
    int maximum = 500;
    bool six_to_five = false;
    bool double_after_split = true;
    DoubleRule doubling = DoubleRule::Any;
    int hands = 4;
    bool resplit_aces = false;
    bool surrender = true;
    int charlie = 0;
    int side_maximum = 25;

    Rules changed(const std::string& name, const std::string& word) const {
        Rules next = *this;
        auto choice = [&](std::initializer_list<std::string_view> allowed) {
            if (!one_of(word, allowed)) fail("bad value " + word);
        };
        if (name == "DEALER") {
            choice({"S17", "H17"});
            next.hit_soft17 = word == "H17";
        } else if (name == "PEN") next.penetration = static_cast<int>(integer(word, 50, 90));
        else if (name == "MIN") next.minimum = static_cast<int>(integer(word, 1, 10000));
        else if (name == "MAX") next.maximum = static_cast<int>(integer(word, 1, 10000));
        else if (name == "BJ") {
            choice({"3:2", "6:5"});
            next.six_to_five = word == "6:5";
        } else if (name == "DAS") {
            choice({"ON", "OFF"});
            next.double_after_split = word == "ON";
        } else if (name == "DOUBLE") {
            choice({"ANY", "9-11", "10-11"});
            next.doubling = word == "ANY" ? DoubleRule::Any
                : word == "9-11" ? DoubleRule::Hard9 : DoubleRule::Hard10;
        } else if (name == "HANDS") next.hands = static_cast<int>(integer(word, 1, 4));
        else if (name == "RSA") {
            choice({"ON", "OFF"});
            next.resplit_aces = word == "ON";
        } else if (name == "SURRENDER") {
            choice({"ON", "OFF"});
            next.surrender = word == "ON";
        } else if (name == "CHARLIE") {
            choice({"0", "5", "6", "7"});
            next.charlie = word.front() - '0';
        } else if (name == "SIDEMAX") next.side_maximum = static_cast<int>(integer(word, 0, 1000));
        else fail("unknown rule " + name);
        return next;
    }

    std::string text() const {
        auto on = [](bool value) { return value ? "ON" : "OFF"; };
        std::ostringstream out;
        out << "rules DEALER " << (hit_soft17 ? "H17" : "S17")
            << " PEN " << penetration << " MIN " << minimum << " MAX " << maximum
            << " BJ " << (six_to_five ? "6:5" : "3:2") << " DAS " << on(double_after_split)
            << " DOUBLE " << (doubling == DoubleRule::Any ? "ANY" : doubling == DoubleRule::Hard9 ? "9-11" : "10-11")
            << " HANDS " << hands << " RSA " << on(resplit_aces) << " SURRENDER " << on(surrender)
            << " CHARLIE " << charlie << " SIDEMAX " << side_maximum;
        return out.str();
    }
};

struct Hand {
    std::vector<Card> cards;
    Money bet;
    bool split = false;
    bool split_aces = false;
    bool finished = false;
    Finish reason = Finish::None;
};

struct Statistics {
    int rounds = 0, hands = 0, wins = 0, losses = 0, pushes = 0;
    int blackjacks = 0, busts = 0, surrenders = 0, doubles = 0, splits = 0;
};

struct Player {
    std::string name;
    int seat;
    Money bankroll;
    Money bet = 0, side = 0, insurance = 0, net = 0;
    Statistics stats;
    std::vector<Hand> hands;

    std::string hand_name(std::size_t index) const {
        return name + "[" + std::to_string(index + 1) + "]";
    }
};

struct Turn { int seat; std::size_t hand; };

class Table {
    Rules rules;
    std::array<std::optional<Player>, 7> seats;
    std::vector<int> participants;
    Phase phase = Phase::Idle;
    int round = 0, dealer_blackjacks = 0, dealer_busts = 0;
    int decks = 0, drawn = 0, running = 0;
    std::int64_t random = 1;
    std::vector<Card> shoe, dealer;
    bool hole_revealed = false;
    std::size_t insurance_turn = 0;

    int find_player(const std::string& name) const {
        for (int i = 0; i < 7; ++i)
            if (seats[i] && seats[i]->name == name) return i;
        return -1;
    }

    int cut() const { return static_cast<int>(shoe.size()) * rules.penetration / 100; }

    void shuffle() {
        shoe.resize(52 * decks);
        for (std::size_t i = 0; i < shoe.size(); ++i) shoe[i] = static_cast<int>(i % 52);
        for (int i = static_cast<int>(shoe.size()) - 1; i >= 1; --i) {
            random = random * 48271 % 2147483647;
            std::swap(shoe[i], shoe[static_cast<std::size_t>(random % (i + 1))]);
        }
        drawn = running = 0;
    }

    void count_card(Card card) {
        const int value = points(card);
        running += value >= 2 && value <= 6 ? 1 : value == 1 || value == 10 ? -1 : 0;
    }

    Card draw(bool face_up = true) {
        const Card card = shoe[drawn++];
        if (face_up) count_card(card);
        return card;
    }

    void reveal_dealer() {
        if (!hole_revealed) {
            count_card(dealer[1]);
            hole_revealed = true;
        }
        std::cout << "dealer: " << hand_text(dealer) << '\n';
    }

    std::optional<Turn> current() const {
        for (int seat : participants) {
            const auto& hands = seats[seat]->hands;
            for (std::size_t i = 0; i < hands.size(); ++i)
                if (!hands[i].finished) return Turn{seat, i};
        }
        return std::nullopt;
    }

    void finish_check(Player& player, Hand& hand) const {
        const int value = total(hand.cards).value;
        if (value > 21) {
            hand.reason = Finish::Bust;
            hand.finished = true;
        } else if (rules.charlie != 0 && hand.cards.size() == static_cast<std::size_t>(rules.charlie)) {
            hand.reason = Finish::Charlie;
            hand.finished = true;
        } else if (value == 21) hand.finished = true;
        else if (hand.split_aces && hand.cards.size() == 2) {
            hand.finished = !(rank(hand.cards[0]) == 0 && rank(hand.cards[1]) == 0
                && rules.resplit_aces && player.hands.size() < static_cast<std::size_t>(rules.hands));
        }
    }

    void settle(bool dealer_natural = false) {
        const int dealer_total = total(dealer).value;
        for (int seat : participants) {
            Player& player = *seats[seat];
            for (std::size_t i = 0; i < player.hands.size(); ++i) {
                const Hand& hand = player.hands[i];
                const bool natural = blackjack(hand.cards, hand.split);
                Result result;
                if (dealer_natural) result = natural ? Result::Push : Result::Lose;
                else if (natural) result = Result::Blackjack;
                else if (hand.reason == Finish::Bust) result = Result::Bust;
                else if (hand.reason == Finish::Surrender) result = Result::Surrender;
                else if (hand.reason == Finish::Charlie) result = Result::Charlie;
                else {
                    const int value = total(hand.cards).value;
                    result = dealer_total > 21 || value > dealer_total ? Result::Win
                        : value == dealer_total ? Result::Push : Result::Lose;
                }
                Money profit;
                if (result == Result::Blackjack)
                    profit = rules.six_to_five ? hand.bet * 6 / 5 : hand.bet * 3 / 2;
                else if (result == Result::Win || result == Result::Charlie) profit = hand.bet;
                else if (result == Result::Push) profit = 0;
                else if (result == Result::Surrender) profit = hand.bet / 2 - hand.bet;
                else profit = -hand.bet;
                player.bankroll += hand.bet + profit;
                player.net += profit;
                ++player.stats.hands;
                if (result == Result::Blackjack || result == Result::Win || result == Result::Charlie) ++player.stats.wins;
                else if (result == Result::Push) ++player.stats.pushes;
                else ++player.stats.losses;
                if (result == Result::Blackjack) ++player.stats.blackjacks;
                if (result == Result::Bust) ++player.stats.busts;
                if (result == Result::Surrender) ++player.stats.surrenders;
                std::cout << player.hand_name(i) << ' ' << result_name(result) << ' ' << signed_number(profit) << '\n';
            }
            std::cout << player.name << " bankroll " << player.bankroll << '\n';
        }
        for (auto& player : seats) if (player) player->bet = player->side = 0;
        phase = Phase::Idle;
    }

    void dealer_turn() {
        reveal_dealer();
        bool must_play = false;
        for (int seat : participants)
            for (const Hand& hand : seats[seat]->hands)
                must_play = must_play || (hand.reason == Finish::None && !blackjack(hand.cards, hand.split));
        bool drew = false;
        if (must_play) {
            for (;;) {
                const Total t = total(dealer);
                if (!(t.value <= 16 || (t.value == 17 && t.soft && rules.hit_soft17))) break;
                dealer.push_back(draw());
                drew = true;
                std::cout << "dealer hits: " << hand_text(dealer) << '\n';
            }
        }
        if (drew && total(dealer).value > 21) ++dealer_busts;
        settle();
    }

    void advance() {
        for (;;) {
            const auto turn = current();
            if (!turn) {
                dealer_turn();
                return;
            }
            Player& player = *seats[turn->seat];
            Hand& hand = player.hands[turn->hand];
            if (hand.cards.size() != 1) return;
            hand.cards.push_back(draw());
            std::cout << player.hand_name(turn->hand) << ": " << hand_text(hand.cards, hand.split) << '\n';
            finish_check(player, hand);
            if (!hand.finished) return;
        }
    }

    void peek() {
        const bool natural = blackjack(dealer);
        std::cout << "dealer peeks: " << (natural ? "blackjack" : "no blackjack") << '\n';
        for (int seat : participants) {
            Player& player = *seats[seat];
            if (!player.insurance) continue;
            const Money profit = player.insurance * (natural ? 2 : -1);
            player.bankroll += player.insurance + profit;
            player.net += profit;
            std::cout << player.name << " insurance " << signed_number(profit) << '\n';
        }
        if (natural) {
            ++dealer_blackjacks;
            reveal_dealer();
            settle(true);
        } else {
            phase = Phase::Play;
            advance();
        }
    }

    void deal() {
        if (drawn >= cut()) {
            shuffle();
            std::cout << "shuffle\n";
        }
        std::cout << "round " << ++round << '\n';
        participants.clear();
        for (int i = 0; i < 7; ++i) if (seats[i] && seats[i]->bet) participants.push_back(i);
        for (int seat : participants) {
            Player& player = *seats[seat];
            player.bankroll -= player.bet + player.side;
            player.insurance = 0;
            ++player.stats.rounds;
            player.hands = {Hand{{draw()}, player.bet}};
        }
        dealer = {draw()};
        for (int seat : participants) {
            Hand& hand = seats[seat]->hands[0];
            hand.cards.push_back(draw());
            hand.finished = blackjack(hand.cards);
        }
        dealer.push_back(draw(false));
        hole_revealed = false;
        for (int seat : participants) {
            const Player& player = *seats[seat];
            std::cout << player.hand_name(0) << ": " << hand_text(player.hands[0].cards) << '\n';
        }
        std::cout << "dealer: " << card_text(dealer[0]) << " ??\n";
        for (int seat : participants) {
            Player& player = *seats[seat];
            if (!player.side) continue;
            const Card a = player.hands[0].cards[0], b = player.hands[0].cards[1];
            std::string result = "lose";
            int multiplier = -1;
            if (rank(a) == rank(b)) {
                if (suit(a) == suit(b)) { result = "perfect"; multiplier = 25; }
                else if (black(a) == black(b)) { result = "colored"; multiplier = 12; }
                else { result = "mixed"; multiplier = 6; }
            }
            const Money profit = player.side * multiplier;
            player.bankroll += player.side + profit;
            player.net += profit;
            std::cout << player.name << " side " << result << ' ' << signed_number(profit) << '\n';
        }
        if (points(dealer[0]) == 1) {
            phase = Phase::Insurance;
            insurance_turn = 0;
            std::cout << "insurance offered\n";
        } else if (points(dealer[0]) == 10) peek();
        else {
            phase = Phase::Play;
            advance();
        }
    }

    std::optional<std::string> action_error(Action action, const Player& player, const Hand& hand) const {
        if (action == Action::Hit) {
            if (hand.split_aces) return "split aces";
        } else if (action == Action::Double) {
            if (hand.split_aces) return "split aces";
            if (hand.cards.size() != 2) return "two cards only";
            const Total t = total(hand.cards);
            if ((rules.doubling != DoubleRule::Any
                 && (t.soft || t.value < (rules.doubling == DoubleRule::Hard9 ? 9 : 10) || t.value > 11))
                || (!rules.double_after_split && hand.split)) return "double not allowed";
            if (player.bankroll < hand.bet) return "insufficient funds";
        } else if (action == Action::Split) {
            if (hand.cards.size() != 2) return "two cards only";
            if (points(hand.cards[0]) != points(hand.cards[1])) return "not a pair";
            if (player.hands.size() >= static_cast<std::size_t>(rules.hands)) return "hand limit";
            if (player.bankroll < hand.bet) return "insufficient funds";
        } else if (action == Action::Surrender) {
            if (!rules.surrender || hand.split) return "surrender not allowed";
            if (hand.cards.size() != 2) return "two cards only";
        }
        return std::nullopt;
    }

    void perform(Action action) {
        const Turn turn = current().value();
        Player& player = *seats[turn.seat];
        const std::string name = player.hand_name(turn.hand);
        if (action == Action::Split) {
            const Hand old = player.hands[turn.hand];
            const Card first = old.cards[0], second = old.cards[1];
            const bool aces = old.split_aces || points(first) == 1;
            player.bankroll -= old.bet;
            ++player.stats.splits;
            std::cout << name << " splits " << card_text(first) << ' ' << card_text(second) << '\n';
            player.hands[turn.hand] = Hand{{first}, old.bet, true, aces};
            player.hands.insert(player.hands.begin() + static_cast<std::ptrdiff_t>(turn.hand + 1),
                                Hand{{second}, old.bet, true, aces});
            Hand& hand = player.hands[turn.hand];
            hand.cards.push_back(draw());
            std::cout << name << ": " << hand_text(hand.cards, true) << '\n';
            finish_check(player, hand);
        } else {
            Hand& hand = player.hands[turn.hand];
            if (action == Action::Stand || action == Action::Surrender) {
                hand.finished = true;
                if (action == Action::Surrender) hand.reason = Finish::Surrender;
                std::cout << name << (action == Action::Stand ? " stands: " : " surrenders: ")
                          << hand_text(hand.cards, hand.split) << '\n';
            } else {
                if (action == Action::Double) {
                    player.bankroll -= hand.bet;
                    hand.bet *= 2;
                    ++player.stats.doubles;
                }
                hand.cards.push_back(draw());
                std::cout << name << (action == Action::Double ? " doubles: " : " hits: ")
                          << hand_text(hand.cards, hand.split) << '\n';
                finish_check(player, hand);
                if (action == Action::Double) hand.finished = true;
            }
        }
        advance();
    }

    Action recommend() const {
        const Turn turn = current().value();
        const Player& player = *seats[turn.seat];
        const Hand& hand = player.hands[turn.hand];
        auto possible = [&](Action action) { return !action_error(action, player, hand); };
        const int u = points(dealer[0]) == 1 ? 11 : points(dealer[0]);
        if (hand.split_aces) return possible(Action::Split) ? Action::Split : Action::Stand;
        if (hand.cards.size() == 2 && points(hand.cards[0]) == points(hand.cards[1]) && possible(Action::Split)) {
            const int v = points(hand.cards[0]);
            if (v == 1 || v == 8 || (v == 9 && u != 7 && u != 10 && u != 11)
                || ((v == 2 || v == 3 || v == 7) && u <= 7) || (v == 6 && u <= 6)
                || (v == 4 && (u == 5 || u == 6))) return Action::Split;
        }
        const Total t = total(hand.cards);
        enum class Symbol { H, S, D, Ds, R };
        Symbol symbol = Symbol::H;
        if (t.soft) {
            if (t.value >= 19) symbol = Symbol::S;
            else if (t.value == 18)
                symbol = u >= 3 && u <= 6 ? Symbol::Ds : u == 2 || u == 7 || u == 8 ? Symbol::S : Symbol::H;
            else if ((t.value == 17 && u >= 3 && u <= 6)
                     || ((t.value == 15 || t.value == 16) && u >= 4 && u <= 6)
                     || ((t.value == 13 || t.value == 14) && (u == 5 || u == 6))) symbol = Symbol::D;
        } else {
            if (t.value >= 17) symbol = Symbol::S;
            else if (t.value >= 13)
                symbol = u <= 6 ? Symbol::S
                    : (t.value == 16 && u >= 9) || (t.value == 15 && u == 10) ? Symbol::R : Symbol::H;
            else if (t.value == 12) symbol = u >= 4 && u <= 6 ? Symbol::S : Symbol::H;
            else if ((t.value == 11 && u <= 10) || (t.value == 10 && u <= 9)
                     || (t.value == 9 && u >= 3 && u <= 6)) symbol = Symbol::D;
        }
        if (symbol == Symbol::S) return Action::Stand;
        if (symbol == Symbol::D || symbol == Symbol::Ds)
            return possible(Action::Double) ? Action::Double : symbol == Symbol::Ds ? Action::Stand : Action::Hit;
        if (symbol == Symbol::R) return possible(Action::Surrender) ? Action::Surrender : Action::Hit;
        return Action::Hit;
    }

    void status() const {
        std::cout << "table " << (phase == Phase::Idle ? "idle" : phase == Phase::Insurance ? "insurance" : "play")
                  << " round " << round;
        if (phase == Phase::Insurance) std::cout << " next " << seats[participants[insurance_turn]]->name;
        else if (phase == Phase::Play) {
            const Turn turn = current().value();
            std::cout << " turn " << seats[turn.seat]->hand_name(turn.hand);
        }
        std::cout << '\n';
        if (phase != Phase::Idle) std::cout << "dealer: " << card_text(dealer[0]) << " ??\n";
        for (int i = 0; i < 7; ++i) {
            if (!seats[i]) continue;
            const Player& player = *seats[i];
            std::cout << "seat " << player.seat << ' ' << player.name << " bankroll " << player.bankroll
                      << " bet " << player.bet << " side " << player.side << '\n';
            if (phase != Phase::Idle && std::find(participants.begin(), participants.end(), i) != participants.end()) {
                for (std::size_t h = 0; h < player.hands.size(); ++h) {
                    const Hand& hand = player.hands[h];
                    std::cout << player.hand_name(h) << ": " << hand_text(hand.cards, hand.split) << " bet " << hand.bet << '\n';
                }
            }
        }
    }

public:
    void command(const std::vector<std::string>& words) {
        const std::string& command = words[0];
        if (!one_of(command, {"SHOE", "RULE", "RULES", "PLAYER", "LEAVE", "REBUY", "BET", "SIDE", "DEAL",
                              "INSURANCE", "HIT", "STAND", "DOUBLE", "SPLIT", "SURRENDER", "HINT", "AUTO", "STATUS", "COUNT", "STATS"}))
            fail("unknown command " + command);
        const std::string first = words.size() > 1 ? words[1] : "";
        const std::string second = words.size() > 2 ? words[2] : "";
        const auto action = parse_action(command);
        int seat = -1;
        std::int64_t value = 0, seed = 0;
        std::optional<Rules> proposed_rules;

        // Argument errors precede state errors, even for commands that cannot run now.
        if (command == "SHOE") {
            value = integer(first, 1, 8);
            seed = integer(second, 1, 2147483646);
        } else if (command == "RULE") proposed_rules = rules.changed(first, second);
        else if (command == "PLAYER") {
            if (first.empty() || first.size() > 8
                || !std::all_of(first.begin(), first.end(), [](char c) { return c >= 'A' && c <= 'Z'; }))
                fail("bad name " + first);
            value = integer(second, 1, 1000000);
        } else if (action || one_of(command, {"LEAVE", "REBUY", "BET", "SIDE", "INSURANCE", "AUTO"})) {
            seat = find_player(first);
            if (seat < 0) fail("unknown player " + first);
            if (one_of(command, {"REBUY", "BET", "SIDE", "INSURANCE"}))
                value = integer(second, command == "REBUY" ? 1 : 0, 1000000);
        }
        if (one_of(command, {"SHOE", "RULE", "PLAYER", "LEAVE", "REBUY", "BET", "SIDE", "DEAL"})) {
            if (phase != Phase::Idle) fail("round in progress");
        } else if (command == "INSURANCE") {
            if (phase != Phase::Insurance) fail("no insurance");
        } else if (action || command == "AUTO" || command == "HINT") {
            if (phase == Phase::Idle) fail("no round");
            if (phase == Phase::Insurance) fail("insurance pending");
        }

        if (action || command == "AUTO") {
            const Turn turn = current().value();
            if (turn.seat != seat) fail("waiting for " + seats[turn.seat]->hand_name(turn.hand));
            if (action) {
                if (auto error = action_error(*action, *seats[seat], seats[seat]->hands[turn.hand])) fail(*error);
                perform(*action);
            } else {
                while (phase == Phase::Play && current()->seat == seat) perform(recommend());
            }
        } else if (command == "SHOE") {
            decks = static_cast<int>(value);
            random = seed;
            shuffle();
            std::cout << "shoe " << decks << " decks " << shoe.size() << " cards cut " << cut() << '\n';
        } else if (command == "RULE") {
            if (proposed_rules->minimum > proposed_rules->maximum) fail("min above max");
            rules = *proposed_rules;
            std::cout << "rule " << first << ' ' << second << '\n';
        } else if (command == "RULES") std::cout << rules.text() << '\n';
        else if (command == "PLAYER") {
            if (find_player(first) >= 0) fail("player exists");
            const auto empty = std::find_if(seats.begin(), seats.end(), [](const auto& player) { return !player; });
            if (empty == seats.end()) fail("table full");
            const int number = static_cast<int>(empty - seats.begin()) + 1;
            *empty = Player{first, number, value};
            std::cout << first << " sits at seat " << number << " with " << value << '\n';
        } else if (command == "LEAVE") {
            const Player& player = *seats[seat];
            std::cout << player.name << " leaves with " << player.bankroll << " net " << signed_number(player.net) << '\n';
            seats[seat].reset();
        } else if (command == "REBUY") {
            Player& player = *seats[seat];
            player.bankroll += value;
            std::cout << player.name << " rebuys " << value << " bankroll " << player.bankroll << '\n';
        } else if (command == "BET") {
            Player& player = *seats[seat];
            if (value != 0) {
                if (value < rules.minimum || value > rules.maximum) fail("bet out of limits");
                if (value + player.side > player.bankroll) fail("insufficient funds");
            }
            player.bet = value;
            if (value == 0) {
                player.side = 0;
                std::cout << player.name << " bet cleared\n";
            } else std::cout << player.name << " bets " << value << '\n';
        } else if (command == "SIDE") {
            Player& player = *seats[seat];
            if (value != 0) {
                if (player.bet == 0) fail("no bet");
                if (value > rules.side_maximum) fail("side out of limits");
                if (player.bet + value > player.bankroll) fail("insufficient funds");
            }
            player.side = value;
            if (value == 0) std::cout << player.name << " side cleared\n";
            else std::cout << player.name << " side " << value << '\n';
        } else if (command == "DEAL") {
            if (decks == 0) fail("no shoe");
            if (std::none_of(seats.begin(), seats.end(), [](const auto& player) { return player && player->bet != 0; }))
                fail("no bets");
            deal();
        } else if (command == "INSURANCE") {
            if (seat != participants[insurance_turn]) fail("waiting for " + seats[participants[insurance_turn]]->name);
            Player& player = *seats[seat];
            if (value > player.bet / 2) fail("insurance out of limits");
            if (value > player.bankroll) fail("insufficient funds");
            player.bankroll -= value;
            player.insurance = value;
            if (value == 0) std::cout << player.name << " declines insurance\n";
            else std::cout << player.name << " insures " << value << '\n';
            if (++insurance_turn == participants.size()) peek();
        } else if (command == "HINT") {
            const Turn turn = current().value();
            std::cout << "hint " << seats[turn.seat]->hand_name(turn.hand) << ": " << action_name(recommend()) << '\n';
        } else if (command == "STATUS") status();
        else if (command == "COUNT") {
            if (decks == 0) fail("no shoe");
            const int remaining = static_cast<int>(shoe.size()) - drawn;
            const int hundredths = (running < 0 ? -running : running) * 5200 / remaining;
            std::ostringstream count;
            if (running < 0) count << '-';
            count << hundredths / 100 << '.' << std::setw(2) << std::setfill('0') << hundredths % 100;
            std::cout << "count running " << running << " true " << count.str() << " remaining " << remaining << '\n';
        } else if (command == "STATS") {
            if (std::none_of(seats.begin(), seats.end(), [](const auto& player) { return player.has_value(); })) fail("no players");
            for (const auto& entry : seats) {
                if (!entry) continue;
                const Player& player = *entry;
                const Statistics& s = player.stats;
                std::cout << "stats " << player.name << " rounds " << s.rounds << " hands " << s.hands
                          << " wins " << s.wins << " losses " << s.losses << " pushes " << s.pushes
                          << " blackjacks " << s.blackjacks << " busts " << s.busts << " surrenders " << s.surrenders
                          << " doubles " << s.doubles << " splits " << s.splits << " net " << signed_number(player.net) << '\n';
            }
            std::cout << "stats dealer rounds " << round << " blackjacks " << dealer_blackjacks << " busts " << dealer_busts << '\n';
        }
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int count;
    std::cin >> count;
    std::string line;
    std::getline(std::cin, line);
    Table table;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        std::istringstream input(line);
        std::vector<std::string> words;
        for (std::string word; input >> word;) words.push_back(std::move(word));
        try {
            table.command(words);
        } catch (const CommandError& error) {
            std::cout << "error: " << error.what() << '\n';
        }
    }
}
