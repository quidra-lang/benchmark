<?php
declare(strict_types=1);

namespace TextClassifier;

require_once __DIR__ . '/tokenizer.php';
require_once __DIR__ . '/vocabulary.php';
require_once __DIR__ . '/naive_bayes.php';
require_once __DIR__ . '/rocchio.php';
require_once __DIR__ . '/evaluation.php';

const BASE_MODELS = ['multinomial', 'bernoulli', 'complement', 'rocchio'];
const MODELS = ['multinomial', 'bernoulli', 'complement', 'rocchio', 'vote'];
const MODEL_PAIRS = [['multinomial', 'bernoulli'], ['multinomial', 'complement'], ['multinomial', 'rocchio'], ['bernoulli', 'complement'], ['bernoulli', 'rocchio'], ['complement', 'rocchio']];

function readLines(string $name): array { return file('input/' . $name, FILE_IGNORE_NEW_LINES); }
function writeLines(string $name, array $lines): void { file_put_contents('output/' . $name, implode("\n", $lines) . "\n"); }
function csvLine(array $fields): string { return implode(',', $fields); }

function joinParts(array $parts): array
{
    $lines = [];
    foreach ($parts as $part) {
        if ($lines !== []) {
            $lines[] = '';
        }
        array_push($lines, ...$part);
    }
    return $lines;
}

function hundredths(string $text): int
{
    [$whole, $fraction] = explode('.', $text);
    return (int)$whole * 100 + (int)$fraction;
}

function hundredthsText(int $value): string { return intdiv($value, 100) . '.' . str_pad((string)($value % 100), 2, '0', STR_PAD_LEFT); }

function classCountsText(array $names, array $counts): string
{
    $fields = [];
    foreach ($names as $label => $name) {
        $fields[] = $name . ' ' . $counts[$label];
    }
    return implode(' ', $fields);
}

function bucketOf(float|int $value, array $boundaries): int
{
    $bucket = 0;
    foreach ($boundaries as $boundary) {
        $bucket += (int)($value >= $boundary);
    }
    return $bucket;
}

function rounded4(float $value): int { return (int)round($value * 10000, 0, PHP_ROUND_HALF_UP); }

function rankedByRatio(array $entries): array
{
    usort($entries, static fn(array $a, array $b): int => ($b[0] * $a[1] <=> $a[0] * $b[1]) ?: ($a[2] <=> $b[2]));
    return $entries;
}

function evaluationFields(Evaluation $evaluation): array
{
    return [$evaluation->correct, realText($evaluation->microF1), realText($evaluation->macroF1)];
}

final class Settings
{
    public array $alphas;
    public int $minDf;
    public int $features;
    public bool $bigrams;
    public int $top;
    public array $curve;
    public array $sizes;
    public array $thresholds;
    public array $lengths;
    public int $iterations;
    public int $weight;
    public int $resamples;
    public int $seed;

    public function __construct(array $lines)
    {
        $values = [];
        foreach ($lines as $line) {
            $fields = explode(' ', $line);
            $values[$fields[0]] = array_slice($fields, 1);
        }
        $this->alphas = array_map(static fn(string $text): int => hundredths($text), $values['ALPHAS']);
        $this->minDf = (int)$values['MIN_DF'][0];
        $this->features = (int)$values['FEATURES'][0];
        $this->bigrams = $values['BIGRAMS'][0] === 'yes';
        $this->top = (int)$values['TOP'][0];
        $this->curve = array_map('intval', $values['CURVE']);
        $this->sizes = array_map('intval', $values['SIZES']);
        $this->thresholds = array_map(static fn(string $text): int => hundredths($text), $values['THRESHOLDS']);
        $this->lengths = array_map('intval', $values['LENGTHS']);
        $this->iterations = (int)$values['EM_ITERATIONS'][0];
        $this->weight = hundredths($values['EM_WEIGHT'][0]);
        $this->resamples = (int)$values['BOOTSTRAP'][0];
        $this->seed = (int)$values['BOOTSTRAP'][1];
    }
}

final class Document
{
    public function __construct(public string $name, public ?int $label, public Tokens $tokens) {}
}

final class VotePrediction
{
    public function __construct(public int $label, public float $score) {}
}

function majorityVote(array $labels, int $classCount): VotePrediction
{
    $votes = array_fill(0, $classCount, 0);
    foreach ($labels as $label) {
        $votes[$label]++;
    }
    $winner = $labels[0];
    foreach ($labels as $label) {
        if ($votes[$label] > $votes[$winner]) {
            $winner = $label;
        }
    }
    return new VotePrediction($winner, $votes[$winner] / count($labels));
}

