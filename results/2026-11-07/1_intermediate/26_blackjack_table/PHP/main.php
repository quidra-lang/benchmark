<?php
declare(strict_types=1);

enum Phase: string { case Idle = 'idle'; case Insurance = 'insurance'; case Play = 'play'; }
enum Action: string { case Hit = 'HIT'; case Stand = 'STAND'; case DoubleDown = 'DOUBLE'; case Split = 'SPLIT'; case Surrender = 'SURRENDER'; }
enum Finish { case Ordinary; case Bust; case Surrender; case Charlie; }
enum Outcome: string { case Blackjack = 'blackjack'; case Win = 'win'; case Charlie = 'charlie'; case Push = 'push'; case Lose = 'lose'; case Bust = 'bust'; case Surrender = 'surrender'; }

const COMMANDS = ['SHOE', 'RULE', 'RULES', 'PLAYER', 'LEAVE', 'REBUY', 'BET', 'SIDE', 'DEAL', 'INSURANCE', 'HIT', 'STAND', 'DOUBLE', 'SPLIT', 'SURRENDER', 'HINT', 'AUTO', 'STATUS', 'COUNT', 'STATS'];
const IDLE_COMMANDS = ['SHOE', 'RULE', 'PLAYER', 'LEAVE', 'REBUY', 'BET', 'SIDE', 'DEAL'];
const PLAYER_COMMANDS = ['LEAVE', 'REBUY', 'BET', 'SIDE', 'INSURANCE', 'HIT', 'STAND', 'DOUBLE', 'SPLIT', 'SURRENDER', 'AUTO'];
final class CommandError extends RuntimeException {}

function integerWord(string $word, int $low, int $high): int
{
    if (preg_match('/\A(?:0|[1-9][0-9]{0,9})\z/', $word) !== 1) throw new CommandError("bad value $word");
    $value = (int)$word;
    if ($value < $low || $value > $high) throw new CommandError("bad value $word");
    return $value;
}
function choiceWord(string $word, array $choices): string
{
    if (!in_array($word, $choices, true)) throw new CommandError("bad value $word");
    return $word;
}
function signed(int $value): string { return ($value >= 0 ? '+' : '') . $value; }
function switchText(bool $value): string { return $value ? 'ON' : 'OFF'; }

final class Rules
{
    public string $dealer = 'S17', $blackjack = '3:2', $doubling = 'ANY';
    public int $penetration = 75, $minimum = 10, $maximum = 500, $hands = 4, $charlie = 0, $sideMaximum = 25;
    public bool $doubleAfterSplit = true, $resplitAces = false, $surrender = true;

    public function changed(string $name, string $word): self
    {
        $next = clone $this;
        switch ($name) {
            case 'DEALER': $next->dealer = choiceWord($word, ['S17', 'H17']); break;
            case 'PEN': $next->penetration = integerWord($word, 50, 90); break;
            case 'MIN': $next->minimum = integerWord($word, 1, 10000); break;
            case 'MAX': $next->maximum = integerWord($word, 1, 10000); break;
            case 'BJ': $next->blackjack = choiceWord($word, ['3:2', '6:5']); break;
            case 'DAS': $next->doubleAfterSplit = choiceWord($word, ['ON', 'OFF']) === 'ON'; break;
            case 'DOUBLE': $next->doubling = choiceWord($word, ['ANY', '9-11', '10-11']); break;
            case 'HANDS': $next->hands = integerWord($word, 1, 4); break;
            case 'RSA': $next->resplitAces = choiceWord($word, ['ON', 'OFF']) === 'ON'; break;
            case 'SURRENDER': $next->surrender = choiceWord($word, ['ON', 'OFF']) === 'ON'; break;
            case 'CHARLIE':
                $next->charlie = integerWord($word, 0, 7);
                if (!in_array($next->charlie, [0, 5, 6, 7], true)) throw new CommandError("bad value $word");
                break;
            case 'SIDEMAX': $next->sideMaximum = integerWord($word, 0, 1000); break;
            default: throw new CommandError("unknown rule $name");
        }
        return $next;
    }
    public function fields(): array
    {
        return [
            'DEALER' => $this->dealer, 'PEN' => $this->penetration, 'MIN' => $this->minimum,
            'MAX' => $this->maximum, 'BJ' => $this->blackjack, 'DAS' => switchText($this->doubleAfterSplit),
            'DOUBLE' => $this->doubling, 'HANDS' => $this->hands, 'RSA' => switchText($this->resplitAces),
            'SURRENDER' => switchText($this->surrender), 'CHARLIE' => $this->charlie, 'SIDEMAX' => $this->sideMaximum,
        ];
    }
}

