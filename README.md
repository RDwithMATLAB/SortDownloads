# SortDownloads

A PowerShell script that automatically organizes your Windows Downloads folder into category subfolders based on file extension — built around a scientific/research workflow (papers, microscopy files, bioinformatics formats, code) but easily customizable for any use case.

## ⚠️ Warnings — read before running

- **This script moves files.** It does not copy. Files in your Downloads folder will be relocated into subfolders.
- **Test on a non-critical folder first**, or back up your Downloads folder before the first run.
- **No dry-run mode exists yet.** There is no way to preview what would move without actually moving it. Review the `$categories` mapping below before running if you're unsure.
- **Not safe for unattended/scheduled runs as-is.** The script ends with `Read-Host -Prompt "Press Enter to exit"`, which will cause it to hang indefinitely if run via Task Scheduler with no one present to press Enter. Remove that line (or gate it behind an interactivity check) if you plan to automate this.
- **Only sorts top-level files.** Subfolders inside Downloads are left untouched.
- Runs on Windows PowerShell 5.1+ / PowerShell 7+.

## What it does

- Scans the top level of your Downloads folder
- Matches each file's extension against a category map (documents, presentations, spreadsheets, images/microscopy, bioinformatics formats, code, videos, installers, archives)
- Moves matched files into `Downloads\<Category>\`
- Unmatched extensions go into `Downloads\11_Others\`
- Skips in-progress downloads (`.crdownload`, `.part`, `.tmp`, etc.) and shortcuts (`.lnk`)
- Renames on collision instead of overwriting (appends a timestamp)
- Handles compound extensions correctly (`.tar.gz`, `.ome.tif`, `.ome.tiff`)
- Logs every action (moved / skipped / failed) to a timestamped CSV in `Downloads_Logs\`, auto-pruned after 30 days
- Prints a summary table to the console when done

## Usage

1. Download `SortDownloads.ps1` to any folder on your machine (it no longer needs to sit inside Downloads).
2. Open PowerShell and allow script execution for your user, if you haven't already:
```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
3. Run it:
```powershell
   .\SortDownloads.ps1
```

The script automatically detects your Downloads folder via `$env:USERPROFILE` — no editing required.

## Customizing categories

Edit the `$categories` hashtable near the top of the script. Each key is a folder name, each value is a list of extensions:

```powershell
"1_Research_Papers_&_Docs" = @(".pdf", ".docx", ".doc", ".txt", ".rtf", ".tex", ".md", ".epub")
```

Add, remove, or rename categories freely. If an extension isn't listed anywhere, files with that extension land in `11_Others`.

## Automating with Task Scheduler

If you want this to run on a schedule, first remove the `Read-Host` line at the end of the script (see warning above), then:

```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"C:\path\to\SortDownloads.ps1`""
$trigger = New-ScheduledTaskTrigger -Daily -At 9am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "SortDownloads"
```

## License

MIT (or your preference — add a LICENSE file before making the repo public if you want this enforced)

## Disclaimer

Provided as-is with no warranty. You are responsible for reviewing the category mappings and testing on your own machine before relying on this for important files.