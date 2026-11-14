/**
 * Guided mode of the Setup dialog (ADR 0002), as pure functions over the step descriptors (`c/boardSetupSteps`).
 *
 * A Widget with no config yet opens in Guided mode: the steps run in order with Back / Next; Next is blocked while a
 * required step up to the current one is invalid; optional steps can be skipped (their defaults apply). A Widget with
 * config opens with free navigation between steps.
 */

/**
 * Keys that don't count as Widget content: the envelope, the title (set in the panel) and the Board-level settings
 * (Board id, which Flow Builder pre-fills with its meta default "default"; Wait for Filter widget; Config currency).
 */
const NON_CONTENT_KEYS = ['version', 'widgetType', 'title', 'boardId', 'waitForFilterWidget', 'configCurrency'];

/** Defaults the config envelope writes for a Widget nobody has set up yet (`orderConfig` in `c/boardCpeUtils`). */
const DEFAULT_VALUES = { chartType: 'bar' };

function isContentKey(config, key) {
    return !NON_CONTENT_KEYS.includes(key) && !(key in DEFAULT_VALUES && config[key] === DEFAULT_VALUES[key]);
}

/**
 * True when the Setup dialog opens in Guided mode: the Widget has no Data / Measures / Columns / Filters content
 * (only the envelope, Board-level settings and defaults) and no content key bound to a Flow resource (`references`).
 */
export function opensGuided(config, references = {}) {
    const own = config && typeof config === 'object' ? config : {};
    const bound = references && typeof references === 'object' ? Object.keys(references) : [];
    return (
        !Object.keys(own).some((key) => isContentKey(own, key)) && !bound.some((key) => !NON_CONTENT_KEYS.includes(key))
    );
}

/**
 * Guided mode navigation from step `current` over `steps`, given the names of the currently invalid steps:
 * `{ backStep, nextStep, canNext, lockedSteps }`. A step is locked (can't be reached yet) while a required step
 * before it is invalid; Next goes to the next step when it isn't locked. Back is always available on any step but
 * the first.
 */
export function guidedNav(steps, current, invalidSteps = []) {
    const names = steps.map((step) => step.name);
    const index = names.indexOf(current);
    const lockedSteps = [];
    let blocked = false;
    steps.forEach((step) => {
        if (blocked) {
            lockedSteps.push(step.name);
        }
        blocked = blocked || (step.required && invalidSteps.includes(step.name));
    });
    const backStep = index > 0 ? names[index - 1] : null;
    const nextStep = index >= 0 && index < names.length - 1 ? names[index + 1] : null;
    return { backStep, nextStep, canNext: Boolean(nextStep) && !lockedSteps.includes(nextStep), lockedSteps };
}