<?php
declare(strict_types=1);

function writeText(string $name, array $lines): void { file_put_contents('output/'.$name, implode("\n",$lines).($lines ? "\n" : '')); }
function writePpm(array $image): void { $lines = ['P3',count($image[0]).' '.count($image),'255']; foreach ($image as $row) $lines[] = implode(' ',array_map(fn($color) => implode(' ',$color),$row)); writeText('image.ppm',$lines); }
function writePreview(array $image): void {
    $lines = []; $ramp = '@%#*+=-:,.'; for ($top = 0; $top < count($image); $top += 4) { $text = ''; for ($left = 0; $left < count($image[0]); $left += 2) { $total = 0; for ($y = $top; $y < $top+4; $y++) for ($x = $left; $x < $left+2; $x++) { [$r,$g,$b] = $image[$y][$x]; $total += 299*$r+587*$g+114*$b; } $text .= $ramp[intdiv(intdiv($total,8000)*10,256)]; } $lines[] = $text; } writeText('preview.txt',$lines);
}
