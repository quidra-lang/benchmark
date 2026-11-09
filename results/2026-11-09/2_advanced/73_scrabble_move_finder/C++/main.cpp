#include "scrabble.hpp"

struct Evaluated {
    Move move;
    int score;
    Placement tiles;
    std::string words, leave;
    int value;
};
struct TopnTotals {
    int jobs = 0, errors = 0, moves = 0, bingos = 0;
};
struct ValidationTotals {
    int jobs = 0, errors = 0, moves = 0, valid = 0, invalid = 0, loss = 0;
};
struct GameTotals {
    int games = 0, duplicates = 0, errors = 0, turns = 0, rounds = 0, plays = 0, exchanges = 0,
        passes = 0, bingos = 0;
};
static Names split(const std::string &text) {
    Names out;
    std::istringstream stream(text);
    std::string word;
    while (stream >> word)
        out.push_back(word);
    return out;
}
static std::string join(const Names &values, const std::string &separator = ",") {
    std::string out;
    for (int i = 0; i < int(values.size()); ++i) {
        if (i)
            out += separator;
        out += values[i];
    }
    return out;
}
static bool valid_name(const std::string &value) {
    if (value.empty() || value.size() > 20)
        return false;
    for (char letter : value)
        if (!(lower(letter) || (letter >= '0' && letter <= '9') || letter == '_'))
            return false;
    return true;
}
static bool valid_number(const std::string &value, int minimum, int maximum) {
    if (value.empty() || (value.size() > 1 && value[0] == '0'))
        return false;
    Integer number = 0;
    for (char digit : value) {
        if (digit < '0' || digit > '9')
            return false;
        number = number * 10 + (digit - '0');
        if (number > maximum)
            return false;
    }
    return number >= minimum;
}
static bool valid_rack(const std::string &value) {
    return !value.empty() && value.size() <= rack_size &&
           std::all_of(value.begin(), value.end(),
                       [](char tile) { return upper(tile) || tile == '?'; });
}
static bool strategy(const std::string &value) {
    return value == "score" || value == "tiles" || value == "equity";
}
static std::string collection(std::string value) {
    std::sort(value.begin(), value.end());
    return value.empty() ? "-" : value;
}
static std::string remove_tiles(const std::string &rack, const std::string &removed) {
    std::array<int, 128> counts{};
    for (char tile : rack)
        ++counts[static_cast<unsigned char>(tile)];
    for (char tile : removed)
        --counts[static_cast<unsigned char>(tile)];
    std::string out;
    for (int tile = 0; tile < 128; ++tile)
        if (counts[tile] > 0)
            out.append(counts[tile], char(tile));
    return out;
}
static std::string notation(const Evaluated &move) {
    return position(move.move) + " " + move.move.word;
}
static auto standard_key(const Evaluated &move) {
    return std::make_tuple(-move.score, move.move.row, move.move.column, move.move.direction,
                           move.move.word);
}
static bool standard_before(const Evaluated &a, const Evaluated &b) {
    return standard_key(a) < standard_key(b);
}
static bool strategy_before(const Evaluated &a, const Evaluated &b, const std::string &order) {
    if (order == "tiles" && a.tiles.size() != b.tiles.size())
        return a.tiles.size() > b.tiles.size();
    if (order == "equity" && a.score + a.value != b.score + b.value)
        return a.score + a.value > b.score + b.value;
    return standard_before(a, b);
}
static std::vector<std::tuple<int, int, char>> placement_key(const Placement &tiles) {
    std::vector<std::tuple<int, int, char>> out;
    for (const Tile &tile : tiles)
        out.emplace_back(tile.row, tile.column, tile.letter);
    std::sort(out.begin(), out.end());
    return out;
}
class Scrabble {
    Counts values{}, counts{}, weights{};
    Trie trie;
    std::vector<Lines> jobs;
    Lines dictionary_lines;
    TopnTotals topn_totals;
    ValidationTotals validation_totals;
    GameTotals game_totals;

