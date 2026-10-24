<?php
// Immutable tagged trees; PHP array values provide independent history snapshots.
function nval(int $n): array { return ['N', $n]; }
function sval(string $s): array { return ['S', $s]; }
function eval_error(string $s): array { return ['E', $s]; }
function reference(int $c, int $r, int $f = 0): array { return ['R', $c, $r, $f]; }
function cell_id(array $r): int { return $r[2] * 26 + $r[1]; }
function label(int $i): string { return chr(65 + $i % 26) . (intdiv($i, 26) + 1); }
function inside(array $r): bool { return $r[1] >= 0 && $r[1] < 26 && $r[2] >= 0 && $r[2] < 99; }
function make_range(array $a, array $b): array {
    [, $c, $r, $f] = $a; [, $d, $t, $g] = $b;
    $ac = $f & 1; $ar = $f & 2; $bc = $g & 1; $br = $g & 2;
    if ($c > $d) { [$c,$d,$ac,$bc] = [$d,$c,$bc,$ac]; }
    if ($r > $t) { [$r,$t,$ar,$br] = [$t,$r,$br,$ar]; }
    return ['G', reference($c,$r,$ac|$ar), reference($d,$t,$bc|$br)];
}
function address(string $s): array {
    if (!preg_match('/\A[A-Z][1-9][0-9]?\z/', $s)) throw new RuntimeException('bad address');
    return reference(ord($s[0])-65, (int)substr($s,1)-1);
}
function area(string $s): array {
    $p=explode(':',$s); if(count($p)>2) throw new RuntimeException('bad address');
    $a=address($p[0]); $b=count($p)===1?$a:address($p[1]); return make_range($a,$b);
}
function cells(array $g): array {
    $out=[];for($r=$g[1][2];$r<=$g[2][2];$r++)for($c=$g[1][1];$c<=$g[2][1];$c++)$out[]=$r*26+$c;return $out;
}
function contains_cell(array $g,array $r): bool { return $r[1]>=$g[1][1]&&$r[1]<=$g[2][1]&&$r[2]>=$g[1][2]&&$r[2]<=$g[2][2]; }
const LEVELS=[['=','<>','<','<=','>','>='],['&'],['+','-'],['*','/']];
function precedence(string $op): int { foreach(LEVELS as $i=>$xs)if(in_array($op,$xs,true))return $i;return -1; }
final class Parser {
    private array $tokens=[]; private int $at=0;
    private function syntax(int $p): never { throw new RuntimeException("syntax error at $p"); }
    public function __construct(string $s) {
        $i=1;$len=strlen($s);
        while($i<$len){$p=$i+1;$ch=$s[$i];if($ch===' '){$i++;continue;}
            if(ctype_digit($ch)){$j=$i;while($j<$len&&ctype_digit($s[$j]))$j++;if($j-$i>=10)$this->syntax($p);$x=nval((int)substr($s,$i,$j-$i));$i=$j;}
            elseif($ch==='"'){$j=strpos($s,'"',$i+1);if($j===false)$this->syntax($p);$x=sval(substr($s,$i+1,$j-$i-1));$i=$j+1;}
            elseif(ctype_alpha($ch)||$ch==='$'){
                $j=$i;while($j<$len&&(ctype_alnum($s[$j])||$s[$j]==='$'))$j++;$w=strtoupper(substr($s,$i,$j-$i));$i=$j;
                if(preg_match('/\A(\$?)([A-Z])(\$?)([1-9][0-9]?)\z/',$w,$m))$x=reference(ord($m[2])-65,(int)$m[4]-1,($m[1]!==''?1:0)|($m[3]!==''?2:0));
                elseif(preg_match('/\A[A-Z][A-Z0-9]*\z/',$w))$x=[str_starts_with(ltrim(substr($s,$i),' '),'(')?'C':'W',$w];
                else $this->syntax($p);
            }else{$op=substr($s,$i,2);if(!in_array($op,['<>','<=','>='],true))$op=$ch;if(!str_contains('+-*/&(),:=<>',$ch))$this->syntax($p);$x=['T',$op];$i+=strlen($op);}
            $this->tokens[]=[$x,$p];
        }$this->tokens[]=[['Z'],$len+1];
    }
    private function take(string $op): bool { if($this->tokens[$this->at][0]===['T',$op]){$this->at++;return true;}return false; }
    private function expect(string $op): void { if(!$this->take($op))$this->syntax($this->tokens[$this->at][1]); }
    private function expression(int $level=0): array {
        if($level===4)return $this->primary();$a=$this->expression($level+1);
        while($this->tokens[$this->at][0][0]==='T'&&in_array($this->tokens[$this->at][0][1],LEVELS[$level],true)){$op=$this->tokens[$this->at++][0][1];$a=['B',$op,$a,$this->expression($level+1)];}return $a;
    }
    private function primary(): array {
        if($this->take('-'))return ['U',$this->primary()];[$x,$p]=$this->tokens[$this->at++];
        if(in_array($x[0],['N','S','W'],true))return $x;
        if($x[0]==='R'){if(!$this->take(':'))return $x;if($this->tokens[$this->at][0][0]!=='R')$this->syntax($this->tokens[$this->at][1]);return make_range($x,$this->tokens[$this->at++][0]);}
        if($x[0]==='C'){$this->expect('(');$args=[];if(!$this->take(')')){$args[]=$this->expression();while($this->take(','))$args[]=$this->expression();$this->expect(')');}return ['F',$x[1],$args];}
        if($x===['T','(']){$a=$this->expression();$this->expect(')');return $a;}$this->syntax($p);
    }
    public function parse(): array { $x=$this->expression();if($this->tokens[$this->at][0][0]!=='Z')$this->syntax($this->tokens[$this->at][1]);return $x; }
}
function canonical(array $x): string {
    switch($x[0]){
    case 'N':return (string)$x[1];case 'S':return '"'.$x[1].'"';case 'W':return $x[1];case 'X':return '#REF!';
    case 'R':return (($x[3]&1)?'$':'').chr(65+$x[1]).(($x[3]&2)?'$':'').($x[2]+1);
    case 'G':return canonical($x[1]).':'.canonical($x[2]);
    case 'F':return $x[1].'('.implode(',',array_map('canonical',$x[2])).')';
    case 'U':return '-'.($x[1][0]==='B'?'('.canonical($x[1]).')':canonical($x[1]));
    case 'B':$a=canonical($x[2]);$b=canonical($x[3]);if($x[2][0]==='B'&&precedence($x[2][1])<precedence($x[1]))$a="($a)";if($x[3][0]==='B'&&precedence($x[3][1])<=precedence($x[1]))$b="($b)";return $a.$x[1].$b;
    }throw new LogicException('invalid tree');
}
function display(?array $x): string { return $x===null?'':(string)$x[1]; }
function notation(?array $x): string { return $x===null?'(empty)':($x[0]==='='?'='.canonical($x[1]):($x[0]==='S'?'"'.$x[1].'"':display($x))); }
function to_number(?array $x): array { return $x===null?nval(0):(in_array($x[0],['S','G'],true)?eval_error('#VALUE!'):$x); }
function to_string(?array $x): array { return $x===null?sval(''):($x[0]==='N'?sval((string)$x[1]):($x[0]==='G'?eval_error('#VALUE!'):$x)); }
function rewrite(?array $x,callable $f): ?array {
    if($x===null)return null;
    switch($x[0]){
    case 'R':case 'G':return $f($x);
    case 'F':return ['F',$x[1],array_map(fn($a)=>rewrite($a,$f),$x[2])];
    case 'B':return ['B',$x[1],rewrite($x[2],$f),rewrite($x[3],$f)];
    case 'U':case '=':return [$x[0],rewrite($x[1],$f)];default:return $x;
    }
}
function dependencies(?array $x,array &$out): void {
    if($x===null)return;
    switch($x[0]){
    case 'R':$out[cell_id($x)]=true;break;
    case 'G':foreach(cells($x) as $i)$out[$i]=true;break;
    case 'F':foreach($x[2] as $a)dependencies($a,$out);break;
    case 'B':dependencies($x[2],$out);dependencies($x[3],$out);break;
    case 'U':case '=':dependencies($x[1],$out);
    }
}
final class Sheet {
    private array $contents;private array $values;private array $deps;private array $history=[];
    public function __construct(){$this->contents=array_fill(0,2574,null);$this->values=$this->contents;$this->deps=array_fill(0,2574,[]);}
    private function evaluate(array $x): ?array {
        switch($x[0]){
        case 'N':case 'S':case 'G':return $x;
        case 'R':return $this->values[cell_id($x)];case 'W':return eval_error('#NAME?');case 'X':return eval_error('#REF!');
        case 'U':$a=to_number($this->evaluate($x[1]));return $a[0]==='E'?$a:nval(-$a[1]);
        case 'B':
            $a=$this->evaluate($x[2]);$b=$this->evaluate($x[3]);if(($a[0]??'')==='E')return $a;if(($b[0]??'')==='E')return $b;$op=$x[1];
            if(precedence($op)===0){
                if(($a[0]??'')==='G'||($b[0]??'')==='G')return eval_error('#VALUE!');$blank=($a[0]??'')==='S'||($b[0]??'')==='S'?sval(''):nval(0);$a??=$blank;$b??=$blank;
                $c=$a[0]!==$b[0]?($a[0]==='N'?-1:1):($a[0]==='N'?($a[1]<=>$b[1]):strcmp($a[1],$b[1]));
                return nval((int)match($op){'='=>$c===0,'<>'=>$c!==0,'<'=>$c<0,'<='=>$c<=0,'>'=>$c>0,default=>$c>=0});
            }
            $a=$op==='&'?to_string($a):to_number($a);$b=$op==='&'?to_string($b):to_number($b);if($a[0]==='E')return $a;if($b[0]==='E')return $b;
            return match($op){'&'=>sval($a[1].$b[1]),'+'=>nval($a[1]+$b[1]),'-'=>nval($a[1]-$b[1]),'*'=>nval($a[1]*$b[1]),default=>$b[1]===0?eval_error('#DIV/0!'):nval(intdiv($a[1],$b[1]))};
        case 'F':return $this->call($x[1],$x[2]);
        }throw new LogicException('invalid expression');
    }
    private function call(string $name,array $args): ?array {
        if(in_array($name,['SUM','MIN','MAX','COUNT','AVERAGE','AND','OR','CONCAT'],true)){
            if(!$args)return eval_error('#VALUE!');$items=[];$ns=[];
            foreach($args as $a){$v=$this->evaluate($a);if(($v[0]??'')==='G'){foreach(cells($v) as $i)$items[]=$this->values[$i];}else $items[]=$v;}
            foreach($items as $v)if(($v[0]??'')==='N')$ns[]=$v[1];if($name==='COUNT')return nval(count($ns));foreach($items as $v)if(($v[0]??'')==='E')return $v;
            return match($name){
                'SUM'=>nval(array_sum($ns)),'MIN'=>nval($ns?min($ns):0),'MAX'=>nval($ns?max($ns):0),
                'AVERAGE'=>$ns?nval(intdiv(array_sum($ns),count($ns))):eval_error('#DIV/0!'),
                'AND'=>$ns?nval((int)!in_array(0,$ns,true)):eval_error('#VALUE!'),
                'OR'=>$ns?nval((int)(count(array_filter($ns,fn($n)=>$n!==0))>0)):eval_error('#VALUE!'),
                default=>sval(implode('',array_map(fn($v)=>to_string($v)[1],$items)))
            };
        }
        if($name==='IF'){if(!in_array(count($args),[2,3],true))return eval_error('#VALUE!');$c=to_number($this->evaluate($args[0]));if($c[0]==='E')return $c;return $c[1]!==0?$this->evaluate($args[1]):(count($args)===3?$this->evaluate($args[2]):nval(0));}
        if(!in_array($name,['ABS','NOT','LEN'],true))return eval_error('#NAME?');if(count($args)!==1)return eval_error('#VALUE!');$v=$this->evaluate($args[0]);$v=$name==='LEN'?to_string($v):to_number($v);return $v[0]==='E'?$v:nval($name==='LEN'?strlen($v[1]):($name==='ABS'?abs($v[1]):(int)($v[1]===0)));
    }
    private function recalculate(): void {
        $indices=array_fill(0,2574,-1);$low=[];$on=[];$stack=[];$cyclic=[];$serial=0;
        for($i=0;$i<2574;$i++){$this->deps[$i]=[];if(($this->contents[$i][0]??'')==='='){dependencies($this->contents[$i][1],$this->deps[$i]);$this->values[$i]=null;}else $this->values[$i]=$this->contents[$i];}
        $visit=function(int $i)use(&$visit,&$indices,&$low,&$on,&$stack,&$cyclic,&$serial):void{
            $indices[$i]=$low[$i]=$serial++;$stack[]=$i;$on[$i]=true;
            foreach($this->deps[$i] as $j=>$_)if(($this->contents[$j][0]??'')==='='){
                if($indices[$j]<0){$visit($j);$low[$i]=min($low[$i],$low[$j]);}elseif(isset($on[$j]))$low[$i]=min($low[$i],$indices[$j]);
            }
            if($low[$i]===$indices[$i]){$part=[];do{$j=array_pop($stack);unset($on[$j]);$part[]=$j;}while($j!==$i);if(count($part)>1||isset($this->deps[$i][$i]))foreach($part as $j)$cyclic[$j]=true;}
        };
        for($i=0;$i<2574;$i++)if(($this->contents[$i][0]??'')==='='&&$indices[$i]<0)$visit($i);
        $done=[];$calculate=function(int $i)use(&$calculate,&$done,$cyclic):void{
            if(($this->contents[$i][0]??'')!=='='||isset($done[$i]))return;$done[$i]=true;if(isset($cyclic[$i])){$this->values[$i]=eval_error('#CYCLE!');return;}
            foreach($this->deps[$i] as $j=>$_)$calculate($j);$v=$this->evaluate($this->contents[$i][1]);$this->values[$i]=$v===null?nval(0):($v[0]==='G'?eval_error('#VALUE!'):$v);
        };for($i=0;$i<2574;$i++)$calculate($i);
    }
    private function replace(array $next):int {$old=$this->values;$this->contents=$next;$this->recalculate();$n=0;foreach($old as $i=>$v)$n+=(int)($v!==$this->values[$i]);return $n;}
    private function describe(int $i):string {return label($i).': '.notation($this->contents[$i]).' -> '.notation($this->values[$i]);}
    public function execute(string $line): array {
        [$name,$rest]=array_pad(explode(' ',$line,2),2,'');
        if($name==='SHOW')return [$this->describe(cell_id(address($rest)))];
        if($name==='LIST'){$out=[];foreach($this->contents as $i=>$v)if($v!==null)$out[]=$this->describe($i);return $out?:['(no cells)'];}
        if($name==='DEPS'){$i=cell_id(address($rest));$ps=array_keys($this->deps[$i]);sort($ps,SORT_NUMERIC);$ds=[];foreach($this->deps as $j=>$xs)if(isset($xs[$i]))$ds[]=$j;$format=fn($xs)=>$xs?implode(',',array_map('label',$xs)):'none';return [$rest.': precedents='.$format($ps).' dependents='.$format($ds)];}
        if($name==='PRINT'){
            $g=area($rest);$rw=strlen((string)($g[2][2]+1));$ws=[];$sep='+'.str_repeat('-',$rw).'+';$head='|'.str_repeat(' ',$rw).'|';
            for($c=$g[1][1];$c<=$g[2][1];$c++){$w=1;for($r=$g[1][2];$r<=$g[2][2];$r++)$w=max($w,strlen(display($this->values[$r*26+$c])));$ws[]=$w;$sep.=str_repeat('-',$w).'+';$head.=str_pad(chr(65+$c),$w).'|';}
            $out=[$sep,$head,$sep];for($r=$g[1][2];$r<=$g[2][2];$r++){$s='|'.str_pad((string)($r+1),$rw,' ',STR_PAD_LEFT).'|';foreach($ws as $j=>$w){$v=$this->values[$r*26+$g[1][1]+$j];$s.=str_pad(display($v),$w,' ',($v[0]??'')==='N'?STR_PAD_LEFT:STR_PAD_RIGHT).'|';}$out[]=$s;}$out[]=$sep;return $out;
        }
        if($name==='UNDO'){if(!$this->history)throw new RuntimeException('nothing to undo');[$command,$old]=array_pop($this->history);return ['UNDO '.$command.' changed='.$this->replace($old)];}
        $next=$this->contents;$target=-1;
        if($name==='SET'){
            [$a,$s]=explode(' ',$rest,2);$target=cell_id(address($a));
            if($s[0]==='=')$next[$target]=['=',(new Parser($s))->parse()];elseif(preg_match('/\A"[^"]*"\z/',$s))$next[$target]=sval(substr($s,1,-1));elseif(preg_match('/\A(?:0|-?[1-9][0-9]{0,8})\z/',$s))$next[$target]=nval((int)$s);else throw new RuntimeException('bad value');
        }elseif($name==='CLEAR'){foreach(cells(area($rest)) as $i)$next[$i]=null;}
        elseif($name==='COPY'||$name==='MOVE'){
            [$a,$b]=explode(' ',$rest);$source=area($a);$dest=address($b);$dc=$dest[1]-$source[1][1];$dr=$dest[2]-$source[1][2];
            $shift=fn($r,$rel)=>reference($r[1]+($rel&&($r[3]&1)?0:$dc),$r[2]+($rel&&($r[3]&2)?0:$dr),$r[3]);$destination=make_range($shift($source[1],false),$shift($source[2],false));if(!inside($destination[1])||!inside($destination[2]))throw new RuntimeException('out of grid');
            $transform=function($x)use($name,$source,$destination,$shift){
                if($x[0]==='R'){if($name==='COPY'){$r=$shift($x,true);return inside($r)?$r:['X'];}return contains_cell($source,$x)?$shift($x,false):(contains_cell($destination,$x)?['X']:$x);}
                if($name==='MOVE'&&!(contains_cell($source,$x[1])&&contains_cell($source,$x[2])))return $x;$a=$shift($x[1],$name==='COPY');$b=$shift($x[2],$name==='COPY');return inside($a)&&inside($b)?make_range($a,$b):['X'];
            };
            if($name==='MOVE')$next=array_map(fn($x)=>rewrite($x,$transform),$next);$moving=[];foreach(cells($source) as $i)$moving[]=[$i,$name==='COPY'?rewrite($this->contents[$i],$transform):$next[$i]];if($name==='MOVE')foreach($moving as [$i,$_])$next[$i]=null;foreach($moving as [$i,$x])$next[$i+$dr*26+$dc]=$x;
        }elseif(in_array($name,['INSERTROW','DELETEROW','INSERTCOL','DELETECOL'],true)){
            $row=str_ends_with($name,'ROW');$insert=str_starts_with($name,'INSERT');if(!preg_match($row?'/\A[1-9][0-9]?\z/':'/\A[A-Z]\z/',$rest))throw new RuntimeException('bad address');$at=$row?(int)$rest-1:ord($rest)-65;$limit=$row?99:26;$axis=fn($x)=>$x[$row?2:1];$change=fn($x,$v)=>$row?reference($x[1],$v,$x[3]):reference($v,$x[2],$x[3]);
            if($insert)foreach($this->contents as $i=>$x)if($x!==null&&($row?intdiv($i,26):$i%26)===$limit-1)throw new RuntimeException('last '.($row?'row':'column').' not empty');
            $transform=function($x)use($insert,$at,$limit,$axis,$change){
                if($x[0]==='R'){$v=$axis($x);if(!$insert&&$v===$at)return ['X'];$n=$v+($insert?(int)($v>=$at):-(int)($v>$at));return $n>=$limit?['X']:$change($x,$n);}
                $a=$axis($x[1]);$b=$axis($x[2]);if(!$insert&&$a===$at&&$b===$at)return ['X'];$u=$a+($insert?(int)($a>=$at):-(int)($a>$at));$v=$b+($insert?(int)($b>=$at):-(int)($b>=$at));return $v>=$limit?['X']:make_range($change($x[1],$u),$change($x[2],$v));
            };
            $next=array_fill(0,2574,null);foreach($this->contents as $i=>$x)if($x!==null){$r=reference($i%26,intdiv($i,26));$v=$axis($r);if(!$insert&&$v===$at)continue;$t=$change($r,$v+($insert?(int)($v>=$at):-(int)($v>$at)));$next[cell_id($t)]=rewrite($x,$transform);}
        }else throw new RuntimeException('unknown command');
        $this->history[]=[$name,$this->contents];$changed=$this->replace($next);return [$name.($name==='SET'?' '.label($target).'='.notation($this->values[$target]):'').' changed='.$changed];
    }
}
$n=(int)fgets(STDIN);$sheet=new Sheet();for($i=0;$i<$n;$i++){try{$out=$sheet->execute(rtrim(fgets(STDIN),"\r\n"));echo implode("\n",$out),"\n";}catch(RuntimeException $e){echo 'ERROR ',$e->getMessage(),"\n";}}
