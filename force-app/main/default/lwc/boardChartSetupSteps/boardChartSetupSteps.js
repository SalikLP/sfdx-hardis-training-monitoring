import { LightningElement, api } from 'lwc';
import {
    BAR_SORT_OPTIONS,
    DATE_FIELD_TYPES,
    DATE_GRANULARITY_OPTIONS,
    MAX_CHART_MEASURES,
    ORIENTATION_OPTIONS,
    PICKLIST_FIELD_TYPES,
    ROLLUP_FUNCTIONS,
    chartMeasures,
    isPlainObject,
    parseNumber,
    resolveFieldDescribe
} from 'c/boardCpeUtils';
import { bucketFieldOptions, bucketIdOf, findBucketField } from 'c/boardBucketFields';
import {
    CHART_TYPE_OPTIONS,
    WATERFALL_DEFAULT_COLORS,
    chartTypeHasSetting,
    chartTypeIsSingleMeasure,
    maxCategoriesFor
} from 'c/boardChartUtils';
import { MAX_PANEL_CATEGORIES, PANEL_KEYS, hasPanelField } from 'c/boardChartPanels';

const STACK_MODE_OPTIONS = [
    { label: 'Stacked', value: 'stacked', illustration: 'stacked' },
    { label: 'Grouped', value: 'grouped', illustration: 'grouped' }
];
/** Chart types as picture tiles (`c-board-picture-tiles`), each drawn by its own illustration. */
const CHART_TYPE_TILES = CHART_TYPE_OPTIONS.map((option) => ({ ...option, illustration: option.value }));
const ORIENTATION_ILLUSTRATIONS = { vertical: 'orientationVertical', horizontal: 'orientationHorizontal' };
const ORIENTATION_TILES = ORIENTATION_OPTIONS.map((option) => ({
    ...option,
    illustration: ORIENTATION_ILLUSTRATIONS[option.value]
}));
const LEGEND_OPTIONS = [
    { label: 'Auto (only when stacked)', value: 'auto' },
    { label: 'Top', value: 'top' },
    { label: 'Bottom', value: 'bottom' },
    { label: 'Hidden', value: 'hidden' }
];
const LABEL_MODE_OPTIONS = [
    { label: 'Percentage', value: 'percent' },
    { label: 'Value', value: 'value' },
    { label: 'Value and percentage', value: 'both' },
    { label: 'None', value: 'none' }
];
const SORT_LABELS = new Map(BAR_SORT_OPTIONS.map((option) => [option.value, option.label]));
const CHRONOLOGICAL_SORTS = ['CHRONOLOGICAL_ASC', 'CHRONOLOGICAL_DESC'];
/**
 * Step content of the Chart widget's Setup dialog (`c/boardSetupDialog`): the inputs of one step (`step`: `data`,
 * `chartType`, `measures`, `grouping`, `display` or `filterBindings`, see `CHART_STEPS` in `c/boardSetupSteps`) over
 * the dialog's draft (`config`).
 *
 * - Data: the object and the Base filters (`c-board-setup-base-filters`).
 * - Chart type: the chart type (only its own settings are shown in later steps; the other types' settings are kept
 *   for a switch back) and the bar orientation.
 * - Measures: the Measures list (`c-board-cpe-measure-list`: up to 6, each with aggregate, field, label, number
 *   format and optional colour; several Measures or a Stack by field, never both).
 * - Grouping: Group by (+ date granularity for Date/DateTime fields), optional Stack by (series field), Bucket
 *   fields and Small multiples.
 * - Display: subtitle, sorting and overflow, legend and labels, and fixed colours.
 * - Filter bindings: `c-board-cpe-filter-bindings`.
 *
 * Discrete choices (chart type, orientation, series layout, overflow) are picture tiles (`c-board-picture-tiles`);
 * every setting carries field-level help. The step's intro and worked example come from its descriptor and are shown
 * by the dialog.
 *
 * Every edit fires `change` with `detail.patch` (merged into the draft by the dialog; null removes a key). Errors only
 * the server or the bindings editor knows (Formula build errors, a Filter binding switched to "Field path" without a
 * path) fire `steperrors` with `detail.step` and `detail.errors`.
 *
 * `context`: `boardBucketFields` (the Board's Bucket fields, usable by id), `builderContext` and `elementInfo`
 * (Filter widget discovery for the Filter bindings).
 */
