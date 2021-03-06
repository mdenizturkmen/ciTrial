#!/bin/bash
set -e

trap "echo TRAPed signal" HUP INT QUIT KILL TERM

sudo chown -R user:user /home/user 
echo "user:$PASSWD" | sudo chpasswd
sudo ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" | sudo tee /etc/timezone > /dev/null

sudo ln -snf /dev/ptmx /dev/tty7
sudo /etc/init.d/ssh start
#sudo /etc/init.d/dbus start
#pulseaudio --start

# Install NVIDIA drivers, including X graphic drivers by omitting --x-{prefix,module-path,library-path,sysconfig-path}
if ! command -v nvidia-xconfig &> /dev/null; then
  export DRIVER_VERSION=$(head -n1 </proc/driver/nvidia/version | awk '{print $8}')
  BASE_URL=https://download.nvidia.com/XFree86/Linux-x86_64
  cd /tmp
  curl -fsSL -O $BASE_URL/$DRIVER_VERSION/NVIDIA-Linux-x86_64-$DRIVER_VERSION.run
  sudo sh NVIDIA-Linux-x86_64-$DRIVER_VERSION.run -x
  cd NVIDIA-Linux-x86_64-$DRIVER_VERSION
  sudo ./nvidia-installer --silent \
                    --no-kernel-module \
                    --install-compat32-libs \
                    --no-nouveau-check \
                    --no-nvidia-modprobe \
                    --no-rpms \
                    --no-backup \
                    --no-check-for-alternate-installs \
                    --no-libglx-indirect \
                    --no-install-libglvnd
  sudo rm -rf /tmp/NVIDIA*
  cd ~
fi

if grep -Fxq "allowed_users=console" /etc/X11/Xwrapper.config; then
  sudo sed -i "s/allowed_users=console/allowed_users=anybody/;$ a needs_root_rights=yes" /etc/X11/Xwrapper.config
fi

if [ -f "/etc/X11/xorg.conf" ]; then
  sudo rm /etc/X11/xorg.conf
fi

if [ "$NVIDIA_VISIBLE_DEVICES" == "all" ]; then
  export GPU_SELECT=$(sudo nvidia-smi --query-gpu=uuid --format=csv | sed -n 2p)
elif [ -z "$NVIDIA_VISIBLE_DEVICES" ]; then
  export GPU_SELECT=$(sudo nvidia-smi --query-gpu=uuid --format=csv | sed -n 2p)
else
  export GPU_SELECT=$(sudo nvidia-smi --id=$(echo "$NVIDIA_VISIBLE_DEVICES" | cut -d ',' -f1) --query-gpu=uuid --format=csv | sed -n 2p)
  if [ -z "$GPU_SELECT" ]; then
    export GPU_SELECT=$(sudo nvidia-smi --query-gpu=uuid --format=csv | sed -n 2p)
  fi
fi

if [ -z "$GPU_SELECT" ]; then
  echo "No NVIDIA GPUs detected. Exiting."
  exit 1
fi

HEX_ID=$(sudo nvidia-smi --query-gpu=pci.bus_id --id="$GPU_SELECT" --format=csv | sed -n 2p)
IFS=":." ARR_ID=($HEX_ID)
unset IFS
BUS_ID=PCI:$((16#${ARR_ID[1]})):$((16#${ARR_ID[2]})):$((16#${ARR_ID[3]}))
export MODELINE=$(cvt -r ${SIZEW} ${SIZEH} | sed -n 2p)
sudo nvidia-xconfig --virtual="${SIZEW}x${SIZEH}" --depth="$CDEPTH" --mode=$(echo $MODELINE | awk '{print $2}' | tr -d '"') --allow-empty-initial-configuration --no-probe-all-gpus --busid="$BUS_ID" --only-one-x-screen --connected-monitor="$VIDEO_PORT"
sudo sed -i '/Driver\s\+"nvidia"/a\    Option         "ModeValidation" "NoMaxPClkCheck, NoEdidMaxPClkCheck, NoMaxSizeCheck, NoHorizSyncCheck, NoVertRefreshCheck, NoVirtualSizeCheck, NoExtendedGpuCapabilitiesCheck, NoTotalSizeCheck, NoDualLinkDVICheck, NoDisplayPortBandwidthCheck, AllowNon3DVisionModes, AllowNonHDMI3DModes, AllowNonEdidModes, NoEdidHDMI2Check, AllowDpInterlaced"\n    Option         "DPI" "96 x 96"' /etc/X11/xorg.conf
sudo sed -i '/Section\s\+"Monitor"/a\    '"$MODELINE" /etc/X11/xorg.conf

sudo /usr/bin/dbus &
export DISPLAY=:0
/usr/bin/pulseaudio --disallow-module-loading -vvvv --disallow-exit --exit-idle-time=-1 &
cd /etc/X11
/usr/bin/X vt7 -novtswitch -sharevts +extension "MIT-SHM" :0 -config xorg.conf :0 &
/usr/bin/neko serve -d --static "/var/www" --bind "0.0.0.0:$NEKO_BIND"   --epr "$NEKO_UDP_PORT" --display ":0" &
mate-session &

echo "Session Running. Press [Return] to exit."
read
