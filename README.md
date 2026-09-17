# Infrastructure Connectivity Check

`TestPort.ps1` tests TCP or UDP connectivity between a local Windows computer and one or more remote Windows or Linux systems. It can test ports from the local computer to the remote systems (`-L`) and, optionally, from each remote system back to the local computer (`-R`). Results are written to a timestamped log file.

## Requirements

- Windows PowerShell 5.1 or later on the local computer.
- A file containing one host name or IP address per line. By default, the script reads `C:\temp\system.txt`.
- For reverse tests from Windows: PowerShell Remoting/WinRM enabled on the remote system and credentials with remoting access.
- For reverse tests from Linux: the `Posh-SSH` module on the local computer and `nc` (netcat) on the remote system.

Install the SSH module if needed:

```powershell
Install-Module -Name Posh-SSH
```

If needed, enable PowerShell Remoting on the remote Windows system by running this command there as an administrator:

```powershell
Enable-PSRemoting -Force
```

For example, `system.txt` may contain:

```text
server01
192.168.1.20
linux-host01
```

Blank and whitespace-only lines are ignored. The ping result is recorded, but a missing reply **does not** stop the port tests: a firewall may block ICMP.

## Usage

Run the script from the directory that contains it:

```powershell
# Test only from the local computer to the remote systems
.\TestPort.ps1 -T TCP -L 80,443

# Test in both directions with a remote Windows system
.\TestPort.ps1 -T TCP -L 5985,3389 -R 8080,3183 -RemoteOS Windows

# Test UDP with a remote Linux system and a two-second timeout
.\TestPort.ps1 -T UDP -L 161,162 -R 514 -RemoteOS Linux -Timeout 2000

# Use a custom host list and log directory
.\TestPort.ps1 -T TCP -L '80,443' -SystemListPath 'D:\network\hosts.txt' -WorkDirectory 'D:\network\logs'
```

`-T`, `-L`, and `-R` are aliases for `-port_type`, `-ports_local_to_remote`, and `-ports_remote_to_local`, respectively. Ports can be supplied as a PowerShell list (`80,443`) or a comma-separated string (`'80,443'`). Non-numeric values and ports outside the range 1–65535 are ignored with a warning. `-L` must contain at least one valid port. When `-R` is omitted, no credentials or remote sessions are needed.

| Parameter | Description |
| --- | --- |
| `-RemoteOS Auto\|Windows\|Linux` | `Auto` (the default) tries WinRM, then SSH. `Windows` or `Linux` skips automatic detection. |
| `-Timeout <ms>` | Socket test timeout, from 100 to 60000 ms. Default: 1000 ms. |
| `-WorkDirectory <path>` | Working and log directory. Default: `C:\temp`. |
| `-SystemListPath <path>` | Host list. Default: `system.txt` in the working directory. |
| `-Credential <PSCredential>` | Credential for remote-to-local tests. |
| `-SaveCredential` | Saves and reuses a credential for each remote system. Without this switch, credentials are not saved. |
| `-TrustSshHostKey` | Automatically accepts an unknown SSH host key. Use only when you trust the host. |

To supply credentials explicitly:

```powershell
$cred = Get-Credential
.\TestPort.ps1 -T TCP -L 443 -R 8080 -RemoteOS Windows -Credential $cred
```

Without `-Credential`, reverse tests prompt for credentials for each remote system. With `-SaveCredential`, a `file_cred_<system_name>.cred` file is created in the working directory and reused on later runs. Data exported with `Export-Clixml` is protected by Windows DPAPI and can normally be decrypted only by the same user on the same computer. An explicitly supplied `-Credential` takes precedence over a saved file.

## Remote OS detection

Detection runs only when `-R` is specified and `-RemoteOS` is `Auto`:

1. The script attempts a PowerShell Remoting session over WinRM. If it succeeds, the Windows path is used.
2. Otherwise, it attempts an SSH session and runs `uname -s`. If the command identifies Linux, the Linux path is used.
3. If neither attempt identifies the system, the script records `Unrecognized` and skips reverse port tests for that host.

The script **does not** infer the OS from port 3389 or from port 22 merely being open. If you already know the OS, use `-RemoteOS Windows` or `-RemoteOS Linux` to skip detection. Reverse tests still require working WinRM or SSH access and valid credentials.

## Results and limitations

The log is written to `log_connection-YYYY-MM-DD_HH-mm-ss.log` in the working directory. It includes ping results, OS detection (when needed), and each port-test result. The script does not generate a CSV file.

For TCP, a successful test confirms that a connection was established. A failed attempt is logged as a closed port, but the log does not always distinguish a refusal from a timeout, firewall filtering, or a name-resolution error.

For UDP, no response is logged as **inconclusive**, not as a closed port: many services ignore probe packets they do not recognize. Likewise, `nc -zu` on Linux cannot by itself confirm that a UDP port is open. Reliable UDP testing requires a valid request for the application protocol and, if needed, a dedicated tool.

The local IP address used for reverse tests is selected based on the route to each remote system. If no local address can be determined, reverse tests for that host are skipped.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| `system.txt` not found | Create it in the working directory or use `-SystemListPath`. |
| Ping fails | Port tests still continue; check their results in the log. |
| OS detection returns `Unrecognized` | Check WinRM/SSH, credentials, the SSH host key, and the log. If you know the OS, use `-RemoteOS`. |
| `Posh-SSH` module is missing | Install the module on the local computer. |
| `nc` is missing | Install netcat on the remote Linux system. |
| Reverse test from Windows fails | Check WinRM, the user's remoting permissions, and the firewall. |
| Saved `.cred` file no longer works | Remove that host's credential file and enter credentials again, or supply `-Credential`. |
