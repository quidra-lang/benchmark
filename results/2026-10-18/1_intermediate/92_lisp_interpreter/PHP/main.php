<?php
final class Atom { public function __construct(public string $name) {} }
final class Pair { public function __construct(public mixed $car, public mixed $cdr) {} }
final class Marker { public function __construct(public string $kind) {} }
$nil=new Marker('nil'); $void=new Marker('void'); $uninit=new Marker('uninitialized'); $symbols=[];
function sym(string $s): Atom { global $symbols; return $symbols[$s]??=new Atom($s); }
function makeList(array $a,mixed $tail=null): mixed { global $nil; if($tail===null)$tail=$nil;for($i=count($a)-1;$i>=0;$i--)$tail=new Pair($a[$i],$tail);return $tail; }
function items(mixed $v): ?array { global $nil;$a=[];while($v instanceof Pair){$a[]=$v->car;$v=$v->cdr;}return $v===$nil?$a:null; }
function rep(mixed $v,bool $quoted=true): string {
    global $nil,$void;if($v===$nil)return '()';if($v===$void)return '#<void>';
    if(is_bool($v))return $v?'#t':'#f';if(is_int($v))return (string)$v;
    if(is_string($v))return $quoted?'"'.str_replace(["\\",'"',"\n"],["\\\\",'\\"','\\n'],$v).'"':$v;
    if($v instanceof Atom)return $v->name;if($v instanceof Procedure)return $v->name!==null?'#<procedure '.$v->name.'>':'#<procedure>';
    $a=[];while($v instanceof Pair){$a[]=rep($v->car,$quoted);$v=$v->cdr;}if($v!==$nil){$a[]='.';$a[]=rep($v,$quoted);}return '('.implode(' ',$a).')';
}
function same(mixed $a,mixed $b,bool $deep=false): bool { if($deep&&$a instanceof Pair&&$b instanceof Pair)return same($a->car,$b->car,true)&&same($a->cdr,$b->cdr,true);return $a===$b; }
final class Env {
    public array $frame=[];
    public function __construct(public ?Env $parent=null) {}
    public function find(string $n): Env { for($e=$this;$e!==null;$e=$e->parent)if(array_key_exists($n,$e->frame))return $e;throw new Exception('unbound variable: '.$n); }
    public function get(string $n): mixed { global $uninit;$v=$this->find($n)->frame[$n];if($v===$uninit)throw new Exception('uninitialized variable: '.$n);return $v; }
}
final class Procedure {
    public function __construct(public ?string $name, public int $minimum, public bool|string $rest, public ?Closure $fn=null, public array $params=[],public array $body=[],public ?Env $env=null) {}
    public function call(array $a): mixed {
        if(count($a)<$this->minimum||($this->rest===false&&count($a)!==$this->minimum))throw new Exception(($this->name??'lambda').': wrong number of arguments (expected '.($this->rest!==false?'at least ':'').$this->minimum.', got '.count($a).')');
        if($this->fn!==null)return ($this->fn)($a);$e=new Env($this->env);foreach($this->params as $i=>$n)$e->frame[$n]=$a[$i];if(is_string($this->rest))$e->frame[$this->rest]=makeList(array_slice($a,$this->minimum));return evalBody($this->body,$e);
    }
}
function parameters(mixed $v): ?array {
    global $nil;$names=[];while($v instanceof Pair){if(!($v->car instanceof Atom))return null;$names[]=$v->car->name;$v=$v->cdr;}
    if($v!==$nil&&!($v instanceof Atom))return null;$rest=$v instanceof Atom?$v->name:false;$all=$rest===false?$names:[...$names,$rest];return count(array_unique($all))===count($all)?[$names,$rest]:null;
}
function bindings(mixed $v,bool $unique): ?array {
    $a=items($v);if($a===null)return null;$bs=[];$seen=[];foreach($a as $x){$z=items($x);if($z===null||count($z)!==2||!($z[0] instanceof Atom))return null;$n=$z[0]->name;if($unique&&isset($seen[$n]))return null;$seen[$n]=true;$bs[]=[$n,$z[1]];}return $bs;
}
function shape(bool $ok,mixed $x): void { if(!$ok)throw new Exception('bad syntax: '.rep($x)); }
function compound(array $p,array $b,Env $e,?string $name=null): Procedure { return new Procedure($name,count($p[0]),$p[1],null,$p[0],$b,$e); }
function evalBody(array $a,Env $e): mixed { global $void;$v=$void;foreach($a as $x)$v=evaluate($x,$e);return $v; }
function evaluate(mixed $x,Env $e): mixed {
    global $nil,$void,$uninit;if($x instanceof Atom)return $e->get($x->name);if(!($x instanceof Pair)){shape($x!==$nil,$x);return $x;}
    $a=items($x);shape($a!==null,$x);$n=count($a);$h=$a[0] instanceof Atom?$a[0]->name:'';
    switch($h){
        case 'quote':shape($n===2,$x);return $a[1];
        case 'if':shape($n===3||$n===4,$x);return evaluate($a[1],$e)!==false?evaluate($a[2],$e):($n===4?evaluate($a[3],$e):$void);
        case 'begin':return evalBody(array_slice($a,1),$e);
        case 'lambda':$p=$n>=3?parameters($a[1]):null;shape($p!==null,$x);return compound($p,array_slice($a,2),$e);
        case 'define':
            if(($a[1]??null) instanceof Atom){shape($n===3,$x);$v=evaluate($a[2],$e);if($v instanceof Procedure&&$v->fn===null&&$v->name===null)$v->name=$a[1]->name;$e->frame[$a[1]->name]=$v;}
            else{$t=$a[1]??null;$p=$n>=3&&$t instanceof Pair&&$t->car instanceof Atom?parameters($t->cdr):null;shape($p!==null,$x);$e->frame[$t->car->name]=compound($p,array_slice($a,2),$e,$t->car->name);}return $void;
        case 'set!':shape($n===3&&$a[1] instanceof Atom,$x);$v=evaluate($a[2],$e);$e->find($a[1]->name)->frame[$a[1]->name]=$v;return $void;
        case 'let':case 'let*':case 'letrec':
            $named=$h==='let'&&($a[1]??null) instanceof Atom;$at=$named?2:1;$bs=$n>=$at+2?bindings($a[$at],$h!=='let*'):null;shape($bs!==null,$x);$scope=new Env($e);
            if($h==='let*'){$scope=$bs?$e:$scope;foreach($bs as [$name,$expr]){$v=evaluate($expr,$scope);$scope=new Env($scope);$scope->frame[$name]=$v;}}
            elseif($h==='letrec'){foreach($bs as [$name])$scope->frame[$name]=$uninit;foreach($bs as [$name,$expr])$scope->frame[$name]=evaluate($expr,$scope);}
            else{$vs=[];foreach($bs as $b)$vs[]=evaluate($b[1],$e);if($named){$p=compound([array_column($bs,0),false],array_slice($a,3),$scope,$a[1]->name);$scope->frame[$a[1]->name]=$p;return $p->call($vs);}foreach($bs as $i=>$b)$scope->frame[$b[0]]=$vs[$i];}return evalBody(array_slice($a,$at+1),$scope);
        case 'cond':
            $cs=array_map('items',array_slice($a,1));foreach($cs as $i=>$c)shape($c!==null&&count($c)>0&&(!($c[0] instanceof Atom)||$c[0]->name!=='else'||(count($c)>=2&&$i===count($cs)-1)),$x);
            foreach($cs as $c){if($c[0]===sym('else'))return evalBody(array_slice($c,1),$e);$v=evaluate($c[0],$e);if($v!==false)return count($c)===1?$v:evalBody(array_slice($c,1),$e);}return $void;
        case 'and':$v=true;foreach(array_slice($a,1) as $z){$v=evaluate($z,$e);if($v===false)break;}return $v;
        case 'or':foreach(array_slice($a,1) as $z){$v=evaluate($z,$e);if($v!==false)return $v;}return false;
        case 'when':case 'unless':shape($n>=3,$x);return (evaluate($a[1],$e)!==false)===($h==='when')?evalBody(array_slice($a,2),$e):$void;
    }
    $f=evaluate($a[0],$e);$args=[];foreach(array_slice($a,1) as $z)$args[]=evaluate($z,$e);if(!($f instanceof Procedure))throw new Exception('not a procedure: '.rep($f));return $f->call($args);
}
$mid=false;
function writeText(string $s): void { global $mid;echo $s;if($s!=='')$mid=!str_ends_with($s,"\n"); }
function writeLine(string $s): void { global $mid;if($mid)writeText("\n");writeText($s."\n"); }
function expect(string $n,mixed $v,string $kind): mixed {
    $ok=match($kind){'integer'=>is_int($v),'string'=>is_string($v),'pair'=>$v instanceof Pair,'procedure'=>$v instanceof Procedure,'list'=>items($v)!==null};if(!$ok)throw new Exception("$n: expected $kind, got ".rep($v));return $v;
}
function globalEnv(): Env {
    global $nil,$void;$e=new Env();$add=function($n,$m,$r,$fn)use($e){$e->frame[$n]=new Procedure($n,$m,$r,$fn);};
    foreach(['+','*','-','quotient','remainder','modulo','abs','min','max','gcd','=','<','>','<=','>='] as $name){
        $fixed=in_array($name,['quotient','remainder','modulo'],true)?2:($name==='abs'?1:null);
        $add($name,$fixed??(in_array($name,['+','*','gcd'],true)?0:1),$fixed===null,function($a)use($name){
            foreach($a as $v)expect($name,$v,'integer');
            switch($name){case '+':return array_sum($a);case '*':return array_product($a);case '-':return count($a)===1?-$a[0]:$a[0]-array_sum(array_slice($a,1));case 'abs':return abs($a[0]);case 'min':return min($a);case 'max':return max($a);
                case 'gcd':$g=0;foreach($a as $v){$v=abs($v);while($v!==0){$t=$g%$v;$g=$v;$v=$t;}}return $g;
                case 'quotient':case 'remainder':case 'modulo':if($a[1]===0)throw new Exception($name.': division by zero');$q=intdiv($a[0],$a[1]);$r=$a[0]-$a[1]*$q;if($name==='quotient')return $q;if($name==='modulo'&&$r!==0&&(($r<0)!==($a[1]<0)))$r+=$a[1];return $r;
            }
            for($i=1;$i<count($a);$i++)if(!match($name){'='=>$a[$i-1]===$a[$i],'<'=>$a[$i-1]<$a[$i],'>'=>$a[$i-1]>$a[$i],'<='=>$a[$i-1]<=$a[$i],'>='=>$a[$i-1]>=$a[$i]})return false;return true;
        });
    }
    $add('not',1,false,fn($a)=>$a[0]===false);$add('eq?',2,false,fn($a)=>same($a[0],$a[1]));$add('equal?',2,false,fn($a)=>same($a[0],$a[1],true));
    foreach(['null?','pair?','list?','number?','symbol?','procedure?'] as $name)$add($name,1,false,fn($a)=>match($name){'null?'=>$a[0]===$nil,'pair?'=>$a[0] instanceof Pair,'list?'=>items($a[0])!==null,'number?'=>is_int($a[0]),'symbol?'=>$a[0] instanceof Atom,'procedure?'=>$a[0] instanceof Procedure});
    $add('cons',2,false,fn($a)=>new Pair($a[0],$a[1]));$add('list',0,true,fn($a)=>makeList($a));
    foreach(['car','cdr','cadr'] as $name)$add($name,1,false,function($a)use($name){$p=expect($name,$a[0],'pair');return match($name){'car'=>$p->car,'cdr'=>$p->cdr,'cadr'=>expect($name,$p->cdr,'pair')->car};});
    foreach(['length','reverse','list-ref'] as $name)$add($name,$name==='list-ref'?2:1,false,function($a)use($name){$ls=items(expect($name,$a[0],'list'));if($name==='length')return count($ls);if($name==='reverse')return makeList(array_reverse($ls));$k=expect($name,$a[1],'integer');if($k<0||$k>=count($ls))throw new Exception('list-ref: index out of range: '.$k);return $ls[$k];});
    $add('append',0,true,function($a)use($nil){if(!$a)return $nil;$z=[];foreach(array_slice($a,0,-1) as $v)$z=[...$z,...items(expect('append',$v,'list'))];return makeList($z,$a[count($a)-1]);});
    foreach(['map','filter','fold-left','apply'] as $name)$add($name,$name==='fold-left'?3:2,$name!=='filter',function($a)use($name){$f=expect($name,$a[0],'procedure');if($name==='apply')return $f->call([...array_slice($a,1,-1),...items(expect($name,$a[count($a)-1],'list'))]);
        $ls=[];foreach(array_slice($a,$name==='fold-left'?2:1) as $v)$ls[]=items(expect($name,$v,'list'));$out=[];$acc=$a[1];$count=min(array_map('count',$ls));for($i=0;$i<$count;$i++){if($name==='filter'){if($f->call([$ls[0][$i]])!==false)$out[]=$ls[0][$i];}else{$z=[];foreach($ls as $l)$z[]=$l[$i];if($name==='map')$out[]=$f->call($z);else $acc=$f->call([$acc,...$z]);}}return $name==='fold-left'?$acc:makeList($out);
    });
    $add('string-append',0,true,fn($a)=>implode('',array_map(fn($v)=>expect('string-append',$v,'string'),$a)));
    $add('number->string',1,false,fn($a)=>(string)expect('number->string',$a[0],'integer'));
    $add('display',1,false,function($a)use($void){writeText(rep($a[0],false));return $void;});$add('newline',0,false,function($a)use($void){writeText("\n");return $void;});
    $add('error',1,true,function($a){throw new Exception(expect('error',$a[0],'string').implode('',array_map(fn($v)=>' '.rep($v),array_slice($a,1))));});return $e;
}
final class Reader {
    private int $row=0,$col=0;
    public function __construct(private array $lines) {}
    public function skip(): void {$this->row++;$this->col=0;}
    public function end(): bool {while($this->row<count($this->lines)){$s=$this->lines[$this->row];while(($s[$this->col]??null)===' ')$this->col++;if($this->col<strlen($s)&&$s[$this->col]!==';')return false;$this->skip();}return true;}
    private function token(): array {
        if($this->end())throw new Exception('unexpected end of input');$s=$this->lines[$this->row];$c=$s[$this->col++];if(str_contains("()'",$c))return [$c,null];
        if($c==='"'){$v='';while($this->col<strlen($s)){$c=$s[$this->col++];if($c==='"')return ['v',$v];if($c==="\\"){if($this->col===strlen($s))break;$c=$s[$this->col++];if(!in_array($c,['"',"\\",'n'],true))throw new Exception('bad escape');$v.=$c==='n'?"\n":$c;}else $v.=$c;}throw new Exception('unterminated string');}
        $start=$this->col-1;while($this->col<strlen($s)&&!str_contains(" ()'\";",$s[$this->col]))$this->col++;$a=substr($s,$start,$this->col-$start);if($a==='.')return ['.',null];if(preg_match('/^[+-]?[0-9]+$/D',$a))return ['v',(int)$a];if($a==='#t'||$a==='#f')return ['v',$a==='#t'];if($a[0]==='#')throw new Exception('bad token: '.$a);return ['v',sym($a)];
    }
    public function datum(?array $t=null): mixed {
        $t??=$this->token();if($t[0]==='v')return $t[1];if($t[0]==="'")return makeList([sym('quote'),$this->datum()]);if($t[0]!=='(')throw new Exception('unexpected '.$t[0]);$a=[];
        while(true){$t=$this->token();if($t[0]===')')return makeList($a);if($t[0]==='.'&&$a){$tail=$this->datum();if($this->token()[0]!==')')throw new Exception('expected )');return makeList($a,$tail);}$a[]=$this->datum($t);}
    }
}
$lines=[];while(($s=fgets(STDIN))!==false){$s=rtrim($s,"\r\n");if($s==='(exit)')break;$lines[]=$s;}$reader=new Reader($lines);$env=globalEnv();
while(!$reader->end()){try{$x=$reader->datum();}catch(Exception $err){writeLine('Error: read: '.$err->getMessage());if($err->getMessage()==='unexpected end of input')break;$reader->skip();continue;}try{$v=evaluate($x,$env);if($v!==$void)writeLine(rep($v));}catch(Exception $err){writeLine('Error: '.$err->getMessage());}}
if($mid)writeText("\n");
