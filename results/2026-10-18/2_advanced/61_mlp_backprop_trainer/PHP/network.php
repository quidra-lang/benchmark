<?php

class Network
{
    public string $name;
    public array $initial;
    public array $layers = [];
    public array $weightIndices = [];
    public int $parameterCount;
    public int $classes;
    public string $outputType;

    public function __construct(object $definition, int $inputSize, array $initial)
    {
        $this->name = $definition->name;
        $this->initial = $initial;
        $offset = 0;
        $inputs = $inputSize;
        foreach ($definition->layers as $definitionLayer) {
            $biasOffset = $offset + $definitionLayer->units * $inputs;
            $end = $biasOffset + $definitionLayer->units;
            $this->layers[] = (object) ['units' => $definitionLayer->units, 'activation' => $definitionLayer->activation,
                'inputs' => $inputs, 'offset' => $offset, 'biasOffset' => $biasOffset, 'end' => $end];
            for ($p = $offset; $p < $biasOffset; $p++) {
                $this->weightIndices[] = $p;
            }
            $offset = $end;
            $inputs = $definitionLayer->units;
        }
        $this->parameterCount = $offset;
        $last = $this->layers[count($this->layers) - 1];
        $this->classes = $last->units;
        $this->outputType = $last->activation;
    }

    public function forward(array $theta, object $image): object
    {
        $activations = [$image->vector];
        $preactivations = [];
        foreach ($this->layers as $l => $layer) {
            $values = preactivate($theta, $layer, $activations[$l]);
            $preactivations[] = $values;
            if ($l + 1 < count($this->layers)) {
                $activations[] = array_map(fn($value) => activate($layer->activation, $value), $values);
            } else {
                $result = outputLayer($layer->activation, $values, $image->label);
                $activations[] = $result->scores;
            }
        }
        $result->activations = $activations;
        $result->preactivations = $preactivations;
        return $result;
    }

    public function backward(array $theta, object $forward): object
    {
        $count = count($this->layers);
        $deltas = array_fill(0, $count, []);
        $deltas[$count - 1] = $forward->errors;
        for ($l = $count - 2; $l >= 0; $l--) {
            $propagated = propagate($theta, $this->layers[$l + 1], $deltas[$l + 1]);
            foreach ($propagated as $j => $value) {
                $deltas[$l][] = $value * derivative($this->layers[$l]->activation,
                    $forward->preactivations[$l][$j], $forward->activations[$l + 1][$j]);
            }
        }
        $gradient = array_fill(0, $this->parameterCount, 0.0);
        foreach ($this->layers as $l => $layer) {
            for ($j = 0; $j < $layer->units; $j++) {
                for ($i = 0; $i < $layer->inputs; $i++) {
                    $gradient[$layer->offset + $j * $layer->inputs + $i] = $deltas[$l][$j] * $forward->activations[$l][$i];
                }
                $gradient[$layer->biasOffset + $j] = $deltas[$l][$j];
            }
        }
        return (object) ['gradient' => $gradient, 'inputGradient' => propagate($theta, $this->layers[0], $deltas[0])];
    }
}
