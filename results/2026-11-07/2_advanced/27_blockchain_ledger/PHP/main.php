<?php

require_once __DIR__ . '/chain.php';

function readInput(): array
{
    $fields = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $parts = explode(' ', $line);
        $name = array_shift($parts);
        $fields[$name] = $parts;
    }
    $settings = [
        'difficulty' => (int) $fields['DIFFICULTY'][0],
        'retarget' => (int) $fields['RETARGET'][0],
        'targetTime' => (int) $fields['RETARGET'][1],
        'reward' => (int) $fields['REWARD'][0],
        'halving' => (int) $fields['REWARD'][1],
        'maturity' => (int) $fields['MATURITY'][0],
        'maxBlock' => (int) $fields['MAXBLOCK'][0],
        'minFee' => (int) $fields['MINFEERATE'][0],
        'maxMempool' => (int) $fields['MEMPOOL'][0],
        'maxOrphans' => (int) $fields['ORPHANS'][0],
        'drift' => (int) $fields['DRIFT'][0],
        'expiry' => (int) $fields['EXPIRY'][0],
        'maxReorg' => (int) $fields['MAXREORG'][0],
        'banThreshold' => (int) $fields['BAN'][0],
        'blockPenalty' => (int) $fields['BAN'][1],
        'transactionPenalty' => (int) $fields['BAN'][2],
        'genesis' => []
    ];
    $distribution = $fields['GENESIS'];
    for ($i = 0; $i < count($distribution); $i += 2) {
        $settings['genesis'][] = ['name' => $distribution[$i], 'amount' => (int) $distribution[$i + 1]];
    }
    $lines = file('input/events.txt', FILE_IGNORE_NEW_LINES);
    $events = [];
    for ($i = 0; $i < count($lines); $i++) {
        $tokens = explode(' ', $lines[$i]);
        $event = ['time' => (int) $tokens[0], 'kind' => $tokens[1], 'tokens' => $tokens];
        if ($event['kind'] === 'TX') {
            $event['transaction'] = new Transaction($tokens[3]);
        } elseif ($event['kind'] === 'BLOCK') {
            $count = (int) $tokens[9];
            $event['block'] = parseBlock($tokens, array_slice($lines, $i + 1, $count));
            $i += $count;
        }
        $events[] = $event;
    }
    return [$settings, $events, readWallets()];
}

function referenceOrder(array $a, array $b): int
{
    return strcmp($a['txid'], $b['txid']) ?: $a['index'] <=> $b['index'];
}

function priorityOrder(array $a, array $b): int
{
    $left = $a['fee'] * $b['transaction']->size;
    $right = $b['fee'] * $a['transaction']->size;
    return $left === $right ? strcmp($a['transaction']->txid, $b['transaction']->txid) : $right <=> $left;
}

function signedAmount(int $value): string
{
    return $value >= 0 ? '+' . $value : (string) $value;
}

class Node
{
    private array $settings;
    private array $events;
    private array $wallets;
    private array $byName = [];
    private array $owners = [];
    private StoredBlock $genesis;
    private StoredBlock $tip;
    private array $blocks = [];
    private array $mainChain = [];
    private array $mainTransactions = [];
    private array $pool = [];
    private array $orphans = [];
    private array $rejected = [];
    private array $dropped = [];
    private array $peers = [];
    private array $rejections = [];
    private array $reorganizations = [];
    private array $log = [];
    private int $time = 0;

    public function __construct(array $settings, array $events, array $wallets)
    {
        $this->settings = $settings;
        $this->events = $events;
        $this->wallets = $wallets;
        foreach ($wallets as $wallet) {
            $this->byName[$wallet['name']] = $wallet;
            $this->owners[$wallet['address']] = $wallet;
        }
        $outputs = [];
        foreach ($settings['genesis'] as $item) {
            $outputs[] = ['address' => $this->byName[$item['name']]['address'], 'amount' => $item['amount']];
        }
        $transaction = coinbase(0, $outputs);
        $block = new Block(0, str_repeat('0', 32), $transaction->txid, 0, 0, 0, [$transaction]);
        $utxo = [];
        applyTransaction($transaction, $utxo, 0);
        $this->genesis = new StoredBlock($block, null, $utxo, 0, [0], 'genesis');
        $this->blocks[$block->hash] = $this->genesis;
        $this->tip = $this->genesis;
        $this->refreshMainChain();
    }

    private function nextHeight(): int
    {
        return $this->tip->block->height + 1;
    }

    private function message(string $text): void
    {
        $this->log[] = $this->time . ' ' . $text;
    }

