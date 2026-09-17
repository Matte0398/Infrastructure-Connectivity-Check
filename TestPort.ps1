###########################################################################################################################################
## Description: Script that it tests some connections between 2 system (Windows vs Windows or Windows vs Linux) through a specific port
##              To use this script you need a library -> Install-Module -Name Posh-SSH
##
## Author: Matteo Z.
###########################################################################################################################################

param (
    [Parameter()] [Alias('T')] [ValidateSet('TCP','UDP')] [string]$port_type,
    # object[] accepts both PowerShell arrays (-L 80,443) and quoted CSV values (-L "80,443").
    [Parameter()] [Alias('L')] [object[]]$ports_local_to_remote,
    [Parameter()] [Alias('R')] [object[]]$ports_remote_to_local,
    [ValidateSet('Auto','Windows','Linux')] [string]$RemoteOS = 'Auto',
    [ValidateRange(100,60000)] [int]$Timeout = 1000,
    [string]$WorkDirectory = 'C:\temp',
    [string]$SystemListPath,
    [PSCredential]$Credential,
    [switch]$SaveCredential,
    [switch]$TrustSshHostKey
)

function print_usage {
    Write-Host -ForegroundColor "red" "`nDescription:"
    Write-Host "  Script that it tests some connections between 2 system (Windows vs Windows or Windows vs Linux) through a specific port"
    Write-Host "  To test ports from a Linux remote system to the local system you need a library -> Install-Module -Name Posh-SSH"
    Write-Host "  The local system will be localhost so: $local_system ($local_ip)"
    Write-Host "  The remote system can be: Windows or Linux"
    Write-Host "  The UDP test is indicative because an open UDP port may not send a response"
    Write-Host -ForegroundColor "red" "`nUsage:"
    Write-Host "  1) $script -T <port_type> -L <ports_local_to_remote>"
    Write-Host "  2) $script -T <port_type> -L <ports_local_to_remote> -R <ports_remote_to_local>"
    Write-Host -ForegroundColor "red" "`nOptions:"
    Write-Host "  -T        Port type (possible values: TCP or UDP; lower case is accepted too)"
    Write-Host "  -L        List of valid ports to test from local system to remote system (e.g. '-L 5985,3181')"
    Write-Host "  -R        Optional list of valid ports to test from remote system to local system (e.g. '-R 8080,3183')"
    Write-Host -ForegroundColor "red" "`nScript operations:"
    Write-Host " - It creates the working folder if it does not exist: $work_dir"
    Write-Host " - It reads a list of remote systems in: $system_list"
    Write-Host " - It records the ping result, but continues the port tests because ICMP may be blocked"
    Write-Host " - It ignores invalid ports and keeps only numeric values between 1 and 65535"
    Write-Host " - It tests some connections from local system to remote system"
    Write-Host " - If you launch as 2), it verifies if the remote system is Windows or Linux"
    Write-Host " - If you launch as 2), it tests also some connections from remote system to local system"
    Write-Host " - On Linux remote systems it uses Posh-SSH locally and the netcat program remotely"
    Write-Host " - It creates a log with all tests done in: $log_connection"
    Write-Host "`nThe content of the file $system_list must be:"
    Write-Host "<system1>"
    Write-Host "<system2>"
    Write-Host "...`n"
}

