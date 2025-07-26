# 🚀 OBS Auto-Upload - Quick Start Guide

**For Complete Beginners** - Get your OBS recordings automatically uploaded to the cloud in 15 minutes!

## 📋 What You'll Need

- ✅ A Mac computer (macOS 14+ recommended)
- ✅ OBS Studio installed
- ✅ A Backblaze B2 account (free tier available)
- ✅ About 15 minutes

## 🎯 What This Does

When you record with OBS, this script will:
1. **Automatically detect** when you finish recording
2. **Wait** for the file to be completely saved
3. **Upload** it to your Backblaze B2 cloud storage
4. **Verify** the upload was successful
5. **Delete** the local file to save space
6. **Notify** you when it's done

## 🛠️ Step 1: Get Your Backblaze B2 Credentials

1. Go to [backblaze.com/b2](https://www.backblaze.com/b2/cloud-storage.html)
2. Sign up for a free account (10GB free storage)
3. Create a new bucket:
   - Click "Create a Bucket"
   - Name it something like "my-obs-recordings"
   - Set it to "Private"
4. Create Application Keys:
   - Go to "App Keys" in the left menu
   - Click "Add a New Application Key"
   - Give it a name like "OBS Upload"
   - Select your bucket
   - **Save the Key ID and Application Key** - you'll need these!

## 🏗️ Step 2: Automatic Setup

1. **Open Terminal** (Applications → Utilities → Terminal)

2. **Navigate to the script folder**:
   ```bash
   cd /path/to/obs-auto-upload
   ```

3. **Run the setup script**:
   ```bash
   ./setup.sh
   ```

4. **Follow the prompts**:
   - Install dependencies? → **Yes**
   - Configure rclone? → **Yes**
   - When asked for credentials, enter your Backblaze B2 Key ID and Application Key
   - Bucket name? → Enter your bucket name (e.g., "my-obs-recordings")
   - Auto-start on login? → **Yes** (recommended)

## ⚙️ Step 3: Grant Permissions (Important!)

**macOS requires special permissions for file monitoring:**

1. **Open System Settings** → **Privacy & Security** → **Full Disk Access**
2. **Click the 🔒 lock** to unlock (enter your password)
3. **Click the + button**
4. **Navigate to Applications** → **Utilities** → **Terminal.app**
5. **Add Terminal** to the list
6. **Restart Terminal completely**

## 🎬 Step 4: Test It!

1. **Start OBS Studio**
2. **Record a short test video** (10-30 seconds)
3. **Stop recording**
4. **Watch for notifications** - you should see:
   - "OBS Recording Detected" (immediately)
   - "OBS Upload Complete" (after ~90 seconds)

## 📊 Step 5: Monitor and Verify

**Check if it's working:**
```bash
# View recent activity
tail -20 ~/logs/obs-backup.log

# Check service status
launchctl list | grep obs-auto-upload
```

**Check your cloud storage:**
- Log into your Backblaze B2 account
- Browse your bucket - your recording should be there!

## 🔧 Daily Usage

Once set up, **you don't need to do anything!** Just:

1. ✅ **Record with OBS** as normal
2. ✅ **Stop recording** when done
3. ✅ **Wait ~90 seconds** for upload to complete
4. ✅ **Get notification** when done

Your recordings are automatically backed up to the cloud and local space is freed up.

## 🆘 Troubleshooting

### "No notifications appearing"
- Check System Settings → Notifications → Terminal (allow notifications)

### "Upload failed" notifications
- Check internet connection
- Verify Backblaze B2 credentials: `rclone lsd b2-remote:your-bucket-name`

### "Files not being detected"
- Ensure Terminal has Full Disk Access (Step 3 above)
- Try running manually: `./obs-auto-upload.sh`

### "Service not starting"
```bash
# Check service status
launchctl list | grep obs-auto-upload

# Restart service
launchctl unload ~/Library/LaunchAgents/com.user.obs-auto-upload.plist
launchctl load ~/Library/LaunchAgents/com.user.obs-auto-upload.plist
```

## 💡 Tips

- **Longer recordings** may take longer to upload (depending on your internet speed)
- **Multiple recordings** are handled automatically - each gets uploaded separately
- **Large files** are uploaded efficiently with optimized chunk sizes
- **Failed uploads** are logged - check `~/logs/obs-backup.log` for details

## 🎉 You're Done!

Your OBS recordings will now automatically upload to Backblaze B2 cloud storage. No more worrying about running out of disk space or losing important recordings!

**Questions?** Check the full `README.md` for advanced configuration options.