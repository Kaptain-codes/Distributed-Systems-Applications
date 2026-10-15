FROM ballerina/ballerina:2201.12.9
# Build outside /home/ballerina: the base image declares it a VOLUME, so Compose would
# keep serving the old jar from that volume after a rebuild.
USER root
RUN mkdir -p /app && chown ballerina /app
USER ballerina
WORKDIR /app
COPY --chown=ballerina Ballerina.toml Dependencies.toml ./
COPY --chown=ballerina *.bal ./
RUN bal build
EXPOSE 9090
# Settings (port, MongoDB, Kafka) come from the BAL_CONFIG_DATA environment variable.
CMD ["java", "-jar", "target/bin/restaurantService.jar"]
