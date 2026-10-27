<?php

function readInputLines(string $filename): array
{
    return file('input/' . $filename, FILE_IGNORE_NEW_LINES);
}

function readInputs(): object
{
    $cases = [];
    $deaths = [];
    foreach (array_slice(readInputLines('cases.csv'), 1) as $line) {
        [$day, $casesValue, $deathsValue] = array_map('intval', explode(',', $line));
        $cases[] = $casesValue;
        $deaths[] = $deathsValue;
    }
    $groups = [];
    $contacts = [];
    foreach (readInputLines('population.txt') as $line) {
        $fields = explode(' ', $line);
        if ($fields[0] === 'group') {
            $groups[] = (object) ['name' => $fields[1], 'population' => (int) $fields[2], 'fatality' => (float) $fields[3]];
        } else {
            $contacts[] = array_map('floatval', array_slice($fields, 1));
        }
    }
    $interventions = [];
    foreach (readInputLines('interventions.txt') as $line) {
        [$day, $multiplier] = explode(' ', $line);
        $interventions[] = (object) ['day' => (int) $day, 'multiplier' => (float) $multiplier];
    }
    $settings = [];
    $scenarios = [];
    $contactChanges = [];
    foreach (readInputLines('params.txt') as $line) {
        $fields = explode(' ', $line);
        $key = array_shift($fields);
        if ($key === 'scenario') {
            $scenarios[] = (object) ['name' => $fields[0], 'multiplier' => (float) $fields[1]];
        } elseif ($key === 'contact_change') {
            $contactChanges[] = (object) ['name' => $fields[0], 'group' => $fields[1], 'factor' => (float) $fields[2]];
        } else {
            $settings[$key] = $fields;
        }
    }
    $params = (object) [
        'sigma' => (float) $settings['sigma'][0], 'gamma' => (float) $settings['gamma'][0],
        'exposed' => (float) $settings['initial'][0], 'infectious' => (float) $settings['initial'][1],
        'betaMin' => (float) $settings['beta_grid'][0], 'betaMax' => (float) $settings['beta_grid'][1], 'betaCount' => (int) $settings['beta_grid'][2],
        'rhoMin' => (float) $settings['rho_grid'][0], 'rhoMax' => (float) $settings['rho_grid'][1], 'rhoCount' => (int) $settings['rho_grid'][2],
        'goldenIterations' => (int) $settings['golden'][0], 'rounds' => (int) $settings['golden'][1],
        'deltaBeta' => (float) $settings['simplex'][0], 'deltaGamma' => (float) $settings['simplex'][1],
        'alpha' => (float) $settings['nelder_mead'][0], 'chi' => (float) $settings['nelder_mead'][1],
        'psi' => (float) $settings['nelder_mead'][2], 'omega' => (float) $settings['nelder_mead'][3], 'iterations' => (int) $settings['nelder_mead'][4],
        'holdout' => (int) $settings['holdout'][0], 'effectWidth' => (float) $settings['effect_width'][0], 'outlier' => (float) $settings['outlier'][0],
        'deathLag' => (int) $settings['death_lag'][0], 'milestones' => array_map('intval', $settings['milestones']),
        'generation' => (int) $settings['generation'][0], 'horizon' => (int) $settings['horizon'][0], 'threshold' => (float) $settings['threshold'][0],
    ];
    return (object) compact('cases', 'deaths', 'groups', 'contacts', 'interventions', 'params', 'scenarios', 'contactChanges');
}

function writeOutputs(array $files): void
{
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    foreach ($files as $filename => $lines) {
        file_put_contents('output/' . $filename, implode("\n", $lines) . "\n");
    }
}
