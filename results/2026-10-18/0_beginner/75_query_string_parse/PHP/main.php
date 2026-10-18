<?php
function decodeComponent(string $source): string {
    $output = '';
    for ($i = 0; $i < strlen($source);) {
        if ($source[$i] === '+') {
            $output .= ' ';
            $i++;
        } elseif ($source[$i] === '%') {
            $output .= chr(hexdec(substr($source,$i+1,2)));
            $i += 3;
        } else {
            $output .= $source[$i];
            $i++;
        }
    }
    return $output;
}
$queries = ['name=Alice+Smith&age=30&city=New%20York','q=c%2B%2B+tutorial&page=2&sort=desc&page=3','msg=50%25+off%21&debug&lang=en&ref=&lang=ja','redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips'];
foreach ($queries as $number => $query) {
    $parameters = [];
    foreach (explode('&',$query) as $item) {
        $parts = explode('=',$item,2);
        $key = decodeComponent($parts[0]);
        $parameters[$key][] = isset($parts[1]) ? decodeComponent($parts[1]) : '';
    }
    ksort($parameters,SORT_STRING);
    printf("query %d:\n",$number+1);
    foreach ($parameters as $key => $values) {
        $quoted = array_map(fn($value) => '"'.$value.'"',$values);
        echo '  ', $key, ': ', implode(', ',$quoted), "\n";
    }
}
