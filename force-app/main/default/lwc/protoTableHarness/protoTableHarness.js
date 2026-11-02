// Plan: Four structural variants of the Table Widget (A: Custom SLDS 1/2 <table>, B: lightning-datatable + companion drawer, C: lightning-tree-grid, SPLIT: Side-by-side comparison), switchable via ?c__variant= and the floating bottom bar.
import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import queryTablePage from '@salesforce/apex/ProtoTableQueryService.queryTablePage';
import fetchChildRows from '@salesforce/apex/ProtoTableQueryService.fetchChildRows';
import seedPrototypeData from '@salesforce/apex/ProtoTableQueryService.seedPrototypeData';

const VARIANTS = [
    {
        key: 'A',
        shortLabel: 'A: Custom SLDS <table>',
        fullLabel: 'A — Custom SLDS 1/2 <table class="slds-table"> (Inline Child Sub-Rows + Smart Links + Highlight)'
    },
    {
        key: 'B',
        shortLabel: 'B: lightning-datatable',
        fullLabel: 'B — Standard lightning-datatable (Flattened Dot-Paths + Separate Child Drawer)'
    },
    {
        key: 'C',
        shortLabel: 'C: lightning-tree-grid',
        fullLabel: 'C — Standard lightning-tree-grid (Homogeneous _children Columns + No Infinite Scroll)'
    },
    {
        key: 'SPLIT',
        shortLabel: 'SPLIT: Side-by-Side',
        fullLabel: 'SPLIT — Side-by-Side Live Compare (Custom SLDS <table> vs lightning-datatable / tree-grid)'
    }
];

const DATATABLE_COLUMNS = [
    {
        label: 'Case #',
        fieldName: 'caseUrl',
        type: 'url',
        sortable: true,
        initialWidth: 110,
        typeAttributes: { label: { fieldName: 'caseNumber' }, target: '_self' }
    },
    {
        label: 'Subject',
        fieldName: 'subject',
        type: 'text',
        sortable: true,
        wrapText: false
    },
    {
        label: 'Account.Name (1-hop)',
        fieldName: 'accountUrl',
        type: 'url',
        sortable: true,
        typeAttributes: { label: { fieldName: 'accountName' }, target: '_self' }
    },
    {
        label: 'Contact.Name (1-hop)',
        fieldName: 'contactUrl',
        type: 'url',
        sortable: true,
        typeAttributes: { label: { fieldName: 'contactName' }, target: '_self' }
    },
    {
        label: 'Status',
        fieldName: 'status',
        type: 'text',
        sortable: true,
        initialWidth: 110
    },
    {
        label: 'Priority',
        fieldName: 'priority',
        type: 'text',
        sortable: true,
        initialWidth: 100
    },
    {
        label: 'Children',
        fieldName: 'childSummaryLabel',
        type: 'text',
        initialWidth: 135
    },
    {
        type: 'button',
        initialWidth: 135,
        typeAttributes: {
            label: { fieldName: 'drawerBtnLabel' },
            name: 'view_children',
            variant: 'base'
        }
    }
];

const TREE_GRID_COLUMNS = [
    {
        label: 'Case # / Child Author',
        fieldName: 'treePrimaryLabel',
        type: 'text',
        initialWidth: 185
    },
    {
        label: 'Subject / Child Comment or Feed Body (Forced Shared Column)',
        fieldName: 'treeBodyLabel',
        type: 'text'
    },
    {
        label: 'Account.Name',
        fieldName: 'accountName',
        type: 'text',
        initialWidth: 170
    },
    {
        label: 'Status / Match',
        fieldName: 'treeStatusLabel',
        type: 'text',
        initialWidth: 140
    },
    {
        label: 'Priority',
        fieldName: 'priority',
        type: 'text',
        initialWidth: 100
    }
];

export default class ProtoTableHarness extends NavigationMixin(LightningElement) {
    @api boardId = 'default';

    currentVariant = 'A';
    pageRef;

