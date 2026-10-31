#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { SEATS = 7, MAX_HANDS = 4, MAX_CARDS = 21, MAX_SHOE = 416 };
typedef int64_t Money;
typedef enum { IDLE, INSURANCE, PLAY } State;
typedef enum { FINISH_NONE, FINISH_BUST, FINISH_SURRENDER, FINISH_CHARLIE } Finish;
typedef enum { HIT, STAND, DOUBLE, SPLIT, SURRENDER } Action;
typedef enum { S17, H17 } DealerRule;
typedef enum { THREE_TWO, SIX_FIVE } BlackjackRule;
typedef enum { ANY, NINE_ELEVEN, TEN_ELEVEN } DoubleRule;
typedef enum {
    R_DEALER, R_PEN, R_MIN, R_MAX, R_BJ, R_DAS, R_DOUBLE, R_HANDS,
    R_RSA, R_SURRENDER, R_CHARLIE, R_SIDEMAX, RULE_COUNT
} Rule;
typedef enum {
    C_SHOE, C_RULE, C_RULES, C_PLAYER, C_LEAVE, C_REBUY, C_BET, C_SIDE,
    C_DEAL, C_INSURANCE, C_HIT, C_STAND, C_DOUBLE, C_SPLIT, C_SURRENDER,
    C_HINT, C_AUTO, C_STATUS, C_COUNT, C_STATS, COMMAND_COUNT
} Command;
typedef enum { BLACKJACK, WIN, LOSE, PUSH, BUST, SURRENDERED, CHARLIE } Result;

static const char *const rule_names[] = {
    "DEALER", "PEN", "MIN", "MAX", "BJ", "DAS", "DOUBLE", "HANDS",
    "RSA", "SURRENDER", "CHARLIE", "SIDEMAX"
};
static const char *const command_names[] = {
    "SHOE", "RULE", "RULES", "PLAYER", "LEAVE", "REBUY", "BET", "SIDE",
    "DEAL", "INSURANCE", "HIT", "STAND", "DOUBLE", "SPLIT", "SURRENDER",
    "HINT", "AUTO", "STATUS", "COUNT", "STATS"
};
static const char *const action_names[] = { "hit", "stand", "double", "split", "surrender" };
static const char *const result_names[] = { "blackjack", "win", "lose", "push", "bust", "surrender", "charlie" };

typedef struct { int rank, suit; } Card;
typedef struct { int value; bool soft; } Total;
typedef struct {
    Card cards[MAX_CARDS];
    int count;
    Money bet;
    bool split, split_aces, finished;
    Finish reason;
} Hand;
typedef struct {
    int rounds, hands, wins, losses, pushes, blackjacks, busts, surrenders, doubles, splits;
} Stats;
typedef struct {
    bool seated, participating;
    char name[9];
    Money bankroll, bet, side, insurance, net;
    Hand hands[MAX_HANDS];
    int hand_count;
    Stats stats;
} Player;
typedef struct {
    DealerRule dealer;
    int pen, min, max;
    BlackjackRule bj;
    bool das;
    DoubleRule doubling;
    int hands;
    bool rsa, surrender;
    int charlie, side_max;
} Rules;
typedef struct {
    Card cards[MAX_SHOE];
    int decks, size, drawn, running;
    int64_t random;
} Shoe;
typedef struct {
    Rules rules;
    Player players[SEATS];
    Shoe shoe;
    State state;
    int round, insurance_seat, current_seat, current_hand;
    Hand dealer;
    bool hole_visible, dealer_blackjack;
    int dealer_blackjacks, dealer_busts;
} Table;
typedef struct { char text[32]; } Text;

static void error_line(const char *format, ...) {
    va_list args;
    va_start(args, format);
    fputs("error: ", stdout);
    vprintf(format, args);
    putchar('\n');
    va_end(args);
}

static int lookup(const char *word, const char *const names[], int count) {
    for (int i = 0; i < count; i++) if (strcmp(word, names[i]) == 0) return i;
    return -1;
}

static bool integer_word(const char *word, int low, int high, int *value) {
    size_t length = strlen(word);
    if (length == 0 || length > 10 || (length > 1 && word[0] == '0')) return false;
    int64_t number = 0;
    for (size_t i = 0; i < length; i++) {
        if (word[i] < '0' || word[i] > '9') return false;
        number = number * 10 + word[i] - '0';
    }
    if (number < low || number > high) return false;
    *value = (int)number;
    return true;
}

static bool valid_name(const char *name) {
    size_t length = strlen(name);
    if (length == 0 || length > 8) return false;
    for (size_t i = 0; i < length; i++) if (name[i] < 'A' || name[i] > 'Z') return false;
    return true;
}

static int find_player(const Table *table, const char *name) {
    for (int i = 0; i < SEATS; i++) {
        if (table->players[i].seated && strcmp(table->players[i].name, name) == 0) return i;
    }
    return -1;
}

static int point(Card card) { return card.rank == 0 ? 1 : card.rank < 9 ? card.rank + 1 : 10; }
static bool black(Card card) { return card.suit == 0 || card.suit == 3; }
static int hilo(Card card) { int value = point(card); return value >= 2 && value <= 6 ? 1 : value >= 7 && value <= 9 ? 0 : -1; }

static Text card_text(Card card) {
    Text text = { { "A23456789TJQK"[card.rank], "CDHS"[card.suit], '\0' } };
    return text;
}

static Text hand_name(const Player *player, int hand) {
    Text text;
    snprintf(text.text, sizeof text.text, "%s[%d]", player->name, hand + 1);
    return text;
}

static Total total(const Hand *hand) {
    int sum = 0;
    bool ace = false;
    for (int i = 0; i < hand->count; i++) {
        sum += point(hand->cards[i]);
        ace = ace || hand->cards[i].rank == 0;
    }
    bool soft = ace && sum + 10 <= 21;
    return (Total){ sum + (soft ? 10 : 0), soft };
}

static bool blackjack(const Hand *hand) { return !hand->split && hand->count == 2 && total(hand).value == 21; }

static void show_hand(const Hand *hand) {
    for (int i = 0; i < hand->count; i++) {
        if (i) putchar(' ');
        fputs(card_text(hand->cards[i]).text, stdout);
    }
    Total score = total(hand);
    if (blackjack(hand)) fputs(" (blackjack)", stdout);
    else if (score.value > 21) printf(" (bust %d)", score.value);
    else if (score.soft) printf(" (soft %d)", score.value);
    else printf(" (%d)", score.value);
}

static void hand_line(const Player *player, int index, const char *verb) {
    printf("%s%s: ", hand_name(player, index).text, verb);
    show_hand(&player->hands[index]);
    putchar('\n');
}

static void dealer_line(const Table *table, bool hit) {
    fputs(hit ? "dealer hits: " : "dealer: ", stdout);
    show_hand(&table->dealer);
    putchar('\n');
}

static void shuffle(Shoe *shoe) {
    for (int i = 0; i < shoe->size; i++) shoe->cards[i] = (Card){ i % 13, i / 13 % 4 };
    for (int i = shoe->size - 1; i > 0; i--) {
        shoe->random = 48271 * shoe->random % 2147483647;
        int j = (int)(shoe->random % (i + 1));
        Card temporary = shoe->cards[i];
        shoe->cards[i] = shoe->cards[j];
        shoe->cards[j] = temporary;
    }
    shoe->drawn = shoe->running = 0;
}

static Card draw(Table *table, bool visible) {
    Card card = table->shoe.cards[table->shoe.drawn++];
    if (visible) table->shoe.running += hilo(card);
    return card;
}

static void add_card(Hand *hand, Card card) { hand->cards[hand->count++] = card; }

static void reveal(Table *table) {
    if (!table->hole_visible) {
        table->shoe.running += hilo(table->dealer.cards[1]);
        table->hole_visible = true;
    }
}

static bool parse_rule(Rule rule, const char *word, int *value) {
    const char *const dealers[] = { "S17", "H17" };
    const char *const blackjacks[] = { "3:2", "6:5" };
    const char *const doubles[] = { "ANY", "9-11", "10-11" };
    switch (rule) {
        case R_DEALER: *value = lookup(word, dealers, 2); return *value >= 0;
        case R_BJ: *value = lookup(word, blackjacks, 2); return *value >= 0;
        case R_DOUBLE: *value = lookup(word, doubles, 3); return *value >= 0;
        case R_DAS: case R_RSA: case R_SURRENDER:
            if (strcmp(word, "ON") == 0) { *value = 1; return true; }
            if (strcmp(word, "OFF") == 0) { *value = 0; return true; }
            return false;
        case R_PEN: return integer_word(word, 50, 90, value);
        case R_MIN: case R_MAX: return integer_word(word, 1, 10000, value);
        case R_HANDS: return integer_word(word, 1, 4, value);
        case R_SIDEMAX: return integer_word(word, 0, 1000, value);
        case R_CHARLIE:
            return integer_word(word, 0, 7, value) && (*value == 0 || *value >= 5);
        default: return false;
    }
}

static void set_rule(Rules *rules, Rule rule, int value) {
    switch (rule) {
        case R_DEALER: rules->dealer = (DealerRule)value; break;
        case R_PEN: rules->pen = value; break;
        case R_MIN: rules->min = value; break;
        case R_MAX: rules->max = value; break;
        case R_BJ: rules->bj = (BlackjackRule)value; break;
        case R_DAS: rules->das = value != 0; break;
        case R_DOUBLE: rules->doubling = (DoubleRule)value; break;
        case R_HANDS: rules->hands = value; break;
        case R_RSA: rules->rsa = value != 0; break;
        case R_SURRENDER: rules->surrender = value != 0; break;
        case R_CHARLIE: rules->charlie = value; break;
        case R_SIDEMAX: rules->side_max = value; break;
        default: break;
    }
}

static Text rule_text(const Rules *rules, Rule rule) {
    Text text = { "" };
    const char *word = NULL;
    int value = 0;
    switch (rule) {
        case R_DEALER: word = rules->dealer == S17 ? "S17" : "H17"; break;
        case R_PEN: value = rules->pen; break;
        case R_MIN: value = rules->min; break;
        case R_MAX: value = rules->max; break;
        case R_BJ: word = rules->bj == THREE_TWO ? "3:2" : "6:5"; break;
        case R_DAS: word = rules->das ? "ON" : "OFF"; break;
        case R_DOUBLE: word = rules->doubling == ANY ? "ANY" : rules->doubling == NINE_ELEVEN ? "9-11" : "10-11"; break;
        case R_HANDS: value = rules->hands; break;
        case R_RSA: word = rules->rsa ? "ON" : "OFF"; break;
        case R_SURRENDER: word = rules->surrender ? "ON" : "OFF"; break;
        case R_CHARLIE: value = rules->charlie; break;
        case R_SIDEMAX: value = rules->side_max; break;
        default: break;
    }
    if (word) snprintf(text.text, sizeof text.text, "%s", word);
    else snprintf(text.text, sizeof text.text, "%d", value);
    return text;
}

static void automatic_finish(const Table *table, const Player *player, Hand *hand) {
    Total score = total(hand);
    if (score.value > 21) { hand->finished = true; hand->reason = FINISH_BUST; }
    else if (table->rules.charlie && hand->count == table->rules.charlie) {
        hand->finished = true; hand->reason = FINISH_CHARLIE;
    } else if (score.value == 21) hand->finished = true;
    else if (hand->split_aces && hand->count == 2) {
        bool resplit = hand->cards[0].rank == 0 && hand->cards[1].rank == 0 &&
                       table->rules.rsa && player->hand_count < table->rules.hands;
        hand->finished = !resplit;
    }
}

static Result hand_result(const Table *table, const Hand *hand) {
    if (table->dealer_blackjack) return blackjack(hand) ? PUSH : LOSE;
    if (blackjack(hand)) return BLACKJACK;
    if (hand->reason == FINISH_BUST) return BUST;
    if (hand->reason == FINISH_SURRENDER) return SURRENDERED;
    if (hand->reason == FINISH_CHARLIE) return CHARLIE;
    int player_total = total(hand).value, dealer_total = total(&table->dealer).value;
    if (dealer_total > 21 || player_total > dealer_total) return WIN;
    return player_total == dealer_total ? PUSH : LOSE;
}

static Money profit(const Rules *rules, Money bet, Result result) {
    switch (result) {
        case BLACKJACK: return rules->bj == THREE_TWO ? bet * 3 / 2 : bet * 6 / 5;
        case WIN: case CHARLIE: return bet;
        case PUSH: return 0;
        case SURRENDERED: return bet / 2 - bet;
        default: return -bet;
    }
}

