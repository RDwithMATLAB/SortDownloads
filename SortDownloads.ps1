$downloadsPath = Join-Path $env:USERPROFILE "Downloads"
$logDirectory  = Join-Path $env:USERPROFILE "Downloads_Logs"
$currentScript = $MyInvocation.MyCommand.Path
$logRetentionDays = 30

# 1. Ensure log directory exists (using -Path for PowerShell 5.1 compatibility)
if (-not (Test-Path -LiteralPath $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory | Out-Null
} else {
    Get-ChildItem -LiteralPath $logDirectory -Filter "Downloads_Sort_Log_*.csv" -File |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$logRetentionDays) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

$timestamp   = Get-Date -Format "dd-MM-yyyy-HHmm"
$logFilePath = Join-Path -Path $logDirectory -ChildPath "Downloads_Sort_Log_$timestamp.csv"

# 2. Compound Extensions
$compoundExtensions = @(
    ".tar.gz",
    ".ome.tiff",
    ".ome.tif"
)

# 3. Category Definitions
$categories = [ordered]@{
    "1_Research_Papers_&_Docs"    = @(".pdf", ".docx", ".doc", ".txt", ".rtf", ".tex", ".md", ".epub")
    "2_Presentations"             = @(".pptx", ".ppt", ".pptm")
    "3_Data_&_Spreadsheets"       = @(".xlsx", ".xls", ".csv", ".pzfx", ".prism", ".tsv")
    "4_Microscopy_&_Images"       = @(".ome.tif", ".ome.tiff", ".czi", ".dv", ".nd2", ".lif", ".oir", ".ims", ".tif", ".tiff", ".png", ".jpg", ".jpeg", ".bmp", ".gif", ".svg", ".emf", ".webp", ".pdb", ".npy")
    "5_Bioinformatics_&_Genomics" = @(".fasta", ".fa", ".fastq", ".fq", ".bam", ".sam", ".dna", ".praln", ".prot", ".nbib")
    "6_Tracking_&_Kinematics"     = @(".slp", ".h5", ".hdf5", ".roi", ".toml", ".asv")
    "7_Code_&_DataScience"        = @(".py", ".m", ".mat", ".jl", ".ijm", ".r", ".rds", ".rdata", ".sh", ".java", ".groovy", ".ps1", ".mlx", ".xml", ".json", ".yaml")
    "8_Videos"                    = @(".mp4", ".avi", ".mov", ".mkv", ".mpeg")
    "9_Software_&_Installers"     = @(".exe", ".msi", ".jar", ".app")
    "10_Archives"                 = @(".tar.gz", ".zip", ".rar", ".7z", ".gz", ".tar")
}

$ignoreExtensions = @(".crdownload", ".part", ".tmp", ".duckload", ".lnk")

# 4. Build O(1) Inverted Hashtable
$extToCategory = @{}
foreach ($cat in $categories.Keys) {
    foreach ($ext in $categories[$cat]) {
        $extToCategory[$ext.ToLower()] = $cat
    }
}

# 5. Helper Functions
function Get-FileNameComponents {
    param([string]$FileName)
    
    $lowerName = $FileName.ToLower()
    foreach ($cExt in $compoundExtensions) {
        if ($lowerName.EndsWith($cExt)) {
            return @{
                BaseName  = $FileName.Substring(0, $FileName.Length - $cExt.Length)
                Extension = $cExt
            }
        }
    }

    return @{
        BaseName  = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
        Extension = [System.IO.Path]::GetExtension($FileName)
    }
}

function Get-UniqueDestinationPath {
    param(
        [string]$TargetFolder,
        [string]$OriginalFileName
    )
    $proposedPath = Join-Path -Path $TargetFolder -ChildPath $OriginalFileName
    if (-not (Test-Path -LiteralPath $proposedPath)) {
        return $proposedPath
    }

    $components = Get-FileNameComponents -FileName $OriginalFileName
    $counter = 1
    $dateStamp = Get-Date -Format "yyyyMMdd_HHmmss"

    do {
        $newCandidate = "{0}_{1}_{2}{3}" -f $components.BaseName, $dateStamp, $counter, $components.Extension
        $proposedPath = Join-Path -Path $TargetFolder -ChildPath $newCandidate
        $counter++
    } while (Test-Path -LiteralPath $proposedPath)

    return $proposedPath
}

$logEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
function Add-LogRecord {
    param(
        [string]$FileName,
        [string]$Destination = "N/A",
        [string]$Status,
        [string]$Message
    )
    $logEntries.Add([PSCustomObject]@{
        Timestamp   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        FileName    = $FileName
        Destination = $Destination
        Status      = $Status
        Message     = $Message
    })
}

# 6. Metric Tracking Setup
$counts = [ordered]@{}
foreach ($cat in $categories.Keys) { $counts[$cat] = 0 }
$counts["11_Others"] = 0

$totalMoved   = 0
$skippedCount = 0
$failedCount  = 0

# 7. Execution Loop (Only top-level files in Downloads)
$files = Get-ChildItem -LiteralPath $downloadsPath -File

foreach ($file in $files) {
    if ($file.FullName -eq $currentScript) { continue }

    $components = Get-FileNameComponents -FileName $file.Name
    $effectiveExt = $components.Extension.ToLower()

    # Fast-skip browser transient files and shortcuts
    if ($ignoreExtensions -contains $effectiveExt) {
        $skippedCount++
        Add-LogRecord -FileName $file.Name -Status "Skipped (Temp/Shortcut)" -Message "Transient file extension ignored"
        continue
    }

    # O(1) Category Lookup
    if ($extToCategory.ContainsKey($effectiveExt)) {
        $targetCategory = $extToCategory[$effectiveExt]
    } else {
        $targetCategory = "11_Others"
    }

    $destFolder = Join-Path -Path $downloadsPath -ChildPath $targetCategory
    if (-not (Test-Path -LiteralPath $destFolder)) {
        New-Item -ItemType Directory -Path $destFolder | Out-Null
    }

    $finalDestPath = Get-UniqueDestinationPath -TargetFolder $destFolder -OriginalFileName $file.Name

    # Direct atomic move with dedicated exception handling
    try {
        Move-Item -LiteralPath $file.FullName -Destination $finalDestPath -ErrorAction Stop
        
        $counts[$targetCategory]++
        $totalMoved++
        Add-LogRecord -FileName $file.Name -Destination $finalDestPath -Status "Moved" -Message "Success"
    }
    catch [System.IO.PathTooLongException] {
        $skippedCount++
        Add-LogRecord -FileName $file.Name -Destination $finalDestPath -Status "Skipped (Path Too Long)" -Message "Windows 260 character limit reached"
    }
    catch [System.IO.IOException] {
        $skippedCount++
        Add-LogRecord -FileName $file.Name -Destination $finalDestPath -Status "Skipped (File Locked)" -Message $_.Exception.Message
    }
    catch {
        $failedCount++
        Add-LogRecord -FileName $file.Name -Destination $finalDestPath -Status "Failed" -Message $_.Exception.Message
    }
}

# 8. Write Audit Trail
if ($logEntries.Count -gt 0) {
    $logEntries | Export-Csv -LiteralPath $logFilePath -NoTypeInformation -Encoding UTF8
}

# 9. Summary Dashboard
Write-Host "`nDownloads Organizer Summary" -ForegroundColor Cyan
Write-Host ("-" * 45) -ForegroundColor DarkGray

foreach ($entry in $counts.GetEnumerator()) {
    $cleanLabel = $entry.Key -replace '^\d+_', '' -replace '_', ' '
    Write-Host ("{0,-28} : {1,4}" -f $cleanLabel, $entry.Value)
}

Write-Host ("-" * 45) -ForegroundColor DarkGray
Write-Host ("{0,-28} : {1,4}" -f "Total moved", $totalMoved) -ForegroundColor Green
Write-Host ("{0,-28} : {1,4}" -f "Skipped (Locked/Temp/Long)", $skippedCount) -ForegroundColor Yellow
Write-Host ("{0,-28} : {1,4}" -f "Failed", $failedCount) -ForegroundColor Red
Write-Host ("-" * 45) -ForegroundColor DarkGray
Write-Host "Log directory: $logDirectory" -ForegroundColor DarkGray
Write-Host "Audit log    : $(Split-Path -Leaf $logFilePath)`n" -ForegroundColor DarkGray

Write-Host ""
Read-Host -Prompt "Press Enter to exit"