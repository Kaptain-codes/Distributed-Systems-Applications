import ballerina/http;
import ballerina/io;
import ballerina/time;
import ballerina/url;

// Overall state of a physical/electronic asset.
public enum AssetStatus {
    AVAILABLE,
    OCCUPIED,
    UNDER_MAINTENANCE,
    DISPOSED
}

// What kind of schedule entry this is: a routine check, a repair, or a booking/loan.
public enum ScheduleType {
    ROUTINE_SERVICE,
    MAINTENANCE,
    BOOKING
}

// Lifecycle state of a single schedule entry.
public enum ScheduleStatus {
    PENDING,
    ACTIVE,
    COMPLETED,
    CANCELLED,
    OVERDUE 
}

// State of a sub-component belonging to an asset (e.g. a printer's motor).
public enum ComponentStatus {
    AVAILABLE,
    IN_USE,
    UNDER_MAINTENANCE,
    DISPOSED
}

// Lifecycle state of a work order (a repair/maintenance ticket).
public enum WorkOrderStatus{
    OPEN,
    IN_PROGRESS,
    CLOSED
}

// DATA TYPES
// These are "records" — Ballerina's way of describing a JSON shape.

// A single loan/maintenance/booking entry attached to an asset.
type Schedule record {|
    string scheduleId;
    ScheduleType scheduleType;
    ScheduleStatus scheduleStatus;
    time:Utc startTime;
    time:Utc dueDate;
    string description;
|};

// A sub-part of a larger asset (e.g. a printer's motor, a laptop's battery).
type Component record {|
    string componentId;
    string name;
    string description;
    string dateAcquired;
    ComponentStatus status;
|};

// A single to-do item inside a work order (e.g. "replace screen").
type Task record {|
    string taskId;
    string description;
|};

// A repair/maintenance ticket raised against an asset.
type WorkOrder record {|
    string workOrderId;
    string description;
    WorkOrderStatus status;
    time:Utc createdAt;
    time:Utc? completedAt; // optional — null until the work order is actually closed
    Task[] tasks;
|};

// The main resource this client manages: a physical or electronic asset (e.g. a printer, a laptop, a microscope).
type Asset record {|
    string assetTag;      // unique identifier for the asset
    string name;
    string description;
    string institutionId; // which institution owns/holds this asset (e.g. "NUST")
    string site;          // which campus/site within that institution
    string dateAcquired;
    AssetStatus status = AVAILABLE; // defaults to AVAILABLE if the server omits it
    Schedule[] schedules;
    Component[] components;
    WorkOrder[] workOrders;
|};

public function main() returns error? {
    http:Client backend = check new ("http://localhost:9090");
    boolean running = true;

    // Main menu loop: keeps showing options until the user picks "0" (Exit).
    while running {
        io:println("1.Global View");
        io:println("2.Campus View");
        io:println("3.Overdue Dashboard");
        io:println("4.Loan and Return");
        io:println("5.Schedule Manager");
        io:println("0.Exit");

        string choice = io:readln();

        // Each case is wrapped in `check` — if a feature function fails
        // unrecoverably, the whole program stops rather than looping forever
        // in a broken state.
        match choice {
            "1" => {check globalView(backend);}
            "2" => {check campusView(backend);}
            "3" => {check overdueDashboard(backend);}
            "4" => {check loanAndReturn(backend);}
            "5" => {check scheduleManager(backend);}
            "0" => {running = false;}
            _ => {io:println("Invalid choice");}
        }
    }

}

//====================================================================
// SHARED HELPERS
//====================================================================

// Fetches a list of assets from any GET endpoint that returns Asset[]
// (used by Global View, Campus View, and Overdue Dashboard alike).
function getAssets(http:Client backend, string path) returns Asset[]|error {
    http:Request request = new;
    request.setHeader("Accept", "application/json");
    
    http:Response response = check backend->execute("GET", path, request);
    
    if response.statusCode == 200 {
        json payload = check response.getJsonPayload();
        Asset[] result = check payload.cloneWithType();
        return result;
    } else if response.statusCode == 404 {
        // Some endpoints (like /assets/overdue) respond with 404 when there's
        // simply nothing to return — treat that as an empty list, not a failure.
        return [];
    } else {
        // Any other non-2xx status is a genuine problem — turn it into an
        // error so the caller can decide how to handle/report it.
        return error(string `HTTP ${response.statusCode}: ${response.reasonPhrase}`);
    }
}

