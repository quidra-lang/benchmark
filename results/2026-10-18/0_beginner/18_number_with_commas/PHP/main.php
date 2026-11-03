<?php

foreach ([0, 7, 999, 1000, -456789, 3141592, 9876543210] as $n) {
    echo number_format($n, 0, '.', ','), "\n";
}
