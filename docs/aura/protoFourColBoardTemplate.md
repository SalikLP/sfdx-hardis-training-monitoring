<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# protoFourColBoardTemplate

## Aura Component attributes

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Component|
|Api Version|65|
|Description|Throwaway prototype 4-column Lightning page template|




<!-- Aura description -->

## Uses

No outbound Visualforce component, page, static resource or custom label reference found in the markup.

## Where Used

No reference to this component found in the project metadata.

## Source

### protoFourColBoardTemplate.cmp

```html
<aura:component implements="lightning:appHomeTemplate"
                description="PROTOTYPE: 1-4 Column Dashboard Page Template with Header, 4-Column KPI Row, and 2-Column Main Row">
    <aura:attribute name="header" type="Aura.Component[]" description="Full-width Filter Bar / Header Region"/>
    <aura:attribute name="col1" type="Aura.Component[]" description="4-Column Row: Column 1 (3/12)"/>
    <aura:attribute name="col2" type="Aura.Component[]" description="4-Column Row: Column 2 (3/12)"/>
    <aura:attribute name="col3" type="Aura.Component[]" description="4-Column Row: Column 3 (3/12)"/>
    <aura:attribute name="col4" type="Aura.Component[]" description="4-Column Row: Column 4 (3/12)"/>
    <aura:attribute name="mainLeft" type="Aura.Component[]" description="2-Column Row: Left (6/12)"/>
    <aura:attribute name="mainRight" type="Aura.Component[]" description="2-Column Row: Right (6/12)"/>
    <aura:attribute name="footer" type="Aura.Component[]" description="Full-width Footer / Secondary Board Region"/>

    <div>
        <!-- 1-Column Full Width Region -->
        <div class="slds-grid slds-wrap slds-m-bottom_small">
            <div class="slds-col slds-size_1-of-1">
                {!v.header}
            </div>
        </div>

        <!-- 4-Column Responsive Region -->
        <div class="slds-grid slds-wrap slds-gutters_small slds-m-bottom_small">
            <div class="slds-col slds-size_1-of-1 slds-medium-size_6-of-12 slds-large-size_3-of-12">
                {!v.col1}
            </div>
            <div class="slds-col slds-size_1-of-1 slds-medium-size_6-of-12 slds-large-size_3-of-12">
                {!v.col2}
            </div>
            <div class="slds-col slds-size_1-of-1 slds-medium-size_6-of-12 slds-large-size_3-of-12">
                {!v.col3}
            </div>
            <div class="slds-col slds-size_1-of-1 slds-medium-size_6-of-12 slds-large-size_3-of-12">
                {!v.col4}
            </div>
        </div>

        <!-- 2-Column Responsive Region -->
        <div class="slds-grid slds-wrap slds-gutters_small slds-m-bottom_small">
            <div class="slds-col slds-size_1-of-1 slds-large-size_6-of-12">
                {!v.mainLeft}
            </div>
            <div class="slds-col slds-size_1-of-1 slds-large-size_6-of-12">
                {!v.mainRight}
            </div>
        </div>

        <!-- Full Width Bottom Region -->
        <div class="slds-grid slds-wrap">
            <div class="slds-col slds-size_1-of-1">
                {!v.footer}
            </div>
        </div>
    </div>
</aura:component>
```

### protoFourColBoardTemplate.design

```html
<design:component label="Proto 4-Column Board Template (PROTOTYPE)">
    <design:supportedFormFactors>
        <design:supportedFormFactor type="Large"/>
        <design:supportedFormFactor type="Small"/>
    </design:supportedFormFactors>
    <flexipage:template>
        <flexipage:region name="header" defaultWidth="LARGE"/>
        <flexipage:region name="col1" defaultWidth="SMALL"/>
        <flexipage:region name="col2" defaultWidth="SMALL"/>
        <flexipage:region name="col3" defaultWidth="SMALL"/>
        <flexipage:region name="col4" defaultWidth="SMALL"/>
        <flexipage:region name="mainLeft" defaultWidth="MEDIUM"/>
        <flexipage:region name="mainRight" defaultWidth="MEDIUM"/>
        <flexipage:region name="footer" defaultWidth="LARGE"/>
    </flexipage:template>
</design:component>
```

## Files

- `protoFourColBoardTemplate.cmp`
- `protoFourColBoardTemplate.cmp-meta.xml`
- `protoFourColBoardTemplate.design`


[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
