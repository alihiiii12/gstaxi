import { useEffect, useRef } from 'react';
import maplibregl, { type Map as MapLibreMap, type Marker } from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import type { LatLngTuple } from '../util/requestRouteMap';

export const APP_MAP_DAY_STYLE = `${import.meta.env.BASE_URL}maps/styles/day.json`;
export const APP_MAP_NIGHT_STYLE = `${import.meta.env.BASE_URL}maps/styles/night.json`;

/** مطلوب لعرض العربية بشكل صحيح على MapLibre (بدون عكس الحروف). */
const RTL_TEXT_PLUGIN =
  'https://unpkg.com/@mapbox/mapbox-gl-rtl-text@0.2.3/mapbox-gl-rtl-text.js';

let rtlPluginStarted = false;
export function ensureRtlTextPlugin(): void {
  if (rtlPluginStarted) return;
  rtlPluginStarted = true;
  try {
    // lazy=false حتى تُصحَّح التسميات من أول تحميل
    maplibregl.setRTLTextPlugin(RTL_TEXT_PLUGIN, false);
  } catch {
    /* already set / unsupported */
  }
}

/** بنفسجي مسار التطبيق + غلاف أبيض */
export const APP_ROUTE_COLOR = '#9C27B0';
export const APP_ROUTE_CASING = '#FFFFFF';

export type AppMapLine = {
  id: string;
  positions: LatLngTuple[];
  color: string;
  width?: number;
  opacity?: number;
  dashArray?: number[];
  casing?: boolean;
};

export type AppMapMarker = {
  id: string;
  position: LatLngTuple;
  emoji: string;
  title?: string;
  detail?: string;
  size?: number;
  /** لون خلفية الدائرة (مثلاً حالة السائق) */
  color?: string;
};

type Props = {
  height?: number | string;
  className?: string;
  center?: LatLngTuple;
  zoom?: number;
  pitch?: number;
  night?: boolean;
  lines?: AppMapLine[];
  markers?: AppMapMarker[];
  /** يضبط الإطار مرة عند تغيّر الرمز */
  fitPoints?: LatLngTuple[];
  fitToken?: number | string;
  /** متابعة سلسة لنقطة (موقع السائق) */
  followPos?: LatLngTuple | null;
  followZoom?: number;
  /** نقر على الخريطة → [lat, lng] */
  onMapClick?: (pos: LatLngTuple) => void;
};

function lineGeoJson(positions: LatLngTuple[]): GeoJSON.Feature {
  return {
    type: 'Feature',
    properties: {},
    geometry: {
      type: 'LineString',
      coordinates: positions.map(([lat, lng]) => [lng, lat]),
    },
  };
}

function markerEl(emoji: string, size: number, title?: string, color?: string): HTMLDivElement {
  const el = document.createElement('div');
  el.className = 'app-map-marker';
  el.title = title ?? '';
  el.style.cssText = [
    'display:flex',
    'align-items:center',
    'justify-content:center',
    `width:${size + 10}px`,
    `height:${size + 10}px`,
    'border-radius:50%',
    color ? `background:${color}` : 'background:rgba(255,255,255,0.92)',
    'box-shadow:0 4px 14px rgba(17,33,91,0.22)',
    color ? 'border:2px solid #fff' : 'border:2px solid rgba(17,33,91,0.12)',
    'cursor:pointer',
    'user-select:none',
  ].join(';');
  const span = document.createElement('span');
  span.textContent = emoji;
  span.style.fontSize = `${size}px`;
  span.style.lineHeight = '1';
  el.appendChild(span);
  return el;
}

