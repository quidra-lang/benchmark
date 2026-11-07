<?php

declare(strict_types=1);

const PROTOCOLS = ['SW', 'GBN', 'SR'];
const KEYS = [
    'PROTOCOL', 'FRAMES', 'WINDOW', 'SEQBITS', 'TIMEOUT', 'DELAY',
    'INTERVAL', 'MAXTICKS', 'DUPACK', 'NAK', 'BACKOFF', 'CONGESTION',
    'UNSAFE', 'TRACE', 'RANDOM', 'LOSEDATA', 'LOSECTRL', 'CORRUPTDATA',
    'CORRUPTCTRL', 'DELAYDATA', 'DELAYCTRL', 'SNAPSHOT',
];
const REQUIRED = ['PROTOCOL', 'FRAMES', 'WINDOW', 'SEQBITS', 'TIMEOUT', 'DELAY'];
const LIST_KEYS = [
    'LOSEDATA', 'LOSECTRL', 'CORRUPTDATA', 'CORRUPTCTRL',
    'DELAYDATA', 'DELAYCTRL', 'SNAPSHOT',
];
const DELAY_KEYS = ['DELAYDATA', 'DELAYCTRL'];
const CHOICES = [
    'PROTOCOL' => PROTOCOLS,
    'NAK' => ['ON', 'OFF'],
    'BACKOFF' => ['ON', 'OFF'],
    'CONGESTION' => ['ON', 'OFF'],
    'UNSAFE' => ['ON', 'OFF'],
    'TRACE' => ['ALL', 'SENDER', 'RECEIVER', 'NONE'],
];
const RANGES = [
    'FRAMES' => [1, 60], 'WINDOW' => [1, 32], 'SEQBITS' => [1, 6],
    'TIMEOUT' => [1, 50], 'DELAY' => [1, 10], 'INTERVAL' => [0, 10],
    'MAXTICKS' => [1, 2000], 'DUPACK' => [1, 10],
    'LOSEDATA' => [1, 9999], 'LOSECTRL' => [1, 9999],
    'CORRUPTDATA' => [1, 9999], 'CORRUPTCTRL' => [1, 9999],
    'SNAPSHOT' => [0, 2000],
];
const TRACE_SIDES = [
    'ALL' => ['SENDER', 'RECEIVER'],
    'SENDER' => ['SENDER'], 'RECEIVER' => ['RECEIVER'], 'NONE' => [],
];
const RANDOM_MULTIPLIER = 48271;
const RANDOM_MODULUS = 2147483647;

final class SettingsError extends RuntimeException {}

function truncated(int $numerator, int $denominator, int $digits): string
{
    $scale = 10 ** $digits;
    $value = intdiv($numerator * $scale, $denominator);
    return intdiv($value, $scale) . '.' . str_pad((string) ($value % $scale), $digits, '0', STR_PAD_LEFT);
}

function tickText(?int $tick): string
{
    return $tick === null ? '-' : (string) $tick;
}

function modulo(int $number, int $modulus): int
{
    return (($number % $modulus) + $modulus) % $modulus;
}

function option(array $settings, string $key, string $fallback): string
{
    return ($settings[$key] ?? [$fallback])[0];
}

function numberSet(array $settings, string $key): array
{
    $set = [];
    foreach ($settings[$key] ?? [] as $text) $set[(int) $text] = true;
    return $set;
}

function delayMap(array $settings, string $key): array
{
    $map = [];
    foreach ($settings[$key] ?? [] as $text) {
        [$number, $extra] = array_map('intval', explode(':', $text));
        $map[$number] = $extra;
    }
    return $map;
}

function inRange(int $value, array $bounds): bool
{
    return $value >= $bounds[0] && $value <= $bounds[1];
}

