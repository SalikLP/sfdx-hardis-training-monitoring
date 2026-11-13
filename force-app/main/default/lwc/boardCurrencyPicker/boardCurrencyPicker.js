import { LightningElement, api } from 'lwc';
import getCurrencyOptions from '@salesforce/apex/BoardCurrencyConverter.getCurrencyOptions';
import { getDisplayCurrency, setDisplayCurrency } from 'c/boardContextStore';

export const DEFAULT_CURRENCY_PICKER_LABEL = 'Currency';

/**
 * Currency picker item of a Filter widget: a single-select of the org's active currencies that publishes the Board's
 * Display currency to the context store (every Widget on the Board re-queries in it). It is not a filter: it never
 * changes which records count, and the choice is not persisted. Renders nothing in a single-currency org.
 */
export default class BoardCurrencyPicker extends LightningElement {
    /** Board id whose Display currency the picker sets. */
    @api boardId;
    /** Label the Admin gave the item (blank: `Currency`). */
    @api label;

    currencyOptions = null;
    value = null;

    connectedCallback() {
        this.value = getDisplayCurrency(this.boardId);
        Promise.resolve(getCurrencyOptions())
            .then((options) => {
                this.currencyOptions = options || null;
            })
            .catch(() => {
                this.currencyOptions = null;
            });
    }

    get isMultiCurrency() {
        return this.currencyOptions?.multiCurrency === true;
    }

    get effectiveLabel() {
        return this.label && String(this.label).trim() ? String(this.label).trim() : DEFAULT_CURRENCY_PICKER_LABEL;
    }

    get options() {
        const isoCodes = Array.isArray(this.currencyOptions?.isoCodes) ? this.currencyOptions.isoCodes : [];
        return isoCodes.map((code) => ({ label: code, value: code }));
    }

    handleChange(event) {
        const isoCode = event.detail.value ? String(event.detail.value) : null;
        setDisplayCurrency(this.boardId, isoCode);
        this.value = getDisplayCurrency(this.boardId);
    }
}