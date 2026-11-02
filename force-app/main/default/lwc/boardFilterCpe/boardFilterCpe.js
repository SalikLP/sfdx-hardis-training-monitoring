import { LightningElement, api } from 'lwc';
import getPicklistOptions from '@salesforce/apex/BoardSchemaService.getPicklistOptions';
import resolveRecordLabels from '@salesforce/apex/BoardSchemaService.resolveRecordLabels';
import searchUsersAndQueues from '@salesforce/apex/BoardSchemaService.searchUsersAndQueues';
import { DATE_PRESETS, RECORD_CONTEXT_OVERRIDE_TYPES, normalizeBoardError } from 'c/boardConfigUtils';
import {
    FILTER_TYPE_LABELS,
    FILTER_TYPE_OPTIONS,
    PERSISTENCE_OPTIONS,
    RECORD_CONTEXT_MODE_OPTIONS,
    TEXT_MATCH_MODE_OPTIONS,
    applyPatch,
    cleanString,
    filterOptionsSource,
    filterSelectionMode,
    isDatePreset,
    isDerivedId,
    isPlainObject,
    moveItem,
    parseNumber,
    toCamelCase,
    uniqueId,
    validateCpe
} from 'c/boardCpeUtils';

const SELECTION_OPTIONS = [
    { label: 'Single', value: 'single' },
    { label: 'Multiple', value: 'multi' }
];
const OPTIONS_SOURCE_OPTIONS = [
    { label: 'Field picklist values', value: 'FIELD_DESCRIBE' },
    { label: 'Custom options', value: 'CUSTOM' }
];
const DATE_NONE = '';
const DATE_CUSTOM_LITERAL = '__CUSTOM_LITERAL__';
const DATE_CUSTOM_DATES = '__DATES__';
const DATE_DEFAULT_OPTIONS = [
    { label: 'No default', value: DATE_NONE },
    ...DATE_PRESETS,
    { label: 'Custom literal (e.g. LAST_N_DAYS:45)', value: DATE_CUSTOM_LITERAL },
    { label: 'Custom dates', value: DATE_CUSTOM_DATES }
];
const NO_DEFAULT = '';
const USER_SEARCH_MIN_CHARACTERS = 2;
// Keys owned by one filter type; dropped when the type changes.
const TYPE_KEYS = [
    'selectionMode',
    'targetObjectApiName',
    'optionsSource',
    'sourceObjectApiName',
    'options',
    'includeQueues',
    'matchMode',
    'minCharacters',
    'placeholder',
    'defaultValue'
];

function picklistKey(objectApiName, fieldApiName) {
    return `${objectApiName}.${fieldApiName}`;
}

function defaultOf(filter) {
    return isPlainObject(filter.defaultValue) ? filter.defaultValue : {};
}

function defaultValuesOf(filter) {
    const values = defaultOf(filter).values;
    return Array.isArray(values) ? values.filter((value) => typeof value === 'string') : [];
}

/**
 * Flow Custom Property Editor for the Board Filter widget: ordered filter definitions (auto-derived, editable
 * camelCase `filterId`s and per-type settings for PICKLIST, LOOKUP, USER, DATE_RANGE, and TEXT), Record context, and
 * persistence, inside the shared `c-board-cpe-common` shell (Board, Config JSON).
 */
export default class BoardFilterCpe extends LightningElement {
    @api inputVariables = [];
    @api builderContext = {};
    @api elementInfo = {};

    config = {};
    newFilterType = 'PICKLIST';

    typeOptions = FILTER_TYPE_OPTIONS;
    selectionOptions = SELECTION_OPTIONS;
    optionsSourceOptions = OPTIONS_SOURCE_OPTIONS;
    matchModeOptions = TEXT_MATCH_MODE_OPTIONS;
    dateDefaultOptions = DATE_DEFAULT_OPTIONS;
    recordContextOptions = RECORD_CONTEXT_MODE_OPTIONS;
    persistenceOptions = PERSISTENCE_OPTIONS;

    /** `Object.Field` → `{ loading, options, error }` for FIELD_DESCRIBE picklist defaults. */
    picklistOptions = {};
    /** Record Id → name of LOOKUP/USER default values. */
    recordLabels = {};
    /** Row key → `{ term, results }` of the USER default search. */
    userSearches = {};

    /** Stable template keys parallel to `filters` (filterIds change while typing). */
    _rowKeys = [];
    _keySeq = 0;
    /** Row key → date default mode chosen before any value is entered. */
    _dateModes = {};