function validValue(string $key, array $values): bool
{
    if (isset(CHOICES[$key])) return in_array($values[0], CHOICES[$key], true);
    if (!in_array($key, LIST_KEYS, true) && isset(RANGES[$key])) {
        return inRange((int) $values[0], RANGES[$key]);
    }
    if ($key === 'RANDOM') {
        [$seed, $loss, $corrupt] = array_map('intval', $values);
        return inRange($seed, [1, RANDOM_MODULUS - 1]) &&
            $loss >= 0 && $corrupt >= 0 && $loss + $corrupt <= 100;
    }
    if (in_array($key, DELAY_KEYS, true)) {
        $numbers = [];
        foreach ($values as $value) {
            [$number, $extra] = array_map('intval', explode(':', $value));
            if (!inRange($number, [1, 9999]) || !inRange($extra, [1, 50])) return false;
            if (isset($numbers[$number])) return false;
            $numbers[$number] = true;
        }
        return true;
    }
    $seen = [];
    foreach ($values as $value) {
        $number = (int) $value;
        if (!inRange($number, RANGES[$key]) || isset($seen[$number])) return false;
        $seen[$number] = true;
    }
    return true;
}

final class Config
{
    public string $protocol;
    public int $frames;
    public int $window;
    public int $seqbits;
    public int $timeout;
    public int $delay;
    public int $interval;
    public int $limit;
    public ?int $dupack;
    public bool $nak;
    public bool $backoff;
    public bool $congestion;
    public bool $unsafe;
    public string $trace;
    public ?array $random;
    public array $loseData;
    public array $loseCtrl;
    public array $corruptData;
    public array $corruptCtrl;
    public array $delayData;
    public array $delayCtrl;
    public array $snapshots;

    public function __construct(array $settings)
    {
        $this->protocol = option($settings, 'PROTOCOL', '');
        $this->frames = (int) option($settings, 'FRAMES', '0');
        $this->window = (int) option($settings, 'WINDOW', '0');
        $this->seqbits = (int) option($settings, 'SEQBITS', '0');
        $this->timeout = (int) option($settings, 'TIMEOUT', '0');
        $this->delay = (int) option($settings, 'DELAY', '0');
        $this->interval = (int) option($settings, 'INTERVAL', '0');
        $this->limit = (int) option($settings, 'MAXTICKS', '1000');
        $this->dupack = isset($settings['DUPACK']) ? (int) $settings['DUPACK'][0] : null;
        $this->nak = option($settings, 'NAK', 'OFF') === 'ON';
        $this->backoff = option($settings, 'BACKOFF', 'OFF') === 'ON';
        $this->congestion = option($settings, 'CONGESTION', 'OFF') === 'ON';
        $this->unsafe = option($settings, 'UNSAFE', 'OFF') === 'ON';
        $this->trace = option($settings, 'TRACE', 'ALL');
        $this->random = isset($settings['RANDOM']) ? array_map('intval', $settings['RANDOM']) : null;
        $this->loseData = numberSet($settings, 'LOSEDATA');
        $this->loseCtrl = numberSet($settings, 'LOSECTRL');
        $this->corruptData = numberSet($settings, 'CORRUPTDATA');
        $this->corruptCtrl = numberSet($settings, 'CORRUPTCTRL');
        $this->delayData = delayMap($settings, 'DELAYDATA');
        $this->delayCtrl = delayMap($settings, 'DELAYCTRL');
        $this->snapshots = numberSet($settings, 'SNAPSHOT');
    }

    public function windowLimit(): int
    {
        return match ($this->protocol) {
            'SW' => 1,
            'GBN' => 2 ** $this->seqbits - 1,
            default => 2 ** ($this->seqbits - 1),
        };
    }

    public function configLine(): string
    {
        return 'config: ' . $this->protocol . ' n=' . $this->frames . ' w=' . $this->window .
            ' k=' . $this->seqbits . ' T=' . $this->timeout . ' d=' . $this->delay;
    }

    public function optionsLine(): string
    {
        $dupack = $this->dupack === null ? 'off' : (string) $this->dupack;
        $random = $this->random === null ? 'off' : implode('/', $this->random);
        $switch = static fn(bool $flag): string => $flag ? 'on' : 'off';
        return 'options: interval=' . $this->interval . ' limit=' . $this->limit .
            ' dupack=' . $dupack . ' nak=' . $switch($this->nak) .
            ' backoff=' . $switch($this->backoff) . ' congestion=' . $switch($this->congestion) .
            ' unsafe=' . $switch($this->unsafe) . ' trace=' . strtolower($this->trace) .
            ' random=' . $random;
    }
}

