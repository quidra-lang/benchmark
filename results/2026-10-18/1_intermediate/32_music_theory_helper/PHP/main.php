<?php
declare(strict_types=1);

final class CommandError extends Exception {
    public function __construct(string $message) { parent::__construct('ERROR ' . $message); }
}

function modulo(int $value, int $base): int { return ($value % $base + $base) % $base; }
function floorDivide(int $value, int $base): int { return intdiv($value - modulo($value, $base), $base); }
function frequencyText(int $cents): string { return intdiv($cents, 100) . '.' . str_pad((string)($cents % 100), 2, '0', STR_PAD_LEFT); }
function signedText(int $value, bool $positiveZero = false): string { return ($value > 0 || ($value === 0 && $positiveZero) ? '+' : '') . $value; }

final readonly class Pitch {
    public const LETTERS = 'CDEFGAB';
    public const NATURALS = [0, 2, 4, 5, 7, 9, 11];
    private const ACCIDENTALS = ['bb', 'b', '', '#', 'x'];
    public function __construct(public int $letter, public int $alteration = 0) {}
    public function natural(): int { return self::NATURALS[$this->letter]; }
    public function pitchClass(): int { return modulo($this->natural() + $this->alteration, 12); }
    public function same(self $other): bool { return $this->letter === $other->letter && $this->alteration === $other->alteration; }
    public function __toString(): string { return self::LETTERS[$this->letter] . self::ACCIDENTALS[$this->alteration + 2]; }
    public static function prefix(string $text): ?array {
        if ($text === '' || ($letter = strpos(self::LETTERS, $text[0])) === false) return null;
        $end = 1; $alteration = 0;
        if (str_starts_with(substr($text, 1), 'bb')) { $end = 3; $alteration = -2; }
        elseif (strlen($text) > 1) {
            [$end, $alteration] = match ($text[1]) {
                'b' => [2, -1], '#' => [2, 1], 'x' => [2, 2], default => [1, 0],
            };
        }
        return [new self($letter, $alteration), $end];
    }
    public static function parse(string $text): self {
        $prefix = self::prefix($text);
        if ($prefix === null || $prefix[1] !== strlen($text)) throw new CommandError("BAD PITCH $text");
        return $prefix[0];
    }
    public static function atFifths(int $fifths): self {
        return new self(strpos(self::LETTERS, 'FCGDAEB'[modulo($fifths + 1, 7)]), floorDivide($fifths + 1, 7));
    }
    public function raise(Interval $interval): self {
        $position = $this->letter + $interval->distance();
        $letter = $position % 7;
        $alteration = $this->natural() + $this->alteration + $interval->semitones()
            - self::NATURALS[$letter] - 12 * intdiv($position, 7);
        if ($alteration < -2 || $alteration > 2) throw new CommandError('CANNOT SPELL');
        return new self($letter, $alteration);
    }
}

final readonly class Note {
    private const SHARPS = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    private const FLATS = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
    public function __construct(public Pitch $pitch, public int $octave) {}
    public function midi(): int { return 12 * ($this->octave + 1) + $this->pitch->natural() + $this->pitch->alteration; }
    public function position(): int { return 7 * $this->octave + $this->pitch->letter; }
    public function valid(): bool { return $this->octave >= -1 && $this->octave <= 9 && $this->midi() >= 0 && $this->midi() <= 127; }
    public function __toString(): string { return $this->pitch . $this->octave; }
    public static function parse(string $text): self {
        $prefix = Pitch::prefix($text);
        if ($prefix === null) throw new CommandError("BAD NOTE $text");
        $tail = substr($text, $prefix[1]);
        if (!preg_match('/\A(?:-1|[0-9])\z/', $tail)) throw new CommandError("BAD NOTE $text");
        $note = new self($prefix[0], (int)$tail);
        if (!$note->valid()) throw new CommandError("BAD NOTE $text");
        return $note;
    }
    public static function fromMidi(Pitch $pitch, int $midi): self {
        return new self($pitch, intdiv($midi - $pitch->natural() - $pitch->alteration, 12) - 1);
    }
    public static function spelling(int $midi, bool $flat = false): self {
        $names = $flat ? self::FLATS : self::SHARPS;
        return new self(Pitch::parse($names[modulo($midi, 12)]), floorDivide($midi, 12) - 1);
    }
}

