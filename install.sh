#!/bin/bash

#TODO run this on the raspberry pi and see what happens, might not work at all

# --- Configuration Variables ---
# Default values for your setup. These will be prompted for, but set good defaults.
HAMLIB_MODEL_DEFAULT="903"                # For SPID ROT2 protocol
SERIAL_PORT_DEFAULT="/dev/ttyUSB0"        # Common USB serial port
BAUD_RATE_DEFAULT="9600"                  # Common baud rate
ROTCTLD_PORT_DEFAULT="4533"               # Standard Hamlib rotctld port
GPREDICT_INSTALL_PATH="/usr/bin/gpredict" # Standard path for apt-installed gpredict

# --- Colors for Output ---
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Helper Functions ---
function check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: '$1' command not found. Please install it manually or check your PATH.${NC}"
        exit 1
    fi
}

function prompt_for_continue() {
    echo ""
    read -p "$(echo -e ${YELLOW}Press Enter to continue, or Ctrl+C to exit.${NC})"
}

function run_sudo_command() {
    echo ""
    echo -e "${GREEN}Running: sudo $@${NC}"
    sudo "$@"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Command failed. Exiting.${NC}"
        exit 1
    fi
}

function install_package() {
    PACKAGE="$1"
    if dpkg -s "$PACKAGE" &>/dev/null; then
        echo -e "${YELLOW}$PACKAGE is already installed. Skipping.${NC}"
    else
        echo -e "${GREEN}Installing $PACKAGE...${NC}"
        run_sudo_command apt install -y "$PACKAGE"
    fi
}

function user_is_in_group() {
    groups $USER | grep -q "$1"
}

# --- Script Start ---
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}  Gpredict Rotator Setup Automation Script          ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo ""
echo -e "${YELLOW}This script will guide you through the setup process. It requires manual steps.${NC}"
echo -e "${YELLOW}Please read all prompts carefully.${NC}"
prompt_for_continue

# --- PART 1: Initial Gpredict and Hamlib Installation ---
echo -e "${GREEN}--- PART 1: Initial Gpredict and Hamlib Installation ---${NC}"

echo -e "${GREEN}Updating package lists...${NC}"
run_sudo_command apt update

install_package "gpredict"
install_package "libhamlib-utils"

echo -e "${GREEN}Gpredict and Hamlib utilities installed.${NC}"
echo ""

# --- PART 2: Serial Port Identification & User Permissions ---
echo -e "${GREEN}--- PART 2: Serial Port Identification & User Permissions ---${NC}"

# Identify Serial Port
echo -e "${YELLOW}Please ensure your MD-03 rotator's USB cable is currently ${RED}UNPLUGGED${YELLOW} from the computer.${NC}"
prompt_for_continue

echo -e "${GREEN}Monitoring kernel messages. Now, please ${YELLOW}PLUG IN${GREEN} your MD-03 rotator's USB cable.${NC}"
echo -e "${GREEN}Look for a line indicating 'ttyUSB' or 'ttyACM', like 'ttyUSB0'.${NC}"
echo -e "${YELLOW}(Press Ctrl+C when you've identified the port. You may need to scroll up slightly).${NC}"
run_sudo_command dmesg -w

read -p "$(echo -e ${YELLOW}Enter the identified serial port (e.g., /dev/ttyUSB0): ${NC})" SERIAL_PORT
SERIAL_PORT=${SERIAL_PORT:-$SERIAL_PORT_DEFAULT} # Use default if empty

echo "Detected serial port: $SERIAL_PORT"
echo ""

# Check and Add User to dialout group
echo -e "${GREEN}Checking user group membership for '$USER'...${NC}"
if user_is_in_group "dialout"; then
    echo -e "${YELLOW}User '$USER' is already in the 'dialout' group. Skipping.${NC}"
else
    echo -e "${GREEN}Adding user '$USER' to the 'dialout' group...${NC}"
    run_sudo_command usermod -a -G dialout "$USER"
    echo -e "${GREEN}User '$USER' has been added to the 'dialout' group.${NC}"
    echo -e "${RED}=======================================================================${NC}"
    echo -e "${RED}  CRITICAL MANUAL STEP REQUIRED!                                       ${NC}"
    echo -e "${RED}  You MUST log out of your Ubuntu session and log back in (or reboot)  ${NC}"
    echo -e "${RED}  for the group changes to take effect and access the serial port.     ${NC}"
    echo -e "${RED}=======================================================================${NC}"
    echo -e "${YELLOW}After logging back in, please re-run this script to continue.${NC}"
    exit 0 # Exit here, user needs to re-run
