<#
.SYNOPSIS
  Verifies and (optionally) applies the Ledgerly PayPal subscription settings.

.DESCRIPTION
  This script is deliberately read-only unless -Apply is supplied. It:

    1. Refuses to use an application origin that redirects to Vercel team
       authentication, or that hosts only the email-confirmation page.
    2. Requires explicit return and cancellation URLs on the same origin.
    3. Authenticates to PayPal and proves the configured plan is ACTIVE,
       USD 3.00, billed monthly - in the environment you asked for.
    4. Optionally proves the webhook id belongs to the same PayPal app.
    5. Lists the Supabase secret NAMES that exist, and reports which required
       names are missing. Secret values are never read or printed.
    6. Only with -Apply does it write secrets, and only after confirmation.

  Nothing is deployed by this script. Deploying Edge Functions is a separate,
  authorised step.

.PARAMETER Environment
  'sandbox' for end-to-end purchase testing, 'live' for production.

.PARAMETER AppOrigin
  Exact public HTTPS origin of the Flutter web app, for example
  https://app.ledgerly.example. No path, no trailing slash.

.PARAMETER ReturnPath
  Path on the app origin that PayPal returns to after approval.

.PARAMETER CancelPath
  Path on the app origin that PayPal returns to after cancellation.

.PARAMETER PlanId
  PayPal billing plan id for Ledgerly Pro (USD 3.00 / month).

.PARAMETER WebhookId
  Webhook id registered in the same PayPal REST app.

.PARAMETER SupabaseProjectRef
  Supabase project ref (defaults to the Ledgerly project).

