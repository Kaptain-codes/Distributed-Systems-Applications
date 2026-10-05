import ballerina/file;
import ballerina/io;

const string stateDirectory = ".food-delivery-client";
const string statePath = ".food-delivery-client/state.json";

function loadState() returns ClientState {
    string|error contents = io:fileReadString(statePath);
    if contents is error {
        return {baseUrl, pollMs};
    }
    json|error raw = contents.fromJsonString();
    if raw is error || !(raw is map<json>) {
        io:println("[ERR] invalid state file " + statePath);
        return {baseUrl, pollMs};
    }
    ClientState|error decoded = <ClientState>raw;
    return decoded is ClientState ? decoded : {baseUrl, pollMs};
}

function saveState(ClientState state) returns error? {
    error? directoryResult = file:createDir(stateDirectory);
    if directoryResult is error {
        return directoryResult;
    }
    return io:fileWriteString(statePath, state.toJsonString());
}

function clearState() returns error? {
    return file:remove(statePath);
}

function stateSummary(ClientState state) returns string {
    return string `customer: ${state.customerId ?: "—"}  address: ${state.addressId ?: "—"}  base: ${state.baseUrl}`;
}
