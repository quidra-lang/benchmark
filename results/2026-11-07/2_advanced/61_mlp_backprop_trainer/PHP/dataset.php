<?php

function inputLines(string $filename): array
{
    return file('input/' . $filename, FILE_IGNORE_NEW_LINES);
}

function readImages(string $filename): array
{
    $images = [];
    foreach (array_slice(inputLines($filename), 1) as $line) {
        [$id, $label, $pixels] = explode(',', $line);
        $vector = [];
        for ($i = 0; $i < strlen($pixels); $i++) {
            $vector[] = $pixels[$i] === '1' ? 1.0 : 0.0;
        }
        $images[] = (object) ['id' => $id, 'label' => (int) $label, 'pixels' => $pixels, 'vector' => $vector];
    }
    return $images;
}

function readNetworks(): object
{
    $source = inputLines('network.txt');
    [, $width, $height] = explode(' ', $source[0]);
    $networks = [];
    foreach (array_slice($source, 2) as $line) {
        if ($line === '') {
            continue;
        }
        [$kind, $first, $second] = array_pad(explode(' ', $line), 3, null);
        if ($kind === 'NETWORK') {
            $networks[] = (object) ['name' => $first, 'layers' => []];
        } else {
            $networks[count($networks) - 1]->layers[] = (object) ['units' => (int) $first, 'activation' => $second];
        }
    }
    return (object) ['width' => (int) $width, 'height' => (int) $height, 'networks' => $networks];
}

function readWeights(): array
{
    $weights = [];
    $key = '';
    foreach (inputLines('weights.txt') as $line) {
        if ($line === '') {
            continue;
        }
        $parts = explode(' ', $line);
        $kind = array_shift($parts);
        if ($kind === 'NETWORK') {
            $key = '#' . $parts[0];
            $weights[$key] = [];
        } elseif ($kind === 'W' || $kind === 'B') {
            foreach ($parts as $value) {
                $weights[$key][] = (float) $value;
            }
        }
    }
    return $weights;
}

function readSettings(): object
{
    $settings = (object) ['runs' => []];
    $single = ['SEED' => 'seed', 'BATCH_SIZE' => 'batchSize', 'MAX_EPOCHS' => 'maxEpochs',
        'PATIENCE' => 'patience', 'GRADIENT_CHECK_STRIDE' => 'stride', 'CALIBRATION_BINS' => 'bins'];
    foreach (inputLines('params.txt') as $line) {
        $parts = explode(' ', $line);
        $key = array_shift($parts);
        if (isset($single[$key])) {
            $settings->{$single[$key]} = (int) $parts[0];
        } elseif ($key === 'LR_STEP') {
            $settings->step = (int) $parts[0];
            $settings->gamma = (float) $parts[1];
        } elseif ($key === 'PRUNE') {
            $settings->prune = array_map('intval', $parts);
        } elseif ($key === 'NOISE') {
            $settings->noise = array_map('intval', $parts);
        } else {
            [$name, $network, $optimizer, $eta, $decay] = $parts;
            $run = (object) ['name' => $name, 'network' => $network, 'optimizer' => $optimizer, 'eta' => (float) $eta,
                'decay' => (float) $decay, 'order' => count($settings->runs)];
            if ($optimizer === 'MOMENTUM') {
                $run->mu = (float) $parts[5];
            } elseif ($optimizer === 'ADAM') {
                $run->beta1 = (float) $parts[5];
                $run->beta2 = (float) $parts[6];
                $run->epsilon = (float) $parts[7];
            }
            $settings->runs[] = $run;
        }
    }
    return $settings;
}

function readInputs(): object
{
    $input = readNetworks();
    $input->weights = readWeights();
    $input->settings = readSettings();
    $input->train = readImages('train.csv');
    $input->test = readImages('test.csv');
    return $input;
}

class Minstd
{
    private int $state;

    public function __construct(int $seed)
    {
        $this->state = $seed;
    }

    public function next(): int
    {
        $this->state = (48271 * $this->state) % 2147483647;
        return $this->state;
    }

    public function shuffle(array &$values): void
    {
        for ($i = count($values) - 1; $i > 0; $i--) {
            $j = $this->next() % ($i + 1);
            [$values[$i], $values[$j]] = [$values[$j], $values[$i]];
        }
    }
}
