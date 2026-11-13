/**
 * Pure helpers behind the Filter bindings of the Config editor and the Setup dialog: `builderContext` Filter widget
 * discovery, convention-binding preview via `resolveFilterBindings`, and the binding rows shown to the Admin.
 * Config envelope and validation helpers live in `c/boardCpeUtils`.
 */
import { RECORD_CONTEXT_FILTER_ID, RECORD_CONTEXT_OVERRIDE_TYPES, resolveFilterBindings } from 'c/boardConfigUtils';
import { normalizeFilterDefinitions } from 'c/boardContextStore';
import {
    BINDING_PATH_HELP,
    FILTER_TYPE_LABELS,
    RECORD_CONTEXT_MODES,
    cleanString,
    isIgnoreBinding,
    isPlainObject,
    isValidBindingPath,
    teamBindingHopError
} from 'c/boardCpeUtils';

const FILTER_WIDGET_EXTENSION = /(^|[:_])boardFilterWidget$/;

function flattenFields(fields, out = []) {
    (Array.isArray(fields) ? fields : []).forEach((field) => {
        if (field) {
            out.push(field);
            flattenFields(field.fields, out);
        }
    });
    return out;
}

/** Literal string value of a screen field input parameter (`{ value }` or metadata `{ value: { stringValue } }`). */
function parameterValue(field, name) {
    const parameter = (Array.isArray(field.inputParameters) ? field.inputParameters : []).find(
        (item) => item && item.name === name
    );
    if (!parameter || parameter.valueDataType === 'reference') {
        return null;
    }
    const value = isPlainObject(parameter.value) ? parameter.value.stringValue : parameter.value;
    return cleanString(value);
}

/**
 * Finds `boardFilterWidget` screen fields with a matching Board id in Flow Builder's `builderContext`
 * (`screens -> fields`, recursing into Section regions). Scans the screen holding `elementInfo.apiName`; when that
 * screen cannot be located (e.g. an unsaved screen), scans every screen.
 */
export function discoverFilterWidgets(builderContext, elementInfo, boardId) {
    const screens = Array.isArray(builderContext?.screens) ? builderContext.screens.filter(Boolean) : [];
    const apiName = cleanString(elementInfo?.apiName);
    let scoped = apiName
        ? screens.filter(
              (screen) =>
                  screen.name === apiName || flattenFields(screen.fields).some((field) => field.name === apiName)
          )
        : [];
    const sameScreen = scoped.length > 0;
    if (!sameScreen) {
        scoped = screens;
    }
    const targetBoardId = cleanString(boardId) || 'default';
    const widgets = [];
    scoped.forEach((screen) => {
        flattenFields(screen.fields).forEach((field) => {
            if (!FILTER_WIDGET_EXTENSION.test(field.extensionName || '')) {
                return;
            }
            let parsed = {};
            try {
                const value = JSON.parse(parameterValue(field, 'configJson') || '{}');
                parsed = isPlainObject(value) ? value : {};
            } catch (err) {
                parsed = {};
            }
            const widgetBoardId = parameterValue(field, 'boardId') || cleanString(parsed.boardId) || 'default';
            if (widgetBoardId !== targetBoardId) {
                return;
            }
            const recordContext = isPlainObject(parsed.recordContext) ? parsed.recordContext : {};
            const recordContextMode = RECORD_CONTEXT_MODES.includes(recordContext.mode)
                ? recordContext.mode
                : 'IMPLICIT';
            const filters = normalizeFilterDefinitions(parsed.filters);
            const overrideFilterId = cleanString(recordContext.overrideFilterId);
            const overrideTarget = filters.find((def) => def.filterId === overrideFilterId);
            widgets.push({
                name: field.name,
                screenName: screen.name || null,
                boardId: widgetBoardId,
                filters,
                // Board-level Bucket fields every Widget on the Board can use by id.
                bucketFields: Array.isArray(parsed.bucketFields) ? parsed.bucketFields.filter(isPlainObject) : [],
                // The Record context scopes Widgets unless LOCKED/DEFAULT feeds it into a Picklist/Lookup/User filter.
                scopesRecordContext:
                    recordContextMode === 'IMPLICIT' ||
                    !overrideTarget ||
                    !RECORD_CONTEXT_OVERRIDE_TYPES.includes(overrideTarget.type)
            });
        });
    });
    return { widgets, sameScreen };
}

function previewEntry(def) {
    const entry = {
        filterId: def.filterId,
        label: def.label,
        type: def.type,
        active: true,
        fieldApiName: def.fieldApiName,
        targetObjectApiName: def.targetObjectApiName,
        operator: 'IN',
        values: ['preview']
    };
    if (def.type === 'DATE_RANGE') {
        return { ...entry, operator: 'LITERAL', values: [], literal: 'TODAY' };
    }
    if (def.type === 'TEXT') {
        return { ...entry, operator: def.matchMode, values: [], text: 'preview' };
    }
    if (def.type === 'BUCKET') {
        return { ...entry, bucketFieldId: def.bucketFieldId };
    }
    return entry;
}