final class FoldSummary
{
    public int $candidateCount;
    public int $vocabularySize;

    public function __construct(public int $trainCount, public int $validateCount, Vocabulary $vocabulary)
    {
        $this->candidateCount = $vocabulary->candidateCount;
        $this->vocabularySize = $vocabulary->size();
    }
}

final class CrossValidationRun
{
    public function __construct(public array $predictions, public Evaluation $evaluation, public array $foldCorrect) {}
}

final class Training
{
    public Vocabulary $vocabulary;
    public TrainingCounts $counts;
    public Rocchio $rocchio;
    public array $models = [];

    public function __construct(array $documents, public bool $useBigrams, int $classCount, int $minDf, int $size)
    {
        $sequences = array_map(static fn(Document $document): array => $document->tokens->terms($useBigrams), $documents);
        $labels = array_map(static fn(Document $document): int => $document->label, $documents);
        $this->vocabulary = new Vocabulary($sequences, $labels, $classCount, $minDf, $size);
        $encoded = array_map(fn(array $sequence): array => $this->vocabulary->encode($sequence), $sequences);
        $this->counts = new TrainingCounts($encoded, $labels, $classCount, $this->vocabulary->size());
        $this->rocchio = new Rocchio($encoded, $labels, $classCount, $this->vocabulary->frequencies);
    }

    public function train(array $alphas): void
    {
        foreach (NB_MODELS as $kind) {
            $this->models[$kind] = trainModel($kind, $this->counts, $alphas[$kind]);
        }
    }

    public function encode(Document $document): array { return $this->vocabulary->encode($document->tokens->terms($this->useBigrams)); }

    public function classify(string $model, array $sequence): Posterior|RocchioPrediction
    {
        return $model === 'rocchio' ? $this->rocchio->predict($sequence) : $this->models[$model]->predict($sequence);
    }
}

final class Experiment
{
    private Settings $settings;
    private array $classes;
    private int $classCount;
    private array $training = [];
    private array $tests = [];
    private array $unlabelled = [];
    private array $labelled = [];
    private array $truths = [];
    private array $folds = [];
    private array $cvRuns = [];
    private array $selected = [];
    private array $selectedRuns = [];
    private Training $final;
    private array $testSequences;
    private array $predictions = [];
    private array $correct = [];

    public function __construct()
    {
        $this->settings = new Settings(readLines('params.txt'));
        $stopwords = [];
        foreach (readLines('stopwords.txt') as $word) {
            $stopwords['#' . $word] = true;
        }
        $rows = $classes = [];
        foreach (readLines('train.txt') as $line) {
            [$label, $text] = explode("\t", $line, 2);
            $rows[] = [$label, $text];
            $classes['#' . $label] = $label;
        }
        $this->classes = array_values($classes);
        usort($this->classes, 'strcmp');
        $this->classCount = count($this->classes);
        $positions = [];
        foreach ($this->classes as $label => $name) {
            $positions['#' . $name] = $label;
        }
        foreach ($rows as $index => [$label, $text]) {
            $this->training[] = new Document((string)($index + 1), $positions['#' . $label], new Tokens($text, $stopwords));
        }
        foreach (readLines('test.txt') as $line) {
            [$name, $label, $text] = explode("\t", $line, 3);
            $truth = $label === '?' ? null : $positions['#' . $label];
            $this->tests[] = new Document($name, $truth, new Tokens($text, $stopwords));
            if ($truth !== null) {
                $this->labelled[] = count($this->tests) - 1;
                $this->truths[] = $truth;
            }
        }
        foreach (readLines('unlabelled.txt') as $index => $text) {
            $this->unlabelled[] = new Document((string)($index + 1), null, new Tokens($text, $stopwords));
        }
    }

    public function run(): void
    {
        $this->crossValidate();
        $this->selectAlphas();
        $this->trainFinal();
    }

    private function trained(array $documents, bool $useBigrams, int $size): Training
    {
        $training = new Training($documents, $useBigrams, $this->classCount, $this->settings->minDf, $size);
        $training->train($this->selected);
        return $training;
    }

    private function alphaText(string $model): string { return isset($this->selected[$model]) ? hundredthsText($this->selected[$model]) : '-'; }

