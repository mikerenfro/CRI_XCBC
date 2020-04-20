[CmdletBinding()]
param (
    [Parameter(Mandatory=$False)][String]$OU = "OU=PC Labs,OU=University Workstations,DC=university,DC=edu",
    [Parameter(Mandatory=$False)][String]$Pattern
)

function Create-CpuId-Array {
    <#
    .SYNOPSIS
      Creates an array of Intel CPU IDs and families
    .DESCRIPTION
      The Create-CpuId-Array cmdlet creates an array of Intel CPU IDs and families.
      Array is keyed by lowercase family name (cascade-lake, nehalem-ex, ...) and
      each value is the contents of the Intel ARK webpage for that family (including
      the CPU IDs for that family, such as 2650).
    #>
    [CmdletBinding()]
    param()
    process {
        # If CPU IDs are not cached, or cache is too old
        if ( -not (Test-Path cpuid_array.xml) -or
         (Test-Path cpuid_array.xml -OlderThan (Get-Date).AddDays(-7)) ) {
	        # https://www.reddit.com/r/PowerShell/comments/4koj4u/is_cpu_skylake_or_note/
            $CpuArray = @(
		    '124664/cascade-lake',
		    '97787/coffee-lake',
		    '82879/kaby-lake',
		    '68926/ivy-bridge-ep',
		    '64275/sandy-bridge-en',
		    '64238/nehalem-ex',
		    '54499/nehalem-ep',
		    '54534/westmere-ep',
		    '42174/haswell',
		    '37572/skylake',
		    '38530/broadwell',
		    '29902/ivy-bridge',
		    '29900/sandy-bridge',
		    '26555/harpertown',
		    '25006/dunnington',
		    '25005/tigerton',
		    '3374/tulsa',
		    '6191/paxville')
	        $ArkPrefix = 'https://ark.intel.com/content/www/us/en/ark/products/codename/'
	        $ArkSuffix = '.html'
	        $WebArray = @{}
            $CpuArray | foreach {
		    $Url = $ArkPrefix+$_+$ArkSuffix
		    $Web = Invoke-WebRequest $Url -UseBasicParsing
		    $Key = $_.split('/')[-1]
		    $WebArray[$Key] = $Web.Content
	    }
            $WebArray | Export-Clixml -Path cpuid_array.xml
        }
        else {
        $WebArray = import-clixml -Path cpuid_array.xml
    }
    }
    end {
        $WebArray
    }
}


function Get-Ram() {
    <#
    .SYNOPSIS
      Returns the total amount of RAM installed in a computer.
    .DESCRIPTION
      The Get-Ram cmdlet returns the total amount of RAM installed in a computer.
    #>
    [CmdletBinding()]
    param(
        [string]$Computer
    )
    process {
        $Ram = Get-WmiObject -Class Win32_PhysicalMemory -ComputerName $Computer |
            Measure-Object -Property Capacity -Sum
    }
    end {
	    $Ram
    }
}


function Get-CpuId() {
    <#
    .SYNOPSIS
      Returns the family of CPU installed in a computer.
    .DESCRIPTION
      The Get-CpuId cmdlet returns the type of CPU (Broadwell, Haswell, etc.) installed in a computer.
    #>
    [CmdletBinding()]
    param (
        [string]$Computer,
        [hashtable]$CpuIdArray
    )
    process {
        $GetWmiObjectParams = @{
            Class = "Win32_Processor"
            ComputerName = $Computer
        }
	    $CpuId = ((Get-WmiObject @GetWmiObjectParams).name) -Replace '.*(\w?\d{4} ?v?\d?).*','$1'
        # So far, regex tested on:
        # Gold 6148 -> 6148 -> skylake
        # E5-2609 v4 -> 2609 v4 -> broadwell
        # E5-2650 v3 -> 2650 v3 -> haswell
        # X5660 -> X5660 -> westmere-ep
        if (($CpuId | Measure-Object).Count -gt 1) {
            $CpuId = $CpuId[0].Trim()
        }
        else {
            $CpuId = $CpuId.Trim()
        }
        $Features = 'NA'
	    foreach ($Key in $CpuIdArray.Keys) {
	        if ($CpuIdArray[$Key] -match $CpuId) {
		        $Features = $Key
			    break
		    }
	    }
    }
    end {
	    $Features
    }
}


