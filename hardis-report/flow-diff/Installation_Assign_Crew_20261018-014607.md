# Installation Assign Crew

## Flow Diagram [(_View History_)](Installation_Assign_Crew-history.md)

```mermaid
%% If you read this, your Markdown visualizer does not handle MermaidJS syntax.
%% - If you are in VS Code, install extension `Markdown Preview Mermaid Support` at https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid
%% - If you are using sfdx-hardis, try to define env variable `MERMAID_MODES=cli,docker` ,then run again the command to regenerate markdown with SVG images.
%% - If you are within a Zensical site, define the mermaid custom fence in `mkdocs.yml` as described in https://zensical.org/docs/
%% - As a last resort, you can copy-paste this MermaidJS code into https://mermaid.live/ to see the flow diagram

flowchart TB
START(["START<br/><b>AutoLaunched Flow</b></br>Type: <b>Record Before Save</b>"]):::startClass
click START "#general-information" "312051724"

Bring_Crew_Back_To_Cap[\"🟰 <em></em><br/>Bring Crew Back To Cap"/]:::assignments
click Bring_Crew_Back_To_Cap "#bring_crew_back_to_cap" "3015166596"

Move_To_Scheduled[\"🟰 <em></em><br/>Move To Scheduled"/]:::assignments
click Move_To_Scheduled "#move_to_scheduled" "708283407"

Raise_Crew_To_Three[\"🟰 <em></em><br/>Raise Crew To Three"/]:::assignments
click Raise_Crew_To_Three "#raise_crew_to_three" "2665584095"

Crew_Over_Cap{"🔀 <em></em><br/>Crew Over Cap"}:::decisions
click Crew_Over_Cap "#crew_over_cap" "4251786941"

Flat_Roof_Minimum{"🔀 <em></em><br/>Flat Roof Minimum"}:::decisions
click Flat_Roof_Minimum "#flat_roof_minimum" "655314016"

Bring_Crew_Back_To_Cap --> END_Bring_Crew_Back_To_Cap
Move_To_Scheduled --> Flat_Roof_Minimum
Raise_Crew_To_Three --> Crew_Over_Cap
Crew_Over_Cap --> |"Too large for this installation"| Bring_Crew_Back_To_Cap
Crew_Over_Cap --> |"Within the cap"| END_Crew_Over_Cap
Flat_Roof_Minimum --> |"Too small for a flat roof"| Raise_Crew_To_Three
Flat_Roof_Minimum --> |"Default Outcome"| Crew_Over_Cap
START -->  Move_To_Scheduled
END_Bring_Crew_Back_To_Cap(( END )):::endClass
END_Crew_Over_Cap(( END )):::endClass


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
|Record Trigger Type|Create And Update|
|Label|Installation Assign Crew|
|Status|⚠️ Draft|
|Filter Formula|AND(<br/>  NOT(ISBLANK({!$Record.Crew_Size__c})),<br/>  NOT(ISBLANK({!$Record.Install_Date__c})),<br/>  ISPICKVAL({!$Record.Status__c}, "Planned")<br/>)|
|Description|When a planner puts a crew on a planned installation that already has a date, the installation moves to Scheduled on its own. A crew larger than the installation cap is brought back down to the cap: too many people on a small roof is a safety problem.|
|Environments|Default|
|Interview Label|Installation Assign Crew {!$Flow.CurrentDateTime}|
|BuilderType (PM)|LightningFlowBuilder|
|CanvasMode (PM)|AUTO_LAYOUT_CANVAS|
|Connector|[Move_To_Scheduled](#move_to_scheduled)|
|Next Node|[Move_To_Scheduled](#move_to_scheduled)|


## Flow Nodes Details

### Bring_Crew_Back_To_Cap

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Assignment|
|Label|Bring Crew Back To Cap|
|Description|US-018: the crew never exceeds the cap the planner set on the installation.|


#### Assignments

|Assign To Reference|Operator|Value|
|:-- |:--:|:--: |
|$Record.Crew_Size__c|Assign|$Record.Crew_Capacity_Cap__c|




### Move_To_Scheduled

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Assignment|
|Label|Move To Scheduled|
|Description|A planned installation with a crew and a date is scheduled: the status follows the facts rather than waiting for somebody to change it.|
|Connector|[Flat_Roof_Minimum](#flat_roof_minimum)|


#### Assignments

|Assign To Reference|Operator|Value|
|:-- |:--:|:--: |
|$Record.Status__c|Assign|Scheduled|




### Raise_Crew_To_Three

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Assignment|
|Label|Raise Crew To Three|
|Connector|[Crew_Over_Cap](#crew_over_cap)|


#### Assignments

|Assign To Reference|Operator|Value|
|:-- |:--:|:--: |
|$Record.Crew_Size__c|Assign|3|




### Crew_Over_Cap

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Decision|
|Label|Crew Over Cap|
|Description|Is the crew larger than the cap this installation allows?|
|Default Connector Label|Within the cap|


#### Rule Too_Large (Too large for this installation)

|<!-- -->|<!-- -->|
|:---|:---|
|Connector|[Bring_Crew_Back_To_Cap](#bring_crew_back_to_cap)|
|Condition Logic|and|




|Condition Id|Left Value Reference|Operator|Right Value|
|:-- |:-- |:--:|:--: |
|1|$Record.Crew_Capacity_Cap__c|Is Null|False|
|2|$Record.Crew_Size__c|Greater Than|$Record.Crew_Capacity_Cap__c|




### Flat_Roof_Minimum

|<!-- -->|<!-- -->|
|:---|:---|
|Type|Decision|
|Label|Flat Roof Minimum|
|Default Connector|[Crew_Over_Cap](#crew_over_cap)|
|Default Connector Label|Default Outcome|


#### Rule Too_small_for_a_flat_roof (Too small for a flat roof)

|<!-- -->|<!-- -->|
|:---|:---|
|Connector|[Raise_Crew_To_Three](#raise_crew_to_three)|
|Condition Logic|and|




|Condition Id|Left Value Reference|Operator|Right Value|
|:-- |:-- |:--:|:--: |
|1|$Record.Roof_Type__c|Equal To|Flat|
|2|$Record.Crew_Size__c|Less Than|3|








___

_Documentation generated from branch monitoring_orgfarm_42750320ff_dev_ed_develop by [sfdx-hardis](https://sfdx-hardis.cloudity.com), featuring [salesforce-flow-visualiser](https://github.com/toddhalfpenny/salesforce-flow-visualiser)_