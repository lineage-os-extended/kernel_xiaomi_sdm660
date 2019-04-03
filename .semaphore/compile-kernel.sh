#!/usr/bin/env bash
# SemaphoreCI Kernel Build Script
# Copyright (C) 2018 Raphiel Rollerscaperers (raphielscape)
# Copyright (C) 2018 Rama Bondan Prakoso (rama982)
# SPDX-License-Identifier: GPL-3.0-or-later

#
# Telegram FUNCTION begin
#

git clone https://github.com/fabianonline/telegram.sh telegram

TELEGRAM_ID=-1001232319637

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
		-d sticker="CAADBQADCgADVxIpHaFgYtltlYK2Ag" \
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
ZIP_DIR=$KERNEL_DIR/AnyKernel2
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
CONFIG=lavender-perf_defconfig
CORES=$(grep -c ^processor /proc/cpuinfo)
THREAD="-j$CORES"
PATH="${KERNEL_DIR}/clang/bin:${KERNEL_DIR}/stock/bin:${PATH}"
KBUILD_COMPILER_STRING="$(clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g')"

# Export
export JOBS="$(grep -c '^processor' /proc/cpuinfo)"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="ramakun"
export CROSS_COMPILE
export PATH
export KBUILD_COMPILER_STRING

# Install build package
install-package --update-new bc bash git-core gnupg build-essential \
	zip curl make automake autogen autoconf autotools-dev libtool shtool python \
	m4 gcc libtool zlib1g-dev gcc-aarch64-linux-gnu

# Clone toolchain
git clone https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 --depth=1 stock

# Clone AnyKernel2
git clone https://github.com/rama982/AnyKernel2 -b lavender-miui
wget https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/master/clang-r353983b.tar.gz
mkdir clang && tar xzxf *.tar.gz -C clang

# Build start
DATE=`date`
BUILD_START=$(date +"%s")

tg_sendstick

tg_channelcast "Genom Kernel For MIUI ROM new build!" \
	"For device <b>LAVENDER</b> (Redmi Note 7)" \
	"Using toolchain: <code>$(clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g')</code>" \
	"At branch <code>${BRANCH}</code>" \
	"With latest commit <code>$(git log --pretty=format:'"%h : %s"' -1)</code>" \
	"Started on <code>$(date)</code>"

make  O=out $CONFIG $THREAD
make -j$(nproc --all) O=out \
                      ARCH=arm64 \
                      CC=clang \
                      CLANG_TRIPLE=aarch64-linux-gnu- \
                      CROSS_COMPILE=aarch64-linux-android-

BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))

if ! [ -a $KERN_IMG ]; then
	echo -e "Kernel compilation failed, See buildlog to fix errors"
	finerr
	exit 1
fi

echo "Build took $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."

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
		cp "${MODULES}" "${VENDOR_MODULEDIR}/qca_cld3_wlan.ko" ;;

	esac
done
echo -e "\n(i) Done moving modules"
rm "${VENDOR_MODULEDIR}/wlan.ko"

cd $ZIP_DIR
cp $KERN_IMG $ZIP_DIR/zImage
make normal &>/dev/null
echo Genom*.zip
echo "Flashable zip generated under $ZIP_DIR."
push
cd ..
fin
# Build end