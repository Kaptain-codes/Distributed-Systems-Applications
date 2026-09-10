import ballerina/time;


// Database for the application
isolated table<Asset> key(assetTag) assetTable = table [];

isolated table<Institution> key(institutionId) instituteTable = table [];

// ASSET MANAGEMENT FUNCTIONS

# Adds a new asset to the system, after validating that its referenced institution exists.
#
# Known limitation: Ballerina does not permit a single `lock` statement to access more than one
# `isolated` global variable, so `instituteTable` (institution check) and `assetTable`
# (uniqueness check + write) cannot be locked together atomically. This leaves a narrow window
# where another strand could remove the referenced institution between the two checks. This is a
# documented, accepted tradeoff for this in-memory service rather than an oversight — see
# addAsset's implementation for details.
#
# + asset - the asset to add; `assetTag` must be unique and `institutionId` must reference an existing institution
# + return - the stored asset with normalized fields on success, or an `error`
#            (`InstituteNotFound` if the institution doesn't exist, `AssetExists` if the tag is already taken)
public isolated function addAsset(Asset asset) returns Asset|error {
    string cleanTag = normalizeId(asset.assetTag);
    string cleanSite = normalizeText(asset.site);
    string cleanInstId = normalizeId(asset.institutionId);

    lock {
        if assetTable.hasKey(cleanTag) {
            return error AssetExists("", id = cleanTag, reason = "Asset tag already exists");
        }
        Asset stored = asset.clone();
        stored.site = cleanSite;
        stored.name = normalizeText(stored.name);
        stored.description = normalizeText(stored.description);
        stored.institutionId = cleanInstId;
        assetTable.add(stored);
    }

    // Compensate if the institution turned out not to exist
    boolean instValid;
    lock {
        instValid = instituteTable.hasKey(cleanInstId);
    }
    if !instValid {
        lock {
            _ = assetTable.removeIfHasKey(cleanTag);
        }
        return error InstituteNotFound("", id = cleanInstId, reason = "Institution with ID not found");
    }

    lock {
        Asset? stored = assetTable[cleanTag];
        return stored is Asset ? stored.cloneReadOnly() : error("Unexpected state");
    }
}
public isolated function getAsset(string assetTag) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    lock {
        Asset? asset = assetTable[cleanTag];
        if (asset is ()) {
            return error AssetNotFound( "",
                id = assetTag,
                reason = string `Asset tag not found`);
        }
        return asset.cloneReadOnly();
    }
}

public isolated function getAssetsByStatus(AssetStatus status) returns Asset[] & readonly {
    lock {
        Asset[] matches = [];
        foreach var asset in assetTable {
            if asset.status == status {
                matches.push(asset.cloneReadOnly());
            }
        }
        return matches.cloneReadOnly();
    }
}

public isolated function getAllAssets() returns Asset[] & readonly {
    lock {
        return assetTable.toArray().cloneReadOnly();
    }
}

# Updates an existing asset's mutable fields.
#
# Known limitation: same institute/asset cross-table atomicity limitation as `addAsset` — see
# that function's doc comment for the full explanation. When `institutionId` is part of the
# update, existence is verified before the write and re-verified after, with a rollback to the
# prior asset state if the institution was removed during that window.
#
# + assetTag - the asset tag to update
# + assetUpdate - the fields to update; unset (`()`) fields are left unchanged
# + return - the updated asset on success, or an `error`
#            (`AssetNotFound` if the tag doesn't exist, `InstituteNotFound` if the new institutionId is invalid)
public isolated function updateAsset(string assetTag, AssetUpdate assetUpdate) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    AssetUpdate updateCopy = assetUpdate.clone();
    string cleanInstId = "";
    boolean existingInst = false;

    if assetUpdate.institutionId is string {
        cleanInstId = normalizeId(<string>assetUpdate.institutionId);
        lock {
            existingInst = instituteTable.hasKey(cleanInstId);
        }
        if !existingInst {
            return error InstituteNotFound("", id = cleanInstId, reason = "Institution not found");
        }
    }

    Asset & readonly previousAsset;
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if existingAsset is () {
            return error AssetNotFound("", id = cleanTag, reason = string `Asset tag not found`);
        }
        previousAsset = existingAsset.cloneReadOnly();

        Asset updatedAsset = existingAsset.clone();
        if updateCopy.name is string {
            updatedAsset.name = normalizeText(<string>updateCopy.name);
        }
        if updateCopy.description is string {
            updatedAsset.description = normalizeText(<string>updateCopy.description);
        }
        if updateCopy.institutionId is string {
            updatedAsset.institutionId = cleanInstId;
        }
        if updateCopy.site is string {
            updatedAsset.site = normalizeText(<string>updateCopy.site);
        }
        if updateCopy.dateAcquired is string {
            updatedAsset.dateAcquired = normalizeText(<string>updateCopy.dateAcquired);
        }
        if updateCopy.status is AssetStatus {
            updatedAsset.status = <AssetStatus>updateCopy.status;
        }

        assetTable.put(updatedAsset);
    }

    // Compensate if institutionId changed but the institution vanished between the first check and now
    if updateCopy.institutionId is string {
        boolean stillValid;
        lock {
            stillValid = instituteTable.hasKey(cleanInstId);
        }
        if !stillValid {
            lock { // Rollback happening if the changed institute vanished after first verification
                assetTable.put(previousAsset);
            }
            return error InstituteNotFound("", id = cleanInstId, reason = "Institution not found");
        }
    }

    lock {
        Asset? finalAsset = assetTable[cleanTag];
        return finalAsset is Asset ? finalAsset.cloneReadOnly() : error("Unexpected state after update");
    }
}

