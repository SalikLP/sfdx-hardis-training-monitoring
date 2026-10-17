# Panel Batch

One pallet of panels delivered for an installation.

## API Name
`Panel_Batch__c`

## Fields
### Arrival Date

The day the pallet reaches the warehouse.

**API Name**

`Arrival_Date__c`

**Type**

*Date*

---
### Cost

What Helios paid for this pallet. Level 2 opens it to the crews.

**API Name**

`Cost__c`

**Type**

*Currency*

---
### External Id

Stable key used by the training data loader. Never edit it by hand.

**API Name**

`External_Id__c`

**Type**

*Text*

---
### Installation

The installation this pallet is for.

**API Name**

`Installation__c`

**Type**

*Lookup*

---
### Quantity

How many panels are on this pallet.

**API Name**

`Quantity__c`

**Type**

*Number*

---
### Quote PDF URL

Where the generated quote PDF for this batch is stored.

**API Name**

`Quote_Pdf_Url__c`

**Type**

*Url*

---
### Serial Prefix

First characters of the serial numbers on this pallet.

**API Name**

`Serial_Prefix__c`

**Type**

*Text*