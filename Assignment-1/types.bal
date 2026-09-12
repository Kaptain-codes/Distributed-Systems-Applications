import ballerina/time;

// Tracks the physical intent of why time if being blocked out
public enum ScheduleType {
    ROUTINE_SERVICE,    // Scheduled inspections, might need some oiling or sun
    MAINTENANCE,        // Something needs fixing
    BOOKING             // Reserved by someone
}
// Tracks the exact state of the time allocation slot
public enum ScheduleStatus {
    PENDING,    // Has been approved, not started yet
    ACTIVE,     // Currently in progress
    COMPLETED,  // Done and dusted
    CANCELLED,  // Aborted
    OVERDUE     // Passed its intended time
}
// Tracks the components on the assets
public enum ComponentStatus {
    AVAILABLE,          // Not being used
    IN_USE,             // Used self-explanatory
    UNDER_MAINTENANCE,  // Getting fixed
    DISPOSED            // Its prolly beyond repair or just not needed
}
// Tracks the high-level parent asset
public enum AssetStatus {
    AVAILABLE,          // Ready for use
    OCCUPIED,           // A patron is currently using it right now via a BOOKING
    UNDER_MAINTENANCE,  // Repairs mybroe
    DISPOSED            // Its prolly beyond repair or just not needed
}
# Lifecycle state of a repair job.
public enum WorkOrderStatus {
    OPEN,
    IN_PROGRESS,
    CLOSED
}

// Domain model for the Asset and Institution entities

public type Asset record {|
    readonly string assetTag;
    string name;
    string description; 
    string institutionId; // Shorten Code like NUST
    string site;
    string dateAcquired;
    AssetStatus status = AVAILABLE;
    Schedule[] schedules = [];
    Component[] components = [];
    WorkOrder[] workOrders = [];
|};

public type Institution record {|
    readonly string institutionId; // Shorten Code like NUST
    string name;
|};

public type WorkOrder record {|
    readonly string workOrderId;
    string description;
    WorkOrderStatus status = OPEN;
    time:Utc createdAt = time:utcNow();
    time:Utc? completedAt;
    Task[] tasks =[];
|};

public type Task record {|
    readonly string taskId;
    string description;
|};
// These records are used as arrays in the database tables, and are used to update the existing records in the database.

public type Component record {|
    readonly string componentId;
    string name;
    string description;
    string dateAcquired;
    ComponentStatus status;
|};

public type Schedule record {|
    readonly string scheduleId;
    ScheduleType scheduleType;
    ScheduleStatus scheduleStatus;
    time:Utc startTime; // This is used to identify the asset's date for the scheduling.
    time:Utc dueDate; // This is used to indicate the end of the schedule, and is used to determine if the schedule is overdue or not.
    string description;
|};

// User Input

// Updating Structures

public type AssetUpdate  record {|
    string? name = ();
    string? description = ();
    string? institutionId = ();
    string? site = ();
    string? dateAcquired = ();
    AssetStatus? status = ();
|} & readonly;

public type InstitutionUpdate record {|
    string name;
|}& readonly;

public type WorkOrderUpdate record {|   // ✅ closed record
    string? description = ();
    WorkOrderStatus? status = ();
    time:Utc? completedAt = ();
    Task[]? tasks = ();
|} & readonly;
