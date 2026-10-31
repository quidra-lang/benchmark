<?php

$program = [
    'SET A 1', 'SET B 1', 'SET D 8', 'MUL A B', 'PRINT A', 'ADD B 1', 'SUB D 1', 'JNZ D -4',
    'SET A 1071', 'SET B 462', 'SET C A', 'MOD C B', 'SET A B', 'SET B C', 'JNZ B -4', 'PRINT A',
    'HALT',
];
$registers = ['A' => 0, 'B' => 0, 'C' => 0, 'D' => 0];
$value = function (string $token) use (&$registers): int {
    return array_key_exists($token, $registers) ? $registers[$token] : (int) $token;
};
$pc = $executed = 0;
while ($pc >= 0 && $pc < count($program)) {
    $parts = explode(' ', $program[$pc]);
    $operation = $parts[0];
    $executed++;
    if ($operation === 'HALT') {
        break;
    }
    if ($operation === 'JNZ') {
        $pc += $value($parts[1]) !== 0 ? (int) $parts[2] : 1;
        continue;
    } elseif ($operation === 'PRINT') {
        printf("%d\n", $value($parts[1]));
    } else {
        $register = $parts[1];
        $operand = $value($parts[2]);
        $registers[$register] = match ($operation) {
            'SET' => $operand,
            'ADD' => $registers[$register] + $operand,
            'SUB' => $registers[$register] - $operand,
            'MUL' => $registers[$register] * $operand,
            'MOD' => $registers[$register] % $operand,
        };
    }
    $pc++;
}
printf("executed: %d\n", $executed);
