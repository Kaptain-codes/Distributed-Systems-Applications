import ballerina/time;

<<<<<<< HEAD
public isolated function normalizeId(string rawId) returns string {
    return rawId.trim().toUpperAscii();
}

public isolated function normalizeText(string rawText) returns string{
    return rawText.trim();
}

public isolated function isValidDate(string d) returns boolean {
if d.length() != 10 { return false; }

// YOU: check positions 4 and 7 are '-', and that the
// year/month/day substrings parse as ints in range.

return true;   // replace
}

// Whole days between two ISO dates. Checkout day is not a night.
public isolated function nightsBetween(string checkIn, string checkOut)
returns int|error {
time:Utc a = check time:utcFromString(checkIn + "T00:00:00Z");
time:Utc b = check time:utcFromString(checkOut + "T00:00:00Z");
decimal secs = time:utcDiffSeconds(b, a);
return <int>(secs / 86400d);
}

// Two ranges overlap when each starts before the other ends.
// Strict < means a checkout on the 15th does NOT block a
// check-in on the 15th - standard hotel turnover.
public isolated function datesOverlap(string aIn, string aOut,
string bIn, string bOut)
returns boolean {
return aIn < bOut && bIn < aOut;
=======
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
>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876
}