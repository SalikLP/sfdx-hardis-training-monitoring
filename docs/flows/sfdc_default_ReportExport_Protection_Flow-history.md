# sfdc_default_ReportExport_Protection_Flow history

<!-- This page has been generated to be viewed with Zensical, you can not view it just as markdown . Activate content tabs following the doc at https://zensical.org/docs/ -->

=== "Oct 17, 2026 (Initial)"

    _Oct 17, 2026, by SalikLP in commit chore(monitoring): org state on 2026-10-17 17:53 for monitoring_orgfarm_42750320ff_dev_ed_develop [skip ci]_

    
    ## Flow Diagram [(_View History_)](sfdc_default_ReportExport_Protection_Flow-history.md)
    
    ![diagram](./sfdc_default_ReportExport_Protection_Flow-history-1.svg)
    
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

