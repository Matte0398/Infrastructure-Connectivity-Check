# Infrastructure-Connectivity-Check

## Description

PowerShell script that tests TCP or UDP port connectivity between a **local Windows machine** and one or more **remote systems** (Windows or Linux). It supports testing ports in both directions:

- **Local → Remote:** tests whether specified ports are open on the remote systems
- **Remote → Local:** tests whether specified ports are open on the local machine, as seen from each remote system

All results are saved to a timestamped log file.

## Requirements

### On the LOCAL machine (always required)

- **PowerShell 5.1** or later
- A file `C:\temp\system.txt` with the list of remote systems to test

### For Remote → Local tests on **Linux** remote systems

The **Posh-SSH** PowerShell module must be installed on the local machine:

```powershell
Install-Module -Name Posh-SSH -Force
```

The **netcat** (`nc`) utility must be installed on each Linux remote system:

```bash
# Debian/Ubuntu
sudo apt-get install netcat -y

# RHEL/CentOS
sudo yum install nmap-ncat -y
```

### For Remote → Local tests on **Windows** remote systems

- **WinRM** must be enabled on the remote Windows system (see below)
- The remote user must have PowerShell Remoting access

```powershell
# On the remote Windows system, run as Administrator
Enable-PSRemoting -Force
```

**Notes:**
- Invalid port values (non-numeric, out of range 1–65535) are automatically ignored with a warning.
- If `-R` is omitted, only the local → remote direction is tested.

## Configuration File

### `C:\temp\system.txt` — list of remote systems

One entry per line. Each entry can be a **hostname** or an **IP address**:

```
server01
192.168.1.20
linux-host01
192.168.1.35
```

**Rules:**
- One system per line
- Blank lines are skipped
- If a system does not respond to ping, it is skipped entirely

## Running the Script

Open PowerShell as **Administrator** and run:

```powershell
# First run only: allow script execution
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 1) Test TCP ports from local to remote only
.\TestPort.ps1 -T TCP -L 5985,3389

# 2) Test UDP ports from local to remote only
.\TestPort.ps1 -T UDP -L 161,162

# 3) Test TCP ports in both directions (local→remote AND remote→local)
.\TestPort.ps1 -T TCP -L 5985,3389 -R 8080,3183

# 4) Using aliases (shorter form)
.\TestPort.ps1 -T tcp -L 443,80 -R 8443
```

## OS Detection (Remote → Local tests)

When `-R` is specified, the script automatically detects the OS of each remote system before testing:

| Check | Result |
|---|---|
| Port **3389/TCP** open | Remote system is **Windows** |
| Port **22/TCP** open | Remote system is **Linux** |
| Neither port open | Remote system is **Unrecognized** — remote → local test is skipped |

For **Windows** remote systems, the test is performed via `Invoke-Command` (WinRM).  
For **Linux** remote systems, the test is performed via SSH (`Posh-SSH`) using the `netcat` command.

## Credentials (Remote → Local tests only)

Credentials are required only when testing the remote → local direction. The script caches credentials per remote system in an encrypted `.cred` file under `C:\temp\`:

```
C:\temp\file_cred_<system_name>.cred
```

If the file already exists, it is reused automatically. If not, a credential prompt appears the first time.

> **Note:** To force a fresh credential prompt, delete the corresponding `.cred` file before running the script.

## Output

### Log file

A timestamped log file is created at each run:

```
C:\temp\log_connection-YYYY-MM-DD_HH-mm-ss.log
```

The log contains, for each remote system:
- Ping result
- OS detection result (when `-R` is used)
- Port test result for each port in each direction

**Example log output:**

```
Tests made from MYPC (192.168.1.5)
---------------------------------------

1) Remote system = server01

    Ping OK
    Port TCP 5985 opened on remote system
    Port TCP 3389 opened on remote system
    OS remote system: Windows
    Port TCP 8080 opened on local system
    Attention!! Port TCP 3183 closed on local system!

2) Remote system = 192.168.1.99

    Ping KO
```

## UDP Testing — Important Note

> UDP is a **connectionless** protocol. An open UDP port may not send any response to a probe packet, which means:
> - A **timeout** is interpreted as "closed" even if the port is actually open and filtering responses.
> - UDP test results should be considered **indicative only**.

For reliable UDP testing, use dedicated tools (e.g. `nmap`) in addition to this script.

## Troubleshooting

| Problem | Solution |
|---|---|
| `Posh-SSH module not found` | Run `Install-Module -Name Posh-SSH -Force` as Administrator |
| `netcat not found on remote Linux` | Install `nc` on the Linux remote system (see Requirements) |
| Ping fails for a known-online system | The system may block ICMP — check firewall rules on the remote host |
| Remote → Local test fails on Windows | Verify WinRM is enabled on the remote system and credentials are correct |
| `.cred` file causes auth errors | Delete `C:\temp\file_cred_<system>.cred` and re-run to re-enter credentials |
| `system.txt not found` | Create the file at `C:\temp\system.txt` with one hostname or IP per line |