.EXAMPLE
  # Verify only - no writes
  .\supabase\configure-paypal-live.ps1 `
      -Environment sandbox `
      -AppOrigin https://ledgerly-app.example.com `
      -PlanId P-XXXXXXXXXXXX `
      -WebhookId WH-XXXXXXXXXXXX

.EXAMPLE
  # Verify, then write the secrets after confirmation
  .\supabase\configure-paypal-live.ps1 `
      -Environment live `
      -AppOrigin https://app.ledgerly.com `
      -PlanId P-XXXXXXXXXXXX `
      -WebhookId WH-XXXXXXXXXXXX `
      -Apply
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('sandbox', 'live')]
  [string]$Environment,

  [Parameter(Mandatory = $true)]
  [string]$AppOrigin,

  [string]$ReturnPath = '/billing/paypal/return',
  [string]$CancelPath = '/billing/paypal/cancel',

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^P-[A-Z0-9]+$')]
  [string]$PlanId,

  # PayPal webhook IDs are opaque provider identifiers; not all accounts use
  # the older WH- prefix, so validate presence rather than inventing a format.
  [ValidateNotNullOrEmpty()]
  [string]$WebhookId,

  [string]$SupabaseProjectRef = 'gcrzwkzithihyhyftfgn',

  [string]$ClientId = $env:PAYPAL_CLIENT_ID,
  [SecureString]$ClientSecret,

  [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Settings that will always be required by the deployed functions.
$RequiredSettings = @(
  'PAYPAL_ENV',
  'PAYPAL_CLIENT_ID',
  'PAYPAL_CLIENT_SECRET',
  'PAYPAL_MONTHLY_PLAN_ID',
  'PAYPAL_WEBHOOK_ID',
  'APP_ALLOWED_ORIGIN',
  'PAYPAL_RETURN_URL',
  'PAYPAL_CANCEL_URL'
)

# Hostnames that must never be used as the application origin: they host the
# static email-confirmation page, not the Flutter application.
$ConfirmationHosts = @('ledgerly-invoice-app.vercel.app')

$PayPalBase = if ($Environment -eq 'live') {
  'https://api-m.paypal.com'
} else {
  'https://api-m.sandbox.paypal.com'
}

$Problems = New-Object System.Collections.Generic.List[string]
$Report = New-Object System.Collections.Generic.List[object]

function Add-Result {
  param([string]$Check, [string]$Status, [string]$Detail)
  $Report.Add([pscustomobject]@{ Check = $Check; Status = $Status; Detail = $Detail })
  $colour = switch ($Status) {
    'PASS' { 'Green' }
    'WARN' { 'Yellow' }
    'FAIL' { 'Red' }
    default { 'Gray' }
  }
  Write-Host ("  [{0}] {1} - {2}" -f $Status, $Check, $Detail) -ForegroundColor $colour
  if ($Status -eq 'FAIL') { $Problems.Add("$Check`: $Detail") | Out-Null }
}

function Get-PlainText {
  param([SecureString]$Secure)
  if ($null -eq $Secure) { return $null }
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

function Invoke-Json {
  param(
    [string]$Uri,
    [string]$Method = 'GET',
    [hashtable]$Headers = @{},
    [string]$Body
  )
  $params = @{
    Uri             = $Uri
    Method          = $Method
    Headers         = $Headers
    UseBasicParsing = $true
  }
  if ($Body) {
    $params['Body'] = $Body
    $params['ContentType'] = 'application/json'
  }
  $response = Invoke-WebRequest @params
  return ($response.Content | ConvertFrom-Json)
}

# Reads the status code and Location header from a failed web request. Windows
# PowerShell (HttpWebResponse) and PowerShell 7 (HttpResponseMessage) expose
# headers differently, so both shapes are handled.
function Get-ErrorResponseInfo {
  param([Parameter(Mandatory = $true)]$ErrorRecord)
  $status = $null
  $location = $null
  $response = $ErrorRecord.Exception.Response
  if ($null -ne $response) {
    try { $status = [int]$response.StatusCode } catch { }
    try {
      $candidate = $response.Headers.Location
      if ($candidate) { $location = [string]$candidate }
    } catch { }
    if (-not $location) {
      try { $location = [string]$response.Headers['Location'] } catch { }
    }
  }
  return [pscustomobject]@{ StatusCode = $status; Location = $location }
}

Write-Host ''
Write-Host "Ledgerly PayPal configuration check ($Environment)" -ForegroundColor Cyan
Write-Host '=================================================='
Write-Host ''

# ---------------------------------------------------------------- 1. Origin
$originUri = $null
try { $originUri = [Uri]$AppOrigin } catch { }

if ($null -eq $originUri -or $originUri.Scheme -ne 'https') {
  Add-Result 'Application origin' 'FAIL' 'must be an absolute HTTPS URL'
} elseif ($originUri.AbsolutePath -ne '/' -or $AppOrigin.EndsWith('/')) {
  Add-Result 'Application origin' 'FAIL' 'must be a bare origin with no path or trailing slash'
} else {
  Add-Result 'Application origin' 'PASS' $AppOrigin
}

if ($null -ne $originUri) {
  if ($ConfirmationHosts -contains $originUri.Host.ToLowerInvariant()) {
    Add-Result 'Confirmation site reuse' 'FAIL' `
      'this host serves the email-confirmation page; use the application origin instead'
  } else {
    Add-Result 'Confirmation site reuse' 'PASS' 'not the confirmation-only host'
  }
}

# ------------------------------------------------- 2. Public reachability
if ($null -ne $originUri -and $originUri.Scheme -eq 'https') {
  try {
    $probe = Invoke-WebRequest -Uri $AppOrigin -Method Get -MaximumRedirection 0 -UseBasicParsing -TimeoutSec 20
    if ($probe.StatusCode -ge 200 -and $probe.StatusCode -lt 400) {
      if ($probe.Content -match 'Vercel Authentication|sso-api') {
        Add-Result 'Public reachability' 'FAIL' 'the deployment is behind Vercel Authentication'
      } else {
        Add-Result 'Public reachability' 'PASS' "HTTP $($probe.StatusCode)"
      }
    } else {
      Add-Result 'Public reachability' 'FAIL' "unexpected HTTP $($probe.StatusCode)"
    }
  } catch {
    $info = Get-ErrorResponseInfo -ErrorRecord $_
    $statusCode = $info.StatusCode
    $location = $info.Location
    if ($statusCode -in 301, 302, 303, 307, 308 -and $location -match 'vercel\.com/sso-api') {
      Add-Result 'Public reachability' 'FAIL' `
        'redirects to Vercel team authentication; this deployment cannot be used for checkout'
    } elseif ($statusCode -eq 401 -or $statusCode -eq 403) {
      Add-Result 'Public reachability' 'FAIL' "HTTP $statusCode - customers cannot load the app"
    } else {
      Add-Result 'Public reachability' 'WARN' "could not be verified from this machine ($($_.Exception.Message))"
    }
  }
}

# ------------------------------------------------------- 3. Checkout URLs
$returnUrl = $null
$cancelUrl = $null
if ($null -ne $originUri -and $originUri.Scheme -eq 'https') {
  $returnUrl = ('{0}{1}' -f $AppOrigin.TrimEnd('/'), $ReturnPath)
  $cancelUrl = ('{0}{1}' -f $AppOrigin.TrimEnd('/'), $CancelPath)
  Add-Result 'Return URL' 'PASS' $returnUrl
  Add-Result 'Cancel URL' 'PASS' $cancelUrl
  if ($ReturnPath -match '^/auth-callback') {
    Add-Result 'Return URL purpose' 'FAIL' 'the confirmation callback page cannot host the app'
  }
} else {
  Add-Result 'Return URL' 'FAIL' 'cannot be derived without a valid origin'
  Add-Result 'Cancel URL' 'FAIL' 'cannot be derived without a valid origin'
}

# --------------------------------------------------------- 4. Credentials
if ([string]::IsNullOrWhiteSpace($ClientId)) {
  Add-Result 'PayPal client id' 'FAIL' 'set $env:PAYPAL_CLIENT_ID or pass -ClientId'
}
$secretPlain = Get-PlainText -Secure $ClientSecret
if ([string]::IsNullOrWhiteSpace($secretPlain)) {
  $secretPlain = $env:PAYPAL_CLIENT_SECRET
  if ([string]::IsNullOrWhiteSpace($secretPlain)) {
    Add-Result 'PayPal client secret' 'FAIL' 'set $env:PAYPAL_CLIENT_SECRET or pass -ClientSecret'
  }
}

# ------------------------------------------------------------ 5. PayPal API
$token = $null
if (-not [string]::IsNullOrWhiteSpace($ClientId) -and -not [string]::IsNullOrWhiteSpace($secretPlain)) {
  try {
    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(('{0}:{1}' -f $ClientId, $secretPlain)))
    $tokenResponse = Invoke-WebRequest -Uri "$PayPalBase/v1/oauth2/token" -Method Post `
      -Headers @{ Authorization = "Basic $basic" } `
      -ContentType 'application/x-www-form-urlencoded' `
      -Body 'grant_type=client_credentials' -UseBasicParsing
    $token = ($tokenResponse.Content | ConvertFrom-Json).access_token
    Add-Result 'PayPal authentication' 'PASS' "$Environment credentials accepted"
  } catch {
    Add-Result 'PayPal authentication' 'FAIL' `
      "credentials rejected for $Environment; check that client id/secret belong to the $Environment app"
  }
}

