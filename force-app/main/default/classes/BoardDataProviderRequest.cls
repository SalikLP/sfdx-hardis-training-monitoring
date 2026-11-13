/**
 * What a Data provider receives (see `BoardDataProvider`): the Widget's data scope as condition trees and its
 * grouping and Measures.
 *
 * Every `Condition` came from one Filter binding or Base filter: `filterId` names it, `path` is the field it compiled
 * onto on `objectApiName` (a child-relationship binding's path is relative to its child object), and `values` hold
 * typed values (Id, Date, Datetime, Decimal, Boolean, String). Text searches (`SOSL`) are not part of the trees.
 */
global inherited sharing class BoardDataProviderRequest {
    /** `chart` or `metric`. */
    global String widgetType;
    global String objectApiName;
    /** Applied Board filters after Filter bindings, one condition (or AND / OR group) per filter. */
    global List<Condition> filters = new List<Condition>();
    /** The Widget's Base filters, one condition (or AND / OR group) per entry. */
    global List<Condition> baseFilters = new List<Condition>();
    /** Record context conditions (empty off a record page or when the Widget opts out). */
    global List<Condition> recordContext = new List<Condition>();
    /** Category field path (null on a Metric widget). */
    global String groupByField;
    global String dateGranularity;
    /** Series field path (null without a series field). */
    global String seriesField;
    /** Panel field path of Small multiples (null without): one more grouping, keyed by `Bucket.panelValue`. */
    global String panelField;
    /** Date granularity of a date Panel field (null otherwise). */
    global String panelDateGranularity;
    /** The Widget's Measures in order; each bucket returns one partial per Measure, in this order. */
    global List<Measure> measures = new List<Measure>();
    /**
     * The Widget's query request as sent by the Widget (`objectApiName`, `filters`, `baseFilters`, `groupByField`,
     * `measures`...). `runStandardQuery` runs it, so a provider can change it first (e.g. another object).
     */
    global Map<String, Object> query = new Map<String, Object>();
    /**
     * ISO code of the Board's Display currency, the currency the engine shows this Widget's amounts in (the org
     * currency in single-currency orgs). For information only: return amounts in the corporate currency.
     */
    global String displayCurrency;

    global BoardDataProviderRequest() {
    }

    /**
     * Engine helper: a corporate-currency amount in `displayCurrency` (e.g. for a label). Never use it on returned
     * partials: the engine converts those. Null stays null; single-currency orgs: unchanged.
     */
    global Decimal toDisplayCurrency(Decimal corporateAmount) {
        return (Decimal) BoardCurrencyConverter.forRequest().fromCorporate(corporateAmount, displayCurrency);
    }

    /**
     * Runs the standard query for `query` and returns its buckets in the provider result shape, ready to add to a
     * result (buckets with the same keys merge). Fails with the Widget's own errors (e.g. `LIMIT_EXCEEDED`).
     */
    global List<BoardDataProviderResult.Bucket> runStandardQuery() {
        return BoardDataProviders.standardBuckets(query);
    }

    /** A condition on one field path, or (with `logic`) an AND / OR group of `children`. */
    global class Condition {
        /** `AND` / `OR` for a group; null for a condition. */
        global String logic;
        global List<Condition> children = new List<Condition>();
        global String filterId;
        global String path;
        /** `EQ`, `NEQ`, `GT`, `GTE`, `LT`, `LTE`, `IN`, `NOT_IN`, `INCLUDES`, `EXCLUDES`, `LIKE`, `RELATIVE_DATE`. */
        global String operator;
        global List<Object> values = new List<Object>();

        global Condition() {
        }

        global Boolean isGroup() {
            return logic != null;
        }
    }

    /** One Measure of the Widget. */
    global class Measure {
        global Integer index;
        /** `COUNT`, `SUM`, `AVG`, `MIN` or `MAX`. */
        global String aggregateFunction;
        /** Value field path (null for `COUNT`). */
        global String valueFieldApiName;
        global String label;
        /** The Measure condition limiting the rows this Measure aggregates (null when none). */
        global Condition condition;

        global Measure() {
        }
    }
}