# Installation Crew Warning

## Flow Diagram [(_View History_)](Installation_Crew_Warning-history.md)

```mermaid
%% If you read this, your Markdown visualizer does not handle MermaidJS syntax.
%% - If you are in VS Code, install extension `Markdown Preview Mermaid Support` at https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid
%% - If you are using sfdx-hardis, try to define env variable `MERMAID_MODES=cli,docker` ,then run again the command to regenerate markdown with SVG images.
%% - If you are within a Zensical site, define the mermaid custom fence in `mkdocs.yml` as described in https://zensical.org/docs/
%% - As a last resort, you can copy-paste this MermaidJS code into https://mermaid.live/ to see the flow diagram

flowchart TB
START(["START<br/><b>AutoLaunched Flow</b></br>Type: <b>Record After Save</b>"]):::startClass
click START "#general-information" "2570715081"

Log_Fault[\"🟰 <em></em><br/>Log Fault"/]:::assignments
click Log_Fault "#log_fault" "626878595"

Crew_Too_Small{"🔀 <em></em><br/>Crew Too Small"}:::decisions
click Crew_Too_Small "#crew_too_small" "2421462193"

Create_Warning_Task[("➕ <em></em><br/>Create Warning Task")]:::recordCreates
click Create_Warning_Task "#create_warning_task" "2018936035"

Mark_Warning_Sent[("🛠️ <em></em><br/>Mark Warning Sent")]:::recordUpdates
click Mark_Warning_Sent "#mark_warning_sent" "1662518614"

Log_Fault --> END_Log_Fault
Crew_Too_Small --> |"Too Small"| Create_Warning_Task
Crew_Too_Small --> |"Default Outcome"| END_Crew_Too_Small
Create_Warning_Task --> Mark_Warning_Sent
Create_Warning_Task -. Fault .->Log_Fault
Mark_Warning_Sent --> END_Mark_Warning_Sent
Mark_Warning_Sent -. Fault .->Log_Fault
START -->  Crew_Too_Small
END_Log_Fault(( END )):::endClass
END_Crew_Too_Small(( END )):::endClass
END_Mark_Warning_Sent(( END )):::endClass


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
|Object|Installation__c|
|Process Type|Auto Launched Flow|
|Trigger Type|Record After Save|
|Record Trigger Type|Create And Update|
|Label|Installation Crew Warning|
|Status|Active|
|Description|Warns the planner when the crew assigned to an installation is too small. It warns on every save, which the planners have started to complain about.|
|Environments|Default|
|Interview Label|Installation Crew Warning {!$Flow.CurrentDateTime}|
|BuilderType (PM)|LightningFlowBuilder|
|CanvasMode (PM)|AUTO_LAYOUT_CANVAS|
|Connector|[Crew_Too_Small](#crew_too_small)|
|Next Node|[Crew_Too_Small](#crew_too_small)|


#### Filters (logic: **and**)

|Filter Id|Field|Operator|Value|
|:-- |:-- |:--:|:--: |
|1|Crew_Size__c|Is Null|False|
|2|Panels_Required__c|Is Null|False|


## Variables

|Name|Data Type|Is Collection|Is Input|Is Output|Object Type|Description|
|:-- |:--:|:--:|:--:|:--:|:--:|:--  |
|faultMessage|String|⬜|⬜|⬜|<!-- -->|The error a failed record element reported.|


## Formulas

|Name|Data Type|Expression|Description|
|:-- |:--:|:-- |:--  |
|crewTooSmall|Boolean|AND(<br/>  {!$Record.Crew_Size__c} * 8 < {!$Record.Panels_Required__c},<br/>  NOT({!$Record.Crew_Warning_Sent__c})<br/>)|True when fewer than two people are assigned.|


## Flow Nodes Details

### Log_Fault

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Assignment|
|Label|Log Fault|
|Description|Keeps the fault message so that a failed warning leaves a trace.|


#### Assignments

|Assign To Reference|Operator|Value|
|:-- |:--:|:--: |
|faultMessage|Assign|$Flow.FaultMessage|




### Crew_Too_Small

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Decision|
|Label|Crew Too Small|
|Description|Warns when the crew is too small.|
|Default Connector Label|Default Outcome|


#### Rule Too_Small (Too Small)

|<!-- -->|<!-- -->|
|:---|:---|
|Connector|[Create_Warning_Task](#create_warning_task)|
|Condition Logic|and|




|Condition Id|Left Value Reference|Operator|Right Value|
|:-- |:-- |:--:|:--: |
|1|crewTooSmall|Equal To|✅|




### Create_Warning_Task

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Record Create|
|Object|Task|
|Label|Create Warning Task|
|Description|Gives the planner a task on the installation, so the warning cannot be missed.|
|Fault Connector|[Log_Fault](#log_fault)|
|Store Output Automatically|✅|
|Connector|[Mark_Warning_Sent](#mark_warning_sent)|


#### Input Assignments

|Field|Value|
|:-- |:--: |
|OwnerId|$Record.OwnerId|
|Subject|Crew may be too small for this installation|
|WhatId|$Record.Id|




### Mark_Warning_Sent

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Record Update|
|Label|Mark Warning Sent|
|Fault Connector|isGoTo: true<br/>targetReference: Log_Fault<br/>|
|Input Reference|$Record|


#### Input Assignments

|Field|Value|
|:-- |:--: |
|Crew_Warning_Sent__c|✅|








___

_Documentation generated from branch monitoring_orgfarm_42750320ff_dev_ed_develop by [sfdx-hardis](https://sfdx-hardis.cloudity.com), featuring [salesforce-flow-visualiser](https://github.com/toddhalfpenny/salesforce-flow-visualiser)_