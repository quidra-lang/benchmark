<?php
declare(strict_types=1);

require_once __DIR__ . '/charset.php';

final class TooManySteps extends RuntimeException {}

final class BacktrackVM
{
    public int $steps = 0;
    private bool $full = false;

    public function __construct(private object $pattern, private string $text) {}

    private function execute(int $start_instruction, int $start_position, array $captures, bool $partial): ?array
    {
        $stack = [[$start_instruction, $start_position, $captures, []]];
        while ($stack) {
            [$p, $q, $current, $visited] = array_pop($stack);
            $failed = false;
            while (!$failed) {
                if (++$this->steps > 200000) {
                    throw new TooManySteps();
                }
                $instruction = $this->pattern->program[$p];
                switch ($instruction['op']) {
                    case 'CHAR': case 'ANY': case 'CLASS':
                        if (!consumes($instruction, $this->text, $q, $this->pattern->flags)) {
                            $failed = true;
                            break;
                        }
                        ++$q;
                        ++$p;
                        $visited = [];
                        break;
                    case 'SPLIT':
                        if (isset($visited[$p])) {
                            $failed = true;
                            break;
                        }
                        $visited[$p] = true;
                        $stack[] = [$instruction['y'], $q, $current, $visited];
                        $p = $instruction['x'];
                        break;
                    case 'JMP':
                        $p = $instruction['x'];
                        break;
                    case 'SAVE':
                        $current[$instruction['group']] = $q;
                        ++$p;
                        break;
                    case 'ASSERT':
                        if (assertion($instruction['assertion'], $this->text, $q, $this->pattern->flags)) {
                            ++$p;
                        } else {
                            $failed = true;
                        }
                        break;
                    case 'BACKREF':
                        $first = $current[2 * $instruction['group']];
                        $last = $current[2 * $instruction['group'] + 1];
                        if ($first === null || $last === null || $first > $last || $q + $last - $first > strlen($this->text)) {
                            $failed = true;
                            break;
                        }
                        $length = $last - $first;
                        for ($i = 0; $i < $length; ++$i) {
                            if (!same(ord($this->text[$q + $i]), ord($this->text[$first + $i]), $this->pattern->flags)) {
                                $failed = true;
                                break;
                            }
                        }
                        if (!$failed) {
                            $q += $length;
                            ++$p;
                            if ($length > 0) {
                                $visited = [];
                            }
                        }
                        break;
                    case 'LOOK':
                        $result = $this->execute($p + 1, $q, $current, true);
                        if ($instruction['kind'] === 'NOT') {
                            if ($result === null) {
                                $p = $instruction['x'];
                            } else {
                                $failed = true;
                            }
                        } elseif ($result === null) {
                            $failed = true;
                        } else {
                            [$current, $position] = $result;
                            if ($instruction['kind'] === 'ATOMIC') {
                                if ($position > $q) {
                                    $visited = [];
                                }
                                $q = $position;
                            }
                            $p = $instruction['x'];
                        }
                        break;
                    case 'MATCH':
                        if ($partial || !$this->full || $q === strlen($this->text)) {
                            return [$current, $q];
                        }
                        $failed = true;
                        break;
                }
            }
        }
        return null;
    }

    public function search(int $start, bool $full): ?array
    {
        $this->full = $full;
        $first = $full ? 0 : $start;
        $last = $full ? 0 : strlen($this->text);
        for ($position = $first; $position <= $last; ++$position) {
            $captures = array_fill(0, 2 * $this->pattern->groups + 2, null);
            $result = $this->execute(0, $position, $captures, false);
            if ($result !== null) {
                return $result[0];
            }
        }
        return null;
    }
}
