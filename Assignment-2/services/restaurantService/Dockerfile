FROM ballerina/ballerina:2201.13.4 AS build
WORKDIR /app
COPY --chown=ballerina:ballerina . .
RUN bal build

FROM eclipse-temurin:21-jre-jammy
WORKDIR /app
COPY --from=build /app/target/bin/*.jar app.jar
EXPOSE 9090
ENTRYPOINT ["java", "-jar", "app.jar"]
