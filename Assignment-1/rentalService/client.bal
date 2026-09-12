import ballerina/io;

public function main() returns error? {
    // Initialize the gRPC client pointing to your running rentalService port (9091)
    RentalServiceClient ep = check new ("http://localhost:9091");

    io:println("gRPC Client initialized successfully, ready to call remote methods.");
}