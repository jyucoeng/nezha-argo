FROM debian

# 脚本源仓库（fork 后可由 workflow 自动传入 --build-arg GITHUB_SOURCE=<你的仓库>，无需修改本文件）
ARG GITHUB_SOURCE=jyucoeng/nezha-argo

WORKDIR /dashboard

RUN apt-get update &&\
    apt-get -y install openssh-server wget curl iproute2 vim git cron unzip supervisor nginx sqlite3 &&\
    git config --global core.bigFileThreshold 1k &&\
    git config --global core.compression 0 &&\
    git config --global advice.detachedHead false &&\
    git config --global pack.threads 1 &&\
    git config --global pack.windowMemory 50m &&\
    apt-get clean &&\
    rm -rf /var/lib/apt/lists/* &&\
    echo "#!/usr/bin/env bash\n\n\
bash <(wget -qO- https://raw.githubusercontent.com/${GITHUB_SOURCE}/main/init.sh)" > entrypoint.sh &&\
    chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]