function checkSettings(array $lines): Config
{
    $settings = [];
    foreach ($lines as [$key, $values]) {
        if (!in_array($key, KEYS, true)) throw new SettingsError('unknown key ' . $key);
        if (array_key_exists($key, $settings)) throw new SettingsError('duplicate key ' . $key);
        $validCount = $key === 'RANDOM' ? count($values) === 3 :
            (in_array($key, LIST_KEYS, true) ? count($values) >= 1 : count($values) === 1);
        if (!$validCount) throw new SettingsError('wrong number of values for ' . $key);
        $settings[$key] = $values;
    }
    foreach (REQUIRED as $key) {
        if (!isset($settings[$key])) throw new SettingsError('missing key ' . $key);
    }
    foreach (KEYS as $key) {
        if (isset($settings[$key]) && !validValue($key, $settings[$key])) {
            throw new SettingsError('bad value for ' . $key);
        }
    }
    $config = new Config($settings);
    if ($config->protocol === 'SR' && $config->dupack !== null) {
        throw new SettingsError('DUPACK not supported for SR');
    }
    $maxWindow = $config->windowLimit();
    if (($config->protocol === 'SW' || !$config->unsafe) && $config->window > $maxWindow) {
        throw new SettingsError('window ' . $config->window . ' exceeds limit ' .
            $maxWindow . ' for ' . $config->protocol);
    }
    $both = array_intersect(array_keys($config->loseData), array_keys($config->corruptData));
    if ($both) throw new SettingsError('data #' . min($both) . ' both lost and corrupted');
    $both = array_intersect(array_keys($config->loseCtrl), array_keys($config->corruptCtrl));
    if ($both) throw new SettingsError('control #' . min($both) . ' both lost and corrupted');
    return $config;
}

final class FrameRecord
{
    public int $transmissions = 0;
    public ?int $first = null;
    public ?int $delivered = null;
    public ?int $acked = null;
}

final class Transmission
{
    public function __construct(
        public int $number,
        public string $kind,
        public int $value,
        public ?int $payload,
        public string $outcome,
        public int $arrival
    ) {}
}

final class LossGenerator
{
    public function __construct(
        private int $state,
        private int $loss,
        private int $corruption
    ) {}

    public function nextOutcome(): string
    {
        $this->state = RANDOM_MULTIPLIER * $this->state % RANDOM_MODULUS;
        $roll = $this->state % 100;
        if ($roll < $this->loss) return 'LOST';
        if ($roll < $this->loss + $this->corruption) return 'CORRUPT';
        return 'NORMAL';
    }
}

final class Channel
{
    public int $sent = 0;
    public int $lost = 0;
    public int $corrupted = 0;
    private array $inTransit = [];

    public function __construct(
        private int $delay,
        private array $losses,
        private array $corruptions,
        private array $extraDelays
    ) {}

    public function send(string $kind, int $value, ?int $payload, int $tick,
                         ?LossGenerator $generator): Transmission
    {
        $number = ++$this->sent;
        $outcome = $generator?->nextOutcome() ?? 'NORMAL';
        if (isset($this->losses[$number])) $outcome = 'LOST';
        elseif (isset($this->corruptions[$number])) $outcome = 'CORRUPT';
        $item = new Transmission($number, $kind, $value, $payload, $outcome,
            $tick + $this->delay + ($this->extraDelays[$number] ?? 0));
        $this->inTransit[] = $item;
        return $item;
    }

    public function arrivals(int $tick): array
    {
        $arrived = [];
        $remaining = [];
        foreach ($this->inTransit as $item) {
            if ($item->arrival === $tick) $arrived[] = $item;
            else $remaining[] = $item;
        }
        $this->inTransit = $remaining;
        return $arrived;
    }

    public function countDamage(Transmission $item): void
    {
        if ($item->outcome === 'LOST') ++$this->lost;
        else ++$this->corrupted;
    }
}