public isolated function deleteAsset(string assetTag) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }
        Asset removedAsset = assetTable.remove(cleanTag);
        return removedAsset.cloneReadOnly();
    }
}

// INSTITUTION FILTERING FUNCTIONS

public isolated function getAssetsByInstitution(string institutionId) returns Asset[] & readonly {
    lock {
        string searchCode = normalizeId(institutionId);
        Asset[] matches = [];
        foreach var asset in assetTable {
            if asset.institutionId == searchCode {
                matches.push(asset.cloneReadOnly());
            }
        }
        return matches.cloneReadOnly();
    }
}

public isolated function getAssetsBySite(string site) returns Asset[] & readonly {
    lock {
        string standizedSite = normalizeText(site);
        Asset[] matches = [];
        foreach var asset in assetTable {
            if asset.site == standizedSite {
                matches.push(asset.cloneReadOnly());
            }
        }
        return matches.cloneReadOnly();
    }
}

public isolated function getAssetsByFilters(string? institutionId, string? site, AssetStatus? status) returns Asset[] & readonly {
    string? cleanInstitutionId = institutionId is string ? normalizeId(institutionId) : ();
    string? cleanSite = site is string ? normalizeText(site) : ();
    lock {
        Asset[] matches = [];
        foreach var asset in assetTable {
            boolean institutionMatches = cleanInstitutionId is () || asset.institutionId == cleanInstitutionId;
            boolean siteMatches = cleanSite is () || asset.site == cleanSite;
            boolean statusMatches = status is () || asset.status == status;
            if institutionMatches && siteMatches && statusMatches {
                matches.push(asset.cloneReadOnly());
            }
        }
        return matches.cloneReadOnly();
    }
}

// MAINTANANCE AND SCHEDULING FUNCTIONS

// SCHEDULE STATUS MUTATIONS

public isolated function getMaintenanceSchedules(string assetTag) returns Schedule[] & readonly|error {
    string cleanTag = normalizeId(assetTag);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }
        return existingAsset.schedules.cloneReadOnly();
    }
}

public isolated function getMaintenanceSchedule(string assetTag, string scheduleId) returns Schedule|error {
    string cleanTag = normalizeId(assetTag);
    string cleanScheduleId = normalizeId(scheduleId);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }

        foreach var schedule in existingAsset.schedules {
            if schedule.scheduleId == cleanScheduleId {
                return schedule.cloneReadOnly();
            }
        }
        return error(string `Schedule with ID '${scheduleId}' not found for asset '${cleanTag}'`);
    }
}

public isolated function findOverdueAssets() returns Asset[] & readonly {
    lock {
        time:Utc currentTime = time:utcNow(); 
        Asset[] matches = [];
        foreach var asset in assetTable {
            foreach var schedule in asset.schedules {
                if (schedule.scheduleStatus == ACTIVE || schedule.scheduleStatus == PENDING) &&
                    schedule.dueDate < currentTime {
                    matches.push(asset.cloneReadOnly());
                    break;
                }
            }
        }
        return matches.cloneReadOnly();
    }
}
public isolated function scheduleForMaintenance(string assetTag, Schedule schedule) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }
        Schedule scheduleCopy = schedule.clone();
        existingAsset.schedules.push(scheduleCopy);
        existingAsset.status = UNDER_MAINTENANCE;

        assetTable.put(existingAsset);
        return existingAsset.cloneReadOnly();
    }
}


