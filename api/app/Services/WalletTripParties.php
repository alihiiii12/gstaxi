<?php

namespace App\Services;

use App\Models\RequestModel;
use App\Models\User;

/** أسماء الراكب والسائق لحركات المحافظ المرتبطة برحلة. */
class WalletTripParties
{
    /**
     * @param  array<int|null>  $requestIds
     * @return array<int, array{customer_id: ?int, customer_name: ?string, driver_id: ?int, driver_name: ?string}>
     */
    public static function forRequestIds(array $requestIds): array
    {
        $ids = array_values(array_unique(array_filter(array_map('intval', $requestIds))));
        if ($ids === []) {
            return [];
        }

        $rows = RequestModel::withTrashed()
            ->whereIn('id', $ids)
            ->with([
                'user' => fn ($q) => $q->withTrashed()->select('id', 'firstName', 'lastName'),
                'driver' => fn ($q) => $q->withTrashed()->select('id', 'userId'),
                'driver.user' => fn ($q) => $q->withTrashed()->select('id', 'firstName', 'lastName'),
            ])
            ->get(['id', 'userId', 'driverId']);

        $out = [];
        foreach ($rows as $r) {
            $driverUser = $r->driver?->user;
            $out[(int) $r->id] = [
                'customer_id' => $r->userId ? (int) $r->userId : null,
                'customer_name' => self::name($r->user) ?? ($r->userId ? 'زبون #'.$r->userId : null),
                'driver_id' => $r->driverId ? (int) $r->driverId : null,
                'driver_name' => self::name($driverUser) ?? ($r->driverId ? 'سائق #'.$r->driverId : null),
            ];
        }

        return $out;
    }

    public static function name(?User $u): ?string
    {
        if (! $u) {
            return null;
        }
        $n = trim(($u->firstName ?? '').' '.($u->lastName ?? ''));

        return $n !== '' ? $n : null;
    }

    /** يضيف أسماء الطرفين وسطر «السائق: …» أو «الراكب: …» لقائمة حركات. */
    public static function attach(array $txPayloads, string $side): array
    {
        $parties = self::forRequestIds(array_column($txPayloads, 'request_id'));
        foreach ($txPayloads as &$tx) {
            $p = $tx['request_id'] ? ($parties[(int) $tx['request_id']] ?? null) : null;
            $tx['customer_name'] = $p['customer_name'] ?? null;
            $tx['driver_name'] = $p['driver_name'] ?? null;
            $tx['customer_id'] = $p['customer_id'] ?? null;
            $tx['driver_id'] = $p['driver_id'] ?? null;
            $other = $side === 'customer' ? $tx['driver_name'] : $tx['customer_name'];
            $tx['counterparty_label'] = $other
                ? ($side === 'customer' ? 'السائق: ' : 'الراكب: ').$other
                : null;
        }
        unset($tx);

        return $txPayloads;
    }
}
