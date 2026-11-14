import { LightningElement, api } from 'lwc';
import { normalizeBoardError } from 'c/boardConfigUtils';
import {
    DATE_FIELD_TYPES,
    PICKLIST_FIELD_TYPES,
    loadChildRelationships,
    loadObjectFields,
    loadQueryableObjects,
    loadScreenFlows,
    containInnerChanges
} from 'c/boardCpeUtils';

const MAX_HOPS = 5;
const MAX_OPTIONS = 100;
const MODES = ['object', 'field', 'childRelationship', 'screenFlow'];
const CAPABILITY_TESTS = {
    filterable: (field) => field.isFilterable,
    groupable: (field) => field.isGroupable,
    sortable: (field) => field.isSortable,
    numeric: (field) => field.isNumeric,
    date: (field) => [...DATE_FIELD_TYPES, 'TIME'].includes(field.dataType),
    picklist: (field) => PICKLIST_FIELD_TYPES.includes(field.dataType),
    lookup: (field) => field.dataType === 'REFERENCE'
};

function matches(term, ...texts) {
    return !term || texts.some((text) => text && String(text).toLowerCase().includes(term));
}

/** Polymorphic lookups traverse to `User` when possible, matching `BoardQueryService` path resolution. */
function traversalTarget(field) {
    const targets = field.referenceTo || [];
    return targets.includes('User') ? 'User' : targets[0];
}

/**
 * Searchable object picker (`mode="object"`), capability-filtered field picker with 1–5 hop parent dot-path and
 * `Child(ForeignKey).Field` builder (`mode="field"`), child relationship selector (`mode="childRelationship"`), and
 * picker of the org's active Screen Flows (`mode="screenFlow"`), backed by `BoardSchemaService`.
 *
 * Fires a non-bubbling `change` event: `{ value, object }` (object), `{ value, field, objectApiName }` (field, where
 * `objectApiName` is the leaf field's object), `{ value: 'Child(FK)', childRelationship }` (childRelationship), or
 * `{ value, flow }` (screenFlow, the flow's API name), or `{ value: null }` when cleared.
 */
export default class BoardCpeObjectFieldPicker extends LightningElement {
    connectedCallback() {
        containInnerChanges(this);
    }

    @api label;
    /** Help text shown next to the label. */
    @api fieldLevelHelp;
    @api placeholder;
    @api value;
    /**
     * Comma-separated capabilities every selectable field must have: filterable, groupable, sortable, numeric, date
     * (Date/DateTime/Time), picklist (Picklist/Multi-Select Picklist). `|` joins alternatives within one entry, e.g. `numeric|date`.
     */
    @api capability;
    @api allowChildRelationships = false;
    @api disabled = false;

    searchTerm = '';
    isOpen = false;
    isLoading = false;
    errorMessage = null;
    items = [];
    childRelationships = [];
    hops = [];
    child = null;

    _mode = 'field';
    _objectApiName = null;
    _maxHops = MAX_HOPS;
    _loadToken = 0;

    @api
    get mode() {
        return this._mode;
    }
    set mode(value) {
        this._mode = MODES.includes(value) ? value : 'field';
        this.resetNavigation();
    }

    @api
    get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(value) {
        const next = typeof value === 'string' && value.trim() ? value.trim() : null;
        if (next !== this._objectApiName) {
            this._objectApiName = next;
            this.resetNavigation();
        }
    }

    /** Parent relationship hops allowed in a field path (0–5, default 5). */
    @api
    get maxHops() {
        return this._maxHops;
    }
    set maxHops(value) {
        const parsed = Number.parseInt(value, 10);
        this._maxHops = Number.isNaN(parsed) ? MAX_HOPS : Math.min(Math.max(parsed, 0), MAX_HOPS);
    }

    get isObjectMode() {
        return this._mode === 'object';
    }

    get isScreenFlowMode() {
        return this._mode === 'screenFlow';
    }

    /** Object and Screen Flow modes pick from one flat list of `{ apiName, label }` that needs no object. */
    get isFlatListMode() {
        return this.isObjectMode || this.isScreenFlowMode;
    }

    get isFieldMode() {
        return this._mode === 'field';
    }

    get needsObject() {
        return !this.isFlatListMode && !this._objectApiName;
    }

    get isInputDisabled() {
        return this.disabled || this.needsObject;
    }

    get inputPlaceholder() {
        if (this.needsObject) {
            return 'Select an object first';
        }
        if (this.placeholder) {
            return this.placeholder;
        }
        if (this.isObjectMode) {
            return 'Search objects by label or API name';
        }
        if (this.isScreenFlowMode) {
            return 'Search active Screen Flows by label or API name';
        }
        return this.isFieldMode ? 'Search fields' : 'Search child relationships';
    }

