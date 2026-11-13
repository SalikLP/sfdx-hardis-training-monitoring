import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { ConfigDialogMixin, baseFilterErrorsByIndex, baseFiltersFromTree, baseFiltersToTree } from 'c/boardCpeUtils';

const ID_PREFIX = 'bf';

/**
 * Base filters Config dialog: a large `LightningModal` that edits a draft of a data Widget's `baseFilters` with the
 * shared condition editor (`c-board-condition-editor`): conditions and AND / OR groups of conditions, matched with
 * AND or OR at the top level. Open it with
 * `openConfigDialog(BoardBaseFilterDialog, { label, description, value: baseFilters, objectApiName })`.
 * Widgets with a Setup dialog edit their Base filters in its Data step instead (`c-board-setup-base-filters`).
 *
 * `baseFilters` stays a list whose entries combine with AND (so existing flat lists load as one AND group); OR at the
 * top level is stored as a single OR group entry `{ id, logic: 'OR', conditions }` (`baseFiltersToTree` /
 * `baseFiltersFromTree`).
 *
 * Closes with `{ action: 'save', draft: baseFilters }` or `{ action: 'dismiss' }`. Save stays disabled while any
 * draft entry breaks the Base filter validation rules (`baseFilterErrorsByIndex`).
 */
export default class BoardBaseFilterDialog extends ConfigDialogMixin(LightningModal) {
    /** The Widget's `baseFilters`, already deep-copied by `openConfigDialog`. */
    @api value;
    /** Object the field pickers start from. */
    @api objectApiName;

    idPrefix = ID_PREFIX;
    /** The condition tree being edited: `{ logic, conditions }`. */
    tree = { logic: 'AND', conditions: [] };
    /** Id of the stored top-level OR group, kept when it is saved again. */
    rootGroupId = null;

    // ---- Draft (ConfigDialogMixin) -------------------------------------------------------------------------------

    initDraft(value) {
        const { tree, rootGroupId } = baseFiltersToTree(value);
        this.tree = tree;
        this.rootGroupId = rootGroupId;
    }

    /** The dialog has no master list: the condition editor edits the whole tree. */
    get draftItems() {
        return [];
    }

    setDraftItems() {}

    get errorsByIndex() {
        return baseFilterErrorsByIndex(this.draft);
    }

    get draft() {
        return baseFiltersFromTree(this.tree, this.rootGroupId);
    }

    handleConditionChange(event) {
        this.tree = event.detail.value;
    }
}