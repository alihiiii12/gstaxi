<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Expires: 0');

$path = __DIR__.DIRECTORY_SEPARATOR.'data'.DIRECTORY_SEPARATOR.'content.json';
if (! is_file($path)) {
    echo '{}';
    exit;
}
readfile($path);
