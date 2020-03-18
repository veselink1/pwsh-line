enum PwshElementAlignment {
    Left
    Right
}

class PwshElement {
    static [bool] $_SessionStarting = $true
    static [bool] $DefaultShowArrows = $true
    static [char] $DefaultRtlArrow = [char]0xe0b2
    static [char] $DefaultLtrArrow = [char]0xe0b0

    [String] $Text
    [ConsoleColor] $ForegroundColor = [ConsoleColor]::White
    [ConsoleColor] $BackgroundColor = [ConsoleColor]::Black
    [PwshElementAlignment] $Alignment = [PwshElementAlignment]::Left

    PwshElement([String] $text, [ConsoleColor] $fg, [ConsoleColor] $bg, [PwshElementAlignment] $alignment) {
        $this.Text = $text
        $this.ForegroundColor = $fg
        $this.BackgroundColor = $bg
        $this.Alignment = $alignment
    }
}

function New-PwshElement {
    [CmdletBinding()]
    param (
        [String]
        $Text,
        [ConsoleColor]
        $ForegroundColor = [ConsoleColor]::White,
        [ConsoleColor]
        $BackgroundColor = [ConsoleColor]::Black,
        [PwshElementAlignment]
        $Alignment = [PwshElementAlignment]::Left
    )

    return [PwshElement]::New($Text, $ForegroundColor, $BackgroundColor, $Alignment)
}

function Write-PwshLine {
    [CmdletBinding()]
    param (
        [Array]
        $Elements,
        [Switch]
        $NoNewLine,
        [Switch]
        $NoArrows = ![PwshElement]::DefaultShowArrows,
        [char]
        $RtlArrow = [PwshElement]::DefaultRtlArrow,
        [char]
        $LtrArrow = [PwshElement]::DefaultLtrArrow
    )

    $pshost = Get-Host
    $pswindow = $pshost.UI.RawUI

    # Sets the position of the cursor
    function SetPositionX([int] $x) {
        $position = $pswindow.CursorPosition
        $position.X = $x
        $pswindow.CursorPosition = $position
    }

    if ($pswindow.CursorPosition.X -ne 0) {
        Write-Host "" -ForegroundColor White -BackgroundColor Black
    }
    elseif ([PwshElement]::_SessionStarting) {
        # Fixes an issue where the background for user input is set to the
        # background of the first printed block
        [PwshElement]::_SessionStarting =  $false
        Write-Host " " -ForegroundColor White -BackgroundColor Black -NoNewLine
        SetPositionX(0)
    }

    # Split input elements in two arrays
    $leftElements = @()
    $rightElements = @()
    foreach ($element in $Elements) {
        if ($element.Alignment -eq [PwshElementAlignment]::Left) {
            $leftElements += $element
        }
        else {
            $rightElements += $element
        }
    }

    # Measure distance from left side
    $left = 0
    $prevElement = $null
    foreach ($element in $leftElements) {
        # Pad string
        $text = " " + $element.Text + " "

        # Needs concat by arrow
        if ($prevElement -and !$NoArrows) {
            Write-Host $LtrArrow -NoNewLine -ForegroundColor $prevElement.BackgroundColor -BackgroundColor $element.BackgroundColor
            $left++
        }

        Write-Host $text -NoNewLine -ForegroundColor $element.ForegroundColor -BackgroundColor $element.BackgroundColor
        # Update distance
        $left += $text.Length

        $prevElement = $element
    }

    # Arrow for last element
    if ($element -and !$NoArrows) {
        Write-Host $LtrArrow -NoNewLine -ForegroundColor $prevElement.BackgroundColor -BackgroundColor Black
        $left++
    }

    # Sum length of right line
    $rightLength = 0
    foreach ($element in $rightElements) {
        $rightLength += $element.Text.Length + 3
    }

    # If right side doesn't fit
    if ($rightLength -gt ($pswindow.WindowSize.Width - $pswindow.CursorPosition.X)) {
        # Move to the next line
        Write-Host "" -ForegroundColor White -BackgroundColor Black
        $left = 0
    } else {
        # The right side fits
        if ($left -gt $pswindow.CursorPosition.X) {
            # But the left overflowed
            $prevPositionX = $pswindow.CursorPosition.X
            $overflowFill = $pswindow.WindowSize.Width - $pswindow.CursorPosition.X
            # Printing whitespace fixes an issue where the background between
            # the overflowing line and the right side is colored improperly
            Write-Host (" " * $overflowFill) -ForegroundColor White -BackgroundColor Black -NoNewLine
            SetPositionX($prevPositionX)
        }
    }

    # Measure distance from right side
    $right = $pswindow.WindowSize.Width
    for ($i = 0; $i -lt $rightElements.Length; $i++) {
        $element = $rightElements[$i]
        # Pad the string
        $text = " " + $element.Text + " "

        # Update the distance
        $right -= $text.Length
        if (!$NoArrows) {
            $right--
        }
        SetPositionX($right)

        if (!$NoArrows) {
            # Check if there is a next element
            if ($i -lt $rightElements.Length - 1) {
                $nextElement = $rightElements[$i + 1]
                # Print the concat arrow for it
                Write-Host $RtlArrow -NoNewLine -ForegroundColor $element.BackgroundColor -BackgroundColor $nextElement.BackgroundColor
            }
            else {
                # This arrow is the last one on that side
                Write-Host $RtlArrow -NoNewLine -ForegroundColor $element.BackgroundColor -BackgroundColor Black
            }
        }

        # Print the text itself
        Write-Host $text -NoNewLine -ForegroundColor $element.ForegroundColor -BackgroundColor $element.BackgroundColor
    }

    # Print the final newline
    Write-Host "" -ForegroundColor White -BackgroundColor Black -NoNewLine:$NoNewLine
}

function Get-PwshVcsInfo() {
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

function Write-PwshDefault() {
    $success = $?
    $exitCode = $LastExitCode

    $pwd = (Get-Location).ToString()
    $pwd = $pwd.Replace($env:UserProfile, '~')

    $branch = Get-PwshVcsInfo

    $isAdmin = ([Security.Principal.WindowsPrincipal] `
      [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $infoElements = @(
        (New-PwshElement "$env:UserName@${env:ComputerName}" -ForegroundColor Black -BackgroundColor DarkYellow),
        (New-PwshElement "$pwd" -ForegroundColor Black -BackgroundColor DarkBlue),
        (New-PwshElement (Get-Date -format "hh:mm:ss") -ForegroundColor Black -BackgroundColor White -Alignment Right)
    )

    if ($branch) {
        $infoElements += New-PwshElement " $branch" -ForegroundColor Black -BackgroundColor Green
    }

    $promptElements = @()
    if ($isAdmin) {
        $promptElements += New-PwshElement "Administrator" -ForegroundColor Black -BackgroundColor Red
    }

    if ($success) {
        $promptElements += New-PwshElement "✓" -ForegroundColor Green -BackgroundColor DarkGray
    }
    else {
        $promptElements += New-PwshElement "⮠ EXIT($exitCode)" -ForegroundColor Yellow -BackgroundColor DarkRed
    }

    Write-PwshLine -Elements $infoElements
    Write-PwshLine -NoNewLine -Elements $promptElements

    return " "
}

Export-ModuleMember -Function New-PwshElement
Export-ModuleMember -Function Write-PwshLine
Export-ModuleMember -Function Write-PwshDefault