public isolated function addSchedule(string assetTag, Schedule schedule) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    string cleanScheduleId = normalizeId(schedule.scheduleId);
    lock {
        Schedule scheduleCopy = schedule.clone();
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }
        boolean scheduleExists = false;
        foreach var s in existingAsset.schedules {
            if s.scheduleId == cleanScheduleId {
                scheduleExists = true;
                break;
            }
        }
        if scheduleExists {
            return error ScheduleExists("",
            id = scheduleCopy.scheduleId,
            reason = string `Schedule ID already exists on asset '${cleanTag}'`);
        }
        existingAsset.schedules.push(scheduleCopy);
        

        assetTable.put(existingAsset);
        return existingAsset.cloneReadOnly();
    }
}

public isolated function removeSchedule(string assetTag, string scheduleId) returns Schedule|error {
    string cleanTag = normalizeId(assetTag);
    string cleanScheduleId = normalizeId(scheduleId);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }

        int? targetIndex = ();
        foreach var [index, schedule] in existingAsset.schedules.enumerate() {
            if schedule.scheduleId == cleanScheduleId {
                targetIndex = index;
                break; // Exit early the moment we match the ID
            }
        }

        if targetIndex is () {
            return error ScheduleNotFound( "",
                id = cleanScheduleId,
                reason = string `Transaction Rejected: Schedule ID not found for asset '${cleanTag}'.`);
        }

        Schedule removedSchedule = existingAsset.schedules.remove(targetIndex);

        assetTable.put(existingAsset);
        return removedSchedule.cloneReadOnly();
    }
}

public isolated function completeMaintenance(string assetTag, string scheduleId) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    string cleanScheduleId = normalizeId(scheduleId);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }
        boolean scheduleFound = false;

        // Efficient In-Place Mutation Loop
        foreach var schedule in existingAsset.schedules {
            if schedule.scheduleId == cleanScheduleId {
                schedule.scheduleStatus = COMPLETED;
                scheduleFound = true;
                break;
            }
        }


        if !scheduleFound {
            return error ScheduleNotFound( "",
                id = cleanScheduleId,
                reason = string `Transaction Rejected: Schedule ID not found for asset '${cleanTag}'.`);
        }

        existingAsset.status = AVAILABLE;
        
        assetTable.put(existingAsset);
        
        return existingAsset.cloneReadOnly();
    }
}

public isolated function cancelMaintenance(string assetTag, string scheduleId) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    string cleanScheduleId = normalizeId(scheduleId);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }
        boolean scheduleFound = false;

        // Efficient In-Place Mutation Loop
        foreach var schedule in existingAsset.schedules {
            if schedule.scheduleId == cleanScheduleId {
                schedule.scheduleStatus = CANCELLED;
                scheduleFound = true;
                break;
            }
        }

        if !scheduleFound {
            return error ScheduleNotFound( "",
                    id = cleanScheduleId,
                    reason = string `Transaction Rejected: Schedule ID not found for asset '${cleanTag}'.`);
        }

        existingAsset.status = AVAILABLE;
        assetTable.put(existingAsset);
        return existingAsset.cloneReadOnly();
    }
}

// SCHEDULE TYPE MUTATIONS

public isolated function getAssetByRoutineService() returns Asset[] & readonly {
    lock {
        Asset[] matches = [];
        foreach var asset in assetTable {
            foreach var schedule in asset.schedules {
                if schedule.scheduleType == ROUTINE_SERVICE {
                    matches.push(asset.cloneReadOnly());
                    break;
                }
            }
        }
        return matches.cloneReadOnly();
    }
    
}

public isolated function addRoutineServiceSchedule(string assetTag, Schedule schedule) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    string cleanScheduleId = normalizeId(schedule.scheduleId);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound("",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }

        boolean scheduleExists = false;
        foreach var s in existingAsset.schedules {
            if s.scheduleId == cleanScheduleId {
                scheduleExists = true;
                break;
            }
        }

        if scheduleExists {
            return error ScheduleExists("",
                id = cleanScheduleId,
                reason = string `Schedule ID already exists on asset '${cleanTag}'`);
        }

        Schedule defensiveSchedule = schedule.clone();
        defensiveSchedule.scheduleType = ROUTINE_SERVICE;
        existingAsset.schedules.push(defensiveSchedule);

        assetTable.put(existingAsset);
        return existingAsset.cloneReadOnly();
    }
}

