###########################################################################################################################################
## Description: Script that it tests some connections between 2 system (Windows vs Windows or Windows vs Linux) through a specific port
##              To use this script you need a library -> Install-Module -Name Posh-SSH
##
## Author: Matteo Z.
###########################################################################################################################################

param (
    [Parameter()] [Alias('T')] [string]$port_type,
    [Parameter()] [Alias('L')] [string]$ports_local_to_remote,
    [Parameter()] [Alias('R')] [string]$ports_remote_to_local
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
    Write-Host " - Initially it tries to ping the systems reported in the file (if a system is unreachable, it goes to the next one)"
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

function Convert-ToPortList {
    param (
        [string]$Ports,
        [string]$ParameterName
    )

    $port_list = @()

    if ([string]::IsNullOrWhiteSpace($Ports)) {
        return $port_list
    }

    foreach ($item in ($Ports -split ",")) {
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
            } else {
                "`tAttention!! Port $port_type $port closed on remote system!" >> $log_connection
            }
        } else {
            "`tFailed to test port $port_type $port - the port must be > 0 or <= 65535" >> $log_connection
        }
    }
}

function Test-OS_System {
    Start-Sleep -Seconds 1.5
    # to verify if the system is a Windows (port RDP: 3389/TCP) or a Linux (port SSH: 22/TCP)
    $result = Test-Port -ComputerName $system -Port 3389 -Protocol TCP -Timeout $Timeout
    # Write-Host "Windows? $result"
    
    if ($result) {
        $flag_OS = "Windows"
    } else {
        $result = Test-Port -ComputerName $system -Port 22 -Protocol TCP -Timeout $Timeout
        # Write-Host "Linux? $result"
        
        if ($result) {
            $flag_OS = "Linux"
        } else {
            $flag_OS = "Unrecognized"
        }
    }
    
    "`tOS remote system: $flag_OS" >> $log_connection

    return $flag_OS
}

function obtain_cred {
    if (Test-Path $file_cred -PathType leaf) {
        $cred = Import-Clixml -Path $file_cred
    } else {
        $cred = (Get-Credential -Message "Type the credential to login on remote system")
        $cred | Export-Clixml -Path $file_cred
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
                    $cred = obtain_cred
                    $result = Invoke-Command -ComputerName $system -Credential $cred -ErrorAction Stop -ScriptBlock {
                        param ($target_ip, $target_port, $target_protocol, $timeout_ms)
                        if ($target_protocol -eq "TCP") {
                            return Test-NetConnection -ComputerName $target_ip -Port $target_port -InformationLevel Quiet
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
                    } else {
                        "`tAttention!! Port $port_type $port closed on local system!" >> $log_connection
                    }
                } catch {
                    # Write-Host -ForegroundColor "red" "An error occurred: $_"
                    "`tAn error occurred to test the port $port_type $port from remote to local system ($_)!" >> $log_connection
                }
            } elseif ($flag_OS -eq "Linux") {
                try {
                    $cred = obtain_cred
                    # to initialize the SSH connection to the system (accepting automatically the host key)
                    $session = New-SSHSession -ComputerName $system -Credential $cred -ErrorAction Stop -AcceptKey

                    # Write-Host -ForegroundColor "green" "Connected to $system"
                    # to run remote commands as if you were on the Linux system
                    if ($port_type -eq "TCP") {
                        $cmd = "nc -zv $local_ip $port"
                    } elseif ($port_type -eq "UDP") {
                        $cmd = "nc -zuv $local_ip $port"
                    }

                    $result = Invoke-SSHCommand -SSHSession $session -Command $cmd

                    if ($result.ExitStatus -eq 127) {
                        "`tAttention!! The command 'netcat' has not been found on remote system, you should install it before continue!" >> $log_connection
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
$local_ip = (Get-NetIPAddress -AddressState Preferred -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1).IPAddress
$work_dir = "C:\temp"
$system_list = Join-Path $work_dir "system.txt"     # if exist C:\Temp instead of C:\temp, the script does not fail
$log_connection = Join-Path $work_dir "log_connection-$date.log"
$Timeout = 1000
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
                        if ($system.Length -eq 0) {
                            continue        # to skip the empty row
                        } else {
                            Start-Sleep -Seconds 1.0
                            $system = $system.Trim()        # to remove all leading and trailing white-space characters
                            Write-Host -ForegroundColor "green" "`nTesting the remote system: $system ...`n"
                            "`n$cont_system) Remote system = $system`n" >> $log_connection

                            if (Test-Connection -ComputerName $system -Count 2 -Quiet) {
                                "`tPing OK" >> $log_connection
                                Test-Port_LocalToRemote

                                if ($list_ports_remote_to_local.Length -ne 0) {    # if there are also some ports to test from remote to local system...
                                    $safe_system_name = $system -replace '[\\/:*?"<>|]', '_'
                                    $file_cred = Join-Path $work_dir "file_cred_$safe_system_name.cred"
                                    $flag_OS = Test-OS_System
                                    Write-Host "  OS remote system: $flag_OS"
                                    Test-Port_RemoteToLocal
                                    # Remove-Item $file_cred
                                }
                            } else {
                                Write-Host -ForegroundColor "red" "  Ping KO"
                                "`tPing KO" >> $log_connection
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
