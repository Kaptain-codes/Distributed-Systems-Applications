FROM ballerina/ballerina:2201.12.9
# Build outside /home/ballerina: the base image declares it a VOLUME, so Compose would
# keep serving the old jar from that volume after a rebuild.
USER root
RUN mkdir -p /app && chown ballerina /app
USER ballerina
WORKDIR /app
COPY Ballerina.toml .
COPY service.bal .
RUN bal build
EXPOSE 8080
CMD ["java", "-jar", "target/bin/gateway.jar"]