export default class BoardChartSetupSteps extends LightningElement {
    @api step;

    _config = {};
    _context = {};

    /** The Setup dialog's draft config. */
    @api
    get config() {
        return this._config;
    }
    set config(value) {
        this._config = isPlainObject(value) ? value : {};
        this.resolveGroupByType();
    }

    @api
    get context() {
        return this._context;
    }
    set context(value) {
        this._context = isPlainObject(value) ? value : {};
    }

    /** `Schema.DisplayType` of the Group by leaf field, once known. */
    groupByType = null;

    chartTypeOptions = CHART_TYPE_TILES;
    granularityOptions = DATE_GRANULARITY_OPTIONS;
    stackModeOptions = STACK_MODE_OPTIONS;
    legendOptions = LEGEND_OPTIONS;
    orientationOptions = ORIENTATION_TILES;

    _typedKey = null;

    get isData() {
        return this.step === 'data';
    }

    get isChartType() {
        return this.step === 'chartType';
    }

    get isMeasures() {
        return this.step === 'measures';
    }

    get isGrouping() {
        return this.step === 'grouping';
    }

    get isDisplay() {
        return this.step === 'display';
    }

    get isFilterBindings() {
        return this.step === 'filterBindings';
    }

    /** Bucket fields of the Board's Filter widget, usable by id. */
    get boardBucketFields() {
        return Array.isArray(this._context.boardBucketFields) ? this._context.boardBucketFields : [];
    }

    get builderContext() {
        return this._context.builderContext || {};
    }

    get elementInfo() {
        return this._context.elementInfo || {};
    }

    update(patch) {
        this.dispatchEvent(new CustomEvent('change', { detail: { patch } }));
    }

    reportErrors(step, errors) {
        this.dispatchEvent(new CustomEvent('steperrors', { detail: { step, errors } }));
    }

    /** FormulaEval build errors of the Formula measures, checked on the server by the Measures list. */
    handleFormulaCheck(event) {
        event.stopPropagation();
        this.reportErrors('measures', event.detail.errors || []);
    }

    groupByKey(objectApiName, groupByField) {
        return objectApiName && groupByField ? `${objectApiName}::${groupByField}` : null;
    }

    /** Describes the saved Group by path (e.g. after reopening the editor) to decide which options apply. */
    resolveGroupByType() {
        const objectApiName = this.objectApiName;
        const groupByField = this.groupByField;
        const key = this.groupByKey(objectApiName, groupByField);
        if (key === this._typedKey) {
            return;
        }
        this._typedKey = key;
        this.groupByType = null;
        if (!key || bucketIdOf(groupByField) !== null) {
            return;
        }
        resolveFieldDescribe(objectApiName, groupByField)
            .then((field) => {
                if (this._typedKey === key) {
                    this.groupByType = field ? field.dataType : null;
                }
            })
            .catch(() => {
                // Unknown type: every option stays available and the server validates at runtime.
            });
    }

    get objectApiName() {
        return this.config.objectApiName || null;
    }

    /** The Panel field (Small multiples): a Cross-object measure maps a field of its source object to it too. */
    get panelField() {
        return this.config.panelField || null;
    }

    // ---- Data ----------------------------------------------------------------------------------------------------

    get objectPickerValue() {
        return this.objectApiName || '';
    }

    handleObject(event) {
        const value = event.detail.value;
        this.update({ objectApiName: value && String(value).trim() ? value : null });
    }

    get baseFilters() {
        return this.config.baseFilters || null;
    }

