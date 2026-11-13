import { runCursorLoad } from 'c/boardCursorProgress';

/**
 * Detail rows off, cursor tier (above 2,000 groups or the single-aggregate row band): a `queryTable` response whose
 * `aggregateCursor` is incomplete is followed through `fetchTableAggregateChunk` until the final chunk, which alone
 * carries the Group rows (final result only; the server keeps the running groups in `partialState`).
 */

/** True when a `queryTable` response starts a cursor-tier load that still has chunks to read. */
export function isIncompleteAggregateCursor(result) {
    return result?.aggregateCursor?.isComplete === false;
}

/** `runCursorLoad` chunk view of a Table response: its cursor progress plus the response itself. */
function toCursorChunk(result) {
    return {
        ...(result?.aggregateCursor || {}),
        isComplete: !isIncompleteAggregateCursor(result),
        result
    };
}

/**
 * Follows the chunks of a cursor-tier load. `fetchChunk(requestJson)` is the Apex call; `onProgress` receives the
 * `buildCursorProgress` state after every incomplete chunk; `isCurrent` stops a superseded run. Resolves the final
 * response, or null when the run was superseded.
 */
export async function followAggregateCursor({ first, request, fetchChunk, isCurrent, onProgress }) {
    let latest = first;
    const completed = await runCursorLoad({
        first: toCursorChunk(first),
        isCurrent,
        merge: (chunk) => {
            latest = chunk.result;
        },
        onProgress,
        fetchNext: async (chunk) =>
            toCursorChunk(
                await fetchChunk({
                    requestJson: JSON.stringify({
                        ...request,
                        cursor: chunk.cursor,
                        offset: chunk.nextOffset,
                        partialState: chunk.partialState
                    })
                })
            )
    });
    return completed ? latest : null;
}