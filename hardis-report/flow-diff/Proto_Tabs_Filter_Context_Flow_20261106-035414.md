# PROTOTYPE Tabs Filter Context Flow

## Flow Diagram [(_View History_)](Proto_Tabs_Filter_Context_Flow-history.md)

```mermaid
%% If you read this, your Markdown visualizer does not handle MermaidJS syntax.
%% - If you are in VS Code, install extension `Markdown Preview Mermaid Support` at https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid
%% - If you are using sfdx-hardis, try to define env variable `MERMAID_MODES=cli,docker` ,then run again the command to regenerate markdown with SVG images.
%% - If you are within a Zensical site, define the mermaid custom fence in `mkdocs.yml` as described in https://zensical.org/docs/
%% - As a last resort, you can copy-paste this MermaidJS code into https://mermaid.live/ to see the flow diagram

flowchart TB
START(["START<br/><b>Screen Flow</b>"]):::startClass
click START "#general-information" "3040901246"

Screen1(["💻 <em></em><br/>Screen 1: conditional visibility"]):::screens
click Screen1 "#screen1" "2881302921"

Screen2(["💻 <em></em><br/>Screen 2: Filter context via Flow variable"]):::screens
click Screen2 "#screen2" "1382970883"

Screen1 --> Screen2
Screen2 --> END_Screen2
START -->  Screen1
END_Screen2(( END )):::endClass


classDef actionCalls fill:#D4E4FC,color:black,text-decoration:none,max-height:100px
classDef assignments fill:#FBEED7,color:black,text-decoration:none,max-height:100px
classDef collectionProcessors fill:#F0E3FA,color:black,text-decoration:none,max-height:100px
classDef customErrors fill:#FFE9E9,color:black,text-decoration:none,max-height:100px
classDef decisions fill:#FDEAF6,color:black,text-decoration:none,max-height:100px
classDef loops fill:#FDEAF6,color:black,text-decoration:none,max-height:100px
classDef recordCreates fill:#FFF8C9,color:black,text-decoration:none,max-height:100px
classDef recordDeletes fill:#FFF8C9,color:black,text-decoration:none,max-height:100px
classDef recordLookups fill:#EDEAFF,color:black,text-decoration:none,max-height:100px
classDef recordRollbacks fill:#FFF8C9,color:black,text-decoration:none,max-height:100px
classDef recordUpdates fill:#FFF8C9,color:black,text-decoration:none,max-height:100px
classDef screens fill:#DFF6FF,color:black,text-decoration:none,max-height:100px
classDef subflows fill:#D4E4FC,color:black,text-decoration:none,max-height:100px
classDef startClass fill:#D9F2E6,color:black,text-decoration:none,max-height:100px
classDef endClass fill:#F9BABA,color:black,text-decoration:none,max-height:100px
classDef transforms fill:#FDEAF6,color:black,text-decoration:none,max-height:100px


```

<!-- Flow description -->

## General Information

