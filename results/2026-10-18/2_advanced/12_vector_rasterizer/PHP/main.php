<?php
declare(strict_types=1);
require_once __DIR__.'/canvas.php';
require_once __DIR__.'/primitives.php';
require_once __DIR__.'/clipping.php';
require_once __DIR__.'/fill.php';
require_once __DIR__.'/ppm_writer.php';

const PEN_COMMANDS = ['LINE','RECT','CIRCLE','ELLIPSE','POLYLINE','POLYGON','PATH'];
const BRUSH_COMMANDS = ['FILLRECT','FILLCIRCLE','FILLELLIPSE','FILLPOLYGON','FILLPATH','FLOOD','TEXT'];
const STATE_COMMANDS = ['TRANSLATE','SCALE','ROTATE','SAVE','RESTORE','CLIP','NOCLIP','USE'];
const ERROR_NAMES = ['unknown_command','bad_arguments','unknown_style','unknown_symbol','unknown_glyph','bad_value','stack_empty'];
const PATH_ARITY = ['M'=>2,'m'=>2,'L'=>2,'l'=>2,'H'=>1,'h'=>1,'V'=>1,'v'=>1,'Q'=>4,'q'=>4,'C'=>6,'c'=>6,'Z'=>0,'z'=>0];

final class Pen { public function __construct(public int $width, public string $color, public int $on, public int $off) {} }
final class Brush { public function __construct(public array $colors, public ?string $axis, public string $rule) {} }
final class Styles { public array $colors = [], $pens = [], $brushes = []; }
final class Font { public array $glyphs = []; public function __construct(public int $width, public int $height) {} }
final class Command { public function __construct(public int $line, public string $keyword, public array $arguments) {} }
final class Repetition { public function __construct(public int $count, public int $dx, public int $dy, public array $body) {} }
final class SceneBlock { public function __construct(public string $name, public array $body, public int $endLine, public int $opacity = 255, public string $mode = 'normal') {} }
final class Scene { public int $width = 0, $height = 0; public string $background = ''; public array $layers = [], $symbols = []; }
final class Subpath { public bool $closed = false; public function __construct(public array $points) {} }
final class Execution {
    public string $kind = '', $error = ''; public int $pixels = 0; public ?array $box = null;
    public function __construct(public int $sequence, public int $layer, public Command $command) {}
}

function readLines(string $name): array { $text = file_get_contents('input/'.$name); return $text === '' ? [] : explode("\n",substr($text,0,-1)); }
function isInteger(string $word): bool { return preg_match('/^-?[0-9]+$/D',$word) === 1; }
function allIntegers(array $words): bool { foreach ($words as $word) if (!isInteger($word)) return false; return true; }
function integers(array $words): array { return array_map(intval(...),$words); }
function intersectRect(array $a, array $b): array { return [max($a[0],$b[0]),max($a[1],$b[1]),min($a[2],$b[2]),min($a[3],$b[3])]; }
function emptyRect(array $r): bool { return $r[0] > $r[2] || $r[1] > $r[3]; }
function containsPoint(array $r, array $p): bool { return $r[0] <= $p[0] && $p[0] <= $r[2] && $r[1] <= $p[1] && $p[1] <= $r[3]; }
function rectPixels(array $r): array { $pixels = []; for ($y=$r[1];$y<=$r[3];$y++) for ($x=$r[0];$x<=$r[2];$x++) addPoint($pixels,$x,$y); return $pixels; }
function boundingBox(array $pixels): ?array { if (!$pixels) return null; $xs = array_column($pixels,0); $ys = array_column($pixels,1); return [min($xs),min($ys),max($xs),max($ys)]; }
function boxText(?array $box): string { return $box === null ? 'none' : implode(' ',$box); }
function segments(array $points, bool $closed): array { $result = []; for ($i=1;$i<count($points);$i++) $result[] = [$points[$i-1],$points[$i]]; if ($closed) $result[] = [$points[count($points)-1],$points[0]]; return $result; }

