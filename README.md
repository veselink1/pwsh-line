# Pwsh-Line
## A very lightweight and opinionated status line and prompt module for PowerShell
## Installation
- Windows
1. Clone into your PowerShell modules directory (`%USERPROFILE%\Documents\PowerShell\Modules` on Windows)
2. Create a PowerShell profile (if you haven't already done so)
    ```powershell
    if (!Test-Path $Profile) {
        New-Item –Path $Profile –Type File –Force
    }
    notepad $Profile
    ```
3. Add the following to your profile
    ```powershell
    Import-Module pwsh-line
    function prompt {
        Write-DefaultPwshLine
    }
    ```
4. Done! You can create a custom status line using a combination of `New-PwshElement` and `Write-PwshLine`.

![Screenshot](https://raw.githubusercontent.com/veselink1/pwsh-line/master/Screenshots/Preview.png)

## Example Custom Status Line
```powershell
function prompt {
    Write-PwshLine -NoNewLine -Separator (New-PwshSeparator "▓") -Segments @(
        (New-PwshSegment (Get-UserString) -F White -B DarkRed),
        (New-PwshSegment (Get-LocationString) -F Black -B DarkBlue)
        (New-PwshSegment (Get-VcsInfoString) -F Black -B Green)
    )
}
```
