<?php
declare(strict_types=1);
const POLICIES=['COST','NEAREST','ROUND','ETA'];
const CONFIG_KEYS=['FLOORS','CARS','CAPACITY','DOOR','START','POLICY','ZONES','PARK','PATIENCE','BYPASS','PERIOD','LIMIT','COMPARE'];
const ARG_COUNTS=['CALL'=>3,'CANCEL'=>1,'OUT'=>1,'IN'=>1,'HOLD'=>2,'FIRE'=>1,'RESET'=>0,'WHERE'=>1,'STATUS'=>0];
final class ConfigError extends RuntimeException {
}
function configCheck(bool $bad,string $message): void {
    if($bad) throw new ConfigError($message);
}
function joined(array $a): string {
    return $a===[]?'-':implode(',',$a);
}
function average(int $total,int $count): string {
    if($count===0) return '-';
    $n=intdiv($total*100,$count);
    return intdiv($n,100).'.'.str_pad((string)($n%100),2,'0',STR_PAD_LEFT);
}
function emit(mixed ...$parts): void {
    echo implode(' ',$parts),"\n";
}
function parseConfig(array $lines): array {
    $entries=[];
    foreach($lines as $words) {
        $k=array_shift($words);
        configCheck(!in_array($k,CONFIG_KEYS,true),"unknown key $k");
        configCheck(isset($entries[$k]),"duplicate key $k");
        $entries[$k]=$words;
    }
    foreach(array_slice(CONFIG_KEYS,0,5) as $k) configCheck(!isset($entries[$k]),"missing key $k");
    $c=['POLICY'=>'COST','BYPASS'=>100,'LIMIT'=>1000,'COMPARE'=>[]];
    $ranges=['FLOORS'=>[2,50],'CARS'=>[1,8],'CAPACITY'=>[1,20],'DOOR'=>[1,9],'PATIENCE'=>[1,1000],'BYPASS'=>[50,100],'PERIOD'=>[1,1000],'LIMIT'=>[1,5000]];
    foreach(CONFIG_KEYS as $k) {
        if(!isset($entries[$k])) continue;
        $vs=$entries[$k];
        $n=count($vs);
        $e=$c['CARS']??0;
        $f=$c['FLOORS']??0;
        $countValid=match($k) {
            'START','ZONES'=>$n===$e,'PARK'=>$n===$e+1,'COMPARE'=>$n>=1&&$n<=4,default=>$n===1
        };
        configCheck(!$countValid,"wrong number of values for $k");
        $valid=true;
        if(isset($ranges[$k])) {
            $v=(int)$vs[0];
            [$lo,$hi]=$ranges[$k];
            $valid=$v>=$lo&&$v<=$hi;
            $c[$k]=$v;
        } elseif($k==='POLICY') {
            $valid=in_array($vs[0],POLICIES,true);
            $c[$k]=$vs[0];
        } elseif($k==='COMPARE') {
            $valid=count(array_unique($vs))===count($vs);
            foreach($vs as $v) $valid=$valid&&in_array($v,POLICIES,true);
            $c[$k]=$vs;
        } elseif($k==='ZONES') {
            $zs=[];
            foreach($vs as $v) {
                [$lo,$hi]=array_map('intval',explode(':',$v));
                $valid=$valid&&1<=$lo&&$lo<$hi&&$hi<=$f;
                $zs[]=[$lo,$hi];
            }
            $c[$k]=$zs;
        } else {
            $ns=array_map('intval',$vs);
            foreach($ns as $i=>$v) $valid=$valid&&($k==='PARK'&&$i===0?$v>=0&&$v<=100:$v>=1&&$v<=$f);
            $c[$k]=$ns;
        }
        configCheck(!$valid,"bad value for $k");
    }
    $c['ZONES']??=array_fill(0,$c['CARS'],[1,$c['FLOORS']]);
    for($i=0;$i<$c['CARS'];$i++) {
        [$lo,$hi]=$c['ZONES'][$i];
        $s=$c['START'][$i];
        configCheck($s<$lo||$s>$hi,'car '.($i+1).' starts outside its zone');
        if(isset($c['PARK'])) {
            $h=$c['PARK'][$i+1];
            configCheck($h<$lo||$h>$hi,'car '.($i+1).' home outside its zone');
        }
    }
    return $c;
}
function validateEvents(array $c,array $lines): array {
    $accepted=[];
    $last=$groups=0;
    $out=[];
    $fire=false;
    foreach($lines as [$line,$words]) {
        $time=(int)$words[0];
        $cmd=$words[1];
        $args=array_slice($words,2);
        $v=array_map('intval',$args);
        $error=null;
        if(!isset(ARG_COUNTS[$cmd])) $error="unknown command $cmd";
        elseif(count($args)!==ARG_COUNTS[$cmd]) $error="wrong number of arguments for $cmd";
        elseif($time<$last) $error='time goes backwards';
        else switch($cmd) {
            case 'CALL':
                [$a,$b,$n]=$v;
                $serves=false;
                foreach($c['ZONES'] as [$lo,$hi]) if($lo<=$a&&$a<=$hi&&$lo<=$b&&$b<=$hi) $serves=true;
                $error=$a<1||$a>$c['FLOORS']||$b<1||$b>$c['FLOORS']?'bad floor':($a===$b?'same floor':($n<1||$n>99?'bad count':(!$serves?"no car serves $a->$b":($fire?'fire service active':null))));
                break;
            case 'CANCEL':
            case 'WHERE':
                if($v[0]<1||$v[0]>$groups) $error='unknown group';
                break;
            case 'OUT':
            case 'IN':
                $e=$v[0];
                $error=$e<1||$e>$c['CARS']?'bad car':($cmd==='OUT'&&isset($out[$e])?"car $e already out":($cmd==='IN'&&!isset($out[$e])?"car $e already in":null));
                break;
            case 'HOLD':
                $error=$v[0]<1||$v[0]>$c['CARS']?'bad car':($v[1]<1||$v[1]>9?'bad ticks':null);
                break;
            case 'FIRE':
                $error=$v[0]<1||$v[0]>$c['FLOORS']?'bad floor':($fire?'fire already active':null);
                break;
            case 'RESET':
                if(!$fire) $error='fire not active';
                break;
        }
        if($error!==null) {
            emit("line $line: $error");
            continue;
        }
        $accepted[]=[$time,$cmd,$v];
        $last=$time;
        if($cmd==='CALL') $groups++;
        elseif($cmd==='OUT') $out[$v[0]]=true;
        elseif($cmd==='IN') unset($out[$v[0]]);
        elseif($cmd==='FIRE') $fire=true;
        elseif($cmd==='RESET') $fire=false;
    }
    return $accepted;
}
final class Group {
    public int $waiting,$boarded=0,$delivered=0,$lost=0,$lastBoard=0,$lastAlight=0,$waitTotal=0,$travelTotal=0;
    public ?Car $car=null;
    public array $cars=[];
    public function __construct(public int $number,public int $a,public int $b,public int $count,public int $time) {
        $this->waiting=$count;
    }
    public function label(): string {
        return 'G'.$this->number;
    }
    public function direction(): int {
        return $this->b<=>$this->a;
    }
}
final readonly class Passenger {
    public function __construct(public Group $group,public int $count,public int $boardTime) {
    }
}
final class Car {
    public int $direction=0,$door=0,$idle=0,$distance=0,$stops=0,$boarded=0,$busy=0,$energy=0;
    public array $passengers=[],$calls=[];
    public bool $service=true;
    public function __construct(public int $number,public int $floor,public array $zone,public ?int $home) {
    }
    public function label(): string {
        return 'E'.$this->number;
    }
    public function load(): int {
        return array_sum(array_map(fn(Passenger $p)=>$p->count,$this->passengers));
    }
    public function targets(): array {
        return array_values(array_unique(array_merge(array_map(fn(Passenger $p)=>$p->group->b,$this->passengers),array_map(fn(Group $g)=>$g->a,$this->calls))));
    }
    public function serves(Group $g): bool {
        return $this->zone[0]<=$g->a&&$g->a<=$this->zone[1]&&$this->zone[0]<=$g->b&&$g->b<=$this->zone[1];
    }
}
function removeObject(array &$list,object $o): void {
    foreach($list as $i=>$v) if($v===$o) {
        array_splice($list,$i,1);
        return;
    }
}
final class Simulation {
    public array $cars=[],$groups=[];
    public int $time=0,$delivered=0,$waitTotal=0,$travelTotal=0;
    public string $status='';
    private array $pending=[];
    private ?int $fire=null;
    private int $round=0,$maxWait=0,$abandoned=0,$evacuated=0;
    public function __construct(private array $c,private array $events,public string $policy,private bool $logging) {
        for($i=0;$i<$c['CARS'];$i++) $this->cars[]=new Car($i+1,$c['START'][$i],$c['ZONES'][$i],$c['PARK'][$i+1]??null);
        $this->run();
    }
    private function log(mixed ...$parts): void {
        if($this->logging) emit($this->time,...$parts);
    }
    private function bypass(Car $car): bool {
        return $car->load()*100 >= $this->c['CAPACITY']*$this->c['BYPASS'];
    }
    private function cost(Car $car,Group $g): int {
        $f=$car->floor;
        $d=$car->direction;
        $x=$g->a;
        if($this->policy==='NEAREST'||$d===0) return abs($f-$x);
        $ts=$car->targets();
        $via=0;
        if($g->direction()===$d&&($x-$f)*$d>=0) {
            $distance=abs($x-$f);
            foreach($ts as $y) if(($y-$f)*$d>0&&($x-$y)*$d>0) $via++;
        } else {
            $turns=[...$ts,$f];
            $m=$d>0?max($turns):min($turns);
            $distance=abs($f-$m)+abs($m-$x);
            foreach($ts as $y) if(($y-$f)*$d>0) $via++;
        }
        return $distance+($this->policy==='ETA'?$this->c['DOOR']*$via+$car->door:0);
    }
    private function assign(Group $g,?Car $excluded=null): bool {
        $candidates=array_values(array_filter($this->cars,fn(Car $car)=>$car->service&&$car!==$excluded&&$car->serves($g)));
        if($candidates===[]) return false;
        if($this->policy==='ROUND') {
            $chosen=$candidates[0];
            foreach($candidates as $car) if($car->number>$this->round) {
                $chosen=$car;
                break;
            }
            $this->round=$chosen->number;
            $this->log($chosen->label(),'ASSIGN',$g->label());
        } else {
            $chosen=$candidates[0];
            $cost=$this->cost($chosen,$g);
            foreach(array_slice($candidates,1) as $car) {
                $v=$this->cost($car,$g);
                if($v<$cost) {
                    $chosen=$car;
                    $cost=$v;
                }
            }
            $this->log($chosen->label(),'ASSIGN',$g->label(),"cost=$cost");
        }
        if($g->car!==null) removeObject($g->car->calls,$g);
        $chosen->calls[]=$g;
        $g->car=$chosen;
        return true;
    }
    private function dispatch(Group $g): void {
        if(!$this->assign($g)) {
            $this->pending[]=$g;
            $this->log('PENDING',$g->label());
        }
    }
    private function walk(Group $g,string $word): void {
        if($g->car!==null) removeObject($g->car->calls,$g);
        else removeObject($this->pending,$g);
        $g->car=null;
        $this->log($word,$g->label(),'x'.$g->waiting);
        $g->lost+=$g->waiting;
        $this->abandoned+=$g->waiting;
        $g->waiting=0;
    }
    private function event(string $cmd,array $v): void {
        switch($cmd) {
            case 'CALL':
                [$a,$b,$n]=$v;
                $g=new Group(count($this->groups)+1,$a,$b,$n,$this->time);
                $this->groups[]=$g;
                $this->log($cmd,$g->label(),"$a->$b","x$n");
                $this->dispatch($g);
                break;
            case 'CANCEL':
                $g=$this->groups[$v[0]-1];
                if($g->waiting>0) $this->walk($g,$cmd);
                else $this->log($cmd,$g->label(),'ignored');
                break;
            case 'OUT':
                $car=$this->cars[$v[0]-1];
                $car->service=false;
                $this->log($car->label(),$cmd);
                $calls=$car->calls;
                $car->calls=[];
                foreach($calls as $g) {
                    $g->car=null;
                    $this->dispatch($g);
                }
                break;
            case 'IN':
                $car=$this->cars[$v[0]-1];
                $car->service=true;
                $car->idle=$this->time;
                $this->log($car->label(),$cmd);
                $pending=$this->pending;
                $this->pending=[];
                foreach($pending as $g) if(!$this->assign($g)) $this->pending[]=$g;
                break;
            case 'HOLD':
                $car=$this->cars[$v[0]-1];
                if($car->door>0) $car->door+=$v[1];
                $this->log($car->label(),$cmd,$car->door>0?$car->door:'ignored');
                break;
            case 'FIRE':
                $this->fire=$v[0];
                $this->log($cmd,$this->fire);
                foreach($this->groups as $g) if($g->waiting>0) $this->walk($g,'ABANDON');
                break;
            case 'RESET':
                $this->fire=null;
                $this->log($cmd);
                foreach($this->cars as $car) $car->idle=$this->time;
                break;
            case 'WHERE':
                $g=$this->groups[$v[0]-1];
                $place=$g->waiting===0?'-':($g->car?->label()??'pending');
                $riding=[];
                foreach($this->cars as $car) {
                    $n=0;
                    foreach($car->passengers as $p) if($p->group===$g) $n+=$p->count;
                    if($n>0) $riding[]=$car->label().'x'.$n;
                }
                $this->log($cmd,$g->label(),"waiting={$g->waiting}","car=$place",'riding='.joined($riding),"delivered={$g->delivered}","lost={$g->lost}");
                break;
            case 'STATUS':
                foreach($this->cars as $car) {
                    $stops=array_values(array_unique(array_map(fn(Passenger $p)=>$p->group->b,$car->passengers)));
                    sort($stops,SORT_NUMERIC);
                    $dir=[-1=>'down',0=>'idle',1=>'up'][$car->direction];
                    $this->log($cmd,$car->label(),"floor={$car->floor}","dir=$dir","door={$car->door}",'load='.$car->load(),'stops='.joined($stops),'calls='.joined(array_map(fn(Group $g)=>$g->label(),$car->calls)),'service='.($car->service?'in':'out'));
                }
                $this->log($cmd,'pending='.joined(array_map(fn(Group $g)=>$g->label(),$this->pending)));
                break;
        }
    }
    private function heading(Car $car): int {
        $f=$car->floor;
        $d=$car->direction;
        $here=$this->bypass($car)?[]:array_values(array_filter($car->calls,fn(Group $g)=>$g->a===$f));
        $ts=$car->targets();
        if($d!==0) {
            foreach($ts as $y) if(($y-$f)*$d>0) return $d;
            foreach($here as $g) if($g->direction()===$d) return $d;
        }
        if($here!==[]) return $here[0]->direction();
        if($d!==0) foreach($ts as $y) if(($y-$f)*$d<0) return -$d;
        if($d===0&&$car->calls!==[]) return $car->calls[0]->a<=>$f;
        return 0;
    }
    private function move(Car $car,int $n): void {
        $car->energy+=$n>0?3+$car->load():1;
        $car->floor+=$n;
        $car->distance++;
    }
    private function deliver(Passenger $p): void {
        $g=$p->group;
        $w=$p->boardTime-$g->time;
        $r=$this->time-$g->time;
        $g->delivered+=$p->count;
        $g->lastAlight=$this->time;
        $g->waitTotal+=$w*$p->count;
        $g->travelTotal+=$r*$p->count;
        $this->delivered+=$p->count;
        $this->waitTotal+=$w*$p->count;
        $this->travelTotal+=$r*$p->count;
        $this->maxWait=max($this->maxWait,$w);
    }
    private function open(Car $car): void {
        $this->log($car->label(),'OPEN',$car->floor);
        $car->door=$this->c['DOOR'];
        $car->stops++;
        $car->energy+=2;
        $riding=[];
        foreach($car->passengers as $p) {
            if($p->group->b===$car->floor) {
                $this->log($car->label(),'ALIGHT',$p->group->label(),'x'.$p->count);
                $this->deliver($p);
            } elseif($this->fire!==null) {
                $this->log($car->label(),'EVACUATE',$p->group->label(),'x'.$p->count);
                $p->group->lost+=$p->count;
                $this->evacuated+=$p->count;
            } else $riding[]=$p;
        }
        $car->passengers=$riding;
        if($this->fire!==null) return;
        $n=$this->heading($car);
        if($n!==0) $car->direction=$n;
        $boarding=array_values(array_filter($car->calls,fn(Group $g)=>$g->a===$car->floor&&$g->direction()===$n));
        foreach($boarding as $g) {
            $k=min($this->c['CAPACITY']-$car->load(),$g->waiting);
            if($k>0) {
                $car->passengers[]=new Passenger($g,$k,$this->time);
                $car->boarded+=$k;
                $g->waiting-=$k;
                $g->boarded+=$k;
                $g->lastBoard=$this->time;
                $g->cars[$car->number]=true;
                $this->log($car->label(),'BOARD',$g->label(),"x$k");
            }
            if($g->waiting===0) {
                removeObject($car->calls,$g);
                $g->car=null;
            } else {
                $this->log($car->label(),'LEFT',$g->label(),'x'.$g->waiting);
                $this->assign($g,$car);
            }
        }
    }
    private function advance(Car $car): void {
        $old=$car->floor;
        if($car->door>0) $car->door--;
        if($car->door===0) {
            if($this->fire!==null) {
                $n=$this->fire<=>$car->floor;
                $stop=$n===0&&$car->passengers!==[];
            } else {
                $n=$this->heading($car);
                $stop=false;
                foreach($car->passengers as $p) if($p->group->b===$car->floor) $stop=true;
                if(!$this->bypass($car)) foreach($car->calls as $g) if($g->a===$car->floor&&$g->direction()===$n) $stop=true;
            }
            if($stop) $this->open($car);
            elseif($n!==0) {
                $car->direction=$n;
                $this->move($car,$n);
            } else {
                if($car->direction!==0) {
                    $this->log($car->label(),'IDLE',$car->floor);
                    $car->direction=0;
                    $car->idle=$this->time;
                }
                if($this->fire===null&&$car->service&&$car->home!==null&&$car->floor!==$car->home&&$this->time-$car->idle >= $this->c['PARK'][0]) {
                    $this->move($car,$car->home<=>$car->floor);
                    if($car->floor===$car->home) $this->log($car->label(),'PARK',$car->home);
                }
            }
        }
        if($car->door>0||$old!==$car->floor) $car->busy++;
    }
    private function settled(Car $car): bool {
        return $car->door===0&&$car->passengers===[]&&$car->calls===[]&&($this->fire!==null?$car->floor===$this->fire:!$car->service||$car->home===null||$car->floor===$car->home);
    }
    private function run(): void {
        $index=0;
        while(true) {
            foreach($this->groups as $g) if($g->waiting>0&&isset($this->c['PATIENCE'])&&$this->time===$g->time+$this->c['PATIENCE']) $this->walk($g,'ABANDON');
            while($index<count($this->events)&&$this->events[$index][0]===$this->time) {
                [, $cmd,$v]=$this->events[$index++];
                $this->event($cmd,$v);
            }
            foreach($this->cars as $car) $this->advance($car);
            $settled=true;
            foreach($this->cars as $car) if(!$this->settled($car)) $settled=false;
            if($index===count($this->events)&&$settled) {
                $this->status='end';
                $this->log('END');
                return;
            }
            if($this->time===$this->c['LIMIT']) {
                $this->status='abort';
                $this->log('ABORT');
                return;
            }
            $this->time++;
        }
    }
    public function averages(): string {
        return 'avg_wait='.average($this->waitTotal,$this->delivered).' avg_travel='.average($this->travelTotal,$this->delivered).' max_wait='.($this->delivered===0?'-':$this->maxWait);
    }
    private function breakdown(string $label,array $gs): void {
        $n=$d=$w=0;
        foreach($gs as $g) {
            $n+=$g->count;
            $d+=$g->delivered;
            $w+=$g->waitTotal;
        }
        emit("$label: groups=".count($gs)." passengers=$n delivered=$d avg_wait=".average($w,$d));
    }
    public function report(): void {
        $passengers=0;
        $floors=$periods=[];
        foreach($this->groups as $g) {
            $passengers+=$g->count;
            $floors[$g->a][]=$g;
            if(isset($this->c['PERIOD'])) $periods[intdiv($g->time,$this->c['PERIOD'])][]=$g;
            $wait=$g->boarded===$g->count?$g->lastBoard-$g->time:'-';
            $travel=$g->delivered===$g->count?$g->lastAlight-$g->time:'-';
            $cs=array_keys($g->cars);
            sort($cs,SORT_NUMERIC);
            emit($g->label(),"t={$g->time}","{$g->a}->{$g->b}","n={$g->count}","delivered={$g->delivered}","lost={$g->lost}","wait=$wait","travel=$travel",'cars='.joined($cs));
        }
        foreach($this->cars as $car) {
            $n=intdiv($car->busy*1000,$this->time+1);
            emit($car->label(),"distance={$car->distance}","stops={$car->stops}","boarded={$car->boarded}","busy={$car->busy}",'util='.intdiv($n,10).'.'.($n%10).'%',"energy={$car->energy}");
        }
        ksort($floors,SORT_NUMERIC);
        foreach($floors as $f=>$gs) $this->breakdown('F'.$f,$gs);
        ksort($periods,SORT_NUMERIC);
        foreach($periods as $k=>$gs) {
            $w=$this->c['PERIOD'];
            $this->breakdown("P$k ".($k*$w).'-'.($k*$w+$w-1),$gs);
        }
        emit('summary:','groups='.count($this->groups),"passengers=$passengers","delivered={$this->delivered}","abandoned={$this->abandoned}","evacuated={$this->evacuated}",$this->averages(),"end={$this->time}");
    }
}
$lines=file('php://stdin',FILE_IGNORE_NEW_LINES);
$index=1;
$scenarios=[];
for($ordinal=0;$ordinal<(int)$lines[0];$ordinal++) {
    $name=explode(' ',$lines[$index++])[1];
    $settings=$events=[];
    while($lines[$index]!=='END') {
        $words=explode(' ',$lines[$index]);
        if(ctype_digit($words[0][0])) $events[]=[$index+1,$words];
        else $settings[]=$words;
        $index++;
    }
    $index++;
    emit("== $name ==");
    try {
        $c=parseConfig($settings);
        emit('config:',"floors={$c['FLOORS']}","cars={$c['CARS']}","capacity={$c['CAPACITY']}","door={$c['DOOR']}","policy={$c['POLICY']}",'park='.($c['PARK'][0]??'off'),'patience='.($c['PATIENCE']??'off'),"bypass={$c['BYPASS']}",'period='.($c['PERIOD']??'off'),"limit={$c['LIMIT']}",'compare='.joined($c['COMPARE']));
        for($i=0;$i<$c['CARS'];$i++) emit('E'.($i+1).':',"start={$c['START'][$i]}",'zone='.implode('-',$c['ZONES'][$i]),'home='.($c['PARK'][$i+1]??'-'));
        $accepted=validateEvents($c,$events);
        $s=new Simulation($c,$accepted,$c['POLICY'],true);
        $s->report();
        $scenarios[]=['name'=>$name,'config'=>$c,'sim'=>$s,'ordinal'=>$ordinal];
        foreach($c['COMPARE'] as $policy) {
            $o=new Simulation($c,$accepted,$policy,false);
            emit("compare $policy:","delivered={$o->delivered}",$o->averages(),"end={$o->time}","status={$o->status}");
        }
    } catch(ConfigError $e) {
        emit('error:',$e->getMessage());
        $scenarios[]=['name'=>$name,'config'=>null,'sim'=>null,'ordinal'=>$ordinal];
    }
}
emit('== ranking ==');
$ranked=array_values(array_filter($scenarios,fn($s)=>$s['sim']!==null&&$s['sim']->status==='end'&&$s['sim']->delivered>0));
usort($ranked,function($x,$y) {
    $a=$x['sim']; $b=$y['sim']; return ($a->waitTotal*$b->delivered<=>$b->waitTotal*$a->delivered)?:($a->travelTotal*$b->delivered<=>$b->travelTotal*$a->delivered)?:($x['ordinal']<=>$y['ordinal']);
});
foreach($ranked as $i=>$r) emit(($i+1).'.',$r['name'],'policy='.$r['config']['POLICY'],$r['sim']->averages());
foreach($scenarios as $r) {
    $s=$r['sim'];
    if($s!==null&&$s->status==='end'&&$s->delivered>0) continue;
    emit('-',$r['name'],$s===null?'invalid':($s->status==='abort'?'aborted':'empty'));
}
emit('== policies ==');
foreach(POLICIES as $policy) {
    $n=$d=$w=$t=0;
    foreach($ranked as $r) if($r['config']['POLICY']===$policy) {
        $s=$r['sim'];
        $n++;
        $d+=$s->delivered;
        $w+=$s->waitTotal;
        $t+=$s->travelTotal;
    }
    if($n>0) emit("$policy:","runs=$n",'avg_wait='.average($w,$d),'avg_travel='.average($t,$d));
}
