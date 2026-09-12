// Methods for normalizing and sanitizing incoming data payloads before they touch internal memory.


public isolated function normalizeId(string rawId) returns string {
    return rawId.trim().toUpperAscii();
}


public isolated function normalizeText(string rawText) returns string {
    return rawText.trim();
}

public isolated function normalizeInstitution(Institution rawInst) returns Institution {
    return {
        institutionId: normalizeId(rawInst.institutionId),
        name: normalizeText(rawInst.name)
    };
}

public isolated function normalizeTasks(Task[] rawTasks) returns Task[] {
    Task[] cleaned = [];
    foreach var task in rawTasks {
        cleaned.push({
            taskId: normalizeId(task.taskId),
            description: normalizeText(task.description)
        });
    }
    return cleaned;
}
