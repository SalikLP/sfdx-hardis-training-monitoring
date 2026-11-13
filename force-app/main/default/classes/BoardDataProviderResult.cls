/**
 * What a Data provider returns (see `BoardDataProvider`): partial buckets, which filters it applied or ignored, and
 * the Measures it can't supply. Never rows.
 */
global inherited sharing class BoardDataProviderResult {
    /** Partial buckets; buckets with the same Panel, category and series value merge. */
    global List<Bucket> buckets = new List<Bucket>();
    /** True to merge `buckets` into the standard query's buckets; false (default) replaces the standard query. */
    global Boolean includeStandardResult = false;
    /** Filter ids the provider applied (shown as applied on the Widget). */
    global List<String> appliedFilterIds = new List<String>();
    /** Filter ids the provider ignored (shown as ignored on the Widget). */
    global List<String> ignoredFilterIds = new List<String>();
    /** Rejected Measures: index to reason. */
    public Map<Integer, String> rejectedMeasures = new Map<Integer, String>();

    global BoardDataProviderResult() {
    }

    /** Rejects Measure `measureIndex` (e.g. a `COUNT_DISTINCT` it can't merge): the Widget shows a config error. */
    global void rejectMeasure(Integer measureIndex, String reason) {
        rejectedMeasures.put(measureIndex, reason);
    }

    /**
     * One group: its category and series keys (the engine's keys: record Id, picklist API value, date bucket key such
     * as `2026-03`; null for "(Blank)" and on a Metric widget) and labels, its Panel key and label with Small
     * multiples (`request.panelField`; null without), and one partial per Measure.
     */
    global class Bucket {
        global String panelValue;
        global String panelLabel;
        global String categoryValue;
        global String categoryLabel;
        global String seriesValue;
        global String seriesLabel;
        /** One partial per request Measure, in Measure order. */
        global List<Partial> measures = new List<Partial>();

        global Bucket() {
        }

        global Bucket(String categoryValue, String categoryLabel, String seriesValue, String seriesLabel) {
            this.categoryValue = categoryValue;
            this.categoryLabel = categoryLabel;
            this.seriesValue = seriesValue;
            this.seriesLabel = seriesLabel;
        }
    }

    /**
     * One Measure in one bucket: sum, count, min and max of its values (corporate currency for amounts). `count` is
     * the number of rows for `COUNT`, else of non-null values; `AVG` is the merged `sum / count`. For Average per
     * record (`AVG_PER`) each value is one record's value: `count` counts records, `sum` adds their values.
     */
    global class Partial {
        global Decimal sum = 0;
        global Integer count = 0;
        global Decimal min;
        global Decimal max;

        global Partial() {
        }

        global Partial(Decimal sum, Integer count, Decimal min, Decimal max) {
            this.sum = sum;
            this.count = count;
            this.min = min;
            this.max = max;
        }
    }
}