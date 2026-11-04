# Flows

| Object | Name | Type | Description | Status |
| :----  | :-------- | :--: | :---------- | :----- |
| 💻 | [Proto_Board_Host_Flow](Proto_Board_Host_Flow.md) [🕒](Proto_Board_Host_Flow-history.md) | Screen Flow | Throwaway prototype Screen Flow Board with 1-col Filter Bar, 4-col Metric Row, and 2-col Chart/Table Row | Active |
| 💻 | [Service_Command_Board](Service_Command_Board.md) [🕒](Service_Command_Board-history.md) | Screen Flow | Reference Screen Flow Board: a footerless screen of 1-, 4-, and 2-column Flow Sections hosting the Board Filter Bar, Metric, Bar Chart, and Table Widgets on Board id serviceCommand. Optional recordId input scopes the Board to a record when the Flow is embedded on a Record Page. | Draft |
| 💻 | [sfdc_default_ReportExport_Protection_Flow](sfdc_default_ReportExport_Protection_Flow.md) [🕒](sfdc_default_ReportExport_Protection_Flow-history.md) | Transaction Security Flow | The default Condition Builder flow for the default ReportEvent Transaction Security Policy. | Draft |
| Installation__c | [Installation_Assign_Crew](Installation_Assign_Crew.md) [🕒](Installation_Assign_Crew-history.md) | Record Before Save | When a planner puts a crew on a planned installation that already has a date, the installation moves to Scheduled on its own. A crew larger than the installation cap is brought back down to the cap: too many people on a small roof is a safety problem. | Draft |
| Installation__c | [Installation_Close_Check](Installation_Close_Check.md) [🕒](Installation_Close_Check-history.md) | Record Before Save | An installation cannot be closed without an install date. | Draft |
| Installation__c | [Installation_Crew_Warning](Installation_Crew_Warning.md) [🕒](Installation_Crew_Warning-history.md) | Record After Save | Warns the planner when the crew assigned to an installation is too small. It warns on every save, which the planners have started to complain about. | Active |

_Documentation generated from branch monitoring_orgfarm_42750320ff_dev_ed_develop with [sfdx-hardis](https://sfdx-hardis.cloudity.com) by [Cloudity](https://cloudity.com?ref=sfdxhardis) command [`sf hardis:doc:project2markdown`](https://sfdx-hardis.cloudity.com/hardis/doc/project2markdown/)_

[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)
