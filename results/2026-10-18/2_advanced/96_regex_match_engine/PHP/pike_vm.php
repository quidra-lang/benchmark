<?php
declare(strict_types=1);

require_once __DIR__ . '/charset.php';

final class PikeVM
{
    public int $steps = 0;

    public function __construct(private object $pattern, private string $text) {}

    private function add(array &$list, int $number, array $captures, int $position): void
    {
        $pending = [[$number, $captures]];
        while ($pending) {
            [$p, $current] = array_pop($pending);
            if (isset($list['marks'][$p])) {
                continue;
            }
            $list['marks'][$p] = true;
            ++$this->steps;
            $instruction = $this->pattern->program[$p];
            switch ($instruction['op']) {
                case 'JMP':
                    $pending[] = [$instruction['x'], $current];
                    break;
                case 'SPLIT':
                    $pending[] = [$instruction['y'], $current];
                    $pending[] = [$instruction['x'], $current];
                    break;
                case 'SAVE':
                    $current[$instruction['group']] = $position;
                    $pending[] = [$p + 1, $current];
                    break;
                case 'ASSERT':
                    if (assertion($instruction['assertion'], $this->text, $position, $this->pattern->flags)) {
                        $pending[] = [$p + 1, $current];
                    }
                    break;
                default:
                    $list['threads'][] = [$p, $current];
            }
        }
    }

    public function search(int $start, bool $full): ?array
    {
        $match = null;
        $list = ['threads' => [], 'marks' => []];
        $position = $start;
        while (true) {
            if ($match === null && (!$full || $position === $start)) {
                $this->add($list, 0, array_fill(0, 2 * $this->pattern->groups + 2, null), $position);
            }
            $next = ['threads' => [], 'marks' => []];
            foreach ($list['threads'] as [$p, $captures]) {
                ++$this->steps;
                $instruction = $this->pattern->program[$p];
                if ($instruction['op'] === 'MATCH') {
                    if (!$full || $position === strlen($this->text)) {
                        $match = $captures;
                        break;
                    }
                } elseif (consumes($instruction, $this->text, $position, $this->pattern->flags)) {
                    $this->add($next, $p + 1, $captures, $position + 1);
                }
            }
            if ($position === strlen($this->text) || (!$next['threads'] && ($match !== null || $full))) {
                break;
            }
            $list = $next;
            ++$position;
        }
        return $match;
    }
}
