#!/opt/homebrew/bin/bash
# OBS to Backblaze B2 Auto-Upload Script
# Monitors OBS recordings and automatically uploads them to Backblaze B2

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
else
    echo "ERROR: .env file not found. Copy env.example to .env and configure it."
    exit 1
fi

# Validate required variables
required_vars=(
    "REMOTE_NAME"
    "BUCKET_NAME"
    "WATCH_DIR"
    "REMOTE_BASE_PATH"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Required variable $var is not set in .env file"
        exit 1
    fi
done

# Set defaults for optional variables
EXTENSIONS="${EXTENSIONS:-mkv}"
MIN_FILE_SIZE_MB="${MIN_FILE_SIZE_MB:-1}"
STABILITY_TIMEOUT="${STABILITY_TIMEOUT:-45}"
MAX_WAIT_TIME="${MAX_WAIT_TIME:-7200}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
ENABLE_UPLOAD_CONFIRMATION="${ENABLE_UPLOAD_CONFIRMATION:-false}"
CONFIRMATION_DELAY_SECONDS="${CONFIRMATION_DELAY_SECONDS:-60}"
UPLOAD_TRANSFERS="${UPLOAD_TRANSFERS:-6}"
UPLOAD_CHECKERS="${UPLOAD_CHECKERS:-8}"
CHUNK_SIZE="${CHUNK_SIZE:-50M}"
BANDWIDTH_LIMIT="${BANDWIDTH_LIMIT:-18M}"
DELETE_AFTER_UPLOAD="${DELETE_AFTER_UPLOAD:-true}"
VERIFY_UPLOAD="${VERIFY_UPLOAD:-true}"
OVERWRITE_REMOTE="${OVERWRITE_REMOTE:-true}"
ENABLE_NOTIFICATIONS="${ENABLE_NOTIFICATIONS:-true}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
LOG_FILE="${LOG_FILE:-$HOME/logs/obs-backup.log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Normalize REMOTE_BASE_PATH (ensure it has trailing slash and no leading slash)
REMOTE_BASE_PATH="${REMOTE_BASE_PATH#/}"  # Remove leading slash
REMOTE_BASE_PATH="${REMOTE_BASE_PATH%/}/" # Ensure trailing slash

# Track file states
declare -A file_last_modified
declare -A file_first_seen
declare -A file_sizes

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log levels: DEBUG=0, INFO=1, WARNING=2, ERROR=3
    local log_levels=( "DEBUG" "INFO" "WARNING" "ERROR" )
    local current_level=1  # Default to INFO
    local message_level=1
    
    # Set current log level
    case "$LOG_LEVEL" in
        "DEBUG") current_level=0 ;;
        "INFO") current_level=1 ;;
        "WARNING") current_level=2 ;;
        "ERROR") current_level=3 ;;
    esac
    
    # Set message level
    case "$level" in
        "DEBUG") message_level=0 ;;
        "INFO") message_level=1 ;;
        "WARNING") message_level=2 ;;
        "ERROR") message_level=3 ;;
    esac
    
    # Only log if message level >= current level
    if [ $message_level -ge $current_level ]; then
        echo "$timestamp [$level] $message" | tee -a "$LOG_FILE"
    fi
}

# Notification function
send_notification() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"
    
    if [ "$ENABLE_NOTIFICATIONS" = "true" ]; then
        # macOS notification
        osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
        
        # Optional: ntfy notification
        if [ -n "$NTFY_TOPIC" ]; then
            local priority="3"  # default
            case "$urgency" in
                "critical") priority="4" ;;
                "high") priority="4" ;;
                "normal") priority="3" ;;
                "low") priority="2" ;;
            esac
            
            curl -s -d "$message" \
                -H "Title: $title" \
                -H "Priority: $priority" \
                "$NTFY_TOPIC" >/dev/null 2>&1 || true
        fi
    fi
}

