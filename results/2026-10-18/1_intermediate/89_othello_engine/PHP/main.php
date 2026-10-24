<?php
const WEIGHTS=[100,-20,10,5,5,10,-20,100,-20,-50,-2,-2,-2,-2,-50,-20,10,-2,-1,-1,-1,-1,-2,10,5,-2,-1,-1,-1,-1,-2,5,5,-2,-1,-1,-1,-1,-2,5,10,-2,-1,-1,-1,-1,-2,10,-20,-50,-2,-2,-2,-2,-50,-20,100,-20,10,5,5,10,-20,100];
const TRANSFORMS=['rot90','rot180','rot270','mirror','flip','diag','anti'];
const ZERO=['NEW','DUMP','SHOW','SCORE','LEGAL','HISTORY','SHEET','STATS','EVAL','STABLE','SOLVE'];
const NUMERIC=['UNDO','REDO','HINT','PV','AI','ANALYZE','RANDOM','PERFT','DIVIDE'];
const ACTIVE=['FLIPS','MOVE','PLAY','HINT','PV','AI','SOLVE','AUTOPLAY','RANDOM','MC','DIVIDE'];
function other(string $s): string {return $s==='B'?'W':'B';}
function squareName(int $p): string {return 'abcdefgh'[$p%8].(intdiv($p,8)+1);}
function squareIndex(string $s): int {return ((int)$s[1]-1)*8+ord($s[0])-97;}
function inside(int $r,int $c): bool {return $r>=0&&$r<8&&$c>=0&&$c<8;}
function initial(): string {$b=str_repeat('.',64);$b[27]=$b[36]='W';$b[28]=$b[35]='B';return $b;}
function flips(string $b,string $s,int $p): array {if($b[$p]!=='.')return [];$out=[];$row=intdiv($p,8);$col=$p%8;for($dr=-1;$dr<=1;$dr++)for($dc=-1;$dc<=1;$dc++){if(!$dr&&!$dc)continue;$r=$row+$dr;$c=$col+$dc;$line=[];while(inside($r,$c)&&$b[8*$r+$c]===other($s)){$line[]=8*$r+$c;$r+=$dr;$c+=$dc;}if($line&&inside($r,$c)&&$b[8*$r+$c]===$s)array_push($out,...$line);}sort($out,SORT_NUMERIC);return $out;}
function legal(string $b,string $s): array {$ms=[];for($p=0;$p<64;$p++)if($b[$p]==='.'&&flips($b,$s,$p))$ms[]=$p;return $ms;}
function place(string $b,string $s,int $p): string {foreach(flips($b,$s,$p) as $q)$b[$q]=$s;$b[$p]=$s;return $b;}
function terminal(string $b): bool {return !legal($b,'B')&&!legal($b,'W');}
function gameOver(string $b): string {$x=substr_count($b,'B');$y=substr_count($b,'W');return "game over B $x W $y ".($x>$y?'winner B':($x<$y?'winner W':'draw'));}
function evaluate(string $b,string $s): array {$w=0;for($i=0;$i<64;$i++)$w+=$b[$i]===$s?WEIGHTS[$i]:($b[$i]===other($s)?-WEIGHTS[$i]:0);$own=count(legal($b,$s));$enemy=count(legal($b,other($s)));return [$w+10*($own-$enemy),$w,$own,$enemy];}
function search(string $b,string $s,int $d): int {static $cache=[];$key=$b.$s.':'.$d;if(isset($cache[$key]))return $cache[$key];$ms=legal($b,$s);$o=other($s);if(!$ms&&!legal($b,$o))$v=($d<0?1:1000)*(substr_count($b,$s)-substr_count($b,$o));elseif($d===0)$v=evaluate($b,$s)[0];elseif(!$ms)$v=-search($b,$o,$d<0?-1:$d-1);else{$v=-1000000;foreach($ms as $p)$v=max($v,-search(place($b,$s,$p),$o,$d<0?-1:$d-1));}if(count($cache)>300000)$cache=[];return $cache[$key]=$v;}
function ranked(string $b,string $s,int $d): array {$out=[];foreach(legal($b,$s) as $p)$out[]=[-search(place($b,$s,$p),other($s),$d<0?-1:$d-1),$p];usort($out,fn($a,$b)=>($b[0]<=>$a[0])?:($a[1]<=>$b[1]));return $out;}
function variation(string $b,string $s,int $d): array {$steps=[];while($d!==0&&!terminal($b)){$ms=ranked($b,$s,$d);if($ms){$p=$ms[0][1];$steps[]=squareName($p);$b=place($b,$s,$p);}else $steps[]='pass';$s=other($s);if($d>0)$d--;}return [$steps,$b];}
function perft(string $b,string $s,int $d): int {if(!$d)return 1;static $cache=[];$key=$b.$s.$d;if(isset($cache[$key]))return $cache[$key];$ms=legal($b,$s);$n=0;if(!$ms)$n=legal($b,other($s))?perft($b,other($s),$d-1):1;else foreach($ms as $p)$n+=perft(place($b,$s,$p),other($s),$d-1);if(count($cache)>200000)$cache=[];return $cache[$key]=$n;}
function stable(string $b): array {$stable=array_fill(0,64,false);$axes=[[0,1],[1,0],[1,1],[1,-1]];while(true){$found=[];for($p=0;$p<64;$p++){if($b[$p]==='.'||$stable[$p])continue;$row=intdiv($p,8);$col=$p%8;$ok=true;foreach($axes as [$dr,$dc]){$full=true;$anchor=false;foreach([-1,1] as $sign){$r=$row+$dr*$sign;$c=$col+$dc*$sign;if(!inside($r,$c)||($stable[8*$r+$c]&&$b[8*$r+$c]===$b[$p]))$anchor=true;while(inside($r,$c)){if($b[8*$r+$c]==='.')$full=false;$r+=$dr*$sign;$c+=$dc*$sign;}}if(!$full&&!$anchor){$ok=false;break;}}if($ok)$found[]=$p;}if(!$found)break;foreach($found as $p)$stable[$p]=true;}$black=$white=0;foreach($stable as $p=>$yes)if($yes){if($b[$p]==='B')$black++;else $white++;}return [$black,$white];}
function transform(int $p,string $op): int {$r=intdiv($p,8);$c=$p%8;return match($op){'rot90'=>8*$c+7-$r,'rot180'=>63-$p,'rot270'=>8*(7-$c)+$r,'mirror'=>8*$r+7-$c,'flip'=>8*(7-$r)+$c,'diag'=>8*$c+$r,default=>8*(7-$c)+7-$r};}
function transformBoard(string $b,string $op): string {$a=str_repeat('.',64);for($p=0;$p<64;$p++)$a[transform($p,$op)]=$b[$p];return $a;}
class Minstd {function __construct(private int $value){}function draw(): int {return $this->value=$this->value*48271%2147483647;}}
function randomGame(string $b,string $s,Minstd $rng): string {while(true){$ms=legal($b,$s);if($ms)$b=place($b,$s,$ms[$rng->draw()%count($ms)]);elseif(!legal($b,other($s)))return $b;$s=other($s);}}
function average(int $f,int $n): string {$v=intdiv(100*$f,$n);return intdiv($v,100).'.'.str_pad((string)($v%100),2,'0',STR_PAD_LEFT);}
class Othello {
    private string $board;private string $side;private bool $over;private array $history=[];private array $redo=[];
    function __construct(){$this->reset();}
    function reset(): void {$this->board=initial();$this->side='B';$this->over=false;$this->history=[];$this->redo=[];}
    function emit(...$xs): void {echo implode(' ',$xs),"\n";}
    function snapshot(): array {return [$this->board,$this->side,$this->over];}
    function restore(array $p): void {[$this->board,$this->side,$this->over]=$p;}
    function status(): string {return $this->over?gameOver($this->board):$this->side.' to move';}
    function adjust(bool $quiet=false): bool {if(legal($this->board,$this->side))return false;if(legal($this->board,other($this->side))){if(!$quiet)$this->emit($this->side,'passes');$this->side=other($this->side);return true;}$this->over=true;if(!$quiet)$this->emit(gameOver($this->board));return false;}
    function move(int $p,bool $quiet=false,?int $value=null): bool {$before=$this->snapshot();$s=$this->side;$k=count(flips($this->board,$s,$p));$this->board=place($this->board,$s,$p);if(!$quiet)$this->emit($s,squareName($p),'flips',$k,...($value===null?[]:['value',$value]));$this->side=other($s);$passed=$this->adjust($quiet);$this->history[]=['side'=>$s,'square'=>$p,'count'=>$k,'passed'=>$passed,'before'=>$before,'after'=>$this->snapshot()];$this->redo=[];return $passed;}
    function reason(int $p): string {return $this->over?'game over':($this->board[$p]!=='.'?'occupied':(!flips($this->board,$this->side,$p)?'no flips':''));}
    function record(string $text): void {$e=new Othello();$ps=[];$passes=0;foreach(str_split($text,2) as $i=>$s){$p=squareIndex($s);$why=$e->reason($p);if($why!==''){$this->emit('ILLEGAL move',$i+1,$s,$why);return;}$ps[]=$p;$passes+=(int)$e->move($p,true);}$this->restore($e->snapshot());$this->history=$e->history;$this->redo=[];$op=['f5'=>'','e6'=>'diag','d3'=>'anti','c4'=>'rot180'][squareName($ps[0])];$normal='';foreach($ps as $p)$normal.=squareName($op===''?$p:transform($p,$op));$this->emit('record',count($ps),'moves',$passes,'passes');$this->emit('normal',$normal);$this->emit($this->status());}
    function sheet(): void {$fields=str_split($this->history?$this->history[0]['before'][0]:$this->board);foreach($this->history as $i=>$r)$fields[$r['square']]=(string)($i+1);$this->emit(' '.implode('',array_map(fn($s)=>str_pad($s,3,' ',STR_PAD_LEFT),str_split('abcdefgh'))));for($r=0;$r<8;$r++)$this->emit(($r+1).implode('',array_map(fn($s)=>str_pad($s,3,' ',STR_PAD_LEFT),array_slice($fields,8*$r,8))));}
    function stats(): void {$all=$this->history;$total=array_sum(array_column($all,'count'));if(!$all)$this->emit('moves 0');else $this->emit('moves',count($all),'flips',$total,'avg',average($total,count($all)),'passes',count(array_filter($all,fn($r)=>$r['passed'])));foreach(['B','W'] as $s){$rows=array_values(array_filter($all,fn($r)=>$r['side']===$s));if(!$rows){$this->emit($s,'moves 0');continue;}$sum=array_sum(array_column($rows,'count'));$max=max(array_column($rows,'count'));$first=array_values(array_filter($rows,fn($r)=>$r['count']===$max))[0];$corners=count(array_filter($rows,fn($r)=>in_array($r['square'],[0,7,56,63],true)));$this->emit($s,'moves',count($rows),'flips',$sum,'avg',average($sum,count($rows)),'max',$max,squareName($first['square']),'corners',$corners);}}
    function autoplay(int $black,int $white,int $seed=0): void {$rng=$seed?new Minstd($seed):null;$ps=[];$passes=0;while(!$this->over){$ms=legal($this->board,$this->side);$p=$rng?$ms[$rng->draw()%count($ms)]:ranked($this->board,$this->side,$this->side==='B'?$black:$white)[0][1];$ps[]=squareName($p);$passes+=(int)$this->move($p,true);}$this->emit($rng?'random':'autoplay',count($ps),'moves',$passes,'passes');$this->emit('moves',implode('',$ps));$this->emit(gameOver($this->board));}
    function monteCarlo(int $k,int $seed): void {$rng=new Minstd($seed);$best=$bp=-1;foreach(legal($this->board,$this->side) as $p){$w=$d=$l=0;$start=place($this->board,$this->side,$p);for($i=0;$i<$k;$i++){$b=randomGame($start,other($this->side),$rng);$diff=substr_count($b,$this->side)-substr_count($b,other($this->side));if($diff>0)$w++;elseif($diff<0)$l++;else $d++;}$this->emit(squareName($p),$w,$d,$l);if(2*$w+$d>$best){$best=2*$w+$d;$bp=$p;}}$this->emit('best',squareName($bp),$best);}
    function execute(string $text): void {$a=explode(' ',$text);$cmd=array_shift($a);$error='';$commands=array_merge(ZERO,NUMERIC,['LOAD','TRANSFORM','AUTOPLAY','MC','FLIPS','MOVE','PLAY','RECORD']);
        if(!in_array($cmd,$commands,true))$error='unknown command';
        elseif($cmd==='LOAD'){if(count($a)!==2||!preg_match('/^[.BW]{64}$/D',$a[0])||!in_array($a[1],['B','W'],true))$error='bad board';}
        elseif(in_array($cmd,['MOVE','FLIPS'],true)){$error=count($a)!==1?'bad arguments':(!preg_match('/^[a-h][1-8]$/D',$a[0])?'bad square':'');}
        elseif(in_array($cmd,['PLAY','RECORD'],true)){$error=count($a)!==1?'bad arguments':(strlen($a[0])>120||!preg_match('/^([a-h][1-8])+$/D',$a[0])?'bad record':'');}
        elseif(in_array($cmd,ZERO,true)){if($a)$error='bad arguments';}
        elseif($cmd==='TRANSFORM'){if(count($a)!==1||!in_array($a[0],TRANSFORMS,true))$error='bad arguments';}
        else {$expected=in_array($cmd,['AUTOPLAY','MC'],true)?2:1;$valid=count($a)===$expected;foreach($a as $s)if(!preg_match('/^[0-9]+$/D',$s))$valid=false;if($valid){$ns=array_map('intval',$a);$n=$ns[0];$valid=match($cmd){'AUTOPLAY'=>$n>=1&&$n<=4&&$ns[1]>=1&&$ns[1]<=4,'HINT','PV','AI','ANALYZE'=>$n>=1&&$n<=4,'PERFT','DIVIDE'=>$n>=1&&$n<=8,'MC'=>$n>=1&&$n<=100&&$ns[1]>=1&&$ns[1]<=2147483646,'RANDOM'=>$n>=1&&$n<=2147483646,default=>$n>=1};}if(!$valid)$error='bad arguments';}
        if($error!==''){$this->emit('ERROR',$error);return;}if($this->over&&in_array($cmd,ACTIVE,true)){$this->emit('ERROR game over');return;}$n=(int)($a[0]??0);
        switch($cmd){
        case 'NEW':$this->reset();$this->emit('OK');break;
        case 'LOAD':$this->board=$a[0];$this->side=$a[1];$this->over=false;$this->history=[];$this->redo=[];$this->emit('OK');$this->adjust();break;
        case 'DUMP':$this->emit('board',$this->board,$this->side);break;
        case 'SHOW':$this->emit('  a b c d e f g h');$ms=$this->over?[]:legal($this->board,$this->side);for($r=0;$r<8;$r++){$row=[$r+1];for($c=0;$c<8;$c++)$row[]=in_array(8*$r+$c,$ms,true)?'*':$this->board[8*$r+$c];$this->emit(...$row);}$this->emit($this->status());break;
        case 'SCORE':$this->emit('score B',substr_count($this->board,'B'),'W',substr_count($this->board,'W'),'empty',substr_count($this->board,'.'));break;
        case 'LEGAL':$ms=$this->over?[]:legal($this->board,$this->side);$this->emit('legal',count($ms),...array_map('squareName',$ms));break;
        case 'MOVE':case 'FLIPS':$p=squareIndex($a[0]);$why=$this->reason($p);if($why!=='')$this->emit('ILLEGAL',$why);elseif($cmd==='MOVE')$this->move($p);else{$f=flips($this->board,$this->side,$p);$this->emit('flips',$a[0],count($f),...array_map('squareName',$f));}break;
        case 'PLAY':foreach(str_split($a[0],2) as $i=>$s){$p=squareIndex($s);$why=$this->reason($p);if($why!==''){$this->emit('ILLEGAL move',$i+1,$s,$why);break;}$this->move($p);}break;
        case 'RECORD':$this->record($a[0]);break;
        case 'UNDO':if($n>count($this->history))$this->emit('ERROR cannot undo');else{$removed=array_splice($this->history,-$n);$this->restore($removed[0]['before']);$this->redo=array_merge($removed,$this->redo);$this->emit($this->status());}break;
        case 'REDO':if($n>count($this->redo))$this->emit('ERROR cannot redo');else{$added=array_splice($this->redo,0,$n);array_push($this->history,...$added);$this->restore($added[count($added)-1]['after']);$this->emit($this->status());}break;
        case 'HISTORY':$this->emit('history',count($this->history));foreach($this->history as $i=>$r)$this->emit($i+1,$r['side'],squareName($r['square']),$r['count'],...($r['passed']?['pass']:[]));break;
        case 'SHEET':$this->sheet();break;
        case 'STATS':$this->stats();break;
        case 'TRANSFORM':$op=$a[0];$this->board=transformBoard($this->board,$op);$tr=function($r)use($op){$r['square']=transform($r['square'],$op);$r['before'][0]=transformBoard($r['before'][0],$op);$r['after'][0]=transformBoard($r['after'][0],$op);return $r;};$this->history=array_map($tr,$this->history);$this->redo=array_map($tr,$this->redo);$this->emit('OK');break;
        case 'EVAL':[$v,$w,$x,$y]=evaluate($this->board,$this->side);$this->emit('eval',$v,'weights',$w,'mobility',$x,$y);break;
        case 'STABLE':[$b,$w]=stable($this->board);$this->emit('stable B',$b,'W',$w);break;
        case 'HINT':foreach(ranked($this->board,$this->side,$n) as [$v,$p])$this->emit(squareName($p),$v);break;
        case 'PV':[$steps]=variation($this->board,$this->side,$n);$this->emit('pv',search($this->board,$this->side,$n),...$steps);break;
        case 'AI':[$v,$p]=ranked($this->board,$this->side,$n)[0];$this->move($p,false,$v);break;
        case 'ANALYZE':$loss=['B'=>0,'W'=>0];foreach($this->history as $i=>$r){$rows=ranked($r['before'][0],$r['side'],$n);[$best,$bp]=$rows[0];foreach($rows as [$value,$p])if($p===$r['square']){$v=$value;break;}$loss[$r['side']]+=$best-$v;$this->emit($i+1,$r['side'],squareName($r['square']),$v,'best',squareName($bp),$best);}$this->emit('loss B',$loss['B'],'W',$loss['W']);break;
        case 'SOLVE':if(substr_count($this->board,'.')>=9)$this->emit('ERROR too many empties');else{foreach(ranked($this->board,$this->side,-1) as [$v,$p])$this->emit(squareName($p),$v);[$steps,$b]=variation($this->board,$this->side,-1);$this->emit('line',...$steps);$this->emit('final B',substr_count($b,'B'),'W',substr_count($b,'W'));}break;
        case 'AUTOPLAY':$this->autoplay($n,(int)$a[1]);break;
        case 'RANDOM':$this->autoplay(0,0,$n);break;
        case 'MC':$this->monteCarlo($n,(int)$a[1]);break;
        case 'PERFT':$this->emit('perft',$n,perft($this->board,$this->side,$n));break;
        case 'DIVIDE':$total=0;foreach(legal($this->board,$this->side) as $p){$v=perft(place($this->board,$this->side,$p),other($this->side),$n-1);$this->emit(squareName($p),$v);$total+=$v;}$this->emit('total',$total);break;
        }
    }
}
$engine=new Othello();$n=(int)trim(fgets(STDIN));for($i=0;$i<$n;$i++)$engine->execute(rtrim(fgets(STDIN),"\r\n"));