    // Filter & Engine controls
    searchText = '';
    statusFilter = 'ALL';
    priorityFilter = 'ALL';
    childMode = 'CASE_COMMENT'; // CASE_COMMENT | FEED_ITEM
    childFetchStrategy = 'LAZY_AND_SEARCH_BATCH'; // LAZY_AND_SEARCH_BATCH | EMBEDDED_SUBQUERY
    searchStrategy = 'HYBRID'; // HYBRID | SOSL_ONLY | LIKE_ONLY
    paginationStrategy = 'OFFSET'; // OFFSET | KEYSET
    sortBy = 'CaseNumber';
    sortDirection = 'ASC';
    pageSize = 25;

    // Runtime state
    rows = [];
    totalCount = 0;
    totalCountDisplay = '0';
    hasMore = false;
    nextOffset = 0;
    nextCursorSortValue = null;
    nextCursorLastId = null;
    telemetry = null;
    isLoading = false;
    isLoadingMore = false;
    isSeeding = false;
    errorMessage = '';
    seedStatusMessage = '';
    selectedDatatableRow = null;

    _searchDebounceTimer;
    _keyHandler;

    datatableColumns = DATATABLE_COLUMNS;
    treeGridColumns = TREE_GRID_COLUMNS;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this.pageRef = pageRef;
        if (pageRef && pageRef.state && pageRef.state.c__variant) {
            const candidate = String(pageRef.state.c__variant).toUpperCase();
            if (VARIANTS.some((v) => v.key === candidate)) {
                this.currentVariant = candidate;
            }
        }
    }

    connectedCallback() {
        this._keyHandler = this.handleGlobalKeydown.bind(this);
        window.addEventListener('keydown', this._keyHandler);
        this.loadFirstPage();
    }

    disconnectedCallback() {
        if (this._keyHandler) {
            window.removeEventListener('keydown', this._keyHandler);
        }
    }

    handleGlobalKeydown(event) {
        const tag = event.target && event.target.tagName ? event.target.tagName.toLowerCase() : '';
        if (
            tag === 'input' ||
            tag === 'textarea' ||
            tag === 'select' ||
            tag === 'lightning-input' ||
            tag === 'lightning-combobox' ||
            (event.target && event.target.isContentEditable)
        ) {
            return;
        }
        if (event.key === 'ArrowLeft') {
            event.preventDefault();
            this.cycleVariant(-1);
        } else if (event.key === 'ArrowRight') {
            event.preventDefault();
            this.cycleVariant(1);
        }
    }

    // Variant Switcher helpers
    get variantItems() {
        return VARIANTS.map((v) => ({
            ...v,
            pillClass: v.key === this.currentVariant ? 'proto-switcher-pill-active' : 'proto-switcher-pill'
        }));
    }

    get currentVariantLabel() {
        const found = VARIANTS.find((v) => v.key === this.currentVariant);
        return found ? found.fullLabel : this.currentVariant;
    }

    get isVariantA() {
        return this.currentVariant === 'A';
    }

    get isVariantB() {
        return this.currentVariant === 'B';
    }

    get isVariantC() {
        return this.currentVariant === 'C';
    }

    get isVariantSplit() {
        return this.currentVariant === 'SPLIT';
    }

    handlePrevVariant() {
        this.cycleVariant(-1);
    }

    handleNextVariant() {
        this.cycleVariant(1);
    }

    handleSelectVariant(event) {
        const targetKey = event.currentTarget.dataset.variant;
        if (targetKey) {
            this.setVariant(targetKey);
        }
    }

    cycleVariant(delta) {
        const idx = VARIANTS.findIndex((v) => v.key === this.currentVariant);
        const nextIdx = (idx + delta + VARIANTS.length) % VARIANTS.length;
        this.setVariant(VARIANTS[nextIdx].key);
    }

    setVariant(variantKey) {
        this.currentVariant = variantKey;
        if (this.pageRef) {
            const nextState = { ...(this.pageRef.state || {}), c__variant: variantKey };
            this[NavigationMixin.Navigate](
                {
                    type: this.pageRef.type,
                    attributes: this.pageRef.attributes,
                    state: nextState
                },
                true
            );
        }
    }

    // Combobox options
    get statusOptions() {
        return [
            { label: 'All Statuses', value: 'ALL' },
            { label: 'New', value: 'New' },
            { label: 'Working', value: 'Working' },
            { label: 'Escalated', value: 'Escalated' },
            { label: 'Closed', value: 'Closed' }
        ];
    }

    get priorityOptions() {
        return [
            { label: 'All Priorities', value: 'ALL' },
            { label: 'High', value: 'High' },
            { label: 'Medium', value: 'Medium' },
            { label: 'Low', value: 'Low' }
        ];
    }

    get childModeOptions() {
        return [
            { label: 'CaseComment (CaseComments)', value: 'CASE_COMMENT' },
            { label: 'FeedItem (Chatter Feeds)', value: 'FEED_ITEM' }
        ];
    }

    get childFetchStrategyOptions() {
        return [
            { label: 'Lazy on Expand + Batch on Search Match', value: 'LAZY_AND_SEARCH_BATCH' },
            { label: 'Embedded SOQL Subquery (Every Row)', value: 'EMBEDDED_SUBQUERY' }
        ];
    }

    get searchStrategyOptions() {
        return [
            { label: 'Hybrid (SOSL + SOQL LIKE Union)', value: 'HYBRID' },
            { label: 'SOSL Only (FIND IN ALL FIELDS)', value: 'SOSL_ONLY' },
            { label: 'SOQL LIKE Only (Synchronous)', value: 'LIKE_ONLY' }
        ];
    }

    get paginationStrategyOptions() {
        return [
            { label: 'OFFSET (LIMIT :n OFFSET :o, 2,000 cap)', value: 'OFFSET' },
            { label: 'Keyset Cursor ((SortVal, Id), Unlimited)', value: 'KEYSET' }
        ];
    }

    // Header sort indicators
    get columnsMeta() {
        const cols = [
            { fieldPath: 'CaseNumber', label: 'Case #', width: 'width: 110px;' },
            { fieldPath: 'Subject', label: 'Subject', width: 'width: 28%;' },
            { fieldPath: 'Account.Name', label: 'Account.Name', width: 'width: 16%;' },
            { fieldPath: 'Contact.Name', label: 'Contact.Name', width: 'width: 13%;' },
            { fieldPath: 'Status', label: 'Status', width: 'width: 105px;' },
            { fieldPath: 'Priority', label: 'Priority', width: 'width: 95px;' },
            { fieldPath: 'CreatedDate', label: 'Created', width: 'width: 120px;' }
        ];
        return cols.map((col) => {
            const isSorted = this.sortBy === col.fieldPath;
            const arrow = isSorted ? (this.sortDirection === 'ASC' ? ' ↑' : ' ↓') : '';
            return {
                ...col,
                headerText: col.label + arrow,
                ariaSort: isSorted ? (this.sortDirection === 'ASC' ? 'ascending' : 'descending') : 'none'
            };
        });
    }

    get loadedRowCount() {
        return this.rows.length;
    }

    get childObjectLabel() {
        return this.childMode === 'FEED_ITEM' ? 'FeedItems (Feeds)' : 'CaseComments';
    }

    get datatableSortDirection() {
        return this.sortDirection === 'ASC' ? 'asc' : 'desc';
    }

    get treeGridRows() {
        return this.rows.map((r) => {
            const childNodes = (r.children || []).map((ch) => ({
                id: ch.id,
                treePrimaryLabel: '↳ ' + (ch.authorName || 'Author'),
                treeBodyLabel: (ch.isSearchMatch ? '★ [MATCH] ' : '') + (ch.body || ''),
                accountName: '— (Child ' + ch.childType + ')',
                treeStatusLabel: ch.isPublished ? 'Published' : 'Internal',
                priority: ''
            }));
            return {
                ...r,
                treePrimaryLabel: r.caseNumber + (r.childCount ? ` (${r.childCount})` : ''),
                treeBodyLabel: r.subject,
                treeStatusLabel: r.matchedOnChild ? `${r.status} [Child Hit]` : r.status,
                _children: childNodes.length > 0 ? childNodes : undefined
            };
        });
    }

    get treeGridExpandedIds() {
        return this.rows.filter((r) => r.isExpanded).map((r) => r.id);
    }

    // Filter handlers
    handleSearchInput(event) {
        const val = event.target.value || '';
        this.searchText = val;
        window.clearTimeout(this._searchDebounceTimer);
        if (val.length === 0 || val.length >= 2) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._searchDebounceTimer = window.setTimeout(() => {
                this.loadFirstPage();
            }, 300);
        }
    }

    handleSearchKeyUp(event) {
        if (event.key === 'Enter') {
            window.clearTimeout(this._searchDebounceTimer);
            this.loadFirstPage();
        }
    }

    handleQuickPreset(event) {
        const term = event.currentTarget.dataset.term || '';
        this.searchText = term;
        this.loadFirstPage();
    }

    handleStatusChange(event) {
        this.statusFilter = event.detail.value;
        this.loadFirstPage();
    }

    handlePriorityChange(event) {
        this.priorityFilter = event.detail.value;
        this.loadFirstPage();
    }

    handleChildModeChange(event) {
        this.childMode = event.detail.value;
        this.loadFirstPage();
    }

    handleChildFetchStrategyChange(event) {
        this.childFetchStrategy = event.detail.value;
        this.loadFirstPage();
    }

    handleSearchStrategyChange(event) {
        this.searchStrategy = event.detail.value;
        this.loadFirstPage();
    }

    handlePaginationStrategyChange(event) {
        this.paginationStrategy = event.detail.value;
        this.loadFirstPage();
    }

    handleResetFilters() {
        this.searchText = '';
        this.statusFilter = 'ALL';
        this.priorityFilter = 'ALL';
        this.errorMessage = '';
        this.loadFirstPage();
    }

    // Column sort
    handleHeaderSort(event) {
        const fieldPath = event.currentTarget.dataset.field;
        if (!fieldPath) return;
        if (this.sortBy === fieldPath) {
            this.sortDirection = this.sortDirection === 'ASC' ? 'DESC' : 'ASC';
        } else {
            this.sortBy = fieldPath;
            this.sortDirection = 'ASC';
        }
        this.loadFirstPage();
    }

    handleDatatableSort(event) {
        const fieldName = event.detail.fieldName;
        const sortDirection = event.detail.sortDirection === 'asc' ? 'ASC' : 'DESC';
        const fieldMap = {
            caseUrl: 'CaseNumber',
            subject: 'Subject',
            accountUrl: 'Account.Name',
            contactUrl: 'Contact.Name',
            status: 'Status',
            priority: 'Priority'
        };
        this.sortBy = fieldMap[fieldName] || 'CaseNumber';
        this.sortDirection = sortDirection;
        this.loadFirstPage();
    }

    // Data loading
    async loadFirstPage(customStartOffset = 0) {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const req = this.buildRequestPayload(customStartOffset, null, null);
            const resp = await queryTablePage({ requestJson: JSON.stringify(req) });
            const decorated = this.decorateRows(resp.rows || []);
            this.rows = decorated;
            this.totalCount = resp.totalCount || 0;
            this.totalCountDisplay = resp.totalCountDisplay || '0';
            this.hasMore = Boolean(resp.hasMore);
            this.nextOffset = resp.nextOffset || 0;
            this.nextCursorSortValue = resp.nextCursorSortValue || null;
            this.nextCursorLastId = resp.nextCursorLastId || null;
            this.telemetry = resp.telemetry || null;
            this.selectedDatatableRow = decorated.find((r) => r.matchedOnChild) || decorated[0] || null;
        } catch (err) {
            this.errorMessage = this.extractErrorMessage(err);
        } finally {
            this.isLoading = false;
        }
    }

    async loadNextPage() {
        if (this.isLoading || this.isLoadingMore || !this.hasMore) {
            return;
        }
        if (this.paginationStrategy === 'OFFSET' && this.nextOffset > 2000) {
            this.errorMessage =
                'OFFSET ceiling reached (2,000 rows max in SOQL). Switch Pagination Strategy to Keyset Cursor to scroll past 2,000 rows without limits.';
            return;
        }
        this.isLoadingMore = true;
        this.errorMessage = '';
        try {
            const req = this.buildRequestPayload(
                this.nextOffset,
                this.nextCursorSortValue,
                this.nextCursorLastId
            );
            const resp = await queryTablePage({ requestJson: JSON.stringify(req) });
            const newRows = this.decorateRows(resp.rows || []);
            this.rows = [...this.rows, ...newRows];
            this.totalCount = resp.totalCount || this.totalCount;
            this.totalCountDisplay = resp.totalCountDisplay || this.totalCountDisplay;
            this.hasMore = Boolean(resp.hasMore);
            this.nextOffset = resp.nextOffset || this.rows.length;
            this.nextCursorSortValue = resp.nextCursorSortValue || null;
            this.nextCursorLastId = resp.nextCursorLastId || null;
            this.telemetry = resp.telemetry || this.telemetry;
        } catch (err) {
            this.errorMessage = this.extractErrorMessage(err);
        } finally {
            this.isLoadingMore = false;
        }
    }

    handleViewportScroll(event) {
        const el = event.target;
        if (!el || this.isLoading || this.isLoadingMore || !this.hasMore) {
            return;
        }
        const remaining = el.scrollHeight - el.scrollTop - el.clientHeight;
        if (remaining < 90) {
            this.loadNextPage();
        }
    }

    handleLoadMoreClick() {
        this.loadNextPage();
    }

    handleDatatableLoadMore() {
        this.loadNextPage();
    }

    // Offset boundary probes
    handleJumpOffset1975() {
        this.paginationStrategy = 'OFFSET';
        this.loadFirstPage(1975);
    }

    handleProbeOffset2025Error() {
        this.paginationStrategy = 'OFFSET';
        this.loadFirstPage(2025);
    }

    // Row expansion (Chevron toggle)
    async handleToggleExpand(event) {
        const rowId = event.currentTarget.dataset.rowid;
        const targetRow = this.rows.find((r) => r.id === rowId);
        if (!targetRow) return;

        const nextExpanded = !targetRow.isExpanded;
        let loadedChildren = targetRow.children || [];
        let isFetchingChildren = false;

        if (nextExpanded && loadedChildren.length === 0 && targetRow.childCount > 0) {
            isFetchingChildren = true;
            this.rows = this.rows.map((r) =>
                r.id === rowId ? { ...r, isExpanded: true, isFetchingChildren: true } : r
            );
            try {
                const rawChildren = await fetchChildRows({
                    parentId: rowId,
                    childMode: this.childMode,
                    searchText: this.searchText
                });
                loadedChildren = this.decorateChildren(rawChildren || []);
            } catch (err) {
                this.errorMessage = this.extractErrorMessage(err);
            } finally {
                isFetchingChildren = false;
            }
        }

        this.rows = this.rows.map((r) => {
            if (r.id !== rowId) return r;
            return {
                ...r,
                isExpanded: nextExpanded,
                isFetchingChildren,
                expandIcon: nextExpanded ? '▾' : '▸',
                trClass: nextExpanded ? 'proto-parent-rowExpanded' : '',
                children: loadedChildren
            };
        });
    }

    handleDatatableRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'view_children' && row) {
            this.selectedDatatableRow = row;
            if ((!row.children || row.children.length === 0) && row.childCount > 0) {
                fetchChildRows({
                    parentId: row.id,
                    childMode: this.childMode,
                    searchText: this.searchText
                }).then((rawChildren) => {
                    const decoratedChildren = this.decorateChildren(rawChildren || []);
                    this.selectedDatatableRow = { ...row, children: decoratedChildren };
                });
            }
        }
    }

    // Smart record navigation link click
    handleRecordLinkClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.recordid;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                actionName: 'view'
            }
        });
    }

    // Seeding test records
    async handleSeed260() {
        await this.runSeed(260);
    }

    async handleSeedBatchTowards2050() {
        this.isSeeding = true;
        this.seedStatusMessage = 'Seeding high-volume Cases in chunks toward 2,050 rows...';
        try {
            let totalCases = 0;
            for (let pass = 0; pass < 5; pass++) {
                // eslint-disable-next-line no-await-in-loop
                const res = await seedPrototypeData({ desiredTotalCases: 2050 });
                totalCases = res.totalCases || 0;
                this.seedStatusMessage = `Seeded ${totalCases} total Cases (${res.totalCaseComments} CaseComments)...`;
                if (totalCases >= 2050) {
                    break;
                }
            }
            await this.loadFirstPage();
        } catch (err) {
            this.errorMessage = this.extractErrorMessage(err);
        } finally {
            this.isSeeding = false;
        }
    }

    async runSeed(targetCount) {
        this.isSeeding = true;
        this.seedStatusMessage = 'Seeding parent Cases + child CaseComments & FeedItems...';
        try {
            const res = await seedPrototypeData({ desiredTotalCases: targetCount });
            this.seedStatusMessage = `Ready: ${res.totalCases} Cases (+${res.createdCasesInBatch} new), ${res.totalCaseComments} CaseComments (+${res.createdCommentsInBatch} new, +${res.createdFeedsInBatch} FeedItems).`;
            await this.loadFirstPage();
        } catch (err) {
            this.errorMessage = this.extractErrorMessage(err);
        } finally {
            this.isSeeding = false;
        }
    }

    // Helpers
    buildRequestPayload(offsetVal, cursorSortValue, cursorLastId) {
        return {
            statuses: this.statusFilter !== 'ALL' ? [this.statusFilter] : [],
            priorities: this.priorityFilter !== 'ALL' ? [this.priorityFilter] : [],
            accountId: null,
            searchText: this.searchText,
            searchStrategy: this.searchStrategy,
            childMode: this.childMode,
            childFetchStrategy: this.childFetchStrategy,
            paginationStrategy: this.paginationStrategy,
            sortBy: this.sortBy,
            sortDirection: this.sortDirection,
            pageSize: this.pageSize,
            offsetVal,
            cursorSortValue,
            cursorLastId
        };
    }

    decorateRows(rawRows) {
        return rawRows.map((row) => {
            const isExpanded = Boolean(row.autoExpanded);
            const children = this.decorateChildren(row.children || []);
            const childCount = row.childCount || 0;
            return {
                ...row,
                isExpanded,
                isFetchingChildren: false,
                expandIcon: isExpanded ? '▾' : '▸',
                hasChildren: childCount > 0,
                trClass: isExpanded ? 'proto-parent-rowExpanded' : '',
                caseUrl: `/lightning/r/Case/${row.id}/view`,
                accountUrl: row.accountId ? `/lightning/r/Account/${row.accountId}/view` : '',
                contactUrl: row.contactId ? `/lightning/r/Contact/${row.contactId}/view` : '',
                ownerUrl: row.ownerId ? `/lightning/r/User/${row.ownerId}/view` : '',
                subjectSegments: this.splitHighlightSegments(row.subject || '', this.searchText),
                accountSegments: this.splitHighlightSegments(row.accountName || '—', this.searchText),
                contactSegments: this.splitHighlightSegments(row.contactName || '—', this.searchText),
                childSummaryLabel: row.matchedOnChild
                    ? `★ ${row.matchedChildCount}/${childCount} matched`
                    : `${childCount} items`,
                drawerBtnLabel: `Inspect (${childCount})`,
                children
            };
        });
    }

    decorateChildren(rawChildren) {
        return rawChildren.map((ch) => ({
            ...ch,
            childTrClass: ch.isSearchMatch ? 'proto-child-match-row' : '',
            publishedBadge: ch.isPublished ? 'Public' : 'Internal',
            bodySegments: this.splitHighlightSegments(ch.body || '', this.searchText)
        }));
    }

    splitHighlightSegments(text, term) {
        const safeText = String(text || '');
        const cleanTerm = String(term || '').trim();
        if (!cleanTerm || cleanTerm.length < 2) {
            return [{ key: '0', text: safeText, isMatch: false }];
        }
        const escaped = cleanTerm.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const regex = new RegExp(`(${escaped})`, 'gi');
        const parts = safeText.split(regex);
        return parts
            .filter((p) => p.length > 0)
            .map((part, idx) => ({
                key: String(idx),
                text: part,
                isMatch: part.toLowerCase() === cleanTerm.toLowerCase()
            }));
    }

    extractErrorMessage(err) {
        if (!err) return 'Unknown error';
        if (err.body && err.body.message) return err.body.message;
        if (err.message) return err.message;
        return JSON.stringify(err);
    }
}