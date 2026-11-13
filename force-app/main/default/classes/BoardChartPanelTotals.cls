/**
 * Panel totals of Small multiples: each Panel's value per Measure over every row of that Panel, whatever max
 * categories cut. They feed the Panel headline (one hidden Measure shown in each Panel header,
 * `panelHeadlineMeasure`) and per-panel Reference lines (drawn at the Panel's value, not the Widget's).
 *
 * Totals are asked for only with a Panel field and a Panel headline or a Reference line (`isNeeded`). The SOQL tier
 * queries them grouped by the Panel field alone, one query per Measure condition group (exact for every aggregate,
 * each Measure under its own Measure condition); the cursor tier merges them from the running partials per Panel
 * (`fromRows`). A Formula measure is evaluated on its inputs' Panel totals; a Share of total has no Panel total
 * (null).
 */
public with sharing class BoardChartPanelTotals {
    /** Request key: index of the Measure shown as the Panel headline (a hidden Measure); absent without one. */
    public static final String HEADLINE_KEY = 'panelHeadlineMeasure';

    /** One Panel's total per Measure, in Measure order. */
    public class PanelTotal {
        @AuraEnabled
        public String panelKey;
        /** One per Measure, in the Display currency; null for a Share of total or a Panel without rows. */
        @AuraEnabled
        public List<Decimal> values = new List<Decimal>();
    }

    /** True when the request draws Small multiples with a Panel headline or a Reference line. */
    public static Boolean isNeeded(Map<String, Object> request) {
        if (!BoardChartQuery.hasPanelField(request)) {
            return false;
        }
        Object headline = request.get(HEADLINE_KEY);
        Boolean hasHeadline = headline != null && String.isNotBlank(String.valueOf(headline));
        return hasHeadline || BoardChartQuery.usesReferenceLines(request);
    }

    /**
     * Queried Measures' totals per Panel key, merged from grouped rows. Cursor partials merge exactly for every
     * aggregate; final SOQL values only for COUNT/SUM/MIN/MAX (else null). Without `includeBlank` the "(Blank)"
     * category and Panel stay out, as in the chart.
     */
    public static Map<String, List<Decimal>> fromRows(
        List<String> aggregateFunctions,
        List<BoardChartEngine.GroupedRow> rows,
        Boolean includeBlank
    ) {
        Map<String, List<BoardChartEngine.GroupedRow>> rowsByPanel = new Map<String, List<BoardChartEngine.GroupedRow>>();
        for (BoardChartEngine.GroupedRow row : rows) {
            if (row.panelValue == null && !includeBlank) {
                continue;
            }
            String key = keyOf(row.panelValue);
            if (!rowsByPanel.containsKey(key)) {
                rowsByPanel.put(key, new List<BoardChartEngine.GroupedRow>());
            }
            rowsByPanel.get(key).add(row);
        }
        Map<String, List<Decimal>> totals = new Map<String, List<Decimal>>();
        for (String key : rowsByPanel.keySet()) {
            totals.put(key, BoardChartEngine.overallValues(aggregateFunctions, rowsByPanel.get(key), includeBlank));
        }
        return totals;
    }

    /**
     * The Panel totals of the shaped `panels`, in Panel order: `queriedTotals` (queried Measures, corporate amounts)
     * widened to the Measures list with each Formula measure evaluated on them, then converted to each Measure's
     * Display currency (`currencyIsoCodes`). `isShare` per Measure: a Share of total gets null.
     */
    public static List<PanelTotal> forPanels(
        List<BoardChartEngine.ChartKey> panels,
        Map<String, List<Decimal>> queriedTotals,
        BoardFormulaMeasures.ChartPlan formulas,
        List<String> currencyIsoCodes,
        List<Boolean> isShare,
        BoardCurrencyConverter converter
    ) {
        List<PanelTotal> result = new List<PanelTotal>();
        for (BoardChartEngine.ChartKey panel : panels) {
            List<Decimal> queried = queriedTotals.get(panel.key);
            List<Decimal> values = formulas.widen(queried == null ? new List<Decimal>() : queried);
            PanelTotal total = new PanelTotal();
            total.panelKey = panel.key;
            for (Integer i = 0; i < values.size(); i++) {
                String isoCode = currencyIsoCodes != null && i < currencyIsoCodes.size() ? currencyIsoCodes[i] : null;
                Boolean share = isShare != null && i < isShare.size() && isShare[i];
                total.values.add(share ? null : (Decimal) converter.fromCorporate(values[i], isoCode));
            }
            result.add(total);
        }
        return result;
    }

    private static String keyOf(String value) {
        return value == null ? BoardChartEngine.BLANK_KEY : value;
    }
}