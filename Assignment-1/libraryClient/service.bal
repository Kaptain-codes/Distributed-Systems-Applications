import ballerina/http;
import ballerina/io;
import ballerina/time;

public enum AssetStatus {
    AVAILABLE,
    OCCUPIED,
    UNDER_MAINTENANCE,
    DISPOSED
}

public enum ScheduleType {
    ROUTINE_SERVICE,
    MAINTENANCE,
    BOOKING
}

public enum ScheduleStatus {
    PENDING,
    ACTIVE,
    COMPLETED,
    CANCELLED,
    OVERDUE 
}

public enum ComponentStatus {
    AVAILABLE,
    IN_USE,
    UNDER_MAINTENANCE,
    DISPOSED
}

public enum WorkOrderStatus{
    OPEN,
    IN_PROGRESS,
    CLOSED
}

type Schedule record {|
    string scheduleId;
    ScheduleType scheduleType;
    ScheduleStatus scheduleStatus;
    time:Utc startTime;
    time:Utc dueDate;
    string description;
|};

type Component record {|
    string componentId;
    string name;
    string description;
    string dateAcquired;
    ComponentStatus status;
|};

type Task record {|
    string taskId;
    string description;
|};

type WorkOrder record {|
    string workOrderId;
    string description;
    WorkOrderStatus status;
    time:Utc createdAt;
    time:Utc completedAt;
    Task[] tasks;
|};

type Asset record {|
    string assetTag;
    string name;
    string description;
    string institutionId;
    string site;
    string dateAcquired;
    AssetStatus status;
    Schedule[] schedules;
    Component[] components;
    WorkOrder[] workOrders;
|};

public function main() returns error? {
    http:Client backend = check new ("http://localhost:9090");
    boolean running = true;

    while running {
        io:println("1.Globel View");
        io:println("2.Campus View");
        io:println("3.Overdue Dashboard");
        io:println("4.Loan and Return");
        io:println("5.Schedule Manager");
        io:println("0.Exit");

        string choice = io:readln();

        match choice {
            "1" => {check globelView(backend);}
            "2" => {check campusView(backend);}
            "3" => {check overdueDashboard(backend);}
            "4" => {check loanAndReturn(backend);}
            "5" => {check scheduleManager(backend);}
            "0" => {running = false;}
            _ => {io:println("Invalid choice");}
        }
    }

}

function printAsset(Asset a) {
    io:println(a.assetTag, "|", a.name, "|", a.description, "|",
            a.institutionId, "|", a.site, "|", a.dateAcquired, "|", a.status,
            "| Schedules: ", a.schedules.length(), 
            "| Components: ", a.components.length(),
            "| WorkOrders: ", a.workOrders.length());
}

function globelView(http:Client backend) returns error? {
    
    Asset[] assets = check backend->get("/assets");
    if assets.length() == 0 {
        io:println("No assets found.");
        return;
    }
    foreach Asset a in assets {
        printAsset(a);
    }
}

function campusView(http:Client backend) returns error? {
    io:println("Institution ID: (blank to skip): ");
    string institutionId = io:readln();
    io:println("Site: (blank to skip): ");
    string site = io:readln();

    string path = string `/assets/filtered?institutionId=${institutionId}+&site=${site}`;
    Asset[] asset = check backend->get(path);

    foreach Asset a in asset {
        printAsset(a);
    }
}

function overdueDashboard(http:Client backend) returns error? {
    Asset[]|error result = backend->get("/assets/overdue");

    if result is error {
        io:println("Error occurred while fetching overdue assets.");
        return result;
    }

    Asset[] asset = check backend->get("/assets/overdue");
    foreach Asset a in asset {
        printAsset(a);
    }
}

function loanAndReturn(http:Client backend) returns error? {
    io:println("1. Loan Asset");
    io:println("2. Return Asset");
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
        _ => {
            io:println("Invalid choice");
        }
    }
}

function loanAsset(http:Client backend, string assetTag) returns error? {
    io:println("Due date (YYYY-MM-DD): ");
    string dueDateInput = io:readln();
    time:Utc dueDate = check time:utcFromString(dueDateInput + "T00:00:00Z");

    Schedule newSchedule = {
        scheduleId: "SCH-" + assetTag + "-" + dueDateInput,
        scheduleType: BOOKING,
        scheduleStatus: PENDING,
        startTime: time:utcNow(),
        dueDate: dueDate,
        description: "Loaned asset"
    };

    http:Response|error response = backend->post(string `/assets/${assetTag}/loan`, newSchedule);

    if response is error {
        io:println("Error occurred while loaning the asset: ", response.message());
        return;
    }
    io:println("Asset loaned successfully.");
}

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
    io:println("Asset returned successfully.");
}

function scheduleManager(http:Client backend) returns error? {
    io:println("1. Create Schedule");
    io:println("2. Update Schedule");
    string choice = io:readln();

    match choice {
        "1" => {
            io:println("Enter Asset Tag: ");
            string assetTag = io:readln();
            check createSchedule(backend, assetTag);
        }
        // "2" => {
        //     io:println("Enter Asset Tag: ");
        //     string assetTag = io:readln();
        //     io:println("Enter Schedule ID: ");
        //     string scheduleId = io:readln();
        //     check updateSchedule(backend, assetTag, scheduleId);
        // }
        _ => {
            io:println("Invalid choice");
            }
    }
}

function createSchedule(http:Client backend, string assetTag) returns error? {
    io:println("Enter Schedule Type (ROUTINE_SERVICE, MAINTENANCE, BOOKING): ");
    string scheduleTypeInput = io:readln();

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
    io:println("Schedule created successfully.");
}

// function updateSchedule(http:Client backend, string assetTag, string scheduleId) returns error? {
//     io:println("Enter Schedule Status (PENDING, ACTIVE, COMPLETED, CANCELLED, OVERDUE): ");
//     string scheduleStatusInput = io:readln();

//     ScheduleStatus scheduleStatus;
//     match scheduleStatusInput {
//         PENDING => {scheduleStatus = PENDING;}
//         ACTIVE => {scheduleStatus = ACTIVE;}
//         COMPLETED => {scheduleStatus = COMPLETED;}
//         CANCELLED => {scheduleStatus = CANCELLED;}
//         OVERDUE => {scheduleStatus = OVERDUE;}
//         _ => {
//             io:println("Invalid schedule status"); 
//             return;
//         }
//     }

//     Schedule updatedSchedule = {
//         scheduleId: scheduleId,
//         scheduleType: BOOKING,
//         scheduleStatus: scheduleStatus,
//         startTime: time:utcNow(),
//         dueDate: time:utcNow(),
//         description: "Updated schedule"
//     };

//     http:Response|error response = backend->put(string `/assets/${assetTag}/schedules/${scheduleId}`, updatedSchedule);

//     if response is error {
//         io:println("Error occurred while updating the schedule: ", response.message());
//         return;
//     }
//     io:println("Schedule updated successfully.");
// }