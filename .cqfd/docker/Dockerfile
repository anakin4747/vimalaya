FROM archlinux

RUN pacman -Syu --noconfirm \
    clamav \
    cloc \
    cocogitto \
    curl \
    git \
    himalaya \
    make \
    neovim \
    sudo \
    which

COPY plenary-patches /plenary-patches

RUN mkdir -p /usr/local/share/nvim/site/pack/plenary/start && \
    cd /usr/local/share/nvim/site/pack/plenary/start && \
    git clone --depth 1 https://github.com/nvim-lua/plenary.nvim.git && \
    git -C plenary.nvim apply /plenary-patches/*.patch
