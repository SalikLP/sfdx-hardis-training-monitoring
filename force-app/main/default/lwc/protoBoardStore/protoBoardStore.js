// Throwaway prototype in-memory state + pub/sub registry for Board filter context.
// Solves late-joiner state initialization and guarantees same-DOM reactivity
// even in hosts/contexts where LMS MessageContext might not be active.

const boards = new Map(); // boardId -> { state, listeners: Set<fn> }

function ensureBoard(boardId) {
    const key = boardId || 'default';
    if (!boards.has(key)) {
        boards.set(key, {
            state: null,
            listeners: new Set()
        });
    }
    return boards.get(key);
}

export function publishBoardFilter(boardId, filterState) {
    const entry = ensureBoard(boardId);
    entry.state = filterState;
    entry.listeners.forEach((listener) => {
        try {
            listener(filterState);
        } catch (e) {
            // ignore listener error in prototype
        }
    });
}

export function subscribeBoardFilter(boardId, callback) {
    const entry = ensureBoard(boardId);
    entry.listeners.add(callback);
    // Late-joiner immediately receives current state if already published
    if (entry.state) {
        callback(entry.state);
    }
    return () => {
        entry.listeners.delete(callback);
    };
}

export function getBoardFilterState(boardId) {
    return ensureBoard(boardId).state;
}