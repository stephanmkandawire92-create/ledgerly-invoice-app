Write-Host "Building Ledgerly Web for Microsoft Edge Extension..." -ForegroundColor Cyan
flutter build web --release --base-href "/"

Write-Host "Copying compiled web assets to edge-extension directory..." -ForegroundColor Cyan
if (!(Test-Path "edge-extension")) {
    New-Item -ItemType Directory -Path "edge-extension"
}

Copy-Item -Path "build/web/*" -Destination "edge-extension" -Recurse -Force

Write-Host "Ensuring manifest.json is present in edge-extension..." -ForegroundColor Cyan
if (Test-Path "edge-extension/manifest.json") {
    Remove-Item "edge-extension/manifest.json" -Force
}
Copy-Item -Path "edge-extension/manifest.json" -Destination "edge-extension/manifest.json" -ErrorAction SilentlyContinue

Write-Host "Microsoft Edge Extension package is fully prepared in /edge-extension folder!" -ForegroundColor Green
Write-Host "To publish to Microsoft Edge Add-ons store:" -ForegroundColor Yellow
Write-Host "1. Compress (zip) the contents of the 'edge-extension' folder." -ForegroundColor White
Write-Host "2. Go to Microsoft Edge Add-ons Developer Dashboard (https://partner.microsoft.com/dashboard/microsoftedge)." -ForegroundColor White
Write-Host "3. Create a new extension and upload the zip file." -ForegroundColor White