    handleBaseFilters(event) {
        event.stopPropagation();
        const baseFilters = event.detail.baseFilters || [];
        this.update({ baseFilters: baseFilters.length ? baseFilters : null });
    }

    // ---- Filter bindings -----------------------------------------------------------------------------------------

    handleBindingsChange(event) {
        event.stopPropagation();
        this.update({ filterBindings: event.detail.filterBindings || null });
    }

    handleBindingState(event) {
        event.stopPropagation();
        this.reportErrors(
            'filterBindings',
            (event.detail.errors || []).map((item) => item.errorString)
        );
    }

    // ---- Orientation ---------------------------------------------------------------------------------------------

    get showOrientation() {
        return chartTypeHasSetting(this.chartType, 'orientation');
    }

    get orientation() {
        return this.config.orientation || 'vertical';
    }

    handleOrientation(event) {
        this.update({ orientation: event.detail.value || null });
    }

    // ---- Chart type ----------------------------------------------------------------------------------------------

    get chartType() {
        return this.config.chartType || 'bar';
    }

    /** Only `chartType` changes: the other types' settings stay in the config, so switching back restores them. */
    handleChartType(event) {
        this.update({ chartType: event.detail.value });
    }

    /** Bar-only settings: stack mode and colour by category (orientation is in the shell). */
    get showBarSettings() {
        return chartTypeHasSetting(this.chartType, 'stackMode');
    }

    get showStackMode() {
        return this.hasStack && this.showBarSettings;
    }

    get showColorByCategory() {
        return !this.hasStack && chartTypeHasSetting(this.chartType, 'colorByCategory');
    }

    /** Pie, donut and polarArea: one Measure, no series field, always coloured by category. */
    get isSingleMeasureType() {
        return chartTypeIsSingleMeasure(this.chartType);
    }

    /** Stack by is hidden for one-Measure types, unless a leftover value needs clearing. */
    get showStackBy() {
        return !this.isSingleMeasureType || this.hasStack;
    }

    get showLabelMode() {
        return chartTypeHasSetting(this.chartType, 'labelMode');
    }

    get showDataLabelsSetting() {
        return !this.showLabelMode;
    }

    get labelModeOptions() {
        return LABEL_MODE_OPTIONS;
    }

    get labelMode() {
        return this.config.labelMode || 'percent';
    }

    handleLabelMode(event) {
        this.update({ labelMode: event.detail.value });
    }

    get showCentreTotal() {
        return chartTypeHasSetting(this.chartType, 'centreTotal');
    }

    get centreTotal() {
        return this.config.centreTotal === true;
    }

    handleCentreTotal(event) {
        this.update({ centreTotal: event.detail.checked ? true : null });
    }

    get showTotalSetting() {
        return chartTypeHasSetting(this.chartType, 'showTotal');
    }

    get showTotal() {
        return this.config.showTotal === true;
    }

    handleShowTotal(event) {
        this.update({ showTotal: event.detail.checked ? true : null });
    }

    get showWaterfallColors() {
        return chartTypeHasSetting(this.chartType, 'waterfallColors');
    }

    get waterfallIncreaseColor() {
        return this.config.waterfallIncreaseColor || WATERFALL_DEFAULT_COLORS.increase;
    }

    get waterfallDecreaseColor() {
        return this.config.waterfallDecreaseColor || WATERFALL_DEFAULT_COLORS.decrease;
    }

    get waterfallTotalColor() {
        return this.config.waterfallTotalColor || WATERFALL_DEFAULT_COLORS.total;
    }

    /** A colour equal to its default is not stored, so the default keeps following the code. */
    handleWaterfallColor(event) {
        const key = event.target.dataset.key;
        const value = String(event.detail.value || '').toLowerCase();
        const fallback = WATERFALL_DEFAULT_COLORS[event.target.dataset.kind];
        this.update({ [key]: !value || value === fallback ? null : value });
    }

