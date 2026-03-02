#ARG DISTRO="archlinux"
#ARG DISTRO="alpine"
ARG DISTRO="ubuntu"
ARG DISTRO_VERSION="latest"

FROM $DISTRO:$DISTRO_VERSION

ARG DISTRO
ENV DEPS_DISTRO=$DISTRO

WORKDIR /gha
COPY --from=gha prepare .
RUN ./prepare -u

COPY --from=gha deps deps.toml .
RUN ./deps -b

WORKDIR /workdir
ADD fetch .
ADD texlive.json texlive.profile .
ADD texhelp install.sh .

#ENV TEXHELP_MIRROR=https://mirrors.mit.edu/CTAN
#ENV TEXHELP_MIRROR=https://mirror.bahnhof.net/pub/ctan
#ENV TEXHELP_MIRROR=https://mirror.math.princeton.edu/pub/CTAN
#ENV TEXHELP_HISTORIC_MIRROR=https://ftp.math.utah.edu/pub/tex
RUN ./install.sh

RUN /gha/deps -t
COPY --from=gha test.sh .
RUN ./test.sh .texhelp
