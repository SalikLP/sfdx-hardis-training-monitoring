import { LightningElement, api } from 'lwc';
import { SetupStepContent } from 'c/boardSetupStepContent';
import { metricMeasures } from 'c/boardConfigUtils';
import { DISPLAY_GAUGE, DISPLAY_NUMBER, DISPLAY_OPTIONS, isGaugeDisplay } from 'c/boardMetricGauge';
import {
    MAX_METRIC_MEASURES,
    THRESHOLD_OPERATOR_OPTIONS,
    THRESHOLD_VARIANT_OPTIONS,
    defaultNotationFor,
    dragRowClass,
    dropRowDrag,
    isPlainObject,
    moveItem,
    NO_DRAG,
    overRowDrag,
    parseNumber,
    startRowDrag,
    remapMeasureRefs
} from 'c/boardCpeUtils';

/** Number vs Gauge as picture tiles (`c-board-picture-tiles`). */
const DISPLAY_ILLUSTRATIONS = { [DISPLAY_NUMBER]: 'displayNumber', [DISPLAY_GAUGE]: 'displayGauge' };
const DISPLAY_TILES = DISPLAY_OPTIONS.map((option) => ({
    ...option,
    illustration: DISPLAY_ILLUSTRATIONS[option.value]
}));

// Short labels for the compact threshold row, so the chosen values aren't truncated. The option values (the config
// contract) come from the shared options.
const OPERATOR_SYMBOLS = { gt: '>', gte: '≥', lt: '<', lte: '≤' };
const VARIANT_LABELS = { success: 'Success', warning: 'Warning', error: 'Error' };
const THRESHOLD_OPERATORS = THRESHOLD_OPERATOR_OPTIONS.map(({ value }) => ({ label: OPERATOR_SYMBOLS[value], value }));
const THRESHOLD_VARIANTS = THRESHOLD_VARIANT_OPTIONS.map(({ value }) => ({ label: VARIANT_LABELS[value], value }));

/**
 * Step content of the Metric widget's Setup dialog (`c/boardSetupDialog`): the inputs of one step (`step`: `data`,
 * `measures`, `display`, `thresholds` or `filterBindings`, see `METRIC_STEPS` in `c/boardSetupSteps`) over the
 * dialog's draft (`config`).
 *
 * - Data: the object and the Base filters (`c-board-setup-base-filters`).
 * - Measures: the Measures list (`c-board-cpe-measure-list`: up to 6, exactly one visible, the others Hidden; each
 *   with aggregate, field, label, number format, Measure condition, Formula or Cross-object measure).
 * - Display: number vs Gauge as picture tiles, the Gauge's minimum, maximum and target (static or a Hidden Measure),
 *   and the subtitle.
 * - Thresholds: ordered rules (drag or Move up / down to reorder); on a Gauge they are its bands.
 * - Filter bindings: `c-board-cpe-filter-bindings`.
 *
 * Every edit fires `change` with `detail.patch` (merged into the draft by the dialog; null removes a key). Errors only
 * the server or the bindings editor knows (Formula build errors, a Filter binding switched to "Field path" without a
 * path) fire `steperrors` with `detail.step` and `detail.errors`.
 *
 * `context`: `builderContext` and `elementInfo` (Filter widget discovery for the Filter bindings).
 */
