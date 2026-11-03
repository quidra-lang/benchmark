<?php

require_once __DIR__ . '/transactions.php';

class Block
{
    public string $hash;
    public int $size = 0;

    public function __construct(
        public int $height, public string $previous, public string $root, public int $timestamp,
        public int $difficulty, public int $nonce, public array $transactions
    ) {
        $this->hash = ledgerHash($this->header());
        foreach (array_slice($transactions, 1) as $transaction) {
            $this->size += $transaction->size;
        }
    }

    public function header(): string
    {
        return implode('|', [$this->height, $this->previous, $this->root, $this->timestamp, $this->difficulty, $this->nonce]);
    }

    public function proofOfWork(): bool
    {
        return str_starts_with($this->hash, str_repeat('0', $this->difficulty));
    }
}

function parseBlock(array $fields, array $lines): Block
{
    return new Block((int) $fields[3], $fields[4], $fields[5], (int) $fields[6], (int) $fields[7], (int) $fields[8],
        array_map(fn($line) => new Transaction($line), $lines));
}

function mineBlock(int $height, string $previous, int $timestamp, int $difficulty, array $transactions): Block
{
    $root = merkleRoot(array_map(fn($tx) => $tx->txid, $transactions));
    $block = new Block($height, $previous, $root, $timestamp, $difficulty, 0, $transactions);
    while (!$block->proofOfWork()) {
        $block->nonce++;
        $block->hash = ledgerHash($block->header());
    }
    return $block;
}

function contextFreeCheck(Block $block, int $maximumSize): ?string
{
    if (!$block->proofOfWork()) {
        return 'bad-pow';
    }
    if (merkleRoot(array_map(fn($tx) => $tx->txid, $block->transactions)) !== $block->root) {
        return 'bad-merkle';
    }
    $first = $block->transactions[0];
    if (!$first->coinbase || $first->height !== $block->height) {
        return 'bad-structure';
    }
    foreach (array_slice($block->transactions, 1) as $transaction) {
        if ($transaction->coinbase) {
            return 'bad-structure';
        }
    }
    return $block->size > $maximumSize ? 'too-large' : null;
}
