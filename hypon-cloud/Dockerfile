FROM ghcr.io/home-assistant/aarch64-base:latest

RUN apk add --no-cache mosquitto-clients

# Copy data for add-on
COPY run.sh /
COPY scripts/ /scripts/

RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