    private function refreshMainChain(): void
    {
        $this->mainChain = chainSequence($this->tip);
        $this->mainTransactions = [];
        foreach ($this->mainChain as $stored) {
            foreach ($stored->block->transactions as $transaction) {
                $this->mainTransactions[$transaction->txid] = ['transaction' => $transaction, 'height' => $stored->block->height];
            }
        }
    }

    private function priority(): array
    {
        $entries = $this->pool;
        usort($entries, 'priorityOrder');
        return $entries;
    }

    private function lockedReferences(): array
    {
        $locked = [];
        foreach ($this->pool as $entry) {
            foreach ($entry['transaction']->inputs as $input) {
                $locked[$input['key']] = true;
            }
        }
        return $locked;
    }

    private function tally(string $category, string $reason): void
    {
        $key = $category . ' ' . $reason;
        $this->rejections[$key] = ($this->rejections[$key] ?? 0) + 1;
    }

    private function peerRecord(string $name): object
    {
        if (!isset($this->peers[$name])) {
            $this->peers[$name] = (object) ['name' => $name, 'blocks' => 0, 'rejectedBlocks' => 0, 'orphans' => 0,
                'transactions' => 0, 'rejectedTransactions' => 0, 'ignored' => 0, 'score' => 0];
        }
        return $this->peers[$name];
    }

    private function penalize(object $peer, int $points): void
    {
        $before = $peer->score;
        $peer->score += $points;
        if ($before < $this->settings['banThreshold'] && $peer->score >= $this->settings['banThreshold']) {
            $this->message("BAN $peer->name score $peer->score");
        }
    }

    private function acceptable(Transaction $transaction): array
    {
        if ($transaction->coinbase) {
            return ['reason' => 'coinbase'];
        }
        if (isset($this->mainTransactions[$transaction->txid])) {
            return ['reason' => 'duplicate'];
        }
        foreach ($this->pool as $entry) {
            if ($entry['transaction']->txid === $transaction->txid) {
                return ['reason' => 'duplicate'];
            }
        }
        $result = checkTransaction($transaction, $this->tip->utxo, [], $this->nextHeight(), $this->settings['maturity'], $this->owners);
        if (isset($result['reason'])) {
            return $result;
        }
        $fee = $result['fee'];
        if ($fee * 1000 < $this->settings['minFee'] * $transaction->size) {
            return ['reason' => 'low-fee'];
        }
        $references = [];
        foreach ($transaction->inputs as $input) {
            $references[$input['key']] = true;
        }
        $conflicts = [];
        foreach ($this->pool as $entry) {
            foreach ($entry['transaction']->inputs as $input) {
                if (isset($references[$input['key']])) {
                    $conflicts[] = $entry;
                    break;
                }
            }
        }
        if ($conflicts) {
            if ($fee <= array_sum(array_column($conflicts, 'fee'))) {
                return ['reason' => 'conflict'];
            }
            foreach ($conflicts as $entry) {
                if ($fee * $entry['transaction']->size <= $entry['fee'] * $transaction->size) {
                    return ['reason' => 'conflict'];
                }
            }
        }
        return ['fee' => $fee, 'conflicts' => $conflicts];
    }

    private function recordDrop(Transaction $transaction, string $reason): void
    {
        $this->dropped[$transaction->txid] = $reason;
        $this->message('DROP ' . shortHash($transaction->txid) . ' ' . $reason);
    }

    private function drop(array $entry, string $reason): void
    {
        foreach ($this->pool as $i => $candidate) {
            if ($candidate['transaction']->txid === $entry['transaction']->txid) {
                array_splice($this->pool, $i, 1);
                break;
            }
        }
        $this->recordDrop($entry['transaction'], $reason);
    }

    private function register(Transaction $transaction, array $result, int $arrival): void
    {
        foreach ($result['conflicts'] as $conflict) {
            $this->drop($conflict, 'replaced');
        }
        $this->pool[] = ['transaction' => $transaction, 'fee' => $result['fee'], 'arrival' => $arrival];
        if (count($this->pool) > $this->settings['maxMempool']) {
            $priority = $this->priority();
            $this->drop($priority[count($priority) - 1], 'mempool-full');
        }
    }

    private function rebuild(array $returned): void
    {
        $previous = $this->pool;
        $this->pool = [];
        $candidates = [];
        foreach ($returned as $transaction) {
            $candidates[] = ['transaction' => $transaction, 'arrival' => $this->time, 'returned' => true];
        }
        foreach ($previous as $entry) {
            $candidates[] = ['transaction' => $entry['transaction'], 'arrival' => $entry['arrival'], 'returned' => false];
        }
        foreach ($candidates as $candidate) {
            $transaction = $candidate['transaction'];
            if (isset($this->mainTransactions[$transaction->txid])) {
                continue;
            }
            $result = $this->acceptable($transaction);
            if (isset($result['reason'])) {
                $this->recordDrop($transaction, $result['reason']);
            } else {
                if ($candidate['returned']) {
                    $this->message('RETURN ' . shortHash($transaction->txid));
                }
                $this->register($transaction, $result, $candidate['arrival']);
            }
        }
    }

