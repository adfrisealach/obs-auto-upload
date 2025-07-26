# Upload Confirmation Feature Implementation

## Original Requirements (What We Agreed On)

### User Experience Flow
1. **OBS finishes recording** → User continues working normally
2. **macOS notification appears** in the top-right corner:
   ```
   🎥 OBS Recording Ready
   video-2024-01-15.mkv (2.3GB)
   Uploading in 60 seconds...
   [Cancel Upload]
   ```
3. **Two scenarios:**
   - **Do nothing** → File uploads automatically after countdown
   - **Click "Cancel Upload" button** → Upload stops, file stays local

### Key Requirements
- ✅ **Single notification per file** - No chain of notifications
- ❌ **macOS notification with clickable cancel button** - NOT IMPLEMENTED
- ✅ **Static countdown timer** - No real-time updates needed
- ❌ **Simple yes/no decision** - NOT IMPLEMENTED
- ✅ **Unobtrusive** - Doesn't interrupt user's work

## Current Implementation (What Was Actually Built)

### What Works
- ✅ Configuration options added (`ENABLE_UPLOAD_CONFIRMATION`, `CONFIRMATION_DELAY_SECONDS`)
- ✅ Integration into file stability workflow
- ✅ Single notification per file (no spam)
- ✅ Timeout behavior (proceeds after delay)

### What's Wrong
- ❌ **Terminal-based confirmation** instead of macOS notification
- ❌ **Manual file creation** (`/tmp/obs_upload_cancel_[PID]`) to cancel
- ❌ **Ctrl+C requirement** - user must monitor terminal
- ❌ **No clickable cancel button** in notification

### Current User Experience
```
Terminal Output:
"Waiting for user response for 10 seconds...
To cancel upload, create file: /tmp/obs_upload_cancel_97286
Press Ctrl+C in this terminal to cancel upload"
```

## Required Fix

### Target Implementation
Replace the current `prompt_upload_confirmation()` function with:

1. **macOS Notification with Action Button**
   ```applescript
   display notification "video.mkv (2.3GB) will upload in 60 seconds" 
   with title "OBS Recording Ready" 
   subtitle "Click to cancel upload"
   ```

2. **AppleScript Action Handler**
   - User clicks notification → Cancel upload
   - User ignores notification → Proceed with upload after timeout

3. **No Terminal Interaction Required**
   - Script runs in background
   - User doesn't need to monitor terminal
   - Pure notification-based interaction

### Technical Approach
- Use AppleScript `display notification` with action buttons
- Implement notification click detection
- Remove terminal-based prompts
- Remove manual file creation requirements

## Files to Modify

1. **obs-auto-upload.sh**
   - Replace `prompt_upload_confirmation()` function
   - Remove terminal output for confirmation
   - Implement AppleScript notification with action

2. **README.md**
   - Update documentation to reflect notification-based approach
   - Remove references to terminal interaction and file creation

3. **Test the implementation**
   - Verify notification appears
   - Verify cancel button works
   - Verify timeout behavior works

## Success Criteria

- [ ] macOS notification appears when file is ready
- [ ] Notification shows file name, size, and countdown
- [ ] Notification has clickable "Cancel Upload" button
- [ ] Clicking cancel button stops upload and keeps file local
- [ ] Ignoring notification proceeds with upload after timeout
- [ ] No terminal interaction required
- [ ] Works when script runs as background service

## Risk Assessment

**Low Risk** - This is a UI change to an existing working feature. The core logic (file detection, stability, upload) remains unchanged. 