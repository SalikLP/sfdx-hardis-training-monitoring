import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import {
    DIALOG_DISMISS,
    DIALOG_SAVE,
    applyPatch,
    cleanString,
    deepCopy,
    isPlainObject,
    loadObjectFields,
    orderConfig
} from 'c/boardCpeUtils';
import { stepsFor } from 'c/boardSetupSteps';
import { guidedNav, opensGuided } from 'c/boardSetupGuide';

/** The modal body's top and bottom padding (1rem each), when it can't be measured. */
const BODY_PADDING_PX = 32;
const ROUNDING_SLACK_PX = 4;
const SETTLE_DELAY_MS = 500;

const STATE_DONE = 'done';
const STATE_INVALID = 'invalid';
const STATE_NOT_VISITED = 'notVisited';

const STATE_TEXT = {
    [STATE_DONE]: 'Done',
    [STATE_INVALID]: 'Has errors',
    [STATE_NOT_VISITED]: 'Not visited'
};
const STATE_ICONS = {
    [STATE_DONE]: { iconName: 'utility:success', variant: 'success' },
    [STATE_INVALID]: { iconName: 'utility:error', variant: 'error' },
    [STATE_NOT_VISITED]: { iconName: null, variant: null }
};

/**
 * Setup dialog of one Widget (ADR 0002): a full-size `LightningModal` with a vertical step nav on the left and the
 * current step's content in the middle and a collapsible live preview of the draft on the right
 * (`c-board-setup-preview`, the width the step content leaves when open). The steps are the Widget's step descriptors
 * (`c/boardSetupSteps`); the content of each step comes from the Widget's step editor (`c-board-chart-setup-steps`,
 * `c-board-metric-setup-steps`, `c-board-table-setup-steps`, `c-board-filter-setup-steps`).
 *
 * Open with `BoardSetupDialog.open({ size: 'full', label, widgetType, config, context, startStep })`:
 * - `config`: the Widget config; the dialog edits one deep-copied draft of it across all steps
 * - `context`: what the step validators and step content read besides the config (`references`,
 *   `boardBucketFields`, `bindingRows`, `builderContext`, `elementInfo`)
 * - `startStep`: the step to open at (the first step when unknown)
 *
 * Each step opens with its descriptor's intro and worked example, above the step content.
 *
 * The nav shows each step as done (visited and valid), invalid (its validator over the whole draft, or errors its
 * content reports through `steperrors`, fails) or not visited. Save is disabled while any step is invalid and
 * resolves `{ action: 'save', config }` with the whole draft; Cancel, Escape and the header X resolve
 * `{ action: 'dismiss' }` and discard the draft.
 *
 * A step editor gets `step`, `config` (the draft) and `context`, and fires `change` with `detail.patch` (shallow
 * merged into the draft; null removes a key) and `steperrors` with `detail.step` and `detail.errors` (messages).
 *
 * A Widget with no config yet opens in Guided mode (`c/boardSetupGuide`) at the first step: Back / Next walk the
 * steps in order, Next is blocked while a required step is invalid and the steps after it are locked in the nav;
 * optional steps can be skipped. Otherwise the Admin moves freely between steps.
 *
 * The dialog describes the draft's object (`context.objectFields`), so an upstream change (a different object)
 * flags the later steps whose fields aren't on it invalid; their settings are kept.
 */
export default class BoardSetupDialog extends LightningModal {
    @api widgetType;
    @api config;
    @api context;
    @api startStep;

    draft = {};
    currentStep = null;
    visited = [];
    /** Errors reported by the step content (`steperrors`) per step name, e.g. a Formula the server rejects. */
    reportedErrors = {};
    /** Whether the live preview pane (`c-board-setup-preview`) is shown; collapsed it keeps only its toggle. */
    previewOpen = true;
    /** Guided mode: linear Back / Next (a Widget with no config yet). */
    guided = false;
    /** Field describes of the draft's object, once loaded: `{ objectApiName, fields }`. */
    objectDescribe = null;

    _initialized = false;

    connectedCallback() {
        if (this._initialized) {
            return;
        }
        this._initialized = true;
        this.draft = isPlainObject(this.config) ? deepCopy(this.config) : {};
        this.guided = opensGuided(this.config, this.stepContext.references);
        const names = this.steps.map((step) => step.name);
        const start = !this.guided && names.includes(this.startStep) ? this.startStep : names[0];
        this.currentStep = start || null;
        this.visited = this.currentStep ? [this.currentStep] : [];
        this.describeDraftObject();
    }