    get hasValue() {
        return Boolean(this.value);
    }

    get currentObjectApiName() {
        if (this.hops.length) {
            return this.hops[this.hops.length - 1].objectApiName;
        }
        return this.child ? this.child.childObjectApiName : this._objectApiName;
    }

    get isRootLevel() {
        return !this.hops.length && !this.child;
    }

    get canTraverse() {
        return this.hops.length < this._maxHops;
    }

    get pathPrefix() {
        const parts = [];
        if (this.child) {
            parts.push(`${this.child.childObjectApiName}(${this.child.foreignKeyField})`);
        }
        this.hops.forEach((hop) => parts.push(hop.relationshipName));
        return parts.length ? `${parts.join('.')}.` : '';
    }

    get showBreadcrumbs() {
        return this.isFieldMode && !this.isRootLevel;
    }

    get breadcrumbs() {
        const crumbs = [{ key: 'root', level: -1, label: this._objectApiName }];
        if (this.child) {
            crumbs.push({
                key: 'child',
                level: 0,
                label: `${this.child.childObjectApiName}(${this.child.foreignKeyField})`
            });
        }
        this.hops.forEach((hop, index) => {
            crumbs.push({ key: `hop-${index}`, level: index + 1, label: hop.relationshipName });
        });
        return crumbs.map((crumb, index) => ({ ...crumb, isCurrent: index === crumbs.length - 1 }));
    }

    get hopStatus() {
        return `${this.hops.length} of ${this._maxHops} relationship hops`;
    }

    /** One predicate per comma entry; each entry passes when any of its `|` alternatives does. */
    get requiredTests() {
        return String(this.capability || '')
            .split(',')
            .map((entry) =>
                entry
                    .split('|')
                    .map((name) => CAPABILITY_TESTS[name.trim().toLowerCase()])
                    .filter(Boolean)
            )
            .filter((alternatives) => alternatives.length)
            .map((alternatives) => (field) => alternatives.some((test) => test(field)));
    }

    isSelectable(field) {
        return this.requiredTests.every((test) => test(field));
    }

    get allOptions() {
        const term = this.searchTerm.trim().toLowerCase();
        if (this.isFlatListMode) {
            return this.items
                .filter((object) => matches(term, object.label, object.apiName))
                .map((object) => ({
                    key: object.apiName,
                    label: object.label,
                    meta: object.apiName,
                    traversable: false
                }));
        }
        if (this._mode === 'childRelationship') {
            return this.childRelationships
                .filter((rel) => matches(term, rel.childObjectLabel, rel.childObjectApiName, rel.relationshipName))
                .map((rel) => this.childOption(rel, false));
        }
        const tests = this.requiredTests;
        const options = [];
        this.items.forEach((field) => {
            if (!matches(term, field.label, field.apiName, field.relationshipName)) {
                return;
            }
            const selectable = tests.every((test) => test(field));
            const traversable =
                this.canTraverse &&
                field.dataType === 'REFERENCE' &&
                Boolean(field.relationshipName) &&
                Boolean(traversalTarget(field));
            if (!selectable && !traversable) {
                return;
            }
            options.push({
                key: `field:${field.apiName}`,
                label: field.label,
                meta: `${this.pathPrefix}${field.apiName} · ${field.dataType}`,
                traversable,
                traverseLabel: `Open ${field.relationshipName} (${traversalTarget(field)}) fields`
            });
        });
        if (this.isRootLevel && this.allowChildRelationships) {
            this.childRelationships
                .filter((rel) => matches(term, rel.childObjectLabel, rel.childObjectApiName, rel.relationshipName))
                .forEach((rel) => options.push(this.childOption(rel, true)));
        }
        return options;
    }

    childOption(rel, traversable) {
        const token = `${rel.childObjectApiName}(${rel.foreignKeyField})`;
        return {
            key: `child:${token}`,
            label: `${rel.childObjectLabel || rel.childObjectApiName} (${rel.foreignKeyField})`,
            meta: rel.relationshipName ? `${token} · ${rel.relationshipName}` : token,
            traversable,
            traverseLabel: `Open ${token} fields`
        };
    }

    get options() {
        return this.allOptions.slice(0, MAX_OPTIONS);
    }

    get hasOptions() {
        return this.options.length > 0;
    }

    get isTruncated() {
        return this.allOptions.length > MAX_OPTIONS;
    }

    get truncatedMessage() {
        return `Showing ${MAX_OPTIONS} of ${this.allOptions.length} matches. Keep typing to narrow the list.`;
    }