static void settle(Table *table) {
    for (int seat = 0; seat < SEATS; seat++) {
        Player *player = &table->players[seat];
        if (!player->participating) continue;
        for (int index = 0; index < player->hand_count; index++) {
            const Hand *hand = &player->hands[index];
            Result result = hand_result(table, hand);
            Money gain = profit(&table->rules, hand->bet, result);
            player->bankroll += hand->bet + gain;
            player->net += gain;
            player->stats.hands++;
            if (result == BLACKJACK || result == WIN || result == CHARLIE) player->stats.wins++;
            else if (result == PUSH) player->stats.pushes++;
            else player->stats.losses++;
            if (result == BLACKJACK) player->stats.blackjacks++;
            if (result == BUST) player->stats.busts++;
            if (result == SURRENDERED) player->stats.surrenders++;
            printf("%s %s %+" PRId64 "\n", hand_name(player, index).text, result_names[result], gain);
        }
        printf("%s bankroll %" PRId64 "\n", player->name, player->bankroll);
    }
    for (int seat = 0; seat < SEATS; seat++) {
        table->players[seat].bet = table->players[seat].side = 0;
        table->players[seat].participating = false;
    }
    table->state = IDLE;
}

static void dealer_turn(Table *table) {
    reveal(table);
    dealer_line(table, false);
    bool needs_draw = false;
    for (int seat = 0; seat < SEATS; seat++) {
        const Player *player = &table->players[seat];
        if (!player->participating) continue;
        for (int i = 0; i < player->hand_count; i++) {
            const Hand *hand = &player->hands[i];
            if (hand->reason == FINISH_NONE && !blackjack(hand)) needs_draw = true;
        }
    }
    bool drew = false;
    if (needs_draw) {
        for (;;) {
            Total score = total(&table->dealer);
            if (!(score.value <= 16 || (score.value == 17 && score.soft && table->rules.dealer == H17))) break;
            add_card(&table->dealer, draw(table, true));
            dealer_line(table, true);
            drew = true;
        }
    }
    if (drew && total(&table->dealer).value > 21) table->dealer_busts++;
    settle(table);
}

static void next_hand(Table *table) {
    for (;;) {
        bool found = false;
        for (int seat = 0; seat < SEATS && !found; seat++) {
            Player *player = &table->players[seat];
            if (!player->participating) continue;
            for (int index = 0; index < player->hand_count; index++) {
                if (!player->hands[index].finished) {
                    table->current_seat = seat;
                    table->current_hand = index;
                    found = true;
                    break;
                }
            }
        }
        if (!found) { dealer_turn(table); return; }
        Player *player = &table->players[table->current_seat];
        Hand *hand = &player->hands[table->current_hand];
        if (hand->count != 1) return;
        add_card(hand, draw(table, true));
        hand_line(player, table->current_hand, "");
        automatic_finish(table, player, hand);
        if (!hand->finished) return;
    }
}

static void peek(Table *table) {
    table->dealer_blackjack = blackjack(&table->dealer);
    printf("dealer peeks: %s\n", table->dealer_blackjack ? "blackjack" : "no blackjack");
    if (table->dealer_blackjack) table->dealer_blackjacks++;
    for (int seat = 0; seat < SEATS; seat++) {
        Player *player = &table->players[seat];
        if (!player->participating || player->insurance == 0) continue;
        Money gain = table->dealer_blackjack ? player->insurance * 2 : -player->insurance;
        player->bankroll += player->insurance + gain;
        player->net += gain;
        printf("%s insurance %+" PRId64 "\n", player->name, gain);
    }
    if (table->dealer_blackjack) {
        reveal(table);
        dealer_line(table, false);
        settle(table);
    } else {
        table->state = PLAY;
        next_hand(table);
    }
}

