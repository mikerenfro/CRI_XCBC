[CmdletBinding()]
param (
    [Parameter(Mandatory=$False)][String]$OU = "OU=BLDG1xx,OU=PC Labs,OU=University Workstations,DC=university,DC=edu",
    [Parameter(Mandatory=$False)][String]$ScopeId = "10.10.10.0",
    [Parameter(Mandatory=$False)][String]$Pattern = "",
    [Parameter(Mandatory=$False)][String]$PatternFile = "",
    [Parameter(Mandatory=$False)][Switch]$Revert = $False,
    [Parameter(Mandatory=$False)][String]$Ohpc = '10.10.10.123',
    [Parameter(Mandatory=$False)][String]$BootFile = '/warewulf/ipxe/bin-i386-pcbios/undionly.kpxe',
    [Parameter(Mandatory=$False)][String]$Class = 'iPXE',
    [Parameter(Mandatory=$False)][String]$UrlPath = 'WW/ipxe/cfg',
    [Parameter(Mandatory=$False)][String]$DhcpServer = 'univdhcp01'
)

Function IS-InSubnet() 
{ 
 
[CmdletBinding()] 
[OutputType([bool])] 
Param( 
    [Parameter(Mandatory=$true, 
     ValueFromPipelineByPropertyName=$true, 
     Position=0)] 
    [validatescript({([System.Net.IPAddress]$_).AddressFamily -match 'InterNetwork'})] 
    [string]$ipaddress="", 
    [Parameter(Mandatory=$true, 
     ValueFromPipelineByPropertyName=$true, 
     Position=1)] 
    [validatescript({(([system.net.ipaddress]($_ -split '/'|select -first 1)).AddressFamily -match 'InterNetwork') -and (0..32 -contains ([int]($_ -split '/'|select -last 1) )) })] 
    [string]$Cidr="" 
    ) 
    Begin{ 
        [int]$BaseAddress=[System.BitConverter]::ToInt32((([System.Net.IPAddress]::Parse(($cidr -split '/'|select -first 1))).GetAddressBytes()),0) 
        [int]$Address=[System.BitConverter]::ToInt32(([System.Net.IPAddress]::Parse($ipaddress).GetAddressBytes()),0) 
        [int]$mask=[System.Net.IPAddress]::HostToNetworkOrder(-1 -shl (32 - [int]($cidr -split '/' |select -last 1))) 
    } 
    Process{ 
        if( ($BaseAddress -band $mask) -eq ($Address -band $mask)) 
        {
            $status=$True 
        } else {
        $status=$False 
        } 
    } 
    end { Write-output $status } 
}

$GetAdcArgs = @{
 Filter = '*'
 SearchBase = $OU
}

if ($Pattern -eq "" -and $PatternFile -eq "") {
	echo "Must specify either -Pattern or -PatternFile"
	exit 1
}
if ($Pattern -ne "" -and $PatternFile -ne "") {
	echo "Must specify either -Pattern or -PatternFile, not both"
	exit 1
}
if ( $PatternFile -ne "") {
	$PatternList = Get-Content $PatternFile | Where-Object { !$_.StartsWith("#") }
}
else {
	$PatternList = @($Pattern)
}

$PatternList | foreach {
	$Pattern = $_
	Get-ADComputer @GetAdcArgs | Where-Object -Property Name -Like $Pattern | foreach {
		$HostName = $_.DNSHostName
		$ClientIP = $(Resolve-DnsName $HostName -Type A |
			Select-Object -ExpandProperty IPAddress)
		echo $ClientIP
		#$ClientMac = $(Get-DhcpServerv4Reservation -IPAddress $ClientIP -ComputerName $DhcpServer | Select-Object -ExpandProperty ClientId)
		$GetLeaseArgs = @{
			ComputerName = $DhcpServer
			ScopeId = $ScopeId
		}
		$ClientMac = $(Get-DhcpServerv4Lease @GetLeaseArgs |
			Where-Object -Property ipaddress -eq $ClientIP |
			Select-Object -ExpandProperty ClientId)
		echo $ClientMac
		$ClientMacDash = $ClientMac.Replace('-',':')
		echo $ClientMacDash
		$Options = @{
				ReservedIP = ${ClientIP}
				ComputerName = $DhcpServer
			}
		if ($Revert -eq $True) {
			echo "Will revert $HostName with IP $ClientIP and MAC $ClientMac to defaults"
			# Remove-DhcpServerv4OptionValue @Options -OptionId 66
			# Remove-DhcpServerv4OptionValue @Options -OptionId 67
			# Remove-DhcpServerv4OptionValue @Options -OptionId 67 -UserClass ${Class}
			$RemoveReservationArgs = @{
				ComputerName = $DhcpServer
				ClientId = $ClientMac
				ScopeId = $ScopeId
			}
			Remove-DhcpServerv4Reservation @RemoveReservationArgs
		}
		else {
			echo "Will set $HostName with IP $ClientIP and MAC $ClientMac to boot OpenHPC"
			$Url = "http://${Ohpc}/${UrlPath}/${ClientMacDash}"
			$GetLeaseOptions = @{
				ComputerName = $DhcpServer
				ScopeId = $ScopeId
			}
			$SetReservationOptions =@{
				ComputerName = $DhcpServer
			}
			Get-DhcpServerv4Lease @GetLeaseOptions |
				Where-Object -Property IPAddress -eq $ClientIP |
					Set-DhcpServerv4Reservation @SetReservationOptions
			Set-DhcpServerv4OptionValue @Options -OptionId 66 -Value ${Ohpc}
			Set-DhcpServerv4OptionValue @Options -OptionId 67 -Value ${BootFile}
			Set-DhcpServerv4OptionValue @Options -UserClass ${Class} -OptionId 67 -Value ${Url}
		}
	}
}

if ( $(Get-DhcpServerv4Failover -ComputerName $DhcpServer | Where-Object {$_.ScopeId -contains $ScopeId} | Measure-Object).count -gt 0 ) {
	Invoke-DhcpServerv4FailoverReplication -force -ComputerName $DhcpServer $(Get-DhcpServerv4Failover -ComputerName $DhcpServer | Where-Object {$_.ScopeId -contains $ScopeId} | select -ExpandProperty name)
}
