<#
.SYNOPSIS
   This script demonstrates an xVC-vMotion where a live running Virtual Machine 
   is live migrated between two vCenter Servers which are NOT part of the
   same vCenter SSO Domain which is only available using the vSphere 6.0 API
.NOTES
   File Name  : run-cool-xVC-vMotion.ps1
   Author     : William Lam - @lamw
   Version    : 1.0
.LINK
    http://www.virtuallyghetto.com/2015/02/did-you-know-of-an-additional-cool-vmotion-capability-in-vsphere-6-0.html
.LINK
   https://github.com/lamw

.INPUTS
   sourceVC, sourceVCUsername, sourceVCPassword, 
   destVC, destVCUsername, destVCPassword, destVCThumbprint
   datastorename, clustername, vmhostname, vmnetworkname,
   vmname
.OUTPUTS
   Console output

.PARAMETER sourceVC
   The hostname or IP Address of the source vCenter Server
.PARAMETER sourceVCUsername
   The username to connect to source vCenter Server
.PARAMETER sourceVCPassword
   The password to connect to source vCenter Server
.PARAMETER destVC
   The hostname or IP Address of the destination vCenter Server
.PARAMETER destVCUsername
   The username to connect to the destination vCenter Server
.PARAMETER destVCPassword
   The password to connect to the destination vCenter Server
.PARAMETER destVCThumbprint
   The SSL Thumbprint (SHA1) of the destination vCenter Server (Certificate checking is enabled, ensure hostname/IP matches)
.PARAMETER datastorename
   The destination vSphere Datastore where the VM will be migrated to
.PARAMETER clustername
   The destination vSphere Cluster where the VM will be migrated to
.PARAMETER vmhostname
   The destination vSphere ESXi host where the VM will be migrated to
.PARAMETER vmnetworkname
   The destination vSphere VM Portgroup where the VM will be migrated to
.PARAMETER vmname
   The name of the source VM to be migrated
#>
param
(
   [Parameter(Mandatory=$true)]
   [string]
   $sourceVC,
   [Parameter(Mandatory=$true)]
   [string]
   $sourceVCUsername,
   [Parameter(Mandatory=$true)]
   [string]
   $sourceVCPassword,
   [Parameter(Mandatory=$true)]
   [string]
   $destVC,
   [Parameter(Mandatory=$true)]
   [string]
   $destVCUsername,
   [Parameter(Mandatory=$true)]
   [string]
   $destVCPassword,
   [Parameter(Mandatory=$true)]
   [string]
   $destVCThumbprint, 
   [Parameter(Mandatory=$true)]
   [string]
   $datastorename,
   [Parameter(Mandatory=$true)]
   [string]
   $clustername,
   [Parameter(Mandatory=$true)]
   [string]
   $vmhostname,
   [Parameter(Mandatory=$true)]
   [string]
   $vmnetworkname,
   [Parameter(Mandatory=$true)]
   [string]
   $vmname
);

## DEBUGGING
#$source = "LA"
#$vmname = "vMA" 
#
## LA->NY
#if ( $source -eq "LA") {
#  $sourceVC = "vcenter60-4.primp-industries.com"
#  $sourceVCUsername = "administrator@vghetto.local"
#  $sourceVCPassword = "VMware1!"
#  $destVC = "vcenter60-5.primp-industries.com" 
#  $destVCUsername = "administrator@vsphere.local"
#  $destVCpassword = "VMware1!"
#  $datastorename = "vesxi60-8-local-storage"
#  $clustername = "NY-Cluster" 
#  $vmhostname = "vesxi60-8.primp-industries.com"
#  $destVCThumbprint = "82:D0:CF:B5:CC:EA:FE:AE:03:BE:E9:4B:AC:A2:B0:AB:2F:E3:87:49"
#  $vmnetworkname = "NY-VM-Network"
#} else {
## NY->LA
#  $sourceVC = "vcenter60-5.primp-industries.com"
#  $sourceVCUsername = "administrator@vsphere.local"
#  $sourceVCPassword = "VMware1!"
#  $destVC = "vcenter60-4.primp-industries.com" 
#  $destVCUsername = "administrator@vghetto.local"
#  $destVCpassword = "VMware1!" 
#  $datastorename = "vesxi60-7-local-storage"
#  $clustername = "LA-Cluster" 
#  $vmhostname = "vesxi60-7.primp-industries.com"
#  $destVCThumbprint = "B8:46:B9:F3:6C:1D:97:8C:ED:A0:19:92:94:E6:1B:45:15:65:63:96"
#  $vmnetworkname = "LA-VM-Network"
#}

# Connect to Source vCenter Server
$sourceVCConn = Connect-VIServer -Server $sourceVC -user $sourceVCUsername -password $sourceVCPassword
# Connect to Destination vCenter Server
$destVCConn = Connect-VIServer -Server $destVC -user $destVCUsername -password $destVCpassword

# Source VM to migrate
$vm = Get-View (Get-VM -Server $sourceVCConn -Name $vmname) -Property Config.Hardware.Device
# Dest Datastore to migrate VM to
$datastore = (Get-Datastore -Server $destVCConn -Name $datastorename)
# Dest Cluster to migrate VM to
$cluster = (Get-Cluster -Server $destVCConn -Name $clustername)
# Dest ESXi host to migrate VM to
$vmhost = (Get-VMHost -Server $destVCConn -Name $vmhostname)

# Find Ethernet Device on VM to change VM Networks
$devices = $vm.Config.Hardware.Device
foreach ($device in $devices) {
   if($device -is [VMware.Vim.VirtualEthernetCard]) {
      $vmNetworkAdapter = $device
   }
}

# Relocate Spec for Migration
$spec = New-Object VMware.Vim.VirtualMachineRelocateSpec
$spec.datastore = $datastore.Id
$spec.host = $vmhost.Id
$spec.pool = $cluster.ExtensionData.ResourcePool
# New Service Locator required for Destination vCenter Server when not part of same SSO Domain
$service = New-Object VMware.Vim.ServiceLocator
$credential = New-Object VMware.Vim.ServiceLocatorNamePassword
$credential.username = $destVCusername
$credential.password = $destVCpassword
$service.credential = $credential
$service.instanceUuid = $destVCConn.InstanceUuid
$service.sslThumbprint = $destVCThumbprint
$service.url = "https://$destVC"
$spec.service = $service
# Modify VM Network Adapter to new VM Netework (assumption 1 vNIC, but can easily be modified)
$spec.deviceChange = New-Object VMware.Vim.VirtualDeviceConfigSpec
$spec.deviceChange[0] = New-Object VMware.Vim.VirtualDeviceConfigSpec
$spec.deviceChange[0].Operation = "edit"
$spec.deviceChange[0].Device = $vmNetworkAdapter
$spec.deviceChange[0].Device.backing.deviceName = $vmnetworkname

Write-Host "`nMigrating $vmname from $sourceVC to $destVC ...`n"
# Issue Cross VC-vMotion 
$task = $vm.RelocateVM_Task($spec,"defaultPriority") 
$task1 = Get-Task -Id ("Task-$($task.value)")
$task1 | Wait-Task -Verbose

# Disconnect from Source/Destination VC
Disconnect-VIServer -Server $sourceVCConn -Confirm:$false
Disconnect-VIServer -Server $destVCConn -Confirm:$false