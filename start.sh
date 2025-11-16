#!/bin/bash

# 检查COLMAP、OpenSplat和ffmpeg是否可用
echo "检查COLMAP、OpenSplat和ffmpeg是否已安装..."

COLMAP_INSTALLED=false
OPENSLAT_INSTALLED=false
FFMPEG_INSTALLED=false

# 检查COLMAP是否已安装
if command -v colmap &> /dev/null; then
    echo "COLMAP 已安装"
    COLMAP_INSTALLED=true
else
    echo "COLMAP 未安装"
fi

# 检查OpenSplat是否已安装
if [ -f "opensplat/build/opensplat" ]; then
    echo "OpenSplat 已安装"
    OPENSLAT_INSTALLED=true
else
    echo "OpenSplat 未安装"
fi

# 检查ffmpeg是否已安装
if command -v ffmpeg &> /dev/null; then
    echo "ffmpeg 已安装"
    FFMPEG_INSTALLED=true
else
    echo "ffmpeg 未安装"
fi

# 如果COLMAP未安装，则进行安装
if [ "$COLMAP_INSTALLED" = false ]; then
    echo "正在安装COLMAP依赖..."
    apt update
    apt-get install -y \
        git \
        cmake \
        ninja-build \
        build-essential \
        libboost-program-options-dev \
        libboost-graph-dev \
        libboost-system-dev \
        libeigen3-dev \
        libfreeimage-dev \
        libmetis-dev \
        libgoogle-glog-dev \
        libgtest-dev \
        libgmock-dev \
        libsqlite3-dev \
        libglew-dev \
        qtbase5-dev \
        libqt5opengl5-dev \
        libcgal-dev \
        libceres-dev \
        libcurl4-openssl-dev \
        libmkl-full-dev 

    # 编译colmap
    echo "正在编译COLMAP..."
    cd colmap || { echo "无法进入colmap目录"; exit 1; }

    mkdir -p build
    cd build || { echo "无法进入build目录"; exit 1; }
    # Removed hardcoded CUDA architecture to make it more flexible
    cmake -GNinja -DBLA_VENDOR=Intel10_64lp .. || { echo "CMake配置失败"; exit 1; }
    ninja || { echo "Ninja编译失败"; exit 1; }
    ninja install || { echo "Ninja安装失败"; exit 1; }

    cd ../..
fi

# 如果OpenSplat未安装，则进行安装
if [ "$OPENSLAT_INSTALLED" = false ]; then
    echo "正在安装OpenSplat依赖..."
    apt install -y libopencv-dev || { echo "OpenCV安装失败"; exit 1; }
    
    if [ ! -f libtorch-cxx11-abi-shared-with-deps-2.3.0+cu121.zip ]; then
        wget https://download.pytorch.org/libtorch/cu121/libtorch-cxx11-abi-shared-with-deps-2.3.0%2Bcu121.zip || { echo "下载LibTorch失败"; exit 1; }
        unzip libtorch-cxx11-abi-shared-with-deps-2.3.0+cu121.zip || { echo "解压LibTorch失败"; exit 1; }
    fi

    # 编译opensplat
    echo "正在编译OpenSplat..."
    cd opensplat || { echo "无法进入opensplat目录"; exit 1; }

    mkdir -p build && cd build || { echo "无法创建或进入build目录"; exit 1; }
    export Torch_DIR="../../libtorch/share/cmake/Torch"
    # Removed hardcoded CUDA architecture to make it more flexible
    cmake -DCMAKE_PREFIX_PATH=../../libtorch/ .. && make -j$(nproc) || { echo "OpenSplat编译失败"; exit 1; }

    cd ../..
fi

# 如果ffmpeg未安装，则进行安装
if [ "$FFMPEG_INSTALLED" = false ]; then
    echo "正在安装ffmpeg..."
    apt update
    apt install -y ffmpeg || { echo "FFmpeg安装失败"; exit 1; }
fi

# 检查 ~/autodl-tmp 目录是否存在
AUTODL_TMP="$HOME/autodl-tmp"
if [ ! -d "$AUTODL_TMP" ]; then
    echo "目录 $AUTODL_TMP 不存在"
    exit 1
fi

