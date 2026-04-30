# YT-LiveDownloader

A PowerShell script that automatically monitors YouTube channels for live streams and downloads them using yt-dlp. Features Telegram notifications and robust error handling with retry mechanisms.

## Features

- **Automatic Live Stream Detection**: Monitors YouTube channel pages for new live streams
- **Intelligent Comparison**: Compares current channel state with cached data to detect new streams
- **Automated Downloads**: Uses yt-dlp to download live streams with optimized settings
- **Telegram Notifications**: Sends real-time updates about download progress and status
- **Retry Mechanism**: Automatically retries failed downloads with configurable delays
- **Comprehensive Logging**: Detailed logging of all operations and errors
- **File Management**: Automatically renames downloaded files with timestamps
- **Debug Mode**: Optional debug output for troubleshooting

## Requirements

- **PowerShell**: Version 5.1 or higher (PowerShell Core recommended for better UTF-8 support)
- **yt-dlp**: Latest version installed and accessible via path
- **Firefox Browser**: For cookie extraction (or configure alternative browser)
- **Internet Connection**: For accessing YouTube and downloading streams
- **Telegram Bot**: For notifications (optional but recommended)
- **bgutil-ytdlp-pot-provider**: For bypassing YouTube bot detection (optional, see [GitHub repo](https://github.com/Brainicism/bgutil-ytdlp-pot-provider))

## Installation

1. **Clone or Download** the script `YT-LiveDownloader.ps1`

2. **Install yt-dlp**:
   ```powershell
   # Download yt-dlp.exe to a directory in your PATH
   # Example: E:\YT-Video\yt-dlp.exe (as configured in script)
   ```

3. **Set up Telegram Bot** (optional):
   - Create a bot via [@BotFather](https://t.me/botfather) on Telegram
   - Get your bot token and chat ID
   - Update the script with your credentials

4. **Configure Browser Cookies**:
   - Ensure Firefox is installed (or modify script for your preferred browser)
   - Log in to YouTube in Firefox for better access

## Usage

### Basic Usage

```powershell
.\YT-LiveDownloader.ps1
```

### With Custom Parameters

```powershell
.\YT-LiveDownloader.ps1 -ytURL "https://www.youtube.com/@YourChannel/streams" -oldFilePath "C:\Temp\YT-Info.json" -logPath "C:\Temp\YT-Downloader.LOG"
```

### Debug Mode

```powershell
.\YT-LiveDownloader.ps1 -Debug
```

### Force Download

```powershell
.\YT-LiveDownloader.ps1 -ForceDownload
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ytURL` | String | `https://www.youtube.com/@club80co/streams` | YouTube channel streams URL to monitor |
| `oldFilePath` | String | `C:\Temp\YT-Info.json` | Path to cache file for comparing channel state |
| `logPath` | String | `C:\Temp\YT-Downloader.LOG` | Path for detailed logging output |
| `expectedDurationSeconds` | Int | `3600` | Expected duration of live streams in seconds |
| `ForceDownload` | Switch | `false` | Force download even if no new streams detected |
| `Debug` | Switch | `false` | Enable debug output for troubleshooting |

## Configuration

### Telegram Settings

Edit these variables in the script:

```powershell
$botToken = 'YOUR_BOT_TOKEN_HERE'
$chat = 'YOUR_CHAT_ID_HERE'
```

### yt-dlp Settings

Modify the download command and arguments:

```powershell
$dosCommand = "E:\YT-Video\yt-dlp.exe"
$dosCommandArguments = "-U --merge-output-format mp4 --live-from-start --embed-thumbnail --add-metadata --encoding utf-8 --cookies-from-browser firefox --extractor-args `"youtubepot-bgutilhttp:base_url=$bgutilhttp`" --js-runtime node https://www.youtube.com/watch?v="
```

### Botguard POT Provider Settings (Optional)

The script uses [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider) to bypass YouTube's "Sign in to confirm you're not a bot" message. This is particularly useful when running from IP addresses flagged by YouTube.

Configure the `$bgutilhttp` variable with your bgutil HTTP server URL:

```powershell
$bgutilhttp = 'http://192.168.9.11:4416'  # Example server URL
```

**Setup Instructions:**
1. Install the bgutil-ytdlp-pot-provider from the GitHub repository
2. Run the bgutil HTTP server
3. Update the `$bgutilhttp` variable with your server URL

## How It Works

1. **Channel Monitoring**: Fetches the channel's streams page and parses the embedded JSON data
2. **Stream Detection**: Extracts live stream information and compares with cached data
3. **Download Trigger**: When new live streams are detected, initiates download process
4. **Progress Tracking**: Monitors download progress and sends Telegram updates
5. **Error Handling**: Implements retry logic for failed downloads with exponential backoff
6. **File Management**: Renames completed downloads with timestamps

## Output and Logging

- **Console Output**: Real-time status updates (when debug enabled)
- **Log File**: Detailed operation logs with timestamps
- **Telegram Notifications**: Instant alerts for download events
- **Cache File**: JSON file storing channel state for comparison

## Troubleshooting

### Common Issues

1. **"Could not extract channel name"**: Check the YouTube URL format
2. **Download failures**: Verify yt-dlp installation and PATH
3. **Telegram errors**: Confirm bot token and chat ID are correct
4. **Cookie issues**: Ensure browser is logged into YouTube

### Debug Mode

Run with `-Debug` switch to see detailed internal operations:

```powershell
.\YT-LiveDownloader.ps1 -Debug
```

This will show:
- Channel parsing details
- JSON structure analysis
- Download attempt logs
- Error details

## Dependencies

- **yt-dlp**: For downloading YouTube streams
- **Firefox**: For cookie extraction (configurable)
- **Node.js**: Required by yt-dlp for some operations
- **PowerShell**: Core runtime environment

## License

This project is provided as-is for educational and personal use. Please respect YouTube's Terms of Service and copyright laws when downloading content.

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve the script.