    private function crossValidate(): void
    {
        $settings = $this->settings;
        $count = count($this->training);
        $nbPredictions = [];
        foreach (NB_MODELS as $kind) {
            $nbPredictions[$kind] = array_fill(0, count($settings->alphas), array_fill(0, $count, 0));
        }
        $rocchioPredictions = array_fill(0, $count, 0);
        for ($fold = 0; $fold < 5; $fold++) {
            $members = $heldOut = [];
            foreach ($this->training as $index => $document) {
                if ($index % 5 === $fold) {
                    $heldOut[] = $index;
                } else {
                    $members[] = $document;
                }
            }
            $training = new Training($members, $settings->bigrams, $this->classCount, $settings->minDf, $settings->features);
            $this->folds[] = new FoldSummary(count($members), count($heldOut), $training->vocabulary);
            $sequences = array_map(fn(int $index): array => $training->encode($this->training[$index]), $heldOut);
            foreach (NB_MODELS as $kind) {
                foreach ($settings->alphas as $position => $alpha) {
                    $model = trainModel($kind, $training->counts, $alpha);
                    foreach ($heldOut as $item => $index) {
                        $nbPredictions[$kind][$position][$index] = $model->predict($sequences[$item])->label;
                    }
                }
            }
            foreach ($heldOut as $item => $index) {
                $rocchioPredictions[$index] = $training->rocchio->predict($sequences[$item])->label;
            }
        }
        foreach (NB_MODELS as $kind) {
            $this->cvRuns[$kind] = array_map(fn(array $predictions): CrossValidationRun => $this->crossValidationRun($predictions), $nbPredictions[$kind]);
        }
        $this->cvRuns['rocchio'] = [$this->crossValidationRun($rocchioPredictions)];
    }

    private function crossValidationRun(array $predictions): CrossValidationRun
    {
        $truths = array_map(static fn(Document $document): int => $document->label, $this->training);
        $foldCorrect = array_fill(0, 5, 0);
        foreach ($truths as $index => $truth) {
            if ($truth === $predictions[$index]) {
                $foldCorrect[$index % 5]++;
            }
        }
        return new CrossValidationRun($predictions, new Evaluation($this->classCount, $truths, $predictions), $foldCorrect);
    }

    private function selectAlphas(): void
    {
        foreach (NB_MODELS as $kind) {
            $runs = $this->cvRuns[$kind];
            $best = 0;
            for ($position = 1; $position < count($runs); $position++) {
                if (rounded4($runs[$position]->evaluation->macroF1) > rounded4($runs[$best]->evaluation->macroF1)) {
                    $best = $position;
                }
            }
            $this->selected[$kind] = $this->settings->alphas[$best];
            $this->selectedRuns[$kind] = $runs[$best];
        }
        $this->selectedRuns['rocchio'] = $this->cvRuns['rocchio'][0];
    }

    private function trainFinal(): void
    {
        $this->final = $this->trained($this->training, $this->settings->bigrams, $this->settings->features);
        $this->testSequences = array_map(fn(Document $document): array => $this->final->encode($document), $this->tests);
        foreach (BASE_MODELS as $model) {
            $this->predictions[$model] = array_map(fn(array $sequence): Posterior|RocchioPrediction => $this->final->classify($model, $sequence), $this->testSequences);
        }
        foreach ($this->tests as $index => $document) {
            $labels = array_map(fn(string $model): int => $this->predictions[$model][$index]->label, BASE_MODELS);
            $this->predictions['vote'][] = majorityVote($labels, $this->classCount);
        }
        foreach (MODELS as $model) {
            $this->correct[$model] = array_map(fn(int $index): bool => $this->predictions[$model][$index]->label === $this->tests[$index]->label, $this->labelled);
        }
    }

    private function testEvaluations(Training $training): array
    {
        $sequences = array_map(fn(int $index): array => $training->encode($this->tests[$index]), $this->labelled);
        $evaluations = [];
        foreach (BASE_MODELS as $model) {
            $predicted = array_map(static fn(array $sequence): int => $training->classify($model, $sequence)->label, $sequences);
            $evaluations[] = new Evaluation($this->classCount, $this->truths, $predicted);
        }
        return $evaluations;
    }

    public function vocabularyLines(): array
    {
        $vocabulary = $this->final->vocabulary;
        $lines = ['documents ' . count($this->training) . ' terms ' . $vocabulary->termCount . ' candidates ' . $vocabulary->candidateCount . ' vocabulary ' . $vocabulary->size()];
        foreach ($vocabulary->ranking as $index => $entry) {
            $lines[] = ($index + 1) . ' ' . $entry->term . ' ' . $entry->frequency . ' ' . realText($entry->score) . ' ' . $this->classes[$entry->bestClass];
        }
        return $lines;
    }

