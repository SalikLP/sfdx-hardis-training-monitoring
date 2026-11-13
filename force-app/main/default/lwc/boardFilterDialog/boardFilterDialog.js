import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getPicklistOptions from '@salesforce/apex/BoardSchemaService.getPicklistOptions';
import resolveRecordLabels from '@salesforce/apex/BoardSchemaService.resolveRecordLabels';
import searchUsersAndQueues from '@salesforce/apex/BoardSchemaService.searchUsersAndQueues';
import getCurrencyOptions from '@salesforce/apex/BoardCurrencyConverter.getCurrencyOptions';
import {
    DATE_PRESETS,
    CURRENCY_PICKER_ITEM,
    EMPTY_FILLED_OPERATORS,
    RECORD_CONTEXT_OVERRIDE_TYPES,
    isCurrencyPickerItem,
    normalizeBoardError
} from 'c/boardConfigUtils';
import {
    ConfigDialogMixin,
    FILTER_TYPE_LABELS,
    FILTER_TYPE_OPTIONS,
    TEXT_MATCH_MODE_OPTIONS,
    USER_MATCH_MODE_OPTIONS,
    applyPatch,
    cleanString,
    compactRecordContext,
    validateFilterDefinitions,
    filterOptionsSource,
    filterSelectionMode,
    isDatePreset,
    isDerivedId,
    isPlainObject,
    parseNumber,
    recordContextErrors,
    toCamelCase,
    uniqueId
} from 'c/boardCpeUtils';

