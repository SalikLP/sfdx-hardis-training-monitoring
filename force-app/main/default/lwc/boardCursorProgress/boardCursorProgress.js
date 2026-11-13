import LOCALE from '@salesforce/i18n/locale';

/**
 * Shared cursor-tier loading pattern for aggregate Widgets (Chart, Metric, and the Table with Detail rows off).
 * A cursor load shows a progress bar with a row counter and renders only the final merged result.
 */

let countFormat;

/** A row or group count in the user's locale (e.g. `1,234`); one shared `Intl.NumberFormat`. */
export function formatCount(count) {
    countFormat = countFormat || new Intl.NumberFormat(LOCALE);
    return countFormat.format(count);
}

/** `{ processedRows, totalRows, percent, label }` for the SLDS progress bar and its row counter. */
export function buildCursorProgress(processedRows, totalRows) {
    const processed = Number(processedRows) || 0;
    const total = Number(totalRows) || 0;
    const percent = total > 0 ? Math.min(100, Math.max(0, Math.floor((processed / total) * 100))) : 0;
    return {
        processedRows: processed,
        totalRows: total,
        percent,
        label: `Loading ${formatCount(processed)} of ${formatCount(total)} rows`
    };
}

/**
 * Drives a chunked cursor load. Each chunk is merged into the caller's accumulator via `merge`; `onProgress` fires
 * after every incomplete chunk. `isCurrent` gates every step so a superseded run stops fetching and never reports.
 * Resolves true only when the last chunk merged while still current (caller may then render the final result).
 */
export async function runCursorLoad({ first, fetchNext, isCurrent, merge, onProgress }) {
    let chunk = first;
    for (;;) {
        if (!isCurrent()) {
            return false;
        }
        merge(chunk);
        if (!chunk || chunk.isComplete) {
            return true;
        }
        onProgress(buildCursorProgress(chunk.nextOffset, chunk.totalRows));
        // eslint-disable-next-line no-await-in-loop -- each chunk needs the previous chunk's cursor offset
        chunk = await fetchNext(chunk);
    }
}