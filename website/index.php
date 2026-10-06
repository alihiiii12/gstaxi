<?php

declare(strict_types=1);

header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

$file = __DIR__.'/index.html';
if (! is_file($file)) {
    http_response_code(404);
    echo 'index.html missing';
    exit;
}

header('Content-Type: text/html; charset=utf-8');
readfile($file);