// LOANING FUNCTIONS

public isolated function loanAsset(string assetTag, Schedule schedule) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }
        
        // 2. Strict Operational Guards (Fail-Early Validation Engine)
        if existingAsset.status == DISPOSED {
            return error AssetDisposed( 
                "Asset is permanently DISPOSED",
                id = cleanTag,
                reason = string `Transaction Rejected: Asset '${cleanTag}' is permanently decommissioned/disposed.`);
        }
        
        if existingAsset.status == UNDER_MAINTENANCE {
            return error AssetBlocked( "Asset is blocked for maintenance",
                id = cleanTag,
                reason = string `Transaction Rejected: Asset '${cleanTag}' is currently blocked out for maintenance or servicing.`);
        }
        
        if existingAsset.status == OCCUPIED {
            return error AssetOccupied( "Asset is already loaned out",
                id = cleanTag,
                reason = string `Transaction Rejected: Asset '${cleanTag}' is already loaned out or active in an existing session.`);
        }

        Schedule defensiveSchedule = {
            scheduleId: normalizeId(schedule.scheduleId),
            scheduleType: BOOKING,
            scheduleStatus: ACTIVE,
            startTime: schedule.startTime,
            dueDate: schedule.dueDate,
            description: normalizeText(schedule.description)
        };

        existingAsset.schedules.push(defensiveSchedule);
        existingAsset.status = OCCUPIED;

        assetTable.put(existingAsset);
        
        return existingAsset.cloneReadOnly();
    }
}

public isolated function returnAsset(string assetTag, string scheduleId) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    string cleanScheduleId = normalizeId(scheduleId);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }

        if existingAsset.status != OCCUPIED {
            return error InvalidAssetState("",
                id = cleanTag,
                reason = string `Transaction Rejected: Asset '${cleanTag}' cannot be returned because its current status is '${existingAsset.status}'.`);
        }

        boolean scheduleFound = false;

        
        foreach var schedule in existingAsset.schedules {
            if schedule.scheduleId == cleanScheduleId && 
            (schedule.scheduleStatus == ACTIVE || schedule.scheduleStatus == OVERDUE) {
                schedule.scheduleStatus = COMPLETED;
                scheduleFound = true;
                break;
            }
        }

        // 4. Guard against faulty or mismatched transaction data
        if !scheduleFound {
            return error ScheduleNotFound( "",
                id = cleanScheduleId,
                reason = string `Transaction Rejected: Active schedule ID  not found for asset '${cleanTag}'.`);
        }

        // 5. Update parent asset status back to operational inventory bounds
        existingAsset.status = AVAILABLE;

        // 6. Persist changes back to database memory
        assetTable.put(existingAsset);
        
        return existingAsset.cloneReadOnly();
    }
}

// COMPONENT MANAGEMENT

public isolated function getComponents() returns Component[] & readonly {
    lock {
        Component[] matches = [];
        foreach var asset in assetTable {
            foreach var comp in asset.components {
                matches.push(comp.cloneReadOnly());
            }
        }
        return matches.cloneReadOnly();
    }
}

public isolated function addComponentToAsset(string assetTag, Component component) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }

        if existingAsset.status == DISPOSED {
            return error AssetDisposed( "Asset is permanently DISPOSED",
                id = cleanTag,
                reason = string `TRANSACTION REJECTED:Cannot add component to disposed asset '${cleanTag}'.`);
        }
        // Scan the entire database for this component ID
        foreach var asset in assetTable {
            foreach var existingComp in asset.components {
                if existingComp.componentId == component.componentId {
                        return error ComponentExists( "",
                        id = component.componentId,
                        reason = string `Component ID  already exists in the system. Cannot assign this to asset '${cleanTag}'.`);
                }
            }
        }

        Component stored = component.clone();
        existingAsset.components.push(stored);
        assetTable.put(existingAsset);
        
        return existingAsset.cloneReadOnly();
    }
}

