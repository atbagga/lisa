#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

#############################################################################
#
# ETHTOOL-CHECK-CHANNEL.sh
# Description:
#   This script will first check the existence of ethtool on vm and that
#   the channel parameters are supported from ethtool.
#   This script will change the channel from the ethtool with all the allowed
#   values.
#
#############################################################################
# Source utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    SetTestStateAborted
    exit 0
}

# Source constants file and initialize most common variables
UtilsInit

# Distro check before proceeding for functionality check
if [[ $DISTRO_NAME == "centos" || $DISTRO_NAME == "rhel" ]]; then
    mj=$(echo $DISTRO_VERSION | cut -d "." -f 1)
    mn=$(echo $DISTRO_VERSION | cut -d "." -f 2)
    if [ $dj -eq 7 ] && [ $dn -lt 4 ]; then
        LogErr "Recommended distro version is RHEL/CentOS 7.4 or later"
        SetTestStateSkipped
        exit 0
    fi
fi

# Check if ethtool exist and install it if not
if ! VerifyIsEthtool; then
    LogErr "Could not find ethtool in the VM"
    SetTestStateFailed
    exit 0
fi

if ! GetSynthNetInterfaces; then
    LogErr "No synthetic network interfaces found"
    SetTestStateFailed
    exit 0
fi

# Skip when host older than 2012R2
vmbus_version=$(dmesg | grep "Vmbus version" | awk -F: '{print $(NF)}' | awk -F. '{print $1}')
if [ "$vmbus_version" -lt "3" ]; then
    LogMsg "Info: Host version older than 2012R2. Skipping test."
    SetTestStateSkipped
    exit 0
fi

for ifc in "${SYNTH_NET_INTERFACES[@]}";do
    # Check if kernel support channel parameters with ethtool
    sts=$(ethtool -l "${ifc}" 2>&1)
    if [[ "$sts" = *"Operation not supported"* ]]; then
        LogErr "$sts"
        kernel_version=$(uname -rs)
        LogErr "Getting number of channels from ethtool is not supported on $kernel_version"
        SetTestStateSkipped
        exit 0
    fi

    ethtool_output=$(ethtool -l "${ifc}" | grep "Combined" | grep -o '[0-9]*')
    # Get number of channels
    channels=$(echo "$ethtool_output" | sed -n 2p)
    # Get max number of channels
    max_channels=$(echo "$ethtool_output" | sed -n 1p)
    # Get number of cores
    cores=$(grep -c processor < /proc/cpuinfo)

    LogMsg "Number of channels: $channels, max number of channels: $max_channels and number of cores: $cores."

    # Change number of channels with all values supported
    for new_channels in $(seq 1 $max_channels); do
        old_channels=$channels
        # Change the number of channels
        if ! ethtool -L "${ifc}" combined "$new_channels" ; then
            LogErr "Change the number of channels of ${ifc} with $new_channels channels failed, old value: $old_channels"
            SetTestStateFailed
            exit 0
        fi

        # Get number of channels
        channels=$(ethtool -l "${ifc}" | grep "Combined" | sed -n 2p | grep -o '[0-9]*')
        if [ "$new_channels" != "$channels" ]; then
            LogErr "Expected: $new_channels channels and actual $channels after change the channels."
            SetTestStateFailed
            exit 0
        fi
        LogMsg "Change number of channels from $old_channels to $new_channels successfully"
    done
done

SetTestStateCompleted
exit 0