/**
 * Convention binding (no `filterBindings` overrides) of each discovered filter on `objectApiName`. A Bucket filter
 * binds to its Bucket field (the Widget's own `bucketFields` first, else the Board's `boardBucketFields`).
 * @returns {Map<string, {status: 'BOUND'|'RUNTIME'|'SOSL'|'BUCKET'|'UNBOUND', fieldPath: string|null,
 *   bucketLabel?: string}>}
 */
export function previewConventionBindings({
    objectApiName,
    fields,
    filters,
    includeRecordContext,
    bucketFields,
    boardBucketFields
}) {
    const preview = new Map();
    const filterEntries = {};
    filters.forEach((def) => {
        filterEntries[def.filterId] = previewEntry(def);
    });
    const filterContext = {
        recordContext: includeRecordContext
            ? { mode: 'IMPLICIT', recordId: 'preview', resolvedValue: 'preview', objectApiName: null }
            : {},
        filters: filterEntries
    };
    const { filters: resolved, applied } = resolveFilterBindings({
        objectApiName,
        fields,
        filterContext,
        filterBindings: {},
        bucketFields,
        boardBucketFields
    });
    const bucketById = new Map(
        resolved.filter((item) => item.bucketField).map((item) => [item.filterId, item.bucketField])
    );
    const appliedById = new Map(applied.map((item) => [item.filterId, item.fieldPath]));
    const ids = filters.map((def) => def.filterId);
    if (includeRecordContext) {
        ids.push(RECORD_CONTEXT_FILTER_ID);
    }
    const textModes = new Map(filters.map((def) => [def.filterId, def.type === 'TEXT' ? def.matchMode : null]));
    ids.forEach((filterId) => {
        if (textModes.get(filterId) === 'SOSL') {
            preview.set(filterId, { status: 'SOSL', fieldPath: null });
        } else if (bucketById.has(filterId)) {
            const bucketField = bucketById.get(filterId);
            preview.set(filterId, {
                status: 'BUCKET',
                fieldPath: appliedById.get(filterId),
                bucketLabel: cleanString(bucketField.label) || bucketField.id
            });
        } else if (appliedById.has(filterId)) {
            const fieldPath = appliedById.get(filterId);
            preview.set(filterId, { status: fieldPath ? 'BOUND' : 'RUNTIME', fieldPath });
        } else {
            preview.set(filterId, { status: 'UNBOUND', fieldPath: null });
        }
    });
    return preview;
}

// ---- Binding rows ----------------------------------------------------------------------------------------------

export const MODE_CONVENTION = 'CONVENTION';
export const MODE_PATH = 'PATH';
export const MODE_IGNORE = 'IGNORE';
const RESOLVED_CONVENTION = ['BOUND', 'RUNTIME', 'SOSL', 'BUCKET'];

/** The `filterBindings` of a config, or `{}`. */
export function bindingsOf(config) {
    return isPlainObject(config?.filterBindings) ? config.filterBindings : {};
}

/** True when `filterId` has a non-IGNORE path binding in `bindings`. */
export function hasPathBinding(bindings, filterId) {
    return Object.prototype.hasOwnProperty.call(bindings, filterId) && !isIgnoreBinding(bindings[filterId]);
}

/** The Admin-facing note on which Filter widgets were found for `boardId`. */
export function discoveryMessage(discovery, boardId, objectApiName) {
    const { widgets, sameScreen } = discovery;
    const board = cleanString(boardId) || 'default';
    if (!widgets.length) {
        return `No Filter widget with Board id "${board}" was found on this screen. Add a filterId manually to bind a Filter widget that lives outside this Flow.`;
    }
    const names = widgets.map((widget) => widget.name).join(', ');
    const where = sameScreen ? 'on this screen' : 'in this Flow';
    return `Filter widget ${names} found ${where} (Board id "${board}"). Filters bind by convention on ${
        cleanString(objectApiName) || 'the selected object'
    } unless overridden.`;
}

function conventionText(item, { objectApiName, previewLoading, previewError }) {
    if (!cleanString(objectApiName)) {
        return 'Select an object to preview';
    }
    if (previewLoading) {
        return 'Loading fields…';
    }
    if (previewError) {
        return previewError;
    }
    switch (item ? item.status : null) {
        case 'BOUND':
            return item.fieldPath;
        case 'RUNTIME':
            return 'Record Id (matched at runtime)';
        case 'SOSL':
            return 'SOSL search (all searchable fields)';
        case 'BUCKET':
            return `Bucket field: ${item.bucketLabel}`;
        default:
            return 'Unbound (skipped)';
    }
}

