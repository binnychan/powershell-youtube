# Save as "UTF-8 with BOM" as Chinese characters
# Define the URL and file path
# $url = "https://www.youtube.com/@xxxxx/streams"
# $oldFilePath = "C:\temp\YT-Info.json"

param(
    [string]$ytURL = "https://www.youtube.com/@xxxxx/streams",
    [string]$oldFilePath = "C:\Temp\YT-Info.json",
    [string]$logPath = "C:\Temp\YT-Downloader.LOG",
    [int]$expectedDurationSeconds = 3600,
	[string]$targetTitle = "直播",
    [switch]$ForceDownload,
    [switch]$Debug
)

if ($Debug) { Write-Host "=== Script Started with Debug Mode Enabled ===" -ForegroundColor Green }

# Define TG
$botToken = '9999999999:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
$chat = '-9999999999'

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
    if ($Debug) { Write-Host "Channel name: $channelName" }
} else {
    $channelName = "UnknownChannel"
    if ($Debug) { Write-Host "Could not extract channel name from URL. Using default: $channelName" }
}

# Add yyyyMMdd at $logPath 
$logPath = Join-Path (Split-Path $logPath) ("{0}-{1}-{2}{3}" -f [System.IO.Path]::GetFileNameWithoutExtension($logPath), $channelName, (Get-Date -Format "yyyyMMdd"), [System.IO.Path]::GetExtension($logPath))

