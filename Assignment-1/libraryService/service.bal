import ballerina/http;
import ballerina/task;

listener http:Listener httpListener = check new (9090);

service /assets on httpListener {

    function init() returns error? {
    // Schedules the background job to wake up and run every 300 seconds (5 minutes)
        task:JobId _ = check task:scheduleJobRecurByFrequency(
            new OverdueSchedulerJob(), 
            300
        );
    }
    
    isolated resource function post .(@http:Payload Asset payload) returns http:Created|http:InternalServerError|http:UnprocessableEntity|http:Conflict {
        Asset|error result = addAsset(payload);
        if result is AssetExists {
            return <http:Conflict>{body: string `Error adding asset: ${result.message()}`};
        }
        else if result is InstituteNotFound {
            return <http:UnprocessableEntity>{body: string `Error adding asset: ${result.message()}`};
        }
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Created>{body: result};
    }

    isolated resource function get overdue() returns http:Ok|http:InternalServerError|http:NotFound {
        Asset[] result = findOverdueAssets();
        if result.length() == 0 {
            return <http:NotFound>{body: string `No overdue assets found.`};
        }

        return <http:Ok>{body: result};
    }
    isolated resource function get [string assetTag]() returns http:Ok|http:InternalServerError|http:NotFound {
        Asset|error result = getAsset(assetTag);
        if result is AssetNotFound {
            return <http:NotFound>{body: string `Error retrieving asset: ${result.message()}`};
        }
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }
    isolated resource function put [string assetTag](@http:Payload AssetUpdate assetUpdate) returns http:Ok|http:InternalServerError|http:UnprocessableEntity|http:Conflict {
        Asset|error result = updateAsset(assetTag, assetUpdate);
        if result is AssetExists {
            return <http:Conflict>{body: string `Error updating asset: ${result.message()}`};
        }
        else if result is InstituteNotFound {
            return <http:UnprocessableEntity>{body: string `Error updating asset: ${result.message()}`};
        }
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }
    isolated resource function delete [string assetTag]() returns http:Ok|http:InternalServerError|http:NotFound {
        Asset|error result = deleteAsset(assetTag);
        if result is AssetNotFound {
            return <http:NotFound>{body: string `Error deleting asset: ${result.message()}`};
        }
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }
    
    isolated resource function get .() returns http:Ok|http:InternalServerError {
        Asset[] result = getAllAssets();
        if result.length() == 0 {
            return <http:Ok>{body: string `No assets found.`};
        }

        return <http:Ok>{body: result};
    }

    // Filtering assets by institutionId and site
    isolated resource function get institute(string institutionId) returns http:Ok|http:InternalServerError|http:NotFound {
        Asset[] result = getAssetsByInstitution(institutionId);
        if result.length() == 0 {
            return <http:NotFound>{body: string `No assets found with institution ID: ${institutionId}`};
        }

        return <http:Ok>{body: result};
    }

    isolated resource function get site(string site) returns http:Ok|http:NotFound|http:InternalServerError {
        Asset[] result = getAssetsBySite(site);
        if result.length() == 0 {
            return <http:NotFound>{body: string `No assets found with site: ${site}`};
        }

        return <http:Ok>{body: result};
    }
    
    isolated resource function get status(AssetStatus status) returns http:Ok|http:InternalServerError|http:NotFound {
        Asset[] result = getAssetsByStatus(status);
        if result.length() == 0 {
            return <http:NotFound>{body: string `No assets found with status: ${status}`};
        }

        return <http:Ok>{body: result};
        
    }

    isolated resource function get filtered(string? institutionId = (), string? site = (), AssetStatus? status = ())
    returns http:Ok|http:NotFound|http:BadRequest {

    if institutionId is () && site is () && status is () {
        return <http:BadRequest>{
            body: "At least one filter parameter (institutionId, site, or status) must be provided."
        };
    }

    Asset[] result = getAssetsByFilters(institutionId, site, status);
    if result.length() == 0 {
        return <http:NotFound>{body: string `No assets found with the provided filters.`};
    }

    return <http:Ok>{body: result};
}


    // SUB-RESOURCE MANAGEMENT

    isolated resource function post [string assetTag]/components(@http:Payload Component component) returns http:Ok|http:InternalServerError|http:NotFound|http:Conflict|http:UnprocessableEntity {
        Asset|error result = addComponentToAsset(assetTag, component);
        if result is AssetNotFound {
            return <http:NotFound>{body: string `Error adding asset: ${result.message()}`};
        } else if result is AssetDisposed {
            return <http:UnprocessableEntity>{body: string `Error adding component: ${result.message()}`};
        } else if result is ComponentExists {
            return <http:Conflict>{body: string `Error adding component: ${result.message()}`};
        } 
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    } 
    isolated resource function delete [string assetTag]/components/[string componentId]() returns http:Ok|http:InternalServerError|http:UnprocessableEntity|http:NotFound {
        Component|error result = removeComponentFromAsset(assetTag, componentId);
        if result is AssetNotFound {
            return <http:NotFound>{body: string `Error deleting component: ${result.message()}`};
        } else if result is AssetDisposed {
            return <http:UnprocessableEntity>{body: string `Error deleting component: ${result.message()}`};
        } else if result is ComponentNotFound {
            return <http:NotFound>{body: string `Error deleting component: ${result.message()}`};
        } 
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    } 
    isolated resource function post [string assetTag]/schedules(@http:Payload Schedule schedule) returns http:Ok|http:InternalServerError|http:Conflict|http:NotFound {
        Asset|error result = addSchedule(assetTag, schedule);
        if result is AssetNotFound {
            return <http:NotFound>{body: string `Error adding schedule: ${result.message()}`};
        } else if result is ScheduleExists {
            return <http:Conflict>{body: string `Error adding schedule: ${result.message()}`};
        } 
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }
    isolated resource function delete [string assetTag]/schedules/[string scheduleId]() returns http:Ok|http:InternalServerError|http:NotFound {
        Schedule|error result = removeSchedule(assetTag, scheduleId);
        if result is AssetNotFound {
            return <http:NotFound>{body: string `Error deleting schedule: ${result.message()}`};
        } else if result is ScheduleNotFound {
            return <http:NotFound>{body: string `Error deleting schedule: ${result.message()}`};
        } 
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};  
    }
    isolated resource function post [string assetTag]/workorders(@http:Payload WorkOrder workOrder) returns http:Ok|http:InternalServerError|http:UnprocessableEntity|http:NotFound|http:Conflict {
        Asset|error result = addWorkOrder(assetTag, workOrder);
        if result is AssetNotFound {
            return <http:NotFound>{body: string `Error adding work order: ${result.message()}`};
        } else if result is WorkOrderAndScheduleExists {
            return <http:Conflict>{body: string `Error adding work order: ${result.message()}`};
        } else if result is AssetDisposed {
            return <http:UnprocessableEntity>{body: string `Error adding work order: ${result.message()}`};
        } 
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }
    isolated resource function put [string assetTag]/workorders/[string workOrderId](@http:Payload WorkOrderUpdate workOrderUpdate) returns http:Ok|http:InternalServerError|http:NotFound {
        Asset|error result = updateWorkOrder(assetTag, workOrderId, workOrderUpdate);
        if result is AssetNotFound {
            return <http:NotFound>{body: string `Error updating work order: ${result.message()}`};
        } else if result is WorkOrderNotFound {
            return <http:NotFound>{body: string `Error updating work order: ${result.message()}`};
        } 
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }
    isolated resource function patch [string assetTag]/workorders/[string orderId]() returns http:NotFound|http:InternalServerError|http:UnprocessableEntity|http:Ok {
        WorkOrder|error result = completeWorkOrder(assetTag, orderId);
        if result is AssetNotFound {
            return <http:NotFound>{ body: string `Error closing work order'${result.message()}'`};
        } else if result is WorkOrderNotFound {
            return <http:NotFound>{ body: string `Error closing work order'${result.message()}'`};
        }else if result is ScheduleNotFound {
            return <http:NotFound>{ body: string `Error closing work order'${result.message()}'`};
        } else if result is WorkOrderClosed {
            return <http:UnprocessableEntity>{ body: string `Error closing work order'${result.message()}'`};
        } 
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }
    isolated resource function post [string assetTag]/workorders/[string workOrderId]/tasks(@http:Payload Task task) returns http:Ok|http:InternalServerError|http:Conflict|http:UnprocessableEntity|http:NotFound {
        Task|error result = addTask(assetTag, workOrderId, task);
        if result is AssetNotFound {
            return <http:NotFound>{body: string `Error adding task: ${result.message()}`};
        } else if result is AssetDisposed {
            return <http:UnprocessableEntity>{body: string `Error adding task: ${result.message()}`};
        } else if result is WorkOrderNotFound {
            return <http:NotFound>{body: string `Error adding task: ${result.message()}`};
        }else if result is WorkOrderClosed {
            return <http:UnprocessableEntity>{body: string `Error adding task: ${result.message()}`};
        } else if result is TaskExists {
            return <http:Conflict>{body: string `Error adding task: ${result.message()}`};
        } 
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }
    isolated resource function delete [string assetTag]/workorders/[string workOrderId]/tasks/[string taskId]() returns http:Ok|http:InternalServerError|http:UnprocessableEntity|http:NotFound {
        Task|error result = removeTask(assetTag, workOrderId, taskId);
        if result is AssetNotFound {
            return <http:NotFound>{body: string `Error deleting task: ${result.message()}`};
        }else if result is AssetDisposed {
            return <http:UnprocessableEntity>{body: string `Error deleting task: ${result.message()}`};
        } else if result is WorkOrderNotFound {
            return <http:NotFound>{body: string `Error deleting task: ${result.message()}`};
        } else if result is WorkOrderClosed {
            return <http:UnprocessableEntity>{body: string `Error deleting task: ${result.message()}`};
        } else if result is TaskNotFound {
            return <http:NotFound>{body: string `Error deleting task: ${result.message()}`};
        } 
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }

    isolated resource function post [string assetTag]/loan(@http:Payload Schedule schedule) returns http:Ok|http:InternalServerError|http:UnprocessableEntity|http:NotFound|http:Conflict {
        Asset|error result = loanAsset(assetTag, schedule);
        if result is AssetNotFound {
            return <http:NotFound>{body: string `Error loaning asset: ${result.message()}`};
        } else if result is AssetDisposed {
            return <http:UnprocessableEntity>{body: string `Error loaning asset: ${result.message()}`};
        } else if result is AssetOccupied {
            return <http:Conflict>{body: string `Error loaning asset: ${result.message()}`};
        } else if result is AssetBlocked {
            return <http:Conflict>{body: string `Error loaning asset: ${result.message()}`};
        } else if result is InvalidAssetState {
            return <http:UnprocessableEntity>{body: string `Error loaning asset: ${result.message()}`};
        }
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }
    isolated resource function post [string assetTag]/'return(@http:Payload Schedule schedule) returns http:Ok|http:InternalServerError|http:UnprocessableEntity|http:NotFound|http:Conflict {
        Asset|error result = returnAsset(assetTag, schedule.scheduleId);
        if result is AssetNotFound {
            return <http:NotFound>{body: string `Error returning asset: ${result.message()}`};
        } else if result is ScheduleNotFound {
            return <http:NotFound>{body: string `Error returning asset: ${result.message()}`};
        } else if result is InvalidAssetState {
            return <http:UnprocessableEntity>{body: string `Error returning asset: ${result.message()}`};
        } 
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }
}

