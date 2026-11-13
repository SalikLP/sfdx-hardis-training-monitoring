import { LightningElement, api } from 'lwc';
import { DATE_FIELD_TYPES, DATE_GRANULARITY_OPTIONS, parseNumber, resolveFieldDescribe } from 'c/boardCpeUtils';
import { bucketIdOf } from 'c/boardBucketFields';
import {
    DEFAULT_MAX_PANELS,
    DEFAULT_PANEL_HEIGHT,
    DEFAULT_PANELS_PER_ROW,
    MAX_PANEL_HEIGHT,
    MIN_PANEL_HEIGHT,
    PANEL_KEYS
} from 'c/boardChartPanels';

const PANEL_SORT_OPTIONS = [
    { label: 'Panel field order (picklist order, dates oldest first, else A–Z)', value: 'FIELD_ORDER' },
    { label: 'Measure total (high to low)', value: 'VALUE_DESC' },
    { label: 'Measure total (low to high)', value: 'VALUE_ASC' }
];

/**
 * Small multiples settings of the Chart Config editor: the Panel field (+ date granularity for a Date/DateTime field),
 * max panels, panel sort (by a Measure's total when there are several), panels per row, panel height, Independent
 * scales and the Panel headline (one of the Measures, hidden from the chart and shown as a number in each Panel header). Reads the Widget config and fires `change` with `detail.patch`, the config keys to update.
 */
export default class BoardChartPanelSettings extends LightningElement {
    @api objectApiName;
    /** Labels of the Chart widget's Measures, in Measure order. */
    @api measureLabels = [];
    /** Bucket field options (`None` first) of the Widget and its Board; the Bucket field picker shows with any. */
    @api bucketOptions = [];

    _config = {};
    /** `Schema.DisplayType` of the Panel field, once known. */
    panelFieldType = null;
    _typedKey = null;

    granularityOptions = DATE_GRANULARITY_OPTIONS;
    sortOptions = PANEL_SORT_OPTIONS;
    defaultMaxPanels = String(DEFAULT_MAX_PANELS);
    defaultPanelsPerRow = String(DEFAULT_PANELS_PER_ROW);
    defaultPanelHeight = String(DEFAULT_PANEL_HEIGHT);
    minPanelHeight = String(MIN_PANEL_HEIGHT);
    maxPanelHeight = String(MAX_PANEL_HEIGHT);

    @api
    get config() {
        return this._config;
    }
    set config(value) {
        this._config = value || {};
        this.resolvePanelFieldType();
    }

    get panelField() {
        return this._config.panelField || '';
    }

    get hasPanelField() {
        return Boolean(this.panelField);
    }

    get panelIsBucket() {
        return bucketIdOf(this.panelField) !== null;
    }

    /** The Panel field picker shows nothing while a Bucket field is the Panel field. */
    get panelPickerValue() {
        return this.panelIsBucket ? '' : this.panelField;
    }

    get panelBucket() {
        return this.panelIsBucket ? this.panelField : '';
    }

    get hasBucketOptions() {
        return (this.bucketOptions || []).some((option) => option.value);
    }

    get showGranularity() {
        return DATE_FIELD_TYPES.includes(this.panelFieldType) || Boolean(this._config.panelDateGranularity);
    }

    get panelDateGranularity() {
        return this._config.panelDateGranularity || 'DAY';
    }

    get maxPanels() {
        return this._config.maxPanels ?? '';
    }

    get panelSort() {
        return this._config.panelSort || 'FIELD_ORDER';
    }

    get showSortMeasure() {
        return this.panelSort !== 'FIELD_ORDER' && (this.measureLabels || []).length > 1;
    }

    get sortMeasureOptions() {
        return (this.measureLabels || []).map((label, index) => ({ label, value: String(index) }));
    }

    get panelSortMeasure() {
        return String(this._config.panelSortMeasure ?? 0);
    }