enum IntervalQuality: string {
    case Perfect = 'P'; case Major = 'M'; case Minor = 'm'; case Augmented = 'A';
    case Diminished = 'd'; case DoubleAugmented = 'AA'; case DoubleDiminished = 'dd';
    public function inverse(): self {
        return match ($this) {
            self::Perfect => self::Perfect, self::Major => self::Minor, self::Minor => self::Major,
            self::Augmented => self::Diminished, self::Diminished => self::Augmented,
            self::DoubleAugmented => self::DoubleDiminished, self::DoubleDiminished => self::DoubleAugmented,
        };
    }
}
final readonly class Interval {
    public function __construct(public IntervalQuality $quality, public int $number) {}
    public function distance(): int { return $this->number - 1; }
    public function perfectType(): bool { return in_array($this->distance() % 7, [0, 3, 4], true); }
    public function semitones(): int {
        $difference = match ($this->quality) {
            IntervalQuality::DoubleDiminished => $this->perfectType() ? -2 : -3,
            IntervalQuality::Diminished => $this->perfectType() ? -1 : -2,
            IntervalQuality::Minor => -1, IntervalQuality::Augmented => 1,
            IntervalQuality::DoubleAugmented => 2, default => 0,
        };
        return 12 * intdiv($this->distance(), 7) + Pitch::NATURALS[$this->distance() % 7] + $difference;
    }
    public function simple(): self {
        $number = $this->number;
        while ($number > 8) $number -= 7;
        return new self($this->quality, $number);
    }
    public function consonance(): string {
        $simple = $this->simple();
        if ($simple->quality === IntervalQuality::Perfect && in_array($simple->number, [1, 5, 8], true)) return 'perfect';
        if (in_array($simple->quality, [IntervalQuality::Minor, IntervalQuality::Major], true)
            && in_array($simple->number, [3, 6], true)) return 'imperfect';
        return 'dissonant';
    }
    public function __toString(): string { return $this->quality->value . $this->number; }
    public static function parse(string $text): self {
        if (!preg_match('/\A(P|M|m|A|d|AA|dd)([1-9][0-9]?)\z/', $text, $parts)) throw new CommandError("BAD INTERVAL $text");
        $quality = IntervalQuality::from($parts[1]);
        $result = new self($quality, (int)$parts[2]);
        $invalid = $result->perfectType()
            ? in_array($quality, [IntervalQuality::Major, IntervalQuality::Minor], true)
            : $quality === IntervalQuality::Perfect;
        if ($invalid || ($result->number === 1 && in_array($quality, [IntervalQuality::Diminished, IntervalQuality::DoubleDiminished], true)))
            throw new CommandError("BAD INTERVAL $text");
        return $result;
    }
    public static function between(Note $a, Note $b): Motion {
        $distance = $b->position() - $a->position();
        $semitones = $b->midi() - $a->midi();
        $down = $distance < 0 || ($distance === 0 && $semitones < 0);
        if ($down) { $distance = -$distance; $semitones = -$semitones; }
        $difference = $semitones - (12 * intdiv($distance, 7) + Pitch::NATURALS[$distance % 7]);
        $quality = in_array($distance % 7, [0, 3, 4], true)
            ? match ($difference) {
                -2 => IntervalQuality::DoubleDiminished, -1 => IntervalQuality::Diminished,
                0 => IntervalQuality::Perfect, 1 => IntervalQuality::Augmented, 2 => IntervalQuality::DoubleAugmented, default => null,
            }
            : match ($difference) {
                -3 => IntervalQuality::DoubleDiminished, -2 => IntervalQuality::Diminished, -1 => IntervalQuality::Minor,
                0 => IntervalQuality::Major, 1 => IntervalQuality::Augmented, 2 => IntervalQuality::DoubleAugmented, default => null,
            };
        if ($quality === null) throw new CommandError('UNNAMEABLE INTERVAL');
        return new Motion(new self($quality, $distance + 1), $down, $semitones);
    }
}
final readonly class Motion {
    public function __construct(public Interval $interval, public bool $down, public int $semitones) {}
}
final readonly class Quality {
    public function __construct(public string $name, public array $pattern, public string $suffix, public string $numeral) {}
    public function lower(): bool { return $this->numeral[0] === 'i'; }
    public function roman(int $degree): string {
        $roman = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'][$degree];
        return ($this->lower() ? strtolower($roman) : $roman) . substr($this->numeral, 1);
    }
    public function symbol(Pitch $root): string { return $root . $this->suffix; }
}
enum Mode: string {
    case Major = 'major'; case Minor = 'minor'; case Ionian = 'ionian'; case Dorian = 'dorian';
    case Phrygian = 'phrygian'; case Lydian = 'lydian'; case Mixolydian = 'mixolydian'; case Aeolian = 'aeolian'; case Locrian = 'locrian';
    public function offset(): int {
        return match ($this) {
            self::Major, self::Ionian => 0, self::Minor, self::Aeolian => -3, self::Dorian => -2,
            self::Phrygian => -4, self::Lydian => 1, self::Mixolydian => -1, self::Locrian => -5,
        };
    }
    public function scale(): string { return $this === self::Minor ? 'natural_minor' : $this->value; }
    public static function parse(string $text): self { return self::tryFrom($text) ?? throw new CommandError("BAD MODE $text"); }
}
final readonly class Key {
    public function __construct(public Pitch $tonic, public Mode $mode) {}
    public function fifths(): int { return [0, 2, 4, -1, 1, 3, 5][$this->tonic->letter] + 7 * $this->tonic->alteration + $this->mode->offset(); }
    public function __toString(): string { return $this->tonic . ' ' . $this->mode->value; }
    public static function parse(string $tonic, string $mode): self {
        $pitch = Pitch::parse($tonic);
        $modeValue = Mode::parse($mode);
        $key = new self($pitch, $modeValue);
        if ($key->fifths() < -7 || $key->fifths() > 7) throw new CommandError('THEORETICAL KEY');
        return $key;
    }
    public static function atFifths(int $fifths, Mode $mode): self { return new self(Pitch::atFifths($fifths - $mode->offset()), $mode); }
}
final readonly class Numeral {
    public function __construct(public int $degree, public int $alteration, public Quality $quality) {}
}
final readonly class Chord {
    public function __construct(public Pitch $root, public Quality $quality) {}
}
final readonly class Degree {
    public function __construct(public int $index, public int $alteration) {}
    public function prefix(): string { return str_repeat($this->alteration < 0 ? 'b' : '#', abs($this->alteration)); }
    public function __toString(): string { return $this->prefix() . ($this->index + 1); }
}