    private function switchTip(StoredBlock $stored): void
    {
        $previous = $this->tip;
        $fork = forkPoint($previous, $stored);
        $disconnected = $previous->block->height - $fork->block->height;
        $connected = $stored->block->height - $fork->block->height;
        $block = $stored->block;
        $prefix = $block->height . ' ' . shortHash($block->hash) . ' work ' . $stored->work . ' fork ' . $fork->block->height;
        if ($disconnected > $this->settings['maxReorg']) {
            $this->message('REFUSE ' . $prefix . ' depth ' . $disconnected);
            return;
        }
        $returned = [];
        foreach ($this->mainChain as $old) {
            if ($old->block->height > $fork->block->height) {
                array_push($returned, ...array_slice($old->block->transactions, 1));
            }
        }
        $this->tip = $stored;
        $this->refreshMainChain();
        if ($disconnected === 0) {
            $this->message('TIP ' . $block->height . ' ' . shortHash($block->hash) . ' work ' . $stored->work);
        } else {
            $this->message('REORG ' . $prefix . ' disconnected ' . $disconnected . ' connected ' . $connected);
            $this->reorganizations[] = ['time' => $this->time, 'fork' => $fork->block->height,
                'disconnected' => $disconnected, 'connected' => $connected, 'old' => $previous->block->hash, 'next' => $block->hash];
        }
        $this->rebuild($returned);
    }

    private function pay(array $tokens): void
    {
        $sender = $this->byName[$tokens[2]];
        $fee = (int) $tokens[3];
        $outputs = [];
        for ($i = 4; $i < count($tokens); $i += 2) {
            $outputs[] = ['address' => $this->byName[$tokens[$i]]['address'], 'amount' => (int) $tokens[$i + 1]];
        }
        $total = array_sum(array_column($outputs, 'amount'));
        $need = $total + $fee;
        $locked = $this->lockedReferences();
        $coins = [];
        foreach ($this->tip->utxo as $key => $coin) {
            if ($coin['address'] === $sender['address'] && !isset($locked[$key]) &&
                mature($coin, $this->nextHeight(), $this->settings['maturity'])) {
                $coins[] = $coin;
            }
        }
        usort($coins, fn($a, $b) => ($b['amount'] <=> $a['amount']) ?: referenceOrder($a, $b));
        $selected = [];
        $value = 0;
        foreach ($coins as $coin) {
            $selected[] = $coin;
            $value += $coin['amount'];
            if ($value >= $need) {
                break;
            }
        }
        $prefix = 'PAY ' . $sender['name'] . ' fee ' . $fee . ' total ' . $total;
        if ($value < $need) {
            $this->message($prefix . ' rejected insufficient-funds');
            $this->tally('pay', 'insufficient-funds');
            return;
        }
        if ($value > $need) {
            $outputs[] = ['address' => $sender['address'], 'amount' => $value - $need];
        }
        $transaction = payment($selected, $outputs, $sender['secret']);
        $result = $this->acceptable($transaction);
        if (isset($result['reason'])) {
            $this->message($prefix . ' tx ' . shortHash($transaction->txid) . ' rejected ' . $result['reason']);
            $this->tally('pay', $result['reason']);
        } else {
            $this->message($prefix . ' tx ' . shortHash($transaction->txid) . ' accepted inputs ' . count($transaction->inputs) .
                ' outputs ' . count($transaction->outputs) . ' size ' . $transaction->size);
            $this->register($transaction, $result, $this->time);
        }
    }

