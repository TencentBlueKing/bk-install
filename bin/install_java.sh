#!/usr/bin/env bash
# install_java.sh ：安装，配置java(jdk)
# 参考文档： https://docs.oracle.com/javase/8/docs/technotes/guides/install/linux_jdk.html

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
TGZ_FILE_PATH=
BINARY_SRC_DIR=
FROM=
PREFIX=/usr/local

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -p, --prefix  [可选] "安装jdk到该目录, 会设置PATH包含\$PREFIX/java/bin" ]
            [ -f, --file    [可选] "从官方的tar.gz压缩包解压安装" ]
            [ -s, --srcdir  [可选] "拷贝解压过的java/目录到到\$PREFIX" ]
            [ -v, --version [可选] 查看脚本版本号 ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

log () {
    echo "$@"
}

error () {
    echo "$@" 1>&2
    usage_and_exit 1
}

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

version () {
    echo "$PROGRAM version $VERSION"
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -s | --srcdir )
            shift
            BINARY_SRC_DIR=$1
            ;;
        -p | --prefix )
            shift
            PREFIX=$1
            ;;
        -f | --file )
            shift
            TGZ_FILE_PATH=$1
            ;;
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --version | -v | -V )
            version 
            exit 0
            ;;
        -*)
            error "不可识别的参数: $1"
            ;;
        *) 
            break
            ;;
    esac
    shift 
done 

# 参数合法性有效性校验，这些可以使用通用函数校验。
if [[ -n "$TGZ_FILE_PATH" && -n "$BINARY_SRC_DIR" ]]; then 
    error "--file和--srcdir是互斥参数，只能指定其中之一"
fi

if [[ -n "$BINARY_SRC_DIR" ]]; then
    if ! [[ -x $BINARY_SRC_DIR/bin/java ]]; then 
        warning "不存在$BINARY_SRC_DIR/bin/java可执行文件"
    fi
    FROM="dir"
fi

if [[ -n "$TGZ_FILE_PATH" ]]; then 
    if ! [[ -f "$TGZ_FILE_PATH" ]]; then 
        warning "$TGZ_FILE_PATH 不存在"
    fi
    FROM="tgz"
fi

if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

case $FROM in 
    dir ) 
        # 拷贝java到$PREFIX
        (
            cd "$(dirname "$BINARY_SRC_DIR")" && \
            tar -cf - java | ( cd "$PREFIX" && tar -xf - )
        )
        ;;
    tgz )
        mkdir -p "$PREFIX"/java && \
        tar -xf "$TGZ_FILE_PATH" --strip-component=1 -C "$PREFIX/java"
        ;;
    * )
        usage_and_exit 1
        ;;
esac

if [[ -x $PREFIX/java/bin/java ]]; then
    log "安装java目录成功：$PREFIX/java/bin/java"
    log "配置java环境变量到 /etc/profile.d/java.sh"
    echo "export JAVA_HOME=$PREFIX/java" > /etc/profile.d/java.sh
    echo "export PATH=$PREFIX/java/bin:\$PATH" >> /etc/profile.d/java.sh
    chmod +x /etc/profile.d/java.sh
    # shellcheck disable=SC1091
    source /etc/profile.d/java.sh
    log "设置软连接/usr/bin/java到$PREFIX/java/bin/java"
    ln -sf "$PREFIX"/java/bin/java /usr/bin/java
    java -version
else
    error "安装java失败，请检查$PREFIX/java/bin目录下是否有可执行文件(java等)"
fi