final class Calculator {
    private int $tuning = 44000;
    private array $scales = [];
    private array $qualities = [];
    private const LIMITS = [
        'MIDI' => [1, 1], 'NOTE' => [1, 1], 'FREQ' => [1, 1], 'TUNING' => [1, 1], 'PITCH' => [1, 1],
        'INTERVAL' => [2, 2], 'INVERT' => [1, 1], 'TRANSPOSE' => [3, 3], 'SCALE' => [2, 2],
        'CHORD' => [2, 3], 'VOICE' => [2, 3], 'IDENTIFY' => [2, 15], 'MELODY' => [2, 15], 'ENHARMONIC' => [1, 1],
        'KEYSIG' => [2, 2], 'RELATIVE' => [2, 2], 'CIRCLE' => [1, 1], 'DIATONIC' => [2, 2],
        'PROGRESSION' => [3, 15], 'ANALYZE' => [3, 15], 'FINDKEY' => [1, 15], 'DEGREE' => [3, 3],
        'SPELL' => [3, 3], 'KEYDIST' => [4, 4],
    ];
    public function __construct() {
        $scales = [
            'major' => 'P1 M2 M3 P4 P5 M6 M7', 'natural_minor' => 'P1 M2 m3 P4 P5 m6 m7',
            'harmonic_minor' => 'P1 M2 m3 P4 P5 m6 M7', 'melodic_minor' => 'P1 M2 m3 P4 P5 M6 M7',
            'ionian' => 'P1 M2 M3 P4 P5 M6 M7', 'dorian' => 'P1 M2 m3 P4 P5 M6 m7',
            'phrygian' => 'P1 m2 m3 P4 P5 m6 m7', 'lydian' => 'P1 M2 M3 A4 P5 M6 M7',
            'mixolydian' => 'P1 M2 M3 P4 P5 M6 m7', 'aeolian' => 'P1 M2 m3 P4 P5 m6 m7',
            'locrian' => 'P1 m2 m3 P4 d5 m6 m7', 'major_pentatonic' => 'P1 M2 M3 P5 M6',
            'minor_pentatonic' => 'P1 m3 P4 P5 m7', 'blues' => 'P1 m3 P4 A4 P5 m7', 'whole_tone' => 'P1 M2 M3 A4 A5 A6',
        ];
        foreach ($scales as $name => $pattern) $this->scales[$name] = array_map(Interval::parse(...), explode(' ', $pattern));
        $qualities = [
            ['maj', 'P1 M3 P5', '', 'I'], ['min', 'P1 m3 P5', 'm', 'i'], ['dim', 'P1 m3 d5', 'dim', 'io'],
            ['aug', 'P1 M3 A5', 'aug', 'I+'], ['sus2', 'P1 M2 P5', 'sus2', 'Isus2'], ['sus4', 'P1 P4 P5', 'sus4', 'Isus4'],
            ['6', 'P1 M3 P5 M6', '6', 'I6'], ['m6', 'P1 m3 P5 M6', 'm6', 'i6'], ['7', 'P1 M3 P5 m7', '7', 'I7'],
            ['maj7', 'P1 M3 P5 M7', 'maj7', 'Imaj7'], ['m7', 'P1 m3 P5 m7', 'm7', 'i7'],
            ['mMaj7', 'P1 m3 P5 M7', 'mMaj7', 'imaj7'], ['m7b5', 'P1 m3 d5 m7', 'm7b5', 'ih7'],
            ['dim7', 'P1 m3 d5 d7', 'dim7', 'io7'], ['9', 'P1 M3 P5 m7 M9', '9', 'I9'], ['add9', 'P1 M3 P5 M9', 'add9', 'Iadd9'],
        ];
        foreach ($qualities as [$name, $pattern, $suffix, $numeral]) {
            $this->qualities[] = new Quality($name, array_map(Interval::parse(...), explode(' ', $pattern)), $suffix, $numeral);
        }
    }
    private static function number(string $text): int {
        if (!preg_match('/\A(?:0|[1-9][0-9]{0,2})\z/', $text) || (int)$text > 127) throw new CommandError("BAD NUMBER $text");
        return (int)$text;
    }
    private static function frequency(string $text, bool $tuning): int {
        if (!preg_match('/\A([0-9]{1,5})(?:\.([0-9]{1,2}))?\z/', $text, $parts)) throw new CommandError("BAD FREQUENCY $text");
        $fraction = $parts[2] ?? '';
        $value = (int)$parts[1] * 100 + (int)$fraction * (strlen($fraction) === 1 ? 10 : 1);
        if ($tuning ? $value < 40000 || $value > 48000 : $value === 0) throw new CommandError("BAD FREQUENCY $text");
        return $value;
    }
    private function quality(string $text): Quality {
        foreach ($this->qualities as $quality) if ($quality->name === $text) return $quality;
        throw new CommandError("BAD QUALITY $text");
    }
    private function scalePattern(string $text): array { return $this->scales[$text] ?? throw new CommandError("BAD SCALE $text"); }
    private static function inversion(string $text, Quality $quality): int {
        if (!preg_match('/\A[0-9]\z/', $text) || (int)$text >= count($quality->pattern)) throw new CommandError("BAD INVERSION $text");
        return (int)$text;
    }
    private function numeral(string $text): Numeral {
        $start = str_contains('b#', $text[0]) ? 1 : 0;
        $alteration = $start === 0 ? 0 : ($text[0] === 'b' ? -1 : 1);
        $end = $start;
        while ($end < strlen($text) && str_contains('IViv', $text[$end])) $end++;
        $roman = substr($text, $start, $end - $start);
        $degree = array_search(strtoupper($roman), ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'], true);
        if ($degree !== false && ($roman === strtoupper($roman) || $roman === strtolower($roman))) {
            foreach ($this->qualities as $quality) {
                if ($quality->lower() === ($roman === strtolower($roman)) && substr($quality->numeral, 1) === substr($text, $end))
                    return new Numeral($degree, $alteration, $quality);
            }
        }
        throw new CommandError("BAD NUMERAL $text");
    }
    private function symbol(string $text): Chord {
        $prefix = Pitch::prefix($text);
        if ($prefix !== null) {
            foreach ($this->qualities as $quality) {
                if ($quality->suffix === substr($text, $prefix[1])) return new Chord($prefix[0], $quality);
            }
        }
        throw new CommandError("BAD SYMBOL $text");
    }
    private static function build(Pitch $root, array $pattern): array { return array_map($root->raise(...), $pattern); }
    private function scale(Key $key): array { return self::build($key->tonic, $this->scales[$key->mode->scale()]); }
    private function degree(Key $key, Pitch $pitch): Degree {
        $index = modulo($pitch->letter - $key->tonic->letter, 7);
        return new Degree($index, $pitch->alteration - $this->scale($key)[$index]->alteration);
    }
    private static function mask(array $pitches): int {
        $mask = 0;
        foreach ($pitches as $pitch) $mask |= 1 << $pitch->pitchClass();
        return $mask;
    }
    private static function cadence(array $numerals): string {
        if (count($numerals) < 2) return 'none';
        $a = $numerals[count($numerals) - 2]; $b = $numerals[count($numerals) - 1];
        if ($a->alteration === 0 && $b->alteration === 0) {
            if ($a->degree === 4 && $b->degree === 0) return 'authentic';
            if ($a->degree === 3 && $b->degree === 0) return 'plagal';
            if ($a->degree === 4 && $b->degree === 5) return 'deceptive';
        }
        return $b->alteration === 0 && $b->degree === 4 ? 'half' : 'none';
    }
    public function execute(string $line): string {
        $words = explode(' ', $line);
        $command = array_shift($words);
        $limits = self::LIMITS[$command] ?? throw new CommandError("UNKNOWN COMMAND $command");
        $count = count($words);
        if ($count < $limits[0] || $count > $limits[1]) throw new CommandError('ARGUMENT COUNT');
        switch ($command) {
            case 'MIDI':
                $note = Note::parse($words[0]);
                return "MIDI $note " . $note->midi();
            case 'NOTE':
                $number = self::number($words[0]);
                return "NOTE $number " . Note::spelling($number) . ' ' . Note::spelling($number, true);
            case 'FREQ':
                $note = Note::parse($words[0]);
                $cents = (int)floor($this->tuning * 2.0 ** (($note->midi() - 69) / 12.0) + 0.5);
                return "FREQ $note " . frequencyText($cents);
            case 'TUNING':
                $value = self::frequency($words[0], true);
                $this->tuning = $value;
                return 'TUNING ' . frequencyText($value);
            case 'PITCH':
                $value = self::frequency($words[0], false);
                $height = 69.0 + 12.0 * log($value / $this->tuning, 2.0);
                $number = (int)floor($height + 0.5);
                if ($number < 0 || $number > 127) throw new CommandError('OUT OF RANGE');
                $cents = (int)floor(100.0 * ($height - $number) + 0.5);
                return 'PITCH ' . frequencyText($value) . ' ' . Note::spelling($number) . ' ' . signedText($cents, true);
            case 'INTERVAL':
                $a = Note::parse($words[0]);
                $b = Note::parse($words[1]);
                $motion = Interval::between($a, $b);
                return "INTERVAL $a $b $motion->interval " . ($motion->down ? 'down' : 'up')
                    . " semitones=$motion->semitones simple=" . $motion->interval->simple() . ' class=' . $motion->interval->consonance();
            case 'INVERT':
                $original = Interval::parse($words[0]);
                $simple = $original->simple();
                $inverse = new Interval($simple->quality->inverse(), 9 - $simple->number);
                if ($inverse->number === 1 && in_array($inverse->quality, [IntervalQuality::Diminished, IntervalQuality::DoubleDiminished], true))
                    throw new CommandError('CANNOT INVERT');
                return "INVERT $original $simple $inverse";
            case 'TRANSPOSE':
                $note = Note::parse($words[0]);
                $interval = Interval::parse($words[1]);
                $direction = $words[2];
                if ($direction !== 'UP' && $direction !== 'DOWN') throw new CommandError("BAD DIRECTION $direction");
                $sign = $direction === 'UP' ? 1 : -1;
                $position = $note->position() + $sign * $interval->distance();
                $midi = $note->midi() + $sign * $interval->semitones();
                $letter = modulo($position, 7); $octave = floorDivide($position, 7);
                $alteration = $midi - (12 * ($octave + 1) + Pitch::NATURALS[$letter]);
                if ($alteration < -2 || $alteration > 2) throw new CommandError('CANNOT SPELL');
                $result = new Note(new Pitch($letter, $alteration), $octave);
                if (!$result->valid()) throw new CommandError('OUT OF RANGE');
                return "TRANSPOSE $note $interval $direction $result";
            case 'SCALE':
                $root = Pitch::parse($words[0]);
                $pattern = $this->scalePattern($words[1]);
                $pitches = self::build($root, $pattern);
                $steps = [];
                foreach ($pattern as $i => $interval) $steps[] = ($i + 1 === count($pattern) ? 12 : $pattern[$i + 1]->semitones()) - $interval->semitones();
                return "SCALE $root $words[1] " . implode(' ', $pitches) . ' steps=' . implode(',', $steps);
            case 'CHORD': case 'VOICE':
                $input = $command === 'VOICE' ? Note::parse($words[0]) : null;
                $root = $input === null ? Pitch::parse($words[0]) : $input->pitch;
                $quality = $this->quality($words[1]);
                $inversion = $count === 3 ? self::inversion($words[2], $quality) : 0;
                $pitches = self::build($root, $quality->pattern);
                $pitches = array_merge(array_slice($pitches, $inversion), array_slice($pitches, 0, $inversion));
                $symbol = $quality->symbol($root) . ($inversion === 0 ? '' : '/' . $pitches[0]);
                if ($command === 'CHORD') return "CHORD $symbol " . implode(' ', $pitches);
                $notes = []; $midis = []; $previous = $input->midi();
                foreach ($pitches as $i => $pitch) {
                    $midi = $previous;
                    if ($i !== 0 || $inversion !== 0) {
                        $midi += modulo($pitch->pitchClass() - $previous, 12);
                        if ($midi === $previous) $midi += 12;
                    }
                    $note = Note::fromMidi($pitch, $midi);
                    if (!$note->valid()) throw new CommandError('OUT OF RANGE');
                    $notes[] = $note; $midis[] = $midi; $previous = $midi;
                }
                return "VOICE $symbol " . implode(' ', $notes) . ' midi=' . implode(',', $midis);
            case 'IDENTIFY':
                $notes = array_map(Note::parse(...), $words);
                usort($notes, fn(Note $a, Note $b): int => $a->midi() <=> $b->midi());
                $candidates = []; $mask = 0;
                foreach ($notes as $note) {
                    $bit = 1 << $note->pitch->pitchClass();
                    if (($mask & $bit) === 0) $candidates[] = $note;
                    $mask |= $bit;
                }
                $bass = $candidates[0];
                foreach ($candidates as $root) {
                    foreach ($this->qualities as $quality) {
                        $candidate = 0; $inversion = 0;
                        foreach ($quality->pattern as $i => $interval) {
                            $pitchClass = modulo($root->midi() + $interval->semitones(), 12);
                            $candidate |= 1 << $pitchClass;
                            if ($pitchClass === $bass->pitch->pitchClass()) $inversion = $i;
                        }
                        if ($candidate === $mask) {
                            $symbol = $quality->symbol($root->pitch) . ($inversion === 0 ? '' : '/' . $bass->pitch);
                            return "IDENTIFY $symbol root=$root->pitch quality=$quality->name inversion=$inversion";
                        }
                    }
                }
                return 'IDENTIFY UNKNOWN';
            case 'MELODY':
                $notes = array_map(Note::parse(...), $words);
                $low = $high = $notes[0];
                foreach ($notes as $note) {
                    if ($note->midi() < $low->midi()) $low = $note;
                    if ($note->midi() > $high->midi()) $high = $note;
                }
                $range = Interval::between($low, $high)->interval;
                $steps = []; $leaps = 0;
                for ($i = 1; $i < $count; $i++) {
                    $motion = Interval::between($notes[$i - 1], $notes[$i]);
                    $steps[] = ($motion->down ? '-' : '+') . $motion->interval;
                    if (abs($notes[$i]->midi() - $notes[$i - 1]->midi()) >= 3) $leaps++;
                }
                return "MELODY n=$count low=$low high=$high range=$range leaps=$leaps steps=" . implode(',', $steps);
            case 'ENHARMONIC':
                $input = Note::parse($words[0]);
                $notes = [];
                for ($letter = 0; $letter < 7; $letter++) {
                    for ($alteration = -2; $alteration <= 2; $alteration++) {
                        $pitch = new Pitch($letter, $alteration);
                        if ($pitch->pitchClass() !== $input->pitch->pitchClass()) continue;
                        $note = Note::fromMidi($pitch, $input->midi());
                        if ($note->valid()) $notes[] = $note;
                    }
                }
                usort($notes, fn(Note $a, Note $b): int => $a->position() <=> $b->position());
                return "ENHARMONIC $input " . implode(' ', $notes);
            case 'KEYSIG':
                $key = Key::parse($words[0], $words[1]);
                $fifths = $key->fifths();
                if ($fifths === 0) return "KEYSIG $key none";
                $names = $fifths > 0 ? ['F#', 'C#', 'G#', 'D#', 'A#', 'E#', 'B#'] : ['Bb', 'Eb', 'Ab', 'Db', 'Gb', 'Cb', 'Fb'];
                return "KEYSIG $key " . ($fifths > 0 ? 'sharps=' : 'flats=') . abs($fifths) . ' ' . implode(' ', array_slice($names, 0, abs($fifths)));
            case 'RELATIVE':
                $key = Key::parse($words[0], $words[1]);
                return "RELATIVE $key major=" . Key::atFifths($key->fifths(), Mode::Major)->tonic . ' minor=' . Key::atFifths($key->fifths(), Mode::Minor)->tonic;
            case 'CIRCLE':
                $mode = Mode::parse($words[0]);
                $tonics = [];
                for ($fifths = -7; $fifths <= 7; $fifths++) $tonics[] = Key::atFifths($fifths, $mode)->tonic;
                return "CIRCLE $words[0] " . implode(' ', $tonics);
            case 'DIATONIC':
                $key = Key::parse($words[0], $words[1]);
                $scale = $this->scale($key);
                $lines = ["DIATONIC $key"];
                foreach ([false, true] as $seventhChord) {
                    $items = [];
                    for ($i = 0; $i < 7; $i++) {
                        $third = modulo($scale[($i + 2) % 7]->pitchClass() - $scale[$i]->pitchClass(), 12);
                        $fifth = modulo($scale[($i + 4) % 7]->pitchClass() - $scale[$i]->pitchClass(), 12);
                        $seventh = modulo($scale[($i + 6) % 7]->pitchClass() - $scale[$i]->pitchClass(), 12);
                        $name = !$seventhChord ? ($third === 4 ? 'maj' : ($fifth === 7 ? 'min' : 'dim'))
                            : ($third === 4 ? ($seventh === 11 ? 'maj7' : '7') : ($fifth === 7 ? 'm7' : 'm7b5'));
                        $quality = $this->quality($name);
                        $items[] = $quality->roman($i) . '=' . $quality->symbol($scale[$i]);
                    }
                    $lines[] = ($seventhChord ? 'SEVENTHS ' : 'TRIADS ') . implode(' ', $items);
                }
                return implode("\n", $lines);
            case 'PROGRESSION':
                $key = Key::parse($words[0], $words[1]);
                $numerals = [];
                foreach (array_slice($words, 2) as $word) $numerals[] = $this->numeral($word);
                $scale = $this->scale($key);
                $lines = ["PROGRESSION $key " . count($numerals)];
                foreach ($numerals as $i => $numeral) {
                    $degree = $scale[$numeral->degree];
                    $root = new Pitch($degree->letter, $degree->alteration + $numeral->alteration);
                    $pitches = self::build($root, $numeral->quality->pattern);
                    $lines[] = $words[$i + 2] . ' ' . $numeral->quality->symbol($root) . ' ' . implode(' ', $pitches);
                }
                $lines[] = 'CADENCE ' . self::cadence($numerals);
                return implode("\n", $lines);
            case 'ANALYZE':
                $key = Key::parse($words[0], $words[1]);
                $chords = [];
                foreach (array_slice($words, 2) as $word) $chords[] = $this->symbol($word);
                $results = [];
                foreach ($chords as $chord) {
                    $degree = $this->degree($key, $chord->root);
                    $results[] = $degree->prefix() . $chord->quality->roman($degree->index);
                }
                return "ANALYZE $key " . implode(' ', $results);
            case 'FINDKEY':
                $pitches = array_map(Pitch::parse(...), $words);
                $keys = [];
                for ($fifths = -7; $fifths <= 7; $fifths++) {
                    foreach ([Mode::Major, Mode::Minor] as $mode) {
                        $key = Key::atFifths($fifths, $mode);
                        $scale = $this->scale($key); $matches = true;
                        foreach ($pitches as $pitch) {
                            $found = false;
                            foreach ($scale as $candidate) if ($candidate->same($pitch)) { $found = true; break; }
                            if (!$found) { $matches = false; break; }
                        }
                        if ($matches) $keys[] = $key;
                    }
                }
                return 'FINDKEY ' . count($keys) . ($keys === [] ? '' : ' ' . implode(', ', $keys));
            case 'DEGREE':
                $key = Key::parse($words[0], $words[1]);
                $pitch = Pitch::parse($words[2]);
                return "DEGREE $key $pitch " . $this->degree($key, $pitch);
            case 'SPELL':
                $midi = self::number($words[0]);
                $key = Key::parse($words[1], $words[2]);
                $pitch = Note::spelling($midi, $key->fifths() < 0)->pitch;
                foreach ($this->scale($key) as $candidate) if ($candidate->pitchClass() === $midi % 12) { $pitch = $candidate; break; }
                $note = Note::fromMidi($pitch, $midi);
                if (!$note->valid()) throw new CommandError('OUT OF RANGE');
                return "SPELL $midi $key $note " . $this->degree($key, $pitch);
            case 'KEYDIST':
                $a = Key::parse($words[0], $words[1]);
                $b = Key::parse($words[2], $words[3]);
                $distance = modulo($b->fifths() - $a->fifths(), 12);
                if ($distance > 6) $distance -= 12;
                $first = self::mask($this->scale($a)); $second = self::mask($this->scale($b));
                $sameTonic = $a->tonic->pitchClass() === $b->tonic->pitchClass();
                $relation = $first === $second ? ($sameTonic ? 'same' : 'relative')
                    : ($sameTonic ? 'parallel' : (abs($distance) === 1 ? 'close' : 'distant'));
                $common = 0;
                for ($i = 0; $i < 12; $i++) if (($first & $second & (1 << $i)) !== 0) $common++;
                return "KEYDIST $a $b fifths=" . signedText($distance) . " common=$common relation=$relation";
        }
        throw new LogicException('Unreachable command');
    }
}

$calculator = new Calculator();
$count = (int)rtrim(fgets(STDIN), "\r\n");
for ($i = 0; $i < $count; $i++) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try { $output = $calculator->execute($line); }
    catch (CommandError $error) { $output = $error->getMessage(); }
    echo $output, "\n";
}