// Prints one asset's key fields in a single readable line.
// Array fields (schedules/components/workOrders) are summarized by count
// rather than printed in full, to keep each line scannable.
function printAsset(Asset a) {
    io:println(a.assetTag, "|", a.name, "|", a.description, "|",
            a.institutionId, "|", a.site, "|", a.dateAcquired, "|", a.status,
            "| Schedules: ", a.schedules.length(), 
            "| Components: ", a.components.length(),
            "| WorkOrders: ", a.workOrders.length());
}

// Shared success/failure handler for every POST/PUT call in this file.
function handleResponse(http:Response response, string successMessage) returns error? {
    if response.statusCode >= 200 && response.statusCode < 300 {
        io:println(successMessage);
        return;
    } else {
        // Try to surface whatever error message the server sent back,
        // falling back to the generic HTTP reason phrase if there isn't one.
        string|error payload = response.getTextPayload();
        string errorMessage;
        if payload is string {
            errorMessage = payload;
        } else {
            errorMessage = response.reasonPhrase;
        }
        io:println("Failed (",response.statusCode,"):", errorMessage);
    }
}

// FEATURE 1: GLOBAL VIEW
function globalView(http:Client backend) returns error? {
    Asset[] assets = check getAssets(backend, "/assets");
    if assets.length() == 0 {
        io:println("No assets found.");
        return;
    }
    foreach Asset a in assets {
        printAsset(a);
    }
}

// FEATURE 2: CAMPUS VIEW
function campusView(http:Client backend) returns error? {
    io:println("Institution ID: (blank to skip): ");
    string institutionId = io:readln();
    io:println("Site: (blank to skip): ");
    string site = io:readln();

    string path;
    // Build the correct query string depending on which filters were given.
    // Values are URL-encoded so spaces/special characters (like "Main Campus")
    // don't break the query string.
    if institutionId != "" && site != "" {
        string encodedInstitutionId = check url:encode(institutionId, "UTF-8");
        string encodedSite = check url:encode(site, "UTF-8");
        path = string `/assets/filtered?institutionId=${encodedInstitutionId}&site=${encodedSite}`;
    } else if institutionId != "" {
        string encodedInstitutionId = check url:encode(institutionId, "UTF-8");
        path = string `/assets/filtered?institutionId=${encodedInstitutionId}`;
    } else if site != "" {
        string encodedSite = check url:encode(site, "UTF-8");
        path = string `/assets/filtered?site=${encodedSite}`;
    } else {
        // No filters given at all — just show everything, same as Global View.
        io:println("No filters provided. Showing all assets.");
        path = "/assets";
    }
    
    Asset[] assets = check getAssets(backend, path);
    if assets.length() == 0 {
        io:println("No assets found for the filter.");
        return;
    }
    foreach Asset a in assets {
        printAsset(a);
    }
}

// FEATURE 3: OVERDUE DASHBOARD
// Shows only assets whose maintenance/booking schedule has passed its due date.
function overdueDashboard(http:Client backend) returns error? {
    Asset[] assets = check getAssets(backend, "/assets/overdue");
    if assets.length() == 0 {
        io:println("No overdue assets.");
        return;
    }
    foreach Asset a in assets {
        printAsset(a);
    }
}