# Upload confirmation function with macOS notification and dialog choice
prompt_upload_confirmation() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    local size_bytes=$(get_file_size "$file_path")
    local size_formatted=$(format_file_size "$size_bytes")
    local delay_seconds="$CONFIRMATION_DELAY_SECONDS"
    
    log_message "INFO" "Showing upload confirmation for: $filename ($size_formatted)"
    
    # Show notification first to inform user
    send_notification "🎥 OBS Recording Ready" "$filename ($size_formatted) - Upload starting in $delay_seconds seconds"
    
    # Create AppleScript that shows a dialog with choice after a brief delay
    local applescript="
    tell application \"System Events\"
        try
            -- Brief delay to let user see the notification
            delay 2
            
            -- Show dialog with choice buttons
            set dialogResult to display dialog \"Upload $filename ($size_formatted) to cloud storage?\" ¬
                with title \"🎥 OBS Upload Confirmation\" ¬
                buttons {\"Cancel\", \"Upload\"} ¬
                default button \"Upload\" ¬
                with icon note ¬
                giving up after ($delay_seconds - 2)
            
            -- Check the result
            if button returned of dialogResult is \"Cancel\" then
                return \"cancelled\"
            else if button returned of dialogResult is \"Upload\" then
                return \"proceed\"
            else
                -- Dialog timed out (gave up), proceed with upload
                return \"proceed\"
            end if
            
        on error errMsg
            -- If dialog fails or is cancelled, default to proceed
            return \"proceed\"
        end try
    end tell
    "
    
    # Run the AppleScript and get the result
    local result=$(echo "$applescript" | osascript 2>/dev/null || echo "proceed")
    
    case "$result" in
        "cancelled")
            log_message "INFO" "User cancelled upload: $filename"
            send_notification "Upload Cancelled" "Kept local: $filename"
            return 1  # Don't upload
            ;;
        *)
            log_message "INFO" "Upload confirmed (timeout or user approval): $filename"
            return 0  # Proceed with upload
            ;;
    esac
}

# File size functions
get_file_size() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        stat -f%z "$file_path" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

get_file_size_mb() {
    local size_bytes=$(get_file_size "$1")
    echo $((size_bytes / 1024 / 1024))
}

format_file_size() {
    local size_bytes="$1"
    local size_mb=$((size_bytes / 1024 / 1024))
    
    if [ $size_mb -gt 1024 ]; then
        local size_gb=$((size_mb / 1024))
        echo "${size_gb}GB"
    else
        echo "${size_mb}MB"
    fi
}

# File stability detection
is_file_stable() {
    local file_path="$1"
    local current_time=$(date +%s)
    local current_size=$(get_file_size "$file_path")
    local last_modified=${file_last_modified[$file_path]:-0}
    local first_seen=${file_first_seen[$file_path]:-$current_time}
    local last_size=${file_sizes[$file_path]:-0}
    
    # Update tracking info
    file_sizes[$file_path]=$current_size
    
    # Check minimum file size
    local size_mb=$(get_file_size_mb "$file_path")
    if [ $size_mb -lt $MIN_FILE_SIZE_MB ]; then
        log_message "DEBUG" "File too small: $(basename "$file_path") - ${size_mb}MB < ${MIN_FILE_SIZE_MB}MB"
        return 1
    fi
    
    # Check if file size changed
    if [ "$current_size" != "$last_size" ]; then
        file_last_modified[$file_path]=$current_time
        log_message "INFO" "File growing: $(basename "$file_path") - $(format_file_size "$current_size")"
        return 1
    fi
    
    # Check if enough time has passed since last change
    local time_since_change=$((current_time - last_modified))
    local total_wait_time=$((current_time - first_seen))
    
    if [ $time_since_change -ge $STABILITY_TIMEOUT ]; then
        log_message "INFO" "File stable: $(basename "$file_path") - $(format_file_size "$current_size")"
        return 0
    elif [ $total_wait_time -ge $MAX_WAIT_TIME ]; then
        log_message "WARNING" "Max wait time reached: $(basename "$file_path") - uploading anyway"
        return 0
    else
        local remaining=$((STABILITY_TIMEOUT - time_since_change))
        log_message "DEBUG" "Waiting for stability: $(basename "$file_path") - ${remaining}s remaining"
        return 1
    fi
}

# Upload verification
verify_remote_file() {
    local local_file="$1"
    local filename=$(basename "$local_file")
    local remote_path="$REMOTE_NAME:$BUCKET_NAME/$REMOTE_BASE_PATH$filename"
    
    log_message "INFO" "Verifying upload: $filename"
    
    # Check if file exists remotely and get info
    local remote_info
    if remote_info=$(rclone lsjson "$remote_path" 2>/dev/null); then
        local local_size=$(get_file_size "$local_file")
        local remote_size=$(echo "$remote_info" | grep -o '"Size":[0-9]*' | cut -d':' -f2 | head -1)
        
        if [ "$local_size" = "$remote_size" ] && [ "$remote_size" -gt 0 ]; then
            log_message "INFO" "Upload verified: $filename ($(format_file_size "$local_size"))"
            return 0
        else
            log_message "ERROR" "Verification failed: $filename - Local: $(format_file_size "$local_size"), Remote: $(format_file_size "$remote_size")"
            return 1
        fi
    else
        log_message "ERROR" "Verification failed: $filename not found remotely"
        return 1
    fi
}

