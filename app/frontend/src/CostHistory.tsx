import { useEffect, useMemo, useState } from 'react';

interface CostSnapshotRow {
  snapshot_time: string;
  namespace: string;
  pod_count: number;
  cpu_request_millicores: number;
  memory_request_ki: number;
  estimated_hourly_cost: number;
}

interface BucketPoint {
  offsetSeconds: number;
  cost: number;
}

interface Series {
  namespace: string;
  color: string;
  points: BucketPoint[];
  average: number;
}

type RangeMode = '1m' | '5m' | '10m';

const RANGE_CONFIG: Record<RangeMode, { rangeSeconds: number; bucketSeconds: number; label: string }> = {
  '1m': { rangeSeconds: 60, bucketSeconds: 15, label: '1m' },
  '5m': { rangeSeconds: 300, bucketSeconds: 60, label: '5m' },
  '10m': { rangeSeconds: 600, bucketSeconds: 120, label: '10m' }
};

const POLL_INTERVAL_SECONDS = 15;
const CHART_WIDTH = 600;
const CHART_HEIGHT = 236;
const CHART_PADDING = 32;

const SERIES_COLORS = ['#aa3bff', '#3b82f6', '#22c55e', '#f59e0b', '#14b8a6'];

function formatCost(cost: number): string {
  return `$${cost.toFixed(3)}/hr`;
}

function formatOffsetLabel(offsetSeconds: number, mode: RangeMode): string {
  if (offsetSeconds === 0) return 'NOW';
  return mode === '1m' ? `-${offsetSeconds}s` : `-${Math.round(offsetSeconds / 60)}m`;
}

function bucketSeries(rows: CostSnapshotRow[], nowMs: number, mode: RangeMode): BucketPoint[] {
  const { rangeSeconds, bucketSeconds } = RANGE_CONFIG[mode];
  // one point per tick, not per gap, so both edges get plotted
  const pointCount = Math.round(rangeSeconds / bucketSeconds) + 1;
  const sums = Array.from({ length: pointCount }, () => ({ total: 0, count: 0 }));

  for (const row of rows) {
    const ageSeconds = (nowMs - new Date(row.snapshot_time).getTime()) / 1000;
    if (ageSeconds < -bucketSeconds / 2 || ageSeconds > rangeSeconds + bucketSeconds / 2) continue;
    const ticksFromNow = Math.round(ageSeconds / bucketSeconds);
    const index = pointCount - 1 - ticksFromNow;
    if (index < 0 || index >= pointCount) continue;
    sums[index].total += row.estimated_hourly_cost;
    sums[index].count++;
  }

  const points: BucketPoint[] = [];
  sums.forEach((bucket, i) => {
    if (bucket.count === 0) return;
    points.push({ offsetSeconds: (pointCount - 1 - i) * bucketSeconds, cost: bucket.total / bucket.count });
  });

  // carry the last value forward if the freshest bucket hasn't landed yet
  if (points.length > 0 && points[points.length - 1].offsetSeconds !== 0) {
    points.push({ offsetSeconds: 0, cost: points[points.length - 1].cost });
  }

  return points;
}