    Board from_rows(const Names &rows) const {
        Board out;
        for (int row = 0; row < 15; ++row)
            for (int column = 0; column < 15; ++column)
                out[row][column] = rows[row][column];
        return out;
    }
    Names initial_rows(const Lines &job) const {
        Names header = split(job[0]);
        Names rows;
        std::size_t start = header[0] == "TOPN" ? 3 : 2;
        for (std::size_t i = start; i < job.size() && job[i].rfind("MOVE", 0) != 0; ++i)
            rows.push_back(job[i]);
        return rows;
    }
    Counts used_tiles(const Board &board) const {
        Counts out{};
        for (const Tile &tile : board_tiles(board))
            ++out[tile_index(tile.letter)];
        return out;
    }
    std::string tile_error(const Board &board, const std::string &rack) const {
        Counts used = used_tiles(board);
        for (char tile : rack)
            ++used[tile_index(tile)];
        for (int tile = 0; tile < 27; ++tile)
            if (used[tile] > counts[tile])
                return std::string("too many ") + tile_order[tile];
        return "";
    }
    std::string unseen(const Board &board, const std::string &rack) const {
        Counts used = used_tiles(board);
        for (char tile : rack)
            ++used[tile_index(tile)];
        std::string out;
        for (int tile = 0; tile < 27; ++tile)
            out.append(counts[tile] - used[tile], tile_order[tile]);
        return out;
    }
    std::string board_error(const Names &rows, const std::string &rack) const {
        if (rows.size() != 15)
            return "board rows " + std::to_string(rows.size());
        for (int row = 0; row < 15; ++row)
            if (rows[row].size() != 15 ||
                std::any_of(rows[row].begin(), rows[row].end(),
                            [](char tile) { return tile != '.' && !upper(tile) && !lower(tile); }))
                return "bad board row " + std::to_string(row + 1);
        Board board = from_rows(rows);
        std::string reason = tile_error(board, rack);
        if (!reason.empty())
            return reason;
        if (!board_tiles(board).empty() && board[7][7] == '.')
            return "center empty";
        if (!connected(board))
            return "disconnected";
        for (const Move &word : board_words(board))
            if (!trie.contains(uppercase(word.word)))
                return "unknown word " + word.word + " at " + position(word);
        return "";
    }
    std::string job_error(const Lines &job, const std::set<std::string> &seen) const {
        Names header = split(job[0]);
        const std::string &kind = header[0], &name = header[1];
        if (!valid_name(name))
            return "bad name";
        if (seen.count(name))
            return "duplicate name";
        if (kind == "TOPN") {
            if (!valid_number(header[2], 1, 99))
                return "bad count";
            if (!strategy(header[3]))
                return "bad order";
            std::string rack = split(job[1])[1];
            if (!valid_rack(rack))
                return "bad rack";
            return board_error(initial_rows(job), rack);
        }
        if (kind == "VALIDATE")
            return board_error(initial_rows(job), "");
        if (!valid_number(header[2], 1, 2147483646))
            return "bad seed";
        if (job.size() - 1 < 2 || job.size() - 1 > 4)
            return "bad player count " + std::to_string(job.size() - 1);
        std::set<std::string> names;
        for (int i = 1; i < int(job.size()); ++i) {
            Names row = split(job[i]);
            if (!valid_name(row[1]) || !strategy(row[2]) ||
                (kind == "GAME" && !valid_number(row[3], 0, 99)))
                return "bad player " + std::to_string(i);
            if (!names.insert(row[1]).second)
                return "duplicate player " + std::to_string(i);
        }
        return "";
    }
    int leave_value(const std::string &rack) const {
        Counts tally{};
        int total = 0, vowels = 0, consonants = 0, duplicates = 0;
        for (char tile : rack) {
            int index = tile_index(tile);
            ++tally[index];
            total += weights[index];
            if (tile != '?') {
                if (std::string("AEIOU").find(tile) != std::string::npos)
                    ++vowels;
                else
                    ++consonants;
            }
        }
        for (int tile = 0; tile < 26; ++tile)
            duplicates += std::max(0, tally[tile] - 1);
        return total - 4 * duplicates - 3 * std::max(0, std::abs(vowels - consonants) - 1);
    }
    std::string best_leave(const std::string &rack) const {
        std::set<std::string> candidates;
        for (int mask = 0; mask < (1 << int(rack.size())) - 1; ++mask) {
            std::string candidate;
            for (int i = 0; i < int(rack.size()); ++i)
                if (mask & (1 << i))
                    candidate += rack[i];
            std::sort(candidate.begin(), candidate.end());
            candidates.insert(candidate);
        }
        std::string best;
        int maximum = leave_value(best);
        for (const std::string &candidate : candidates) {
            int value = leave_value(candidate);
            if (value > maximum ||
                (value == maximum && (candidate.size() > best.size() ||
                                      (candidate.size() == best.size() && candidate < best)))) {
                best = candidate;
                maximum = value;
            }
        }
        return best;
    }
    Evaluated evaluate(const Board &board, const std::string &rack, const Move &move) const {
        Scored scored = score_move(board, move, values);
        std::string removed;
        for (const Tile &tile : scored.tiles)
            removed += upper(tile.letter) ? tile.letter : '?';
        std::string leave = remove_tiles(rack, removed);
        Names words;
        for (const auto &word : scored.words)
            words.push_back(word.first.word + ":" + std::to_string(word.second));
        return {move,        scored.score, std::move(scored.tiles),
                join(words), leave,        leave_value(leave)};
    }
    std::vector<Evaluated> legal_moves(const Board &board, const std::string &rack) const {
        std::vector<Evaluated> out;
        for (const Move &move : generate(board, rack, trie))
            out.push_back(evaluate(board, rack, move));
        std::sort(out.begin(), out.end(), standard_before);
        return out;
    }
    const Evaluated &choose(const std::vector<Evaluated> &moves, const std::string &order) const {
        return *std::min_element(
            moves.begin(), moves.end(),
            [&](const Evaluated &a, const Evaluated &b) { return strategy_before(a, b, order); });
    }
    std::string position_summary(const Board &board) const {
        auto words = board_words(board);
        auto tiles = board_tiles(board);
        std::string longest = "-";
        std::size_t length = 0;
        int blanks = 0;
        std::map<char, int> used;
        for (const Move &word : words)
            if (word.word.size() > length) {
                longest = word.word;
                length = word.word.size();
            }
        for (const Tile &tile : tiles) {
            blanks += lower(tile.letter);
            ++used[premiums[tile.row][tile.column]];
        }
        Lines out;
        line(out, "position tiles=", tiles.size(), " words=", words.size(), " longest=", longest,
             " blanks=", blanks, " premiums=TW:", used['#'], ",DW:", used['*'], ",TL:", used['^'],
             ",DL:", used['+']);
        return out[0];
    }
    void append_board(Lines &out, const Board &board) const {
        out.push_back(position_summary(board));
        Lines image = display(board);
        out.insert(out.end(), image.begin(), image.end());
    }
    Lines topn(const Lines &job) {
        Names header = split(job[0]);
        const std::string &name = header[1], &order = header[3];
        int count = std::stoi(header[2]);
        std::string rack = split(job[1])[1];
        Board board = from_rows(initial_rows(job));
        auto moves = legal_moves(board, rack);
        auto shown = moves;
        std::sort(shown.begin(), shown.end(), [&](const Evaluated &a, const Evaluated &b) {
            return strategy_before(a, b, order);
        });
        if (shown.size() > std::size_t(count))
            shown.resize(count);
        std::string unknown = unseen(board, rack);
        Squares anchor_squares = anchors(board);
        std::array<Checks, 2> checks = {cross_checks(board, trie),
                                        cross_checks(transpose(board), trie)};
        std::array<std::string, 2> check_text;
        for (int direction = 0; direction < 2; ++direction) {
            int empty = 0, elements = 0;
            for (const auto &entry : checks[direction]) {
                empty += entry.second == 0;
                for (int letter = 0; letter < 26; ++letter)
                    elements += (entry.second >> letter) & 1;
            }
            check_text[direction] = std::to_string(checks[direction].size()) + "," +
                                    std::to_string(empty) + "," + std::to_string(elements);
        }
        int vowels = 0, consonants = 0, blanks = 0;
        for (char tile : rack) {
            if (tile == '?')
                ++blanks;
            else if (std::string("AEIOU").find(tile) != std::string::npos)
                ++vowels;
            else
                ++consonants;
        }
        int across = 0, bingos = 0, blank_moves = 0;
        std::array<std::optional<int>, 8> best_scores{};
        for (const Evaluated &move : moves) {
            across += move.move.direction == 0;
            bingos += move.tiles.size() == 7;
            blank_moves += std::any_of(move.tiles.begin(), move.tiles.end(),
                                       [](const Tile &tile) { return lower(tile.letter); });
            auto &best = best_scores[move.tiles.size()];
            if (!best || move.score > *best)
                best = move.score;
        }
        Lines out;
        line(out, "TOPN ", name, " n=", count, " order=", order, " rack=", collection(rack));
        line(out, "board tiles=", board_tiles(board).size(), " anchors=", anchor_squares.size());
        line(out, "unseen count=", unknown.size(), " tiles=", collection(unknown));
        line(out, "rack vowels=", vowels, " consonants=", consonants, " blanks=", blanks,
             " value=", points(rack, values));
        line(out, "checks across=", check_text[0], " down=", check_text[1]);
        line(out, "moves total=", moves.size(), " across=", across, " down=", moves.size() - across,
             " bingos=", bingos, " blanks=", blank_moves);
        std::ostringstream by_tiles;
        by_tiles << "best_by_tiles";
        for (int tiles = 1; tiles <= 7; ++tiles)
            by_tiles << ' ' << tiles << '='
                     << (best_scores[tiles] ? std::to_string(*best_scores[tiles]) : "-");
        out.push_back(by_tiles.str());
        std::string keep = best_leave(rack);
        line(out, "exchange keep=", collection(keep), " value=", leave_value(keep));
        Names anagrams = trie.anagrams(rack);
        std::sort(anagrams.begin(), anagrams.end(), [](const std::string &a, const std::string &b) {
            return a.size() != b.size() ? a.size() > b.size() : a < b;
        });
        Names first(anagrams.begin(),
                    anagrams.begin() + std::min<std::size_t>(10, anagrams.size()));
        line(out, "anagrams total=", anagrams.size(), " top=", first.empty() ? "-" : join(first));
        for (const Move &word : board_words(board))
            if (word.word.size() >= 3) {
                std::string front, back, capital = uppercase(word.word);
                for (int letter = 0; letter < 26; ++letter) {
                    if (trie.contains(char('A' + letter) + capital))
                        front += char('A' + letter);
                    if (trie.contains(capital + char('A' + letter)))
                        back += char('A' + letter);
                }
                if (!front.empty() || !back.empty())
                    line(out, "hook ", position(word), " ", word.word,
                         " front=", front.empty() ? "-" : front,
                         " back=", back.empty() ? "-" : back);
            }
        std::vector<int> nets;
        if (!unknown.empty() && unknown.size() <= 7 && !shown.empty()) {
            for (const Evaluated &move : shown) {
                auto reply = legal_moves(apply_tiles(board, move.tiles), unknown);
                nets.push_back(move.score - (reply.empty() ? 0 : reply[0].score));
            }
            int best = int(std::max_element(nets.begin(), nets.end()) - nets.begin());
            line(out, "endgame opponent=", collection(unknown), " best=", best + 1,
                 " net=", nets[best]);
        }
        for (int i = 0; i < int(shown.size()); ++i) {
            const Evaluated &move = shown[i];
            std::ostringstream row;
            row << i + 1 << ' ' << notation(move) << " score=" << move.score
                << " tiles=" << move.tiles.size() << " leave=" << collection(move.leave)
                << " value=" << move.value;
            if (!nets.empty())
                row << " net=" << nets[i];
            row << " words=" << move.words;
            out.push_back(row.str());
        }
        topn_totals.moves += int(moves.size());
        topn_totals.bingos += bingos;
        return out;
    }
    std::pair<std::string, std::optional<Move>> record_error(const Board &board,
                                                             const std::string &player,
                                                             const std::string &rack,
                                                             const Names &action) const {
        auto invalid = [](std::string reason) {
            return std::make_pair(reason, std::optional<Move>{});
        };
        if (!valid_name(player))
            return invalid("bad player");
        if (!valid_rack(rack))
            return invalid("bad rack");
        std::string reason = tile_error(board, rack);
        if (!reason.empty())
            return invalid(reason);
        if (action.size() == 1 && action[0] == "PASS")
            return invalid("");
        if (action[0] == "EXCHANGE") {
            const std::string &returned = action[1];
            if (!valid_rack(returned))
                return invalid("bad exchange");
            Counts available{}, requested{};
            for (char tile : rack)
                ++available[tile_index(tile)];
            for (char tile : returned)
                ++requested[tile_index(tile)];
            for (char tile : returned)
                if (requested[tile_index(tile)] > available[tile_index(tile)])
                    return invalid(std::string("rack lacks ") + tile);
            return invalid("");
        }
        auto parsed = parse_position(action[0]);
        if (!parsed)
            return invalid("bad position");
        const std::string &word = action[1];
        if (word.size() < 2 || word.size() > 15 ||
            std::any_of(word.begin(), word.end(),
                        [](char letter) { return !upper(letter) && !lower(letter); }))
            return invalid("bad word");
        Move move = *parsed;
        move.word = word;
        Placement cells = squares(move);
        for (const Tile &tile : cells)
            if (!inside(tile.row, tile.column))
                return invalid("off board");
        for (const Tile &tile : cells)
            if (board[tile.row][tile.column] != '.' && board[tile.row][tile.column] != tile.letter)
                return invalid("mismatch at " + square_name(tile.row, tile.column));
        int dr = move.direction, dc = 1 - move.direction;
        std::array<std::pair<int, int>, 2> boundary = {
            {{move.row - dr, move.column - dc},
             {move.row + dr * int(word.size()), move.column + dc * int(word.size())}}};
        for (auto point : boundary)
            if (inside(point.first, point.second) && board[point.first][point.second] != '.')
                return invalid("not whole word");
        Placement tiles = placement(board, move);
        if (tiles.empty())
            return invalid("no new tiles");
        Counts available{};
        for (char tile : rack)
            ++available[tile_index(tile)];
        for (const Tile &tile : tiles) {
            int index = tile_index(tile.letter);
            if (!available[index])
                return invalid(std::string("rack lacks ") + tile_order[index]);
            --available[index];
        }
        if (board_tiles(board).empty()) {
            if (std::none_of(tiles.begin(), tiles.end(),
                             [](const Tile &tile) { return tile.row == 7 && tile.column == 7; }))
                return invalid("center not covered");
        } else {
            bool touches = false;
            for (const Tile &tile : tiles)
                for (auto point : neighbors(tile.row, tile.column))
                    if (board[point.first][point.second] != '.')
                        touches = true;
            if (!touches)
                return invalid("not connected");
        }
        std::vector<Move> formed{move};
        auto cross = cross_words(board, move);
        formed.insert(formed.end(), cross.begin(), cross.end());
        for (const Move &item : formed)
            if (!trie.contains(uppercase(item.word)))
                return invalid("unknown word " + item.word + " at " + position(item));
        return {"", move};
    }
    Lines validate(const Lines &job) {
        Lines out;
        line(out, "VALIDATE ", split(job[0])[1]);
        Board board = from_rows(initial_rows(job));
        struct Player {
            std::string name;
            int moves = 0, valid = 0, score = 0, loss = 0;
        };
        std::vector<Player> players;
        int valid = 0, invalid = 0, score = 0, best_total = 0, loss = 0;
        for (int i = 17; i < int(job.size()); ++i) {
            Names row = split(job[i]), action(row.begin() + 3, row.end());
            const std::string &player = row[1], &rack = row[2];
            std::string prefix =
                "move " + std::to_string(i - 16) + " " + player + " " + join(action, " ");
            auto checked = record_error(board, player, rack, action);
            Player *statistics = nullptr;
            if (checked.first != "bad player") {
                auto found = std::find_if(players.begin(), players.end(),
                                          [&](const Player &item) { return item.name == player; });
                if (found == players.end()) {
                    players.push_back({player});
                    statistics = &players.back();
                } else
                    statistics = &*found;
                ++statistics->moves;
            }
            if (!checked.first.empty()) {
                line(out, prefix, " invalid ", checked.first);
                ++invalid;
                continue;
            }
            auto legal = legal_moves(board, rack);
            int best = legal.empty() ? 0 : legal[0].score, earned = 0, rank = 0;
            std::optional<Evaluated> played;
            if (checked.second) {
                played = evaluate(board, rack, *checked.second);
                earned = played->score;
                auto target = placement_key(played->tiles);
                for (int j = 0; j < int(legal.size()); ++j)
                    if (placement_key(legal[j].tiles) == target) {
                        rank = j + 1;
                        break;
                    }
            }
            ++statistics->valid;
            statistics->score += earned;
            statistics->loss += best - earned;
            ++valid;
            score += earned;
            best_total += best;
            loss += best - earned;
            if (!played)
                line(out, prefix, " score=0 total=", statistics->score, " moves=", legal.size(),
                     " best=", best);
            else {
                line(out, prefix, " score=", earned, " total=", statistics->score,
                     " tiles=", played->tiles.size(), " rank=", rank, "/", legal.size(),
                     " best=", best, " words=", played->words);
                board = apply_tiles(board, played->tiles);
            }
        }
        for (const Player &player : players)
            line(out, "player ", player.name, " moves=", player.moves, " valid=", player.valid,
                 " score=", player.score, " loss=", player.loss);
        line(out, "total valid=", valid, " invalid=", invalid, " score=", score,
             " best=", best_total, " loss=", loss);
        append_board(out, board);
        validation_totals.moves += int(job.size()) - 17;
        validation_totals.valid += valid;
        validation_totals.invalid += invalid;
        validation_totals.loss += loss;
        return out;
    }
    Lines ordinary_game(const Lines &job) {
        Names header = split(job[0]);
        Minstd random{std::stoll(header[2])};
        std::string bag = make_bag(counts, random);
        Board board = empty_board();
        struct Player {
            std::string name, strategy, rack;
            int threshold, score = 0, plays = 0, bingos = 0, exchanges = 0, passes = 0, top = 0,
                           loss = 0;
        };
        std::vector<Player> players;
        Lines out;
        line(out, "GAME ", header[1], " seed=", header[2], " players=", job.size() - 1);
        for (int i = 1; i < int(job.size()); ++i) {
            Names row = split(job[i]);
            players.push_back({row[1], row[2], draw(bag, 7), std::stoi(row[3])});
            line(out, "player ", i, " ", row[1], " strategy=", row[2], " threshold=", row[3]);
        }
        int turn = 0, consecutive = 0;
        std::optional<int> outgoing;
        struct Highlight {
            int turn, player;
            Evaluated move;
        };
        std::optional<Highlight> highlight;
        for (;;) {
            int index = turn % int(players.size());
            Player &player = players[index];
            ++turn;
            std::string rack = player.rack;
            auto legal = legal_moves(board, rack);
            std::optional<Evaluated> candidate;
            if (!legal.empty())
                candidate = choose(legal, player.strategy);
            std::string prefix = "turn " + std::to_string(turn) + " " + player.name +
                                 " rack=" + collection(rack) +
                                 " moves=" + std::to_string(legal.size());
            if (candidate && !(candidate->score < player.threshold && bag.size() >= 7)) {
                const Evaluated &move = *candidate;
                board = apply_tiles(board, move.tiles);
                player.score += move.score;
                std::string drawn = draw(bag, 7 - int(move.leave.size()));
                player.rack = move.leave + drawn;
                ++player.plays;
                player.bingos += move.tiles.size() == 7;
                player.top = std::max(player.top, move.score);
                player.loss += legal[0].score - move.score;
                consecutive = 0;
                if (!highlight || move.score > highlight->move.score)
                    highlight = Highlight{turn, index, move};
                line(out, prefix, " best=", legal[0].score, " play ", notation(move),
                     " score=", move.score, " total=", player.score, " draw=", collection(drawn),
                     " bag=", bag.size());
                if (player.rack.empty() && bag.empty()) {
                    outgoing = index;
                    break;
                }
            } else if (bag.size() >= 7) {
                std::string keep = best_leave(rack), returned = remove_tiles(rack, keep),
                            drawn = exchange(bag, returned, random);
                player.rack = keep + drawn;
                ++player.exchanges;
                ++consecutive;
                line(out, prefix, " exchange keep=", collection(keep), " draw=", collection(drawn),
                     " bag=", bag.size());
            } else {
                ++player.passes;
                ++consecutive;
                line(out, prefix, " pass bag=", bag.size());
            }
            if (consecutive == 6)
                break;
        }
        if (outgoing)
            line(out, "end reason=out player=", players[*outgoing].name, " turns=", turn);
        else
            line(out, "end reason=scoreless turns=", turn);
        std::vector<int> adjustments, final_scores;
        for (const Player &player : players)
            adjustments.push_back(-points(player.rack, values));
        if (outgoing) {
            adjustments[*outgoing] = 0;
            for (int i = 0; i < int(players.size()); ++i)
                if (i != *outgoing)
                    adjustments[*outgoing] += points(players[i].rack, values);
        }
        for (int i = 0; i < int(players.size()); ++i) {
            const Player &player = players[i];
            int adjustment = adjustments[i], total = player.score + adjustment;
            final_scores.push_back(total);
            line(out, "final ", player.name, " score=", player.score,
                 " rack=", collection(player.rack), " adjust=", adjustment > 0 ? "+" : "",
                 adjustment, " total=", total);
        }
        std::vector<int> standings(players.size());
        std::iota(standings.begin(), standings.end(), 0);
        std::stable_sort(standings.begin(), standings.end(),
                         [&](int a, int b) { return final_scores[a] > final_scores[b]; });
        for (int i = 0; i < int(standings.size()); ++i) {
            int index = standings[i];
            const Player &player = players[index];
            line(out, "standing ", i + 1, " ", player.name, " total=", final_scores[index],
                 " plays=", player.plays, " bingos=", player.bingos,
                 " exchanges=", player.exchanges, " passes=", player.passes, " top=", player.top,
                 " loss=", player.loss);
        }
        Names winners;
        int maximum = *std::max_element(final_scores.begin(), final_scores.end());
        for (int i = 0; i < int(players.size()); ++i)
            if (final_scores[i] == maximum)
                winners.push_back(players[i].name);
        line(out, "winner ", join(winners));
        if (highlight)
            line(out, "highlight turn=", highlight->turn,
                 " player=", players[highlight->player].name, " play ", notation(highlight->move),
                 " score=", highlight->move.score);
        append_board(out, board);
        game_totals.turns += turn;
        for (const Player &player : players) {
            game_totals.plays += player.plays;
            game_totals.exchanges += player.exchanges;
            game_totals.passes += player.passes;
            game_totals.bingos += player.bingos;
        }
        return out;
    }
    Lines duplicate_game(const Lines &job) {
        Names header = split(job[0]);
        Minstd random{std::stoll(header[2])};
        std::string bag = make_bag(counts, random), rack = draw(bag, 7);
        Board board = empty_board();
        std::vector<Names> players;
        std::vector<int> totals(job.size() - 1);
        Lines out;
        line(out, "DUPLICATE ", header[1], " seed=", header[2], " players=", job.size() - 1);
        for (int i = 1; i < int(job.size()); ++i) {
            Names row = split(job[i]);
            players.push_back({row[1], row[2]});
            line(out, "player ", i, " ", row[1], " strategy=", row[2]);
        }
        int round = 0, master_total = 0;
        bool went_out = false;
        for (;;) {
            auto legal = legal_moves(board, rack);
            if (legal.empty())
                break;
            ++round;
            const Evaluated &master = legal[0];
            Names picks;
            for (int i = 0; i < int(players.size()); ++i) {
                int score = choose(legal, players[i][1]).score;
                totals[i] += score;
                picks.push_back(std::to_string(score));
            }
            master_total += master.score;
            line(out, "round ", round, " rack=", collection(rack), " moves=", legal.size(),
                 " master ", notation(master), " score=", master.score, " picks=", join(picks));
            board = apply_tiles(board, master.tiles);
            rack = master.leave + draw(bag, 7 - int(master.leave.size()));
            if (rack.empty()) {
                went_out = true;
                break;
            }
        }
        if (went_out)
            line(out, "end reason=out rounds=", round);
        else
            line(out, "end reason=stuck rounds=", round, " rack=", collection(rack));
        line(out, "master total=", master_total);
        Names winners;
        int maximum = *std::max_element(totals.begin(), totals.end());
        for (int i = 0; i < int(players.size()); ++i) {
            line(out, "final ", players[i][0], " total=", totals[i],
                 " percent=", master_total >= 1 ? 100 * totals[i] / master_total : 0);
            if (totals[i] == maximum)
                winners.push_back(players[i][0]);
        }
        line(out, "winner ", join(winners));
        append_board(out, board);
        game_totals.rounds += round;
        return out;
    }
    void read_inputs() {
        std::ifstream tiles("input/tiles.txt");
        std::string text;
        while (std::getline(tiles, text))
            if (!text.empty() && text[0] != '#') {
                std::istringstream row(text);
                char tile;
                int value, count, weight;
                row >> tile >> value >> count >> weight;
                int index = tile_index(tile);
                values[index] = value;
                counts[index] = count;
                weights[index] = weight;
            }
        std::ifstream dictionary("input/dictionary.txt");
        int candidates = 0, skipped = 0, duplicates = 0;
        std::array<int, 16> lengths{};
        while (std::getline(dictionary, text)) {
            if (text.empty() || text[0] == '#')
                continue;
            ++candidates;
            if (text.size() < 2 || text.size() > 15 ||
                std::any_of(text.begin(), text.end(), [](char letter) { return !upper(letter); }))
                ++skipped;
            else if (trie.add(text))
                ++lengths[text.size()];
            else
                ++duplicates;
        }
        line(dictionary_lines, "DICTIONARY lines=", candidates, " words=", trie.words,
             " skipped=", skipped, " duplicates=", duplicates, " nodes=", trie.nodes.size());
        std::ostringstream length_line;
        length_line << "lengths";
        for (int length = 2; length <= 15; ++length)
            if (lengths[length])
                length_line << ' ' << length << '=' << lengths[length];
        dictionary_lines.push_back(length_line.str());
        std::ifstream tasks("input/jobs.txt");
        Lines current;
        while (std::getline(tasks, text)) {
            if (current.empty()) {
                if (!text.empty() && text[0] != '#')
                    current.push_back(text);
            } else if (text == "END") {
                jobs.push_back(current);
                current.clear();
            } else
                current.push_back(text);
        }
    }
    void write_blocks(const std::string &name, const std::vector<Lines> &blocks) const {
        std::ofstream file("output/" + name);
        for (int i = 0; i < int(blocks.size()); ++i) {
            if (i)
                file << '\n';
            for (const std::string &text : blocks[i])
                file << text << '\n';
        }
    }

