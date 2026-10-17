<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# CrewCapacityBatch Class

Sample for Lab 2.4. Copy it into your org as it is. 
 
It recalculates Total Capacity kW on every planned installation, from how many 
panels a crew can lay in a day on that roof type. What it computes matters far 
less than the fact that it has to be scheduled in every org it is deployed to, 
which is what the lab is about. 
 
It is both Batchable, so it can work through thousands of records, and 
Schedulable, so Salesforce can run it every night.

**Implements**

Database.Batchable<SObject>, 
Database.Stateful, 
Schedulable

## Class Diagram

```mermaid
graph TD
  CrewCapacityBatch["CrewCapacityBatch"]:::mainApexClass
  click CrewCapacityBatch "../CrewCapacityBatch/"
  CrewCapacityBatchTest["CrewCapacityBatchTest"]:::apexTestClass
  click CrewCapacityBatchTest "../CrewCapacityBatchTest/"


  CrewCapacityBatchTest --> CrewCapacityBatch


classDef apexClass fill:#FFF4C2,stroke:#CCAA00,stroke-width:3px,rx:12px,ry:12px,shadow:drop,color:#333;
classDef apexTestClass fill:#F5F5F5,stroke:#999999,stroke-width:3px,rx:12px,ry:12px,shadow:drop,color:#333;
classDef mainApexClass fill:#FFB3B3,stroke:#A94442,stroke-width:4px,rx:14px,ry:14px,shadow:drop,color:#333,font-weight:bold;

linkStyle 0 stroke:#FF8C00,stroke-width:2px;
```

<!-- Apex description -->

## Apex Code

```java
/**
 * Sample for Lab 2.4. Copy it into your org as it is.
 *
 * It recalculates Total Capacity kW on every planned installation, from how many
 * panels a crew can lay in a day on that roof type. What it computes matters far
 * less than the fact that it has to be scheduled in every org it is deployed to,
 * which is what the lab is about.
 *
 * It is both Batchable, so it can work through thousands of records, and
 * Schedulable, so Salesforce can run it every night.
 */
public with sharing class CrewCapacityBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
  // Rough panel output, used only to turn a panel count into kW
  private static final Decimal KW_PER_PANEL = 0.4;

  // Kept across the chunks of one run, for the summary email
  private Integer recalculated = 0;

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      'SELECT Id, Crew_Size__c, Roof_Type__c, Total_Capacity_kW__c ' +
      'FROM Installation__c ' +
      'WHERE Status__c = \'Planned\''
    );
  }

  public void execute(Database.BatchableContext context, List<Installation__c> installations) {
    Map<String, Decimal> panelsPerDayByRoofType = new Map<String, Decimal>();
    for (Crew_Capacity__c capacity : [
      SELECT Roof_Type__c, Panels_Per_Day__c
      FROM Crew_Capacity__c
      WHERE Panels_Per_Day__c != null
      WITH USER_MODE
    ]) {
      panelsPerDayByRoofType.put(capacity.Roof_Type__c, capacity.Panels_Per_Day__c);
    }

    for (Installation__c installation : installations) {
      Decimal panelsPerDay = panelsPerDayByRoofType.get(installation.Roof_Type__c);
      Decimal crewSize = installation.Crew_Size__c == null ? 0 : installation.Crew_Size__c;
      installation.Total_Capacity_kW__c = panelsPerDay == null
        ? 0
        : (crewSize * panelsPerDay * KW_PER_PANEL).setScale(2);
    }
    update installations;
    recalculated += installations.size();
  }

  /**
   * Emails the summary to whoever scheduled the job. An org whose email
   * deliverability is not All email refuses to send it, which is why Lab 2.4
   * declares a manual step: no deployment can change that setting. The debug
   * log is the only place a batch can say so, hence the one debug statement.
   */
  @SuppressWarnings('PMD.AvoidDebugStatements')
  public void finish(Database.BatchableContext context) {
    Messaging.SingleEmailMessage summary = new Messaging.SingleEmailMessage();
    summary.setToAddresses(new List<String>{ UserInfo.getUserEmail() });
    summary.setSubject('Crew capacity recalculated');
    summary.setPlainTextBody(recalculated + ' planned installation(s) recalculated.');
    try {
      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ summary });
    } catch (EmailException e) {
      System.debug(LoggingLevel.WARN, 'Summary email not sent: ' + e.getMessage());
    }
  }

  /** Entry point when Salesforce runs this on a schedule. */
  public void execute(SchedulableContext context) {
    Database.executeBatch(new CrewCapacityBatch(), 200);
  }
}
```

## Fields
### `KW_PER_PANEL`

#### Signature
```apex
private static final KW_PER_PANEL
```

#### Type
Decimal

---

### `recalculated`

#### Signature
```apex
private recalculated
```

#### Type
Integer

## Methods
### `start(context)`

#### Signature
```apex
public Database.QueryLocator start(Database.BatchableContext context)
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| context | Database.BatchableContext |  |

#### Return Type
**Database.QueryLocator**

---

### `execute(context, installations)`

#### Signature
```apex
public void execute(Database.BatchableContext context, List<Installation__c> installations)
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| context | Database.BatchableContext |  |
| installations | List<Installation__c> |  |

#### Return Type
**void**

---

### `finish(context)`

`SUPPRESSWARNINGS`

Emails the summary to whoever scheduled the job. An org whose email 
deliverability is not All email refuses to send it, which is why Lab 2.4 
declares a manual step: no deployment can change that setting. The debug 
log is the only place a batch can say so, hence the one debug statement.

#### Signature
```apex
public void finish(Database.BatchableContext context)
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| context | Database.BatchableContext |  |

#### Return Type
**void**

---

### `execute(context)`

Entry point when Salesforce runs this on a schedule.

#### Signature
```apex
public void execute(SchedulableContext context)
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| context | SchedulableContext |  |

#### Return Type
**void**