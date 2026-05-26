## Requirements:

ID|Requirement|Note
--|-----------|----
R1|This sw will be used by a small group| Up to 15 users
R2|Roles are: workers, manager
R3|This sw works on a weekly cycle
R4|Workers shall be able to exclude shifts from the publication of the previous duty roster until midnight of the next Saturday
R5|The duty roster shall be made available for manager review on Sunday morning
R6|The sw will alert the manager if no roster was published after Tuesday noon

## Implementation Highlights:

ID|Item|Note
--|-----------|----
IH1|All times are IST|I.e., hours will move on IDT|
IH2|Roster generation (Hence: RG): A Python function will run weekly| at 0100 hours Sunday|
IH3|Inputs to SG: context + requests| context: output of the prev run. requests: user requests|
IH4|Output of SG: context + roster|
IH5|Backend will be AWS based|Using Lambda, S3, REST-API GW|
IH6|Front-end will will a static site|
IH7|Front-end to be a mobile-first Flutter app|
IH8|Front-end to be hosted on Cloudflare|
