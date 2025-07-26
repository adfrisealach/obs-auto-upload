# OBS Auto-Upload to Backblaze B2

Automatically upload your OBS screen recordings to Backblaze B2 cloud storage with intelligent file monitoring, stability detection, and safe deletion.

## Features

- 🎯 **Smart File Detection**: Monitors OBS recordings and waits for them to finish before uploading
- 🔄 **Automatic Upload**: Uses rclone with optimized settings for fast, reliable uploads
- 🗑️ **Safe Deletion**: Verifies uploads before deleting local files
- 📱 **Notifications**: macOS notifications and optional NTFY push notifications
- 🔧 **Configurable**: Easy-to-use `.env` configuration file
- 🚀 **Auto-Start**: Runs automatically on login using macOS launchd
- 📊 **Comprehensive Logging**: Detailed logs for monitoring and troubleshooting

## How It Works

1. **File Monitoring**: Uses `fswatch` to detect new `.mkv` files in your OBS directory
2. **Stability Detection**: Waits for files to stop growing (configurable timeout)
3. **Upload**: Uses `rclone` with optimized settings for Backblaze B2
4. **Verification**: Confirms file exists remotely with correct size
5. **Cleanup**: Safely deletes local file after successful upload

## Requirements

- macOS (tested on macOS 14+)
- Homebrew package manager
- Backblaze B2 account
- OBS Studio (or any software that creates `.mkv` files)

## Quick Start

1. **Clone or download** this repository
2. **Run the setup script**:
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```
3. **Follow the prompts** to configure rclone and set up the service
4. **Start recording** with OBS - files will be uploaded automatically!

## Installation

### Automated Setup (Recommended)

The setup script will handle everything for you:

```bash
./setup.sh
```

This will:
- Install dependencies (`rclone`, `fswatch`)
- Configure rclone for Backblaze B2
- Create configuration files
- Set up auto-start service
- Test the configuration

### Manual Setup

If you prefer to set up manually:

1. **Install dependencies**:
   ```bash
   brew install rclone fswatch
   ```

2. **Configure rclone**:
   ```bash
   rclone config
   # Choose "n" for new remote
   # Name: b2-remote
   # Type: Backblaze B2
   # Enter your Application Key ID and Key
   ```

3. **Create configuration**:
   ```bash
   cp env.example .env
   # Edit .env with your settings
   ```

4. **Make script executable**:
   ```bash
   chmod +x obs-auto-upload.sh
   ```

## Configuration

Edit the `.env` file to customize your settings:

### Required Settings

```bash
# Your rclone remote name
REMOTE_NAME="b2-remote"

# Your Backblaze B2 bucket name
BUCKET_NAME="your-bucket-name"

# Directory to monitor for OBS recordings
WATCH_DIR="/Users/yourusername/Movies/OBS"

# Folder in bucket where files will be stored
REMOTE_BASE_PATH="obs-recordings/"
```

### Optional Settings

```bash
# File extensions to monitor
EXTENSIONS="mkv mp4 mov avi"

# Stability timeout (seconds to wait after file stops growing)
STABILITY_TIMEOUT=45

# Upload optimization
UPLOAD_TRANSFERS=6
CHUNK_SIZE="50M"
BANDWIDTH_LIMIT="18M"

# Safety settings
DELETE_AFTER_UPLOAD=true
VERIFY_UPLOAD=true

# Notifications
ENABLE_NOTIFICATIONS=true
NTFY_TOPIC="https://ntfy.sh/your-topic"  # Optional
```

## Usage

### Running Manually

```bash
# Start the monitoring service
./obs-auto-upload.sh

# View logs in real-time
tail -f ~/logs/obs-backup.log
```

### Auto-Start Service

The setup script can configure the service to start automatically:

```bash
# Start the service
launchctl load ~/Library/LaunchAgents/com.user.obs-auto-upload.plist

# Stop the service
launchctl unload ~/Library/LaunchAgents/com.user.obs-auto-upload.plist

# Check service status
launchctl list | grep obs-auto-upload
```

### Monitoring

```bash
# View application logs
tail -f ~/logs/obs-backup.log

# View service logs
tail -f ~/logs/obs-auto-upload.out
tail -f ~/logs/obs-auto-upload.err
```

## File Processing Flow

```
OBS Recording Created
       ↓
File Detected by fswatch
       ↓
Added to Monitoring Queue
       ↓
Wait for File Stability (45s default)
       ↓
Upload to Backblaze B2
       ↓
Verify Upload Success
       ↓
Delete Local File
       ↓
Send Notification
```

## Notifications

### macOS Notifications

Automatically shows notifications for:
- New recording detected
- Upload started
- Upload completed
- Upload failed

### NTFY Push Notifications

Set `NTFY_TOPIC` in `.env` to receive push notifications on any device:

```bash
NTFY_TOPIC="https://ntfy.sh/your-unique-topic"
```

## Troubleshooting

### Common Issues

**Script won't start**:
- Check if `.env` file exists and is configured
- Verify rclone remote is set up: `rclone listremotes`
- Test bucket access: `rclone lsd b2-remote:your-bucket-name`

**Files not uploading**:
- Check file extensions in `EXTENSIONS` setting
- Verify file size meets `MIN_FILE_SIZE_MB` requirement
- Check logs for stability timeout issues

**Upload failures**:
- Verify internet connection
- Check Backblaze B2 credentials
- Review bandwidth limits in configuration

**Service not starting automatically**:
- Check launch agent: `launchctl list | grep obs-auto-upload`
- Verify plist file exists: `ls ~/Library/LaunchAgents/com.user.obs-auto-upload.plist`
- Check service logs: `tail -f ~/logs/obs-auto-upload.err`

### Debug Mode

Enable debug logging:

```bash
# In .env file
LOG_LEVEL="DEBUG"
```

### Manual Testing

Test individual components:

```bash
# Test rclone connection
rclone lsd b2-remote:your-bucket-name

# Test file upload
rclone copy test-file.mkv b2-remote:your-bucket-name/obs-recordings/

# Test fswatch
fswatch -1 ~/Movies/OBS
```

## File Structure

```
obs-auto-upload/
├── obs-auto-upload.sh    # Main script
├── setup.sh             # Automated setup script
├── env.example          # Configuration template
├── .env                 # Your configuration (created by setup)
└── README.md           # This file
```

## Advanced Configuration

### Custom Upload Settings

For different internet speeds, adjust these settings in `.env`:

```bash
# For slower connections
UPLOAD_TRANSFERS=2
BANDWIDTH_LIMIT="5M"

# For faster connections
UPLOAD_TRANSFERS=10
BANDWIDTH_LIMIT="50M"
```

### Multiple File Types

Monitor additional file types:

```bash
EXTENSIONS="mkv mp4 mov avi flv"
```

### Custom Stability Timeout

For longer recordings or slower storage:

```bash
STABILITY_TIMEOUT=120    # 2 minutes
MAX_WAIT_TIME=14400     # 4 hours
```

## Security Considerations

- rclone stores credentials securely in `~/.config/rclone/rclone.conf`
- `.env` file contains no sensitive information
- All uploads use HTTPS encryption
- File verification prevents incomplete uploads

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is open source and available under the [MIT License](LICENSE).

## Support

If you encounter issues:

1. Check the troubleshooting section
2. Review the logs for error messages
3. Test individual components
4. Create an issue with detailed information

## Changelog

### v1.0.0
- Initial release
- Basic file monitoring and upload
- macOS notifications
- Auto-start service
- Comprehensive logging 