    @api
    validate() {
        return validateCpe(this.shell, 'filter', this.inputVariables);
    }

    get shell() {
        return this.template.querySelector('c-board-cpe-common');
    }

    handleConfigChange(event) {
        this.config = event.detail.config;
        if (this._rowKeys.length !== this.filters.length) {
            this._rowKeys = this.filters.map(() => this.nextKey());
            this._dateModes = {};
        }
        this.loadDefaultSupport();
    }

    /** Loads described picklist values and record names the default-value editors display. */
    loadDefaultSupport() {
        const missingIds = new Set();
        this.filters.forEach((filter) => {
            const objectApiName = cleanString(filter.sourceObjectApiName);
            const fieldApiName = cleanString(filter.fieldApiName);
            if (
                filter.type === 'PICKLIST' &&
                filterOptionsSource(filter) === 'FIELD_DESCRIBE' &&
                objectApiName &&
                fieldApiName
            ) {
                this.loadPicklistOptions(objectApiName, fieldApiName);
            }
            if (filter.type === 'LOOKUP' || filter.type === 'USER') {
                defaultValuesOf(filter)
                    .filter((id) => !(id in this.recordLabels))
                    .forEach((id) => missingIds.add(id));
            }
        });
        if (missingIds.size) {
            const recordIds = [...missingIds];
            // Mark as requested so a pending lookup is not repeated; unresolved ids show as-is.
            this.recordLabels = { ...Object.fromEntries(recordIds.map((id) => [id, id])), ...this.recordLabels };
            resolveRecordLabels({ recordIds })
                .then((labels) => {
                    this.recordLabels = { ...this.recordLabels, ...(labels || {}) };
                })
                .catch(() => {
                    // Ids stay visible; the runtime resolves names again.
                });
        }
    }

    loadPicklistOptions(objectApiName, fieldApiName) {
        const key = picklistKey(objectApiName, fieldApiName);
        if (this.picklistOptions[key]) {
            return;
        }
        this.picklistOptions = { ...this.picklistOptions, [key]: { loading: true, options: [], error: null } };
        getPicklistOptions({ objectApiName, fieldApiName })
            .then((options) => {
                this.picklistOptions = {
                    ...this.picklistOptions,
                    [key]: { loading: false, options: options || [], error: null }
                };
            })
            .catch((err) => {
                this.picklistOptions = {
                    ...this.picklistOptions,
                    [key]: { loading: false, options: [], error: normalizeBoardError(err).message }
                };
            });
    }

    nextKey() {
        this._keySeq += 1;
        return `filter-${this._keySeq}`;
    }

    update(patch) {
        this.shell.updateConfig(patch);
    }

    get filters() {
        return Array.isArray(this.config.filters) ? this.config.filters.map((f) => (isPlainObject(f) ? f : {})) : [];
    }

    get hasFilters() {
        return this.filters.length > 0;
    }

    // ---- Filter rows ---------------------------------------------------------------------------------------------

