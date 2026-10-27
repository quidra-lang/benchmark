<?php

const BUS_TYPES = ['BusRd', 'BusRdX', 'BusUpgr', 'BusWr', 'WB'];

function dirtyState(string $state): bool
{
    return $state === 'M' || $state === 'O';
}

function requestTransition(string $protocol, string $old, string $operation): array
{
    if ($protocol === 'VI') {
        if ($operation === 'R') return $old === 'I' ? ['BusRd', 'V'] : [null, 'V'];
        return ['BusWr', $old === 'I' ? 'I' : 'V'];
    }
    if ($old === 'I') {
        if ($operation === 'W') return ['BusRdX', 'M'];
        return ['BusRd', $protocol === 'MSI' ? 'S' : 'ES'];
    }
    if ($operation === 'R') return [null, $old];
    if ($old === 'M' || $old === 'E') return [null, 'M'];
    return ['BusUpgr', 'M'];
}

function snoopTransition(string $protocol, string $old, string $type): array
{
    if ($protocol === 'VI') return [$type === 'BusRd' ? 'V' : 'I', false, false];
    if ($type === 'BusRd') {
        if ($old === 'M') return $protocol === 'MOESI' ? ['O', true, false] : ['S', true, true];
        if ($old === 'O') return ['O', true, false];
        return ['S', false, false];
    }
    if ($type === 'BusRdX') return ['I', dirtyState($old), false];
    return ['I', false, false];
}