    public function cvLines(): array
    {
        $lines = ['model,alpha,correct,accuracy,macro_f1,selected'];
        foreach (NB_MODELS as $kind) {
            foreach ($this->settings->alphas as $index => $alpha) {
                $fields = [$kind, hundredthsText($alpha), ...evaluationFields($this->cvRuns[$kind][$index]->evaluation), $alpha === $this->selected[$kind] ? 'yes' : 'no'];
                $lines[] = csvLine($fields);
            }
        }
        $lines[] = csvLine(['rocchio', '-', ...evaluationFields($this->cvRuns['rocchio'][0]->evaluation), 'yes']);
        return $lines;
    }

    public function predictionLines(): array
    {
        $lines = ['id,model,label,score'];
        foreach ($this->tests as $index => $document) {
            foreach (MODELS as $model) {
                $prediction = $this->predictions[$model][$index];
                $lines[] = csvLine([$document->name, $model, $this->classes[$prediction->label], realText($prediction->score)]);
            }
        }
        return $lines;
    }

    public function curveLines(): array
    {
        $lines = ['size,vocabulary,model,correct,accuracy,macro_f1'];
        foreach ($this->settings->curve as $size) {
            $training = $this->trained(array_slice($this->training, 0, $size), $this->settings->bigrams, $this->settings->features);
            foreach ($this->testEvaluations($training) as $index => $evaluation) {
                $lines[] = csvLine([$size, $training->vocabulary->size(), BASE_MODELS[$index], ...evaluationFields($evaluation)]);
            }
        }
        return $lines;
    }

    public function featureLines(): array
    {
        $lines = ['terms,features,vocabulary,model,correct,accuracy,macro_f1'];
        foreach ([['unigrams', false], ['bigrams', true]] as [$kind, $useBigrams]) {
            foreach ($this->settings->sizes as $size) {
                $training = $this->trained($this->training, $useBigrams, $size);
                foreach ($this->testEvaluations($training) as $index => $evaluation) {
                    $lines[] = csvLine([$kind, $size, $training->vocabulary->size(), BASE_MODELS[$index], ...evaluationFields($evaluation)]);
                }
            }
        }
        return $lines;
    }

    private function dataPart(): array
    {
        $settings = $this->settings;
        $vocabulary = $this->final->vocabulary;
        $lines = ['documents train ' . count($this->training) . ' test ' . count($this->tests) . ' labelled ' . count($this->labelled)
            . ' unlabelled ' . count($this->unlabelled) . ' classes ' . $this->classCount];
        $trainCounts = $testCounts = array_fill(0, $this->classCount, 0);
        foreach ($this->training as $document) {
            $trainCounts[$document->label]++;
        }
        foreach ($this->truths as $truth) {
            $testCounts[$truth]++;
        }
        foreach ($this->classes as $label => $name) {
            $lines[] = "class $name train " . $trainCounts[$label] . ' test ' . $testCounts[$label];
        }
        $raw = $stopwords = $short = $kept = $bigrams = 0;
        $terms = [];
        foreach ($this->training as $document) {
            $tokens = $document->tokens;
            $raw += $tokens->rawCount;
            $stopwords += $tokens->stopwordCount;
            $short += $tokens->shortCount;
            $kept += count($tokens->words);
            if ($settings->bigrams) {
                $bigrams += count($tokens->bigrams);
            }
            foreach ($tokens->terms($settings->bigrams) as $term) {
                $terms['#' . $term] = $term;
            }
        }
        $distinctBigrams = 0;
        foreach ($terms as $term) {
            $distinctBigrams += (int)isBigram($term);
        }
        $lines[] = "train_tokens raw $raw stopwords $stopwords short $short unigrams $kept bigrams $bigrams";
        $lines[] = 'train_terms unigrams ' . (count($terms) - $distinctBigrams) . " bigrams $distinctBigrams candidates "
            . $vocabulary->candidateCount . ' vocabulary ' . $vocabulary->size();
        $total = $inVocabulary = 0;
        $occurrences = $words = [];
        foreach ($this->tests as $index => $document) {
            $total += count($document->tokens->terms($settings->bigrams));
            $inVocabulary += count($this->testSequences[$index]);
            foreach ($document->tokens->words as $word) {
                $key = '#' . $word;
                if (!isset($vocabulary->index[$key])) {
                    if (!isset($occurrences[$key])) {
                        $occurrences[$key] = 0;
                        $words[] = $word;
                    }
                    $occurrences[$key]++;
                }
            }
        }
        $lines[] = "test_terms total $total in_vocabulary $inVocabulary";
        usort($words, static fn(string $a, string $b): int => ($occurrences['#' . $b] <=> $occurrences['#' . $a]) ?: strcmp($a, $b));
        $parts = ['test_oov'];
        foreach (array_slice($words, 0, $settings->top) as $word) {
            $parts[] = $word . ' ' . $occurrences['#' . $word];
        }
        $lines[] = implode(' ', $parts);
        return $lines;
    }