function readStyles(array $lines): Styles {
    $styles = new Styles(); foreach ($lines as $line) { if ($line === '' || $line[0] === '#') continue; $words = explode(' ',$line); $kind = $words[0]; $name = $words[1]; $v = array_slice($words,2);
        if ($kind === 'color') $styles->colors[$name] = integers($v);
        elseif ($kind === 'pen') $styles->pens[$name] = new Pen((int)$v[0],$v[1],(int)$v[2],(int)$v[3]);
        elseif ($kind === 'brush') $styles->brushes[$name] = new Brush([$v[0]],null,$v[1]);
        else $styles->brushes[$name] = new Brush([$v[0],$v[1]],$v[2],$v[3]);
    } return $styles;
}
function readFont(array $lines): Font {
    $header = explode(' ',$lines[0]); $font = new Font((int)$header[1],(int)$header[2]);
    for ($i=1;$i<count($lines);$i+=1+$font->height) { $character = explode(' ',$lines[$i])[1]; $dots = []; for ($r=0;$r<$font->height;$r++) for ($c=0;$c<$font->width;$c++) if ($lines[$i+1+$r][$c] === '#') $dots[] = [$c,$r]; $font->glyphs[$character] = $dots; } return $font;
}
function readBody(array $instructions, int &$index, string $end): array {
    $body = []; while ($index<count($instructions)) { [$line,$words] = $instructions[$index++]; $keyword = $words[0]; if ($keyword === $end) return [$body,$line]; if ($keyword === 'REPEAT') { [$nested] = readBody($instructions,$index,'ENDREPEAT'); $body[] = new Repetition((int)$words[1],(int)$words[2],(int)$words[3],$nested); } else $body[] = new Command($line,$keyword,array_slice($words,1)); } return [$body,0];
}
function readScene(array $lines): Scene {
    $instructions = []; foreach ($lines as $i=>$line) { $line = ltrim($line,' '); if ($line === '' || $line[0] === '#') continue; $instructions[] = [$i+1,preg_split('/ +/',$line)]; }
    $scene = new Scene(); $index = 0; while ($index<count($instructions)) { [$line,$words] = $instructions[$index++]; if ($words[0] === 'CANVAS') { $scene->width = (int)$words[1]; $scene->height = (int)$words[2]; $scene->background = $words[3]; continue; } [$body,$end] = readBody($instructions,$index,'END'); $block = new SceneBlock($words[1],$body,$end); if ($words[0] === 'LAYER') { $block->opacity = (int)$words[2]; $block->mode = $words[3]; $scene->layers[] = $block; } else $scene->symbols[$block->name] = $block; } return $scene;
}
function parsePath(array $words): ?array {
    $commands = []; $index = 0; while ($index<count($words)) { $letter = $words[$index]; if (!array_key_exists($letter,PATH_ARITY)) return null; $arity = PATH_ARITY[$letter]; $values = array_slice($words,$index+1,$arity); if (count($values)!==$arity || !allIntegers($values)) return null; if ((!$commands || in_array($commands[count($commands)-1][0],['Z','z'],true)) && !in_array($letter,['M','m'],true)) return null; $commands[] = [$letter,integers($values)]; $index += 1+$arity; } return $commands ?: null;
}
function validForm(string $keyword, array $a): bool {
    $fixed = ['LINE'=>[5,1],'RECT'=>[5,1],'FILLRECT'=>[5,1],'CIRCLE'=>[4,1],'FILLCIRCLE'=>[4,1],'ELLIPSE'=>[5,1],'FILLELLIPSE'=>[5,1],'FLOOD'=>[3,1],'ERASE'=>[4,0],'TRANSLATE'=>[2,0],'SCALE'=>[2,0],'ROTATE'=>[1,0],'SAVE'=>[0,0],'RESTORE'=>[0,0],'NOCLIP'=>[0,0],'CLIP'=>[4,0],'USE'=>[3,1]];
    if (isset($fixed[$keyword])) { [$count,$first] = $fixed[$keyword]; return count($a)===$count && allIntegers(array_slice($a,$first)); }
    if ($keyword === 'TEXT') return count($a)===5 && allIntegers(array_slice($a,1,2));
    if (in_array($keyword,['POLYLINE','POLYGON','FILLPOLYGON'],true)) return count($a)>=2 && allIntegers(array_slice($a,1)) && count($a)===2+2*(int)$a[1];
    return count($a)>=2 && isInteger($a[1]) && parsePath(array_slice($a,2))!==null;
}

