<#
Title: azureflow.ps1
Author: Ryan McKenna, MSU Denver
Date: 12/17/2024
Version: 1.2
Purpose: Runs following the tdxFlow.py script. Makes changes to the Intune and Azure device records according to the CSV outputted by the TDX script.
Flow:
    Supply a device ID and the appropriate groups and do the following:
    1. Update device name
    2. Set primary user (if applicable)
    3. Update security group membership
        a. Check if groups exist
            a. If not, create on demand
            b. If yes, continue
        b. Check device's current group membership
            a. Remove device from groups that do not match (only ones with "Intune - TDX" prefix)
            b. Add device to new groups
            c. Do nothing if device already in group
    4. Update Intune notes field with current date and time
Tip for readability: The below function "Sync-Groups" is called within the for loop at the bottom of this document. To understand the order of operations, begin with the for loop and return to Sync-Groups after.
#>

# Start the transcript.
$date = Get-Date -Format "yyyy-MM-dd"
Start-Transcript -Path "Logs\azureFlow-$date.log" -Append
Write-Host "---INFO:: LOG BEGIN---"

# Connecting to Microsoft Graph API using the app-only method (certificate).
Write-Host "---INFO:: CONNECTING GRAPH API---"
$clientId = "REPLACE WITH YOUR CLIENT ID"
$tenantId = "REPLACE WITH YOUR TENANT ID"
$certificate = "CN=PowerShell App-Only"
Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateName $certificate -NoWelcome

# Import the CSV file which was outputted by the TDX python script.
Write-Host "---INFO:: IMPORTING CSV---"
$csvPath = Join-Path -Path $PSScriptRoot -ChildPath "tdxFlowOutput.csv"
$data = Import-Csv -Path $csvPath

# Function to sync device group membership. Gets called in the for loop below.
function Sync-Groups {

    # Set the parameters for the function: the Azure AD object ID and the array of group names.
    param (
        [string]$azureObjectId,
        [string[]]$groupNames
    )

    Write-Host "---INFO:: BEGINNING GROUP SYNC---"
    Write-Host "---INFO:: AZURE OBJECT ID: '$azureObjectId'---"
    Write-Host "---INFO:: REQUESTED GROUP NAMES:---"
    # Remove any blank entries from $groupNames
    $groupNames = $groupNames | Where-Object { $_ -ne "" }
    $groupNames

    # Declare the list of groups that do not exist in Azure AD and need to be created and the list of filtered device groups.
    $notExistList = [System.Collections.Generic.List[string]]::new()
    $filteredDeviceGroups = [System.Collections.Generic.List[string]]::new()

    # GROUP EXISTENCE CHECK
    # Loop through the group names produced by TDX and check if they exist in Azure AD, if not, add to creation list.
    Write-Host "---INFO:: GROUP EXISTENCE CHECK---"
    foreach ($group in $groupNames) {
        $result = (Get-MgGroup -Filter "DisplayName eq '$group'" | Select-Object -expandproperty DisplayName)
            if ($null -eq $result)
            {
                Write-Host "---INFO:: GROUP DOES NOT EXIST. ADDING TO CREATION LIST. GROUP: '$group'---"
                $notExistList.Add($group)
            }
    }

    # GROUP CREATION
    # Create any groups that do no exist in Azure AD. Uses regex to remove special characters for the mailNickname.
    Write-Host "---INFO:: CREATING GROUPS---"
    foreach ($group in $notExistList)
        {
            Write-Host "---INFO:: CREATING GROUP: '$group'---"
            $mailNickname = New-Guid
            New-MgGroup -DisplayName $group.ToString() -SecurityEnabled:$True -MailEnabled:$False -MailNickname $mailNickname
        }

    # GROUP MEMBERSHIP UPDATE
    # Getting the groups the device is currently apart of.
    # The securityEnabledOnly parameter needs to be set to false. It only works for users and service principals.
    Write-Host "---INFO:: UPDATING DEVICE GROUP MEMBERSHIP---"
    Write-Host "---INFO:: GETTING CURRENT DEVICE GROUPS---"
    $params = @{
        securityEnabledOnly = $false
    }
    $currentDeviceGroups = Get-MgDirectoryObjectMemberGroup -DirectoryObjectId $azureObjectId -bodyparameter $params
    Write-Host "---INFO:: CURRENT DEVICE GROUPS: '$currentDeviceGroups'---"
    
    # Filtering so only groups managed by this integration appear.
    Write-Host "---INFO:: FILTERING GROUPS---"
    foreach ($group in $currentDeviceGroups)
    {
        $filteredGroupItem = Get-MgGroup -GroupId $group | Where-Object { $_.DisplayName.startsWith("Intune - Win") } | Select-Object -expandproperty DisplayName

        # The above command outputs blanks when the group isn't found. So we only add the group if it's not blank.
        if ($filteredGroupItem) {
            $filteredDeviceGroups.Add($filteredGroupItem)
        }
        
    }
    Write-Host "---INFO:: FILTERED DEVICE GROUPS:---"
    $filteredDeviceGroups

    # Adding device to any new groups.
    Write-Host "---INFO:: ADDING DEVICE TO GROUPS---"
    foreach ($group in $groupNames)
    {
        # If the group from TDX is not in the device's current list of groups, add the device to the group.
        if ($group -notin $filteredDeviceGroups)
        {
            Write-Host "---INFO:: ADDING DEVICE TO GROUP: '$group'---"
            $groupId = Get-MgGroup -Filter "DisplayName eq '$group'" -top 1 | Select-Object -expandproperty id
            New-MgGroupMember -GroupId $groupId -DirectoryObjectId $azureObjectId
        }
        else
        {
            # Device already in group, skip.
        }
    }

    # Removing device from any old groups.
    Write-Host "---INFO:: REMOVING DEVICE FROM GROUPS---"
    foreach ($group in $filteredDeviceGroups)
    {
        # Now do the opposite, if the group in device's current list of groups is NOT in the TDX list of groups, remove the device from that group.
        if ($group -notin $groupNames)
        {
            Write-Host "---INFO:: REMOVING DEVICE FROM GROUP: '$group'---"
            $groupId = Get-MgGroup -Filter "DisplayName eq '$group'" -top 1 | Select-Object -expandproperty id
            Remove-MgGroupMemberDirectoryObjectByRef -GroupId $groupId -DirectoryObjectId $azureObjectId
        }
    }
}

