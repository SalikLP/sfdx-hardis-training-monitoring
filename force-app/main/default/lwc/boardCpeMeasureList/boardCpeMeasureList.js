import { LightningElement, api } from 'lwc';
import checkFormulas from '@salesforce/apex/BoardFormulaMeasures.checkFormulas';
import {
    MEASURE_AGGREGATE_OPTIONS,
    NO_DRAG,
    PER_RECORD_INNER_OPTIONS,
    ROLLUP_FUNCTIONS,
    SHOW_AS_OPTIONS,
    applyPatch,
    dragRowClass,
    dropRowDrag,
    isFormulaMeasure,
    measureTitle,
    moveItem,
    overRowDrag,
    startRowDrag,
    containInnerChanges
} from 'c/boardCpeUtils';
import {
    MEASURE_AXIS_OPTIONS,
    MEASURE_RENDER_OPTIONS,
    chartTypeHasSetting,
    normalizeMeasureDisplay
} from 'c/boardChartUtils';

/** `mapping[oldIndex]` = new index of every item after `moveItem(items, index, offset)`. */
function movedIndexes(length, index, offset) {
    const order = moveItem(
        Array.from({ length }, (unused, position) => position),
        index,
        offset
    );
    return Array.from({ length }, (unused, oldIndex) => order.indexOf(oldIndex));
}

/** Picture tile illustration (`c-board-picture-tiles`) of each Show as and Draw as choice. */
const SHOW_AS_ILLUSTRATIONS = {
    value: 'showAsValue',
    percentOfTotal: 'showAsPercentOfTotal',
    percentOfCategory: 'showAsPercentOfCategory'
};
const SHOW_AS_TILES = SHOW_AS_OPTIONS.map((option) => ({
    ...option,
    illustration: SHOW_AS_ILLUSTRATIONS[option.value]
}));
const RENDER_ILLUSTRATIONS = { bar: 'renderBar', line: 'renderLine', referenceLine: 'renderReferenceLine' };
const RENDER_TILES = MEASURE_RENDER_OPTIONS.map((option) => ({
    ...option,
    illustration: RENDER_ILLUSTRATIONS[option.value]
}));

const SHOW_AS_HELP =
    "Percent of total: each category's share of the grand total. Percent of category: each series' share within its category. A percentage defaults to a percent format; set a number format below to override it.";
const SHOW_AS_REFERENCE_LINE_HELP = 'A Reference line shows the overall value, not a percentage.';
const RENDER_HELP =
    "A Reference line draws the Measure's value as one line across the chart, e.g. a target or an average.";
const RENDER_SHARE_HELP = "A Share of total can't be drawn as a Reference line.";

/** `tiles` with the options in `unavailable` disabled. */
function withDisabled(tiles, unavailable) {
    return tiles.map((tile) => (unavailable.includes(tile.value) ? { ...tile, disabled: true } : tile));
}

function formulaText(measure) {
    return typeof measure.formula === 'string' ? measure.formula.trim() : '';
}

/**
 * Measures list editor shared by the Chart and Metric Config editors: up to `maxMeasures` Measures, each with
 * aggregate, value field, label, number format and an optional Measure condition (`condition`, edited with the shared
 * condition editor), plus an optional colour (`showColor`, Chart widget) and hidden flag (`showHidden`), and a Share
 * of total "Show as" choice for COUNT and SUM Measures (`showShareOfTotal`, Chart widget only; never on the Metric
 * widget). A Formula measure (`FORMULA`) takes formula text over the other Measures by slot (Measure 1 is A);
 * reordering or removing Measures keeps its references on the same Measures. Rows reorder by arrows or drag. Fires a
 * non-bubbling `change` event with `detail.measures` (the full edited list; plus `detail.mapping` after a reorder or
 * a removal, see `updateMeasures`), and `formulacheck` with `detail.errors`
 * (the server's FormulaEval build errors, `Measure 2 (B) formula: …`) whenever they change. An Average per record
 * (`AVG_PER`) Measure adds its per-record lookup `perField` and how each record's value is taken, `inner`.
 */
export default class BoardCpeMeasureList extends LightningElement {
    connectedCallback() {
        containInnerChanges(this);
    }

