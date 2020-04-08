enum PwshAlignment {
    Left
    Right
}

class PwshSeparator {
    [string] $Left
    [string] $Right

    PwshSeparator([string] $left, [string] $right) {
        $this.Left = $left
        $this.Right = $right
    }
}

function New-PwshSeparator {
    [CmdletBinding()]
    param (
        [String] $Left,
        [String] $Right = $Left
    )

    return [PwshSeparator]::New($Left, $Right)
}

$ArrowSeparator = New-PwshSeparator -Left ([char]0xe0b0) -Right ([char]0xe0b2)

class Segment {
    static [bool] $_SessionStarting = $true
    static [bool] $DefaultShowArrows = $true

    [String] $Text
    [ConsoleColor] $ForegroundColor = [ConsoleColor]::White
    [ConsoleColor] $BackgroundColor = [ConsoleColor]::Black
    [PwshAlignment] $Alignment = [PwshAlignment]::Left

    Segment([String] $text, [ConsoleColor] $fg, [ConsoleColor] $bg, [PwshAlignment] $alignment) {
        $this.Text = $text
        $this.ForegroundColor = $fg
        $this.BackgroundColor = $bg
        $this.Alignment = $alignment
    }
}

function New-PwshSegment {
    [CmdletBinding()]
    param (
        [String] $Text,
        [System.Nullable``1[[ConsoleColor]]] $ForegroundColor = $null,
        [System.Nullable``1[[ConsoleColor]]] $BackgroundColor = $null,
        [PwshAlignment] $Alignment = [PwshAlignment]::Left
    )

    $pshost = Get-Host
    $pswindow = $pshost.UI.RawUI
    if ($ForegroundColor -eq $null) {
        $ForegroundColor = $pswindow.ForegroundColor
    }
    if ($BackgroundColor -eq $null) {
        $BackgroundColor = $pswindow.BackgroundColor
    }

    return [Segment]::New($Text, $ForegroundColor, $BackgroundColor, $Alignment)
}

function Compute-Length {
    param(
        [Array] $Segments,
        [String] $Separator,
        [bool] $NoPadding
    )

    # Sum length of right line
    $length = 0
    foreach ($seg in $Segments) {
        $length += $seg.Text.Length
    }
    if (!$NoPadding) {
        $length += $Segments.Length * 2
    }

    if ($Separator) {
        $length += ($Segments.Length - 1) * $Separator.Length
    }

    return $length
}

function Write-PwshLineLeft {
    [CmdletBinding()]
    param (
        [Array] $Segments,
        [bool] $NoNewLine,
        [bool] $NoPadding,
        [String] $Separator
    )
    # Measure distance from left side
    $left = $pswindow.CursorPosition.X
    $prevSeg = $null
    foreach ($seg in $leftSegs) {
        $text = $seg.Text
        if (!$NoPadding) {
            # Pad the string
            $text = " " + $text + " "
        }

        # Needs concat by arrow
        if ($prevSeg) {
            if ($Separator) {
                Write-Host $Separator -NoNewLine -ForegroundColor $prevSeg.BackgroundColor -BackgroundColor $seg.BackgroundColor
                $left += $Separator.Length
            }
        }

        Write-Host $text -NoNewLine -ForegroundColor $seg.ForegroundColor -BackgroundColor $seg.BackgroundColor
        # Update distance
        $left += $text.Length

        $prevSeg = $seg
    }

    # Arrow for last element
    if ($seg -and $Separator) {
        Write-Host $Separator -NoNewLine -ForegroundColor $prevSeg.BackgroundColor -BackgroundColor $pswindow.BackgroundColor
    }
}