# Upload function
upload_file() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    local file_ext="${filename##*.}"
    
    # Check file extension
    if [[ " $EXTENSIONS " =~ " $file_ext " ]]; then
        local size_bytes=$(get_file_size "$file_path")
        local size_formatted=$(format_file_size "$size_bytes")
        
        log_message "INFO" "Starting upload: $filename ($size_formatted)"
        
        # Build rclone command arguments
        local rclone_args=(
            "copy"
            "$file_path"
            "$REMOTE_NAME:$BUCKET_NAME/$REMOTE_BASE_PATH"
            "--progress"
            "--transfers" "$UPLOAD_TRANSFERS"
            "--checkers" "$UPLOAD_CHECKERS"
            "--retries" "3"
            "--b2-chunk-size" "$CHUNK_SIZE"
            "--bwlimit" "$BANDWIDTH_LIMIT"
            "--stats" "30s"
            "--stats-one-line"
            "--log-level" "INFO"
            "--log-file" "$LOG_FILE"
        )
        
        # Add overwrite flag if enabled
        if [ "$OVERWRITE_REMOTE" = "true" ]; then
            rclone_args+=("--ignore-times")
        fi
        
        # Send start notification
        send_notification "OBS Upload Started" "Uploading: $filename ($size_formatted)"
        
        # Execute upload
        local start_time=$(date +%s)
        if rclone "${rclone_args[@]}"; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            local duration_formatted=$(printf "%02d:%02d" $((duration / 60)) $((duration % 60)))
            
            log_message "INFO" "Upload completed: $filename in ${duration_formatted}"
            
            # Handle post-upload actions
            local upload_success=true
            
            # Verify upload if enabled
            if [ "$VERIFY_UPLOAD" = "true" ]; then
                if ! verify_remote_file "$file_path"; then
                    upload_success=false
                    send_notification "OBS Upload Failed" "Verification failed: $filename" "critical"
                fi
            fi
            
            # Delete local file if upload was successful
            if [ "$upload_success" = "true" ] && [ "$DELETE_AFTER_UPLOAD" = "true" ]; then
                if rm "$file_path" 2>/dev/null; then
                    log_message "INFO" "Local file deleted: $filename"
                    send_notification "OBS Upload Complete" "Uploaded and deleted: $filename ($size_formatted)"
                else
                    log_message "ERROR" "Failed to delete local file: $filename"
                    send_notification "OBS Upload Warning" "Uploaded but failed to delete: $filename" "critical"
                fi
            elif [ "$upload_success" = "true" ]; then
                send_notification "OBS Upload Complete" "Uploaded: $filename ($size_formatted)"
            fi
            
            # Clean up tracking
            unset file_last_modified[$file_path]
            unset file_first_seen[$file_path]
            unset file_sizes[$file_path]
            
        else
            local exit_code=$?
            log_message "ERROR" "Upload failed: $filename (exit code: $exit_code)"
            send_notification "OBS Upload Failed" "Failed to upload: $filename" "critical"
        fi
    else
        log_message "DEBUG" "Skipping file with unsupported extension: $filename"
    fi
}

# File event handler
handle_file_event() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    local file_ext="${filename##*.}"
    
    log_message "DEBUG" "File event received: $file_path (ext: $file_ext)"
    
    # Only process files with correct extensions
    if [ -f "$file_path" ] && [[ " $EXTENSIONS " =~ " $file_ext " ]]; then
        local current_time=$(date +%s)
        
        # Initialize tracking if new file
        if [ -z "${file_first_seen[$file_path]:-}" ]; then
            file_first_seen[$file_path]=$current_time
            file_last_modified[$file_path]=$current_time
            file_sizes[$file_path]=$(get_file_size "$file_path")
            
            log_message "INFO" "New OBS recording detected: $filename"
            send_notification "OBS Recording Detected" "Monitoring: $filename"
            
            # Start a background process to handle this specific file's stability and upload
            (
                sleep 5  # Give file a moment to settle
                while true; do
                    if [ -f "$file_path" ]; then
                        if is_file_stable "$file_path"; then
                            log_message "INFO" "File is stable: $filename"
                            
                            # Check if upload confirmation is enabled
                            if [ "$ENABLE_UPLOAD_CONFIRMATION" = "true" ]; then
                                if prompt_upload_confirmation "$file_path"; then
                                    log_message "INFO" "Starting upload: $filename"
                                    upload_file "$file_path"
                                else
                                    log_message "INFO" "Upload cancelled by user: $filename"
                                fi
                            else
                                # Original behavior - auto upload
                                log_message "INFO" "Starting upload: $filename"
                                upload_file "$file_path"
                            fi
                            break
                        fi
                    else
                        log_message "DEBUG" "File no longer exists: $filename"
                        break
                    fi
                    sleep $CHECK_INTERVAL
                done
            ) &
        fi
    fi
}