final readonly class Card
{
    public function __construct(public int $code) {}
    public function rank(): int { return $this->code % 13; }
    public function point(): int { return min(10, $this->rank() + 1); }
    public function black(): bool { return in_array(intdiv($this->code, 13), [0, 3], true); }
    public function count(): int
    {
        $point = $this->point();
        return $point >= 2 && $point <= 6 ? 1 : ($point >= 7 && $point <= 9 ? 0 : -1);
    }
    public function __toString(): string { return 'A23456789TJQK'[$this->rank()] . 'CDHS'[intdiv($this->code, 13)]; }
}
final readonly class Total
{
    public function __construct(public int $value, public bool $soft) {}
}
final class Hand
{
    public ?Finish $finish = null;
    public function __construct(public array $cards = [], public int $bet = 0, public bool $split = false, public bool $splitAces = false) {}
    public function total(): Total
    {
        $sum = 0;
        $ace = false;
        foreach ($this->cards as $card) {
            $sum += $card->point();
            $ace = $ace || $card->rank() === 0;
        }
        $soft = $ace && $sum + 10 <= 21;
        return new Total($sum + ($soft ? 10 : 0), $soft);
    }
    public function blackjack(): bool { return !$this->split && count($this->cards) === 2 && $this->total()->value === 21; }
    public function __toString(): string
    {
        $total = $this->total();
        $status = $this->blackjack() ? 'blackjack' : ($total->value > 21 ? "bust $total->value" : ($total->soft ? "soft $total->value" : (string)$total->value));
        return implode(' ', $this->cards) . " ($status)";
    }
    public function check(Rules $rules, int $handCount): void
    {
        $total = $this->total()->value;
        if ($total > 21) $this->finish = Finish::Bust;
        elseif ($rules->charlie !== 0 && count($this->cards) === $rules->charlie) $this->finish = Finish::Charlie;
        elseif ($total === 21) $this->finish = Finish::Ordinary;
        elseif ($this->splitAces && count($this->cards) === 2) {
            $again = $this->cards[0]->rank() === 0 && $this->cards[1]->rank() === 0 && $rules->resplitAces && $handCount < $rules->hands;
            if (!$again) $this->finish = Finish::Ordinary;
        }
    }
}
final class Player
{
    public int $bet = 0, $side = 0, $insurance = 0, $net = 0;
    public array $hands = [];
    public array $stats = ['rounds' => 0, 'hands' => 0, 'wins' => 0, 'losses' => 0, 'pushes' => 0, 'blackjacks' => 0, 'busts' => 0, 'surrenders' => 0, 'doubles' => 0, 'splits' => 0];
    public function __construct(public readonly string $name, public int $bankroll) {}
    public function handName(int $index): string { return $this->name . '[' . ($index + 1) . ']'; }
}

final class Table
{
    private Rules $rules;
    private array $players;
    private Phase $phase = Phase::Idle;
    private int $round = 0, $decks = 0, $random = 1, $drawn = 0, $running = 0;
    private array $shoe = [], $participants = [], $output = [];
    private int $insuranceTurn = 0, $currentSeat = -1, $currentHand = 0;
    private Hand $dealer;
    private bool $holeVisible = false, $dealerNatural = false;
    private int $dealerBlackjacks = 0, $dealerBusts = 0;

