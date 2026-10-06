import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  AppStyleMap,
  type AppMapMarker,
} from './AppStyleMap';
import type { LatLngTuple } from '../util/requestRouteMap';
import { reversePlaceName, searchPlaces, type PlaceHit } from '../util/placeSearch';

type Props = {
  label: string;
  emoji: string;
  value: { position: LatLngTuple; name: string } | null;
  onChange: (next: { position: LatLngTuple; name: string } | null) => void;
  disabled?: boolean;
  near?: LatLngTuple | null;
};

const DAMASCUS: LatLngTuple = [33.5138, 36.2765];

/** اختيار موقع: بحث مكان + نقر على الخريطة (مثل التطبيق) */
export function MapPlacePicker({
  label,
  emoji,
  value,
  onChange,
  disabled,
  near,
}: Props) {
  const [query, setQuery] = useState('');
  const [debounced, setDebounced] = useState('');
  const [hits, setHits] = useState<PlaceHit[]>([]);
  const [searching, setSearching] = useState(false);
  const [resolving, setResolving] = useState(false);
  const [fitToken, setFitToken] = useState(0);

  useEffect(() => {
    const t = window.setTimeout(() => setDebounced(query.trim()), 350);
    return () => window.clearTimeout(t);
  }, [query]);

  useEffect(() => {
    if (debounced.length < 2) {
      setHits([]);
      return;
    }
    let cancelled = false;
    setSearching(true);
    void searchPlaces(debounced, near ?? value?.position ?? DAMASCUS).then(
      (list) => {
        if (!cancelled) setHits(list);
      },
    ).finally(() => {
      if (!cancelled) setSearching(false);
    });
    return () => {
      cancelled = true;
    };
  }, [debounced, near, value?.position]);

  const pickPos = useCallback(
    async (pos: LatLngTuple, nameHint?: string) => {
      setResolving(true);
      try {
        const name =
          nameHint?.trim() ||
          (await reversePlaceName(pos[0], pos[1]));
        onChange({ position: pos, name });
        setQuery('');
        setHits([]);
        setFitToken((n) => n + 1);
      } finally {
        setResolving(false);
      }
    },
    [onChange],
  );

  const markers = useMemo((): AppMapMarker[] => {
    if (!value) return [];
    return [
      {
        id: 'picked',
        position: value.position,
        emoji,
        title: label,
        detail: value.name,
        size: 24,
      },
    ];
  }, [value, emoji, label]);

  return (
    <div style={{ marginTop: 8 }}>
      <div className="row-between wrap" style={{ gap: 8, alignItems: 'center' }}>
        <strong>
          {emoji} {label}
        </strong>
        {value && (
          <button
            type="button"
            className="btn-ghost"
            style={{ fontSize: 12, padding: '4px 10px' }}
            disabled={disabled}
            onClick={() => onChange(null)}
          >
            مسح
          </button>
        )}
      </div>

      {value ? (
        <p style={{ margin: '8px 0', fontSize: 14 }}>
          <strong>{value.name}</strong>
          <span className="text-muted" style={{ display: 'block', fontSize: 12 }}>
            {value.position[0].toFixed(5)}, {value.position[1].toFixed(5)}
          </span>
        </p>
      ) : (
        <p className="text-muted" style={{ margin: '6px 0', fontSize: 13 }}>
          ابحث عن المكان أو انقر على الخريطة لتحديد الموقع.
        </p>
      )}

      <label className="field-block" style={{ display: 'block', marginBottom: 8 }}>
        بحث عن مكان
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="مثال: باب توما، المزة…"
          disabled={disabled || resolving}
          autoComplete="off"
          dir="rtl"
        />
      </label>

      {(searching || hits.length > 0 || debounced.length >= 2) && (
        <div
          style={{
            maxHeight: 160,
            overflowY: 'auto',
            border: '1px solid var(--border, #ddd)',
            borderRadius: 10,
            marginBottom: 8,
          }}
        >
          {searching && (
            <p className="text-muted" style={{ padding: 10, margin: 0, fontSize: 13 }}>
              جاري البحث…
            </p>
          )}
          {!searching &&
            hits.map((h, i) => (
              <button
                key={`${h.position[0]}-${h.position[1]}-${i}`}
                type="button"
                disabled={disabled || resolving}
                onClick={() =>
                  void pickPos(
                    h.position,
                    h.subtitle ? `${h.name} — ${h.subtitle}` : h.name,
                  )
                }
                style={{
                  display: 'block',
                  width: '100%',
                  textAlign: 'right',
                  padding: '8px 10px',
                  border: 'none',
                  borderBottom: '1px solid var(--border, #eee)',
                  background: 'transparent',
                  cursor: 'pointer',
                  font: 'inherit',
                }}
              >
                <strong>{h.name}</strong>
                {h.subtitle && (
                  <div className="text-muted" style={{ fontSize: 12 }}>
                    {h.subtitle}
                  </div>
                )}
              </button>
            ))}
          {!searching && debounced.length >= 2 && hits.length === 0 && (
            <p className="text-muted" style={{ padding: 10, margin: 0, fontSize: 13 }}>
              لا نتائج لـ «{debounced}» — جرّب اسماً آخر أو انقر على الخريطة
            </p>
          )}
        </div>
      )}

      <AppStyleMap
        height={220}
        center={value?.position ?? near ?? DAMASCUS}
        zoom={value ? 15 : 12}
        pitch={40}
        markers={markers}
        fitPoints={value ? [value.position] : []}
        fitToken={fitToken}
        onMapClick={
          disabled || resolving
            ? undefined
            : (pos) => {
                void pickPos(pos);
              }
        }
      />
      {resolving && (
        <p className="text-muted" style={{ fontSize: 12, marginTop: 6 }}>
          جاري تحديد اسم الموقع…
        </p>
      )}
    </div>
  );
}
