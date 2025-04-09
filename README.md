# TDX-Intune-Integration-Public
This integration was built at MSU Denver to take information from our Windows device records in TeamDynamix Assets/CIs and bring it to Microsoft Intune in a meaningful way. Unlike preparing Windows machines with an SCCM task sequence and OSD FrontEnd, Microsoft Intune provides no way easy to decide how a device will be provisioned ahead of time. Group tags exist, but we didn't like that it's a write-in field and mistakes could be made easily. Additionally, since we manage over 300 classrooms, labs and shared spaces, manually creating an Entra group for each space felt like a burden, especially knowing that things change frequently on our shared campus. Since we already maintained an asset management database in TeamDynamix, we felt it was only natural to pull information from there. This way, a technican need only update the asset record in TDX and the device records in Intune and Entra would fall in line.
## Who this is for
Your organization:
- uses TeamDynamix Assets/CIs to record information about their devices.
- uses Microsoft Intune to manage their Windows devices
- uses Autopilot for device provisioning
- has many shared spaces and needs to deploy software, policies or configurations to those spaces on an individual basis
## Who this isn't for
Your organization:
- does not maintain an asset management database in TeamDynamix. Asset records need to originate in TDX; this integration does not create TDX asset records (see the [official integration](https://solutions.teamdynamix.com/TDClient/1965/Portal/KB/ArticleDet?ID=161834) for that).
- does not use Microsoft Intune to manage their Windows devices
- does not use Autopilot for provisioning
- doesn't have that many shared spaces (use group tags instead)
## What this integration does
1. tdxFlow.py runs a report every 5 minutes that shows TDX assets modified in the last 5 minutes with heavy filtering.
2. Takes information from each asset in the report results, creates group names that the asset shoujld belong to based off the location and department info and adds it to a CSV.
3. Calls azureFlow.ps1 which reads the CSV and does the following for each asset on the list:
4. Checks to see if the device has an Autopilot record, if not then the integration will skip this device.
5. Gets the device's Autopilot, Azure Device, Azure Object and Intune device IDs.
6. Checks to see if the desired groups exist in Azure AD.
7. Creates any groups that do not exist.
8. Checks the device's current group membership.
9. Adds the device to any necessary groups.
10. Removes the device from any necessary groups.
11. Sets the primary user if Single User provisioning type was selected.
12. Writes the current date and time to Azure AD Extension Attribute 1.
## How to set up the integration
### Microsoft Graph
- [ ] Create an application registraion according to Microsoft's directions: [Build PowerShell scripts with Microsoft Graph and app-only authentication](https://learn.microsoft.com/en-us/graph/tutorials/powershell-app-only?tabs=windows).
- [ ] Grant the app registration the following permissions with admin consent:
  - Device.ReadWrite.All
  - DeviceManagementConfiguration.ReadWrite.All
  - DeviceManagementManagedDevices.PrivilegedOperations.All
  - DeviceManagementManagedDevices.ReadWrite.All
  - DeviceManagementServiceConfig.ReadWrite.All
  - Directory.ReadWrite.All
  - User.Read
- [ ] Install the certificate to the computer store on your integration machine. Use the default location. The certificate should be named 'PowerShell App-Only' but can be renamed in the script.
### TeamDynamix
- [ ] Retreive the WebServicesKey and BEID of the API User in TDX. Ensure it has full admin permissions on the Assets/CIs app.
- [ ] We use two fields to record the room number of an asset: the built-in *LocationRoomName* field and a custom built write-in option called *Room Number* because we don't have good data on all the spaces on our campus. You may not need this. Feel free to remove lines 84 through 86 of the tdxFlow.py if that is the case.
- [ ] Create an Assets/CIs report that looks like this:

![image](https://github.com/user-attachments/assets/71b4ebcf-4efc-4018-a615-85e7ba6ff656)

### Server Setup
- [ ] Identify a machine that you want the integration to run on. Ideally, this is a virtual Windows machine that is always on.
- [ ] Install the certificate to the computer store on your integration machine. Use the default location. The certificate should be named 'PowerShell App-Only' but can be renamed in the script.
- [ ] Install PowerShell 7. This can be used with PowerShell 5, but I found PowerShell 7 works better.
- [ ] Install Python 3.12. You may need to add Python to the PATH environment variable so it can be run from the command line.
- [ ] Create a scheduled task to run tdxFlow.py with the following settings:

![Screenshot 2025-04-09 090931](https://github.com/user-attachments/assets/6e498be4-4d74-4da8-8443-50467ba64616)
![Screenshot 2025-04-09 090705](https://github.com/user-attachments/assets/15bebe4e-77b2-49bd-9a29-983d2ed4d618)
![Screenshot 2025-04-09 090745](https://github.com/user-attachments/assets/97aa381e-fc2f-47af-9a8b-9d89a9d13db9)

Program/script: "pwsh.exe"

Add arguments: "-Command python tdxFlow.py"

Start in: "C:\Integrations\TDX-Intune-Integration\TDX-MDM-Integration\"
- [ ] Copy down the files from this repo into the folder specified above.
- [ ] Modify the two scripts to include your authentication information from the previous steps.
- [ ] Test out the integration by modifying an asset record. Ensure you have all the required fields.