    private function foldsPart(): array
    {
        $lines = ['folds 5'];
        foreach ($this->folds as $index => $summary) {
            $lines[] = 'fold ' . ($index + 1) . ' train ' . $summary->trainCount . ' validate ' . $summary->validateCount
                . ' candidates ' . $summary->candidateCount . ' vocabulary ' . $summary->vocabularySize;
        }
        return $lines;
    }

    private function selectionPart(): array
    {
        $lines = ['selection'];
        foreach (BASE_MODELS as $model) {
            $run = $this->selectedRuns[$model];
            $evaluation = $run->evaluation;
            $lines[] = $model . ' alpha ' . $this->alphaText($model) . ' correct ' . proportionText($evaluation->correct, $evaluation->total)
                . ' macro_f1 ' . realText($evaluation->macroF1) . ' folds ' . implode(' ', $run->foldCorrect);
        }
        return $lines;
    }

    private function crossValidationPart(string $model): array
    {
        return array_merge(['cross_validation ' . $model . ' alpha ' . $this->alphaText($model)], $this->selectedRuns[$model]->evaluation->lines($this->classes));
    }

    private function testPart(string $model): array
    {
        $predictions = array_map(fn(int $index): Posterior|RocchioPrediction|VotePrediction => $this->predictions[$model][$index], $this->labelled);
        $predicted = array_map(static fn(Posterior|RocchioPrediction|VotePrediction $prediction): int => $prediction->label, $predictions);
        $evaluation = new Evaluation($this->classCount, $this->truths, $predicted);
        $count = count($predictions);
        $lines = ['test ' . $model . ' alpha ' . $this->alphaText($model), "labelled $count correct " . proportionText($evaluation->correct, $count)];
        if ($model !== 'vote') {
            $topTwo = 0;
            foreach ($predictions as $index => $prediction) {
                $topTwo += (int)($this->truths[$index] === $prediction->ranking[0] || $this->truths[$index] === $prediction->ranking[1]);
            }
            $lines[] = 'top2 ' . proportionText($topTwo, $count);
        }
        array_push($lines, ...$evaluation->lines($this->classes));
        return $lines;
    }

    private function probabilityPart(string $kind): array
    {
        $thresholds = $this->settings->thresholds;
        $limits = array_map(static fn(int $threshold): float => $threshold / 100, $thresholds);
        $count = count($this->labelled);
        $binRows = $binCorrect = array_fill(0, count($limits) + 1, 0);
        $binSums = array_fill(0, count($limits) + 1, 0.0);
        $accepted = $acceptedCorrect = array_fill(0, count($limits), 0);
        $loss = $brier = 0.0;
        foreach ($this->labelled as $position => $index) {
            $prediction = $this->predictions[$kind][$index];
            $truth = $this->truths[$position];
            $correct = $this->correct[$kind][$position];
            $gap = $prediction->scores[$truth] - $prediction->scores[$prediction->label];
            $loss += log($prediction->normalizer) - $gap;
            $squares = 0.0;
            foreach ($prediction->probabilities as $label => $probability) {
                $difference = $probability - ($label === $truth ? 1.0 : 0.0);
                $squares += $difference * $difference;
            }
            $brier += $squares;
            $bucket = bucketOf($prediction->score, $limits);
            $binRows[$bucket]++;
            $binSums[$bucket] += $prediction->score;
            $binCorrect[$bucket] += (int)$correct;
            foreach ($limits as $threshold => $limit) {
                if ($prediction->score >= $limit) {
                    $accepted[$threshold]++;
                    $acceptedCorrect[$threshold] += (int)$correct;
                }
            }
        }
        $lines = ['probability ' . $kind . ' alpha ' . $this->alphaText($kind), 'log_loss ' . realText($loss / $count) . ' brier ' . realText($brier / $count)];
        foreach (array_merge([0], $thresholds) as $bucket => $bound) {
            $rows = $binRows[$bucket];
            $line = 'bin ' . hundredthsText($bound) . " rows $rows";
            if ($rows > 0) {
                $line .= ' correct ' . proportionText($binCorrect[$bucket], $rows) . ' mean ' . realText($binSums[$bucket] / $rows);
            }
            $lines[] = $line;
        }
        foreach ($thresholds as $position => $threshold) {
            $covered = proportionText($accepted[$position], $count);
            $precise = $accepted[$position] > 0 ? proportionText($acceptedCorrect[$position], $accepted[$position]) : '-';
            $lines[] = 'threshold ' . hundredthsText($threshold) . " covered $covered correct $precise";
        }
        return $lines;
    }

