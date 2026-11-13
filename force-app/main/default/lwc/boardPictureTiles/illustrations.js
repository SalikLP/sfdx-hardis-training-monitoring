/**
 * Picture tile illustrations, as data: each is a list of SVG paths `{ d, tone }` on a 48 × 32 canvas. `tone` picks
 * the SLDS-hooked colour (`boardPictureTiles.css`, class `c-tone-<tone>`):
 *
 * - `axis`: the chart axes and guides (stroke)
 * - `series1` / `series2` / `series3`: filled shapes in the first three series colours
 * - `line1`: a series drawn as a line (stroke)
 * - `area1`: a translucent fill under a line
 * - `reference`: a dashed Reference line (stroke)
 * - `increase` / `decrease`: waterfall steps up and down
 * - `muted`: a grey shape, e.g. an "Other" category
 *
 * Shipped with the component, so tiles need no static resource or external asset. Add a Widget's illustrations here
 * and refer to them by name (`illustration: 'bar'`) from the picker's options.
 */

const round = (value) => Math.round(value * 100) / 100;

function rect(x, y, width, height) {
    return `M${x} ${y}h${width}v${height}h${-width}z`;
}

function polyline(points) {
    return points.map(([x, y], index) => `${index ? 'L' : 'M'}${x} ${y}`).join(' ');
}

function polygon(points) {
    return `${polyline(points)} Z`;
}

/** Point at `radius` and `degrees` clockwise from 12 o'clock around (cx, cy). */
function polar(cx, cy, radius, degrees) {
    const radians = ((degrees - 90) * Math.PI) / 180;
    return [round(cx + radius * Math.cos(radians)), round(cy + radius * Math.sin(radians))];
}

/** A pie slice from `from` to `to` degrees. */
function wedge(cx, cy, radius, from, to) {
    const [x0, y0] = polar(cx, cy, radius, from);
    const [x1, y1] = polar(cx, cy, radius, to);
    const large = to - from > 180 ? 1 : 0;
    return `M${cx} ${cy} L${x0} ${y0} A${radius} ${radius} 0 ${large} 1 ${x1} ${y1} Z`;
}

/** A donut slice: the ring between `inner` and `outer` from `from` to `to` degrees. */
function ringSlice(cx, cy, inner, outer, from, to) {
    const large = to - from > 180 ? 1 : 0;
    const [ox0, oy0] = polar(cx, cy, outer, from);
    const [ox1, oy1] = polar(cx, cy, outer, to);
    const [ix1, iy1] = polar(cx, cy, inner, to);
    const [ix0, iy0] = polar(cx, cy, inner, from);
    return (
        `M${ox0} ${oy0} A${outer} ${outer} 0 ${large} 1 ${ox1} ${oy1} ` +
        `L${ix1} ${iy1} A${inner} ${inner} 0 ${large} 0 ${ix0} ${iy0} Z`
    );
}

const AXES = { d: 'M6 3V28H45', tone: 'axis' };

/** Bars standing on the x axis (y = 28), `heights` left to right. */
function bars(heights, { x = 10, width = 6, gap = 3, tone = 'series1' } = {}) {
    return heights.map((height, index) => ({ d: rect(x + index * (width + gap), 28 - height, width, height), tone }));
}

/** Stacked bars: each entry lists its segment heights, bottom up, in series tones. */
function stackedBars(stacks, { x = 10, width = 6, gap = 3 } = {}) {
    return stacks.flatMap((segments, index) => {
        let top = 28;
        return segments.map((height, series) => {
            top -= height;
            return { d: rect(x + index * (width + gap), top, width, height), tone: `series${series + 1}` };
        });
    });
}

const LINE = [
    [8, 22],
    [17, 16],
    [26, 19],
    [35, 9],
    [43, 6]
];

const RADAR = [0, 60, 120, 180, 240, 300];

