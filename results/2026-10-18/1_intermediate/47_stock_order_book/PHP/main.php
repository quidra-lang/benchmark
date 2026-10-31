<?php
declare(strict_types=1);
final class CommandError extends RuntimeException {
}
function dec(int $n): string {
    return intdiv($n,100).'.'.str_pad((string)($n%100),2,'0',STR_PAD_LEFT);
}
final class Order {
    public int $remaining, $quantity, $visible=0, $filled=0, $value=0, $priority=0;
    public string $status='INCOMING';
    public array $history=['ACCEPT'];
    public function __construct(public string $id, public string $trader, public string $kind, public string $side,
    int $q, public ?int $price=null, public ?int $trigger=null, public ?int $peak=null, public ?string $condition=null) {
        $this->quantity=$this->remaining=$q;
    }
    public function active(): bool {
        return in_array($this->status,['PENDING','OPEN','PARTIAL'],true);
    }
    public function resting(): bool {
        return in_array($this->status,['OPEN','PARTIAL'],true);
    }
    public function matches(int $p): bool {
        return $this->price===null || ($this->side==='BUY' ? $p<=$this->price : $p>=$this->price);
    }
    public function triggered(int $p): bool {
        return $this->side==='BUY' ? $p >= $this->trigger : $p <= $this->trigger;
    }
    public function line(): string {
        return "ORDER {$this->id} {$this->status} {$this->filled}/{$this->quantity}";
    }
    public function details(): string {
        $p=$this->price??'-';
        $avg=$this->filled===0?'-':dec(intdiv($this->value*100,$this->filled));
        return "{$this->id} {$this->trader} {$this->kind} {$this->side} $p {$this->status} {$this->filled}/{$this->quantity} avg $avg".($this->trigger===null?'':" trigger {$this->trigger}");
    }
}
final class Trader {
    public int $bought=0,$sold=0,$cash=0,$fees=0;
    public ?int $limit=null;
    public function __construct(public string $name) {
    }
    public function net(): int {
        return $this->bought-$this->sold;
    }
    public function volume(): int {
        return $this->bought+$this->sold;
    }
    public function pnl(int $mark): int {
        return $this->cash+$this->net()*$mark;
    }
    public function line(int $mark): string {
        return "POSITION {$this->name} bought {$this->bought} sold {$this->sold} net ".$this->net()." cash {$this->cash} fees {$this->fees} pnl ".$this->pnl($mark);
    }
}
final readonly class Trade {
    public function __construct(public int $number, public int $price, public int $quantity, public Order $buy, public Order $sell, public Order $taker, public int $buyFee, public int $sellFee) {
    }
    public function line(): string {
        return "TRADE {$this->number} {$this->price} {$this->quantity} {$this->buy->id} {$this->buy->trader} {$this->sell->id} {$this->sell->trader}";
    }
}
final class Engine {
    private array $orders=[],$traders=[],$trades=[];
    private int $maker=0,$taker=0,$band=0,$priority=0,$tick=1,$lot=1;
    private bool $halted=false;
    private function emit(mixed ...$parts): void {
        echo implode(' ',$parts),"\n";
    }
    private function check(bool $bad,string $reason): void {
        if($bad) throw new CommandError($reason);
    }
    private function opposite(string $side): string {
        return $side==='BUY'?'SELL':'BUY';
    }
    private function resting(string $side): array {
        return array_values(array_filter($this->orders,fn(Order $o)=>$o->side===$side&&$o->resting()));
    }
    private function best(string $side): ?Order {
        $os=$this->resting($side);
        usort($os,fn(Order $a,Order $b)=>($side==='BUY'?$b->price<=>$a->price:$a->price<=>$b->price)?:$a->priority<=>$b->priority);
        return $os[0]??null;
    }
    private function active(string $name): array {
        return array_values(array_filter($this->orders,fn(Order $o)=>$o->trader===$name&&$o->active()));
    }
    private function register(string $name): Trader {
        return $this->traders[$name]??=new Trader($name);
    }
    private function order(string $id): Order {
        return $this->orders[$id]??throw new CommandError('unknown order');
    }
    private function trader(string $name): Trader {
        return $this->traders[$name]??throw new CommandError('unknown trader');
    }
    private function last(): ?int {
        return $this->trades===[]?null:$this->trades[array_key_last($this->trades)]->price;
    }
    private function exposure(string $name,string $side,?Order $excluded=null): int {
        $v=$this->traders[$name]->net()*($side==='BUY'?1:-1);
        foreach($this->active($name) as $o) if($o!==$excluded&&$o->side===$side) $v+=$o->remaining;
        return $v;
    }
    private function risk(string $name,string $side,int $q,?Order $excluded=null): void {
        $t=$this->traders[$name]??null;
        if($t!==null&&$t->limit!==null) $this->check($this->exposure($name,$side,$excluded)+$q>$t->limit,'risk limit');
    }
    private function checkBand(int $p): void {
        $l=$this->last();
        $this->check($this->band>0&&$l!==null&&abs($p-$l)>$this->band,'outside band');
    }
    private function levels(string $side): array {
        $ls=[];
        foreach($this->resting($side) as $o) {
            $ls[$o->price]??=[$o->price,0,0];
            $ls[$o->price][1]+=$o->visible;
            $ls[$o->price][2]++;
        }
        if($side==='BUY') krsort($ls,SORT_NUMERIC);
        else ksort($ls,SORT_NUMERIC);
        return array_values($ls);
    }
    private function cancel(Order $o): void {
        $o->history[]="CANCEL {$o->remaining}";
        $o->remaining=$o->visible=0;
        $o->status='CANCELLED';
        $this->emit($o->line());
    }
    private function match(Order $o): void {
        while($o->remaining>0) {
            $y=$this->best($this->opposite($o->side));
            if($y===null||!$o->matches($y->price)) break;
            if($y->trader===$o->trader) {
                $this->emit('STP',$y->id,$y->remaining);
                $y->history[]="STP {$y->remaining}";
                $y->remaining=$y->visible=0;
                $y->status='CANCELLED';
                continue;
            }
            $q=min($o->remaining,$y->visible);
            $p=$y->price;
            [$buy,$sell]=$o->side==='BUY'?[$o,$y]:[$y,$o];
            [$bf,$sf]=$o->side==='BUY'?[$q*$this->taker,$q*$this->maker]:[$q*$this->maker,$q*$this->taker];
            $tr=new Trade(count($this->trades)+1,$p,$q,$buy,$sell,$o,$bf,$sf);
            $this->trades[]=$tr;
            foreach([$o,$y] as $x) {
                $x->remaining-=$q;
                $x->filled+=$q;
                $x->value+=$q*$p;
                $x->history[]="FILL {$tr->number} $p $q";
            }
            $y->visible-=$q;
            $bt=$this->traders[$buy->trader];
            $st=$this->traders[$sell->trader];
            $bt->bought+=$q;
            $bt->cash-=$q*$p+$bf;
            $bt->fees+=$bf;
            $st->sold+=$q;
            $st->cash+=$q*$p-$sf;
            $st->fees+=$sf;
            $this->emit($tr->line());
            $y->status=$y->remaining===0?'FILLED':'PARTIAL';
            if($y->remaining>0&&$y->visible===0) {
                $y->priority=++$this->priority;
                $y->visible=min($y->peak,$y->remaining);
                $h=$y->remaining-$y->visible;
                $y->history[]="REFRESH {$y->visible} $h";
                $this->emit('REFRESH',$y->id,$y->visible,$h);
            }
        }
    }
    private function finish(Order $o,bool $force=false): void {
        if($o->remaining===0) $o->status='FILLED';
        elseif($force||($o->kind==='LIMIT'&&$o->condition!=='IOC')||in_array($o->kind,['ICEBERG','STOPLIMIT'],true)) {
            $o->priority=++$this->priority;
            $o->visible=min($o->peak??$o->remaining,$o->remaining);
            $o->status=$o->filled===0?'OPEN':'PARTIAL';
            $o->history[]="REST {$o->price} {$o->visible}";
        } else {
            $o->history[]="EXPIRE {$o->remaining}";
            $o->remaining=0;
            $o->status='CANCELLED';
        }
        $this->emit($o->line());
    }
    private function triggers(): void {
        while($this->last()!==null) {
            $last=$this->last();
            $selected=array_filter($this->orders,fn(Order $o)=>$o->status==='PENDING'&&$o->triggered($last));
            if($selected===[]) break;
            foreach($selected as $o) $o->status='TRIGGERING';
            foreach($selected as $o) {
                $this->emit('TRIGGER',$o->id);
                $o->history[]='TRIGGER';
                $this->match($o);
                $this->finish($o);
            }
        }
    }
    private function submit(string $c,array $a): void {
        [$id,$name,$side]=$a;
        $p=$r=$peak=$cond=null;
        if($c==='MARKET') $q=(int)$a[3];
        elseif($c==='STOP') {
            $r=(int)$a[3];
            $q=(int)$a[4];
        } elseif($c==='STOPLIMIT') {
            $r=(int)$a[3];
            $p=(int)$a[4];
            $q=(int)$a[5];
        } else {
            $p=(int)$a[3];
            $q=(int)$a[4];
            if($c==='ICEBERG') $peak=(int)$a[5];
            if($c==='LIMIT') $cond=$a[5]??null;
        }
        $prices=array_filter([$r,$p],fn($x)=>$x!==null);
        $this->check($this->halted,'halted');
        $this->check(isset($this->orders[$id]),'duplicate id');
        $this->check(in_array(0,$prices,true),'invalid price');
        $this->check($q===0,'invalid quantity');
        foreach($prices as $price) $this->check($price%$this->tick!==0,'invalid tick');
        $this->check($q%$this->lot!==0,'invalid lot');
        $o=new Order($id,$name,$c,$side,$q,$p,$r,$peak,$cond);
        $this->check($peak!==null&&($peak===0||$peak>$q||$peak%$this->lot!==0),'invalid peak');
        $this->check($r!==null&&$this->last()!==null&&$o->triggered($this->last()),'invalid trigger');
        if($p!==null) $this->checkBand($p);
        $this->risk($name,$side,$q);
        $y=$this->best($this->opposite($side));
        $this->check($cond==='POSTONLY'&&$y!==null&&$o->matches($y->price),'would cross');
        $v=0;
        foreach($this->resting($this->opposite($side)) as $x) if($x->trader!==$name&&$o->matches($x->price)) $v+=$x->remaining;
        $this->check($cond==='FOK'&&$v<$q,'unfillable');
        $this->register($name);
        $this->orders[$id]=$o;
        if($r!==null) {
            $o->status='PENDING';
            $this->emit($o->line());
        } else {
            if($cond!=='POSTONLY') $this->match($o);
            $this->finish($o);
            $this->triggers();
        }
    }
    private function replace(array $a): void {
        [$id,$p,$q]=[$a[0],(int)$a[1],(int)$a[2]];
        $this->check($this->halted,'halted');
        $o=$this->order($id);
        $this->check(!$o->resting(),'not open');
        $this->check($p===0,'invalid price');
        $this->check($q===0,'invalid quantity');
        $moved=$p!==$o->price;
        $this->check($moved&&$p%$this->tick!==0,'invalid tick');
        $this->check($q%$this->lot!==0,'invalid lot');
        $this->check(!$moved&&$q===$o->remaining,'no change');
        if($moved) $this->checkBand($p);
        if($q>$o->remaining) $this->risk($o->trader,$o->side,$q,$o);
        $kept=!$moved&&$q<$o->remaining;
        $o->quantity=$o->filled+$q;
        $o->remaining=$q;
        $word=$kept?'kept':'lost';
        $o->history[]="REPLACE $p $q $word";
        $this->emit('REPLACE',$id,$word);
        if($kept) {
            $o->visible=min($o->visible,$q);
            $this->emit($o->line());
        } else {
            $o->price=$p;
            $o->status='INCOMING';
            $this->match($o);
            $this->finish($o,true);
            $this->triggers();
        }
    }
    private function bar(array $ts): string {
        $ps=array_map(fn(Trade $t)=>$t->price,$ts);
        $v=array_sum(array_map(fn(Trade $t)=>$t->quantity,$ts));
        return 'open '.$ps[0].' high '.max($ps).' low '.min($ps).' close '.$ps[count($ps)-1].' volume '.$v;
    }
    public function execute(string $line): void {
        $a=explode(' ',trim($line));
        $c=array_shift($a);
        try {
            if(in_array($c,['LIMIT','MARKET','STOP','STOPLIMIT','ICEBERG'],true)) {
                $this->submit($c,$a);
                return;
            }
            switch($c) {
                case 'CANCEL':
                    $o=$this->order($a[0]);
                    $this->check(!$o->active(),'not open');
                    $this->cancel($o);
                    break;
                case 'REPLACE':
                    $this->replace($a);
                    break;
                case 'CANCELALL':
                    $this->trader($a[0]);
                    $os=$this->active($a[0]);
                    $this->emit($c,$a[0],count($os));
                    foreach($os as $o) $this->cancel($o);
                    break;
                case 'HALT':
                case 'RESUME':
                    $this->check($c==='HALT'?$this->halted:!$this->halted,$c==='HALT'?'already halted':'not halted');
                    $this->halted=$c==='HALT';
                    $this->emit($c);
                    break;
                case 'RISK':
                    $this->register($a[0])->limit=(int)$a[1];
                    $this->emit($c,...[...$a,'exposure buy',$this->exposure($a[0],'BUY'),'sell',$this->exposure($a[0],'SELL')]);
                    break;
                case 'FEE':
                    [$m,$t]=array_map('intval',$a);
                    $this->check($m+$t<0,'invalid fee');
                    $this->maker=$m;
                    $this->taker=$t;
                    $this->emit($c,'maker',$m,'taker',$t);
                    break;
                case 'BAND':
                    $this->band=(int)$a[0];
                    $this->emit($c,$this->band);
                    break;
                case 'TICK':
                case 'LOT':
                    $n=(int)$a[0];
                    $this->check($n===0,'invalid size');
                    if($c==='TICK') $this->tick=$n;
                    else $this->lot=$n;
                    $this->emit($c,$n);
                    break;
                case 'BOOK':
                    $n=(int)$a[0];
                    $this->check($n===0,'invalid depth');
                    $bs=$this->levels('BUY');
                    $ss=$this->levels('SELL');
                    $this->emit($c,'bids',count($bs),'asks',count($ss));
                    foreach(array_reverse(array_slice($ss,0,$n)) as $v) $this->emit('ASK',...$v);
                    foreach(array_slice($bs,0,$n) as $v) $this->emit('BID',...$v);
                    break;
                case 'ORDERS':
                    $this->trader($a[0]);
                    $os=$this->active($a[0]);
                    $this->emit($c,$a[0],count($os));
                    foreach($os as $o) $this->emit($o->details());
                    break;
                case 'STATUS':
                    $this->emit($c,$this->order($a[0])->details());
                    break;
                case 'HISTORY':
                    $o=$this->order($a[0]);
                    $this->emit($c,$o->id,count($o->history));
                    foreach($o->history as $h) $this->emit($h);
                    break;
                case 'POSITION':
                    $this->emit($this->trader($a[0])->line($this->last()??0));
                    break;
                case 'FILLS':
                    $this->trader($a[0]);
                    $ts=array_filter($this->trades,fn(Trade $t)=>$t->buy->trader===$a[0]||$t->sell->trader===$a[0]);
                    $this->emit($c,$a[0],count($ts));
                    $net=0;
                    foreach($ts as $t) {
                        $b=$t->buy->trader===$a[0];
                        $o=$b?$t->buy:$t->sell;
                        $net+=$b?$t->quantity:-$t->quantity;
                        $this->emit($t->number,$o->side,$t->price,$t->quantity,$o->id,$t->taker===$o?'TAKER':'MAKER','fee',$b?$t->buyFee:$t->sellFee,'net',$net);
                    }
                    break;
                case 'LAST':
                    if($this->trades===[]) $this->emit($c,'none');
                    else {
                        $t=$this->trades[array_key_last($this->trades)];
                        $this->emit($c,$t->price,$t->quantity);
                    }
                    break;
                case 'VWAP':
                    if($this->trades===[]) $this->emit($c,'none');
                    else {
                        $v=$amount=0;
                        foreach($this->trades as $t) {
                            $v+=$t->quantity;
                            $amount+=$t->price*$t->quantity;
                        }
                        $this->emit($c,dec(intdiv($amount*100,$v)),'volume',$v,'trades',count($this->trades));
                    }
                    break;
                case 'SPREAD':
                    $b=$this->best('BUY');
                    $s=$this->best('SELL');
                    $text='SPREAD bid '.($b?->price??'none').' ask '.($s?->price??'none');
                    if($b!==null&&$s!==null) {
                        $n=$b->price+$s->price;
                        $text.=' spread '.($s->price-$b->price).' mid '.intdiv($n,2).'.'.($n%2?5:0);
                    }
                    $this->emit($text);
                    break;
                case 'IMPACT':
                    $side=$a[0];
                    $q=(int)$a[1];
                    $this->check($q===0,'invalid quantity');
                    $ls=$this->levels($this->opposite($side));
                    $r=$q;
                    $cost=$used=$worst=$total=0;
                    foreach($ls as [$p,$v]) {
                        $total+=$v;
                        if($r===0) continue;
                        $u=min($r,$v);
                        $r-=$u;
                        $cost+=$u*$p;
                        $worst=$p;
                        $used++;
                    }
                    $this->emit($c,$side,$q,...($r>0?['insufficient',$total]:['avg',dec(intdiv($cost*100,$q)),'worst',$worst,'levels',$used]));
                    break;
                case 'TRADES':
                case 'BARS':
                    $k=(int)$a[0];
                    $this->check($k===0,'invalid count');
                    if($c==='TRADES') {
                        $ts=array_slice($this->trades,-$k);
                        $this->emit($c,count($ts),'of',count($this->trades));
                        foreach($ts as $t) $this->emit($t->line());
                    } else {
                        $gs=array_chunk($this->trades,$k);
                        $this->emit($c,count($gs));
                        foreach($gs as $i=>$g) $this->emit($i+1,$this->bar($g));
                    }
                    break;
                case 'RANK':
                    $ts=array_values($this->traders);
                    $mark=$this->last()??0;
                    usort($ts,fn(Trader $x,Trader $y)=>($y->pnl($mark)<=>$x->pnl($mark))?:($y->volume()<=>$x->volume())?:strcmp($x->name,$y->name));
                    $this->emit($c,count($ts));
                    foreach($ts as $i=>$t) $this->emit($i+1,$t->name,'pnl',$t->pnl($mark),'volume',$t->volume());
                    break;
                case 'FLOW':
                    $b=$s=0;
                    foreach($this->trades as $t) {
                        if($t->taker->side==='BUY') $b+=$t->quantity;
                        else $s+=$t->quantity;
                    }
                    $this->emit($c,'buy',$b,'sell',$s,'net',$b-$s);
                    break;
                case 'SUMMARY':
                    if($this->trades===[]) $this->emit($c,'trades',0);
                    else {
                        $ps=[];
                        $v=$fees=0;
                        foreach($this->trades as $t) {
                            $ps[]=$t->price;
                            $v+=$t->quantity;
                            $fees+=$t->buyFee+$t->sellFee;
                        }
                        $this->emit($c,'trades',count($ps),'volume',$v,'open',$ps[0],'high',max($ps),'low',min($ps),'close',$ps[count($ps)-1],'fees',$fees);
                    }
                    $names=array_keys($this->traders);
                    sort($names,SORT_STRING);
                    foreach($names as $name) $this->emit($this->traders[$name]->line($this->last()??0));
                    break;
            }
        } catch(CommandError $e) {
            $prefix=in_array($c,['LIMIT','MARKET','STOP','STOPLIMIT','ICEBERG','CANCEL','REPLACE'],true)?['REJECT',$a[0]]:['ERROR'];
            $this->emit(...[...$prefix,$e->getMessage()]);
        }
    }
}
$engine=new Engine();
$n=(int)fgets(STDIN);
for($i=0;$i<$n;$i++) $engine->execute(fgets(STDIN));
