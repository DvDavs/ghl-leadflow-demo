<#
.SYNOPSIS
    Replays a captured GHL outbound-webhook payload against the n8n production
    webhook, for TC-02 (duplicate delivery) and TC-18 (unauthorized).

.DESCRIPTION
    The free GoHighLevel "Outbound Webhook" action supports no custom headers
    and no signature, so the shared secret travels inside the JSON body. That
    has one unavoidable consequence: any payload captured from a real delivery
    is secret-bearing and must never be committed.

    This script therefore takes a REDACTED payload file and injects the secret
    at send time. Neither the webhook URL nor the secret is ever echoed,
    written to disk, or included in error output.

    Inputs are read from environment variables when present, otherwise
    prompted for without echo:

        N8N_WEBHOOK_URL             production webhook URL
        GHL_WEBHOOK_SHARED_SECRET   shared secret

    Set them for the current shell session only. Do not persist them to a
    profile, and do not commit a file that contains them.

.PARAMETER PayloadPath
    Path to the redacted JSON payload captured in TC-01.

.PARAMETER Mode
    Valid       inject the real secret            -> expect 200
    NoSecret    remove the secret key entirely    -> expect 401
    WrongSecret inject a deliberately bad value   -> expect 401

.PARAMETER SecretKey
    Top-level JSON key carrying the shared secret. Matches the Custom Data key
    configured on the GHL webhook action.

.EXAMPLE
    # TC-02 — exact redelivery
    .\scripts\replay-webhook.ps1 -PayloadPath .\payloads\ghl-opportunity-created.example.json

.EXAMPLE
    # TC-18 — unauthorized
    .\scripts\replay-webhook.ps1 -PayloadPath .\payloads\ghl-opportunity-created.example.json -Mode NoSecret
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PayloadPath,

    [ValidateSet('Valid', 'NoSecret', 'WrongSecret')]
    [string] $Mode = 'Valid',

    [string] $SecretKey = 'sharedSecret'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-SecretValue {
    <#
        Reads from the named environment variable if set, otherwise prompts
        without echo. Returns plaintext to the caller, which is responsible
        for clearing it.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $EnvVarName,
        [Parameter(Mandatory = $true)] [string] $Prompt
    )

    $existing = [Environment]::GetEnvironmentVariable($EnvVarName)
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        Write-Host "  using $EnvVarName from the environment" -ForegroundColor DarkGray
        return $existing
    }

    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $secure.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $PayloadPath)) {
    throw "Payload file not found: $PayloadPath"
}

$payload = Get-Content -LiteralPath $PayloadPath -Raw | ConvertFrom-Json

$url = $null
$secret = $null
$body = $null

try {
    $url = Read-SecretValue -EnvVarName 'N8N_WEBHOOK_URL' -Prompt 'n8n production webhook URL'
    if ($url -notmatch '^https://') {
        throw 'Webhook URL must be https. Refusing to send a secret over plaintext.'
    }

    switch ($Mode) {
        'Valid' {
            $secret = Read-SecretValue -EnvVarName 'GHL_WEBHOOK_SHARED_SECRET' -Prompt 'shared secret'
            $payload | Add-Member -NotePropertyName $SecretKey -NotePropertyValue $secret -Force
        }
        'WrongSecret' {
            # Deliberately invalid, and deliberately not derived from the real
            # secret, so a partial match can never occur by accident.
            $payload | Add-Member -NotePropertyName $SecretKey -NotePropertyValue 'not-the-shared-secret' -Force
        }
        'NoSecret' {
            if ($payload.PSObject.Properties.Name -contains $SecretKey) {
                $payload.PSObject.Properties.Remove($SecretKey)
            }
        }
    }

    $body = $payload | ConvertTo-Json -Depth 20 -Compress

    Write-Host ''
    Write-Host "Mode        : $Mode"
    Write-Host "Payload     : $PayloadPath"
    Write-Host "Body bytes  : $([Text.Encoding]::UTF8.GetByteCount($body))"
    Write-Host 'Sending...'

    $status = $null
    $responseBody = $null

    try {
        # -SkipHttpErrorCheck exists only on PowerShell 7+. On 5.1 a non-2xx
        # status raises, and the response is read from the exception instead.
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $response = Invoke-WebRequest -Uri $url -Method Post -Body $body `
                -ContentType 'application/json' -SkipHttpErrorCheck
            $status = [int] $response.StatusCode
            $responseBody = $response.Content
        }
        else {
            $response = Invoke-WebRequest -Uri $url -Method Post -Body $body `
                -ContentType 'application/json' -UseBasicParsing
            $status = [int] $response.StatusCode
            $responseBody = $response.Content
        }
    }
    catch [Net.WebException] {
        # Surface the status and body only. The exception message can contain
        # the request URL, which must never be printed.
        $webResponse = $_.Exception.Response
        if ($null -ne $webResponse) {
            $status = [int] $webResponse.StatusCode
            $reader = New-Object IO.StreamReader($webResponse.GetResponseStream())
            try { $responseBody = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        else {
            throw 'Request failed before a response was received. Check network reachability.'
        }
    }

    Write-Host ''
    Write-Host "HTTP status : $status"
    Write-Host "Response    : $responseBody"
    Write-Host ''

    $expected = @{ 'Valid' = 200; 'NoSecret' = 401; 'WrongSecret' = 401 }[$Mode]
    if ($status -eq $expected) {
        Write-Host "Matches the expected status for mode '$Mode' ($expected)." -ForegroundColor Green
    }
    else {
        Write-Host "UNEXPECTED: mode '$Mode' expects $expected, got $status." -ForegroundColor Yellow
    }

    Write-Host 'Record the n8n execution id, the leads_backup row count, and the'
    Write-Host 'run_log rows as evidence. A status code alone does not prove the'
    Write-Host 'downstream state.'
}
finally {
    # Best-effort scrub. PowerShell strings are immutable and may persist in
    # memory until collected; this removes the references, not the bytes.
    if ($null -ne $secret) { $secret = $null }
    if ($null -ne $url) { $url = $null }
    if ($null -ne $body) { $body = $null }
    [GC]::Collect()
}