  public:
    void run() {
        read_inputs();
        std::vector<Lines> move_blocks{dictionary_lines}, validation_blocks, game_blocks;
        std::set<std::string> seen;
        for (const Lines &job : jobs) {
            Names header = split(job[0]);
            const std::string &kind = header[0], &name = header[1];
            std::vector<Lines> *destination;
            if (kind == "TOPN") {
                destination = &move_blocks;
                ++topn_totals.jobs;
            } else if (kind == "VALIDATE") {
                destination = &validation_blocks;
                ++validation_totals.jobs;
            } else {
                destination = &game_blocks;
                if (kind == "GAME")
                    ++game_totals.games;
                else
                    ++game_totals.duplicates;
            }
            std::string reason = job_error(job, seen);
            seen.insert(name);
            if (!reason.empty()) {
                destination->push_back({kind + " " + name, "error " + reason});
                if (kind == "TOPN")
                    ++topn_totals.errors;
                else if (kind == "VALIDATE")
                    ++validation_totals.errors;
                else
                    ++game_totals.errors;
            } else if (kind == "TOPN")
                destination->push_back(topn(job));
            else if (kind == "VALIDATE")
                destination->push_back(validate(job));
            else if (kind == "GAME")
                destination->push_back(ordinary_game(job));
            else
                destination->push_back(duplicate_game(job));
        }
        Lines summary;
        line(summary, "SUMMARY jobs=", topn_totals.jobs, " errors=", topn_totals.errors,
             " moves=", topn_totals.moves, " bingos=", topn_totals.bingos);
        move_blocks.push_back(summary);
        summary.clear();
        line(summary, "SUMMARY jobs=", validation_totals.jobs, " errors=", validation_totals.errors,
             " moves=", validation_totals.moves, " valid=", validation_totals.valid,
             " invalid=", validation_totals.invalid, " loss=", validation_totals.loss);
        validation_blocks.push_back(summary);
        summary.clear();
        line(summary, "SUMMARY games=", game_totals.games, " duplicates=", game_totals.duplicates,
             " errors=", game_totals.errors, " turns=", game_totals.turns,
             " rounds=", game_totals.rounds, " plays=", game_totals.plays,
             " exchanges=", game_totals.exchanges, " passes=", game_totals.passes,
             " bingos=", game_totals.bingos);
        game_blocks.push_back(summary);
        std::filesystem::create_directories("output");
        write_blocks("moves.txt", move_blocks);
        write_blocks("validation.txt", validation_blocks);
        write_blocks("game.txt", game_blocks);
    }
};
int main() { Scrabble().run(); }