final class DrawingState {
    public array $matrix = [1,0,0,1,0,0], $stack = [], $clip;
    public function __construct(public array $screen) { $this->clip = $screen; }
    public function transform(int $x, int $y): array { [$a,$b,$c,$d,$e,$f] = $this->matrix; return [$a*$x+$b*$y+$e,$c*$x+$d*$y+$f]; }
    public function deviceRect(int $x0, int $y0, int $x1, int $y1): array { [$a,$b] = $this->transform($x0,$y0); [$c,$d] = $this->transform($x1,$y1); return [min($a,$c),min($b,$d),max($a,$c),max($b,$d)]; }
    public function radii(int $rx, int $ry): array { [$a,$b,$c,$d] = $this->matrix; return [abs($a)*$rx+abs($b)*$ry,abs($c)*$rx+abs($d)*$ry]; }
    public function translate(int $dx, int $dy): void { [$a,$b,$c,$d,$e,$f] = $this->matrix; $this->matrix = [$a,$b,$c,$d,$e+$a*$dx+$b*$dy,$f+$c*$dx+$d*$dy]; }
    public function scale(int $sx, int $sy): void { [$a,$b,$c,$d,$e,$f] = $this->matrix; $this->matrix = [$a*$sx,$b*$sy,$c*$sx,$d*$sy,$e,$f]; }
    public function rotate(int $k): void { $q = ($k%4+4)%4; for ($i=0;$i<$q;$i++) { [$a,$b,$c,$d,$e,$f] = $this->matrix; $this->matrix = [$b,-$a,$d,-$c,$e,$f]; } }
}

