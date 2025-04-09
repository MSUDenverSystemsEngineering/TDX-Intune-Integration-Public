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
1. Runs a report that shows TDX assets modified in the last 5 minutes with heavy filtering.
2. Takes information from each asset in the report results and adds it to a CSV.
## How to set up the integration
Identify a machine that you want the integration to run on. Ideally, this is a virtual Windows machine that is always on.
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
- [ ] Set up the report 
