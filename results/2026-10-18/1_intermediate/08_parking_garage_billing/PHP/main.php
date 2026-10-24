<?php
const TYPES = ['MOTORCYCLE','CAR','ECAR','VAN','BUS'];
const KINDS = ['MOTO','COMPACT','LARGE','EV'];
const PREFS = ['MOTORCYCLE'=>['MOTO','COMPACT','LARGE'],'CAR'=>['COMPACT','LARGE'],'ECAR'=>['EV','COMPACT','LARGE'],'VAN'=>['LARGE']];
$rates = ['MOTORCYCLE'=>[100,800],'CAR'=>[200,1600],'ECAR'=>[200,1600],'VAN'=>[300,2400],'BUS'=>[600,4800]];
$fees = ['NIGHT'=>300,'LOST'=>2000,'KWH'=>30];
$levels = [];
$spots = [];
$vehicles = [];
$queue = [];
$passes = [];
$history = [];
$stats = array_fill_keys(TYPES,array_fill_keys(['entries','exits','refused','stay','parking','night','lost','charge','total'],0));
$daily = [];
$now = 0;
$peak = 0;
$peakTime = 0;
function fail(string $message): never { throw new InvalidArgumentException($message); }
function date_of(int $time): int { return intdiv($time,1440)+1; }
function time_text(int $time): string { return date_of($time) . '-' . sprintf('%02d:%02d',intdiv($time%1440,60),$time%60); }
function duration(int $minutes): string { return intdiv($minutes,60) . ':' . sprintf('%02d',$minutes%60); }
function one_decimal(int $q): string { return intdiv($q,10) . '.' . $q%10; }
function valid_pass(string $plate,int $time): bool
{
    global $passes;
    return isset($passes[$plate]) && date_of($time)<=$passes[$plate];
}
function get_spot(string $id): object
{
    global $spots;
    if (!isset($spots[$id])) fail("unknown spot $id");
    return $spots[$id];
}
function get_vehicle(string $plate): object
{
    global $vehicles;
    if (!isset($vehicles[$plate])) fail("$plate is not parked");
    return $vehicles[$plate];
}
function location(object $v): string
{
    $s = $v->spots[0];
    return $v->type==='BUS' ? "L$s->level-$s->number.." . ($s->number+2) : $s->id;
}
function location_key(object $v): array { return [$v->spots[0]->level,$v->spots[0]->number]; }
function free_spot(object $s): bool { return !$s->closed && $s->plate===''; }
function assignment(string $type): array
{
    global $levels;
    if ($type==='BUS') {
        foreach ($levels as $level) {
            for ($i=0; $i+2<count($level); ++$i) {
                $triple = array_slice($level,$i,3);
                if (array_all($triple,fn($s)=>$s->kind==='LARGE' && free_spot($s))) return $triple;
            }
        }
    } else {
        foreach (PREFS[$type] as $kind) {
            foreach ($levels as $level) {
                foreach ($level as $s) if ($s->kind===$kind && free_spot($s)) return [$s];
            }
        }
    }
    return [];
}
function add_stat(string $type,string $field,int $amount,int $date): void
{
    global $stats,$daily;
    $stats[$type][$field] += $amount;
    if (in_array($field,['entries','exits','refused','total'],true)) {
        if (!isset($daily[$date])) {
            $daily[$date] = [];
            foreach (TYPES as $k) $daily[$date][$k] = array_fill_keys(['entries','exits','refused','revenue'],0);
        }
        $daily[$date][$type][$field==='total' ? 'revenue' : $field] += $amount;
    }
}
function park_vehicle(string $plate,string $type,array $chosen): object
{
    global $now,$vehicles,$peak,$peakTime;
    $v = (object)['plate'=>$plate,'type'=>$type,'spots'=>$chosen,'entry'=>$now,'kwh'=>0,'cost'=>0,'validation'=>0,'payment'=>null];
    foreach ($chosen as $s) $s->plate = $plate;
    $vehicles[$plate] = $v;
    add_stat($type,'entries',1,date_of($now));
    if (count($vehicles)>$peak) {
        $peak = count($vehicles);
        $peakTime = $now;
    }
    return $v;
}
function process_queue(array &$out): void
{
    global $queue,$now;
    $remaining = [];
    foreach ($queue as $waiting) {
        $chosen = assignment($waiting->type);
        if ($chosen===[]) {
            $remaining[] = $waiting;
        } else {
            $v = park_vehicle($waiting->plate,$waiting->type,$chosen);
            $out[] = "ADMIT $v->plate $v->type " . location($v) . ' waited ' . duration($now-$waiting->time);
        }
    }
    $queue = $remaining;
}
function giveups(): array
{
    global $queue,$now;
    $remaining = [];
    $out = [];
    foreach ($queue as $waiting) {
        if ($now-$waiting->time>=30) {
            $time = $waiting->time+30;
            $out[] = "GIVEUP $waiting->plate $waiting->type " . time_text($time);
            add_stat($waiting->type,'refused',1,date_of($time));
        } else {
            $remaining[] = $waiting;
        }
    }
    $queue = $remaining;
    return $out;
}
function interval_fee(object $v,int $a,int $b,int $free): array
{
    global $rates,$fees;
    $total = $b-$a;
    if (valid_pass($v->plate,$b) || $total<=$free) return [0,0];
    [$rate,$cap] = $rates[$v->type];
    $parking = 0;
    for ($i=0; $total>0; ++$i) {
        $minutes = min($total,1440);
        $billable = $minutes-($i===0 ? $free : 0);
        $parking += min(intdiv($billable+29,30)*$rate,$cap);
        $total -= $minutes;
    }
    return [$parking,(date_of($b)-date_of($a))*$fees['NIGHT']];
}
function charges(object $v,bool $lost=false): array
{
    global $now,$fees;
    if ($v->payment===null) {
        [$parking,$night] = interval_fee($v,$v->entry,$now,15+$v->validation);
        $loss = $lost ? $fees['LOST'] : 0;
        $total = $parking+$night+$loss+$v->cost;
        return [$parking,$night,$loss,$v->cost,$total,$total];
    }
    [$extra,$extraNight] = interval_fee($v,$v->payment->time,$now,15);
    $parking = $v->payment->parking+$extra;
    $night = $v->payment->night+$extraNight;
    return [$parking,$night,0,$v->cost,$parking+$night+$v->cost,$extra+$extraNight];
}
function fee_line(string $label,object $v,array $f): string
{
    global $now;
    return "$label $v->plate " . location($v) . ' stay ' . duration($now-$v->entry) . " parking $f[0] night $f[1] lost $f[2] charge $f[3] total $f[4] due $f[5]";
}
function annotation(object $v): string
{
    global $now;
    $text = valid_pass($v->plate,$now) ? ' PASS' : '';
    if ($v->validation!==0) $text .= " VAL $v->validation";
    if ($v->kwh!==0) $text .= " KWH $v->kwh";
    if ($v->payment!==null) $text .= ' PAID';
    return $text;
}
function move_vehicle(object $v,object $spot): string
{
    $old = location($v);
    $v->spots[0]->plate = '';
    $spot->plate = $v->plate;
    $v->spots = [$spot];
    return "MOVE $v->plate $old -> $spot->id";
}
function occupancy_line(string $label,array $used,array $available,int $closed): string
{
    $parts = [$label];
    foreach (KINDS as $kind) $parts = [...$parts,$kind,"$used[$kind]/$available[$kind]"];
    return implode(' ',$parts) . " closed $closed";
}
function execute(array $t): array
{
    global $now,$levels,$spots,$vehicles,$queue,$rates,$fees,$passes,$history,$stats,$daily,$peak,$peakTime;
    $cmd = $t[0];
    $out = [];
    if ($cmd==='LEVEL') {
        $levelNo = count($levels)+1;
        $level = [];
        foreach (KINDS as $index=>$kind) {
            for ($i=0; $i<(int)$t[$index+1]; ++$i) {
                $number = count($level)+1;
                $id = "L$levelNo-$number";
                $s = (object)['id'=>$id,'level'=>$levelNo,'number'=>$number,'kind'=>$kind,'closed'=>false,'plate'=>''];
                $spots[$id] = $s;
                $level[] = $s;
            }
        }
        $levels[] = $level;
        $out[] = "LEVEL $levelNo spots " . count($level) . " MOTO $t[1] COMPACT $t[2] LARGE $t[3] EV $t[4]";
    } elseif ($cmd==='CLOSE' || $cmd==='OPEN') {
        $s = get_spot($t[1]);
        if ($cmd==='CLOSE') {
            if ($s->closed) fail("spot $t[1] is already closed");
            if ($s->plate!=='') fail("spot $t[1] is occupied by $s->plate");
            $s->closed = true;
        } else {
            if (!$s->closed) fail("spot $t[1] is not closed");
            $s->closed = false;
        }
        $out[] = "$cmd $s->id $s->kind";
    } elseif ($cmd==='RATE') {
        if (!isset($rates[$t[1]])) fail("unknown type $t[1]");
        if ((int)$t[3]<(int)$t[2]) fail("cap below rate for $t[1]");
        $rates[$t[1]] = [(int)$t[2],(int)$t[3]];
        $out[] = "RATE $t[1] $t[2] $t[3]";
    } elseif ($cmd==='FEE') {
        if (!isset($fees[$t[1]])) fail("unknown fee $t[1]");
        $fees[$t[1]] = (int)$t[2];
        $out[] = "FEE $t[1] $t[2]";
    } elseif ($cmd==='ENTER') {
        [$plate,$type] = array_slice($t,1,2);
        if (!isset($rates[$type])) fail("unknown type $type");
        if (isset($vehicles[$plate])) fail("$plate is already parked at " . location($vehicles[$plate]));
        if (array_any($queue,fn($w)=>$w->plate===$plate)) fail("$plate is already waiting");
        $chosen = assignment($type);
        if ($chosen!==[]) {
            $v = park_vehicle($plate,$type,$chosen);
            $out[] = "ENTER $plate $type " . location($v);
        } elseif (count($queue)<3) {
            $queue[] = (object)['plate'=>$plate,'type'=>$type,'time'=>$now];
            $out[] = "WAIT $plate $type " . count($queue);
        } else {
            add_stat($type,'refused',1,date_of($now));
            $out[] = "FULL $plate $type";
        }
    } elseif ($cmd==='LEAVE') {
        $found = array_find_key($queue,fn($w)=>$w->plate===$t[1]);
        if ($found===null) fail("$t[1] is not waiting");
        $w = $queue[$found];
        array_splice($queue,$found,1);
        $out[] = "LEAVE $w->plate $w->type";
    } elseif (in_array($cmd,['EXIT','PAY','QUOTE','CHARGE','VALIDATE','MOVE'],true)) {
        $v = get_vehicle($t[1]);
        if ($cmd==='EXIT') {
            $lost = count($t)===3;
            if ($lost && $v->payment!==null) fail("$v->plate has already paid");
            $f = charges($v,$lost);
            $out[] = fee_line('EXIT',$v,$f);
            $record = (object)['entry'=>$v->entry,'exit'=>$now,'location'=>location($v),'type'=>$v->type,'total'=>$f[4],'lost'=>$lost];
            $history[$v->plate][] = $record;
            foreach ($v->spots as $s) $s->plate = '';
            unset($vehicles[$v->plate]);
            add_stat($v->type,'exits',1,date_of($now));
            add_stat($v->type,'stay',$now-$v->entry,date_of($now));
            foreach (['parking','night','lost','charge','total'] as $index=>$field) add_stat($v->type,$field,$f[$index],date_of($now));
        } elseif ($cmd==='PAY') {
            if ($v->payment!==null) fail("$v->plate has already paid");
            $f = charges($v);
            $v->payment = (object)['time'=>$now,'parking'=>$f[0],'night'=>$f[1]];
            $out[] = "PAY $v->plate parking $f[0] night $f[1] charge $f[3] total $f[4]";
        } elseif ($cmd==='QUOTE') {
            $out[] = fee_line('QUOTE',$v,charges($v));
        } elseif ($cmd==='CHARGE') {
            if ($v->type!=='ECAR') fail("$v->plate is not an electric car");
            if ($v->spots[0]->kind!=='EV') fail("$v->plate is not at a charger");
            if ($v->payment!==null) fail("$v->plate has already paid");
            $kwh = (int)$t[2];
            if ($v->kwh+$kwh>100) fail("charge limit exceeded for $v->plate");
            $cost = $kwh*$fees['KWH'];
            $v->kwh += $kwh;
            $v->cost += $cost;
            $out[] = "CHARGE $v->plate kwh $kwh cost $cost stay_kwh $v->kwh stay_cost $v->cost";
        } elseif ($cmd==='VALIDATE') {
            if ($v->payment!==null) fail("$v->plate has already paid");
            $minutes = (int)$t[2];
            if ($v->validation+$minutes>180) fail("validation limit exceeded for $v->plate");
            $v->validation += $minutes;
            $out[] = "VALIDATE $v->plate $minutes total $v->validation";
        } else {
            if ($v->type==='BUS') fail("bus $v->plate cannot be moved");
            $s = get_spot($t[2]);
            if ($v->spots[0]->id===$s->id) fail("$v->plate is already at $s->id");
            if ($s->closed) fail("spot $s->id is closed");
            if ($s->plate!=='') fail("spot $s->id is occupied by $s->plate");
            if (!in_array($s->kind,PREFS[$v->type],true)) fail("$v->type cannot use $s->kind spot $s->id");
            $out[] = move_vehicle($v,$s);
        }
    } elseif ($cmd==='PASS') {
        $plate = $t[1];
        $passes[$plate] = valid_pass($plate,$now) ? $passes[$plate]+(int)$t[2] : date_of($now)+(int)$t[2]-1;
        $out[] = "PASS $plate until $passes[$plate]";
    } elseif ($cmd==='UNPASS') {
        if (!valid_pass($t[1],$now)) fail("$t[1] has no pass");
        unset($passes[$t[1]]);
        $out[] = "UNPASS $t[1]";
    } elseif ($cmd==='REBALANCE') {
        $targets = array_values(array_filter($vehicles,fn($v)=>$v->type!=='BUS'));
        usort($targets,fn($a,$b)=>location_key($a)<=>location_key($b));
        $moved = 0;
        foreach ($targets as $v) {
            $current = array_search($v->spots[0]->kind,PREFS[$v->type],true);
            if ($current===0) continue;
            $chosen = assignment($v->type);
            if ($chosen!==[] && array_search($chosen[0]->kind,PREFS[$v->type],true)<$current) {
                $out[] = move_vehicle($v,$chosen[0]);
                ++$moved;
            }
        }
        $out[] = "REBALANCE $moved";
    } elseif ($cmd==='WHERE') {
        $plate = $t[1];
        if (isset($vehicles[$plate])) {
            $v = $vehicles[$plate];
            $out[] = "WHERE $plate " . location($v) . " $v->type " . time_text($v->entry) . ' stay ' . duration($now-$v->entry) . annotation($v);
        } else {
            $position = array_find_key($queue,fn($w)=>$w->plate===$plate);
            if ($position!==null) $out[] = "WHERE $plate waiting " . ($position+1);
            elseif (isset($history[$plate])) $out[] = "WHERE $plate gone " . time_text($history[$plate][count($history[$plate])-1]->exit);
            else fail("unknown plate $plate");
        }
    } elseif ($cmd==='LIST' || $cmd==='OVERSTAY') {
        if ($cmd==='LIST' && isset($t[1]) && !isset($levels[(int)$t[1]-1])) fail("unknown level $t[1]");
        $targets = array_values($vehicles);
        if ($cmd==='LIST' && isset($t[1])) $targets = array_values(array_filter($targets,fn($v)=>$v->spots[0]->level===(int)$t[1]));
        if ($cmd==='OVERSTAY') $targets = array_values(array_filter($targets,fn($v)=>$now-$v->entry>=(int)$t[1]*60));
        usort($targets,function($a,$b) use ($cmd) {
            if ($cmd==='OVERSTAY' && $a->entry!==$b->entry) return $a->entry<=>$b->entry;
            return location_key($a)<=>location_key($b);
        });
        $out[] = $cmd . ($cmd==='OVERSTAY' ? " $t[1]" : '') . ' ' . count($targets);
        foreach ($targets as $v) {
            $text = location($v) . " $v->plate $v->type " . time_text($v->entry);
            $text .= $cmd==='LIST' ? annotation($v) : ' stay ' . duration($now-$v->entry);
            $out[] = $text;
        }
    } elseif ($cmd==='MAP') {
        $out[] = 'MAP ' . count($levels);
        foreach ($levels as $index=>$level) {
            $symbols = '';
            foreach ($level as $s) $symbols .= $s->closed ? '#' : ($s->plate!=='' ? $s->kind[0] : strtolower($s->kind[0]));
            $out[] = 'L' . ($index+1) . ' ' . implode(' ',str_split($symbols,10));
        }
    } elseif ($cmd==='OCCUPANCY') {
        $out[] = 'OCCUPANCY vehicles ' . count($vehicles) . ' waiting ' . count($queue);
        $totalUsed = array_fill_keys(KINDS,0);
        $totalAvailable = array_fill_keys(KINDS,0);
        $totalClosed = 0;
        foreach ($levels as $index=>$level) {
            $used = array_fill_keys(KINDS,0);
            $available = array_fill_keys(KINDS,0);
            $closedCount = 0;
            foreach ($level as $s) {
                if ($s->closed) ++$closedCount;
                else ++$available[$s->kind];
                if ($s->plate!=='') ++$used[$s->kind];
            }
            $out[] = occupancy_line('L' . ($index+1),$used,$available,$closedCount);
            foreach (KINDS as $kind) {
                $totalUsed[$kind] += $used[$kind];
                $totalAvailable[$kind] += $available[$kind];
            }
            $totalClosed += $closedCount;
        }
        $capacity = array_sum($totalAvailable);
        $usage = $capacity===0 ? 0 : intdiv(array_sum($totalUsed)*1000,$capacity);
        $out[] = occupancy_line('TOTAL',$totalUsed,$totalAvailable,$totalClosed) . ' rate ' . one_decimal($usage) . '%';
    } elseif ($cmd==='SIGN') {
        $parts = ['SIGN'];
        foreach (TYPES as $type) {
            $count = 0;
            foreach ($levels as $level) {
                $run = 0;
                foreach ($level as $s) {
                    if ($type==='BUS') {
                        if ($s->kind==='LARGE' && free_spot($s)) ++$run;
                        else {
                            $count += intdiv($run,3);
                            $run = 0;
                        }
                    } elseif (in_array($s->kind,PREFS[$type],true) && free_spot($s)) ++$count;
                }
                if ($type==='BUS') $count += intdiv($run,3);
            }
            $parts = [...$parts,$type,$count===0 ? 'FULL' : $count];
        }
        $out[] = implode(' ',$parts);
    } elseif ($cmd==='RATES') {
        $out[] = 'RATES';
        foreach (TYPES as $type) $out[] = "$type " . implode(' ',$rates[$type]);
        $out[] = "NIGHT $fees[NIGHT] LOST $fees[LOST] KWH $fees[KWH]";
    } elseif ($cmd==='PASSES') {
        $plates = array_values(array_filter(array_keys($passes),fn($plate)=>valid_pass((string)$plate,$now)));
        sort($plates,SORT_STRING);
        $out[] = 'PASSES ' . count($plates);
        foreach ($plates as $plate) $out[] = "$plate until $passes[$plate]" . (isset($vehicles[$plate]) ? ' IN' : '');
    } elseif ($cmd==='HISTORY') {
        if (!isset($history[$t[1]])) fail("no history for $t[1]");
        $records = $history[$t[1]];
        $out[] = "HISTORY $t[1] visits " . count($records) . ' paid ' . array_sum(array_column($records,'total'));
        foreach ($records as $r) $out[] = time_text($r->entry) . ' ' . time_text($r->exit) . " $r->location $r->type $r->total" . ($r->lost ? ' LOST' : '');
    } elseif ($cmd==='REVENUE') {
        $out[] = 'REVENUE';
        $total = array_fill_keys(array_keys($stats[TYPES[0]]),0);
        foreach (TYPES as $type) {
            $s = $stats[$type];
            $out[] = "$type exits $s[exits] parking $s[parking] night $s[night] lost $s[lost] charge $s[charge] total $s[total]";
            foreach ($s as $key=>$value) $total[$key] += $value;
        }
        $out[] = "TOTAL exits $total[exits] parking $total[parking] night $total[night] lost $total[lost] charge $total[charge] total $total[total]";
    } elseif ($cmd==='DAILY') {
        $date = (int)$t[1];
        $rows = $daily[$date] ?? array_fill_keys(TYPES,array_fill_keys(['entries','exits','refused','revenue'],0));
        $total = array_fill_keys(['entries','exits','refused','revenue'],0);
        $lines = [];
        foreach (TYPES as $type) {
            $s = $rows[$type];
            foreach ($s as $key=>$value) $total[$key] += $value;
            $lines[] = "$type entries $s[entries] exits $s[exits] refused $s[refused] revenue $s[revenue]";
        }
        $out[] = "DAILY $date entries $total[entries] exits $total[exits] refused $total[refused] revenue $total[revenue]";
        $out = [...$out,...$lines];
    } elseif ($cmd==='STATS') {
        $out[] = 'STATS parked ' . count($vehicles) . " peak $peak at " . ($peak===0 ? '-' : time_text($peakTime));
        $total = array_fill_keys(['entries','exits','refused','stay'],0);
        foreach ([...TYPES,'ALL'] as $type) {
            $s = $type==='ALL' ? $total : $stats[$type];
            if ($type!=='ALL') foreach (array_keys($total) as $key) $total[$key] += $s[$key];
            $average = $s['exits']===0 ? 0 : intdiv($s['stay']*10,$s['exits']);
            $out[] = "$type entries $s[entries] exits $s[exits] refused $s[refused] avg_stay " . one_decimal($average);
        }
    }
    if (in_array($cmd,['LEVEL','OPEN','EXIT','MOVE','REBALANCE'],true)) process_queue($out);
    return $out;
}
$n = (int)fgets(STDIN);
for ($i=0; $i<$n; ++$i) {
    $tokens = explode(' ',rtrim(fgets(STDIN),"\r\n"));
    [$hour,$minute] = array_map('intval',explode(':',$tokens[1]));
    $now = ((int)$tokens[0]-1)*1440+$hour*60+$minute;
    foreach (giveups() as $output) echo $output,"\n";
    try {
        foreach (execute(array_slice($tokens,2)) as $output) echo $output,"\n";
    } catch (InvalidArgumentException $error) {
        echo 'ERROR ',$error->getMessage(),"\n";
    }
}
