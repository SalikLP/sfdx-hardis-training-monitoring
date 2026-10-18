# The default Report Export Policy Flow.

## Flow Diagram [(_View History_)](sfdc_default_ReportExport_Protection_Flow-history.md)

```mermaid
%% If you read this, your Markdown visualizer does not handle MermaidJS syntax.
%% - If you are in VS Code, install extension `Markdown Preview Mermaid Support` at https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid
%% - If you are using sfdx-hardis, try to define env variable `MERMAID_MODES=cli,docker` ,then run again the command to regenerate markdown with SVG images.
%% - If you are within a Zensical site, define the mermaid custom fence in `mkdocs.yml` as described in https://zensical.org/docs/
%% - As a last resort, you can copy-paste this MermaidJS code into https://mermaid.live/ to see the flow diagram

flowchart TB
START(["START"]):::startClass
click START "#general-information" "3252298671"

START --> ConditionBuilder
EvaluationOutcomeAssignment[\"🟰 <em></em><br/>EvaluationOutcomeAssignment"/]:::assignments
click EvaluationOutcomeAssignment "#evaluationoutcomeassignment" "4276763372"

EvaluationOutcomeAssignmentFalse[\"🟰 <em></em><br/>EvaluationOutcomeAssignmentFalse"/]:::assignments
click EvaluationOutcomeAssignmentFalse "#evaluationoutcomeassignmentfalse" "2432873768"

ConditionBuilder{"🔀 <em></em><br/>ConditionBuilder"}:::decisions
click ConditionBuilder "#conditionbuilder" "2263104084"

EvaluationOutcomeAssignment --> END_EvaluationOutcomeAssignment
EvaluationOutcomeAssignmentFalse --> END_EvaluationOutcomeAssignmentFalse
ConditionBuilder --> |"MatchAll"| EvaluationOutcomeAssignment
ConditionBuilder --> |"EvaluationOutcomeAssignmentFalse"| EvaluationOutcomeAssignmentFalse
END_EvaluationOutcomeAssignment(( END )):::endClass
END_EvaluationOutcomeAssignmentFalse(( END )):::endClass


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
|Process Type|Transaction Security Flow|
|Label|The default Report Export Policy Flow.|
|Status|⚠️ Draft|
|Description|The default Condition Builder flow for the default ReportEvent Transaction Security Policy.|
|Start Element Reference|[ConditionBuilder](#conditionbuilder)|


## Variables

|Name|Data Type|Is Collection|Is Input|Is Output|Object Type|Description|
|:-- |:--:|:--:|:--:|:--:|:--:|:--  |
|EvaluationOutcome|Boolean|⬜|⬜|✅|<!-- -->|<!-- -->|
|myVariable_myEvent|SObject|⬜|✅|⬜|ReportEvent|<!-- -->|


## Flow Nodes Details

### EvaluationOutcomeAssignment

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Assignment|
|Label|[EvaluationOutcomeAssignment](#evaluationoutcomeassignment)|


#### Assignments

|Assign To Reference|Operator|Value|
|:-- |:--:|:--: |
|EvaluationOutcome|Assign|✅|




### EvaluationOutcomeAssignmentFalse

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Assignment|
|Label|[EvaluationOutcomeAssignmentFalse](#evaluationoutcomeassignmentfalse)|


#### Assignments

|Assign To Reference|Operator|Value|
|:-- |:--:|:--: |
|EvaluationOutcome|Assign|⬜|




### ConditionBuilder

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Decision|
|Label|[ConditionBuilder](#conditionbuilder)|
|Default Connector|[EvaluationOutcomeAssignmentFalse](#evaluationoutcomeassignmentfalse)|
|Default Connector Label|[EvaluationOutcomeAssignmentFalse](#evaluationoutcomeassignmentfalse)|


#### Rule MatchAll (MatchAll)

|<!-- -->|<!-- -->|
|:---|:---|
|Connector|[EvaluationOutcomeAssignment](#evaluationoutcomeassignment)|
|Condition Logic|(1 OR 2) AND 3|




|Condition Id|Left Value Reference|Operator|Right Value|
|:-- |:-- |:--:|:--: |
|1|myVariable_myEvent.Operation|Equal To|ReportExported|
|2|myVariable_myEvent.Operation|Equal To|ReportExportedUsingExcelConnector|
|3|myVariable_myEvent.RowsProcessed|Greater Than|10000|








___

_Documentation generated from branch monitoring_orgfarm_42750320ff_dev_ed_develop by [sfdx-hardis](https://sfdx-hardis.cloudity.com), featuring [salesforce-flow-visualiser](https://github.com/toddhalfpenny/salesforce-flow-visualiser)_