// FEATURE 4: LOAN AND RETURN
// Sub-menu that lets the user either loan out an asset or return one
// that's currently on loan.
function loanAndReturn(http:Client backend) returns error? {
    io:println("1. Loan Asset");
    io:println("2. Return Asset");
    io:println("0. Back to Main Menu");
    string choice = io:readln();

    match choice {
        "1" => {
            io:println("Enter Asset Tag: ");
            string assetTag = io:readln();
            check loanAsset(backend, assetTag);
            
        }
        "2" => {
            io:println("Enter Asset Tag: ");
            string assetTag = io:readln();
            io:println("Enter Schedule ID of the loan to be returned: ");
            string scheduleId = io:readln();
            check returnAsset(backend, assetTag, scheduleId);
        }
        "0" => {
            // Selecting back to main menu: do nothing and let this function
            // end naturally — main()'s loop will show the top-level menu again.
            io:println("Returning to main menu.");
        }
        _ => {
            io:println("Invalid choice");
        }
    }
}

// Loans out a single asset by creating a BOOKING-type Schedule and POSTing
// it to the asset's /loan endpoint.
function loanAsset(http:Client backend, string assetTag) returns error? {
    io:println("Due date (YYYY-MM-DD): ");
    string dueDateInput = io:readln();

    if dueDateInput == "" {
        io:println("Due date cannot be empty.");
        return;
    }

    // Convert the plain date string into Ballerina's time:Utc type — the
    // server expects a proper Utc value here, not a raw string.
    time:Utc dueDate = check time:utcFromString(dueDateInput + "T00:00:00Z");

    // scheduleId is generated locally rather than by the server, since the
    // /loan endpoint expects a fully-formed Schedule object as its payload.
    Schedule newSchedule = {
        scheduleId: "SCH-" + assetTag + "-" + dueDateInput,
        scheduleType: BOOKING,
        scheduleStatus: PENDING,
        startTime: time:utcNow(),
        dueDate: dueDate,
        description: "Loaned asset"
    };

    // This only catches transport-level failures (server down, bad connection).
    http:Response|error response = backend->post(string `/assets/${assetTag}/loan`, newSchedule);

    // This is what actually checks whether the SERVER accepted the loan
    // (e.g. rejects a bad assetTag with a 404).
    if response is error {
        io:println("Error occurred while loaning the asset: ", response.message());
        return;
    }

    check handleResponse(response, "Asset Loaned successfully.");
}

// Closes out an existing loan. The server only needs the scheduleId to know
// which loan to close — the rest of the Schedule fields are placeholders,
// required only because the endpoint's payload type is the full Schedule record.
function returnAsset(http:Client backend, string assetTag, string scheduleId) returns error? {
    Schedule closingSchedule = {
        scheduleId: scheduleId,
        scheduleType: BOOKING,
        scheduleStatus: COMPLETED,
        startTime: time:utcNow(),
        dueDate: time:utcNow(),
        description: "Returned asset"
    };

    http:Response|error response = backend->post(string `/assets/${assetTag}/return`, closingSchedule);
    if response is error {
        io:println("Error occurred while returning the asset: ", response.message());
        return;
    }
    check handleResponse(response, "Asset returned successfully.");
}

// FEATURE 5: SCHEDULE MANAGER
// Lets the user add or partially update a maintenance/service schedule.
function scheduleManager(http:Client backend) returns error? {
    io:println("1. Create Schedule");
    io:println("2. Update Schedule");
    io:println("0. Back to Main Menu");
    string choice = io:readln();

    match choice {
        "1" => {
            io:println("Enter Asset Tag: ");
            string assetTag = io:readln();
            check createSchedule(backend, assetTag);
        }
        "2" => {
            io:println("Enter Asset Tag: ");
            string assetTag = io:readln();
            io:println("Enter Schedule ID: ");
            string scheduleId = io:readln();
            check updateSchedule(backend, assetTag, scheduleId);
        }
        "0" => {
            io:println("Returning to main menu.");
        }
        _ => {
            io:println("Invalid choice");
            }
    }
}

