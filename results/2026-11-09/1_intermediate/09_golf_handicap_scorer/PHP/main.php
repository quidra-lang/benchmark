<?php
$courses = [];
$players = [];
$events = [];
$eventOrder = [];
function fail(string $message): never { throw new InvalidArgumentException($message); }
function floor_div(int $a,int $b): int
{
    $q = intdiv($a,$b);
    return $a<0 && $a%$b!==0 ? $q-1 : $q;
}
function half_up(int $a,int $b): int { return floor_div(2*$a+$b,2*$b); }
function half_away(int $a,int $b): int { return ($a<0 ? -1 : 1)*intdiv(2*abs($a)+$b,2*$b); }
function decimal(int $v): string { return intdiv(abs($v),10) . '.' . abs($v)%10; }
function index_text(?int $v): string { return $v===null ? 'none' : ($v<0 ? '+' : '') . decimal($v); }
function signed_text(int $v): string { return ($v<0 ? '-' : '') . decimal($v); }
function handicap_text(?int $v): string { return $v===null ? 'none' : ($v<0 ? '+' . -$v : (string)$v); }
function hundredths(int $v): string { return intdiv($v,100) . '.' . sprintf('%02d',$v%100); }
function mean_text(int $sum,int $count): string { return $count===0 ? '-' : hundredths(intdiv($sum*100,$count)); }
function status_text(int $lead): string
{
    if ($lead===0) return 'AS';
    return abs($lead) . ($lead>0 ? ' UP' : ' DN');
}
function get_player(string $id): object
{
    global $players;
    if (!isset($players[$id])) fail('unknown player');
    return $players[$id];
}
function get_course(string $id): object
{
    global $courses;
    if (!isset($courses[$id])) fail('unknown course');
    return $courses[$id];
}
function tee_check(string $course,string $tee): array
{
    $c = get_course($course);
    if (!isset($c->tees[$tee])) fail('unknown tee');
    return [$c,$c->tees[$tee]];
}
function course_handicap(int $index,object $c,array $tee): int
{
    return half_up($index*$tee[1]+113*($tee[0]-10*array_sum($c->pars)),1130);
}
function allocate(int $handicap,array $si): array
{
    $q = intdiv(abs($handicap),18);
    $r = abs($handicap)%18;
    return array_map(fn($rank)=>$handicap>=0 ? $q+(int)($rank<=$r) : -$q-(int)($rank>=19-$r),$si);
}
function low_index(object $p,int $day): ?array
{
    $best = null;
    foreach ($p->records as $record) {
        if ($record[0]>=$day-365 && $record[0]<$day && ($best===null || [$record[1],$record[0]]<[$best[1],$best[0]])) $best = $record;
    }
    return $best;
}
function counting_rule(int $n): array
{
    if ($n<3) return [0,0];
    if ($n===3) return [1,-20];
    if ($n===4) return [1,-10];
    if ($n===5) return [1,0];
    if ($n===6) return [2,-10];
    if ($n<=8) return [2,0];
    if ($n<=11) return [3,0];
    if ($n<=14) return [4,0];
    if ($n<=16) return [5,0];
    if ($n<=18) return [6,0];
    return [$n===19 ? 7 : 8,0];
}
function eligible(object $p): array
{
    $result = [];
    $reduction = 0;
    for ($i=count($p->rounds)-1; $i>=max(0,count($p->rounds)-20); --$i) {
        $r = $p->rounds[$i];
        $reduction += $r->exceptional;
        $result[] = ['number'=>$i+1,'round'=>$r,'adjusted'=>$r->diff-$reduction];
    }
    return array_reverse($result);
}
function counting(array $eligible): array
{
    [$k] = counting_rule(count($eligible));
    usort($eligible,fn($a,$b)=>[$a['adjusted'],-$a['number']]<=>[$b['adjusted'],-$b['number']]);
    return array_slice($eligible,0,$k);
}
function update_index(object $p,int $day): void
{
    $eligible = eligible($p);
    [$k,$adjustment] = counting_rule(count($eligible));
    if ($k===0) {
        $p->calculation = null;
        return;
    }
    $sum = array_sum(array_column(counting($eligible),'adjusted'));
    $average = half_away($sum,$k);
    $value = $average+$adjustment;
    $low = low_index($p,$day);
    $soft = false;
    $hard = false;
    $maximum = false;
    if ($low!==null) {
        $l = $low[1];
        if ($value-$l>30) {
            $new = $l+30+intdiv($value-$l-30,2);
            $soft = $new!==$value;
            $value = $new;
        }
        if ($value-$l>50) {
            $value = $l+50;
            $hard = true;
        }
    }
    if ($value>540) {
        $value = 540;
        $maximum = true;
    }
    $p->index = $value;
    $p->calculation = ['k'=>$k,'average'=>$average,'adjustment'=>$adjustment,'low'=>$low===null ? null : $low[1],'hard'=>$hard,'soft'=>$soft,'maximum'=>$maximum];
}
function hole_values(object $r,array $strokes,object $c): array
{
    $nets = [];
    $points = [];
    foreach ($r->scores as $h=>$score) {
        $net = ctype_digit($score) ? (int)$score-$strokes[$h] : null;
        $nets[] = $net;
        $points[] = $net===null ? 0 : max(0,$c->pars[$h]+2-$net);
    }
    return [$nets,$points];
}
function countback(array $values,bool $larger=false): array
{
    $key = [];
    foreach ([0,9,12,15,17] as $start) $key[] = array_sum(array_slice($values,$start))*($larger ? -1 : 1);
    return $key;
}
function event_context(object $e): array
{
    global $players;
    [$c] = tee_check($e->course,$e->tee);
    $rounds = [];
    $ph = [];
    foreach ($e->players as $id) {
        $found = array_find($players[$id]->rounds,fn($r)=>
            $r->course===$e->course && $r->tee===$e->tee && $r->day===$e->day);
        if ($found===null) fail('missing round');
        if ($found->handicap===null) fail('no index');
        $rounds[$id] = $found;
        $ph[$id] = half_up($found->handicap*$e->allowance,100);
    }
    $minimum = in_array($e->format,['MATCH','NASSAU','FOURBALL'],true) ? min($ph) : 0;
    $nets = [];
    $points = [];
    foreach ($e->players as $id) [$nets[$id],$points[$id]] = hole_values($rounds[$id],allocate($ph[$id]-$minimum,$c->si),$c);
    return ['course'=>$c,'rounds'=>$rounds,'ph'=>$ph,'minimum'=>$minimum,'nets'=>$nets,'points'=>$points];
}
function par_values(array $nets,array $pars): array
{
    return array_map(fn($net,$par)=>$net===null ? -1 : ($par<=>$net),$nets,$pars);
}
function ranking(object $e,array $ctx): array
{
    $ranked = [];
    $keys = [];
    foreach ($e->players as $id) {
        if ($e->format==='STROKE') {
            if (in_array(null,$ctx['nets'][$id],true)) continue;
            $values = $ctx['nets'][$id];
        } elseif ($e->format==='STABLEFORD') {
            $values = $ctx['points'][$id];
        } else {
            $values = par_values($ctx['nets'][$id],$ctx['course']->pars);
        }
        $ranked[] = $id;
        $keys[$id] = countback($values,$e->format!=='STROKE');
    }
    usort($ranked,fn($a,$b)=>($keys[$a]<=>$keys[$b]) ?: strcmp($a,$b));
    return $ranked;
}
function play_match(array $wins,array $names,int $first,int $last): array
{
    $lead = 0;
    $statuses = [];
    $remaining = 0;
    for ($h=$first; $h<=$last; ++$h) {
        $lead += $wins[$h];
        $statuses[] = status_text($lead);
        $remaining = $last-$h;
        if (abs($lead)>$remaining) break;
    }
    $result = 'AS';
    if ($lead!==0) $result = $names[$lead>0 ? 0 : 1] . ' ' . ($remaining>0 ? abs($lead) . "&$remaining" : abs($lead) . ' UP');
    return [$statuses,$result];
}
function result_lines(object $e): array
{
    $ctx = event_context($e);
    $c = $ctx['course'];
    $out = ["results $e->id: $e->format $e->course $e->tee day $e->day allowance $e->allowance"];
    if (in_array($e->format,['STROKE','STABLEFORD','PAR'],true)) {
        $ranked = ranking($e,$ctx);
        foreach ($ranked as $rank=>$id) {
            $hcp = handicap_text($ctx['ph'][$id]);
            if ($e->format==='STROKE') $text = 'net ' . array_sum($ctx['nets'][$id]) . ' gross ' . array_sum(array_map('intval',$ctx['rounds'][$id]->scores));
            elseif ($e->format==='STABLEFORD') $text = 'points ' . array_sum($ctx['points'][$id]);
            else {
                $record = array_sum(par_values($ctx['nets'][$id],$c->pars));
                $text = status_text($record);
            }
            $out[] = ($rank+1) . " $id $text hcp $hcp";
        }
        if ($e->format==='STROKE') {
            $nr = array_values(array_diff($e->players,$ranked));
            sort($nr,SORT_STRING);
            foreach ($nr as $id) $out[] = "NR $id hcp " . handicap_text($ctx['ph'][$id]);
            if ($ranked!==[]) {
                usort($ranked,fn($a,$b)=>(countback(array_map('intval',$ctx['rounds'][$a]->scores))
                    <=> countback(array_map('intval',$ctx['rounds'][$b]->scores))) ?: strcmp($a,$b));
                $id = $ranked[0];
                $out[] = "gross $id " . array_sum(array_map('intval',$ctx['rounds'][$id]->scores));
            }
        }
    } elseif (in_array($e->format,['MATCH','NASSAU','FOURBALL'],true)) {
        $sideSize = $e->format==='FOURBALL' ? 2 : 1;
        $sides = [array_slice($e->players,0,$sideSize),array_slice($e->players,$sideSize,$sideSize)];
        $names = array_map(fn($ids)=>implode('+',$ids),$sides);
        $wins = [];
        for ($h=0; $h<18; ++$h) {
            $scores = [];
            foreach ($sides as $ids) {
                $values = [];
                foreach ($ids as $id) if ($ctx['nets'][$id][$h]!==null) $values[] = $ctx['nets'][$id][$h];
                $scores[] = $values===[] ? null : min($values);
            }
            if ($scores[0]===null) $wins[] = $scores[1]===null ? 0 : -1;
            elseif ($scores[1]===null) $wins[] = 1;
            else $wins[] = $scores[1]<=>$scores[0];
        }
        $parts = ['strokes'];
        foreach ($e->players as $id) $parts = [...$parts,$id,$ctx['ph'][$id]-$ctx['minimum']];
        $out[] = implode(' ',$parts);
        if ($e->format==='NASSAU') {
            foreach ([['front',0,8],['back',9,17],['total',0,17]] as [$label,$first,$last]) $out[] = $label . ' ' . play_match($wins,$names,$first,$last)[1];
        } else {
            [$statuses,$result] = play_match($wins,$names,0,17);
            $out[] = 'status ' . implode(', ',$statuses);
            $out[] = "result $result";
        }
    } elseif ($e->format==='BETTERBALL') {
        $teams = [];
        for ($i=0; $i<count($e->players); $i+=2) {
            [$a,$b] = array_slice($e->players,$i,2);
            $values = array_map('max',$ctx['points'][$a],$ctx['points'][$b]);
            $teams[] = ['a'=>$a,'b'=>$b,'values'=>$values,'key'=>countback($values,true)];
        }
        usort($teams,fn($a,$b)=>($a['key']<=>$b['key']) ?: strcmp($a['a'],$b['a']));
        foreach ($teams as $rank=>$team) {
            [$a,$b] = [$team['a'],$team['b']];
            $out[] = ($rank+1) . " $a+$b points " . array_sum($team['values']) . ' hcp ' . handicap_text($ctx['ph'][$a]) . ' ' . handicap_text($ctx['ph'][$b]);
        }
    } else {
        $totals = array_fill_keys($e->players,0);
        $carry = 0;
        $winners = [];
        for ($h=0; $h<18; ++$h) {
            ++$carry;
            $minimum = null;
            $winners = [];
            foreach ($e->players as $id) {
                $net = $ctx['nets'][$id][$h];
                if ($net===null) continue;
                if ($minimum===null || $net<$minimum) {
                    $minimum = $net;
                    $winners = [$id];
                } elseif ($net===$minimum) $winners[] = $id;
            }
            if (count($winners)===1) {
                $id = $winners[0];
                $totals[$id] += 100*$carry;
                $out[] = 'hole ' . ($h+1) . " $id $carry";
                $carry = 0;
            }
        }
        if ($carry>0) {
            if ($winners===[]) $winners = $e->players;
            sort($winners,SORT_STRING);
            $share = intdiv(100*$carry,count($winners));
            foreach ($winners as $id) $totals[$id] += $share;
            $out[] = "carry $carry " . implode(' ',$winners);
        }
        $ids = $e->players;
        usort($ids,fn($a,$b)=>($totals[$b]<=>$totals[$a]) ?: strcmp($a,$b));
        foreach ($ids as $id) $out[] = "$id " . hundredths($totals[$id]);
    }
    return $out;
}
function execute(string $line): array
{
    global $courses,$players,$events,$eventOrder;
    $t = explode(' ',$line);
    $cmd = $t[0];
    $out = [];
    if ($cmd==='COURSE') {
        if (isset($courses[$t[1]])) fail('duplicate course');
        $pars = array_map('intval',array_slice($t,2,18));
        $si = array_map('intval',array_slice($t,20,18));
        $sorted = $si;
        sort($sorted,SORT_NUMERIC);
        if (array_any($pars,fn($par)=>!in_array($par,[3,4,5],true)) || $sorted!==range(1,18)) fail('invalid course');
        $courses[$t[1]] = (object)['id'=>$t[1],'pars'=>$pars,'si'=>$si,'tees'=>[]];
    } elseif ($cmd==='TEE') {
        $c = get_course($t[1]);
        if (isset($c->tees[$t[2]])) fail('duplicate tee');
        [$rating,$slope] = [(int)$t[3],(int)$t[4]];
        if ($rating<500 || $rating>900 || $slope<55 || $slope>155) fail('invalid tee');
        $c->tees[$t[2]] = [$rating,$slope];
    } elseif ($cmd==='PLAYER') {
        if (isset($players[$t[1]])) fail('duplicate player');
        $index = isset($t[3]) ? (int)$t[3] : null;
        if ($index!==null && ($index < -100 || $index>540)) fail('invalid index');
        $players[$t[1]] = (object)['id'=>$t[1],'name'=>$t[2],'index'=>$index,'rounds'=>[],'records'=>[],'calculation'=>null];
    } elseif ($cmd==='ROUND') {
        $p = get_player($t[1]);
        [$c,$tee] = tee_check($t[2],$t[3]);
        $day = (int)$t[4];
        if ($p->rounds!==[] && $day<$p->rounds[count($p->rounds)-1]->day) fail('invalid day');
        $scores = array_slice($t,5);
        if (count(array_filter($scores,fn($score)=>$score==='-'))>=5) fail('too few holes');
        $hcp = $p->index===null ? null : course_handicap($p->index,$c,$tee);
        $strokes = allocate($hcp ?? 0,$c->si);
        $adjusted = [];
        foreach ($scores as $h=>$score) {
            $limit = $c->pars[$h]+($p->index===null ? 5 : 2+$strokes[$h]);
            if ($score==='X') $adjusted[] = $limit;
            elseif ($score==='-') $adjusted[] = $c->pars[$h]+$strokes[$h];
            else $adjusted[] = min((int)$score,$limit);
        }
        $ags = array_sum($adjusted);
        $diff = half_away(113*(10*$ags-$tee[0]),$tee[1]);
        $exceptional = 0;
        if ($p->index!==null && $p->index-$diff>=70) $exceptional = $p->index-$diff>=100 ? 20 : 10;
        $r = (object)['day'=>$day,'course'=>$c->id,'tee'=>$t[3],'scores'=>$scores,'handicap'=>$hcp,'adjusted'=>$adjusted,'ags'=>$ags,'diff'=>$diff,'exceptional'=>$exceptional,
            'beforeIndex'=>$p->index,'beforeRecords'=>count($p->records),'beforeCalculation'=>$p->calculation];
        $p->rounds[] = $r;
        update_index($p,$day);
        if ($p->index!==null) $p->records[] = [$day,$p->index];
        $out[] = "round $p->id " . count($p->rounds) . ": ags $ags diff " . signed_text($diff) . ($exceptional===0 ? '' : ' exceptional ' . signed_text(-$exceptional)) . ' index ' . index_text($p->index);
    } elseif ($cmd==='REMOVE') {
        $p = get_player($t[1]);
        if ($p->rounds===[]) fail('no rounds');
        $number = count($p->rounds);
        $r = array_pop($p->rounds);
        $p->index = $r->beforeIndex;
        $p->records = array_slice($p->records,0,$r->beforeRecords);
        $p->calculation = $r->beforeCalculation;
        $out[] = "removed $p->id $number: index " . index_text($p->index);
    } elseif (in_array($cmd,['INDEX','HISTORY','LOWINDEX','COURSEHCP','CARD','STATS'],true)) {
        $p = get_player($t[1]);
        if ($cmd==='INDEX') {
            $text = "index $p->id: " . index_text($p->index) . ' rounds ' . count($p->rounds);
            $calc = $p->calculation;
            if ($calc!==null) {
                $text .= ' lowest ' . $calc['k'] . ' average ' . signed_text($calc['average']) . ' adjustment ' . signed_text($calc['adjustment']);
                if ($calc['low']!==null) $text .= ' low ' . index_text($calc['low']);
                if ($calc['hard']) $text .= ' hard cap';
                elseif ($calc['soft']) $text .= ' soft cap';
                if ($calc['maximum']) $text .= ' maximum';
            }
            $out[] = $text;
        } elseif ($cmd==='HISTORY') {
            $out[] = "history $p->id: rounds " . count($p->rounds);
            $eligible = eligible($p);
            $counted = array_column(counting($eligible),'number');
            foreach ($eligible as $item) {
                $r = $item['round'];
                $text = $item['number'] . " day $r->day $r->course $r->tee ags $r->ags diff " . signed_text($r->diff);
                if ($item['adjusted']!==$r->diff) $text .= ' adjusted ' . signed_text($item['adjusted']);
                if (in_array($item['number'],$counted,true)) $text .= ' *';
                $out[] = $text;
            }
        } elseif ($cmd==='LOWINDEX') {
            $low = low_index($p,(int)$t[2]);
            $out[] = "lowindex $p->id $t[2]: " . ($low===null ? 'none' : index_text($low[1]) . " day $low[0]");
        } elseif ($cmd==='COURSEHCP') {
            [$c,$tee] = tee_check($t[2],$t[3]);
            if ($p->index===null) fail('no index');
            $hcp = course_handicap($p->index,$c,$tee);
            $out[] = "coursehcp $p->id $c->id $t[3]: " . handicap_text($hcp) . ' strokes ' . implode(' ',allocate($hcp,$c->si));
        } elseif ($cmd==='CARD') {
            $number = (int)$t[2];
            if ($number>count($p->rounds)) fail('unknown round');
            $r = $p->rounds[$number-1];
            $c = $courses[$r->course];
            $strokes = allocate($r->handicap ?? 0,$c->si);
            [$nets,$points] = hole_values($r,$strokes,$c);
            $out[] = "card $p->id $number: $r->course $r->tee day $r->day handicap " . handicap_text($r->handicap);
            for ($h=0; $h<18; ++$h) {
                $out[] = ($h+1) . " {$c->pars[$h]} {$c->si[$h]} {$r->scores[$h]} {$r->adjusted[$h]} $strokes[$h] " . ($nets[$h]===null ? '-' : $nets[$h]) . " $points[$h]";
                if ($h===8) $ranges = [['OUT',0,9]];
                elseif ($h===17) $ranges = [['IN',9,9],['TOTAL',0,18]];
                else $ranges = [];
                foreach ($ranges as [$label,$start,$length]) {
                    $partNets = array_slice($nets,$start,$length);
                    $complete = !in_array(null,$partNets,true);
                    $raw = $complete ? array_sum(array_map('intval',array_slice($r->scores,$start,$length))) : '-';
                    $net = $complete ? array_sum($partNets) : '-';
                    $out[] = "$label " . array_sum(array_slice($c->pars,$start,$length)) . " $raw " . array_sum(array_slice($r->adjusted,$start,$length)) . ' ' . array_sum(array_slice($strokes,$start,$length)) . " $net " . array_sum(array_slice($points,$start,$length));
                }
            }
            $out[] = "ags $r->ags diff " . signed_text($r->diff);
        } else {
            $counts = array_fill_keys(['eagles','birdies','pars','bogeys','doubles','others','pickups'],0);
            $sums = [3=>0,4=>0,5=>0];
            $numbers = $sums;
            $totals = [];
            foreach ($p->rounds as $r) {
                $c = $courses[$r->course];
                $total = 0;
                $complete = true;
                foreach ($r->scores as $h=>$score) {
                    if (!ctype_digit($score)) {
                        $complete = false;
                        if ($score==='X') ++$counts['pickups'];
                        continue;
                    }
                    $value = (int)$score;
                    $par = $c->pars[$h];
                    $relative = $value-$par;
                    if ($relative<=-2) $category = 'eagles';
                    elseif ($relative===-1) $category = 'birdies';
                    elseif ($relative===0) $category = 'pars';
                    elseif ($relative===1) $category = 'bogeys';
                    elseif ($relative===2) $category = 'doubles';
                    else $category = 'others';
                    ++$counts[$category];
                    $sums[$par] += $value;
                    ++$numbers[$par];
                    $total += $value;
                }
                if ($complete) $totals[] = $total;
            }
            $best = $totals===[] ? '-' : min($totals);
            $out[] = "stats $p->id: rounds " . count($p->rounds) . " best $best average " . mean_text(array_sum($totals),count($totals)) . " eagles $counts[eagles] birdies $counts[birdies] pars $counts[pars] bogeys $counts[bogeys] doubles $counts[doubles] others $counts[others] pickups $counts[pickups] par3 " . mean_text($sums[3],$numbers[3]) . ' par4 ' . mean_text($sums[4],$numbers[4]) . ' par5 ' . mean_text($sums[5],$numbers[5]);
        }
    } elseif ($cmd==='HCPTABLE') {
        [$c,$tee] = tee_check($t[1],$t[2]);
        [$first,$last] = [(int)$t[3],(int)$t[4]];
        if ($first < -100 || $first>$last || $last>540) fail('invalid index');
        $out[] = "hcptable $c->id $t[2]: " . index_text($first) . ' to ' . index_text($last);
        $start = $first;
        $hcp = course_handicap($first,$c,$tee);
        for ($i=$first+1; $i<=$last+1; ++$i) {
            $next = $i<=$last ? course_handicap($i,$c,$tee) : null;
            if ($next!==$hcp) {
                $out[] = index_text($start) . ' to ' . index_text($i-1) . ': ' . handicap_text($hcp);
                $start = $i;
                $hcp = $next;
            }
        }
    } elseif ($cmd==='HOLESTATS') {
        $c = get_course($t[1]);
        $sums = array_fill(0,18,0);
        $numbers = array_fill(0,18,0);
        $rounds = 0;
        foreach ($players as $p) {
            foreach ($p->rounds as $r) {
                if ($r->course!==$c->id) continue;
                ++$rounds;
                foreach ($r->scores as $h=>$score) if (ctype_digit($score)) {
                    $sums[$h] += (int)$score;
                    ++$numbers[$h];
                }
            }
        }
        $holes = range(0,17);
        usort($holes,function($a,$b) use ($sums,$numbers,$c) {
            if ($numbers[$a]===0 || $numbers[$b]===0) return [$numbers[$a]===0,$a]<=>[$numbers[$b]===0,$b];
            $left = ($sums[$a]-$c->pars[$a]*$numbers[$a])*$numbers[$b];
            $right = ($sums[$b]-$c->pars[$b]*$numbers[$b])*$numbers[$a];
            return $right<=>$left ?: $a<=>$b;
        });
        $ranks = [];
        foreach ($holes as $rank=>$h) $ranks[$h] = $rank+1;
        $out[] = "holestats $c->id: rounds $rounds";
        for ($h=0; $h<18; ++$h) $out[] = ($h+1) . " par {$c->pars[$h]} si {$c->si[$h]} scores $numbers[$h] avg " . mean_text($sums[$h],$numbers[$h]) . " rank $ranks[$h]";
    } elseif ($cmd==='PLAYERS') {
        $all = array_values($players);
        usort($all,fn($a,$b)=>([$a->index===null,$a->index ?? 0]
            <=> [$b->index===null,$b->index ?? 0]) ?: strcmp($a->id,$b->id));
        $out[] = 'players ' . count($all);
        foreach ($all as $p) $out[] = "$p->id $p->name " . index_text($p->index) . ' rounds ' . count($p->rounds);
    } elseif ($cmd==='EVENT') {
        if (isset($events[$t[1]])) fail('duplicate event');
        tee_check($t[3],$t[4]);
        $allowance = (int)$t[6];
        if ($allowance<1 || $allowance>100) fail('invalid allowance');
        $ids = array_slice($t,7);
        foreach ($ids as $id) get_player($id);
        $n = count($ids);
        $valid = match ($t[2]) {'MATCH','NASSAU'=>$n===2,'FOURBALL'=>$n===4,'BETTERBALL'=>in_array($n,[4,6,8],true),default=>$n>=2 && $n<=8};
        if (!$valid || count(array_unique($ids))!==$n) fail('invalid players');
        $events[$t[1]] = (object)['id'=>$t[1],'format'=>$t[2],'course'=>$t[3],'tee'=>$t[4],'day'=>(int)$t[5],'allowance'=>$allowance,'players'=>$ids];
        $eventOrder[] = $t[1];
    } elseif ($cmd==='RESULTS') {
        if (!isset($events[$t[1]])) fail('unknown event');
        $out = result_lines($events[$t[1]]);
    } elseif ($cmd==='MERIT') {
        $totals = [];
        $counted = 0;
        foreach ($eventOrder as $id) {
            $e = $events[$id];
            if (!in_array($e->format,['STROKE','STABLEFORD','PAR'],true)) continue;
            try { $ctx = event_context($e); }
            catch (InvalidArgumentException $error) { continue; }
            ++$counted;
            foreach ($e->players as $player) {
                $totals[$player] ??= [0,0,0];
                ++$totals[$player][2];
            }
            foreach (ranking($e,$ctx) as $rank=>$player) {
                $totals[$player][0] += [10,8,6,5,4,3,2,1][$rank];
                if ($rank===0) ++$totals[$player][1];
            }
        }
        $ids = array_keys($totals);
        usort($ids,fn($a,$b)=>([-$totals[$a][0],-$totals[$a][1]]
            <=> [-$totals[$b][0],-$totals[$b][1]]) ?: strcmp((string)$a,(string)$b));
        $out[] = "merit: events $counted";
        foreach ($ids as $rank=>$id) $out[] = ($rank+1) . " $id " . $totals[$id][0] . ' wins ' . $totals[$id][1] . ' played ' . $totals[$id][2];
    }
    return $out;
}
$n = (int)fgets(STDIN);
for ($i=0; $i<$n; ++$i) {
    $line = rtrim(fgets(STDIN),"\r\n");
    try {
        foreach (execute($line) as $output) echo $output,"\n";
    } catch (InvalidArgumentException $error) {
        echo 'ERROR ',$error->getMessage(),"\n";
    }
}