function Write-PwshLineRight {
    [CmdletBinding()]
    param (
        [Array] $Segments,
        [bool] $NoNewLine,
        [bool] $NoPadding,
        [String] $Separator
    )

    $rightLength = Compute-Length -Segments:$Segments -Separator:$Separator -NoPadding:$NoPadding

    # If right side doesn't fit
    if ($rightLength -gt ($pswindow.WindowSize.Width - $pswindow.CursorPosition.X)) {
        # Move to the next line
        Write-Host "" -ForegroundColor $pswindow.ForegroundColor -BackgroundColor $pswindow.BackgroundColor
    } else {
        $prevPositionX = $pswindow.CursorPosition.X
        $overflowFill = $pswindow.WindowSize.Width - $pswindow.CursorPosition.X
        # Printing whitespace fixes an issue where the background between
        # the overflowing line and the right side is colored improperly
        Write-Host (" " * $overflowFill) -ForegroundColor $pswindow.ForegroundColor -BackgroundColor $pswindow.BackgroundColor -NoNewLine
        SetPositionX($prevPositionX)
    }

    # Measure distance from left side
    $right = $pswindow.WindowSize.Width - 1
    for ($i = 0; $i -lt $rightSegs.Length; $i++) {
        $seg = $rightSegs[$i]

        $text = $seg.Text
        if (!$NoPadding) {
            # Pad the string
            $text = " " + $text + " "
        }

        # Update the distance
        $right -= $text.Length
        SetPositionX($right)

        if ($Separator) {
            # Check if there is a next element
            if ($i -lt $rightSegs.Length - 1) {
                $nextSeg = $rightSegs[$i + 1]
                # Print the concat arrow for it
                Write-Host $Separator -NoNewLine -ForegroundColor $seg.BackgroundColor -BackgroundColor $nextSeg.BackgroundColor
                $right -= $Separator.Length
            }
            else {
                # This arrow is the last one on that side
                Write-Host $Separator -NoNewLine -ForegroundColor $seg.BackgroundColor -BackgroundColor $pswindow.BackgroundColor
                $right -= $Separator.Length
            }
        }

        # Print the text itself
        Write-Host $text -NoNewLine -ForegroundColor $seg.ForegroundColor -BackgroundColor $seg.BackgroundColor
    }
}

function Write-PwshLine {
    [CmdletBinding()]
    param (
        [Array] $Segments,
        [Switch] $NoNewLine,
        [Switch] $NoPadding,
        [PwshSeparator] $Separator = $ArrowSeparator
    )

    $pshost = Get-Host
    $pswindow = $pshost.UI.RawUI

    # Sets the position of the cursor
    function SetPositionX([int] $x) {
        $position = $pswindow.CursorPosition
        $position.X = $x
        $pswindow.CursorPosition = $position
    }

    if ([Segment]::_SessionStarting) {
        # Fixes an issue where the background for user input is set to the
        # background of the first printed block
        [Segment]::_SessionStarting =  $false
        Write-Host " " -ForegroundColor $pswindow.ForegroundColor -BackgroundColor $pswindow.BackgroundColor -NoNewLine
        SetPositionX(0)
    }

    # Split input segments in two arrays
    $leftSegs = @()
    $rightSegs = @()
    foreach ($seg in $Segments) {
        if (($seg.Alignment -eq [PwshAlignment]::Left) -and $seg.Text) {
            $leftSegs += $seg
        }
        elseif ($seg.Text) {
            $rightSegs += $seg
        }
    }

    Write-PwshLineLeft -Segments $leftSegs -NoNewLine:$NoNewLine `
        -NoPadding:$NoPadding -Separator:$Separator.Left

    Write-PwshLineRight -Segments $rightSegs -NoNewLine:$NoNewLine `
        -NoPadding:$NoPadding -Separator:$Separator.Right

    # Print the final newline
    Write-Host "" -ForegroundColor $pswindow.ForegroundColor -BackgroundColor $pswindow.BackgroundColor -NoNewLine:$NoNewLine
}