    get showPointsSetting() {
        return chartTypeHasSetting(this.chartType, 'showPoints');
    }

    get showPoints() {
        return this.config.showPoints !== false;
    }

    handleShowPoints(event) {
        this.update({ showPoints: event.detail.checked ? null : false });
    }

    /** Max categories of the chart type; Small multiples show at most 50 per Panel. */
    get maxCategories() {
        const max = maxCategoriesFor(this.chartType);
        return String(hasPanelField(this.config) ? Math.min(max, MAX_PANEL_CATEGORIES) : max);
    }

    // ---- Small multiples -----------------------------------------------------------------------------------------

    /** Each Measure's label for the panel sort: the Admin's label, else e.g. `Record Count` or `SUM of Amount`. */
    get measureLabels() {
        return this.measures.map((measure) => {
            if (measure.label) {
                return measure.label;
            }
            const fn = measure.aggregateFunction || 'COUNT';
            return fn === 'COUNT' ? 'Record Count' : `${fn} of ${measure.valueFieldApiName || '?'}`;
        });
    }

    handlePanelSettings(event) {
        this.update(event.detail.patch);
    }

    get maxBarsLabel() {
        return `Maximum ${this.categoryNoun}`;
    }

    /** What a category is drawn as: `bars` on a bar chart, else `categories`. */
    get categoryNoun() {
        return this.chartType === 'bar' ? 'bars' : 'categories';
    }

    // ---- Dimensions ----------------------------------------------------------------------------------------------

    get groupByField() {
        return this.config.groupByField || '';
    }

    /** The Group by field picker shows nothing while a Bucket field is the Group by. */
    get groupByPickerValue() {
        return this.groupByIsBucket ? '' : this.groupByField;
    }

    get stackByPickerValue() {
        return bucketIdOf(this.stackByField) !== null ? '' : this.stackByField;
    }

    get groupByIsBucket() {
        return bucketIdOf(this.groupByField) !== null;
    }

    get isDateGroup() {
        return DATE_FIELD_TYPES.includes(this.groupByType);
    }

    get showGranularity() {
        return Boolean(this.groupByField) && (this.isDateGroup || Boolean(this.config.dateGranularity));
    }

    get dateGranularity() {
        return this.config.dateGranularity || 'DAY';
    }

    get stackByField() {
        return this.config.stackByField || '';
    }

    get hasStack() {
        return Boolean(this.config.stackByField);
    }

    get stackMode() {
        return this.config.stackMode === 'grouped' ? 'grouped' : 'stacked';
    }

    get maxSeries() {
        return this.config.maxSeries ?? '';
    }

    get includeNullBucket() {
        return this.config.includeNullBucket !== false;
    }

    handleGroupBy(event) {
        const groupByField = event.detail.value || null;
        const dataType = event.detail.field ? event.detail.field.dataType : null;
        this._typedKey = this.groupByKey(this.objectApiName, groupByField);
        this.groupByType = groupByField ? dataType : null;
        const patch = { groupByField };
        const isDate = DATE_FIELD_TYPES.includes(this.groupByType);
        if (!isDate) {
            patch.dateGranularity = null;
        } else if (this.config.overflowMode === 'OTHER') {
            patch.overflowMode = 'TRUNCATE';
        }
        const sortBy = this.config.sortBy;
        if (
            (CHRONOLOGICAL_SORTS.includes(sortBy) && !isDate) ||
            (sortBy === 'PICKLIST_ORDER' && !PICKLIST_FIELD_TYPES.includes(this.groupByType))
        ) {
            patch.sortBy = null;
        }
        this.update(patch);
    }

    // ---- Bucket fields -------------------------------------------------------------------------------------------

    get bucketFields() {
        return Array.isArray(this.config.bucketFields) ? this.config.bucketFields : [];
    }

    /** The Widget's own Bucket fields or the Board's (its Filter widget's), so the Bucket field pickers show. */
    get hasBucketFields() {
        return this.bucketFields.length > 0 || this.boardBucketFields.length > 0;
    }