    get filterRows() {
        const filters = this.filters;
        const last = filters.length - 1;
        return filters.map((filter, index) => {
            const key = this._rowKeys[index] || `index-${index}`;
            const type = filter.type;
            const options = Array.isArray(filter.options) ? filter.options : [];
            const optionsSource = filterOptionsSource(filter);
            const selectionMode = filterSelectionMode(filter);
            const defaultValue = defaultOf(filter);
            const defaultValues = defaultValuesOf(filter);
            const dateMode = this.dateMode(key, defaultValue);
            const picklistDefault = type === 'PICKLIST' ? this.picklistDefault(filter, optionsSource) : {};
            const userSearch = this.userSearches[key] || { term: '', results: [] };
            return {
                key,
                selectionName: `${key}-selection`,
                sourceName: `${key}-source`,
                index,
                title: `Filter ${index + 1}`,
                label: filter.label || '',
                filterId: filter.filterId || '',
                type,
                typeLabel: FILTER_TYPE_LABELS[type] || 'Unknown type',
                isFirst: index === 0,
                isLast: index === last,
                isPicklist: type === 'PICKLIST',
                isLookup: type === 'LOOKUP',
                isUser: type === 'USER',
                isDateRange: type === 'DATE_RANGE',
                isText: type === 'TEXT',
                showSelectionMode: ['PICKLIST', 'LOOKUP', 'USER'].includes(type),
                selectionMode,
                isSingle: selectionMode === 'single',
                fieldApiName: filter.fieldApiName || '',
                optionsSource,
                isCustomOptions: optionsSource === 'CUSTOM',
                sourceObjectApiName: filter.sourceObjectApiName || '',
                sourceFieldObject: filter.sourceObjectApiName || null,
                optionRows: options.map((option, optionIndex) => ({
                    key: `${key}-option-${optionIndex}`,
                    optionIndex,
                    label: isPlainObject(option) && option.label ? option.label : '',
                    value: isPlainObject(option) && option.value !== undefined ? String(option.value) : ''
                })),
                ...picklistDefault,
                defaultValues,
                defaultSingle: defaultValues[0] || NO_DEFAULT,
                defaultPills: defaultValues.map((value) => ({
                    key: `${key}-default-${value}`,
                    value,
                    label: this.recordLabels[value] || value
                })),
                hasDefaultPills: defaultValues.length > 0,
                targetObjectApiName: filter.targetObjectApiName || '',
                hasTargetObject: Boolean(cleanString(filter.targetObjectApiName)),
                includeQueues: filter.includeQueues === true,
                defaultMe: defaultValue.token === 'ME',
                userSearchTerm: userSearch.term,
                userResults: userSearch.results.map((result) => ({
                    key: `${key}-user-${result.id}`,
                    id: result.id,
                    label: result.entityType === 'Queue' ? `${result.label} (Queue)` : result.label
                })),
                hasUserResults: userSearch.results.length > 0,
                defaultText: typeof defaultValue.text === 'string' ? defaultValue.text : '',
                dateDefault: dateMode,
                isCustomLiteral: dateMode === DATE_CUSTOM_LITERAL,
                isCustomDates: dateMode === DATE_CUSTOM_DATES,
                customLiteral: defaultValue.literal || '',
                defaultFrom: defaultValue.from || '',
                defaultTo: defaultValue.to || '',
                matchMode: filter.matchMode || 'SOSL',
                showTextField: (filter.matchMode || 'SOSL') !== 'SOSL',
                minCharacters:
                    filter.minCharacters === null || filter.minCharacters === undefined
                        ? ''
                        : String(filter.minCharacters),
                placeholder: filter.placeholder || ''
            };
        });
    }

    dateMode(key, defaultValue) {
        if (defaultValue.from || defaultValue.to) {
            return DATE_CUSTOM_DATES;
        }
        if (defaultValue.literal) {
            // A literal typed in custom mode stays editable there even when it matches a preset.
            return this._dateModes[key] !== DATE_CUSTOM_LITERAL && isDatePreset(defaultValue.literal)
                ? defaultValue.literal
                : DATE_CUSTOM_LITERAL;
        }
        return this._dateModes[key] || DATE_NONE;
    }

    /** Choices of the PICKLIST default editor: custom options or the described picklist values. */
    picklistDefault(filter, optionsSource) {
        let choices = [];
        let message = null;
        if (optionsSource === 'CUSTOM') {
            choices = (Array.isArray(filter.options) ? filter.options : [])
                .filter((option) => isPlainObject(option) && cleanString(option.value))
                .map((option) => ({ label: cleanString(option.label) || option.value, value: option.value.trim() }));
        } else if (cleanString(filter.sourceObjectApiName) && cleanString(filter.fieldApiName)) {
            const state =
                this.picklistOptions[picklistKey(filter.sourceObjectApiName.trim(), filter.fieldApiName.trim())];
            if (!state || state.loading) {
                message = 'Loading picklist values…';
            } else if (state.error) {
                message = state.error;
            }
            choices = state ? state.options.map((option) => ({ label: option.label, value: option.value })) : [];
        } else {
            message = 'Choose the picklist field to pick default values.';
        }
        const known = new Set(choices.map((choice) => choice.value));
        defaultValuesOf(filter)
            .filter((value) => !known.has(value))
            .forEach((value) => choices.push({ label: `${value} (not an option)`, value }));
        return {
            defaultChoices: choices,
            defaultSingleOptions: [{ label: 'No default', value: NO_DEFAULT }, ...choices],
            hasDefaultChoices: choices.length > 0,
            defaultChoicesMessage: message
        };
    }

    handleNewType(event) {
        this.newFilterType = event.detail.value;
    }

    handleAddFilter() {
        const type = this.newFilterType;
        const label = FILTER_TYPE_LABELS[type];
        const filter = {
            filterId: uniqueId(
                toCamelCase(label),
                this.filters.map((item) => item.filterId)
            ),
            label,
            type
        };
        if (type === 'PICKLIST') {
            filter.optionsSource = 'FIELD_DESCRIBE';
        }
        this._rowKeys = [...this._rowKeys, this.nextKey()];
        this.setFilters([...this.filters, filter]);
    }

