<?php

$identifiers = [
    'user_name', 'maxRetryCount', 'ShoppingCartItem', 'background-color', 'get_last_login_time',
    'isEmailAddressValid',
];
foreach ($identifiers as $identifier) {
    $separated = preg_replace('/([A-Z])/', ' $1', $identifier);
    $words = preg_split('/[_\- ]+/', strtolower($separated), -1, PREG_SPLIT_NO_EMPTY);
    $capitals = array_map('ucfirst', $words);
    $camel = $words[0] . implode('', array_slice($capitals, 1));
    printf(
        "%s: snake=%s, camel=%s, pascal=%s, kebab=%s\n",
        $identifier,
        implode('_', $words),
        $camel,
        implode('', $capitals),
        implode('-', $words),
    );
}
