#!/bin/bash
# OBS Auto-Upload Setup Script
# This script will install dependencies, configure rclone, and set up the service

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on macOS
check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_error "This script is designed for macOS only"
        exit 1
    fi
}

# Check if Homebrew is installed
check_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        print_error "Homebrew is not installed"
        echo "Please install Homebrew first: https://brew.sh/"
        exit 1
    fi
    print_success "Homebrew is installed"
}

# Install required dependencies
install_dependencies() {
    print_status "Installing dependencies..."
    
    local packages=("rclone" "fswatch")
    local missing_packages=()
    
    # Check which packages are missing
    for package in "${packages[@]}"; do
        if ! brew list "$package" >/dev/null 2>&1; then
            missing_packages+=("$package")
        fi
    done
    
    # Install missing packages
    if [ ${#missing_packages[@]} -gt 0 ]; then
        print_status "Installing: ${missing_packages[*]}"
        brew install "${missing_packages[@]}"
        print_success "Dependencies installed"
    else
        print_success "All dependencies already installed"
    fi
}

# Configure rclone for Backblaze B2
configure_rclone() {
    print_status "Configuring rclone for Backblaze B2..."
    
    # Check if b2-remote already exists
    if rclone listremotes | grep -q "^b2-remote:$"; then
        print_warning "rclone remote 'b2-remote' already exists"
        read -p "Do you want to reconfigure it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Skipping rclone configuration"
            return
        fi
    fi
    
    echo
    print_status "You'll need your Backblaze B2 credentials:"
    echo "1. Go to https://secure.backblaze.com/b2_buckets.htm"
    echo "2. Create an Application Key with read/write access"
    echo "3. Note down your Application Key ID and Application Key"
    echo
    
    read -p "Press Enter when you have your credentials ready..."
    
    # Run rclone config
    echo
    print_status "Running rclone config..."
    echo "When prompted:"
    echo "- Choose 'n' for new remote"
    echo "- Name: b2-remote"
    echo "- Storage type: Choose 'Backblaze B2'"
    echo "- Enter your Application Key ID and Application Key"
    echo "- Accept defaults for other options"
    echo
    
    rclone config
    
    # Verify configuration
    if rclone listremotes | grep -q "^b2-remote:$"; then
        print_success "rclone configured successfully"
    else
        print_error "rclone configuration failed"
        exit 1
    fi
}

# Test rclone connection
test_rclone() {
    print_status "Testing rclone connection..."
    
    # Get bucket name from user
    read -p "Enter your Backblaze B2 bucket name: " bucket_name
    
    if [ -z "$bucket_name" ]; then
        print_error "Bucket name cannot be empty"
        exit 1
    fi
    
    # Test connection
    if rclone lsd "b2-remote:$bucket_name" >/dev/null 2>&1; then
        print_success "Connection to bucket '$bucket_name' successful"
        echo "BUCKET_NAME=\"$bucket_name\"" >> "$SCRIPT_DIR/.env"
    else
        print_error "Cannot connect to bucket '$bucket_name'"
        print_error "Please check your bucket name and rclone configuration"
        exit 1
    fi
}

# Create .env file
create_env_file() {
    print_status "Creating .env configuration file..."
    
    if [ -f "$SCRIPT_DIR/.env" ]; then
        print_warning ".env file already exists"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Keeping existing .env file"
            return
        fi
    fi
    
    # Copy from example
    cp "$SCRIPT_DIR/env.example" "$SCRIPT_DIR/.env"
    
    # Update with user-specific values
    sed -i '' 's|WATCH_DIR="/Users/yourusername/Movies/OBS"|WATCH_DIR="'"$HOME"'/Movies/OBS"|g' "$SCRIPT_DIR/.env"
    sed -i '' 's|LOG_FILE="$HOME/logs/obs-backup.log"|LOG_FILE="'"$HOME"'/logs/obs-backup.log"|g' "$SCRIPT_DIR/.env"
    
    print_success ".env file created"
    print_status "Please edit .env file to customize your settings"
}

# Create directories
create_directories() {
    print_status "Creating necessary directories..."
    
    # Create logs directory
    mkdir -p "$HOME/logs"
    
    # Create OBS directory if it doesn't exist
    if [ ! -d "$HOME/Movies/OBS" ]; then
        mkdir -p "$HOME/Movies/OBS"
        print_success "Created OBS directory: $HOME/Movies/OBS"
    fi
    
    print_success "Directories created"
}

# Make script executable
make_executable() {
    print_status "Making script executable..."
    chmod +x "$SCRIPT_DIR/obs-auto-upload.sh"
    print_success "Script is now executable"
}

# Create launch agent for auto-start
create_launch_agent() {
    print_status "Setting up auto-start service..."
    
    local plist_file="$HOME/Library/LaunchAgents/com.user.obs-auto-upload.plist"
    
    if [ -f "$plist_file" ]; then
        print_warning "Launch agent already exists"
        read -p "Do you want to replace it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Keeping existing launch agent"
            return
        fi
        
        # Unload existing service
        launchctl unload "$plist_file" 2>/dev/null || true
    fi
    
    # Create launch agent directory
    mkdir -p "$HOME/Library/LaunchAgents"
    
    # Create plist file
    cat > "$plist_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.obs-auto-upload</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/obs-auto-upload.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/logs/obs-auto-upload.out</string>
    <key>StandardErrorPath</key>
    <string>$HOME/logs/obs-auto-upload.err</string>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
</dict>
</plist>
EOF
    
    print_success "Launch agent created"
    
    # Ask if user wants to start the service now
    read -p "Do you want to start the service now? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        launchctl load "$plist_file"
        print_success "Service started"
    else
        print_status "Service not started. You can start it later with:"
        echo "  launchctl load $plist_file"
    fi
}

# Test the setup
test_setup() {
    print_status "Testing setup..."
    
    # Check if script can run without errors
    if "$SCRIPT_DIR/obs-auto-upload.sh" --help >/dev/null 2>&1; then
        print_error "Script test failed"
        return 1
    fi
    
    # Check if .env file is properly configured
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        print_error ".env file not found"
        return 1
    fi
    
    # Source .env and check required variables
    source "$SCRIPT_DIR/.env"
    
    local required_vars=("REMOTE_NAME" "BUCKET_NAME" "WATCH_DIR" "REMOTE_BASE_PATH")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            print_error "Required variable $var is not set in .env file"
            return 1
        fi
    done
    
    print_success "Setup test passed"
}

# Show usage instructions
show_usage() {
    echo
    print_success "Setup completed successfully!"
    echo
    echo "Next steps:"
    echo "1. Edit the .env file to customize your settings:"
    echo "   nano $SCRIPT_DIR/.env"
    echo
    echo "2. Test the script manually:"
    echo "   $SCRIPT_DIR/obs-auto-upload.sh"
    echo
    echo "3. Monitor the logs:"
    echo "   tail -f $HOME/logs/obs-backup.log"
    echo
    echo "4. Service management:"
    echo "   Start:  launchctl load $HOME/Library/LaunchAgents/com.user.obs-auto-upload.plist"
    echo "   Stop:   launchctl unload $HOME/Library/LaunchAgents/com.user.obs-auto-upload.plist"
    echo "   Status: launchctl list | grep obs-auto-upload"
    echo
    echo "5. View service logs:"
    echo "   tail -f $HOME/logs/obs-auto-upload.out"
    echo "   tail -f $HOME/logs/obs-auto-upload.err"
    echo
}

# Main setup function
main() {
    echo "=== OBS Auto-Upload Setup ==="
    echo
    
    check_macos
    check_homebrew
    install_dependencies
    configure_rclone
    test_rclone
    create_env_file
    create_directories
    make_executable
    
    # Ask about auto-start
    echo
    read -p "Do you want to set up auto-start on login? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        create_launch_agent
    fi
    
    # Test setup
    if test_setup; then
        show_usage
    else
        print_error "Setup test failed. Please check the configuration and try again."
        exit 1
    fi
}

# Run main function
main "$@" 