    private function bump(string $txid, int $fee): void
    {
        $prefix = 'BUMP ' . shortHash($txid) . ' fee ' . $fee;
        $entry = null;
        foreach ($this->pool as $candidate) {
            if ($candidate['transaction']->txid === $txid) {
                $entry = $candidate;
                break;
            }
        }
        if ($entry === null) {
            $this->message($prefix . ' rejected unknown');
            $this->tally('bump', 'unknown');
            return;
        }
        $old = $entry['transaction'];
        $addresses = [];
        foreach ($old->inputs as $input) {
            $addresses[$this->tip->utxo[$input['key']]['address']] = true;
        }
        $lastIndex = count($old->outputs) - 1;
        $last = $old->outputs[$lastIndex];
        $amount = $last['amount'] - ($fee - $entry['fee']);
        if (count($addresses) !== 1 || !isset($addresses[$last['address']]) || $amount < 1) {
            $this->message($prefix . ' rejected no-change');
            $this->tally('bump', 'no-change');
            return;
        }
        $outputs = $old->outputs;
        $outputs[$lastIndex]['amount'] = $amount;
        $transaction = payment($old->inputs, $outputs, $this->owners[$last['address']]['secret']);
        $result = $this->acceptable($transaction);
        if (isset($result['reason'])) {
            $this->message($prefix . ' tx ' . shortHash($transaction->txid) . ' rejected ' . $result['reason']);
            $this->tally('bump', $result['reason']);
        } else {
            $this->message($prefix . ' tx ' . shortHash($transaction->txid) . ' accepted size ' . $transaction->size);
            $this->register($transaction, $result, $this->time);
        }
    }

    private function receiveTransaction(Transaction $transaction, object $peer): void
    {
        $result = $this->acceptable($transaction);
        $prefix = 'TX ' . $peer->name . ' ' . shortHash($transaction->txid);
        if (isset($result['reason'])) {
            $peer->rejectedTransactions++;
            $this->tally('tx', $result['reason']);
            $this->message($prefix . ' rejected ' . $result['reason']);
            if (in_array($result['reason'], ['coinbase', 'bad-output', 'bad-sig', 'overspend'], true)) {
                $this->penalize($peer, $this->settings['transactionPenalty']);
            }
        } else {
            $peer->transactions++;
            $this->message($prefix . ' accepted fee ' . $result['fee'] . ' size ' . $transaction->size);
            $this->register($transaction, $result, $this->time);
        }
    }

    private function mine(string $walletName): void
    {
        $selected = [];
        $size = 0;
        $fees = 0;
        foreach ($this->priority() as $entry) {
            if ($size + $entry['transaction']->size > $this->settings['maxBlock']) {
                continue;
            }
            $selected[] = $entry;
            $size += $entry['transaction']->size;
            $fees += $entry['fee'];
        }
        $height = $this->nextHeight();
        $coinbase = coinbase($height, [['address' => $this->byName[$walletName]['address'], 'amount' => reward($height, $this->settings) + $fees]]);
        $list = [$coinbase];
        $transactionFees = [0];
        foreach ($selected as $entry) {
            $list[] = $entry['transaction'];
            $transactionFees[] = $entry['fee'];
        }
        $timestamp = max($this->time, medianTime($this->tip) + 1);
        $block = mineBlock($height, $this->tip->block->hash, $timestamp, requiredDifficulty($this->tip, $this->settings), $list);
        $utxo = $this->tip->utxo;
        foreach ($list as $transaction) {
            applyTransaction($transaction, $utxo, $height);
        }
        $stored = new StoredBlock($block, $this->tip, $utxo, $fees, $transactionFees, 'local');
        $this->blocks[$block->hash] = $stored;
        $this->message('MINE ' . $walletName . ' ' . $height . ' ' . shortHash($block->hash) . ' bits ' . $block->difficulty .
            ' nonce ' . $block->nonce . ' txs ' . count($list) . ' size ' . $size . ' fees ' . $fees . ' work ' . $stored->work);
        $this->switchTip($stored);
    }

    private function rejectBlock(string $kind, Block $block, object $peer, string $reason): void
    {
        $this->rejected[$block->hash] = true;
        $peer->rejectedBlocks++;
        $this->tally('block', explode(' ', $reason)[0]);
        $this->message($kind . ' ' . $peer->name . ' ' . $block->height . ' ' . shortHash($block->hash) . ' rejected ' . $reason);
        if ($reason !== 'time-too-new') {
            $this->penalize($peer, $this->settings['blockPenalty']);
        }
    }