    get showEmpty() {
        return !this.isLoading && !this.errorMessage && !this.hasOptions;
    }

    resetNavigation() {
        this.hops = [];
        this.child = null;
        this.items = [];
        this.childRelationships = [];
        this.errorMessage = null;
        if (this.isOpen) {
            this.loadLevel();
        }
    }

    async loadLevel() {
        const token = ++this._loadToken;
        this.isLoading = true;
        this.errorMessage = null;
        try {
            let items = [];
            let childRelationships = [];
            if (this.isObjectMode) {
                items = await loadQueryableObjects();
            } else if (this.isScreenFlowMode) {
                items = await loadScreenFlows();
            } else if (this._objectApiName) {
                if (this._mode === 'childRelationship') {
                    childRelationships = await loadChildRelationships(this._objectApiName);
                } else {
                    const loads = [loadObjectFields(this.currentObjectApiName)];
                    if (this.isRootLevel && this.allowChildRelationships) {
                        loads.push(loadChildRelationships(this._objectApiName));
                    }
                    [items, childRelationships = []] = await Promise.all(loads);
                }
            }
            if (token === this._loadToken) {
                this.items = items || [];
                this.childRelationships = childRelationships || [];
            }
        } catch (err) {
            if (token === this._loadToken) {
                this.items = [];
                this.childRelationships = [];
                this.errorMessage = normalizeBoardError(err).message;
            }
        } finally {
            if (token === this._loadToken) {
                this.isLoading = false;
            }
        }
    }

    open() {
        if (this.isInputDisabled || this.isOpen) {
            return;
        }
        this.isOpen = true;
        this.loadLevel();
    }

    close() {
        this.isOpen = false;
        this.searchTerm = '';
        this.hops = [];
        this.child = null;
    }

    handleFocus() {
        this.open();
    }

    handleSearch(event) {
        this.searchTerm = event.detail.value || '';
        this.open();
    }

    handleKeyDown(event) {
        if (event.key === 'Escape') {
            this.close();
        }
    }

    handleClose() {
        this.close();
    }

    handleClear() {
        this.close();
        this.fireChange({ value: null });
    }

    handleOptionClick(event) {
        const key = event.currentTarget.dataset.key;
        const option = this.allOptions.find((item) => item.key === key);
        if (!option) {
            return;
        }
        if (this.isFlatListMode) {
            const item = this.items.find((candidate) => candidate.apiName === key);
            this.close();
            this.fireChange({ value: item.apiName, [this.isObjectMode ? 'object' : 'flow']: { ...item } });
            return;
        }
        if (key.startsWith('child:')) {
            const rel = this.findChild(key);
            if (this._mode === 'childRelationship') {
                this.close();
                this.fireChange({ value: key.slice('child:'.length), childRelationship: { ...rel } });
            } else {
                this.enterChild(rel);
            }
            return;
        }
        const field = this.items.find((item) => `field:${item.apiName}` === key);
        if (!this.isSelectable(field)) {
            this.traverse(field);
            return;
        }
        const value = `${this.pathPrefix}${field.apiName}`;
        const objectApiName = this.currentObjectApiName;
        this.close();
        this.fireChange({ value, field: { ...field }, objectApiName });
    }

    handleTraverseClick(event) {
        const key = event.currentTarget.dataset.key;
        if (key.startsWith('child:')) {
            this.enterChild(this.findChild(key));
            return;
        }
        this.traverse(this.items.find((item) => `field:${item.apiName}` === key));
    }

    handleCrumbClick(event) {
        const level = Number(event.currentTarget.dataset.level);
        if (level < 0) {
            this.child = null;
            this.hops = [];
        } else {
            this.hops = this.hops.slice(0, level);
        }
        this.searchTerm = '';
        this.loadLevel();
    }

    findChild(key) {
        return this.childRelationships.find((rel) => `child:${rel.childObjectApiName}(${rel.foreignKeyField})` === key);
    }

    enterChild(rel) {
        if (!rel) {
            return;
        }
        this.child = { ...rel };
        this.hops = [];
        this.searchTerm = '';
        this.loadLevel();
    }

    traverse(field) {
        if (!field || !this.canTraverse || !field.relationshipName) {
            return;
        }
        this.hops = [
            ...this.hops,
            { relationshipName: field.relationshipName, objectApiName: traversalTarget(field), label: field.label }
        ];
        this.searchTerm = '';
        this.loadLevel();
    }

    fireChange(detail) {
        this.dispatchEvent(new CustomEvent('change', { detail }));
    }
}