<?php
$students = [['Tanaka',78,85,94],['Suzuki',88,74,82],['Yamada',65,90,71],['Ito',80,79,85],['Kato',92,88,95],['Mori',70,62,78]];
foreach ($students as &$student) $student['total'] = $student[1]+$student[2]+$student[3];
unset($student);
usort($students,fn($a,$b) => ($b['total']<=>$a['total']) ?: strcmp($a[0],$b[0]));
$rank = 0; $previous = -1;
foreach ($students as $position => $student) {
    if ($student['total'] !== $previous) $rank = $position+1;
    printf("%d. %s total=%d average=%.2F\n",$rank,$student[0],$student['total'],round($student['total']/3,2,PHP_ROUND_HALF_UP));
    $previous = $student['total'];
}
