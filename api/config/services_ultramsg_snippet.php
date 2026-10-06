<?php

/**
 * أضف هذا المفتاح داخل return [...] في config/services.php على السيرفر/XAMPP:
 *
 * 'ultramsg' => [
 *     'instance_id' => env('ULTRAMSG_INSTANCE_ID', '187935'),
 *     'token' => env('ULTRAMSG_TOKEN', ''),
 * ],
 */

return [
    'ultramsg' => [
        'instance_id' => env('ULTRAMSG_INSTANCE_ID', '187935'),
        'token' => env('ULTRAMSG_TOKEN', ''),
    ],
];