function Get-UserString {
    [CmdletBinding()]
    param(
        [Switch] $IncludeHostname = $false
    )
    if ($IncludeHostname) {
        return "$env:UserName@$env:ComputerName"
    }
    return $env:UserName
}

function Get-ElevationString {
    [CmdletBinding()]
    param()

    $isElevated = ([Security.Principal.WindowsPrincipal] `
      [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isElevated) {
        return "ELEVATED"
    }
    return $null
}

function Get-LocationString {
    [CmdletBinding()]
    param(
        [string] $CustomSeparator = $null
    )

    $pwd = (Get-Location).ToString()
    $pwd = $pwd.Replace($env:UserProfile, '~')

    if ($CustomSeparator) {
        $pwd = $pwd.Replace([System.IO.Path]::DirectorySeparatorChar.ToString(), $CustomSeparator)
    }
    return $pwd
}

function Get-VcsInfoString() {
    [CmdletBinding()]
    param()

    if (Get-Command "Write-VcsStatus") {
        $output = Write-VcsStatus 6>&1 | Foreach { $_.MessageData.Message }
        $output = ($output -join "").Trim(' ', '[', ']')

        if ($output.Length -gt 0) {
            return $output
        }
        return $null
    }

    try {
        $branch = git rev-parse --abbrev-ref HEAD

        if (!$branch) {
            return $null
        }

        if ($branch -eq "HEAD") {
            # we're probably in detached HEAD state, so print the SHA
            $branch = git rev-parse --short HEAD
            return "$branch"
        }
        else {
            # we're on an actual branch, so print it
            return "$branch"
        }
    } catch {
        # we'll end up here if we're in a newly initiated git repo
        return $null
    }
}

function New-ExitCodeSegment {
    [CmdletBinding()]
    param(
        [bool] $Success,
        [int] $ExitCode,
        [PwshAlignment] $Alignment = [PwshAlignment]::Left
    )

    if ($Success) {
        return New-PwshSegment "✓" -ForegroundColor Green -BackgroundColor DarkGray -Alignment:$Alignment
    }
    else {
        return New-PwshSegment "⮠ EXIT($ExitCode)" -ForegroundColor Yellow -BackgroundColor DarkRed -Alignment:$Alignment
    }
}

function Write-DefaultPwshLine {
    $success = $?
    $exitCode = $LastExitCode

    $vcsInfo = Get-VcsInfoString

    $infoSegs = @(
        (New-PwshSegment (Get-ElevationString) -ForegroundColor Black -BackgroundColor Red)
        (New-PwshSegment (Get-UserString) -ForegroundColor DarkYellow -BackgroundColor DarkGray)
        (New-PwshSegment (Get-LocationString) -ForegroundColor Black -BackgroundColor DarkBlue)
        (New-PwshSegment (Get-Date -format "hh:mm:ss") -ForegroundColor Black -BackgroundColor White -Alignment Right)
    )

    $promptSegs = @()
    if ($vcsInfo) {
        $vcsInfoSeg = New-PwshSegment " $vcsInfo" -ForegroundColor Black -BackgroundColor Green
        if ($vcsInfo -like "*!*") {
            $vcsInfoSeg.BackgroundColor = [ConsoleColor]::DarkYellow
        }
        $promptSegs += $vcsInfoSeg
    }

    $promptSegs += New-ExitCodeSegment -Success $success -ExitCode $exitCode

    Write-PwshLine $infoSegs
    Write-PwshLine $promptSegs -NoNewLine

    return " "
}

Export-ModuleMember -Function New-PwshSeparator
Export-ModuleMember -Function New-PwshSegment
Export-ModuleMember -Function New-ExitCodeSegment

Export-ModuleMember -Function Get-UserString
Export-ModuleMember -Function Get-ElevationString
Export-ModuleMember -Function Get-LocationString
Export-ModuleMember -Function Get-VcsInfoString

Export-ModuleMember -Function Write-PwshLine
Export-ModuleMember -Function Write-DefaultPwshLine