    handleRemoveFilter(event) {
        const index = Number(event.currentTarget.dataset.index);
        const removed = this.filters[index];
        this._rowKeys = this._rowKeys.filter((key, position) => position !== index);
        const patch = { filters: this.filters.filter((filter, position) => position !== index) };
        this.retargetRecordContext(patch, removed ? removed.filterId : null, null);
        this.update(this.normalizeFiltersPatch(patch));
    }

    handleMoveUp(event) {
        this.moveFilter(Number(event.currentTarget.dataset.index), -1);
    }

    handleMoveDown(event) {
        this.moveFilter(Number(event.currentTarget.dataset.index), 1);
    }

    moveFilter(index, offset) {
        this._rowKeys = moveItem(this._rowKeys, index, offset);
        this.setFilters(moveItem(this.filters, index, offset));
    }

    handleLabel(event) {
        const index = Number(event.target.dataset.index);
        const filter = this.filters[index];
        const label = event.detail.value || '';
        const patch = { label: label.trim() ? label : null };
        if (isDerivedId(filter.filterId, filter.label || '')) {
            patch.filterId = uniqueId(toCamelCase(label), this.otherIds(index));
        }
        this.updateFilter(index, patch);
    }

    handleFilterId(event) {
        this.updateFilter(Number(event.target.dataset.index), { filterId: cleanString(event.detail.value) });
    }

    handleType(event) {
        const index = Number(event.target.dataset.index);
        const type = event.detail.value;
        const reset = Object.fromEntries(TYPE_KEYS.map((key) => [key, null]));
        const filterId = this.filters[index].filterId;
        const configPatch = {};
        if (!RECORD_CONTEXT_OVERRIDE_TYPES.includes(type)) {
            // Record context can only feed Picklist, Lookup, and User filters.
            this.retargetRecordContext(configPatch, filterId, null);
        }
        this.updateFilter(
            index,
            { ...reset, type, optionsSource: type === 'PICKLIST' ? 'FIELD_DESCRIBE' : null },
            configPatch
        );
    }

    handleSelectionMode(event) {
        this.updateFilter(Number(event.target.dataset.index), { selectionMode: event.detail.value });
    }

    handleFieldApiName(event) {
        this.updateFilter(Number(event.target.dataset.index), { fieldApiName: cleanString(event.detail.value) });
    }

    // PICKLIST

    handleOptionsSource(event) {
        const index = Number(event.target.dataset.index);
        const optionsSource = event.detail.value;
        const filter = this.filters[index];
        this.updateFilter(index, {
            optionsSource,
            sourceObjectApiName: optionsSource === 'CUSTOM' ? null : filter.sourceObjectApiName,
            options:
                optionsSource === 'CUSTOM'
                    ? (Array.isArray(filter.options) && filter.options.length && filter.options) || [
                          { label: '', value: '' }
                      ]
                    : null
        });
    }

    handleSourceObject(event) {
        const index = Number(event.target.dataset.index);
        const sourceObjectApiName = event.detail.value || null;
        const filter = this.filters[index];
        const patch = { sourceObjectApiName };
        if (sourceObjectApiName !== (filter.sourceObjectApiName || null)) {
            patch.fieldApiName = null;
        }
        this.updateFilter(index, patch);
    }

    handleSourceField(event) {
        this.updateFilter(Number(event.target.dataset.index), { fieldApiName: event.detail.value || null });
    }

    handleAddOption(event) {
        const index = Number(event.currentTarget.dataset.index);
        const options = Array.isArray(this.filters[index].options) ? this.filters[index].options : [];
        this.updateFilter(index, { options: [...options, { label: '', value: '' }] });
    }

    handleRemoveOption(event) {
        const index = Number(event.currentTarget.dataset.index);
        const optionIndex = Number(event.currentTarget.dataset.optionIndex);
        const options = this.filters[index].options.filter((option, position) => position !== optionIndex);
        this.updateFilter(index, { options });
    }

    handleOptionText(event) {
        const index = Number(event.target.dataset.index);
        const optionIndex = Number(event.target.dataset.optionIndex);
        const name = event.target.dataset.name;
        const options = this.filters[index].options.map((option, position) => {
            return position === optionIndex ? { ...option, [name]: event.detail.value || '' } : option;
        });
        this.updateFilter(index, { options });
    }

    // LOOKUP / USER

