##############################################################
# App: Branch clean up for AWS clusters
##############################################################
FROM amazon/aws-cli:2.1.19 AS k8s-prune-aws

RUN yum install -y jq curl bash \
  && yum clean all
COPY aws/cleanup.sh /opt/cleanup.sh
CMD ["/opt/cleanup.sh"]

# Remove default AWS CLI entrypoint
ENTRYPOINT []
