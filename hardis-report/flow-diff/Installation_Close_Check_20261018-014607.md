# Installation Close Check

## Flow Diagram [(_View History_)](Installation_Close_Check-history.md)

```mermaid
%% If you read this, your Markdown visualizer does not handle MermaidJS syntax.
%% - If you are in VS Code, install extension `Markdown Preview Mermaid Support` at https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid
%% - If you are using sfdx-hardis, try to define env variable `MERMAID_MODES=cli,docker` ,then run again the command to regenerate markdown with SVG images.
%% - If you are within a Zensical site, define the mermaid custom fence in `mkdocs.yml` as described in https://zensical.org/docs/
%% - As a last resort, you can copy-paste this MermaidJS code into https://mermaid.live/ to see the flow diagram

flowchart TB
START(["START<br/><b>AutoLaunched Flow</b></br>Type: <b>Record Before Save</b>"]):::startClass
click START "#general-information" "2764666805"

Log_Fault[\"🟰 <em></em><br/>Log Fault"/]:::assignments
click Log_Fault "#log_fault" "898203744"

Handover_Not_Done("🚫 <em></em><br/>Handover Not Done"):::customErrors
click Handover_Not_Done "#handover_not_done" "2880519171"

Install_Date_Missing("🚫 <em></em><br/>Install Date Missing"):::customErrors
click Install_Date_Missing "#install_date_missing" "426048938"

Any_Not_Done{"🔀 <em></em><br/>Any Not Done"}:::decisions
click Any_Not_Done "#any_not_done" "2666303570"

No_Install_Date{"🔀 <em></em><br/>No Install Date"}:::decisions
click No_Install_Date "#no_install_date" "2998211114"

Get_Handovers_Not_Done[("🔍 <em></em><br/>Get Handovers Not Done")]:::recordLookups
click Get_Handovers_Not_Done "#get_handovers_not_done" "2662119427"

Log_Fault --> END_Log_Fault
Handover_Not_Done --> END_Handover_Not_Done
Install_Date_Missing --> END_Install_Date_Missing
Any_Not_Done --> |"Not All Done"| Handover_Not_Done
Any_Not_Done --> |"Default Outcome"| No_Install_Date
No_Install_Date --> |"Date missing"| Install_Date_Missing
No_Install_Date --> |"Install date set"| END_No_Install_Date
Get_Handovers_Not_Done --> Any_Not_Done
Get_Handovers_Not_Done -. Fault .->Log_Fault
START -->  Get_Handovers_Not_Done
END_Log_Fault(( END )):::endClass
END_Handover_Not_Done(( END )):::endClass
END_Install_Date_Missing(( END )):::endClass
END_No_Install_Date(( END )):::endClass


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
|Trigger Type|Record Before Save|
|Record Trigger Type|Update|
|Label|Installation Close Check|
|Status|⚠️ Draft|
|Does Require Record Changed To Meet Criteria|✅|
|Description|An installation cannot be closed without an install date.|
|Environments|Default|
|Interview Label|Installation Close Check {!$Flow.CurrentDateTime}|
|BuilderType (PM)|LightningFlowBuilder|
|CanvasMode (PM)|AUTO_LAYOUT_CANVAS|
|Connector|[Get_Handovers_Not_Done](#get_handovers_not_done)|
|Next Node|[Get_Handovers_Not_Done](#get_handovers_not_done)|


#### Filters (logic: **and**)

|Filter Id|Field|Operator|Value|
|:-- |:-- |:--:|:--: |
|1|Status__c|Equal To|Completed|


## Variables

|Name|Data Type|Is Collection|Is Input|Is Output|Object Type|Description|
|:-- |:--:|:--:|:--:|:--:|:--:|:--  |
|faultMessage|String|⬜|⬜|✅|<!-- -->|<!-- -->|


## Flow Nodes Details

### Log_Fault

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Assignment|
|Label|Log Fault|


#### Assignments

|Assign To Reference|Operator|Value|
|:-- |:--:|:--: |
|faultMessage|Assign|$Flow.FaultMessage|




### Handover_Not_Done

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Custom Error|
|Label|Handover Not Done|
|Custom Error Messages|errorMessage: Not all Handovers are done<br/>isFieldError: false<br/>|


### Install_Date_Missing

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Custom Error|
|Label|Install Date Missing|
|Description|Refuses to close an installation that was never given an install date.|
|Custom Error Messages|errorMessage: Set the install date before closing this installation.<br/>isFieldError: false<br/>|


### Any_Not_Done

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Decision|
|Label|Any Not Done|
|Default Connector|[No_Install_Date](#no_install_date)|
|Default Connector Label|Default Outcome|


#### Rule Not_All_Done (Not All Done)

|<!-- -->|<!-- -->|
|:---|:---|
|Connector|[Handover_Not_Done](#handover_not_done)|
|Condition Logic|and|




|Condition Id|Left Value Reference|Operator|Right Value|
|:-- |:-- |:--:|:--: |
|1|[Get_Handovers_Not_Done](#get_handovers_not_done)|Is Null|False|




### No_Install_Date

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Decision|
|Label|No Install Date|
|Description|Was the installation ever given an install date?|
|Default Connector Label|Install date set|


#### Rule Date_Missing (Date missing)

|<!-- -->|<!-- -->|
|:---|:---|
|Connector|[Install_Date_Missing](#install_date_missing)|
|Condition Logic|and|




|Condition Id|Left Value Reference|Operator|Right Value|
|:-- |:-- |:--:|:--: |
|1|$Record.Install_Date__c|Is Null|True|




### Get_Handovers_Not_Done

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Record Lookup|
|Object|Handover_Item__c|
|Label|Get Handovers Not Done|
|Assign Null Values If No Records Found|⬜|
|Fault Connector|[Log_Fault](#log_fault)|
|Get First Record Only|✅|
|Store Output Automatically|✅|
|Connector|[Any_Not_Done](#any_not_done)|


#### Filters (logic: **and**)

|Filter Id|Field|Operator|Value|
|:-- |:-- |:--:|:--: |
|1|Installation__c|Equal To|$Record.Id|
|2|Is_Done__c|Equal To|⬜|








___

_Documentation generated from branch monitoring_orgfarm_42750320ff_dev_ed_develop by [sfdx-hardis](https://sfdx-hardis.cloudity.com), featuring [salesforce-flow-visualiser](https://github.com/toddhalfpenny/salesforce-flow-visualiser)_