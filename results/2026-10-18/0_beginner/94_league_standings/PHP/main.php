<?php
$teams = ['Lions','Tigers','Eagles','Sharks','Wolves','Bears'];
$records = array_fill_keys($teams,array_fill(0,7,0));
$matches = ['Lions 0-3 Bears','Tigers 2-2 Wolves','Eagles 4-0 Sharks','Bears 0-1 Sharks','Wolves 2-1 Eagles','Lions 0-1 Tigers','Tigers 3-3 Bears','Eagles 2-2 Lions','Sharks 2-2 Wolves','Bears 3-1 Wolves','Lions 2-0 Sharks','Tigers 2-1 Eagles','Eagles 1-0 Bears','Sharks 2-0 Tigers','Wolves 2-1 Lions'];
foreach ($matches as $match) {
    [$home,$score,$away] = explode(' ',$match);
    [$h,$a] = array_map('intval',explode('-',$score));
    foreach ([[$home,$h,$a],[$away,$a,$h]] as [$team,$gf,$ga]) {
        $records[$team][0]++;
        $records[$team][4] += $gf;
        $records[$team][5] += $ga;
        if ($gf > $ga) {
            $records[$team][1]++;
            $records[$team][6] += 3;
        } elseif ($gf === $ga) {
            $records[$team][2]++;
            $records[$team][6]++;
        } else {
            $records[$team][3]++;
        }
    }
}
usort($teams,function($a,$b) use ($records) {
    $x = $records[$a];
    $y = $records[$b];
    return ($y[6]<=>$x[6]) ?: (($y[4]-$y[5])<=>($x[4]-$x[5])) ?: ($y[4]<=>$x[4]) ?: strcmp($a,$b);
});
foreach ($teams as $position => $team) {
    [$played,$wins,$draws,$losses,$gf,$ga,$points] = $records[$team];
    $difference = $gf-$ga;
    $signed = $difference > 0 ? '+'.$difference : (string)$difference;
    printf("%d. %s P=%d W=%d D=%d L=%d GF=%d GA=%d GD=%s Pts=%d\n",$position+1,$team,$played,$wins,$draws,$losses,$gf,$ga,$signed,$points);
}