    @api objectApiName;
    @api maxMeasures = 6;
    /** Why no Measure can be added right now (e.g. a Stack by field is set); empty when adding is allowed. */
    @api addBlockedReason = '';
    @api showColor = false;
    /** A Hidden checkbox per Measure (fetched for calculations such as a Formula measure, not shown). */
    @api showHidden = false;
    /** Metric widget: exactly one Measure is visible, so added Measures start hidden. */
    @api singleVisible = false;
    /** MIN and MAX may also aggregate date and time fields (Metric widget). */
    @api dateMinMax = false;
    /** Chart widget: a "Show as" (Share of total) choice per COUNT or SUM Measure. */
    @api showShareOfTotal = false;
    /** Percent of category is offered: the chart has a series (Stack by) field or several Measures. */
    @api canShareCategory = false;
    /** Notation the Widget uses when a Measure format leaves it unset, shown by the format editor. */
    @api defaultNotation = 'standard';
    /** Chart widget: its chart type; bar and line charts show Draw as and Value axis per Measure. */
    @api chartType = '';
    /** Chart widget: a Cross-object measure maps a field of its source object to the category. */
    @api showCategoryMapping = false;
    /** The Widget's Panel field (Small multiples): a Cross-object measure maps a field to it too. */
    @api panelField;

    aggregateOptions = MEASURE_AGGREGATE_OPTIONS;
    perRecordInnerOptions = PER_RECORD_INNER_OPTIONS;
    measureAxisOptions = MEASURE_AXIS_OPTIONS;
    _measures = [{ aggregateFunction: 'COUNT' }];
    /** Server build message per formula text (null: it builds). */
    _formulaMessages = new Map();
    _formulaErrorsKey = '[]';
    /** Drag-to-reorder state of the Measures list (see the drag helpers in c/boardCpeUtils). */
    drag = NO_DRAG;

    @api
    get measures() {
        return this._measures;
    }
    set measures(value) {
        this._measures = Array.isArray(value) && value.length ? value : [{ aggregateFunction: 'COUNT' }];
        this.checkFormulas();
    }

    /** Builds new formula texts on the server (FormulaEval), then reports the current Measures' build errors. */
    async checkFormulas() {
        await Promise.resolve();
        const texts = [...new Set(this._measures.filter(isFormulaMeasure).map(formulaText))].filter(
            (text) => text && !this._formulaMessages.has(text)
        );
        if (texts.length) {
            let messages = [];
            try {
                messages = await checkFormulas({ formulas: texts });
            } catch (unavailable) {
                // Not checkable here; the Widget still reports a bad formula when it runs.
            }
            texts.forEach((text, index) =>
                this._formulaMessages.set(text, (Array.isArray(messages) && messages[index]) || null)
            );
        }
        const errors = this._measures
            .map((measure, index) => {
                const message = isFormulaMeasure(measure) ? this.formulaMessage(measure) : null;
                return message ? `${measureTitle(index)} formula: ${message}` : null;
            })
            .filter(Boolean);
        const key = JSON.stringify(errors);
        if (key !== this._formulaErrorsKey) {
            this._formulaErrorsKey = key;
            // Re-render the inline messages.
            this._measures = [...this._measures];
            this.dispatchEvent(new CustomEvent('formulacheck', { detail: { errors } }));
        }
    }

    formulaMessage(measure) {
        return this._formulaMessages.get(formulaText(measure)) || null;
    }

    get canAddMeasure() {
        return this._measures.length < this.maxMeasures && !this.addBlockedReason;
    }

    get addMeasureDisabled() {
        return !this.canAddMeasure;
    }

    get addMeasureHelp() {
        if (this.addBlockedReason) {
            return this.addBlockedReason;
        }
        if (this._measures.length >= this.maxMeasures) {
            return `At most ${this.maxMeasures} Measures.`;
        }
        return '';
    }

    valueCapability(aggregateFunction) {
        if (aggregateFunction === 'COUNT_DISTINCT') {
            return '';
        }
        return this.dateMinMax && (aggregateFunction === 'MIN' || aggregateFunction === 'MAX')
            ? 'numeric|date'
            : 'numeric';
    }