    /** Loads the field describes of the draft's object, for the validators' `context.objectFields`. */
    describeDraftObject() {
        const objectApiName = cleanString(this.draft.objectApiName);
        if (!objectApiName || (this.objectDescribe && this.objectDescribe.objectApiName === objectApiName)) {
            return;
        }
        loadObjectFields(objectApiName)
            .then((fields) => {
                if (cleanString(this.draft.objectApiName) === objectApiName && Array.isArray(fields)) {
                    this.objectDescribe = { objectApiName, fields };
                }
            })
            .catch(() => {
                // Undescribed object: field paths aren't checked here; the server validates at runtime.
            });
    }

    get steps() {
        return stepsFor(this.widgetType);
    }

    get stepContext() {
        const context = isPlainObject(this.context) ? this.context : {};
        const described = this.objectDescribe;
        return described && described.objectApiName === cleanString(this.draft.objectApiName)
            ? { ...context, objectFields: described.fields }
            : context;
    }

    /** The step's errors over the whole draft, plus the ones its content reported. */
    errorsOf(step) {
        const own = step.validate(this.draft, this.stepContext).map((item) => item.errorString);
        return [...own, ...(this.reportedErrors[step.name] || [])];
    }

    stateOf(step) {
        if (this.errorsOf(step).length) {
            return STATE_INVALID;
        }
        return this.visited.includes(step.name) ? STATE_DONE : STATE_NOT_VISITED;
    }

    /** Guided mode navigation from the current step (`c/boardSetupGuide`), or null with free navigation. */
    get guide() {
        if (!this.guided) {
            return null;
        }
        const invalid = this.steps.filter((step) => this.errorsOf(step).length > 0).map((step) => step.name);
        return guidedNav(this.steps, this.currentStep, invalid);
    }

    get isBackDisabled() {
        return !this.guide || !this.guide.backStep;
    }

    get isNextDisabled() {
        return !this.guide || !this.guide.canNext;
    }

    get navItems() {
        const locked = this.guide ? this.guide.lockedSteps : [];
        return this.steps.map((step, index) => {
            const state = this.stateOf(step);
            const isCurrent = step.name === this.currentStep;
            return {
                name: step.name,
                label: step.label,
                number: index + 1,
                state,
                stateText: STATE_TEXT[state],
                ...STATE_ICONS[state],
                ariaCurrent: isCurrent ? 'step' : null,
                locked: locked.includes(step.name),
                itemClass: `c-setup-step slds-nav-vertical__item${isCurrent ? ' slds-is-active' : ''}`
            };
        });
    }

    get current() {
        return this.steps.find((step) => step.name === this.currentStep) || null;
    }

    get currentLabel() {
        return this.current ? this.current.label : '';
    }

    /** The current step's errors; one of a retired setting (`step.retired`) carries the keys that remove it. */
    get currentErrors() {
        if (!this.current) {
            return [];
        }
        const retired = Array.isArray(this.current.retired) ? this.current.retired : [];
        return this.errorsOf(this.current).map((message, index) => {
            const setting = retired.find((entry) => entry.message === message);
            return { key: `error-${index}`, message, retiredKeys: setting ? setting.keys.join(',') : null };
        });
    }

    /** "Remove retired setting": drops the retired keys of that error from the draft. */
    handleRemoveRetired(event) {
        const keys = (event.target.dataset.keys || '').split(',').filter(Boolean);
        if (keys.length) {
            this.draft = orderConfig(
                this.widgetType,
                applyPatch(this.draft, Object.fromEntries(keys.map((key) => [key, null])))
            );
        }
    }

    get hasCurrentErrors() {
        return this.currentErrors.length > 0;
    }

    get isChart() {
        return this.widgetType === 'chart';
    }

    get isMetric() {
        return this.widgetType === 'metric';
    }

    get isTable() {
        return this.widgetType === 'table';
    }

    get isFilter() {
        return this.widgetType === 'filter';
    }

    get isSaveDisabled() {
        return this.steps.some((step) => this.errorsOf(step).length > 0);
    }

    handleStepSelect(event) {
        this.goTo(event.currentTarget.dataset.step);
    }

    goTo(name) {
        if (!name || (this.guide && this.guide.lockedSteps.includes(name))) {
            return;
        }
        this.currentStep = name;
        if (!this.visited.includes(name)) {
            this.visited = [...this.visited, name];
        }
    }

    handleBack() {
        if (this.guide) {
            this.goTo(this.guide.backStep);
        }
    }

    handleNext() {
        if (this.guide && this.guide.canNext) {
            this.goTo(this.guide.nextStep);
        }
    }

    handleDraftChange(event) {
        event.stopPropagation();
        const patch = event.detail && event.detail.patch;
        if (isPlainObject(patch)) {
            this.draft = orderConfig(this.widgetType, applyPatch(this.draft, patch));
            this.describeDraftObject();
        }
    }

