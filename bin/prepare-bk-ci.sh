#!/usr/bin/env bash
# 转换bk-ci安装包适配企业版部署脚本.

set -eu

# 变量
: ${PKG_SRC_PATH:=/data/src}
: ${CTRL_DIR:=/data/install}
: ${INSTALL_PATH:=/data/bkee}

: ${CI_DOWNLOAD_URL_FMT:=https://bkopen-1252002024.file.myqcloud.com/bkci/bkci-%s.tar.gz}
download_ci (){
  local vers=$1
  CI_PKG="$PKG_SRC_PATH/bkci-$vers.tar.gz"
  local url
  printf -v url "$CI_DOWNLOAD_URL_FMT" "$vers"
  echo " download $url to $CI_PKG"
  curl -C - -o "$CI_PKG" "$url"
}

CI_PKG="${1-}"
# 检查安装包.
if [ -f "$CI_PKG" ]; then
  echo "$CI_PKG exist."
elif [[ "$CI_PKG" =~ ^v1[.]2[.][0-9]+ ]]; then
  download_ci "$CI_PKG"
else
  echo "Usage: $0 /path/to/bkci-tgz-package|VERSION  -- prepare bk-ci installation source."
  echo "VERSION should begin with v1.2.[0-9], and will be downloaded from url:"
  printf "* $CI_DOWNLOAD_URL_FMT\n" VERSION
  echo ""
  echo "you can pre-download CI package from here and place it into /path/to/bkci-tgz-package:"
  echo "* BlueKing official release: https://bk.tencent.com/download/"
  echo "* GitHub stable build (version v1.2.X): https://github.com/Tencent/bk-ci/releases"
  exit 1
fi
CI_PKG=$(readlink -f "$CI_PKG")  # 取绝对路径.
ci_pkg_first_dir=$(tar tf "$CI_PKG"| head -1 )
if [ "$ci_pkg_first_dir" = "bkci/" ]; then
  :
elif [ "$ci_pkg_first_dir" = "ci/" ]; then
  :
else
  echo "ERROR: invalid ci package: $CI_PKG"
  echo " first directory in package should be ci/ or bkci/, but got: $ci_pkg_first_dir"
  exit 1
fi

# 解压安装包
cd "$PKG_SRC_PATH"
if [ -d ci ]; then
  ci_bak_dir=../ci-bak-$(date +%Y%m%d-%H%M%S)  # 应该不会每秒生成多个ci-bak吧? ^_^
  echo "backup current ci dir to $ci_bak_dir"
  mv ci "$ci_bak_dir" || echo >&2 "NOTE: failed to backup."
  # 以防万一, 确保ci目录不存在.
  if [ -d "ci" ]; then
    echo "NOTE: ci dir still exist yet, maybe something wrong, try to delete it."
    rm -rf ci || { echo >&2 "ERROR: failed to delete dir: ci"; exit 1; }
  fi
fi
tar zxf "$CI_PKG"

# 调整安装包命名
if [ "$ci_pkg_first_dir" = "bkci/" ]; then
  mv bkci ci || { echo >&2 "ERROR: failed to rename bkci to ci."; exit 1; }
fi

# 删除mysql flag
echo "try to clean up mysql flag."
clean_migrate_flag() {
  local flag_file=$HOME/.migrate/$1
  if [ -f "$flag_file" ]; then
    chattr -i "$flag_file" && rm "$flag_file"
  fi
}
for f in "$PKG_SRC_PATH"/ci/support-files/sql/*_mysql.sql; do
  clean_migrate_flag "${f##*/}"
done

echo "prepare finished. enjoy! ^_^"
