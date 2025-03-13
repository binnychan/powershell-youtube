# Save as "UTF-8 with BOM" as Chinese Char
# Define the URL and file path
$url = "https://www.youtube.com/xxxxx/stream"
$oldFilePath = "C:\temp\youtube-record.html"

$botToken = '9999999999:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
$chat = '-9999999999'

# Define the DOS command you want to run
$dosCommand = "X:\YT-Video\yt-dlp.exe"
$dosCommandArguments = "-U --merge-output-format mp4 --live-from-start --embed-thumbnail --add-metadata --cookies-from-browser firefox https://www.youtube.com/watch?v="

function Send-TelegramTextMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true,
            HelpMessage = '#########:xxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxx')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]$BotToken, #you could set a token right here if you wanted

        [Parameter(Mandatory = $true,
            HelpMessage = '-#########')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]$ChatID, #you could set a Chat ID right here if you wanted

        [Parameter(Mandatory = $true,
            HelpMessage = 'Text of the message to be sent')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false,
            HelpMessage = 'HTML vs Markdown for message formatting')]
        [ValidateSet('Markdown', 'MarkdownV2', 'HTML')]
        [string]$ParseMode = 'HTML', #set to HTML by default

        [Parameter(Mandatory = $false,
            HelpMessage = 'Custom or inline keyboard object')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [psobject]$Keyboard,

        [Parameter(Mandatory = $false,
            HelpMessage = 'Disables link previews')]
        [switch]$DisablePreview, #set to false by default

        [Parameter(Mandatory = $false,
            HelpMessage = 'Send the message silently')]
        [switch]$DisableNotification,

        [Parameter(Mandatory = $false,
            HelpMessage = 'Protects the contents of the sent message from forwarding and saving')]
        [switch]$ProtectContent
    )

    Write-Verbose -Message ('Starting: {0}' -f $MyInvocation.Mycommand)

    $payload = @{
        chat_id                  = $ChatID
        text                     = $Message
        parse_mode               = $ParseMode
        disable_web_page_preview = $DisablePreview.IsPresent
        disable_notification     = $DisableNotification.IsPresent
        protect_content          = $ProtectContent.IsPresent
    } #payload

    if ($Keyboard) {
        $payload.Add('reply_markup', $Keyboard)
    }

    $uri = 'https://api.telegram.org/bot{0}/sendMessage' -f $BotToken
    Write-Debug -Message ('Base URI: {0}' -f $uri)

    Write-Verbose -Message 'Sending message...'
    $invokeRestMethodSplat = @{
        Uri         = $uri
        Body        = ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -Compress -InputObject $payload -Depth 50)))
        ErrorAction = 'Stop'
        ContentType = 'application/json'
        Method      = 'Post'
    }
    try {
        $results = Invoke-RestMethod @invokeRestMethodSplat
    } #try_messageSend
    catch {
        Write-Warning -Message 'An error was encountered sending the Telegram message:'
        Write-Error $_
        if ($_.ErrorDetails) {
            $results = $_.ErrorDetails | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        else {
            throw $_
        }
    } #catch_messageSend

    return $results
} #function_Send-TelegramTextMessage

# Fetch the current HTML content
$responseNew = Invoke-WebRequest -Uri $url -UseBasicParsing
$newHtmlContent = $responseNew.Content

# Function to extract ytInitialData script section
function Get-YtInitialData {
    param (
        [string]$htmlContent
    )
    if ($htmlContent -match 'var ytInitialData = (.*?);</script>') {
        $jsonString = $matches[1]
        return $jsonString | ConvertFrom-Json
    } else {
        return $null
    }
}

# Function to extract and group videoId and simpleText fields
function Extract-GroupedFields {
    param (
        [object]$jsonObject
    )
    $fields = @()
    $jsonObject | ForEach-Object {
        if ($_ -is [System.Management.Automation.PSObject]) {
            $group = @{}
            $_.PSObject.Properties | ForEach-Object {
                if ($_.Name -eq "videoId") {
                    $group["videoId"] = $_.Value
                } elseif ($_.Name -eq "title") {
                    $title = $_.Value
                    if ($title -is [System.Management.Automation.PSObject]) {
                        $title.PSObject.Properties | ForEach-Object {
                            if ($_.Name -eq "simpleText" -and $_.Value -ne "") {
                                $group["simpleText"] = $_.Value
                            }
                        }
                    }
                } elseif ($_.Value -is [System.Management.Automation.PSObject] -or $_.Value -is [System.Collections.IEnumerable]) {
                    $nestedFields = Extract-GroupedFields -jsonObject $_.Value
                    if ($nestedFields) {
                        $fields += $nestedFields
                    }
                }
            }
            if ($group["videoId"] -and $group["simpleText"]) {
                $fields += [PSCustomObject]$group
            }
        }
    }
    return $fields
}

