/**
 * Pure helpers behind the shared Flow CPE shell: `builderContext` Filter widget discovery and convention-binding
 * preview via `resolveFilterBindings`. Config envelope and validation helpers live in `c/boardCpeUtils`.
 */
import { RECORD_CONTEXT_FILTER_ID, RECORD_CONTEXT_OVERRIDE_TYPES, resolveFilterBindings } from 'c/boardConfigUtils';
import { normalizeFilterDefinitions } from 'c/boardContextStore';
import { RECORD_CONTEXT_MODES, cleanString, isPlainObject } from 'c/boardCpeUtils';

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
    return entry;
}

/**
 * Convention binding (no `filterBindings` overrides) of each discovered filter on `objectApiName`.
 * @returns {Map<string, {status: 'BOUND'|'RUNTIME'|'SOSL'|'UNBOUND', fieldPath: string|null}>}
 */
export function previewConventionBindings({ objectApiName, fields, filters, includeRecordContext }) {
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
    const { applied } = resolveFilterBindings({ objectApiName, fields, filterContext, filterBindings: {} });
    const appliedById = new Map(applied.map((item) => [item.filterId, item.fieldPath]));
    const ids = filters.map((def) => def.filterId);
    if (includeRecordContext) {
        ids.push(RECORD_CONTEXT_FILTER_ID);
    }
    const textModes = new Map(filters.map((def) => [def.filterId, def.type === 'TEXT' ? def.matchMode : null]));
    ids.forEach((filterId) => {
        if (textModes.get(filterId) === 'SOSL') {
            preview.set(filterId, { status: 'SOSL', fieldPath: null });
        } else if (appliedById.has(filterId)) {
            const fieldPath = appliedById.get(filterId);
            preview.set(filterId, { status: fieldPath ? 'BOUND' : 'RUNTIME', fieldPath });
        } else {
            preview.set(filterId, { status: 'UNBOUND', fieldPath: null });
        }
    });
    return preview;
}