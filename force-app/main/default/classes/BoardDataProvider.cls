/**
 * Data provider: an Apex class an Admin names in a Metric or Chart Widget config (`dataProvider`) to supply that
 * Widget's aggregate results in place of the standard query.
 *
 * The engine calls `provide` once per run with the structured request (object, Filter context after Filter bindings,
 * Base filters, Record context, Measure conditions, group / series / panel fields, Measures). The provider returns
 * partial buckets (keys, labels, and `{ sum, count, min, max }` per Measure), never rows; the engine merges them by key,
 * with the standard query's own buckets when `includeStandardResult` is set, then sorts and caps them like any Widget.
 * `request.runStandardQuery()` runs the standard query for a request so a provider can add to it;
 * `BoardDataProviderRows` gives virtual rows the engine's keys and labels (Bucket fields, date buckets, reference
 * labels) and evaluates conditions against them.
 *
 * Currency: return amounts (`sum`, `min`, `max` of SUM / AVG / MIN / MAX Measures on currency fields) in the org's
 * corporate currency, like `runStandardQuery` does. The engine converts them to the Board's Display currency
 * (`request.displayCurrency`) and returns its ISO code, as for any aggregate; counts are never converted.
 *
 * Implementing classes need a public no-argument constructor.
 */
global interface BoardDataProvider {
    BoardDataProviderResult provide(BoardDataProviderRequest request);
}