service /institutions on httpListener {
    isolated resource function post .(@http:Payload Institution inst) returns http:Conflict|http:InternalServerError|http:Created {
        Institution|error result = addInstitution(inst);
        if result is InstituteExists {
            return <http:Conflict>{body: string `Error adding institution: ${result.message()}`};
        }
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Created>{body: result};
    }
    isolated resource function get .() returns http:Ok|http:InternalServerError|http:NotFound {
        Institution[] result = getAllInstitutions();
        if result.length() == 0 {
            return <http:NotFound>{body: "No institutions found"};
        }

        return <http:Ok>{body: result};
    }
    isolated resource function get [string id]() returns http:Ok|http:InternalServerError|http:NotFound {
        Institution|error result = getInstitution(id);
        if result is InstituteNotFound {
            return <http:NotFound>{body: string `Institution not found: ${id}`};
        } 
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }

    isolated resource function delete [string id]() returns http:Ok|http:InternalServerError|http:Conflict|http:NotFound {
        Institution|error result = removeInstitution(id);
        if result is InstituteNotFound {
            return <http:NotFound>{body: string `Institution not found: ${id}`};
        } else if result is InstitutionInUseError {
            return <http:Conflict>{body: string `Cannot delete institution: ${result.message()}`};
        }
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }

        return <http:Ok>{body: result};
    }
    isolated resource function put [string id](@http:Payload InstitutionUpdate updateInst) returns http:Ok|http:NotFound|http:InternalServerError {
        Institution|error result = updateInstitution(id, updateInst);
        if result is InstituteNotFound {
            return <http:NotFound>{ body: string `Institution not found: ${id}'`};
        }
        if result is error {
            return <http:InternalServerError>{body: {message: result.message()}};
        }
        return <http:Ok>{body: result};
    }
}



