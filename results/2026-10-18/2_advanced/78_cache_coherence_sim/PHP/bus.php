<?php

class Bus
{
    public int $free = 0;
    public int $wait = 0;
    public int $busy = 0;
    public array $transactions = [];
    private int $latency;

    public function __construct(int $latency)
    {
        $this->latency = $latency;
    }

    public function assign(int $request, int $core, string $type, int $block): int
    {
        $start = max($request, $this->free);
        $this->wait += $start - $request;
        $this->free = $start + $this->latency;
        $this->busy += $this->latency;
        $index = count($this->transactions);
        $this->transactions[] = ['number' => $index + 1, 'start' => $start, 'core' => $core, 'type' => $type,
            'block' => $block, 'snoops' => [], 'invalidations' => 0, 'supplier' => null, 'l2' => null, 'eviction' => null];
        return $index;
    }

    public function lines(int $lineSize): array
    {
        $lines = [];
        foreach ($this->transactions as $tx) {
            $line = $tx['number'] . ' ' . $tx['start'] . ' c' . $tx['core'] . ' ' . $tx['type'] . ' ' . hexAddress($tx['block'] * $lineSize);
            if ($tx['type'] !== 'WB') {
                $line .= ' snoop ' . ($tx['snoops'] ? implode(' ', $tx['snoops']) : 'none');
                if ($tx['type'] !== 'BusUpgr') {
                    if ($tx['type'] === 'BusRd' || $tx['type'] === 'BusRdX') {
                        $source = $tx['supplier'] !== null ? 'c' . $tx['supplier'] : ($tx['l2'] === 'hit' ? 'L2' : 'mem');
                        $line .= ' data ' . $source;
                    }
                    $line .= ' l2 ' . $tx['l2'];
                    if ($tx['eviction'] !== null) {
                        $eviction = $tx['eviction'];
                        $line .= ' evict ' . hexAddress($eviction['block'] * $lineSize) . ' ' .
                            ($eviction['copies'] ? implode(' ', $eviction['copies']) : 'none') . ' ' .
                            ($eviction['dirty'] ? 'dirty' : 'clean');
                    }
                }
            }
            $lines[] = $line;
        }
        return $lines;
    }
}