function Test-Port {
    param (
        [string]$ComputerName,
        [int]$Port,
        [string]$Protocol,
        [int]$Timeout
    )

    $result = $false
    # Write-Host "Computer name = $ComputerName - Port = $Port - Protocol = $Protocol - Timeout = $Timeout"

    if ($Protocol -eq 'TCP') {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $null

        try {
            # BeginConnect is used instead of Connect so that this script controls the timeout.
            # EndConnect is still required: a signaled wait handle does not guarantee success.
            $connect = $tcpClient.BeginConnect($ComputerName, $Port, $null, $null)
            $wait = $connect.AsyncWaitHandle.WaitOne($Timeout, $false)

            if ($wait) {
                $tcpClient.EndConnect($connect)
                $result = $true
            }
        } catch {
            $result = $false
        } finally {
            if ($connect -and $connect.AsyncWaitHandle) {
                $connect.AsyncWaitHandle.Close()
            }

            $tcpClient.Close()
            $tcpClient.Dispose()
        }
    } elseif ($Protocol -eq 'UDP') {
        $udpClient = New-Object System.Net.Sockets.UdpClient

        try {
            # UDP has no connection handshake. Only an application reply can confirm
            # that the service answered; a timeout is therefore treated as inconclusive.
            $udpClient.Client.ReceiveTimeout = $Timeout
            $udpClient.Connect($ComputerName, $Port)
            $a = New-Object System.Text.ASCIIEncoding
            $byte = $a.GetBytes("$(Get-Date)")
            [void]$udpClient.Send($byte, $byte.Length)
            $remoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $receiveBytes = $udpClient.Receive([ref]$remoteEndpoint)
            $returnData = $a.GetString($receiveBytes)

            if ($returnData) {
                $result = $true
            }
        } catch {
            $result = $false
        } finally {
            $udpClient.Close()
            $udpClient.Dispose()
        }
    }

    return $result
}

function Get-LocalIpForRemoteSystem {
    param ([string]$ComputerName)
    $client = New-Object System.Net.Sockets.UdpClient
    try {
        # Connect() on a UDP socket selects the route and local interface without
        # sending traffic. This avoids choosing an unrelated VPN/network adapter.
        $client.Connect($ComputerName, 65530)
        return ([System.Net.IPEndPoint]$client.Client.LocalEndPoint).Address.IPAddressToString
    } catch {
        return $null
    } finally {
        $client.Dispose()
    }
}

function Convert-ToPortList {
    param (
        [object[]]$Ports,
        [string]$ParameterName
    )

    $port_list = @()

    if ([string]::IsNullOrWhiteSpace($Ports)) {
        return $port_list
    }

    # Normalize both array and CSV input to a single sequence of candidate values.
    foreach ($item in (($Ports -join ',') -split ",")) {
        $clean_item = $item.Trim()
        $port_number = 0

        if ([int]::TryParse($clean_item, [ref]$port_number) -and $port_number -gt 0 -and $port_number -le 65535) {
            $port_list += $port_number
        } elseif ($clean_item -ne "") {
            Write-Host -ForegroundColor "red" "Attention!! The value '$clean_item' in $ParameterName is not a valid port and will be ignored!"
        }
    }

    return $port_list
}

function Import-PoshSSHModule {
    # Avoid importing the module repeatedly during OS detection and Linux tests.
    if (Get-Module -Name Posh-SSH) {
        return $true
    }

    try {
        Import-Module Posh-SSH -ErrorAction Stop
        return $true
    } catch {
        "`tAttention!! The module 'Posh-SSH' has not been found, you should install it before continue!" >> $log_connection
        return $false
    }
}

function Test-Port_LocalToRemote {
    foreach ($port in $list_ports_local_to_remote) {
        Start-Sleep -Seconds 1.0
        Write-Host "  Testing the port $port_type $port opening on this system ..."

        if ($port -gt 0 -and $port -le 65535) {
            $result = Test-Port -ComputerName $system -Port $port -Protocol $port_type -Timeout $Timeout
            # Write-Host "Result = $result"

            if ($result) {
                "`tPort $port_type $port opened on remote system" >> $log_connection
            } elseif ($port_type -eq 'UDP') {
                "`tPort UDP ${port}: no reply received; result inconclusive" >> $log_connection
            } else {
                "`tAttention!! Port $port_type $port closed on remote system!" >> $log_connection
            }
        } else {
            "`tFailed to test port $port_type $port - the port must be > 0 or <= 65535" >> $log_connection
        }
    }
}