    private function connectBlock(string $kind, Block $block, object $peer): void
    {
        $parent = $this->blocks[$block->previous];
        if ($block->height !== $parent->block->height + 1) {
            $this->rejectBlock($kind, $block, $peer, 'bad-height');
            return;
        }
        if ($block->difficulty !== requiredDifficulty($parent, $this->settings)) {
            $this->rejectBlock($kind, $block, $peer, 'bad-difficulty');
            return;
        }
        if ($block->timestamp <= medianTime($parent)) {
            $this->rejectBlock($kind, $block, $peer, 'time-too-old');
            return;
        }
        if ($block->timestamp > $this->time + $this->settings['drift']) {
            $this->rejectBlock($kind, $block, $peer, 'time-too-new');
            return;
        }
        $utxo = $parent->utxo;
        $spent = [];
        $transactionFees = [0];
        $fees = 0;
        for ($i = 1; $i < count($block->transactions); $i++) {
            $transaction = $block->transactions[$i];
            $result = checkTransaction($transaction, $utxo, $spent, $block->height, $this->settings['maturity'], $this->owners);
            if (isset($result['reason'])) {
                $this->rejectBlock($kind, $block, $peer, $result['reason'] . ' tx ' . ($i + 1));
                return;
            }
            foreach ($transaction->inputs as $input) {
                $spent[$input['key']] = true;
            }
            applyTransaction($transaction, $utxo, $block->height);
            $fees += $result['fee'];
            $transactionFees[] = $result['fee'];
        }
        $coinbase = $block->transactions[0];
        foreach ($coinbase->outputs as $output) {
            if (!isset($this->owners[$output['address']]) || $output['amount'] === 0) {
                $this->rejectBlock($kind, $block, $peer, 'bad-output tx 1');
                return;
            }
        }
        if (outputTotal($coinbase) > reward($block->height, $this->settings) + $fees) {
            $this->rejectBlock($kind, $block, $peer, 'bad-coinbase');
            return;
        }
        applyTransaction($coinbase, $utxo, $block->height);
        $stored = new StoredBlock($block, $parent, $utxo, $fees, $transactionFees, $peer->name);
        $this->blocks[$block->hash] = $stored;
        $peer->blocks++;
        $this->message($kind . ' ' . $peer->name . ' ' . $block->height . ' ' . shortHash($block->hash) . ' accepted work ' . $stored->work);
        if ($stored->work > $this->tip->work) {
            $this->switchTip($stored);
        }
    }

    private function resolveOrphans(string $startingHash): void
    {
        $queue = [$startingHash];
        for ($head = 0; $head < count($queue); $head++) {
            $parentHash = $queue[$head];
            $children = [];
            $remaining = [];
            foreach ($this->orphans as $orphan) {
                if ($orphan['block']->previous === $parentHash) {
                    $children[] = $orphan;
                } else {
                    $remaining[] = $orphan;
                }
            }
            $this->orphans = $remaining;
            foreach ($children as $orphan) {
                $block = $orphan['block'];
                $peer = $this->peerRecord($orphan['peer']);
                if (isset($this->rejected[$parentHash])) {
                    $this->rejectBlock('UNORPHAN', $block, $peer, 'bad-parent');
                } else {
                    $this->connectBlock('UNORPHAN', $block, $peer);
                }
                $queue[] = $block->hash;
            }
        }
    }

    private function receiveBlock(Block $block, object $peer): void
    {
        $duplicate = isset($this->blocks[$block->hash]) || isset($this->rejected[$block->hash]);
        foreach ($this->orphans as $orphan) {
            if ($orphan['block']->hash === $block->hash) {
                $duplicate = true;
                break;
            }
        }
        if ($duplicate) {
            $this->message('BLOCK ' . $peer->name . ' ' . $block->height . ' ' . shortHash($block->hash) . ' rejected duplicate');
            $peer->rejectedBlocks++;
            $this->tally('block', 'duplicate');
            return;
        }
        $reason = contextFreeCheck($block, $this->settings['maxBlock']);
        if ($reason === null && isset($this->rejected[$block->previous])) {
            $reason = 'bad-parent';
        }
        if ($reason !== null) {
            $this->rejectBlock('BLOCK', $block, $peer, $reason);
            $this->resolveOrphans($block->hash);
            return;
        }
        if (!isset($this->blocks[$block->previous])) {
            $this->orphans[] = ['block' => $block, 'peer' => $peer->name];
            $peer->orphans++;
            $this->message('BLOCK ' . $peer->name . ' ' . $block->height . ' ' . shortHash($block->hash) . ' orphan parent ' . shortHash($block->previous));
            if (count($this->orphans) > $this->settings['maxOrphans']) {
                $oldest = array_shift($this->orphans);
                $this->message('EVICT ' . shortHash($oldest['block']->hash) . ' orphan-limit');
            }
            return;
        }
        $this->connectBlock('BLOCK', $block, $peer);
        $this->resolveOrphans($block->hash);
    }

    private function status(string $txid): void
    {
        $prefix = 'STATUS ' . shortHash($txid);
        if (isset($this->mainTransactions[$txid])) {
            $height = $this->mainTransactions[$txid]['height'];
            $this->message($prefix . ' confirmed ' . $height . ' confirmations ' . ($this->nextHeight() - $height));
            return;
        }
        $priority = $this->priority();
        foreach ($priority as $index => $entry) {
            if ($entry['transaction']->txid === $txid) {
                $this->message($prefix . ' mempool rank ' . ($index + 1) . ' of ' . count($priority));
                return;
            }
        }
        if (isset($this->dropped[$txid])) {
            $this->message($prefix . ' dropped ' . $this->dropped[$txid]);
            return;
        }
        foreach ($this->blocks as $stored) {
            foreach ($stored->block->transactions as $transaction) {
                if ($transaction->txid === $txid) {
                    $this->message($prefix . ' stale');
                    return;
                }
            }
        }
        $this->message($prefix . ' unknown');
    }

