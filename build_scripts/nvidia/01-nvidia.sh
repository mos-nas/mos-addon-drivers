#!/bin/bash

# Set variables
DRIVER_NAME=nvidia
DRIVER_BUILD_DIR=$BUILD_DIR/$DRIVER_NAME
DRIVER_PACKAGE_DIR=$DRIVER_BUILD_DIR/package
DRIVER_OUTPUT_DIR=$WORK_DIR/$KERNEL_V

# Create driver build directory
mkdir $DRIVER_BUILD_DIR
cd $DRIVER_BUILD_DIR

# Get latest versions
LIBNVIDIA_CONTAINER_JSON="$(curl -u ${GH_ACTOR}:${MOS_TOKEN} -s https://api.github.com/repos/ich777/mos-libnvidia-container/releases/latest)"
LIBNVIDIA_CONTAINER_V="$(echo "$LIBNVIDIA_CONTAINER_JSON" | jq -r '.tag_name' | sed 's/^v//')"
CONTAINER_TOOLKIT_JSON="$(curl -u ${GH_ACTOR}:${MOS_TOKEN} -s https://api.github.com/repos/ich777/mos-nvidia-container-toolkit/releases/latest)"
CONTAINER_TOOLKIT_V="$(echo "$CONTAINER_TOOLKIT_JSON" | jq -r '.tag_name' | sed 's/^v//')"

