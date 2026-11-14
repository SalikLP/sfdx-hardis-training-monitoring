import { LightningElement, api } from 'lwc';
import getCurrencyOptions from '@salesforce/apex/BoardCurrencyConverter.getCurrencyOptions';
import { containInnerChanges } from 'c/boardCpeUtils';

/**
 * Config currency setting of the Filter widget's Setup dialog (its Currency step): a combobox of the org's active
 * currencies. Blank (the default) means the corporate currency. In a single-currency org it explains that there is
 * nothing to set.
 *
 * Fires `change` (`detail: { value }`, an ISO code or null for the corporate default).
 */
export default class BoardConfigCurrency extends LightningElement {
    /** The saved Config currency ISO code; blank for the corporate currency. */
    @api value = '';

    currencyOptions = null;

    connectedCallback() {
        containInnerChanges(this);
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

    /** Known to be a single-currency org (unknown while loading). */
    get isSingleCurrency() {
        return Boolean(this.currencyOptions) && !this.isMultiCurrency;
    }

    get corporateLabel() {
        const corporate = this.currencyOptions?.corporateIsoCode;
        return corporate ? `Corporate currency (${corporate})` : 'Corporate currency';
    }

    get selectedValue() {
        return this.value ? String(this.value).trim().toUpperCase() : '';
    }

    get options() {
        const isoCodes = Array.isArray(this.currencyOptions?.isoCodes) ? this.currencyOptions.isoCodes : [];
        const selected = this.selectedValue;
        // A saved code that is no longer active stays listed so the Admin sees it.
        const codes = selected && !isoCodes.includes(selected) ? [...isoCodes, selected] : isoCodes;
        return [{ label: this.corporateLabel, value: '' }, ...codes.map((code) => ({ label: code, value: code }))];
    }

    handleChange(event) {
        event.stopPropagation();
        const value = event.detail.value ? String(event.detail.value) : null;
        this.dispatchEvent(new CustomEvent('change', { detail: { value } }));
    }
}