// Module initialization block to kick off the clock



// This is a snippet that calculates the due date for a routine service schedule based on the current time and the duration provided in the request payload. It then creates a new Schedule record and attempts to add it to the database. If successful, it returns the updated Asset; otherwise, it returns an error message.

// import ballerina/http;
// import ballerina/time;

// service /library on new http:Listener(9090) {

//     // This resource handles an incoming POST request to schedule service
//     resource function post assets/[string assetTag]/routine\-service(ScheduleRequest payload) returns Asset|http:InternalServerError {
        
//         // --- THIS IS WHERE THE SNIPPET LIVES ---
//         time:Utc now = time:utcNow();
//         // Calculate dynamic deadline (e.g., converting payload days to seconds)
//         decimal durationInSeconds = <decimal>payload.durationInDays * 86400d; 
//         time:Utc targetDueDate = time:utcAdd(now, durationInSeconds);

//         // Assemble the actual database-ready record structure
//         Schedule serviceTicket = {
//             scheduleId: "SCH-" + time:utcNow()[0].toString(), // Unique ID generation
//             scheduleType: ROUTINE_SERVICE,
//             scheduleStatus: PENDING,
//             startTime: now,
//             dueDate: targetDueDate,
//             description: payload.description
//         };

//         // Call your internal isolated function to update the database table
//         Asset|error result = addRoutineServiceSchedule(assetTag, serviceTicket);
        
//         if result is error {
//             return {body: "Database transaction failed: " + result.message()};
//         }
//         return result;
//         // ---------------------------------------
//     }
// }

// // Simple record to catch the incoming user JSON layout
// type ScheduleRequest record {
//     int durationInDays;
//     string description;
// };