static void deal(Table *table) {
    if (table->shoe.drawn >= table->shoe.size * table->rules.pen / 100) {
        shuffle(&table->shoe);
        puts("shuffle");
    }
    table->round++;
    printf("round %d\n", table->round);
    table->dealer = (Hand){0};
    table->hole_visible = table->dealer_blackjack = false;
    for (int seat = 0; seat < SEATS; seat++) {
        Player *player = &table->players[seat];
        player->participating = player->seated && player->bet != 0;
        player->hand_count = 0;
        if (player->participating) {
            player->bankroll -= player->bet + player->side;
            player->insurance = 0;
            player->stats.rounds++;
            player->hand_count = 1;
            player->hands[0] = (Hand){ .bet = player->bet };
            add_card(&player->hands[0], draw(table, true));
        }
    }
    add_card(&table->dealer, draw(table, true));
    for (int seat = 0; seat < SEATS; seat++) {
        Player *player = &table->players[seat];
        if (player->participating) {
            add_card(&player->hands[0], draw(table, true));
            player->hands[0].finished = blackjack(&player->hands[0]);
        }
    }
    add_card(&table->dealer, draw(table, false));
    for (int seat = 0; seat < SEATS; seat++) {
        if (table->players[seat].participating) hand_line(&table->players[seat], 0, "");
    }
    printf("dealer: %s ??\n", card_text(table->dealer.cards[0]).text);
    for (int seat = 0; seat < SEATS; seat++) {
        Player *player = &table->players[seat];
        if (!player->participating || player->side == 0) continue;
        Card a = player->hands[0].cards[0], b = player->hands[0].cards[1];
        int multiplier = a.rank != b.rank ? -1 : a.suit == b.suit ? 25 : black(a) == black(b) ? 12 : 6;
        const char *result = multiplier == 25 ? "perfect" : multiplier == 12 ? "colored" : multiplier == 6 ? "mixed" : "lose";
        Money gain = player->side * multiplier;
        player->bankroll += player->side + gain;
        player->net += gain;
        printf("%s side %s %+" PRId64 "\n", player->name, result, gain);
    }
    int upcard = point(table->dealer.cards[0]);
    if (upcard == 1) {
        table->state = INSURANCE;
        table->insurance_seat = 0;
        while (!table->players[table->insurance_seat].participating) table->insurance_seat++;
        puts("insurance offered");
    } else if (upcard == 10) peek(table);
    else { table->state = PLAY; next_hand(table); }
}

static const char *action_problem(const Table *table, Action action) {
    const Player *player = &table->players[table->current_seat];
    const Hand *hand = &player->hands[table->current_hand];
    Total score = total(hand);
    if (action == HIT) return hand->split_aces ? "split aces" : NULL;
    if (action == DOUBLE) {
        if (hand->split_aces) return "split aces";
        if (hand->count != 2) return "two cards only";
        if ((!table->rules.das && hand->split) ||
            (table->rules.doubling != ANY && (score.soft || score.value > 11 ||
             score.value < (table->rules.doubling == NINE_ELEVEN ? 9 : 10)))) return "double not allowed";
        if (player->bankroll < hand->bet) return "insufficient funds";
    } else if (action == SPLIT) {
        if (hand->count != 2) return "two cards only";
        if (point(hand->cards[0]) != point(hand->cards[1])) return "not a pair";
        if (player->hand_count >= table->rules.hands) return "hand limit";
        if (player->bankroll < hand->bet) return "insufficient funds";
    } else if (action == SURRENDER) {
        if (!table->rules.surrender || hand->split) return "surrender not allowed";
        if (hand->count != 2) return "two cards only";
    }
    return NULL;
}

static Action recommendation(const Table *table) {
    const Player *player = &table->players[table->current_seat];
    const Hand *hand = &player->hands[table->current_hand];
    int up = point(table->dealer.cards[0]);
    if (up == 1) up = 11;
    bool split_possible = action_problem(table, SPLIT) == NULL;
    if (hand->split_aces) return split_possible ? SPLIT : STAND;
    if (split_possible) {
        int value = point(hand->cards[0]);
        bool preferred = value == 1 || value == 8 ||
            (value == 9 && up != 7 && up != 10 && up != 11) ||
            ((value == 2 || value == 3 || value == 7) && up <= 7) ||
            (value == 6 && up <= 6) || (value == 4 && (up == 5 || up == 6));
        if (preferred) return SPLIT;
    }
    Total score = total(hand);
    int value = score.value;
    bool can_double = action_problem(table, DOUBLE) == NULL;
    if (score.soft) {
        if (value >= 19) return STAND;
        if (value == 18) {
            if (up >= 3 && up <= 6) return can_double ? DOUBLE : STAND;
            return up == 2 || up == 7 || up == 8 ? STAND : HIT;
        }
        bool wants_double = (value == 17 && up >= 3 && up <= 6) ||
            ((value == 15 || value == 16) && up >= 4 && up <= 6) ||
            ((value == 13 || value == 14) && (up == 5 || up == 6));
        return wants_double && can_double ? DOUBLE : HIT;
    }
    if (value >= 17) return STAND;
    if (value >= 13) {
        if (up <= 6) return STAND;
        if (((value == 16 && up >= 9) || (value == 15 && up == 10)) && action_problem(table, SURRENDER) == NULL) return SURRENDER;
        return HIT;
    }
    if (value == 12) return up >= 4 && up <= 6 ? STAND : HIT;
    bool wants_double = (value == 11 && up <= 10) || (value == 10 && up <= 9) ||
                        (value == 9 && up >= 3 && up <= 6);
    return wants_double && can_double ? DOUBLE : HIT;
}

