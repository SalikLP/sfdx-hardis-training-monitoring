import { LightningElement, api } from 'lwc';
import { SLDS_NAMED_COLOURS, contrastWarning, namedColourOf } from 'c/boardChartColours';
import { baseFilterError, moveItem, containInnerChanges } from 'c/boardCpeUtils';
import {
    DEFAULT_BUCKET_FALLBACK_LABEL,
    MAX_BUCKET_RULES,
    bucketFieldErrors,
    newBucketField,
    newBucketRule
} from 'c/boardBucketFields';

const CUSTOM = 'custom';
const NO_COLOUR = '';
const COLOUR_OPTIONS = [
    { label: 'No colour (palette)', value: NO_COLOUR },
    ...SLDS_NAMED_COLOURS,
    { label: 'Custom hex colour�', value: CUSTOM }
];

/**
 * Edits a Widget's Bucket fields (`bucketFields`, see `c/boardBucketFields`): each Bucket field's label, its ordered
 * rules (label, optional colour, and a condition tree in the shared condition editor; at most 25 rules, first match
 * wins) and its fallback bucket (label, default "Other", or leave rows matching no rule out).
 *
 * Fires `change` with `detail.value`, the whole edited list, after every edit.
 */
export default class BoardBucketFieldEditor extends LightningElement {
    connectedCallback() {
        containInnerChanges(this);
    }

    /** Object the rule conditions' field pickers start from. */
    @api objectApiName;

    maxRules = MAX_BUCKET_RULES;
    defaultFallbackLabel = DEFAULT_BUCKET_FALLBACK_LABEL;
    colourOptions = COLOUR_OPTIONS;
    fields = [];
    /** Rules (`fieldIndex-ruleIndex`) switched to a custom hex while their colour is empty or a named one. */
    customColourRules = new Set();

    @api
    get value() {
        return this.fields;
    }

    set value(value) {
        this.fields = Array.isArray(value) ? value : [];
    }

    get hasFields() {
        return this.fields.length > 0;
    }

    get errors() {
        return bucketFieldErrors(this.fields, baseFilterError);
    }

    get hasErrors() {
        return this.errors.length > 0;
    }

    get fieldViews() {
        return this.fields.map((field, fieldIndex) => {
            const safe = field && typeof field === 'object' ? field : {};
            const rules = Array.isArray(safe.rules) ? safe.rules : [];
            const fallback = safe.fallback && typeof safe.fallback === 'object' ? safe.fallback : {};
            const atLimit = rules.length >= MAX_BUCKET_RULES;
            return {
                key: safe.id || `field-${fieldIndex}`,
                fieldIndex,
                label: safe.label || '',
                title: safe.label || `Bucket field ${fieldIndex + 1}`,
                fallbackLabel: fallback.label ?? DEFAULT_BUCKET_FALLBACK_LABEL,
                exclude: fallback.exclude === true,
                addRuleDisabled: atLimit,
                atLimit,
                rules: rules.map((rule, ruleIndex) => {
                    const safeRule = rule && typeof rule === 'object' ? rule : {};
                    const key = `${fieldIndex}-${ruleIndex}`;
                    const colour = typeof safeRule.colour === 'string' ? safeRule.colour : '';
                    const isCustomColour = this.customColourRules.has(key) || (colour !== '' && !namedColourOf(colour));
                    return {
                        key,
                        ruleIndex,
                        title: `Rule ${ruleIndex + 1}`,
                        label: safeRule.label || '',
                        colour,
                        isCustomColour,
                        choice: isCustomColour ? CUSTOM : colour === '' ? NO_COLOUR : namedColourOf(colour).value,
                        colourWarning: isCustomColour ? contrastWarning(colour) : null,
                        condition: safeRule.condition,
                        isFirst: ruleIndex === 0,
                        isLast: ruleIndex === rules.length - 1,
                        isOnly: rules.length === 1
                    };
                })
            };
        });
    }