final class Simulation
{
    public array $lines = [];
    public ?int $completion = null;
    public int $delivered = 0;
    public Channel $dataChannel;
    public Channel $controlChannel;
    private Config $config;
    private bool $selective;
    private int $modulus;
    private array $visible;
    private ?LossGenerator $generator;
    private array $records;
    private int $tick = 0;
    private int $base = 0;
    private int $framesSent = 0;
    private int $nextFrame = 0;
    private int $timerLength;
    private ?int $timer = null;
    private int $duplicates = 0;
    private array $acked;
    private array $timers;
    private array $queue = [];
    private int $cwnd = 1;
    private int $ssthresh;
    private int $roundAcks = 0;
    private int $expected = 0;
    private bool $nakSent = false;
    private array $buffer = [];
    private int $resent = 0;
    private int $naks = 0;
    private int $timeouts = 0;
    private int $fastRetransmits = 0;
    private int $errors = 0;
    private int $discarded = 0;
    private int $maxBuffer = 0;

    public function __construct(Config $config)
    {
        $this->config = $config;
        $this->selective = $config->protocol === 'SR';
        $this->modulus = 2 ** $config->seqbits;
        $this->visible = TRACE_SIDES[$config->trace];
        $this->generator = $config->random === null ? null : new LossGenerator(...$config->random);
        $this->dataChannel = new Channel($config->delay, $config->loseData,
            $config->corruptData, $config->delayData);
        $this->controlChannel = new Channel($config->delay, $config->loseCtrl,
            $config->corruptCtrl, $config->delayCtrl);
        $this->records = array_fill(0, $config->frames, null);
        for ($i = 0; $i < $config->frames; ++$i) $this->records[$i] = new FrameRecord();
        $this->timerLength = $config->timeout;
        $this->acked = array_fill(0, $config->frames, false);
        $this->timers = array_fill(0, $config->frames, null);
        $this->ssthresh = $config->window;
    }

    private function emit(mixed ...$parts): void
    {
        $this->lines[] = $this->tick . ' ' . implode(' ', $parts);
    }

    private function trace(string $side, mixed ...$parts): void
    {
        if (in_array($side, $this->visible, true)) $this->emit(...$parts);
    }

    private function frameOf(int $value): int
    {
        return $this->base + modulo($value - $this->base, $this->modulus);
    }

    private function effectiveWindow(): int
    {
        return $this->config->congestion ? min($this->config->window, $this->cwnd) : $this->config->window;
    }

    public function run(): void
    {
        for ($tick = 0; $tick <= $this->config->limit; ++$tick) {
            $this->tick = $tick;
            foreach ($this->dataChannel->arrivals($tick) as $item) {
                if ($item->outcome === 'NORMAL') $this->receiveData($item);
                else $this->reportDamage($this->dataChannel, $item, 'RECEIVER');
            }
            foreach ($this->controlChannel->arrivals($tick) as $item) {
                if ($item->outcome === 'NORMAL') $this->receiveControl($item);
                else $this->reportDamage($this->controlChannel, $item, 'SENDER');
            }
            $completed = $this->base === $this->config->frames;
            if (!$completed) {
                $this->processTimeouts();
                $this->sendData();
            }
            if (isset($this->config->snapshots[$tick])) $this->snapshot();
            if ($completed) {
                $this->completion = $tick;
                $this->emit('DONE');
                return;
            }
        }
        $this->emit('ABORT');
    }

    private function reportDamage(Channel $channel, Transmission $item, string $side): void
    {
        $channel->countDamage($item);
        $this->trace($side, $item->outcome, $item->kind, '#' . $item->number);
    }

    private function receiveData(Transmission $item): void
    {
        $this->trace('RECEIVER', 'RECV', 'seq=' . $item->value, '#' . $item->number);
        if ($this->selective) $this->selectiveReceive($item->value, $item->payload);
        else $this->goBackNReceive($item->value, $item->payload);
    }

    private function goBackNReceive(int $seq, int $payload): void
    {
        if ($seq === $this->expected % $this->modulus) {
            $this->deliver($payload);
            $this->sendControl('ack', $seq);
            return;
        }
        $this->discard($seq);
        if ($this->config->nak && !$this->nakSent) {
            $this->sendControl('nak', $this->expected % $this->modulus);
            $this->nakSent = true;
        } elseif ($this->expected > 0) {
            $this->sendControl('ack', ($this->expected - 1) % $this->modulus);
        }
    }

