import { LightningElement, api } from 'lwc';

const CROSS_OBJECT_KEYS = ['sourceObject', 'categoryMapping', 'panelMapping', 'filterBindings', 'dataProvider'];
const FORECASTING_QUOTA = 'forecastingquota';

function text(value) {
    return typeof value === 'string' && value.trim() ? value.trim() : null;
}

/**
 * Cross-object measure settings of one Measure in the Measures list: whether its rows come from another object, that
 * source object, the field on it matching the Widget's category (`showCategoryMapping`, Chart widget) and Panel field
 * (`panelField`, Small multiples), its own Filter bindings (`filterBindings`: filter id → field path or IGNORE), and
 * the Data provider class supplying its values instead of the source object's query (`dataProvider`).
 * Fires a non-bubbling `change` event whose `detail.value` is a Measure patch (null removes a key); switching it off
 * removes every Cross-object key.
 */
export default class BoardCpeCrossObjectMeasure extends LightningElement {
    /** The Measure being edited. */
    @api measure;
    /** Chart widget: the source object needs a field matching the category. */
    @api showCategoryMapping = false;
    /** The Widget's Panel field (Small multiples), when it has one. */
    @api panelField;

    /** Toggled on before a source object is chosen. */
    isOpen = false;
    newBindingId = '';

    get sourceObject() {
        return text(this.measure && this.measure.sourceObject);
    }

    get isEnabled() {
        return this.isOpen || Boolean(this.sourceObject);
    }

    get categoryMapping() {
        return text(this.measure && this.measure.categoryMapping) || '';
    }

    get panelMapping() {
        return text(this.measure && this.measure.panelMapping) || '';
    }

    get dataProvider() {
        return text(this.measure && this.measure.dataProvider) || '';
    }

    get showPanelMapping() {
        return Boolean(text(this.panelField));
    }

    /**
     * ForecastingQuota read by the engine (no Data provider) follows the forecast hierarchy in USER_MODE: a static
     * note, with no runtime permission check.
     */
    get showQuotaNote() {
        return (
            (this.sourceObject || '').toLowerCase() === FORECASTING_QUOTA &&
            !text(this.measure && this.measure.dataProvider)
        );
    }

    get sourceLabel() {
        return this.sourceObject || 'the source object';
    }

    get bindings() {
        const bindings = this.measure && this.measure.filterBindings;
        return bindings && typeof bindings === 'object' && !Array.isArray(bindings) ? bindings : {};
    }

    get bindingRows() {
        return Object.entries(this.bindings).map(([filterId, path]) => ({
            key: filterId,
            filterId,
            path: path === null ? 'IGNORE' : String(path)
        }));
    }

    get addBindingDisabled() {
        return !text(this.newBindingId) || Object.prototype.hasOwnProperty.call(this.bindings, text(this.newBindingId));
    }

    emit(patch) {
        this.dispatchEvent(new CustomEvent('change', { detail: { value: patch } }));
    }

    handleToggle(event) {
        if (event.detail.checked) {
            this.isOpen = true;
            return;
        }
        this.isOpen = false;
        this.emit(Object.fromEntries(CROSS_OBJECT_KEYS.map((key) => [key, null])));
    }

    handleSource(event) {
        const sourceObject = event.detail.value || null;
        // Mappings and bindings name fields of the previous source object.
        this.emit({
            sourceObject,
            categoryMapping: null,
            panelMapping: null,
            filterBindings: null,
            valueFieldApiName: null,
            condition: null
        });
    }

    handleCategory(event) {
        this.emit({ categoryMapping: event.detail.value || null });
    }

    handlePanel(event) {
        this.emit({ panelMapping: event.detail.value || null });
    }

    handleProvider(event) {
        this.emit({ dataProvider: text(event.detail.value) });
    }

    handleNewBindingId(event) {
        this.newBindingId = event.detail.value || '';
    }

    handleAddBinding() {
        const filterId = text(this.newBindingId);
        if (!filterId || this.addBindingDisabled) {
            return;
        }
        this.newBindingId = '';
        this.emit({ filterBindings: { ...this.bindings, [filterId]: 'IGNORE' } });
    }

    handleBindingPath(event) {
        const filterId = event.target.dataset.filterId;
        const path = text(event.detail.value);
        this.emit({ filterBindings: { ...this.bindings, [filterId]: path || 'IGNORE' } });
    }

    handleRemoveBinding(event) {
        const bindings = { ...this.bindings };
        delete bindings[event.currentTarget.dataset.filterId];
        this.emit({ filterBindings: Object.keys(bindings).length ? bindings : null });
    }
}