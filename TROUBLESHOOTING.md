# 🔧 Troubleshooting Guide

## Common Issues and Solutions

### 🚫 Files Not Being Detected

**Symptoms:** Script runs but doesn't detect new recordings

**Solutions:**
1. **Grant Full Disk Access:**
   - System Settings → Privacy & Security → Full Disk Access
   - Add Terminal.app
   - Restart Terminal completely

2. **Test fswatch manually:**
   ```bash
   fswatch -1 /Users/yourusername/Movies/OBS
   # Should show file paths when files are created
   ```

3. **Check watch directory:**
   ```bash
   # Verify OBS saves to the correct directory
   ls -la ~/Movies/OBS
   ```

### ⚠️ Upload Failures

**Symptoms:** "Upload failed" notifications

**Solutions:**
1. **Check internet connection**
2. **Verify Backblaze B2 credentials:**
   ```bash
   rclone lsd b2-remote:your-bucket-name
   ```
3. **Check logs for specific errors:**
   ```bash
   tail -50 ~/logs/obs-backup.log | grep ERROR
   ```

### 🔄 Service Not Starting

**Symptoms:** No automatic monitoring

**Solutions:**
1. **Check service status:**
   ```bash
   launchctl list | grep obs-auto-upload
   ```

2. **Restart service:**
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.user.obs-auto-upload.plist
   launchctl load ~/Library/LaunchAgents/com.user.obs-auto-upload.plist
   ```

3. **Check service logs:**
   ```bash
   tail -f ~/logs/obs-auto-upload.err
   ```

### 📱 No Notifications

**Symptoms:** Script works but no popup notifications

**Solutions:**
1. **Enable Terminal notifications:**
   - System Settings → Notifications → Terminal
   - Allow notifications

2. **Test notifications manually:**
   ```bash
   osascript -e 'display notification "Test message" with title "Test"'
   ```

## Advanced Troubleshooting

### Debug Mode

Enable detailed logging:
```bash
LOG_LEVEL=DEBUG ./obs-auto-upload.sh
```

### Manual Testing

Test the script manually:
```bash
cd /path/to/obs-auto-upload
./obs-auto-upload.sh
```

### Check Configuration

Verify your settings:
```bash
cat .env
```

### Reset Everything

If all else fails:
```bash
# Stop service
launchctl unload ~/Library/LaunchAgents/com.user.obs-auto-upload.plist

# Remove service file
rm ~/Library/LaunchAgents/com.user.obs-auto-upload.plist

# Re-run setup
./setup.sh
```