static void perform_action(Table *table, Action action) {
    Player *player = &table->players[table->current_seat];
    int index = table->current_hand;
    Hand *hand = &player->hands[index];
    if (action == HIT || action == DOUBLE) {
        if (action == DOUBLE) {
            player->bankroll -= hand->bet;
            hand->bet *= 2;
            player->stats.doubles++;
        }
        add_card(hand, draw(table, true));
        hand_line(player, index, action == HIT ? " hits" : " doubles");
        automatic_finish(table, player, hand);
        if (action == DOUBLE) hand->finished = true;
    } else if (action == STAND || action == SURRENDER) {
        hand->finished = true;
        if (action == SURRENDER) hand->reason = FINISH_SURRENDER;
        hand_line(player, index, action == STAND ? " stands" : " surrenders");
    } else {
        Card first = hand->cards[0], second = hand->cards[1];
        Money bet = hand->bet;
        bool aces = hand->split_aces || first.rank == 0;
        player->bankroll -= bet;
        player->stats.splits++;
        printf("%s splits %s %s\n", hand_name(player, index).text, card_text(first).text, card_text(second).text);
        memmove(&player->hands[index + 2], &player->hands[index + 1],
                (size_t)(player->hand_count - index - 1) * sizeof(Hand));
        player->hands[index] = (Hand){ .bet = bet, .split = true, .split_aces = aces };
        player->hands[index + 1] = (Hand){ .bet = bet, .split = true, .split_aces = aces };
        add_card(&player->hands[index], first);
        add_card(&player->hands[index + 1], second);
        player->hand_count++;
        add_card(&player->hands[index], draw(table, true));
        hand_line(player, index, "");
        automatic_finish(table, player, &player->hands[index]);
    }
    next_hand(table);
}

static void show_status(const Table *table) {
    if (table->state == IDLE) printf("table idle round %d\n", table->round);
    else if (table->state == INSURANCE) printf("table insurance round %d next %s\n", table->round, table->players[table->insurance_seat].name);
    else printf("table play round %d turn %s\n", table->round, hand_name(&table->players[table->current_seat], table->current_hand).text);
    if (table->state != IDLE) printf("dealer: %s ??\n", card_text(table->dealer.cards[0]).text);
    for (int seat = 0; seat < SEATS; seat++) {
        const Player *player = &table->players[seat];
        if (!player->seated) continue;
        printf("seat %d %s bankroll %" PRId64 " bet %" PRId64 " side %" PRId64 "\n",
               seat + 1, player->name, player->bankroll, player->bet, player->side);
        if (table->state != IDLE && player->participating) {
            for (int i = 0; i < player->hand_count; i++) {
                printf("%s: ", hand_name(player, i).text);
                show_hand(&player->hands[i]);
                printf(" bet %" PRId64 "\n", player->hands[i].bet);
            }
        }
    }
}

static void show_stats(const Table *table) {
    for (int seat = 0; seat < SEATS; seat++) {
        const Player *player = &table->players[seat];
        if (!player->seated) continue;
        const Stats *s = &player->stats;
        printf("stats %s rounds %d hands %d wins %d losses %d pushes %d blackjacks %d busts %d surrenders %d doubles %d splits %d net %+" PRId64 "\n",
               player->name, s->rounds, s->hands, s->wins, s->losses, s->pushes, s->blackjacks, s->busts, s->surrenders, s->doubles, s->splits, player->net);
    }
    printf("stats dealer rounds %d blackjacks %d busts %d\n", table->round, table->dealer_blackjacks, table->dealer_busts);
}