    private function lengthsPart(): array
    {
        $boundaries = $this->settings->lengths;
        $rows = array_fill(0, count($boundaries) + 1, 0);
        $correct = [];
        foreach (MODELS as $model) {
            $correct[$model] = array_fill(0, count($boundaries) + 1, 0);
        }
        foreach ($this->labelled as $position => $index) {
            $bucket = bucketOf(count($this->testSequences[$index]), $boundaries);
            $rows[$bucket]++;
            foreach (MODELS as $model) {
                $correct[$model][$bucket] += (int)$this->correct[$model][$position];
            }
        }
        $lines = ['lengths'];
        foreach (array_merge([0], $boundaries) as $bucket => $bound) {
            $parts = ["length $bound rows " . $rows[$bucket]];
            if ($rows[$bucket] > 0) {
                foreach (MODELS as $model) {
                    $parts[] = $model . ' ' . proportionText($correct[$model][$bucket], $rows[$bucket]);
                }
            }
            $lines[] = implode(' ', $parts);
        }
        return $lines;
    }

    private function comparisonPart(): array
    {
        $lines = ['comparison'];
        foreach (MODEL_PAIRS as [$first, $second]) {
            $agree = $b = $c = 0;
            foreach ($this->tests as $index => $document) {
                $agree += (int)($this->predictions[$first][$index]->label === $this->predictions[$second][$index]->label);
            }
            foreach ($this->correct[$first] as $position => $one) {
                $other = $this->correct[$second][$position];
                $b += (int)($one && !$other);
                $c += (int)($other && !$one);
            }
            $difference = max(0, abs($b - $c) - 1);
            $statistic = $b + $c > 0 ? fractionText($difference * $difference, $b + $c) : fractionText(0, 1);
            $lines[] = "$first $second agree " . proportionText($agree, count($this->tests)) . " b $b c $c statistic $statistic";
        }
        $errors = array_fill(0, 5, 0);
        foreach ($this->labelled as $position => $index) {
            $wrong = 0;
            foreach (BASE_MODELS as $model) {
                $wrong += (int)!$this->correct[$model][$position];
            }
            $errors[$wrong]++;
        }
        $parts = ['errors'];
        foreach ($errors as $wrong => $count) {
            $parts[] = "$wrong $count";
        }
        $lines[] = implode(' ', $parts);
        return $lines;
    }

    private function bootstrapPart(): array
    {
        $settings = $this->settings;
        $count = count($this->labelled);
        $state = $settings->seed;
        $totals = [];
        foreach (MODELS as $model) {
            $totals[$model] = [];
        }
        for ($repetition = 0; $repetition < $settings->resamples; $repetition++) {
            $chosen = [];
            for ($selection = 0; $selection < $count; $selection++) {
                $state = 48271 * $state % 2147483647;
                $chosen[] = $state % $count;
            }
            foreach (MODELS as $model) {
                $correct = 0;
                foreach ($chosen as $position) {
                    $correct += (int)$this->correct[$model][$position];
                }
                $totals[$model][] = $correct;
            }
        }
        $rank = intdiv($settings->resamples, 40);
        $lines = ['bootstrap resamples ' . $settings->resamples . ' seed ' . $settings->seed];
        foreach (MODELS as $model) {
            $ordered = $totals[$model];
            sort($ordered, SORT_NUMERIC);
            $mean = array_sum($ordered) / ($settings->resamples * $count);
            $lines[] = $model . ' mean ' . realText($mean) . ' low ' . proportionText($ordered[$rank], $count)
                . ' high ' . proportionText($ordered[count($ordered) - 1 - $rank], $count);
        }
        foreach (MODEL_PAIRS as [$first, $second]) {
            $wins = $ties = $losses = 0;
            foreach ($totals[$first] as $index => $one) {
                $other = $totals[$second][$index];
                $wins += (int)($one > $other);
                $ties += (int)($one === $other);
                $losses += (int)($one < $other);
            }
            $lines[] = "pair $first $second wins $wins ties $ties losses $losses";
        }
        return $lines;
    }

    private function hardPart(): array
    {
        $hard = [];
        $counts = array_fill(0, $this->classCount, 0);
        foreach ($this->training as $index => $document) {
            $predicted = array_map(fn(string $model): int => $this->selectedRuns[$model]->predictions[$index], BASE_MODELS);
            if (!in_array($document->label, $predicted, true)) {
                $hard[] = [$document, $predicted];
                $counts[$document->label]++;
            }
        }
        $lines = ['hard_documents ' . count($hard) . ' ' . classCountsText($this->classes, $counts)];
        foreach (array_slice($hard, 0, $this->settings->top) as [$document, $predicted]) {
            $names = array_map(fn(int $label): string => $this->classes[$label], $predicted);
            $lines[] = $document->name . ' true ' . $this->classes[$document->label] . ' predicted ' . implode(' ', $names);
        }
        return $lines;
    }

