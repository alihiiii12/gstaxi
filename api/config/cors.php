<?php

return [

    'paths' => ['api/*', 'sanctum/csrf-cookie'],

    'allowed_methods' => ['*'],

    // VUL-09: لا تستخدم * مع بيانات حساسة — نطاقات النظام فقط
    'allowed_origins' => array_values(array_filter([
        env('FRONTEND_URL', 'https://gstaxi.online'),
        'https://gstaxi.online',
        'https://www.gstaxi.online',
        'http://gstaxi.online',
        'http://www.gstaxi.online',
        'http://127.0.0.1:5173',
        'http://localhost:5173',
        env('APP_URL'),
    ])),

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => false,

];
