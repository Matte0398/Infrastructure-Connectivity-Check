# Infrastructure-Connectivity-Check

PowerShell utility for testing network connectivity between infrastructure systems.
The script can be used to test connections:

- From a Windows system to a remote Windows or Linux system
- From a remote system back to the local Windows system
- On specific TCP or UDP ports

## Features

- TCP port checks
- UDP port checks
- Local-to-remote connectivity tests
- Remote-to-local connectivity tests
- Support for Windows and Linux remote systems
- Input validation for port numbers
- Connectivity logs
- Useful for infrastructure troubleshooting and monitoring validation

## Requirements

- Windows PowerShell
- Network access to the target systems
- Posh-SSH PowerShell module when testing from remote Linux systems

## Use Cases
- Firewall rule validation
- Application port checks
- Infrastructure migration checks
- Network troubleshooting between Windows and Linux systems

## Install Requirements

```powershell
Install-Module -Name Posh-SSH
```

## Usage

```
.\TestPort.ps1 -T [port_type] -L [local_port] -R [remote_port]
```

## Example

```
.\TestPort.ps1 -T UDP -L 80,443,10050
.\TestPort.ps1 -T TCP -L 10050,10051 -R 8080,8443