    private function selectiveReceive(int $seq, int $payload): void
    {
        $offset = modulo($seq - $this->expected, $this->modulus);
        if ($offset >= $this->config->window) {
            $this->discard($seq);
            if (modulo($this->expected - $seq, $this->modulus) <= $this->config->window) {
                $this->sendControl('ack', $seq);
            }
            return;
        }
        $position = $this->expected + $offset;
        if (isset($this->buffer[$position])) {
            $this->discard($seq);
            $this->sendControl('ack', $seq);
        } elseif ($offset === 0) {
            $this->deliver($payload);
            while (isset($this->buffer[$this->expected])) {
                $waiting = $this->buffer[$this->expected];
                unset($this->buffer[$this->expected]);
                $this->deliver($waiting);
            }
            $this->sendControl('ack', $seq);
        } else {
            $this->buffer[$position] = $payload;
            $this->maxBuffer = max($this->maxBuffer, count($this->buffer));
            $this->trace('RECEIVER', 'BUFFER', 'f=' . $position);
            $this->sendControl('ack', $seq);
            if ($this->config->nak && !$this->nakSent) {
                $this->sendControl('nak', $this->expected % $this->modulus);
                $this->nakSent = true;
            }
        }
    }

    private function deliver(int $payload): void
    {
        $position = $this->expected;
        if ($payload === $position) {
            ++$this->delivered;
            $this->records[$payload]->delivered = $this->tick;
            $this->trace('RECEIVER', 'DELIVER', 'f=' . $position);
        } else {
            ++$this->errors;
            $this->trace('RECEIVER', 'DELIVER', 'f=' . $position, 'wrong=' . $payload);
        }
        ++$this->expected;
        $this->nakSent = false;
    }

    private function discard(int $seq): void
    {
        ++$this->discarded;
        $this->trace('RECEIVER', 'DISCARD', 'seq=' . $seq);
    }

    private function sendControl(string $kind, int $value): void
    {
        $item = $this->controlChannel->send($kind, $value, null, $this->tick, $this->generator);
        if ($kind === 'nak') ++$this->naks;
        $this->trace('RECEIVER', strtoupper($kind), 'a=' . $value, '#' . $item->number);
    }

    private function receiveControl(Transmission $item): void
    {
        $before = [$this->cwnd, $this->ssthresh];
        if ($item->kind === 'ack') {
            if ($this->selective) $this->selectiveAck($item);
            else $this->goBackNAck($item);
        } elseif ($this->selective) {
            $this->selectiveNak($item);
        } else {
            $this->goBackNNak($item);
        }
        $this->reportWindow($before);
    }

    private function controlLine(Transmission $item, bool $accepted): void
    {
        $parts = [($accepted ? 'GOT' : 'OLD') . strtoupper($item->kind),
            'a=' . $item->value, '#' . $item->number];
        if ($accepted) $parts[] = 'base=' . $this->base;
        $this->trace('SENDER', ...$parts);
    }

    private function goBackNAck(Transmission $item): void
    {
        $frame = $this->frameOf($item->value);
        if ($frame < $this->framesSent) {
            $this->growWindow($frame - $this->base + 1);
            $this->moveBase($frame + 1);
            if ($this->nextFrame < $this->base) $this->nextFrame = $this->base;
            $this->timer = $this->base === $this->nextFrame ? null : $this->tick + $this->timerLength;
            $this->controlLine($item, true);
            return;
        }
        $this->controlLine($item, false);
        if ($this->config->dupack === null || $this->base < 1) return;
        if ($item->value === ($this->base - 1) % $this->modulus) {
            ++$this->duplicates;
            if ($this->duplicates === $this->config->dupack) {
                ++$this->fastRetransmits;
                $this->trace('SENDER', 'FASTRETX', 'f=' . $this->base);
                $this->goBack();
                $this->halveWindow();
            }
        }
    }

    private function goBackNNak(Transmission $item): void
    {
        $frame = $this->frameOf($item->value);
        if ($frame > $this->framesSent) {
            $this->controlLine($item, false);
            return;
        }
        $this->growWindow($frame - $this->base);
        $this->moveBase($frame);
        $this->goBack();
        $this->halveWindow();
        $this->controlLine($item, true);
    }

