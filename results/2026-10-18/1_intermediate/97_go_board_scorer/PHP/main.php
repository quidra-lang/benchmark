<?php
const COLUMNS='ABCDEFGHJKLMNOPQRST';
const HANDICAP=[9=>['C3','G7','C7','G3','C5','G5','E3','E7','E5'],13=>['D4','K10','D10','K4','D7','K7','G4','G10','G7'],19=>['D4','Q16','D16','Q4','D10','Q10','K4','K16','K10']];
const ARITY=['BOARD'=>2,'KOMI'=>1,'SUPERKO'=>1,'HANDICAP'=>1,'PLAY'=>2,'PASS'=>1,'REPLAY'=>1,'UNDO'=>0,'SHOW'=>0,'MAP'=>0,'STATUS'=>0,'CAPTURES'=>0,'HISTORY'=>0,'MOVES'=>0,'GROUP'=>1,'GROUPS'=>0,'ATARI'=>0,'LEGAL'=>1,'EYES'=>1,'SAFE'=>1,'LADDER'=>1,'DEAD'=>1,'REGIONS'=>0,'SCORE'=>1];
function other(string $c): string {
    return $c==='B'?'W':'B';
}
function halfText(int $x): string {
    return ($x<0?'-':'').intdiv(abs($x),2).(abs($x)%2?'.5':'.0');
}
function parseKomi(string $s): ?int {
    if(!preg_match('~\A-?(0|[1-9][0-9]*)(?:\.[05])?\z~',$s))return null;
    $negative=$s[0]==='-';
    $parts=explode('.',$negative?substr($s,1):$s);
    if(strlen($parts[0])>3||(int)$parts[0]>100)return null;
    $v=2*(int)$parts[0]+(($parts[1]??'')==='5'?1:0);
    return $negative&&$v===0?null:($negative?-$v:$v);
}
function adjacent(int $p,int $n,bool $diagonal=false): array {
    $r=intdiv($p,$n);
    $c=$p%$n;
    $a=[];
    foreach($diagonal?[[-1,-1],[-1,1],[1,-1],[1,1]]:[[-1,0],[1,0],[0,-1],[0,1]] as [$dr,$dc])if($r+$dr>=0&&$r+$dr<$n&&$c+$dc>=0&&$c+$dc<$n)$a[]=($r+$dr)*$n+$c+$dc;
    return $a;
}
function ordered(array $s): array {
    $a=array_keys($s);
    sort($a,SORT_NUMERIC);
    return $a;
}
function flood(string $b,int $n,int $p,string $allowed): array {
    $seen=[$p=>true];
    $todo=[$p];
    while($todo)foreach(adjacent(array_pop($todo),$n) as $q)if(!isset($seen[$q])&&str_contains($allowed,$b[$q])){
        $seen[$q]=true;
        $todo[]=$q;
    }
    return $seen;
}
function group(string $b,int $n,int $p): array {
    $stones=flood($b,$n,$p,$b[$p]);
    $liberties=[];
    foreach($stones as $q=>$_)foreach(adjacent($q,$n) as $t)if($b[$t]==='.')$liberties[$t]=true;
    return ['color'=>$b[$p],'first'=>min(array_keys($stones)),'stones'=>$stones,'liberties'=>$liberties];
}
function groups(string $b,int $n,string $color=''): array {
    $seen=[];
    $out=[];
    for($p=0;$p<strlen($b);$p++)if($b[$p]!=='.'&&!isset($seen[$p])&&($color===''||$color===$b[$p])){
        $g=group($b,$n,$p);
        $seen+=$g['stones'];
        $out[]=$g;
    }
    return $out;
}
function placement(string $b,int $n,string $c,int $p): array {
    if($b[$p]!=='.')return [$b,0,'occupied'];
    $next=$b;
    $next[$p]=$c;
    $captured=0;
    $seen=[];
    foreach(adjacent($p,$n) as $q)if($next[$q]===other($c)&&!isset($seen[$q])){
        $g=group($next,$n,$q);
        $seen+=$g['stones'];
        if(!$g['liberties']){
            foreach($g['stones'] as $t=>$_)$next[$t]='.';
            $captured+=count($g['stones']);
        }
    }
    return [$next,$captured,group($next,$n,$p)['liberties']?'':'suicide'];
}
function regions(string $b,int $n): array {
    $out=[];
    $seen=[];
    for($p=0;$p<strlen($b);$p++)if($b[$p]==='.'&&!isset($seen[$p])){
        $points=flood($b,$n,$p,'.');
        $seen+=$points;
        $border=[];
        foreach($points as $q=>$_)foreach(adjacent($q,$n) as $t)if($b[$t]!=='.')$border[$b[$t]]=true;
        $out[]=[$p,$points,count($border)===1?array_key_first($border):'neutral'];
    }
    return $out;
}
function safeGroups(string $b,int $n,string $c): array {
    $own=groups($b,$n,$c);
    $touch=[];
    $vital=[];
    $seen=[];
    for($p=0;$p<strlen($b);$p++)if($b[$p]!==$c&&!isset($seen[$p])){
        $area=flood($b,$n,$p,'.'.other($c));
        $seen+=$area;
        $empty=array_filter($area,fn($_,$q)=>$b[$q]==='.',ARRAY_FILTER_USE_BOTH);
        $t=[];
        $v=[];
        foreach($own as $i=>$g){
            $touches=false;
            foreach($area as $q=>$_)foreach(adjacent($q,$n) as $a)if(isset($g['stones'][$a]))$touches=true;
            if($touches)$t[$i]=true;
            if(!array_diff_key($empty,$g['liberties']))$v[$i]=true;
        }
        $touch[]=$t;
        $vital[]=$v;
    }
    $s=array_fill_keys(array_keys($own),true);
    $a=array_fill_keys(array_keys($touch),true);
    while(true){
        $count=count($s)+count($a);
        foreach(array_keys($s) as $i){
            $nVital=0;
            foreach($a as $j=>$_)if(isset($vital[$j][$i]))$nVital++;
            if($nVital<2)unset($s[$i]);
        }
        foreach(array_keys($a) as $j)if(array_diff_key($touch[$j],$s))unset($a[$j]);
        if($count===count($s)+count($a))break;
    }
    return array_values(array_intersect_key($own,$s));
}
function ladder(string $b,int $n,int $p): array {
    $defender=$b[$p];
    $attacker=other($defender);
    $memo=[];
    $read=function(string $current,int $depth,bool $defending) use (&$read,&$memo,$defender,$attacker,$n,$p): array {
        if($depth>=40)return [$defending,-1];
        $key=$current.':'.$depth.':'.(int)$defending;
        if(isset($memo[$key]))return $memo[$key];
        $g=group($current,$n,$p);
        $candidates=$g['liberties'];
        $seen=[];
        if($defending)foreach($g['stones'] as $q=>$_)foreach(adjacent($q,$n) as $t)if($current[$t]===$attacker&&!isset($seen[$t])){
            $e=group($current,$n,$t);
            $seen+=$e['stones'];
            if(count($e['liberties'])===1)$candidates+=$e['liberties'];
        }
        foreach(ordered($candidates) as $q){
            [$next,$_,$reason]=placement($current,$n,$defending?$defender:$attacker,$q);
            if($reason!=='')continue;
            if($defending){
                $m=count(group($next,$n,$p)['liberties']);
                $success=$m>=3||($m===2&&!$read($next,$depth+1,false)[0]);
            }else $success=!$read($next,$depth+1,true)[0];
            if($success)return $memo[$key]=[true,$q];
        }
        return $memo[$key]=[false,-1];
    };
    $count=count(group($b,$n,$p)['liberties']);
    if($count>=3)return ['safe',-1];
    [$success,$move]=$read($b,0,$count===1);
    return [($count===1?$success:!$success)?'escapes':'captured',$move];
}
final class Game {
    private int $n=19,$komi=13,$passes=0;
    private string $board='',$turn='B';
    private array $captures=['B'=>0,'W'=>0],$handicap=[],$history=[],$positions=[],$dead=[];
    private bool $over=false,$superko=false;
    public function __construct(){
        $this->reset(19,13);
    }
    private function emit(string|int ...$a): void {
        echo implode(' ',$a),"\n";
    }
    private function reset(int $n,int $k): void {
        $this->n=$n;
        $this->komi=$k;
        $this->board=str_repeat('.',$n*$n);
        $this->turn='B';
        $this->captures=['B'=>0,'W'=>0];
        $this->passes=0;
        $this->over=false;
        $this->handicap=[];
        $this->history=[];
        $this->positions=[$this->board];
        $this->dead=[];
    }
    private function point(string $s): int {
        if(!preg_match('~\A[A-HJ-T](?:[1-9]|1[0-9])\z~',$s))return -1;
        $c=strpos(COLUMNS,$s[0]);
        $r=(int)substr($s,1);
        return $c<$this->n&&$r<=$this->n?($r-1)*$this->n+$c:-1;
    }
    private function name(int $p): string {
        return COLUMNS[$p%$this->n].(intdiv($p,$this->n)+1);
    }
    private function sgf(int $p): string {
        return chr(97+$p%$this->n).chr(97+$this->n-1-intdiv($p,$this->n));
    }
    private function check(string $c,int $p): array {
        [$b,$captured,$reason]=placement($this->board,$this->n,$c,$p);
        if($reason===''&&count($this->positions)>=2&&$b===$this->positions[count($this->positions)-2])$reason='ko';
        if($reason===''&&$this->superko&&in_array($b,$this->positions,true))$reason='superko';
        return [$b,$captured,$reason];
    }
    private function move(string $c,int $p,?array $checked=null): int {
        $before=[$this->board,$this->turn,$this->captures,$this->passes,$this->over];
        $captured=0;
        if($p<0){
            $this->passes++;
            if($this->passes===2)$this->over=true;
        }else{
            [$this->board,$captured,$_]= $checked??$this->check($c,$p);
            $this->captures[$c]+=$captured;
            $this->passes=0;
        }
        $this->turn=other($c);
        $this->history[]=[$c,$p,$captured,$before];
        $this->positions[]=$this->board;
        $this->dead=[];
        return $captured;
    }
    private function clean(): string {
        $b=$this->board;
        foreach($this->dead as $p=>$_)$b[$p]='.';
        return $b;
    }
    private function show(bool $map=false): void {
        $b=$map?$this->clean():$this->board;
        $chars=$b;
        $stars=[];
        foreach(HANDICAP[$this->n] as $i=>$s)if($this->n===19||$i<4||$i===8)$stars[$this->point($s)]=true;
        if($map)foreach(regions($b,$this->n) as [$_,$points,$owner])foreach($points as $p=>$_)$chars[$p]=$owner==='B'?'x':($owner==='W'?'o':'.');
        for($p=0;$p<strlen($b);$p++)if($b[$p]!=='.'){
            $c=$b[$p]==='B'?'X':'O';
            $chars[$p]=!$map&&isset($this->dead[$p])?strtolower($c):$c;
        }
        elseif(!$map)$chars[$p]=isset($stars[$p])?'+':'.';
        $header='   '.implode(' ',str_split(substr(COLUMNS,0,$this->n)));
        $this->emit($header);
        for($r=$this->n;$r>=1;$r--)$this->emit(str_pad((string)$r,2,' ',STR_PAD_LEFT),implode(' ',str_split(substr($chars,($r-1)*$this->n,$this->n))),$r);
        $this->emit($header);
    }
    private function score(string $method): void {
        $b=$this->clean();
        $territory=['B'=>0,'W'=>0];
        $total=[];
        foreach(regions($b,$this->n) as [$_,$points,$owner])if(isset($territory[$owner]))$territory[$owner]+=count($points);
        foreach(['B','W'] as $c){
            if($method==='AREA'){
                $stones=substr_count($b,$c);
                $total[$c]=2*($stones+$territory[$c])+($c==='W'?$this->komi:0);
                $fields=[$c,'stones',$stones,'territory',$territory[$c]];
            }else{
                $prisoners=$this->captures[$c];
                foreach($this->dead as $p=>$_)if($this->board[$p]===other($c))$prisoners++;
                $total[$c]=2*($territory[$c]+$prisoners)+($c==='W'?$this->komi:0);
                $fields=[$c,'territory',$territory[$c],'prisoners',$prisoners];
            }
            if($c==='W')array_push($fields,'komi',halfText($this->komi));
            array_push($fields,'total',halfText($total[$c]));
            $this->emit(...$fields);
        }
        $d=$total['B']-$total['W'];
        $this->emit('result',$d>0?'B+'.halfText($d):($d<0?'W+'.halfText(-$d):'Draw'));
    }
    public function execute(string $line): void {
        $words=explode(' ',$line);
        $c=array_shift($words);
        $a=$words;
        if(!isset(ARITY[$c])){
            $this->emit('ERROR unknown command');
            return;
        }
        if(count($a)!==ARITY[$c]){
            $this->emit('ERROR bad arguments');
            return;
        }
        $valid=match($c){
            'BOARD'=>in_array($a[0],['9','13','19'],true)&&parseKomi($a[1])!==null,'KOMI'=>parseKomi($a[0])!==null,'SUPERKO'=>in_array($a[0],['ON','OFF'],true),'HANDICAP'=>(bool)preg_match('~\A[2-9]\z~',$a[0]),'PLAY','PASS','LEGAL','EYES','SAFE'=>in_array($a[0],['B','W'],true),'SCORE'=>in_array($a[0],['AREA','TERRITORY'],true),default=>true
        };
        if(!$valid){
            $this->emit('ERROR bad arguments');
            return;
        }
        $p=-1;
        if(in_array($c,['PLAY','GROUP','LADDER','DEAD'],true)){
            $p=$this->point($a[$c==='PLAY'?1:0]);
            if($p<0){
                $this->emit('ERROR bad point');
                return;
            }
        }
        $records=[];
        if($c==='REPLAY'){
            if(!preg_match('~\A(?:;[BW]\[[a-z]{0,2}\])+\z~',$a[0])){
                $this->emit('ERROR bad sequence');
                return;
            }
            preg_match_all('~;([BW])\[([a-z]*)\]~',$a[0],$records,PREG_SET_ORDER);
            foreach($records as $r){
                $s=$r[2];
                if($s!==''&&(strlen($s)!==2||ord($s[0])-97>=$this->n||ord($s[1])-97>=$this->n)){
                    $this->emit('ERROR bad sequence');
                    return;
                }
            }
        }
        if(in_array($c,['PLAY','PASS','REPLAY'],true)&&$this->over){
            $this->emit('ERROR game over');
            return;
        }
        switch($c){
            case 'BOARD':$this->reset((int)$a[0],parseKomi($a[1]));
            $this->emit('board',$this->n,'komi',halfText($this->komi));
            break;
            case 'KOMI':$this->komi=parseKomi($a[0]);
            $this->emit('komi',halfText($this->komi));
            break;
            case 'SUPERKO':$this->superko=$a[0]==='ON';
            $this->emit('superko',$this->superko?'on':'off');
            break;
            case 'HANDICAP':if($this->history||strpbrk($this->board,'BW')!==false){
                $this->emit('ERROR handicap not allowed');
                break;
            }
            $k=(int)$a[0];
            $ix=$k===5?[0,1,2,3,8]:($k===7?[0,1,2,3,4,5,8]:range(0,$k-1));
            $this->handicap=array_map(fn($i)=>$this->point(HANDICAP[$this->n][$i]),$ix);
            foreach($this->handicap as $q)$this->board[$q]='B';
            $this->turn='W';
            $this->positions=[$this->board];
            $this->dead=[];
            $this->emit('handicap',$k,...array_map(fn($q)=>$this->name($q),$this->handicap));
            break;
            case 'PLAY':$r=$this->check($a[0],$p);
            $reason=$a[0]!==$this->turn?'turn':$r[2];
            if($reason!=='')$this->emit('ILLEGAL',$a[0],$a[1],$reason);
            else{
                $captured=$this->move($a[0],$p,$r);
                $this->emit($a[0],$a[1],...($captured?['captures',$captured]:[]));
            }
            break;
            case 'PASS':if($a[0]!==$this->turn)$this->emit('ILLEGAL',$a[0],'pass turn');
            else{
                $this->move($a[0],-1);
                $this->emit($a[0],'pass');
                if($this->over)$this->emit('game over');
            }
            break;
            case 'REPLAY':$count=0;
            $stop=[];
            foreach($records as $r){
                $color=$r[1];
                $s=$r[2];
                $q=$s===''?-1:($this->n-1-(ord($s[1])-97))*$this->n+ord($s[0])-97;
                $next=$q<0?null:$this->check($color,$q);
                $reason=$this->over?'game over':($color!==$this->turn?'turn':($next[2]??''));
                if($reason!==''){
                    $stop=['stopped',$color,$q<0?'pass':$this->name($q),$reason];
                    break;
                }
                $this->move($color,$q,$next);
                $count++;
            }
            $this->emit('replay',$count,'moves',...$stop);
            if($this->over)$this->emit('game over');
            break;
            case 'UNDO':if(!$this->history){
                $this->emit('ERROR nothing to undo');
                break;
            }
            [$color,$q,$_,$before]=array_pop($this->history);
            [$this->board,$this->turn,$this->captures,$this->passes,$this->over]=$before;
            array_pop($this->positions);
            $this->dead=[];
            $this->emit('undo',$color,$q<0?'pass':$this->name($q));
            break;
            case 'SHOW':$this->show();
            break;
            case 'MAP':$this->show(true);
            break;
            case 'STATUS':$this->emit('size',$this->n,'komi',halfText($this->komi),'handicap',count($this->handicap),'superko',$this->superko?'on':'off');
            $this->emit('moves',count($this->history),...($this->over?['game over']:['next',$this->turn,'passes',$this->passes]));
            break;
            case 'CAPTURES':$this->emit('captures B',$this->captures['B'],'W',$this->captures['W']);
            break;
            case 'HISTORY':$this->emit('history',count($this->history));
            foreach($this->history as $i=>[$color,$q,$captured,$_])$this->emit($i+1,$color,$q<0?'pass':$this->name($q),...($captured?['captures',$captured]:[]));
            break;
            case 'MOVES':$text='(;GM[1]FF[4]SZ['.$this->n.']KM['.halfText($this->komi).']';
            if($this->handicap){
                $text.='HA['.count($this->handicap).']AB';
                foreach($this->handicap as $q)$text.='['.$this->sgf($q).']';
            }
            foreach($this->history as [$color,$q,$_,$_])$text.=';'.$color.'['.($q<0?'':$this->sgf($q)).']';
            $this->emit($text.')');
            break;
            case 'GROUP':case 'DEAD':case 'LADDER':if($this->board[$p]==='.'){
                $this->emit('ERROR no stone');
                break;
            }
            $g=group($this->board,$this->n,$p);
            if($c==='GROUP'){
                $this->emit('group',$g['color'],$this->name($g['first']),'size',count($g['stones']),'liberties',count($g['liberties']));
                $this->emit('stones',...array_map(fn($q)=>$this->name($q),ordered($g['stones'])));
                $this->emit('liberties',...array_map(fn($q)=>$this->name($q),ordered($g['liberties'])));
            }
            elseif($c==='DEAD'){
                $alive=isset($this->dead[$p]);
                if($alive)$this->dead=array_diff_key($this->dead,$g['stones']);
                else $this->dead+=$g['stones'];
                $this->emit($alive?'alive':'dead',$g['color'],$this->name($g['first']),'size',count($g['stones']));
            }else{
                [$status,$q]=ladder($this->board,$this->n,$p);
                $this->emit('ladder',$a[0],$status,...($q<0?[]:[$this->name($q)]));
            }
            break;
            case 'GROUPS':$gs=groups($this->board,$this->n);
            $this->emit('groups',count($gs));
            foreach($gs as $g)$this->emit($g['color'],$this->name($g['first']),'size',count($g['stones']),'liberties',count($g['liberties']),...(isset($this->dead[$g['first']])?['dead']:[]));
            break;
            case 'ATARI':$gs=array_filter(groups($this->board,$this->n),fn($g)=>count($g['liberties'])===1);
            if(!$gs)$this->emit('atari none');
            foreach($gs as $g)$this->emit('atari',$g['color'],$this->name($g['first']),'size',count($g['stones']),'at',$this->name(array_key_first($g['liberties'])));
            break;
            case 'LEGAL':$rejected=[];
            $count=0;
            for($q=0;$q<strlen($this->board);$q++)if($this->board[$q]==='.'){
                $why=$this->check($a[0],$q)[2];
                if($why==='')$count++;
                else $rejected[]=[$this->name($q),$why];
            }
            $this->emit('legal',$a[0],$count);
            foreach($rejected as $r)$this->emit(...$r);
            break;
            case 'EYES':$found=[];
            for($q=0;$q<strlen($this->board);$q++)if($this->board[$q]==='.'){
                $ns=adjacent($q,$this->n);
                if(count(array_filter($ns,fn($t)=>$this->board[$t]===$a[0]))===count($ns)){
                    $enemies=count(array_filter(adjacent($q,$this->n,true),fn($t)=>$this->board[$t]===other($a[0])));
                    $found[]=[$this->name($q),$enemies<=(count($ns)===4?1:0)?'real':'false'];
                }
            }
            $this->emit('eyes',$a[0],count($found));
            foreach($found as $r)$this->emit(...$r);
            break;
            case 'SAFE':$gs=safeGroups($this->board,$this->n,$a[0]);
            $this->emit('safe',$a[0],count($gs));
            foreach($gs as $g)$this->emit($this->name($g['first']),'size',count($g['stones']));
            break;
            case 'REGIONS':$rs=regions($this->clean(),$this->n);
            $this->emit('regions',count($rs));
            foreach($rs as [$first,$points,$owner])$this->emit($this->name($first),'size',count($points),$owner);
            break;
            case 'SCORE':$this->score($a[0]);
            break;
        }
    }
}
$game=new Game();
$count=(int)trim(fgets(STDIN));
for($i=0;$i<$count;$i++)$game->execute(rtrim(fgets(STDIN),"\r\n"));
