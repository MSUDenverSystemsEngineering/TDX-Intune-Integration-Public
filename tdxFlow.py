'''
Title: tdxflow.py
Author: Ryan McKenna, MSU Denver
Date: 5/10/2024
Purpose: Retrieves data from a TeamDynamix report, parses it, and writes it to a CSV file. Then, the script launches azureFlow.ps1 to do work in Intune and Azure AD.
'''

# Importing libraries
import requests
import json
import pprint
import datetime
import logging
import csv
import subprocess

# Setting up the log
logging.basicConfig(level=logging.INFO, filename="Logs/tdxFlow-" + str(datetime.datetime.now().date()) + ".log")
logging.info("---LOG BEGIN:: " + str(datetime.datetime.now()) + " ---")

# Open the CSV file in write mode, create the writer object, and write the header row
csvfile = open('tdxFlowOutput.csv', 'w', newline='')
writer = csv.writer(csvfile)
writer.writerow(['assetName', 'serialNumber', 'primaryUser', 'groupNameProvisioning', 'groupNameDept', 'groupNameBuilding', 'groupNameCombo'])

# Retreiving the token using the key-based administrative TDX api user
token = requests.post('https://YOURORG.teamdynamix.com/TDWebApi/api/auth/loginadmin', json={'BEID':'12345678-1234-1234-1234-123456789012', 'WebServicesKey':'12345678-1234-1234-1234-123456789012'})
if token.status_code == 200:
    logging.info("---TDX API KEY RETRIEVED---")
else:
    logging.critical("---ERROR:: TDX API KEY COULD NOT BE RETRIEVED:: Response: " + str(token.status_code) + " Reason: " + str(token.reason) + ":: EXITING SCRIPT...")
    logging.info("---LOG END:: " + str(datetime.datetime.now()) + " ---")
    exit()

# Taking the result and truncating it
result = str(token.content)
length = len(result)
token = (result[2:length-1])

# Concatenating the admin token with appropriate header info
auth = {'Authorization':'Bearer ' + token}

# Retrieving the report, converting into JSON (same as a Python dictionary), and measuring how may rows of data we got
report = requests.get('https://YOURORG.teamdynamix.com/TDWebApi/api/reports/REPORTID?withData=True', headers=auth)

if report.status_code == 200:
    reportJSON = report.json()
    length = len(reportJSON['DataRows'])
    logging.info("---REPORT RETRIEVED. ROWS OF DATA:: " + str(length) + " ---")
else:
    logging.critical("---ERROR:: TDX REPORT COULD NOT BE RETRIEVED:: Response:" + str(report.status_code) + " Reason: " + str(report.reason) + ":: EXITING SCRIPT...")
    logging.info("---LOG END:: " + str(datetime.datetime.now()) + " ---")
    exit()

# If there is no data, then exit the script, if there is more than 0, then traverse the list and do work
if length == 0:
    logging.info("---EMPTY:: NO NEW REQUESTS, EXITING SCRIPT...---")
    logging.shutdown()
    exit()
elif length > 0:
    i = 0
    while i < length:

        # Record the data we need from the JSON. If ever these values are blank, an empty string '' will be written to the variable.
        logging.info("---PARSING REPORT DATA---")
        assetName = reportJSON['DataRows'][i]['Name']
        serialNumber = reportJSON['DataRows'][i]['SerialNumber']
        provisioningType = reportJSON['DataRows'][i]['153921']
        department = (reportJSON['DataRows'][i]['OwningDepartmentName']).replace("'", "''")
        building = reportJSON['DataRows'][i]['LocationName']
        logging.info("---ASSET NAME: " + assetName + " ---")
        logging.info("---SERIAL NUMBER: " + serialNumber + " ---")
        logging.info("---PROVISIONING TYPE: " + provisioningType + " ---")
        logging.info("---DEPARTMENT: " + department + " ---")
        logging.info("---BUILDING: " + building + " ---")
        
        # Recording the asset location data.
        # LocationRoomName is a pre-populated field and 121007 is a write-in field. Our preference is to use the pre-populated field.
        # We do not need a location if the type is Single User because they would be too numerous and we do not apply Intune configs to those individually.
        if provisioningType != "Single User":
            if reportJSON['DataRows'][i]['LocationRoomName'] != '':
                room = reportJSON['DataRows'][i]['LocationRoomName']
                logging.info("---ROOM (Pre-pop): " + room + " ---")
            else:
                room = reportJSON['DataRows'][i]['121007']
                logging.info("---ROOM (Write-in): " + room + " ---")
        else:
            room = ''
            logging.info("---ROOM: N/A ---")

        # OwningCustomerName is used in Single User scenarios as the primary user. There is no primary user for all other scenarios.
        if provisioningType == 'Single User':
            primaryUser = reportJSON['DataRows'][i]['OwningCustomerEmail']
            logging.info("---PRIMARY USER: " + primaryUser + " ---")
        else:
            primaryUser = ''
            logging.info("---PRIMARY USER: N/A ---")

        # Creating the group names
        logging.info("---CREATING GROUP NAMES---")
        groupNameProvisioning = 'Intune - Win - ' + provisioningType
        groupNameDept = 'Intune - Win - ' + department
        groupNameBuilding = 'Intune - Win - ' + building
        logging.info("---GROUP NAME (PROVISIONING): " + groupNameProvisioning + " ---")
        logging.info("---GROUP NAME (DEPARTMENT): " + groupNameDept + " ---")
        logging.info("---GROUP NAME (BUILDING): " + groupNameBuilding + " ---")

        # Creating the combo group name. Single User machines do not need a combination group. They would be too numerous.
        if provisioningType != 'Single User':
            groupNameCombo = 'Intune - Win - ' + provisioningType + ' - ' + department + ' - ' + (building.split(' ')[0]) + ' - ' + room
            logging.info("---GROUP NAME (COMBO): " + groupNameCombo + " ---")
        else:
            groupNameCombo = ''
            logging.info("---GROUP NAME (COMBO): N/A ---")
            
        # Write the data to the CSV file
        logging.info("---WRITING DATA TO CSV---")
        writer.writerow([assetName, serialNumber, primaryUser, groupNameProvisioning, groupNameDept, groupNameBuilding, groupNameCombo])

        i+=1

logging.info("---CLOSING CSV FILE---")
csvfile.close()

logging.info("---LAUNCHING AZURE FLOW POWERSHELL SCRIPT---")
logging.shutdown()
subprocess.run(r'pwsh.exe .\azureFlow.ps1', capture_output=False)