# Initialize output string and hash table for unique combinations
$outputString = ""
$uniqueFields = @{}

# Extract ytInitialData from new HTML content
$newYtInitialData = Get-YtInitialData -htmlContent $newHtmlContent

# Extract and group specific fields from new HTML content
$newFields = Extract-GroupedFields -jsonObject $newYtInitialData

# Check if old.html exists
if (Test-Path $oldFilePath) {
    # Extract ytInitialData from old file
    $oldHtmlContent = Get-Content -Path $oldFilePath -Raw -Encoding UTF8
    $oldYtInitialData = Get-YtInitialData -htmlContent $oldHtmlContent

    # Extract and group specific fields from old file
    $oldFields = Extract-GroupedFields -jsonObject $oldYtInitialData

    # Compare the fields if oldFields is not null
    if ($oldFields) {
        $diff = Compare-Object -ReferenceObject $oldFields -DifferenceObject $newFields -Property videoId, simpleText -PassThru

        # Append only unique differences to the output string
        $diff | ForEach-Object {
            $uniqueKey = "$($_.videoId)|$($_.simpleText)"
            if (-not $uniqueFields.ContainsKey($uniqueKey)) {
                $uniqueFields[$uniqueKey] = $true
                if ($_.SideIndicator -eq "=>") {
                    $outputString += "New: videoId = $($_.videoId), simpleText = $($_.simpleText)`n"
                }
                #if ($_.SideIndicator -eq "<=") {
                #    $outputString += "Old: videoId = $($_.videoId), simpleText = $($_.simpleText)`n"
                #} elseif ($_.SideIndicator -eq "=>") {
                #    $outputString += "New: videoId = $($_.videoId), simpleText = $($_.simpleText)`n"
                #}
            }
        }
    } else {
        $outputString += "Old file is empty or does not contain ytInitialData.`n"
        $newFields | ForEach-Object {
            $uniqueKey = "$($_.videoId)|$($_.simpleText)"
            if (-not $uniqueFields.ContainsKey($uniqueKey)) {
                $uniqueFields[$uniqueKey] = $true
                $outputString += "videoId = $($_.videoId), simpleText = $($_.simpleText)`n"
            }
        }
    }
} else {
    $outputString += "Old file not found. Showing videoId from new HTML content:`n"
    $newFields | ForEach-Object {
        $uniqueKey = "$($_.videoId)|$($_.simpleText)"
        if (-not $uniqueFields.ContainsKey($uniqueKey)) {
            $uniqueFields[$uniqueKey] = $true
            $outputString += "videoId = $($_.videoId), simpleText = $($_.simpleText)`n"
        }
    }
}

# Replace the old HTML file with the new HTML content
#$outputString += "The old HTML file has been replaced with the new HTML content.`n"
[System.IO.File]::WriteAllText($oldFilePath, $newHtmlContent, [System.Text.Encoding]::UTF8)

# Output the final string
if ($outputString -ne "") {

    Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message ("Downloading : " + $newFields[0].simpleText.ToString() + " as " + $newFields[0].videoId)

    # Extract the directory path from the DOS command
    $commandDirectory = Split-Path -Path $dosCommand

    # Set the working directory to the command's folder
    Set-Location -Path $commandDirectory

    try {
        # Run the DOS command and wait for it to complete
        Start-Process "cmd.exe" -ArgumentList "/c $dosCommand $dosCommandArguments$($newFields[0].videoId)" -NoNewWindow -Wait -PassThru
        Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "Downloading : Executed successfully! - $dosCommand $dosCommandArguments$($newFields[0].videoId)"
    } catch {
        $errorMessage = $_.Exception.Message
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $errorLogEntry = "$timestamp - Error: $errorMessage"
    
        Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "Downloading : Error occurred - " $errorLogEntry
    }
}else{
    #Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "YT-xxxxxx - No Update"
}

