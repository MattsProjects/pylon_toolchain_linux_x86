#!/bin/sh

set -e
cd `dirname $0`

# Returns 0 if the user answered no.
# Returns 1 if the user answered yes.
askNoYes() {
    local q="$1 (yes or no [y/n]?) : "
    while true; do
        read -p "$q" yn
        case $yn in
            [Yy]* ) return 1; ;;
            [Nn]* ) return 0; ;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

echo "
Welcome to

########  ##    ## ##        #######  ##    ##
##     ##  ##  ##  ##       ##     ## ###   ##
##     ##   ####   ##       ##     ## ####  ##
########     ##    ##       ##     ## ## ## ##
##           ##    ##       ##     ## ##  ####
##           ##    ##       ##     ## ##   ###
##           ##    ########  #######  ##    ##

This setup configures your system so that you can use Basler USB cameras with it."

if askNoYes "Continue setup?" ; then
    exit 1;
fi

SUDO=""
if [ `id -u` != "0" ] ; then
    if askNoYes "You are not root. I will try to use sudo. Continue?" ; then
        exit 1;
    fi
    SUDO="sudo "
fi

RULES_DIR=/etc/udev/rules.d
RULE_FILE=69-basler-cameras.rules
if [ ! -d "$RULES_DIR" ] ; then
    echo "
Udev rules directory '$RULES_DIR' does not exist. I don't know how to proceed.
You have to manually ensure that the USB camera you want to use is accessible by the user.
Normally, this is done by installing a udev rule like this one:
$(readlink -f $RULE_FILE)
"
    exit 1
fi

echo "
Installing udev rules to $RULES_DIR/$RULE_FILE"
$SUDO cp $RULE_FILE $RULES_DIR

# Install usb.id
# Remove old entry
if [ -f "/usr/share/hwdata/usb.ids" ] ; then
    FILE=/usr/share/hwdata/usb.ids
elif [ -f "/usr/share/usb.ids" ] ; then
    FILE=/usr/share/usb.ids
elif [ -f "/usr/share/misc/usb.ids" ] ; then
    FILE=/usr/share/misc/usb.ids
fi

if [ -f "$FILE" ] ; then
    echo ""
    echo "Checking whether $FILE must be updated"
    LINE_START=`grep -n -m 1 BASLER_START $FILE | cut -d: -f1`
    LINE_END=`grep -n -m 1 BASLER_END $FILE | cut -d: -f1`

    if [ -n "$LINE_START" -a -n "$LINE_END" ] && [ "$LINE_START" -lt "$LINE_END" ] ; then
        echo "Remove old Basler device entries from $FILE"
        cp $FILE usb.ids.old
        $SUDO sed -i -e "$LINE_START,$LINE_END d" $FILE
    fi

    # Test if there are already basler entries in the file.
    FOUND=`grep -e '^2676' $FILE || true`

    if [ -n "$FOUND" ] ; then
        echo "Your USB hardware database is up to date. Nothing to do."
    else
        echo "Add Basler device entries to $FILE"

        # Append the data into usb.ids.

        $SUDO sh -c "echo \"###BASLER_START ###################################################
# These lines were automatically added by the pylon installer.
# Please leave the BASLER_... markers in place as the lines between
# them will be overwritten during the next install.
2676  Basler AG
    ba02  ace USB3 Vision Camera
    ba03  dart USB3 Vision Camera
    ba04  pulse USB3 Vision Camera
    ba05  ace 2 USB3 Vision Camera
    ba06  USB3 Vision Camera
    ba07  USB3 Vision Camera
    ba08  USB3 Vision Camera
    ba09  USB3 Vision Camera
    ba0a  USB3 Vision Camera
    ba0b  USB3 Vision Camera
    ba0c  USB3 Vision Camera
    ba0d  USB3 Vision Camera
    ba0e  USB3 Vision Camera
    ba0f  USB3 Vision Camera
###BASLER_END #####################################################\" >> $FILE"
    fi

else
    echo ""
    echo "Couldn't locate the usb-ids database. This is no big problem. Only the descriptions for Basler devices will be missing when calling lsusb."
fi

echo ""
echo "For a better experience with many USB3 cameras,"
echo "Basler recommends increasing the limit of open files and USB memory."
echo "Warning: The script will have to edit your GRUB configuration file to permanently modify the usbfs memory!"