# Configuration validation
validate_config() {
    log_message "INFO" "Validating configuration..."
    
    # Check if required tools are installed
    local missing_tools=()
    
    if ! command -v rclone >/dev/null 2>&1; then
        missing_tools+=("rclone")
    fi
    
    if ! command -v fswatch >/dev/null 2>&1; then
        missing_tools+=("fswatch")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_message "ERROR" "Missing required tools: ${missing_tools[*]}"
        log_message "ERROR" "Install with: brew install ${missing_tools[*]}"
        exit 1
    fi
    
    # Check if rclone remote exists
    if ! rclone listremotes | grep -q "^${REMOTE_NAME}:$"; then
        log_message "ERROR" "rclone remote '$REMOTE_NAME' not found"
        log_message "ERROR" "Run 'rclone config' to set up Backblaze B2 remote"
        exit 1
    fi
    
    # Check if watch directory exists
    if [ ! -d "$WATCH_DIR" ]; then
        log_message "ERROR" "Watch directory does not exist: $WATCH_DIR"
        exit 1
    fi
    
    # Test remote connection
    if ! rclone lsd "$REMOTE_NAME:$BUCKET_NAME" >/dev/null 2>&1; then
        log_message "ERROR" "Cannot access bucket '$BUCKET_NAME' on remote '$REMOTE_NAME'"
        log_message "ERROR" "Check your bucket name and rclone configuration"
        exit 1
    fi
    
    # Create remote directory if it doesn't exist
    rclone mkdir "$REMOTE_NAME:$BUCKET_NAME/$REMOTE_BASE_PATH" 2>/dev/null || true
    
    log_message "INFO" "Configuration validation passed"
}

# Global variables for process management
FSWATCH_PID=""
CLEANUP_DONE=false

# Enhanced cleanup function with proper process management
cleanup() {
    if [ "$CLEANUP_DONE" = "true" ]; then
        return
    fi
    CLEANUP_DONE=true
    
    log_message "INFO" "Shutting down OBS auto-upload..."
    
    # Kill fswatch process if running
    if [ -n "$FSWATCH_PID" ] && kill -0 "$FSWATCH_PID" 2>/dev/null; then
        log_message "DEBUG" "Stopping fswatch process (PID: $FSWATCH_PID)"
        kill -TERM "$FSWATCH_PID" 2>/dev/null
        sleep 2
        if kill -0 "$FSWATCH_PID" 2>/dev/null; then
            kill -KILL "$FSWATCH_PID" 2>/dev/null || true
        fi
        wait "$FSWATCH_PID" 2>/dev/null || true
    fi
    
    pkill -f "fswatch.*$WATCH_DIR" 2>/dev/null || true
    
    send_notification "OBS Auto-Upload Stopped" "Service has been stopped"
    exit 0
}

# File system monitor
start_file_monitor() {
    log_message "INFO" "Starting file system monitor..."
    
    while IFS= read -r -d '' filepath; do
        log_message "DEBUG" "Raw fswatch event: '$filepath'"
        
        if [[ -f "$filepath" ]]; then
            local filename=$(basename "$filepath")
            local file_ext="${filename##*.}"
            
            if [[ "$filepath" == "$WATCH_DIR"/* ]] && [[ " $EXTENSIONS " =~ " $file_ext " ]]; then
                log_message "INFO" "New file detected: $filename"
                handle_file_event "$filepath"
            fi
        fi
    done < <(
        exec fswatch -0 -r \
            --event=Created \
            --event=MovedTo \
            --latency=1.0 \
            "$WATCH_DIR" 2>/dev/null
    )
    
    log_message "ERROR" "File system monitor exited unexpectedly"
}

# Main execution
main() {
    log_message "INFO" "=== OBS to B2 Auto-Upload Started ==="
    log_message "INFO" "Watch directory: $WATCH_DIR"
    log_message "INFO" "Remote target: $REMOTE_NAME:$BUCKET_NAME/$REMOTE_BASE_PATH"
    log_message "INFO" "File extensions: $EXTENSIONS"
    log_message "INFO" "Delete after upload: $DELETE_AFTER_UPLOAD"
    log_message "INFO" "Verify uploads: $VERIFY_UPLOAD"
    log_message "INFO" "Stability timeout: ${STABILITY_TIMEOUT}s"
    
    # Validate configuration
    validate_config
    
    # Enhanced signal handling - catch all relevant signals
    trap cleanup EXIT INT TERM HUP
    
    # Send startup notification
    send_notification "OBS Auto-Upload Started" "Monitoring: $WATCH_DIR"
    
    # Start the file monitor
    log_message "INFO" "Starting file system monitor..."
    start_file_monitor
    
    # If we reach here, the monitor exited unexpectedly
    log_message "ERROR" "File monitor exited, shutting down service"
    cleanup
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi