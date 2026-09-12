import ballerina/time;

public isolated function calculateNights(string checkIn, string checkOut) returns int|error {
    time:Utc|error t1 = time:utcFromString(checkIn + "T00:00:00Z");
    time:Utc|error t2 = time:utcFromString(checkOut + "T00:00:00Z");
    if t1 is error || t2 is error {
        return error("Invalid date format. Expected YYYY-MM-DD.");
    }
    decimal diffSeconds = <decimal>t2[0] - <decimal>t1[0];
    int days = <int>(diffSeconds / <decimal>86400);
    if days <= 0 {
        return error("Check-out date must be after check-in date.");
    }
    return days;
}

public isolated function nightsBetween(string checkIn, string checkOut) returns int {
    int|error n = calculateNights(checkIn, checkOut);
    return n is error ? 0 : n;
}

public isolated function datesOverlap(string start1, string end1, string start2, string end2) returns boolean {
    return !(end1 <= start2 || start1 >= end2);
}

public isolated function normalizeId(string id) returns string {
    return id.trim().toLowerAscii();
}

public isolated function normalizeText(string text) returns string {
    return text.trim();
}