    private function printState(): void
    {
        $size = 0;
        foreach ($this->pool as $entry) {
            $size += $entry['transaction']->size;
        }
        $this->message('PRINT height ' . $this->tip->block->height . ' tip ' . shortHash($this->tip->block->hash) . ' work ' . $this->tip->work .
            ' bits ' . requiredDifficulty($this->tip, $this->settings) . ' reward ' . reward($this->nextHeight(), $this->settings) .
            ' mempool ' . count($this->pool) . ' size ' . $size . ' orphans ' . count($this->orphans));
        foreach ($this->priority() as $i => $entry) {
            $this->message('MEMPOOL ' . ($i + 1) . ' ' . shortHash($entry['transaction']->txid) .
                ' fee ' . $entry['fee'] . ' size ' . $entry['transaction']->size);
        }
        foreach ($this->wallets as $wallet) {
            $balance = 0;
            foreach ($this->tip->utxo as $coin) {
                if ($coin['address'] === $wallet['address']) {
                    $balance += $coin['amount'];
                }
            }
            $this->message('BALANCE ' . $wallet['name'] . ' ' . $balance);
        }
    }

    public function processEvents(): void
    {
        foreach ($this->events as $event) {
            $this->time = $event['time'];
            foreach ($this->pool as $entry) {
                if ($this->time - $entry['arrival'] >= $this->settings['expiry']) {
                    $this->drop($entry, 'expired');
                }
            }
            $kind = $event['kind'];
            $tokens = $event['tokens'];
            if ($kind === 'TX' || $kind === 'BLOCK') {
                $peer = $this->peerRecord($tokens[2]);
                if ($peer->score >= $this->settings['banThreshold']) {
                    $peer->ignored++;
                    $this->message('IGNORE ' . $peer->name . ' ' . $kind);
                    continue;
                }
            }
            switch ($kind) {
                case 'PAY':
                    $this->pay($tokens);
                    break;
                case 'BUMP':
                    $this->bump($tokens[2], (int) $tokens[3]);
                    break;
                case 'TX':
                    $this->receiveTransaction($event['transaction'], $peer);
                    break;
                case 'MINE':
                    $this->mine($tokens[2]);
                    break;
                case 'BLOCK':
                    $this->receiveBlock($event['block'], $peer);
                    break;
                case 'STATUS':
                    $this->status($tokens[2]);
                    break;
                case 'PRINT':
                    $this->printState();
                    break;
            }
        }
    }

