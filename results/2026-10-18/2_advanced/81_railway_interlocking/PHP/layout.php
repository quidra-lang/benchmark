<?php

final class Layout
{
    public array
        $sections = [],
        $points = [],
        $signals = [],
        $buffers = [],
        $boundaries = [],
        $labels = [],
        $ends = [],
        $signalsAt = []
    ;

    public function __construct()
    {
        foreach (file('input/layout.txt', FILE_IGNORE_NEW_LINES) as $line) {
            $f = explode(' ', $line);
            $type = array_shift($f);
            $name = $f[0];
            switch ($type) {
                case 'SECTION':
                    $this->sections[$name] = (object) [
                        'name' => $name,
                        'length' => (int) $f[1],
                        'row' => (int) $f[2],
                        'first' => (int) $f[3],
                        'last' => (int) $f[4],
                        'failed' => false,
                        'occupants' => [],
                        'occupiedSeconds' => 0,
                        'lockedSeconds' => 0,
                        'trains' => [],
                        'routeLock' => null,
                        'overlapLocks' => [],
                    ];
                    break;
                case 'JOINT':
                    $this->ends[$f[0] . ':R'] = ['section', $f[1]];
                    $this->ends[$f[1] . ':L'] = ['section', $f[0]];
                    break;
                case 'POINT':
                    $point = (object) [
                        'name' => $name,
                        'side' => $f[1],
                        'common' => $f[2],
                        'normal' => $f[3],
                        'reverse' => $f[4],
                        'row' => (int) $f[5],
                        'column' => (int) $f[6],
                        'position' => 'N',
                        'moving' => false,
                        'failed' => false,
                        'target' => null,
                        'completion' => null,
                        'throws' => 0,
                        'lockedSeconds' => 0,
                        'movingSeconds' => 0,
                        'locks' => [],
                    ];
                    $this->points[$name] = $point;
                    $this->ends[$point->common . ':' . $point->side] = ['point', $name];
                    $other = $point->side === 'R' ? 'L' : 'R';
                    $this->ends[$point->normal . ':' . $other] =
                        $this->ends[$point->reverse . ':' . $other] = ['point', $name];
                    break;
                case 'SIGNAL':
                    $signal = (object) [
                        'name' => $name,
                        'section' => $f[1],
                        'direction' => $f[2],
                        'row' => (int) $f[3],
                        'column' => (int) $f[4],
                        'aspect' => 'RED',
                        'seconds' => ['RED' => 0, 'YELLOW' => 0, 'GREEN' => 0],
                        'passes' => 0,
                    ];
                    $this->signals[$name] =
                        $this->signalsAt[$signal->section . ':' . $signal->direction] = $signal;
                    break;
                case 'BUFFER':
                case 'BOUNDARY':
                    $item = (object) ['name' => $name, 'section' => $f[1], 'end' => $f[2]];
                    if ($type === 'BUFFER') {
                        $item->row = (int) $f[3];
                        $item->column = (int) $f[4];
                        $this->buffers[$name] = $item;
                    } else
                        $this->boundaries[$name] = $item;
                    $this->ends[$item->section . ':' . $item->end] = [strtolower($type), $name];
                    break;
                case 'LABEL':
                    $this->labels[] = [(int) $f[0], (int) $f[1], $f[2]];
                    break;
            }
        }
    }

    public function beyond(string $section, string $direction): array
    {
        [$kind, $name] = $this->ends[$section . ':' . ($direction === 'UP' ? 'R' : 'L')];
        if ($kind !== 'point')
            return [$kind, $name];
        $point = $this->points[$name];
        $branch = $point->position === 'N' ? $point->normal : $point->reverse;
        if ($point->moving || $section !== $point->common && $section !== $branch)
            return ['impassable', null];
        return ['section', $section === $point->common ? $branch : $point->common];
    }
}