final class Renderer {
    public array $layers = [], $executions = []; public DrawingState $state; public Layer $layer; public array $screen;
    public function __construct(public Scene $scene, public Styles $styles, public Font $font) { $this->screen = [0,0,$scene->width-1,$scene->height-1]; }
    public function run(): void { foreach ($this->scene->layers as $block) { $this->layer = new Layer($this->scene->width,$this->scene->height,$block->opacity,$block->mode); $this->layers[] = $this->layer; $this->state = new DrawingState($this->screen); $this->executeBody($block->body); } }
    private function executeBody(array $body): void {
        foreach ($body as $item) { if ($item instanceof Repetition) { $saved = clone $this->state; for ($k=0;$k<$item->count;$k++) { $this->state = clone $saved; $this->state->translate($k*$item->dx,$k*$item->dy); $this->executeBody($item->body); } $this->state = clone $saved; } else $this->executeCommand($item); }
    }
    private function executeCommand(Command $command): void {
        $e = new Execution(count($this->executions)+1,count($this->layers),$command); $this->executions[] = $e; $error = $this->check($command);
        if ($error !== null) { $e->kind = 'error'; $e->error = $error; return; }
        if (in_array($command->keyword,STATE_COMMANDS,true)) { $e->kind = 'state'; $this->applyState($command); return; }
        $pixels = $this->draw($command); $e->kind = 'drawing'; $e->pixels = count($pixels); $e->box = boundingBox($pixels);
    }
    private function check(Command $command): ?string {
        $k = $command->keyword; $a = $command->arguments;
        if (!in_array($k,[...PEN_COMMANDS,...BRUSH_COMMANDS,'ERASE',...STATE_COMMANDS],true)) return 'unknown_command';
        if (!validForm($k,$a)) return 'bad_arguments';
        if (in_array($k,PEN_COMMANDS,true) && !isset($this->styles->pens[$a[0]]) || in_array($k,BRUSH_COMMANDS,true) && !isset($this->styles->brushes[$a[0]])) return 'unknown_style';
        if ($k === 'USE' && (!isset($this->scene->symbols[$a[0]]) || $this->scene->symbols[$a[0]]->endLine >= $command->line)) return 'unknown_symbol';
        if ($k === 'TEXT') foreach (str_split($a[4]) as $character) if ($character !== '_' && !isset($this->font->glyphs[$character])) return 'unknown_glyph';
        if ($k === 'RESTORE' && !$this->state->stack) return 'stack_empty';
        $valid = match ($k) {
            'CIRCLE','FILLCIRCLE' => (int)$a[3]>=1,
            'ELLIPSE','FILLELLIPSE' => (int)$a[3]>=1 && (int)$a[4]>=1,
            'POLYLINE' => (int)$a[1]>=2,
            'POLYGON','FILLPOLYGON' => (int)$a[1]>=3,
            'PATH','FILLPATH' => (int)$a[1]>=1 && (int)$a[1]<=32,
            'FLOOD' => containsPoint($this->state->clip,$this->state->transform((int)$a[1],(int)$a[2])),
            'TEXT' => in_array($a[3],['left','center','right'],true),
            'SCALE' => (int)$a[0]!==0 && (int)$a[1]!==0,
            'CLIP' => !emptyRect(intersectRect($this->state->deviceRect(...integers($a)),$this->state->clip)),
            default => true,
        }; return $valid ? null : 'bad_value';
    }
    private function applyState(Command $command): void {
        $a = $command->arguments; $s = $this->state;
        switch ($command->keyword) {
            case 'TRANSLATE': $s->translate((int)$a[0],(int)$a[1]); break;
            case 'SCALE': $s->scale((int)$a[0],(int)$a[1]); break;
            case 'ROTATE': $s->rotate((int)$a[0]); break;
            case 'SAVE': $s->stack[] = [$s->matrix,$s->clip]; break;
            case 'RESTORE': [$s->matrix,$s->clip] = array_pop($s->stack); break;
            case 'CLIP': $s->clip = intersectRect($s->deviceRect(...integers($a)),$s->clip); break;
            case 'NOCLIP': $s->clip = $this->screen; break;
            case 'USE': $saved = clone $s; $s->translate((int)$a[1],(int)$a[2]); $this->executeBody($this->scene->symbols[$a[0]]->body); $this->state = $saved; break;
        }
    }
    private function draw(Command $command): array {
        $k = $command->keyword; $a = $command->arguments;
        if ($k === 'ERASE') { $pixels = rectPixels(intersectRect($this->state->deviceRect(...integers($a)),$this->state->clip)); $erased = []; foreach ($pixels as [$x,$y]) if ($this->layer->erase($x,$y)) addPoint($erased,$x,$y); return $erased; }
        if (in_array($k,PEN_COMMANDS,true)) { $pen = $this->styles->pens[$a[0]]; $pixels = $this->penCoverage($k,$pen,array_slice($a,1)); foreach ($pixels as [$x,$y]) $this->layer->paint($x,$y,$this->styles->colors[$pen->color],$command->line); return $pixels; }
        $brush = $this->styles->brushes[$a[0]]; $pixels = $this->brushCoverage($k,$brush,array_slice($a,1)); $first = $this->styles->colors[$brush->colors[0]]; $box = boundingBox($pixels);
        foreach ($pixels as [$x,$y]) { $color = $first; if ($brush->axis !== null) { $second = $this->styles->colors[$brush->colors[1]]; $offset = $brush->axis === 'x' ? $x-$box[0] : $y-$box[1]; $length = $brush->axis === 'x' ? $box[2]-$box[0] : $box[3]-$box[1]; if ($length>0) for ($i=0;$i<4;$i++) $color[$i] += roundRatio(($second[$i]-$first[$i])*$offset,$length); } $this->layer->paint($x,$y,$color,$command->line); } return $pixels;
    }
    private function vertices(array $a): array { $v = integers(array_slice($a,1)); $points = []; for ($i=0;$i<count($v);$i+=2) $points[] = $this->state->transform($v[$i],$v[$i+1]); return $points; }
    private function shape(string $keyword, array $v): array {
        $center = $this->state->transform($v[0],$v[1]); if (in_array($keyword,['CIRCLE','FILLCIRCLE'],true)) { [$rx,$ry] = $this->state->radii($v[2],$v[2]); if ($rx===$ry) return [$center,circlePoints($rx)]; } else [$rx,$ry] = $this->state->radii($v[2],$v[3]); return [$center,ellipsePoints($rx,$ry)];
    }
    private function penCoverage(string $keyword, Pen $pen, array $a): array {
        if (in_array($keyword,['CIRCLE','ELLIPSE'],true)) { [[$cx,$cy],$points] = $this->shape($keyword,integers($a)); return $this->expand(array_map(fn($p) => [$cx+$p[0],$cy+$p[1]],array_values($points)),$pen->width); }
        if ($keyword === 'LINE') { $v = integers($a); $segments = [[$this->state->transform($v[0],$v[1]),$this->state->transform($v[2],$v[3])]]; }
        elseif ($keyword === 'RECT') { [$x0,$y0,$x1,$y1] = $this->state->deviceRect(...integers($a)); $segments = segments([[$x0,$y0],[$x1,$y0],[$x1,$y1],[$x0,$y1]],true); }
        elseif (in_array($keyword,['POLYLINE','POLYGON'],true)) $segments = segments($this->vertices($a),$keyword==='POLYGON');
        else { $segments = []; foreach ($this->buildSubpaths(parsePath(array_slice($a,1)),(int)$a[0]) as $path) array_push($segments,...segments($path->points,$path->closed)); }
        $points = []; foreach ($segments as [$start,$end]) { $clipped = clipSegment($start,$end,$this->state->clip); if ($clipped !== null) array_push($points,...bresenham($clipped[0],$clipped[1])); }
        if ($pen->off>0) $points = array_values(array_filter($points,fn($i) => $i%($pen->on+$pen->off)<$pen->on,ARRAY_FILTER_USE_KEY)); return $this->expand($points,$pen->width);
    }
    private function expand(array $points, int $width): array { $pixels = []; foreach ($points as [$x,$y]) foreach (expandSquare($x,$y,$width) as $point) if (containsPoint($this->state->clip,$point)) addPoint($pixels,$point[0],$point[1]); return $pixels; }
    private function brushCoverage(string $keyword, Brush $brush, array $a): array {
        $clip = $this->state->clip;
        if ($keyword === 'FILLRECT') return rectPixels(intersectRect($this->state->deviceRect(...integers($a)),$clip));
        if (in_array($keyword,['FILLCIRCLE','FILLELLIPSE'],true)) { [$center,$points] = $this->shape($keyword,integers($a)); return fillShape($center,$points,$clip); }
        if ($keyword === 'FILLPOLYGON') return fillPolygons([clipPolygon($this->vertices($a),$clip)],$brush->rule,$clip);
        if ($keyword === 'FILLPATH') { $paths = $this->buildSubpaths(parsePath(array_slice($a,1)),(int)$a[0]); return fillPolygons(array_map(fn($p) => clipPolygon($p->points,$clip),$paths),$brush->rule,$clip); }
        if ($keyword === 'FLOOD') return floodFill($this->layer,$this->state->transform((int)$a[0],(int)$a[1]),$clip);
        return $this->textCoverage((int)$a[0],(int)$a[1],$a[2],$a[3]);
    }
    private function textCoverage(int $x, int $y, string $alignment, string $text): array {
        $advance = $this->font->width+1; $extent = strlen($text)*$advance-1; $left = match ($alignment) { 'left'=>$x,'center'=>$x-intdiv($extent,2),default=>$x-$extent+1 }; $pixels = [];
        foreach (str_split($text) as $i=>$character) { if ($character === '_') continue; $origin = $left+$i*$advance; foreach ($this->font->glyphs[$character] as [$column,$row]) { [$x0,$y0,$x1,$y1] = $this->state->deviceRect($origin+$column,$y+$row,$origin+$column+1,$y+$row+1); $pixels += rectPixels(intersectRect([$x0,$y0,$x1-1,$y1-1],$this->state->clip)); } } return $pixels;
    }
    private function buildSubpaths(array $commands, int $segments): array {
        $paths = []; $current = $start = [0,0];
        foreach ($commands as [$letter,$v]) { $kind = strtoupper($letter); if ($kind === 'Z') { $paths[count($paths)-1]->closed = true; $current = $start; continue; } [$ox,$oy] = $letter === strtolower($letter) ? $current : [0,0];
            if ($kind === 'H') $points = [[$v[0]+$ox,$current[1]]]; elseif ($kind === 'V') $points = [[$current[0],$v[0]+$oy]]; else { $points = []; for ($i=0;$i<count($v);$i+=2) $points[] = [$v[$i]+$ox,$v[$i+1]+$oy]; }
            $device = array_map(fn($p) => $this->state->transform($p[0],$p[1]),$points);
            if ($kind === 'M') { $paths[] = new Subpath([$device[0]]); $start = $points[0]; }
            elseif (in_array($kind,['L','H','V'],true)) $paths[count($paths)-1]->points[] = $device[0];
            else { $path = $paths[count($paths)-1]; $controls = array_merge([$path->points[count($path->points)-1]],$device); array_push($path->points,...array_slice(bezierPoints($controls,$segments),1)); }
            $current = $points[count($points)-1];
        } return $paths;
    }
}

