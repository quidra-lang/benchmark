<?php

foreach ([0, 10, 255, 1000, 43981, 65535] as $n) {
    printf("%d: bin=%s oct=%s hex=%s\n", $n, decbin($n), decoct($n), strtoupper(dechex($n)));
}
