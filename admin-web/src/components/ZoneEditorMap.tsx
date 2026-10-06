import { useEffect, useRef } from 'react';
import maplibregl, { type Map as MapLibreMap, type Marker } from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import { APP_MAP_DAY_STYLE, ensureRtlTextPlugin } from './AppStyleMap';
import type { LatLngTuple } from '../util/requestRouteMap';

export type ZoneShape = {
  id: number;
  name: string;
  color: string;
  polygon: LatLngTuple[];
  active: boolean;
};

export type TestPin = { position: LatLngTuple; label: string };

type Props = {
  zones: ZoneShape[];
  /** المنطقة قيد التعديل (تُرسم بنقاط قابلة للسحب) */
  editing: { id: number | null; color: string; polygon: LatLngTuple[] } | null;
  onEditingChange?: (polygon: LatLngTuple[]) => void;
  onMapClick?: (pos: LatLngTuple) => void;
  testPins?: TestPin[];
  fitToken?: number;
  height?: number;
};

const SRC_ZONES = 'pz-zones';
const SRC_EDIT = 'pz-edit';

function ring(poly: LatLngTuple[]): number[][] {
  const r = poly.map(([lat, lng]) => [lng, lat]);
  if (r.length) r.push(r[0]);
  return r;
}

function polyArea(poly: LatLngTuple[]): number {
  let s = 0;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    s += poly[j][1] * poly[i][0] - poly[i][1] * poly[j][0];
  }
  return Math.abs(s) / 2;
}

function zonesGeo(zones: ZoneShape[], hideId: number | null): GeoJSON.FeatureCollection {
  return {
    type: 'FeatureCollection',
    // الأكبر أولاً ليظهر الأصغر (مثل المدينة) فوقه.
    features: zones
      .filter((z) => z.polygon.length >= 3 && z.id !== hideId)
      .sort((a, b) => polyArea(b.polygon) - polyArea(a.polygon))
      .map((z) => ({
        type: 'Feature',
        properties: { name: z.name, color: z.color, active: z.active ? 1 : 0 },
        geometry: { type: 'Polygon', coordinates: [ring(z.polygon)] },
      })),
  };
}

function editGeo(poly: LatLngTuple[]): GeoJSON.FeatureCollection {
  if (poly.length < 2) return { type: 'FeatureCollection', features: [] };
  return {
    type: 'FeatureCollection',
    features: [
      poly.length >= 3
        ? {
            type: 'Feature',
            properties: {},
            geometry: { type: 'Polygon', coordinates: [ring(poly)] },
          }
        : {
            type: 'Feature',
            properties: {},
            geometry: { type: 'LineString', coordinates: poly.map(([a, b]) => [b, a]) },
          },
    ],
  };
}

function dotEl(kind: 'vertex' | 'mid', color: string): HTMLDivElement {
  const el = document.createElement('div');
  const size = kind === 'vertex' ? 14 : 10;
  el.style.cssText = [
    `width:${size}px`,
    `height:${size}px`,
    'border-radius:50%',
    kind === 'vertex' ? `background:#fff;border:3px solid ${color}` : `background:${color};opacity:.55;border:2px solid #fff`,
    'box-shadow:0 1px 4px rgba(0,0,0,.35)',
    'cursor:grab',
  ].join(';');
  el.title =
    kind === 'vertex' ? 'اسحب لتعديل الحد — انقر مرتين للحذف' : 'اسحب لإضافة نقطة جديدة هنا';
  return el;
}

function pinEl(label: string): HTMLDivElement {
  const el = document.createElement('div');
  el.textContent = label;
  el.style.cssText = [
    'min-width:30px',
    'height:30px',
    'padding:0 8px',
    'border-radius:15px',
    'display:flex',
    'align-items:center',
    'justify-content:center',
    'background:#11215b',
    'color:#ffc107',
    'font-weight:800',
    'font-size:13px',
    'box-shadow:0 4px 12px rgba(0,0,0,.3)',
    'border:2px solid #fff',
  ].join(';');
  return el;
}

