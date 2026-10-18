# Installation_Crew_Warning history

<!-- This page has been generated to be viewed with Zensical, you can not view it just as markdown . Activate content tabs following the doc at https://zensical.org/docs/ -->

=== "Oct 17, 2026 (Initial)"

    _Oct 17, 2026, by SalikLP in commit chore(monitoring): org state on 2026-10-17 17:53 for monitoring_orgfarm_42750320ff_dev_ed_develop [skip ci]_

    
    ## Flow Diagram [(_View History_)](Installation_Crew_Warning-history.md)
    
    ![diagram](./Installation_Crew_Warning-history-1.svg)
    
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