    private function uncertainPart(): array
    {
        $predictions = $this->predictions['multinomial'];
        $order = range(0, count($this->tests) - 1);
        usort($order, static fn(int $a, int $b): int => (rounded4($predictions[$a]->margin) <=> rounded4($predictions[$b]->margin)) ?: ($a <=> $b));
        $shown = array_slice($order, 0, $this->settings->top);
        $lines = ['uncertain multinomial ' . count($shown)];
        foreach ($shown as $index) {
            $document = $this->tests[$index];
            $prediction = $predictions[$index];
            $truth = $document->label === null ? '?' : $this->classes[$document->label];
            $lines[] = $document->name . ' predicted ' . $this->classes[$prediction->label] . ' runner_up ' . $this->classes[$prediction->runnerUp]
                . ' margin ' . realText($prediction->margin) . ' posterior ' . realText($prediction->score) . " true $truth";
        }
        return $lines;
    }

    private function evidenceLines(array $sequence, int $predicted, int $truth): array
    {
        $alpha = $this->selected['multinomial'];
        $occurrences = $this->final->counts->occurrences;
        $weights = $this->final->models['multinomial']->weights;
        $frequencies = array_count_values($sequence);
        $entries = [];
        foreach (firstOccurrences($sequence) as $term) {
            $entries[] = [100 * $occurrences[$predicted][$term] + $alpha, 100 * $occurrences[$truth][$term] + $alpha, $term];
        }
        $lines = [];
        foreach (array_slice(rankedByRatio($entries), 0, 3) as [$numerator, $denominator, $term]) {
            $lines[] = '  ' . $this->final->vocabulary->terms[$term] . ' count ' . $frequencies[$term] . ' evidence ' . realText($weights[$predicted][$term] - $weights[$truth][$term]);
        }
        return $lines;
    }

    private function misclassifiedPart(): array
    {
        $predictions = $this->predictions['multinomial'];
        $misclassified = array_values(array_filter($this->labelled, fn(int $index): bool => $predictions[$index]->label !== $this->tests[$index]->label));
        $lines = ['misclassified multinomial ' . count($misclassified)];
        foreach ($misclassified as $index) {
            $document = $this->tests[$index];
            $prediction = $predictions[$index];
            $lines[] = $document->name . ' true ' . $this->classes[$document->label] . ' predicted ' . $this->classes[$prediction->label] . ' posterior ' . realText($prediction->score);
            array_push($lines, ...$this->evidenceLines($this->testSequences[$index], $prediction->label, $document->label));
        }
        return $lines;
    }

    private function maximization(array $posteriors, array $sequences): NaiveBayes
    {
        $settings = $this->settings;
        $counts = $this->final->counts;
        $weight = $settings->weight / 100;
        $occurrences = array_map(static fn(array $row): array => array_map(static fn(int $count): float => (float)$count, $row), $counts->occurrences);
        $documents = array_map(static fn(int $count): float => (float)$count, $counts->documents);
        foreach ($posteriors as $index => $posterior) {
            $sequence = $sequences[$index];
            $frequencies = array_count_values($sequence);
            $terms = firstOccurrences($sequence);
            for ($label = 0; $label < $this->classCount; $label++) {
                $share = $weight * $posterior->probabilities[$label];
                $documents[$label] += $share;
                foreach ($terms as $term) {
                    $occurrences[$label][$term] += $share * $frequencies[$term];
                }
            }
        }
        $alpha = $this->selected['multinomial'];
        $size = $this->final->vocabulary->size();
        $weights = [];
        foreach ($occurrences as $row) {
            $total = 0.0;
            foreach ($row as $value) {
                $total += $value;
            }
            $weights[] = array_map(static fn(float $value): float => smoothedLog($value, $total, $alpha, $size), $row);
        }
        $scale = count($this->training) + ($settings->weight * count($this->unlabelled)) / 100;
        $priors = array_map(static fn(float $value): float => log($value / $scale), $documents);
        return new NaiveBayes('multinomial', $priors, array_fill(0, $this->classCount, 0.0), $weights);
    }