    // ---- Edits ---------------------------------------------------------------------------------------------------

    handleAddField() {
        this.commit([...this.fields, newBucketField(this.fields)]);
    }

    handleRemoveField(event) {
        this.customColourRules = new Set();
        const index = Number(event.currentTarget.dataset.fieldIndex);
        this.commit(this.fields.filter((field, position) => position !== index));
    }

    handleFieldLabel(event) {
        this.updateField(event, (field) => ({ ...field, label: event.detail.value || '' }));
    }

    handleFallbackLabel(event) {
        const label = event.detail.value || '';
        this.updateField(event, (field) => ({ ...field, fallback: { ...fallbackOf(field), label } }));
    }

    handleFallbackExclude(event) {
        const exclude = event.detail.checked === true;
        this.updateField(event, (field) => ({ ...field, fallback: { ...fallbackOf(field), exclude } }));
    }

    handleAddRule(event) {
        this.updateRules(event, (rules) => (rules.length < MAX_BUCKET_RULES ? [...rules, newBucketRule()] : rules));
    }

    handleRemoveRule(event) {
        this.customColourRules = new Set();
        const index = Number(event.currentTarget.dataset.ruleIndex);
        this.updateRules(event, (rules) => rules.filter((rule, position) => position !== index));
    }

    handleRuleUp(event) {
        this.customColourRules = new Set();
        this.updateRules(event, (rules) => moveItem(rules, Number(event.currentTarget.dataset.ruleIndex), -1));
    }

    handleRuleDown(event) {
        this.customColourRules = new Set();
        this.updateRules(event, (rules) => moveItem(rules, Number(event.currentTarget.dataset.ruleIndex), 1));
    }

    handleRuleText(event) {
        const name = event.target.dataset.name;
        const value = event.detail.value ? String(event.detail.value) : '';
        this.updateRule(event, (rule) => {
            const next = { ...rule, [name]: value };
            if (name === 'colour' && !value.trim()) {
                delete next.colour;
            }
            return next;
        });
    }

    handleRuleColourChoice(event) {
        const choice = event.detail.value || NO_COLOUR;
        const key = `${event.currentTarget.dataset.fieldIndex}-${event.currentTarget.dataset.ruleIndex}`;
        const custom = new Set(this.customColourRules);
        if (choice === CUSTOM) {
            custom.add(key);
            this.customColourRules = custom;
            // Re-render with the hex input; the stored colour is unchanged until a hex is typed.
            this.fields = [...this.fields];
            return;
        }
        custom.delete(key);
        this.customColourRules = custom;
        this.updateRule(event, (rule) => {
            const next = { ...rule };
            if (choice === NO_COLOUR) {
                delete next.colour;
            } else {
                next.colour = choice;
            }
            return next;
        });
    }

    handleRuleCondition(event) {
        const condition = event.detail.value;
        this.updateRule(event, (rule) => ({ ...rule, condition }));
    }

    updateField(event, update) {
        const index = Number(event.currentTarget.dataset.fieldIndex);
        this.commit(this.fields.map((field, position) => (position === index ? update(field) : field)));
    }

    updateRules(event, update) {
        this.updateField(event, (field) => ({
            ...field,
            rules: update(Array.isArray(field.rules) ? field.rules : [])
        }));
    }

    updateRule(event, update) {
        const index = Number(event.currentTarget.dataset.ruleIndex);
        this.updateRules(event, (rules) => rules.map((rule, position) => (position === index ? update(rule) : rule)));
    }

    commit(fields) {
        this.fields = fields;
        this.dispatchEvent(new CustomEvent('change', { detail: { value: fields } }));
    }
}

function fallbackOf(field) {
    return field.fallback && typeof field.fallback === 'object'
        ? field.fallback
        : { label: DEFAULT_BUCKET_FALLBACK_LABEL, exclude: false };
}