if ! askNoYes "Should I do that for you?" ; then
    # This is the size in MB which is used to configure the system.
    USBFS_SIZE=1000; # 1000MB

    # Increase open file limit.
    if [ -d  /etc/security/limits.d ] && [ ! -f /etc/security/limits.d/90-pylon-nofile.conf ] ; then
        $SUDO sh -c 'echo "*          soft     nofile         524288" >> /etc/security/limits.d/90-pylon-nofile.conf'
        $SUDO sh -c 'echo "*          hard     nofile         524288" >> /etc/security/limits.d/90-pylon-nofile.conf'
    fi

    # Increase the usbfs_memory_mb memory for the current session.
    if [ -f /sys/module/usbcore/parameters/usbfs_memory_mb ] ; then
        echo "Parameter usbfs_memory_mb in /sys/module/usbcore/parameters changed to $USBFS_SIZE"
        $SUDO sh -c "echo $USBFS_SIZE > /sys/module/usbcore/parameters/usbfs_memory_mb"
    fi

    # !!! Assuming the GRUB bootloader is installed on this system !!!
    # Edit/Add GRUB_CMDLINE_LINUX(_DEFAULT) to permanently modify the usbfs memory.
    if [ -f /etc/default/grub ] ; then
        # Create a backup file of /etc/default/grub
        # in case it doesn't exist.
        $SUDO cp /etc/default/grub /etc/default/grub.pylon.backup.$(date "+%Y.%m.%d-%H.%M.%S")
        if [ -f /etc/default/grub.pylon.backup ] ; then
            $SUDO cp /etc/default/grub.pylon.backup /etc/default/grub
        else
            $SUDO cp /etc/default/grub /etc/default/grub.pylon.backup
        fi

        # Change the parameter GRUB_CMDLINE_LINUX_DEFAULT to make the usbfs_memory permanent.
        if $(grep -q "GRUB_CMDLINE_LINUX_DEFAULT=" "/etc/default/grub"); then
            # Parameter exists. We have to append the new value.
            TMP=$(grep "GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | sed 's/.$//')
            TMP="$TMP quiet splash usbcore.usbfs_memory_mb=$USBFS_SIZE\""
            $SUDO sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*$/$TMP/" /etc/default/grub
        else
            # Parameter doesn't exist. We have to append it to the end of the file.
            TMP="GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash usbcore.usbfs_memory_mb=$USBFS_SIZE\""
            $SUDO sh -c "echo '$TMP' >> /etc/default/grub"
        fi

        # Change the parameter GRUB_CMDLINE_LINUX to make the usbfs_memory permanent.
        if $(grep -q "GRUB_CMDLINE_LINUX=" "/etc/default/grub"); then
            # Parameter exists. We have to append the new values.
            TMP=$(grep "GRUB_CMDLINE_LINUX=" /etc/default/grub | sed 's/.$//')
            TMP="$TMP quiet splash usbcore.usbfs_memory_mb=$USBFS_SIZE\""
            $SUDO sed -i "s/GRUB_CMDLINE_LINUX=.*$/$TMP/" /etc/default/grub
        else
            # Parameter doesn't exist. We have to append it to the end of the file.
            TMP="GRUB_CMDLINE_LINUX=\"quiet splash usbcore.usbfs_memory_mb=$USBFS_SIZE\""
            $SUDO sh -c "echo '$TMP' >> /etc/default/grub"
        fi

        echo "Working with the following data in /etc/default/grub"
        cat /etc/default/grub

        # Update GRUB to create a new grub.cfg.
        if [ -f /sbin/update-grub ] ; then
            echo "Preparing grub.cfg for next boot."
            $SUDO update-grub
            echo "Please reboot system to make the parameter change permanent."
        else
            # Check grub.cfg location.
            if [ -f /etc/os-release ] ; then
                . /etc/os-release
                GRUB_CFG_LOCATION=$($SUDO find /boot/efi/EFI/$ID -name grub.cfg)
                if [ -z $GRUB_CFG_LOCATION ] ; then
                    GRUB_CFG_LOCATION=$($SUDO find /boot/grub* -name grub.cfg)
                    if [ -z $GRUB_CFG_LOCATION ] ; then
                        echo "WARNING: No GRUB config file found."
                        echo "GRUB bootloader may not be installed."
                        echo "Script can't make permanent changes to the usbfs_memory_mb parameter."
                    fi
                fi

                if [ "$GRUB_CFG_LOCATION" ] ; then
                    echo "Preparing $GRUB_CFG_LOCATION for next boot."
                    $SUDO /usr/sbin/grub2-mkconfig -o $GRUB_CFG_LOCATION
                    echo "Please reboot system to make the parameter change permanent."
                fi
            else
                echo "WARNING: /etc/os-release not existing."
                echo "Script can't make permanent changes to the usbfs_memory_mb parameter."
            fi
        fi
    else
        echo "WARNING: No GRUB bootloader installed."
        echo "Script can't make permanent changes to the usbfs_memory_mb parameter."
    fi
fi


echo ""
echo "Installation successful"
echo ""