static bool named_player(Command command) {
    return command == C_LEAVE || command == C_REBUY || command == C_BET || command == C_SIDE ||
           command == C_INSURANCE || (command >= C_HIT && command <= C_SURRENDER) || command == C_AUTO;
}

static bool idle_only(Command command) {
    return command == C_SHOE || command == C_RULE || command == C_PLAYER || command == C_LEAVE ||
           command == C_REBUY || command == C_BET || command == C_SIDE || command == C_DEAL;
}

static void execute(Table *table, char *words[]) {
    int found = lookup(words[0], command_names, COMMAND_COUNT);
    if (found < 0) { error_line("unknown command %s", words[0]); return; }
    Command command = (Command)found;
    int seat = -1, first = 0, second = 0, rule = -1;
    if (command == C_SHOE) {
        if (!integer_word(words[1], 1, 8, &first)) { error_line("bad value %s", words[1]); return; }
        if (!integer_word(words[2], 1, 2147483646, &second)) { error_line("bad value %s", words[2]); return; }
    } else if (command == C_RULE) {
        rule = lookup(words[1], rule_names, RULE_COUNT);
        if (rule < 0) { error_line("unknown rule %s", words[1]); return; }
        if (!parse_rule((Rule)rule, words[2], &first)) { error_line("bad value %s", words[2]); return; }
    } else if (command == C_PLAYER) {
        if (!valid_name(words[1])) { error_line("bad name %s", words[1]); return; }
        if (!integer_word(words[2], 1, 1000000, &first)) { error_line("bad value %s", words[2]); return; }
    } else if (named_player(command)) {
        seat = find_player(table, words[1]);
        if (seat < 0) { error_line("unknown player %s", words[1]); return; }
        if (command == C_REBUY || command == C_BET || command == C_SIDE || command == C_INSURANCE) {
            if (!integer_word(words[2], command == C_REBUY ? 1 : 0, 1000000, &first)) {
                error_line("bad value %s", words[2]); return;
            }
        }
    }
    if (idle_only(command) && table->state != IDLE) { error_line("round in progress"); return; }
    if (command == C_INSURANCE && table->state != INSURANCE) { error_line("no insurance"); return; }
    bool action_command = (command >= C_HIT && command <= C_SURRENDER) || command == C_AUTO;
    if (action_command || command == C_HINT) {
        if (table->state == IDLE) { error_line("no round"); return; }
        if (table->state == INSURANCE) { error_line("insurance pending"); return; }
        if (action_command && seat != table->current_seat) {
            error_line("waiting for %s", hand_name(&table->players[table->current_seat], table->current_hand).text);
            return;
        }
    }
    Player *player = seat < 0 ? NULL : &table->players[seat];
    switch (command) {
        case C_SHOE:
            table->shoe.decks = first;
            table->shoe.size = first * 52;
            table->shoe.random = second;
            shuffle(&table->shoe);
            printf("shoe %d decks %d cards cut %d\n", first, table->shoe.size, table->shoe.size * table->rules.pen / 100);
            break;
        case C_RULE: {
            Rules changed = table->rules;
            set_rule(&changed, (Rule)rule, first);
            if (changed.min > changed.max) { error_line("min above max"); return; }
            table->rules = changed;
            printf("rule %s %s\n", rule_names[rule], rule_text(&changed, (Rule)rule).text);
            break;
        }
        case C_RULES:
            fputs("rules", stdout);
            for (int i = 0; i < RULE_COUNT; i++) printf(" %s %s", rule_names[i], rule_text(&table->rules, (Rule)i).text);
            putchar('\n');
            break;
        case C_PLAYER:
            if (find_player(table, words[1]) >= 0) { error_line("player exists"); return; }
            for (seat = 0; seat < SEATS && table->players[seat].seated; seat++) {}
            if (seat == SEATS) { error_line("table full"); return; }
            table->players[seat] = (Player){ .seated = true, .bankroll = first };
            strcpy(table->players[seat].name, words[1]);
            printf("%s sits at seat %d with %d\n", words[1], seat + 1, first);
            break;
        case C_LEAVE:
            printf("%s leaves with %" PRId64 " net %+" PRId64 "\n", player->name, player->bankroll, player->net);
            *player = (Player){0};
            break;
        case C_REBUY:
            player->bankroll += first;
            printf("%s rebuys %d bankroll %" PRId64 "\n", player->name, first, player->bankroll);
            break;
        case C_BET:
            if (first == 0) {
                player->bet = player->side = 0;
                printf("%s bet cleared\n", player->name);
            } else {
                if (first < table->rules.min || first > table->rules.max) { error_line("bet out of limits"); return; }
                if (first + player->side > player->bankroll) { error_line("insufficient funds"); return; }
                player->bet = first;
                printf("%s bets %d\n", player->name, first);
            }
            break;
        case C_SIDE:
            if (first == 0) {
                player->side = 0;
                printf("%s side cleared\n", player->name);
            } else {
                if (player->bet == 0) { error_line("no bet"); return; }
                if (first > table->rules.side_max) { error_line("side out of limits"); return; }
                if (player->bet + first > player->bankroll) { error_line("insufficient funds"); return; }
                player->side = first;
                printf("%s side %d\n", player->name, first);
            }
            break;
        case C_DEAL: {
            if (table->shoe.size == 0) { error_line("no shoe"); return; }
            bool bets = false;
            for (int i = 0; i < SEATS; i++) if (table->players[i].seated && table->players[i].bet != 0) bets = true;
            if (!bets) { error_line("no bets"); return; }
            deal(table);
            break;
        }
        case C_INSURANCE:
            if (seat != table->insurance_seat) { error_line("waiting for %s", table->players[table->insurance_seat].name); return; }
            if (first > player->bet / 2) { error_line("insurance out of limits"); return; }
            if (first > player->bankroll) { error_line("insufficient funds"); return; }
            player->bankroll -= first;
            player->insurance = first;
            if (first == 0) printf("%s declines insurance\n", player->name);
            else printf("%s insures %d\n", player->name, first);
            do { table->insurance_seat++; }
            while (table->insurance_seat < SEATS && !table->players[table->insurance_seat].participating);
            if (table->insurance_seat == SEATS) peek(table);
            break;
        case C_HIT: case C_STAND: case C_DOUBLE: case C_SPLIT: case C_SURRENDER: {
            Action action = (Action)(command - C_HIT);
            const char *problem = action_problem(table, action);
            if (problem) { error_line("%s", problem); return; }
            perform_action(table, action);
            break;
        }
        case C_HINT:
            printf("hint %s: %s\n", hand_name(&table->players[table->current_seat], table->current_hand).text, action_names[recommendation(table)]);
            break;
        case C_AUTO:
            while (table->state == PLAY && table->current_seat == seat) perform_action(table, recommendation(table));
            break;
        case C_STATUS: show_status(table); break;
        case C_COUNT: {
            if (table->shoe.size == 0) { error_line("no shoe"); return; }
            int remaining = table->shoe.size - table->shoe.drawn;
            int running = table->shoe.running;
            int64_t scaled = (int64_t)abs(running) * 5200 / remaining;
            printf("count running %d true %s%" PRId64 ".%02" PRId64 " remaining %d\n", running, running < 0 ? "-" : "", scaled / 100, scaled % 100, remaining);
            break;
        }
        case C_STATS: {
            bool seated = false;
            for (int i = 0; i < SEATS; i++) seated = seated || table->players[i].seated;
            if (!seated) { error_line("no players"); return; }
            show_stats(table);
            break;
        }
        default: break;
    }
}

int main(void) {
    Table table = {
        .rules = { .dealer = S17, .pen = 75, .min = 10, .max = 500, .bj = THREE_TWO,
                   .das = true, .doubling = ANY, .hands = 4, .rsa = false,
                   .surrender = true, .charlie = 0, .side_max = 25 }
    };
    char line[128];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int commands = atoi(line);
    for (int i = 0; i < commands; i++) {
        if (!fgets(line, sizeof line, stdin)) break;
        char *words[4] = {0};
        int count = 0;
        char *word = strtok(line, " \r\n");
        while (word && count < 4) {
            words[count++] = word;
            word = strtok(NULL, " \r\n");
        }
        execute(&table, words);
    }
    return 0;
}
