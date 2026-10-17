# Installation

One solar installation at a customer site. The master record of the Helios Delivery app.

## API Name
`Installation__c`

## Fields
### Account

The customer whose roof this is.

**API Name**

`Account__c`

**Type**

*Lookup*

---
### Crew Capacity Cap

The largest crew this installation can take. Above it, people get in each other&#x27;s way on the roof.

**API Name**

`Crew_Capacity_Cap__c`

**Type**

*Number*

---
### Crew Notes

Used for Crew Notes

**API Name**

`Crew_Notes__c`

**Type**

*LongTextArea*

---
### Crew Size
**Required**

How many people are assigned to this job. Level 2 makes it mandatory.

**API Name**

`Crew_Size__c`

**Type**

*Number*

---
### Crew Warning Sent

**API Name**

`Crew_Warning_Sent__c`

**Type**

*Checkbox*

---
### Crew Workload

Panels each person of the crew has to lay on this job.

**API Name**

`Crew_Workload__c`

**Type**

*Number*

---
### External Id

Stable key used by the training data loader. Never edit it by hand.

**API Name**

`External_Id__c`

**Type**

*Text*

---
### Install Date

The day the crew is expected on site.

**API Name**

`Install_Date__c`

**Type**

*Date*

---
### Panels Required

How many panels the crew has to load for this installation.

**API Name**

`Panels_Required__c`

**Type**

*Number*

---
### Roof Type

Drives how long the job takes.

**API Name**

`Roof_Type__c`

**Type**

*Picklist*

#### Possible values are
* Tile
* Slate
* Flat
* Metal

---
### Signed Off By

Who signed the installation off with the customer.

**API Name**

`Signed_Off_By__c`

**Type**

*Text*

---
### Status

Where this installation stands.

**API Name**

`Status__c`

**Type**

*Picklist*

#### Possible values are
* Planned
* Scheduled
* In Progress
* Completed
* Cancelled

---
### Total Capacity kW

Total installed capacity once every panel is on the roof.

**API Name**

`Total_Capacity_kW__c`

**Type**

*Number*