    private function chainLines(): array
    {
        $lines = ['TIP ' . $this->tip->block->height . ' ' . $this->tip->block->hash . ' work ' . $this->tip->work .
            ' stored ' . count($this->blocks) . ' orphans ' . count($this->orphans)];
        $mainHashes = [];
        foreach ($this->mainChain as $stored) {
            $block = $stored->block;
            $mainHashes[$block->hash] = true;
            $miner = $block->height === 0 ? '-' : $this->owners[$block->transactions[0]->outputs[0]['address']]['name'];
            $lines[] = 'BLOCK ' . $block->height . ' ' . $block->hash . ' prev ' . shortHash($block->previous) . ' time ' . $block->timestamp .
                ' bits ' . $block->difficulty . ' nonce ' . $block->nonce . ' txs ' . count($block->transactions) . ' size ' . $block->size .
                ' fees ' . $stored->fees . ' miner ' . $miner . ' source ' . $stored->source . ' work ' . $stored->work;
            foreach ($block->transactions as $i => $transaction) {
                $prefix = 'TX ' . ($i + 1) . ' ' . $transaction->txid;
                if ($transaction->coinbase) {
                    $category = $block->height === 0 ? 'genesis' : 'coinbase';
                    $lines[] = $prefix . ' ' . $category . ' out ' . count($transaction->outputs) . ' amount ' . outputTotal($transaction);
                } else {
                    $lines[] = $prefix . ' payment in ' . count($transaction->inputs) . ' out ' . count($transaction->outputs) .
                        ' size ' . $transaction->size . ' fee ' . $stored->transactionFees[$i];
                }
            }
        }
        $stale = array_values(array_filter($this->blocks, fn($stored) => !isset($mainHashes[$stored->block->hash])));
        usort($stale, fn($a, $b) => ($a->block->height <=> $b->block->height) ?: strcmp($a->block->hash, $b->block->hash));
        foreach ($stale as $stored) {
            $block = $stored->block;
            $lines[] = 'STALE ' . $block->height . ' ' . $block->hash . ' prev ' . shortHash($block->previous) .
                ' source ' . $stored->source . ' work ' . $stored->work;
        }
        foreach ($this->orphans as $orphan) {
            $block = $orphan['block'];
            $lines[] = 'ORPHAN ' . $block->height . ' ' . $block->hash . ' prev ' . shortHash($block->previous) . ' source ' . $orphan['peer'];
        }
        foreach ($this->reorganizations as $change) {
            $lines[] = 'REORG ' . $change['time'] . ' fork ' . $change['fork'] . ' disconnected ' . $change['disconnected'] .
                ' connected ' . $change['connected'] . ' old ' . shortHash($change['old']) . ' new ' . shortHash($change['next']);
        }
        foreach ($this->wallets as $wallet) {
            $count = 0;
            $coinbaseTotal = 0;
            $fees = 0;
            foreach ($this->mainChain as $stored) {
                $block = $stored->block;
                if ($block->height > 0 && $block->transactions[0]->outputs[0]['address'] === $wallet['address']) {
                    $count++;
                    $coinbaseTotal += outputTotal($block->transactions[0]);
                    $fees += $stored->fees;
                }
            }
            if ($count > 0) {
                $lines[] = 'MINER ' . $wallet['name'] . ' blocks ' . $count . ' coinbase ' . $coinbaseTotal . ' fees ' . $fees;
            }
        }
        for ($first = 1; $first < count($this->mainChain);) {
            $last = $first;
            while ($last + 1 < count($this->mainChain) &&
                $this->mainChain[$last + 1]->block->difficulty === $this->mainChain[$first]->block->difficulty) {
                $last++;
            }
            $lines[] = 'BITS ' . $this->mainChain[$first]->block->difficulty . ' heights ' . $this->mainChain[$first]->block->height .
                '-' . $this->mainChain[$last]->block->height . ' blocks ' . ($last - $first + 1);
            $first = $last + 1;
        }
        $peers = $this->peers;
        ksort($peers, SORT_STRING);
        foreach ($peers as $peer) {
            $state = $peer->score >= $this->settings['banThreshold'] ? 'banned' : 'ok';
            $lines[] = 'PEER ' . $peer->name . ' blocks ' . $peer->blocks . ' rejected ' . $peer->rejectedBlocks . ' orphans ' . $peer->orphans .
                ' txs ' . $peer->transactions . ' rejected ' . $peer->rejectedTransactions . ' ignored ' . $peer->ignored .
                ' score ' . $peer->score . ' ' . $state;
        }
        foreach ($this->priority() as $i => $entry) {
            $lines[] = 'MEMPOOL ' . ($i + 1) . ' ' . $entry['transaction']->txid . ' fee ' . $entry['fee'] .
                ' size ' . $entry['transaction']->size . ' time ' . $entry['arrival'];
        }
        $rejections = $this->rejections;
        ksort($rejections, SORT_STRING);
        foreach ($rejections as $key => $count) {
            $lines[] = 'REJECT ' . $key . ' ' . $count;
        }
        $rewards = 0;
        $fees = 0;
        $coinbaseTotal = 0;
        foreach (array_slice($this->mainChain, 1) as $stored) {
            $rewards += reward($stored->block->height, $this->settings);
            $fees += $stored->fees;
            $coinbaseTotal += outputTotal($stored->block->transactions[0]);
        }
        $lines[] = 'SUPPLY genesis ' . outputTotal($this->genesis->block->transactions[0]) . ' rewards ' . $rewards . ' fees ' . $fees .
            ' burned ' . ($rewards + $fees - $coinbaseTotal) . ' utxo ' . array_sum(array_column($this->tip->utxo, 'amount'));
        return $lines;
    }

    private function balanceLines(): array
    {
        $lines = ['wallet,address,balance,immature,locked,incoming,utxos'];
        $locked = $this->lockedReferences();
        foreach ($this->wallets as $wallet) {
            $balance = 0;
            $immature = 0;
            $reserved = 0;
            $incoming = 0;
            $count = 0;
            foreach ($this->tip->utxo as $key => $coin) {
                if ($coin['address'] !== $wallet['address']) {
                    continue;
                }
                $count++;
                $balance += $coin['amount'];
                if (!mature($coin, $this->nextHeight(), $this->settings['maturity'])) {
                    $immature += $coin['amount'];
                }
                if (isset($locked[$key])) {
                    $reserved += $coin['amount'];
                }
            }
            foreach ($this->pool as $entry) {
                foreach ($entry['transaction']->outputs as $output) {
                    if ($output['address'] === $wallet['address']) {
                        $incoming += $output['amount'];
                    }
                }
            }
            $lines[] = implode(',', [$wallet['name'], $wallet['address'], $balance, $immature, $reserved, $incoming, $count]);
        }
        return $lines;
    }