function Get-Network-Config() {
    <#
    .SYNOPSIS
      Returns the IP and MAC address of a computer corresponding to its default route.
    .DESCRIPTION
      The Get-Network-Config cmdlet returns the IPv4 IP and MAC address of a computer.
      Only one IP and MAC will be returned: the one attached to the default route for the computer.
    #>
    [CmdletBinding()]
    param (
        [string]$Computer
    )
    process {
        $GetWmiObjectParams = @{
            Class = "Win32_NetworkAdapterConfiguration"
            ComputerName = "$Computer"
            Filter = 'IPEnabled=True'
            ErrorAction = "Stop"
        }
	    $AC = Get-WmiObject @GetWmiObjectParams |where{$_.DefaultIPGateway}
    }
    end {
        if (($AC| Select-Object -ExpandProperty IPAddress | Measure-Object).count -gt 1) {
            (($AC| Select-Object -ExpandProperty IPAddress) -like '*.*').Trim()
        } else {
            ($AC| Select-Object -ExpandProperty IPAddress).Trim()
        }
	    ([string]$AC.MacAddress).Trim()
    }
}


function Get-CPU-Details() {
    <#
    .SYNOPSIS
      Returns the sockets, cores, and threads available in a computer.
    .DESCRIPTION
      The Get-CPU-Details cmdlet returns number of sockets, cores, and threads available in a computer.
    #>
    [CmdletBinding()]
    param (
        [string]$Computer
    )
    process {
	    $Cpu = Get-WmiObject -class Win32_Processor -ComputerName $Computer
	    $CpuCount = ($Cpu | Measure-Object).Count
    }
    end {
        $CpuCount
        if ($CpuCount -gt 1) {
            $Cpu[0].NumberOfCores # cores per socket
	        $Cpu[0].NumberOfLogicalProcessors # threads per socket
        } else {
            $Cpu.NumberOfCores
            $Cpu.NumberOfLogicalProcessors
        }
    }
}


$ReservedBytes = 2*1024*1024*1024

echo @"
---
  compute_nodes:
"@
$j = 0
$GetAdcArgs = @{
 Filter = '*'
 SearchBase = $OU
}
$CpuIdArray = Create-CpuId-Array
Get-ADComputer @GetAdcArgs | Where-Object -Property Name -Like $Pattern | foreach {
    $ComputerName = ($_.Name).ToLower()
    try {
		Write-Progress "$ComputerName"
		Write-Progress "Getting network config"
		$IP, $Mac = Get-Network-Config $ComputerName
		if ($IP) {
			Write-Progress "Getting CPU config"
			$Sockets, $CoresPerSocket, $ThreadsPerSocket = Get-CPU-Details $ComputerName
			Write-Progress "Getting CPU family"
			$Features = Get-CpuId $ComputerName $CpuIdArray
			Write-Progress "Getting RAM config"
			$Ram = Get-RAM $ComputerName
			$UsableRam = ([int64]($Ram.Sum))-$ReservedBytes
			if (([int]$Sockets) -ne 0) {
                $Cps = $CoresPerSocket
                $Tpc = $ThreadsPerSocket/$CoresPerSocket
				echo @"
  - { name: "compute-${j}", vnfs: '{{compute_chroot}}',
      ram: ${UsableRam},
      features: ${Features}, cpus: -1, sockets: ${Sockets}, corespersocket: ${Cps}, threadspercore: ${Tpc},
      mac: "$Mac", ip: "$IP"} # $ComputerName
"@
				$j += 1
			}
		} else {
			throw $error[0].Exception
		}
	}
	catch {
		Write-Error "Some exception occurred on ${ComputerName}: $error[0].Exception"
	}
}