if ($null -ne $token) {
  $authHeaders = @{ Authorization = "Bearer $token" }
  try {
    $plan = Invoke-Json -Uri "$PayPalBase/v1/billing/plans/$PlanId" -Headers $authHeaders
    $regular = $plan.billing_cycles | Where-Object { $_.tenure_type -eq 'REGULAR' } | Select-Object -First 1
    $price = $regular.pricing_scheme.fixed_price
    $priceOk = ($price.currency_code -eq 'USD') -and ([decimal]$price.value -eq [decimal]3)
    $cycleOk = ($regular.frequency.interval_unit -eq 'MONTH') -and ([int]$regular.frequency.interval_count -eq 1)
    if ($plan.status -ne 'ACTIVE') {
      Add-Result 'Plan status' 'FAIL' "plan is $($plan.status); it must be ACTIVE"
    } else {
      Add-Result 'Plan status' 'PASS' 'ACTIVE'
    }
    if ($priceOk) {
      Add-Result 'Plan price' 'PASS' ('{0} {1}' -f $price.currency_code, $price.value)
    } else {
      Add-Result 'Plan price' 'FAIL' ('expected USD 3.00, found {0} {1}' -f $price.currency_code, $price.value)
    }
    if ($cycleOk) {
      Add-Result 'Plan interval' 'PASS' 'every 1 MONTH'
    } else {
      Add-Result 'Plan interval' 'FAIL' 'expected a monthly billing cycle'
    }
  } catch {
    Add-Result 'Plan lookup' 'FAIL' "plan $PlanId not found in the $Environment app"
  }

  if (-not [string]::IsNullOrWhiteSpace($WebhookId)) {
    try {
      $webhook = Invoke-Json -Uri "$PayPalBase/v1/notifications/webhooks/$WebhookId" -Headers $authHeaders
      Add-Result 'Webhook registration' 'PASS' $webhook.url
      $eventNames = @($webhook.event_types | ForEach-Object { $_.name })
      $requiredEvents = @(
        'BILLING.SUBSCRIPTION.ACTIVATED',
        'BILLING.SUBSCRIPTION.UPDATED',
        'BILLING.SUBSCRIPTION.CANCELLED',
        'BILLING.SUBSCRIPTION.EXPIRED',
        'BILLING.SUBSCRIPTION.SUSPENDED',
        'BILLING.SUBSCRIPTION.RE-ACTIVATED',
        'BILLING.SUBSCRIPTION.PAYMENT.FAILED',
        'PAYMENT.SALE.COMPLETED',
        'PAYMENT.SALE.REFUNDED',
        'PAYMENT.SALE.REVERSED'
      )
      $missingEvents = $requiredEvents | Where-Object { $eventNames -notcontains $_ }
      if ($missingEvents.Count -eq 0) {
        Add-Result 'Webhook events' 'PASS' 'all subscription and payment events subscribed'
      } else {
        Add-Result 'Webhook events' 'WARN' ("not subscribed: {0}" -f ($missingEvents -join ', '))
      }
    } catch {
      Add-Result 'Webhook registration' 'FAIL' `
        "webhook $WebhookId not found in the $Environment app; it must belong to the same REST app"
    }
  } else {
    Add-Result 'Webhook registration' 'WARN' 'no -WebhookId supplied, registration not verified'
  }
}

# ------------------------------------------------------- 6. Supabase secrets
$existingNames = @()
if (Get-Command supabase -ErrorAction SilentlyContinue) {
  try {
    $listOutput = & supabase secrets list --project-ref $SupabaseProjectRef 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($listOutput | Out-String) }
    $existingNames = @(
      $listOutput |
        Select-Object -Skip 2 |
        ForEach-Object {
          $line = $_.Trim()
          if ($line) { ($line -split '\s+')[0] }
        } |
        Where-Object { $_ -and $_ -notmatch '^-+$' }
    )
    Add-Result 'Supabase secrets' 'PASS' ("{0} secret names found (values never read)" -f $existingNames.Count)
  } catch {
    Add-Result 'Supabase secrets' 'WARN' 'could not list secrets; run: supabase login'
  }
} else {
  Add-Result 'Supabase secrets' 'WARN' 'Supabase CLI not installed; names not verified'
}

if ($existingNames.Count -gt 0) {
  $missing = $RequiredSettings | Where-Object { $existingNames -notcontains $_ }
  if ($missing.Count -eq 0) {
    Add-Result 'Required secret names' 'PASS' 'all required names are present'
  } else {
    Add-Result 'Required secret names' 'FAIL' ("missing: {0}" -f ($missing -join ', '))
  }
}

# ------------------------------------------------------------- 7. Apply
Write-Host ''
if ($Problems.Count -gt 0) {
  Write-Host 'Configuration is NOT ready:' -ForegroundColor Red
  $Problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  Write-Host ''
  Write-Host 'No secrets were written. Fix the items above and run the script again.' -ForegroundColor Yellow
  exit 1
}

$settings = [ordered]@{
  PAYPAL_ENV             = $Environment
  PAYPAL_CLIENT_ID       = $ClientId
  PAYPAL_CLIENT_SECRET   = $secretPlain
  PAYPAL_MONTHLY_PLAN_ID = $PlanId
  PAYPAL_WEBHOOK_ID      = $WebhookId
  APP_ALLOWED_ORIGIN     = $AppOrigin
  PAYPAL_RETURN_URL      = $returnUrl
  PAYPAL_CANCEL_URL      = $cancelUrl
}

Write-Host 'All checks passed.' -ForegroundColor Green
Write-Host 'Settings that would be written (values masked):'
$settings.Keys | ForEach-Object {
  $value = $settings[$_]
  $shown = if ($_ -match 'SECRET|CLIENT_ID|WEBHOOK_ID|PLAN_ID') { '********' } else { $value }
  Write-Host ("  {0} = {1}" -f $_, $shown)
}
Write-Host ''

if (-not $Apply) {
  Write-Host 'Dry run: no changes made. Re-run with -Apply to write these secrets.' -ForegroundColor Yellow
  exit 0
}

if ($PSCmdlet.ShouldProcess("Supabase project $SupabaseProjectRef", "Write $($settings.Count) PayPal secrets")) {
  $confirmation = Read-Host ("Type {0} to write these secrets to {1}" -f $Environment.ToUpperInvariant(), $SupabaseProjectRef)
  if ($confirmation -ne $Environment.ToUpperInvariant()) {
    Write-Host 'Confirmation not given. No changes made.' -ForegroundColor Yellow
    exit 1
  }
  & supabase secrets set --project-ref $SupabaseProjectRef `
    "PAYPAL_ENV=$($settings.PAYPAL_ENV)" `
    "PAYPAL_CLIENT_ID=$($settings.PAYPAL_CLIENT_ID)" `
    "PAYPAL_CLIENT_SECRET=$($settings.PAYPAL_CLIENT_SECRET)" `
    "PAYPAL_MONTHLY_PLAN_ID=$($settings.PAYPAL_MONTHLY_PLAN_ID)" `
    "PAYPAL_WEBHOOK_ID=$($settings.PAYPAL_WEBHOOK_ID)" `
    "APP_ALLOWED_ORIGIN=$($settings.APP_ALLOWED_ORIGIN)" `
    "PAYPAL_RETURN_URL=$($settings.PAYPAL_RETURN_URL)" `
    "PAYPAL_CANCEL_URL=$($settings.PAYPAL_CANCEL_URL)"
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'Writing secrets failed. Nothing was deployed.' -ForegroundColor Red
    exit 1
  }
  Write-Host 'Secrets written. Deploy the Edge Functions as a separate, authorised step:' -ForegroundColor Green
  Write-Host ("  supabase functions deploy paypal-create-subscription paypal-webhook paypal-sync-subscription --project-ref {0}" -f $SupabaseProjectRef)
}

$secretPlain = $null