export const ILLUSTRATIONS = {
    // ---- Chart types (`chartType`) --------------------------------------------------------------------------------
    bar: [AXES, ...bars([10, 18, 13, 22])],
    line: [AXES, { d: polyline(LINE), tone: 'line1' }],
    area: [AXES, { d: polygon([[8, 28], ...LINE, [43, 28]]), tone: 'area1' }, { d: polyline(LINE), tone: 'line1' }],
    combo: [
        AXES,
        ...bars([10, 16, 12, 20], { tone: 'series2' }),
        {
            d: polyline([
                [13, 14],
                [22, 9],
                [31, 12],
                [40, 5]
            ]),
            tone: 'line1'
        }
    ],
    pie: [
        { d: wedge(24, 16, 13, 0, 150), tone: 'series1' },
        { d: wedge(24, 16, 13, 150, 260), tone: 'series2' },
        { d: wedge(24, 16, 13, 260, 360), tone: 'series3' }
    ],
    donut: [
        { d: ringSlice(24, 16, 7, 13, 0, 150), tone: 'series1' },
        { d: ringSlice(24, 16, 7, 13, 150, 260), tone: 'series2' },
        { d: ringSlice(24, 16, 7, 13, 260, 360), tone: 'series3' }
    ],
    polarArea: [
        { d: wedge(24, 16, 14, 0, 90), tone: 'series1' },
        { d: wedge(24, 16, 9, 90, 180), tone: 'series2' },
        { d: wedge(24, 16, 12, 180, 270), tone: 'series3' },
        { d: wedge(24, 16, 7, 270, 360), tone: 'series1' }
    ],
    radar: [
        { d: polygon(RADAR.map((degrees) => polar(24, 16, 13, degrees))), tone: 'axis' },
        { d: polygon(RADAR.map((degrees) => polar(24, 16, 7, degrees))), tone: 'axis' },
        {
            d: polygon(RADAR.map((degrees, index) => polar(24, 16, [11, 7, 12, 5, 9, 10][index], degrees))),
            tone: 'area1'
        },
        {
            d: polygon(RADAR.map((degrees, index) => polar(24, 16, [11, 7, 12, 5, 9, 10][index], degrees))),
            tone: 'line1'
        }
    ],
    waterfall: [
        AXES,
        { d: rect(9, 18, 6, 10), tone: 'increase' },
        { d: rect(17, 10, 6, 8), tone: 'increase' },
        { d: rect(25, 10, 6, 5), tone: 'decrease' },
        { d: rect(33, 15, 6, 13), tone: 'series1' }
    ],

    // ---- Series layout (`stackMode`) ------------------------------------------------------------------------------
    stacked: [
        AXES,
        ...stackedBars([
            [8, 6],
            [12, 8],
            [6, 9],
            [14, 7]
        ])
    ],
    grouped: [
        AXES,
        ...[
            [8, 13],
            [17, 11],
            [12, 20]
        ].flatMap(([first, second], index) => [
            { d: rect(9 + index * 12, 28 - first, 5, first), tone: 'series1' },
            { d: rect(14 + index * 12, 28 - second, 5, second), tone: 'series2' }
        ])
    ],

    // ---- Share of total (`showAs`) --------------------------------------------------------------------------------
    // The values as they are.
    showAsValue: [AXES, ...bars([8, 20, 13, 16])],
    // Each category's share of the grand total: the categories together make up one whole.
    showAsPercentOfTotal: [
        { d: rect(4, 12, 10, 8), tone: 'series1' },
        { d: rect(14, 12, 16, 8), tone: 'series2' },
        { d: rect(30, 12, 8, 8), tone: 'series3' },
        { d: rect(38, 12, 6, 8), tone: 'series1' },
        { d: 'M4 25H44 M4 23v4 M44 23v4', tone: 'axis' }
    ],
    // Each series' share within its category: every category adds up to 100%.
    showAsPercentOfCategory: [
        AXES,
        ...stackedBars([
            [14, 10],
            [8, 16],
            [17, 7],
            [11, 13]
        ])
    ],

    // ---- Draw as (`render`, bar and line charts) ------------------------------------------------------------------
    renderBar: [AXES, ...bars([12, 18, 9, 15])],
    renderLine: [AXES, { d: polyline(LINE), tone: 'line1' }],
    // A Reference line: one value drawn across the whole chart, e.g. a target.
    renderReferenceLine: [AXES, ...bars([12, 18, 9, 15], { tone: 'series2' }), { d: 'M6 13H45', tone: 'reference' }],

    // ---- Orientation (`orientation`, bar charts) ------------------------------------------------------------------
    orientationVertical: [AXES, ...bars([10, 18, 13, 22])],
    orientationHorizontal: [
        AXES,
        ...[30, 18, 24, 12].map((width, index) => ({ d: rect(6, 5 + index * 6, width, 4), tone: 'series1' }))
    ],

    // ---- Categories beyond the maximum (`overflowMode`) -----------------------------------------------------------
    // The largest categories only; the rest are left out.
    overflowTruncate: [AXES, ...bars([22, 17, 13, 9])],
    // The largest categories, then one "Other" category summing the rest.
    overflowOther: [AXES, ...bars([22, 17, 13]), { d: rect(37, 14, 6, 14), tone: 'muted' }],

    // ---- Metric display (`display`, Metric widget) -----------------------------------------------------------------
    // One big number ("42") over a muted subtitle line.
    displayNumber: [
        { d: `${rect(12, 5, 3, 10)} ${rect(12, 13, 11, 3)} ${rect(19, 5, 3, 19)}`, tone: 'series1' },
        {
            d: `${rect(26, 5, 10, 3)} ${rect(33, 5, 3, 10)} ${rect(26, 13, 10, 3)} ${rect(26, 13, 3, 11)} ${rect(26, 21, 10, 3)}`,
            tone: 'series1'
        },
        { d: rect(13, 27, 22, 2), tone: 'muted' }
    ],
    // A half-ring scale filled up to the value, with a target marker.
    displayGauge: [
        { d: ringSlice(24, 26, 12, 20, -90, 30), tone: 'series1' },
        { d: ringSlice(24, 26, 12, 20, 30, 90), tone: 'muted' },
        { d: `M${polar(24, 26, 10, 60).join(' ')} L${polar(24, 26, 22, 60).join(' ')}`, tone: 'reference' }
    ],

    // ---- Table widget: Row limit (`rowLimit`), Detail rows (`detailRows`), Subtotals (`showSubtotals`) ------------
    // A header row (series1) above record rows (muted); Group rows in series2, Subtotal rows in series3.
    // Every row of the table.
    rowLimitAll: [
        { d: rect(4, 3, 40, 4), tone: 'series1' },
        ...[9, 13, 17, 21, 25].map((y) => ({ d: rect(4, y, 40, 2.5), tone: 'muted' }))
    ],
    // The first N rows, cut off below.
    rowLimitTop: [
        { d: rect(4, 3, 40, 4), tone: 'series1' },
        ...[9, 13, 17].map((y) => ({ d: rect(4, y, 40, 2.5), tone: 'muted' })),
        { d: 'M4 22H44', tone: 'reference' }
    ],
    // Records indented under their Group rows.
    detailRowsOn: [
        ...[3, 17].map((y) => ({ d: rect(4, y, 40, 3), tone: 'series2' })),
        ...[8, 12, 22, 26].map((y) => ({ d: rect(9, y, 35, 2.5), tone: 'muted' }))
    ],
    // Only the Group rows: an aggregated table.
    detailRowsOff: [4, 10, 16, 22].map((y) => ({ d: rect(4, y, 40, 4), tone: 'series2' })),
    // Groups of records, nothing closing them.
    subtotalsOff: [
        ...[2, 18].map((y) => ({ d: rect(4, y, 40, 3), tone: 'series2' })),
        ...[7, 10.5, 14, 23, 26.5].map((y) => ({ d: rect(9, y, 35, 2.5), tone: 'muted' }))
    ],
    // A Subtotal row closing each group.
    subtotalsOn: [
        ...[2, 18].map((y) => ({ d: rect(4, y, 40, 3), tone: 'series2' })),
        ...[7, 10.5, 23].map((y) => ({ d: rect(9, y, 35, 2.5), tone: 'muted' })),
        ...[14, 26.5].map((y) => ({ d: rect(9, y, 35, 3), tone: 'series3' }))
    ]
};

/** The paths of an illustration: one of `ILLUSTRATIONS` by name, or paths given as data; `[]` when unknown. */
export function illustrationPaths(illustration) {
    if (Array.isArray(illustration)) {
        return illustration;
    }
    return (typeof illustration === 'string' && ILLUSTRATIONS[illustration]) || [];
}