export default class BoardMetricSetupSteps extends SetupStepContent(LightningElement) {
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
    }

    @api
    get context() {
        return this._context;
    }
    set context(value) {
        this._context = isPlainObject(value) ? value : {};
    }

    /** Widget default notation, shown by the format editor. */
    defaultNotation = defaultNotationFor('metric');
    maxMeasures = MAX_METRIC_MEASURES;
    displayOptions = DISPLAY_TILES;
    thresholdOperatorOptions = THRESHOLD_OPERATORS;
    thresholdVariantOptions = THRESHOLD_VARIANTS;
    /** Drag-to-reorder state of the threshold rules (see the drag helpers in c/boardCpeUtils). */
    drag = NO_DRAG;

    get isData() {
        return this.step === 'data';
    }

    get isMeasures() {
        return this.step === 'measures';
    }

    get isDisplay() {
        return this.step === 'display';
    }

    get isThresholds() {
        return this.step === 'thresholds';
    }

    get isFilterBindings() {
        return this.step === 'filterBindings';
    }

    // ---- Measures ------------------------------------------------------------------------------------------------

    /** The Measures list; a single-aggregate config shows as its one visible Measure. */
    get measures() {
        return metricMeasures(this.config);
    }

    /** Writes the Measures list; a single-aggregate config's keys move into it on the first Measure edit. */
    /** A reorder or removal (`mapping`) keeps Formula slots and the Gauge's Measures on the same Measures. */
    handleMeasuresChange(event) {
        const { measures, mapping } = event.detail;
        this.update({
            measures,
            ...(mapping ? remapMeasureRefs(this.config, measures, mapping) : {}),
            aggregateFunction: null,
            valueFieldApiName: null,
            format: null
        });
    }

    /** FormulaEval build errors of the Formula measures, checked on the server by the Measures list. */
    handleFormulaCheck(event) {
        event.stopPropagation();
        this.reportErrors('measures', event.detail.errors || []);
    }

    // ---- Display (number | Gauge) --------------------------------------------------------------------------------

    get display() {
        return isGaugeDisplay(this.config) ? DISPLAY_GAUGE : DISPLAY_NUMBER;
    }

    get isGauge() {
        return isGaugeDisplay(this.config);
    }

    get gauge() {
        return isPlainObject(this.config.gauge) ? this.config.gauge : {};
    }

    /** Hidden Measures a Gauge can read, labelled by their position in the list. */
    get hiddenMeasureOptions() {
        return this.measures
            .map((measure, index) => ({ measure, index }))
            .filter(({ measure }) => measure && measure.hidden === true)
            .map(({ measure, index }) => ({
                label: `Measure ${index + 1}: ${measure.label || measure.aggregateFunction || 'COUNT'}`,
                value: String(index)
            }));
    }

    get edgeSourceOptions() {
        return [{ label: 'Static number', value: 'static' }, ...this.hiddenMeasureOptions];
    }

    get targetOptions() {
        return [{ label: 'No target', value: 'none' }, ...this.hiddenMeasureOptions];
    }

    get minSource() {
        return this.measureSource(this.gauge.minMeasure, 'static');
    }

    get maxSource() {
        return this.measureSource(this.gauge.maxMeasure, 'static');
    }

    get targetSource() {
        return this.measureSource(this.gauge.targetMeasure, 'none');
    }

    measureSource(index, none) {
        return index === null || index === undefined ? none : String(index);
    }

    get minStatic() {
        return this.minSource === 'static';
    }

    get maxStatic() {
        return this.maxSource === 'static';
    }

    get minValue() {
        return this.gauge.min === null || this.gauge.min === undefined ? '' : String(this.gauge.min);
    }

    get maxValue() {
        return this.gauge.max === null || this.gauge.max === undefined ? '' : String(this.gauge.max);
    }

    get bandsPercentOfMax() {
        return this.gauge.bandsPercentOfMax === true;
    }

    handleDisplay(event) {
        this.update({ display: event.detail.value === DISPLAY_GAUGE ? DISPLAY_GAUGE : null });
    }

    /** Writes the Gauge settings, dropping unset keys (and the whole object when empty). */
    updateGauge(patch) {
        const next = { ...this.gauge, ...patch };
        Object.keys(next).forEach((key) => {
            if (next[key] === null || next[key] === undefined || next[key] === false) {
                delete next[key];
            }
        });
        this.update({ gauge: Object.keys(next).length ? next : null });
    }

    handleMinSource(event) {
        const value = event.detail.value;
        this.updateGauge(value === 'static' ? { minMeasure: null } : { minMeasure: Number(value), min: null });
    }

    handleMaxSource(event) {
        const value = event.detail.value;
        this.updateGauge(value === 'static' ? { maxMeasure: null } : { maxMeasure: Number(value), max: null });
    }

    handleMinValue(event) {
        this.updateGauge({ min: parseNumber(event.detail.value) });
    }

    handleMaxValue(event) {
        this.updateGauge({ max: parseNumber(event.detail.value) });
    }

    handleTargetSource(event) {
        const value = event.detail.value;
        this.updateGauge({ targetMeasure: value === 'none' ? null : Number(value) });
    }

    handleBandsPercent(event) {
        this.updateGauge({ bandsPercentOfMax: event.detail.checked });
    }

    // ---- Thresholds ----------------------------------------------------------------------------------------------

    get thresholds() {
        return Array.isArray(this.config.thresholds) ? this.config.thresholds : [];
    }

    get hasThresholds() {
        return this.thresholds.length > 0;
    }

    get thresholdRows() {
        const last = this.thresholds.length - 1;
        return this.thresholds.map((rule, index) => ({
            key: `threshold-${index}`,
            index,
            operatorLabel: `Rule ${index + 1}: when value is`,
            valueLabel: `Rule ${index + 1}: value`,
            variantLabel: `Rule ${index + 1}: status`,
            moveUpLabel: `Move rule ${index + 1} up`,
            moveDownLabel: `Move rule ${index + 1} down`,
            removeLabel: `Remove rule ${index + 1}`,
            operator: rule && rule.operator ? rule.operator : '',
            value: rule && rule.value !== null && rule.value !== undefined ? String(rule.value) : '',
            variant: rule && rule.variant ? rule.variant : '',
            isFirst: index === 0,
            isLast: index === last,
            rowClass: `c-metric-threshold slds-p-vertical_xx-small${dragRowClass(this.drag, index)}`
        }));
    }

    handleThresholdDragStart(event) {
        this.drag = startRowDrag(event);
    }

    handleThresholdDragOver(event) {
        this.drag = overRowDrag(event, this.drag);
    }

    handleThresholdDrop(event) {
        const move = dropRowDrag(event, this.drag);
        this.drag = NO_DRAG;
        if (move) {
            this.setThresholds(moveItem(this.thresholds, move.index, move.offset));
        }
    }

    handleThresholdDragEnd() {
        this.drag = NO_DRAG;
    }

    handleAddThreshold() {
        this.setThresholds([...this.thresholds, { operator: 'gte', value: null, variant: 'success' }]);
    }

    handleRemoveThreshold(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.setThresholds(this.thresholds.filter((rule, position) => position !== index));
    }

    handleMoveThresholdUp(event) {
        this.setThresholds(moveItem(this.thresholds, Number(event.currentTarget.dataset.index), -1));
    }

    handleMoveThresholdDown(event) {
        this.setThresholds(moveItem(this.thresholds, Number(event.currentTarget.dataset.index), 1));
    }

    handleThresholdOperator(event) {
        this.updateThreshold(event, { operator: event.detail.value });
    }

    handleThresholdValue(event) {
        this.updateThreshold(event, { value: parseNumber(event.detail.value) });
    }

    handleThresholdVariant(event) {
        this.updateThreshold(event, { variant: event.detail.value });
    }

    updateThreshold(event, patch) {
        const index = Number(event.target.dataset.index);
        this.setThresholds(
            this.thresholds.map((rule, position) => (position === index ? { ...rule, ...patch } : rule))
        );
    }

    setThresholds(thresholds) {
        this.update({ thresholds: thresholds.length ? thresholds : null });
    }

    // ---- Filter bindings -----------------------------------------------------------------------------------------
}