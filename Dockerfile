# Base image pinned by digest so rebuilds start from the same root filesystem.
# To bump: look up the new digest for the tag and replace it here deliberately.
FROM alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc

# Third-party sources pinned so a rebuild cannot silently pick up new code.
# brlaser: last upstream commit (2023-02-20, "Merge pull request #133").
ARG BRLASER_COMMIT=2a49e3287c70c254e7e3ac9dabe9d6a07218c3fa
ARG GUTENPRINT_VERSION=5.3.5
ARG GUTENPRINT_SHA256=f5a9f47de28530b1ae2069cfbc647a9a641baeeabe809bb0ef2b3ec5b9668d70

# Install the packages we need. Avahi will be included
RUN echo -e "https://dl-cdn.alpinelinux.org/alpine/edge/testing\nhttps://dl-cdn.alpinelinux.org/alpine/edge/community\nhttps://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories &&\
	apk add --update cups \
	cups-libs \
	cups-pdf \
	cups-client \
	cups-filters \
	cups-dev \
	gcompat \
	ghostscript \
	hplip \
	avahi \
	dbus \
	inotify-tools \
	python3 \
	build-base \
	wget \
	perl \
	splix \
	tzdata \
	&& rm -rf /var/cache/apk/*

# Build and install brlaser from source
RUN apk add --no-cache git cmake && \
    git clone https://github.com/pdewacht/brlaser.git && \
    cd brlaser && \
    git checkout --detach "$BRLASER_COMMIT" && \
    cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 . && \
    make && \
    make install && \
    cd .. && \
    rm -rf brlaser

# Build and install gutenprint from source
RUN wget -O gutenprint-${GUTENPRINT_VERSION}.tar.xz https://sourceforge.net/projects/gimp-print/files/gutenprint-5.3/${GUTENPRINT_VERSION}/gutenprint-${GUTENPRINT_VERSION}.tar.xz/download && \
    echo "${GUTENPRINT_SHA256}  gutenprint-${GUTENPRINT_VERSION}.tar.xz" | sha256sum -c - && \
    tar -xJf gutenprint-${GUTENPRINT_VERSION}.tar.xz && \
    cd gutenprint-${GUTENPRINT_VERSION} && \
    # Patch to rename conflicting PAGESIZE identifiers to GPT_PAGESIZE in all files in src/testpattern
    find src/testpattern -type f -exec sed -i 's/\bPAGESIZE\b/GPT_PAGESIZE/g' {} + && \
    ./configure && \
    make -j$(nproc) && \
    make install && \
    cd .. && \
    rm -rf gutenprint-${GUTENPRINT_VERSION} gutenprint-${GUTENPRINT_VERSION}.tar.xz && \
    # Fix cups-genppdupdate script shebang
    sed -i '1s|.*|#!/usr/bin/perl|' /usr/sbin/cups-genppdupdate

# This will use port 631
EXPOSE 631

# We want a mount for these
VOLUME /config

# Add scripts
ADD root /
RUN chmod +x /root/*

#Run Script
CMD ["/root/run_cups.sh"]

# Baked-in config file changes
RUN sed -i 's/Listen localhost:631/Listen 0.0.0.0:631/' /etc/cups/cupsd.conf && \
	sed -i 's/Browsing Off/Browsing On/' /etc/cups/cupsd.conf && \
 	sed -i 's/IdleExitTimeout/#IdleExitTimeout/' /etc/cups/cupsd.conf && \
	sed -i 's/<Location \/>/<Location \/>\n  Allow All/' /etc/cups/cupsd.conf && \
	sed -i 's/<Location \/admin>/<Location \/admin>\n  Allow All\n  Require user @SYSTEM/' /etc/cups/cupsd.conf && \
	sed -i 's/<Location \/admin\/conf>/<Location \/admin\/conf>\n  Allow All/' /etc/cups/cupsd.conf && \
	sed -i 's/.*enable\-dbus=.*/enable\-dbus\=yes/' /etc/avahi/avahi-daemon.conf && \
	echo "ServerAlias *" >> /etc/cups/cupsd.conf && \
	echo "DefaultEncryption Never" >> /etc/cups/cupsd.conf && \
	echo "ReadyPaperSizes A4,TA4,4X6FULL,T4X6FULL,2L,T2L,A6,A5,B5,L,TL,INDEX5,8x10,T8x10,4X7,T4X7,Postcard,TPostcard,ENV10,EnvDL,ENVC6,Letter,Legal" >> /etc/cups/cupsd.conf && \
	echo "DefaultPaperSize Letter" >> /etc/cups/cupsd.conf && \
	echo "pdftops-renderer ghostscript" >> /etc/cups/cupsd.conf