function Test-OS_System {
    param ([PSCredential]$cred)

    if ($RemoteOS -ne 'Auto') {
        "`tOS remote system: $RemoteOS (specified by parameter)" >> $log_connection
        return $RemoteOS
    }

    # In Auto mode, detect the remote execution mechanism that is actually usable.
    # A successful WinRM session identifies Windows more reliably than checking RDP/3389.
    $flag_OS = $null
    $winrmError = $null
    $sshError = $null
    $probeSession = $null
    try {
        $sessionOption = New-PSSessionOption -OpenTimeout $Timeout
        $probeSession = New-PSSession -ComputerName $system -Credential $cred -SessionOption $sessionOption -ErrorAction Stop
        $flag_OS = 'Windows'
    } catch {
        $winrmError = $_.Exception.Message
    } finally {
        if ($probeSession) {
            Remove-PSSession -Session $probeSession -ErrorAction SilentlyContinue
        }
    }

    if (-not $flag_OS) {
        # If WinRM is unavailable, try SSH and verify Linux with uname. Merely finding
        # SSH open is insufficient because Windows can also run an OpenSSH server.
        $probeSession = $null
        try {
            if (-not (Import-PoshSSHModule)) {
                throw "The Posh-SSH module is not available."
            }
            $sshArgs = @{
                ComputerName = $system
                Credential   = $cred
                ErrorAction  = 'Stop'
            }
            if ($TrustSshHostKey) { $sshArgs.AcceptKey = $true }
            $probeSession = New-SSHSession @sshArgs
            $osProbe = Invoke-SSHCommand -SSHSession $probeSession -Command 'uname -s' -ErrorAction Stop
            if ($osProbe.ExitStatus -eq 0 -and (($osProbe.Output -join ' ') -match '^Linux')) {
                $flag_OS = 'Linux'
            } else {
                $flag_OS = 'Unrecognized'
                $sshError = "SSH connected, but 'uname -s' did not identify Linux."
            }
        } catch {
            $sshError = $_.Exception.Message
            $flag_OS = 'Unrecognized'
        } finally {
            if ($probeSession) {
                Remove-SSHSession -SSHSession $probeSession | Out-Null
            }
        }
    }

    "`tOS remote system: $flag_OS" >> $log_connection
    if ($flag_OS -eq 'Unrecognized') {
        "`tWinRM probe failed: $winrmError" >> $log_connection
        "`tSSH probe failed: $sshError" >> $log_connection
    }

    return $flag_OS
}

function Get-SavedCredential {
    if ($Credential) { return $Credential }
    # Export-Clixml encrypts the password with Windows DPAPI. The resulting file can
    # normally be decrypted only by the same Windows user on the same computer.
    if ($SaveCredential -and (Test-Path $file_cred -PathType leaf)) {
        $cred = Import-Clixml -Path $file_cred
    } else {
        $cred = (Get-Credential -Message "Type the credential to login on remote system")
        if ($SaveCredential) { $cred | Export-Clixml -Path $file_cred }
    }

    return $cred
}

