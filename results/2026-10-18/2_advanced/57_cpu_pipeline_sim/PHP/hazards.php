<?php

function attachSources(array &$instructions): void
{
    $lastWriter = array_fill(0, 32, null);
    foreach ($instructions as $i => &$instruction) {
        $instruction['sources'] = [];
        foreach (['rs1', 'rs2'] as $slot) {
            $register = $instruction[$slot];
            if ($register !== null && $register !== 0) {
                $instruction['sources'][] = ['slot' => $slot, 'register' => $register, 'producer' => $lastWriter[$register]];
            }
        }
        if ($instruction['rd'] !== null && $instruction['rd'] !== 0) $lastWriter[$instruction['rd']] = $i;
    }
    unset($instruction);
}

function idResolved(array $instruction, array $variant): bool
{
    if ($instruction['className'] === 'JUMP') return $instruction['rs1'] === null || $variant['resolution'] === 'ID';
    return $instruction['className'] === 'BRANCH' && $variant['resolution'] === 'ID';
}

function readyCycle(array $source, array $consumer, array $variant, array $instructions, array $times): ?int
{
    if ($source['producer'] === null) return null;
    $producer = $instructions[$source['producer']];
    $time = $times[$source['producer']];
    if (!$variant['forwarding']) return $time['W'] + 1;
    return ($producer['className'] === 'LOAD' ? $time['W'] : $time['M']) + (idResolved($consumer, $variant) ? 1 : 0);
}

function forwardingPath(array $source, int $consumerIndex, array $variant, array $instructions, array $times): string
{
    if (!$variant['forwarding'] || $source['producer'] === null) return 'regfile';
    $early = idResolved($instructions[$consumerIndex], $variant);
    $usedAt = $times[$consumerIndex]['X'] - ($early ? 1 : 0);
    $producer = $times[$source['producer']];
    if ($producer['M'] === $usedAt) return 'ex_mem';
    if (!$early && $producer['W'] === $usedAt) return 'mem_wb';
    return 'regfile';
}
