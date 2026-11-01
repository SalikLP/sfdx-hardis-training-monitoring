import { LightningElement, api, wire } from 'lwc';
import { subscribe, unsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import PROTO_BOARD_FILTER_CHANNEL from '@salesforce/messageChannel/ProtoBoardFilter__c';
import { subscribeBoardFilter } from 'c/protoBoardStore';

const SAMPLE_DEALS = [
    { id: '1', name: 'Acme Solar Expansion', stage: 'Prospecting', owner: 'ME', amountNum: 120000, amount: '$120,000' },
    { id: '2', name: 'Global Media Cloud', stage: 'Qualification', owner: 'TEAM_ENT', amountNum: 250000, amount: '$250,000' },
    { id: '3', name: 'Northwind Grid Upgrade', stage: 'Proposal/Price Quote', owner: 'ME', amountNum: 480000, amount: '$480,000' },
    { id: '4', name: 'Stark Clean Energy', stage: 'Closed Won', owner: 'ME', amountNum: 850000, amount: '$850,000' },
    { id: '5', name: 'Wayne Industrial IoT', stage: 'Closed Won', owner: 'TEAM_ENT', amountNum: 620000, amount: '$620,000' }
];

export default class ProtoBoardWidget extends LightningElement {
    @api title = 'Board Widget (PROTOTYPE)';
    @api widgetType = 'metric'; // metric | bar | table
    @api recordId;

    _boardId = 'default';
    _filterContextJson = '';

    currentState = null;
    lastTransport = 'none (initial)';
    updateCount = 0;

    lmsSubscription = null;
    storeUnsubscribe = null;

    @wire(MessageContext)
    messageContext;

    @api
    get boardId() {
        return this._boardId;
    }
    set boardId(val) {
        const nextId = val || 'default';
        if (nextId !== this._boardId) {
            this._boardId = nextId;
            this.setupStoreSubscription();
        }
    }

    @api
    get filterContextJson() {
        return this._filterContextJson;
    }
    set filterContextJson(val) {
        this._filterContextJson = val;
        if (val) {
            try {
                const parsed = JSON.parse(val);
                this.applyFilterState(parsed, 'FlowAttributeChangeEvent (@api filterContextJson)');
            } catch (e) {
                // ignore malformed json
            }
        }
    }

    get effectiveBoardId() {
        return this._boardId || 'default';
    }

    get iconName() {
        if (this.widgetType === 'bar') return 'utility:chart';
        if (this.widgetType === 'table') return 'utility:table';
        return 'utility:metrics';
    }

    get isMetric() {
        return !this.widgetType || this.widgetType === 'metric';
    }

    get isBar() {
        return this.widgetType === 'bar';
    }

    get isTable() {
        return this.widgetType === 'table';
    }

    get activeStage() {
        return this.currentState?.filters?.stage || 'ALL';
    }

    get activeOwner() {
        return this.currentState?.filters?.ownerScope || 'ALL';
    }

    get activeDateRange() {
        return this.currentState?.filters?.dateRange || 'THIS_QUARTER';
    }

    get effectiveRecordContext() {
        return this.currentState?.recordId || this.recordId || 'None (App/Home)';
    }

    get filteredDeals() {
        return SAMPLE_DEALS.filter((d) => {
            const matchStage = this.activeStage === 'ALL' || d.stage === this.activeStage;
            const matchOwner = this.activeOwner === 'ALL' || d.owner === this.activeOwner;
            return matchStage && matchOwner;
        });
    }

    get simulatedMetricValue() {
        const dateMultiplier =
            this.activeDateRange === 'THIS_MONTH' ? 0.4 :
            this.activeDateRange === 'LAST_N_DAYS:30' ? 0.5 :
            this.activeDateRange === 'THIS_YEAR' ? 1.5 : 1.0;
        const sum = this.filteredDeals.reduce((acc, d) => acc + d.amountNum, 0) * dateMultiplier;
        return '$' + Math.round(sum).toLocaleString();
    }

    get simulatedSubtitle() {
        return `${this.filteredDeals.length} matching deals (${this.activeDateRange})`;
    }

    get simulatedBars() {
        const stages = ['Prospecting', 'Qualification', 'Proposal/Price Quote', 'Closed Won'];
        const deals = this.filteredDeals;
        const max = 850000;
        return stages.map((st) => {
            const sum = deals.filter((d) => d.stage === st).reduce((a, b) => a + b.amountNum, 0);
            const pct = Math.min(100, Math.round((sum / max) * 100));
            return {
                label: st,
                displayValue: '$' + sum.toLocaleString(),
                barStyle: `width: ${pct}%; height: 100%; background: #0176d3;`
            };
        });
    }

    get simulatedRows() {
        return this.filteredDeals;
    }

    connectedCallback() {
        this.setupStoreSubscription();
        this.setupLmsSubscription();
    }

    disconnectedCallback() {
        if (this.storeUnsubscribe) {
            this.storeUnsubscribe();
            this.storeUnsubscribe = null;
        }
        if (this.lmsSubscription) {
            unsubscribe(this.lmsSubscription);
            this.lmsSubscription = null;
        }
    }

    setupStoreSubscription() {
        if (this.storeUnsubscribe) {
            this.storeUnsubscribe();
        }
        this.storeUnsubscribe = subscribeBoardFilter(this.effectiveBoardId, (stateObj) => {
            this.applyFilterState(stateObj, 'In-Memory Store (c/protoBoardStore)');
        });
    }

    setupLmsSubscription() {
        if (this.lmsSubscription || !this.messageContext) {
            return;
        }
        try {
            this.lmsSubscription = subscribe(
                this.messageContext,
                PROTO_BOARD_FILTER_CHANNEL,
                (message) => {
                    if (message && message.boardId === this.effectiveBoardId && message.filterState) {
                        try {
                            const parsed = JSON.parse(message.filterState);
                            this.applyFilterState(parsed, 'LMS (ProtoBoardFilter__c)');
                        } catch (e) {
                            // ignore
                        }
                    }
                },
                { scope: APPLICATION_SCOPE }
            );
        } catch (e) {
            // ignore if LMS unavailable
        }
    }

    applyFilterState(stateObj, sourceLabel) {
        if (!stateObj) return;
        const prevUpdatedAt = this.currentState?.updatedAt;
        this.currentState = stateObj;
        if (prevUpdatedAt !== stateObj.updatedAt) {
            this.updateCount += 1;
            this.lastTransport = sourceLabel;
        } else {
            this.lastTransport = `${this.lastTransport} + ${sourceLabel}`;
        }
    }
}