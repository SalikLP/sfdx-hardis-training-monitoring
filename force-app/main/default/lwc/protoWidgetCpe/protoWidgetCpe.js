import { LightningElement, api } from 'lwc';

export default class ProtoWidgetCpe extends LightningElement {
    _inputVariables = [];
    _builderContext = {};

    @api
    get inputVariables() {
        return this._inputVariables;
    }
    set inputVariables(variables) {
        this._inputVariables = variables || [];
    }

    @api
    get builderContext() {
        return this._builderContext;
    }
    set builderContext(context) {
        this._builderContext = context || {};
    }

    @api
    validate() {
        const validity = [];
        if (!this.titleValue) {
            validity.push({
                key: 'title',
                errorString: 'Widget Title is required.'
            });
        }
        return validity;
    }

    get titleValue() {
        return this.getParamValue('title') || 'Pipeline Metric';
    }

    get widgetTypeValue() {
        return this.getParamValue('widgetType') || 'metric';
    }

    get boardIdValue() {
        return this.getParamValue('boardId') || 'default';
    }

    get filterContextRef() {
        return this.getParamValue('filterContextJson') || '';
    }

    get widgetTypeOptions() {
        return [
            { label: 'Metric Card (KPI)', value: 'metric' },
            { label: 'Horizontal/Vertical Bar Chart', value: 'bar' },
            { label: 'Data Table', value: 'table' }
        ];
    }

    get availableFilterWidgets() {
        const opts = [{ label: '-- None (Use LMS / Shared Store by Board ID) --', value: '' }];
        const screens = this._builderContext?.screens || [];
        screens.forEach((scr) => {
            (scr.fields || []).forEach((fld) => {
                if (fld.extensionName && fld.extensionName.includes('protoFilterWidget')) {
                    opts.push({
                        label: `${fld.name}.filterContextJson`,
                        value: `${fld.name}.filterContextJson`
                    });
                }
            });
        });
        return opts;
    }

    getParamValue(name) {
        const param = this._inputVariables.find((p) => p.name === name);
        return param ? param.value : '';
    }

    handleTitleChange(event) {
        this.dispatchChange('title', event.detail.value, 'String');
    }

    handleTypeChange(event) {
        this.dispatchChange('widgetType', event.detail.value, 'String');
    }

    handleBoardIdChange(event) {
        this.dispatchChange('boardId', event.detail.value, 'String');
    }

    handleReactiveBindChange(event) {
        const val = event.detail.value;
        this.dispatchChange('filterContextJson', val, val ? 'reference' : 'String');
    }

    dispatchChange(name, newValue, newValueDataType) {
        this.dispatchEvent(
            new CustomEvent('configuration_editor_input_value_changed', {
                bubbles: true,
                cancelable: false,
                composed: true,
                detail: {
                    name,
                    newValue,
                    newValueDataType
                }
            })
        );
    }
}