    get measureRows() {
        const measures = this._measures;
        const last = measures.length - 1;
        return measures.map((measure, index) => {
            const aggregateFunction = measure.aggregateFunction || 'COUNT';
            const isFormula = isFormulaMeasure(measure);
            const showAs = measure.showAs || 'value';
            const display = this.measureDisplayRow(measure);
            const isReferenceLine = display.showDisplay && display.render === 'referenceLine';
            return {
                key: `measure-${index}`,
                index,
                title: measureTitle(index),
                aggregateFunction,
                isFormula,
                formula: isFormula ? formulaText(measure) : '',
                formulaError: isFormula ? this.formulaMessage(measure) : null,
                isCurrency: isFormula && measure.isCurrency === true,
                showValueField: aggregateFunction !== 'COUNT' && !isFormula,
                showPerRecord: aggregateFunction === 'AVG_PER',
                perField: measure.perField || '',
                inner: measure.inner || 'SUM',
                valueCapability: this.valueCapability(aggregateFunction),
                valueFieldApiName: measure.valueFieldApiName || '',
                label: measure.label || '',
                colour: measure.colour || '',
                hidden: measure.hidden === true,
                format: measure.format || null,
                condition: measure.condition || undefined,
                conditionIdPrefix: `m${index + 1}c`,
                showShareOfTotal: this.showShareOfTotal && ROLLUP_FUNCTIONS.includes(aggregateFunction),
                showAs,
                showAsOptions: withDisabled(
                    SHOW_AS_TILES.filter(
                        (option) =>
                            option.value !== 'percentOfCategory' ||
                            this.canShareCategory ||
                            showAs === 'percentOfCategory'
                    ),
                    isReferenceLine ? ['percentOfTotal', 'percentOfCategory'] : []
                ),
                showAsHelp: isReferenceLine ? `${SHOW_AS_HELP} ${SHOW_AS_REFERENCE_LINE_HELP}` : SHOW_AS_HELP,
                ...display,
                // A Share of total and a Reference line exclude each other (a share of the whole scope is always 100%).
                renderOptions: withDisabled(RENDER_TILES, showAs !== 'value' ? ['referenceLine'] : []),
                renderHelp: showAs !== 'value' ? `${RENDER_HELP} ${RENDER_SHARE_HELP}` : RENDER_HELP,
                // Cross-object measure: its value field and condition are on its own source object.
                measure,
                showCrossObject: !isFormula,
                measureObjectApiName: (!isFormula && measure.sourceObject) || this.objectApiName,
                isFirst: index === 0,
                isLast: index === last,
                isOnly: measures.length === 1,
                rowClass: `c-measure slds-p-vertical_x-small${dragRowClass(this.drag, index)}`
            };
        });
    }

    /**
     * Fires `change` with the new `measures`, plus `mapping` (old position → new position, -1 when removed) when the
     * list was reordered or a Measure removed: the owner remaps every position-based Measure reference with it
     * (`remapMeasureRefs` in `c/boardCpeUtils`).
     */
    updateMeasures(measures, mapping = null) {
        this.dispatchEvent(new CustomEvent('change', { detail: mapping ? { measures, mapping } : { measures } }));
    }

    renderedCallback() {
        // A native textarea's text is a DOM property, not a template attribute; leave the one being typed in alone.
        this.template.querySelectorAll('textarea.c-measure-formula').forEach((textarea) => {
            const formula = textarea.dataset.formula || '';
            if (textarea.value !== formula && textarea !== this.template.activeElement) {
                textarea.value = formula;
            }
        });
    }

    updateMeasure(event, patch) {
        const index = Number(event.target.dataset.index);
        this.updateMeasures(
            this._measures.map((measure, position) => (position === index ? applyPatch(measure, patch) : measure))
        );
    }

    handleAddMeasure() {
        if (this.canAddMeasure) {
            const measure = this.singleVisible
                ? { aggregateFunction: 'COUNT', hidden: true }
                : { aggregateFunction: 'COUNT' };
            this.updateMeasures([...this._measures, measure]);
        }
    }

    handleRemoveMeasure(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.updateMeasures(
            this._measures.filter((measure, position) => position !== index),
            this._measures.map((measure, oldIndex) => (oldIndex === index ? -1 : oldIndex - (oldIndex > index ? 1 : 0)))
        );
    }

    /** Moves a Measure; the owner keeps every reference on the same Measures (`mapping`). */
    moveMeasure(index, offset) {
        this.updateMeasures(
            moveItem(this._measures, index, offset),
            movedIndexes(this._measures.length, index, offset)
        );
    }

