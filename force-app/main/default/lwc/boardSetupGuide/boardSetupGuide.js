/**
 * Guided mode of the Setup dialog (ADR 0002), as pure functions over the step descriptors (`c/boardSetupSteps`).
 *
 * A Widget with no config yet opens in Guided mode: the steps run in order with Back / Next; Next is blocked while a
 * required step up to the current one is invalid; optional steps can be skipped (their defaults apply). A Widget with
 * config opens with free navigation between steps.
 */

/** Envelope keys that don't count as config: the title is set in the panel. */
const ENVELOPE_KEYS = ['version', 'widgetType', 'title'];

/**
 * True when the Setup dialog opens in Guided mode: the Widget has no config besides its envelope and no config key
 * bound to a Flow resource (`references`).
 */
export function opensGuided(config, references = {}) {
    const own = config && typeof config === 'object' ? Object.keys(config) : [];
    const bound = references && typeof references === 'object' ? Object.keys(references) : [];
    return !own.some((key) => !ENVELOPE_KEYS.includes(key)) && !bound.length;
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