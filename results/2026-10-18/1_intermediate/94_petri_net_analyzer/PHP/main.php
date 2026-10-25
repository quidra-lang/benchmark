<?php
function yn(bool $b): string {
    return $b ? 'yes' : 'no';
}
function mark(array $m): string {
    return '('.implode(',',array_map(fn($x)=>$x<0?'w':(string)$x,$m)).')';
}
function listed(array $a): string {
    return $a ? implode(' ',$a) : 'none';
}
function number(string $s,int $lo,int $hi): int {
    return preg_match('/\A(?:0|[1-9][0-9]{0,9})\z/D',$s) && (int)$s >= $lo && (int)$s <= $hi ? (int)$s : -1;
}
function bad(string $s): never {
    throw new RuntimeException($s);
}
function visit(array $adj,int $start): array {
    $seen=array_fill(0,count($adj),false);
    $q=[$start];
    $seen[$start]=true;
    for($i=0;$i<count($q);++$i)foreach($adj[$q[$i]] as $v)if(!$seen[$v]){
        $seen[$v]=true;
        $q[]=$v;
    }
    return $seen;
}
function flows(array $a): array {
    $n=count($a);
    $m=count($a[0]);
    $rows=[];
    foreach($a as $i=>$r){
        for($j=0;$j<$n;++$j)$r[]=(int)($i===$j);
        $rows[]=$r;
    }
    $gcd=function(int $a,int $b)use(&$gcd):int{
        return $b?$gcd($b,$a%$b):abs($a);
    };
    for($j=0;$j<$m;++$j){
        $all=[];
        foreach($rows as $r)if($r[$j]===0)$all[implode(',',$r)]=$r;
        foreach($rows as $r)if($r[$j]>0)foreach($rows as $s)if($s[$j]<0){
            $v=[];
            $d=0;
            foreach($r as $k=>$x){
                $v[$k]=-$s[$j]*$x+$r[$j]*$s[$k];
                $d=$gcd($d,$v[$k]);
            }
            foreach($v as &$x)$x=intdiv($x,$d);
            unset($x);
            $all[implode(',',$v)]=$v;
        }
        $all=array_values($all);
        $supports=[];
        foreach($all as $r){
            $mask=0;
            for($i=0;$i<$n;++$i)if($r[$m+$i]>0)$mask|=1<<$i;
            $supports[]=$mask;
        }
        $rows=[];
        foreach($all as $i=>$r){
            $minimal=true;
            foreach($supports as $s)if($s!==$supports[$i]&&($s&$supports[$i])===$s){
                $minimal=false;
                break;
            }
            if($minimal)$rows[]=$r;
        }
    }
    $result=array_map(fn($r)=>array_slice($r,$m),$rows);
    usort($result,fn($a,$b)=>$b<=>$a);
    return $result;
}
final class Net {
    public array $p=[],$t=[],$initial=[],$cap=[],$priority=[],$current=[],$history=[],$pre=[],$post=[],$inh=[];
    public int $arcs=0,$inhibitors=0;
    public function __construct(public string $name){
        $this->pre=$this->post=$this->inh=array_fill(0,16,array_fill(0,16,0));
    }
    public function define(array $w):void {
        $cmd=$w[0];
        $n=count($w)-1;
        if(!in_array($cmd,['place','transition','arc','inhibit'],true))bad('unknown definition '.$cmd);
        if(!match($cmd){
            'place'=>$n===2||$n===3,'transition'=>$n===1||$n===2,default=>$n===3
        })bad('wrong number of arguments');
        $a=$w[1];
        if($cmd==='place'||$cmd==='transition'){
            if(in_array($a,$this->p,true)||in_array($a,$this->t,true))bad('duplicate name '.$a);
            if($cmd==='place'){
                if($n===3&&(int)$w[2]>(int)$w[3])bad('tokens exceed capacity of '.$a);
                $this->p[]=$a;
                $this->initial[]=(int)$w[2];
                $this->cap[]=$n===3?(int)$w[3]:0;
            }else{
                $this->t[]=$a;
                $this->priority[]=$n===2?(int)$w[2]:0;
            }
        }
        elseif($cmd==='arc'){
            $b=$w[2];
            foreach([$a,$b]as$x)if(!in_array($x,$this->p,true)&&!in_array($x,$this->t,true))bad('unknown node '.$x);
            $pa=array_search($a,$this->p,true);
            $pb=array_search($b,$this->p,true);
            if(($pa!==false)===($pb!==false))bad('arc must connect a place and a transition');
            $p=$pa!==false?$pa:$pb;
            $t=array_search($pa!==false?$b:$a,$this->t,true);
            $field=$pa!==false?'pre':'post';
            if($this->{
                $field
            }
            [$p][$t])bad("duplicate arc $a $b");
            $this->{
                $field
            }
            [$p][$t]=(int)$w[3];
            ++$this->arcs;
        }else{
            $p=array_search($a,$this->p,true);
            $t=array_search($w[2],$this->t,true);
            if($p===false)bad('unknown place '.$a);
            if($t===false)bad('unknown transition '.$w[2]);
            if($this->inh[$p][$t])bad("duplicate inhibitor $a {$w[2]}");
            $this->inh[$p][$t]=(int)$w[3];
            ++$this->inhibitors;
        }
    }
    public function reason(array $m,int $t):string {
        foreach($this->p as$p=>$name)if($m[$p]>=0&&$m[$p]<$this->pre[$p][$t])return 'insufficient tokens in '.$name;
        foreach($this->p as$p=>$name)if($this->inh[$p][$t]&&($m[$p]<0||$m[$p]>=$this->inh[$p][$t]))return 'inhibited by '.$name;
        foreach($this->p as$p=>$name)if($this->cap[$p]&&($m[$p]<0||$m[$p]-$this->pre[$p][$t]+$this->post[$p][$t]>$this->cap[$p]))return 'capacity of '.$name.' exceeded';
        return '';
    }
    public function enabled(array $m):array {
        $r=[];
        foreach($this->t as$t=>$name)if($this->reason($m,$t)==='')$r[]=$t;
        return $r;
    }
    public function fire(array $m,int $t):array {
        foreach($m as$p=>$v)if($v>=0)$m[$p]+=$this->post[$p][$t]-$this->pre[$p][$t];
        return $m;
    }
    public function commit(int $t):void {
        $this->history[]=$this->current;
        $this->current=$this->fire($this->current,$t);
    }
    public function names(array $ts):array{
        return array_map(fn($t)=>$this->t[$t],$ts);
    }
    public function graph(array $start,int $limit,?array $target=null):array {
        $g=['states'=>[$start],'parent'=>[-1],'via'=>[-1],'edges'=>[[]],'found'=>-1,'aborted'=>false];
        $index=[implode(',',$start)=>0];
        $matches=static function($m)use($target){
            if($target===null)return false;
            foreach($m as$p=>$v)if($v<$target[$p][0]||($target[$p][1]>=0&&$v!==$target[$p][1]))return false;
            return true;
        };
        if($matches($start)){
            $g['found']=0;
            return $g;
        }
        for($q=0;$q<count($g['states']);++$q)foreach($this->enabled($g['states'][$q])as$t){
            $m=$this->fire($g['states'][$q],$t);
            $key=implode(',',$m);
            if(!array_key_exists($key,$index)){
                if(count($g['states'])===$limit){
                    $g['aborted']=true;
                    return $g;
                }
                $k=count($g['states']);
                $index[$key]=$k;
                $g['states'][]=$m;
                $g['parent'][]=$q;
                $g['via'][]=$t;
                $g['edges'][]=[];
                if($matches($m)){
                    $g['found']=$k;
                    return $g;
                }
            }
            else$k=$index[$key];
            $g['edges'][$q][]=[$t,$k];
        }
        return $g;
    }
    public function path(array $g,int $k):array{
        $r=[];
        while($g['parent'][$k]>=0){
            $r[]=$g['via'][$k];
            $k=$g['parent'][$k];
        }
        return array_reverse($r);
    }
    public function reach(int $limit,bool $display):void {
        $g=$this->graph($this->current,$limit);
        if($g['aborted']){
            echo"reachability graph limit $limit exceeded\n";
            return;
        }
        $states=$g['states'];
        $edges=$g['edges'];
        $n=count($states);
        if($display){
            foreach($states as$i=>$m){
                $a=[];
                foreach($edges[$i]as[$t,$k])$a[]=$this->t[$t].'->M'.$k;
                echo'M'.$i.' '.mark($m).': '.($a?implode(' ',$a):'dead')."\n";
            }
            return;
        }
        $adj=array_map(fn($e)=>array_column($e,1),$edges);
        $closure=[];
        for($i=0;$i<$n;++$i)$closure[]=visit($adj,$i);
        $comp=array_fill(0,$n,-1);
        $count=0;
        for($i=0;$i<$n;++$i)if($comp[$i]<0){
            for($j=$i;$j<$n;++$j)if($closure[$i][$j]&&$closure[$j][$i])$comp[$j]=$count;
            ++$count;
        }
        $terminal=array_fill(0,$count,true);
        $home=array_fill(0,$n,true);
        $maximum=array_fill(0,count($this->p),0);
        $dead=[];
        $edgeCount=0;
        $persistent=true;
        foreach($states as$i=>$m){
            if(!$edges[$i])$dead[]=$i;
            $edgeCount+=count($edges[$i]);
            foreach($m as$p=>$v)$maximum[$p]=max($maximum[$p],$v);
            for($j=0;$j<$n;++$j)$home[$j]=$home[$j]&&$closure[$i][$j];
            foreach($edges[$i]as[$t,$k]){
                if($comp[$i]!==$comp[$k])$terminal[$comp[$i]]=false;
                foreach($edges[$i]as[$u,$v])if($t!==$u&&$this->reason($states[$k],$u)!=='')$persistent=false;
            }
        }
        echo"reachable markings: $n\nedges: $edgeCount\ncomponents: $count (terminal ".count(array_filter($terminal)).")\ndead markings: ".count($dead)."\n";
        foreach($dead as$i){
            $a=$this->names($this->path($g,$i));
            echo'  M'.$i.' '.mark($states[$i]).' path '.($a?implode(' ',$a):'empty')."\n";
        }
        $bound=max($maximum);
        echo'max tokens: '.mark($maximum)."\nbound: $bound\nsafe: ".yn($bound<=1)."\n";
        echo'home markings: '.count(array_filter($home))."\nreversible: ".yn($home[0])."\npersistent: ".yn($persistent)."\n";
        $levels=[];
        foreach($this->t as$t=>$name){
            $present=array_fill(0,$count,false);
            $used=$cycle=false;
            foreach($edges as$i=>$e)foreach($e as[$u,$v])if($u===$t){
                $used=true;
                $present[$comp[$i]]=true;
                if($comp[$i]===$comp[$v])$cycle=true;
            }
            $live=true;
            foreach($terminal as$c=>$v)if($v&&!$present[$c])$live=false;
            $levels[]=$name.'='.($live?'L4':($cycle?'L3':($used?'L1':'L0')));
        }
        echo'liveness: '.implode(' ',$levels)."\n";
    }
    public function cover(int $limit):void {
        $states=[$this->current];
        $parents=[-1];
        $via=[-1];
        $old=[false];
        $dead=[false];
        $rank=fn($v)=>$v<0?PHP_INT_MAX:$v;
        for($q=0;$q<count($states);++$q){
            if($old[$q])continue;
            $es=$this->enabled($states[$q]);
            $dead[$q]=!$es;
            $anc=[];
            for($a=$q;$a>=0;$a=$parents[$a])$anc[]=$a;
            $anc=array_reverse($anc);
            foreach($es as$t){
                $m=$this->fire($states[$q],$t);
                foreach($anc as$a){
                    $ge=true;
                    $gt=false;
                    foreach($m as$p=>$v){
                        $ge=$ge&&$rank($v)>=$rank($states[$a][$p]);
                        $gt=$gt||$rank($v)>$rank($states[$a][$p]);
                    }
                    if($ge&&$gt)foreach($m as$p=>$v)if(!$this->cap[$p]&&$rank($v)>$rank($states[$a][$p]))$m[$p]=-1;
                }
                if(count($states)===$limit){
                    echo"coverability tree limit $limit exceeded\n";
                    return;
                }
                $old[]=in_array($m,$states,true);
                $states[]=$m;
                $parents[]=$q;
                $via[]=$t;
                $dead[]=false;
            }
        }
        echo'coverability tree nodes: '.count($states)."\n";
        $maximum=array_fill(0,count($this->p),0);
        foreach($states as$i=>$m){
            echo'  '.$i.' '.mark($m).' '.($i?'<- '.$parents[$i].' '.$this->t[$via[$i]]:'root').($old[$i]?' old':'').($dead[$i]?' dead':'')."\n";
            foreach($m as$p=>$v)if($rank($v)>$rank($maximum[$p]))$maximum[$p]=$v;
        }
        $names=[];
        foreach($maximum as$p=>$v)if($v<0)$names[]=$this->p[$p];
        echo'bounds: '.mark($maximum)."\nunbounded: ".listed($names)."\n";
    }
    public function sets(bool $trap):array {
        $all=[];
        for($mask=1;$mask<(1<<count($this->p));++$mask){
            $valid=true;
            foreach($this->t as$t=>$name){
                $in=$out=false;
                foreach($this->p as$p=>$name)if($mask&(1<<$p)){
                    $in=$in||$this->post[$p][$t]>0;
                    $out=$out||$this->pre[$p][$t]>0;
                }
                if($trap?($out&&!$in):($in&&!$out)){
                    $valid=false;
                    break;
                }
            }
            if($valid)$all[]=$mask;
        }
        $r=[];
        foreach($all as$m){
            $minimal=true;
            foreach($all as$s)if($s!==$m&&($s&$m)===$s){
                $minimal=false;
                break;
            }
            if($minimal)$r[]=$m;
        }
        $bits=function($m){
            $a=[];
            foreach($this->p as$i=>$name)if($m&(1<<$i))$a[]=$i;
            return $a;
        };
        usort($r,function($a,$b)use($bits){
            $x=$bits($a);$y=$bits($b);return(count($x)<=>count($y))?:($x<=>$y);
        });
        return $r;
    }
    public function setText(int $mask):string{
        $a=[];
        foreach($this->p as$p=>$name)if($mask&(1<<$p))$a[]=$name;
        return'{'.implode(',',$a).'}';
    }
    public function realize(array $counts):?array {
        $used=array_fill(0,count($counts),0);
        $stack=[$this->current];
        $choices=[0];
        $path=[];
        $seen=[];
        $total=array_sum($counts);
        while($stack){
            $d=count($path);
            if($d===$total)return $path;
            $chosen=-1;
            for($t=$choices[$d];$t<count($counts);++$t){
                $choices[$d]=$t+1;
                if($used[$t]>=$counts[$t]||$this->reason($stack[$d],$t)!=='')continue;
                ++$used[$t];
                $key=implode(',',$used);
                --$used[$t];
                if(isset($seen[$key]))continue;
                $seen[$key]=true;
                $chosen=$t;
                break;
            }
            if($chosen>=0){
                ++$used[$chosen];
                $path[]=$chosen;
                $stack[]=$this->fire($stack[$d],$chosen);
                $choices[]=0;
            }else{
                array_pop($stack);
                array_pop($choices);
                if($path)--$used[array_pop($path)];
            }
        }
        return null;
    }
    public function invariants(bool $transpose):void {
        $a=[];
        foreach($this->p as$p=>$name){
            $r=[];
            foreach($this->t as$t=>$name)$r[]=$this->post[$p][$t]-$this->pre[$p][$t];
            $a[]=$r;
        }
        if($transpose){
            $b=[];
            foreach($this->t as$t=>$name)$b[]=array_column($a,$t);
            $a=$b;
        }
        $f=flows($a);
        $names=$transpose?$this->t:$this->p;
        $bounds=array_fill(0,count($names),-1);
        $covered=array_fill(0,count($names),false);
        echo($transpose?'T':'P').'-semiflows: '.count($f)."\n";
        foreach($f as$c){
            $terms=[];
            $value=0;
            foreach($c as$i=>$v)if($v){
                $terms[]=($v===1?'':$v.'*').$names[$i];
                $covered[$i]=true;
                if(!$transpose)$value+=$v*$this->current[$i];
            }
            echo'  '.implode(' + ',$terms);
            if($transpose){
                $path=$this->realize($c);
                echo': '.($path===null?'not realizable':'realizable '.implode(' ',$this->names($path)))."\n";
            }else{
                echo' = '.$value."\n";
                foreach($c as$p=>$v)if($v){
                    $b=intdiv($value,$v);
                    $bounds[$p]=$bounds[$p]<0?$b:min($bounds[$p],$b);
                }
            }
        }
        if(!$transpose)echo'bounds: ('.implode(',',array_map(fn($v)=>$v<0?'-':(string)$v,$bounds)).")\n";
        echo($transpose?'consistent: ':'conservative: ').yn(!in_array(false,$covered,true))."\n";
    }
    public function classify():void {
        $ordinary=$pure=$sm=$mg=$fc=$efc=true;
        $inputs=array_fill(0,count($this->t),[]);
        $outputs=array_fill(0,count($this->p),[]);
        foreach($this->p as$p=>$name)foreach($this->t as$t=>$name){
            $ordinary=$ordinary&&$this->pre[$p][$t]<=1&&$this->post[$p][$t]<=1;
            $pure=$pure&&!($this->pre[$p][$t]&&$this->post[$p][$t]);
            if($this->pre[$p][$t]){
                $inputs[$t][]=$p;
                $outputs[$p][]=$t;
            }
        }
        foreach($inputs as$t=>$a){
            $n=0;
            foreach($this->p as$p=>$name)$n+=(int)($this->post[$p][$t]>0);
            $sm=$sm&&count($a)===1&&$n===1;
        }
        foreach($outputs as$p=>$a){
            $n=0;
            foreach($this->t as$t=>$name)$n+=(int)($this->post[$p][$t]>0);
            $mg=$mg&&count($a)===1&&$n===1;
            foreach($a as$t)if(count($a)!==1&&count($inputs[$t])!==1)$fc=false;
            foreach($outputs as$b)if(array_intersect($a,$b)&&$a!==$b)$efc=false;
        }
        $sm=$sm&&$ordinary;
        $mg=$mg&&$ordinary;
        $fc=$fc&&$ordinary;
        $efc=$efc&&$ordinary;
        foreach(['ordinary'=>$ordinary,'pure'=>$pure,'state machine'=>$sm,'marked graph'=>$mg,'free choice'=>$fc,'extended free choice'=>$efc]as$label=>$v)echo$label.': '.yn($v)."\n";
        $verdict=!$fc?'not applicable':(count($this->p)>12?'too many places':'holds');
        if($fc&&count($this->p)<=12){
            $traps=$this->sets(true);
            foreach($this->sets(false)as$s){
                $holds=false;
                foreach($traps as$q)if(($s&$q)===$q)foreach($this->current as$p=>$v)if($v>0&&($q&(1<<$p)))$holds=true;
                if(!$holds){
                    $verdict='fails at '.$this->setText($s);
                    break;
                }
            }
        }
        echo'commoner: '.$verdict."\n";
    }
    public function workflow(int $limit):void {
        $sources=$sinks=[];
        $P=count($this->p);
        foreach($this->p as$p=>$name){
            $in=$out=false;
            foreach($this->t as$t=>$name){
                $in=$in||$this->post[$p][$t]>0;
                $out=$out||$this->pre[$p][$t]>0;
            }
            if(!$in)$sources[]=$p;
            if(!$out)$sinks[]=$p;
        }
        if(count($sources)!==1){
            echo'workflow: no ('.count($sources)." source places)\n";
            return;
        }
        if(count($sinks)!==1){
            echo'workflow: no ('.count($sinks)." sink places)\n";
            return;
        }
        $i=$sources[0];
        $o=$sinks[0];
        $names=array_merge($this->p,$this->t);
        $adj=$rev=array_fill(0,count($names),[]);
        foreach($this->p as$p=>$name)foreach($this->t as$t=>$name){
            if($this->pre[$p][$t]){
                $adj[$p][]=$P+$t;
                $rev[$P+$t][]=$p;
            }
            if($this->post[$p][$t]){
                $adj[$P+$t][]=$p;
                $rev[$p][]=$P+$t;
            }
        }
        $f=visit($adj,$i);
        $b=visit($rev,$o);
        foreach($names as$v=>$name)if(!$f[$v]||!$b[$v]){
            echo"workflow: no ($name is not on a path from {$this->p[$i]} to {$this->p[$o]})\n";
            return;
        }
        echo"workflow: source {$this->p[$i]} sink {$this->p[$o]}\n";
        $start=$goal=array_fill(0,$P,0);
        $start[$i]=1;
        $goal[$o]=1;
        $g=$this->graph($start,$limit);
        if($g['aborted']){
            echo"reachability graph limit $limit exceeded\n";
            return;
        }
        $end=array_search($goal,$g['states'],true);
        $rev=array_fill(0,count($g['states']),[]);
        $used=array_fill(0,count($this->t),false);
        $proper=true;
        foreach($g['states']as$u=>$m){
            if($m[$o]>=1&&$m!==$goal)$proper=false;
            foreach($g['edges'][$u]as[$t,$v]){
                $rev[$v][]=$u;
                $used[$t]=true;
            }
        }
        $option=$end!==false&&!in_array(false,visit($rev,$end),true);
        $live=!in_array(false,$used,true);
        echo'option to complete: '.yn($option)."\nproper completion: ".yn($proper)."\nno dead transitions: ".yn($live)."\nsound: ".yn($option&&$proper&&$live)."\n";
    }
    public function execute(array $w):void {
        $cmd=$w[0];
        $arity=['MARKING'=>0,'RESET'=>0,'SET'=>2,'ENABLED'=>0,'FIRE'=>-1,'UNDO'=>1,'SIMULATE'=>3,'CONFLICTS'=>0,'REACH'=>1,'GRAPH'=>1,'COVER'=>1,'PATH'=>2,'INCIDENCE'=>0,'PINV'=>0,'TINV'=>0,'SIPHONS'=>0,'TRAPS'=>0,'CLASSIFY'=>0,'WORKFLOW'=>1,'SHOW'=>0];
        if(!array_key_exists($cmd,$arity))bad('unknown command '.$cmd);
        if($arity[$cmd]<0?count($w)<2:count($w)!==$arity[$cmd]+1)bad('wrong number of arguments');
        $limit=0;
        if(in_array($cmd,['REACH','GRAPH','COVER','PATH','WORKFLOW'],true)){
            $limit=number($w[1],1,2000);
            if($limit<0)bad('invalid limit '.$w[1]);
        }
        switch($cmd){
            case'MARKING':case'RESET':if($cmd==='RESET'){
                $this->current=$this->initial;
                $this->history=[];
            }
            echo'marking '.mark($this->current)."\n";
            break;
            case'SET':$p=array_search($w[1],$this->p,true);
            if($p===false)bad('unknown place '.$w[1]);
            $v=number($w[2],0,999);
            if($v<0)bad('invalid tokens '.$w[2]);
            if($this->cap[$p]&&$v>$this->cap[$p])bad('tokens exceed capacity of '.$w[1]);
            $this->current[$p]=$v;
            $this->history=[];
            echo'marking '.mark($this->current)."\n";
            break;
            case'ENABLED':echo'enabled: '.listed($this->names($this->enabled($this->current)))."\n";
            break;
            case'FIRE':$ts=[];
            foreach(array_slice($w,1)as$name){
                $t=array_search($name,$this->t,true);
                if($t===false)bad('unknown transition '.$name);
                $ts[]=$t;
            }
            foreach($ts as$i=>$t){
                $r=$this->reason($this->current,$t);
                if($r!==''){
                    echo'step '.($i+1).": {$this->t[$t]} not enabled ($r) at ".mark($this->current)."\n";
                    return;
                }
                $this->commit($t);
            }
            echo'fired '.count($ts).' -> '.mark($this->current)."\n";
            break;
            case'UNDO':$k=number($w[1],1,1000);
            if($k<0)bad('invalid count '.$w[1]);
            $h=count($this->history);
            if($k>$h)bad("cannot undo $k: history size $h");
            $this->current=$this->history[$h-$k];
            $this->history=array_slice($this->history,0,$h-$k);
            echo'marking '.mark($this->current)."\n";
            break;
            case'SIMULATE':$steps=number($w[1],1,1000);
            $x=number($w[2],1,2147483646);
            if($steps<0)bad('invalid steps '.$w[1]);
            if($x<0)bad('invalid seed '.$w[2]);
            if(!in_array($w[3],['PRIORITY','RANDOM'],true))bad('invalid mode '.$w[3]);
            $counts=array_fill(0,count($this->t),0);
            for($done=0;$done<$steps;++$done){
                $e=$this->enabled($this->current);
                if(!$e){
                    echo"dead (steps=$done)\n";
                    break;
                }
                $t=$e[0];
                if($w[3]==='RANDOM'){
                    $x=$x*48271%2147483647;
                    $t=$e[$x%count($e)];
                }else foreach($e as$u)if($this->priority[$u]>$this->priority[$t])$t=$u;
                $this->commit($t);
                ++$counts[$t];
                echo'step '.($done+1).': '.$this->t[$t].' -> '.mark($this->current)."\n";
            }
            if($done===$steps)echo"completed (steps=$steps)\n";
            $a=[];
            foreach($this->t as$t=>$name)$a[]=$name.'='.$counts[$t];
            echo'counts: '.implode(' ',$a)."\n";
            break;
            case'CONFLICTS':$s=$e=[];
            for($u=0;$u<count($this->t);++$u)for($v=$u+1;$v<count($this->t);++$v){
                $pair=$this->t[$u].'/'.$this->t[$v];
                $conflict=false;
                foreach($this->p as$p=>$name)if($this->pre[$p][$u]&&$this->pre[$p][$v])$conflict=true;
                if($conflict)$s[]=$pair;
                if($this->reason($this->current,$u)===''&&$this->reason($this->current,$v)===''&&($this->reason($this->fire($this->current,$u),$v)!==''||$this->reason($this->fire($this->current,$v),$u)!==''))$e[]=$pair;
            }
            echo'structural: '.listed($s)."\neffective: ".listed($e)."\n";
            break;
            case'REACH':case'GRAPH':$this->reach($limit,$cmd==='GRAPH');
            break;
            case'COVER':$this->cover($limit);
            break;
            case'PATH':$entries=explode(',',$w[2]);
            if(count($entries)!==count($this->p))bad('target needs '.count($this->p).' entries');
            $target=[];
            foreach($entries as$s){
                if($s==='*'){
                    $target[]=[0,-1];
                    continue;
                }
                $plus=str_ends_with($s,'+');
                $v=number($plus?substr($s,0,-1):$s,0,9999999999);
                if($v<0)bad('invalid target entry '.$s);
                $target[]=[$v,$plus?-1:$v];
            }
            $g=$this->graph($this->current,$limit,$target);
            if($g['found']>=0){
                $a=$this->names($this->path($g,$g['found']));
                echo'reached '.mark($g['states'][$g['found']]).' length='.count($a).($a?': '.implode(' ',$a):'')."\n";
            }
            elseif($g['aborted'])echo"search limit $limit exceeded\n";
            else echo'unreachable (markings explored: '.count($g['states']).")\n";
            break;
            case'INCIDENCE':$rows=[array_merge([''],$this->t)];
            foreach($this->p as$p=>$name){
                $r=[$name];
                foreach($this->t as$t=>$name)$r[]=(string)($this->post[$p][$t]-$this->pre[$p][$t]);
                $rows[]=$r;
            }
            $width=array_fill(0,count($this->t)+1,0);
            foreach($rows as$r)foreach($r as$i=>$s)$width[$i]=max($width[$i],strlen($s));
            foreach($rows as$r){
                $a=[];
                foreach($r as$i=>$s)$a[]=str_pad($s,$width[$i],' ',$i?STR_PAD_LEFT:STR_PAD_RIGHT);
                echo rtrim(implode('  ',$a))."\n";
            }
            break;
            case'PINV':case'TINV':$this->invariants($cmd==='TINV');
            break;
            case'SIPHONS':case'TRAPS':if(count($this->p)>12)bad('more than 12 places');
            $sets=$this->sets($cmd==='TRAPS');
            echo'minimal '.($cmd==='TRAPS'?'traps':'siphons').': '.count($sets)."\n";
            foreach($sets as$s){
                $tokens=0;
                foreach($this->current as$p=>$v)if($s&(1<<$p))$tokens+=$v;
                echo'  '.$this->setText($s).' tokens='.$tokens."\n";
            }
            break;
            case'CLASSIFY':$this->classify();
            break;
            case'WORKFLOW':$this->workflow($limit);
            break;
            case'SHOW':foreach($this->p as$p=>$name)echo"place $name tokens={$this->initial[$p]} capacity=".($this->cap[$p]?:'none')."\n";
            foreach($this->t as$t=>$name){
                $lists=[];
                foreach([$this->pre,$this->post,$this->inh]as$matrix){
                    $a=[];
                    foreach($this->p as$p=>$pn)if($matrix[$p][$t])$a[]=$pn.':'.$matrix[$p][$t];
                    $lists[]=$a?implode(',',$a):'-';
                }
                echo"transition $name priority={$this->priority[$t]} pre={$lists[0]} post={$lists[1]} inhibit={$lists[2]}\n";
            }
            break;
        }
    }
}
$blocks=(int)trim(fgets(STDIN));
for($b=0;$b<$blocks;++$b){
    $net=new Net(explode(' ',trim(fgets(STDIN)))[1]);
    while(($line=rtrim(fgets(STDIN),"\r\n"))!=='END NET'){
        try{
            $net->define(explode(' ',$line));
        }catch(RuntimeException $e){
            echo'error: '.$e->getMessage()."\n";
        }
    }
    $net->current=$net->initial;
    echo"net {$net->name}: places=".count($net->p).' transitions='.count($net->t)." arcs={$net->arcs} inhibitors={$net->inhibitors}\n";
    $n=(int)trim(fgets(STDIN));
    for($i=0;$i<$n;++$i){
        try{
            $net->execute(explode(' ',rtrim(fgets(STDIN),"\r\n")));
        }catch(RuntimeException $e){
            echo'error: '.$e->getMessage()."\n";
        }
    }
}