# 获取 ~/autodl-tmp 下的所有文件夹
DATA_FOLDERS=($(ls -d "$AUTODL_TMP"/*/ 2>/dev/null))
if [ ${#DATA_FOLDERS[@]} -eq 0 ]; then
    echo "目录 $AUTODL_TMP 中没有找到子文件夹"
    exit 1
fi

echo "找到 ${#DATA_FOLDERS[@]} 个数据文件夹"

# 提示用户输入每个文件夹对应的抽帧时间（秒）
echo "请输入每个文件夹对应的抽帧时间（秒），用空格分隔:"
echo "例如：对于3个文件夹，可以输入 '0 5 10' 表示分别在第0、5、10秒抽帧"
read -p "输入时间值: " -a FRAME_TIMES

# 验证输入的数量是否正确
if [ ${#FRAME_TIMES[@]} -ne ${#DATA_FOLDERS[@]} ]; then
    echo "错误：您输入了 ${#FRAME_TIMES[@]} 个时间值，但有 ${#DATA_FOLDERS[@]} 个文件夹"
    echo "请确保输入的时间值数量与文件夹数量一致"
    exit 1
fi

# 将秒数转换为 hh:mm:ss 格式
format_time() {
    local total_seconds=$1
    local hours=$((total_seconds / 3600))
    local minutes=$(( (total_seconds % 3600) / 60 ))
    local seconds=$((total_seconds % 60))
    printf "%02d:%02d:%02d" $hours $minutes $seconds
}

# 保存起始目录
START_DIR=$(pwd)

# 循环处理每个文件夹
for i in "${!DATA_FOLDERS[@]}"; do
    folder="${DATA_FOLDERS[$i]}"
    frame_time="${FRAME_TIMES[$i]}"
    formatted_time=$(format_time $frame_time)
    
    FOLDER_NAME=$(basename "$folder")
    echo "正在处理文件夹: $FOLDER_NAME"
    echo "抽帧时间设置为: 第${frame_time}秒 (${formatted_time})"
    
    # 创建对应的数据目录
    DATA_DIR="data_$FOLDER_NAME"
    mkdir -p "$DATA_DIR"
    cd "$DATA_DIR" || { echo "无法进入$DATA_DIR目录"; exit 1; }
    
    # 复制视频文件到videos目录
    mkdir -p videos
    # 更安全的复制命令，避免隐藏文件问题
    cp -r "$folder"* videos/ 2>/dev/null || echo "警告：某些文件复制可能失败"
    
    # 创建拆帧所需目录
    mkdir -p camera/input process/input
    
    # 处理所有视频文件
    for video in videos/*.mp4 videos/*.avi videos/*.mov videos/*.mkv videos/*.MP4 videos/*.AVI videos/*.MOV videos/*.MKV; do
        if [ -f "$video" ]; then
            filename=$(basename "$video" | cut -d. -f1)
            echo "处理视频: $video"
            
            ffmpeg -i "$video" -ss 00:00:00 -vframes 1 -q:v 2 "camera/input/${filename}.png" -y || echo "警告：从$video提取第一帧失败"
            
            ffmpeg -i "$video" -ss "$formatted_time" -vframes 1 -q:v 2 "process/input/${filename}.png" -y || echo "警告：从$video提取第二帧失败（时间：${formatted_time}）"
        fi
    done
    
    # 准备相机参数
    echo "准备相机参数..."
    colmap feature_extractor \
        --database_path ./camera/database.db \
        --image_path ./camera/input \
        --ImageReader.camera_model OPENCV \
        --camera_mode 3 || { echo "COLMAP特征提取失败"; exit 1; }

    colmap exhaustive_matcher \
        --database_path ./camera/database.db || { echo "COLMAP匹配失败"; exit 1; }

    colmap mapper \
        --database_path ./camera/database.db \
        --image_path ./camera/input \
        --output_path ./camera/sparse || { echo "COLMAP建图失败"; exit 1; }

    colmap model_converter \
       --input_path ./camera/sparse/0 \
       --output_path ./camera/sparse/0 \
       --output_type TXT || { echo "COLMAP模型转换失败"; exit 1; }

    colmap image_undistorter \
       --image_path ./process/input \
       --input_path ./camera/sparse/0 \
       --output_path ./process \
       --output_type COLMAP || { echo "COLMAP图像矫正失败"; exit 1; }

    # 运行opensplat训练高斯
    echo "开始高斯训练..."
    ../../opensplat/build/opensplat process --o process/output/$folder.ply || { echo "OpenSplat训练失败"; exit 1; }
    
    cd "$START_DIR" || { echo "无法返回起始目录"; exit 1; }
    
    echo "完成处理文件夹: $FOLDER_NAME"
done

echo "所有文件夹处理完毕"