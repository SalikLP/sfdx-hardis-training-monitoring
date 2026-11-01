import { LightningElement, api, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import PROTO_BOARD_FILTER_CHANNEL from '@salesforce/messageChannel/ProtoBoardFilter__c';
import { publishBoardFilter } from 'c/protoBoardStore';

export default class ProtoFilterWidget extends LightningElement {
    @api title = 'Board Filter Bar (PROTOTYPE)';
    _boardId = 'default';
    _recordId = '';
    _filterContextJson = '';

    stage = 'ALL';
    ownerScope = 'ALL';
    dateRange = 'THIS_QUARTER';

    @wire(MessageContext)
    messageContext;

    @api
    get boardId() {
        return this._boardId;
    }
    set boardId(val) {
        this._boardId = val || 'default';
        this.broadcastFilterState('boardId-setter');
    }

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(val) {
        this._recordId = val || '';
        this.broadcastFilterState('recordId-setter');
    }

    @api
    get filterContextJson() {
        return this._filterContextJson;
    }
    set filterContextJson(val) {
        this._filterContextJson = val;
    }

    get effectiveBoardId() {
        return this._boardId || 'default';
    }

    get stageOptions() {
        return [
            { label: 'All Stages', value: 'ALL' },
            { label: 'Prospecting', value: 'Prospecting' },
            { label: 'Qualification', value: 'Qualification' },
            { label: 'Proposal/Price Quote', value: 'Proposal/Price Quote' },
            { label: 'Closed Won', value: 'Closed Won' }
        ];
    }

    get ownerOptions() {
        return [
            { label: 'All Owners', value: 'ALL' },
            { label: 'My Records ($User.Id)', value: 'ME' },
            { label: 'Enterprise Team', value: 'TEAM_ENT' }
        ];
    }

    get dateRangeOptions() {
        return [
            { label: 'This Quarter', value: 'THIS_QUARTER' },
            { label: 'This Month', value: 'THIS_MONTH' },
            { label: 'This Year', value: 'THIS_YEAR' },
            { label: 'Last 30 Days', value: 'LAST_N_DAYS:30' }
        ];
    }

    connectedCallback() {
        this.broadcastFilterState('connectedCallback');
    }

    handleStageChange(event) {
        this.stage = event.detail.value;
        this.broadcastFilterState('user-stage');
    }

    handleOwnerChange(event) {
        this.ownerScope = event.detail.value;
        this.broadcastFilterState('user-owner');
    }

    handleDateRangeChange(event) {
        this.dateRange = event.detail.value;
        this.broadcastFilterState('user-date');
    }

    handleReset() {
        this.stage = 'ALL';
        this.ownerScope = 'ALL';
        this.dateRange = 'THIS_QUARTER';
        this.broadcastFilterState('reset');
    }

    broadcastFilterState(trigger) {
        const stateObj = {
            boardId: this.effectiveBoardId,
            recordId: this._recordId || null,
            filters: {
                stage: this.stage,
                ownerScope: this.ownerScope,
                dateRange: this.dateRange
            },
            trigger,
            updatedAt: new Date().toISOString()
        };
        const serialized = JSON.stringify(stateObj);
        this._filterContextJson = serialized;

        // 1. In-memory shared LWC module (instant, handles late-joiners + Flow Debug)
        publishBoardFilter(this.effectiveBoardId, stateObj);

        // 2. Lightning Message Service (cross-DOM on App/Home/Record pages & embedded Flows)
        if (this.messageContext) {
            try {
                publish(this.messageContext, PROTO_BOARD_FILTER_CHANNEL, {
                    boardId: this.effectiveBoardId,
                    filterState: serialized,
                    source: 'LMS',
                    timestamp: stateObj.updatedAt
                });
            } catch (e) {
                // ignore if outside LMS context
            }
        }

        // 3. Flow Reactive Screen Component output event
        try {
            this.dispatchEvent(new FlowAttributeChangeEvent('filterContextJson', serialized));
        } catch (e) {
            // ignore if not in Flow runtime
        }
    }
}