function tallyColor(array &$counts, array $color): void { $key = implode(' ',$color); if (!isset($counts[$key])) $counts[$key] = ['color'=>$color,'count'=>0]; $counts[$key]['count']++; }
function rankedColors(array $counts): array { $values = array_values($counts); usort($values,fn($a,$b) => ($b['count'] <=> $a['count']) ?: ($a['color'] <=> $b['color'])); return $values; }
function commandLines(array $executions): array {
    $lines = []; foreach ($executions as $e) { $head = "cmd $e->sequence line {$e->command->line} {$e->command->keyword}"; $lines[] = match ($e->kind) { 'error'=>"$head error $e->error",'drawing'=>"$head pixels $e->pixels box ".boxText($e->box),default=>"$head ok" }; } return $lines;
}
function visibleCounts(array $layers, int $width, int $height): array {
    $counts = array_fill(0,count($layers),0); for ($y=0;$y<$height;$y++) for ($x=0;$x<$width;$x++) { $covered = false; for ($i=count($layers)-1;$i>=0;$i--) { $alpha = $layers[$i]->alphaAt($x,$y); if ($alpha>0 && !$covered) $counts[$i]++; if ($alpha===255) $covered = true; } } return $counts;
}
function layerLines(Scene $scene, array $layers, array $executions): array {
    $visible = visibleCounts($layers,$scene->width,$scene->height); $lines = ['layers '.count($layers)];
    foreach ($layers as $i=>$layer) { $block = $scene->layers[$i]; $number = $i+1; $own = array_filter($executions,fn($e) => $e->layer===$number); $errors = count(array_filter($own,fn($e) => $e->kind==='error')); $painted = []; $counts = [];
        for ($y=0;$y<$layer->height;$y++) for ($x=0;$x<$layer->width;$x++) { $color = $layer->colors[$y][$x]; if ($color !== null) { addPoint($painted,$x,$y); tallyColor($counts,$color); } }
        $lines[] = "layer $number $block->name opacity $block->opacity mode $block->mode commands ".count($own)." errors $errors pixels ".count($painted).' box '.boxText(boundingBox($painted))." visible {$visible[$i]} colors ".count($counts);
        foreach (array_slice(rankedColors($counts),0,5) as $entry) $lines[] = 'color '.implode(' ',$entry['color']).' pixels '.$entry['count'];
    } return $lines;
}
function symbolUses(Scene $scene, array $executions): array { $uses = array_fill_keys(array_keys($scene->symbols),0); foreach ($executions as $e) if ($e->kind==='state' && $e->command->keyword==='USE') $uses[$e->command->arguments[0]]++; return $uses; }
function unusedItems(Scene $scene, Styles $styles, array $executions): array {
    $pens = $brushes = []; foreach ($executions as $e) { if ($e->kind!=='drawing') continue; $k = $e->command->keyword; if (in_array($k,PEN_COMMANDS,true)) $pens[$e->command->arguments[0]] = true; elseif (in_array($k,BRUSH_COMMANDS,true)) $brushes[$e->command->arguments[0]] = true; }
    $colors = [$scene->background=>true]; foreach ($pens as $name=>$_) $colors[$styles->pens[$name]->color] = true; foreach ($brushes as $name=>$_) foreach ($styles->brushes[$name]->colors as $color) $colors[$color] = true;
    $uses = symbolUses($scene,$executions); $unused = []; foreach ([['color',$styles->colors,$colors],['pen',$styles->pens,$pens],['brush',$styles->brushes,$brushes],['symbol',$scene->symbols,array_filter($uses)]] as [$kind,$all,$used]) { $names = array_keys($all); sort($names,SORT_STRING); foreach ($names as $name) if (!isset($used[$name])) $unused[] = [$kind,$name]; } return $unused;
}
function summaryLines(Scene $scene, Styles $styles, array $executions, array $image): array {
    $background = array_slice($styles->colors[$scene->background],0,3); $kinds = ['drawing'=>0,'state'=>0,'error'=>0]; $errors = array_fill_keys(ERROR_NAMES,0); $painted = $erased = 0; $keywords = [];
    foreach ($executions as $e) { $kinds[$e->kind]++; $k = $e->command->keyword; if (!isset($keywords[$k])) $keywords[$k] = [0,0,0]; $keywords[$k][0]++; if ($e->kind==='error') { $errors[$e->error]++; $keywords[$k][1]++; } elseif ($e->kind==='drawing') { $keywords[$k][2] += $e->pixels; if ($k==='ERASE') $erased += $e->pixels; else $painted += $e->pixels; } }
    $lines = ["canvas $scene->width $scene->height",'background '.implode(' ',$background),'layers '.count($scene->layers),'symbols '.count($scene->symbols),'commands '.count($executions),'drawing '.$kinds['drawing'],'state '.$kinds['state'],'errors '.$kinds['error']]; foreach (ERROR_NAMES as $name) $lines[] = "error $name {$errors[$name]}"; $lines[] = "painted $painted"; $lines[] = "erased $erased";
    $counts = []; foreach ($image as $row) foreach ($row as $color) tallyColor($counts,$color); $lines[] = 'colors '.count($counts); foreach (array_slice(rankedColors($counts),0,8) as $i=>$entry) $lines[] = 'top '.($i+1).' '.implode(' ',$entry['color']).' pixels '.$entry['count'];
    $uses = symbolUses($scene,$executions); ksort($uses,SORT_STRING); foreach ($uses as $name=>$count) $lines[] = "symbol $name uses $count"; ksort($keywords,SORT_STRING); foreach ($keywords as $keyword=>[$executed,$bad,$pixels]) $lines[] = "keyword $keyword executed $executed errors $bad pixels $pixels";
    $unused = unusedItems($scene,$styles,$executions); $lines[] = 'unused '.count($unused); foreach ($unused as [$kind,$name]) $lines[] = "unused $kind $name"; return $lines;
}
function probeLines(array $probes, array $image, array $layers): array {
    $lines = []; foreach (array_slice($probes,1,(int)$probes[0]) as $i=>$text) { $words = explode(' ',$text); $values = integers(array_slice($words,1)); $number = $i+1;
        if ($words[0]==='point') { [$x,$y] = $values; $stack = []; foreach ($layers as $j=>$layer) if ($layer->alphaAt($x,$y)>0) $stack[] = ($j+1).':'.$layer->lines[$y][$x]; $lines[] = "point $number $x $y rgb ".implode(' ',$image[$y][$x]).' layers '.count($stack).' stack '.($stack ? implode(' ',$stack) : 'none'); }
        else { [$x0,$y0,$x1,$y1] = $values; $totals = [0,0,0]; $colors = []; $cover = array_fill(0,count($layers),0); for ($y=$y0;$y<=$y1;$y++) for ($x=$x0;$x<=$x1;$x++) { $color = $image[$y][$x]; $colors[implode(' ',$color)] = true; for ($c=0;$c<3;$c++) $totals[$c] += $color[$c]; foreach ($layers as $j=>$layer) if ($layer->alphaAt($x,$y)>0) $cover[$j]++; } $count = ($x1-$x0+1)*($y1-$y0+1); $means = array_map(fn($total) => intdiv($total,$count),$totals); $lines[] = "area $number $x0 $y0 $x1 $y1 pixels $count mean ".implode(' ',$means).' colors '.count($colors).' cover '.implode(' ',$cover); }
    } return $lines;
}

$styles = readStyles(readLines('styles.txt')); $font = readFont(readLines('font.txt')); $scene = readScene(readLines('scene.txt')); $probes = readLines('probes.txt');
$renderer = new Renderer($scene,$styles,$font); $renderer->run(); $image = composite($renderer->layers,$styles->colors[$scene->background],$scene->width,$scene->height);
if (!is_dir('output')) mkdir('output',0777,true);
writePpm($image); writePreview($image); writeText('commands.txt',commandLines($renderer->executions)); writeText('layers.txt',layerLines($scene,$renderer->layers,$renderer->executions)); writeText('summary.txt',summaryLines($scene,$styles,$renderer->executions,$image)); writeText('probes.txt',probeLines($probes,$image,$renderer->layers));