    /** `None`, then every Measure. */
    get headlineOptions() {
        return [
            { label: 'None', value: '' },
            ...(this.measureLabels || []).map((label, index) => ({ label, value: String(index) }))
        ];
    }

    get panelHeadlineMeasure() {
        const index = this._config.panelHeadlineMeasure;
        return index === null || index === undefined ? '' : String(index);
    }

    get panelsPerRow() {
        return this._config.panelsPerRow ?? '';
    }

    get panelHeight() {
        return this._config.panelHeight ?? '';
    }

    get independentScales() {
        return this._config.independentScales === true;
    }

    /** Describes a saved Panel field (e.g. on reopening the editor) to know whether it takes a date granularity. */
    resolvePanelFieldType() {
        const key =
            this.objectApiName && this.panelField && !this.panelIsBucket
                ? `${this.objectApiName}::${this.panelField}`
                : null;
        if (key === this._typedKey) {
            return;
        }
        this._typedKey = key;
        this.panelFieldType = null;
        if (!key) {
            return;
        }
        resolveFieldDescribe(this.objectApiName, this.panelField)
            .then((field) => {
                if (this._typedKey === key) {
                    this.panelFieldType = field ? field.dataType : null;
                }
            })
            .catch(() => {
                // Unknown type: the server validates the granularity at runtime.
            });
    }

    fire(patch) {
        this.dispatchEvent(new CustomEvent('change', { detail: { patch } }));
    }

    handlePanelField(event) {
        const panelField = event.detail.value || null;
        if (!panelField) {
            this.fire(Object.fromEntries(PANEL_KEYS.map((key) => [key, null])));
            return;
        }
        const dataType = event.detail.field ? event.detail.field.dataType : null;
        this._typedKey = this.objectApiName ? `${this.objectApiName}::${panelField}` : null;
        this.panelFieldType = dataType;
        const patch = { panelField };
        if (!DATE_FIELD_TYPES.includes(dataType)) {
            patch.panelDateGranularity = null;
        }
        this.fire(patch);
    }

    /** A Bucket field as the Panel field: one Panel per bucket, no date granularity. */
    handlePanelBucket(event) {
        const panelField = event.detail.value || null;
        if (!panelField) {
            this.fire(Object.fromEntries(PANEL_KEYS.map((key) => [key, null])));
            return;
        }
        this._typedKey = null;
        this.panelFieldType = null;
        this.fire({ panelField, panelDateGranularity: null });
    }

    handleGranularity(event) {
        this.fire({ panelDateGranularity: event.detail.value });
    }

    handleMaxPanels(event) {
        this.fire({ maxPanels: parseNumber(event.detail.value) });
    }

    handleSort(event) {
        const panelSort = event.detail.value === 'FIELD_ORDER' ? null : event.detail.value;
        this.fire(panelSort ? { panelSort } : { panelSort: null, panelSortMeasure: null });
    }

    handleSortMeasure(event) {
        const index = Number(event.detail.value) || 0;
        this.fire({ panelSortMeasure: index === 0 ? null : index });
    }

    /** Picks the Panel headline Measure and hides it from the chart (it stays one of the max 6 Measures). */
    handleHeadline(event) {
        const value = event.detail.value;
        if (value === '' || value === null || value === undefined) {
            this.fire({ panelHeadlineMeasure: null });
            return;
        }
        const index = Number(value);
        const measures = Array.isArray(this._config.measures) ? this._config.measures : [];
        const patch = { panelHeadlineMeasure: index };
        if (measures[index]) {
            patch.measures = [...measures];
            patch.measures[index] = { ...measures[index], hidden: true };
        }
        this.fire(patch);
    }

    handlePanelsPerRow(event) {
        this.fire({ panelsPerRow: parseNumber(event.detail.value) });
    }

    handlePanelHeight(event) {
        this.fire({ panelHeight: parseNumber(event.detail.value) });
    }

    handleIndependentScales(event) {
        this.fire({ independentScales: event.detail.checked ? true : null });
    }
}