function Test-Port_RemoteToLocal {
	param (
		[PSCredential] $cred
	)

    if ($flag_OS -eq "Linux" -and -not (Import-PoshSSHModule)) {
        return
    }

    foreach ($port in $list_ports_remote_to_local) {
        Start-Sleep -Seconds 1.0
        Write-Host "  Testing the port $port_type $port opening on local system ($local_system - $local_ip) ..."

        if ($port -gt 0 -and $port -le 65535) {
            if ($flag_OS -eq "Windows") {
                try {
                    # This block runs on the Windows remote host, so the target is the
                    # local address and the result describes the reverse direction.
                    $result = Invoke-Command -ComputerName $system -Credential $cred -ErrorAction Stop -ScriptBlock {
                        param ($target_ip, $target_port, $target_protocol, $timeout_ms)
                        if ($target_protocol -eq "TCP") {
                            $client = New-Object System.Net.Sockets.TcpClient
                            $async = $null
                            try {
                                # Keep the same explicit timeout used by the local TCP test.
                                $async = $client.BeginConnect($target_ip, $target_port, $null, $null)
                                if (-not $async.AsyncWaitHandle.WaitOne($timeout_ms, $false)) { return $false }
                                $client.EndConnect($async)
                                return $true
                            } catch { return $false }
                            finally {
                                if ($async) { $async.AsyncWaitHandle.Close() }
                                $client.Dispose()
                            }
                        }

                        $udpClient = New-Object System.Net.Sockets.UdpClient

                        try {
                            $udpClient.Client.ReceiveTimeout = $timeout_ms
                            $udpClient.Connect($target_ip, $target_port)
                            $a = New-Object System.Text.ASCIIEncoding
                            $byte = $a.GetBytes("$(Get-Date)")
                            [void]$udpClient.Send($byte, $byte.Length)
                            $remoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                            [void]$udpClient.Receive([ref]$remoteEndpoint)
                            return $true
                        } catch {
                            return $false
                        } finally {
                            $udpClient.Close()
                            $udpClient.Dispose()
                        }
                    } -ArgumentList $local_ip, $port, $port_type, $Timeout

                    if ($result) {
                        "`tPort $port_type $port opened on local system" >> $log_connection
                    } elseif ($port_type -eq 'UDP') {
                        "`tPort UDP ${port}: no reply received; result inconclusive" >> $log_connection
                    } else {
                        "`tAttention!! Port $port_type $port closed on local system!" >> $log_connection
                    }
                } catch {
                    # Write-Host -ForegroundColor "red" "An error occurred: $_"
                    "`tAn error occurred to test the port $port_type $port from remote to local system ($_)!" >> $log_connection
                }
            } elseif ($flag_OS -eq "Linux") {
                try {
                    # AcceptKey is intentionally opt-in: trusting unknown SSH keys by
                    # default would hide a possible host-identity change/MITM attack.
                    $sshArgs = @{ ComputerName = $system; Credential = $cred; ErrorAction = 'Stop' }
                    if ($TrustSshHostKey) { $sshArgs.AcceptKey = $true }
                    $session = New-SSHSession @sshArgs

                    # Write-Host -ForegroundColor "green" "Connected to $system"
                    # to run remote commands as if you were on the Linux system
                    if ($port_type -eq "TCP") {
                        $cmd = "nc -zv $local_ip $port"
                    } elseif ($port_type -eq "UDP") {
                        $cmd = "nc -zuv $local_ip $port"
                    }

                    $result = Invoke-SSHCommand -SSHSession $session -Command $cmd

                    # Exit 127 means nc is missing. For UDP, even exit 0 is not proof
                    # of an open port, because there is no handshake to validate it.
                    if ($result.ExitStatus -eq 127) {
                        "`tAttention!! The command 'netcat' has not been found on remote system, you should install it before continue!" >> $log_connection
                    } elseif ($port_type -eq 'UDP') {
                        "`tPort UDP ${port}: netcat exit status $($result.ExitStatus); result inconclusive" >> $log_connection
                    } elseif ($result.ExitStatus -eq 0) {
                        "`tPort $port_type $port opened on local system" >> $log_connection
                    } else {
                        "`tAttention!! Port $port_type $port closed on local system!" >> $log_connection
                    }
                } catch {
                    # Write-Host -ForegroundColor "red" "An error occurred: $_"
                    "`tAn error occurred to test the port $port_type $port from remote to local system ($_)!" >> $log_connection
                } finally {
                    # to end the SSH session if there is one open
                    if ($session) {
                        Remove-SSHSession $session | Out-Null
                        # Write-Host -ForegroundColor "green" "Connection closed to $system"
                    }
                }
            } else {
                "`tFailed to test port $port_type $port from $system ($flag_OS)" >> $log_connection
            }
        } else {
            "`tFailed to test port $port_type $port - the port must be > 0 or <= 65535" >> $log_connection
        }
    }
}


########## MAIN ##########