# Force UTF-8 output regardless of host
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $OutputEncoding = [System.Text.Encoding]::UTF8
} else {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

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
        if ($Debug) {
            Write-Host "Debug Mode: Message payload that would be sent to Telegram:" -ForegroundColor Yellow
            $payload | ConvertTo-Json -Depth 50 | Write-Host
            $results = @{ ok = $true; result = @{ message_id = 12345 } }
       } else {
            $results = Invoke-RestMethod @invokeRestMethodSplat
        }
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
function Get-GroupedFields {
    param (
        [object]$jsonObject
    )
    
    $fields = @()
    $targetTitle = "直播"

    # Navigate to the tabs array
    $tabs = $jsonObject.contents.twoColumnBrowseResultsRenderer.tabs
    if ($Debug) { Write-Host "Found tabs: $($tabs.Count)" }

    # Debug: Show all tab titles
    if ($Debug) {
        Write-Host "=== All Tab Titles ===" -ForegroundColor Yellow
        foreach ($tab in $tabs) {
            if ($tab.tabRenderer.title) {
                $title = $tab.tabRenderer.title
                Write-Host "  Tab title: '$title'" -ForegroundColor Cyan
                Write-Host "    Length: $($title.Length), Bytes: $([System.Text.Encoding]::UTF8.GetBytes($title) -join ',')" -ForegroundColor Gray
                Write-Host "    Matches $($targetTitle): $($title -eq $($targetTitle))" -ForegroundColor Gray
            } else {
                Write-Host "  Tab: (No title property)" -ForegroundColor Gray
            }
        }
    }

    # Find the tab(s) where title = "直播"
    $targetTabs = $tabs | Where-Object { $_.tabRenderer.title -eq $targetTitle }
    
    # If not found, try case-insensitive or partial match
    if (-not $targetTabs) {
        if ($Debug) { Write-Host "Exact match '$($targetTitle)' not found, trying case-insensitive..." -ForegroundColor Yellow }
        $targetTabs = $tabs | Where-Object { $_.tabRenderer.title -like "*$($targetTitle)*" }
    }
    
    # If still not found, try to find by looking at tab with richGridRenderer content
    if (-not $targetTabs) {
        if ($Debug) { Write-Host "Partial match failed, trying to find tab with richGridRenderer content..." -ForegroundColor Yellow }
        $targetTabs = $tabs | Where-Object { $null -ne $_.tabRenderer.content.richGridRenderer }
        if ($targetTabs) {
            if ($Debug) { Write-Host "Found $($targetTabs.tabRenderer.title) tab(s) with richGridRenderer content" }
        }
    }
    
    # If still nothing, show all properties of all tabs for debugging
    if (-not $targetTabs) {
        if ($Debug) {
            Write-Host "ERROR: Still no tabs found. Showing all tab properties..." -ForegroundColor Red
            for ($i = 0; $i -lt $tabs.Count; $i++) {
                $tab = $tabs[$i]
                Write-Host "Tab[$i] Properties:" -ForegroundColor Yellow
                if ($tab.tabRenderer) {
                    $tab.tabRenderer | Get-Member -MemberType NoteProperty | ForEach-Object {
                        $propName = $_.Name
                        $propValue = $tab.tabRenderer.$propName
                        if ($propValue -is [string]) {
                            Write-Host "  .$propName = '$propValue'" -ForegroundColor Gray
                        } elseif ($propValue -is [object]) {
                            Write-Host "  .$propName = [Object]" -ForegroundColor Gray
                        } else {
                            Write-Host "  .$propName = $propValue" -ForegroundColor Gray
                        }
                    }
                }
            }
            Write-Host "Save the json structure of the entire tabs array for offline analysis." -ForegroundColor Yellow
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $tabs | ConvertTo-Json -Depth 100 | Out-File -FilePath "C:\Temp\YT-Tabs-Debug_$timestamp.json" -Encoding UTF8
        }
        return @()
    }
    
    if ($Debug) { Write-Host "Found targettabs - Titles: $($targetTabs.tabRenderer.title -join ', ')" }

    if ($targetTabs) {
        if ($Debug) { Write-Host "Found items in target tab: $($targetTabs.tabRenderer.content.richGridRenderer.contents.Count)" }
    } else {
        if ($Debug) { Write-Host "ERROR: No target tabs found! Will return empty results." -ForegroundColor Red }
        return @()
    }
	
	$targetTabs.tabRenderer.content.richGridRenderer.contents | ForEach-Object {
		#$videoId   = $_.richItemRenderer.content.lockupViewModel.contentID
		#$simpleText = $_.richItemRenderer.content.lockupViewModel.metadata.lockupMetadataViewModel.title.content
		$videoId = $_.richItemRenderer.content.lockupViewModel.contentID
		if (-not $videoId) {
			$videoId = $_.richItemRenderer.content.videoRenderer.videoID
		}

		$simpleText = $_.richItemRenderer.content.lockupViewModel.metadata.lockupMetadataViewModel.title.content
		if (-not $simpleText) {
			$simpleText = ($_.richItemRenderer.content.videoRenderer.title.runs | ForEach-Object { $_.text }) -join ''
		}

		# Only proceed if both fields are non-empty
		if (![string]::IsNullOrWhiteSpace($videoId) -and 
			![string]::IsNullOrWhiteSpace($simpleText)) {
			
			$group = @{
				videoId    = $videoId
				simpleText = $simpleText
			}

			if ($Debug) { 
                Write-Host "Group: videoId=" -NoNewline
                Write-Host $videoId -ForegroundColor Green -NoNewline
                Write-Host ", simpleText=" -NoNewline
                Write-Host $simpleText -ForegroundColor Green
            }
			$fields += [PSCustomObject]$group
		} else {
            if ($Debug) { 
                Write-Host "Skipping item due to missing fields: videoId='$videoId', simpleText='$simpleText'" -ForegroundColor Yellow
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

# Extract ytInitialData from new HTML content
$newYtInitialData = Get-YtInitialData -htmlContent $newHtmlContent

if ($Debug) {
    Write-Host "=== ytInitialData Structure ===" -ForegroundColor Yellow
    if ($newYtInitialData) {
        Write-Host "ytInitialData exists: Yes" -ForegroundColor Green
        if ($newYtInitialData.contents) {
            Write-Host "  .contents: exists" -ForegroundColor Green
            if ($newYtInitialData.contents.twoColumnBrowseResultsRenderer) {
                Write-Host "    .twoColumnBrowseResultsRenderer: exists" -ForegroundColor Green
            } else {
                Write-Host "    .twoColumnBrowseResultsRenderer: MISSING" -ForegroundColor Red
            }
        } else {
            Write-Host "  .contents: MISSING" -ForegroundColor Red
        }
    } else {
        Write-Host "ytInitialData exists: NO - JSON parsing may have failed" -ForegroundColor Red
    }
}

# Extract and group specific fields from new HTML content
$newFields = Get-GroupedFields -jsonObject $newYtInitialData

if ($Debug) { Write-Host "Extracted $($newFields.Count) new fields from HTML content" }

# Initialize output string and hash table for unique combinations
$outputString = ""
$uniqueFields = @{}
$liveStream = $false

# Check if old file exists
if (Test-Path $oldFilePath) {

    # Assuming the old file is already in JSON format with the same structure as newFields
    $oldFields = Get-Content -Path $oldFilePath -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($Debug) { Write-Host "Loaded $($oldFields.Count) old fields from file" }

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
                    $liveStream = $true
                    $outputString += "New: videoId = $($_.videoId), liveStream = $($liveStream), simpleText = $($_.simpleText)`n"
                }elseif ($_.SideIndicator -eq "<=") {
                     $outputString += "Old: videoId = $($_.videoId), liveStream = $($liveStream), simpleText = $($_.simpleText)`n"
                }
            }
        }
    } else {
        $liveStream = $true
        $outputString += "Old file is empty or does not contain ytInitialData.`n"
        $newFields | ForEach-Object {
            $uniqueKey = "$($_.videoId)|$($_.simpleText)"
            if (-not $uniqueFields.ContainsKey($uniqueKey)) {
                $uniqueFields[$uniqueKey] = $true
                $outputString += "videoId = $($_.videoId), liveStream = $($liveStream), simpleText = $($_.simpleText)`n"
            }
        }
    }
} else {
    $liveStream = $true
    $outputString += "Old file not found. Showing videoId from new HTML content:`n"
    $newFields | ForEach-Object {
        $uniqueKey = "$($_.videoId)|$($_.simpleText)"
        if (-not $uniqueFields.ContainsKey($uniqueKey)) {
            $uniqueFields[$uniqueKey] = $true
            $outputString += "videoId = $($_.videoId), liveStream = $($liveStream), simpleText = $($_.simpleText)`n"
        }
    }
}

# Replace the old HTML file with the new HTML content
$newFields | ConvertTo-Json -Depth 100 | Out-File -FilePath $oldFilePath -Encoding UTF8
#$outputString += "The old HTML file has been replaced with the new HTML content.`n"

if ($Debug) { Write-Host "outputString : $outputString" }

# live stream detected or force download specified, start download process
if ($liveStream -or $ForceDownload) {

	# Extract the directory path from the DOS command
    $commandDirectory = Split-Path -Path $dosCommand

    # Set the working directory to the command's folder
    Set-Location -Path $commandDirectory

	$startTotalTime = Get-Date
	$retryCount = 0
	$success = $false
	$delaySeconds = 180
	$currentVideoID = $newFields[0].videoId
	$currentVideoText = $newFields[0].simpleText
	
	while (-not $success) {
		$currentTime = Get-Date
		$totalElapsed = ($currentTime - $startTotalTime).TotalSeconds
		if ($totalElapsed -ge $expectedDurationSeconds) {
			break
		}
		if ($retryCount -gt 0) {
			$remainingTime = $expectedDurationSeconds - $totalElapsed
			$actualDelay = [math]::Min($delaySeconds, $remainingTime)
            if ($Debug) { 
                # Convert remaining seconds into a DateTime starting from Unix epoch (or just current time + remainingTime)
                $formattedRemainingTime = (Get-Date).AddSeconds($remainingTime).ToString("yyyyMMdd_HHmmss")
                Write-Host "Retrying download at $formattedRemainingTime ($actualDelay)s later" -ForegroundColor Yellow
            }
			if ($actualDelay -gt 0) {
				Start-Sleep -Seconds $actualDelay
			}
		}
		$retryCount++

		if ($Debug) { Write-Host "Starting download attempt #$retryCount" }

		$startTime = Get-Date
		try {
			Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message ("" + $currentVideoText + " as https://www.youtube.com/watch?v=" + $currentVideoID)
			
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "cmd.exe"
            $psi.Arguments = "/c chcp 65001 >nul && $dosCommand $dosCommandArguments$($currentVideoID)"
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

            $psi.WorkingDirectory =  Split-Path $dosCommand
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
			
			Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "$($currentVideoText) Run #$retryCount finished (ExitCode=$($process.ExitCode), Duration=$([math]::Round($elapsedSeconds))s)" -DisableNotification

			# Success if no error output and ran for expected time, or specific end-of-stream error
			if (($null -eq $errorOutput -or $errorOutput -eq "") -and $elapsedSeconds -ge $expectedDurationSeconds) {
				$success = $true
				Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "$($currentVideoText) - Completed successfully. Ended."
			} elseif ($errorOutput -match "ERROR: Did not get any data blocks" -and $elapsedSeconds -ge $expectedDurationSeconds) {
				$success = $true
				Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "$($currentVideoText) - Stream ended normally. Completed."
			} else {
				Add-Content -Path $logPath -Value ("==== Run #$retryCount start at $($startTime) ====`n" + $output + "`n==== Error ====`n" + $errorOutput + "`n==== Run #$retryCount end at $($endTime) ====`n") -Encoding UTF8
				$message = Get-TrimmedDownloadOutput($output)
				if ($null -ne $errorOutput -and $errorOutput -ne "") {
					$message += "`n" + $errorOutput.Trim()
				}
				Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message $message -DisablePreview -DisableNotification
				
				# Clear YT-DLP Cache
                    Start-Process "cmd.exe" -ArgumentList "/c $dosCommand --rm-cache-dir" -Wait -PassThru
                    
					# Rename downloaded file if exists
					if ($output -match '\[download\]\s+(.+?)\s+has already been downloaded' -or
						$output -match '\[Merger\]\s+Merging formats into\s+"(.+?)"') {

						$downloadedFile = $matches[1]

						# Build timestamp string (yyyyMMdd_HHmmss format)
						$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

						# Extract base name and extension
						$baseName  = [System.IO.Path]::GetFileNameWithoutExtension($downloadedFile)
						$extension = [System.IO.Path]::GetExtension($downloadedFile)

						# Construct new filename
						$newFileName = "$baseName`_$timestamp$extension"
						$newFilePath = Join-Path $commandDirectory $newFileName
						$downloadFilePath = Join-Path $commandDirectory $downloadedFile

						# Rename the file
						if (Get-ChildItem -LiteralPath $downloadFilePath) {
							[System.IO.File]::Move($downloadFilePath, $newFilePath)
							# Notify via Telegram
							Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "Renamed file:`n$downloadedFile → $newFileName" -DisablePreview -DisableNotification
						} else {
							Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "Renamed file (Not Found):`n$downloadedFile → $newFileName" -DisablePreview -DisableNotification
						}
					}

					$retryTime = (Get-Date).AddSeconds($delaySeconds).ToString('HH:mm:ss')
					Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "$($currentVideoText) Process ended prematurely $([math]::Round($elapsedSeconds))s. Retrying@$retryTime..."
				
			}
		} catch {
			$errorMessage = $_.Exception.Message
			$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			$errorLogEntry = "$timestamp - Error: $errorMessage"
			Add-Content -Path $logPath -Value $errorLogEntry -Encoding UTF8
			Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "YT Live Downloader : Error occurred - $errorLogEntry"
		}
	}
	if (-not $success) {
		Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "$($currentVideoText) Process ended prematurely ($expectedDurationSeconds)s. Time limit exceeded. Ended."
	}
} else {
    if ($Debug) { Write-Host "No new videos found for URL: $ytURL" }
    # Optional: Send message if no new videos
    # Send-TelegramTextMessage -BotToken $botToken -ChatID $chat -Message "YT Live Downloader : No new videos - $ytURL"
}

if ($Debug) { Write-Host "=== Script Ended with Debug Mode Enabled ===" -ForegroundColor Green }