public isolated function removeComponentFromAsset(string assetTag, string componentId) returns Component|error {
    string cleanTag = normalizeId(assetTag);
    string cleanComponentId = normalizeId(componentId);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }

        if existingAsset.status == DISPOSED {
            return error AssetDisposed( "Asset is permanently DISPOSED",
                id = cleanTag,
                reason = string `Transaction Rejected: Cannot modify components. Asset '${cleanTag}' is permanently DISPOSED.`);
        }

        int? targetIndex = ();
        foreach var [index, comp] in existingAsset.components.enumerate() {
            if comp.componentId == cleanComponentId {
                targetIndex = index;
                break; // Exit early the moment we match the ID
            }
        }

        if targetIndex is () {
            return error ComponentNotFound( "Component not found",
                id = cleanComponentId,
                reason = string `Component ID not found in asset '${cleanTag}'.`);
        }

        Component removedComponent = existingAsset.components.remove(targetIndex);

        assetTable.put(existingAsset);
        return removedComponent.cloneReadOnly();
    }
}


// WORK ORDERS AND TASK TRACKING

public isolated function addWorkOrder(string assetTag, WorkOrder workOrder) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    string cleanWorkOrderId = normalizeId(workOrder.workOrderId);
    
    lock {
        WorkOrder workOrderCopy = workOrder.clone();
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }
        
        if existingAsset.status == DISPOSED { 
            return error AssetDisposed( "Asset is permanently DISPOSED",
                id  = cleanTag,
                reason = string `Transaction Rejected: Cannot add work order.`);
        }
        
        // GLOBAL UNIQUE GUARD: Sweep all asset schedules to prevent duplicate IDs anywhere in the database
        foreach var asset in assetTable {
            foreach var existingSchedule in asset.schedules {
                if existingSchedule.scheduleId == cleanWorkOrderId {
                    return error WorkOrderAndScheduleExists( "Transaction Rejected: Work Order ID already exists in the system under asset tag.",
                        id = cleanWorkOrderId,
                        reason = string `Transaction Rejected: Work Order ID '${workOrder.workOrderId}' already exists in the system under asset tag '${asset.assetTag}'.`);
                }
            }
        }

        Schedule mappingSchedule = {
            scheduleId: normalizeId(workOrder.workOrderId),
            scheduleType: MAINTENANCE,
            scheduleStatus: PENDING,
            startTime: workOrder.createdAt,
            dueDate: workOrder.createdAt, // Anchored accurately to creation state
            description: normalizeText(workOrder.description)
        };

        
        existingAsset.workOrders.push(workOrderCopy);

        existingAsset.schedules.push(mappingSchedule);
        existingAsset.status = UNDER_MAINTENANCE; // Keep asset state synced with work order intent

        assetTable.put(existingAsset);
        return existingAsset.cloneReadOnly();
    }
}

public isolated function updateWorkOrder(string assetTag, string workOrderId, WorkOrderUpdate workOrderUpdate) returns Asset|error {
    string cleanTag = normalizeId(assetTag);
    string cleanWorkOrderId = normalizeId(workOrderId);
    WorkOrderUpdate workOrderUpdateCopy = workOrderUpdate.clone();

    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }
        boolean workOrderFound = false;

        // Locate and modify the targeted Work Order
        foreach var workOrder in existingAsset.workOrders {
            if workOrder.workOrderId == cleanWorkOrderId {
                
                // Safe mapping using localized nil checking rules
                if workOrderUpdateCopy.description is string {
                    workOrder.description = <string>workOrderUpdateCopy.description;
                }
                if workOrderUpdateCopy.status is WorkOrderStatus {
                    workOrder.status = <WorkOrderStatus>workOrderUpdateCopy.status;

                    if workOrderUpdateCopy.status == CLOSED {
                        foreach var schedule in existingAsset.schedules {
                            if schedule.scheduleId == cleanWorkOrderId {
                                schedule.scheduleStatus = COMPLETED;
                            }
                        }
                    }

                    Schedule[] activeRepairs = [];
                    foreach var schedule in existingAsset.schedules {
                        if (schedule.scheduleType == MAINTENANCE || schedule.scheduleType == ROUTINE_SERVICE) &&
                            (schedule.scheduleStatus == PENDING || schedule.scheduleStatus == ACTIVE || schedule.scheduleStatus == OVERDUE) {
                            activeRepairs.push(schedule);
                        }
                    }

                    if activeRepairs.length() == 0 {
                        existingAsset.status = AVAILABLE;
                    }
                }
                if workOrderUpdateCopy.completedAt is time:Utc {
                    workOrder.completedAt = workOrderUpdateCopy.completedAt;
                }
                if workOrderUpdateCopy.tasks is Task[] {
                    Task[] tasksCopy = (<Task[]>workOrderUpdateCopy.tasks).clone();
                    workOrder.tasks = tasksCopy;
                }
                
                workOrderFound = true;
                break; 
            }
        }

        if !workOrderFound {
            return error WorkOrderNotFound( "",
                id = cleanWorkOrderId,
                reason = string `Work Order ID not found for asset '${cleanTag}'.`);
        }
        assetTable.put(existingAsset);
        return existingAsset.cloneReadOnly();
    }
}