fi

echo -e "${GREEN}Serial port identified and user permissions confirmed.${NC}"
prompt_for_continue

# --- PART 3: Testing Hamlib Communication with rotctl ---
echo -e "${GREEN}--- PART 3: Testing Hamlib Communication with rotctl ---${NC}"

echo -e "${YELLOW}Before proceeding, please ensure your MD-03 controller's 'PROT. AE:' setting is set to 'SPID ROT2'.${NC}"
echo -e "${YELLOW}Refer to your MD-03 manual for how to change this setting.${NC}"
prompt_for_continue

echo -e "${GREEN}Finding Hamlib model ID for SPID rotators...${NC}"
rotctl -l | grep -i spid
echo -e "${YELLOW}From the list above, confirm the model ID for 'SPID MD-01/02 (ROT2 mode)'. (It's usually 903).${NC}"
read -p "$(echo -e ${YELLOW}Enter the Hamlib model ID: ${NC})" HAMLIB_MODEL
HAMLIB_MODEL=${HAMLIB_MODEL:-$HAMLIB_MODEL_DEFAULT}

echo -e "${GREEN}Now, let's test communication with your rotator.${NC}"
echo -e "${YELLOW}Run the following command in a NEW terminal and check if you get the 'Rotator command:' prompt and if 'p' (lowercase) returns valid Az/El readings.${NC}"
echo -e "${YELLOW}Command to run: ${NC}${GREEN}/usr/bin/rotctl -m $HAMLIB_MODEL -r $SERIAL_PORT -s $BAUD_RATE -v${NC}"
echo -e "${YELLOW}Also, confirm that sending 'P 10 10' moves the rotator and the controller's display matches (or is off by a consistent amount, which you fixed by setting to 'immediate' start/stop).${NC}"
echo -e "${YELLOW}Type 'q' to quit that rotctl session after testing.${NC}"
prompt_for_continue