/** خريطة بأسلوب التطبيق (MapLibre + OpenFreeMap Waze-like). */
export function AppStyleMap({
  height = 280,
  className = '',
  center = [33.5138, 36.2765],
  zoom = 12,
  pitch = 42,
  night = false,
  lines = [],
  markers = [],
  fitPoints = [],
  fitToken = 0,
  followPos = null,
  followZoom = 15,
  onMapClick,
}: Props) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<MapLibreMap | null>(null);
  const markersRef = useRef<Marker[]>([]);
  const readyRef = useRef(false);
  const lastFitRef = useRef<string | number | null>(null);
  const userMovedRef = useRef(false);
  const linesRef = useRef(lines);
  linesRef.current = lines;
  const onMapClickRef = useRef(onMapClick);
  onMapClickRef.current = onMapClick;

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    ensureRtlTextPlugin();
    const map = new maplibregl.Map({
      container: containerRef.current,
      style: night ? APP_MAP_NIGHT_STYLE : APP_MAP_DAY_STYLE,
      center: [center[1], center[0]],
      zoom,
      pitch,
      bearing: 0,
      attributionControl: { compact: true },
    });
    map.addControl(new maplibregl.NavigationControl({ visualizePitch: true }), 'top-left');
    mapRef.current = map;

    const markUserMoved = () => {
      userMovedRef.current = true;
    };
    map.on('dragstart', markUserMoved);
    map.on('zoomstart', (e) => {
      // تجاهل الزوم البرمجي (fitBounds/easeTo) — فقط تفاعل المستخدم
      if (e.originalEvent) markUserMoved();
    });
    map.on('rotatestart', (e) => {
      if (e.originalEvent) markUserMoved();
    });
    map.on('pitchstart', (e) => {
      if (e.originalEvent) markUserMoved();
    });

    const onClick = (e: maplibregl.MapMouseEvent) => {
      const cb = onMapClickRef.current;
      if (!cb) return;
      cb([e.lngLat.lat, e.lngLat.lng]);
    };
    map.on('click', onClick);

    const onLoad = () => {
      readyRef.current = true;
      applyLines(map, linesRef.current);
    };
    map.on('load', onLoad);

    return () => {
      map.off('load', onLoad);
      map.off('click', onClick);
      map.off('dragstart', markUserMoved);
      markersRef.current.forEach((m) => m.remove());
      markersRef.current = [];
      map.remove();
      mapRef.current = null;
      readyRef.current = false;
    };
    // إنشاء مرة واحدة
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    map.getCanvas().style.cursor = onMapClick ? 'crosshair' : '';
  }, [onMapClick]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const styleUrl = night ? APP_MAP_NIGHT_STYLE : APP_MAP_DAY_STYLE;
    readyRef.current = false;
    map.setStyle(styleUrl);
    map.once('style.load', () => {
      readyRef.current = true;
      applyLines(map, linesRef.current);
    });
  }, [night]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !readyRef.current) return;
    applyLines(map, lines);
  }, [lines]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    markersRef.current.forEach((m) => m.remove());
    markersRef.current = [];
    for (const mk of markers) {
      const el = markerEl(mk.emoji, mk.size ?? 22, mk.title, mk.color);
      const marker = new maplibregl.Marker({ element: el, anchor: 'center' })
        .setLngLat([mk.position[1], mk.position[0]])
        .addTo(map);
      if (mk.title || mk.detail) {
        const html = `<strong>${escapeHtml(mk.title ?? '')}</strong>${
          mk.detail ? `<div style="margin-top:4px;font-size:13px">${escapeHtml(mk.detail)}</div>` : ''
        }`;
        marker.setPopup(new maplibregl.Popup({ offset: 18 }).setHTML(html));
      }
      markersRef.current.push(marker);
    }
  }, [markers]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !fitPoints.length) return;
    if (lastFitRef.current === fitToken) return;
    // بعد أن يحرّك المستخدم الخريطة: لا نعيد الإطار إلا عند fitToken جديد صريح
    const tokenChanged =
      lastFitRef.current !== null && lastFitRef.current !== fitToken;
    if (userMovedRef.current && !tokenChanged && lastFitRef.current !== null) {
      return;
    }
    lastFitRef.current = fitToken;
    userMovedRef.current = false;
    if (fitPoints.length === 1) {
      map.easeTo({
        center: [fitPoints[0][1], fitPoints[0][0]],
        zoom: 15,
        pitch,
        duration: 700,
      });
      return;
    }
    const bounds = new maplibregl.LngLatBounds(
      [fitPoints[0][1], fitPoints[0][0]],
      [fitPoints[0][1], fitPoints[0][0]],
    );
    for (const p of fitPoints) bounds.extend([p[1], p[0]]);
    map.fitBounds(bounds, {
      padding: 56,
      maxZoom: 15,
      pitch,
      duration: 800,
    });
  }, [fitPoints, fitToken, pitch]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !followPos) return;
    // لا نلحق بالمتابعة إذا المستخدم يحرّك الخريطة يدوياً
    if (userMovedRef.current) return;
    map.easeTo({
      center: [followPos[1], followPos[0]],
      zoom: Math.max(map.getZoom(), followZoom),
      duration: 650,
    });
  }, [followPos, followZoom]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const t = window.setTimeout(() => map.resize(), 220);
    return () => window.clearTimeout(t);
  }, [height]);

  return (
    <div
      className={`app-style-map ${className}`.trim()}
      dir="ltr"
      style={{
        height: typeof height === 'number' ? `${height}px` : height,
        width: '100%',
        borderRadius: 16,
        overflow: 'hidden',
        position: 'relative',
        direction: 'ltr',
        unicodeBidi: 'isolate',
      }}
    >
      <div
        ref={containerRef}
        dir="ltr"
        style={{ position: 'absolute', inset: 0, direction: 'ltr' }}
      />
    </div>
  );
}

function applyLines(map: MapLibreMap, lines: AppMapLine[]) {
  const existing = map.getStyle()?.layers ?? [];
  for (const layer of existing) {
    if (String(layer.id).startsWith('admin-line-')) {
      try {
        map.removeLayer(layer.id);
      } catch {
        /* ignore */
      }
    }
  }
  const sources = map.getStyle()?.sources ?? {};
  for (const id of Object.keys(sources)) {
    if (id.startsWith('admin-line-')) {
      try {
        map.removeSource(id);
      } catch {
        /* ignore */
      }
    }
  }

  for (const line of lines) {
    if (line.positions.length < 2) continue;
    const srcId = `admin-line-${line.id}`;
    const geo = lineGeoJson(line.positions);
    if (map.getSource(srcId)) {
      (map.getSource(srcId) as maplibregl.GeoJSONSource).setData(geo);
    } else {
      map.addSource(srcId, { type: 'geojson', data: geo });
    }

    if (line.casing !== false) {
      const casingId = `admin-line-${line.id}-casing`;
      if (!map.getLayer(casingId)) {
        map.addLayer({
          id: casingId,
          type: 'line',
          source: srcId,
          layout: { 'line-cap': 'round', 'line-join': 'round' },
          paint: {
            'line-color': APP_ROUTE_CASING,
            'line-width': (line.width ?? 5) + 4,
            'line-opacity': 0.9,
          },
        });
      }
    }

    const layerId = `admin-line-${line.id}-main`;
    if (!map.getLayer(layerId)) {
      map.addLayer({
        id: layerId,
        type: 'line',
        source: srcId,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': line.color,
          'line-width': line.width ?? 5,
          'line-opacity': line.opacity ?? 0.92,
          ...(line.dashArray
            ? { 'line-dasharray': line.dashArray }
            : {}),
        },
      });
    } else {
      map.setPaintProperty(layerId, 'line-color', line.color);
      map.setPaintProperty(layerId, 'line-width', line.width ?? 5);
    }
  }
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