    handleStepErrors(event) {
        event.stopPropagation();
        const { step, errors } = event.detail || {};
        if (step) {
            this.reportedErrors = { ...this.reportedErrors, [step]: Array.isArray(errors) ? errors : [] };
        }
    }

    get contentColumnClass() {
        return `c-setup-content slds-p-horizontal_medium${this.previewOpen ? ' c-setup-content_beside-preview' : ''}`;
    }

    get previewColumnClass() {
        return `c-setup-preview slds-p-left_medium${this.previewOpen ? ' c-setup-preview_open' : ''}`;
    }

    get previewOpenText() {
        return String(this.previewOpen);
    }

    renderedCallback() {
        if (!this.resizeListener) {
            this.resizeListener = () => this.measureFillHeight();
            window.addEventListener('resize', this.resizeListener);
            this.observeLayout();
            // The modal opens with an animation and its fonts and intro settle late: measure again once it rests.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this.settleTimer = setTimeout(this.resizeListener, SETTLE_DELAY_MS);
        }
        this.measureFillHeight();
    }

    disconnectedCallback() {
        if (this.resizeListener) {
            window.removeEventListener('resize', this.resizeListener);
            clearTimeout(this.settleTimer);
            this.resizeListener = null;
        }
        if (this.layoutObserver) {
            this.layoutObserver.disconnect();
            this.layoutObserver = null;
        }
    }

    /** Measures again whenever the modal body or the step column (its intro wrapping, its errors) changes size. */
    observeLayout() {
        if (typeof ResizeObserver !== 'function') {
            return;
        }
        this.layoutObserver = new ResizeObserver(this.resizeListener);
        ['lightning-modal-body', '.c-setup-content'].forEach((selector) => {
            const element = this.template.querySelector(selector);
            if (element) {
                this.layoutObserver.observe(element);
            }
        });
    }

    /**
     * Fits the dialog's content to the visible modal body, so the body itself never scrolls: the columns get that
     * height (`--c-setup-visible-height`) and scroll on their own. Also publishes the height left under the step's
     * title, intro and errors (`--c-setup-fill-height`) for a step that fills the dialog (the Filter definitions
     * list). Without a laid-out modal nothing is set: the body scrolls and such a step keeps its own estimate.
     */
    measureFillHeight() {
        const setup = this.template.querySelector('.c-setup');
        const stepBody = this.template.querySelector('.c-setup-step-body');
        if (!setup || !stepBody) {
            return;
        }
        const setupTop = setup.getBoundingClientRect().top;
        const visible = this.visibleBodyHeight(setupTop);
        if (visible === null) {
            return;
        }
        const height = Math.floor(visible - ROUNDING_SLACK_PX);
        // Measured inside the step column, which scrolls on its own once fitted: add back what it has scrolled.
        const content = this.template.querySelector('.c-setup-content');
        const aboveStep = stepBody.getBoundingClientRect().top - setupTop + (content ? content.scrollTop : 0);
        const fill = Math.floor(height - aboveStep);
        if (height <= 0 || fill <= 0) {
            return;
        }
        setup.classList.add('c-setup_fitted');
        setup.style.setProperty('--c-setup-visible-height', `${height}px`);
        setup.style.setProperty('--c-setup-fill-height', `${fill}px`);
    }

    /**
     * The height the dialog's content can take without the modal body scrolling, or null when it can't be measured.
     * Read from the modal body when it is the scroll container (its client height minus the gap above the content,
     * taken again below it); otherwise from the space between the modal header and footer.
     */
    visibleBodyHeight(setupTop) {
        const body = this.template.querySelector('lightning-modal-body');
        if (body && body.clientHeight > 0 && /auto|scroll/.test(getComputedStyle(body).overflowY)) {
            const gap = setupTop - body.getBoundingClientRect().top + body.scrollTop;
            return body.clientHeight - 2 * Math.max(gap, 0);
        }
        const header = this.template.querySelector('lightning-modal-header');
        const footer = this.template.querySelector('lightning-modal-footer');
        if (!header || !footer) {
            return null;
        }
        const headerRect = header.getBoundingClientRect();
        const footerRect = footer.getBoundingClientRect();
        if (!headerRect.height || !footerRect.height || footerRect.top <= headerRect.bottom) {
            return null;
        }
        return footerRect.top - headerRect.bottom - BODY_PADDING_PX;
    }

    handlePreviewToggle(event) {
        event.stopPropagation();
        this.previewOpen = Boolean(event.detail && event.detail.open);
    }

    handleCancel() {
        this.close({ action: DIALOG_DISMISS });
    }

    handleSave() {
        if (this.isSaveDisabled) {
            return;
        }
        this.close({ action: DIALOG_SAVE, config: deepCopy(this.draft) });
    }
}