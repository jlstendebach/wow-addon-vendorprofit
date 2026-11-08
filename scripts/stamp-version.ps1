# Stamps a version into a copy of VendorProfit.toc, in place of the
# @project-version@ placeholder the repository keeps there. For deploy
# scripts, after copying the addon into the AddOns folder:
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\stamp-version.ps1 -Toc "<AddOns>\VendorProfit\VendorProfit.toc"
#
# The version comes from git: the latest release tag (v1.26.0 -> 1.26.0), plus
# how many commits you are past it (1.26.0-3), or "dev" with no tags. Prints
# the version it stamped.
param([Parameter(Mandatory = $true)][string]$Toc)

$version = "dev"
$described = & git -C $PSScriptRoot describe --tags --match "v[0-9]*" 2> $null
if ($LASTEXITCODE -eq 0 -and $described) {
    # v1.26.0 or v1.26.0-3-gabc1234
    if ($described -match '^v(\d+\.\d+\.\d+)(?:-(\d+)-g[0-9a-f]+)?$') {
        $version = $Matches[1]
        if ($Matches[2]) { $version = "$version-$($Matches[2])" }
    }
}

$text = [System.IO.File]::ReadAllText($Toc)
$text = $text -replace '(?m)^## Version:[^\r\n]*', "## Version: $version"
[System.IO.File]::WriteAllText($Toc, $text)
Write-Output $version
