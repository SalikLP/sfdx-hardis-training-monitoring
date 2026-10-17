<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# InstallationSchedulerTest Class

`ISTEST`

## Class Diagram

```mermaid
graph TD
  InstallationSchedulerTest["InstallationSchedulerTest"]:::mainApexClass
  click InstallationSchedulerTest "../InstallationSchedulerTest/"
  InstallationScheduler["InstallationScheduler"]:::apexClass
  click InstallationScheduler "../InstallationScheduler/"

  InstallationSchedulerTest --> InstallationScheduler



classDef apexClass fill:#FFF4C2,stroke:#CCAA00,stroke-width:3px,rx:12px,ry:12px,shadow:drop,color:#333;
classDef apexTestClass fill:#F5F5F5,stroke:#999999,stroke-width:3px,rx:12px,ry:12px,shadow:drop,color:#333;
classDef mainApexClass fill:#FFB3B3,stroke:#A94442,stroke-width:4px,rx:14px,ry:14px,shadow:drop,color:#333,font-weight:bold;

linkStyle 0 stroke:#4C9F70,stroke-width:4px;
```

<!-- Apex description -->

## Apex Code

```java
@isTest
private class InstallationSchedulerTest{
    @testSetup
    static void makeData(){
        Installation__c inst = new Installation__c(
            Status__c = 'Planned', 
            Install_Date__c = Date.today().addDays(30), 
            Crew_Size__c = 2, 
            External_Id__c = 'TEST-INST-001'
        );
        insert inst;
        insert new Panel_Batch__c(
            Installation__c = inst.Id, 
            Quantity__c = 24, 
            Arrival_Date__c = Date.today().addDays(10), 
            External_Id__c = 'TEST-BATCH-001'
        );
        // Still waiting for a date, so the Installation Assign Crew flow leaves
        // it alone and it stays Planned. The record above does not: that flow
        // moves any Planned installation with a crew and a date to Scheduled.
        insert new Installation__c(
            Status__c = 'Planned', 
            Crew_Size__c = 2, 
            External_Id__c = 'TEST-INST-900'
        );
    }

    @isTest
    static void earliestInstallDateAddsThePreparationBuffer(){
        Installation__c inst = [SELECT Id
                                FROM Installation__c
                                LIMIT 1];
        Test.startTest();
        Date earliest = InstallationScheduler.earliestInstallDate(inst.Id);
        Test.stopTest();
        System.assertEquals(Date.today().addDays(10 + InstallationScheduler.PREPARATION_DAYS), earliest, 'The earliest date should be the last arrival plus the preparation buffer');
    }

    @isTest
    static void earliestInstallDateIsNullWhenNothingHasArrived(){
        Installation__c lonely = new Installation__c(
            Status__c = 'Planned', 
            Crew_Size__c = 2, 
            External_Id__c = 'TEST-INST-002'
        );
        insert lonely;
        Test.startTest();
        Date earliest = InstallationScheduler.earliestInstallDate(lonely.Id);
        Test.stopTest();
        System.assertEquals(null, earliest, 'With no panel batch there is no earliest date');
    }

    @isTest
    static void suggestedCrewSizeNeverGoesBelowTwo(){
        System.assertEquals(2, InstallationScheduler.suggestedCrewSize(null), 'No panel count means the default crew');
        System.assertEquals(2, InstallationScheduler.suggestedCrewSize(4), 'A small job still needs two people');
        System.assertEquals(3, InstallationScheduler.suggestedCrewSize(20), '20 panels is three people');
    }

    @isTest
    static void installationsReadyToScheduleReturnsPlannedOnes(){
        Test.startTest();
        List<Installation__c> ready = InstallationScheduler.installationsReadyToSchedule();
        Test.stopTest();
        System.assert(!ready.isEmpty(), 'The planned installation should be listed');
    }

    @isTest
    static void schedulableOnRefusesBeforeThePanelsArrive(){
        Installation__c inst = [SELECT Id
                                FROM Installation__c
                                LIMIT 1];
        Test.startTest();
        List<Id> tooEarly = InstallationScheduler.schedulableOn(new List<Id>{ inst.Id }, Date.today());
        List<Id> lateEnough = InstallationScheduler.schedulableOn(new List<Id>{ inst.Id }, Date.today().addDays(60));
        Test.stopTest();
        System.assert(tooEarly.isEmpty(), 'The crew cannot be sent before the panels arrive');
        System.assertEquals(1, lateEnough.size(), 'A date after the buffer is allowed');
    }

    @isTest
    static void schedulableOnIgnoresInstallationsWithNoBatch(){
        Installation__c lonely = new Installation__c(
            Status__c = 'Planned', 
            Crew_Size__c = 2, 
            External_Id__c = 'TEST-INST-003'
        );
        insert lonely;
        Test.startTest();
        List<Id> allowed = InstallationScheduler.schedulableOn(new List<Id>{ lonely.Id }, Date.today().addDays(30));
        Test.stopTest();
        System.assert(allowed.isEmpty(), 'With no panel batch, nothing can be scheduled');
    }

}
```

## Methods
### `makeData()`

`TESTSETUP`

#### Signature
```apex
private static void makeData()
```

#### Return Type
**void**

---

### `earliestInstallDateAddsThePreparationBuffer()`

`ISTEST`

#### Signature
```apex
private static void earliestInstallDateAddsThePreparationBuffer()
```

#### Return Type
**void**

---

### `earliestInstallDateIsNullWhenNothingHasArrived()`

`ISTEST`

#### Signature
```apex
private static void earliestInstallDateIsNullWhenNothingHasArrived()
```

#### Return Type
**void**

---

### `suggestedCrewSizeNeverGoesBelowTwo()`

`ISTEST`

#### Signature
```apex
private static void suggestedCrewSizeNeverGoesBelowTwo()
```

#### Return Type
**void**

---

### `installationsReadyToScheduleReturnsPlannedOnes()`

`ISTEST`

#### Signature
```apex
private static void installationsReadyToScheduleReturnsPlannedOnes()
```

#### Return Type
**void**

---

### `schedulableOnRefusesBeforeThePanelsArrive()`

`ISTEST`

#### Signature
```apex
private static void schedulableOnRefusesBeforeThePanelsArrive()
```

#### Return Type
**void**

---

### `schedulableOnIgnoresInstallationsWithNoBatch()`

`ISTEST`

#### Signature
```apex
private static void schedulableOnIgnoresInstallationsWithNoBatch()
```

#### Return Type
**void**