    /** The Widget's own Bucket fields, then the Board's not shadowed by an own one with the same id. */
    get bucketOptions() {
        const own = bucketFieldOptions(this.bucketFields);
        const ownValues = new Set(own.map((option) => option.value));
        const board = bucketFieldOptions(this.boardBucketFields)
            .filter((option) => !ownValues.has(option.value))
            .map((option) => ({ ...option, label: `${option.label} (Board)` }));
        return [{ label: 'None (use the field above)', value: '' }, ...own, ...board];
    }

    get groupByBucket() {
        return this.groupByIsBucket ? this.groupByField : '';
    }

    get stackByBucket() {
        return bucketIdOf(this.stackByField) !== null ? this.stackByField : '';
    }

    /** Writes the Bucket fields; a Group by, Stack by or Panel field on a removed Bucket field is cleared. */
    handleBucketFields(event) {
        const bucketFields = event.detail.value;
        const patch = { bucketFields };
        const isRemoved = (reference) => {
            const id = bucketIdOf(reference);
            return id !== null && !findBucketField(bucketFields, id) && !findBucketField(this.boardBucketFields, id);
        };
        if (isRemoved(this.groupByField)) {
            patch.groupByField = null;
        }
        if (isRemoved(this.stackByField)) {
            Object.assign(patch, { stackByField: null, stackMode: null, maxSeries: null });
        }
        if (isRemoved(this.config.panelField)) {
            Object.assign(patch, Object.fromEntries(PANEL_KEYS.map((key) => [key, null])));
        }
        this.update(patch);
    }

    handleGroupByBucket(event) {
        const groupByField = event.detail.value || null;
        this._typedKey = this.groupByKey(this.objectApiName, groupByField);
        this.groupByType = null;
        const patch = { groupByField, dateGranularity: null };
        if (CHRONOLOGICAL_SORTS.includes(this.config.sortBy)) {
            patch.sortBy = null;
        }
        this.update(patch);
    }

    handleStackByBucket(event) {
        this.handleStackBy(event);
    }

    handleGranularity(event) {
        this.update({ dateGranularity: event.detail.value });
    }

    handleStackBy(event) {
        const stackByField = event.detail.value || null;
        const patch = { stackByField };
        if (!stackByField) {
            patch.stackMode = null;
            patch.maxSeries = null;
        }
        this.update(patch);
    }

    handleStackMode(event) {
        this.update({ stackMode: event.detail.value });
    }

    handleMaxSeries(event) {
        this.update({ maxSeries: parseNumber(event.detail.value) });
    }

    get colorByCategory() {
        return this.config.colorByCategory === true;
    }

    handleColorByCategory(event) {
        this.update({ colorByCategory: event.detail.checked ? true : null });
    }

    handleIncludeNull(event) {
        this.update({ includeNullBucket: event.detail.checked ? null : false });
    }

    // ---- Measures ------------------------------------------------------------------------------------------------

    get measures() {
        return chartMeasures(this.config);
    }

    /** Several Measures disable the Stack by field: a chart shows several Measures or one split by series. */
    get stackByDisabled() {
        return this.measures.length > 1 && !this.hasStack;
    }

    get maxMeasures() {
        return this.isSingleMeasureType ? 1 : MAX_CHART_MEASURES;
    }

    get addMeasureBlockedReason() {
        if (this.isSingleMeasureType) {
            return 'A pie, donut, polar area or waterfall chart shows exactly one Measure.';
        }
        return this.hasStack ? 'Remove the Stack by field to show several Measures side by side.' : '';
    }

    /** Percent of category shares a category between its series or between several Measures. */
    get canShareCategory() {
        return !this.isSingleMeasureType && (this.hasStack || this.measures.length > 1);
    }

