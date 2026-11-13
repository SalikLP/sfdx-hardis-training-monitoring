import { LightningElement, api } from 'lwc';
import { applyChartConfig } from 'c/boardChartUtils';
import { effectivePanelsPerRow, legendFromConfig, shareValueScales, withoutLegend } from './panelLayout';

/**
 * Small multiples grid of the Chart widget: one titled Chart.js chart per Panel, laid out `panelsPerRow` per row
 * (fewer when a Panel would get narrower than ~200 px) at `panelHeight` px each, so the Widget grows with its rows and
 * never scrolls inside. The Panels share one value axis unless `independentScales`, and the grid draws one legend for
 * all of them (each chart's own legend is off).
 *
 * The Widget hands in the Chart.js constructor (`chartLibrary`) and `buildConfigs()`, returning a fresh
 * `Map<panelKey, config>`; the grid calls it whenever `drawVersion` changes or its Panels change, then creates, morphs
 * in place, or destroys each Panel's chart.
 */
export default class BoardChartPanelGrid extends LightningElement {
    /** `[{ key, label, headline }]`, in order (`headline`: the Panel headline text right of the title, or null). */
    @api panels = [];
    @api panelsPerRow = 3;
    @api panelHeight = 250;
    @api independentScales = false;
    @api chartLibrary;
    @api buildConfigs;

    /** The one legend `{ position, items }`, or null. */
    legend = null;
    measuredWidth = 0;

    _drawVersion = 0;
    _drawnKey = null;
    _charts = new Map();
    _resizeObserver = null;
    _isConnected = false;

    /** Bumped by the Widget when the Panels' data, settings or theme changed. */
    @api
    get drawVersion() {
        return this._drawVersion;
    }
    set drawVersion(value) {
        this._drawVersion = value;
        if (this._isConnected) {
            Promise.resolve().then(() => this.draw());
        }
    }

    connectedCallback() {
        this._isConnected = true;
    }

    disconnectedCallback() {
        this._isConnected = false;
        if (this._resizeObserver) {
            this._resizeObserver.disconnect();
            this._resizeObserver = null;
        }
        this._charts.forEach((entry) => entry.chart.destroy());
        this._charts = new Map();
        this._drawnKey = null;
    }

    renderedCallback() {
        this.measure();
        this.observeResize();
        this.draw();
    }

    get columns() {
        return effectivePanelsPerRow(this.panelsPerRow, this.measuredWidth);
    }

    get gridStyle() {
        return `--board-panel-columns: ${this.columns}; --board-panel-height: ${Number(this.panelHeight) || 250}px;`;
    }

    get hasLegend() {
        return Boolean(this.legend && this.legend.items.length);
    }

    get legendClass() {
        const position = this.legend && this.legend.position === 'bottom' ? 'bottom' : 'top';
        return `c-board-panel-legend c-board-panel-legend_${position}`;
    }

    get legendItems() {
        return (this.legend ? this.legend.items : []).map((item) => ({
            ...item,
            swatchStyle: `background-color: ${item.color};`
        }));
    }

    measure() {
        const grid = this.template.querySelector('.c-board-panel-grid');
        const width = grid ? grid.clientWidth : 0;
        if (width !== this.measuredWidth) {
            this.measuredWidth = width;
        }
    }

    observeResize() {
        const grid = this.template.querySelector('.c-board-panel-grid');
        if (this._resizeObserver || !grid || typeof ResizeObserver === 'undefined') {
            return;
        }
        this._resizeObserver = new ResizeObserver(() => this.measure());
        this._resizeObserver.observe(grid);
    }

    /** Draws every rendered Panel container once per `drawVersion` and set of containers. */
    draw() {
        if (!this._isConnected || typeof this.chartLibrary !== 'function' || typeof this.buildConfigs !== 'function') {
            return;
        }
        const containers = [...this.template.querySelectorAll('.c-board-panel-canvas')];
        const drawnKey = `${this._drawVersion}|${containers.map((container) => container.dataset.key).join('|')}`;
        if (drawnKey === this._drawnKey) {
            return;
        }
        this._drawnKey = drawnKey;
        const configs = this.buildConfigs();
        const drawn = containers
            .map((container) => ({ container, config: configs.get(container.dataset.key) }))
            .filter((entry) => entry.config);
        const legend = drawn.length ? legendFromConfig(drawn[0].config) : null;
        if (JSON.stringify(legend) !== JSON.stringify(this.legend)) {
            this.legend = legend;
        }
        if (!this.independentScales) {
            shareValueScales(drawn.map((entry) => entry.config));
        }
        const keep = new Set();
        drawn.forEach(({ container, config }) => {
            const key = container.dataset.key;
            keep.add(key);
            this.drawPanel(key, container, withoutLegend(config));
        });
        this._charts.forEach((entry, key) => {
            if (!keep.has(key)) {
                entry.chart.destroy();
                this._charts.delete(key);
            }
        });
    }

    drawPanel(key, container, config) {
        const existing = this._charts.get(key);
        // Chart.js can't morph one chart type into another, nor move to a new container: those get a new chart.
        if (existing && existing.container === container && existing.type === config.type) {
            applyChartConfig(existing.chart, config);
            existing.chart.update();
            return;
        }
        if (existing) {
            existing.chart.destroy();
        }
        container.textContent = '';
        const canvas = document.createElement('canvas');
        canvas.setAttribute('role', 'img');
        canvas.setAttribute('aria-label', this.panelLabel(key));
        container.appendChild(canvas);
        const Chart = this.chartLibrary;
        this._charts.set(key, { chart: new Chart(canvas, config), container, type: config.type });
    }

    panelLabel(key) {
        const panel = (this.panels || []).find((entry) => entry.key === key);
        return panel ? panel.label : key;
    }
}