const SELECTION_OPTIONS = [
    { label: 'Single', value: 'single' },
    { label: 'Multiple', value: 'multi' }
];
const DISPLAY_OPTIONS = [
    { label: 'Dropdown', value: 'dropdown' },
    { label: 'Buttons (up to 5 values)', value: 'buttons' }
];
const EMPTY_FILLED_DEFAULT_OPTIONS = [
    { label: 'All', value: 'ALL' },
    { label: 'Empty', value: 'EMPTY' },
    { label: 'Filled in', value: 'FILLED' }
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
    'display',
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
 * Filter definitions Config dialog: a large `LightningModal` that edits a draft of the Filter widget's `filters`
 * (master-detail: ordered list on the left, the selected filter's settings on the right). Open it with
 * `openConfigDialog(BoardFilterDialog, { label, description, value: { filters, recordContext } })`.
 *
 * Closes with `{ action: 'save', draft: { filters, recordContext } }` or `{ action: 'dismiss' }`. `recordContext` is
 * carried only so its override follows filterId renames, removals, and type changes made in the draft. Save stays
 * disabled while any draft filter breaks the Filter widget's validation rules (`validateFilterDefinitions`), or while
 * the Record context no longer matches the draft filters (`recordContextErrors`).
 */
export default class BoardFilterDialog extends ConfigDialogMixin(LightningModal) {
    /** `{ filters, recordContext, bucketFields }`, already deep-copied by `openConfigDialog`. */
    @api value;

    filters = [];
    recordContext = null;
    /** The Filter widget's Board-level Bucket fields a Bucket filter can use (not edited here). */
    bucketFields = [];
    rowKeyPrefix = 'filter';
    newFilterType = 'PICKLIST';

    typeOptions = FILTER_TYPE_OPTIONS;
    selectionOptions = SELECTION_OPTIONS;
    displayOptions = DISPLAY_OPTIONS;
    emptyFilledDefaultOptions = EMPTY_FILLED_DEFAULT_OPTIONS;
    optionsSourceOptions = OPTIONS_SOURCE_OPTIONS;
    matchModeOptions = TEXT_MATCH_MODE_OPTIONS;
    userMatchModeOptions = USER_MATCH_MODE_OPTIONS;
    dateDefaultOptions = DATE_DEFAULT_OPTIONS;

    /** `Object.Field` → `{ loading, options, error }` for FIELD_DESCRIBE picklist defaults. */
    picklistOptions = {};
    /** Record Id → name of LOOKUP/USER default values. */
    recordLabels = {};
    /** Row key → `{ term, results }` of the USER default search. */
    userSearches = {};

    /** Row key → date default mode chosen before any value is entered. */
    _dateModes = {};

    /** The org's currency setup (`getCurrencyOptions`); a single-currency org has no Currency picker. */
    currencyOptions = null;

    connectedCallback() {
        super.connectedCallback();
        Promise.resolve(getCurrencyOptions())
            .then((options) => {
                this.currencyOptions = options || null;
            })
            .catch(() => {
                this.currencyOptions = null;
            });
    }

    /** Known to be a single-currency org: the Currency picker is unavailable (unknown while loading). */
    get isCurrencyUnavailable() {
        return Boolean(this.currencyOptions) && this.currencyOptions.multiCurrency !== true;
    }

    /** At most one Currency picker per Filter widget, and none in a single-currency org. */
    get isAddCurrencyPickerDisabled() {
        return this.isCurrencyUnavailable || this.filters.some(isCurrencyPickerItem);
    }

    get currencyPickerMeta() {
        const label = FILTER_TYPE_LABELS[CURRENCY_PICKER_ITEM];
        return this.isCurrencyUnavailable ? `${label} (unavailable)` : label;
    }

    // ---- Draft (ConfigDialogMixin) -------------------------------------------------------------------------------

    initDraft(value) {
        const source = isPlainObject(value) ? value : {};
        this.filters = Array.isArray(source.filters) ? source.filters.map((f) => (isPlainObject(f) ? f : {})) : [];
        this.recordContext = source.recordContext === undefined ? null : source.recordContext;
        this.bucketFields = Array.isArray(source.bucketFields) ? source.bucketFields.filter(isPlainObject) : null;
        this.loadDefaultSupport();
    }

    get draftItems() {
        return this.filters;
    }

    /** A removed filter also drops the Record context override that pointed at it. */
    setDraftItems(filters, change) {
        const patch = { filters };
        if (change && change.removed) {
            this.retargetRecordContext(patch, change.removed.filterId, null);
        }
        this.update(patch);
    }

    get draft() {
        return { filters: this.filters, recordContext: this.recordContext };
    }

    // ---- Validation and master list ------------------------------------------------------------------------------

    /** The Filter widget's own validation rules applied to the draft filters. */
    get validation() {
        return validateFilterDefinitions(this.filters, this.bucketFields);
    }

    /** Messages per draft filter. */
    get errorsByIndex() {
        return this.validation.byIndex;
    }

    /**
     * Problems of the carried Record context against the draft filters (e.g. its override filter was renamed onto a
     * duplicate id or now resolves to a filter of the wrong type). Same rule as the Filter widget's `validate()`.
     */
    get recordContextErrors() {
        return recordContextErrors(this.recordContext, this.validation.filterTypes).map((item, position) => ({
            key: `record-context-error-${position}`,
            message: item.errorString
        }));
    }

    get hasRecordContextErrors() {
        return this.recordContextErrors.length > 0;
    }

    get isSaveDisabled() {
        return super.isSaveDisabled || this.hasRecordContextErrors;
    }

    get masterItems() {
        const errors = this.errorsByIndex;
        return this.filters.map((filter, index) => ({
            key: this._rowKeys[index],
            label: this.titleOf(filter, index),
            meta: isCurrencyPickerItem(filter)
                ? this.currencyPickerMeta
                : FILTER_TYPE_LABELS[filter.type] || 'Unknown type',
            hasError: errors[index].length > 0
        }));
    }

    titleOf(filter, index) {
        if (filter.type === 'section') {
            return cleanString(filter.label) || `Section ${index + 1}`;
        }
        if (isCurrencyPickerItem(filter)) {
            return cleanString(filter.label) || FILTER_TYPE_LABELS[CURRENCY_PICKER_ITEM];
        }
        return cleanString(filter.label) || cleanString(filter.filterId) || `Filter ${index + 1}`;
    }

    // ---- Selected filter -----------------------------------------------------------------------------------------

    get row() {
        const index = this.selectedIndex;
        return index < 0 ? null : this.rowFor(this.filters[index], index);
    }

    rowFor(filter, index) {
        const key = this._rowKeys[index];
        const type = filter.type;
        const options = Array.isArray(filter.options) ? filter.options : [];
        const optionsSource = filterOptionsSource(filter);
        const selectionMode = filterSelectionMode(filter);
        const defaultValue = defaultOf(filter);
        const defaultValues = defaultValuesOf(filter);
        const dateMode = this.dateMode(key, defaultValue);
        const picklistDefault = type === 'PICKLIST' ? this.picklistDefault(filter, optionsSource) : {};
        const userSearch = this.userSearches[key] || { term: '', results: [] };
        const errors = this.errorsByIndex[index].map((message, position) => ({
            key: `${key}-error-${position}`,
            message
        }));
        return {
            key,
            isSection: type === 'section',
            isCurrencyPicker: type === CURRENCY_PICKER_ITEM,
            startCollapsed: filter.startCollapsed === true,
            selectionName: `${key}-selection`,
            sourceName: `${key}-source`,
            displayName: `${key}-display`,
            index,
            title: this.titleOf(filter, index),
            errors,
            hasErrors: errors.length > 0,
            label: filter.label || '',
            filterId: filter.filterId || '',
            type,
            typeLabel: FILTER_TYPE_LABELS[type] || 'Unknown type',
            isPicklist: type === 'PICKLIST',
            isLookup: type === 'LOOKUP',
            isUser: type === 'USER',
            isDateRange: type === 'DATE_RANGE',
            isText: type === 'TEXT',
            isEmptyFilled: type === 'EMPTY_FILLED',
            isBucket: type === 'BUCKET',
            bucketFieldId: filter.bucketFieldId || '',
            emptyFilledDefault: EMPTY_FILLED_OPERATORS.includes(defaultValue.operator) ? defaultValue.operator : 'ALL',
            showSelectionMode:
                ['LOOKUP', 'USER'].includes(type) || (type === 'PICKLIST' && filter.display !== 'buttons'),
            display: filter.display === 'buttons' ? 'buttons' : 'dropdown',
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
            userMatchModeName: `${key}-user-match-mode`,
            userMatchMode: filter.matchMode || 'users',
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
                filter.minCharacters === null || filter.minCharacters === undefined ? '' : String(filter.minCharacters),
            placeholder: filter.placeholder || ''
        };
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

    // ---- Draft edits ---------------------------------------------------------------------------------------------

    /** Applies `{ filters?, recordContext? }` to the draft (never to the Widget config). */
    update(patch) {
        if ('filters' in patch) {
            this.filters = patch.filters;
        }
        if ('recordContext' in patch) {
            this.recordContext = patch.recordContext;
        }
        this.loadDefaultSupport();
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
        this.addDraftItem(filter);
    }

    handleAddSection() {
        this.addDraftItem({ type: 'section', label: 'Section', startCollapsed: false });
    }

    handleAddCurrencyPicker() {
        if (!this.isAddCurrencyPickerDisabled) {
            this.addDraftItem({ type: CURRENCY_PICKER_ITEM });
        }
    }

    handleCurrencyPickerLabel(event) {
        const label = event.detail.value || '';
        this.updateFilter(Number(event.target.dataset.index), { label: label.trim() ? label : null });
    }

    handleSectionLabel(event) {
        this.updateFilter(Number(event.target.dataset.index), { label: event.detail.value || '' });
    }

    handleSectionCollapsed(event) {
        this.updateFilter(Number(event.target.dataset.index), { startCollapsed: event.detail.checked ? true : null });
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
        const draftPatch = {};
        if (!RECORD_CONTEXT_OVERRIDE_TYPES.includes(type)) {
            // Record context can only feed Picklist, Lookup, and User filters.
            this.retargetRecordContext(draftPatch, filterId, null);
        }
        this.updateFilter(
            index,
            { ...reset, type, optionsSource: type === 'PICKLIST' ? 'FIELD_DESCRIBE' : null },
            draftPatch
        );
    }

    handleSelectionMode(event) {
        this.updateFilter(Number(event.target.dataset.index), { selectionMode: event.detail.value });
    }

    handleDisplay(event) {
        const display = event.detail.value;
        // Buttons display is single-select + All.
        this.updateFilter(
            Number(event.target.dataset.index),
            display === 'buttons' ? { display, selectionMode: 'single' } : { display: null }
        );
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

    handleUserMatchMode(event) {
        const matchMode = event.detail.value;
        this.updateFilter(Number(event.target.dataset.index), {
            matchMode: matchMode === 'usersAndTeam' ? matchMode : null
        });
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

    // BUCKET

    /** Combobox options of the Board-level Bucket fields, by id. */
    get bucketFieldOptions() {
        return (this.bucketFields || [])
            .filter((field) => cleanString(field.id))
            .map((field) => ({ label: cleanString(field.label) || field.id.trim(), value: field.id.trim() }));
    }

    handleBucketField(event) {
        this.updateFilter(Number(event.target.dataset.index), { bucketFieldId: event.detail.value || null });
    }

    // EMPTY_FILLED

    handleEmptyFilledDefault(event) {
        const operator = event.detail.value;
        this.updateFilter(Number(event.target.dataset.index), {
            defaultValue: EMPTY_FILLED_OPERATORS.includes(operator) ? { operator } : null
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

    updateFilter(index, patch, extraDraftPatch = {}) {
        const previous = this.filters[index];
        const next = applyPatch(previous, patch);
        const filters = this.filters.map((filter, position) => (position === index ? next : filter));
        const draftPatch = { ...extraDraftPatch, filters };
        if (previous.filterId !== next.filterId) {
            this.retargetRecordContext(draftPatch, previous.filterId, next.filterId || null);
        }
        this.update(draftPatch);
    }

    /** Keeps the Record context override pointing at a renamed filter (or clears it when removed / retyped). */
    retargetRecordContext(patch, fromId, toId) {
        const recordContext = isPlainObject(this.recordContext) ? this.recordContext : {};
        if (fromId && recordContext.overrideFilterId === fromId) {
            patch.recordContext = compactRecordContext({ ...recordContext, overrideFilterId: toId });
        }
    }
}