    private function semiSupervisedPart(): array
    {
        $settings = $this->settings;
        $sequences = array_map(fn(Document $document): array => $this->final->encode($document), $this->unlabelled);
        $labelledSequences = array_map(fn(int $index): array => $this->testSequences[$index], $this->labelled);
        $model = $this->final->models['multinomial'];
        $previous = null;
        $lines = ['semi_supervised multinomial alpha ' . $this->alphaText('multinomial') . ' weight ' . hundredthsText($settings->weight) . ' unlabelled ' . count($this->unlabelled)];
        for ($iteration = 0; $iteration <= $settings->iterations; $iteration++) {
            $posteriors = array_map(static fn(array $sequence): Posterior => $model->predict($sequence), $sequences);
            $assignments = array_map(static fn(Posterior $posterior): int => $posterior->label, $posteriors);
            $predicted = array_map(static fn(array $sequence): int => $model->predict($sequence)->label, $labelledSequences);
            $evaluation = new Evaluation($this->classCount, $this->truths, $predicted);
            $changed = '-';
            if ($previous !== null) {
                $count = 0;
                foreach ($previous as $index => $old) {
                    $count += (int)($old !== $assignments[$index]);
                }
                $changed = (string)$count;
            }
            $assigned = array_fill(0, $this->classCount, 0);
            foreach ($assignments as $label) {
                $assigned[$label]++;
            }
            $lines[] = "iteration $iteration correct " . proportionText($evaluation->correct, $evaluation->total)
                . ' macro_f1 ' . realText($evaluation->macroF1) . " changed $changed assigned " . classCountsText($this->classes, $assigned);
            if ($iteration < $settings->iterations) {
                $model = $this->maximization($posteriors, $sequences);
            }
            $previous = $assignments;
        }
        return $lines;
    }

    public function metricsParts(): array
    {
        $parts = [$this->dataPart(), $this->foldsPart(), $this->selectionPart()];
        foreach (BASE_MODELS as $model) {
            $parts[] = $this->crossValidationPart($model);
        }
        foreach (MODELS as $model) {
            $parts[] = $this->testPart($model);
        }
        foreach (NB_MODELS as $kind) {
            $parts[] = $this->probabilityPart($kind);
        }
        array_push($parts, $this->lengthsPart(), $this->comparisonPart(), $this->bootstrapPart(), $this->hardPart(),
            $this->uncertainPart(), $this->misclassifiedPart(), $this->semiSupervisedPart());
        return $parts;
    }

    private function characteristicParts(string $kind): array
    {
        $counts = $this->final->counts;
        $terms = $this->final->vocabulary->terms;
        $size = count($terms);
        $alpha = $this->selected[$kind];
        if ($kind === 'multinomial') {
            $table = $counts->occurrences;
            $totals = $counts->totals;
            $overall = $counts->total;
            $outcomes = $size;
        } else {
            $table = $counts->containing;
            $totals = $counts->documents;
            $overall = $counts->documentTotal;
            $outcomes = 2;
        }
        $termTotals = array_fill(0, $size, 0);
        foreach ($table as $row) {
            foreach ($row as $term => $count) {
                $termTotals[$term] += $count;
            }
        }
        $parts = [['model ' . $kind . ' alpha ' . hundredthsText($alpha) . " vocabulary $size top " . $this->settings->top]];
        foreach ($this->classes as $label => $name) {
            $total = $totals[$label];
            $other = $overall - $total;
            $lines = ["class $name total $total other $other"];
            $entries = [];
            foreach ($table[$label] as $term => $count) {
                $entries[] = [100 * $count + $alpha, 100 * ($termTotals[$term] - $count) + $alpha, $term];
            }
            foreach (array_slice(rankedByRatio($entries), 0, $this->settings->top) as $index => [$numerator, $denominator, $term]) {
                $count = $table[$label][$term];
                $otherCount = $termTotals[$term] - $count;
                $logOdds = smoothedLog($count, $total, $alpha, $outcomes) - smoothedLog($otherCount, $other, $alpha, $outcomes);
                $lines[] = ($index + 1) . ' ' . $terms[$term] . " $count $otherCount " . realText($logOdds);
            }
            $parts[] = $lines;
        }
        return $parts;
    }

    public function topFeatureParts(): array
    {
        return array_merge($this->characteristicParts('multinomial'), $this->characteristicParts('bernoulli'));
    }
}

$experiment = new Experiment();
$experiment->run();
if (!is_dir('output')) {
    mkdir('output', 0777, true);
}
writeLines('vocabulary.txt', $experiment->vocabularyLines());
writeLines('cv_results.csv', $experiment->cvLines());
writeLines('predictions.csv', $experiment->predictionLines());
writeLines('learning_curve.csv', $experiment->curveLines());
writeLines('feature_study.csv', $experiment->featureLines());
writeLines('metrics.txt', joinParts($experiment->metricsParts()));
writeLines('top_features.txt', joinParts($experiment->topFeatureParts()));
