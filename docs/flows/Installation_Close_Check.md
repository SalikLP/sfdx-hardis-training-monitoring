<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# Installation Close Check

## Flow Diagram [(_View History_)](Installation_Close_Check-history.md)

![diagram](./Installation_Close_Check-1.svg)

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