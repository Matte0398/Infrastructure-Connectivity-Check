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

## Supported Scenarios

- Windows → Windows
- Windows → Linux
- Linux → Windows
- Firewall validation
- Application port validation

## Install Requirements

``` powershell
Install-Module -Name Posh-SSH
```

## Input

By default, the script reads the list of systems from:

``` text
C:\temp\system.txt

server01
192.168.1.11
```

## Output

By default, the script creates output files under:

``` text
C:\temp
```

Generated files:

``` text
  C:\temp\log_connection-<timestamp>.log
```

## Usage

``` powershell
.\TestPort.ps1 -T [port_type] -L [local_port] -R [remote_port]
```

## Example

Run a TCP test from the local machine to the remote systems on ports 80, 443 and 10050, and from the remote systems back to the local machine on ports 8080 and 8443:

``` powershell
.\TestPort.ps1 -T TCP -L 80,443,10050 -R 8080,8443
```

Run a UDP test from the remote systems to the local machine on port 161:

``` powershell
.\TestPort.ps1 -T UDP -R 161
```

## Repository Structure

``` text
Infrastructure-Connectivity-Check/
│   TestPort.ps1
├── examples/
│   ├── system.txt
└── README.md