/**
 * The Filter binding rows of a data Widget: every Filter of the discovered Filter widgets (plus Record context when
 * one scopes it), then the bound or manually added filter ids. Each row carries its mode, path, convention preview,
 * effective binding, `status` (`bound` / `unbound` / `ignored`) and `error`.
 *
 * `state`: `{ discovery, bindings, objectApiName, previewFields, previewLoading, previewError, pendingPathIds,
 * manualFilterIds, bucketFields }`; `pendingPathIds` are rows switched to "Field path" without a path yet;
 * `bucketFields` are the Widget's own Bucket fields (the Board's come from the discovered Filter widgets).
 */
export function bindingRows(state) {
    const { discovery, bindings, objectApiName, previewFields, previewLoading, previewError } = state;
    const pendingPathIds = state.pendingPathIds || [];
    const manualFilterIds = state.manualFilterIds || [];
    const definitions = [];
    const seen = new Set();
    discovery.widgets.forEach((widget) =>
        widget.filters.forEach((def) => {
            if (!seen.has(def.filterId)) {
                seen.add(def.filterId);
                definitions.push(def);
            }
        })
    );
    const includeRecordContext = discovery.widgets.some((widget) => widget.scopesRecordContext);
    const preview =
        cleanString(objectApiName) && !previewLoading && !previewError
            ? previewConventionBindings({
                  objectApiName,
                  fields: previewFields || [],
                  filters: definitions,
                  includeRecordContext,
                  bucketFields: Array.isArray(state.bucketFields) ? state.bucketFields : [],
                  boardBucketFields: discovery.widgets.flatMap((widget) => widget.bucketFields || [])
              })
            : null;

    const row = (filterId, label, typeLabel, isManual, def = null) => {
        const hasBinding = Object.prototype.hasOwnProperty.call(bindings, filterId);
        const binding = bindings[filterId];
        let mode = MODE_CONVENTION;
        if (pendingPathIds.includes(filterId)) {
            mode = MODE_PATH;
        } else if (hasBinding) {
            mode = isIgnoreBinding(binding) ? MODE_IGNORE : MODE_PATH;
        }
        const path = hasPathBinding(bindings, filterId) ? String(binding) : '';
        const previewItem = preview && !isManual ? preview.get(filterId) : null;
        const convention = isManual ? 'Resolved by convention at runtime' : conventionText(previewItem, state);
        let effectiveText = convention;
        let status =
            isManual || (previewItem && RESOLVED_CONVENTION.includes(previewItem.status)) ? 'bound' : 'unbound';
        if (mode === MODE_IGNORE || (mode === MODE_PATH && hasBinding && !path)) {
            effectiveText = 'Ignored by this widget';
            status = 'ignored';
        } else if (path) {
            effectiveText = path;
            status = 'bound';
        }
        const isTeam = Boolean(def) && def.type === 'USER' && def.matchMode === 'usersAndTeam';
        const teamError = isTeam && path ? teamBindingHopError(filterId, path) : null;
        return {
            key: filterId,
            filterId,
            label,
            typeLabel,
            isManual,
            mode,
            isPath: mode === MODE_PATH,
            path,
            conventionText: convention,
            effectiveText,
            status,
            teamError,
            error: path && !isValidBindingPath(path) ? `Invalid binding. ${BINDING_PATH_HELP}` : teamError
        };
    };

    const rows = definitions.map((def) => row(def.filterId, def.label, FILTER_TYPE_LABELS[def.type], false, def));
    if (includeRecordContext) {
        seen.add(RECORD_CONTEXT_FILTER_ID);
        rows.push(row(RECORD_CONTEXT_FILTER_ID, 'Record context', 'Record', false));
    }
    [...Object.keys(bindings), ...manualFilterIds].forEach((filterId) => {
        if (!seen.has(filterId)) {
            seen.add(filterId);
            rows.push(row(filterId, filterId, 'Manual', true));
        }
    });
    return rows;
}

/** Design-time errors of the binding rows: a "Field path" without a path, or a Team filter bound too deep. */
export function bindingRowErrors(rows, bindings, pendingPathIds = []) {
    const errors = [];
    pendingPathIds
        .filter((filterId) => !hasPathBinding(bindings, filterId))
        .forEach((filterId) =>
            errors.push({ key: 'filterBindings', errorString: `Filter binding "${filterId}": enter a field path.` })
        );
    rows.filter((row) => row.teamError).forEach((row) =>
        errors.push({ key: 'filterBindings', errorString: row.teamError })
    );
    return errors;
}