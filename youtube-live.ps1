# Save as "UTF-8 with BOM" as Chinese characters
# Define the URL and file path
param(
    [string]$ytURL = "https://www.youtube.com/xxxxx/stream",
    [string]$oldFilePath = "C:\Temp\YT.html",
    [string]$logPath = "C:\Temp\YT-Downloader.LOG",
    [int]$expectedSeconds = 3600
)

# Define TG
$botToken = '9999999999:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
$chat = '-9999999999'

# Define Loop - Max retries
$maxRetries = 3

# Define bgutilhttp
$bgutilhttp = 'http://xxx.xxx.xxx.xxx:4416'
# Due to YT Live new policy, require to use 
#   deno (https://github.com/denoland/deno)
#   node.js (install it https://nodejs.org/en/download/current)
#   bgutil-ytdlp-pot-provider (https://github.com/Brainicism/bgutil-ytdlp-pot-provider)

# Define the DOS command you want to run
$dosCommand = "X:\YT-Video\yt-dlp.exe"
$dosCommandArguments = "-U --merge-output-format mp4 --live-from-start --embed-thumbnail --add-metadata --encoding utf-8 --cookies-from-browser firefox --extractor-args `"youtubepot-bgutilhttp:base_url=$bgutilhttp`" --js-runtime node https://www.youtube.com/watch?v="

# Extract channel name
if ($ytURL -match '@([^/]+)') {
    $channelName = $matches[1]
    #Write-Output "Channel name: $channelName"
#} else {
    #Write-Output "No channel name found in URL."
}

# Add yyyyMMdd at $logPath 
$logPath = Join-Path (Split-Path $logPath) ("{0}-{1}-{2}{3}" -f [System.IO.Path]::GetFileNameWithoutExtension($logPath), $channelName, (Get-Date -Format "yyyyMMdd"), [System.IO.Path]::GetExtension($logPath))

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
                            #if ($_.Name -eq "simpleText" -and $_.Value -notlike "*收看次數*" -and $_.Value -ne "") {
                            if ($_.Name -eq "runs" -and $_.Value -ne "") {
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

function Get-TrimmedDownloadOutput {
    param (
        [string]$Output
    )

    # Split into lines
    $lines = $Output -split "`r?`n"

    # Find line numbers that contain multiple [download]% markers
    $segments = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '\[download\].*%.*\[download\].*%' -or
			$lines[$i] -match '^\d+:\s*\[download\]') {
            
			$segments += $i
        }
    }

    # Process each segment line
    foreach ($idx in $segments) {
        $segLine = $lines[$idx]

        # Split that single line into pseudo-lines at each [download]
		if ($segLine -match '\[download\].*%.*\[download\].*%') {
			$parts = $segLine -split '(?=\[download\])'
		}else{
			$parts = $segLine -split '(?=\d+:\s\[download\])'
		}
        $parts = $parts | Where-Object { $_.Trim() -ne "" }

        # Take first 3 and last 3
        $first3 = $parts | Select-Object -First 3
        $last3  = $parts | Select-Object -Last 3

        # Build shortened segment
        $shortSeg = ($first3 + '...' + $last3) -join "`n"

        # Replace back into $lines array
        $lines[$idx] = $shortSeg
    }

    # Return the modified output as a single string
    return ($lines -join "`n")
}