export function ZoneEditorMap({
  zones,
  editing,
  onEditingChange,
  onMapClick,
  testPins = [],
  fitToken = 0,
  height = 520,
}: Props) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<MapLibreMap | null>(null);
  const readyRef = useRef(false);
  const handleMarkersRef = useRef<Marker[]>([]);
  const pinMarkersRef = useRef<Marker[]>([]);
  const propsRef = useRef({ zones, editing, onEditingChange, onMapClick });
  propsRef.current = { zones, editing, onEditingChange, onMapClick };

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    ensureRtlTextPlugin();
    const map = new maplibregl.Map({
      container: containerRef.current,
      style: APP_MAP_DAY_STYLE,
      center: [36.29, 33.5],
      zoom: 10.6,
      pitch: 0,
      attributionControl: { compact: true },
    });
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-left');
    map.doubleClickZoom.disable();
    mapRef.current = map;

    map.on('load', () => {
      map.addSource(SRC_ZONES, { type: 'geojson', data: zonesGeo([], null) });
      map.addLayer({
        id: 'pz-zones-fill',
        type: 'fill',
        source: SRC_ZONES,
        paint: {
          'fill-color': ['get', 'color'],
          'fill-opacity': ['case', ['==', ['get', 'active'], 1], 0.2, 0.06],
        },
      });
      map.addLayer({
        id: 'pz-zones-line',
        type: 'line',
        source: SRC_ZONES,
        paint: {
          'line-color': ['get', 'color'],
          'line-width': 2.5,
          'line-opacity': ['case', ['==', ['get', 'active'], 1], 1, 0.35],
        },
      });
      map.addLayer({
        id: 'pz-zones-label',
        type: 'symbol',
        source: SRC_ZONES,
        layout: { 'text-field': ['get', 'name'], 'text-size': 14, 'text-font': ['Noto Sans Regular'] },
        paint: { 'text-color': '#11215b', 'text-halo-color': '#fff', 'text-halo-width': 2 },
      });
      map.addSource(SRC_EDIT, { type: 'geojson', data: editGeo([]) });
      map.addLayer({
        id: 'pz-edit-fill',
        type: 'fill',
        source: SRC_EDIT,
        paint: { 'fill-color': '#ffc107', 'fill-opacity': 0.22 },
      });
      map.addLayer({
        id: 'pz-edit-line',
        type: 'line',
        source: SRC_EDIT,
        paint: { 'line-color': '#e0a800', 'line-width': 3 },
      });
      readyRef.current = true;
      redraw();
    });

    map.on('click', (e) => {
      propsRef.current.onMapClick?.([e.lngLat.lat, e.lngLat.lng]);
    });

    return () => {
      handleMarkersRef.current.forEach((m) => m.remove());
      pinMarkersRef.current.forEach((m) => m.remove());
      map.remove();
      mapRef.current = null;
      readyRef.current = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function redraw() {
    const map = mapRef.current;
    if (!map || !readyRef.current) return;
    const { zones: zs, editing: ed } = propsRef.current;
    (map.getSource(SRC_ZONES) as maplibregl.GeoJSONSource | undefined)?.setData(
      zonesGeo(zs, ed?.id ?? null),
    );
    (map.getSource(SRC_EDIT) as maplibregl.GeoJSONSource | undefined)?.setData(
      editGeo(ed?.polygon ?? []),
    );
    rebuildHandles();
  }

  function rebuildHandles() {
    const map = mapRef.current;
    if (!map) return;
    handleMarkersRef.current.forEach((m) => m.remove());
    handleMarkersRef.current = [];
    const ed = propsRef.current.editing;
    if (!ed) return;
    const poly = ed.polygon;
    const emit = (next: LatLngTuple[]) => propsRef.current.onEditingChange?.(next);

    poly.forEach((p, i) => {
      const el = dotEl('vertex', '#11215b');
      const mk = new maplibregl.Marker({ element: el, draggable: true })
        .setLngLat([p[1], p[0]])
        .addTo(map);
      mk.on('drag', () => {
        const ll = mk.getLngLat();
        const cur = propsRef.current.editing?.polygon ?? poly;
        const next = cur.slice();
        next[i] = [ll.lat, ll.lng];
        (map.getSource(SRC_EDIT) as maplibregl.GeoJSONSource | undefined)?.setData(editGeo(next));
      });
      mk.on('dragend', () => {
        const ll = mk.getLngLat();
        const next = poly.slice();
        next[i] = [ll.lat, ll.lng];
        emit(next);
      });
      el.addEventListener('dblclick', (ev) => {
        ev.stopPropagation();
        if (poly.length <= 3) return;
        emit(poly.filter((_, k) => k !== i));
      });
      el.addEventListener('click', (ev) => ev.stopPropagation());
      handleMarkersRef.current.push(mk);
    });

    if (poly.length >= 3) {
      poly.forEach((p, i) => {
        const q = poly[(i + 1) % poly.length];
        const mid: LatLngTuple = [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2];
        const el = dotEl('mid', '#11215b');
        const mk = new maplibregl.Marker({ element: el, draggable: true })
          .setLngLat([mid[1], mid[0]])
          .addTo(map);
        mk.on('dragend', () => {
          const ll = mk.getLngLat();
          const next = poly.slice();
          next.splice(i + 1, 0, [ll.lat, ll.lng]);
          emit(next);
        });
        el.addEventListener('click', (ev) => ev.stopPropagation());
        handleMarkersRef.current.push(mk);
      });
    }
  }

  useEffect(() => {
    redraw();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [zones, editing]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    pinMarkersRef.current.forEach((m) => m.remove());
    pinMarkersRef.current = testPins.map((p) =>
      new maplibregl.Marker({ element: pinEl(p.label) })
        .setLngLat([p.position[1], p.position[0]])
        .addTo(map),
    );
  }, [testPins]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    map.getCanvas().style.cursor = onMapClick ? 'crosshair' : '';
  }, [onMapClick]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !fitToken) return;
    const pts = editing?.polygon.length
      ? editing.polygon
      : zones.flatMap((z) => z.polygon);
    if (pts.length < 2) return;
    const b = new maplibregl.LngLatBounds([pts[0][1], pts[0][0]], [pts[0][1], pts[0][0]]);
    for (const p of pts) b.extend([p[1], p[0]]);
    map.fitBounds(b, { padding: 50, duration: 600, maxZoom: 14 });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fitToken]);

  return (
    <div
      dir="ltr"
      style={{
        height,
        width: '100%',
        borderRadius: 16,
        overflow: 'hidden',
        position: 'relative',
        direction: 'ltr',
        border: '1px solid #dde3f0',
      }}
    >
      <div ref={containerRef} style={{ position: 'absolute', inset: 0 }} />
    </div>
  );
}
