import ballerina/time;

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
}