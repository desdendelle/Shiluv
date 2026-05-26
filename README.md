## Requirements:

ID|Requirement|Note
--|-----------|----
R1|This sw will be used by a small group| Up to 10 users
R2|Roles are: workers+manager
R3|This sw works on a weekly cycle
R4|The shift-list will be published weekly| On midnight Saturday 
R5|After the shift-list publication, the users will be able to exclude shifts
R6|Exclusion can be done until Tuesday 8AM
R7|The roaster will be published on or before Tuesday noon-time 

## Implementation Highlights:

ID|Item|Note
--|-----------|----
IH1|All times are JST|I.e., hours will move on JDT|
IH2|Roster-Generation (Hence: RG): A Python function will run weekly| at 8AM Tuesday|
IH3|Inputs to SG: context + requests| context: output of the prev run. requests: users requests|
IH4|Output of SG: context + roster|
IH5|Backend will be AWS based|Using Lambda, S3, REST-API GW|
IH6|Front-end will will a static site|
IH7|Front-end to be a mobile-first Flutter app|
IH8|Front-end to be hosted on Cloud Flare|
