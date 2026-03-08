#!/bin/bash

# --- Configuration ---
DEVICE="larry"
MODEL="OP5958L1"
DEFCONFIG="vendor/holi-qgki_defconfig"
USER="VIAAN"
HOST="Kernel-SM6375"
THREAD=$(nproc --all)
OUT_DIR="$(pwd)/out"

# --- Toolchain Setup ---
CLANG_DIR="$(pwd)/clang"

function setup_tc() {
    if [ ! -d "$CLANG_DIR" ]; then
        echo "--> Downloading Neutron Toolchain..."
        mkdir -p "$CLANG_DIR" && cd "$CLANG_DIR"
        bash <(curl -s https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman) -S
        bash <(curl -s https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman) --patch=glibc
        cd ..
    fi
    export PATH="$CLANG_DIR/bin:$PATH"
}

function compile() {
    echo "Starting build for $DEVICE..."
     
    export ARCH=arm64
    export SUBARCH=arm64
    export KBUILD_BUILD_USER="$USER"
    export KBUILD_BUILD_HOST="$HOST"
    export USE_CCACHE=1
     
    read -p "Wanna do dirty build? (y/N): " build_type
    if [[ ! $build_type =~ ^[Yy]$ ]]; then
        echo "--> Cleaning out directory..."
        rm -rf "$OUT_DIR"
    fi
    mkdir -p "$OUT_DIR"

    make O=out ARCH=arm64 $DEFCONFIG

    make -j$THREAD O=out \
        ARCH=arm64 \
        CC=clang \
        NM=llvm-nm \
        OBJCOPY=llvm-objcopy \
        OBJUMP=llvm-objdump \
        STRIP=llvm-strip \
        LD=ld.lld \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        LLVM=1 LLVM_IAS=1 \
        KCFLAGS="-Wno-error=frame-larger-than=" \
        CONFIG_SECTION_MISMATCH_WARN_ONLY=y \
        2>&1 | tee error.log
}

function pack() {
    if [ -f "out/arch/arm64/boot/Image" ]; then
        echo "--> Build Successful! Preparing AnyKernel3..."
         
        rm -rf AnyKernel3
        git clone --depth=1 https://github.com/osm0sis/AnyKernel3 AnyKernel3
         
        echo "--> Patching anykernel.sh..."
        # Use a different delimiter (|) for sed to handle slashes in paths safely
        sed -i "s|kernel.string=.*|kernel.string=Astra-Kernel-$DEVICE by $USER|g" AnyKernel3/anykernel.sh
        sed -i "s|device.name1=maguro|device.name1=$MODEL|g" AnyKernel3/anykernel.sh
        sed -i "s|device.name2=toro|device.name2=$DEVICE|g" AnyKernel3/anykernel.sh
        
        # This line fixes your specific error by replacing the old OMAP path
        sed -i "s|BLOCK=.*|BLOCK=/dev/block/by-name/boot;|g" AnyKernel3/anykernel.sh
        sed -i 's/IS_SLOT_DEVICE=0/IS_SLOT_DEVICE=1/g' AnyKernel3/anykernel.sh
        sed -i 's/supported.versions=.*/supported.versions=11, 12, 13, 14, 15/g' AnyKernel3/anykernel.sh

        echo "--> Injecting ASTRA Banner..."
        sed -i '/if \[ -f banner \]; then/,/fi;/c\
ui_print "-----------------------------------------------";\
ui_print "                                               ";\
ui_print "     AAA     SSSS   TTTTT  RRRR      AAA       ";\
ui_print "    A   A   S         T    R   R    A   A      ";\
ui_print "    AAAAA    SSS      T    RRRR     AAAAA      ";\
ui_print "    A   A       S     T    R R      A   A      ";\
ui_print "    A   A   SSSS      T    R  RR    A   A      ";\
ui_print "                                               ";\
ui_print "-----------------------------------------------";\
ui_print "|-----------Astra-Kernel-larry----------------|";\
ui_print "|-------------By Viaan Thakur---- ------------|";\
ui_print "|-------Telegram : @VIAAN_THAKUR--------------|";' AnyKernel3/META-INF/com/google/android/update-binary

        cp out/arch/arm64/boot/Image AnyKernel3/
        cd AnyKernel3
        ZIP_NAME="Astra-Kernel-$DEVICE-$(date +%Y%m%d-%H%M).zip"
        zip -r9 "$ZIP_NAME" * -x .git README.md
        mv "$ZIP_NAME" ..
        cd ..
        
        echo "--> All done! Flashable zip created: $ZIP_NAME"
    else
        echo "--> Build Failed! Check error.log"
        exit 1
    fi
}

setup_tc
compile
pack
