// Server-only state. Not part of the wire contract - the client
// holds only a cartItemId, so the cart never crosses the network.

public type CartItem record {|
    string cartItemId;
    string guestId;
    string propertyId;
    string checkIn;         // ISO YYYY-MM-DD
    string checkOut;
    int nights;
    decimal estimatedCost;
|};