    private function selectiveAck(Transmission $item): void
    {
        $frame = $this->frameOf($item->value);
        if ($frame >= $this->framesSent || $this->acked[$frame]) {
            $this->controlLine($item, false);
            return;
        }
        $this->acked[$frame] = true;
        $this->records[$frame]->acked = $this->tick;
        $this->timers[$frame] = null;
        $this->queue = array_values(array_filter($this->queue,
            static fn(int $waiting): bool => $waiting !== $frame));
        $this->growWindow(1);
        $previous = $this->base;
        while ($this->base < $this->framesSent && $this->acked[$this->base]) ++$this->base;
        if ($this->base > $previous) $this->timerLength = $this->config->timeout;
        $this->controlLine($item, true);
    }

    private function selectiveNak(Transmission $item): void
    {
        $frame = $this->frameOf($item->value);
        if ($frame >= $this->framesSent || $this->acked[$frame]) {
            $this->controlLine($item, false);
            return;
        }
        $this->timers[$frame] = null;
        if (!in_array($frame, $this->queue, true)) $this->queue[] = $frame;
        $this->halveWindow();
        $this->controlLine($item, true);
    }

    private function moveBase(int $newBase): void
    {
        if ($newBase <= $this->base) return;
        for ($f = $this->base; $f < $newBase; ++$f) $this->records[$f]->acked = $this->tick;
        $this->base = $newBase;
        $this->timerLength = $this->config->timeout;
        $this->duplicates = 0;
    }

    private function goBack(): void
    {
        $this->nextFrame = $this->base;
        $this->timer = null;
        $this->duplicates = 0;
    }

    private function growWindow(int $count): void
    {
        if (!$this->config->congestion) return;
        for ($i = 0; $i < $count; ++$i) {
            if ($this->cwnd >= $this->config->window) continue;
            if ($this->cwnd < $this->ssthresh) {
                ++$this->cwnd;
            } else {
                ++$this->roundAcks;
                if ($this->roundAcks === $this->cwnd) {
                    ++$this->cwnd;
                    $this->roundAcks = 0;
                }
            }
        }
    }

    private function halveWindow(): void
    {
        if (!$this->config->congestion) return;
        $this->ssthresh = max(intdiv($this->cwnd, 2), 1);
        $this->cwnd = $this->ssthresh;
        $this->roundAcks = 0;
    }

    private function collapseWindow(): void
    {
        if (!$this->config->congestion) return;
        $this->ssthresh = max(intdiv($this->cwnd, 2), 1);
        $this->cwnd = 1;
        $this->roundAcks = 0;
    }

    private function reportWindow(array $before): void
    {
        if ([$this->cwnd, $this->ssthresh] !== $before) {
            $this->trace('SENDER', 'CWND', $this->cwnd, 'ssthresh=' . $this->ssthresh);
        }
    }

    private function processTimeouts(): void
    {
        if ($this->selective) {
            for ($frame = $this->base; $frame < $this->framesSent; ++$frame) {
                if ($this->timers[$frame] === $this->tick) {
                    $this->timers[$frame] = null;
                    $this->queue[] = $frame;
                    $this->timeOut($frame);
                }
            }
        } elseif ($this->timer === $this->tick) {
            $this->timeOut($this->base);
            $this->goBack();
        }
    }

    private function timeOut(int $frame): void
    {
        $before = [$this->cwnd, $this->ssthresh];
        ++$this->timeouts;
        $this->trace('SENDER', 'TIMEOUT', 'f=' . $frame);
        if ($this->config->backoff) {
            $this->timerLength = min(2 * $this->timerLength, 8 * $this->config->timeout);
        }
        $this->collapseWindow();
        $this->reportWindow($before);
    }

    private function maySendNew(int $frame): bool
    {
        return $frame < $this->config->frames &&
            $frame < $this->base + $this->effectiveWindow() &&
            $frame * $this->config->interval <= $this->tick;
    }

    private function sendData(): void
    {
        if ($this->selective) $this->selectiveSend();
        else $this->goBackNSend();
    }

