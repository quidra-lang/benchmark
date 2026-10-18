<?php
$counts = array_fill(0, 26, 0);
foreach (str_split(strtolower('Peter Piper picked a peck of pickled peppers!')) as $letter) {
    $code = ord($letter);
    if ($code >= 97 && $code <= 122) $counts[$code-97]++;
}
foreach ($counts as $i => $count) if ($count > 0) printf("%s: %d\n", chr(97+$i), $count);
