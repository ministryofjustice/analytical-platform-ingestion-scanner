#checkov:skip=CKV_DOCKER_2: HEALTHCHECK not required - AWS Lambda does not support HEALTHCHECK
#checkov:skip=CKV_DOCKER_3: USER not required - A non-root user is used by AWS Lambda
FROM public.ecr.aws/lambda/provided@sha256:35ef3ebbb1aa85d66a977b47ac5cbe4b185861e8e60d86e25fbc6f5e012e60da

LABEL org.opencontainers.image.vendor="Ministry of Justice" \
      org.opencontainers.image.authors="Analytical Platform (analytical-platform@digital.justice.gov.uk)" \
      org.opencontainers.image.title="Ingestion Scanner" \
      org.opencontainers.image.description="Ingestion scanner image for Analytical Platform" \
      org.opencontainers.image.url="https://github.com/ministryofjustice/analytical-platform"

ENV AWS_CLI_VERSION="2.15.23"

RUN microdnf update \
    && microdnf install --assumeyes \
         clamav-0.103.9-1.amzn2023.0.2.x86_64 \
         clamav-update-0.103.9-1.amzn2023.0.2.x86_64 \
         clamd-0.103.9-1.amzn2023.0.2.x86_64 \
         jq-1.6-10.amzn2023.0.2.x86_64 \
         tar-2:1.34-1.amzn2023.0.4.x86_64 \
         unzip-6.0-57.amzn2023.0.2.x86_64 \
    && microdnf clean all

# Amazon AWS CLI
RUN curl --location --fail-with-body \
         "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip" \
         --output "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm --force --recursive awscliv2.zip aws

COPY --chown=nobody:nobody --chmod=0755 src/var/runtime/ ${LAMBDA_RUNTIME_DIR}
COPY --chown=nobody:nobody --chmod=0755 src/var/task/ ${LAMBDA_TASK_ROOT}

CMD ["function.handler"]