    private function goBackNSend(): void
    {
        $frame = $this->nextFrame;
        if ($frame >= $this->config->frames || $frame >= $this->base + $this->effectiveWindow()) return;
        if ($frame >= $this->framesSent && $frame * $this->config->interval > $this->tick) return;
        $this->transmit($frame);
        $this->framesSent = max($this->framesSent, $frame + 1);
        ++$this->nextFrame;
        if ($this->timer === null) $this->timer = $this->tick + $this->timerLength;
    }

    private function selectiveSend(): void
    {
        if ($this->queue) {
            $frame = array_shift($this->queue);
        } elseif ($this->maySendNew($this->framesSent)) {
            $frame = $this->framesSent++;
        } else {
            return;
        }
        $this->transmit($frame);
        $this->timers[$frame] = $this->tick + $this->timerLength;
    }

    private function transmit(int $frame): void
    {
        $record = $this->records[$frame];
        $seq = $frame % $this->modulus;
        $item = $this->dataChannel->send('data', $seq, $frame, $this->tick, $this->generator);
        ++$record->transmissions;
        if ($record->transmissions === 1) {
            $record->first = $this->tick;
            $label = 'SEND';
        } else {
            ++$this->resent;
            $label = 'RESEND';
        }
        $this->trace('SENDER', $label, 'f=' . $frame, 'seq=' . $seq, '#' . $item->number);
    }

    private function senderMark(int $frame): string
    {
        if ($this->selective) {
            $acknowledged = $this->acked[$frame];
            $waiting = in_array($frame, $this->queue, true);
            $sent = $frame < $this->framesSent;
        } else {
            $acknowledged = $frame < $this->base;
            $waiting = $this->nextFrame <= $frame && $frame < $this->framesSent;
            $sent = $frame < $this->nextFrame;
        }
        if ($acknowledged) return 'A';
        if ($waiting) return 'R';
        if ($sent) return 'O';
        if ($frame < $this->base + $this->effectiveWindow()) return 'W';
        return '.';
    }

    private function receiverMark(int $position): string
    {
        if ($position < $this->expected) return 'D';
        if ($this->selective) {
            if (isset($this->buffer[$position])) return 'B';
            if ($position < $this->expected + $this->config->window) return 'W';
        } elseif ($position === $this->expected) {
            return 'W';
        }
        return '.';
    }

    private function snapshot(): void
    {
        $sender = $receiver = '';
        for ($frame = 0; $frame < $this->config->frames; ++$frame) {
            $sender .= $this->senderMark($frame);
            $receiver .= $this->receiverMark($frame);
        }
        $this->emit('SNAPSHOT', 'sender=' . $sender, 'receiver=' . $receiver);
    }

    public function dataCount(): int
    {
        return $this->dataChannel->sent;
    }

    public function goodputText(): string
    {
        return truncated($this->delivered, $this->completion, 2);
    }

    public function efficiencyText(): string
    {
        return truncated(100 * $this->delivered, $this->dataCount(), 1);
    }

    private function latencyText(): string
    {
        if ($this->delivered === 0) return '-';
        $total = 0;
        foreach ($this->records as $record) {
            if ($record->delivered !== null) $total += $record->delivered - $record->first;
        }
        return truncated($total, $this->delivered, 2);
    }

    public function report(): array
    {
        $lines = [];
        foreach ($this->records as $frame => $record) {
            $lines[] = 'frame ' . $frame . ': seq=' . ($frame % $this->modulus) .
                ' tx=' . $record->transmissions . ' first=' . tickText($record->first) .
                ' delivered=' . tickText($record->delivered) . ' acked=' . tickText($record->acked);
        }
        $data = $this->dataChannel;
        $control = $this->controlChannel;
        $lines[] = 'totals: data=' . $data->sent . ' resent=' . $this->resent .
            ' control=' . $control->sent . ' nak=' . $this->naks .
            ' timeouts=' . $this->timeouts . ' fastretx=' . $this->fastRetransmits;
        $lines[] = 'channel: lost_data=' . $data->lost . ' lost_ctrl=' . $control->lost .
            ' corrupt_data=' . $data->corrupted . ' corrupt_ctrl=' . $control->corrupted;
        $lines[] = 'receiver: delivered=' . $this->delivered . ' errors=' . $this->errors .
            ' discarded=' . $this->discarded . ' max_buffer=' . $this->maxBuffer;
        $completion = $this->completion === null ? '-' : (string) $this->completion;
        $goodput = $this->completion === null ? '-' : $this->goodputText();
        $utilization = truncated(100 * $data->sent, $this->tick + 1, 1);
        $lines[] = 'result: completion=' . $completion . ' goodput=' . $goodput .
            ' efficiency=' . $this->efficiencyText() . '% utilization=' . $utilization .
            '% latency=' . $this->latencyText();
        return $lines;
    }
}