    handleTargetObject(event) {
        this.updateFilter(Number(event.target.dataset.index), { targetObjectApiName: event.detail.value || null });
    }

    handleIncludeQueues(event) {
        this.updateFilter(Number(event.target.dataset.index), { includeQueues: event.detail.checked ? true : null });
    }

    // Defaults (spec §5 `defaultValue`): PICKLIST/LOOKUP/USER `{ values?, token? }`, TEXT `{ text }`.

    setChoiceDefault(index, values, token) {
        const unique = [...new Set(values)];
        const defaultValue = applyPatch({}, { token: token || null, values: unique.length ? unique : null });
        this.updateFilter(index, { defaultValue: Object.keys(defaultValue).length ? defaultValue : null });
    }

    /** Adds a default value (replacing the current one, including Me, on single-select filters). */
    addDefaultValue(index, value) {
        const filter = this.filters[index];
        if (filterSelectionMode(filter) === 'single') {
            this.setChoiceDefault(index, [value], null);
            return;
        }
        this.setChoiceDefault(index, [...defaultValuesOf(filter), value], defaultOf(filter).token);
    }

    handleDefaultValues(event) {
        const values = event.detail.value;
        this.setChoiceDefault(Number(event.target.dataset.index), Array.isArray(values) ? values : [], null);
    }

    handleDefaultSingle(event) {
        const value = event.detail.value;
        this.setChoiceDefault(Number(event.target.dataset.index), value ? [value] : [], null);
    }

    handleDefaultRecord(event) {
        const recordId = event.detail.recordId;
        if (recordId) {
            this.addDefaultValue(Number(event.target.dataset.index), recordId);
        }
    }

    handleRemoveDefault(event) {
        const index = Number(event.target.dataset.index);
        const filter = this.filters[index];
        const remaining = defaultValuesOf(filter).filter((value) => value !== event.target.dataset.value);
        this.setChoiceDefault(index, remaining, defaultOf(filter).token);
    }

    handleDefaultMe(event) {
        const index = Number(event.target.dataset.index);
        const filter = this.filters[index];
        const checked = event.detail.checked;
        const single = filterSelectionMode(filter) === 'single';
        this.setChoiceDefault(index, checked && single ? [] : defaultValuesOf(filter), checked ? 'ME' : null);
    }

    handleUserSearch(event) {
        const index = Number(event.target.dataset.index);
        const key = this._rowKeys[index];
        const term = event.detail.value || '';
        this.userSearches = { ...this.userSearches, [key]: { term, results: [] } };
        if (term.trim().length < USER_SEARCH_MIN_CHARACTERS) {
            return;
        }
        searchUsersAndQueues({ searchTerm: term.trim(), includeQueues: this.filters[index].includeQueues === true })
            .then((results) => {
                if (this.userSearches[key] && this.userSearches[key].term === term) {
                    this.userSearches = { ...this.userSearches, [key]: { term, results: results || [] } };
                }
            })
            .catch(() => {
                // No suggestions; the admin can retype.
            });
    }

    handleUserPick(event) {
        const index = Number(event.currentTarget.dataset.index);
        const { id, label } = event.currentTarget.dataset;
        const key = this._rowKeys[index];
        this.recordLabels = { ...this.recordLabels, [id]: label };
        this.userSearches = { ...this.userSearches, [key]: { term: '', results: [] } };
        this.addDefaultValue(index, id);
    }

    handleDefaultText(event) {
        const text = event.detail.value;
        this.updateFilter(Number(event.target.dataset.index), {
            defaultValue: text && text.trim() ? { text } : null
        });
    }

    // DATE_RANGE

    handleDateDefault(event) {
        const index = Number(event.target.dataset.index);
        const key = this._rowKeys[index];
        const selection = event.detail.value;
        this._dateModes = { ...this._dateModes, [key]: selection };
        if (selection === DATE_NONE || selection === DATE_CUSTOM_LITERAL || selection === DATE_CUSTOM_DATES) {
            this.updateFilter(index, { defaultValue: null });
            return;
        }
        this.updateFilter(index, { defaultValue: { operator: 'LITERAL', literal: selection } });
    }

    handleCustomLiteral(event) {
        const literal = String(event.detail.value || '')
            .trim()
            .toUpperCase();
        this.updateFilter(Number(event.target.dataset.index), {
            defaultValue: literal ? { operator: 'LITERAL', literal } : null
        });
    }