    private function utxoLines(): array
    {
        $locked = $this->lockedReferences();
        $coins = array_values($this->tip->utxo);
        usort($coins, 'referenceOrder');
        $lines = [];
        $total = 0;
        foreach ($coins as $coin) {
            $reference = $coin['txid'] . ':' . $coin['index'];
            $category = $coin['height'] === 0 ? 'genesis' : ($coin['coinbase'] ? 'coinbase' : 'payment');
            $state = !mature($coin, $this->nextHeight(), $this->settings['maturity']) ? 'immature' :
                (isset($locked[$reference]) ? 'locked' : 'free');
            $lines[] = $reference . ' ' . $this->owners[$coin['address']]['name'] . ' ' . $coin['amount'] .
                ' height ' . $coin['height'] . ' ' . $category . ' ' . $state;
            $total += $coin['amount'];
        }
        $root = merkleRoot(array_map('ledgerHash', $lines));
        $lines[] = 'TOTAL ' . count($coins) . ' ' . $total;
        $lines[] = 'ROOT ' . $root;
        return $lines;
    }

    private function historyLines(): array
    {
        $lines = [];
        $priority = $this->priority();
        foreach ($this->wallets as $wallet) {
            $lines[] = 'WALLET ' . $wallet['name'] . ' ' . $wallet['address'];
            $count = 0;
            $totalSpent = 0;
            $totalReceived = 0;
            $balance = 0;
            foreach ($this->mainChain as $stored) {
                $block = $stored->block;
                foreach ($block->transactions as $transaction) {
                    $spent = 0;
                    foreach ($transaction->inputs as $input) {
                        $previous = $this->mainTransactions[$input['txid']]['transaction'];
                        $output = $previous->outputs[$input['index']];
                        if ($output['address'] === $wallet['address']) {
                            $spent += $output['amount'];
                        }
                    }
                    $received = 0;
                    foreach ($transaction->outputs as $output) {
                        if ($output['address'] === $wallet['address']) {
                            $received += $output['amount'];
                        }
                    }
                    if ($spent === 0 && $received === 0) {
                        continue;
                    }
                    $net = $received - $spent;
                    $balance += $net;
                    $count++;
                    $totalSpent += $spent;
                    $totalReceived += $received;
                    $category = $block->height === 0 ? 'genesis' : ($transaction->coinbase ? 'coinbase' : 'payment');
                    $lines[] = $block->height . ' ' . shortHash($transaction->txid) . ' ' . $category . ' spent ' . $spent .
                        ' received ' . $received . ' net ' . signedAmount($net) . ' balance ' . $balance;
                }
            }
            $pending = 0;
            foreach ($priority as $entry) {
                $transaction = $entry['transaction'];
                $spent = 0;
                foreach ($transaction->inputs as $input) {
                    $coin = $this->tip->utxo[$input['key']];
                    if ($coin['address'] === $wallet['address']) {
                        $spent += $coin['amount'];
                    }
                }
                $received = 0;
                foreach ($transaction->outputs as $output) {
                    if ($output['address'] === $wallet['address']) {
                        $received += $output['amount'];
                    }
                }
                if ($spent !== 0 || $received !== 0) {
                    $pending++;
                    $lines[] = 'pending ' . shortHash($transaction->txid) . ' spent ' . $spent . ' received ' . $received .
                        ' net ' . signedAmount($received - $spent);
                }
            }
            $lines[] = 'END ' . $wallet['name'] . ' txs ' . $count . ' spent ' . $totalSpent . ' received ' . $totalReceived .
                ' balance ' . $balance . ' pending ' . $pending;
        }
        return $lines;
    }

    public function writeOutput(): void
    {
        if (!is_dir('output')) {
            mkdir('output', 0777, true);
        }
        $files = ['log.txt' => $this->log, 'chain.txt' => $this->chainLines(), 'balances.csv' => $this->balanceLines(),
            'utxo.txt' => $this->utxoLines(), 'history.txt' => $this->historyLines()];
        foreach ($files as $name => $lines) {
            file_put_contents('output/' . $name, $lines ? implode("\n", $lines) . "\n" : '');
        }
    }
}

[$settings, $events, $wallets] = readInput();
$node = new Node($settings, $events, $wallets);
$node->processEvents();
$node->writeOutput();
