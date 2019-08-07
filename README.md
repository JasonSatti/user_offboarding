# User_Offboarding
GAM User Offboarding Script

# Flags

-e - User Email
  Requires a valid email address within your GSuite Instance
  
-t - Term Type
  Term options are V for Voluntary and I for Involuntary 
  
# Use

bash offboarding.sh -e email@company.com -t V|I


## Notes
Slack Deprovision and Update Jamf Device commented out

Slack Deprovision Script and Update Jamf Device script can be found in these repos:
https://github.com/JasonSatti/Deprovision_Slack_User
https://github.com/JasonSatti/Update_Jamf_Device
