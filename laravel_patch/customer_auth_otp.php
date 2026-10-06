<?php

/**
 * تسجيل زبون + OTP + استعادة كلمة المرور — طُبّق على SyriaTaxi-main.
 *
 * الملفات:
 * - database/migrations/2026_05_15_120000_add_phone_verified_at_to_users_table.php
 * - app/Services/PhoneOtpService.php
 * - app/Http/Requests/CustomerRegisterRequest.php
 * - app/Http/Controllers/UserController.php (دوال registerCustomer, confirmAccount, …)
 * - routes/api.php
 *
 * مسارات API:
 * POST /register-customer
 * POST /confirm-account          { number, code, fcm_token? }
 *   → يُرجع user + token (دخول تلقائي للزبون بعد التأكيد)
 * POST /confirmation-code/resend { number, purpose: register|reset_password }
 * POST /forget-password          { number }
 * POST /forget-password/check-code { number, code }
 * POST /forget-password/reset    { number, reset_token, password, password_confirmation }
 *
 * الرمز يُسجَّل في storage/logs/laravel.log أثناء التطوير (واتساب لاحقاً).
 */
