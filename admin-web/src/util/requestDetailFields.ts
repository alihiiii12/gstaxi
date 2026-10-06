import { recordFromJsonMaybe } from './tripPathLabels';

export function personName(
  u: Record<string, unknown> | undefined,
  fallback = '—',
): string {
  if (!u) return fallback;
  const n = `${u.firstName ?? ''} ${u.lastName ?? ''}`.trim();
  return n || fallback;
}

function trimDyn(v: unknown): string | null {
  if (v == null) return null;
  const s = String(v).trim();
  return s.length ? s : null;
}

/** اسم منطقة/عنوان من كائن موقع — بدون إحداثيات. */
export function areaLabelFromLocationJson(
  loc: Record<string, unknown> | undefined,
): string {
  if (!loc) return '';
  const keys = [
    'area_name',
    'areaName',
    'zone_name',
    'zoneName',
    'name',
    'label',
    'address',
    'formatted_address',
    'formattedAddress',
    'title',
    'description',
    'locationDesc',
    'placeName',
    'place_name',
    'display_name',
    'displayName',
  ];
  for (const k of keys) {
    const t = trimDyn(loc[k]);
    if (t) return t;
  }
  for (const nest of ['service_area', 'serviceArea', 'area', 'zone']) {
    const inner = loc[nest];
    if (inner && typeof inner === 'object') {
      const im = inner as Record<string, unknown>;
      const t = trimDyn(im.name ?? im.title ?? im.label);
      if (t) return t;
    }
  }
  return '';
}

/** اسم نقطة انطلاق أو وجهة من الطلب + علاقة الموقع. */
export function areaLabelFromRequestForPoint(
  request: Record<string, unknown>,
  locationJson: Record<string, unknown> | undefined,
  destination: boolean,
): string {
  const fromLoc = areaLabelFromLocationJson(locationJson);
  if (fromLoc) return fromLoc;

  if (!destination) {
    for (const key of [
      'pickup_service_area',
      'pickupServiceArea',
      'start_service_area',
      'startServiceArea',
    ]) {
      const sa = request[key];
      if (sa && typeof sa === 'object') {
        const t = trimDyn((sa as Record<string, unknown>).name);
        if (t) return t;
      }
    }
    const sa = request.service_area ?? request.serviceArea;
    if (sa && typeof sa === 'object') {
      const t = trimDyn((sa as Record<string, unknown>).name);
      if (t) return t;
    }
    const ld = trimDyn(request.locationDesc ?? request.location_desc);
    if (ld) return ld;
  } else {
    for (const key of [
      'dest_service_area',
      'destServiceArea',
      'destination_service_area',
      'destinationServiceArea',
      'drop_service_area',
      'dropServiceArea',
    ]) {
      const sa = request[key];
      if (sa && typeof sa === 'object') {
        const t = trimDyn((sa as Record<string, unknown>).name);
        if (t) return t;
      }
    }
  }

  return '—';
}

/** للعرض في التفاصيل والقوائم — اسم فقط بدون إحداثيات. */
export function locationNameOnly(
  request: Record<string, unknown>,
  loc: Record<string, unknown> | undefined,
  destination: boolean,
): string {
  const label = areaLabelFromRequestForPoint(request, loc, destination);
  return label !== '—' ? label : 'غير معرّف';
}

/** @deprecated استخدم locationNameOnly */
export function locationLabel(loc: Record<string, unknown> | undefined): string {
  return areaLabelFromLocationJson(loc) || '—';
}

export function requestLocations(r: Record<string, unknown>) {
  const start =
    (r.start_location as Record<string, unknown> | undefined) ??
    (r.startLocation as Record<string, unknown> | undefined);
  const dest =
    (r.dest_location as Record<string, unknown> | undefined) ??
    (r.destLocation as Record<string, unknown> | undefined);
  return { start, dest };
}

function labelFromApiFields(
  r: Record<string, unknown>,
  destination: boolean,
): string | null {
  const keys = destination
    ? ['dest_label', 'destLabel', 'destination_label', 'destinationLabel']
    : ['pickup_label', 'pickupLabel', 'start_label', 'startLabel'];
  for (const k of keys) {
    const t = trimDyn(r[k]);
    if (t) return t;
  }
  return null;
}

export function pickupDestLabelsFromRequest(r: Record<string, unknown>): {
  pickup: string;
  dest: string;
} {
  const { start, dest } = requestLocations(r);
  const apiPickup = labelFromApiFields(r, false);
  const apiDest = labelFromApiFields(r, true);
  return {
    pickup: apiPickup ?? locationNameOnly(r, start, false),
    dest: apiDest ?? locationNameOnly(r, dest, true),
  };
}

export function requestHistory(r: Record<string, unknown>) {
  return recordFromJsonMaybe(r.history) ?? recordFromJsonMaybe(r.History);
}

export function requestCustomer(r: Record<string, unknown>) {
  return r.user as Record<string, unknown> | undefined;
}

export function requestDriverUser(r: Record<string, unknown>) {
  const driver = r.driver as Record<string, unknown> | undefined;
  if (!driver) return undefined;
  return driver.user as Record<string, unknown> | undefined;
}