final class Scenario
{
    public ?Config $config = null;
    public ?Simulation $simulation = null;

    public function __construct(public string $name, private array $settings) {}

    public function completed(): bool
    {
        return $this->simulation !== null && $this->simulation->completion !== null;
    }

    public function status(): string
    {
        return $this->simulation === null ? 'invalid' : 'aborted';
    }

    public function execute(array &$output): void
    {
        $output[] = '== ' . $this->name . ' ==';
        try {
            $this->config = checkSettings($this->settings);
        } catch (SettingsError $error) {
            $output[] = 'error: ' . $error->getMessage();
            return;
        }
        $output[] = $this->config->configLine();
        $output[] = $this->config->optionsLine();
        $this->simulation = new Simulation($this->config);
        $this->simulation->run();
        array_push($output, ...$this->simulation->lines, ...$this->simulation->report());
    }
}

function rankingLines(array $scenarios): array
{
    $output = ['== ranking =='];
    $completed = [];
    foreach ($scenarios as $index => $scenario) {
        if ($scenario->completed()) $completed[] = [$scenario, $index];
    }
    usort($completed, static function (array $a, array $b): int {
        [$first, $ia] = $a;
        [$second, $ib] = $b;
        $left = $first->simulation;
        $right = $second->simulation;
        $goodput = $right->delivered * $left->completion - $left->delivered * $right->completion;
        if ($goodput !== 0) return $goodput <=> 0;
        $efficiency = $right->delivered * $left->dataCount() -
            $left->delivered * $right->dataCount();
        return $efficiency !== 0 ? $efficiency <=> 0 : $ia <=> $ib;
    });
    foreach ($completed as $rank => [$scenario]) {
        $run = $scenario->simulation;
        $output[] = ($rank + 1) . '. ' . $scenario->name . ' ' . $scenario->config->protocol .
            ' goodput=' . $run->goodputText() . ' efficiency=' . $run->efficiencyText() . '%';
    }
    foreach ($scenarios as $scenario) {
        if (!$scenario->completed()) $output[] = '- ' . $scenario->name . ' ' . $scenario->status();
    }
    return $output;
}

function protocolLines(array $scenarios): array
{
    $output = ['== protocols =='];
    foreach (PROTOCOLS as $protocol) {
        $runs = [];
        foreach ($scenarios as $scenario) {
            if ($scenario->completed() && $scenario->config->protocol === $protocol) {
                $runs[] = $scenario->simulation;
            }
        }
        if (!$runs) continue;
        $delivered = $ticks = $data = 0;
        foreach ($runs as $run) {
            $delivered += $run->delivered;
            $ticks += $run->completion;
            $data += $run->dataCount();
        }
        $output[] = $protocol . ': runs=' . count($runs) .
            ' goodput=' . truncated($delivered, $ticks, 2) .
            ' efficiency=' . truncated(100 * $delivered, $data, 1) . '%';
    }
    return $output;
}

function readScenarios(array $lines): array
{
    $count = (int) $lines[0];
    $index = 1;
    $scenarios = [];
    for ($number = 0; $number < $count; ++$number) {
        $name = explode(' ', $lines[$index++])[1];
        $settings = [];
        while ($lines[$index] !== 'END') {
            $parts = explode(' ', $lines[$index++]);
            $key = array_shift($parts);
            $settings[] = [$key, $parts];
        }
        ++$index;
        $scenarios[] = new Scenario($name, $settings);
    }
    return $scenarios;
}

$scenarios = readScenarios(file('php://stdin', FILE_IGNORE_NEW_LINES));
$output = [];
foreach ($scenarios as $scenario) $scenario->execute($output);
array_push($output, ...rankingLines($scenarios), ...protocolLines($scenarios));
echo implode("\n", $output) . "\n";
