<?php

require_once __DIR__ . '/wallets.php';

class Transaction
{
    public string $txid;
    public int $size;
    public bool $coinbase;
    public ?int $height = null;
    public array $inputs = [];
    public array $outputs = [];
    public array $signatures = [];
    public string $body = '';

    public function __construct(public string $text)
    {
        $this->txid = ledgerHash($text);
        $this->size = strlen($text);
        $fields = explode(';', $text);
        $this->coinbase = str_starts_with($text, 'cb=');
        foreach (explode(',', substr($fields[1], 4)) as $item) {
            [$address, $amount] = explode(':', $item);
            $this->outputs[] = ['address' => $address, 'amount' => (int) $amount];
        }
        if ($this->coinbase) {
            $this->height = (int) substr($fields[0], 3);
        } else {
            foreach (explode(',', substr($fields[0], 3)) as $reference) {
                [$txid, $index] = explode(':', $reference);
                $this->inputs[] = ['txid' => $txid, 'index' => (int) $index, 'key' => $reference];
            }
            $this->signatures = explode(',', substr($fields[2], 4));
            $this->body = substr($text, 0, strpos($text, ';sig='));
        }
    }
}

function outputText(array $outputs): string
{
    return implode(',', array_map(fn($out) => $out['address'] . ':' . $out['amount'], $outputs));
}

function payment(array $inputs, array $outputs, string $secret): Transaction
{
    $refs = array_map(fn($input) => $input['txid'] . ':' . $input['index'], $inputs);
    $body = 'in=' . implode(',', $refs) . ';out=' . outputText($outputs);
    $signatures = [];
    foreach ($inputs as $i => $_) {
        $signatures[] = signature($secret, $i, $body);
    }
    return new Transaction($body . ';sig=' . implode(',', $signatures));
}

function coinbase(int $height, array $outputs): Transaction
{
    return new Transaction('cb=' . $height . ';out=' . outputText($outputs));
}

function mature(array $coin, int $height, int $maturity): bool
{
    return !$coin['coinbase'] || $coin['height'] === 0 || $height >= $coin['height'] + $maturity;
}

function outputTotal(Transaction $transaction): int
{
    return array_sum(array_column($transaction->outputs, 'amount'));
}

function checkTransaction(Transaction $transaction, array $utxo, array $spent, int $height, int $maturity, array $owners): array
{
    foreach ($transaction->outputs as $out) {
        if (!isset($owners[$out['address']]) || $out['amount'] === 0) {
            return ['reason' => 'bad-output'];
        }
    }
    $seen = [];
    $inputTotal = 0;
    foreach ($transaction->inputs as $i => $input) {
        $key = $input['key'];
        if (isset($spent[$key]) || isset($seen[$key])) {
            return ['reason' => 'double-spend'];
        }
        $seen[$key] = true;
        if (!isset($utxo[$key])) {
            return ['reason' => 'missing-input'];
        }
        $coin = $utxo[$key];
        if (!mature($coin, $height, $maturity)) {
            return ['reason' => 'immature'];
        }
        if ($transaction->signatures[$i] !== signature($owners[$coin['address']]['secret'], $i, $transaction->body)) {
            return ['reason' => 'bad-sig'];
        }
        $inputTotal += $coin['amount'];
    }
    $outputTotal = outputTotal($transaction);
    return $inputTotal < $outputTotal ? ['reason' => 'overspend'] : ['fee' => $inputTotal - $outputTotal];
}

function applyTransaction(Transaction $transaction, array &$utxo, int $height): void
{
    foreach ($transaction->inputs as $input) {
        unset($utxo[$input['key']]);
    }
    foreach ($transaction->outputs as $index => $output) {
        $utxo[$transaction->txid . ':' . $index] = $output + [
            'txid' => $transaction->txid, 'index' => $index, 'height' => $height, 'coinbase' => $transaction->coinbase
        ];
    }
}
