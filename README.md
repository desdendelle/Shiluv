## Requirements:

ID|Requirement|Note
--|-----------|----
R1|This sw will be used by a small group| Up to 15 users
R2|Roles are: workers, manager
R3|This sw works on a weekly cycle
R4|The "progrmatsia" .xlsx file will be uploaded to the sw weekly|On or before Monday morning|
R5|The "progrmatsia" file will be automatically converted to the shift schedule|
R6|The shift-schedule will be available to view starting Monday noon|
R7|An alert will be sent if the "progrmatsia" file will not be uploaded on time or not valid
R8|Workers shall be able to exclude shifts from the shift-schedule until Saturday at 2300 hours.
R9|The duty roster shall be made available for manager review on Sunday morning
R10|The sw will alert the manager if no roster was authorized after Tuesday noon

## Implementation Highlights:

ID|Item|Note
--|-----------|----
IH1|All times are IST|I.e., hours will move on IDT|
IH2|Roster generation (Hence: RG): A Python function will run weekly| at 0100 hours Sunday|
IH3|Inputs to SG: context + requests| context: output of the prev run. requests: user requests|
IH4|Output of SG: context + roster|
IH5|The backend will be initially implemented using fastAPI|w/o authentication, to support the development and testing of the front-end and of the RG function
IH6|The production backend will be AWS based|Using Lambda, S3, REST-API GW|
IH7|The backend will have a documented REST API|Documented using openAPI|
IH8|The Front-end will will a static site|
IH9|The Front-end to be a mobile-first app/site|
IH10|The Front-end to be hosted on Cloud flare|