$script = $MyInvocation.MyCommand.Name
$date = Get-Date -f yyyy-MM-dd_HH-mm-ss
$local_system = $env:COMPUTERNAME       # environment variable with the computer name
try {
    # Initial fallback address for help/log output. Inside the host loop it is replaced
    # with the address selected for the route to that specific destination.
    $local_ip = (Get-NetIPAddress -AddressState Preferred -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -First 1).IPAddress
} catch {
    $local_ip = $null
    Write-Warning "Unable to determine the local IPv4 address: $($_.Exception.Message)"
}
$work_dir = $WorkDirectory
$system_list = if ($SystemListPath) { $SystemListPath } else { Join-Path $work_dir "system.txt" }
$log_connection = Join-Path $work_dir "log_connection-$date.log"
$list_ports_local_to_remote = @()
$list_ports_remote_to_local = @()
$cont_system = 1

if (-not (Test-Path $work_dir -PathType Container)) {
    New-Item -Path $work_dir -ItemType Directory -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($port_type) -or [string]::IsNullOrWhiteSpace($ports_local_to_remote)) {
    print_usage
} else {
    $port_type = $port_type.ToUpperInvariant()

    if ($port_type -eq "TCP" -or $port_type -eq "UDP") {
        # to create a list of valid ports (keeping in mind also the comma)
        $list_ports_local_to_remote = @(Convert-ToPortList -Ports $ports_local_to_remote -ParameterName "-L")

        if (-not [string]::IsNullOrWhiteSpace($ports_remote_to_local)) {
            $list_ports_remote_to_local = @(Convert-ToPortList -Ports $ports_remote_to_local -ParameterName "-R")
        }

        if ($list_ports_local_to_remote.Length -ne 0) {
                if (Test-Path $system_list -PathType leaf) {
                    "Tests made from $local_system ($local_ip)`n---------------------------------------" > $log_connection
                    $file_content = Get-Content $system_list

                    foreach ($system in $file_content) {
                        $system = $system.Trim()
                        if ([string]::IsNullOrWhiteSpace($system)) {
                            continue        # to skip the empty row
                        } else {
                            Start-Sleep -Seconds 1.0
                            $routed_ip = Get-LocalIpForRemoteSystem -ComputerName $system
                            if ($routed_ip) { $local_ip = $routed_ip }
                            Write-Host -ForegroundColor "green" "`nTesting the remote system: $system ...`n"
                            "`n$cont_system) Remote system = $system`n" >> $log_connection

                            # Ping is diagnostic only. Firewalls often block ICMP while
                            # allowing the TCP/UDP ports that this script must test.
                            if (Test-Connection -ComputerName $system -Count 2 -Quiet -ErrorAction SilentlyContinue) {
                                "`tPing OK" >> $log_connection
                            } else {
                                Write-Host -ForegroundColor "red" "  Ping KO"
                                "`tPing KO (port tests continue because ICMP may be blocked)" >> $log_connection
                            }

                            Test-Port_LocalToRemote
                            if ($list_ports_remote_to_local.Length -ne 0 -and $local_ip) {
                                # Replace invalid filename characters before using the host
                                # name as part of the optional credential-cache filename.
                                $safe_system_name = $system -replace '[\\/:*?"<>|]', '_'
                                $file_cred = Join-Path $work_dir "file_cred_$safe_system_name.cred"
                                try {
                                    $cred = Get-SavedCredential
                                    $flag_OS = Test-OS_System -cred $cred
                                    Write-Host "  OS remote system: $flag_OS"
                                    Test-Port_RemoteToLocal -cred $cred
                                } catch {
                                    "`tRemote tests skipped: $($_.Exception.Message)" >> $log_connection
                                }
                            } elseif ($list_ports_remote_to_local.Length -ne 0) {
                                "`tRemote tests skipped: unable to determine the local route address" >> $log_connection
                            }
                        }

                        $cont_system++
                    }

                    Start-Sleep -Seconds 1.0
                    Write-Host -ForegroundColor "yellow" "`nThe script has terminated!! You should verify in $log_connection and see all output!`n"
                } else {
                    Write-Host -ForegroundColor "red" "Attention!! The file $system_list with a list of the system has not been found, you must created it!"
                }
        } else {
            Write-Host -ForegroundColor "red" "Attention!! There aren't any port to test!"
        }
    } else {
        Write-Host -ForegroundColor "red" "Attention!! The port type must be TCP or UDP!"
    }
}