public isolated function completeWorkOrder(string assetTag, string workOrderId) returns WorkOrder|error {
    string cleanTag = normalizeId(assetTag);
    string cleanWorkOrderId = normalizeId(workOrderId);

    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset tag not found`);
        }

        boolean workOrderFound = false;
        WorkOrder? targetWorkOrder = ();
        foreach var workOrder in existingAsset.workOrders {
            if workOrder.workOrderId == cleanWorkOrderId {
                if workOrder.status == CLOSED {
                    return error WorkOrderClosed( "Work Order already closed",
                        id = cleanWorkOrderId,
                        reason = string `Transaction Rejected: Work Order is already CLOSED.`);
                }
                workOrder.status = CLOSED;
                workOrder.completedAt = time:utcNow();
                workOrderFound = true;
                targetWorkOrder = workOrder;
                break;
            }
        }

        if !workOrderFound {
            return error WorkOrderNotFound( "",
                id = cleanWorkOrderId,
                reason = string `Transaction Rejected: Work Order ID not found for asset '${cleanTag}'.`);
        }

        boolean scheduleFound = false;
        foreach var schedule in existingAsset.schedules {
            if schedule.scheduleId == cleanWorkOrderId && schedule.scheduleType == MAINTENANCE {
                schedule.scheduleStatus = COMPLETED;
                scheduleFound = true;
                break;
            }
        }

        // FIXED: was inverted before
        if !scheduleFound {
            return error ScheduleNotFound(
                "",
                id = cleanWorkOrderId,
                reason = string `Transaction Rejected: Schedule ID  not found for Work Order '${cleanWorkOrderId}'.`);
        }

        Schedule[] activeRepairs = [];
        foreach var schedule in existingAsset.schedules {
            if schedule.scheduleType == MAINTENANCE &&
                (schedule.scheduleStatus == PENDING || schedule.scheduleStatus == ACTIVE || schedule.scheduleStatus == OVERDUE) {
                activeRepairs.push(schedule);
            }
        }

        if activeRepairs.length() == 0 {
            existingAsset.status = AVAILABLE;
        }
        assetTable.put(existingAsset);
        WorkOrder finalWorkOrder = <WorkOrder>targetWorkOrder;
        return finalWorkOrder.cloneReadOnly();
    }
}


public isolated function getWorkOrders(string assetTag) returns WorkOrder[] & readonly|error {
    string cleanTag = normalizeId(assetTag);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( "",
                id = cleanTag,
                reason = string `Asset not found`);
        }
        boolean hasWorkOrders = existingAsset.workOrders.length() > 0;
        if !hasWorkOrders {
            return error WorkOrderNotFound( "",
                id = cleanTag,
                reason = string `No work orders found for asset '${cleanTag}'.`);
        }
        return existingAsset.workOrders.cloneReadOnly();
    }
}

public isolated function removeWorkOrder(string assetTag, string workOrderId) returns WorkOrder|error {
    string cleanTag = normalizeId(assetTag);
    string cleanWorkOrderId = normalizeId(workOrderId);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( 
            "",
            id = cleanTag,
            reason = string `Asset with tag '${cleanTag}' not found`);
        }
        int? targetIndex = ();
        
        foreach var [index, workOrder] in existingAsset.workOrders.enumerate() {
            if workOrder.workOrderId == cleanWorkOrderId {
                targetIndex = index;
                break;
            }
        }
        if targetIndex is () {
            return error WorkOrderNotFound( 
            "",
            id = cleanWorkOrderId,
            reason = string `Transaction Rejected: Work Order ID not found for asset '${cleanTag}'.`);
        }
    
        WorkOrder removedWorkOrder = existingAsset.workOrders.remove(<int>targetIndex);
        assetTable.put(existingAsset);
        return removedWorkOrder.cloneReadOnly();

    }
}



// TASK MANAGEMENT FUNCTIONS

public isolated function addTask(string assetTag, string workOrderId, Task task) returns Task|error {
    string cleanTag = normalizeId(assetTag);
    string cleanWorkOrderId = normalizeId(workOrderId);
    string cleanTaskId = normalizeId(task.taskId);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound( 
            "",
            id = cleanTag,
            reason = string `Asset with tag '${cleanTag}' not found`);
        }

        if existingAsset.status == DISPOSED {
            return error AssetDisposed(
                "",
                id = cleanTag,
                reason = string `Transaction Rejected: Cannot add task. Asset is permanently DISPOSED.`);
        }

        boolean workOrderFound = false;
        Task defensiveTask = task.clone();

        foreach var workOrder in existingAsset.workOrders {
            if workOrder.workOrderId == cleanWorkOrderId {
                if workOrder.status == CLOSED {    // ✅ only checks the target
                    return error WorkOrderClosed( "Work Order already closed",
                        id = cleanWorkOrderId,
                        reason = string `Transaction Rejected: Work Order is already CLOSED.`);
                }

                workOrder.tasks.push(defensiveTask);
                workOrderFound = true;
                break;
            }
        }


        foreach var asset in assetTable {
            foreach var workOrder in asset.workOrders {
                foreach var existingTask in workOrder.tasks {
                    if existingTask.taskId == cleanTaskId {
                        return error TaskExists(
                            "",
                            id = cleanTaskId,
                            reason = string `Transaction Rejected: Task ID '${cleanTaskId}' already exists in the system under asset tag '${asset.assetTag}'.`);
                    }
                }
            }
        }

        if !workOrderFound {
            return error WorkOrderNotFound(
                "",
                id = cleanWorkOrderId,
                reason = string `Transaction Rejected: Work Order ID not found for asset '${cleanTag}'.`);
        }

        assetTable.put(existingAsset);
        return defensiveTask.cloneReadOnly();
    }
}

public isolated function removeTask(string assetTag, string workOrderId, string taskId) returns Task|error {
    string cleanTag = normalizeId(assetTag);
    string cleanWorkOrderId = normalizeId(workOrderId);
    string cleanTaskId = normalizeId(taskId);
    lock {
        Asset? existingAsset = assetTable[cleanTag];
        if (existingAsset is ()) {
            return error AssetNotFound(
                "",
                id = cleanTag,
                reason = string `Asset with tag '${cleanTag}' not found`);
        }
        if existingAsset.status == DISPOSED {
            return error AssetDisposed(
                "",
                id = cleanTag,
                reason = string `Transaction Rejected: Cannot remove task. Asset is permanently DISPOSED.`);
        }

        boolean workOrderFound = false;
        Task? deletedTask = ();

        foreach var workOrder in existingAsset.workOrders {
            if workOrder.workOrderId == cleanWorkOrderId {
                if workOrder.status == CLOSED {    // ✅ only checks the target
                    return error WorkOrderClosed( "Work Order already closed",
                        id = cleanWorkOrderId,
                        reason = string `Transaction Rejected: Work Order is already CLOSED.`);
                }

                workOrderFound = true;
                int? targetIndex = ();

                foreach var [index, task] in workOrder.tasks.enumerate() {
                    if task.taskId == cleanTaskId {
                        targetIndex = index;
                        break; 
                    }
                }

                // 4. If found, remove it immediately inside the scope boundary
                if targetIndex is int {
                    deletedTask = workOrder.tasks.remove(targetIndex); // Removed redundant '<int>' casting
                }
                break;
            }
        }

        if !workOrderFound {
            return error WorkOrderNotFound(
                "",
                id = cleanWorkOrderId,
                reason = string `Transaction Rejected: Work Order ID '${cleanWorkOrderId}' not found for asset '${cleanTag}'.`);
        }

        if deletedTask is () {
            return error TaskNotFound(
                "Task has already been removed or does not exist",
                id = cleanTaskId,
                reason = string `Transaction Rejected: Task ID '${cleanTaskId}' not found in Work Order '${cleanWorkOrderId}' for asset '${cleanTag}'.`);
        }

        assetTable.put(existingAsset);
        return deletedTask.cloneReadOnly();
    }
}

// INSTITUTION MANAGEMENT FUNCTIONS

public isolated function addInstitution(Institution inst) returns Institution|error {
    lock {
        Institution instCopy = inst.clone();
        Institution finalizedInst = normalizeInstitution(instCopy);

        if instituteTable.hasKey(finalizedInst.institutionId) {
            return error InstituteExists(
                "",
                id = finalizedInst.institutionId,
                reason = string `Transaction Rejected: Institution abbreviation already exists.`);
        }

        instituteTable.add(finalizedInst);
        return finalizedInst.cloneReadOnly();
    }
}


public isolated function getInstitution(string institutionId) returns Institution|error {
    string cleanId = normalizeId(institutionId);
    lock {
        Institution? institution = instituteTable[cleanId];
        if (institution is ()) {
            return error InstituteNotFound(
                "",
                id = cleanId,
                reason = string `Institution with ID not found`);
        }
        return institution.cloneReadOnly();
    }
}

public isolated function getAllInstitutions() returns Institution[] & readonly{
    lock {
        return instituteTable.toArray().cloneReadOnly();
    }
}

public isolated function updateInstitution(string institutionId, InstitutionUpdate updateInst) returns Institution|error {
    string cleanId = normalizeId(institutionId);
    string newName = normalizeText(updateInst.name);
    // Currently this work but these two locks are atomic if the second fails the first locks changes still occur
    lock {
        Institution? existingInst = instituteTable[cleanId];
        if existingInst is () {
           return error InstituteNotFound(
                "",
                id = cleanId,
                reason = string `Institution with ID not found`);
        }

        Institution localUpdated = existingInst.clone();
        localUpdated.name = newName;
        instituteTable.put(localUpdated);
        return localUpdated.cloneReadOnly();
    }
}

# Removes an institution, provided no assets are currently assigned to it.
#
# Known limitation: same cross-table atomicity limitation as `addAsset` — see that function's
# doc comment for the full explanation. The "no assets assigned" check and the removal can't be
# locked together, so after removing, we re-check for any asset referencing the institution and
# restore it (re-add) if one slipped in during the window.
#
# + institutionId - the institution ID to remove
# + return - the removed institution on success, or an `error`
#            (`InstituteNotFound` if the ID doesn't exist, `InstitutionInUseError` if assets are/became assigned)
public isolated function removeInstitution(string institutionId) returns Institution|error {
    string cleanId = normalizeId(institutionId);
    string institutionName;
    Institution & readonly instSnapshot;

    // Phase 1: Verify institution exists and capture a restorable snapshot
    lock {
        Institution? institution = instituteTable[cleanId];
        if institution is () {
            return error InstituteNotFound("", id = cleanId, reason = "Institution with ID not found");
        }
        institutionName = institution.name;
        instSnapshot = institution.cloneReadOnly();
    }

    // Phase 2: Check ownership/dependencies in asset table
    int ownedCount;
    lock {
        ownedCount = 0;
        foreach var asset in assetTable {
            if asset.institutionId == cleanId {
                ownedCount += 1;
            }
        }
    }
    if ownedCount > 0 {
        return error InstitutionInUseError(
            string `Cannot remove '${institutionName}': ${ownedCount} asset(s) still assigned`,
            institutionName = institutionName,
            ownedCount = ownedCount
        );
    }

    // Phase 3: Remove institution
    Institution? & readonly removed = ();
    lock {
        removed = instituteTable.removeIfHasKey(cleanId).cloneReadOnly();
    }
    if removed is () {
        return error InstituteNotFound("", id = cleanId, reason = "Institution with ID not found");
    }

    // Phase 4: Compensate if an asset was added referencing this institution during the race window
    int postRemovalOwnedCount;
    lock {
        postRemovalOwnedCount = 0;
        foreach var asset in assetTable {
            if asset.institutionId == cleanId {
                postRemovalOwnedCount += 1;
            }
        }
    }
    if postRemovalOwnedCount > 0 {
        lock {
            instituteTable.add(instSnapshot);
        }
        return error InstitutionInUseError(
            string `Cannot remove '${institutionName}': an asset was assigned during removal`,
            institutionName = institutionName,
            ownedCount = postRemovalOwnedCount
        );
    }

    return removed.cloneReadOnly();
}
