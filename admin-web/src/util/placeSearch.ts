import { API } from '../api/endpoints';
import { fetchJsonAuth } from '../api/http';
import type { LatLngTuple } from './requestRouteMap';

export type PlaceHit = {
  name: string;
  subtitle: string;
  position: LatLngTuple;
};

/** بحث أماكن عبر API اللوحة (Photon/Nominatim من السيرفر — بدون CORS) */
export async function searchPlaces(
  query: string,
  near?: LatLngTuple | null,
  limit = 8,
): Promise<PlaceHit[]> {
  const q = query.trim();
  if (q.length < 2) return [];
  const params = new URLSearchParams({
    q,
    limit: String(limit),
  });
  if (near) {
    params.set('lat', String(near[0]));
    params.set('lng', String(near[1]));
  }
  try {
    const { res, data: j } = await fetchJsonAuth(
      `${API.adminPlacesSearch}?${params}`,
    );
    if (!res.ok || j.success !== true) return [];
    const rows = (j.data as unknown[]) ?? [];
    const out: PlaceHit[] = [];
    for (const raw of rows) {
      const row = raw as Record<string, unknown>;
      const pos = row.position as number[] | undefined;
      if (!Array.isArray(pos) || pos.length < 2) continue;
      const lat = Number(pos[0]);
      const lng = Number(pos[1]);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
      out.push({
        name: String(row.name ?? 'موقع'),
        subtitle: String(row.subtitle ?? ''),
        position: [lat, lng],
      });
    }
    return out;
  } catch {
    return [];
  }
}

/** عكس إحداثيات → اسم مقروء عبر API اللوحة */
export async function reversePlaceName(
  lat: number,
  lng: number,
): Promise<string> {
  const fallback = `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
  try {
    const params = new URLSearchParams({
      lat: String(lat),
      lng: String(lng),
    });
    const { res, data: j } = await fetchJsonAuth(
      `${API.adminPlacesReverse}?${params}`,
    );
    if (!res.ok || j.success !== true) return fallback;
    const data = j.data as Record<string, unknown> | undefined;
    const name = String(data?.name ?? '').trim();
    return name || fallback;
  } catch {
    return fallback;
  }
}
