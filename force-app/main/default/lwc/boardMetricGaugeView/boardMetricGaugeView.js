import { LightningElement, api } from 'lwc';

/**
 * Metric widget Gauge: a horizontal scale drawn from the model of `resolveGauge` (`c/boardMetricGauge`): status
 * bands, the value marker, an optional target marker, and the min / max labels. Presentation only.
 */
export default class BoardMetricGaugeView extends LightningElement {
    /** `{ minLabel, maxLabel, valuePct, valueLabel, bands: [{ key, variant, startPct, widthPct }], target }`. */
    @api model;

    get bands() {
        return (this.model?.bands || []).map((band) => ({
            key: band.key,
            className: `c-gauge-band c-gauge-band_${band.variant}`,
            variant: band.variant,
            style: `left: ${band.startPct}%; width: ${band.widthPct}%`
        }));
    }

    get hasValue() {
        return this.model?.valuePct !== null && this.model?.valuePct !== undefined;
    }

    get valueStyle() {
        return `left: ${this.model.valuePct}%`;
    }

    get valueTitle() {
        return `Value: ${this.model.valueLabel}`;
    }

    get target() {
        return this.model?.target || null;
    }

    get targetStyle() {
        return `left: ${this.target.pct}%`;
    }

    get targetTitle() {
        return `Target: ${this.target.label}`;
    }

    get summary() {
        const model = this.model;
        const parts = [`Gauge from ${model.minLabel} to ${model.maxLabel}`];
        if (this.hasValue) {
            parts.push(`value ${model.valueLabel}`);
        }
        if (this.target) {
            parts.push(`target ${this.target.label}`);
        }
        return parts.join(', ');
    }
}