    handleDefaultDate(event) {
        const index = Number(event.target.dataset.index);
        const current = isPlainObject(this.filters[index].defaultValue) ? this.filters[index].defaultValue : {};
        const dates = { from: current.from || null, to: current.to || null };
        dates[event.target.dataset.name] = event.detail.value || null;
        let operator = 'LTE';
        if (dates.from && dates.to) {
            operator = 'BETWEEN';
        } else if (dates.from) {
            operator = 'GTE';
        }
        this.updateFilter(index, {
            defaultValue: dates.from || dates.to ? applyPatch({ operator }, dates) : null
        });
    }

    // TEXT

    handleMatchMode(event) {
        this.updateFilter(Number(event.target.dataset.index), { matchMode: event.detail.value });
    }

    handleMinCharacters(event) {
        this.updateFilter(Number(event.target.dataset.index), { minCharacters: parseNumber(event.detail.value) });
    }

    handlePlaceholder(event) {
        const value = event.detail.value;
        this.updateFilter(Number(event.target.dataset.index), { placeholder: value && value.trim() ? value : null });
    }

    otherIds(index) {
        return this.filters.filter((filter, position) => position !== index).map((filter) => filter.filterId);
    }

    updateFilter(index, patch, extraConfigPatch = {}) {
        const previous = this.filters[index];
        const next = applyPatch(previous, patch);
        const filters = this.filters.map((filter, position) => (position === index ? next : filter));
        const configPatch = { ...extraConfigPatch, filters };
        if (previous.filterId !== next.filterId) {
            this.retargetRecordContext(configPatch, previous.filterId, next.filterId || null);
        }
        this.update(configPatch);
    }

    setFilters(filters) {
        this.update(this.normalizeFiltersPatch({ filters }));
    }

    normalizeFiltersPatch(patch) {
        return { ...patch, filters: patch.filters.length ? patch.filters : null };
    }

    /** Keeps `recordContext.overrideFilterId` pointing at a renamed filter (or clears it when removed). */
    retargetRecordContext(patch, fromId, toId) {
        const recordContext = this.recordContext;
        if (fromId && recordContext.overrideFilterId === fromId) {
            patch.recordContext = this.compactRecordContext({ ...recordContext, overrideFilterId: toId });
        }
    }

    // ---- Record context & persistence ----------------------------------------------------------------------------

    get recordContext() {
        return isPlainObject(this.config.recordContext) ? this.config.recordContext : {};
    }

    get recordContextMode() {
        return this.recordContext.mode || 'IMPLICIT';
    }

    get isLocked() {
        return this.recordContextMode === 'LOCKED';
    }

    get overrideFilterOptions() {
        return [
            { label: 'None (filter Widgets by the record Id)', value: '' },
            ...this.filters
                .filter((filter) => cleanString(filter.filterId) && RECORD_CONTEXT_OVERRIDE_TYPES.includes(filter.type))
                .map((filter) => ({
                    label: `${filter.label || filter.filterId} (${filter.filterId})`,
                    value: filter.filterId
                }))
        ];
    }

    get overrideFilterId() {
        return this.recordContext.overrideFilterId || '';
    }

    get overrideFieldPath() {
        return this.recordContext.overrideFieldPath || '';
    }

    get showRecordContextBadge() {
        return this.config.showRecordContextBadge !== false;
    }

    get persistence() {
        return this.config.persistence || 'SESSION';
    }

    handleRecordContextMode(event) {
        this.updateRecordContext({ mode: event.detail.value });
    }

    handleOverrideFilterId(event) {
        this.updateRecordContext({ overrideFilterId: event.detail.value || null });
    }

    handleOverrideFieldPath(event) {
        this.updateRecordContext({ overrideFieldPath: cleanString(event.detail.value) });
    }

    handleBadge(event) {
        this.update({ showRecordContextBadge: event.detail.checked ? null : false });
    }

    handlePersistence(event) {
        this.update({ persistence: event.detail.value });
    }

    updateRecordContext(patch) {
        this.update({ recordContext: this.compactRecordContext({ ...this.recordContext, ...patch }) });
    }

    /** `{ mode, overrideFilterId?, overrideFieldPath? }`, or null for the default (IMPLICIT without overrides). */
    compactRecordContext(recordContext) {
        const next = applyPatch(
            { mode: recordContext.mode || 'IMPLICIT' },
            {
                overrideFilterId: cleanString(recordContext.overrideFilterId),
                overrideFieldPath: cleanString(recordContext.overrideFieldPath)
            }
        );
        return next.mode === 'IMPLICIT' && Object.keys(next).length === 1 ? null : next;
    }
}