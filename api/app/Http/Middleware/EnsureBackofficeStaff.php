<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/** يمنع وصول غير الموظفين لمسارات الإدارة/التقارير. */
class EnsureBackofficeStaff
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if (! $user || ! $user->isBackofficeStaff()) {
            return response()->json([
                'success' => false,
                'state' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        return $next($request);
    }
}
