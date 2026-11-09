<?php
declare(strict_types=1);
const ALGOS=['FCFS','SJF','SRTF','RR','PRIORITY','HRRN','EDF','LOTTERY','MLFQ'];
const KEYS=['cs','q','k','s','seed'];
const RANGES=['cs'=>[0,5],'q'=>[1,20],'k'=>[1,50],'s'=>[0,500],'seed'=>[1,2147483646]];
const DEFAULTS=['cs'=>0,'q'=>4,'k'=>5,'s'=>0,'seed'=>1];
const METRICS=['turnaround','waiting','response'];
const EVENT_KINDS=['PREEMPT','EXPIRE','DEMOTE','BOOST','AGE'];
const SYMBOLS=['FUTURE'=>'-','DONE'=>'-','RUN'=>'#','SWITCH'=>'s','READY'=>'.','IO'=>'i'];
final class CommandError extends RuntimeException {
}
function check(bool $bad,string $reason): void {
    if($bad) throw new CommandError($reason);
}
function emit(mixed ...$parts): void {
    echo implode(' ',$parts),"\n";
}
function allowed(string $a): array {
    return ['cs',...(['RR'=>['q'],'LOTTERY'=>['q','seed'],'PRIORITY'=>['k'],'MLFQ'=>['s']][$a]??[])];
}
function notation(array $p,?string $a=null): string {
    return implode(' ',array_map(fn($k)=>"$k={$p[$k]}",$a===null?KEYS:allowed($a)));
}
function truncated(int $u,int $v): string {
    $n=intdiv($u*100,$v);
    return intdiv($n,100).'.'.str_pad((string)($n%100),2,'0',STR_PAD_LEFT);
}
function parseParams(array $words,?string $a=null,array $seen=[]): array {
    $p=DEFAULTS;
    foreach($words as $word) {
        [$k,$text]=explode('=',$word);
        $v=(int)$text;
        check(!isset(RANGES[$k]),"unknown key $k");
        check($a!==null&&!in_array($k,allowed($a),true),"key $k not allowed for $a");
        check(in_array($k,$seen,true),"duplicate key $k");
        [$lo,$hi]=RANGES[$k];
        check($v<$lo||$v>$hi,"invalid $k");
        $seen[]=$k;
        $p[$k]=$v;
    }
    return $p;
}
final class ProcessDef {
    public ?int $deadline=null;
    public function __construct(public string $id,public int $arrival,public int $priority,public array $bursts) {
    }
    public function describe(): string {
        $bs=[];
        foreach($this->bursts as $i=>$n) $bs[]=($i%2===0?'C':'I').$n;
        return "{$this->id} arrival={$this->arrival} priority={$this->priority} deadline=".($this->deadline??'none').' bursts='.implode(',',$bs);
    }
}
final class Burst {
    public ?int $start=null,$end=null;
    public int $slices=0;
    public function __construct(public int $length,public int $ready) {
    }
}
final class Job {
    public string $state='FUTURE',$timeline='';
    public int $burst=0,$left,$effective,$wait=0,$level=0,$used=0,$enqueued=0;
    public ?int $start=null,$finish=null;
    public array $records=[];
    public function __construct(public ProcessDef $process) {
        $this->left=$process->bursts[0];
        $this->effective=$process->priority;
    }
    public function id(): string {
        return $this->process->id;
    }
    public function deadline(): ?int {
        return $this->process->deadline===null?null:$this->process->arrival+$this->process->deadline;
    }
    public function metrics(): array {
        $t=$this->finish-$this->process->arrival;
        return [$t,$t-array_sum($this->process->bursts),$this->start-$this->process->arrival];
    }
    public function slices(): int {
        return array_sum(array_map(fn(Burst $r)=>$r->slices,$this->records));
    }
    public function missed(): bool {
        return $this->deadline()!==null&&$this->finish>$this->deadline();
    }
    public function record(): Burst {
        return $this->records[count($this->records)-1];
    }
}
final class Simulation {
    public array $jobs=[],$events=[],$counts=[],$labels=[],$states=[],$lengths=[],$snapshot=[];
    public int $time=0,$switches=0;
    private array $queues=[[],[],[]];
    private string $cpu='IDLE';
    private ?Job $current=null,$previous=null;
    private int $switchLeft=0,$run=0,$random;
    public function __construct(array $processes,private string $a,private array $p,private ?int $snapshotTime=null) {
        usort($processes,fn(ProcessDef $x,ProcessDef $y)=>strcmp($x->id,$y->id));
        foreach($processes as $d) $this->jobs[]=new Job($d);
        $this->random=$p['seed'];
        $this->simulate();
    }
    private function event(string $kind,mixed ...$parts): void {
        $this->events[]=implode(' ',[$this->time,$kind,...$parts]);
        $this->counts[$kind]=($this->counts[$kind]??0)+1;
    }
    private function enqueue(Job $j): void {
        $j->state='READY';
        $j->enqueued=$this->time;
        $this->queues[$j->level][]=$j;
    }
    private function advance(Job $j): void {
        $j->burst++;
        $j->left=$j->process->bursts[$j->burst];
    }
    private function release(): void {
        $this->cpu='IDLE';
        $this->current=null;
    }
    private function start(Job $j): void {
        $this->cpu='RUN';
        $this->current=$j;
        $this->run=0;
        $j->state='RUN';
        $j->start??=$this->time;
        $j->record()->start??=$this->time;
    }
    private function preempts(Job $j): bool {
        if($this->a==='MLFQ') {
            for($i=0;$i<$j->level;$i++) if($this->queues[$i]!==[]) return true;
            return false;
        }
        foreach($this->queues[0] as $x) {
            if($this->a==='SRTF'&&$x->left<$j->left) return true;
            if($this->a==='PRIORITY'&&$x->effective<$j->effective) return true;
            if($this->a==='EDF'&&$x->deadline()!==null&&($j->deadline()===null||$x->deadline()<$j->deadline())) return true;
        }
        return false;
    }
    private function choose(array $q): Job {
        if($this->a==='LOTTERY') {
            $this->random=48271*$this->random%2147483647;
            $z=array_sum(array_map(fn(Job $j)=>10-$j->process->priority,$q));
            $target=$this->random%$z;
            foreach($q as $j) {
                $target-=10-$j->process->priority;
                if($target<0) return $j;
            }
        }
        $best=$q[0];
        foreach(array_slice($q,1) as $j) {
            $better=match($this->a) {
                'SJF','SRTF'=>$j->left<$best->left, 'PRIORITY'=>$j->effective<$best->effective,
                'EDF'=>$j->deadline()!==null&&($best->deadline()===null||$j->deadline()<$best->deadline()),
                'HRRN'=>($this->time-$j->enqueued+$j->left)*$best->left>($this->time-$best->enqueued+$best->left)*$j->left,
                default=>false
            };
            if($better) $best=$j;
        }
        return $best;
    }
    private function simulate(): void {
        while(true) {
            if($this->a==='PRIORITY') foreach($this->queues[0] as $j) {
                $j->wait++;
                if($j->wait===$this->p['k']) {
                    $j->wait=0;
                    if($j->effective>0) {
                        $j->effective--;
                        $this->event('AGE',$j->id(),$j->effective);
                    }
                }
            }
            foreach($this->jobs as $j) if($j->state==='IO'&&$j->left===0) {
                $this->advance($j);
                $j->records[]=new Burst($j->left,$this->time);
                $this->enqueue($j);
                $this->event('IODONE',$j->id());
            }
            foreach($this->jobs as $j) if($j->state==='FUTURE'&&$j->process->arrival===$this->time) {
                $j->records[]=new Burst($j->left,$this->time);
                $this->enqueue($j);
                $this->event('ARRIVE',$j->id());
            }
            $j=$this->current;
            if($this->cpu==='SWITCH'&&$this->switchLeft===0) {
                $this->start($j);
                $this->event('START',$j->id());
            } elseif($this->cpu==='RUN') {
                if($j->left===0&&$j->burst===count($j->process->bursts)-1) {
                    $j->state='DONE';
                    $j->finish=$this->time;
                    $this->event('DONE',$j->id());
                    $this->release();
                } else {
                    $demoted=$this->a==='MLFQ'&&$j->level<2&&$j->used===[4,8][$j->level];
                    if($demoted) {
                        $j->level++;
                        $j->used=0;
                        $this->event('DEMOTE',$j->id(),$j->level);
                    }
                    if($j->left===0) {
                        $this->advance($j);
                        $j->state='IO';
                        $this->event('IO',$j->id(),$j->left);
                        $this->release();
                    } elseif($demoted) {
                        $this->enqueue($j);
                        $this->release();
                    } elseif(in_array($this->a,['RR','LOTTERY'],true)&&$this->run===$this->p['q']) {
                        $this->enqueue($j);
                        $this->event('EXPIRE',$j->id());
                        $this->release();
                    } elseif($this->preempts($j)) {
                        $this->enqueue($j);
                        $this->event('PREEMPT',$j->id());
                        $this->release();
                    }
                }
            }
            if(count(array_filter($this->jobs,fn(Job $x)=>$x->state!=='DONE'))===0) break;
            if($this->a==='MLFQ'&&$this->p['s']>0&&$this->time>0&&$this->time%$this->p['s']===0) {
                $this->queues=[array_merge(...$this->queues),[],[]];
                foreach($this->jobs as $x) $x->level=$x->used=0;
                $this->event('BOOST');
            }
            if($this->cpu==='IDLE') for($i=0;$i<3;$i++) if($this->queues[$i]!==[]) {
                $j=$this->choose($this->queues[$i]);
                $index=array_search($j,$this->queues[$i],true);
                array_splice($this->queues[$i],$index,1);
                $j->effective=$j->process->priority;
                $j->wait=0;
                $j->record()->slices++;
                $switched=$j!==$this->previous;
                if($switched) $this->switches++;
                if($switched&&$this->p['cs']>0) {
                    $this->cpu='SWITCH';
                    $this->current=$j;
                    $this->switchLeft=$this->p['cs'];
                    $j->state='SWITCH';
                    $this->event('SWITCH',$j->id());
                } else {
                    $this->start($j);
                    $this->event('DISPATCH',$j->id());
                }
                break;
            }
            if($this->time===$this->snapshotTime) $this->capture();
            foreach($this->jobs as $x) $x->timeline.=SYMBOLS[$x->state];
            $this->lengths[]=array_sum(array_map('count',$this->queues));
            $this->states[]=$this->cpu;
            if($this->cpu==='RUN') {
                $j=$this->current;
                $j->left--;
                $j->used++;
                $this->run++;
                $this->previous=$j;
                $this->labels[]=$j->id();
                if($j->left===0) $j->record()->end=$this->time+1;
            } elseif($this->cpu==='SWITCH') {
                $this->switchLeft--;
                $this->labels[]='CS';
            } else $this->labels[]='IDLE';
            foreach($this->jobs as $x) if($x->state==='IO') $x->left--;
            $this->time++;
        }
        if($this->snapshot===[]) $this->capture();
    }
    private function capture(): void {
        $this->snapshot=[$this->cpu==='IDLE'?'CPU IDLE':"CPU {$this->cpu} ".$this->current->id()];
        for($i=0;$i<($this->a==='MLFQ'?3:1);$i++) {
            $ids=array_map(fn(Job $j)=>$j->id(),$this->queues[$i]);
            $this->snapshot[]='QUEUE'.($this->a==='MLFQ'?$i:'').' '.($ids===[]?'none':implode(' ',$ids));
        }
        foreach($this->jobs as $j) {
            if($j->state==='FUTURE') $text=$j->id()." FUTURE at={$j->process->arrival}";
            elseif($j->state==='DONE') $text=$j->id()." DONE at={$j->finish}";
            else {
                $text=$j->id()." {$j->state} burst=".($j->burst+1)." left={$j->left}";
                if($this->a==='PRIORITY') $text.=" prio={$j->effective}";
                if($this->a==='MLFQ') $text.=" level={$j->level} used={$j->used}";
            }
            $this->snapshot[]=$text;
        }
    }
    public function totals(): array {
        $v=[0,0,0];
        foreach($this->jobs as $j) foreach($j->metrics() as $i=>$n) $v[$i]+=$n;
        return $v;
    }
    public function averages(): array {
        return array_map(fn($n)=>truncated($n,count($this->jobs)),$this->totals());
    }
    public function ticks(int $a,int $b): array {
        $ss=array_count_values(array_slice($this->states,$a,$b-$a));
        return [$ss['RUN']??0,$ss['SWITCH']??0,$ss['IDLE']??0];
    }
    public function utilization(): string {
        return truncated($this->ticks(0,$this->time)[0]*100,$this->time);
    }
    public function missed(): int {
        return count(array_filter($this->jobs,fn(Job $j)=>$j->missed()));
    }
    public function met(): int {
        return count(array_filter($this->jobs,fn(Job $j)=>$j->deadline()!==null&&!$j->missed()));
    }
    public function segments(): array {
        $result=[];
        $start=0;
        for($t=1;$t<=$this->time;$t++) if($t===$this->time||$this->labels[$t]!==$this->labels[$start]) {
            $result[]="[$start-$t {$this->labels[$start]}]";
            $start=$t;
        }
        return $result;
    }
}
final class Scheduler {
    private array $registry=[];
    private function algorithm(string $a): void {
        check(!in_array($a,ALGOS,true),"unknown algorithm $a");
    }
    private function process(string $id): ProcessDef {
        return $this->registry[$id]??throw new CommandError("unknown process $id");
    }
    private function prepare(array $words,?string $a=null,array $preset=[]): array {
        $p=parseParams($words,$a,$preset);
        check($this->registry===[],'no processes');
        return $p;
    }
    private function sim(string $a,array $p,?int $t=null): Simulation {
        return new Simulation(array_values($this->registry),$a,$p,$t);
    }
    private function table(array $cells): string {
        $s=str_pad(array_shift($cells),8);
        foreach($cells as $v) $s.=' '.str_pad((string)$v,8,' ',STR_PAD_LEFT);
        return $s;
    }
    private function metricParts(array $v): array {
        $p=[];
        foreach(METRICS as $i=>$m) $p[]="$m={$v[$i]}";
        return $p;
    }
    public function execute(string $line): void {
        $a=explode(' ',trim($line));
        $c=array_shift($a);
        try {
            switch($c) {
                case 'PROC':
                    [$id,$at,$pr]=[$a[0],(int)$a[1],(int)$a[2]];
                    $words=array_slice($a,3);
                    check(isset($this->registry[$id]),"duplicate process $id");
                    check(count($this->registry)>=10,'too many processes');
                    check($at>200,"invalid arrival $id");
                    check($pr>9,"invalid priority $id");
                    $valid=count($words)%2===1;
                    $bs=[];
                    $cpu=$io=0;
                    foreach($words as $i=>$w) {
                        $n=(int)substr($w,1);
                        $valid=$valid&&$w[0]===($i%2===0?'C':'I')&&$n>=1&&$n<=30;
                        $bs[]=$n;
                        if($i%2===0) $cpu+=$n;
                        else $io+=$n;
                    }
                    check(!$valid,"invalid bursts $id");
                    $this->registry[$id]=new ProcessDef($id,$at,$pr,$bs);
                    emit($c,$id,"cpu=$cpu","io=$io");
                    return;
                case 'GEN':
                    [$prefix,$count,$seed]=[$a[0],(int)$a[1],(int)$a[2]];
                    for($i=1;$i<=$count;$i++) check(isset($this->registry[$prefix.$i]),'duplicate process '.$prefix.$i);
                    check(count($this->registry)+$count>10,'too many processes');
                    emit($c,"count=$count");
                    $draw=function(int $m) use (&$seed): int {
                        $seed=48271*$seed%2147483647;
                        return $seed%$m;
                    };
                    for($i=1;$i<=$count;$i++) {
                        $id=$prefix.$i;
                        $at=$draw(21);
                        $pr=$draw(10);
                        $m=1+$draw(3);
                        $bs=[];
                        for($j=0;$j<$m;$j++) {
                            if($j>0) $bs[]=1+$draw(8);
                            $bs[]=1+$draw(9);
                        }
                        $d=new ProcessDef($id,$at,$pr,$bs);
                        $this->registry[$id]=$d;
                        emit($d->describe());
                    }
                    return;
                case 'SETPRIO':
                case 'DEADLINE':
                    $d=$this->process($a[0]);
                    $n=(int)$a[1];
                    check($n>($c==='SETPRIO'?9:1000),'invalid '.($c==='SETPRIO'?'priority':'deadline')." {$d->id}");
                    if($c==='SETPRIO') {
                        $d->priority=$n;
                        emit($c,$d->id,"priority=$n");
                    } else {
                        $d->deadline=$n===0?null:$n;
                        emit($c,$d->id,$d->deadline??'none');
                    }
                    return;
                case 'DROP':
                    $this->process($a[0]);
                    unset($this->registry[$a[0]]);
                    emit($c,$a[0]);
                    return;
                case 'CLEAR':
                    emit($c,'count='.count($this->registry));
                    $this->registry=[];
                    return;
                case 'LIST':
                    emit($c,'count='.count($this->registry));
                    $ids=array_keys($this->registry);
                    sort($ids,SORT_STRING);
                    foreach($ids as $id) emit($this->registry[$id]->describe());
                    return;
            }
            if(in_array($c,['COMPARE','DIFF','RANK'],true)) {
                $first=$second=$metric=null;
                $header=[];
                if($c==='DIFF') {
                    $first=array_shift($a);
                    $second=array_shift($a);
                    $this->algorithm($first);
                    $this->algorithm($second);
                    $header=[$first,$second];
                } elseif($c==='RANK') {
                    $metric=array_shift($a);
                    check(!in_array($metric,[...METRICS,'end','switches','missed'],true),"unknown metric $metric");
                    $header=[$metric];
                }
                $p=$this->prepare($a);
                emit($c,...[...$header,notation($p)]);
                $algos=$c==='DIFF'?[$first,$second]:ALGOS;
                $sims=array_map(fn($algo)=>$this->sim($algo,$p),$algos);
                if($c==='COMPARE') {
                    emit($this->table(['ALGO','TURN','WAIT','RESP','UTIL','END','SWITCH','MISS']));
                    foreach($sims as $i=>$s) emit($this->table([$algos[$i],...$s->averages(),$s->utilization(),$s->time,$s->switches,$s->missed()]));
                    $best=[];
                    foreach(METRICS as $i=>$m) {
                        $b=0;
                        foreach($sims as $j=>$s) if($s->totals()[$i]<$sims[$b]->totals()[$i]) $b=$j;
                        $best[]="$m={$algos[$b]}";
                    }
                    emit('BEST',...$best);
                } elseif($c==='DIFF') {
                    $wins=[0,0,0];
                    foreach($sims[0]->jobs as $i=>$j) {
                        $x=$j->metrics();
                        $y=$sims[1]->jobs[$i]->metrics();
                        $parts=[];
                        foreach(METRICS as $k=>$m) $parts[]="$m={$x[$k]}/{$y[$k]}";
                        emit($j->id(),...$parts);
                        $wins[$x[0]<$y[0]?0:($x[0]>$y[0]?1:2)]++;
                    }
                    emit('WINS',"$first={$wins[0]}","$second={$wins[1]}","ties={$wins[2]}");
                } else {
                    $idx=array_search($metric,METRICS,true);
                    $values=[];
                    foreach($sims as $s) $values[]=$idx!==false?$s->totals()[$idx]:match($metric) {
                        'end'=>$s->time,'switches'=>$s->switches,default=>$s->missed()
                    };
                    $indices=array_keys($values);
                    usort($indices,fn($i,$j)=>($values[$i]<=>$values[$j])?:($i<=>$j));
                    foreach($indices as $i) {
                        $rank=1;
                        foreach($values as $v) if($v<$values[$i]) $rank++;
                        emit($rank,$algos[$i],$idx!==false?truncated($values[$i],count($this->registry)):$values[$i]);
                    }
                }
                return;
            }
            $algo=array_shift($a);
            $this->algorithm($algo);
            $extra=null;
            $preset=[];
            if($c==='WINDOW') {
                $extra=(int)array_shift($a);
                check($extra<1||$extra>1000,'invalid window');
            } elseif($c==='SNAPSHOT') $extra=(int)array_shift($a);
            elseif($c==='SWEEP') {
                $key=array_shift($a);
                $lo=(int)array_shift($a);
                $hi=(int)array_shift($a);
                check(!isset(RANGES[$key]),"unknown key $key");
                check(!in_array($key,allowed($algo),true),"key $key not allowed for $algo");
                [$min,$max]=RANGES[$key];
                check($lo>$hi||$lo<$min||$hi>$max||$hi-$lo>20,'invalid range');
                $preset=[$key];
            }
            $p=$this->prepare($a,$algo,$preset);
            if($c==='SWEEP') {
                emit($c,$algo,$key,$lo,$hi);
                $best=null;
                $bestValue=$lo;
                for($v=$lo;$v<=$hi;$v++) {
                    $p[$key]=$v;
                    $s=$this->sim($algo,$p);
                    emit(notation($p,$algo),...array_merge($this->metricParts($s->averages()),['util='.$s->utilization(),"end={$s->time}","switches={$s->switches}"]));
                    $total=$s->totals()[1];
                    if($best===null||$total<$best) {
                        $best=$total;
                        $bestValue=$v;
                    }
                }
                emit('BEST',"$key=$bestValue");
                return;
            }
            $s=$this->sim($algo,$p,$c==='SNAPSHOT'?$extra:null);
            check($c==='TIMELINE'&&$s->time>100,"too long {$s->time}");
            $suffix=match($c) {
                'TIMELINE'=>["end={$s->time}"],'SNAPSHOT'=>["t=$extra"],'WINDOW'=>["width=$extra"],default=>[]
            };
            emit($c,$algo,notation($p,$algo),...$suffix);
            switch($c) {
                case 'TRACE':
                    foreach($s->events as $v) emit($v);
                    emit('END',$s->time);
                    break;
                case 'SNAPSHOT':
                    foreach($s->snapshot as $v) emit($v);
                    break;
                case 'TIMELINE':
                    foreach($s->jobs as $j) emit(str_pad($j->id(),8),$j->timeline);
                    break;
                case 'BURSTS':
                    foreach($s->jobs as $j) foreach($j->records as $i=>$r) emit($j->id(),'#'.($i+1),"len={$r->length}","ready={$r->ready}","start={$r->start}","end={$r->end}",'wait='.($r->end-$r->ready-$r->length),"slices={$r->slices}");
                    break;
                case 'WINDOW':
                    for($start=0;$start<$s->time;$start+=$extra) {
                        $stop=min($start+$extra,$s->time);
                        [$b,$cs,$idle]=$s->ticks($start,$stop);
                        $counts=[];
                        for($t=$start;$t<$stop;$t++) if($s->states[$t]==='RUN') $counts[$s->labels[$t]]=($counts[$s->labels[$t]]??0)+1;
                        $ids=array_keys($counts);
                        usort($ids,fn($x,$y)=>($counts[$y]<=>$counts[$x])?:strcmp($x,$y));
                        emit("$start-$stop","busy=$b","switch=$cs","idle=$idle",'util='.truncated($b*100,$stop-$start),'top='.($ids[0]??'none'));
                    }
                    break;
                case 'STATS':
                    foreach(METRICS as $i=>$m) {
                        $vs=array_map(fn(Job $j)=>$j->metrics()[$i],$s->jobs);
                        $sorted=$vs;
                        sort($sorted,SORT_NUMERIC);
                        $n=count($vs);
                        $double=$sorted[intdiv($n-1,2)]+$sorted[intdiv($n,2)];
                        $low=min($vs);
                        $high=max($vs);
                        $lowId=$s->jobs[array_search($low,$vs,true)]->id();
                        $highId=$s->jobs[array_search($high,$vs,true)]->id();
                        emit($m,"min=$low","($lowId)","max=$high","($highId)",'median='.intdiv($double,2).'.'.($double%2?5:0),'total='.array_sum($vs));
                    }
                    break;
                case 'RUN':
                    foreach(array_chunk($s->segments(),8) as $g) emit('GANTT',implode('',$g));
                    foreach($s->jobs as $j) {
                        [$t,$w,$r]=$j->metrics();
                        $text=$j->id()." arrival={$j->process->arrival} done={$j->finish} turnaround=$t waiting=$w response=$r slices=".$j->slices();
                        if($j->deadline()!==null) $text.=' deadline='.$j->deadline().' late='.max(0,$j->finish-$j->deadline());
                        emit($text);
                    }
                    emit('AVERAGE',...$this->metricParts($s->averages()));
                    [$b,$cs,$idle]=$s->ticks(0,$s->time);
                    emit('CPU',"end={$s->time}","busy=$b","switch=$cs","idle=$idle","switches={$s->switches}",'util='.$s->utilization());
                    emit('QUEUE','max='.max($s->lengths),'avg='.truncated(array_sum($s->lengths),$s->time));
                    $parts=[];
                    foreach(EVENT_KINDS as $k) $parts[]=strtolower($k).'='.($s->counts[$k]??0);
                    emit('EVENTS',...$parts);
                    emit('DEADLINE','met='.$s->met(),'missed='.$s->missed());
                    break;
            }
        } catch(CommandError $e) {
            emit('ERROR',$e->getMessage());
        }
    }
}
$scheduler=new Scheduler();
$n=(int)fgets(STDIN);
for($i=0;$i<$n;$i++) $scheduler->execute(fgets(STDIN));