function CostHistory() {
  const [rows, setRows] = useState<CostSnapshotRow[] | null>(null);
  // "now" for bucketing, captured when rows arrive (Date.now() can't be called during render)
  const [fetchedAtMs, setFetchedAtMs] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [rangeMode, setRangeMode] = useState<RangeMode>('1m');
  const [namespaceFilter, setNamespaceFilter] = useState<string>('all');
  const [secondsUntilRefresh, setSecondsUntilRefresh] = useState(POLL_INTERVAL_SECONDS);

  useEffect(() => {
    const fetchHistory = () => {
      fetch('/api/cost-history')
        .then((res) => res.json())
        .then((json) => {
          if ('error' in json) {
            setError(json.error);
          } else {
            setError(null);
            setRows(json);
            setFetchedAtMs(Date.now());
          }
        })
        .catch((err) => setError(err.message));
    };

    // aligned to the same wall-clock grid as App.tsx's /api/cluster poll
    let lastFetchedBoundary = -1;

    const tick = () => {
      const nowSeconds = Date.now() / 1000;
      const secondsIntoWindow = nowSeconds % POLL_INTERVAL_SECONDS;
      setSecondsUntilRefresh(Math.ceil(POLL_INTERVAL_SECONDS - secondsIntoWindow));

      const currentBoundary = Math.floor(nowSeconds / POLL_INTERVAL_SECONDS);
      if (currentBoundary !== lastFetchedBoundary) {
        lastFetchedBoundary = currentBoundary;
        fetchHistory();
      }
    };

    tick();
    const clockInterval = setInterval(tick, 1000);
    return () => clearInterval(clockInterval);
  }, []);

  const namespaces = useMemo(() => {
    if (!rows) return [];
    return Array.from(new Set(rows.map((r) => r.namespace))).sort();
  }, [rows]);

  const namespaceColors = useMemo(() => {
    const colors: Record<string, string> = {};
    namespaces.forEach((ns, i) => {
      colors[ns] = SERIES_COLORS[i % SERIES_COLORS.length];
    });
    return colors;
  }, [namespaces]);

  const series: Series[] = useMemo(() => {
    if (!rows) return [];
    const visibleNamespaces = namespaceFilter === 'all' ? namespaces : [namespaceFilter];

    return visibleNamespaces.map((namespace) => {
      const namespaceRows = rows.filter((r) => r.namespace === namespace);
      const points = bucketSeries(namespaceRows, fetchedAtMs, rangeMode);
      const average = points.length === 0 ? 0 : points.reduce((sum, p) => sum + p.cost, 0) / points.length;
      return { namespace, color: namespaceColors[namespace], points, average };
    });
  }, [rows, fetchedAtMs, rangeMode, namespaceFilter, namespaces, namespaceColors]);

  if (error) {
    return <div className="cost-history error">{error}</div>;
  }

  if (!rows) {
    return <div className="cost-history">Loading cost history...</div>;
  }

  if (rows.length === 0) {
    return <div className="cost-history">Collecting cost history - check back in a minute.</div>;
  }

  const { rangeSeconds, bucketSeconds } = RANGE_CONFIG[rangeMode];
  const tickCount = Math.round(rangeSeconds / bucketSeconds);
  const plotWidth = CHART_WIDTH - 2 * CHART_PADDING;
  const plotHeight = CHART_HEIGHT - 2 * CHART_PADDING;
  const maxCost = Math.max(...series.flatMap((s) => s.points.map((p) => p.cost)), 0.001);

  const toX = (offsetSeconds: number) => CHART_PADDING + (1 - offsetSeconds / rangeSeconds) * plotWidth;
  const toY = (cost: number) => CHART_HEIGHT - CHART_PADDING - (cost / maxCost) * plotHeight;

  const ticks = Array.from({ length: tickCount + 1 }, (_, i) => i * bucketSeconds);

  return (
    <div className="cost-history">
      <div className="cost-history-header">
        <div className="cost-history-title">Estimated cost by namespace</div>

        <div className="cost-history-controls">
          <div className="cost-history-toggle-group">
            {(Object.keys(RANGE_CONFIG) as RangeMode[]).map((mode) => (
              <button
                key={mode}
                className={mode === rangeMode ? 'active' : ''}
                onClick={() => setRangeMode(mode)}
              >
                {RANGE_CONFIG[mode].label}
              </button>
            ))}
          </div>

          <div className="cost-history-toggle-group">
            <button className={namespaceFilter === 'all' ? 'active' : ''} onClick={() => setNamespaceFilter('all')}>
              All
            </button>
            {namespaces.map((ns) => (
              <button
                key={ns}
                className={namespaceFilter === ns ? 'active' : ''}
                onClick={() => setNamespaceFilter(ns)}
              >
                {ns}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="cost-history-chart-wrap">
        <svg viewBox={`0 0 ${CHART_WIDTH} ${CHART_HEIGHT}`} className="cost-history-chart">
          {ticks.map((offsetSeconds) => (
            <line
              key={offsetSeconds}
              x1={toX(offsetSeconds)}
              y1={CHART_PADDING}
              x2={toX(offsetSeconds)}
              y2={CHART_HEIGHT - CHART_PADDING}
              className="cost-history-gridline"
            />
          ))}

          <line
            x1={CHART_PADDING}
            y1={CHART_HEIGHT - CHART_PADDING}
            x2={CHART_WIDTH - CHART_PADDING}
            y2={CHART_HEIGHT - CHART_PADDING}
            className="cost-history-axis"
          />

          {series.map((s) => (
            <path
              key={s.namespace}
              d={s.points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${toX(p.offsetSeconds)} ${toY(p.cost)}`).join(' ')}
              fill="none"
              stroke={s.color}
              strokeWidth={2}
            />
          ))}

          {ticks.map((offsetSeconds) => (
            <text
              key={offsetSeconds}
              x={toX(offsetSeconds)}
              y={CHART_HEIGHT - CHART_PADDING + 16}
              className="cost-history-tick-label"
              textAnchor="middle"
            >
              {formatOffsetLabel(offsetSeconds, rangeMode)}
            </text>
          ))}

          <text
            x={toX(0)}
            y={CHART_HEIGHT - CHART_PADDING + 28}
            className="cost-history-countdown-label"
            textAnchor="middle"
          >
            next in {secondsUntilRefresh}s
          </text>
        </svg>

        <div className="cost-history-averages">
          {series.map((s) => (
            <div key={s.namespace} className="cost-history-average-item" style={{ color: s.color }}>
              {s.namespace} avg: {formatCost(s.average)}
            </div>
          ))}
        </div>
      </div>

      <div className="cost-history-legend">
        {series.map((s) => (
          <div key={s.namespace} className="cost-history-legend-item">
            <span className="cost-history-swatch" style={{ background: s.color }} />
            <span>{s.namespace}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

export default CostHistory;
