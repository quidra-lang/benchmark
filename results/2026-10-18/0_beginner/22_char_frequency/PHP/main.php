<?php

foreach (count_chars(strtolower('Peter Piper picked a peck of pickled peppers!'), 1) as $code => $count) {
    if ($code >= 97 && $code <= 122) {
        printf("%s: %d\n", chr($code), $count);
    }
}
