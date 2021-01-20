##############################################################
# App: Branch clean up for AWS clusters
##############################################################
FROM amazon/aws-cli:2.1.19 AS kube-branch-cleaner-aws

RUN yum install -y jq curl bash \
  && yum clean all
COPY aws/cleanup.sh /opt/cleanup.sh
CMD ["/opt/cleanup.sh"]

# Remove default AWS CLI entrypoint
ENTRYPOINT []

##############################################################
# App: Branch clean up for base-metal clusters
##############################################################
FROM alpine:3.12.0 AS kube-branch-cleaner-bare-metal

ARG USER=cleaner
ENV HOME /home/$USER

RUN adduser -D $USER
RUN apk add --no-cache bash curl jq

USER $USER
WORKDIR $HOME

COPY bare-metal/cleanup.sh ./
CMD ["/home/alpine/cleanup.sh"]