    public function __construct()
    {
        $this->rules = new Rules();
        $this->players = array_fill(0, 7, null);
        $this->dealer = new Hand();
    }
    private function say(string $line): void { $this->output[] = $line; }
    private function findPlayer(string $name): int
    {
        foreach ($this->players as $seat => $player) if ($player !== null && $player->name === $name) return $seat;
        return -1;
    }
    private function lookup(string $name): int
    {
        $seat = $this->findPlayer($name);
        if ($seat < 0) throw new CommandError("unknown player $name");
        return $seat;
    }
    private function player(int $seat): Player { return $this->players[$seat]; }
    private function current(): Hand { return $this->player($this->currentSeat)->hands[$this->currentHand]; }
    private function currentName(): string { return $this->player($this->currentSeat)->handName($this->currentHand); }
    private function cut(): int { return intdiv(count($this->shoe) * $this->rules->penetration, 100); }
    private function shuffle(): void
    {
        $this->shoe = [];
        for ($i = 0; $i < 52 * $this->decks; $i++) $this->shoe[] = new Card($i % 52);
        for ($i = count($this->shoe) - 1; $i > 0; $i--) {
            $this->random = 48271 * $this->random % 2147483647;
            $j = $this->random % ($i + 1);
            [$this->shoe[$i], $this->shoe[$j]] = [$this->shoe[$j], $this->shoe[$i]];
        }
        $this->drawn = $this->running = 0;
    }
    private function draw(bool $visible = true): Card
    {
        $card = $this->shoe[$this->drawn++];
        if ($visible) $this->running += $card->count();
        return $card;
    }
    private function revealDealer(): void
    {
        if (!$this->holeVisible) {
            $this->running += $this->dealer->cards[1]->count();
            $this->holeVisible = true;
        }
        $this->say('dealer: ' . $this->dealer);
    }
    private function result(Hand $hand): Outcome
    {
        if ($this->dealerNatural) return $hand->blackjack() ? Outcome::Push : Outcome::Lose;
        if ($hand->blackjack()) return Outcome::Blackjack;
        if ($hand->finish === Finish::Bust) return Outcome::Bust;
        if ($hand->finish === Finish::Surrender) return Outcome::Surrender;
        if ($hand->finish === Finish::Charlie) return Outcome::Charlie;
        $own = $hand->total()->value;
        $dealer = $this->dealer->total()->value;
        return $dealer > 21 || $own > $dealer ? Outcome::Win : ($own === $dealer ? Outcome::Push : Outcome::Lose);
    }
    private function profit(int $bet, Outcome $outcome): int
    {
        return match ($outcome) {
            Outcome::Blackjack => $this->rules->blackjack === '3:2' ? intdiv($bet * 3, 2) : intdiv($bet * 6, 5),
            Outcome::Win, Outcome::Charlie => $bet,
            Outcome::Push => 0,
            Outcome::Surrender => intdiv($bet, 2) - $bet,
            Outcome::Lose, Outcome::Bust => -$bet,
        };
    }
    private function settle(): void
    {
        foreach ($this->participants as $seat) {
            $player = $this->player($seat);
            foreach ($player->hands as $index => $hand) {
                $outcome = $this->result($hand);
                $profit = $this->profit($hand->bet, $outcome);
                $player->bankroll += $hand->bet + $profit;
                $player->net += $profit;
                $player->stats['hands']++;
                $field = match ($outcome) {
                    Outcome::Blackjack, Outcome::Win, Outcome::Charlie => 'wins',
                    Outcome::Push => 'pushes',
                    default => 'losses',
                };
                $player->stats[$field]++;
                $special = match ($outcome) {
                    Outcome::Blackjack => 'blackjacks', Outcome::Bust => 'busts', Outcome::Surrender => 'surrenders', default => null,
                };
                if ($special !== null) $player->stats[$special]++;
                $this->say($player->handName($index) . " {$outcome->value} " . signed($profit));
            }
            $this->say("$player->name bankroll $player->bankroll");
        }
        foreach ($this->players as $player) if ($player !== null) $player->bet = $player->side = 0;
        $this->phase = Phase::Idle;
    }
    private function dealerTurn(): void
    {
        $this->revealDealer();
        $required = false;
        foreach ($this->participants as $seat) {
            foreach ($this->player($seat)->hands as $hand) {
                if ($hand->finish === Finish::Ordinary && !$hand->blackjack()) $required = true;
            }
        }
        $drew = false;
        if ($required) {
            while (true) {
                $total = $this->dealer->total();
                if ($total->value > 16 && !($total->value === 17 && $total->soft && $this->rules->dealer === 'H17')) break;
                $this->dealer->cards[] = $this->draw();
                $this->say('dealer hits: ' . $this->dealer);
                $drew = true;
            }
        }
        if ($drew && $this->dealer->total()->value > 21) $this->dealerBusts++;
        $this->settle();
    }
    private function advanceHands(): void
    {
        while (true) {
            $next = null;
            foreach ($this->participants as $seat) {
                foreach ($this->player($seat)->hands as $index => $hand) {
                    if ($hand->finish === null) { $next = [$seat, $index]; break 2; }
                }
            }
            if ($next === null) { $this->dealerTurn(); return; }
            [$this->currentSeat, $this->currentHand] = $next;
            $hand = $this->current();
            if (count($hand->cards) !== 1) return;
            $hand->cards[] = $this->draw();
            $this->say($this->currentName() . ': ' . $hand);
            $hand->check($this->rules, count($this->player($this->currentSeat)->hands));
            if ($hand->finish === null) return;
        }
    }
    private function peek(): void
    {
        $this->dealerNatural = $this->dealer->blackjack();
        $this->say('dealer peeks: ' . ($this->dealerNatural ? 'blackjack' : 'no blackjack'));
        foreach ($this->participants as $seat) {
            $player = $this->player($seat);
            if ($player->insurance === 0) continue;
            $profit = $this->dealerNatural ? $player->insurance * 2 : -$player->insurance;
            $player->bankroll += $player->insurance + $profit;
            $player->net += $profit;
            $this->say("$player->name insurance " . signed($profit));
        }
        if ($this->dealerNatural) {
            $this->dealerBlackjacks++;
            $this->revealDealer();
            $this->settle();
        } else {
            $this->phase = Phase::Play;
            $this->advanceHands();
        }
    }
    private function deal(): void
    {
        if ($this->drawn >= $this->cut()) { $this->shuffle(); $this->say('shuffle'); }
        $this->round++;
        $this->say("round $this->round");
        $this->participants = [];
        foreach ($this->players as $seat => $player) {
            if ($player === null || $player->bet === 0) continue;
            $this->participants[] = $seat;
            $player->bankroll -= $player->bet + $player->side;
            $player->insurance = 0;
            $player->stats['rounds']++;
            $player->hands = [new Hand(bet: $player->bet)];
        }
        foreach ($this->participants as $seat) $this->player($seat)->hands[0]->cards[] = $this->draw();
        $this->dealer = new Hand([$this->draw()]);
        foreach ($this->participants as $seat) {
            $hand = $this->player($seat)->hands[0];
            $hand->cards[] = $this->draw();
            if ($hand->blackjack()) $hand->finish = Finish::Ordinary;
        }
        $this->dealer->cards[] = $this->draw(false);
        $this->holeVisible = $this->dealerNatural = false;
        foreach ($this->participants as $seat) {
            $player = $this->player($seat);
            $this->say($player->handName(0) . ': ' . $player->hands[0]);
        }
        $this->say('dealer: ' . $this->dealer->cards[0] . ' ??');
        foreach ($this->participants as $seat) {
            $player = $this->player($seat);
            if ($player->side === 0) continue;
            [$first, $second] = $player->hands[0]->cards;
            [$result, $multiplier] = match (true) {
                $first->rank() !== $second->rank() => ['lose', -1],
                $first->code === $second->code => ['perfect', 25],
                $first->black() === $second->black() => ['colored', 12],
                default => ['mixed', 6],
            };
            $profit = $player->side * $multiplier;
            $player->bankroll += $player->side + $profit;
            $player->net += $profit;
            $this->say("$player->name side $result " . signed($profit));
        }
        $up = $this->dealer->cards[0]->point();
        if ($up === 1) {
            $this->phase = Phase::Insurance;
            $this->insuranceTurn = 0;
            $this->say('insurance offered');
        } elseif ($up === 10) $this->peek();
        else { $this->phase = Phase::Play; $this->advanceHands(); }
    }
    private function actionProblem(Action $action): ?string
    {
        $player = $this->player($this->currentSeat);
        $hand = $this->current();
        if ($action === Action::Hit) return $hand->splitAces ? 'split aces' : null;
        if ($action === Action::DoubleDown) {
            if ($hand->splitAces) return 'split aces';
            if (count($hand->cards) !== 2) return 'two cards only';
            $total = $hand->total();
            $limited = $this->rules->doubling !== 'ANY' && ($total->soft || $total->value > 11 || $total->value < ($this->rules->doubling === '9-11' ? 9 : 10));
            if ($limited || (!$this->rules->doubleAfterSplit && $hand->split)) return 'double not allowed';
            if ($player->bankroll < $hand->bet) return 'insufficient funds';
        } elseif ($action === Action::Split) {
            if (count($hand->cards) !== 2) return 'two cards only';
            if ($hand->cards[0]->point() !== $hand->cards[1]->point()) return 'not a pair';
            if (count($player->hands) >= $this->rules->hands) return 'hand limit';
            if ($player->bankroll < $hand->bet) return 'insufficient funds';
        } elseif ($action === Action::Surrender) {
            if (!$this->rules->surrender || $hand->split) return 'surrender not allowed';
            if (count($hand->cards) !== 2) return 'two cards only';
        }
        return null;
    }
    private function recommendation(): Action
    {
        $hand = $this->current();
        $canSplit = $this->actionProblem(Action::Split) === null;
        if ($hand->splitAces) return $canSplit ? Action::Split : Action::Stand;
        $up = $this->dealer->cards[0]->point();
        if ($up === 1) $up = 11;
        if ($canSplit) {
            $point = $hand->cards[0]->point();
            $wanted = in_array($point, [1, 8], true)
                || ($point === 9 && !in_array($up, [7, 10, 11], true))
                || (in_array($point, [2, 3, 7], true) && $up <= 7)
                || ($point === 6 && $up <= 6) || ($point === 4 && in_array($up, [5, 6], true));
            if ($wanted) return Action::Split;
        }
        $total = $hand->total();
        $value = $total->value;
        $canDouble = $this->actionProblem(Action::DoubleDown) === null;
        if ($total->soft) {
            if ($value >= 19) return Action::Stand;
            if ($value === 18) {
                if ($up >= 3 && $up <= 6) return $canDouble ? Action::DoubleDown : Action::Stand;
                return in_array($up, [2, 7, 8], true) ? Action::Stand : Action::Hit;
            }
            $wanted = ($value === 17 && $up >= 3 && $up <= 6)
                || (in_array($value, [15, 16], true) && $up >= 4 && $up <= 6)
                || (in_array($value, [13, 14], true) && in_array($up, [5, 6], true));
            return $wanted && $canDouble ? Action::DoubleDown : Action::Hit;
        }
        if ($value >= 17) return Action::Stand;
        if ($value >= 13) {
            if ($up <= 6) return Action::Stand;
            if ((($value === 16 && $up >= 9) || ($value === 15 && $up === 10)) && $this->actionProblem(Action::Surrender) === null) return Action::Surrender;
            return Action::Hit;
        }
        if ($value === 12) return $up >= 4 && $up <= 6 ? Action::Stand : Action::Hit;
        $wanted = ($value === 11 && $up <= 10) || ($value === 10 && $up <= 9) || ($value === 9 && $up >= 3 && $up <= 6);
        return $wanted && $canDouble ? Action::DoubleDown : Action::Hit;
    }
    private function act(Action $action): void
    {
        $player = $this->player($this->currentSeat);
        $index = $this->currentHand;
        $hand = $this->current();
        $name = $player->handName($index);
        if ($action === Action::Split) {
            $player->bankroll -= $hand->bet;
            $player->stats['splits']++;
            $this->say($name . ' splits ' . implode(' ', $hand->cards));
            $aces = $hand->splitAces || $hand->cards[0]->point() === 1;
            $first = new Hand([$hand->cards[0]], $hand->bet, true, $aces);
            $second = new Hand([$hand->cards[1]], $hand->bet, true, $aces);
            array_splice($player->hands, $index, 1, [$first, $second]);
            $first->cards[] = $this->draw();
            $this->say($name . ': ' . $first);
            $first->check($this->rules, count($player->hands));
        } elseif ($action === Action::Stand || $action === Action::Surrender) {
            $hand->finish = $action === Action::Stand ? Finish::Ordinary : Finish::Surrender;
            $verb = $action === Action::Stand ? 'stands' : 'surrenders';
            $this->say("$name $verb: " . $hand);
        } else {
            if ($action === Action::DoubleDown) {
                $player->bankroll -= $hand->bet;
                $hand->bet *= 2;
                $player->stats['doubles']++;
            }
            $hand->cards[] = $this->draw();
            $verb = $action === Action::DoubleDown ? 'doubles' : 'hits';
            $this->say("$name $verb: " . $hand);
            $hand->check($this->rules, count($player->hands));
            if ($action === Action::DoubleDown && $hand->finish === null) $hand->finish = Finish::Ordinary;
        }
        $this->advanceHands();
    }
    private function status(): void
    {
        $line = "table {$this->phase->value} round $this->round";
        if ($this->phase === Phase::Insurance) $line .= ' next ' . $this->player($this->participants[$this->insuranceTurn])->name;
        elseif ($this->phase === Phase::Play) $line .= ' turn ' . $this->currentName();
        $this->say($line);
        if ($this->phase !== Phase::Idle) $this->say('dealer: ' . $this->dealer->cards[0] . ' ??');
        foreach ($this->players as $seat => $player) {
            if ($player === null) continue;
            $this->say('seat ' . ($seat + 1) . " $player->name bankroll $player->bankroll bet $player->bet side $player->side");
            if ($this->phase !== Phase::Idle && in_array($seat, $this->participants, true)) {
                foreach ($player->hands as $index => $hand) $this->say($player->handName($index) . ': ' . $hand . " bet $hand->bet");
            }
        }
    }
    private function statistics(): void
    {
        foreach ($this->players as $player) {
            if ($player === null) continue;
            $line = "stats $player->name";
            foreach ($player->stats as $name => $value) $line .= " $name $value";
            $this->say($line . ' net ' . signed($player->net));
        }
        $this->say("stats dealer rounds $this->round blackjacks $this->dealerBlackjacks busts $this->dealerBusts");
    }
    public function execute(array $words): array
    {
        $this->output = [];
        $op = $words[0];
        if (!in_array($op, COMMANDS, true)) throw new CommandError("unknown command $op");
        $seat = -1;
        $amount = $seed = 0;
        $proposed = null;
        if ($op === 'SHOE') {
            $amount = integerWord($words[1], 1, 8);
            $seed = integerWord($words[2], 1, 2147483646);
        } elseif ($op === 'RULE') $proposed = $this->rules->changed($words[1], $words[2]);
        elseif ($op === 'PLAYER') {
            if (preg_match('/\A[A-Z]{1,8}\z/', $words[1]) !== 1) throw new CommandError("bad name $words[1]");
            $amount = integerWord($words[2], 1, 1000000);
        } elseif (in_array($op, PLAYER_COMMANDS, true)) {
            $seat = $this->lookup($words[1]);
            if (in_array($op, ['REBUY', 'BET', 'SIDE', 'INSURANCE'], true)) $amount = integerWord($words[2], $op === 'REBUY' ? 1 : 0, 1000000);
        }
        if (in_array($op, IDLE_COMMANDS, true) && $this->phase !== Phase::Idle) throw new CommandError('round in progress');
        if ($op === 'INSURANCE' && $this->phase !== Phase::Insurance) throw new CommandError('no insurance');
        $action = Action::tryFrom($op);
        $actionCommand = $action !== null || $op === 'AUTO';
        if ($actionCommand || $op === 'HINT') {
            if ($this->phase === Phase::Idle) throw new CommandError('no round');
            if ($this->phase === Phase::Insurance) throw new CommandError('insurance pending');
            if ($actionCommand && $seat !== $this->currentSeat) throw new CommandError('waiting for ' . $this->currentName());
        }
        if ($actionCommand) {
            if ($op === 'AUTO') {
                while ($this->phase === Phase::Play && $this->currentSeat === $seat) $this->act($this->recommendation());
            } else {
                $problem = $this->actionProblem($action);
                if ($problem !== null) throw new CommandError($problem);
                $this->act($action);
            }
            return $this->output;
        }
        switch ($op) {
            case 'SHOE':
                $this->decks = $amount;
                $this->random = $seed;
                $this->shuffle();
                $this->say("shoe $amount decks " . count($this->shoe) . ' cards cut ' . $this->cut());
                break;
            case 'RULE':
                if ($proposed->minimum > $proposed->maximum) throw new CommandError('min above max');
                $this->rules = $proposed;
                $this->say("rule $words[1] " . $this->rules->fields()[$words[1]]);
                break;
            case 'RULES':
                $line = 'rules';
                foreach ($this->rules->fields() as $name => $value) $line .= " $name $value";
                $this->say($line);
                break;
            case 'PLAYER':
                if ($this->findPlayer($words[1]) >= 0) throw new CommandError('player exists');
                $empty = array_search(null, $this->players, true);
                if ($empty === false) throw new CommandError('table full');
                $this->players[$empty] = new Player($words[1], $amount);
                $this->say("$words[1] sits at seat " . ($empty + 1) . " with $amount");
                break;
            case 'LEAVE':
                $player = $this->player($seat);
                $this->say("$player->name leaves with $player->bankroll net " . signed($player->net));
                $this->players[$seat] = null;
                break;
            case 'REBUY':
                $player = $this->player($seat);
                $player->bankroll += $amount;
                $this->say("$player->name rebuys $amount bankroll $player->bankroll");
                break;
            case 'BET':
                $player = $this->player($seat);
                if ($amount !== 0) {
                    if ($amount < $this->rules->minimum || $amount > $this->rules->maximum) throw new CommandError('bet out of limits');
                    if ($amount + $player->side > $player->bankroll) throw new CommandError('insufficient funds');
                }
                $player->bet = $amount;
                if ($amount === 0) { $player->side = 0; $this->say("$player->name bet cleared"); }
                else $this->say("$player->name bets $amount");
                break;
            case 'SIDE':
                $player = $this->player($seat);
                if ($amount !== 0) {
                    if ($player->bet === 0) throw new CommandError('no bet');
                    if ($amount > $this->rules->sideMaximum) throw new CommandError('side out of limits');
                    if ($player->bet + $amount > $player->bankroll) throw new CommandError('insufficient funds');
                }
                $player->side = $amount;
                $this->say($amount === 0 ? "$player->name side cleared" : "$player->name side $amount");
                break;
            case 'DEAL':
                if ($this->decks === 0) throw new CommandError('no shoe');
                if (!array_filter($this->players, static fn(?Player $player): bool => $player !== null && $player->bet !== 0)) throw new CommandError('no bets');
                $this->deal();
                break;
            case 'INSURANCE':
                $waiting = $this->participants[$this->insuranceTurn];
                if ($seat !== $waiting) throw new CommandError('waiting for ' . $this->player($waiting)->name);
                $player = $this->player($seat);
                if ($amount > intdiv($player->bet, 2)) throw new CommandError('insurance out of limits');
                if ($amount > $player->bankroll) throw new CommandError('insufficient funds');
                $player->bankroll -= $amount;
                $player->insurance = $amount;
                $this->say($amount === 0 ? "$player->name declines insurance" : "$player->name insures $amount");
                if (++$this->insuranceTurn === count($this->participants)) $this->peek();
                break;
            case 'HINT': $this->say('hint ' . $this->currentName() . ': ' . strtolower($this->recommendation()->value)); break;
            case 'STATUS': $this->status(); break;
            case 'COUNT':
                if ($this->decks === 0) throw new CommandError('no shoe');
                $remaining = count($this->shoe) - $this->drawn;
                $value = intdiv(abs($this->running) * 5200, $remaining);
                $text = ($this->running < 0 ? '-' : '') . intdiv($value, 100) . '.' . sprintf('%02d', $value % 100);
                $this->say("count running $this->running true $text remaining $remaining");
                break;
            case 'STATS':
                if (!array_filter($this->players, static fn(?Player $player): bool => $player !== null)) throw new CommandError('no players');
                $this->statistics();
                break;
        }
        return $this->output;
    }
}

$count = (int)fgets(STDIN);
$table = new Table();
for ($i = 0; $i < $count; $i++) {
    $line = fgets(STDIN);
    if ($line === false) break;
    try {
        $output = $table->execute(explode(' ', rtrim($line, "\r\n")));
        foreach ($output as $text) fwrite(STDOUT, $text . "\n");
    } catch (CommandError $problem) {
        fwrite(STDOUT, 'error: ' . $problem->getMessage() . "\n");
    }
}
