<?php
const CONTROL_CONSTANTS = [
    2 => [1.880,2.659,0.0,3.267,0.0,3.267,1.128,0.7979], 3 => [1.023,1.954,0.0,2.568,0.0,2.574,1.693,0.8862],
    4 => [0.729,1.628,0.0,2.266,0.0,2.282,2.059,0.9213], 5 => [0.577,1.427,0.0,2.089,0.0,2.114,2.326,0.9400],
    6 => [0.483,1.287,0.030,1.970,0.0,2.004,2.534,0.9515], 7 => [0.419,1.182,0.118,1.882,0.076,1.924,2.704,0.9594],
    8 => [0.373,1.099,0.185,1.815,0.136,1.864,2.847,0.9650], 9 => [0.337,1.032,0.239,1.761,0.184,1.816,2.970,0.9693],
    10 => [0.308,0.975,0.284,1.716,0.223,1.777,3.078,0.9727]
];
function read_rows(string $name): array { return array_map(fn($line) => array_map('intval', explode(',', $line)), array_slice(file("input/$name", FILE_IGNORE_NEW_LINES), 1)); }
function read_settings(): array {
    $settings = ['rules' => []];
    foreach (file('input/spec.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $words = explode(' ', $line); $name = array_shift($words);
        if ($name === 'rules') { $chart = array_shift($words); $settings['rules'][$chart] = array_map('intval', $words); }
        else $settings[$name] = $name === 'characteristic' ? $words[0] : (in_array($name, ['cusum_k','cusum_h','ewma_lambda','ewma_l','ci_z'], true) ? (float)$words[0] : (int)$words[0]);
    }
    return $settings;
}