# Fetch the current HTML content
$responseNew = Invoke-WebRequest -Uri $ytURL -UseBasicParsing
$newHtmlContent = $responseNew.Content

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
            #$uniqueKey = "$($_.videoId)|$($_.simpleText)"
            $uniqueKey = "$($_.videoId)"
            if (-not $uniqueFields.ContainsKey($uniqueKey)) {
                $uniqueFields[$uniqueKey] = $true
                if ($_.SideIndicator -eq "=>") {
                    $outputString += "New: videoId = $($_.videoId), simpleText = $($_.simpleText)`n"
                }
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
[System.IO.File]::WriteAllText($oldFilePath, $newHtmlContent, [System.Text.Encoding]::UTF8)

# Output the final string
if ($outputString -ne "") {

	$retryCount = 0
	$success = $false
	
	# Extract the directory path from the DOS command
    $commandDirectory = Split-Path -Path $dosCommand

    # Set the working directory to the command's folder
    Set-Location -Path $commandDirectory
	
	while ($retryCount -lt $maxRetries -and -not $success) {
		$retryCount++

		$startTime = Get-Date
		try {
			Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message ("" + $newFields[0].simpleText[0].text + " as " + $newFields[0].videoId)
			
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "cmd.exe"
            $psi.Arguments = "/c chcp 65001 >nul && $dosCommand $dosCommandArguments$($newFields[0].videoId)"
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

            $psi.WorkingDirectory = "E:\YT-Video"
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            $process.Start() | Out-Null

            # Capture output
            $output = $process.StandardOutput.ReadToEnd()
            $errorOutput = $process.StandardError.ReadToEnd()

            $process.WaitForExit()

			$endTime = Get-Date
			$elapsedSeconds = ($endTime - $startTime).TotalSeconds
			
			Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "$($newFields[0].simpleText[0].text) Run #$retryCount finished (ExitCode=$($process.ExitCode), Duration=$([math]::Round($elapsedSeconds))s)"

			# Success if no error output and ran for the expected time, or specific end-of-stream error
			if (($null -eq $errorOutput -or $errorOutput -eq "") -and $elapsedSeconds -ge $expectedSeconds) {
				$success = $true
				Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "$($newFields[0].simpleText[0].text) - Completed successfully. Ended."
			} elseif ($errorOutput -match "ERROR: Did not get any data blocks" -and $elapsedSeconds -ge $expectedSeconds) {
				$success = $true
				Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "$($newFields[0].simpleText[0].text) - Stream ended normally. Completed."
			} else {
				Add-Content -Path $logPath -Value ("==== Run #$retryCount start at $($startTime) ====`n" + $output + "`n==== Error ====`n" + $errorOutput + "`n==== Run #$retryCount end at $($endTime) ====`n") -Encoding UTF8
				$message = Get-TrimmedDownloadOutput($output)
				if ($null -ne $errorOutput -and $errorOutput -ne "") {
					$message += "`n" + $errorOutput.Trim()
				}
				Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message $message
								
				if ($retryCount -lt $maxRetries) {

					#Clear YT-DLP Cache
                    $process = Start-Process "cmd.exe" -ArgumentList "/c $dosCommand --rm-cache-dir" -Wait -PassThru
                    
					#Rename downloaded file
					if ($output -match '\[download\]\s+(.+?)\s+has already been downloaded' -or
						$output -match '\[Merger\]\s+Merging formats into\s+"(.+?)"') {

						$downloadedFile = $matches[1]

						# Build timestamp string (yyyyMMdd_HHmmss format)
						$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

						# Extract directory and base name
						$baseName  = [System.IO.Path]::GetFileNameWithoutExtension($downloadedFile)
						$extension = [System.IO.Path]::GetExtension($downloadedFile)

						# Construct new filename
						$newFileName = "$baseName`_$timestamp$extension"
						$newFilePath = Join-Path $commandDirectory $newFileName
						$downloadFilePath = Join-Path $commandDirectory $downloadedFile

						# Rename the file
						[System.IO.File]::Move($downloadFilePath, $newFilePath)

						# Notify via Telegram
						Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "Renamed file:`n$downloadedFile → $newFileName"
					}

					Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "$($newFields[0].simpleText[0].text) Process ended prematurely ($expectedSeconds)s. Retrying..."
				} else {
					Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "$($newFields[0].simpleText[0].text) Process ended prematurely ($expectedSeconds)s. Max retries reached. Ended."
				}
			}
		} catch {
			$errorMessage = $_.Exception.Message
			$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			$errorLogEntry = "$timestamp - Error: $errorMessage"
			Add-Content -Path $logPath -Value $errorLogEntry -Encoding UTF8
			Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "YT Live Downloader : Error occurred - $errorLogEntry"
		}
	}
}
