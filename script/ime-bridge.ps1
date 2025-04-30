# Detect Company Portal Folder
# Using registry, as standard users are not allows to dir the WindowsApps Folder
$cpfolder = $(Get-Childitem -Path "Registry::HKEY_CLASSES_ROOT\Extensions\ContractId\Windows.Launch\PackageId").PsChildName | Where-Object { $_ -like "Microsoft.CompanyPortal_*" } | select -First 1

$imeAssembly = "$ENV:ProgramFiles\WindowsApps\$cpfolder\IntuneManagementExtensionBridge\Microsoft.Management.Clients.IntuneManagementExtension.StatusServiceLibrary.dll"

if(-not $(Test-Path $imeAssembly)) {
    write-host "Assembly not found in Path $imeAssembly"
    exit 1
}

# List of required assemblies
$assemblies = @(
    "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\System.ServiceModel.dll",
    "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\System.dll",
    $imeAssembly
)

# Add assemblies
foreach ($assemblyPath in $assemblies) {
    Add-Type -Path $assemblyPath
}

# Create a C# Callbackhandler and complile it (thanks, ChatGPT)
$callbackCode = @"
using System;
using System.ServiceModel;
using Microsoft.Management.Clients.IntuneManagementExtension.StatusServiceLibrary;

public class CallbackHandler : IStatusServiceCallback
{
    public void SyncComplete(SyncResult result)
    {
        if (result != null)
        {
            Console.WriteLine("SyncComplete called: " + result.ToString());
        }
        else
        {
            Console.WriteLine("SyncComplete called: result is null");
        }
    }

    public void AppStatusUpdate(AppInstallStatusReport report)
    {
        if (report != null)
        {
            Console.WriteLine("AppStatusUpdate called: " + report.ToString());
        }
        else
        {
            Console.WriteLine("AppStatusUpdate called: report is null");
        }
    }

    public void DownloadProgressUpdate(DownloadProgressReport report)
    {
        if (report != null)
        {
            Console.WriteLine("DownloadProgressUpdate called: " + report.ToString());
        }
        else
        {
            Console.WriteLine("DownloadProgressUpdate called: report is null");
        }
    }
}
"@
Add-Type -TypeDefinition $callbackCode -ReferencedAssemblies $assemblies -Language CSharp

# Create Instances & Context for the Callback handler
$callbackInstance = New-Object CallbackHandler
$instanceContext = New-Object System.ServiceModel.InstanceContext($callbackInstance)

# Binding and Endpoint
$binding = New-Object System.ServiceModel.NetNamedPipeBinding
$endpoint = "net.pipe://localhost/IntuneManagementExtension/StatusService"
$endpointAddress = New-Object System.ServiceModel.EndpointAddress($endpoint)

# Get the Interface Type from IME Assembly
$asm = [System.Reflection.Assembly]::LoadFrom($assemblies[2])
$interfaceType = $asm.GetType("Microsoft.Management.Clients.IntuneManagementExtension.StatusServiceLibrary.IStatusService")

# And create a Duplex Channel from the System.Servicemodel Assembly
$sasm = [System.Reflection.Assembly]::LoadFrom($assemblies[0])
$genericType = $sasm.GetType("System.ServiceModel.DuplexChannelFactory``1")
$factoryType = $genericType.MakeGenericType($interfaceType)

# Create a factory, instance it and finally create a client
$factory = [Activator]::CreateInstance($factoryType, $instanceContext, $binding, $endpointAddress)
$client = $factory.CreateChannel()

###########################
# Examples:
# Get Status of Apps
# $appStatus = $client.GetAllAppsStatusAsync().Result
# $appStatus | ft

# Perform a Check-In / Sync (Device-Only Context?)
# $checkinGuid = $($client.GetCurrentCheckInIdAsync().Result.Guid)
# $performSync = $client.CheckInAsync($checkinGuid)