# Grab latest version
OPENSOURCE_DRV_V_PKG=$(wget -qO- https://download.nvidia.com/XFree86/Linux-x86_64/ | grep "href='" | cut -d ">" -f3- | cut -d '/' -f1 | grep -E '^[0-9]+\.[0-9]+' | awk -F'.' '$1 >= 590' | sort -V | tail -1)

# Grab legacy driver version 580.x
LEGACY_DRV_V_PKG=$(wget -qO- https://download.nvidia.com/XFree86/Linux-x86_64/ | grep "href='" | cut -d ">" -f3- | cut -d '/' -f1 | grep "^580" | sort -V | tail -1)

# Define application_download and md5 check function
component_download() {
  echo "Downloading: ${1}_${2}-1+mos_amd64.deb${4}"
  curl --progress-bar -L \
    --header "Authorization: Bearer ${MOS_TOKEN}" \
    --header "Accept: application/octet-stream" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --output "$DRIVER_BUILD_DIR/$1_$2-1+mos_amd64.deb$4" \
    "https://api.github.com/repos/ich777/mos-${1}/releases/assets/$3"
  if [ "$4" == ".md5" ] ; then
    if [ "$(md5sum $DRIVER_BUILD_DIR/${1}_${2}-1+mos_amd64.deb | awk '{print $1}')" != "$(cat $DRIVER_BUILD_DIR/${1}_${2}-1+mos_amd64.deb${4})" ] ; then
      echo "Checksum error from file: ${1}_${2}-1+mos_amd64.deb${4}"
      exit 1
    fi
  fi
}

# Download additional components
cd $DRIVER_BUILD_DIR
if [ ! -f $DRIVER_BUILD_DIR/libnvidia-container_${LIBNVIDIA_CONTAINER_V}-1+mos_amd64.deb ]; then
  # Get Asset IDs
  LIBNVIDIA_DEB=$(echo $LIBNVIDIA_CONTAINER_JSON | jq -r  '.assets[] | select(.name | startswith("libnvidia-container") and endswith("amd64.deb")) | .id')
  LIBNVIDIA_DEB_MD5=$(echo $LIBNVIDIA_CONTAINER_JSON | jq -r  '.assets[] | select(.name | startswith("libnvidia-container") and endswith("amd64.deb.md5")) | .id')
  component_download "libnvidia-container" "$LIBNVIDIA_CONTAINER_V" "$LIBNVIDIA_DEB"
  component_download "libnvidia-container" "$LIBNVIDIA_CONTAINER_V" "$LIBNVIDIA_DEB_MD5" ".md5"
fi
if [ ! -f $DRIVER_BUILD_DIR/nvidia-container-toolkit_${CONTAINER_TOOLKIT_V}-1+mos_amd64.deb ]; then
  CONTAINER_TOOLKIT_DEB=$(echo $CONTAINER_TOOLKIT_JSON | jq -r  '.assets[] | select(.name | startswith("nvidia-container-toolkit") and endswith("amd64.deb")) | .id')
  CONTAINER_TOOLKIT_DEB_MD5=$(echo $CONTAINER_TOOLKIT_JSON | jq -r  '.assets[] | select(.name | startswith("nvidia-container-toolkit") and endswith("amd64.deb.md5")) | .id')
  component_download "nvidia-container-toolkit" "$CONTAINER_TOOLKIT_V" "$CONTAINER_TOOLKIT_DEB"
  component_download "nvidia-container-toolkit" "$CONTAINER_TOOLKIT_V" "$CONTAINER_TOOLKIT_DEB_MD5" ".md5"
fi

nvidia_driver() {
  # Set variables for open or proprietary driver modules
  if [ "$2" == "opensource" ]; then
    NV_PROPRIETARY="--kernel-module-type=open"
  else
    NV_PROPRIETARY="--kernel-module-type=proprietary"
  fi

  # Change directory and remove old directories
  cd $DRIVER_BUILD_DIR
  rm -rf $DRIVER_PACKAGE_DIR /lib/firmware/nvidia

  if [ ! -f $DRIVER_BUILD_DIR/NVIDIA_v${1}.run ]; then
    wget -q -nc --show-progress --progress=bar:force:noscroll -O $DRIVER_BUILD_DIR/NVIDIA_v${1}.run http://us.download.nvidia.com/XFree86/Linux-x86_64/$1/NVIDIA-Linux-x86_64-${1}.run
  fi

  # Make driver executable and create directories
  chmod +x $DRIVER_BUILD_DIR/NVIDIA_v${1}.run
  mkdir -p $DRIVER_PACKAGE_DIR/usr/lib/xorg/modules/{drivers,extensions} $DRIVER_PACKAGE_DIR/usr/lib/x86_64-linux-gnu $DRIVER_PACKAGE_DIR/usr/bin $DRIVER_PACKAGE_DIR/etc $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/drivers/video $DRIVER_PACKAGE_DIR/lib/firmware

  # Workaround for Kernel 6.19+ & OpenSource driver 590.48.01
  if [[ "$KERNEL_V" == 6.19.* && "$1" == 590.48.01 && "$2" == "opensource" ]]; then
    $DRIVER_BUILD_DIR/NVIDIA_v${1}.run --extract-only
    cd $DRIVER_BUILD_DIR/NVIDIA-Linux-x86_64-*
    patch -p1 < $WORK_DIR/build_scripts/$DRIVER_NAME/cachyos-kernel-6.19.patch
    # Compile driver
    $DRIVER_BUILD_DIR/NVIDIA-Linux-x86_64-*/nvidia-installer --kernel-source-path=$KERNEL_DIR \
      --no-precompiled-interface \
      --disable-nouveau \
      --x-prefix=$DRIVER_PACKAGE_DIR/usr \
      --x-library-path=lib/x86_64-linux-gnu \
      --x-module-path=$DRIVER_PACKAGE_DIR/usr/lib/xorg/modules \
      --opengl-prefix=$DRIVER_PACKAGE_DIR/usr \
      --installer-prefix=$DRIVER_PACKAGE_DIR/usr \
      --utility-prefix=$DRIVER_PACKAGE_DIR/usr \
      --documentation-prefix=$DRIVER_PACKAGE_DIR/usr \
      --application-profile-path=share/nvidia \
      --proc-mount-point=$DRIVER_PACKAGE_DIR/proc \
      --kernel-install-path=$DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/drivers/video \
      --compat32-prefix=$DRIVER_PACKAGE_DIR/usr \
      --compat32-libdir=lib/i386-linux-gnu \
      --install-compat32-libs \
      --no-x-check \
      --no-nouveau-check \
      --no-systemd \
      --skip-depmod \
      --skip-module-load \
      --no-backup \
      --j$(nproc --all) \
      ${NV_PROPRIETARY} --silent
  else
    # Compile driver
    $DRIVER_BUILD_DIR/NVIDIA_v${1}.run --kernel-source-path=$KERNEL_DIR \
      --no-precompiled-interface \
      --disable-nouveau \
      --x-prefix=$DRIVER_PACKAGE_DIR/usr \
      --x-library-path=lib/x86_64-linux-gnu \
      --x-module-path=$DRIVER_PACKAGE_DIR/usr/lib/xorg/modules \
      --opengl-prefix=$DRIVER_PACKAGE_DIR/usr \
      --installer-prefix=$DRIVER_PACKAGE_DIR/usr \
      --utility-prefix=$DRIVER_PACKAGE_DIR/usr \
      --documentation-prefix=$DRIVER_PACKAGE_DIR/usr \
      --application-profile-path=share/nvidia \
      --proc-mount-point=$DRIVER_PACKAGE_DIR/proc \
      --kernel-install-path=$DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/drivers/video \
      --compat32-prefix=$DRIVER_PACKAGE_DIR/usr \
      --compat32-libdir=lib/i386-linux-gnu \
      --install-compat32-libs \
      --no-x-check \
      --no-nouveau-check \
      --no-systemd \
      --skip-depmod \
      --skip-module-load \
      --no-backup \
      --j$(nproc --all) \
      ${NV_PROPRIETARY} --silent
  fi

  # Add missing files
  if [ -d /lib/firmware/nvidia ]; then
    cp -R /lib/firmware/nvidia $DRIVER_PACKAGE_DIR/lib/firmware/
  fi
  cp /usr/bin/nvidia-modprobe $DRIVER_PACKAGE_DIR/usr/bin/
  cp -R /etc/OpenCL $DRIVER_PACKAGE_DIR/etc/
  cp -R /etc/vulkan $DRIVER_PACKAGE_DIR/etc/

  mkdir -p $DRIVER_PACKAGE_DIR/usr/share/glvnd/egl_vendor.d /$DRIVER_PACKAGE_DIR/usr/share/egl/egl_external_platform.d
  cp /usr/share/glvnd/egl_vendor.d/*nvidia*.json $DRIVER_PACKAGE_DIR/usr/share/glvnd/egl_vendor.d/
  cp /usr/share/egl/egl_external_platform.d/*nvidia*.json $DRIVER_PACKAGE_DIR/usr/share/egl/egl_external_platform.d/

  # Fix for gbm symlink
  cd $DRIVER_PACKAGE_DIR/lib/x86_64-linux-gnu/gbm
  rm -f nvidia-drm_gbm.so
  ln -sf /lib/x86_64-linux-gnu/libnvidia-allocator.so.1 nvidia-drm_gbm.so

  # Add additional components
  dpkg --root=$DRIVER_PACKAGE_DIR --install $DRIVER_BUILD_DIR/libnvidia-container_${LIBNVIDIA_CONTAINER_V}-1+mos_amd64.deb
  dpkg --root=$DRIVER_PACKAGE_DIR --install $DRIVER_BUILD_DIR/nvidia-container-toolkit_${CONTAINER_TOOLKIT_V}-1+mos_amd64.deb

  # Remove dpkg folders
  rm -rf $DRIVER_PACKAGE_DIR/var

  # Create Debian control file
  mkdir $DRIVER_PACKAGE_DIR/DEBIAN
  cat > $DRIVER_PACKAGE_DIR/DEBIAN/control << EOF
Package: $DRIVER_NAME-${2}-driver
Version: $1
Architecture: amd64
Maintainer: ich777
Description: ${DRIVER_NAME}-${2} drivers for MOS
EOF

  # Create Debian package and md5 checksum
  cd $DRIVER_BUILD_DIR
  dpkg-deb --build package $DRIVER_OUTPUT_DIR/${DRIVER_NAME}-${2}_${1}-1+mos_amd64.deb

  # Check filesize
  MIN_SIZE=250000000
  PACKAGE_SIZE=$(stat -c%s $DRIVER_OUTPUT_DIR/${DRIVER_NAME}-${2}_${1}-1+mos_amd64.deb)
  if [ "$PACKAGE_SIZE" -lt "$MIN_SIZE" ] ; then
    echo "ERROR: Package filesize to low, deleting package: ${DRIVER_NAME}-${2}_${1}-1+mos_amd64.deb"
    discord_push_notification "$DRIVER_NAME-${2}" "Compilation failed for $1" "1"
    rm -f $DRIVER_OUTPUT_DIR/${DRIVER_NAME}-${2}_${1}-1+mos_amd64.deb
  else
    md5sum $DRIVER_OUTPUT_DIR/${DRIVER_NAME}-${2}_${1}-1+mos_amd64.deb | awk '{print $1}' > $DRIVER_OUTPUT_DIR/${DRIVER_NAME}-${2}_${1}-1+mos_amd64.deb.md5
  fi
}

# Compile latest driver
nvidia_driver "$OPENSOURCE_DRV_V_PKG" "opensource"

# Compile legacy driver version 580.x
nvidia_driver "$LEGACY_DRV_V_PKG" "proprietary"

exit 0