|<!-- -->|<!-- -->|
|:---|:---|
|Process Type|Flow|
|Label|PROTOTYPE Tabs Filter Context Flow|
|Status|Active|
|Environments|Default|
|Interview Label|PROTOTYPE Tabs Filter Context Flow {!$Flow.CurrentDateTime}|
|BuilderType (PM)|LightningFlowBuilder|
|CanvasMode (PM)|AUTO_LAYOUT_CANVAS|
|Connector|[Screen1](#screen1)|
|Next Node|[Screen1](#screen1)|


## Flow Nodes Details

### Screen1

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Screen|
|Label|Screen 1: conditional visibility|
|Allow Back|⬜|
|Allow Finish|✅|
|Allow Pause|⬜|
|Show Footer|✅|
|Show Header|✅|
|Connector|[Screen2](#screen2)|


#### View

|<!-- -->|<!-- -->|
|:---|:---|
|Data Type|String|
|Choice References|- choicePipeline<br/>- choicePerformance<br/>|
|Default Selected Choice Reference|choicePipeline|
|Field Text|View (acts as tabs)|
|Field Type|Radio Buttons|
|Is Required|⬜|
|Style Properties|verticalAlignment:<br/>&nbsp;&nbsp;stringValue: top<br/>width:<br/>&nbsp;&nbsp;stringValue: 12<br/>|




#### HideFilter

|<!-- -->|<!-- -->|
|:---|:---|
|Data Type|Boolean|
|Default Value|false|
|Field Text|Hide the Filter widget (tests Filter remount, persistence NONE)|
|Field Type|Input Field|
|Is Required|✅|
|Style Properties|verticalAlignment:<br/>&nbsp;&nbsp;stringValue: top<br/>width:<br/>&nbsp;&nbsp;stringValue: 12<br/>|




#### Filter1

|<!-- -->|<!-- -->|
|:---|:---|
|Extension Name|c:boardFilterWidget|
|Field Type|Component Instance|
|Inputs On Next Nav To Assoc Scrn|Use Stored Values|
|Is Required|✅|
|Store Output Automatically|✅|
|Style Properties|verticalAlignment:<br/>&nbsp;&nbsp;stringValue: top<br/>width:<br/>&nbsp;&nbsp;stringValue: 12<br/>|
|Visibility Rule|conditionLogic: and<br/>conditions:<br/>&nbsp;&nbsp;leftValueReference: HideFilter<br/>&nbsp;&nbsp;operator: EqualTo<br/>&nbsp;&nbsp;rightValue:<br/>&nbsp;&nbsp;&nbsp;&nbsp;booleanValue: false<br/>|
|boardId (input)|flowB|
|title (input)|Filter flowB (screen 1)|
|configJson (input)|{"version":1,"widgetType":"filter","boardId":"flowB","title":"Filter flowB","persistence":"NONE","filters":[{"filterId":"stage","label":"Stage","type":"PICKLIST","selectionMode":"multi","optionsSource":"FIELD_DESCRIBE","sourceObjectApiName":"Opportunity","fieldApiName":"StageName","defaultValue":{"values":["Closed Won"]}}]}|




#### ProbeAlways

|<!-- -->|<!-- -->|
|:---|:---|
|Extension Name|c:protoTabProbe|
|Field Type|Component Instance|
|Inputs On Next Nav To Assoc Scrn|Use Stored Values|
|Is Required|✅|
|Store Output Automatically|✅|
|Style Properties|verticalAlignment:<br/>&nbsp;&nbsp;stringValue: top<br/>width:<br/>&nbsp;&nbsp;stringValue: 12<br/>|
|boardId (input)|flowB|
|label (input)|S1 always visible|




#### ProbePipeline

|<!-- -->|<!-- -->|
|:---|:---|
|Extension Name|c:protoTabProbe|
|Field Type|Component Instance|
|Inputs On Next Nav To Assoc Scrn|Use Stored Values|
|Is Required|✅|
|Store Output Automatically|✅|
|Style Properties|verticalAlignment:<br/>&nbsp;&nbsp;stringValue: top<br/>width:<br/>&nbsp;&nbsp;stringValue: 12<br/>|
|Visibility Rule|conditionLogic: and<br/>conditions:<br/>&nbsp;&nbsp;leftValueReference: View<br/>&nbsp;&nbsp;operator: EqualTo<br/>&nbsp;&nbsp;rightValue:<br/>&nbsp;&nbsp;&nbsp;&nbsp;stringValue: Pipeline<br/>|
|boardId (input)|flowB|
|label (input)|S1 Pipeline view|




#### MetricPipeline

|<!-- -->|<!-- -->|
|:---|:---|
|Extension Name|c:boardMetricWidget|
|Field Type|Component Instance|
|Inputs On Next Nav To Assoc Scrn|Use Stored Values|
|Is Required|✅|
|Store Output Automatically|✅|
|Style Properties|verticalAlignment:<br/>&nbsp;&nbsp;stringValue: top<br/>width:<br/>&nbsp;&nbsp;stringValue: 12<br/>|
|Visibility Rule|conditionLogic: and<br/>conditions:<br/>&nbsp;&nbsp;leftValueReference: View<br/>&nbsp;&nbsp;operator: EqualTo<br/>&nbsp;&nbsp;rightValue:<br/>&nbsp;&nbsp;&nbsp;&nbsp;stringValue: Pipeline<br/>|
|boardId (input)|flowB|
|title (input)|S1 Pipeline count|
|objectApiName (input)|Opportunity|
|configJson (input)|{"version":1,"widgetType":"metric","boardId":"flowB","title":"S1 Pipeline count","objectApiName":"Opportunity","aggregateFunction":"COUNT"}|




#### ProbePerformance

|<!-- -->|<!-- -->|
|:---|:---|
|Extension Name|c:protoTabProbe|
|Field Type|Component Instance|
|Inputs On Next Nav To Assoc Scrn|Use Stored Values|
|Is Required|✅|
|Store Output Automatically|✅|
|Style Properties|verticalAlignment:<br/>&nbsp;&nbsp;stringValue: top<br/>width:<br/>&nbsp;&nbsp;stringValue: 12<br/>|
|Visibility Rule|conditionLogic: and<br/>conditions:<br/>&nbsp;&nbsp;leftValueReference: View<br/>&nbsp;&nbsp;operator: EqualTo<br/>&nbsp;&nbsp;rightValue:<br/>&nbsp;&nbsp;&nbsp;&nbsp;stringValue: Performance<br/>|
|boardId (input)|flowB|
|label (input)|S1 Performance view|




#### MetricPerformance

|<!-- -->|<!-- -->|
|:---|:---|
|Extension Name|c:boardMetricWidget|
|Field Type|Component Instance|
|Inputs On Next Nav To Assoc Scrn|Use Stored Values|
|Is Required|✅|
|Store Output Automatically|✅|
|Style Properties|verticalAlignment:<br/>&nbsp;&nbsp;stringValue: top<br/>width:<br/>&nbsp;&nbsp;stringValue: 12<br/>|
|Visibility Rule|conditionLogic: and<br/>conditions:<br/>&nbsp;&nbsp;leftValueReference: View<br/>&nbsp;&nbsp;operator: EqualTo<br/>&nbsp;&nbsp;rightValue:<br/>&nbsp;&nbsp;&nbsp;&nbsp;stringValue: Performance<br/>|
|boardId (input)|flowB|
|title (input)|S1 Performance count|
|objectApiName (input)|Opportunity|
|configJson (input)|{"version":1,"widgetType":"metric","boardId":"flowB","title":"S1 Performance count","objectApiName":"Opportunity","aggregateFunction":"COUNT"}|




### Screen2

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Screen|
|Label|Screen 2: Filter context via Flow variable|
|Allow Back|✅|
|Allow Finish|✅|
|Allow Pause|⬜|
|Show Footer|✅|
|Show Header|✅|


#### Filter2

|<!-- -->|<!-- -->|
|:---|:---|
|Extension Name|c:boardFilterWidget|
|Field Type|Component Instance|
|Inputs On Next Nav To Assoc Scrn|Use Stored Values|
|Is Required|✅|
|Store Output Automatically|✅|
|Style Properties|verticalAlignment:<br/>&nbsp;&nbsp;stringValue: top<br/>width:<br/>&nbsp;&nbsp;stringValue: 12<br/>|
|boardId (input)|flowB|
|title (input)|Filter flowB (screen 2)|
|configJson (input)|{"version":1,"widgetType":"filter","boardId":"flowB","title":"Filter flowB","persistence":"NONE","filters":[{"filterId":"stage","label":"Stage","type":"PICKLIST","selectionMode":"multi","optionsSource":"FIELD_DESCRIBE","sourceObjectApiName":"Opportunity","fieldApiName":"StageName","defaultValue":{"values":["Closed Won"]}}]}|
|filterContextJson (input)|Filter1.filterContextJson|




#### ProbeScreen2

|<!-- -->|<!-- -->|
|:---|:---|
|Extension Name|c:protoTabProbe|
|Field Type|Component Instance|
|Inputs On Next Nav To Assoc Scrn|Use Stored Values|
|Is Required|✅|
|Store Output Automatically|✅|
|Style Properties|verticalAlignment:<br/>&nbsp;&nbsp;stringValue: top<br/>width:<br/>&nbsp;&nbsp;stringValue: 12<br/>|
|boardId (input)|flowB|
|label (input)|S2 probe|




#### MetricScreen2

|<!-- -->|<!-- -->|
|:---|:---|
|Extension Name|c:boardMetricWidget|
|Field Type|Component Instance|
|Inputs On Next Nav To Assoc Scrn|Use Stored Values|
|Is Required|✅|
|Store Output Automatically|✅|
|Style Properties|verticalAlignment:<br/>&nbsp;&nbsp;stringValue: top<br/>width:<br/>&nbsp;&nbsp;stringValue: 12<br/>|
|boardId (input)|flowB|
|title (input)|S2 count|
|objectApiName (input)|Opportunity|
|configJson (input)|{"version":1,"widgetType":"metric","boardId":"flowB","title":"S2 count","objectApiName":"Opportunity","aggregateFunction":"COUNT"}|








___

_Documentation generated from branch monitoring_orgfarm_42750320ff_dev_ed_develop by [sfdx-hardis](https://sfdx-hardis.cloudity.com), featuring [salesforce-flow-visualiser](https://github.com/toddhalfpenny/salesforce-flow-visualiser)_