read -p "$(echo -e ${YELLOW}Did the rotctl test succeed (rotator responded and moved)? (y/n): ${NC})" test_success
if [[ ! "$test_success" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Rotctl test failed. Please re-check MD-03 settings, USB connection, and serial port permissions. Exiting.${NC}"
    exit 1
fi

echo -e "${GREEN}Hamlib communication confirmed!${NC}"
prompt_for_continue

# --- PART 4: Configure Gpredict for Network Rotator Daemon ---
echo -e "${GREEN}--- PART 4: Configure Gpredict for Network Rotator Daemon ---${NC}"

echo -e "${GREEN}Starting rotctld daemon in the background for Gpredict configuration...${NC}"
/usr/bin/rotctld -m "$HAMLIB_MODEL" -r "$SERIAL_PORT" -s "$BAUD_RATE" -T 127.0.0.1 -t "$ROTCTLD_PORT" > /dev/null 2>&1 &
ROTCTLD_PID=$! # Store PID to kill it later

echo -e "${YELLOW}Now, please open Gpredict GUI and configure the rotator interface:${NC}"
echo -e "  1. Launch Gpredict."
echo -e "  2. Go to ${YELLOW}Edit > Preferences > Interfaces${NC} tab."
echo -e "  3. In the 'Rotators' section, click ${YELLOW}'New'${NC}."
echo -e "  4. For 'Rotator Type', select ${YELLOW}'Hamlib Net rotator'${NC} (or similar network option)."
echo -e "  5. Click ${YELLOW}'Configure'${NC}."
echo -e "  6. Set ${YELLOW}'Host:' to '127.0.0.1'${NC} and ${YELLOW}'Port:' to '$ROTCTLD_PORT'${NC}."
echo -e "  7. ${RED}ENSURE 'Start daemon' is UNCHECKED!${NC} (We're running it manually/via script)."
echo -e "  8. Click 'OK' to save."
echo -e "  9. Go to the ${YELLOW}Antennas${NC} tab."
echo -e " 10. Select your antenna and set its 'Rotator' dropdown to the new ${YELLOW}'Hamlib Net rotator'${NC}."
echo -e " 11. Click 'OK' to close Preferences."
echo -e " 12. ${YELLOW}Close Gpredict after configuration.${NC}"
prompt_for_continue

# Kill the background rotctld process now that Gpredict is configured
if ps -p $ROTCTLD_PID > /dev/null; then
    echo -e "${GREEN}Stopping temporary rotctld daemon (PID: $ROTCTLD_PID)...${NC}"
    kill "$ROTCTLD_PID"
else
    echo -e "${YELLOW}Temporary rotctld daemon already stopped or not found.${NC}"
fi

echo -e "${GREEN}Gpredict configured for network rotator control.${NC}"
prompt_for_continue

# --- PART 5: Create Startup/Shutdown Scripts ---
echo -e "${GREEN}--- PART 5: Creating Startup/Shutdown Scripts ---${NC}"

# Create start_gpredict_rotator.sh
echo -e "${GREEN}Creating 'start_gpredict_rotator.sh' script...${NC}"
cat << EOF > ~/start_gpredict_rotator.sh
#!/bin/bash

# --- Configuration (from setup script) ---
HAMLIB_MODEL="$HAMLIB_MODEL"
SERIAL_PORT="$SERIAL_PORT"
BAUD_RATE="$BAUD_RATE"
ROTCTLD_PORT="$ROTCTLD_PORT"
GPREDICT_PATH="$GPREDICT_INSTALL_PATH"

# --- Start Hamlib Rotator Daemon (rotctld) in background ---
echo "Starting Hamlib rotctld daemon..."
/usr/bin/rotctld -m "\$HAMLIB_MODEL" -r "\$SERIAL_PORT" -s "\$BAUD_RATE" -T 127.0.0.1 -t "\$ROTCTLD_PORT" > /dev/null 2>&1 &
# The '> /dev/null 2>&1 &' part sends output to nowhere and runs in background.

# Give rotctld a moment to start up
sleep 2

# --- Launch Gpredict ---
echo "Launching Gpredict..."
"\$GPREDICT_PATH"

echo "Gpredict closed. To stop rotctld, run 'pkill rotctld' in a terminal."
EOF
chmod +x ~/start_gpredict_rotator.sh
echo -e "${GREEN}Script '~/start_gpredict_rotator.sh' created and made executable.${NC}"

# Create park_rotator.sh
echo -e "${GREEN}Creating 'park_rotator.sh' script...${NC}"
cat << EOF > ~/park_rotator.sh
#!/bin/bash

# --- Configuration (from setup script) ---
ROTCTLD_HOST="127.0.0.1"
ROTCTLD_PORT="$ROTCTLD_PORT"

# --- Desired Park Position (Adjust as needed) ---
PARK_AZIMUTH="0"
PARK_ELEVATION="0"

# --- Send Park Command ---
echo "Attempting to park rotator to Az: \$PARK_AZIMUTH, El: \$PARK_ELEVATION..."

# Try connecting to the running rotctld daemon first
if /usr/bin/rotctl -m 2 -r "\$ROTCTLD_HOST":"\$ROTCTLD_PORT" P "\$PARK_AZIMUTH" "\$PARK_ELEVATION" > /dev/null 2>&1; then
    echo "Successfully sent park command via running rotctld daemon."
else
    # If connection to daemon failed, try directly to serial port (if daemon is not running)
    echo "Rotctld daemon not found or connection failed. Attempting direct serial control..."
    # Ensure these match your direct serial setup
    HAMLIB_MODEL="$HAMLIB_MODEL"
    SERIAL_PORT="$SERIAL_PORT"
    BAUD_RATE="$BAUD_RATE"

    if /usr/bin/rotctl -m "\$HAMLIB_MODEL" -r "\$SERIAL_PORT" -s "\$BAUD_RATE" P "\$PARK_AZIMUTH" "\$PARK_ELEVATION" > /dev/null 2>&1; then
        echo "Successfully sent park command via direct serial."
    else
        echo "Failed to park rotator. Check connections and ensure Hamlib is not in conflict."
        echo "You may need to manually stop rotctld first if it's in an unknown state."
    fi
fi
EOF
chmod +x ~/park_rotator.sh
echo -e "${GREEN}Script '~/park_rotator.sh' created and made executable.${NC}"
echo ""

# --- Final Instructions ---
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}  SETUP COMPLETE!                                   ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}To start Gpredict and your rotator daemon:${NC}"
echo -e "${YELLOW}  Run: ~/start_gpredict_rotator.sh${NC}"
echo -e "${GREEN}When finished, to stop the rotator daemon and/or park the rotator:${NC}"
echo -e "${YELLOW}  Stop daemon: pkill rotctld${NC}"
echo -e "${YELLOW}  Park rotator: ~/park_rotator.sh${NC}"
echo -e "${GREEN}====================================================${NC}"
