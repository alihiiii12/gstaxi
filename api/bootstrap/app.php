<?php

use Illuminate\Auth\AuthenticationException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Session\TokenMismatchException;

return Application::configure(basePath: dirname(__DIR__))
    ->withSchedule(function (\Illuminate\Console\Scheduling\Schedule $schedule): void {
        $schedule->command('subscriptions:expire-drivers')->dailyAt('02:00');
        $schedule->command('subscriptions:warn-drivers-48h')->dailyAt('10:00');
        $schedule->command('drivers:process-subscriptions')->hourly();
        $schedule->command('bookings:send-reminders')->everyMinute();
        $schedule->command('requests:expand-searching')->everyTenSeconds()->withoutOverlapping(1);
        $schedule->command('requests:expire-stale-pending')->hourly();
        $schedule->command('free-meter:close-stale')->everyTenMinutes()->withoutOverlapping(10);
    })
    ->withRouting(
        web: __DIR__ . '/../routes/web.php',
        api: __DIR__ . '/../routes/api.php',
        apiPrefix: 'api',
        commands: __DIR__ . '/../routes/console.php',
        channels: __DIR__ . '/../routes/channels.php',
        health: '/up',
    )
    ->withBroadcasting(
        __DIR__ . '/../routes/channels.php'
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // التطبيق + لوحة الإدارة: Bearer token فقط — بدون جلسة Sanctum/CSRF على API
        $middleware->validateCsrfTokens(except: [
            'api/*',
            'sanctum/*',
        ]);
        $middleware->append(\App\Http\Middleware\SecurityHeaders::class);
        $middleware->appendToGroup('api', \App\Http\Middleware\RejectWhenServiceCut::class);
        $middleware->alias([
            'auth' => \App\Http\Middleware\Authenticate::class,
            'driver.poll' => \App\Http\Middleware\ThrottleDriverPoll::class,
            'staff' => \App\Http\Middleware\EnsureBackofficeStaff::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->render(function (AuthenticationException $e, $request) {
            return response()->json([
                'state' => false,
                'message' => 'You Must Login First',
            ], 401);
        });
        $exceptions->render(function (TokenMismatchException $e, $request) {
            if ($request->is('api/*') || $request->expectsJson()) {
                return response()->json([
                    'success' => false,
                    'state' => false,
                    'message' => 'CSRF token mismatch — حدّث bootstrap/app.php على السيرفر',
                ], 419);
            }

            return null;
        });
    })->create();
