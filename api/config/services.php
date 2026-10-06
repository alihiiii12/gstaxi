<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    /*
    | مسار ملف حساب الخدمة JSON من Firebase (مفاتيح حساب الخدمة → إنشاء مفتاح).
    | مثال: storage_path('firebase/service-account.json')
    */
    'firebase' => [
        'credentials' => env(
            'FIREBASE_CREDENTIALS_PATH',
            storage_path('firebase/service-account.json')
        ),
        'project_id' => env('FIREBASE_PROJECT_ID', 'syriataxi-f46d3'),
    ],

    /*
    | UltraMsg — واتساب (اختياري؛ البث الجماعي فقط إن بقي مستخدماً)
    */
    'ultramsg' => [
        'instance_id' => env('ULTRAMSG_INSTANCE_ID', '187935'),
        'token' => env('ULTRAMSG_TOKEN', ''),
    ],

    /*
    | MTN Syria SMS — رمز التحقق OTP عبر ConcatenatedSender
    */
    'mtn_sms' => [
        'url' => env(
            'MTN_SMS_URL',
            'https://services.mtnsyr.com:7443/general/MTNSERVICES/ConcatenatedSender.aspx'
        ),
        'username' => env('MTN_SMS_USER', ''),
        'password' => env('MTN_SMS_PASS', ''),
        'from' => env('MTN_SMS_FROM', 'GSTaxi'),
        // شهادة المنفذ 7443 غالباً تحتاج تعطيل التحقق
        'verify_ssl' => filter_var(env('MTN_SMS_VERIFY_SSL', false), FILTER_VALIDATE_BOOLEAN),
        // مهلات قصيرة: إن فشل MTN يمرّ OTP فوراً لاحتياطي واتساب.
        'timeout' => (int) env('MTN_SMS_TIMEOUT', 12),
        'connect_timeout' => (int) env('MTN_SMS_CONNECT_TIMEOUT', 5),
        'retries' => (int) env('MTN_SMS_RETRIES', 1),
        // إجبار الخروج عبر واي فاي Ghafir (STE) بدل Starlink على الإيثرنت.
        // يجب اسم الواجهة (مثل wlp131s0) وليس IP — الربط بالـ IP يبقى على مسار Starlink.
        'bind_interface' => env('MTN_SMS_BIND_INTERFACE', 'wlp131s0'),
    ],

    /*
    | OTP — القناة: sms (MTN ثم احتياطي واتساب) | whatsapp | auto
    | OTP_BYPASS=false في الإنتاج.
    */
    'otp' => [
        'channel' => env('OTP_CHANNEL', 'sms'),
        'bypass' => filter_var(env('OTP_BYPASS', false), FILTER_VALIDATE_BOOLEAN),
        'fallback_code' => env('OTP_FALLBACK_CODE', '0000'),
        'expose_in_api' => filter_var(env('EXPOSE_OTP_IN_API', false), FILTER_VALIDATE_BOOLEAN),
    ],

];
