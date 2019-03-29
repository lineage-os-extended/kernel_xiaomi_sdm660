#!/usr/bin/env bash
# SemaphoreCI Kernel Build Script
# Copyright (C) 2018 Raphiel Rollerscaperers (raphielscape)
# Copyright (C) 2018 Rama Bondan Prakoso (rama982)
# SPDX-License-Identifier: GPL-3.0-or-later

#
# Telegram FUNCTION begin
#

git clone https://github.com/fabianonline/telegram.sh telegram

TELEGRAM_ID=-1001465615408

TELEGRAM=telegram/telegram

export TELEGRAM_TOKEN

# Push kernel installer to channel
function push() {
	JIP=$(echo Genom*.zip)
	curl -F document=@$JIP  "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument" \
			-F chat_id="$TELEGRAM_ID"
}

# Send the info up
function tg_channelcast() {
	"${TELEGRAM}" -c ${TELEGRAM_ID} -H \
		"$(
			for POST in "${@}"; do
				echo "${POST}"
			done
		)"
}

function tg_sendinfo() {
	curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
		-d "parse_mode=markdown" \
		-d text="${1}" \
		-d chat_id="$TELEGRAM_ID" \
		-d "disable_web_page_preview=true"
}

# Errored prober
function finerr() {
	tg_sendinfo "$(echo -e "Build took $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds\nbut it's error...")"
	exit 1
}

# Send sticker
function tg_sendstick() {
	curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendSticker" \
		-d sticker="CAADBQADgQADuMZ9GebdeJ3qOSmSAg" \
		-d chat_id="$TELEGRAM_ID" >> /dev/null
}

# Fin prober
function fin() {
	tg_sendinfo "$(echo "Build took $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.")"
}

#
# Telegram FUNCTION end
#

# Main environtment
KERNEL_DIR=${HOME}/msm-4.4-tulip
KERN_IMG=$KERNEL_DIR/out/arch/arm64/boot/Image.gz-dtb
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
ZIP_DIR=$KERNEL_DIR/AnyKernel2
CONFIG=lavender-perf_defconfig
CORES=$(grep -c ^processor /proc/cpuinfo)
THREAD="-j$CORES"
CROSS_COMPILE+="ccache "
CROSS_COMPILE+="$PWD/stock/bin/aarch64-linux-android-"

# Export
export JOBS="$(grep -c '^processor' /proc/cpuinfo)"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="ramakun"
export CROSS_COMPILE

# Install build package
install-package --update-new ccache bc bash git-core gnupg build-essential \
	zip curl make automake autogen autoconf autotools-dev libtool shtool python \
	m4 gcc libtool zlib1g-dev

# Clone toolchain
git clone https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 -b android-9.0.0_r34 --depth=1 stock

# Clone AnyKernel2
git clone https://github.com/rama982/AnyKernel2 -b lavender-miui

# Build start
DATE=`date`
BUILD_START=$(date +"%s")

tg_sendstick

tg_channelcast "<b>GENOM MIUI</b> kernel new build!" \
		"For device <b>LAVENDER</b> (Redmi Note 7)" \
		"At branch <code>${BRANCH}</code>" \
		"Under commit <code>$(git log --pretty=format:'"%h : %s"' -1)</code>" \
		"Started on <code>$(date)</code>"

make  O=out $CONFIG $THREAD
make  O=out $THREAD

BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))

if ! [ -a $KERN_IMG ]; then
	echo -e "Kernel compilation failed, See buildlog to fix errors"
	finerr
	exit 1
fi

cd $ZIP_DIR
make clean &>/dev/null
cd ..

# For MIUI Build
# Credit @adekmaulana
OUTDIR="$PWD/out/"
SRCDIR="$PWD/"
VENDOR_MODULEDIR="$PWD/AnyKernel2/modules/vendor/lib/modules"
STRIP="$PWD/stock/bin/$(echo "$(find "$PWD/stock/bin" -type f -name "aarch64-*-gcc")" | awk -F '/' '{print $NF}' |\
			sed -e 's/gcc/strip/')"

for MODULES in $(find "${OUTDIR}" -name '*.ko'); do
	"${STRIP}" --strip-unneeded --strip-debug "${MODULES}" &> /dev/null
	"${OUTDIR}"/scripts/sign-file sha512 \
			"${OUTDIR}/certs/signing_key.pem" \
			"${OUTDIR}/certs/signing_key.x509" \
			"${MODULES}"
    find "${OUTDIR}" -name '*.ko' -exec cp {} "${VENDOR_MODULEDIR}" \;
	case ${MODULES} in
			*/wlan.ko)
		mv "${MODULES}" "${VENDOR_MODULEDIR}/qca_cld3_wlan.ko" ;;

	esac
done
echo -e "\n(i) Done moving modules"

cd $ZIP_DIR
cp $KERN_IMG $ZIP_DIR/zImage
make normal &>/dev/null
echo Genom*.zip
echo "Flashable zip generated under $ZIP_DIR."
push
cd ..
fin
# Build end