    handleMeasureUp(event) {
        this.moveMeasure(Number(event.currentTarget.dataset.index), -1);
    }

    handleMeasureDown(event) {
        this.moveMeasure(Number(event.currentTarget.dataset.index), 1);
    }

    handleMeasureDragStart(event) {
        this.drag = startRowDrag(event);
    }

    handleMeasureDragOver(event) {
        this.drag = overRowDrag(event, this.drag);
    }

    handleMeasureDrop(event) {
        const move = dropRowDrag(event, this.drag);
        this.drag = NO_DRAG;
        if (move) {
            this.moveMeasure(move.index, move.offset);
        }
    }

    handleMeasureDragEnd() {
        this.drag = NO_DRAG;
    }

    handleMeasureAggregate(event) {
        const aggregateFunction = event.detail.value;
        const patch = { aggregateFunction };
        if (aggregateFunction === 'COUNT' || aggregateFunction === 'FORMULA') {
            patch.valueFieldApiName = null;
        }
        if (aggregateFunction !== 'FORMULA') {
            patch.formula = null;
            patch.isCurrency = null;
        } else {
            // A Formula measure reads the other Measures, never an object of its own.
            Object.assign(patch, {
                sourceObject: null,
                categoryMapping: null,
                panelMapping: null,
                filterBindings: null
            });
        }
        if (!ROLLUP_FUNCTIONS.includes(aggregateFunction)) {
            patch.showAs = null;
        }
        // Average per record starts as the sum of each record's rows; other aggregates drop its settings.
        if (aggregateFunction === 'AVG_PER') {
            patch.inner = 'SUM';
        } else {
            patch.perField = null;
            patch.inner = null;
        }
        this.updateMeasure(event, patch);
    }

    handleMeasurePerField(event) {
        this.updateMeasure(event, { perField: event.detail.value || null });
    }

    handleMeasureInner(event) {
        this.updateMeasure(event, { inner: event.detail.value || 'SUM' });
    }

    handleMeasureField(event) {
        this.updateMeasure(event, { valueFieldApiName: event.detail.value || null });
    }

    handleMeasureText(event) {
        const value = event.detail.value;
        this.updateMeasure(event, { [event.target.dataset.name]: value && value.trim() ? value.trim() : null });
    }

    /** A currency Formula measure returns an amount: converted to the Display currency, constants in Config currency. */
    handleMeasureCurrency(event) {
        this.updateMeasure(event, { isCurrency: event.detail.checked ? true : null });
    }

    handleMeasureHidden(event) {
        this.updateMeasure(event, { hidden: event.detail.checked ? true : null });
    }

    handleMeasureShowAs(event) {
        const showAs = event.detail.value;
        this.updateMeasure(event, { showAs: showAs && showAs !== 'value' ? showAs : null });
    }

    handleMeasureFormat(event) {
        this.updateMeasure(event, { format: event.detail.value });
    }

    /** `input` of the native Formula textarea (`event.target.value`). */
    handleMeasureFormula(event) {
        const value = event.target.value;
        this.updateMeasure(event, { formula: value && value.trim() ? value : null });
    }

    /** Draw as (bars or line) and value axis of a Measure, shown only for chart types that draw combo charts. */
    measureDisplayRow(measure) {
        const showDisplay = Boolean(this.chartType) && chartTypeHasSetting(this.chartType, 'comboMeasures');
        const { render, axis } = normalizeMeasureDisplay(measure, this.chartType);
        return { showDisplay, render, axis };
    }

    handleMeasureRender(event) {
        this.updateMeasure(event, { render: event.detail.value });
    }

    /** The primary axis is the default, so it is not written. */
    handleMeasureAxis(event) {
        this.updateMeasure(event, { axis: event.detail.value === 'secondary' ? 'secondary' : null });
    }

    /** Cross-object measure settings (`c-board-cpe-cross-object-measure` patch). */
    handleMeasureCrossObject(event) {
        event.stopPropagation();
        this.updateMeasure(event, event.detail.value);
    }

    /** Measure condition from the shared condition editor; an emptied tree removes it. */
    handleMeasureCondition(event) {
        const tree = event.detail.value;
        const hasConditions = tree && Array.isArray(tree.conditions) && tree.conditions.length > 0;
        this.updateMeasure(event, { condition: hasConditions ? tree : null });
    }
}