    /** Writes the Measures list; turning a Measure non-additive turns an "Other" bar into truncation. */
    updateMeasures(measures) {
        const patch = { measures };
        const additive = measures.every((measure) => ROLLUP_FUNCTIONS.includes(measure.aggregateFunction || 'COUNT'));
        if (!additive && this.config.overflowMode === 'OTHER') {
            patch.overflowMode = 'TRUNCATE';
        }
        this.update(patch);
    }

    handleMeasuresChange(event) {
        this.updateMeasures(event.detail.measures);
    }

    // ---- Display -------------------------------------------------------------------------------------------------

    get sortOptions() {
        const values = ['VALUE_DESC', 'VALUE_ASC', 'LABEL_ASC', 'LABEL_DESC'];
        // A Bucket field's "picklist order" is its rule order.
        if (PICKLIST_FIELD_TYPES.includes(this.groupByType) || this.groupByIsBucket) {
            values.push('PICKLIST_ORDER');
        }
        if (this.showGranularity) {
            values.push(...CHRONOLOGICAL_SORTS);
        }
        const current = this.config.sortBy;
        if (current && !values.includes(current)) {
            values.push(current);
        }
        const fallback = this.showGranularity ? 'chronological, oldest first' : 'value, high to low';
        return [
            { label: `Default (${fallback})`, value: '' },
            ...values.map((value) => ({ label: SORT_LABELS.get(value) || value, value }))
        ];
    }

    get sortBy() {
        return this.config.sortBy || '';
    }

    get maxBars() {
        return this.config.maxBars ?? '';
    }

    /** The first Measure that can't be summed into "Other" (not COUNT or SUM), or null. */
    get nonAdditiveFunction() {
        const fn = this.measures
            .map((measure) => measure.aggregateFunction || 'COUNT')
            .find((aggregateFunction) => !ROLLUP_FUNCTIONS.includes(aggregateFunction));
        return fn || null;
    }

    get overflowOptions() {
        const options = [{ label: 'Hide extra bars', value: 'TRUNCATE', illustration: 'overflowTruncate' }];
        if (!this.nonAdditiveFunction && !this.showGranularity) {
            options.push({ label: 'Combine into "Other"', value: 'OTHER', illustration: 'overflowOther' });
        }
        return options;
    }

    get overflowMode() {
        return this.config.overflowMode === 'OTHER' ? 'OTHER' : 'TRUNCATE';
    }

    get overflowHelp() {
        if (this.showGranularity) {
            return 'A date axis hides the bars beyond the maximum (earliest first when ascending, latest first when descending); there is no "Other" bar.';
        }
        const fn = this.nonAdditiveFunction;
        return fn
            ? `An "Other" bar is only available for COUNT and SUM Measures; ${fn} hides extra bars.`
            : 'Bars beyond the maximum are hidden or summed into one "Other" bar.';
    }

    get legendPosition() {
        return this.config.legendPosition || 'auto';
    }

    get showDataLabels() {
        return this.config.showDataLabels === true;
    }

    get subtitle() {
        return this.config.subtitle || '';
    }

    handleSortBy(event) {
        this.update({ sortBy: event.detail.value || null });
    }

    handleMaxBars(event) {
        this.update({ maxBars: parseNumber(event.detail.value) });
    }

    handleOverflow(event) {
        this.update({ overflowMode: event.detail.value });
    }

    handleLegend(event) {
        this.update({ legendPosition: event.detail.value });
    }

    handleDataLabels(event) {
        this.update({ showDataLabels: event.detail.checked });
    }

    // ---- Fixed colours --------------------------------------------------------------------------------------------

    get fixedColours() {
        return Array.isArray(this.config.fixedColours) ? this.config.fixedColours : [];
    }

    handleFixedColours(event) {
        const fixedColours = event.detail.value;
        this.update({ fixedColours: fixedColours && fixedColours.length ? fixedColours : null });
    }

    handleSubtitle(event) {
        const value = event.detail.value;
        this.update({ subtitle: value && value.trim() ? value : null });
    }
}