<?php
const RULES = ['STUDENT'=>[3,14,25,1000,2,50], 'STAFF'=>[10,28,10,2000,5,100]];
$day = 1;
$closed = [];
$books = [];
$bookOrder = [];
$members = [];
$memberOrder = [];
$counts = ['borrowed'=>0,'returned'=>0,'renewed'=>0,'lost'=>0,'FINE'=>0,'FEE'=>0,'PRICE'=>0,'paid'=>0,'waived'=>0];
function fail(string $message): never { throw new InvalidArgumentException($message); }
function cents(string $text): int
{
    [$whole,$fraction] = explode('.', $text);
    return (int)$whole * 100 + (int)$fraction;
}
function money(int $v): string { return intdiv($v,100) . '.' . sprintf('%02d',$v%100); }
function isbn(string $text): string
{
    $s = str_replace('-','',$text);
    if (preg_match('/^[0-9]{9}[0-9X]$/D',$s)) {
        $sum = 0;
        for ($i=0; $i<10; ++$i) $sum += (10-$i) * ($s[$i]==='X' ? 10 : (int)$s[$i]);
        if ($sum%11 !== 0) fail('invalid isbn');
        $s = '978' . substr($s,0,9);
        $sum = 0;
        for ($i=0; $i<12; ++$i) $sum += (int)$s[$i] * ($i%2===0 ? 1 : 3);
        return $s . ((10-$sum%10)%10);
    }
    if (preg_match('/^97[89][0-9]{10}$/D',$s)) {
        $sum = 0;
        for ($i=0; $i<13; ++$i) $sum += (int)$s[$i] * ($i%2===0 ? 1 : 3);
        if ($sum%10===0) return $s;
    }
    fail('invalid isbn');
}
function get_member(string $id): object
{
    global $members;
    if (!isset($members[$id])) fail('unknown member');
    return $members[$id];
}
function get_book(string $text): object
{
    global $books;
    $id = isbn($text);
    if (!isset($books[$id])) fail('unknown book');
    return $books[$id];
}
function balance(object $m): int { return array_sum(array_column($m->items,'unpaid')); }
function holdings(object $b): int
{
    return count(array_filter($b->copies,fn($c)=>in_array($c->state,['AVAILABLE','LOANED','HOLD'],true)));
}
function reservations(object $m): int
{
    global $books;
    $n = count($m->holds);
    foreach ($books as $b) if (in_array($m->id,$b->queue,true)) ++$n;
    return $n;
}
function open_day(int $date): int
{
    global $closed;
    while (isset($closed[$date])) ++$date;
    return $date;
}
function late_fine(object $c): array
{
    global $day,$members;
    $m = $members[$c->member];
    $late = max(0,$day-$c->due);
    return [$late,min($late*RULES[$m->type][2],RULES[$m->type][3])];
}
function charge(object $m,string $kind,string $id,int $amount): void
{
    global $day,$counts;
    if ($amount===0) return;
    $m->items[] = (object)['day'=>$day,'kind'=>$kind,'isbn'=>$id,'amount'=>$amount,'unpaid'=>$amount];
    $counts[$kind] += $amount;
}
function release_copy(object $b,object $c,array &$out): void
{
    global $day,$members;
    if ($b->queue===[]) {
        $c->state = 'AVAILABLE';
        return;
    }
    $id = array_shift($b->queue);
    $c->state = 'HOLD';
    $c->member = $id;
    $c->expiry = open_day($day+3);
    $members[$id]->holds[$b->id] = $c;
    $out[] = "HOLD $b->id copy $c->number $id until $c->expiry";
}
function end_loan(object $b,object $c,string $result): array
{
    global $day,$members;
    $m = $members[$c->member];
    [$late,$fine] = late_fine($c);
    unset($m->loans[$b->id]);
    charge($m,'FINE',$b->id,$fine);
    $m->history[] = "$result $b->id copy $c->number from $c->start to $day late $late fine " . money($fine);
    return [$m,$late,$fine];
}
function lose_copy(object $b,object $c,string $heading,array &$out): void
{
    global $counts;
    [$m,$late,$fine] = end_loan($b,$c,'LOST');
    $last = count($m->history)-1;
    $m->history[$last] .= ' price ' . money($b->price);
    charge($m,'PRICE',$b->id,$b->price);
    $c->state = 'LOST';
    ++$counts['lost'];
    $out[] = "$heading $m->id $b->id copy $c->number late $late fine " . money($fine) . ' price ' . money($b->price) . ' balance ' . money(balance($m));
    if (holdings($b)===0) {
        foreach ($b->queue as $id) $out[] = "DROPPED $b->id $id";
        $b->queue = [];
    }
}
function renewal_reason(object $b,object $c): string
{
    global $day;
    if ($c->due < $day) return 'loan overdue';
    if ($c->renewals===2) return 'renewal limit';
    return $b->queue!==[] ? 'title reserved' : '';
}
function renew_loan(object $m,object $b,object $c): string
{
    global $day,$counts;
    $c->due = open_day($day+RULES[$m->type][1]);
    ++$c->renewals;
    ++$counts['renewed'];
    return "RENEW $m->id $b->id copy $c->number due $c->due renewals $c->renewals";
}
function sorted_copies(array $copies,string $date): array
{
    $values = array_values($copies);
    usort($values,fn($a,$b)=>[$a->$date,$a->isbn] <=> [$b->$date,$b->isbn]);
    return $values;
}
function execute(string $line): array
{
    global $day,$closed,$books,$bookOrder,$members,$memberOrder,$counts;
    $t = explode(' ',$line);
    $cmd = $t[0];
    $out = [];
    if ($cmd==='DAY') {
        $target = (int)$t[1];
        if ($target <= $day) fail('invalid day');
        $out[] = "DAY $target";
        while ($day < $target) {
            $next = $target+1;
            foreach ($members as $m) {
                foreach ($m->loans as $c) $next = min($next,$c->due+365);
                foreach ($m->holds as $c) $next = min($next,$c->expiry+1);
            }
            if ($next > $target) {
                $day = $target;
                break;
            }
            $day = $next;
            $losses = [];
            foreach ($memberOrder as $id) {
                $m = $members[$id];
                $ids = array_keys($m->loans);
                sort($ids,SORT_STRING);
                foreach ($ids as $key) {
                    $c = $m->loans[$key];
                    if ($c->due+365 <= $day) $losses[] = $c;
                }
            }
            foreach ($losses as $c) lose_copy($books[$c->isbn],$c,'AUTOLOST',$out);
            $expired = [];
            foreach ($bookOrder as $id) {
                foreach ($books[$id]->copies as $c) {
                    if ($c->state==='HOLD' && $c->expiry < $day) $expired[] = $c;
                }
            }
            foreach ($expired as $c) {
                $b = $books[$c->isbn];
                $m = $members[$c->member];
                $fee = RULES[$m->type][5];
                charge($m,'FEE',$b->id,$fee);
                unset($m->holds[$b->id]);
                $out[] = "EXPIRED $b->id copy $c->number $m->id fee " . money($fee);
                release_copy($b,$c,$out);
            }
        }
    } elseif ($cmd==='CLOSED') {
        $date = (int)$t[1];
        if ($date <= $day) fail('invalid day');
        if (isset($closed[$date])) fail('already closed');
        $closed[$date] = true;
        $out[] = "CLOSED $date";
        foreach ($bookOrder as $id) {
            foreach ($books[$id]->copies as $c) {
                if ($c->state==='LOANED' && $c->due===$date) {
                    $c->due = open_day($date);
                    $out[] = "MOVED $id copy $c->number $c->member due $c->due";
                } elseif ($c->state==='HOLD' && $c->expiry===$date) {
                    $c->expiry = open_day($date);
                    $out[] = "MOVED $id copy $c->number $c->member until $c->expiry";
                }
            }
        }
    } elseif ($cmd==='ADDBOOK') {
        $id = isbn($t[1]);
        $name = implode(' ',array_slice($t,4));
        if (isset($books[$id]) && $books[$id]->name!==$name) fail('title mismatch');
        if (!isset($books[$id])) {
            $books[$id] = (object)['id'=>$id,'name'=>$name,'price'=>0,'copies'=>[],'queue'=>[],'borrowed'=>0];
            $bookOrder[] = $id;
            sort($bookOrder,SORT_STRING);
        }
        $b = $books[$id];
        $b->price = cents($t[3]);
        $added = [];
        for ($i=0; $i<(int)$t[2]; ++$i) {
            $c = (object)['isbn'=>$id,'number'=>count($b->copies)+1,'state'=>'AVAILABLE','member'=>'','start'=>0,'due'=>0,'renewals'=>0,'expiry'=>0];
            $b->copies[] = $c;
            $added[] = $c;
        }
        $out[] = "ADDBOOK $id added $t[2] total " . holdings($b);
        foreach ($added as $c) release_copy($b,$c,$out);
    } elseif ($cmd==='ADDMEMBER') {
        if (isset($members[$t[1]])) fail('duplicate member');
        if (!isset(RULES[$t[2]])) fail('unknown type');
        $m = (object)['id'=>$t[1],'type'=>$t[2],'name'=>implode(' ',array_slice($t,3)),'loans'=>[],'holds'=>[],'items'=>[],'history'=>[]];
        $members[$m->id] = $m;
        $memberOrder[] = $m->id;
        sort($memberOrder,SORT_STRING);
        $rule = RULES[$m->type];
        $out[] = "ADDMEMBER $m->id $m->type loans $rule[0] days $rule[1]";
    } elseif (in_array($cmd,['BORROW','RETURN','RENEW','RESERVE','CANCEL','LOST'],true)) {
        $m = get_member($t[1]);
        $b = get_book($t[2]);
        $id = $b->id;
        $loan = $m->loans[$id] ?? null;
        $hold = $m->holds[$id] ?? null;
        $rule = RULES[$m->type];
        if ($cmd==='BORROW') {
            if (isset($closed[$day])) fail('library closed');
            if ($loan!==null) fail('already borrowed');
            if (balance($m)>500) fail('member blocked');
            if (array_any($m->loans,fn($c)=>$c->due<$day)) fail('overdue loans');
            if (count($m->loans)>=$rule[0]) fail('loan limit');
            $chosen = $hold ?? array_find($b->copies,fn($c)=>$c->state==='AVAILABLE');
            if ($chosen===null) {
                if (array_any($b->copies,fn($c)=>$c->state==='HOLD')) fail('all copies on hold');
                fail('no copy available');
            }
            unset($m->holds[$id]);
            $chosen->state = 'LOANED';
            $chosen->member = $m->id;
            $chosen->start = $day;
            $chosen->due = open_day($day+$rule[1]);
            $chosen->renewals = 0;
            $m->loans[$id] = $chosen;
            ++$b->borrowed;
            ++$counts['borrowed'];
            $out[] = "BORROW $m->id $id copy $chosen->number due $chosen->due";
        } elseif (in_array($cmd,['RETURN','RENEW','LOST'],true)) {
            if ($loan===null) fail('not borrowed');
            if ($cmd==='RETURN') {
                [$member,$late,$fine] = end_loan($b,$loan,'RETURNED');
                ++$counts['returned'];
                $out[] = "RETURN $m->id $id copy $loan->number late $late fine " . money($fine) . ' balance ' . money(balance($m));
                release_copy($b,$loan,$out);
            } elseif ($cmd==='LOST') {
                lose_copy($b,$loan,'LOST',$out);
            } else {
                if (balance($m)>500) fail('member blocked');
                $reason = renewal_reason($b,$loan);
                if ($reason!=='') fail($reason);
                $out[] = renew_loan($m,$b,$loan);
            }
        } elseif ($cmd==='RESERVE') {
            if ($loan!==null) fail('already borrowed');
            if ($hold!==null || in_array($m->id,$b->queue,true)) fail('already reserved');
            if (balance($m)>500) fail('member blocked');
            if (reservations($m)>=$rule[4]) fail('reservation limit');
            if (holdings($b)===0) fail('no copies');
            if (array_any($b->copies,fn($c)=>$c->state==='AVAILABLE')) fail('copy available');
            $b->queue[] = $m->id;
            $position = count($b->queue);
            $dues = array_column(array_filter($b->copies,fn($c)=>$c->state==='LOANED'),'due');
            sort($dues,SORT_NUMERIC);
            $estimate = $dues[$position-1] ?? 'none';
            $out[] = "RESERVE $m->id $id position $position estimate $estimate";
        } else {
            $position = array_search($m->id,$b->queue,true);
            if ($position===false && $hold===null) fail('not reserved');
            if ($position!==false) {
                array_splice($b->queue,$position,1);
                $out[] = "CANCEL $m->id $id queue";
            } else {
                unset($m->holds[$id]);
                $out[] = "CANCEL $m->id $id hold copy $hold->number";
                release_copy($b,$hold,$out);
            }
        }
    } elseif (in_array($cmd,['RENEWALL','PAYFINE','WAIVE','FINES','MEMBER','HISTORY'],true)) {
        $m = get_member($t[1]);
        if ($cmd==='RENEWALL') {
            if ($m->loans===[]) fail('no loans');
            if (balance($m)>500) fail('member blocked');
            $ids = array_keys($m->loans);
            sort($ids,SORT_STRING);
            $renewed = 0;
            $skipped = 0;
            foreach ($ids as $id) {
                $reason = renewal_reason($books[$id],$m->loans[$id]);
                if ($reason==='') {
                    $out[] = renew_loan($m,$books[$id],$m->loans[$id]);
                    ++$renewed;
                } else {
                    $out[] = "SKIP $id $reason";
                    ++$skipped;
                }
            }
            $out[] = "RENEWALL $m->id renewed $renewed skipped $skipped";
        } elseif ($cmd==='PAYFINE') {
            if (balance($m)===0) fail('no fines');
            $remaining = cents($t[2]);
            $paid = 0;
            $lines = [];
            foreach ($m->items as $index=>$item) {
                $applied = min($remaining,$item->unpaid);
                if ($applied>0) {
                    $item->unpaid -= $applied;
                    $remaining -= $applied;
                    $paid += $applied;
                    $lines[] = 'ITEM ' . ($index+1) . " $item->kind paid " . money($applied) . ' remaining ' . money($item->unpaid);
                }
            }
            $counts['paid'] += $paid;
            $out[] = "PAYFINE $m->id paid " . money($paid) . ' change ' . money($remaining) . ' balance ' . money(balance($m));
            $out = [...$out,...$lines];
        } elseif ($cmd==='WAIVE') {
            $index = (int)$t[2]-1;
            if (!isset($m->items[$index])) fail('unknown item');
            $item = $m->items[$index];
            if ($item->unpaid===0) fail('item settled');
            $amount = $item->unpaid;
            $item->unpaid = 0;
            $counts['waived'] += $amount;
            $out[] = "WAIVE $m->id item $t[2] $item->kind amount " . money($amount) . ' balance ' . money(balance($m));
        } elseif ($cmd==='FINES') {
            $n = count(array_filter($m->items,fn($item)=>$item->unpaid>0));
            $out[] = "FINES $m->id items $n balance " . money(balance($m));
            foreach ($m->items as $index=>$item) {
                if ($item->unpaid>0) $out[] = ($index+1) . " day $item->day $item->kind $item->isbn amount " . money($item->amount) . ' remaining ' . money($item->unpaid);
            }
        } elseif ($cmd==='HISTORY') {
            $out[] = "HISTORY $m->id " . count($m->history);
            $out = [...$out,...$m->history];
        } else {
            $rule = RULES[$m->type];
            $state = balance($m)>500 ? 'BLOCKED' : 'OK';
            $out[] = "MEMBER $m->id $m->type $m->name";
            $out[] = 'STATUS loans ' . count($m->loans) . "/$rule[0] reservations " . reservations($m) . "/$rule[4] balance " . money(balance($m)) . " $state";
            foreach (sorted_copies($m->loans,'due') as $c) {
                $text = "LOAN $c->isbn copy $c->number due $c->due renewals $c->renewals";
                if ($c->due<$day) {
                    [$late,$fine] = late_fine($c);
                    $text .= " late $late fine " . money($fine);
                }
                $out[] = $text;
            }
            foreach (sorted_copies($m->holds,'expiry') as $c) $out[] = "HOLD $c->isbn copy $c->number until $c->expiry";
            foreach ($bookOrder as $id) {
                $position = array_search($m->id,$books[$id]->queue,true);
                if ($position!==false) $out[] = "QUEUE $id position " . ($position+1);
            }
        }
    } elseif ($cmd==='WITHDRAW' || $cmd==='BOOK') {
        $b = get_book($t[1]);
        if ($cmd==='WITHDRAW') {
            $index = (int)$t[2]-1;
            if (!isset($b->copies[$index])) fail('unknown copy');
            $c = $b->copies[$index];
            if ($c->state!=='AVAILABLE') fail('copy not available');
            $c->state = 'WITHDRAWN';
            $out[] = "WITHDRAW $b->id copy $c->number total " . holdings($b);
        } else {
            $out[] = "BOOK $b->id $b->name";
            $out[] = 'PRICE ' . money($b->price) . ' copies ' . holdings($b) . " borrowed $b->borrowed";
            foreach ($b->copies as $c) {
                $text = "COPY $c->number $c->state";
                if ($c->state==='LOANED') $text .= " $c->member due $c->due";
                elseif ($c->state==='HOLD') $text .= " $c->member until $c->expiry";
                $out[] = $text;
            }
            $out[] = implode(' ',['QUEUE',count($b->queue),...$b->queue]);
        }
    } elseif ($cmd==='SEARCH') {
        $keyword = strtolower(implode(' ',array_slice($t,1)));
        $found = array_values(array_filter($books,fn($b)=>str_contains(strtolower($b->name),$keyword)));
        usort($found,fn($a,$b)=>strcmp(strtolower($a->name),strtolower($b->name)) ?: strcmp($a->id,$b->id));
        $out[] = 'SEARCH ' . count($found);
        foreach ($found as $b) {
            $available = count(array_filter($b->copies,fn($c)=>$c->state==='AVAILABLE'));
            $out[] = "$b->id $available/" . holdings($b) . " $b->name";
        }
    } elseif ($cmd==='OVERDUE' || $cmd==='NOTICES') {
        $lines = [];
        if ($cmd==='OVERDUE') {
            $loans = [];
            foreach ($members as $m) foreach ($m->loans as $c) if ($c->due<$day) $loans[] = $c;
            usort($loans,fn($a,$b)=>($a->due <=> $b->due) ?: strcmp($a->member,$b->member) ?: strcmp($a->isbn,$b->isbn));
            foreach ($loans as $c) {
                [$late,$fine] = late_fine($c);
                $lines[] = "$c->member $c->isbn copy $c->number due $c->due late $late fine " . money($fine);
            }
        } else {
            foreach ($memberOrder as $id) {
                $m = $members[$id];
                $loans = sorted_copies($m->loans,'due');
                foreach ($loans as $c) if ($c->due<$day) $lines[] = "OVERDUE $id $c->isbn due $c->due";
                foreach ($loans as $c) if ($c->due>=$day && $c->due<=$day+2) $lines[] = "DUESOON $id $c->isbn due $c->due";
                foreach (sorted_copies($m->holds,'expiry') as $c) $lines[] = "PICKUP $id $c->isbn until $c->expiry";
            }
        }
        $out[] = "$cmd " . count($lines);
        $out = [...$out,...$lines];
    } elseif ($cmd==='MEMBERS') {
        $out[] = 'MEMBERS ' . count($members);
        foreach ($memberOrder as $id) {
            $m = $members[$id];
            $state = balance($m)>500 ? 'BLOCKED' : 'OK';
            $out[] = "$id $m->type loans " . count($m->loans) . ' reservations ' . reservations($m) . ' balance ' . money(balance($m)) . " $state";
        }
    } elseif ($cmd==='INVENTORY') {
        $totals = array_fill_keys(['AVAILABLE','LOANED','HOLD','LOST','WITHDRAWN'],0);
        $lines = [];
        foreach ($bookOrder as $id) {
            $b = $books[$id];
            $n = array_count_values(array_column($b->copies,'state')) + array_fill_keys(array_keys($totals),0);
            foreach ($n as $state=>$count) $totals[$state] += $count;
            $lines[] = "$id copies " . holdings($b) . " available $n[AVAILABLE] loaned $n[LOANED] hold $n[HOLD] queue " . count($b->queue);
        }
        $holding = $totals['AVAILABLE']+$totals['LOANED']+$totals['HOLD'];
        $out[] = 'INVENTORY titles ' . count($books) . " copies $holding available $totals[AVAILABLE] loaned $totals[LOANED] hold $totals[HOLD] lost $totals[LOST] withdrawn $totals[WITHDRAWN]";
        $out = [...$out,...$lines];
    } elseif ($cmd==='STATS') {
        $active = array_sum(array_map(fn($m)=>count($m->loans),$members));
        $outstanding = array_sum(array_map('balance',$members));
        $out[] = "STATS day $day titles " . count($books) . ' members ' . count($members) . ' closed ' . count($closed);
        $out[] = "LOANS borrowed $counts[borrowed] returned $counts[returned] renewed $counts[renewed] lost $counts[lost] active $active";
        $out[] = 'MONEY fines ' . money($counts['FINE']) . ' fees ' . money($counts['FEE']) . ' charges ' . money($counts['PRICE']) . ' paid ' . money($counts['paid']) . ' waived ' . money($counts['waived']) . ' outstanding ' . money($outstanding);
        $top = array_values(array_filter($books,fn($b)=>$b->borrowed>0));
        usort($top,fn($a,$b)=>[-$a->borrowed,$a->id] <=> [-$b->borrowed,$b->id]);
        foreach (array_slice($top,0,3) as $rank=>$b) $out[] = 'TOP ' . ($rank+1) . " $b->id $b->borrowed $b->name";
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