Write-Host "---INFO:: BEGINNING FOR-LOOP---"
# Loop through each row in the CSV and sync the device group membership.
foreach ($line in $data) {

    Write-Host "---INFO:: RETRIEVING CSV LINE---"
    Write-Host "---INFO:: CSV LINE / LOOP ITERATOR: '$line'---"
    # Get the serial number and device name from the current row in the CSV.
    $assetName = $line.assetName
    $serialNumber = $line.serialNumber
    $userPrincipalName = $line.primaryUser

    # Place all the group names into an array.
    $groupNames = @($line.groupNameProvisioning, $line.groupNameDept, $line.groupNameBuilding, $line.groupNameCombo)

    Write-Host "---INFO:: RETRIEVING DEVICE AUTOPILOT ID, INTUNE DEVICE ID, AZURE DEVICE ID, AND AZURE OBJECT ID---"
    # Grab the device's AutoPilot ID.
    $autopilotId = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -top 1 -filter "contains(serialNumber,'$serialNumber')" | Select-Object -expandproperty id

    # If the device is found in AutoPilot, continue.
    if ($autopilotId) {

        # Grab the device's Intune Device ID, Azure AD Device ID, and Azure AD Object ID.
        $intuneDeviceId = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -top 1 -filter "contains(serialNumber,'$serialNumber')" | Select-Object -expandproperty ManagedDeviceId
        $azureDeviceId = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -top 1 -filter "contains(serialNumber,'$serialNumber')" | Select-Object -expandproperty AzureActiveDirectoryDeviceId
        $azureObjectId = Get-MgDevice -filter "DeviceId eq '$azureDeviceId'" | select-object -expandproperty Id
        Write-Host "---INFO:: AUTOPILOT ID: '$autopilotId'---"
        Write-Host "---INFO:: INTUNE DEVICE ID: '$intuneDeviceId'---"
        Write-Host "---INFO:: AZURE DEVICE ID: '$azureDeviceId'---"
        Write-Host "---INFO:: AZURE OBJECT ID: '$azureObjectId'---"

        Write-Host "---INFO:: UPDATING AUTOPILOT DISPLAY NAME: $assetName---"
        # Update the device's display name in AutoPilot. This only applies during OOBE.
        Update-MgDeviceManagementWindowsAutopilotDeviceIdentityDeviceProperty -WindowsAutopilotDeviceIdentityId $autopilotId -DisplayName $assetName

        # Check if the device has an active Intune record and a primary user is present in the CSV.
        # Devices that have never been provisioned before will not have an Intune record.
        # If the device has an Intune record, set the primary user. (Can only be done after provisioning.)
        if ($userPrincipalName -and $intuneDeviceId -ne '00000000-0000-0000-0000-000000000000') {

            Write-Host "---INFO:: INTUNE RECORD EXISTS FOR DEVICE, SETTING PRIMARY USER: $userPrincipalName---"
            # Retrieve the user's Azure ID
            $userId = Get-MgUser -filter "userPrincipalName eq '$userPrincipalName'" -property Id | Select-Object -expandproperty Id

            # Set the user as the primary user of the device
            Invoke-MgGraphRequest -uri "beta/deviceManagement/managedDevices/$intunedeviceId/users/`$ref" -Body @{ "@odata.id" = "https://graph.microsoft.com/beta/users/$userId" } -Method POST
            
        }
        else {
            Write-HOST "---INFO:: PRIMARY USER NOT REQUESTED OR DEVICE NOT PROVISIONED. SKIPPING USER ASSIGNMENT.---"
        }
        
        # Sync the device group membership
        Sync-Groups -groupNames $groupNames -azureObjectId $azureObjectId

        # Write to the device's first extension attribute with the date and time.
        Write-Host "---INFO:: UPDATING EXTENSION ATTRIBUTE 1 WITH TIMESTAMP---"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $params = @{
            extensionAttributes = @{
                extensionAttribute1 = $timestamp
            }
        }
        Update-MgDevice -DeviceId $azureObjectId -BodyParameter $params
    }
    else {
        Write-Host "---INFO:: DEVICE NOT FOUND IN AUTOPILOT. SKIPPING DEVICE.---"
    }
    
}

Stop-Transcript