// Builds a new Schedule (of any type — routine service, maintenance, or
// booking) from user input and POSTs it to the asset's /schedules endpoint.
function createSchedule(http:Client backend, string assetTag) returns error? {
    io:println("Enter Schedule Type (ROUTINE_SERVICE, MAINTENANCE, BOOKING): ");
    string scheduleTypeInput = io:readln();

    // scheduleType must be declared with a placeholder value up front —
    // Ballerina's compiler can't always prove every branch of a `match`
    // assigns it, even when the logic guarantees it (every branch here
    // either assigns it or returns early).
    ScheduleType scheduleType = BOOKING;
    match scheduleTypeInput {
        "MAINTENANCE" => {scheduleType = MAINTENANCE;}
        "ROUTINE_SERVICE" => {scheduleType = ROUTINE_SERVICE;}
        "BOOKING" => {scheduleType = BOOKING;}
        _ => {
            io:println("Invalid schedule type"); 
            return;
        }
    }

    ScheduleStatus scheduleStatus = PENDING;

    io:println("Enter Start Time (YYYY-MM-DD): ");
    string startTimeInput = io:readln();
    time:Utc startTime = check time:utcFromString(startTimeInput + "T00:00:00Z");

    io:println("Enter Due Date (YYYY-MM-DD): ");
    string dueDateInput = io:readln();
    time:Utc dueDate = check time:utcFromString(dueDateInput + "T00:00:00Z");

    io:println("Enter Description: ");
    string description = io:readln();

    Schedule newSchedule = {
        scheduleId: "SCH-" + assetTag + "-" + dueDateInput,
        scheduleType: scheduleType,
        scheduleStatus: scheduleStatus,
        startTime: startTime,
        dueDate: dueDate,
        description: description
    };

    http:Response|error response = backend->post(string `/assets/${assetTag}/schedules`, newSchedule);

    if response is error {
        io:println("Error occurred while creating the schedule: ", response.message());
        return;
    }
    check handleResponse(response, "Schedule created successfully.");
}

type ScheduleUpdate record {|
    ScheduleType? scheduleType = ();
    ScheduleStatus? scheduleStatus = ();
    time:Utc? startTime = ();
    time:Utc? dueDate = ();
    string? description = ();
|};

function updateSchedule(http:Client backend, string assetTag, string scheduleId) returns error? {
    io:println("Enter Schedule Type (blank to skip): ");
    string scheduleTypeInput = io:readln();
    io:println("Enter Schedule Status (blank to skip): ");
    string scheduleStatusInput = io:readln();
    io:println("Enter Start Time (YYYY-MM-DD, blank to skip): ");
    string startTimeInput = io:readln();
    io:println("Enter Due Date (YYYY-MM-DD, blank to skip): ");
    string dueDateInput = io:readln();
    io:println("Enter Description (blank to skip): ");
    string descriptionInput = io:readln();

    ScheduleUpdate update = {};
    if scheduleTypeInput != "" {
        match scheduleTypeInput {
            "ROUTINE_SERVICE" => {update.scheduleType = ROUTINE_SERVICE;}
            "MAINTENANCE" => {update.scheduleType = MAINTENANCE;}
            "BOOKING" => {update.scheduleType = BOOKING;}
            _ => {
                io:println("Invalid schedule type");
                return;
            }
        }
    }
    if scheduleStatusInput != "" {
        match scheduleStatusInput {
            "PENDING" => {update.scheduleStatus = PENDING;}
            "ACTIVE" => {update.scheduleStatus = ACTIVE;}
            "COMPLETED" => {update.scheduleStatus = COMPLETED;}
            "CANCELLED" => {update.scheduleStatus = CANCELLED;}
            "OVERDUE" => {update.scheduleStatus = OVERDUE;}
            _ => {
                io:println("Invalid schedule status");
                return;
            }
        }
    }
    if startTimeInput != "" {
        update.startTime = check time:utcFromString(startTimeInput + "T00:00:00Z");
    }
    if dueDateInput != "" {
        update.dueDate = check time:utcFromString(dueDateInput + "T00:00:00Z");
    }
    if descriptionInput != "" {
        update.description = descriptionInput;
    }

    http:Response|error response = backend->put(
        string `/assets/${assetTag}/schedules/${scheduleId}`, update);
    if response is error {
        io:println("Error occurred while updating the schedule: ", response.message());
        return;
    }
    check handleResponse(response, "Schedule updated successfully.");
}