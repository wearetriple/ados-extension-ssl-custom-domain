param (
    [string] $ResourceGroupName,
    [string] $AppServiceName,
    [string] $AppServiceSlotName,
    [string] $CustomDomains,
    [string] $CertificatePassword,
    [string] $CertificateFileName
)

if ($AppServiceSlotName) {
    $AppServiceDisplayName = "$AppServiceName/$AppServiceSlotName"
}
else {
    $AppServiceDisplayName = $AppServiceName
}

$CertificateFilePath = $env:AGENT_TEMPDIRECTORY + "/" +  $CertificateFileName

$WebAppResource = Get-AzureRmResource -Name $AppServiceName -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites -ApiVersion 2014-11-01

if ([System.IO.File]::Exists($CertificateFilePath)) 
{
    Write-Host ("Certificate found at {0}" -f $CertificateFilePath)
}
else 
{
    Write-Error ("Certificate does not exist at path {0}" -f $CertificateFilePath)
    throw
}

$certificateObject = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$certificateObject.Import($CertificateFilePath, $CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
$CertificateThumbprint = $certificateObject.Thumbprint

Write-Host ("Checking if certificate with thumbprint {0} exists on {1} .." -f $CertificateThumbprint, $AppServiceDisplayName)

$Certificates = Get-AzureRmResource -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/certificates -ApiVersion 2018-09-01

$UploadedCertificateResource = $Certificates | Where-Object { $_.Name -eq $CertificateThumbprint } 
if ($UploadedCertificateResource -eq $null)
{   
    Write-Host ("Certificate with thumbprint {0} does not exist. Uploading .." -f $CertificateThumbprint)

    $pfxContents = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($CertificateFilePath))

    $CertificateProperties = @{"pfxBlob" = $pfxContents; "password" = $CertificatePassword}
    $UploadedCertificateResource = New-AzureRmResource -Name $CertificateThumbprint -Location $WebAppResource.Location -PropertyObject $CertificateProperties -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/certificates -ApiVersion 2015-08-01 -Force
}
else 
{
    Write-Host "Certificate found."
}

foreach ($CustomDomain in $CustomDomains.Split(",")) 
{
    Write-Host ("Checking if hostname {0} exists on {1} .." -f $CustomDomain, $AppServiceDisplayName)

    $HostnameBinding = $WebAppResource.Properties.HostNames | Where-Object { $_ -eq $CustomDomain }
    if ($HostnameBinding -eq $null) 
    {
        $HostnameBindingProperties = @{
            SiteName = $AppServiceName;
            HostNameType = "Verified";
        }
        
        Write-Host ("Hostname {0} does not exist. Creating .." -f $CustomDomain)
         
        if ($AppServiceSlotName) {
            New-AzureRmResource -ResourceName "$AppServiceName/$AppServiceSlotName/$CustomDomain" -Location $WebAppResource.Location -PropertyObject $HostnameBindingProperties -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/hostNameBindings -ApiVersion 2015-08-01 -Force | Out-Null
        
            $WebAppResource = Get-AzureRmResource -Name $AppServiceName -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/slots -ApiVersion 2014-11-01
        }
        else {
            New-AzureRmResource -ResourceName "$AppServiceName/$CustomDomain" -Location $WebAppResource.Location -PropertyObject $HostnameBindingProperties -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/hostNameBindings -ApiVersion 2015-08-01 -Force | Out-Null
        
            $WebAppResource = Get-AzureRmResource -Name $AppServiceName -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites -ApiVersion 2014-11-01
        }
    }
    else 
    {
        Write-Host "Hostname found."
    }
    
    $WebProperties = $WebAppResource.Properties
    [System.Collections.ArrayList]$HostnameSslStates = $WebProperties.HostNameSslStates
    
    Write-Host ("Checking if hostname SSL binding for {0} exists on {1} .." -f $CustomDomain, $AppServiceDisplayName)

    $SslState = $WebProperties.HostNameSslStates | Where-Object { $_.name -eq $CustomDomain }
    if ($SslState -eq $null -or $SslState.Thumbprint -eq $null) 
    {
        $SslState = @{
            name = $CustomDomain
            SslState = 1
            thumbprint = $CertificateThumbprint
            toUpdate = $true
        }

        $HostnameSslStates.Add($SslState)
        $WebProperties.HostNameSslStates = $HostnameSslStates
        
        try
        {
            Write-Host ("Hostname SSL binding for {0} does not exist. Creating binding with thumbprint {1} .." -f $CustomDomain, $CertificateThumbprint)
            
            if ($AppServiceSlotName) {
                Set-AzureRmResource -Name "$AppServiceName/$AppServiceSlotName" -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/slots -PropertyObject $WebProperties -ApiVersion 2014-11-01 -Force | Out-Null
            }
            else {
                Set-AzureRmResource -Name $AppServiceName -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites -PropertyObject $WebProperties -ApiVersion 2014-11-01 -Force | Out-Null
            }
        }
        catch 
        {
            Write-Error ("Cannot set hostname SSL binding for {0}." -f $CustomDomain)
            throw
        }
    }
    elseif ($SslState.Thumbprint -notmatch $CertificateThumbprint) 
    {
        Write-Host ("Hostname SSL binding for {0} does exist, but the thumbprint does not match. Override old SSL binding with thumbprint {1} -> {2} ..." -f $CustomDomain, $SslState.Thumbprint, $CertificateThumbprint)
        
        $SslState.SslState = 1
        $SslState.thumbprint = $CertificateThumbprint
        $SslState.toUpdate = $true

        $WebProperties.HostNameSslStates[$HostnameSslStates.IndexOf($SslState)] = $SslState
    
        if ($AppServiceSlotName) {
            Set-AzureRmResource -Name "$AppServiceName/$AppServiceSlotName" -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites/slots -PropertyObject $WebProperties -ApiVersion 2014-11-01 -Force | Out-Null
        }
        else {
            Set-AzureRmResource -Name $AppServiceName -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Web/sites -PropertyObject $WebProperties -ApiVersion 2014-11-01 -Force | Out-Null
        }
    }
    else 
    {
        Write-Host "Hostname SSL binding found."
    }
}